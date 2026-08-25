import Foundation
import SwiftData

@MainActor
final class CheckRunnerCoordinatorFailureInjection {
    private var failurePoint: CheckRunnerCoordinatorFailurePoint?

    init(failOnceAt failurePoint: CheckRunnerCoordinatorFailurePoint) {
        self.failurePoint = failurePoint
    }

    func removeFailure() {
        failurePoint = nil
    }

    fileprivate func consume(_ point: CheckRunnerCoordinatorFailurePoint) -> Bool {
        guard failurePoint == point else { return false }
        failurePoint = nil
        return true
    }
}

@MainActor
final class CheckRunnerCoordinator {
    private static let pdfTemplateID = "field.evidence.pdf.worklight.v1"
    private static let pdfTemplateVersion = 1
    private static let recheckOutcomes: Set<String> = [
        "resolved",
        "issue_still_visible",
        "original_resolved_different_issue",
        "could_not_verify",
    ]

    private let modelContext: ModelContext
    private let signPack: SignPack
    private let diagnosticsStore: DiagnosticsStore?
    private let storagePreflight: StoragePreflightService
    private let evidenceStoreFailureInjection: EvidenceBundleStoreFailureInjection?
    private let evidenceSaveFailureInjection: CheckRunnerCoordinatorFailureInjection?
    private let finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection?
    private let finalizationServiceFailureInjection: FinalizationServiceFailureInjection?
    private let draftAccessState: (@MainActor () -> DraftAccessNormalizedStateV1)?
    private var captureGenerationRootURL: URL?
    private var evidenceBundleStore: EvidenceBundleStore?
    private var reportDeliveryCoordinator: ReportDeliveryCoordinator?
    private var finalizationAttempt: FinalizationAttempt?
    private var pendingRecheckRequest: (assetID: UUID, issueID: UUID)?

    private struct FinalizationAttempt {
        let assetID: UUID
        let draftID: UUID?
        let selection: CheckOutcomeSelection
        let completedAt: Date
        let snapshotCreatedAt: Date
        let sourceApp: SourceAppSnapshotV1
        let identifiers: FinalizationIdentifiers
    }

    init(
        modelContext: ModelContext,
        signPack: SignPack,
        diagnosticsStore: DiagnosticsStore? = nil,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        evidenceStoreFailureInjection: EvidenceBundleStoreFailureInjection? = nil,
        evidenceSaveFailureInjection: CheckRunnerCoordinatorFailureInjection? = nil,
        finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil,
        finalizationServiceFailureInjection: FinalizationServiceFailureInjection? = nil,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        draftAccessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil
    ) {
        self.modelContext = modelContext
        self.signPack = signPack
        self.diagnosticsStore = diagnosticsStore
        self.evidenceStoreFailureInjection = evidenceStoreFailureInjection
        self.evidenceSaveFailureInjection = evidenceSaveFailureInjection
        self.finalizationStoreFailureInjection = finalizationStoreFailureInjection
        self.finalizationServiceFailureInjection = finalizationServiceFailureInjection
        self.draftAccessState = draftAccessState
        if injectsLowStorageFailureOnceForUITest {
            var shouldFail = true
            self.storagePreflight = StoragePreflightService { _ in
                if shouldFail {
                    shouldFail = false
                    return 0
                }
                return StoragePreflightService.evidenceAcceptanceRequiredBytes
            }
        } else {
            self.storagePreflight = storagePreflight
        }
    }

    var signPackIssueLabels: [SignPack.RegistryEntry] {
        signPack.issueLabels
    }

    var couldNotVerifyReasons: [SignPack.RegistryEntry] {
        validCouldNotVerifyRegistry() ? signPack.couldNotVerifyReasons.entries : []
    }

    func signPackOutcomeDisplay(key: String) -> String? {
        let matches = signPack.outcomeDisplays.filter { $0.key == key }
        return matches.count == 1 ? matches[0].display : nil
    }

    func reviewThumbnailData(for evidence: ReviewEvidence) throws -> Data {
        guard let generationRootURL = captureGenerationRootURL else {
            throw CheckRunnerCoordinatorError.captureNotConfigured
        }
        let root = generationRootURL.standardizedFileURL
        let candidate = root
            .appendingPathComponent(evidence.thumbnailRelativePath)
            .standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              !evidence.thumbnailRelativePath.hasPrefix("/"),
              !evidence.thumbnailRelativePath.contains("..") else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        do {
            return try Data(contentsOf: candidate, options: .mappedIfSafe)
        } catch {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
    }

    func configureCapture(generationRootURL: URL) {
        let standardizedURL = generationRootURL.standardizedFileURL
        guard captureGenerationRootURL != standardizedURL else { return }
        captureGenerationRootURL = standardizedURL
        reportDeliveryCoordinator = nil
        evidenceBundleStore = EvidenceBundleStore(
            generationRootURL: standardizedURL,
            failureInjection: evidenceStoreFailureInjection
        )
    }

    func prepareReview(
        assetID: UUID,
        selection: CheckOutcomeSelection
    ) throws -> FinalizationReview {
        let outcome = try resolvedOutcome(selection)
        let preparation = try prepareCapture(
            assetID: assetID,
            allowsIncompleteReview: outcome.couldNotVerify != nil
        )
        guard outcome.couldNotVerify != nil || preparation.step == .outcome else {
            throw CheckRunnerCoordinatorError.reviewUnavailable
        }
        let draftID = preparation.draftID
        let draftDescriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == draftID }
        )
        guard let draft = try modelContext.fetch(draftDescriptor).first,
              let localDate = draft.localDate,
              let localTime = draft.localTime,
              let timeZoneID = draft.timeZoneID,
              let afterDarkCopy = draft.afterDarkAcknowledgementCopy,
              let safePositionCopy = draft.safePositionAcknowledgementCopy else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let evidenceDescriptor = FetchDescriptor<EvidenceFile>(
            predicate: #Predicate { $0.recordID == draftID }
        )
        let evidence = try modelContext.fetch(evidenceDescriptor)
        let wideRows = evidence.filter { $0.purposeKey == "wide_context" }
        let closeRows = evidence.filter { $0.purposeKey == "close_detail" }
        guard evidence.count == wideRows.count + closeRows.count,
              wideRows.count <= 1,
              closeRows.count <= 1,
              outcome.couldNotVerify != nil || (wideRows.count == 1 && closeRows.count == 1) else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let widePurpose = try capturePurpose(key: "wide_context", index: 0)
        let closePurpose = try capturePurpose(key: "close_detail", index: 1)
        let wide = wideRows.first
        let close = closeRows.first
        return FinalizationReview(
            draftID: draftID,
            outcomeKey: outcome.key,
            outcomeDisplay: outcome.display,
            issueLabelDisplay: outcome.issueLabel?.display,
            wideEvidence: wide.map { reviewEvidence($0, purposeDisplay: widePurpose.display) },
            closeEvidence: close.map { reviewEvidence($0, purposeDisplay: closePurpose.display) },
            couldNotVerifyReasonDisplay: outcome.couldNotVerify?.display,
            note: outcome.note,
            missingPurposeDisplays: [wide == nil ? widePurpose.display : nil, close == nil ? closePurpose.display : nil].compactMap { $0 },
            localDate: localDate,
            localTime: localTime,
            timeZoneID: timeZoneID,
            afterDarkAcknowledgementCopy: afterDarkCopy,
            safePositionAcknowledgementCopy: safePositionCopy
        )
    }

    func valueReceiptDidPresent() async {
        guard let diagnosticsStore else { return }
        let counters = await diagnosticsStore.snapshot()
        guard counters.onboardingCompleted == 0 else { return }
        await diagnosticsStore.increment(.onboardingCompleted)
    }

    func finalize(
        assetID: UUID,
        selection: CheckOutcomeSelection,
        completedAt: Date,
        snapshotCreatedAt: Date,
        sourceApp: SourceAppSnapshotV1,
        identifiers suppliedIdentifiers: FinalizationIdentifiers? = nil
    ) async throws -> FinalizationResult {
        guard let generationRootURL = captureGenerationRootURL else {
            throw CheckRunnerCoordinatorError.finalizationNotConfigured
        }
        let outcome = try resolvedOutcome(selection)
        let currentDraft = try existingDraft(assetID: assetID)
        let currentDraftID = currentDraft?.id
        let suppliedMutationRecord: WorkflowRecord?
        if let suppliedIdentifiers {
            let matches = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
                $0.finalizationMutationID == suppliedIdentifiers.mutationID
            }
            guard matches.count <= 1 else {
                throw CheckRunnerCoordinatorError.finalizationFailed
            }
            suppliedMutationRecord = matches.first
        } else {
            suppliedMutationRecord = nil
        }
        let isRecheck = currentDraft?.stage == WorkflowStage.recheck.rawValue
            || finalizationAttempt?.selection.isRecheck == true
            || suppliedMutationRecord?.stage == WorkflowStage.recheck.rawValue
        let existingIssueID = currentDraft?.issueID
            ?? finalizationAttempt?.identifiers.issueID
            ?? suppliedMutationRecord?.issueID
        let activeAttempt: FinalizationAttempt
        if let suppliedIdentifiers {
            guard isRecheck
                    ? (suppliedIdentifiers.issueID == existingIssueID
                        && (outcome.issueLabel != nil)
                            == (suppliedIdentifiers.newIssueID != nil))
                    : ((outcome.issueLabel != nil)
                        == (suppliedIdentifiers.issueID != nil)
                        && suppliedIdentifiers.newIssueID == nil) else {
                throw CheckRunnerCoordinatorError.issueLabelInvalid
            }
            activeAttempt = FinalizationAttempt(
                assetID: assetID,
                draftID: currentDraftID,
                selection: outcome.selection,
                completedAt: completedAt,
                snapshotCreatedAt: snapshotCreatedAt,
                sourceApp: sourceApp,
                identifiers: suppliedIdentifiers
            )
        } else if let attempt = finalizationAttempt,
                  attempt.assetID == assetID,
                  attempt.selection == outcome.selection,
                  attempt.sourceApp == sourceApp,
                  currentDraftID == nil || attempt.draftID == currentDraftID {
            activeAttempt = attempt
        } else {
            activeAttempt = FinalizationAttempt(
                assetID: assetID,
                draftID: currentDraftID,
                selection: outcome.selection,
                completedAt: completedAt,
                snapshotCreatedAt: snapshotCreatedAt,
                sourceApp: sourceApp,
                identifiers: FinalizationIdentifiers(
                    mutationID: UUID(),
                    packetID: UUID(),
                    stableRootID: UUID(),
                    reportID: UUID(),
                    issueID: isRecheck
                        ? existingIssueID
                        : outcome.issueLabel == nil ? nil : UUID(),
                    newIssueID: isRecheck && outcome.issueLabel != nil ? UUID() : nil
                )
            )
        }
        finalizationAttempt = activeAttempt
        let identifiers = activeAttempt.identifiers
        let asset = try requiredAsset(id: assetID)
        let site = try requiredSite(id: asset.siteID)
        let mutationID = identifiers.mutationID
        let mutationRecords = try modelContext.fetch(
            FetchDescriptor<WorkflowRecord>(
                predicate: #Predicate { $0.finalizationMutationID == mutationID }
            )
        )
        guard mutationRecords.count <= 1 else {
            throw CheckRunnerCoordinatorError.finalizationFailed
        }
        let draft: WorkflowRecord
        if let completed = mutationRecords.first {
            guard completed.assetID == assetID else {
                throw CheckRunnerCoordinatorError.finalizationFailed
            }
            draft = completed
        } else {
            _ = try prepareReview(assetID: assetID, selection: selection)
            guard let existing = try existingDraft(assetID: assetID) else {
                throw CheckRunnerCoordinatorError.captureDraftRequired
            }
            draft = existing
        }
        let draftID = draft.id
        let evidenceDescriptor = FetchDescriptor<EvidenceFile>(
            predicate: #Predicate { $0.recordID == draftID }
        )
        let evidence = try modelContext.fetch(evidenceDescriptor)
        let service: FinalizationService
        do {
            service = try FinalizationService(
                modelContext: modelContext,
                signPack: signPack,
                generationRootURL: generationRootURL,
                intentStoreFailureInjection: finalizationStoreFailureInjection,
                failureInjection: finalizationServiceFailureInjection
            )
        } catch {
            throw CheckRunnerCoordinatorError.finalizationNotConfigured
        }
        let outcomeResult: FinalizationServiceOutcome
        do {
            outcomeResult = try await service.finalize(
                FinalizationServiceInput(
                    draft: draft,
                    asset: asset,
                    site: site,
                    evidence: evidence,
                    outcomeKey: outcome.key,
                    outcomeDisplay: outcome.display,
                    issueLabel: outcome.issueLabel,
                    couldNotVerify: outcome.couldNotVerify,
                    note: outcome.note,
                    completedAt: activeAttempt.completedAt,
                    snapshotCreatedAt: activeAttempt.snapshotCreatedAt,
                    sourceApp: activeAttempt.sourceApp,
                    identifiers: identifiers
                )
            )
        } catch {
            throw CheckRunnerCoordinatorError.finalizationFailed
        }
        let result = outcomeResult.result

        let reportID = result.reportID
        let reportDescriptor = FetchDescriptor<Report>(
            predicate: #Predicate { $0.id == reportID }
        )
        guard try modelContext.fetch(reportDescriptor).count == 1 else {
            throw CheckRunnerCoordinatorError.finalizationFailed
        }
        if outcomeResult.createdAuthority {
            await diagnosticsStore?.increment(.reportSaved)
            if draft.stage == WorkflowStage.recheck.rawValue {
                await diagnosticsStore?.increment(.recheckCompleted)
            }
        }
        finalizationAttempt = nil
        return result
    }

    func makeReportDeliveryCoordinator() throws -> ReportDeliveryCoordinator {
        if let reportDeliveryCoordinator { return reportDeliveryCoordinator }
        guard let generationRootURL = captureGenerationRootURL else {
            throw CheckRunnerCoordinatorError.finalizationNotConfigured
        }
        let coordinator = try ReportDeliveryCoordinator(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            diagnosticsStore: diagnosticsStore,
            signPack: signPack
        )
        reportDeliveryCoordinator = coordinator
        return coordinator
    }

    func prepareReportDelivery(
        result: FinalizationResult
    ) throws -> ReportDeliveryPreparation {
        try makeReportDeliveryCoordinator().prepareFinalizedReport(id: result.reportID)
    }

    func prepareCapture(
        assetID: UUID,
        allowsIncompleteReview: Bool = false
    ) throws -> CapturePreparation {
        guard let draft = try existingDraft(assetID: assetID) else {
            throw CheckRunnerCoordinatorError.captureDraftRequired
        }
        let isCheck = draft.stage == WorkflowStage.check.rawValue
            && draft.issueID == nil
            && draft.parentRecordID == nil
        let isRecheck = draft.stage == WorkflowStage.recheck.rawValue
            && draft.issueID != nil
            && draft.parentRecordID != nil
        guard draft.revisionKind == WorkflowRevisionKind.original.rawValue,
              isCheck || isRecheck,
              draft.state == WorkflowState.draft.rawValue,
              draft.packetID == nil,
              draft.recordRevisionRootID == draft.id,
              draft.revisesRecordID == nil,
              draft.evidenceSourceRecordID == nil,
              draft.completedAt == nil,
              draft.outcomeKey == nil,
              draft.packID == signPack.packID,
              draft.packSchemaVersion == signPack.schemaVersion,
              draft.packContentVersion == signPack.contentVersion,
              draft.finalizationMutationID == nil,
              let stepValue = draft.draftStepKey,
              let step = WorkflowDraftStep(rawValue: stepValue),
              step == .wide || step == .close || step == .outcome else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }

        let draftID = draft.id
        let descriptor = FetchDescriptor<EvidenceFile>(
            predicate: #Predicate { $0.recordID == draftID }
        )
        let evidence = try modelContext.fetch(descriptor)
        let wide = evidence.filter { $0.purposeKey == "wide_context" }
        let close = evidence.filter { $0.purposeKey == "close_detail" }
        guard evidence.count == wide.count + close.count,
              wide.count <= 1,
              close.count <= 1 else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }

        let purpose: SignPack.EvidencePurpose?
        switch step {
        case .wide:
            guard wide.isEmpty, close.isEmpty else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            purpose = try capturePurpose(key: "wide_context", index: 0)
        case .close:
            guard wide.count == 1, close.isEmpty else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            purpose = try capturePurpose(key: "close_detail", index: 1)
        case .outcome:
            guard allowsIncompleteReview
                ? (close.isEmpty || wide.count == 1)
                : (wide.count == 1 && close.count == 1) else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            purpose = nil
        case .review:
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        return CapturePreparation(
            draftID: draft.id,
            step: step,
            purpose: purpose
        )
    }

    func importCandidate(
        assetID: UUID,
        sourceData: Data,
        createdAt: Date
    ) async throws -> CaptureCandidate {
        let preparation = try prepareCapture(assetID: assetID)
        guard let purpose = preparation.purpose else {
            throw CheckRunnerCoordinatorError.captureUnavailable
        }
        guard let generationRootURL = captureGenerationRootURL,
              let evidenceBundleStore else {
            throw CheckRunnerCoordinatorError.captureNotConfigured
        }

        do {
            try storagePreflight.checkEvidenceAcceptance(
                onVolumeContaining: generationRootURL
            )
        } catch {
            throw CheckRunnerCoordinatorError.storageUnavailable
        }

        let normalized: NormalizedMediaV1
        do {
            normalized = try MediaNormalizerV1().normalize(sourceData)
        } catch {
            throw CheckRunnerCoordinatorError.mediaImportFailed
        }

        let evidenceID = UUID()
        let staged: StagedEvidenceBundle
        do {
            staged = try await evidenceBundleStore.stage(
                evidenceID: evidenceID,
                normalized: normalized
            )
        } catch {
            throw CheckRunnerCoordinatorError.mediaImportFailed
        }
        return CaptureCandidate(
            id: evidenceID,
            recordID: preparation.draftID,
            purposeKey: purpose.key,
            createdAt: createdAt,
            previewJPEG: normalized.originalJPEG,
            stagedBundle: staged
        )
    }

    func retake(candidate: CaptureCandidate) async throws {
        guard let evidenceBundleStore else {
            throw CheckRunnerCoordinatorError.captureNotConfigured
        }
        let recordID = candidate.recordID
        let descriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        )
        guard let draft = try modelContext.fetch(descriptor).first else {
            throw CheckRunnerCoordinatorError.captureDraftRequired
        }
        let preparation = try prepareCapture(assetID: draft.assetID)
        guard preparation.draftID == candidate.recordID,
              preparation.purpose?.key == candidate.purposeKey,
              candidate.stagedBundle.evidenceID == candidate.id else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        do {
            try await evidenceBundleStore.discardStaging(
                evidenceID: candidate.id
            )
        } catch {
            throw CheckRunnerCoordinatorError.mediaImportFailed
        }
    }

    @discardableResult
    func accept(
        candidate: CaptureCandidate,
        assetID: UUID
    ) async throws -> EvidenceFile {
        if let replay = try await replayedEvidence(
            candidate: candidate,
            assetID: assetID
        ) {
            return replay
        }
        let preparation = try prepareCapture(assetID: assetID)
        guard preparation.draftID == candidate.recordID,
              preparation.purpose?.key == candidate.purposeKey,
              candidate.stagedBundle.evidenceID == candidate.id,
              let evidenceBundleStore else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }

        let promoted: PromotedEvidenceBundle
        do {
            promoted = try await evidenceBundleStore.promote(
                candidate.stagedBundle
            )
        } catch {
            throw CheckRunnerCoordinatorError.mediaImportFailed
        }

        var draftMutation: (draft: WorkflowRecord, priorStepKey: String?)?
        do {
            let currentPreparation = try prepareCapture(assetID: assetID)
            guard currentPreparation == preparation else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            let draftID = currentPreparation.draftID
            let descriptor = FetchDescriptor<WorkflowRecord>(
                predicate: #Predicate { $0.id == draftID }
            )
            guard let draft = try modelContext.fetch(descriptor).first else {
                throw CheckRunnerCoordinatorError.captureDraftRequired
            }
            draftMutation = (draft, draft.draftStepKey)
            let evidence = EvidenceFile(
                id: candidate.id,
                recordID: candidate.recordID,
                purposeKey: candidate.purposeKey,
                relativePath: promoted.originalRelativePath,
                mimeType: "image/jpeg",
                byteCount: promoted.originalByteCount,
                sha256: promoted.originalSHA256,
                createdAt: candidate.createdAt,
                thumbnailRelativePath: promoted.thumbnailRelativePath,
                thumbnailByteCount: promoted.thumbnailByteCount,
                thumbnailSHA256: promoted.thumbnailSHA256
            )
            modelContext.insert(evidence)
            draft.draftStepKey = preparation.step == .wide
                ? WorkflowDraftStep.close.rawValue
                : WorkflowDraftStep.outcome.rawValue
            if evidenceSaveFailureInjection?.consume(.evidenceModelSave) == true {
                throw CheckRunnerCoordinatorError.saveFailed
            }
            try modelContext.save()
            return evidence
        } catch {
            let saveError = error
            modelContext.rollback()
            if let draftMutation {
                draftMutation.draft.draftStepKey = draftMutation.priorStepKey
            }
            do {
                try await evidenceBundleStore.removePromotedBundleIfOwned(promoted)
            } catch {
                throw CheckRunnerCoordinatorError.cleanupFailed
            }
            if let failure = saveError as? CheckRunnerCoordinatorError {
                throw failure
            }
            throw CheckRunnerCoordinatorError.saveFailed
        }
    }

    private func replayedEvidence(
        candidate: CaptureCandidate,
        assetID: UUID
    ) async throws -> EvidenceFile? {
        guard let evidenceBundleStore else {
            throw CheckRunnerCoordinatorError.captureNotConfigured
        }
        let evidenceID = candidate.id
        let matches = try modelContext.fetch(
            FetchDescriptor<EvidenceFile>(
                predicate: #Predicate { $0.id == evidenceID }
            )
        )
        guard matches.count <= 1 else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        guard let evidence = matches.first else { return nil }

        let recordID = candidate.recordID
        let records = try modelContext.fetch(
            FetchDescriptor<WorkflowRecord>(
                predicate: #Predicate { $0.id == recordID }
            )
        )
        let recordEvidence = try modelContext.fetch(
            FetchDescriptor<EvidenceFile>(
                predicate: #Predicate { $0.recordID == recordID }
            )
        )
        let expectedStep: WorkflowDraftStep
        switch candidate.purposeKey {
        case "wide_context": expectedStep = .close
        case "close_detail": expectedStep = .outcome
        default:
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let staged = candidate.stagedBundle
        let canonicalID = candidate.id.uuidString.lowercased()
        guard records.count == 1,
              let draft = records.first,
              draft.assetID == assetID,
              draft.state == WorkflowState.draft.rawValue,
              draft.draftStepKey == expectedStep.rawValue,
              evidence.recordID == candidate.recordID,
              evidence.purposeKey == candidate.purposeKey,
              evidence.createdAt == candidate.createdAt,
              evidence.mimeType == MediaContractV1.durableMIMEType,
              evidence.relativePath == staged.originalRelativePath,
              evidence.thumbnailRelativePath == staged.thumbnailRelativePath,
              evidence.byteCount == staged.originalByteCount,
              evidence.thumbnailByteCount == staged.thumbnailByteCount,
              evidence.sha256 == staged.originalSHA256,
              evidence.thumbnailSHA256 == staged.thumbnailSHA256,
              staged.evidenceID == candidate.id,
              staged.stagingDirectoryRelativePath
                == ".staging/evidence/\(canonicalID)",
              staged.originalRelativePath
                == "evidence/\(canonicalID)/original.jpg",
              staged.thumbnailRelativePath
                == "evidence/\(canonicalID)/thumbnail.jpg",
              recordEvidence.filter({
                  $0.purposeKey == candidate.purposeKey
              }).count == 1 else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let promoted = PromotedEvidenceBundle(
            evidenceID: staged.evidenceID,
            originalRelativePath: staged.originalRelativePath,
            thumbnailRelativePath: staged.thumbnailRelativePath,
            originalByteCount: staged.originalByteCount,
            thumbnailByteCount: staged.thumbnailByteCount,
            originalSHA256: staged.originalSHA256,
            thumbnailSHA256: staged.thumbnailSHA256
        )
        do {
            guard try await evidenceBundleStore.verifyPromoted(promoted) == promoted else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
        } catch let error as CheckRunnerCoordinatorError {
            throw error
        } catch {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        return evidence
    }

    func prepare(assetID: UUID) throws -> CheckRunnerPreparation {
        let draft = try existingDraft(assetID: assetID)
        if draft != nil {
            pendingRecheckRequest = nil
        }
        let asset = try requiredAsset(id: assetID)
        let site = try requiredSite(id: asset.siteID)
        return CheckRunnerPreparation(
            confirmedTimeZoneID: site.timeZoneID,
            existingDraftID: draft?.id
        )
    }

    func existingDraft(assetID: UUID) throws -> WorkflowRecord? {
        let descriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.assetID == assetID }
        )
        let drafts = try modelContext.fetch(descriptor).filter {
            $0.state == WorkflowState.draft.rawValue
        }
        guard drafts.count <= 1 else {
            throw CheckRunnerCoordinatorError.multipleActiveDrafts
        }
        return drafts.first
    }

    func beginCheck(
        assetID: UUID,
        timeZoneID: String?,
        isTimeZoneConfirmed: Bool,
        afterDarkAccepted: Bool,
        safePositionAccepted: Bool,
        observedAt: Date
    ) throws -> WorkflowRecord {
        let requestedStage: WorkflowStage
        let issueID: UUID?
        if let request = pendingRecheckRequest {
            guard request.assetID == assetID else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            requestedStage = .recheck
            issueID = request.issueID
        } else {
            requestedStage = .check
            issueID = nil
        }
        let draft = try beginOrResumeDraft(
            BeginDraftSubmission(
                assetID: assetID,
                requestedStage: requestedStage,
                issueID: issueID,
                observedAtUTC: observedAt,
                confirmedTimeZoneID: isTimeZoneConfirmed ? timeZoneID : nil,
                afterDarkAccepted: afterDarkAccepted,
                safePositionAccepted: safePositionAccepted
            )
        )
        pendingRecheckRequest = nil
        return draft
    }

    func accessDecision(
        assetID: UUID,
        requestedStage: WorkflowStage,
        issueID: UUID?
    ) throws -> DraftAccessDecisionV1 {
        guard !modelContext.hasChanges else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        guard let requestedEntry = draftAccessEntry(for: requestedStage) else {
            return .blockInvalidRequest
        }
        let gateCheckedAt = Date()
        if let draft = try existingDraft(assetID: assetID) {
            guard draftAccessEntry(for: draft) == requestedEntry,
                  draft.issueID == issueID,
                  let proof = validatedDraftProof(
                    draft,
                    entry: requestedEntry,
                    gateCheckedAt: gateCheckedAt
                  ) else {
                return .blockInvalidRequest
            }
            if let draftAccessState {
                return try evaluateDraftAccess(
                    state: draftAccessState(),
                    entry: requestedEntry,
                    existingDraft: proof
                )
            }
            return .continueExisting
        }

        _ = try requiredAsset(id: assetID)
        _ = try validatedParentRecordID(
            assetID: assetID,
            requestedStage: requestedStage,
            issueID: issueID
        )
        guard let draftAccessState else { return .allow }
        return try evaluateDraftAccess(
            state: draftAccessState(),
            entry: requestedEntry,
            existingDraft: nil
        )
    }

    func requestRecheck(assetID: UUID, issueID: UUID) throws {
        let decision = try accessDecision(
            assetID: assetID,
            requestedStage: .recheck,
            issueID: issueID
        )
        if decision == .continueExisting {
            pendingRecheckRequest = nil
            return
        }
        guard decision == .allow else {
            throw CheckRunnerCoordinatorError.accessDenied(decision)
        }
        pendingRecheckRequest = (assetID, issueID)
    }

    func clearPendingRecheckRequest() {
        pendingRecheckRequest = nil
    }

    func activeDraftStage(assetID: UUID) -> WorkflowStage? {
        guard let draft = try? existingDraft(assetID: assetID) else { return nil }
        return WorkflowStage(rawValue: draft.stage)
    }

    func issueStatus(assetID: UUID, issueID: UUID) throws -> IssueStatus {
        guard !modelContext.hasChanges else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        let issues = try modelContext.fetch(FetchDescriptor<Issue>()).filter {
            $0.id == issueID
        }
        guard issues.count == 1,
              issues[0].schemaVersion == 1,
              issues[0].assetID == assetID,
              let status = IssueStatus(rawValue: issues[0].status) else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return status
    }

    func beginOrResumeDraft(
        assetID: UUID,
        requestedStage: WorkflowStage,
        issueID: UUID?
    ) throws -> WorkflowRecord {
        let decision = try accessDecision(
            assetID: assetID,
            requestedStage: requestedStage,
            issueID: issueID
        )
        if let draft = try existingDraft(assetID: assetID) {
            guard decision == .continueExisting else {
                throw CheckRunnerCoordinatorError.accessDenied(decision)
            }
            return draft
        }

        guard decision == .allow else {
            throw CheckRunnerCoordinatorError.accessDenied(decision)
        }

        let asset = try requiredAsset(id: assetID)
        let parentRecordID = try validatedParentRecordID(
            assetID: assetID,
            requestedStage: requestedStage,
            issueID: issueID
        )

        guard requestedStage == .work else {
            throw CheckRunnerCoordinatorError.acknowledgementsRequired
        }

        return try createDraft(
            asset: asset,
            requestedStage: requestedStage,
            issueID: issueID,
            parentRecordID: parentRecordID,
            timeContext: nil,
            acknowledgementSnapshots: nil,
            startedAt: Date()
        )
    }

    func beginOrResumeDraft(
        _ submission: BeginDraftSubmission
    ) throws -> WorkflowRecord {
        let decision = try accessDecision(
            assetID: submission.assetID,
            requestedStage: submission.requestedStage,
            issueID: submission.issueID
        )
        if let draft = try existingDraft(assetID: submission.assetID) {
            guard decision == .continueExisting else {
                throw CheckRunnerCoordinatorError.accessDenied(decision)
            }
            return draft
        }


        guard decision == .allow else {
            throw CheckRunnerCoordinatorError.accessDenied(decision)
        }

        let asset = try requiredAsset(id: submission.assetID)
        let parentRecordID = try validatedParentRecordID(
            assetID: submission.assetID,
            requestedStage: submission.requestedStage,
            issueID: submission.issueID
        )

        switch submission.requestedStage {
        case .work:
            return try createDraft(
                asset: asset,
                requestedStage: .work,
                issueID: submission.issueID,
                parentRecordID: parentRecordID,
                timeContext: nil,
                acknowledgementSnapshots: nil,
                startedAt: submission.observedAtUTC ?? Date()
            )

        case .check, .recheck:
            guard submission.afterDarkAccepted,
                  submission.safePositionAccepted else {
                throw CheckRunnerCoordinatorError.acknowledgementsRequired
            }
            guard let observedAtUTC = submission.observedAtUTC else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }

            let acknowledgementSnapshots = try acknowledgementSnapshots(for: asset)
            let timeZoneResolution = try resolvedTimeZone(
                asset: asset,
                proposedTimeZoneID: submission.confirmedTimeZoneID
            )
            let timeContext: FrozenTimeContext
            do {
                timeContext = try TimeContextRule.freeze(
                    observedAtUTC: observedAtUTC,
                    confirmedTimeZoneID: timeZoneResolution.timeZoneID
                )
            } catch TimeContextRuleError.invalidTimeZoneID {
                throw CheckRunnerCoordinatorError.invalidTimeZoneID
            }
            try persistConfirmedTimeZoneIfNeeded(
                timeZoneResolution,
                confirmedAt: observedAtUTC
            )

            return try createDraft(
                asset: asset,
                requestedStage: submission.requestedStage,
                issueID: submission.issueID,
                parentRecordID: parentRecordID,
                timeContext: timeContext,
                acknowledgementSnapshots: acknowledgementSnapshots,
                startedAt: observedAtUTC
            )
        }
    }

    private func evaluateDraftAccess(
        state: DraftAccessNormalizedStateV1,
        entry: DraftAccessEntryV1,
        existingDraft: RepositoryValidatedDraftV1?
    ) throws -> DraftAccessDecisionV1 {
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        guard Set(assets.map(\.id)).count == assets.count,
              assets.allSatisfy({
                $0.schemaVersion == 1
                    && $0.updatedAt >= $0.createdAt
                    && !$0.label.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
              }),
              Set(packets.map(\.id)).count == packets.count,
              Set(packets.map(\.stableRootID)).count == packets.count,
              packets.allSatisfy({ packet in
                guard packet.schemaVersion == 1 else { return false }
                if packet.currentRecordID == nil {
                    return packet.contentDeletedAt.map {
                        $0 >= packet.createdAt
                    } ?? false
                }
                return packet.contentDeletedAt == nil
              }) else {
            return .blockInvalidRequest
        }
        return DraftAccessPolicy.evaluate(
            DraftAccessPolicyInputV1(
                accessState: state,
                liveAssetCount: assets.count,
                countedStableRootIDs: Set(
                    packets.lazy
                        .filter(\.evaluationCounted)
                        .map(\.stableRootID)
                ),
                requestedEntry: entry,
                existingDraft: existingDraft
            )
        )
    }

    private func draftAccessEntry(
        for stage: WorkflowStage
    ) -> DraftAccessEntryV1? {
        switch stage {
        case .check: return .check
        case .work: return .work
        case .recheck: return .recheck
        }
    }

    private func draftAccessEntry(
        for draft: WorkflowRecord
    ) -> DraftAccessEntryV1? {
        guard let stage = WorkflowStage(rawValue: draft.stage) else {
            return nil
        }
        return draftAccessEntry(for: stage)
    }

    private func validatedDraftProof(
        _ draft: WorkflowRecord,
        entry: DraftAccessEntryV1,
        gateCheckedAt: Date
    ) -> RepositoryValidatedDraftV1? {
        guard draft.schemaVersion == 1,
              draft.state == WorkflowState.draft.rawValue,
              draft.revisionKind == WorkflowRevisionKind.original.rawValue,
              draft.recordRevisionRootID == draft.id,
              draft.packetID == nil,
              draft.revisesRecordID == nil,
              draft.evidenceSourceRecordID == nil,
              draft.completedAt == nil,
              draft.outcomeKey == nil,
              draft.finalizationMutationID == nil,
              draft.startedAt < gateCheckedAt,
              let asset = try? requiredAsset(id: draft.assetID),
              asset.packID == draft.packID,
              asset.packSchemaVersion == draft.packSchemaVersion,
              asset.packContentVersion == draft.packContentVersion else {
            return nil
        }

        switch entry {
        case .check:
            guard draft.stage == WorkflowStage.check.rawValue,
                  draft.issueID == nil,
                  draft.parentRecordID == nil else {
                return nil
            }
        case .work, .recheck:
            guard draft.stage == entry.rawValue,
                  let issueID = draft.issueID,
                  let requestedStage = WorkflowStage(rawValue: draft.stage),
                  let expectedParent = try? validatedParentRecordID(
                    assetID: draft.assetID,
                    requestedStage: requestedStage,
                    issueID: issueID
                  ),
                  draft.parentRecordID == expectedParent else {
                return nil
            }
            let issues = (try? modelContext.fetch(FetchDescriptor<Issue>()))?
                .filter { $0.id == issueID } ?? []
            guard issues.count == 1,
                  issues[0].schemaVersion == 1,
                  issues[0].assetID == draft.assetID,
                  issues[0].updatedAt <= draft.startedAt else {
                return nil
            }
        case .createSign:
            return nil
        }

        return RepositoryValidatedDraftV1(
            draftID: draft.id,
            assetID: draft.assetID,
            issueID: draft.issueID,
            entry: entry,
            createdAt: draft.startedAt,
            gateCheckedAt: gateCheckedAt
        )
    }

    private func requiredAsset(id: UUID) throws -> Asset {
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == id }
        )
        let assets = try modelContext.fetch(descriptor)
        guard assets.count == 1, let asset = assets.first else {
            throw CheckRunnerCoordinatorError.assetNotFound
        }
        return asset
    }

    private func requiredSite(id: UUID) throws -> Site {
        let descriptor = FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == id }
        )
        let sites = try modelContext.fetch(descriptor)
        guard sites.count == 1, let site = sites.first else {
            throw CheckRunnerCoordinatorError.siteNotFound
        }
        return site
    }

    private func resolvedTimeZone(
        asset: Asset,
        proposedTimeZoneID: String?
    ) throws -> TimeZoneResolution {
        let site = try requiredSite(id: asset.siteID)

        if let storedTimeZoneID = site.timeZoneID {
            guard TimeZone.knownTimeZoneIdentifiers.contains(storedTimeZoneID),
                  TimeZone(identifier: storedTimeZoneID) != nil else {
                throw CheckRunnerCoordinatorError.invalidTimeZoneID
            }
            return TimeZoneResolution(
                site: site,
                timeZoneID: storedTimeZoneID,
                requiresSave: false
            )
        }

        guard let proposedTimeZoneID else {
            throw CheckRunnerCoordinatorError.timeZoneConfirmationRequired
        }
        let normalizedTimeZoneID = proposedTimeZoneID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard TimeZone.knownTimeZoneIdentifiers.contains(normalizedTimeZoneID),
              TimeZone(identifier: normalizedTimeZoneID) != nil else {
            throw CheckRunnerCoordinatorError.invalidTimeZoneID
        }

        return TimeZoneResolution(
            site: site,
            timeZoneID: normalizedTimeZoneID,
            requiresSave: true
        )
    }

    private func persistConfirmedTimeZoneIfNeeded(
        _ resolution: TimeZoneResolution,
        confirmedAt: Date
    ) throws {
        guard resolution.requiresSave else { return }

        resolution.site.timeZoneID = resolution.timeZoneID
        resolution.site.updatedAt = confirmedAt
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw CheckRunnerCoordinatorError.saveFailed
        }

        let siteID = resolution.site.id
        let descriptor = FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        )
        guard let persistedSite = try? modelContext.fetch(descriptor),
              persistedSite.count == 1,
              persistedSite.first?.timeZoneID == resolution.timeZoneID else {
            throw CheckRunnerCoordinatorError.saveFailed
        }
    }

    private func validatedParentRecordID(
        assetID: UUID,
        requestedStage: WorkflowStage,
        issueID: UUID?
    ) throws -> UUID? {
        switch requestedStage {
        case .check:
            guard issueID == nil else {
                throw CheckRunnerCoordinatorError.issueNotAllowed
            }
            return nil

        case .work, .recheck:
            guard let issueID else {
                throw CheckRunnerCoordinatorError.issueRequired
            }
            let issue = try requiredIssue(id: issueID)
            guard issue.assetID == assetID else {
                throw CheckRunnerCoordinatorError.issueAssetMismatch
            }

            let requiredStatus: IssueStatus = requestedStage == .work
                ? .open
                : .recheckDue
            guard issue.status == requiredStatus.rawValue else {
                throw CheckRunnerCoordinatorError.issueStateMismatch
            }
            return try latestCompletedSubstantiveRecordID(
                assetID: assetID,
                issue: issue
            )
        }
    }

    private func requiredIssue(id: UUID) throws -> Issue {
        let descriptor = FetchDescriptor<Issue>(
            predicate: #Predicate { $0.id == id }
        )
        let issues = try modelContext.fetch(descriptor)
        guard issues.count == 1, let issue = issues.first else {
            throw CheckRunnerCoordinatorError.issueNotFound
        }
        return issue
    }

    private func latestCompletedSubstantiveRecordID(
        assetID: UUID,
        issue: Issue
    ) throws -> UUID {
        let descriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.assetID == assetID }
        )
        let records = try modelContext.fetch(descriptor).filter {
            $0.state == WorkflowState.completed.rawValue
                && $0.revisionKind == WorkflowRevisionKind.original.rawValue
        }

        guard !records.isEmpty else {
            throw CheckRunnerCoordinatorError.parentRecordMissing
        }
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        guard recordsByID.count == records.count,
              let openingRecord = recordsByID[issue.openedByRecordID],
              openingRecord.completedAt != nil,
              openingRecord.finalizationMutationID != nil else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        let opensOrdinaryIssue = openingRecord.parentRecordID == nil
            && openingRecord.stage == WorkflowStage.check.rawValue
            && openingRecord.outcomeKey == "visible_issue"
            && openingRecord.issueID == issue.id
        let opensDifferentIssue: Bool
        if let originalIssueID = openingRecord.issueID,
           originalIssueID != issue.id,
           openingRecord.stage == WorkflowStage.recheck.rawValue,
           openingRecord.outcomeKey == "original_resolved_different_issue" {
            let originalIssue = try requiredIssue(id: originalIssueID)
            guard originalIssue.assetID == assetID,
                  originalIssue.status == IssueStatus.resolved.rawValue,
                  originalIssue.resolvedByRecordID == openingRecord.id else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            opensDifferentIssue = try ordinaryIssueChainTerminal(
                assetID: assetID,
                issue: originalIssue,
                records: records,
                recordsByID: recordsByID
            ).id == openingRecord.id
        } else {
            opensDifferentIssue = false
        }
        guard opensOrdinaryIssue || opensDifferentIssue else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        if opensOrdinaryIssue {
            return try ordinaryIssueChainTerminal(
                assetID: assetID,
                issue: issue,
                records: records,
                recordsByID: recordsByID
            ).id
        }

        let issueRecords = records.filter { $0.issueID == issue.id }
        var visitedIssueRecords: Set<UUID> = []
        var current = openingRecord
        while true {
            let children = issueRecords.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            guard let child = children.first else {
                break
            }
            guard visitedIssueRecords.insert(child.id).inserted,
                  child.issueID == issue.id,
                  child.assetID == assetID,
                  child.completedAt != nil,
                  child.finalizationMutationID != nil,
                  (child.stage == WorkflowStage.work.rawValue
                    && child.outcomeKey == "work_recorded")
                    || (child.stage == WorkflowStage.recheck.rawValue
                    && Self.recheckOutcomes.contains(child.outcomeKey ?? "")) else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            current = child
        }

        guard visitedIssueRecords.count == issueRecords.count else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return current.id
    }

    private func ordinaryIssueChainTerminal(
        assetID: UUID,
        issue: Issue,
        records: [WorkflowRecord],
        recordsByID: [UUID: WorkflowRecord]
    ) throws -> WorkflowRecord {
        guard let openingRecord = recordsByID[issue.openedByRecordID],
              openingRecord.assetID == assetID,
              openingRecord.issueID == issue.id,
              openingRecord.parentRecordID == nil,
              openingRecord.stage == WorkflowStage.check.rawValue,
              openingRecord.outcomeKey == "visible_issue",
              openingRecord.completedAt != nil,
              openingRecord.finalizationMutationID != nil else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        let issueRecords = records.filter { $0.issueID == issue.id }
        var visited: Set<UUID> = [openingRecord.id]
        var current = openingRecord
        while true {
            let children = issueRecords.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            guard let child = children.first else { break }
            guard visited.insert(child.id).inserted,
                  child.assetID == assetID,
                  child.completedAt != nil,
                  child.finalizationMutationID != nil,
                  (child.stage == WorkflowStage.work.rawValue
                    && child.outcomeKey == "work_recorded")
                    || (child.stage == WorkflowStage.recheck.rawValue
                    && Self.recheckOutcomes.contains(child.outcomeKey ?? "")) else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            current = child
        }

        guard visited.count == issueRecords.count else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return current
    }

    private func acknowledgementSnapshots(for asset: Asset) throws -> (
        afterDark: SignPack.Acknowledgement,
        safePosition: SignPack.Acknowledgement
    ) {
        guard signPack.packID == asset.packID,
              signPack.schemaVersion == asset.packSchemaVersion,
              signPack.contentVersion == asset.packContentVersion,
              signPack.acknowledgements.count == 2,
              signPack.acknowledgements[0].key == "after_dark",
              signPack.acknowledgements[1].key == "safe_authorized_position" else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return (
            afterDark: signPack.acknowledgements[0],
            safePosition: signPack.acknowledgements[1]
        )
    }

    private func capturePurpose(
        key: String,
        index: Int
    ) throws -> SignPack.EvidencePurpose {
        guard signPack.evidencePurposes.count == 3,
              signPack.evidencePurposes.indices.contains(index),
              signPack.evidencePurposes[index].key == key else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        return signPack.evidencePurposes[index]
    }

    private func resolvedOutcome(
        _ selection: CheckOutcomeSelection
    ) throws -> (
        key: String,
        display: String,
        issueLabel: SignPack.RegistryEntry?,
        couldNotVerify: SignPack.RegistryEntry?,
        note: String?,
        selection: CheckOutcomeSelection
    ) {
        let key: String
        let issueLabel: SignPack.RegistryEntry?
        let couldNotVerify: SignPack.RegistryEntry?
        let note: String?
        let normalizedSelection: CheckOutcomeSelection
        switch selection {
        case .noVisibleIssue:
            key = "no_visible_issue"
            issueLabel = nil
            couldNotVerify = nil
            note = nil
            normalizedSelection = .noVisibleIssue
        case let .visibleIssue(labelKey):
            let normalizedKey = labelKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalizedKey.isEmpty else {
                throw CheckRunnerCoordinatorError.issueLabelRequired
            }
            guard let selected = signPack.issueLabels.first(where: {
                $0.key == normalizedKey
            }), signPack.issueLabels.filter({ $0.key == normalizedKey }).count == 1 else {
                throw CheckRunnerCoordinatorError.issueLabelInvalid
            }
            key = "visible_issue"
            issueLabel = selected
            couldNotVerify = nil
            note = nil
            normalizedSelection = .visibleIssue(labelKey: normalizedKey)
        case let .couldNotVerify(reasonKey, rawNote):
            let normalizedKey = reasonKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard reasonKey == normalizedKey,
                  !normalizedKey.isEmpty,
                  validCouldNotVerifyRegistry(),
                  let selected = signPack.couldNotVerifyReasons.entries.first(where: { $0.key == normalizedKey }) else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            let trimmed = rawNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedNote = trimmed.flatMap { $0.isEmpty ? nil : $0 }
            guard rawNote.map({ $0.isEmpty || $0 == trimmed }) ?? true,
                  normalizedNote.map({ (1...1000).contains($0.count) }) ?? true else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            key = "could_not_verify"
            issueLabel = nil
            couldNotVerify = selected
            note = normalizedNote
            normalizedSelection = .couldNotVerify(reasonKey: selected.key, note: normalizedNote)
        case let .resolved(rawNote):
            let normalizedNote = try normalizedRecheckNote(rawNote)
            key = "resolved"
            issueLabel = nil
            couldNotVerify = nil
            note = normalizedNote
            normalizedSelection = .resolved(note: normalizedNote)
        case let .issueStillVisible(rawNote):
            let normalizedNote = try normalizedRecheckNote(rawNote)
            key = "issue_still_visible"
            issueLabel = nil
            couldNotVerify = nil
            note = normalizedNote
            normalizedSelection = .issueStillVisible(note: normalizedNote)
        case let .originalResolvedDifferentIssue(labelKey, rawNote):
            let normalizedKey = labelKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard labelKey == normalizedKey,
                  !normalizedKey.isEmpty,
                  let selected = signPack.issueLabels.first(where: {
                      $0.key == normalizedKey
                  }),
                  signPack.issueLabels.filter({ $0.key == normalizedKey }).count == 1 else {
                throw CheckRunnerCoordinatorError.issueLabelInvalid
            }
            let normalizedNote = try normalizedRecheckNote(rawNote)
            key = "original_resolved_different_issue"
            issueLabel = selected
            couldNotVerify = nil
            note = normalizedNote
            normalizedSelection = .originalResolvedDifferentIssue(
                labelKey: normalizedKey,
                note: normalizedNote
            )
        }
        guard let display = signPack.outcomeDisplays.first(where: {
            $0.key == key
        })?.display,
              signPack.outcomeDisplays.filter({ $0.key == key }).count == 1 else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return (key, display, issueLabel, couldNotVerify, note, normalizedSelection)
    }

    private func normalizedRecheckNote(_ value: String?) throws -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        guard value.map({ $0.isEmpty || $0 == trimmed }) ?? true,
              normalized.map({ (1...1000).contains($0.count) }) ?? true else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return normalized
    }

    private func validCouldNotVerifyRegistry() -> Bool {
        signPack.couldNotVerifyReasons.version == "cnv.reason.en-US.v1"
            && signPackOutcomeDisplay(key: "could_not_verify") == "Could not verify"
            && signPack.couldNotVerifyReasons.entries == [
                .init(key: "conditions_changed", display: "Conditions changed"),
                .init(key: "access_lost", display: "I lost safe access"),
                .init(key: "unsafe_to_continue", display: "It became unsafe to continue"),
                .init(key: "required_view_obstructed", display: "Required view is blocked"),
                .init(key: "capture_unavailable", display: "Camera or photo capture is unavailable"),
                .init(key: "other", display: "Another reason"),
            ]
    }

    private func reviewEvidence(
        _ evidence: EvidenceFile,
        purposeDisplay: String
    ) -> ReviewEvidence {
        ReviewEvidence(
            id: evidence.id,
            purposeKey: evidence.purposeKey,
            purposeDisplay: purposeDisplay,
            thumbnailRelativePath: evidence.thumbnailRelativePath
        )
    }

    private func createDraft(
        asset: Asset,
        requestedStage: WorkflowStage,
        issueID: UUID?,
        parentRecordID: UUID?,
        timeContext: FrozenTimeContext?,
        acknowledgementSnapshots: (
            afterDark: SignPack.Acknowledgement,
            safePosition: SignPack.Acknowledgement
        )?,
        startedAt: Date
    ) throws -> WorkflowRecord {
        guard signPack.packID == asset.packID,
              signPack.schemaVersion == asset.packSchemaVersion,
              signPack.contentVersion == asset.packContentVersion else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        let id = UUID()
        let draft = WorkflowRecord(
            id: id,
            assetID: asset.id,
            packetID: nil,
            issueID: issueID,
            parentRecordID: parentRecordID,
            recordRevisionRootID: id,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: requestedStage,
            state: .draft,
            draftStepKey: requestedStage == .work ? nil : .wide,
            startedAt: startedAt,
            completedAt: nil,
            observedAtUTC: timeContext?.observedAtUTC,
            timeZoneID: timeContext?.timeZoneID,
            utcOffsetMinutes: timeContext?.utcOffsetMinutes,
            localDate: timeContext?.localDate,
            localTime: timeContext?.localTime,
            afterDarkAcknowledgementKey: acknowledgementSnapshots?.afterDark.key,
            afterDarkAcknowledgementCopy: acknowledgementSnapshots?.afterDark.copy,
            afterDarkAcknowledgementVersion: acknowledgementSnapshots?.afterDark.version,
            afterDarkAcknowledgementAccepted: acknowledgementSnapshots == nil ? nil : true,
            safePositionAcknowledgementKey: acknowledgementSnapshots?.safePosition.key,
            safePositionAcknowledgementCopy: acknowledgementSnapshots?.safePosition.copy,
            safePositionAcknowledgementVersion: acknowledgementSnapshots?.safePosition.version,
            safePositionAcknowledgementAccepted: acknowledgementSnapshots == nil ? nil : true,
            packID: asset.packID,
            packSchemaVersion: asset.packSchemaVersion,
            packContentVersion: asset.packContentVersion,
            pdfTemplateID: Self.pdfTemplateID,
            pdfTemplateVersion: Self.pdfTemplateVersion,
            outcomeKey: nil,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: nil,
            finalizationMutationID: nil
        )

        modelContext.insert(draft)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw CheckRunnerCoordinatorError.saveFailed
        }
        return draft
    }
}

private extension CheckOutcomeSelection {
    var isRecheck: Bool {
        switch self {
        case .resolved, .issueStillVisible, .originalResolvedDifferentIssue: true
        default: false
        }
    }
}

private struct TimeZoneResolution {
    let site: Site
    let timeZoneID: String
    let requiresSave: Bool
}

import Foundation

enum CheckRunnerScheduleCoordinatorBoundaryV1 { static let checkRunnerMayAutoStartOccurrence = false }

enum C51CheckRunnerScheduleCoordinatorBoundaryV1 {
    static let checkRunnerMayAutoStartOccurrence = false
    static let scheduleClosureMetadataIsDerivedOnly = true
    static let coordinatorOwnsNoOccurrenceWriter = true

    static func validate(_ metadata: C51CheckRunnerScheduleMetadataV1) throws {
        try metadata.validate()
    }
}

extension CheckRunnerCoordinator {
    /// Produces capture context only. The existing explicit draft/start path
    /// remains the sole authority to start work.
    func prepareResolvedAssetLocator(
        resolution: LocatorResolutionV1,
        locator: AssetLocatorV1,
        receipt: LocatorBindingReceiptV1
    ) throws -> CheckRunnerAssetLocatorContextV1 {
        try CheckRunnerAssetLocatorContextV1(
            resolution: resolution, locator: locator, receipt: receipt
        )
    }
}

extension CheckRunnerCoordinator {
    /// Resolution/preview only. The caller must invoke the existing explicit
    /// Start action before any render job is enqueued or workspace mutation made.
    func prepareAssetLabelPreview(
        plan: AssetLabelGenerationPlanV1,
        input: CheckRunnerAssetLabelInputV1
    ) throws -> CheckRunnerAssetLabelPreviewV1 {
        try CheckRunnerAssetLabelPreviewV1(plan: plan, input: input)
    }
}
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

extension CheckRunnerCoordinator {
    func validateSurveyResume(_ context:CheckRunnerSurveySessionContextV1)throws{try context.validate();guard [.draft,.paused,.reviewRequired,.amended].contains(context.session.state)else{throw CheckRunnerCoordinatorError.workPacketStaleRevision}}
    func validateSurveyPublication(_ publication:SurveyPublicationSnapshotV1,context:CheckRunnerSurveySessionContextV1)throws{try context.validate();try publication.validate(session:context.session,definition:context.definition,captures:context.captures)}
}

@MainActor
final class CheckRunnerCoordinator {
    private enum MutationRoute {
        case live(
            WorkspacePackageLifecycleDependenciesV1,
            WorkspacePackageLifecycleProfileV1
        )
        case expiringCompatibility(
            WorkspaceWriterAdapterV1,
            any ApplicationFileAuthorityV1,
            CheckRunnerCompatibilityPostureV1
        )
    }

    private let modelContext: ModelContext
    private let mutationRoute: MutationRoute
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let signPack: SignPack
    private let diagnosticsStore: DiagnosticsStore?
    private let storagePreflight: StoragePreflightService
    private let evidenceStoreFailureInjection: EvidenceBundleStoreFailureInjection?
    private let evidenceSaveFailureInjection: CheckRunnerCoordinatorFailureInjection?
    private let finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection?
    private let finalizationServiceFailureInjection: FinalizationServiceFailureInjection?
    private let draftAccessState: (@MainActor () -> DraftAccessNormalizedStateV1)?
    private let requirementEvaluatorRegistry: RequirementEvaluatorRegistryV1?
    private let offMainWorker = DeterministicOffMainWorkerV1()
    private var captureGenerationRootURL: URL?
    private var evidenceBundleStore: EvidenceBundleStore?
    private var reportDeliveryCoordinator: ReportDeliveryCoordinator?
    private var finalizationAttempt: FinalizationAttempt?
    private var pendingRecheckRequest: (assetID: UUID, issueID: UUID)?

    private var liveLifecycle: (
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        profile: WorkspacePackageLifecycleProfileV1
    )? {
        guard case let .live(dependencies, profile) = mutationRoute else { return nil }
        return (dependencies, profile)
    }

    private var fileAuthority: any ApplicationFileAuthorityV1 {
        switch mutationRoute {
        case let .live(dependencies, _): dependencies.fileAuthority
        case let .expiringCompatibility(_, authority, _): authority
        }
    }

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
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1(),
        diagnosticsStore: DiagnosticsStore? = nil,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        evidenceStoreFailureInjection: EvidenceBundleStoreFailureInjection? = nil,
        evidenceSaveFailureInjection: CheckRunnerCoordinatorFailureInjection? = nil,
        finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil,
        finalizationServiceFailureInjection: FinalizationServiceFailureInjection? = nil,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        requirementEvaluatorRegistry: RequirementEvaluatorRegistryV1? = nil,
        draftAccessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil,
        compatibilityPosture: CheckRunnerCompatibilityPostureV1 = .frozenS10CallersOnly
    ) {
        self.modelContext = modelContext
        self.mutationRoute = .expiringCompatibility(
            WorkspaceWriterAdapterV1(modelContext: modelContext),
            fileAuthority,
            compatibilityPosture
        )
        self.clock = clock
        self.idSource = idSource
        self.signPack = signPack
        self.diagnosticsStore = diagnosticsStore
        self.evidenceStoreFailureInjection = evidenceStoreFailureInjection
        self.evidenceSaveFailureInjection = evidenceSaveFailureInjection
        self.finalizationStoreFailureInjection = finalizationStoreFailureInjection
        self.finalizationServiceFailureInjection = finalizationServiceFailureInjection
        self.draftAccessState = draftAccessState
        self.requirementEvaluatorRegistry = requirementEvaluatorRegistry
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

    init(
        modelContext: ModelContext,
        packageLifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        packageLifecycleProfile: WorkspacePackageLifecycleProfileV1,
        diagnosticsStore: DiagnosticsStore? = nil,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        evidenceStoreFailureInjection: EvidenceBundleStoreFailureInjection? = nil,
        evidenceSaveFailureInjection: CheckRunnerCoordinatorFailureInjection? = nil,
        finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil,
        finalizationServiceFailureInjection: FinalizationServiceFailureInjection? = nil,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        requirementEvaluatorRegistry: RequirementEvaluatorRegistryV1? = nil,
        draftAccessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil
    ) throws {
        guard try packageLifecycleDependencies.profileRegistry.resolve(
            packageLifecycleProfile.release
        ) == packageLifecycleProfile else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        self.modelContext = modelContext
        self.mutationRoute = .live(
            packageLifecycleDependencies,
            packageLifecycleProfile
        )
        self.clock = packageLifecycleDependencies.clock
        self.idSource = packageLifecycleDependencies.idSource
        self.signPack = packageLifecycleProfile.package
        self.diagnosticsStore = diagnosticsStore
        self.evidenceStoreFailureInjection = evidenceStoreFailureInjection
        self.evidenceSaveFailureInjection = evidenceSaveFailureInjection
        self.finalizationStoreFailureInjection = finalizationStoreFailureInjection
        self.finalizationServiceFailureInjection = finalizationServiceFailureInjection
        self.draftAccessState = draftAccessState
        self.requirementEvaluatorRegistry = requirementEvaluatorRegistry
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

    /// Exposes the canonical C25 release gate to the check-runner boundary.
    /// Draft and retired releases remain readable elsewhere, but cannot be
    /// selected for newly started work.
    func surveyDefinitionStartBinding(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws -> CheckRunnerSurveyDefinitionStartBindingV1 {
        try CheckRunnerSurveyDefinitionStartBindingV1(
            release: release,
            lifecycleState: lifecycleState
        )
    }

    func currentRequirementAssuranceDecision(
        workflowRecordID: UUID
    ) -> RequirementAssuranceGatePreflightV1 {
        do {
            guard let snapshot = try currentRequirementAssuranceSnapshot(
                workflowRecordID: workflowRecordID
            ) else {
                return .failed(.noAcceptedRevision, priorAcceptedSnapshot: nil)
            }
            return .evaluated(snapshot, priorAcceptedSnapshot: nil)
        } catch {
            return .failed(requirementAssuranceFailure(for: error), priorAcceptedSnapshot: nil)
        }
    }

    /// Deterministically evaluates a candidate without changing canonical data.
    /// Reserved S10 UI/finalization callers may consume this receipt only after
    /// their separate reconciliation; this method does not claim reachability.
    func evaluateRequirementAssurance(
        workflowRecordID: UUID,
        inputs: [RequirementEvaluationInputV1],
        integrity: RequirementIntegrityInputV1
    ) -> RequirementAssuranceGatePreflightV1 {
        let prior: RequirementAssuranceSnapshotV1?
        do {
            prior = try currentRequirementAssuranceSnapshot(workflowRecordID: workflowRecordID)
        } catch {
            return .failed(requirementAssuranceFailure(for: error), priorAcceptedSnapshot: nil)
        }
        guard !Task.isCancelled else {
            return .failed(.cancelled, priorAcceptedSnapshot: prior)
        }
        guard let registry = requirementEvaluatorRegistry,
              let lifecycle = liveLifecycle else {
            return .failed(.notConfigured, priorAcceptedSnapshot: prior)
        }
        do {
            let snapshot = try RequirementEvaluationEngineV1.makeSnapshot(
                workflowRecordID: workflowRecordID,
                workspaceID: lifecycle.dependencies.workspaceID.rawValue,
                inputs: inputs,
                registry: registry,
                integrity: integrity
            )
            let expectedRevision = prior?.evaluatedRevision ?? 0
            guard snapshot.evaluatedRevision == expectedRevision + 1 else {
                return .failed(.staleRevision, priorAcceptedSnapshot: prior)
            }
            return .evaluated(snapshot, priorAcceptedSnapshot: prior)
        } catch {
            return .failed(requirementAssuranceFailure(for: error), priorAcceptedSnapshot: prior)
        }
    }

    /// Evaluates and publishes through the sole workspace writer command. The
    /// accepted row is reread and compared before a permitting receipt returns.
    func rebuildRequirementAssurance(
        workflowRecordID: UUID,
        inputs: [RequirementEvaluationInputV1],
        integrity: RequirementIntegrityInputV1
    ) -> RequirementAssuranceGatePreflightV1 {
        let evaluated = evaluateRequirementAssurance(
            workflowRecordID: workflowRecordID,
            inputs: inputs,
            integrity: integrity
        )
        guard evaluated.failure == nil,
              let snapshot = evaluated.candidateSnapshot,
              let lifecycle = liveLifecycle else {
            return evaluated
        }
        guard !Task.isCancelled else {
            return .failed(.cancelled, priorAcceptedSnapshot: evaluated.priorAcceptedSnapshot)
        }
        do {
            let mutationID = try lifecycle.dependencies.writer.makeMutationID()
            let mutation = try RequirementAssuranceMutationV1(
                snapshot: snapshot,
                expectedEvaluatedRevision: evaluated.priorAcceptedSnapshot?.evaluatedRevision ?? 0,
                mutationID: mutationID.rawValue
            )
            _ = try lifecycle.dependencies.writer.execute(
                .applyRequirementAssurance(mutation),
                mutationID: mutationID
            )
            guard let accepted = try currentRequirementAssuranceSnapshot(
                workflowRecordID: workflowRecordID
            ), accepted == snapshot else {
                return .failed(
                    .persistenceUnavailable,
                    priorAcceptedSnapshot: evaluated.priorAcceptedSnapshot
                )
            }
            return .evaluated(accepted, priorAcceptedSnapshot: evaluated.priorAcceptedSnapshot)
        } catch {
            return .failed(
                requirementAssuranceFailure(for: error),
                priorAcceptedSnapshot: evaluated.priorAcceptedSnapshot
            )
        }
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

    /// Provisional job-kernel route. Existing synchronous UI callers remain
    /// source-compatible until the S10.6 shipping-route reconciliation.
    func reviewThumbnailDataOffMain(for evidence: ReviewEvidence) async throws -> Data {
        guard let generationRootURL = captureGenerationRootURL else {
            throw CheckRunnerCoordinatorError.captureNotConfigured
        }
        let root = generationRootURL.standardizedFileURL
        let relativePath = evidence.thumbnailRelativePath
        return try await offMainWorker.run {
            try Task.checkCancellation()
            let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
            guard candidate.path.hasPrefix(root.path + "/"),
                  !relativePath.hasPrefix("/"), !relativePath.contains("..") else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            return try Data(contentsOf: candidate, options: .mappedIfSafe)
        }
    }

    func configureCapture(generationRootURL: URL) {
        let standardizedURL = generationRootURL.standardizedFileURL
        guard liveLifecycle.map({
            $0.dependencies.generationRootURL == standardizedURL
        }) ?? true else { return }
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
        let purposes = try requiredEvidencePurposes(for: draft)
        guard purposes.count == 2 else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let firstRows = evidence.filter { $0.purposeKey == purposes[0].key }
        let secondRows = evidence.filter { $0.purposeKey == purposes[1].key }
        guard evidence.count == firstRows.count + secondRows.count,
              firstRows.count <= 1,
              secondRows.count <= 1,
              outcome.couldNotVerify != nil || (firstRows.count == 1 && secondRows.count == 1) else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let first = firstRows.first
        let second = secondRows.first
        return FinalizationReview(
            draftID: draftID,
            outcomeKey: outcome.key,
            outcomeDisplay: outcome.display,
            issueLabelDisplay: outcome.issueLabel?.display,
            wideEvidence: first.map { reviewEvidence($0, purposeDisplay: purposes[0].display) },
            closeEvidence: second.map { reviewEvidence($0, purposeDisplay: purposes[1].display) },
            couldNotVerifyReasonDisplay: outcome.couldNotVerify?.display,
            note: outcome.note,
            missingPurposeDisplays: [
                first == nil ? purposes[0].display : nil,
                second == nil ? purposes[1].display : nil,
            ].compactMap { $0 },
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
                    mutationID: idSource.makeID(),
                    packetID: idSource.makeID(),
                    stableRootID: idSource.makeID(),
                    reportID: idSource.makeID(),
                    issueID: isRecheck
                        ? existingIssueID
                        : outcome.issueLabel == nil ? nil : idSource.makeID(),
                    newIssueID: isRecheck && outcome.issueLabel != nil
                        ? idSource.makeID()
                        : nil
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
        let outcomeResult: FinalizationServiceOutcome
        do {
            let input = FinalizationServiceInput(
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
            if let lifecycle = liveLifecycle {
                let adapter = try PackFinalizationAdapterV1(
                    dependencies: lifecycle.dependencies,
                    profile: lifecycle.profile,
                    legacyModelContext: modelContext,
                    intentStoreFailureInjection: finalizationStoreFailureInjection,
                    failureInjection: finalizationServiceFailureInjection
                )
                let binding = try PackFinalizationBindingV1(
                    workspaceID: lifecycle.dependencies.workspaceID,
                    generationID: lifecycle.dependencies.generationID,
                    packageRelease: lifecycle.profile.release,
                    mutationID: MutationIDV1(rawValue: identifiers.mutationID),
                    durableReceiptIdentity: nil,
                    preservesReservedLegacyRawWriteDebt: true
                )
                outcomeResult = try await adapter.finalize(input, binding: binding).finalization
            } else {
                let service = try FinalizationService(
                    modelContext: modelContext,
                    signPack: signPack,
                    generationRootURL: generationRootURL,
                    intentStoreFailureInjection: finalizationStoreFailureInjection,
                    failureInjection: finalizationServiceFailureInjection
                )
                outcomeResult = try await service.finalize(input)
            }
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
        let coordinator: ReportDeliveryCoordinator
        if let liveLifecycle {
            guard liveLifecycle.dependencies.generationRootURL.standardizedFileURL
                    == generationRootURL.standardizedFileURL else {
                throw CheckRunnerCoordinatorError.packageLifecycleMismatch
            }
            coordinator = try ReportDeliveryCoordinator(
                modelContext: modelContext,
                lifecycleDependencies: liveLifecycle.dependencies,
                lifecycleProfile: liveLifecycle.profile,
                diagnosticsStore: diagnosticsStore
            )
        } else {
            coordinator = try ReportDeliveryCoordinator(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                diagnosticsStore: diagnosticsStore,
                signPack: signPack
            )
        }
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
        let purposes = try requiredEvidencePurposes(for: draft)
        guard purposes.count == 2 else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let first = evidence.filter { $0.purposeKey == purposes[0].key }
        let second = evidence.filter { $0.purposeKey == purposes[1].key }
        guard evidence.count == first.count + second.count,
              first.count <= 1,
              second.count <= 1 else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }

        let purpose: SignPack.EvidencePurpose?
        switch step {
        case .wide:
            guard first.isEmpty, second.isEmpty else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            purpose = purposes[0]
        case .close:
            guard first.count == 1, second.isEmpty else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            purpose = purposes[1]
        case .outcome:
            guard allowsIncompleteReview
                ? (second.isEmpty || first.count == 1)
                : (first.count == 1 && second.count == 1) else {
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

        let evidenceID = idSource.makeID()
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
            let nextDraftStepKey = preparation.step == .wide
                ? WorkflowDraftStep.close.rawValue
                : WorkflowDraftStep.outcome.rawValue
            if evidenceSaveFailureInjection?.consume(.evidenceModelSave) == true {
                throw CheckRunnerCoordinatorError.saveFailed
            }
            try executeWorkspaceMutation(
                .acceptCheckEvidence(CheckEvidenceMutationV1(
                    evidenceID: candidate.id,
                    draftID: candidate.recordID,
                    purposeKey: candidate.purposeKey,
                    relativePath: promoted.originalRelativePath,
                    mimeType: "image/jpeg",
                    byteCount: promoted.originalByteCount,
                    sha256: promoted.originalSHA256,
                    thumbnailRelativePath: promoted.thumbnailRelativePath,
                    thumbnailByteCount: promoted.thumbnailByteCount,
                    thumbnailSHA256: promoted.thumbnailSHA256,
                    nextDraftStepKey: nextDraftStepKey,
                    createdAt: candidate.createdAt
                )),
                mutationID: try MutationIDV1(rawValue: candidate.id),
                occurredAt: candidate.createdAt
            )
            let evidenceID = candidate.id
            let persisted = try modelContext.fetch(FetchDescriptor<EvidenceFile>(
                predicate: #Predicate { $0.id == evidenceID }
            ))
            guard persisted.count == 1, let accepted = persisted.first else {
                throw CheckRunnerCoordinatorError.saveFailed
            }
            return accepted
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
        guard let record = records.first else {
            throw CheckRunnerCoordinatorError.invalidCaptureState
        }
        let purposes = try requiredEvidencePurposes(for: record)
        let expectedStep: WorkflowDraftStep
        if purposes.indices.contains(0), candidate.purposeKey == purposes[0].key {
            expectedStep = .close
        } else if purposes.indices.contains(1), candidate.purposeKey == purposes[1].key {
            expectedStep = .outcome
        } else {
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
        let gateCheckedAt = clock.now()
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
            startedAt: clock.now()
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
                startedAt: submission.observedAtUTC ?? clock.now()
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

        do {
            try executeWorkspaceMutation(
                .updateSiteTimeZone(SiteTimeZoneMutationV1(
                    siteID: resolution.site.id,
                    timeZoneID: resolution.timeZoneID,
                    confirmedAt: confirmedAt
                )),
                mutationID: nil,
                occurredAt: confirmedAt
            )
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

    private func executeWorkspaceMutation(
        _ command: WorkspaceCommandV1,
        mutationID suppliedMutationID: MutationIDV1?,
        occurredAt: Date
    ) throws {
        let mutationID: MutationIDV1
        switch mutationRoute {
        case let .live(dependencies, _):
            mutationID = try suppliedMutationID ?? dependencies.writer.makeMutationID()
        case .expiringCompatibility:
            mutationID = try suppliedMutationID ?? MutationIDV1(rawValue: idSource.makeID())
        }
        if case let .live(dependencies, _) = mutationRoute {
            let workspaceWriter = dependencies.writer
            let current = try workspaceWriter.currentRevision()
            let targets = try workspaceTargets(command)
            let known = Dictionary(
                uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) }
            )
            let scoped = try WorkspaceRevisionV1(
                workspaceID: current.workspaceID,
                generationID: current.generationID,
                writerInstanceID: current.writerInstanceID,
                revision: current.revision,
                entityRevisions: targets.map {
                    WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
                }
            )
            _ = try workspaceWriter.execute(WorkspaceMutationRequestV1(
                mutationID: mutationID,
                expectedRevision: WorkspaceExpectedRevisionV1(snapshot: scoped),
                command: command
            ))
        } else if case let .expiringCompatibility(mutationAdapter, _, _) = mutationRoute {
            let temporaryPath = try fileAuthority.temporaryRelativePath(
                mutationID: mutationID,
                component: command.kind.rawValue
            )
            _ = try mutationAdapter.apply(
                command,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryPath
            )
        } else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
    }

    private func workspaceTargets(
        _ command: WorkspaceCommandV1
    ) throws -> [WorkspaceEntityIdentityV1] {
        switch command {
        case let .createFirstSign(value):
            return try [
                WorkspaceEntityIdentityV1(kind: .site, id: value.siteID),
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
            ]
        case let .createCheckDraft(value):
            var dependencies = try [
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID),
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
            ]
            if let issueID = value.issueID {
                dependencies.append(try WorkspaceEntityIdentityV1(kind: .issue, id: issueID))
            }
            if let parentRecordID = value.parentRecordID {
                dependencies.append(try WorkspaceEntityIdentityV1(
                    kind: .workflowRecord,
                    id: parentRecordID
                ))
            }
            return dependencies
        case let .acceptCheckEvidence(value):
            return try [
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.draftID),
                WorkspaceEntityIdentityV1(kind: .evidenceFile, id: value.evidenceID),
            ]
        case let .updateSiteTimeZone(value):
            return [try WorkspaceEntityIdentityV1(kind: .site, id: value.siteID)]
        case let .archiveEntities(value):
            return value.identities
        default:
            throw WorkspaceMutationFailureV1.unsupportedCommand
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
            && openingRecord.outcomeKey == (try packageOutcome(for: .findingObserved).key)
            && openingRecord.issueID == issue.id
        let opensDifferentIssue: Bool
        if let originalIssueID = openingRecord.issueID,
           originalIssueID != issue.id,
           openingRecord.stage == WorkflowStage.recheck.rawValue,
           openingRecord.outcomeKey == (try packageOutcome(for: .originalResolvedDifferentFinding).key) {
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
                    && child.outcomeKey == (try packageOutcome(for: .workRecorded).key))
                    || (child.stage == WorkflowStage.recheck.rawValue
                    && Set(try recheckOutcomeKeys()).contains(child.outcomeKey ?? "")) else {
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
              openingRecord.outcomeKey == (try packageOutcome(for: .findingObserved).key),
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
                    && child.outcomeKey == (try packageOutcome(for: .workRecorded).key))
                    || (child.stage == WorkflowStage.recheck.rawValue
                    && Set(try recheckOutcomeKeys()).contains(child.outcomeKey ?? "")) else {
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
        guard let profile = try? activeLifecycleProfile(),
              profile.release.matches(signPack),
              profile.release.packageID == asset.packID,
              profile.release.schemaVersion == asset.packSchemaVersion,
              profile.release.contentVersion == asset.packContentVersion,
              profile.requiredAcknowledgementKeys.count == 2 else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        let acknowledgements = try profile.requiredAcknowledgementKeys.map { key in
            let matches = signPack.acknowledgements.filter { $0.key == key }
            guard matches.count == 1 else { throw CheckRunnerCoordinatorError.invalidLineage }
            return matches[0]
        }
        return (
            afterDark: acknowledgements[0],
            safePosition: acknowledgements[1]
        )
    }

    private func requiredEvidencePurposes(
        for draft: WorkflowRecord
    ) throws -> [SignPack.EvidencePurpose] {
        let profile = try activeLifecycleProfile()
        _ = try profile.stage(draft.stage)
        return try profile.evidencePurposeKeys(for: .captureRequired).map { key in
            let matches = signPack.evidencePurposes.filter { $0.key == key }
            guard matches.count == 1 else {
                throw CheckRunnerCoordinatorError.invalidCaptureState
            }
            return matches[0]
        }
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
            key = try packageOutcome(for: .noFinding).key
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
            key = try packageOutcome(for: .findingObserved).key
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
            key = try packageOutcome(for: .couldNotVerify).key
            issueLabel = nil
            couldNotVerify = selected
            note = normalizedNote
            normalizedSelection = .couldNotVerify(reasonKey: selected.key, note: normalizedNote)
        case let .resolved(rawNote):
            let normalizedNote = try normalizedRecheckNote(rawNote)
            key = try packageOutcome(for: .resolved).key
            issueLabel = nil
            couldNotVerify = nil
            note = normalizedNote
            normalizedSelection = .resolved(note: normalizedNote)
        case let .issueStillVisible(rawNote):
            let normalizedNote = try normalizedRecheckNote(rawNote)
            key = try packageOutcome(for: .findingStillPresent).key
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
            key = try packageOutcome(for: .originalResolvedDifferentFinding).key
            issueLabel = selected
            couldNotVerify = nil
            note = normalizedNote
            normalizedSelection = .originalResolvedDifferentIssue(
                labelKey: normalizedKey,
                note: normalizedNote
            )
        }
        let matches = try activeLifecycleProfile().stages
            .flatMap(\.outcomes).filter { $0.key == key }
        guard let expected = matches.first,
              matches.allSatisfy({
                  $0.role == expected.role && $0.display == expected.display
              }) else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return (key, expected.display, issueLabel, couldNotVerify, note, normalizedSelection)
    }

    private func packageOutcome(
        for role: WorkspacePackageOutcomeRoleV1
    ) throws -> WorkspacePackageOutcomeProfileV1 {
        let matches = try activeLifecycleProfile().stages
            .flatMap(\.outcomes).filter { $0.role == role }
        guard let first = matches.first,
              matches.allSatisfy({ $0.key == first.key && $0.display == first.display }) else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        return first
    }

    private func activeLifecycleProfile() throws -> WorkspacePackageLifecycleProfileV1 {
        switch mutationRoute {
        case let .live(_, profile): return profile
        case .expiringCompatibility:
            return try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
                package: signPack
            )
        }
    }

    private func recheckOutcomeKeys() throws -> [String] {
        try [
            WorkspacePackageOutcomeRoleV1.resolved,
            .findingStillPresent,
            .originalResolvedDifferentFinding,
            .couldNotVerify,
        ].map { try packageOutcome(for: $0).key }
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
        let registry = signPack.couldNotVerifyReasons
        guard let outcome = try? packageOutcome(for: .couldNotVerify),
              signPackOutcomeDisplay(key: outcome.key) == outcome.display,
              !registry.version.isEmpty,
              registry.version == registry.version.trimmingCharacters(in: .whitespacesAndNewlines),
              (1...64).contains(registry.entries.count),
              Set(registry.entries.map(\.key)).count == registry.entries.count else {
            return false
        }
        return registry.entries.allSatisfy {
            !$0.key.isEmpty && $0.key == $0.key.trimmingCharacters(in: .whitespacesAndNewlines)
                && !$0.display.isEmpty
                && $0.display == $0.display.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
        let pdfTemplate = try activeLifecycleProfile().pdfTemplate
        guard signPack.packID == asset.packID,
              signPack.schemaVersion == asset.packSchemaVersion,
              signPack.contentVersion == asset.packContentVersion else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        let id = idSource.makeID()
        do {
            try executeWorkspaceMutation(
                .createCheckDraft(CheckDraftMutationV1(
                    recordID: id,
                    assetID: asset.id,
                    issueID: issueID,
                    parentRecordID: parentRecordID,
                    stage: requestedStage.rawValue,
                    draftStepKey: requestedStage == .work
                        ? nil
                        : WorkflowDraftStep.wide.rawValue,
                    startedAt: startedAt,
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
                    pdfTemplateID: pdfTemplate.id,
                    pdfTemplateVersion: pdfTemplate.version
                )),
                mutationID: try MutationIDV1(rawValue: id),
                occurredAt: startedAt
            )
        } catch {
            modelContext.rollback()
            throw CheckRunnerCoordinatorError.saveFailed
        }
        let persisted = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == id }
        ))
        guard persisted.count == 1, let accepted = persisted.first else {
            throw CheckRunnerCoordinatorError.saveFailed
        }
        return accepted
    }

    private func currentRequirementAssuranceSnapshot(
        workflowRecordID: UUID
    ) throws -> RequirementAssuranceSnapshotV1? {
        var descriptor = FetchDescriptor<RequirementAssuranceRow>(
            predicate: #Predicate { $0.workflowRecordID == workflowRecordID }
        )
        descriptor.fetchLimit = 2
        let rows = try modelContext.fetch(descriptor)
        guard rows.count <= 1 else {
            throw RequirementAssuranceFailureV1.duplicateIdentity
        }
        return try rows.first?.snapshot()
    }

    private func requirementAssuranceFailure(
        for error: Error
    ) -> RequirementAssuranceGateFailureV1 {
        if error is CancellationError { return .cancelled }
        if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
            return .protectedDataUnavailable
        }
        if let failure = error as? RequirementAssuranceFailureV1 {
            switch failure {
            case .staleRevision:
                return .staleRevision
            case .unknownRequirementType:
                return .unknownRequirementType
            case .missingEvaluator:
                return .missingEvaluator
            case .invalidValue, .incompatibleVersion, .duplicateIdentity,
                 .invalidEvidence, .invalidWaiver, .nonCanonicalOrder,
                 .digestMismatch, .revisionOverflow:
                return .invalidCanonicalState
            }
        }
        if let failure = error as? WorkspaceMutationFailureV1 {
            switch failure {
            case .writerInvalidated, .wrongWriterInstance, .wrongWorkspace,
                 .wrongGeneration, .staleWorkspaceRevision, .staleEntityRevision:
                return .staleRevision
            case .storageAdmissionFailed, .mutationIDQuarantined, .idempotencyCapacityReached,
                 .revisionOverflow, .unsupportedCommand, .invalidCommand,
                 .invalidEnvelope, .invalidReceipt, .invalidReversal,
                 .receiptHistoryCorrupt, .sequenceCollision, .persistenceFailed:
                return .persistenceUnavailable
            }
        }
        return .persistenceUnavailable
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

extension CheckRunnerCoordinator {
    nonisolated static func inspectionReviewCandidate(
        subject: InspectionReviewSubjectReferenceV1
    ) throws -> CheckRunnerInspectionReviewCandidateV1 {
        try .init(subject: subject)
    }
}

// MARK: - C19 measurement capture boundary

@MainActor
extension CheckRunnerCoordinator {
    /// Performs the C19 fixed-point/reference checks at the existing runner
    /// boundary. No draft, workflow, or persistence mutation occurs here.
    func validateMeasurementCapture(
        _ context: CheckRunnerMeasurementCaptureContextV1
    ) throws {
        try context.validate()
    }

    /// Runs the one canonical C19 quality evaluator after the read-only check
    /// boundary has passed. Quality remains review evidence and never an
    /// automatic workflow/compliance outcome.
    func evaluateMeasurementQuality(
        _ context: CheckRunnerMeasurementCaptureContextV1,
        assessmentID: UUID,
        policyVersion: String,
        policySHA256: String,
        evidence: [ContentReferenceV1] = [],
        assessedAt: Date,
        mutationID: MutationIDV1
    ) throws -> MeasurementQualityAssessmentV1 {
        try context.validate()
        return try MeasurementQualityEvaluatorV1.assessCapture(
            assessmentID: assessmentID,
            capture: context.capture,
            calibration: context.calibration,
            requiresUncertainty: context.protocolRelease.requiresUncertainty,
            policyVersion: policyVersion,
            policySHA256: policySHA256,
            evidence: evidence,
            assessedAt: assessedAt,
            mutationID: mutationID
        )
    }
}

// MARK: - C36 durable draft attachment bridge

@MainActor
extension CheckRunnerCoordinator {
    /// Builds the device-local staging adapter with the same application
    /// support root used by the other persistence writers.  When capture is
    /// configured, the existing C05 EvidenceBundleStore is injected as the
    /// sole immutable-content writer; no legacy EvidenceID is allocated here.
    func makeDraftAttachmentStagingAdapter(
        applicationSupportURL: URL,
        workspaceID: WorkspaceID,
        scratchStore: (any ScratchDataLeasePortV1)? = nil,
        storageLedger: OwnedStorageLedgerV1? = nil,
        immutableContentWriter: (any DraftImmutableContentWriterV1)? = nil
    ) throws -> DraftAttachmentStagingAdapterV1 {
        let writer: (any DraftImmutableContentWriterV1)?
        if let immutableContentWriter {
            writer = immutableContentWriter
        } else if let evidenceBundleStore {
            writer = evidenceBundleStore
        } else {
            writer = nil
        }
        try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: applicationSupportURL,
            workspaceID: workspaceID,
            scratchStore: scratchStore,
            storageLedger: storageLedger,
            immutableContentWriter: writer,
            clock: { [clock] in clock.now() }
        )
    }

    /// Stages one capture after the existing entitlement/access provider has
    /// been consulted.  A missing provider fails closed so callers cannot
    /// accidentally bypass the legacy check/work entitlement gate.
    func stageDraftAttachment(
        data: Data,
        draftID: UUID,
        workspaceID: WorkspaceID,
        attachmentKind: DraftAttachmentKindV1,
        adapter: DraftAttachmentStagingAdapterV1,
        stageID: UUID = UUID(),
        mutationID: MutationIDV1? = nil,
        mediaType: String? = nil,
        createdAt: Date? = nil,
        durableReceiptReadBack: Bool = false
    ) async throws -> CheckRunnerDraftCaptureCandidateV1 {
        guard let draftAccessState else {
            throw CheckRunnerDraftBridgeFailureV1.accessRequired
        }
        let item = try await adapter.stage(
            data: data,
            draftID: draftID,
            workspaceID: workspaceID,
            attachmentKind: attachmentKind,
            stageID: stageID,
            mutationID: mutationID,
            mediaType: mediaType,
            createdAt: createdAt
        )
        return try CheckRunnerDraftBridgeV1.captureCandidate(
            item: item,
            durableReceiptReadBack: durableReceiptReadBack,
            accessState: draftAccessState()
        )
    }

    /// Converts a committed draft reservation into a legacy media boundary
    /// without manufacturing the legacy EvidenceID.  The actual legacy
    /// finalization route remains responsible for any post-commit ID mapping.
    nonisolated static func draftMediaBoundary(
        reservation: DraftContentReservationV1
    ) throws -> DraftMediaPromotionBoundaryV1 {
        try reservation.validate()
        return .committed(
            contentID: reservation.locator.contentID,
            locatorID: reservation.locator.locatorID
        )
    }
}

// MARK: - C15 WorkPacket read-only check context

// MARK: - C33 bounded temporal evidence review

extension CheckRunnerCoordinator {
    /// Adopts an already-staged item for review. It starts no device capture and
    /// performs no canonical temporal-evidence write.
    nonisolated static func temporalEvidenceReviewCandidate(
        staged draft: CheckRunnerDraftCaptureCandidateV1,
        facts: TemporalEvidenceMediaFactsV1,
        profile: TemporalEvidenceLimitProfileV1,
        accessibleDescription: String,
        admissionReceipt: TemporalEvidenceIncrementalBudgetReceiptV1,
        manualTranscript: String? = nil
    ) throws -> CheckRunnerTemporalEvidenceReviewCandidateV1 {
        try CheckRunnerTemporalEvidenceReviewCandidateV1(
            draft: draft, facts: facts, profile: profile,
            accessibleDescription: accessibleDescription,
            manualTranscript: manualTranscript,
            admissionReceipt: admissionReceipt
        )
    }

    static let c33StartsMicrophoneOrVideoCapture = false
    static let c33AutomaticTranscriptionEnabled = false
    static let c33ManualFileImportFallbackPreserved = true
}

// MARK: - C15 WorkPacket read-only check context

@MainActor
extension CheckRunnerCoordinator {
    /// Resolves the immutable packet/item context used by a check without
    /// claiming, leasing, or otherwise mutating packet state.
    func workPacketContext(
        from snapshot: CompletedWorkPacketSnapshotV1,
        itemID: String
    ) throws -> CheckRunnerWorkPacketContextV1 {
        let context = try CheckRunnerWorkPacketContextV1(
            snapshot: snapshot,
            itemID: itemID
        )
        guard snapshot.items.contains(where: { $0.itemID == itemID }) else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
        return context
    }

    /// Returns collision metadata for review. The result intentionally
    /// contains no actor, claim, lease, evidence, or result content.
    func workPacketCollisionReview(
        from snapshot: CompletedWorkPacketSnapshotV1,
        itemID: String
    ) throws -> CheckRunnerWorkPacketCollisionReviewV1 {
        try snapshot.validate()
        guard let item = snapshot.items.first(where: { $0.itemID == itemID }) else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
        return try CheckRunnerWorkPacketCollisionReviewV1(
            packetID: snapshot.manifest.packetID,
            item: item
        )
    }

    /// Revalidates a previously resolved context against the latest immutable
    /// snapshot before a check begins. A changed revision/digest is stale;
    /// an explicitly conflicted item requires collision review.
    func validateWorkPacketReadyForCheck(
        _ context: CheckRunnerWorkPacketContextV1,
        currentSnapshot: CompletedWorkPacketSnapshotV1
    ) throws {
        try context.validate()
        try currentSnapshot.validate()
        let current = try CheckRunnerWorkPacketContextV1(
            snapshot: currentSnapshot,
            itemID: context.itemID
        )
        guard current.workspaceID == context.workspaceID,
              current.packetID == context.packetID,
              current.manifestID == context.manifestID,
              current.manifestSHA256 == context.manifestSHA256,
              current.expectedRevision == context.expectedRevision,
              current.itemSHA256 == context.itemSHA256 else {
            throw CheckRunnerCoordinatorError.workPacketStaleRevision
        }
        guard current.currentState != .conflicted else {
            throw CheckRunnerCoordinatorError.workPacketCollisionReviewRequired
        }
    }
}

// MARK: - C20 reviewed-derivative check boundary

@MainActor
extension CheckRunnerCoordinator {
    /// Evaluates the canonical C20 projection at the existing check boundary.
    /// This is deliberately read-only: a projection decision cannot complete
    /// a check, change a workflow outcome, or imply privacy/compliance.
    func validatePrivacyProjection(
        _ context: CheckRunnerPrivacyTransformContextV1
    ) throws -> PrivacyProjectionDecisionV1 {
        try context.projectionDecision()
    }

    /// Resolves the exact derivative only after the shared C20 gate has
    /// admitted policy, audience, source revision/digest, review, freshness,
    /// and metadata sanitation.
    func reviewedDerivativeReference(
        _ context: CheckRunnerPrivacyTransformContextV1
    ) throws -> ContentReferenceV1 {
        try context.reviewedDerivative()
    }
}

// MARK: - C23 field-reference check boundary

@MainActor
extension CheckRunnerCoordinator {
    /// Resolves the completed packet and its exact C23 release/binding
    /// projections without claiming or mutating any work-packet state.
    func fieldReferenceContext(
        from snapshot: CompletedWorkPacketSnapshotV1,
        itemID: String,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1]
    ) throws -> CheckRunnerFieldReferenceContextV1 {
        try CheckRunnerFieldReferenceContextV1(
            snapshot: snapshot,
            itemID: itemID,
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness
        )
    }

    /// Re-proves the packet and binding digests against the latest completed
    /// snapshot before a check consumes an offline reference.
    func validateFieldReferenceContext(
        _ context: CheckRunnerFieldReferenceContextV1,
        currentSnapshot: CompletedWorkPacketSnapshotV1,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1]
    ) throws {
        try context.validate()
        let current = try CheckRunnerFieldReferenceContextV1(
            snapshot: currentSnapshot,
            itemID: context.packet.itemID,
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness
        )
        guard current.packet == context.packet,
              current.fieldReferences == context.fieldReferences else {
            throw CheckRunnerCoordinatorError.workPacketStaleRevision
        }
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Features_CheckRunner_CheckRunnerCoordinator {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Features_CheckRunner_CheckRunnerCoordinator_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Features_CheckRunner_CheckRunnerCoordinator {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift", role: .checkRunner)
}

enum C31LightingConsumerBoundary_Features_CheckRunner_CheckRunnerCoordinator {
    static let registrationID = "C31_LIGHTING_CONSUMER/check-runner-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

// MARK: - C32 assistance review and acceptance

@MainActor
extension CheckRunnerCoordinator {
    /// Presents an explicitly unverified proposal. This does not complete a
    /// check or write a fact; the shared lifecycle owns only memory/scratch.
    func presentAssistance(
        _ context: CheckRunnerAssistanceReviewContextV1,
        using assistance: AssistanceCoordinatorV1
    ) async throws {
        try context.validate()
        try await assistance.present(context.proposal, context: context.evaluation)
    }

    func reviewAssistance(
        _ context: CheckRunnerAssistanceReviewContextV1,
        using assistance: AssistanceCoordinatorV1
    ) async throws -> AssistanceReviewDecisionV1 {
        try context.validate()
        return try await assistance.review(
            proposalID: context.proposal.proposalID,
            context: context.evaluation
        )
    }

    /// Acceptance remains a normal expected-revision writer operation. The
    /// runner re-reviews immediately before delegation and never applies the
    /// proposed ResponseValue directly to model state.
    func acceptReviewedAssistance(
        _ context: CheckRunnerAssistanceReviewContextV1,
        targetMutation: AssistanceCanonicalTargetMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        acceptedBy: ActorSnapshotV1,
        acceptedAt: Date,
        using assistance: AssistanceCoordinatorV1
    ) async throws -> AssistanceAcceptanceReceiptV1 {
        try context.validate()
        switch try await reviewAssistance(context, using: assistance) {
        case let .ready(current):
            guard current == context.proposal else {
                throw AssistanceContractFailureV1.staleTarget
            }
        case let .expired(disposition):
            throw AssistanceContractFailureV1.expired(disposition.reason)
        }
        return try await assistance.accept(
            proposalID: context.proposal.proposalID,
            targetMutation: targetMutation,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            acceptedBy: acceptedBy,
            acceptedAt: acceptedAt,
            context: context.evaluation
        )
    }

    /// Manual entry is always sourced from the independent user-authored
    /// value, never copied from a rejected or expired proposal.
    func manualAssistanceFallback(
        _ context: CheckRunnerAssistanceReviewContextV1
    ) throws -> ResponseValueV1 {
        try context.useManualValue()
    }

    /// Constructs C32 only on the canonical live package lifecycle. The
    /// compatibility adapter has no journal-owned receipt or authoritative
    /// revision projection and therefore fails closed.
    func makeAssistanceRuntime(
        scratchLeases: any CapabilityScratchLeasePortV1
    ) throws -> CheckRunnerAssistanceRuntimeV1 {
        guard case let .live(dependencies, _) = mutationRoute else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        let scratch = AssistanceCapabilityScratchLifecycleAdapterV1(
            leases: scratchLeases
        )
        let reader = CheckRunnerAssistanceAuthoritativeStateReaderV1(
            modelContext: modelContext,
            dependencies: dependencies,
            scratchSource: scratch
        )
        let currentState = AssistanceTrustedSnapshotAuthorityV1(reader: reader)
        let lifecycle = AssistanceLifecycleAdapterV1(
            writer: dependencies.writer,
            scratch: scratch,
            currentState: currentState
        )
        return CheckRunnerAssistanceRuntimeV1(
            coordinator: AssistanceCoordinatorV1(lifecycle: lifecycle),
            scratch: scratch
        )
    }
}

/// Keeps the sole scratch binding adapter reachable by a future authorized
/// proposal producer while the coordinator owns the same adapter for terminal
/// cleanup. C32 itself adds no capture/runtime provider.
@MainActor
struct CheckRunnerAssistanceRuntimeV1 {
    let coordinator: AssistanceCoordinatorV1
    let scratch: AssistanceCapabilityScratchLifecycleAdapterV1
}

/// Live, read-only C32 authority. It composes the existing workspace writer,
/// released feature-policy loader, exact C26 session release rows, package
/// promotion rows, scratch binding authority, and application clock. It never
/// captures OCR, speech, location, or other device observations.
@MainActor
private final class CheckRunnerAssistanceAuthoritativeStateReaderV1:
    AssistanceAuthoritativeStateReadingV1 {
    private let modelContext: ModelContext
    private let dependencies: WorkspacePackageLifecycleDependenciesV1
    private let scratchSource: any AssistanceCurrentSourceReadingV1
    private let policyLoader: FeaturePolicyLoaderV1

    init(
        modelContext: ModelContext,
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        scratchSource: any AssistanceCurrentSourceReadingV1,
        policyLoader: FeaturePolicyLoaderV1 = FeaturePolicyLoaderV1(
            provider: BundleFeaturePolicyDataProviderV1()
        )
    ) {
        self.modelContext = modelContext
        self.dependencies = dependencies
        self.scratchSource = scratchSource
        self.policyLoader = policyLoader
    }

    func readCurrentAssistanceState(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1
    ) async throws -> AssistanceAuthoritativeStateV1 {
        try capability.validate()
        try target.validate()
        try source.validate()
        guard target.workspaceID == dependencies.workspaceID,
              target.entity.kind == .surveySession else {
            throw AssistanceContractFailureV1.staleTarget
        }

        let workspaceRevision = try dependencies.writer.currentRevision()
        let currentTargetRows = workspaceRevision.entityRevisions.filter {
            $0.identity == target.entity
        }
        guard workspaceRevision.workspaceID == dependencies.workspaceID,
              workspaceRevision.generationID == dependencies.generationID,
              currentTargetRows.count == 1 else {
            throw AssistanceContractFailureV1.staleTarget
        }

        let binding = try AssistanceFeaturePolicyBindingV1.binding(for: capability)
        let resolution = try binding.featureID.map {
            try policyLoader.resolve(featureID: $0)
        }
        let policy = try binding.makePolicy(
            capability: capability,
            resolution: resolution
        )

        let sessionID = target.entity.id
        let sessionRows = try modelContext.fetch(FetchDescriptor<SurveySessionRow>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))
        guard sessionRows.count == 1, let sessionRow = sessionRows.first else {
            throw AssistanceContractFailureV1.staleTarget
        }
        let session = try sessionRow.value()
        guard session.workspaceID == dependencies.workspaceID,
              session.sessionID == sessionID,
              session.revision == currentTargetRows[0].revision else {
            throw AssistanceContractFailureV1.staleTarget
        }

        let definitionReleaseID = session.authority.definitionRelease.releaseID
        let definitionRows = try modelContext.fetch(
            FetchDescriptor<SurveyDefinitionReleaseRow>(
                predicate: #Predicate { $0.releaseID == definitionReleaseID }
            )
        )
        let promoted = try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
            .map { try $0.value() }
            .filter {
                $0.workspaceID == dependencies.workspaceID
                    && $0.packageRelease.packageReleaseID
                        == session.authority.packageRelease.packageReleaseID
            }
        guard definitionRows.count == 1,
              let definitionRow = definitionRows.first,
              promoted.count == 1,
              let packageRelease = promoted.first?.packageRelease else {
            throw AssistanceContractFailureV1.staleTarget
        }
        let definition = try definitionRow.value(
            pinnedBy: session.authority,
            packageRelease: packageRelease
        )
        guard definition.releaseSHA256
                == session.authority.definitionRelease.releaseSHA256 else {
            throw AssistanceContractFailureV1.staleTarget
        }

        let currentSource: AssistanceSourceReferenceV1?
        if source.kind == .leasedScratch {
            currentSource = try scratchSource.currentSource(
                proposalID: proposalID,
                expected: source
            )
        } else {
            // C32 ships no immutable/deterministic/device source provider.
            currentSource = nil
        }
        return try AssistanceAuthoritativeStateV1(
            workspaceRevision: workspaceRevision,
            policy: policy,
            packageReleaseSHA256: packageRelease.packageSHA256,
            definitionReleaseSHA256: definition.releaseSHA256,
            currentSource: currentSource,
            evaluatedAt: dependencies.clock.now()
        )
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Features_CheckRunner_CheckRunnerCoordinator_swift {
    static let c47IntegrationRole = "EXPLICIT_START_NO_P04_ROUTE"
    static let c47SharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let c47InstallationReceipt = InstallationActivityContractReceiptV1.self
    static let c47PunchReceipt = PunchActivityContractReceiptV1.self
    static let c47NoPlanFallback = NoPlanFallbackV1.self
    static let c47UsesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let c47CreatesSecondRouteOrInspectionAlias = false
    static func c47ValidateExplicitStart(_ candidate: ActivityContractReviewCandidateV2) throws {
        try candidate.envelope.kind.requireKnownForMutation()
        guard candidate.mayStart else { throw ActivityContractFailureV2.invalidTransition }
    }
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

extension CheckRunnerCoordinator {
    static func activityContractReviewCandidate(
        envelope: ActivitySessionEnvelopeV2,
        noPlanFallback: NoPlanFallbackV1?
    ) throws -> ActivityContractReviewCandidateV2 {
        try ActivityContractCloseoutSettingsPolicyV2.validateCanonicalPresentation(envelope)
        return try ActivityContractReviewCandidateV2(
            envelope: envelope, noPlanFallback: noPlanFallback
        )
    }

    static func restoreActivityRoute(
        from canonicalData: Data,
        querying query: any ActivityContractCurrentStateQueryingV2
    ) async throws -> ActivityRouteV2 {
        let route = try ActivityRouteCanonicalRegistryV2.decode(canonicalData)
        guard let current = try await query.currentActivityContract(
            workspaceID: route.workspaceID, activityID: route.activityID
        ), let envelope = current.envelope,
              envelope.workspaceID == route.workspaceID,
              envelope.activityID == route.activityID,
              envelope.kind == route.kind else {
            throw ActivityContractCoordinatorFailureV2.targetMissing
        }
        return route
    }
}

enum C47ActivityContractConformance_FieldEvidenceApp_Features_CheckRunner_CheckRunnerCoordinator_swift {
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingInfrastructureOnly = true
    static let createsSecondWriterRendererStoreRouteOrInspectionAlias = false
}

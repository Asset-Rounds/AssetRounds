import CryptoKit
import Foundation
import SwiftData

struct WorkDraftValue: Equatable, Hashable, Sendable {
    let recordID: UUID
    let issueID: UUID
    let assetID: UUID
    let startedAt: Date
}

struct WorkPhotoSubmission: Equatable, Sendable {
    let purposeKey: String
    let sourceData: Data
    let createdAt: Date
}

struct WorkSaveSubmission: Equatable, Sendable {
    let performedLocalDate: String
    let description: String
    let note: String?
    let photos: [WorkPhotoSubmission]
    let completedAt: Date
}

struct WorkIdentifiers: Equatable, Sendable {
    let mutationID: UUID
    let evidenceID: UUID?
}

struct WorkRecordPresentationValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let performedLocalDate: String
    let description: String
    let note: String?
    let photoThumbnailJPEG: Data?
}

struct WorkIssuePresentationValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let assetID: UUID
    let label: String
    let status: IssueStatus
    let records: [WorkRecordPresentationValue]

    var canRecordWork: Bool { status == .open }
}

enum WorkCoordinatorError: Error, Equatable {
    case invalidAuthority
    case invalidSubmission
    case differentDraftActive
    case storageUnavailable
    case mediaInvalid
    case saveFailed
    case cleanupFailed
}

enum WorkCoordinatorFailurePoint: Equatable, Sendable {
    case modelSave
    case afterEvidencePromotion
}

@MainActor
final class WorkCoordinatorFailureInjection {
    private var pending: WorkCoordinatorFailurePoint?

    init(failOnceAt point: WorkCoordinatorFailurePoint) {
        pending = point
    }

    func removeFailure() {
        pending = nil
    }

    fileprivate func consume(_ point: WorkCoordinatorFailurePoint) -> Bool {
        guard pending == point else { return false }
        pending = nil
        return true
    }
}

@MainActor
final class WorkCoordinator {
    private static let pdfTemplateID = "field.evidence.pdf.worklight.v1"
    private static let recheckOutcomes: Set<String> = [
        "resolved",
        "issue_still_visible",
        "original_resolved_different_issue",
        "could_not_verify",
    ]

    private let modelContext: ModelContext
    private let signPack: SignPack
    private let generationRootURL: URL
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let checkRunnerCoordinator: CheckRunnerCoordinator
    private let evidenceStore: EvidenceBundleStore
    private let storagePreflight: StoragePreflightService
    private let failureInjection: WorkCoordinatorFailureInjection?

    private struct Authority {
        let asset: Asset
        let issue: Issue
        let draft: WorkflowRecord?
        let parent: WorkflowRecord
        let substantiveChain: [WorkflowRecord]
        let evidence: [EvidenceFile]
    }

    init(
        modelContext: ModelContext,
        signPack: SignPack,
        generationRootURL: URL,
        checkRunnerCoordinator: CheckRunnerCoordinator,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        evidenceStoreFailureInjection: EvidenceBundleStoreFailureInjection? = nil,
        failureInjection: WorkCoordinatorFailureInjection? = nil
    ) throws {
        let root = generationRootURL.standardizedFileURL
        self.modelContext = modelContext
        self.signPack = signPack
        self.generationRootURL = root
        self.rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        self.checkRunnerCoordinator = checkRunnerCoordinator
        self.evidenceStore = EvidenceBundleStore(
            generationRootURL: root,
            failureInjection: evidenceStoreFailureInjection
        )
        self.storagePreflight = storagePreflight
        self.failureInjection = failureInjection
    }

    func activeIssue(assetID: UUID) async throws -> WorkIssuePresentationValue? {
        try requireCleanContext()
        let descriptor = FetchDescriptor<Issue>(
            predicate: #Predicate { $0.assetID == assetID }
        )
        let candidates = try modelContext.fetch(descriptor).filter {
            $0.status == IssueStatus.open.rawValue
                || $0.status == IssueStatus.recheckDue.rawValue
        }
        guard candidates.count <= 1 else {
            throw WorkCoordinatorError.invalidAuthority
        }
        guard let issue = candidates.first else { return nil }
        let authority = try validatedAuthority(issueID: issue.id, draftID: nil)
        return try await presentation(authority)
    }

    func issue(id issueID: UUID) async throws -> WorkIssuePresentationValue {
        try requireCleanContext()
        return try await presentation(
            validatedAuthority(issueID: issueID, draftID: nil)
        )
    }

    func beginWork(issueID: UUID) throws -> WorkDraftValue {
        try requireCleanContext()
        let authority = try validatedAuthority(issueID: issueID, draftID: nil)
        guard authority.issue.status == IssueStatus.open.rawValue else {
            throw WorkCoordinatorError.invalidAuthority
        }
        let draft: WorkflowRecord
        do {
            draft = try checkRunnerCoordinator.beginOrResumeDraft(
                assetID: authority.asset.id,
                requestedStage: .work,
                issueID: issueID
            )
        } catch {
            throw WorkCoordinatorError.invalidAuthority
        }
        guard draft.stage == WorkflowStage.work.rawValue,
              draft.issueID == issueID else {
            throw WorkCoordinatorError.differentDraftActive
        }
        let refreshed = try validatedAuthority(issueID: issueID, draftID: draft.id)
        guard refreshed.draft?.id == draft.id else {
            throw WorkCoordinatorError.invalidAuthority
        }
        return WorkDraftValue(
            recordID: draft.id,
            issueID: issueID,
            assetID: draft.assetID,
            startedAt: draft.startedAt
        )
    }

    func saveWork(
        draftID: UUID,
        submission: WorkSaveSubmission,
        identifiers suppliedIdentifiers: WorkIdentifiers? = nil
    ) async throws -> WorkIssuePresentationValue {
        try requireCleanContext()
        try requireRootIdentity()

        let identifiers = suppliedIdentifiers ?? WorkIdentifiers(
            mutationID: UUID(),
            evidenceID: submission.photos.isEmpty ? nil : UUID()
        )
        guard (submission.photos.count == 1) == (identifiers.evidenceID != nil) else {
            throw WorkCoordinatorError.invalidSubmission
        }

        if let replay = try await replayedWork(
            draftID: draftID,
            submission: submission,
            identifiers: identifiers
        ) {
            return replay
        }

        let authority = try authorityForDraft(draftID)
        guard let draft = authority.draft,
              draft.id == draftID else {
            throw WorkCoordinatorError.invalidAuthority
        }
        let ruleSubmission = WorkRuleSubmission(
            performedLocalDate: submission.performedLocalDate,
            description: submission.description,
            note: submission.note,
            completedAt: submission.completedAt,
            mutationID: identifiers.mutationID,
            evidencePurposeKeys: submission.photos.map(\.purposeKey)
        )
        let plan: WorkRulePlan
        do {
            plan = try WorkRule.makePlan(
                draft: payload(draft),
                issue: payload(authority.issue),
                parent: payload(authority.parent),
                submission: ruleSubmission
            )
        } catch {
            throw WorkCoordinatorError.invalidSubmission
        }
        guard authority.evidence.filter({ $0.recordID == draftID }).isEmpty,
              try uniqueMutationOwner(identifiers.mutationID) == nil else {
            throw WorkCoordinatorError.invalidAuthority
        }

        var promoted: PromotedEvidenceBundle?
        var evidenceToInsert: EvidenceFile?
        if let photo = submission.photos.first,
           let evidenceID = identifiers.evidenceID {
            guard photo.createdAt >= draft.startedAt,
                  photo.createdAt <= submission.completedAt else {
                throw WorkCoordinatorError.invalidSubmission
            }
            do {
                try storagePreflight.checkEvidenceAcceptance(
                    onVolumeContaining: generationRootURL
                )
            } catch {
                throw WorkCoordinatorError.storageUnavailable
            }
            let normalized: NormalizedMediaV1
            do {
                normalized = try MediaNormalizerV1().normalize(photo.sourceData)
            } catch {
                throw WorkCoordinatorError.mediaInvalid
            }
            let staged: StagedEvidenceBundle
            do {
                staged = try await evidenceStore.stage(
                    evidenceID: evidenceID,
                    normalized: normalized
                )
            } catch {
                throw WorkCoordinatorError.mediaInvalid
            }
            do {
                try requireCleanContext()
                try requireRootIdentity()
                try revalidate(
                    authority,
                    draftID: draftID,
                    submission: ruleSubmission,
                    plan: plan
                )
                let published = try await evidenceStore.promote(staged)
                promoted = published
                try requireCleanContext()
                try requireRootIdentity()
                try revalidate(
                    authority,
                    draftID: draftID,
                    submission: ruleSubmission,
                    plan: plan
                )
                if failureInjection?.consume(.afterEvidencePromotion) == true {
                    throw WorkCoordinatorError.saveFailed
                }
                evidenceToInsert = EvidenceFile(
                    id: evidenceID,
                    recordID: draftID,
                    purposeKey: "work_context",
                    relativePath: published.originalRelativePath,
                    mimeType: "image/jpeg",
                    byteCount: published.originalByteCount,
                    sha256: published.originalSHA256,
                    createdAt: photo.createdAt,
                    thumbnailRelativePath: published.thumbnailRelativePath,
                    thumbnailByteCount: published.thumbnailByteCount,
                    thumbnailSHA256: published.thumbnailSHA256
                )
            } catch {
                let failure = error
                if let promoted {
                    do {
                        try await evidenceStore.removePromotedBundleIfOwned(promoted)
                    } catch {
                        throw WorkCoordinatorError.cleanupFailed
                    }
                } else {
                    do {
                        try await evidenceStore.discardStaging(evidenceID: evidenceID)
                    } catch {
                        throw WorkCoordinatorError.cleanupFailed
                    }
                }
                if let typed = failure as? WorkCoordinatorError { throw typed }
                throw WorkCoordinatorError.invalidAuthority
            }
        }

        let draftBefore = payload(draft)
        let issueBefore = payload(authority.issue)
        do {
            apply(plan.recordAfter, to: draft)
            apply(plan.issueAfter, to: authority.issue)
            if let evidenceToInsert {
                modelContext.insert(evidenceToInsert)
            }
            if failureInjection?.consume(.modelSave) == true {
                throw WorkCoordinatorError.saveFailed
            }
            try modelContext.save()
        } catch {
            let failure = error
            restore(draftBefore, to: draft)
            restore(issueBefore, to: authority.issue)
            modelContext.rollback()
            if let promoted {
                do {
                    try await evidenceStore.removePromotedBundleIfOwned(promoted)
                } catch {
                    throw WorkCoordinatorError.cleanupFailed
                }
            }
            if let typed = failure as? WorkCoordinatorError { throw typed }
            throw WorkCoordinatorError.saveFailed
        }

        try requireCleanContext()
        return try await issue(id: authority.issue.id)
    }

    private func replayedWork(
        draftID: UUID,
        submission: WorkSaveSubmission,
        identifiers: WorkIdentifiers
    ) async throws -> WorkIssuePresentationValue? {
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let mutationOwners = records.filter {
            $0.finalizationMutationID == identifiers.mutationID
        }
        let completedByID = records.filter { $0.id == draftID }
        guard !mutationOwners.isEmpty || completedByID.contains(where: {
            $0.state == WorkflowState.completed.rawValue
        }) else {
            return nil
        }
        guard mutationOwners.count == 1,
              completedByID.count == 1,
              let record = mutationOwners.first,
              record.id == draftID,
              completedByID.first === record,
              record.state == WorkflowState.completed.rawValue,
              record.stage == WorkflowStage.work.rawValue,
              record.workPerformedLocalDate == submission.performedLocalDate,
              record.workDescription == submission.description,
              record.note == submission.note,
              record.completedAt == submission.completedAt,
              let issueID = record.issueID else {
            throw WorkCoordinatorError.invalidAuthority
        }
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>()).filter {
            $0.recordID == draftID
        }
        guard evidence.count == submission.photos.count,
              evidence.first?.id == identifiers.evidenceID,
              evidence.allSatisfy({ $0.purposeKey == "work_context" }) else {
            throw WorkCoordinatorError.invalidAuthority
        }
        if let photo = submission.photos.first,
           let row = evidence.first {
            let normalized: NormalizedMediaV1
            do {
                normalized = try MediaNormalizerV1().normalize(photo.sourceData)
            } catch {
                throw WorkCoordinatorError.invalidAuthority
            }
            let promoted = PromotedEvidenceBundle(
                evidenceID: row.id,
                originalRelativePath: row.relativePath,
                thumbnailRelativePath: row.thumbnailRelativePath,
                originalByteCount: row.byteCount,
                thumbnailByteCount: row.thumbnailByteCount,
                originalSHA256: row.sha256,
                thumbnailSHA256: row.thumbnailSHA256
            )
            guard row.createdAt == photo.createdAt,
                  row.byteCount == normalized.originalJPEG.count,
                  row.thumbnailByteCount == normalized.thumbnailJPEG.count,
                  row.sha256 == SHA256.hash(data: normalized.originalJPEG).hexString,
                  row.thumbnailSHA256
                    == SHA256.hash(data: normalized.thumbnailJPEG).hexString else {
                throw WorkCoordinatorError.invalidAuthority
            }
            do {
                _ = try await evidenceStore.verifyPromoted(promoted)
                try requireCleanContext()
                try requireRootIdentity()
            } catch {
                throw WorkCoordinatorError.invalidAuthority
            }
        }
        return try await issue(id: issueID)
    }

    private func authorityForDraft(_ draftID: UUID) throws -> Authority {
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        guard records.filter({ $0.id == draftID }).count == 1,
              let draft = records.first(where: { $0.id == draftID }),
              let issueID = draft.issueID else {
            throw WorkCoordinatorError.invalidAuthority
        }
        return try validatedAuthority(issueID: issueID, draftID: draftID)
    }

    private func validatedAuthority(
        issueID: UUID,
        draftID: UUID?
    ) throws -> Authority {
        try requireCleanContext()
        try requireRootIdentity()
        let sites = try modelContext.fetch(FetchDescriptor<Site>())
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let issues = try modelContext.fetch(FetchDescriptor<Issue>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let mutationIDs = records.compactMap(\.finalizationMutationID)
        let evidencePaths = evidence.flatMap {
            [$0.relativePath, $0.thumbnailRelativePath]
        }
        guard uniqueIDs(sites.map(\.id)),
              uniqueIDs(assets.map(\.id)),
              uniqueIDs(issues.map(\.id)),
              uniqueIDs(records.map(\.id)),
              uniqueIDs(evidence.map(\.id)),
              uniqueIDs(packets.map(\.id)),
              uniqueIDs(packets.map(\.stableRootID)),
              uniqueIDs(packets.compactMap(\.currentRecordID)),
              uniqueIDs(mutationIDs),
              Set(evidencePaths).count == evidencePaths.count,
              issues.filter({ $0.id == issueID }).count == 1,
              let issue = issues.first(where: { $0.id == issueID }),
              assets.filter({ $0.id == issue.assetID }).count == 1,
              let asset = assets.first(where: { $0.id == issue.assetID }),
              sites.filter({ $0.id == asset.siteID }).count == 1,
              let site = sites.first(where: { $0.id == asset.siteID }),
              site.schemaVersion == 1,
              site.updatedAt >= site.createdAt,
              asset.schemaVersion == 1,
              asset.updatedAt >= asset.createdAt,
              asset.packID == signPack.packID,
              asset.packSchemaVersion == signPack.schemaVersion,
              asset.packContentVersion == signPack.contentVersion,
              issue.schemaVersion == 1,
              issue.resolvedByRecordID == nil,
              issue.updatedAt >= issue.createdAt,
              signPack.issueLabels.filter({
                  $0.key == issue.labelKey
                      && $0.display == issue.labelDisplaySnapshot
              }).count == 1 else {
            throw WorkCoordinatorError.invalidAuthority
        }
        let activeIssues = issues.filter {
            $0.assetID == asset.id
                && ($0.status == IssueStatus.open.rawValue
                    || $0.status == IssueStatus.recheckDue.rawValue)
        }
        guard activeIssues.count == 1,
              activeIssues.first?.id == issue.id else {
            throw WorkCoordinatorError.invalidAuthority
        }

        guard records.filter({ $0.id == issue.openedByRecordID }).count == 1,
              let opening = records.first(where: { $0.id == issue.openedByRecordID }),
              validOpeningRecord(opening, issue: issue) else {
            throw WorkCoordinatorError.invalidAuthority
        }
        let issueRecords = records.filter { $0.issueID == issue.id }
        guard issueRecords.allSatisfy({ $0.assetID == asset.id }) else {
            throw WorkCoordinatorError.invalidAuthority
        }
        let substantive = issueRecords.filter {
            $0.issueID == issue.id
                && $0.revisionKind == WorkflowRevisionKind.original.rawValue
                && $0.state == WorkflowState.completed.rawValue
        }
        let corrections = issueRecords.filter {
            $0.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue
                && $0.state == WorkflowState.completed.rawValue
        }
        let issueDrafts = issueRecords.filter {
            $0.state == WorkflowState.draft.rawValue
        }
        guard substantive.count + corrections.count + issueDrafts.count
                == issueRecords.count else {
            throw WorkCoordinatorError.invalidAuthority
        }
        try validateRevisionAuthority(
            substantiveRecords: substantive,
            allRecords: records
        )
        var chain: [WorkflowRecord] = [opening]
        var visited: Set<UUID> = [opening.id]
        var current = opening
        while true {
            let children = records.filter {
                $0.parentRecordID == current.id
                    && $0.revisionKind == WorkflowRevisionKind.original.rawValue
                    && $0.state == WorkflowState.completed.rawValue
            }
            guard children.count <= 1 else {
                throw WorkCoordinatorError.invalidAuthority
            }
            guard let child = children.first else { break }
            guard visited.insert(child.id).inserted,
                  validSubstantiveChild(child, issue: issue),
                  let parentCompletedAt = current.completedAt,
                  child.startedAt >= parentCompletedAt else {
                throw WorkCoordinatorError.invalidAuthority
            }
            chain.append(child)
            current = child
        }
        guard visited.count == substantive.count,
              validStatus(issue, terminal: current) else {
            throw WorkCoordinatorError.invalidAuthority
        }
        for record in chain where record.stage != WorkflowStage.work.rawValue {
            guard let packetID = record.packetID,
                  packets.filter({ $0.id == packetID }).count == 1,
                  let packet = packets.first(where: { $0.id == packetID }),
                  packet.schemaVersion == 1,
                  packet.contentDeletedAt == nil,
                  packet.evaluationCounted,
                  packet.createdAt <= (record.completedAt ?? .distantPast),
                  packet.currentRecordID
                    == revisionTip(for: record, allRecords: records)?.id else {
                throw WorkCoordinatorError.invalidAuthority
            }
        }

        let allDrafts = records.filter {
            $0.assetID == asset.id && $0.state == WorkflowState.draft.rawValue
        }
        let draft: WorkflowRecord?
        if let draftID {
            guard allDrafts.count == 1,
                  allDrafts.first?.id == draftID,
                  let match = allDrafts.first,
                  match.stage == WorkflowStage.work.rawValue,
                  match.issueID == issue.id,
                  match.parentRecordID == current.id else {
                throw WorkCoordinatorError.invalidAuthority
            }
            draft = match
        } else {
            guard allDrafts.count <= 1 else {
                throw WorkCoordinatorError.invalidAuthority
            }
            draft = nil
        }

        let issueRecordIDs = Set(issueRecords.map(\.id))
        let issueEvidence = evidence.filter { row in
            issueRecordIDs.contains(row.recordID)
        }
        for record in chain {
            let rows = issueEvidence.filter { $0.recordID == record.id }
            try validateEvidence(rows, for: record)
        }
        guard corrections.allSatisfy({ correction in
            issueEvidence.allSatisfy({ $0.recordID != correction.id })
        }) else {
            throw WorkCoordinatorError.invalidAuthority
        }
        if let draft {
            guard issueEvidence.filter({ $0.recordID == draft.id }).isEmpty else {
                throw WorkCoordinatorError.invalidAuthority
            }
        }
        return Authority(
            asset: asset,
            issue: issue,
            draft: draft,
            parent: current,
            substantiveChain: chain,
            evidence: evidence
        )
    }

    private func presentation(
        _ authority: Authority
    ) async throws -> WorkIssuePresentationValue {
        let workRecords = authority.substantiveChain.filter {
            $0.stage == WorkflowStage.work.rawValue
        }.sorted {
            let left = $0.completedAt ?? .distantPast
            let right = $1.completedAt ?? .distantPast
            return left == right
                ? $0.id.uuidString < $1.id.uuidString
                : left < right
        }
        var values: [WorkRecordPresentationValue] = []
        for record in workRecords {
            guard let date = record.workPerformedLocalDate,
                  let description = record.workDescription,
                  validCompletedWorkText(description, maximum: 160),
                  (record.note.map({
                      validCompletedWorkText($0, maximum: 1_000)
                  }) ?? true) else {
                throw WorkCoordinatorError.invalidAuthority
            }
            let rows = authority.evidence.filter { $0.recordID == record.id }
            guard rows.count <= 1 else {
                throw WorkCoordinatorError.invalidAuthority
            }
            var thumbnail: Data?
            if let row = rows.first {
                let promoted = PromotedEvidenceBundle(
                    evidenceID: row.id,
                    originalRelativePath: row.relativePath,
                    thumbnailRelativePath: row.thumbnailRelativePath,
                    originalByteCount: row.byteCount,
                    thumbnailByteCount: row.thumbnailByteCount,
                    originalSHA256: row.sha256,
                    thumbnailSHA256: row.thumbnailSHA256
                )
                _ = try await evidenceStore.verifyPromoted(promoted)
                try requireRootIdentity()
                let data = try ReportPDFAnchoredFile.readRegularFile(
                    at: generationRootURL.appendingPathComponent(row.thumbnailRelativePath),
                    within: generationRootURL,
                    rootIdentity: rootIdentity
                )
                guard data.count == row.thumbnailByteCount,
                      SHA256.hash(data: data).hexString == row.thumbnailSHA256 else {
                    throw WorkCoordinatorError.invalidAuthority
                }
                thumbnail = data
            }
            values.append(
                WorkRecordPresentationValue(
                    id: record.id,
                    performedLocalDate: date,
                    description: description,
                    note: record.note,
                    photoThumbnailJPEG: thumbnail
                )
            )
        }
        guard let status = IssueStatus(rawValue: authority.issue.status) else {
            throw WorkCoordinatorError.invalidAuthority
        }
        return WorkIssuePresentationValue(
            id: authority.issue.id,
            assetID: authority.issue.assetID,
            label: authority.issue.labelDisplaySnapshot,
            status: status,
            records: values
        )
    }

    private func revalidate(
        _ original: Authority,
        draftID: UUID,
        submission: WorkRuleSubmission,
        plan: WorkRulePlan
    ) throws {
        let current = try validatedAuthority(
            issueID: original.issue.id,
            draftID: draftID
        )
        guard let originalDraft = original.draft,
              let draft = current.draft,
              payload(draft) == payload(originalDraft),
              payload(current.issue) == payload(original.issue),
              payload(current.parent) == payload(original.parent),
              try WorkRule.makePlan(
                  draft: payload(draft),
                  issue: payload(current.issue),
                  parent: payload(current.parent),
                  submission: submission
              ) == plan else {
            throw WorkCoordinatorError.invalidAuthority
        }
    }

    private func uniqueMutationOwner(_ mutationID: UUID) throws -> WorkflowRecord? {
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.finalizationMutationID == mutationID
        }
        guard records.count <= 1 else {
            throw WorkCoordinatorError.invalidAuthority
        }
        return records.first
    }

    private func validateRevisionAuthority(
        substantiveRecords: [WorkflowRecord],
        allRecords: [WorkflowRecord]
    ) throws {
        for root in substantiveRecords {
            guard root.recordRevisionRootID == root.id,
                  root.revisesRecordID == nil,
                  root.evidenceSourceRecordID == nil else {
                throw WorkCoordinatorError.invalidAuthority
            }
            let revisionGroup = allRecords.filter {
                $0.recordRevisionRootID == root.id
            }
            var visited: Set<UUID> = [root.id]
            var current = root
            while true {
                let children = allRecords.filter {
                    $0.revisesRecordID == current.id
                }
                guard children.count <= 1 else {
                    throw WorkCoordinatorError.invalidAuthority
                }
                guard let child = children.first else { break }
                guard visited.insert(child.id).inserted,
                      validCorrection(child, prior: current, root: root) else {
                    throw WorkCoordinatorError.invalidAuthority
                }
                current = child
            }
            guard visited.count == revisionGroup.count else {
                throw WorkCoordinatorError.invalidAuthority
            }
        }
    }

    private func revisionTip(
        for root: WorkflowRecord,
        allRecords: [WorkflowRecord]
    ) -> WorkflowRecord? {
        var visited: Set<UUID> = [root.id]
        var current = root
        while true {
            let children = allRecords.filter { $0.revisesRecordID == current.id }
            guard children.count <= 1 else { return nil }
            guard let child = children.first else { return current }
            guard visited.insert(child.id).inserted else { return nil }
            current = child
        }
    }

    private func validCorrection(
        _ correction: WorkflowRecord,
        prior: WorkflowRecord,
        root: WorkflowRecord
    ) -> Bool {
        correction.schemaVersion == 1
            && correction.id != root.id
            && correction.assetID == prior.assetID
            && correction.packetID == prior.packetID
            && correction.issueID == prior.issueID
            && correction.parentRecordID == prior.parentRecordID
            && correction.recordRevisionRootID == root.id
            && correction.revisesRecordID == prior.id
            && correction.evidenceSourceRecordID == root.id
            && correction.revisionKind
                == WorkflowRevisionKind.clericalCorrection.rawValue
            && correction.stage == prior.stage
            && correction.stage != WorkflowStage.work.rawValue
            && correction.state == WorkflowState.completed.rawValue
            && correction.draftStepKey == nil
            && correction.startedAt == prior.startedAt
            && correction.completedAt == prior.completedAt
            && correction.observedAtUTC == prior.observedAtUTC
            && correction.timeZoneID == prior.timeZoneID
            && correction.utcOffsetMinutes == prior.utcOffsetMinutes
            && correction.localDate == prior.localDate
            && correction.localTime == prior.localTime
            && correction.afterDarkAcknowledgementKey
                == prior.afterDarkAcknowledgementKey
            && correction.afterDarkAcknowledgementCopy
                == prior.afterDarkAcknowledgementCopy
            && correction.afterDarkAcknowledgementVersion
                == prior.afterDarkAcknowledgementVersion
            && correction.afterDarkAcknowledgementAccepted
                == prior.afterDarkAcknowledgementAccepted
            && correction.safePositionAcknowledgementKey
                == prior.safePositionAcknowledgementKey
            && correction.safePositionAcknowledgementCopy
                == prior.safePositionAcknowledgementCopy
            && correction.safePositionAcknowledgementVersion
                == prior.safePositionAcknowledgementVersion
            && correction.safePositionAcknowledgementAccepted
                == prior.safePositionAcknowledgementAccepted
            && correction.packID == prior.packID
            && correction.packSchemaVersion == prior.packSchemaVersion
            && correction.packContentVersion == prior.packContentVersion
            && correction.pdfTemplateID == prior.pdfTemplateID
            && correction.pdfTemplateVersion == prior.pdfTemplateVersion
            && correction.outcomeKey == prior.outcomeKey
            && correction.couldNotVerifyKey == prior.couldNotVerifyKey
            && correction.couldNotVerifyDisplaySnapshot
                == prior.couldNotVerifyDisplaySnapshot
            && correction.couldNotVerifyRegistryVersion
                == prior.couldNotVerifyRegistryVersion
            && correction.workPerformedLocalDate == prior.workPerformedLocalDate
            && correction.workDescription == prior.workDescription
            && correction.note != prior.note
            && (correction.note.map({
                validCompletedWorkText($0, maximum: 1_000)
            }) ?? true)
            && correction.finalizationMutationID != nil
    }

    private func validateEvidence(
        _ rows: [EvidenceFile],
        for record: WorkflowRecord
    ) throws {
        let purposes = rows.map(\.purposeKey)
        switch record.stage {
        case WorkflowStage.work.rawValue:
            guard rows.count <= 1,
                  purposes.allSatisfy({ $0 == "work_context" }) else {
                throw WorkCoordinatorError.invalidAuthority
            }
        case WorkflowStage.check.rawValue, WorkflowStage.recheck.rawValue:
            let allowed = Set(["wide_context", "close_detail"])
            if record.outcomeKey == "could_not_verify" {
                guard rows.count <= 2,
                      Set(purposes).count == purposes.count,
                      purposes.allSatisfy(allowed.contains) else {
                    throw WorkCoordinatorError.invalidAuthority
                }
            } else {
                guard rows.count == 2, Set(purposes) == allowed else {
                    throw WorkCoordinatorError.invalidAuthority
                }
            }
        default:
            throw WorkCoordinatorError.invalidAuthority
        }
        for row in rows {
            try validateEvidenceRow(row, record: record)
        }
    }

    private func validateEvidenceRow(
        _ row: EvidenceFile,
        record: WorkflowRecord
    ) throws {
        let canonicalID = row.id.uuidString.lowercased()
        guard row.schemaVersion == 1,
              row.recordID == record.id,
              row.mimeType == "image/jpeg",
              row.relativePath == "evidence/\(canonicalID)/original.jpg",
              row.thumbnailRelativePath
                == "evidence/\(canonicalID)/thumbnail.jpg",
              row.byteCount > 0,
              row.thumbnailByteCount > 0,
              isLowercaseSHA256(row.sha256),
              isLowercaseSHA256(row.thumbnailSHA256),
              row.createdAt >= record.startedAt,
              record.completedAt.map({ row.createdAt <= $0 }) ?? true else {
            throw WorkCoordinatorError.invalidAuthority
        }
        let original = try ReportPDFAnchoredFile.readRegularFile(
            at: generationRootURL.appendingPathComponent(row.relativePath),
            within: generationRootURL,
            rootIdentity: rootIdentity
        )
        let thumbnail = try ReportPDFAnchoredFile.readRegularFile(
            at: generationRootURL.appendingPathComponent(row.thumbnailRelativePath),
            within: generationRootURL,
            rootIdentity: rootIdentity
        )
        guard original.count == row.byteCount,
              thumbnail.count == row.thumbnailByteCount,
              SHA256.hash(data: original).hexString == row.sha256,
              SHA256.hash(data: thumbnail).hexString == row.thumbnailSHA256 else {
            throw WorkCoordinatorError.invalidAuthority
        }
        do {
            _ = try MediaNormalizerV1().validateCanonicalJPEG(
                original,
                kind: .original
            )
            _ = try MediaNormalizerV1().validateCanonicalJPEG(
                thumbnail,
                kind: .thumbnail
            )
        } catch {
            throw WorkCoordinatorError.invalidAuthority
        }
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private func validOpeningRecord(_ record: WorkflowRecord, issue: Issue) -> Bool {
        record.schemaVersion == 1
            && record.assetID == issue.assetID
            && record.issueID == issue.id
            && record.parentRecordID == nil
            && record.recordRevisionRootID == record.id
            && record.revisesRecordID == nil
            && record.evidenceSourceRecordID == nil
            && record.revisionKind == WorkflowRevisionKind.original.rawValue
            && record.stage == WorkflowStage.check.rawValue
            && record.state == WorkflowState.completed.rawValue
            && record.draftStepKey == nil
            && record.packetID != nil
            && record.completedAt.map({ $0 >= record.startedAt }) == true
            && validTimeAndAcknowledgements(record)
            && record.packID == signPack.packID
            && record.packSchemaVersion == signPack.schemaVersion
            && record.packContentVersion == signPack.contentVersion
            && record.pdfTemplateID == Self.pdfTemplateID
            && record.pdfTemplateVersion == 1
            && record.outcomeKey == "visible_issue"
            && record.couldNotVerifyKey == nil
            && record.couldNotVerifyDisplaySnapshot == nil
            && record.couldNotVerifyRegistryVersion == nil
            && record.workPerformedLocalDate == nil
            && record.workDescription == nil
            && (record.note.map({
                validCompletedWorkText($0, maximum: 1_000)
            }) ?? true)
            && record.finalizationMutationID != nil
            && issue.createdAt == record.completedAt
    }

    private func validSubstantiveChild(_ record: WorkflowRecord, issue: Issue) -> Bool {
        guard record.schemaVersion == 1,
              record.assetID == issue.assetID,
              record.issueID == issue.id,
              record.recordRevisionRootID == record.id,
              record.revisesRecordID == nil,
              record.evidenceSourceRecordID == nil,
              record.revisionKind == WorkflowRevisionKind.original.rawValue,
              record.state == WorkflowState.completed.rawValue,
              record.draftStepKey == nil,
              record.completedAt.map({ $0 >= record.startedAt }) == true,
              record.packID == signPack.packID,
              record.packSchemaVersion == signPack.schemaVersion,
              record.packContentVersion == signPack.contentVersion,
              record.pdfTemplateID == Self.pdfTemplateID,
              record.pdfTemplateVersion == 1,
              record.finalizationMutationID != nil else {
            return false
        }
        if record.stage == WorkflowStage.work.rawValue {
            return record.outcomeKey == "work_recorded"
                && record.packetID == nil
                && record.observedAtUTC == nil
                && record.timeZoneID == nil
                && record.utcOffsetMinutes == nil
                && record.localDate == nil
                && record.localTime == nil
                && record.afterDarkAcknowledgementKey == nil
                && record.afterDarkAcknowledgementCopy == nil
                && record.afterDarkAcknowledgementVersion == nil
                && record.afterDarkAcknowledgementAccepted == nil
                && record.safePositionAcknowledgementKey == nil
                && record.safePositionAcknowledgementCopy == nil
                && record.safePositionAcknowledgementVersion == nil
                && record.safePositionAcknowledgementAccepted == nil
                && record.couldNotVerifyKey == nil
                && record.couldNotVerifyDisplaySnapshot == nil
                && record.couldNotVerifyRegistryVersion == nil
                && record.workPerformedLocalDate.map(validLocalDate) == true
                && record.workDescription.map({
                    validCompletedWorkText($0, maximum: 160)
                }) == true
                && (record.note.map({
                    validCompletedWorkText($0, maximum: 1_000)
                }) ?? true)
        }
        if record.stage == WorkflowStage.recheck.rawValue {
            let isCouldNotVerify = record.outcomeKey == "could_not_verify"
            return Self.recheckOutcomes.contains(record.outcomeKey ?? "")
                && record.packetID != nil
                && validTimeAndAcknowledgements(record)
                && record.workPerformedLocalDate == nil
                && record.workDescription == nil
                && (record.note.map({
                    validCompletedWorkText($0, maximum: 1_000)
                }) ?? true)
                && (isCouldNotVerify
                    ? validCouldNotVerify(record)
                    : record.couldNotVerifyKey == nil
                        && record.couldNotVerifyDisplaySnapshot == nil
                        && record.couldNotVerifyRegistryVersion == nil)
        }
        return false
    }

    private func validStatus(_ issue: Issue, terminal: WorkflowRecord) -> Bool {
        switch issue.status {
        case IssueStatus.open.rawValue:
            return terminal.stage == WorkflowStage.check.rawValue
                && terminal.outcomeKey == "visible_issue"
                && terminal.completedAt == issue.updatedAt
        case IssueStatus.recheckDue.rawValue:
            return terminal.stage == WorkflowStage.work.rawValue
                && terminal.outcomeKey == "work_recorded"
                && terminal.completedAt == issue.updatedAt
        default:
            return false
        }
    }

    private func validCompletedWorkText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximum
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validLocalDate(_ value: String) -> Bool {
        guard value.range(
            of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
            options: .regularExpression
        ) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private func validTimeAndAcknowledgements(_ record: WorkflowRecord) -> Bool {
        guard let observedAtUTC = record.observedAtUTC,
              let timeZoneID = record.timeZoneID,
              observedAtUTC == record.startedAt,
              let frozen = try? TimeContextRule.freeze(
                  observedAtUTC: observedAtUTC,
                  confirmedTimeZoneID: timeZoneID
              ),
              frozen.utcOffsetMinutes == record.utcOffsetMinutes,
              frozen.localDate == record.localDate,
              frozen.localTime == record.localTime,
              record.afterDarkAcknowledgementAccepted == true,
              record.safePositionAcknowledgementAccepted == true else {
            return false
        }
        let afterDark = signPack.acknowledgements.filter {
            $0.key == "after_dark"
                && $0.key == record.afterDarkAcknowledgementKey
                && $0.copy == record.afterDarkAcknowledgementCopy
                && $0.version == record.afterDarkAcknowledgementVersion
        }
        let safePosition = signPack.acknowledgements.filter {
            $0.key == "safe_authorized_position"
                && $0.key == record.safePositionAcknowledgementKey
                && $0.copy == record.safePositionAcknowledgementCopy
                && $0.version == record.safePositionAcknowledgementVersion
        }
        return afterDark.count == 1 && safePosition.count == 1
    }

    private func validCouldNotVerify(_ record: WorkflowRecord) -> Bool {
        guard let key = record.couldNotVerifyKey,
              let display = record.couldNotVerifyDisplaySnapshot,
              let version = record.couldNotVerifyRegistryVersion else {
            return false
        }
        return signPack.couldNotVerifyReasons.version == version
            && signPack.couldNotVerifyReasons.entries.filter {
                $0.key == key && $0.display == display
            }.count == 1
    }

    private func requireCleanContext() throws {
        guard !modelContext.hasChanges else {
            throw WorkCoordinatorError.invalidAuthority
        }
    }

    private func requireRootIdentity() throws {
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL) == rootIdentity else {
            throw WorkCoordinatorError.invalidAuthority
        }
    }

    private func uniqueIDs(_ ids: [UUID]) -> Bool {
        Set(ids).count == ids.count
    }

    private func payload(_ record: WorkflowRecord) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: record.id, schemaVersion: record.schemaVersion,
            assetID: record.assetID, packetID: record.packetID,
            issueID: record.issueID, parentRecordID: record.parentRecordID,
            recordRevisionRootID: record.recordRevisionRootID,
            revisesRecordID: record.revisesRecordID,
            evidenceSourceRecordID: record.evidenceSourceRecordID,
            revisionKind: record.revisionKind, stage: record.stage,
            state: record.state, draftStepKey: record.draftStepKey,
            startedAt: record.startedAt, completedAt: record.completedAt,
            observedAtUTC: record.observedAtUTC, timeZoneID: record.timeZoneID,
            utcOffsetMinutes: record.utcOffsetMinutes, localDate: record.localDate,
            localTime: record.localTime,
            afterDarkAcknowledgementKey: record.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: record.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: record.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: record.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: record.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: record.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: record.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: record.safePositionAcknowledgementAccepted,
            packID: record.packID, packSchemaVersion: record.packSchemaVersion,
            packContentVersion: record.packContentVersion,
            pdfTemplateID: record.pdfTemplateID,
            pdfTemplateVersion: record.pdfTemplateVersion,
            outcomeKey: record.outcomeKey,
            couldNotVerifyKey: record.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: record.workPerformedLocalDate,
            workDescription: record.workDescription, note: record.note,
            finalizationMutationID: record.finalizationMutationID
        )
    }

    private func payload(_ issue: Issue) -> IssuePayloadV1 {
        IssuePayloadV1(
            id: issue.id, schemaVersion: issue.schemaVersion,
            assetID: issue.assetID, openedByRecordID: issue.openedByRecordID,
            labelKey: issue.labelKey,
            labelDisplaySnapshot: issue.labelDisplaySnapshot,
            status: issue.status, resolvedByRecordID: issue.resolvedByRecordID,
            createdAt: issue.createdAt, updatedAt: issue.updatedAt
        )
    }

    private func apply(_ value: WorkflowRecordPayloadV1, to record: WorkflowRecord) {
        record.packetID = value.packetID
        record.issueID = value.issueID
        record.parentRecordID = value.parentRecordID
        record.revisesRecordID = value.revisesRecordID
        record.evidenceSourceRecordID = value.evidenceSourceRecordID
        record.revisionKind = value.revisionKind
        record.stage = value.stage
        record.state = value.state
        record.draftStepKey = value.draftStepKey
        record.completedAt = value.completedAt
        record.observedAtUTC = value.observedAtUTC
        record.timeZoneID = value.timeZoneID
        record.utcOffsetMinutes = value.utcOffsetMinutes
        record.localDate = value.localDate
        record.localTime = value.localTime
        record.afterDarkAcknowledgementKey = value.afterDarkAcknowledgementKey
        record.afterDarkAcknowledgementCopy = value.afterDarkAcknowledgementCopy
        record.afterDarkAcknowledgementVersion = value.afterDarkAcknowledgementVersion
        record.afterDarkAcknowledgementAccepted = value.afterDarkAcknowledgementAccepted
        record.safePositionAcknowledgementKey = value.safePositionAcknowledgementKey
        record.safePositionAcknowledgementCopy = value.safePositionAcknowledgementCopy
        record.safePositionAcknowledgementVersion = value.safePositionAcknowledgementVersion
        record.safePositionAcknowledgementAccepted = value.safePositionAcknowledgementAccepted
        record.outcomeKey = value.outcomeKey
        record.couldNotVerifyKey = value.couldNotVerifyKey
        record.couldNotVerifyDisplaySnapshot = value.couldNotVerifyDisplaySnapshot
        record.couldNotVerifyRegistryVersion = value.couldNotVerifyRegistryVersion
        record.workPerformedLocalDate = value.workPerformedLocalDate
        record.workDescription = value.workDescription
        record.note = value.note
        record.finalizationMutationID = value.finalizationMutationID
    }

    private func restore(_ value: WorkflowRecordPayloadV1, to record: WorkflowRecord) {
        apply(value, to: record)
    }

    private func apply(_ value: IssuePayloadV1, to issue: Issue) {
        issue.status = value.status
        issue.resolvedByRecordID = value.resolvedByRecordID
        issue.updatedAt = value.updatedAt
    }

    private func restore(_ value: IssuePayloadV1, to issue: Issue) {
        apply(value, to: issue)
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

@MainActor
protocol WorkspaceWriterAdapterPortV1: AnyObject {
    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1
    func rollback()
}

extension WorkspaceWriterAdapterPortV1 {
    func rollback() {}
}

@MainActor
final class WorkspaceWriterV1: WorkspaceQueryClientV1 {
    static let defaultMaximumRememberedMutationCount = 10_000

    private struct RememberedMutation {
        let digest: String
        let outcome: WorkspaceMutationOutcomeV1
    }

    private let identity: WorkspaceReplicaIdentityV1
    private let generationID: UUID
    private let writerInstanceID: UUID
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileAuthority: any ApplicationFileAuthorityV1
    private let adapter: any WorkspaceWriterAdapterPortV1
    private let journalStore: MutationJournalStoreV1?
    private let maximumRememberedMutationCount: Int

    private var workspaceRevision: UInt64
    private var entityRevisions: [WorkspaceEntityIdentityV1: UInt64]
    private var remembered: [MutationIDV1: RememberedMutation] = [:]
    private var quarantined: Set<MutationIDV1> = []
    private var isExecuting = false
    private var isActive = true

    init(
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        initialRevision: WorkspaceRevisionV1,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        adapter: any WorkspaceWriterAdapterPortV1,
        journalStore: MutationJournalStoreV1? = nil,
        maximumRememberedMutationCount: Int = WorkspaceWriterV1.defaultMaximumRememberedMutationCount
    ) throws {
        guard initialRevision.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard initialRevision.generationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        guard maximumRememberedMutationCount > 0 else {
            throw WorkspaceMutationFailureV1.idempotencyCapacityReached
        }
        self.identity = identity
        self.generationID = generationID
        let instanceID = idSource.makeID()
        guard instanceID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        writerInstanceID = instanceID
        self.workspaceRevision = initialRevision.revision
        self.entityRevisions = Dictionary(
            uniqueKeysWithValues: initialRevision.entityRevisions.map { ($0.identity, $0.revision) }
        )
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.adapter = adapter
        self.journalStore = journalStore
        self.maximumRememberedMutationCount = maximumRememberedMutationCount
    }

    func makeMutationID() throws -> MutationIDV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        return try MutationIDV1(rawValue: idSource.makeID())
    }

    func currentRevision() throws -> WorkspaceRevisionV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        if let journalStore {
            return try journalStore.currentRevision(writerInstanceID: writerInstanceID)
        }
        return try WorkspaceRevisionV1(
            workspaceID: identity.workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            revision: workspaceRevision,
            entityRevisions: entityRevisions.map {
                WorkspaceEntityRevisionV1(identity: $0.key, revision: $0.value)
            }
        )
    }

    /// This operation is synchronous by design: no canonical transaction can
    /// suspend and admit another command on the main actor.
    func execute(_ request: WorkspaceMutationRequestV1) throws -> WorkspaceMutationOutcomeV1 {
        try executeInternal(request, reversalPlan: nil, semanticReversalExecution: nil, semanticReversalReplayIdentitySHA256: nil)
    }

    func execute(
        _ request: WorkspaceMutationRequestV1,
        reversalPlan: SemanticReversalPlanV1
    ) throws -> WorkspaceMutationOutcomeV1 {
        try executeInternal(request, reversalPlan: reversalPlan, semanticReversalExecution: nil, semanticReversalReplayIdentitySHA256: nil)
    }

    func executeSemanticReversal(
        _ request: WorkspaceMutationRequestV1,
        targetMutationID: MutationIDV1,
        plan: SemanticReversalPlanV1,
        compensatingMutationIDs: [MutationIDV1]
    ) throws -> WorkspaceMutationOutcomeV1 {
        let replayIdentity = try SemanticReversalReplayIdentityV1(
            request: request,
            identity: identity,
            targetMutationID: targetMutationID,
            planDigest: plan.planDigest,
            compensatingMutationIDs: compensatingMutationIDs
        )
        let replayIdentitySHA256 = try replayIdentity.canonicalSHA256()
        let replayObservedAt = clock.now()
        if let journalStore,
           let prior = try journalStore.resolveSemanticReversalReplay(
             request: request,
             replayIdentitySHA256: replayIdentitySHA256,
             detectedAt: replayObservedAt
           ) {
            return try outcome(
                from: prior,
                request: request,
                digest: prior.envelopeSHA256,
                occurredAt: replayObservedAt
            )
        }
        guard let journalStore,
              plan.mutationID == targetMutationID,
              plan.compensatingCommands.count == 1,
              plan.compensatingCommands.first == request.command,
              compensatingMutationIDs == [request.mutationID],
              let target = try journalStore.receipt(mutationID: targetMutationID),
              let basis = try journalStore.reversalBasis(mutationID: targetMutationID),
              basis.planDigest == plan.planDigest,
              basis.compensatingCommandKinds == plan.compensatingCommands.map(\.kind) else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        let execution = try SemanticReversalExecutionV1(
            targetMutationID: targetMutationID,
            targetReceiptIdentity: target.identity,
            reversalBasisSHA256: basis.canonicalSHA256(),
            planDigest: plan.planDigest,
            compensatingMutationIDs: compensatingMutationIDs
        )
        return try executeInternal(
            request,
            reversalPlan: nil,
            semanticReversalExecution: execution,
            semanticReversalReplayIdentitySHA256: replayIdentitySHA256
        )
    }

    private func executeInternal(
        _ request: WorkspaceMutationRequestV1,
        reversalPlan: SemanticReversalPlanV1?,
        semanticReversalExecution: SemanticReversalExecutionV1?,
        semanticReversalReplayIdentitySHA256: String?
    ) throws -> WorkspaceMutationOutcomeV1 {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard !isExecuting else { throw WorkspaceMutationFailureV1.persistenceFailed }
        let envelope: MutationEnvelopeV1
        let digest: String
        do {
            envelope = try MutationEnvelopeV1(
                request: request,
                identity: identity,
                sourceKind: semanticReversalExecution == nil ? .localUser : .semanticReversal,
                causationMutationID: semanticReversalExecution?.targetMutationID,
                reversalPlanDigest: reversalPlan?.planDigest,
                semanticReversalReplayIdentitySHA256: semanticReversalReplayIdentitySHA256,
                semanticReversalExecution: semanticReversalExecution
            )
            digest = try envelope.canonicalSHA256()
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        let occurredAt = clock.now()
        if let journalStore,
           let prior = try journalStore.resolveReplay(envelope: envelope, detectedAt: occurredAt) {
            return try outcome(from: prior, request: request, digest: digest, occurredAt: occurredAt)
        }

        guard !quarantined.contains(request.mutationID) else {
            throw WorkspaceMutationFailureV1.mutationIDQuarantined
        }
        if let prior = remembered[request.mutationID] {
            guard prior.digest == digest else {
                quarantined.insert(request.mutationID)
                throw WorkspaceMutationFailureV1.mutationIDQuarantined
            }
            return prior.outcome
        }
        guard remembered.count < maximumRememberedMutationCount else {
            throw WorkspaceMutationFailureV1.idempotencyCapacityReached
        }

        let targets = try Self.targetIdentities(for: request.command)
        try require(request.expectedRevision, targets: targets)
        let liveRevision = try currentRevision()
        let liveByIdentity = Dictionary(uniqueKeysWithValues: liveRevision.entityRevisions.map { ($0.identity, $0.revision) })
        guard liveRevision.revision < UInt64(Int64.max),
              targets.allSatisfy({ liveByIdentity[$0, default: 0] < UInt64(Int64.max) }) else {
            throw WorkspaceMutationFailureV1.revisionOverflow
        }

        let before = try currentRevision()
        let temporaryRelativePath: String
        do {
            temporaryRelativePath = try fileAuthority.temporaryRelativePath(
                mutationID: request.mutationID,
                component: request.command.kind.rawValue
            )
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard !temporaryRelativePath.isEmpty,
              !temporaryRelativePath.hasPrefix("/"),
              !temporaryRelativePath.contains("..") else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: targets,
            temporaryRelativePath: temporaryRelativePath
        )

        isExecuting = true
        defer { isExecuting = false }
        do {
            let applied = try adapter.apply(
                request.command,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
            guard applied == effect else {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            if let journalStore {
                try journalStore.reach(.afterEffectBeforeReceipt)
                let basis: ReversalBasisV1?
                if let reversalPlan {
                    guard reversalPlan.mutationID == request.mutationID,
                          reversalPlan.commandKind == request.command.kind,
                          reversalPlan.expectedRevision == request.expectedRevision else {
                        throw WorkspaceMutationFailureV1.invalidReversal
                    }
                    basis = try ReversalBasisV1(
                        targetMutationID: request.mutationID,
                        targetReceiptIdentity: MutationReceiptIdentityV1(
                            workspaceID: identity.workspaceID,
                            replicaID: identity.replicaID,
                            localSequence: try journalStore.nextLocalSequence()
                        ),
                        plan: reversalPlan
                    )
                } else {
                    basis = nil
                }
                let receipt = try journalStore.commit(
                    envelope: envelope,
                    writerInstanceID: writerInstanceID,
                    affectedEntities: applied.affectedEntities,
                    committedAt: occurredAt,
                    reversalBasis: basis,
                    semanticReversalExecution: semanticReversalExecution
                )
                let after = try revision(from: receipt.resultingRevision)
                return WorkspaceMutationOutcomeV1(
                    mutationID: request.mutationID,
                    commandDigest: digest,
                    occurredAt: occurredAt,
                    before: before,
                    after: after,
                    effect: applied
                )
            }
        } catch let failure as MutationJournalFailureV1 {
            adapter.rollback()
            throw failure
        } catch let error as WorkspaceMutationFailureV1 {
            adapter.rollback()
            throw error
        } catch {
            adapter.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }

        workspaceRevision += 1
        for target in targets { entityRevisions[target, default: 0] += 1 }
        let after = try currentRevision()
        let outcome = WorkspaceMutationOutcomeV1(
            mutationID: request.mutationID,
            commandDigest: digest,
            occurredAt: occurredAt,
            before: before,
            after: after,
            effect: effect
        )
        remembered[request.mutationID] = RememberedMutation(digest: digest, outcome: outcome)
        return outcome
    }

    func durableReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1? {
        guard isActive else { throw WorkspaceMutationFailureV1.writerInvalidated }
        guard let journalStore else { return nil }
        return try journalStore.receipt(mutationID: mutationID)
    }

    func invalidate() {
        isActive = false
        remembered.removeAll(keepingCapacity: false)
        quarantined.removeAll(keepingCapacity: false)
    }

    private func require(
        _ expected: WorkspaceExpectedRevisionV1,
        targets: [WorkspaceEntityIdentityV1]
    ) throws {
        guard expected.workspaceID == identity.workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        guard expected.generationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        guard expected.writerInstanceID == writerInstanceID else {
            throw WorkspaceMutationFailureV1.wrongWriterInstance
        }
        let current = try currentRevision()
        guard expected.workspaceRevision == current.revision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let expectedByID = Dictionary(
            uniqueKeysWithValues: expected.entityRevisions.map { ($0.identity, $0.revision) }
        )
        guard targets.allSatisfy({ expectedByID[$0] != nil }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let currentByID = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        for identity in targets where expectedByID[identity, default: 0] != currentByID[identity, default: 0] {
            throw WorkspaceMutationFailureV1.staleEntityRevision(identity)
        }
    }

    private func outcome(
        from receipt: MutationReceiptV1,
        request: WorkspaceMutationRequestV1,
        digest: String,
        occurredAt: Date
    ) throws -> WorkspaceMutationOutcomeV1 {
        let temporaryRelativePath = try fileAuthority.temporaryRelativePath(
            mutationID: request.mutationID,
            component: request.command.kind.rawValue
        )
        let entities = try receipt.postImages.map { try $0.identity }
        return WorkspaceMutationOutcomeV1(
            mutationID: receipt.mutationID,
            commandDigest: digest,
            occurredAt: receipt.committedAt,
            before: try revision(from: receipt.expectedRevision),
            after: try revision(from: receipt.resultingRevision),
            effect: try WorkspaceMutationEffectV1(
                affectedEntities: entities,
                temporaryRelativePath: temporaryRelativePath
            )
        )
    }

    private func revision(from value: MutationPortableExpectedRevisionV1) throws -> WorkspaceRevisionV1 {
        try WorkspaceRevisionV1(
            workspaceID: value.workspaceID,
            generationID: value.generationID,
            writerInstanceID: writerInstanceID,
            revision: value.workspaceRevision,
            entityRevisions: value.entityRevisions
        )
    }

    private static func targetIdentities(
        for command: WorkspaceCommandV1
    ) throws -> [WorkspaceEntityIdentityV1] {
        let values: [WorkspaceEntityIdentityV1]
        switch command {
        case let .createFirstSign(value):
            var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
            if let site = value.newSite {
                identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
            }
            values = identities
        case let .createCheckDraft(value):
            values = [try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID)]
        case let .acceptCheckEvidence(value):
            values = try [
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.draftID),
                WorkspaceEntityIdentityV1(kind: .evidenceFile, id: value.evidenceID),
            ]
        case let .updateSiteTimeZone(value):
            values = [try WorkspaceEntityIdentityV1(kind: .site, id: value.siteID)]
        case let .deleteAsset(value):
            try requireOperationID(value.deletionID)
            try requireDigest(value.planDigest)
            values = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        case let .deleteSite(value):
            try requireOperationID(value.deletionID)
            try requireDigest(value.planDigest)
            values = [try WorkspaceEntityIdentityV1(kind: .site, id: value.siteID)]
        case let .eraseWorkspace(value):
            try requireOperationID(value.eraseID)
            try requireOperationID(value.targetGenerationID)
            try requireDigest(value.oldPointerDigest)
            try requireDigest(value.emptyLedgerDigest)
            values = []
        case let .finalizeCheck(value):
            try requireOperationID(value.finalizationMutationID)
            try requireDigest(value.semanticDigest)
            guard value.contentDigests.count <= 256,
                  Set(value.contentDigests).count == value.contentDigests.count else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            try value.contentDigests.forEach { try requireDigest($0) }
            var identities = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID),
                WorkspaceEntityIdentityV1(kind: .packet, id: value.packetID),
                WorkspaceEntityIdentityV1(kind: .report, id: value.reportID),
            ]
            if let issueID = value.issueID {
                identities.append(try WorkspaceEntityIdentityV1(kind: .issue, id: issueID))
            }
            values = identities
        case let .finalizeCorrection(value):
            try requireOperationID(value.finalizationMutationID)
            try requireDigest(value.semanticDigest)
            values = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.correctionRecordID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.revisesRecordID),
                WorkspaceEntityIdentityV1(kind: .packet, id: value.packetID),
                WorkspaceEntityIdentityV1(kind: .report, id: value.reportID),
                WorkspaceEntityIdentityV1(kind: .report, id: value.replacesReportID),
            ]
        case let .recordWork(value):
            try requireOperationID(value.workMutationID)
            try requireDigest(value.semanticDigest)
            guard value.evidenceIDs.count <= 256,
                  Set(value.evidenceIDs).count == value.evidenceIDs.count else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            var identities = try [
                WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                WorkspaceEntityIdentityV1(kind: .issue, id: value.issueID),
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID),
            ]
            identities.append(contentsOf: try value.evidenceIDs.map {
                try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: $0)
            })
            values = identities
        case let .restoreWorkspace(value):
            try requireOperationID(value.restoreID)
            try requireOperationID(value.targetGenerationID)
            try requireDigest(value.sourceArchiveDigest)
            guard BackupRestoreMode(rawValue: value.mode) != nil else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            values = []
        case let .archiveEntities(value):
            guard value.identities.count <= 256,
                  !value.reason.isEmpty,
                  value.reason.count <= 4_096 else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            values = value.identities
        }
        guard Set(values).count == values.count else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return values
    }

    private static func requireOperationID(_ value: UUID) throws {
        _ = try MutationIDV1(rawValue: value)
    }

    private static func requireDigest(_ value: String) throws {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

}

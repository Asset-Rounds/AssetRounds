import CryptoKit
import Foundation

/// The device-local, derived delivery projection over the immutable mutation journal.
/// Canonical receipts and reversal bases remain owned by `MutationJournalStoreV1`.
@MainActor
final class LocalChangeJournalV1 {
    static func partyAccountabilityCoverage() throws -> PartyAccountabilityJournalCoverageV1 {
        try PartyAccountabilityJournalCoverageV1()
    }
    static func assetSemanticCoverage() throws -> AssetSemanticJournalCoverageV1 {
        try AssetSemanticJournalCoverageV1()
    }
    static func recoverabilityVerificationCoverage() throws -> RecoverabilityVerificationJournalCoverageV1 {
        let coverage = RecoverabilityVerificationJournalCoverageV1()
        try coverage.validate()
        return coverage
    }
    typealias ConflictPolicyResolver = (WorkspaceEntityIdentityV1, MutationPostImageV1) throws -> ConflictPolicyV1
    typealias ContentReferenceResolver = (String) throws -> ContentReferenceV1
    typealias ContentEntryResolver = (ContentReferenceV1) throws -> LocalContentStoreEntryV1
    typealias PortableReversalPlanResolver = (ReversalBasisV1, MutationReceiptV1) throws -> PortableReversalPlanV1?

    struct CheckpointSupplementV1: Equatable, Sendable {
        let contentEntries: [CheckpointContentEntryV1]
        let reversalEligibility: [ReversalEligibilitySnapshotV1]

        init(
            contentEntries: [CheckpointContentEntryV1],
            reversalEligibility: [ReversalEligibilitySnapshotV1]
        ) {
            self.contentEntries = contentEntries
            self.reversalEligibility = reversalEligibility
        }

    }

    enum InterruptionPointV1: Equatable, Sendable {
        case none
        case afterCheckpointPrepared
        case afterCheckpointStateWritten
        case afterReplayMutation(Int)
        case afterCompactionStateWritten
    }

    struct ReplayResultV1: Equatable, Sendable {
        let receipt: ChangeReplayReceiptV1
        let nextCursor: ChangeCursorV1
        let isDeferred: Bool
    }

    private struct DurableState: Codable {
        static let schemaVersion = 1
        let schemaVersion: Int
        var checkpoints: [WorkspaceCheckpointContentV1]
        var checkpointFloor: WorkspaceSnapshotManifestV1?
        var replayReceipts: [ChangeReplayReceiptV1]
        var replayCursors: [ChangeCursorV1]
        var conflictResolutions: [ConflictResolutionBasisV1]
        var unresolvedConflicts: [ConflictIdentityV1]
        var observedConflictInputs: [ObservedConflictInputs]
        var pendingBatches: [ChangeBatchV1]
        var pendingReplayBases: [PendingReplayBasis]
        var contentQuarantines: [DerivedContentQuarantine]

        init() {
            schemaVersion = Self.schemaVersion
            checkpoints = []
            checkpointFloor = nil
            replayReceipts = []
            replayCursors = []
            conflictResolutions = []
            unresolvedConflicts = []
            observedConflictInputs = []
            pendingBatches = []
            pendingReplayBases = []
            contentQuarantines = []
        }
    }

    private let identity: WorkspaceReplicaIdentityV1
    private let generationID: UUID
    private let generationRootURL: URL
    private let writer: WorkspaceWriterV1
    private let backupExport: BackupExportService
    private let limits: ChangeJournalLimitsV1
    private let policyResolver: ConflictPolicyResolver
    private let contentReferenceResolver: ContentReferenceResolver
    private let contentEntryResolver: ContentEntryResolver
    private let portableReversalPlanResolver: PortableReversalPlanResolver
    private let fileManager: FileManager
    private let makeUUID: () -> UUID
    private let interruptionPoint: () -> InterruptionPointV1
    private var state: DurableState

    init(
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        generationRootURL: URL,
        writer: WorkspaceWriterV1,
        backupExport: BackupExportService,
        limits: ChangeJournalLimitsV1 = try! ChangeJournalLimitsV1(),
        policyResolver: @escaping ConflictPolicyResolver,
        contentReferenceResolver: @escaping ContentReferenceResolver,
        contentEntryResolver: @escaping ContentEntryResolver,
        portableReversalPlanResolver: @escaping PortableReversalPlanResolver = { _, _ in nil },
        fileManager: FileManager = .default,
        makeUUID: @escaping () -> UUID = UUID.init,
        interruptionPoint: @escaping () -> InterruptionPointV1 = { .none }
    ) throws {
        try limits.validate()
        guard generationID != Self.zero else { throw ChangeJournalFailureV1.wrongGeneration }
        self.identity = identity
        self.generationID = generationID
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.writer = writer
        self.backupExport = backupExport
        self.limits = limits
        self.policyResolver = policyResolver
        self.contentReferenceResolver = contentReferenceResolver
        self.contentEntryResolver = contentEntryResolver
        self.portableReversalPlanResolver = portableReversalPlanResolver
        self.fileManager = fileManager
        self.makeUUID = makeUUID
        self.interruptionPoint = interruptionPoint
        state = DurableState()
        try recoverInterruptedWork()
    }

    var activeCheckpoint: WorkspaceCheckpointContentV1? {
        state.checkpoints.last
    }

    var logicalCheckpointFloor: WorkspaceSnapshotManifestV1? {
        state.checkpointFloor
    }

    /// Immutable accepted receipts are the sole C17 projection input. This
    /// method exposes no writer, provider, or canonical mutation seam.
    func acceptedReceiptsForIntegrationProjection() throws -> [MutationReceiptV1] {
        let snapshot = try writer.sourceMutationHistorySnapshot()
        guard snapshot.receipts.count <= ChangeJournalLimitsV1.productionMaximumEntitiesPerCheckpoint else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let receipts = try snapshot.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
        }.sorted {
            if $0.resultingRevision.workspaceRevision != $1.resultingRevision.workspaceRevision {
                return $0.resultingRevision.workspaceRevision < $1.resultingRevision.workspaceRevision
            }
            return $0.identity.stableKey < $1.identity.stableKey
        }
        guard receipts.allSatisfy({
            $0.identity.workspaceID == identity.workspaceID
        }), Set(receipts.map(\.identity)).count == receipts.count,
              Set(receipts.map { $0.resultingRevision.workspaceRevision }).count == receipts.count else {
            throw IntegrationEventFailureV1.divergentEvent
        }
        try receipts.forEach { try IntegrationEventProjectionV1.validatePackagePromotionReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validateMeasurementIntegrityReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validatePrivacyTransformReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validateClientCapabilityReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validateFieldReferenceReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validateAccessibleDocumentAssessmentReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validateSurveyDefinitionReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validateSurveySessionReceiptShape($0) }
        try receipts.forEach { try IntegrationEventProjectionV1.validateAssetLocatorReceiptShape($0) }
        return receipts
    }

    func advanceIntegrationProjection(
        using consumer: IntegrationConformanceConsumerV1
    ) async throws -> IntegrationEventConsumerResultV1 {
        try await consumer.advance(
            workspaceID: identity.workspaceID,
            acceptedReceipts: acceptedReceiptsForIntegrationProjection()
        )
    }

    func rebuildIntegrationProjection(
        using consumer: IntegrationConformanceConsumerV1
    ) async throws -> IntegrationEventConsumerResultV1 {
        try await consumer.rebuild(
            workspaceID: identity.workspaceID,
            acceptedReceipts: acceptedReceiptsForIntegrationProjection()
        )
    }

    /// Derives the recovery-point frontier from the same immutable checkpoint
    /// manifest used by journal replay.  No staging, archive, or canonical
    /// workspace bytes are written by this projection.
    func recoveryPointFrontier(checkpointID: String? = nil) throws -> RecoveryPointFrontierV1 {
        let checkpoint = try resolvedCheckpoint(checkpointID)
        let frontier = checkpoint.manifest.frontier
        return try RecoveryPointFrontierV1(
            workspaceRevision: frontier.workspaceRevision,
            lastLocalSequence: checkpointLocalSequence(frontier),
            checkpointID: checkpoint.manifest.checkpointID,
            checkpointFrontierSHA256: try frontier.canonicalSHA256()
        )
    }

    /// Explicit spelling for callers that need to distinguish the current
    /// journal recovery point from a caller-selected historical checkpoint.
    func currentRecoveryPointFrontier() throws -> RecoveryPointFrontierV1 {
        try recoveryPointFrontier()
    }

    /// Validates a C22 receipt at the journal boundary without storing a
    /// second receipt family.  Staging is optional because it is disposable
    /// and may already have been purged after cleanup.
    func validateRecoverabilityVerificationReceipt(
        _ receipt: RecoverabilityVerificationReceiptV1,
        staging: RecoverabilityVerificationStagingV1? = nil
    ) throws {
        guard receipt.workspaceID == identity.workspaceID else {
            throw ChangeJournalFailureV1.wrongWorkspace
        }
        let coverage = try Self.recoverabilityVerificationCoverage()
        try coverage.validate(staging: staging, receipt: receipt)
    }

    /// Compares an immutable receipt with the current journal/archive binding
    /// while preserving historic-noncurrent semantics for a changed archive.
    func recoverabilityFreshnessProjection(
        for receipt: RecoverabilityVerificationReceiptV1,
        currentArchiveSHA256: String,
        checkpointID: String? = nil
    ) throws -> RecoverabilityFreshnessProjectionV1 {
        try validateRecoverabilityVerificationReceipt(receipt)
        return try RecoverabilityFreshnessProjectionV1.derive(
            receipt: receipt,
            currentArchiveSHA256: currentArchiveSHA256,
            currentSourceFrontier: recoveryPointFrontier(checkpointID: checkpointID)
        )
    }

    /// Converts a completed journal replay into the canonical C22 replay
    /// receipt.  The caller supplies the two canonical-state digests produced
    /// by isolated restore/replay; a deferred or rejected journal result can
    /// never be represented as a completed recovery proof.
    func deterministicRecoveryReplayReceipt(
        from result: ReplayResultV1,
        checkpointID: String,
        restoredCanonicalStateSHA256: String,
        replayedCanonicalStateSHA256: String
    ) throws -> DeterministicRecoveryReplayReceiptV1 {
        guard !result.isDeferred,
              result.receipt.dispositions.allSatisfy({
                  switch $0.disposition {
                  case .applied, .alreadyApplied, .deleteWon, .derivedRebuild, .localOnlyExcluded:
                      return true
                  case .deferredGap, .deferredContent, .unresolvedConflict, .rejected:
                      return false
                  }
              }) else {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        return try DeterministicRecoveryReplayReceiptV1(
            checkpointID: checkpointID,
            orderedMutationCount: result.receipt.dispositions.count,
            orderedMutationDigestSHA256: result.receipt.batchSHA256,
            restoredCanonicalStateSHA256: restoredCanonicalStateSHA256,
            replayedCanonicalStateSHA256: replayedCanonicalStateSHA256
        )
    }

    func prepareCheckpoint(
        supplement: CheckpointSupplementV1
    ) throws -> WorkspaceCheckpointPreparationV1 {
        let checkpoint = try makeCheckpoint(supplement: supplement)
        let entries = try checkpointArchiveEntries(checkpoint)
        let preparation = try WorkspaceCheckpointPreparationV1(
            preparationID: makeUUID(),
            manifest: checkpoint.manifest,
            entries: entries,
            limits: limits
        )
        try persistPrepared(checkpoint, preparation: preparation)
        if interruptionPoint() == .afterCheckpointPrepared {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        return preparation
    }

    /// Publishes only the exactly prepared and revalidated checkpoint.
    func activatePreparedCheckpoint(
        _ preparation: WorkspaceCheckpointPreparationV1
    ) throws -> CheckpointActivationReceiptV1 {
        try preparation.validate(limits: limits)
        let prepared = try loadPrepared(preparation.preparationID)
        guard prepared.manifest == preparation.manifest,
              try checkpointArchiveEntries(prepared) == preparation.entries else {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        let verification = try verifiedContentDisposition(
            prepared.contentEntries.map(\.reference)
        )
        let projection = try semanticProjection(
            checkpoint: prepared,
            unresolvedConflicts: state.unresolvedConflicts
        )
        state.checkpoints.removeAll { $0.manifest.checkpointID == prepared.manifest.checkpointID }
        state.checkpoints.append(prepared)
        state.checkpoints.sort {
            if $0.manifest.frontier.workspaceRevision != $1.manifest.frontier.workspaceRevision {
                return $0.manifest.frontier.workspaceRevision < $1.manifest.frontier.workspaceRevision
            }
            return $0.manifest.checkpointID < $1.manifest.checkpointID
        }
        try persistState()
        if interruptionPoint() == .afterCheckpointStateWritten {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        try removePrepared(preparation.preparationID)
        return try CheckpointActivationReceiptV1(
            workspaceID: identity.workspaceID,
            destinationReplicaID: identity.replicaID,
            destinationGenerationID: generationID,
            manifest: prepared.manifest,
            activatedFrontier: prepared.manifest.frontier,
            semanticProjectionSHA256: projection.semanticSHA256,
            contentDispositionSHA256: verification,
            limits: limits
        )
    }

    /// Freezes the canonical checkpoint payload represented by a preparation.
    /// Callers may transport these exact bytes but may not substitute a
    /// differently encoded or partially populated package.
    func exportPreparedCheckpoint(
        _ preparation: WorkspaceCheckpointPreparationV1,
        packageRelativePath: String
    ) throws -> (export: WorkspaceCheckpointExportV1, packageData: Data) {
        try preparation.validate(limits: limits)
        let checkpoint = try loadPrepared(preparation.preparationID)
        let data = try WorkspaceMutationCanonicalV1.data(checkpoint)
        let decoded = try Self.decoder.decode(WorkspaceCheckpointContentV1.self, from: data)
        try decoded.validate(limits: limits)
        guard decoded == checkpoint,
              try WorkspaceMutationCanonicalV1.data(decoded) == data else {
            throw ChangeJournalFailureV1.tamperedBatch
        }
        let value = try WorkspaceCheckpointExportV1(
            preparation: preparation,
            packageRelativePath: packageRelativePath,
            packageByteCount: Int64(data.count),
            packageSHA256: Self.rawSHA256(data),
            limits: limits
        )
        return (value, data)
    }

    /// Publishes a transported checkpoint only after an existing restore
    /// authority has made the destination's normalized semantic state equal to
    /// the transported snapshot. This method never writes canonical models.
    func installImportedCheckpoint(
        export: WorkspaceCheckpointExportV1,
        packageData: Data
    ) throws -> CheckpointActivationReceiptV1 {
        try export.validate()
        guard export.workspaceID == identity.workspaceID,
              export.packageByteCount == Int64(packageData.count),
              export.packageSHA256 == Self.rawSHA256(packageData) else {
            throw ChangeJournalFailureV1.tamperedBatch
        }
        let checkpoint = try Self.decoder.decode(
            WorkspaceCheckpointContentV1.self,
            from: packageData
        )
        try checkpoint.validate(limits: limits)
        guard try WorkspaceMutationCanonicalV1.data(checkpoint) == packageData,
              checkpoint.manifest.workspaceID == identity.workspaceID,
              checkpoint.manifest.sourceReplicaID != identity.replicaID,
              checkpoint.manifest.checkpointID == export.checkpointID,
              checkpoint.manifest.manifestSHA256 == export.manifestSHA256 else {
            throw ChangeJournalFailureV1.tamperedBatch
        }
        let verification = try verifiedContentDisposition(
            checkpoint.contentEntries.map(\.reference)
        )
        let destination = try backupExport.canonicalCheckpointBasis()
        let history = try writer.sourceMutationHistorySnapshot()
        let destinationPackages = try packageDigests(destination.packageReleases)
        let destinationFrontier = try frontier(history)
        let destinationTombstones = try tombstones(history)
        let destinationMutationIDs = Set(try mutationIDs(history))
        let checkpointMutationIDs = Set(
            checkpoint.reversalEligibility.map(\.targetMutationID)
        )
        let persistentSchemaSHA256 = try Self.sha256(PersistentSchemaDigestBasis(
            persistentSchemaVersion: destination.persistentSchemaVersion,
            compatibilityID: try persistentCompatibilityID(destination.persistentSchemaVersion),
            modelNames: CurrentSyncClassificationCatalogV1.activePersistentModelNames
        ))
        let recordSchemaSHA256 = try Self.sha256(RecordSchemaDigestBasis(
            recordsSchemaVersion: destination.recordsSchemaVersion,
            orderedFields: Self.backupRecordFields(
                for: destination.recordsSchemaVersion
            )
        ))
        guard destination.workspaceIdentity == identity,
              destination.generationID == generationID,
              destination.workspaceRevision == history.workspaceRevision,
              destination.lastLocalSequence == history.lastLocalSequence,
              destination.persistentSchemaVersion == checkpoint.manifest.persistentSchemaVersion,
              destination.recordsSchemaVersion == checkpoint.manifest.recordSchemaVersion,
              persistentSchemaSHA256 == checkpoint.manifest.persistentSchemaSHA256,
              recordSchemaSHA256 == checkpoint.manifest.recordSchemaSHA256,
              destinationPackages == checkpoint.manifest.packages,
              destinationFrontier == checkpoint.manifest.frontier,
              destinationTombstones == checkpoint.tombstoneIdentities,
              destinationMutationIDs == checkpointMutationIDs,
              Self.rawSHA256(destination.semanticRecordsData)
                == checkpoint.manifest.normalizedRecordsSHA256 else {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        let projection = try semanticProjection(
            checkpoint: checkpoint,
            unresolvedConflicts: state.unresolvedConflicts
        )
        state.checkpoints.removeAll {
            $0.manifest.checkpointID == checkpoint.manifest.checkpointID
        }
        state.checkpoints.append(checkpoint)
        state.checkpoints.sort {
            if $0.manifest.frontier.workspaceRevision != $1.manifest.frontier.workspaceRevision {
                return $0.manifest.frontier.workspaceRevision < $1.manifest.frontier.workspaceRevision
            }
            return $0.manifest.checkpointID < $1.manifest.checkpointID
        }
        try persistState()
        return try CheckpointActivationReceiptV1(
            workspaceID: identity.workspaceID,
            destinationReplicaID: identity.replicaID,
            destinationGenerationID: generationID,
            manifest: checkpoint.manifest,
            activatedFrontier: checkpoint.manifest.frontier,
            semanticProjectionSHA256: projection.semanticSHA256,
            contentDispositionSHA256: verification,
            limits: limits
        )
    }

    func initialCursor(
        consumerReplicaID: ReplicaID,
        checkpointID: String? = nil
    ) throws -> ChangeCursorV1 {
        let checkpoint = try resolvedCheckpoint(checkpointID)
        return try ChangeCursorV1(
            workspaceID: identity.workspaceID,
            consumerReplicaID: consumerReplicaID,
            checkpointID: checkpoint.manifest.checkpointID,
            frontierSHA256: checkpoint.manifest.frontier.canonicalSHA256(),
            nextOrdinal: 0,
            previousBatchSHA256: nil
        )
    }

    /// Produces a deterministic bounded page. The cursor ordinal is relative to
    /// the immutable receipt sequence strictly after the checkpoint frontier.
    func page(after cursor: ChangeCursorV1) throws -> ChangeBatchV1 {
        let checkpoint = try resolvedCheckpoint(cursor.checkpointID)
        guard checkpoint.manifest.sourceReplicaID == identity.replicaID,
              checkpoint.manifest.sourceGenerationID == generationID else {
            throw ChangeJournalFailureV1.wrongGeneration
        }
        try cursor.validate(
            workspaceID: identity.workspaceID,
            consumerReplicaID: cursor.consumerReplicaID,
            checkpointID: checkpoint.manifest.checkpointID,
            frontierSHA256: checkpoint.manifest.frontier.canonicalSHA256()
        )
        let all = try journalChanges().filter {
            $0.receipt.identity.localSequence > checkpointLocalSequence(checkpoint.manifest.frontier)
        }
        guard cursor.nextOrdinal <= UInt64(all.count) else { throw ChangeJournalFailureV1.staleCursor }
        let start = Int(cursor.nextOrdinal)
        var selected = Array(all.dropFirst(start).prefix(limits.maximumChangesPerBatch))
        while true {
            let candidate = try ChangeBatchV1(
                workspaceID: identity.workspaceID,
                sourceReplicaID: identity.replicaID,
                checkpointID: checkpoint.manifest.checkpointID,
                beforeCursor: cursor,
                changes: selected,
                limits: limits
            )
            if try candidate.canonicalData(limits: limits).count <= limits.maximumBatchBytes {
                return candidate
            }
            guard !selected.isEmpty else { throw ChangeJournalFailureV1.limitExceeded }
            selected.removeLast()
        }
    }

    func installConflictResolution(_ basis: ConflictResolutionBasisV1) throws {
        try basis.validate()
        guard basis.subject.workspaceIdentity == identity.workspaceID else {
            throw ChangeJournalFailureV1.wrongWorkspace
        }
        state.conflictResolutions.removeAll { $0.conflictIdentity == basis.conflictIdentity }
        state.conflictResolutions.append(basis)
        state.conflictResolutions.sort { $0.conflictIdentity.digestSHA256 < $1.conflictIdentity.digestSHA256 }
        try persistState()
    }

    /// Replays verified imported history only through the sole writer seam.
    /// The first causal/content/conflict gap stops advancement for later changes.
    func replay(_ batch: ChangeBatchV1) throws -> ChangeReplayReceiptV1 {
        try replayResult(batch).receipt
    }

    func replayResult(_ batch: ChangeBatchV1) throws -> ReplayResultV1 {
        try batch.validate(limits: limits)
        guard batch.workspaceID == identity.workspaceID else { throw ChangeJournalFailureV1.wrongWorkspace }
        let checkpoint = try resolvedCheckpoint(batch.checkpointID)
        guard batch.beforeCursor.consumerReplicaID == identity.replicaID,
              batch.sourceReplicaID != identity.replicaID,
              checkpoint.manifest.sourceReplicaID == batch.sourceReplicaID else {
            throw ChangeJournalFailureV1.wrongWorkspace
        }
        if let prior = state.replayReceipts.first(where: { $0.batchSHA256 == batch.batchSHA256 }) {
            let next = state.replayCursors.first {
                $0.consumerReplicaID == batch.beforeCursor.consumerReplicaID
                    && $0.checkpointID == batch.checkpointID
            } ?? batch.beforeCursor
            return ReplayResultV1(
                receipt: prior,
                nextCursor: next,
                isDeferred: Self.isDeferred(prior)
            )
        }
        let expectedCursor = state.replayCursors.first {
            $0.consumerReplicaID == batch.beforeCursor.consumerReplicaID
                && $0.checkpointID == batch.checkpointID
        } ?? (try initialCursor(
            consumerReplicaID: batch.beforeCursor.consumerReplicaID,
            checkpointID: checkpoint.manifest.checkpointID
        ))
        if expectedCursor != batch.beforeCursor {
            guard batch.beforeCursor.nextOrdinal > expectedCursor.nextOrdinal else {
                throw ChangeJournalFailureV1.staleCursor
            }
            return try stageGap(batch, expectedCursor: expectedCursor)
        }
        try retainPendingBatch(batch)
        try persistState()
        var dispositions: [MutationReplayDispositionV1] = []
        var blocked = false
        let before = try writer.sourceMutationHistorySnapshot()
        var existing = try Set(before.receipts.map { try MutationReceiptV1.decodeCanonical(from: $0.receiptData).mutationID })
        let replayBasis: PendingReplayBasis
        if let value = state.pendingReplayBases.first(where: {
            $0.batchSHA256 == batch.batchSHA256
        }) {
            replayBasis = value
        } else {
            replayBasis = PendingReplayBasis(
                batchSHA256: batch.batchSHA256,
                preexistingMutationIDs: batch.changes.map(\.envelope.mutationID)
                    .filter { existing.contains($0) }
                    .sorted { $0.rawValue.uuidString.lowercased() < $1.rawValue.uuidString.lowercased() }
            )
            state.pendingReplayBases.append(replayBasis)
            state.pendingReplayBases.sort { $0.batchSHA256 < $1.batchSHA256 }
            try persistState()
        }
        for (index, change) in batch.changes.enumerated() {
            try change.validate()
            try Self.validateAssetSemanticChange(change)
            try Self.validateAuthorityCriterionChange(change)
            try Self.validateFunctionalRelationshipChange(change)
            try Self.validateEvidenceAssuranceChange(change)
            try Self.validateInspectionReviewChange(change)
            try Self.validatePortableReviewChange(change)
            try Self.validateWorkResourceChange(change)
            try WorkPacketJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try FieldDraftJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try FieldReferenceJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try AccessibleDocumentAssessmentJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try SurveyDefinitionJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try SurveySessionJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try AssetLocatorJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try ScheduleJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try Self.validateC51ScheduleExceptionChange(change)
            try PlanJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try PlacementPoseJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try EvidenceContextJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try LightingJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)
            try AssistanceLocalChangeJournalPolicyV1.validate(change)
            try TemporalEvidenceLocalChangeJournalPolicyV1.validate(change)
            let disposition: MutationReplayDispositionV1
            if blocked {
                disposition = try .init(mutationID: change.envelope.mutationID, disposition: .deferredGap, reasonCode: "PRIOR_CAUSAL_GAP")
            } else {
                let wasExisting = existing.contains(change.envelope.mutationID)
                let existedBeforePage = replayBasis.preexistingMutationIDs.contains(
                    change.envelope.mutationID
                )
                if wasExisting {
                    // The writer owns identical-input recognition and durable
                    // changed-input quarantine. Run it before any derived
                    // conflict projection can observe a mismatched duplicate.
                    _ = try writer.executeImported(change)
                    if let gate = try contentGate(batch: batch, change: change) {
                        blocked = gate.blocksFollowing
                        disposition = gate.disposition
                    } else if !existedBeforePage,
                              let gate = try conflictGate(change) {
                        // This is a prefix applied before an interruption, not
                        // a mutation that predated the page. Rebuild the same
                        // derived conflict observation a clean run produced.
                        blocked = gate.blocksFollowing
                        disposition = gate.disposition
                    } else {
                        disposition = try .init(
                            mutationID: change.envelope.mutationID,
                            disposition: existedBeforePage ? .alreadyApplied : .applied
                        )
                    }
                } else if let gate = try contentGate(batch: batch, change: change) {
                    blocked = gate.blocksFollowing
                    disposition = gate.disposition
                } else if let gate = try conflictGate(change) {
                    blocked = gate.blocksFollowing
                    disposition = gate.disposition
                } else {
                    _ = try writer.executeImported(change)
                    existing.insert(change.envelope.mutationID)
                    disposition = try .init(
                        mutationID: change.envelope.mutationID,
                        disposition: .applied
                    )
                }
            }
            dispositions.append(disposition)
            if interruptionPoint() == .afterReplayMutation(index) {
                throw ChangeJournalFailureV1.discontinuousBatch
            }
        }
        let resulting = try frontier(try writer.sourceMutationHistorySnapshot())
        let projection = try semanticProjection(unresolvedConflicts: unresolvedConflictIdentities())
        let receipt = try ChangeReplayReceiptV1(
            workspaceID: identity.workspaceID,
            destinationReplicaID: identity.replicaID,
            destinationGenerationID: generationID,
            batchSHA256: batch.batchSHA256,
            resultingFrontier: resulting,
            dispositions: dispositions.sorted { $0.stableKey < $1.stableKey },
            semanticProjectionSHA256: projection.semanticSHA256,
            limits: limits
        )
        let nextCursor = blocked ? batch.beforeCursor : batch.afterCursor
        if !blocked {
            state.pendingBatches.removeAll { $0.batchSHA256 == batch.batchSHA256 }
            state.pendingReplayBases.removeAll { $0.batchSHA256 == batch.batchSHA256 }
            state.replayReceipts.append(receipt)
            state.replayReceipts.sort { $0.batchSHA256 < $1.batchSHA256 }
            state.replayCursors.removeAll {
                $0.consumerReplicaID == batch.beforeCursor.consumerReplicaID
                    && $0.checkpointID == batch.checkpointID
            }
            state.replayCursors.append(nextCursor)
            state.replayCursors.sort {
                if $0.consumerReplicaID != $1.consumerReplicaID {
                    return $0.consumerReplicaID.rawValue.uuidString < $1.consumerReplicaID.rawValue.uuidString
                }
                return $0.checkpointID < $1.checkpointID
            }
        } else {
            try retainPendingBatch(batch)
        }
        try persistState()
        return ReplayResultV1(receipt: receipt, nextCursor: nextCursor, isDeferred: blocked)
    }

    func resumeStagedBatches() throws -> [ReplayResultV1] {
        var results: [ReplayResultV1] = []
        while true {
            let ordered = state.pendingBatches.sorted(by: {
            if $0.beforeCursor.nextOrdinal != $1.beforeCursor.nextOrdinal {
                return $0.beforeCursor.nextOrdinal < $1.beforeCursor.nextOrdinal
            }
            return $0.batchSHA256 < $1.batchSHA256
            })
            var ready: ChangeBatchV1?
            for batch in ordered {
                if try currentReplayCursor(for: batch) == batch.beforeCursor {
                    ready = batch
                    break
                }
            }
            guard let candidate = ready else { break }
            let result = try replayResult(candidate)
            results.append(result)
            if result.isDeferred { break }
        }
        return results
    }

    /// Advances only the derived delivery floor. It never mutates canonical
    /// mutation receipts, quarantines, entity revisions, or reversal bases.
    func compact(through checkpointID: String) throws -> ChangeJournalCompactionReceiptV1 {
        let checkpoint = try resolvedCheckpoint(checkpointID)
        guard checkpoint.manifest.sourceReplicaID == identity.replicaID,
              checkpoint.manifest.sourceGenerationID == generationID else {
            throw ChangeJournalFailureV1.wrongGeneration
        }
        let snapshotBefore = try writer.sourceMutationHistorySnapshot()
        let receiptSet = try Self.sha256(snapshotBefore.receipts.map(\.receiptData))
        let reversalSet = try Self.sha256(snapshotBefore.receipts.compactMap(\.reversalBasisData))
        let oldFloor = state.checkpointFloor.map { checkpointLocalSequence($0.frontier) } ?? 0
        let newFloor = checkpointLocalSequence(checkpoint.manifest.frontier)
        guard newFloor >= oldFloor else { throw ChangeJournalFailureV1.staleCursor }
        guard newFloor - oldFloor <= UInt64(Int.max) else { throw ChangeJournalFailureV1.limitExceeded }
        state.checkpointFloor = checkpoint.manifest
        state.checkpoints.removeAll { $0.manifest.frontier.workspaceRevision < checkpoint.manifest.frontier.workspaceRevision }
        try persistState()
        if interruptionPoint() == .afterCompactionStateWritten {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        let snapshotAfter = try writer.sourceMutationHistorySnapshot()
        guard snapshotAfter == snapshotBefore else { throw ChangeJournalFailureV1.incompleteCheckpoint }
        return try ChangeJournalCompactionReceiptV1(
            workspaceID: identity.workspaceID,
            sourceReplicaID: identity.replicaID,
            manifest: checkpoint.manifest,
            compactedThrough: checkpoint.manifest.frontier,
            preservedReceiptSetSHA256: receiptSet,
            preservedReversalBasisSetSHA256: reversalSet,
            removedChangeCount: Int(newFloor - oldFloor),
            limits: limits
        )
    }

    func semanticProjection(
        unresolvedConflicts: [ConflictIdentityV1]? = nil
    ) throws -> SemanticConvergenceProjectionV1 {
        let basis = try backupExport.canonicalCheckpointBasis()
        let history = try writer.sourceMutationHistorySnapshot()
        guard basis.workspaceIdentity == identity,
              basis.generationID == generationID,
              basis.workspaceRevision == history.workspaceRevision,
              basis.lastLocalSequence == history.lastLocalSequence else {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        return try SemanticConvergenceProjectionV1(
            workspaceID: identity.workspaceID,
            canonicalSnapshotSHA256: Self.rawSHA256(basis.semanticRecordsData),
            tombstoneIdentities: try tombstones(history),
            unresolvedConflictIdentities: (unresolvedConflicts ?? unresolvedConflictIdentities()).sorted { $0.digestSHA256 < $1.digestSHA256 },
            contentDispositionSHA256: try Self.sha256(activeCheckpoint?.contentEntries ?? []),
            observedMutationIDs: try mutationIDs(history),
            limits: limits
        )
    }

    func recoverInterruptedWork() throws {
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        for url in try fileManager.contentsOfDirectory(at: stateDirectoryURL, includingPropertiesForKeys: nil)
        where url.lastPathComponent.hasSuffix(".tmp") {
            try fileManager.removeItem(at: url)
        }
        if fileManager.fileExists(atPath: stateURL.path) {
            let data = try Data(contentsOf: stateURL)
            let decoded = try Self.decoder.decode(DurableState.self, from: data)
            guard decoded.schemaVersion == DurableState.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }
            guard try WorkspaceMutationCanonicalV1.data(decoded) == data else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
            state = decoded
            try validateState()
        }
        _ = try resumableCheckpointPreparations()
    }

    func rollbackPreparedCheckpoint(_ preparationID: UUID) throws {
        try removePrepared(preparationID)
    }

    func resumableCheckpointPreparations() throws -> [WorkspaceCheckpointPreparationV1] {
        let urls = try fileManager.contentsOfDirectory(at: stateDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("prepared-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map {
            let data = try Data(contentsOf: $0)
            let record = try Self.decoder.decode(PreparedRecord.self, from: data)
            guard try WorkspaceMutationCanonicalV1.data(record) == data else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
            try record.preparation.validate(limits: limits)
            try record.checkpoint.validate(limits: limits)
            guard record.preparation.manifest == record.checkpoint.manifest else {
                throw ChangeJournalFailureV1.incompleteCheckpoint
            }
            return record.preparation
        }
    }

    // MARK: - Construction

    private func makeCheckpoint(supplement: CheckpointSupplementV1) throws -> WorkspaceCheckpointContentV1 {
        let basis = try backupExport.canonicalCheckpointBasis()
        guard basis.workspaceIdentity == identity, basis.generationID == generationID else {
            throw ChangeJournalFailureV1.wrongGeneration
        }
        guard basis.persistentSchemaVersion == 16,
              basis.recordsSchemaVersion == 15 else {
            throw ChangeJournalFailureV1.incompatibleVersion
        }
        guard basis.memberInventory.map(\.path) == basis.memberInventory.map(\.path).sorted(),
              Set(basis.memberInventory.map(\.path)).count == basis.memberInventory.count,
              let recordsEntry = basis.memberInventory.first(where: { $0.path == "records.json" }),
              recordsEntry.byteCount == basis.recordsData.count,
              recordsEntry.sha256 == Self.rawSHA256(basis.recordsData) else {
            throw ChangeJournalFailureV1.invalidDigest
        }
        let history = try writer.sourceMutationHistorySnapshot()
        let currentFrontier = try frontier(history)
        guard basis.workspaceRevision == history.workspaceRevision,
              basis.lastLocalSequence == history.lastLocalSequence,
              checkpointLocalSequence(currentFrontier) == basis.lastLocalSequence else {
            throw ChangeJournalFailureV1.incompleteCheckpoint
        }
        let persistentSchemaSHA256 = try Self.sha256(PersistentSchemaDigestBasis(
            persistentSchemaVersion: basis.persistentSchemaVersion,
            compatibilityID: try persistentCompatibilityID(basis.persistentSchemaVersion),
            modelNames: CurrentSyncClassificationCatalogV1.activePersistentModelNames
        ))
        let packages = try packageDigests(basis.packageReleases)
        let tombstones = try tombstones(history)
        let expectedMutationIDs = Set(try mutationIDs(history))
        guard Set(supplement.reversalEligibility.map(\.targetMutationID)) == expectedMutationIDs else {
            throw ChangeJournalFailureV1.invalidReversal
        }
        let expectedContentIDs = try Set(history.receipts.flatMap {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).contentDependencyIDs
        })
        let suppliedContentIDs = Set(supplement.contentEntries.map { $0.reference.contentID })
        guard expectedContentIDs.isSubset(of: suppliedContentIDs),
              supplement.contentEntries.allSatisfy({
                  $0.reference.workspaceID == identity.workspaceID.rawValue.uuidString.lowercased()
                    && basis.memberInventory.contains(where: { entry in
                        entry.path == $0.archiveRelativePath
                            && entry.byteCount == Int($0.reference.byteLength)
                            && entry.sha256 == $0.reference.digests.digest(for: .sha256)?.hexadecimalValue
                    })
              }) else {
            throw ChangeJournalFailureV1.missingContent
        }
        let manifest = try WorkspaceSnapshotManifestV1(
            workspaceID: identity.workspaceID,
            sourceReplicaID: identity.replicaID,
            sourceGenerationID: generationID,
            persistentSchemaVersion: basis.persistentSchemaVersion,
            persistentSchemaSHA256: persistentSchemaSHA256,
            recordSchemaVersion: basis.recordsSchemaVersion,
            recordSchemaSHA256: try Self.sha256(RecordSchemaDigestBasis(
                recordsSchemaVersion: basis.recordsSchemaVersion,
                orderedFields: Self.backupRecordFields(
                    for: basis.recordsSchemaVersion
                )
            )),
            packages: packages,
            frontier: currentFrontier,
            normalizedRecordsSHA256: Self.rawSHA256(basis.semanticRecordsData),
            tombstonesSHA256: try Self.sha256(tombstones),
            contentManifestSHA256: try Self.sha256(supplement.contentEntries),
            reversalEligibilitySHA256: try Self.sha256(supplement.reversalEligibility),
            limits: limits
        )
        return try WorkspaceCheckpointContentV1(
            manifest: manifest,
            normalizedRecordData: basis.semanticRecordsData,
            tombstoneIdentities: tombstones,
            contentEntries: supplement.contentEntries,
            reversalEligibility: supplement.reversalEligibility,
            limits: limits
        )
    }

    private func journalChanges() throws -> [JournalChangeV1] {
        let snapshot = try writer.sourceMutationHistorySnapshot()
        return try snapshot.receipts.compactMap { record in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            guard envelope.workspaceID == identity.workspaceID else { throw ChangeJournalFailureV1.wrongWorkspace }
            guard envelope.replicaID == identity.replicaID else { return nil }
            let basis = try record.reversalBasisData.map(ReversalBasisV1.decodeCanonical)
            let portable = try basis.flatMap { try portableReversalPlanResolver($0, receipt) }
            if basis != nil && portable == nil { throw ChangeJournalFailureV1.invalidReversal }
            let semantic = try record.semanticReversalData.map(SemanticReversalReceiptV1.decodeCanonical)
            let entities = try receipt.postImages.map { image in
                try EntityChangeV1(
                    postImage: image,
                    conflictPolicy: policyResolver(try image.identity, image),
                    conflictIdentity: nil
                )
            }
            let references = try envelope.contentDependencyIDs.map(contentReferenceResolver)
            return try JournalChangeV1(
                envelope: envelope,
                receipt: receipt,
                entityChanges: entities.sorted { $0.stableKey < $1.stableKey },
                reversalBasis: basis,
                portableReversalPlan: portable,
                semanticReversalReceipt: semantic,
                contentReferences: references.sorted { $0.contentID < $1.contentID }
            )
        }.sorted { $0.receipt.identity.localSequence < $1.receipt.identity.localSequence }
    }

    private func frontier(_ snapshot: MutationHistorySnapshotV1) throws -> ChangeJournalFrontierV1 {
        let receipts = try snapshot.receipts.map { try MutationReceiptV1.decodeCanonical(from: $0.receiptData) }
        let grouped = Dictionary(grouping: receipts, by: { $0.identity.replicaID })
        let replicas = try grouped.map { key, values in
            try ReplicaRevisionFrontierV1(replicaID: key, localSequence: values.map { $0.identity.localSequence }.max() ?? 0)
        }.sorted { $0.stableKey < $1.stableKey }
        return try ChangeJournalFrontierV1(
            workspaceRevision: snapshot.workspaceRevision,
            replicas: replicas,
            entityRevisionSHA256: try Self.sha256(snapshot.entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey }),
            observedMutationSetSHA256: try Self.sha256(receipts.map(\.mutationID).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }),
            limits: limits
        )
    }

    private func conflictGate(_ change: JournalChangeV1) throws -> (disposition: MutationReplayDispositionV1, blocksFollowing: Bool)? {
        for entity in change.entityChanges {
            switch entity.conflictPolicy.rule {
            case .localOnly:
                return (try .init(mutationID: change.envelope.mutationID, disposition: .localOnlyExcluded), false)
            case .derivedRebuild:
                return (try .init(mutationID: change.envelope.mutationID, disposition: .derivedRebuild), false)
            case .deleteWins:
                if !Self.isTombstone(entity.postImage), try localTombstones().contains(entity.identity) {
                    return (try .init(mutationID: change.envelope.mutationID, disposition: .deleteWon), false)
                }
            case .exactRevisionManual:
                let competitor = try ConflictCompetitorV1(
                    mutationID: change.envelope.mutationID,
                    canonicalInputSHA256: entity.postImage.semanticSHA256
                )
                let subject = ConflictSubjectIdentityV1.entity(
                    workspaceID: identity.workspaceID,
                    entity: entity.identity
                )
                let available = try observedConflictCompetitors(
                    entity: entity.identity,
                    including: competitor
                )
                try persistObservedConflictInputs(entity: entity.identity, competitors: available)
                if available.count == 1,
                   !state.conflictResolutions.contains(where: {
                       $0.subject == subject && $0.policy == entity.conflictPolicy
                   }) {
                    break
                }
                let derived = try ConflictIdentityV1.derive(
                    subject: subject,
                    policy: entity.conflictPolicy,
                    competitors: available
                )
                guard entity.conflictIdentity == nil || entity.conflictIdentity == derived else {
                    throw ChangeJournalFailureV1.tamperedBatch
                }
                let candidates = state.conflictResolutions.filter {
                    $0.subject == subject && $0.policy == entity.conflictPolicy
                }.sorted {
                    if $0.competitors.count != $1.competitors.count {
                        return $0.competitors.count > $1.competitors.count
                    }
                    return $0.conflictIdentity.digestSHA256 < $1.conflictIdentity.digestSHA256
                }
                guard let basis = candidates.first(where: { $0.conflictIdentity == derived })
                        ?? candidates.first else {
                    try recordUnresolved(derived)
                    return (try .init(mutationID: change.envelope.mutationID, disposition: .unresolvedConflict, conflictIdentity: derived, reasonCode: "RESOLUTION_REQUIRED"), true)
                }
                switch try basis.readiness(availableInputs: available) {
                case .ready:
                    state.unresolvedConflicts.removeAll {
                        $0 == basis.conflictIdentity || $0 == derived
                    }
                case .deferred:
                    try recordUnresolved(basis.conflictIdentity)
                    return (try .init(mutationID: change.envelope.mutationID, disposition: .unresolvedConflict, conflictIdentity: basis.conflictIdentity, reasonCode: "RESOLUTION_INPUTS_INCOMPLETE"), true)
                case .successorRequired(let identity, _):
                    try recordUnresolved(identity)
                    return (try .init(mutationID: change.envelope.mutationID, disposition: .unresolvedConflict, conflictIdentity: identity, reasonCode: "SUCCESSOR_RESOLUTION_REQUIRED"), true)
                }
            case .immutableVersion, .stableIDAppendUnion:
                break
            }
        }
        return nil
    }

    private enum ContentDisposition {
        case verified
        case missing([String])
        case corrupt
    }

    private func contentGate(
        batch: ChangeBatchV1,
        change: JournalChangeV1
    ) throws -> (disposition: MutationReplayDispositionV1, blocksFollowing: Bool)? {
        switch contentDisposition(change.contentReferences) {
        case .verified:
            return nil
        case .missing(let missing):
            return (
                try .init(
                    mutationID: change.envelope.mutationID,
                    disposition: .deferredContent,
                    missingContentIDs: missing,
                    reasonCode: "CONTENT_NOT_VERIFIED"
                ),
                true
            )
        case .corrupt:
            try quarantineCorruptContent(batch: batch, change: change)
            return (
                try .init(
                    mutationID: change.envelope.mutationID,
                    disposition: .rejected,
                    reasonCode: "CONTENT_CORRUPT"
                ),
                true
            )
        }
    }

    private func contentDisposition(_ references: [ContentReferenceV1]) -> ContentDisposition {
        guard !references.isEmpty else { return .verified }
        do {
            _ = try verifiedContentDisposition(references)
            return .verified
        } catch let error as ContentIntegrityFailureV1 {
            return error == .missingContent
                ? .missing(references.map(\.contentID).sorted())
                : .corrupt
        } catch let error as ContentContractFailureV1 {
            return error == .missingContent
                ? .missing(references.map(\.contentID).sorted())
                : .corrupt
        } catch {
            return .corrupt
        }
    }

    private func verifiedContentDisposition(_ references: [ContentReferenceV1]) throws -> String {
        let ordered = references.sorted { $0.contentID < $1.contentID }
        guard ordered.map(\.contentID) == references.map(\.contentID),
              Set(ordered.map(\.contentID)).count == ordered.count else {
            throw ChangeJournalFailureV1.noncanonicalOrder
        }
        for reference in ordered {
            let entry = try contentEntryResolver(reference)
            guard entry.reference == reference else { throw ChangeJournalFailureV1.tamperedBatch }
            try ContentIntegrityV1.verify(
                reference: reference,
                locator: entry.locator,
                observed: entry.observed
            )
        }
        return try Self.sha256(ordered)
    }

    private func stageGap(
        _ batch: ChangeBatchV1,
        expectedCursor: ChangeCursorV1
    ) throws -> ReplayResultV1 {
        if let collision = state.pendingBatches.first(where: {
            $0.beforeCursor.consumerReplicaID == batch.beforeCursor.consumerReplicaID
                && $0.checkpointID == batch.checkpointID
                && $0.beforeCursor.nextOrdinal == batch.beforeCursor.nextOrdinal
        }), collision.batchSHA256 != batch.batchSHA256 {
            throw ChangeJournalFailureV1.tamperedBatch
        }
        if !state.pendingBatches.contains(where: { $0.batchSHA256 == batch.batchSHA256 }) {
            try retainPendingBatch(batch)
            try persistState()
        }
        let dispositions = try batch.changes.map {
            try MutationReplayDispositionV1(
                mutationID: $0.envelope.mutationID,
                disposition: .deferredGap,
                reasonCode: "CAUSAL_GAP_STAGED"
            )
        }.sorted { $0.stableKey < $1.stableKey }
        let projection = try semanticProjection(
            unresolvedConflicts: unresolvedConflictIdentities()
        )
        let receipt = try ChangeReplayReceiptV1(
            workspaceID: identity.workspaceID,
            destinationReplicaID: identity.replicaID,
            destinationGenerationID: generationID,
            batchSHA256: batch.batchSHA256,
            resultingFrontier: try frontier(writer.sourceMutationHistorySnapshot()),
            dispositions: dispositions,
            semanticProjectionSHA256: projection.semanticSHA256,
            limits: limits
        )
        return ReplayResultV1(receipt: receipt, nextCursor: expectedCursor, isDeferred: true)
    }

    private func retainPendingBatch(_ batch: ChangeBatchV1) throws {
        if state.pendingBatches.contains(where: { $0.batchSHA256 == batch.batchSHA256 }) {
            return
        }
        guard state.pendingBatches.count < limits.maximumReplicaFrontiers else {
            throw ChangeJournalFailureV1.limitExceeded
        }
        state.pendingBatches.append(batch)
        state.pendingBatches.sort {
            if $0.beforeCursor.nextOrdinal != $1.beforeCursor.nextOrdinal {
                return $0.beforeCursor.nextOrdinal < $1.beforeCursor.nextOrdinal
            }
            return $0.batchSHA256 < $1.batchSHA256
        }
    }

    private func currentReplayCursor(for batch: ChangeBatchV1) throws -> ChangeCursorV1 {
        state.replayCursors.first {
            $0.consumerReplicaID == batch.beforeCursor.consumerReplicaID
                && $0.checkpointID == batch.checkpointID
        } ?? (try initialCursor(
            consumerReplicaID: batch.beforeCursor.consumerReplicaID,
            checkpointID: batch.checkpointID
        ))
    }

    private func quarantineCorruptContent(
        batch: ChangeBatchV1,
        change: JournalChangeV1
    ) throws {
        let value = DerivedContentQuarantine(
            batchSHA256: batch.batchSHA256,
            mutationID: change.envelope.mutationID,
            changeSHA256: try change.canonicalSHA256()
        )
        if !state.contentQuarantines.contains(value) {
            guard state.contentQuarantines.count < limits.maximumConflicts else {
                throw ChangeJournalFailureV1.limitExceeded
            }
            state.contentQuarantines.append(value)
            state.contentQuarantines.sort { $0.stableKey < $1.stableKey }
            try persistState()
        }
    }

    private func semanticProjection(
        checkpoint: WorkspaceCheckpointContentV1,
        unresolvedConflicts: [ConflictIdentityV1]
    ) throws -> SemanticConvergenceProjectionV1 {
        try SemanticConvergenceProjectionV1(
            workspaceID: identity.workspaceID,
            canonicalSnapshotSHA256: checkpoint.manifest.normalizedRecordsSHA256,
            tombstoneIdentities: checkpoint.tombstoneIdentities,
            unresolvedConflictIdentities: unresolvedConflicts.sorted { $0.digestSHA256 < $1.digestSHA256 },
            contentDispositionSHA256: checkpoint.manifest.contentManifestSHA256,
            observedMutationIDs: try mutationIDs(writer.sourceMutationHistorySnapshot()),
            limits: limits
        )
    }

    private func resolvedCheckpoint(_ checkpointID: String?) throws -> WorkspaceCheckpointContentV1 {
        guard let checkpoint = checkpointID.flatMap({ id in state.checkpoints.first { $0.manifest.checkpointID == id } }) ?? state.checkpoints.last else {
            throw ChangeJournalFailureV1.unknownCheckpoint
        }
        try checkpoint.validate(limits: limits)
        return checkpoint
    }

    private func checkpointLocalSequence(_ frontier: ChangeJournalFrontierV1) -> UInt64 {
        frontier.replicas.first { $0.replicaID == identity.replicaID }?.localSequence ?? 0
    }

    private func tombstones(_ snapshot: MutationHistorySnapshotV1) throws -> [WorkspaceEntityIdentityV1] {
        let values = try snapshot.receipts.flatMap { record -> [WorkspaceEntityIdentityV1] in
            try MutationReceiptV1.decodeCanonical(from: record.receiptData).postImages.compactMap {
                if case .tombstone(let identity, _, _) = $0 { return identity }
                return nil
            }
        }
        return Array(Set(values)).sorted { $0.stableKey < $1.stableKey }
    }

    private func localTombstones() throws -> Set<WorkspaceEntityIdentityV1> {
        try Set(tombstones(writer.sourceMutationHistorySnapshot()))
    }

    private func mutationIDs(_ snapshot: MutationHistorySnapshotV1) throws -> [MutationIDV1] {
        try snapshot.receipts.map { try MutationReceiptV1.decodeCanonical(from: $0.receiptData).mutationID }
            .sorted { $0.rawValue.uuidString.lowercased() < $1.rawValue.uuidString.lowercased() }
    }

    private func unresolvedConflictIdentities() -> [ConflictIdentityV1] {
        state.unresolvedConflicts
    }

    private func recordUnresolved(_ identity: ConflictIdentityV1) throws {
        try identity.validate()
        if !state.unresolvedConflicts.contains(identity) {
            guard state.unresolvedConflicts.count < limits.maximumConflicts else {
                throw ChangeJournalFailureV1.limitExceeded
            }
            state.unresolvedConflicts.append(identity)
            state.unresolvedConflicts.sort { $0.digestSHA256 < $1.digestSHA256 }
        }
    }

    private func observedConflictCompetitors(
        entity: WorkspaceEntityIdentityV1,
        including incoming: ConflictCompetitorV1
    ) throws -> [ConflictCompetitorV1] {
        var values = state.observedConflictInputs.first { $0.entity == entity }?.competitors ?? []
        let history = try writer.sourceMutationHistorySnapshot()
        for record in history.receipts {
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            for image in receipt.postImages {
                if (try image.identity) == entity {
                    values.append(try ConflictCompetitorV1(
                        mutationID: receipt.mutationID,
                        canonicalInputSHA256: image.semanticSHA256
                    ))
                }
            }
        }
        values.append(incoming)
        return try canonicalCompetitors(values)
    }

    private func persistObservedConflictInputs(
        entity: WorkspaceEntityIdentityV1,
        competitors: [ConflictCompetitorV1]
    ) throws {
        let value = try ObservedConflictInputs(entity: entity, competitors: competitors)
        state.observedConflictInputs.removeAll { $0.entity == entity }
        state.observedConflictInputs.append(value)
        state.observedConflictInputs.sort { $0.entity.stableKey < $1.entity.stableKey }
    }

    private func canonicalCompetitors(_ values: [ConflictCompetitorV1]) throws -> [ConflictCompetitorV1] {
        let unique = Array(Set(values))
        guard Set(unique.map(\.mutationID)).count == unique.count,
              unique.count <= ConflictCompetitorV1.maximumCount else {
            throw ChangeJournalFailureV1.tamperedBatch
        }
        return unique.sorted {
            let left = $0.mutationID.rawValue.uuidString.lowercased() + ":" + $0.canonicalInputSHA256
            let right = $1.mutationID.rawValue.uuidString.lowercased() + ":" + $1.canonicalInputSHA256
            return left < right
        }
    }

    private func checkpointArchiveEntries(_ checkpoint: WorkspaceCheckpointContentV1) throws -> [CheckpointArchiveEntryDigestV1] {
        let manifestData = try WorkspaceMutationCanonicalV1.data(checkpoint.manifest)
        let tombstoneData = try WorkspaceMutationCanonicalV1.data(checkpoint.tombstoneIdentities)
        let reversalData = try WorkspaceMutationCanonicalV1.data(checkpoint.reversalEligibility)
        var entries = [
            try CheckpointArchiveEntryDigestV1(relativePath: "manifest.json", byteCount: Int64(manifestData.count), sha256: Self.rawSHA256(manifestData)),
            try CheckpointArchiveEntryDigestV1(relativePath: "records.json", byteCount: Int64(checkpoint.normalizedRecordData.count), sha256: Self.rawSHA256(checkpoint.normalizedRecordData)),
            try CheckpointArchiveEntryDigestV1(relativePath: "reversal-eligibility.json", byteCount: Int64(reversalData.count), sha256: Self.rawSHA256(reversalData)),
            try CheckpointArchiveEntryDigestV1(relativePath: "tombstones.json", byteCount: Int64(tombstoneData.count), sha256: Self.rawSHA256(tombstoneData)),
        ]
        entries += try checkpoint.contentEntries.map {
            guard let digest = $0.reference.digests.digest(for: .sha256) else {
                throw ChangeJournalFailureV1.invalidDigest
            }
            return try CheckpointArchiveEntryDigestV1(relativePath: $0.archiveRelativePath, byteCount: $0.reference.byteLength, sha256: digest.hexadecimalValue)
        }
        return entries.sorted { $0.stableKey < $1.stableKey }
    }

    private func persistentCompatibilityID(_ version: Int) throws -> String {
        switch version {
        case 1: return PersistentSchemaReleaseV1.v1.compatibilityID
        case 2: return PersistentSchemaReleaseV1.v2.compatibilityID
        case 3: return PersistentSchemaReleaseV1.v3.compatibilityID
        case 4: return PersistentSchemaReleaseV1.v4.compatibilityID
        case 5: return PersistentSchemaReleaseV1.v5.compatibilityID
        case 6: return PersistentSchemaReleaseV1.v6.compatibilityID
        case 7: return PersistentSchemaReleaseV1.v7.compatibilityID
        case 8: return PersistentSchemaReleaseV1.v8.compatibilityID
        case 9: return PersistentSchemaReleaseV1.v9.compatibilityID
        case 10: return PersistentSchemaReleaseV1.v10.compatibilityID
        case 11: return PersistentSchemaReleaseV1.v11.compatibilityID
        case 12: return PersistentSchemaReleaseV1.v12.compatibilityID
        case 13: return PersistentSchemaReleaseV1.v13.compatibilityID
        case 14: return PersistentSchemaReleaseV1.v14.compatibilityID
        case 15: return PersistentSchemaReleaseV1.v15.compatibilityID
        case 16: return PersistentSchemaReleaseV1.v16.compatibilityID
        default: throw ChangeJournalFailureV1.incompatibleVersion
        }
    }

    private func packageDigests(
        _ releases: [PackageReleaseIdentityV1]
    ) throws -> [CheckpointPackageDigestV1] {
        try releases.sorted().map {
            try CheckpointPackageDigestV1(
                packageID: $0.packageID,
                packageSchemaVersion: $0.schemaVersion,
                contentVersion: $0.contentVersion,
                packageSHA256: WorkspaceMutationCanonicalV1.sha256($0)
            )
        }.sorted { $0.stableKey < $1.stableKey }
    }

    // MARK: - Derived-state durability

    private var stateDirectoryURL: URL { generationRootURL.appendingPathComponent("replication/local-change-journal-v1", isDirectory: true) }
    private var stateURL: URL { stateDirectoryURL.appendingPathComponent("state.json") }
    private func preparedURL(_ id: UUID) -> URL { stateDirectoryURL.appendingPathComponent("prepared-\(id.uuidString.lowercased()).json") }

    private func persistState() throws {
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        try WorkspaceMutationCanonicalV1.data(state).write(to: stateURL, options: .atomic)
    }

    private func persistPrepared(_ checkpoint: WorkspaceCheckpointContentV1, preparation: WorkspaceCheckpointPreparationV1) throws {
        let payload = PreparedRecord(preparation: preparation, checkpoint: checkpoint)
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        try WorkspaceMutationCanonicalV1.data(payload).write(
            to: preparedURL(preparation.preparationID),
            options: .atomic
        )
    }

    private func loadPrepared(_ id: UUID) throws -> WorkspaceCheckpointContentV1 {
        let data = try Data(contentsOf: preparedURL(id))
        let record = try Self.decoder.decode(PreparedRecord.self, from: data)
        guard try WorkspaceMutationCanonicalV1.data(record) == data else {
            throw ChangeJournalFailureV1.tamperedBatch
        }
        try record.preparation.validate(limits: limits)
        try record.checkpoint.validate(limits: limits)
        guard record.preparation.manifest == record.checkpoint.manifest else { throw ChangeJournalFailureV1.incompleteCheckpoint }
        return record.checkpoint
    }

    private func removePrepared(_ id: UUID) throws {
        let url = preparedURL(id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private func validateState() throws {
        for checkpoint in state.checkpoints {
            try checkpoint.validate(limits: limits)
            guard checkpoint.manifest.workspaceID == identity.workspaceID else {
                throw ChangeJournalFailureV1.wrongWorkspace
            }
        }
        try state.checkpointFloor?.validate(limits: limits)
        if let floor = state.checkpointFloor {
            guard floor.workspaceID == identity.workspaceID,
                  floor.sourceReplicaID == identity.replicaID,
                  floor.sourceGenerationID == generationID else {
                throw ChangeJournalFailureV1.wrongGeneration
            }
        }
        for receipt in state.replayReceipts {
            try receipt.validate(limits: limits)
            guard receipt.workspaceID == identity.workspaceID,
                  receipt.destinationReplicaID == identity.replicaID,
                  receipt.destinationGenerationID == generationID else {
                throw ChangeJournalFailureV1.wrongGeneration
            }
        }
        for cursor in state.replayCursors {
            try cursor.validate()
            guard cursor.workspaceID == identity.workspaceID else {
                throw ChangeJournalFailureV1.wrongWorkspace
            }
        }
        for basis in state.conflictResolutions {
            try basis.validate()
            guard basis.subject.workspaceIdentity == identity.workspaceID else {
                throw ChangeJournalFailureV1.wrongWorkspace
            }
        }
        for conflict in state.unresolvedConflicts { try conflict.validate() }
        for projection in state.observedConflictInputs { try projection.validate() }
        for batch in state.pendingBatches {
            try batch.validate(limits: limits)
            guard batch.workspaceID == identity.workspaceID,
                  batch.beforeCursor.consumerReplicaID == identity.replicaID,
                  batch.sourceReplicaID != identity.replicaID,
                  state.checkpoints.contains(where: {
                      $0.manifest.checkpointID == batch.checkpointID
                        && $0.manifest.sourceReplicaID == batch.sourceReplicaID
                        && (try? $0.manifest.frontier.canonicalSHA256())
                            == batch.beforeCursor.frontierSHA256
                  }) else {
                throw ChangeJournalFailureV1.wrongWorkspace
            }
        }
        for basis in state.pendingReplayBases {
            try basis.validate()
            guard let batch = state.pendingBatches.first(where: {
                $0.batchSHA256 == basis.batchSHA256
            }), Set(basis.preexistingMutationIDs).isSubset(of: Set(
                batch.changes.map(\.envelope.mutationID)
            )) else {
                throw ChangeJournalFailureV1.invalidValue
            }
        }
        for quarantine in state.contentQuarantines { try quarantine.validate() }
        guard state.checkpoints == state.checkpoints.sorted(by: {
                  if $0.manifest.frontier.workspaceRevision != $1.manifest.frontier.workspaceRevision {
                      return $0.manifest.frontier.workspaceRevision < $1.manifest.frontier.workspaceRevision
                  }
                  return $0.manifest.checkpointID < $1.manifest.checkpointID
              }),
              Set(state.checkpoints.map { $0.manifest.checkpointID }).count == state.checkpoints.count,
              state.replayReceipts.map(\.batchSHA256) == state.replayReceipts.map(\.batchSHA256).sorted(),
              Set(state.replayReceipts.map(\.batchSHA256)).count == state.replayReceipts.count,
              Set(state.replayCursors.map {
                  $0.consumerReplicaID.rawValue.uuidString.lowercased() + ":" + $0.checkpointID
              }).count == state.replayCursors.count,
              state.unresolvedConflicts.map(\.digestSHA256) == state.unresolvedConflicts.map(\.digestSHA256).sorted(),
              Set(state.unresolvedConflicts).count == state.unresolvedConflicts.count,
              state.observedConflictInputs.map(\.entity.stableKey) == state.observedConflictInputs.map(\.entity.stableKey).sorted(),
              Set(state.observedConflictInputs.map(\.entity)).count == state.observedConflictInputs.count,
              state.pendingBatches.count <= limits.maximumReplicaFrontiers,
              state.pendingBatches.map(\.batchSHA256).count == Set(state.pendingBatches.map(\.batchSHA256)).count,
              state.pendingReplayBases.map(\.batchSHA256) == state.pendingReplayBases.map(\.batchSHA256).sorted(),
              Set(state.pendingReplayBases.map(\.batchSHA256)).count == state.pendingReplayBases.count,
              Set(state.pendingReplayBases.map(\.batchSHA256)).isSubset(of: Set(state.pendingBatches.map(\.batchSHA256))),
              Set(state.pendingBatches.map {
                  $0.sourceReplicaID.rawValue.uuidString.lowercased()
                    + ":" + $0.checkpointID
                    + ":" + String($0.beforeCursor.nextOrdinal)
              }).count == state.pendingBatches.count,
              state.pendingBatches == state.pendingBatches.sorted(by: {
                  if $0.beforeCursor.nextOrdinal != $1.beforeCursor.nextOrdinal {
                      return $0.beforeCursor.nextOrdinal < $1.beforeCursor.nextOrdinal
                  }
                  return $0.batchSHA256 < $1.batchSHA256
              }),
              state.contentQuarantines.count <= limits.maximumConflicts,
              state.contentQuarantines.map(\.stableKey) == state.contentQuarantines.map(\.stableKey).sorted(),
              Set(state.contentQuarantines.map(\.stableKey)).count == state.contentQuarantines.count else {
            throw ChangeJournalFailureV1.invalidValue
        }
    }

    private struct PreparedRecord: Codable {
        let preparation: WorkspaceCheckpointPreparationV1
        let checkpoint: WorkspaceCheckpointContentV1
    }

    private struct ObservedConflictInputs: Codable {
        let entity: WorkspaceEntityIdentityV1
        let competitors: [ConflictCompetitorV1]

        init(entity: WorkspaceEntityIdentityV1, competitors: [ConflictCompetitorV1]) throws {
            guard !competitors.isEmpty,
                  competitors.count <= ConflictCompetitorV1.maximumCount else {
                throw ChangeJournalFailureV1.limitExceeded
            }
            self.entity = entity
            self.competitors = competitors
            try validate()
        }

        func validate() throws {
            guard competitors.count <= ConflictCompetitorV1.maximumCount,
                  Set(competitors).count == competitors.count,
                  competitors == competitors.sorted(by: {
                      let left = $0.mutationID.rawValue.uuidString.lowercased() + ":" + $0.canonicalInputSHA256
                      let right = $1.mutationID.rawValue.uuidString.lowercased() + ":" + $1.canonicalInputSHA256
                      return left < right
                  }) else {
                throw ChangeJournalFailureV1.noncanonicalOrder
            }
        }
    }

    private struct DerivedContentQuarantine: Codable, Equatable {
        let batchSHA256: String
        let mutationID: MutationIDV1
        let changeSHA256: String

        var stableKey: String {
            batchSHA256 + ":" + mutationID.rawValue.uuidString.lowercased()
        }

        func validate() throws {
            guard LocalChangeJournalV1.isSHA256(batchSHA256),
                  LocalChangeJournalV1.isSHA256(changeSHA256) else {
                throw ChangeJournalFailureV1.invalidDigest
            }
        }
    }

    private struct PendingReplayBasis: Codable {
        let batchSHA256: String
        let preexistingMutationIDs: [MutationIDV1]

        func validate() throws {
            guard LocalChangeJournalV1.isSHA256(batchSHA256),
                  preexistingMutationIDs.map({ $0.rawValue.uuidString.lowercased() })
                    == preexistingMutationIDs.map({ $0.rawValue.uuidString.lowercased() }).sorted(),
                  Set(preexistingMutationIDs).count == preexistingMutationIDs.count else {
                throw ChangeJournalFailureV1.invalidValue
            }
        }
    }

    private struct PersistentSchemaDigestBasis: Codable {
        let persistentSchemaVersion: Int
        let compatibilityID: String
        let modelNames: [String]
    }

    private struct RecordSchemaDigestBasis: Codable {
        let recordsSchemaVersion: Int
        let orderedFields: [String]
    }

    private static let v4BackupRecordFields = [
        "assets", "deletionLedger", "evidenceFiles", "issues", "mutationHistory",
        "packets", "recordsSchemaVersion", "reports", "sites", "workflowRecords",
    ]

    private static let v5BackupRecordFields = [
        "assetCompositionEdges", "assetCompositionEvents", "assetPlacementEvents",
        "assets", "deletionLedger", "evidenceFiles", "issues", "locationHierarchyEvents",
        "locationMigrationReceipts", "locationNodes", "mutationHistory", "packets",
        "recordsSchemaVersion", "reports", "sites", "workflowRecords",
    ]

    private static let v6BackupRecordFields = [
        "assetCompositionEdges", "assetCompositionEvents", "assetPlacementEvents",
        "assets", "deletionLedger", "evidenceFiles", "issues", "locationHierarchyEvents",
        "locationMigrationReceipts", "locationNodes", "mutationHistory", "packets",
        "recordsSchemaVersion", "reports", "savedSmartViews", "sites", "workflowRecords",
    ]

    private static let v7BackupRecordFields = [
        "assetCompositionEdges", "assetCompositionEvents", "assetPlacementEvents",
        "assets", "deletionLedger", "evidenceFiles", "issues", "locationHierarchyEvents",
        "locationMigrationReceipts", "locationNodes", "mutationHistory", "packets",
        "recordsSchemaVersion", "reports", "requirementAssurance", "savedSmartViews",
        "sites", "workflowRecords",
    ]

    private static func backupRecordFields(for version: Int) -> [String] {
        if version <= 4 { return v4BackupRecordFields }
        if version == 5 { return v5BackupRecordFields }
        if version == 6 { return v6BackupRecordFields }
        var fields = v7BackupRecordFields
        if version >= 8 { fields.append("partyAccountability") }
        if version >= 9 { fields.append("assetSemantics") }
        if version >= 10 { fields.append("authorityCriterion") }
        if version >= 11 { fields.append("functionalRelationships") }
        if version >= 12 { fields.append("evidenceAssurance") }
        if version >= 13 { fields.append("inspectionReview") }
        if version >= 14 { fields.append("workPackets") }
        if version >= 15 { fields.append("fieldDrafts") }
        return fields.sorted()
    }

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }()

    private static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }

    private static func isSHA256(_ value: String) -> Bool {
        MutationEnvelopeV1.isSHA256(value)
    }

    private static func isDeferred(_ receipt: ChangeReplayReceiptV1) -> Bool {
        receipt.dispositions.contains {
            switch $0.disposition {
            case .deferredGap, .deferredContent, .unresolvedConflict, .rejected:
                return true
            case .applied, .alreadyApplied, .deleteWon, .derivedRebuild, .localOnlyExcluded:
                return false
            }
        }
    }

    private static func rawSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isTombstone(_ value: MutationPostImageV1) -> Bool {
        if case .tombstone = value { return true }
        return false
    }

    private static func validateAssetSemanticChange(
        _ change: JournalChangeV1
    ) throws {
        guard case let .applyAssetSemantics(mutation) = change.envelope.command else {
            return
        }
        do {
            try mutation.validate()
            let identity = try mutation.affectedIdentity
            let postImageIdentities = try change.receipt.postImages.map { try $0.identity }
            guard change.envelope.commandKind == .applyAssetSemantics,
                  change.envelope.mutationID == mutation.mutationID,
                  change.receipt.mutationID == mutation.mutationID,
                  postImageIdentities == [identity],
                  change.entityChanges.map(\.identity) == [identity] else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        } catch let failure as ChangeJournalFailureV1 {
            throw failure
        } catch {
            throw ChangeJournalFailureV1.tamperedBatch
        }
    }

    private static func validateAuthorityCriterionChange(_ change: JournalChangeV1) throws {
        guard case let .applyAuthorityCriterion(mutation) = change.envelope.command else { return }
        do {
            try mutation.validate()
            let identity = try mutation.affectedIdentity
            let postImages = change.receipt.postImages
            guard change.envelope.commandKind == .applyAuthorityCriterion,
                  change.envelope.mutationID == mutation.mutationID,
                  change.receipt.mutationID == mutation.mutationID,
                  postImages == [try mutation.postImage.mutationPostImage],
                  change.entityChanges.map(\.identity) == [identity],
                  change.entityChanges.map(\.postImage) == postImages else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        } catch let failure as ChangeJournalFailureV1 { throw failure }
        catch { throw ChangeJournalFailureV1.tamperedBatch }
    }

    private static func validateFunctionalRelationshipChange(_ change: JournalChangeV1) throws {
        guard case let .applyFunctionalRelationship(mutation) = change.envelope.command else { return }
        do {
            try mutation.validate()
            let identity = try mutation.affectedIdentity
            let postImages = change.receipt.postImages
            guard change.envelope.commandKind == .applyFunctionalRelationship,
                  change.envelope.mutationID == mutation.mutationID,
                  change.receipt.mutationID == mutation.mutationID,
                  postImages == [try mutation.postImage.mutationPostImage],
                  change.entityChanges.map(\.identity) == [identity],
                  change.entityChanges.map(\.postImage) == postImages else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        } catch let failure as ChangeJournalFailureV1 { throw failure }
        catch { throw ChangeJournalFailureV1.tamperedBatch }
    }
    private static func validateEvidenceAssuranceChange(_ change:JournalChangeV1)throws{guard case let .applyEvidenceAssurance(m)=change.envelope.command else{return};do{try m.validate();let i=try m.affectedIdentity;let images=change.receipt.postImages;guard change.envelope.commandKind == .applyEvidenceAssurance,change.envelope.mutationID==m.mutationID,change.receipt.mutationID==m.mutationID,images==[try m.postImage.mutationPostImage],change.entityChanges.map(\.identity)==[i],change.entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch}}catch let f as ChangeJournalFailureV1{throw f}catch{throw ChangeJournalFailureV1.tamperedBatch}}
    private static func validateInspectionReviewChange(_ change:JournalChangeV1)throws{do{try InspectionReviewJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)}catch let f as ChangeJournalFailureV1{throw f}catch{throw ChangeJournalFailureV1.tamperedBatch}}
    private static func validatePortableReviewChange(_ change:JournalChangeV1)throws{do{try PortableReviewJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)}catch let f as ChangeJournalFailureV1{throw f}catch{throw ChangeJournalFailureV1.tamperedBatch}}
    private static func validateWorkResourceChange(_ change:JournalChangeV1)throws{do{try WorkResourceJournalContractV1.validate(envelope:change.envelope,receipt:change.receipt,entityChanges:change.entityChanges)}catch let f as ChangeJournalFailureV1{throw f}catch{throw ChangeJournalFailureV1.tamperedBatch}}
    private static func validateC51ScheduleExceptionChange(_ change: JournalChangeV1) throws {
        guard case let .applySchedule(mutation) = change.envelope.command else { return }
        switch mutation.payload {
        case .appendExceptionCalendarRelease:
            guard change.entityChanges.map(\.identity.kind) == [.exceptionCalendarRelease] else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        case .appendOverrideEvent:
            guard change.entityChanges.map(\.identity.kind) == [.scheduleOverrideEvent] else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        default:
            return
        }
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

private extension ConflictSubjectIdentityV1 {
    var workspaceIdentity: WorkspaceID {
        switch self {
        case .workspace(let workspaceID), .entity(let workspaceID, _): return workspaceID
        }
    }
}

@MainActor
extension StoreSessionCoordinator {
    func localChangeJournal(
        backupExport: BackupExportService,
        limits: ChangeJournalLimitsV1 = try! ChangeJournalLimitsV1(),
        policyResolver: @escaping LocalChangeJournalV1.ConflictPolicyResolver,
        contentReferenceResolver: @escaping LocalChangeJournalV1.ContentReferenceResolver,
        contentEntryResolver: @escaping LocalChangeJournalV1.ContentEntryResolver,
        portableReversalPlanResolver: @escaping LocalChangeJournalV1.PortableReversalPlanResolver = { _, _ in nil },
        fileManager: FileManager = .default,
        makeUUID: @escaping () -> UUID = UUID.init,
        interruptionPoint: @escaping () -> LocalChangeJournalV1.InterruptionPointV1 = { .none }
    ) throws -> LocalChangeJournalV1 {
        try LocalChangeJournalV1(
            identity: workspaceIdentity,
            generationID: generationID,
            generationRootURL: generationRootURL,
            writer: workspaceWriter,
            backupExport: backupExport,
            limits: limits,
            policyResolver: policyResolver,
            contentReferenceResolver: contentReferenceResolver,
            contentEntryResolver: contentEntryResolver,
            portableReversalPlanResolver: portableReversalPlanResolver,
            fileManager: fileManager,
            makeUUID: makeUUID,
            interruptionPoint: interruptionPoint
        )
    }
}

enum LightingLocalChangeJournalPolicyV1 { static let commandKind:WorkspaceCommandKindV1 = .applyLighting;static let durableEntityKinds:Set<WorkspaceEntityKindV1>=[.lightingSystem,.lightingObservation,.lightingIssue,.lightingMeasurementPlan,.lightingClaimState];static func validate(_ envelope:MutationEnvelopeV1)throws{guard case let .applyLighting(operation)=envelope.command else{return};try operation.validate();guard envelope.commandKind==commandKind,envelope.mutationID==operation.mutationID else{throw ChangeJournalFailureV1.tamperedBatch}} }

enum AssistanceLocalChangeJournalPolicyV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let proposalJournalPersistence = "OUTER_ACCEPTANCE_ENVELOPE_ONLY"

    static func validate(_ change: JournalChangeV1) throws {
        guard case let .applyAssistanceAcceptance(request) = change.envelope.command else { return }
        do {
            try request.validate()
            let affected = try request.targetMutation.affectedIdentities.sorted {
                $0.stableKey < $1.stableKey
            }
            let imageIdentities = try change.receipt.postImages.map(\.identity).sorted {
                $0.stableKey < $1.stableKey
            }
            let projected = try AssistanceAcceptanceReceiptV1(
                request: request,
                canonicalMutationReceipt: change.receipt
            )
            guard proposalJournalPersistence == "OUTER_ACCEPTANCE_ENVELOPE_ONLY",
                  change.envelope.commandKind == commandKind,
                  change.envelope.mutationID == request.mutationID,
                  change.receipt.mutationID == request.mutationID,
                  affected == imageIdentities,
                  Set(affected) == Set(change.entityChanges.map(\.identity)),
                  projected.mutationID == request.mutationID else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        } catch let failure as ChangeJournalFailureV1 { throw failure }
        catch { throw ChangeJournalFailureV1.tamperedBatch }
    }
}


enum TemporalEvidenceLocalChangeJournalPolicyV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyTemporalEvidence
    static let originalContentTravelsOnlyByDigestVerifiedCheckpointMember = true

    static func validate(_ change: JournalChangeV1) throws {
        guard case let .applyTemporalEvidence(mutation) = change.envelope.command else { return }
        do {
            try C33TemporalEvidenceJournalBoundaryV1.validate(
                mutation: mutation,
                receipt: change.receipt
            )
            let affected = try mutation.affectedIdentities
            guard change.envelope.commandKind == commandKind,
                  change.envelope.mutationID == mutation.mutationID,
                  change.receipt.mutationID == mutation.mutationID,
                  change.receipt.postImages == (try mutation.mutationPostImages),
                  Set(change.entityChanges.map(\.identity)) == Set(affected),
                  change.entityChanges.map(\.postImage) == change.receipt.postImages,
                  originalContentTravelsOnlyByDigestVerifiedCheckpointMember else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        } catch let failure as ChangeJournalFailureV1 { throw failure }
        catch { throw ChangeJournalFailureV1.tamperedBatch }
    }
}

enum C45AcceptedLabelLocalJournalBoundaryV1 { static let replaysAcceptedSnapshot=true;static let replaysProjectionScratch=false }

enum OperationalContactLocalChangeJournalPolicyV1 {
    static let commandKind: WorkspaceCommandKindV1 = .applyOperationalContact
    static let durableKinds: Set<WorkspaceEntityKindV1> = [
        .serviceContactPoint, .systemHandoffIntent,
    ]

    static func validate(_ change: JournalChangeV1) throws {
        guard case let .applyOperationalContact(mutation) = change.envelope.command else { return }
        do {
            try mutation.validate()
            let receipt = try OperationalContactMutationReceiptV1(
                mutation: mutation,
                mutationReceipt: change.receipt
            )
            let identities = try mutation.affectedIdentities
            guard change.envelope.commandKind == commandKind,
                  change.envelope.mutationID == mutation.mutationID,
                  change.receipt.postImages == (try mutation.mutationPostImages),
                  Set(change.entityChanges.map(\.identity)) == Set(identities),
                  change.entityChanges.map(\.postImage) == change.receipt.postImages,
                  try change.receipt.postImages.allSatisfy {
                    durableKinds.contains(try $0.identity.kind)
                  },
                  receipt.mutationID == mutation.mutationID else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        } catch let failure as ChangeJournalFailureV1 { throw failure }
        catch { throw ChangeJournalFailureV1.tamperedBatch }
    }
}

enum C46OperationalContactBoundary_22{static let commandKind:WorkspaceCommandKindV1 = .applyOperationalContact;static let platformOutcomesProjected=false}
enum C47ActivityContractLocalJournalBoundaryV2 { static let commandKind:WorkspaceCommandKindV1 = .applyActivityContract;static let replayUsesExactMutationPostimages=true;static let completedSnapshotReferenceDoesNotDuplicateBytes=true }
enum C48PortableReviewLocalJournalBoundaryV1 { static let commandKind:WorkspaceCommandKindV1 = .applyPortableReview;static let replayUsesExactEnvelopeBytesAndExistingC14Postimages=true;static let sessionOnlyHistoryIsExcluded=true }

enum C50IncumbentFileExchangeLocalChangeJournalBoundaryV1 {
    static let profileSelectionSessionSourceQuarantineDisposition = "NONPERSISTENT"
    static let newJournalSubjectCount = 0
    static let adapterStateIsExcluded = true
    static let sourceScratchAndQuarantineAreExcluded = true
    static let canonicalImportedEffectsUseExistingLocalJournal = true
    static let replayDisposition = "NOT_APPLICABLE"
    static let syncDisposition = "NOT_APPLICABLE"

    static func validate() -> Bool {
        profileSelectionSessionSourceQuarantineDisposition == "NONPERSISTENT"
            && newJournalSubjectCount == 0
            && adapterStateIsExcluded
            && sourceScratchAndQuarantineAreExcluded
            && canonicalImportedEffectsUseExistingLocalJournal
            && replayDisposition == "NOT_APPLICABLE"
            && syncDisposition == "NOT_APPLICABLE"
            && C50IncumbentFileExchangePersistenceBoundaryV1.validate()
    }
}

enum C34SceneNavigationLocalJournalBoundaryV1 {
    static let durableRouteKindCount = 0
    static let journalsResolutionOrRestoration = false
    static func validate() -> Bool { durableRouteKindCount == 0 && !journalsResolutionOrRestoration && C34SceneNavigationChangeJournalBoundaryV1.validate() }
}

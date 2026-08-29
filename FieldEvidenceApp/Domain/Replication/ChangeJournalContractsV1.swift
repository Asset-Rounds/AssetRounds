import CryptoKit
import Foundation

enum ChangeJournalFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion
    case invalidValue
    case invalidDigest
    case limitExceeded
    case duplicateValue
    case noncanonicalOrder
    case wrongWorkspace
    case wrongGeneration
    case unknownCheckpoint
    case unknownCursor
    case staleCursor
    case discontinuousBatch
    case tamperedBatch
    case missingContent
    case unresolvedConflict
    case invalidReversal
    case incompleteCheckpoint
}

/// C17 lifecycle declaration. Integration events and consumer checkpoints are
/// derived only: accepted mutation receipts/journal history are the exclusive
/// rebuild input, and every operational byte may be dropped on delete, Erase,
/// downgrade, restore, or recovery without affecting canonical truth.
struct IntegrationEventJournalCoverageV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sourceTruth: String
    let projectionSchema: String
    let acceptedReceiptAndJournalOnly: Bool
    let providerNeutral: Bool
    let canonicalPersistence: Bool
    let backupIncluded: Bool
    let restoreIncluded: Bool
    let exportIncluded: Bool
    let reportSourceOfTruth: Bool
    let dropAndRebuild: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceTruth = "ACCEPTED_MUTATION_RECEIPTS_AND_CHANGE_JOURNAL_V1"
        projectionSchema = "INTEGRATION_PROJECTION_SCHEMA_V1"
        acceptedReceiptAndJournalOnly = true
        providerNeutral = true
        canonicalPersistence = false
        backupIncluded = false
        restoreIncluded = false
        exportIncluded = false
        reportSourceOfTruth = false
        dropAndRebuild = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceTruth == "ACCEPTED_MUTATION_RECEIPTS_AND_CHANGE_JOURNAL_V1",
              projectionSchema == "INTEGRATION_PROJECTION_SCHEMA_V1",
              acceptedReceiptAndJournalOnly, providerNeutral,
              !canonicalPersistence, !backupIncluded, !restoreIncluded,
              !exportIncluded, !reportSourceOfTruth, dropAndRebuild else {
            throw ChangeJournalFailureV1.invalidValue
        }
    }
}

/// Declares C38 transport coverage without creating a network or identity
/// source. These kinds travel only as ordinary accepted writer envelopes.
struct PartyAccountabilityJournalCoverageV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let entityKinds: [WorkspaceEntityKindV1]
    let acceptedEnvelopeOnly: Bool
    let historicSnapshotsImmutable: Bool

    init(
        schemaVersion: Int = Self.schemaVersion,
        entityKinds: [WorkspaceEntityKindV1] = [
            .serviceParty, .sitePartyRoleEvent, .actorSnapshot,
            .qualificationSnapshot, .signoffSnapshot,
        ],
        acceptedEnvelopeOnly: Bool = true,
        historicSnapshotsImmutable: Bool = true
    ) throws {
        self.schemaVersion = schemaVersion
        self.entityKinds = entityKinds.sorted { $0.rawValue < $1.rawValue }
        self.acceptedEnvelopeOnly = acceptedEnvelopeOnly
        self.historicSnapshotsImmutable = historicSnapshotsImmutable
        try validate()
    }

    func validate() throws {
        let expected: Set<WorkspaceEntityKindV1> = [
            .serviceParty, .sitePartyRoleEvent, .actorSnapshot,
            .qualificationSnapshot, .signoffSnapshot,
        ]
        guard schemaVersion == Self.schemaVersion,
              Set(entityKinds) == expected,
              entityKinds.count == expected.count,
              entityKinds == entityKinds.sorted(by: { $0.rawValue < $1.rawValue }),
              acceptedEnvelopeOnly, historicSnapshotsImmutable else {
            throw ChangeJournalFailureV1.invalidValue
        }
    }
}

/// Declares the C39 transport invariants.  Semantic rows use the existing
/// Asset entity identity; paired lifecycle facts are carried by one accepted
/// envelope and changed input remains subject to the journal quarantine.
struct AssetSemanticJournalCoverageV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let entityKinds: [WorkspaceEntityKindV1]
    let atomicLifecyclePairing: Bool
    let changedInputQuarantine: Bool
    let acceptedEnvelopeOnly: Bool
    let historicSnapshotsImmutable: Bool

    init(
        schemaVersion: Int = Self.schemaVersion,
        entityKinds: [WorkspaceEntityKindV1] = [.asset],
        atomicLifecyclePairing: Bool = true,
        changedInputQuarantine: Bool = true,
        acceptedEnvelopeOnly: Bool = true,
        historicSnapshotsImmutable: Bool = true
    ) throws {
        self.schemaVersion = schemaVersion
        self.entityKinds = entityKinds.sorted { $0.rawValue < $1.rawValue }
        self.atomicLifecyclePairing = atomicLifecyclePairing
        self.changedInputQuarantine = changedInputQuarantine
        self.acceptedEnvelopeOnly = acceptedEnvelopeOnly
        self.historicSnapshotsImmutable = historicSnapshotsImmutable
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              entityKinds == [.asset],
              atomicLifecyclePairing,
              changedInputQuarantine,
              acceptedEnvelopeOnly,
              historicSnapshotsImmutable else {
            throw ChangeJournalFailureV1.invalidValue
        }
    }
}

/// C22 recovery verification is a consumer of the journal, not a second
/// canonical writer.  Staging is disposable derived state; the accepted
/// verification receipt is immutable evidence bound to one archive and may
/// only be carried by a subsequent backup.  The coverage declaration keeps
/// the replay/frontier/reconciliation/cleanup boundary explicit without
/// duplicating the recoverability contracts.
struct RecoverabilityVerificationJournalCoverageV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let sourceTruth = "RECOVERABILITY_VERIFICATION_RECEIPT_V1"
    static let projectionSchema = "RECOVERABILITY_VERIFICATION_JOURNAL_PROJECTION_V1"

    let schemaVersion: Int
    let sourceTruth: String
    let projectionSchema: String
    let stagingPersistence: String
    let receiptPersistence: String
    let backupEligibility: String
    let receiptOutsideVerifiedArchive: Bool
    let acceptedReceiptImmutable: Bool
    let orderedIdempotentReplay: Bool
    let contentAndCanonicalStateReconciliationRequired: Bool
    let cleanupIsolationRequired: Bool
    let stagingDropAndRebuild: Bool
    let liveWorkspaceMutationAllowed: Bool
    let sourceArchiveMutationAllowed: Bool
    let sourceArchiveRepairAllowed: Bool
    let externalCopyAvailabilityClaimed: Bool
    let secondWriterAllowed: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceTruth = Self.sourceTruth
        projectionSchema = Self.projectionSchema
        stagingPersistence = RecoverabilityVerificationLifecycleV1.stagingPersistence
        receiptPersistence = RecoverabilityVerificationLifecycleV1.receiptPersistence
        backupEligibility = RecoverabilityVerificationLifecycleV1.backupEligibility
        receiptOutsideVerifiedArchive = !RecoverabilityVerificationLifecycleV1.receiptInsideVerifiedArchive
        acceptedReceiptImmutable = true
        orderedIdempotentReplay = true
        contentAndCanonicalStateReconciliationRequired = true
        cleanupIsolationRequired = true
        stagingDropAndRebuild = true
        liveWorkspaceMutationAllowed = RecoverabilityVerificationLifecycleV1.liveRestorePermitted
        sourceArchiveMutationAllowed = false
        sourceArchiveRepairAllowed = false
        externalCopyAvailabilityClaimed = RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed
        secondWriterAllowed = false
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceTruth == Self.sourceTruth,
              projectionSchema == Self.projectionSchema,
              stagingPersistence == "DERIVED_ONLY_DROP_AND_REBUILD",
              receiptPersistence == "RECOVERABILITY_VERIFICATION_RECEIPT_V1_IMMUTABLE_EVIDENCE",
              backupEligibility == "SUBSEQUENT_BACKUPS_ONLY",
              receiptOutsideVerifiedArchive,
              acceptedReceiptImmutable,
              orderedIdempotentReplay,
              contentAndCanonicalStateReconciliationRequired,
              cleanupIsolationRequired,
              stagingDropAndRebuild,
              !liveWorkspaceMutationAllowed,
              !sourceArchiveMutationAllowed,
              !sourceArchiveRepairAllowed,
              !externalCopyAvailabilityClaimed,
              !secondWriterAllowed else {
            throw ChangeJournalFailureV1.invalidValue
        }
    }

    /// Validates the canonical C22 values at the journal boundary.  This is a
    /// projection check only; it does not persist staging or receipt bytes.
    func validate(
        staging: RecoverabilityVerificationStagingV1? = nil,
        receipt: RecoverabilityVerificationReceiptV1? = nil
    ) throws {
        try validate()
        if let staging {
            try staging.validate()
        }
        if let receipt {
            try receipt.validate()
            guard !receipt.receiptIncludedInVerifiedArchive else {
                throw ChangeJournalFailureV1.invalidValue
            }
            if let staging {
                guard staging.verificationID == receipt.verificationID,
                      staging.workspaceID == receipt.workspaceID,
                      staging.archive == receipt.archive,
                      staging.mode == receipt.mode else {
                    throw ChangeJournalFailureV1.invalidValue
                }
            }
        }
    }
}

struct ChangeJournalLimitsV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let productionMaximumChangesPerBatch = 128
    static let productionMaximumBatchBytes = 4_194_304
    static let productionMaximumEntitiesPerCheckpoint = 100_000
    static let productionMaximumContentEntriesPerCheckpoint = 100_000
    static let productionMaximumReplicaFrontiers = 64
    static let productionMaximumConflicts = 64
    let schemaVersion: Int
    let maximumChangesPerBatch: Int
    let maximumBatchBytes: Int
    let maximumEntitiesPerCheckpoint: Int
    let maximumContentEntriesPerCheckpoint: Int
    let maximumReplicaFrontiers: Int
    let maximumConflicts: Int

    init(
        maximumChangesPerBatch: Int = ChangeJournalLimitsV1.productionMaximumChangesPerBatch,
        maximumBatchBytes: Int = ChangeJournalLimitsV1.productionMaximumBatchBytes,
        maximumEntitiesPerCheckpoint: Int = ChangeJournalLimitsV1.productionMaximumEntitiesPerCheckpoint,
        maximumContentEntriesPerCheckpoint: Int = ChangeJournalLimitsV1.productionMaximumContentEntriesPerCheckpoint,
        maximumReplicaFrontiers: Int = ChangeJournalLimitsV1.productionMaximumReplicaFrontiers,
        maximumConflicts: Int = ChangeJournalLimitsV1.productionMaximumConflicts
    ) throws {
        schemaVersion = Self.schemaVersion
        self.maximumChangesPerBatch = maximumChangesPerBatch
        self.maximumBatchBytes = maximumBatchBytes
        self.maximumEntitiesPerCheckpoint = maximumEntitiesPerCheckpoint
        self.maximumContentEntriesPerCheckpoint = maximumContentEntriesPerCheckpoint
        self.maximumReplicaFrontiers = maximumReplicaFrontiers
        self.maximumConflicts = maximumConflicts
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              (1...Self.productionMaximumChangesPerBatch).contains(maximumChangesPerBatch),
              (1...Self.productionMaximumBatchBytes).contains(maximumBatchBytes),
              (1...Self.productionMaximumEntitiesPerCheckpoint).contains(maximumEntitiesPerCheckpoint),
              (1...Self.productionMaximumContentEntriesPerCheckpoint).contains(maximumContentEntriesPerCheckpoint),
              (1...Self.productionMaximumReplicaFrontiers).contains(maximumReplicaFrontiers),
              (1...Self.productionMaximumConflicts).contains(maximumConflicts) else {
            throw ChangeJournalFailureV1.limitExceeded
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, maximumChangesPerBatch, maximumBatchBytes, maximumEntitiesPerCheckpoint
        case maximumContentEntriesPerCheckpoint, maximumReplicaFrontiers, maximumConflicts
    }

    init(from decoder: any Decoder) throws {
        try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ChangeJournalFailureV1.incompatibleVersion
        }
        try self.init(
            maximumChangesPerBatch: c.decode(Int.self, forKey: .maximumChangesPerBatch),
            maximumBatchBytes: c.decode(Int.self, forKey: .maximumBatchBytes),
            maximumEntitiesPerCheckpoint: c.decode(Int.self, forKey: .maximumEntitiesPerCheckpoint),
            maximumContentEntriesPerCheckpoint: c.decode(Int.self, forKey: .maximumContentEntriesPerCheckpoint),
            maximumReplicaFrontiers: c.decode(Int.self, forKey: .maximumReplicaFrontiers),
            maximumConflicts: c.decode(Int.self, forKey: .maximumConflicts)
        )
    }
}

struct ReplicaRevisionFrontierV1: Codable, Equatable, Sendable {
    let replicaID: ReplicaID
    let localSequence: UInt64

    var stableKey: String { replicaID.rawValue.uuidString.lowercased() }

    init(replicaID: ReplicaID, localSequence: UInt64) throws {
        guard replicaID.rawValue != ChangeJournalValidationV1.zero else {
            throw ChangeJournalFailureV1.invalidValue
        }
        self.replicaID = replicaID
        self.localSequence = localSequence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case replicaID, localSequence }
    init(from decoder: any Decoder) throws {
        try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(replicaID: c.decode(ReplicaID.self, forKey: .replicaID), localSequence: c.decode(UInt64.self, forKey: .localSequence))
    }
}

struct ChangeJournalFrontierV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceRevision: UInt64
    let replicas: [ReplicaRevisionFrontierV1]
    let entityRevisionSHA256: String
    let observedMutationSetSHA256: String

    init(
        workspaceRevision: UInt64,
        replicas: [ReplicaRevisionFrontierV1],
        entityRevisionSHA256: String,
        observedMutationSetSHA256: String,
        limits: ChangeJournalLimitsV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceRevision = workspaceRevision
        self.replicas = replicas
        self.entityRevisionSHA256 = entityRevisionSHA256
        self.observedMutationSetSHA256 = observedMutationSetSHA256
        try validate(limits: limits)
    }

    func validate(limits: ChangeJournalLimitsV1) throws {
        try limits.validate()
        guard schemaVersion == Self.schemaVersion,
              replicas.count <= limits.maximumReplicaFrontiers,
              replicas.map(\.stableKey) == replicas.map(\.stableKey).sorted(),
              Set(replicas.map(\.replicaID)).count == replicas.count,
              ChangeJournalValidationV1.isSHA256(entityRevisionSHA256),
              ChangeJournalValidationV1.isSHA256(observedMutationSetSHA256) else {
            throw ChangeJournalFailureV1.invalidValue
        }
    }

    func canonicalSHA256() throws -> String {
        try validate(limits: ChangeJournalLimitsV1())
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceRevision, replicas, entityRevisionSHA256, observedMutationSetSHA256
    }
    init(from decoder: any Decoder) throws {
        try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }
        try self.init(
            workspaceRevision: c.decode(UInt64.self, forKey: .workspaceRevision),
            replicas: c.decode([ReplicaRevisionFrontierV1].self, forKey: .replicas),
            entityRevisionSHA256: c.decode(String.self, forKey: .entityRevisionSHA256),
            observedMutationSetSHA256: c.decode(String.self, forKey: .observedMutationSetSHA256),
            limits: ChangeJournalLimitsV1()
        )
    }
}

struct ChangeCursorV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let consumerReplicaID: ReplicaID
    let checkpointID: String
    let frontierSHA256: String
    let nextOrdinal: UInt64
    let previousBatchSHA256: String?

    init(workspaceID: WorkspaceID, consumerReplicaID: ReplicaID, checkpointID: String, frontierSHA256: String, nextOrdinal: UInt64, previousBatchSHA256: String?) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.consumerReplicaID = consumerReplicaID
        self.checkpointID = checkpointID
        self.frontierSHA256 = frontierSHA256
        self.nextOrdinal = nextOrdinal
        self.previousBatchSHA256 = previousBatchSHA256
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != ChangeJournalValidationV1.zero,
              consumerReplicaID.rawValue != ChangeJournalValidationV1.zero,
              ChangeJournalValidationV1.isSHA256(checkpointID),
              ChangeJournalValidationV1.isSHA256(frontierSHA256),
              previousBatchSHA256.map(ChangeJournalValidationV1.isSHA256) ?? true,
              (nextOrdinal == 0) == (previousBatchSHA256 == nil) else { throw ChangeJournalFailureV1.invalidValue }
    }

    func validate(workspaceID: WorkspaceID, consumerReplicaID: ReplicaID, checkpointID: String, frontierSHA256: String) throws {
        try validate()
        guard self.workspaceID == workspaceID else { throw ChangeJournalFailureV1.wrongWorkspace }
        guard self.consumerReplicaID == consumerReplicaID else { throw ChangeJournalFailureV1.unknownCursor }
        guard self.checkpointID == checkpointID else { throw ChangeJournalFailureV1.unknownCheckpoint }
        guard self.frontierSHA256 == frontierSHA256 else { throw ChangeJournalFailureV1.staleCursor }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, consumerReplicaID, checkpointID, frontierSHA256, nextOrdinal, previousBatchSHA256 }
    init(from decoder: any Decoder) throws {
        try ChangeJournalClosedCodingV1.requireClosed(decoder, CodingKeys.self, required: [.schemaVersion, .workspaceID, .consumerReplicaID, .checkpointID, .frontierSHA256, .nextOrdinal]); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), consumerReplicaID: c.decode(ReplicaID.self, forKey: .consumerReplicaID), checkpointID: c.decode(String.self, forKey: .checkpointID), frontierSHA256: c.decode(String.self, forKey: .frontierSHA256), nextOrdinal: c.decode(UInt64.self, forKey: .nextOrdinal), previousBatchSHA256: c.decodeIfPresent(String.self, forKey: .previousBatchSHA256))
    }
    func encode(to encoder: any Encoder) throws {
        try validate(); var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(consumerReplicaID, forKey: .consumerReplicaID); try c.encode(checkpointID, forKey: .checkpointID)
        try c.encode(frontierSHA256, forKey: .frontierSHA256); try c.encode(nextOrdinal, forKey: .nextOrdinal)
        try c.encode(previousBatchSHA256, forKey: .previousBatchSHA256)
    }
}

struct CheckpointPackageDigestV1: Codable, Equatable, Sendable {
    let packageID: String
    let packageSchemaVersion: Int
    let contentVersion: Int
    let packageSHA256: String
    var releaseKey: String { "\(packageID):\(packageSchemaVersion):\(contentVersion)" }
    var stableKey: String { "\(packageID):\(packageSchemaVersion):\(contentVersion):\(packageSHA256)" }

    init(packageID: String, packageSchemaVersion: Int, contentVersion: Int, packageSHA256: String) throws {
        guard ChangeJournalValidationV1.validToken(packageID), packageSchemaVersion > 0,
              contentVersion > 0, ChangeJournalValidationV1.isSHA256(packageSHA256) else {
            throw ChangeJournalFailureV1.invalidValue
        }
        self.packageID = packageID; self.packageSchemaVersion = packageSchemaVersion
        self.contentVersion = contentVersion; self.packageSHA256 = packageSHA256
    }
    func canonicalSHA256() throws -> String { try WorkspaceMutationCanonicalV1.sha256(self) }
    private enum CodingKeys: String, CodingKey, CaseIterable { case packageID, packageSchemaVersion, contentVersion, packageSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(packageID: c.decode(String.self, forKey: .packageID), packageSchemaVersion: c.decode(Int.self, forKey: .packageSchemaVersion), contentVersion: c.decode(Int.self, forKey: .contentVersion), packageSHA256: c.decode(String.self, forKey: .packageSHA256)) }
}

struct WorkspaceSnapshotManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let sourceReplicaID: ReplicaID
    let sourceGenerationID: UUID
    let persistentSchemaVersion: Int
    let persistentSchemaSHA256: String
    let recordSchemaVersion: Int
    let recordSchemaSHA256: String
    let packages: [CheckpointPackageDigestV1]
    let frontier: ChangeJournalFrontierV1
    let normalizedRecordsSHA256: String
    let tombstonesSHA256: String
    let contentManifestSHA256: String
    let reversalEligibilitySHA256: String
    let checkpointID: String
    let manifestSHA256: String

    init(workspaceID: WorkspaceID, sourceReplicaID: ReplicaID, sourceGenerationID: UUID, persistentSchemaVersion: Int, persistentSchemaSHA256: String, recordSchemaVersion: Int, recordSchemaSHA256: String, packages: [CheckpointPackageDigestV1], frontier: ChangeJournalFrontierV1, normalizedRecordsSHA256: String, tombstonesSHA256: String, contentManifestSHA256: String, reversalEligibilitySHA256: String, limits: ChangeJournalLimitsV1) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.sourceReplicaID = sourceReplicaID; self.sourceGenerationID = sourceGenerationID
        self.persistentSchemaVersion = persistentSchemaVersion; self.persistentSchemaSHA256 = persistentSchemaSHA256; self.recordSchemaVersion = recordSchemaVersion; self.recordSchemaSHA256 = recordSchemaSHA256
        self.packages = packages; self.frontier = frontier; self.normalizedRecordsSHA256 = normalizedRecordsSHA256; self.tombstonesSHA256 = tombstonesSHA256; self.contentManifestSHA256 = contentManifestSHA256; self.reversalEligibilitySHA256 = reversalEligibilitySHA256
        let identity = IdentityBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, sourceGenerationID: sourceGenerationID, persistentSchemaVersion: persistentSchemaVersion, persistentSchemaSHA256: persistentSchemaSHA256, recordSchemaVersion: recordSchemaVersion, recordSchemaSHA256: recordSchemaSHA256, packages: packages, frontier: frontier, normalizedRecordsSHA256: normalizedRecordsSHA256, tombstonesSHA256: tombstonesSHA256, contentManifestSHA256: contentManifestSHA256, reversalEligibilitySHA256: reversalEligibilitySHA256)
        checkpointID = try WorkspaceMutationCanonicalV1.sha256(identity)
        let basis = DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, sourceGenerationID: sourceGenerationID, persistentSchemaVersion: persistentSchemaVersion, persistentSchemaSHA256: persistentSchemaSHA256, recordSchemaVersion: recordSchemaVersion, recordSchemaSHA256: recordSchemaSHA256, packages: packages, frontier: frontier, normalizedRecordsSHA256: normalizedRecordsSHA256, tombstonesSHA256: tombstonesSHA256, contentManifestSHA256: contentManifestSHA256, reversalEligibilitySHA256: reversalEligibilitySHA256, checkpointID: checkpointID)
        manifestSHA256 = try WorkspaceMutationCanonicalV1.sha256(basis)
        try validate(limits: limits)
    }

    func validate(limits: ChangeJournalLimitsV1) throws {
        try frontier.validate(limits: limits)
        let hashes = [persistentSchemaSHA256, recordSchemaSHA256, normalizedRecordsSHA256, tombstonesSHA256, contentManifestSHA256, reversalEligibilitySHA256, checkpointID, manifestSHA256]
        guard schemaVersion == Self.schemaVersion, workspaceID.rawValue != ChangeJournalValidationV1.zero, sourceReplicaID.rawValue != ChangeJournalValidationV1.zero, sourceGenerationID != ChangeJournalValidationV1.zero, persistentSchemaVersion > 0, recordSchemaVersion > 0, packages.count <= 256, packages.map(\.stableKey) == packages.map(\.stableKey).sorted(), Set(packages.map(\.stableKey)).count == packages.count, Set(packages.map(\.releaseKey)).count == packages.count, hashes.allSatisfy(ChangeJournalValidationV1.isSHA256) else { throw ChangeJournalFailureV1.invalidValue }
        let rebuilt = try Self(workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, sourceGenerationID: sourceGenerationID, persistentSchemaVersion: persistentSchemaVersion, persistentSchemaSHA256: persistentSchemaSHA256, recordSchemaVersion: recordSchemaVersion, recordSchemaSHA256: recordSchemaSHA256, packages: packages, frontier: frontier, normalizedRecordsSHA256: normalizedRecordsSHA256, tombstonesSHA256: tombstonesSHA256, contentManifestSHA256: contentManifestSHA256, reversalEligibilitySHA256: reversalEligibilitySHA256, limits: limits, skipValidation: true)
        guard checkpointID == rebuilt.checkpointID, manifestSHA256 == rebuilt.manifestSHA256 else { throw ChangeJournalFailureV1.invalidDigest }
    }

    private init(workspaceID: WorkspaceID, sourceReplicaID: ReplicaID, sourceGenerationID: UUID, persistentSchemaVersion: Int, persistentSchemaSHA256: String, recordSchemaVersion: Int, recordSchemaSHA256: String, packages: [CheckpointPackageDigestV1], frontier: ChangeJournalFrontierV1, normalizedRecordsSHA256: String, tombstonesSHA256: String, contentManifestSHA256: String, reversalEligibilitySHA256: String, limits: ChangeJournalLimitsV1, skipValidation: Bool) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.sourceReplicaID = sourceReplicaID; self.sourceGenerationID = sourceGenerationID; self.persistentSchemaVersion = persistentSchemaVersion; self.persistentSchemaSHA256 = persistentSchemaSHA256; self.recordSchemaVersion = recordSchemaVersion; self.recordSchemaSHA256 = recordSchemaSHA256; self.packages = packages; self.frontier = frontier; self.normalizedRecordsSHA256 = normalizedRecordsSHA256; self.tombstonesSHA256 = tombstonesSHA256; self.contentManifestSHA256 = contentManifestSHA256; self.reversalEligibilitySHA256 = reversalEligibilitySHA256
        checkpointID = try WorkspaceMutationCanonicalV1.sha256(IdentityBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, sourceGenerationID: sourceGenerationID, persistentSchemaVersion: persistentSchemaVersion, persistentSchemaSHA256: persistentSchemaSHA256, recordSchemaVersion: recordSchemaVersion, recordSchemaSHA256: recordSchemaSHA256, packages: packages, frontier: frontier, normalizedRecordsSHA256: normalizedRecordsSHA256, tombstonesSHA256: tombstonesSHA256, contentManifestSHA256: contentManifestSHA256, reversalEligibilitySHA256: reversalEligibilitySHA256))
        manifestSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, sourceGenerationID: sourceGenerationID, persistentSchemaVersion: persistentSchemaVersion, persistentSchemaSHA256: persistentSchemaSHA256, recordSchemaVersion: recordSchemaVersion, recordSchemaSHA256: recordSchemaSHA256, packages: packages, frontier: frontier, normalizedRecordsSHA256: normalizedRecordsSHA256, tombstonesSHA256: tombstonesSHA256, contentManifestSHA256: contentManifestSHA256, reversalEligibilitySHA256: reversalEligibilitySHA256, checkpointID: checkpointID))
    }

    private struct IdentityBasis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let sourceReplicaID: ReplicaID; let sourceGenerationID: UUID; let persistentSchemaVersion: Int; let persistentSchemaSHA256: String; let recordSchemaVersion: Int; let recordSchemaSHA256: String; let packages: [CheckpointPackageDigestV1]; let frontier: ChangeJournalFrontierV1; let normalizedRecordsSHA256: String; let tombstonesSHA256: String; let contentManifestSHA256: String; let reversalEligibilitySHA256: String }
    private struct DigestBasis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let sourceReplicaID: ReplicaID; let sourceGenerationID: UUID; let persistentSchemaVersion: Int; let persistentSchemaSHA256: String; let recordSchemaVersion: Int; let recordSchemaSHA256: String; let packages: [CheckpointPackageDigestV1]; let frontier: ChangeJournalFrontierV1; let normalizedRecordsSHA256: String; let tombstonesSHA256: String; let contentManifestSHA256: String; let reversalEligibilitySHA256: String; let checkpointID: String }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, sourceReplicaID, sourceGenerationID, persistentSchemaVersion, persistentSchemaSHA256, recordSchemaVersion, recordSchemaSHA256, packages, frontier, normalizedRecordsSHA256, tombstonesSHA256, contentManifestSHA256, reversalEligibilitySHA256, checkpointID, manifestSHA256 }
    init(from decoder: any Decoder) throws {
        try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }
        let rebuilt = try Self(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), sourceReplicaID: c.decode(ReplicaID.self, forKey: .sourceReplicaID), sourceGenerationID: c.decode(UUID.self, forKey: .sourceGenerationID), persistentSchemaVersion: c.decode(Int.self, forKey: .persistentSchemaVersion), persistentSchemaSHA256: c.decode(String.self, forKey: .persistentSchemaSHA256), recordSchemaVersion: c.decode(Int.self, forKey: .recordSchemaVersion), recordSchemaSHA256: c.decode(String.self, forKey: .recordSchemaSHA256), packages: c.decode([CheckpointPackageDigestV1].self, forKey: .packages), frontier: c.decode(ChangeJournalFrontierV1.self, forKey: .frontier), normalizedRecordsSHA256: c.decode(String.self, forKey: .normalizedRecordsSHA256), tombstonesSHA256: c.decode(String.self, forKey: .tombstonesSHA256), contentManifestSHA256: c.decode(String.self, forKey: .contentManifestSHA256), reversalEligibilitySHA256: c.decode(String.self, forKey: .reversalEligibilitySHA256), limits: ChangeJournalLimitsV1())
        guard try c.decode(String.self, forKey: .checkpointID) == rebuilt.checkpointID, try c.decode(String.self, forKey: .manifestSHA256) == rebuilt.manifestSHA256 else { throw ChangeJournalFailureV1.invalidDigest }
        self = rebuilt
    }
}

struct CheckpointContentEntryV1: Codable, Equatable, Sendable {
    let reference: ContentReferenceV1
    let archiveRelativePath: String
    var stableKey: String { reference.contentID }

    init(reference: ContentReferenceV1, archiveRelativePath: String) throws {
        guard ChangeJournalValidationV1.validRelativePath(archiveRelativePath) else { throw ChangeJournalFailureV1.invalidValue }
        self.reference = reference; self.archiveRelativePath = archiveRelativePath
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case reference, archiveRelativePath }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(reference: c.decode(ContentReferenceV1.self, forKey: .reference), archiveRelativePath: c.decode(String.self, forKey: .archiveRelativePath)) }
}

enum PortableReversalEligibilityV1: String, CaseIterable, Codable, Sendable {
    case eligible = "ELIGIBLE"
    case alreadyReversed = "ALREADY_REVERSED"
    case superseded = "SUPERSEDED"
    case irreversible = "IRREVERSIBLE"
    case erased = "ERASED"
}

struct PortableReversalPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let targetMutationID: MutationIDV1
    let targetReceiptIdentity: MutationReceiptIdentityV1
    let expectedRevision: MutationPortableExpectedRevisionV1
    let planDigest: String
    let compensatingCommands: [WorkspaceCommandV1]

    init(targetMutationID: MutationIDV1, targetReceiptIdentity: MutationReceiptIdentityV1, expectedRevision: MutationPortableExpectedRevisionV1, planDigest: String, compensatingCommands: [WorkspaceCommandV1]) throws {
        schemaVersion = Self.schemaVersion; self.targetMutationID = targetMutationID; self.targetReceiptIdentity = targetReceiptIdentity; self.expectedRevision = expectedRevision; self.planDigest = planDigest; self.compensatingCommands = compensatingCommands
        try validate()
    }
    init(basis: ReversalBasisV1, expectedRevision: MutationPortableExpectedRevisionV1, compensatingCommands: [WorkspaceCommandV1]) throws {
        guard compensatingCommands.map(\.kind) == basis.compensatingCommandKinds else { throw ChangeJournalFailureV1.invalidReversal }
        try self.init(targetMutationID: basis.targetMutationID, targetReceiptIdentity: basis.targetReceiptIdentity, expectedRevision: expectedRevision, planDigest: basis.planDigest, compensatingCommands: compensatingCommands)
    }
    init(plan: SemanticReversalPlanV1, targetReceiptIdentity: MutationReceiptIdentityV1) throws {
        try self.init(
            targetMutationID: plan.mutationID,
            targetReceiptIdentity: targetReceiptIdentity,
            expectedRevision: MutationPortableExpectedRevisionV1(plan.expectedRevision),
            planDigest: plan.planDigest,
            compensatingCommands: plan.compensatingCommands
        )
    }
    func validate() throws {
        try targetReceiptIdentity.validate(); try expectedRevision.validate()
        guard schemaVersion == Self.schemaVersion, targetReceiptIdentity.workspaceID == expectedRevision.workspaceID, ChangeJournalValidationV1.isSHA256(planDigest), !compensatingCommands.isEmpty, compensatingCommands.count <= SemanticReversalPlanV1.maximumItems else { throw ChangeJournalFailureV1.invalidReversal }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, targetMutationID, targetReceiptIdentity, expectedRevision, planDigest, compensatingCommands }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; try self.init(targetMutationID: c.decode(MutationIDV1.self, forKey: .targetMutationID), targetReceiptIdentity: c.decode(MutationReceiptIdentityV1.self, forKey: .targetReceiptIdentity), expectedRevision: c.decode(MutationPortableExpectedRevisionV1.self, forKey: .expectedRevision), planDigest: c.decode(String.self, forKey: .planDigest), compensatingCommands: c.decode([WorkspaceCommandV1].self, forKey: .compensatingCommands)) }
}

extension ReversalBasisV1 {
    init(portablePlan: PortableReversalPlanV1, targetReceiptIdentity: MutationReceiptIdentityV1) throws {
        try portablePlan.validate()
        try targetReceiptIdentity.validate()
        schemaVersion = Self.schemaVersion
        targetMutationID = portablePlan.targetMutationID
        self.targetReceiptIdentity = targetReceiptIdentity
        policyVersion = MutationReversalPolicyRegistryV1.version
        planDigest = portablePlan.planDigest
        compensatingCommandKinds = portablePlan.compensatingCommands.map(\.kind)
        try validate()
    }
}

struct ReversalEligibilitySnapshotV1: Codable, Equatable, Sendable {
    let targetMutationID: MutationIDV1
    let eligibility: PortableReversalEligibilityV1
    let portablePlan: PortableReversalPlanV1?
    let reversingMutationID: MutationIDV1?
    let basisSHA256: String?

    init(targetMutationID: MutationIDV1, eligibility: PortableReversalEligibilityV1, portablePlan: PortableReversalPlanV1?, reversingMutationID: MutationIDV1?, basisSHA256: String?) throws {
        guard (eligibility == .eligible) == (portablePlan != nil),
              (eligibility == .alreadyReversed) == (reversingMutationID != nil),
              (portablePlan?.targetMutationID == targetMutationID || portablePlan == nil),
              eligibility != .eligible || basisSHA256 != nil,
              basisSHA256.map(ChangeJournalValidationV1.isSHA256) ?? true else { throw ChangeJournalFailureV1.invalidReversal }
        self.targetMutationID = targetMutationID; self.eligibility = eligibility; self.portablePlan = portablePlan; self.reversingMutationID = reversingMutationID; self.basisSHA256 = basisSHA256
    }
    var stableKey: String { targetMutationID.rawValue.uuidString.lowercased() }
    private enum CodingKeys: String, CodingKey, CaseIterable { case targetMutationID, eligibility, portablePlan, reversingMutationID, basisSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireClosed(decoder, CodingKeys.self, required: [.targetMutationID, .eligibility]); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(targetMutationID: c.decode(MutationIDV1.self, forKey: .targetMutationID), eligibility: c.decode(PortableReversalEligibilityV1.self, forKey: .eligibility), portablePlan: c.decodeIfPresent(PortableReversalPlanV1.self, forKey: .portablePlan), reversingMutationID: c.decodeIfPresent(MutationIDV1.self, forKey: .reversingMutationID), basisSHA256: c.decodeIfPresent(String.self, forKey: .basisSHA256)) }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(targetMutationID, forKey: .targetMutationID)
        try c.encode(eligibility, forKey: .eligibility); try c.encode(portablePlan, forKey: .portablePlan)
        try c.encode(reversingMutationID, forKey: .reversingMutationID); try c.encode(basisSHA256, forKey: .basisSHA256)
    }
}

struct WorkspaceCheckpointContentV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let manifest: WorkspaceSnapshotManifestV1
    let normalizedRecordData: Data
    let tombstoneIdentities: [WorkspaceEntityIdentityV1]
    let contentEntries: [CheckpointContentEntryV1]
    let reversalEligibility: [ReversalEligibilitySnapshotV1]

    init(manifest: WorkspaceSnapshotManifestV1, normalizedRecordData: Data, tombstoneIdentities: [WorkspaceEntityIdentityV1], contentEntries: [CheckpointContentEntryV1], reversalEligibility: [ReversalEligibilitySnapshotV1], limits: ChangeJournalLimitsV1) throws {
        schemaVersion = Self.schemaVersion; self.manifest = manifest; self.normalizedRecordData = normalizedRecordData; self.tombstoneIdentities = tombstoneIdentities; self.contentEntries = contentEntries; self.reversalEligibility = reversalEligibility
        try validate(limits: limits)
    }
    func validate(limits: ChangeJournalLimitsV1) throws {
        try manifest.validate(limits: limits)
        guard schemaVersion == Self.schemaVersion, normalizedRecordData.count <= ChangeJournalLimitsV1.productionMaximumBatchBytes * 4,
              tombstoneIdentities.count <= limits.maximumEntitiesPerCheckpoint, tombstoneIdentities.map(\.stableKey) == tombstoneIdentities.map(\.stableKey).sorted(), Set(tombstoneIdentities).count == tombstoneIdentities.count,
              contentEntries.count <= limits.maximumContentEntriesPerCheckpoint, contentEntries.map(\.stableKey) == contentEntries.map(\.stableKey).sorted(), Set(contentEntries.map(\.stableKey)).count == contentEntries.count,
              reversalEligibility.map(\.stableKey) == reversalEligibility.map(\.stableKey).sorted(), Set(reversalEligibility.map(\.targetMutationID)).count == reversalEligibility.count,
              manifest.normalizedRecordsSHA256 == ChangeJournalValidationV1.sha256(normalizedRecordData),
              manifest.tombstonesSHA256 == (try WorkspaceMutationCanonicalV1.sha256(tombstoneIdentities)),
              manifest.contentManifestSHA256 == (try WorkspaceMutationCanonicalV1.sha256(contentEntries)),
              manifest.reversalEligibilitySHA256 == (try WorkspaceMutationCanonicalV1.sha256(reversalEligibility)) else { throw ChangeJournalFailureV1.invalidDigest }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, manifest, normalizedRecordData, tombstoneIdentities, contentEntries, reversalEligibility }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; try self.init(manifest: c.decode(WorkspaceSnapshotManifestV1.self, forKey: .manifest), normalizedRecordData: c.decode(Data.self, forKey: .normalizedRecordData), tombstoneIdentities: c.decode([WorkspaceEntityIdentityV1].self, forKey: .tombstoneIdentities), contentEntries: c.decode([CheckpointContentEntryV1].self, forKey: .contentEntries), reversalEligibility: c.decode([ReversalEligibilitySnapshotV1].self, forKey: .reversalEligibility), limits: ChangeJournalLimitsV1()) }
}

struct EntityChangeV1: Codable, Equatable, Sendable {
    let identity: WorkspaceEntityIdentityV1
    let postImage: MutationPostImageV1
    let conflictPolicy: ConflictPolicyV1
    let conflictIdentity: ConflictIdentityV1?

    init(postImage: MutationPostImageV1, conflictPolicy: ConflictPolicyV1, conflictIdentity: ConflictIdentityV1?) throws {
        identity = try postImage.identity; self.postImage = postImage; self.conflictPolicy = conflictPolicy; self.conflictIdentity = conflictIdentity
        try validate()
    }
    func validate() throws {
        try conflictPolicy.validate(); try conflictIdentity?.validate()
        let concurrencyIdentity = try postImage.concurrencyIdentity
        guard identity == (try postImage.identity),
              concurrencyIdentity.kind == identity.kind,
              postImage.revision > 0,
              ChangeJournalValidationV1.isSHA256(postImage.semanticSHA256),
              (conflictPolicy.rule == .exactRevisionManual) || conflictIdentity == nil else {
            throw ChangeJournalFailureV1.invalidValue
        }
    }
    var stableKey: String { identity.stableKey }
    private enum CodingKeys: String, CodingKey, CaseIterable { case identity, postImage, conflictPolicy, conflictIdentity }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireClosed(decoder, CodingKeys.self, required: [.identity, .postImage, .conflictPolicy]); let c = try decoder.container(keyedBy: CodingKeys.self); let value = try Self(postImage: c.decode(MutationPostImageV1.self, forKey: .postImage), conflictPolicy: c.decode(ConflictPolicyV1.self, forKey: .conflictPolicy), conflictIdentity: c.decodeIfPresent(ConflictIdentityV1.self, forKey: .conflictIdentity)); guard try c.decode(WorkspaceEntityIdentityV1.self, forKey: .identity) == value.identity else { throw ChangeJournalFailureV1.invalidValue }; self = value }
    func encode(to encoder: any Encoder) throws {
        try validate(); var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(identity, forKey: .identity)
        try c.encode(postImage, forKey: .postImage); try c.encode(conflictPolicy, forKey: .conflictPolicy)
        try c.encode(conflictIdentity, forKey: .conflictIdentity)
    }
}

struct JournalChangeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let envelope: MutationEnvelopeV1
    let receipt: MutationReceiptV1
    let entityChanges: [EntityChangeV1]
    let reversalBasis: ReversalBasisV1?
    let portableReversalPlan: PortableReversalPlanV1?
    let semanticReversalReceipt: SemanticReversalReceiptV1?
    let contentReferences: [ContentReferenceV1]

    init(envelope: MutationEnvelopeV1, receipt: MutationReceiptV1, entityChanges: [EntityChangeV1], reversalBasis: ReversalBasisV1?, portableReversalPlan: PortableReversalPlanV1?, semanticReversalReceipt: SemanticReversalReceiptV1?, contentReferences: [ContentReferenceV1]) throws {
        schemaVersion = Self.schemaVersion; self.envelope = envelope; self.receipt = receipt; self.entityChanges = entityChanges; self.reversalBasis = reversalBasis; self.portableReversalPlan = portableReversalPlan; self.semanticReversalReceipt = semanticReversalReceipt; self.contentReferences = contentReferences
        try validate()
    }
    func validate() throws {
        try envelope.validate(); try receipt.validate(); try reversalBasis?.validate(); try semanticReversalReceipt?.validate()
        try FunctionalRelationshipJournalContractV1.validate(
            envelope: envelope, receipt: receipt, entityChanges: entityChanges
        )
        try EvidenceAssuranceJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        try InspectionReviewJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        try WorkPacketJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        try FieldDraftJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        try PackagePromotionJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        try MeasurementIntegrityJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        try PrivacyTransformJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        try ClientCapabilityJournalContractV1.validate(envelope:envelope,receipt:receipt,entityChanges:entityChanges)
        let receiptIdentities = try receipt.postImages.map { try $0.identity }
        let locationIdentities = try envelope.command.canonicalLocationAffectedIdentities()
        guard schemaVersion == Self.schemaVersion, envelope.workspaceID == receipt.identity.workspaceID, envelope.replicaID == receipt.identity.replicaID, envelope.mutationID == receipt.mutationID, receipt.envelopeSHA256 == (try envelope.canonicalSHA256()),
              locationIdentities == nil || locationIdentities == receiptIdentities,
              entityChanges.map(\.stableKey) == entityChanges.map(\.stableKey).sorted(), Set(entityChanges.map(\.identity)).count == entityChanges.count, entityChanges.map(\.identity) == receiptIdentities,
              entityChanges.map(\.postImage) == receipt.postImages,
              contentReferences.map(\.contentID) == contentReferences.map(\.contentID).sorted(), Set(contentReferences.map(\.contentID)).count == contentReferences.count,
              contentReferences.map(\.contentID) == envelope.contentDependencyIDs,
              (reversalBasis == nil) == (portableReversalPlan == nil),
              reversalBasis?.targetReceiptIdentity.workspaceID == envelope.workspaceID || reversalBasis == nil,
              reversalBasis?.targetMutationID == receipt.mutationID || reversalBasis == nil,
              reversalBasis?.targetReceiptIdentity == receipt.identity || reversalBasis == nil,
              portableReversalPlan?.targetMutationID == reversalBasis?.targetMutationID,
              portableReversalPlan?.targetReceiptIdentity == reversalBasis?.targetReceiptIdentity,
              portableReversalPlan?.planDigest == reversalBasis?.planDigest,
              portableReversalPlan?.compensatingCommands.map(\.kind) == reversalBasis?.compensatingCommandKinds,
              portableReversalPlan?.expectedRevision == receipt.resultingRevision,
              semanticReversalReceipt?.reversalReceiptIdentity == receipt.identity || semanticReversalReceipt == nil else { throw ChangeJournalFailureV1.tamperedBatch }
    }
    var stableKey: String { receipt.identity.stableKey }
    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, envelope, receipt, entityChanges, reversalBasis, portableReversalPlan, semanticReversalReceipt, contentReferences }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireClosed(decoder, CodingKeys.self, required: [.schemaVersion, .envelope, .receipt, .entityChanges, .contentReferences]); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; try self.init(envelope: c.decode(MutationEnvelopeV1.self, forKey: .envelope), receipt: c.decode(MutationReceiptV1.self, forKey: .receipt), entityChanges: c.decode([EntityChangeV1].self, forKey: .entityChanges), reversalBasis: c.decodeIfPresent(ReversalBasisV1.self, forKey: .reversalBasis), portableReversalPlan: c.decodeIfPresent(PortableReversalPlanV1.self, forKey: .portableReversalPlan), semanticReversalReceipt: c.decodeIfPresent(SemanticReversalReceiptV1.self, forKey: .semanticReversalReceipt), contentReferences: c.decode([ContentReferenceV1].self, forKey: .contentReferences)) }
    func encode(to encoder: any Encoder) throws {
        try validate(); var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(envelope, forKey: .envelope); try c.encode(receipt, forKey: .receipt); try c.encode(entityChanges, forKey: .entityChanges)
        try c.encode(reversalBasis, forKey: .reversalBasis); try c.encode(portableReversalPlan, forKey: .portableReversalPlan)
        try c.encode(semanticReversalReceipt, forKey: .semanticReversalReceipt); try c.encode(contentReferences, forKey: .contentReferences)
    }
}

/// Closed C41 journal binding. Revision authority and post-image construction
/// remain owned by the canonical mutation and receipt contracts.
enum FunctionalRelationshipJournalContractV1 {
    static func validate(
        envelope: MutationEnvelopeV1,
        receipt: MutationReceiptV1,
        entityChanges: [EntityChangeV1]
    ) throws {
        guard case let .applyFunctionalRelationship(mutation) = envelope.command else { return }
        try mutation.validate()
        let affected = try mutation.affectedIdentity
        let expectedPostImage = try mutation.postImage.mutationPostImage
        switch mutation.postImage {
        case .appendDescriptor, .supersedeDescriptor:
            guard affected.kind == .functionalRelationshipTypeDescriptor,
                  case .functionalRelationshipTypeDescriptor = expectedPostImage else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        case .addRelationship, .endRelationship, .supersedeRelationship:
            guard affected.kind == .assetFunctionalRelationshipEvent,
                  case .assetFunctionalRelationshipEvent = expectedPostImage else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        }
        guard envelope.commandKind == .applyFunctionalRelationship,
              envelope.mutationID == mutation.mutationID,
              receipt.mutationID == mutation.mutationID,
              receipt.postImages == [expectedPostImage],
              entityChanges.map(\.identity) == [affected],
              entityChanges.map(\.postImage) == [expectedPostImage] else {
            throw ChangeJournalFailureV1.tamperedBatch
        }
    }
}
enum EvidenceAssuranceJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyEvidenceAssurance(m)=envelope.command else{return};try m.validate();let a=try m.affectedIdentity;let image=try m.postImage.mutationPostImage;guard envelope.commandKind == .applyEvidenceAssurance,receipt.mutationID==m.mutationID,receipt.postImages==[image],entityChanges.map(\.identity)==[a],entityChanges.map(\.postImage)==[image]else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum InspectionReviewJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyInspectionReview(m)=envelope.command else{return};try m.validate();let affected=try m.affectedIdentities;let images=try m.postImage.mutationPostImages;guard envelope.commandKind == .applyInspectionReview,envelope.mutationID==m.mutationID,receipt.mutationID==m.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch}}}

enum WorkPacketJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyWorkPacket(m)=envelope.command else{return};try m.validate();let a=try m.affectedIdentity;let image=try m.postImage.mutationPostImage;guard envelope.commandKind == .applyWorkPacket,envelope.mutationID==m.mutationID,receipt.mutationID==m.mutationID,receipt.postImages==[image],entityChanges.map(\.identity)==[a],entityChanges.map(\.postImage)==[image]else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum FieldDraftJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyFieldDraft(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentities,images=try mutation.postImage.mutationPostImages;guard envelope.commandKind == .applyFieldDraft,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum PackagePromotionJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyPackagePromotion(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentities,images=try mutation.mutationPostImages;guard envelope.commandKind == .applyPackagePromotion,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum MeasurementIntegrityJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyMeasurementIntegrity(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentities,images=try mutation.mutationPostImages;guard envelope.commandKind == .applyMeasurementIntegrity,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum PrivacyTransformJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyPrivacyTransform(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentities,images=try mutation.mutationPostImages;guard envelope.commandKind == .applyPrivacyTransform,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum ClientCapabilityJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyClientCapability(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentity,image=try mutation.mutationPostImage;guard envelope.commandKind == .applyClientCapability,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==[image],entityChanges.map(\.identity)==[affected],entityChanges.map(\.postImage)==[image]else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum FieldReferenceJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyFieldReference(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentity,image=try mutation.mutationPostImage;guard envelope.commandKind == .applyFieldReference,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==[image],entityChanges.map(\.identity)==[affected],entityChanges.map(\.postImage)==[image]else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum AccessibleDocumentAssessmentJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyAccessibleDocumentAssessment(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentity,image=try mutation.mutationPostImage;guard envelope.commandKind == .applyAccessibleDocumentAssessment,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==[image],entityChanges.map(\.identity)==[affected],entityChanges.map(\.postImage)==[image]else{throw ChangeJournalFailureV1.tamperedBatch}}}
enum SurveyDefinitionJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applySurveyDefinition(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentities,images=try mutation.mutationPostImages;guard envelope.commandKind == .applySurveyDefinition,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch}}}

enum SurveySessionJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applySurveySession(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentities,images=try mutation.mutationPostImages;guard envelope.commandKind == .applySurveySession,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch};_ = try SurveySessionMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}}
enum AssetLocatorJournalContractV1{static func validate(envelope:MutationEnvelopeV1,receipt:MutationReceiptV1,entityChanges:[EntityChangeV1])throws{guard case let .applyAssetLocator(mutation)=envelope.command else{return};try mutation.validate();let affected=try mutation.affectedIdentities,images=try mutation.mutationPostImages;guard envelope.commandKind == .applyAssetLocator,envelope.mutationID==mutation.mutationID,receipt.mutationID==mutation.mutationID,receipt.postImages==images,entityChanges.map(\.identity)==affected,entityChanges.map(\.postImage)==images else{throw ChangeJournalFailureV1.tamperedBatch};_ = try AssetLocatorMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}}

struct ChangeBatchV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let sourceReplicaID: ReplicaID
    let checkpointID: String
    let beforeCursor: ChangeCursorV1
    let afterCursor: ChangeCursorV1
    let changes: [JournalChangeV1]
    let batchSHA256: String

    init(workspaceID: WorkspaceID, sourceReplicaID: ReplicaID, checkpointID: String, beforeCursor: ChangeCursorV1, changes: [JournalChangeV1], limits: ChangeJournalLimitsV1) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.sourceReplicaID = sourceReplicaID; self.checkpointID = checkpointID; self.beforeCursor = beforeCursor; self.changes = changes
        guard beforeCursor.nextOrdinal <= UInt64.max - UInt64(changes.count) else { throw ChangeJournalFailureV1.limitExceeded }
        let prior = changes.isEmpty ? beforeCursor.previousBatchSHA256 : try WorkspaceMutationCanonicalV1.sha256(BatchBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, checkpointID: checkpointID, beforeCursor: beforeCursor, changes: changes))
        afterCursor = try ChangeCursorV1(workspaceID: workspaceID, consumerReplicaID: beforeCursor.consumerReplicaID, checkpointID: checkpointID, frontierSHA256: beforeCursor.frontierSHA256, nextOrdinal: beforeCursor.nextOrdinal + UInt64(changes.count), previousBatchSHA256: prior)
        batchSHA256 = try WorkspaceMutationCanonicalV1.sha256(BatchBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, checkpointID: checkpointID, beforeCursor: beforeCursor, changes: changes))
        try validateStructure(limits: limits)
    }

    func validate(limits: ChangeJournalLimitsV1) throws {
        try validateStructure(limits: limits)
        guard try WorkspaceMutationCanonicalV1.data(self).count <= limits.maximumBatchBytes else {
            throw ChangeJournalFailureV1.limitExceeded
        }
    }
    private func validateStructure(limits: ChangeJournalLimitsV1) throws {
        try beforeCursor.validate(); try afterCursor.validate()
        guard schemaVersion == Self.schemaVersion, workspaceID.rawValue != ChangeJournalValidationV1.zero, sourceReplicaID.rawValue != ChangeJournalValidationV1.zero, ChangeJournalValidationV1.isSHA256(checkpointID), ChangeJournalValidationV1.isSHA256(batchSHA256), changes.count <= limits.maximumChangesPerBatch,
              beforeCursor.workspaceID == workspaceID, afterCursor.workspaceID == workspaceID, beforeCursor.consumerReplicaID == afterCursor.consumerReplicaID,
              beforeCursor.checkpointID == checkpointID, afterCursor.checkpointID == checkpointID, beforeCursor.frontierSHA256 == afterCursor.frontierSHA256,
              beforeCursor.nextOrdinal <= UInt64.max - UInt64(changes.count), afterCursor.nextOrdinal == beforeCursor.nextOrdinal + UInt64(changes.count),
              changes.map { $0.receipt.identity.localSequence } == changes.map { $0.receipt.identity.localSequence }.sorted(), Set(changes.map { $0.receipt.identity }).count == changes.count, Set(changes.map { $0.envelope.mutationID }).count == changes.count,
              changes.allSatisfy({ $0.envelope.workspaceID == workspaceID && $0.envelope.replicaID == sourceReplicaID }),
              batchSHA256 == (try WorkspaceMutationCanonicalV1.sha256(BatchBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, checkpointID: checkpointID, beforeCursor: beforeCursor, changes: changes))),
              (changes.isEmpty ? afterCursor.previousBatchSHA256 == beforeCursor.previousBatchSHA256 : afterCursor.previousBatchSHA256 == batchSHA256) else { throw ChangeJournalFailureV1.tamperedBatch }
    }
    func canonicalData(limits: ChangeJournalLimitsV1) throws -> Data { try validateStructure(limits: limits); return try WorkspaceMutationCanonicalV1.data(self) }
    private struct BatchBasis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let sourceReplicaID: ReplicaID; let checkpointID: String; let beforeCursor: ChangeCursorV1; let changes: [JournalChangeV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, sourceReplicaID, checkpointID, beforeCursor, afterCursor, changes, batchSHA256 }
    init(from decoder: any Decoder) throws {
        try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }
        let before = try c.decode(ChangeCursorV1.self, forKey: .beforeCursor), changes = try c.decode([JournalChangeV1].self, forKey: .changes)
        let rebuilt = try Self(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), sourceReplicaID: c.decode(ReplicaID.self, forKey: .sourceReplicaID), checkpointID: c.decode(String.self, forKey: .checkpointID), beforeCursor: before, changes: changes, limits: ChangeJournalLimitsV1())
        guard try c.decode(ChangeCursorV1.self, forKey: .afterCursor) == rebuilt.afterCursor, try c.decode(String.self, forKey: .batchSHA256) == rebuilt.batchSHA256 else { throw ChangeJournalFailureV1.tamperedBatch }; self = rebuilt
        try validate(limits: ChangeJournalLimitsV1())
    }
}

enum ChangeReplayDispositionV1: String, CaseIterable, Codable, Sendable {
    case applied = "APPLIED"
    case alreadyApplied = "ALREADY_APPLIED"
    case deferredGap = "DEFERRED_GAP"
    case deferredContent = "DEFERRED_CONTENT"
    case unresolvedConflict = "UNRESOLVED_CONFLICT"
    case deleteWon = "DELETE_WON"
    case derivedRebuild = "DERIVED_REBUILD"
    case localOnlyExcluded = "LOCAL_ONLY_EXCLUDED"
    case rejected = "REJECTED"
}

struct MutationReplayDispositionV1: Codable, Equatable, Sendable {
    let mutationID: MutationIDV1
    let disposition: ChangeReplayDispositionV1
    let missingContentIDs: [String]
    let conflictIdentity: ConflictIdentityV1?
    let reasonCode: String?

    init(mutationID: MutationIDV1, disposition: ChangeReplayDispositionV1, missingContentIDs: [String] = [], conflictIdentity: ConflictIdentityV1? = nil, reasonCode: String? = nil) throws {
        guard missingContentIDs == missingContentIDs.sorted(), Set(missingContentIDs).count == missingContentIDs.count, missingContentIDs.allSatisfy(ChangeJournalValidationV1.validToken),
              (disposition == .deferredContent) == !missingContentIDs.isEmpty,
              (disposition == .unresolvedConflict) == (conflictIdentity != nil),
              reasonCode.map(ChangeJournalValidationV1.validToken) ?? true else { throw ChangeJournalFailureV1.invalidValue }
        self.mutationID = mutationID; self.disposition = disposition; self.missingContentIDs = missingContentIDs; self.conflictIdentity = conflictIdentity; self.reasonCode = reasonCode
    }
    var stableKey: String { mutationID.rawValue.uuidString.lowercased() }
    private enum CodingKeys: String, CodingKey, CaseIterable { case mutationID, disposition, missingContentIDs, conflictIdentity, reasonCode }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireClosed(decoder, CodingKeys.self, required: [.mutationID, .disposition, .missingContentIDs]); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), disposition: c.decode(ChangeReplayDispositionV1.self, forKey: .disposition), missingContentIDs: c.decode([String].self, forKey: .missingContentIDs), conflictIdentity: c.decodeIfPresent(ConflictIdentityV1.self, forKey: .conflictIdentity), reasonCode: c.decodeIfPresent(String.self, forKey: .reasonCode)) }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(mutationID, forKey: .mutationID)
        try c.encode(disposition, forKey: .disposition); try c.encode(missingContentIDs, forKey: .missingContentIDs)
        try c.encode(conflictIdentity, forKey: .conflictIdentity); try c.encode(reasonCode, forKey: .reasonCode)
    }
}

struct ChangeReplayReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let destinationReplicaID: ReplicaID
    let destinationGenerationID: UUID
    let batchSHA256: String
    let resultingFrontier: ChangeJournalFrontierV1
    let dispositions: [MutationReplayDispositionV1]
    let semanticProjectionSHA256: String
    let receiptSHA256: String

    init(workspaceID: WorkspaceID, destinationReplicaID: ReplicaID, destinationGenerationID: UUID, batchSHA256: String, resultingFrontier: ChangeJournalFrontierV1, dispositions: [MutationReplayDispositionV1], semanticProjectionSHA256: String, limits: ChangeJournalLimitsV1) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.destinationReplicaID = destinationReplicaID; self.destinationGenerationID = destinationGenerationID; self.batchSHA256 = batchSHA256; self.resultingFrontier = resultingFrontier; self.dispositions = dispositions; self.semanticProjectionSHA256 = semanticProjectionSHA256
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, destinationReplicaID: destinationReplicaID, destinationGenerationID: destinationGenerationID, batchSHA256: batchSHA256, resultingFrontier: resultingFrontier, dispositions: dispositions, semanticProjectionSHA256: semanticProjectionSHA256))
        try validate(limits: limits)
    }
    func validate(limits: ChangeJournalLimitsV1) throws { try resultingFrontier.validate(limits: limits); guard schemaVersion == Self.schemaVersion, (try? WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: destinationReplicaID)) != nil, destinationGenerationID != ChangeJournalValidationV1.zero, [batchSHA256, semanticProjectionSHA256, receiptSHA256].allSatisfy(ChangeJournalValidationV1.isSHA256), dispositions.count <= limits.maximumChangesPerBatch, dispositions.map(\.stableKey) == dispositions.map(\.stableKey).sorted(), Set(dispositions.map(\.mutationID)).count == dispositions.count, receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: schemaVersion, workspaceID: workspaceID, destinationReplicaID: destinationReplicaID, destinationGenerationID: destinationGenerationID, batchSHA256: batchSHA256, resultingFrontier: resultingFrontier, dispositions: dispositions, semanticProjectionSHA256: semanticProjectionSHA256))) else { throw ChangeJournalFailureV1.invalidDigest } }
    private struct DigestBasis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let destinationReplicaID: ReplicaID; let destinationGenerationID: UUID; let batchSHA256: String; let resultingFrontier: ChangeJournalFrontierV1; let dispositions: [MutationReplayDispositionV1]; let semanticProjectionSHA256: String }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, destinationReplicaID, destinationGenerationID, batchSHA256, resultingFrontier, dispositions, semanticProjectionSHA256, receiptSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; let rebuilt = try Self(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), destinationReplicaID: c.decode(ReplicaID.self, forKey: .destinationReplicaID), destinationGenerationID: c.decode(UUID.self, forKey: .destinationGenerationID), batchSHA256: c.decode(String.self, forKey: .batchSHA256), resultingFrontier: c.decode(ChangeJournalFrontierV1.self, forKey: .resultingFrontier), dispositions: c.decode([MutationReplayDispositionV1].self, forKey: .dispositions), semanticProjectionSHA256: c.decode(String.self, forKey: .semanticProjectionSHA256), limits: ChangeJournalLimitsV1()); guard try c.decode(String.self, forKey: .receiptSHA256) == rebuilt.receiptSHA256 else { throw ChangeJournalFailureV1.invalidDigest }; self = rebuilt }
}

struct CheckpointActivationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let destinationReplicaID: ReplicaID
    let destinationGenerationID: UUID
    let checkpointID: String
    let manifestSHA256: String
    let activatedFrontier: ChangeJournalFrontierV1
    let semanticProjectionSHA256: String
    let contentDispositionSHA256: String
    let receiptSHA256: String

    init(workspaceID: WorkspaceID, destinationReplicaID: ReplicaID, destinationGenerationID: UUID, manifest: WorkspaceSnapshotManifestV1, activatedFrontier: ChangeJournalFrontierV1, semanticProjectionSHA256: String, contentDispositionSHA256: String, limits: ChangeJournalLimitsV1) throws {
        guard manifest.workspaceID == workspaceID else { throw ChangeJournalFailureV1.wrongWorkspace }
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.destinationReplicaID = destinationReplicaID; self.destinationGenerationID = destinationGenerationID; checkpointID = manifest.checkpointID; manifestSHA256 = manifest.manifestSHA256; self.activatedFrontier = activatedFrontier; self.semanticProjectionSHA256 = semanticProjectionSHA256; self.contentDispositionSHA256 = contentDispositionSHA256
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, destinationReplicaID: destinationReplicaID, destinationGenerationID: destinationGenerationID, checkpointID: checkpointID, manifestSHA256: manifestSHA256, activatedFrontier: activatedFrontier, semanticProjectionSHA256: semanticProjectionSHA256, contentDispositionSHA256: contentDispositionSHA256))
        try validate(limits: limits)
    }
    func validate(limits: ChangeJournalLimitsV1) throws { try activatedFrontier.validate(limits: limits); guard schemaVersion == Self.schemaVersion, (try? WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: destinationReplicaID)) != nil, destinationGenerationID != ChangeJournalValidationV1.zero, [checkpointID, manifestSHA256, semanticProjectionSHA256, contentDispositionSHA256, receiptSHA256].allSatisfy(ChangeJournalValidationV1.isSHA256), receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: schemaVersion, workspaceID: workspaceID, destinationReplicaID: destinationReplicaID, destinationGenerationID: destinationGenerationID, checkpointID: checkpointID, manifestSHA256: manifestSHA256, activatedFrontier: activatedFrontier, semanticProjectionSHA256: semanticProjectionSHA256, contentDispositionSHA256: contentDispositionSHA256))) else { throw ChangeJournalFailureV1.invalidDigest } }
    private struct DigestBasis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let destinationReplicaID: ReplicaID; let destinationGenerationID: UUID; let checkpointID: String; let manifestSHA256: String; let activatedFrontier: ChangeJournalFrontierV1; let semanticProjectionSHA256: String; let contentDispositionSHA256: String }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, destinationReplicaID, destinationGenerationID, checkpointID, manifestSHA256, activatedFrontier, semanticProjectionSHA256, contentDispositionSHA256, receiptSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; let workspaceID = try c.decode(WorkspaceID.self, forKey: .workspaceID), replica = try c.decode(ReplicaID.self, forKey: .destinationReplicaID), generation = try c.decode(UUID.self, forKey: .destinationGenerationID), checkpointID = try c.decode(String.self, forKey: .checkpointID), manifestSHA = try c.decode(String.self, forKey: .manifestSHA256), frontier = try c.decode(ChangeJournalFrontierV1.self, forKey: .activatedFrontier), semantic = try c.decode(String.self, forKey: .semanticProjectionSHA256), content = try c.decode(String.self, forKey: .contentDispositionSHA256); guard [checkpointID, manifestSHA, semantic, content].allSatisfy(ChangeJournalValidationV1.isSHA256) else { throw ChangeJournalFailureV1.invalidDigest }; self.schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; destinationReplicaID = replica; destinationGenerationID = generation; self.checkpointID = checkpointID; manifestSHA256 = manifestSHA; activatedFrontier = frontier; semanticProjectionSHA256 = semantic; contentDispositionSHA256 = content; receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, destinationReplicaID: replica, destinationGenerationID: generation, checkpointID: checkpointID, manifestSHA256: manifestSHA, activatedFrontier: frontier, semanticProjectionSHA256: semantic, contentDispositionSHA256: content)); guard try c.decode(String.self, forKey: .receiptSHA256) == receiptSHA256 else { throw ChangeJournalFailureV1.invalidDigest }; try validate(limits: ChangeJournalLimitsV1()) }
}

struct ChangeJournalCompactionReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let sourceReplicaID: ReplicaID
    let checkpointID: String
    let checkpointManifestSHA256: String
    let compactedThrough: ChangeJournalFrontierV1
    let preservedReceiptSetSHA256: String
    let preservedReversalBasisSetSHA256: String
    let removedChangeCount: Int
    let canonicalHistoryDeleted: Bool
    let receiptSHA256: String

    init(workspaceID: WorkspaceID, sourceReplicaID: ReplicaID, manifest: WorkspaceSnapshotManifestV1, compactedThrough: ChangeJournalFrontierV1, preservedReceiptSetSHA256: String, preservedReversalBasisSetSHA256: String, removedChangeCount: Int, limits: ChangeJournalLimitsV1) throws {
        guard manifest.workspaceID == workspaceID, manifest.frontier == compactedThrough else { throw ChangeJournalFailureV1.incompleteCheckpoint }
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.sourceReplicaID = sourceReplicaID; checkpointID = manifest.checkpointID; checkpointManifestSHA256 = manifest.manifestSHA256; self.compactedThrough = compactedThrough; self.preservedReceiptSetSHA256 = preservedReceiptSetSHA256; self.preservedReversalBasisSetSHA256 = preservedReversalBasisSetSHA256; self.removedChangeCount = removedChangeCount; canonicalHistoryDeleted = false
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, checkpointID: checkpointID, checkpointManifestSHA256: checkpointManifestSHA256, compactedThrough: compactedThrough, preservedReceiptSetSHA256: preservedReceiptSetSHA256, preservedReversalBasisSetSHA256: preservedReversalBasisSetSHA256, removedChangeCount: removedChangeCount, canonicalHistoryDeleted: false))
        try validate(limits: limits)
    }
    func validate(limits: ChangeJournalLimitsV1) throws { try compactedThrough.validate(limits: limits); guard schemaVersion == Self.schemaVersion, (try? WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: sourceReplicaID)) != nil, removedChangeCount >= 0, canonicalHistoryDeleted == false, [checkpointID, checkpointManifestSHA256, preservedReceiptSetSHA256, preservedReversalBasisSetSHA256, receiptSHA256].allSatisfy(ChangeJournalValidationV1.isSHA256), receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: schemaVersion, workspaceID: workspaceID, sourceReplicaID: sourceReplicaID, checkpointID: checkpointID, checkpointManifestSHA256: checkpointManifestSHA256, compactedThrough: compactedThrough, preservedReceiptSetSHA256: preservedReceiptSetSHA256, preservedReversalBasisSetSHA256: preservedReversalBasisSetSHA256, removedChangeCount: removedChangeCount, canonicalHistoryDeleted: canonicalHistoryDeleted))) else { throw ChangeJournalFailureV1.invalidDigest } }
    private struct DigestBasis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let sourceReplicaID: ReplicaID; let checkpointID: String; let checkpointManifestSHA256: String; let compactedThrough: ChangeJournalFrontierV1; let preservedReceiptSetSHA256: String; let preservedReversalBasisSetSHA256: String; let removedChangeCount: Int; let canonicalHistoryDeleted: Bool }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, sourceReplicaID, checkpointID, checkpointManifestSHA256, compactedThrough, preservedReceiptSetSHA256, preservedReversalBasisSetSHA256, removedChangeCount, canonicalHistoryDeleted, receiptSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(Bool.self, forKey: .canonicalHistoryDeleted) == false else { throw ChangeJournalFailureV1.incompatibleVersion }; let workspace = try c.decode(WorkspaceID.self, forKey: .workspaceID), replica = try c.decode(ReplicaID.self, forKey: .sourceReplicaID), checkpoint = try c.decode(String.self, forKey: .checkpointID), manifest = try c.decode(String.self, forKey: .checkpointManifestSHA256), frontier = try c.decode(ChangeJournalFrontierV1.self, forKey: .compactedThrough), receipts = try c.decode(String.self, forKey: .preservedReceiptSetSHA256), reversals = try c.decode(String.self, forKey: .preservedReversalBasisSetSHA256), count = try c.decode(Int.self, forKey: .removedChangeCount); schemaVersion = Self.schemaVersion; workspaceID = workspace; sourceReplicaID = replica; checkpointID = checkpoint; checkpointManifestSHA256 = manifest; compactedThrough = frontier; preservedReceiptSetSHA256 = receipts; preservedReversalBasisSetSHA256 = reversals; removedChangeCount = count; canonicalHistoryDeleted = false; receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspace, sourceReplicaID: replica, checkpointID: checkpoint, checkpointManifestSHA256: manifest, compactedThrough: frontier, preservedReceiptSetSHA256: receipts, preservedReversalBasisSetSHA256: reversals, removedChangeCount: count, canonicalHistoryDeleted: false)); guard try c.decode(String.self, forKey: .receiptSHA256) == receiptSHA256 else { throw ChangeJournalFailureV1.invalidDigest }; try validate(limits: ChangeJournalLimitsV1()) }
}

struct SemanticConvergenceProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let canonicalSnapshotSHA256: String
    let tombstoneIdentities: [WorkspaceEntityIdentityV1]
    let unresolvedConflictIdentities: [ConflictIdentityV1]
    let contentDispositionSHA256: String
    let observedMutationIDs: [MutationIDV1]
    let semanticSHA256: String

    init(workspaceID: WorkspaceID, canonicalSnapshotSHA256: String, tombstoneIdentities: [WorkspaceEntityIdentityV1], unresolvedConflictIdentities: [ConflictIdentityV1], contentDispositionSHA256: String, observedMutationIDs: [MutationIDV1], limits: ChangeJournalLimitsV1) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.canonicalSnapshotSHA256 = canonicalSnapshotSHA256; self.tombstoneIdentities = tombstoneIdentities; self.unresolvedConflictIdentities = unresolvedConflictIdentities; self.contentDispositionSHA256 = contentDispositionSHA256; self.observedMutationIDs = observedMutationIDs
        semanticSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, canonicalSnapshotSHA256: canonicalSnapshotSHA256, tombstoneIdentities: tombstoneIdentities, unresolvedConflictIdentities: unresolvedConflictIdentities, contentDispositionSHA256: contentDispositionSHA256, observedMutationIDs: observedMutationIDs))
        try validate(limits: limits)
    }
    func validate(limits: ChangeJournalLimitsV1) throws { guard schemaVersion == Self.schemaVersion, workspaceID.rawValue != ChangeJournalValidationV1.zero, [canonicalSnapshotSHA256, contentDispositionSHA256, semanticSHA256].allSatisfy(ChangeJournalValidationV1.isSHA256), tombstoneIdentities.count <= limits.maximumEntitiesPerCheckpoint, tombstoneIdentities.map(\.stableKey) == tombstoneIdentities.map(\.stableKey).sorted(), Set(tombstoneIdentities).count == tombstoneIdentities.count, unresolvedConflictIdentities.count <= limits.maximumConflicts, unresolvedConflictIdentities.map(\.digestSHA256) == unresolvedConflictIdentities.map(\.digestSHA256).sorted(), Set(unresolvedConflictIdentities.map(\.digestSHA256)).count == unresolvedConflictIdentities.count, observedMutationIDs.map { $0.rawValue.uuidString.lowercased() } == observedMutationIDs.map { $0.rawValue.uuidString.lowercased() }.sorted(), Set(observedMutationIDs).count == observedMutationIDs.count, semanticSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: schemaVersion, workspaceID: workspaceID, canonicalSnapshotSHA256: canonicalSnapshotSHA256, tombstoneIdentities: tombstoneIdentities, unresolvedConflictIdentities: unresolvedConflictIdentities, contentDispositionSHA256: contentDispositionSHA256, observedMutationIDs: observedMutationIDs))) else { throw ChangeJournalFailureV1.invalidDigest } }
    private struct DigestBasis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let canonicalSnapshotSHA256: String; let tombstoneIdentities: [WorkspaceEntityIdentityV1]; let unresolvedConflictIdentities: [ConflictIdentityV1]; let contentDispositionSHA256: String; let observedMutationIDs: [MutationIDV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, canonicalSnapshotSHA256, tombstoneIdentities, unresolvedConflictIdentities, contentDispositionSHA256, observedMutationIDs, semanticSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; let rebuilt = try Self(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), canonicalSnapshotSHA256: c.decode(String.self, forKey: .canonicalSnapshotSHA256), tombstoneIdentities: c.decode([WorkspaceEntityIdentityV1].self, forKey: .tombstoneIdentities), unresolvedConflictIdentities: c.decode([ConflictIdentityV1].self, forKey: .unresolvedConflictIdentities), contentDispositionSHA256: c.decode(String.self, forKey: .contentDispositionSHA256), observedMutationIDs: c.decode([MutationIDV1].self, forKey: .observedMutationIDs), limits: ChangeJournalLimitsV1()); guard try c.decode(String.self, forKey: .semanticSHA256) == rebuilt.semanticSHA256 else { throw ChangeJournalFailureV1.invalidDigest }; self = rebuilt }
}

struct CheckpointArchiveEntryDigestV1: Codable, Equatable, Sendable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
    var stableKey: String { relativePath }
    init(relativePath: String, byteCount: Int64, sha256: String) throws {
        guard ChangeJournalValidationV1.validRelativePath(relativePath), byteCount >= 0, ChangeJournalValidationV1.isSHA256(sha256) else { throw ChangeJournalFailureV1.invalidValue }
        self.relativePath = relativePath; self.byteCount = byteCount; self.sha256 = sha256
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case relativePath, byteCount, sha256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(relativePath: c.decode(String.self, forKey: .relativePath), byteCount: c.decode(Int64.self, forKey: .byteCount), sha256: c.decode(String.self, forKey: .sha256)) }
}

struct WorkspaceCheckpointPreparationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let preparationID: UUID
    let manifest: WorkspaceSnapshotManifestV1
    let entries: [CheckpointArchiveEntryDigestV1]
    let preparationSHA256: String

    init(preparationID: UUID, manifest: WorkspaceSnapshotManifestV1, entries: [CheckpointArchiveEntryDigestV1], limits: ChangeJournalLimitsV1) throws {
        schemaVersion = Self.schemaVersion; self.preparationID = preparationID; self.manifest = manifest; self.entries = entries
        preparationSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, preparationID: preparationID, manifest: manifest, entries: entries))
        try validate(limits: limits)
    }
    func validate(limits: ChangeJournalLimitsV1) throws { try manifest.validate(limits: limits); guard schemaVersion == Self.schemaVersion, preparationID != ChangeJournalValidationV1.zero, entries.count <= limits.maximumContentEntriesPerCheckpoint + 4, entries.map(\.stableKey) == entries.map(\.stableKey).sorted(), Set(entries.map(\.relativePath)).count == entries.count, ChangeJournalValidationV1.isSHA256(preparationSHA256), preparationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: schemaVersion, preparationID: preparationID, manifest: manifest, entries: entries))) else { throw ChangeJournalFailureV1.invalidDigest } }
    private struct DigestBasis: Codable { let schemaVersion: Int; let preparationID: UUID; let manifest: WorkspaceSnapshotManifestV1; let entries: [CheckpointArchiveEntryDigestV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, preparationID, manifest, entries, preparationSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; let rebuilt = try Self(preparationID: c.decode(UUID.self, forKey: .preparationID), manifest: c.decode(WorkspaceSnapshotManifestV1.self, forKey: .manifest), entries: c.decode([CheckpointArchiveEntryDigestV1].self, forKey: .entries), limits: ChangeJournalLimitsV1()); guard try c.decode(String.self, forKey: .preparationSHA256) == rebuilt.preparationSHA256 else { throw ChangeJournalFailureV1.invalidDigest }; self = rebuilt }
}

struct WorkspaceCheckpointExportV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let preparationID: UUID
    let workspaceID: WorkspaceID
    let checkpointID: String
    let packageRelativePath: String
    let packageByteCount: Int64
    let packageSHA256: String
    let manifestSHA256: String
    let exportSHA256: String

    init(preparation: WorkspaceCheckpointPreparationV1, packageRelativePath: String, packageByteCount: Int64, packageSHA256: String, limits: ChangeJournalLimitsV1) throws {
        try preparation.validate(limits: limits)
        schemaVersion = Self.schemaVersion; preparationID = preparation.preparationID; workspaceID = preparation.manifest.workspaceID; checkpointID = preparation.manifest.checkpointID; self.packageRelativePath = packageRelativePath; self.packageByteCount = packageByteCount; self.packageSHA256 = packageSHA256; manifestSHA256 = preparation.manifest.manifestSHA256
        exportSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, preparationID: preparationID, workspaceID: workspaceID, checkpointID: checkpointID, packageRelativePath: packageRelativePath, packageByteCount: packageByteCount, packageSHA256: packageSHA256, manifestSHA256: manifestSHA256))
        try validate()
    }
    func validate() throws { guard schemaVersion == Self.schemaVersion, preparationID != ChangeJournalValidationV1.zero, workspaceID.rawValue != ChangeJournalValidationV1.zero, ChangeJournalValidationV1.validRelativePath(packageRelativePath), packageByteCount > 0, [checkpointID, packageSHA256, manifestSHA256, exportSHA256].allSatisfy(ChangeJournalValidationV1.isSHA256), exportSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: schemaVersion, preparationID: preparationID, workspaceID: workspaceID, checkpointID: checkpointID, packageRelativePath: packageRelativePath, packageByteCount: packageByteCount, packageSHA256: packageSHA256, manifestSHA256: manifestSHA256))) else { throw ChangeJournalFailureV1.invalidDigest } }
    private struct DigestBasis: Codable { let schemaVersion: Int; let preparationID: UUID; let workspaceID: WorkspaceID; let checkpointID: String; let packageRelativePath: String; let packageByteCount: Int64; let packageSHA256: String; let manifestSHA256: String }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, preparationID, workspaceID, checkpointID, packageRelativePath, packageByteCount, packageSHA256, manifestSHA256, exportSHA256 }
    init(from decoder: any Decoder) throws { try ChangeJournalClosedCodingV1.requireExact(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ChangeJournalFailureV1.incompatibleVersion }; let preparationID = try c.decode(UUID.self, forKey: .preparationID), workspaceID = try c.decode(WorkspaceID.self, forKey: .workspaceID), checkpointID = try c.decode(String.self, forKey: .checkpointID), path = try c.decode(String.self, forKey: .packageRelativePath), count = try c.decode(Int64.self, forKey: .packageByteCount), packageSHA = try c.decode(String.self, forKey: .packageSHA256), manifestSHA = try c.decode(String.self, forKey: .manifestSHA256); schemaVersion = Self.schemaVersion; self.preparationID = preparationID; self.workspaceID = workspaceID; self.checkpointID = checkpointID; packageRelativePath = path; packageByteCount = count; packageSHA256 = packageSHA; manifestSHA256 = manifestSHA; exportSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, preparationID: preparationID, workspaceID: workspaceID, checkpointID: checkpointID, packageRelativePath: path, packageByteCount: count, packageSHA256: packageSHA, manifestSHA256: manifestSHA)); guard try c.decode(String.self, forKey: .exportSHA256) == exportSHA256 else { throw ChangeJournalFailureV1.invalidDigest }; try validate() }
}

private enum ChangeJournalValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func isSHA256(_ value: String) -> Bool { MutationEnvelopeV1.isSHA256(value) }
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func validToken(_ value: String) -> Bool { MutationEnvelopeV1.validBoundedToken(value) && !value.contains("/") && !value.contains("\\") }
    static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 1_024, !value.hasPrefix("/"), !value.hasPrefix("\\"), !value.contains("\\"), !value.contains(":"), value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

private enum ChangeJournalClosedCodingV1 {
    static func requireExact<Key: CodingKey & CaseIterable>(_ decoder: any Decoder, _ type: Key.Type) throws where Key.AllCases: Collection {
        try KernelClosedCodingV1.require(decoder, keys: Array(Key.allCases).map(\.stringValue))
    }
    static func requireClosed<Key: CodingKey & CaseIterable>(_ decoder: any Decoder, _ type: Key.Type, required: [Key]) throws where Key.AllCases: Collection {
        try KernelClosedCodingV1.require(
            decoder,
            keys: Array(Key.allCases).map(\.stringValue),
            required: required.map(\.stringValue)
        )
    }
}

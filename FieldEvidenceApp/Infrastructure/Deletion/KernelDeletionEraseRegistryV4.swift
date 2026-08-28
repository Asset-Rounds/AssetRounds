import Foundation

enum KernelDeleteDispositionV4: String, Codable, Sendable {
    case explicitOnly = "EXPLICIT_ONLY"
    case deleteAfterDependents = "DELETE_AFTER_DEPENDENTS"
    case deleteWithOwner = "DELETE_WITH_OWNER"
    case tombstonePreservingHistory = "TOMBSTONE_PRESERVING_HISTORY"
    case preserveUntilErase = "PRESERVE_UNTIL_ERASE"
}

enum KernelOrphanCleanupDispositionV4: String, Codable, Sendable {
    case removeOwnedBytesWhenUnreferenced = "REMOVE_OWNED_BYTES_WHEN_UNREFERENCED"
    case removeDerivedProjection = "REMOVE_DERIVED_PROJECTION"
    case preserveCanonicalRecord = "PRESERVE_CANONICAL_RECORD"
}

enum KernelEraseDispositionV4: String, Codable, Sendable {
    case clearCanonicalAndHistory = "CLEAR_CANONICAL_AND_HISTORY"
    case clearLocalOperationalState = "CLEAR_LOCAL_OPERATIONAL_STATE"
    case clearRecoveryState = "CLEAR_RECOVERY_STATE"
    case rebuildEmptyProjection = "REBUILD_EMPTY_PROJECTION"
}

enum KernelRemovalActionV4: String, Codable, Sendable {
    case delete = "DELETE"
    case orphanCleanup = "ORPHAN_CLEANUP"
    case erase = "ERASE"
}

struct KernelDeletionEraseRegistrationV4: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, deleteRule, deletion, orphanCleanup, erase
        case clearsTombstonesOnDelete, clearsTombstonesOnErase
    }

    let kind: KernelPersistenceV4RecordKind
    let deleteRule: KernelPersistenceV4DeleteRule
    let deletion: KernelDeleteDispositionV4
    let orphanCleanup: KernelOrphanCleanupDispositionV4
    let erase: KernelEraseDispositionV4
    let clearsTombstonesOnDelete: Bool
    let clearsTombstonesOnErase: Bool

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind < rhs.kind }

    init(
        kind: KernelPersistenceV4RecordKind,
        deleteRule: KernelPersistenceV4DeleteRule,
        deletion: KernelDeleteDispositionV4,
        orphanCleanup: KernelOrphanCleanupDispositionV4,
        erase: KernelEraseDispositionV4,
        clearsTombstonesOnDelete: Bool,
        clearsTombstonesOnErase: Bool
    ) throws {
        self.kind = kind
        self.deleteRule = deleteRule
        self.deletion = deletion
        self.orphanCleanup = orphanCleanup
        self.erase = erase
        self.clearsTombstonesOnDelete = clearsTombstonesOnDelete
        self.clearsTombstonesOnErase = clearsTombstonesOnErase
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind),
            deleteRule: values.decode(KernelPersistenceV4DeleteRule.self, forKey: .deleteRule),
            deletion: values.decode(KernelDeleteDispositionV4.self, forKey: .deletion),
            orphanCleanup: values.decode(KernelOrphanCleanupDispositionV4.self, forKey: .orphanCleanup),
            erase: values.decode(KernelEraseDispositionV4.self, forKey: .erase),
            clearsTombstonesOnDelete: values.decode(Bool.self, forKey: .clearsTombstonesOnDelete),
            clearsTombstonesOnErase: values.decode(Bool.self, forKey: .clearsTombstonesOnErase)
        )
    }

    func validate() throws {
        let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
        let expectedDeletion = KernelDeletionEraseRegistryV4.deleteDisposition(descriptor.deleteRule)
        let expectedErase = KernelDeletionEraseRegistryV4.eraseDisposition(descriptor.classification)
        let expectedOrphan = KernelDeletionEraseRegistryV4.orphanDisposition(kind, descriptor.classification)
        let hasTombstone = [.tombstoneWhenCounted, .appendEraseOnly].contains(descriptor.deleteRule)
        guard deleteRule == descriptor.deleteRule,
              deletion == expectedDeletion,
              orphanCleanup == expectedOrphan,
              erase == expectedErase,
              !clearsTombstonesOnDelete,
              clearsTombstonesOnErase == hasTombstone else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

struct KernelRemovalReceiptV4: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaID, schemaVersion, operationID, kind, targetID, action
        case priorRevision, resultingRevision, clearedTombstone, effectSHA256
    }

    let schemaID: String
    let schemaVersion: Int
    let operationID: String
    let kind: KernelPersistenceV4RecordKind
    let targetID: String
    let action: KernelRemovalActionV4
    let priorRevision: UInt64
    let resultingRevision: UInt64
    let clearedTombstone: Bool
    let effectSHA256: String

    init(
        operationID: String,
        kind: KernelPersistenceV4RecordKind,
        targetID: String,
        action: KernelRemovalActionV4,
        priorRevision: UInt64,
        resultingRevision: UInt64,
        clearedTombstone: Bool,
        effectSHA256: String? = nil
    ) throws {
        schemaID = KernelPersistenceV4Validation.schemaID
        schemaVersion = KernelPersistenceV4Validation.schemaVersion
        self.operationID = operationID
        self.kind = kind
        self.targetID = targetID
        self.action = action
        self.priorRevision = priorRevision
        self.resultingRevision = resultingRevision
        self.clearedTombstone = clearedTombstone
        self.effectSHA256 = try effectSHA256 ?? Self.digest(
            operationID: operationID, kind: kind, targetID: targetID, action: action,
            priorRevision: priorRevision, resultingRevision: resultingRevision,
            clearedTombstone: clearedTombstone
        )
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(String.self, forKey: .schemaID) == KernelPersistenceV4Validation.schemaID,
              try values.decode(Int.self, forKey: .schemaVersion) == KernelPersistenceV4Validation.schemaVersion else {
            throw KernelPersistenceV4Failure.futureVersion
        }
        try self.init(
            operationID: values.decode(String.self, forKey: .operationID),
            kind: values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind),
            targetID: values.decode(String.self, forKey: .targetID),
            action: values.decode(KernelRemovalActionV4.self, forKey: .action),
            priorRevision: values.decode(UInt64.self, forKey: .priorRevision),
            resultingRevision: values.decode(UInt64.self, forKey: .resultingRevision),
            clearedTombstone: values.decode(Bool.self, forKey: .clearedTombstone),
            effectSHA256: values.decode(String.self, forKey: .effectSHA256)
        )
    }

    func validate() throws {
        let registration = try KernelDeletionEraseRegistryV4.registration(for: kind)
        let validAction: Bool
        switch action {
        case .delete:
            validAction = registration.deletion != .preserveUntilErase && !clearedTombstone
        case .orphanCleanup:
            validAction = registration.orphanCleanup != .preserveCanonicalRecord && !clearedTombstone
        case .erase:
            validAction = clearedTombstone == registration.clearsTombstonesOnErase
        }
        guard schemaID == KernelPersistenceV4Validation.schemaID,
              schemaVersion == KernelPersistenceV4Validation.schemaVersion,
              KernelPersistenceV4Validation.validID(operationID),
              KernelPersistenceV4Validation.validID(targetID),
              priorRevision < UInt64.max,
              resultingRevision == priorRevision + 1,
              validAction,
              effectSHA256 == (try Self.digest(
                operationID: operationID, kind: kind, targetID: targetID, action: action,
                priorRevision: priorRevision, resultingRevision: resultingRevision,
                clearedTombstone: clearedTombstone
              )) else {
            throw KernelPersistenceV4Failure.invalidTransition
        }
    }

    private struct DigestMaterial: Encodable {
        let schemaID: String
        let schemaVersion: Int
        let operationID: String
        let kind: KernelPersistenceV4RecordKind
        let targetID: String
        let action: KernelRemovalActionV4
        let priorRevision: UInt64
        let resultingRevision: UInt64
        let clearedTombstone: Bool
    }

    private static func digest(
        operationID: String,
        kind: KernelPersistenceV4RecordKind,
        targetID: String,
        action: KernelRemovalActionV4,
        priorRevision: UInt64,
        resultingRevision: UInt64,
        clearedTombstone: Bool
    ) throws -> String {
        try KernelPersistenceV4Validation.canonicalDigest(DigestMaterial(
            schemaID: KernelPersistenceV4Validation.schemaID,
            schemaVersion: KernelPersistenceV4Validation.schemaVersion,
            operationID: operationID, kind: kind, targetID: targetID, action: action,
            priorRevision: priorRevision, resultingRevision: resultingRevision,
            clearedTombstone: clearedTombstone
        ))
    }
}

enum KernelDeletionEraseRegistryV4 {
    enum IntegrationProjectionDispositionV1: String, CaseIterable, Sendable {
        case ordinaryDelete = "DROP_DERIVED_AND_REBUILD"
        case workspaceErase = "DROP_DERIVED_AND_REBUILD_EMPTY"
    }

    static let integrationProjectionLifecycle =
        IntegrationProjectionDispositionV1.allCases

    static func validateIntegrationProjectionLifecycle() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        try coverage.validate()
        guard IntegrationProjectionSchemaV1.persistenceMode == "DERIVED_ONLY",
              IntegrationProjectionSchemaV1.downgradeDisposition == "DROP_AND_REBUILD",
              !IntegrationProjectionSchemaV1.canonicalBackupIncluded,
              !IntegrationProjectionSchemaV1.canonicalExportIncluded,
              !IntegrationProjectionSchemaV1.canonicalReportSource,
              integrationProjectionLifecycle == [.ordinaryDelete, .workspaceErase]
        else { throw KernelPersistenceV4Failure.incompleteCoverage }
    }
    static let functionalRelationshipDeleteKinds =
        V12BackupFunctionalRelationshipRecordV1.Kind.allCases
    static let evidenceAssuranceDeleteKinds = V13BackupEvidenceAssuranceRecordV1.Kind.allCases
    static let inspectionReviewDeleteKinds = V14BackupInspectionReviewRecordV1.Kind.allCases
    static let workPacketDeleteKinds=V15BackupWorkPacketRecordV1.Kind.allCases
    static let fieldDraftDeleteKinds = V16BackupFieldDraftRecordV1.Kind.allCases
    static let packageEvolutionDeleteKinds = V17BackupPackageEvolutionRecordV1.Kind.allCases

    static func validateFunctionalRelationshipLifecycle() throws {
        guard functionalRelationshipDeleteKinds.count == 2,
              functionalRelationshipDeleteKinds.allSatisfy({
                  FunctionalRelationshipDeletionLedgerPolicyV1.disposition(for: $0)
                    == .preserveImmutableHistoryUntilWorkspaceErase
              }) else { throw KernelPersistenceV4Failure.incompleteCoverage }
    }

    static func validateEvidenceAssuranceLifecycle() throws {
        guard evidenceAssuranceDeleteKinds.count == 4 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validateInspectionReviewLifecycle() throws {
        guard inspectionReviewDeleteKinds.count == 5 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try InspectionReviewDeletionLedgerPolicyV1.validate()
    }
    static func validateWorkPacketLifecycle()throws{guard workPacketDeleteKinds.count==5 else{throw KernelPersistenceV4Failure.incompleteCoverage}}
    static func validateFieldDraftLifecycle() throws {
        guard fieldDraftDeleteKinds.count == 6 else { throw KernelPersistenceV4Failure.incompleteCoverage }
        try FieldDraftDeletionLedgerPolicyV1.validate()
    }
    static func validatePackageEvolutionLifecycle() throws {
        guard packageEvolutionDeleteKinds.count == 4 else { throw KernelPersistenceV4Failure.incompleteCoverage }
        try PackageEvolutionDeletionLedgerPolicyV1.validate()
    }
    /// Search V1 has one canonical workspace-owned record and one disposable
    /// local projection. Keeping these routes beside the kernel registry makes
    /// delete/Erase audits distinguish canonical deletion from index rebuild.
    static let savedSmartViewLifecycle = SavedSmartViewLifecycleDispositionV1.allCases
    static let searchIndexLifecycle = SearchIndexLifecycleDispositionV1.allCases

    static func validateSearchLifecycle() throws {
        guard savedSmartViewLifecycle.contains(.deleteWithWorkspace),
              savedSmartViewLifecycle.contains(.erase),
              searchIndexLifecycle.contains(.purgeOnDelete),
              searchIndexLifecycle.contains(.purgeOnErase),
              searchIndexLifecycle.contains(.dropAndRebuildAfterRestore) else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static let registrations: [KernelDeletionEraseRegistrationV4] = {
        do {
            return try KernelPersistenceV4RecordKind.allCases.map { kind in
                let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
                return try KernelDeletionEraseRegistrationV4(
                    kind: kind,
                    deleteRule: descriptor.deleteRule,
                    deletion: deleteDisposition(descriptor.deleteRule),
                    orphanCleanup: orphanDisposition(kind, descriptor.classification),
                    erase: eraseDisposition(descriptor.classification),
                    clearsTombstonesOnDelete: false,
                    clearsTombstonesOnErase: [.tombstoneWhenCounted, .appendEraseOnly]
                        .contains(descriptor.deleteRule)
                )
            }.sorted()
        } catch { preconditionFailure("Invalid KERNEL_PERSISTENCE_V4 deletion registry: \(error)") }
    }()

    static func registration(for kind: KernelPersistenceV4RecordKind) throws -> KernelDeletionEraseRegistrationV4 {
        let matches = registrations.filter { $0.kind == kind }
        guard matches.count == 1, let value = matches.first else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        return value
    }

    static var canonicalDigest: String {
        get throws { try KernelPersistenceV4Validation.canonicalDigest(registrations) }
    }

    static func validate() throws {
        try validatePackageEvolutionLifecycle()
        try validateFunctionalRelationshipLifecycle()
        try validateEvidenceAssuranceLifecycle()
        try validateInspectionReviewLifecycle()
        try validateWorkPacketLifecycle()
        try validateFieldDraftLifecycle()
        try validateSearchLifecycle()
        try validateIntegrationProjectionLifecycle()
        try validate(registrations)
    }

    static func validate(_ candidate: [KernelDeletionEraseRegistrationV4]) throws {
        let schema = try KernelPersistenceV4Schema.descriptor()
        guard schema.runtimePosture == .dormantStatic, !schema.activationEnabled else {
            throw KernelPersistenceV4Failure.partialActivation
        }
        try candidate.forEach { try $0.validate() }
        let kinds = candidate.map(\.kind)
        guard candidate == candidate.sorted(),
              kinds == KernelPersistenceV4RecordKind.allCases.sorted(),
              Set(kinds).count == kinds.count,
              candidate.allSatisfy({ !$0.clearsTombstonesOnDelete }) else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func reconcile(
        candidate: KernelRemovalReceiptV4,
        existing: KernelRemovalReceiptV4?
    ) throws -> KernelRemovalReceiptV4 {
        try candidate.validate()
        guard let existing else { return candidate }
        try existing.validate()
        guard existing == candidate else { throw KernelPersistenceV4Failure.duplicateIdentity }
        return existing
    }

    static func deleteDisposition(_ rule: KernelPersistenceV4DeleteRule) -> KernelDeleteDispositionV4 {
        switch rule {
        case .preserveUnlessExplicit: return .explicitOnly
        case .deleteAfterDependents: return .deleteAfterDependents
        case .deleteWithOwner: return .deleteWithOwner
        case .tombstoneWhenCounted: return .tombstonePreservingHistory
        case .appendEraseOnly, .clearOnErase: return .preserveUntilErase
        }
    }

    static func orphanDisposition(
        _ kind: KernelPersistenceV4RecordKind,
        _ classification: KernelPersistenceV4Classification
    ) -> KernelOrphanCleanupDispositionV4 {
        if [.contentReference, .evidenceFile].contains(kind) {
            return .removeOwnedBytesWhenUnreferenced
        }
        if classification == .dormantContractDeclaration {
            return .removeDerivedProjection
        }
        return .preserveCanonicalRecord
    }

    static func eraseDisposition(
        _ classification: KernelPersistenceV4Classification
    ) -> KernelEraseDispositionV4 {
        switch classification {
        case .canonicalWorkspace, .immutableContentMetadata, .appendOnlyReceipt:
            return .clearCanonicalAndHistory
        case .deviceLocalOperational: return .clearLocalOperationalState
        case .recoveryJournal: return .clearRecoveryState
        case .dormantContractDeclaration: return .rebuildEmptyProjection
        }
    }
}

import Foundation

enum C34SceneNavigationKernelEraseBoundaryV1 {
    static let persistentRowCount = 0
    static let eraseDisposition = "DEVICE_OPERATIONAL_CLEAR_ONLY"

    static func validate() -> Bool {
        C34SceneNavigationDeviceLifecycleBoundaryV1.validate()
            && persistentRowCount == 0
            && eraseDisposition == "DEVICE_OPERATIONAL_CLEAR_ONLY"
    }
}

enum C50IncumbentFileExchangeKernelDeletionEnrollmentV1 {
    static let canonicalRowRegistrationCount = 0
    static let orphanCleanupOwnsTerminalScratch = true
    static let eraseOwnsAppControlledExchangeBytes = true
    static let ordinaryDeletionPreservesCanonicalHistory = true
}

enum SurveySessionKernelDeletionEnrollmentV1{static let persistentRowNames=Set(["SurveySessionRow","FactCaptureRow","ProvisionalSubjectRow","SubjectPromotionReceiptRow","SurveyPublicationSnapshotRow"]);static func validate()throws{guard persistentRowNames.count==5 else{throw KernelPersistenceV4Failure.incompleteCoverage};try SurveySessionEraseAllEnrollmentV1.validate()}}

/// C32 keeps only the reviewed acceptance receipt. Proposals and every
/// rejected, cancelled, or expired proposal corpus remain ephemeral. An
/// ordinary entity deletion preserves the accountability receipt as mutation
/// history; workspace Erase removes its durable row with the rest of the
/// canonical store, and there are no proposal-owned files to orphan-clean.
enum C32AssistanceKernelDeletionEnrollmentV1 {
    static let durableRowNames: Set<String> = ["AssistanceAcceptanceReceiptRow"]
    static let nonpersistentValueNames: Set<String> = ["AssistanceProposalV1"]
    static let ordinaryDeletionPreservesAcceptedHistory = true
    static let workspaceEraseClearsAcceptedHistory = true
    static let proposalsOwnNoFilesystemPayload = true

    static func validate() throws {
        guard durableRowNames == AssistancePersistentKindPolicyV1.durableKindIDs
                .map({ $0.replacingOccurrences(of: "PERSISTENT_MODEL:", with: "") })
                .reduce(into: Set<String>(), { $0.insert($1) }),
              nonpersistentValueNames == ["AssistanceProposalV1"],
              AssistancePersistenceEnrollmentV1.durableModelCount == durableRowNames.count,
              !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent,
              ordinaryDeletionPreservesAcceptedHistory,
              workspaceEraseClearsAcceptedHistory,
              proposalsOwnNoFilesystemPayload else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C49WorkResourceKernelDeletionEraseEnrollmentV1 {
    static let family = "ManualWorkResourceRecordRow"
    static let deleteDisposition = "PRESERVE_ACCEPTED_HISTORY"
    static let eraseDisposition = "CLEAR_WITH_WORKSPACE_GENERATION"
}

enum C55PartsStockKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = C55PartsStockPersistenceBoundaryV1.persistentTypes.map { String(describing: $0) }
    static let ordinaryPartRetirementUsesCanonicalSuccessor = true
    static let ordinaryDeletePreservesAppendOnlyMovements = true
    static let workspaceEraseClearsAllSevenFamilies = true
    static func validate() throws { guard durableFamilies.count == 7, ordinaryPartRetirementUsesCanonicalSuccessor, ordinaryDeletePreservesAppendOnlyMovements, workspaceEraseClearsAllSevenFamilies else { throw KernelPersistenceV4Failure.incompleteCoverage } }
}

enum C57MyDayKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = ["MyDayPlanRowV1", "MyDayCarryoverReceiptRowV1"]
    static let ordinaryRemovalPreservesPlanHistory = true
    static let workspaceEraseClearsAllMyDayTruth = true
    static let projectionsOwnNoDeletionTruth = true
    static func validate() throws {
        guard durableFamilies.count == 2, ordinaryRemovalPreservesPlanHistory,
              workspaceEraseClearsAllMyDayTruth, projectionsOwnNoDeletionTruth else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

/// C05 owns exactly the append-only association event and immutable sequence
/// revision rows. Subject/report removal records an association successor;
/// only workspace Erase clears the two V43 families and their owned content.
enum EvidenceMetadataKernelDeletionEraseEnrollmentV1 {
    static let durableRowNames: Set<String> = [
        "EvidenceAssociationEventRowV1",
        "EvidenceSequenceRevisionRowV1",
    ]
    static let durableFamilies = EvidenceMetadataDeletionLedgerPolicyV1.durableFamilies
    static let ordinaryRemovalPreservesPredecessorHistory = true
    static let ordinaryRemovalUsesAppendOnlyAssociationSuccessor = true
    static let workspaceEraseClearsRowsAndOwnedDerivatives = true
    static let orphanCleanupNeverDeletesMetadataRowsFromMissingBytes = true

    static func validate() throws {
        try EvidenceMetadataDeletionLedgerPolicyV1.validate()
        guard durableRowNames.count == 2,
              durableFamilies == [
                EvidenceMetadataPersistenceEnrollmentV1.associationEventFamily,
                EvidenceMetadataPersistenceEnrollmentV1.sequenceRevisionFamily,
              ], ordinaryRemovalPreservesPredecessorHistory,
              ordinaryRemovalUsesAppendOnlyAssociationSuccessor,
              workspaceEraseClearsRowsAndOwnedDerivatives,
              orphanCleanupNeverDeletesMetadataRowsFromMissingBytes else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}


/// C33 has exactly two SwiftData rows. Derivative and retention values are
/// journal/content support, not additional row families.
enum TemporalEvidenceKernelDeletionEnrollmentV1 {
    static let durableRowNames: Set<String> = [
        "TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"
    ]
    static let journalSupportValueNames: Set<String> = [
        "TemporalEvidenceDerivativeV1", "TemporalEvidenceRetentionEventV1"
    ]
    static let ordinaryDeleteRemovesClipGraph = true
    static let eraseClearsRowsAndOwnedContent = true
    static let missingBytesNeverDeleteCanonicalRows = true

    static func validate() throws {
        guard durableRowNames.count == 2,
              journalSupportValueNames.count == 2,
              durableRowNames.isDisjoint(with: journalSupportValueNames),
              ordinaryDeleteRemovesClipGraph,
              eraseClearsRowsAndOwnedContent,
              missingBytesNeverDeleteCanonicalRows else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C30EvidenceContextKernelDeletionEnrollmentV1 {
    static let persistentRowNames: Set<String> = ["EvidenceContextRow", "PairedObservationLinkRow"]
    static let derivedNames: Set<String> = ["DerivedSolarContextV1", "PairedObservationMismatchPreviewV1"]
    static let ordinaryDeletionRetainsImmutableHistory = true
    static let workspaceEraseClearsRows = true

    static func validate() throws {
        guard persistentRowNames.count == 2, derivedNames.count == 2,
              persistentRowNames.isDisjoint(with: derivedNames),
              ordinaryDeletionRetainsImmutableHistory, workspaceEraseClearsRows else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}
enum AssetLocatorKernelDeletionEnrollmentV1 {
    static let persistentRowNames: Set<String> = [
        "AssetLocatorRow", "LocatorBindingReceiptRow"
    ]
    static let derivedProjectionNames: Set<String> = [
        "LocatorResolutionV1", "LocatorBindingPreviewV1",
        "AssetLocatorLifecycleClosureV1"
    ]
    static let ordinaryAssetDeleteRemovesOwnedRows = true
    static let workspaceEraseClearsRows = true

    static func validate() throws {
        guard persistentRowNames.count == 2,
              derivedProjectionNames.count == 3,
              persistentRowNames.isDisjoint(with: derivedProjectionNames),
              ordinaryAssetDeleteRemovesOwnedRows,
              workspaceEraseClearsRows else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try AssetLocatorDeletionLedgerPolicyV1.validate()
    }
}

/// Schedule rows have no file-owned payload and remain intact through an
/// ordinary asset/site delete. Workspace Erase clears the release/history
/// closure, while due/reminder projections are rebuilt from it.
enum ScheduleKernelDeletionEnrollmentV1 {
    static let persistentRowNames: Set<String> = [
        "ScheduleDefinitionReleaseRow", "OccurrenceHistoryEventRow",
        "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"
    ]
    static let derivedProjectionNames: Set<String> = [
        "DueQueueProjectionV1", "ReminderProjectionV1", "OccurrenceGenerationPlanV1"
    ]
    static let ordinaryAssetOrSiteDeletePreservesRows = true
    static let workspaceEraseClearsRows = true
    static let rowsOwnNoFilesystemPayload = true
    static let embeddedCalendarOverrideBasisClosureCount = 6

    static func validate() throws {
        guard persistentRowNames.count == 4,
              derivedProjectionNames.count == 3,
              persistentRowNames.isDisjoint(with: derivedProjectionNames),
              ordinaryAssetOrSiteDeletePreservesRows,
              workspaceEraseClearsRows,
              rowsOwnNoFilesystemPayload,
              embeddedCalendarOverrideBasisClosureCount == C51ScheduleBackupClosureV1.embeddedCanonicalComponents.count,
              ScheduleEraseBoundaryV1.validate() else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try ScheduleDeletionLedgerPolicyV1.validate()
    }
}

/// Plan rows preserve immutable document/revision/placement history through
/// ordinary asset or site deletion. Workspace Erase clears the four SwiftData
/// rows; spatial frames remain an embedded transport family and previews or
/// component registries are rebuilt rather than deleted as canonical rows.
enum PlanKernelDeletionEnrollmentV1 {
    static let persistentRowNames: Set<String> = [
        "PlanDocumentRow", "PlanRevisionRow", "PlanPlacementRow", "RebaseReceiptRow"
    ]
    static let embeddedTransportFamily = "SpatialReferenceFrameV1"
    static let derivedProjectionNames: Set<String> = [
        "RebasePreviewV1", "PlanRebaseComponentRegistryV1"
    ]
    static let ordinaryDeletionPreservesHistory = true
    static let workspaceEraseClearsRows = true
    static let rowsOwnNoFilesystemPayload = true

    static func validate() throws {
        guard persistentRowNames.count == PlanPersistenceEnrollmentV1.durableModelCount,
              embeddedTransportFamily == "SpatialReferenceFrameV1",
              derivedProjectionNames.count == 2,
              persistentRowNames.isDisjoint(with: derivedProjectionNames),
              ordinaryDeletionPreservesHistory,
              workspaceEraseClearsRows,
              rowsOwnNoFilesystemPayload else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try PlanDeletionLedgerPolicyV1.validate()
    }
}

/// Pose observations are durable event history, while current tips, completed
/// snapshots, and axis registries are rebuilt projections.  Ordinary asset
/// deletion therefore preserves the event graph; workspace Erase is the only
/// operation that clears its canonical rows.
enum PlacementPoseKernelDeletionEnrollmentV1 {
    static let persistentRowNames: Set<String> = [
        "AssetPoseEventRow", "SpatialAnchorObservationRow"
    ]
    static let derivedProjectionNames: Set<String> = [
        "PoseAxisDescriptorRegistryV1", "AssetPoseCurrentTipV1",
        "CompletedPlacementPoseSnapshotV1"
    ]
    static let ordinaryDeletionPreservesHistory = true
    static let workspaceEraseClearsRows = true
    static let sensorProposalsAreNonpersistent = true

    static func validate() throws {
        guard persistentRowNames.count == PlacementPosePersistenceEnrollmentV1.durableModelCount,
              derivedProjectionNames.count == 3,
              persistentRowNames.isDisjoint(with: derivedProjectionNames),
              ordinaryDeletionPreservesHistory,
              workspaceEraseClearsRows,
              sensorProposalsAreNonpersistent else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try PlacementPoseDeletionLedgerPolicyV1.validate()
    }
}

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
    static let measurementIntegrityDeleteKinds = V18BackupMeasurementIntegrityRecordV1.Kind.allCases
    static let privacyTransformDeleteKinds = V19BackupPrivacyTransformRecordV1.Kind.allCases
    static let clientCapabilityDeleteKinds=V20BackupClientCapabilityRecordV1.Kind.allCases
    static let fieldReferenceDeleteKinds=V22BackupFieldReferenceRecordV1.Kind.allCases
    static let accessibleDocumentDeleteFamilyCount=AccessibleDocumentLifecycleV1.persistentFamilies.count

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
    static func validateMeasurementIntegrityLifecycle() throws {
        guard measurementIntegrityDeleteKinds.count == 5 else { throw KernelPersistenceV4Failure.incompleteCoverage }
        try MeasurementIntegrityDeletionLedgerPolicyV1.validate()
    }
    static func validatePrivacyTransformLifecycle() throws {
        guard privacyTransformDeleteKinds.count == 4 else { throw KernelPersistenceV4Failure.incompleteCoverage }
        try PrivacyTransformDeletionLedgerPolicyV1.validate()
    }
    static func validateClientCapabilityLifecycle()throws{guard clientCapabilityDeleteKinds.count==4 else{throw KernelPersistenceV4Failure.incompleteCoverage};try ClientCapabilityDeletionLedgerPolicyV1.validate()}
    static func validateFieldReferenceLifecycle()throws{guard fieldReferenceDeleteKinds.count==2,FieldReferencePackLifecycleV1.persistentFamilies.count==2 else{throw KernelPersistenceV4Failure.incompleteCoverage};try FieldReferenceDeletionLedgerPolicyV1.validate()}
    static func validateAccessibleDocumentLifecycle()throws{guard accessibleDocumentDeleteFamilyCount==1,AccessibleDocumentLifecycleV1.semanticTreePersistence=="DERIVED_ONLY" else{throw KernelPersistenceV4Failure.incompleteCoverage};try AccessibleDocumentDeletionLedgerPolicyV1.validate()}
    static func validateScheduleLifecycle() throws {
        try ScheduleKernelDeletionEnrollmentV1.validate()
        guard ScheduleDeletionIntentBoundaryV1.validate(),
              ScheduleOrphanCleanupPolicyV1.rowsOwnNoFilesystemPayload,
              ScheduleOrphanCleanupPolicyV1.projectionsAreDerived,
              ScheduleOrphanCleanupPolicyV1.missingFileCannotDeleteCanonicalRows,
              ScheduleOrphanCleanupPolicyV1.missingFileCannotPruneEmbeddedCalendarOverrideOrBasisClosure,
              !ScheduleOrphanCleanupPolicyV1.notificationStateIsTruth else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validatePlanLifecycle() throws {
        try PlanKernelDeletionEnrollmentV1.validate()
        guard PlanStreamingArchivePolicyV1.recordsSchemaVersion == 27,
              PlanStreamingArchivePolicyV1.persistentSchemaVersion == 28,
              PlanRestoreIdentityPolicyV1.durableFamilyCount == 4,
              !PlanRestoreIdentityPolicyV1.sourcePlanAutomaticallyActive,
              !PlanReplacementRestorePolicyV1.derivedPreviewRestored,
              !PlanReplacementRestorePolicyV1.sourcePlanAutomaticallyActiveOnCloneOrFork else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validatePlacementPoseLifecycle() throws {
        try PlacementPoseKernelDeletionEnrollmentV1.validate()
        guard PlacementPoseStreamingArchivePolicyV1.recordsSchemaVersion == 28,
              PlacementPoseStreamingArchivePolicyV1.persistentSchemaVersion == 29,
              PlacementPoseRestoreIdentityPolicyV1.durableFamilyCount == 2,
              !PlacementPoseRestoreIdentityPolicyV1.cloneForkSourcePoseAutomaticallyActive,
              PlacementPoseReplacementRestorePolicyV1.durableFamilyCount == 2,
              !PlacementPoseReplacementRestorePolicyV1.derivedProjectionsRestored else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static let lightingDeleteKinds = V31BackupLightingRecordV1.Kind.allCases
    static let lightingDurableFamilyCount = 5

    static func validateLightingLifecycle() throws {
        guard lightingDeleteKinds.count == lightingDurableFamilyCount,
              Set(lightingDeleteKinds.map(\.rawValue)).count
                == lightingDurableFamilyCount,
              LightingPersistenceEnrollmentV1.persistentSchemaVersion == 31,
              LightingPersistenceEnrollmentV1.recordsSchemaVersion == 30,
              LightingPersistenceEnrollmentV1.durableModelCount
                == lightingDurableFamilyCount,
              C31LightingDeletionIntentBoundaryV1
                .ordinaryDeletionPreservesImmutableLightingHistory,
              C31LightingEraseIntentBoundaryV1
                .removesAllFiveDurableFamilies else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
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
        try EvidenceMetadataKernelDeletionEraseEnrollmentV1.validate()
        try C04ShopReportProfileKernelDeletionEraseEnrollmentV1.validate()
        try C05RoundSessionKernelDeletionEraseEnrollmentV1.validate()
        try C08ImportBulkKernelDeletionEraseEnrollmentV1.validate()
        try EvidenceQualityKernelDeletionEraseEnrollmentV1.validate()
        try FastSurveyInboxKernelDeletionEraseEnrollmentV1.validate()
        try TemporalEvidenceKernelDeletionEnrollmentV1.validate()
        try AssetLocatorKernelDeletionEnrollmentV1.validate()
        try validateSurveyDefinitionLifecycle()
        try SurveySessionKernelDeletionEnrollmentV1.validate()
        try validateClientCapabilityLifecycle()
        try validateFieldReferenceLifecycle()
        try validateAccessibleDocumentLifecycle()
        try validateScheduleLifecycle()
        try validatePlanLifecycle()
        try validatePlacementPoseLifecycle()
        try validateLightingLifecycle()
        try validatePrivacyTransformLifecycle()
        try validateMeasurementIntegrityLifecycle()
        try validatePackageEvolutionLifecycle()
        try validateFunctionalRelationshipLifecycle()
        try validateEvidenceAssuranceLifecycle()
        try validateInspectionReviewLifecycle()
        try validateWorkPacketLifecycle()
        try validateFieldDraftLifecycle()
        try validateSearchLifecycle()
        try validateIntegrationProjectionLifecycle()
        try validateAssistanceLifecycle()
        try C53AssetServiceReliabilityKernelDeletionEraseEnrollmentV1.validate()
        try C55PartsStockKernelDeletionEraseEnrollmentV1.validate()
        try validate(registrations)
    }

    static func validateAssistanceLifecycle() throws {
        try C32AssistanceKernelDeletionEnrollmentV1.validate()
        guard AssistanceRemovalKindV1.allCases.count == 4 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func validateSurveyDefinitionLifecycle() throws {
        guard SurveyDefinitionEraseBoundaryV1.atomicFamilyCount == 2,
              SurveyDefinitionEraseBoundaryV1.lifecycleEventsAreMutationHistoryOnly,
              SurveyDefinitionEraseBoundaryV1.workspaceEraseClearsIdentityAndReleaseRows,
              SurveyDefinitionEraseBoundaryV1.quarantinedImportsAreNoncanonical else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
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

enum C45AcceptedLabelKernelDeletionEnrollmentV1 {
    static let durableFamily = "AcceptedLabelGenerationSnapshotRow"
    static let ordinaryDeleteRule = "DELETE_WHOLE_SNAPSHOT_WHEN_ANY_BOUND_ASSET_IS_DELETED"
    static let deletionLedgerKind = DeletionRecordKindV2.acceptedLabelGenerationSnapshot
    static let scratchOwner = "jobs/asset-label-render/<jobID>"
    static let eraseOwner = "WORKSPACE_ERASE"

    static func validate() throws {
        guard AssetLabelPersistenceEnrollmentV1.durableModelCount == 1,
              AssetLabelPersistenceEnrollmentV1.persistentFamilies == [durableFamily],
              deletionLedgerKind.rawValue == "acceptedLabelGenerationSnapshot",
              ordinaryDeleteRule == "DELETE_WHOLE_SNAPSHOT_WHEN_ANY_BOUND_ASSET_IS_DELETED",
              scratchOwner == "jobs/asset-label-render/<jobID>",
              eraseOwner == "WORKSPACE_ERASE" else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C46OperationalContactKernelDeletionEnrollmentV1 {
    static let durableFamilies = ["ServiceContactPointRow", "SystemHandoffIntentRow"]
    static let ordinaryAssetOrSiteDeleteCascades = false
    static let workspaceEraseOwnsRows = true
    static let platformOutcomeRows = 0

    static func validate() throws {
        guard OperationalContactPersistenceEnrollmentV1.persistentSchemaVersion == 35,
              OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion == 34,
              OperationalContactPersistenceEnrollmentV1.persistentFamilies == durableFamilies,
              !ordinaryAssetOrSiteDeleteCascades,
              workspaceEraseOwnsRows,
              platformOutcomeRows == 0 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C47ActivityContractKernelDeletionEnrollmentV2 {
    static let newlyRowBackedFamilies = C47ActivityContractPersistenceBoundaryV2.newlyEnrolledRows
    static let reusedCompletedSnapshotFamily = C47ActivityContractPersistenceBoundaryV2.reusedDurableFamily
    static let ordinaryAssetDeletionRemovesOnlyUnfinalizedMatchingSubjects = true
    static let finalizedAndSupersededHistoryIsRetained = true
    static let workspaceEraseOwnsAllFiveRowsAndReleasedSnapshotFiles = true
    static let conformanceReceiptsAndNoPlanFallbackAreNonpersistent = true

    static func validate() throws {
        guard C47ActivityContractPersistenceBoundaryV2.persistentSchemaVersion == 36,
              C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion == 35,
              C47ActivityContractPersistenceBoundaryV2.durableModelCount == 6,
              newlyRowBackedFamilies.count == 5,
              reusedCompletedSnapshotFamily == "CompletedActivitySnapshotV2",
              ordinaryAssetDeletionRemovesOnlyUnfinalizedMatchingSubjects,
              finalizedAndSupersededHistoryIsRetained,
              workspaceEraseOwnsAllFiveRowsAndReleasedSnapshotFiles,
              conformanceReceiptsAndNoPlanFallbackAreNonpersistent else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}


enum C48PortableExchangeKernelDeletionEnrollmentV2 {
    static let persistentRowCount = 0
    static let ordinaryDeletionRetainsHistory = true
    static let workspaceEraseRemovesProtectedStore = true
    static let exportedCopiesAreNonrecallable = true
    static func validate() throws {
        guard persistentRowCount == 0,
              ordinaryDeletionRetainsHistory,
              workspaceEraseRemovesProtectedStore,
              exportedCopiesAreNonrecallable else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-lifecycle
enum C52ServiceRequestKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = ServiceRequestPersistenceEnrollmentV1.durableFamilies
    static let ordinaryDeleteDisposition = "PRESERVE_ACCEPTED_HISTORY"
    static let explicitUnlinkUsesAppendOnlyReversal = true
    static let workspaceEraseClearsAllThreeFamilies = true
    static let eraseClearsProtectedInvitationMappings = true
    static let escapedPortableFilesAreRecallable = false

    static func validate() throws {
        try ServiceRequestPersistenceEnrollmentV1.validate()
        guard durableFamilies.count == 3,
              ordinaryDeleteDisposition == "PRESERVE_ACCEPTED_HISTORY",
              explicitUnlinkUsesAppendOnlyReversal,
              workspaceEraseClearsAllThreeFamilies,
              eraseClearsProtectedInvitationMappings,
              !escapedPortableFilesAreRecallable else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C53AssetServiceReliabilityKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = AssetServiceReliabilityPersistenceEnrollmentV1.durableFamilies
    static let ordinaryDeleteDisposition = "PRESERVE_APPEND_ONLY_HISTORY"
    static let workspaceEraseClearsAllCanonicalFamilies = true
    static let cloneForkSourceHistoryIsNotActiveTruth = true
    static let derivedMetricProjectionIsRebuilt = true
    static let rowsOwnNoFilesystemPayload = true

    static func validate() throws {
        try AssetServiceReliabilityPersistenceEnrollmentV1.validate()
        guard durableFamilies.count == 7,
              ordinaryDeleteDisposition == "PRESERVE_APPEND_ONLY_HISTORY",
              workspaceEraseClearsAllCanonicalFamilies,
              cloneForkSourceHistoryIsNotActiveTruth,
              derivedMetricProjectionIsRebuilt,
              rowsOwnNoFilesystemPayload,
              C53AssetServiceReliabilityEraseIntentBoundaryV1.validate() else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

/// C04 persists one append-only, device-local profile history family. Normal
/// domain deletion never rewrites it; workspace erase is the only destructive
/// lifecycle boundary and clears the complete family with its generation.
enum C04ShopReportProfileKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = ["ShopReportProfileRowV1"]
    static let ordinaryDeleteDisposition = "PRESERVE_APPEND_ONLY_HISTORY"
    static let workspaceEraseClearsAllCanonicalFamilies = true
    static let cloneForkSourceHistoryIsNotActiveTruth = true
    static let rowsOwnNoFilesystemPayload = true

    static func validate() throws {
        try C04ShopReportProfileBackupEnrollmentV1.validate(
            V4BackupRecordsV1(recordsSchemaVersion:
                C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion)
        )
        guard durableFamilies == ["ShopReportProfileRowV1"],
              ordinaryDeleteDisposition == "PRESERVE_APPEND_ONLY_HISTORY",
              workspaceEraseClearsAllCanonicalFamilies,
              cloneForkSourceHistoryIsNotActiveTruth,
              rowsOwnNoFilesystemPayload else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

/// C05 stores completed-item state inside one append-only session revision
/// family. Ordinary asset removal leaves that historic completion evidence
/// intact; only workspace Erase clears it.
enum C05RoundSessionKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = ["RoundSessionRevisionRowV1"]
    static let ordinaryDeleteDisposition = "PRESERVE_SESSION_AND_COMPLETED_ITEM_HISTORY"
    static let workspaceEraseClearsAllCanonicalFamilies = true
    static let rowsOwnNoFilesystemPayload = true

    static func validate() throws {
        try C05RoundSessionBackupEnrollmentV1.validate(
            V4BackupRecordsV1(
                assets: [], evidenceFiles: [], issues: [], packets: [],
                recordsSchemaVersion: C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion,
                reports: [], sites: [], workflowRecords: []
            )
        )
        guard durableFamilies == ["RoundSessionRevisionRowV1"],
              ordinaryDeleteDisposition == "PRESERVE_SESSION_AND_COMPLETED_ITEM_HISTORY",
              workspaceEraseClearsAllCanonicalFamilies,
              rowsOwnNoFilesystemPayload else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C08ImportBulkKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = ["ImportMappingProfileRowV1", "BulkSessionRowV1", "BulkCommitReceiptRowV1"]
    static let ordinaryDeleteRemovesSavedMappingsAndSessions = true
    static let immutableReceiptHistoryIsPreservedOrArchived = true
    static let committedBatchRollbackIsForbidden = true
    static let workspaceEraseClearsC08Rows = true
    static func validate() throws {
        guard durableFamilies.count == 3,
              ordinaryDeleteRemovesSavedMappingsAndSessions,
              immutableReceiptHistoryIsPreservedOrArchived,
              committedBatchRollbackIsForbidden,
              workspaceEraseClearsC08Rows else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

/// C10 assessments, rule snapshots, waiver history, and their typed receipts
/// are immutable workspace truth. Ordinary sign deletion never rewrites that
/// history; only an authorized whole-workspace erase clears all four rows.
enum EvidenceQualityKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = [
        "EvidenceQualityRuleSetRowV1",
        "EvidenceQualityAssessmentRowV1",
        "EvidenceQualityWaiverRowV1",
        "EvidenceQualityMutationReceiptRowV1",
    ]
    static let ordinaryDeletePreservesHistoricAssessmentsAndWaivers = true
    static let workspaceEraseClearsAllCanonicalFamilies = true
    static let waiverHistoryIsNeverRewritten = true

    static func validate() throws {
        guard durableFamilies.count == EvidenceQualitySchemaV1.durableModelCount,
              ordinaryDeletePreservesHistoricAssessmentsAndWaivers,
              workspaceEraseClearsAllCanonicalFamilies,
              waiverHistoryIsNeverRewritten else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

/// Ordinary sign deletion retains C11 reviewable inbox/provenance history;
/// only whole-workspace erase clears its five canonical families.
enum FastSurveyInboxKernelDeletionEraseEnrollmentV1 {
    static let durableFamilies = ["CaptureInboxItemRowV1", "CapturePromotionRowV1", "SnippetRowV1", "SnippetInsertionHistoryRowV1", "FastSurveyInboxMutationReceiptRowV1"]
    static let ordinaryDeletePreservesReviewableInbox = true
    static let workspaceEraseClearsAllCanonicalFamilies = true

    static func validate() throws {
        guard durableFamilies.count == FastSurveyInboxSchemaV1.durableModelCount,
              ordinaryDeletePreservesReviewableInbox, workspaceEraseClearsAllCanonicalFamilies else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

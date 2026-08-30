import Foundation

enum GuidedSurveyBackupRegistryV1 {
    static let persistentSchemaVersion = 25
    static let recordsSchemaVersion = 24
    static let canonicalKinds = Set(V25BackupGuidedSurveyRecordV1.Kind.allCases)
}

enum C30EvidenceContextBackupRestoreRegistryV1 {
    static let persistentSchemaVersion = 30
    static let recordsSchemaVersion = 29
    static let archiveKinds = V30BackupEvidenceContextRecordV1.Kind.allCases
    static let derivedProjectionDisposition = "DROP_AND_REBUILD"
    static let providerStateIsTruth = false

    static func validate() throws {
        guard persistentSchemaVersion == 30, recordsSchemaVersion == 29,
              archiveKinds.count == 2,
              derivedProjectionDisposition == "DROP_AND_REBUILD",
              !providerStateIsTruth else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C31LightingBackupRestoreRegistryV1 {
    static let persistentSchemaVersion = 31
    static let recordsSchemaVersion = 30
    static let archiveKinds = V31BackupLightingRecordV1.Kind.allCases
    static let durableFamilyCount = 5
    static let derivedProjectionDisposition = "DROP_AND_REBUILD"
    static let providerStateIsTruth = false
    static let licensedCriterionTextIncluded = false
    static let sameWorkspacePreservesCanonicalBytes = true
    static let cloneForkSourceClaimAutomaticallyActive = false

    static func validate() throws {
        guard persistentSchemaVersion == 31,
              recordsSchemaVersion == 30,
              archiveKinds.count == durableFamilyCount,
              Set(archiveKinds.map(\.rawValue)).count == durableFamilyCount,
              derivedProjectionDisposition == "DROP_AND_REBUILD",
              !providerStateIsTruth,
              !licensedCriterionTextIncluded,
              sameWorkspacePreservesCanonicalBytes,
              !cloneForkSourceClaimAutomaticallyActive else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C32AssistanceBackupRestoreRegistryV1 {
    static let persistentSchemaVersion = 32
    static let recordsSchemaVersion = 31
    static let durableFamilyCount = 1
    static let archiveDisposition = "IMMUTABLE_ACCEPTANCE_RECEIPT_ONLY"
    static let proposalDisposition = "EXCLUDED_NONPERSISTENT"
    static let cloneForkDisposition = "PRESERVE_TRANSITIVE_HISTORIC_SOURCE_PROVENANCE"

    static func validate() throws {
        guard persistentSchemaVersion == AssistancePersistenceEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion == AssistancePersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount == AssistancePersistenceEnrollmentV1.durableModelCount,
              archiveDisposition == "IMMUTABLE_ACCEPTANCE_RECEIPT_ONLY",
              proposalDisposition == "EXCLUDED_NONPERSISTENT",
              cloneForkDisposition == "PRESERVE_TRANSITIVE_HISTORIC_SOURCE_PROVENANCE" else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C33TemporalEvidenceBackupRestoreRegistryV1 {
    static let durableFamilies = TemporalEvidencePersistenceEnrollmentV1.persistentFamilies
    static let archiveDisposition = "CANONICAL_METADATA_PLUS_DIRECT_CONTENT_BYTES"
    static let contentMemberAuthority = "content/<workspace>/<contentID>/original.bin"
    static let cloneForkDisposition = "REBIND_METADATA_PRESERVE_ORIGINAL_CONTENT_DIGEST"
    static let derivedContentDisposition = "EXISTING_CONTENT_AUTHORITY_REGENERABLE"

    static func validate() throws {
        guard durableFamilies == ["TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"],
              archiveDisposition == "CANONICAL_METADATA_PLUS_DIRECT_CONTENT_BYTES",
              contentMemberAuthority.contains("content"),
              cloneForkDisposition == "REBIND_METADATA_PRESERVE_ORIGINAL_CONTENT_DIGEST",
              derivedContentDisposition == "EXISTING_CONTENT_AUTHORITY_REGENERABLE" else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C45AcceptedLabelBackupRestoreRegistryV1 {
    static let persistentSchemaVersion = AssetLabelPersistenceEnrollmentV1.persistentSchemaVersion
    static let recordsSchemaVersion = AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion
    static let durableFamilies = AssetLabelPersistenceEnrollmentV1.persistentFamilies
    static let archiveDisposition = "CANONICAL_ACCEPTED_SNAPSHOT_AND_IMMUTABLE_MUTATION_HISTORY"
    static let cloneForkDisposition = "TARGET_SCOPED_HISTORIC_EXPORT_ONLY"
    static let derivedScratchDisposition = "EXCLUDED_REGENERABLE"

    static func validate() throws {
        guard persistentSchemaVersion == 34, recordsSchemaVersion == 33,
              durableFamilies == ["AcceptedLabelGenerationSnapshotRow"],
              archiveDisposition == "CANONICAL_ACCEPTED_SNAPSHOT_AND_IMMUTABLE_MUTATION_HISTORY",
              cloneForkDisposition == "TARGET_SCOPED_HISTORIC_EXPORT_ONLY",
              derivedScratchDisposition == "EXCLUDED_REGENERABLE" else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

/// C28 schedule backup/restore is a two-family closure: immutable definition
/// releases plus append-only occurrence history. Projection queues and
/// reminders are rebuilt after restore and never enter the kernel archive.
enum ScheduleBackupRestoreRegistryV1 {
    static let persistentSchemaVersion = 27
    static let recordsSchemaVersion = 26
    static let durableFamilyCount = 2
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let derivedProjectionDisposition = "DROP_AND_REBUILD"
    static let notificationStateIsTruth = false
    static let cloneForkSourceScheduleAutomaticallyActive = false

    static func validate() throws {
        guard persistentSchemaVersion == 27,
              recordsSchemaVersion == 26,
              durableFamilyCount == 2,
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              derivedProjectionDisposition == "DROP_AND_REBUILD",
              !notificationStateIsTruth,
              !cloneForkSourceScheduleAutomaticallyActive else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try ScheduleRestoreIdentityPolicyV1.validate()
    }
}

enum KernelArchiveDispositionV4: String, Codable, Sendable {
    case includeCanonical = "INCLUDE_CANONICAL"
    case includeImmutableHistory = "INCLUDE_IMMUTABLE_HISTORY"
    case includeOperationalCheckpoint = "INCLUDE_OPERATIONAL_CHECKPOINT"
    case rebuildAfterRestore = "REBUILD_AFTER_RESTORE"
    case excludeDormantDeclaration = "EXCLUDE_DORMANT_DECLARATION"
}

enum KernelRestoreDispositionV4: String, Codable, Sendable {
    case replaceCanonical = "REPLACE_CANONICAL"
    case restoreImmutableIdentity = "RESTORE_IMMUTABLE_IDENTITY"
    case restoreAppendOnlyHistory = "RESTORE_APPEND_ONLY_HISTORY"
    case resetLocalOperational = "RESET_LOCAL_OPERATIONAL"
    case replayRecoveryCheckpoint = "REPLAY_RECOVERY_CHECKPOINT"
    case rebuildContractProjection = "REBUILD_CONTRACT_PROJECTION"
}

enum KernelIdentityMappingV4: String, Codable, Sendable {
    case preserve = "PRESERVE"
    case rebindWorkspace = "REBIND_WORKSPACE"
    case rebindWorkspaceAndLineage = "REBIND_WORKSPACE_AND_LINEAGE"
    case regenerateLocal = "REGENERATE_LOCAL"
    case notApplicable = "NOT_APPLICABLE"
}

struct KernelBackupRestoreRegistrationV4: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, archive, backup, restore, clone, fork, openExport
    }

    let kind: KernelPersistenceV4RecordKind
    let archive: KernelArchiveDispositionV4
    let backup: KernelArchiveDispositionV4
    let restore: KernelRestoreDispositionV4
    let clone: KernelIdentityMappingV4
    let fork: KernelIdentityMappingV4
    let openExport: KernelOpenExportDispositionV4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind < rhs.kind }

    init(
        kind: KernelPersistenceV4RecordKind,
        archive: KernelArchiveDispositionV4,
        backup: KernelArchiveDispositionV4,
        restore: KernelRestoreDispositionV4,
        clone: KernelIdentityMappingV4,
        fork: KernelIdentityMappingV4,
        openExport: KernelOpenExportDispositionV4
    ) throws {
        self.kind = kind
        self.archive = archive
        self.backup = backup
        self.restore = restore
        self.clone = clone
        self.fork = fork
        self.openExport = openExport
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind),
            archive: values.decode(KernelArchiveDispositionV4.self, forKey: .archive),
            backup: values.decode(KernelArchiveDispositionV4.self, forKey: .backup),
            restore: values.decode(KernelRestoreDispositionV4.self, forKey: .restore),
            clone: values.decode(KernelIdentityMappingV4.self, forKey: .clone),
            fork: values.decode(KernelIdentityMappingV4.self, forKey: .fork),
            openExport: values.decode(KernelOpenExportDispositionV4.self, forKey: .openExport)
        )
    }

    func validate() throws {
        let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
        let expected = KernelBackupRestoreRegistryV4.route(for: descriptor.classification)
        guard archive == expected.archive, backup == expected.archive,
              restore == expected.restore, clone == expected.clone,
              fork == expected.fork, openExport == expected.export else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

struct KernelArchiveEntryV4: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, disposition, recordCount, payloadSHA256
    }

    let kind: KernelPersistenceV4RecordKind
    let disposition: KernelArchiveDispositionV4
    let recordCount: Int
    let payloadSHA256: String

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind < rhs.kind }

    init(
        kind: KernelPersistenceV4RecordKind,
        disposition: KernelArchiveDispositionV4,
        recordCount: Int,
        payloadSHA256: String
    ) throws {
        self.kind = kind
        self.disposition = disposition
        self.recordCount = recordCount
        self.payloadSHA256 = payloadSHA256
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind),
            disposition: values.decode(KernelArchiveDispositionV4.self, forKey: .disposition),
            recordCount: values.decode(Int.self, forKey: .recordCount),
            payloadSHA256: values.decode(String.self, forKey: .payloadSHA256)
        )
    }

    func validate() throws {
        let registration = try KernelBackupRestoreRegistryV4.registration(for: kind)
        guard disposition == registration.archive,
              recordCount >= 0,
              KernelMutationEffectV4.validSHA256(payloadSHA256) else {
            throw KernelPersistenceV4Failure.invalidValue
        }
        if [.rebuildAfterRestore, .excludeDormantDeclaration].contains(disposition) {
            guard recordCount == 0,
                  payloadSHA256 == KernelBackupRestoreRegistryV4.emptyPayloadSHA256 else {
                throw KernelPersistenceV4Failure.invalidValue
            }
        }
    }
}

struct KernelArchiveManifestV4: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaID, schemaVersion, schemaDescriptorSHA256, archiveID, sourceGenerationID
        case entries, archiveSHA256
    }

    let schemaID: String
    let schemaVersion: Int
    let schemaDescriptorSHA256: String
    let archiveID: String
    let sourceGenerationID: String
    let entries: [KernelArchiveEntryV4]
    let archiveSHA256: String

    init(
        archiveID: String,
        sourceGenerationID: String,
        entries: [KernelArchiveEntryV4],
        archiveSHA256: String? = nil
    ) throws {
        let schema = try KernelPersistenceV4Schema.descriptor()
        schemaID = schema.schemaID
        schemaVersion = schema.schemaVersion
        schemaDescriptorSHA256 = schema.descriptorDigest
        self.archiveID = archiveID
        self.sourceGenerationID = sourceGenerationID
        self.entries = entries
        self.archiveSHA256 = try archiveSHA256 ?? Self.digest(
            schemaDescriptorSHA256: schema.descriptorDigest,
            archiveID: archiveID,
            sourceGenerationID: sourceGenerationID,
            entries: entries
        )
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaID = try values.decode(String.self, forKey: .schemaID)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaID == KernelPersistenceV4Validation.schemaID,
              schemaVersion == KernelPersistenceV4Validation.schemaVersion else {
            throw KernelPersistenceV4Failure.futureVersion
        }
        self.schemaID = schemaID
        self.schemaVersion = schemaVersion
        schemaDescriptorSHA256 = try values.decode(String.self, forKey: .schemaDescriptorSHA256)
        archiveID = try values.decode(String.self, forKey: .archiveID)
        sourceGenerationID = try values.decode(String.self, forKey: .sourceGenerationID)
        entries = try values.decode([KernelArchiveEntryV4].self, forKey: .entries)
        archiveSHA256 = try values.decode(String.self, forKey: .archiveSHA256)
        try validate()
    }

    func validate() throws {
        let schema = try KernelPersistenceV4Schema.descriptor()
        try KernelBackupRestoreRegistryV4.validate()
        try entries.forEach { try $0.validate() }
        guard schemaID == schema.schemaID, schemaVersion == schema.schemaVersion,
              schemaDescriptorSHA256 == schema.descriptorDigest,
              KernelPersistenceV4Validation.validID(archiveID),
              KernelPersistenceV4Validation.validID(sourceGenerationID),
              entries == entries.sorted(),
              entries.map(\.kind) == KernelPersistenceV4RecordKind.allCases.sorted(),
              Set(entries.map(\.kind)).count == entries.count,
              archiveSHA256 == (try Self.digest(
                schemaDescriptorSHA256: schemaDescriptorSHA256,
                archiveID: archiveID,
                sourceGenerationID: sourceGenerationID,
                entries: entries
              )) else {
            throw KernelPersistenceV4Failure.digestMismatch
        }
    }

    private struct DigestMaterial: Encodable {
        let schemaID: String
        let schemaVersion: Int
        let schemaDescriptorSHA256: String
        let archiveID: String
        let sourceGenerationID: String
        let entries: [KernelArchiveEntryV4]
    }

    private static func digest(
        schemaDescriptorSHA256: String,
        archiveID: String,
        sourceGenerationID: String,
        entries: [KernelArchiveEntryV4]
    ) throws -> String {
        try KernelPersistenceV4Validation.canonicalDigest(DigestMaterial(
            schemaID: KernelPersistenceV4Validation.schemaID,
            schemaVersion: KernelPersistenceV4Validation.schemaVersion,
            schemaDescriptorSHA256: schemaDescriptorSHA256,
            archiveID: archiveID,
            sourceGenerationID: sourceGenerationID,
            entries: entries
        ))
    }
}

enum KernelBackupRestoreRegistryV4 {
    static let functionalRelationshipArchiveKinds =
        V12BackupFunctionalRelationshipRecordV1.Kind.allCases
    static let evidenceAssuranceArchiveKinds = V13BackupEvidenceAssuranceRecordV1.Kind.allCases
    static let inspectionReviewArchiveKinds = V14BackupInspectionReviewRecordV1.Kind.allCases
    static let workPacketArchiveKinds=V15BackupWorkPacketRecordV1.Kind.allCases
    static let fieldDraftArchiveKinds = V16BackupFieldDraftRecordV1.Kind.allCases
    static let packageEvolutionArchiveKinds = V17BackupPackageEvolutionRecordV1.Kind.allCases
    static let measurementIntegrityArchiveKinds = V18BackupMeasurementIntegrityRecordV1.Kind.allCases
    static let privacyTransformArchiveKinds = V19BackupPrivacyTransformRecordV1.Kind.allCases
    static let clientCapabilityArchiveKinds=V20BackupClientCapabilityRecordV1.Kind.allCases
    static let fieldReferenceArchiveKinds=V22BackupFieldReferenceRecordV1.Kind.allCases
    static let assetLocatorArchiveKinds = V26BackupAssetLocatorRecordV1.Kind.allCases
    static let planArchiveKinds = V28BackupPlanRecordV1.Kind.allCases
    static let placementPoseArchiveKinds = V29BackupPlacementPoseRecordV1.Kind.allCases
    static let lightingArchiveKinds = V31BackupLightingRecordV1.Kind.allCases
    static let lightingDurableFamilyCount = 5
    static let accessibleDocumentPersistentFamilies=AccessibleDocumentLifecycleV1.persistentFamilies
    static let accessibleDocumentSemanticTreePersistence=AccessibleDocumentLifecycleV1.semanticTreePersistence
    static let recoverabilityVerificationArchiveKindCount=1

    static func validateFunctionalRelationshipLifecycle() throws {
        guard functionalRelationshipArchiveKinds.count == 2,
              Set(functionalRelationshipArchiveKinds.map(\.rawValue)).count == 2 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func validateEvidenceAssuranceLifecycle() throws {
        guard evidenceAssuranceArchiveKinds.count == 4 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func validateInspectionReviewLifecycle() throws {
        guard inspectionReviewArchiveKinds.count == 5,
              Set(inspectionReviewArchiveKinds.map(\.rawValue)).count == 5 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validateWorkPacketLifecycle()throws{guard workPacketArchiveKinds.count==5,Set(workPacketArchiveKinds.map(\.rawValue)).count==5 else{throw KernelPersistenceV4Failure.incompleteCoverage}}
    static func validateFieldDraftLifecycle() throws {
        guard fieldDraftArchiveKinds.count == 6,
              Set(fieldDraftArchiveKinds.map(\.rawValue)).count == 6 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validatePackageEvolutionLifecycle() throws {
        guard packageEvolutionArchiveKinds.count == 4,
              Set(packageEvolutionArchiveKinds.map(\.rawValue)).count == 4 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validateMeasurementIntegrityLifecycle() throws {
        guard measurementIntegrityArchiveKinds.count == 5,
              Set(measurementIntegrityArchiveKinds.map(\.rawValue)).count == 5 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validatePrivacyTransformLifecycle() throws {
        guard privacyTransformArchiveKinds.count == 4,
              Set(privacyTransformArchiveKinds.map(\.rawValue)).count == 4 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validateClientCapabilityLifecycle()throws{guard clientCapabilityArchiveKinds.count==4 else{throw KernelPersistenceV4Failure.incompleteCoverage}}
    static func validateRecoverabilityVerificationLifecycle()throws{guard recoverabilityVerificationArchiveKindCount==1,RecoverabilityVerificationReceiptV1.schemaVersion==1,RecoverabilityVerificationLifecycleV1.stagingPersistence=="DERIVED_ONLY_DROP_AND_REBUILD",RecoverabilityVerificationLifecycleV1.backupEligibility=="SUBSEQUENT_BACKUPS_ONLY",!RecoverabilityVerificationLifecycleV1.receiptInsideVerifiedArchive,!RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed,!RecoverabilityVerificationLifecycleV1.liveRestorePermitted else{throw KernelPersistenceV4Failure.incompleteCoverage}}
    static func validateFieldReferenceLifecycle()throws{guard fieldReferenceArchiveKinds.count==2,Set(fieldReferenceArchiveKinds.map(\.rawValue)).count==2,FieldReferencePackLifecycleV1.persistentFamilies.count==2,FieldReferencePackLifecycleV1.stagingPersistence=="DERIVED_ONLY",!FieldReferencePackLifecycleV1.runtimeFetchingAllowed,!FieldReferencePackLifecycleV1.currentProjectionPersistent else{throw KernelPersistenceV4Failure.incompleteCoverage}}
    static func validateAssetLocatorLifecycle() throws {
        guard assetLocatorArchiveKinds.count == 2,
              Set(assetLocatorArchiveKinds.map(\.rawValue)).count == 2,
              AssetLocatorStreamingArchivePolicyV1.persistentSchemaVersion == 26,
              AssetLocatorStreamingArchivePolicyV1.recordsSchemaVersion == 25,
              AssetLocatorStreamingArchivePolicyV1.durableFamilyCount == 2,
              AssetLocatorStreamingArchivePolicyV1.lifecycleEventsRemainInMutationHistory,
              AssetLocatorStreamingArchivePolicyV1.sameWorkspacePreservesPublicSignedPayload,
              !AssetLocatorStreamingArchivePolicyV1.cloneForkSourceSignatureActive,
              !AssetLocatorStreamingArchivePolicyV1.privateKeyMaterialMayBeExported else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validateScheduleLifecycle() throws {
        try ScheduleBackupRestoreRegistryV1.validate()
        guard ScheduleStreamingArchivePolicyV1.recordsSchemaVersion == 26,
              ScheduleStreamingArchivePolicyV1.persistentSchemaVersion == 27,
              ScheduleStreamingArchivePolicyV1.durableFamilyCount == 2,
              ScheduleStreamingArchivePolicyV1.lifecycleEventsRemainInMutationHistory,
              !ScheduleStreamingArchivePolicyV1.notificationStateIsTruth,
              !ScheduleStreamingArchivePolicyV1.cloneForkSourceScheduleAutomaticallyActive,
              !ScheduleReplacementRestorePolicyV1.cloneForkSourceScheduleAutomaticallyActive,
              !ScheduleReplacementRestorePolicyV1.derivedProjectionsRestored,
              !ScheduleReplacementRestorePolicyV1.notificationStateRestored else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
    static func validatePlanLifecycle() throws {
        guard planArchiveKinds.count == PlanStreamingArchivePolicyV1.archiveFamilyCount,
              Set(planArchiveKinds.map(\.rawValue)).count == planArchiveKinds.count,
              PlanPersistenceEnrollmentV1.persistentSchemaVersion == 28,
              PlanPersistenceEnrollmentV1.recordsSchemaVersion == 27,
              PlanPersistenceEnrollmentV1.durableModelCount == 4,
              PlanStreamingArchivePolicyV1.recordsSchemaVersion == 27,
              PlanStreamingArchivePolicyV1.persistentSchemaVersion == 28,
              PlanStreamingArchivePolicyV1.lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              PlanStreamingArchivePolicyV1.derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              !PlanStreamingArchivePolicyV1.cloneForkSourcePlanAutomaticallyActive,
              !PlanStreamingArchivePolicyV1.componentRegistryIsArchiveTruth,
              PlanRestoreIdentityPolicyV1.persistentSchemaVersion == 28,
              PlanRestoreIdentityPolicyV1.recordsSchemaVersion == 27,
              PlanRestoreIdentityPolicyV1.durableFamilyCount == 4,
              !PlanRestoreIdentityPolicyV1.sourcePlanAutomaticallyActive,
              !PlanRestoreIdentityPolicyV1.derivedPreviewRestored,
              PlanReplacementRestorePolicyV1.persistentSchemaVersion == 28,
              PlanReplacementRestorePolicyV1.recordsSchemaVersion == 27,
              PlanReplacementRestorePolicyV1.durableFamilyCount == 4,
              !PlanReplacementRestorePolicyV1.derivedPreviewRestored,
              !PlanReplacementRestorePolicyV1.sourcePlanAutomaticallyActiveOnCloneOrFork else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try PlanDeletionLedgerPolicyV1.validate()
    }

    static func validatePlacementPoseLifecycle() throws {
        guard placementPoseArchiveKinds.count == 2,
              Set(placementPoseArchiveKinds.map(\.rawValue)).count == 2,
              PlacementPosePersistenceEnrollmentV1.persistentSchemaVersion == 29,
              PlacementPosePersistenceEnrollmentV1.recordsSchemaVersion == 28,
              PlacementPosePersistenceEnrollmentV1.durableModelCount == 2,
              PlacementPoseStreamingArchivePolicyV1.persistentSchemaVersion == 29,
              PlacementPoseStreamingArchivePolicyV1.recordsSchemaVersion == 28,
              PlacementPoseStreamingArchivePolicyV1.durableFamilyCount == 2,
              PlacementPoseStreamingArchivePolicyV1.archiveFamilyCount == 2,
              PlacementPoseStreamingArchivePolicyV1.lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              PlacementPoseStreamingArchivePolicyV1.derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              PlacementPoseStreamingArchivePolicyV1.sensorProposalPersistence == "NONPERSISTENT",
              !PlacementPoseStreamingArchivePolicyV1.cloneForkSourcePoseAutomaticallyActive,
              PlacementPoseRestoreIdentityPolicyV1.durableFamilyCount == 2,
              !PlacementPoseRestoreIdentityPolicyV1.cloneForkSourcePoseAutomaticallyActive else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try PlacementPoseRestoreIdentityPolicyV1.validate()
        try PlacementPoseDeletionLedgerPolicyV1.validate()
        try PlacementPoseReplacementRestorePolicyV1.validate([])
    }
    static func validateLightingLifecycle() throws {
        guard lightingArchiveKinds.count == lightingDurableFamilyCount,
              Set(lightingArchiveKinds.map(\.rawValue)).count
                == lightingDurableFamilyCount,
              LightingPersistenceEnrollmentV1.persistentSchemaVersion == 31,
              LightingPersistenceEnrollmentV1.recordsSchemaVersion == 30,
              LightingPersistenceEnrollmentV1.durableModelCount
                == lightingDurableFamilyCount else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        try C31LightingBackupRestoreRegistryV1.validate()
    }
    typealias Route = (
        archive: KernelArchiveDispositionV4,
        restore: KernelRestoreDispositionV4,
        clone: KernelIdentityMappingV4,
        fork: KernelIdentityMappingV4,
        export: KernelOpenExportDispositionV4
    )

    static let emptyPayloadSHA256 = KernelCanonicalHashV1.sha256(Data())

    static let registrations: [KernelBackupRestoreRegistrationV4] = {
        do {
            return try KernelPersistenceV4RecordKind.allCases.map { kind in
                let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
                let value = route(for: descriptor.classification)
                return try KernelBackupRestoreRegistrationV4(
                    kind: kind, archive: value.archive, backup: value.archive,
                    restore: value.restore, clone: value.clone, fork: value.fork,
                    openExport: value.export
                )
            }.sorted()
        } catch { preconditionFailure("Invalid KERNEL_PERSISTENCE_V4 backup registry: \(error)") }
    }()

    static func registration(for kind: KernelPersistenceV4RecordKind) throws -> KernelBackupRestoreRegistrationV4 {
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
        try validateSurveyDefinitionLifecycle()
        try validateClientCapabilityLifecycle()
        try validateRecoverabilityVerificationLifecycle()
        try validateFieldReferenceLifecycle()
        try validateAssetLocatorLifecycle()
        try validateScheduleLifecycle()
        try validatePlanLifecycle()
        try validatePlacementPoseLifecycle()
        try validateLightingLifecycle()
        try C32AssistanceBackupRestoreRegistryV1.validate()
        try C33TemporalEvidenceBackupRestoreRegistryV1.validate()
        try C45AcceptedLabelBackupRestoreRegistryV1.validate()
        try C46OperationalContactBackupRestoreRegistryV1.validate()
        try validatePrivacyTransformLifecycle()
        try validateMeasurementIntegrityLifecycle()
        try validatePackageEvolutionLifecycle()
        try validateFunctionalRelationshipLifecycle()
        try validateEvidenceAssuranceLifecycle()
        try validateInspectionReviewLifecycle()
        try validateWorkPacketLifecycle()
        try validateFieldDraftLifecycle()
        try validate(registrations)
    }

    static func validateSurveyDefinitionLifecycle() throws {
        guard SurveyDefinitionLifecycleV1.persistentFamilies == [
            "SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"
        ], SurveyDefinitionLifecycleV1.lifecycleEventPersistence
            == "CANONICAL_MUTATION_JOURNAL_ENVELOPE" else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func validate(_ candidate: [KernelBackupRestoreRegistrationV4]) throws {
        let schema = try KernelPersistenceV4Schema.descriptor()
        guard schema.runtimePosture == .dormantStatic, !schema.activationEnabled else {
            throw KernelPersistenceV4Failure.partialActivation
        }
        try candidate.forEach { try $0.validate() }
        let kinds = candidate.map(\.kind)
        guard candidate == candidate.sorted(),
              kinds == KernelPersistenceV4RecordKind.allCases.sorted(),
              Set(kinds).count == kinds.count else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }

    static func validateForRestore(
        _ manifest: KernelArchiveManifestV4,
        expectedArchiveID: String,
        knownSourceGenerationID: String
    ) throws {
        try manifest.validate()
        guard manifest.archiveID == expectedArchiveID,
              manifest.sourceGenerationID == knownSourceGenerationID else {
            throw KernelPersistenceV4Failure.incompatibleSourceVersion
        }
    }

    static func route(for classification: KernelPersistenceV4Classification) -> Route {
        switch classification {
        case .canonicalWorkspace:
            return (.includeCanonical, .replaceCanonical, .rebindWorkspace,
                    .rebindWorkspaceAndLineage, .canonicalPortable)
        case .immutableContentMetadata:
            return (.includeImmutableHistory, .restoreImmutableIdentity, .rebindWorkspace,
                    .rebindWorkspaceAndLineage, .immutableHistoryPortable)
        case .appendOnlyReceipt:
            return (.includeImmutableHistory, .restoreAppendOnlyHistory, .preserve,
                    .preserve, .immutableHistoryPortable)
        case .deviceLocalOperational:
            return (.includeOperationalCheckpoint, .resetLocalOperational, .regenerateLocal,
                    .regenerateLocal, .excluded)
        case .recoveryJournal:
            return (.includeOperationalCheckpoint, .replayRecoveryCheckpoint, .regenerateLocal,
                    .regenerateLocal, .excluded)
        case .dormantContractDeclaration:
            return (.excludeDormantDeclaration, .rebuildContractProjection, .notApplicable,
                    .notApplicable, .readOnlyContractProjection)
        }
    }
}

enum C45AcceptedLabelBackupRegistryEnrollmentV1 { static let durableFamily="AcceptedLabelGenerationSnapshotRow";static let recordsSchemaVersion=AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion;static let includesDerivedScratch=false }

enum C46OperationalContactBackupRestoreRegistryV1 {
    static let archiveKinds = V35BackupOperationalContactKindV1.allCases

    static func validate() throws {
        guard OperationalContactPersistenceEnrollmentV1.persistentSchemaVersion == 35,
              OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion == 34,
              OperationalContactPersistenceEnrollmentV1.durableModelCount == 2,
              OperationalContactPersistenceEnrollmentV1.persistentFamilies == [
                "ServiceContactPointRow", "SystemHandoffIntentRow",
              ],
              archiveKinds == [.serviceContactPoint, .systemHandoffIntent],
              Set(archiveKinds.map(\.rawValue)).count == 2 else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

enum C46OperationalContactBoundary_12{static let recordsSchemaVersion=34;static let sourceBytesPersistent=false;static let platformOutcomesPersistent=false}
enum C47ActivityContractKernelBackupRestoreEnrollmentV2 { static let persistentSchemaVersion=36;static let recordsSchemaVersion=35;static let semanticFamilyCount=6;static let newRowCount=5;static let completedSnapshotReusesReleasedArchiveLifecycle=true }

enum C48PortableExchangeKernelBackupRestoreEnrollmentV2 {
    static let durableRowCount = 0
    static let explicitArchiveMember = PortableExchangeBackupMemberV2.relativePath
    static let restoreUsesProtectedSidecar = true
    static let cloneForkInvalidatesCapabilities = true
    static func validate() throws {
        guard durableRowCount == 0,
              explicitArchiveMember == "review-exchange/snapshot.json",
              restoreUsesProtectedSidecar,
              cloneForkInvalidatesCapabilities else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

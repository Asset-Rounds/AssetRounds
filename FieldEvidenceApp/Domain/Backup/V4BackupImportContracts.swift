import Foundation

enum C50IncumbentFileExchangeBackupImportBoundaryV1 {
    static let excludesSceneRouteState = C34SceneNavigationCompatibilityBoundaryV1.validate()
    static let createsCanonicalFamily = false
    static let acceptsSourceBytesAsBackupMembers = false
    static let acceptsQuarantineAsBackupMembers = false
    static let acceptsSecurityBookmarks = false
    static let canonicalEffectsUseExistingImportOwners = true

    static func validate() -> Bool {
        excludesSceneRouteState
            && C50IncumbentFileExchangeBackupBoundaryV1.validate()
            && !createsCanonicalFamily
            && !acceptsSourceBytesAsBackupMembers
            && !acceptsQuarantineAsBackupMembers
            && !acceptsSecurityBookmarks
            && canonicalEffectsUseExistingImportOwners
    }
}

enum C08ImportBulkBackupImportBoundaryV1 {
    static let persistentSchemaVersion = 46
    static let recordsSchemaVersion = 45
    static let durableRowKinds = ["ImportMappingProfileRowV1", "BulkSessionRowV1", "BulkCommitReceiptRowV1"]
    static let restoresSourceOrPreviewScratch = false

    static func validate(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion <= recordsSchemaVersion,
              persistentSchemaVersion == recordsSchemaVersion + 1,
              durableRowKinds == C08ImportBulkBackupEnrollmentV1.canonicalRowKinds,
              !restoresSourceOrPreviewScratch else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        try C08ImportBulkBackupEnrollmentV1.validate(records)
    }
}

enum BackupCanonicalDecodingErrorV1: Error, Equatable {
    case invalidManifest
    case invalidRecords
}

enum C49WorkResourceBackupImportBoundaryV1 {
    static let persistentSchemaVersion = 37
    static let recordsSchemaVersion = 36
    static let replacesCanonicalRowsAtomically = true
    static let derivedTotalsSearchAndDraftsAreRebuilt = true

    static func validate(_ records: V4BackupRecordsV1) throws {
        guard (recordsSchemaVersion...C08ImportBulkBackupEnrollmentV1.recordsSchemaVersion)
            .contains(records.recordsSchemaVersion) else {
            throw WorkResourceContractFailureV1.invalidValue
        }
        _ = try records.validateC49WorkResources()
    }
}

/// C52 imports the three canonical service-request families atomically into
/// their existing owners. Older envelopes keep their established absent-array
/// defaults; an envelope carrying any C52 row must advertise records schema 38.
enum C52ServiceRequestBackupImportBoundaryV1 {
    static let persistentSchemaVersion = C52ServiceRequestBackupEnrollmentV1.persistentSchemaVersion
    static let recordsSchemaVersion = C52ServiceRequestBackupEnrollmentV1.recordsSchemaVersion
    static let durableFamilyCount = C52ServiceRequestBackupEnrollmentV1.durableFamilyCount
    static let replacesCanonicalRowsAtomically = true
    static let preservesAppendOnlyHistory = true
    static let preservesImmutableAcceptedSourceBytes = true
    static let rebindRequiresExplicitRestoreIdentity = true
    static let cloneAndForkInvalidateOutstandingCapabilities = true
    static let derivedProjectionsAreRebuilt = true
    static let rawCapabilityBytesAreImportable = false

    static func validate(
        persistent: Int,
        records: Int,
        backup: V4BackupRecordsV1
    ) throws {
        guard persistent == persistentSchemaVersion,
              records == backup.recordsSchemaVersion,
              recordsSchemaVersion == 38,
              durableFamilyCount == 3,
              replacesCanonicalRowsAtomically,
              preservesAppendOnlyHistory,
              preservesImmutableAcceptedSourceBytes,
              rebindRequiresExplicitRestoreIdentity,
              cloneAndForkInvalidateOutstandingCapabilities,
              derivedProjectionsAreRebuilt,
              !rawCapabilityBytesAreImportable else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        do {
            try C52ServiceRequestBackupEnrollmentV1.validate(records: backup)
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validate(_ backup: V4BackupRecordsV1) throws {
        try validate(
            persistent: backup.recordsSchemaVersion + 1,
            records: backup.recordsSchemaVersion,
            backup: backup
        )
    }
}

/// The C55 import boundary accepts only the typed canonical snapshot. The
/// incumbent lifecycle port owns atomic materialization and all derived
/// balance/search rebuild work; this contract never creates a second store.
enum C55PartsStockBackupImportBoundaryV1 {
    static let persistentSchemaVersion = C55PartsStockBackupEnrollmentV1.persistentSchemaVersion
    static let recordsSchemaVersion = C55PartsStockBackupEnrollmentV1.recordsSchemaVersion
    static let restoresSevenFamiliesAtomically = true
    static let usesIncumbentLifecyclePort = true
    static let derivedBalanceAndSearchAreRebuilt = true

    static func validate(_ records: V4BackupRecordsV1, workspaceID: WorkspaceID? = nil) throws {
        guard records.recordsSchemaVersion == recordsSchemaVersion,
              persistentSchemaVersion == 41,
              restoresSevenFamiliesAtomically,
              usesIncumbentLifecyclePort,
              derivedBalanceAndSearchAreRebuilt else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        try C55PartsStockBackupEnrollmentV1.validate(records, workspaceID: workspaceID)
    }
}

enum V12FunctionalRelationshipImportBoundaryV1 {
    static let persistentSchemaVersion = 12
    static let recordsSchemaVersion = 11
    static let recordKinds = V12BackupFunctionalRelationshipRecordV1.Kind.allCases

    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              recordKinds.count == 2 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}
enum C52ServiceRequestBoundary_V4BackupImportContracts {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

enum V13EvidenceAssuranceImportBoundaryV1 {
    static let persistentSchemaVersion = 13
    static let recordsSchemaVersion = 12
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V13BackupEvidenceAssuranceRecordV1.Kind.allCases.count == 4 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

enum V14InspectionReviewImportBoundaryV1 {
    static let persistentSchemaVersion = 14
    static let recordsSchemaVersion = 13
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V14BackupInspectionReviewRecordV1.Kind.allCases.count == 5 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

enum V15WorkPacketImportBoundaryV1 {
    static let persistentSchemaVersion = 15
    static let recordsSchemaVersion = 14
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V15BackupWorkPacketRecordV1.Kind.allCases.count == 5 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

enum V16FieldDraftImportBoundaryV1 {
    static let persistentSchemaVersion = 16
    static let recordsSchemaVersion = 15
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V16BackupFieldDraftRecordV1.Kind.allCases.count == 6 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

enum V17PackageEvolutionImportBoundaryV1 {
    static let persistentSchemaVersion = 17
    static let recordsSchemaVersion = 16
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V17BackupPackageEvolutionRecordV1.Kind.allCases.count == 4 else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

enum V18MeasurementIntegrityImportBoundaryV1 {
    static let persistentSchemaVersion = 18
    static let recordsSchemaVersion = 17
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V18BackupMeasurementIntegrityRecordV1.Kind.allCases.count == 5 else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

enum V19PrivacyTransformImportBoundaryV1 {
    static let persistentSchemaVersion = 19
    static let recordsSchemaVersion = 18
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V19BackupPrivacyTransformRecordV1.Kind.allCases.count == 4 else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

enum V20ClientCapabilityImportBoundaryV1 {
    static let persistentSchemaVersion = 20; static let recordsSchemaVersion = 19
    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion, records == recordsSchemaVersion,
              V20BackupClientCapabilityRecordV1.Kind.allCases.count == 4 else { throw BackupImportServiceError.unsupportedSchemaVersion }
    }
}

enum V21RecoverabilityImportBoundaryV1 {
    static let persistentSchemaVersion=21;static let recordsSchemaVersion=20;static let durableFamilyCount=1
    static func validate(persistent:Int,records:Int)throws {
        guard persistent==persistentSchemaVersion,records==recordsSchemaVersion,durableFamilyCount==1 else{throw BackupImportServiceError.unsupportedSchemaVersion}
    }
}
enum V22FieldReferenceImportBoundaryV1{static let persistentSchemaVersion=22;static let recordsSchemaVersion=21;static func validate(persistent:Int,records:Int)throws{guard persistent==22,records==21,V22BackupFieldReferenceRecordV1.Kind.allCases.count==2 else{throw BackupImportServiceError.unsupportedSchemaVersion}}}
enum V23AccessibleDocumentImportBoundaryV1{static let persistentSchemaVersion=23;static let recordsSchemaVersion=22;static let durableFamilyCount=1;static let semanticTreePersistence="DERIVED_ONLY";static func validate(persistent:Int,records:Int)throws{guard persistent==23,records==22,durableFamilyCount==1,semanticTreePersistence==AccessibleDocumentLifecycleV1.semanticTreePersistence else{throw BackupImportServiceError.unsupportedSchemaVersion}}}
enum V24SurveyDefinitionImportBoundaryV1{static let persistentSchemaVersion=24;static let recordsSchemaVersion=23;static let durableFamilyCount=2;static let lifecycleEventStorage="MUTATION_HISTORY_ONLY";static func validate(persistent:Int,records:Int)throws{guard persistent==persistentSchemaVersion,records==recordsSchemaVersion,durableFamilyCount==V24BackupSurveyDefinitionRecordV1.Kind.allCases.count,lifecycleEventStorage=="MUTATION_HISTORY_ONLY" else{throw BackupImportServiceError.unsupportedSchemaVersion}}}
enum V25GuidedSurveyImportBoundaryV1{static let persistentSchemaVersion=25;static let recordsSchemaVersion=24;static let durableFamilyCount=5;static let lifecycleHistoryStorage="MUTATION_HISTORY_ONLY";static func validate(persistent:Int,records:Int)throws{guard persistent==persistentSchemaVersion,records==recordsSchemaVersion,durableFamilyCount==V25BackupGuidedSurveyRecordV1.Kind.allCases.count,lifecycleHistoryStorage=="MUTATION_HISTORY_ONLY" else{throw BackupImportServiceError.unsupportedSchemaVersion}}}
enum V26AssetLocatorImportBoundaryV1 {
    static let persistentSchemaVersion = 26
    static let recordsSchemaVersion = 25
    static let durableFamilyCount = 2
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let cloneForkBindingPolicy = "HISTORIC_REBIND_SOURCE_SIGNATURE_INACTIVE"

    static func validate(persistent: Int, records: Int) throws {
        guard ((persistent == persistentSchemaVersion && records == recordsSchemaVersion)
                || (persistent == TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
                    && records == TemporalEvidencePersistenceEnrollmentV1.recordsSchemaVersion)),
              durableFamilyCount == V26BackupAssetLocatorRecordV1.Kind.allCases.count,
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              cloneForkBindingPolicy == "HISTORIC_REBIND_SOURCE_SIGNATURE_INACTIVE" else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

/// C51 retains the C28 schedule record family and adds calendar/override kinds
/// without changing old record bytes. Due/reminder projections and generation plans
/// are rebuilt locally from the imported immutable rows.
enum V27ScheduleImportBoundaryV1 {
    static let persistentSchemaVersion = 27
    static let recordsSchemaVersion = 26
    static let durableFamilyCount = 4
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let derivedProjectionStorage = "NONPERSISTENT_REBUILD"
    static let notificationStateIsTruth = false
    static let cloneForkSourceScheduleAutomaticallyActive = false

    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion,
              records == recordsSchemaVersion,
              durableFamilyCount == V27BackupScheduleRecordV1.Kind.allCases.count,
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              C51ScheduleBackupClosureV1.preservedV27RecordBytes,
              C51ScheduleBackupClosureV1.allDaysMigrationPreservesOccurrenceIdentityAndDate,
              C51ScheduleBackupClosureV1.embeddedCanonicalComponents.count == 6,
              !notificationStateIsTruth,
              !cloneForkSourceScheduleAutomaticallyActive else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

/// C29 accepts only the immutable plan families.  Frames travel as a
/// transport family but remain embedded in the durable revision row; preview
/// and component-registry values are rebuilt and never imported as truth.
enum V28PlanImportBoundaryV1 {
    static let persistentSchemaVersion = 28
    static let recordsSchemaVersion = 27
    static let durableFamilyCount = 4
    static let archiveFamilyCount = 5
    static let derivedProjectionStorage = "NONPERSISTENT_REBUILD"
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let cloneForkPlanAutomaticallyActive = false

    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion,
              records == recordsSchemaVersion,
              durableFamilyCount == PlanPersistenceEnrollmentV1.durableModelCount,
              archiveFamilyCount == V28BackupPlanRecordV1.Kind.allCases.count,
              PlanPersistenceEnrollmentV1.persistentSchemaVersion == persistentSchemaVersion,
              PlanPersistenceEnrollmentV1.recordsSchemaVersion == recordsSchemaVersion,
              PlanPersistenceEnrollmentV1.durableModelCount == 4,
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              !cloneForkPlanAutomaticallyActive else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

/// C37 archives only the two durable pose-event families. Current tips,
/// completed placement snapshots, editor state, and sensor/proposal values
/// are derived projections and must be rebuilt after import. Pose history is
/// mutation-history backed, so a restored event can never become live merely
/// because a projection happened to be present in the package.
enum V29PlacementPoseImportBoundaryV1 {
    static let persistentSchemaVersion = 29
    static let recordsSchemaVersion = 28
    static let durableFamilyCount = 2
    static let archiveFamilyCount = 2
    static let derivedProjectionStorage = "NONPERSISTENT_REBUILD"
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let sensorProposalPersistence = "NONPERSISTENT"
    static let cloneForkSourcePoseAutomaticallyActive = false

    static func validate(persistent: Int, records: Int) throws {
        guard persistent == persistentSchemaVersion,
              records == recordsSchemaVersion,
              durableFamilyCount == PlacementPosePersistenceEnrollmentV1.durableModelCount,
              archiveFamilyCount == V29BackupPlacementPoseRecordV1.Kind.allCases.count,
              PlacementPosePersistenceEnrollmentV1.persistentSchemaVersion == persistentSchemaVersion,
              PlacementPosePersistenceEnrollmentV1.recordsSchemaVersion == recordsSchemaVersion,
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              sensorProposalPersistence == "NONPERSISTENT",
              !cloneForkSourcePoseAutomaticallyActive else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

/// C30 imports only canonical context/link rows. Derived projections and any
/// provider-owned solar result are rebuilt from these immutable bytes.
enum V30EvidenceContextImportBoundaryV1 {
    static let persistentSchemaVersion = 30
    static let recordsSchemaVersion = 29
    static let durableFamilyCount = 2
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let inferredContextImport = false

    static func validate(persistent: Int, records: Int,
                         rows: [V30BackupEvidenceContextRecordV1] = []) throws {
        guard persistent == persistentSchemaVersion,
              records == recordsSchemaVersion,
              durableFamilyCount == V30BackupEvidenceContextRecordV1.Kind.allCases.count,
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              !inferredContextImport else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        _ = try EvidenceContextBackupRecordSetV1.decode(rows)
    }
}

/// C31 imports only the five canonical lighting roots.  Zone/group/luminaire
/// topology, observations, issues, measurement plans, and claim state travel
/// as one ordered canonical graph; display/search and any measurement result
/// not present in the archive are derived after restore.
enum V31LightingImportBoundaryV1 {
    static let persistentSchemaVersion = 31
    static let recordsSchemaVersion = 30
    static let durableFamilyCount = 5
    static let lifecycleHistoryStorage = "MUTATION_HISTORY_ONLY"
    static let derivedProjectionStorage = "NONPERSISTENT_REBUILD"
    static let externalMeasurementProvider = false
    static let licensedCriterionTextImported = false

    static func validate(
        persistent: Int,
        records: Int,
        rows: [V31BackupLightingRecordV1] = []
    ) throws {
        guard persistent == persistentSchemaVersion,
              records == recordsSchemaVersion,
              durableFamilyCount == V31BackupLightingRecordV1.Kind.allCases.count,
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              !externalMeasurementProvider,
              !licensedCriterionTextImported else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        _ = try LightingBackupRecordSetV1.decode(rows)
    }
}

/// C32 imports only durable acceptance receipts. Proposals and capability
/// scratch are intentionally absent and therefore cannot be revived by an
/// import, restore, clone, or fork.
enum V32AssistanceImportBoundaryV1 {
    static let persistentSchemaVersion = 32
    static let recordsSchemaVersion = 31
    static let durableFamilyCount = 1
    static let proposalImportDisposition = "EXCLUDED_NONPERSISTENT"
    static let rejectedCorpusImported = false

    static func validate(
        persistent: Int,
        records: Int,
        receipts: [V32BackupAssistanceAcceptanceRecordV1] = []
    ) throws {
        guard persistent == persistentSchemaVersion,
              records == recordsSchemaVersion,
              durableFamilyCount == AssistancePersistenceEnrollmentV1.durableModelCount,
              proposalImportDisposition == "EXCLUDED_NONPERSISTENT",
              !rejectedCorpusImported else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        guard Set(receipts.map(\.receiptID)).count == receipts.count,
              Set(receipts.map(\.mutationID)).count == receipts.count else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        for receipt in receipts { _ = try receipt.value() }
    }
}

// MARK: - C45 accepted-label import boundary
enum C45AcceptedLabelImportBoundaryV1 {
    static let durableFamilyCount = AssetLabelPersistenceEnrollmentV1.durableModelCount
    static let derivedProjectionBytesAreImportable = false
    static let historicCloneForkSnapshotsAreReprintActive = false
}

enum C46OperationalContactBoundary_02{static let recordsSchemaVersion=34;static let sourceBytesPersistent=false;static let platformOutcomesPersistent=false}
enum C47ActivityContractImportBoundaryV2 { static let persistentSchemaVersion=36;static let recordsSchemaVersion=35;static let canonicalFiveRowRecordsImportable=true;static let completedSnapshotUsesReleasedArchiveMember=true;static let conformanceReceiptsImportable=false }

enum C48PortableExchangeImportBoundaryV2 {
    static let member = PortableExchangeBackupMemberV2.relativePath
    static let sessionTruthIsNonpersistent = true
    static func validate(_ snapshot: PortableExchangeBackupSnapshotV2) throws {
        try snapshot.validate()
        guard member == "review-exchange/snapshot.json",
              sessionTruthIsNonpersistent else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

/// C53 imports the seven service-reliability source families and their
/// journal receipts through the existing backup envelope.  No derived metric,
/// capability byte, or parallel import store is part of the archive contract.
enum C53ServiceReliabilityBackupImportContractBoundaryV1 {
    static let persistentSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.targetPersistentSchemaVersion
    static let recordsSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.recordsSchemaVersion
    static let durableFamilyCount = AssetServiceReliabilityPersistenceEnrollmentV1.durableFamilies.count
    static let canonicalRowKinds = C53ServiceReliabilityBackupEnrollmentV1.canonicalRowKinds
    static let importsCanonicalRowsOnly = true
    static let importsMutationHistoryReceipts = true
    static let replacesAllSevenFamiliesInOneWriterTransaction = true
    static let preservesAppendOnlyIncidentAndExposureHistory = true
    static let preservesReliabilityIdentityEpochs = true
    static let derivedProjectionsAreRebuilt = true
    static let importsProjectionRows = false

    static func validate(
        persistent: Int,
        records: Int,
        backup: V4BackupRecordsV1,
        workspaceID: UUID? = nil
    ) throws {
        guard persistent == records + 1,
              records == backup.recordsSchemaVersion,
              (recordsSchemaVersion...C08ImportBulkBackupEnrollmentV1.recordsSchemaVersion)
                .contains(records),
              persistentSchemaVersion == 40,
              durableFamilyCount == 7,
              canonicalRowKinds == C53ServiceReliabilityBackupEnrollmentV1.canonicalRowKinds,
              importsCanonicalRowsOnly,
              importsMutationHistoryReceipts,
              replacesAllSevenFamiliesInOneWriterTransaction,
              preservesAppendOnlyIncidentAndExposureHistory,
              preservesReliabilityIdentityEpochs,
              derivedProjectionsAreRebuilt,
              !importsProjectionRows else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        do {
            try C53ServiceReliabilityBackupEnrollmentV1.validate(
                records: backup,
                workspaceID: workspaceID
            )
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validate(_ backup: V4BackupRecordsV1, workspaceID: UUID? = nil) throws {
        try validate(
            persistent: backup.recordsSchemaVersion + 1,
            records: backup.recordsSchemaVersion,
            backup: backup,
            workspaceID: workspaceID
        )
    }

    static func canonicalRows(
        from backup: V4BackupRecordsV1,
        workspaceID: UUID? = nil
    ) throws -> C53ServiceReliabilityBackupRowsV1 {
        try validate(backup, workspaceID: workspaceID)
        return try C53ServiceReliabilityBackupEnrollmentV1.canonicalRows(
            from: backup,
            workspaceID: workspaceID
        )
    }
}

enum C05RoundSessionBackupImportBoundaryV1 {
    static let persistentSchemaVersion = 45
    static let recordsSchemaVersion = 44
    static let durableFamilyCount = 1
    static let importsCanonicalHistoryOnly = true
    static let mutableItemTablesAreImported = false

    static func validate(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion <= recordsSchemaVersion,
              persistentSchemaVersion == recordsSchemaVersion + 1,
              durableFamilyCount == C05RoundSessionBackupEnrollmentV1.durableFamilyCount,
              importsCanonicalHistoryOnly,
              !mutableItemTablesAreImported else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        try C05RoundSessionBackupEnrollmentV1.validate(records)
    }
}

enum LightingNightWorkflowBackupImportBoundaryV1 {
    static let persistentSchemaVersion = 53
    static let recordsSchemaVersion = 52
    static func validate(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion <= recordsSchemaVersion,
              persistentSchemaVersion == recordsSchemaVersion + 1 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        try LightingNightWorkflowBackupEnrollmentV1.validate(records)
        try records.validateC18LightingNightWorkflowClosure()
    }
}

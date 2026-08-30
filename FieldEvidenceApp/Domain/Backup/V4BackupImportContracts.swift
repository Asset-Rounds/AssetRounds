import Foundation

enum C50IncumbentFileExchangeBackupImportBoundaryV1 {
    static let createsCanonicalFamily = false
    static let acceptsSourceBytesAsBackupMembers = false
    static let acceptsQuarantineAsBackupMembers = false
    static let acceptsSecurityBookmarks = false
    static let canonicalEffectsUseExistingImportOwners = true

    static func validate() -> Bool {
        C50IncumbentFileExchangeBackupBoundaryV1.validate()
            && !createsCanonicalFamily
            && !acceptsSourceBytesAsBackupMembers
            && !acceptsQuarantineAsBackupMembers
            && !acceptsSecurityBookmarks
            && canonicalEffectsUseExistingImportOwners
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
        guard records.recordsSchemaVersion == recordsSchemaVersion else {
            throw WorkResourceContractFailureV1.invalidValue
        }
        _ = try records.validateC49WorkResources()
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

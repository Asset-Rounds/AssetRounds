import Foundation

enum BackupCanonicalDecodingErrorV1: Error, Equatable {
    case invalidManifest
    case invalidRecords
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
        guard persistent == persistentSchemaVersion,
              records == recordsSchemaVersion,
              durableFamilyCount == V26BackupAssetLocatorRecordV1.Kind.allCases.count,
              lifecycleHistoryStorage == "MUTATION_HISTORY_ONLY",
              cloneForkBindingPolicy == "HISTORIC_REBIND_SOURCE_SIGNATURE_INACTIVE" else {
            throw BackupImportServiceError.unsupportedSchemaVersion
        }
    }
}

/// C28 schedule releases and occurrence history are the only additional
/// durable package families.  Due/reminder projections and generation plans
/// are rebuilt locally from the imported immutable rows.
enum V27ScheduleImportBoundaryV1 {
    static let persistentSchemaVersion = 27
    static let recordsSchemaVersion = 26
    static let durableFamilyCount = 2
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

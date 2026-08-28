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

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

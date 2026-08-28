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

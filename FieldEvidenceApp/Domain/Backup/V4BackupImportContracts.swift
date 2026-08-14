import Foundation

enum BackupCanonicalDecodingErrorV1: Error, Equatable {
    case invalidManifest
    case invalidRecords
}

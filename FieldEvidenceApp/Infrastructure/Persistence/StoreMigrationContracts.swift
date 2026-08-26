import CryptoKit
import Foundation

enum StoreMigrationPhaseV1: String, CaseIterable, Codable, Equatable, Sendable {
    case prepared
    case sourceCloned
    case v2WriteAuthorized
    case v2Validated
    case generationInstalled
    case pointerPublished
    case firstLaunchValidated
    case secondLaunchValidated

    fileprivate var ordinal: Int {
        switch self {
        case .prepared: return 0
        case .sourceCloned: return 1
        case .v2WriteAuthorized: return 2
        case .v2Validated: return 3
        case .generationInstalled: return 4
        case .pointerPublished: return 5
        case .firstLaunchValidated: return 6
        case .secondLaunchValidated: return 7
        }
    }

    func isAtLeast(_ other: StoreMigrationPhaseV1) -> Bool {
        ordinal >= other.ordinal
    }

    func isImmediateSuccessor(of other: StoreMigrationPhaseV1) -> Bool {
        ordinal == other.ordinal + 1
    }
}

enum StoreMigrationFaultBoundaryV1: String, CaseIterable, Codable, Equatable, Sendable {
    case beforePreparedJournalWrite
    case afterPreparedJournalWrite
    case beforeSourceClone
    case afterSourceClone
    case beforeV2WriteAuthorization
    case afterV2WriteAuthorization
    case beforeV2Validation
    case afterV2Validation
    case beforeGenerationInstall
    case afterGenerationInstall
    case beforePointerPublication
    case afterPointerPublication
    case beforeFirstLaunchValidation
    case afterFirstLaunchValidation
    case beforeSecondLaunchValidation
    case afterSecondLaunchValidation
    case beforeJournalRemoval
    case afterJournalRemoval
}

enum StoreMigrationMaintenanceReasonV1: String, CaseIterable, Codable, Equatable, Sendable {
    case futureVersion = "future_version"
    case invalidJournal = "invalid_journal"
    case invalidPointer = "invalid_pointer"
    case sourceUnavailable = "source_unavailable"
    case sourceMismatch = "source_mismatch"
    case targetUnavailable = "target_unavailable"
    case targetMismatch = "target_mismatch"
    case protectedDataUnavailable = "protected_data_unavailable"
    case insufficientStorage = "insufficient_storage"
    case forwardFixRequired = "forward_fix_required"
}

enum StoreMigrationFailure: Error, Equatable, Sendable {
    case invalidContract
    case invalidPhaseTransition
    case invalidDigest
    case invalidIdentity
    case invalidPath
    case canonicalEncodingFailed
    case canonicalDecodingFailed
    case digestMismatch
    case injectedFault(StoreMigrationFaultBoundaryV1)
    case maintenanceRequired(StoreMigrationMaintenanceReasonV1)
}

struct StoreGenerationFileDigestV1: Codable, Equatable, Sendable {
    let relativePath: String
    let byteCount: Int
    let sha256: String
    let kind: OwnedFileKindV1

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case byteCount
        case sha256
        case kind
    }

    init(
        relativePath: String,
        byteCount: Int,
        sha256: String,
        kind: OwnedFileKindV1
    ) throws {
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.kind = kind
        try validate()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try values.decode(String.self, forKey: .relativePath)
        byteCount = try values.decode(Int.self, forKey: .byteCount)
        sha256 = try values.decode(String.self, forKey: .sha256)
        let rawKind = try values.decode(String.self, forKey: .kind)
        guard let decodedKind = OwnedFileKindV1(rawValue: rawKind) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: values,
                debugDescription: "Unknown owned-file kind."
            )
        }
        kind = decodedKind
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(relativePath, forKey: .relativePath)
        try values.encode(byteCount, forKey: .byteCount)
        try values.encode(sha256, forKey: .sha256)
        try values.encode(kind.rawValue, forKey: .kind)
    }

    func validate() throws {
        guard Self.isCanonicalRelativePath(relativePath) else {
            throw StoreMigrationFailure.invalidPath
        }
        guard byteCount >= 0,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha256) else {
            throw StoreMigrationFailure.invalidDigest
        }
        let disposition = ProtectedFilePolicyV1.disposition(for: kind)
        guard !disposition.expectsDirectory else {
            throw StoreMigrationFailure.invalidContract
        }
    }

    fileprivate static func isCanonicalRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\") else {
            return false
        }
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

struct StoreGenerationManifestV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generationID: UUID
    let predecessorGenerationID: UUID
    let migrationID: UUID
    let storeSchemaRelease: PersistentSchemaReleaseV1
    /// V1 source manifests deliberately omit semantic identity. The immutable
    /// physical source is first durably bound to the prepared journal, then a
    /// read-only semantic export is taken from its copy-on-write clone and
    /// frozen in `StoreMigrationJournalV1.sourceSemanticDigest`. V2 manifests
    /// always carry the validated semantic digest.
    let semanticSHA256: String?
    let frozenIdentityDigest: String
    let files: [StoreGenerationFileDigestV1]

    init(
        schemaVersion: Int = 1,
        generationID: UUID,
        predecessorGenerationID: UUID,
        migrationID: UUID,
        storeSchemaRelease: PersistentSchemaReleaseV1,
        semanticSHA256: String?,
        frozenIdentityDigest: String,
        files: [StoreGenerationFileDigestV1]
    ) throws {
        self.schemaVersion = schemaVersion
        self.generationID = generationID
        self.predecessorGenerationID = predecessorGenerationID
        self.migrationID = migrationID
        self.storeSchemaRelease = storeSchemaRelease
        self.semanticSHA256 = semanticSHA256
        self.frozenIdentityDigest = frozenIdentityDigest
        self.files = files
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 1,
              generationID != predecessorGenerationID else {
            throw StoreMigrationFailure.invalidContract
        }
        guard semanticSHA256.map(
            StoreMigrationCanonicalJSONV1.isLowercaseSHA256
        ) ?? true,
              (storeSchemaRelease == .v1
                ? semanticSHA256 == nil
                : semanticSHA256 != nil),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
                  frozenIdentityDigest
              ) else {
            throw StoreMigrationFailure.invalidDigest
        }
        try files.forEach { try $0.validate() }
        let paths = files.map(\.relativePath)
        guard paths == paths.sorted(),
              Set(paths).count == paths.count,
              paths.contains("model.sqlite"),
              files.allSatisfy({ file in
                switch (file.relativePath, file.kind) {
                case ("model.sqlite", .database),
                     ("model.sqlite-wal", .databaseWAL),
                     ("model.sqlite-shm", .databaseSHM):
                    return true
                default:
                    return false
                }
              }) else {
            throw StoreMigrationFailure.invalidContract
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try StoreMigrationCanonicalJSONV1.digest(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
    }
}

struct CurrentGenerationPointerV2: Codable, Equatable, Sendable {
    let generationID: String
    let generationManifestSHA256: String
    let storeSchemaVersion: Int
    let schemaVersion: Int

    init(
        generationID: UUID,
        generationManifestSHA256: String,
        storeSchemaVersion: Int = 2,
        schemaVersion: Int = 2
    ) throws {
        self.generationID = generationID.uuidString.lowercased()
        self.generationManifestSHA256 = generationManifestSHA256
        self.storeSchemaVersion = storeSchemaVersion
        self.schemaVersion = schemaVersion
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 2,
              storeSchemaVersion == 2,
              let identifier = UUID(uuidString: generationID),
              identifier.uuidString.lowercased() == generationID else {
            throw StoreMigrationFailure.invalidContract
        }
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
            generationManifestSHA256
        ) else {
            throw StoreMigrationFailure.invalidDigest
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try StoreMigrationCanonicalJSONV1.digest(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
    }
}

struct StoreMigrationJournalV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let migrationID: UUID
    let sourceGenerationID: UUID
    let targetGenerationID: UUID
    let sourceRelease: PersistentSchemaReleaseV1
    let targetRelease: PersistentSchemaReleaseV1
    let sourcePointerDigest: String
    let sourceTreeDigest: String
    let sourceManifestDigest: String
    let sourceSemanticDigest: String?
    let targetManifestDigest: String?
    let targetSemanticDigest: String?
    let frozenIdentityDigest: String
    let expectedPointerDigest: String
    let desiredPointerDigest: String?
    let originatingProcessID: UUID
    let publicationProcessID: UUID?
    let firstValidationProcessID: UUID?
    let secondValidationProcessID: UUID?
    let phase: StoreMigrationPhaseV1
    let targetWritePossible: Bool
    let pointerPublicationAttempted: Bool

    init(
        schemaVersion: Int = 1,
        migrationID: UUID,
        sourceGenerationID: UUID,
        targetGenerationID: UUID,
        sourceRelease: PersistentSchemaReleaseV1,
        targetRelease: PersistentSchemaReleaseV1,
        sourcePointerDigest: String,
        sourceTreeDigest: String,
        sourceManifestDigest: String,
        sourceSemanticDigest: String? = nil,
        targetManifestDigest: String? = nil,
        targetSemanticDigest: String? = nil,
        frozenIdentityDigest: String,
        expectedPointerDigest: String,
        desiredPointerDigest: String? = nil,
        originatingProcessID: UUID,
        publicationProcessID: UUID? = nil,
        firstValidationProcessID: UUID? = nil,
        secondValidationProcessID: UUID? = nil,
        phase: StoreMigrationPhaseV1,
        targetWritePossible: Bool,
        pointerPublicationAttempted: Bool
    ) throws {
        self.schemaVersion = schemaVersion
        self.migrationID = migrationID
        self.sourceGenerationID = sourceGenerationID
        self.targetGenerationID = targetGenerationID
        self.sourceRelease = sourceRelease
        self.targetRelease = targetRelease
        self.sourcePointerDigest = sourcePointerDigest
        self.sourceTreeDigest = sourceTreeDigest
        self.sourceManifestDigest = sourceManifestDigest
        self.sourceSemanticDigest = sourceSemanticDigest
        self.targetManifestDigest = targetManifestDigest
        self.targetSemanticDigest = targetSemanticDigest
        self.frozenIdentityDigest = frozenIdentityDigest
        self.expectedPointerDigest = expectedPointerDigest
        self.desiredPointerDigest = desiredPointerDigest
        self.originatingProcessID = originatingProcessID
        self.publicationProcessID = publicationProcessID
        self.firstValidationProcessID = firstValidationProcessID
        self.secondValidationProcessID = secondValidationProcessID
        self.phase = phase
        self.targetWritePossible = targetWritePossible
        self.pointerPublicationAttempted = pointerPublicationAttempted
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 1,
              migrationID != sourceGenerationID,
              migrationID != targetGenerationID,
              sourceGenerationID != targetGenerationID,
              sourceRelease == .v1,
              targetRelease == .v2 else {
            throw StoreMigrationFailure.invalidContract
        }

        let requiredDigests = [
            sourcePointerDigest,
            sourceTreeDigest,
            sourceManifestDigest,
            frozenIdentityDigest,
            expectedPointerDigest,
        ]
        guard requiredDigests.allSatisfy(
            StoreMigrationCanonicalJSONV1.isLowercaseSHA256
        ), sourcePointerDigest == expectedPointerDigest,
           sourceSemanticDigest.map(
            StoreMigrationCanonicalJSONV1.isLowercaseSHA256
        ) ?? true,
           targetManifestDigest.map(
            StoreMigrationCanonicalJSONV1.isLowercaseSHA256
        ) ?? true,
           targetSemanticDigest.map(
            StoreMigrationCanonicalJSONV1.isLowercaseSHA256
           ) ?? true,
           desiredPointerDigest.map(
            StoreMigrationCanonicalJSONV1.isLowercaseSHA256
           ) ?? true else {
            throw StoreMigrationFailure.invalidDigest
        }

        let sourceSemanticDigestRequired = phase.isAtLeast(.sourceCloned)
        guard (sourceSemanticDigest != nil) == sourceSemanticDigestRequired else {
            throw StoreMigrationFailure.invalidContract
        }

        let writeMustBePossible = phase.isAtLeast(.v2WriteAuthorized)
        guard targetWritePossible == writeMustBePossible else {
            throw StoreMigrationFailure.invalidContract
        }

        let targetDigestsRequired = phase.isAtLeast(.v2Validated)
        guard (targetManifestDigest != nil) == targetDigestsRequired,
              (targetSemanticDigest != nil) == targetDigestsRequired,
              (desiredPointerDigest != nil) == targetDigestsRequired else {
            throw StoreMigrationFailure.invalidContract
        }

        if phase.isAtLeast(.pointerPublished) {
            guard pointerPublicationAttempted,
                  publicationProcessID != nil else {
                throw StoreMigrationFailure.invalidContract
            }
        } else if phase.ordinal < StoreMigrationPhaseV1.generationInstalled.ordinal {
            guard !pointerPublicationAttempted,
                  publicationProcessID == nil else {
                throw StoreMigrationFailure.invalidContract
            }
        } else {
            guard pointerPublicationAttempted == (publicationProcessID != nil) else {
                throw StoreMigrationFailure.invalidContract
            }
        }

        if phase.isAtLeast(.firstLaunchValidated) {
            guard firstValidationProcessID != nil else {
                throw StoreMigrationFailure.invalidContract
            }
        } else {
            guard firstValidationProcessID == nil else {
                throw StoreMigrationFailure.invalidContract
            }
        }

        if phase == .secondLaunchValidated {
            guard let firstValidationProcessID,
                  let publicationProcessID,
                  let secondValidationProcessID,
                  firstValidationProcessID != secondValidationProcessID,
                  publicationProcessID != secondValidationProcessID,
                  originatingProcessID != secondValidationProcessID else {
                throw StoreMigrationFailure.invalidIdentity
            }
        } else {
            guard secondValidationProcessID == nil else {
                throw StoreMigrationFailure.invalidContract
            }
        }
    }

    func validateReplacement(of previous: StoreMigrationJournalV1) throws {
        try previous.validate()
        try validate()
        guard schemaVersion == previous.schemaVersion,
              migrationID == previous.migrationID,
              sourceGenerationID == previous.sourceGenerationID,
              targetGenerationID == previous.targetGenerationID,
              sourceRelease == previous.sourceRelease,
              targetRelease == previous.targetRelease,
              sourcePointerDigest == previous.sourcePointerDigest,
              sourceTreeDigest == previous.sourceTreeDigest,
              sourceManifestDigest == previous.sourceManifestDigest,
              frozenIdentityDigest == previous.frozenIdentityDigest,
              expectedPointerDigest == previous.expectedPointerDigest,
              originatingProcessID == previous.originatingProcessID else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }

        if phase == previous.phase {
            guard phase == .generationInstalled,
                  !previous.pointerPublicationAttempted,
                  previous.publicationProcessID == nil,
                  pointerPublicationAttempted,
                  publicationProcessID != nil,
                  sourceSemanticDigest == previous.sourceSemanticDigest,
                  targetManifestDigest == previous.targetManifestDigest,
                  targetSemanticDigest == previous.targetSemanticDigest,
                  desiredPointerDigest == previous.desiredPointerDigest,
                  firstValidationProcessID == nil,
                  secondValidationProcessID == nil else {
                throw StoreMigrationFailure.invalidPhaseTransition
            }
            return
        }

        guard phase.isImmediateSuccessor(of: previous.phase),
              (phase == .pointerPublished
                ? previous.phase == .generationInstalled
                    && previous.pointerPublicationAttempted
                    && previous.publicationProcessID == publicationProcessID
                : true),
              (previous.phase == .prepared && phase == .sourceCloned
                ? previous.sourceSemanticDigest == nil
                    && sourceSemanticDigest != nil
                : sourceSemanticDigest == previous.sourceSemanticDigest),
              !previous.targetWritePossible || targetWritePossible,
              !previous.pointerPublicationAttempted
                || pointerPublicationAttempted,
              previous.targetManifestDigest.map {
                $0 == targetManifestDigest
              } ?? true,
              previous.targetSemanticDigest.map {
                $0 == targetSemanticDigest
              } ?? true,
              previous.desiredPointerDigest.map {
                $0 == desiredPointerDigest
              } ?? true,
              previous.publicationProcessID.map {
                $0 == publicationProcessID
              } ?? true,
              previous.firstValidationProcessID.map {
                $0 == firstValidationProcessID
              } ?? true,
              previous.secondValidationProcessID.map {
                $0 == secondValidationProcessID
              } ?? true else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
    }

    func validateImmediateSuccessor(of previous: StoreMigrationJournalV1) throws {
        guard phase.isImmediateSuccessor(of: previous.phase) else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        try validateReplacement(of: previous)
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try StoreMigrationCanonicalJSONV1.digest(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
    }
}

enum StoreMigrationCanonicalJSONV1 {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(value)
        } catch {
            throw StoreMigrationFailure.canonicalEncodingFailed
        }
    }

    static func decodeCanonical<Value: Codable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        do {
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw StoreMigrationFailure.canonicalDecodingFailed
            }
            return value
        } catch let failure as StoreMigrationFailure {
            throw failure
        } catch {
            throw StoreMigrationFailure.canonicalDecodingFailed
        }
    }

    static func decodeCanonicalContract<Value: Codable>(
        _ type: Value.Type,
        from data: Data,
        validate: (Value) throws -> Void
    ) throws -> Value {
        let value = try decodeCanonical(type, from: data)
        try validate(value)
        return value
    }

    static func digest<Value: Encodable>(_ value: Value) throws -> String {
        sha256(try encode(value))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

@MainActor
struct StoreMigrationIdentitySourceV1 {
    private static let liveProcessID = UUID()

    let makeMigrationID: () -> UUID
    let makeGenerationID: () -> UUID
    let makeProcessID: () -> UUID

    init(
        makeMigrationID: @escaping () -> UUID,
        makeGenerationID: @escaping () -> UUID,
        makeProcessID: @escaping () -> UUID
    ) {
        self.makeMigrationID = makeMigrationID
        self.makeGenerationID = makeGenerationID
        self.makeProcessID = makeProcessID
    }

    static var live: StoreMigrationIdentitySourceV1 {
        StoreMigrationIdentitySourceV1(
            makeMigrationID: UUID.init,
            makeGenerationID: UUID.init,
            makeProcessID: { Self.liveProcessID }
        )
    }
}

#if DEBUG
@MainActor
final class StoreMigrationFailureInjection {
    private var pending: StoreMigrationFaultBoundaryV1?

    init(failOnceAt boundary: StoreMigrationFaultBoundaryV1) {
        pending = boundary
    }

    func removeFailure() {
        pending = nil
    }

    func reach(_ boundary: StoreMigrationFaultBoundaryV1) throws {
        guard pending == boundary else { return }
        pending = nil
        throw StoreMigrationFailure.injectedFault(boundary)
    }
}
#endif

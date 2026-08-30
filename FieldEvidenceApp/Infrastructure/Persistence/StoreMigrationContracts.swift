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

enum ObservationAndTimeMigrationDispositionV1: String, Codable, Equatable,
    Sendable {
    case noLegacyValues = "NO_LEGACY_VALUES"
    case migratedLegacyValues = "MIGRATED_LEGACY_VALUES"
    case alreadyCurrent = "ALREADY_CURRENT"
    case quarantinedUnsupportedBytes = "QUARANTINED_UNSUPPORTED_BYTES"
}

struct ObservationAndTimeMigrationReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let disposition: ObservationAndTimeMigrationDispositionV1
    let sourceSHA256: String
    let resultSHA256: String
    let legacyColumnsPreserved: Bool
    let inventedDirectObservation: Bool
    let requiresForwardRepair: Bool

    init(
        disposition: ObservationAndTimeMigrationDispositionV1,
        sourceSHA256: String,
        resultSHA256: String,
        requiresForwardRepair: Bool
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.disposition = disposition
        self.sourceSHA256 = sourceSHA256
        self.resultSHA256 = resultSHA256
        legacyColumnsPreserved = true
        inventedDirectObservation = false
        self.requiresForwardRepair = requiresForwardRepair
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sourceSHA256),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(resultSHA256),
              legacyColumnsPreserved,
              !inventedDirectObservation,
              requiresForwardRepair
                == (disposition == .quarantinedUnsupportedBytes) else {
            throw StoreMigrationFailure.invalidContract
        }
    }
}

struct ObservationAndTimeMigrationResultV1: Equatable, Sendable {
    let observationBasisData: Data?
    let temporalContextData: Data?
    let disposition: ObservationAndTimeMigrationDispositionV1
    let receipt: ObservationAndTimeMigrationReceiptV1

    var requiresForwardRepair: Bool {
        receipt.requiresForwardRepair
    }
}

/// Pure deterministic V4-to-V5 value migration. Existing current bytes win;
/// malformed or future bytes are returned unchanged with a quarantine receipt
/// so callers can fail the generation migration without damaging V4.
enum ObservationAndTimeMigrationV1 {
    private struct DigestInputV1: Codable {
        let existingObservationBasisData: Data?
        let existingTemporalContextData: Data?
        let couldNotVerifyKey: String?
        let couldNotVerifyDisplaySnapshot: String?
        let couldNotVerifyRegistryVersion: String?
        let observedAtUTC: Date?
        let recordedAtUTC: Date
        let timeZoneID: String?
        let utcOffsetMinutes: Int?
        let localDate: String?
        let localTime: String?
    }

    private struct DigestOutputV1: Codable {
        let observationBasisData: Data?
        let temporalContextData: Data?
        let disposition: ObservationAndTimeMigrationDispositionV1
    }

    static func migrate(
        existingObservationBasisData: Data?,
        existingTemporalContextData: Data?,
        couldNotVerifyKey: String?,
        couldNotVerifyDisplaySnapshot: String?,
        couldNotVerifyRegistryVersion: String?,
        observedAtUTC: Date?,
        recordedAtUTC: Date,
        timeZoneID: String?,
        utcOffsetMinutes: Int?,
        localDate: String?,
        localTime: String?
    ) throws -> ObservationAndTimeMigrationResultV1 {
        let input = DigestInputV1(
            existingObservationBasisData: existingObservationBasisData,
            existingTemporalContextData: existingTemporalContextData,
            couldNotVerifyKey: couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: couldNotVerifyRegistryVersion,
            observedAtUTC: observedAtUTC,
            recordedAtUTC: recordedAtUTC,
            timeZoneID: timeZoneID,
            utcOffsetMinutes: utcOffsetMinutes,
            localDate: localDate,
            localTime: localTime
        )
        let sourceSHA256 = try StoreMigrationCanonicalJSONV1.digest(input)

        do {
            if let existingObservationBasisData {
                _ = try ObservationAndTimeCodecV1.decodeObservationBasis(
                    existingObservationBasisData
                )
            }
            if let existingTemporalContextData {
                _ = try ObservationAndTimeCodecV1.decodeTemporalContext(
                    existingTemporalContextData
                )
            }
        } catch {
            return try result(
                observationBasisData: existingObservationBasisData,
                temporalContextData: existingTemporalContextData,
                disposition: .quarantinedUnsupportedBytes,
                sourceSHA256: sourceSHA256
            )
        }

        var basisData = existingObservationBasisData
        var timeData = existingTemporalContextData
        do {
            if basisData == nil,
               let basis = try ObservationAndTimeLegacyMigrationV1
                .observationBasis(
                    couldNotVerifyKey: couldNotVerifyKey,
                    displaySnapshot: couldNotVerifyDisplaySnapshot,
                    registryVersion: couldNotVerifyRegistryVersion
                ) {
                basisData = try ObservationAndTimeCodecV1.encode(basis)
            }
            if timeData == nil,
               let temporal = try ObservationAndTimeLegacyMigrationV1
                .temporalContext(
                    observedAtUTC: observedAtUTC,
                    recordedAtUTC: recordedAtUTC,
                    timeZoneID: timeZoneID,
                    utcOffsetMinutes: utcOffsetMinutes,
                    localDate: localDate,
                    localTime: localTime
                ) {
                timeData = try ObservationAndTimeCodecV1.encode(temporal)
            }
        } catch {
            return try result(
                observationBasisData: existingObservationBasisData,
                temporalContextData: existingTemporalContextData,
                disposition: .quarantinedUnsupportedBytes,
                sourceSHA256: sourceSHA256
            )
        }

        let disposition: ObservationAndTimeMigrationDispositionV1
        if basisData == nil, timeData == nil {
            disposition = .noLegacyValues
        } else if basisData == existingObservationBasisData,
                  timeData == existingTemporalContextData {
            disposition = .alreadyCurrent
        } else {
            disposition = .migratedLegacyValues
        }
        return try result(
            observationBasisData: basisData,
            temporalContextData: timeData,
            disposition: disposition,
            sourceSHA256: sourceSHA256
        )
    }

    private static func result(
        observationBasisData: Data?,
        temporalContextData: Data?,
        disposition: ObservationAndTimeMigrationDispositionV1,
        sourceSHA256: String
    ) throws -> ObservationAndTimeMigrationResultV1 {
        let output = DigestOutputV1(
            observationBasisData: observationBasisData,
            temporalContextData: temporalContextData,
            disposition: disposition
        )
        let receipt = try ObservationAndTimeMigrationReceiptV1(
            disposition: disposition,
            sourceSHA256: sourceSHA256,
            resultSHA256: try StoreMigrationCanonicalJSONV1.digest(output),
            requiresForwardRepair: disposition == .quarantinedUnsupportedBytes
        )
        return ObservationAndTimeMigrationResultV1(
            observationBasisData: observationBasisData,
            temporalContextData: temporalContextData,
            disposition: disposition,
            receipt: receipt
        )
    }
}

enum ObservationAndTimeStoreMigrationV1 {
    static func row(for record: WorkflowRecord) throws -> ObservationAndTimeRow {
        let result = try ObservationAndTimeMigrationV1.migrate(
            existingObservationBasisData: nil,
            existingTemporalContextData: nil,
            couldNotVerifyKey: record.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
            observedAtUTC: record.observedAtUTC,
            recordedAtUTC: record.completedAt ?? record.startedAt,
            timeZoneID: record.timeZoneID,
            utcOffsetMinutes: record.utcOffsetMinutes,
            localDate: record.localDate,
            localTime: record.localTime
        )
        guard !result.requiresForwardRepair else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        guard let basis = result.observationBasisData,
              let temporal = result.temporalContextData else {
            throw StoreMigrationFailure.invalidContract
        }
        return try ObservationAndTimeRow(
            recordID: record.id,
            observationBasisV1Data: basis,
            temporalContextV1Data: temporal
        )
    }
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

struct CurrentGenerationPointerV3: Codable, Equatable, Sendable {
    static let maximumKnownReplicaCount = 64

    let generationID: String
    let generationManifestSHA256: String
    let knownReplicaIDs: [String]
    let replicaID: String
    let storeSchemaVersion: Int
    let workspaceID: String
    let schemaVersion: Int

    init(
        generationID: UUID,
        generationManifestSHA256: String,
        workspaceID: WorkspaceID,
        replicaID: ReplicaID,
        knownReplicaIDs: Set<ReplicaID> = [],
        storeSchemaVersion: Int = 2,
        schemaVersion: Int = 3
    ) throws {
        var history = knownReplicaIDs
        history.insert(replicaID)
        self.generationID = generationID.uuidString.lowercased()
        self.generationManifestSHA256 = generationManifestSHA256
        self.knownReplicaIDs = history
            .map { $0.rawValue.uuidString.lowercased() }
            .sorted()
        self.replicaID = replicaID.rawValue.uuidString.lowercased()
        self.storeSchemaVersion = storeSchemaVersion
        self.workspaceID = workspaceID.rawValue.uuidString.lowercased()
        self.schemaVersion = schemaVersion
        try validate()
    }

    func validate() throws {
        let zero = "00000000-0000-0000-0000-000000000000"
        guard schemaVersion == 3,
              (2...26).contains(storeSchemaVersion),
              Self.canonicalUUID(generationID) != nil,
              Self.canonicalUUID(workspaceID) != nil,
              Self.canonicalUUID(replicaID) != nil,
              generationID != workspaceID,
              generationID != replicaID,
              workspaceID != replicaID,
              generationID != zero,
              workspaceID != zero,
              replicaID != zero,
              !knownReplicaIDs.isEmpty,
              knownReplicaIDs.count <= Self.maximumKnownReplicaCount,
              knownReplicaIDs == knownReplicaIDs.sorted(),
              Set(knownReplicaIDs).count == knownReplicaIDs.count,
              knownReplicaIDs.contains(replicaID),
              knownReplicaIDs.allSatisfy({
                  $0 != zero && Self.canonicalUUID($0) != nil
              }) else {
            throw StoreMigrationFailure.invalidContract
        }
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
            generationManifestSHA256
        ) else {
            throw StoreMigrationFailure.invalidDigest
        }
    }

    func identity() throws -> WorkspaceReplicaIdentityV1 {
        try validate()
        guard let workspaceUUID = Self.canonicalUUID(workspaceID),
              let replicaUUID = Self.canonicalUUID(replicaID) else {
            throw StoreMigrationFailure.invalidContract
        }
        return try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            replicaID: ReplicaID(rawValue: replicaUUID)
        )
    }

    func knownReplicaIdentitySet() throws -> Set<ReplicaID> {
        try validate()
        let values = knownReplicaIDs.compactMap(Self.canonicalUUID)
        guard values.count == knownReplicaIDs.count else {
            throw StoreMigrationFailure.invalidContract
        }
        return Set(values.map { ReplicaID(rawValue: $0) })
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

    private static func canonicalUUID(_ value: String) -> UUID? {
        guard let identifier = UUID(uuidString: value),
              identifier.uuidString.lowercased() == value else {
            return nil
        }
        return identifier
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
        guard C50IncumbentFileExchangeMigrationBoundaryV1.validate() else {
            throw StoreMigrationFailure.invalidContract
        }
        guard schemaVersion == 1,
              migrationID != targetGenerationID,
              sourceGenerationID != targetGenerationID,
              (sourceRelease == .v2 || migrationID != sourceGenerationID),
              ((sourceRelease == .v1 && targetRelease == .v2)
                || (sourceRelease == .v2 && targetRelease == .v3)
                || (sourceRelease == .v3 && targetRelease == .v4)
                || (sourceRelease == .v4 && targetRelease == .v5)
                || (sourceRelease == .v5 && targetRelease == .v6)
                || (sourceRelease == .v6 && targetRelease == .v7)
                || (sourceRelease == .v7 && targetRelease == .v8)
                || (sourceRelease == .v8 && targetRelease == .v9)
                || (sourceRelease == .v9 && targetRelease == .v10)
                || (sourceRelease == .v10 && targetRelease == .v11)
                || (sourceRelease == .v11 && targetRelease == .v12)
                || (sourceRelease == .v12 && targetRelease == .v13)
                || (sourceRelease == .v13 && targetRelease == .v14)
                || (sourceRelease == .v14 && targetRelease == .v15)
                || (sourceRelease == .v15 && targetRelease == .v16)
                || (sourceRelease == .v16 && targetRelease == .v17)
                || (sourceRelease == .v17 && targetRelease == .v18)
                || (sourceRelease == .v18 && targetRelease == .v19)
                || (sourceRelease == .v19 && targetRelease == .v20)
                || (sourceRelease == .v20 && targetRelease == .v21)
                || (sourceRelease == .v21 && targetRelease == .v22)
                || (sourceRelease == .v22 && targetRelease == .v23)
                || (sourceRelease == .v23 && targetRelease == .v24)
                || (sourceRelease == .v24 && targetRelease == .v25)
                || (sourceRelease == .v25 && targetRelease == .v26)
                || (sourceRelease == .v26 && targetRelease == .v27)
                || (sourceRelease == .v27 && targetRelease == .v28)
                || (sourceRelease == .v28 && targetRelease == .v29)
                || (sourceRelease == .v29 && targetRelease == .v30)
                || (sourceRelease == .v30 && targetRelease == .v31)
                || (sourceRelease == .v31 && targetRelease == .v32)
                || (sourceRelease == .v32 && targetRelease == .v33)) else {
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

enum GenerationLeaseRoleV1: String, Codable, CaseIterable, Equatable, Sendable {
    case reader = "READER"
    case writer = "WRITER"
}

private enum GenerationContractCanonicalOrderV1 {
    static func epoch(
        _ lhs: GenerationEpochV1,
        _ rhs: GenerationEpochV1
    ) -> Bool {
        let left = uuid(lhs.generationID)
        let right = uuid(rhs.generationID)
        if left != right { return left < right }
        return lhs.generationManifestSHA256 < rhs.generationManifestSHA256
    }

    static func uuid(_ lhs: UUID, _ rhs: UUID) -> Bool {
        uuid(lhs) < uuid(rhs)
    }

    private static func uuid(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

enum GenerationLeaseRegistryFailureV1: Error, Equatable, Sendable {
    case invalidContract
    case invalidPath
    case invalidIdentity
    case corruptRegistry
    case registryLimitExceeded
    case duplicateLease
    case leaseNotActive
    case wrongLeaseRole
    case staleGeneration
    case uncertainOwner
    case protectedDataUnavailable
}

struct GenerationEpochV1: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generationID: UUID
    let generationManifestSHA256: String

    init(
        generationID: UUID,
        generationManifestSHA256: String,
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.generationID = generationID
        self.generationManifestSHA256 = generationManifestSHA256
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              generationID != Self.zeroUUID,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
                  generationManifestSHA256
              ) else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(try canonicalData())
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
    }

    static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

struct GenerationLeaseTokenV1: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let leaseID: UUID
    let ownerID: UUID
    let epoch: GenerationEpochV1
    let role: GenerationLeaseRoleV1
    let acquiredAt: Date

    init(
        leaseID: UUID,
        ownerID: UUID,
        epoch: GenerationEpochV1,
        role: GenerationLeaseRoleV1,
        acquiredAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.leaseID = leaseID
        self.ownerID = ownerID
        self.epoch = epoch
        self.role = role
        self.acquiredAt = acquiredAt
        try validate()
    }

    func validate() throws {
        try epoch.validate()
        guard schemaVersion == Self.currentSchemaVersion,
              leaseID != GenerationEpochV1.zeroUUID,
              ownerID != GenerationEpochV1.zeroUUID,
              acquiredAt.timeIntervalSinceReferenceDate.isFinite else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(try canonicalData())
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
    }
}

struct GenerationPrunePolicyV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let productionRetainedInactiveAcceptedGenerationCount = 2

    let schemaVersion: Int
    let retainedInactiveAcceptedGenerationCount: Int
    let pruningEnabled: Bool

    init(
        retainedInactiveAcceptedGenerationCount: Int,
        pruningEnabled: Bool = true,
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.retainedInactiveAcceptedGenerationCount =
            retainedInactiveAcceptedGenerationCount
        self.pruningEnabled = pruningEnabled
        try validate()
    }

    static var production: GenerationPrunePolicyV1 {
        // All arguments are compile-time-valid closed policy values.
        try! GenerationPrunePolicyV1(
            retainedInactiveAcceptedGenerationCount:
                productionRetainedInactiveAcceptedGenerationCount
        )
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              retainedInactiveAcceptedGenerationCount >= 0,
              retainedInactiveAcceptedGenerationCount <= 64 else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
    }
}

enum GenerationPruneDispositionV1: String, Codable, Equatable, Sendable {
    case pruned = "PRUNED"
    case noEligibleGenerations = "NO_ELIGIBLE_GENERATIONS"
    case disabledRetainAll = "DISABLED_RETAIN_ALL"
    case uncertainRetainAll = "UNCERTAIN_RETAIN_ALL"
}

struct GenerationPruneReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let currentEpoch: GenerationEpochV1
    let retainedEpochs: [GenerationEpochV1]
    let prunedEpochs: [GenerationEpochV1]
    let activeRetainedEpochs: [GenerationEpochV1]
    let uncertainRetainedGenerationIDs: [UUID]
    let ownerLivenessUncertain: Bool
    let inventoryBeforeSHA256: String
    let inventoryAfterSHA256: String
    let disposition: GenerationPruneDispositionV1

    init(
        operationID: UUID,
        currentEpoch: GenerationEpochV1,
        retainedEpochs: [GenerationEpochV1],
        prunedEpochs: [GenerationEpochV1],
        activeRetainedEpochs: [GenerationEpochV1],
        uncertainRetainedGenerationIDs: [UUID],
        ownerLivenessUncertain: Bool = false,
        inventoryBeforeSHA256: String,
        inventoryAfterSHA256: String,
        disposition: GenerationPruneDispositionV1,
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.currentEpoch = currentEpoch
        self.retainedEpochs = retainedEpochs
        self.prunedEpochs = prunedEpochs
        self.activeRetainedEpochs = activeRetainedEpochs
        self.uncertainRetainedGenerationIDs = uncertainRetainedGenerationIDs
        self.ownerLivenessUncertain = ownerLivenessUncertain
        self.inventoryBeforeSHA256 = inventoryBeforeSHA256
        self.inventoryAfterSHA256 = inventoryAfterSHA256
        self.disposition = disposition
        try validate()
    }

    func validate() throws {
        try currentEpoch.validate()
        try (retainedEpochs + prunedEpochs + activeRetainedEpochs).forEach {
            try $0.validate()
        }
        let retained = retainedEpochs.map(\.generationID)
        let pruned = prunedEpochs.map(\.generationID)
        let active = activeRetainedEpochs.map(\.generationID)
        let uncertain = Set(uncertainRetainedGenerationIDs)
        let exactRetainedEpochs = Set(retainedEpochs)
        let exactActiveEpochs = Set(activeRetainedEpochs)
        let allKnownEpochIDs = Set(retained + pruned + active)
        guard schemaVersion == Self.currentSchemaVersion,
              operationID != GenerationEpochV1.zeroUUID,
              retained.count + pruned.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              active.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              uncertainRetainedGenerationIDs.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              retainedEpochs == retainedEpochs.sorted(
                  by: GenerationContractCanonicalOrderV1.epoch
              ),
              prunedEpochs == prunedEpochs.sorted(
                  by: GenerationContractCanonicalOrderV1.epoch
              ),
              activeRetainedEpochs == activeRetainedEpochs.sorted(
                  by: GenerationContractCanonicalOrderV1.epoch
              ),
              uncertainRetainedGenerationIDs
                == uncertainRetainedGenerationIDs.sorted(
                    by: GenerationContractCanonicalOrderV1.uuid
                ),
              Set(retained).count == retained.count,
              Set(pruned).count == pruned.count,
              Set(active).count == active.count,
              uncertain.count
                == uncertainRetainedGenerationIDs.count,
              uncertainRetainedGenerationIDs.allSatisfy({
                  $0 != GenerationEpochV1.zeroUUID
              }),
              Set(retained).isDisjoint(with: Set(pruned)),
              exactActiveEpochs.isSubset(of: exactRetainedEpochs),
              exactRetainedEpochs.contains(currentEpoch),
              !Set(pruned).contains(currentEpoch.generationID),
              uncertain.isDisjoint(with: allKnownEpochIDs),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
                  inventoryBeforeSHA256
              ),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
                  inventoryAfterSHA256
              ) else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        switch disposition {
        case .pruned:
            guard !prunedEpochs.isEmpty,
                  uncertainRetainedGenerationIDs.isEmpty,
                  !ownerLivenessUncertain else {
                throw GenerationLeaseRegistryFailureV1.invalidContract
            }
        case .uncertainRetainAll:
            guard prunedEpochs.isEmpty,
                  ownerLivenessUncertain
                    || !uncertainRetainedGenerationIDs.isEmpty else {
                throw GenerationLeaseRegistryFailureV1.invalidContract
            }
        case .noEligibleGenerations, .disabledRetainAll:
            guard prunedEpochs.isEmpty,
                  !ownerLivenessUncertain else {
                throw GenerationLeaseRegistryFailureV1.invalidContract
            }
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(try canonicalData())
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
    }
}

enum GenerationPruneIntentPhaseV1: String, Codable, CaseIterable, Equatable,
    Sendable {
    case prepared = "PREPARED"
    case bytesRemoved = "BYTES_REMOVED"
    case retiredPointerPublished = "RETIRED_POINTER_PUBLISHED"
    case receiptPublished = "RECEIPT_PUBLISHED"

    fileprivate var ordinal: Int {
        switch self {
        case .prepared: return 0
        case .bytesRemoved: return 1
        case .retiredPointerPublished: return 2
        case .receiptPublished: return 3
        }
    }
}

struct GenerationPruneIntentV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let phase: GenerationPruneIntentPhaseV1
    let currentEpoch: GenerationEpochV1
    let candidateEpochs: [GenerationEpochV1]
    let retainedEpochs: [GenerationEpochV1]
    let activeRetainedEpochs: [GenerationEpochV1]
    let uncertainRetainedGenerationIDs: [UUID]
    let inventoryBeforeSHA256: String
    let expectedRetiredGenerationIDs: [UUID]
    let desiredRetiredGenerationIDs: [UUID]

    init(
        operationID: UUID,
        phase: GenerationPruneIntentPhaseV1 = .prepared,
        currentEpoch: GenerationEpochV1,
        candidateEpochs: [GenerationEpochV1],
        retainedEpochs: [GenerationEpochV1],
        activeRetainedEpochs: [GenerationEpochV1],
        uncertainRetainedGenerationIDs: [UUID],
        inventoryBeforeSHA256: String,
        expectedRetiredGenerationIDs: [UUID],
        desiredRetiredGenerationIDs: [UUID],
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.phase = phase
        self.currentEpoch = currentEpoch
        self.candidateEpochs = candidateEpochs
        self.retainedEpochs = retainedEpochs
        self.activeRetainedEpochs = activeRetainedEpochs
        self.uncertainRetainedGenerationIDs = uncertainRetainedGenerationIDs
        self.inventoryBeforeSHA256 = inventoryBeforeSHA256
        self.expectedRetiredGenerationIDs = expectedRetiredGenerationIDs
        self.desiredRetiredGenerationIDs = desiredRetiredGenerationIDs
        try validate()
    }

    func advancing(to next: GenerationPruneIntentPhaseV1) throws -> Self {
        guard next.ordinal == phase.ordinal + 1 else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        return try GenerationPruneIntentV1(
            operationID: operationID,
            phase: next,
            currentEpoch: currentEpoch,
            candidateEpochs: candidateEpochs,
            retainedEpochs: retainedEpochs,
            activeRetainedEpochs: activeRetainedEpochs,
            uncertainRetainedGenerationIDs: uncertainRetainedGenerationIDs,
            inventoryBeforeSHA256: inventoryBeforeSHA256,
            expectedRetiredGenerationIDs: expectedRetiredGenerationIDs,
            desiredRetiredGenerationIDs: desiredRetiredGenerationIDs
        )
    }

    func validateReplacement(of previous: Self) throws {
        guard self == (try previous.advancing(to: phase)) else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
    }

    func validate() throws {
        try currentEpoch.validate()
        try (candidateEpochs + retainedEpochs + activeRetainedEpochs).forEach {
            try $0.validate()
        }
        let candidates = candidateEpochs.map(\.generationID)
        let retained = retainedEpochs.map(\.generationID)
        let active = activeRetainedEpochs.map(\.generationID)
        let uncertain = Set(uncertainRetainedGenerationIDs)
        let exactRetainedEpochs = Set(retainedEpochs)
        let expectedRetired = Set(expectedRetiredGenerationIDs)
        let desiredRetired = Set(desiredRetiredGenerationIDs)
        guard schemaVersion == Self.currentSchemaVersion,
              operationID != GenerationEpochV1.zeroUUID,
              !candidateEpochs.isEmpty,
              candidates.count + retained.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              active.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              uncertainRetainedGenerationIDs.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              expectedRetiredGenerationIDs.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              desiredRetiredGenerationIDs.count
                <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
              candidateEpochs == candidateEpochs.sorted(
                  by: GenerationContractCanonicalOrderV1.epoch
              ),
              retainedEpochs == retainedEpochs.sorted(
                  by: GenerationContractCanonicalOrderV1.epoch
              ),
              activeRetainedEpochs == activeRetainedEpochs.sorted(
                  by: GenerationContractCanonicalOrderV1.epoch
              ),
              uncertainRetainedGenerationIDs
                == uncertainRetainedGenerationIDs.sorted(
                    by: GenerationContractCanonicalOrderV1.uuid
                ),
              expectedRetiredGenerationIDs
                == expectedRetiredGenerationIDs.sorted(
                    by: GenerationContractCanonicalOrderV1.uuid
                ),
              desiredRetiredGenerationIDs
                == desiredRetiredGenerationIDs.sorted(
                    by: GenerationContractCanonicalOrderV1.uuid
                ),
              Set(candidates).count == candidates.count,
              Set(retained).count == retained.count,
              Set(active).count == active.count,
              uncertain.count == uncertainRetainedGenerationIDs.count,
              uncertainRetainedGenerationIDs.allSatisfy({
                  $0 != GenerationEpochV1.zeroUUID
              }),
              Set(candidates).isDisjoint(with: Set(retained)),
              Set(activeRetainedEpochs).isSubset(of: exactRetainedEpochs),
              exactRetainedEpochs.contains(currentEpoch),
              Set(expectedRetiredGenerationIDs).count
                == expectedRetiredGenerationIDs.count,
              Set(desiredRetiredGenerationIDs).count
                == desiredRetiredGenerationIDs.count,
              desiredRetired.isSubset(of: expectedRetired),
              expectedRetired.subtracting(desiredRetired)
                == Set(candidates),
              !expectedRetiredGenerationIDs.contains(currentEpoch.generationID),
              !desiredRetiredGenerationIDs.contains(currentEpoch.generationID),
              desiredRetired == Set(retained)
                .subtracting(Set([currentEpoch.generationID]))
                .union(uncertain),
              uncertain.isSubset(of: expectedRetired),
              uncertain.isDisjoint(with: Set(candidates)),
              uncertain.isDisjoint(with: Set(retained)),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
                  inventoryBeforeSHA256
              ) else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(try canonicalData())
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
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

enum C45AcceptedLabelMigrationBoundaryV1 { static let sourceVersion=33;static let targetVersion=AssetLabelPersistenceEnrollmentV1.persistentSchemaVersion;static let backfillCreatesSnapshots=false }
enum C46OperationalContactMigrationBoundaryV1 { static let sourceVersion=34;static let targetVersion=OperationalContactPersistenceEnrollmentV1.persistentSchemaVersion;static let backfillCreatesContactsOrHandoffIntents=false;static let handoffOutcomesAndImportSourceBytesAreExcluded=true }
enum C47ActivityContractMigrationBoundaryV2 { static let sourceVersion=35;static let targetVersion=36;static let recordsVersion=35;static let backfillCreatesActivityTruth=false;static let reusesReleasedCompletedSnapshotStorage=true }
enum C48PortableExchangeMigrationBoundaryV2 {
    static let sourceVersion = 1
    static let targetVersion = 2
    static let persistentSchemaVersion = 36
    static let canonicalSwiftDataSchemaChanged = false
    static let preservesExactBytes = true
    static let quarantineExcludedFromBackup = true
    static let cloneOrForkInvalidatesCapabilities = true
}
enum C49WorkResourceMigrationBoundaryV1 {
    static let sourceVersion = 36
    static let targetVersion = 37
    static let recordsVersion = 36
    static let newDurableRows = ["ManualWorkResourceRecordRow"]
    static let backfillCreatesWorkResourceTruth = false
    static let localPartReferenceRemainsEmbedded = true
    static let liveInventoryRowsAdded = false
}

enum C50IncumbentFileExchangeMigrationBoundaryV1 {
    static let sourceVersion = 37
    static let targetVersion = 37
    static let persistentSchemaVersion = 37
    static let recordsSchemaVersion = 36
    static let migrationDisposition = "NOT_APPLICABLE"
    static let profileSelectionSessionSourceQuarantineAreNonpersistent = true
    static let newPersistentRows = 0
    static let canonicalImportedEffectsUseExistingMigration = true

    static func validate() -> Bool {
        sourceVersion == 37
            && targetVersion == 37
            && persistentSchemaVersion == 37
            && recordsSchemaVersion == 36
            && migrationDisposition == "NOT_APPLICABLE"
            && profileSelectionSessionSourceQuarantineAreNonpersistent
            && newPersistentRows == 0
            && canonicalImportedEffectsUseExistingMigration
            && C50IncumbentFileExchangePersistenceBoundaryV1.validate()
    }
}

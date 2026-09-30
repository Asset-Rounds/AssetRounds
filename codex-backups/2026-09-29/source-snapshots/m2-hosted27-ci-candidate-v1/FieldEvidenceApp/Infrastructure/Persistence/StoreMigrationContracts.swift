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

/// Structural ownership only. A recognized staging path still belongs to its
/// original recovery operation and is never a durable migration input.
enum GenerationOwnedPathV1 {
    enum NodeType: Equatable { case directory, regularFile }
    struct Classification {
        let kind: OwnedFileKindV1
        let recoveryOwned: Bool
    }

    static func classify(_ path: String, nodeType: NodeType) throws -> Classification {
        guard StoreGenerationFileDigestV1.isCanonicalRelativePath(path) else {
            throw StoreMigrationFailure.invalidPath
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let staging = parts.first == ".staging"
        let components = staging ? Array(parts.dropFirst()) : parts
        func result(_ kind: OwnedFileKindV1) -> Classification {
            Classification(kind: staging
                ? (nodeType == .directory ? .stagingDirectory : .stagingFile)
                : kind, recoveryOwned: staging)
        }
        func uuid(_ value: String) -> Bool {
            UUID(uuidString: value)?.uuidString.lowercased() == value
        }
        func suffixedUUID(_ value: String, suffix: String) -> Bool {
            value.hasSuffix(suffix) && uuid(String(value.dropLast(suffix.count)))
        }
        if nodeType == .directory {
            if staging && components.isEmpty { return result(.stagingDirectory) }
            if components.count == 1,
               ["evidence", "snapshots", "pdfs"].contains(components[0]) {
                return result(.durableDirectory)
            }
            if components.count == 2, components[0] == "evidence", uuid(components[1]) {
                return result(.durableDirectory)
            }
            if staging, components.first == "evidence-derivatives" {
                if components.count == 1
                    || (components.count == 2 && uuid(components[1]))
                    || (components.count == 3 && uuid(components[1])
                        && ContentContractValidationV1.validID(components[2])) {
                    return result(.stagingDirectory)
                }
            }
            if !staging, components.first == "content" {
                if components.count == 1
                    || (components.count == 2 && uuid(components[1]))
                    || (components.count == 3 && uuid(components[1])
                        && (ContentContractValidationV1.validID(components[2])
                            || components[2] == ".asset-label-publications"))
                    || (components.count == 4 && uuid(components[1])
                        && components[2] == ".asset-label-publications" && uuid(components[3])) {
                    return result(.durableDirectory)
                }
            }
        } else {
            if !staging, components.count == 1 {
                switch path {
                case "model.sqlite": return result(.database)
                case "model.sqlite-wal": return result(.databaseWAL)
                case "model.sqlite-shm": return result(.databaseSHM)
                default: break
                }
            }
            if components.count == 3, components[0] == "evidence", uuid(components[1]) {
                if components[2] == "original.jpg" { return result(.mediaOriginal) }
                if components[2] == "thumbnail.jpg" { return result(.mediaThumbnail) }
                if staging && components[2] == "pair-publication.json" {
                    return result(.stagingFile)
                }
            }
            if components.count == 2, components[0] == "snapshots",
               suffixedUUID(components[1], suffix: ".json") { return result(.reportSnapshot) }
            if components.count == 2, components[0] == "pdfs",
               suffixedUUID(components[1], suffix: ".pdf") { return result(.reportPDF) }
            if components.count == 4, uuid(components[1]),
               ContentContractValidationV1.validID(components[2]),
               ((!staging && components[0] == "content")
                || (staging && components[0] == "evidence-derivatives")) {
                if components[3] == "original.bin" { return result(.mediaOriginal) }
                if components[3] == "derivative-publication.json" { return result(.reportSnapshot) }
            }
            if !staging, components.count == 5, components[0] == "content",
               uuid(components[1]), components[2] == ".asset-label-publications",
               uuid(components[3]), components[4] == "publication.json" {
                return result(.reportSnapshot)
            }
        }
        throw StoreMigrationFailure.invalidPath
    }
}

/// Exact recovery-owned generation membership for one authenticated photo
/// restore. This value is derived from the closed photo member plan; callers
/// cannot turn arbitrary staging paths into restore manifest input.
struct StoreRestoreGenerationManifestProofV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let restoreID: UUID
    let predecessorGenerationID: UUID
    let generationID: UUID
    /// SHA-256 of the incumbent restore publication-binding payload before
    /// this proof is attached. Keeping the layers separate avoids a circular
    /// digest while still binding the authenticated member mappings.
    let incumbentPublicationBindingSHA256: String
    /// Ordered canonical digests of the complete freshly resolved plans. These
    /// bind source, child phase, raw publications, every generation member,
    /// and metadata even when the recovery-owned subset is empty.
    let planBindingSHA256s: [String]
    let selectedChildCount: Int
    let generationFiles: [StoreGenerationFileDigestV1]
    let recoveryFiles: [StoreGenerationFileDigestV1]
    let recoveryDirectories: [String]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, restoreID, predecessorGenerationID, generationID
        case incumbentPublicationBindingSHA256, planBindingSHA256s
        case selectedChildCount
        case generationFiles, recoveryFiles, recoveryDirectories
    }

    private struct PlanBinding: Codable {
        struct Child: Codable {
            let childDraftID: UUID
            let stageID: UUID
            let physicalEntry: CheckRunnerPhotoBackupPhysicalEntryV1?
            let pairLocation: String
            let stagedMarkerPresent: Bool?
            let immutableRawPath: String?
            let entries: [V4BackupEntryV1]
        }
        struct RawPublication: Codable {
            let physicalEntry: CheckRunnerPhotoBackupPhysicalEntryV1
            let payload: V4BackupEntryV1
            let witness: V4BackupEntryV1
            let witnessBytes: Data
        }
        struct GenerationMember: Codable {
            let entry: V4BackupEntryV1
            let relativePath: String
            let kind: String
        }
        struct Metadata: Codable {
            let path: String
            let bytes: Data
        }

        let source: V4BackupSourceV1
        let children: [Child]
        let rawPublications: [RawPublication]
        let generationMembers: [GenerationMember]
        let metadata: [Metadata]

        init(_ plan: CheckRunnerPhotoBackupRestorePlanV1) {
            source = plan.source
            children = plan.children.map { child in
                let location: String
                let marker: Bool?
                switch child.pairLocation {
                case .absent:
                    location = "absent"
                    marker = nil
                case .staged(let markerPresent):
                    location = "staged"
                    marker = markerPresent
                case .promoted:
                    location = "promoted"
                    marker = nil
                case .targetOwned:
                    location = "targetOwned"
                    marker = nil
                }
                return Child(
                    childDraftID: child.childDraftID,
                    stageID: child.stageID,
                    physicalEntry: child.physicalEntry,
                    pairLocation: location,
                    stagedMarkerPresent: marker,
                    immutableRawPath: child.immutableRawPath,
                    entries: child.entries
                )
            }
            rawPublications = plan.rawPublications.map {
                RawPublication(
                    physicalEntry: $0.physicalEntry,
                    payload: $0.payload,
                    witness: $0.witness,
                    witnessBytes: $0.witnessBytes
                )
            }
            generationMembers = plan.generationMembers.map {
                let kind: String
                switch $0.kind {
                case .original: kind = "original"
                case .thumbnail: kind = "thumbnail"
                case .staging: kind = "staging"
                }
                return GenerationMember(
                    entry: $0.entry,
                    relativePath: $0.relativePath,
                    kind: kind
                )
            }
            metadata = plan.metadata.keys.sorted().map {
                Metadata(path: $0, bytes: plan.metadata[$0]!)
            }
        }
    }

    private static func planBindingSHA256(
        _ plan: CheckRunnerPhotoBackupRestorePlanV1
    ) throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(
            try StoreMigrationCanonicalJSONV1.encode(PlanBinding(plan))
        )
    }

    init(
        restoreID: UUID,
        predecessorGenerationID: UUID,
        generationID: UUID,
        incumbentPublicationBindingSHA256: String,
        plans: [CheckRunnerPhotoBackupRestorePlanV1]
    ) throws {
        self.schemaVersion = 1
        self.restoreID = restoreID
        self.predecessorGenerationID = predecessorGenerationID
        self.generationID = generationID
        self.incumbentPublicationBindingSHA256 = incumbentPublicationBindingSHA256
        guard !plans.isEmpty else { throw StoreMigrationFailure.invalidContract }
        planBindingSHA256s = try plans.map {
            try Self.planBindingSHA256($0)
        }
        guard Set(planBindingSHA256s).count == planBindingSHA256s.count else {
            throw StoreMigrationFailure.invalidContract
        }
        selectedChildCount = plans.reduce(0) { $0 + $1.children.count }
        var childIDsBySource: [Data: Set<UUID>] = [:]
        for plan in plans {
            let sourceTuple = try StoreMigrationCanonicalJSONV1.encode(
                plan.source
            )
            for child in plan.children {
                let inserted = childIDsBySource[sourceTuple, default: []]
                    .insert(child.childDraftID)
                guard inserted.inserted else {
                    throw StoreMigrationFailure.invalidContract
                }
            }
        }
        // A plan may contribute no child only as an explicitly hashed member of
        // a larger nonempty selection. The ordered binding above keeps that plan
        // visible and rejects an exact duplicate even when it owns no files.
        guard childIDsBySource.values.contains(where: { !$0.isEmpty }) else {
            throw StoreMigrationFailure.invalidContract
        }
        var fileByPath: [String: StoreGenerationFileDigestV1] = [:]
        for plan in plans {
            for member in plan.generationMembers {
                let owned = try GenerationOwnedPathV1.classify(
                    member.relativePath,
                    nodeType: .regularFile
                )
                guard member.kind.protection == owned.kind,
                      member.entry.byteCount >= 0 else {
                    throw StoreMigrationFailure.invalidContract
                }
                let value = try StoreGenerationFileDigestV1(
                    relativePath: member.relativePath,
                    byteCount: member.entry.byteCount,
                    sha256: member.entry.sha256,
                    kind: owned.kind
                )
                if let existing = fileByPath[member.relativePath],
                   existing != value {
                    throw StoreMigrationFailure.invalidContract
                }
                fileByPath[member.relativePath] = value
            }
        }
        generationFiles = fileByPath.values.sorted {
            $0.relativePath < $1.relativePath
        }
        recoveryFiles = try generationFiles.filter {
            try GenerationOwnedPathV1.classify(
                $0.relativePath,
                nodeType: .regularFile
            ).recoveryOwned
        }
        recoveryDirectories = try Self.requiredDirectories(for: recoveryFiles)
        try validate()
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        restoreID = try values.decode(UUID.self, forKey: .restoreID)
        predecessorGenerationID = try values.decode(UUID.self, forKey: .predecessorGenerationID)
        generationID = try values.decode(UUID.self, forKey: .generationID)
        incumbentPublicationBindingSHA256 = try values.decode(
            String.self,
            forKey: .incumbentPublicationBindingSHA256
        )
        planBindingSHA256s = try values.decode(
            [String].self,
            forKey: .planBindingSHA256s
        )
        selectedChildCount = try values.decode(
            Int.self,
            forKey: .selectedChildCount
        )
        generationFiles = try values.decode(
            [StoreGenerationFileDigestV1].self,
            forKey: .generationFiles
        )
        recoveryFiles = try values.decode(
            [StoreGenerationFileDigestV1].self,
            forKey: .recoveryFiles
        )
        recoveryDirectories = try values.decode(
            [String].self,
            forKey: .recoveryDirectories
        )
        try validate()
    }

    func validate() throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard schemaVersion == 1,
              restoreID != zero,
              predecessorGenerationID != zero,
              generationID != zero,
              restoreID != predecessorGenerationID,
              restoreID != generationID,
              predecessorGenerationID != generationID,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
                  incumbentPublicationBindingSHA256
              ),
              !planBindingSHA256s.isEmpty,
              selectedChildCount > 0,
              Set(planBindingSHA256s).count == planBindingSHA256s.count,
              planBindingSHA256s.allSatisfy(
                StoreMigrationCanonicalJSONV1.isLowercaseSHA256
              ),
              generationFiles == generationFiles.sorted(by: {
                  $0.relativePath < $1.relativePath
              }),
              Set(generationFiles.map(\.relativePath)).count
                == generationFiles.count,
              recoveryFiles == recoveryFiles.sorted(by: {
                  $0.relativePath < $1.relativePath
              }),
              Set(recoveryFiles.map(\.relativePath)).count
                == recoveryFiles.count,
              recoveryDirectories == (try Self.requiredDirectories(
                  for: recoveryFiles
              )) else {
            throw StoreMigrationFailure.invalidContract
        }
        try generationFiles.forEach { file in
            try file.validate()
            let owned = try GenerationOwnedPathV1.classify(
                file.relativePath,
                nodeType: .regularFile
            )
            guard owned.kind == file.kind else {
                throw StoreMigrationFailure.invalidContract
            }
        }
        let derivedRecovery = try generationFiles.filter {
            try GenerationOwnedPathV1.classify(
                $0.relativePath,
                nodeType: .regularFile
            ).recoveryOwned
        }
        guard derivedRecovery == recoveryFiles else {
            throw StoreMigrationFailure.invalidContract
        }
        var leavesByEvidenceID: [String: Set<String>] = [:]
        for file in recoveryFiles {
            try file.validate()
            let parts = file.relativePath.split(
                separator: "/",
                omittingEmptySubsequences: false
            ).map(String.init)
            guard parts.count == 4,
                  parts[0] == ".staging",
                  parts[1] == "evidence",
                  UUID(uuidString: parts[2])?.uuidString.lowercased()
                    == parts[2],
                  ["original.jpg", "thumbnail.jpg", "pair-publication.json"]
                    .contains(parts[3]),
                  let owned = try? GenerationOwnedPathV1.classify(
                      file.relativePath,
                      nodeType: .regularFile
                  ),
                  owned.recoveryOwned,
                  owned.kind == file.kind else {
                throw StoreMigrationFailure.invalidPath
            }
            leavesByEvidenceID[parts[2], default: []].insert(parts[3])
        }
        for leaves in leavesByEvidenceID.values {
            guard leaves == ["original.jpg", "thumbnail.jpg"]
                    || leaves == [
                        "original.jpg", "thumbnail.jpg",
                        "pair-publication.json",
                    ] else {
                throw StoreMigrationFailure.invalidContract
            }
        }
    }

    func matches(
        incumbentPublicationBindingSHA256 expectedBindingSHA256: String,
        plans: [CheckRunnerPhotoBackupRestorePlanV1]
    ) throws -> Bool {
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(
            expectedBindingSHA256
        ) else {
            throw StoreMigrationFailure.invalidDigest
        }
        return try Self(
            restoreID: restoreID,
            predecessorGenerationID: predecessorGenerationID,
            generationID: generationID,
            incumbentPublicationBindingSHA256: expectedBindingSHA256,
            plans: plans
        ) == self
    }

    func canonicalData() throws -> Data {
        try validate()
        return try StoreMigrationCanonicalJSONV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        StoreMigrationCanonicalJSONV1.sha256(try canonicalData())
    }

    static func decodeCanonical(
        from data: Data,
        incumbentPublicationBindingSHA256 expectedBindingSHA256: String,
        resolving plans: [CheckRunnerPhotoBackupRestorePlanV1]
    ) throws -> Self {
        let value = try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            Self.self,
            from: data,
            validate: { try $0.validate() }
        )
        guard try value.matches(
            incumbentPublicationBindingSHA256: expectedBindingSHA256,
            plans: plans
        ) else {
            throw StoreMigrationFailure.invalidContract
        }
        return value
    }

    private static func requiredDirectories(
        for files: [StoreGenerationFileDigestV1]
    ) throws -> [String] {
        var paths = Set<String>()
        for file in files {
            var components = file.relativePath.split(separator: "/").map(String.init)
            guard components.count > 1 else {
                throw StoreMigrationFailure.invalidPath
            }
            components.removeLast()
            while !components.isEmpty {
                let path = components.joined(separator: "/")
                let owned = try GenerationOwnedPathV1.classify(
                    path,
                    nodeType: .directory
                )
                guard owned.recoveryOwned else {
                    throw StoreMigrationFailure.invalidPath
                }
                paths.insert(path)
                components.removeLast()
            }
        }
        return paths.sorted()
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

/// Manifest schema 1 retains its original nested canonical SHA256 meaning.
/// Schema 2 explicitly opts into this closed, V53-only format.
enum StoreSemanticDigestAlgorithmV1: String, Codable, Equatable, Sendable {
    case framedLayersV1
}

/// Hashes every complete local validation envelope once, in V3...Vn order.
/// Framing is domain UTF8 (including NUL), UInt64 big-endian release n, then
/// (layer number, byte count, canonical bytes) per layer, and final layer count.
/// Release n (3...53) has exactly n-2 layers; V53 bytes are unchanged from the
/// original V53-only format. V1/V2 flat record digests are never framed.
/// No encoded layer or predecessor byte stream is retained after append returns.
struct StoreSemanticLayerDigestV1 {
    private var hasher = SHA256()
    private var layerCount: UInt64 = 0
    private let expectedLayerCount: UInt64

    init(release: PersistentSchemaReleaseV1) throws {
        let major = release.versionIdentifier.major
        guard (3...53).contains(major),
              PersistentSchemaReleaseRegistryV1.releases.contains(release) else {
            throw StoreMigrationFailure.invalidContract
        }
        expectedLayerCount = UInt64(major - 2)
        hasher.update(data: Data("AssetRounds.StoreSemanticDigest.framed-layers.v1\0".utf8))
        appendInteger(UInt64(major))
    }

    mutating func append(_ canonicalLayer: Data) throws {
        guard layerCount < expectedLayerCount else { throw StoreMigrationFailure.invalidContract }
        appendInteger(layerCount + 3)
        appendInteger(UInt64(canonicalLayer.count))
        hasher.update(data: canonicalLayer)
        layerCount += 1
    }

    mutating func finalize() throws -> String {
        guard layerCount == expectedLayerCount else { throw StoreMigrationFailure.invalidContract }
        appendInteger(layerCount)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private mutating func appendInteger(_ integer: UInt64) {
        var bigEndian = integer.bigEndian
        hasher.update(data: withUnsafeBytes(of: &bigEndian) { Data($0) })
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
    let semanticDigestAlgorithm: StoreSemanticDigestAlgorithmV1?
    let frozenIdentityDigest: String
    let files: [StoreGenerationFileDigestV1]
    let restoreProof: StoreRestoreGenerationManifestProofV1?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generationID, predecessorGenerationID, migrationID
        case storeSchemaRelease, semanticSHA256, frozenIdentityDigest, files
        case restoreProof, semanticDigestAlgorithm
    }

    init(
        schemaVersion: Int = 1,
        generationID: UUID,
        predecessorGenerationID: UUID,
        migrationID: UUID,
        storeSchemaRelease: PersistentSchemaReleaseV1,
        semanticSHA256: String?,
        semanticDigestAlgorithm: StoreSemanticDigestAlgorithmV1? = nil,
        frozenIdentityDigest: String,
        files: [StoreGenerationFileDigestV1],
        restoreProof: StoreRestoreGenerationManifestProofV1? = nil
    ) throws {
        self.schemaVersion = schemaVersion
        self.generationID = generationID
        self.predecessorGenerationID = predecessorGenerationID
        self.migrationID = migrationID
        self.storeSchemaRelease = storeSchemaRelease
        self.semanticSHA256 = semanticSHA256
        self.semanticDigestAlgorithm = semanticDigestAlgorithm
        self.frozenIdentityDigest = frozenIdentityDigest
        self.files = files
        self.restoreProof = restoreProof
        try validate()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        generationID = try values.decode(UUID.self, forKey: .generationID)
        predecessorGenerationID = try values.decode(
            UUID.self,
            forKey: .predecessorGenerationID
        )
        migrationID = try values.decode(UUID.self, forKey: .migrationID)
        storeSchemaRelease = try values.decode(
            PersistentSchemaReleaseV1.self,
            forKey: .storeSchemaRelease
        )
        semanticSHA256 = try values.decodeIfPresent(
            String.self,
            forKey: .semanticSHA256
        )
        // A legacy manifest must omit this field, even when its JSON value is null.
        guard schemaVersion != 1 || !values.contains(.semanticDigestAlgorithm) else {
            throw StoreMigrationFailure.invalidContract
        }
        semanticDigestAlgorithm = try values.decodeIfPresent(
            StoreSemanticDigestAlgorithmV1.self, forKey: .semanticDigestAlgorithm
        )
        frozenIdentityDigest = try values.decode(
            String.self,
            forKey: .frozenIdentityDigest
        )
        files = try values.decode(
            [StoreGenerationFileDigestV1].self,
            forKey: .files
        )
        restoreProof = try values.decodeIfPresent(
            StoreRestoreGenerationManifestProofV1.self,
            forKey: .restoreProof
        )
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(generationID, forKey: .generationID)
        try values.encode(
            predecessorGenerationID,
            forKey: .predecessorGenerationID
        )
        try values.encode(migrationID, forKey: .migrationID)
        try values.encode(storeSchemaRelease, forKey: .storeSchemaRelease)
        try values.encodeIfPresent(semanticSHA256, forKey: .semanticSHA256)
        try values.encodeIfPresent(semanticDigestAlgorithm, forKey: .semanticDigestAlgorithm)
        try values.encode(frozenIdentityDigest, forKey: .frozenIdentityDigest)
        try values.encode(files, forKey: .files)
        try values.encodeIfPresent(restoreProof, forKey: .restoreProof)
    }

    func validate() throws {
        guard generationID != predecessorGenerationID else {
            throw StoreMigrationFailure.invalidContract
        }
        switch schemaVersion {
        case 1:
            guard semanticDigestAlgorithm == nil else {
                throw StoreMigrationFailure.invalidContract
            }
        case 2:
            guard semanticDigestAlgorithm == .framedLayersV1,
                  storeSchemaRelease == .v53 else {
                throw StoreMigrationFailure.invalidContract
            }
        default:
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
        let classified = try files.map { file -> GenerationOwnedPathV1.Classification in
            try GenerationOwnedPathV1.classify(
                file.relativePath,
                nodeType: .regularFile
            )
        }
        let recoveryFiles = zip(files, classified).compactMap { file, owned in
            owned.recoveryOwned ? file : nil
        }
        guard paths == paths.sorted(),
              Set(paths).count == paths.count,
              paths.contains("model.sqlite"),
              zip(files, classified).allSatisfy({ file, owned in
                  file.kind == owned.kind
              }) else {
            throw StoreMigrationFailure.invalidContract
        }
        if let restoreProof {
            try restoreProof.validate()
            let manifestFiles = Dictionary(
                uniqueKeysWithValues: files.map { ($0.relativePath, $0) }
            )
            guard restoreProof.generationID == generationID,
                  restoreProof.predecessorGenerationID
                    == predecessorGenerationID,
                  recoveryFiles == restoreProof.recoveryFiles,
                  restoreProof.generationFiles.allSatisfy({
                      manifestFiles[$0.relativePath] == $0
                  }) else {
                throw StoreMigrationFailure.invalidContract
            }
        } else if !recoveryFiles.isEmpty {
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
              (2...PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major)
                .contains(storeSchemaVersion),
              PersistentSchemaReleaseRegistryV1.releases.contains(where: {
                  $0.versionIdentifier.major == storeSchemaVersion
              }),
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
                || (sourceRelease == .v32 && targetRelease == .v33)
                || (sourceRelease == .v33 && targetRelease == .v34)
                || (sourceRelease == .v34 && targetRelease == .v35)
                || (sourceRelease == .v35 && targetRelease == .v36)
                || (sourceRelease == .v36 && targetRelease == .v37)
                || (sourceRelease == .v37 && targetRelease == .v38)
                || (sourceRelease == .v38 && targetRelease == .v39)
                || (sourceRelease == .v39 && targetRelease == .v40)) else {
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
              previous.targetManifestDigest.map({
                $0 == targetManifestDigest
              }) ?? true,
              previous.targetSemanticDigest.map({
                $0 == targetSemanticDigest
              }) ?? true,
              previous.desiredPointerDigest.map({
                $0 == desiredPointerDigest
              }) ?? true,
              previous.publicationProcessID.map({
                $0 == publicationProcessID
              }) ?? true,
              previous.firstValidationProcessID.map({
                $0 == firstValidationProcessID
              }) ?? true,
              previous.secondValidationProcessID.map({
                $0 == secondValidationProcessID
              }) ?? true else {
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

/// Separate operational authority for a skipped-release upgrade. Activation
/// manifests describe their original activation, never the latest user writes.
struct StoreMigrationSourceCheckpointV1: Codable, Equatable, Sendable {
    let files: [StoreGenerationFileDigestV1]
    let directories: [String]
    let frozenIdentityDigest: String
    let semanticSHA256: String

    func validate() throws {
        guard !files.isEmpty, files.contains(where: { $0.relativePath == "model.sqlite" }),
              files == files.sorted(by: { $0.relativePath < $1.relativePath }),
              Set(files.map(\.relativePath)).count == files.count,
              directories == directories.sorted(), Set(directories).count == directories.count,
              Self.isDigest(frozenIdentityDigest), Self.isDigest(semanticSHA256) else {
            throw StoreMigrationFailure.invalidContract
        }
        for file in files {
            try file.validate()
            let owned = try GenerationOwnedPathV1.classify(file.relativePath, nodeType: .regularFile)
            guard !owned.recoveryOwned, owned.kind == file.kind else { throw StoreMigrationFailure.invalidPath }
        }
        for path in directories { _ = try GenerationOwnedPathV1.classify(path, nodeType: .directory) }
    }

    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct StoreAggregateMigrationTransitionV1: Codable, Equatable, Sendable {
    let sourceRelease: PersistentSchemaReleaseV1
    let targetRelease: PersistentSchemaReleaseV1
    let sourceSemanticSHA256: String
    let targetSemanticSHA256: String
}

enum StoreAggregateMigrationPhaseV1: Int, Codable, Equatable, Sendable {
    case recoveringSource, sourceFrozen, cloned, migrating, targetValidated
    case generationInstalled, pointerPublished, awaitingIndependentValidation, complete
}

struct StoreAggregateMutationNormalizationV1: Codable, Equatable, Sendable {
    let generationID: UUID
    let mutableSemanticSHA256: String?
}

struct StoreAggregateMigrationJournalV1: Codable, Equatable, Sendable {
    /// Schema 2 records V3...V53 candidate digests as `StoreSemanticLayerDigestV1`
    /// (V1/V2 flat records digests are unchanged). Schema 1 recorded nested
    /// canonical digests: only its completed history remains readable.
    static let currentSchemaVersion = 2
    /// An unfinished schema-1 journal is never reinterpreted or re-hashed.
    static let nestedDigestJournalRequiresForwardFix = StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
    var schemaVersion: Int = Self.currentSchemaVersion
    let upgradeID: UUID
    var ownerID: UUID
    var revision: Int = 0
    let sourceGenerationID: UUID
    let sourceRelease: PersistentSchemaReleaseV1
    let originalPointerData: Data
    let sourceRootDevice: UInt64
    let sourceRootInode: UInt64
    let activationManifestSHA256: String?
    let migrationID: UUID
    let targetGenerationID: UUID
    let targetRelease: PersistentSchemaReleaseV1
    let workspaceID: UUID
    let replicaID: UUID
    let knownReplicaIDs: [UUID]
    let originatingProcessID: UUID
    var phase: StoreAggregateMigrationPhaseV1 = .recoveringSource
    var sourceCheckpoint: StoreMigrationSourceCheckpointV1?
    var candidateRootDevice: UInt64?
    var candidateRootInode: UInt64?
    var allocationID: UUID?
    var transitions: [StoreAggregateMigrationTransitionV1] = []
    var authorizedTargetRelease: PersistentSchemaReleaseV1?
    var authorizedPriorMutationState: StoreAggregateMutationNormalizationV1?
    var targetManifestSHA256: String?
    var desiredPointerData: Data?
    var publicationProcessID: UUID?
    var firstValidationProcessID: UUID?
    var secondValidationProcessID: UUID?

    var reservationIsActive: Bool { phase != .complete }
    var currentCandidateRelease: PersistentSchemaReleaseV1 { transitions.last?.targetRelease ?? sourceRelease }
    var currentCandidateSemanticSHA256: String? { transitions.last?.targetSemanticSHA256 ?? sourceCheckpoint?.semanticSHA256 }

    func identity() throws -> WorkspaceReplicaIdentityV1 {
        try WorkspaceReplicaIdentityV1(workspaceID: WorkspaceID(rawValue: workspaceID), replicaID: ReplicaID(rawValue: replicaID))
    }

    func validate() throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        if schemaVersion == 1, phase != .complete { throw Self.nestedDigestJournalRequiresForwardFix }
        guard schemaVersion == Self.currentSchemaVersion || (schemaVersion == 1 && phase == .complete), revision >= 0,
              [upgradeID, ownerID, sourceGenerationID, targetGenerationID, migrationID, originatingProcessID].allSatisfy({ $0 != zero }),
              sourceGenerationID != targetGenerationID, upgradeID != sourceGenerationID, upgradeID != targetGenerationID,
              sourceRelease.versionIdentifier.major < targetRelease.versionIdentifier.major,
              targetRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              !originalPointerData.isEmpty, sourceRootInode != 0,
              activationManifestSHA256.map(StoreMigrationSourceCheckpointV1.isDigest) ?? true,
              Set(knownReplicaIDs).count == knownReplicaIDs.count,
              knownReplicaIDs.contains(replicaID) else {
            throw StoreMigrationFailure.invalidContract
        }
        _ = try identity()
        let original = try CurrentPointerCodecV1.decode(originalPointerData)
        guard original.generationID == sourceGenerationID.uuidString.lowercased() else { throw StoreMigrationFailure.invalidIdentity }
        switch original {
        case .legacy:
            guard sourceRelease == .v1, activationManifestSHA256 == nil else { throw StoreMigrationFailure.invalidContract }
        case .v2(let pointer, _):
            guard sourceRelease == .v2, activationManifestSHA256 == pointer.generationManifestSHA256 else { throw StoreMigrationFailure.invalidContract }
        case .v3(let pointer, _):
            guard pointer.storeSchemaVersion == sourceRelease.versionIdentifier.major,
                  activationManifestSHA256 == pointer.generationManifestSHA256,
                  try pointer.identity() == identity(),
                  Set(try pointer.knownReplicaIdentitySet().map(\.rawValue)) == Set(knownReplicaIDs) else { throw StoreMigrationFailure.invalidContract }
        }
        if let sourceCheckpoint { try sourceCheckpoint.validate() }
        guard (phase == .recoveringSource) == (sourceCheckpoint == nil) else { throw StoreMigrationFailure.invalidContract }
        guard (candidateRootDevice == nil) == (candidateRootInode == nil),
              (allocationID == nil) == (candidateRootInode == nil),
              allocationID.map({ $0 != zero && $0 != sourceGenerationID && $0 != targetGenerationID }) ?? true,
              candidateRootInode.map({ $0 != 0 }) ?? true else { throw StoreMigrationFailure.invalidIdentity }
        if phase == .recoveringSource, candidateRootInode != nil { throw StoreMigrationFailure.invalidPhaseTransition }
        if phase.rawValue >= StoreAggregateMigrationPhaseV1.cloned.rawValue, candidateRootInode == nil { throw StoreMigrationFailure.invalidIdentity }
        var release = sourceRelease
        var semantic = sourceCheckpoint?.semanticSHA256
        for transition in transitions {
            guard transition.sourceRelease == release,
                  transition.targetRelease.predecessorVersionIdentifier == release.versionIdentifier,
                  transition.targetRelease.versionIdentifier.major <= targetRelease.versionIdentifier.major,
                  transition.sourceSemanticSHA256 == semantic,
                  StoreMigrationSourceCheckpointV1.isDigest(transition.targetSemanticSHA256) else {
                throw StoreMigrationFailure.invalidPhaseTransition
            }
            release = transition.targetRelease
            semantic = transition.targetSemanticSHA256
        }
        if let authorizedTargetRelease {
            guard phase == .migrating,
                  authorizedTargetRelease.predecessorVersionIdentifier == release.versionIdentifier else {
                throw StoreMigrationFailure.invalidPhaseTransition
            }
        }
        if let normalization = authorizedPriorMutationState {
            guard authorizedTargetRelease != nil, currentCandidateRelease.versionIdentifier.major >= 4,
                  [sourceGenerationID, targetGenerationID].contains(normalization.generationID),
                  normalization.mutableSemanticSHA256.map(StoreMigrationSourceCheckpointV1.isDigest) ?? true else {
                throw StoreMigrationFailure.invalidContract
            }
        }
        if authorizedTargetRelease != nil, currentCandidateRelease.versionIdentifier.major >= 4,
           authorizedPriorMutationState == nil { throw StoreMigrationFailure.invalidContract }
        if phase.rawValue < StoreAggregateMigrationPhaseV1.migrating.rawValue {
            guard transitions.isEmpty, authorizedTargetRelease == nil else { throw StoreMigrationFailure.invalidPhaseTransition }
        }
        if phase.rawValue >= StoreAggregateMigrationPhaseV1.targetValidated.rawValue {
            guard release == targetRelease, authorizedTargetRelease == nil,
                  targetManifestSHA256.map(StoreMigrationSourceCheckpointV1.isDigest) == true,
                  desiredPointerData != nil else { throw StoreMigrationFailure.invalidContract }
        } else {
            guard targetManifestSHA256 == nil, desiredPointerData == nil else { throw StoreMigrationFailure.invalidContract }
        }
        if let desiredPointerData {
            let pointer = try CurrentGenerationPointerV3.decodeCanonical(from: desiredPointerData)
            guard pointer.generationID == targetGenerationID.uuidString.lowercased(),
                  pointer.storeSchemaVersion == targetRelease.versionIdentifier.major,
                  pointer.generationManifestSHA256 == targetManifestSHA256,
                  try pointer.identity() == identity(),
                  Set(try pointer.knownReplicaIdentitySet().map(\.rawValue)) == Set(knownReplicaIDs) else { throw StoreMigrationFailure.invalidContract }
        }
        if phase.rawValue >= StoreAggregateMigrationPhaseV1.pointerPublished.rawValue {
            guard publicationProcessID != nil else { throw StoreMigrationFailure.invalidContract }
        }
        if phase.rawValue < StoreAggregateMigrationPhaseV1.generationInstalled.rawValue, publicationProcessID != nil {
            throw StoreMigrationFailure.invalidContract
        }
        if phase.rawValue >= StoreAggregateMigrationPhaseV1.awaitingIndependentValidation.rawValue {
            guard firstValidationProcessID != nil else { throw StoreMigrationFailure.invalidContract }
        } else if firstValidationProcessID != nil { throw StoreMigrationFailure.invalidContract }
        for processID in [publicationProcessID, firstValidationProcessID, secondValidationProcessID].compactMap({ $0 }) {
            guard processID != zero else { throw StoreMigrationFailure.invalidIdentity }
        }
        if phase == .complete {
            guard let secondValidationProcessID,
                  secondValidationProcessID != originatingProcessID,
                  secondValidationProcessID != publicationProcessID,
                  secondValidationProcessID != firstValidationProcessID else { throw StoreMigrationFailure.invalidContract }
        } else if secondValidationProcessID != nil { throw StoreMigrationFailure.invalidContract }
    }

    func validateReplacement(of previous: Self) throws {
        try previous.validate(); try validate()
        guard revision == previous.revision + 1, schemaVersion == previous.schemaVersion,
              upgradeID == previous.upgradeID, sourceGenerationID == previous.sourceGenerationID,
              sourceRelease == previous.sourceRelease, originalPointerData == previous.originalPointerData,
              sourceRootDevice == previous.sourceRootDevice, sourceRootInode == previous.sourceRootInode,
              activationManifestSHA256 == previous.activationManifestSHA256, migrationID == previous.migrationID,
              targetGenerationID == previous.targetGenerationID, targetRelease == previous.targetRelease,
              workspaceID == previous.workspaceID, replicaID == previous.replicaID, knownReplicaIDs == previous.knownReplicaIDs,
              originatingProcessID == previous.originatingProcessID,
              phase.rawValue >= previous.phase.rawValue, phase.rawValue <= previous.phase.rawValue + 1,
              previous.sourceCheckpoint.map({ sourceCheckpoint == $0 }) ?? true,
              previous.candidateRootDevice.map({ candidateRootDevice == $0 }) ?? true,
              previous.candidateRootInode.map({ candidateRootInode == $0 }) ?? true,
              previous.allocationID.map({ allocationID == $0 }) ?? true,
              transitions.starts(with: previous.transitions), transitions.count <= previous.transitions.count + 1,
              previous.targetManifestSHA256.map({ targetManifestSHA256 == $0 }) ?? true,
              previous.desiredPointerData.map({ desiredPointerData == $0 }) ?? true,
              previous.publicationProcessID.map({ publicationProcessID == $0 }) ?? true,
              previous.firstValidationProcessID.map({ firstValidationProcessID == $0 }) ?? true else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        if ownerID != previous.ownerID {
            var transferred = previous
            transferred.ownerID = ownerID; transferred.revision = revision
            guard transferred == self else { throw StoreMigrationFailure.invalidPhaseTransition }
        }
        if let authorized = previous.authorizedTargetRelease {
            guard authorizedTargetRelease == authorized ||
                (authorizedTargetRelease == nil && transitions.count == previous.transitions.count + 1 && transitions.last?.targetRelease == authorized) else {
                throw StoreMigrationFailure.invalidPhaseTransition
            }
            if authorizedTargetRelease != nil {
                guard authorizedPriorMutationState == previous.authorizedPriorMutationState else {
                    throw StoreMigrationFailure.invalidPhaseTransition
                }
            }
        }
        if transitions.count != previous.transitions.count {
            guard let authorized = previous.authorizedTargetRelease,
                  transitions.last?.targetRelease == authorized,
                  transitions.last?.sourceRelease == previous.currentCandidateRelease,
                  authorizedTargetRelease == nil else { throw StoreMigrationFailure.invalidPhaseTransition }
        }
    }

    func canonicalData() throws -> Data { try validate(); return try StoreMigrationCanonicalJSONV1.encode(self) }
    static func decodeCanonical(from data: Data) throws -> Self {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(Self.self, from: data, validate: { try $0.validate() })
    }
}

struct StoreMigrationAwaitingValidationV1: Equatable, Sendable {
    let upgradeID: UUID
    let targetGenerationID: UUID
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
enum StoreAggregateMigrationFaultBoundaryV1: Error, CaseIterable, Equatable {
    case afterAllocationCreation, afterAllocationBinding, afterAllocationRenameBeforeSync, afterAllocationPublication
    case afterAdjacentMarkerSave, afterFinalCheckpointSave
}

@MainActor
final class StoreMigrationFailureInjection {
    private var pending: StoreMigrationFaultBoundaryV1?
    private var aggregatePending: StoreAggregateMigrationFaultBoundaryV1?
    private var aggregateTargetRelease: PersistentSchemaReleaseV1?

    init(failOnceAt boundary: StoreMigrationFaultBoundaryV1) {
        pending = boundary
    }

    init(aggregateFault boundary: StoreAggregateMigrationFaultBoundaryV1, targetRelease: PersistentSchemaReleaseV1? = nil) {
        aggregatePending = boundary
        aggregateTargetRelease = targetRelease
    }

    func reachAggregate(_ boundary: StoreAggregateMigrationFaultBoundaryV1, targetRelease: PersistentSchemaReleaseV1? = nil) throws {
        guard aggregatePending == boundary,
              aggregateTargetRelease == nil || aggregateTargetRelease == targetRelease else { return }
        aggregatePending = nil
        throw boundary
    }

    func removeFailure() {
        pending = nil
        aggregatePending = nil
    }

    func failNext(at boundary: StoreMigrationFaultBoundaryV1) {
        pending = boundary
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

enum C51ScheduleExceptionMigrationBoundaryV1 {
    static let sourceVersion = 37
    static let targetVersion = 38
    static let recordsVersion = 37
    static let persistentSchemaVersion = 38
    static let newDurableRows = ["ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"]
    static let backfillCreatesScheduleTruth = false
    static let downgradeRequiresRestoreCompatibleV37Export = true
    static let existingScheduleRowsRemainByteStable = true

    static func validate() -> Bool {
        sourceVersion == 37
            && targetVersion == 38
            && recordsVersion == 37
            && persistentSchemaVersion == 38
            && newDurableRows == ["ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"]
            && !backfillCreatesScheduleTruth
            && downgradeRequiresRestoreCompatibleV37Export
            && existingScheduleRowsRemainByteStable
    }
}

enum C34SceneNavigationStoreMigrationBoundaryV1 {
    static let migrationStageCount = 0
    static let migratesSceneSnapshot = false
    static func validate() -> Bool { migrationStageCount == 0 && !migratesSceneSnapshot && C34SceneNavigationPersistentSchemaBoundaryV1.validate() }
}
// C52_BOUNDARY_ANCHOR: v38-to-v39-service-request-migration
enum C52ServiceRequestMigrationBoundaryV1 {
    static let sourceVersion = 38
    static let targetVersion = 39
    static let recordsSchemaVersion = 38
    static let newlyAddedRowCount = 3
    static let sourceRowsMustBeEmpty = true
    static let migrationPreservesAllV38Bytes = true
    static let downgradeDisposition = "READ_ONLY_OR_FORWARD_FIX"
}
enum C53AssetServiceReliabilityMigrationBoundaryV1{static let sourceVersion=39,targetVersion=40,recordsSchemaVersion=39,newlyAddedRowCount=7,sourceRowsMustBeEmpty=true,derivedProjectionMigrated=false}

enum C05EvidenceCurationMigrationBoundaryV1 {
    static let sourcePersistentSchemaVersion = 42
    static let targetPersistentSchemaVersion = 43
    static let currentRecordsSchemaVersion = 42
    static let compatibleRecordsSchemaVersions = [41, 42]
    static let newlyAddedRows = [
        "EvidenceAssociationEventRowV1",
        "EvidenceSequenceRevisionRowV1",
    ]
    static let sourceRowsMustBeEmpty = true
    static let backfillCreatesEvidenceTruth = false

    static func validate() -> Bool {
        sourcePersistentSchemaVersion == 42
            && targetPersistentSchemaVersion == 43
            && currentRecordsSchemaVersion == 42
            && compatibleRecordsSchemaVersions == [41, 42]
            && newlyAddedRows.count == 2
            && sourceRowsMustBeEmpty
            && !backfillCreatesEvidenceTruth
    }
}

/// V44 adds one append-only canonical profile family.  A V43 store has no
/// profile rows to synthesize: the first profile is always an explicit writer
/// mutation, and every previously persisted report remains unchanged.
enum C04ShopReportProfileMigrationBoundaryV1 {
    static let sourcePersistentSchemaVersion = 43
    static let targetPersistentSchemaVersion = 44
    static let currentRecordsSchemaVersion = 43
    static let compatibleRecordsSchemaVersions = [42, 43]
    static let newlyAddedRows = ["ShopReportProfileRowV1"]
    static let sourceRowsMustBeEmpty = true
    static let backfillCreatesProfileTruth = false
    static let downgradeDisposition = "FORWARD_FIX_ONLY"

    static func validate() -> Bool {
        sourcePersistentSchemaVersion == 43
            && targetPersistentSchemaVersion == 44
            && currentRecordsSchemaVersion == 43
            && compatibleRecordsSchemaVersions == [42, 43]
            && newlyAddedRows == ["ShopReportProfileRowV1"]
            && sourceRowsMustBeEmpty
            && !backfillCreatesProfileTruth
            && downgradeDisposition == "FORWARD_FIX_ONLY"
    }
}

/// V45 adds the one canonical round-session history family.  A V44 store has
/// no rows to synthesize; the initial round session is always an explicit
/// accepted mutation, so migration remains additive and forward-only.
enum C05RoundSessionMigrationBoundaryV1 {
    static let sourcePersistentSchemaVersion = 44
    static let targetPersistentSchemaVersion = 45
    static let currentRecordsSchemaVersion = 44
    static let compatibleRecordsSchemaVersions = [43, 44]
    static let newlyAddedRows = ["RoundSessionRevisionRowV1"]
    static let sourceRowsMustBeEmpty = true
    static let backfillCreatesRoundSessionTruth = false
    static let downgradeDisposition = "FORWARD_FIX_ONLY"

    static func validate() -> Bool {
        sourcePersistentSchemaVersion == 44
            && targetPersistentSchemaVersion == 45
            && currentRecordsSchemaVersion == 44
            && compatibleRecordsSchemaVersions == [43, 44]
            && newlyAddedRows == ["RoundSessionRevisionRowV1"]
            && sourceRowsMustBeEmpty
            && !backfillCreatesRoundSessionTruth
            && downgradeDisposition == "FORWARD_FIX_ONLY"
    }
}

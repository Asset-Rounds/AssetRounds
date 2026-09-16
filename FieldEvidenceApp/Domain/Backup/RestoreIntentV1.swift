import CoreFoundation
import Foundation

enum RestoreIntentPhaseV1: String, CaseIterable, Codable, Sendable {
    case prepared
    case generationInstalled = "generation_installed"
    case pointerSwitched = "pointer_switched"
    case newGenerationValidated = "new_generation_validated"

    var isPublished: Bool {
        self == .pointerSwitched || self == .newGenerationValidated
    }
}

struct RestoreIntentV1: Equatable, Sendable {
    /// Milliseconds must remain distinguishable when represented as a Date.
    /// This covers more than 142,000 years on either side of the epoch.
    private static let maximumCanonicalTimestampMilliseconds = 4_503_599_627_370_496
    let newGenerationID: UUID
    let newGenerationRelativePath: String
    let oldGenerationID: UUID
    let phase: RestoreIntentPhaseV1
    let restoreID: UUID
    let schemaVersion: Int
    let stagingGenerationRelativePath: String
    let identity: RestoreIdentityV1?
    let cloneRetirementPlanSHA256: String?
    /// The one canonical replacement instant used to materialize tombstones.
    /// Released journals intentionally have no value: recovery must not invent
    /// an instant that was never durably bound.
    let replacementTimestampMilliseconds: Int?

    var replacementAt: Date? {
        replacementTimestampMilliseconds.flatMap(Self.date)
    }

    /// Compatibility initializer for released schema-V1 restore journals.
    init(
        newGenerationID: UUID,
        newGenerationRelativePath: String,
        oldGenerationID: UUID,
        phase: RestoreIntentPhaseV1,
        restoreID: UUID,
        schemaVersion: Int,
        stagingGenerationRelativePath: String,
        identity: RestoreIdentityV1? = nil,
        replacementTimestampMilliseconds: Int? = nil,
        cloneRetirementPlanSHA256: String? = nil
    ) {
        self.newGenerationID = newGenerationID
        self.newGenerationRelativePath = newGenerationRelativePath
        self.oldGenerationID = oldGenerationID
        self.phase = phase
        self.restoreID = restoreID
        self.schemaVersion = schemaVersion
        self.stagingGenerationRelativePath = stagingGenerationRelativePath
        self.identity = identity
        self.replacementTimestampMilliseconds = replacementTimestampMilliseconds
        self.cloneRetirementPlanSHA256 = cloneRetirementPlanSHA256
    }

    init(
        identity: RestoreIdentityV1,
        phase: RestoreIntentPhaseV1 = .prepared,
        restoreID: UUID,
        replacementTimestampMilliseconds: Int,
        cloneRetirementPlanSHA256: String? = nil
    ) {
        newGenerationID = identity.targetPointer.generationID
        newGenerationRelativePath = "FieldEvidenceData/generations/\(Self.canonical(identity.targetPointer.generationID))"
        oldGenerationID = identity.oldPointer.generationID
        self.phase = phase
        self.restoreID = restoreID
        schemaVersion = cloneRetirementPlanSHA256 == nil ? 3 : 4
        stagingGenerationRelativePath = "FieldEvidenceRestore/generations/\(Self.canonical(identity.targetPointer.generationID))"
        self.identity = identity
        self.replacementTimestampMilliseconds = replacementTimestampMilliseconds
        self.cloneRetirementPlanSHA256 = cloneRetirementPlanSHA256
    }

    func advancing(to phase: RestoreIntentPhaseV1) -> RestoreIntentV1 {
        RestoreIntentV1(
            newGenerationID: newGenerationID,
            newGenerationRelativePath: newGenerationRelativePath,
            oldGenerationID: oldGenerationID,
            phase: phase,
            restoreID: restoreID,
            schemaVersion: schemaVersion,
            stagingGenerationRelativePath: stagingGenerationRelativePath,
            identity: identity,
            replacementTimestampMilliseconds: replacementTimestampMilliseconds,
            cloneRetirementPlanSHA256: cloneRetirementPlanSHA256
        )
    }

    static func canonicalReplacementTimestampMilliseconds(_ value: Date) -> Int? {
        let raw = value.timeIntervalSince1970 * 1_000
        guard raw.isFinite,
              raw >= -Double(maximumCanonicalTimestampMilliseconds),
              raw <= Double(maximumCanonicalTimestampMilliseconds) else {
            return nil
        }
        let milliseconds = Int(raw.rounded())
        guard date(milliseconds) != nil else { return nil }
        return milliseconds
    }

    static func date(_ milliseconds: Int) -> Date? {
        guard milliseconds >= -maximumCanonicalTimestampMilliseconds,
              milliseconds <= maximumCanonicalTimestampMilliseconds else {
            return nil
        }
        let seconds = TimeInterval(milliseconds) / 1_000
        guard seconds.isFinite else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

enum RestoreIntentContractErrorV1: Error, Equatable {
    case invalidIntent
}

enum RestoreIntentCodecV1 {
    private static let legacyKeys = Set([
        "newGenerationID",
        "newGenerationRelativePath",
        "oldGenerationID",
        "phase",
        "restoreID",
        "schemaVersion",
        "stagingGenerationRelativePath",
    ])
    private static let v2Keys = legacyKeys.union(["identity"])
    private static let v3Keys = v2Keys.union(["replacementTimestampMilliseconds"])
    private static let v4Keys = v3Keys.union(["cloneRetirementPlanSHA256"])
    private static let identityKeys = Set([
        "mode",
        "oldPointer",
        "recordIdentityDisposition",
        "source",
        "targetPointer",
    ])
    private static let pointerKeys = Set([
        "generationID",
        "generationManifestSHA256",
        "knownReplicaIDs",
        "replicaID",
        "workspaceID",
    ])
    private static let sourceKeys = Set(["replicaID", "workspaceID"])

    static func encode(_ value: RestoreIntentV1) throws -> Data {
        guard valid(value) else {
            throw RestoreIntentContractErrorV1.invalidIntent
        }
        var object: [String: CanonicalJSONValueV1] = [
            "newGenerationID": .string(canonical(value.newGenerationID)),
            "newGenerationRelativePath": .string(value.newGenerationRelativePath),
            "oldGenerationID": .string(canonical(value.oldGenerationID)),
            "phase": .string(value.phase.rawValue),
            "restoreID": .string(canonical(value.restoreID)),
            "schemaVersion": .integer(value.schemaVersion),
            "stagingGenerationRelativePath": .string(
                value.stagingGenerationRelativePath
            ),
        ]
        if let identity = value.identity {
            object["identity"] = identityJSON(identity)
        } else if value.schemaVersion == 3 || value.schemaVersion == 4 {
            object["identity"] = .null
        }
        if let replacementTimestampMilliseconds = value.replacementTimestampMilliseconds {
            object["replacementTimestampMilliseconds"] = .integer(
                replacementTimestampMilliseconds
            )
        }
        if value.schemaVersion == 4 {
            object["cloneRetirementPlanSHA256"] = value.cloneRetirementPlanSHA256.map {
                .string($0)
            } ?? .null
        }
        return try CanonicalJSONV1.encode(.object(object))
    }

    static func decode(_ data: Data) throws -> RestoreIntentV1 {
        guard let object = try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any],
              let schemaVersion = exactInteger(object["schemaVersion"]) else {
            throw RestoreIntentContractErrorV1.invalidIntent
        }
        let expectedKeys: Set<String>
        switch schemaVersion {
        case 1: expectedKeys = legacyKeys
        case 2: expectedKeys = v2Keys
        case 3: expectedKeys = v3Keys
        case 4: expectedKeys = v4Keys
        default: throw RestoreIntentContractErrorV1.invalidIntent
        }
        guard Set(object.keys) == expectedKeys,
              object.count == expectedKeys.count,
              let newGenerationID = canonicalUUID(object["newGenerationID"]),
              let newGenerationRelativePath = object["newGenerationRelativePath"]
                as? String,
              let oldGenerationID = canonicalUUID(object["oldGenerationID"]),
              let phaseValue = object["phase"] as? String,
              let phase = RestoreIntentPhaseV1(rawValue: phaseValue),
              let restoreID = canonicalUUID(object["restoreID"]),
              let stagingGenerationRelativePath = object[
                "stagingGenerationRelativePath"
              ] as? String else {
            throw RestoreIntentContractErrorV1.invalidIntent
        }
        let identity: RestoreIdentityV1?
        if schemaVersion == 2 {
            guard let decoded = decodeIdentity(object["identity"]) else {
                throw RestoreIntentContractErrorV1.invalidIntent
            }
            identity = decoded
        } else if schemaVersion == 3 || schemaVersion == 4 {
            if object["identity"] is NSNull {
                identity = nil
            } else {
                guard let decoded = decodeIdentity(object["identity"]) else {
                    throw RestoreIntentContractErrorV1.invalidIntent
                }
                identity = decoded
            }
        } else {
            identity = nil
        }
        let replacementTimestampMilliseconds: Int?
        if schemaVersion == 3 || schemaVersion == 4 {
            guard let timestamp = exactInteger(
                object["replacementTimestampMilliseconds"]
            ), RestoreIntentV1.date(timestamp) != nil else {
                throw RestoreIntentContractErrorV1.invalidIntent
            }
            replacementTimestampMilliseconds = timestamp
        } else {
            replacementTimestampMilliseconds = nil
        }
        let cloneRetirementPlanSHA256: String?
        if schemaVersion == 4 {
            guard let decoded = nullableSHA256(
                object["cloneRetirementPlanSHA256"]
            ) else {
                throw RestoreIntentContractErrorV1.invalidIntent
            }
            cloneRetirementPlanSHA256 = decoded
        } else {
            cloneRetirementPlanSHA256 = nil
        }
        let value = RestoreIntentV1(
            newGenerationID: newGenerationID,
            newGenerationRelativePath: newGenerationRelativePath,
            oldGenerationID: oldGenerationID,
            phase: phase,
            restoreID: restoreID,
            schemaVersion: schemaVersion,
            stagingGenerationRelativePath: stagingGenerationRelativePath,
            identity: identity,
            replacementTimestampMilliseconds: replacementTimestampMilliseconds,
            cloneRetirementPlanSHA256: cloneRetirementPlanSHA256
        )
        guard try encode(value) == data else {
            throw RestoreIntentContractErrorV1.invalidIntent
        }
        return value
    }

    static func valid(_ value: RestoreIntentV1) -> Bool {
        let newID = canonical(value.newGenerationID)
        guard value.newGenerationID != value.oldGenerationID,
              value.newGenerationID != value.restoreID,
              value.oldGenerationID != value.restoreID,
              value.newGenerationRelativePath
                == "FieldEvidenceData/generations/\(newID)",
              value.stagingGenerationRelativePath
                == "FieldEvidenceRestore/generations/\(newID)" else {
            return false
        }
        switch value.schemaVersion {
        case 1:
            return value.identity == nil
                && value.replacementTimestampMilliseconds == nil
                && value.cloneRetirementPlanSHA256 == nil
        case 2:
            guard let identity = value.identity,
                  value.replacementTimestampMilliseconds == nil,
                  value.cloneRetirementPlanSHA256 == nil else { return false }
            return identity.oldPointer.generationID == value.oldGenerationID
                && identity.targetPointer.generationID == value.newGenerationID
                && validPointer(identity.oldPointer)
                && validPointer(identity.targetPointer)
                && validIdentity(identity)
        case 3:
            guard let timestamp = value.replacementTimestampMilliseconds,
                  RestoreIntentV1.date(timestamp) != nil,
                  value.cloneRetirementPlanSHA256 == nil else { return false }
            guard let identity = value.identity else {
                return true
            }
            return identity.oldPointer.generationID == value.oldGenerationID
                && identity.targetPointer.generationID == value.newGenerationID
                && validPointer(identity.oldPointer)
                && validPointer(identity.targetPointer)
                && validIdentity(identity)
        case 4:
            guard let timestamp = value.replacementTimestampMilliseconds,
                  RestoreIntentV1.date(timestamp) != nil else { return false }
            if let digest = value.cloneRetirementPlanSHA256 {
                guard validSHA256(digest), value.identity?.mode == .clone else {
                    return false
                }
            } else if value.identity?.mode == .clone {
                return false
            }
            guard let identity = value.identity else {
                return true
            }
            return identity.oldPointer.generationID == value.oldGenerationID
                && identity.targetPointer.generationID == value.newGenerationID
                && validPointer(identity.oldPointer)
                && validPointer(identity.targetPointer)
                && validIdentity(identity)
        default:
            return false
        }
    }
}

private extension RestoreIntentCodecV1 {
    static func identityJSON(
        _ value: RestoreIdentityV1
    ) -> CanonicalJSONValueV1 {
        return .object([
            "mode": .string(value.mode.rawValue),
            "oldPointer": pointerJSON(value.oldPointer),
            "recordIdentityDisposition": .string(
                value.recordIdentityDisposition.rawValue
            ),
            "source": .object([
                "replicaID": value.source.replicaID.map {
                    .string(canonical($0))
                } ?? .null,
                "workspaceID": value.source.workspaceID.map {
                    .string(canonical($0))
                } ?? .null,
            ]),
            "targetPointer": pointerJSON(value.targetPointer),
        ])
    }

    static func pointerJSON(
        _ value: RestorePointerIdentityV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "generationID": .string(canonical(value.generationID)),
            "generationManifestSHA256": .string(
                value.generationManifestSHA256
            ),
            "knownReplicaIDs": .array(value.knownReplicaIDs.map {
                .string(canonical($0))
            }),
            "replicaID": .string(canonical(value.replicaID)),
            "workspaceID": .string(canonical(value.workspaceID)),
        ])
    }

    static func decodeIdentity(_ raw: Any?) -> RestoreIdentityV1? {
        guard let object = exactObject(raw, keys: identityKeys),
              let modeRaw = object["mode"] as? String,
              let mode = BackupRestoreMode(rawValue: modeRaw),
              let dispositionRaw = object["recordIdentityDisposition"] as? String,
              let disposition = RestoreRecordIdentityDispositionV1(
                rawValue: dispositionRaw
              ),
              let oldPointer = decodePointer(object["oldPointer"]),
              let targetPointer = decodePointer(object["targetPointer"]),
              let sourceObject = exactObject(
                object["source"],
                keys: sourceKeys
              ),
              let sourceWorkspaceID = nullableCanonicalUUID(
                sourceObject["workspaceID"]
              ),
              let sourceReplicaID = nullableCanonicalUUID(
                sourceObject["replicaID"]
              ) else {
            return nil
        }
        return RestoreIdentityV1(
            mode: mode,
            source: RestoreSourceIdentityV1(
                workspaceID: sourceWorkspaceID,
                replicaID: sourceReplicaID
            ),
            oldPointer: oldPointer,
            targetPointer: targetPointer,
            recordIdentityDisposition: disposition
        )
    }

    static func decodePointer(_ raw: Any?) -> RestorePointerIdentityV1? {
        guard let object = exactObject(raw, keys: pointerKeys),
              let generationID = canonicalUUID(object["generationID"]),
              let digest = object["generationManifestSHA256"] as? String,
              let rawKnownReplicaIDs = object["knownReplicaIDs"] as? [Any],
              let replicaID = canonicalUUID(object["replicaID"]),
              let workspaceID = canonicalUUID(object["workspaceID"]) else {
            return nil
        }
        let knownReplicaIDs = rawKnownReplicaIDs.compactMap(canonicalUUID)
        guard knownReplicaIDs.count == rawKnownReplicaIDs.count,
              knownReplicaIDs == knownReplicaIDs.sorted(by: {
                  canonical($0) < canonical($1)
              }),
              Set(knownReplicaIDs).count == knownReplicaIDs.count else {
            return nil
        }
        return RestorePointerIdentityV1(
            generationID: generationID,
            generationManifestSHA256: digest,
            knownReplicaIDs: Set(knownReplicaIDs),
            workspaceID: workspaceID,
            replicaID: replicaID
        )
    }

    static func validIdentity(_ value: RestoreIdentityV1) -> Bool {
        guard let sourceWorkspaceID = value.source.workspaceID,
              let sourceReplicaID = value.source.replicaID,
              sourceWorkspaceID != sourceReplicaID,
              value.targetPointer.replicaID != sourceReplicaID,
              value.targetPointer.knownReplicaIDs.contains(sourceReplicaID),
              Set(value.targetPointer.knownReplicaIDs).isSuperset(
                  of: Set(value.oldPointer.knownReplicaIDs)
              ) else {
            return false
        }
        switch value.mode {
        case .emptyInstall:
            return value.targetPointer.workspaceID == sourceWorkspaceID
                && value.recordIdentityDisposition == .preserve
        case .replaceExisting:
            return value.targetPointer.workspaceID
                    == value.oldPointer.workspaceID
                && value.recordIdentityDisposition == .preserve
        case .clone:
            return value.targetPointer.workspaceID != sourceWorkspaceID
                && value.targetPointer.workspaceID
                    != value.oldPointer.workspaceID
                && value.recordIdentityDisposition == .preserve
        case .fork:
            return value.targetPointer.workspaceID != sourceWorkspaceID
                && value.targetPointer.workspaceID
                    != value.oldPointer.workspaceID
                && value.recordIdentityDisposition == .preserve
        }
    }

    static func validPointer(_ value: RestorePointerIdentityV1) -> Bool {
        value.generationID != value.workspaceID
            && value.generationID != value.replicaID
            && value.workspaceID != value.replicaID
            && !value.knownReplicaIDs.isEmpty
            && value.knownReplicaIDs.count <= 64
            && value.knownReplicaIDs == value.knownReplicaIDs.sorted(by: {
                canonical($0) < canonical($1)
            })
            && Set(value.knownReplicaIDs).count == value.knownReplicaIDs.count
            && value.knownReplicaIDs.contains(value.replicaID)
            && validSHA256(value.generationManifestSHA256)
    }

    static func validSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                (48...57).contains(Int($0.value))
                    || (97...102).contains(Int($0.value))
            }
    }

    /// Outer optional distinguishes malformed values from canonical JSON null.
    static func nullableSHA256(_ raw: Any?) -> String?? {
        if raw is NSNull { return .some(nil) }
        guard let value = raw as? String, validSHA256(value) else { return nil }
        return .some(value)
    }

    static func exactObject(
        _ raw: Any?,
        keys: Set<String>
    ) -> [String: Any]? {
        guard let object = raw as? [String: Any],
              Set(object.keys) == keys,
              object.count == keys.count else {
            return nil
        }
        return object
    }

    /// Outer optional distinguishes malformed from canonical JSON null.
    static func nullableCanonicalUUID(_ raw: Any?) -> UUID?? {
        if raw is NSNull { return .some(nil) }
        guard let value = canonicalUUID(raw) else { return nil }
        return .some(value)
    }

    static func exactInteger(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue >= Double(Int.min),
              number.doubleValue < Double(Int.max),
              number.doubleValue == Double(number.intValue) else {
            return nil
        }
        return number.intValue
    }

    static func canonicalUUID(_ value: Any?) -> UUID? {
        guard let string = value as? String,
              let value = UUID(uuidString: string),
              canonical(value) == string else {
            return nil
        }
        return value
    }

    static func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

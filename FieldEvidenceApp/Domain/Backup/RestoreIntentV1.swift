import CoreFoundation
import Foundation

enum RestoreIntentPhaseV1: String, CaseIterable, Codable, Sendable {
    case prepared
    case generationInstalled = "generation_installed"
    case pointerSwitched = "pointer_switched"
    case newGenerationValidated = "new_generation_validated"
}

struct RestoreIntentV1: Equatable, Sendable {
    let newGenerationID: UUID
    let newGenerationRelativePath: String
    let oldGenerationID: UUID
    let phase: RestoreIntentPhaseV1
    let restoreID: UUID
    let schemaVersion: Int
    let stagingGenerationRelativePath: String

    func advancing(to phase: RestoreIntentPhaseV1) -> RestoreIntentV1 {
        RestoreIntentV1(
            newGenerationID: newGenerationID,
            newGenerationRelativePath: newGenerationRelativePath,
            oldGenerationID: oldGenerationID,
            phase: phase,
            restoreID: restoreID,
            schemaVersion: schemaVersion,
            stagingGenerationRelativePath: stagingGenerationRelativePath
        )
    }
}

enum RestoreIntentContractErrorV1: Error, Equatable {
    case invalidIntent
}

enum RestoreIntentCodecV1 {
    private static let keys = Set([
        "newGenerationID",
        "newGenerationRelativePath",
        "oldGenerationID",
        "phase",
        "restoreID",
        "schemaVersion",
        "stagingGenerationRelativePath",
    ])

    static func encode(_ value: RestoreIntentV1) throws -> Data {
        guard valid(value) else {
            throw RestoreIntentContractErrorV1.invalidIntent
        }
        return try CanonicalJSONV1.encode(.object([
            "newGenerationID": .string(canonical(value.newGenerationID)),
            "newGenerationRelativePath": .string(value.newGenerationRelativePath),
            "oldGenerationID": .string(canonical(value.oldGenerationID)),
            "phase": .string(value.phase.rawValue),
            "restoreID": .string(canonical(value.restoreID)),
            "schemaVersion": .integer(value.schemaVersion),
            "stagingGenerationRelativePath": .string(
                value.stagingGenerationRelativePath
            ),
        ]))
    }

    static func decode(_ data: Data) throws -> RestoreIntentV1 {
        guard let object = try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any],
              Set(object.keys) == keys,
              object.count == keys.count,
              let newGenerationID = canonicalUUID(object["newGenerationID"]),
              let newGenerationRelativePath = object["newGenerationRelativePath"]
                as? String,
              let oldGenerationID = canonicalUUID(object["oldGenerationID"]),
              let phaseValue = object["phase"] as? String,
              let phase = RestoreIntentPhaseV1(rawValue: phaseValue),
              let restoreID = canonicalUUID(object["restoreID"]),
              let schemaNumber = object["schemaVersion"] as? NSNumber,
              CFGetTypeID(schemaNumber) != CFBooleanGetTypeID(),
              schemaNumber.intValue == 1,
              schemaNumber.doubleValue == 1,
              let stagingGenerationRelativePath = object[
                "stagingGenerationRelativePath"
              ] as? String else {
            throw RestoreIntentContractErrorV1.invalidIntent
        }
        let value = RestoreIntentV1(
            newGenerationID: newGenerationID,
            newGenerationRelativePath: newGenerationRelativePath,
            oldGenerationID: oldGenerationID,
            phase: phase,
            restoreID: restoreID,
            schemaVersion: 1,
            stagingGenerationRelativePath: stagingGenerationRelativePath
        )
        guard try encode(value) == data else {
            throw RestoreIntentContractErrorV1.invalidIntent
        }
        return value
    }

    static func valid(_ value: RestoreIntentV1) -> Bool {
        let newID = canonical(value.newGenerationID)
        return value.schemaVersion == 1
            && value.newGenerationID != value.oldGenerationID
            && value.newGenerationID != value.restoreID
            && value.oldGenerationID != value.restoreID
            && value.newGenerationRelativePath
                == "FieldEvidenceData/generations/\(newID)"
            && value.stagingGenerationRelativePath
                == "FieldEvidenceRestore/generations/\(newID)"
    }

    private static func canonicalUUID(_ value: Any?) -> UUID? {
        guard let string = value as? String,
              let value = UUID(uuidString: string),
              canonical(value) == string else {
            return nil
        }
        return value
    }

    private static func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

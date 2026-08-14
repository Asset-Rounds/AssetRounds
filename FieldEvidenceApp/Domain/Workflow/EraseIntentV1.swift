import CoreFoundation
import Foundation

enum EraseIntentPhaseV1: String, CaseIterable, Codable, Sendable {
    case emptyGenerationPrepared = "empty_generation_prepared"
    case pointerSwitched = "pointer_switched"
    case sessionActivated = "session_activated"
    case cleanupComplete = "cleanup_complete"
}

struct EraseIntentV1: Equatable, Sendable {
    static let canonicalAuxiliaryRoots = [
        "FieldEvidenceRestore/",
        "FieldEvidenceOperations/",
        "FieldEvidenceCommerce/",
        "FieldEvidenceDiagnostics/",
        "Library/Caches/FieldEvidenceApp/",
        "tmp/FieldEvidenceApp/",
        "UserDefaults/com.palatis3.fieldrecord",
    ]

    let auxiliaryRoots: [String]
    let eraseID: UUID
    let generationIDsToDelete: [UUID]
    let newGenerationID: UUID
    let oldGenerationID: UUID
    let phase: EraseIntentPhaseV1
    let schemaVersion: Int

    func advancing(to phase: EraseIntentPhaseV1) -> EraseIntentV1 {
        EraseIntentV1(
            auxiliaryRoots: auxiliaryRoots,
            eraseID: eraseID,
            generationIDsToDelete: generationIDsToDelete,
            newGenerationID: newGenerationID,
            oldGenerationID: oldGenerationID,
            phase: phase,
            schemaVersion: schemaVersion
        )
    }
}

enum EraseIntentContractErrorV1: Error, Equatable {
    case invalidIntent
}

enum EraseIntentCodecV1 {
    private static let keys = Set([
        "auxiliaryRoots",
        "eraseID",
        "generationIDsToDelete",
        "newGenerationID",
        "oldGenerationID",
        "phase",
        "schemaVersion",
    ])

    static func encode(_ value: EraseIntentV1) throws -> Data {
        guard valid(value) else {
            throw EraseIntentContractErrorV1.invalidIntent
        }
        return try CanonicalJSONV1.encode(.object([
            "auxiliaryRoots": .array(
                value.auxiliaryRoots.map { .string($0) }
            ),
            "eraseID": .string(canonical(value.eraseID)),
            "generationIDsToDelete": .array(
                value.generationIDsToDelete.map {
                    .string(canonical($0))
                }
            ),
            "newGenerationID": .string(canonical(value.newGenerationID)),
            "oldGenerationID": .string(canonical(value.oldGenerationID)),
            "phase": .string(value.phase.rawValue),
            "schemaVersion": .integer(value.schemaVersion),
        ]))
    }

    static func decode(_ data: Data) throws -> EraseIntentV1 {
        guard let object = try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any],
              Set(object.keys) == keys,
              object.count == keys.count,
              let auxiliaryRoots = object["auxiliaryRoots"] as? [String],
              let eraseID = canonicalUUID(object["eraseID"]),
              let generationValues = object["generationIDsToDelete"] as? [Any],
              let generationIDsToDelete = canonicalUUIDs(generationValues),
              let newGenerationID = canonicalUUID(object["newGenerationID"]),
              let oldGenerationID = canonicalUUID(object["oldGenerationID"]),
              let phaseValue = object["phase"] as? String,
              let phase = EraseIntentPhaseV1(rawValue: phaseValue),
              let schemaNumber = object["schemaVersion"] as? NSNumber,
              CFGetTypeID(schemaNumber) != CFBooleanGetTypeID(),
              schemaNumber.intValue == 1,
              schemaNumber.doubleValue == 1 else {
            throw EraseIntentContractErrorV1.invalidIntent
        }
        let value = EraseIntentV1(
            auxiliaryRoots: auxiliaryRoots,
            eraseID: eraseID,
            generationIDsToDelete: generationIDsToDelete,
            newGenerationID: newGenerationID,
            oldGenerationID: oldGenerationID,
            phase: phase,
            schemaVersion: 1
        )
        guard try encode(value) == data else {
            throw EraseIntentContractErrorV1.invalidIntent
        }
        return value
    }

    static func valid(_ value: EraseIntentV1) -> Bool {
        let generationIDs = value.generationIDsToDelete
        return value.schemaVersion == 1
            && value.auxiliaryRoots == EraseIntentV1.canonicalAuxiliaryRoots
            && value.newGenerationID != value.oldGenerationID
            && value.eraseID != value.newGenerationID
            && value.eraseID != value.oldGenerationID
            && generationIDs.contains(value.oldGenerationID)
            && !generationIDs.contains(value.newGenerationID)
            && !generationIDs.contains(value.eraseID)
            && Set(generationIDs).count == generationIDs.count
            && generationIDs == generationIDs.sorted(by: idOrder)
    }

    private static func canonicalUUIDs(_ values: [Any]) -> [UUID]? {
        var result: [UUID] = []
        result.reserveCapacity(values.count)
        for value in values {
            guard let id = canonicalUUID(value) else { return nil }
            result.append(id)
        }
        return result
    }

    private static func canonicalUUID(_ value: Any?) -> UUID? {
        guard let string = value as? String,
              let value = UUID(uuidString: string),
              canonical(value) == string else {
            return nil
        }
        return value
    }

    private static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        canonical(lhs) < canonical(rhs)
    }

    private static func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

import CoreFoundation
import Foundation

enum FunctionalRelationshipEraseBoundaryV1 {
    static let descriptorAndEventRowsAreClearedOnlyWithWorkspaceErase = true
    static let ordinaryEndpointDeletionPreservesRows = true

    static func validate() -> Bool {
        descriptorAndEventRowsAreClearedOnlyWithWorkspaceErase
            && ordinaryEndpointDeletionPreservesRows
    }
}

enum EvidenceAssuranceEraseBoundaryV1 {
    static let immutableHistoryClearedOnlyByWorkspaceErase = true
    static let ordinaryDeletionIsZeroWrite = true
}

enum EraseIntentPhaseV1: String, CaseIterable, Codable, Sendable {
    case emptyGenerationPrepared = "empty_generation_prepared"
    case pointerSwitched = "pointer_switched"
    case sessionActivated = "session_activated"
    case cleanupComplete = "cleanup_complete"
}

struct EraseEmptyGenerationProofV2: Equatable, Sendable {
    let contentRecordCount: Int
    let deletionLedgerEntryCount: Int
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
    let oldPointer: RestorePointerIdentityV1?
    let phase: EraseIntentPhaseV1
    let schemaVersion: Int
    let sourceLedger: DeletionLedgerProofV2?
    let targetEmptyProof: EraseEmptyGenerationProofV2?
    let targetPointer: RestorePointerIdentityV1?

    init(
        auxiliaryRoots: [String],
        eraseID: UUID,
        generationIDsToDelete: [UUID],
        newGenerationID: UUID,
        oldGenerationID: UUID,
        phase: EraseIntentPhaseV1,
        schemaVersion: Int,
        oldPointer: RestorePointerIdentityV1? = nil,
        sourceLedger: DeletionLedgerProofV2? = nil,
        targetEmptyProof: EraseEmptyGenerationProofV2? = nil,
        targetPointer: RestorePointerIdentityV1? = nil
    ) {
        self.auxiliaryRoots = auxiliaryRoots
        self.eraseID = eraseID
        self.generationIDsToDelete = generationIDsToDelete
        self.newGenerationID = newGenerationID
        self.oldGenerationID = oldGenerationID
        self.oldPointer = oldPointer
        self.phase = phase
        self.schemaVersion = schemaVersion
        self.sourceLedger = sourceLedger
        self.targetEmptyProof = targetEmptyProof
        self.targetPointer = targetPointer
    }

    func advancing(to phase: EraseIntentPhaseV1) -> EraseIntentV1 {
        EraseIntentV1(
            auxiliaryRoots: auxiliaryRoots,
            eraseID: eraseID,
            generationIDsToDelete: generationIDsToDelete,
            newGenerationID: newGenerationID,
            oldGenerationID: oldGenerationID,
            phase: phase,
            schemaVersion: schemaVersion,
            oldPointer: oldPointer,
            sourceLedger: sourceLedger,
            targetEmptyProof: targetEmptyProof,
            targetPointer: targetPointer
        )
    }
}

enum EraseIntentContractErrorV1: Error, Equatable {
    case invalidIntent
}

enum EraseIntentCodecV1 {
    private static let legacyKeys = Set([
        "auxiliaryRoots",
        "eraseID",
        "generationIDsToDelete",
        "newGenerationID",
        "oldGenerationID",
        "phase",
        "schemaVersion",
    ])
    private static let v2Keys = legacyKeys.union([
        "oldPointer",
        "sourceLedger",
        "targetEmptyProof",
        "targetPointer",
    ])
    private static let pointerKeys = Set([
        "generationID",
        "generationManifestSHA256",
        "knownReplicaIDs",
        "replicaID",
        "workspaceID",
    ])
    private static let ledgerProofKeys = Set([
        "canonicalSHA256",
        "entryCount",
    ])
    private static let emptyProofKeys = Set([
        "contentRecordCount",
        "deletionLedgerEntryCount",
    ])

    static func encode(_ value: EraseIntentV1) throws -> Data {
        guard valid(value) else {
            throw EraseIntentContractErrorV1.invalidIntent
        }
        var object: [String: CanonicalJSONValueV1] = [
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
        ]
        if value.schemaVersion == 2,
           let oldPointer = value.oldPointer,
           let sourceLedger = value.sourceLedger,
           let targetEmptyProof = value.targetEmptyProof,
           let targetPointer = value.targetPointer {
            object["oldPointer"] = pointerJSON(oldPointer)
            object["sourceLedger"] = .object([
                "canonicalSHA256": .string(sourceLedger.canonicalSHA256),
                "entryCount": .integer(sourceLedger.entryCount),
            ])
            object["targetEmptyProof"] = .object([
                "contentRecordCount": .integer(
                    targetEmptyProof.contentRecordCount
                ),
                "deletionLedgerEntryCount": .integer(
                    targetEmptyProof.deletionLedgerEntryCount
                ),
            ])
            object["targetPointer"] = pointerJSON(targetPointer)
        }
        return try CanonicalJSONV1.encode(.object(object))
    }

    static func decode(_ data: Data) throws -> EraseIntentV1 {
        guard let object = try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any],
              let schemaNumber = object["schemaVersion"] as? NSNumber,
              CFGetTypeID(schemaNumber) != CFBooleanGetTypeID(),
              (schemaNumber.intValue == 1 || schemaNumber.intValue == 2),
              schemaNumber.doubleValue == Double(schemaNumber.intValue),
              Set(object.keys) == (schemaNumber.intValue == 1
                  ? legacyKeys
                  : v2Keys),
              let auxiliaryRoots = object["auxiliaryRoots"] as? [String],
              let eraseID = canonicalUUID(object["eraseID"]),
              let generationValues = object["generationIDsToDelete"] as? [Any],
              let generationIDsToDelete = canonicalUUIDs(generationValues),
              let newGenerationID = canonicalUUID(object["newGenerationID"]),
              let oldGenerationID = canonicalUUID(object["oldGenerationID"]),
              let phaseValue = object["phase"] as? String,
              let phase = EraseIntentPhaseV1(rawValue: phaseValue) else {
            throw EraseIntentContractErrorV1.invalidIntent
        }
        let oldPointer: RestorePointerIdentityV1?
        let sourceLedger: DeletionLedgerProofV2?
        let targetEmptyProof: EraseEmptyGenerationProofV2?
        let targetPointer: RestorePointerIdentityV1?
        if schemaNumber.intValue == 2 {
            guard let decodedOldPointer = decodePointer(object["oldPointer"]),
                  let decodedSourceLedger = decodeLedgerProof(
                      object["sourceLedger"]
                  ),
                  let decodedTargetEmptyProof = decodeEmptyProof(
                      object["targetEmptyProof"]
                  ),
                  let decodedTargetPointer = decodePointer(
                      object["targetPointer"]
                  ) else {
                throw EraseIntentContractErrorV1.invalidIntent
            }
            oldPointer = decodedOldPointer
            sourceLedger = decodedSourceLedger
            targetEmptyProof = decodedTargetEmptyProof
            targetPointer = decodedTargetPointer
        } else {
            oldPointer = nil
            sourceLedger = nil
            targetEmptyProof = nil
            targetPointer = nil
        }
        let value = EraseIntentV1(
            auxiliaryRoots: auxiliaryRoots,
            eraseID: eraseID,
            generationIDsToDelete: generationIDsToDelete,
            newGenerationID: newGenerationID,
            oldGenerationID: oldGenerationID,
            phase: phase,
            schemaVersion: schemaNumber.intValue,
            oldPointer: oldPointer,
            sourceLedger: sourceLedger,
            targetEmptyProof: targetEmptyProof,
            targetPointer: targetPointer
        )
        guard try encode(value) == data else {
            throw EraseIntentContractErrorV1.invalidIntent
        }
        return value
    }

    static func valid(_ value: EraseIntentV1) -> Bool {
        let generationIDs = value.generationIDsToDelete
        guard value.auxiliaryRoots == EraseIntentV1.canonicalAuxiliaryRoots
            && value.newGenerationID != value.oldGenerationID
            && value.eraseID != value.newGenerationID
            && value.eraseID != value.oldGenerationID
            && generationIDs.contains(value.oldGenerationID)
            && !generationIDs.contains(value.newGenerationID)
            && !generationIDs.contains(value.eraseID)
            && Set(generationIDs).count == generationIDs.count
            && generationIDs == generationIDs.sorted(by: idOrder) else {
            return false
        }
        switch value.schemaVersion {
        case 1:
            return value.oldPointer == nil
                && value.sourceLedger == nil
                && value.targetEmptyProof == nil
                && value.targetPointer == nil
        case 2:
            guard let oldPointer = value.oldPointer,
                  let sourceLedger = value.sourceLedger,
                  let targetEmptyProof = value.targetEmptyProof,
                  let targetPointer = value.targetPointer else {
                return false
            }
            return oldPointer.generationID == value.oldGenerationID
                && targetPointer.generationID == value.newGenerationID
                && validPointer(oldPointer)
                && validPointer(targetPointer)
                && targetPointer.workspaceID != oldPointer.generationID
                && targetPointer.replicaID != oldPointer.generationID
                && targetPointer.generationID != oldPointer.workspaceID
                && targetPointer.generationID != oldPointer.replicaID
                && targetPointer.workspaceID != oldPointer.workspaceID
                && targetPointer.workspaceID != oldPointer.replicaID
                && targetPointer.replicaID != oldPointer.workspaceID
                && targetPointer.replicaID != oldPointer.replicaID
                && !oldPointer.knownReplicaIDs.contains(
                    targetPointer.generationID
                )
                && !oldPointer.knownReplicaIDs.contains(
                    targetPointer.workspaceID
                )
                && !oldPointer.knownReplicaIDs.contains(
                    targetPointer.replicaID
                )
                && !oldPointer.knownReplicaIDs.contains(value.eraseID)
                && value.eraseID != oldPointer.workspaceID
                && value.eraseID != oldPointer.replicaID
                && value.eraseID != targetPointer.workspaceID
                && value.eraseID != targetPointer.replicaID
                && targetPointer.knownReplicaIDs == [targetPointer.replicaID]
                && sourceLedger.entryCount >= 0
                && sourceLedger.entryCount
                    <= DeletionLedgerV2.maximumEntryCount
                && validSHA256(sourceLedger.canonicalSHA256)
                && targetEmptyProof.contentRecordCount == 0
                && targetEmptyProof.deletionLedgerEntryCount == 0
        default:
            return false
        }
    }

    private static func pointerJSON(
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

    private static func decodePointer(
        _ raw: Any?
    ) -> RestorePointerIdentityV1? {
        guard let object = exactObject(raw, keys: pointerKeys),
              let generationID = canonicalUUID(object["generationID"]),
              let digest = object["generationManifestSHA256"] as? String,
              let rawKnownReplicaIDs = object["knownReplicaIDs"] as? [Any],
              let knownReplicaIDs = canonicalUUIDs(rawKnownReplicaIDs),
              knownReplicaIDs == knownReplicaIDs.sorted(by: idOrder),
              Set(knownReplicaIDs).count == knownReplicaIDs.count,
              let replicaID = canonicalUUID(object["replicaID"]),
              let workspaceID = canonicalUUID(object["workspaceID"]) else {
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

    private static func decodeLedgerProof(_ raw: Any?) -> DeletionLedgerProofV2? {
        guard let object = exactObject(raw, keys: ledgerProofKeys),
              let entryCount = canonicalNonnegativeInt(object["entryCount"]),
              let digest = object["canonicalSHA256"] as? String else {
            return nil
        }
        return try? DeletionLedgerProofV2(
            entryCount: entryCount,
            canonicalSHA256: digest
        )
    }

    private static func decodeEmptyProof(
        _ raw: Any?
    ) -> EraseEmptyGenerationProofV2? {
        guard let object = exactObject(raw, keys: emptyProofKeys),
              let contentRecordCount = canonicalNonnegativeInt(
                  object["contentRecordCount"]
              ),
              let ledgerEntryCount = canonicalNonnegativeInt(
                  object["deletionLedgerEntryCount"]
              ) else {
            return nil
        }
        return EraseEmptyGenerationProofV2(
            contentRecordCount: contentRecordCount,
            deletionLedgerEntryCount: ledgerEntryCount
        )
    }

    private static func validPointer(_ value: RestorePointerIdentityV1) -> Bool {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        return value.generationID != zero
            && value.workspaceID != zero
            && value.replicaID != zero
            && value.generationID != value.workspaceID
            && value.generationID != value.replicaID
            && value.workspaceID != value.replicaID
            && !value.knownReplicaIDs.isEmpty
            && value.knownReplicaIDs.count <= 64
            && value.knownReplicaIDs == value.knownReplicaIDs.sorted(by: idOrder)
            && Set(value.knownReplicaIDs).count == value.knownReplicaIDs.count
            && value.knownReplicaIDs.contains(value.replicaID)
            && validSHA256(value.generationManifestSHA256)
    }

    private static func validSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                (48...57).contains(Int($0.value))
                    || (97...102).contains(Int($0.value))
            }
    }

    private static func exactObject(
        _ raw: Any?,
        keys: Set<String>
    ) -> [String: Any]? {
        guard let value = raw as? [String: Any],
              Set(value.keys) == keys,
              value.count == keys.count else {
            return nil
        }
        return value
    }

    private static func canonicalNonnegativeInt(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.intValue >= 0,
              number.doubleValue == Double(number.intValue) else {
            return nil
        }
        return number.intValue
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

import Foundation

enum FieldReferenceOrdinaryDeletionDispositionV1:Equatable,Sendable{case preserveBoundHistory(releaseIDs:Set<UUID>,bindingIDs:Set<UUID>);case discardUnboundRelease(releaseID:UUID);case blockedMissingRequiredBytes(releaseID:UUID,contentIDs:[String])}
enum AccessibleDocumentOrdinaryDeletionDispositionV1:Equatable,Sendable{case preserveSealedOutputAndAssessment(receiptIDs:Set<UUID>,outputSHA256:Set<String>);case removeAfterAuthorizedPrivacyExpiry(receiptID:UUID,tombstoneSHA256:String,redactionProofSHA256:String);case blockedMissingRetentionProof(receiptID:UUID)}

enum DeletionPhaseV1: String, Codable, Equatable, Sendable {
    case prepared
    case databaseCommitted = "database_committed"
}

struct DeletionIntentV1: Codable, Equatable, Sendable {
    let assetID: UUID
    let countedPacketTombstones: [PacketPayloadV1]
    let deletionID: UUID
    let generationID: UUID
    let ledgerEntries: [DeletionLedgerEntryV2]
    let phase: DeletionPhaseV1
    let relativePaths: [String]
    let schemaVersion: Int

    func withPhase(_ phase: DeletionPhaseV1) -> DeletionIntentV1 {
        DeletionIntentV1(
            assetID: assetID,
            countedPacketTombstones: countedPacketTombstones,
            deletionID: deletionID,
            generationID: generationID,
            ledgerEntries: ledgerEntries,
            phase: phase,
            relativePaths: relativePaths,
            schemaVersion: schemaVersion
        )
    }
}

struct EncodedDeletionIntentV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum DeletionIntentEncodingErrorV1: Error, Equatable {
    case invalidIntent
}

enum DeletionIntentDecodingErrorV1: Error, Equatable {
    case invalidCanonicalIntent
}

struct DeletionIntentEncoderV1 {
    func encode(_ intent: DeletionIntentV1) throws -> EncodedDeletionIntentV1 {
        guard Self.valid(intent) else {
            throw DeletionIntentEncodingErrorV1.invalidIntent
        }
        let tombstones = intent.countedPacketTombstones.map { packet in
            CanonicalJSONValueV1.object([
                "contentDeletedAt": CanonicalJSONV1.optionalDate(packet.contentDeletedAt),
                "createdAt": CanonicalJSONV1.date(packet.createdAt),
                "currentRecordID": CanonicalJSONV1.optionalUUID(packet.currentRecordID),
                "evaluationCounted": .bool(packet.evaluationCounted),
                "id": CanonicalJSONV1.uuid(packet.id),
                "schemaVersion": .integer(packet.schemaVersion),
                "stableRootID": CanonicalJSONV1.uuid(packet.stableRootID),
            ])
        }
        var fields: [String: CanonicalJSONValueV1] = [
            "assetID": CanonicalJSONV1.uuid(intent.assetID),
            "countedPacketTombstones": .array(tombstones),
            "deletionID": CanonicalJSONV1.uuid(intent.deletionID),
            "generationID": CanonicalJSONV1.uuid(intent.generationID),
            "phase": .string(intent.phase.rawValue),
            "relativePaths": .array(intent.relativePaths.map {
                CanonicalJSONValueV1.string($0)
            }),
            "schemaVersion": .integer(intent.schemaVersion),
        ]
        if intent.schemaVersion == 2 {
            fields["ledgerEntries"] = .array(intent.ledgerEntries.map { entry in
                CanonicalJSONValueV1.object([
                    "deletedAt": CanonicalJSONV1.date(entry.deletedAt),
                    "identity": .object([
                        "id": CanonicalJSONV1.uuid(entry.identity.id),
                        "kind": .string(entry.identity.kind.rawValue),
                    ]),
                    "schemaVersion": .integer(entry.schemaVersion),
                ])
            })
        }
        let value = CanonicalJSONValueV1.object(fields)
        let data = try CanonicalJSONV1.encode(value)
        return EncodedDeletionIntentV1(
            data: data,
            sha256: CanonicalJSONV1.sha256(data)
        )
    }

    static func valid(_ intent: DeletionIntentV1) -> Bool {
        guard intent.schemaVersion == 1 || intent.schemaVersion == 2,
              unique(intent.countedPacketTombstones.map(\.id)),
              unique(intent.countedPacketTombstones.map(\.stableRootID)),
              Set(intent.countedPacketTombstones.compactMap(\.contentDeletedAt)).count <= 1,
              intent.countedPacketTombstones == intent.countedPacketTombstones.sorted(by: {
                  canonicalID($0.id) < canonicalID($1.id)
              }),
              unique(intent.relativePaths),
              intent.relativePaths == intent.relativePaths.sorted(),
              intent.relativePaths.allSatisfy(validRelativePath) else {
            return false
        }
        guard intent.countedPacketTombstones.allSatisfy({ packet in
            packet.schemaVersion == 1
                && packet.currentRecordID == nil
                && packet.evaluationCounted
                && packet.contentDeletedAt != nil
                && packet.contentDeletedAt.map({ $0 >= packet.createdAt }) == true
        }) else { return false }
        if intent.schemaVersion == 1 {
            return intent.ledgerEntries.isEmpty
        }
        return (try? DeletionLedgerV2(entries: intent.ledgerEntries)) != nil
            && intent.ledgerEntries.map(\.identity)
                == intent.ledgerEntries.map(\.identity).sorted()
            && intent.ledgerEntries.allSatisfy({
                Optional($0.deletedAt) == deletionTimestamp(intent)
            })
            && intent.ledgerEntries.filter({ $0.identity.kind == .asset }).map({
                $0.identity.id
            }) == [intent.assetID]
            && !intent.ledgerEntries.contains(where: { $0.identity.kind == .site })
            && Set(intent.countedPacketTombstones.map(\.id)).isSubset(of:
                Set(intent.ledgerEntries.compactMap { entry in
                    entry.identity.kind == .packet ? entry.identity.id : nil
                })
            )
    }

    private static func deletionTimestamp(_ intent: DeletionIntentV1) -> Date? {
        let dates = Set(intent.countedPacketTombstones.compactMap(\.contentDeletedAt))
        if let date = dates.first { return date }
        let ledgerDates = Set(intent.ledgerEntries.map(\.deletedAt))
        return ledgerDates.count == 1 ? ledgerDates.first : nil
    }

    static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\"),
              !value.contains(":") else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.count == 3,
           components[0] == "evidence",
           components[2] == "original.jpg" || components[2] == "thumbnail.jpg" {
            return canonicalUUID(components[1])
        }
        if components.count == 2, components[0] == "snapshots" {
            return canonicalUUIDFilename(components[1], pathExtension: "json")
        }
        if components.count == 2, components[0] == "pdfs" {
            return canonicalUUIDFilename(components[1], pathExtension: "pdf")
        }
        return false
    }

    private static func canonicalUUIDFilename(_ filename: String, pathExtension: String) -> Bool {
        let suffix = ".\(pathExtension)"
        guard filename.hasSuffix(suffix) else { return false }
        return canonicalUUID(String(filename.dropLast(suffix.count)))
    }

    private static func canonicalUUID(_ value: String) -> Bool {
        guard let identifier = UUID(uuidString: value) else { return false }
        return identifier.uuidString.lowercased() == value
    }

    private static func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    private static func canonicalID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

struct DeletionIntentDecoderV1 {
    func decode(_ data: Data) throws -> DeletionIntentV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard Self.isCanonicalTimestamp(string),
                  let date = Self.timestampFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected canonical RFC3339 UTC milliseconds"
                )
            }
            return date
        }
        do {
            let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
            let intent: DeletionIntentV1
            if version == 1 {
                let legacy = try decoder.decode(LegacyIntent.self, from: data)
                intent = DeletionIntentV1(
                    assetID: legacy.assetID,
                    countedPacketTombstones: legacy.countedPacketTombstones,
                    deletionID: legacy.deletionID,
                    generationID: legacy.generationID,
                    ledgerEntries: [],
                    phase: legacy.phase,
                    relativePaths: legacy.relativePaths,
                    schemaVersion: legacy.schemaVersion
                )
            } else {
                intent = try decoder.decode(DeletionIntentV1.self, from: data)
            }
            let canonical = try DeletionIntentEncoderV1().encode(intent).data
            guard canonical == data else {
                throw DeletionIntentDecodingErrorV1.invalidCanonicalIntent
            }
            return intent
        } catch {
            throw DeletionIntentDecodingErrorV1.invalidCanonicalIntent
        }
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct LegacyIntent: Decodable {
        let assetID: UUID
        let countedPacketTombstones: [PacketPayloadV1]
        let deletionID: UUID
        let generationID: UUID
        let phase: DeletionPhaseV1
        let relativePaths: [String]
        let schemaVersion: Int
    }

    private static func isCanonicalTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 24 else { return false }
        let punctuation: [Int: UInt8] = [
            4: 0x2d, 7: 0x2d, 10: 0x54, 13: 0x3a,
            16: 0x3a, 19: 0x2e, 23: 0x5a,
        ]
        for (index, byte) in bytes.enumerated() {
            if let expected = punctuation[index] {
                guard byte == expected else { return false }
            } else if !(0x30...0x39).contains(byte) {
                return false
            }
        }
        return true
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

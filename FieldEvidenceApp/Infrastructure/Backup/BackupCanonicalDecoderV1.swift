import Foundation

struct BackupCanonicalDecoderV1: Sendable {
    func decodeManifestOffMain(
        _ data: Data,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> V4BackupManifestV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().decodeManifest(data)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func decodeRecordsOffMain(
        _ data: Data,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> V4BackupRecordsV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().decodeRecords(data)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func decodeManifest(_ data: Data) throws -> V4BackupManifestV1 {
        do {
            let value = try decoder().decode(V4BackupManifestV1.self, from: data)
            let canonical = try BackupCanonicalEncoderV1().encodeManifest(value).data
            guard canonical == data else {
                throw BackupCanonicalDecodingErrorV1.invalidManifest
            }
            return value
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidManifest
        }
    }

    func decodeRecords(_ data: Data) throws -> V4BackupRecordsV1 {
        do {
            let value = try decoder().decode(V4BackupRecordsV1.self, from: data)
            try Self.validatePartyAccountability(value)
            let canonical = try BackupCanonicalEncoderV1().encodeRecords(value).data
            guard canonical == data else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return value
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

private extension BackupCanonicalDecoderV1 {
    static func validatePartyAccountability(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 8 else {
            guard records.partyAccountability.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        var partyIDs = Set<UUID>()
        var roleValues: [SitePartyRoleEventV1] = []
        var actorValues: [UUID: ActorSnapshotV1] = [:]
        var qualificationValues: [UUID: QualificationSnapshotV1] = [:]
        var signoffValues: [SignoffSnapshotV1] = []
        for record in records.partyAccountability {
            switch record.kind {
            case .serviceParty:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    ServicePartyReferenceV1.self, from: record.canonicalData
                )
                guard value.partyID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision,
                      partyIDs.insert(value.partyID).inserted else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .sitePartyRoleEvent:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    SitePartyRoleEventV1.self, from: record.canonicalData
                )
                guard value.eventID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                roleValues.append(value)
            case .actorSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    ActorSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      record.revision == nil,
                      actorValues.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .qualificationSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    QualificationSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      record.revision == nil,
                      qualificationValues.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .signoffSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    SignoffSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.subjectRevision == record.revision else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                signoffValues.append(value)
            }
        }
        let siteIDs = Set(records.sites.map(\.id))
        guard roleValues.allSatisfy({
                  partyIDs.contains($0.partyID) && siteIDs.contains($0.siteID)
              }),
              actorValues.values.allSatisfy({ value in
                  value.actor.partyID.map(partyIDs.contains) ?? true
              }),
              signoffValues.allSatisfy({ value in
                  (value.roleAssertion.map {
                      actorValues[$0.actor.snapshotID] == $0.actor
                  } ?? true)
                    && (value.qualification.map {
                        qualificationValues[$0.snapshotID] == $0
                    } ?? true)
              }) else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        let timestampFormatter = Self.makeTimestampFormatter()
        value.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard Self.isCanonicalTimestamp(string),
                  let date = timestampFormatter.date(from: string),
                  timestampFormatter.string(from: date) == string else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected canonical RFC3339 UTC milliseconds"
                )
            }
            return date
        }
        return value
    }

    static func isCanonicalTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 24 else { return false }
        let punctuation: [Int: UInt8] = [
            4: 0x2d,
            7: 0x2d,
            10: 0x54,
            13: 0x3a,
            16: 0x3a,
            19: 0x2e,
            23: 0x5a,
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

    static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        value.timeZone = TimeZone(secondsFromGMT: 0)
        return value
    }
}

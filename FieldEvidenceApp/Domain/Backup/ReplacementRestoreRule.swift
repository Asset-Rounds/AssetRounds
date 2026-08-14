import Foundation

struct ReplacementRestoreRuleInput: Equatable, Sendable {
    let currentPackets: [V4BackupPacketDTO]
    let incomingPackets: [V4BackupPacketDTO]
    let replacementAt: Date
}

struct ReplacementRestorePlan: Equatable, Sendable {
    let packetsAfter: [V4BackupPacketDTO]
    let currentOnlyTombstones: [V4BackupPacketDTO]
    let consumedEvaluationRootIDs: [UUID]
}

enum ReplacementRestoreRuleError: Error, Equatable {
    case invalidAuthority
}

enum ReplacementRestoreRule {
    static func makePlan(
        _ input: ReplacementRestoreRuleInput
    ) throws -> ReplacementRestorePlan {
        guard validDate(input.replacementAt),
              validPacketSet(input.currentPackets),
              validPacketSet(input.incomingPackets) else {
            throw ReplacementRestoreRuleError.invalidAuthority
        }

        let incomingByID = Dictionary(
            uniqueKeysWithValues: input.incomingPackets.map { ($0.id, $0) }
        )
        let incomingByRoot = Dictionary(
            uniqueKeysWithValues: input.incomingPackets.map { ($0.stableRootID, $0) }
        )

        for current in input.currentPackets {
            let idMatch = incomingByID[current.id]
            let rootMatch = incomingByRoot[current.stableRootID]
            guard (idMatch == nil) == (rootMatch == nil) else {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            if let idMatch, let rootMatch {
                guard idMatch.id == rootMatch.id,
                      sameImmutableFacts(current, idMatch) else {
                    throw ReplacementRestoreRuleError.invalidAuthority
                }
            }
        }

        let currentOnlyTombstones = try input.currentPackets.compactMap { packet in
            guard incomingByRoot[packet.stableRootID] == nil else { return nil }
            guard packet.evaluationCounted,
                  input.replacementAt >= packet.createdAt,
                  packet.contentDeletedAt.map({ input.replacementAt >= $0 }) ?? true else {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            return V4BackupPacketDTO(
                id: packet.id,
                schemaVersion: packet.schemaVersion,
                stableRootID: packet.stableRootID,
                currentRecordID: nil,
                evaluationCounted: true,
                contentDeletedAt: input.replacementAt,
                createdAt: packet.createdAt
            )
        }.sorted(by: packetOrder)

        let packetsAfter = (input.incomingPackets + currentOnlyTombstones)
            .sorted(by: packetOrder)
        guard validPacketSet(packetsAfter),
              Set(packetsAfter.map(\.stableRootID))
                == Set(
                    (input.currentPackets + input.incomingPackets)
                        .filter(\.evaluationCounted)
                        .map(\.stableRootID)
                ),
              input.incomingPackets.allSatisfy({ incoming in
                  packetsAfter.first(where: { $0.id == incoming.id }) == incoming
              }) else {
            throw ReplacementRestoreRuleError.invalidAuthority
        }

        return ReplacementRestorePlan(
            packetsAfter: packetsAfter,
            currentOnlyTombstones: currentOnlyTombstones,
            consumedEvaluationRootIDs: packetsAfter
                .filter(\.evaluationCounted)
                .map(\.stableRootID)
                .sorted(by: idOrder)
        )
    }
}

private extension ReplacementRestoreRule {
    static func validPacketSet(_ packets: [V4BackupPacketDTO]) -> Bool {
        guard sortedUnique(packets.map(\.id)),
              Set(packets.map(\.stableRootID)).count == packets.count else {
            return false
        }
        return packets.allSatisfy(validPacket)
    }

    static func validPacket(_ packet: V4BackupPacketDTO) -> Bool {
        guard packet.schemaVersion == 1,
              packet.evaluationCounted,
              validDate(packet.createdAt) else {
            return false
        }
        if packet.currentRecordID != nil {
            return packet.contentDeletedAt == nil
        }
        guard let deletedAt = packet.contentDeletedAt else { return false }
        return validDate(deletedAt) && packet.createdAt <= deletedAt
    }

    static func sameImmutableFacts(
        _ current: V4BackupPacketDTO,
        _ incoming: V4BackupPacketDTO
    ) -> Bool {
        current.id == incoming.id
            && current.schemaVersion == incoming.schemaVersion
            && current.stableRootID == incoming.stableRootID
            && current.evaluationCounted == incoming.evaluationCounted
            && current.createdAt == incoming.createdAt
    }

    static func sortedUnique(_ ids: [UUID]) -> Bool {
        Set(ids).count == ids.count && ids == ids.sorted(by: idOrder)
    }

    static func packetOrder(
        _ lhs: V4BackupPacketDTO,
        _ rhs: V4BackupPacketDTO
    ) -> Bool {
        idOrder(lhs.id, rhs.id)
    }

    static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        canonical(lhs) < canonical(rhs)
    }

    static func canonical(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}

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

struct DeletionWinningRestoreInputV2: Equatable, Sendable {
    let currentRecords: V4BackupRecordsV1
    let incomingRecords: V4BackupRecordsV1
    let mode: BackupRestoreMode
    let replacementAt: Date
}

struct DeletionWinningRestorePlanV2: Equatable, Sendable {
    let recordsAfter: V4BackupRecordsV1
    let deletionLedger: DeletionLedgerV2
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
        let currentByID = Dictionary(
            uniqueKeysWithValues: input.currentPackets.map { ($0.id, $0) }
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

        var currentOnlyTombstones = [V4BackupPacketDTO]()
        for current in input.currentPackets where incomingByRoot[current.stableRootID] == nil {
            guard current.evaluationCounted,
                  input.replacementAt >= current.createdAt,
                  current.contentDeletedAt.map({ input.replacementAt >= $0 }) ?? true else {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            currentOnlyTombstones.append(
                current.currentRecordID == nil
                    ? current
                    : V4BackupPacketDTO(
                        id: current.id,
                        schemaVersion: current.schemaVersion,
                        stableRootID: current.stableRootID,
                        currentRecordID: nil,
                        evaluationCounted: true,
                        contentDeletedAt: input.replacementAt,
                        createdAt: current.createdAt
                    )
            )
        }
        currentOnlyTombstones.sort(by: packetOrder)

        let incomingAfterDeletionWins = input.incomingPackets.map { incoming in
            guard let current = currentByID[incoming.id],
                  current.currentRecordID == nil else {
                return incoming
            }
            return current
        }
        let packetsAfter = (incomingAfterDeletionWins + currentOnlyTombstones)
            .sorted(by: packetOrder)
        guard validPacketSet(packetsAfter),
              Set(packetsAfter.map(\.stableRootID))
                == Set(
                    (input.currentPackets + input.incomingPackets)
                        .filter(\.evaluationCounted)
                        .map(\.stableRootID)
                ) else {
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

    static func makeDeletionWinningPlan(
        _ input: DeletionWinningRestoreInputV2
    ) throws -> DeletionWinningRestorePlanV2 {
        guard validDate(input.replacementAt) else {
            throw ReplacementRestoreRuleError.invalidAuthority
        }
        var ledger = try normalizedLedger(input.currentRecords)
            .union(normalizedLedger(input.incomingRecords))
        var incoming = input.incomingRecords

        if input.mode == .replaceExisting {
            let packetPlan = try makePlan(.init(
                currentPackets: input.currentRecords.packets,
                incomingPackets: input.incomingRecords.packets,
                replacementAt: input.replacementAt
            ))
            incoming = replacingPackets(in: incoming, with: packetPlan.packetsAfter)
            let packetEntries = try packetPlan.packetsAfter.compactMap { packet in
                guard packet.currentRecordID == nil,
                      let deletedAt = packet.contentDeletedAt else { return nil }
                return try DeletionLedgerEntryV2(
                    identity: DeletionIdentityV2(kind: .packet, id: packet.id),
                    deletedAt: deletedAt
                )
            }
            ledger = try ledger.union(DeletionLedgerV2(
                entries: packetEntries.sorted { $0.identity < $1.identity }
            ))
        }

        let recordsAfter = try filtering(incoming, through: ledger)
        return DeletionWinningRestorePlanV2(
            recordsAfter: recordsAfter,
            deletionLedger: ledger
        )
    }
}

private extension ReplacementRestoreRule {
    static func normalizedLedger(_ records: V4BackupRecordsV1) throws
        -> DeletionLedgerV2 {
        let explicit: DeletionLedgerV2
        switch (records.recordsSchemaVersion, records.deletionLedger) {
        case (1, nil):
            explicit = .empty
        case (2, let ledger?):
            try ledger.validate()
            explicit = ledger
        default:
            throw ReplacementRestoreRuleError.invalidAuthority
        }
        let legacyPacketEntries = try records.packets.compactMap { packet in
            guard packet.currentRecordID == nil,
                  packet.evaluationCounted,
                  let deletedAt = packet.contentDeletedAt else { return nil }
            return try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(kind: .packet, id: packet.id),
                deletedAt: deletedAt
            )
        }.sorted { $0.identity < $1.identity }
        return try explicit.union(DeletionLedgerV2(entries: legacyPacketEntries))
    }

    static func filtering(
        _ records: V4BackupRecordsV1,
        through ledger: DeletionLedgerV2
    ) throws -> V4BackupRecordsV1 {
        try ledger.validate()
        let deleted = Dictionary(
            uniqueKeysWithValues: ledger.entries.map { ($0.identity, $0) }
        )
        func isDeleted(_ kind: DeletionRecordKindV2, _ id: UUID) throws -> Bool {
            deleted[try DeletionIdentityV2(kind: kind, id: id)] != nil
        }

        let sites = try records.sites.filter { try !isDeleted(.site, $0.id) }
        let assets = try records.assets.filter { try !isDeleted(.asset, $0.id) }
        let workflow = try records.workflowRecords.filter {
            try !isDeleted(.workflowRecord, $0.id)
        }
        let evidence = try records.evidenceFiles.filter {
            try !isDeleted(.evidenceFile, $0.id)
        }
        let issues = try records.issues.filter { try !isDeleted(.issue, $0.id) }
        let reports = try records.reports.filter { try !isDeleted(.report, $0.id) }
        let packets = try records.packets.map { packet -> V4BackupPacketDTO in
            let identity = try DeletionIdentityV2(kind: .packet, id: packet.id)
            guard let entry = deleted[identity] else { return packet }
            guard packet.evaluationCounted,
                  packet.createdAt <= entry.deletedAt else {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            return V4BackupPacketDTO(
                id: packet.id,
                schemaVersion: packet.schemaVersion,
                stableRootID: packet.stableRootID,
                currentRecordID: nil,
                evaluationCounted: true,
                contentDeletedAt: entry.deletedAt,
                createdAt: packet.createdAt
            )
        }

        let result = V4BackupRecordsV1(
            assets: assets,
            deletionLedger: ledger,
            evidenceFiles: evidence,
            issues: issues,
            packets: packets,
            recordsSchemaVersion: 2,
            reports: reports,
            sites: sites,
            workflowRecords: workflow
        )
        guard validReferences(result), noDeletedLiveIdentity(result, ledger: ledger) else {
            throw ReplacementRestoreRuleError.invalidAuthority
        }
        return result
    }

    static func replacingPackets(
        in records: V4BackupRecordsV1,
        with packets: [V4BackupPacketDTO]
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            packets: packets,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: records.reports,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    static func noDeletedLiveIdentity(
        _ records: V4BackupRecordsV1,
        ledger: DeletionLedgerV2
    ) -> Bool {
        let deleted = Set(ledger.entries.map(\.identity))
        func absent(_ kind: DeletionRecordKindV2, _ ids: [UUID]) -> Bool {
            ids.allSatisfy { id in
                guard let identity = try? DeletionIdentityV2(kind: kind, id: id) else {
                    return false
                }
                return !deleted.contains(identity)
            }
        }
        guard absent(.site, records.sites.map(\.id)),
              absent(.asset, records.assets.map(\.id)),
              absent(.workflowRecord, records.workflowRecords.map(\.id)),
              absent(.evidenceFile, records.evidenceFiles.map(\.id)),
              absent(.issue, records.issues.map(\.id)),
              absent(.report, records.reports.map(\.id)) else { return false }
        return records.packets.allSatisfy { packet in
            guard let identity = try? DeletionIdentityV2(kind: .packet, id: packet.id),
                  let entry = ledger.entries.first(where: { $0.identity == identity }) else {
                return true
            }
            return packet.currentRecordID == nil
                && packet.evaluationCounted
                && packet.contentDeletedAt == entry.deletedAt
        }
    }

    static func validReferences(_ records: V4BackupRecordsV1) -> Bool {
        let sites = Set(records.sites.map(\.id))
        let assets = Set(records.assets.map(\.id))
        let workflow = Set(records.workflowRecords.map(\.id))
        let issues = Set(records.issues.map(\.id))
        let packets = Set(records.packets.map(\.id))
        let reports = Set(records.reports.map(\.id))
        let allIDs = records.sites.map(\.id) + records.assets.map(\.id)
            + records.workflowRecords.map(\.id) + records.evidenceFiles.map(\.id)
            + records.issues.map(\.id) + records.packets.map(\.id)
            + records.reports.map(\.id)
        guard Set(allIDs).count == allIDs.count,
              records.assets.allSatisfy({ sites.contains($0.siteID) }),
              records.workflowRecords.allSatisfy({ record in
                  assets.contains(record.assetID)
                    && record.packetID.map(packets.contains) ?? true
                    && record.issueID.map(issues.contains) ?? true
                    && record.parentRecordID.map(workflow.contains) ?? true
                    && workflow.contains(record.recordRevisionRootID)
                    && record.revisesRecordID.map(workflow.contains) ?? true
                    && record.evidenceSourceRecordID.map(workflow.contains) ?? true
              }),
              records.evidenceFiles.allSatisfy({ workflow.contains($0.recordID) }),
              records.issues.allSatisfy({ issue in
                  assets.contains(issue.assetID)
                    && workflow.contains(issue.openedByRecordID)
                    && issue.resolvedByRecordID.map(workflow.contains) ?? true
              }),
              records.packets.allSatisfy({ packet in
                  packet.currentRecordID.map(workflow.contains) ?? true
              }),
              records.reports.allSatisfy({ report in
                  packets.contains(report.packetID)
                    && workflow.contains(report.sourceRecordID)
                    && report.replacesReportID.map(reports.contains) ?? true
              }) else { return false }
        return true
    }

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
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}

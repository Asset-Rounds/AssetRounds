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
    let currentIdentity: WorkspaceReplicaIdentityV1?
    let incomingRecords: V4BackupRecordsV1
    let incomingIdentity: WorkspaceReplicaIdentityV1?
    let mode: BackupRestoreMode
    let replacementAt: Date

    init(
        currentRecords: V4BackupRecordsV1,
        currentIdentity: WorkspaceReplicaIdentityV1? = nil,
        incomingRecords: V4BackupRecordsV1,
        incomingIdentity: WorkspaceReplicaIdentityV1? = nil,
        mode: BackupRestoreMode,
        replacementAt: Date
    ) {
        self.currentRecords = currentRecords
        self.currentIdentity = currentIdentity
        self.incomingRecords = incomingRecords
        self.incomingIdentity = incomingIdentity
        self.mode = mode
        self.replacementAt = replacementAt
    }
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

        let mutationHistory: MutationHistorySnapshotV1?
        switch input.mode {
        case .emptyInstall, .clone, .fork:
            mutationHistory = input.incomingRecords.mutationHistory
        case .replaceExisting:
            mutationHistory = try mergedMutationHistory(
                current: input.currentRecords.mutationHistory,
                currentIdentity: input.currentIdentity,
                incoming: input.incomingRecords.mutationHistory,
                incomingIdentity: input.incomingIdentity
            )
        }
        incoming = replacingMutationHistory(in: incoming, with: mutationHistory)
        if input.mode == .replaceExisting {
            incoming = try replacingRequirementAssurance(
                in: incoming,
                with: mergedRequirementAssurance(
                    current: input.currentRecords.requirementAssurance,
                    incoming: incoming.requirementAssurance,
                    retainedWorkflowIDs: Set(incoming.workflowRecords.map(\.id))
                )
            )
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
        switch (
            records.recordsSchemaVersion,
            records.deletionLedger,
            records.mutationHistory
        ) {
        case (1, nil, nil):
            explicit = .empty
        case (2, let ledger?, nil):
            try ledger.validate()
            explicit = ledger
        case (3, let ledger?, let history?), (4, let ledger?, let history?),
             (5, let ledger?, let history?), (6, let ledger?, let history?),
             (7, let ledger?, let history?):
            try ledger.validate()
            try MutationJournalStoreV1.validateImportedSnapshot(history)
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
        let retainedWorkflowIDs = Set(workflow.map(\.id))
        let requirementAssurance = records.requirementAssurance.filter {
            retainedWorkflowIDs.contains($0.workflowRecordID)
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
            workPackets:records.workPackets, inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion, assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: assets,
            deletionLedger: ledger,
            evidenceFiles: evidence,
            issues: issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: records.mutationHistory,
            packets: packets,
            partyAccountability: records.partyAccountability,
            recordsSchemaVersion: records.mutationHistory == nil
                ? 2
                : records.recordsSchemaVersion,
            reports: reports,
            requirementAssurance: requirementAssurance,
            savedSmartViews: records.savedSmartViews,
            sites: sites,
            workflowRecords: workflow
        )
        guard validReferences(result), noDeletedLiveIdentity(result, ledger: ledger),
              validLocationReferences(result, ledger: ledger) else {
            throw ReplacementRestoreRuleError.invalidAuthority
        }
        return result
    }

    static func replacingPackets(
        in records: V4BackupRecordsV1,
        with packets: [V4BackupPacketDTO]
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            workPackets:records.workPackets, inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion, assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: records.mutationHistory,
            packets: packets,
            partyAccountability: records.partyAccountability,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: records.reports,
            requirementAssurance: records.requirementAssurance,
            savedSmartViews: records.savedSmartViews,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    static func replacingMutationHistory(
        in records: V4BackupRecordsV1,
        with mutationHistory: MutationHistorySnapshotV1?
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            workPackets:records.workPackets, inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion, assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: mutationHistory,
            packets: records.packets,
            partyAccountability: records.partyAccountability,
            recordsSchemaVersion: mutationHistory == nil
                ? min(records.recordsSchemaVersion, 2)
                : records.recordsSchemaVersion,
            reports: records.reports,
            requirementAssurance: records.requirementAssurance,
            savedSmartViews: records.savedSmartViews,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    static func replacingRequirementAssurance(
        in records: V4BackupRecordsV1,
        with requirementAssurance: [V8BackupRequirementAssuranceRecordV1]
    ) throws -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            workPackets:records.workPackets, inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion, assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets, deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles, issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes, mutationHistory: records.mutationHistory,
            packets: records.packets, partyAccountability: records.partyAccountability,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: records.reports, requirementAssurance: requirementAssurance,
            savedSmartViews: records.savedSmartViews, sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    static func mergedRequirementAssurance(
        current: [V8BackupRequirementAssuranceRecordV1],
        incoming: [V8BackupRequirementAssuranceRecordV1],
        retainedWorkflowIDs: Set<UUID>
    ) throws -> [V8BackupRequirementAssuranceRecordV1] {
        var result = Dictionary(uniqueKeysWithValues: incoming.map { ($0.workflowRecordID, $0) })
        for candidate in current where retainedWorkflowIDs.contains(candidate.workflowRecordID) {
            guard let existing = result[candidate.workflowRecordID] else {
                result[candidate.workflowRecordID] = candidate
                continue
            }
            let currentSnapshot = try candidate.snapshot()
            let incomingSnapshot = try existing.snapshot()
            if currentSnapshot.evaluatedRevision > incomingSnapshot.evaluatedRevision {
                result[candidate.workflowRecordID] = candidate
            } else if currentSnapshot.evaluatedRevision == incomingSnapshot.evaluatedRevision,
                      currentSnapshot != incomingSnapshot {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
        }
        return result.values.sorted {
            $0.workflowRecordID.uuidString < $1.workflowRecordID.uuidString
        }
    }

    static func mergedMutationHistory(
        current: MutationHistorySnapshotV1?,
        currentIdentity: WorkspaceReplicaIdentityV1?,
        incoming: MutationHistorySnapshotV1?,
        incomingIdentity: WorkspaceReplicaIdentityV1?
    ) throws -> MutationHistorySnapshotV1? {
        guard let current else { return incoming }
        guard let incoming else { return current }
        do {
            try MutationJournalStoreV1.validateImportedSnapshot(current)
            try MutationJournalStoreV1.validateImportedSnapshot(incoming)
        } catch {
            throw ReplacementRestoreRuleError.invalidAuthority
        }

        var receiptByMutationID: [String: MutationHistoryReceiptRecordV1] = [:]
        var receiptIdentityByMutationID: [String: String] = [:]
        var mutationIDByReceiptIdentity: [String: String] = [:]
        for record in current.receipts + incoming.receipts {
            let envelope: MutationEnvelopeV1
            let receipt: MutationReceiptV1
            do {
                envelope = try MutationEnvelopeV1.decodeCanonical(
                    from: record.envelopeData
                )
                receipt = try MutationReceiptV1.decodeCanonical(
                    from: record.receiptData
                )
            } catch {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            let mutationID = MutationWorkspaceKeyV1.value(
                workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID
            )
            let receiptIdentity = receipt.identity.stableKey
            if let existing = receiptByMutationID[mutationID], existing != record {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            if let existing = mutationIDByReceiptIdentity[receiptIdentity],
               existing != mutationID {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            receiptByMutationID[mutationID] = record
            receiptIdentityByMutationID[mutationID] = receiptIdentity
            mutationIDByReceiptIdentity[receiptIdentity] = mutationID
        }
        let receipts = receiptByMutationID.keys.sorted {
            receiptIdentityByMutationID[$0]! < receiptIdentityByMutationID[$1]!
        }.map { receiptByMutationID[$0]! }

        var quarantines: [String: MutationHistoryQuarantineRecordV1] = [:]
        for value in current.quarantines + incoming.quarantines {
            let key = MutationWorkspaceKeyV1.value(
                workspaceID: value.workspaceID,
                mutationID: try MutationIDV1(rawValue: value.mutationID)
            )
            if let existing = quarantines[key], existing != value {
                throw ReplacementRestoreRuleError.invalidAuthority
            }
            quarantines[key] = value
        }
        let orderedQuarantines = quarantines.values.sorted {
            let lhs = "\($0.workspaceID.rawValue.uuidString.lowercased()):\($0.mutationID.uuidString.lowercased())"
            let rhs = "\($1.workspaceID.rawValue.uuidString.lowercased()):\($1.mutationID.uuidString.lowercased())"
            return lhs < rhs
        }

        var revisions: [
            WorkspaceEntityIdentityV1: MutationHistoryEntityRevisionV1
        ] = [:]
        for value in current.entityRevisions + incoming.entityRevisions {
            guard let existing = revisions[value.identity] else {
                revisions[value.identity] = value
                continue
            }
            if value.revision > existing.revision {
                revisions[value.identity] = value
            }
        }
        let entityRevisions = revisions.values.sorted {
            $0.identity.stableKey < $1.identity.stableKey
        }
        let retainedSequence = currentIdentity != nil
            && currentIdentity == incomingIdentity
            ? max(current.lastLocalSequence, incoming.lastLocalSequence)
            : current.lastLocalSequence
        let result = MutationHistorySnapshotV1(
            workspaceRevision: max(
                current.workspaceRevision,
                incoming.workspaceRevision
            ),
            lastLocalSequence: retainedSequence,
            receipts: receipts,
            quarantines: orderedQuarantines,
            entityRevisions: entityRevisions
        )
        do { try MutationJournalStoreV1.validateImportedSnapshot(result) }
        catch { throw ReplacementRestoreRuleError.invalidAuthority }
        return result
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

    static func validLocationReferences(
        _ records: V4BackupRecordsV1,
        ledger: DeletionLedgerV2
    ) -> Bool {
        guard records.recordsSchemaVersion == 5
                || records.recordsSchemaVersion == 6
                || records.recordsSchemaVersion == 7
                || records.recordsSchemaVersion == 8
                || records.recordsSchemaVersion == 9
                || records.recordsSchemaVersion == 10
                || records.recordsSchemaVersion == 11
                || records.recordsSchemaVersion == 12
                || records.recordsSchemaVersion == 13
                || records.recordsSchemaVersion == 14 else {
            return records.locationNodes.isEmpty
                && records.assetPlacementEvents.isEmpty
                && records.assetCompositionEdges.isEmpty
                && records.assetCompositionEvents.isEmpty
                && records.locationHierarchyEvents.isEmpty
                && records.locationMigrationReceipts.isEmpty
        }
        let liveSites = Set(records.sites.map(\.id))
        let liveAssets = Set(records.assets.map(\.id))
        let deletedSites = Set(ledger.entries.compactMap {
            $0.identity.kind == .site ? $0.identity.id : nil
        })
        let deletedAssets = Set(ledger.entries.compactMap {
            $0.identity.kind == .asset ? $0.identity.id : nil
        })
        let knownSites = liveSites.union(deletedSites)
        let knownAssets = liveAssets.union(deletedAssets)
        func decode<T: Codable>(_ type: T.Type, _ record: V5BackupLocationRecordV1) throws -> T {
            try LocationPersistenceCodecV1.decode(type, from: record.canonicalData)
        }
        do {
            let nodes = try records.locationNodes.map { try decode(LocationNodeV1.self, $0) }
            let nodeIDs = Set(nodes.map(\.id))
            guard nodes.allSatisfy({
                knownSites.contains($0.siteID)
                    && (!deletedSites.contains($0.siteID) || $0.state == .archived)
            }) else { return false }

            let placements = try records.assetPlacementEvents.map {
                try decode(AssetPlacementEventV1.self, $0)
            }
            let placementIDs = Set(placements.map(\.id))
            guard placements.allSatisfy({ value in
                knownAssets.contains(value.assetID)
                    && knownSites.contains(value.siteID)
                    && value.locationNodeID.map(nodeIDs.contains) ?? true
                    && value.predecessorEventID.map(placementIDs.contains) ?? true
            }) else { return false }
            for history in Dictionary(grouping: placements, by: \.assetID).values {
                try AssetPlacementHistoryV1.validate(history)
            }
            let predecessorIDs = Set(placements.compactMap(\.predecessorEventID))
            let tips = placements.filter { !predecessorIDs.contains($0.id) }
            guard Set(tips.map(\.assetID)).count == tips.count,
                  Set(tips.map(\.assetID)) == Set(placements.map(\.assetID)),
                  liveAssets.isSubset(of: Set(tips.map(\.assetID))) else { return false }
            let placementsByID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
            var reachedPlacementIDs = Set<UUID>()
            for tip in tips {
                var cursor: AssetPlacementEventV1? = tip
                var visited = Set<UUID>()
                while let value = cursor {
                    guard value.assetID == tip.assetID,
                          visited.insert(value.id).inserted,
                          reachedPlacementIDs.insert(value.id).inserted else { return false }
                    cursor = value.predecessorEventID.flatMap { placementsByID[$0] }
                }
            }
            guard reachedPlacementIDs.count == placements.count else { return false }
            let liveSiteByAsset = Dictionary(uniqueKeysWithValues: records.assets.map { ($0.id, $0.siteID) })
            guard tips.allSatisfy({ tip in
                guard liveAssets.contains(tip.assetID) else { return deletedAssets.contains(tip.assetID) }
                return liveSites.contains(tip.siteID) && liveSiteByAsset[tip.assetID] == tip.siteID
            }) else { return false }
            let placementByAsset = Dictionary(uniqueKeysWithValues: tips.map { ($0.assetID, $0) })

            let edges = try records.assetCompositionEdges.map {
                try decode(AssetCompositionEdgeV1.self, $0)
            }
            guard edges.allSatisfy({ edge in
                knownAssets.contains(edge.parentAssetID)
                    && knownAssets.contains(edge.childAssetID)
                    && (!edge.isActive || (liveAssets.contains(edge.parentAssetID)
                        && liveAssets.contains(edge.childAssetID)))
            }) else { return false }
            try AssetCompositionPolicyV1.validate(
                edges: edges.filter(\.isActive),
                placementByAssetID: placementByAsset
            )
            let edgeIDs = Set(edges.map(\.id))
            let compositionEvents = try records.assetCompositionEvents.map {
                try decode(AssetCompositionEventV1.self, $0)
            }
            guard compositionEvents.allSatisfy({ event in
                edgeIDs.contains(event.edge.id)
                    && knownAssets.contains(event.edge.parentAssetID)
                    && knownAssets.contains(event.edge.childAssetID)
            }) else { return false }
            let compositionHistoryByEdgeID = Dictionary(grouping: compositionEvents, by: { $0.edge.id })
            guard Set(compositionHistoryByEdgeID.keys) == edgeIDs else { return false }
            let currentEdgeByID = Dictionary(uniqueKeysWithValues: edges.map { ($0.id, $0) })
            for (edgeID, history) in compositionHistoryByEdgeID {
                guard let currentEdge = currentEdgeByID[edgeID] else { return false }
                try AssetCompositionHistoryV1.validate(history, currentEdge: currentEdge)
            }

            for record in records.locationHierarchyEvents {
                guard let receiptData = record.secondaryCanonicalData else { return false }
                let plan = try decode(LocationHierarchyChangePlanV1.self, record)
                let receipt = try LocationPersistenceCodecV1.decode(
                    LocationHierarchyChangeReceiptV1.self, from: receiptData
                )
                guard plan.operationID == record.id,
                      receipt.planSHA256 == plan.planSHA256,
                      plan.affectedAssetIDs.allSatisfy(knownAssets.contains),
                      (plan.beforeNodes + plan.afterNodes).allSatisfy({ knownSites.contains($0.siteID) }),
                      (plan.beforePaths + plan.afterPaths).allSatisfy({ knownSites.contains($0.siteID) }) else {
                    return false
                }
            }
            let migrationReceipts = try records.locationMigrationReceipts.map {
                try decode(LocationMigrationReceiptV1.self, $0)
            }
            guard migrationReceipts.count <= 1,
                  migrationReceipts.allSatisfy({ receipt in
                receipt.bindings.allSatisfy {
                    knownAssets.contains($0.assetID) && knownSites.contains($0.siteID)
                }
            }) else { return false }
            try LocationMigrationIntegrityV1.validate(
                receipt: migrationReceipts.first,
                placementEvents: placements,
                knownAssetIDs: knownAssets,
                liveAssetSiteByID: liveSiteByAsset
            )
            return true
        } catch {
            return false
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

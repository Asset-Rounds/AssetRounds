import Foundation

/// A bounded selection minted only from a complete authenticated photo-history
/// projection. It is consumed by the member resolver; it is not itself a
/// history projection and grants no filesystem or writer authority.
struct CheckRunnerPhotoRestoreSourceSelectionV1: Equatable, Sendable {
    let source: V4BackupSourceV1
    let children: [CheckRunnerPhotoBackupHistoryChildV1]

    fileprivate init(source: V4BackupSourceV1,
                     children: [CheckRunnerPhotoBackupHistoryChildV1]) {
        self.source = source
        self.children = children
    }
}

/// Durable, value-only proof needed to reselect the original source photo
/// closure after the import package has been removed. A fresh complete
/// destination projection is mandatory before this value can issue a selection.
struct CheckRunnerPhotoRestoreCompositionBindingV1: Codable, Equatable, Sendable {
    struct HistoryKey: Codable, Equatable, Hashable, Sendable {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1

        private enum CodingKeys: String, CodingKey { case workspaceID, mutationID }

        init(workspaceID: WorkspaceID, mutationID: MutationIDV1) {
            self.workspaceID = workspaceID
            self.mutationID = mutationID
        }

        init(from decoder: Decoder) throws {
            try ClosedContractDecodingV1.rejectUnknownKeys(
                decoder, allowed: ["workspaceID", "mutationID"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            workspaceID = try values.decode(WorkspaceID.self, forKey: .workspaceID)
            mutationID = try values.decode(MutationIDV1.self, forKey: .mutationID)
        }

        var stableKey: String {
            MutationWorkspaceKeyV1.value(workspaceID: workspaceID, mutationID: mutationID)
        }
    }

    let schemaVersion: Int
    let source: V4BackupSourceV1
    let childDraftIDs: [UUID]
    let requiredHistoryKeys: [HistoryKey]
    let requiredHistorySHA256: String
    let canonicalClosureSHA256: String
    let frontierSHA256: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, source, childDraftIDs, requiredHistoryKeys
        case requiredHistorySHA256, canonicalClosureSHA256, frontierSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: [
            "schemaVersion", "source", "childDraftIDs", "requiredHistoryKeys",
            "requiredHistorySHA256", "canonicalClosureSHA256", "frontierSHA256",
        ])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        source = try values.decode(V4BackupSourceV1.self, forKey: .source)
        childDraftIDs = try values.decode([UUID].self, forKey: .childDraftIDs)
        requiredHistoryKeys = try values.decode([HistoryKey].self, forKey: .requiredHistoryKeys)
        requiredHistorySHA256 = try values.decode(String.self, forKey: .requiredHistorySHA256)
        canonicalClosureSHA256 = try values.decode(String.self, forKey: .canonicalClosureSHA256)
        frontierSHA256 = try values.decode(String.self, forKey: .frontierSHA256)
        try validateShape()
    }

    fileprivate init(sourceHistory: CheckRunnerPhotoBackupHistoryV1,
                     records: V4BackupRecordsV1, selecting selectedIDs: Set<UUID>? = nil) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        // The input is always a complete authenticated projection. A retained
        // subset keeps the complete original history proof while narrowing only
        // its canonical/frontier selection; no partial history is fabricated.
        let allIDs = Set(sourceHistory.children.map { $0.payload.childDraftID })
        let selectedIDs = selectedIDs ?? allIDs
        // A source with no photo child still contributes an exact authenticated
        // binding. Empty selection cannot hide children of a nonempty source.
        guard selectedIDs.isSubset(of: allIDs),
              !selectedIDs.isEmpty || allIDs.isEmpty else { throw failure }
        let children = sourceHistory.children.filter { selectedIDs.contains($0.payload.childDraftID) }
            .sorted(by: Self.childLess)
        let keys = sourceHistory.requiredHistory.map {
            HistoryKey(workspaceID: $0.envelope.workspaceID,
                       mutationID: $0.envelope.mutationID)
        }.sorted { $0.stableKey < $1.stableKey }
        guard Set(children.map { $0.payload.childDraftID }).count == children.count,
              Set(keys).count == keys.count else { throw failure }
        schemaVersion = 2
        source = sourceHistory.source
        childDraftIDs = children.map { $0.payload.childDraftID }
        requiredHistoryKeys = keys
        requiredHistorySHA256 = try Self.historySHA256(
            sourceHistory.requiredHistory.map(\.original), keys: keys)
        canonicalClosureSHA256 = try CheckRunnerPhotoRestoreCompositionV1
            .canonicalClosure(history: sourceHistory, childDraftIDs: Set(childDraftIDs),
                              records: records).sha256
        frontierSHA256 = try Self.frontierSHA256(children)
        try validateShape()
    }

    func selectSource(in destination: V4BackupRecordsV1) throws
        -> CheckRunnerPhotoRestoreSourceSelectionV1 {
        try validateShape()
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let projected = try CheckRunnerPhotoBackupHistoryV1.project(
            source: source, records: destination)
        let byID = try checkRunnerPhotoRestoreDictionary(projected.children) {
            ($0.payload.childDraftID, $0)
        }
        let selected = try childDraftIDs.map { id -> CheckRunnerPhotoBackupHistoryChildV1 in
            guard let child = byID[id] else { throw failure }
            return child
        }
        guard try Self.frontierSHA256(selected) == frontierSHA256,
              let snapshot = destination.mutationHistory else { throw failure }
        let recordsByKey = try checkRunnerPhotoRestoreDictionary(snapshot.receipts) { row in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            return (MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                                                  mutationID: envelope.mutationID), row)
        }
        let originals = try requiredHistoryKeys.map { key -> MutationHistoryReceiptRecordV1 in
            guard let value = recordsByKey[key.stableKey] else { throw failure }
            return value
        }
        let quarantined = Set(try snapshot.quarantines.map {
            MutationWorkspaceKeyV1.value(workspaceID: $0.workspaceID,
                mutationID: try MutationIDV1(rawValue: $0.mutationID))
        })
        guard quarantined.isDisjoint(with: Set(requiredHistoryKeys.map(\.stableKey))),
              try Self.historySHA256(originals, keys: requiredHistoryKeys)
                == requiredHistorySHA256,
              try CheckRunnerPhotoRestoreCompositionV1.canonicalClosure(
                history: projected, childDraftIDs: Set(childDraftIDs),
                records: destination, bindingVersion: schemaVersion).sha256 == canonicalClosureSHA256 else { throw failure }
        return .init(source: source, children: selected)
    }

    private func validateShape() throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard (schemaVersion == 1 || schemaVersion == 2),
              let workspaceID = source.workspaceID,
              requiredHistoryKeys.allSatisfy({ $0.workspaceID.rawValue == workspaceID }),
              childDraftIDs.allSatisfy({ $0 != Self.zero }),
              childDraftIDs == childDraftIDs.sorted(by: Self.uuidLess),
              Set(childDraftIDs).count == childDraftIDs.count,
              childDraftIDs.isEmpty || !requiredHistoryKeys.isEmpty,
              requiredHistoryKeys == requiredHistoryKeys.sorted(by: {
                  $0.stableKey < $1.stableKey
              }), Set(requiredHistoryKeys).count == requiredHistoryKeys.count,
              [requiredHistorySHA256, canonicalClosureSHA256, frontierSHA256]
                .allSatisfy(Self.isSHA256) else { throw failure }
    }

    private static func historySHA256(_ originals: [MutationHistoryReceiptRecordV1],
                                      keys: [HistoryKey]) throws -> String {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard originals.count == keys.count else { throw failure }
        let byKey = try checkRunnerPhotoRestoreDictionary(originals) { original in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            return (MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID), original)
        }
        let ordered = try keys.map { key -> MutationHistoryReceiptRecordV1 in
            guard let original = byKey[key.stableKey] else { throw failure }
            return original
        }
        return CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode(ordered))
    }

    private struct FrontierChild: Codable {
        let childDraftID: UUID
        let parentDraftID: UUID
        let stageID: UUID
        let payloadSHA256: String
        let childCheckpointSHA256: String
        let parentCheckpointSHA256: String
        let graphDraftSHA256s: [String]
        let roundSessionID: UUID
        let roundSHA256: String
        let targetWorkflowSHA256: String?
        let targetEvidenceSHA256: String?
    }

    private static func frontierSHA256(_ children: [CheckRunnerPhotoBackupHistoryChildV1]) throws
        -> String {
        let values = try children.sorted(by: childLess).map { child -> FrontierChild in
            let graph = child.sourceGraph
            return FrontierChild(
                childDraftID: child.payload.childDraftID,
                parentDraftID: child.payload.parentDraftID,
                stageID: child.payload.phase.intent.stageID,
                payloadSHA256: CanonicalJSONV1.sha256(
                    try FieldDraftCanonicalCodecV1.encode(child.payload)),
                childCheckpointSHA256: child.currentCheckpoint.checkpointSHA256,
                parentCheckpointSHA256: child.parentCheckpoint.checkpointSHA256,
                graphDraftSHA256s: graph.checkpoints.map(\.current.checkpointSHA256),
                roundSessionID: graph.packageCurrentRound.sessionID,
                roundSHA256: graph.packageCurrentRound.sessionSHA256,
                targetWorkflowSHA256: try child.targetRecords.map {
                    CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode($0.workflow))
                },
                targetEvidenceSHA256: try child.targetRecords.map {
                    CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode($0.evidence))
                })
        }
        return CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode(values))
    }

    fileprivate static func childLess(_ lhs: CheckRunnerPhotoBackupHistoryChildV1,
                                      _ rhs: CheckRunnerPhotoBackupHistoryChildV1) -> Bool {
        lhs.payload.childDraftID.uuidString.lowercased()
            < rhs.payload.childDraftID.uuidString.lowercased()
    }

    private static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                           0, 0, 0, 0, 0, 0, 0, 0))
}

struct CheckRunnerPhotoRestoreDraftClosureV1: Equatable, Sendable {
    let draftID: UUID
    let rows: [V16BackupFieldDraftRecordV1]
    let history: [MutationHistoryReceiptRecordV1]
    let stageIDs: [UUID]
}

struct CheckRunnerPhotoRestoreCanonicalRowsV1: Equatable, Sendable {
    let assetPlacementEvents: [V5BackupLocationRecordV1]
    let reports: [V4BackupReportDTO]
    let fieldDrafts: [V16BackupFieldDraftRecordV1]
    let workflowRecords: [V4BackupWorkflowRecordDTO]
    let evidenceFiles: [V4BackupEvidenceFileDTO]
    let roundSessions: [RoundSessionV1]
    let assets: [V4BackupAssetDTO]
    let sites: [V4BackupSiteDTO]
    let packets: [V4BackupPacketDTO]
    let issues: [V4BackupIssueDTO]
    let requirementAssurance: [V8BackupRequirementAssuranceRecordV1]

    fileprivate func applying(to records: V4BackupRecordsV1,
                              mutationHistory: MutationHistorySnapshotV1?) -> V4BackupRecordsV1 {
        let result = V4BackupRecordsV1(
            guidedSurveys: records.guidedSurveys,
            assetLocators: records.assetLocators,
            schedules: records.schedules,
            plans: records.plans,
            placementPoses: records.placementPoses,
            accessibleDocumentAssessments: records.accessibleDocumentAssessments,
            surveyDefinitions: records.surveyDefinitions,
            fieldReferences: records.fieldReferences,
            recoverabilityReceipts: records.recoverabilityReceipts,
            clientCapabilities: records.clientCapabilities,
            privacyTransforms: records.privacyTransforms,
            measurementIntegrity: records.measurementIntegrity,
            packageEvolution: records.packageEvolution,
            fieldDrafts: self.fieldDrafts,
            workPackets: records.workPackets,
            inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion,
            assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: self.assetPlacementEvents,
            assets: self.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: self.evidenceFiles,
            issues: self.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: mutationHistory,
            packets: self.packets,
            partyAccountability: records.partyAccountability,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: self.reports,
            requirementAssurance: self.requirementAssurance,
            savedSmartViews: records.savedSmartViews,
            sites: self.sites,
            workflowRecords: self.workflowRecords,
            evidenceContexts: records.evidenceContexts,
            pairedObservationLinks: records.pairedObservationLinks,
            lighting: records.lighting,
            lightingDayInventoryWorkflows: records.lightingDayInventoryWorkflows,
            lightingNightWorkflows: records.lightingNightWorkflows,
            assistanceAcceptanceReceipts: records.assistanceAcceptanceReceipts,
            temporalEvidence: records.temporalEvidence,
            acceptedLabelGenerationSnapshots: records.acceptedLabelGenerationSnapshots,
            operationalContacts: records.operationalContacts,
            activityContracts: records.activityContracts,
            workResources: records.workResources,
            serviceRequests: records.serviceRequests,
            serviceRequestDispositionEvents: records.serviceRequestDispositionEvents,
            serviceRequestWorkLinkEvents: records.serviceRequestWorkLinkEvents,
            serviceReliabilityIncidents: records.serviceReliabilityIncidents,
            serviceImpactSegments: records.serviceImpactSegments,
            serviceCauseAssertions: records.serviceCauseAssertions,
            serviceRemedyAssertions: records.serviceRemedyAssertions,
            serviceRepairIntervals: records.serviceRepairIntervals,
            serviceRestorationAssertions: records.serviceRestorationAssertions,
            qualifiedServiceExposures: records.qualifiedServiceExposures,
            serviceReliabilityReceipts: records.serviceReliabilityReceipts,
            partsStockSnapshot: records.partsStockSnapshot,
            myDayPlans: records.myDayPlans,
            myDayCarryoverReceipts: records.myDayCarryoverReceipts,
            nonactivePlanReferences: records.nonactivePlanReferences,
            evidenceAssociationEvents: records.evidenceAssociationEvents,
            evidenceSequenceRevisions: records.evidenceSequenceRevisions,
            shopReportProfiles: records.shopReportProfiles,
            roundSessions: self.roundSessions,
            importMappingProfiles: records.importMappingProfiles,
            bulkSessions: records.bulkSessions,
            bulkCommitReceipts: records.bulkCommitReceipts,
            evidenceQuality: records.evidenceQuality,
            fastSurveyInbox: records.fastSurveyInbox,
            reinspectionExceptionQueue: records.reinspectionExceptionQueue,
            entityIdentityResolution: records.entityIdentityResolution,
            practiceWorkspaceProvenance: records.practiceWorkspaceProvenance)
        return result
    }
}

struct CheckRunnerPhotoRestoreCompositionPlanV1: Equatable, Sendable {
    let sourcePhotoHistory: CheckRunnerPhotoBackupHistoryV1
    let currentPhotoHistory: CheckRunnerPhotoBackupHistoryV1
    let sourceSelection: CheckRunnerPhotoRestoreSourceSelectionV1
    let sourceBinding: CheckRunnerPhotoRestoreCompositionBindingV1
    let retainedCurrentBinding: CheckRunnerPhotoRestoreCompositionBindingV1?
    let mutationHistory: MutationHistorySnapshotV1
    let canonicalRows: CheckRunnerPhotoRestoreCanonicalRowsV1
    let retainedCurrentDrafts: [CheckRunnerPhotoRestoreDraftClosureV1]
    let retainedCurrentPhotoChildDraftIDs: [UUID]
    let retainedCurrentStageIDs: [UUID]
    let photoRestorePlans: [CheckRunnerPhotoBackupRestorePlanV1]

    func applying(to records: V4BackupRecordsV1) throws -> V4BackupRecordsV1 {
        let result = canonicalRows.applying(to: records, mutationHistory: mutationHistory)
        try requireDestination(result)
        return result
    }

    func requireDestination(_ records: V4BackupRecordsV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard records.mutationHistory == mutationHistory,
              records.assetPlacementEvents == canonicalRows.assetPlacementEvents,
              records.reports == canonicalRows.reports,
              records.fieldDrafts == canonicalRows.fieldDrafts,
              records.workflowRecords == canonicalRows.workflowRecords,
              records.evidenceFiles == canonicalRows.evidenceFiles,
              records.roundSessions == canonicalRows.roundSessions,
              records.assets == canonicalRows.assets,
              records.sites == canonicalRows.sites,
              records.packets == canonicalRows.packets,
              records.issues == canonicalRows.issues,
              records.requirementAssurance == canonicalRows.requirementAssurance else {
            throw failure
        }
        let selected = try sourceBinding.selectSource(in: records)
        guard selected == sourceSelection else { throw failure }
        let projected = try CheckRunnerPhotoBackupHistoryV1.project(
            source: sourceBinding.source, records: records)
        let byID = try checkRunnerPhotoRestoreDictionary(projected.children) {
            ($0.payload.childDraftID, $0)
        }
        let expectedIDs = Set(sourceSelection.children.map { $0.payload.childDraftID })
            .union(retainedCurrentPhotoChildDraftIDs)
        guard Set(byID.keys) == expectedIDs else { throw failure }
        let currentByID = try checkRunnerPhotoRestoreDictionary(currentPhotoHistory.children) {
            ($0.payload.childDraftID, $0)
        }
        for id in retainedCurrentPhotoChildDraftIDs {
            guard byID[id] == currentByID[id] else { throw failure }
        }
        if let retainedCurrentBinding {
            let retained = try retainedCurrentBinding.selectSource(in: records)
            guard retained.children.map({ $0.payload.childDraftID }) == retainedCurrentPhotoChildDraftIDs,
                  retained.children.allSatisfy({ currentByID[$0.payload.childDraftID] == $0 }) else { throw failure }
        } else if !retainedCurrentPhotoChildDraftIDs.isEmpty { throw failure }
    }
}

/// Pure same-workspace composition. All effects, live roots, restore intent,
/// generation installation, and raw publication remain owned by their existing
/// infrastructure services.
enum CheckRunnerPhotoRestoreCompositionV1 {
    /// A complete authenticated value closure. It grants no filesystem, writer,
    /// restore or publication authority. Only prepareCanonical can construct it.
    struct CanonicalPreparation: Equatable, Sendable {
        fileprivate let sourceRecords: V4BackupRecordsV1
        fileprivate let currentRecords: V4BackupRecordsV1
        fileprivate let sourceIdentity: WorkspaceReplicaIdentityV1
        fileprivate let currentIdentity: WorkspaceReplicaIdentityV1
        let sourceHistory: CheckRunnerPhotoBackupHistoryV1
        let currentHistory: CheckRunnerPhotoBackupHistoryV1
        fileprivate let historyUnion: CheckRunnerPhotoRestoreHistoryUnionV1
        fileprivate let sourceClosure: CanonicalClosure
        fileprivate let currentClosure: CanonicalClosure
        fileprivate let sourceBinding: CheckRunnerPhotoRestoreCompositionBindingV1
        fileprivate let sourceSelection: CheckRunnerPhotoRestoreSourceSelectionV1
        fileprivate let retainedCurrentBinding: CheckRunnerPhotoRestoreCompositionBindingV1?
        fileprivate let retainedDrafts: [CheckRunnerPhotoRestoreDraftClosureV1]
        fileprivate let retainedPhotoIDs: Set<UUID>
        fileprivate let retainedStageIDs: [UUID]
        fileprivate let retainedCurrentSelection: CheckRunnerPhotoRestoreSourceSelectionV1

        var mutationHistory: MutationHistorySnapshotV1 { historyUnion.merged }

        func requireOriginals(sourceRecords: V4BackupRecordsV1, currentRecords: V4BackupRecordsV1,
            sourceIdentity: WorkspaceReplicaIdentityV1, currentIdentity: WorkspaceReplicaIdentityV1) throws {
            guard self.sourceRecords == sourceRecords, self.currentRecords == currentRecords,
                  self.sourceIdentity == sourceIdentity, self.currentIdentity == currentIdentity else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }

        /// Add only authenticated retained rows before omission-derived packet
        /// tombstones are computed. The original source journal and ledger stay
        /// intact; the incumbent replacement rule still owns their merge.
        func includingRetainedRows(in sourceRecords: V4BackupRecordsV1) throws -> V4BackupRecordsV1 {
            guard sourceRecords == self.sourceRecords else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let rows = try CheckRunnerPhotoRestoreCompositionV1.mergedRows(
                base: sourceRecords, additions: currentClosure)
            return rows.applying(to: sourceRecords, mutationHistory: sourceRecords.mutationHistory)
        }
    }

    static func prepareCanonical(
        source: V4BackupSourceV1, sourceRecords: V4BackupRecordsV1,
        currentSource: V4BackupSourceV1, currentRecords: V4BackupRecordsV1,
        sourceIdentity: WorkspaceReplicaIdentityV1, currentIdentity: WorkspaceReplicaIdentityV1
    ) throws -> CanonicalPreparation {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard source.workspaceID == currentSource.workspaceID,
              source.workspaceID == sourceIdentity.workspaceID.rawValue,
              currentSource.workspaceID == currentIdentity.workspaceID.rawValue,
              source.recordsSchemaVersion == sourceRecords.recordsSchemaVersion,
              currentSource.recordsSchemaVersion == currentRecords.recordsSchemaVersion,
              sourceRecords.recordsSchemaVersion == currentRecords.recordsSchemaVersion,
              let sourceSnapshot = sourceRecords.mutationHistory,
              let currentSnapshot = currentRecords.mutationHistory else { throw failure }

        let sourceHistory = try CheckRunnerPhotoBackupHistoryV1.project(
            source: source, records: sourceRecords)
        let currentHistory = try CheckRunnerPhotoBackupHistoryV1.project(
            source: currentSource, records: currentRecords)
        guard !sourceHistory.children.isEmpty || !currentHistory.children.isEmpty else { throw failure }
        let historyUnion = try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: sourceSnapshot, current: currentSnapshot,
            sourceIdentity: sourceIdentity, currentIdentity: currentIdentity)
        try historyUnion.requireSourcePhotoHistory(sourceHistory)

        let sourceDrafts = try DraftProjection(records: sourceRecords)
        let currentDrafts = try DraftProjection(records: currentRecords)
        let sourceChildIDs = Set(sourceHistory.children.map { $0.payload.childDraftID })
        let sourceClosure = try canonicalClosure(
            history: sourceHistory, childDraftIDs: sourceChildIDs, records: sourceRecords)
        let sourceFootprint = try HistoryFootprint(records: sourceHistory.requiredHistory,
            draftProjection: sourceDrafts, canonicalClosure: sourceClosure)
        try requireNoCurrentTouch(source: sourceSnapshot, current: currentSnapshot,
                                  sourceFootprint: sourceFootprint)

        let sourceChildByID = try checkRunnerPhotoRestoreDictionary(sourceHistory.children) {
            ($0.payload.childDraftID, $0)
        }
        let currentChildByID = try checkRunnerPhotoRestoreDictionary(currentHistory.children) {
            ($0.payload.childDraftID, $0)
        }
        for (id, currentChild) in currentChildByID where sourceChildByID[id] != nil {
            guard sourceChildByID[id] == currentChild else { throw failure }
        }
        let retainedPhotoIDs = Set(currentChildByID.keys).subtracting(sourceChildByID.keys)
        let retainedCurrentSelection = CheckRunnerPhotoRestoreSourceSelectionV1(
            source: currentSource,
            children: retainedPhotoIDs.sorted(by: uuidLess).compactMap { currentChildByID[$0] })

        let retainedDrafts = try retainedCurrentDraftClosures(
            source: draftClosures(sourceDrafts), current: draftClosures(currentDrafts))

        let retainedPhotoClosure = try canonicalClosure(history: currentHistory,
            childDraftIDs: retainedPhotoIDs, records: currentRecords)
        let retainedDraftClosure = try canonicalClosure(
            draftClosures: retainedDrafts, records: currentRecords)
        let currentClosure = try merged(retainedPhotoClosure, retainedDraftClosure)

        let sourceBinding = try CheckRunnerPhotoRestoreCompositionBindingV1(
            sourceHistory: sourceHistory, records: sourceRecords)
        let sourceSelection = try sourceBinding.selectSource(in: sourceRecords)
        let retainedCurrentBinding: CheckRunnerPhotoRestoreCompositionBindingV1?
        if retainedPhotoIDs.isEmpty { retainedCurrentBinding = nil }
        else {
            retainedCurrentBinding = try .init(sourceHistory: currentHistory,
                records: currentRecords, selecting: retainedPhotoIDs)
        }
        let retainedStageIDs = Set(retainedDrafts.flatMap(\.stageIDs)).sorted(by: uuidLess)
        return CanonicalPreparation(sourceRecords: sourceRecords, currentRecords: currentRecords,
            sourceIdentity: sourceIdentity, currentIdentity: currentIdentity,
            sourceHistory: sourceHistory, currentHistory: currentHistory,
            historyUnion: historyUnion, sourceClosure: sourceClosure, currentClosure: currentClosure,
            sourceBinding: sourceBinding, sourceSelection: sourceSelection,
            retainedCurrentBinding: retainedCurrentBinding, retainedDrafts: retainedDrafts,
            retainedPhotoIDs: retainedPhotoIDs, retainedStageIDs: retainedStageIDs,
            retainedCurrentSelection: retainedCurrentSelection)
    }

    static func compose(
        source: V4BackupSourceV1,
        sourceRecords: V4BackupRecordsV1,
        sourcePlan: CheckRunnerPhotoBackupRestorePlanV1,
        currentSource: V4BackupSourceV1,
        currentRecords: V4BackupRecordsV1,
        currentPlan: CheckRunnerPhotoBackupRestorePlanV1?,
        replacementRecords: V4BackupRecordsV1,
        sourceIdentity: WorkspaceReplicaIdentityV1,
        currentIdentity: WorkspaceReplicaIdentityV1
    ) throws -> CheckRunnerPhotoRestoreCompositionPlanV1 {
        let preparation = try prepareCanonical(source: source, sourceRecords: sourceRecords,
            currentSource: currentSource, currentRecords: currentRecords,
            sourceIdentity: sourceIdentity, currentIdentity: currentIdentity)
        return try compose(preparation: preparation, sourcePlan: sourcePlan,
            currentPlan: currentPlan, replacementRecords: replacementRecords)
    }

    static func compose(preparation: CanonicalPreparation,
        sourcePlan: CheckRunnerPhotoBackupRestorePlanV1,
        currentPlan: CheckRunnerPhotoBackupRestorePlanV1?, replacementRecords: V4BackupRecordsV1
    ) throws -> CheckRunnerPhotoRestoreCompositionPlanV1 {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let sourceHistory = preparation.sourceHistory, currentHistory = preparation.currentHistory
        let source = sourceHistory.source, currentSource = currentHistory.source
        guard replacementRecords.recordsSchemaVersion == preparation.sourceRecords.recordsSchemaVersion,
              let destinationSnapshot = replacementRecords.mutationHistory else { throw failure }
        try preparation.historyUnion.requireDestination(destinationSnapshot)
        // Explicit deletion never authorizes resurrecting an authenticated row.
        // Reject an incompatible deletion-filtered destination before any merge.
        try preparation.sourceClosure.requireSubset(of: replacementRecords)
        try preparation.currentClosure.requireSubset(of: replacementRecords)
        if !preparation.currentClosure.assets.isEmpty {
            try requireUncopiedPlacementDependencies(from: preparation.currentRecords,
                in: replacementRecords)
        }
        let sourceMemberBinding = try CheckRunnerPhotoRestoreMemberBindingV1(plan: sourcePlan)
        guard sourcePlan.source == source,
              try sourceMemberBinding.resolve(history: sourceHistory) == sourcePlan else { throw failure }
        let currentMemberBinding = try currentPlan.map {
            try CheckRunnerPhotoRestoreMemberBindingV1(plan: $0)
        }
        if let currentPlan, let currentMemberBinding {
            guard currentPlan.source == currentSource,
                  try currentMemberBinding.resolve(history: currentHistory) == currentPlan else { throw failure }
        } else if !currentHistory.children.isEmpty {
            throw failure
        }

        let retainedPhotoIDs = preparation.retainedPhotoIDs
        let retainedCurrentSelection = preparation.retainedCurrentSelection
        var retainedPlans: [CheckRunnerPhotoBackupRestorePlanV1] = [sourcePlan]
        if !retainedPhotoIDs.isEmpty {
            guard let currentPlan, let currentMemberBinding else { throw failure }
            let selectedPlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
                sourceSelection: retainedCurrentSelection,
                entries: currentMemberBinding.entries) { path in
                    guard let value = currentPlan.metadata[path] else { throw failure }
                    return value
                }
            retainedPlans.append(selectedPlan)
        }

        let finalRows = try mergedRows(base: replacementRecords, additions: preparation.currentClosure)
        return CheckRunnerPhotoRestoreCompositionPlanV1(
            sourcePhotoHistory: sourceHistory, currentPhotoHistory: currentHistory,
            sourceSelection: preparation.sourceSelection, sourceBinding: preparation.sourceBinding,
            retainedCurrentBinding: preparation.retainedCurrentBinding,
            mutationHistory: preparation.historyUnion.merged, canonicalRows: finalRows,
            retainedCurrentDrafts: preparation.retainedDrafts,
            retainedCurrentPhotoChildDraftIDs: retainedPhotoIDs.sorted(by: uuidLess),
            retainedCurrentStageIDs: preparation.retainedStageIDs, photoRestorePlans: retainedPlans)
    }

    fileprivate static func mergedRows(base: V4BackupRecordsV1, additions: CanonicalClosure) throws
        -> CheckRunnerPhotoRestoreCanonicalRowsV1 {
        let finalFieldDrafts = try merged(base: base.fieldDrafts,
            additions: additions.fieldDrafts, key: fieldDraftKey, less: fieldDraftLess)
        return CheckRunnerPhotoRestoreCanonicalRowsV1(
            assetPlacementEvents: try merged(base: base.assetPlacementEvents,
                additions: additions.assetPlacementEvents, key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            reports: try merged(base: base.reports, additions: additions.reports,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            fieldDrafts: finalFieldDrafts,
            workflowRecords: try merged(base: base.workflowRecords,
                additions: additions.workflowRecords, key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            evidenceFiles: try merged(base: base.evidenceFiles,
                additions: additions.evidenceFiles, key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            roundSessions: try merged(base: base.roundSessions,
                additions: additions.roundSessions,
                key: { "\($0.sessionID.uuidString.lowercased()):\($0.revision)" },
                less: roundLess),
            assets: try merged(base: base.assets, additions: additions.assets,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            sites: try merged(base: base.sites, additions: additions.sites,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            packets: try merged(base: base.packets, additions: additions.packets,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            issues: try merged(base: base.issues, additions: additions.issues,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            requirementAssurance: try merged(base: base.requirementAssurance,
                additions: additions.requirementAssurance,
                key: { "\($0.workflowRecordID.uuidString.lowercased()):\($0.snapshotSHA256)" },
                less: { lhs, rhs in
                    "\(lhs.workflowRecordID.uuidString.lowercased()):\(lhs.snapshotSHA256)"
                        < "\(rhs.workflowRecordID.uuidString.lowercased()):\(rhs.snapshotSHA256)"
                }))

    }

    /// Authenticates complete canonical/journal families without granting any
    /// restore authority. Typed payload closure is resolved separately by
    /// composition, so this remains a narrow value-only test seam.
    static func authenticatedDraftClosures(in records: V4BackupRecordsV1) throws
        -> [CheckRunnerPhotoRestoreDraftClosureV1] {
        draftClosures(try DraftProjection(records: records))
    }

    /// Reconstructs a canonical draft frontier from exact accepted journal
    /// records. The caller may use this to compare a previously frozen frontier
    /// with the current complete family; it never invents a receipt or payload.
    static func authenticatedDraftClosure(
        draftID: UUID,
        history originals: [MutationHistoryReceiptRecordV1]
    ) throws -> CheckRunnerPhotoRestoreDraftClosureV1 {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var history: [AuthenticatedHistoryRecord] = []
        var keys = Set<String>()
        for original in originals {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
            guard case let .applyFieldDraft(mutation) = envelope.command,
                  try CheckRunnerPhotoRestoreCompositionV1.draftID(mutation.postImage) == draftID,
                  keys.insert(historyKey(envelope)).inserted else { throw failure }
            _ = try FieldDraftCommittedEvidenceV1(envelope: envelope, receipt: receipt)
            history.append(.init(original: original, envelope: envelope, receipt: receipt))
        }
        history.sort { historyKey($0.envelope) < historyKey($1.envelope) }
        let rows = try latestRows(history.flatMap { record -> [V16BackupFieldDraftRecordV1] in
            guard case let .applyFieldDraft(mutation) = record.envelope.command else {
                throw failure
            }
            return try canonicalRows(mutation.postImage)
        })
        let closure = CheckRunnerPhotoRestoreDraftClosureV1(
            draftID: draftID, rows: rows, history: history.map(\.original),
            stageIDs: rows.filter { $0.kind == .stagingItem }.map(\.id).sorted(by: uuidLess))
        guard try checkedDraftFamilies([closure])[draftID] != nil else { throw failure }
        return closure
    }

    /// Selects only complete current-only families. Exact duplicate source
    /// families need no amendment; every conflicting or scope-sharing family
    /// fails before the restore owner can perform effects.
    static func retainedCurrentDraftClosures(
        source: [CheckRunnerPhotoRestoreDraftClosureV1],
        current: [CheckRunnerPhotoRestoreDraftClosureV1]
    ) throws -> [CheckRunnerPhotoRestoreDraftClosureV1] {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let sourceFamilies = try checkedDraftFamilies(source)
        let currentFamilies = try checkedDraftFamilies(current)
        let sourceScopes = Set(sourceFamilies.values.flatMap(\.scopeSHA256s))
        let sourceAnchors = Set(sourceFamilies.values.flatMap(\.resumeAnchorSHA256s))
        var retained: [CheckRunnerPhotoRestoreDraftClosureV1] = []
        for id in currentFamilies.keys.sorted(by: uuidLess) {
            guard let family = currentFamilies[id] else { throw failure }
            if let source = sourceFamilies[id] {
                guard source == family else { throw failure }
                continue
            }
            guard family.scopeSHA256s.isDisjoint(with: sourceScopes),
                  family.resumeAnchorSHA256s.isDisjoint(with: sourceAnchors),
                  let closure = current.first(where: { $0.draftID == id }) else { throw failure }
            retained.append(closure)
        }
        return retained
    }

    /// Verifies causal disjointness using original accepted records. Resulting
    /// workspace revision vectors are deliberately excluded because they are a
    /// census, not a dependency of the command that produced the receipt.
    static func requireDisjointHistory(
        source: [MutationHistoryReceiptRecordV1],
        current: [MutationHistoryReceiptRecordV1]
    ) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var sourceFootprint = HistoryFootprint()
        var sourceByKey: [String: MutationHistoryReceiptRecordV1] = [:]
        for original in source {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
            let key = historyKey(envelope)
            guard sourceByKey.updateValue(original, forKey: key) == nil else { throw failure }
            try sourceFootprint.include(envelope, receipt)
        }
        for original in current {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            let key = historyKey(envelope)
            if let exact = sourceByKey[key] {
                guard exact == original else { throw failure }
                continue
            }
            let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
            var footprint = HistoryFootprint()
            try footprint.include(envelope, receipt)
            guard !sourceFootprint.intersects(footprint) else { throw failure }
        }
    }
}

fileprivate extension CheckRunnerPhotoRestoreCompositionV1 {
    struct AuthenticatedHistoryRecord: Equatable, Sendable {
        let original: MutationHistoryReceiptRecordV1
        let envelope: MutationEnvelopeV1
        let receipt: MutationReceiptV1
    }

    struct DraftFamily: Equatable, Sendable {
        let draftID: UUID
        let rows: [V16BackupFieldDraftRecordV1]
        let history: [AuthenticatedHistoryRecord]
        let stageIDs: [UUID]
        let scopeSHA256s: Set<String>
        let resumeAnchorSHA256s: Set<String>
    }

    struct DraftProjection: Sendable {
        let families: [UUID: DraftFamily]
        let scopeSHA256s: Set<String>
        let resumeAnchorSHA256s: Set<String>

        init(records: V4BackupRecordsV1) throws {
            let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
            guard let snapshot = records.mutationHistory else { throw failure }
            try MutationJournalStoreV1.validateImportedSnapshot(snapshot)
            var rowsByDraft: [UUID: [V16BackupFieldDraftRecordV1]] = [:]
            var checkpointsByDraft: [UUID: [FieldDraftCheckpointV1]] = [:]
            var stageIDsByDraft: [UUID: Set<UUID>] = [:]
            var rowKeys = Set<String>()
            for row in records.fieldDrafts {
                guard rowKeys.insert(fieldDraftKey(row)).inserted else { throw failure }
                let value = try decodedRow(row)
                guard value.workspaceID.rawValue == row.workspaceID,
                      value.id == row.id, value.revision == row.revision else { throw failure }
                rowsByDraft[value.draftID, default: []].append(row)
                if let checkpoint = value.checkpoint {
                    checkpointsByDraft[value.draftID, default: []].append(checkpoint)
                }
                if row.kind == .stagingItem {
                    stageIDsByDraft[value.draftID, default: []].insert(row.id)
                }
            }
            var historyByDraft: [UUID: [AuthenticatedHistoryRecord]] = [:]
            for original in snapshot.receipts {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
                guard case let .applyFieldDraft(mutation) = envelope.command else { continue }
                let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
                _ = try FieldDraftCommittedEvidenceV1(envelope: envelope, receipt: receipt)
                let draftID = try draftID(mutation.postImage)
                historyByDraft[draftID, default: []].append(.init(
                    original: original, envelope: envelope, receipt: receipt))
            }
            guard Set(rowsByDraft.keys) == Set(historyByDraft.keys) else { throw failure }
            var result: [UUID: DraftFamily] = [:]
            var allScopes = Set<String>(), allAnchors = Set<String>()
            for draftID in rowsByDraft.keys {
                guard let rows = rowsByDraft[draftID], let history = historyByDraft[draftID],
                      let checkpoints = checkpointsByDraft[draftID], !checkpoints.isEmpty else {
                    throw failure
                }
                let produced = try history.flatMap { record -> [V16BackupFieldDraftRecordV1] in
                    guard case let .applyFieldDraft(mutation) = record.envelope.command else {
                        throw failure
                    }
                    return try canonicalRows(mutation.postImage)
                }
                let latest = try latestRows(produced)
                let sortedRows = rows.sorted(by: fieldDraftLess)
                guard latest == sortedRows else { throw failure }
                let scopes = try Set(checkpoints.map {
                    CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode($0.scope))
                })
                let anchors = try Set(checkpoints.map {
                    CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode($0.resumeAnchor))
                })
                allScopes.formUnion(scopes); allAnchors.formUnion(anchors)
                result[draftID] = .init(draftID: draftID, rows: sortedRows,
                    history: history.sorted { historyKey($0.envelope) < historyKey($1.envelope) },
                    stageIDs: Array(stageIDsByDraft[draftID, default: []]).sorted(by: uuidLess),
                    scopeSHA256s: scopes, resumeAnchorSHA256s: anchors)
            }
            families = result; scopeSHA256s = allScopes; resumeAnchorSHA256s = allAnchors
        }
    }

    static func draftClosures(_ projection: DraftProjection)
        -> [CheckRunnerPhotoRestoreDraftClosureV1] {
        projection.families.keys.sorted(by: uuidLess).compactMap { id in
            projection.families[id].map {
                .init(draftID: id, rows: $0.rows,
                      history: $0.history.map(\.original), stageIDs: $0.stageIDs)
            }
        }
    }

    static func checkedDraftFamilies(_ closures: [CheckRunnerPhotoRestoreDraftClosureV1]) throws
        -> [UUID: DraftFamily] {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard closures.map(\.draftID) == closures.map(\.draftID).sorted(by: uuidLess),
              Set(closures.map(\.draftID)).count == closures.count else { throw failure }
        var result: [UUID: DraftFamily] = [:]
        for closure in closures {
            guard !closure.rows.isEmpty, !closure.history.isEmpty,
                  closure.rows == closure.rows.sorted(by: fieldDraftLess),
                  closure.stageIDs == closure.stageIDs.sorted(by: uuidLess),
                  Set(closure.stageIDs).count == closure.stageIDs.count else { throw failure }
            var checkpoints: [FieldDraftCheckpointV1] = []
            var rowStageIDs = Set<UUID>(), rowKeys = Set<String>()
            for row in closure.rows {
                guard rowKeys.insert(fieldDraftKey(row)).inserted else { throw failure }
                let decoded = try decodedRow(row)
                guard decoded.draftID == closure.draftID,
                      decoded.workspaceID.rawValue == row.workspaceID,
                      decoded.id == row.id, decoded.revision == row.revision else { throw failure }
                decoded.checkpoint.map { checkpoints.append($0) }
                if row.kind == .stagingItem { rowStageIDs.insert(row.id) }
            }
            guard !checkpoints.isEmpty,
                  closure.stageIDs == rowStageIDs.sorted(by: uuidLess) else { throw failure }
            var history: [AuthenticatedHistoryRecord] = []
            var historyKeys = Set<String>()
            for original in closure.history {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
                let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
                guard case let .applyFieldDraft(mutation) = envelope.command,
                      try draftID(mutation.postImage) == closure.draftID,
                      historyKeys.insert(historyKey(envelope)).inserted else { throw failure }
                _ = try FieldDraftCommittedEvidenceV1(envelope: envelope, receipt: receipt)
                history.append(.init(original: original, envelope: envelope, receipt: receipt))
            }
            history.sort { historyKey($0.envelope) < historyKey($1.envelope) }
            guard closure.history == history.map(\.original) else { throw failure }
            let produced = try history.flatMap { record -> [V16BackupFieldDraftRecordV1] in
                guard case let .applyFieldDraft(mutation) = record.envelope.command else {
                    throw failure
                }
                return try canonicalRows(mutation.postImage)
            }
            guard try latestRows(produced) == closure.rows else { throw failure }
            let scopes = try Set(checkpoints.map {
                CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode($0.scope))
            })
            let anchors = try Set(checkpoints.map {
                CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode($0.resumeAnchor))
            })
            result[closure.draftID] = .init(draftID: closure.draftID, rows: closure.rows,
                history: history, stageIDs: closure.stageIDs,
                scopeSHA256s: scopes, resumeAnchorSHA256s: anchors)
        }
        return result
    }

    struct DecodedDraftRow {
        let workspaceID: WorkspaceID
        let draftID: UUID
        let id: UUID
        let revision: UInt64
        let checkpoint: FieldDraftCheckpointV1?
    }

    struct HistoryFootprint {
        var entityIdentities = Set<WorkspaceEntityIdentityV1>()
        var mutationKeys = Set<String>()
        var contentDependencies = Set<String>()
        var correlationIDs = Set<UUID>()
        var draftIDs = Set<UUID>()
        var stageIDs = Set<UUID>()
        var scopeSHA256s = Set<String>()
        var resumeAnchorSHA256s = Set<String>()

        init(records: [RepetitiveCaptureSourceHistoryRecordV2],
             draftProjection: DraftProjection,
             canonicalClosure: CanonicalClosure) throws {
            self.init()
            for record in records { try include(record.envelope, record.receipt) }
            draftIDs.formUnion(draftProjection.families.keys)
            stageIDs.formUnion(draftProjection.families.values.flatMap(\.stageIDs))
            scopeSHA256s.formUnion(draftProjection.scopeSHA256s)
            resumeAnchorSHA256s.formUnion(draftProjection.resumeAnchorSHA256s)
            try include(canonicalClosure)
        }

        init() {}

        mutating func include(_ envelope: MutationEnvelopeV1,
                              _ receipt: MutationReceiptV1) throws {
            mutationKeys.insert(historyKey(envelope))
            if let id = envelope.causationMutationID {
                mutationKeys.insert(MutationWorkspaceKeyV1.value(
                    workspaceID: envelope.workspaceID, mutationID: id))
            }
            if let id = receipt.reversesMutationID {
                mutationKeys.insert(MutationWorkspaceKeyV1.value(
                    workspaceID: envelope.workspaceID, mutationID: id))
            }
            contentDependencies.formUnion(envelope.contentDependencyIDs)
            correlationIDs.formUnion([envelope.correlationID].compactMap { $0 })
            for image in receipt.postImages {
                entityIdentities.insert(try image.identity)
                entityIdentities.insert(try image.concurrencyIdentity)
            }
            try includeReferences(envelope.command)
            if case let .applyFieldDraft(mutation) = envelope.command {
                entityIdentities.formUnion(try mutation.affectedIdentities)
                entityIdentities.formUnion(try mutation.concurrencyIdentities)
                let facts = try draftFacts(mutation.postImage)
                entityIdentities.formUnion(facts.entityIdentities)
                draftIDs.formUnion(facts.draftIDs); stageIDs.formUnion(facts.stageIDs)
                scopeSHA256s.formUnion(facts.scopeSHA256s)
                resumeAnchorSHA256s.formUnion(facts.resumeAnchorSHA256s)
            }
        }

        mutating func include(_ closure: CanonicalClosure) throws {
            for row in closure.fieldDrafts {
                let kind: WorkspaceEntityKindV1
                switch row.kind {
                case .checkpoint: kind = .fieldDraftCheckpoint
                case .stagingItem: kind = .attachmentStagingItem
                case .commitSaga: kind = .draftCommitSaga
                case .contentReservation: kind = .draftContentReservation
                case .commitReceipt: kind = .draftCommitReceipt
                case .discardReceipt: kind = .draftDiscardReceipt
                }
                entityIdentities.insert(try .init(kind: kind, id: row.id))
            }
            for row in closure.workflowRecords {
                entityIdentities.insert(try .init(kind: .workflowRecord, id: row.id))
            }
            for row in closure.assetPlacementEvents {
                entityIdentities.insert(try .init(kind: .assetPlacementEvent, id: row.id))
            }
            for row in closure.reports {
                entityIdentities.insert(try .init(kind: .report, id: row.id))
            }
            for row in closure.evidenceFiles {
                entityIdentities.insert(try .init(kind: .evidenceFile, id: row.id))
            }
            for row in closure.roundSessions {
                entityIdentities.insert(try .init(kind: .roundSession, id: row.sessionID))
            }
            for row in closure.assets {
                entityIdentities.insert(try .init(kind: .asset, id: row.id))
            }
            for row in closure.sites {
                entityIdentities.insert(try .init(kind: .site, id: row.id))
            }
            for row in closure.packets {
                entityIdentities.insert(try .init(kind: .packet, id: row.id))
            }
            for row in closure.issues {
                entityIdentities.insert(try .init(kind: .issue, id: row.id))
            }
        }

        mutating func includeReferences(_ command: WorkspaceCommandV1) throws {
            func add(_ kind: WorkspaceEntityKindV1, _ id: UUID?) throws {
                if let id { entityIdentities.insert(try .init(kind: kind, id: id)) }
            }
            switch command {
            case let .createFirstSign(value):
                try add(.site, value.siteID); try add(.asset, value.assetID)
            case let .createCheckDraft(value):
                try add(.workflowRecord, value.recordID); try add(.asset, value.assetID)
                try add(.issue, value.issueID); try add(.workflowRecord, value.parentRecordID)
            case let .acceptCheckEvidence(value):
                try add(.workflowRecord, value.draftID); try add(.evidenceFile, value.evidenceID)
            case let .updateSiteTimeZone(value): try add(.site, value.siteID)
            case let .deleteAsset(value): try add(.asset, value.assetID)
            case let .deleteSite(value): try add(.site, value.siteID)
            case let .finalizeCheck(value):
                try add(.asset, value.assetID); try add(.workflowRecord, value.recordID)
                try add(.packet, value.packetID); try add(.issue, value.issueID)
                if let authority = value.writerAuthority {
                    entityIdentities.formUnion(try authority.affectedIdentities)
                }
            case let .finalizeCorrection(value):
                try add(.asset, value.assetID); try add(.workflowRecord, value.correctionRecordID)
                try add(.workflowRecord, value.revisesRecordID); try add(.packet, value.packetID)
                if let authority = value.writerAuthority {
                    entityIdentities.formUnion(try authority.affectedIdentities)
                }
            case let .recordWork(value):
                try add(.asset, value.assetID); try add(.issue, value.issueID)
                try add(.workflowRecord, value.recordID)
                for id in value.evidenceIDs { try add(.evidenceFile, id) }
                if let authority = value.writerAuthority {
                    entityIdentities.formUnion(try authority.affectedIdentities)
                }
            case let .archiveEntities(value): entityIdentities.formUnion(value.identities)
            case let .applyRequirementAssurance(value):
                try add(.workflowRecord, value.snapshot.workflowRecordID)
            case let .applyRoundSession(value):
                try add(.roundSession, value.session.sessionID)
                for item in value.session.items {
                    try add(.asset, item.selection.assetID); try add(.site, item.selection.siteID)
                    try add(.workflowRecord, item.completion?.completionID)
                }
            case .applyFieldDraft,
                 .applyPartyAccountability, .applyPackagePromotion,
                 .applySurveyDefinition, .applySurveySession, .applyTemporalEvidence,
                 .transitionReportPDF:
                break
            default:
                // No released domain utility declares immutable references for
                // the remaining command families. Reject instead of scanning
                // opaque canonical payloads for UUID-shaped strings.
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }

        func intersects(_ other: Self) -> Bool {
            !entityIdentities.isDisjoint(with: other.entityIdentities)
                || !mutationKeys.isDisjoint(with: other.mutationKeys)
                || !contentDependencies.isDisjoint(with: other.contentDependencies)
                || !correlationIDs.isDisjoint(with: other.correlationIDs)
                || !draftIDs.isDisjoint(with: other.draftIDs)
                || !stageIDs.isDisjoint(with: other.stageIDs)
                || !scopeSHA256s.isDisjoint(with: other.scopeSHA256s)
                || !resumeAnchorSHA256s.isDisjoint(with: other.resumeAnchorSHA256s)
        }
    }

    struct DraftFacts {
        var entityIdentities = Set<WorkspaceEntityIdentityV1>()
        var draftIDs = Set<UUID>()
        var stageIDs = Set<UUID>()
        var scopeSHA256s = Set<String>()
        var resumeAnchorSHA256s = Set<String>()
    }

    struct CanonicalClosure: Equatable, Sendable {
        let assetPlacementEvents: [V5BackupLocationRecordV1]
        let reports: [V4BackupReportDTO]
        let fieldDrafts: [V16BackupFieldDraftRecordV1]
        let workflowRecords: [V4BackupWorkflowRecordDTO]
        let evidenceFiles: [V4BackupEvidenceFileDTO]
        let roundSessions: [RoundSessionV1]
        let assets: [V4BackupAssetDTO]
        let sites: [V4BackupSiteDTO]
        let packets: [V4BackupPacketDTO]
        let issues: [V4BackupIssueDTO]
        let requirementAssurance: [V8BackupRequirementAssuranceRecordV1]
        let sha256: String

        func requireSubset(of records: V4BackupRecordsV1) throws {
            let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
            guard try isSubset(assetPlacementEvents, of: records.assetPlacementEvents,
                    key: { $0.id.uuidString.lowercased() }),
                  try isSubset(reports, of: records.reports, key: { $0.id.uuidString.lowercased() }),
                  try isSubset(fieldDrafts, of: records.fieldDrafts, key: fieldDraftKey),
                  try isSubset(workflowRecords, of: records.workflowRecords,
                    key: { $0.id.uuidString.lowercased() }),
                  try isSubset(evidenceFiles, of: records.evidenceFiles,
                    key: { $0.id.uuidString.lowercased() }),
                  try isSubset(roundSessions, of: records.roundSessions,
                    key: { "\($0.sessionID.uuidString.lowercased()):\($0.revision)" }),
                  try isSubset(assets, of: records.assets,
                    key: { $0.id.uuidString.lowercased() }),
                  try isSubset(sites, of: records.sites,
                    key: { $0.id.uuidString.lowercased() }),
                  try isSubset(packets, of: records.packets,
                    key: { $0.id.uuidString.lowercased() }),
                  try isSubset(issues, of: records.issues,
                    key: { $0.id.uuidString.lowercased() }),
                  try isSubset(requirementAssurance, of: records.requirementAssurance,
                    key: { "\($0.workflowRecordID.uuidString.lowercased()):\($0.snapshotSHA256)" })
            else { throw failure }
        }
    }

    struct LegacyCanonicalClosureBasisV1: Codable {
        let fieldDrafts: [V16BackupFieldDraftRecordV1]
        let workflowRecords: [V4BackupWorkflowRecordDTO]
        let evidenceFiles: [V4BackupEvidenceFileDTO]
        let roundSessions: [RoundSessionV1]
        let assets: [V4BackupAssetDTO]
        let sites: [V4BackupSiteDTO]
        let packets: [V4BackupPacketDTO]
        let issues: [V4BackupIssueDTO]
        let requirementAssurance: [V8BackupRequirementAssuranceRecordV1]
    }

    struct CanonicalClosureBasisV2: Codable {
        let assetPlacementEvents: [V5BackupLocationRecordV1]
        let reports: [V4BackupReportDTO]
        let fieldDrafts: [V16BackupFieldDraftRecordV1]
        let workflowRecords: [V4BackupWorkflowRecordDTO]
        let evidenceFiles: [V4BackupEvidenceFileDTO]
        let roundSessions: [RoundSessionV1]
        let assets: [V4BackupAssetDTO]
        let sites: [V4BackupSiteDTO]
        let packets: [V4BackupPacketDTO]
        let issues: [V4BackupIssueDTO]
        let requirementAssurance: [V8BackupRequirementAssuranceRecordV1]
    }

    static func canonicalClosure(history: CheckRunnerPhotoBackupHistoryV1,
                                 childDraftIDs: Set<UUID>,
                                 records: V4BackupRecordsV1, bindingVersion: Int = 2) throws -> CanonicalClosure {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard bindingVersion == 1 || bindingVersion == 2 else { throw failure }
        if childDraftIDs.isEmpty {
            return try makeCanonicalClosure(fieldDrafts: [], workflowRecords: [], evidenceFiles: [],
                roundSessions: [], assets: [], sites: [], packets: [], issues: [],
                requirementAssurance: [], reports: [], bindingVersion: bindingVersion)
        }
        let children = history.children.filter { childDraftIDs.contains($0.payload.childDraftID) }
        guard children.count == childDraftIDs.count else { throw failure }
        var draftIDs = Set<UUID>()
        var workflowIDs = Set<UUID>(), evidenceIDs = Set<UUID>(), sessionIDs = Set<UUID>()
        var assetIDs = Set<UUID>(), siteIDs = Set<UUID>()
        for child in children {
            draftIDs.formUnion([child.payload.childDraftID, child.payload.parentDraftID])
            draftIDs.formUnion(child.sourceGraph.checkpoints.map { $0.current.draftID })
            workflowIDs.insert(child.payload.recordID)
            assetIDs.insert(child.payload.assetID)
            sessionIDs.insert(child.sourceGraph.packageCurrentRound.sessionID)
            sessionIDs.insert(child.payload.sourceBinding.roundAtEntry.sessionID)
            if let target = child.targetRecords {
                workflowIDs.insert(target.workflow.id); evidenceIDs.insert(target.evidence.id)
            }
        }
        var changed = true
        while changed {
            changed = false
            for row in records.workflowRecords where workflowIDs.contains(row.id) {
                let linked = [row.recordRevisionRootID]
                    + [row.parentRecordID, row.revisesRecordID,
                       row.evidenceSourceRecordID].compactMap { $0 }
                for id in linked {
                    changed = workflowIDs.insert(id).inserted || changed
                }
            }
        }
        let reports = bindingVersion == 2
            ? try completeReportDependencies(workflowIDs: &workflowIDs, records: records) : []
        if bindingVersion == 2 {
            evidenceIDs.formUnion(records.evidenceFiles.filter { workflowIDs.contains($0.recordID) }.map(\.id))
        }
        let workflows = records.workflowRecords.filter { workflowIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(workflows.map(\.id)) == workflowIDs else { throw failure }
        assetIDs.formUnion(workflows.map(\.assetID))
        let rounds = records.roundSessions.filter { sessionIDs.contains($0.sessionID) }
            .sorted(by: roundLess)
        guard Set(rounds.map(\.sessionID)) == sessionIDs else { throw failure }
        for round in rounds {
            assetIDs.formUnion(round.items.map { $0.selection.assetID })
            siteIDs.formUnion(round.items.map { $0.selection.siteID })
        }
        let assets = records.assets.filter { assetIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(assets.map(\.id)) == assetIDs else { throw failure }
        siteIDs.formUnion(assets.map(\.siteID))
        let placementRows = try placementClosure(assetIDs: assetIDs, records: records,
            siteIDs: &siteIDs, enabled: bindingVersion == 2)
        let sites = records.sites.filter { siteIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(sites.map(\.id)) == siteIDs else { throw failure }
        let evidence = records.evidenceFiles.filter { evidenceIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(evidence.map(\.id)) == evidenceIDs else { throw failure }
        let packetIDs = Set(workflows.compactMap(\.packetID)).union(reports.map(\.packetID))
        let packets = records.packets.filter { packetIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(packets.map(\.id)) == packetIDs else { throw failure }
        let issueIDs = Set(workflows.compactMap(\.issueID))
        let issues = records.issues.filter { issueIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(issues.map(\.id)) == issueIDs else { throw failure }
        let drafts = try DraftProjection(records: records)
        let fieldDrafts = try draftIDs.flatMap { id -> [V16BackupFieldDraftRecordV1] in
            guard let family = drafts.families[id] else { throw failure }
            return family.rows
        }.sorted(by: fieldDraftLess)
        let assurance = records.requirementAssurance.filter {
            workflowIDs.contains($0.workflowRecordID)
        }.sorted {
            "\($0.workflowRecordID.uuidString.lowercased()):\($0.snapshotSHA256)"
                < "\($1.workflowRecordID.uuidString.lowercased()):\($1.snapshotSHA256)"
        }
        return try makeCanonicalClosure(fieldDrafts: fieldDrafts, workflowRecords: workflows,
            evidenceFiles: evidence, roundSessions: rounds, assets: assets, sites: sites,
            packets: packets, issues: issues, requirementAssurance: assurance,
            reports: reports, assetPlacementEvents: placementRows, bindingVersion: bindingVersion)
    }

    /// Resolves the complete canonical family of current-only drafts through
    /// their typed payload codecs. A codec is admitted only when every external
    /// reference it can carry is represented by one of the canonical row kinds
    /// copied below. Opaque codecs and unsupported My Day variants fail closed.
    static func canonicalClosure(draftClosures: [CheckRunnerPhotoRestoreDraftClosureV1],
                                 records: V4BackupRecordsV1) throws -> CanonicalClosure {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        if draftClosures.isEmpty {
            return try makeCanonicalClosure(fieldDrafts: [], workflowRecords: [], evidenceFiles: [],
                roundSessions: [], assets: [], sites: [], packets: [], issues: [],
                requirementAssurance: [])
        }
        let projection = try DraftProjection(records: records)
        let checked = try checkedDraftFamilies(draftClosures)
        var draftIDs = Set(checked.keys)
        var workflowIDs = Set<UUID>(), evidenceIDs = Set<UUID>(), sessionIDs = Set<UUID>()
        var assetIDs = Set<UUID>(), siteIDs = Set<UUID>(), packetIDs = Set<UUID>(), issueIDs = Set<UUID>()
        var processedDraftIDs = Set<UUID>()

        while let draftID = draftIDs.subtracting(processedDraftIDs).sorted(by: uuidLess).first {
            guard let family = projection.families[draftID] else { throw failure }
            processedDraftIDs.insert(draftID)
            for row in family.rows where row.kind == .checkpoint {
                let checkpoint = try FieldDraftCanonicalCodecV1.decode(
                    FieldDraftCheckpointV1.self, from: row.canonicalData)
                let facts = try completeDraftFacts(checkpoint)
                try validateDraftReferences(checkpoint, projection: projection)
                draftIDs.formUnion(facts.draftIDs)
                for identity in facts.entityIdentities {
                    switch identity.kind {
                    case .fieldDraftCheckpoint: draftIDs.insert(identity.id)
                    case .workflowRecord: workflowIDs.insert(identity.id)
                    case .evidenceFile: evidenceIDs.insert(identity.id)
                    case .roundSession: sessionIDs.insert(identity.id)
                    case .asset: assetIDs.insert(identity.id)
                    case .site: siteIDs.insert(identity.id)
                    case .packet: packetIDs.insert(identity.id)
                    case .issue: issueIDs.insert(identity.id)
                    case .attachmentStagingItem, .draftCommitSaga, .draftContentReservation,
                         .draftCommitReceipt, .draftDiscardReceipt:
                        break
                    default:
                        throw failure
                    }
                }
            }
        }
        guard draftIDs == processedDraftIDs else { throw failure }

        var changed = true
        while changed {
            changed = false
            for row in records.workflowRecords where workflowIDs.contains(row.id) {
                for id in [row.recordRevisionRootID, row.parentRecordID,
                           row.revisesRecordID, row.evidenceSourceRecordID].compactMap({ $0 }) {
                    changed = workflowIDs.insert(id).inserted || changed
                }
                assetIDs.insert(row.assetID)
                if let id = row.packetID { packetIDs.insert(id) }
                if let id = row.issueID { issueIDs.insert(id) }
            }
        }
        let rounds = records.roundSessions.filter { sessionIDs.contains($0.sessionID) }
            .sorted(by: roundLess)
        guard Set(rounds.map(\.sessionID)) == sessionIDs else { throw failure }
        for round in rounds {
            assetIDs.formUnion(round.items.map { $0.selection.assetID })
            siteIDs.formUnion(round.items.map { $0.selection.siteID })
            workflowIDs.formUnion(round.items.compactMap { $0.completion?.completionID })
        }
        changed = true
        while changed {
            changed = false
            for row in records.workflowRecords where workflowIDs.contains(row.id) {
                for id in [row.recordRevisionRootID, row.parentRecordID,
                           row.revisesRecordID, row.evidenceSourceRecordID].compactMap({ $0 }) {
                    changed = workflowIDs.insert(id).inserted || changed
                }
                assetIDs.insert(row.assetID)
                if let id = row.packetID { packetIDs.insert(id) }
                if let id = row.issueID { issueIDs.insert(id) }
            }
        }
        let reports = try completeReportDependencies(workflowIDs: &workflowIDs, records: records)
        evidenceIDs.formUnion(records.evidenceFiles.filter { workflowIDs.contains($0.recordID) }.map(\.id))
        packetIDs.formUnion(reports.map(\.packetID))
        let workflows = records.workflowRecords.filter { workflowIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(workflows.map(\.id)) == workflowIDs else { throw failure }
        assetIDs.formUnion(workflows.map(\.assetID))
        packetIDs.formUnion(workflows.compactMap(\.packetID))
        issueIDs.formUnion(workflows.compactMap(\.issueID))
        let assets = records.assets.filter { assetIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(assets.map(\.id)) == assetIDs else { throw failure }
        siteIDs.formUnion(assets.map(\.siteID))
        let placementRows = try placementClosure(assetIDs: assetIDs, records: records,
            siteIDs: &siteIDs, enabled: true)
        let sites = records.sites.filter { siteIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(sites.map(\.id)) == siteIDs else { throw failure }
        let evidence = records.evidenceFiles.filter { evidenceIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(evidence.map(\.id)) == evidenceIDs else { throw failure }
        let packets = records.packets.filter { packetIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(packets.map(\.id)) == packetIDs else { throw failure }
        let issues = records.issues.filter { issueIDs.contains($0.id) }
            .sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        guard Set(issues.map(\.id)) == issueIDs else { throw failure }
        let fieldDrafts = try draftIDs.flatMap { id -> [V16BackupFieldDraftRecordV1] in
            guard let family = projection.families[id] else { throw failure }
            return family.rows
        }.sorted(by: fieldDraftLess)
        let assurance = records.requirementAssurance.filter {
            workflowIDs.contains($0.workflowRecordID)
        }.sorted {
            "\($0.workflowRecordID.uuidString.lowercased()):\($0.snapshotSHA256)"
                < "\($1.workflowRecordID.uuidString.lowercased()):\($1.snapshotSHA256)"
        }
        return try makeCanonicalClosure(fieldDrafts: fieldDrafts, workflowRecords: workflows,
            evidenceFiles: evidence, roundSessions: rounds, assets: assets, sites: sites,
            packets: packets, issues: issues, requirementAssurance: assurance, reports: reports,
            assetPlacementEvents: placementRows)
    }

    static func completeDraftFacts(_ checkpoint: FieldDraftCheckpointV1) throws -> DraftFacts {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        if try (checkpoint.codec == CheckRunnerPhotoDraftCodecV1.release()
            || checkpoint.codec == CheckRunnerItemDraftCodecV1.release()
            || checkpoint.codec == RepetitiveCaptureDraftCodecV1.release()
            || checkpoint.codec == RepetitiveCaptureProgressDraftCodecV2.release()) {
            return try draftFacts(.createCheckpoint(checkpoint))
        }
        guard checkpoint.codec == (try MyDayPlanningDraftCodecV1.release()),
              checkpoint.stageIDs.isEmpty else { throw failure }
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
        guard let context = payload.confirmedContext, let intent = payload.editingIntent,
              context.recordedBy.actor.partyID == nil,
              checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)) else {
            throw failure
        }
        if case .preparedCommit = payload.phase { throw failure }
        switch intent {
        case .plan(let draft, let predecessor):
            guard draft.items.isEmpty, draft.eligibleReferences.isEmpty,
                  predecessor == nil else { throw failure }
        case .carryover:
            throw failure
        }
        return try draftFacts(.createCheckpoint(checkpoint))
    }

    static func validateDraftReferences(_ checkpoint: FieldDraftCheckpointV1,
                                        projection: DraftProjection) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        if checkpoint.codec == (try CheckRunnerPhotoDraftCodecV1.release()) {
            _ = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
            return
        }
        if checkpoint.codec == (try CheckRunnerItemDraftCodecV1.release()) {
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
            _ = try referencedCheckpoint(payload.source.sourceCheckpoint, projection: projection)
            _ = try referencedCheckpoint(payload.source.entryProgressCheckpoint,
                projection: projection)
            return
        }
        if checkpoint.codec == (try RepetitiveCaptureDraftCodecV1.release()) {
            switch try RepetitiveCaptureDraftCodecV1.decode(checkpoint.payloadData) {
            case .source:
                _ = try RepetitiveCaptureDraftCodecV1.validateSourceCheckpoint(checkpoint)
            case .continuation(let source, _):
                let sourceCheckpoint = try referencedCheckpoint(source, projection: projection)
                _ = try RepetitiveCaptureDraftCodecV1.validateContinuationCheckpoint(
                    checkpoint, sourceCheckpoint: sourceCheckpoint)
            }
            return
        }
        if checkpoint.codec == (try RepetitiveCaptureProgressDraftCodecV2.release()) {
            try RepetitiveCaptureProgressDraftCodecV2.validateCheckpoint(checkpoint)
            switch try RepetitiveCaptureProgressDraftCodecV2.decode(checkpoint.payloadData) {
            case .source:
                _ = try RepetitiveCaptureProgressDraftCodecV2.source(checkpoint)
            case .progress(let step):
                let source = try referencedCheckpoint(step.source, projection: projection)
                let prior = try step.prior.map {
                    try referencedCheckpoint($0, projection: projection)
                }
                try step.validate(sourceCheckpoint: source, priorCheckpoint: prior)
                guard checkpoint.workspaceID == source.workspaceID,
                      checkpoint.scope == source.scope,
                      checkpoint.resumeAnchor == step.resumeAnchor else { throw failure }
            }
            return
        }
        guard checkpoint.codec == (try MyDayPlanningDraftCodecV1.release()) else { throw failure }
    }

    static func referencedCheckpoint(_ reference: RepetitiveCaptureSourceCheckpointReferenceV1,
                                     projection: DraftProjection) throws
        -> FieldDraftCheckpointV1 {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard let family = projection.families[reference.draftID],
              let row = family.rows.first(where: { $0.kind == .checkpoint }) else { throw failure }
        let checkpoint = try FieldDraftCanonicalCodecV1.decode(
            FieldDraftCheckpointV1.self, from: row.canonicalData)
        try reference.validate(source: checkpoint)
        return checkpoint
    }

    static func makeCanonicalClosure(
        fieldDrafts: [V16BackupFieldDraftRecordV1],
        workflowRecords: [V4BackupWorkflowRecordDTO], evidenceFiles: [V4BackupEvidenceFileDTO],
        roundSessions: [RoundSessionV1], assets: [V4BackupAssetDTO], sites: [V4BackupSiteDTO],
        packets: [V4BackupPacketDTO], issues: [V4BackupIssueDTO],
        requirementAssurance: [V8BackupRequirementAssuranceRecordV1],
        reports: [V4BackupReportDTO] = [],
        assetPlacementEvents: [V5BackupLocationRecordV1] = [], bindingVersion: Int = 2
    ) throws -> CanonicalClosure {
        let bytes: Data
        switch bindingVersion {
        case 1:
            guard reports.isEmpty, assetPlacementEvents.isEmpty else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let legacy = LegacyCanonicalClosureBasisV1(fieldDrafts: fieldDrafts,
                workflowRecords: workflowRecords, evidenceFiles: evidenceFiles, roundSessions: roundSessions,
                assets: assets, sites: sites, packets: packets, issues: issues,
                requirementAssurance: requirementAssurance)
            bytes = try FieldDraftCanonicalCodecV1.encode(legacy)
        case 2:
            let current = CanonicalClosureBasisV2(assetPlacementEvents: assetPlacementEvents, reports: reports, fieldDrafts: fieldDrafts,
                workflowRecords: workflowRecords, evidenceFiles: evidenceFiles, roundSessions: roundSessions,
                assets: assets, sites: sites, packets: packets, issues: issues,
                requirementAssurance: requirementAssurance)
            bytes = try FieldDraftCanonicalCodecV1.encode(current)
        default:
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return .init(assetPlacementEvents: assetPlacementEvents, reports: reports, fieldDrafts: fieldDrafts, workflowRecords: workflowRecords,
            evidenceFiles: evidenceFiles, roundSessions: roundSessions, assets: assets, sites: sites,
            packets: packets, issues: issues, requirementAssurance: requirementAssurance,
            sha256: CanonicalJSONV1.sha256(bytes))
    }

    /// Keep the complete predecessor chain for each selected asset, including
    /// earlier sites. The canonical event bytes remain the existing codec's bytes.
    static func placementClosure(assetIDs: Set<UUID>, records: V4BackupRecordsV1,
        siteIDs: inout Set<UUID>, enabled: Bool) throws -> [V5BackupLocationRecordV1] {
        guard enabled, !assetIDs.isEmpty else { return [] }
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var selected: [V5BackupLocationRecordV1] = []
        var events: [AssetPlacementEventV1] = []
        for row in records.assetPlacementEvents {
            let event = try LocationPersistenceCodecV1.decode(AssetPlacementEventV1.self,
                from: row.canonicalData)
            guard event.id == row.id, row.secondaryCanonicalData == nil else { throw failure }
            if assetIDs.contains(event.assetID) {
                selected.append(row); events.append(event); siteIDs.insert(event.siteID)
            }
        }
        for history in Dictionary(grouping: events, by: \.assetID).values {
            try AssetPlacementHistoryV1.validate(history)
        }
        return selected.sorted { uuidLess($0.id, $1.id) }
    }

    /// This composition does not reconstruct other location/pose codecs. Require
    /// the incumbent replacement path to retain their exact original rows. Until
    /// full codec adoption, conservative denial prevents a partial graph restore.
    static func requireUncopiedPlacementDependencies(from original: V4BackupRecordsV1,
        in destination: V4BackupRecordsV1) throws {
        let groups = [
            (original.assetCompositionEdges, destination.assetCompositionEdges),
            (original.assetCompositionEvents, destination.assetCompositionEvents),
            (original.locationHierarchyEvents, destination.locationHierarchyEvents),
            (original.locationMigrationReceipts, destination.locationMigrationReceipts),
            (original.locationNodes, destination.locationNodes)
        ]
        for (before, after) in groups {
            guard try isSubset(before, of: after, key: { $0.id.uuidString.lowercased() }) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        guard try isSubset(original.placementPoses, of: destination.placementPoses,
            key: { "\($0.kind.rawValue):\($0.id.uuidString.lowercased())" }) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
    }

    /// Reports are immutable originals. Include every report for a selected
    /// workflow and every predecessor, closing their workflow references before
    /// selecting canonical assets, packets and evidence. Missing links deny.
    static func completeReportDependencies(workflowIDs: inout Set<UUID>,
        records: V4BackupRecordsV1) throws -> [V4BackupReportDTO] {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let workflows = try checkRunnerPhotoRestoreDictionary(records.workflowRecords) { ($0.id, $0) }
        let reports = try checkRunnerPhotoRestoreDictionary(records.reports) { ($0.id, $0) }
        var reportIDs = Set<UUID>()
        var changed = true
        while changed {
            changed = false
            for id in workflowIDs {
                guard let row = workflows[id] else { throw failure }
                for linked in [row.recordRevisionRootID, row.parentRecordID,
                               row.revisesRecordID, row.evidenceSourceRecordID].compactMap({ $0 }) {
                    changed = workflowIDs.insert(linked).inserted || changed
                }
            }
            for row in records.reports where workflowIDs.contains(row.sourceRecordID) {
                changed = reportIDs.insert(row.id).inserted || changed
            }
            for id in reportIDs {
                guard let row = reports[id] else { throw failure }
                changed = workflowIDs.insert(row.sourceRecordID).inserted || changed
                if let predecessor = row.replacesReportID {
                    changed = reportIDs.insert(predecessor).inserted || changed
                }
            }
        }
        return try reportIDs.sorted(by: uuidLess).map {
            guard let report = reports[$0] else { throw failure }
            return report
        }
    }

    static func merged(_ lhs: CanonicalClosure, _ rhs: CanonicalClosure) throws
        -> CanonicalClosure {
        try makeCanonicalClosure(
            fieldDrafts: merged(base: lhs.fieldDrafts, additions: rhs.fieldDrafts,
                key: fieldDraftKey, less: fieldDraftLess),
            workflowRecords: merged(base: lhs.workflowRecords, additions: rhs.workflowRecords,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            evidenceFiles: merged(base: lhs.evidenceFiles, additions: rhs.evidenceFiles,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            roundSessions: merged(base: lhs.roundSessions, additions: rhs.roundSessions,
                key: { "\($0.sessionID.uuidString.lowercased()):\($0.revision)" }, less: roundLess),
            assets: merged(base: lhs.assets, additions: rhs.assets,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            sites: merged(base: lhs.sites, additions: rhs.sites,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            packets: merged(base: lhs.packets, additions: rhs.packets,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            issues: merged(base: lhs.issues, additions: rhs.issues,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            requirementAssurance: merged(base: lhs.requirementAssurance,
                additions: rhs.requirementAssurance,
                key: { "\($0.workflowRecordID.uuidString.lowercased()):\($0.snapshotSHA256)" },
                less: {
                    "\($0.workflowRecordID.uuidString.lowercased()):\($0.snapshotSHA256)"
                        < "\($1.workflowRecordID.uuidString.lowercased()):\($1.snapshotSHA256)"
                }),
            reports: merged(base: lhs.reports, additions: rhs.reports,
                key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }),
            assetPlacementEvents: merged(base: lhs.assetPlacementEvents,
                additions: rhs.assetPlacementEvents, key: { $0.id.uuidString.lowercased() },
                less: { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }))
    }

    static func requireNoCurrentTouch(source: MutationHistorySnapshotV1,
                                      current: MutationHistorySnapshotV1,
                                      sourceFootprint: HistoryFootprint) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var sourceRecords: [String: MutationHistoryReceiptRecordV1] = [:]
        for row in source.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            sourceRecords[historyKey(envelope)] = row
        }
        for row in current.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            let key = historyKey(envelope)
            if let exact = sourceRecords[key] {
                guard exact == row else { throw failure }
                continue
            }
            let receipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
            var footprint = HistoryFootprint()
            try footprint.include(envelope, receipt)
            guard !sourceFootprint.intersects(footprint) else { throw failure }
        }
        let sourceQuarantines = try checkRunnerPhotoRestoreDictionary(source.quarantines) {
            (MutationWorkspaceKeyV1.value(workspaceID: $0.workspaceID,
                mutationID: try MutationIDV1(rawValue: $0.mutationID)), $0)
        }
        let currentReceipts = try checkRunnerPhotoRestoreDictionary(current.receipts) { row in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            return (historyKey(envelope), row)
        }
        for row in current.quarantines {
            let key = MutationWorkspaceKeyV1.value(workspaceID: row.workspaceID,
                mutationID: try MutationIDV1(rawValue: row.mutationID))
            if let exact = sourceQuarantines[key] {
                guard exact == row else { throw failure }
                continue
            }
            guard let original = currentReceipts[key] else { throw failure }
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
            var footprint = HistoryFootprint()
            try footprint.include(envelope, receipt)
            guard !sourceFootprint.intersects(footprint) else { throw failure }
        }
        let sourceRevisions = try checkRunnerPhotoRestoreDictionary(source.entityRevisions) {
            ($0.identity, $0)
        }
        for row in current.entityRevisions {
            if sourceFootprint.entityIdentities.contains(row.identity) {
                guard sourceRevisions[row.identity] == row else { throw failure }
            }
        }
    }

    static func draftFacts(_ payload: FieldDraftMutationPayloadV1) throws -> DraftFacts {
        var facts = DraftFacts()
        func checkpoint(_ value: FieldDraftCheckpointV1) throws {
            facts.draftIDs.insert(value.draftID); facts.stageIDs.formUnion(value.stageIDs)
            facts.entityIdentities.insert(try .init(kind: .fieldDraftCheckpoint,
                                                    id: value.draftID))
            facts.scopeSHA256s.insert(CanonicalJSONV1.sha256(
                try FieldDraftCanonicalCodecV1.encode(value.scope)))
            facts.resumeAnchorSHA256s.insert(CanonicalJSONV1.sha256(
                try FieldDraftCanonicalCodecV1.encode(value.resumeAnchor)))
            if value.codec == (try CheckRunnerPhotoDraftCodecV1.release()) {
                let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(value)
                facts.entityIdentities.insert(try .init(kind: .fieldDraftCheckpoint,
                                                        id: payload.parentDraftID))
                facts.entityIdentities.insert(try .init(kind: .workflowRecord,
                                                        id: payload.recordID))
                facts.entityIdentities.insert(try .init(kind: .asset, id: payload.assetID))
                facts.entityIdentities.insert(try .init(kind: .site,
                    id: payload.sourceBinding.itemAtEntry.selection.siteID))
                facts.entityIdentities.insert(try .init(kind: .roundSession,
                    id: payload.sourceBinding.roundAtEntry.sessionID))
            } else if value.codec == (try CheckRunnerItemDraftCodecV1.release()) {
                let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(value)
                let source = payload.source
                facts.entityIdentities.insert(try .init(kind: .asset, id: source.assetID))
                facts.entityIdentities.insert(try .init(kind: .site,
                    id: source.itemAtEntry.selection.siteID))
                facts.entityIdentities.insert(try .init(kind: .roundSession,
                    id: source.roundAtEntry.sessionID))
                facts.entityIdentities.insert(try .init(kind: .fieldDraftCheckpoint,
                    id: source.sourceCheckpoint.draftID))
                facts.entityIdentities.insert(try .init(kind: .fieldDraftCheckpoint,
                    id: source.entryProgressCheckpoint.draftID))
                if let attempt = payload.field.begin.attempt {
                    facts.entityIdentities.insert(try .init(kind: .workflowRecord,
                        id: attempt.recordCommand.recordID))
                }
            } else if value.codec == (try RepetitiveCaptureDraftCodecV1.release()) {
                func selection(_ selection: BatchScanSelectionV1) throws {
                    for preview in selection.previews {
                        if let asset = preview.asset {
                            facts.entityIdentities.insert(try .init(kind: .asset, id: asset.assetID))
                            facts.entityIdentities.insert(try .init(kind: .site, id: asset.siteID))
                            facts.entityIdentities.insert(try .init(kind: .roundSession,
                                id: asset.readiness.session.sessionID))
                        }
                    }
                }
                switch try RepetitiveCaptureDraftCodecV1.decode(value.payloadData) {
                case let .source(_, round, selected):
                    facts.entityIdentities.insert(try .init(kind: .roundSession, id: round.sessionID))
                    try selection(selected)
                case let .continuation(source, request):
                    facts.entityIdentities.insert(try .init(kind: .fieldDraftCheckpoint, id: source.draftID))
                    facts.entityIdentities.insert(try .init(kind: .asset, id: request.assetID))
                    if let round = request.plan.round {
                        facts.entityIdentities.insert(try .init(kind: .roundSession, id: round.sessionID))
                    }
                    try selection(request.plan.selection)
                }
            } else if value.codec == (try RepetitiveCaptureProgressDraftCodecV2.release()) {
                let payload = try FieldDraftCanonicalCodecV1.decode(
                    RepetitiveCaptureProgressDraftPayloadV2.self, from: value.payloadData)
                try payload.validate()
                let round: RoundSessionV1
                switch payload {
                case .source(let source): round = source.round
                case .progress(let step):
                    round = step.expectedRound
                    facts.entityIdentities.insert(try .init(kind: .fieldDraftCheckpoint, id: step.source.draftID))
                    if let prior = step.prior {
                        facts.entityIdentities.insert(try .init(kind: .fieldDraftCheckpoint, id: prior.draftID))
                    }
                }
                facts.entityIdentities.insert(try .init(kind: .roundSession, id: round.sessionID))
                for item in round.items {
                    facts.entityIdentities.insert(try .init(kind: .asset, id: item.selection.assetID))
                    facts.entityIdentities.insert(try .init(kind: .site, id: item.selection.siteID))
                    if let completion = item.completion {
                        facts.entityIdentities.insert(try .init(kind: .workflowRecord, id: completion.completionID))
                    }
                }
            }
        }
        switch payload {
        case let .createCheckpoint(value), let .reviseCheckpoint(value): try checkpoint(value)
        case let .appendStagingItem(value), let .reviseStagingItem(value):
            facts.draftIDs.insert(value.draftID); facts.stageIDs.insert(value.stageID)
        case let .appendCommitSaga(value), let .advanceCommitSaga(value):
            facts.draftIDs.insert(value.draftID)
        case let .appendContentReservation(value), let .reviseContentReservation(value):
            facts.draftIDs.insert(value.draftID); facts.stageIDs.insert(value.stageID)
        case let .applyCommitTerminal(value, _):
            try checkpoint(value.committedCheckpoint); facts.draftIDs.insert(value.retiredSaga.draftID)
            facts.draftIDs.insert(value.receipt.draftID)
            facts.stageIDs.formUnion(value.receipt.consumedStageToContentID.keys.compactMap {
                UUID(uuidString: $0)
            })
        case let .applyDiscardTerminal(value):
            try checkpoint(value.discardedCheckpoint); facts.draftIDs.insert(value.receipt.draftID)
        case let .resolveConflict(value):
            try checkpoint(value.expectedCheckpoint); try checkpoint(value.successorCheckpoint)
        case let .publishReadyStage(value):
            try checkpoint(value.expectedCheckpoint); try checkpoint(value.successorCheckpoint)
            facts.draftIDs.insert(value.readyItem.draftID); facts.stageIDs.insert(value.readyItem.stageID)
        }
        return facts
    }

    static func draftID(_ payload: FieldDraftMutationPayloadV1) throws -> UUID {
        let values = try draftFacts(payload).draftIDs
        guard values.count == 1, let value = values.first else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return value
    }

    static func canonicalRows(_ payload: FieldDraftMutationPayloadV1) throws
        -> [V16BackupFieldDraftRecordV1] {
        func row<T: Encodable>(_ kind: V16BackupFieldDraftRecordV1.Kind, _ id: UUID,
                               _ workspaceID: WorkspaceID, _ revision: UInt64,
                               _ value: T) throws -> V16BackupFieldDraftRecordV1 {
            .init(kind: kind, id: id, workspaceID: workspaceID.rawValue,
                  revision: revision, canonicalData: try FieldDraftCanonicalCodecV1.encode(value))
        }
        switch payload {
        case let .createCheckpoint(value), let .reviseCheckpoint(value):
            return [try row(.checkpoint, value.draftID, value.workspaceID, value.draftRevision, value)]
        case let .appendStagingItem(value), let .reviseStagingItem(value):
            return [try row(.stagingItem, value.stageID, value.workspaceID, value.revision, value)]
        case let .appendCommitSaga(value), let .advanceCommitSaga(value):
            return [try row(.commitSaga, value.sagaID, value.workspaceID, value.revision, value)]
        case let .appendContentReservation(value), let .reviseContentReservation(value):
            return [try row(.contentReservation, value.reservationID, value.workspaceID,
                            value.revision, value)]
        case let .applyCommitTerminal(value, _):
            return [
                try row(.commitSaga, value.retiredSaga.sagaID, value.workspaceID,
                        value.retiredSaga.revision, value.retiredSaga),
                try row(.checkpoint, value.committedCheckpoint.draftID, value.workspaceID,
                        value.committedCheckpoint.draftRevision, value.committedCheckpoint),
                try row(.commitReceipt, value.receipt.receiptID, value.workspaceID,
                        value.receipt.revision, value.receipt),
            ]
        case let .applyDiscardTerminal(value):
            return [
                try row(.checkpoint, value.discardedCheckpoint.draftID, value.workspaceID,
                        value.discardedCheckpoint.draftRevision, value.discardedCheckpoint),
                try row(.discardReceipt, value.receipt.receiptID, value.workspaceID,
                        value.receipt.revision, value.receipt),
            ]
        case let .resolveConflict(value):
            return [try row(.checkpoint, value.successorCheckpoint.draftID,
                            value.successorCheckpoint.workspaceID,
                            value.successorCheckpoint.draftRevision, value.successorCheckpoint)]
        case let .publishReadyStage(value):
            return [
                try row(.stagingItem, value.readyItem.stageID, value.workspaceID,
                        value.readyItem.revision, value.readyItem),
                try row(.checkpoint, value.successorCheckpoint.draftID, value.workspaceID,
                        value.successorCheckpoint.draftRevision, value.successorCheckpoint),
            ]
        }
    }

    static func decodedRow(_ row: V16BackupFieldDraftRecordV1) throws -> DecodedDraftRow {
        switch row.kind {
        case .checkpoint:
            let value = try FieldDraftCanonicalCodecV1.decode(
                FieldDraftCheckpointV1.self, from: row.canonicalData)
            return .init(workspaceID: value.workspaceID, draftID: value.draftID,
                id: value.draftID, revision: value.draftRevision, checkpoint: value)
        case .stagingItem:
            let value = try FieldDraftCanonicalCodecV1.decode(
                AttachmentStagingItemV1.self, from: row.canonicalData)
            return .init(workspaceID: value.workspaceID, draftID: value.draftID,
                id: value.stageID, revision: value.revision, checkpoint: nil)
        case .commitSaga:
            let value = try FieldDraftCanonicalCodecV1.decode(
                DraftCommitSagaV1.self, from: row.canonicalData)
            return .init(workspaceID: value.workspaceID, draftID: value.draftID,
                id: value.sagaID, revision: value.revision, checkpoint: nil)
        case .contentReservation:
            let value = try FieldDraftCanonicalCodecV1.decode(
                DraftContentReservationV1.self, from: row.canonicalData)
            return .init(workspaceID: value.workspaceID, draftID: value.draftID,
                id: value.reservationID, revision: value.revision, checkpoint: nil)
        case .commitReceipt:
            let value = try FieldDraftCanonicalCodecV1.decode(
                DraftCommitReceiptV1.self, from: row.canonicalData)
            return .init(workspaceID: value.workspaceID, draftID: value.draftID,
                id: value.receiptID, revision: value.revision, checkpoint: nil)
        case .discardReceipt:
            let value = try FieldDraftCanonicalCodecV1.decode(
                DraftDiscardReceiptV1.self, from: row.canonicalData)
            return .init(workspaceID: value.workspaceID, draftID: value.draftID,
                id: value.receiptID, revision: value.revision, checkpoint: nil)
        }
    }

    static func latestRows(_ rows: [V16BackupFieldDraftRecordV1]) throws
        -> [V16BackupFieldDraftRecordV1] {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var result: [String: V16BackupFieldDraftRecordV1] = [:]
        for row in rows {
            let key = fieldDraftKey(row)
            if let old = result[key] {
                guard old.revision != row.revision || old == row else { throw failure }
                if old.revision > row.revision { continue }
            }
            result[key] = row
        }
        return result.values.sorted(by: fieldDraftLess)
    }

    static func merged<T: Equatable>(base: [T], additions: [T],
                                     key: (T) -> String,
                                     less: (T, T) -> Bool) throws -> [T] {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var values: [String: T] = [:]
        for value in base + additions {
            let id = key(value)
            guard values[id].map({ $0 == value }) ?? true else { throw failure }
            values[id] = value
        }
        return values.values.sorted(by: less)
    }

    static func isSubset<T: Equatable>(_ subset: [T], of values: [T],
                                       key: (T) -> String) throws -> Bool {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var byKey: [String: T] = [:]
        for value in values {
            guard byKey.updateValue(value, forKey: key(value)) == nil else { throw failure }
        }
        return subset.allSatisfy { byKey[key($0)] == $0 }
    }

    static func fieldDraftKey(_ row: V16BackupFieldDraftRecordV1) -> String {
        "\(row.kind.rawValue):\(row.id.uuidString.lowercased())"
    }

    static func fieldDraftLess(_ lhs: V16BackupFieldDraftRecordV1,
                               _ rhs: V16BackupFieldDraftRecordV1) -> Bool {
        fieldDraftKey(lhs) < fieldDraftKey(rhs)
    }

    static func roundLess(_ lhs: RoundSessionV1, _ rhs: RoundSessionV1) -> Bool {
        (lhs.sessionID.uuidString.lowercased(), lhs.revision)
            < (rhs.sessionID.uuidString.lowercased(), rhs.revision)
    }

    static func historyKey(_ envelope: MutationEnvelopeV1) -> String {
        MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                                     mutationID: envelope.mutationID)
    }

    static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }
}

private func checkRunnerPhotoRestoreDictionary<S: Sequence, Key: Hashable, Value>(
    _ values: S,
    transform: (S.Element) throws -> (Key, Value)
) throws -> [Key: Value] {
    var result: [Key: Value] = [:]
    for value in values {
        let (key, mapped) = try transform(value)
        guard result.updateValue(mapped, forKey: key) == nil else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
    }
    return result
}

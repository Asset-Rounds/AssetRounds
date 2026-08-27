import Foundation
import SwiftData

/// Applies content changes without saving. MutationJournalStoreV1 owns the
/// single atomic save containing content, revisions, and immutable receipt.
@MainActor
final class WorkspaceWriterAdapterV1: WorkspaceWriterAdapterPortV1 {
    let requiresInitialPlacementForFirstSign = true
    static let supportedCommandKinds: Set<WorkspaceCommandKindV1> = [
        .createFirstSign,
        .createCheckDraft,
        .acceptCheckEvidence,
        .updateSiteTimeZone,
    ]
    static let locationSupportedCommandKinds: Set<WorkspaceCommandKindV1> = [
        .applyLocationHierarchyChange,
        .applyAssetPlacementChange,
        .applyAssetCompositionChange,
    ]
    static let activeSupportedCommandKinds = supportedCommandKinds.union(locationSupportedCommandKinds)
        .union([.applySavedSmartView])

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard !modelContext.hasChanges else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        do {
            _ = try ObservationAndTimeRowStoreV1.validatedIndex(in: modelContext)
        } catch {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        switch command {
        case let .createFirstSign(value):
            return try createFirstSign(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .createCheckDraft(value):
            return try createCheckDraft(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .acceptCheckEvidence(value):
            return try acceptCheckEvidence(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .updateSiteTimeZone(value):
            return try updateSiteTimeZone(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyLocationHierarchyChange(value):
            let hierarchy = try applyLocationHierarchyChange(
                value.plan,
                placementChanges: value.placementChanges,
                temporaryRelativePath: temporaryRelativePath
            )
            var affected = hierarchy.affectedEntities
            for placement in value.placementChanges {
                affected += try applyAssetPlacementChange(
                    placement,
                    occurredAt: occurredAt,
                    temporaryRelativePath: temporaryRelativePath
                ).affectedEntities
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: affected,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyAssetPlacementChange(plan):
            return try applyAssetPlacementChange(plan, occurredAt: occurredAt, temporaryRelativePath: temporaryRelativePath)
        case let .applyAssetCompositionChange(plan):
            return try applyAssetCompositionChange(plan, temporaryRelativePath: temporaryRelativePath)
        case let .applySavedSmartView(value):
            return try applySavedSmartView(value, temporaryRelativePath: temporaryRelativePath)
        case .deleteAsset,
             .deleteSite,
             .eraseWorkspace,
             .finalizeCheck,
             .finalizeCorrection,
             .recordWork,
             .restoreWorkspace,
             .archiveEntities:
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
    }

    func queryExisting(
        identities: [WorkspaceEntityIdentityV1]
    ) throws -> (
        identities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    ) {
        guard !modelContext.hasChanges,
              identities.count <= 256,
              Set(identities).count == identities.count else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        var existing: [WorkspaceEntityIdentityV1] = []
        var bindings: [WorkspacePackageBindingV1] = []
        let deletionLedgerRows: [DeletionLedgerRow]
        let deletionLedgerIdentities: [DeletionIdentityV2]
        if identities.contains(where: { $0.kind == .deletionLedgerEntry }) {
            deletionLedgerRows = try modelContext.fetch(FetchDescriptor<DeletionLedgerRow>())
            guard Set(deletionLedgerRows.map(\.typedID)).count == deletionLedgerRows.count else {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            do {
                deletionLedgerIdentities = try deletionLedgerRows.map {
                    try DeletionIdentityV2(typedID: $0.typedID)
                }
            } catch {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
        } else {
            deletionLedgerRows = []
            deletionLedgerIdentities = []
        }
        for identity in identities {
            let id = identity.id
            let exists: Bool
            switch identity.kind {
            case .site:
                let values = try modelContext.fetch(FetchDescriptor<Site>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .asset:
                let assets = try modelContext.fetch(FetchDescriptor<Asset>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard assets.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = assets.count == 1
                if let asset = assets.first {
                    bindings.append(WorkspacePackageBindingV1(
                        assetID: asset.id,
                        packageID: asset.packID,
                        packageSchemaVersion: asset.packSchemaVersion,
                        packageContentVersion: asset.packContentVersion
                    ))
                }
            case .locationNode:
                let values = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetPlacementEvent:
                let values = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetCompositionEdge:
                let values = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetCompositionEvent:
                let values = try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .savedSmartView:
                let values = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .workflowRecord:
                let values = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .evidenceFile:
                let values = try modelContext.fetch(FetchDescriptor<EvidenceFile>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .issue:
                let values = try modelContext.fetch(FetchDescriptor<Issue>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .packet:
                let values = try modelContext.fetch(FetchDescriptor<Packet>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .report:
                let values = try modelContext.fetch(FetchDescriptor<Report>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .deletionLedgerEntry:
                let matches = deletionLedgerIdentities.filter { $0.id == identity.id }
                guard matches.count <= 1 else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = matches.count == 1
            }
            if exists { existing.append(identity) }
        }
        return (
            existing.sorted { $0.stableKey < $1.stableKey },
            bindings.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
        )
    }

    func createFirstSign(
        _ value: FirstSignMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard value.assetLabel == value.assetLabel.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.assetLabel.isEmpty,
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              Self.isFinite(value.createdAt),
              value.newSite == nil || value.newSite?.id == value.siteID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementFields = [
            value.initialPlacementMutationID != nil,
            value.initialPlacementEventID != nil,
            value.initialPhysicalEpisodeID != nil,
        ]
        guard placementFields.allSatisfy({ $0 }) || placementFields.allSatisfy({ !$0 }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        let siteID = value.siteID
        let existingSites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        if value.newSite == nil {
            guard existingSites.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        } else {
            guard existingSites.isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        }

        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite {
            guard site.label == site.label.trimmingCharacters(in: .whitespacesAndNewlines),
                  !site.label.isEmpty else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
        }
        if let placementEventID = value.initialPlacementEventID {
            guard try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
                predicate: #Predicate { $0.id == placementEventID }
            )).isEmpty else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            identities.append(try WorkspaceEntityIdentityV1(
                kind: .assetPlacementEvent,
                id: placementEventID
            ))
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )

        if let site = value.newSite {
            modelContext.insert(Site(
                id: site.id,
                label: site.label,
                address: site.address,
                timeZoneID: site.timeZoneID,
                createdAt: value.createdAt
            ))
        }
        modelContext.insert(Asset(
            id: value.assetID,
            siteID: value.siteID,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            label: value.assetLabel,
            createdAt: value.createdAt
        ))
        if let mutationID = value.initialPlacementMutationID,
           let eventID = value.initialPlacementEventID,
           let episodeID = value.initialPhysicalEpisodeID {
            let siteDisplay = value.newSite?.label ?? existingSites[0].label
            let event = try AssetPlacementEventV1(
                id: eventID,
                workspaceID: try currentWorkspaceID(),
                assetID: value.assetID,
                siteID: value.siteID,
                locationNodeID: nil,
                predecessorEventID: nil,
                source: .manual,
                physicalEpisodeID: episodeID,
                continuity: .samePhysicalInstallation,
                pathSnapshot: try LocationPathSnapshotV1(
                    siteID: value.siteID,
                    siteDisplay: siteDisplay,
                    nodes: []
                ),
                mutationID: mutationID,
                occurredAt: occurredAt
            )
            try AssetPlacementHistoryV1.validate([event])
            modelContext.insert(try AssetPlacementEventRow(event))
        }
        return effect
    }

    private func currentWorkspaceID() throws -> WorkspaceID {
        let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count == 1, let state = states.first else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        return WorkspaceID(rawValue: state.workspaceID)
    }

    func createCheckDraft(
        _ value: CheckDraftMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard let stage = WorkflowStage(rawValue: value.stage),
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              !value.pdfTemplateID.isEmpty,
              value.pdfTemplateVersion > 0,
              Self.isFinite(value.startedAt),
              value.observedAtUTC.map({ Self.isFinite($0) }) ?? true else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard (value.observationBasis == nil) == (value.temporalContext == nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let observationBasisData: Data
        let temporalContextData: Data
        do {
            if let observationBasis = value.observationBasis,
               let temporalContext = value.temporalContext {
                try Self.requireLegacyTimeProjectionMatches(
                    temporalContext,
                    command: value
                )
                observationBasisData = try ObservationAndTimeCodecV1.encode(
                    observationBasis
                )
                temporalContextData = try ObservationAndTimeCodecV1.encode(
                    temporalContext
                )
            } else {
                let migratedBasis = try ObservationAndTimeLegacyMigrationV1.observationBasis(
                    couldNotVerifyKey: nil,
                    displaySnapshot: nil,
                    registryVersion: nil
                )
                let migratedTemporal = try ObservationAndTimeLegacyMigrationV1.temporalContext(
                    observedAtUTC: value.observedAtUTC,
                    recordedAtUTC: value.startedAt,
                    timeZoneID: value.timeZoneID,
                    utcOffsetMinutes: value.utcOffsetMinutes,
                    localDate: value.localDate,
                    localTime: value.localTime
                )
                guard let migratedBasis, let migratedTemporal else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                observationBasisData = try ObservationAndTimeCodecV1.encode(migratedBasis)
                temporalContextData = try ObservationAndTimeCodecV1.encode(migratedTemporal)
            }
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftStep: WorkflowDraftStep?
        if let key = value.draftStepKey {
            guard let parsed = WorkflowDraftStep(rawValue: key) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            draftStep = parsed
        } else {
            draftStep = nil
        }
        guard (stage == .work && draftStep == nil)
                || (stage != .work && draftStep != nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let recordID = value.recordID
        guard try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).count == 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID)
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [identity],
            temporaryRelativePath: temporaryRelativePath
        )
        modelContext.insert(WorkflowRecord(
            id: value.recordID,
            assetID: value.assetID,
            packetID: nil,
            issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordID,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: stage,
            state: .draft,
            draftStepKey: draftStep,
            startedAt: value.startedAt,
            completedAt: nil,
            observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: nil,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: nil,
            finalizationMutationID: nil
        ))
        modelContext.insert(try ObservationAndTimeRow(
            recordID: value.recordID,
            observationBasisV1Data: observationBasisData,
            temporalContextV1Data: temporalContextData
        ))
        return effect
    }

    private static func requireLegacyTimeProjectionMatches(
        _ temporal: TemporalContextV1,
        command: CheckDraftMutationV1
    ) throws {
        try temporal.validate()
        guard temporal.occurredAtUTC == command.observedAtUTC,
              temporal.localDate == command.localDate,
              temporal.localTime == command.localTime,
              temporal.ianaTimeZoneIdentifier == command.timeZoneID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let expectedOffsetSeconds: Int?
        if let minutes = command.utcOffsetMinutes {
            let (seconds, overflow) = minutes.multipliedReportingOverflow(
                by: 60
            )
            guard !overflow else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            expectedOffsetSeconds = seconds
        } else {
            expectedOffsetSeconds = nil
        }
        guard temporal.utcOffsetSeconds == expectedOffsetSeconds else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func acceptCheckEvidence(
        _ value: CheckEvidenceMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard WorkflowDraftStep(rawValue: value.nextDraftStepKey) != nil,
              value.byteCount >= 0,
              value.thumbnailByteCount >= 0,
              Self.isSHA256(value.sha256),
              Self.isSHA256(value.thumbnailSHA256),
              Self.isSafeRelativePath(value.relativePath),
              Self.isSafeRelativePath(value.thumbnailRelativePath),
              !value.mimeType.isEmpty,
              !value.purposeKey.isEmpty,
              Self.isFinite(value.createdAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftID = value.draftID
        let drafts = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == draftID }
        ))
        guard drafts.count == 1,
              let draft = drafts.first,
              draft.state == WorkflowState.draft.rawValue else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let evidenceID = value.evidenceID
        guard try modelContext.fetch(FetchDescriptor<EvidenceFile>(
            predicate: #Predicate { $0.id == evidenceID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identities = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.draftID),
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: value.evidenceID),
        ]
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )
        draft.draftStepKey = value.nextDraftStepKey
        modelContext.insert(EvidenceFile(
            id: value.evidenceID,
            recordID: value.draftID,
            purposeKey: value.purposeKey,
            relativePath: value.relativePath,
            mimeType: value.mimeType,
            byteCount: value.byteCount,
            sha256: value.sha256,
            createdAt: value.createdAt,
            thumbnailRelativePath: value.thumbnailRelativePath,
            thumbnailByteCount: value.thumbnailByteCount,
            thumbnailSHA256: value.thumbnailSHA256
        ))
        return effect
    }

    func updateSiteTimeZone(
        _ value: SiteTimeZoneMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard TimeZone(identifier: value.timeZoneID) != nil,
              Self.isFinite(value.confirmedAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let siteID = value.siteID
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count == 1, let site = sites.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [try WorkspaceEntityIdentityV1(kind: .site, id: siteID)],
            temporaryRelativePath: temporaryRelativePath
        )
        site.timeZoneID = value.timeZoneID
        site.updatedAt = value.confirmedAt
        return effect
    }

    func rollback() {
        modelContext.rollback()
    }

    private func applyLocationHierarchyChange(
        _ plan: LocationHierarchyChangePlanV1,
        placementChanges: [AssetPlacementChangePlanV1],
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try plan.validate()
        let workspaceID = plan.workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(
            predicate: #Predicate { $0.workspaceID == workspaceID }
        ))
        let current = try rows.map { try $0.value() }
        let affectedIDs = Set(plan.beforeNodes.map(\.id)).union(plan.afterNodes.map(\.id))
        let currentAffected = current.filter { affectedIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard currentAffected == plan.beforeNodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementEvents = try modelContext.fetch(
            FetchDescriptor<AssetPlacementEventRow>(predicate: #Predicate { $0.workspaceID == workspaceID })
        ).map { try $0.value() }
        let immutablePlacementReferencedNodeIDs = placementEvents.compactMap(\.locationNodeID)
            .sorted { $0.uuidString < $1.uuidString }
        guard Array(Set(immutablePlacementReferencedNodeIDs)).sorted(by: { $0.uuidString < $1.uuidString })
                == plan.immutablePlacementReferencedNodeIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let unaffected = current.filter { !affectedIDs.contains($0.id) }
        let resultingNodes = unaffected + plan.afterNodes
        try LocationHierarchyPolicyV1.validate(resultingNodes)
        let sites = try modelContext.fetch(FetchDescriptor<Site>())
        let siteDisplayByID = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0.label) })
        let liveAssetIDs = Set(try modelContext.fetch(FetchDescriptor<Asset>()).map(\.id))
        let placementPredecessorIDs = Set(placementEvents.compactMap(\.predecessorEventID))
        let liveTips = placementEvents.filter {
            liveAssetIDs.contains($0.assetID) && !placementPredecessorIDs.contains($0.id)
        }
        guard Set(liveTips.map(\.assetID)).count == liveTips.count,
              Set(liveTips.map(\.assetID)) == liveAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementChangesByAssetID = Dictionary(
            uniqueKeysWithValues: placementChanges.map { ($0.basis.assetID, $0) }
        )
        var expectedPathChanges: [AssetLocationPathChangeV1] = []
        for tip in liveTips {
            guard let beforeSiteDisplay = siteDisplayByID[tip.siteID] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let beforePath = try makeLocationPath(
                siteID: tip.siteID,
                siteDisplay: beforeSiteDisplay,
                nodeID: tip.locationNodeID,
                nodes: current
            )
            let change = placementChangesByAssetID[tip.assetID]
            let afterSiteID = change?.basis.proposedSiteID ?? tip.siteID
            let afterNodeID = change?.basis.proposedLocationNodeID ?? tip.locationNodeID
            guard let afterSiteDisplay = siteDisplayByID[afterSiteID] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let afterPath = try makeLocationPath(
                siteID: afterSiteID,
                siteDisplay: afterSiteDisplay,
                nodeID: afterNodeID,
                nodes: resultingNodes
            )
            if beforePath != afterPath {
                expectedPathChanges.append(try AssetLocationPathChangeV1(
                    assetID: tip.assetID,
                    beforePath: beforePath,
                    afterPath: afterPath
                ))
            }
            if let change {
                guard change.basis.currentPlacement == tip,
                      change.basis.proposedPath == afterPath else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
        }
        expectedPathChanges.sort()
        guard expectedPathChanges == plan.assetPathChanges,
              expectedPathChanges.map(\.assetID) == plan.affectedAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: plan.afterNodes.map { ($0.id, $0) })
        for id in affectedIDs {
            if let value = afterByID[id], let row = rowsByID[id] {
                let replacement = try LocationNodeRow(value)
                row.workspaceID = replacement.workspaceID; row.siteID = replacement.siteID
                row.parentNodeID = replacement.parentNodeID; row.kind = replacement.kind
                row.label = replacement.label; row.shortCode = replacement.shortCode
                row.siblingOrder = replacement.siblingOrder; row.state = replacement.state
                row.revision = replacement.revision; row.mutationID = replacement.mutationID
                row.occurredAt = replacement.occurredAt
                row.canonicalData = replacement.canonicalData
            } else if let value = afterByID[id] {
                modelContext.insert(try LocationNodeRow(value))
            } else if let row = rowsByID[id] {
                modelContext.delete(row)
            }
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: try affectedIDs.map { try .init(kind: .locationNode, id: $0) },
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applyAssetPlacementChange(
        _ plan: AssetPlacementChangePlanV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        let rebuilt = try AssetPlacementChangePlanV1(
            operationID: plan.operationID,
            mutationID: plan.mutationID,
            basis: plan.basis,
            newEventID: plan.newEventID,
            resultingPhysicalEpisodeID: plan.resultingPhysicalEpisodeID,
            componentContributions: plan.componentContributions
        )
        guard rebuilt == plan else { throw WorkspaceMutationFailureV1.invalidCommand }
        let assetID = plan.basis.assetID
        let assets = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID }))
        guard assets.count == 1, let asset = assets.first else { throw WorkspaceMutationFailureV1.invalidCommand }
        let placementRows = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
            predicate: #Predicate { $0.assetID == assetID }
        ))
        let placements = try placementRows.map { try $0.value() }
        let predecessorIDs = Set(placements.compactMap(\.predecessorEventID))
        let tips = placements.filter { !predecessorIDs.contains($0.id) }
        let newEventID = plan.newEventID
        guard tips.count <= 1, tips.first == plan.basis.currentPlacement,
              asset.siteID == (plan.basis.currentPlacement?.siteID ?? plan.basis.proposedSiteID),
              try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
                predicate: #Predicate { $0.id == newEventID }
              )).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        let exactPath = try currentLocationPath(
            workspaceID: plan.basis.workspaceID,
            siteID: plan.basis.proposedSiteID,
            nodeID: plan.basis.proposedLocationNodeID
        )
        guard exactPath == plan.basis.proposedPath else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let event = try AssetPlacementEventV1(
            id: plan.newEventID,
            workspaceID: plan.basis.workspaceID,
            assetID: assetID,
            siteID: plan.basis.proposedSiteID,
            locationNodeID: plan.basis.proposedLocationNodeID,
            predecessorEventID: plan.basis.currentPlacement?.id,
            source: plan.basis.source,
            physicalEpisodeID: plan.resultingPhysicalEpisodeID,
            continuity: plan.basis.reviewedContinuity,
            pathSnapshot: plan.basis.proposedPath,
            mutationID: plan.mutationID,
            occurredAt: occurredAt
        )
        try AssetPlacementHistoryV1.validate(placements + [event])
        asset.siteID = event.siteID
        asset.updatedAt = occurredAt
        modelContext.insert(try AssetPlacementEventRow(event))
        return try WorkspaceMutationEffectV1(
            affectedEntities: try [
                .init(kind: .asset, id: assetID),
                .init(kind: .assetPlacementEvent, id: event.id),
            ],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func currentLocationPath(
        workspaceID: WorkspaceID,
        siteID: UUID,
        nodeID: UUID?
    ) throws -> LocationPathSnapshotV1 {
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count == 1, let site = sites.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let rawWorkspaceID = workspaceID.rawValue
        let nodes = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(
            predicate: #Predicate { $0.workspaceID == rawWorkspaceID }
        )).map { try $0.value() }
        try LocationHierarchyPolicyV1.validate(nodes)
        return try makeLocationPath(
            siteID: siteID,
            siteDisplay: site.label,
            nodeID: nodeID,
            nodes: nodes
        )
    }

    private func makeLocationPath(
        siteID: UUID,
        siteDisplay: String,
        nodeID: UUID?,
        nodes: [LocationNodeV1]
    ) throws -> LocationPathSnapshotV1 {
        guard let nodeID else {
            return try LocationPathSnapshotV1(siteID: siteID, siteDisplay: siteDisplay, nodes: [])
        }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var cursorID: UUID? = nodeID
        var visited = Set<UUID>()
        var reversed: [LocationPathComponentV1] = []
        while let id = cursorID {
            guard visited.insert(id).inserted, let node = byID[id], node.siteID == siteID,
                  node.state == .active else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            reversed.append(try LocationPathComponentV1(
                nodeID: node.id,
                kind: node.kind,
                label: node.label,
                shortCode: node.shortCode,
                revision: node.revision
            ))
            cursorID = node.parentNodeID
        }
        return try LocationPathSnapshotV1(
            siteID: siteID,
            siteDisplay: siteDisplay,
            nodes: Array(reversed.reversed())
        )
    }

    private func applyAssetCompositionChange(
        _ plan: AssetCompositionChangePlanV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try plan.validate()
        let event = plan.event
        let eventID = event.id
        guard try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(
            predicate: #Predicate { $0.id == eventID }
        )).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        let edgeID = event.edge.id
        let edgeRows = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>(
            predicate: #Predicate { $0.id == edgeID }
        ))
        guard edgeRows.count <= 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        let priorEvents = try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(
            predicate: #Predicate { $0.edgeID == edgeID }
        ))
        let priorValues = try priorEvents.map {
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEventV1.self, from: $0.canonicalData)
            try value.validate()
            return value
        }
        let predecessorIDs = Set(priorValues.compactMap(\.predecessorEventID))
        let tips = priorValues.filter { !predecessorIDs.contains($0.id) }
        let priorRevision: UInt64
        if let prior = edgeRows.first {
            guard prior.revision >= 0, prior.revision < Int64.max else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            priorRevision = UInt64(prior.revision)
        } else {
            priorRevision = 0
        }
        guard tips.count <= 1, tips.first?.id == event.predecessorEventID,
              event.edge.revision == priorRevision + 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        try AssetCompositionHistoryV1.validate(priorValues + [event], currentEdge: event.edge)
        let allEdges = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>()).map {
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEdgeV1.self, from: $0.canonicalData)
            try value.validate()
            return value
        }
        let resultingEdges = (allEdges.filter { $0.id != edgeID } + [event.edge]).filter(\.isActive).sorted { $0.id.uuidString < $1.id.uuidString }
        let liveAssetIDs = Set(try modelContext.fetch(FetchDescriptor<Asset>()).map(\.id))
        let placementValues = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>()).map { try $0.value() }
        let allPredecessors = Set(placementValues.compactMap(\.predecessorEventID))
        let placementTips = placementValues.filter {
            liveAssetIDs.contains($0.assetID) && !allPredecessors.contains($0.id)
        }
        guard Set(placementTips.map(\.assetID)).count == placementTips.count,
              Set(placementTips.map(\.assetID)) == liveAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementByAsset = Dictionary(uniqueKeysWithValues: placementTips.map { ($0.assetID, $0) })
        guard plan.currentPlacementByAssetID.allSatisfy({ placementByAsset[$0.key] == $0.value }),
              resultingEdges == plan.resultingActiveEdges else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        try AssetCompositionPolicyV1.validate(edges: resultingEdges, placementByAssetID: placementByAsset)
        if let row = edgeRows.first {
            let replacement = try AssetCompositionEdgeRow(event.edge)
            row.workspaceID = replacement.workspaceID; row.parentAssetID = replacement.parentAssetID
            row.childAssetID = replacement.childAssetID; row.relationship = replacement.relationship
            row.isActive = replacement.isActive; row.revision = replacement.revision
            row.edgeSHA256 = replacement.edgeSHA256; row.canonicalData = replacement.canonicalData
        } else {
            modelContext.insert(try AssetCompositionEdgeRow(event.edge))
        }
        modelContext.insert(try AssetCompositionEventRow(event))
        return try WorkspaceMutationEffectV1(
            affectedEntities: try [
                .init(kind: .assetCompositionEdge, id: event.edge.id),
                .init(kind: .assetCompositionEvent, id: event.id),
            ],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applySavedSmartView(
        _ mutation: SavedSmartViewMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try mutation.validate()
        let id = mutation.id
        let stableKey = SavedSmartViewRowV1.key(
            workspaceID: mutation.workspaceID,
            stableID: mutation.stableID
        )
        let byID = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
            predicate: #Predicate { $0.id == id }
        ))
        let byStableKey = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
            predicate: #Predicate { $0.workspaceStableKey == stableKey }
        ))
        guard byID.count <= 1, byStableKey.count <= 1,
              Set((byID + byStableKey).map(\.id)).count <= 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let existing = byID.first ?? byStableKey.first
        if let existing {
            guard existing.id == id,
                  existing.workspaceStableKey == stableKey,
                  existing.workspaceID == mutation.workspaceID,
                  existing.stableID == mutation.stableID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        let existingDescriptor = try existing?.descriptor()
        switch mutation.disposition {
        case .upsert:
            guard let descriptor = mutation.descriptor,
                  descriptor.origin == .userSaved,
                  existingDescriptor.map({
                      $0.revision == mutation.expectedDescriptorRevision
                  })
                    ?? (mutation.expectedDescriptorRevision == 0) else {
                throw WorkspaceMutationFailureV1.staleEntityRevision(
                    try .init(kind: .savedSmartView, id: id)
                )
            }
            if let existing { modelContext.delete(existing) }
            modelContext.insert(try SavedSmartViewRowV1(descriptor))
        case .delete:
            guard let existing,
                  existingDescriptor?.origin == .userSaved,
                  existingDescriptor?.revision == mutation.expectedDescriptorRevision,
                  existing.workspaceID == mutation.workspaceID,
                  existing.stableID == mutation.stableID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            modelContext.delete(existing)
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: [.init(kind: .savedSmartView, id: id)],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("..") && !value.contains("\\")
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }
}

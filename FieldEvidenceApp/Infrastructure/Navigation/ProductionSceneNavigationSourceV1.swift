import Foundation
import SwiftData

enum ProductionSceneNavigationSourceFailureV1: Error, Equatable {
    case tooManyTargets
    case corruptSource
}

/// Builds the runtime-only route availability projection from the active
/// generation. The caller owns the one scene read token that encloses this
/// synchronous read; this type never retains persistence objects.
@MainActor
enum ProductionSceneNavigationSourceV1 {
    private static let maximumSuppliedTargets =
        (AppRootV1.frozenOrder.count * SceneNavigationSnapshotV1.maximumPathDepth) + 3
    private static let maximumIdentitiesPerQuery = 256
    private static let probedKinds: [WorkspaceEntityKindV1] = [
        .site, .asset, .locationNode, .signoffSnapshot, .roundSession,
        .fieldDraftCheckpoint, .surveyDefinitionIdentity, .surveySession,
        .workflowRecord, .report,
    ]

    static func context(
        for targets: [NavigationTargetV1],
        in storeSession: StoreSessionCoordinator,
        registry: RouteRegistryV1
    ) throws -> RouteResolutionContextV1 {
        guard targets.count <= maximumSuppliedTargets else {
            throw ProductionSceneNavigationSourceFailureV1.tooManyTargets
        }

        let workspaceID = storeSession.workspaceID
        let generationID = storeSession.generationID
        let modelContext = storeSession.modelContext
        let currentTargets = targets.filter { $0.workspaceID == workspaceID }
        let probedIDs = Set(currentTargets.flatMap {
            [$0.stableEntityID, $0.stableSessionID, $0.stableLocationID].compactMap { $0 }
        })
        let identities = try probedIDs.flatMap { id in
            try probedKinds.map { try WorkspaceEntityIdentityV1(kind: $0, id: id) }
        }.sorted { $0.stableKey < $1.stableKey }
        let chunks: [[WorkspaceEntityIdentityV1]] = identities.isEmpty
            ? [[]]
            : stride(from: 0, to: identities.count, by: maximumIdentitiesPerQuery).map {
                Array(identities[$0..<min($0 + maximumIdentitiesPerQuery, identities.count)])
            }
        let queries = try chunks.map { chunk in
            try storeSession.workspaceWriter.query(
                WorkspacePackageLifecycleQueryRequestV1(
                    workspaceID: workspaceID,
                    generationID: generationID,
                    operation: .query,
                    identities: chunk
                )
            )
        }
        guard let sourceRevision = queries.first?.revision,
              queries.allSatisfy({ $0.revision == sourceRevision }) else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        let existing = Set(queries.flatMap(\.existingIdentities))
        let revisions = Dictionary(uniqueKeysWithValues: sourceRevision.entityRevisions.map {
            ($0.identity, $0.revision)
        })

        var sourceAvailability: [NavigationTargetV1: RouteTargetAvailabilityV1] = [:]
        for root in AppRootV1.frozenOrder {
            let marker = try NavigationTargetV1(
                workspaceID: workspaceID,
                destination: RouteRegistryV1.rootDestination(for: root)
            )
            sourceAvailability[marker] = .available
        }

        var availablePackageIDs = Set<String>()
        for target in targets {
            let result = try availability(
                for: target,
                workspaceID: workspaceID,
                modelContext: modelContext,
                registry: registry,
                existing: existing,
                revisions: revisions
            )
            sourceAvailability[target] = result.availability
            if let packageID = result.availablePackageID {
                availablePackageIDs.insert(packageID)
            }
        }

        return RouteResolutionContextV1(
            currentWorkspaceID: workspaceID,
            currentRevision: sourceRevision.revision,
            availablePackageIDs: availablePackageIDs,
            sourceAvailability: sourceAvailability
        )
    }

    private static func availability(
        for target: NavigationTargetV1,
        workspaceID: WorkspaceID,
        modelContext: ModelContext,
        registry: RouteRegistryV1,
        existing: Set<WorkspaceEntityIdentityV1>,
        revisions: [WorkspaceEntityIdentityV1: UInt64]
    ) throws -> (availability: RouteTargetAvailabilityV1, availablePackageID: String?) {
        guard target.workspaceID == workspaceID else {
            return (.fallback(.wrongWorkspace), nil)
        }
        guard (try? target.validate()) != nil else {
            return (.fallback(.invalidTarget), nil)
        }

        let hasEntity = target.stableEntityID != nil
        let hasSession = target.stableSessionID != nil
        let hasLocation = target.stableLocationID != nil
        let hasSchedule = target.stableScheduleDefinitionID != nil
            || target.stableScheduleReleaseID != nil || target.stableOccurrenceID != nil
        let hasPackage = target.packageSurfaceID != nil
        let semanticGroupCount = [hasEntity, hasSession, hasLocation, hasSchedule, hasPackage]
            .filter { $0 }.count

        if semanticGroupCount == 0 {
            return (identitylessAvailability(target, registry: registry), nil)
        }

        if hasPackage {
            guard semanticGroupCount == 1, target.destination == .packageSurface,
                  target.requestedMode == .read, target.expectedRevision == nil,
                  target.draftResumeAnchor == nil, target.fieldPosition == nil,
                  target.searchAnchor == nil else {
                return (.fallback(.invalidTarget), nil)
            }
            return try packageAvailability(
                target: target, workspaceID: workspaceID,
                modelContext: modelContext, registry: registry
            )
        }

        if hasSchedule {
            guard semanticGroupCount == 1, target.expectedRevision == nil,
                  target.draftResumeAnchor == nil, target.fieldPosition == nil,
                  target.searchAnchor == nil else {
                return (.fallback(.invalidTarget), nil)
            }
            return (try scheduleAvailability(
                target: target, workspaceID: workspaceID, modelContext: modelContext
            ), nil)
        }

        if target.destination == .signoffEditor || target.destination == .signoffHistory {
            guard hasEntity, semanticGroupCount == 1 else {
                return (.fallback(.invalidTarget), nil)
            }
            return (try signoffAvailability(
                target: target, workspaceID: workspaceID,
                modelContext: modelContext, existing: existing
            ), nil)
        }

        // Scan-to-Work is the one currently defined compound semantic target.
        if hasEntity || hasSession || hasLocation {
            if semanticGroupCount > 1 {
                guard semanticGroupCount == 3, target.destination == .work,
                      target.stableEntityID != nil, target.stableSessionID != nil,
                      target.stableLocationID != nil, target.expectedRevision == nil,
                      target.draftResumeAnchor == nil, target.fieldPosition == nil,
                      target.searchAnchor == nil else {
                    return (.fallback(.invalidTarget), nil)
                }
                let entity = try entityAvailability(
                    target: target, permittedKinds: [.asset], permitsPacketID: false,
                    workspaceID: workspaceID, modelContext: modelContext,
                    existing: existing, revisions: revisions
                )
                guard case .available = entity else { return (entity, nil) }
                let location = try locationAvailability(
                    target: target, workspaceID: workspaceID,
                    existing: existing, revisions: revisions
                )
                guard case .available = location else { return (location, nil) }
                return (try scanToWorkSessionAvailability(
                    target: target, workspaceID: workspaceID, modelContext: modelContext,
                    existing: existing
                ), nil)
            }
            if hasEntity {
                let role: ([WorkspaceEntityKindV1], Bool)
                switch target.destination {
                case .assets: role = ([.asset, .surveyDefinitionIdentity], false)
                case .reports: role = ([.report], false)
                case .draftReview: role = ([.fieldDraftCheckpoint, .workflowRecord], false)
                case .work: role = ([.asset], true)
                default: return (.fallback(.invalidTarget), nil)
                }
                return (try entityAvailability(
                    target: target, permittedKinds: role.0, permitsPacketID: role.1,
                    workspaceID: workspaceID, modelContext: modelContext,
                    existing: existing, revisions: revisions
                ), nil)
            }
            if hasSession {
                guard target.destination == .work else {
                    return (.fallback(.invalidTarget), nil)
                }
                return (try sessionAvailability(
                    target: target, permittedKinds: [.roundSession, .surveySession],
                    workspaceID: workspaceID, modelContext: modelContext,
                    existing: existing
                ), nil)
            }
            guard target.destination == .work else {
                return (.fallback(.invalidTarget), nil)
            }
            return (try locationAvailability(
                target: target, workspaceID: workspaceID,
                existing: existing, revisions: revisions
            ), nil)
        }

        return (.fallback(.invalidTarget), nil)
    }

    private static func identitylessAvailability(
        _ target: NavigationTargetV1,
        registry: RouteRegistryV1
    ) -> RouteTargetAvailabilityV1 {
        guard target.expectedRevision == nil, target.draftResumeAnchor == nil,
              registry.descriptors.contains(where: {
                  $0.destination == target.destination && $0.root == target.root
              }) else {
            return .fallback(.invalidTarget)
        }
        if target.isIdentitylessSceneRootMarker { return .available }
        switch target.destination {
        case .settings, .startupMaintenance, .mutationRecovery, .recoveryCenter,
             .recipientReviewRequest, .recipientReviewResponseQuarantine:
            guard target.requestedMode == .read, target.fieldPosition == nil,
                  target.searchAnchor == nil else {
                return .fallback(.invalidTarget)
            }
            return .available
        case .searchResults:
            guard target.requestedMode == .read, target.searchAnchor != nil else {
                return .fallback(.invalidTarget)
            }
            return .available
        case .draftReview:
            guard target.requestedMode == .resume, target.fieldPosition != nil else {
                return .fallback(.invalidTarget)
            }
            return .available
        default:
            return .fallback(.invalidTarget)
        }
    }

    private static func entityAvailability(
        target: NavigationTargetV1,
        permittedKinds: [WorkspaceEntityKindV1],
        permitsPacketID: Bool,
        workspaceID: WorkspaceID,
        modelContext: ModelContext,
        existing: Set<WorkspaceEntityIdentityV1>,
        revisions: [WorkspaceEntityIdentityV1: UInt64]
    ) throws -> RouteTargetAvailabilityV1 {
        guard let id = target.stableEntityID else { return .fallback(.invalidTarget) }
        if target.destination == .draftReview {
            guard target.searchAnchor == nil else { return .fallback(.invalidTarget) }
        } else {
            guard target.draftResumeAnchor == nil, target.fieldPosition == nil,
                  target.searchAnchor == nil else {
                return .fallback(.invalidTarget)
            }
        }
        let presentKinds = try probedKinds.filter {
            existing.contains(try WorkspaceEntityIdentityV1(kind: $0, id: id))
        }
        let permittedPresent = presentKinds.filter { kind in permittedKinds.contains(kind) }
        if target.draftResumeAnchor != nil,
           !permittedKinds.contains(.fieldDraftCheckpoint) {
            return .fallback(.invalidTarget)
        }
        let packets = permitsPacketID
            ? try workPackets(packetID: id, workspaceID: workspaceID, modelContext: modelContext)
            : []
        if packets.count > 1 { return .fallback(.invalidTarget) }
        let packet = packets.first
        let candidateCount = permittedPresent.count + (packet == nil ? 0 : 1)
        if candidateCount > 1 { return .fallback(.invalidTarget) }
        guard candidateCount == 1 else {
            return .fallback(presentKinds.isEmpty ? .deletedOrTombstoned : .invalidTarget)
        }

        if let packet {
            guard target.requestedMode == .read else { return .fallback(.invalidTarget) }
            return revisionAvailability(expected: target.expectedRevision, current: packet.revision)
        }
        guard let kind = permittedPresent.first else { return .fallback(.invalidTarget) }
        let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)

        switch kind {
        case .asset:
            let retired = try assetIsRetired(
                assetID: id, workspaceID: workspaceID, modelContext: modelContext
            )
            if retired { return .fallback(.deletedOrTombstoned) }
            return revisionAvailability(expected: target.expectedRevision, current: revisions[identity])
        case .report:
            guard target.requestedMode == .read else { return .fallback(.invalidTarget) }
            return revisionAvailability(expected: target.expectedRevision, current: revisions[identity])
        case .workflowRecord:
            guard target.draftResumeAnchor == nil else { return .fallback(.invalidTarget) }
            let workspaceRecord = try workflowRecord(
                recordID: id, modelContext: modelContext
            )
            guard let workspaceRecord,
                  WorkflowState(rawValue: workspaceRecord.state) != nil else {
                throw ProductionSceneNavigationSourceFailureV1.corruptSource
            }
            if target.requestedMode == .resume {
                guard workspaceRecord.state == WorkflowState.draft.rawValue else {
                    return .fallback(.deletedOrTombstoned)
                }
            }
            return revisionAvailability(expected: target.expectedRevision, current: revisions[identity])
        case .fieldDraftCheckpoint:
            let checkpoint = try fieldDraft(
                draftID: id, workspaceID: workspaceID, modelContext: modelContext
            )
            guard let checkpoint else { return .fallback(.deletedOrTombstoned) }
            if target.draftResumeAnchor != nil, target.requestedMode != .resume {
                return .fallback(.invalidTarget)
            }
            if checkpoint.state == .committed || checkpoint.state == .discarded {
                return .fallback(.deletedOrTombstoned)
            }
            if let anchor = target.draftResumeAnchor, anchor != checkpoint.resumeAnchor {
                return .fallback(.staleRevision)
            }
            return revisionAvailability(
                expected: target.expectedRevision, current: checkpoint.draftRevision
            )
        case .surveyDefinitionIdentity:
            guard let definition = try surveyDefinition(
                definitionID: id, workspaceID: workspaceID, modelContext: modelContext
            ) else { return .fallback(.deletedOrTombstoned) }
            if definition.lifecycleState == .retired {
                return .fallback(.deletedOrTombstoned)
            }
            return revisionAvailability(
                expected: target.expectedRevision, current: definition.revision
            )
        default:
            return .fallback(.invalidTarget)
        }
    }

    private static func sessionAvailability(
        target: NavigationTargetV1,
        permittedKinds: [WorkspaceEntityKindV1],
        workspaceID: WorkspaceID,
        modelContext: ModelContext,
        existing: Set<WorkspaceEntityIdentityV1>
    ) throws -> RouteTargetAvailabilityV1 {
        guard let id = target.stableSessionID, target.draftResumeAnchor == nil,
              target.fieldPosition == nil, target.searchAnchor == nil else {
            return .fallback(.invalidTarget)
        }
        let allSessionKinds: [WorkspaceEntityKindV1] = [.roundSession, .surveySession]
        let present = try allSessionKinds.filter {
            existing.contains(try WorkspaceEntityIdentityV1(kind: $0, id: id))
        }
        let permitted = present.filter { kind in permittedKinds.contains(kind) }
        if permitted.count > 1 { return .fallback(.invalidTarget) }
        guard let kind = permitted.first else {
            return .fallback(present.isEmpty ? .deletedOrTombstoned : .invalidTarget)
        }

        switch kind {
        case .roundSession:
            guard let current = try roundSession(
                sessionID: id, workspaceID: workspaceID, modelContext: modelContext
            ) else { return .fallback(.deletedOrTombstoned) }
            if target.requestedMode == .resume,
               current.state == .completed || current.state == .archived {
                return .fallback(.invalidTarget)
            }
            return revisionAvailability(expected: target.expectedRevision, current: current.revision)
        case .surveySession:
            guard let session = try surveySession(
                sessionID: id, workspaceID: workspaceID, modelContext: modelContext
            ) else { return .fallback(.deletedOrTombstoned) }
            if session.state == .deleted { return .fallback(.deletedOrTombstoned) }
            if target.requestedMode == .resume,
               ![.draft, .paused, .reviewRequired].contains(session.state) {
                return .fallback(.invalidTarget)
            }
            return revisionAvailability(expected: target.expectedRevision, current: session.revision)
        default:
            return .fallback(.invalidTarget)
        }
    }

    private static func locationAvailability(
        target: NavigationTargetV1,
        workspaceID: WorkspaceID,
        existing: Set<WorkspaceEntityIdentityV1>,
        revisions: [WorkspaceEntityIdentityV1: UInt64]
    ) throws -> RouteTargetAvailabilityV1 {
        guard let id = target.stableLocationID, target.draftResumeAnchor == nil,
              target.fieldPosition == nil, target.searchAnchor == nil else {
            return .fallback(.invalidTarget)
        }
        let site = try WorkspaceEntityIdentityV1(kind: .site, id: id)
        guard existing.contains(site) else {
            let node = try WorkspaceEntityIdentityV1(kind: .locationNode, id: id)
            return .fallback(existing.contains(node) ? .invalidTarget : .deletedOrTombstoned)
        }
        return revisionAvailability(expected: target.expectedRevision, current: revisions[site])
    }

    private static func scanToWorkSessionAvailability(
        target: NavigationTargetV1,
        workspaceID: WorkspaceID,
        modelContext: ModelContext,
        existing: Set<WorkspaceEntityIdentityV1>
    ) throws -> RouteTargetAvailabilityV1 {
        guard let assetID = target.stableEntityID,
              let siteID = target.stableLocationID,
              let sessionID = target.stableSessionID else {
            return .fallback(.invalidTarget)
        }
        let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        let sessionIdentity = try WorkspaceEntityIdentityV1(kind: .roundSession, id: sessionID)
        guard existing.contains(assetIdentity), existing.contains(sessionIdentity) else {
            return .fallback(.deletedOrTombstoned)
        }
        let assets = try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        ))
        guard assets.count == 1, assets[0].siteID == siteID else {
            return .fallback(.invalidTarget)
        }
        guard let current = try roundSession(
            sessionID: sessionID, workspaceID: workspaceID, modelContext: modelContext
        ) else { return .fallback(.deletedOrTombstoned) }
        guard current.items.contains(where: {
            $0.selection.assetID == assetID && $0.selection.siteID == siteID
        }) else { return .fallback(.invalidTarget) }
        if target.requestedMode == .resume,
           current.state == .completed || current.state == .archived {
            return .fallback(.invalidTarget)
        }
        return .available
    }

    private static func scheduleAvailability(
        target: NavigationTargetV1,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> RouteTargetAvailabilityV1 {
        let supportedShape = target.destination == .work
            ? target.requestedMode == .read && target.stableOccurrenceID == nil
            : target.destination == .scheduleOccurrence
                && (target.requestedMode == .read || target.requestedMode == .resume)
                && target.stableOccurrenceID != nil
        guard supportedShape, let definitionID = target.stableScheduleDefinitionID,
              let releaseID = target.stableScheduleReleaseID,
              let expectedDefinitionRevision = target.expectedScheduleRevision else {
            return .fallback(.invalidTarget)
        }
        let workspace = workspaceID.rawValue
        let definitions = try modelContext.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        )).map { try $0.value() }
        let history = try modelContext.fetch(FetchDescriptor<OccurrenceHistoryEventRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        )).map { try $0.value() }
        try ScheduleLifecycleClosureV1(definitions: definitions, history: history).validate()

        let releases = definitions.filter { $0.scheduleDefinitionID == definitionID }
            .sorted { $0.revision < $1.revision }
        guard let currentRelease = releases.last else {
            let releaseExistsElsewhere = definitions.contains { $0.releaseID == releaseID }
            return .fallback(releaseExistsElsewhere ? .invalidTarget : .deletedOrTombstoned)
        }
        if currentRelease.lifecycleState == .retired {
            return .fallback(.deletedOrTombstoned)
        }
        guard currentRelease.releaseID == releaseID,
              currentRelease.revision == expectedDefinitionRevision else {
            return .fallback(.staleRevision)
        }

        guard let occurrenceID = target.stableOccurrenceID else {
            return target.requestedMode == .read ? .available : .fallback(.invalidTarget)
        }
        let occurrenceHistory = history.filter { $0.occurrenceID == occurrenceID }
            .sorted { $0.revision < $1.revision }
        guard let currentOccurrence = occurrenceHistory.last else {
            return .fallback(.deletedOrTombstoned)
        }
        guard currentOccurrence.scheduleRelease.scheduleDefinitionID == definitionID else {
            return .fallback(.invalidTarget)
        }
        guard currentOccurrence.scheduleRelease.releaseID == releaseID else {
            return .fallback(.staleRevision)
        }
        if target.requestedMode == .resume {
            if currentOccurrence.action == .complete {
                return .fallback(.invalidTarget)
            }
            if let kind = currentOccurrence.exception?.kind,
               [.skipped, .cancelled, .missed, .retiredForRuleChange].contains(kind) {
                return .fallback(.invalidTarget)
            }
        }
        return revisionAvailability(
            expected: target.expectedOccurrenceRevision, current: currentOccurrence.revision
        )
    }

    private static func signoffAvailability(
        target: NavigationTargetV1,
        workspaceID: WorkspaceID,
        modelContext: ModelContext,
        existing: Set<WorkspaceEntityIdentityV1>
    ) throws -> RouteTargetAvailabilityV1 {
        guard let id = target.stableEntityID, target.draftResumeAnchor == nil,
              target.fieldPosition == nil, target.searchAnchor == nil else {
            return .fallback(.invalidTarget)
        }
        let identity = try WorkspaceEntityIdentityV1(kind: .signoffSnapshot, id: id)
        guard existing.contains(identity) else {
            return .fallback(try anyKnownIdentity(id, existing: existing)
                ? .invalidTarget : .deletedOrTombstoned)
        }
        guard target.destination == .signoffEditor
                ? target.requestedMode == .resume : target.requestedMode == .read else {
            return .fallback(.invalidTarget)
        }
        let component = try signoffComponent(
            snapshotID: id, workspaceID: workspaceID, modelContext: modelContext
        )
        guard let snapshot = component[id] else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        let successors = component.values.filter { $0.supersedesSnapshotID == id }
        if target.destination == .signoffEditor, !successors.isEmpty {
            return .fallback(.staleRevision)
        }
        return revisionAvailability(
            expected: target.expectedRevision, current: snapshot.subjectRevision
        )
    }

    private static func packageAvailability(
        target: NavigationTargetV1,
        workspaceID: WorkspaceID,
        modelContext: ModelContext,
        registry: RouteRegistryV1
    ) throws -> (availability: RouteTargetAvailabilityV1, availablePackageID: String?) {
        guard let surfaceID = target.packageSurfaceID else {
            return (.fallback(.invalidTarget), nil)
        }
        let owners = registry.manifests.filter { manifest in
            manifest.routes.contains { $0.routeID == surfaceID && $0.root == target.root }
        }
        guard owners.count == 1, let packageID = owners.first?.packageID else {
            return (.fallback(owners.isEmpty ? .retiredOrMissingPackage : .invalidTarget), nil)
        }

        let workspace = workspaceID.rawValue
        let promoted = try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        )).map { try $0.value() }
        let runs = try modelContext.fetch(FetchDescriptor<PackageSandboxRunRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        )).map { try $0.value() }
        let receipts = try modelContext.fetch(FetchDescriptor<PackagePromotionReceiptRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        )).map { try $0.value() }
        let pointers = try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        )).map { try $0.value() }
        _ = try PackageEvolutionLifecycleClosureV1(
            promotedReleases: promoted, sandboxRuns: runs,
            promotionReceipts: receipts, activePointers: pointers
        )

        let packagePointers = pointers.filter { $0.packageID == packageID }
            .sorted { $0.revision < $1.revision }
        for (index, pointer) in packagePointers.enumerated() {
            if index == 0 {
                guard pointer.revision == 1, pointer.supersedesPointerID == nil else {
                    throw ProductionSceneNavigationSourceFailureV1.corruptSource
                }
            } else {
                try pointer.validateSuccessor(
                    of: packagePointers[index - 1],
                    expectedRevision: packagePointers[index - 1].revision
                )
            }
        }
        guard let pointer = packagePointers.last else {
            return (.fallback(.retiredOrMissingPackage), nil)
        }
        let releases = promoted.filter { $0.releaseRecordID == pointer.activeReleaseRecordID }
        guard releases.count == 1, let release = releases.first else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        guard release.packageRelease.packageID == packageID,
              release.packageRelease.packageReleaseID == pointer.activePackageReleaseID,
              release.releaseRecordSHA256 == pointer.activeReleaseRecordSHA256 else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }

        let packageReleaseID = release.packageRelease.packageReleaseID
        let dispositions = try modelContext.fetch(FetchDescriptor<PackageLifecycleDispositionRow>(
            predicate: #Predicate {
                $0.workspaceID == workspace && $0.packageReleaseID == packageReleaseID
            }
        )).map { try $0.value(release: release.packageRelease) }
            .sorted { $0.revision < $1.revision }
        for (index, disposition) in dispositions.enumerated() {
            if index == 0 {
                guard disposition.revision == 1,
                      disposition.supersedesDispositionID == nil else {
                    throw ProductionSceneNavigationSourceFailureV1.corruptSource
                }
            } else {
                try disposition.validateSuccessor(
                    of: dispositions[index - 1], release: release.packageRelease
                )
            }
        }
        let state = dispositions.last?.state ?? .active
        guard state == .active || state == .deprecated else {
            return (.fallback(.retiredOrMissingPackage), nil)
        }
        return (.available, packageID)
    }

    private static func workPackets(
        packetID: UUID,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> [WorkPacketManifestV1] {
        let workspace = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.packetID == packetID }
        ))
        let values = try rows.map { try $0.value() }
        guard Set(values.map(\.manifestID)).count == values.count,
              Set(values.map(\.packetVersion)).count == values.count else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        return values.sorted { $0.packetVersion < $1.packetVersion }
    }

    private static func workflowRecord(
        recordID: UUID,
        modelContext: ModelContext
    ) throws -> WorkflowRecord? {
        let rows = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        ))
        guard rows.count <= 1 else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        return rows.first
    }

    private static func roundSession(
        sessionID: UUID,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> RoundSessionV1? {
        let workspace = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<RoundSessionRevisionRowV1>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.sessionID == sessionID }
        ))
        let history = try rows.map { try $0.value() }.sorted { $0.revision < $1.revision }
        return try RoundSessionHistoryValidatorV1.validate(
            history, workspaceID: workspaceID, sessionID: sessionID
        )
    }

    private static func fieldDraft(
        draftID: UUID,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> FieldDraftCheckpointV1? {
        let workspace = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.draftID == draftID }
        ))
        guard rows.count <= 1 else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        return try rows.first?.value()
    }

    private static func surveyDefinition(
        definitionID: UUID,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> SurveyDefinitionIdentityV1? {
        let workspace = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<SurveyDefinitionIdentityRow>(
            predicate: #Predicate {
                $0.workspaceID == workspace && $0.definitionID == definitionID
            }
        ))
        guard rows.count <= 1 else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        guard let definition = try rows.first?.value() else { return nil }
        let releaseRows = try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>(
            predicate: #Predicate {
                $0.workspaceID == workspace && $0.definitionID == definitionID
            }
        ))
        let releases = try releaseRows.map { try $0.value() }
            .sorted { $0.revision < $1.revision }
        guard let currentRelease = releases.last else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        for (index, release) in releases.enumerated() {
            if index == 0 {
                guard release.revision == 1, release.supersedesReleaseID == nil else {
                    throw ProductionSceneNavigationSourceFailureV1.corruptSource
                }
            } else {
                try release.validateSuccessor(of: releases[index - 1])
            }
        }
        guard (try SurveyDefinitionReleaseReferenceV1(currentRelease))
                == definition.currentRelease else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        return definition
    }

    private static func surveySession(
        sessionID: UUID,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> SurveySessionV1? {
        let workspace = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<SurveySessionRow>(
            predicate: #Predicate { $0.workspaceID == workspace && $0.sessionID == sessionID }
        ))
        guard rows.count <= 1 else {
            throw ProductionSceneNavigationSourceFailureV1.corruptSource
        }
        return try rows.first?.value()
    }

    private static func signoffComponent(
        snapshotID: UUID,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> [UUID: SignoffSnapshotV1] {
        let workspace = workspaceID.rawValue
        var values: [UUID: SignoffSnapshotV1] = [:]
        var queue = [snapshotID]
        var inspected = Set<UUID>()
        while let id = queue.popLast() {
            if !inspected.insert(id).inserted { continue }
            let rows = try modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>(
                predicate: #Predicate { $0.workspaceID == workspace && $0.snapshotID == id }
            ))
            guard rows.count == 1, let value = try rows.first?.value() else {
                throw ProductionSceneNavigationSourceFailureV1.corruptSource
            }
            values[id] = value
            if let predecessorID = value.supersedesSnapshotID { queue.append(predecessorID) }
            let successorRows = try modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>(
                predicate: #Predicate {
                    $0.workspaceID == workspace && $0.supersedesSnapshotID == id
                }
            ))
            guard successorRows.count <= 1 else {
                throw ProductionSceneNavigationSourceFailureV1.corruptSource
            }
            if let successor = try successorRows.first?.value() {
                try successor.validateSupersession(of: value)
                values[successor.snapshotID] = successor
                queue.append(successor.snapshotID)
            }
        }
        for value in values.values {
            if let predecessorID = value.supersedesSnapshotID {
                guard let predecessor = values[predecessorID] else {
                    throw ProductionSceneNavigationSourceFailureV1.corruptSource
                }
                try value.validateSupersession(of: predecessor)
            }
        }
        return values
    }

    private static func assetIsRetired(
        assetID: UUID,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws -> Bool {
        let snapshot = try AssetSemanticPersistentSnapshotV1.load(
            workspaceID: workspaceID, assetID: assetID, in: modelContext
        )
        let ordered = snapshot.lifecycleEvents.sorted { $0.record.revision < $1.record.revision }
        var retired = false
        var previous: AssetLifecycleEventV1?
        var mutationIDs = Set<MutationIDV1>()
        for (index, event) in ordered.enumerated() {
            let record = event.record
            guard record.revision == UInt64(index + 1),
                  record.predecessorEventID == previous?.record.eventID,
                  mutationIDs.insert(record.mutationID).inserted,
                  previous.map({ record.recordedAt >= $0.record.recordedAt }) ?? true else {
                throw ProductionSceneNavigationSourceFailureV1.corruptSource
            }
            switch event.kind {
            case .activeRecorded:
                if retired { throw ProductionSceneNavigationSourceFailureV1.corruptSource }
            case .retiredRecorded, .replacedRecorded:
                retired = true
            case .classificationChangedRecorded, .commissioningNotRecorded:
                break
            }
            if event.kind == .classificationChangedRecorded {
                let matches = snapshot.kindBindings.filter { $0.eventID == record.kindBindingEventID }
                guard matches.count == 1, let binding = matches.first else {
                    throw ProductionSceneNavigationSourceFailureV1.corruptSource
                }
                try event.validateAtomicReference(kindBinding: binding)
            }
            if event.kind == .replacedRecorded {
                let matches = snapshot.successorLinks.filter { $0.linkID == record.successorLinkID }
                guard matches.count == 1, let link = matches.first else {
                    throw ProductionSceneNavigationSourceFailureV1.corruptSource
                }
                try event.validateAtomicReference(successorLink: link)
            }
            previous = event
        }
        return retired
    }

    private static func revisionAvailability(
        expected: UInt64?,
        current: UInt64?
    ) -> RouteTargetAvailabilityV1 {
        guard let expected else { return .available }
        guard let current else { return .fallback(.staleRevision) }
        return expected == current ? .available : .fallback(.staleRevision)
    }

    private static func anyKnownIdentity(
        _ id: UUID,
        existing: Set<WorkspaceEntityIdentityV1>
    ) throws -> Bool {
        try probedKinds.contains {
            existing.contains(try WorkspaceEntityIdentityV1(kind: $0, id: id))
        }
    }
}

import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_LocationHierarchyPlacementCompositionTests: XCTestCase {
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV9_LocationHierarchyPlacementCompositionG01FlatMigrationAndHierarchyRemainStable() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus["schema"] as? String, "V21P03C35LocationPlacementCompositionCorpusV1")
        XCTAssertEqual(corpus["schemaVersion"] as? Int, 1)
        let migrationFixture = try dictionary(corpus, "flatMigration")
        XCTAssertEqual(migrationFixture["sourceSchema"] as? Int, 5)
        XCTAssertEqual(migrationFixture["destinationSchema"] as? Int, 6)
        XCTAssertEqual(migrationFixture["eventsPerAsset"] as? Int, 1)
        XCTAssertEqual(migrationFixture["preservesSiteAndAssetIDs"] as? Bool, true)
        XCTAssertTrue(LocationHierarchyPolicyV1.permits(parent: nil, child: .campus))
        XCTAssertTrue(LocationHierarchyPolicyV1.permits(parent: .building, child: .level))
        XCTAssertFalse(LocationHierarchyPolicyV1.permits(parent: .zone, child: .building))
        XCTAssertEqual(LocationHierarchyPolicyV1.maximumDepth, 8)
        let graph = try makeGraph()
        XCTAssertNoThrow(try LocationHierarchyPolicyV1.validate(graph.nodes))
        for history in Dictionary(grouping: graph.placements, by: \.assetID).values {
            XCTAssertNoThrow(try AssetPlacementHistoryV1.validate(history))
        }
        XCTAssertNoThrow(try AssetCompositionPolicyV1.validate(
            edges: graph.edges,
            placementByAssetID: graph.tips
        ))
        let expected = WorkspaceExpectedRevisionV1(snapshot: try WorkspaceRevisionV1(
            workspaceID: graph.workspaceID,
            generationID: id("70000000-0000-4000-8000-000000000010"),
            revision: 1,
            entityRevisions: []
        ))
        let renameOperationID = id("80000000-0000-4000-8000-000000000010")
        let renamedLeaf = try LocationNodeV1(
            id: graph.nodes[3].id, workspaceID: graph.workspaceID,
            siteID: graph.siteID, parentNodeID: graph.nodes[3].parentNodeID,
            kind: graph.nodes[3].kind, label: "Electrical Room A",
            shortCode: "ER-A", siblingOrder: graph.nodes[3].siblingOrder,
            state: .active, revision: 2,
            provenance: try LocationMutationProvenanceV1(
                mutationID: MutationIDV1(rawValue: renameOperationID),
                occurredAt: Date(timeIntervalSince1970: 30)
            )
        )
        let renamedPath = try LocationPathSnapshotV1(
            siteID: graph.siteID, siteDisplay: "North Campus",
            nodes: try (Array(graph.nodes.prefix(3)) + [renamedLeaf]).map {
                try LocationPathComponentV1(
                    nodeID: $0.id, kind: $0.kind, label: $0.label,
                    shortCode: $0.shortCode, revision: $0.revision
                )
            }
        )
        let pathChanges = try graph.assetIDs.map { assetID in
            try AssetLocationPathChangeV1(
                assetID: assetID,
                beforePath: try XCTUnwrap(graph.tips[assetID]).pathSnapshot,
                afterPath: renamedPath
            )
        }
        let consumerImpact = try LocationHierarchyConsumerImpactV1(
            planIDs: [id("88000000-0000-4000-8000-000000000001")],
            referenceIDs: [id("88000000-0000-4000-8000-000000000002")],
            openRoundIDs: [id("88000000-0000-4000-8000-000000000003")],
            scheduleIDs: [id("88000000-0000-4000-8000-000000000004")],
            reportConsumerIDs: [id("88000000-0000-4000-8000-000000000005")]
        )
        let renamePlan = try LocationHierarchyChangePlanV1(
            operationID: renameOperationID, workspaceID: graph.workspaceID,
            expectedRevision: expected, beforeNodes: [graph.nodes[3]],
            afterNodes: [renamedLeaf], affectedAssetIDs: graph.assetIDs,
            assetPathChanges: pathChanges,
            immutablePlacementReferencedNodeIDs: [graph.nodes[3].id],
            consumerImpact: consumerImpact,
            assetBindingsChange: false, operationContinuityDisposition: nil,
            continuityByAssetID: [:]
        )
        XCTAssertEqual(renamePlan.bindingChangedAssetIDs, [])
        XCTAssertTrue(renamePlan.consumerImpact.searchRebuildRequired)
        XCTAssertTrue(renamePlan.consumerImpact.currentPathProjectionRebuildRequired)
        XCTAssertNoThrow(try LocationHierarchyMutationV1(
            plan: renamePlan, placementChanges: []
        ))
        let archiveOperationID = id("80000000-0000-4000-8000-000000000020")
        let archivedLeaf = try LocationNodeV1(
            id: graph.nodes[3].id, workspaceID: graph.workspaceID,
            siteID: graph.siteID, parentNodeID: graph.nodes[3].parentNodeID,
            kind: graph.nodes[3].kind, label: graph.nodes[3].label,
            shortCode: graph.nodes[3].shortCode,
            siblingOrder: graph.nodes[3].siblingOrder, state: .archived,
            revision: 2,
            provenance: try LocationMutationProvenanceV1(
                mutationID: MutationIDV1(rawValue: archiveOperationID),
                occurredAt: Date(timeIntervalSince1970: 31)
            )
        )
        let siteOnlyPath = try LocationPathSnapshotV1(
            siteID: graph.siteID, siteDisplay: "North Campus", nodes: []
        )
        let archivePathChanges = try graph.assetIDs.map { assetID in
            try AssetLocationPathChangeV1(
                assetID: assetID,
                beforePath: try XCTUnwrap(graph.tips[assetID]).pathSnapshot,
                afterPath: siteOnlyPath
            )
        }
        let archivePlan = try LocationHierarchyChangePlanV1(
            operationID: archiveOperationID, workspaceID: graph.workspaceID,
            expectedRevision: expected, beforeNodes: [graph.nodes[3]],
            afterNodes: [archivedLeaf], affectedAssetIDs: graph.assetIDs,
            assetPathChanges: archivePathChanges,
            immutablePlacementReferencedNodeIDs: [graph.nodes[3].id],
            consumerImpact: try LocationHierarchyConsumerImpactV1(
                planIDs: [], referenceIDs: [], openRoundIDs: [],
                scheduleIDs: [], reportConsumerIDs: []
            ),
            assetBindingsChange: true,
            operationContinuityDisposition: .samePhysicalInstallation,
            continuityByAssetID: [:]
        )
        let archivePlacementChanges = try graph.assetIDs.enumerated().map { index, assetID in
            let tip = try XCTUnwrap(graph.tips[assetID])
            return try AssetPlacementChangePlanV1(
                operationID: archiveOperationID,
                mutationID: MutationIDV1(rawValue: archiveOperationID),
                basis: try AssetPlacementPreviewBasisV1(
                    workspaceID: graph.workspaceID, expectedRevision: expected,
                    assetID: assetID, currentPlacement: tip,
                    proposedSiteID: graph.siteID, proposedLocationNodeID: nil,
                    proposedPath: siteOnlyPath, source: .hierarchyRebase,
                    reviewedContinuity: .samePhysicalInstallation
                ),
                newEventID: id(String(format: "89000000-0000-4000-8000-%012d", index + 1)),
                resultingPhysicalEpisodeID: tip.physicalEpisodeID,
                componentContributions: []
            )
        }
        XCTAssertNoThrow(try LocationDeletionPlanV1(
            operationID: archiveOperationID, workspaceID: graph.workspaceID,
            nodeID: graph.nodes[3].id, expectedRevision: expected,
            affectedNodeIDs: [graph.nodes[3].id],
            affectedAssetIDs: graph.assetIDs, archiveOnly: true
        ))
        XCTAssertNoThrow(try LocationHierarchyMutationV1(
            plan: archivePlan, placementChanges: archivePlacementChanges
        ))
        let migration = try LocationMigrationReceiptV1(
            workspaceID: graph.workspaceID,
            sourceGenerationID: id("70000000-0000-4000-8000-000000000001"),
            candidateGenerationID: id("70000000-0000-4000-8000-000000000002"),
            sourceSiteCount: 1,
            sourceAssetCount: 2,
            bindings: graph.placements.filter { $0.source == .migratedBaseline }.map {
                LocationMigratedBaselineBindingV1(
                    assetID: $0.assetID, siteID: $0.siteID,
                    placementEventID: $0.id, physicalEpisodeID: $0.physicalEpisodeID
                )
            }.sorted()
        )
        let migrationData = try LocationPersistenceCodecV1.encode(migration)
        XCTAssertEqual(try LocationPersistenceCodecV1.decode(LocationMigrationReceiptV1.self, from: migrationData), migration)
        let lastAsset = try deletionCase("last-asset", in: corpus)
        XCTAssertEqual(lastAsset["expected"] as? String, "SITE_AND_HIERARCHY_PRESERVED_HISTORY_PRESERVED")
    }

    func testV9_LocationHierarchyPlacementCompositionA01DeletionIsExplicitAndNeverCascadesHistory() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(
            Set(DeletionRecordKindV2.allCases.map(\.rawValue)),
            ["site", "asset", "workflowRecord", "evidenceFile", "issue", "packet", "report"]
        )
        XCTAssertEqual(try deletionCase("active-component-parent", in: corpus)["expected"] as? String,
                       "REJECT_EXPLICIT_RETIREMENT_REQUIRED")
        XCTAssertEqual(try deletionCase("node-with-active-asset", in: corpus)["expected"] as? String,
                       "REJECT_EXPLICIT_ASSET_DISPOSITION_REQUIRED")
        XCTAssertEqual(try deletionCase("archived-empty-node", in: corpus)["expected"] as? String,
                       "ARCHIVE_ONLY_HISTORY_PRESERVED")
        XCTAssertEqual(try deletionCase("erase-all", in: corpus)["expected"] as? String,
                       "NEW_GENERATION_NO_PRIOR_ROWS_VISIBLE")
        let parentID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
        let childID = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
        let activeEdge = try AssetCompositionEdgeV1(
            id: UUID(uuidString: "60000000-0000-4000-8000-000000000001")!,
            workspaceID: WorkspaceID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!),
            parentAssetID: parentID,
            childAssetID: childID,
            isActive: true,
            revision: 1
        )
        XCTAssertThrowsError(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: parentID,
            deletingSiteID: nil,
            liveAssetSiteByID: [:],
            locationNodes: [],
            placementEvents: [],
            compositionEdges: [activeEdge]
        ))
        XCTAssertNoThrow(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: parentID,
            deletingSiteID: nil,
            liveAssetSiteByID: [:],
            locationNodes: [],
            placementEvents: [],
            compositionEdges: []
        ))
        let graph = try makeGraph()
        XCTAssertThrowsError(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: graph.assetIDs[0], deletingSiteID: nil,
            liveAssetSiteByID: Dictionary(uniqueKeysWithValues: graph.assetIDs.map { ($0, graph.siteID) }), locationNodes: graph.nodes,
            placementEvents: graph.placements, compositionEdges: graph.edges
        ))
        XCTAssertThrowsError(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: nil, deletingSiteID: graph.siteID,
            liveAssetSiteByID: Dictionary(uniqueKeysWithValues: graph.assetIDs.map { ($0, graph.siteID) }), locationNodes: graph.nodes,
            placementEvents: graph.placements, compositionEdges: graph.edges
        ))
        XCTAssertThrowsError(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: graph.assetIDs[0], deletingSiteID: nil,
            liveAssetSiteByID: [
                graph.assetIDs[0]: id("20000000-0000-4000-8000-000000000099"),
                graph.assetIDs[1]: graph.siteID,
            ],
            locationNodes: graph.nodes,
            placementEvents: graph.placements,
            compositionEdges: []
        ))
        // Asset A may already be ledger-deleted while its immutable placement
        // history remains. Deleting live asset B must still validate once all
        // active composition edges have been explicitly retired.
        XCTAssertNoThrow(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
            deletingAssetID: graph.assetIDs[1], deletingSiteID: nil,
            liveAssetSiteByID: [graph.assetIDs[1]: graph.siteID], locationNodes: graph.nodes,
            placementEvents: graph.placements, compositionEdges: []
        ))
        let history = try array(corpus, "placementHistory")
        XCTAssertEqual(history.count, 4)
        XCTAssertEqual(history.filter { ($0 as? [String: Any])?["tip"] as? Bool == true }.count, 2)
    }

    func testV9_LocationHierarchyPlacementCompositionH01HostileGraphsFailClosed() throws {
        let corpus = try loadCorpus()
        let hostile = try strings(corpus, "hostileCases")
        XCTAssertEqual(Set(hostile), [
            "UNKNOWN_DISPOSITION", "IMPLICIT_CASCADE", "CROSS_SITE_PARENT", "ORPHAN_PARENT",
            "HIERARCHY_CYCLE", "DEPTH_NINE", "TWO_PLACEMENT_TIPS", "STALE_PREDECESSOR",
            "REUSED_ID_CHANGED_INPUT", "SECOND_STRUCTURAL_PARENT", "COMPOSITION_CYCLE", "DELETE_ACTIVE_EDGE",
        ])
        XCTAssertEqual(hostile.count, Set(hostile).count)
        let graph = try makeGraph()
        let expected = WorkspaceExpectedRevisionV1(snapshot: try WorkspaceRevisionV1(
            workspaceID: graph.workspaceID,
            generationID: id("70000000-0000-4000-8000-000000000010"),
            revision: 1,
            entityRevisions: []
        ))
        for hostileID in hostile {
            switch hostileID {
            case "UNKNOWN_DISPOSITION", "IMPLICIT_CASCADE":
                XCTAssertThrowsError(try LocationDeletionPlanV1(
                    operationID: id("82000000-0000-4000-8000-000000000001"),
                    workspaceID: graph.workspaceID, nodeID: graph.nodes[3].id,
                    expectedRevision: expected, affectedNodeIDs: [graph.nodes[3].id],
                    affectedAssetIDs: [graph.assetIDs[0]], archiveOnly: false
                ), hostileID)
            case "CROSS_SITE_PARENT":
                let child = try LocationNodeV1(
                    id: id("83000000-0000-4000-8000-000000000001"), workspaceID: graph.workspaceID,
                    siteID: id("20000000-0000-4000-8000-000000000002"), parentNodeID: graph.nodes[0].id,
                    kind: .building, label: "Foreign", shortCode: nil, siblingOrder: 0,
                    state: .active, revision: 1, provenance: graph.nodes[0].provenance
                )
                XCTAssertThrowsError(try LocationHierarchyPolicyV1.validate([graph.nodes[0], child]), hostileID)
            case "ORPHAN_PARENT":
                let orphan = try LocationNodeV1(
                    id: id("83000000-0000-4000-8000-000000000002"), workspaceID: graph.workspaceID,
                    siteID: graph.siteID, parentNodeID: id("83000000-0000-4000-8000-000000000099"),
                    kind: .building, label: "Orphan", shortCode: nil, siblingOrder: 0,
                    state: .active, revision: 1, provenance: graph.nodes[0].provenance
                )
                XCTAssertThrowsError(try LocationHierarchyPolicyV1.validate([orphan]), hostileID)
            case "HIERARCHY_CYCLE":
                let aID = id("83000000-0000-4000-8000-000000000003")
                let bID = id("83000000-0000-4000-8000-000000000004")
                let a = try LocationNodeV1(id: aID, workspaceID: graph.workspaceID, siteID: graph.siteID, parentNodeID: bID, kind: .other, label: "A", shortCode: nil, siblingOrder: 0, state: .active, revision: 1, provenance: graph.nodes[0].provenance)
                let b = try LocationNodeV1(id: bID, workspaceID: graph.workspaceID, siteID: graph.siteID, parentNodeID: aID, kind: .other, label: "B", shortCode: nil, siblingOrder: 0, state: .active, revision: 1, provenance: graph.nodes[0].provenance)
                XCTAssertThrowsError(try LocationHierarchyPolicyV1.validate([a, b]), hostileID)
            case "DEPTH_NINE":
                var nodes: [LocationNodeV1] = []
                for index in 0..<9 {
                    nodes.append(try LocationNodeV1(
                        id: id(String(format: "84000000-0000-4000-8000-%012d", index + 1)),
                        workspaceID: graph.workspaceID, siteID: graph.siteID,
                        parentNodeID: index == 0 ? nil : nodes[index - 1].id,
                        kind: .other, label: "N\(index)", shortCode: nil, siblingOrder: 0,
                        state: .active, revision: 1, provenance: graph.nodes[0].provenance
                    ))
                }
                XCTAssertThrowsError(try LocationHierarchyPolicyV1.validate(nodes), hostileID)
            case "TWO_PLACEMENT_TIPS":
                let history = graph.placements.filter { $0.assetID == graph.assetIDs[0] }
                let branch = try AssetPlacementEventV1(
                    id: id("85000000-0000-4000-8000-000000000001"), workspaceID: graph.workspaceID,
                    assetID: graph.assetIDs[0], siteID: graph.siteID, locationNodeID: graph.nodes[3].id,
                    predecessorEventID: history[0].id, source: .manual,
                    physicalEpisodeID: history[0].physicalEpisodeID, continuity: .samePhysicalInstallation,
                    pathSnapshot: history[1].pathSnapshot,
                    mutationID: MutationIDV1(rawValue: id("85000000-0000-4000-8000-000000000002")),
                    occurredAt: Date(timeIntervalSince1970: 30)
                )
                XCTAssertThrowsError(try AssetPlacementHistoryV1.validate(history + [branch]), hostileID)
            case "STALE_PREDECESSOR":
                let stale = try AssetPlacementEventV1(
                    id: id("85000000-0000-4000-8000-000000000003"), workspaceID: graph.workspaceID,
                    assetID: graph.assetIDs[0], siteID: graph.siteID, locationNodeID: nil,
                    predecessorEventID: id("85000000-0000-4000-8000-000000000099"), source: .manual,
                    physicalEpisodeID: graph.placements[0].physicalEpisodeID, continuity: .samePhysicalInstallation,
                    pathSnapshot: graph.placements[0].pathSnapshot,
                    mutationID: MutationIDV1(rawValue: id("85000000-0000-4000-8000-000000000004")),
                    occurredAt: Date(timeIntervalSince1970: 31)
                )
                XCTAssertThrowsError(try AssetPlacementHistoryV1.validate([stale]), hostileID)
            case "REUSED_ID_CHANGED_INPUT":
                let changed = try LocationNodeV1(
                    id: graph.nodes[0].id, workspaceID: graph.workspaceID, siteID: graph.siteID,
                    parentNodeID: nil, kind: .campus, label: "Changed", shortCode: nil,
                    siblingOrder: 1, state: .active, revision: 2, provenance: graph.nodes[0].provenance
                )
                XCTAssertThrowsError(try LocationHierarchyPolicyV1.validate([graph.nodes[0], changed]), hostileID)
            case "SECOND_STRUCTURAL_PARENT":
                let second = try AssetCompositionEdgeV1(
                    id: id("86000000-0000-4000-8000-000000000001"), workspaceID: graph.workspaceID,
                    parentAssetID: graph.assetIDs[0], childAssetID: graph.assetIDs[1], isActive: true, revision: 1
                )
                XCTAssertThrowsError(try AssetCompositionPolicyV1.validate(edges: [graph.edges[0], second], placementByAssetID: graph.tips), hostileID)
            case "COMPOSITION_CYCLE":
                let reverse = try AssetCompositionEdgeV1(
                    id: id("86000000-0000-4000-8000-000000000002"), workspaceID: graph.workspaceID,
                    parentAssetID: graph.assetIDs[1], childAssetID: graph.assetIDs[0], isActive: true, revision: 1
                )
                XCTAssertThrowsError(try AssetCompositionPolicyV1.validate(edges: [graph.edges[0], reverse], placementByAssetID: graph.tips), hostileID)
            case "DELETE_ACTIVE_EDGE":
                XCTAssertThrowsError(try WholeSignDeletionRule.validateLocationDeletionNoCascade(
                    deletingAssetID: graph.assetIDs[0], deletingSiteID: nil,
                    liveAssetSiteByID: Dictionary(uniqueKeysWithValues: graph.assetIDs.map { ($0, graph.siteID) }), locationNodes: graph.nodes,
                    placementEvents: graph.placements, compositionEdges: graph.edges
                ), hostileID)
            default:
                XCTFail("unhandled hostile case: \(hostileID)")
            }
        }
        XCTAssertThrowsError(try DeletionIdentityV2(typedID: "site:not-a-uuid"))
        XCTAssertThrowsError(try DeletionIdentityV2(typedID: "unknown:30000000-0000-4000-8000-000000000001"))
        XCTAssertThrowsError(try DeletionLedgerV2(entries: [
            try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(kind: .asset, id: UUID(uuidString: "30000000-0000-4000-8000-000000000002")!),
                deletedAt: Date(timeIntervalSince1970: 1)
            ),
            try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(kind: .asset, id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!),
                deletedAt: Date(timeIntervalSince1970: 1)
            ),
        ]))
        let compositionEdgeID = id("86000000-0000-4000-8000-000000000010")
        let addedEdge = try AssetCompositionEdgeV1(
            id: compositionEdgeID, workspaceID: graph.workspaceID,
            parentAssetID: graph.assetIDs[0], childAssetID: graph.assetIDs[1],
            isActive: true, revision: 1
        )
        let addEvent = try AssetCompositionEventV1(
            id: id("86000000-0000-4000-8000-000000000011"),
            workspaceID: graph.workspaceID, edge: addedEdge,
            predecessorEventID: nil, action: .add,
            mutationID: MutationIDV1(rawValue: id("86000000-0000-4000-8000-000000000012")),
            occurredAt: Date(timeIntervalSince1970: 50)
        )
        let removedEdge = try AssetCompositionEdgeV1(
            id: compositionEdgeID, workspaceID: graph.workspaceID,
            parentAssetID: graph.assetIDs[0], childAssetID: graph.assetIDs[1],
            isActive: false, revision: 2
        )
        let removeEvent = try AssetCompositionEventV1(
            id: id("86000000-0000-4000-8000-000000000013"),
            workspaceID: graph.workspaceID, edge: removedEdge,
            predecessorEventID: addEvent.id, action: .remove,
            mutationID: MutationIDV1(rawValue: id("86000000-0000-4000-8000-000000000014")),
            occurredAt: Date(timeIntervalSince1970: 51)
        )
        XCTAssertNoThrow(try AssetCompositionHistoryV1.validate(
            [addEvent, removeEvent], currentEdge: removedEdge
        ))
        let reversedInitialEdge = try AssetCompositionEdgeV1(
            id: compositionEdgeID, workspaceID: graph.workspaceID,
            parentAssetID: graph.assetIDs[0], childAssetID: graph.assetIDs[1],
            isActive: false, revision: 2
        )
        let reversedInitialAdd = try AssetCompositionEventV1(
            id: id("86000000-0000-4000-8000-000000000018"),
            workspaceID: graph.workspaceID, edge: reversedInitialEdge,
            predecessorEventID: addEvent.id, action: .semanticReversal,
            mutationID: MutationIDV1(rawValue: id("86000000-0000-4000-8000-000000000019")),
            occurredAt: Date(timeIntervalSince1970: 51)
        )
        XCTAssertNoThrow(try AssetCompositionHistoryV1.validate(
            [addEvent, reversedInitialAdd], currentEdge: reversedInitialEdge
        ))
        XCTAssertThrowsError(try AssetCompositionHistoryV1.validate(
            [removeEvent], currentEdge: removedEdge
        ))
        XCTAssertThrowsError(try AssetCompositionEventV1(
            id: LocationContractValidationV1.zero,
            workspaceID: graph.workspaceID, edge: addedEdge,
            predecessorEventID: nil, action: .add,
            mutationID: MutationIDV1(rawValue: id("86000000-0000-4000-8000-000000000015")),
            occurredAt: Date(timeIntervalSince1970: 52)
        ))
        XCTAssertThrowsError(try AssetCompositionChangePlanV1(
            operationID: id("86000000-0000-4000-8000-000000000016"),
            mutationID: addEvent.mutationID, workspaceID: graph.workspaceID,
            expectedRevision: expected, event: addEvent,
            currentPlacementByAssetID: graph.tips,
            resultingActiveEdges: []
        ))
        XCTAssertThrowsError(try AssetPlacementPreviewBasisV1(
            workspaceID: graph.workspaceID, expectedRevision: expected,
            assetID: graph.assetIDs[0], currentPlacement: nil,
            proposedSiteID: graph.siteID, proposedLocationNodeID: nil,
            proposedPath: try LocationPathSnapshotV1(
                siteID: graph.siteID, siteDisplay: "North Campus", nodes: []
            ),
            source: .migratedBaseline,
            reviewedContinuity: .samePhysicalInstallation
        ))
        let currentPlacement = try XCTUnwrap(graph.tips[graph.assetIDs[0]])
        XCTAssertThrowsError(try AssetPlacementPreviewBasisV1(
            workspaceID: graph.workspaceID, expectedRevision: expected,
            assetID: graph.assetIDs[0], currentPlacement: currentPlacement,
            proposedSiteID: currentPlacement.siteID,
            proposedLocationNodeID: currentPlacement.locationNodeID,
            proposedPath: currentPlacement.pathSnapshot,
            source: .hierarchyRebase,
            reviewedContinuity: .samePhysicalInstallation
        ))
        XCTAssertThrowsError(try LocationHierarchyChangePlanV1(
            operationID: id("86000000-0000-4000-8000-000000000017"),
            workspaceID: graph.workspaceID, expectedRevision: expected,
            beforeNodes: [graph.nodes[3]], afterNodes: [graph.nodes[3]],
            affectedAssetIDs: [], assetPathChanges: [],
            immutablePlacementReferencedNodeIDs: [graph.nodes[3].id],
            consumerImpact: try LocationHierarchyConsumerImpactV1(
                planIDs: [], referenceIDs: [], openRoundIDs: [],
                scheduleIDs: [], reportConsumerIDs: []
            ),
            assetBindingsChange: false, operationContinuityDisposition: nil,
            continuityByAssetID: [:]
        ))
    }

    func testV9_LocationHierarchyPlacementCompositionI01InterruptionMatrixPreservesRestartAuthority() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(try strings(corpus, "interruptionPoints"), [
            "PLAN_PREPARED", "JOURNAL_PREPARED", "DATABASE_COMMITTED", "RECEIPT_COMMITTED", "CLEANUP_STARTED",
        ])
        let restoration = try strings(corpus, "restoreMatrix")
        XCTAssertEqual(restoration, [
            "BACKUP_RESTORE", "CLONE", "FORK", "JOURNAL_REPLAY", "INTERRUPTED_RESTART", "FORWARD_FIX", "ERASE_ALL",
        ])
        XCTAssertEqual(Set(restoration).count, restoration.count)
        XCTAssertTrue(restoration.contains("ERASE_ALL"))
        XCTAssertTrue(restoration.contains("INTERRUPTED_RESTART"))
        let graph = try makeGraph()
        let eventData = try LocationPersistenceCodecV1.encode(graph.placements[0])
        for boundary in try strings(corpus, "interruptionPoints") {
            XCTAssertEqual(
                try LocationPersistenceCodecV1.decode(AssetPlacementEventV1.self, from: eventData),
                graph.placements[0], boundary
            )
        }
        XCTAssertEqual(try LocationPersistenceCodecV1.encode(graph.placements[0]), eventData)
        var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: eventData) as? [String: Any])
        changed["id"] = "50000000-0000-4000-8000-000000000099"
        let changedData = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])
        XCTAssertThrowsError(try LocationPersistenceCodecV1.decode(AssetPlacementEventV1.self, from: changedData))
    }

    func testV9_LocationHierarchyPlacementCompositionR01FrozenHistorySurvivesRestoreAndEraseIsGenerationScoped() throws {
        let corpus = try loadCorpus()
        let placements = try array(corpus, "placementHistory").compactMap { $0 as? [String: Any] }
        XCTAssertEqual(placements.first?["kind"] as? String, "MIGRATED_BASELINE")
        XCTAssertNil(placements.first?["predecessorID"] as? String)
        XCTAssertEqual(placements[1]["predecessorID"] as? String, placements[0]["eventID"] as? String)
        XCTAssertEqual(placements[3]["predecessorID"] as? String, placements[2]["eventID"] as? String)
        let composition = try array(corpus, "compositionHistory").compactMap { $0 as? [String: Any] }
        XCTAssertEqual(composition.map { $0["state"] as? String }, ["ACTIVE", "RETIRED"])
        XCTAssertEqual(Set(composition.compactMap { $0["edgeID"] as? String }).count, 1)
        XCTAssertEqual(Set(composition.compactMap { $0["eventID"] as? String }).count, 2)
        XCTAssertEqual(
            composition[1]["predecessorID"] as? String,
            composition[0]["eventID"] as? String
        )
        let graph = try makeGraph()
        let historicSubjectPlacement = try XCTUnwrap(graph.tips[graph.assetIDs[0]])
        let currentPath = try LocationPathSnapshotV1(
            siteID: graph.siteID, siteDisplay: "North Campus",
            nodes: try historicSubjectPlacement.pathSnapshot.nodes.enumerated().map { index, node in
                try LocationPathComponentV1(
                    nodeID: node.nodeID, kind: node.kind,
                    label: index == historicSubjectPlacement.pathSnapshot.nodes.count - 1
                        ? "Electrical Room A" : node.label,
                    shortCode: node.shortCode,
                    revision: index == historicSubjectPlacement.pathSnapshot.nodes.count - 1
                        ? node.revision + 1 : node.revision
                )
            }
        )
        let frozen = try CompletedLocationCompositionSnapshotV1.build(
            workspaceID: graph.workspaceID, assetID: graph.assetIDs[0],
            currentLocationPath: currentPath,
            currentPlacementByAssetID: graph.tips,
            activeCompositionEdges: graph.edges.filter(\.isActive),
            frozenAtRevision: 4
        )
        XCTAssertNotEqual(frozen.locationPath, historicSubjectPlacement.pathSnapshot)
        let frozenData = try LocationPersistenceCodecV1.encode(frozen)
        XCTAssertEqual(try LocationPersistenceCodecV1.decode(CompletedLocationCompositionSnapshotV1.self, from: frozenData), frozen)
        let locationRows = try graph.placements.map {
            V5BackupLocationRecordV1(
                id: $0.id, canonicalData: try LocationPersistenceCodecV1.encode($0)
            )
        }
        let nodeRows = try graph.nodes.map {
            V5BackupLocationRecordV1(
                id: $0.id, canonicalData: try LocationPersistenceCodecV1.encode($0)
            )
        }
        let edgeRows = try graph.edges.map {
            V5BackupLocationRecordV1(
                id: $0.id, canonicalData: try LocationPersistenceCodecV1.encode($0)
            )
        }
        let compositionEvents = try graph.edges.enumerated().map { index, edge in
            try AssetCompositionEventV1(
                id: id(String(format: "61000000-0000-4000-8000-%012d", index + 1)),
                workspaceID: graph.workspaceID, edge: edge, predecessorEventID: nil,
                action: edge.isActive ? .add : .remove,
                mutationID: MutationIDV1(rawValue: id(String(format: "87000000-0000-4000-8000-%012d", index + 1))),
                occurredAt: Date(timeIntervalSince1970: 40 + Double(index))
            )
        }
        let compositionEventRows = try compositionEvents.map {
            V5BackupLocationRecordV1(
                id: $0.id, canonicalData: try LocationPersistenceCodecV1.encode($0)
            )
        }
        let migrationReceipt = try LocationMigrationReceiptV1(
            workspaceID: graph.workspaceID,
            sourceGenerationID: id("70000000-0000-4000-8000-000000000001"),
            candidateGenerationID: id("70000000-0000-4000-8000-000000000002"),
            sourceSiteCount: 1, sourceAssetCount: graph.assetIDs.count,
            bindings: graph.placements.filter { $0.source == .migratedBaseline }.map {
                LocationMigratedBaselineBindingV1(
                    assetID: $0.assetID, siteID: $0.siteID,
                    placementEventID: $0.id, physicalEpisodeID: $0.physicalEpisodeID
                )
            }.sorted()
        )
        let migrationRows = [V5BackupLocationRecordV1(
            id: migrationReceipt.candidateGenerationID,
            canonicalData: try LocationPersistenceCodecV1.encode(migrationReceipt)
        )]
        XCTAssertNoThrow(try LocationMigrationIntegrityV1.validate(
            receipt: migrationReceipt,
            placementEvents: graph.placements,
            knownAssetIDs: Set(graph.assetIDs),
            liveAssetSiteByID: Dictionary(uniqueKeysWithValues: graph.assetIDs.map { ($0, graph.siteID) })
        ))
        XCTAssertThrowsError(try LocationMigrationIntegrityV1.validate(
            receipt: migrationReceipt,
            placementEvents: Array(graph.placements.dropFirst()),
            knownAssetIDs: Set(graph.assetIDs),
            liveAssetSiteByID: Dictionary(uniqueKeysWithValues: graph.assetIDs.map { ($0, graph.siteID) })
        ))
        XCTAssertThrowsError(try LocationMigrationIntegrityV1.validate(
            receipt: migrationReceipt,
            placementEvents: graph.placements,
            knownAssetIDs: [graph.assetIDs[0]],
            liveAssetSiteByID: [graph.assetIDs[0]: graph.siteID]
        ))
        // DTO Codable and checkpoint semantic encoding are tested here. Full
        // package validation is covered by the backup validator suite because
        // a hierarchy-event receipt requires its durable writer receipt.
        let hierarchyRows = [V5BackupLocationRecordV1(
            id: id("62000000-0000-4000-8000-000000000001"),
            canonicalData: Data("hierarchy-plan-dto".utf8),
            secondaryCanonicalData: Data("hierarchy-receipt-dto".utf8)
        )]
        let records5 = V4BackupRecordsV1(
            assetCompositionEdges: edgeRows,
            assetCompositionEvents: compositionEventRows,
            assetPlacementEvents: locationRows,
            assets: graph.assetIDs.map {
                V4BackupAssetDTO(
                    id: $0, schemaVersion: 1, siteID: graph.siteID,
                    packID: "illuminated_sign", packSchemaVersion: 1,
                    packContentVersion: 1, label: $0.uuidString,
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: 1)
                )
            },
            deletionLedger: .empty, evidenceFiles: [], issues: [],
            locationHierarchyEvents: hierarchyRows,
            locationMigrationReceipts: migrationRows,
            locationNodes: nodeRows,
            packets: [],
            recordsSchemaVersion: 5, reports: [],
            sites: [V4BackupSiteDTO(
                id: graph.siteID, schemaVersion: 1, label: "North Campus",
                address: nil, timeZoneID: nil,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            )], workflowRecords: []
        )
        let directData = try JSONEncoder().encode(records5)
        XCTAssertEqual(try JSONDecoder().decode(V4BackupRecordsV1.self, from: directData), records5)
        let semanticA = try BackupCanonicalEncoderV1().encodeSemanticRecords(records5)
        let semanticB = try BackupCanonicalEncoderV1().encodeSemanticRecords(records5)
        XCTAssertEqual(semanticA, semanticB)
        let posture = try dictionary(corpus, "releaseAbsence")
        for key in ["nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceCredit", "releaseCredit", "phase10PollingDuringParallelExecution"] {
            XCTAssertEqual(posture[key] as? Bool, false, key)
        }
        XCTAssertEqual(posture["requiresAcceptedS10_6Reconciliation"] as? Bool, true)
    }

    private struct Graph {
        let workspaceID: WorkspaceID
        let siteID: UUID
        let assetIDs: [UUID]
        let nodes: [LocationNodeV1]
        let placements: [AssetPlacementEventV1]
        let tips: [UUID: AssetPlacementEventV1]
        let edges: [AssetCompositionEdgeV1]
    }

    private func makeGraph() throws -> Graph {
        let workspaceID = WorkspaceID(rawValue: id("11111111-1111-4111-8111-111111111111"))
        let siteID = id("20000000-0000-4000-8000-000000000001")
        let assetIDs = [id("40000000-0000-4000-8000-000000000001"), id("40000000-0000-4000-8000-000000000002")]
        let nodeIDs = (1...4).map { id(String(format: "30000000-0000-4000-8000-%012d", $0)) }
        let kinds: [LocationKindV1] = [.campus, .building, .level, .area]
        let labels = ["North Campus", "Plant 1", "Level 2", "Electrical Room"]
        let provenance = try LocationMutationProvenanceV1(
            mutationID: MutationIDV1(rawValue: id("80000000-0000-4000-8000-000000000001")),
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        let nodes = try nodeIDs.indices.map { index in
            try LocationNodeV1(
                id: nodeIDs[index], workspaceID: workspaceID, siteID: siteID,
                parentNodeID: index == 0 ? nil : nodeIDs[index - 1], kind: kinds[index],
                label: labels[index], shortCode: nil, siblingOrder: 0,
                state: .active, revision: 1, provenance: provenance
            )
        }
        let sitePath = try LocationPathSnapshotV1(siteID: siteID, siteDisplay: "North Campus", nodes: [])
        let nodePath = try LocationPathSnapshotV1(
            siteID: siteID, siteDisplay: "North Campus",
            nodes: try nodes.map {
                try LocationPathComponentV1(nodeID: $0.id, kind: $0.kind, label: $0.label, shortCode: $0.shortCode, revision: $0.revision)
            }
        )
        var placements: [AssetPlacementEventV1] = []
        for (index, assetID) in assetIDs.enumerated() {
            let baselineID = id(String(format: "50000000-0000-4000-8000-%012d", index * 2 + 1))
            let episode = try PhysicalPlacementEpisodeIDV1(rawValue: id(String(format: "90000000-0000-4000-8000-%012d", index + 1)))
            placements.append(try AssetPlacementEventV1(
                id: baselineID, workspaceID: workspaceID, assetID: assetID, siteID: siteID,
                locationNodeID: nil, predecessorEventID: nil, source: .migratedBaseline,
                physicalEpisodeID: episode, continuity: .samePhysicalInstallation,
                pathSnapshot: sitePath,
                mutationID: MutationIDV1(rawValue: id(String(format: "81000000-0000-4000-8000-%012d", index * 2 + 1))),
                occurredAt: Date(timeIntervalSince1970: 10 + Double(index))
            ))
            placements.append(try AssetPlacementEventV1(
                id: id(String(format: "50000000-0000-4000-8000-%012d", index * 2 + 2)),
                workspaceID: workspaceID, assetID: assetID, siteID: siteID,
                locationNodeID: nodeIDs[3], predecessorEventID: baselineID, source: .manual,
                physicalEpisodeID: episode, continuity: .samePhysicalInstallation,
                pathSnapshot: nodePath,
                mutationID: MutationIDV1(rawValue: id(String(format: "81000000-0000-4000-8000-%012d", index * 2 + 2))),
                occurredAt: Date(timeIntervalSince1970: 20 + Double(index))
            ))
        }
        let tips = Dictionary(uniqueKeysWithValues: assetIDs.map { assetID in
            let history = placements.filter { $0.assetID == assetID }
            let referenced = Set(history.compactMap(\.predecessorEventID))
            return (assetID, history.first { !referenced.contains($0.id) }!)
        })
        let edges = [
            try AssetCompositionEdgeV1(
                id: id("60000000-0000-4000-8000-000000000001"), workspaceID: workspaceID,
                parentAssetID: assetIDs[0], childAssetID: assetIDs[1], isActive: true, revision: 1
            ),
            try AssetCompositionEdgeV1(
                id: id("60000000-0000-4000-8000-000000000002"), workspaceID: workspaceID,
                parentAssetID: assetIDs[0], childAssetID: assetIDs[1], isActive: false, revision: 2
            ),
        ]
        return Graph(workspaceID: workspaceID, siteID: siteID, assetIDs: assetIDs, nodes: nodes, placements: placements, tips: tips, edges: edges)
    }

    private func id(_ value: String) -> UUID { UUID(uuidString: value)! }

    private func loadCorpus() throws -> [String: Any] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "V21P03C35LocationPlacementCompositionCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Location"
        ))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func dictionary(_ value: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(value[key] as? [String: Any])
    }

    private func array(_ value: [String: Any], _ key: String) throws -> [Any] {
        try XCTUnwrap(value[key] as? [Any])
    }

    private func strings(_ value: [String: Any], _ key: String) throws -> [String] {
        try XCTUnwrap(value[key] as? [String])
    }

    private func deletionCase(_ id: String, in corpus: [String: Any]) throws -> [String: Any] {
        let rows = try array(corpus, "deletionMatrix").compactMap { $0 as? [String: Any] }
        return try XCTUnwrap(rows.first { $0["id"] as? String == id })
    }
}

extension V9_LocationHierarchyPlacementCompositionTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferencePackLifecycleV1.stagingPersistence, "DERIVED_ONLY")
        XCTAssertFalse(FieldReferencePackLifecycleV1.currentProjectionPersistent)
        XCTAssertEqual(FieldReferencePackLifecycleV1.persistentFamilies.count, 2)
    }
}

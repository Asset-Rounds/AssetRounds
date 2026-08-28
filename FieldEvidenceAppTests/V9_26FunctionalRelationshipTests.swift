import Foundation
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_26FunctionalRelationshipTests: XCTestCase {
    func testV23P03C41GoldenDirectionSymmetryAndFrozenSnapshot() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture()

        XCTAssertEqual(
            Set(FunctionalRelationshipDirectionV1.allCases), [.directed, .undirected]
        )
        XCTAssertEqual(
            Set(FunctionalRelationshipSymmetryV1.allCases), [.asymmetric, .symmetric]
        )
        XCTAssertEqual(fixture.descriptor.direction, .directed)
        XCTAssertEqual(fixture.descriptor.symmetry, .asymmetric)
        XCTAssertEqual(fixture.descriptor.sitePolicy, .sameSiteRequired)
        XCTAssertEqual(fixture.descriptor.workspacePolicy, .sameWorkspaceRequired)
        XCTAssertEqual(fixture.descriptor.minimumCardinalityBoundaries, [.finalization, .readiness])

        try fixture.descriptor.validate(
            sourceCatalog: fixture.sourceCatalog, targetCatalog: fixture.targetCatalog
        )
        let projection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added],
            descriptors: [fixture.descriptor]
        )
        XCTAssertEqual(projection.readiness, .ready)
        XCTAssertEqual(projection.currentRelationships.map(\.relationshipID), [fixture.relationshipID])
        XCTAssertEqual(projection.currentRelationships.first?.action, .added)
        try projection.validate()

        let snapshot = try CompletedFunctionalRelationshipSnapshotV1(
            snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_900),
            workspaceID: fixture.workspaceID,
            capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            descriptorReleases: [fixture.descriptor],
            relationships: [fixture.added]
        )
        XCTAssertEqual(snapshot.frozenReferences.count, 1)
        XCTAssertEqual(snapshot.frozenReferences.first?.relationshipID, fixture.relationshipID)
        XCTAssertEqual(snapshot.frozenReferences.first?.descriptorReleaseID, fixture.descriptor.descriptorReleaseID)
        try snapshot.validate()
        try assertCanonicalRoundTrip(snapshot)
    }

    func testV23P03C41AlternateMinimumsAreNamedReadinessBoundaries() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(
            seed: 41_100,
            sourceMinimum: 2,
            targetMinimum: 2,
            minimumCardinalityBoundaries: [.atomicCreationBundle, .readiness, .finalization]
        )

        let mutationProjection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added],
            descriptors: [fixture.descriptor]
        )
        XCTAssertEqual(mutationProjection.readiness, .ready)
        XCTAssertTrue(mutationProjection.readinessRequirements.isEmpty)

        let readinessProjection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added],
            descriptors: [fixture.descriptor],
            boundary: .readiness
        )
        XCTAssertEqual(readinessProjection.readiness, .incomplete)
        XCTAssertEqual(readinessProjection.readinessRequirements.count, 2)
        XCTAssertTrue(readinessProjection.readinessRequirements.allSatisfy { $0.minimum == 2 && $0.actual == 1 })

        XCTAssertThrowsError(
            try FunctionalRelationshipProjectionBuilderV1.validateAtomicCreationBundle(
                workspaceID: fixture.workspaceID,
                existing: [], additions: [fixture.added], descriptors: [fixture.descriptor]
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .incomplete)
        }
    }

    func testV23P03C41HostileTopologyAndEndpointCapabilityInputsFailClosed() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_200)

        XCTAssertThrowsError(
            try FunctionalRelationshipProjectionBuilderV1.rebuild(
                workspaceID: fixture.workspaceID,
                events: try C41FunctionalRelationshipTestSupportV1.makeCycleEvents(fixture),
                descriptors: [fixture.descriptor]
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .cycleDetected)
        }

        let selfEdge = try C41FunctionalRelationshipTestSupportV1.makeEvent(
            eventID: C41FunctionalRelationshipTestSupportV1.id(41_220),
            relationshipID: C41FunctionalRelationshipTestSupportV1.id(41_221),
            workspaceID: fixture.workspaceID,
            action: .added,
            sourceAssetID: fixture.sourceAssetID,
            targetAssetID: fixture.sourceAssetID,
            descriptor: fixture.descriptor,
            actor: fixture.actor,
            predecessorEventID: nil,
            expectedRelationshipRevision: 0,
            revision: 1,
            mutationID: try C41FunctionalRelationshipTestSupportV1.mutation(41_222)
        )
        XCTAssertThrowsError(
            try FunctionalRelationshipProjectionBuilderV1.rebuild(
                workspaceID: fixture.workspaceID,
                events: [selfEdge], descriptors: [fixture.descriptor]
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .selfEdgeDenied)
        }

        let overLimit = try (0..<3).map { offset in
            try C41FunctionalRelationshipTestSupportV1.makeEvent(
                eventID: C41FunctionalRelationshipTestSupportV1.id(41_230 + offset),
                relationshipID: C41FunctionalRelationshipTestSupportV1.id(41_240 + offset),
                workspaceID: fixture.workspaceID,
                action: .added,
                sourceAssetID: fixture.sourceAssetID,
                targetAssetID: C41FunctionalRelationshipTestSupportV1.id(41_250 + offset),
                descriptor: fixture.descriptor,
                actor: fixture.actor,
                predecessorEventID: nil,
                expectedRelationshipRevision: 0,
                revision: 1,
                mutationID: try C41FunctionalRelationshipTestSupportV1.mutation(41_260 + offset)
            )
        }
        XCTAssertThrowsError(
            try FunctionalRelationshipProjectionBuilderV1.rebuild(
                workspaceID: fixture.workspaceID, events: overLimit, descriptors: [fixture.descriptor]
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .cardinalityExceeded)
        }

        let otherWorkspaceEvent = try fixture.added.rebound(
            to: C41FunctionalRelationshipTestSupportV1.workspace(41_280)
        )
        XCTAssertThrowsError(
            try FunctionalRelationshipProjectionBuilderV1.rebuild(
                workspaceID: fixture.workspaceID,
                events: [otherWorkspaceEvent], descriptors: [fixture.descriptor]
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .duplicateIdentity)
        }

        let missingCapabilityCatalog = try C41FunctionalRelationshipTestSupportV1.makeCatalog(
            packageRelease: fixture.packageRelease,
            releaseID: C41FunctionalRelationshipTestSupportV1.id(41_290),
            semanticID: "asset.zone",
            capabilityIDs: []
        )
        let incompatibleDescriptor = try FunctionalRelationshipTypeDescriptorV1(
            descriptorReleaseID: C41FunctionalRelationshipTestSupportV1.id(41_291),
            workspaceID: fixture.workspaceID,
            packageRelease: fixture.packageRelease,
            semanticID: "relationship.controls.incompatible",
            sourceCatalogRelease: fixture.sourceCatalog.reference,
            targetCatalogRelease: missingCapabilityCatalog.reference,
            sourceSemanticIDs: ["asset.controller"],
            targetSemanticIDs: ["asset.zone"],
            requiredSourceCapabilityIDs: [try AssetSemanticCapabilityIDV1("capability.control")],
            requiredTargetCapabilityIDs: [try AssetSemanticCapabilityIDV1("capability.inspect")],
            direction: .directed,
            symmetry: .asymmetric,
            sourceCardinality: try FunctionalRelationshipCardinalityV1(minimum: 0, maximum: 2),
            targetCardinality: try FunctionalRelationshipCardinalityV1(minimum: 0, maximum: 2),
            selfEdgePolicy: .forbidden,
            cyclePolicy: .forbidden,
            maximumTraversalDepth: 8,
            maximumHardEdges: 16,
            sitePolicy: .sameSiteRequired,
            minimumCardinalityBoundaries: [],
            displayNameLocalizationKey: "functional_relationship.incompatible.name",
            sourceRoleLocalizationKey: "functional_relationship.incompatible.source",
            targetRoleLocalizationKey: "functional_relationship.incompatible.target",
            releasedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            mutationID: try C41FunctionalRelationshipTestSupportV1.mutation(41_292)
        )
        XCTAssertThrowsError(
            try incompatibleDescriptor.validate(
                sourceCatalog: fixture.sourceCatalog, targetCatalog: missingCapabilityCatalog
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .incompatibleEndpoint)
        }
    }

    func testV23P03C41InterruptionRecoveryPreservesEventHistoryAndCanonicalBytes() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_300)
        let addedData = try FunctionalRelationshipCanonicalCodecV1.encode(fixture.added)
        let decodedAdded = try FunctionalRelationshipCanonicalCodecV1.decode(
            AssetFunctionalRelationshipEventV1.self, from: addedData
        )
        XCTAssertEqual(decodedAdded, fixture.added)
        XCTAssertEqual(try FunctionalRelationshipCanonicalCodecV1.encode(decodedAdded), addedData)

        var nonCanonical = addedData
        nonCanonical.append(0x0A)
        XCTAssertThrowsError(
            try FunctionalRelationshipCanonicalCodecV1.decode(
                AssetFunctionalRelationshipEventV1.self, from: nonCanonical
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .nonCanonicalData)
        }

        let endedProjection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added, fixture.ended], descriptors: [fixture.descriptor]
        )
        XCTAssertTrue(endedProjection.currentRelationships.isEmpty)

        let supersededProjection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added, fixture.superseded], descriptors: [fixture.descriptor]
        )
        XCTAssertEqual(supersededProjection.currentRelationships.first?.action, .superseded)
        XCTAssertEqual(supersededProjection.currentRelationships.first?.predecessorEventID, fixture.added.eventID)
        XCTAssertEqual(supersededProjection.currentRelationships.first?.revision, 2)

        let rebound = try fixture.added.rebound(
            to: C41FunctionalRelationshipTestSupportV1.workspace(41_301)
        )
        XCTAssertNotEqual(rebound.workspaceID, fixture.workspaceID)
        XCTAssertEqual(rebound.actor.workspaceID, rebound.workspaceID)
        XCTAssertNotEqual(rebound.eventSHA256, fixture.added.eventSHA256)
    }

    func testV23P03C41RecoveryDispositionPreviewsAreZeroWriteAndSnapshotsRejectEndedHistory() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_400)
        for change in FunctionalRelationshipEndpointChangeV1.allCases {
            let disposition: FunctionalRelationshipDispositionV1 =
                change == .crossSiteChanged ? .denied : .reviewRequired
            let preview = try FunctionalRelationshipDispositionPreviewV1(
                workspaceID: fixture.workspaceID,
                relationshipID: fixture.relationshipID,
                relationshipRevision: fixture.added.revision,
                change: change,
                disposition: disposition,
                reasonCode: "C41_PREVIEW_\(change.rawValue)"
            )
            XCTAssertFalse(preview.persistentWriteOccurred)
            XCTAssertEqual(preview.workspaceID, fixture.workspaceID)
            XCTAssertEqual(preview.relationshipID, fixture.relationshipID)
        }

        XCTAssertThrowsError(
            try CompletedFunctionalRelationshipSnapshotV1(
                snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_490),
                workspaceID: fixture.workspaceID,
                capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
                descriptorReleases: [fixture.descriptor], relationships: [fixture.ended]
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .digestMismatch)
        }
    }

    func testV23P03C41PortableCorpusAndProvisionalFlagsRemainClosed() throws {
        let url = C41FunctionalRelationshipTestSupportV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/FunctionalRelationships/V21P03C41FunctionalRelationshipCorpusV1.json"
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(root["schema"] as? String, "V21P03C41FunctionalRelationshipCorpusV1")
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertEqual(root["cardID"] as? String, "V23-P03-C41")
        XCTAssertEqual(root["synthetic"] as? Bool, true)
        XCTAssertEqual(root["containsCustomerData"] as? Bool, false)
        XCTAssertEqual(root["containsSecrets"] as? Bool, false)

        let persistence = try XCTUnwrap(root["persistence"] as? [String: Any])
        XCTAssertEqual(persistence["schemaRelease"] as? String, "PERSISTENT_SCHEMA_V12_FUNCTIONAL_RELATIONSHIPS")
        XCTAssertEqual(persistence["predecessorSchemaVersion"] as? Int, 11)
        XCTAssertEqual(persistence["recordsCatalog"] as? String, "RECORDS11")
        XCTAssertEqual(persistence["canonicalWriter"] as? String, "V23-P02-C01")

        XCTAssertEqual(
            root["requiredContractNames"] as? [String],
            [
                "FunctionalRelationshipTypeDescriptorV1",
                "AssetFunctionalRelationshipEventV1",
                "CurrentFunctionalRelationshipProjectionV1",
                "FunctionalRelationshipDispositionPreviewV1",
                "CompletedFunctionalRelationshipSnapshotV1",
            ]
        )
        let flags = try XCTUnwrap(root["provisionalFlags"] as? [String: Any])
        for key in ["nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit"] {
            XCTAssertEqual(flags[key] as? Bool, false, key)
        }
        XCTAssertEqual(flags["requiresAcceptedS10_6Reconciliation"] as? Bool, true)

        let hostileCases = try XCTUnwrap(root["hostileCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(hostileCases.count, 10)
        XCTAssertTrue(hostileCases.allSatisfy { $0["expectedDisposition"] as? String == "FAIL_CLOSED" })
        let interruptionCases = try XCTUnwrap(root["interruptionCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(interruptionCases.count, 7)
        XCTAssertTrue(interruptionCases.allSatisfy { $0["expectedDisposition"] as? String == "RETRY_IDEMPOTENT_NO_PARTIAL_ACTIVATION" })
        let recoveryCases = try XCTUnwrap(root["recoveryCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(recoveryCases.count, 8)
        XCTAssertTrue(recoveryCases.allSatisfy { $0["expectedDisposition"] as? String == "RECOVER_EFFECT_RECEIPT_AND_HISTORY" })
    }

    private func assertCanonicalRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try FunctionalRelationshipCanonicalCodecV1.encode(value)
        let decoded = try FunctionalRelationshipCanonicalCodecV1.decode(T.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try FunctionalRelationshipCanonicalCodecV1.encode(decoded), data)
    }
}

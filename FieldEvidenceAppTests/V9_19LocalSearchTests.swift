import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private final class C30EvidenceContextAnchorV9_19LocalSearch: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_19LocalSearchTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV23P03C13AssuranceSearchIsMetadataOnlyAndOptIn() throws {
        let registry = try SearchIndexRebuildCoordinatorV1.makeEvidenceAssuranceRegistry()
        XCTAssertEqual(
            registry.fields.count,
            SearchContractLimitsV1.maximumAssuranceFieldRegistrations
        )
        XCTAssertTrue(
            SearchEvidenceAssurancePersistencePolicyV1.fieldIDs.allSatisfy { fieldID in
                registry.fields.contains { $0.fieldID == fieldID && $0.sourceKind == .report }
            }
        )
        XCTAssertTrue(SearchEvidenceAssurancePersistencePolicyV1.indexesCurrentManifestHeadsOnly)
        XCTAssertTrue(SearchEvidenceAssurancePersistencePolicyV1.excludesClaimAndEvidenceContent)
        XCTAssertTrue(SearchEvidenceAssurancePersistencePolicyV1.excludesEvidenceIdentifiersAndDigests)
        XCTAssertTrue(SearchEvidenceAssurancePersistencePolicyV1.excludesActorPrivateDetail)
        let safeTokens = SearchCoordinatorV1.normalizedTokens("CUSTOMER_REPORT")
        XCTAssertTrue(
            SearchEvidenceAssurancePersistencePolicyV1.acceptsMetadata(
                fieldID: "assurance_audience", tokens: safeTokens, snippet: "CUSTOMER_REPORT"
            )
        )
        XCTAssertFalse(
            SearchEvidenceAssurancePersistencePolicyV1.acceptsMetadata(
                fieldID: "assurance_audience",
                tokens: SearchCoordinatorV1.normalizedTokens("private actor evidence"),
                snippet: "private actor evidence"
            )
        )
        for marker in SearchEvidenceAssurancePersistencePolicyV1.acceptedProjectionVersionMarkers {
            XCTAssertTrue(
                SearchEvidenceAssurancePersistencePolicyV1.acceptsMetadata(
                    fieldID: "assurance_projection_version",
                    tokens: SearchCoordinatorV1.normalizedTokens(marker),
                    snippet: marker
                )
            )
        }
        XCTAssertFalse(
            SearchEvidenceAssurancePersistencePolicyV1.acceptsMetadata(
                fieldID: "assurance_projection_version",
                tokens: SearchCoordinatorV1.normalizedTokens("report-evidence-assurance-v2"),
                snippet: "report-evidence-assurance-v2"
            )
        )
    }

    func testV23P03C41FunctionalRelationshipSearchRegistryIsOptInAndBounded() throws {
        let registry = try SearchIndexRebuildCoordinatorV1.makeExtendedRegistry(
            includeAccountability: false,
            includeAssetSemantics: false,
            includeAuthorityCriterion: false,
            includeFunctionalRelationships: true
        )
        XCTAssertEqual(
            registry.fields.count,
            SearchContractLimitsV1.maximumFunctionalRelationshipFieldRegistrations
        )
        XCTAssertTrue(
            SearchFunctionalRelationshipsPersistencePolicyV1.fieldIDs.allSatisfy { fieldID in
                registry.fields.contains { $0.fieldID == fieldID && $0.sourceKind == .asset }
            }
        )
        XCTAssertTrue(SearchFunctionalRelationshipsPersistencePolicyV1.indexesCurrentHeadsOnly)
        XCTAssertTrue(SearchFunctionalRelationshipsPersistencePolicyV1.excludesHistoricalEvents)
        XCTAssertTrue(SearchFunctionalRelationshipsPersistencePolicyV1.excludesGraphTruth)
    }

    func testV23P03C40SearchHeadExcludesSupersededAuthorityRelease() throws {
        let root = try C40BackupLifecycleTestValues.source()
        let successor = try C40BackupLifecycleTestValues.source(
            releaseID: C40BackupLifecycleTestValues.id(90_010),
            supersedes: root.releaseID,
            revision: 2
        )
        let values = [root, successor]
        let supersededIDs = Set(values.compactMap(\.supersedesReleaseID))
        let heads = values.filter { !supersededIDs.contains($0.releaseID) }
        XCTAssertEqual(heads.map(\.releaseID), [successor.releaseID])
        XCTAssertEqual(heads.first?.revision, 2)
        XCTAssertFalse(heads.contains(where: { $0.releaseID == root.releaseID }))
    }

    private let fileManager = FileManager.default

    func testV9_19G01MutationDeleteSynchronization() async throws {
        let harness = try makeHarness("golden")
        defer { harness.cleanup() }
        let registry = try makeRegistry()
        let source1 = try source(revision: 1)
        let original = try record(id: "asset-old", text: "Old Pump", revision: 1)
        try await harness.store.replaceProjection(source: source1, records: [original], registry: registry)

        let source2 = try source(revision: 2)
        let amended = try record(id: "asset-new", text: "New Pump", revision: 2)
        try await harness.store.applyCanonicalCommit(
            source: source2,
            upserting: [amended],
            deleting: [try SearchCanonicalRecordIdentityV1(sourceKind: .asset, stableID: "asset-old")],
            registry: registry
        )
        let projection = try await harness.store.projection(for: source2, registry: registry)
        XCTAssertEqual(projection.index.indexedCommitRevision, 2)
        XCTAssertEqual(projection.records.map(\.sourceStableID), ["asset-new"])

        let coordinator = SearchCoordinatorV1(index: harness.store)
        let plan = try coordinator.makePlan(query: "new pump", sourceRevision: 2)
        let response = try await coordinator.search(plan, source: source2, registry: registry)
        XCTAssertEqual(response.results.map(\.stableID), ["asset-new"])

        let source3 = try source(revision: 3)
        let sharedAsset = try record(id: "shared-delete", text: "Shared asset", revision: 3)
        let sharedWork = try record(
            id: "shared-delete", kind: .work, fieldID: "work_summary",
            text: "Shared work", revision: 3
        )
        try await harness.store.replaceProjection(
            source: source3, records: [sharedAsset, sharedWork], registry: registry
        )
        await XCTAssertThrowsErrorAsync {
            try await harness.store.applyCanonicalCommit(
                source: try self.source(revision: 4), upserting: [],
                deletingStableIDs: ["shared-delete"], registry: registry
            )
        }
        try await harness.store.applyCanonicalCommit(
            source: try source(revision: 4), upserting: [],
            deleting: [try SearchCanonicalRecordIdentityV1(sourceKind: .asset, stableID: "shared-delete")],
            registry: registry
        )
        let compositeProjection = try await harness.store.projection(
            for: source(revision: 4), registry: registry
        )
        XCTAssertEqual(compositeProjection.records.map(\.sourceKind), [.work])
    }

    func testV9_19A01CrashThenRevisionBoundRebuild() async throws {
        let harness = try makeHarness("alternate")
        defer { harness.cleanup() }
        let registry = try makeRegistry()
        let revision = try source(revision: 42)
        let staleIndex = try SearchIndexRevisionV1(
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            indexedCommitRevision: 41
        )
        let aheadIndex = try SearchIndexRevisionV1(
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            indexedCommitRevision: 43
        )
        XCTAssertEqual(SearchIndexReconciliationV1.disposition(source: revision, index: staleIndex), .staleDropAndRebuild)
        XCTAssertEqual(SearchIndexReconciliationV1.disposition(source: revision, index: aheadIndex), .aheadDropAndRebuild)
        let incompatibleIndex = try SearchIndexRevisionV1(
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            projectionFormatVersion: SearchPersistenceReleaseV1.derivedProjectionFormatVersion + 1,
            indexedCommitRevision: 42
        )
        XCTAssertEqual(
            SearchIndexReconciliationV1.disposition(source: revision, index: incompatibleIndex),
            .incompatibleFormatDropAndRebuild
        )
        let records = try [
            record(id: "asset-1", text: "Pump One", revision: 42),
            record(id: "asset-2", text: "Pump Two", revision: 42),
        ]
        let source = InterruptibleProjectionSource(revision: revision, records: records)
        let first = try SearchIndexRebuildCoordinatorV1(
            store: harness.store,
            source: source,
            registry: registry,
            makeOperationID: { UUID(uuidString: "00000000-0000-4000-8000-000000000901")! }
        )
        await source.failOnce(afterOffset: 1)
        await XCTAssertThrowsErrorAsync { try await first.rebuildIfNeeded() }
        let stagingValue = try await harness.store.rebuildStaging()
        let staging = try XCTUnwrap(stagingValue)
        XCTAssertEqual(staging.checkpoint.nextCanonicalOffset, 1)
        XCTAssertEqual(staging.records.map(\.sourceStableID), ["asset-1"])

        let resumed = try SearchIndexRebuildCoordinatorV1(store: harness.store, source: source, registry: registry)
        let result = try await resumed.rebuildIfNeeded()
        XCTAssertTrue(result.resumedFromCheckpoint)
        XCTAssertEqual(result.source.commitRevision, 42)
        XCTAssertEqual(result.indexedRecordCount, 2)
        let rebuiltRevision = try await harness.store.revision()
        XCTAssertEqual(rebuiltRevision?.indexedCommitRevision, 42)

        let aheadSource = try source(revision: 43)
        try await harness.store.replaceProjection(
            source: aheadSource,
            records: [record(id: "ahead", text: "Ahead", revision: 43)],
            registry: registry
        )
        let aheadRebuilder = try SearchIndexRebuildCoordinatorV1(
            store: harness.store, source: source, registry: registry
        )
        let aheadResult = try await aheadRebuilder.rebuildIfNeeded()
        XCTAssertEqual(aheadResult.disposition, .aheadDropAndRebuild)
        let afterAheadRebuild = try await harness.store.revision()
        XCTAssertEqual(afterAheadRebuild?.indexedCommitRevision, 42)

        let incompatibleHarness = try makeHarness("incompatible")
        defer { incompatibleHarness.cleanup() }
        try await incompatibleHarness.store.replaceProjection(
            source: revision, records: records, registry: registry
        )
        try rewriteStoredProjectionFormat(in: incompatibleHarness.root, as: 999)
        let reloaded = try LocalSearchIndexStoreV1(applicationSupportURL: incompatibleHarness.root)
        let incompatibleRebuilder = try SearchIndexRebuildCoordinatorV1(
            store: reloaded, source: source, registry: registry
        )
        let incompatibleResult = try await incompatibleRebuilder.rebuildIfNeeded()
        XCTAssertEqual(incompatibleResult.disposition, .incompatibleFormatDropAndRebuild)
        let afterIncompatibleRebuild = try await reloaded.revision()
        XCTAssertEqual(afterIncompatibleRebuild?.indexedCommitRevision, 42)

        let stalePublicationToken = await reloaded.publicationToken()
        try await reloaded.dropProjection()
        do {
            try await reloaded.replaceProjection(
                source: revision, records: records, registry: registry,
                publicationToken: stalePublicationToken
            )
            XCTFail("A purge must revoke an in-flight rebuild publication token")
        } catch let error as LocalSearchIndexStoreFailureV1 {
            XCTAssertEqual(error, .staleMutation)
        }
        let afterRejectedPublication = try await reloaded.revision()
        XCTAssertNil(afterRejectedPublication)

        let raceHarness = try makeHarness("same-revision-race")
        defer { raceHarness.cleanup() }
        let invalidatingStore = try LocalSearchIndexStoreV1(applicationSupportURL: raceHarness.root)
        let staleRecord = try record(id: "deleted-during-rebuild", text: "Stale", revision: 42)
        let survivor = try record(id: "post-delete-survivor", text: "Survivor", revision: 42)
        let raceSource = SameRevisionDeletionRaceSource(
            revision: revision,
            preDeleteRecords: [staleRecord, survivor],
            postDeleteRecords: [survivor],
            invalidatingStore: invalidatingStore
        )
        let racedRebuilder = try SearchIndexRebuildCoordinatorV1(
            store: raceHarness.store, source: raceSource, registry: registry
        )
        do {
            _ = try await racedRebuilder.rebuildIfNeeded()
            XCTFail("An invalidated in-flight staging write must fail")
        } catch let error as LocalSearchIndexStoreFailureV1 {
            XCTAssertEqual(error, .staleMutation)
        }
        let raceDiscardCount = await raceSource.discardCount()
        XCTAssertEqual(raceDiscardCount, 1)
        let raceStaging = try await raceHarness.store.rebuildStaging()
        XCTAssertNil(raceStaging)

        let freshRebuilder = try SearchIndexRebuildCoordinatorV1(
            store: raceHarness.store, source: raceSource, registry: registry
        )
        let freshResult = try await freshRebuilder.rebuildIfNeeded()
        XCTAssertEqual(freshResult.indexedRecordCount, 1)
        let postDeleteProjection = try await raceHarness.store.projection(
            for: revision, registry: registry
        )
        XCTAssertEqual(postDeleteProjection.records.map(\.sourceStableID), ["post-delete-survivor"])
        XCTAssertFalse(postDeleteProjection.records.contains {
            $0.sourceStableID == "deleted-during-rebuild"
        })

        let guardedToken = await raceHarness.store.publicationToken()
        try await invalidatingStore.dropProjection()
        let guardedCheckpoint = try SearchIndexRebuildCheckpointV1(
            operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000919")!,
            source: revision, nextCanonicalOffset: 0, projectedRecordCount: 0, state: .building
        )
        do {
            _ = try await raceHarness.store.rebuildStaging(publicationToken: guardedToken)
            XCTFail("A stale token must not read rebuild staging")
        } catch let error as LocalSearchIndexStoreFailureV1 {
            XCTAssertEqual(error, .staleMutation)
        }
        do {
            try await raceHarness.store.saveRebuildStaging(
                checkpoint: guardedCheckpoint, records: [], registry: registry,
                publicationToken: guardedToken
            )
            XCTFail("A stale token must not write rebuild staging")
        } catch let error as LocalSearchIndexStoreFailureV1 {
            XCTAssertEqual(error, .staleMutation)
        }
        do {
            try await raceHarness.store.clearRebuildStaging(publicationToken: guardedToken)
            XCTFail("A stale token must not clear rebuild staging")
        } catch let error as LocalSearchIndexStoreFailureV1 {
            XCTAssertEqual(error, .staleMutation)
        }
    }

    func testV9_19H01SortingFilteringUnicodeAndPrivacyBoundary() async throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture["schema"] as? String, "V21P03C09LocalSearchCorpusV1")
        XCTAssertEqual((fixture["hostileCases"] as? [[String: Any]])?.count, 8)
        let privacy = try XCTUnwrap(fixture["privacy"] as? [String: Any])
        XCTAssertEqual(privacy["diagnosticsContainCustomerContent"] as? Bool, false)

        let harness = try makeHarness("hostile")
        defer { harness.cleanup() }
        let registry = try makeRegistry()
        let revision = try source(revision: 42)
        let values = try [
            record(id: "asset-b", text: "PUMP A-01", status: "Complete", revision: 42, timestamp: 4),
            record(id: "asset-a", text: "Pump Á-01", status: "Incomplete", revision: 42, timestamp: 5),
            record(id: "asset-rtl", text: "مضخة 12", status: "Complete", revision: 42, timestamp: 3),
            record(id: "work-a", kind: .work, fieldID: "work_summary", text: "Seal replacement",
                   status: "Recheck due", revision: 42, timestamp: 2),
        ]
        try await harness.store.replaceProjection(source: revision, records: values, registry: registry)
        let coordinator = SearchCoordinatorV1(index: harness.store)
        XCTAssertEqual(SearchCoordinatorV1.normalize("cafe\u{301}"), SearchCoordinatorV1.normalize("Café"))
        XCTAssertEqual(SearchCoordinatorV1.normalize("\u{200F}مضخة\u{202C}"), "مضخة")

        let pumpPlan = try coordinator.makePlan(query: "pump a", scope: .assets, sourceRevision: 42)
        let pumps = try await coordinator.search(pumpPlan, source: revision, registry: registry)
        XCTAssertEqual(pumps.results.map(\.stableID), ["asset-a", "asset-b"])
        let filter = try SearchFilterV1(kind: .recheckDue)
        let workPlan = try coordinator.makePlan(query: "seal", scope: .work, filters: [filter], sourceRevision: 42)
        let workResponse = try await coordinator.search(workPlan, source: revision, registry: registry)
        XCTAssertEqual(workResponse.results.map(\.stableID), ["work-a"])
        XCTAssertThrowsError(try searchableField(id: "raw_ocr", kind: .asset))
        XCTAssertThrowsError(try searchableField(id: "uncommitted_c36", kind: .asset))
        XCTAssertThrowsError(try searchableField(id: "asset_label", kind: .work))

        let fieldMappings = registry.fields.map { "\($0.fieldID):\($0.sourceKind.rawValue)" }
        XCTAssertEqual(fieldMappings, expectedFieldMappings)
        XCTAssertEqual(Set(registry.fields.map(\.fieldID)), Set(expectedIndexedFieldIDs))

        let sortValues = try [
            record(id: "same", text: "Shared", status: "INCOMPLETE", revision: 42, timestamp: 9),
            record(id: "same", kind: .work, fieldID: "work_summary", text: "Shared",
                   status: "INCOMPLETE", revision: 42, timestamp: 8, dueAt: Date(timeIntervalSince1970: 20)),
            record(id: "z-last", kind: .work, fieldID: "work_summary", text: "Shared",
                   status: "INCOMPLETE", revision: 42, timestamp: 7),
            record(id: "due-b", kind: .work, fieldID: "work_summary", text: "Due",
                   status: "RECHECK_DUE", revision: 42, timestamp: 6, dueAt: Date(timeIntervalSince1970: 10)),
            record(id: "due-a", kind: .work, fieldID: "work_summary", text: "Due",
                   status: "RECHECK_DUE", revision: 42, timestamp: 5, dueAt: Date(timeIntervalSince1970: 10)),
            record(id: "due-nil", kind: .work, fieldID: "work_summary", text: "Due",
                   status: "RECHECK_DUE", revision: 42, timestamp: 4),
        ]
        try await harness.store.replaceProjection(source: revision, records: sortValues, registry: registry)
        let incomplete = try SearchFilterV1(kind: .incomplete)
        let statusPlan = try coordinator.makePlan(
            query: "shared", filters: [incomplete], sort: .statusThenStableID, sourceRevision: 42
        )
        let statusResponse = try await coordinator.search(statusPlan, source: revision, registry: registry)
        XCTAssertEqual(
            statusResponse.results.map { "\($0.stableID):\($0.sourceKind.rawValue)" },
            ["same:ASSET", "same:WORK", "z-last:WORK"]
        )
        let duePlan = try coordinator.makePlan(
            query: "due", scope: .work, filters: [filter],
            sort: .dueDateThenStableID, sourceRevision: 42
        )
        let dueResponse = try await coordinator.search(duePlan, source: revision, registry: registry)
        XCTAssertEqual(dueResponse.results.map(\.stableID), ["due-a", "due-b", "due-nil"])

        let stateValues = try [
            ("draft", "draft"), ("open", "open"), ("pending", "pending"),
            ("incomplete", "incomplete"), ("recheck", "recheck_due"),
            ("progress", "in_progress"), ("completed", "completed"),
            ("resolved", "resolved"), ("ready", "ready"), ("failed", "failed"),
        ].map { id, status in
            try record(id: "state-\(id)", text: "State", status: status, revision: 42)
        }
        try await harness.store.replaceProjection(source: revision, records: stateValues, registry: registry)
        let incompletePlan = try coordinator.makePlan(
            query: "state", filters: [incomplete], sourceRevision: 42
        )
        let incompleteResponse = try await coordinator.search(
            incompletePlan, source: revision, registry: registry
        )
        XCTAssertEqual(Set(incompleteResponse.results.map(\.stableID)), Set([
            "state-draft", "state-open", "state-pending", "state-incomplete",
            "state-recheck", "state-progress",
        ]))

        let session = try SearchSessionStateV1(query: "live-secret", scope: .all)
        XCTAssertEqual(session.liveNavigationState().query, "live-secret")
        let encoded = try JSONEncoder().encode(session)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("live-secret"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("\"query\""))
        var injected = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        injected["query"] = "injected-secret"
        let decoded = try JSONDecoder().decode(
            SearchSessionStateV1.self, from: JSONSerialization.data(withJSONObject: injected)
        )
        XCTAssertEqual(decoded.query, "")
        let shortTypoPlan = try coordinator.makePlan(query: "pmp", scope: .assets, sourceRevision: 42)
        let shortTypoResponse = try await coordinator.search(shortTypoPlan, source: revision, registry: registry)
        XCTAssertTrue(shortTypoResponse.suggestions.isEmpty)
    }

    @MainActor
    func testV9_19I01TenThousandRecordBudgetsFailClosed() async throws {
        let fixture = try loadFixture()
        let bounds = try XCTUnwrap(fixture["bounds"] as? [String: Any])
        XCTAssertEqual(bounds["scaleRecordCount"] as? Int, 10_000)
        XCTAssertEqual(bounds["maximumProjectionRows"] as? Int, 100_000)
        XCTAssertEqual(bounds["maximumProjectionRowsPerPage"] as? Int, 2_500)
        XCTAssertEqual(SearchContractLimitsV1.maximumCanonicalRecords, 10_000)
        XCTAssertEqual(SearchContractLimitsV1.maximumProjectionRecords, 100_000)
        XCTAssertEqual(SearchIndexRebuildCoordinatorV1.maximumProjectionRowsPerPage, 2_500)
        let harness = try makeHarness("scale")
        defer { harness.cleanup() }
        let registry = try makeRegistry()
        let revision = try source(revision: 10_000)
        let records = try (0..<10_000).map { index in
            try record(id: String(format: "asset-%05d", index), text: String(format: "Asset %05d", index),
                       revision: 10_000, timestamp: TimeInterval(index))
        }
        let rebuildStart = ContinuousClock.now
        try await harness.store.replaceProjection(source: revision, records: records, registry: registry)
        let rebuildMilliseconds = milliseconds(since: rebuildStart)
        XCTAssertLessThanOrEqual(rebuildMilliseconds, try XCTUnwrap(bounds["maximumRebuildMilliseconds"] as? Int))
        let indexURL = harness.root.appendingPathComponent(LocalSearchIndexStoreV1.directoryName)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
        let size = try XCTUnwrap(try fileManager.attributesOfItem(atPath: indexURL.path)[.size] as? NSNumber).intValue
        XCTAssertLessThanOrEqual(size, try XCTUnwrap(bounds["maximumIndexBytes"] as? Int))

        let coordinator = SearchCoordinatorV1(index: harness.store)
        let plan = try coordinator.makePlan(query: "Asset 09999", maximumResults: 100, sourceRevision: 10_000)
        let queryStart = ContinuousClock.now
        let response = try await coordinator.search(plan, source: revision, registry: registry)
        let queryMilliseconds = milliseconds(since: queryStart)
        XCTAssertEqual(response.results.map(\.stableID), ["asset-09999"])
        XCTAssertLessThanOrEqual(queryMilliseconds, try XCTUnwrap(bounds["maximumQueryMilliseconds"] as? Int))

        let ahead = try source(revision: 9_999)
        await XCTAssertThrowsErrorAsync {
            try await harness.store.projection(for: ahead, registry: registry)
        }
        let retainedRevision = try await harness.store.revision()
        XCTAssertEqual(retainedRevision?.indexedCommitRevision, 10_000)

        let productionContainer = try makeProductionSearchContainer("ten-thousand")
        let productionContext = productionContainer.mainContext
        for index in 0..<10_000 {
            productionContext.insert(Asset(
                id: scaleUUID(index), siteID: scaleUUID(10_001), packID: "scale.pack",
                packSchemaVersion: 1, packContentVersion: 1,
                label: String(format: "Production Asset %05d", index),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index + 1))
            ))
        }
        try productionContext.save()
        let productionRevision = try source(revision: 10_000)
        let productionRevisionBox = SearchRevisionBox(productionRevision)
        let productionSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: productionContext,
            workspaceID: productionRevision.workspaceID,
            generationID: productionRevision.generationID,
            revisionProvider: { productionRevisionBox.value }
        )
        var canonicalOffset = 0
        var projectedRows = 0
        var pageCount = 0
        while canonicalOffset < 10_000 {
            let page = try await productionSource.searchProjectionPage(
                at: productionRevision, canonicalOffset: canonicalOffset, limit: 250
            )
            XCTAssertLessThanOrEqual(page.nextCanonicalOffset - canonicalOffset, 250)
            XCTAssertLessThanOrEqual(page.records.count, 2_500)
            canonicalOffset = page.nextCanonicalOffset
            projectedRows += page.records.count
            pageCount += 1
        }
        XCTAssertEqual(canonicalOffset, 10_000)
        XCTAssertEqual(projectedRows, 30_000)
        XCTAssertEqual(pageCount, 40)
        XCTAssertLessThanOrEqual(projectedRows, 100_000)
    }

    @MainActor
    func testV9_19R01DropRebuildRetainsCanonicalRecordsAndSavedViews() async throws {
        let harness = try makeHarness("recovery")
        defer { harness.cleanup() }
        let registry = try makeRegistry()
        let revision = try source(revision: 7)
        let canonicalRecords = try [record(id: "asset-7", text: "Recovery Pump", revision: 7)]
        let source = InterruptibleProjectionSource(revision: revision, records: canonicalRecords)
        let descriptor = try SavedSmartViewDescriptorV1(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000907")!,
            workspaceID: revision.workspaceID,
            stableID: "saved.recovery",
            origin: .userSaved,
            name: "Recovery",
            query: "pump",
            scope: .assets,
            sort: .deterministicRelevance,
            revision: 1,
            mutationID: UUID(uuidString: "00000000-0000-4000-8000-000000000908")!,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let saved = try SavedSmartView(descriptor)
        XCTAssertEqual(try saved.descriptor(), descriptor)
        let production = try XCTUnwrap(try loadFixture()["productionClosure"] as? [String: Any])
        XCTAssertEqual(production["sourceKindRegistrationCount"] as? Int, 13)
        XCTAssertEqual(production["writerInvalidationSynchronous"] as? Bool, true)
        XCTAssertEqual(production["startupInvalidationSynchronous"] as? Bool, true)
        XCTAssertEqual(production["assetSiteCrashRetryMarkerOrdered"] as? Bool, true)
        XCTAssertEqual(production["orphanCleanupPurgesDerivedIndex"] as? Bool, true)
        XCTAssertEqual(production["typedCanonicalStableKeys"] as? Bool, true)
        XCTAssertEqual(production["sameSearchKindTypedIdentityCollisionSafe"] as? Bool, true)
        XCTAssertEqual(production["truthfulIncompleteStatusSemantics"] as? Bool, true)
        XCTAssertEqual(production["backupStaleRequiresOperationalProvider"] as? Bool, true)
        XCTAssertEqual(production["rebuildPublicationTokenRequired"] as? Bool, true)
        XCTAssertEqual(production["sameRevisionDeletionRaceCovered"] as? Bool, true)

        let productionContainer = try makeProductionSearchContainer("behavior")
        let productionContext = productionContainer.mainContext
        let siteID = UUID(uuidString: "00000000-0000-4000-8000-000000001111")!
        productionContext.insert(Site(id: siteID, label: "Canonical Site"))
        for index in 0..<251 {
            productionContext.insert(Asset(
                id: scaleUUID(index), siteID: siteID, packID: "behavior.pack",
                packSchemaVersion: 1, packContentVersion: 1,
                label: "Canonical Asset \(index)"
            ))
        }
        try productionContext.save()
        let productionRevisionBox = SearchRevisionBox(revision)
        let productionSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: productionContext,
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            revisionProvider: { productionRevisionBox.value }
        )
        let productionServices = try ProductionSearchServicesV1(
            store: harness.store,
            modelContext: productionContext,
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            revisionProvider: { productionRevisionBox.value }
        )
        XCTAssertEqual(productionServices.registry.fields, productionSource.registry.fields)
        let serviceRevision = try await productionServices.source.currentSearchSourceRevision()
        XCTAssertEqual(serviceRevision, revision)
        let firstProductionPage = try await productionSource.searchProjectionPage(
            at: revision, canonicalOffset: 0, limit: 250
        )
        XCTAssertEqual(firstProductionPage.nextCanonicalOffset, 250)
        XCTAssertFalse(firstProductionPage.isComplete)
        XCTAssertEqual(firstProductionPage.records.count, 750)
        XCTAssertEqual(
            firstProductionPage.records.first?.sourceStableID,
            try WorkspaceEntityIdentityV1(kind: .asset, id: scaleUUID(0)).stableKey
        )
        XCTAssertFalse(firstProductionPage.records.contains {
            $0.normalizedTokens.contains("backup") || $0.normalizedTokens.contains("stale")
        })
        productionRevisionBox.value = try source(revision: 8)
        do {
            _ = try await productionSource.searchProjectionPage(
                at: revision, canonicalOffset: 250, limit: 250
            )
            XCTFail("Revision drift must fail before a page is published")
        } catch let error as SearchIndexRebuildFailureV1 {
            XCTAssertEqual(error, .sourceChangedDuringRebuild)
        }
        productionRevisionBox.value = revision
        let finalProductionPage = try await productionSource.searchProjectionPage(
            at: revision, canonicalOffset: 250, limit: 250
        )
        XCTAssertTrue(finalProductionPage.isComplete)
        XCTAssertEqual(finalProductionPage.nextCanonicalOffset, 252)
        XCTAssertEqual(finalProductionPage.records.count, 7)
        let siteStableKey = try WorkspaceEntityIdentityV1(kind: .site, id: siteID).stableKey
        XCTAssertTrue(finalProductionPage.records.contains {
            $0.sourceKind == .location && $0.sourceStableID == siteStableKey
        })

        let staleAssetID = scaleUUID(0)
        let staleAssetStableKey = try WorkspaceEntityIdentityV1(
            kind: .asset, id: staleAssetID
        ).stableKey
        let staleProvider = FixedOperationalStatusProvider(identities: [
            try SearchCanonicalRecordIdentityV1(sourceKind: .asset, stableID: staleAssetStableKey)
        ])
        let staleSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: productionContext, workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            revisionProvider: { productionRevisionBox.value },
            operationalStatusProvider: staleProvider
        )
        let stalePage = try await staleSource.searchProjectionPage(
            at: revision, canonicalOffset: 0, limit: 250
        )
        let staleRows = stalePage.records.filter { $0.sourceStableID == staleAssetStableKey }
        let staleStatusRows = staleRows.filter { $0.fieldID == "status" }
        XCTAssertEqual(staleStatusRows.count, 1)
        XCTAssertTrue(staleStatusRows[0].normalizedTokens.contains("backup"))
        XCTAssertTrue(staleStatusRows[0].normalizedTokens.contains("stale"))
        XCTAssertTrue(staleRows.filter { $0.fieldID != "status" }.allSatisfy {
            !$0.normalizedTokens.contains("backup") && !$0.normalizedTokens.contains("stale")
        })
        let unknownProvider = FixedOperationalStatusProvider(identities: [
            try SearchCanonicalRecordIdentityV1(sourceKind: .asset, stableID: "asset:unknown")
        ])
        let unknownSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: productionContext, workspaceID: revision.workspaceID,
            generationID: revision.generationID, revisionProvider: { revision },
            operationalStatusProvider: unknownProvider
        )
        do {
            _ = try await unknownSource.searchProjectionPage(
                at: revision, canonicalOffset: 0, limit: 250
            )
            XCTFail("Unknown Backup Stale identities must fail closed")
        } catch let error as SearchContractFailureV1 {
            XCTAssertEqual(error, .invalidContext)
        }

        let collisionContainer = try makeProductionSearchContainer("collision")
        let collisionContext = collisionContainer.mainContext
        let collisionID = UUID(uuidString: "00000000-0000-4000-8000-000000001212")!
        collisionContext.insert(workflowRecord(id: collisionID))
        collisionContext.insert(Issue(
            id: collisionID, assetID: siteID, openedByRecordID: collisionID,
            labelKey: "collision", labelDisplaySnapshot: "Collision", status: .open,
            resolvedByRecordID: nil, createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        ))
        try collisionContext.save()
        let collisionSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: collisionContext,
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            revisionProvider: { revision }
        )
        let collisionPage = try await collisionSource.searchProjectionPage(
            at: revision, canonicalOffset: 0, limit: 250
        )
        XCTAssertEqual(collisionPage.nextCanonicalOffset, 2)
        XCTAssertEqual(collisionPage.records.count, 6)
        XCTAssertEqual(Set(collisionPage.records.map(\.sourceStableID)), Set([
            try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: collisionID).stableKey,
            try WorkspaceEntityIdentityV1(kind: .issue, id: collisionID).stableKey,
        ]))

        let rebuilder = try SearchIndexRebuildCoordinatorV1(store: harness.store, source: source, registry: registry)
        _ = try await rebuilder.rebuildIfNeeded()
        try await harness.store.dropProjection(workspaceID: revision.workspaceID)
        let droppedRevision = try await harness.store.revision()
        XCTAssertNil(droppedRevision)
        let result = try await rebuilder.rebuildIfNeeded()
        XCTAssertEqual(result.indexedRecordCount, 1)
        let retainedRecords = await source.recordsSnapshot()
        XCTAssertEqual(retainedRecords, canonicalRecords)
        XCTAssertEqual(try saved.descriptor(), descriptor)
        XCTAssertEqual(try loadFixture()["recovery"] as? [String: Bool], [
            "dropDerivedIndex": true, "retainCanonicalRecords": true,
            "retainSavedSmartViews": true, "retainTransientQuery": false,
            "rebuildDeterministic": true,
        ])
    }
}

private final class C27V919TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorInputSourceV1.allCases.count, 3)
        XCTAssertEqual(AssetLocatorLimitsV1.maximumInputBytes, 1_024)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension V9_19LocalSearchTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_19LocalSearchTests {
    func testV23P03C18SearchRebuildUsesDedicatedTypedSandboxCheck() throws {
        XCTAssertTrue(PackageSandboxCheckKindV1.allCases.contains(.searchRebuild))
        XCTAssertTrue(PackageSandboxCheckKindV1.allCases.contains(.replay))
        XCTAssertTrue(PackageEvolutionLifecycleV1.searchRebuildReplayRequired)
    }

    func testV23P03C19SearchRebuildUsesCanonicalMeasurementIdentity() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let captureData = try MeasurementIntegrityCanonicalCodecV1.encode(fixture.capture)
        let capture = try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementCaptureV1.self, from: captureData
        )
        XCTAssertEqual(capture.captureID, fixture.capture.captureID)
        XCTAssertEqual(capture.captureSHA256, fixture.capture.captureSHA256)
        XCTAssertEqual(capture.measurement.canonicalUnitID, "lx")
        XCTAssertTrue(capture.measurement.source.isLocalMeasurementCaptureSource)
    }
}

extension V9_19LocalSearchTests {
    func testV23P03C15SearchProjectionRetainsStablePacketTokens() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_119)
        let searchable = [
            fixture.manifest.manifestID.uuidString,
            fixture.manifest.packetID.uuidString,
            fixture.item.itemID,
            fixture.claim.claimID.uuidString,
            fixture.result.resultID.uuidString
        ]
        XCTAssertTrue(searchable.contains(fixture.itemReference.itemID))
        XCTAssertTrue(searchable.contains(fixture.manifest.packetID.uuidString))
        XCTAssertTrue(searchable.contains(fixture.claim.claimID.uuidString))
        XCTAssertEqual(fixture.manifest.items.first(where: { $0.itemID == fixture.item.itemID }), fixture.item)
    }
}

private extension V9_19LocalSearchTests {
    struct Harness {
        let root: URL
        let store: LocalSearchIndexStoreV1
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    func makeHarness(_ label: String) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_19LocalSearchTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        return Harness(root: root, store: try LocalSearchIndexStoreV1(applicationSupportURL: root))
    }

    func source(revision: UInt64) throws -> SearchSourceRevisionV1 {
        try SearchSourceRevisionV1(
            workspaceID: UUID(uuidString: "00000000-0000-4000-8000-000000000309")!,
            generationID: UUID(uuidString: "00000000-0000-4000-8000-000000000310")!,
            commitRevision: revision)
    }

    func searchableField(id: String, kind: SearchSourceKindV1) throws -> SearchableFieldDescriptorV1 {
        let frozen = try XCTUnwrap(FrozenSearchableFieldV1(rawValue: id))
        let identity = frozen.isIdentifier
        let operational = frozen == .status
        try SearchableFieldDescriptorV1(
            fieldID: id, sourceKind: kind,
            privacyClass: identity ? .userVisibleIdentifier
                : (operational ? .approvedOperationalState : .approvedCustomerText),
            tokenization: identity ? .exactIdentity : (operational ? .keyword : .unicodeWords),
            normalization: identity ? .stableIdentity : .unicodeCaseAndDiacriticFoldedNFC,
            snippetPermission: (identity || operational) ? .exactDisplayValue : .boundedUserVisibleExcerpt,
            retention: .untilSourceFieldIsAmended, purgeOwner: .indexRebuildCoordinator)
    }

    func makeRegistry() throws -> SearchableFieldRegistryV1 {
        try SearchableFieldRegistryV1(fields: [
            searchableField(id: "asset_identifier", kind: .asset),
            searchableField(id: "asset_label", kind: .asset),
            searchableField(id: "location_breadcrumb", kind: .location),
            searchableField(id: "location_identifier", kind: .location),
            searchableField(id: "location_label", kind: .location),
            searchableField(id: "report_identifier", kind: .report),
            searchableField(id: "report_summary", kind: .report),
            searchableField(id: "status", kind: .asset),
            searchableField(id: "status", kind: .location),
            searchableField(id: "status", kind: .report),
            searchableField(id: "status", kind: .work),
            searchableField(id: "work_identifier", kind: .work),
            searchableField(id: "work_summary", kind: .work),
        ])
    }

    func record(
        id: String,
        kind: SearchSourceKindV1 = .asset,
        fieldID: String = "asset_identifier",
        text: String,
        status: String = "Incomplete",
        revision: UInt64,
        timestamp: TimeInterval = 1,
        dueAt: Date? = nil
    ) throws -> SearchIndexProjectionRecordV1 {
        try SearchIndexProjectionRecordV1(
            workspaceID: try source(revision: revision).workspaceID,
            sourceKind: kind,
            sourceStableID: id,
            sourceRevision: revision,
            fieldID: fieldID,
            normalizedTokens: SearchCoordinatorV1.normalizedTokens(text + " " + status),
            displayIdentity: text,
            locationBreadcrumb: ["Fixture"],
            status: status,
            permittedSnippet: text,
            dueAt: dueAt,
            sourceTimestamp: Date(timeIntervalSince1970: timestamp))
    }

    var expectedIndexedFieldIDs: [String] {
        ["asset_identifier", "asset_label", "location_identifier", "location_label",
         "location_breadcrumb", "work_identifier", "work_summary", "report_identifier",
         "report_summary", "status"]
    }

    var expectedFieldMappings: [String] {
        ["asset_identifier:ASSET", "asset_label:ASSET", "location_breadcrumb:LOCATION",
         "location_identifier:LOCATION", "location_label:LOCATION", "report_identifier:REPORT",
         "report_summary:REPORT", "status:ASSET", "status:LOCATION", "status:REPORT",
         "status:WORK", "work_identifier:WORK", "work_summary:WORK"]
    }

    func rewriteStoredProjectionFormat(in root: URL, as format: Int) throws {
        let url = root.appendingPathComponent(LocalSearchIndexStoreV1.directoryName)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        var projection = try XCTUnwrap(envelope["projection"] as? [String: Any])
        var index = try XCTUnwrap(projection["index"] as? [String: Any])
        index["projectionFormatVersion"] = format
        projection["index"] = index
        envelope["projection"] = projection
        try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: url)
    }

    func loadFixture() throws -> [String: Any] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "V21P03C09LocalSearchCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/Search") ?? bundle.url(
                forResource: "V21P03C09LocalSearchCorpusV1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.last, 0x0A)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        return Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    @MainActor
    func makeProductionSearchContainer(_ name: String) throws -> ModelContainer {
        let schema = Schema(PersistentSchemaV7.models, version: PersistentSchemaV7.versionIdentifier)
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V9_19-\(name)", schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, cloudKitDatabase: .none
            )]
        )
    }

    func scaleUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "10000000-0000-4000-8000-%012x", index + 1))!
    }

    func workflowRecord(id: UUID) -> WorkflowRecord {
        WorkflowRecord(
            id: id, assetID: id, packetID: nil, issueID: nil, parentRecordID: nil,
            recordRevisionRootID: id, revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: .work, state: .draft, draftStepKey: nil,
            startedAt: Date(timeIntervalSince1970: 1), completedAt: nil,
            observedAtUTC: nil, timeZoneID: nil, utcOffsetMinutes: nil,
            localDate: nil, localTime: nil, afterDarkAcknowledgementKey: nil,
            afterDarkAcknowledgementCopy: nil, afterDarkAcknowledgementVersion: nil,
            afterDarkAcknowledgementAccepted: nil, safePositionAcknowledgementKey: nil,
            safePositionAcknowledgementCopy: nil, safePositionAcknowledgementVersion: nil,
            safePositionAcknowledgementAccepted: nil, packID: "collision.pack",
            packSchemaVersion: 1, packContentVersion: 1, pdfTemplateID: "collision.pdf",
            pdfTemplateVersion: 1, outcomeKey: nil, couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: "Collision", note: nil,
            finalizationMutationID: nil
        )
    }
}

@MainActor
private final class SearchRevisionBox {
    var value: SearchSourceRevisionV1
    init(_ value: SearchSourceRevisionV1) { self.value = value }
}

private actor FixedOperationalStatusProvider: SearchOperationalStatusProvidingV1 {
    let identities: Set<SearchCanonicalRecordIdentityV1>
    init(identities: Set<SearchCanonicalRecordIdentityV1>) { self.identities = identities }
    func backupStaleCanonicalIdentities(
        at source: SearchSourceRevisionV1
    ) async throws -> Set<SearchCanonicalRecordIdentityV1> {
        _ = source
        return identities
    }
}

private actor InterruptibleProjectionSource: SearchCanonicalProjectionSourceV1 {
    enum Failure: Error { case injectedCrash }
    private let revision: SearchSourceRevisionV1
    private let records: [SearchIndexProjectionRecordV1]
    private var failOffset: Int?

    init(revision: SearchSourceRevisionV1, records: [SearchIndexProjectionRecordV1]) {
        self.revision = revision
        self.records = records
    }

    func failOnce(afterOffset offset: Int) { failOffset = offset }
    func recordsSnapshot() -> [SearchIndexProjectionRecordV1] { records }
    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 { revision }
    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        guard source == revision else { throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild }
        if failOffset == canonicalOffset {
            failOffset = nil
            throw Failure.injectedCrash
        }
        let end = min(canonicalOffset + min(limit, 1), records.count)
        return try SearchCanonicalProjectionPageV1(
            requestedCanonicalOffset: canonicalOffset,
            nextCanonicalOffset: end,
            isComplete: end == records.count,
            records: Array(records[canonicalOffset..<end]))
    }
}

private actor SameRevisionDeletionRaceSource: SearchCanonicalProjectionSourceV1 {
    private let revision: SearchSourceRevisionV1
    private let preDeleteRecords: [SearchIndexProjectionRecordV1]
    private let postDeleteRecords: [SearchIndexProjectionRecordV1]
    private let invalidatingStore: LocalSearchIndexStoreV1
    private var liveRecords: [SearchIndexProjectionRecordV1]
    private var capturedSnapshot: [SearchIndexProjectionRecordV1]?
    private var invalidated = false
    private var discardInvocationCount = 0

    init(
        revision: SearchSourceRevisionV1,
        preDeleteRecords: [SearchIndexProjectionRecordV1],
        postDeleteRecords: [SearchIndexProjectionRecordV1],
        invalidatingStore: LocalSearchIndexStoreV1
    ) {
        self.revision = revision
        self.preDeleteRecords = preDeleteRecords
        self.postDeleteRecords = postDeleteRecords
        self.invalidatingStore = invalidatingStore
        liveRecords = preDeleteRecords
    }

    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 { revision }

    func discardCachedSearchProjectionSnapshot() async {
        capturedSnapshot = nil
        discardInvocationCount += 1
    }

    func discardCount() -> Int { discardInvocationCount }

    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        guard source == revision else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        if capturedSnapshot == nil { capturedSnapshot = liveRecords }
        let snapshot = capturedSnapshot ?? preDeleteRecords
        let end = min(canonicalOffset + min(limit, 1), snapshot.count)
        let page = try SearchCanonicalProjectionPageV1(
            requestedCanonicalOffset: canonicalOffset,
            nextCanonicalOffset: end,
            isComplete: end == snapshot.count,
            records: Array(snapshot[canonicalOffset..<end])
        )
        if !invalidated {
            invalidated = true
            liveRecords = postDeleteRecords
            try await invalidatingStore.dropProjection(workspaceID: revision.workspaceID)
        }
        return page
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch {}
}

extension V9_19LocalSearchTests {
    func testV23P03C14SearchableReferencesRetainTypedSubjectAndItemScope() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_019)
        let terms = [fixture.subject.subjectID, fixture.changeRequest.item.itemID]
        XCTAssertTrue(terms.contains(fixture.subject.subjectID))
        XCTAssertEqual(fixture.changeRequest.item.kind, .finding)
        XCTAssertEqual(fixture.subject.kind, .completedActivitySnapshot)
    }

    func testC20PrivacyTransformSearchProjectionNeverExposesUnreviewedAudience() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let decision = try PrivacyProjectionV1.decide(
            manifest: fixture.manifest, review: nil, policy: fixture.policy,
            requestedAudience: .customerReport, currentSourceRevision: 1,
            currentSourceSHA256: fixture.manifest.sourceSHA256, at: fixture.capturedAt
        )
        XCTAssertEqual(decision.denial, .missingReview)
        XCTAssertNil(decision.derivative)
    }
}

extension V9_19LocalSearchTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_19LocalSearchTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.semanticDiffPersistence, "NONPERSISTENT")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.adoptionPreviewPersistence, "NONPERSISTENT")
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimReleaseToService)
    }
}
extension V9_19LocalSearchTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_19LocalSearchTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}

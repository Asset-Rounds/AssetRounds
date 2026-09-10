import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P02C05GlobalizedSearchTests: XCTestCase {
    private let fileManager = FileManager.default

    func testFixtureBytesAndGlobalizedNormalizationCoverRequiredCases() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(
            fixture.provenance.purpose,
            "Deterministic local-search normalization diagnostics; not a shipping localization catalog or language-release claim."
        )
        XCTAssertEqual(fixture.shippingCases.map(\.languageTag), [
            "en", "es", "zh-Hans", "zh-Hant", "vi", "ko",
        ])
        XCTAssertEqual(
            fixture.provenance.turkish,
            "Hostile Turkish dotted and dotless I coverage only; Turkish is not a required shipping locale."
        )
        XCTAssertEqual(
            fixture.provenance.arabic,
            "Hostile Arabic meaning-preservation coverage only; Arabic is not a shipping language claim."
        )

        for item in fixture.shippingCases + fixture.hostileCases {
            XCTAssertEqual(
                KernelCanonicalHashV1.sha256(Data(item.sourceText.utf8)),
                item.sourceSHA256,
                item.id
            )
            XCTAssertEqual(item.sourceText.utf8.count, item.sourceUTF8ByteCount, item.id)

            let derived = try GlobalizedSearchNormalizationServiceV1
                .normalizeProjectionText(item.sourceText)
            XCTAssertEqual(derived.schemaVersion, 1, item.id)
            XCTAssertEqual(derived.algorithmVersion, .v1, item.id)
            XCTAssertEqual(derived.normalizedText, item.expectedNormalizedText, item.id)
            XCTAssertEqual(derived.tokens, item.expectedTokens, item.id)
            XCTAssertEqual(derived.cjkRunCount, item.expectedCJKRunCount, item.id)
            XCTAssertEqual(derived.cjkChunkCount, item.expectedCJKChunkCount, item.id)
        }

        let decomposedHangul = try XCTUnwrap(
            fixture.shippingCases.first { $0.id == "korean-canonical-composition" }
        )
        XCTAssertNotEqual(
            Array(decomposedHangul.sourceText.utf8),
            Array(decomposedHangul.expectedNormalizedText.utf8)
        )
        XCTAssertEqual(
            try GlobalizedSearchNormalizationServiceV1.normalizeQuery(decomposedHangul.query)
                .normalizedText,
            decomposedHangul.expectedNormalizedText.components(separatedBy: " ").first
        )

        let turkishDotless = try XCTUnwrap(
            fixture.hostileCases.first { $0.id == "turkish-dotless-i" }
        )
        XCTAssertNotEqual(
            try GlobalizedSearchNormalizationServiceV1.normalizeQuery(turkishDotless.query),
            try GlobalizedSearchNormalizationServiceV1.normalizeQuery(
                try XCTUnwrap(turkishDotless.nonMatchingQuery)
            )
        )
        let dotted = try XCTUnwrap(fixture.hostileCases.first { $0.id == "turkish-dotted-i" })
        let rootI = try XCTUnwrap(fixture.hostileCases.first { $0.id == "turkish-root-i" })
        XCTAssertEqual(
            try GlobalizedSearchNormalizationServiceV1.normalizeProjectionText(dotted.sourceText),
            try GlobalizedSearchNormalizationServiceV1.normalizeProjectionText(rootI.sourceText)
        )

        let arabicFlag = try XCTUnwrap(fixture.hostileCases.first { $0.id == "arabic-flag" })
        XCTAssertNotEqual(
            try GlobalizedSearchNormalizationServiceV1.normalizeQuery(arabicFlag.query),
            try GlobalizedSearchNormalizationServiceV1.normalizeQuery(
                try XCTUnwrap(arabicFlag.nonMatchingQuery)
            )
        )
    }

    func testDerivedNormalizationKeepsForeignSourceBytesAndRejectsTamperedReceipts() throws {
        let decomposed = "Cafe\u{301}"
        let composed = "Café"
        XCTAssertNotEqual(Array(decomposed.utf8), Array(composed.utf8))
        let normalization = try GlobalizedSearchNormalizationServiceV1
            .normalizeProjectionText(decomposed)
        XCTAssertEqual(normalization.normalizedText, "cafe")
        XCTAssertEqual(Array(normalization.normalizedText.utf8), Array("cafe".utf8))

        let encoded = try JSONEncoder().encode(normalization)
        var tampered = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        tampered["tokens"] = ["tampered"]
        let tokenTamper = try JSONSerialization.data(
            withJSONObject: tampered,
            options: [.sortedKeys]
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(GlobalizedSearchDerivedNormalizationV1.self, from: tokenTamper)
        )

        tampered = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        tampered["algorithmVersion"] = 99
        let versionTamper = try JSONSerialization.data(
            withJSONObject: tampered,
            options: [.sortedKeys]
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(GlobalizedSearchDerivedNormalizationV1.self, from: versionTamper)
        )
    }
    func testCJKChunksRemainBoundedAndCoordinatorMatchesOnlyContiguousCrossChunkPhrases() async throws {
        let measurement = try loadFixture().cjkMeasurement
        XCTAssertEqual(
            KernelCanonicalHashV1.sha256(Data(measurement.sourceText.utf8)),
            measurement.sourceSHA256
        )
        XCTAssertEqual(measurement.sourceText.utf8.count, measurement.sourceUTF8ByteCount)

        let normalization = try GlobalizedSearchNormalizationServiceV1
            .normalizeProjectionText(measurement.sourceText)
        XCTAssertEqual(normalization.cjkRunCount, measurement.expectedCJKRunCount)
        XCTAssertEqual(normalization.cjkChunkCount, measurement.expectedCJKChunkCount)
        XCTAssertFalse(normalization.tokens.contains { $0.contains(measurement.crossChunkQuery) })
        XCTAssertTrue(normalization.tokens.allSatisfy {
            $0.utf8.count <= SearchContractLimitsV1.maximumNormalizedTokenBytes
        })

        let sourceRevision = try source(revision: 4)
        let record = try searchRecord(
            stableID: measurement.stableID,
            displayIdentity: measurement.sourceText,
            source: sourceRevision,
            normalization: normalization
        )
        let harness = try makeHarness("cjk-cross-chunk")
        defer { harness.cleanup() }
        let registry = try registry()
        try await harness.store.replaceProjection(
            source: sourceRevision,
            records: [record],
            registry: registry
        )
        let coordinator = SearchCoordinatorV1(index: harness.store)
        let crossChunk = try await search(
            measurement.crossChunkQuery,
            coordinator: coordinator,
            source: sourceRevision,
            registry: registry
        )
        XCTAssertEqual(crossChunk.results.map(\.stableID), [measurement.stableID])

        let nonContiguous = try await search(
            measurement.nonMatchingQuery,
            coordinator: coordinator,
            source: sourceRevision,
            registry: registry
        )
        XCTAssertTrue(nonContiguous.results.isEmpty)
        XCTAssertThrowsError(
            try GlobalizedSearchNormalizationServiceV1.normalizeQuery(measurement.sourceText)
        ) { error in
            XCTAssertEqual(error as? SearchContractFailureV1, .limitExceeded)
        }
    }

    func testCurrentDerivedRowsSearchThroughCoordinatorWithRawStableTieBreakers() async throws {
        let fixture = try loadFixture()
        let sourceRevision = try source(revision: 5)
        let registry = try registry()
        let records = try fixture.shippingCases.map {
            try record(from: $0, source: sourceRevision)
        } + fixture.hostileCases.map {
            try record(from: $0, source: sourceRevision)
        }
        let harness = try makeHarness("coordinator")
        defer { harness.cleanup() }
        let source = FixtureProjectionSource(revision: sourceRevision, records: records)
        let rebuilder = try SearchIndexRebuildCoordinatorV1(
            store: harness.store,
            source: source,
            registry: registry,
            privateSystemDiscoveryIndex: nil,
            privateSystemDiscoverySource: nil
        )
        let rebuilt = try await rebuilder.rebuildIfNeeded()
        XCTAssertEqual(rebuilt.indexedRecordCount, records.count)

        let coordinator = SearchCoordinatorV1(
            index: harness.store,
            displayLocaleIdentifier: "en_US"
        )
        for item in fixture.shippingCases {
            let response = try await search(
                item.query,
                coordinator: coordinator,
                source: sourceRevision,
                registry: registry
            )
            XCTAssertEqual(response.results.map(\.stableID), [item.stableID], item.id)
        }
        for item in fixture.hostileCases where item.id != "turkish-root-i" && item.id != "turkish-dotted-i" {
            let response = try await search(
                item.query,
                coordinator: coordinator,
                source: sourceRevision,
                registry: registry
            )
            XCTAssertEqual(response.results.map(\.stableID), [item.stableID], item.id)
            let nonMatch = try await search(
                try XCTUnwrap(item.nonMatchingQuery),
                coordinator: coordinator,
                source: sourceRevision,
                registry: registry
            )
            XCTAssertFalse(nonMatch.results.contains { $0.stableID == item.stableID }, item.id)
        }

        let izmir = try await search(
            "izmir",
            coordinator: coordinator,
            source: sourceRevision,
            registry: registry
        )
        XCTAssertEqual(izmir.results.map(\.stableID), [
            "asset-tr-dotted-izmir", "asset-tr-root-izmir",
        ])

        let tieRows = try tieRecords(source: sourceRevision, fixture: fixture.stableTie)
        try await harness.store.replaceProjection(
            source: sourceRevision,
            records: records + tieRows,
            registry: registry
        )
        let tied = try await search(
            fixture.stableTie.displayIdentity,
            coordinator: coordinator,
            source: sourceRevision,
            registry: registry,
            sort: .localizedDisplayIdentity
        )
        XCTAssertEqual(
            tied.results.map(\.stableID).filter { fixture.stableTie.stableIDs.contains($0) },
            fixture.stableTie.expectedOrder
        )

        let rawID = fixture.shippingCases[0].stableID
        let rawIDResponse = try await search(
            rawID,
            coordinator: coordinator,
            source: sourceRevision,
            registry: registry
        )
        XCTAssertEqual(rawIDResponse.results.map(\.stableID), [rawID])
        XCTAssertEqual(rawIDResponse.results.first?.rankingKey.tier, .exactStableOrDisplayIdentity)

        let englishTypo = try await search(
            "caff",
            coordinator: coordinator,
            source: sourceRevision,
            registry: registry
        )
        XCTAssertEqual(englishTypo.suggestions.map(\.suggestedToken), ["cafe"])
        XCTAssertEqual(englishTypo.suggestions.first?.sourceStableID, rawID)
        XCTAssertEqual(englishTypo.suggestions.first?.editDistance, 1)
    }

    func testLocalizedDisplaySortUsesInjectedSwedishDiagnosticCollation() async throws {
        let sourceRevision = try source(revision: 10)
        let registry = try registry()
        let aland = try searchRecord(
            stableID: "asset-locale-aland",
            displayIdentity: "Åland",
            source: sourceRevision,
            normalization: try GlobalizedSearchNormalizationServiceV1
                .normalizeProjectionText("Åland")
        )
        let zulu = try searchRecord(
            stableID: "asset-locale-zulu",
            displayIdentity: "Zulu",
            source: sourceRevision,
            normalization: try GlobalizedSearchNormalizationServiceV1
                .normalizeProjectionText("Zulu")
        )
        let harness = try makeHarness("locale-sort")
        defer { harness.cleanup() }
        try await harness.store.replaceProjection(
            source: sourceRevision,
            records: [aland, zulu],
            registry: registry
        )
        let filter = try SearchFilterV1(kind: .incomplete)
        let enCoordinator = SearchCoordinatorV1(
            index: harness.store,
            displayLocaleIdentifier: "en_US"
        )
        let swedishCoordinator = SearchCoordinatorV1(
            index: harness.store,
            displayLocaleIdentifier: "sv_SE"
        )
        let enPlan = try enCoordinator.makePlan(
            query: "",
            filters: [filter],
            sort: .localizedDisplayIdentity,
            sourceRevision: sourceRevision.commitRevision
        )
        let swedishPlan = try swedishCoordinator.makePlan(
            query: "",
            filters: [filter],
            sort: .localizedDisplayIdentity,
            sourceRevision: sourceRevision.commitRevision
        )
        let enResponse = try await enCoordinator.search(
            enPlan,
            source: sourceRevision,
            registry: registry
        )
        let swedishResponse = try await swedishCoordinator.search(
            swedishPlan,
            source: sourceRevision,
            registry: registry
        )
        XCTAssertEqual(enResponse.results.map(\.stableID), ["asset-locale-aland", "asset-locale-zulu"])
        XCTAssertEqual(swedishResponse.results.map(\.stableID), ["asset-locale-zulu", "asset-locale-aland"])
    }
    func testFreshLegacyArabicRowsUseTheLegacyQueryPolicyWithoutChangingRawIDs() async throws {
        let sourceRevision = try source(revision: 6)
        let registry = try registry()
        let legacyStableID = "asset-legacy-arabic-flag"
        let legacyDisplay = "عَلَم مخزون"
        let legacy = try legacySearchRecord(
            stableID: legacyStableID,
            displayIdentity: legacyDisplay,
            source: sourceRevision
        )
        let differentVowels = try XCTUnwrap(
            try loadFixture().hostileCases.first { $0.id == "arabic-knowledge" }
        )
        let current = try record(from: differentVowels, source: sourceRevision)
        let harness = try makeHarness("fresh-legacy")
        defer { harness.cleanup() }
        try await harness.store.replaceProjection(
            source: sourceRevision,
            records: [legacy, current],
            registry: registry
        )

        let coordinator = SearchCoordinatorV1(index: harness.store)
        let response = try await search(
            "عَلَم",
            coordinator: coordinator,
            source: sourceRevision,
            registry: registry
        )
        XCTAssertEqual(response.results.map(\.stableID), [legacyStableID])
        XCTAssertEqual(response.results.first?.displayIdentity, legacyDisplay)
        XCTAssertEqual(response.results.first?.rankingKey.tier, .normalizedExactToken)
    }
    func testPersistedFormatOneProjectionAndStagingAreDiscardedBeforeRecoveryPublication() async throws {
        let fixture = try loadFixture()
        let sourceRevision = try source(revision: 7)
        let registry = try registry()
        let records = try fixture.shippingCases.prefix(2).map {
            try record(from: $0, source: sourceRevision)
        }
        let harness = try makeHarness("format-one")
        defer { harness.cleanup() }
        try await harness.store.replaceProjection(
            source: sourceRevision,
            records: records,
            registry: registry
        )
        let checkpoint = try SearchIndexRebuildCheckpointV1(
            operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000c05")!,
            source: sourceRevision,
            nextCanonicalOffset: 0,
            projectedRecordCount: 0,
            state: .building
        )
        try await harness.store.saveRebuildStaging(
            checkpoint: checkpoint,
            records: [],
            registry: registry
        )
        try rewritePersistedFormats(in: harness.root, as: 1)

        let reopened = try LocalSearchIndexStoreV1(applicationSupportURL: harness.root)
        let legacyRevision = try await reopened.revision()
        let legacyStaging = try await reopened.rebuildStaging()
        XCTAssertEqual(legacyRevision?.projectionFormatVersion, 1)
        XCTAssertEqual(legacyStaging?.checkpoint.projectionFormatVersion, 1)
        do {
            _ = try await reopened.projection(for: sourceRevision, registry: registry)
            XCTFail("The stale V1 projection must be rejected before recovery.")
        } catch {
            XCTAssertEqual(error as? SearchContractFailureV1, .staleIndex)
        }

        let source = FixtureProjectionSource(revision: sourceRevision, records: records)
        let rebuilder = try SearchIndexRebuildCoordinatorV1(
            store: reopened,
            source: source,
            registry: registry,
            privateSystemDiscoveryIndex: nil,
            privateSystemDiscoverySource: nil
        )
        let result = try await rebuilder.rebuildIfNeeded()
        XCTAssertEqual(result.disposition, .incompatibleFormatDropAndRebuild)
        XCTAssertEqual(result.indexedRecordCount, records.count)
        let recoveredProjection = try await reopened.projection(
            for: sourceRevision,
            registry: registry
        )
        let recoveredRawSources = await source.rawSources()
        let currentRevision = try await reopened.revision()
        let currentStaging = try await reopened.rebuildStaging()
        XCTAssertEqual(
            recoveredProjection.records.map(\.sourceStableID),
            records.sorted().map(\.sourceStableID)
        )
        XCTAssertTrue(recoveredProjection.records.allSatisfy { $0.globalizedNormalization != nil })
        XCTAssertEqual(
            currentRevision?.projectionFormatVersion,
            SearchPersistenceReleaseV1.derivedProjectionFormatVersion
        )
        XCTAssertNil(currentStaging)
        XCTAssertEqual(recoveredRawSources, records.map(\.displayIdentity))
    }

    func testFailedRebuildKeepsCanonicalSourceAndPublishesOnlyAfterRecovery() async throws {
        let fixture = try loadFixture()
        let sourceRevision = try source(revision: 8)
        let registry = try registry()
        let records = try fixture.shippingCases.prefix(2).map {
            try record(from: $0, source: sourceRevision)
        }
        let harness = try makeHarness("recovery")
        defer { harness.cleanup() }
        let source = FixtureProjectionSource(
            revision: sourceRevision,
            records: records,
            failOnceAtOffset: 1
        )
        let rebuilder = try SearchIndexRebuildCoordinatorV1(
            store: harness.store,
            source: source,
            registry: registry,
            privateSystemDiscoveryIndex: nil,
            privateSystemDiscoverySource: nil
        )

        do {
            _ = try await rebuilder.rebuildIfNeeded()
            XCTFail("The injected canonical-page failure must stop publication.")
        } catch {
            XCTAssertEqual(error as? FixtureProjectionSource.Failure, .injected)
        }
        let failedRevision = try await harness.store.revision()
        let persistedStaging = try await harness.store.rebuildStaging()
        let staging = try XCTUnwrap(persistedStaging)
        let sourcesAfterFailure = await source.rawSources()
        XCTAssertNil(failedRevision)
        XCTAssertEqual(staging.records.map(\.sourceStableID), [records[0].sourceStableID])
        XCTAssertEqual(sourcesAfterFailure, records.map(\.displayIdentity))

        let recovered = try await rebuilder.rebuildIfNeeded()
        let recoveredProjection = try await harness.store.projection(
            for: sourceRevision,
            registry: registry
        )
        let stagingAfterRecovery = try await harness.store.rebuildStaging()
        let sourcesAfterRecovery = await source.rawSources()
        XCTAssertEqual(recovered.indexedRecordCount, records.count)
        XCTAssertTrue(recovered.resumedFromCheckpoint)
        XCTAssertEqual(
            recoveredProjection.records.map(\.sourceStableID),
            records.sorted().map(\.sourceStableID)
        )
        XCTAssertNil(stagingAfterRecovery)
        XCTAssertEqual(sourcesAfterRecovery, records.map(\.displayIdentity))
    }

    func testEraseRemovesOnlyDerivedSearchBytes() async throws {
        let fixture = try loadFixture()
        let sourceRevision = try source(revision: 9)
        let registry = try registry()
        let records = try fixture.shippingCases.prefix(2).map {
            try record(from: $0, source: sourceRevision)
        }
        let harness = try makeHarness("erase")
        defer { harness.cleanup() }
        try await harness.store.replaceProjection(
            source: sourceRevision,
            records: records,
            registry: registry
        )
        let canonicalFixtureURL = fixtureURL()
        let canonicalFixtureBytes = try Data(contentsOf: canonicalFixtureURL)

        try LocalSearchIndexStoreV1.synchronouslyEraseAll(applicationSupportURL: harness.root)
        let indexFile = harness.root
            .appendingPathComponent(LocalSearchIndexStoreV1.directoryName, isDirectory: true)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName, isDirectory: false)
        XCTAssertFalse(fileManager.fileExists(atPath: indexFile.path))
        XCTAssertEqual(try Data(contentsOf: canonicalFixtureURL), canonicalFixtureBytes)
        let reopened = try LocalSearchIndexStoreV1(applicationSupportURL: harness.root)
        let erasedRevision = try await reopened.revision()
        XCTAssertNil(erasedRevision)
    }
}

private extension V30P02C05GlobalizedSearchTests {
    struct Fixture: Decodable {
        let schemaVersion: Int
        let provenance: Provenance
        let shippingCases: [Case]
        let hostileCases: [Case]
        let cjkMeasurement: CJKMeasurement
        let stableTie: StableTie
    }

    struct Provenance: Decodable {
        let purpose: String
        let turkish: String
        let arabic: String
        let canonical: String
    }

    struct Case: Decodable {
        let id: String
        let languageTag: String
        let stableID: String
        let sourceText: String
        let sourceUTF8ByteCount: Int
        let sourceSHA256: String
        let query: String
        let nonMatchingQuery: String?
        let expectedNormalizedText: String
        let expectedTokens: [String]
        let expectedCJKRunCount: Int
        let expectedCJKChunkCount: Int
    }

    struct CJKMeasurement: Decodable {
        let sourceText: String
        let sourceUTF8ByteCount: Int
        let sourceSHA256: String
        let stableID: String
        let crossChunkQuery: String
        let nonMatchingQuery: String
        let expectedCJKRunCount: Int
        let expectedCJKChunkCount: Int
    }

    struct StableTie: Decodable {
        let displayIdentity: String
        let stableIDs: [String]
        let expectedOrder: [String]
    }

    struct Harness {
        let root: URL
        let store: LocalSearchIndexStoreV1

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/Search/globalized-search-cases-v1.json")
    }

    func loadFixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL()))
    }

    func makeHarness(_ label: String) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V30P02C05-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        return Harness(
            root: root,
            store: try LocalSearchIndexStoreV1(applicationSupportURL: root)
        )
    }

    func source(revision: UInt64) throws -> SearchSourceRevisionV1 {
        try SearchSourceRevisionV1(
            workspaceID: UUID(uuidString: "00000000-0000-4000-8000-000000000c05")!,
            generationID: UUID(uuidString: "00000000-0000-4000-8000-000000000c06")!,
            commitRevision: revision
        )
    }

    func registry() throws -> SearchableFieldRegistryV1 {
        try SearchableFieldRegistryV1(fields: [
            try field("asset_identifier", .asset),
            try field("asset_label", .asset),
            try field("location_breadcrumb", .location),
            try field("location_identifier", .location),
            try field("location_label", .location),
            try field("report_identifier", .report),
            try field("report_summary", .report),
            try field("status", .asset),
            try field("status", .location),
            try field("status", .report),
            try field("status", .work),
            try field("work_identifier", .work),
            try field("work_summary", .work),
        ])
    }

    func field(
        _ fieldID: String,
        _ sourceKind: SearchSourceKindV1
    ) throws -> SearchableFieldDescriptorV1 {
        let frozen = try XCTUnwrap(FrozenSearchableFieldV1(rawValue: fieldID))
        let identity = frozen.isIdentifier
        let operational = frozen == .status
        return try SearchableFieldDescriptorV1(
            fieldID: fieldID,
            sourceKind: sourceKind,
            privacyClass: identity
                ? .userVisibleIdentifier
                : (operational ? .approvedOperationalState : .approvedCustomerText),
            tokenization: identity
                ? .exactIdentity
                : (operational ? .keyword : .unicodeWords),
            normalization: identity
                ? .stableIdentity
                : .unicodeCaseAndDiacriticFoldedNFC,
            snippetPermission: (identity || operational)
                ? .exactDisplayValue
                : .boundedUserVisibleExcerpt,
            retention: .untilSourceFieldIsAmended,
            purgeOwner: .indexRebuildCoordinator
        )
    }

    func record(from item: Case, source: SearchSourceRevisionV1) throws -> SearchIndexProjectionRecordV1 {
        let derived = try GlobalizedSearchNormalizationServiceV1
            .normalizeProjectionText(item.sourceText)
        return try SearchIndexProjectionRecordV1(
            workspaceID: source.workspaceID,
            sourceKind: .asset,
            sourceStableID: item.stableID,
            sourceRevision: source.commitRevision,
            fieldID: "asset_label",
            normalizedTokens: derived.tokens,
            globalizedNormalization: derived,
            displayIdentity: item.sourceText,
            locationBreadcrumb: ["Fixture"],
            status: "Incomplete",
            permittedSnippet: item.sourceText,
            sourceTimestamp: Date(timeIntervalSince1970: 1)
        )
    }

    func searchRecord(
        stableID: String,
        displayIdentity: String,
        source: SearchSourceRevisionV1,
        normalization: GlobalizedSearchDerivedNormalizationV1
    ) throws -> SearchIndexProjectionRecordV1 {
        try SearchIndexProjectionRecordV1(
            workspaceID: source.workspaceID,
            sourceKind: .asset,
            sourceStableID: stableID,
            sourceRevision: source.commitRevision,
            fieldID: "asset_label",
            normalizedTokens: normalization.tokens,
            globalizedNormalization: normalization,
            displayIdentity: displayIdentity,
            locationBreadcrumb: ["Fixture"],
            status: "Incomplete",
            permittedSnippet: displayIdentity,
            sourceTimestamp: Date(timeIntervalSince1970: 1)
        )
    }

    func legacySearchRecord(
        stableID: String,
        displayIdentity: String,
        source: SearchSourceRevisionV1
    ) throws -> SearchIndexProjectionRecordV1 {
        try SearchIndexProjectionRecordV1(
            workspaceID: source.workspaceID,
            sourceKind: .asset,
            sourceStableID: stableID,
            sourceRevision: source.commitRevision,
            fieldID: "asset_label",
            normalizedTokens: SearchCoordinatorV1.normalizedTokens(displayIdentity),
            globalizedNormalization: nil,
            displayIdentity: displayIdentity,
            locationBreadcrumb: ["Fixture"],
            status: "Incomplete",
            permittedSnippet: displayIdentity,
            sourceTimestamp: Date(timeIntervalSince1970: 1)
        )
    }

    func tieRecords(
        source: SearchSourceRevisionV1,
        fixture: StableTie
    ) throws -> [SearchIndexProjectionRecordV1] {
        let derived = try GlobalizedSearchNormalizationServiceV1
            .normalizeProjectionText(fixture.displayIdentity)
        return try fixture.stableIDs.map { stableID in
            try SearchIndexProjectionRecordV1(
                workspaceID: source.workspaceID,
                sourceKind: .asset,
                sourceStableID: stableID,
                sourceRevision: source.commitRevision,
                fieldID: "asset_label",
                normalizedTokens: derived.tokens,
                globalizedNormalization: derived,
                displayIdentity: fixture.displayIdentity,
                locationBreadcrumb: ["Fixture"],
                status: "Incomplete",
                permittedSnippet: fixture.displayIdentity,
                sourceTimestamp: Date(timeIntervalSince1970: 1)
            )
        }
    }

    func search(
        _ query: String,
        coordinator: SearchCoordinatorV1,
        source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1,
        sort: SearchSortV1 = .deterministicRelevance
    ) async throws -> SearchResponseV1 {
        let plan = try coordinator.makePlan(
            query: query,
            sort: sort,
            sourceRevision: source.commitRevision
        )
        return try await coordinator.search(plan, source: source, registry: registry)
    }

    func rewritePersistedFormats(in root: URL, as version: Int) throws {
        let url = root
            .appendingPathComponent(LocalSearchIndexStoreV1.directoryName)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
        let original = try String(contentsOf: url, encoding: .utf8)
        let current = "\"projectionFormatVersion\":2"
        let replacement = "\"projectionFormatVersion\":\(version)"
        XCTAssertEqual(
            original.components(separatedBy: current).count - 1,
            2,
            "Fixture must rewrite exactly the projection and rebuild-checkpoint format receipts."
        )
        let legacyWithoutReceipts = original.replacingOccurrences(
            of: ",\"globalizedNormalization\":\\{[^{}]*\\}",
            with: "",
            options: .regularExpression
        )
        XCTAssertEqual(
            original.components(separatedBy: "\"globalizedNormalization\":").count - 1,
            2,
            "Fixture must remove each current derived-normalization receipt."
        )
        let currentSpanishTokens = "\"normalizedTokens\":[\"de\",\"revision\",\"valvula\"]"
        let legacySpanishTokens = "\"normalizedTokens\":[\"revision\",\"de\",\"valvula\"]"
        XCTAssertEqual(
            legacyWithoutReceipts.components(separatedBy: currentSpanishTokens).count - 1,
            1,
            "Fixture must retain V1 token order after removing V30 receipts."
        )
        let rewritten = legacyWithoutReceipts
            .replacingOccurrences(of: current, with: replacement)
            .replacingOccurrences(of: currentSpanishTokens, with: legacySpanishTokens)
        try Data(rewritten.utf8).write(to: url)
    }
}

private actor FixtureProjectionSource: SearchCanonicalProjectionSourceV1 {
    enum Failure: Error, Equatable { case injected }

    private let revision: SearchSourceRevisionV1
    private let records: [SearchIndexProjectionRecordV1]
    private var failureOffset: Int?

    init(
        revision: SearchSourceRevisionV1,
        records: [SearchIndexProjectionRecordV1],
        failOnceAtOffset: Int? = nil
    ) {
        self.revision = revision
        self.records = records
        failureOffset = failOnceAtOffset
    }

    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 { revision }

    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        guard source == revision else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        if failureOffset == canonicalOffset {
            failureOffset = nil
            throw Failure.injected
        }
        let end = min(canonicalOffset + min(limit, 1), records.count)
        return try SearchCanonicalProjectionPageV1(
            requestedCanonicalOffset: canonicalOffset,
            nextCanonicalOffset: end,
            isComplete: end == records.count,
            records: Array(records[canonicalOffset..<end])
        )
    }

    func rawSources() -> [String] { records.map(\.displayIdentity) }
}

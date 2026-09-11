import Foundation
import SwiftData
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class S2PersistenceLedgerTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testLegitimatelyWrittenActiveStoreReopensWithoutRepinningItsActivationManifest() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let generationID: UUID
        let pointerBytes: Data
        let manifestBytes: Data
        let siteID = UUID(), assetID = UUID(), placementID = UUID()
        do {
            let session = try factory.openOrBootstrapCurrent()
            generationID = session.generationID
            pointerBytes = try Data(contentsOf: currentPointerURL(in: root))
            let store = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
            manifestBytes = try XCTUnwrap(store.loadManifestIfPresent(targetGenerationID: generationID)).manifest.canonicalData()
            let coordinator = try StoreSessionCoordinator(validatingSession: session)
            let writer = coordinator.workspaceWriter
            let current = try writer.currentRevision()
            let mutation = try MutationIDV1(rawValue: UUID())
            let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID,
                generationID: current.generationID, writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision, entityRevisions: [
                    .init(identity: WorkspaceEntityIdentityV1(kind: .site, id: siteID), revision: 0),
                    .init(identity: WorkspaceEntityIdentityV1(kind: .asset, id: assetID), revision: 0),
                    .init(identity: WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: placementID), revision: 0),
                ])
            let outcome = try writer.execute(.init(mutationID: mutation, expectedRevision: expected,
                command: .createFirstSign(.init(siteID: siteID,
                    newSite: .init(id: siteID, label: "Written current site", address: nil, timeZoneID: "UTC"),
                    assetID: assetID, assetLabel: "Written current asset", packID: "test.pack",
                    packSchemaVersion: 1, packContentVersion: 1,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    initialPlacementMutationID: mutation, initialPlacementEventID: placementID,
                    initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID())))))
            XCTAssertEqual(outcome.after.revision, 1)
            _ = try factory.reconcileGenerationLeasesAndPrune()
            XCTAssertEqual(try Data(contentsOf: currentPointerURL(in: root)), pointerBytes)
            XCTAssertEqual(try XCTUnwrap(store.loadManifestIfPresent(targetGenerationID: generationID)).manifest.canonicalData(), manifestBytes)
            try coordinator.invalidateAndReleaseWriter()
        }
        let reopened = try await factory.openForStartup { _ in XCTFail("Active current store must not enter migration") }
        guard case .ready(let session) = reopened else { return XCTFail("Already accepted active store must reopen") }
        XCTAssertEqual(session.generationID, generationID)
        XCTAssertEqual(session.storeSchemaRelease, .v53)
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<Site>()).map(\.id), [siteID])
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<Asset>()).map(\.id), [assetID])
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).count, 1)
        XCTAssertEqual(try Data(contentsOf: currentPointerURL(in: root)), pointerBytes)
        XCTAssertEqual(try XCTUnwrap(StoreMigrationJournalStoreV1(applicationSupportURL: root).loadManifestIfPresent(targetGenerationID: generationID)).manifest.canonicalData(), manifestBytes)
    }

    @MainActor
    func testBootstrapPersistsReleasesAndReopensTheExactGenerationLedger() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }

        let siteID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let assetID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let createdAt = Date(timeIntervalSince1970: 1_723_456_789)
        let updatedAt = Date(timeIntervalSince1970: 1_723_460_000)
        let factory = StoreGenerationFactory(applicationSupportURL: root)

        let generationID: UUID
        do {
            var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
            let opened = try XCTUnwrap(session)
            generationID = opened.generationID

            opened.modelContext.insert(
                Site(
                    id: siteID,
                    label: "North Campus",
                    address: "10 Main Street",
                    timeZoneID: "America/New_York",
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
            opened.modelContext.insert(
                Asset(
                    id: assetID,
                    siteID: siteID,
                    packID: "field.evidence.illuminated_sign.v1",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    label: "Monument Sign",
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
            try opened.modelContext.save()

            XCTAssertEqual(
                try Data(contentsOf: currentPointerURL(in: root)),
                Data("{\"generationID\":\"\(generationID.uuidString.lowercased())\",\"schemaVersion\":1}".utf8)
            )
            XCTAssertEqual(
                try Data(contentsOf: retiredPointerURL(in: root)),
                Data("{\"generationIDs\":[],\"schemaVersion\":1}".utf8)
            )
            XCTAssertTrue(
                fileManager.fileExists(
                    atPath: generationURL(generationID, in: root)
                        .appendingPathComponent("model.sqlite", isDirectory: false).path
                )
            )

            session = nil
        }

        let reopened = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, generationID)

        let sites = try reopened.modelContext.fetch(FetchDescriptor<Site>())
        let assets = try reopened.modelContext.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(assets.count, 1)

        let site = try XCTUnwrap(sites.first)
        XCTAssertEqual(site.id, siteID)
        XCTAssertEqual(site.schemaVersion, 1)
        XCTAssertEqual(site.label, "North Campus")
        XCTAssertEqual(site.address, "10 Main Street")
        XCTAssertEqual(site.timeZoneID, "America/New_York")
        XCTAssertEqual(site.createdAt, createdAt)
        XCTAssertEqual(site.updatedAt, updatedAt)

        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(asset.id, assetID)
        XCTAssertEqual(asset.schemaVersion, 1)
        XCTAssertEqual(asset.siteID, siteID)
        XCTAssertEqual(asset.packID, "field.evidence.illuminated_sign.v1")
        XCTAssertEqual(asset.packSchemaVersion, 1)
        XCTAssertEqual(asset.packContentVersion, 1)
        XCTAssertEqual(asset.label, "Monument Sign")
        XCTAssertEqual(asset.createdAt, createdAt)
        XCTAssertEqual(asset.updatedAt, updatedAt)

        XCTAssertEqual(
            try Data(contentsOf: currentPointerURL(in: root)),
            Data("{\"generationID\":\"\(generationID.uuidString.lowercased())\",\"schemaVersion\":1}".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: retiredPointerURL(in: root)),
            Data("{\"generationIDs\":[],\"schemaVersion\":1}".utf8)
        )
    }

    @MainActor
    func testInvalidGenerationLedgerFailsClosedWithoutMutationOrNewestGuessing() throws {
        struct InvalidLedgerCase {
            let name: String
            let expectedFailure: StoreGenerationFailure
            let mutate: (URL, UUID) throws -> Void
        }

        let cases: [InvalidLedgerCase] = [
            .init(name: "missing current pointer", expectedFailure: .dataPointerInvalid) { root, _ in
                try self.fileManager.removeItem(at: self.currentPointerURL(in: root))
            },
            .init(name: "missing retired pointer", expectedFailure: .dataPointerInvalid) { root, _ in
                try self.fileManager.removeItem(at: self.retiredPointerURL(in: root))
            },
            .init(name: "malformed current pointer", expectedFailure: .dataPointerInvalid) { root, _ in
                try Data("{".utf8).write(to: self.currentPointerURL(in: root), options: .atomic)
            },
            .init(name: "noncanonical current pointer", expectedFailure: .dataPointerInvalid) { root, id in
                try Data("{ \"generationID\" : \"\(id.uuidString.lowercased())\", \"schemaVersion\" : 1 }".utf8)
                    .write(to: self.currentPointerURL(in: root), options: .atomic)
            },
            .init(name: "extra current key", expectedFailure: .dataPointerInvalid) { root, id in
                try Data("{\"extra\":0,\"generationID\":\"\(id.uuidString.lowercased())\",\"schemaVersion\":1}".utf8)
                    .write(to: self.currentPointerURL(in: root), options: .atomic)
            },
            .init(name: "duplicate current key", expectedFailure: .dataPointerInvalid) { root, id in
                let value = id.uuidString.lowercased()
                try Data("{\"generationID\":\"\(value)\",\"generationID\":\"\(value)\",\"schemaVersion\":1}".utf8)
                    .write(to: self.currentPointerURL(in: root), options: .atomic)
            },
            .init(name: "unsupported current schema", expectedFailure: .dataPointerInvalid) { root, id in
                try Data("{\"generationID\":\"\(id.uuidString.lowercased())\",\"schemaVersion\":2}".utf8)
                    .write(to: self.currentPointerURL(in: root), options: .atomic)
            },
            .init(name: "malformed retired pointer", expectedFailure: .dataPointerInvalid) { root, _ in
                try Data("[]".utf8).write(to: self.retiredPointerURL(in: root), options: .atomic)
            },
            .init(name: "noncanonical retired pointer", expectedFailure: .dataPointerInvalid) { root, _ in
                try Data("{ \"generationIDs\" : [], \"schemaVersion\" : 1 }".utf8)
                    .write(to: self.retiredPointerURL(in: root), options: .atomic)
            },
            .init(name: "extra retired key", expectedFailure: .dataPointerInvalid) { root, _ in
                try Data("{\"extra\":0,\"generationIDs\":[],\"schemaVersion\":1}".utf8)
                    .write(to: self.retiredPointerURL(in: root), options: .atomic)
            },
            .init(name: "duplicate retired key", expectedFailure: .dataPointerInvalid) { root, _ in
                try Data("{\"generationIDs\":[],\"generationIDs\":[],\"schemaVersion\":1}".utf8)
                    .write(to: self.retiredPointerURL(in: root), options: .atomic)
            },
            .init(name: "unsupported retired schema", expectedFailure: .dataPointerInvalid) { root, _ in
                try Data("{\"generationIDs\":[],\"schemaVersion\":2}".utf8)
                    .write(to: self.retiredPointerURL(in: root), options: .atomic)
            },
            .init(name: "missing current generation", expectedFailure: .dataGenerationMissing) { root, id in
                try self.fileManager.removeItem(at: self.generationURL(id, in: root))
            },
            .init(name: "missing current store", expectedFailure: .dataGenerationMissing) { root, id in
                try self.fileManager.removeItem(
                    at: self.generationURL(id, in: root)
                        .appendingPathComponent("model.sqlite", isDirectory: false)
                )
            },
            .init(name: "current generation also retired", expectedFailure: .dataPointerInvalid) { root, id in
                try Data("{\"generationIDs\":[\"\(id.uuidString.lowercased())\"],\"schemaVersion\":1}".utf8)
                    .write(to: self.retiredPointerURL(in: root), options: .atomic)
            },
            .init(name: "unclassified newest generation", expectedFailure: .dataPointerInvalid) { root, _ in
                let unclassified = self.generationsURL(in: root)
                    .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
                try self.fileManager.createDirectory(at: unclassified, withIntermediateDirectories: false)
            },
        ]

        for testCase in cases {
            let root = try makeTemporaryApplicationSupportURL()
            defer { try? fileManager.removeItem(at: root) }
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            let generationID: UUID
            do {
                var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
                generationID = try XCTUnwrap(session).generationID
                session = nil
            }

            try testCase.mutate(root, generationID)
            let currentBefore = try optionalData(contentsOf: currentPointerURL(in: root))
            let retiredBefore = try optionalData(contentsOf: retiredPointerURL(in: root))
            let generationNamesBefore = try fileManager.contentsOfDirectory(
                atPath: generationsURL(in: root).path
            ).sorted()

            XCTAssertThrowsError(try factory.openOrBootstrapCurrent(), testCase.name) { error in
                XCTAssertEqual(error as? StoreGenerationFailure, testCase.expectedFailure, testCase.name)
            }

            XCTAssertEqual(try optionalData(contentsOf: currentPointerURL(in: root)), currentBefore, testCase.name)
            XCTAssertEqual(try optionalData(contentsOf: retiredPointerURL(in: root)), retiredBefore, testCase.name)
            XCTAssertEqual(
                try fileManager.contentsOfDirectory(atPath: generationsURL(in: root).path).sorted(),
                generationNamesBefore,
                testCase.name
            )
        }
    }

    @MainActor
    func testStoreSessionCoordinatorActivationChangesContextAndMonotonicallyAdvancesToken() throws {
        let firstRoot = try makeTemporaryApplicationSupportURL()
        let secondRoot = try makeTemporaryApplicationSupportURL()
        defer {
            try? fileManager.removeItem(at: firstRoot)
            try? fileManager.removeItem(at: secondRoot)
        }

        let firstSession = try StoreGenerationFactory(applicationSupportURL: firstRoot)
            .openOrBootstrapCurrent()
        let secondSession = try StoreGenerationFactory(applicationSupportURL: firstRoot)
            .openOrBootstrapCurrent()
        let foreignSession = try StoreGenerationFactory(applicationSupportURL: secondRoot)
            .openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: firstSession)
        defer { XCTAssertNoThrow(try coordinator.invalidateAndReleaseWriter()) }
        let firstContext = coordinator.modelContext
        let initialToken = coordinator.uiGenerationToken

        try coordinator.activateValidating(session: secondSession)

        XCTAssertEqual(coordinator.generationID, secondSession.generationID)
        XCTAssertEqual(coordinator.generationRootURL, secondSession.generationRootURL)
        XCTAssertFalse(coordinator.modelContext === firstContext)
        XCTAssertEqual(coordinator.uiGenerationToken, initialToken + 1)

        let secondWriter = coordinator.workspaceWriter
        XCTAssertThrowsError(try coordinator.activateValidating(session: foreignSession)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .invalidPath)
        }
        XCTAssertTrue(coordinator.workspaceWriter === secondWriter)
        XCTAssertNoThrow(try secondWriter.currentRevision())
        XCTAssertEqual(coordinator.uiGenerationToken, initialToken + 1)
        try coordinator.activateValidating(session: firstSession)
        XCTAssertEqual(coordinator.generationID, firstSession.generationID)
        XCTAssertEqual(coordinator.uiGenerationToken, initialToken + 2)
    }

    func testDiagnosticsCreatesExactZeroBytesAndReloadsEveryCounterAndBucket() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let countersURL = diagnosticsCountersURL(in: root)
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let store = DiagnosticsStore(applicationSupportURL: root, now: { now })

        await store.prepare()
        let initialSnapshot = await store.snapshot()
        XCTAssertEqual(initialSnapshot, .zero)
        let initialOperationalSnapshot = try await store.operationalSupportSnapshot()
        XCTAssertEqual(initialOperationalSnapshot.schemaVersion, 2)
        XCTAssertEqual(initialOperationalSnapshot.counters, .zero)
        XCTAssertEqual(initialOperationalSnapshot.health.generatedAt, now)
        let initialV3Bytes = try await store.canonicalOperationalSupportEnvelopeDataV3()
        XCTAssertEqual(
            try Data(contentsOf: countersURL),
            initialV3Bytes
        )

        let v2MigrationRoot = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: v2MigrationRoot) }
        let v2MigrationURL = diagnosticsCountersURL(in: v2MigrationRoot)
        try fileManager.createDirectory(
            at: v2MigrationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let v2Bytes = try canonicalOperationalSupportData(initialOperationalSnapshot)
        try v2Bytes.write(to: v2MigrationURL, options: .atomic)
        let v2MigrationStore = DiagnosticsStore(
            applicationSupportURL: v2MigrationRoot,
            now: { now }
        )
        let migratedV2Snapshot = try await v2MigrationStore.operationalSupportSnapshot()
        XCTAssertEqual(migratedV2Snapshot.schemaVersion, 2)
        XCTAssertEqual(migratedV2Snapshot.counters, .zero)
        let migratedV3Bytes = try await v2MigrationStore
            .canonicalOperationalSupportEnvelopeDataV3()
        let migratedV3Object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedV3Bytes) as? [String: Any]
        )
        XCTAssertEqual(
            (migratedV3Object["schemaVersion"] as? NSNumber)?.intValue,
            3
        )
        XCTAssertEqual(try Data(contentsOf: v2MigrationURL), migratedV3Bytes)

        for counter in allCounters {
            await store.increment(counter)
        }
        for result in allPurchaseResults {
            await store.incrementPurchaseResult(result)
        }

        let expected = DiagnosticsV1(
            firstSignCreated: 1,
            onboardingCompleted: 1,
            paywallPresented: 1,
            purchaseResult: .init(
                cancelled: 1,
                failed: 1,
                pending: 1,
                unverified: 1,
                verified: 1
            ),
            recheckCompleted: 1,
            reportSaved: 1,
            reportShareSheetPresented: 1,
            schemaVersion: 1
        )
        let incrementedSnapshot = await store.snapshot()
        XCTAssertEqual(incrementedSnapshot, expected)

        let persistedBytes = try Data(contentsOf: countersURL)
        let incrementedOperationalSnapshot = try await store.operationalSupportSnapshot()
        XCTAssertEqual(incrementedOperationalSnapshot.counters, expected)
        let incrementedV3Bytes = try await store.canonicalOperationalSupportEnvelopeDataV3()
        XCTAssertEqual(
            persistedBytes,
            incrementedV3Bytes
        )
        let reloaded = DiagnosticsStore(applicationSupportURL: root, now: { now })
        let reloadedSnapshot = await reloaded.snapshot()
        XCTAssertEqual(reloadedSnapshot, expected)
        let reloadedOperationalSnapshot = try await reloaded.operationalSupportSnapshot()
        XCTAssertEqual(reloadedOperationalSnapshot, incrementedOperationalSnapshot)
        XCTAssertEqual(try Data(contentsOf: countersURL), persistedBytes)
    }

    func testDiagnosticsCountersAndPurchaseBucketsSaturateAtInt64Max() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let countersURL = diagnosticsCountersURL(in: root)
        try fileManager.createDirectory(
            at: countersURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let maximum = Int64.max
        let maximumValue = DiagnosticsV1(
            firstSignCreated: maximum,
            onboardingCompleted: maximum,
            paywallPresented: maximum,
            purchaseResult: .init(
                cancelled: maximum,
                failed: maximum,
                pending: maximum,
                unverified: maximum,
                verified: maximum
            ),
            recheckCompleted: maximum,
            reportSaved: maximum,
            reportShareSheetPresented: maximum,
            schemaVersion: 1
        )
        let maximumBytes = try canonicalDiagnosticsData(maximumValue)
        try maximumBytes.write(to: countersURL, options: .atomic)

        let now = Date(timeIntervalSince1970: 1_777_777_778)
        let store = DiagnosticsStore(applicationSupportURL: root, now: { now })
        for counter in allCounters {
            await store.increment(counter)
        }
        for result in allPurchaseResults {
            await store.incrementPurchaseResult(result)
        }

        let saturatedSnapshot = await store.snapshot()
        XCTAssertEqual(saturatedSnapshot, maximumValue)
        let migrated = try await store.operationalSupportSnapshot()
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.counters, maximumValue)
        XCTAssertEqual(migrated.health.generatedAt, now)
        XCTAssertNotEqual(try Data(contentsOf: countersURL), maximumBytes)
        let saturatedV3Bytes = try await store.canonicalOperationalSupportEnvelopeDataV3()
        XCTAssertEqual(
            try Data(contentsOf: countersURL),
            saturatedV3Bytes
        )
    }

    func testMalformedDiagnosticsResetOnlyDiagnosticsAndPreserveDomainSentinels() async throws {
        let canonicalZero = exactZeroDiagnosticsData
        let now = Date(timeIntervalSince1970: 1_777_777_779)
        let malformedCases: [(name: String, data: Data)] = [
            ("malformed", Data("{".utf8)),
            ("unknown top-level key", inserting("\"unknown\":0,", after: "{", in: canonicalZero)),
            ("missing counter", removing("\"first_sign_created\":0,", from: canonicalZero)),
            ("negative counter", replacing("\"first_sign_created\":0", with: "\"first_sign_created\":-1", in: canonicalZero)),
            ("duplicate counter", inserting("\"first_sign_created\":0,", after: "{", in: canonicalZero)),
            ("noncanonical whitespace", Data(" \(String(decoding: canonicalZero, as: UTF8.self))".utf8)),
            ("malformed legacy schema", replacing("\"schemaVersion\":1", with: "\"schemaVersion\":2", in: canonicalZero)),
            (
                "unknown purchase bucket",
                replacing(
                    "\"purchase_result\":{",
                    with: "\"purchase_result\":{\"unknown\":0,",
                    in: canonicalZero
                )
            ),
        ]

        for testCase in malformedCases {
            let root = try makeTemporaryApplicationSupportURL()
            defer { try? fileManager.removeItem(at: root) }

            let currentURL = currentPointerURL(in: root)
            let retiredURL = retiredPointerURL(in: root)
            let modelURL = generationsURL(in: root)
                .appendingPathComponent("sentinel", isDirectory: true)
                .appendingPathComponent("model.sqlite", isDirectory: false)
            let countersURL = diagnosticsCountersURL(in: root)
            let currentSentinel = Data("current-pointer-sentinel".utf8)
            let retiredSentinel = Data("retired-pointer-sentinel".utf8)
            let modelSentinel = Data("domain-model-sentinel".utf8)

            try fileManager.createDirectory(
                at: modelURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: countersURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try currentSentinel.write(to: currentURL)
            try retiredSentinel.write(to: retiredURL)
            try modelSentinel.write(to: modelURL)
            try testCase.data.write(to: countersURL)

            let store = DiagnosticsStore(applicationSupportURL: root, now: { now })
            let resetSnapshot = try await store.operationalSupportSnapshot()
            XCTAssertEqual(resetSnapshot.schemaVersion, 2, testCase.name)
            XCTAssertEqual(resetSnapshot.counters, .zero, testCase.name)
            XCTAssertEqual(resetSnapshot.health.generatedAt, now, testCase.name)
            let persistedEnvelope = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: countersURL))
                    as? [String: Any]
            )
            XCTAssertEqual(
                (persistedEnvelope["schemaVersion"] as? NSNumber)?.intValue,
                3,
                testCase.name
            )
            XCTAssertEqual(
                (persistedEnvelope["feedbackDraftRecoveryRequired"] as? NSNumber)?.boolValue,
                true,
                testCase.name
            )
            let persistedV3Bytes = try await store
                .canonicalOperationalSupportEnvelopeDataV3()
            XCTAssertEqual(
                try Data(contentsOf: countersURL),
                persistedV3Bytes,
                testCase.name
            )
            let recoverySnapshot = try await store.supportFeedbackDraftSnapshot()
            XCTAssertEqual(recoverySnapshot.state, .recoveryRequired, testCase.name)
            XCTAssertTrue(recoverySnapshot.safeCopyAvailable, testCase.name)
            XCTAssertEqual(try Data(contentsOf: currentURL), currentSentinel, testCase.name)
            XCTAssertEqual(try Data(contentsOf: retiredURL), retiredSentinel, testCase.name)
            XCTAssertEqual(try Data(contentsOf: modelURL), modelSentinel, testCase.name)
        }

        let forwardRoot = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: forwardRoot) }
        let seed = DiagnosticsStore(applicationSupportURL: forwardRoot, now: { now })
        let releasedBytes = try await seed.canonicalOperationalSupportEnvelopeDataV3()
        let forwardBytes = replacing(
            "\"schemaVersion\":3",
            with: "\"schemaVersion\":4",
            in: releasedBytes
        )
        try forwardBytes.write(to: diagnosticsCountersURL(in: forwardRoot), options: .atomic)
        let forwardStore = DiagnosticsStore(applicationSupportURL: forwardRoot, now: { now })
        do {
            _ = try await forwardStore.operationalSupportSnapshot()
            XCTFail("Expected the future diagnostics envelope to fail closed")
        } catch {
            XCTAssertEqual(
                try Data(contentsOf: diagnosticsCountersURL(in: forwardRoot)),
                forwardBytes
            )
        }
    }

    func testDiagnosticsWriteFailureIsNonGatingAndDoesNotInventAnIncrement() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let countersURL = diagnosticsCountersURL(in: root)
        try fileManager.createDirectory(at: countersURL, withIntermediateDirectories: true)

        let store = DiagnosticsStore(applicationSupportURL: root)
        await store.prepare()
        await store.increment(.firstSignCreated)
        await store.incrementPurchaseResult(.verified)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot, .zero)
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(fileManager.fileExists(atPath: countersURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    func testStartupUsesTheFrozenOrderBeforeEnablingWrites() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }

        var observedSteps: [StartupStep] = []
        let router = StartupRouter(
            applicationSupportURL: root,
            didBeginStep: { observedSteps.append($0) }
        )
        defer { router.failClosedPDFRecovery() }

        await router.retryChecks()

        XCTAssertEqual(
            observedSteps,
            [.erase, .restore, .currentOpen, .fieldDraft, .finalization, .deletion, .media, .pdf]
        )
        guard case .ready = router.route else {
            return XCTFail("A clean application-support root must become writable.")
        }
    }

    @MainActor
    func testPendingEraseAndRestoreRootsRouteToTheirExactMaintenanceReasons() async throws {
        let cases: [(directoryName: String, expectedReason: StartupMaintenanceReason, expectedSteps: [StartupStep])] = [
            ("FieldEvidenceErase", .eraseInconsistent, [.erase]),
            ("FieldEvidenceRestore", .restoreInconsistent, [.erase, .restore]),
        ]

        for testCase in cases {
            let root = try makeTemporaryApplicationSupportURL()
            defer { try? fileManager.removeItem(at: root) }

            let pendingRoot = root.appendingPathComponent(testCase.directoryName, isDirectory: true)
            try fileManager.createDirectory(
                at: pendingRoot,
                withIntermediateDirectories: true
            )
            try Data("pending".utf8).write(
                to: pendingRoot.appendingPathComponent("pending.json", isDirectory: false)
            )

            var observedSteps: [StartupStep] = []
            let router = StartupRouter(
                applicationSupportURL: root,
                didBeginStep: { observedSteps.append($0) }
            )
            await router.retryChecks()

            XCTAssertEqual(observedSteps, testCase.expectedSteps, testCase.directoryName)
            guard case let .maintenance(reason) = router.route else {
                XCTFail("\(testCase.directoryName) must block startup.")
                continue
            }
            XCTAssertEqual(reason, testCase.expectedReason, testCase.directoryName)
        }
    }

    @MainActor
    func testInvalidPointerAndMissingGenerationRouteToExactMaintenanceReasons() async throws {
        let cases: [(name: String, expectedReason: StartupMaintenanceReason, mutate: (URL, UUID) throws -> Void)] = [
            ("invalid pointer", .dataPointerInvalid, { root, _ in
                try self.fileManager.removeItem(at: self.currentPointerURL(in: root))
            }),
            ("missing generation", .dataGenerationMissing, { root, generationID in
                try self.fileManager.removeItem(at: self.generationURL(generationID, in: root))
            }),
        ]

        for testCase in cases {
            let root = try makeTemporaryApplicationSupportURL()
            defer { try? fileManager.removeItem(at: root) }
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            let generationID: UUID
            do {
                var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
                generationID = try XCTUnwrap(session).generationID
                session = nil
            }
            try testCase.mutate(root, generationID)

            var observedSteps: [StartupStep] = []
            let router = StartupRouter(
                applicationSupportURL: root,
                didBeginStep: { observedSteps.append($0) }
            )
            await router.retryChecks()

            XCTAssertEqual(observedSteps, [.erase, .restore, .currentOpen], testCase.name)
            guard case let .maintenance(reason) = router.route else {
                XCTFail("\(testCase.name) must block startup.")
                continue
            }
            XCTAssertEqual(reason, testCase.expectedReason, testCase.name)
        }
    }

    @MainActor
    func testMaintenanceReasonAndCopyContractIsClosedAndExact() {
        XCTAssertEqual(
            StartupMaintenanceReason.allCases.map(\.rawValue),
            [
                "data_pointer_invalid",
                "data_generation_missing",
                "finalization_inconsistent",
                "media_inconsistent",
                "restore_inconsistent",
                "erase_inconsistent",
            ]
        )
        XCTAssertEqual(StartupMaintenanceView.titleText, "Local data needs attention")
        XCTAssertEqual(
            StartupMaintenanceView.messageText,
            "The app stopped to avoid changing or losing local records."
        )
        XCTAssertEqual(StartupMaintenanceView.retryButtonText, "Retry checks")
        XCTAssertEqual(StartupMaintenanceView.recoveryButtonText, "Recovery steps")
        XCTAssertEqual(
            StartupMaintenanceView.recoveryStepsText,
            "If Retry cannot recover this device, delete and reinstall the app. This removes all local app data and does not cancel your Apple subscription. A backup stored outside this app can be restored from Welcome after reinstalling."
        )
    }

    private func makeTemporaryApplicationSupportURL() throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("S2PersistenceLedgerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func dataRootURL(in applicationSupportURL: URL) -> URL {
        applicationSupportURL.appendingPathComponent("FieldEvidenceData", isDirectory: true)
    }

    private func currentPointerURL(in applicationSupportURL: URL) -> URL {
        dataRootURL(in: applicationSupportURL).appendingPathComponent("current.json", isDirectory: false)
    }

    private func retiredPointerURL(in applicationSupportURL: URL) -> URL {
        dataRootURL(in: applicationSupportURL).appendingPathComponent("retired.json", isDirectory: false)
    }

    private func generationsURL(in applicationSupportURL: URL) -> URL {
        dataRootURL(in: applicationSupportURL).appendingPathComponent("generations", isDirectory: true)
    }

    private func generationURL(_ generationID: UUID, in applicationSupportURL: URL) -> URL {
        generationsURL(in: applicationSupportURL)
            .appendingPathComponent(generationID.uuidString.lowercased(), isDirectory: true)
    }

    private func optionalData(contentsOf url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private var allCounters: [Counter] {
        [
            .firstSignCreated,
            .onboardingCompleted,
            .paywallPresented,
            .recheckCompleted,
            .reportSaved,
            .reportShareSheetPresented,
        ]
    }

    private var allPurchaseResults: [PurchaseResult] {
        [.cancelled, .failed, .pending, .unverified, .verified]
    }

    private var exactZeroDiagnosticsData: Data {
        Data("{\"first_sign_created\":0,\"onboarding_completed\":0,\"paywall_presented\":0,\"purchase_result\":{\"cancelled\":0,\"failed\":0,\"pending\":0,\"unverified\":0,\"verified\":0},\"recheck_completed\":0,\"report_saved\":0,\"report_share_sheet_presented\":0,\"schemaVersion\":1}".utf8)
    }

    private func diagnosticsCountersURL(in applicationSupportURL: URL) -> URL {
        applicationSupportURL
            .appendingPathComponent("FieldEvidenceDiagnostics", isDirectory: true)
            .appendingPathComponent("counters.json", isDirectory: false)
    }

    private func canonicalDiagnosticsData(_ value: DiagnosticsV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func canonicalOperationalSupportData(
        _ value: DeviceOperationalSupportSnapshotV2
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func inserting(_ insertion: String, after marker: String, in data: Data) -> Data {
        let source = String(decoding: data, as: UTF8.self)
        let range = source.range(of: marker)!
        var changed = source
        changed.insert(contentsOf: insertion, at: range.upperBound)
        return Data(changed.utf8)
    }

    private func removing(_ target: String, from data: Data) -> Data {
        replacing(target, with: "", in: data)
    }

    private func replacing(_ target: String, with replacement: String, in data: Data) -> Data {
        Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: target, with: replacement).utf8)
    }
}

extension S2PersistenceLedgerTests {
    @MainActor
    func testStartupRecoversPendingPDFAndPublishesItsSingleWriter() async throws {
        let harness = try await S42CurrentReportHarness.make("startup-single-writer") { seed in
            UIGraphicsImageRenderer(size: CGSize(width: 48, height: 32)).pngData { context in
                UIColor(red: CGFloat(seed) / 255, green: 0.4, blue: 0.7, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
            }
        }
        let root = harness.applicationSupportURL
        defer { try? fileManager.removeItem(at: root) }
        let reportID = harness.report.id
        let initialHistory = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
        let initialEnvelopes = Set(initialHistory.map(\.envelopeData))
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.pending.rawValue)
        try harness.close()
        XCTAssertEqual(try writerLeaseIDs(in: root).count, 0)
        var recoveryWriterID: UUID?
        var leaseCountAtBoundary: Int?
        let router = StartupRouter(applicationSupportURL: root, entitlementRuntime: isolatedStartupRuntime,
            beforeCommerceActivation: { writerID in
                recoveryWriterID = writerID
                leaseCountAtBoundary = try? self.writerLeaseIDs(in: root).count
            })
        defer { router.failClosedPDFRecovery() }
        await router.retryChecks()
        guard case let .ready(coordinator, _, _) = router.route else {
            return XCTFail("A canonical finalized pending report must recover before startup publishes its writer")
        }
        XCTAssertEqual(recoveryWriterID, try coordinator.workspaceWriter.currentRevision().writerInstanceID)
        XCTAssertEqual(leaseCountAtBoundary, 1)
        XCTAssertEqual(try writerLeaseIDs(in: root).count, 1)
        let report = try XCTUnwrap(coordinator.modelContext.fetch(FetchDescriptor<Report>()).first { $0.id == reportID })
        XCTAssertEqual(report.pdfState, ReportPDFState.ready.rawValue)
        let path = try XCTUnwrap(report.pdfRelativePath)
        XCTAssertFalse(try Data(contentsOf: coordinator.generationRootURL.appendingPathComponent(path)).isEmpty)
        let finalHistory = try coordinator.workspaceWriter.sourceMutationHistorySnapshot()
        XCTAssertEqual(finalHistory.receipts.count, initialHistory.count + 1)
        XCTAssertTrue(initialEnvelopes.isSubset(of: Set(finalHistory.receipts.map(\.envelopeData))))
        let pdfEnvelopes = try finalHistory.receipts.map { try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData) }
            .filter { $0.command.kind == .transitionReportPDF }
        XCTAssertEqual(pdfEnvelopes.count, 1)
        XCTAssertTrue(router.entitlementProcessor?.isStarted == true)
    }

    @MainActor
    func testStartupRetryAndUnsafePDFFailureExplicitlyReleaseRetainedPublishedWriters() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let router = StartupRouter(applicationSupportURL: root, entitlementRuntime: isolatedStartupRuntime)
        defer { router.failClosedPDFRecovery() }
        await router.retryChecks()
        guard case let .ready(first, _, _) = router.route else { return XCTFail("Initial startup") }
        let firstWriter = first.workspaceWriter
        let firstLeases = try writerLeaseIDs(in: root)
        XCTAssertEqual(firstLeases.count, 1)
        await router.retryChecks()
        guard case let .ready(second, _, _) = router.route else { return XCTFail("Explicit retry") }
        XCTAssertFalse(first === second)
        XCTAssertThrowsError(try firstWriter.currentRevision()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        let secondLeases = try writerLeaseIDs(in: root)
        XCTAssertEqual(secondLeases.count, 1)
        XCTAssertTrue(firstLeases.isDisjoint(with: secondLeases))
        let processor = try XCTUnwrap(router.entitlementProcessor)
        router.failClosedPDFRecovery()
        XCTAssertFalse(processor.isStarted)
        XCTAssertNil(router.entitlementProcessor)
        XCTAssertThrowsError(try second.workspaceWriter.currentRevision())
        XCTAssertEqual(try writerLeaseIDs(in: root).count, 0)
        XCTAssertFalse(router.hasPendingWriterCleanup)
        XCTAssertNil(router.maintenanceRestoreSession)
        XCTAssertNil(router.maintenanceEraseSession)
        guard case .maintenance(.finalizationInconsistent) = router.route else {
            return XCTFail("Unsafe PDF recovery must stay closed")
        }
    }

    @MainActor
    func testStartupReleaseFailureRemainsOwnedAndBlocksRetryUntilOriginalRegistryIsReadable() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let router = StartupRouter(applicationSupportURL: root, entitlementRuntime: isolatedStartupRuntime)
        defer { router.failClosedPDFRecovery() }
        await router.retryChecks()
        guard case let .ready(coordinator, _, _) = router.route else { return XCTFail("Initial startup") }
        let writer = coordinator.workspaceWriter
        let originalLeaseIDs = try writerLeaseIDs(in: root)
        let registryURL = root.appendingPathComponent("FieldEvidenceOperations/generation-leases/registry.json")
        let originalRegistry = try Data(contentsOf: registryURL)
        let pointer = try Data(contentsOf: currentPointerURL(in: root))
        // A real unreadable control file makes close throw; no test-only
        // success flag or synthetic registry/checkpoint substitutes for it.
        try Data("invalid registry transport".utf8).write(to: registryURL)
        var registryNeedsRestoring = true
        defer { if registryNeedsRestoring { try? originalRegistry.write(to: registryURL) } }
        router.failClosedPDFRecovery()
        XCTAssertTrue(router.hasPendingWriterCleanup)
        XCTAssertNotNil(router.lastWriterCleanupFailure)
        XCTAssertThrowsError(try writer.currentRevision()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
        }
        await router.retryChecks()
        XCTAssertTrue(router.hasPendingWriterCleanup)
        XCTAssertNil(router.entitlementProcessor)
        XCTAssertNil(router.maintenanceRestoreSession)
        XCTAssertNil(router.maintenanceEraseSession)
        XCTAssertEqual(try Data(contentsOf: currentPointerURL(in: root)), pointer)
        try originalRegistry.write(to: registryURL)
        registryNeedsRestoring = false
        await router.retryChecks()
        guard case let .ready(retried, _, _) = router.route else { return XCTFail("Release retry must recover") }
        XCTAssertFalse(router.hasPendingWriterCleanup)
        XCTAssertNil(router.lastWriterCleanupFailure)
        XCTAssertFalse(retried.workspaceWriter === writer)
        let currentLeaseIDs = try writerLeaseIDs(in: root)
        XCTAssertEqual(currentLeaseIDs.count, 1)
        XCTAssertTrue(currentLeaseIDs.isDisjoint(with: originalLeaseIDs))
        XCTAssertEqual(try Data(contentsOf: currentPointerURL(in: root)), pointer)
    }

    @MainActor
    func testSupersededStartupCannotPublishOrClearTheNewReadyOperation() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let pause = S2StartupPublicationPause()
        var observedWriterIDs: [UUID] = []
        let router = StartupRouter(applicationSupportURL: root, entitlementRuntime: isolatedStartupRuntime,
            beforeCommerceActivation: { writerID in
                observedWriterIDs.append(writerID)
                if observedWriterIDs.count == 1 { await pause.suspend() }
            })
        defer { pause.resume(); router.failClosedPDFRecovery() }
        let original = Task { await router.retryChecks() }
        let reached = await XCTWaiter.fulfillment(of: [pause.reached], timeout: 20)
        XCTAssertEqual(reached, .completed)
        router.failClosedPDFRecovery()
        XCTAssertEqual(try writerLeaseIDs(in: root).count, 0)
        XCTAssertNil(router.entitlementProcessor)
        await router.retryChecks()
        guard case let .ready(current, _, _) = router.route else {
            pause.resume(); await original.value
            return XCTFail("New operation should complete while the previous continuation is held")
        }
        let currentLeases = try writerLeaseIDs(in: root)
        pause.resume()
        await original.value
        guard case let .ready(stillCurrent, _, _) = router.route else { return XCTFail("Stale completion overwrote ready") }
        XCTAssertTrue(stillCurrent === current)
        XCTAssertEqual(observedWriterIDs.count, 2)
        XCTAssertNotEqual(observedWriterIDs.first, observedWriterIDs.last)
        XCTAssertEqual(try current.workspaceWriter.currentRevision().writerInstanceID, observedWriterIDs.last)
        XCTAssertEqual(try writerLeaseIDs(in: root), currentLeases)
        XCTAssertTrue(router.entitlementProcessor?.isStarted == true)
    }

    @MainActor
    func testSuspendedRestoredActivationCannotReleaseANewerBindingInTheSameCoordinator() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let session = try factory.openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        defer { XCTAssertNoThrow(try coordinator.invalidateAndReleaseWriter()) }
        let pause = S2StartupPublicationPause()
        let router = StartupRouter(applicationSupportURL: root, entitlementRuntime: isolatedStartupRuntime,
            beforeCommerceActivation: { _ in await pause.suspend() })
        defer { pause.resume(); router.failClosedPDFRecovery() }
        let activation = Task { await router.activateRestoredSession(session, coordinator: coordinator) }
        let reached = await XCTWaiter.fulfillment(of: [pause.reached], timeout: 20)
        XCTAssertEqual(reached, .completed)
        let suspendedWriter = coordinator.workspaceWriter
        router.failClosedPDFRecovery()
        XCTAssertEqual(try writerLeaseIDs(in: root).count, 0)
        let reopened = try factory.openOrBootstrapCurrent()
        try coordinator.activateValidating(session: reopened)
        let replacementWriter = coordinator.workspaceWriter
        let replacementLeases = try writerLeaseIDs(in: root)
        XCTAssertFalse(replacementWriter === suspendedWriter)
        pause.resume()
        await activation.value
        XCTAssertTrue(coordinator.workspaceWriter === replacementWriter)
        XCTAssertNoThrow(try replacementWriter.currentRevision())
        XCTAssertEqual(try writerLeaseIDs(in: root), replacementLeases)
        XCTAssertEqual(replacementLeases.count, 1)
        XCTAssertFalse(router.hasPendingWriterCleanup)
        XCTAssertNil(router.entitlementProcessor)
        guard case .maintenance(.finalizationInconsistent) = router.route else {
            return XCTFail("The superseded restored activation must not publish its borrowed replacement")
        }
    }

    private var isolatedStartupRuntime: StoreKitEntitlementRuntimeV1 {
        StoreKitEntitlementRuntimeV1(initialEvents: { [] },
            transactionUpdates: { AsyncStream { $0.finish() } },
            statusUpdates: { AsyncStream { $0.finish() } })
    }

    @MainActor
    func testErasedActivationMismatchAndRepeatedBeginReleaseOnlyTheAcquiredWriter() async throws {
        for action in ["finish", "defer", "begin"] {
            let root = try makeTemporaryApplicationSupportURL()
            let foreignRoot = try makeTemporaryApplicationSupportURL()
            defer {
                try? fileManager.removeItem(at: root)
                try? fileManager.removeItem(at: foreignRoot)
            }
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            let initial = try factory.openOrBootstrapCurrent()
            let owner = try StoreSessionCoordinator(validatingSession: initial)
            let activeSession = try factory.openOrBootstrapCurrent()
            let foreignSession = try StoreGenerationFactory(applicationSupportURL: foreignRoot).openOrBootstrapCurrent()
            let borrowed = try StoreSessionCoordinator(validatingSession: foreignSession)
            defer {
                XCTAssertNoThrow(try owner.invalidateAndReleaseWriter())
                XCTAssertNoThrow(try borrowed.invalidateAndReleaseWriter())
            }
            let router = StartupRouter(applicationSupportURL: root, entitlementRuntime: isolatedStartupRuntime)
            await router.beginErasedSessionActivation(activeSession, coordinator: owner)
            let acquiredWriter = owner.workspaceWriter
            let borrowedWriter = borrowed.workspaceWriter
            let borrowedLeases = try writerLeaseIDs(in: foreignRoot)
            XCTAssertEqual(try writerLeaseIDs(in: root).count, 1)
            switch action {
            case "finish": await router.finishErasedSessionActivation(foreignSession, coordinator: borrowed)
            case "defer": router.deferErasedSessionCleanup(foreignSession, coordinator: borrowed)
            default: await router.beginErasedSessionActivation(foreignSession, coordinator: borrowed)
            }
            guard case .maintenance(.eraseInconsistent) = router.route else {
                return XCTFail("Mismatched or repeated erased activation must fail closed: \(action)")
            }
            XCTAssertThrowsError(try acquiredWriter.currentRevision()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
            }
            XCTAssertEqual(try writerLeaseIDs(in: root).count, 0)
            XCTAssertTrue(borrowed.workspaceWriter === borrowedWriter)
            XCTAssertNoThrow(try borrowedWriter.currentRevision())
            XCTAssertEqual(try writerLeaseIDs(in: foreignRoot), borrowedLeases)
            XCTAssertFalse(router.hasPendingWriterCleanup)
            XCTAssertNil(router.entitlementProcessor)
            XCTAssertNil(router.maintenanceRestoreSession)
            XCTAssertNil(router.maintenanceEraseSession)
        }
    }

    @MainActor
    func testValidatingCoordinatorConstructionReleasesLeaseAfterRealJournalFailure() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        let checkpoint = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
            .mutableSemanticSHA256
        let corruptRow = Site(id: UUID(), label: "Unjournaled corruption", address: nil, timeZoneID: "UTC")
        session.modelContext.insert(corruptRow)
        try session.modelContext.save()
        XCTAssertThrowsError(try StoreSessionCoordinator(validatingSession: session)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try writerLeaseIDs(in: root).count, 0)
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<Site>()).map(\.id), [corruptRow.id])
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).count, 0)
        XCTAssertEqual(try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
            .mutableSemanticSHA256, checkpoint)
    }

    private func writerLeaseIDs(in root: URL) throws -> Set<String> {
        let data = try Data(contentsOf: root.appendingPathComponent("FieldEvidenceOperations/generation-leases/registry.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let leases = try XCTUnwrap(object["leases"] as? [[String: Any]])
        return Set(try leases.filter { $0["role"] as? String == GenerationLeaseRoleV1.writer.rawValue }
            .map { try XCTUnwrap($0["leaseID"] as? String) })
    }

    func testV23P03C54EncryptedEnvelopeAddsNoPersistentModelWriterOrLedgerFamily() {
        XCTAssertTrue(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.validate())
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.storeEnrollmentCount, 0)
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.writerEnrollmentCount, 0)
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.persistentModelCountAdded, 0)
        XCTAssertFalse(EphemeralSecretHandlingDispositionV1.passphraseIsPersisted)
        XCTAssertFalse(EphemeralSecretHandlingDispositionV1.derivedKeyIsPersisted)
    }
}

@MainActor
private final class S2StartupPublicationPause {
    let reached = XCTestExpectation(description: "Actual writer recovered, before commerce publication")
    private var continuation: CheckedContinuation<Void, Never>?
    private var isResumed = false

    func suspend() async {
        guard !isResumed else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            reached.fulfill()
        }
    }

    func resume() {
        isResumed = true
        continuation?.resume()
        continuation = nil
    }
}

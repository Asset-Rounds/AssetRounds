import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S2PersistenceLedgerTests: XCTestCase {
    private let fileManager = FileManager.default

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
        let secondSession = try StoreGenerationFactory(applicationSupportURL: secondRoot)
            .openOrBootstrapCurrent()
        let coordinator = StoreSessionCoordinator(session: firstSession)
        let firstContext = coordinator.modelContext
        let initialToken = coordinator.uiGenerationToken

        coordinator.activate(session: secondSession)

        XCTAssertEqual(coordinator.generationID, secondSession.generationID)
        XCTAssertEqual(coordinator.generationRootURL, secondSession.generationRootURL)
        XCTAssertFalse(coordinator.modelContext === firstContext)
        XCTAssertEqual(coordinator.uiGenerationToken, initialToken + 1)

        coordinator.activate(session: firstSession)
        XCTAssertEqual(coordinator.generationID, firstSession.generationID)
        XCTAssertEqual(coordinator.uiGenerationToken, initialToken + 2)
    }

    func testDiagnosticsCreatesExactZeroBytesAndReloadsEveryCounterAndBucket() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let countersURL = diagnosticsCountersURL(in: root)
        let store = DiagnosticsStore(applicationSupportURL: root)

        await store.prepare()
        let initialSnapshot = await store.snapshot()
        XCTAssertEqual(initialSnapshot, .zero)
        XCTAssertEqual(try Data(contentsOf: countersURL), exactZeroDiagnosticsData)

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
        XCTAssertEqual(persistedBytes, try canonicalDiagnosticsData(expected))
        let reloaded = DiagnosticsStore(applicationSupportURL: root)
        let reloadedSnapshot = await reloaded.snapshot()
        XCTAssertEqual(reloadedSnapshot, expected)
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

        let store = DiagnosticsStore(applicationSupportURL: root)
        for counter in allCounters {
            await store.increment(counter)
        }
        for result in allPurchaseResults {
            await store.incrementPurchaseResult(result)
        }

        let saturatedSnapshot = await store.snapshot()
        XCTAssertEqual(saturatedSnapshot, maximumValue)
        XCTAssertEqual(try Data(contentsOf: countersURL), maximumBytes)
    }

    func testMalformedDiagnosticsResetOnlyDiagnosticsAndPreserveDomainSentinels() async throws {
        let canonicalZero = exactZeroDiagnosticsData
        let malformedCases: [(name: String, data: Data)] = [
            ("malformed", Data("{".utf8)),
            ("unknown top-level key", inserting("\"unknown\":0,", after: "{", in: canonicalZero)),
            ("missing counter", removing("\"first_sign_created\":0,", from: canonicalZero)),
            ("negative counter", replacing("\"first_sign_created\":0", with: "\"first_sign_created\":-1", in: canonicalZero)),
            ("duplicate counter", inserting("\"first_sign_created\":0,", after: "{", in: canonicalZero)),
            ("noncanonical whitespace", Data(" \(String(decoding: canonicalZero, as: UTF8.self))".utf8)),
            ("unsupported schema", replacing("\"schemaVersion\":1", with: "\"schemaVersion\":2", in: canonicalZero)),
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

            let store = DiagnosticsStore(applicationSupportURL: root)
            let resetSnapshot = await store.snapshot()
            XCTAssertEqual(resetSnapshot, .zero, testCase.name)
            XCTAssertEqual(try Data(contentsOf: countersURL), canonicalZero, testCase.name)
            XCTAssertEqual(try Data(contentsOf: currentURL), currentSentinel, testCase.name)
            XCTAssertEqual(try Data(contentsOf: retiredURL), retiredSentinel, testCase.name)
            XCTAssertEqual(try Data(contentsOf: modelURL), modelSentinel, testCase.name)
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

        await router.retryChecks()

        XCTAssertEqual(
            observedSteps,
            [.erase, .restore, .currentOpen, .finalization, .deletion, .media, .pdf]
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

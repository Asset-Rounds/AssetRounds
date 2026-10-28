import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S2SignSetupTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testPresentOptionalValuesSaveReleaseAndReopenExactFirstSign() async throws {
        try await assertFirstSignRoundTrip(
            input: FirstSignInput(
                siteLabel: "  North Campus  ",
                signLabel: "  Monument Sign  ",
                address: "  10 Main Street  ",
                timeZoneID: "America/New_York",
                isTimeZoneConfirmed: true
            ),
            expectedSiteLabel: "North Campus",
            expectedSignLabel: "Monument Sign",
            expectedAddress: "10 Main Street",
            expectedTimeZoneID: "America/New_York"
        )
    }

    @MainActor
    func testNilOptionalValuesSaveReleaseAndReopenExactFirstSign() async throws {
        try await assertFirstSignRoundTrip(
            input: FirstSignInput(
                siteLabel: "South Campus",
                signLabel: "Wall Sign",
                address: " \n\t ",
                timeZoneID: "",
                isTimeZoneConfirmed: false
            ),
            expectedSiteLabel: "South Campus",
            expectedSignLabel: "Wall Sign",
            expectedAddress: nil,
            expectedTimeZoneID: nil
        )
    }

    @MainActor
    func testInvalidInputsReturnOneExactFieldAndWriteNothing() async throws {
        struct InvalidCase {
            let name: String
            let input: FirstSignInput
            let expectedField: FirstSignValidationField
        }

        let cases = [
            InvalidCase(
                name: "blank site label",
                input: FirstSignInput(siteLabel: " \n ", signLabel: "Monument Sign"),
                expectedField: .siteLabel
            ),
            InvalidCase(
                name: "blank sign label",
                input: FirstSignInput(siteLabel: "North Campus", signLabel: "\t "),
                expectedField: .signLabel
            ),
            InvalidCase(
                name: "unknown IANA identifier",
                input: FirstSignInput(
                    siteLabel: "North Campus",
                    signLabel: "Monument Sign",
                    timeZoneID: "Mars/Olympus_Mons",
                    isTimeZoneConfirmed: true
                ),
                expectedField: .timeZoneID
            ),
            InvalidCase(
                name: "supplied but unconfirmed zone",
                input: FirstSignInput(
                    siteLabel: "North Campus",
                    signLabel: "Monument Sign",
                    timeZoneID: "America/New_York",
                    isTimeZoneConfirmed: false
                ),
                expectedField: .timeZoneConfirmation
            ),
        ]

        for testCase in cases {
            let root = try makeTemporaryApplicationSupportURL()
            defer {
                if !FirstSignFixtureWriterReleaseV1.retains(root: root) {
                    try? fileManager.removeItem(at: root)
                }
            }

            let session = try StoreGenerationFactory(applicationSupportURL: root)
                .openOrBootstrapCurrent()
            let diagnosticsStore = DiagnosticsStore(applicationSupportURL: root)
            let firstSignProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: .illuminatedSignV1)
            let firstSignRegistry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [firstSignProfile])
            let firstSignOwner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: session,
                profileRegistry: firstSignRegistry, root: root)
            defer {
                do { try FirstSignFixtureWriterReleaseV1.close(firstSignOwner, session: session, root: root) }
                catch { XCTFail("First-sign fixture writer release failed: \(error)") }
            }
            let firstSignDependencies = try firstSignOwner.packageLifecycleDependencies(profileRegistry: firstSignRegistry)
            let coordinator = try FirstSignCoordinator(
                modelContext: session.modelContext,
                diagnosticsStore: diagnosticsStore,
                packageLifecycleDependencies: firstSignDependencies,
                packageLifecycleProfile: firstSignProfile
            )

            do {
                _ = try await coordinator.create(testCase.input)
                XCTFail("\(testCase.name) must not create a sign.")
            } catch let error as FirstSignCoordinatorError {
                XCTAssertEqual(
                    error,
                    .validation(testCase.expectedField),
                    testCase.name
                )
            } catch {
                XCTFail("\(testCase.name) returned unexpected error: \(error)")
            }

            XCTAssertEqual(
                try session.modelContext.fetchCount(FetchDescriptor<Site>()),
                0,
                testCase.name
            )
            XCTAssertEqual(
                try session.modelContext.fetchCount(FetchDescriptor<Asset>()),
                0,
                testCase.name
            )
            let diagnostics = await diagnosticsStore.snapshot()
            XCTAssertEqual(diagnostics, .zero, testCase.name)
        }
    }

    @MainActor
    func testSecondCreateIsRejectedWithoutAnotherRowOrCounter() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer {
            if !FirstSignFixtureWriterReleaseV1.retains(root: root) {
                try? fileManager.removeItem(at: root)
            }
        }

        let session = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        let diagnosticsStore = DiagnosticsStore(applicationSupportURL: root)
        let firstSignProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: .illuminatedSignV1)
        let firstSignRegistry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [firstSignProfile])
        let firstSignOwner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: session,
            profileRegistry: firstSignRegistry, root: root)
        defer {
            do { try FirstSignFixtureWriterReleaseV1.close(firstSignOwner, session: session, root: root) }
            catch { XCTFail("First-sign fixture writer release failed: \(error)") }
        }
        let firstSignDependencies = try firstSignOwner.packageLifecycleDependencies(profileRegistry: firstSignRegistry)
        let coordinator = try FirstSignCoordinator(
            modelContext: session.modelContext,
            diagnosticsStore: diagnosticsStore,
            packageLifecycleDependencies: firstSignDependencies,
            packageLifecycleProfile: firstSignProfile
        )

        let first = try await coordinator.create(
            FirstSignInput(siteLabel: "North Campus", signLabel: "Monument Sign")
        )

        do {
            _ = try await coordinator.create(
                FirstSignInput(siteLabel: "South Campus", signLabel: "Wall Sign")
            )
            XCTFail("The first-sign-only action must reject a second Asset.")
        } catch let error as FirstSignCoordinatorError {
            XCTAssertEqual(error, .firstSignAlreadyExists)
        } catch {
            XCTFail("Second create returned unexpected error: \(error)")
        }

        let sites = try session.modelContext.fetch(FetchDescriptor<Site>())
        let assets = try session.modelContext.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(sites.first?.id, first.siteID)
        XCTAssertEqual(assets.first?.id, first.assetID)
        XCTAssertEqual(assets.first?.siteID, first.siteID)
        try assertOnlyFirstSignCreated(await diagnosticsStore.snapshot())
    }

    @MainActor
    func testDiagnosticsWriteFailureDoesNotGateTheCommittedFirstSign() async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer {
            if !FirstSignFixtureWriterReleaseV1.retains(root: root) {
                try? fileManager.removeItem(at: root)
            }
        }

        let diagnosticsURL = root
            .appendingPathComponent("FieldEvidenceDiagnostics", isDirectory: true)
            .appendingPathComponent("counters.json", isDirectory: true)
        try fileManager.createDirectory(
            at: diagnosticsURL,
            withIntermediateDirectories: true
        )

        let session = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        let diagnosticsStore = DiagnosticsStore(applicationSupportURL: root)
        let firstSignProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: .illuminatedSignV1)
        let firstSignRegistry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [firstSignProfile])
        let firstSignOwner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: session,
            profileRegistry: firstSignRegistry, root: root)
        defer {
            do { try FirstSignFixtureWriterReleaseV1.close(firstSignOwner, session: session, root: root) }
            catch { XCTFail("First-sign fixture writer release failed: \(error)") }
        }
        let firstSignDependencies = try firstSignOwner.packageLifecycleDependencies(profileRegistry: firstSignRegistry)
        let coordinator = try FirstSignCoordinator(
            modelContext: session.modelContext,
            diagnosticsStore: diagnosticsStore,
            packageLifecycleDependencies: firstSignDependencies,
            packageLifecycleProfile: firstSignProfile
        )

        let created = try await coordinator.create(
            FirstSignInput(siteLabel: "North Campus", signLabel: "Monument Sign")
        )

        XCTAssertEqual(created.siteLabel, "North Campus")
        XCTAssertEqual(created.signLabel, "Monument Sign")
        XCTAssertEqual(
            try session.modelContext.fetchCount(FetchDescriptor<Site>()),
            1
        )
        XCTAssertEqual(
            try session.modelContext.fetchCount(FetchDescriptor<Asset>()),
            1
        )
        let diagnostics = await diagnosticsStore.snapshot()
        XCTAssertEqual(diagnostics, .zero)
    }

    @MainActor
    private func assertFirstSignRoundTrip(
        input: FirstSignInput,
        expectedSiteLabel: String,
        expectedSignLabel: String,
        expectedAddress: String?,
        expectedTimeZoneID: String?
    ) async throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer {
            if !FirstSignFixtureWriterReleaseV1.retains(root: root) {
                try? fileManager.removeItem(at: root)
            }
        }

        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let pack = SignPack.illuminatedSignV1
        let diagnosticsStore = DiagnosticsStore(applicationSupportURL: root)
        let created = try await createVerifyAndRelease(
            input: input,
            factory: factory,
            root: root,
            diagnosticsStore: diagnosticsStore,
            pack: pack,
            expectedSiteLabel: expectedSiteLabel,
            expectedSignLabel: expectedSignLabel,
            expectedAddress: expectedAddress,
            expectedTimeZoneID: expectedTimeZoneID
        )
        try assertOnlyFirstSignCreated(await diagnosticsStore.snapshot())

        let reopenedSession = try factory.openOrBootstrapCurrent()
        let reopenedDiagnosticsStore = DiagnosticsStore(applicationSupportURL: root)
        let firstSignProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let firstSignRegistry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [firstSignProfile])
        let firstSignOwner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: reopenedSession,
            profileRegistry: firstSignRegistry, root: root)
        defer {
            do { try FirstSignFixtureWriterReleaseV1.close(firstSignOwner, session: reopenedSession, root: root) }
            catch { XCTFail("First-sign fixture writer release failed: \(error)") }
        }
        let firstSignDependencies = try firstSignOwner.packageLifecycleDependencies(profileRegistry: firstSignRegistry)
        let reopenedCoordinator = try FirstSignCoordinator(
            modelContext: reopenedSession.modelContext,
            diagnosticsStore: reopenedDiagnosticsStore,
            packageLifecycleDependencies: firstSignDependencies,
            packageLifecycleProfile: firstSignProfile
        )
        let reopened = try XCTUnwrap(reopenedCoordinator.load())

        XCTAssertEqual(reopened, created)
        assertSnapshot(
            reopened,
            siteLabel: expectedSiteLabel,
            signLabel: expectedSignLabel,
            address: expectedAddress,
            timeZoneID: expectedTimeZoneID,
            pack: pack
        )
        try assertStoredRows(
            sites: reopenedSession.modelContext.fetch(FetchDescriptor<Site>()),
            assets: reopenedSession.modelContext.fetch(FetchDescriptor<Asset>()),
            snapshot: reopened
        )
        try assertOnlyFirstSignCreated(await reopenedDiagnosticsStore.snapshot())
    }

    @MainActor
    private func createVerifyAndRelease(
        input: FirstSignInput,
        factory: StoreGenerationFactory,
        root: URL,
        diagnosticsStore: DiagnosticsStore,
        pack: SignPack,
        expectedSiteLabel: String,
        expectedSignLabel: String,
        expectedAddress: String?,
        expectedTimeZoneID: String?
    ) async throws -> FirstSignSnapshot {
        let session = try factory.openOrBootstrapCurrent()
        let firstSignProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let firstSignRegistry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [firstSignProfile])
        let firstSignOwner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: session,
            profileRegistry: firstSignRegistry, root: root)
        var closeAttempted = false
        defer {
            if !closeAttempted {
                do { try FirstSignFixtureWriterReleaseV1.close(firstSignOwner, session: session, root: root) }
                catch { XCTFail("First-sign fixture writer release failed: \(error)") }
            }
        }
        let firstSignDependencies = try firstSignOwner.packageLifecycleDependencies(profileRegistry: firstSignRegistry)
        let coordinator = try FirstSignCoordinator(
            modelContext: session.modelContext,
            diagnosticsStore: diagnosticsStore,
            packageLifecycleDependencies: firstSignDependencies,
            packageLifecycleProfile: firstSignProfile
        )
        let created = try await coordinator.create(input)

        assertSnapshot(
            created,
            siteLabel: expectedSiteLabel,
            signLabel: expectedSignLabel,
            address: expectedAddress,
            timeZoneID: expectedTimeZoneID,
            pack: pack
        )
        try assertStoredRows(
            sites: session.modelContext.fetch(FetchDescriptor<Site>()),
            assets: session.modelContext.fetch(FetchDescriptor<Asset>()),
            snapshot: created
        )
        closeAttempted = true
        try FirstSignFixtureWriterReleaseV1.close(firstSignOwner, session: session, root: root)
        return created
    }

    private func assertSnapshot(
        _ snapshot: FirstSignSnapshot,
        siteLabel: String,
        signLabel: String,
        address: String?,
        timeZoneID: String?,
        pack: SignPack,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(snapshot.id, snapshot.assetID, file: file, line: line)
        XCTAssertEqual(snapshot.siteLabel, siteLabel, file: file, line: line)
        XCTAssertEqual(snapshot.signLabel, signLabel, file: file, line: line)
        XCTAssertEqual(snapshot.address, address, file: file, line: line)
        XCTAssertEqual(snapshot.timeZoneID, timeZoneID, file: file, line: line)
        XCTAssertEqual(snapshot.packID, pack.packID, file: file, line: line)
        XCTAssertEqual(snapshot.packSchemaVersion, pack.schemaVersion, file: file, line: line)
        XCTAssertEqual(snapshot.packContentVersion, pack.contentVersion, file: file, line: line)
    }

    private func assertStoredRows(
        sites: [Site],
        assets: [Asset],
        snapshot: FirstSignSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(sites.count, 1, file: file, line: line)
        XCTAssertEqual(assets.count, 1, file: file, line: line)

        let site = try XCTUnwrap(sites.first, file: file, line: line)
        let asset = try XCTUnwrap(assets.first, file: file, line: line)
        XCTAssertEqual(site.id, snapshot.siteID, file: file, line: line)
        XCTAssertEqual(site.schemaVersion, 1, file: file, line: line)
        XCTAssertEqual(site.label, snapshot.siteLabel, file: file, line: line)
        XCTAssertEqual(site.address, snapshot.address, file: file, line: line)
        XCTAssertEqual(site.timeZoneID, snapshot.timeZoneID, file: file, line: line)
        XCTAssertEqual(asset.id, snapshot.assetID, file: file, line: line)
        XCTAssertEqual(asset.schemaVersion, 1, file: file, line: line)
        XCTAssertEqual(asset.siteID, site.id, file: file, line: line)
        XCTAssertEqual(asset.label, snapshot.signLabel, file: file, line: line)
        XCTAssertEqual(asset.packID, snapshot.packID, file: file, line: line)
        XCTAssertEqual(asset.packSchemaVersion, snapshot.packSchemaVersion, file: file, line: line)
        XCTAssertEqual(asset.packContentVersion, snapshot.packContentVersion, file: file, line: line)
    }

    private func assertOnlyFirstSignCreated(
        _ snapshot: DiagnosticsV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(snapshot.firstSignCreated, 1, file: file, line: line)
        XCTAssertEqual(snapshot.onboardingCompleted, 0, file: file, line: line)
        XCTAssertEqual(snapshot.paywallPresented, 0, file: file, line: line)
        XCTAssertEqual(snapshot.purchaseResult, .zero, file: file, line: line)
        XCTAssertEqual(snapshot.recheckCompleted, 0, file: file, line: line)
        XCTAssertEqual(snapshot.reportSaved, 0, file: file, line: line)
        XCTAssertEqual(snapshot.reportShareSheetPresented, 0, file: file, line: line)
        XCTAssertEqual(snapshot.schemaVersion, 1, file: file, line: line)
    }

    private func makeTemporaryApplicationSupportURL() throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("S2SignSetupTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

// Failure retention is shared only by these three legacy fixture migrations.
// A failed close must keep its owner graph and physical root for diagnosis.
@MainActor
enum FirstSignFixtureWriterReleaseV1 {
    private static var failed: [(root: URL, session: StoreGenerationSession, owner: StoreSessionCoordinator)] = []
    private static var failedConstruction: [(root: URL, session: StoreGenerationSession, error: any Error)] = []

    static func retains(root: URL) -> Bool {
        failed.contains { $0.root.standardizedFileURL == root.standardizedFileURL }
            || failedConstruction.contains { $0.root.standardizedFileURL == root.standardizedFileURL }
    }

    static func makeOwner(session: StoreGenerationSession,
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1, root: URL) throws -> StoreSessionCoordinator {
        do {
            return try StoreSessionCoordinator(validatingSession: session,
                lifecycleProfileRegistry: profileRegistry)
        } catch {
            // The actual construction error may own an unclosed writer lease.
            // Retain it with the session and physical root; never retry here.
            failedConstruction.append((root, session, error))
            throw error
        }
    }

    static func close(_ owner: StoreSessionCoordinator, session: StoreGenerationSession, root: URL) throws {
        do {
            try owner.invalidateAndReleaseWriter()
        } catch {
            failed.append((root, session, owner))
            throw error
        }
    }
}

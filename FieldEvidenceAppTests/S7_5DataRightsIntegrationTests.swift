import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S7_5DataRightsIntegrationTests: XCTestCase {
    private let fileManager = FileManager.default
    private let bundleID = "com.palatis3.fieldrecord"

    @MainActor
    func testFormerPaidBlocksOnlyNewValueAndKeepsExactDraftAndDataServices()
        async throws {
        let root = try makeApplicationSupport("lapse")
        defer { try? fileManager.removeItem(at: root) }
        let session = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        let diagnostics = DiagnosticsStore(applicationSupportURL: root)
        var access = DraftAccessNormalizedStateV1.entitled
        let signs = FirstSignCoordinator(
            modelContext: session.modelContext,
            diagnosticsStore: diagnostics,
            signPack: .illuminatedSignV1,
            accessState: { access }
        )
        let first = try await signs.create(FirstSignInput(
            siteLabel: "Lapse site",
            signLabel: "Existing draft sign",
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true
        ))
        let second = try await signs.create(FirstSignInput(
            existingSiteID: first.siteID,
            siteLabel: "",
            signLabel: "New-value sign"
        ))
        let runner = CheckRunnerCoordinator(
            modelContext: session.modelContext,
            signPack: .illuminatedSignV1,
            diagnosticsStore: diagnostics,
            draftAccessState: { access }
        )
        let draft = try runner.beginOrResumeDraft(BeginDraftSubmission(
            assetID: first.assetID,
            requestedStage: .check,
            issueID: nil,
            observedAtUTC: Date().addingTimeInterval(-60),
            confirmedTimeZoneID: nil,
            afterDarkAccepted: true,
            safePositionAccepted: true
        ))

        access = .formerPaidInactive
        XCTAssertEqual(
            try signs.accessDecisionForCreateSign(),
            .blockPaid
        )
        XCTAssertEqual(
            try runner.accessDecision(
                assetID: second.assetID,
                requestedStage: .check,
                issueID: nil
            ),
            .blockPaid
        )
        XCTAssertEqual(
            try runner.accessDecision(
                assetID: first.assetID,
                requestedStage: .check,
                issueID: nil
            ),
            .continueExisting
        )
        XCTAssertEqual(
            try runner.beginOrResumeDraft(
                assetID: first.assetID,
                requestedStage: .check,
                issueID: nil
            ).id,
            draft.id
        )

        let reportDelivery = try ReportDeliveryCoordinator(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            diagnosticsStore: diagnostics
        )
        _ = reportDelivery
        let backup = BackupExportService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_900_000_000) },
            appVersion: { "1.0" },
            appBuild: { "1" }
        )
        let preview = try backup.prepare()
        XCTAssertEqual(preview.signCount, 2)
        XCTAssertEqual(preview.reportCount, 0)
        XCTAssertEqual(preview.photoCount, 0)
        XCTAssertEqual(
            try session.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            1
        )

        _ = try await WholeSignDeletionService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL
        ).delete(assetID: first.assetID)
        XCTAssertEqual(try signs.loadAll().map(\.assetID), [second.assetID])
        XCTAssertEqual(
            try session.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            0
        )
    }

    @MainActor
    func testActiveEraseClearsLocalAuthorityThenOrdinaryRefreshRediscovers()
        async throws {
        let paths = try makeErasePaths("active")
        defer { try? fileManager.removeItem(at: paths.root) }
        let factory = StoreGenerationFactory(applicationSupportURL: paths.support)
        var coordinator: StoreSessionCoordinator? = StoreSessionCoordinator(
            session: try factory.openOrBootstrapCurrent()
        )
        let createdAt = Date(timeIntervalSince1970: 1_800_500_000)
        let siteID = UUID()
        try insertEraseRows(
            into: try XCTUnwrap(coordinator).modelContext,
            siteID: siteID,
            createdAt: createdAt
        )

        let entitlementNow = Date(
            timeIntervalSince1970: floor(Date().timeIntervalSince1970)
        )
        let cache = EntitlementCacheV1(
            productID: EntitlementReducerV1.productID,
            state: .active,
            expirationAt: entitlementNow.addingTimeInterval(3_600),
            graceExpirationAt: nil,
            revocationAt: nil,
            verifiedAt: entitlementNow,
            hasEverVerifiedPaid: true
        )
        _ = try EntitlementStore(applicationSupportURL: paths.support)
            .persist(cache)
        let commerceURL = paths.support.appendingPathComponent(
            "FieldEvidenceCommerce",
            isDirectory: true
        )
        XCTAssertTrue(fileManager.fileExists(atPath: commerceURL.path))

        let diagnostics = DiagnosticsStore(applicationSupportURL: paths.support)
        await diagnostics.prepare()
        await diagnostics.increment(.reportSaved)
        let defaultsName = "S7_5-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: bundleID)
            defaults.removePersistentDomain(forName: defaultsName)
        }
        let activeCoordinator = try XCTUnwrap(coordinator)
        let erased = try await EraseAllService(
            applicationSupportURL: paths.support,
            cachesDirectoryURL: paths.caches,
            temporaryDirectoryURL: paths.temporary,
            userDefaults: defaults,
            bundleIdentifier: bundleID
        ).erase(
            confirmation: "ERASE",
            coordinator: activeCoordinator,
            diagnosticsStore: diagnostics
        ) { session in
            activeCoordinator.activate(session: session)
        }
        XCTAssertFalse(erased.cleanupDeferred)
        XCTAssertEqual(try rowCounts(erased.session.modelContext), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertFalse(fileManager.fileExists(atPath: commerceURL.path))
        let diagnosticsAfterErase = await diagnostics.snapshot()
        XCTAssertEqual(diagnosticsAfterErase, .zero)
        coordinator = nil
        await Task.yield()

        let probe = CommerceRuntimeProbe()
        let expiration = entitlementNow.addingTimeInterval(7_200)
        let fact = VerifiedEntitlementFactV1(
            productID: EntitlementReducerV1.productID,
            purchaseAt: entitlementNow.addingTimeInterval(-3_600),
            expirationAt: expiration,
            verifiedAt: entitlementNow,
            state: .active
        )
        let router = StartupRouter(
            applicationSupportURL: paths.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(
                initialEvents: {
                    await probe.recordRefresh()
                    return [.verified(.init(fact: fact))]
                },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }
            )
        )
        await router.startIfNeeded()
        await router.entitlementProcessor?.waitForInitialRefresh()

        guard case let .ready(reopened, _, _) = router.route else {
            return XCTFail("Cold launch must reopen the erased generation.")
        }
        XCTAssertEqual(try rowCounts(reopened.modelContext), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(
            router.entitlementProcessor?.state,
            .entitled(.active, until: expiration)
        )
        XCTAssertEqual(router.entitlementProcessor?.draftAccessState, .entitled)
        let refreshCount = await probe.refreshCount
        let syncCount = await probe.syncCount
        let finishCount = await probe.finishCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(syncCount, 0)
        XCTAssertEqual(finishCount, 0)
        router.entitlementProcessor?.stop()
    }
}

private extension S7_5DataRightsIntegrationTests {
    struct ErasePaths {
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
    }

    func makeApplicationSupport(_ name: String) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S7_5-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func makeErasePaths(_ name: String) throws -> ErasePaths {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S7_5-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        return ErasePaths(root: root, support: support, caches: caches, temporary: temporary)
    }

    @MainActor
    func rowCounts(_ context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<Site>()),
            try context.fetchCount(FetchDescriptor<Asset>()),
            try context.fetchCount(FetchDescriptor<WorkflowRecord>()),
            try context.fetchCount(FetchDescriptor<EvidenceFile>()),
            try context.fetchCount(FetchDescriptor<Issue>()),
            try context.fetchCount(FetchDescriptor<Packet>()),
            try context.fetchCount(FetchDescriptor<Report>()),
        ]
    }

    @MainActor
    func insertEraseRows(
        into context: ModelContext,
        siteID: UUID,
        createdAt: Date
    ) throws {
        context.insert(Site(
            id: siteID,
            label: "Erase site",
            address: nil,
            timeZoneID: "America/New_York",
            createdAt: createdAt
        ))
        context.insert(Asset(
            id: UUID(),
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Erase sign",
            createdAt: createdAt.addingTimeInterval(1)
        ))
        context.insert(Packet(
            id: UUID(),
            stableRootID: UUID(),
            currentRecordID: nil,
            evaluationCounted: true,
            contentDeletedAt: createdAt.addingTimeInterval(3),
            createdAt: createdAt.addingTimeInterval(2)
        ))
        try context.save()
    }
}

private actor CommerceRuntimeProbe {
    private(set) var refreshCount = 0
    private(set) var syncCount = 0
    private(set) var finishCount = 0

    func recordRefresh() { refreshCount += 1 }
    func recordSync() { syncCount += 1 }
    func recordFinish() { finishCount += 1 }
}

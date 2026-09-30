import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class S7_2PaywallPurchaseTests: XCTestCase {
    private let validPresentation = PaywallProductPresentationV1(
        productID: EntitlementReducerV1.productID,
        displayName: "Solo Access Monthly",
        displayPrice: "$59.99",
        subscriptionDuration: "1 month",
        isEligibleForIntroOffer: true
    )

    func testLocalizedPresentationLinksEligibilityAndPresentationTokenOnce() async throws {
        let harness = try makeHarness("presentation")
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let coordinator = StoreKitPurchaseCoordinator(
            diagnosticsStore: harness.diagnostics,
            catalogLinks: .uiTestFixture,
            presentationLoader: { self.validPresentation }
        )
        let token = UUID()

        await coordinator.present(token: token)
        await coordinator.present(token: token)

        XCTAssertEqual(coordinator.loadState, .available)
        XCTAssertEqual(coordinator.productPresentation, validPresentation)
        XCTAssertTrue(coordinator.productPresentation?.isEligibleForIntroOffer == true)
        let presentationDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertEqual(presentationDiagnostics.paywallPresented, 1)

        let ineligible = PaywallProductPresentationV1(
            productID: EntitlementReducerV1.productID,
            displayName: "Solo Access Monthly",
            displayPrice: "$59.99",
            subscriptionDuration: "1 month",
            isEligibleForIntroOffer: false
        )
        let other = StoreKitPurchaseCoordinator(
            diagnosticsStore: harness.diagnostics,
            catalogLinks: .uiTestFixture,
            presentationLoader: { ineligible }
        )
        await other.present(token: UUID())
        XCTAssertEqual(other.productPresentation, ineligible)
        XCTAssertFalse(other.productPresentation?.isEligibleForIntroOffer == true)

        XCTAssertEqual(PaywallCatalogLinksV1.uiTestFixture.terms.absoluteString,
                       "https://example.invalid/terms")
        XCTAssertEqual(PaywallCatalogLinksV1.uiTestFixture.privacy.absoluteString,
                       "https://example.invalid/privacy")
        XCTAssertEqual(PaywallCatalogLinksV1.uiTestFixture.support.absoluteString,
                       "https://example.invalid/support")
        XCTAssertNil(PaywallCatalogLinksV1(
            terms: URL(string: "http://example.invalid/terms"),
            privacy: PaywallCatalogLinksV1.uiTestFixture.privacy,
            support: PaywallCatalogLinksV1.uiTestFixture.support
        ))
    }

    func testTerminalPurchaseTableHasExactCopyOneBucketAndReleasesLock() async throws {
        let rows: [(PaywallPurchaseAttemptV1, PaywallPurchaseStateV1, String)] = [
            (.cancelled, .cancelled,
             "Purchase canceled. Nothing changed. You can try again when you’re ready."),
            (.pending, .pending,
             "Purchase pending. Your existing data is still available. Access will update when the App Store completes the purchase."),
            (.unverified, .unverified,
             "Purchase couldn’t be verified. Your existing data is still available. Try again."),
            (.failed, .failed,
             "Purchase couldn’t be completed. Your existing data is still available. Try again."),
        ]

        for (index, row) in rows.enumerated() {
            let harness = try makeHarness("terminal-\(index)")
            defer { try? FileManager.default.removeItem(at: harness.root) }
            let coordinator = makeCoordinator(harness.diagnostics)
            await coordinator.present(token: UUID())
            XCTAssertTrue(coordinator.purchaseStarted(
                productID: EntitlementReducerV1.productID
            ))
            await coordinator.complete(row.0)

            XCTAssertEqual(coordinator.purchaseState, row.1)
            XCTAssertEqual(coordinator.purchaseState.recoveryMessage, row.2)
            XCTAssertFalse(coordinator.isPurchasing)
            let histogram = (await harness.diagnostics.snapshot()).purchaseResult
            let counts = [histogram.cancelled, histogram.pending,
                          histogram.unverified, histogram.failed]
            XCTAssertEqual(counts.reduce(0, +), 1)
            XCTAssertEqual(counts[index], 1)

            await coordinator.complete(row.0)
            let afterReplay = await harness.diagnostics.snapshot()
            XCTAssertEqual(afterReplay.purchaseResult, histogram)
        }
    }

    func testVerifiedAwaitsDurabilityAndCountsExactlyOnce() async throws {
        let harness = try makeHarness("verified")
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let probe = DurableProbe()
        let coordinator = makeCoordinator(harness.diagnostics)
        await coordinator.present(token: UUID())
        XCTAssertTrue(coordinator.purchaseStarted(
            productID: EntitlementReducerV1.productID
        ))

        await coordinator.complete(.verified { [weak coordinator] in
            XCTAssertEqual(coordinator?.purchaseState, .purchasing)
            await probe.persistAndReopen()
            return await probe.isDurable ? .verified : .failed
        })

        XCTAssertEqual(coordinator.purchaseState, .verified)
        XCTAssertFalse(coordinator.isPurchasing)
        let durable = await probe.isDurable
        let callCount = await probe.callCount
        let verifiedDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertTrue(durable)
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(
            verifiedDiagnostics.purchaseResult,
            PurchaseResultHistogram(
                cancelled: 0, failed: 0, pending: 0, unverified: 0, verified: 1
            )
        )
        await coordinator.complete(.verified { .verified })
        let replayCallCount = await probe.callCount
        let replayDiagnostics = await harness.diagnostics.snapshot()
        XCTAssertEqual(replayCallCount, 1)
        XCTAssertEqual(replayDiagnostics.purchaseResult.verified, 1)
    }

    func testWrongDoubleUnavailableAndCounterFailureFailClosed() async throws {
        let harness = try makeHarness("negative")
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let coordinator = makeCoordinator(harness.diagnostics)
        await coordinator.present(token: UUID())
        XCTAssertFalse(coordinator.purchaseStarted(productID: "wrong.product"))
        XCTAssertTrue(coordinator.purchaseStarted(
            productID: EntitlementReducerV1.productID
        ))
        XCTAssertFalse(coordinator.purchaseStarted(
            productID: EntitlementReducerV1.productID
        ))
        await coordinator.complete(.pending)
        XCTAssertEqual(coordinator.purchaseState, .pending)

        let unavailable = StoreKitPurchaseCoordinator(
            diagnosticsStore: harness.diagnostics,
            catalogLinks: .uiTestFixture,
            presentationLoader: { throw ProbeError.unavailable }
        )
        await unavailable.present(token: UUID())
        XCTAssertEqual(unavailable.loadState, .unavailable)
        XCTAssertNil(unavailable.productPresentation)
        XCTAssertFalse(unavailable.purchaseStarted(
            productID: EntitlementReducerV1.productID
        ))

        let invalid = StoreKitPurchaseCoordinator(
            diagnosticsStore: harness.diagnostics,
            catalogLinks: .uiTestFixture,
            presentationLoader: {
                PaywallProductPresentationV1(
                    productID: "wrong.product",
                    displayName: "Solo Access Monthly",
                    displayPrice: "$59.99",
                    subscriptionDuration: "1 month",
                    isEligibleForIntroOffer: true
                )
            }
        )
        await invalid.present(token: UUID())
        XCTAssertEqual(invalid.loadState, .unavailable)

        let failedHarness = try makeHarness("counter-failure", blockCounters: true)
        defer { try? FileManager.default.removeItem(at: failedHarness.root) }
        let counterFailure = makeCoordinator(failedHarness.diagnostics)
        await counterFailure.present(token: UUID())
        XCTAssertTrue(counterFailure.purchaseStarted(
            productID: EntitlementReducerV1.productID
        ))
        await counterFailure.complete(.failed)
        XCTAssertEqual(counterFailure.purchaseState, .failed)
        XCTAssertFalse(counterFailure.isPurchasing)
        let failedDiagnostics = await failedHarness.diagnostics.snapshot()
        XCTAssertEqual(failedDiagnostics, .zero)
    }

    func testStoreKitReservationPublishesAfterPresentationAndCancelsStaleState() async throws {
        let harness = try makeHarness("storekit-reservation")
        defer { try? FileManager.default.removeItem(at: harness.root) }

        let published = makeCoordinator(harness.diagnostics)
        await published.present(token: UUID())
        XCTAssertTrue(published.storeKitPurchaseStarted(
            productID: EntitlementReducerV1.productID
        ))
        XCTAssertFalse(published.isPurchasing)
        XCTAssertEqual(published.purchaseState, .idle)
        XCTAssertFalse(published.storeKitPurchaseStarted(
            productID: EntitlementReducerV1.productID
        ))
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(published.isPurchasing)
        XCTAssertEqual(published.purchaseState, .purchasing)
        await published.complete(.cancelled)
        XCTAssertFalse(published.isPurchasing)
        XCTAssertEqual(published.purchaseState, .cancelled)

        let completedEarly = makeCoordinator(harness.diagnostics)
        await completedEarly.present(token: UUID())
        XCTAssertTrue(completedEarly.storeKitPurchaseStarted(
            productID: EntitlementReducerV1.productID
        ))
        await completedEarly.complete(.pending)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(completedEarly.isPurchasing)
        XCTAssertEqual(completedEarly.purchaseState, .pending)
    }
}

private extension S7_2PaywallPurchaseTests {
    enum ProbeError: Error { case unavailable }

    actor DurableProbe {
        private(set) var isDurable = false
        private(set) var callCount = 0

        func persistAndReopen() {
            callCount += 1
            isDurable = true
        }
    }

    struct Harness {
        let root: URL
        let diagnostics: DiagnosticsStore
    }

    func makeHarness(_ name: String, blockCounters: Bool = false) throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "S7_2-\(name)-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false
        )
        if blockCounters {
            try Data("blocked".utf8).write(to: root.appendingPathComponent(
                "FieldEvidenceDiagnostics"
            ))
        }
        return Harness(
            root: root,
            diagnostics: DiagnosticsStore(applicationSupportURL: root)
        )
    }

    func makeCoordinator(
        _ diagnostics: DiagnosticsStore
    ) -> StoreKitPurchaseCoordinator {
        StoreKitPurchaseCoordinator(
            diagnosticsStore: diagnostics,
            catalogLinks: .uiTestFixture,
            presentationLoader: { self.validPresentation }
        )
    }
}

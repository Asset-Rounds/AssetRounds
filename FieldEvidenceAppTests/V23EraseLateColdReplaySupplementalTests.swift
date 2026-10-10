import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23EraseLateColdReplaySupplementalTests: XCTestCase {
    func testDeleteCommittedThenAfterCleanupColdReplayRequiresCompleteAuthority() async throws {
        // Supplemental I01 prefix; the full fault matrices remain separate.
        let boundaries = ["DELETE_COMMITTED_PHASE", "ERASE_AFTER_CLEANUP"]
        let harness = try KernelConformanceProductionHarnessV1(
            label: "delete-committed-then-erase-after-cleanup-supplement"
        )
        defer { harness.cleanup() }

        let receipts = try await harness.exerciseProductionFaultBoundaries(boundaries)
        XCTAssertEqual(receipts.count, 2)
        XCTAssertEqual(receipts.map(\.boundary), boundaries)
        XCTAssertEqual(receipts.map(\.family), ["DELETE", "ERASE"])
        for receipt in receipts {
            XCTAssertFalse(receipt.family.isEmpty, receipt.boundary)
            XCTAssertFalse(receipt.visibleFailure.isEmpty, receipt.boundary)
            XCTAssertFalse(receipt.operationAttempted.isEmpty, receipt.boundary)
            XCTAssertFalse(receipt.recoveryOperation.isEmpty, receipt.boundary)
            XCTAssertTrue(receipt.coldRecoverySucceeded, receipt.boundary)
            XCTAssertTrue(receipt.noPartialAuthority, receipt.boundary)
            XCTAssertGreaterThanOrEqual(receipt.canonicalRowCount, 0, receipt.boundary)
            XCTAssertEqual(receipt.residualIntentCount, 0, receipt.boundary)
            XCTAssertEqual(receipt.orphanPathCount, 0, receipt.boundary)
        }

        let eraseReceipt = try XCTUnwrap(receipts.last)
        XCTAssertEqual(eraseReceipt.boundary, "ERASE_AFTER_CLEANUP")
        XCTAssertEqual(
            eraseReceipt.visibleFailure,
            String(describing: EraseAllServiceError.injectedFailure)
        )
        XCTAssertEqual(eraseReceipt.canonicalRowCount, 0)
    }
}

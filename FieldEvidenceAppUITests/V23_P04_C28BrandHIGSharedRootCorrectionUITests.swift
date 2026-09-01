import Foundation
import XCTest

final class V23_P04_C28BrandHIGSharedRootCorrectionUITests: XCTestCase {
    func testV23P04C28G01LowestOwnerCorrectionsCloseC27FindingsAndPreserveHistoricReportsUI() throws {
        let source = try feedbackUISource()
        for semanticID in stableMailSemanticIDs {
            XCTAssertTrue(source.contains("\"\(semanticID)\""), semanticID)
        }
        XCTAssertFalse(source.contains("s8.4.mail."))
    }

    func testV23P04C28A01NativeSemanticParityPreservesTasksIdentityAndHistoricBytesUI() throws {
        throw XCTSkip("V23-P04-C28-A01: minimum/latest-runtime native semantic parity remains pending accepted S10.6 and hosted macOS evidence; this static correction earns no UI acceptance credit.")
    }

    func testV23P04C28H01SharedStateRoleAXContrastClaimsAndReportDriftFailClosedUI() throws {
        throw XCTSkip("V23-P04-C28-H01: AX5 plus dark/increased-contrast hostile rendering requires hosted native evidence after accepted S10.6; no UI acceptance credit is claimed.")
    }

    func testV23P04C28I01InterruptedCorrectionPreservesAcceptedC27BaselineAndNoPartialReceiptUI() throws {
        throw XCTSkip("V23-P04-C28-I01: manifest-last repository interruption is non-UI evidence; native UI reconciliation remains pending accepted S10.6 with no acceptance credit.")
    }

    func testV23P04C28R01RejectedDirectionAndFailedRetryPreserveAcceptedBrandRevisionUI() throws {
        throw XCTSkip("V23-P04-C28-R01: rejected direction and retry preserve the provisional C27 baseline; native adoption remains pending accepted S10.6 and earns no UI acceptance credit.")
    }

    private let stableMailSemanticIDs = [
        "feedback.mail.attachment-count",
        "feedback.mail.body",
        "feedback.mail.done",
        "feedback.mail.recipient",
        "feedback.mail.screen",
    ]

    private func feedbackUISource() throws -> String {
        let uiTestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = uiTestsDirectory.appendingPathComponent("S8_4FeedbackUITests.swift")
        return String(decoding: try Data(contentsOf: sourceURL), as: UTF8.self)
    }
}

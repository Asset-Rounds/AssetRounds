import Foundation
import MessageUI
import XCTest
@testable import FieldEvidenceApp

final class V23_P00_C11MailComposerConcurrencyTests: XCTestCase {
    @MainActor
    func testEveryMailOutcomeCompletesExactlyOnceOnMainActor() {
        let cases: [(MFMailComposeResult, FeedbackMailResultV1)] = [
            (.cancelled, .cancelled),
            (.failed, .failed),
            (.saved, .saved),
            (.sent, .sent),
        ]

        for (mailResult, expected) in cases {
            var observed: [FeedbackMailResultV1] = []
            let coordinator = MailComposerCoordinator { result in
                MainActor.preconditionIsolated()
                observed.append(result)
            }
            let controller = MFMailComposeViewController()

            coordinator.mailComposeController(
                controller,
                didFinishWith: mailResult,
                error: nil
            )
            coordinator.mailComposeController(
                controller,
                didFinishWith: .failed,
                error: NSError(domain: "V23-P00-C11", code: 1)
            )

            XCTAssertEqual(observed, [expected])
        }
    }

    @MainActor
    func testErrorOverridesMessageUIResultAndDuplicateCompletionIsIgnored() {
        var observed: [FeedbackMailResultV1] = []
        let coordinator = MailComposerCoordinator { observed.append($0) }

        coordinator.mailComposeController(
            MFMailComposeViewController(),
            didFinishWith: .sent,
            error: NSError(domain: "V23-P00-C11", code: 2)
        )
        coordinator.complete(.saved)

        XCTAssertEqual(observed, [.failed])
    }

    func testResultMappingDoesNotCrossMessageUIValuesIntoMainActor() {
        XCTAssertEqual(
            MailComposerCoordinator.outcome(for: .cancelled, hasError: false),
            .cancelled
        )
        XCTAssertEqual(
            MailComposerCoordinator.outcome(for: .failed, hasError: false),
            .failed
        )
        XCTAssertEqual(
            MailComposerCoordinator.outcome(for: .saved, hasError: false),
            .saved
        )
        XCTAssertEqual(
            MailComposerCoordinator.outcome(for: .sent, hasError: false),
            .sent
        )
        XCTAssertEqual(
            MailComposerCoordinator.outcome(for: .sent, hasError: true),
            .failed
        )
    }
}

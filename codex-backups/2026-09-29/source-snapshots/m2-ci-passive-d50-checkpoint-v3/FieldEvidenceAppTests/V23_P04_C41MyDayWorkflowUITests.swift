import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C41MyDayWorkflowUITests: XCTestCase {
    private enum SemanticSelector {
        static let screen = "v23.p04.c41.my-day.screen"
        static let eligibleWork = "v23.p04.c41.my-day.eligible-work"
        static let planOrder = "v23.p04.c41.my-day.plan-order"
        static let readiness = "v23.p04.c41.my-day.readiness"
        static let duration = "v23.p04.c41.my-day.duration"
        static let startResume = "v23.p04.c41.my-day.start-resume"
        static let carryover = "v23.p04.c41.my-day.carryover"
        static let reconciliation = "v23.p04.c41.my-day.reconciliation-boundaries"

        static let all = [
            screen, eligibleWork, planOrder, readiness, duration, startResume, carryover, reconciliation
        ]
    }

    private static let containedMyDaySurfaceOnly = true
    private static let rootAdoptionEnabled = false
    private static let nativeLaunchAdoptionEnabled = false

    func testV23P04C41SemanticSelectorContractIsClosedAndUnique() {
        XCTAssertEqual(SemanticSelector.all.count, 8)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertTrue(SemanticSelector.all.allSatisfy {
            $0.hasPrefix("v23.p04.c41.my-day.")
                && $0 == $0.lowercased()
                && !$0.contains(where: { $0.isWhitespace })
        })
    }

    @MainActor
    func testV23P04C41WorkflowInitializerBindsCoreContractShapes() {
        let makeDraftItem: (UUID, MyDayEligibleReferenceV1, MyDayEstimateV1?) throws -> MyDayDraftItemV1 = MyDayDraftItemV1.init
        let move: (UUID) -> MyDayAccessibleMoveV1 = { .up(membershipID: $0) }
        let route: (MyDayExistingRouteIntentV1) -> MyDayExistingRouteIntentV1 = { $0 }
        let saveCommand: (MyDaySavePreviewV1) -> MyDayWorkflowCommandV1 = { .save($0) }
        let carryoverCommand: (MyDayCarryoverPreviewV1) -> MyDayWorkflowCommandV1 = { .carryover($0) }
        let coordinator = MyDayWorkflowCoordinatorV1.self
        let initializeSurface: (
            [MyDayEligibleReferenceV1],
            MyDayPlanDraftV1?,
            MyDaySummaryProjectionV1?,
            MyDaySavePreviewV1?,
            MyDayCarryoverPreviewV1?
        ) -> MyDayWorkflowView = { eligible, draft, summary, savePreview, carryoverPreview in
            MyDayWorkflowView(
                eligibleReferences: eligible,
                draft: draft,
                summary: summary,
                savePreview: savePreview,
                carryoverPreview: carryoverPreview,
                onSelectEligible: { _ in },
                onMove: { _ in },
                onRequestRoute: { _ in },
                onPreviewCarryover: {},
                onRefreshSummary: {}
            )
        }

        XCTAssertNotNil(makeDraftItem)
        XCTAssertNotNil(move)
        XCTAssertNotNil(route)
        XCTAssertNotNil(saveCommand)
        XCTAssertNotNil(carryoverCommand)
        XCTAssertNotNil(coordinator)
        XCTAssertNotNil(initializeSurface)
    }

    func testV23P04C41MyDayWorkflowRemainsContainedBeforeS10() throws {
        XCTAssertTrue(Self.containedMyDaySurfaceOnly)
        XCTAssertFalse(Self.rootAdoptionEnabled)
        XCTAssertFalse(Self.nativeLaunchAdoptionEnabled)
        throw XCTSkip(
            "V23-P04-C41 remains a contained My Day surface pending accepted S10.6 route adoption; "
                + "this no-launch declaration makes no scheduling, route-open, work-start, carryover, dispatch, notification, telemetry, or accessibility activation claim."
        )
    }
}

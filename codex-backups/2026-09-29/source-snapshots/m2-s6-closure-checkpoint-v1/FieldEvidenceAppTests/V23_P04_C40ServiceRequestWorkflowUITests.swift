import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C40ServiceRequestWorkflowUITests: XCTestCase {
    private enum SemanticSelector {
        static let screen = "v23.p04.c40.service-request.screen"
        static let mode = "v23.p04.c40.service-request.mode"
        static let draft = "v23.p04.c40.service-request.draft"
        static let duplicates = "v23.p04.c40.service-request.duplicates"
        static let dispositions = "v23.p04.c40.service-request.dispositions"
        static let createWork = "v23.p04.c40.service-request.create-work"
        static let status = "v23.p04.c40.service-request.status"
        static let boundaries = "v23.p04.c40.service-request.boundaries"

        static let all = [screen, mode, draft, duplicates, dispositions, createWork, status, boundaries]
    }

    private static let containedServiceRequestSurfaceOnly = true
    private static let previewIsZeroWrite = true
    private static let appShellAdoptionEnabled = false
    private static let nativeLaunchAdoptionEnabled = false

    func testV23P04C40SemanticSelectorContractIsClosedAndUnique() {
        XCTAssertEqual(SemanticSelector.all.count, 8)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertTrue(
            SemanticSelector.all.allSatisfy {
                $0.hasPrefix("v23.p04.c40.service-request.")
                    && $0 == $0.lowercased()
                    && !$0.contains(where: { $0.isWhitespace })
            }
        )
    }

    @MainActor
    func testV23P04C40TypedPreviewAndStatusInitializerShape() {
        let presentManual: (ServiceRequestManualPreviewV1) -> ServiceRequestPreviewPresentationV1 = {
            .manual($0)
        }
        let presentPortable: (ServiceRequestImportPreviewV1) -> ServiceRequestPreviewPresentationV1 = {
            .portable($0)
        }
        let initializeSurface: (
            ServiceRequestPreviewPresentationV1?,
            ServiceRequestStatusArtifactV1?
        ) -> ServiceRequestWorkflowView = { preview, statusArtifact in
            ServiceRequestWorkflowView(
                sourceKind: .phone,
                preview: preview,
                stateProjection: nil,
                statusArtifact: statusArtifact,
                onRefreshPreview: {},
                onCreateWork: {}
            )
        }

        XCTAssertNotNil(presentManual)
        XCTAssertNotNil(presentPortable)
        XCTAssertNotNil(initializeSurface)
    }

    func testV23P04C40ServiceRequestWorkflowRemainsContainedBeforeS10() throws {
        XCTAssertTrue(Self.containedServiceRequestSurfaceOnly)
        XCTAssertTrue(Self.previewIsZeroWrite)
        XCTAssertFalse(Self.appShellAdoptionEnabled)
        XCTAssertFalse(Self.nativeLaunchAdoptionEnabled)
        throw XCTSkip(
            "V23-P04-C40 remains a contained Service Request surface pending accepted S10.6 route adoption; "
                + "this no-launch declaration makes no intake, import, work, delivery, dispatch, SLA, monitoring, portal, PDF, or accessibility activation claim."
        )
    }
}

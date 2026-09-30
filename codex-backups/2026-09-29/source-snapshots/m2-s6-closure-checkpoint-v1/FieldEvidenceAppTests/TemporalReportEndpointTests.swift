import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Uses genuine released C33 constructors. This exercises the shared pure law;
/// it does not pretend a constructed value is held-FD report-source authority.
final class TemporalReportEndpointTests: XCTestCase {
    func testExactReportClipAndAnchorBindingsUseIncumbentLaw() throws {
        let fixture = try C33TemporalEvidenceTestSupport.clip(slot: 31)
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: fixture.clip, slot: 131)
        let report = try C33TemporalEvidenceTestSupport.reportSnapshot(clip: fixture.clip,
            anchors: [anchor], reportID: UUID(), slot: 231, includesAssurance: false)
        let clips = [fixture.clip.clipID: fixture.clip], anchors = [anchor.anchorID: anchor]
        XCTAssertNoThrow(try C33TemporalEvidencePackageValidationV1.validateReportLinks(report,
            sourceWorkspaceID: fixture.clip.workspaceID.rawValue, clipsByID: clips, anchorsByID: anchors))
        XCTAssertThrowsError(try C33TemporalEvidencePackageValidationV1.validateReportLinks(report,
            sourceWorkspaceID: UUID(), clipsByID: clips, anchorsByID: anchors))
        XCTAssertThrowsError(try C33TemporalEvidencePackageValidationV1.validateReportLinks(report,
            sourceWorkspaceID: fixture.clip.workspaceID.rawValue, clipsByID: [:], anchorsByID: anchors))
        XCTAssertThrowsError(try C33TemporalEvidencePackageValidationV1.validateReportLinks(report,
            sourceWorkspaceID: fixture.clip.workspaceID.rawValue, clipsByID: clips, anchorsByID: [:]))
        let foreign = try C33TemporalEvidenceTestSupport.clip(slot: 32)
        XCTAssertThrowsError(try C33TemporalEvidencePackageValidationV1.validateReportLinks(report,
            sourceWorkspaceID: fixture.clip.workspaceID.rawValue,
            clipsByID: [fixture.clip.clipID: foreign.clip], anchorsByID: anchors))
        let wrongAnchor = try C33TemporalEvidenceTestSupport.anchor(clip: foreign.clip, slot: 132)
        XCTAssertThrowsError(try C33TemporalEvidencePackageValidationV1.validateReportLinks(report,
            sourceWorkspaceID: fixture.clip.workspaceID.rawValue,
            clipsByID: clips, anchorsByID: [anchor.anchorID: wrongAnchor]))
    }
}

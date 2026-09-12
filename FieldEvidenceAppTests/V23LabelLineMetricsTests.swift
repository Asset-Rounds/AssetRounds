import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23LabelLineMetricsTests: XCTestCase {
    func testFrozenTenPixelLineBoxesContainOrdinaryFractionalAndFullHeightMetrics() throws {
        for bottom in [CGFloat(0), 10, 20] {
            for (ascent, descent) in [(CGFloat(5.5), CGFloat(1.5)), (7.25, 1), (8, 2)] {
                let baseline = try DeterministicPDFRendererV1.assetLabelTextBaseline(
                    ascent: ascent, descent: descent, lineBoxBottom: bottom)
                XCTAssertGreaterThanOrEqual(baseline - descent, bottom)
                XCTAssertLessThanOrEqual(baseline + ascent, bottom + 10)
                if ascent + descent <= 8 {
                    XCTAssertEqual(baseline, bottom + descent + 1)
                } else {
                    XCTAssertEqual(baseline - descent - bottom, bottom + 10 - baseline - ascent)
                }
            }
        }
    }

    func testMalformedAndOversizedMetricsStillFailClosed() {
        for (ascent, descent, bottom) in [
            (CGFloat(9), CGFloat(2), CGFloat(0)),
            (-1, 1, 0), (1, -1, 0), (1, 1, -1),
            (.nan, 1, 0), (1, .infinity, 0), (1, 1, .infinity)
        ] {
            XCTAssertThrowsError(try DeterministicPDFRendererV1.assetLabelTextBaseline(
                ascent: ascent, descent: descent, lineBoxBottom: bottom)) { error in
                XCTAssertEqual(error as? AssetLabelRenderFailureV1, .contentDoesNotFit)
            }
        }
    }
}

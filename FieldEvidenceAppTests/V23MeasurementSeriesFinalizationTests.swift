import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Focused check for the C19 series finalization cross-check: the bundled
/// evaluator records sample uncertainty on the provenance, not on the derived
/// measurement, and the independent aggregate is compared there exactly.
@MainActor
final class V23MeasurementSeriesFinalizationTests: XCTestCase {
    func testSeriesFinalizationBindsSampleUncertaintyThroughProvenance() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let captures = [fixture.capture, fixture.secondCapture]
        XCTAssertTrue(captures.allSatisfy { $0.measurement.uncertaintyCanonical != nil })
        let expected = try XCTUnwrap(MeasurementSeriesEvaluatorV1.aggregate(policy: .mean, captures: captures))
        let derived = try XCTUnwrap(fixture.series.derivedFact)
        let result = try XCTUnwrap(derived.result)
        XCTAssertEqual(result.canonicalValue, expected.canonicalValue)
        XCTAssertEqual(result.canonicalUnitID, expected.canonicalUnitID)
        XCTAssertNil(result.uncertaintyCanonical)
        XCTAssertEqual(derived.uncertaintyCanonical, expected.uncertaintyCanonical)
        XCTAssertNotNil(derived.uncertaintyCanonical)
    }
}

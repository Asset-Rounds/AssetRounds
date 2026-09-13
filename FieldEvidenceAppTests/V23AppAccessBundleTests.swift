import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23AppAccessBundleTests: XCTestCase {
    func testHostedAppBundlePublishesCanonicalFaceIDUsageDescription() throws {
        let appBundle = Bundle.main

        XCTAssertEqual(appBundle.bundleIdentifier, "com.palatis3.fieldrecord")
        let info = try XCTUnwrap(appBundle.infoDictionary)
        XCTAssertEqual(
            info["NSFaceIDUsageDescription"] as? String,
            AppLockCopyV1.faceIDPurpose
        )
    }
}

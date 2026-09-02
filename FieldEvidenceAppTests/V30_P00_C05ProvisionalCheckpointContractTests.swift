import CryptoKit
import Foundation
import XCTest

final class V30_P00_C05ProvisionalCheckpointContractTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private func bytes(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    private func object(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: bytes(path)) as? [String: Any])
    }

    private func digest(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }

    private func contract() throws -> [String: Any] {
        try object("docs/design/v30/contracts/V30ProvisionalCIAndCheckpointContractV1.json")
    }

    func testPinnedRouteAndWatchdogs() throws {
        let value = try contract()
        XCTAssertEqual(value["repository"] as? String, "Asset-Rounds/AssetRounds")
        XCTAssertEqual(value["branchRef"] as? String, "refs/heads/phase/v30-globalization")
        XCTAssertEqual(value["runner"] as? String, "macos-26")
        XCTAssertEqual(value["jobWatchdogMinutes"] as? Int, 90)
        XCTAssertEqual(value["cancelInProgress"] as? Bool, false)
        let environment = try XCTUnwrap(value["environment"] as? [String: String])
        XCTAssertEqual(environment["EXPECTED_XCODE_VERSION"], "Xcode 26.6")
        XCTAssertEqual(environment["EXPECTED_XCODE_BUILD"], "Build version 17F113")
        XCTAssertEqual(environment["SIMULATOR_RUNTIME"], "iOS 26.2")
        XCTAssertEqual(environment["SIMULATOR_NAME"], "iPhone 17")
        XCTAssertEqual(environment["CI_SIMULATOR_BOOT_TIMEOUT_SECONDS"], "900")
        XCTAssertEqual(environment["CODE_SIGNING_ALLOWED"], "NO")
        let tiers = try XCTUnwrap(value["tiers"] as? [String: [Int]])
        XCTAssertEqual(tiers["N8"], [300, 600, 900, 0, 2400])
        XCTAssertEqual(tiers["P12"], [300, 600, 900, 900, 3300])
        XCTAssertEqual(tiers["F25"], [300, 900, 1200, 1800, 4500])
    }

    func testRouteAndFilesRemainExactlyBound() throws {
        let value = try contract()
        let route = try object("docs/design/v30/execution/V30_PROVISIONAL_DEVELOPMENT_ROUTE_SELECTOR.json")
        let path = try XCTUnwrap(route["contractPath"] as? String)
        XCTAssertEqual(route["contractSHA256"] as? String, digest(try bytes(path)))
        let files = try XCTUnwrap(value["files"] as? [[String: String]])
        XCTAssertEqual(files.count, 6)
        for file in files {
            XCTAssertEqual(file["sha256"], digest(try bytes(XCTUnwrap(file["path"]))))
        }
        let sources = try XCTUnwrap(value["frozenSourceBindings"] as? [[String: Any]])
        XCTAssertEqual(sources.count, 3)
        let overlaps = sources.filter { $0["overlapTuple"] is [String: Any] }
        XCTAssertEqual(Set(overlaps.compactMap { $0["path"] as? String }), Set([".github/workflows/ios-ci.yml", "Scripts/ui-smoke.sh"]))
    }

    func testDiagnosticsCannotGrantAcceptanceOrReleaseCredit() throws {
        let value = try contract()
        XCTAssertEqual(value["finalCredit"] as? Bool, false)
        XCTAssertEqual(value["nativeDiagnosticsAreAcceptance"] as? Bool, false)
        XCTAssertEqual(value["nativeDiagnosticsOptional"] as? Bool, true)
        XCTAssertEqual(value["postS10QualificationRequired"] as? Bool, true)
        let required = try XCTUnwrap(value["requiredArtifacts"] as? [String])
        XCTAssertTrue(Set(["Build.xcresult", "UnitTests.xcresult", "SHA256SUMS.txt", "v30-selection-validation.json"]).isSubset(of: Set(required)))
        let ui = try XCTUnwrap(value["uiArtifacts"] as? [String])
        XCTAssertTrue(ui.contains("UISmoke.xcresult") && ui.contains("ui-final.png"))
        let recovery = try XCTUnwrap(value["recoveryLaw"] as? [String])
        XCTAssertTrue(recovery.contains { $0.contains("correctionOf") })
        XCTAssertTrue(recovery.contains { $0.contains("NOT_EXECUTED_NO_NATIVE_CREDIT") })
    }
}

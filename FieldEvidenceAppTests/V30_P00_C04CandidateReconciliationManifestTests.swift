import CryptoKit
import Foundation
import XCTest

/// These tests inspect the checked-in contract. Git ancestry and historic blobs
/// are verified by the companion read-only Python validator on the authoring host.
final class V30_P00_C04CandidateReconciliationManifestTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    private func object(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(path)) as? [String: Any])
    }

    private func manifest() throws -> [String: Any] {
        try object("docs/design/v30/contracts/V30ProvisionalCandidateReconciliationManifestV1.json")
    }

    private func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func testFrozenAuthorityAndUnresolvedIntegrationBases() throws {
        let value = try manifest()
        let authority = try object("docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json")
        XCTAssertEqual(value["authorityID"] as? String, authority["authorityID"] as? String)
        XCTAssertEqual(value["authorityContentDigest"] as? String, authority["authorityContentDigest"] as? String)
        let base = try XCTUnwrap(value["B"] as? [String: String])
        let frozen = try XCTUnwrap(authority["frozenV23"] as? [String: Any])
        XCTAssertEqual(base["head"], frozen["head"] as? String)
        XCTAssertEqual(base["tree"], frozen["tree"] as? String)
        for (key, state) in [("P", "NOT_FROZEN_PRE_S10"), ("S", "POST_S10_AUTHORITY_REQUIRED")] {
            let binding = try XCTUnwrap(value[key] as? [String: Any])
            XCTAssertTrue(binding["head"] is NSNull)
            XCTAssertTrue(binding["tree"] is NSNull)
            XCTAssertEqual(binding["state"] as? String, state)
        }
        let credit = try XCTUnwrap(value["credit"] as? [String: Bool])
        XCTAssertEqual(credit.count, 6)
        XCTAssertTrue(credit.values.allSatisfy { !$0 })
        XCTAssertEqual(value["schemaSHA256"] as? String, digest(try data("docs/design/v30/schemas/v30-provisional-candidate-reconciliation-manifest.schema.json")))
        XCTAssertEqual(value["fenceSHA256"] as? String, digest(try data("docs/design/v30/authority/V30PreS10PathFencesV1.json")))
    }

    func testEveryReferenceCandidateRetainsItsMappingAndEvidence() throws {
        let value = try manifest()
        let rows = try XCTUnwrap(value["cards"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["cardID"] as? String }, ["V30-P00-C01", "V30-P00-C02", "V30-P00-C03"])
        for row in rows {
            let candidate = try XCTUnwrap(row["candidate"] as? [String: String])
            let reconciliation = try XCTUnwrap(row["reconciliation"] as? [String: Any])
            XCTAssertEqual(reconciliation["originalCandidate"] as? [String: String], candidate)
            XCTAssertTrue(reconciliation["replayedCandidate"] is NSNull)
            XCTAssertEqual(reconciliation["compatibility"] as? String, "UNASSESSED_PRE_S10")
            let history = try XCTUnwrap(row["candidateHistory"] as? [[String: Any]])
            let last = try XCTUnwrap(history.last)
            XCTAssertEqual(last["head"] as? String, candidate["head"])
            XCTAssertEqual(last["tree"] as? String, candidate["tree"])
            XCTAssertEqual(last["state"] as? String, "PROVISIONAL_CHECKPOINTED")
            let evidence = try XCTUnwrap(row["evidence"] as? [[String: String]])
            XCTAssertFalse(evidence.isEmpty)
            XCTAssertEqual(Set(evidence.compactMap { $0["head"] }), Set(history.compactMap { $0["head"] as? String }))
            for attempt in history {
                let bindings = try XCTUnwrap(attempt["immutableReceiptBindings"] as? [[String: String]])
                XCTAssertFalse(bindings.isEmpty)
                let paths = try XCTUnwrap(attempt["changedPaths"] as? [String])
                XCTAssertFalse(paths.isEmpty)
            }
            for item in evidence {
                XCTAssertEqual(item["native"], "NOT_EXECUTED_NO_NATIVE_CREDIT")
                let path = try XCTUnwrap(item["path"])
                XCTAssertEqual(item["sha256"], digest(try data(path)))
            }
        }
    }

    func testReplayAndEvidenceDispositionRemainSeparate() throws {
        let value = try manifest()
        let policy = try XCTUnwrap(value["policy"] as? [String: Any])
        XCTAssertEqual(policy["wholesaleMergeAllowed"] as? Bool, false)
        XCTAssertEqual(policy["preS10PromotionAllowed"] as? Bool, false)
        XCTAssertEqual(policy["compatibilityClasses"] as? [String], [
            "UNCHANGED_SAFE_REPLAY", "S10_ALREADY_SATISFIES_WITH_PROOF",
            "CONFLICT_REQUIRES_AUTHORIZED_REIMPLEMENTATION", "OBSOLETE_REJECTED_WITH_RATIONALE"
        ])
        XCTAssertEqual(policy["evidenceDispositionClasses"] as? [String], [
            "COMPATIBLE", "CORRECTION_REQUIRED", "SUPERSEDED", "OBSOLETE_WITH_RATIONALE"
        ])
        let invalidated = try XCTUnwrap(policy["headOrTreeChangeInvalidates"] as? [String])
        XCTAssertTrue(Set(["unit", "UI", "localization", "persistence", "brand", "exact-head hosted CI"]).isSubset(of: Set(invalidated)))
    }
}

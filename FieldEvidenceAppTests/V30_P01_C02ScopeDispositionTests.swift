import CryptoKit
import Foundation
import XCTest

final class V30_P01_C02ScopeDispositionTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    private let folder = "docs/design/v30/research/"
    private let dispositions: Set<String> = [
        "PRESERVE_IN_V30", "VERIFY_EXISTING_BEHAVIOR", "FUTURE_CARD", "REJECT_SCOPE"
    ]

    private func object(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func research(_ name: String) throws -> [String: Any] {
        try object(folder + name + ".json")
    }

    private func assertBinding(_ value: Any?) throws {
        let binding = try XCTUnwrap(value as? [String: String])
        let path = try XCTUnwrap(binding["path"])
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(binding["sha256"], hash)
    }

    func testDispositionRegisterCoversNeedsWithoutGrantingImplementationAuthority() throws {
        let register = try research("V30CustomerNeedsScopeDispositionRegisterV1")
        try assertBinding(register["blueprint"])
        try assertBinding(register["researchManifest"])
        try assertBinding(register["competitorEvidence"])
        try assertBinding(register["keywordBinding"])
        let rows = try XCTUnwrap(register["rows"] as? [[String: Any]])
        let ids = try rows.map { try XCTUnwrap($0["id"] as? String) }
        XCTAssertEqual(Set(ids).count, rows.count)
        XCTAssertTrue(Set((1...8).map { String(format: "NEED-%02d", $0) }).isSubset(of: Set(ids)))
        XCTAssertEqual(Set(rows.compactMap { $0["disposition"] as? String }), dispositions)

        let catalog = try object("docs/design/v30/authority/V30CardRegisterV1.json")
        let cards = try XCTUnwrap(catalog["cards"] as? [[String: Any]])
        let knownIDs = Set(cards.compactMap { $0["cardID"] as? String })
        for row in rows {
            XCTAssertTrue(dispositions.contains(try XCTUnwrap(row["disposition"] as? String)))
            XCTAssertEqual(row["implementationAuthorizedByThisRecord"] as? Bool, false)
            XCTAssertEqual(row["currentProductBehaviorVerified"] as? Bool, false)
            XCTAssertFalse(try XCTUnwrap(row["rationale"] as? String).isEmpty)
            XCTAssertFalse(try XCTUnwrap(row["scopeBoundary"] as? String).isEmpty)
            let nextCards = try XCTUnwrap(row["verificationOrImplementationCards"] as? [String])
            XCTAssertTrue(Set(nextCards).isSubset(of: knownIDs))
            if row["disposition"] as? String == "REJECT_SCOPE" {
                XCTAssertTrue(nextCards.isEmpty)
            }
        }
        XCTAssertEqual(register["finalCredit"] as? Bool, false)
        XCTAssertEqual(register["newBackendAuthorized"] as? Bool, false)
        XCTAssertEqual(register["newModuleAuthorized"] as? Bool, false)
        XCTAssertEqual(register["storefrontCountries"] as? [String], ["US"])
    }

    func testRecentReviewsAreDatedTerritorialReportsNotVerifiedDefects() throws {
        let register = try research("V30CustomerNeedsScopeDispositionRegisterV1")
        let sample = try XCTUnwrap(register["reviewSample"] as? [String: Any])
        let sources = try XCTUnwrap(sample["sources"] as? [[String: Any]])
        let window = try XCTUnwrap(sample["window"] as? [String: String])
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: XCTUnwrap(window["start"])))
        let end = try XCTUnwrap(formatter.date(from: XCTUnwrap(window["end"])))
        XCTAssertEqual(sources.count, 6)
        var reviewIDs = Set<String>()
        for source in sources {
            XCTAssertEqual(source["territory"] as? String, "US")
            XCTAssertEqual((source["httpResponseSHA256"] as? String)?.count, 64)
            let reviews = try XCTUnwrap(source["reviews"] as? [[String: Any]])
            XCTAssertLessThanOrEqual(reviews.count, 3)
            for review in reviews {
                let date = try XCTUnwrap(formatter.date(from: XCTUnwrap(review["date"] as? String)))
                XCTAssertGreaterThanOrEqual(date, start)
                XCTAssertLessThanOrEqual(date, end)
                XCTAssertEqual(review["sourceType"] as? String, "CUSTOMER_REPORTED")
                XCTAssertEqual(review["defectVerified"] as? Bool, false)
                XCTAssertTrue(reviewIDs.insert(try XCTUnwrap(review["reviewID"] as? String)).inserted)
            }
        }
        XCTAssertEqual(reviewIDs.count, 16)
        let optional = try XCTUnwrap(sample["optionalSpanishSignal"] as? [String: Any])
        XCTAssertEqual(optional["territory"] as? String, "CL")
        XCTAssertEqual(optional["inWindow"] as? Int, 0)
        XCTAssertEqual(optional["status"] as? String, "NO_IN_WINDOW_REVIEW_ON_FIRST_PAGE")
    }

    func testCohortAndUnfinishedV23StatesRemainFrozen() throws {
        let register = try research("V30CustomerNeedsScopeDispositionRegisterV1")
        XCTAssertEqual(register["localeIDs"] as? [String], ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"])
        let states = try XCTUnwrap(register["preservedV23States"] as? [[String: Any]])
        XCTAssertEqual(states.count, 4)
        for (number, cardID, classification, state) in [
            (135, "V23-P05-C02", "OWNER_ACTION", "NOT_STARTED"),
            (136, "V23-P05-C03", "MONITOR", "NOT_STARTED"),
            (141, "V23-P06-C05", "DEFER", "DEFERRED"),
            (146, "V23-P06-C10", "DEFER", "DEFERRED")
        ] {
            let row = try XCTUnwrap(states.first { $0["globalCard"] as? Int == number })
            XCTAssertEqual(row["cardID"] as? String, cardID)
            XCTAssertEqual(row["classification"] as? String, classification)
            XCTAssertEqual(row["state"] as? String, state)
            XCTAssertEqual(row["staticPreparation"] as? Bool, false)
            if number == 136 { XCTAssertEqual(row["armed"] as? Bool, false) }
        }
    }

    func testKeywordBindingPreservesMeasuredVersusIdeaAndHistoricalScope() throws {
        let binding = try research("V30KeywordEvidenceBindingV1")
        try assertBinding(binding["researchManifest"])
        let integrity = try XCTUnwrap(binding["packageIntegrity"] as? [String: Any])
        XCTAssertEqual((integrity["payloads"] as? [[String: Any]])?.count, 11)
        let entries = try XCTUnwrap(binding["representativePhrases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(entries.count, 6)
        XCTAssertLessThanOrEqual(entries.count, 10)
        for phrase in entries {
            XCTAssertFalse(try XCTUnwrap(phrase["phrase"] as? String).isEmpty)
            XCTAssertFalse(try XCTUnwrap(phrase["sourceJSONPointer"] as? String).isEmpty)
            XCTAssertEqual(phrase["country"] as? String, "US")
            XCTAssertEqual(phrase["language"] as? String, "en")
            XCTAssertEqual(phrase["researchDate"] as? String, "2026-08-12")
            XCTAssertEqual(phrase["productTruth"] as? Bool, false)
            XCTAssertEqual(phrase["localizedDemandMeasured"] as? Bool, false)
            let kind = try XCTUnwrap(phrase["statusKind"] as? String)
            XCTAssertTrue(["measured", "idea"].contains(kind))
            if kind == "idea" {
                XCTAssertEqual(phrase["sourceType"] as? String, "HYPOTHESIS")
            } else {
                XCTAssertEqual(phrase["sourceType"] as? String, "KEYWORD_MEASURED")
            }
        }
        let history = try XCTUnwrap(binding["historicalBuildFit"] as? [String: Any])
        XCTAssertEqual(history["isCurrentV23ProductAudit"] as? Bool, false)
        XCTAssertEqual(history["changesCurrentAuthority"] as? Bool, false)
        XCTAssertEqual(binding["newVerticalAuthorized"] as? Bool, false)
        XCTAssertEqual(binding["newBackendAuthorized"] as? Bool, false)
        XCTAssertEqual(binding["newModuleAuthorized"] as? Bool, false)
        XCTAssertEqual(binding["metadataPublicationAuthorized"] as? Bool, false)
        XCTAssertEqual(binding["finalCredit"] as? Bool, false)
    }
}

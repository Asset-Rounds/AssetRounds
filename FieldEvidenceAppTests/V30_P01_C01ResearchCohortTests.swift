import CryptoKit
import Foundation
import XCTest

final class V30_P01_C01ResearchCohortTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    private let researchRoot = "docs/design/v30/research/"
    private let expectedLocales = ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]

    private func bytes(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    private func object(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: bytes(path)) as? [String: Any])
    }

    private func research(_ name: String) throws -> [String: Any] {
        try object(researchRoot + name + ".json")
    }

    private func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func assertBinding(_ value: Any?, file: StaticString = #filePath, line: UInt = #line) throws {
        let binding = try XCTUnwrap(value as? [String: String], file: file, line: line)
        let path = try XCTUnwrap(binding["path"], file: file, line: line)
        XCTAssertFalse(path.hasPrefix("/") || path.contains(".."), file: file, line: line)
        XCTAssertEqual(binding["sha256"], sha256(try bytes(path)), file: file, line: line)
    }

    func testResearchSourcesAndCohortAreBoundToImmutableInputs() throws {
        let cohort = try research("V30InitialLanguageCohortV1")
        let manifest = try research("V30ResearchManifestV1")
        try assertBinding(cohort["registry"])
        try assertBinding(cohort["researchManifest"])
        try assertBinding(cohort["competitorEvidence"])
        try assertBinding(manifest["competitorEvidence"])
        let bindings = try XCTUnwrap(manifest["packageBindings"] as? [String: Any])
        for binding in bindings.values { try assertBinding(binding) }

        let authority = try object("docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json")
        for document in [cohort, manifest, try research("V30CompetitorCapabilityEvidenceV1")] {
            let observed = try XCTUnwrap(document["authority"] as? [String: Any])
            XCTAssertEqual(observed["authorityID"] as? String, authority["authorityID"] as? String)
            XCTAssertEqual(observed["authorityContentDigest"] as? String, authority["authorityContentDigest"] as? String)
            XCTAssertEqual(document["cardID"] as? String, "V30-P01-C01")
            XCTAssertEqual(document["finalCredit"] as? Bool, false)
            XCTAssertEqual(document["nativeEvidence"] as? String, "NOT_EXECUTED_NO_NATIVE_CREDIT")
        }
    }

    func testExactCohortAndMarketAxesCannotBeSilentlyExpanded() throws {
        let cohort = try research("V30InitialLanguageCohortV1")
        let registry = try object("docs/design/v30/authority/V30LocaleRegistryV1.json")
        XCTAssertEqual(cohort["localeIDs"] as? [String], expectedLocales)
        XCTAssertEqual(cohort["localeIDs"] as? [String], registry["completeBinaryLocalizationIDs"] as? [String])
        XCTAssertEqual(cohort["decision"] as? String, "CONFIRM_PINNED_COHORT")
        XCTAssertEqual(cohort["cohortChangeResult"] as? String, "AMENDMENT_REQUIRED")
        XCTAssertEqual(cohort["sourceAndFinalFallback"] as? String, "en")
        XCTAssertEqual(cohort["languageFamilies"] as? Int, 5)
        XCTAssertEqual(cohort["localizations"] as? Int, 6)

        let matrix = try XCTUnwrap(cohort["localeMarketMatrix"] as? [[String: Any]])
        let pinned = try XCTUnwrap(registry["initialLocales"] as? [[String: Any]])
        XCTAssertEqual(matrix.count, 6)
        XCTAssertEqual(matrix.compactMap { $0["id"] as? String }, expectedLocales)
        for (row, source) in zip(matrix, pinned) {
            XCTAssertEqual(row["formattingProfiles"] as? [String], source["formattingProfiles"] as? [String])
            XCTAssertEqual(row["metadataLanguage"] as? String, source["metadataLanguage"] as? String)
            XCTAssertEqual(row["storefrontCountries"] as? [String], ["US"])
            XCTAssertEqual(row["projectJurisdiction"] as? String, "US")
            XCTAssertEqual(row["supportStatus"] as? String, "PLANNED_REQUIRED_INITIAL")
            XCTAssertEqual(row["claimStatus"] as? String, "NOT_SUPPORTED_UNTIL_ACCEPTED")
            XCTAssertEqual(row["supportCapacityAssessment"] as? String, "NOT_VERIFIED")
            XCTAssertEqual(row["professionalNativeAcceptance"] as? String, "NOT_EXECUTED")
        }
        let axes = try XCTUnwrap(cohort["independentAxes"] as? [String])
        XCTAssertEqual(Set(axes), Set(["appLanguage", "formattingLocale", "authoredContentLanguage",
                                      "reportLanguage", "storefrontCountry", "projectJurisdiction"]))
        let capacity = try XCTUnwrap(cohort["supportCapacity"] as? [String: Any])
        XCTAssertEqual(capacity["assessment"] as? String, "NOT_VERIFIED")
        XCTAssertTrue(capacity["staffingCount"] is NSNull)
        XCTAssertEqual(capacity["staffingOrProfessionalNativeReceiptsProvided"] as? Bool, false)
    }

    // Foundation matching is exercised only when this test runs on the authorized macOS route.
    // These are compatibility probes, not proof that the app has shipped localized resources.
    func testAppleMatchingPreservesRequiredScriptIdentities() {
        for id in expectedLocales {
            XCTAssertEqual(Bundle.preferredLocalizations(from: expectedLocales, forPreferences: [id]).first, id)
        }
        for (preference, expected) in [("es-US", "es"), ("es-MX", "es"), ("vi-VN", "vi"),
                                       ("ko-KR", "ko"), ("zh-Hans-US", "zh-Hans"), ("zh-Hant-US", "zh-Hant")] {
            XCTAssertEqual(Bundle.preferredLocalizations(from: expectedLocales, forPreferences: [preference]).first, expected)
        }
        XCTAssertEqual(Bundle.preferredLocalizations(from: expectedLocales, forPreferences: ["ar", "en"]).first, "en")
    }

    func testCompetitorEvidenceCannotClaimRuntimeCoverage() throws {
        let evidence = try research("V30CompetitorCapabilityEvidenceV1")
        let rows = try XCTUnwrap(evidence["listings"] as? [[String: Any]])
        XCTAssertEqual(Set(rows.compactMap { $0["appID"] as? String }),
                       Set(["499999532", "1437854484", "921799415", "1515671684", "993015031",
                            "418917158", "467758260", "780165517", "498795789"]))
        XCTAssertEqual(rows.count, 9)
        var recurrence: [String: Int] = [:]
        for row in rows {
            XCTAssertEqual(row["territory"] as? String, "US")
            XCTAssertEqual(row["sourceType"] as? String, "BINARY_OBSERVED")
            XCTAssertEqual(row["runtimeStatus"] as? String, "BINARY_NOT_TESTED")
            XCTAssertEqual(row["evidenceKind"] as? String, "APP_STORE_LISTING_DECLARATION")
            let ids = try XCTUnwrap(row["languageIDs"] as? [String])
            let raw = try XCTUnwrap(row["languagesRaw"] as? [String])
            XCTAssertEqual(ids.count, raw.count)
            XCTAssertEqual(Set(ids).count, ids.count)
            XCTAssertFalse(ids.isEmpty)
            for id in ids { recurrence[id, default: 0] += 1 }
            for field in ["url", "capturedAtUTC", "version", "versionDateRaw", "vendorDocumentDiscrepancy"] {
                XCTAssertFalse(try XCTUnwrap(row[field] as? String).isEmpty)
            }
            XCTAssertEqual((row["httpResponseSHA256"] as? String)?.count, 64)
        }
        let portfolio = try XCTUnwrap(evidence["portfolioSignal"] as? [String: Any])
        XCTAssertEqual(portfolio["languageRecurrence"] as? [String: Int], recurrence)
        XCTAssertEqual(portfolio["label"] as? String, "ANALYST_PORTFOLIO_SIGNAL")
        let maintainX = try XCTUnwrap(rows.first { $0["appID"] as? String == "1437854484" })
        XCTAssertEqual(maintainX["languageIDs"] as? [String], ["en"])
        let freshness = try XCTUnwrap(maintainX["freshness"] as? [String: Any])
        XCTAssertEqual(freshness["refreshRequired"] as? Bool, true)
        XCTAssertEqual(freshness["refreshReason"] as? String, "UNRESOLVED_VENDOR_LISTING_CONFLICT")
        let policy = try XCTUnwrap(evidence["freshnessPolicy"] as? [String: Any])
        XCTAssertEqual(policy["currentMaxDays"] as? Int, 30)
        XCTAssertEqual(policy["agingMaxDays"] as? Int, 90)
        let reviews = try XCTUnwrap(evidence["reviews"] as? [[String: Any]])
        XCTAssertTrue(reviews.allSatisfy { $0["sourceType"] as? String == "CUSTOMER_REPORTED" })
    }

    func testPopulationAndKeywordEvidenceRetainTheirLimits() throws {
        let manifest = try research("V30ResearchManifestV1")
        let acs = try XCTUnwrap(manifest["acs"] as? [String: Any])
        XCTAssertEqual(acs["year"] as? Int, 2024)
        XCTAssertEqual(acs["nationalGEOID"] as? String, "0100000US")
        let rows = try XCTUnwrap(acs["nationalLanguageRows"] as? [[String: Any]])
        let chinese = try XCTUnwrap(rows.first { ($0["language"] as? String)?.hasPrefix("Chinese") == true })
        let count = try XCTUnwrap(chinese["speakAtHome"] as? [String: Int])
        XCTAssertEqual(count, ["estimate": 3734956, "marginOfError": 51891])
        XCTAssertNil(chinese["scriptPreference"])
        let keyword = try XCTUnwrap(manifest["keywordEvidence"] as? [String: Any])
        XCTAssertEqual(keyword["market"] as? String, "United States")
        XCTAssertEqual(keyword["language"] as? String, "English")
        XCTAssertEqual(keyword["researchDate"] as? String, "2026-08-12")
        XCTAssertEqual(keyword["keywordRows"] as? Int, 1757)
        XCTAssertEqual(keyword["statusKindCounts"] as? [String: Int], ["measured": 572, "idea": 1185])
        XCTAssertEqual((keyword["payloads"] as? [[String: Any]])?.count, 11)
        let workbook = try XCTUnwrap(keyword["workbook"] as? [String: Any])
        XCTAssertEqual(workbook["formulaValidation"] as? String, "NOT_PERFORMED_HASH_INTEGRITY_ONLY")
        let official = try XCTUnwrap(manifest["officialSources"] as? [[String: Any]])
        let bls = try XCTUnwrap(official.first { $0["id"] as? String == "bls2025" })
        XCTAssertTrue(try XCTUnwrap(bls["limitation"] as? String).contains("11-month"))
        XCTAssertTrue(bls["rawSHA256"] is NSNull)
        XCTAssertEqual(bls["evidenceRoute"] as? String, "WEB_TOOL_TEXT_OBSERVATION")
    }
}

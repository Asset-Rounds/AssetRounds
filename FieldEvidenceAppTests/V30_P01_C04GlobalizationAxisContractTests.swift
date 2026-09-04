import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P01C04GlobalizationAxisContractTests: XCTestCase {
    func testFixtureCasesResolveIndependentAxesWithoutCanonicalMutation() throws {
        let fixture = try loadFixture()
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4)

        for item in cases {
            let formatting = try formattingProfile(from: try XCTUnwrap(item["formatting"] as? [String: Any]))
            let authored = try authoredLanguage(item["authoredContentLanguage"] as? String)
            let report = try reportSelection(from: try XCTUnwrap(item["report"] as? [String: Any]))
            let jurisdiction = try projectJurisdiction(item["projectJurisdiction"] as? String)
            let request = try GlobalizationAxisResolutionRequestV1(
                preferredAppLanguageTags: try XCTUnwrap(item["preferredAppLanguageTags"] as? [String]),
                formatting: formatting,
                authoredContentLanguage: authored,
                reportLanguage: report,
                projectJurisdiction: jurisdiction
            )
            let resolved = try GlobalizationAxisCoordinatorV1.resolve(request)
            XCTAssertEqual(resolved.axes.appLanguage.rawValue, item["expectedAppLanguage"] as? String)
            XCTAssertEqual(resolved.language.fallback.rawValue, item["expectedFallback"] as? String)
            XCTAssertEqual(resolved.axes.formatting, formatting)
            XCTAssertEqual(resolved.axes.authoredContentLanguage, authored)
            XCTAssertEqual(resolved.axes.reportLanguage, report)
            XCTAssertEqual(resolved.axes.projectJurisdiction, jurisdiction)
            XCTAssertEqual(resolved.axes.storefrontCountry, .unitedStates)
            XCTAssertNoThrow(try GlobalizationCanonicalIdentityBoundaryV1.validateNoCanonicalIdentityMutation([]))
        }
    }

    func testEachAxisCanVaryWithoutBeingCollapsedIntoAnotherAxis() throws {
        let english = try AppLanguageTagV1("en")
        let spanish = try AppLanguageTagV1("es")
        let usFormatting = try FormattingLocaleProfileV1(
            localeIdentifier: "en-US", ianaTimeZoneIdentifier: "America/New_York",
            calendar: .gregorian, numberingSystem: .latin, units: .usCustomary
        )
        let japaneseFormatting = try FormattingLocaleProfileV1(
            localeIdentifier: "ja-JP", ianaTimeZoneIdentifier: "Asia/Tokyo",
            calendar: .japanese, numberingSystem: .hanDecimal, units: .metric
        )
        let report = try ReportLanguageSelectionV1(
            requestedLanguage: english, effectiveLanguage: english, fallback: .exact
        )
        let jurisdiction = try ProjectJurisdictionV1(countryCode: "US", subdivisionCode: "PA")
        let baseline = GlobalizationAxisSetV1(
            appLanguage: spanish, formatting: usFormatting,
            authoredContentLanguage: try .declared("vi"), reportLanguage: report,
            storefrontCountry: .unitedStates, projectJurisdiction: jurisdiction
        )
        let changedFormatting = GlobalizationAxisSetV1(
            appLanguage: spanish, formatting: japaneseFormatting,
            authoredContentLanguage: try .declared("vi"), reportLanguage: report,
            storefrontCountry: .unitedStates, projectJurisdiction: jurisdiction
        )
        let changedAuthoredLanguage = GlobalizationAxisSetV1(
            appLanguage: spanish, formatting: usFormatting, authoredContentLanguage: .unknown,
            reportLanguage: report, storefrontCountry: .unitedStates, projectJurisdiction: jurisdiction
        )
        XCTAssertEqual(baseline.appLanguage, changedFormatting.appLanguage)
        XCTAssertEqual(baseline.reportLanguage, changedFormatting.reportLanguage)
        XCTAssertEqual(baseline.projectJurisdiction, changedFormatting.projectJurisdiction)
        XCTAssertNotEqual(baseline.formatting, changedFormatting.formatting)
        XCTAssertEqual(baseline.formatting, changedAuthoredLanguage.formatting)
        XCTAssertNotEqual(baseline.authoredContentLanguage, changedAuthoredLanguage.authoredContentLanguage)
        XCTAssertFalse(GlobalizationCanonicalIdentityBoundaryV1.languageOrFormattingChangesCanonicalIdentity)
        XCTAssertFalse(GlobalizationCanonicalIdentityBoundaryV1.backupIncludesAxisPreferences)
        XCTAssertFalse(GlobalizationCanonicalIdentityBoundaryV1.rawEnumValuesLocalized)
    }

    func testExistingReportDocumentAndBackupSeamsKeepPresentationDerived() throws {
        let language = try AppLanguageTagV1("es")
        let english = try AppLanguageTagV1("en")
        let report = try ReportLanguageSelectionV1(
            requestedLanguage: language,
            effectiveLanguage: english,
            fallback: .englishWithUserConfirmation
        )
        let formatting = try standardFormatting()

        let reportMetadata = try ReportPresentationMetadataV1(
            reportLanguage: report,
            formatting: formatting
        )
        let documentProvenance = try AccessibleDocumentDisplayProvenanceV1(
            reportLanguage: report,
            formatting: formatting
        )

        XCTAssertFalse(reportMetadata.canonicalProjectionIdentityIncluded)
        XCTAssertFalse(documentProvenance.semanticTreeIdentityIncluded)
        XCTAssertTrue(documentProvenance.sourceContentPreserved)
        XCTAssertTrue(V4BackupRecordsV1.v30GlobalizationBoundaryIsValid())
        XCTAssertFalse(GlobalizationCanonicalIdentityBoundaryV1.backupIncludesAxisPreferences)
        try reportMetadata.validate()
        try documentProvenance.validate()
    }

    func testDeviceLocalPresentationPreferenceUsesTheExistingAdapter() throws {
        let suiteName = "V30-P01-C04-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let adapter = PreferencesAdapterV1(defaults: defaults)
        let initial = try adapter.readGlobalizationPresentationPreference()
        XCTAssertEqual(initial, GlobalizationDevicePreferenceV1.logicalDefault)

        let changed = try GlobalizationPresentationPreferenceV1(
            formatting: FormattingLocaleProfileV1(
                localeIdentifier: "es-US",
                ianaTimeZoneIdentifier: "America/Chicago",
                calendar: .gregorian,
                numberingSystem: .latin,
                units: .metric
            ),
            reportLanguage: ReportLanguageSelectionV1(
                requestedLanguage: try AppLanguageTagV1("es"),
                effectiveLanguage: try AppLanguageTagV1("es"),
                fallback: .exact
            )
        )
        try adapter.writeGlobalizationPresentationPreference(changed, operationID: UUID())
        let reread = try adapter.readGlobalizationPresentationPreference()
        XCTAssertEqual(reread, changed)
        let descriptor = try GlobalizationDevicePreferenceV1.descriptor()
        XCTAssertEqual(descriptor.scope, .deviceLocal)
        XCTAssertEqual(descriptor.backup, .excludedDeviceLocal)
    }

    func testFixtureNegativeCasesFailClosed() throws {
        let fixture = try loadFixture()
        let negatives = try XCTUnwrap(fixture["negativeCases"] as? [[String: Any]])
        XCTAssertEqual(negatives.count, 4)

        for item in negatives {
            switch item["kind"] as? String {
            case "MALFORMED_APP_LANGUAGE":
                XCTAssertThrowsError(try GlobalizationAxisResolutionRequestV1(
                    preferredAppLanguageTags: try XCTUnwrap(item["preferredAppLanguageTags"] as? [String]),
                    formatting: try standardFormatting(), authoredContentLanguage: .unknown,
                    projectJurisdiction: try ProjectJurisdictionV1(countryCode: "US")
                ))
            case "MALFORMED_TIME_ZONE":
                XCTAssertThrowsError(try FormattingLocaleProfileV1(
                    localeIdentifier: "en-US", ianaTimeZoneIdentifier: try XCTUnwrap(item["timeZone"] as? String),
                    calendar: .gregorian, numberingSystem: .latin, units: .usCustomary
                ))
            case "REPORT_LANGUAGE_INFERENCE":
                XCTAssertThrowsError(try ReportLanguageSelectionV1(
                    requestedLanguage: try AppLanguageTagV1("es"), effectiveLanguage: .english, fallback: .exact
                ))
            case "CANONICAL_CONTAMINATION":
                XCTAssertThrowsError(try GlobalizationCanonicalIdentityBoundaryV1.validateNoCanonicalIdentityMutation(
                    try XCTUnwrap(item["changedCanonicalFields"] as? [String])
                ))
            default:
                XCTFail("Unknown negative fixture case")
            }
        }
    }

    private func loadFixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/GlobalizationAxes/axis-matrix-v1.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(fixture["schema"] as? String, "V30GlobalizationAxisMatrixV1")
        XCTAssertEqual(fixture["cardID"] as? String, "V30-P01-C04")
        let provisional = try XCTUnwrap(fixture["provisional"] as? [String: Any])
        XCTAssertEqual(provisional["finalCredit"] as? Bool, false)
        XCTAssertEqual(provisional["nativeEvidence"] as? String, "NOT_EXECUTED_NO_NATIVE_CREDIT")
        XCTAssertEqual(provisional["storefrontCountry"] as? String, "US")
        return fixture
    }

    private func formattingProfile(from value: [String: Any]) throws -> FormattingLocaleProfileV1 {
        try FormattingLocaleProfileV1(
            localeIdentifier: try XCTUnwrap(value["locale"] as? String),
            ianaTimeZoneIdentifier: try XCTUnwrap(value["timeZone"] as? String),
            calendar: try XCTUnwrap(GlobalizationCalendarV1(rawValue: try XCTUnwrap(value["calendar"] as? String))),
            numberingSystem: try XCTUnwrap(GlobalizationNumberingSystemV1(rawValue: try XCTUnwrap(value["numbering"] as? String))),
            units: try XCTUnwrap(GlobalizationUnitsV1(rawValue: try XCTUnwrap(value["units"] as? String)))
        )
    }

    private func authoredLanguage(_ value: String?) throws -> AuthoredContentLanguageV1 {
        guard let value else { throw GlobalizationAxisFailureV1.invalidAuthoredContentLanguage }
        return value == "unknown" ? .unknown : try .declared(value)
    }

    private func reportSelection(from value: [String: Any]) throws -> ReportLanguageSelectionV1 {
        try ReportLanguageSelectionV1(
            requestedLanguage: try AppLanguageTagV1(try XCTUnwrap(value["requested"] as? String)),
            effectiveLanguage: try AppLanguageTagV1(try XCTUnwrap(value["effective"] as? String)),
            fallback: try XCTUnwrap(ReportLanguageFallbackV1(rawValue: try XCTUnwrap(value["fallback"] as? String)))
        )
    }

    private func projectJurisdiction(_ value: String?) throws -> ProjectJurisdictionV1 {
        guard let value else { throw GlobalizationAxisFailureV1.invalidProjectJurisdiction }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard (parts.count == 1 || parts.count == 2), parts.allSatisfy({ !$0.isEmpty }) else {
            throw GlobalizationAxisFailureV1.invalidProjectJurisdiction
        }
        return try ProjectJurisdictionV1(
            countryCode: String(parts[0]),
            subdivisionCode: parts.count == 2 ? String(parts[1]) : nil
        )
    }

    private func standardFormatting() throws -> FormattingLocaleProfileV1 {
        try FormattingLocaleProfileV1(
            localeIdentifier: "en-US", ianaTimeZoneIdentifier: "America/New_York",
            calendar: .gregorian, numberingSystem: .latin, units: .usCustomary
        )
    }
}

import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P01C05CanonicalIdentityInvarianceTests: XCTestCase {
    func testFixturePreservesCanonicalIdentityAcrossChangedPresentationAxes() throws {
        let fixture = try loadFixture()
        try fixture.validate()

        let comparison = try CanonicalIdentityAuditCoordinatorV1.audit(fixture)
        XCTAssertTrue(comparison.presentationChanged)
        XCTAssertTrue(comparison.canonicalIdentityUnchanged)
        XCTAssertTrue(comparison.historicalEnUSIdentityPreserved)
        XCTAssertTrue(comparison.changedCanonicalFields.isEmpty)
    }

    func testDeclaredJournalBackupSettingsAndRestoreSeamsAreFailClosed() throws {
        XCTAssertTrue(V30P01C05SettingsCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05ChangeJournalCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05MutationJournalCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05LocalChangeJournalCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05WorkspaceWriterCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05BackupRecordsCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05BackupEncoderCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05BackupDecoderCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05BackupPackageCanonicalIdentityBoundaryV1.validate())
        XCTAssertTrue(V30P01C05BackupRestoreCanonicalIdentityBoundaryV1.validate())
        XCTAssertNoThrow(try CanonicalIdentityInvarianceV1.validateDeclaredSeams())
    }

    func testCanonicalMutationFailsClosed() throws {
        let fixture = try loadFixture()
        let baseline = fixture.baseline
        let changed = try CanonicalIdentitySnapshotV1(
            stableIDs: baseline.stableIDs + ["z:unapproved"],
            rawEnumValues: baseline.rawEnumValues,
            mutationSHA256: baseline.mutationSHA256,
            journalSHA256: baseline.journalSHA256,
            evidenceSHA256: baseline.evidenceSHA256,
            backupIdentitySHA256: baseline.backupIdentitySHA256,
            authoredEvidenceSHA256: baseline.authoredEvidenceSHA256,
            productIdentitySHA256: baseline.productIdentitySHA256,
            jurisdictionIdentifier: baseline.jurisdictionIdentifier,
            historicalEnUSIdentities: baseline.historicalEnUSIdentities
        )
        let mutated = CanonicalIdentityBaselineFixtureV1(
            baseline: baseline,
            localized: changed,
            beforePresentation: fixture.beforePresentation,
            afterPresentation: fixture.afterPresentation
        )

        XCTAssertThrowsError(try CanonicalIdentityAuditCoordinatorV1.audit(mutated)) { error in
            XCTAssertEqual(
                error as? CanonicalIdentityInvarianceFailureV1,
                .canonicalIdentityChanged(["stableIDs"])
            )
        }
    }

    func testPresentationMustActuallyChange() throws {
        let fixture = try loadFixture()
        let unchanged = CanonicalIdentityBaselineFixtureV1(
            baseline: fixture.baseline,
            localized: fixture.localized,
            beforePresentation: fixture.beforePresentation,
            afterPresentation: fixture.beforePresentation
        )
        XCTAssertThrowsError(try CanonicalIdentityAuditCoordinatorV1.audit(unchanged)) { error in
            XCTAssertEqual(error as? CanonicalIdentityInvarianceFailureV1, .presentationDidNotChange)
        }
    }

    func testC04AxisTypesProduceDifferentPresentationFingerprints() throws {
        let english = try AppLanguageTagV1("en")
        let spanish = try AppLanguageTagV1("es")
        let report = try ReportLanguageSelectionV1(
            requestedLanguage: english,
            effectiveLanguage: english,
            fallback: .exact
        )
        let jurisdiction = try ProjectJurisdictionV1(countryCode: "US", subdivisionCode: "PA")
        let us = try FormattingLocaleProfileV1(
            localeIdentifier: "en-US",
            ianaTimeZoneIdentifier: "America/New_York",
            calendar: .gregorian,
            numberingSystem: .latin,
            units: .usCustomary
        )
        let metric = try FormattingLocaleProfileV1(
            localeIdentifier: "es-ES",
            ianaTimeZoneIdentifier: "Europe/Madrid",
            calendar: .gregorian,
            numberingSystem: .latin,
            units: .metric
        )
        let baseline = GlobalizationAxisSetV1(
            appLanguage: english,
            formatting: us,
            authoredContentLanguage: try .declared("en-US"),
            reportLanguage: report,
            storefrontCountry: .unitedStates,
            projectJurisdiction: jurisdiction
        )
        let localized = GlobalizationAxisSetV1(
            appLanguage: spanish,
            formatting: metric,
            authoredContentLanguage: try .declared("es"),
            reportLanguage: try ReportLanguageSelectionV1(
                requestedLanguage: spanish,
                effectiveLanguage: spanish,
                fallback: .exact
            ),
            storefrontCountry: .unitedStates,
            projectJurisdiction: jurisdiction
        )

        XCTAssertNotEqual(
            GlobalizationPresentationFingerprintV1(axisSet: baseline).displayKey,
            GlobalizationPresentationFingerprintV1(axisSet: localized).displayKey
        )
    }

    private func loadFixture() throws -> CanonicalIdentityBaselineFixtureV1 {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/CanonicalIdentity/en-us-identity-baseline-v1.json")
        let fixture = try JSONDecoder().decode(
            CanonicalIdentityBaselineFixtureV1.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(fixture.schemaVersion, CanonicalIdentityBaselineFixtureV1.schemaVersion)
        XCTAssertEqual(fixture.baseline.historicalEnUSIdentities.count, 2)
        return fixture
    }
}

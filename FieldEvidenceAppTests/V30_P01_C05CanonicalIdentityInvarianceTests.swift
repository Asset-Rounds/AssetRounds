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

        let expectedStableIDs = try [
            WorkspaceEntityIdentityV1(
                kind: .asset,
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
            ),
            WorkspaceEntityIdentityV1(
                kind: .report,
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
            ),
            WorkspaceEntityIdentityV1(
                kind: .site,
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
            )
        ].map(\.stableKey).sorted()
        XCTAssertEqual(fixture.baseline.stableIDs, expectedStableIDs)
        XCTAssertEqual(
            fixture.baseline.rawEnumValues,
            ["US_CUSTOMARY", "apply_asset_label", "asset", "site"]
        )

        try GlobalizationDevicePreferenceV1.validateC05CanonicalIdentityBoundary(
            GlobalizationDevicePreferenceV1.logicalDefault
        )
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

        let bytes = Data("c05-canonical-bytes".utf8)
        let digest = CanonicalIdentityInvarianceV1.sha256(bytes)
        XCTAssertNoThrow(
            try CanonicalIdentityInvarianceV1.validateCanonicalBytes(
                bytes,
                declaredSHA256: digest
            )
        )
        XCTAssertThrowsError(
            try CanonicalIdentityInvarianceV1.validateCanonicalBytes(
                bytes,
                declaredSHA256: digest.uppercased()
            )
        )
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
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(raw["schema"] as? String, "V30CanonicalIdentityBaselineV1")
        XCTAssertEqual(raw["cardID"] as? String, "V30-P01-C05")
        let provisional = try XCTUnwrap(raw["provisional"] as? [String: Any])
        XCTAssertEqual(provisional["finalCredit"] as? Bool, false)
        XCTAssertEqual(provisional["nativeEvidence"] as? String, "NOT_EXECUTED_NO_NATIVE_CREDIT")
        XCTAssertEqual(provisional["reconciliationRequired"] as? Bool, true)
        XCTAssertEqual(provisional["phase10Forbidden"] as? Bool, true)
        let fixture = try JSONDecoder().decode(
            CanonicalIdentityBaselineFixtureV1.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(fixture.schemaVersion, CanonicalIdentityBaselineFixtureV1.schemaVersion)
        XCTAssertEqual(fixture.baseline.historicalEnUSIdentities.count, 2)
        return fixture
    }
}

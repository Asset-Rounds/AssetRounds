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

        let axes = try makePresentationAxisSets()
        XCTAssertEqual(
            fixture.beforePresentation,
            GlobalizationPresentationFingerprintV1(axisSet: axes.before)
        )
        XCTAssertEqual(
            fixture.afterPresentation,
            GlobalizationPresentationFingerprintV1(axisSet: axes.after)
        )

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
            [
                "APPLIED", "EXACT", "GREGORIAN", "US", "US_CUSTOMARY",
                "apply_asset_label", "asset", "latn", "site"
            ]
        )
        XCTAssertEqual(GlobalizationCalendarV1.gregorian.rawValue, "GREGORIAN")
        XCTAssertEqual(GlobalizationNumberingSystemV1.latin.rawValue, "latn")
        XCTAssertEqual(StorefrontCountryV1.unitedStates.rawValue, "US")
        XCTAssertEqual(ReportLanguageFallbackV1.exact.rawValue, "EXACT")
        XCTAssertEqual(ChangeReplayDispositionV1.applied.rawValue, "APPLIED")

        let expectedHistorical = [
            "preflight.ack.en-US.v1:after_dark",
            "preflight.ack.en-US.v1:safe_authorized_position"
        ]
        XCTAssertEqual(fixture.baseline.historicalEnUSIdentities, expectedHistorical)
        XCTAssertEqual(fixture.localized.historicalEnUSIdentities, expectedHistorical)

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

    func testAuditRejectsEachProtectedCanonicalFieldIndependently() throws {
        let fixture = try loadFixture()
        let original = fixture.baseline
        let fields = [
            "stableIDs", "rawEnumValues", "mutationSHA256", "journalSHA256",
            "evidenceSHA256", "backupIdentitySHA256", "authoredEvidenceSHA256",
            "productIdentitySHA256", "jurisdictionIdentifier", "historicalEnUSIdentities"
        ]
        let replacementDigest = CanonicalIdentityInvarianceV1.sha256(Data("changed".utf8))
        for field in fields {
            func digest(_ name: String, _ value: String) -> String {
                field == name ? replacementDigest : value
            }
            let changed = try CanonicalIdentitySnapshotV1(
                stableIDs: field == "stableIDs" ? original.stableIDs + ["changed:id"] : original.stableIDs,
                rawEnumValues: field == "rawEnumValues" ? original.rawEnumValues + ["CHANGED"] : original.rawEnumValues,
                mutationSHA256: digest("mutationSHA256", original.mutationSHA256),
                journalSHA256: digest("journalSHA256", original.journalSHA256),
                evidenceSHA256: digest("evidenceSHA256", original.evidenceSHA256),
                backupIdentitySHA256: digest("backupIdentitySHA256", original.backupIdentitySHA256),
                authoredEvidenceSHA256: digest("authoredEvidenceSHA256", original.authoredEvidenceSHA256),
                productIdentitySHA256: digest("productIdentitySHA256", original.productIdentitySHA256),
                jurisdictionIdentifier: field == "jurisdictionIdentifier" ? "US-NY" : original.jurisdictionIdentifier,
                historicalEnUSIdentities: field == "historicalEnUSIdentities"
                    ? original.historicalEnUSIdentities + ["preflight.ack.en-US.v1:changed"]
                    : original.historicalEnUSIdentities
            )
            XCTAssertThrowsError(try CanonicalIdentityInvarianceV1.audit(
                baseline: original, localized: changed,
                beforePresentation: fixture.beforePresentation,
                afterPresentation: fixture.afterPresentation
            )) { error in
                XCTAssertEqual(
                    error as? CanonicalIdentityInvarianceFailureV1,
                    .canonicalIdentityChanged([field]),
                    "Must reject a change to \(field)"
                )
            }
        }
    }

    func testC04AxisTypesProduceDifferentPresentationFingerprints() throws {
        let axes = try makePresentationAxisSets()

        XCTAssertNotEqual(
            GlobalizationPresentationFingerprintV1(axisSet: axes.before).displayKey,
            GlobalizationPresentationFingerprintV1(axisSet: axes.after).displayKey
        )
    }

    func testFrozenEnUSReportSnapshotCanonicalBytesSurvivePresentationChange() throws {
        let fixtureBytes = try Data(contentsOf: historicalReportSnapshotURL())
        let snapshot = try ReportSnapshotEncoderV1().decode(fixtureBytes)
        let encodedBefore = try ReportSnapshotEncoderV1().encode(snapshot)
        // This frozen report proves preservation of recorded evidence hashes;
        // it does not claim to regenerate digests for the absent media bytes.
        let evidenceSHA256s = snapshot.evidence.map(\.sha256).sorted()
        let authoredContentBytes = try [
            WorkspaceMutationCanonicalV1.data(snapshot.asset),
            WorkspaceMutationCanonicalV1.data(snapshot.site)
        ]
        let suiteName = "V30-P01-C05-historic-report-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let initial = try preferences.readGlobalizationPresentationPreference()
        let changed = try GlobalizationPresentationPreferenceV1(
            formatting: FormattingLocaleProfileV1(
                localeIdentifier: "es-US",
                ianaTimeZoneIdentifier: "America/Chicago",
                calendar: .gregorian,
                numberingSystem: .latin,
                units: .metric
            ),
            reportLanguage: ReportLanguageSelectionV1(
                requestedLanguage: AppLanguageTagV1("es"),
                effectiveLanguage: AppLanguageTagV1("es"),
                fallback: .exact
            )
        )
        try preferences.writeGlobalizationPresentationPreference(
            changed,
            operationID: UUID()
        )
        let reread = try preferences.readGlobalizationPresentationPreference()

        XCTAssertNotEqual(initial, changed)
        XCTAssertEqual(reread, changed)
        XCTAssertEqual(encodedBefore.data, fixtureBytes)
        XCTAssertEqual(
            encodedBefore.sha256,
            try String(
                contentsOf: historicalReportSnapshotDigestURL(),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertEqual(
            snapshot.acknowledgements.map { "\($0.version):\($0.key)" }.sorted(),
            [
                "preflight.ack.en-US.v1:after_dark",
                "preflight.ack.en-US.v1:safe_authorized_position"
            ]
        )
        XCTAssertEqual(
            evidenceSHA256s,
            [
                String(repeating: "a", count: 64),
                String(repeating: "c", count: 64)
            ]
        )
        XCTAssertTrue(snapshot.acknowledgements.allSatisfy { !$0.copy.isEmpty })
        XCTAssertEqual(snapshot.asset.label, "Monument Sign")
        XCTAssertEqual(snapshot.site.label, "North Campus")

        let encodedAfter = try ReportSnapshotEncoderV1().encode(snapshot)
        XCTAssertEqual(encodedAfter.data, encodedBefore.data)
        XCTAssertEqual(encodedAfter.sha256, encodedBefore.sha256)
        XCTAssertEqual(
            try [
                WorkspaceMutationCanonicalV1.data(snapshot.asset),
                WorkspaceMutationCanonicalV1.data(snapshot.site)
            ],
            authoredContentBytes
        )
    }

    func testPersistedPresentationChangePreservesAssetProductIdentityCanonicalBytes() throws {
        // The C05 baseline fixture is a comparison-unit projection. This uses
        // the actual product-identity contract and its canonical codec instead.
        let productIdentity = try makeAssetProductIdentity()
        let before = try AssetSemanticCanonicalCodecV1.encode(productIdentity)
        let beforeIdentitySHA256 = productIdentity.identitySHA256
        let billingContract = StoreKitProductContractV1(
            productID: EntitlementReducerV1.productID,
            kind: .autoRenewableSubscription,
            periodValue: 1,
            periodUnit: .month,
            isFamilyShareable: false,
            introductoryPeriodValue: 2,
            introductoryPeriodUnit: .week,
            introductoryPaymentMode: .freeTrial
        )
        let billingProductIDBefore = billingContract.productID
        let suiteName = "V30-P01-C05-product-identity-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let initial = try preferences.readGlobalizationPresentationPreference()
        let changed = try c05ChangedPresentationPreference()
        try preferences.writeGlobalizationPresentationPreference(changed, operationID: UUID())
        let reread = try preferences.readGlobalizationPresentationPreference()

        XCTAssertNotEqual(initial, changed)
        XCTAssertEqual(reread, changed)
        XCTAssertEqual(try AssetSemanticCanonicalCodecV1.encode(productIdentity), before)
        XCTAssertEqual(productIdentity.identitySHA256, beforeIdentitySHA256)
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode(AssetProductIdentityV1.self, from: before),
            productIdentity
        )

        XCTAssertNoThrow(try StoreKitProductLoader.validate(billingContract))
        XCTAssertEqual(billingContract.productID, billingProductIDBefore)
        XCTAssertEqual(billingContract.productID, EntitlementReducerV1.productID)
    }

    func testLocalUserAndImportedHistoryEnvelopesRoundTripWithoutReversalMetadata() throws {
        let fixture = try makeMutationEnvelopeFixture()
        let localUser = try MutationEnvelopeV1(
            request: fixture.request,
            identity: fixture.identity,
            sourceKind: .localUser
        )
        let importedHistory = try MutationEnvelopeV1(
            request: fixture.request,
            identity: fixture.identity,
            sourceKind: .importedHistory
        )

        for envelope in [localUser, importedHistory] {
            XCTAssertNil(envelope.causationMutationID)
            XCTAssertNil(envelope.semanticReversalExecution)
            XCTAssertNil(envelope.semanticReversalReplayIdentitySHA256)
            let bytes = try envelope.canonicalData()
            XCTAssertEqual(try MutationEnvelopeV1.decodeCanonical(from: bytes), envelope)
            XCTAssertEqual(try envelope.canonicalSHA256(), try WorkspaceMutationCanonicalV1.sha256(envelope))
        }
        XCTAssertNotEqual(try localUser.canonicalData(), try importedHistory.canonicalData())
    }

    func testSemanticReversalEnvelopeRejectsForeignTargetReceiptWorkspace() throws {
        let fixture = try makeMutationEnvelopeFixture()
        let reversalRequest = WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: c05UUID("00000000-0000-4000-8000-000000000107")),
            expectedRevision: fixture.request.expectedRevision,
            command: fixture.request.command
        )
        let foreignReceipt = MutationReceiptIdentityV1(
            workspaceID: WorkspaceID(rawValue: c05UUID("00000000-0000-4000-8000-000000000108")),
            replicaID: ReplicaID(rawValue: c05UUID("00000000-0000-4000-8000-000000000109")),
            localSequence: 1
        )
        let plan = try SemanticReversalPlanV1(
            mutationID: fixture.request.mutationID,
            commandKind: fixture.request.command.kind,
            expectedRevision: fixture.request.expectedRevision,
            prospectiveTargets: fixture.targets,
            requiredSemanticValues: [.init(key: "c05", value: "foreign-receipt-workspace")],
            contentReferences: [],
            dependencyGraph: [],
            conflicts: [],
            compensatingCommands: [reversalRequest.command]
        )
        let basis = try ReversalBasisV1(
            targetMutationID: fixture.request.mutationID,
            targetReceiptIdentity: foreignReceipt,
            plan: plan
        )
        let execution = try SemanticReversalExecutionV1(
            targetMutationID: fixture.request.mutationID,
            targetReceiptIdentity: foreignReceipt,
            reversalBasisSHA256: try basis.canonicalSHA256(),
            planDigest: plan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        )
        let replayIdentity = try SemanticReversalReplayIdentityV1(
            request: reversalRequest,
            identity: fixture.identity,
            targetMutationID: fixture.request.mutationID,
            planDigest: plan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        ).canonicalSHA256()

        let sameWorkspaceReceipt = MutationReceiptIdentityV1(
            workspaceID: fixture.identity.workspaceID,
            replicaID: foreignReceipt.replicaID,
            localSequence: foreignReceipt.localSequence
        )
        let sameWorkspaceBasis = try ReversalBasisV1(
            targetMutationID: fixture.request.mutationID,
            targetReceiptIdentity: sameWorkspaceReceipt,
            plan: plan
        )
        let sameWorkspaceExecution = try SemanticReversalExecutionV1(
            targetMutationID: fixture.request.mutationID,
            targetReceiptIdentity: sameWorkspaceReceipt,
            reversalBasisSHA256: try sameWorkspaceBasis.canonicalSHA256(),
            planDigest: plan.planDigest,
            compensatingMutationIDs: [reversalRequest.mutationID]
        )
        let accepted = try MutationEnvelopeV1(
            request: reversalRequest,
            identity: fixture.identity,
            sourceKind: .semanticReversal,
            causationMutationID: fixture.request.mutationID,
            correlationID: c05UUID("00000000-0000-4000-8000-000000000110"),
            semanticReversalReplayIdentitySHA256: replayIdentity,
            semanticReversalExecution: sameWorkspaceExecution
        )
        XCTAssertEqual(
            try MutationEnvelopeV1.decodeCanonical(from: accepted.canonicalData()), accepted
        )

        XCTAssertThrowsError(
            try MutationEnvelopeV1(
                request: reversalRequest,
                identity: fixture.identity,
                sourceKind: .semanticReversal,
                causationMutationID: fixture.request.mutationID,
                correlationID: c05UUID("00000000-0000-4000-8000-000000000110"),
                semanticReversalReplayIdentitySHA256: replayIdentity,
                semanticReversalExecution: execution
            )
        ) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .invalidCommand)
        }
    }

    private func makePresentationAxisSets() throws -> (
        before: GlobalizationAxisSetV1,
        after: GlobalizationAxisSetV1
    ) {
        let english = try AppLanguageTagV1("en")
        let spanish = try AppLanguageTagV1("es")
        let jurisdiction = try ProjectJurisdictionV1(countryCode: "US", subdivisionCode: "PA")
        let before = GlobalizationAxisSetV1(
            appLanguage: english,
            formatting: try FormattingLocaleProfileV1(
                localeIdentifier: "en-US",
                ianaTimeZoneIdentifier: "America/New_York",
                calendar: .gregorian,
                numberingSystem: .latin,
                units: .usCustomary
            ),
            authoredContentLanguage: try .declared("en-US"),
            reportLanguage: try ReportLanguageSelectionV1(
                requestedLanguage: english,
                effectiveLanguage: english,
                fallback: .exact
            ),
            storefrontCountry: .unitedStates,
            projectJurisdiction: jurisdiction
        )
        let after = GlobalizationAxisSetV1(
            appLanguage: spanish,
            formatting: try FormattingLocaleProfileV1(
                localeIdentifier: "es-ES",
                ianaTimeZoneIdentifier: "Europe/Madrid",
                calendar: .gregorian,
                numberingSystem: .latin,
                units: .metric
            ),
            authoredContentLanguage: try .declared("es"),
            reportLanguage: try ReportLanguageSelectionV1(
                requestedLanguage: spanish,
                effectiveLanguage: spanish,
                fallback: .exact
            ),
            storefrontCountry: .unitedStates,
            projectJurisdiction: jurisdiction
        )
        return (before, after)
    }

    private func makeMutationEnvelopeFixture() throws -> (
        request: WorkspaceMutationRequestV1,
        identity: WorkspaceReplicaIdentityV1,
        targets: [WorkspaceEntityIdentityV1]
    ) {
        let workspaceID = WorkspaceID(rawValue: c05UUID("00000000-0000-4000-8000-000000000101"))
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: c05UUID("00000000-0000-4000-8000-000000000102"))
        )
        let siteID = c05UUID("00000000-0000-4000-8000-000000000103")
        let assetID = c05UUID("00000000-0000-4000-8000-000000000104")
        let targets = try [
            WorkspaceEntityIdentityV1(kind: .site, id: siteID),
            WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        ]
        let expectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: c05UUID("00000000-0000-4000-8000-000000000105"),
            writerInstanceID: c05UUID("00000000-0000-4000-8000-000000000106"),
            workspaceRevision: 0,
            entityRevisions: targets.map { .init(identity: $0, revision: 0) }
        )
        return (
            WorkspaceMutationRequestV1(
                mutationID: try MutationIDV1(rawValue: c05UUID("00000000-0000-4000-8000-000000000111")),
                expectedRevision: expectedRevision,
                command: .createFirstSign(.init(
                    siteID: siteID,
                    newSite: .init(id: siteID, label: "C05 site", address: nil, timeZoneID: "UTC"),
                    assetID: assetID,
                    assetLabel: "C05 asset",
                    packID: "test.c05",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000)
                ))
            ),
            identity,
            targets
        )
    }

    private func c05UUID(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func c05ChangedPresentationPreference() throws -> GlobalizationPresentationPreferenceV1 {
        try GlobalizationPresentationPreferenceV1(
            formatting: FormattingLocaleProfileV1(
                localeIdentifier: "es-US",
                ianaTimeZoneIdentifier: "America/Chicago",
                calendar: .gregorian,
                numberingSystem: .latin,
                units: .metric
            ),
            reportLanguage: ReportLanguageSelectionV1(
                requestedLanguage: AppLanguageTagV1("es"),
                effectiveLanguage: AppLanguageTagV1("es"),
                fallback: .exact
            )
        )
    }

    private func makeAssetProductIdentity() throws -> AssetProductIdentityV1 {
        try AssetProductIdentityV1(
            identityID: c05UUID("00000000-0000-4000-8000-000000000121"),
            workspaceID: WorkspaceID(rawValue: c05UUID("00000000-0000-4000-8000-000000000122")),
            assetID: c05UUID("00000000-0000-4000-8000-000000000123"),
            identifiers: [
                AssetProductIdentifierV1(
                    kind: .manufacturer,
                    value: "Acme Lighting",
                    normalizedComparisonValue: "acme lighting",
                    issuer: "Acme",
                    provenance: .humanRecorded,
                    reviewState: .reviewedAsRecorded,
                    effectiveFrom: Date(timeIntervalSince1970: 1_800_000_000),
                    effectiveUntil: nil
                )
            ],
            predecessorIdentityID: nil,
            revision: 1,
            mutationID: try MutationIDV1(rawValue: c05UUID("00000000-0000-4000-8000-000000000124")),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/CanonicalIdentity/en-us-identity-baseline-v1.json")
    }

    private func historicalReportSnapshotURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/S3_3ReportSnapshotV1.json")
    }

    private func historicalReportSnapshotDigestURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/S3_3ReportSnapshotV1.sha256")
    }

    private func loadFixture() throws -> CanonicalIdentityBaselineFixtureV1 {
        let url = fixtureURL()
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(raw["schema"] as? String, "V30CanonicalIdentityBaselineV1")
        XCTAssertEqual(raw["cardID"] as? String, "V30-P01-C05")
        XCTAssertEqual(
            raw["digestProvenance"] as? String,
            "COMPARISON_UNIT_SYNTHETIC_NOT_DOMAIN_DERIVED"
        )
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

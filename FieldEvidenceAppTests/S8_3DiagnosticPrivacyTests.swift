import Foundation
import XCTest
@testable import FieldEvidenceApp

private final class C30EvidenceContextAnchorS8_3DiagnosticPrivacy: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S8_3DiagnosticPrivacyTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testCanonicalExportContainsOnlyAllowedControlledValues() async throws {
        let counters = DiagnosticsV1(
            firstSignCreated: 2,
            onboardingCompleted: 1,
            paywallPresented: 3,
            purchaseResult: PurchaseResultHistogram(
                cancelled: 4,
                failed: 5,
                pending: 6,
                unverified: 7,
                verified: 8
            ),
            recheckCompleted: 9,
            reportSaved: 10,
            reportShareSheetPresented: 11,
            schemaVersion: 1
        )
        let summary = MetricKitSummaryV1(
            crashCount: 12,
            hangCount: 13,
            launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                from1000Through1999: 14,
                from2000Up: 15,
                from500Through999: 16,
                under500: 17
            ),
            peakMemoryBytes: 18
        )
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000.123)
        let service = DiagnosticExportService(
            counters: { counters },
            metricKit: { summary },
            app: {
                DiagnosticAppContextV1(build: "42", version: "1.2.3")
            },
            device: {
                DiagnosticDeviceContextV1(
                    model: "iPhone",
                    osVersion: "26.2"
                )
            },
            clock: { generatedAt }
        )

        let prepared = try await service.prepare()
        let encodedAgain = try DiagnosticExportCanonicalEncoderV1.encode(
            prepared.value
        )
        XCTAssertEqual(prepared.canonicalData, encodedAgain)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: prepared.canonicalData)
                as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            Set([
                "app", "counters", "device", "diagnosticSchemaVersion",
                "generatedAt", "metricKit",
            ])
        )
        let metric = try XCTUnwrap(object["metricKit"] as? [String: Any])
        XCTAssertEqual(
            Set(metric.keys),
            Set([
                "crashCount", "hangCount", "launchTimeMilliseconds",
                "peakMemoryBytes",
            ])
        )
        let launch = try XCTUnwrap(
            metric["launchTimeMilliseconds"] as? [String: Any]
        )
        XCTAssertEqual(
            Set(launch.keys),
            Set([
                "from1000Through1999", "from2000Up",
                "from500Through999", "under500",
            ])
        )

        let text = try XCTUnwrap(
            String(data: prepared.canonicalData, encoding: .utf8)
        )
        for forbidden in [
            "Customer North Campus",
            "Monument Sign",
            "123 Main Street",
            "technician note",
            "photos/private.jpg",
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "transaction-123",
            "com.palatis3.fieldrecord.sub.solo.monthly.v1",
            "%PDF-report-content",
            "model.sqlite",
            "FieldEvidenceBackup",
            "authorization-token",
        ] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testBoundedMetricsAndFailedCountersRemainNonAuthoritative() async throws {
        let log = DiagnosticsLogProbe()
        let logger = DiagnosticsLogger { event in
            log.append(event)
        }
        let adapter = MetricKitDiagnosticsAdapter(manager: nil, logger: logger)

        XCTAssertTrue(adapter.accept(MetricKitSummaryV1(
            crashCount: .max,
            hangCount: 2,
            launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                from1000Through1999: 3,
                from2000Up: 4,
                from500Through999: 5,
                under500: 6
            ),
            peakMemoryBytes: 7
        )))
        XCTAssertTrue(adapter.accept(MetricKitSummaryV1(
            crashCount: 1,
            hangCount: 8,
            launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                from1000Through1999: 9,
                from2000Up: 10,
                from500Through999: 11,
                under500: 12
            ),
            peakMemoryBytes: 13
        )))
        XCTAssertFalse(adapter.accept(MetricKitSummaryV1(
            crashCount: -1,
            hangCount: 0,
            launchTimeMilliseconds: nil,
            peakMemoryBytes: nil
        )))

        XCTAssertEqual(
            adapter.snapshot(),
            MetricKitSummaryV1(
                crashCount: .max,
                hangCount: 10,
                launchTimeMilliseconds: LaunchTimeMillisecondsV1(
                    from1000Through1999: 12,
                    from2000Up: 14,
                    from500Through999: 16,
                    under500: 18
                ),
                peakMemoryBytes: 13
            )
        )
        XCTAssertEqual(log.snapshot(), [.metricValueDiscarded])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try Data("occupied".utf8).write(
            to: root.appendingPathComponent("FieldEvidenceDiagnostics")
        )
        let store = DiagnosticsStore(
            applicationSupportURL: root,
            logger: logger
        )
        await store.increment(.reportSaved)
        let durableCounters = await store.snapshot()
        XCTAssertEqual(durableCounters, .zero)
        XCTAssertTrue(log.snapshot().contains(.countersWriteFailed))

        let minimal = try await DiagnosticExportService(
            counters: { durableCounters },
            metricKit: { nil },
            app: { DiagnosticAppContextV1(build: "1", version: "1.0") },
            device: {
                DiagnosticDeviceContextV1(
                    model: "iPhone",
                    osVersion: "26.2"
                )
            },
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        ).prepare()
        XCTAssertNil(minimal.value.metricKit)
        XCTAssertEqual(minimal.value.counters, .zero)
        let minimalText = try XCTUnwrap(
            String(data: minimal.canonicalData, encoding: .utf8)
        )
        XCTAssertTrue(minimalText.contains(#""metricKit":null"#))
        XCTAssertTrue(minimalText.contains(#""report_saved":0"#))
    }

    func testC40AuthorityCriterionLocalizationIsCustomerSafeAndClaimBounded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = root
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let c40Text = try AuthorityCriterionLocalizationKeyV1.allCases.flatMap { key in
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            return [comment, value]
        }

        XCTAssertFalse(
            AuthorityCriterionLocalizationPolicyV1.containsProhibitedClaim(in: c40Text)
        )
        XCTAssertFalse(c40Text.contains { $0 == "\n" })
        XCTAssertFalse(c40Text.contains { $0 == "\r" })
        for restricted in ["http://", "https://", "file://", "raw sample", "private locator"] {
            XCTAssertFalse(
                c40Text.contains { $0.localizedCaseInsensitiveContains(restricted) },
                restricted
            )
        }

        XCTAssertTrue(
            AuthorityCriterionLocalizationPolicyV1.containsProhibitedClaim(
                in: ["SAFE", "COMPLIANT", "CERTIFIED", "AHJ", "professional"]
            )
        )
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesLicensedSourceText)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesRawMeasurementSamples)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesQualificationDetail)
        XCTAssertTrue(AuthorityCriterionLocalizationPolicyV1.excludesUnsupportedClaims)

        let hostileAuthorityText = [
            "safe-compliant-certified-copy-leak",
            "Legal research engine",
            "GPS-derived jurisdiction",
            "automatic legal precedence or AHJ selection",
            "automatic compliance or safety score",
            "licensed source text",
            "web-updated standards",
            "user-authored evaluator or script",
            "full UCUM or second unit system",
            "second reference store",
            "package-specific table or writer",
            "S10 release or brand approval",
        ]
        XCTAssertTrue(
            hostileAuthorityText.allSatisfy {
                AuthorityCriterionClaimVocabularyV1.containsProhibitedClaim(in: [$0])
            }
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://authority.example/source", "file:///Users/private/source"]
            )
        )
    }

    func testC41FunctionalRelationshipLocalizationIsCustomerSafeAndClaimBounded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = root
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let c41Text = try FunctionalRelationshipLocalizationKeyV1.allCases.flatMap { key in
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            return [comment, try XCTUnwrap(unit["value"] as? String)]
        }

        XCTAssertFalse(
            FunctionalRelationshipLocalizationPolicyV1.containsProhibitedClaim(in: c41Text)
        )
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.excludesOwnershipClaims)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.excludesAuthorizationClaims)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.excludesComplianceClaims)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.excludesSafetyClaims)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.excludesTelemetryClaims)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.excludesRemoteClaims)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(FunctionalRelationshipLocalizationPolicyV1.requiresActionableNextStep)

        XCTAssertFalse(c41Text.contains { $0 == "\n" })
        XCTAssertFalse(c41Text.contains { $0 == "\r" })
        for restricted in [
            "http://", "https://", "file://", "private locator", "raw sample",
        ] {
            XCTAssertFalse(
                c41Text.contains { $0.localizedCaseInsensitiveContains(restricted) },
                restricted
            )
        }

        let hostileRelationshipText = [
            "ownership asserted", "authorization granted", "compliance result",
            "safety guarantee", "telemetry stream", "remote command",
            "owned by a provider", "cross-site remote operation",
        ]
        XCTAssertTrue(
            hostileRelationshipText.allSatisfy {
                FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(in: [$0])
            }
        )
        XCTAssertFalse(
            FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(
                in: ["Recorded source to target relationship", "safely recorded state"]
            )
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://relationship.example/type", "file:///Users/private/relationship"]
            )
        )
    }

    func testC13EvidenceVisibilityLocalizationIsDenyByDefaultAndClaimBounded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = root
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        XCTAssertEqual(object["sourceLanguage"] as? String, "en")
        XCTAssertEqual(object["version"] as? String, "1.0")
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let c13Text = try EvidenceVisibilityLocalizationKeyV1.allCases.flatMap { key in
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            return [comment, try XCTUnwrap(unit["value"] as? String)]
        }

        XCTAssertFalse(
            EvidenceVisibilityLocalizationPolicyV1.containsProhibitedClaim(in: c13Text)
        )
        XCTAssertFalse(
            EvidenceVisibilityLocalizationPolicyV1.containsCustomerDataLeakage(in: c13Text)
        )
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresExplicitAudience)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresRecordedSensitivity)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.excludesCustomerDataLeakage)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.excludesUnsupportedClaims)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(EvidenceVisibilityLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertFalse(EvidenceVisibilityLocalizationPolicyV1.allowsColorOnlyState)
        XCTAssertFalse(EvidenceVisibilityLocalizationPolicyV1.allowsIconOnlyState)

        let hostileClaims = [
            "approval granted", "authorship recorded", "legal signature",
            "non-repudiation asserted", "tamper-proof archive", "verified identity",
            "secure delivery", "sent successfully", "delivered successfully",
            "compliance result", "professional service", "customer-data leakage",
        ]
        XCTAssertTrue(hostileClaims.allSatisfy {
            EvidenceVisibilityClaimVocabularyV1.containsProhibitedClaim(in: [$0])
        })
        XCTAssertTrue(
            EvidenceVisibilityClaimVocabularyV1.containsCustomerDataLeakage(
                in: ["customer data", "private data", "personal data"]
            )
        )
        XCTAssertFalse(
            EvidenceVisibilityClaimVocabularyV1.containsProhibitedClaim(
                in: ["Recorded audience scope", "Observed limitation"]
            )
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://visibility.example/evidence", "file:///Users/private/evidence"]
            )
        )
    }

    func testC14InspectionReviewLocalizationIsCustomerSafeAndClaimBounded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = root
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        XCTAssertEqual(object["sourceLanguage"] as? String, "en")
        XCTAssertEqual(object["version"] as? String, "1.0")
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let c14Text = try InspectionReviewLocalizationKeyV1.allCases.flatMap { key in
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            return [comment, try XCTUnwrap(unit["value"] as? String)]
        }

        XCTAssertFalse(
            InspectionReviewLocalizationPolicyV1.containsProhibitedClaim(in: c14Text)
        )
        XCTAssertFalse(
            InspectionReviewLocalizationPolicyV1.containsCustomerDataLeakage(in: c14Text)
        )
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.requiresTextAndIconForIndeterminateStates)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertFalse(InspectionReviewLocalizationPolicyV1.allowsColorOnlyState)
        XCTAssertFalse(InspectionReviewLocalizationPolicyV1.allowsIconOnlyState)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.excludesCustomerDataLeakage)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(InspectionReviewLocalizationPolicyV1.excludesUnsupportedClaims)

        let hostileClaims = [
            "approval granted", "authorization granted", "verified identity",
            "legal signature", "compliance result", "tamperproof history",
            "nonrepudiation asserted", "secure delivery", "sent successfully",
            "delivered successfully", "professional certification",
        ]
        XCTAssertTrue(hostileClaims.allSatisfy {
            InspectionReviewClaimVocabularyV1.containsProhibitedClaim(in: [$0])
        })
        XCTAssertTrue(
            InspectionReviewClaimVocabularyV1.containsCustomerDataLeakage(
                in: ["customer data", "customer-data leak", "private data", "personal data"]
            )
        )
        XCTAssertFalse(
            InspectionReviewClaimVocabularyV1.containsProhibitedClaim(
                in: ["Recorded review state", "Changes requested", "Awaiting recorded check"]
            )
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://review.example/request", "file:///Users/private/review"]
            )
        )
    }

    func testC15WorkPacketLocalizationIsSecretAndWorkDataFree() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = root
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        XCTAssertEqual(object["sourceLanguage"] as? String, "en")
        XCTAssertEqual(object["version"] as? String, "1.0")
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let c15Text = try WorkPacketLocalizationKeyV1.allCases.flatMap { key in
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            return [comment, value]
        }

        XCTAssertFalse(
            WorkPacketLocalizationPolicyV1.containsProhibitedClaim(in: c15Text)
        )
        XCTAssertFalse(
            WorkPacketLocalizationPolicyV1.containsSensitiveDataLeakage(in: c15Text)
        )
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.requiresNonColorStateText)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.requiresTextAndIconForIndeterminateStates)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.requiresActionableNextStep)
        XCTAssertFalse(WorkPacketLocalizationPolicyV1.allowsColorOnlyState)
        XCTAssertFalse(WorkPacketLocalizationPolicyV1.allowsIconOnlyState)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesSecrets)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesCustomerData)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesWorkData)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesCustomerDataLeakage)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(WorkPacketLocalizationPolicyV1.excludesUnsupportedClaims)

        let hostileClaims = [
            "approval granted", "authorization granted", "verified identity",
            "legal signature", "compliance result", "tamperproof history",
            "non-repudiation asserted", "secure delivery", "sent successfully",
            "delivered successfully", "professional certification",
        ]
        XCTAssertTrue(hostileClaims.allSatisfy {
            WorkPacketClaimVocabularyV1.containsProhibitedClaim(in: [$0])
        })
        XCTAssertTrue(
            WorkPacketClaimVocabularyV1.containsSensitiveDataLeakage(
                in: [
                    "customer data", "customer-information leak", "private data",
                    "work data", "work product", "secret", "credential", "password",
                ]
            )
        )
        XCTAssertTrue(
            WorkPacketClaimVocabularyV1.containsCustomerDataLeakage(
                in: ["customer information", "work data"]
            )
        )
        XCTAssertFalse(
            WorkPacketClaimVocabularyV1.containsProhibitedClaim(
                in: ["Recorded packet state", "Claim released", "Minimum requirement"]
            )
        )
        XCTAssertTrue(
            AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: ["https://packet.example/item", "file:///Users/private/work-packet"]
            )
        )
    }

    func testV23P03C36FieldDraftLocalizationIsSecretAndClaimFree() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = root
            .appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        XCTAssertEqual(object["sourceLanguage"] as? String, "en")
        XCTAssertEqual(object["version"] as? String, "1.0")
        let strings = try XCTUnwrap(object["strings"] as? [String: Any])
        let expectedKeys = Set(FieldDraftLocalizationKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(
            Set(strings.keys.filter { $0.hasPrefix("field.draft.") }),
            expectedKeys
        )

        let text = try FieldDraftLocalizationKeyV1.allCases.flatMap { key -> [String] in
            let entry = try XCTUnwrap(strings[key.rawValue] as? [String: Any])
            let comment = try XCTUnwrap(entry["comment"] as? String)
            XCTAssertFalse(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(["en"]))
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertEqual(value, key.englishDefaultValue)
            return [comment, value]
        }

        XCTAssertFalse(FieldDraftClaimVocabularyV1.containsProhibitedClaim(in: text))
        XCTAssertFalse(FieldDraftClaimVocabularyV1.containsSensitiveDataLeakage(in: text))
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.denyByDefault)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesSecrets)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesCustomerData)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesWorkData)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesPrivateLocators)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.excludesUnsupportedClaims)
        XCTAssertTrue(FieldDraftLocalizationPolicyV1.readyLocallyIsStagingOnly)
        XCTAssertTrue(
            FieldDraftClaimVocabularyV1.containsProhibitedClaim(
                in: [
                    "approval granted", "authorization granted", "verified identity",
                    "legal signature", "compliance result", "tamperproof history",
                    "tamper-proof history", "nonrepudiation asserted",
                    "non-repudiation asserted", "secure delivery", "sent successfully",
                    "delivered successfully", "synced to the cloud", "remote upload",
                ]
            )
        )
        XCTAssertTrue(
            FieldDraftClaimVocabularyV1.containsSensitiveDataLeakage(
                in: [
                    "customer data", "customer-information leak", "private data",
                    "personal data", "work item data", "secret credential", "password",
                    "private locator", "filename", "photo EXIF metadata",
                ]
            )
        )
        XCTAssertTrue(
            FieldDraftClaimVocabularyV1.containsCustomerOrWorkDataLeakage(
                in: ["customer data", "work data"]
            )
        )
        XCTAssertFalse(
            FieldDraftClaimVocabularyV1.containsProhibitedClaim(
                in: [
                    "Saved on this iPhone", "Saving on this iPhone", "Ready locally",
                    "Recorded checkpoint state", "Resume available", "Safe action",
                ]
            )
        )
        XCTAssertFalse(
            FieldDraftClaimVocabularyV1.containsSensitiveDataLeakage(
                in: ["Recorded local state", "Ready locally", "Minimum requirement"]
            )
        )
    }
}

private final class C27S83TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(ExternalKeyNormalizationV1.allCases.count, 2)
        XCTAssertEqual(AssetLocatorLimitsV1.maximumNamespaceBytes, 128)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension S8_3DiagnosticPrivacyTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension S8_3DiagnosticPrivacyTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.receiptInsideVerifiedArchive)
    }
}

private final class DiagnosticsLogProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var events = [DiagnosticsLogEvent]()

    func append(_ event: DiagnosticsLogEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [DiagnosticsLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

extension S8_3DiagnosticPrivacyTests {
    func testV23P03C41CorpusContainsNoCustomerOrSecretDiagnosticData() throws {
        let url = C41FunctionalRelationshipTestSupportV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/FunctionalRelationships/V21P03C41FunctionalRelationshipCorpusV1.json"
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )

        XCTAssertEqual(root["synthetic"] as? Bool, true)
        XCTAssertEqual(root["containsCustomerData"] as? Bool, false)
        XCTAssertEqual(root["containsSecrets"] as? Bool, false)
        let claims = try XCTUnwrap(root["claims"] as? [String: Any])
        XCTAssertTrue(claims.values.allSatisfy { ($0 as? Bool) == false })
        XCTAssertTrue(root.keys.contains("localizationAccessibility"))
    }

    func testV23P03C19MeasurementEvidenceRemainsLocalAndProviderFree() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        XCTAssertTrue(fixture.capture.measurement.source.isLocalMeasurementCaptureSource)
        XCTAssertFalse(fixture.capture.evidence.contains {
            $0.contentID.localizedCaseInsensitiveContains("provider")
                || $0.contentID.localizedCaseInsensitiveContains("cloud")
        })
        XCTAssertFalse(MeasurementIntegrityLifecycleCatalogV1.persistentKinds.contains("REMOTE_PROVIDER_V1"))
        XCTAssertTrue(MeasurementIntegrityEraseBoundaryV1.workspaceEraseClearsEntireClosure)
    }

    func testC20PrivacyTransformDiagnosticsCarryNoProviderOrLegalClaim() throws {
        let corpusURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V21/PrivacyTransform/V21P03C20PrivacyTransformCorpusV1.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: corpusURL)) as? [String: Any])
        XCTAssertEqual(object["noCloudClaim"] as? Bool, true)
        XCTAssertEqual(object["noLegalClaim"] as? Bool, true)
        XCTAssertEqual(object["noRecognitionClaim"] as? Bool, true)
    }
}

extension S8_3DiagnosticPrivacyTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension S8_3DiagnosticPrivacyTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        let settings = try SettingsRegistryV1.current()
        let recent = try settings.descriptor(for: "device.recentInputMemory")
        XCTAssertEqual(recent.scope, .deviceLocal)
        XCTAssertEqual(recent.backup, .excludedDeviceLocal)
        XCTAssertEqual(recent.privacy, .devicePreferenceNoCustomerData)
        XCTAssertEqual(SurveyDefinitionDeviceMemoryV1.favoriteKey, "device.surveyDefinition.favoriteIDs")
        XCTAssertEqual(SurveyDefinitionDeviceMemoryV1.recentsKey, "device.surveyDefinition.recentIDs")
        XCTAssertNoThrow(try SurveyDefinitionDeviceMemoryV1.validatePolicy())
    }
}
extension S8_3DiagnosticPrivacyTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S8_3DiagnosticPrivacyTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}

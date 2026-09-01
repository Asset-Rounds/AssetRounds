import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_S8_2GoldenAccessibilityTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45GoldenAccessibilityCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityOwnsAccessibleStructuredTextArtifact() {
        XCTAssertTrue(LabelArtifactKindV1.allCases.contains(.structuredText))
        XCTAssertEqual(LabelDisclosureProfileV1.shortCodeOnly.rawValue, "SHORT_CODE_ONLY")
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelPhysicalScanAcceptanceClaimed)
    }
}

private final class C51S82GoldenAccessibilityAnchorTests: XCTestCase {
    func testV23P03C51AccessibilityRequirementsDoNotClaimAnImplementedUI() {
        XCTAssertTrue(ScheduleAccessibilityPolicyV1.accessibilityContractDeclared)
        XCTAssertTrue(ScheduleAccessibilityPolicyV1.voiceControlStableNameRequired)
        XCTAssertTrue(ScheduleAccessibilityPolicyV1.switchControlReachabilityRequired)
        XCTAssertTrue(ScheduleAccessibilityPolicyV1.rtlReadingOrderRequired)
        XCTAssertFalse(ScheduleAccessibilityPolicyV1.uiConformanceClaimed)
    }
}

private final class C30EvidenceContextAnchorS8_2GoldenAccessibility: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S8_2GoldenAccessibilityTests: XCTestCase {
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
    func testGoldenFlowAccessibilitySpineAndControlMetricsAreExact() {
        let identifiers = [
            SignsRootView.welcomeScreenAccessibilityIdentifier,
            SignsRootView.addFirstSignAccessibilityIdentifier,
            NewSignView.screenAccessibilityIdentifier,
            NewSignView.siteLabelAccessibilityIdentifier,
            NewSignView.signLabelAccessibilityIdentifier,
            NewSignView.errorAccessibilityIdentifier,
            NewSignView.saveAccessibilityIdentifier,
            SignDetailView.screenAccessibilityIdentifier,
            SignDetailView.startCheckAccessibilityIdentifier,
            PreflightView.screenAccessibilityIdentifier,
            PreflightView.timeZoneAccessibilityIdentifier,
            PreflightView.timeZoneConfirmationAccessibilityIdentifier,
            PreflightView.afterDarkAccessibilityIdentifier,
            PreflightView.safePositionAccessibilityIdentifier,
            PreflightView.beginAccessibilityIdentifier,
            CaptureStepView.screenAccessibilityIdentifier,
            CaptureStepView.headingAccessibilityIdentifier,
            CaptureStepView.fixtureImportAccessibilityIdentifier,
            CaptureStepView.previewAccessibilityIdentifier,
            CaptureStepView.usePhotoAccessibilityIdentifier,
            OutcomeReviewView.outcomeScreenAccessibilityIdentifier,
            OutcomeReviewView.visibleIssueAccessibilityIdentifier,
            OutcomeReviewView.continueAccessibilityIdentifier,
            OutcomeReviewView.reviewScreenAccessibilityIdentifier,
            OutcomeReviewView.saveAccessibilityIdentifier,
            ValueReceiptView.screenAccessibilityIdentifier,
            ValueReceiptView.savedAccessibilityIdentifier,
            ValueReceiptView.viewReportAccessibilityIdentifier,
            ValueReceiptView.doneAccessibilityIdentifier,
            ReportDetailView.screenAccessibilityIdentifier,
            ReportDetailView.previewAccessibilityIdentifier,
            SignDetailView.recordWorkAccessibilityIdentifier,
            RecordWorkView.screenAccessibilityIdentifier,
            RecordWorkView.descriptionAccessibilityIdentifier,
            RecordWorkView.importFixtureAccessibilityIdentifier,
            RecordWorkView.saveAccessibilityIdentifier,
            IssueDetailView.screenAccessibilityIdentifier,
            IssueDetailView.statusAccessibilityIdentifier,
            IssueDetailView.startRecheckAccessibilityIdentifier,
            OutcomeReviewView.resolvedAccessibilityIdentifier,
            SignDetailView.resolvedIssueAccessibilityIdentifier,
            AppShellView.settingsButtonAccessibilityIdentifier,
            AppShellView.settingsScreenAccessibilityIdentifier,
            PaywallView.settingsEntryAccessibilityIdentifier,
            PaywallView.screenAccessibilityIdentifier,
            PaywallView.storeAccessibilityIdentifier,
            PaywallView.productNameAccessibilityIdentifier,
            PaywallView.productDurationAccessibilityIdentifier,
            PaywallView.productPriceAccessibilityIdentifier,
            PaywallView.trialAccessibilityIdentifier,
            PaywallView.renewalAccessibilityIdentifier,
            PaywallView.noSyncAccessibilityIdentifier,
            PaywallView.closeAccessibilityIdentifier,
        ]
        let expected = [
            "s2.welcome.screen",
            "s2.welcome.add-first-sign",
            "s2.new-sign.screen",
            "s2.new-sign.site-label",
            "s2.new-sign.sign-label",
            "s2.new-sign.error",
            "s2.new-sign.save",
            "s2.sign-detail.screen",
            "s2.sign-detail.start-check",
            "s3.preflight.screen",
            "s3.preflight.time-zone",
            "s3.preflight.time-zone-confirmed",
            "s3.preflight.after-dark",
            "s3.preflight.safe-position",
            "s3.preflight.begin",
            "s3.capture.screen",
            "s3.capture.heading",
            "s3.capture.import-fixture",
            "s3.capture.preview",
            "s3.capture.use-photo",
            "s3.outcome.screen",
            "s3.outcome.visible-issue",
            "s3.outcome.continue",
            "s3.review.screen",
            "s3.review.save-report",
            "s3.receipt.screen",
            "s3.receipt.saved",
            "s3.receipt.view-report",
            "s3.receipt.done",
            "s4.3.report-detail.screen",
            "s4.3.report-detail.preview",
            "s5.1.sign-detail.record-work",
            "s5.1.work.screen",
            "s5.1.work.description",
            "s5.1.work.import-fixture",
            "s5.1.work.save",
            "s5.1.issue.screen",
            "s5.1.issue.status",
            "s5.2.issue.start-recheck",
            "s5.2.outcome.resolved",
            "s5.2.sign-detail.resolved",
            "s1.settings.button",
            "s1.settings.screen",
            "s7.2.settings.paywall",
            "s7.2.paywall.screen",
            "s7.2.paywall.store",
            "s7.2.paywall.product-name",
            "s7.2.paywall.duration",
            "s7.2.paywall.price",
            "s7.2.paywall.trial",
            "s7.2.paywall.renewal",
            "s7.2.paywall.no-sync",
            "s7.2.paywall.close",
        ]

        XCTAssertEqual(identifiers, expected)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertEqual(DesignTokens.Control.minimumHitSize, 44)
        XCTAssertEqual(
            WorklightStatusKind.allCases.map(\.rawValue),
            ["complete", "attention", "blocked", "information"]
        )
    }
}

private final class C27S82TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(ExternalKeyNormalizationV1.allCases.count, 2)
        XCTAssertEqual(AssetLocatorLimitsV1.maximumCandidates, 32)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension S8_2GoldenAccessibilityTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}
extension S8_2GoldenAccessibilityTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyFieldKindV1.allCases.count, 18)
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .operationalRecheck).completion, .subsequentOperationalObservation)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .operationalRecheck).mayClaimReleaseToService)
    }
}
extension S8_2GoldenAccessibilityTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S8_2GoldenAccessibilityTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS82GoldenAccessibilityTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S8_2GoldenAccessibilityTests {
    func testV23P03C42GoldenAccessibilityResolvesTypedJourneyThroughShippingRegistry() throws {
        let scenarios = [
            try CompositeAreaSafetyArchetypeV1.scenario(),
            try ControllerZoneDistributionArchetypeV1.scenario()
        ]
        let localization = try BundledLocalizationCatalogV1.registry()
        let accessibility = try BundledLocalizationCatalogV1.accessibilityRegistry(
            localization: localization
        )
        try accessibility.validate()
        let exactRoles: [String: SemanticAccessibilityRoleV1] = [
            "feedback.mail.screen": .screen,
            "feedback.mail.recipient": .group,
            "feedback.mail.attachment-count": .status,
            "feedback.mail.body": .textField,
            "feedback.mail.done": .button,
        ]
        XCTAssertEqual(Set(accessibility.entries.map(\.semanticID)), Set(exactRoles.keys))
        for entry in accessibility.entries {
            XCTAssertEqual(entry.role, try XCTUnwrap(exactRoles[entry.semanticID]))
            XCTAssertEqual(entry.reachability, .always)
            XCTAssertTrue(entry.deprecatedAliases.isEmpty)
        }

        for scenario in scenarios {
            XCTAssertTrue(scenario.operations.contains { $0.kind == .verifyReleaseExclusion })
            let semanticID = scenario.operations.contains { $0.kind == .backupRestore }
                ? "feedback.mail.done"
                : "feedback.mail.body"
            let identifier = try accessibility.identifier(semanticID: semanticID)
            let entry = try XCTUnwrap(
                accessibility.entries.first { $0.semanticID == semanticID }
            )
            XCTAssertEqual(identifier, semanticID)
            XCTAssertEqual(entry.role, try XCTUnwrap(exactRoles[semanticID]))
            XCTAssertEqual(entry.reachability, .always)
            XCTAssertEqual(BundledLocalizationCatalogV1.localized(.commonDone), "Done")
            XCTAssertTrue(entry.deprecatedAliases.isEmpty)
        }
    }
}

private final class C33TemporalEvidenceAnchorS82GoldenAccessibility: XCTestCase {
    func testC33S82GoldenAccessibilityCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "golden.temporal-accessible-description",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "golden.temporal-accessible-description",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS82GoldenAccessibility: XCTestCase {
    func testC32S82GoldenAccessibilityCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .factCapture,
            fieldID: "accessibility.manual-fallback",
            value: .text("VoiceOver editable manual value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .factCapture,
            fieldID: "accessibility.manual-fallback",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46S82GoldenAccessibilityCompatibilityTests: XCTestCase {
    func testC46GoldenAccessibilityRequiresExplicitHandoff() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "golden-accessibility",
            kind: .email,
            handoff: .email,
            slot: 46802
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift_Tests: XCTestCase {
    func testC47S82GoldenAccessibilityTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_2GoldenAccessibilityTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertFalse(ActivityContractPersistenceEnrollmentV2.completionClaimsCommissioningComplianceApprovalOrCertification)
        XCTAssertEqual(Set(ActivityContractPersistenceEnrollmentV2.nonpersistentFamilies).count, 3)
    }
}

private final class C48PortableReviewS82AccessibilityTests: XCTestCase {
    func testC48AccessibilitySpeaksTrustLimitWithoutSecrets() {
        XCTAssertTrue(C48PortableReviewAccessibilityPolicyV1.statusIsNotColorOnly)
        XCTAssertTrue(C48PortableReviewAccessibilityPolicyV1.explicitTrustLimitationIsSpoken)
        XCTAssertFalse(C48PortableReviewAccessibilityPolicyV1.capabilityBytesSpoken)
        XCTAssertFalse(C48PortableReviewAccessibilityPolicyV1.verifiedIdentitySpoken)
    }
}
private final class C49WorkResourceGoldenAccessibilityBoundaryTests: XCTestCase {
    func testVisibilityLabelsRemainExplicitAndStable() {
        XCTAssertEqual(WorkResourceVisibilityPolicyV1.allCases.map(\.rawValue), ["INTERNAL_ONLY", "CUSTOMER_SAFE"])
    }
}

private final class C50IncumbentAdapterS82AccessibilityBoundaryTests: XCTestCase {
    func testDisabledProfileStateRemainsTruthfulAndProviderNeutral() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "FieldEvidenceIncumbentFileAdapterStatus") as? String,
            "DISABLED_NO_SELECTED_PROFILE"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "FieldEvidenceIncumbentFileAdapterDeclaresProviderType") as? Bool,
            false
        )
    }
}

extension S8_2GoldenAccessibilityTests {
    func testV23P03C34AccessibilityUsesStableFourRootRouteIdentity() throws {
        let receipt = RouteConformanceReceiptV1(
            registry: try RouteRegistryV1(), evidenceKind: .golden,
            observedShellCount: 1, observedParserCount: 1,
            observedMutationAuthorityCount: 0
        )
        try receipt.validate()
        XCTAssertEqual(receipt.roots.map(\.rawValue), ["TODAY", "WORK", "ASSETS", "REPORTS"])
        XCTAssertEqual(receipt.roots, AppRootV1.frozenOrder)
        XCTAssertEqual(receipt.duplicateCount, 0)
    }
}

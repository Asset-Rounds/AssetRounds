import Foundation
import CryptoKit
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_16SnapshotProjectionTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_V9_16SnapshotProjectionTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

final class C50SnapshotProjectionTests: XCTestCase {
    func testV23P03C50PrivacyManifestKeepsSensitiveClassesExplicitAndNeverImplicit() throws {
        XCTAssertEqual(IncumbentCanonicalFieldV1.allCases, [
            .fileFormatVersion,
            .portableReviewPublicID,
            .portableReviewState,
            .portableReviewLatestResponsePublicID,
            .workDurationMinutes,
            .workMaterialLineCount,
            .workMaterialTotals,
        ])
        let manifest = try IncumbentMappingManifestV1(mappings: [
            IncumbentFieldMappingV1(
                externalHeader: "Review Public ID",
                canonicalField: .portableReviewPublicID,
                required: false
            ),
            IncumbentFieldMappingV1(
                externalHeader: "Version",
                canonicalField: .fileFormatVersion,
                required: true
            ),
        ])
        XCTAssertEqual(
            manifest.mappings.map(\.canonicalField),
            [.portableReviewPublicID, .fileFormatVersion]
        )
        XCTAssertTrue(manifest.mappings.allSatisfy { $0.fieldClass == .ordinary })
        XCTAssertThrowsError(try IncumbentFieldMappingV1(
            externalHeader: "Direct Cost",
            canonicalField: "workResource.directCost",
            fieldClass: .directCost,
            required: false
        )) {
            XCTAssertEqual($0 as? IncumbentFileContractFailureV1, .fieldNotAllowed)
        }
        try manifest.validate()
    }
}

final class C51V916SnapshotProjectionAnchorTests: XCTestCase {
    func testV23P03C51SnapshotAdoptsOnlyDerivedScheduleClosureMetadata() {
        let _: C51ScheduleClosureMetadataV1.Type =
            C51CompletedActivitySnapshotScheduleBoundaryV1.scheduleClosureMetadataType
        let _: AdvancedScheduleReportProjectionV1.Type = AdvancedScheduleReportProjectionV1.self
        XCTAssertTrue(C51CompletedActivitySnapshotScheduleBoundaryV1.scheduleClosureIsDerivedMetadataOnly)
        XCTAssertTrue(C51CompletedActivitySnapshotScheduleBoundaryV1.snapshotCanonicalBytesRemainUnchanged)
    }
}

final class C45SnapshotProjectionCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityProjectsExactlyPDFFormulaSafeCSVAndText() {
        XCTAssertEqual(LabelArtifactKindV1.allCases, [.pdf, .formulaSafeCSV, .structuredText])
        XCTAssertEqual(AssetLabelCanonicalCodecV1.maximumCanonicalByteCount, 16 * 1_024 * 1_024)
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("LabelProjectionResultV1"))
    }
}

final class C30EvidenceContextAnchorV9_16SnapshotProjection: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_16SnapshotProjectionTests: XCTestCase {
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
    func testV23P03C13PreviewManifestBindsVisibilityAndRejectsStaleInputs() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c130")!)
        let customerVisibility = try EvidenceVisibilityV1(
            visibilityID: UUID(uuidString: "00000000-0000-4000-8000-00000000c131")!,
            workspaceID: workspace,
            sensitivity: .routine,
            allowedAudiences: [.internalReview, .customerReport],
            effectiveAt: Date(timeIntervalSince1970: 100),
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c132")!
            )
        )
        let internalVisibility = try EvidenceVisibilityV1(
            visibilityID: UUID(uuidString: "00000000-0000-4000-8000-00000000c133")!,
            workspaceID: workspace,
            sensitivity: .routine,
            allowedAudiences: [.internalReview],
            effectiveAt: Date(timeIntervalSince1970: 100),
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c134")!
            )
        )
        let included = try ClaimEvidenceLinkV1(
            linkID: UUID(uuidString: "00000000-0000-4000-8000-00000000c135")!,
            workspaceID: workspace,
            claimID: "claim-visible",
            evidenceID: "evidence-visible",
            evidenceRevision: 1,
            evidenceSHA256: String(repeating: "a", count: 64),
            visibility: customerVisibility,
            audience: .customerReport,
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c136")!
            )
        )
        let excluded = try ClaimEvidenceLinkV1(
            linkID: UUID(uuidString: "00000000-0000-4000-8000-00000000c137")!,
            workspaceID: workspace,
            claimID: "claim-internal",
            evidenceID: "evidence-internal",
            evidenceRevision: 1,
            evidenceSHA256: String(repeating: "b", count: 64),
            visibility: internalVisibility,
            audience: .customerReport,
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c138")!
            )
        )
        let preview = try AssuranceProjectionPreviewV1(
            previewID: UUID(uuidString: "00000000-0000-4000-8000-00000000c139")!,
            workspaceID: workspace,
            audience: .customerReport,
            snapshotSHA256: String(repeating: "c", count: 64),
            projectionVersion: "report-projection-v1",
            links: [included, excluded],
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let manifest = try AssuranceManifestV1(
            manifestID: UUID(uuidString: "00000000-0000-4000-8000-00000000c13a")!,
            preview: preview,
            recordedAt: Date(timeIntervalSince1970: 102),
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c13b")!
            )
        )
        let projection = try ReportEvidenceAssuranceProjectionV1(
            preview: preview,
            manifest: manifest,
            visibilities: [internalVisibility, customerVisibility]
        )
        try projection.validate(
            expectedSnapshotSHA256: String(repeating: "c", count: 64),
            expectedProjectionVersion: "report-projection-v1",
            expectedAudience: .customerReport
        )
        XCTAssertEqual(projection.omissionCount, 1)
        XCTAssertEqual(projection.limitationCodes, [.audienceNotDeclared])
        XCTAssertFalse(projection.publicationDisposition.isEmpty)

        let bytes = try ReportEvidenceAssuranceCanonicalCodecV1.encode(projection)
        XCTAssertEqual(try ReportEvidenceAssuranceCanonicalCodecV1.decode(bytes), projection)
        XCTAssertThrowsError(
            try projection.validate(expectedProjectionVersion: "stale-report-projection-v1")
        )
    }

    func testV23P03C41V6FunctionalRelationshipSnapshotIsRequiredAtTheTypeBoundary() {
        let keyPath: KeyPath<
            CompletedActivitySnapshotPayloadV6,
            CompletedFunctionalRelationshipSnapshotV1
        > = \.functionalRelationships
        XCTAssertNotNil(keyPath)
        XCTAssertEqual(CompletedActivitySnapshotPayloadV6.schemaVersion, 6)
        XCTAssertEqual(CompletedFunctionalRelationshipSnapshotV1.schemaVersion, 1)
        XCTAssertEqual(
            ReportFunctionalRelationshipsProjectionPolicyV1.sectionID,
            "functional-relationships"
        )
        XCTAssertTrue(ReportFunctionalRelationshipsProjectionPolicyV1.requiredTypedLabels)
        XCTAssertTrue(
            ReportFunctionalRelationshipsProjectionPolicyV1
                .excludesOwnershipAuthorizationComplianceClaims
        )
    }

    func testV23P03C40V5AuthorityProjectionIsRequiredAtTheTypeBoundary() {
        let keyPath: KeyPath<
            CompletedActivitySnapshotPayloadV5,
            CompletedAuthorityCriterionSnapshotV1
        > = \.authorityCriterion
        XCTAssertNotNil(keyPath)
        XCTAssertEqual(CompletedActivitySnapshotPayloadV5.schemaVersion, 5)
        XCTAssertEqual(CompletedAuthorityCriterionSnapshotV1.schemaVersion, 1)
    }

    func testV23P03C39WorkSubjectReferenceSnapshotIsCanonical() throws {
        let reference = WorkSubjectReferenceV1(
            kind: .asset,
            subjectID: UUID(uuidString: "00000000-0000-0000-0000-000000002301")!,
            revision: 1,
            ownerAssetID: nil
        )
        try reference.validate()
        let bytes = try AssetSemanticCanonicalCodecV1.encode(reference)
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode(WorkSubjectReferenceV1.self, from: bytes),
            reference
        )
    }

    func testV9_16G01CanonicalSnapshotAndRepeatProjectionBytesAreStable() throws {
        let fixture = try makeFixture(snapshotRevision: 1)
        let registry = ReportProjectionRegistryV1()
        guard case .complete(let first) = try registry.render(snapshot: fixture.snapshot, manifest: fixture.manifest, reportProfile: fixture.layout, exportProfile: fixture.export),
              case .complete(let second) = try registry.render(snapshot: fixture.snapshot, manifest: fixture.manifest, reportProfile: fixture.layout, exportProfile: fixture.export) else {
            return XCTFail("complete deterministic projection expected")
        }
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.pdf.sha256, KernelCanonicalHashV1.sha256(first.pdf.data))
        XCTAssertEqual(first.openJSON.sha256, KernelCanonicalHashV1.sha256(first.openJSON.data))
        XCTAssertEqual(first.structuredText.sha256, KernelCanonicalHashV1.sha256(first.structuredText.data))
        XCTAssertEqual(
            try CompletedActivitySnapshotCanonicalCodecV1.encode(fixture.snapshot),
            try CompletedActivitySnapshotCanonicalCodecV1.encode(fixture.snapshot)
        )
        let canonical = try CompletedActivitySnapshotCanonicalCodecV1.encode(fixture.snapshot)
        var unknownKeyDocument = Data("{\"unexpected\":true,".utf8)
        unknownKeyDocument.append(canonical.dropFirst())
        XCTAssertThrowsError(try CompletedActivitySnapshotCanonicalCodecV1.decode(unknownKeyDocument))
        var explicitNullRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        var explicitNullPayload = try XCTUnwrap(explicitNullRoot["payload"] as? [String: Any])
        var explicitNullFacts = try XCTUnwrap(explicitNullPayload["serviceFacts"] as? [[String: Any]])
        explicitNullFacts[1]["effectiveAt"] = NSNull()
        explicitNullPayload["serviceFacts"] = explicitNullFacts
        explicitNullRoot["payload"] = explicitNullPayload
        let explicitNullDocument = try JSONSerialization.data(
            withJSONObject: explicitNullRoot,
            options: [.sortedKeys]
        )
        XCTAssertThrowsError(try CompletedActivitySnapshotCanonicalCodecV1.decode(explicitNullDocument))
        let legacyBytes = try legacyFixtureData(withExtension: "json")
        let legacySHA = try XCTUnwrap(String(data: legacyFixtureData(withExtension: "sha256"), encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(legacyBytes), legacySHA)
        let legacySnapshot = try ReportSnapshotEncoderV1().decode(legacyBytes)
        XCTAssertEqual(try ReportSnapshotEncoderV1().encode(legacySnapshot).data, legacyBytes)
        XCTAssertFalse(first.taggedPDFAccessibilityClaimed)
        XCTAssertTrue(first.accessibleStructuredTextAlwaysPresent)
        XCTAssertTrue(first.requiresFinalAudienceConfirmation)
        XCTAssertFalse(first.externalPublicationAuthorized)
    }

    func testV9_16A01PDFOpenJSONAndStructuredTextReconcileToOneSemanticProjection() throws {
        let fixture = try makeFixture(snapshotRevision: 1)
        guard case .complete(let bundle) = try ReportProjectionRegistryV1().render(
            snapshot: fixture.snapshot,
            manifest: fixture.manifest,
            reportProfile: fixture.layout,
            exportProfile: fixture.export
        ) else { return XCTFail("complete projection expected") }
        XCTAssertEqual(bundle.pdf.semanticSHA256, bundle.openJSON.semanticSHA256)
        XCTAssertEqual(bundle.openJSON.semanticSHA256, bundle.structuredText.semanticSHA256)
        XCTAssertEqual(bundle.pdf.orderedSemanticIDs, bundle.openJSON.orderedSemanticIDs)
        XCTAssertEqual(bundle.openJSON.orderedSemanticIDs, bundle.structuredText.orderedSemanticIDs)
        XCTAssertTrue(bundle.pdf.data.starts(with: Data("%PDF-1.4".utf8)))
        XCTAssertNotNil(String(data: bundle.structuredText.data, encoding: .utf8))
        let reopened = try JSONDecoder().decode(ReportSemanticProjectionV1.self, from: bundle.openJSON.data)
        XCTAssertEqual(reopened, bundle.semanticProjection)
        XCTAssertEqual(try DeterministicOpenJSONRendererV1.reopen(bundle.openJSON.data), bundle.semanticProjection)
        XCTAssertEqual(try DeterministicOpenJSONRendererV1.reopenStructuredText(bundle.structuredText.data), bundle.semanticProjection)
        XCTAssertEqual(try DeterministicPDFRendererV1.reopen(bundle.pdf.data), bundle.semanticProjection)
        XCTAssertTrue(reopened.nodes.contains(where: { $0.sectionID == "service" && $0.value == "Scheduled" }))
        XCTAssertTrue(reopened.nodes.contains(where: {
            $0.sectionID == "service" && $0.label == "Service history" && $0.value == "Request received"
        }))
        XCTAssertTrue(reopened.nodes.contains(where: { $0.sectionID == "limitations" }))
        let multilingual = try makeFixture(snapshotRevision: 1, serviceStatus: "Café معدات")
        guard case .complete(let multilingualBundle) = try ReportProjectionRegistryV1().render(
            snapshot: multilingual.snapshot,
            manifest: multilingual.manifest,
            reportProfile: multilingual.layout,
            exportProfile: multilingual.export
        ) else { return XCTFail("multilingual projection expected") }
        XCTAssertEqual(try DeterministicPDFRendererV1.reopen(multilingualBundle.pdf.data), multilingualBundle.semanticProjection)
        XCTAssertTrue(multilingualBundle.semanticProjection.nodes.contains(where: { $0.value == "Café معدات" }))
        let maximumText = String(repeating: "A", count: SnapshotProjectionLimitsV1.maximumTextBytes)
        let bounded = try makeFixture(snapshotRevision: 1, serviceStatus: maximumText)
        guard case .complete(let boundedBundle) = try ReportProjectionRegistryV1().render(
            snapshot: bounded.snapshot,
            manifest: bounded.manifest,
            reportProfile: bounded.layout,
            exportProfile: bounded.export
        ) else { return XCTFail("bounded projection expected") }
        XCTAssertEqual(try DeterministicPDFRendererV1.reopen(boundedBundle.pdf.data), boundedBundle.semanticProjection)
    }

    func testV9_16H01PrivacyBeforeMarkupOutputReferencesAndUnsupportedClaimsFailClosed() throws {
        let fixture = try makeFixture(snapshotRevision: 1)
        let card = try XCTUnwrap(fixture.snapshot.payload.evidenceCards.first)
        XCTAssertEqual(card.fields.map(\.fieldID), ["service_request", "service_status"])
        XCTAssertFalse(card.fields.contains(where: { $0.value == "PRIVATE-CANARY" }))
        XCTAssertTrue(card.outputReferences.allSatisfy({ $0.outputReferenceID.hasPrefix("out-") }))
        XCTAssertFalse(card.outputReferences.contains(where: { $0.outputReferenceID.contains("content-original") }))
        XCTAssertTrue(card.outputReferences.allSatisfy({
            $0.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(
                Data("workspace-a|output-scope-a".utf8)
            )
        }))
        XCTAssertFalse(card.outputReferences.contains(where: {
            $0.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(Data("workspace-a".utf8))
        }))
        let cardEncoder = JSONEncoder()
        cardEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let safeCardJSON = try XCTUnwrap(String(data: cardEncoder.encode(card), encoding: .utf8))
        let hostileCardJSON = safeCardJSON.replacingOccurrences(
            of: "Reviewed for customer-safe output",
            with: "PRIVATE-CANARY-NOTE"
        )
        XCTAssertThrowsError(try JSONDecoder().decode(EvidenceDetailCardV1.self, from: Data(hostileCardJSON.utf8)))
        XCTAssertThrowsError(try EvidenceDetailFieldV1(
            fieldID: "hostile", label: "Hostile", value: "hidden\u{0000}value", sensitivity: .audienceSafe
        ))
        XCTAssertThrowsError(try EvidenceDetailFieldV1(
            fieldID: "hostile-bidi", label: "Hostile", value: "hidden\u{202E}value", sensitivity: .audienceSafe
        ))
        XCTAssertThrowsError(try EvidenceDetailFieldV1(
            fieldID: "hostile-noncharacter", label: "Hostile", value: "hidden\u{FFFE}value", sensitivity: .audienceSafe
        ))
        XCTAssertThrowsError(try EvidenceDetailFieldV1(
            fieldID: "hostile-byte-bound",
            label: "Hostile",
            value: String(repeating: "é", count: (SnapshotProjectionLimitsV1.maximumTextBytes / 2) + 1),
            sensitivity: .audienceSafe
        ))
        XCTAssertThrowsError(try makeFixture(snapshotRevision: 1, duplicateOutputReferenceAcrossCards: true))
        let semanticText = "Reviewed customer-safe semantic output"
        let semanticSHA256 = String(repeating: "b", count: 64)
        let composedOutput = Data("Final reviewed customer-safe bytes".utf8)
        let blockedDetection = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: card,
            policy: card.audiencePrivacyPolicy,
            semanticText: semanticText,
            composedOutput: Data("PRIVATE-CANARY-NOTE".utf8),
            detectorID: "audience-privacy-detector-v1",
            detectorVersion: 1
        )
        XCTAssertEqual(blockedDetection.disposition, .blocked)
        let blockedBytes = try cardEncoder.encode(blockedDetection)
        var forgedPass = try XCTUnwrap(
            JSONSerialization.jsonObject(with: blockedBytes) as? [String: Any]
        )
        forgedPass["disposition"] = AudiencePrivacyDetectorDispositionV1.pass.rawValue
        forgedPass["findingKinds"] = []
        XCTAssertThrowsError(try JSONDecoder().decode(
            PostMarkupAudiencePrivacyDetectionV1.self,
            from: JSONSerialization.data(withJSONObject: forgedPass, options: [.sortedKeys])
        ))
        let detection = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: card,
            policy: card.audiencePrivacyPolicy,
            semanticText: semanticText,
            composedOutput: composedOutput,
            detectorID: "audience-privacy-detector-v1",
            detectorVersion: 1
        )
        let composedOutputSHA256 = KernelCanonicalHashV1.sha256(composedOutput)
        XCTAssertEqual(detection.disposition, .pass)
        XCTAssertThrowsError(try FinalAudiencePrivacyConfirmationV1(
            confirmationID: "confirm-not-user-approved",
            sourceSnapshotSHA256: fixture.snapshot.snapshotSHA256,
            semanticSHA256: semanticSHA256,
            composedOutputSHA256: composedOutputSHA256,
            card: card,
            detection: detection,
            userConfirmedExactComposedBytes: false
        ))
        let confirmation = try FinalAudiencePrivacyConfirmationV1(
            confirmationID: "confirm-forged",
            sourceSnapshotSHA256: fixture.snapshot.snapshotSHA256,
            semanticSHA256: semanticSHA256,
            composedOutputSHA256: composedOutputSHA256,
            card: card,
            detection: detection,
            userConfirmedExactComposedBytes: true
        )
        var mismatchedAudienceConfirmation = try XCTUnwrap(
            JSONSerialization.jsonObject(with: cardEncoder.encode(confirmation)) as? [String: Any]
        )
        var mismatchedDetection = try XCTUnwrap(
            mismatchedAudienceConfirmation["detection"] as? [String: Any]
        )
        mismatchedDetection["audience"] = ReportAudienceV1.internalUse.rawValue
        mismatchedAudienceConfirmation["detection"] = mismatchedDetection
        XCTAssertThrowsError(try JSONDecoder().decode(
            FinalAudiencePrivacyConfirmationV1.self,
            from: JSONSerialization.data(withJSONObject: mismatchedAudienceConfirmation, options: [.sortedKeys])
        ))
        let validReceipt = try EvidenceDetailCardRenderReceiptV1(
            receiptID: "receipt-valid",
            snapshotID: fixture.snapshot.payload.snapshotID,
            sourceSnapshotSHA256: fixture.snapshot.snapshotSHA256,
            semanticSHA256: semanticSHA256,
            card: card,
            composedOutputSHA256: composedOutputSHA256,
            confirmation: confirmation
        )
        XCTAssertEqual(confirmation.detection.composedOutput, composedOutput)
        XCTAssertEqual(
            KernelCanonicalHashV1.sha256(confirmation.detection.composedOutput),
            validReceipt.composedOutputSHA256
        )
        XCTAssertFalse(validReceipt.captureTimeVerified)
        XCTAssertFalse(validReceipt.locationVerified)
        XCTAssertFalse(validReceipt.personVerified)
        XCTAssertThrowsError(try EvidenceDetailCardRenderReceiptV1(
            receiptID: "receipt-forged",
            snapshotID: fixture.snapshot.payload.snapshotID,
            sourceSnapshotSHA256: fixture.snapshot.snapshotSHA256,
            semanticSHA256: String(repeating: "d", count: 64),
            card: card,
            composedOutputSHA256: String(repeating: "c", count: 64),
            confirmation: confirmation
        ))
        guard case .complete(let bundle) = try ReportProjectionRegistryV1().render(
            snapshot: fixture.snapshot, manifest: fixture.manifest,
            reportProfile: fixture.layout, exportProfile: fixture.export
        ) else { return XCTFail("complete projection expected") }
        XCTAssertFalse(bundle.pdf.taggedPDFAccessibilityEvidence)
        XCTAssertFalse(bundle.taggedPDFAccessibilityClaimed)
        let unsupportedAccessibilityClaim = ReportProjectionOutputV1(
            format: .pdf,
            data: bundle.pdf.data,
            sha256: bundle.pdf.sha256,
            semanticSHA256: bundle.pdf.semanticSHA256,
            orderedSemanticIDs: bundle.pdf.orderedSemanticIDs,
            taggedPDFAccessibilityEvidence: true
        )
        XCTAssertThrowsError(try ReportProjectionBundleV1(
            snapshot: fixture.snapshot,
            semanticProjection: bundle.semanticProjection,
            pdf: unsupportedAccessibilityClaim,
            openJSON: bundle.openJSON,
            structuredText: bundle.structuredText
        ))
        let mismatchedLayout = try ReportLayoutProfileV1(
            profileID: fixture.layout.profileID,
            profileRelease: fixture.layout.profileRelease,
            audience: fixture.layout.audience,
            detail: fixture.layout.detail,
            sectionIDs: fixture.layout.sectionIDs,
            mediaLayout: fixture.layout.mediaLayout,
            orientation: .landscape,
            localeIdentifier: fixture.layout.localeIdentifier,
            unitsProfileID: fixture.layout.unitsProfileID,
            displayProfileID: fixture.layout.displayProfileID,
            registry: fixture.manifest.reportSectionRegistry
        )
        XCTAssertThrowsError(try ReportProjectionRegistryV1().render(
            snapshot: fixture.snapshot,
            manifest: fixture.manifest,
            reportProfile: mismatchedLayout,
            exportProfile: fixture.export
        ))
    }

    func testV9_16I01InterruptedProjectionExposesZeroOrCompleteOutputAndRegeneratesIdempotently() throws {
        let fixture = try makeFixture(snapshotRevision: 1)
        let registry = ReportProjectionRegistryV1()
        for boundary in ReportProjectionPublicationBoundaryV1.allCases {
            XCTAssertEqual(
                try registry.render(snapshot: fixture.snapshot, manifest: fixture.manifest, reportProfile: fixture.layout, exportProfile: fixture.export, recoveringFrom: boundary),
                .zero,
                "boundary must publish no partial projection: \(boundary.rawValue)"
            )
        }
        guard case .complete(let complete) = try registry.render(snapshot: fixture.snapshot, manifest: fixture.manifest, reportProfile: fixture.layout, exportProfile: fixture.export) else {
            return XCTFail("complete retry expected")
        }
        XCTAssertEqual(try registry.recover(snapshot: fixture.snapshot, manifest: fixture.manifest, reportProfile: fixture.layout, exportProfile: fixture.export, storedBundle: nil), complete)
        XCTAssertEqual(try registry.recover(snapshot: fixture.snapshot, manifest: fixture.manifest, reportProfile: fixture.layout, exportProfile: fixture.export, storedBundle: complete), complete)
        var corruptedPDFBytes = complete.pdf.data
        corruptedPDFBytes.append(0x20)
        let corruptedPDF = ReportProjectionOutputV1(
            format: .pdf,
            data: corruptedPDFBytes,
            sha256: KernelCanonicalHashV1.sha256(corruptedPDFBytes),
            semanticSHA256: complete.pdf.semanticSHA256,
            orderedSemanticIDs: complete.pdf.orderedSemanticIDs,
            taggedPDFAccessibilityEvidence: false
        )
        XCTAssertThrowsError(try ReportProjectionBundleV1(
            snapshot: fixture.snapshot,
            semanticProjection: complete.semanticProjection,
            pdf: corruptedPDF,
            openJSON: complete.openJSON,
            structuredText: complete.structuredText
        ))
        let preview = try ReportPreviewProjectionV1(
            previewID: "preview-a", sourceRevision: 1, profileSHA256: fixture.snapshot.payload.profileBinding.reportProfileSHA256
        )
        XCTAssertTrue(preview.isStale(currentSourceRevision: 2, currentProfileSHA256: fixture.snapshot.payload.profileBinding.reportProfileSHA256))
        XCTAssertFalse(preview.hasReportEffect)
        XCTAssertFalse(preview.hasMetricEffect)
        XCTAssertFalse(preview.hasShareEffect)
        let previewBytes = try JSONEncoder().encode(preview)
        XCTAssertEqual(try JSONDecoder().decode(
            ReportPreviewProjectionV1.self, from: previewBytes
        ), preview)
        let previewObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: previewBytes) as? [String: Any]
        )
        for key in ["hasReportEffect", "hasMetricEffect", "hasShareEffect"] {
            var missing = previewObject
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(
                ReportPreviewProjectionV1.self,
                from: JSONSerialization.data(withJSONObject: missing)
            )) { XCTAssertTrue($0 is DecodingError) }
            var claimed = previewObject
            claimed[key] = true
            XCTAssertThrowsError(try JSONDecoder().decode(
                ReportPreviewProjectionV1.self,
                from: JSONSerialization.data(withJSONObject: claimed)
            )) { XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .partialEffect) }
        }
        let privacyPolicy = try AudiencePrivacyPolicyV1(
            policyID: "strict-report-policy", policyVersion: 1,
            audience: .customerSafe, prohibitedCanaries: ["private-canary"]
        )
        XCTAssertEqual(try JSONDecoder().decode(
            AudiencePrivacyPolicyV1.self, from: JSONEncoder().encode(privacyPolicy)
        ), privacyPolicy)
        for invalidText in [
            "", "control\u{0001}",
            String(repeating: "x", count: SnapshotProjectionLimitsV1.maximumTextBytes + 1)
        ] {
            XCTAssertThrowsError(try AudiencePrivacyPolicyV1(
                policyID: "strict-report-policy", policyVersion: 1,
                audience: .customerSafe, prohibitedCanaries: [invalidText]
            )) { XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .invalidValue) }
        }
    }

    func testV9_16R01AmendmentSupersedesWithoutRewritingHistoricalSnapshotBytes() throws {
        let original = try makeFixture(snapshotRevision: 1)
        let originalBytes = try CompletedActivitySnapshotCanonicalCodecV1.encode(original.snapshot)
        let amendment = try makeFixture(
            snapshotRevision: 2,
            snapshotID: "snapshot-b",
            supersedesSnapshotID: original.snapshot.payload.snapshotID,
            supersededSnapshotSHA256: original.snapshot.snapshotSHA256,
            amendmentReason: "Corrected reviewed service status"
        )
        try amendment.snapshot.validateSupersession(of: original.snapshot)
        try CompletedActivitySnapshotChainV1.validate([original.snapshot, amendment.snapshot])
        XCTAssertEqual(try CompletedActivitySnapshotCanonicalCodecV1.encode(original.snapshot), originalBytes)
        let registry = ReportProjectionRegistryV1()
        let regeneratedOriginal = try registry.recover(snapshot: original.snapshot, manifest: original.manifest, reportProfile: original.layout, exportProfile: original.export, storedBundle: nil)
        let regeneratedAgain = try registry.recover(snapshot: original.snapshot, manifest: original.manifest, reportProfile: original.layout, exportProfile: original.export, storedBundle: regeneratedOriginal)
        XCTAssertEqual(regeneratedAgain, regeneratedOriginal)
        let amendedProjection = try registry.recover(
            snapshot: amendment.snapshot,
            manifest: amendment.manifest,
            reportProfile: amendment.layout,
            exportProfile: amendment.export,
            storedBundle: nil
        )
        XCTAssertNotEqual(amendedProjection.snapshotSHA256, regeneratedOriginal.snapshotSHA256)
        XCTAssertEqual(
            try DeterministicOpenJSONRendererV1.reopen(regeneratedOriginal.openJSON.data),
            regeneratedOriginal.semanticProjection
        )
        XCTAssertEqual(
            try DeterministicOpenJSONRendererV1.reopen(amendedProjection.openJSON.data),
            amendedProjection.semanticProjection
        )
        XCTAssertTrue(amendedProjection.semanticProjection.nodes.contains(where: {
            $0.sectionID == "supersession" && $0.label == "Supersedes snapshot"
        }))

        let rewrite = try makeFixture(snapshotRevision: 1, serviceStatus: "Changed in place")
        XCTAssertThrowsError(try original.snapshot.validateImmutableIdentity(against: rewrite.snapshot))
        XCTAssertThrowsError(try original.snapshot.validateSupersession(of: amendment.snapshot))
    }

    private struct Fixture {
        let snapshot: CompletedActivitySnapshotV1
        let manifest: ContractManifestV1
        let layout: ReportLayoutProfileV1
        let export: ExportProfileV1
    }

    private func makeFixture(
        snapshotRevision: Int,
        snapshotID: String = "snapshot-a",
        supersedesSnapshotID: String? = nil,
        supersededSnapshotSHA256: String? = nil,
        amendmentReason: String? = nil,
        serviceStatus: String = "Scheduled",
        duplicateOutputReferenceAcrossCards: Bool = false
    ) throws -> Fixture {
        let formats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
        let sections = try [
            ReportSectionDefinitionV1(sectionID: "identity", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 0),
            ReportSectionDefinitionV1(sectionID: "service", version: 1, required: false, supportedFormats: formats, privacyClass: .audienceSafe, requiresHeading: true, requiresTextAlternative: true, order: 1),
            ReportSectionDefinitionV1(sectionID: "evidence", version: 1, required: false, supportedFormats: formats, privacyClass: .audienceSafe, requiresHeading: true, requiresTextAlternative: true, order: 2),
            ReportSectionDefinitionV1(sectionID: "limitations", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 3),
            ReportSectionDefinitionV1(sectionID: "provenance", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 4),
            ReportSectionDefinitionV1(sectionID: "supersession", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 5),
            ReportSectionDefinitionV1(sectionID: "manifest", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 6),
        ]
        let sectionRegistry = try ReportSectionRegistryV1(registryID: "section-registry-v1", registryVersion: 1, sections: sections)
        let manifest = try ContractManifestV1(
            manifestID: "snapshot-contract-manifest-v1",
            manifestVersion: 1,
            codec: ContractCodecRuleV1(codecVersion: 1),
            compatibility: ContractCompatibilityRuleV1(minimumReaderVersion: 1, maximumReaderVersion: 1, unknownObjectFields: .reject),
            objects: [try ContractObjectDefinitionV1(
                typeID: "completed-snapshot", version: 1, unknownFieldPolicy: .reject,
                fields: [try ContractFieldDefinitionV1(fieldID: "snapshot-id", jsonName: "snapshotID", kind: .string, required: true, maximumUTF8Bytes: 128)]
            )],
            enums: [try ContractEnumDefinitionV1(typeID: "report-audience", version: 1, policy: .closed, knownValues: ["CUSTOMER_SAFE", "INTERNAL"])],
            reportSectionRegistry: sectionRegistry
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let layout = try ReportLayoutProfileV1(
            profileID: "customer-complete-v1", profileRelease: 1, audience: .customerSafe, detail: .complete,
            sectionIDs: sections.map(\.sectionID), mediaLayout: .standardGrid, orientation: .portrait,
            localeIdentifier: "en_US", unitsProfileID: "units-si-v1", displayProfileID: "display-v1", registry: sectionRegistry
        )
        let export = try ExportProfileV1(
            exportProfileID: "portable-v1", exportProfileRelease: 1, formats: formats,
            packaging: .combined, privacyTransformID: "customer-safe-v1", maximumMediaItems: 32,
            maximumArchiveBytes: Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes)
        )
        let binding = try FinalizedReportProfileBindingV1(
            workspaceID: "workspace-a", snapshotID: snapshotID, outputScopeID: "output-scope-a",
            reportProfileID: layout.profileID, reportProfileRelease: layout.profileRelease,
            reportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(layout)),
            exportProfileID: export.exportProfileID, exportProfileRelease: export.exportProfileRelease,
            exportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(export)),
            sectionRegistryID: sectionRegistry.registryID, sectionRegistryVersion: sectionRegistry.registryVersion,
            sectionRegistrySHA256: KernelCanonicalHashV1.sha256(try encoder.encode(sectionRegistry)),
            contractManifestID: manifest.manifestID, contractManifestVersion: manifest.manifestVersion,
            contractManifestSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(manifest)),
            sectionIDs: layout.sectionIDs,
            audience: .customerSafe, detail: .complete, privacyTransformID: "customer-safe-v1", localeIdentifier: "en_US",
            unitsProfileID: "units-si-v1", displayProfileID: "display-v1",
            orientation: .portrait, mediaLayout: .standardGrid,
            rendererVersion: ReportSemanticProjectorV1.rendererVersion, projectionVersion: "report-projection-v1"
        )
        let contentDigest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: String(repeating: "1", count: 64))
        let reference = try ContentReferenceV1(
            workspaceID: "workspace-a", contentID: "content-original", byteLength: 12, mediaType: "image/jpeg",
            digests: ContentDigestSetV1([contentDigest]), byteRole: .derivative, createdAt: "2026-08-27T00:00:00.000Z"
        )
        let outputReference = try OutputScopedContentReferenceV1(outputScopeID: "output-scope-a", ordinal: 0, reference: reference)
        let privacyPolicy = try AudiencePrivacyPolicyV1(
            policyID: "customer-safe-policy-v1",
            policyVersion: 1,
            audience: .customerSafe,
            prohibitedCanaries: [
                "C:\\private\\", "CONTACT-CANARY", "COST-CANARY", "DIAGNOSTIC-CANARY",
                "LOCAL-ID-CANARY", "ORIGINAL-CANARY", "PRIVATE-CANARY", "SECRET-CANARY",
            ].sorted()
        )
        let detailProfile = try EvidenceDetailCardProfileV1(
            profileID: "evidence-detail-customer-v1", profileRelease: 1, audience: .customerSafe,
            outputScopeID: "output-scope-a", privacyTransformID: "customer-safe-v1", privacyTransformVersion: 1,
            markupProfileID: "reviewed-markup-v1", markupProfileVersion: 1,
            localeIdentifier: "en_US", displayProfileID: "display-v1",
            rendererVersion: ReportSemanticProjectorV1.rendererVersion,
            audiencePrivacyPolicy: privacyPolicy,
            includedFieldIDs: ["private_note", "service_request", "service_status"],
            limitationsText: "Evidence detail does not verify capture time, location, or person."
        )
        let fields = try [
            EvidenceDetailFieldV1(fieldID: "private_note", label: "Private note", value: "PRIVATE-CANARY", sensitivity: .privateNote),
            EvidenceDetailFieldV1(fieldID: "service_request", label: "Service request", value: "SR-100", sensitivity: .audienceSafe),
            EvidenceDetailFieldV1(fieldID: "service_status", label: "Service status", value: serviceStatus, sensitivity: .audienceSafe),
        ]
        let card = try EvidenceDetailComposerV1.compose(
            cardID: "evidence-card-a", workspaceID: "workspace-a", evidenceID: "evidence-a",
            fields: fields, profile: detailProfile, markupID: "markup-a",
            annotations: ["Reviewed for customer-safe output"], referenceLabels: ["Customer-safe derivative"],
            outputReferences: [outputReference]
        )
        var evidenceCards = [card]
        if duplicateOutputReferenceAcrossCards {
            evidenceCards.append(try EvidenceDetailComposerV1.compose(
                cardID: "evidence-card-b", workspaceID: "workspace-a", evidenceID: "evidence-b",
                fields: fields, profile: detailProfile, markupID: "markup-b",
                annotations: ["Second reviewed customer-safe output"], referenceLabels: ["Customer-safe derivative"],
                outputReferences: [outputReference]
            ))
        }
        let serviceFacts = try [
            CompletedServiceFactV1(factID: "service-history", kind: .serviceHistory, privacyClass: .audienceSafe, label: "Service history", value: "Request received", effectiveAt: "2026-08-26T23:59:59.000Z"),
            CompletedServiceFactV1(factID: "service-request", kind: .serviceRequest, privacyClass: .audienceSafe, label: "Service request", value: "SR-100", effectiveAt: nil),
            CompletedServiceFactV1(factID: "service-status", kind: .serviceStatus, privacyClass: .audienceSafe, label: "Service status", value: serviceStatus, effectiveAt: "2026-08-27T00:00:00.000Z"),
        ]
        let payload = try CompletedActivitySnapshotPayloadV1(
            workspaceID: "workspace-a", snapshotID: snapshotID, snapshotRevision: snapshotRevision,
            sourceActivityID: "activity-a", sourceRevision: snapshotRevision, reportID: "report-a",
            packageReleaseID: "package-release-v1", generatedAt: "2026-08-27T00:00:00.000Z",
            completedAt: "2026-08-27T00:00:00.000Z", supersedesSnapshotID: supersedesSnapshotID,
            supersededSnapshotSHA256: supersededSnapshotSHA256,
            amendmentReason: amendmentReason, profileBinding: binding, serviceFacts: serviceFacts,
            evidenceCards: evidenceCards.sorted(by: { $0.cardID < $1.cardID }),
            limitations: ["Projection facts are frozen from the completed activity."]
        )
        let snapshot: CompletedActivitySnapshotV1
        if snapshotRevision == 1 {
            snapshot = try CompletedActivitySnapshotV1.freezeOriginal(payload)
        } else {
            guard let priorID = supersedesSnapshotID, let priorSHA = supersededSnapshotSHA256 else {
                throw SnapshotProjectionFailureV1.historyRewrite
            }
            let priorFixture = try makeFixture(snapshotRevision: snapshotRevision - 1, snapshotID: priorID)
            guard priorFixture.snapshot.snapshotSHA256 == priorSHA else { throw SnapshotProjectionFailureV1.historyRewrite }
            snapshot = try CompletedActivitySnapshotV1.freezeAmendment(payload, superseding: priorFixture.snapshot)
        }
        return Fixture(snapshot: snapshot, manifest: manifest, layout: layout, export: export)
    }

    func testV23P03C38ReportProjectionUsesFrozenAccountabilityDisplayFields() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Accountability/V21P03C38PartyAccountabilityCorpusV1.json"
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let projection = try XCTUnwrap(fixture["reportProjection"] as? [String: Any])
        let fields = try XCTUnwrap(projection["frozenDisplayFields"] as? [String])
        XCTAssertTrue(fields.contains("displayNameAtTime"))
        XCTAssertTrue(fields.contains("claimedRole"))
        XCTAssertTrue(fields.contains("purpose"))
        XCTAssertEqual(projection["historyIsImmutable"] as? Bool, true)
        XCTAssertEqual(projection["renamesDoNotRewriteSnapshots"] as? Bool, true)

        let projectorSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(projectorSource.contains("CompletedActivitySnapshotV1"))
        XCTAssertTrue(projectorSource.contains("snapshotSHA256"))
        XCTAssertFalse(projectorSource.contains("ServicePartyReferenceV1.displayName ="))
    }

    private func legacyFixtureData(withExtension fileExtension: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "S3_3ReportSnapshotV1", withExtension: fileExtension, subdirectory: "Fixtures")
                ?? bundle.url(forResource: "S3_3ReportSnapshotV1", withExtension: fileExtension)
        )
        return try Data(contentsOf: url)
    }
}

final class C27V916TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension V9_16SnapshotProjectionTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_16SnapshotProjectionTests {
    func testV23P03C18SemanticReleaseBindingsIgnoreInputOrdering() throws {
        let first = try PackageSemanticReleaseBindingsV1(
            localizationReleaseSHA256: String(repeating: "1", count: 64),
            assetSemanticCatalogSHA256s: [
                String(repeating: "3", count: 64), String(repeating: "2", count: 64)
            ]
        )
        let second = try PackageSemanticReleaseBindingsV1(
            localizationReleaseSHA256: String(repeating: "1", count: 64),
            assetSemanticCatalogSHA256s: [
                String(repeating: "2", count: 64), String(repeating: "3", count: 64)
            ]
        )
        XCTAssertEqual(first, second)
    }

    func testV23P03C19SnapshotProjectionRetainsSeriesAndQualityDigests() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let seriesData = try MeasurementIntegrityCanonicalCodecV1.encode(fixture.series)
        let series = try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementSeriesV1.self, from: seriesData
        )
        XCTAssertEqual(series.seriesSHA256, fixture.series.seriesSHA256)
        XCTAssertEqual(series.samples.map(\.sampleOrdinal), [1, 2])
        XCTAssertEqual(fixture.qualityReview.result, .reviewRequired)
        try fixture.qualityReview.validate()
    }
}

extension V9_16SnapshotProjectionTests {
    func testV23P03C17SnapshotEncoderExcludesDerivedIntegrationPayloads() throws {
        XCTAssertNoThrow(try IntegrationProjectionReportSnapshotExclusionV1.validate())
        let coverage = IntegrationEventJournalCoverageV1()
        XCTAssertNoThrow(try coverage.validate())
        XCTAssertFalse(coverage.reportSourceOfTruth)
    }
}

extension V9_16SnapshotProjectionTests {
    func testV23P03C15SnapshotProjectionIncludesActiveClaimAndLease() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_116)
        let projection = try WorkPacketProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, manifest: fixture.manifest,
            claims: [fixture.claim], leases: [fixture.lease], releases: [], handoffs: [],
            at: fixture.lease.startsAt.addingTimeInterval(1)
        )
        let item = try XCTUnwrap(projection.items.first(where: { $0.item.itemID == fixture.item.itemID }))
        XCTAssertEqual(item.currentClaim, fixture.claim)
        XCTAssertEqual(item.currentLease, fixture.lease)
        XCTAssertNil(item.latestRelease)
        XCTAssertTrue(item.exceptions.isEmpty)

        let active = try CompletedWorkPacketSnapshotV1(
            manifest: fixture.manifest, claims: [fixture.claim], leases: [fixture.lease],
            releases: [], handoffs: [], createdAt: fixture.lease.startsAt.addingTimeInterval(1)
        )
        XCTAssertEqual(active.claims, [fixture.claim])
        XCTAssertEqual(active.leases, [fixture.lease])
        let packetReport = try ReportWorkPacketProjectionV1(
            snapshot: active, sourceSnapshotSHA256: fixture.item.itemSHA256
        )
        try packetReport.validate()
        let packetReportBytes = try JSONEncoder().encode(packetReport)
        XCTAssertEqual(try JSONDecoder().decode(
            ReportWorkPacketProjectionV1.self, from: packetReportBytes
        ), packetReport)
        let packetReportObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: packetReportBytes) as? [String: Any]
        )
        for key in [
            "sourceSnapshotSHA256", "packetID", "manifestSHA256", "itemCount",
            "itemIDs", "itemStateLabels", "preservedResultCount", "collisionCount",
            "historyEventCount", "bindingSHA256"
        ] {
            var missing = packetReportObject
            missing.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(
                ReportWorkPacketProjectionV1.self,
                from: JSONSerialization.data(withJSONObject: missing)
            )) { XCTAssertTrue($0 is DecodingError) }
        }
        var forgedPacketReport = packetReportObject
        forgedPacketReport["bindingSHA256"] = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try JSONDecoder().decode(
            ReportWorkPacketProjectionV1.self,
            from: JSONSerialization.data(withJSONObject: forgedPacketReport)
        )) { XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .digestMismatch) }
        // Exercise the exact tuple boundary used by V9, without fabricating
        // an unrelated eight-layer completed-activity producer fixture.
        func associate(_ packet: CompletedWorkPacketSnapshotV1, _ id: String,
                       _ revision: Int, _ digest: String) throws {
            try CompletedActivitySnapshotPayloadV9.validatePacketAssociation(
                packet, workspaceID: fixture.workspaceID.rawValue.uuidString,
                snapshotID: id, snapshotRevision: revision, snapshotSHA256: digest
            )
        }
        let activeBytes = try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(active)
        try associate(active, fixture.item.itemID, 1, fixture.item.itemSHA256)
        XCTAssertTrue(active.releases.isEmpty)
        XCTAssertTrue(active.handoffs.isEmpty)
        let wrongDirectTuples: [(String, Int, String)] = [
            ("unrelated-snapshot", 1, fixture.item.itemSHA256),
            (fixture.item.itemID, 2, fixture.item.itemSHA256),
            (fixture.item.itemID, 1, String(repeating: "0", count: 64)),
            (fixture.secondItem.itemID, 1, fixture.secondItem.itemSHA256)
        ]
        for (id, revision, digest) in wrongDirectTuples {
            XCTAssertThrowsError(try associate(active, id, revision, digest)) {
                XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .missingBinding)
            }
        }
        // A valid standalone active packet is not automatically associated
        // with every completed artifact from the same workspace.
        try active.validate()
        XCTAssertThrowsError(try CompletedActivitySnapshotPayloadV9.validatePacketAssociation(
            active, workspaceID: fixture.otherWorkspaceID.rawValue.uuidString,
            snapshotID: fixture.item.itemID, snapshotRevision: 1,
            snapshotSHA256: fixture.item.itemSHA256
        )) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .wrongWorkspace)
        }
        let frozen = try CompletedWorkPacketSnapshotV1(
            manifest: fixture.manifest, claims: [fixture.successorClaim, fixture.claim],
            leases: [fixture.successorLease, fixture.lease],
            releases: [fixture.handoffRelease, fixture.completedRelease],
            handoffs: [fixture.handoff], sourceRevision: 2,
            createdAt: fixture.handoff.handedOffAt.addingTimeInterval(1)
        )
        XCTAssertEqual(frozen.claims, [fixture.claim, fixture.successorClaim])
        XCTAssertEqual(frozen.leases, [fixture.lease, fixture.successorLease])
        XCTAssertEqual(frozen.releases, [fixture.completedRelease, fixture.handoffRelease])
        XCTAssertEqual(frozen.handoffs, [fixture.handoff])
        try frozen.validateImmutableHistory(of: active)
        let bytes = try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(frozen)
        let decoded = try JSONDecoder().decode(CompletedWorkPacketSnapshotV1.self, from: bytes)
        XCTAssertEqual(decoded, frozen)
        XCTAssertEqual(try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(decoded), bytes)
        let resultReference = try XCTUnwrap(fixture.result.evidence.first)
        try associate(decoded, resultReference.referenceID, 1, resultReference.sha256)
        for (id, revision, digest) in [
            ("unrelated-result", 1, resultReference.sha256),
            (resultReference.referenceID, 2, resultReference.sha256),
            (resultReference.referenceID, 1, String(repeating: "0", count: 64))
        ] {
            XCTAssertThrowsError(try associate(decoded, id, revision, digest)) {
                XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .missingBinding)
            }
        }
        let wrongKindEvidence = try ReviewEvidenceReferenceV1(
            kind: .externalEvidenceReference, referenceID: resultReference.referenceID,
            revision: resultReference.revision, sha256: resultReference.sha256
        )
        let wrongKindResult = try WorkPacketResultLinkV1(
            resultID: fixture.result.resultID, resultMutationID: fixture.result.resultMutationID,
            itemExpectedRevision: fixture.result.itemExpectedRevision,
            resultRevision: fixture.result.resultRevision, resultSHA256: fixture.result.resultSHA256,
            evidence: [wrongKindEvidence]
        )
        let originalRelease = fixture.handoffRelease
        let wrongKindRelease = try WorkReleaseV1(
            releaseID: originalRelease.releaseID, workspaceID: originalRelease.workspaceID,
            claimID: originalRelease.claimID, leaseID: originalRelease.leaseID,
            item: originalRelease.item, holder: originalRelease.holder, reason: originalRelease.reason,
            resultLinks: [wrongKindResult], releasedAt: originalRelease.releasedAt,
            mutationID: originalRelease.mutationID
        )
        let wrongKindPacket = try CompletedWorkPacketSnapshotV1(
            manifest: fixture.manifest, claims: [fixture.claim], leases: [fixture.lease],
            releases: [wrongKindRelease], handoffs: [], createdAt: frozen.createdAt
        )
        XCTAssertThrowsError(try associate(
            wrongKindPacket, resultReference.referenceID, 1, resultReference.sha256
        )) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .missingBinding)
        }
        XCTAssertEqual(try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(active), activeBytes)
        XCTAssertEqual(try CompletedWorkPacketSnapshotCanonicalCodecV1.encode(decoded), bytes)

        let droppedHistory = try CompletedWorkPacketSnapshotV1(
            manifest: fixture.manifest, claims: [fixture.claim], leases: [fixture.lease],
            releases: [], handoffs: [], sourceRevision: 3,
            createdAt: frozen.createdAt.addingTimeInterval(1)
        )
        XCTAssertThrowsError(try droppedHistory.validateImmutableHistory(of: frozen)) {
            XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .historyRewrite)
        }
        var tampered = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        tampered["snapshotSHA256"] = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try JSONDecoder().decode(
            CompletedWorkPacketSnapshotV1.self,
            from: JSONSerialization.data(withJSONObject: tampered, options: [.sortedKeys])
        ))
    }
}

extension V9_16SnapshotProjectionTests {
    func testV23P03C14SnapshotCandidateStartsAsDraftWithoutAcceptanceClaim() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_016)
        let candidate = try CheckRunnerInspectionReviewCandidateV1(subject: fixture.subject)
        XCTAssertEqual(candidate.initialState, .draft)
        XCTAssertEqual(candidate.subject.subjectRevision, 1)
        XCTAssertEqual(candidate.subject.subjectSHA256, fixture.subject.subjectSHA256)
    }

    func testC20PrivacyTransformClosureBindsOrderedRegionsAndReview() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let closure = PrivacyTransformLifecycleClosureV1(
            policy: fixture.policy, regions: fixture.regions,
            manifest: fixture.manifest, review: fixture.approvedReview
        )
        try closure.validate()
        XCTAssertEqual(closure.regions.map(\.regionID), fixture.manifest.orderedRegions.map(\.regionID))
    }
}

extension V9_16SnapshotProjectionTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_16SnapshotProjectionTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies.count, 2)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.semanticDiffPersistence, "NONPERSISTENT")
        XCTAssertTrue(SurveyDefinitionLimitsV1.token("survey.report.heading"))
    }
}
extension V9_16SnapshotProjectionTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_16SnapshotProjectionTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
final class C31LightingAnchorV916SnapshotProjectionTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension V9_16SnapshotProjectionTests {
    func testV23P03C42SnapshotProjectionRebuildsFromTypedArchetypeState() throws {
        let scenarios = [
            try CompositeAreaSafetyArchetypeV1.scenario(),
            try ControllerZoneDistributionArchetypeV1.scenario()
        ]
        let registry = ReportProjectionRegistryV1()
        var originalSnapshotIDs = Set<String>()

        for (index, scenario) in scenarios.enumerated() {
            XCTAssertTrue(scenario.operations.contains { $0.kind == .rebuildProjection })
            let typedState = ([scenario.archetypeID] + scenario.capabilities.map(\.rawValue))
                .joined(separator: " ")
            let fixture = try makeFixture(
                snapshotRevision: 1,
                snapshotID: "c42-snapshot-\(index + 1)",
                serviceStatus: typedState
            )
            // Each archetype is an independent original, not an amendment
            // of the preceding scenario's completed snapshot.
            XCTAssertTrue(originalSnapshotIDs.insert(fixture.snapshot.payload.snapshotID).inserted)
            XCTAssertEqual(fixture.snapshot.payload.snapshotRevision, 1)
            XCTAssertNil(fixture.snapshot.payload.supersedesSnapshotID)
            XCTAssertNil(fixture.snapshot.payload.supersededSnapshotSHA256)
            XCTAssertNil(fixture.snapshot.payload.amendmentReason)
            XCTAssertThrowsError(try makeFixture(
                snapshotRevision: 2,
                snapshotID: "c42-unbound-amendment-\(index + 1)",
                serviceStatus: typedState
            )) {
                XCTAssertEqual($0 as? SnapshotProjectionFailureV1, .historyRewrite)
            }
            guard case .complete(let projected) = try registry.render(
                snapshot: fixture.snapshot,
                manifest: fixture.manifest,
                reportProfile: fixture.layout,
                exportProfile: fixture.export
            ) else {
                return XCTFail("C42 typed state must produce one complete projection")
            }
            let serviceNode = try XCTUnwrap(projected.semanticProjection.nodes.first {
                $0.sectionID == "service" && $0.label == "Service status"
            })
            XCTAssertEqual(serviceNode.value, typedState)
            XCTAssertEqual(
                try DeterministicOpenJSONRendererV1.reopen(projected.openJSON.data),
                projected.semanticProjection
            )
            XCTAssertEqual(
                try DeterministicPDFRendererV1.reopen(projected.pdf.data),
                projected.semanticProjection
            )
            let rebuilt = try registry.recover(
                snapshot: fixture.snapshot,
                manifest: fixture.manifest,
                reportProfile: fixture.layout,
                exportProfile: fixture.export,
                storedBundle: nil
            )
            XCTAssertEqual(rebuilt, projected)
        }
        XCTAssertEqual(originalSnapshotIDs.count, 2)
    }
}

final class C33TemporalEvidenceAnchorV916SnapshotProjection: XCTestCase {
    func testC33V916SnapshotProjectionCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "snapshot.temporal-evidence-link",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "snapshot.temporal-evidence-link",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

final class C32AssistanceAnchorV916SnapshotProjection: XCTestCase {
    func testC32V916SnapshotProjectionCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .surveyPublicationSnapshot,
            fieldID: "snapshot.exclude-proposal",
            value: .text("accepted snapshot value only")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .surveyPublicationSnapshot,
            fieldID: "snapshot.exclude-proposal",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
final class C46V916SnapshotCompatibilityTests: XCTestCase {
    func testC46SnapshotProjectionExcludesRawContactValue() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "snapshot-projection",
            kind: .phone,
            handoff: .call,
            slot: 46016
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift_Tests: XCTestCase {
    func testC47V916SnapshotProjectionTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_16SnapshotProjectionTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityStateMachineV2.exhaustiveTable.count, ActivityStateV2.allCases.count)
        XCTAssertFalse(ActivityStateMachineV2.permits(from: .finalized, to: .draft))
    }
}

final class C48PortableReviewV916SnapshotTests: XCTestCase {
    func testC48SnapshotProjectionContainsDerivedHistoryOnly() {
        XCTAssertTrue(C48PortableReviewReportSnapshotBoundaryV1.reportSnapshotCarriesDerivedHistoryOnly)
        XCTAssertTrue(C48PortableReviewReportSnapshotBoundaryV1.capabilityProofIsExcluded)
        XCTAssertTrue(C48PortableReviewReportSnapshotBoundaryV1.rawResponseBytesAreExcluded)
    }
}
final class C49WorkResourceSnapshotProjectionBoundaryTests: XCTestCase {
    func testTotalsProjectionKeepsCurrenciesKeyedSeparately() {
        let totals = WorkResourceTotalsProjectionV1(durationMinutes: 0, materialLineCount: 0, directCostByCurrency: ["EUR": 1, "USD": 2])
        XCTAssertEqual(Set(totals.directCostByCurrency.keys), ["EUR", "USD"])
    }
}

private enum C57MyDaySnapshotFixtureV1 {
    static let workspace = WorkspaceID(rawValue: id(1))
    static let evaluatedAt = Date(timeIntervalSince1970: 1_804_000_000)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c5700000-0000-4000-8000-%012x", value))!
    }
    static func reference(_ value: Int, digest: Character) -> MyDayEligibleReferenceV1 {
        .roundSession(workspaceID: workspace, sessionID: id(value), revision: 1,
                      sessionSHA256: String(repeating: digest, count: 64))
    }
    static func values() throws -> (MyDayPlanV1, MyDayReadinessProjectionV1) {
        let actorReference = try LocalActorReferenceV1(
            actorReferenceID: id(2), workspaceID: workspace, displayName: "C57 recorder"
        )
        let actor = try ActorSnapshotV1(
            snapshotID: id(3), workspaceID: workspace, actor: actorReference,
            responsibility: .recordedBy, displayNameAtTime: actorReference.displayName,
            capturedAt: evaluatedAt
        )
        let firstReference = reference(10, digest: "a")
        let secondReference = reference(11, digest: "b")
        let items = [
            try MyDayItemV1(membershipID: id(20), reference: firstReference,
                            manualOrder: 0, estimate: .init(wholeMinutes: 30)),
            try MyDayItemV1(membershipID: id(21), reference: secondReference,
                            manualOrder: 1),
        ]
        let plan = try MyDayPlanV1(
            planID: id(30),
            key: .init(workspaceID: workspace,
                       civilDate: try .init(year: 2026, month: 8, day: 30),
                       ianaTimeZoneIdentifier: "America/New_York"),
            items: items, revision: 1,
            mutationID: try .init(rawValue: id(31)), authoredBy: actor,
            authoredAt: evaluatedAt
        )
        let frontiers = [
            try MyDaySourceFrontierV1(
                membershipID: items[0].membershipID, plannedReference: firstReference,
                currentReference: firstReference, state: .active, readiness: .ready,
                dueAt: evaluatedAt.addingTimeInterval(3_600), evaluatedAt: evaluatedAt
            ),
            try MyDaySourceFrontierV1(
                membershipID: items[1].membershipID, plannedReference: secondReference,
                currentReference: secondReference, state: .completed, readiness: .notReady,
                dueAt: nil, evaluatedAt: evaluatedAt
            ),
        ]
        return (plan, try MyDayReadinessProjectionV1(
            plan: plan, evaluatedAt: evaluatedAt, frontiers: frontiers
        ))
    }
}

final class C57MyDaySnapshotProjectionTests: XCTestCase {
    func testC57ProjectionAndOpenJSONAreDeterministicSourceBoundAndPrivacyBounded() throws {
        let (plan, readiness) = try C57MyDaySnapshotFixtureV1.values()
        let first = try C57MyDayReportProjectionRegistryV1.projection(
            plan: plan, readiness: readiness
        )
        let second = try C57MyDayReportProjectionRegistryV1.projection(
            plan: plan, readiness: readiness
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.items.map(\.manualOrder), [0, 1])
        XCTAssertEqual(first.sourceClosureSHA256, readiness.sourceClosureSHA256)
        XCTAssertNoThrow(try C57MyDaySnapshotValidatorBoundaryV1.validate(
            first, plan: plan, readiness: readiness
        ))

        let bytesA = try C57MyDayOpenJSONRendererV1.render(
            first, plan: plan, readiness: readiness
        )
        let bytesB = try C57MyDayOpenJSONRendererV1.render(
            second, plan: plan, readiness: readiness
        )
        XCTAssertEqual(bytesA, bytesB)
        let reopened = try C57MyDayOpenJSONRendererV1.reopen(bytesA)
        XCTAssertEqual(reopened.itemCount, 2)
        XCTAssertEqual(reopened.estimatedItemCount, 1)
        XCTAssertEqual(reopened.dueItemCount, 1)
        XCTAssertNil(bytesA.range(of: Data("ROUND_SESSION".utf8)))
        XCTAssertNil(bytesA.range(of: Data(C57MyDaySnapshotFixtureV1.id(10).uuidString.utf8)))
        XCTAssertNil(bytesA.range(of: Data(C57MyDaySnapshotFixtureV1.id(10).uuidString.lowercased().utf8)))
        XCTAssertNil(bytesA.range(of: Data("1804003600000".utf8)))
        XCTAssertNil(bytesA.range(of: Data("C57 recorder".utf8)))

        let staleFrontiers = try readiness.frontiers.enumerated().map { index, frontier in
            try MyDaySourceFrontierV1(
                membershipID: frontier.membershipID,
                plannedReference: frontier.plannedReference,
                currentReference: frontier.currentReference,
                state: index == 0 ? .cancelled : frontier.state,
                readiness: index == 0 ? .blocked : frontier.readiness,
                dueAt: frontier.dueAt, evaluatedAt: readiness.evaluatedAt
            )
        }
        let stale = try MyDayReadinessProjectionV1(
            plan: plan, evaluatedAt: readiness.evaluatedAt, frontiers: staleFrontiers
        )
        XCTAssertThrowsError(try C57MyDaySnapshotValidatorBoundaryV1.validate(
            first, plan: plan, readiness: stale
        ))
    }
}

extension V9_16SnapshotProjectionTests {
    func testV23P03C34SnapshotProjectionValidatesSelectedRootAndTarget() throws {
        let workspace = WorkspaceID()
        let today = try NavigationTargetV1(workspaceID: workspace, destination: .today)
        let work = try NavigationTargetV1(workspaceID: workspace, destination: .work)
        let assets = try NavigationTargetV1(workspaceID: workspace, destination: .assets)
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .reports, requestedMode: .read)
        let snapshot = try SceneNavigationSnapshotV1(
            workspaceID: workspace,
            selectedRoot: .reports,
            paths: [
                .init(root: .today, targets: [today]),
                .init(root: .work, targets: [work]),
                .init(root: .assets, targets: [assets]),
                .init(root: .reports, targets: [target]),
            ],
            snapshotID: UUID()
        )
        try snapshot.validate()
        XCTAssertEqual(snapshot.selectedTarget?.destination, .reports)
        XCTAssertEqual(snapshot.selectedTarget?.workspaceID, workspace)
    }
}


extension V9_16SnapshotProjectionTests {
    func testLegacyC33ReportReadbackPreservesCompleteTemporalLinksAndTypedWire() throws {
        let encoder = ReportSnapshotEncoderV1()
        for kind in [TemporalEvidenceMediaKindV1.audio, .video] {
            for preview in [false, true] {
                for anchorCount in [0, 2] {
                    let fixture = try legacyTemporalReportFixture(kind: kind, preview: preview,
                        anchorCount: anchorCount)
                    let snapshot = fixture.snapshot
                    let link = try XCTUnwrap(snapshot.temporalEvidenceLinks?.first)
                    try link.validate(clip: fixture.clip, anchors: fixture.anchors)
                    XCTAssertEqual(link.anchorCount, anchorCount)
                    XCTAssertEqual(link.derivativePreview != nil, preview)
                    XCTAssertNil(link.manualTranscript)
                    let originalBytes = try encoder.encode(snapshot)
                    let reopened = try encoder.decode(originalBytes.data)
                    XCTAssertEqual(reopened, snapshot)
                    XCTAssertEqual(reopened.temporalEvidenceLinks, [link])
                    XCTAssertEqual(try encoder.encode(reopened).data, originalBytes.data)
                    XCTAssertEqual(originalBytes.sha256, publicationDigest(originalBytes.data))
                    let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBytes.data)
                        as? [String: Any])
                    XCTAssertEqual(try legacyTemporalJSON(wire), originalBytes.data,
                        "The hostile-wire helper must preserve this original canonical representation")
                    let legacyLink = try XCTUnwrap((wire["temporalEvidenceLinks"] as? [[String: Any]])?.first)
                    XCTAssertEqual(legacyLink["workspaceID"] as? String,
                        fixture.clip.workspaceID.rawValue.uuidString.lowercased())
                    XCTAssertEqual(legacyLink["anchorCount"] as? Int, anchorCount)

                    // Ordinary Codable retains its original keyed workspace wire,
                    // omits the computed count, and defers domain validation.
                    let typedEncoder = JSONEncoder()
                    typedEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    let typedBytes = try typedEncoder.encode(link)
                    XCTAssertEqual(typedBytes, try legacyTemporalJSON(legacyTemporalExpectedTypedLink(link)))
                    XCTAssertEqual(try JSONDecoder().decode(TemporalEvidenceReportLinkV1.self,
                        from: typedBytes), link)
                    var typedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: typedBytes)
                        as? [String: Any])
                    typedObject["clipID"] = "00000000-0000-0000-0000-000000000000"
                    let invalidTyped = try JSONDecoder().decode(TemporalEvidenceReportLinkV1.self,
                        from: legacyTemporalJSON(typedObject))
                    XCTAssertThrowsError(try invalidTyped.validate()) {
                        XCTAssertEqual($0 as? TemporalEvidenceContractFailureV1, .invalidValue)
                    }

                    // A stored optional transcript remains lossless. This is
                    // typed historical-field compatibility, not a claim that
                    // today's report producer publishes transcript text.
                    if !preview {
                        var storedFields = legacyTemporalExpectedTypedLink(link)
                        storedFields["manualTranscript"] = try XCTUnwrap(fixture.clip.manualTranscript)
                        let storedLink = try JSONDecoder().decode(TemporalEvidenceReportLinkV1.self,
                            from: legacyTemporalJSON(storedFields))
                        try storedLink.validate(clip: fixture.clip, anchors: fixture.anchors)
                        var storedSnapshot = snapshot
                        storedSnapshot.temporalEvidenceLinks = [storedLink]
                        let storedBytes = try encoder.encode(storedSnapshot)
                        XCTAssertEqual(try encoder.decode(storedBytes.data), storedSnapshot)
                        XCTAssertEqual(try encoder.encode(encoder.decode(storedBytes.data)).data, storedBytes.data)
                    }
                }
            }
        }
    }

    func testLegacyC33ReportDecoderRejectsMalformedAndCrossFormatTemporalWires() throws {
        let fixture = try legacyTemporalReportFixture(kind: .video, preview: true, anchorCount: 2)
        let encoder = ReportSnapshotEncoderV1()
        let original = try encoder.encode(fixture.snapshot).data
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let link = try XCTUnwrap((object["temporalEvidenceLinks"] as? [[String: Any]])?.first)
        let originalAnchors = try XCTUnwrap(link["anchorBindings"] as? [[String: Any]])
        let firstAnchor = try XCTUnwrap(originalAnchors.first)
        let originalDerivative = try XCTUnwrap(link["derivativePreview"] as? [String: Any])
        func reject(_ label: String, _ mutate: (inout [String: Any]) -> Void) throws {
            var changed = link
            mutate(&changed)
            var root = object
            root["temporalEvidenceLinks"] = [changed]
            XCTAssertThrowsError(try encoder.decode(legacyTemporalJSON(root)), label) {
                XCTAssertEqual($0 as? ReportSnapshotEncodingErrorV1, .noncanonicalData, label)
            }
        }
        try reject("missing count") { $0.removeValue(forKey: "anchorCount") }
        try reject("false count") { $0["anchorCount"] = 1 }
        try reject("fractional count") { $0["anchorCount"] = 2.5 }
        try reject("null count") { $0["anchorCount"] = NSNull() }
        try reject("typed workspace in legacy file") {
            $0["workspaceID"] = ["rawValue": fixture.clip.workspaceID.rawValue.uuidString]
        }
        try reject("invalid workspace UUID") { $0["workspaceID"] = "not-a-uuid" }
        try reject("noncanonical UUID spelling") { $0["clipID"] = fixture.clip.clipID.uuidString.uppercased() }
        try reject("unknown field") { $0["unexpected"] = true }
        try reject("missing stored field") { $0.removeValue(forKey: "accessibleDescription") }
        try reject("missing canonical null field") { $0.removeValue(forKey: "manualTranscript") }
        try reject("unsupported schema") { $0["schemaVersion"] = 2 }
        try reject("unsupported media") { $0["mediaKind"] = "UNKNOWN" }
        try reject("unsupported projection") { $0["projection"] = "UNKNOWN" }
        try reject("zero revision") { $0["clipRevision"] = 0 }
        try reject("unrepresentable legacy integer") { $0["durationMilliseconds"] = UInt64.max }
        try reject("malformed digest") { $0["clipSHA256"] = String(repeating: "a", count: 63) }
        try reject("source content disagreement") { $0["contentID"] = "different.content" }
        try reject("raw bytes forbidden") { $0["embedsOriginalBytes"] = true }
        try reject("oversized description") { $0["accessibleDescription"] = String(repeating: "x", count: 4_097) }
        try reject("preview and transcript conflict") { $0["manualTranscript"] = "Reviewed transcript" }
        try reject("duplicate anchor identity with matching count") {
            $0["anchorBindings"] = [firstAnchor, firstAnchor]
        }
        try reject("reversed anchor order") { $0["anchorBindings"] = Array(originalAnchors.reversed()) }
        try reject("anchor revision disagreement") {
            var anchors = originalAnchors
            anchors[0]["clipRevision"] = fixture.clip.revision + 1
            $0["anchorBindings"] = anchors
        }
        try reject("anchor digest disagreement") {
            var anchors = originalAnchors
            anchors[0]["clipSHA256"] = String(repeating: "f", count: 64)
            $0["anchorBindings"] = anchors
        }
        try reject("preview source disagreement") {
            var derivative = originalDerivative
            derivative["sourceClipRevision"] = fixture.clip.revision + 1
            $0["derivativePreview"] = derivative
        }
        var dateObject = object
        dateObject["snapshotCreatedAt"] = "2027-09-04T00:00:40.0000Z"
        XCTAssertThrowsError(try encoder.decode(legacyTemporalJSON(dateObject)))
        XCTAssertThrowsError(try encoder.decode(Data(" ".utf8) + original))
        let duplicate = Data("{\"snapshotSchemaVersion\":1,".utf8) + original.dropFirst()
        XCTAssertThrowsError(try encoder.decode(duplicate))

        // No global WorkspaceID widening and no legacy shape in the new wire.
        let stringWorkspace = try JSONSerialization.data(withJSONObject:
            fixture.clip.workspaceID.rawValue.uuidString.lowercased(), options: [.fragmentsAllowed])
        XCTAssertThrowsError(try JSONDecoder().decode(WorkspaceID.self, from: stringWorkspace))
        let typedLink = try JSONEncoder().encode(try XCTUnwrap(fixture.snapshot.temporalEvidenceLinks?.first))
        var typedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: typedLink) as? [String: Any])
        typedObject["workspaceID"] = fixture.clip.workspaceID.rawValue.uuidString.lowercased()
        XCTAssertThrowsError(try JSONDecoder().decode(TemporalEvidenceReportLinkV1.self,
            from: legacyTemporalJSON(typedObject)))
        let basis = try ReportPublicationBasisV1(workspaceID: fixture.clip.workspaceID,
            audience: .customerSafe, projectionVersion: "report-projection-v1", snapshot: fixture.snapshot)
        let basisBytes = try ReportPublicationCanonicalCodecV1.encodeBasis(basis)
        var basisObject = try XCTUnwrap(JSONSerialization.jsonObject(with: basisBytes) as? [String: Any])
        var snapshotObject = try XCTUnwrap(basisObject["snapshot"] as? [String: Any])
        snapshotObject["temporalEvidenceLinks"] = [link]
        basisObject["snapshot"] = snapshotObject
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeBasis(legacyTemporalJSON(basisObject)))
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decodeBasis(basisBytes), basis)
    }

    private func legacyTemporalReportFixture(kind: TemporalEvidenceMediaKindV1, preview: Bool,
        anchorCount: Int) throws -> (snapshot: ReportSnapshotV1, clip: TemporalEvidenceClipV1,
                                    anchors: [TimecodedEvidenceAnchorV1]) {
        let base = try C33TemporalEvidenceTestSupport.clip(slot: 2_200, kind: kind,
            reportProjection: preview ? .typedLinkWithDerivativePreview : .typedLinkOnly)
        let clip: TemporalEvidenceClipV1
        let derivative: TemporalEvidenceDerivativeReferenceV1?
        if preview {
            let value = try C33TemporalEvidenceTestSupport.derivative(clip: base.clip, slot: 2_201)
            derivative = try value.reference
            clip = try base.clip.successor(clipID: C33TemporalEvidenceTestSupport.id(2_202),
                profile: base.profile, derivativeReferences: [try value.reference],
                mutationID: C33TemporalEvidenceTestSupport.mutation(2_203))
        } else {
            clip = base.clip
            derivative = nil
        }
        let anchors = try (0..<anchorCount).map {
            try C33TemporalEvidenceTestSupport.anchor(clip: clip, slot: 2_210 + $0)
        }
        var snapshot = try C33TemporalEvidenceTestSupport.reportSnapshot(clip: clip, anchors: anchors,
            reportID: C33TemporalEvidenceTestSupport.id(2_220), slot: 2_230, includesAssurance: false)
        if let derivative {
            snapshot.temporalEvidenceLinks = [try TemporalEvidenceReportLinkV1(clip: clip,
                anchors: anchors, currentDerivative: derivative, profile: base.profile)]
        }
        return (snapshot, clip, anchors)
    }

    private func legacyTemporalJSON(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func legacyTemporalExpectedTypedLink(_ value: TemporalEvidenceReportLinkV1) -> [String: Any] {
        var result: [String: Any] = [
            "schemaVersion": value.schemaVersion,
            "workspaceID": ["rawValue": value.workspaceID.rawValue.uuidString],
            "clipID": value.clipID.uuidString, "clipRevision": value.clipRevision,
            "clipSHA256": value.clipSHA256, "contentID": value.contentID,
            "mediaKind": value.mediaKind.rawValue, "durationMilliseconds": value.durationMilliseconds,
            "anchorBindings": value.anchorBindings.map { anchor -> [String: Any] in [
                "anchorID": anchor.anchorID.uuidString, "revision": anchor.revision,
                "anchorSHA256": anchor.anchorSHA256, "clipID": anchor.clipID.uuidString,
                "clipRevision": anchor.clipRevision, "clipSHA256": anchor.clipSHA256,
                "sourceContentID": anchor.sourceContentID, "sourceSHA256": anchor.sourceSHA256,
            ] },
            "accessibleDescription": value.accessibleDescription,
            "projection": value.projection.rawValue, "embedsOriginalBytes": value.embedsOriginalBytes,
        ]
        if let transcript = value.manualTranscript { result["manualTranscript"] = transcript }
        if let preview = value.derivativePreview {
            result["derivativePreview"] = [
                "derivativeID": preview.derivativeID.uuidString, "revision": preview.revision,
                "derivativeSHA256": preview.derivativeSHA256, "kind": preview.kind.rawValue,
                "sourceClipID": preview.sourceClipID.uuidString, "sourceClipRevision": preview.sourceClipRevision,
                "sourceClipSHA256": preview.sourceClipSHA256, "projection": preview.projection.rawValue,
            ] as [String: Any]
        }
        return result
    }

    func testReportPublicationBindsCompleteTemporalBasisAndSeparateOuterIdentity() throws {
        let snapshot = try publicationSnapshot(anchorSlots: [991, 992])
        let workspace = C33TemporalEvidenceTestSupport.workspace()
        let basis = try ReportPublicationBasisV1(workspaceID: workspace, audience: .customerSafe,
            projectionVersion: "report-projection-v1", snapshot: snapshot)
        // Independent fixed-object oracle for the explicitly NEW full typed
        // snapshot wire, including every stored optional projection.
        let expectedBasis = try publicationExpectedBytes(publicationExpectedBasis(basis))
        let expectedDigest = publicationDigest(expectedBasis)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.encodeBasis(basis), expectedBasis)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decodeBasis(expectedBasis), basis)
        let plain = try ReportPublicationV1(basis: basis)
        XCTAssertEqual(plain.basisSHA256, expectedDigest)
        let assurance = try publicationAssurance(basis: basis, digest: expectedDigest)
        let publication = try ReportPublicationV1(basis: basis, assurance: assurance)
        let encoded = try ReportPublicationCanonicalCodecV1.encode(publication)
        let expectedOuter = try publicationExpectedBytes(publicationExpectedWire(publication))
        XCTAssertEqual(encoded.data, expectedOuter)
        XCTAssertEqual(encoded.sha256, publicationDigest(expectedOuter))
        XCTAssertNotEqual(encoded.sha256, expectedDigest)
        XCTAssertNotEqual(encoded, try ReportPublicationCanonicalCodecV1.encode(plain))
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decode(encoded.data), publication)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decode(
            ReportPublicationCanonicalCodecV1.encode(plain).data), plain)
        XCTAssertEqual(publication.basis.snapshot, snapshot)

        let otherSnapshot = try publicationSnapshot(anchorSlots: [992, 993])
        let otherBasis = try ReportPublicationBasisV1(workspaceID: workspace, audience: .customerSafe,
            projectionVersion: basis.projectionVersion, snapshot: otherSnapshot)
        XCTAssertEqual(snapshot.temporalEvidenceLinks?.first?.anchorCount,
                       otherSnapshot.temporalEvidenceLinks?.first?.anchorCount)
        XCTAssertNotEqual(try ReportPublicationV1(basis: otherBasis).basisSHA256, expectedDigest)
        XCTAssertThrowsError(try ReportPublicationV1(basis: otherBasis, assurance: assurance))
        let otherPlain = try ReportPublicationV1(basis: otherBasis)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decode(
            ReportPublicationCanonicalCodecV1.encode(otherPlain).data).basis.snapshot, otherSnapshot)

        // Every selected fact is part of the source, not just its temporal link.
        let sourceChanges: [(String, Any)] = [
            ("note", "Changed reviewed note"),
            ("snapshotCreatedAt", snapshot.snapshotCreatedAt.addingTimeInterval(60).timeIntervalSinceReferenceDate),
            ("sourceRecordID", "c3300000-0000-4000-8000-000000000fff"),
        ]
        for (key, changed) in sourceChanges {
            // Construct the complete typed source in its own representation.
            // The legacy report file's distinct wire format is not this new
            // source's representation or mutation authority.
            var object = try XCTUnwrap(publicationSnapshotObject(snapshot) as? [String: Any])
            object[key] = changed
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
            let changedSnapshot = try decoder.decode(ReportSnapshotV1.self,
                from: JSONSerialization.data(withJSONObject: object))
            let changedBasis = try ReportPublicationBasisV1(workspaceID: workspace,
                audience: basis.audience, projectionVersion: basis.projectionVersion, snapshot: changedSnapshot)
            XCTAssertThrowsError(try ReportPublicationV1(basis: changedBasis, assurance: assurance), key)
        }
        for changedBasis in [
            try ReportPublicationBasisV1(workspaceID: workspace, audience: .internalUse,
                projectionVersion: basis.projectionVersion, snapshot: snapshot),
            try ReportPublicationBasisV1(workspaceID: workspace, audience: basis.audience,
                projectionVersion: "report-projection-v2", snapshot: snapshot),
        ] {
            XCTAssertThrowsError(try ReportPublicationV1(basis: changedBasis, assurance: assurance))
        }
    }

    func testReportPublicationRejectsUnboundNestedAndNoncanonicalInputs() throws {
        let snapshot = try publicationSnapshot(anchorSlots: [991, 992])
        let workspace = C33TemporalEvidenceTestSupport.workspace()
        let basis = try ReportPublicationBasisV1(workspaceID: workspace, audience: .customerSafe,
            projectionVersion: "report-projection-v1", snapshot: snapshot)
        let plain = try ReportPublicationV1(basis: basis)
        let assurance = try publicationAssurance(basis: basis, digest: plain.basisSHA256)
        var embedded = snapshot
        embedded.assurance = assurance
        XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: workspace,
            audience: .customerSafe, projectionVersion: basis.projectionVersion, snapshot: embedded))
        var duplicate = snapshot
        duplicate.temporalEvidenceLinks = (snapshot.temporalEvidenceLinks ?? []) + (snapshot.temporalEvidenceLinks ?? [])
        XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: workspace,
            audience: .customerSafe, projectionVersion: basis.projectionVersion, snapshot: duplicate))
        XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: C33TemporalEvidenceTestSupport.workspace(9),
            audience: .customerSafe, projectionVersion: basis.projectionVersion, snapshot: snapshot))
        XCTAssertThrowsError(try ReportPublicationV1(basis: basis, assurance:
            publicationAssurance(basis: basis, digest: plain.basisSHA256,
                workspace: C33TemporalEvidenceTestSupport.workspace(9))))
        XCTAssertThrowsError(try ReportPublicationV1(basis: basis, assurance:
            publicationAssurance(basis: basis, digest: plain.basisSHA256, audience: .internalReview)))
        XCTAssertThrowsError(try ReportPublicationV1(basis: basis, assurance:
            publicationAssurance(basis: basis, digest: plain.basisSHA256, projectionVersion: "other-version")))

        let valid = try ReportPublicationCanonicalCodecV1.encode(plain).data
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        let outerChanges: [(String, Any)] = [
            ("basisSHA256", String(repeating: "0", count: 64)),
            ("reportPublicationSchemaVersion", 2),
            ("reportPublicationSchemaVersion", NSNull()),
            ("schemaVersion", 1), ("snapshotSchemaVersion", 1),
            ("unknown", true), ("assurance", NSNull()),
        ]
        for (key, value) in outerChanges {
            var changed = root; changed[key] = value
            XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(
                JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes])), key)
        }
        for key in ["unknown", "reportPublicationSchemaVersion"] {
            var changed = root
            var nested = try XCTUnwrap(changed["basis"] as? [String: Any])
            nested[key] = 1; changed["basis"] = nested
            XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(
                JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes])))
        }
        for invalidTime in ["not-a-time", "2027-09-04T00:00:40Z"] {
            var changed = root
            var nested = try XCTUnwrap(changed["basis"] as? [String: Any])
            var nestedSnapshot = try XCTUnwrap(nested["snapshot"] as? [String: Any])
            nestedSnapshot["snapshotCreatedAt"] = invalidTime
            nested["snapshot"] = nestedSnapshot; changed["basis"] = nested
            XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(
                JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes])))
        }
        let text = try XCTUnwrap(String(data: valid, encoding: .utf8))
        let duplicateKey = "{\"reportPublicationSchemaVersion\":1," + text.dropFirst()
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(Data(duplicateKey.utf8)))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(Data((text + "\n").utf8)))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(Data()))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(
            Data(repeating: 0x20, count: SnapshotProjectionLimitsV1.maximumProjectionBytes + 1)))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeBasis(valid))
    }

    func testReportPublicationLeavesLegacyGoldenBytesAndAdmissionUnchanged() throws {
        let bundle = Bundle(for: V9_16SnapshotProjectionTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "S3_3ReportSnapshotV1", withExtension: "json",
            subdirectory: "Fixtures") ?? bundle.url(forResource: "S3_3ReportSnapshotV1", withExtension: "json"))
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(publicationDigest(bytes), "8b81589641276df9ee94dba99ac390ce8679fcc2932825e79e4178eb91377b3e")
        let encoder = ReportSnapshotEncoderV1()
        let snapshot = try encoder.decode(bytes)
        XCTAssertEqual(try encoder.encode(snapshot).data, bytes)
        XCTAssertNil(try encoder.completedActivityV2SnapshotIfPresent(bytes, declaredSchemaVersion: 1))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(bytes))
        let basis = try ReportPublicationBasisV1(workspaceID: C33TemporalEvidenceTestSupport.workspace(),
            audience: .customerSafe, projectionVersion: "report-projection-v1", snapshot: snapshot)
        let publication = try ReportPublicationV1(basis: basis)
        let published = try ReportPublicationCanonicalCodecV1.encode(publication)
        XCTAssertEqual(try encoder.encode(publication.basis.snapshot).data, bytes)
        XCTAssertThrowsError(try encoder.decode(published.data))
        XCTAssertThrowsError(try encoder.completedActivityV2SnapshotIfPresent(
            published.data, declaredSchemaVersion: 1))

        // This schema-two fixture is specified independently as the existing
        // golden document plus the complete C07 observation/time fields. No new
        // publication codec supplies its expected legacy bytes.
        var schemaTwoObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        schemaTwoObject["snapshotSchemaVersion"] = 2
        schemaTwoObject["observationBasis"] = [
            "version": 1, "kind": "DIRECTLY_OBSERVED", "method": ["key": "visual"],
            "source": ["kind": "OBSERVER", "reference": NSNull()], "limitations": [],
        ] as [String: Any]
        schemaTwoObject["temporalContext"] = [
            "version": 1, "occurredAtUTC": "2026-01-14T20:02:03.000Z",
            "recordedAtUTC": "2026-01-14T20:02:06.000Z", "localDate": "2026-01-14",
            "localTime": "15:02:03", "utcOffsetSeconds": -18_000,
            "ianaTimeZoneIdentifier": "America/New_York", "localTimeDisposition": "UNAMBIGUOUS",
        ] as [String: Any]
        let schemaTwoBytes = try JSONSerialization.data(withJSONObject: schemaTwoObject,
            options: [.sortedKeys, .withoutEscapingSlashes])
        let schemaTwo = try encoder.decode(schemaTwoBytes)
        XCTAssertEqual(try encoder.encode(schemaTwo).data, schemaTwoBytes)
        XCTAssertEqual(try encoder.encode(schemaTwo).sha256, publicationDigest(schemaTwoBytes))
        XCTAssertNil(try encoder.completedActivityV2SnapshotIfPresent(schemaTwoBytes, declaredSchemaVersion: 2))
        let schemaTwoPublication = try ReportPublicationV1(basis: ReportPublicationBasisV1(
            workspaceID: basis.workspaceID, audience: basis.audience,
            projectionVersion: basis.projectionVersion, snapshot: schemaTwo))
        let schemaTwoOuter = try ReportPublicationCanonicalCodecV1.encode(schemaTwoPublication)
        XCTAssertEqual(try encoder.encode(ReportPublicationCanonicalCodecV1.decode(
            schemaTwoOuter.data).basis.snapshot).data, schemaTwoBytes)
        XCTAssertThrowsError(try encoder.decode(schemaTwoOuter.data))
        XCTAssertThrowsError(try encoder.completedActivityV2SnapshotIfPresent(
            schemaTwoOuter.data, declaredSchemaVersion: 2))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(schemaTwoBytes))

        // New full typed dates preserve fractional milliseconds even though
        // the old report timestamp representation cannot carry that precision.
        var submillisecond = schemaTwo
        let time = try XCTUnwrap(schemaTwo.temporalContext)
        submillisecond.temporalContext = try TemporalContextV1(
            occurredAtUTC: time.occurredAtUTC,
            recordedAtUTC: time.recordedAtUTC.addingTimeInterval(1.0 / 1_024),
            localDate: time.localDate, localTime: time.localTime,
            utcOffsetSeconds: time.utcOffsetSeconds, ianaTimeZoneIdentifier: time.ianaTimeZoneIdentifier,
            localTimeDisposition: time.localTimeDisposition)
        let lossyBytes = try encoder.encode(submillisecond).data
        XCTAssertNotEqual(try encoder.decode(lossyBytes), submillisecond)
        let precise = try ReportPublicationV1(basis: ReportPublicationBasisV1(workspaceID: basis.workspaceID,
            audience: basis.audience, projectionVersion: basis.projectionVersion, snapshot: submillisecond))
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decode(
            ReportPublicationCanonicalCodecV1.encode(precise).data).basis.snapshot, submillisecond)
        XCTAssertNotEqual(precise.basisSHA256, schemaTwoPublication.basisSHA256)

    }

    func testReportPublicationPreservesExactSourceAndAssuranceDatePrecision() throws {
        let original = try publicationSnapshot(anchorSlots: [991, 992])
        let workspace = C33TemporalEvidenceTestSupport.workspace()
        let base: Double = 812_000_000
        let probes = [base, base.nextUp, base + 0.00025, base + 1.0 / 1_024,
                      Date().timeIntervalSinceReferenceDate]
        let snapshotDecoder = JSONDecoder()
        snapshotDecoder.dateDecodingStrategy = .deferredToDate
        var sourceDigests = Set<String>()
        for seconds in probes {
            var object = try XCTUnwrap(publicationSnapshotObject(original) as? [String: Any])
            object["snapshotCreatedAt"] = seconds
            let precise = try snapshotDecoder.decode(ReportSnapshotV1.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(precise.snapshotCreatedAt.timeIntervalSinceReferenceDate, seconds)
            let basis = try ReportPublicationBasisV1(workspaceID: workspace, audience: .customerSafe,
                projectionVersion: "report-projection-v1", snapshot: precise)
            let publication = try ReportPublicationV1(basis: basis)
            XCTAssertTrue(sourceDigests.insert(publication.basisSHA256).inserted)
            let decoded = try ReportPublicationCanonicalCodecV1.decode(
                ReportPublicationCanonicalCodecV1.encode(publication).data)
            XCTAssertEqual(decoded, publication)
            XCTAssertEqual(decoded.basis.snapshot.snapshotCreatedAt.timeIntervalSinceReferenceDate, seconds)
        }
        // Demonstrate the ordinary epoch-conversion edge deterministically;
        // the new wire does not perform this lossy conversion.
        let unixMilliseconds = (base.nextUp + 978_307_200) * 1_000
        XCTAssertNotEqual(unixMilliseconds / 1_000 - 978_307_200, base.nextUp)
        let basis = try ReportPublicationBasisV1(workspaceID: workspace, audience: .customerSafe,
            projectionVersion: "report-projection-v1", snapshot: original)
        let plain = try ReportPublicationV1(basis: basis)
        var outerDigests = Set<String>()
        for seconds in probes {
            let assurance = try publicationAssurance(basis: basis, digest: plain.basisSHA256,
                createdAt: Date(timeIntervalSinceReferenceDate: seconds))
            let publication = try ReportPublicationV1(basis: basis, assurance: assurance)
            let encoded = try ReportPublicationCanonicalCodecV1.encode(publication)
            XCTAssertTrue(outerDigests.insert(encoded.sha256).inserted)
            let decoded = try ReportPublicationCanonicalCodecV1.decode(encoded.data)
            XCTAssertEqual(decoded.assurance, assurance)
            XCTAssertEqual(decoded.assurance?.preview.createdAt.timeIntervalSinceReferenceDate, seconds)
            XCTAssertEqual(decoded.basisSHA256, plain.basisSHA256)
        }
        // Build hostile typed values without normalizing their dates. The new
        // encoder's default finite-number rule must reject all three cases.
        snapshotDecoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NAN")
        for nonfinite in ["INF", "-INF", "NAN"] {
            var object = try XCTUnwrap(publicationSnapshotObject(original) as? [String: Any])
            object["snapshotCreatedAt"] = nonfinite
            let invalid = try snapshotDecoder.decode(ReportSnapshotV1.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertFalse(invalid.snapshotCreatedAt.timeIntervalSinceReferenceDate.isFinite)
            XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: workspace,
                audience: .customerSafe, projectionVersion: basis.projectionVersion, snapshot: invalid))
        }
    }

    func testReportPublicationPreservesAllLegacyOmittedTypedFamilies() throws {
        // Pure domain fixture: this does not claim a persisted report or writer
        // acceptance. It carries the real family constructors' complete values.
        let lighting = try CanonicalLightingFixtureV1.makeFixture(slot: 916)
        let workspace = lighting.system.workspaceID
        let original = try publicationSnapshot(anchorSlots: [991, 992], workspace: workspace)
        let contents = try C23FieldReferenceTestSupport.contents(workspaceID: workspace)
        let release = try C23FieldReferenceTestSupport.release(workspaceID: workspace, contents: contents)
        let binding = try C23FieldReferenceTestSupport.binding(workspaceID: workspace,
            release: release, subjectID: original.packetID, subjectState: .finalized)
        let readiness = try FieldReferenceOfflineReadinessV1(release: release, binding: binding,
            inputs: .init(references: contents.map(\.reference), locators: contents.map(\.locator),
                evaluatedAt: binding.boundAt, policy: .exactLocalContentV1, protectedDataAvailable: true))
        var complete = try original.withC23FieldReferenceProjection(binding: binding,
            release: release, readiness: readiness, subjectRevision: binding.subjectRevision)
        complete.lightingDayInventory = try C17LightingDayInventoryFrozenSnapshotV1(
            workflow: lighting.day, admission: lighting.dayAdmission, poseSnapshots: [],
            capturedAt: lighting.day.recordedAt)
        complete.lightingNightWorkflow = try C18LightingNightFrozenSnapshotV1(
            workflow: lighting.night, capturedAt: lighting.night.recordedAt)
        complete.practiceWorkspace = try PracticeWorkspaceReportProjectionV1(
            workspaceID: workspace, provenance: nil)
        let basis = try ReportPublicationBasisV1(workspaceID: workspace, audience: .customerSafe,
            projectionVersion: "report-projection-v1", snapshot: complete)
        let publication = try ReportPublicationV1(basis: basis)
        let encoded = try ReportPublicationCanonicalCodecV1.encode(publication)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decode(encoded.data).basis.snapshot, complete)
        let nested = try XCTUnwrap(publicationSnapshotObject(complete) as? [String: Any])
        for key in ["fieldReferences", "lightingDayInventory", "lightingNightWorkflow", "practiceWorkspace"] {
            XCTAssertNotNil(nested[key], key)
        }
        let expectedBasis = try JSONSerialization.data(withJSONObject: [
            "reportBasisSchemaVersion": 1, "workspaceID": workspace.rawValue.uuidString.lowercased(),
            "audience": ReportAudienceV1.customerSafe.rawValue,
            "projectionVersion": basis.projectionVersion, "snapshot": nested,
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertEqual(publication.basisSHA256, publicationDigest(expectedBasis))
        let assurance = try publicationAssurance(basis: basis, digest: publication.basisSHA256)
        let reviewed = try ReportPublicationV1(basis: basis, assurance: assurance)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decode(
            ReportPublicationCanonicalCodecV1.encode(reviewed).data), reviewed)

        // Each omitted family separately contributes identity; nil and an
        // explicitly empty collection remain different complete source values.
        var noReferences = complete; noReferences.fieldReferences = nil
        var emptyReferences = complete; emptyReferences.fieldReferences = []
        var noDay = complete; noDay.lightingDayInventory = nil
        var noNight = complete; noNight.lightingNightWorkflow = nil
        var noPractice = complete; noPractice.practiceWorkspace = nil
        var digests = Set([publication.basisSHA256])
        for value in [noReferences, emptyReferences, noDay, noNight, noPractice] {
            XCTAssertEqual(try ReportSnapshotEncoderV1().encode(value),
                           try ReportSnapshotEncoderV1().encode(complete))
            let otherBasis = try ReportPublicationBasisV1(workspaceID: workspace, audience: basis.audience,
                projectionVersion: basis.projectionVersion, snapshot: value)
            let other = try ReportPublicationV1(basis: otherBasis)
            XCTAssertTrue(digests.insert(other.basisSHA256).inserted)
            XCTAssertThrowsError(try ReportPublicationV1(basis: otherBasis, assurance: assurance))
            XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decode(
                ReportPublicationCanonicalCodecV1.encode(other).data).basis.snapshot, value)
        }
        // These formerly omitted projections must also retain their own typed
        // predicates, independently of the containing basis digest.
        let snapshotDecoder = JSONDecoder()
        snapshotDecoder.dateDecodingStrategy = .deferredToDate
        for key in ["fieldReferences", "lightingDayInventory", "lightingNightWorkflow", "practiceWorkspace"] {
            var corrupted = nested
            if key == "fieldReferences" {
                var references = try XCTUnwrap(corrupted[key] as? [[String: Any]])
                references[0]["projectionSHA256"] = String(repeating: "0", count: 64)
                corrupted[key] = references
            } else {
                var projection = try XCTUnwrap(corrupted[key] as? [String: Any])
                projection[key == "practiceWorkspace" ? "watermark" : "snapshotSHA256"] =
                    key == "practiceWorkspace" ? "Invalid real-workspace watermark" : String(repeating: "0", count: 64)
                corrupted[key] = projection
            }
            let invalid = try snapshotDecoder.decode(ReportSnapshotV1.self,
                from: JSONSerialization.data(withJSONObject: corrupted))
            XCTAssertNoThrow(try ReportSnapshotEncoderV1().encode(invalid))
            XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: workspace, audience: basis.audience,
                projectionVersion: basis.projectionVersion, snapshot: invalid), key)
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded.data) as? [String: Any])
        for key in ["fieldReferences", "lightingDayInventory", "lightingNightWorkflow", "practiceWorkspace"] {
            var tampered = root
            var tamperedBasis = try XCTUnwrap(tampered["basis"] as? [String: Any])
            var tamperedSnapshot = try XCTUnwrap(tamperedBasis["snapshot"] as? [String: Any])
            tamperedSnapshot.removeValue(forKey: key)
            tamperedBasis["snapshot"] = tamperedSnapshot; tampered["basis"] = tamperedBasis
            XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(
                JSONSerialization.data(withJSONObject: tampered, options: [.sortedKeys, .withoutEscapingSlashes])), key)
        }
    }

    func testReportReviewedPublicationPreservesSchemaThreeSourceAndCompleteSchemaFourView() throws {
        let fixture = try publicationReviewFixture()
        let originalBytes = try ReportPublicationCanonicalCodecV1.encode(fixture.original)
        let source = try ReportReviewedSourceV1(original: fixture.original,
            reportSubject: fixture.key, history: fixture.history)
        let sourceBytes = try ReportPublicationCanonicalCodecV1.encodeReviewedSource(source)
        let publication = try ReportReviewPublicationV1(source: source)
        let encoded = try ReportPublicationCanonicalCodecV1.encode(publication)
        // Assemble an independent fixed typed wire from original values.
        // Parsing exact Date numbers through Any/NSNumber and reserializing
        // would introduce a different numeric spelling operation.
        let expectedSourceValue = PublicationExpectedReviewedSource(
            original: try publicationExpectedWire(fixture.original),
            reportSubject: .init(workspaceID: fixture.key.workspaceID.rawValue.uuidString.lowercased(),
                reportID: fixture.key.subjectID.uuidString.lowercased(),
                fixedCorrectionChainRevision: fixture.key.subjectRevision),
            history: fixture.history)
        let expectedSource = try publicationExpectedBytes(expectedSourceValue)
        XCTAssertEqual(sourceBytes, expectedSource)
        let expectedOuter = try publicationExpectedBytes(
            PublicationExpectedReviewedOutput(source: expectedSourceValue))
        XCTAssertEqual(encoded.data, expectedOuter)
        XCTAssertEqual(encoded.sha256, publicationDigest(expectedOuter))
        XCTAssertNotEqual(encoded.sha256, originalBytes.sha256)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decodeReviewedSource(sourceBytes), source)
        let reopened = try ReportPublicationCanonicalCodecV1.decodeReview(encoded.data)
        XCTAssertEqual(reopened, publication)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.encode(reopened.source.original), originalBytes)
        XCTAssertEqual(reopened.source.history, fixture.history)
        XCTAssertFalse(fixture.history.reviewTransitions.isEmpty)
        XCTAssertFalse(fixture.history.reviewDispositions.isEmpty)
        XCTAssertEqual(fixture.original.basis.snapshot.snapshotSchemaVersion, 3)
        XCTAssertFalse(try XCTUnwrap(fixture.original.basis.snapshot.authorityCriterion).aggregate.sourceReleases.isEmpty)
        XCTAssertEqual(fixture.key.subjectRevision, 2)
        XCTAssertNotEqual(fixture.key.subjectRevision, UInt64(fixture.history.reviewTransitions.count))
        XCTAssertEqual(fixture.history.sourceSnapshotSHA256, originalBytes.sha256)
        XCTAssertEqual(fixture.original.assurance?.snapshotSHA256, fixture.original.basisSHA256)
        XCTAssertThrowsError(try fixture.original.assurance?.validate(
            expectedSnapshotSHA256: publicationDigest(sourceBytes)))

        let view = try reopened.source.reportSnapshot()
        // Independent expected full-value view: every source key survives,
        // exactly the three declared view fields are added/replaced.
        var expectedView = try XCTUnwrap(publicationSnapshotObject(fixture.original.basis.snapshot) as? [String: Any])
        expectedView["snapshotSchemaVersion"] = 4
        expectedView["assurance"] = try publicationAssuranceObject(XCTUnwrap(fixture.original.assurance))
        expectedView["inspectionReviewHistory"] = try publicationTypedObject(fixture.history)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
        let expected = try decoder.decode(ReportSnapshotV1.self,
            from: JSONSerialization.data(withJSONObject: expectedView))
        XCTAssertEqual(view, expected)
        XCTAssertEqual(view.fieldReferences, fixture.original.basis.snapshot.fieldReferences)
        XCTAssertNotNil(view.lightingDayInventory)
        XCTAssertNotNil(view.lightingNightWorkflow)
        XCTAssertNotNil(view.practiceWorkspace)
        XCTAssertEqual(view.temporalEvidenceLinks, fixture.original.basis.snapshot.temporalEvidenceLinks)
        XCTAssertNoThrow(try ReportSnapshotEncoderV1().encode(view))
        XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: fixture.key.workspaceID,
            audience: .customerSafe, projectionVersion: fixture.original.basis.projectionVersion, snapshot: view))
        XCTAssertThrowsError(try ReportSnapshotEncoderV1().decode(encoded.data))
        XCTAssertThrowsError(try ReportSnapshotEncoderV1().completedActivityV2SnapshotIfPresent(
            encoded.data, declaredSchemaVersion: 4))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(encoded.data))
    }

    func testReportReviewedSourceRejectsWrongReportTupleAndHistoricalComponents() throws {
        let fixture = try publicationReviewFixture()
        let original = fixture.original
        let digest = try ReportPublicationCanonicalCodecV1.encode(original).sha256
        let workspace = fixture.key.workspaceID
        for key in [
            try CompletedWorkSubjectKeyV1(workspaceID: workspace,
                subjectID: C33TemporalEvidenceTestSupport.id(999), subjectRevision: 2),
            try CompletedWorkSubjectKeyV1(workspaceID: workspace,
                subjectID: fixture.key.subjectID, subjectRevision: 3),
            try CompletedWorkSubjectKeyV1(workspaceID: C33TemporalEvidenceTestSupport.workspace(),
                subjectID: fixture.key.subjectID, subjectRevision: 2),
            try CompletedWorkSubjectKeyV1(workspaceID: workspace, family: .typedCompletedActivityReserved,
                subjectID: fixture.key.subjectID, subjectRevision: 2),
        ] {
            XCTAssertThrowsError(try ReportReviewedSourceV1(original: original,
                reportSubject: key, history: fixture.history))
        }
        let correctSubject = try InspectionReviewSubjectReferenceV1(workspaceID: workspace,
            kind: .reportSnapshot, subjectID: fixture.key.subjectID.uuidString.lowercased(),
            subjectRevision: 2, subjectSHA256: digest)
        let wrongSubjects = [
            try InspectionReviewSubjectReferenceV1(workspaceID: workspace, kind: .reportSnapshot,
                subjectID: C33TemporalEvidenceTestSupport.id(999).uuidString.lowercased(),
                subjectRevision: 2, subjectSHA256: digest),
            try InspectionReviewSubjectReferenceV1(workspaceID: workspace, kind: .reportSnapshot,
                subjectID: correctSubject.subjectID, subjectRevision: 3, subjectSHA256: digest),
            try InspectionReviewSubjectReferenceV1(workspaceID: workspace, kind: .reportSnapshot,
                subjectID: correctSubject.subjectID, subjectRevision: 2, subjectSHA256: String(repeating: "0", count: 64)),
            try InspectionReviewSubjectReferenceV1(workspaceID: workspace, kind: .completedActivitySnapshot,
                subjectID: correctSubject.subjectID, subjectRevision: 2, subjectSHA256: digest),
        ]
        for wrong in wrongSubjects {
            for wrongDispositionOnly in [false, true] {
                let history = try publicationReviewHistory(original: original, key: fixture.key,
                    transitionSubject: wrongDispositionOnly ? correctSubject : wrong,
                    dispositionSubject: wrongDispositionOnly ? wrong : correctSubject)
                try history.validate() // The old generic history is insufficient for REPORT tuples.
                XCTAssertThrowsError(try ReportReviewedSourceV1(original: original,
                    reportSubject: fixture.key, history: history))
            }
        }
        let priorBinding = fixture.history.binding
        for field in ["source", "c13", "c38", "c40", "c41"] {
            let invalidDigest = String(repeating: "0", count: 64)
            let binding = try CompletedInspectionReviewBindingV1(workspaceID: workspace,
                completedSnapshotSHA256: field == "source" ? invalidDigest : priorBinding.completedSnapshotSHA256,
                c13AssuranceSHA256: field == "c13" ? invalidDigest : priorBinding.c13AssuranceSHA256,
                c38AccountabilitySHA256: field == "c38" ? invalidDigest : priorBinding.c38AccountabilitySHA256,
                c40AuthorityCriterionSHA256: field == "c40" ? invalidDigest : priorBinding.c40AuthorityCriterionSHA256,
                c41FunctionalRelationshipsSHA256: field == "c41" ? invalidDigest : priorBinding.c41FunctionalRelationshipsSHA256)
            let history = try publicationReviewHistory(original: original, key: fixture.key, binding: binding)
            try history.validate()
            XCTAssertThrowsError(try ReportReviewedSourceV1(original: original,
                reportSubject: fixture.key, history: history), field)
        }
        // A legitimate new current source and fresh preview still cannot
        // inherit an old review by substituting its different original bytes.
        var changedObject = try XCTUnwrap(publicationSnapshotObject(original.basis.snapshot) as? [String: Any])
        changedObject["note"] = "A separately revised factual source"
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
        let changedSnapshot = try decoder.decode(ReportSnapshotV1.self,
            from: JSONSerialization.data(withJSONObject: changedObject))
        let changedBasis = try ReportPublicationBasisV1(workspaceID: workspace, audience: original.basis.audience,
            projectionVersion: original.basis.projectionVersion, snapshot: changedSnapshot)
        let changedPlain = try ReportPublicationV1(basis: changedBasis)
        let changed = try ReportPublicationV1(basis: changedBasis,
            assurance: publicationAssurance(basis: changedBasis, digest: changedPlain.basisSHA256))
        XCTAssertThrowsError(try ReportReviewedSourceV1(original: changed,
            reportSubject: fixture.key, history: fixture.history))
        var missingAuthority = original.basis.snapshot
        missingAuthority.authorityCriterion = nil
        XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: workspace, audience: original.basis.audience,
            projectionVersion: original.basis.projectionVersion, snapshot: missingAuthority))
        var foreignAccountability = original.basis.snapshot
        foreignAccountability.accountability = try CompletedAccountabilitySnapshotV1(
            workspaceID: C33TemporalEvidenceTestSupport.workspace(90))
        XCTAssertNoThrow(try ReportSnapshotEncoderV1().encode(foreignAccountability))
        XCTAssertThrowsError(try ReportPublicationBasisV1(workspaceID: workspace, audience: original.basis.audience,
            projectionVersion: original.basis.projectionVersion, snapshot: foreignAccountability))
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.encode(original).sha256, digest)
    }

    func testReportReviewedPublicationRejectsNoncanonicalAndMissingOriginalWire() throws {
        let fixture = try publicationReviewFixture()
        let source = try ReportReviewedSourceV1(original: fixture.original,
            reportSubject: fixture.key, history: fixture.history)
        let encoded = try ReportPublicationCanonicalCodecV1.encode(ReportReviewPublicationV1(source: source)).data
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for field in ["original", "history", "reportSubject"] {
            var root = original
            var nested = try XCTUnwrap(root["source"] as? [String: Any])
            nested.removeValue(forKey: field); root["source"] = nested
            XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeReview(
                JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])), field)
        }
        for field in ["reportPublicationSchemaVersion", "snapshotSchemaVersion", "unknown", "assurance"] {
            var root = original; root[field] = 1
            XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeReview(
                JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])), field)
        }
        for version in [0, 2] {
            var root = original; root["reportReviewPublicationSchemaVersion"] = version
            XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeReview(
                JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])))
        }
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeReview(
            Data(("{\"reportReviewPublicationSchemaVersion\":1," + text.dropFirst()).utf8)))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeReview(encoded + Data("\n".utf8)))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeReview(
            Data(repeating: 0x20, count: SnapshotProjectionLimitsV1.maximumProjectionBytes + 1)))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decodeReview(
            ReportSnapshotEncoderV1().encode(source.reportSnapshot()).data))
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.decodeReview(encoded).source.history, fixture.history)
    }

    private func publicationReviewFixture() throws ->
        (original: ReportPublicationV1, key: CompletedWorkSubjectKeyV1, history: CompletedInspectionReviewHistorySnapshotV1) {
        let authority = try C40AuthorityCriterionFixtureV1.makeFixture()
        let workspace = authority.workspaceID
        var snapshot = try publicationSnapshot(anchorSlots: [991, 992], workspace: workspace)
        // Use the actual shared constructor's seed mapping to share C40's
        // workspace; no accepted value is rebound or manually blessed.
        let lighting = try CanonicalLightingFixtureV1.makeFixture(slot: 8_000 - 290_000)
        XCTAssertEqual(lighting.system.workspaceID, workspace)
        snapshot.lightingDayInventory = try .init(workflow: lighting.day,
            admission: lighting.dayAdmission, poseSnapshots: [], capturedAt: lighting.day.recordedAt)
        snapshot.lightingNightWorkflow = try .init(workflow: lighting.night, capturedAt: lighting.night.recordedAt)
        snapshot.practiceWorkspace = try .init(workspaceID: workspace, provenance: nil)
        snapshot.fieldReferences = []
        snapshot.observationBasis = try .init(kind: .directlyObserved, method: .init(key: "visual"),
            source: .init(kind: .observer))
        snapshot.temporalContext = try .init(occurredAtUTC: snapshot.timeContext.observedAtUTC,
            recordedAtUTC: snapshot.snapshotCreatedAt, localDate: snapshot.timeContext.localDate,
            localTime: snapshot.timeContext.localTime, utcOffsetSeconds: snapshot.timeContext.utcOffsetMinutes * 60,
            ianaTimeZoneIdentifier: snapshot.timeContext.timeZoneID, localTimeDisposition: .unambiguous)
        snapshot.accountability = try .init(workspaceID: workspace, actors: [authority.actor],
            qualifications: [authority.qualification])
        let semantic = try XCTUnwrap(authority.scope.semanticBindings.first)
        let kind = try AssetKindBindingEventV1.canonical(eventID: semantic.kindBindingEventID,
            workspaceID: workspace, assetID: semantic.assetID, catalogRelease: semantic.catalogRelease,
            semanticID: semantic.semanticID, predecessorEventID: nil, revision: semantic.kindBindingRevision,
            mutationID: authority.mutationID, recordedAt: C40AuthorityCriterionFixtureV1.fixedDate)
        snapshot.assetSemantics = try .init(workspaceID: workspace, catalogReleases: [semantic.catalogRelease],
            kindBindings: [kind], workflowCapabilityBindings: [], productIdentities: [], lifecycleEvents: [],
            successorLinks: [], workSubjectScopes: [authority.scope])
        snapshot.authorityCriterion = try .init(workspaceID: workspace, aggregate: authority.aggregate)
        let relationships = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 8_000)
        snapshot.functionalRelationships = try .init(snapshotID: C33TemporalEvidenceTestSupport.id(10_020),
            workspaceID: workspace, capturedAt: relationships.added.recordedAt,
            descriptorReleases: [relationships.descriptor], relationships: [relationships.added])
        var object = try XCTUnwrap(publicationSnapshotObject(snapshot) as? [String: Any])
        object["snapshotSchemaVersion"] = 3
        object["snapshotCreatedAt"] = snapshot.snapshotCreatedAt.timeIntervalSinceReferenceDate.nextUp
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
        snapshot = try decoder.decode(ReportSnapshotV1.self, from: JSONSerialization.data(withJSONObject: object))
        let basis = try ReportPublicationBasisV1(workspaceID: workspace, audience: .customerSafe,
            projectionVersion: "report-projection-v1", snapshot: snapshot)
        let plain = try ReportPublicationV1(basis: basis)
        let original = try ReportPublicationV1(basis: basis,
            assurance: publicationAssurance(basis: basis, digest: plain.basisSHA256,
                createdAt: Date(timeIntervalSinceReferenceDate:
                    C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(50).timeIntervalSinceReferenceDate.nextUp)))
        // Explicit pure tuple uses the fixed position 2, not schema3 or four
        // history entries. Canonical lineage derivation belongs to the producer.
        let key = try CompletedWorkSubjectKeyV1(workspaceID: workspace,
            subjectID: snapshot.reportID, subjectRevision: 2)
        return (original, key, try publicationReviewHistory(original: original, key: key))
    }

    private func publicationReviewHistory(original: ReportPublicationV1, key: CompletedWorkSubjectKeyV1,
        transitionSubject: InspectionReviewSubjectReferenceV1? = nil,
        dispositionSubject: InspectionReviewSubjectReferenceV1? = nil,
        binding: CompletedInspectionReviewBindingV1? = nil) throws -> CompletedInspectionReviewHistorySnapshotV1 {
        return try fullReportHistory(snapshot: original.basis.snapshot,
            digest: ReportPublicationCanonicalCodecV1.encode(original).sha256,
            assurance: XCTUnwrap(original.assurance), key: key,
            transitionSubject: transitionSubject, dispositionSubject: dispositionSubject, binding: binding)
    }

    private func fullReportHistory(snapshot: ReportSnapshotV1, digest: String,
        assurance: ReportEvidenceAssuranceProjectionV1, key: CompletedWorkSubjectKeyV1,
        transitionSubject: InspectionReviewSubjectReferenceV1? = nil,
        dispositionSubject: InspectionReviewSubjectReferenceV1? = nil,
        binding: CompletedInspectionReviewBindingV1? = nil) throws -> CompletedInspectionReviewHistorySnapshotV1 {
        let subject = try InspectionReviewSubjectReferenceV1(workspaceID: key.workspaceID, kind: .reportSnapshot,
            subjectID: key.subjectID.uuidString.lowercased(), subjectRevision: key.subjectRevision, subjectSHA256: digest)
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: key.workspaceID,
            slot: 10_031, responsibility: .recordedBy)
        let reviewer = try C26SurveySessionTestSupport.actor(workspaceID: key.workspaceID,
            slot: 10_032, responsibility: .reviewedBy)
        let reviewID = C33TemporalEvidenceTestSupport.id(10_033)
        let dispositionID = C33TemporalEvidenceTestSupport.id(10_034)
        let states: [(InspectionReviewStateV1, InspectionReviewStateV1)] = [
            (.draft, .fieldComplete), (.fieldComplete, .readyForReview),
            (.readyForReview, .accepted), (.accepted, .finalized),
        ]
        var transitions: [InspectionReviewTransitionV1] = []
        for (index, states) in states.enumerated() {
            let value = try C14InspectionReviewTestSupportV1.makeTransition(seed: 916_100 + index,
                reviewID: reviewID, workspaceID: key.workspaceID, subject: transitionSubject ?? subject,
                from: states.0, to: states.1, actor: index == 2 ? reviewer : actor,
                revision: UInt64(index + 1), mutationSeed: 916_200 + index,
                predecessor: transitions.last?.transitionID, dispositionID: index == 2 ? dispositionID : nil)
            transitions.append(value)
        }
        let disposition = try ReviewDispositionV1(dispositionID: dispositionID, reviewID: reviewID,
            workspaceID: key.workspaceID, subject: dispositionSubject ?? subject, reviewRevision: 3,
            kind: .accepted, reviewer: reviewer, reason: "Recorded local review of this exact report",
            recordedAt: C14InspectionReviewTestSupportV1.fixedDate.addingTimeInterval(3),
            mutationID: C33TemporalEvidenceTestSupport.mutation(10_035))
        let exactBinding = try binding ?? CompletedInspectionReviewBindingV1(workspaceID: key.workspaceID,
            completedSnapshotSHA256: digest,
            c13AssuranceSHA256: publicationDigest(ReportEvidenceAssuranceCanonicalCodecV1.encode(assurance)),
            c38AccountabilitySHA256: XCTUnwrap(snapshot.accountability).snapshotSHA256,
            c40AuthorityCriterionSHA256: XCTUnwrap(snapshot.authorityCriterion).snapshotSHA256,
            c41FunctionalRelationshipsSHA256: XCTUnwrap(snapshot.functionalRelationships).snapshotSHA256)
        return try CompletedInspectionReviewHistorySnapshotV1(workspaceID: key.workspaceID,
            sourceSnapshotSHA256: exactBinding.completedSnapshotSHA256, binding: exactBinding,
            reviewHistory: transitions, reviewDispositions: [disposition], changeHistory: [], actionHistory: [])
    }

    // Test-owned explicit wire schemas. These never parse product output or
    // copy product-computed hashes; expected basis identity is computed below
    // from original typed source values with the independently named fields.
    private struct PublicationExpectedBasis: Encodable {
        let reportBasisSchemaVersion = 1
        let workspaceID: String
        let audience: String
        let projectionVersion: String
        let snapshot: ReportSnapshotV1
    }

    private struct PublicationExpectedOuter: Encodable {
        let reportPublicationSchemaVersion = 1
        let basis: PublicationExpectedBasis
        let basisSHA256: String
        let assurance: ReportEvidenceAssuranceProjectionV1?
    }

    private struct PublicationExpectedReportSubject: Encodable {
        let workspaceID: String
        let reportID: String
        let fixedCorrectionChainRevision: UInt64
    }

    private struct PublicationExpectedReviewedSource: Encodable {
        let reportReviewedSourceSchemaVersion = 1
        let original: PublicationExpectedOuter
        let reportSubject: PublicationExpectedReportSubject
        let history: CompletedInspectionReviewHistorySnapshotV1
    }

    private struct PublicationExpectedReviewedOutput: Encodable {
        let reportReviewPublicationSchemaVersion = 1
        let source: PublicationExpectedReviewedSource
    }

    private func publicationExpectedBasis(_ basis: ReportPublicationBasisV1) -> PublicationExpectedBasis {
        .init(workspaceID: basis.workspaceID.rawValue.uuidString.lowercased(),
            audience: basis.audience.rawValue, projectionVersion: basis.projectionVersion,
            snapshot: basis.snapshot)
    }

    private func publicationExpectedWire(_ value: ReportPublicationV1) throws -> PublicationExpectedOuter {
        let basis = publicationExpectedBasis(value.basis)
        return try .init(basis: basis,
            basisSHA256: publicationDigest(publicationExpectedBytes(basis)), assurance: value.assurance)
    }

    private func publicationExpectedBytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(value)
    }

    private func publicationTypedObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private func publicationSnapshotObject(_ snapshot: ReportSnapshotV1) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try JSONSerialization.jsonObject(with: encoder.encode(snapshot))
    }

    private func publicationAssuranceObject(_ assurance: ReportEvidenceAssuranceProjectionV1) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try JSONSerialization.jsonObject(with: encoder.encode(assurance))
    }

    private func publicationSnapshot(anchorSlots: [Int],
        workspace: WorkspaceID = C33TemporalEvidenceTestSupport.workspace()) throws -> ReportSnapshotV1 {
        let fixture = try C33TemporalEvidenceTestSupport.clip(slot: 990,
            workspaceID: workspace, reportProjection: .typedLinkOnly)
        let anchors = try anchorSlots.map { try C33TemporalEvidenceTestSupport.anchor(clip: fixture.clip, slot: $0) }
        return try C33TemporalEvidenceTestSupport.reportSnapshot(clip: fixture.clip, anchors: anchors,
            reportID: C33TemporalEvidenceTestSupport.id(950), slot: 960, includesAssurance: false)
    }

    private func publicationAssurance(basis: ReportPublicationBasisV1, digest: String,
        workspace: WorkspaceID? = nil, audience: EvidenceAudienceV1 = .customerReport,
        projectionVersion: String? = nil, createdAt: Date? = nil) throws -> ReportEvidenceAssuranceProjectionV1 {
        let workspace = workspace ?? basis.workspaceID
        let visibility = try EvidenceVisibilityV1(visibilityID: C33TemporalEvidenceTestSupport.id(970),
            workspaceID: workspace, sensitivity: .routine, allowedAudiences: [.customerReport, .internalReview],
            effectiveAt: C33TemporalEvidenceTestSupport.fixedDate,
            mutationID: C33TemporalEvidenceTestSupport.mutation(971))
        let link = try ClaimEvidenceLinkV1(linkID: C33TemporalEvidenceTestSupport.id(972),
            workspaceID: workspace, claimID: "temporal-observation", evidenceID: "temporal.content.990",
            evidenceRevision: 1, evidenceSHA256: try XCTUnwrap(basis.snapshot.temporalEvidenceLinks?.first?.clipSHA256),
            visibility: visibility, audience: audience, mutationID: C33TemporalEvidenceTestSupport.mutation(973))
        let preview = try AssuranceProjectionPreviewV1(previewID: C33TemporalEvidenceTestSupport.id(974),
            workspaceID: workspace, audience: audience, snapshotSHA256: digest,
            projectionVersion: projectionVersion ?? basis.projectionVersion, links: [link],
            createdAt: createdAt ?? C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(50))
        return try ReportEvidenceAssuranceProjectionV1(preview: preview, visibilities: [visibility])
    }

    private func publicationDigest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

extension V9_16SnapshotProjectionTests {
    @MainActor
    func testReportFullSourceInitialPacketPoseMatrixPreservesIndependentIdentities() throws {
        let base = try publicationReviewFixture().original.basis
        let assetID = C33TemporalEvidenceTestSupport.id(11_001)
        let input = try fullReportInput(base, assetID: assetID, revision: 2, step: "close")
        let assigned = try fullReportInput(base, assetID: assetID, revision: 1, step: "wide")
        let packet = try fullReportPacketInput(assigned, legacyPacketID: base.snapshot.packetID)
        let pose = try fullReportPose(base.workspaceID, assetID: assetID)
        XCTAssertNotEqual(packet.snapshot.manifest.packetID, base.snapshot.packetID)
        XCTAssertEqual(packet.snapshot.manifest.items.count, 2)
        XCTAssertNotEqual(input.sourceRevision, packet.item.expectedRevision)
        let combinations: [(ReportPacketInputSourceV1?, ReportPoseHistorySourceV1?)] = [
            (packet, nil), (nil, pose), (packet, pose),
        ]
        for (packet, pose) in combinations {
            let source = try ReportInitialCoordinatedSourceV1(initial: base, input: input, packet: packet, pose: pose)
            let basis = try ReportCurrentPublicationBasisV2(source: .initialCoordinated(source),
                audience: base.audience, projectionVersion: base.projectionVersion)
            let value = try ReportCurrentPublicationV2(basis: basis)
            let expectedBasis = FullExpectedBasis(basis: FullExpectedBasisValue(
                source: FullExpectedSource(sourceKind: "INITIAL_COORDINATED", value: FullExpectedCoordinated(
                    initial: publicationExpectedBasis(base), input: input, packet: packet, pose: pose)),
                audience: base.audience, projectionVersion: base.projectionVersion))
            let bytes = try publicationExpectedBytes(expectedBasis)
            XCTAssertEqual(try ReportCurrentPublicationCanonicalCodecV2.encodeBasis(basis), bytes)
            XCTAssertEqual(value.basisSHA256, publicationDigest(bytes))
            let expected = FullExpectedOuter(basis: expectedBasis, basisSHA256: publicationDigest(bytes), currentAssurance: nil)
            let encoded = try ReportCurrentPublicationCanonicalCodecV2.encode(value)
            XCTAssertEqual(encoded.data, try publicationExpectedBytes(expected))
            XCTAssertEqual(encoded.sha256, try publicationDigest(publicationExpectedBytes(expected)))
            XCTAssertEqual(try ReportCurrentPublicationCanonicalCodecV2.decode(encoded.data), value)
            let view = try value.view()
            XCTAssertEqual(view.base, base.snapshot)
            XCTAssertEqual(view.initialPacket?.itemCount, packet?.snapshot.manifest.items.count)
            XCTAssertEqual(view.initialPose?.projection.history.count, pose == nil ? nil : 1)
            XCTAssertNil(view.history); XCTAssertNil(view.historicalAssurance); XCTAssertNil(view.currentAssurance)
            XCTAssertNil(view.laterPose); XCTAssertNil(view.laterPacket)
            XCTAssertEqual(view.base.temporalEvidenceLinks, base.snapshot.temporalEvidenceLinks)
        }
        XCTAssertThrowsError(try ReportInitialCoordinatedSourceV1(initial: base, input: input))
        let conflictingSameRevision = try fullReportInput(base, assetID: assetID, revision: 1, step: "close")
        XCTAssertThrowsError(try packet.validate(current: conflictingSameRevision))
        let wrongAsset = try fullReportInput(base, assetID: C33TemporalEvidenceTestSupport.id(11_002), revision: 2, step: "close")
        XCTAssertThrowsError(try packet.validate(current: wrongAsset))
        // Pure compatibility is not an accepted continuation; the production
        // writer/journal witness remains a separate required adoption gate.
        try packet.validate(current: input)
    }

    @MainActor
    func testReportFullSourceReviewsCompleteInitialV2AndRequiresFreshWholeSourceAssurance() throws {
        let fixture = try publicationReviewFixture(), base = fixture.original.basis
        let assetID = C33TemporalEvidenceTestSupport.id(11_100)
        let input = try fullReportInput(base, assetID: assetID, revision: 1, step: "review")
        let packet = try fullReportPacketInput(input, legacyPacketID: base.snapshot.packetID)
        let pose = try fullReportPose(base.workspaceID, assetID: assetID)
        let coordinated = try ReportInitialCoordinatedSourceV1(initial: base, input: input, packet: packet, pose: pose)
        let preAssurance = try ReportInitialPublicationV2(content: .coordinated(coordinated),
            audience: base.audience, projectionVersion: base.projectionVersion)
        let initial = try ReportInitialPublicationV2(content: .coordinated(coordinated),
            audience: base.audience, projectionVersion: base.projectionVersion,
            assurance: publicationAssurance(basis: base, digest: preAssurance.basisSHA256))
        let originalBytes = try ReportCurrentPublicationCanonicalCodecV2.encode(initial.currentPublication())
        let subject = try CompletedWorkSubjectKeyV1(workspaceID: base.workspaceID,
            subjectID: base.snapshot.reportID, subjectRevision: 1)
        let history = try fullReportHistory(snapshot: base.snapshot, digest: originalBytes.sha256,
            assurance: XCTUnwrap(initial.assurance), key: subject)
        let reviewed = try ReportReviewedSourceV2(original: .initial(initial), reportSubject: subject, history: history)
        let basis = try ReportCurrentPublicationBasisV2(source: .reviewed(reviewed), audience: base.audience,
            projectionVersion: base.projectionVersion)
        let unassured = try ReportCurrentPublicationV2(basis: basis)
        XCTAssertThrowsError(try ReportCurrentPublicationV2(basis: basis, currentAssurance: initial.assurance))
        let current = try publicationAssurance(basis: base, digest: unassured.basisSHA256)
        let output = try ReportCurrentPublicationV2(basis: basis, currentAssurance: current)
        let view = try output.view()
        XCTAssertEqual(view.history, history); XCTAssertEqual(view.historicalAssurance, initial.assurance)
        XCTAssertEqual(view.currentAssurance, current); XCTAssertNotEqual(view.currentAssurance, view.historicalAssurance)
        XCTAssertEqual(view.initialPacket?.packetID, packet.snapshot.manifest.packetID)
        XCTAssertEqual(view.initialPose, try pose.projection())
        XCTAssertEqual(view.base, base.snapshot)
        let bytes = try ReportCurrentPublicationCanonicalCodecV2.encode(output)
        XCTAssertEqual(try ReportCurrentPublicationCanonicalCodecV2.decode(bytes.data), output)
        XCTAssertEqual(try reviewed.original.encoded(), originalBytes)
        XCTAssertNotEqual(bytes.sha256, originalBytes.sha256)
        XCTAssertEqual(try ReportPublicationCanonicalCodecV1.encode(fixture.original).data,
            try publicationExpectedBytes(publicationExpectedWire(fixture.original)))
        // V1 and full V2 are both legitimate immutable C14 original cases.
        let oldReviewed = try ReportReviewedSourceV2(original: .legacy(fixture.original),
            reportSubject: fixture.key, history: fixture.history)
        let oldOutput = try ReportCurrentPublicationV2(basis: .init(source: .reviewed(oldReviewed),
            audience: base.audience, projectionVersion: base.projectionVersion))
        XCTAssertEqual(try oldOutput.view().history, fixture.history)
        XCTAssertThrowsError(try ReportReviewedSourceV2(original: .initial(initial), reportSubject: fixture.key, history: history))
        let changedAudience = try ReportCurrentPublicationBasisV2(source: .reviewed(reviewed), audience: .internalUse,
            projectionVersion: base.projectionVersion)
        XCTAssertThrowsError(try ReportCurrentPublicationV2(basis: changedAudience, currentAssurance: current))
        let changedVersion = try ReportCurrentPublicationBasisV2(source: .reviewed(reviewed), audience: base.audience,
            projectionVersion: "report-projection-v2")
        XCTAssertThrowsError(try ReportCurrentPublicationV2(basis: changedVersion, currentAssurance: current))
        // A reviewed original is structurally impossible in the initial-only
        // type and is rejected by its decoder before parsing another wrapper.
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
        XCTAssertThrowsError(try decoder.decode(ReportInitialPublicationV2.self, from: bytes.data))
    }

    @MainActor
    func testReportFullSourceRecordedResultJoinsExactReportTupleWithoutEvidenceRelabeling() throws {
        let fixture = try publicationReviewFixture(), base = fixture.original.basis
        let input = try fullReportInput(base, assetID: C33TemporalEvidenceTestSupport.id(11_200), revision: 1, step: "review")
        let packet = try fullReportPacketInput(input, legacyPacketID: base.snapshot.packetID)
        let initialSource = try ReportInitialCoordinatedSourceV1(initial: base, input: input, packet: packet)
        let plain = try ReportInitialPublicationV2(content: .coordinated(initialSource), audience: base.audience,
            projectionVersion: base.projectionVersion)
        let initial = try ReportInitialPublicationV2(content: plain.content, audience: base.audience,
            projectionVersion: base.projectionVersion,
            assurance: publicationAssurance(basis: base, digest: plain.basisSHA256))
        let original = ReportOriginalPublicationV2.initial(initial)
        let subject = try CompletedWorkSubjectKeyV1(workspaceID: base.workspaceID, subjectID: base.snapshot.reportID, subjectRevision: 1)
        let history = try fullReportHistory(snapshot: base.snapshot, digest: original.encoded().sha256,
            assurance: XCTUnwrap(initial.assurance), key: subject)
        let reviewed = try ReportReviewedSourceV2(original: original, reportSubject: subject, history: history)
        let origin = try fullReportStructuralOrigin(original: original, assetID: input.sourceRecord.assetID, subject: subject)
        let product = try WorkPacketResultLinkV1(resultID: subject.subjectID,
            resultMutationID: origin.receipt.mutationID, itemExpectedRevision: packet.item.expectedRevision,
            resultRevision: subject.subjectRevision, resultSHA256: original.encoded().sha256, evidence: [])
        let released = try fullReportRelease(packet: packet, result: product)
        let binding = try WorkPacketReportResultBindingV1(snapshot: released.snapshot, item: packet.item,
            releaseID: released.release.releaseID, result: product, subject: subject,
            originalSHA256: original.encoded().sha256, finalizationMutationID: origin.receipt.mutationID)
        let source = try ReportReviewedCoordinatedSourceV1(reviewed: reviewed, origin: origin,
            packet: .init(snapshot: released.snapshot, association: .recordedResult(binding)))
        let basis = try ReportCurrentPublicationBasisV2(source: .reviewedCoordinated(source),
            audience: base.audience, projectionVersion: base.projectionVersion)
        let output = try ReportCurrentPublicationV2(basis: basis)
        XCTAssertEqual(try ReportCurrentPublicationCanonicalCodecV2.decode(ReportCurrentPublicationCanonicalCodecV2.encode(output).data), output)
        XCTAssertNotEqual(released.snapshot.manifest.packetID, base.snapshot.packetID)
        XCTAssertEqual(released.snapshot.manifest.items.count, 2)
        XCTAssertEqual(binding.result.evidence, [])
        XCTAssertEqual(try output.view().laterPacket?.preservedResultCount, 1)
        XCTAssertEqual(try output.view().initialPacket?.preservedResultCount, 0)
        XCTAssertEqual(try output.view().base, base.snapshot)
        let wrongMutation = try C33TemporalEvidenceTestSupport.mutation(11_201)
        XCTAssertThrowsError(try binding.validate(snapshot: released.snapshot, subject: subject,
            originalSHA256: original.encoded().sha256, finalizationMutationID: wrongMutation))
        XCTAssertThrowsError(try binding.validate(snapshot: released.snapshot, subject: fixture.key,
            originalSHA256: original.encoded().sha256, finalizationMutationID: origin.receipt.mutationID))
        XCTAssertThrowsError(try binding.validate(snapshot: released.snapshot, subject: subject,
            originalSHA256: String(repeating: "f", count: 64), finalizationMutationID: origin.receipt.mutationID))
        let requiringEvidence = try fullReportPacketInput(input, legacyPacketID: base.snapshot.packetID,
            requiresEvidence: true)
        XCTAssertThrowsError(try fullReportRelease(packet: requiringEvidence, result: product))
        let directItem = try WorkPacketItemV1(itemID: subject.subjectID.uuidString.lowercased(), kind: .inspection,
            expectedRevision: subject.subjectRevision, itemSHA256: original.encoded().sha256)
        let directManifest = try WorkPacketManifestV1(manifestID: C33TemporalEvidenceTestSupport.id(11_210),
            packetID: C33TemporalEvidenceTestSupport.id(11_211), packetVersion: 1, workspaceID: base.workspaceID,
            items: [directItem, packet.snapshot.manifest.items.first(where: { $0.itemID == "unrelated-recheck" })!],
            packageReleases: [], creationBasis: .explicitLocalSelection, creator: packet.snapshot.manifest.creator,
            createdAt: packet.snapshot.createdAt, mutationID: C33TemporalEvidenceTestSupport.mutation(11_212))
        let direct = ReportPacketSourceV1(snapshot: try .init(manifest: directManifest, claims: [], leases: [],
            releases: [], handoffs: [], createdAt: packet.snapshot.createdAt),
            association: .directInspection(try .init(manifest: directManifest, item: directItem)))
        let pose = try fullReportPose(base.workspaceID, assetID: input.sourceRecord.assetID)
        for (packetSource, poseSource) in [(Optional(direct), Optional<ReportPoseHistorySourceV1>.none),
                                         (nil, Optional(pose)), (Optional(direct), Optional(pose))] {
            let value = try ReportReviewedCoordinatedSourceV1(reviewed: reviewed, origin: origin,
                packet: packetSource, pose: poseSource)
            let frozen = try ReportCurrentPublicationV2(basis: .init(source: .reviewedCoordinated(value),
                audience: base.audience, projectionVersion: base.projectionVersion))
            XCTAssertEqual(try ReportCurrentPublicationCanonicalCodecV2.decode(
                ReportCurrentPublicationCanonicalCodecV2.encode(frozen).data), frozen)
            XCTAssertEqual(try frozen.view().history, history)
            XCTAssertEqual(try frozen.view().laterPose, try poseSource?.projection())
            XCTAssertEqual(try frozen.view().base, base.snapshot)
            XCTAssertEqual(try frozen.view().historicalAssurance, initial.assurance)
        }
        XCTAssertThrowsError(try ReportReviewedCoordinatedSourceV1(reviewed: reviewed, origin: origin))
        // Handoff is optional corroboration of the exact selected release and
        // full result. It cannot substitute a different result or release.
        let handed = try fullReportRelease(packet: packet, result: product, reason: .handoff)
        let handoff = try WorkHandoffV1(handoffID: C33TemporalEvidenceTestSupport.id(11_220), workspaceID: base.workspaceID,
            releaseID: handed.release.releaseID, item: packet.item, fromHolder: handed.release.holder,
            toHolder: C26SurveySessionTestSupport.actor(workspaceID: base.workspaceID, slot: 11_221, responsibility: .assignedTo),
            resultLinks: [product], reason: "Explicit local handoff", handedOffAt: handed.release.releasedAt.addingTimeInterval(1),
            mutationID: C33TemporalEvidenceTestSupport.mutation(11_222))
        let handedSnapshot = try CompletedWorkPacketSnapshotV1(manifest: handed.snapshot.manifest,
            claims: handed.snapshot.claims, leases: handed.snapshot.leases, releases: handed.snapshot.releases,
            handoffs: [handoff], sourceRevision: 5, createdAt: handoff.handedOffAt)
        let handoffBinding = try WorkPacketReportResultBindingV1(snapshot: handedSnapshot, item: packet.item,
            releaseID: handed.release.releaseID, handoffID: handoff.handoffID, result: product, subject: subject,
            originalSHA256: original.encoded().sha256, finalizationMutationID: origin.receipt.mutationID)
        XCTAssertEqual(handoffBinding.result, product)
        XCTAssertThrowsError(try handoffBinding.validate(snapshot: released.snapshot, subject: subject,
            originalSHA256: original.encoded().sha256, finalizationMutationID: origin.receipt.mutationID))
        func releaseCopy(_ result: WorkPacketResultLinkV1, slot: Int) throws -> WorkReleaseV1 {
            let old = released.release
            return try .init(releaseID: C33TemporalEvidenceTestSupport.id(slot), workspaceID: old.workspaceID,
                claimID: old.claimID, leaseID: old.leaseID, item: old.item, holder: old.holder, reason: old.reason,
                resultLinks: [result], releasedAt: old.releasedAt, mutationID: C33TemporalEvidenceTestSupport.mutation(slot + 1))
        }
        func snapshot(_ additions: [WorkReleaseV1]) throws -> CompletedWorkPacketSnapshotV1 {
            try .init(manifest: released.snapshot.manifest, claims: released.snapshot.claims, leases: released.snapshot.leases,
                releases: released.snapshot.releases + additions, handoffs: [], sourceRevision: 6,
                createdAt: released.snapshot.createdAt)
        }
        let divergent = try WorkPacketResultLinkV1(resultID: product.resultID, resultMutationID: wrongMutation,
            itemExpectedRevision: product.itemExpectedRevision, resultRevision: product.resultRevision,
            resultSHA256: product.resultSHA256, evidence: [])
        let ambiguous = try snapshot([releaseCopy(divergent, slot: 11_230)])
        XCTAssertThrowsError(try binding.validate(snapshot: ambiguous, subject: subject,
            originalSHA256: original.encoded().sha256, finalizationMutationID: origin.receipt.mutationID))
        let otherID = C33TemporalEvidenceTestSupport.id(11_240)
        let otherA = try WorkPacketResultLinkV1(resultID: otherID, resultMutationID: wrongMutation,
            itemExpectedRevision: product.itemExpectedRevision, resultRevision: 1,
            resultSHA256: String(repeating: "a", count: 64), evidence: [])
        let otherB = try WorkPacketResultLinkV1(resultID: otherID, resultMutationID: C33TemporalEvidenceTestSupport.mutation(11_241),
            itemExpectedRevision: product.itemExpectedRevision, resultRevision: 2,
            resultSHA256: String(repeating: "b", count: 64), evidence: [])
        let unrelated = try snapshot([releaseCopy(otherA, slot: 11_242), releaseCopy(otherB, slot: 11_244)])
        try binding.validate(snapshot: unrelated, subject: subject,
            originalSHA256: original.encoded().sha256, finalizationMutationID: origin.receipt.mutationID)
        XCTAssertEqual(unrelated.releases.count, 3)
        XCTAssertGreaterThan(try ReportWorkPacketProjectionV1(snapshot: unrelated,
            sourceSnapshotSHA256: original.encoded().sha256).collisionCount, 0)
    }

    @MainActor
    func testReportFullSourceCodecRejectsUnknownNullNonfiniteAndChangedCanonicalBytes() throws {
        let base = try publicationReviewFixture().original.basis
        let value = try ReportCurrentPublicationV2(basis: .init(source: .initial(base),
            audience: base.audience, projectionVersion: base.projectionVersion))
        let encoded = try ReportCurrentPublicationCanonicalCodecV2.encode(value)
        XCTAssertEqual(try ReportCurrentPublicationCanonicalCodecV2.decode(encoded.data), value)
        XCTAssertThrowsError(try ReportSnapshotEncoderV1().decode(encoded.data))
        XCTAssertThrowsError(try ReportPublicationCanonicalCodecV1.decode(encoded.data))
        let text = try XCTUnwrap(String(data: encoded.data, encoding: .utf8))
        let hostile = [" " + text, text + "\n",
            text.replacingOccurrences(of: "\"reportCurrentPublicationSchemaVersion\":2", with: "\"reportCurrentPublicationSchemaVersion\":3"),
            text.replacingOccurrences(of: "\"sourceKind\":\"INITIAL\"", with: "\"sourceKind\":\"UNKNOWN\""),
            "{\"extra\":true," + text.dropFirst(),
            "{\"currentAssurance\":null," + text.dropFirst(),
            "{\"reportCurrentPublicationSchemaVersion\":2," + text.dropFirst(),
        ]
        for bytes in hostile { XCTAssertThrowsError(try ReportCurrentPublicationCanonicalCodecV2.decode(Data(bytes.utf8))) }
        XCTAssertThrowsError(try ReportCurrentPublicationCanonicalCodecV2.typedBytes(Date(timeIntervalSinceReferenceDate: .infinity)))
        let instant = Date(timeIntervalSinceReferenceDate: 841_694_450.0000001)
        XCTAssertEqual(try ReportCurrentPublicationCanonicalCodecV2.typedBytes(instant), try publicationExpectedBytes(instant))
        XCTAssertNotEqual(try ReportCurrentPublicationCanonicalCodecV2.typedBytes(instant),
            try ReportCurrentPublicationCanonicalCodecV2.typedBytes(Date(timeIntervalSinceReferenceDate: instant.timeIntervalSinceReferenceDate.nextUp)))
    }

    private struct FullExpectedSource<Value: Encodable>: Encodable { let sourceKind: String; let value: Value }
    private struct FullExpectedCoordinated: Encodable {
        let initial: PublicationExpectedBasis; let input: ReportInitialInputBindingV1
        let packet: ReportPacketInputSourceV1?; let pose: ReportPoseHistorySourceV1?
    }
    private struct FullExpectedBasisValue<Source: Encodable>: Encodable {
        let source: Source; let audience: ReportAudienceV1; let projectionVersion: String
    }
    private struct FullExpectedBasis<Basis: Encodable>: Encodable { let reportCurrentBasisSchemaVersion = 2; let basis: Basis }
    private struct FullExpectedOuter<Basis: Encodable>: Encodable {
        let reportCurrentPublicationSchemaVersion = 2; let basis: Basis
        let basisSHA256: String; let currentAssurance: ReportEvidenceAssuranceProjectionV1?
    }

    private func fullReportInput(_ base: ReportPublicationBasisV1, assetID: UUID, revision: UInt64,
        step: String, completed: Bool = false, mutationID: UUID? = nil) throws -> ReportInitialInputBindingV1 {
        let s = base.snapshot
        let record = WorkflowRecordPayloadV1(id: s.sourceRecordID, schemaVersion: 1, assetID: assetID,
            packetID: completed ? s.packetID : nil, issueID: nil, parentRecordID: nil,
            recordRevisionRootID: s.sourceRecordID, revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: WorkflowRevisionKind.original.rawValue, stage: s.stage,
            state: completed ? WorkflowState.completed.rawValue : WorkflowState.draft.rawValue,
            draftStepKey: completed ? nil : step, startedAt: s.snapshotCreatedAt.addingTimeInterval(-60),
            completedAt: completed ? s.snapshotCreatedAt : nil, observedAtUTC: s.timeContext.observedAtUTC,
            timeZoneID: s.timeContext.timeZoneID, utcOffsetMinutes: s.timeContext.utcOffsetMinutes,
            localDate: s.timeContext.localDate, localTime: s.timeContext.localTime,
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: nil,
            packID: s.pack.id, packSchemaVersion: s.pack.schemaVersion, packContentVersion: s.pack.contentVersion,
            pdfTemplateID: s.pdfTemplate.id, pdfTemplateVersion: s.pdfTemplate.version, outcomeKey: s.outcome,
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil, note: s.note, finalizationMutationID: mutationID)
        return try .init(workspaceID: base.workspaceID, sourceRecord: record, sourceRevision: revision)
    }

    private func fullReportPacketInput(_ input: ReportInitialInputBindingV1, legacyPacketID: UUID,
        requiresEvidence: Bool = false) throws -> ReportPacketInputSourceV1 {
        let creator = try C26SurveySessionTestSupport.actor(workspaceID: input.workspaceID,
            slot: 11_300, responsibility: .recordedBy)
        let requirement = try WorkPacketEvidenceRequirementV1(requirementID: "required-completed-activity",
            evidenceKind: .completedActivitySnapshot, minimumCount: 1)
        let item = try WorkPacketItemV1(itemID: input.sourceRecord.id.uuidString.lowercased(), kind: .inspection,
            expectedRevision: input.sourceRevision, itemSHA256: input.inputSHA256,
            evidenceRequirements: requiresEvidence ? [requirement] : [])
        let other = try WorkPacketItemV1(itemID: "unrelated-recheck", kind: .operationalRecheck,
            expectedRevision: 7, itemSHA256: String(repeating: "b", count: 64))
        let manifest = try WorkPacketManifestV1(manifestID: C33TemporalEvidenceTestSupport.id(11_301),
            packetID: C33TemporalEvidenceTestSupport.id(11_302), packetVersion: 1, workspaceID: input.workspaceID,
            items: [item, other], packageReleases: [], creationBasis: .explicitLocalSelection, creator: creator,
            createdAt: C33TemporalEvidenceTestSupport.fixedDate, mutationID: C33TemporalEvidenceTestSupport.mutation(11_303))
        XCTAssertNotEqual(manifest.packetID, legacyPacketID)
        let snapshot = try CompletedWorkPacketSnapshotV1(manifest: manifest, claims: [], leases: [], releases: [],
            handoffs: [], createdAt: C33TemporalEvidenceTestSupport.fixedDate)
        return try .init(snapshot: snapshot, item: .init(manifest: manifest, item: item), manifestInput: input)
    }

    private func fullReportRelease(packet: ReportPacketInputSourceV1, result: WorkPacketResultLinkV1, reason: WorkReleaseReasonV1 = .completed) throws
        -> (snapshot: CompletedWorkPacketSnapshotV1, release: WorkReleaseV1) {
        let workspace = packet.snapshot.workspaceID, date = packet.snapshot.createdAt
        let holder = try C26SurveySessionTestSupport.actor(workspaceID: workspace, slot: 11_310, responsibility: .assignedTo)
        let claim = try WorkItemClaimV1(claimID: C33TemporalEvidenceTestSupport.id(11_311), workspaceID: workspace,
            manifest: .init(packet.snapshot.manifest), item: packet.item, holder: holder, claimSequence: 1,
            claimedAt: date, mutationID: C33TemporalEvidenceTestSupport.mutation(11_312))
        let lease = try WorkLeaseV1(leaseID: C33TemporalEvidenceTestSupport.id(11_313), workspaceID: workspace,
            claimID: claim.claimID, item: packet.item, holder: holder, leaseSequence: 1,
            startsAt: date, expiresAt: date.addingTimeInterval(600), mutationID: C33TemporalEvidenceTestSupport.mutation(11_314))
        let release = try WorkReleaseV1(releaseID: C33TemporalEvidenceTestSupport.id(11_315), workspaceID: workspace,
            claimID: claim.claimID, leaseID: lease.leaseID, item: packet.item, holder: holder, reason: reason,
            resultLinks: [result], releasedAt: date.addingTimeInterval(20), mutationID: C33TemporalEvidenceTestSupport.mutation(11_316))
        try release.validate(claim: claim, lease: lease, manifest: packet.snapshot.manifest)
        return (try .init(manifest: packet.snapshot.manifest, claims: [claim], leases: [lease], releases: [release],
            handoffs: [], sourceRevision: 4, createdAt: date.addingTimeInterval(21)), release)
    }
}

extension V9_16SnapshotProjectionTests {
    // Pure command/receipt constructors prove structural joins, not journal
    // acceptance. The production finalizer does not yet emit this V2 wire.
    private func fullReportAtomic(workspace: WorkspaceID, mutation: MutationIDV1,
        command: WorkspaceCommandV1, images: [MutationPostImageV1],
        additionalLocks: [WorkspaceEntityRevisionV1] = [], sequence: UInt64 = 1,
        sourceKind: MutationSourceKindV1 = .localUser, generation: UUID = C33TemporalEvidenceTestSupport.id(11_500)) throws
        -> (envelope: MutationEnvelopeV1, receipt: MutationReceiptV1) {
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: workspace,
            generationID: generation, writerInstanceID: C33TemporalEvidenceTestSupport.id(11_501),
            workspaceRevision: sequence - 1, entityRevisions: images.map {
                .init(identity: try $0.concurrencyIdentity, revision: $0.revision - 1)
            } + additionalLocks)
        let envelope = try MutationEnvelopeV1(request: .init(mutationID: mutation,
            expectedRevision: expected, command: command), identity: .init(workspaceID: workspace,
                replicaID: ReplicaID(rawValue: C33TemporalEvidenceTestSupport.id(11_502))), sourceKind: sourceKind)
        let imageIDs = Set(try images.map { try $0.identity })
        let result = try WorkspaceExpectedRevisionV1(workspaceID: workspace,
            generationID: generation, writerInstanceID: expected.writerInstanceID,
            workspaceRevision: sequence, entityRevisions: images.map {
                .init(identity: try $0.identity, revision: $0.revision)
            } + expected.entityRevisions.filter { !imageIDs.contains($0.identity) })
        let receipt = try MutationReceiptV1(identity: .init(workspaceID: workspace,
            replicaID: envelope.replicaID, localSequence: sequence), envelope: envelope,
            resultingRevision: .init(result), postImages: images,
            committedAt: C37PoseTestSupport.fixedDate.addingTimeInterval(Double(sequence)))
        return (envelope, receipt)
    }

    private func fullReportPose(_ workspace: WorkspaceID, assetID: UUID, planRelative: Bool = false, optional: Bool = false) throws -> ReportPoseHistorySourceV1 {
        let package = try C37PoseTestSupport.packageRelease()
        let axis = try C37PoseTestSupport.descriptor("report", required: .azimuthOnly,
            observationRequirement: optional ? .optional : .requiredForCompletion)
        let (plan, page, frame) = try C37PoseTestSupport.planRevision(workspaceID: workspace)
        let poseFrame: PoseReferenceFrameV1 = planRelative ? .planRelative(.init(planRevision: try plan.reference,
            pageID: page.pageID, spatialFrameID: frame.frameID, acceptedTransformSHA256: try PlanAffineTransformV1(
                m11: 1_000_000_000, m12: 0, m21: 0, m22: 1_000_000_000, tx: 0, ty: 0).transformSHA256)) : .trueBearing
        let registry = try PoseAxisRegistryReleaseV1(packageRelease: package,
            registry: .init(descriptors: [axis]))
        let placement = try C37PoseTestSupport.placement(workspaceID: workspace, assetID: assetID,
            placementID: C37PoseTestSupport.id(11_510), episode: C37PoseTestSupport.episode(11_511),
            path: C37PoseTestSupport.locationPathSnapshot(), mutationSlot: 11_512)
        let event = try C37PoseTestSupport.poseEvent(workspaceID: workspace, assetID: assetID,
            descriptor: axis, eventID: C37PoseTestSupport.id(11_513),
            pose: C37PoseTestSupport.observedPose(descriptor: axis, referenceFrame: poseFrame),
            placementEventID: placement.id, placementEpisodeID: placement.physicalEpisodeID)
        let pose = try PlacementPoseMutationV1(workspaceID: workspace, mutationID: event.mutationID,
            events: [event], eventPredecessors: [nil], admissionClosure: .init(workspaceID: workspace,
                packageRelease: package, axisRegistryRelease: registry, planRevisions: planRelative ? [plan] : [], placementEvents: [placement]))
        let atomic = try fullReportAtomic(workspace: workspace, mutation: pose.mutationID,
            command: .applyPlacementPose(pose), images: pose.mutationPostImages)
        return try .init(completed: .init(snapshotID: C37PoseTestSupport.id(11_514), workspaceID: workspace,
            assetID: assetID, placementEpisodeID: placement.physicalEpisodeID,
            events: [event], capturedAt: event.recordedAt), selectedPlacementEventID: placement.id,
            admissions: [.init(envelope: atomic.envelope, receipt: atomic.receipt)])
    }

    private struct FullPostImageBasis<Value: Codable>: Codable {
        let identity: WorkspaceEntityIdentityV1; let revision: UInt64; let value: Value
    }
    private struct FullRecordPostImage: Codable {
        let record: V4BackupWorkflowRecordDTO; let requirementAssurance: RequirementAssuranceSnapshotV1?
    }
    private func fullReportImage<Value: Codable>(_ kind: WorkspaceEntityKindV1, id: UUID,
        revision: UInt64, value: Value) throws -> MutationPostImageV1 {
        let sha = try WorkspaceMutationCanonicalV1.sha256(FullPostImageBasis(
            identity: WorkspaceEntityIdentityV1(kind: kind, id: id), revision: revision, value: value))
        switch kind {
        case .workflowRecord: return .workflowRecord(id: id, revision: revision, semanticSHA256: sha)
        case .packet: return .packet(id: id, revision: revision, semanticSHA256: sha)
        case .report: return .report(id: id, revision: revision, semanticSHA256: sha)
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func fullReportStructuralOrigin(original: ReportOriginalPublicationV2, assetID: UUID,
        subject: CompletedWorkSubjectKeyV1) throws -> ReportAcceptedOriginV1 {
        let base = original.basis, s = base.snapshot
        let mutation = try C33TemporalEvidenceTestSupport.mutation(11_520)
        let record = try fullReportInput(base, assetID: assetID, revision: 2, step: "review",
            completed: true, mutationID: mutation.rawValue).sourceRecord
        let packet = PacketPayloadV1(id: s.packetID, schemaVersion: 1, stableRootID: s.stableRootID,
            currentRecordID: s.sourceRecordID, evaluationCounted: true, contentDeletedAt: nil, createdAt: s.snapshotCreatedAt)
        let report = ReportPayloadV1(id: s.reportID, schemaVersion: 1, packetID: s.packetID,
            sourceRecordID: s.sourceRecordID, snapshotSchemaVersion: s.snapshotSchemaVersion,
            snapshotRelativePath: "snapshots/\(s.reportID.uuidString.lowercased()).json",
            snapshotSHA256: try original.encoded().sha256, pdfState: ReportPDFState.pending.rawValue,
            pdfRelativePath: nil, pdfSHA256: nil, createdAt: s.snapshotCreatedAt, replacesReportID: nil)
        let payload = FinalizationPayloadV1(issueInsert: nil, issueTransition: nil, packetAfter: packet,
            packetBefore: nil, reportInsert: report, workflowRecordAfter: record)
        let digest = try FinalizationContractEncoderV1().encodePayload(payload).sha256
        let sourceBinding = FinalizationWriterSourceBindingV1(sourceRecordID: s.sourceRecordID,
            observationBasisV1Data: try ObservationAndTimeCodecV1.encode(XCTUnwrap(s.observationBasis)),
            temporalContextV1Data: try ObservationAndTimeCodecV1.encode(XCTUnwrap(s.temporalContext)),
            requirementAssurance: nil)
        let authority = FinalizationWriterAuthorityV1(workspaceID: base.workspaceID,
            generationID: C33TemporalEvidenceTestSupport.id(11_500), payload: payload, payloadSHA256: digest,
            snapshotRelativePath: report.snapshotRelativePath, snapshotSHA256: report.snapshotSHA256,
            contentDigests: [], sourceBinding: sourceBinding)
        let command = FinalizeCheckMutationV1(finalizationMutationID: mutation.rawValue, assetID: assetID,
            recordID: s.sourceRecordID, packetID: s.packetID, reportID: s.reportID, issueID: nil,
            semanticDigest: digest, contentDigests: [], writerAuthority: authority)
            let recordDTO = V4BackupWorkflowRecordDTO(
                id: record.id, schemaVersion: record.schemaVersion, assetID: record.assetID,
                packetID: record.packetID, issueID: record.issueID,
                parentRecordID: record.parentRecordID,
                recordRevisionRootID: record.recordRevisionRootID,
                revisesRecordID: record.revisesRecordID,
                evidenceSourceRecordID: record.evidenceSourceRecordID,
                revisionKind: record.revisionKind, stage: record.stage, state: record.state,
                draftStepKey: record.draftStepKey, startedAt: record.startedAt,
                completedAt: record.completedAt, observedAtUTC: record.observedAtUTC,
                timeZoneID: record.timeZoneID, utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate, localTime: record.localTime,
                afterDarkAcknowledgementKey: record.afterDarkAcknowledgementKey,
                afterDarkAcknowledgementCopy: record.afterDarkAcknowledgementCopy,
                afterDarkAcknowledgementVersion: record.afterDarkAcknowledgementVersion,
                afterDarkAcknowledgementAccepted: record.afterDarkAcknowledgementAccepted,
                safePositionAcknowledgementKey: record.safePositionAcknowledgementKey,
                safePositionAcknowledgementCopy: record.safePositionAcknowledgementCopy,
                safePositionAcknowledgementVersion: record.safePositionAcknowledgementVersion,
                safePositionAcknowledgementAccepted: record.safePositionAcknowledgementAccepted,
                packID: record.packID, packSchemaVersion: record.packSchemaVersion,
                packContentVersion: record.packContentVersion,
                pdfTemplateID: record.pdfTemplateID, pdfTemplateVersion: record.pdfTemplateVersion,
                outcomeKey: record.outcomeKey, couldNotVerifyKey: record.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
                workPerformedLocalDate: record.workPerformedLocalDate,
                workDescription: record.workDescription, note: record.note,
                finalizationMutationID: record.finalizationMutationID,
                observationBasisV1Data: sourceBinding.observationBasisV1Data,
                temporalContextV1Data: sourceBinding.temporalContextV1Data
            )
            let recordValue = FullRecordPostImage(
                record: recordDTO, requirementAssurance: nil
            )
            let packetValue = V4BackupPacketDTO(
                id: packet.id, schemaVersion: packet.schemaVersion,
                stableRootID: packet.stableRootID, currentRecordID: packet.currentRecordID,
                evaluationCounted: packet.evaluationCounted,
                contentDeletedAt: packet.contentDeletedAt, createdAt: packet.createdAt
            )
            let reportValue = V4BackupReportDTO(
                id: report.id, schemaVersion: report.schemaVersion, packetID: report.packetID,
                sourceRecordID: report.sourceRecordID,
                snapshotSchemaVersion: report.snapshotSchemaVersion,
                snapshotRelativePath: report.snapshotRelativePath,
                snapshotSHA256: report.snapshotSHA256, pdfState: report.pdfState,
                pdfRelativePath: report.pdfRelativePath, pdfSHA256: report.pdfSHA256,
                createdAt: report.createdAt, replacesReportID: report.replacesReportID
            )
        let images = try [
            fullReportImage(.workflowRecord, id: record.id, revision: 2, value: recordValue),
            fullReportImage(.packet, id: packet.id, revision: 1, value: packetValue),
            fullReportImage(.report, id: report.id, revision: 1, value: reportValue),
        ]
        let atomic = try fullReportAtomic(workspace: base.workspaceID, mutation: mutation,
            command: .finalizeCheck(command), images: images,
            additionalLocks: [.init(identity: WorkspaceEntityIdentityV1(kind: .asset, id: assetID), revision: 7)])
        return try .init(subject: subject, finalization: .init(envelopeData: atomic.envelope.canonicalData(),
            occurredAt: s.snapshotCreatedAt), receipt: atomic.receipt)
    }
}

extension V9_16SnapshotProjectionTests {
    @MainActor
    func testReportFullSourcePoseRetainsFourAtomicCommandFamiliesAndPredecessors() throws {
        let workspace = C37PoseTestSupport.workspace(90), assetID = C37PoseTestSupport.id(11_600)
        let root = try fullReportPose(workspace, assetID: assetID, planRelative: true, optional: true)
        let rebase = try fullReportRebasedPose(root)
        let moved = try fullReportMovedPose(root, hierarchy: false)
        let hierarchy = try fullReportMovedPose(root, hierarchy: true)
        XCTAssertEqual(root.admissions[0].envelope.commandKind, .applyPlacementPose)
        XCTAssertEqual(rebase.admissions[1].envelope.commandKind, .applyPlan)
        XCTAssertEqual(moved.admissions[1].envelope.commandKind, .applyAssetPlacementChange)
        XCTAssertEqual(hierarchy.admissions[1].envelope.commandKind, .applyLocationHierarchyChange)
        for source in [rebase, moved, hierarchy] {
            XCTAssertEqual(try source.history().count, 2)
            XCTAssertEqual(try source.history().first, root.completed.events.first)
            XCTAssertEqual(source.completed.events.first?.predecessor, root.completed.events.first?.reference)
            XCTAssertEqual(source.completed.events.first?.rootObservedAt, root.completed.events.first?.rootObservedAt)
            let leaf = try source.admissions[1].poseMutation()
            XCTAssertGreaterThan(source.admissions[1].receipt.postImages.count, try leaf.mutationPostImages.count)
            XCTAssertEqual(try source.projection().projection.history.count, 2)
            let bytes = try publicationExpectedBytes(source)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
            XCTAssertEqual(try decoder.decode(ReportPoseHistorySourceV1.self, from: bytes), source)
            XCTAssertThrowsError(try ReportPoseHistorySourceV1(completed: source.completed,
                selectedPlacementEventID: source.selectedPlacementEventID, admissions: [source.admissions[1]]))
            XCTAssertThrowsError(try ReportPoseHistorySourceV1(completed: source.completed,
                selectedPlacementEventID: source.selectedPlacementEventID,
                admissions: source.admissions + [source.admissions[0]]))
            XCTAssertThrowsError(try ReportPoseHistorySourceV1(completed: source.completed,
                selectedPlacementEventID: C37PoseTestSupport.id(11_699), admissions: source.admissions))
            let second = source.admissions[1]
            let narrowed = try fullReportAtomic(workspace: workspace, mutation: leaf.mutationID,
                command: second.envelope.command, images: leaf.mutationPostImages, sequence: 2)
            XCTAssertThrowsError(try ReportPoseAdmissionV1(envelope: narrowed.envelope, receipt: narrowed.receipt))
            XCTAssertThrowsError(try ReportPoseAdmissionV1(envelope: second.envelope, receipt: root.admissions[0].receipt))
        }
        // The complete atomic envelopes remain unchanged, including the plan
        // receipt and C35 asset/placement effects; they are never recast as a
        // newly accepted direct-pose command for serialization convenience.
        XCTAssertNotEqual(try rebase.admissions[1].envelope.canonicalData(),
            try root.admissions[0].envelope.canonicalData())
        for source in [moved, hierarchy] {
            let old = source.admissions[1]
            for sourceKind in [MutationSourceKindV1.localUser, .localRecovery] {
                let mismatch = try fullReportAtomic(workspace: workspace, mutation: old.envelope.mutationID,
                    command: old.envelope.command, images: old.receipt.postImages, sequence: 3, sourceKind: sourceKind)
                try mismatch.envelope.validate(); try mismatch.receipt.validate()
                XCTAssertThrowsError(try ReportPoseAdmissionV1(envelope: mismatch.envelope, receipt: mismatch.receipt))
            }
            let imported = try fullReportAtomic(workspace: workspace, mutation: old.envelope.mutationID,
                command: old.envelope.command, images: old.receipt.postImages, sequence: 3, sourceKind: .importedHistory)
            XCTAssertNotEqual(imported.envelope.expectedRevision, old.envelope.expectedRevision)
            XCTAssertEqual(imported.envelope.command, old.envelope.command)
            let preserved = try ReportPoseAdmissionV1(envelope: imported.envelope, receipt: imported.receipt)
            XCTAssertEqual(try preserved.poseMutation(), try old.poseMutation())
            let importedSource = try ReportPoseHistorySourceV1(completed: source.completed,
                selectedPlacementEventID: source.selectedPlacementEventID, admissions: [source.admissions[0], preserved])
            XCTAssertEqual(try importedSource.history(), try source.history())
        }
    }

    private func fullReportSuccessor(_ prior: AssetPoseEventV1, mutation: MutationIDV1, slot: Int,
        placement: AssetPlacementEventV1, pose: PlacementPoseV1, source: PoseObservationSourceV1) throws -> AssetPoseEventV1 {
        try .init(eventID: C37PoseTestSupport.id(slot), workspaceID: prior.workspaceID,
            assetID: prior.assetID, axisDescriptor: prior.axisDescriptor, placementEpisodeID: placement.physicalEpisodeID,
            placementEventID: placement.id, locationPathSnapshot: placement.pathSnapshot, pose: pose, source: source,
            rootObservationEventID: prior.rootObservationEventID, rootObservedAt: prior.rootObservedAt,
            predecessor: prior, revision: prior.revision + 1, mutationID: mutation,
            recordedBy: C37PoseTestSupport.actor(workspaceID: prior.workspaceID, slot: slot, responsibility: .recordedBy),
            occurredAt: prior.recordedAt.addingTimeInterval(1), recordedAt: prior.recordedAt.addingTimeInterval(2))
    }

    private func fullReportMovedPose(_ root: ReportPoseHistorySourceV1, hierarchy: Bool) throws -> ReportPoseHistorySourceV1 {
        let original = try root.admissions[0].poseMutation(), prior = try XCTUnwrap(original.events.first)
        let old = try XCTUnwrap(original.admissionClosure.placementEvents.first)
        let slot = hierarchy ? 11_630 : 11_620
        let mutation = try C37PoseTestSupport.mutation(slot)
        let path = try LocationPathSnapshotV1(siteID: C37PoseTestSupport.id(slot + 1), siteDisplay: "Moved site", nodes: [])
        let placement = try AssetPlacementEventV1(id: C37PoseTestSupport.id(slot + 2), workspaceID: prior.workspaceID,
            assetID: prior.assetID, siteID: path.siteID, locationNodeID: nil, predecessorEventID: old.id,
            source: hierarchy ? .hierarchyRebase : .manual, physicalEpisodeID: C37PoseTestSupport.episode(slot),
            continuity: .physicalMove, pathSnapshot: path, mutationID: mutation, occurredAt: prior.recordedAt.addingTimeInterval(1))
        let proposed = try C37PoseTestSupport.notObservedPose(descriptor: prior.axisDescriptor, reason: .physicalMoveReobservationRequired)
        let event = try fullReportSuccessor(prior, mutation: mutation, slot: slot + 3,
            placement: placement, pose: proposed, source: .placementCarryForward)
        let closure = try PlacementPoseAdmissionClosureV1(workspaceID: prior.workspaceID,
            packageRelease: original.admissionClosure.packageRelease, axisRegistryRelease: original.admissionClosure.axisRegistryRelease,
            planRevisions: [], placementEvents: [placement])
        let intent = try PosePlacementDispositionIntentV1(predecessor: prior.reference, proposedPose: proposed, disposition: .markNotObserved)
        let contribution = try PlacementChangeComponentContributionV1(componentID: "c37.report.move", componentVersion: 1,
            warnings: [], requiredContinuityReview: false, intentSHA256: intent.intentSHA256, poseDispositionIntents: [intent])
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: prior.workspaceID,
            generationID: C33TemporalEvidenceTestSupport.id(11_500), writerInstanceID: C33TemporalEvidenceTestSupport.id(11_501),
            workspaceRevision: 1, entityRevisions: [
                .init(identity: WorkspaceEntityIdentityV1(kind: .asset, id: prior.assetID), revision: 1),
                .init(identity: WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: placement.id), revision: 0),
                .init(identity: WorkspaceEntityIdentityV1(kind: .assetPoseEvent, id: prior.eventID), revision: prior.revision)])
        let basis = try AssetPlacementPreviewBasisV1(workspaceID: prior.workspaceID, expectedRevision: expected,
            assetID: prior.assetID, currentPlacement: old, proposedSiteID: path.siteID, proposedLocationNodeID: nil,
            proposedPath: path, source: placement.source, reviewedContinuity: .physicalMove)
        let plan = try AssetPlacementChangePlanV1(operationID: mutation.rawValue, mutationID: mutation,
            basis: basis, newEventID: placement.id, resultingPhysicalEpisodeID: placement.physicalEpisodeID,
            componentContributions: [contribution], poseEvents: [event], poseEventPredecessors: [prior], poseAdmissionClosure: closure)
        let command: WorkspaceCommandV1
        if hierarchy {
            let change = try LocationHierarchyChangePlanV1(operationID: mutation.rawValue, workspaceID: prior.workspaceID,
                expectedRevision: expected, beforeNodes: [], afterNodes: [], affectedAssetIDs: [prior.assetID],
                assetPathChanges: [.init(assetID: prior.assetID, beforePath: old.pathSnapshot, afterPath: path)],
                immutablePlacementReferencedNodeIDs: [], consumerImpact: .init(planIDs: [], referenceIDs: [],
                    openRoundIDs: [], scheduleIDs: [], reportConsumerIDs: []), assetBindingsChange: true,
                operationContinuityDisposition: nil, continuityByAssetID: [prior.assetID: .physicalMove])
            command = .applyLocationHierarchyChange(try .init(plan: change, placementChanges: [plan]))
        } else { command = .applyAssetPlacementChange(plan) }
        // Non-pose hashes are opaque at this pure report boundary. These are
        // structural fixtures derived from the full plan/event, not a claim of
        // accepted asset rows. The future writer witness must supply real rows.
        let images = try XCTUnwrap(plan.placementPoseMutation).mutationPostImages + [
            .asset(id: prior.assetID, revision: 2, semanticSHA256: plan.planSHA256),
            .assetPlacementEvent(id: placement.id, revision: 1, semanticSHA256: placement.eventSHA256)]
        let atomic = try fullReportAtomic(workspace: prior.workspaceID, mutation: mutation, command: command, images: images, sequence: 2)
        return try .init(completed: .init(snapshotID: C37PoseTestSupport.id(slot + 4), workspaceID: prior.workspaceID,
            assetID: prior.assetID, placementEpisodeID: placement.physicalEpisodeID, events: [event], capturedAt: event.recordedAt),
            selectedPlacementEventID: placement.id, admissions: root.admissions + [.init(envelope: atomic.envelope, receipt: atomic.receipt)])
    }

    private func fullReportRebasedPose(_ root: ReportPoseHistorySourceV1) throws -> ReportPoseHistorySourceV1 {
        let original = try root.admissions[0].poseMutation(), prior = try XCTUnwrap(original.events.first)
        let placement = try XCTUnwrap(original.admissionClosure.placementEvents.first)
        let old = try XCTUnwrap(original.admissionClosure.planRevisions.first)
        let mutation = try C37PoseTestSupport.mutation(11_640)
        let new = try PlanRevisionV1(planRevisionID: C37PoseTestSupport.id(11_641), workspaceID: prior.workspaceID,
            planDocument: old.planDocument, contentBinding: old.contentBinding, pages: old.pages, spatialFrames: old.spatialFrames,
            state: .released, predecessor: old, revision: 2, mutationID: mutation, recordedBy: old.recordedBy,
            recordedAt: old.recordedAt.addingTimeInterval(10))
        let transform = try PlanAffineTransformV1(m11: 1_000_000_000, m12: 0, m21: 0, m22: 1_000_000_000, tx: 0, ty: 0)
        let frame = PlanRelativePoseFrameBindingV1(planRevision: try new.reference, pageID: old.pages[0].pageID,
            spatialFrameID: old.spatialFrames[0].frameID, acceptedTransformSHA256: transform.transformSHA256)
        let event = try fullReportSuccessor(prior, mutation: mutation, slot: 11_642, placement: placement,
            pose: C37PoseTestSupport.observedPose(descriptor: prior.axisDescriptor, referenceFrame: .planRelative(frame)), source: .planRebase)
        let effects = try PlacementPoseMutationV1(workspaceID: prior.workspaceID, mutationID: mutation,
            events: [event], eventPredecessors: [prior], admissionClosure: .init(workspaceID: prior.workspaceID,
                packageRelease: original.admissionClosure.packageRelease, axisRegistryRelease: original.admissionClosure.axisRegistryRelease,
                planRevisions: [new], placementEvents: [placement]))
        let component = PoseFrameRebaseComponentV1(policy: try .init(), currentPoseEvents: { _, _ in [] })
        let registry = try PlanRebaseComponentRegistryV1(components: [component])
        let preview = try RebasePreviewV1(previewID: C37PoseTestSupport.id(11_643), workspaceID: prior.workspaceID,
            oldRevision: old.reference, newRevision: new.reference, transform: transform,
            registrySHA256: registry.registrySHA256, registryVersion: registry.registryVersion,
            componentDescriptors: registry.descriptors, contributions: [component.reviewedContribution(poseEffects: effects)],
            expectedRevision: old.revision, generatedAt: new.recordedAt)
        let reviewer = try C37PoseTestSupport.actor(workspaceID: prior.workspaceID, slot: 11_644, responsibility: .reviewedBy)
        let commandBasis = try PlanRebaseCommandBasisV1(workspaceID: prior.workspaceID, mutationID: mutation,
            preview: preview, newRevision: new, predecessorRevision: old, placements: [], predecessorPlacements: [],
            receiptID: C37PoseTestSupport.id(11_645), predecessorReceipt: nil, reviewedBy: reviewer,
            recordedAt: new.recordedAt, poseEffects: effects)
        let receipt = try RebaseReceiptV1(receiptID: commandBasis.receiptID, preview: preview, decision: .approved,
            resultingRevision: new.reference, resultingPlacementsSHA256: PlanRebasePreviewBuilderV1.placementSetSHA256([]),
            canonicalPlanMutationSHA256: commandBasis.canonicalSHA256, reviewedBy: reviewer, recordedAt: new.recordedAt,
            revision: 1, mutationID: mutation)
        let plan = try PlanMutationV1(workspaceID: prior.workspaceID, mutationID: mutation,
            payload: .applyRebase(newRevision: new, predecessorRevision: old, placements: [], predecessorPlacements: [],
                receipt: receipt, predecessorReceipt: nil, poseEffects: effects))
        let atomic = try fullReportAtomic(workspace: prior.workspaceID, mutation: mutation,
            command: .applyPlan(plan), images: plan.mutationPostImages, sequence: 2)
        return try .init(completed: .init(snapshotID: C37PoseTestSupport.id(11_646), workspaceID: prior.workspaceID,
            assetID: prior.assetID, placementEpisodeID: placement.physicalEpisodeID, events: [event], capturedAt: event.recordedAt),
            selectedPlacementEventID: placement.id, admissions: root.admissions + [.init(envelope: atomic.envelope, receipt: atomic.receipt)])
    }
}

extension V9_16SnapshotProjectionTests {
    @MainActor
    func testReportPoseProjectionPreservesPresentComponentsAndExplicitUnknownUncertainty() throws {
        let workspace = C37PoseTestSupport.workspace(91)
        let assetID = C37PoseTestSupport.id(11_700)
        // These are domain-valid immutable events, not accepted writer receipts.
        // Expected labels are an independent closed table from frozen C37 law.
        let cases: [(String, Bool, Bool, Bool, Bool, Bool, C37PoseObservationStateV1)] = [
            ("azimuth-known", false, false, false, false, false, .observed),
            ("azimuth-unknown", false, true, false, false, false, .uncertaintyUnknown),
            ("two-axis-known", true, false, false, false, false, .observed),
            ("two-axis-horizontal-unknown", true, true, false, false, false, .uncertaintyUnknown),
            ("two-axis-vertical-unknown", true, false, true, false, false, .uncertaintyUnknown),
            ("two-axis-both-unknown", true, true, true, false, false, .uncertaintyUnknown),
            ("manual-known", false, false, false, true, false, .manualFallback),
            ("manual-unknown", true, true, true, true, false, .manualFallback),
            ("not-observed", false, false, false, false, true, .notObserved),
        ]
        for (index, item) in cases.enumerated() {
            let (name, twoAxis, unknownHorizontal, unknownVertical, manual, notObserved, expectedState) = item
            let slot = 11_710 + index * 10
            let axis = try C37PoseTestSupport.descriptor("projection-\(index)",
                required: twoAxis ? .azimuthAndElevation : .azimuthOnly, observationRequirement: .optional)
            let knownHorizontal = PoseUncertaintyV1.known(try .init(kind: .horizontalUncertainty, milliDegrees: 3))
            let knownVertical = PoseUncertaintyV1.known(try .init(kind: .verticalUncertainty, milliDegrees: 4))
            let pose: PlacementPoseV1
            if notObserved {
                pose = try C37PoseTestSupport.notObservedPose(descriptor: axis, reason: .sourceUnavailable)
            } else {
                pose = try .init(disposition: .observed, referenceFrame: .trueBearing,
                    azimuth: .init(kind: .azimuth, milliDegrees: 12_345),
                    elevation: twoAxis ? .init(kind: .elevation, milliDegrees: -6_000) : nil,
                    horizontalUncertainty: unknownHorizontal ? .unknown : knownHorizontal,
                    verticalUncertainty: twoAxis ? (unknownVertical ? .unknown : knownVertical) : nil,
                    descriptor: axis)
            }
            let original = try C37PoseTestSupport.poseEvent(workspaceID: workspace, assetID: assetID,
                descriptor: axis, eventID: C37PoseTestSupport.id(slot), pose: pose)
            let selected: AssetPoseEventV1
            if manual {
                selected = original
            } else {
                selected = try C37PoseTestSupport.poseEvent(workspaceID: workspace,
                    assetID: assetID, descriptor: axis, eventID: C37PoseTestSupport.id(slot + 1),
                    pose: pose, predecessor: original)
            }
            let events = manual ? [original] : [original, selected]
            try events.forEach { try $0.validateIntrinsic() }
            let projection = try C37PlacementPoseReportProjectionV1(workspaceID: workspace,
                assetID: assetID, events: events, capturedAt: selected.recordedAt)
            let leaf = try XCTUnwrap(projection.history.last)
            XCTAssertEqual(leaf.observationState, expectedState, name)
            XCTAssertEqual(leaf.azimuthMilliDegrees, notObserved ? nil : 12_345, name)
            XCTAssertEqual(leaf.elevationMilliDegrees, twoAxis && !notObserved ? -6_000 : nil, name)
            XCTAssertEqual(leaf.horizontalUncertaintyMilliDegrees, notObserved || unknownHorizontal ? nil : 3, name)
            XCTAssertEqual(leaf.verticalUncertaintyMilliDegrees, !twoAxis || notObserved || unknownVertical ? nil : 4, name)
            XCTAssertEqual(leaf.horizontalUncertaintyState, notObserved || unknownHorizontal ? .unknown : .known, name)
            XCTAssertEqual(leaf.verticalUncertaintyState, !twoAxis || notObserved || unknownVertical ? .unknown : .known, name)
            XCTAssertEqual(projection.currentTipReferences, [selected.reference], name)
            XCTAssertEqual(projection.history.map(\.eventID), events.map(\.eventID), name)
            try projection.validate()
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
            XCTAssertEqual(try decoder.decode(C37PlacementPoseReportProjectionV1.self,
                from: publicationExpectedBytes(projection)), projection, name)

            func rejectRehashed(_ changes: [String: Any], _ reason: String) throws {
                var leafObject = try XCTUnwrap(try publicationTypedObject(leaf) as? [String: Any])
                for (key, value) in changes { leafObject[key] = value }
                let changedLeaf = try decoder.decode(C37PoseHistoryProjectionV1.self,
                    from: JSONSerialization.data(withJSONObject: leafObject, options: [.sortedKeys]))
                var history = projection.history; history[history.count - 1] = changedLeaf
                // Rehash the complete otherwise unchanged outer projection, so
                // denial proves semantic validation instead of stale digest.
                let basis = PoseProjectionExpectedBasis(projection, history: history)
                let hashEncoder = JSONEncoder()
                hashEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                hashEncoder.dateEncodingStrategy = .millisecondsSince1970
                let digest = SHA256.hash(data: try hashEncoder.encode(basis))
                    .map { String(format: "%02x", $0) }.joined()
                var outer = try XCTUnwrap(try publicationTypedObject(projection) as? [String: Any])
                outer["history"] = try history.map { try publicationTypedObject($0) }
                outer["projectionSHA256"] = digest
                let hostile = try decoder.decode(C37PlacementPoseReportProjectionV1.self,
                    from: JSONSerialization.data(withJSONObject: outer, options: [.sortedKeys]))
                XCTAssertEqual(hostile.projectionSHA256, digest, reason)
                XCTAssertThrowsError(try hostile.validate(), "\(name): \(reason)") { error in
                    XCTAssertEqual(error as? C37PoseReportProjectionFailureV1, .invalidValue)
                }
            }
            for wrongState in C37PoseObservationStateV1.allCases where wrongState != expectedState {
                try rejectRehashed(["observationState": wrongState.rawValue], "wrong observation label")
            }
            try rejectRehashed(["horizontalUncertaintyState": "KNOWN", "horizontalUncertaintyMilliDegrees": NSNull()], "known without value")
            try rejectRehashed(["horizontalUncertaintyState": "UNKNOWN", "horizontalUncertaintyMilliDegrees": 3], "unknown with value")
            if !twoAxis {
                try rejectRehashed(["verticalUncertaintyState": "KNOWN", "verticalUncertaintyMilliDegrees": 4], "absent vertical axis with value")
            }
            if notObserved {
                try rejectRehashed(["azimuthMilliDegrees": 12_345], "not observed with angle")
                try rejectRehashed(["notObservedReason": NSNull()], "not observed without reason")
            }
        }
    }

    private struct PoseProjectionExpectedBasis: Encodable {
        let schemaVersion: Int
        let projectionVersion: String
        let workspaceID: WorkspaceID
        let assetID: UUID
        let currentTipReferences: [AssetPoseEventReferenceV1]
        let history: [C37PoseHistoryProjectionV1]
        let capturedAt: Date
        let historyFrozen: Bool
        let rebasePreviewIsNotApplied: Bool
        let sensorInputAllowed: Bool
        let networkInputAllowed: Bool

        init(_ value: C37PlacementPoseReportProjectionV1, history: [C37PoseHistoryProjectionV1]) {
            schemaVersion = value.schemaVersion; projectionVersion = value.projectionVersion
            workspaceID = value.workspaceID; assetID = value.assetID
            currentTipReferences = value.currentTipReferences; self.history = history
            capturedAt = value.capturedAt; historyFrozen = value.historyFrozen
            rebasePreviewIsNotApplied = value.rebasePreviewIsNotApplied
            sensorInputAllowed = value.sensorInputAllowed; networkInputAllowed = value.networkInputAllowed
        }
    }
}

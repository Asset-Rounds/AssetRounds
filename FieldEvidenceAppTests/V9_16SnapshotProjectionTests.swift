import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_16SnapshotProjectionTests: XCTestCase {
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

import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V9_69ShopProfileOpenHandoffTests: XCTestCase {
    func testV23P04C04G01DeterministicProfilePresetAndConfirmationBytes() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(fixture.profile.activation, .off)
        XCTAssertEqual(fixture.profile.packaging, .combinedArchive)

        let firstWrite = try ShopReportProfileMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 0,
            mutationID: fixture.profile.mutationID,
            profile: fixture.profile
        )
        XCTAssertEqual(try firstWrite.affectedIdentity, try firstWrite.concurrencyIdentity)

        let firstBytes = try ShopReportProfileCanonicalCodecV1.encode(fixture.profile)
        XCTAssertEqual(firstBytes, try ShopReportProfileCanonicalCodecV1.encode(fixture.profile))
        XCTAssertEqual(try ShopReportProfileCanonicalCodecV1.decode(ShopReportProfileV1.self, from: firstBytes), fixture.profile)

        let customer = try makeProfile(
            workspaceID: fixture.workspaceID,
            actor: fixture.actor,
            registry: fixture.registry,
            profileID: fixture.profile.profileID,
            predecessor: fixture.profile,
            revision: 2,
            mutationID: id(14),
            activation: .on,
            packaging: .separateFiles,
            audience: .customerSafe,
            recordedAt: Self.fixedDate.addingTimeInterval(1)
        )
        try customer.validateSuccessor(of: fixture.profile, sectionRegistry: fixture.registry)
        XCTAssertNotEqual(try ShopReportProfileCanonicalCodecV1.encode(customer), firstBytes)
        XCTAssertNotEqual(customer.profileSHA256, fixture.profile.profileSHA256)
    }

    func testV23P04C04A01CustomerSafePackagingAndAccessibleOutputs() throws {
        let fixture = try makeFixture(activation: .on, packaging: .separateFiles)
        let frontier = try ShopReportProfileLifecycleAdapterV1.freeze(fixture.profile, sectionRegistry: fixture.registry)
        let artifacts = try fixture.artifacts.map { try ShopOpenEvidenceArtifactV1(format: $0.format, bytes: $0.bytes) }

        XCTAssertEqual(frontier, try fixture.profile.reference)
        XCTAssertEqual(fixture.profile.packaging, .separateFiles)
        XCTAssertEqual(artifacts.map(\.format), [.formulaSafeCSV, .openJSON, .pdf, .structuredText])
        XCTAssertFalse(fixture.artifacts.contains(where: { $0.format == .manifest }))
        XCTAssertFalse(artifacts.contains(where: { $0.format == .manifest }))
        XCTAssertTrue(artifacts.allSatisfy { $0.sha256 == KernelCanonicalHashV1.sha256($0.bytes) })
        XCTAssertEqual(fixture.accessibleOutput.sha256, KernelCanonicalHashV1.sha256(fixture.accessibleOutput.bytes))
        XCTAssertFalse(String(decoding: fixture.accessibleOutput.bytes, as: UTF8.self).contains("INTERNAL-CANARY"))
        XCTAssertFalse(String(decoding: fixture.accessibleOutput.bytes, as: UTF8.self).contains("CUSTOMER-CANARY"))

        let blocked = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: fixture.card,
            policy: fixture.profile.evidenceDetailProfile.audiencePrivacyPolicy,
            semanticText: "customer-safe summary",
            composedOutput: Data("CONTACT-CANARY https://internal.invalid/customer".utf8),
            detectorID: ShopReportProfileLifecycleAdapterV1.detectorID,
            detectorVersion: ShopReportProfileLifecycleAdapterV1.detectorVersion
        )
        XCTAssertEqual(blocked.disposition, .blocked)

        let csv = try ShopReportProfileLifecycleAdapterV1.formulaSafeCSV(rows: [["title", "=SUM(A1:A2)"], ["asset", "+unsafe"]])
        XCTAssertEqual(String(decoding: csv, as: UTF8.self), "\"title\",\"'=SUM(A1:A2)\"\r\n\"asset\",\"'+unsafe\"\r\n")
        for formula in ["\t=TAB", "\u{00A0}=NBSP", "\u{FEFF}=BOM", "\u{2003}=UNICODE"] {
            let guarded = try ShopReportProfileLifecycleAdapterV1.formulaSafeCSV(rows: [[formula]])
            XCTAssertEqual(String(decoding: guarded, as: UTF8.self), "\"'\(formula)\"\r\n")
        }
    }

    func testV23P04C04H01RejectsCorruptStaleUnsafeAndSecondRendererInputs() throws {
        let fixture = try makeFixture()
        let canonical = try ShopReportProfileCanonicalCodecV1.encode(fixture.profile)
        XCTAssertThrowsError(try ShopReportProfileCanonicalCodecV1.decode(ShopReportProfileV1.self, from: canonical + Data(" ".utf8)))

        var unknownKey = try XCTUnwrap(JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        unknownKey["secondRenderer"] = "remote active content script macro path traversal"
        let unknownBytes = try JSONSerialization.data(withJSONObject: unknownKey, options: [.sortedKeys])
        XCTAssertThrowsError(try ShopReportProfileCanonicalCodecV1.decode(ShopReportProfileV1.self, from: unknownBytes))
        unknownKey["manifestArtifact"] = "caller-supplied manifest tamper reorder omission"
        let manifestInjection = try JSONSerialization.data(withJSONObject: unknownKey, options: [.sortedKeys])
        XCTAssertThrowsError(try ShopReportProfileCanonicalCodecV1.decode(ShopReportProfileV1.self, from: manifestInjection))
        XCTAssertThrowsError(try ShopReportProfileMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: 1,
            mutationID: fixture.profile.mutationID,
            profile: fixture.profile
        ))
        XCTAssertThrowsError(try ShopReportProfileLifecycleAdapterV1.freeze(fixture.profile, sectionRegistry: fixture.registry))
        XCTAssertThrowsError(try ShopReportProfileLifecycleAdapterV1.formulaSafeCSV(rows: [[""]]))
        XCTAssertThrowsError(try ShopReportProfileLifecycleAdapterV1.formulaSafeCSV(rows: Array(repeating: ["shape", "overflow"], count: ShopReportProfileLifecycleAdapterV1.maximumCSVRows + 1)))
        XCTAssertThrowsError(try ShopReportProfileLifecycleAdapterV1.formulaSafeCSV(rows: [["one"], ["two", "three"]]))
        XCTAssertThrowsError(try DeterministicPDFRendererV1.reopen(Data("%PDF-1.4\n/JavaScript /Launch /EmbeddedFile /OpenAction /RichMedia /XFA https://remote.invalid\n%%EOF".utf8)))
        XCTAssertThrowsError(try DeterministicOpenJSONRendererV1.reopen(Data("{\"activeContent\":true}".utf8)))
        XCTAssertThrowsError(try DeterministicOpenJSONRendererV1.reopen(Data([0xFF, 0xFE, 0x00])))
        XCTAssertThrowsError(try DeterministicOpenJSONRendererV1.reopenStructuredText(Data("<script>embedded</script> https://remote.invalid ../path".utf8)))
        XCTAssertThrowsError(try ShopReportProfileLifecycleAdapterV1.prepareBulk(Array(repeating: { throw ShopReportProfileFailureV1.limitExceeded }, count: ShopReportProfileLifecycleAdapterV1.maximumBulkHandoffs + 1)))

        for formula in ["=ASCII", "+ASCII", "-ASCII", "@ASCII"] {
            let csv = try ShopReportProfileLifecycleAdapterV1.formulaSafeCSV(rows: [[formula]])
            XCTAssertEqual(String(decoding: csv, as: UTF8.self), "\"'\(formula)\"\r\n")
        }
        XCTAssertThrowsError(try ShopReportBrandV1(shopDisplayName: String(repeating: "x", count: ShopReportProfileLimitsV1.maximumTextBytes + 1)))
    }

    func testV23P04C04I01InterruptionLeavesZeroOrRecoverableCanonicalEffect() throws {
        let fixture = try makeFixture(activation: .on)
        let originalRow = try ShopReportProfileRowV1(fixture.profile)
        XCTAssertEqual(try originalRow.value(), fixture.profile)
        XCTAssertEqual(try ShopReportProfileLifecycleAdapterV1.freeze(fixture.profile, sectionRegistry: fixture.registry), try fixture.profile.reference)

        XCTAssertThrowsError(try ShopReportProfileLifecycleAdapterV1.prepareBulk([]))
        XCTAssertThrowsError(try ShopReportProfileLifecycleAdapterV1.prepareBulk([
            { throw ShopReportProfileFailureV1.profileMismatch }
        ]))
        XCTAssertEqual(try originalRow.value(), fixture.profile)
    }

    func testV23P04C04R01RestoreCloneForkAndHistoricExportImmutability() throws {
        let fixture = try makeFixture(activation: .on)
        let archivedBytes = try ShopReportProfileCanonicalCodecV1.encode(fixture.profile)
        let archivedRow = try ShopReportProfileRowV1(fixture.profile)
        let restored = try archivedRow.value()
        XCTAssertEqual(try ShopReportProfileCanonicalCodecV1.encode(restored), archivedBytes)

        let successor = try makeProfile(
            workspaceID: fixture.workspaceID,
            actor: fixture.actor,
            registry: fixture.registry,
            profileID: fixture.profile.profileID,
            predecessor: fixture.profile,
            revision: 2,
            mutationID: id(15),
            activation: .on,
            packaging: .combinedArchive,
            audience: .customerSafe,
            recordedAt: Self.fixedDate.addingTimeInterval(2)
        )
        try successor.validateSuccessor(of: restored, sectionRegistry: fixture.registry)
        XCTAssertEqual(try ShopReportProfileCanonicalCodecV1.encode(restored), archivedBytes)
        XCTAssertNotEqual(successor.profileSHA256, restored.profileSHA256)
        XCTAssertThrowsError(try successor.validateSuccessor(of: successor, sectionRegistry: fixture.registry))
    }

    @MainActor
    func testShopProfileSaveExactRetryReturnsOriginalReceipt() throws {
        let harness = try makeSaveRetryHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let mutation = try profileMutation(harness.fixture.profile)
        let first = try harness.coordinator.save(mutation)
        let revision = try harness.sessions.workspaceWriter.currentRevision()
        let snapshot = try saveRetrySnapshot(harness.session.modelContext)
        XCTAssertEqual(snapshot.map(\.count), [1, 1, 1])

        XCTAssertEqual(try harness.coordinator.save(mutation), first)
        XCTAssertEqual(try harness.sessions.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try saveRetrySnapshot(harness.session.modelContext), snapshot)
    }

    @MainActor
    func testShopProfileSaveHistoricExactRetryAfterSuccessorReturnsOriginalReceipt() throws {
        let harness = try makeSaveRetryHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let original = try profileMutation(harness.fixture.profile)
        let first = try harness.coordinator.save(original)
        let successor = try retrySuccessor(harness.fixture, mutationID: id(91))
        _ = try harness.coordinator.save(profileMutation(successor))
        let revision = try harness.sessions.workspaceWriter.currentRevision()
        let snapshot = try saveRetrySnapshot(harness.session.modelContext)
        XCTAssertEqual(snapshot.map(\.count), [2, 2, 2])

        XCTAssertEqual(try harness.coordinator.save(original), first)
        XCTAssertEqual(try harness.coordinator.current(profileID: successor.profileID), successor)
        XCTAssertEqual(try harness.sessions.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try saveRetrySnapshot(harness.session.modelContext), snapshot)
    }

    @MainActor
    func testShopProfileSaveDivergentMutationReuseRejectsWithoutChanges() throws {
        let harness = try makeSaveRetryHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        _ = try harness.coordinator.save(profileMutation(harness.fixture.profile))
        // Reusing a mutation ID for changed content fails both the coordinator
        // successor rule and the writer's independent durable receipt check.
        let divergent = try retrySuccessor(
            harness.fixture, mutationID: harness.fixture.profile.mutationID.rawValue
        )
        let revision = try harness.sessions.workspaceWriter.currentRevision()
        let snapshot = try saveRetrySnapshot(harness.session.modelContext)

        XCTAssertThrowsError(try harness.coordinator.save(profileMutation(divergent)))
        XCTAssertThrowsError(try harness.sessions.workspaceWriter.commitShopReportProfile(
            profileMutation(divergent)
        )) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .invalidReceipt)
        }
        XCTAssertEqual(try harness.sessions.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try saveRetrySnapshot(harness.session.modelContext), snapshot)
    }

    @MainActor
    func testShopProfileSaveNewStaleMutationRejectsWithoutChanges() throws {
        let harness = try makeSaveRetryHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        _ = try harness.coordinator.save(profileMutation(harness.fixture.profile))
        let successor = try retrySuccessor(harness.fixture, mutationID: id(91))
        _ = try harness.coordinator.save(profileMutation(successor))
        let stale = try retrySuccessor(harness.fixture, mutationID: id(92))
        let revision = try harness.sessions.workspaceWriter.currentRevision()
        let snapshot = try saveRetrySnapshot(harness.session.modelContext)

        XCTAssertThrowsError(try harness.coordinator.save(profileMutation(stale)))
        XCTAssertThrowsError(try harness.sessions.workspaceWriter.commitShopReportProfile(
            profileMutation(stale)
        )) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        XCTAssertEqual(try harness.sessions.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try saveRetrySnapshot(harness.session.modelContext), snapshot)
    }

    @MainActor
    private func makeSaveRetryHarness() throws -> (
        directory: URL,
        session: StoreGenerationSession,
        sessions: StoreSessionCoordinator,
        coordinator: ShopReportProfileCoordinatorV1,
        fixture: Fixture
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("C04-save-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = try StoreGenerationFactory(applicationSupportURL: directory).openOrBootstrapCurrent()
        let sessions = try StoreSessionCoordinator(validatingSession: session)
        let fixture = try makeFixture(workspaceOverride: session.workspaceID)
        let coordinator = try ShopReportProfileCoordinatorV1(
            workspaceID: session.workspaceID,
            sectionRegistry: fixture.registry,
            reader: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            writer: sessions.workspaceWriter
        )
        return (directory, session, sessions, coordinator, fixture)
    }

    private func profileMutation(_ profile: ShopReportProfileV1) throws -> ShopReportProfileMutationV1 {
        try ShopReportProfileMutationV1(
            workspaceID: profile.workspaceID,
            expectedRevision: profile.revision - 1,
            mutationID: profile.mutationID,
            profile: profile
        )
    }

    private func retrySuccessor(_ fixture: Fixture, mutationID: UUID) throws -> ShopReportProfileV1 {
        try makeProfile(
            workspaceID: fixture.workspaceID, actor: fixture.actor, registry: fixture.registry,
            profileID: fixture.profile.profileID, predecessor: fixture.profile, revision: 2,
            mutationID: mutationID, activation: .on, packaging: .separateFiles,
            audience: .customerSafe, recordedAt: Self.fixedDate.addingTimeInterval(1)
        )
    }

    @MainActor
    private func saveRetrySnapshot(_ context: ModelContext) throws -> [[Data]] {
        let receipts = try context.fetch(FetchDescriptor<MutationReceiptRow>())
        let values: [[Data]] = [
            try context.fetch(FetchDescriptor<ShopReportProfileRowV1>()).map {
                try ShopReportProfileCanonicalCodecV1.encode($0.value())
            },
            receipts.map(\.receiptData),
            receipts.map(\.envelopeData)
        ]
        return values.map { $0.sorted { $0.lexicographicallyPrecedes($1) } }
    }

    private struct Fixture {
        let workspaceID: WorkspaceID
        let actor: ActorSnapshotV1
        let registry: ReportSectionRegistryV1
        let profile: ShopReportProfileV1
        let binding: FinalizedReportProfileBindingV1
        let card: EvidenceDetailCardV1
        let artifacts: [ShopReportProfileLifecycleAdapterV1.ArtifactInput]
        let accessibleTree: AccessibleDocumentSemanticTreeV1
        let accessibleAssessment: AccessibleDocumentAssessmentReceiptV1
        let accessibleOutput: AccessibleDocumentRenderOutputV1
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_788_132_800)

    private func makeFixture(
        activation: ShopReportProfileActivationV1 = .off,
        packaging: ShopOpenEvidencePackagingV1 = .combinedArchive,
        workspaceOverride: WorkspaceID? = nil
    ) throws -> Fixture {
        let workspaceID = workspaceOverride ?? WorkspaceID(rawValue: id(1))
        let actorReference = try LocalActorReferenceV1(actorReferenceID: id(2), workspaceID: workspaceID, displayName: "C04 recorder")
        let actor = try ActorSnapshotV1(snapshotID: id(3), workspaceID: workspaceID, actor: actorReference, responsibility: .recordedBy, displayNameAtTime: actorReference.displayName, capturedAt: Self.fixedDate)
        let formats: [ReportProjectionFormatV1] = [.formulaSafeCSV, .openJSON, .pdf, .structuredText]
        let sections = try [
            ReportSectionDefinitionV1(sectionID: "summary", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 0),
            ReportSectionDefinitionV1(sectionID: "evidence", version: 1, required: true, supportedFormats: formats, privacyClass: .audienceSafe, requiresHeading: true, requiresTextAlternative: true, order: 1),
            ReportSectionDefinitionV1(sectionID: "limitations", version: 1, required: true, supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true, requiresTextAlternative: true, order: 2)
        ]
        let registry = try ReportSectionRegistryV1(registryID: "c04-registry", registryVersion: 1, sections: sections)
        let profile = try makeProfile(workspaceID: workspaceID, actor: actor, registry: registry, profileID: id(4), predecessor: nil, revision: 1, mutationID: id(5), activation: activation, packaging: packaging, audience: .customerSafe, recordedAt: Self.fixedDate)
        let binding = try finalizedBinding(workspaceID: workspaceID, registry: registry, profile: profile)
        let card = try evidenceCard(workspaceID: workspaceID, profile: profile)
        let artifacts = try artifactInputs()
        let accessibleOutput = try AccessibleDocumentRenderOutputV1(bytes: Data("semantic customer-safe output".utf8), mediaType: "text/plain", rendererID: "c04-accessibility-renderer", rendererVersion: profile.rendererVersion)
        let accessibility = try accessibleFixture(workspaceID: workspaceID, actor: actor, profile: profile, binding: binding, sourceSnapshotSHA256: String(repeating: "c", count: 64), output: accessibleOutput)
        return Fixture(workspaceID: workspaceID, actor: actor, registry: registry, profile: profile, binding: binding, card: card, artifacts: artifacts, accessibleTree: accessibility.tree, accessibleAssessment: accessibility.assessment, accessibleOutput: accessibleOutput)
    }

    private func makeProfile(workspaceID: WorkspaceID, actor: ActorSnapshotV1, registry: ReportSectionRegistryV1, profileID: UUID, predecessor: ShopReportProfileV1?, revision: UInt64, mutationID: UUID, activation: ShopReportProfileActivationV1, packaging: ShopOpenEvidencePackagingV1, audience: ReportAudienceV1, recordedAt: Date) throws -> ShopReportProfileV1 {
        let layout = try ReportLayoutProfileV1(profileID: "c04-customer", profileRelease: 1, audience: audience, detail: .complete, sectionIDs: ["summary", "evidence", "limitations"], mediaLayout: .standardGrid, orientation: .portrait, localeIdentifier: "en_US", unitsProfileID: "units-si-v1", displayProfileID: "display-v1", registry: registry)
        let exportPackaging: ReportPackagingV1 = packaging == .combinedArchive ? .combined : .separatePerWorkItem
        let export = try ExportProfileV1(exportProfileID: "c04-export", exportProfileRelease: 1, formats: [.formulaSafeCSV, .openJSON, .pdf, .structuredText], packaging: exportPackaging, privacyTransformID: "customer-safe-v1", maximumMediaItems: 16, maximumArchiveBytes: 1_024_000)
        let policy = try AudiencePrivacyPolicyV1(policyID: "c04-policy", policyVersion: 1, audience: audience, prohibitedCanaries: ["BRAND-INTERNAL-CANARY", "C:\\private\\customer", "CAPABILITY-CANARY", "CONTACT-CANARY", "COST-CANARY", "CUSTOMER-CANARY", "DIAGNOSTIC-CANARY", "INTERNAL-CANARY", "RAW-OCR-CANARY", "VERIFICATION-CANARY", "https://internal.invalid/customer"])
        let detail = try EvidenceDetailCardProfileV1(profileID: "c04-detail", profileRelease: 1, audience: audience, outputScopeID: "c04-output", privacyTransformID: "customer-safe-v1", privacyTransformVersion: 1, markupProfileID: "c04-markup", markupProfileVersion: 1, localeIdentifier: "en_US", displayProfileID: "display-v1", rendererVersion: ReportSemanticProjectorV1.rendererVersion, audiencePrivacyPolicy: policy, includedFieldIDs: ["service_request", "service_status"], limitationsText: "Evidence detail does not verify capture time, location, or person.")
        return try ShopReportProfileV1(workspaceID: workspaceID, profileID: profileID, predecessor: predecessor, revision: revision, mutationID: try MutationIDV1(rawValue: mutationID), activation: activation, brand: try ShopReportBrandV1(shopDisplayName: "C04 Shop", orderedBrandLines: ["Customer safe"], accentHexRGB: "#204060"), reportLayoutProfile: layout, exportProfile: export, evidenceDetailProfile: detail, sectionRegistry: registry, rendererVersion: ReportSemanticProjectorV1.rendererVersion, packaging: packaging, recordedBy: actor, recordedAt: recordedAt)
    }

    private func finalizedBinding(workspaceID: WorkspaceID, registry: ReportSectionRegistryV1, profile: ShopReportProfileV1) throws -> FinalizedReportProfileBindingV1 {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try FinalizedReportProfileBindingV1(workspaceID: workspaceID.rawValue.uuidString.lowercased(), snapshotID: "c04-snapshot", outputScopeID: "c04-output", reportProfileID: profile.reportLayoutProfile.profileID, reportProfileRelease: profile.reportLayoutProfile.profileRelease, reportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(profile.reportLayoutProfile)), exportProfileID: profile.exportProfile.exportProfileID, exportProfileRelease: profile.exportProfile.exportProfileRelease, exportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(profile.exportProfile)), sectionRegistryID: registry.registryID, sectionRegistryVersion: registry.registryVersion, sectionRegistrySHA256: KernelCanonicalHashV1.sha256(try encoder.encode(registry)), contractManifestID: "c04-manifest", contractManifestVersion: 1, contractManifestSHA256: String(repeating: "a", count: 64), sectionIDs: profile.reportLayoutProfile.sectionIDs, audience: profile.reportLayoutProfile.audience, detail: profile.reportLayoutProfile.detail, privacyTransformID: profile.exportProfile.privacyTransformID, localeIdentifier: profile.reportLayoutProfile.localeIdentifier, unitsProfileID: profile.reportLayoutProfile.unitsProfileID, displayProfileID: profile.reportLayoutProfile.displayProfileID, orientation: profile.reportLayoutProfile.orientation, mediaLayout: profile.reportLayoutProfile.mediaLayout, rendererVersion: profile.rendererVersion, projectionVersion: "report-projection-v1")
    }

    private func evidenceCard(workspaceID: WorkspaceID, profile: ShopReportProfileV1) throws -> EvidenceDetailCardV1 {
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: String(repeating: "b", count: 64))
        let content = try ContentReferenceV1(workspaceID: workspaceID.rawValue.uuidString.lowercased(), contentID: "c04-content", byteLength: 12, mediaType: "image/jpeg", digests: ContentDigestSetV1([digest]), byteRole: .derivative, createdAt: "2026-08-30T00:00:00.000Z")
        let reference = try OutputScopedContentReferenceV1(outputScopeID: "c04-output", ordinal: 0, reference: content)
        return try EvidenceDetailComposerV1.compose(cardID: "c04-card", workspaceID: workspaceID.rawValue.uuidString.lowercased(), evidenceID: "c04-evidence", fields: [try EvidenceDetailFieldV1(fieldID: "service_request", label: "Service request", value: "SR-204", sensitivity: .audienceSafe), try EvidenceDetailFieldV1(fieldID: "service_status", label: "Service status", value: "Recorded", sensitivity: .audienceSafe)], profile: profile.evidenceDetailProfile, markupID: "c04-markup", annotations: ["Reviewed customer-safe derivative"], referenceLabels: ["Customer-safe derivative"], outputReferences: [reference])
    }

    private func artifactInputs() throws -> [ShopReportProfileLifecycleAdapterV1.ArtifactInput] {
        [
            .init(format: .formulaSafeCSV, bytes: try ShopReportProfileLifecycleAdapterV1.formulaSafeCSV(rows: [["section", "customer-safe"]])),
            .init(format: .openJSON, bytes: Data("{\"schema\":\"c04\"}".utf8)),
            .init(format: .pdf, bytes: Data("%PDF-1.4\n%%EOF".utf8)),
            .init(format: .structuredText, bytes: Data("summary: customer-safe".utf8))
        ]
    }

    private func accessibleFixture(workspaceID: WorkspaceID, actor: ActorSnapshotV1, profile: ShopReportProfileV1, binding: FinalizedReportProfileBindingV1, sourceSnapshotSHA256: String, output: AccessibleDocumentRenderOutputV1) throws -> (tree: AccessibleDocumentSemanticTreeV1, assessment: AccessibleDocumentAssessmentReceiptV1) {
        let publication = try AccessibleDocumentPublicationBindingV1(snapshotSHA256: sourceSnapshotSHA256, manifestID: binding.contractManifestID, manifestVersion: binding.contractManifestVersion, manifestSHA256: binding.contractManifestSHA256, localeIdentifier: binding.localeIdentifier, profileID: binding.reportProfileID, profileRelease: binding.reportProfileRelease, profileSHA256: binding.reportProfileSHA256, brandProfileID: profile.profileID.uuidString.lowercased(), brandProfileRelease: Int(profile.revision), brandProfileSHA256: profile.profileSHA256)
        let tree = try AccessibleDocumentSemanticTreeV1(treeID: id(16), workspaceID: workspaceID, audience: .customerSafe, publication: publication, nodes: [try AccessibleDocumentNodeV1(nodeID: "c04-document", role: .document, parentNodeID: nil, order: 0, localizedText: "Customer-safe evidence", sensitivity: .customerSafe)], projectionVersion: binding.projectionVersion)
        let reviewerReference = try LocalActorReferenceV1(actorReferenceID: id(17), workspaceID: workspaceID, displayName: "C04 accessibility reviewer")
        let reviewer = try ActorSnapshotV1(snapshotID: id(18), workspaceID: workspaceID, actor: reviewerReference, responsibility: .reviewedBy, displayNameAtTime: reviewerReference.displayName, capturedAt: Self.fixedDate.addingTimeInterval(3))
        let assessment = try AccessibleDocumentAssessmentReceiptV1(receiptID: id(19), workspaceID: workspaceID, tree: tree, outputSHA256: output.sha256, outputByteCount: Int64(output.bytes.count), outputMediaType: output.mediaType, rendererID: output.rendererID, rendererVersion: output.rendererVersion, assessmentToolID: "c04-accessibility-tool", assessmentToolVersion: "1", assessor: reviewer, state: .internalPass, assessedAt: Self.fixedDate.addingTimeInterval(4), mutationID: try MutationIDV1(rawValue: id(20)))
        XCTAssertEqual(tree.publication.brandProfileID, profile.profileID.uuidString.lowercased())
        XCTAssertEqual(tree.publication.brandProfileRelease, Int(profile.revision))
        XCTAssertEqual(tree.publication.brandProfileSHA256, profile.profileSHA256)
        XCTAssertEqual(assessment.outputSHA256, output.sha256)
        _ = actor
        return (tree, assessment)
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }
}

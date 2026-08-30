import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_49TemporalEvidenceClipTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45TemporalEvidenceCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityKeepsLabelArtifactsDerivedAndOutputClaimsBounded() {
        XCTAssertEqual(Set(LabelArtifactKindV1.allCases), [.pdf, .formulaSafeCSV, .structuredText])
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("LabelProjectedArtifactV1"))
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelPhysicalScanAcceptanceClaimed)
    }
}

enum C33TemporalEvidenceTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_820_001_600)
    static let fixedInstant = "2027-09-04T00:00:00Z"

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c3300000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func codec(for kind: TemporalEvidenceMediaKindV1) throws -> TemporalEvidenceCodecV1 {
        switch kind {
        case .audio:
            return try TemporalEvidenceCodecV1(
                container: "m4a",
                codec: "aac-lc",
                mediaType: "audio/mp4"
            )
        case .video:
            return try TemporalEvidenceCodecV1(
                container: "mp4",
                codec: "h264",
                mediaType: "video/mp4"
            )
        }
    }

    static func profile(
        workspaceID: WorkspaceID = workspace(),
        reportProjection: TemporalEvidenceReportProjectionV1 = .typedLinkWithDerivativePreview,
        requiresTranscript: Bool = true
    ) throws -> TemporalEvidenceLimitProfileV1 {
        let definition = try C26SurveySessionTestSupport.release(
            releaseSlot: 330,
            workspaceID: workspaceID
        )
        return try TemporalEvidenceLimitProfileV1(
            profileID: id(10),
            revision: 1,
            packageRelease: try SurveyPackageReleaseReferenceV1(
                C26SurveySessionTestSupport.packageRelease()
            ),
            definitionRelease: try SurveyDefinitionReleaseReferenceV1(definition),
            audio: TemporalEvidenceMediaLimitV1(
                kind: .audio,
                maximumDurationMilliseconds: 120_000,
                maximumByteCount: 8_388_608,
                acceptedCodecs: [codec(for: .audio)]
            ),
            video: TemporalEvidenceMediaLimitV1(
                kind: .video,
                maximumDurationMilliseconds: 60_000,
                maximumByteCount: 67_108_864,
                acceptedCodecs: [codec(for: .video)],
                maximumPixelWidth: 1_920,
                maximumPixelHeight: 1_080
            ),
            maximumClipsPerRequirement: 4,
            maximumClipsPerSession: 16,
            minimumFreeByteCount: 134_217_728,
            reportProjection: reportProjection,
            requiresAccessibleDescription: true,
            requiresManualTranscript: requiresTranscript
        )
    }

    static func target(
        workspaceID: WorkspaceID = workspace(),
        profile: TemporalEvidenceLimitProfileV1? = nil,
        factID: String = "fact-temporal-evidence"
    ) throws -> TemporalEvidenceTargetV1 {
        let profile = try profile ?? self.profile(workspaceID: workspaceID)
        return try TemporalEvidenceTargetV1(
            workspaceID: workspaceID,
            sessionID: id(20),
            sessionRevision: 7,
            sessionSHA256: String(repeating: "7", count: 64),
            definitionRelease: profile.definitionRelease,
            factID: factID,
            repeatCoordinates: []
        )
    }

    static func bytes(for kind: TemporalEvidenceMediaKindV1) -> Data {
        Data(repeating: kind == .audio ? 0x33 : 0x49, count: kind == .audio ? 4_096 : 8_192)
    }

    static func content(
        workspaceID: WorkspaceID = workspace(),
        kind: TemporalEvidenceMediaKindV1 = .audio,
        role: ContentByteRoleV1 = .immutableOriginal,
        slot: Int = 30
    ) throws -> ContentReferenceV1 {
        let data = bytes(for: kind)
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: KernelCanonicalHashV1.sha256(data)
        )
        return try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: "temporal.content.\(slot)",
            byteLength: Int64(data.count),
            mediaType: role == .derivative ? "image/png" : try codec(for: kind).mediaType,
            digests: ContentDigestSetV1([digest]),
            byteRole: role,
            createdAt: fixedInstant
        )
    }

    static func locator(_ content: ContentReferenceV1, slot: Int = 30) throws -> ContentLocatorV1 {
        try ContentLocatorV1(
            locatorID: "c05-\(content.contentID)",
            workspaceID: content.workspaceID,
            contentID: content.contentID,
            locatorRevision: 0,
            contentDigest: try XCTUnwrap(content.digests.digest(for: .sha256)),
            expectedByteLength: content.byteLength
        )
    }

    static func provenance(_ content: ContentReferenceV1) throws -> ContentOriginalProvenanceV1 {
        try ContentOriginalProvenanceV1(
            provenanceID: "temporal.provenance.\(content.contentID)",
            workspaceID: content.workspaceID,
            contentID: content.contentID,
            contentDigest: try XCTUnwrap(content.digests.digest(for: .sha256)),
            origin: .humanCapture,
            recordedAt: fixedInstant
        )
    }

    static func facts(
        kind: TemporalEvidenceMediaKindV1 = .audio,
        byteCount: UInt64? = nil,
        durationMilliseconds: UInt64? = nil
    ) throws -> TemporalEvidenceMediaFactsV1 {
        let count = UInt64(bytes(for: kind).count)
        return try TemporalEvidenceMediaFactsV1(
            kind: kind,
            durationMilliseconds: durationMilliseconds ?? (kind == .audio ? 45_000 : 30_000),
            byteCount: byteCount ?? count,
            codec: codec(for: kind),
            pixelWidth: kind == .video ? 1_280 : nil,
            pixelHeight: kind == .video ? 720 : nil
        )
    }

    static func clip(
        slot: Int = 40,
        workspaceID: WorkspaceID = workspace(),
        kind: TemporalEvidenceMediaKindV1 = .audio,
        factID: String = "fact-temporal-evidence",
        reportProjection: TemporalEvidenceReportProjectionV1 = .typedLinkWithDerivativePreview,
        requiresTranscript: Bool = true
    ) throws -> (clip: TemporalEvidenceClipV1, profile: TemporalEvidenceLimitProfileV1) {
        let profile = try self.profile(
            workspaceID: workspaceID,
            reportProjection: reportProjection,
            requiresTranscript: requiresTranscript
        )
        let content = try self.content(workspaceID: workspaceID, kind: kind, slot: slot)
        let clip = try TemporalEvidenceClipV1(
            clipID: id(slot),
            workspaceID: workspaceID,
            target: target(workspaceID: workspaceID, profile: profile, factID: factID),
            original: content,
            originalProvenance: provenance(content),
            locator: locator(content, slot: slot),
            facts: facts(kind: kind),
            profile: profile,
            accessibleDescription: kind == .audio
                ? "Short reviewed audio evidence recorded at the inspected asset."
                : "Short reviewed video evidence showing the inspected asset.",
            manualTranscript: requiresTranscript ? "Reviewer-entered temporal evidence transcript." : nil,
            recordedBy: C26SurveySessionTestSupport.actor(
                workspaceID: workspaceID,
                slot: 330,
                responsibility: .recordedBy
            ),
            capturedAt: fixedDate,
            acceptedAt: fixedDate.addingTimeInterval(5),
            revision: 1,
            mutationID: mutation(500 + slot)
        )
        return (clip, profile)
    }

    static func anchor(
        clip: TemporalEvidenceClipV1,
        slot: Int = 60,
        offsetMilliseconds: UInt64 = 12_500
    ) throws -> TimecodedEvidenceAnchorV1 {
        try TimecodedEvidenceAnchorV1(
            anchorID: id(slot),
            clip: clip,
            offsetMilliseconds: offsetMilliseconds,
            label: "Observed change",
            note: "Reviewer-entered time-coded note.",
            author: C26SurveySessionTestSupport.actor(
                workspaceID: clip.workspaceID,
                slot: 340,
                responsibility: .recordedBy
            ),
            recordedAt: fixedDate.addingTimeInterval(6),
            revision: 1,
            mutationID: mutation(600 + slot)
        )
    }

    static func derivative(
        clip: TemporalEvidenceClipV1,
        slot: Int = 70,
        kind: TemporalEvidenceDerivativeKindV1? = nil
    ) throws -> TemporalEvidenceDerivativeV1 {
        let derivativeKind = kind ?? (clip.facts.kind == .audio ? .waveform : .thumbnail)
        let content = try self.content(
            workspaceID: clip.workspaceID,
            kind: clip.facts.kind,
            role: .derivative,
            slot: slot
        )
        let generatorID = "temporal.preview.generator"
        let generatorVersion = "v1"
        let transform: ContentDerivativeTransformV1
        switch derivativeKind {
        case .thumbnail:
            transform = .thumbnail(try ThumbnailDerivativeV1(
                rendererID: generatorID,
                rendererVersion: generatorVersion,
                pixelWidth: 320,
                pixelHeight: 180
            ))
        case .waveform:
            transform = .waveform(try WaveformDerivativeV1(
                rendererID: generatorID,
                rendererVersion: generatorVersion,
                sampleCount: 1_024
            ))
        }
        let provenance = try ContentDerivativeProvenanceV1(
            provenanceID: "temporal.derivative.provenance.\(slot)",
            workspaceID: content.workspaceID,
            sources: [try ContentSourceBindingV1(
                contentID: clip.original.contentID,
                digest: XCTUnwrap(clip.original.digests.digest(for: .sha256))
            )],
            derivativeContentID: content.contentID,
            derivativeDigest: XCTUnwrap(content.digests.digest(for: .sha256)),
            transform: transform,
            metadataSanitizerID: "temporal.metadata.sanitizer",
            metadataSanitizerVersion: "v1",
            createdAt: fixedInstant
        )
        return try TemporalEvidenceDerivativeV1(
            derivativeID: id(slot),
            clip: clip,
            content: content,
            locator: locator(content, slot: slot),
            kind: derivativeKind,
            generatorID: generatorID,
            generatorVersion: generatorVersion,
            provenance: provenance,
            revision: 1,
            mutationID: mutation(700 + slot)
        )
    }

    static func expectedRevision(
        for clip: TemporalEvidenceClipV1,
        generationID: UUID = id(800),
        writerInstanceID: UUID = id(801),
        workspaceRevision: UInt64 = 0,
        entityRevision: UInt64 = 0
    ) throws -> WorkspaceExpectedRevisionV1 {
        try WorkspaceExpectedRevisionV1(
            workspaceID: clip.workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: workspaceRevision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .temporalEvidenceClip,
                        id: clip.clipID
                    ),
                    revision: entityRevision
                )
            ]
        )
    }

    static func review(
        for clip: TemporalEvidenceClipV1,
        decision: TemporalEvidenceReviewDecisionV1 = .accept
    ) throws -> TemporalEvidenceCaptureReviewV1 {
        try TemporalEvidenceCaptureReviewV1(
            reviewID: id(810),
            workspaceID: clip.workspaceID,
            clipID: clip.clipID,
            decision: decision,
            reviewer: C26SurveySessionTestSupport.actor(
                workspaceID: clip.workspaceID,
                slot: 811,
                responsibility: .reviewedBy
            ),
            reviewedAt: clip.acceptedAt
        )
    }

    static func admissionReceipt(
        for clip: TemporalEvidenceClipV1,
        profile: TemporalEvidenceLimitProfileV1
    ) throws -> TemporalEvidenceIncrementalAdmissionReceiptV1 {
        try TemporalEvidenceIncrementalAdmissionReceiptV1(
            profile: profile,
            kind: clip.facts.kind,
            codec: clip.facts.codec,
            pixelWidth: clip.facts.pixelWidth,
            pixelHeight: clip.facts.pixelHeight,
            observedDurationMilliseconds: clip.facts.durationMilliseconds,
            observedByteCount: clip.facts.byteCount,
            sequence: 1,
            captureCompleted: true
        )
    }

    static func reportAssurance(
        workspaceID: WorkspaceID,
        slot: Int
    ) throws -> ReportEvidenceAssuranceProjectionV1 {
        let visibility = try EvidenceVisibilityV1(
            visibilityID: id(slot),
            workspaceID: workspaceID,
            sensitivity: .routine,
            allowedAudiences: [.internalReview, .customerReport],
            effectiveAt: fixedDate,
            mutationID: mutation(slot + 1)
        )
        let link = try ClaimEvidenceLinkV1(
            linkID: id(slot + 2),
            workspaceID: workspaceID,
            claimID: "temporal-evidence-report-claim",
            evidenceID: "temporal-evidence-report-evidence",
            evidenceRevision: 1,
            evidenceSHA256: String(repeating: "a", count: 64),
            visibility: visibility,
            audience: .customerReport,
            mutationID: mutation(slot + 3)
        )
        let preview = try AssuranceProjectionPreviewV1(
            previewID: id(slot + 4),
            workspaceID: workspaceID,
            audience: .customerReport,
            snapshotSHA256: String(repeating: "b", count: 64),
            projectionVersion: "report-projection-v1",
            links: [link],
            createdAt: fixedDate.addingTimeInterval(30)
        )
        return try ReportEvidenceAssuranceProjectionV1(
            preview: preview,
            visibilities: [visibility]
        )
    }

    static func reportSnapshot(
        clip: TemporalEvidenceClipV1,
        anchors: [TimecodedEvidenceAnchorV1],
        reportID: UUID,
        slot: Int,
        includesAssurance: Bool
    ) throws -> ReportSnapshotV1 {
        var snapshot = ReportSnapshotV1(
            acknowledgements: [
                AcknowledgementSnapshotV1(
                    accepted: true,
                    copy: "It is dark enough to observe the sign's visible illumination.",
                    key: "after_dark",
                    version: "preflight.ack.en-US.v1"
                ),
                AcknowledgementSnapshotV1(
                    accepted: true,
                    copy: "I am in a safe, authorized position to take these photos.",
                    key: "safe_authorized_position",
                    version: "preflight.ack.en-US.v1"
                )
            ],
            asset: AssetSnapshotV1(label: "Temporal evidence asset"),
            couldNotVerify: nil,
            disclaimer: "This report records visible conditions and reviewed temporal evidence.",
            display: DisplaySnapshotV1(
                assetSingular: "asset",
                checkSingular: "check",
                issueSingular: "visible issue",
                outcome: "Recorded",
                stage: "Check"
            ),
            evidence: [],
            evidenceSourceRecordID: id(slot + 1),
            history: [],
            issues: [],
            note: nil,
            outcome: "recorded",
            pack: PackSnapshotV1(
                contentVersion: 1,
                id: "field.evidence.illuminated_sign.v1",
                schemaVersion: 1
            ),
            packetID: id(slot + 2),
            pdfTemplate: PDFTemplateReferenceV1(
                id: "field.evidence.pdf.worklight.v1",
                version: 1
            ),
            reportID: reportID,
            site: SiteSnapshotV1(address: nil, label: "Temporal evidence site"),
            snapshotCreatedAt: fixedDate.addingTimeInterval(40),
            snapshotSchemaVersion: 1,
            sourceApp: SourceAppSnapshotV1(build: "33", version: "1.0"),
            sourceRecordID: id(slot + 3),
            stableRootID: id(slot + 4),
            stage: "check",
            timeContext: TimeContextSnapshotV1(
                localDate: "2027-09-04",
                localTime: "00:00:00",
                observedAtUTC: fixedDate,
                timeZoneID: "America/New_York",
                utcOffsetMinutes: -240
            )
        )
        snapshot.temporalEvidenceLinks = [try TemporalEvidenceReportLinkV1(
            clip: clip,
            anchors: anchors,
            profile: clip.limitProfile
        )]
        if includesAssurance {
            snapshot.assurance = try reportAssurance(
                workspaceID: clip.workspaceID,
                slot: slot + 20
            )
        }
        return snapshot
    }

    @MainActor
    static func persistReportSnapshots(
        in session: StoreGenerationSession,
        clip: TemporalEvidenceClipV1,
        anchorSubsets: [[TimecodedEvidenceAnchorV1]],
        slot: Int
    ) throws -> [ReportSnapshotV1] {
        guard anchorSubsets.count == 2,
              anchorSubsets[0].count == anchorSubsets[1].count,
              Set(anchorSubsets[0].map(\.anchorID)) != Set(anchorSubsets[1].map(\.anchorID)) else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        let snapshots = try [false, true].enumerated().map { offset, includesAssurance in
            try reportSnapshot(
                clip: clip,
                anchors: anchorSubsets[offset],
                reportID: id(slot + offset),
                slot: slot + offset * 100,
                includesAssurance: includesAssurance
            )
        }
        let directory = session.generationRootURL.appendingPathComponent(
            "snapshots",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for snapshot in snapshots {
            let encoded = try ReportSnapshotEncoderV1().encode(snapshot)
            let relativePath = "snapshots/\(snapshot.reportID.uuidString.lowercased()).json"
            try encoded.data.write(
                to: session.generationRootURL.appendingPathComponent(relativePath),
                options: .atomic
            )
            session.modelContext.insert(Report(
                id: snapshot.reportID,
                packetID: snapshot.packetID,
                sourceRecordID: snapshot.sourceRecordID,
                snapshotSchemaVersion: snapshot.snapshotSchemaVersion,
                snapshotRelativePath: relativePath,
                snapshotSHA256: encoded.sha256,
                pdfState: .pending,
                pdfRelativePath: nil,
                pdfSHA256: nil,
                createdAt: snapshot.snapshotCreatedAt,
                replacesReportID: nil
            ))
        }
        return snapshots
    }

    @MainActor
    static func commitPersistentAnchors(
        in session: StoreGenerationSession,
        clip: TemporalEvidenceClipV1,
        slots: [Int]
    ) throws -> [TimecodedEvidenceAnchorV1] {
        guard !slots.isEmpty else { throw TemporalEvidenceContractFailureV1.invalidValue }
        let writerInstanceID = id(8_000 + slots[0])
        let store = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let initial = try store.currentRevision(writerInstanceID: writerInstanceID)
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: initial,
            clock: C33TemporalEvidenceClock(value: clip.acceptedAt.addingTimeInterval(20)),
            idSource: C33TemporalEvidenceIDSource(value: writerInstanceID),
            fileAuthority: C33TemporalEvidenceFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: store
        )
        var values: [TimecodedEvidenceAnchorV1] = []
        for (offset, slot) in slots.enumerated() {
            let anchor = try self.anchor(
                clip: clip,
                slot: slot,
                offsetMilliseconds: UInt64(5_000 + offset * 10_000)
            )
            let current = try store.currentRevision(writerInstanceID: writerInstanceID)
            let expected = try WorkspaceExpectedRevisionV1(
                workspaceID: current.workspaceID,
                generationID: current.generationID,
                writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision,
                entityRevisions: [WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .timecodedEvidenceAnchor,
                        id: anchor.anchorID
                    ),
                    revision: 0
                )]
            )
            _ = try writer.commitTemporalEvidence(TemporalEvidenceMutationV1(
                workspaceID: clip.workspaceID,
                expectedRevision: expected,
                mutationID: anchor.mutationID,
                payload: .appendAnchor(anchor, clip: clip, predecessor: nil)
            ))
            values.append(anchor)
        }
        return values
    }

    @MainActor
    static func commitPersistentClip(
        in session: StoreGenerationSession,
        slot: Int
    ) async throws -> (clip: TemporalEvidenceClipV1, receipt: TemporalEvidenceMutationReceiptV1) {
        let fixture = try clip(
            slot: slot,
            workspaceID: session.workspaceID,
            reportProjection: .typedLinkOnly,
            requiresTranscript: true
        )
        let writerInstanceID = id(8_000 + slot)
        let store = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let current = try store.currentRevision(writerInstanceID: writerInstanceID)
        let expected = try expectedRevision(
            for: fixture.clip,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision
        )
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: current,
            clock: C33TemporalEvidenceClock(value: fixture.clip.acceptedAt),
            idSource: C33TemporalEvidenceIDSource(value: writerInstanceID),
            fileAuthority: C33TemporalEvidenceFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: store
        )
        let digest = try XCTUnwrap(fixture.clip.original.digests.digest(for: .sha256))
        let contentRequest = try DraftImmutableContentWriteRequestV1(
            workspaceID: fixture.clip.workspaceID,
            contentID: fixture.clip.original.contentID,
            digest: digest,
            byteLength: fixture.clip.original.byteLength,
            mediaType: fixture.clip.original.mediaType,
            mutationID: fixture.clip.mutationID,
            createdAt: fixture.clip.original.createdAt
        )
        _ = try await EvidenceBundleStore(
            generationRootURL: session.generationRootURL
        ).persistImmutableOriginal(
            bytes: bytes(for: fixture.clip.facts.kind),
            request: contentRequest
        )
        let mutation = try TemporalEvidenceMutationV1(
            workspaceID: fixture.clip.workspaceID,
            expectedRevision: expected,
            mutationID: fixture.clip.mutationID,
            payload: .acceptClip(
                fixture.clip,
                review: C33TemporalEvidenceTestSupport.review(for: fixture.clip),
                predecessor: nil
            )
        )
        return (fixture.clip, try writer.commitTemporalEvidence(mutation))
    }

    @MainActor
    static func verifyRealBackupRestoreDeleteAndErase(slot: Int) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C33-R01-\(slot)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let sourceSupport = root.appendingPathComponent("source-support", isDirectory: true)
        try fileManager.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let sourceSession = try StoreGenerationFactory(
            applicationSupportURL: sourceSupport
        ).openOrBootstrapCurrent()
        let source = try await commitPersistentClip(in: sourceSession, slot: slot)
        try sourceSession.modelContext.save()
        let sourceBytes = bytes(for: source.clip.facts.kind)
        let sourceCanonical = try XCTUnwrap(
            sourceSession.modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).first
        ).canonicalData
        let exportRoot = root.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: sourceSession.modelContext,
            generationRootURL: sourceSession.generationRootURL,
            now: { fixedDate.addingTimeInterval(120) }
        )
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: exportRoot)

        for (index, mode) in [
            BackupRestoreMode.emptyInstall,
            .replaceExisting,
            .clone,
            .fork
        ].enumerated() {
            let support = root.appendingPathComponent("restore-\(index)", isDirectory: true)
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            let current = try StoreGenerationFactory(
                applicationSupportURL: support
            ).openOrBootstrapCurrent()
            let validated = try BackupImportService(
                generationRootURL: current.generationRootURL,
                makeUUID: { id(9_000 + slot + index) },
                scopedAccess: .alreadyAuthorized
            ).stageAndValidate(selectedPackageURL: package)
            XCTAssertEqual(validated.records.temporalEvidence.count, 1)
            XCTAssertEqual(validated.members[try TemporalEvidenceBackupMemberV1.original(for: source.clip)], sourceBytes)
            let restored = try await BackupRestoreService(
                applicationSupportURL: support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: current.modelContext,
                currentGenerationID: current.generationID,
                currentGenerationRootURL: current.generationRootURL,
                mode: mode
            )
            let row = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).first
            )
            let restoredClip = try row.value()
            XCTAssertEqual(restoredClip.workspaceID, restored.workspaceID)
            XCTAssertEqual(restoredClip.original.contentID, source.clip.original.contentID)
            XCTAssertEqual(restoredClip.original.digests, source.clip.original.digests)
            XCTAssertEqual(
                try Data(contentsOf: restored.generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: restoredClip)
                )),
                sourceBytes
            )
            if mode == .emptyInstall || mode == .replaceExisting {
                XCTAssertEqual(row.canonicalData, sourceCanonical)
                XCTAssertEqual(restoredClip.limitProfile, source.clip.limitProfile)
            } else {
                XCTAssertNotEqual(restoredClip.workspaceID, source.clip.workspaceID)
                XCTAssertEqual(
                    restoredClip.limitProfile.revision,
                    source.clip.limitProfile.revision + 1
                )
                XCTAssertEqual(restoredClip.limitProfile.audio, source.clip.limitProfile.audio)
                XCTAssertEqual(restoredClip.limitProfile.video, source.clip.limitProfile.video)
                XCTAssertEqual(
                    restoredClip.limitProfile.definitionRelease,
                    restoredClip.target.definitionRelease
                )
                XCTAssertNotEqual(
                    restoredClip.limitProfile.packageRelease,
                    source.clip.limitProfile.packageRelease
                )
                XCTAssertNotEqual(restoredClip.clipSHA256, source.clip.clipSHA256)
            }
            let journal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try journal.validateAll()
        }

        let deleteSupport = root.appendingPathComponent("delete-support", isDirectory: true)
        try fileManager.createDirectory(at: deleteSupport, withIntermediateDirectories: true)
        let deleteSession = try StoreGenerationFactory(
            applicationSupportURL: deleteSupport
        ).openOrBootstrapCurrent()
        let deleted = try await commitPersistentClip(in: deleteSession, slot: slot + 20)
        let deleteWriterInstanceID = id(8_000 + slot + 20)
        let deleteStore = try MutationJournalStoreV1(
            modelContext: deleteSession.modelContext,
            identity: deleteSession.workspaceIdentity,
            generationID: deleteSession.generationID,
            allowStateBootstrap: false
        )
        let deleteCurrent = try deleteStore.currentRevision(
            writerInstanceID: deleteWriterInstanceID
        )
        let deleteExpected = try expectedRevision(
            for: deleted.clip,
            generationID: deleteCurrent.generationID,
            writerInstanceID: deleteCurrent.writerInstanceID,
            workspaceRevision: deleteCurrent.revision,
            entityRevision: deleted.clip.revision
        )
        let deleteWriter = try WorkspaceWriterV1(
            identity: deleteSession.workspaceIdentity,
            generationID: deleteSession.generationID,
            initialRevision: deleteCurrent,
            clock: C33TemporalEvidenceClock(value: fixedDate.addingTimeInterval(240)),
            idSource: C33TemporalEvidenceIDSource(value: deleteWriterInstanceID),
            fileAuthority: C33TemporalEvidenceFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: deleteSession.modelContext),
            journalStore: deleteStore
        )
        let deleteEvent = try TemporalEvidenceRetentionEventV1(
            eventID: id(9_500 + slot),
            clip: deleted.clip,
            disposition: .deleteClip,
            policySHA256: String(repeating: "e", count: 64),
            actor: C26SurveySessionTestSupport.actor(
                workspaceID: deleted.clip.workspaceID,
                slot: 9_501 + slot,
                responsibility: .reviewedBy
            ),
            occurredAt: fixedDate.addingTimeInterval(240),
            revision: 1,
            mutationID: mutation(9_502 + slot)
        )
        _ = try deleteWriter.commitTemporalEvidence(TemporalEvidenceMutationV1(
            workspaceID: deleted.clip.workspaceID,
            expectedRevision: deleteExpected,
            mutationID: deleteEvent.mutationID,
            payload: .removeClip(
                event: deleteEvent,
                clips: [deleted.clip],
                anchors: [],
                derivatives: [],
                predecessorEvent: nil
            )
        ))
        XCTAssertEqual(
            try deleteSession.modelContext.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()),
            0
        )
        let cleanup = try OrphanFileCleanupService(
            generationRootURL: deleteSession.generationRootURL
        )
        let summary = try cleanup.removeCanonicalContentIfUnreferenced(
            reference: deleted.clip.original,
            locator: deleted.clip.locator,
            liveClipContentIDs: [],
            liveReportContentIDs: [],
            reservedContentIDs: [],
            recoveryContentIDs: []
        )
        XCTAssertEqual(summary.removedFileCount, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: deleteSession.generationRootURL
            .appendingPathComponent(try TemporalEvidenceBackupMemberV1.original(for: deleted.clip)).path))

        let eraseLibrary = root.appendingPathComponent("erase-library", isDirectory: true)
        let eraseSupport = eraseLibrary.appendingPathComponent("Application Support", isDirectory: true)
        let eraseCaches = eraseLibrary.appendingPathComponent("Caches", isDirectory: true)
        let eraseTemporary = root.appendingPathComponent("erase-tmp", isDirectory: true)
        try fileManager.createDirectory(at: eraseSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: eraseCaches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: eraseTemporary, withIntermediateDirectories: true)
        let eraseSession = try StoreGenerationFactory(
            applicationSupportURL: eraseSupport
        ).openOrBootstrapCurrent()
        _ = try await commitPersistentClip(in: eraseSession, slot: slot + 40)
        let coordinator = StoreSessionCoordinator(session: eraseSession)
        let diagnostics = DiagnosticsStore(applicationSupportURL: eraseSupport)
        await diagnostics.prepare()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "C33-R01-\(UUID())"))
        let eraseIDs = [id(9_700 + slot), id(9_701 + slot)]
        var remainingEraseIDs = eraseIDs
        let erase = EraseAllService(
            applicationSupportURL: eraseSupport,
            cachesDirectoryURL: eraseCaches,
            temporaryDirectoryURL: eraseTemporary,
            userDefaults: defaults,
            bundleIdentifier: "com.palatis3.fieldrecord.c33.tests",
            makeUUID: { remainingEraseIDs.removeFirst() }
        )
        let outcome = try await erase.erase(
            confirmation: "ERASE",
            coordinator: coordinator,
            diagnosticsStore: diagnostics
        ) { session in
            coordinator.activate(session: session)
        }
        try erase.validateTemporalEvidenceEraseClosure(session: outcome.session)
        XCTAssertEqual(
            try outcome.session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            0
        )
    }

    static func ownerClip(
        factID: String,
        kind: TemporalEvidenceMediaKindV1,
        reportProjection: TemporalEvidenceReportProjectionV1
    ) throws -> (clip: TemporalEvidenceClipV1, profile: TemporalEvidenceLimitProfileV1) {
        try clip(
            slot: 900,
            kind: kind,
            factID: factID,
            reportProjection: reportProjection,
            requiresTranscript: true
        )
    }

    static func assertOwnerBoundary(
        _ value: (clip: TemporalEvidenceClipV1, profile: TemporalEvidenceLimitProfileV1),
        factID: String,
        kind: TemporalEvidenceMediaKindV1,
        reportProjection: TemporalEvidenceReportProjectionV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(value.clip.target.factID, factID, file: file, line: line)
        XCTAssertEqual(value.clip.facts.kind, kind, file: file, line: line)
        XCTAssertEqual(value.profile.reportProjection, reportProjection, file: file, line: line)
        XCTAssertEqual(value.clip.limitProfile, value.profile, file: file, line: line)
        XCTAssertEqual(value.clip.original.byteRole, .immutableOriginal, file: file, line: line)
        XCTAssertEqual(value.clip.original.byteLength, Int64(value.clip.facts.byteCount), file: file, line: line)
        XCTAssertFalse(TemporalEvidencePersistenceEnrollmentV1.immutableOriginalsAreRewritten, file: file, line: line)
        XCTAssertFalse(TemporalEvidencePersistenceEnrollmentV1.secondByteStoreAllowed, file: file, line: line)
        try value.clip.validate(profile: value.profile)
    }
}

private struct C33TemporalEvidenceClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct C33TemporalEvidenceIDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C33TemporalEvidenceFileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "c33/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C33TemporalEvidenceContentCleanupResolver:
    TemporalEvidenceRetentionContentCleanupResolvingV1 {
    private let remove: TemporalEvidencePromotedContentRemovalV1

    init(remove: @escaping TemporalEvidencePromotedContentRemovalV1) {
        self.remove = remove
    }

    func removeCommittedContent(
        for mutation: TemporalEvidenceMutationV1,
        receipt: TemporalEvidenceMutationReceiptV1
    ) async throws {
        try receipt.validate(mutation: mutation)
        guard case let .removeClip(_, clips, _, derivatives, _) = mutation.payload else {
            throw TemporalEvidenceContractFailureV1.invalidTransition
        }
        let values = (clips.map(\.original) + derivatives.map(\.content)).sorted {
            $0.contentID < $1.contentID
        }
        guard Set(values.map(\.contentID)).count == values.count else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        for value in values {
            let digest = try XCTUnwrap(
                value.digests.digest(for: .sha256)?.hexadecimalValue
            )
            try await remove(mutation.workspaceID, value.contentID, digest)
        }
    }
}

private actor C33TemporalEvidenceScratchSpy: TemporalEvidenceScratchLifecycleV1 {
    private var operationByLeaseID: [UUID: UUID] = [:]
    private var dispositions: [ScratchPublicationDispositionV1] = []
    private var recoveryCount = 0
    private var failAcceptedFinishOnce: Bool

    init(failAcceptedFinishOnce: Bool = false) {
        self.failAcceptedFinishOnce = failAcceptedFinishOnce
    }

    func acquire(_ request: CapabilityScratchLeaseRequestV1) async throws -> CapabilityScratchLeaseV1 {
        operationByLeaseID[request.leaseID] = request.operationID
        return CapabilityScratchLeaseV1(
            leaseID: request.leaseID,
            purpose: request.purpose,
            relativeDirectory: "scratch/c33/\(request.leaseID.uuidString.lowercased())"
        )
    }

    func write(_ data: Data, named: String, lease: CapabilityScratchLeaseV1) async throws -> URL {
        guard !data.isEmpty, !named.isEmpty, operationByLeaseID[lease.leaseID] != nil else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        return URL(fileURLWithPath: "scratch/c33/\(lease.leaseID.uuidString.lowercased())/\(named)")
    }

    func finish(
        lease: CapabilityScratchLeaseV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws -> ScratchPublicationLinkageReceiptV1 {
        if disposition == .acceptedIntoImmutableContent, failAcceptedFinishOnce {
            failAcceptedFinishOnce = false
            throw TemporalEvidenceContractFailureV1.interruption
        }
        let operationID = try XCTUnwrap(operationByLeaseID[lease.leaseID])
        dispositions.append(disposition)
        return try ScratchPublicationLinkageReceiptV1(
            operationID: operationID,
            leaseID: lease.leaseID,
            purpose: lease.purpose,
            disposition: disposition,
            immutableContentReceiptDigest: immutableContentReceiptDigest,
            scratchDeleted: true
        )
    }

    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        recoveryCount += 1
        return try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: operationByLeaseID.count,
            removedByteCount: 0
        )
    }

    func recordedDispositions() -> [ScratchPublicationDispositionV1] { dispositions }
    func recordedRecoveryCount() -> Int { recoveryCount }
}

private enum C33TemporalEvidenceRecoveryFault: Equatable, Sendable {
    case afterPrepared
    case afterOriginalPromoted
}

private actor C33TemporalEvidenceFaultingRecovery: TemporalEvidencePromotionRecoveryPortV1 {
    private let base: any TemporalEvidencePromotionRecoveryPortV1
    private var pending: C33TemporalEvidenceRecoveryFault?

    init(
        base: any TemporalEvidencePromotionRecoveryPortV1,
        pending: C33TemporalEvidenceRecoveryFault
    ) {
        self.base = base
        self.pending = pending
    }

    func prepare(_ reservation: TemporalEvidencePromotionReservationV1) async throws {
        try await base.prepare(reservation)
        if pending == .afterPrepared {
            pending = nil
            throw TemporalEvidenceContractFailureV1.interruption
        }
    }

    func transition(
        _ reservation: TemporalEvidencePromotionReservationV1,
        to state: TemporalEvidencePromotionRecoveryStateV1
    ) async throws {
        try await base.transition(reservation, to: state)
        if state == .originalPromoted, pending == .afterOriginalPromoted {
            pending = nil
            throw TemporalEvidenceContractFailureV1.interruption
        }
    }

    func reservation(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> TemporalEvidencePromotionReservationV1? {
        try await base.reservation(workspaceID: workspaceID, mutationID: mutationID)
    }

    func recoverPending() async throws -> [TemporalEvidencePromotionReservationV1] {
        try await base.recoverPending()
    }

    func promotedContentExists(
        _ reservation: TemporalEvidencePromotionReservationV1
    ) async throws -> Bool {
        try await base.promotedContentExists(reservation)
    }

    func adoptCommittedContent(
        _ reservation: TemporalEvidencePromotionReservationV1,
        receiptSHA256: String
    ) async throws {
        try await base.adoptCommittedContent(reservation, receiptSHA256: receiptSHA256)
    }

    func removeUncommittedContent(
        _ reservation: TemporalEvidencePromotionReservationV1
    ) async throws {
        try await base.removeUncommittedContent(reservation)
    }

    func remove(_ reservation: TemporalEvidencePromotionReservationV1) async throws {
        try await base.remove(reservation)
    }
}

private actor C33TemporalEvidenceAdmissionStub: TemporalEvidenceAdmissionResolvingV1 {
    var snapshot: TemporalEvidenceAdmissionSnapshotV1

    init(snapshot: TemporalEvidenceAdmissionSnapshotV1) {
        self.snapshot = snapshot
    }

    func currentAdmission(
        for clip: TemporalEvidenceClipV1
    ) async throws -> TemporalEvidenceAdmissionSnapshotV1 {
        snapshot
    }

    func replace(with value: TemporalEvidenceAdmissionSnapshotV1) {
        snapshot = value
    }
}

@MainActor
private final class C33TemporalEvidencePersistentHarness {
    let fixture: (clip: TemporalEvidenceClipV1, profile: TemporalEvidenceLimitProfileV1)
    let container: ModelContainer
    let context: ModelContext
    let identity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let writerInstanceID: UUID
    let store: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let scratch: C33TemporalEvidenceScratchSpy
    let admission: C33TemporalEvidenceAdmissionStub
    let recovery: any TemporalEvidencePromotionRecoveryPortV1
    let cleanupRecovery: any TemporalEvidenceRetentionCleanupRecoveryPortV1
    let contentCleanup: TemporalEvidenceRetentionContentCleanupAdapterV1
    let content: TemporalEvidenceExistingContentPromotionAdapterV1
    let coordinator: TemporalEvidenceCoordinatorV1
    let request: TemporalEvidenceAcceptanceRequestV1
    let generationRootURL: URL

    init(
        slot: Int,
        failureBoundary: MutationJournalFaultBoundaryV1? = nil,
        recoveryFault: C33TemporalEvidenceRecoveryFault? = nil,
        failAcceptedScratchFinishOnce: Bool = false
    ) async throws {
        let fixture = try C33TemporalEvidenceTestSupport.clip(slot: slot)
        let schema = Schema(
            PersistentSchemaV33.models,
            version: PersistentSchemaV33.versionIdentifier
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C33TemporalEvidence-\(slot)",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: fixture.clip.workspaceID,
            replicaID: ReplicaID(rawValue: C33TemporalEvidenceTestSupport.id(802 + slot))
        )
        let generationID = C33TemporalEvidenceTestSupport.id(800)
        let writerInstanceID = C33TemporalEvidenceTestSupport.id(801)
        let store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID,
            failureInjection: failureBoundary.map {
                MutationJournalFailureInjectionV1(failOnceAt: $0)
            }
        )
        let expected = try C33TemporalEvidenceTestSupport.expectedRevision(
            for: fixture.clip,
            generationID: generationID,
            writerInstanceID: writerInstanceID
        )
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: writerInstanceID),
            clock: C33TemporalEvidenceClock(value: fixture.clip.acceptedAt),
            idSource: C33TemporalEvidenceIDSource(value: writerInstanceID),
            fileAuthority: C33TemporalEvidenceFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
        let generationRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "C33TemporalEvidence-\(slot)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: generationRootURL,
            withIntermediateDirectories: true
        )
        let content = TemporalEvidenceExistingContentPromotionAdapterV1(
            writer: EvidenceBundleStore(generationRootURL: generationRootURL)
        )
        let scratch = C33TemporalEvidenceScratchSpy(
            failAcceptedFinishOnce: failAcceptedScratchFinishOnce
        )
        let admission = C33TemporalEvidenceAdmissionStub(snapshot: try TemporalEvidenceAdmissionSnapshotV1(
            expectedRevision: expected,
            profile: fixture.profile,
            clipsForRequirement: 0,
            clipsForSession: 0,
            availableByteCount: fixture.profile.minimumFreeByteCount + fixture.clip.facts.byteCount,
            evaluatedAt: fixture.clip.acceptedAt
        ))
        let recoveryBase = try TemporalEvidencePromotionRecoveryFileAdapterV1(
            generationRootURL: generationRootURL,
            workspaceID: fixture.clip.workspaceID,
            verify: { workspaceID, contentID, contentSHA256 in
                guard workspaceID == fixture.clip.workspaceID,
                      contentID == fixture.clip.original.contentID,
                      contentSHA256 == fixture.clip.original.digests.digest(for: .sha256)?.hexadecimalValue else {
                    return false
                }
                let url = generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: fixture.clip)
                )
                guard FileManager.default.fileExists(atPath: url.path) else { return false }
                return KernelCanonicalHashV1.sha256(try Data(contentsOf: url)) == contentSHA256
            },
            remove: { workspaceID, contentID, contentSHA256 in
                guard workspaceID == fixture.clip.workspaceID,
                      contentID == fixture.clip.original.contentID,
                      contentSHA256 == fixture.clip.original.digests.digest(for: .sha256)?.hexadecimalValue else {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
                let url = generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: fixture.clip)
                )
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        )
        let recovery: any TemporalEvidencePromotionRecoveryPortV1
        if let recoveryFault {
            recovery = C33TemporalEvidenceFaultingRecovery(
                base: recoveryBase,
                pending: recoveryFault
            )
        } else {
            recovery = recoveryBase
        }
        let cleanupRecovery = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(
            generationRootURL: generationRootURL,
            workspaceID: fixture.clip.workspaceID
        )
        let cleanupResolver = C33TemporalEvidenceContentCleanupResolver {
            workspaceID, contentID, contentSHA256 in
            let url = generationRootURL
                .appendingPathComponent("content", isDirectory: true)
                .appendingPathComponent(
                    workspaceID.rawValue.uuidString.lowercased(),
                    isDirectory: true
                )
                .appendingPathComponent(contentID, isDirectory: true)
                .appendingPathComponent("original.bin", isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            guard KernelCanonicalHashV1.sha256(try Data(contentsOf: url)) == contentSHA256 else {
                throw TemporalEvidenceContractFailureV1.digestMismatch
            }
            try FileManager.default.removeItem(at: url)
        }
        let contentCleanup = TemporalEvidenceRetentionContentCleanupAdapterV1(
            resolver: cleanupResolver
        )
        let coordinator = TemporalEvidenceCoordinatorV1(
            writer: writer,
            content: content,
            scratch: scratch,
            admission: admission,
            recovery: recovery,
            cleanupRecovery: cleanupRecovery,
            contentCleanup: contentCleanup
        )
        let binding = try await coordinator.acquireScratch(
            leaseID: C33TemporalEvidenceTestSupport.id(820 + slot),
            mutationID: fixture.clip.mutationID,
            contentID: fixture.clip.original.contentID,
            contentSHA256: try XCTUnwrap(
                fixture.clip.original.digests.digest(for: .sha256)?.hexadecimalValue
            ),
            profile: fixture.profile,
            kind: fixture.clip.facts.kind,
            createdAt: fixture.clip.capturedAt.addingTimeInterval(-1),
            expiresAt: fixture.clip.acceptedAt.addingTimeInterval(60)
        )
        _ = try await scratch.write(
            C33TemporalEvidenceTestSupport.bytes(for: fixture.clip.facts.kind),
            named: "completed.bin",
            lease: binding.lease
        )
        let request = try TemporalEvidenceAcceptanceRequestV1(
            clip: fixture.clip,
            profile: fixture.profile,
            review: C33TemporalEvidenceTestSupport.review(for: fixture.clip),
            expectedRevision: expected,
            scratchBinding: binding,
            admissionReceipt: C33TemporalEvidenceTestSupport.admissionReceipt(
                for: fixture.clip,
                profile: fixture.profile
            ),
            completedBytes: C33TemporalEvidenceTestSupport.bytes(for: fixture.clip.facts.kind)
        )
        self.fixture = fixture
        self.container = container
        self.context = context
        self.identity = identity
        self.generationID = generationID
        self.writerInstanceID = writerInstanceID
        self.store = store
        self.writer = writer
        self.scratch = scratch
        self.admission = admission
        self.recovery = recovery
        self.cleanupRecovery = cleanupRecovery
        self.contentCleanup = contentCleanup
        self.content = content
        self.coordinator = coordinator
        self.request = request
        self.generationRootURL = generationRootURL
    }

    private func coldRecoveryAdapter() throws -> TemporalEvidencePromotionRecoveryFileAdapterV1 {
        let fixture = fixture
        let generationRootURL = generationRootURL
        return try TemporalEvidencePromotionRecoveryFileAdapterV1(
            generationRootURL: generationRootURL,
            workspaceID: fixture.clip.workspaceID,
            verify: { workspaceID, contentID, contentSHA256 in
                guard workspaceID == fixture.clip.workspaceID,
                      contentID == fixture.clip.original.contentID,
                      contentSHA256 == fixture.clip.original.digests
                        .digest(for: .sha256)?.hexadecimalValue else {
                    return false
                }
                let url = generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: fixture.clip)
                )
                guard FileManager.default.fileExists(atPath: url.path) else { return false }
                return KernelCanonicalHashV1.sha256(try Data(contentsOf: url)) == contentSHA256
            },
            remove: { workspaceID, contentID, contentSHA256 in
                guard workspaceID == fixture.clip.workspaceID,
                      contentID == fixture.clip.original.contentID,
                      contentSHA256 == fixture.clip.original.digests
                        .digest(for: .sha256)?.hexadecimalValue else {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
                let url = generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: fixture.clip)
                )
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        )
    }

    private func coldCleanupRecoveryAdapter() throws
        -> TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1 {
        try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(
            generationRootURL: generationRootURL,
            workspaceID: fixture.clip.workspaceID
        )
    }

    func relaunchedCoordinator(
        failureBoundary: MutationJournalFaultBoundaryV1? = nil
    ) throws -> TemporalEvidenceCoordinatorV1 {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID,
            failureInjection: failureBoundary.map {
                MutationJournalFailureInjectionV1(failOnceAt: $0)
            },
            allowStateBootstrap: false
        )
        try MutationReceiptRecoveryServiceV1(store: store).recoverBeforeWriterActivation()
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: writerInstanceID),
            clock: C33TemporalEvidenceClock(value: fixture.clip.acceptedAt),
            idSource: C33TemporalEvidenceIDSource(value: writerInstanceID),
            fileAuthority: C33TemporalEvidenceFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
        return TemporalEvidenceCoordinatorV1(
            writer: writer,
            content: content,
            scratch: scratch,
            admission: admission,
            recovery: try coldRecoveryAdapter(),
            cleanupRecovery: try coldCleanupRecoveryAdapter(),
            contentCleanup: contentCleanup
        )
    }
}

private struct C33TemporalEvidenceCorpusV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let durableFamilies: [String]
    let evidenceIDs: [String]
    let captureProfiles: [CaptureProfile]
    let writerBoundaries: [String]
    let hostileCases: [String]
    let lifecycle: [String: String]
    let invariants: [String: Bool]
    let statusFlags: [String: Bool]

    struct CaptureProfile: Decodable {
        let profileID: String
        let kind: String
        let maximumDurationMilliseconds: UInt64
        let maximumByteCount: UInt64
        let containers: [String]
        let codecs: [String]
        let maximumPixelWidth: Int?
        let maximumPixelHeight: Int?
        let maximumClipsPerRequirement: Int
        let maximumClipsPerSession: Int
        let minimumFreeByteCount: UInt64
        let reportProjection: String
    }
}

final class V9_49TemporalEvidenceClipTests: XCTestCase {
    private func corpus() throws -> C33TemporalEvidenceCorpusV1 {
        let url = Bundle(for: Self.self).url(
            forResource: "V22P03C33TemporalEvidenceCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V22/TemporalEvidence"
        ) ?? Bundle(for: Self.self).url(
            forResource: "V22P03C33TemporalEvidenceCorpusV1",
            withExtension: "json"
        )
        return try JSONDecoder().decode(
            C33TemporalEvidenceCorpusV1.self,
            from: Data(contentsOf: XCTUnwrap(url))
        )
    }

    @MainActor
    func testV23P03C33G01ReviewedClipPromotesImmutableContentAndOneCanonicalMutation() async throws {
        let harness = try await C33TemporalEvidencePersistentHarness(slot: 40)
        let accepted = try await harness.coordinator.accept(harness.request)
        let fixture = harness.fixture
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: fixture.clip)

        try fixture.clip.validate(profile: fixture.profile)
        try anchor.validate(clip: fixture.clip)
        let reportLink = try TemporalEvidenceReportLinkV1(
            clip: fixture.clip,
            anchors: [anchor],
            profile: fixture.profile
        )
        try TemporalEvidenceReportProjectionPolicyV1.validate(reportLink)
        let searchRecord = try TemporalEvidenceSearchRecordV1(
            clip: fixture.clip,
            anchors: [anchor]
        )
        try TemporalEvidenceSearchProjectionPolicyV1.validate(searchRecord)
        XCTAssertFalse(reportLink.embedsOriginalBytes)
        XCTAssertEqual(searchRecord.clipID, fixture.clip.clipID)
        XCTAssertEqual(anchor.sourceContentID, fixture.clip.original.contentID)
        XCTAssertEqual(anchor.sourceSHA256, fixture.clip.original.digests.digest(for: .sha256)?.hexadecimalValue)
        XCTAssertEqual(fixture.clip.mutationID, try C33TemporalEvidenceTestSupport.mutation(540))
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).first?.value(), fixture.clip)
        XCTAssertEqual(accepted.mutationReceipt.mutationReceipt.mutationID, fixture.clip.mutationID)
        XCTAssertEqual(accepted.contentReceipt.digest, fixture.clip.original.digests.digest(for: .sha256))
        XCTAssertEqual(
            try Data(contentsOf: harness.generationRootURL.appendingPathComponent(accepted.contentReceipt.relativePath)),
            harness.request.completedBytes
        )
        let scratchDispositions = await harness.scratch.recordedDispositions()
        XCTAssertEqual(scratchDispositions, [.acceptedIntoImmutableContent])
        XCTAssertEqual(TemporalEvidencePersistenceEnrollmentV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertEqual(TemporalEvidencePersistenceEnrollmentV1.scratchPersistence, "NONPERSISTENT_BACKUP_EXCLUDED")
        XCTAssertFalse(TemporalEvidencePersistenceEnrollmentV1.secondByteStoreAllowed)
    }

    @MainActor
    func testV23P03C33A01TypedLimitsAnchorsAndReplaceableDerivativesRemainBounded() async throws {
        let audio = try C33TemporalEvidenceTestSupport.clip(slot: 101, kind: .audio)
        let video = try C33TemporalEvidenceTestSupport.clip(slot: 102, kind: .video)
        let audioAnchor = try C33TemporalEvidenceTestSupport.anchor(clip: audio.clip, offsetMilliseconds: 45_000)
        let videoAnchor = try C33TemporalEvidenceTestSupport.anchor(clip: video.clip, offsetMilliseconds: 30_000)
        let waveform = try C33TemporalEvidenceTestSupport.derivative(clip: audio.clip, kind: .waveform)
        let thumbnail = try C33TemporalEvidenceTestSupport.derivative(clip: video.clip, kind: .thumbnail)

        XCTAssertEqual(audio.profile.limit(for: .audio).maximumDurationMilliseconds, 120_000)
        XCTAssertEqual(video.profile.limit(for: .video).maximumPixelWidth, 1_920)
        XCTAssertEqual(audioAnchor.offsetMilliseconds, audio.clip.facts.durationMilliseconds)
        XCTAssertEqual(videoAnchor.offsetMilliseconds, video.clip.facts.durationMilliseconds)
        XCTAssertEqual(waveform.kind, .waveform)
        XCTAssertEqual(thumbnail.kind, .thumbnail)
        XCTAssertEqual(waveform.source.contentID, audio.clip.original.contentID)
        XCTAssertNotEqual(waveform.content.contentID, audio.clip.original.contentID)
        XCTAssertEqual(audio.clip.original.byteRole, .immutableOriginal)
        XCTAssertEqual(waveform.content.byteRole, .derivative)
        XCTAssertEqual(waveform.content.mediaType, "image/png")
        if case .waveform(let metadata) = waveform.provenance.transform {
            XCTAssertEqual(metadata.sampleCount, 1_024)
        } else {
            XCTFail("waveform derivative must retain typed waveform provenance")
        }
        if case .thumbnail(let metadata) = thumbnail.provenance.transform {
            XCTAssertEqual(metadata.pixelWidth, 320)
            XCTAssertEqual(metadata.pixelHeight, 180)
        } else {
            XCTFail("thumbnail derivative must retain typed thumbnail provenance")
        }
        XCTAssertEqual(TemporalEvidenceStopReasonV1.allCases, [
            .durationBound, .byteBound, .requirementCountBound, .sessionCountBound,
            .insufficientStorage, .codecUnavailable, .permissionDenied,
            .protectedDataUnavailable, .interruption, .backgrounded, .cancelled
        ])
        XCTAssertEqual(audio.clip.manualTranscript, "Reviewer-entered temporal evidence transcript.")
        XCTAssertFalse(TemporalEvidencePersistenceEnrollmentV1.automaticTranscriptionEnabled)

        let terminalHarness = try await C33TemporalEvidencePersistentHarness(slot: 150)
        let lease = terminalHarness.request.scratchBinding.lease
        let rejected = try await terminalHarness.coordinator.reject(lease: lease)
        let cancelled = try await terminalHarness.coordinator.cancel(lease: lease)
        let expired = try await terminalHarness.coordinator.expire(lease: lease)
        let failed = try await terminalHarness.coordinator.fail(lease: lease)
        XCTAssertEqual([rejected.disposition, cancelled.disposition, expired.disposition, failed.disposition], [
            .rejected, .cancelled, .expired, .failed
        ])
        XCTAssertTrue([rejected, cancelled, expired, failed].allSatisfy(\.scratchDeleted))
        XCTAssertEqual(try terminalHarness.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 0)
        XCTAssertEqual(try terminalHarness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
    }

    @MainActor
    func testV23P03C33H01InvalidMediaStaleAuthorityAndHostileRuntimeStatesFailClosed() async throws {
        let fixture = try C33TemporalEvidenceTestSupport.clip(slot: 201, kind: .video)
        XCTAssertThrowsError(try C33TemporalEvidenceTestSupport.facts(
            kind: .video,
            byteCount: 67_108_865
        ).validate(against: fixture.profile.video)) { error in
            XCTAssertEqual(error as? TemporalEvidenceContractFailureV1, .limitExceeded)
        }
        XCTAssertThrowsError(try C33TemporalEvidenceTestSupport.anchor(
            clip: fixture.clip,
            offsetMilliseconds: fixture.clip.facts.durationMilliseconds + 1
        )) { error in
            XCTAssertEqual(error as? TemporalEvidenceContractFailureV1, .staleSource)
        }
        XCTAssertThrowsError(try TemporalEvidenceCodecV1(
            container: " mp4",
            codec: "h264",
            mediaType: "video/mp4"
        ))
        let unavailableCodec = try TemporalEvidenceCodecV1(
            container: "webm",
            codec: "vp9",
            mediaType: "video/webm"
        )
        XCTAssertThrowsError(try TemporalEvidenceMediaFactsV1(
            kind: .video,
            durationMilliseconds: 1_000,
            byteCount: 1_024,
            codec: unavailableCodec,
            pixelWidth: 640,
            pixelHeight: 480
        ).validate(against: fixture.profile.video)) { error in
            XCTAssertEqual(error as? TemporalEvidenceContractFailureV1, .limitExceeded)
        }
        XCTAssertEqual(TemporalEvidenceContractFailureV1.hostileRuntimeFailures, [
            .insufficientStorage, .unsupportedMedia, .interruption
        ])

        let hostileCases = Set(try corpus().hostileCases)
        XCTAssertTrue(Set([
            "INCOMING_CALL_INTERRUPTION", "LOW_DISK", "CODEC_UNAVAILABLE",
            "PROTECTED_DATA_LOCKED", "APP_BACKGROUNDED", "OVERSIZED_IMPORT",
            "PERMISSION_DENIED", "CAPTURE_CANCELLED", "CONTENT_DIGEST_TAMPERED",
            "WRONG_WORKSPACE", "UNKNOWN_SCHEMA_VERSION"
        ]).isSubset(of: hostileCases))
        XCTAssertThrowsError(try TemporalEvidenceCanonicalCodecV1.decode(
            TemporalEvidenceClipV1.self,
            from: Data(repeating: 0, count: TemporalEvidenceCanonicalCodecV1.maximumCanonicalBytes + 1)
        )) { error in
            XCTAssertEqual(error as? TemporalEvidenceContractFailureV1, .limitExceeded)
        }
        var unknownObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: TemporalEvidenceCanonicalCodecV1.encode(fixture.clip))
                as? [String: Any]
        )
        unknownObject["schemaVersion"] = 999
        XCTAssertThrowsError(try TemporalEvidenceCanonicalCodecV1.decode(
            TemporalEvidenceClipV1.self,
            from: JSONSerialization.data(withJSONObject: unknownObject, options: [.sortedKeys])
        ))

        let tamperedHarness = try await C33TemporalEvidencePersistentHarness(slot: 220)
        var tampered = tamperedHarness.request.completedBytes
        tampered[0] ^= 0xff
        XCTAssertThrowsError(try TemporalEvidenceAcceptanceRequestV1(
            clip: tamperedHarness.request.clip,
            profile: tamperedHarness.request.profile,
            review: tamperedHarness.request.review,
            expectedRevision: tamperedHarness.request.expectedRevision,
            scratchBinding: tamperedHarness.request.scratchBinding,
            admissionReceipt: tamperedHarness.request.admissionReceipt,
            completedBytes: tampered
        )) { error in
            XCTAssertEqual(error as? TemporalEvidenceContractFailureV1, .digestMismatch)
        }
        let wrongWorkspaceExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: C33TemporalEvidenceTestSupport.workspace(999),
            generationID: tamperedHarness.generationID,
            writerInstanceID: tamperedHarness.writerInstanceID,
            workspaceRevision: 0,
            entityRevisions: []
        )
        XCTAssertThrowsError(try TemporalEvidenceAcceptanceRequestV1(
            clip: tamperedHarness.request.clip,
            profile: tamperedHarness.request.profile,
            review: tamperedHarness.request.review,
            expectedRevision: wrongWorkspaceExpected,
            scratchBinding: tamperedHarness.request.scratchBinding,
            admissionReceipt: tamperedHarness.request.admissionReceipt,
            completedBytes: tamperedHarness.request.completedBytes
        ))

        let lowSpace = try await C33TemporalEvidencePersistentHarness(slot: 221)
        await lowSpace.admission.replace(with: try TemporalEvidenceAdmissionSnapshotV1(
            expectedRevision: lowSpace.request.expectedRevision,
            profile: lowSpace.fixture.profile,
            clipsForRequirement: 0,
            clipsForSession: 0,
            availableByteCount: lowSpace.fixture.profile.minimumFreeByteCount - 1,
            evaluatedAt: lowSpace.fixture.clip.acceptedAt
        ))
        do {
            _ = try await lowSpace.coordinator.accept(lowSpace.request)
            XCTFail("low-space admission must fail")
        } catch let failure as TemporalEvidenceContractFailureV1 {
            XCTAssertEqual(failure, .insufficientStorage)
        }
        XCTAssertEqual(try lowSpace.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 0)
        XCTAssertEqual(try lowSpace.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)

        let staleAuthority = try await C33TemporalEvidencePersistentHarness(slot: 222)
        await staleAuthority.admission.replace(with: try TemporalEvidenceAdmissionSnapshotV1(
            expectedRevision: C33TemporalEvidenceTestSupport.expectedRevision(
                for: staleAuthority.fixture.clip,
                generationID: C33TemporalEvidenceTestSupport.id(999),
                writerInstanceID: staleAuthority.writerInstanceID
            ),
            profile: staleAuthority.fixture.profile,
            clipsForRequirement: 0,
            clipsForSession: 0,
            availableByteCount: staleAuthority.fixture.profile.minimumFreeByteCount
                + staleAuthority.fixture.clip.facts.byteCount,
            evaluatedAt: staleAuthority.fixture.clip.acceptedAt
        ))
        do {
            _ = try await staleAuthority.coordinator.accept(staleAuthority.request)
            XCTFail("trusted expected-token mismatch must fail")
        } catch let failure as TemporalEvidenceContractFailureV1 {
            XCTAssertEqual(failure, .staleSource)
        }
        XCTAssertEqual(try staleAuthority.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 0)
        XCTAssertEqual(try staleAuthority.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
    }

    @MainActor
    func testV23P03C33I01EveryWriterBoundaryRecoversZeroOrCompleteWithoutOrphans() async throws {
        let corpus = try corpus()
        XCTAssertEqual(Set(corpus.writerBoundaries), Set([
            "BEFORE_VALIDATION",
            "AFTER_VALIDATION_BEFORE_SCRATCH_PROMOTION",
            "AFTER_ORIGINAL_PROMOTION_BEFORE_CANONICAL_EFFECT",
            "AFTER_CANONICAL_EFFECT_BEFORE_RECEIPT",
            "AFTER_RECEIPT_BEFORE_SCRATCH_CLEANUP",
            "AFTER_DERIVATIVE_WRITE_BEFORE_PUBLICATION",
            "AFTER_ASSOCIATION_COMMIT_BEFORE_RECEIPT"
        ]))
        XCTAssertEqual(
            corpus.lifecycle["scratch"],
            "DELETE_ON_CANCEL_CRASH_PERMISSION_LOSS_OR_DISK_PRESSURE"
        )
        XCTAssertEqual(corpus.lifecycle["retry"], "SAME_EFFECT_AND_RECEIPT_OR_NO_EFFECT")

        let scratchRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "C33-I01-scratch-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchRoot) }
        let scratchStore = try ScratchDataLeaseStoreV1(
            applicationSupportURL: scratchRoot,
            clock: { C33TemporalEvidenceTestSupport.fixedDate },
            capacityProvider: { _ in Int64.max }
        )
        let scratchLifecycle = TemporalEvidenceScratchLifecycleAdapterV1(
            base: CapabilityScratchLeaseAdapterV1(scratch: scratchStore)
        )
        let scratchRequest = try CapabilityScratchLeaseRequestV1(
            leaseID: C33TemporalEvidenceTestSupport.id(360),
            operationID: C33TemporalEvidenceTestSupport.id(361),
            purpose: .capture,
            requestedByteCount: 4_096,
            createdAt: C33TemporalEvidenceTestSupport.fixedDate,
            expiresAt: C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(1)
        )
        let realLease = try await scratchLifecycle.acquire(scratchRequest)
        let realScratchURL = try await scratchLifecycle.write(
            Data(repeating: 0x33, count: 4_096),
            named: "completed.bin",
            lease: realLease
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: realScratchURL.path))
        let coldStore = try ScratchDataLeaseStoreV1(
            applicationSupportURL: scratchRoot,
            clock: { C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(2) },
            capacityProvider: { _ in Int64.max }
        )
        let coldLifecycle = TemporalEvidenceScratchLifecycleAdapterV1(
            base: CapabilityScratchLeaseAdapterV1(scratch: coldStore)
        )
        let coldSummary = try await coldLifecycle.recoverAfterInterruption()
        XCTAssertEqual(coldSummary.recoveredExpiredLeaseCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: realScratchURL.path))

        for (index, boundary) in MutationJournalFaultBoundaryV1.allCases.enumerated() {
            let harness = try await C33TemporalEvidencePersistentHarness(
                slot: 300 + index,
                failureBoundary: boundary
            )
            do {
                _ = try await harness.coordinator.accept(harness.request)
                XCTFail("expected injected boundary \(boundary)")
            } catch let failure as MutationJournalFailureV1 {
                XCTAssertEqual(failure, .injected(boundary))
            }

            let relaunched = try harness.relaunchedCoordinator()
            _ = try await relaunched.recoverAfterInterruption()
            let recovered = try await relaunched.accept(harness.request)
            let idempotent = try await relaunched.accept(harness.request)
            XCTAssertEqual(idempotent.mutationReceipt, recovered.mutationReceipt)
            XCTAssertEqual(idempotent.contentReceipt.digest, recovered.contentReceipt.digest)
            XCTAssertTrue(idempotent.contentReceipt.reusedExistingBytes)

            let auditContext = ModelContext(harness.container)
            XCTAssertEqual(try auditContext.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 1)
            XCTAssertEqual(try auditContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
            XCTAssertEqual(
                try auditContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).first?.value(),
                harness.fixture.clip
            )
            XCTAssertEqual(
                try Data(contentsOf: harness.generationRootURL.appendingPathComponent(recovered.contentReceipt.relativePath)),
                harness.request.completedBytes
            )
            let dispositions = await harness.scratch.recordedDispositions()
            XCTAssertTrue(dispositions.allSatisfy { $0 == .acceptedIntoImmutableContent })
        }

        for (index, fault) in [
            C33TemporalEvidenceRecoveryFault.afterPrepared,
            .afterOriginalPromoted
        ].enumerated() {
            let harness = try await C33TemporalEvidencePersistentHarness(
                slot: 330 + index,
                recoveryFault: fault
            )
            do {
                _ = try await harness.coordinator.accept(harness.request)
                XCTFail("expected promotion recovery fault \(fault)")
            } catch let failure as TemporalEvidenceContractFailureV1 {
                XCTAssertEqual(failure, .interruption)
            }
            let originalURL = harness.generationRootURL.appendingPathComponent(
                try TemporalEvidenceBackupMemberV1.original(for: harness.fixture.clip)
            )
            let relaunched = try harness.relaunchedCoordinator()
            _ = try await relaunched.recoverAfterInterruption()
            XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
            _ = try await relaunched.accept(harness.request)
            XCTAssertEqual(
                try harness.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()),
                1
            )
            XCTAssertEqual(
                try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
                1
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        }

        let cleanupFault = try await C33TemporalEvidencePersistentHarness(
            slot: 340,
            failAcceptedScratchFinishOnce: true
        )
        do {
            _ = try await cleanupFault.coordinator.accept(cleanupFault.request)
            XCTFail("expected accepted scratch cleanup interruption")
        } catch let failure as TemporalEvidenceContractFailureV1 {
            XCTAssertEqual(failure, .interruption)
        }
        let cleanupRelaunch = try cleanupFault.relaunchedCoordinator()
        _ = try await cleanupRelaunch.recoverAfterInterruption()
        let cleanupRecovered = try await cleanupRelaunch.accept(cleanupFault.request)
        XCTAssertTrue(cleanupRecovered.contentReceipt.reusedExistingBytes)
        XCTAssertEqual(
            try cleanupFault.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()),
            1
        )
        XCTAssertEqual(
            try cleanupFault.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            1
        )

        let associationFault = try await C33TemporalEvidencePersistentHarness(slot: 345)
        _ = try await associationFault.coordinator.accept(associationFault.request)
        let associationAnchor = try C33TemporalEvidenceTestSupport.anchor(
            clip: associationFault.fixture.clip,
            slot: 346
        )
        let associationCurrent = try associationFault.store.currentRevision(
            writerInstanceID: associationFault.writerInstanceID
        )
        let associationExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: associationCurrent.workspaceID,
            generationID: associationCurrent.generationID,
            writerInstanceID: associationCurrent.writerInstanceID,
            workspaceRevision: associationCurrent.revision,
            entityRevisions: [WorkspaceEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(
                    kind: .timecodedEvidenceAnchor,
                    id: associationAnchor.anchorID
                ),
                revision: 0
            )]
        )
        let faultingAssociation = try associationFault.relaunchedCoordinator(
            failureBoundary: .afterEffectBeforeReceipt
        )
        XCTAssertThrowsError(try faultingAssociation.appendAnchor(
            associationAnchor,
            clip: associationFault.fixture.clip,
            predecessor: nil,
            expectedRevision: associationExpected
        ))
        let recoveredAssociation = try associationFault.relaunchedCoordinator()
        let recoveredAnchorReceipt = try recoveredAssociation.appendAnchor(
            associationAnchor,
            clip: associationFault.fixture.clip,
            predecessor: nil,
            expectedRevision: associationExpected
        )
        XCTAssertEqual(recoveredAnchorReceipt.mutationReceipt.mutationID, associationAnchor.mutationID)
        XCTAssertEqual(
            try associationFault.context.fetchCount(FetchDescriptor<TimecodedEvidenceAnchorRow>()),
            1
        )
        XCTAssertEqual(
            try associationFault.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            2
        )

        let derivativeHarness = try await C33TemporalEvidencePersistentHarness(slot: 370)
        _ = try await derivativeHarness.coordinator.accept(derivativeHarness.request)
        let derivative = try C33TemporalEvidenceTestSupport.derivative(
            clip: derivativeHarness.fixture.clip,
            slot: 371
        )
        let derivativeDigest = try XCTUnwrap(
            derivative.content.digests.digest(for: .sha256)
        )
        let derivativeRequest = try DraftImmutableContentWriteRequestV1(
            workspaceID: derivative.workspaceID,
            contentID: derivative.content.contentID,
            digest: derivativeDigest,
            byteLength: derivative.content.byteLength,
            mediaType: derivative.content.mediaType,
            mutationID: derivative.mutationID,
            createdAt: derivative.content.createdAt
        )
        let derivativeReceipt = try await EvidenceBundleStore(
            generationRootURL: derivativeHarness.generationRootURL
        ).persistImmutableOriginal(
            bytes: C33TemporalEvidenceTestSupport.bytes(for: derivativeHarness.fixture.clip.facts.kind),
            request: derivativeRequest
        )
        let derivativeURL = derivativeHarness.generationRootURL.appendingPathComponent(
            derivativeReceipt.relativePath
        )
        let originalURL = derivativeHarness.generationRootURL.appendingPathComponent(
            try TemporalEvidenceBackupMemberV1.original(for: derivativeHarness.fixture.clip)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: derivativeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        try derivativeHarness.coordinator.validateDerivativeReplacement(
            derivative,
            clip: derivativeHarness.fixture.clip,
            predecessor: nil
        )
        let association = try TemporalEvidenceReportLinkV1(
            clip: derivativeHarness.fixture.clip,
            anchors: [C33TemporalEvidenceTestSupport.anchor(clip: derivativeHarness.fixture.clip)],
            profile: derivativeHarness.fixture.profile
        )
        try TemporalEvidenceReportProjectionPolicyV1.validate(association)
        XCTAssertEqual(association.contentID, derivativeHarness.fixture.clip.original.contentID)
        let cleanup = try OrphanFileCleanupService(
            generationRootURL: derivativeHarness.generationRootURL
        )
        let cleanupSummary = try cleanup.removeCanonicalContentIfUnreferenced(
            reference: derivative.content,
            locator: derivative.locator,
            liveClipContentIDs: [derivativeHarness.fixture.clip.original.contentID],
            liveReportContentIDs: [association.contentID],
            reservedContentIDs: [],
            recoveryContentIDs: []
        )
        XCTAssertEqual(cleanupSummary.removedFileCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: derivativeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))

        let recoveryHarness = try await C33TemporalEvidencePersistentHarness(slot: 350)
        let summary = try await recoveryHarness.coordinator.recoverAfterInterruption()
        XCTAssertEqual(summary.recoveredExpiredLeaseCount, 1)
        let recoveryCount = await recoveryHarness.scratch.recordedRecoveryCount()
        XCTAssertEqual(recoveryCount, 1)
    }

    @MainActor
    func testV23P03C33R01BackupRestoreReplayDeleteEraseAndRetentionRemainExact() async throws {
        let harness = try await C33TemporalEvidencePersistentHarness(slot: 401)
        let accepted = try await harness.coordinator.accept(harness.request)
        let fixture = harness.fixture
        let retention = try TemporalEvidenceRetentionEventV1(
            eventID: C33TemporalEvidenceTestSupport.id(402),
            clip: fixture.clip,
            disposition: .removeRegenerableDerivatives,
            policySHA256: String(repeating: "d", count: 64),
            actor: C26SurveySessionTestSupport.actor(
                workspaceID: fixture.clip.workspaceID,
                slot: 403,
                responsibility: .reviewedBy
            ),
            occurredAt: C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(30),
            revision: 1,
            mutationID: C33TemporalEvidenceTestSupport.mutation(404)
        )
        try retention.validate(clip: fixture.clip)
        XCTAssertEqual(TemporalEvidenceRetentionDispositionV1.allCases, [
            .retain, .removeRegenerableDerivatives, .deleteClip, .eraseWorkspace
        ])
        XCTAssertTrue(TemporalEvidencePersistenceEnrollmentV1.persistentFamilies.contains("TemporalEvidenceClipRow"))
        XCTAssertTrue(TemporalEvidencePersistenceEnrollmentV1.persistentFamilies.contains("TimecodedEvidenceAnchorRow"))
        XCTAssertFalse(TemporalEvidencePersistenceEnrollmentV1.immutableOriginalsAreRewritten)

        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: fixture.clip, slot: 405)
        let current = try harness.store.currentRevision(writerInstanceID: harness.writerInstanceID)
        let anchorExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .timecodedEvidenceAnchor,
                        id: anchor.anchorID
                    ),
                    revision: 0
                )
            ]
        )
        let anchorReceipt = try harness.coordinator.appendAnchor(
            anchor,
            clip: fixture.clip,
            predecessor: nil,
            expectedRevision: anchorExpected
        )
        let sameAnchorReceipt = try harness.coordinator.appendAnchor(
            anchor,
            clip: fixture.clip,
            predecessor: nil,
            expectedRevision: anchorExpected
        )
        XCTAssertEqual(sameAnchorReceipt, anchorReceipt)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<TimecodedEvidenceAnchorRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>()).first?.value(), anchor)
        XCTAssertEqual(
            try harness.writer.temporalEvidenceReceipt(mutationID: fixture.clip.mutationID),
            accepted.mutationReceipt.mutationReceipt
        )

        for expected in [
            try C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                generationID: C33TemporalEvidenceTestSupport.id(990),
                writerInstanceID: harness.writerInstanceID
            ),
            try C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                generationID: harness.generationID,
                writerInstanceID: C33TemporalEvidenceTestSupport.id(991)
            ),
            try C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                generationID: harness.generationID,
                writerInstanceID: harness.writerInstanceID,
                workspaceRevision: 99
            )
        ] {
            let hostile = try TemporalEvidenceMutationV1(
                workspaceID: fixture.clip.workspaceID,
                expectedRevision: expected,
                mutationID: fixture.clip.mutationID,
                payload: .acceptClip(
                    fixture.clip,
                    review: C33TemporalEvidenceTestSupport.review(for: fixture.clip),
                    predecessor: nil
                )
            )
            XCTAssertThrowsError(try harness.writer.commitTemporalEvidence(hostile))
        }
        XCTAssertThrowsError(try TemporalEvidenceMutationV1(
            workspaceID: fixture.clip.workspaceID,
            expectedRevision: C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                entityRevision: 1
            ),
            mutationID: fixture.clip.mutationID,
            payload: .acceptClip(
                fixture.clip,
                review: C33TemporalEvidenceTestSupport.review(for: fixture.clip),
                predecessor: nil
            )
        ))

        let deleteHarness = try await C33TemporalEvidencePersistentHarness(slot: 460)
        _ = try await deleteHarness.coordinator.accept(deleteHarness.request)
        let deleteCurrent = try deleteHarness.store.currentRevision(
            writerInstanceID: deleteHarness.writerInstanceID
        )
        let deleteExpected = try C33TemporalEvidenceTestSupport.expectedRevision(
            for: deleteHarness.fixture.clip,
            generationID: deleteCurrent.generationID,
            writerInstanceID: deleteCurrent.writerInstanceID,
            workspaceRevision: deleteCurrent.revision,
            entityRevision: deleteHarness.fixture.clip.revision
        )
        let deleteEvent = try TemporalEvidenceRetentionEventV1(
            eventID: C33TemporalEvidenceTestSupport.id(461),
            clip: deleteHarness.fixture.clip,
            disposition: .deleteClip,
            policySHA256: String(repeating: "f", count: 64),
            actor: C26SurveySessionTestSupport.actor(
                workspaceID: deleteHarness.fixture.clip.workspaceID,
                slot: 462,
                responsibility: .reviewedBy
            ),
            occurredAt: C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(60),
            revision: 1,
            mutationID: C33TemporalEvidenceTestSupport.mutation(463)
        )
        let deleteURL = deleteHarness.generationRootURL.appendingPathComponent(
            try TemporalEvidenceBackupMemberV1.original(for: deleteHarness.fixture.clip)
        )
        let deleteReceipt = try await deleteHarness.coordinator.removeClip(
            deleteEvent,
            clips: [deleteHarness.fixture.clip],
            anchors: [],
            derivatives: [],
            predecessorEvent: nil,
            expectedRevision: deleteExpected
        )
        let repeatedDeleteReceipt = try await deleteHarness.coordinator.removeClip(
            deleteEvent,
            clips: [deleteHarness.fixture.clip],
            anchors: [],
            derivatives: [],
            predecessorEvent: nil,
            expectedRevision: deleteExpected
        )
        XCTAssertEqual(repeatedDeleteReceipt, deleteReceipt)
        XCTAssertEqual(
            try deleteHarness.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()),
            0
        )
        XCTAssertEqual(
            try deleteHarness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            2
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleteURL.path))

        let value = try corpus()
        XCTAssertEqual(value.schema, "V22P03C33TemporalEvidenceCorpusV1")
        XCTAssertEqual(value.cardID, "V23-P03-C33")
        XCTAssertEqual(value.persistentSchemaVersion, 33)
        XCTAssertEqual(value.recordsSchemaVersion, 32)
        XCTAssertEqual(value.durableFamilies, ["TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"])
        XCTAssertEqual(value.evidenceIDs, [
            "V23-P03-C33-G01", "V23-P03-C33-A01", "V23-P03-C33-H01",
            "V23-P03-C33-I01", "V23-P03-C33-R01"
        ])
        XCTAssertTrue(value.invariants["noSecondByteStore"] == true)
        XCTAssertTrue(value.invariants["noRuntimeProvider"] == true)
        XCTAssertTrue(value.statusFlags["physicalDeviceEvidence"] == false)
        try await C33TemporalEvidenceTestSupport.verifyRealBackupRestoreDeleteAndErase(slot: 520)
    }
}

private extension TemporalEvidenceContractFailureV1 {
    static var hostileRuntimeFailures: [Self] {
        [.insufficientStorage, .unsupportedMedia, .interruption]
    }
}
private final class C46V949TemporalCompatibilityTests: XCTestCase {
    func testC46TemporalEvidenceCannotBecomeContactHistory() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "temporal-evidence",
            kind: .phone,
            handoff: .text,
            slot: 46049
        )
    }
}

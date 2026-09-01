import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_88TemporalEvidenceCaptureTests: XCTestCase {
    func testV23P04C25G01BoundedOfflineAudioVideoCaptureReviewAndUse() async throws {
        let trace = C25Trace()
        for (offset, kind) in [TemporalEvidenceMediaKindV1.audio, .video].enumerated() {
            let bundle = try C25Support.bundle(kind: kind, slot: 900 + offset * 20)
            let canonical = C25Canonical(operationID: bundle.clip.mutationID.rawValue)
            let runtime = C25Runtime()
            let scratch = C25Scratch()
            let coordinator = C25Support.coordinator(
                bundle: bundle, trace: trace, canonical: canonical, runtime: runtime,
                scratch: scratch
            )
            let start = try await coordinator.start(bundle.request)
            let review = try XCTUnwrap(start.review)
            XCTAssertEqual(start.disposition, .reviewRequired)
            XCTAssertNil(start.fallback)
            XCTAssertEqual(
                try review.scrub(to: review.pendingReview.facts.durationMilliseconds / 2)
                    .playbackOffsetMilliseconds,
                review.pendingReview.facts.durationMilliseconds / 2
            )
            XCTAssertEqual(review.pendingReview.leaseID, review.scratchBinding.lease.leaseID)
            XCTAssertEqual(review.pendingReview.byteCount, bundle.clip.facts.byteCount)
            XCTAssertFalse(Mirror(reflecting: review.pendingReview).children.contains { $0.value is Data })
            let writes = await scratch.writeRecords()
            XCTAssertEqual(writes.count, 1)
            XCTAssertEqual(writes[0].byteCount, bundle.clip.facts.byteCount)
            XCTAssertEqual(
                writes[0].maximumByteCount,
                bundle.request.profile.limit(for: kind).maximumByteCount
            )
            XCTAssertEqual(writes[0].relativeName, review.pendingReview.relativeName)
            let presentation = try TemporalEvidenceRecordingPresentationV1(
                disposition: .recording,
                statusTextKey: TemporalEvidenceLocalizationKeyV1.recording.rawValue,
                statusIconName: "record.circle",
                elapsedMilliseconds: 1_000,
                remainingMilliseconds: review.pendingReview.facts.durationMilliseconds - 1_000,
                remainingByteCount: review.request.profile.limit(for: kind).maximumByteCount
                    - review.pendingReview.facts.byteCount
            )
            XCTAssertFalse(presentation.usesColorAsSoleIndicator)
            if kind == .audio {
                _ = try AudioEvidenceCaptureFlowV1(request: bundle.request, disposition: .reviewRequired, review: review)
            } else {
                _ = try VideoEvidenceCaptureFlowV1(request: bundle.request, disposition: .reviewRequired, review: review)
            }
            XCTAssertEqual(canonical.useCount, 0, "capture and review must not write automatically")
            do {
                _ = try await coordinator.useRecording(
                    review, clip: bundle.clip,
                    review: try C33TemporalEvidenceTestSupport.review(for: bundle.clip)
                )
                XCTFail("the recording canonical spy deliberately stops at the writer boundary")
            } catch C25Probe.writerBoundary { }
            XCTAssertEqual(canonical.useCount, 1, "only explicit Use Recording reaches the canonical boundary")
            let readCount = await scratch.pendingReviewReadCount()
            XCTAssertEqual(readCount, 1,
                           "Use Recording must reread and digest-validate lease bytes")
        }
        let events = await trace.values()
        XCTAssertEqual(events.first, "access")
        XCTAssertEqual(events.filter { $0 == "access" }.count, 2)
    }

    func testV23P04C25A01IndependentPermissionsBoundsDiskAndManualFallback() async throws {
        let audio = try C25Support.bundle(kind: .audio, slot: 940)
        let deniedTrace = C25Trace()
        let deniedRuntime = C25Runtime()
        let denied = C25Support.coordinator(
            bundle: audio, trace: deniedTrace,
            permissions: [.audioCapture: .authorized, .microphone: .denied],
            canonical: C25Canonical(operationID: audio.clip.mutationID.rawValue),
            runtime: deniedRuntime
        )
        let fallback = try await denied.start(audio.request)
        XCTAssertEqual(fallback.disposition, .manualFallback)
        XCTAssertEqual(fallback.fallback, .textOrPhoto)
        let deniedCaptureCount = await deniedRuntime.captureCount()
        let deniedEvents = await deniedTrace.values()
        XCTAssertEqual(deniedCaptureCount, 0)
        XCTAssertEqual(deniedEvents.first, "access")

        let video = try C25Support.bundle(kind: .video, slot: 960)
        let videoRuntime = C25Runtime()
        let allowedVideo = C25Support.coordinator(
            bundle: video, trace: C25Trace(),
            permissions: [.camera: .authorized, .videoCapture: .authorized],
            canonical: C25Canonical(operationID: video.clip.mutationID.rawValue),
            runtime: videoRuntime
        )
        let allowedVideoStart = try await allowedVideo.start(video.request)
        XCTAssertNotNil(allowedVideoStart.review)
        let videoCaptureCount = await videoRuntime.captureCount()
        XCTAssertEqual(videoCaptureCount, 1,
                       "audio denial must not disable the independent video matrix")

        let lowStorage = C25Support.coordinator(
            bundle: audio, trace: C25Trace(),
            canonical: C25Canonical(operationID: audio.clip.mutationID.rawValue),
            runtime: C25Runtime(), availableBytes: audio.clip.limitProfile.minimumFreeByteCount - 1
        )
        let lowStorageResult = try await lowStorage.start(audio.request)
        XCTAssertEqual(lowStorageResult.disposition, .manualFallback)
        XCTAssertEqual(lowStorageResult.fallback, .textOrPhoto)
    }

    func testV23P04C25H01HostileCodecResolutionDurationSizeCountAndProhibitedProcessing() throws {
        let fixture = try corpus()
        XCTAssertEqual(fixture.hostileCases.count, 12)
        let audio = try C33TemporalEvidenceTestSupport.profile()
        XCTAssertThrowsError(try TemporalEvidenceMediaFactsV1(
            kind: .audio,
            durationMilliseconds: audio.audio.maximumDurationMilliseconds + 1,
            byteCount: 1,
            codec: C33TemporalEvidenceTestSupport.codec(for: .audio)
        ).validate(against: audio.audio))
        XCTAssertThrowsError(try TemporalEvidenceMediaFactsV1(
            kind: .video, durationMilliseconds: 1, byteCount: 1,
            codec: C33TemporalEvidenceTestSupport.codec(for: .video),
            pixelWidth: (audio.video.maximumPixelWidth ?? 0) + 1,
            pixelHeight: audio.video.maximumPixelHeight
        ).validate(against: audio.video))
        XCTAssertFalse(TemporalEvidenceCapturePolicyV1.automaticUploadAllowed)
        XCTAssertFalse(TemporalEvidenceCapturePolicyV1.automaticTranscriptionOrRedactionAllowed)
        XCTAssertTrue(TemporalEvidenceCapturePolicyV1.foregroundOnly)
        XCTAssertFalse(TemporalEvidenceCaptureLifecycleDeclarationV1.networkAllowed)
        XCTAssertFalse(TemporalEvidenceCaptureLifecycleDeclarationV1.backgroundOrAmbientCaptureAllowed)
        XCTAssertFalse(TemporalEvidenceCaptureRuntimeAdoptionV1.secondScratchOrContentStoreAllowed)
        XCTAssertFalse(TemporalEvidencePersistenceEnrollmentV1.automaticTranscriptionEnabled)
        XCTAssertFalse(TemporalEvidencePersistenceEnrollmentV1.secondByteStoreAllowed)
    }

    func testV23P04C25I01InterruptionRetakeDeleteAndScratchCleanupRecovery() async throws {
        let failedBundle = try C25Support.bundle(kind: .audio, slot: 980)
        let failedScratch = C25Scratch()
        let failedRuntime = C25Runtime(failure: .interrupted)
        let failed = C25Support.coordinator(
            bundle: failedBundle, trace: C25Trace(),
            canonical: C25Canonical(operationID: failedBundle.clip.mutationID.rawValue),
            runtime: failedRuntime, scratch: failedScratch
        )
        await XCTAssertThrowsErrorAsync(try await failed.start(failedBundle.request)) {
            XCTAssertEqual($0 as? TemporalEvidenceCaptureFailureV1, .interrupted)
        }
        let failedFinishes = await failedScratch.finishDispositions()
        let failedStops = await failedRuntime.stopReasons()
        XCTAssertEqual(failedFinishes, [.failed])
        XCTAssertEqual(failedStops, [.interruption])

        for (slot, action) in [(1_000, "delete"), (1_020, "retake")] {
            let bundle = try C25Support.bundle(kind: .video, slot: slot)
            let canonical = C25Canonical(operationID: bundle.clip.mutationID.rawValue)
            let coordinator = C25Support.coordinator(
                bundle: bundle, trace: C25Trace(), canonical: canonical, runtime: C25Runtime()
            )
            let start = try await coordinator.start(bundle.request)
            let review = try XCTUnwrap(start.review)
            let receipt = action == "delete"
                ? try await coordinator.delete(review)
                : try await coordinator.retake(review)
            XCTAssertEqual(receipt.disposition, .rejected)
            XCTAssertTrue(receipt.scratchDeleted)
            XCTAssertEqual(canonical.terminalCount, 1)
        }

        let recoveryCanonical = C25Canonical(operationID: failedBundle.clip.mutationID.rawValue)
        let recovery = C25Support.coordinator(
            bundle: failedBundle, trace: C25Trace(), canonical: recoveryCanonical,
            runtime: C25Runtime()
        )
        let firstRecovery = try await recovery.recoverAfterInterruption()
        let secondRecovery = try await recovery.recoverAfterInterruption()
        XCTAssertEqual(firstRecovery.recoveredExpiredLeaseCount, 1)
        XCTAssertEqual(secondRecovery.recoveredExpiredLeaseCount, 1)
        XCTAssertEqual(recoveryCanonical.recoveryCount, 2)
        XCTAssertEqual(recoveryCanonical.useCount, 0, "recovery must not fabricate or reapply acceptance")

        let pendingBundle = try C25Support.bundle(kind: .audio, slot: 1_030)
        let pendingScratch = C25Scratch()
        let pendingCanonical = C25Canonical(operationID: pendingBundle.clip.mutationID.rawValue)
        let pendingCoordinator = C25Support.coordinator(
            bundle: pendingBundle, trace: C25Trace(), canonical: pendingCanonical,
            runtime: C25Runtime(), scratch: pendingScratch
        )
        let pendingStart = try await pendingCoordinator.start(pendingBundle.request)
        let pendingReview = try XCTUnwrap(pendingStart.review)
        let restored = try await pendingCoordinator.recoverAfterInterruption(
            pendingReview: pendingReview
        )
        XCTAssertEqual(restored, pendingReview)
        let restoredReadCount = await pendingScratch.pendingReviewReadCount()
        XCTAssertEqual(restoredReadCount, 1)
        await pendingScratch.corruptPendingReview(for: pendingReview.scratchBinding.lease.leaseID)
        let cleaned = try await pendingCoordinator.recoverAfterInterruption(
            pendingReview: pendingReview
        )
        XCTAssertNil(cleaned)
        let pendingFinishes = await pendingScratch.finishDispositions()
        XCTAssertEqual(pendingFinishes.last, .expired)
        XCTAssertEqual(pendingCanonical.recoveryCount, 1)

        let recoveryBundle = try C25Support.bundle(kind: .audio, slot: 1_040)
        let recoveryStart = try await C25Support.coordinator(
            bundle: recoveryBundle, trace: C25Trace(),
            canonical: C25Canonical(operationID: recoveryBundle.clip.mutationID.rawValue),
            runtime: C25Runtime()
        ).start(recoveryBundle.request)
        let recoveryReview = try XCTUnwrap(recoveryStart.review)
        let reservation = try TemporalEvidencePromotionReservationV1(
            workspaceID: recoveryBundle.clip.workspaceID,
            mutationID: recoveryBundle.clip.mutationID,
            contentID: recoveryBundle.clip.original.contentID,
            contentSHA256: recoveryReview.scratchBinding.contentSHA256,
            binding: recoveryReview.scratchBinding,
            state: .prepared
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-P04-C25-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let effects = C25RecoveryEffects()
        let store = try TemporalEvidencePromotionRecoveryFileAdapterV1(
            generationRootURL: directory,
            workspaceID: recoveryBundle.clip.workspaceID,
            verify: { _, _, _ in await effects.verify() },
            remove: { _, _, _ in await effects.remove() }
        )
        try await store.prepare(reservation)
        try await store.prepare(reservation)
        let reopenedPrepared = try TemporalEvidencePromotionRecoveryFileAdapterV1(
            generationRootURL: directory,
            workspaceID: recoveryBundle.clip.workspaceID,
            verify: { _, _, _ in await effects.verify() },
            remove: { _, _, _ in await effects.remove() }
        )
        let preparedPending = try await reopenedPrepared.recoverPending()
        XCTAssertEqual(preparedPending, [reservation])
        try await reopenedPrepared.transition(reservation, to: .originalPromoted)
        let reopenedPromoted = try TemporalEvidencePromotionRecoveryFileAdapterV1(
            generationRootURL: directory,
            workspaceID: recoveryBundle.clip.workspaceID,
            verify: { _, _, _ in await effects.verify() },
            remove: { _, _, _ in await effects.remove() }
        )
        let promotedPending = try await reopenedPromoted.recoverPending()
        XCTAssertEqual(promotedPending.count, 1)
        try await reopenedPromoted.removeUncommittedContent(reservation)
        try await reopenedPromoted.transition(reservation, to: .finished)
        try await reopenedPromoted.remove(reservation)
        let finishedPending = try await reopenedPromoted.recoverPending()
        let removalCount = await effects.removeCount()
        XCTAssertTrue(finishedPending.isEmpty)
        XCTAssertEqual(removalCount, 1)
    }

    func testV23P04C25R01ReportPosterMetadataLinkAndLifecycleRecovery() throws {
        for (slot, kind) in [(1_060, TemporalEvidenceMediaKindV1.audio), (1_080, .video)] {
            let base = try C33TemporalEvidenceTestSupport.clip(slot: slot, kind: kind)
            let derivative = try C33TemporalEvidenceTestSupport.derivative(clip: base.clip, slot: slot + 1)
            let current = try base.clip.successor(
                clipID: C33TemporalEvidenceTestSupport.id(slot + 2),
                profile: base.profile,
                derivativeReferences: [try derivative.reference],
                mutationID: C33TemporalEvidenceTestSupport.mutation(slot + 3)
            )
            let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: current, slot: slot + 4)
            let link = try TemporalEvidenceReportProjectionRegistryV1.projection(
                clip: current, anchors: [anchor], currentDerivative: try derivative.reference,
                profile: base.profile
            )
            XCTAssertEqual(link.derivativePreview?.kind, kind == .video ? .thumbnail : .waveform)
            XCTAssertFalse(link.embedsOriginalBytes)
            XCTAssertNil(link.manualTranscript, "report projection must not expose transcript text")
            XCTAssertEqual(link.accessibleDescription, current.accessibleDescription)
            try TemporalEvidenceDetailCardBoundaryV1.validate(
                link, clip: current, currentDerivative: try derivative.reference
            )
            let search = try LocalSearchIndexStoreV1.temporalEvidenceRecord(
                clip: current, anchors: [anchor]
            )
            try TemporalEvidenceSearchProjectionPolicyV1.validate(search)
            XCTAssertTrue(search.includesTranscript)
            XCTAssertTrue(TemporalEvidenceSearchProjectionPolicyV1.excludesTranscriptBody)
        }
        try C33TemporalEvidenceBackupRestoreRegistryV1.validate()
        XCTAssertEqual(TemporalEvidencePersistenceEnrollmentV1.writer,
                       "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertEqual(TemporalEvidencePersistenceEnrollmentV1.scratchPersistence,
                       "NONPERSISTENT_BACKUP_EXCLUDED")
        try TemporalEvidenceLocalizationPolicyV1.validate()
        try TemporalEvidenceAccessibilityPolicyV1.validate()
        let localization = try BundledLocalizationCatalogV1.temporalEvidenceCaptureRegistry()
        _ = try BundledLocalizationCatalogV1.temporalEvidenceCaptureAccessibilityRegistry(
            localization: localization
        )
        XCTAssertEqual(try corpus().selectors.count, 5)
    }

    private func corpus() throws -> C25Corpus {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "V23P04C25TemporalEvidenceCaptureCorpusV1",
            withExtension: "json", subdirectory: "Fixtures/V23/TemporalEvidence"
        ) ?? Bundle(for: Self.self).url(
            forResource: "V23P04C25TemporalEvidenceCaptureCorpusV1", withExtension: "json"
        ))
        return try JSONDecoder().decode(C25Corpus.self, from: Data(contentsOf: url))
    }
}

private enum C25Probe: Error { case writerBoundary }

private struct C25Corpus: Decodable {
    let schema: String
    let schemaVersion: Int
    let sourceLocale: String
    let selectors: [String]
    let hostileCases: [String]
}

private struct C25Bundle {
    let clip: TemporalEvidenceClipV1
    let request: TemporalEvidenceCaptureRequestV1
}

private enum C25Support {
    static func bundle(kind: TemporalEvidenceMediaKindV1, slot: Int) throws -> C25Bundle {
        let value = try C33TemporalEvidenceTestSupport.clip(slot: slot, kind: kind)
        let actor = C26SurveySessionTestSupport.actor(
            workspaceID: value.clip.workspaceID, slot: slot + 5, responsibility: .recordedBy
        )
        let consent = try TemporalEvidenceCaptureConsentV1(
            consentID: C33TemporalEvidenceTestSupport.id(slot + 6),
            workspaceID: value.clip.workspaceID, mediaKind: kind,
            firstUseReason: "Record bounded evidence for this selected requirement.",
            explicitlyAccepted: true, actor: actor,
            recordedAt: value.clip.capturedAt.addingTimeInterval(-1)
        )
        let request = try TemporalEvidenceCaptureRequestV1(
            requestID: C33TemporalEvidenceTestSupport.id(slot + 7),
            workspaceID: value.clip.workspaceID, target: value.clip.target,
            profile: value.profile, mediaKind: kind,
            expectedRevision: C33TemporalEvidenceTestSupport.expectedRevision(for: value.clip),
            mutationID: value.clip.mutationID,
            leaseID: C33TemporalEvidenceTestSupport.id(slot + 8),
            contentID: value.clip.original.contentID, consent: consent,
            manualFallback: .textOrPhoto, requestedAt: value.clip.capturedAt
        )
        return C25Bundle(clip: value.clip, request: request)
    }

    @MainActor static func coordinator(
        bundle: C25Bundle,
        trace: C25Trace,
        permissions: [CapabilityIDV1: CapabilityPermissionStateV1]? = nil,
        canonical: C25Canonical,
        runtime: C25Runtime,
        scratch: C25Scratch = C25Scratch(),
        availableBytes: UInt64? = nil
    ) -> TemporalEvidenceCaptureCoordinatorV1 {
        let required = bundle.request.mediaKind == .audio
            ? [CapabilityIDV1.audioCapture, .microphone]
            : [.camera, .videoCapture]
        let permissionMap = permissions ?? Dictionary(uniqueKeysWithValues: required.map { ($0, .authorized) })
        return TemporalEvidenceCaptureCoordinatorV1(
            access: C25Access(trace: trace),
            capabilities: C25Capabilities(permissions: permissionMap, trace: trace),
            environment: InjectedTemporalEvidenceCaptureEnvironmentResolverV1 { request in
                await trace.add("environment")
                let selectedLimit = request.profile.limit(for: request.mediaKind)
                let (requiredAvailableBytes, overflow) = request.profile.minimumFreeByteCount
                    .addingReportingOverflow(selectedLimit.maximumByteCount)
                guard !overflow else { throw TemporalEvidenceCaptureFailureV1.limitExceeded }
                return TemporalEvidenceCaptureEnvironmentV1(
                    workspaceID: request.workspaceID, isForeground: true,
                    protectedDataAvailable: true,
                    availableByteCount: availableBytes ?? requiredAvailableBytes,
                    clipsForRequirement: 0, clipsForSession: 0,
                    observedAt: request.requestedAt
                )
            },
            scratch: scratch,
            runtime: InjectedTemporalEvidenceCaptureRuntimeV1(
                isForeground: { true }, protectedDataAvailable: { true },
                capture: { request in try await runtime.capture(request) },
                stop: { requestID, reason in await runtime.stop(requestID: requestID, reason: reason) }
            ),
            canonical: canonical
        )
    }
}

private actor C25Trace {
    private var events: [String] = []
    func add(_ value: String) { events.append(value) }
    func values() -> [String] { events }
}

private actor C25Access: AppAccessGatePortV1 {
    let trace: C25Trace
    init(trace: C25Trace) { self.trace = trace }
    func currentState() async -> AppAccessStateV1 { .disabled }
    func lock(reason: AppLockReasonV1) async { }
    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 { .authenticated }
    func requireContentAccess() async throws { await trace.add("access") }
}

private actor C25Capabilities: CapabilityRuntimePortV1 {
    let permissions: [CapabilityIDV1: CapabilityPermissionStateV1]
    let trace: C25Trace
    init(permissions: [CapabilityIDV1: CapabilityPermissionStateV1], trace: C25Trace) {
        self.permissions = permissions; self.trace = trace
    }
    func state(for capabilityID: CapabilityIDV1) async throws -> CapabilityStateV1 {
        await trace.add("capability")
        return try CapabilityStateV1(
            capabilityID: capabilityID,
            permission: permissions[capabilityID] ?? .denied,
            runtime: .available, observedAt: C33TemporalEvidenceTestSupport.fixedDate
        )
    }
    func requestPermission(for capabilityID: CapabilityIDV1,
                           boundary: PermissionRequestBoundaryV1) async throws -> CapabilityStateV1 {
        try await state(for: capabilityID)
    }
}

private actor C25Scratch: TemporalEvidenceCaptureScratchManagingV1 {
    struct WriteRecord: Equatable, Sendable {
        let leaseID: UUID
        let relativeName: String
        let byteCount: UInt64
        let maximumByteCount: UInt64
    }
    private var operations: [UUID: UUID] = [:]
    private var finishes: [ScratchPublicationDispositionV1] = []
    private var bytesByLease: [UUID: Data] = [:]
    private var namesByLease: [UUID: String] = [:]
    private var writes: [WriteRecord] = []
    private var reads = 0
    func acquire(_ request: CapabilityScratchLeaseRequestV1) async throws -> CapabilityScratchLeaseV1 {
        operations[request.leaseID] = request.operationID
        return CapabilityScratchLeaseV1(
            leaseID: request.leaseID, purpose: request.purpose,
            relativeDirectory: "scratch/\(request.leaseID.uuidString.lowercased())"
        )
    }
    func write(_ data: Data, named: String, lease: CapabilityScratchLeaseV1,
               maximumByteCount: UInt64) async throws -> URL {
        guard !data.isEmpty, UInt64(data.count) <= maximumByteCount,
              operations[lease.leaseID] != nil else {
            throw TemporalEvidenceCaptureFailureV1.limitExceeded
        }
        bytesByLease[lease.leaseID] = data
        namesByLease[lease.leaseID] = named
        writes.append(WriteRecord(
            leaseID: lease.leaseID, relativeName: named,
            byteCount: UInt64(data.count), maximumByteCount: maximumByteCount
        ))
        return FileManager.default.temporaryDirectory.appendingPathComponent(named)
    }
    func readPendingReview(_ reference: TemporalEvidencePendingReviewReferenceV1,
                           lease: CapabilityScratchLeaseV1) async throws -> Data {
        reads += 1
        guard reference.leaseID == lease.leaseID,
              namesByLease[lease.leaseID] == reference.relativeName,
              let data = bytesByLease[lease.leaseID] else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }
        return data
    }
    func finish(lease: CapabilityScratchLeaseV1,
                disposition: ScratchPublicationDispositionV1,
                immutableContentReceiptDigest: String?) async throws -> ScratchPublicationLinkageReceiptV1 {
        finishes.append(disposition)
        if disposition != .acceptedIntoImmutableContent {
            bytesByLease.removeValue(forKey: lease.leaseID)
            namesByLease.removeValue(forKey: lease.leaseID)
        }
        return try ScratchPublicationLinkageReceiptV1(
            operationID: operations[lease.leaseID] ?? lease.leaseID,
            leaseID: lease.leaseID, purpose: lease.purpose,
            disposition: disposition,
            immutableContentReceiptDigest: immutableContentReceiptDigest,
            scratchDeleted: true
        )
    }
    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        try ScratchDataLeaseRecoverySummaryV1(recoveredExpiredLeaseCount: 1, removedByteCount: 1)
    }
    func finishDispositions() -> [ScratchPublicationDispositionV1] { finishes }
    func writeRecords() -> [WriteRecord] { writes }
    func pendingReviewReadCount() -> Int { reads }
    func corruptPendingReview(for leaseID: UUID) {
        bytesByLease[leaseID] = Data([0x00])
    }
}

private actor C25Runtime: TemporalEvidenceCaptureRuntimeV1 {
    private let failure: TemporalEvidenceCaptureFailureV1?
    private var captures = 0
    private var stops: [TemporalEvidenceStopReasonV1] = []
    init(failure: TemporalEvidenceCaptureFailureV1? = nil) { self.failure = failure }
    func capture(_ request: TemporalEvidenceRuntimeCaptureRequestV1) async throws
        -> TemporalEvidenceRuntimeCaptureResultV1 {
        captures += 1
        if let failure { throw failure }
        let facts = try C33TemporalEvidenceTestSupport.facts(kind: request.request.mediaKind)
        let receipt = try TemporalEvidenceIncrementalAdmissionReceiptV1(
            profile: request.request.profile, kind: facts.kind, codec: facts.codec,
            pixelWidth: facts.pixelWidth, pixelHeight: facts.pixelHeight,
            observedDurationMilliseconds: facts.durationMilliseconds,
            observedByteCount: facts.byteCount, sequence: 1, captureCompleted: true
        )
        return try TemporalEvidenceRuntimeCaptureResultV1(
            request: request, bytes: C33TemporalEvidenceTestSupport.bytes(for: facts.kind),
            facts: facts, admissionReceipt: receipt,
            capturedAt: request.request.requestedAt,
            stoppedAt: request.request.requestedAt.addingTimeInterval(Double(facts.durationMilliseconds) / 1_000),
            stopReason: receipt.terminalStopReason
        )
    }
    func stop(requestID: UUID, reason: TemporalEvidenceStopReasonV1) async { stops.append(reason) }
    func captureCount() -> Int { captures }
    func stopReasons() -> [TemporalEvidenceStopReasonV1] { stops }
}

private actor C25RecoveryEffects {
    private var removals = 0
    func verify() -> Bool { true }
    func remove() { removals += 1 }
    func removeCount() -> Int { removals }
}

@MainActor
private final class C25Canonical: TemporalEvidenceCaptureCanonicalUsingV1 {
    let operationID: UUID
    private(set) var useCount = 0
    private(set) var terminalCount = 0
    private(set) var recoveryCount = 0
    init(operationID: UUID) { self.operationID = operationID }
    func use(_ request: TemporalEvidenceAcceptanceRequestV1) async throws -> TemporalEvidenceAcceptanceReceiptV1 {
        useCount += 1
        throw C25Probe.writerBoundary
    }
    func reject(lease: CapabilityScratchLeaseV1) async throws -> ScratchPublicationLinkageReceiptV1 {
        terminalCount += 1
        return try terminal(lease, .rejected)
    }
    func cancel(lease: CapabilityScratchLeaseV1) async throws -> ScratchPublicationLinkageReceiptV1 {
        terminalCount += 1
        return try terminal(lease, .cancelled)
    }
    func fail(lease: CapabilityScratchLeaseV1) async throws -> ScratchPublicationLinkageReceiptV1 {
        terminalCount += 1
        return try terminal(lease, .failed)
    }
    func appendAnchor(_ anchor: TimecodedEvidenceAnchorV1, clip: TemporalEvidenceClipV1,
                      predecessor: TimecodedEvidenceAnchorV1?,
                      expectedRevision: WorkspaceExpectedRevisionV1) throws -> TemporalEvidenceMutationReceiptV1 {
        throw C25Probe.writerBoundary
    }
    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        recoveryCount += 1
        return try ScratchDataLeaseRecoverySummaryV1(recoveredExpiredLeaseCount: 1, removedByteCount: 1)
    }
    private func terminal(_ lease: CapabilityScratchLeaseV1,
                          _ disposition: ScratchPublicationDispositionV1) throws
        -> ScratchPublicationLinkageReceiptV1 {
        try ScratchPublicationLinkageReceiptV1(
            operationID: operationID, leaseID: lease.leaseID, purpose: lease.purpose,
            disposition: disposition, immutableContentReceiptDigest: nil, scratchDeleted: true
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in }
) async {
    do { _ = try await expression(); XCTFail("expected error") }
    catch { handler(error) }
}

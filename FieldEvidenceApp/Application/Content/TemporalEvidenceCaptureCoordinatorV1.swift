import Foundation

protocol TemporalEvidenceCaptureEnvironmentResolvingV1: Sendable {
    func currentEnvironment(
        for request: TemporalEvidenceCaptureRequestV1
    ) async throws -> TemporalEvidenceCaptureEnvironmentV1
}

protocol TemporalEvidenceCaptureRuntimeV1: Sendable {
    func capture(
        _ request: TemporalEvidenceRuntimeCaptureRequestV1
    ) async throws -> TemporalEvidenceRuntimeCaptureResultV1
    func stop(requestID: UUID, reason: TemporalEvidenceStopReasonV1) async
}

protocol TemporalEvidenceCaptureScratchManagingV1: Sendable {
    func acquire(_ request: CapabilityScratchLeaseRequestV1) async throws
        -> CapabilityScratchLeaseV1
    func write(
        _ data: Data,
        named: String,
        lease: CapabilityScratchLeaseV1,
        maximumByteCount: UInt64
    ) async throws -> URL
    func readPendingReview(
        _ reference: TemporalEvidencePendingReviewReferenceV1,
        lease: CapabilityScratchLeaseV1
    ) async throws -> Data
    func recoverPendingReview(
        _ reference: TemporalEvidencePendingReviewReferenceV1,
        lease: CapabilityScratchLeaseV1
    ) async throws -> Data?
    func finish(
        lease: CapabilityScratchLeaseV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws -> ScratchPublicationLinkageReceiptV1
    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1
}

extension TemporalEvidenceCaptureScratchManagingV1 {
    func recoverPendingReview(
        _ reference: TemporalEvidencePendingReviewReferenceV1,
        lease: CapabilityScratchLeaseV1
    ) async throws -> Data? {
        try await readPendingReview(reference, lease: lease)
    }
}

@MainActor protocol TemporalEvidenceCaptureCanonicalUsingV1: AnyObject {
    func use(_ request: TemporalEvidenceAcceptanceRequestV1) async throws
        -> TemporalEvidenceAcceptanceReceiptV1
    func reject(lease: CapabilityScratchLeaseV1) async throws
        -> ScratchPublicationLinkageReceiptV1
    func cancel(lease: CapabilityScratchLeaseV1) async throws
        -> ScratchPublicationLinkageReceiptV1
    func fail(lease: CapabilityScratchLeaseV1) async throws
        -> ScratchPublicationLinkageReceiptV1
    func appendAnchor(
        _ anchor: TimecodedEvidenceAnchorV1,
        clip: TemporalEvidenceClipV1,
        predecessor: TimecodedEvidenceAnchorV1?,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) throws -> TemporalEvidenceMutationReceiptV1
    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1
}

extension TemporalEvidenceCoordinatorV1: TemporalEvidenceCaptureCanonicalUsingV1 {
    func use(_ request: TemporalEvidenceAcceptanceRequestV1) async throws
        -> TemporalEvidenceAcceptanceReceiptV1 {
        try await accept(request)
    }
}

struct TemporalEvidenceCaptureStartResultV1: Equatable, Sendable {
    let review: TemporalClipReviewStateV1?
    let fallback: TemporalEvidenceManualFallbackV1?
    let disposition: TemporalEvidenceCaptureDispositionV1

    init(review: TemporalClipReviewStateV1) {
        self.review = review; fallback = nil; disposition = .reviewRequired
    }

    init(fallback: TemporalEvidenceManualFallbackV1) {
        review = nil; self.fallback = fallback; disposition = .manualFallback
    }
}

@MainActor final class TemporalEvidenceCaptureCoordinatorV1 {
    private let access: any AppAccessGatePortV1
    private let capabilities: any CapabilityRuntimePortV1
    private let environment: any TemporalEvidenceCaptureEnvironmentResolvingV1
    private let scratch: any TemporalEvidenceCaptureScratchManagingV1
    private let runtime: any TemporalEvidenceCaptureRuntimeV1
    private let canonical: any TemporalEvidenceCaptureCanonicalUsingV1

    init(
        access: any AppAccessGatePortV1,
        capabilities: any CapabilityRuntimePortV1,
        environment: any TemporalEvidenceCaptureEnvironmentResolvingV1,
        scratch: any TemporalEvidenceCaptureScratchManagingV1,
        runtime: any TemporalEvidenceCaptureRuntimeV1,
        canonical: any TemporalEvidenceCaptureCanonicalUsingV1
    ) {
        self.access = access; self.capabilities = capabilities
        self.environment = environment; self.scratch = scratch
        self.runtime = runtime; self.canonical = canonical
    }

    func startAudio(_ request: TemporalEvidenceCaptureRequestV1) async throws
        -> AudioEvidenceCaptureFlowV1 {
        guard request.mediaKind == .audio else {
            throw TemporalEvidenceCaptureFailureV1.invalidValue
        }
        let result = try await start(request)
        return try AudioEvidenceCaptureFlowV1(
            request: request, disposition: result.disposition, review: result.review
        )
    }

    func startVideo(_ request: TemporalEvidenceCaptureRequestV1) async throws
        -> VideoEvidenceCaptureFlowV1 {
        guard request.mediaKind == .video else {
            throw TemporalEvidenceCaptureFailureV1.invalidValue
        }
        let result = try await start(request)
        return try VideoEvidenceCaptureFlowV1(
            request: request, disposition: result.disposition, review: result.review
        )
    }

    func start(_ request: TemporalEvidenceCaptureRequestV1) async throws
        -> TemporalEvidenceCaptureStartResultV1 {
        try request.validate()

        // This must remain the first asynchronous operation: no capability,
        // target, environment, scratch, or provider read may precede AppAccess.
        let permit: AppAccessContentPermitV1
        switch request.mediaKind {
        case .audio: permit = try await access.requireTemporalAudioCaptureAccess()
        case .video: permit = try await access.requireTemporalVideoCaptureAccess()
        }
        switch request.mediaKind {
        case .audio: try TemporalEvidenceCaptureAppAccessBoundaryV1.validateAudio(permit)
        case .video: try TemporalEvidenceCaptureAppAccessBoundaryV1.validateVideo(permit)
        }

        let matrix = try await permissionMatrix(for: request)
        do {
            try matrix.requireAuthorized()
        } catch {
            guard request.manualFallback != .prohibitedByPinnedRule else { throw error }
            return TemporalEvidenceCaptureStartResultV1(fallback: request.manualFallback)
        }

        let current = try await environment.currentEnvironment(for: request)
        try current.validate(profile: request.profile)
        guard current.workspaceID == request.workspaceID else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }

        let limit = request.profile.limit(for: request.mediaKind)
        let (requiredAvailableBytes, overflow) = request.profile.minimumFreeByteCount
            .addingReportingOverflow(limit.maximumByteCount)
        guard !overflow, current.availableByteCount >= requiredAvailableBytes else {
            if request.manualFallback != .prohibitedByPinnedRule {
                return TemporalEvidenceCaptureStartResultV1(fallback: request.manualFallback)
            }
            throw TemporalEvidenceCaptureFailureV1.insufficientStorage
        }
        let leaseRequest = try CapabilityScratchLeaseRequestV1(
            leaseID: request.leaseID,
            operationID: request.mutationID.rawValue,
            purpose: .capture,
            requestedByteCount: limit.maximumByteCount,
            createdAt: request.requestedAt,
            expiresAt: request.requestedAt.addingTimeInterval(TemporalEvidenceCapturePolicyV1.maximumScratchLifetime)
        )
        let lease = try await scratch.acquire(leaseRequest)
        do {
            let runtimeRequest = try TemporalEvidenceRuntimeCaptureRequestV1(
                request: request, permissionMatrix: matrix,
                environment: current, lease: lease
            )
            let result = try await runtime.capture(runtimeRequest)
            try result.validate(request: runtimeRequest)
            let finalPermissions = try await permissionMatrix(for: request)
            try finalPermissions.requireAuthorized()
            guard finalPermissions.mediaKind == matrix.mediaKind else {
                throw TemporalEvidenceCaptureFailureV1.permissionDenied
            }
            let observed = try ContentIntegrityV1.observe(
                workspaceID: request.workspaceID.rawValue.uuidString.lowercased(),
                contentID: request.contentID,
                data: result.bytes,
                mediaType: result.facts.codec.mediaType,
                algorithms: [.sha256]
            )
            guard let sha = observed.digests.digest(for: .sha256)?.hexadecimalValue else {
                throw TemporalEvidenceCaptureFailureV1.invalidValue
            }
            let relativeName = "temporal-evidence-\(request.requestID.uuidString.lowercased()).bin"
            let writtenURL = try await scratch.write(
                result.bytes, named: relativeName, lease: lease,
                maximumByteCount: limit.maximumByteCount
            )
            guard writtenURL.isFileURL, writtenURL.lastPathComponent == relativeName else {
                throw TemporalEvidenceCaptureFailureV1.staleSource
            }
            let binding = try TemporalEvidenceScratchBindingV1(
                request: leaseRequest, lease: lease, mutationID: request.mutationID,
                contentID: request.contentID, contentSHA256: sha
            )
            let pendingReview = try TemporalEvidencePendingReviewReferenceV1(
                request: runtimeRequest, result: result,
                relativeName: relativeName, contentSHA256: sha
            )
            let review = try TemporalClipReviewStateV1(
                request: request, permissionMatrix: matrix, environment: current,
                scratchBinding: binding, pendingReview: pendingReview
            )
            return TemporalEvidenceCaptureStartResultV1(review: review)
        } catch {
            await runtime.stop(requestID: request.requestID, reason: Self.stopReason(for: error))
            _ = try? await scratch.finish(
                lease: lease, disposition: .failed, immutableContentReceiptDigest: nil
            )
            throw error
        }
    }

    func useRecording(
        _ reviewState: TemporalClipReviewStateV1,
        clip: TemporalEvidenceClipV1,
        review: TemporalEvidenceCaptureReviewV1
    ) async throws -> TemporalEvidenceAcceptanceReceiptV1 {
        try reviewState.validate(); try clip.validate(profile: reviewState.request.profile)
        try review.validate()
        let completedBytes = try await scratch.readPendingReview(
            reviewState.pendingReview, lease: reviewState.scratchBinding.lease
        )
        try reviewState.pendingReview.validateBytes(
            completedBytes,
            workspaceID: reviewState.request.workspaceID,
            contentID: reviewState.request.contentID
        )
        guard reviewState.disposition == .reviewRequired,
              clip.workspaceID == reviewState.request.workspaceID,
              clip.target == reviewState.request.target,
              clip.mutationID == reviewState.request.mutationID,
              clip.facts == reviewState.pendingReview.facts,
              clip.capturedAt == reviewState.pendingReview.capturedAt,
              clip.original.contentID == reviewState.request.contentID,
              clip.original.digests.digest(for: .sha256)?.hexadecimalValue
                == reviewState.scratchBinding.contentSHA256,
              review.workspaceID == clip.workspaceID,
              review.clipID == clip.clipID,
              review.decision == .accept,
              review.reviewedAt == clip.acceptedAt else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }
        let acceptance = try TemporalEvidenceAcceptanceRequestV1(
            clip: clip, profile: reviewState.request.profile, review: review,
            expectedRevision: reviewState.request.expectedRevision,
            scratchBinding: reviewState.scratchBinding,
            admissionReceipt: reviewState.pendingReview.admissionReceipt,
            completedBytes: completedBytes
        )
        return try await canonical.use(acceptance)
    }

    func delete(_ review: TemporalClipReviewStateV1) async throws
        -> ScratchPublicationLinkageReceiptV1 {
        try review.validate()
        return try await canonical.reject(lease: review.scratchBinding.lease)
    }

    /// Retake never reuses a lease, content ID, mutation ID, or consent event.
    /// The caller must create a fresh request after this terminal cleanup.
    func retake(_ review: TemporalClipReviewStateV1) async throws
        -> ScratchPublicationLinkageReceiptV1 {
        try await delete(review)
    }

    func cancel(_ review: TemporalClipReviewStateV1) async throws
        -> ScratchPublicationLinkageReceiptV1 {
        try review.validate()
        await runtime.stop(requestID: review.request.requestID, reason: .cancelled)
        return try await canonical.cancel(lease: review.scratchBinding.lease)
    }

    func appendAnchor(
        _ anchor: TimecodedEvidenceAnchorV1,
        to clip: TemporalEvidenceClipV1,
        predecessor: TimecodedEvidenceAnchorV1?,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) throws -> TemporalEvidenceMutationReceiptV1 {
        try anchor.validate(clip: clip)
        return try canonical.appendAnchor(anchor, clip: clip,
                                          predecessor: predecessor,
                                          expectedRevision: expectedRevision)
    }

    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        try await canonical.recoverAfterInterruption()
    }

    /// Restores only a caller-held, digest-bound device-local review. With no
    /// valid reference, incumbent recovery expires orphan scratch and returns
    /// no review. No directory scan or latest-record fallback is permitted.
    func recoverAfterInterruption(
        pendingReview review: TemporalClipReviewStateV1?
    ) async throws -> TemporalClipReviewStateV1? {
        guard let review else {
            _ = try await canonical.recoverAfterInterruption()
            return nil
        }
        do {
            try review.validate()
            guard let bytes = try await scratch.recoverPendingReview(
                review.pendingReview, lease: review.scratchBinding.lease
            ) else { throw TemporalEvidenceCaptureFailureV1.interrupted }
            try review.pendingReview.validateBytes(
                bytes,
                workspaceID: review.request.workspaceID,
                contentID: review.request.contentID
            )
            return review
        } catch {
            _ = try? await scratch.finish(
                lease: review.scratchBinding.lease,
                disposition: .expired,
                immutableContentReceiptDigest: nil
            )
            _ = try await canonical.recoverAfterInterruption()
            return nil
        }
    }

    private func permissionMatrix(for request: TemporalEvidenceCaptureRequestV1) async throws
        -> TemporalEvidenceCapturePermissionMatrixV1 {
        let required: [CapabilityIDV1] = request.mediaKind == .audio
            ? [.audioCapture, .microphone] : [.camera, .videoCapture]
        var states: [CapabilityStateV1] = []
        for capability in required {
            var state = try await capabilities.state(for: capability)
            if state.permission == .notDetermined {
                let boundary = try PermissionRequestBoundaryV1(
                    operationID: request.requestID, capabilityID: capability,
                    trigger: .explicitUserInitiatedFeatureBoundary,
                    userInitiatedAt: request.requestedAt
                )
                state = try await capabilities.requestPermission(
                    for: capability, boundary: boundary
                )
            }
            states.append(state)
        }
        return try TemporalEvidenceCapturePermissionMatrixV1(
            mediaKind: request.mediaKind, states: states
        )
    }

    private static func stopReason(for error: Error) -> TemporalEvidenceStopReasonV1 {
        switch error {
        case TemporalEvidenceCaptureFailureV1.notForeground: return .backgrounded
        case TemporalEvidenceCaptureFailureV1.protectedDataUnavailable:
            return .protectedDataUnavailable
        case TemporalEvidenceCaptureFailureV1.insufficientStorage: return .insufficientStorage
        case TemporalEvidenceCaptureFailureV1.permissionDenied: return .permissionDenied
        case TemporalEvidenceCaptureFailureV1.interrupted: return .interruption
        case TemporalEvidenceContractFailureV1.unsupportedMedia: return .codecUnavailable
        case TemporalEvidenceContractFailureV1.insufficientStorage: return .insufficientStorage
        default: return .cancelled
        }
    }
}

enum TemporalEvidenceCapturePolicyV1 {
    static let maximumScratchLifetime: TimeInterval = 60 * 60
    static let foregroundOnly = true
    static let appAccessPrecedesEveryPrivateRead = true
    static let visibleTextAndIconRecordingStateRequired = true
    static let automaticUploadAllowed = false
    static let automaticTranscriptionOrRedactionAllowed = false
    static let shippingAdoption = false
    static let nativeAcceptance = false
}

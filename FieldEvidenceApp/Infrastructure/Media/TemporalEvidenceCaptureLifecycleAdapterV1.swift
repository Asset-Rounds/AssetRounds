import Foundation

/// Adds exact reads to the incumbent C33 scratch lifecycle without owning a
/// second byte store. Composition must resolve only the supplied lease and
/// relative name; it may not scan for a latest recording.
struct InjectedTemporalEvidenceCaptureScratchManagerV1:
    TemporalEvidenceCaptureScratchManagingV1, Sendable {
    typealias ReadPendingReview = @Sendable (
        TemporalEvidencePendingReviewReferenceV1, CapabilityScratchLeaseV1
    ) async throws -> Data

    private let base: any TemporalEvidenceScratchLifecycleV1
    private let read: ReadPendingReview

    init(
        base: any TemporalEvidenceScratchLifecycleV1,
        readPendingReview: @escaping ReadPendingReview
    ) {
        self.base = base
        read = readPendingReview
    }

    func acquire(_ request: CapabilityScratchLeaseRequestV1) async throws
        -> CapabilityScratchLeaseV1 {
        try await base.acquire(request)
    }

    func write(
        _ data: Data,
        named: String,
        lease: CapabilityScratchLeaseV1,
        maximumByteCount: UInt64
    ) async throws -> URL {
        guard !data.isEmpty,
              maximumByteCount > 0,
              UInt64(data.count) <= maximumByteCount else {
            throw TemporalEvidenceCaptureFailureV1.limitExceeded
        }
        return try await base.write(data, named: named, lease: lease)
    }

    func readPendingReview(
        _ reference: TemporalEvidencePendingReviewReferenceV1,
        lease: CapabilityScratchLeaseV1
    ) async throws -> Data {
        guard reference.leaseID == lease.leaseID,
              lease.purpose == .capture else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }
        let data = try await read(reference, lease)
        guard !data.isEmpty, UInt64(data.count) == reference.byteCount else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }
        return data
    }

    func finish(
        lease: CapabilityScratchLeaseV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws -> ScratchPublicationLinkageReceiptV1 {
        try await base.finish(
            lease: lease,
            disposition: disposition,
            immutableContentReceiptDigest: immutableContentReceiptDigest
        )
    }

    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        try await base.recoverAfterInterruption()
    }

}

struct InjectedTemporalEvidenceCaptureEnvironmentResolverV1:
    TemporalEvidenceCaptureEnvironmentResolvingV1, Sendable {
    typealias Resolve = @Sendable (TemporalEvidenceCaptureRequestV1) async throws
        -> TemporalEvidenceCaptureEnvironmentV1
    private let resolve: Resolve

    init(resolve: @escaping Resolve) { self.resolve = resolve }

    func currentEnvironment(for request: TemporalEvidenceCaptureRequestV1) async throws
        -> TemporalEvidenceCaptureEnvironmentV1 {
        try request.validate()
        let value = try await resolve(request)
        try value.validate(profile: request.profile)
        guard value.workspaceID == request.workspaceID else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }
        return value
    }
}

/// Runtime injection point for the eventual S10-owned foreground presentation.
/// This adapter owns neither an AV session nor a byte store. Its closures must
/// bridge a foreground-only engine into the already-owned C33 scratch lease.
struct InjectedTemporalEvidenceCaptureRuntimeV1:
    TemporalEvidenceCaptureRuntimeV1, Sendable {
    typealias Capture = @Sendable (TemporalEvidenceRuntimeCaptureRequestV1) async throws
        -> TemporalEvidenceRuntimeCaptureResultV1
    typealias Stop = @Sendable (UUID, TemporalEvidenceStopReasonV1) async -> Void
    typealias Foreground = @Sendable () async -> Bool
    typealias ProtectedData = @Sendable () async -> Bool

    private let performCapture: Capture
    private let performStop: Stop
    private let isForeground: Foreground
    private let protectedDataAvailable: ProtectedData

    init(
        isForeground: @escaping Foreground,
        protectedDataAvailable: @escaping ProtectedData,
        capture: @escaping Capture,
        stop: @escaping Stop
    ) {
        self.isForeground = isForeground
        self.protectedDataAvailable = protectedDataAvailable
        performCapture = capture
        performStop = stop
    }

    func capture(_ request: TemporalEvidenceRuntimeCaptureRequestV1) async throws
        -> TemporalEvidenceRuntimeCaptureResultV1 {
        try request.validate()
        guard await isForeground() else {
            throw TemporalEvidenceCaptureFailureV1.notForeground
        }
        guard await protectedDataAvailable() else {
            throw TemporalEvidenceCaptureFailureV1.protectedDataUnavailable
        }
        let value = try await performCapture(request)
        guard await isForeground() else {
            await performStop(request.request.requestID, .backgrounded)
            throw TemporalEvidenceCaptureFailureV1.notForeground
        }
        guard await protectedDataAvailable() else {
            await performStop(request.request.requestID, .protectedDataUnavailable)
            throw TemporalEvidenceCaptureFailureV1.protectedDataUnavailable
        }
        try value.validate(request: request)
        return value
    }

    func stop(requestID: UUID, reason: TemporalEvidenceStopReasonV1) async {
        await performStop(requestID, reason)
    }
}

/// Composition only. Canonical writes, receipts, immutable-content promotion,
/// and recovery remain owned by TemporalEvidenceLifecycleAdapterV1/C33.
@MainActor final class TemporalEvidenceCaptureLifecycleAdapterV1 {
    let captureCoordinator: TemporalEvidenceCaptureCoordinatorV1
    let temporalEvidence: TemporalEvidenceLifecycleAdapterV1

    init(
        temporalEvidence: TemporalEvidenceLifecycleAdapterV1,
        access: any AppAccessGatePortV1,
        capabilities: any CapabilityRuntimePortV1,
        environment: any TemporalEvidenceCaptureEnvironmentResolvingV1,
        runtime: any TemporalEvidenceCaptureRuntimeV1,
        readPendingReview: @escaping
            InjectedTemporalEvidenceCaptureScratchManagerV1.ReadPendingReview
    ) {
        self.temporalEvidence = temporalEvidence
        let captureScratch = InjectedTemporalEvidenceCaptureScratchManagerV1(
            base: temporalEvidence.scratch,
            readPendingReview: readPendingReview
        )
        captureCoordinator = TemporalEvidenceCaptureCoordinatorV1(
            access: access,
            capabilities: capabilities,
            environment: environment,
            scratch: captureScratch,
            runtime: runtime,
            canonical: temporalEvidence.coordinator
        )
    }

    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        try await captureCoordinator.recoverAfterInterruption()
    }

    func recoverAfterInterruption(
        pendingReview: TemporalClipReviewStateV1?
    ) async throws -> TemporalClipReviewStateV1? {
        try await captureCoordinator.recoverAfterInterruption(
            pendingReview: pendingReview
        )
    }
}

enum TemporalEvidenceCaptureRuntimeAdoptionV1 {
    static let shippingUIInstalled = false
    static let nativeCaptureAccepted = false
    static let physicalDeviceMatrixAccepted = false
    static let networkProviderAllowed = false
    static let backgroundCaptureAllowed = false
    static let secondScratchOrContentStoreAllowed = false
}

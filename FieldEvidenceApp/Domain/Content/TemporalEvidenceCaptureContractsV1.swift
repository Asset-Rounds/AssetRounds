import Foundation

enum TemporalEvidenceCaptureFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case accessDenied
    case consentRequired
    case capabilityUnavailable
    case permissionDenied
    case notForeground
    case protectedDataUnavailable
    case insufficientStorage
    case limitExceeded
    case staleSource
    case invalidTransition
    case interrupted
}

enum TemporalEvidenceCaptureDispositionV1: String, Codable, CaseIterable, Sendable {
    case ready = "READY"
    case recording = "RECORDING"
    case reviewRequired = "REVIEW_REQUIRED"
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
    case cancelled = "CANCELLED"
    case failed = "FAILED"
    case interrupted = "INTERRUPTED"
    case manualFallback = "MANUAL_FALLBACK"
}

enum TemporalEvidenceManualFallbackV1: String, Codable, CaseIterable, Sendable {
    case text = "TEXT"
    case photo = "PHOTO"
    case textOrPhoto = "TEXT_OR_PHOTO"
    case leaveIncompleteAndResume = "LEAVE_INCOMPLETE_AND_RESUME"
    case prohibitedByPinnedRule = "PROHIBITED_BY_PINNED_RULE"
}

struct TemporalEvidenceRecordingPresentationV1: Codable, Equatable, Sendable {
    let disposition: TemporalEvidenceCaptureDispositionV1
    let statusTextKey: String
    let statusIconName: String
    let elapsedMilliseconds: UInt64
    let remainingMilliseconds: UInt64
    let remainingByteCount: UInt64
    let usesColorAsSoleIndicator: Bool

    init(
        disposition: TemporalEvidenceCaptureDispositionV1,
        statusTextKey: String,
        statusIconName: String,
        elapsedMilliseconds: UInt64,
        remainingMilliseconds: UInt64,
        remainingByteCount: UInt64,
        usesColorAsSoleIndicator: Bool = false
    ) throws {
        self.disposition = disposition; self.statusTextKey = statusTextKey
        self.statusIconName = statusIconName; self.elapsedMilliseconds = elapsedMilliseconds
        self.remainingMilliseconds = remainingMilliseconds
        self.remainingByteCount = remainingByteCount
        self.usesColorAsSoleIndicator = usesColorAsSoleIndicator
        guard [.ready, .recording, .reviewRequired, .interrupted, .failed].contains(disposition),
              !statusTextKey.isEmpty, statusTextKey.utf8.count <= 256,
              !statusIconName.isEmpty, statusIconName.utf8.count <= 128,
              !usesColorAsSoleIndicator else {
            throw TemporalEvidenceCaptureFailureV1.invalidValue
        }
    }
}

struct TemporalEvidenceCaptureConsentV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let consentID: UUID
    let workspaceID: WorkspaceID
    let mediaKind: TemporalEvidenceMediaKindV1
    let firstUseReason: String
    let explicitlyAccepted: Bool
    let actor: ActorSnapshotV1
    let recordedAt: Date

    init(
        consentID: UUID,
        workspaceID: WorkspaceID,
        mediaKind: TemporalEvidenceMediaKindV1,
        firstUseReason: String,
        explicitlyAccepted: Bool,
        actor: ActorSnapshotV1,
        recordedAt: Date
    ) throws {
        schemaVersion = Self.schemaVersion
        self.consentID = consentID
        self.workspaceID = workspaceID
        self.mediaKind = mediaKind
        self.firstUseReason = firstUseReason
        self.explicitlyAccepted = explicitlyAccepted
        self.actor = actor
        self.recordedAt = recordedAt
        try validate()
    }

    func validate() throws {
        try actor.validate()
        let reason = firstUseReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard schemaVersion == Self.schemaVersion,
              consentID != TemporalEvidenceValidationV1.zeroUUID,
              actor.workspaceID == workspaceID,
              reason == firstUseReason, !reason.isEmpty, reason.utf8.count <= 512,
              explicitlyAccepted,
              recordedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw TemporalEvidenceCaptureFailureV1.consentRequired
        }
    }
}

struct TemporalEvidenceCapturePermissionMatrixV1: Codable, Equatable, Sendable {
    let mediaKind: TemporalEvidenceMediaKindV1
    let states: [CapabilityStateV1]

    init(mediaKind: TemporalEvidenceMediaKindV1, states: [CapabilityStateV1]) throws {
        self.mediaKind = mediaKind
        self.states = states.sorted { $0.capabilityID.rawValue < $1.capabilityID.rawValue }
        try validate()
    }

    var requiredCapabilities: [CapabilityIDV1] {
        switch mediaKind {
        case .audio: return [.audioCapture, .microphone]
        case .video: return [.camera, .videoCapture]
        }
    }

    func validate() throws {
        let expected = requiredCapabilities.sorted { $0.rawValue < $1.rawValue }
        guard states.map(\.capabilityID) == expected,
              Set(states.map(\.capabilityID)).count == states.count,
              states.allSatisfy({ $0.observedAt.timeIntervalSinceReferenceDate.isFinite }) else {
            throw TemporalEvidenceCaptureFailureV1.capabilityUnavailable
        }
    }

    func requireAuthorized() throws {
        try validate()
        let byID = Dictionary(uniqueKeysWithValues: states.map { ($0.capabilityID, $0) })
        let permissionOK: Bool
        switch mediaKind {
        case .audio:
            if let microphone = byID[.microphone], let capture = byID[.audioCapture] {
                permissionOK = microphone.permission == .authorized
                    && (capture.permission == .authorized || capture.permission == .notRequired)
            } else {
                permissionOK = false
            }
        case .video:
            if let camera = byID[.camera], let capture = byID[.videoCapture] {
                permissionOK = camera.permission == .authorized
                    && (capture.permission == .authorized || capture.permission == .notRequired)
            } else {
                permissionOK = false
            }
        }
        guard permissionOK, states.allSatisfy({ $0.runtime == .available }) else {
            throw TemporalEvidenceCaptureFailureV1.permissionDenied
        }
    }
}

struct TemporalEvidenceCaptureEnvironmentV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let isForeground: Bool
    let protectedDataAvailable: Bool
    let availableByteCount: UInt64
    let clipsForRequirement: Int
    let clipsForSession: Int
    let observedAt: Date

    func validate(profile: TemporalEvidenceLimitProfileV1) throws {
        try profile.validate()
        guard observedAt.timeIntervalSinceReferenceDate.isFinite,
              clipsForRequirement >= 0,
              clipsForSession >= clipsForRequirement else {
            throw TemporalEvidenceCaptureFailureV1.invalidValue
        }
        guard isForeground else { throw TemporalEvidenceCaptureFailureV1.notForeground }
        guard protectedDataAvailable else {
            throw TemporalEvidenceCaptureFailureV1.protectedDataUnavailable
        }
        guard clipsForRequirement < profile.maximumClipsPerRequirement,
              clipsForSession < profile.maximumClipsPerSession else {
            throw TemporalEvidenceCaptureFailureV1.limitExceeded
        }
        guard availableByteCount >= profile.minimumFreeByteCount else {
            throw TemporalEvidenceCaptureFailureV1.insufficientStorage
        }
    }
}

struct TemporalEvidenceCaptureRequestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let requestID: UUID
    let workspaceID: WorkspaceID
    let target: TemporalEvidenceTargetV1
    let profile: TemporalEvidenceLimitProfileV1
    let mediaKind: TemporalEvidenceMediaKindV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1
    let leaseID: UUID
    let contentID: String
    let consent: TemporalEvidenceCaptureConsentV1
    let manualFallback: TemporalEvidenceManualFallbackV1
    let requestedAt: Date

    init(
        requestID: UUID,
        workspaceID: WorkspaceID,
        target: TemporalEvidenceTargetV1,
        profile: TemporalEvidenceLimitProfileV1,
        mediaKind: TemporalEvidenceMediaKindV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        leaseID: UUID,
        contentID: String,
        consent: TemporalEvidenceCaptureConsentV1,
        manualFallback: TemporalEvidenceManualFallbackV1,
        requestedAt: Date
    ) throws {
        schemaVersion = Self.schemaVersion
        self.requestID = requestID; self.workspaceID = workspaceID
        self.target = target; self.profile = profile; self.mediaKind = mediaKind
        self.expectedRevision = expectedRevision; self.mutationID = mutationID
        self.leaseID = leaseID; self.contentID = contentID; self.consent = consent
        self.manualFallback = manualFallback; self.requestedAt = requestedAt
        try validate()
    }

    func validate() throws {
        try target.validate(); try profile.validate(); try consent.validate()
        guard schemaVersion == Self.schemaVersion,
              requestID != TemporalEvidenceValidationV1.zeroUUID,
              leaseID != TemporalEvidenceValidationV1.zeroUUID,
              target.workspaceID == workspaceID,
              target.definitionRelease == profile.definitionRelease,
              expectedRevision.workspaceID == workspaceID,
              consent.workspaceID == workspaceID,
              consent.mediaKind == mediaKind,
              consent.recordedAt <= requestedAt,
              ContentContractValidationV1.validID(contentID),
              requestedAt.timeIntervalSinceReferenceDate.isFinite,
              profile.limit(for: mediaKind).kind == mediaKind else {
            throw TemporalEvidenceCaptureFailureV1.invalidValue
        }
    }
}

struct TemporalEvidenceRuntimeCaptureRequestV1: Equatable, Sendable {
    let request: TemporalEvidenceCaptureRequestV1
    let permissionMatrix: TemporalEvidenceCapturePermissionMatrixV1
    let environment: TemporalEvidenceCaptureEnvironmentV1
    let lease: CapabilityScratchLeaseV1

    init(
        request: TemporalEvidenceCaptureRequestV1,
        permissionMatrix: TemporalEvidenceCapturePermissionMatrixV1,
        environment: TemporalEvidenceCaptureEnvironmentV1,
        lease: CapabilityScratchLeaseV1
    ) throws {
        self.request = request; self.permissionMatrix = permissionMatrix
        self.environment = environment; self.lease = lease
        try validate()
    }

    func validate() throws {
        try request.validate(); try permissionMatrix.requireAuthorized()
        try environment.validate(profile: request.profile)
        guard permissionMatrix.mediaKind == request.mediaKind,
              environment.workspaceID == request.workspaceID,
              lease.leaseID == request.leaseID,
              lease.purpose == .capture else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }
    }
}

struct TemporalEvidenceRuntimeCaptureResultV1: Equatable, Sendable {
    let requestID: UUID
    let bytes: Data
    let facts: TemporalEvidenceMediaFactsV1
    let admissionReceipt: TemporalEvidenceIncrementalAdmissionReceiptV1
    let capturedAt: Date
    let stoppedAt: Date
    let stopReason: TemporalEvidenceStopReasonV1?

    init(
        request: TemporalEvidenceRuntimeCaptureRequestV1,
        bytes: Data,
        facts: TemporalEvidenceMediaFactsV1,
        admissionReceipt: TemporalEvidenceIncrementalAdmissionReceiptV1,
        capturedAt: Date,
        stoppedAt: Date,
        stopReason: TemporalEvidenceStopReasonV1?
    ) throws {
        requestID = request.request.requestID; self.bytes = bytes; self.facts = facts
        self.admissionReceipt = admissionReceipt; self.capturedAt = capturedAt
        self.stoppedAt = stoppedAt; self.stopReason = stopReason
        try validate(request: request)
    }

    func validate(request: TemporalEvidenceRuntimeCaptureRequestV1) throws {
        try request.validate()
        try admissionReceipt.validateTerminal(facts: facts, profile: request.request.profile)
        guard requestID == request.request.requestID,
              facts.kind == request.request.mediaKind,
              !bytes.isEmpty, UInt64(bytes.count) == facts.byteCount,
              capturedAt.timeIntervalSinceReferenceDate.isFinite,
              stoppedAt.timeIntervalSinceReferenceDate.isFinite,
              stoppedAt >= capturedAt,
              stoppedAt.timeIntervalSince(capturedAt) * 1_000
                >= Double(facts.durationMilliseconds),
              stopReason == admissionReceipt.terminalStopReason else {
            throw TemporalEvidenceCaptureFailureV1.limitExceeded
        }
    }
}

/// Device-local, noncanonical handle to a completed recording held by the
/// incumbent protected scratch lease. It intentionally carries no media bytes.
struct TemporalEvidencePendingReviewReferenceV1: Equatable, Sendable {
    let requestID: UUID
    let leaseID: UUID
    let relativeName: String
    let byteCount: UInt64
    let contentSHA256: String
    let facts: TemporalEvidenceMediaFactsV1
    let admissionReceipt: TemporalEvidenceIncrementalAdmissionReceiptV1
    let capturedAt: Date
    let stoppedAt: Date
    let stopReason: TemporalEvidenceStopReasonV1?

    init(
        request: TemporalEvidenceRuntimeCaptureRequestV1,
        result: TemporalEvidenceRuntimeCaptureResultV1,
        relativeName: String,
        contentSHA256: String
    ) throws {
        requestID = result.requestID; leaseID = request.lease.leaseID
        self.relativeName = relativeName; byteCount = result.facts.byteCount
        self.contentSHA256 = contentSHA256; facts = result.facts
        admissionReceipt = result.admissionReceipt; capturedAt = result.capturedAt
        stoppedAt = result.stoppedAt; stopReason = result.stopReason
        try result.validate(request: request)
        try validate(request: request)
    }

    func validate(request: TemporalEvidenceRuntimeCaptureRequestV1) throws {
        try request.validate()
        try admissionReceipt.validateTerminal(facts: facts, profile: request.request.profile)
        guard requestID == request.request.requestID,
              leaseID == request.lease.leaseID,
              relativeName == "temporal-evidence-\(requestID.uuidString.lowercased()).bin",
              !relativeName.contains("/"), !relativeName.contains("\\"),
              byteCount > 0,
              byteCount == facts.byteCount,
              byteCount <= request.request.profile.limit(for: facts.kind).maximumByteCount,
              MutationEnvelopeV1.isSHA256(contentSHA256),
              facts.kind == request.request.mediaKind,
              capturedAt.timeIntervalSinceReferenceDate.isFinite,
              stoppedAt.timeIntervalSinceReferenceDate.isFinite,
              stoppedAt >= capturedAt,
              stoppedAt.timeIntervalSince(capturedAt) * 1_000
                >= Double(facts.durationMilliseconds),
              stopReason == admissionReceipt.terminalStopReason else {
            throw TemporalEvidenceCaptureFailureV1.invalidTransition
        }
    }

    func validateBytes(_ bytes: Data, workspaceID: WorkspaceID, contentID: String) throws {
        guard !bytes.isEmpty, UInt64(bytes.count) == byteCount else {
            throw TemporalEvidenceCaptureFailureV1.limitExceeded
        }
        let observed = try ContentIntegrityV1.observe(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: contentID,
            data: bytes,
            mediaType: facts.codec.mediaType,
            algorithms: [.sha256]
        )
        guard observed.digests.digest(for: .sha256)?.hexadecimalValue == contentSHA256 else {
            throw TemporalEvidenceCaptureFailureV1.staleSource
        }
    }
}

struct TemporalClipReviewStateV1: Equatable, Sendable {
    let request: TemporalEvidenceCaptureRequestV1
    let permissionMatrix: TemporalEvidenceCapturePermissionMatrixV1
    let environment: TemporalEvidenceCaptureEnvironmentV1
    let scratchBinding: TemporalEvidenceScratchBindingV1
    let pendingReview: TemporalEvidencePendingReviewReferenceV1
    let playbackOffsetMilliseconds: UInt64
    let disposition: TemporalEvidenceCaptureDispositionV1

    init(
        request: TemporalEvidenceCaptureRequestV1,
        permissionMatrix: TemporalEvidenceCapturePermissionMatrixV1,
        environment: TemporalEvidenceCaptureEnvironmentV1,
        scratchBinding: TemporalEvidenceScratchBindingV1,
        pendingReview: TemporalEvidencePendingReviewReferenceV1,
        playbackOffsetMilliseconds: UInt64 = 0,
        disposition: TemporalEvidenceCaptureDispositionV1 = .reviewRequired
    ) throws {
        self.request = request; self.permissionMatrix = permissionMatrix
        self.environment = environment; self.scratchBinding = scratchBinding
        self.pendingReview = pendingReview
        self.playbackOffsetMilliseconds = playbackOffsetMilliseconds
        self.disposition = disposition
        try validate()
    }

    func validate() throws {
        let runtime = try TemporalEvidenceRuntimeCaptureRequestV1(
            request: request,
            permissionMatrix: permissionMatrix,
            environment: environment,
            lease: scratchBinding.lease
        )
        try pendingReview.validate(request: runtime)
        guard scratchBinding.request.leaseID == request.leaseID,
              scratchBinding.mutationID == request.mutationID,
              scratchBinding.contentID == request.contentID,
              scratchBinding.contentSHA256 == pendingReview.contentSHA256,
              playbackOffsetMilliseconds <= pendingReview.facts.durationMilliseconds,
              [.reviewRequired, .accepted, .rejected, .cancelled].contains(disposition) else {
            throw TemporalEvidenceCaptureFailureV1.invalidTransition
        }
    }

    func scrub(to offsetMilliseconds: UInt64) throws -> Self {
        try .init(request: request, permissionMatrix: permissionMatrix,
                  environment: environment, scratchBinding: scratchBinding,
                  pendingReview: pendingReview,
                  playbackOffsetMilliseconds: offsetMilliseconds,
                  disposition: disposition)
    }
}

struct AudioEvidenceCaptureFlowV1: Equatable, Sendable {
    let request: TemporalEvidenceCaptureRequestV1
    let disposition: TemporalEvidenceCaptureDispositionV1
    let review: TemporalClipReviewStateV1?
    init(request: TemporalEvidenceCaptureRequestV1,
         disposition: TemporalEvidenceCaptureDispositionV1,
         review: TemporalClipReviewStateV1? = nil) throws {
        try request.validate()
        let reviewMatches = review.map { $0.request == request } ?? true
        guard request.mediaKind == .audio,
              (disposition == .reviewRequired) == (review != nil), reviewMatches else {
            throw TemporalEvidenceCaptureFailureV1.invalidTransition
        }
        self.request = request; self.disposition = disposition; self.review = review
    }
}

struct VideoEvidenceCaptureFlowV1: Equatable, Sendable {
    let request: TemporalEvidenceCaptureRequestV1
    let disposition: TemporalEvidenceCaptureDispositionV1
    let review: TemporalClipReviewStateV1?
    init(request: TemporalEvidenceCaptureRequestV1,
         disposition: TemporalEvidenceCaptureDispositionV1,
         review: TemporalClipReviewStateV1? = nil) throws {
        try request.validate()
        let reviewMatches = review.map { $0.request == request } ?? true
        guard request.mediaKind == .video,
              (disposition == .reviewRequired) == (review != nil), reviewMatches else {
            throw TemporalEvidenceCaptureFailureV1.invalidTransition
        }
        self.request = request; self.disposition = disposition; self.review = review
    }
}

enum TemporalEvidenceCaptureLifecycleDeclarationV1 {
    static let persistentRowsAdded = 0
    static let schemaVersionAdded = 0
    static let ownsWriter = false
    static let foregroundOnly = true
    static let networkAllowed = false
    static let backgroundOrAmbientCaptureAllowed = false
    static let automaticTranscriptionOrRedactionAllowed = false
    static let nativeAdoptionAccepted = false
    static let physicalDeviceAcceptance = false
}

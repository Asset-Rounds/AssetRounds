import Foundation
import CryptoKit

private enum StructuredVoiceCaptureLimitsV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

/// C45 is a memory-only capture boundary.  It owns neither a store nor a
/// writer: durable draft changes remain exclusively behind C56 review.
enum StructuredVoiceCapturePersistenceBoundaryV1: String, Codable, Sendable {
    case nonpersistent = "NONPERSISTENT"
    case notApplicable = "NOT_APPLICABLE"
}

enum VoiceScratchDispositionV1: String, Codable, CaseIterable, Equatable, Sendable {
    /// Temporary capture audio is discarded. `preservingSource` in the scratch
    /// call determines whether a leased transcript has transferred to C56.
    case captureAudioDiscarded = "CAPTURE_AUDIO_DISCARDED"
    case cancelled = "CANCELLED"
    case backgrounded = "BACKGROUNDED"
    case interrupted = "INTERRUPTED"
    case permissionRevoked = "PERMISSION_REVOKED"
    case unavailable = "UNAVAILABLE"
    case stale = "STALE"
    case failed = "FAILED"
}

enum VoiceCaptureManualFallbackReasonV1: String, Codable, CaseIterable, Equatable, Sendable {
    case typeManually = "TYPE_MANUALLY"
    case permissionDenied = "PERMISSION_DENIED"
    case permissionRevoked = "PERMISSION_REVOKED"
    case permissionRestricted = "PERMISSION_RESTRICTED"
    case permissionNotDetermined = "PERMISSION_NOT_DETERMINED"
    case unsupportedLocale = "UNSUPPORTED_LOCALE"
    case unsupportedDevice = "UNSUPPORTED_DEVICE"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case backgrounded = "BACKGROUNDED"
    case interrupted = "INTERRUPTED"
    case cancelled = "CANCELLED"
    case unavailable = "UNAVAILABLE"
}

enum VoiceCaptureCapabilityDispositionV1: String, Codable, CaseIterable, Equatable, Sendable {
    case availableOnDevice = "AVAILABLE_ON_DEVICE"
    case permissionDenied = "PERMISSION_DENIED"
    case permissionRestricted = "PERMISSION_RESTRICTED"
    case permissionNotDetermined = "PERMISSION_NOT_DETERMINED"
    case unsupportedLocale = "UNSUPPORTED_LOCALE"
    case unsupportedDevice = "UNSUPPORTED_DEVICE"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case unavailable = "UNAVAILABLE"
}

enum VoiceCaptureFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case noActiveSession
    case sessionAlreadyActive
    case staleCallback
    case captureRejected
    case scratchCleanupFailed
    case cleanupInProgress
    case terminalCancellationPending
    case presentationInFlight
    case structuringFailed
    case reviewFailed
}

struct VoiceCaptureLifecycleGenerationV1: Codable, Equatable, Sendable {
    let permissionGenerationID: UUID
    let audioGenerationID: UUID
    let applicationGenerationID: UUID
    let protectedDataGenerationID: UUID
    let eraseGenerationID: UUID

    init(
        permissionGenerationID: UUID,
        audioGenerationID: UUID,
        applicationGenerationID: UUID,
        protectedDataGenerationID: UUID,
        eraseGenerationID: UUID
    ) throws {
        let values = [permissionGenerationID, audioGenerationID, applicationGenerationID,
                      protectedDataGenerationID, eraseGenerationID]
        guard values.allSatisfy({ $0 != StructuredVoiceCaptureLimitsV1.zeroUUID }) else {
            throw VoiceCaptureFailureV1.invalidValue
        }
        self.permissionGenerationID = permissionGenerationID
        self.audioGenerationID = audioGenerationID
        self.applicationGenerationID = applicationGenerationID
        self.protectedDataGenerationID = protectedDataGenerationID
        self.eraseGenerationID = eraseGenerationID
    }
}

/// The immutable target and lifecycle fence captured by one press-and-hold
/// action.  A source is deliberately supplied only with a final transcript:
/// C56 requires its SHA-256 to describe the actual UTF-8 transcript bytes.
struct StructuredVoiceCaptureContextV1: Codable, Equatable, Sendable {
    static let maximumCaptureSeconds: UInt64 = 60

    let sessionID: UUID
    let capability: AssistanceCapabilityReferenceV1
    let workspaceID: WorkspaceID
    let entity: WorkspaceEntityIdentityV1
    let targetRevision: UInt64
    let packageReleaseSHA256: String?
    let definitionReleaseSHA256: String?
    let lifecycleGeneration: VoiceCaptureLifecycleGenerationV1
    let explicitPushToTalk: Bool
    let onDeviceOnly: Bool
    let networkAccessForbidden: Bool
    let maximumDurationSeconds: UInt64
    let contextSHA256: String

    init(
        sessionID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        workspaceID: WorkspaceID,
        entity: WorkspaceEntityIdentityV1,
        targetRevision: UInt64,
        packageReleaseSHA256: String? = nil,
        definitionReleaseSHA256: String? = nil,
        lifecycleGeneration: VoiceCaptureLifecycleGenerationV1,
        explicitPushToTalk: Bool = true,
        onDeviceOnly: Bool = true,
        networkAccessForbidden: Bool = true,
        maximumDurationSeconds: UInt64 = StructuredVoiceCaptureContextV1.maximumCaptureSeconds
    ) throws {
        try capability.validate()
        _ = try WorkspaceEntityIdentityV1(kind: entity.kind, id: entity.id)
        try packageReleaseSHA256.map(VoiceStructuringLimitsV1.digest)
        try definitionReleaseSHA256.map(VoiceStructuringLimitsV1.digest)
        guard sessionID != StructuredVoiceCaptureLimitsV1.zeroUUID, targetRevision > 0, explicitPushToTalk,
              onDeviceOnly, networkAccessForbidden,
              maximumDurationSeconds == Self.maximumCaptureSeconds else {
            throw VoiceCaptureFailureV1.invalidValue
        }
        self.sessionID = sessionID
        self.capability = capability
        self.workspaceID = workspaceID
        self.entity = entity
        self.targetRevision = targetRevision
        self.packageReleaseSHA256 = packageReleaseSHA256
        self.definitionReleaseSHA256 = definitionReleaseSHA256
        self.lifecycleGeneration = lifecycleGeneration
        self.explicitPushToTalk = explicitPushToTalk
        self.onDeviceOnly = onDeviceOnly
        self.networkAccessForbidden = networkAccessForbidden
        self.maximumDurationSeconds = maximumDurationSeconds
        contextSHA256 = try Self.digest(
            sessionID: sessionID, capability: capability, workspaceID: workspaceID, entity: entity,
            targetRevision: targetRevision, packageReleaseSHA256: packageReleaseSHA256,
            definitionReleaseSHA256: definitionReleaseSHA256, lifecycleGeneration: lifecycleGeneration,
            explicitPushToTalk: explicitPushToTalk, onDeviceOnly: onDeviceOnly,
            networkAccessForbidden: networkAccessForbidden, maximumDurationSeconds: maximumDurationSeconds
        )
    }

    func validate() throws {
        try capability.validate()
        _ = try WorkspaceEntityIdentityV1(kind: entity.kind, id: entity.id)
        _ = try VoiceCaptureLifecycleGenerationV1(
            permissionGenerationID: lifecycleGeneration.permissionGenerationID,
            audioGenerationID: lifecycleGeneration.audioGenerationID,
            applicationGenerationID: lifecycleGeneration.applicationGenerationID,
            protectedDataGenerationID: lifecycleGeneration.protectedDataGenerationID,
            eraseGenerationID: lifecycleGeneration.eraseGenerationID
        )
        try packageReleaseSHA256.map(VoiceStructuringLimitsV1.digest)
        try definitionReleaseSHA256.map(VoiceStructuringLimitsV1.digest)
        guard sessionID != StructuredVoiceCaptureLimitsV1.zeroUUID, targetRevision > 0,
              explicitPushToTalk, onDeviceOnly, networkAccessForbidden,
              maximumDurationSeconds == Self.maximumCaptureSeconds else {
            throw VoiceCaptureFailureV1.invalidValue
        }
        guard contextSHA256 == (try Self.digest(
            sessionID: sessionID, capability: capability, workspaceID: workspaceID, entity: entity,
            targetRevision: targetRevision, packageReleaseSHA256: packageReleaseSHA256,
            definitionReleaseSHA256: definitionReleaseSHA256, lifecycleGeneration: lifecycleGeneration,
            explicitPushToTalk: explicitPushToTalk, onDeviceOnly: onDeviceOnly,
            networkAccessForbidden: networkAccessForbidden, maximumDurationSeconds: maximumDurationSeconds
        )) else { throw VoiceCaptureFailureV1.invalidDigest }
    }

    func proposalContext(source: AssistanceSourceReferenceV1) throws -> VoiceProposalContextV1 {
        try VoiceProposalContextV1(
            capability: capability, workspaceID: workspaceID, entity: entity,
            targetRevision: targetRevision, source: source,
            packageReleaseSHA256: packageReleaseSHA256,
            definitionReleaseSHA256: definitionReleaseSHA256
        )
    }

    func lifecycleAdmission(
        proposalID: UUID,
        operation: VoiceStructuringLifecycleOperationV1
    ) throws -> VoiceStructuringLifecycleAdmissionV1 {
        try VoiceStructuringLifecycleAdmissionV1(
            workspaceID: workspaceID, proposalID: proposalID, operation: operation,
            permissionGenerationID: lifecycleGeneration.permissionGenerationID,
            audioGenerationID: lifecycleGeneration.audioGenerationID,
            applicationGenerationID: lifecycleGeneration.applicationGenerationID,
            protectedDataGenerationID: lifecycleGeneration.protectedDataGenerationID,
            eraseGenerationID: lifecycleGeneration.eraseGenerationID
        )
    }

    private static func digest(
        sessionID: UUID, capability: AssistanceCapabilityReferenceV1, workspaceID: WorkspaceID,
        entity: WorkspaceEntityIdentityV1, targetRevision: UInt64, packageReleaseSHA256: String?,
        definitionReleaseSHA256: String?, lifecycleGeneration: VoiceCaptureLifecycleGenerationV1,
        explicitPushToTalk: Bool, onDeviceOnly: Bool, networkAccessForbidden: Bool,
        maximumDurationSeconds: UInt64
    ) throws -> String {
        struct Basis: Codable {
            let sessionID: UUID; let capability: AssistanceCapabilityReferenceV1; let workspaceID: WorkspaceID
            let entity: WorkspaceEntityIdentityV1; let targetRevision: UInt64; let packageReleaseSHA256: String?
            let definitionReleaseSHA256: String?; let lifecycleGeneration: VoiceCaptureLifecycleGenerationV1
            let explicitPushToTalk: Bool; let onDeviceOnly: Bool; let networkAccessForbidden: Bool
            let maximumDurationSeconds: UInt64
        }
        let data = try WorkspaceMutationCanonicalV1.data(Basis(
            sessionID: sessionID, capability: capability, workspaceID: workspaceID, entity: entity,
            targetRevision: targetRevision, packageReleaseSHA256: packageReleaseSHA256,
            definitionReleaseSHA256: definitionReleaseSHA256, lifecycleGeneration: lifecycleGeneration,
            explicitPushToTalk: explicitPushToTalk, onDeviceOnly: onDeviceOnly,
            networkAccessForbidden: networkAccessForbidden, maximumDurationSeconds: maximumDurationSeconds
        ))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct VoiceTranscriptConfidenceSpanV1: Codable, Equatable, Sendable {
    let sourceSpan: VoiceTranscriptUTF8SpanV1
    let confidence: Double

    init(sourceSpan: VoiceTranscriptUTF8SpanV1, confidence: Double) throws {
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw VoiceCaptureFailureV1.invalidValue
        }
        self.sourceSpan = sourceSpan
        self.confidence = confidence
    }
}

struct StructuredVoiceCapturedTranscriptV1: Codable, Equatable, Sendable {
    let sessionID: UUID
    let lifecycleGeneration: VoiceCaptureLifecycleGenerationV1
    let contextSHA256: String
    let callbackSequence: UInt64
    let transcript: String
    let source: AssistanceSourceReferenceV1
    let sourceSpans: [VoiceTranscriptUTF8SpanV1]
    let confidenceSpans: [VoiceTranscriptConfidenceSpanV1]
    let durationSeconds: UInt64
    let processedOnDevice: Bool
    let networkAccessUsed: Bool

    init(sessionID: UUID, lifecycleGeneration: VoiceCaptureLifecycleGenerationV1,
         contextSHA256: String, callbackSequence: UInt64, transcript: String,
         source: AssistanceSourceReferenceV1, sourceSpans: [VoiceTranscriptUTF8SpanV1],
         confidenceSpans: [VoiceTranscriptConfidenceSpanV1], durationSeconds: UInt64,
         processedOnDevice: Bool, networkAccessUsed: Bool) throws {
        try source.validate()
        _ = try VoiceCaptureLifecycleGenerationV1(
            permissionGenerationID: lifecycleGeneration.permissionGenerationID,
            audioGenerationID: lifecycleGeneration.audioGenerationID,
            applicationGenerationID: lifecycleGeneration.applicationGenerationID,
            protectedDataGenerationID: lifecycleGeneration.protectedDataGenerationID,
            eraseGenerationID: lifecycleGeneration.eraseGenerationID
        )
        guard sessionID != StructuredVoiceCaptureLimitsV1.zeroUUID, callbackSequence > 0, !transcript.isEmpty,
              transcript.utf8.count <= VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes,
              source.kind == .leasedScratch,
              source.contentSHA256 == Self.transcriptSHA256(transcript),
              durationSeconds <= StructuredVoiceCaptureContextV1.maximumCaptureSeconds,
              processedOnDevice, !networkAccessUsed else { throw VoiceCaptureFailureV1.invalidValue }
        try VoiceStructuringLimitsV1.digest(contextSHA256)
        try sourceSpans.forEach { try $0.validate(in: transcript) }
        try confidenceSpans.forEach { try $0.sourceSpan.validate(in: transcript) }
        guard !sourceSpans.isEmpty,
              sourceSpans == sourceSpans.sorted(by: Self.isOrdered),
              confidenceSpans == confidenceSpans.sorted { Self.isOrdered($0.sourceSpan, $1.sourceSpan) } else {
            throw VoiceCaptureFailureV1.invalidValue
        }
        for index in sourceSpans.indices.dropFirst() {
            guard sourceSpans[index].start >= sourceSpans[index - 1].end else {
                throw VoiceCaptureFailureV1.invalidValue
            }
        }
        for index in confidenceSpans.indices.dropFirst() {
            guard confidenceSpans[index].sourceSpan.start >= confidenceSpans[index - 1].sourceSpan.end else {
                throw VoiceCaptureFailureV1.invalidValue
            }
        }
        guard confidenceSpans.allSatisfy({ confidence in
            sourceSpans.contains { source in
                confidence.sourceSpan.start >= source.start
                    && confidence.sourceSpan.end <= source.end
            }
        }) else { throw VoiceCaptureFailureV1.invalidValue }
        self.sessionID = sessionID; self.lifecycleGeneration = lifecycleGeneration
        self.contextSHA256 = contextSHA256; self.callbackSequence = callbackSequence
        self.transcript = transcript; self.source = source; self.sourceSpans = sourceSpans
        self.confidenceSpans = confidenceSpans; self.durationSeconds = durationSeconds
        self.processedOnDevice = processedOnDevice; self.networkAccessUsed = networkAccessUsed
    }

    private static func isOrdered(_ lhs: VoiceTranscriptUTF8SpanV1, _ rhs: VoiceTranscriptUTF8SpanV1) -> Bool {
        (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }

    private static func transcriptSHA256(_ transcript: String) -> String {
        SHA256.hash(data: Data(transcript.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func validate() throws {
        _ = try Self(
            sessionID: sessionID, lifecycleGeneration: lifecycleGeneration,
            contextSHA256: contextSHA256, callbackSequence: callbackSequence,
            transcript: transcript, source: source, sourceSpans: sourceSpans,
            confidenceSpans: confidenceSpans, durationSeconds: durationSeconds,
            processedOnDevice: processedOnDevice, networkAccessUsed: networkAccessUsed
        )
    }
}

enum StructuredVoiceCaptureEventV1: Equatable, Sendable {
    case final(StructuredVoiceCapturedTranscriptV1)
    case failed(sessionID: UUID, lifecycleGeneration: VoiceCaptureLifecycleGenerationV1,
                contextSHA256: String, callbackSequence: UInt64,
                fallback: VoiceCaptureManualFallbackReasonV1)
}

@MainActor
protocol StructuredVoiceCapturePortV1: AnyObject {
    func beginPushToTalkCapture(_ context: StructuredVoiceCaptureContextV1) async throws
    func stopPushToTalkCapture(sessionID: UUID) async throws
    func cancelPushToTalkCapture(sessionID: UUID) async
}

@MainActor
protocol StructuredVoiceScratchLifecycleV1: AnyObject {
    func discardStructuredVoiceCaptureScratch(
        sessionID: UUID,
        disposition: VoiceScratchDispositionV1,
        preservingSource: AssistanceSourceReferenceV1?
    ) async throws
}

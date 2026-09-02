import AVFoundation
import CryptoKit
import Foundation
import Speech
import UIKit

/// The concrete iOS edge for C45.  It owns one explicit, memory-only
/// push-to-talk session and reports transcript updates back to the caller.
/// It never writes audio, calls a network service, or adopts a root route.
@MainActor
final class OnDevicePushToTalkVoiceCaptureAdapterV1:
    StructuredVoiceCapturePortV1,
    StructuredVoiceScratchLifecycleV1 {
    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    struct TranscriptUpdateV1: Sendable {
        let sessionID: UUID
        let lifecycleGeneration: VoiceCaptureLifecycleGenerationV1
        let contextSHA256: String
        let callbackSequence: UInt64
        let transcript: String
        let sourceSpans: [VoiceTranscriptUTF8SpanV1]
        let confidenceSpans: [VoiceTranscriptConfidenceSpanV1]
        let durationSeconds: UInt64
        let isFinal: Bool
    }

    typealias TranscriptUpdateHandler = @MainActor (TranscriptUpdateV1) -> Void
    typealias EventHandler = @MainActor (StructuredVoiceCaptureEventV1) -> Void

    @MainActor
    private final class ActiveCapture {
        let context: StructuredVoiceCaptureContextV1
        let recognizer: SFSpeechRecognizer
        let request: SFSpeechAudioBufferRecognitionRequest
        let audioEngine: AVAudioEngine
        let startedUptime: TimeInterval
        var recognitionTask: SFSpeechRecognitionTask?
        var callbackSequence: UInt64 = 0
        var tapInstalled = false
        var stopRequested = false

        init(
            context: StructuredVoiceCaptureContextV1,
            recognizer: SFSpeechRecognizer,
            request: SFSpeechAudioBufferRecognitionRequest,
            audioEngine: AVAudioEngine,
            startedUptime: TimeInterval
        ) {
            self.context = context
            self.recognizer = recognizer
            self.request = request
            self.audioEngine = audioEngine
            self.startedUptime = startedUptime
        }
    }

    private let defaultLocaleIdentifier: String?
    private let transcriptUpdateHandler: TranscriptUpdateHandler
    private let eventHandler: EventHandler
    private var activeCapture: ActiveCapture?
    private var expirationWorkItem: DispatchWorkItem?
    private var notificationTokens: [NSObjectProtocol] = []
    private var scratchDispositions: [UUID: VoiceScratchDispositionV1] = [:]
    private var preservedTranscriptSources: [UUID: AssistanceSourceReferenceV1] = [:]
    private var pendingSessionIDs: Set<UUID> = []
    private var cancelledPendingSessionIDs: Set<UUID> = []

    init(
        defaultLocaleIdentifier: String? = nil,
        onTranscriptUpdate: @escaping TranscriptUpdateHandler = { _ in },
        onEvent: @escaping EventHandler = { _ in }
    ) {
        self.defaultLocaleIdentifier = defaultLocaleIdentifier
        transcriptUpdateHandler = onTranscriptUpdate
        eventHandler = onEvent
    }

    // MARK: - Independently observable speech permissions

    func permissionDisposition() async throws -> SpeechPermissionDispositionV1 {
        Self.permissionSnapshot()
    }

    func requestMicrophonePermission() async throws -> SpeechPermissionDispositionV1 {
        guard AVAudioSession.sharedInstance().recordPermission == .undetermined else {
            return Self.permissionSnapshot()
        }

        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                Task { @MainActor in
                    continuation.resume(returning: Self.permissionSnapshot())
                }
            }
        }
    }

    func requestSpeechRecognitionPermission() async throws -> SpeechPermissionDispositionV1 {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
            return Self.permissionSnapshot()
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in
                    continuation.resume(returning: Self.permissionSnapshot())
                }
            }
        }
    }

    // MARK: - StructuredVoiceCapturePortV1

    func beginPushToTalkCapture(_ context: StructuredVoiceCaptureContextV1) async throws {
        try context.validate()
        guard activeCapture == nil else {
            throw VoiceCaptureFailureV1.sessionAlreadyActive
        }
        guard pendingSessionIDs.isEmpty else {
            throw VoiceCaptureFailureV1.sessionAlreadyActive
        }
        pendingSessionIDs.insert(context.sessionID)
        defer {
            pendingSessionIDs.remove(context.sessionID)
            cancelledPendingSessionIDs.remove(context.sessionID)
        }

        guard let locale = Self.supportedLocale(
            context.capability.localeIdentifier ?? defaultLocaleIdentifier ?? Locale.current.identifier
        ) else {
            emitFailure(for: context, sequence: 1, fallback: .unsupportedLocale)
            throw VoiceCaptureFailureV1.captureRejected
        }

        let permission = try await requestMicrophonePermission()
        try checkPendingCancellation(for: context)
        guard permission.microphone == .authorized else {
            emitFailure(
                for: context,
                sequence: 1,
                fallback: Self.manualFallback(for: permission.microphone)
            )
            throw VoiceCaptureFailureV1.captureRejected
        }

        let speechPermission = try await requestSpeechRecognitionPermission()
        try checkPendingCancellation(for: context)
        guard speechPermission.speechRecognition == .authorized else {
            emitFailure(
                for: context,
                sequence: 1,
                fallback: Self.manualFallback(for: speechPermission.speechRecognition)
            )
            throw VoiceCaptureFailureV1.captureRejected
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition,
              AVAudioSession.sharedInstance().isInputAvailable else {
            emitFailure(for: context, sequence: 1, fallback: .unsupportedDevice)
            throw VoiceCaptureFailureV1.captureRejected
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        try checkPendingCancellation(for: context)

        let session = ActiveCapture(
            context: context,
            recognizer: recognizer,
            request: request,
            audioEngine: AVAudioEngine(),
            startedUptime: ProcessInfo.processInfo.systemUptime
        )
        pendingSessionIDs.remove(context.sessionID)
        activeCapture = session

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])

            let inputNode = session.audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceCaptureFailureV1.captureRejected
            }

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) {
                [weak request] buffer, _ in
                request?.append(buffer)
            }
            session.tapInstalled = true
            installNotificationObservers(for: session)
            session.recognitionTask = recognizer.recognitionTask(
                with: request
            ) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    self?.handleRecognitionCallback(
                        result: result,
                        error: error,
                        sessionID: context.sessionID,
                        lifecycleGeneration: context.lifecycleGeneration,
                        contextSHA256: context.contextSHA256
                    )
                }
            }
            session.audioEngine.prepare()
            try session.audioEngine.start()
            scheduleExpiration(for: session)
        } catch {
            teardown(session)
            activeCapture = nil
            emitFailure(for: context, sequence: 1, fallback: .unavailable)
            throw VoiceCaptureFailureV1.captureRejected
        }
    }

    func stopPushToTalkCapture(sessionID: UUID) async throws {
        guard let session = activeCapture, session.context.sessionID == sessionID else {
            throw VoiceCaptureFailureV1.noActiveSession
        }
        session.stopRequested = true
        if session.tapInstalled {
            session.audioEngine.inputNode.removeTap(onBus: 0)
            session.tapInstalled = false
        }
        session.audioEngine.stop()
        session.request.endAudio()
    }

    func cancelPushToTalkCapture(sessionID: UUID) async {
        if pendingSessionIDs.contains(sessionID) {
            // `beginPushToTalkCapture` may be suspended in an OS permission
            // callback. Marking the pending session makes cancellation safe
            // and idempotent without allowing that callback to start audio.
            cancelledPendingSessionIDs.insert(sessionID)
            return
        }
        guard let session = activeCapture, session.context.sessionID == sessionID else {
            return
        }
        finishFailure(session, fallback: .cancelled)
    }

    // MARK: - StructuredVoiceScratchLifecycleV1

    func discardStructuredVoiceCaptureScratch(
        sessionID: UUID,
        disposition: VoiceScratchDispositionV1,
        preservingSource: AssistanceSourceReferenceV1?
    ) async throws {
        guard sessionID != Self.zeroUUID else {
            throw VoiceCaptureFailureV1.invalidValue
        }

        if disposition == .captureAudioDiscarded {
            guard let preservingSource,
                  preservingSource.kind == .leasedScratch else {
                throw VoiceCaptureFailureV1.invalidValue
            }
            try preservingSource.validate()
            if let existing = preservedTranscriptSources[sessionID], existing != preservingSource {
                throw VoiceCaptureFailureV1.invalidValue
            }
            // C56 receives this leased transcript source before this call.
            // Only temporary capture audio is discarded here; this typed
            // source remains available to C56 review and draft checkpointing.
            preservedTranscriptSources[sessionID] = preservingSource
        } else if preservingSource != nil {
            throw VoiceCaptureFailureV1.invalidValue
        }

        if let existing = scratchDispositions[sessionID] {
            // Idempotent retries must describe the same terminal operation;
            // a conflicting disposition is not allowed to rewrite its receipt.
            guard existing == disposition else {
                throw VoiceCaptureFailureV1.invalidValue
            }
            return
        }

        if let session = activeCapture, session.context.sessionID == sessionID {
            teardown(session)
            activeCapture = nil
        }
        // Record the disposition after validation and cleanup so a future
        // cleanup attempt remains possible if the operation ever fails.
        scratchDispositions[sessionID] = disposition
    }

    // MARK: - Runtime callbacks

    private func handleRecognitionCallback(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        sessionID: UUID,
        lifecycleGeneration: VoiceCaptureLifecycleGenerationV1,
        contextSHA256: String
    ) {
        guard let session = activeCapture,
              session.context.sessionID == sessionID,
              session.context.lifecycleGeneration == lifecycleGeneration,
              session.context.contextSHA256 == contextSHA256 else {
            return
        }

        let permission = Self.permissionSnapshot()
        guard permission.microphone == .authorized,
              permission.speechRecognition == .authorized else {
            finishFailure(session, fallback: .permissionRevoked)
            return
        }

        if let result {
            let transcript = result.bestTranscription.formattedString
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let spans = Self.spans(for: result.bestTranscription, in: transcript)
                let sequence = nextCallbackSequence(for: session)
                let update = TranscriptUpdateV1(
                    sessionID: sessionID,
                    lifecycleGeneration: lifecycleGeneration,
                    contextSHA256: contextSHA256,
                    callbackSequence: sequence,
                    transcript: transcript,
                    sourceSpans: spans.source,
                    confidenceSpans: spans.confidence,
                    durationSeconds: reportedElapsedSeconds(for: session),
                    isFinal: result.isFinal
                )
                transcriptUpdateHandler(update)

                if result.isFinal {
                    do {
                        let rawDurationSeconds = rawElapsedSeconds(for: session)
                        // Never admit a late final callback based on a clamped
                        // display duration. The raw monotonic duration is the
                        // authoritative 60-second boundary.
                        guard rawDurationSeconds <= Double(contextMaximumSeconds(session)),
                              transcript.utf8.count <= VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes else {
                            throw VoiceCaptureFailureV1.captureRejected
                        }
                        let source = try Self.scratchSource(
                            sessionID: sessionID,
                            transcript: transcript
                        )
                        let captured = try StructuredVoiceCapturedTranscriptV1(
                            sessionID: sessionID,
                            lifecycleGeneration: lifecycleGeneration,
                            contextSHA256: contextSHA256,
                            callbackSequence: nextCallbackSequence(for: session),
                            transcript: transcript,
                            source: source,
                            sourceSpans: spans.source,
                            confidenceSpans: spans.confidence,
                            durationSeconds: reportedElapsedSeconds(for: session),
                            processedOnDevice: true,
                            networkAccessUsed: false
                        )
                        finishFinal(session, captured: captured)
                    } catch {
                        finishFailure(session, fallback: .unavailable)
                    }
                    return
                }
            } else if result.isFinal {
                finishFailure(session, fallback: .unavailable)
                return
            }
        }

        if error != nil {
            finishFailure(session, fallback: .unavailable)
        }
    }

    private func installNotificationObservers(for session: ActiveCapture) {
        let center = NotificationCenter.default
        let sessionID = session.context.sessionID
        notificationTokens = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] note in
                let rawType = note.userInfo?[AVAudioSession.InterruptionTypeKey] as? UInt
                guard rawType == AVAudioSession.InterruptionType.began.rawValue else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.finishIfActive(sessionID: sessionID, fallback: .interrupted)
                }
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleRouteChange(sessionID: sessionID)
                }
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishIfActive(sessionID: sessionID, fallback: .backgrounded)
                }
            },
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePermissionChange(sessionID: sessionID)
                }
            }
        ]
    }

    private func handleRouteChange(sessionID: UUID) {
        guard let session = activeCapture, session.context.sessionID == sessionID else {
            return
        }
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.isInputAvailable, !audioSession.currentRoute.inputs.isEmpty else {
            finishFailure(session, fallback: .unavailable)
            return
        }
        if !session.stopRequested, !session.audioEngine.isRunning {
            finishFailure(session, fallback: .unavailable)
        }
    }

    private func handlePermissionChange(sessionID: UUID) {
        guard let session = activeCapture, session.context.sessionID == sessionID else {
            return
        }
        let permission = Self.permissionSnapshot()
        guard permission.microphone == .authorized,
              permission.speechRecognition == .authorized else {
            finishFailure(session, fallback: .permissionRevoked)
            return
        }
        handleRouteChange(sessionID: sessionID)
    }

    private func scheduleExpiration(for session: ActiveCapture) {
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      let active = self.activeCapture,
                      active.context.sessionID == session.context.sessionID else {
                    return
                }
                self.finishFailure(active, fallback: .unavailable)
            }
        }
        expirationWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(contextMaximumSeconds(session)),
            execute: item
        )
    }

    private func finishIfActive(sessionID: UUID, fallback: VoiceCaptureManualFallbackReasonV1) {
        guard let session = activeCapture, session.context.sessionID == sessionID else {
            return
        }
        finishFailure(session, fallback: fallback)
    }

    private func finishFailure(
        _ session: ActiveCapture,
        fallback: VoiceCaptureManualFallbackReasonV1
    ) {
        guard activeCapture === session else { return }
        let event = StructuredVoiceCaptureEventV1.failed(
            sessionID: session.context.sessionID,
            lifecycleGeneration: session.context.lifecycleGeneration,
            contextSHA256: session.context.contextSHA256,
            callbackSequence: nextCallbackSequence(for: session),
            fallback: fallback
        )
        teardown(session)
        activeCapture = nil
        eventHandler(event)
    }

    private func finishFinal(
        _ session: ActiveCapture,
        captured: StructuredVoiceCapturedTranscriptV1
    ) {
        guard activeCapture === session else { return }
        teardown(session)
        activeCapture = nil
        eventHandler(.final(captured))
    }

    private func teardown(_ session: ActiveCapture) {
        expirationWorkItem?.cancel()
        expirationWorkItem = nil
        let center = NotificationCenter.default
        for token in notificationTokens {
            center.removeObserver(token)
        }
        notificationTokens.removeAll()

        if session.tapInstalled {
            session.audioEngine.inputNode.removeTap(onBus: 0)
            session.tapInstalled = false
        }
        session.audioEngine.stop()
        session.request.endAudio()
        session.recognitionTask?.cancel()
        session.recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    private func nextCallbackSequence(for session: ActiveCapture) -> UInt64 {
        let (next, overflow) = session.callbackSequence.addingReportingOverflow(1)
        session.callbackSequence = overflow ? UInt64.max : next
        return session.callbackSequence
    }

    private func rawElapsedSeconds(for session: ActiveCapture) -> TimeInterval {
        max(0, ProcessInfo.processInfo.systemUptime - session.startedUptime)
    }

    private func reportedElapsedSeconds(for session: ActiveCapture) -> UInt64 {
        UInt64(
            min(
                Double(contextMaximumSeconds(session)),
                rawElapsedSeconds(for: session).rounded(.up)
            )
        )
    }

    private func contextMaximumSeconds(_ session: ActiveCapture) -> UInt64 {
        session.context.maximumDurationSeconds
    }

    private func checkPendingCancellation(
        for context: StructuredVoiceCaptureContextV1
    ) throws {
        guard cancelledPendingSessionIDs.remove(context.sessionID) != nil else {
            return
        }
        emitFailure(for: context, sequence: 1, fallback: .cancelled)
        throw VoiceCaptureFailureV1.captureRejected
    }

    private func emitFailure(
        for context: StructuredVoiceCaptureContextV1,
        sequence: UInt64,
        fallback: VoiceCaptureManualFallbackReasonV1
    ) {
        eventHandler(
            .failed(
                sessionID: context.sessionID,
                lifecycleGeneration: context.lifecycleGeneration,
                contextSHA256: context.contextSHA256,
                callbackSequence: sequence,
                fallback: fallback
            )
        )
    }

    private static func permissionSnapshot() -> SpeechPermissionDispositionV1 {
        let microphone: CapabilityPermissionDispositionV1
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            microphone = .notDetermined
        case .denied:
            microphone = .denied
        case .granted:
            microphone = .authorized
        @unknown default:
            microphone = .unavailable
        }

        let speechRecognition: CapabilityPermissionDispositionV1
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            speechRecognition = .notDetermined
        case .denied:
            speechRecognition = .denied
        case .restricted:
            speechRecognition = .restricted
        case .authorized:
            speechRecognition = .authorized
        @unknown default:
            speechRecognition = .unavailable
        }

        return try! SpeechPermissionDispositionV1(
            microphone: microphone,
            speechRecognition: speechRecognition,
            observedAt: Date()
        )
    }

    private static func supportedLocale(_ identifier: String) -> Locale? {
        let normalized = identifier.lowercased()
        return SFSpeechRecognizer.supportedLocales().first {
            $0.identifier.lowercased() == normalized
        }
    }

    private static func manualFallback(
        for disposition: CapabilityPermissionDispositionV1
    ) -> VoiceCaptureManualFallbackReasonV1 {
        switch disposition {
        case .denied:
            return .permissionDenied
        case .restricted:
            return .permissionRestricted
        case .notDetermined:
            return .permissionNotDetermined
        case .authorized:
            return .unavailable
        case .unavailable:
            return .unavailable
        }
    }

    private static func spans(
        for transcription: SFTranscription,
        in transcript: String
    ) -> (
        source: [VoiceTranscriptUTF8SpanV1],
        confidence: [VoiceTranscriptConfidenceSpanV1]
    ) {
        let value = transcript as NSString
        var sourceSpans: [VoiceTranscriptUTF8SpanV1] = []
        var confidenceSpans: [VoiceTranscriptConfidenceSpanV1] = []

        for segment in transcription.segments {
            let range = segment.substringRange
            guard range.location >= 0,
                  range.length > 0,
                  range.location <= value.length,
                  range.length <= value.length - range.location else {
                continue
            }
            let prefix = value.substring(with: NSRange(location: 0, length: range.location))
            let substring = value.substring(with: range)
            guard let span = try? VoiceTranscriptUTF8SpanV1(
                start: prefix.utf8.count,
                length: substring.utf8.count
            ) else {
                continue
            }
            guard (try? span.validate(in: transcript)) != nil else {
                continue
            }
            if !sourceSpans.contains(span) {
                sourceSpans.append(span)
            }

            let confidence = Double(segment.confidence)
            if confidence.isFinite,
               (0...1).contains(confidence),
               let confidenceSpan = try? VoiceTranscriptConfidenceSpanV1(
                   sourceSpan: span,
                   confidence: confidence
               ),
               !confidenceSpans.contains(where: {
                   $0.sourceSpan == confidenceSpan.sourceSpan && $0.confidence == confidenceSpan.confidence
               }) {
                confidenceSpans.append(confidenceSpan)
            }
        }

        sourceSpans.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        sourceSpans = sourceSpans.reduce(into: []) { result, span in
            guard result.last.map({ $0.end <= span.start }) ?? true else {
                return
            }
            result.append(span)
        }
        confidenceSpans.sort {
            ($0.sourceSpan.start, $0.sourceSpan.end)
                < ($1.sourceSpan.start, $1.sourceSpan.end)
        }
        confidenceSpans = confidenceSpans.reduce(into: []) { result, span in
            guard result.last.map({ $0.sourceSpan.end <= span.sourceSpan.start }) ?? true else {
                return
            }
            result.append(span)
        }
        return (sourceSpans, confidenceSpans)
    }

    private static func scratchSource(
        sessionID: UUID,
        transcript: String
    ) throws -> AssistanceSourceReferenceV1 {
        let digest = SHA256.hash(data: Data(transcript.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try AssistanceSourceReferenceV1(
            kind: .leasedScratch,
            sourceID: "voice-capture-\(sessionID.uuidString.lowercased())",
            revision: 1,
            contentSHA256: digest
        )
    }
}

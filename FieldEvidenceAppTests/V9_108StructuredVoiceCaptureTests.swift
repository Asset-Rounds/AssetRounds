import CryptoKit
import Foundation
import XCTest

@testable import FieldEvidenceApp

private enum C45 {
    static let now = Date(timeIntervalSince1970: 1_788_451_200)
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "C4500000-0000-4000-8000-%012x", n))! }
    static func sha(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func generation(_ slot: Int = 0) throws -> VoiceCaptureLifecycleGenerationV1 {
        try .init(permissionGenerationID: id(1 + slot), audioGenerationID: id(2 + slot), applicationGenerationID: id(3 + slot), protectedDataGenerationID: id(4 + slot), eraseGenerationID: id(5 + slot))
    }
    static func context(_ slot: Int = 0, revision: UInt64 = 7) throws -> StructuredVoiceCaptureContextV1 {
        try .init(sessionID: id(10 + slot), capability: AssistanceCapabilityReferenceV1(capabilityID: "STRUCTURED_VOICE_PROPOSAL", version: "STRUCTURED_VOICE_V1", localeIdentifier: "en-US"), workspaceID: WorkspaceID(rawValue: id(20)), entity: WorkspaceEntityIdentityV1(kind: .asset, id: id(30)), targetRevision: revision, lifecycleGeneration: generation(slot))
    }
    static func source(_ text: String) throws -> AssistanceSourceReferenceV1 { try .init(kind: .leasedScratch, sourceID: "c45-transcript", revision: 1, contentSHA256: sha(text)) }
    static func captured(_ context: StructuredVoiceCaptureContextV1, sequence: UInt64 = 1, text: String = "note: checked") throws -> StructuredVoiceCapturedTranscriptV1 {
        let span = try VoiceTranscriptUTF8SpanV1(start: 0, length: text.utf8.count)
        return try .init(sessionID: context.sessionID, lifecycleGeneration: context.lifecycleGeneration, contextSHA256: context.contextSHA256, callbackSequence: sequence, transcript: text, source: source(text), sourceSpans: [span], confidenceSpans: [try .init(sourceSpan: span, confidence: 0.9)], durationSeconds: 3, processedOnDevice: true, networkAccessUsed: false)
    }
    static func service() throws -> VoiceStructuringServiceV1 {
        let alias = try VoiceStructuringAliasV1(spokenAlias: "note", fieldID: "note", fieldKind: .noteText)
        let grammar = try VoiceStructuringGrammarReleaseV1(grammarID: "C45_VOICE_EN_US", version: 1, localeIdentifier: "en-US", aliases: [alias], releasedAt: now)
        let entry = try VoiceStructuringGrammarRegistryEntryV1(release: grammar, semanticFields: [VoiceStructuringSemanticFieldV1(purpose: .note)])
        return try VoiceStructuringServiceV1(registry: try .init(entries: [entry]), grammarID: grammar.grammarID, version: grammar.version, localeIdentifier: grammar.localeIdentifier, releaseSHA256: try grammar.releaseSHA256, now: { now }, makeID: { id(90) })
    }
    static func review(_ disposition: VoiceProposalFieldReviewDispositionV1) throws -> VoiceProposalFieldReviewV1 {
        switch disposition { case .accept, .edit: return try .init(fieldID: "note", disposition: disposition, reviewedValue: .text("checked")); case .reject: return try .init(fieldID: "note", disposition: disposition, reviewedValue: nil) }
    }
}

@MainActor private final class C45Capture: StructuredVoiceCapturePortV1 {
    var begun: [StructuredVoiceCaptureContextV1] = []; var stopped: [UUID] = []; var cancelled: [UUID] = []
    func beginPushToTalkCapture(_ context: StructuredVoiceCaptureContextV1) async throws { begun.append(context) }
    func stopPushToTalkCapture(sessionID: UUID) async throws { stopped.append(sessionID) }
    func cancelPushToTalkCapture(sessionID: UUID) async { cancelled.append(sessionID) }
}

@MainActor private final class C45Scratch: StructuredVoiceScratchLifecycleV1 {
    struct Call: Equatable { let sessionID: UUID; let disposition: VoiceScratchDispositionV1; let source: AssistanceSourceReferenceV1? }
    var calls: [Call] = []; var failuresRemaining = 0
    func discardStructuredVoiceCaptureScratch(sessionID: UUID, disposition: VoiceScratchDispositionV1, preservingSource: AssistanceSourceReferenceV1?) async throws {
        calls.append(.init(sessionID: sessionID, disposition: disposition, source: preservingSource))
        if failuresRemaining > 0 { failuresRemaining -= 1; throw VoiceCaptureFailureV1.scratchCleanupFailed }
    }
}

@MainActor private final class C45Review: VoicePushToTalkReviewingV1 {
    enum PresentationError: Error { case injected }
    var presented: [(StructuredVoiceProposalV1, VoiceStructuringLifecycleAdmissionV1)] = []; var fieldReviews: [VoiceProposalFieldReviewV1] = []; var rejected: [UUID] = []; var cancelled: [UUID] = []; var cancelFailuresRemaining = 0
    var suspendPresent = false; var presentInFlight = false; var presentFailure: Error?; private var presentContinuation: CheckedContinuation<Void, Never>?
    func present(_ proposal: StructuredVoiceProposalV1, admission: VoiceStructuringLifecycleAdmissionV1) async throws {
        presented.append((proposal, admission))
        if suspendPresent {
            presentInFlight = true
            await withCheckedContinuation { presentContinuation = $0 }
            presentInFlight = false
        }
        if let presentFailure { throw presentFailure }
    }
    func releasePresent() { presentContinuation?.resume(); presentContinuation = nil }
    func review(proposalID: UUID, fieldReview: VoiceProposalFieldReviewV1, admission: VoiceStructuringLifecycleAdmissionV1) async throws -> VoiceProposalDraftCheckpointResultV1? { fieldReviews.append(fieldReview); return nil }
    func finalizeReview(proposalID: UUID, admission: VoiceStructuringLifecycleAdmissionV1) async throws -> VoiceProposalReviewPlanV1 { throw VoiceStructuringFailureV1.incompleteReview }
    func reject(proposalID: UUID, admission: VoiceStructuringLifecycleAdmissionV1) async throws { rejected.append(proposalID) }
    func cancel(proposalID: UUID, admission: VoiceStructuringLifecycleAdmissionV1) async throws {
        cancelled.append(proposalID)
        if cancelFailuresRemaining > 0 { cancelFailuresRemaining -= 1; throw VoiceCaptureFailureV1.terminalCancellationPending }
    }
}

@MainActor private final class C45ReceiveProbe {
    var outcome: VoicePushToTalkCoordinatorV1.Outcome?
    var error: Error?
}

@MainActor final class V9_108StructuredVoiceCaptureTests: XCTestCase {
    private func coordinator(_ scratch: C45Scratch = C45Scratch(), capture: C45Capture = C45Capture(), review: C45Review = C45Review()) throws -> (VoicePushToTalkCoordinatorV1, C45Capture, C45Scratch, C45Review) { (try .init(capture: capture, scratch: scratch, structuring: C45.service(), review: review), capture, scratch, review) }
    private func corpus() throws -> [String: Any] {
        let name = "V23P04C45StructuredVoiceCaptureCorpusV1"
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures/V23/VoiceCapture") ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/V23/VoiceCapture/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func waitForPresent(_ review: C45Review, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<32 {
            if review.presentInFlight { return }
            await Task.yield()
        }
        XCTFail("presentation did not suspend", file: file, line: line)
    }

    func testV23P04C45G01ExplicitOnDeviceCaptureStructuresThenRequiresPerFieldReview() async throws {
        let (coordinator, capture, scratch, review) = try coordinator(); let context = try C45.context()
        let start = try await coordinator.start(context)
        XCTAssertEqual(start, .capturing(sessionID: context.sessionID)); XCTAssertEqual(capture.begun, [context])
        try await coordinator.stop(sessionID: context.sessionID)
        XCTAssertEqual(capture.stopped, [context.sessionID])
        let outcome = try await coordinator.receive(.final(try C45.captured(context)), currentTargetRevision: 7)
        guard case .proposal(let proposal) = outcome else { return XCTFail("expected proposal") }
        XCTAssertEqual(proposal.transcript, "note: checked"); XCTAssertEqual(proposal.fields.count, 1); XCTAssertEqual(review.presented.count, 1)
        XCTAssertEqual(review.fieldReviews.count, 0, "presentation cannot automatically checkpoint or write")
        XCTAssertEqual(scratch.calls.last?.disposition, .captureAudioDiscarded); XCTAssertEqual(scratch.calls.last?.source, proposal.context.source)
        let accepted = try await coordinator.reviewField(try C45.review(.accept), currentTargetRevision: 7)
        let edited = try await coordinator.reviewField(try C45.review(.edit), currentTargetRevision: 7)
        let rejected = try await coordinator.reviewField(try C45.review(.reject), currentTargetRevision: 7)
        XCTAssertNil(accepted); XCTAssertNil(edited); XCTAssertNil(rejected)
        XCTAssertEqual(review.fieldReviews.map(\.disposition), [.accept, .edit, .reject])
    }

    func testV23P04C45A01DeniedUnsupportedAndManualFallbackAreComplete() async throws {
        for fallback in [VoiceCaptureManualFallbackReasonV1.permissionDenied, .unsupportedLocale] {
            let (coordinator, capture, scratch, review) = try coordinator(); let context = try C45.context(fallback == .permissionDenied ? 100 : 200)
            _ = try await coordinator.start(context)
            let outcome = try await coordinator.receive(.failed(sessionID: context.sessionID, lifecycleGeneration: context.lifecycleGeneration, contextSHA256: context.contextSHA256, callbackSequence: 1, fallback: fallback), currentTargetRevision: 7)
            XCTAssertEqual(outcome, .manualFallback(fallback)); XCTAssertEqual(capture.cancelled, [context.sessionID]); XCTAssertEqual(scratch.calls.last?.disposition, .unavailable); XCTAssertTrue(review.presented.isEmpty)
        }
    }

    func testV23P04C45H01MalformedTranscriptAndHostileCallbacksFailClosed() async throws {
        let context = try C45.context(); let text = "note: checked"; let span = try VoiceTranscriptUTF8SpanV1(start: 0, length: text.utf8.count)
        XCTAssertThrowsError(try VoiceTranscriptConfidenceSpanV1(sourceSpan: span, confidence: .nan))
        XCTAssertThrowsError(try StructuredVoiceCapturedTranscriptV1(sessionID: context.sessionID, lifecycleGeneration: context.lifecycleGeneration, contextSHA256: context.contextSHA256, callbackSequence: 1, transcript: text, source: try C45.source("wrong"), sourceSpans: [span], confidenceSpans: [], durationSeconds: 3, processedOnDevice: true, networkAccessUsed: false))
        XCTAssertThrowsError(try StructuredVoiceCapturedTranscriptV1(sessionID: context.sessionID, lifecycleGeneration: context.lifecycleGeneration, contextSHA256: context.contextSHA256, callbackSequence: 1, transcript: text, source: try C45.source(text), sourceSpans: [span], confidenceSpans: [], durationSeconds: 61, processedOnDevice: true, networkAccessUsed: false))
        XCTAssertThrowsError(try StructuredVoiceCapturedTranscriptV1(sessionID: context.sessionID, lifecycleGeneration: context.lifecycleGeneration, contextSHA256: context.contextSHA256, callbackSequence: 1, transcript: text, source: try C45.source(text), sourceSpans: [span], confidenceSpans: [], durationSeconds: 3, processedOnDevice: true, networkAccessUsed: true))
        let (coordinator, _, scratch, review) = try coordinator(); _ = try await coordinator.start(context)
        let wrongGeneration = try StructuredVoiceCapturedTranscriptV1(sessionID: context.sessionID, lifecycleGeneration: try C45.generation(800), contextSHA256: context.contextSHA256, callbackSequence: 1, transcript: text, source: try C45.source(text), sourceSpans: [span], confidenceSpans: [try .init(sourceSpan: span, confidence: 0.9)], durationSeconds: 3, processedOnDevice: true, networkAccessUsed: false)
        await XCTAssertThrowsErrorAsync { try await coordinator.receive(.final(wrongGeneration), currentTargetRevision: 7) }
        await XCTAssertThrowsErrorAsync { try await coordinator.receive(.final(try C45.captured(try C45.context(300))), currentTargetRevision: 7) }
        await XCTAssertThrowsErrorAsync { try await coordinator.receive(.failed(sessionID: context.sessionID, lifecycleGeneration: context.lifecycleGeneration, contextSHA256: String(repeating: "0", count: 64), callbackSequence: 1, fallback: .unavailable), currentTargetRevision: 7) }
        XCTAssertTrue(scratch.calls.isEmpty); XCTAssertTrue(review.presented.isEmpty)

        let (duplicate, _, duplicateScratch, duplicateReview) = try coordinator(); _ = try await duplicate.start(try C45.context(900))
        let duplicateContext = try C45.context(900); let final = try C45.captured(duplicateContext, sequence: 2)
        _ = try await duplicate.receive(.final(final), currentTargetRevision: 7)
        await XCTAssertThrowsErrorAsync { try await duplicate.receive(.final(final), currentTargetRevision: 7) }
        XCTAssertEqual(duplicateReview.presented.count, 1); XCTAssertEqual(duplicateScratch.calls.count, 1)
    }

    func testV23P04C45I01CancellationBackgroundInterruptionRevisionAndCleanupRetryAreFenced() async throws {
        let context = try C45.context(); let (cancelled, capture, scratch, _) = try coordinator(); _ = try await cancelled.start(context)
        let cancelledOutcome = try await cancelled.cancel(sessionID: context.sessionID)
        XCTAssertEqual(cancelledOutcome, .cleaned(.cancelled)); XCTAssertEqual(capture.cancelled, [context.sessionID]); XCTAssertEqual(scratch.calls.map(\.disposition), [.cancelled])
        let (backgrounded, _, backgroundScratch, _) = try coordinator(); _ = try await backgrounded.start(try C45.context(400)); let backgroundOutcome = try await backgrounded.applicationDidEnterBackground(); XCTAssertEqual(backgroundOutcome, .manualFallback(.backgrounded)); XCTAssertEqual(backgroundScratch.calls.last?.disposition, .backgrounded)
        let retryScratch = C45Scratch(); retryScratch.failuresRemaining = 1; let (interrupted, _, retryProbe, _) = try coordinator(retryScratch); let interruptedContext = try C45.context(500); _ = try await interrupted.start(interruptedContext)
        await XCTAssertThrowsErrorAsync { try await interrupted.audioInterrupted() }; XCTAssertEqual(retryProbe.calls.count, 1); let retriedOutcome = try await interrupted.retryScratchCleanup(); XCTAssertEqual(retriedOutcome, .cleaned(.interrupted)); XCTAssertEqual(retryProbe.calls.count, 2)
        let (stale, _, staleScratch, _) = try coordinator(); _ = try await stale.start(try C45.context(600)); let staleOutcome = try await stale.targetRevisionDidChange(8); XCTAssertEqual(staleOutcome, .manualFallback(.typeManually)); XCTAssertEqual(staleScratch.calls.last?.disposition, .stale)

        let terminalScratch = C45Scratch(); let terminalReview = C45Review(); terminalReview.cancelFailuresRemaining = 1
        let (terminal, _, terminalProbe, reviewProbe) = try coordinator(terminalScratch, review: terminalReview)
        let terminalContext = try C45.context(650); _ = try await terminal.start(terminalContext)
        _ = try await terminal.receive(.final(try C45.captured(terminalContext)), currentTargetRevision: 7)
        await XCTAssertThrowsErrorAsync { try await terminal.audioInterrupted() }
        XCTAssertEqual(terminalProbe.calls.map(\.disposition), [.captureAudioDiscarded])
        await XCTAssertThrowsErrorAsync { try await terminal.reviewField(try C45.review(.accept), currentTargetRevision: 7) }
        let terminalOutcome = try await terminal.retryTerminalCancellation()
        XCTAssertEqual(terminalOutcome, .manualFallback(.interrupted)); XCTAssertEqual(reviewProbe.cancelled.count, 2)
    }

    func testV23P04C45R01StaleCallbacksHaveNoEffectAndFixtureIsClosed() async throws {
        let (coordinator, _, scratch, review) = try coordinator(); let context = try C45.context(700); _ = try await coordinator.start(context)
        let revokedOutcome = try await coordinator.permissionRevoked()
        XCTAssertEqual(revokedOutcome, .manualFallback(.permissionRevoked))
        await XCTAssertThrowsErrorAsync { try await coordinator.receive(.final(try C45.captured(context)), currentTargetRevision: 7) }
        XCTAssertEqual(scratch.calls.count, 1, "late callback cannot recreate scratch effects"); XCTAssertTrue(review.presented.isEmpty, "typed/manual draft remains untouched absent explicit review")
        XCTAssertEqual(try corpus()["cardID"] as? String, "V23-P04-C45"); XCTAssertEqual(try corpus()["schemaVersion"] as? Int, 1)

        let scratch = C45Scratch(); scratch.failuresRemaining = 2; let review = C45Review(); review.cancelFailuresRemaining = 2
        let (terminal, _, scratchProbe, reviewProbe) = try coordinator(scratch, review: review)
        let terminalContext = try C45.context(750); _ = try await terminal.start(terminalContext)
        await XCTAssertThrowsErrorAsync { try await terminal.receive(.final(try C45.captured(terminalContext)), currentTargetRevision: 7) }
        let proposal = try XCTUnwrap(reviewProbe.presented.first?.0)
        await XCTAssertThrowsErrorAsync { try await terminal.applicationDidEnterBackground() }
        XCTAssertEqual(scratchProbe.calls.last?.source, proposal.context.source)
        let cleanupOutcome = try await terminal.retryScratchCleanup()
        XCTAssertEqual(cleanupOutcome, .terminalCancellationPending(.backgrounded))
        await XCTAssertThrowsErrorAsync { try await terminal.retryTerminalCancellation() }
        let recoveredOutcome = try await terminal.retryTerminalCancellation()
        XCTAssertEqual(recoveredOutcome, .manualFallback(.backgrounded))
        XCTAssertEqual(reviewProbe.cancelled.count, 3)

        let clearScratch = C45Scratch(); clearScratch.failuresRemaining = 2; let clearReview = C45Review()
        let (cleared, _, clearedScratch, clearedReview) = try coordinator(clearScratch, review: clearReview)
        let clearContext = try C45.context(800); _ = try await cleared.start(clearContext)
        await XCTAssertThrowsErrorAsync { try await cleared.receive(.final(try C45.captured(clearContext)), currentTargetRevision: 7) }
        await XCTAssertThrowsErrorAsync { try await cleared.permissionRevoked() }
        let clearedOutcome = try await cleared.retryScratchCleanup()
        XCTAssertEqual(clearedOutcome, .cleaned(.permissionRevoked), "successful C56 cancellation clears its proposal before scratch retry")
        XCTAssertEqual(clearedReview.cancelled.count, 1)
    }

    func testV23P04C45R01DeferredPresentationTerminalIsFencedAndRetryable() async throws {
        let scratch = C45Scratch(); let review = C45Review(); review.suspendPresent = true; review.cancelFailuresRemaining = 1
        let (coordinator, capture, scratchProbe, reviewProbe) = try coordinator(scratch, review: review)
        let context = try C45.context(850); _ = try await coordinator.start(context)
        let receiveProbe = C45ReceiveProbe()
        let receiveTask = Task { @MainActor in
            do { receiveProbe.outcome = try await coordinator.receive(.final(try C45.captured(context)), currentTargetRevision: 7) }
            catch { receiveProbe.error = error }
        }
        await waitForPresent(reviewProbe)
        let staleOutcome = try await coordinator.targetRevisionDidChange(8)
        XCTAssertEqual(staleOutcome, .presentationTerminalPending(.stale))
        let backgroundOutcome = try await coordinator.applicationDidEnterBackground()
        XCTAssertEqual(backgroundOutcome, .presentationTerminalPending(.stale), "first terminal reason wins while C56 present is suspended")
        XCTAssertEqual(reviewProbe.cancelled.count, 0, "C56 cancellation cannot race its in-flight presentation")
        XCTAssertTrue(scratchProbe.calls.isEmpty)
        reviewProbe.releasePresent()
        await receiveTask.value
        XCTAssertNil(receiveProbe.outcome, "deferred terminal must not return proposal")
        XCTAssertEqual(receiveProbe.error as? VoiceCaptureFailureV1, .terminalCancellationPending)
        let proposal = try XCTUnwrap(reviewProbe.presented.first?.0)
        XCTAssertEqual(reviewProbe.cancelled, [proposal.proposalID])
        XCTAssertEqual(scratchProbe.calls.map(\.disposition), [.captureAudioDiscarded])
        XCTAssertEqual(scratchProbe.calls.last?.source, proposal.context.source)
        XCTAssertEqual(capture.cancelled, [context.sessionID, context.sessionID, context.sessionID])
        await XCTAssertThrowsErrorAsync { try await coordinator.reviewField(try C45.review(.accept), currentTargetRevision: 7) }
        let retried = try await coordinator.retryTerminalCancellation()
        XCTAssertEqual(retried, .manualFallback(.unavailable))
        XCTAssertEqual(reviewProbe.cancelled, [proposal.proposalID, proposal.proposalID])
    }

    func testV23P04C45R01DeferredPresentationFailureLeavesNoOrphan() async throws {
        let scratch = C45Scratch(); let review = C45Review(); review.suspendPresent = true; review.presentFailure = C45Review.PresentationError.injected
        let (coordinator, _, scratchProbe, reviewProbe) = try coordinator(scratch, review: review)
        let context = try C45.context(875); _ = try await coordinator.start(context)
        let receiveProbe = C45ReceiveProbe()
        let receiveTask = Task { @MainActor in
            do { receiveProbe.outcome = try await coordinator.receive(.final(try C45.captured(context)), currentTargetRevision: 7) }
            catch { receiveProbe.error = error }
        }
        await waitForPresent(reviewProbe)
        let backgroundOutcome = try await coordinator.applicationDidEnterBackground()
        XCTAssertEqual(backgroundOutcome, .presentationTerminalPending(.backgrounded))
        reviewProbe.releasePresent()
        await receiveTask.value
        XCTAssertNil(receiveProbe.outcome, "failed present cannot return an outcome")
        XCTAssertEqual(receiveProbe.error as? VoiceCaptureFailureV1, .structuringFailed)
        XCTAssertTrue(reviewProbe.cancelled.isEmpty, "failed C56 presentation owns no cancellable review state")
        XCTAssertEqual(scratchProbe.calls.last?.disposition, .failed)
        XCTAssertNil(scratchProbe.calls.last?.source)
        await XCTAssertThrowsErrorAsync { try await coordinator.retryTerminalCancellation() }
        await XCTAssertThrowsErrorAsync { try await coordinator.reviewField(try C45.review(.accept), currentTargetRevision: 7) }
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async { do { _ = try await expression(); XCTFail("expected error", file: file, line: line) } catch { } }

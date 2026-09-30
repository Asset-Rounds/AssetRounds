import Foundation
import SwiftUI

/// The UI state is supplied by the capture/review owner. The view does not
/// infer a successful capture from a button press or retain an audio session.
enum VoicePushToTalkCaptureStateV1: String, CaseIterable, Equatable, Sendable {
    case ready = "READY"
    case capturing = "CAPTURING"
    case processing = "PROCESSING"
    case review = "REVIEW"
    case manualFallback = "MANUAL_FALLBACK"
    case permissionDenied = "PERMISSION_DENIED"
    case permissionRevoked = "PERMISSION_REVOKED"
    case unsupported = "UNSUPPORTED"
    case offline = "OFFLINE"
    case interrupted = "INTERRUPTED"
    case backgrounded = "BACKGROUNDED"
    case cancelled = "CANCELLED"
    case staleTarget = "STALE_TARGET"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case storageUnavailable = "STORAGE_UNAVAILABLE"
    case failed = "FAILED"
}

enum VoicePushToTalkDraftStateV1: String, CaseIterable, Equatable, Sendable {
    case current = "CURRENT"
    case interrupted = "INTERRUPTED"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case storageUnavailable = "STORAGE_UNAVAILABLE"
    case stale = "STALE"
    case unavailable = "UNAVAILABLE"
}

/// Existing draft context is presentation-only. The ordinary draft authority
/// remains responsible for checkpoints, revision checks, and durable receipts.
struct VoicePushToTalkDraftPresentationV1: Equatable, Sendable, Identifiable {
    let draftID: UUID
    let label: String
    let targetRevision: UInt64
    let manualText: String
    let state: VoicePushToTalkDraftStateV1
    let canEdit: Bool

    var id: UUID { draftID }

    init(
        draftID: UUID,
        label: String = "Existing work draft",
        targetRevision: UInt64,
        manualText: String = "",
        state: VoicePushToTalkDraftStateV1 = .current,
        canEdit: Bool = true
    ) {
        self.draftID = draftID
        self.label = label
        self.targetRevision = targetRevision
        self.manualText = manualText
        self.state = state
        self.canEdit = canEdit
    }
}

enum VoicePushToTalkFieldReviewStateV1: String, CaseIterable, Equatable, Sendable {
    case pending = "PENDING"
    case accepted = "ACCEPTED_REQUESTED"
    case edited = "EDIT_REQUESTED"
    case rejected = "REJECTED_REQUESTED"
    case needsManualReview = "NEEDS_MANUAL_REVIEW"
}

/// One field card combines the exact C56 proposal with optional caller-bound
/// confidence/review presentation. Confidence never becomes a correctness or
/// acceptance decision in this value.
struct VoicePushToTalkFieldPresentationV1: Equatable, Sendable, Identifiable {
    let field: StructuredVoiceFieldProposalV1
    let label: String
    let confidenceSpan: VoiceTranscriptConfidenceSpanV1?
    let reviewState: VoicePushToTalkFieldReviewStateV1
    let editedText: String
    let message: String?

    var id: String { field.fieldID }
    var displayLabel: String { label.isEmpty ? field.fieldID : label }

    init(
        field: StructuredVoiceFieldProposalV1,
        label: String? = nil,
        confidenceSpan: VoiceTranscriptConfidenceSpanV1? = nil,
        reviewState: VoicePushToTalkFieldReviewStateV1 = .pending,
        editedText: String = "",
        message: String? = nil
    ) {
        self.field = field
        self.label = label ?? field.fieldID
        self.confidenceSpan = confidenceSpan
        self.reviewState = reviewState
        self.editedText = editedText
        self.message = message
    }
}

enum VoicePushToTalkOperationStateV1: String, CaseIterable, Equatable, Sendable {
    case idle = "IDLE"
    case requesting = "REQUESTING"
    case awaitingReceipt = "AWAITING_RECEIPT"
    case receiptReturned = "RECEIPT_RETURNED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case stale = "STALE"
}

struct VoicePushToTalkOperationPresentationV1: Equatable, Sendable {
    let state: VoicePushToTalkOperationStateV1
    let message: String?

    init(
        state: VoicePushToTalkOperationStateV1 = .idle,
        message: String? = nil
    ) {
        self.state = state
        self.message = message
    }
}

/// The caller supplies this complete projection after each capture/review
/// transition. It deliberately carries no audio bytes, writer, route, store,
/// or platform-recognition object.
struct VoicePushToTalkCaptureProjectionV1: Equatable, Sendable {
    let draft: VoicePushToTalkDraftPresentationV1
    let captureContext: StructuredVoiceCaptureContextV1?
    let state: VoicePushToTalkCaptureStateV1
    let elapsedSeconds: UInt64
    let fallbackReason: VoiceCaptureManualFallbackReasonV1?
    let scratchDisposition: VoiceScratchDispositionV1?
    let proposal: StructuredVoiceProposalV1?
    let confidenceSpans: [VoiceTranscriptConfidenceSpanV1]
    let fields: [VoicePushToTalkFieldPresentationV1]
    let operation: VoicePushToTalkOperationPresentationV1
    let errorMessage: String?
    let canStartCapture: Bool

    init(
        draft: VoicePushToTalkDraftPresentationV1,
        captureContext: StructuredVoiceCaptureContextV1? = nil,
        state: VoicePushToTalkCaptureStateV1 = .ready,
        elapsedSeconds: UInt64 = 0,
        fallbackReason: VoiceCaptureManualFallbackReasonV1? = nil,
        scratchDisposition: VoiceScratchDispositionV1? = nil,
        proposal: StructuredVoiceProposalV1? = nil,
        confidenceSpans: [VoiceTranscriptConfidenceSpanV1] = [],
        fields: [VoicePushToTalkFieldPresentationV1] = [],
        operation: VoicePushToTalkOperationPresentationV1 = .init(),
        errorMessage: String? = nil,
        canStartCapture: Bool = true
    ) {
        self.draft = draft
        self.captureContext = captureContext
        self.state = state
        self.elapsedSeconds = elapsedSeconds
        self.fallbackReason = fallbackReason
        self.scratchDisposition = scratchDisposition
        self.proposal = proposal
        self.confidenceSpans = confidenceSpans
        self.fields = fields
        self.operation = operation
        self.errorMessage = errorMessage
        self.canStartCapture = canStartCapture
    }

    var sessionID: UUID? { captureContext?.sessionID }
    var proposalID: UUID? { proposal?.proposalID }
    var transcript: String? { proposal?.transcript }

    var presentedFields: [VoicePushToTalkFieldPresentationV1] {
        if !fields.isEmpty {
            return fields.map { value in
                guard value.confidenceSpan == nil,
                      let confidence = confidenceSpan(for: value.field) else {
                    return value
                }
                return VoicePushToTalkFieldPresentationV1(
                    field: value.field,
                    label: value.label,
                    confidenceSpan: confidence,
                    reviewState: value.reviewState,
                    editedText: value.editedText,
                    message: value.message
                )
            }
        }
        guard let proposal else { return [] }
        return proposal.fields.map { field in
            VoicePushToTalkFieldPresentationV1(
                field: field,
                confidenceSpan: confidenceSpan(for: field)
            )
        }
    }

    var hasReviewedAllFields: Bool {
        !presentedFields.isEmpty
            && presentedFields.allSatisfy {
                $0.reviewState != .pending && $0.reviewState != .needsManualReview
            }
    }

    private func confidenceSpan(
        for field: StructuredVoiceFieldProposalV1
    ) -> VoiceTranscriptConfidenceSpanV1? {
        confidenceSpans.first { span in
            span.sourceSpan.start < field.sourceSpan.end
                && field.sourceSpan.start < span.sourceSpan.end
        }
    }
}

typealias VoicePushToTalkCaptureModelV1 = VoicePushToTalkCaptureProjectionV1

/// Typed requests emitted by the view. `VoicePushToTalkCoordinatorV1` owns
/// capture, cleanup, C56 review, and the ordinary draft checkpoint authority;
/// the view never invokes a writer or treats a request as a durable result.
enum VoicePushToTalkCaptureCommandV1: Equatable, Sendable {
    case start(context: StructuredVoiceCaptureContextV1)
    case stop(sessionID: UUID)
    case cancel(sessionID: UUID)
    case retry
    case manualEntry(text: String)
    case acceptField(proposalID: UUID, review: VoiceProposalFieldReviewV1)
    case editField(
        proposalID: UUID,
        fieldID: String,
        fieldKind: VoiceStructuredFieldKindV1,
        valueText: String
    )
    case rejectField(proposalID: UUID, review: VoiceProposalFieldReviewV1)
    case finalizeReview(proposalID: UUID)
    case rejectProposal(proposalID: UUID)
}

/// Contained iPhone C45 push-to-talk and structured-review surface.
///
/// This view is intentionally a no-launch surface before S10.6. It presents
/// caller-supplied state and sends typed requests only. On-device recognition,
/// lifecycle fencing, scratch cleanup, C56 per-field review, and ordinary
/// draft persistence remain outside the view.
@MainActor
struct VoicePushToTalkCaptureView: View {
    static let cardID = "V23-P04-C45"
    static let containedSurfaceOnly = true
    static let iPhoneOnly = true
    static let captureUIRuntimeOwnedByP04C45 = true
    static let appShellAdoptionEnabled = false
    static let rootAdoptionEnabled = false
    static let nativeAdoptionEnabled = false
    static let nativeLaunchAdoptionEnabled = false
    static let hostedAdoptionEnabled = false
    static let physicalDeviceAcceptanceEnabled = false
    static let acceptanceEnabled = false
    static let acceptanceCredit = false
    static let releaseEnabled = false
    static let liveAdoptionEnabled = false
    static let s10_6ReconciliationRequired = true
    static let automaticWrite = false
    static let continuousListening = false
    static let wakeWord = false
    static let cloudOrNetworkFallback = false
    static let recordingArchive = false
    static let nonpersistent = true
    static let newRoot = false
    static let newWriter = false
    static let newStore = false
    static let newModel = false
    static let newMigration = false
    static let acceptedOrEditedValuesUseExistingDraftAuthority = true
    static let confidenceIsInformationalOnly = true
    static let manualFallbackComplete = true
    static let maximumCaptureSeconds = StructuredVoiceCaptureContextV1.maximumCaptureSeconds

    static let screenAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.screen"
    static let draftAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.draft"
    static let speakDetailsAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.speak-details"
    static let captureAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.capture"
    static let stopAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.stop"
    static let countdownAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.countdown"
    static let processingAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.processing"
    static let transcriptAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.transcript"
    static let fieldsAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.fields"
    static let manualFallbackAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.manual-fallback"
    static let recoveryAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.recovery"
    static let errorAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.error"
    static let statusAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.status"
    static let finishReviewAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.finish-review"
    static let cancelAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.cancel"
    static let rejectProposalAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.reject-proposal"
    static let boundariesAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.boundaries"
    static let manualEntryFieldAccessibilityIdentifier = "v23.p04.c45.structured-voice-capture.manual-fallback.field"
    static let fieldAccessibilityIdentifierPrefix = "v23.p04.c45.structured-voice-capture.field."
    static let fieldReviewAccessibilityIdentifierPrefix = "v23.p04.c45.structured-voice-capture.field-review."

    // Compatibility names keep the visible action and its automation target
    // discoverable without creating a second rendered identifier.
    static let startAccessibilityIdentifier = speakDetailsAccessibilityIdentifier
    static let speakAccessibilityIdentifier = speakDetailsAccessibilityIdentifier
    static let fieldReviewAccessibilityIdentifier = fieldsAccessibilityIdentifier

    static let fixedAccessibilityIdentifiers = [
        screenAccessibilityIdentifier,
        draftAccessibilityIdentifier,
        speakDetailsAccessibilityIdentifier,
        captureAccessibilityIdentifier,
        stopAccessibilityIdentifier,
        countdownAccessibilityIdentifier,
        processingAccessibilityIdentifier,
        transcriptAccessibilityIdentifier,
        fieldsAccessibilityIdentifier,
        manualFallbackAccessibilityIdentifier,
        recoveryAccessibilityIdentifier,
        errorAccessibilityIdentifier,
        statusAccessibilityIdentifier,
        finishReviewAccessibilityIdentifier,
        cancelAccessibilityIdentifier,
        rejectProposalAccessibilityIdentifier,
        boundariesAccessibilityIdentifier,
        manualEntryFieldAccessibilityIdentifier
    ]

    let model: VoicePushToTalkCaptureProjectionV1
    let onCommand: @MainActor (VoicePushToTalkCaptureCommandV1) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?
    @FocusState private var focusedField: InputField?

    @State private var manualText: String
    @State private var editedValues: [String: String] = [:]
    @State private var editingFieldID: String?
    @State private var localErrorMessage: String?
    @State private var localStatusMessage: String?

    private enum FocusTarget: Hashable {
        case heading
        case capture
        case transcript
        case manual
        case error
        case status
    }

    private enum InputField: Hashable {
        case manual
        case edit(String)
    }

    init(
        model: VoicePushToTalkCaptureProjectionV1,
        onCommand: @escaping @MainActor (VoicePushToTalkCaptureCommandV1) -> Void = { _ in }
    ) {
        self.model = model
        self.onCommand = onCommand
        _manualText = State(initialValue: model.draft.manualText)
    }

    init(
        projection: VoicePushToTalkCaptureProjectionV1,
        onCommand: @escaping @MainActor (VoicePushToTalkCaptureCommandV1) -> Void = { _ in }
    ) {
        self.init(model: projection, onCommand: onCommand)
    }

    init(
        draft: VoicePushToTalkDraftPresentationV1,
        captureContext: StructuredVoiceCaptureContextV1? = nil,
        state: VoicePushToTalkCaptureStateV1 = .ready,
        elapsedSeconds: UInt64 = 0,
        fallbackReason: VoiceCaptureManualFallbackReasonV1? = nil,
        scratchDisposition: VoiceScratchDispositionV1? = nil,
        proposal: StructuredVoiceProposalV1? = nil,
        confidenceSpans: [VoiceTranscriptConfidenceSpanV1] = [],
        fields: [VoicePushToTalkFieldPresentationV1] = [],
        operation: VoicePushToTalkOperationPresentationV1 = .init(),
        errorMessage: String? = nil,
        canStartCapture: Bool = true,
        onCommand: @escaping @MainActor (VoicePushToTalkCaptureCommandV1) -> Void = { _ in }
    ) {
        self.init(
            model: VoicePushToTalkCaptureProjectionV1(
                draft: draft,
                captureContext: captureContext,
                state: state,
                elapsedSeconds: elapsedSeconds,
                fallbackReason: fallbackReason,
                scratchDisposition: scratchDisposition,
                proposal: proposal,
                confidenceSpans: confidenceSpans,
                fields: fields,
                operation: operation,
                errorMessage: errorMessage,
                canStartCapture: canStartCapture
            ),
            onCommand: onCommand
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                draftContext
                captureControls
                if model.proposal != nil {
                    transcript
                    fieldReview
                }
                manualFallback
                recovery
                errorSummary
                operationStatus
                boundaries
            }
            .padding(DesignTokens.Spacing.medium)
            .accessibilityElement(children: .contain)
        }
        .navigationTitle("Speak details")
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            if displayedErrorMessage != nil || stateRequiresRecovery {
                moveAccessibilityFocus(to: .error)
            } else {
                moveAccessibilityFocus(to: .heading)
            }
        }
        .onChange(of: model.state) { _, newValue in
            if newValue == .review {
                moveAccessibilityFocus(to: .transcript)
            } else if newValue == .capturing {
                moveAccessibilityFocus(to: .capture)
            } else if stateRequiresRecovery {
                moveAccessibilityFocus(to: .error)
            }
        }
        .onChange(of: model.errorMessage) { _, newValue in
            if newValue != nil { moveAccessibilityFocus(to: .error) }
        }
        .onChange(of: model.operation.state) { _, _ in
            if model.operation.message != nil || localStatusMessage != nil {
                moveAccessibilityFocus(to: .status)
            }
        }
        .environment(\.layoutDirection, layoutDirection)
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var displayedErrorMessage: String? {
        localErrorMessage ?? model.errorMessage
    }

    private var currentSessionID: UUID? {
        model.sessionID
    }

    private var canReviewFields: Bool {
        model.state == .review
            && model.proposalID != nil
            && model.draft.state == .current
            && model.draft.canEdit
            && model.operation.state != .awaitingReceipt
            && model.operation.state != .stale
    }

    private var canStartCapture: Bool {
        guard model.canStartCapture,
              model.captureContext != nil,
              model.draft.state == .current,
              model.draft.canEdit else { return false }
        switch model.state {
        case .ready, .manualFallback, .permissionDenied, .permissionRevoked, .cancelled, .failed:
            return true
        case .capturing, .processing, .review, .unsupported, .offline, .interrupted,
             .backgrounded, .staleTarget, .protectedDataUnavailable, .storageUnavailable:
            return false
        }
    }

    private var stateRequiresRecovery: Bool {
        switch model.state {
        case .ready, .capturing, .processing, .review:
            return false
        case .manualFallback, .permissionDenied, .permissionRevoked, .unsupported, .offline,
             .interrupted, .backgrounded, .cancelled, .staleTarget, .protectedDataUnavailable,
             .storageUnavailable, .failed:
            return true
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Speak details")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("Optional push-to-talk assistance for this existing draft. Press Speak details to start one explicit, on-device capture; there is no continuous listening or wake word.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var draftContext: some View {
        WorklightCard {
            sectionHeading("Existing draft", identifier: Self.draftAccessibilityIdentifier)
            valueRow("Draft", value: model.draft.label)
            valueRow("Draft revision", value: "\(model.draft.targetRevision)")
            valueRow("Draft state", value: draftStateText(model.draft.state))
            Text("The complete typed path stays available. Voice proposals are review-only until an explicit per-field request crosses the existing ordinary draft authority.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let context = model.captureContext {
                valueRow("Voice target revision", value: "\(context.targetRevision)")
                Text("The capture target is fixed by the supplied context. If that revision changes, the caller must mark this session stale and return to manual entry.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Speak details is unavailable until the caller supplies a current StructuredVoiceCaptureContextV1. Manual entry remains complete.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var captureControls: some View {
        WorklightCard {
            sectionHeading("Capture", identifier: Self.captureAccessibilityIdentifier)
            Text(captureStateText)
                .font(.body.weight(.semibold))
                .foregroundStyle(captureStateColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($accessibilityFocus, equals: .capture)

            switch model.state {
            case .capturing:
                captureIndicator
                countdown
                if let sessionID = currentSessionID {
                    Button("Stop speaking") {
                        send(.stop(sessionID: sessionID), status: "Stop requested. Waiting for the caller's final on-device transcript; no proposal or draft effect is claimed.")
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .keyboardShortcut("x", modifiers: [.command])
                    .accessibilityHint("Stops this explicit push-to-talk capture. It does not accept a transcript or write the draft.")
                    .accessibilityIdentifier(Self.stopAccessibilityIdentifier)

                    Button("Cancel voice capture") {
                        send(.cancel(sessionID: sessionID), status: "Cancellation requested. Temporary capture scratch and any unfinished utterance remain subject to the caller's cleanup result; no draft effect is claimed.")
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint("Cancels capture and returns to the complete manual path.")
                    .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
                }
            case .processing:
                Text("The caller is processing the stopped capture on device. Review begins only after a validated StructuredVoiceProposalV1 is supplied.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.processingAccessibilityIdentifier)
                if let sessionID = currentSessionID {
                    Button("Cancel voice processing") {
                        send(.cancel(sessionID: sessionID), status: "Cancellation requested. No transcript, proposal, or draft effect is claimed.")
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
                }
            case .review:
                Text("A validated proposal is ready. Review every field and choose Accept, Edit, or Reject before requesting review closure.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.processingAccessibilityIdentifier)
                if let proposalID = model.proposalID {
                    Button("Discard voice suggestions") {
                        send(.rejectProposal(proposalID: proposalID), status: "Discard requested. Rejected suggestions remain nonpersistent; no draft rollback or completion is claimed.")
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint("Rejects the complete proposal through the existing review authority without changing the existing draft.")
                    .accessibilityIdentifier(Self.rejectProposalAccessibilityIdentifier)
                }
            default:
                Text(captureStateDetail)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let context = model.captureContext {
                    Button("Speak details") {
                        send(.start(context: context), status: "Speak details requested. The caller must start explicit on-device capture; no microphone, transcript, or draft effect is claimed by this button press.")
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .disabled(!canStartCapture)
                    .keyboardShortcut("s", modifiers: [.command])
                    .accessibilityHint("Starts one explicit push-to-talk capture for at most 60 seconds. It does not continuously listen or use a wake word.")
                    .accessibilityIdentifier(Self.speakDetailsAccessibilityIdentifier)
                } else {
                    Text("Speak details is unavailable until a current capture context is supplied. Use the manual entry below.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.speakDetailsAccessibilityIdentifier)
                }
            }
            if let scratchDisposition = model.scratchDisposition {
                valueRow("Temporary scratch disposition", value: scratchDispositionText(scratchDisposition))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var captureIndicator: some View {
        Label("Capture active", systemImage: "mic.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.attentionText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityValue("On-device capture is active. Stop or cancel explicitly.")
    }

    private var countdown: some View {
        let elapsed = min(model.elapsedSeconds, Self.maximumCaptureSeconds)
        let remaining = Self.maximumCaptureSeconds - elapsed
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Capture time: \(elapsed) of \(Self.maximumCaptureSeconds) seconds; \(remaining) seconds remaining")
                .font(.body.weight(.semibold))
                .foregroundStyle(remaining == 0 ? DesignTokens.Colors.attentionText : DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(elapsed), total: Double(Self.maximumCaptureSeconds))
                .accessibilityLabel("Capture time limit")
                .accessibilityValue(remaining == 0 ? "60 seconds reached" : "\(remaining) seconds remaining")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.countdownAccessibilityIdentifier)
    }

    private var transcript: some View {
        WorklightCard {
            sectionHeading("Transcript", identifier: Self.transcriptAccessibilityIdentifier)
            if let transcript = model.transcript {
                Text(transcript)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Captured transcript")
                    .accessibilityValue(transcript)
                Text("This transcript is a temporary, on-device review input. It is not a recording archive, correctness proof, diagnosis, compliance finding, identity claim, or final draft result.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let proposal = model.proposal, !proposal.unmatchedClauses.isEmpty {
                    Text("\(proposal.unmatchedClauses.count) transcript segment\(proposal.unmatchedClauses.count == 1 ? "" : "s") needs manual handling. No value is inferred for an unmatched segment.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.attentionText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No transcript is supplied. Return to Speak details or continue with manual entry; no speech result is inferred.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var fieldReview: some View {
        WorklightCard {
            sectionHeading("Review each field", identifier: Self.fieldsAccessibilityIdentifier)
            Text("Each proposal is tied to an exact UTF-8 transcript span. Confidence is informational only and never decides correctness, verification, approval, or acceptance. Every field needs an explicit Accept, Edit, or Reject request.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            let fields = model.presentedFields
            if fields.isEmpty {
                Text("No structured fields are supplied. Manual entry remains complete; no draft value is inferred.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    fieldCard(field, position: index + 1)
                }
                if let proposalID = model.proposalID {
                    Button("Finish voice review") {
                        send(.finalizeReview(proposalID: proposalID), status: "Review closure requested through C56. No Saved or Complete claim is made until the caller returns its validated result.")
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .disabled(!model.hasReviewedAllFields || !canReviewFields)
                    .accessibilityHint(model.hasReviewedAllFields ? "Requests C56 review closure. It does not claim the ordinary draft is Saved or Complete." : "Review every field with Accept, Edit, or Reject before requesting closure.")
                    .accessibilityIdentifier(Self.finishReviewAccessibilityIdentifier)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func fieldCard(
        _ presentation: VoicePushToTalkFieldPresentationV1,
        position: Int
    ) -> some View {
        let baseID = fieldIdentifier(presentation.field.fieldID)
        let fieldLabel = "Field \(position): \(presentation.displayLabel)"
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(fieldLabel)
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow("Field ID", value: presentation.field.fieldID)
            valueRow("Resolution", value: resolutionText(presentation.field.resolution))
            valueRow("Proposed value", value: fieldValueText(presentation.field.proposedValue, kind: presentation.field.kind))
            valueRow("Exact source span", value: sourceSpanText(presentation.field.sourceSpan))
            valueRow("Source text", value: sourceText(for: presentation.field))
            Text(confidenceText(presentation.confidenceSpan))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Review state: \(reviewStateText(presentation.reviewState))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(reviewStateColor(presentation.reviewState))
                .fixedSize(horizontal: false, vertical: true)

            if let message = presentation.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if editingFieldID == presentation.id {
                TextField(
                    "Edit value for \(presentation.displayLabel)",
                    text: editedValueBinding(for: presentation)
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 6)
                .focused($focusedField, equals: .edit(presentation.id))
                .accessibilityLabel("Edit \(fieldLabel)")
                .accessibilityHint("Enter a manual value. The caller validates its type and sends it through the ordinary draft authority; typing does not write the draft.")
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).edit-field")

                Button("Apply edit for \(fieldLabel)") {
                    submitEdit(presentation)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(!canReviewFields)
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).apply-edit")

                Button("Cancel edit for \(fieldLabel)") {
                    editingFieldID = nil
                    focusedField = nil
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).cancel-edit")
            } else {
                Button("Accept \(fieldLabel)") {
                    submitAccept(presentation)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canReviewFields || !acceptIsAvailable(presentation.field))
                .accessibilityHint(acceptIsAvailable(presentation.field) ? "Requests acceptance of this exact structured proposal through C56. It does not claim Saved or Complete." : "Accept is unavailable because this field is ambiguous or unsupported; edit it manually or reject it.")
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).accept")

                Button("Edit \(fieldLabel)") {
                    beginEdit(presentation)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canReviewFields)
                .accessibilityHint("Opens a full keyboard-editable value field. The caller validates the typed value before ordinary draft review.")
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).edit")

                Button("Reject \(fieldLabel)") {
                    submitReject(presentation)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canReviewFields)
                .accessibilityHint("Rejects this proposal field through C56 without writing the rejected value to the draft.")
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).reject")
            }
        }
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(Self.fieldAccessibilityIdentifierPrefix)\(baseID)")
    }

    private var manualFallback: some View {
        WorklightCard {
            sectionHeading("Manual entry", identifier: Self.manualFallbackAccessibilityIdentifier)
            Text("Manual entry is the complete fallback for permission denial or revocation, unsupported locale/device, offline use, interruption, backgrounding, cancellation, stale targets, protected data, storage pressure, and relaunch. Your typed text is not treated as Saved until the ordinary draft authority returns its result.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $manualText)
                .frame(minHeight: 132)
                .padding(DesignTokens.Spacing.small)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.Colors.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                        .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
                }
                .focused($focusedField, equals: .manual)
                .accessibilityLabel("Manual draft entry")
                .accessibilityHint("Type or edit the existing draft with the full keyboard path. Text changes do not start speech and do not write until you explicitly continue.")
                .accessibilityIdentifier(Self.manualEntryFieldAccessibilityIdentifier)
            Button("Continue with manual entry") {
                submitManualEntry()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!model.draft.canEdit)
            .keyboardShortcut("m", modifiers: [.command])
            .accessibilityHint("Sends the current typed text to the existing ordinary draft authority. It does not claim Saved or Complete.")
            .accessibilityIdentifier("\(Self.manualFallbackAccessibilityIdentifier).continue")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recovery: some View {
        if stateRequiresRecovery || model.draft.state != .current {
            WorklightCard {
                sectionHeading("Recovery", identifier: Self.recoveryAccessibilityIdentifier)
                Text(recoveryText)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The caller must re-read the current draft/context and fence late callbacks before retrying. This view never infers a partial transcript, proposal, checkpoint, or receipt.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if canRetryCapture {
                    Button("Retry voice capture") {
                        send(.retry, status: "Retry requested. The caller must re-check permission, lifecycle generations, target revision, and scratch state; no effect is claimed.")
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint("Retries only after the caller reports a current valid capture context. Manual entry remains available.")
                    .accessibilityIdentifier("\(Self.recoveryAccessibilityIdentifier).retry")
                }
                Button("Return focus to manual entry") {
                    focusedField = .manual
                    moveAccessibilityFocus(to: .manual)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint("Moves focus to the complete keyboard/manual draft path.")
                .accessibilityIdentifier("\(Self.recoveryAccessibilityIdentifier).manual")
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var errorSummary: some View {
        if let displayedErrorMessage {
            WorklightCard {
                Label("Voice capture needs attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(displayedErrorMessage)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .error)
                Text("No partial canonical draft effect is inferred. Review the current supplied state, preserve the typed fallback, and retry the same intent only after the caller reports recovery.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.errorAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private var operationStatus: some View {
        let message = localStatusMessage ?? model.operation.message
        if let message {
            WorklightCard {
                sectionHeading("Operation status", identifier: "\(Self.statusAccessibilityIdentifier).heading")
                Text(message)
                    .font(.body)
                    .foregroundStyle(operationColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .status)
                Text(operationBoundaryText)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
        }
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading("Accessibility and boundaries", identifier: Self.boundariesAccessibilityIdentifier)
            Text("Every action has a visible text label and a stable VoiceOver/Voice Control identifier. Switch Control, external keyboard, and motor access use the same buttons and text fields; no microphone gesture, wake word, or icon-only action is required.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("At Accessibility Dynamic Type sizes content reflows vertically without truncation. Leading alignment supports RTL, system controls retain contrast and hit targets, and Reduce Motion removes view-owned state-change animation.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Capture is on-device only, nonpersistent, and has no cloud/network fallback or recording archive. Accepted or edited fields request the existing C56 ordinary draft authority; this screen never claims Saved, Complete, Verified, Approved, identity, authority, diagnosis, compliance, delivery, or legal effect.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("This is an iPhone contained surface only. Native/root/hosted/physical acceptance and release adoption remain false pending S10.6 reconciliation.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func sectionHeading(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func valueRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Text(value)
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func editedValueBinding(
        for presentation: VoicePushToTalkFieldPresentationV1
    ) -> Binding<String> {
        Binding(
            get: {
                editedValues[presentation.id]
                    ?? (presentation.editedText.isEmpty
                        ? fieldValueText(presentation.field.proposedValue, kind: presentation.field.kind)
                        : presentation.editedText)
            },
            set: { editedValues[presentation.id] = $0 }
        )
    }

    private func beginEdit(_ presentation: VoicePushToTalkFieldPresentationV1) {
        editingFieldID = presentation.id
        if editedValues[presentation.id] == nil {
            editedValues[presentation.id] = presentation.editedText.isEmpty
                ? fieldValueText(presentation.field.proposedValue, kind: presentation.field.kind)
                : presentation.editedText
        }
        focusedField = .edit(presentation.id)
    }

    private func submitAccept(_ presentation: VoicePushToTalkFieldPresentationV1) {
        guard let proposalID = model.proposalID,
              let value = presentation.field.proposedValue,
              acceptIsAvailable(presentation.field),
              let review = try? VoiceProposalFieldReviewV1(
                  fieldID: presentation.field.fieldID,
                  disposition: .accept,
                  reviewedValue: value
              ) else {
            presentError("This field is not an exact proposal. Edit it manually or reject it; no value was sent.")
            return
        }
        send(
            .acceptField(proposalID: proposalID, review: review),
            status: "Accept request sent for \(presentation.displayLabel). Waiting for C56's ordinary draft authority; no Saved or Complete claim is made."
        )
    }

    private func submitEdit(_ presentation: VoicePushToTalkFieldPresentationV1) {
        guard let proposalID = model.proposalID else {
            presentError("No current proposal is supplied. Keep the typed fallback and retry after the caller supplies a current review target.")
            return
        }
        let value = editedValues[presentation.id, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            presentError("Enter a value before applying this edit.", focus: .edit(presentation.id))
            return
        }
        guard value.utf8.count <= VoiceStructuringLimitsV1.maximumTextUTF8Bytes else {
            presentError("This edited value is too long for the bounded voice field. Use a shorter value or the manual draft path.", focus: .edit(presentation.id))
            return
        }
        send(
            .editField(
                proposalID: proposalID,
                fieldID: presentation.field.fieldID,
                fieldKind: presentation.field.kind,
                valueText: value
            ),
            status: "Edit request sent for \(presentation.displayLabel). The caller must convert and validate the typed value through C56; no Saved or Complete claim is made."
        )
        editingFieldID = nil
        focusedField = nil
    }

    private func submitReject(_ presentation: VoicePushToTalkFieldPresentationV1) {
        guard let proposalID = model.proposalID,
              let review = try? VoiceProposalFieldReviewV1(
                  fieldID: presentation.field.fieldID,
                  disposition: .reject,
                  reviewedValue: nil
              ) else {
            presentError("This proposal field cannot be rejected from the supplied state. Keep the manual path available and reload the review target.")
            return
        }
        send(
            .rejectField(proposalID: proposalID, review: review),
            status: "Reject request sent for \(presentation.displayLabel). The rejected value remains nonpersistent; no draft effect is claimed."
        )
    }

    private func submitManualEntry() {
        localErrorMessage = nil
        let text = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            presentError("Enter a manual draft value or keep the existing typed text. No empty value was sent.", focus: .manual)
            return
        }
        guard text.utf8.count <= VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes else {
            presentError("The manual draft text is above the bounded input limit. Use a shorter value and try again.", focus: .manual)
            return
        }
        send(
            .manualEntry(text: text),
            status: "Manual-entry request sent to the existing draft authority. No Saved or Complete claim is made."
        )
    }

    private func send(
        _ command: VoicePushToTalkCaptureCommandV1,
        status: String
    ) {
        localErrorMessage = nil
        localStatusMessage = status
        moveAccessibilityFocus(to: .status)
        onCommand(command)
    }

    private func presentError(_ message: String, focus: InputField? = nil) {
        localErrorMessage = message
        localStatusMessage = nil
        if let focus { focusedField = focus }
        moveAccessibilityFocus(to: .error)
    }

    private func moveAccessibilityFocus(to target: FocusTarget) {
        accessibilityFocus = nil
        Task { @MainActor in
            await Task.yield()
            accessibilityFocus = target
        }
    }

    private func acceptIsAvailable(_ field: StructuredVoiceFieldProposalV1) -> Bool {
        field.resolution == .exact && field.proposedValue != nil
    }

    private func fieldIdentifier(_ fieldID: String) -> String {
        fieldID
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func sourceText(for field: StructuredVoiceFieldProposalV1) -> String {
        guard let transcript = model.transcript else { return "Source text unavailable; reload the supplied transcript." }
        let bytes = Array(transcript.utf8)
        let start = field.sourceSpan.start
        let end = field.sourceSpan.end
        guard start >= 0, end > start, end <= bytes.count else {
            return "Source span unavailable; reload the supplied proposal."
        }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func sourceSpanText(_ span: VoiceTranscriptUTF8SpanV1) -> String {
        "UTF-8 bytes \(span.start)..<\(span.end) (start \(span.start), length \(span.length))"
    }

    private func fieldValueText(
        _ value: VoiceStructuredFieldValueV1?,
        kind: VoiceStructuredFieldKindV1
    ) -> String {
        guard let value else {
            switch kind {
            case .materialDescriptionAndQuantity:
                return "No structured quantity supplied; manual review required"
            default:
                return "No value supplied"
            }
        }
        switch value {
        case .text(let text):
            return text
        case .allowedEnum(let word):
            return word
        case .exactNumber(let decimal):
            return "\(decimalText(decimal.mantissa, scale: decimal.scale)) \(decimal.unit.rawValue.lowercased())"
        case .durationSeconds(let seconds):
            return "\(seconds) seconds"
        case .material(let material):
            if let quantity = material.quantity {
                return "\(decimalText(quantity.mantissa, scale: quantity.scale)) \(quantity.unit.rawValue.lowercased()) \(material.description)"
            }
            return material.description
        }
    }

    private func decimalText(_ mantissa: Int64, scale: Int) -> String {
        let raw = String(mantissa)
        let negative = raw.hasPrefix("-")
        let digits = negative ? String(raw.dropFirst()) : raw
        guard scale > 0 else { return raw }
        let padded = String(repeating: "0", count: max(0, scale - digits.count + 1)) + digits
        let split = padded.index(padded.endIndex, offsetBy: -scale)
        return (negative ? "-" : "") + String(padded[..<split]) + "." + String(padded[split...])
    }

    private func confidenceText(_ span: VoiceTranscriptConfidenceSpanV1?) -> String {
        guard let span else {
            return "Confidence: not supplied; informational only, not a correctness decision."
        }
        let percent = Int((span.confidence * 100).rounded())
        return "Confidence: \(percent)% (informational only; not a correctness, verification, or approval decision)."
    }

    private func resolutionText(_ resolution: VoiceStructuringResolutionV1) -> String {
        switch resolution {
        case .exact:
            return "Exact explicit grammar match"
        case .ambiguous:
            return "Ambiguous; manual edit or rejection required"
        case .unsupported:
            return "Unsupported; manual entry required"
        }
    }

    private func reviewStateText(_ state: VoicePushToTalkFieldReviewStateV1) -> String {
        switch state {
        case .pending:
            return "Pending explicit decision"
        case .accepted:
            return "Acceptance requested; caller result not yet claimed"
        case .edited:
            return "Edit requested; caller result not yet claimed"
        case .rejected:
            return "Rejection requested; no value write claimed"
        case .needsManualReview:
            return "Manual review required"
        }
    }

    private func reviewStateColor(_ state: VoicePushToTalkFieldReviewStateV1) -> Color {
        switch state {
        case .accepted:
            return DesignTokens.Colors.completeText
        case .edited, .rejected, .needsManualReview:
            return DesignTokens.Colors.attentionText
        case .pending:
            return DesignTokens.Colors.secondaryText
        }
    }

    private var captureStateText: String {
        switch model.state {
        case .ready: return "Ready for one explicit push-to-talk capture"
        case .capturing: return "Capturing on device"
        case .processing: return "Processing stopped capture"
        case .review: return "Review required before draft authority"
        case .manualFallback: return "Manual fallback available"
        case .permissionDenied: return "Microphone or speech permission denied"
        case .permissionRevoked: return "Microphone or speech permission revoked"
        case .unsupported: return "On-device speech unsupported"
        case .offline: return "Offline; manual path preserved"
        case .interrupted: return "Capture interrupted"
        case .backgrounded: return "Capture stopped after backgrounding"
        case .cancelled: return "Capture cancelled"
        case .staleTarget: return "Capture target is stale"
        case .protectedDataUnavailable: return "Protected data unavailable"
        case .storageUnavailable: return "Local storage unavailable"
        case .failed: return "Capture failed; recovery required"
        }
    }

    private var captureStateDetail: String {
        switch model.state {
        case .ready:
            return "Press Speak details only when you want one explicit utterance. The caller supplies the current lifecycle-fenced context and starts the 60-second on-device session."
        case .manualFallback:
            return fallbackDetail
        case .permissionDenied, .permissionRevoked:
            return "Speech access is unavailable. Manual entry below is complete and remains usable without another permission prompt or a network fallback."
        case .unsupported:
            return "This device or locale does not report the required on-device recognition capability. No cloud fallback is used; continue manually."
        case .offline:
            return "The capture path has no network fallback. Continue with manual entry while the caller rechecks the local capability state."
        case .interrupted, .backgrounded, .cancelled, .staleTarget, .protectedDataUnavailable,
             .storageUnavailable, .failed:
            return recoveryText
        case .capturing, .processing, .review:
            return ""
        }
    }

    private var fallbackDetail: String {
        guard let fallbackReason = model.fallbackReason else {
            return "The voice path returned to manual entry. No transcript or draft effect is inferred."
        }
        return "\(fallbackReasonText(fallbackReason)) Manual entry remains complete; no transcript, proposal, or draft effect is inferred."
    }

    private var recoveryText: String {
        switch model.state {
        case .staleTarget:
            return "The draft target revision changed or could not be revalidated. Reload the current draft/context before retrying; keep the typed fallback."
        case .protectedDataUnavailable:
            return "Protected local data is unavailable. No transcript, proposal, scratch, or draft effect is reconstructed. Retry after protected data becomes available."
        case .storageUnavailable:
            return "Local storage is unavailable or under pressure. No scratch cleanup or draft checkpoint is claimed; retry after storage recovery."
        case .interrupted:
            return "Audio capture was interrupted. The caller must fence the callback and clean temporary scratch; manual text remains available."
        case .backgrounded:
            return "The app moved to the background. This foreground-only capture does not continue silently; return to manual entry or retry explicitly."
        case .cancelled:
            return "Capture was cancelled. The unfinished utterance is not a transcript, proposal, or draft write."
        case .failed:
            return "The capture or structuring request failed. The caller must report cleanup/retry truth before another attempt."
        case .manualFallback, .permissionDenied, .permissionRevoked, .unsupported, .offline:
            return fallbackDetail
        case .ready, .capturing, .processing, .review:
            return "Manual entry remains available while the caller supplies a current state."
        }
    }

    private func fallbackReasonText(_ reason: VoiceCaptureManualFallbackReasonV1) -> String {
        switch reason {
        case .typeManually: return "Manual entry was selected."
        case .permissionDenied: return "Microphone or speech permission was denied."
        case .permissionRevoked: return "Microphone or speech permission was revoked."
        case .permissionRestricted: return "Microphone or speech permission is restricted."
        case .permissionNotDetermined: return "Permission is not determined."
        case .unsupportedLocale: return "The selected locale is unsupported for on-device recognition."
        case .unsupportedDevice: return "This device does not support the required on-device recognition path."
        case .protectedDataUnavailable: return "Protected data is unavailable."
        case .backgrounded: return "The app was backgrounded during foreground-only capture."
        case .interrupted: return "Audio capture was interrupted."
        case .cancelled: return "Capture was cancelled."
        case .unavailable: return "The on-device capture path is unavailable."
        }
    }

    private var canRetryCapture: Bool {
        canStartCapture && model.state != .unsupported && model.state != .offline
    }

    private var captureStateColor: Color {
        switch model.state {
        case .ready, .processing, .review:
            return DesignTokens.Colors.informationText
        case .capturing:
            return DesignTokens.Colors.attentionText
        case .manualFallback, .permissionDenied, .permissionRevoked, .unsupported, .offline,
             .interrupted, .backgrounded, .cancelled, .staleTarget, .protectedDataUnavailable,
             .storageUnavailable, .failed:
            return DesignTokens.Colors.attentionText
        }
    }

    private var operationColor: Color {
        switch model.operation.state {
        case .receiptReturned:
            return DesignTokens.Colors.completeText
        case .failed, .stale:
            return DesignTokens.Colors.blockedText
        case .cancelled:
            return DesignTokens.Colors.attentionText
        case .idle, .requesting, .awaitingReceipt:
            return DesignTokens.Colors.informationText
        }
    }

    private var operationBoundaryText: String {
        switch model.operation.state {
        case .receiptReturned:
            return "The caller supplied an operation result. This view does not infer Saved, Complete, or any additional canonical effect."
        case .failed, .stale:
            return "The operation did not produce a confirmed canonical result. Review the supplied error and reload before retrying."
        case .cancelled:
            return "Cancellation makes no completion, transcript, proposal, or draft-effect claim."
        case .requesting, .awaitingReceipt:
            return "A request is not a durable receipt and does not prove a draft effect."
        case .idle:
            return "No canonical operation result is supplied."
        }
    }

    private func draftStateText(_ state: VoicePushToTalkDraftStateV1) -> String {
        switch state {
        case .current: return "Current supplied draft"
        case .interrupted: return "Draft interrupted; recovery required"
        case .protectedDataUnavailable: return "Draft held while protected data is unavailable"
        case .storageUnavailable: return "Draft held while storage is unavailable"
        case .stale: return "Draft target is stale"
        case .unavailable: return "Draft unavailable; no draft result claimed"
        }
    }

    private func scratchDispositionText(_ disposition: VoiceScratchDispositionV1) -> String {
        switch disposition {
        case .captureAudioDiscarded:
            return "Capture audio discarded; scratch cleanup completed"
        case .cancelled:
            return "Cancelled; cleanup requested"
        case .backgrounded:
            return "Backgrounded; cleanup requested"
        case .interrupted:
            return "Interrupted; cleanup requested"
        case .permissionRevoked:
            return "Permission revoked; cleanup requested"
        case .unavailable:
            return "Unavailable; cleanup requested"
        case .stale:
            return "Stale; cleanup requested"
        case .failed:
            return "Failed; cleanup requested"
        }
    }
}

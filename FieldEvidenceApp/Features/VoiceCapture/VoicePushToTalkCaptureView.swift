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
        label: String = BundledLocalizationCatalogV1.v30Text(.voiceCaptureExistingWorkDraft),
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
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.voiceCaptureNavigationTitle))
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
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var draftContext: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftHeading), identifier: Self.draftAccessibilityIdentifier)
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraft), value: model.draft.label)
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftRevision), value: "\(model.draft.targetRevision)")
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftState), value: draftStateText(model.draft.state))
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let context = model.captureContext {
                valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureTargetRevision), value: "\(context.targetRevision)")
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureTargetDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureContextUnavailable))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var captureControls: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureCaptureHeading), identifier: Self.captureAccessibilityIdentifier)
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
                    Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureStopSpeaking)) {
                        send(.stop(sessionID: sessionID), status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureStopRequested))
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .keyboardShortcut("x", modifiers: [.command])
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureStopHint))
                    .accessibilityIdentifier(Self.stopAccessibilityIdentifier)

                    Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureCancelCapture)) {
                        send(.cancel(sessionID: sessionID), status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureCaptureCancellationRequested))
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureCancelCaptureHint))
                    .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
                }
            case .processing:
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureProcessingDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.processingAccessibilityIdentifier)
                if let sessionID = currentSessionID {
                    Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureCancelProcessing)) {
                        send(.cancel(sessionID: sessionID), status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureProcessingCancellationRequested))
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
                }
            case .review:
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureProposalReady))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.processingAccessibilityIdentifier)
                if let proposalID = model.proposalID {
                    Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDiscardSuggestions)) {
                        send(.rejectProposal(proposalID: proposalID), status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureDiscardRequested))
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDiscardHint))
                    .accessibilityIdentifier(Self.rejectProposalAccessibilityIdentifier)
                }
            default:
                Text(captureStateDetail)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let context = model.captureContext {
                    Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureSpeakDetails)) {
                        send(.start(context: context), status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureStartRequested))
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .disabled(!canStartCapture)
                    .keyboardShortcut("s", modifiers: [.command])
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureStartHint))
                    .accessibilityIdentifier(Self.speakDetailsAccessibilityIdentifier)
                } else {
                    Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureStartUnavailable))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.speakDetailsAccessibilityIdentifier)
                }
            }
            if let scratchDisposition = model.scratchDisposition {
                valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchDisposition), value: scratchDispositionText(scratchDisposition))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var captureIndicator: some View {
        Label(BundledLocalizationCatalogV1.v30Text(.voiceCaptureActive), systemImage: "mic.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.attentionText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityValue(BundledLocalizationCatalogV1.v30Text(.voiceCaptureActiveAccessibilityValue))
    }

    private var countdown: some View {
        let elapsed = min(model.elapsedSeconds, Self.maximumCaptureSeconds)
        let remaining = Self.maximumCaptureSeconds - elapsed
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30VoiceCaptureTime(elapsed: elapsed, maximum: Self.maximumCaptureSeconds, remaining: remaining))
                .font(.body.weight(.semibold))
                .foregroundStyle(remaining == 0 ? DesignTokens.Colors.attentionText : DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(elapsed), total: Double(Self.maximumCaptureSeconds))
                .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.voiceCaptureTimeLimit))
                .accessibilityValue(remaining == 0 ? BundledLocalizationCatalogV1.v30Text(.voiceCaptureTimeLimitReached) : BundledLocalizationCatalogV1.v30VoiceCaptureSecondsRemaining(seconds: remaining))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.countdownAccessibilityIdentifier)
    }

    private var transcript: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureTranscriptHeading), identifier: Self.transcriptAccessibilityIdentifier)
            if let transcript = model.transcript {
                Text(transcript)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.voiceCaptureTranscriptLabel))
                    .accessibilityValue(transcript)
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureTranscriptDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let proposal = model.proposal, !proposal.unmatchedClauses.isEmpty {
                    Text(BundledLocalizationCatalogV1.v30VoiceCaptureUnmatchedSegments(count: proposal.unmatchedClauses.count))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.attentionText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureNoTranscript))
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
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureFieldsHeading), identifier: Self.fieldsAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureFieldsDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            let fields = model.presentedFields
            if fields.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureNoFields))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    fieldCard(field, position: index + 1)
                }
                if let proposalID = model.proposalID {
                    Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureFinishReview)) {
                        send(.finalizeReview(proposalID: proposalID), status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureReviewClosureRequested))
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .disabled(!model.hasReviewedAllFields || !canReviewFields)
                    .accessibilityHint(model.hasReviewedAllFields ? BundledLocalizationCatalogV1.v30Text(.voiceCaptureFinishReviewHint) : BundledLocalizationCatalogV1.v30Text(.voiceCaptureFinishReviewUnavailableHint))
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
        let fieldLabel = BundledLocalizationCatalogV1.v30VoiceCaptureField(position: position, label: presentation.displayLabel)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(fieldLabel)
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureFieldID), value: presentation.field.fieldID)
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureResolution), value: resolutionText(presentation.field.resolution))
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureProposedValue), value: fieldValueText(presentation.field.proposedValue, kind: presentation.field.kind))
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureSourceSpan), value: sourceSpanText(presentation.field.sourceSpan))
            valueRow(BundledLocalizationCatalogV1.v30Text(.voiceCaptureSourceText), value: sourceText(for: presentation.field))
            Text(confidenceText(presentation.confidenceSpan))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30VoiceCaptureReviewState(state: reviewStateText(presentation.reviewState)))
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
                    BundledLocalizationCatalogV1.v30VoiceCaptureEditValue(label: presentation.displayLabel),
                    text: editedValueBinding(for: presentation)
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 6)
                .focused($focusedField, equals: .edit(presentation.id))
                .accessibilityLabel(BundledLocalizationCatalogV1.v30VoiceCaptureEditField(label: fieldLabel))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureEditFieldHint))
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).edit-field")

                Button(BundledLocalizationCatalogV1.v30VoiceCaptureApplyEdit(label: fieldLabel)) {
                    submitEdit(presentation)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(!canReviewFields)
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).apply-edit")

                Button(BundledLocalizationCatalogV1.v30VoiceCaptureCancelEdit(label: fieldLabel)) {
                    editingFieldID = nil
                    focusedField = nil
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).cancel-edit")
            } else {
                Button(BundledLocalizationCatalogV1.v30VoiceCaptureAcceptField(label: fieldLabel)) {
                    submitAccept(presentation)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canReviewFields || !acceptIsAvailable(presentation.field))
                .accessibilityHint(acceptIsAvailable(presentation.field) ? BundledLocalizationCatalogV1.v30Text(.voiceCaptureAcceptHint) : BundledLocalizationCatalogV1.v30Text(.voiceCaptureAcceptUnavailableHint))
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).accept")

                Button(BundledLocalizationCatalogV1.v30VoiceCaptureEditField(label: fieldLabel)) {
                    beginEdit(presentation)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canReviewFields)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureEditHint))
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).edit")

                Button(BundledLocalizationCatalogV1.v30VoiceCaptureRejectField(label: fieldLabel)) {
                    submitReject(presentation)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(!canReviewFields)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureRejectHint))
                .accessibilityIdentifier("\(Self.fieldReviewAccessibilityIdentifierPrefix)\(baseID).reject")
            }
        }
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(Self.fieldAccessibilityIdentifierPrefix)\(baseID)")
    }

    private var manualFallback: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureManualEntryHeading), identifier: Self.manualFallbackAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureManualEntryDescription))
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
                .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.voiceCaptureManualDraftLabel))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureManualDraftHint))
                .accessibilityIdentifier(Self.manualEntryFieldAccessibilityIdentifier)
            Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureContinueManual)) {
                submitManualEntry()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!model.draft.canEdit)
            .keyboardShortcut("m", modifiers: [.command])
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureContinueManualHint))
            .accessibilityIdentifier("\(Self.manualFallbackAccessibilityIdentifier).continue")
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recovery: some View {
        if stateRequiresRecovery || model.draft.state != .current {
            WorklightCard {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryHeading), identifier: Self.recoveryAccessibilityIdentifier)
                Text(recoveryText)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if canRetryCapture {
                    Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureRetry)) {
                        send(.retry, status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureRetryRequested))
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureRetryHint))
                    .accessibilityIdentifier("\(Self.recoveryAccessibilityIdentifier).retry")
                }
                Button(BundledLocalizationCatalogV1.v30Text(.voiceCaptureReturnManualFocus)) {
                    focusedField = .manual
                    moveAccessibilityFocus(to: .manual)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.voiceCaptureReturnManualFocusHint))
                .accessibilityIdentifier("\(Self.recoveryAccessibilityIdentifier).manual")
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var errorSummary: some View {
        if let displayedErrorMessage {
            WorklightCard {
                Label(BundledLocalizationCatalogV1.v30Text(.voiceCaptureNeedsAttention), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(displayedErrorMessage)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .error)
                Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureNeedsAttentionDescription))
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
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureOperationStatusHeading), identifier: "\(Self.statusAccessibilityIdentifier).heading")
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
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.voiceCaptureBoundariesHeading), identifier: Self.boundariesAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureAccessibilityDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureDynamicTypeDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCapturePrivacyBoundary))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.voiceCaptureContainmentBoundary))
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
            presentError(BundledLocalizationCatalogV1.v30Text(.voiceCaptureNotExactProposal))
            return
        }
        send(
            .acceptField(proposalID: proposalID, review: review),
            status: BundledLocalizationCatalogV1.v30VoiceCaptureAcceptRequested(label: presentation.displayLabel)
        )
    }

    private func submitEdit(_ presentation: VoicePushToTalkFieldPresentationV1) {
        guard let proposalID = model.proposalID else {
            presentError(BundledLocalizationCatalogV1.v30Text(.voiceCaptureNoProposal))
            return
        }
        let value = editedValues[presentation.id, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            presentError(BundledLocalizationCatalogV1.v30Text(.voiceCaptureEnterEditValue), focus: .edit(presentation.id))
            return
        }
        guard value.utf8.count <= VoiceStructuringLimitsV1.maximumTextUTF8Bytes else {
            presentError(BundledLocalizationCatalogV1.v30Text(.voiceCaptureEditValueTooLong), focus: .edit(presentation.id))
            return
        }
        send(
            .editField(
                proposalID: proposalID,
                fieldID: presentation.field.fieldID,
                fieldKind: presentation.field.kind,
                valueText: value
            ),
            status: BundledLocalizationCatalogV1.v30VoiceCaptureEditRequested(label: presentation.displayLabel)
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
            presentError(BundledLocalizationCatalogV1.v30Text(.voiceCaptureRejectUnavailable))
            return
        }
        send(
            .rejectField(proposalID: proposalID, review: review),
            status: BundledLocalizationCatalogV1.v30VoiceCaptureRejectRequested(label: presentation.displayLabel)
        )
    }

    private func submitManualEntry() {
        localErrorMessage = nil
        let text = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            presentError(BundledLocalizationCatalogV1.v30Text(.voiceCaptureEnterManualValue), focus: .manual)
            return
        }
        guard text.utf8.count <= VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes else {
            presentError(BundledLocalizationCatalogV1.v30Text(.voiceCaptureManualValueTooLong), focus: .manual)
            return
        }
        send(
            .manualEntry(text: text),
            status: BundledLocalizationCatalogV1.v30Text(.voiceCaptureManualRequested)
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
        guard let transcript = model.transcript else { return BundledLocalizationCatalogV1.v30Text(.voiceCaptureSourceTextUnavailable) }
        let bytes = Array(transcript.utf8)
        let start = field.sourceSpan.start
        let end = field.sourceSpan.end
        guard start >= 0, end > start, end <= bytes.count else {
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureSourceSpanUnavailable)
        }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func sourceSpanText(_ span: VoiceTranscriptUTF8SpanV1) -> String {
        BundledLocalizationCatalogV1.v30VoiceCaptureSourceSpan(start: span.start, end: span.end, repeatedStart: span.start, length: span.length)
    }

    private func fieldValueText(
        _ value: VoiceStructuredFieldValueV1?,
        kind: VoiceStructuredFieldKindV1
    ) -> String {
        guard let value else {
            switch kind {
            case .materialDescriptionAndQuantity:
                return BundledLocalizationCatalogV1.v30Text(.voiceCaptureNoStructuredQuantity)
            default:
                return BundledLocalizationCatalogV1.v30Text(.voiceCaptureNoValue)
            }
        }
        switch value {
        case .text(let text):
            return text
        case .allowedEnum(let word):
            return word
        case .exactNumber(let decimal):
            return BundledLocalizationCatalogV1.v30VoiceCaptureDecimalValue(value: decimalText(decimal.mantissa, scale: decimal.scale), unit: decimal.unit.rawValue.lowercased())
        case .durationSeconds(let seconds):
            return BundledLocalizationCatalogV1.v30VoiceCaptureSeconds(seconds: seconds)
        case .material(let material):
            if let quantity = material.quantity {
                return BundledLocalizationCatalogV1.v30VoiceCaptureMaterialQuantity(value: decimalText(quantity.mantissa, scale: quantity.scale), unit: quantity.unit.rawValue.lowercased(), material: material.description)
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
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureConfidenceUnavailable)
        }
        let percent = Int((span.confidence * 100).rounded())
        return BundledLocalizationCatalogV1.v30VoiceCaptureConfidence(percent: percent)
    }

    private func resolutionText(_ resolution: VoiceStructuringResolutionV1) -> String {
        switch resolution {
        case .exact:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureResolutionExactMatch)
        case .ambiguous:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureResolutionAmbiguous)
        case .unsupported:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureResolutionUnsupported)
        }
    }

    private func reviewStateText(_ state: VoicePushToTalkFieldReviewStateV1) -> String {
        switch state {
        case .pending:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReviewPending)
        case .accepted:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReviewAcceptedRequested)
        case .edited:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReviewEditedRequested)
        case .rejected:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReviewRejectedRequested)
        case .needsManualReview:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReviewManualRequired)
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
        case .ready: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateReady)
        case .capturing: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateCapturing)
        case .processing: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateProcessing)
        case .review: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateReview)
        case .manualFallback: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateManualFallback)
        case .permissionDenied: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStatePermissionDenied)
        case .permissionRevoked: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStatePermissionRevoked)
        case .unsupported: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateUnsupported)
        case .offline: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateOffline)
        case .interrupted: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateInterrupted)
        case .backgrounded: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateBackgrounded)
        case .cancelled: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateCancelled)
        case .staleTarget: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateStaleTarget)
        case .protectedDataUnavailable: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateProtectedDataUnavailable)
        case .storageUnavailable: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateStorageUnavailable)
        case .failed: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureStateFailed)
        }
    }

    private var captureStateDetail: String {
        switch model.state {
        case .ready:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureFallbackReady)
        case .manualFallback:
            return fallbackDetail
        case .permissionDenied, .permissionRevoked:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureFallbackPermission)
        case .unsupported:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureFallbackUnsupported)
        case .offline:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureFallbackOffline)
        case .interrupted, .backgrounded, .cancelled, .staleTarget, .protectedDataUnavailable,
             .storageUnavailable, .failed:
            return recoveryText
        case .capturing, .processing, .review:
            return ""
        }
    }

    private var fallbackDetail: String {
        guard let fallbackReason = model.fallbackReason else {
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureFallbackManual)
        }
        return BundledLocalizationCatalogV1.v30VoiceCaptureFallback(reason: fallbackReasonText(fallbackReason))
    }

    private var recoveryText: String {
        switch model.state {
        case .staleTarget:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryStale)
        case .protectedDataUnavailable:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryProtectedData)
        case .storageUnavailable:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryStorage)
        case .interrupted:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryInterrupted)
        case .backgrounded:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryBackgrounded)
        case .cancelled:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryCancelled)
        case .failed:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryFailed)
        case .manualFallback, .permissionDenied, .permissionRevoked, .unsupported, .offline:
            return fallbackDetail
        case .ready, .capturing, .processing, .review:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureRecoveryDefault)
        }
    }

    private func fallbackReasonText(_ reason: VoiceCaptureManualFallbackReasonV1) -> String {
        switch reason {
        case .typeManually: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonManual)
        case .permissionDenied: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonPermissionDenied)
        case .permissionRevoked: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonPermissionRevoked)
        case .permissionRestricted: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonPermissionRestricted)
        case .permissionNotDetermined: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonPermissionNotDetermined)
        case .unsupportedLocale: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonUnsupportedLocale)
        case .unsupportedDevice: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonUnsupportedDevice)
        case .protectedDataUnavailable: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonProtectedDataUnavailable)
        case .backgrounded: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonBackgrounded)
        case .interrupted: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonInterrupted)
        case .cancelled: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonCancelled)
        case .unavailable: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureReasonUnavailable)
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
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureOperationReceipt)
        case .failed, .stale:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureOperationFailure)
        case .cancelled:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureOperationCancelled)
        case .requesting, .awaitingReceipt:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureOperationPending)
        case .idle:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureOperationNoResult)
        }
    }

    private func draftStateText(_ state: VoicePushToTalkDraftStateV1) -> String {
        switch state {
        case .current: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftCurrent)
        case .interrupted: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftInterrupted)
        case .protectedDataUnavailable: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftProtectedData)
        case .storageUnavailable: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftStorage)
        case .stale: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftStale)
        case .unavailable: return BundledLocalizationCatalogV1.v30Text(.voiceCaptureDraftUnavailable)
        }
    }

    private func scratchDispositionText(_ disposition: VoiceScratchDispositionV1) -> String {
        switch disposition {
        case .captureAudioDiscarded:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchDiscarded)
        case .cancelled:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchCancelled)
        case .backgrounded:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchBackgrounded)
        case .interrupted:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchInterrupted)
        case .permissionRevoked:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchPermissionRevoked)
        case .unavailable:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchUnavailable)
        case .stale:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchStale)
        case .failed:
            return BundledLocalizationCatalogV1.v30Text(.voiceCaptureScratchFailed)
        }
    }
}

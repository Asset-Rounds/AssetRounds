import SwiftUI

struct ReportCorrectionView: View {
    static let screenAccessibilityIdentifier = "s4.5.correction.screen"
    static let headerAccessibilityIdentifier = "s4.5.correction.header"
    static let noteAccessibilityIdentifier = "s4.5.correction.note"
    static let countAccessibilityIdentifier = "s4.5.correction.count"
    static let validationAccessibilityIdentifier = "s4.5.correction.validation"
    static let saveAccessibilityIdentifier = "s4.5.correction.save"
    static let savingAccessibilityIdentifier = "s4.5.correction.saving"
    static let failureAccessibilityIdentifier = "s4.5.correction.failure"
    static let readyAccessibilityIdentifier = "s4.5.correction.ready"
    static let priorReportAccessibilityIdentifier = "s4.5.correction.prior-report"
    static let currentReportAccessibilityIdentifier = "s4.5.correction.current-report"

    private enum FocusTarget: Hashable {
        case header
        case note
        case validation
        case saving
        case failure
        case ready
    }

    private enum SubmissionState: Equatable {
        case editing
        case saving
        case failed
        case ready(currentReportID: UUID, priorReportID: UUID?)
        case deliveryFailed(reportID: UUID, priorReportID: UUID)
    }

    let source: ReportCorrectionSourceValue
    let coordinator: ReportDeliveryCoordinator
    let didProduceReady: (ReportDeliveryChainValue) -> Void
    let didSelectReport: (UUID) -> Void
    let didPersistDeliveryFailure: (UUID, ReportDeliveryValue) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var validationMessage: String?
    @State private var state: SubmissionState = .editing
    @State private var didAcknowledgeDeliveryFailure = false
    @FocusState private var keyboardFocus: FocusTarget?
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    init(
        source: ReportCorrectionSourceValue,
        coordinator: ReportDeliveryCoordinator,
        didProduceReady: @escaping (ReportDeliveryChainValue) -> Void,
        didSelectReport: @escaping (UUID) -> Void,
        didPersistDeliveryFailure: @escaping (UUID, ReportDeliveryValue) -> Void
    ) {
        self.source = source
        self.coordinator = coordinator
        self.didProduceReady = didProduceReady
        self.didSelectReport = didSelectReport
        self.didPersistDeliveryFailure = didPersistDeliveryFailure
        _note = SwiftUI.State(initialValue: source.currentNote ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                AssetRoundsEvidenceCard {
                    AssetRoundsReportBrandHeader(title: Text("Correct report"))
                        .accessibilityFocused($accessibilityFocus, equals: .header)
                        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)

                    Text("Change the note only. Evidence, outcome, time, and report history stay unchanged.")
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsForm {
                    AssetRoundsEvidenceCard {
                        Text("Correction note")
                            .font(DesignTokens.Typography.fieldLabel)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                            .accessibilityHidden(true)

                        TextField("Correction note", text: $note, axis: .vertical)
                            .lineLimit(4...8)
                            .padding(.horizontal, DesignTokens.Spacing.space8)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: DesignTokens.Target.minimumInteractiveHeight,
                                alignment: .topLeading
                            )
                            .background(DesignTokens.SemanticColors.elevatedSurface)
                            .clipShape(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                                    .stroke(
                                        DesignTokens.SemanticColors.separator,
                                        lineWidth: DesignTokens.Stroke.standard
                                    )
                            }
                            .textInputAutocapitalization(.sentences)
                            .focused($keyboardFocus, equals: .note)
                            .accessibilityFocused($accessibilityFocus, equals: .note)
                            .accessibilityLabel("Correction note")
                            .accessibilityHint("Enter a different note, up to 1,000 characters. Leave it blank to remove the current note.")
                            .accessibilityIdentifier(Self.noteAccessibilityIdentifier)
                            .onChange(of: note) { _, _ in
                                validationMessage = nil
                                if state == .failed { state = .editing }
                            }

                        Text("\(normalizedCharacterCount) of 1,000 characters")
                            .font(DesignTokens.Typography.supportingCaption)
                            .foregroundStyle(
                                normalizedCharacterCount > 1_000
                                    ? DesignTokens.SemanticColors.error
                                    : DesignTokens.SemanticColors.primaryText
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(Self.countAccessibilityIdentifier)
                    }
                }

                if let validationMessage {
                    AssetRoundsStateLabel(
                        kind: .error,
                        text: Text(validationMessage)
                    )
                        .accessibilityLabel(Text("Blocked: \(validationMessage)"))
                        .accessibilityValue(Text(verbatim: String()))
                        .accessibilityFocused($accessibilityFocus, equals: .validation)
                        .accessibilityIdentifier(Self.validationAccessibilityIdentifier)
                }

                stateContent

                if showsForm {
                    Button("Save correction", action: save)
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.SemanticColors.primaryAction)
                        .controlSize(.large)
                        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                        .disabled(state == .saving)
                        .accessibilityHint("Creates a new report revision and keeps the prior report.")
                        .accessibilityIdentifier(Self.saveAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .navigationTitle("Correct report")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hidesBackNavigation)
        .background(DesignTokens.SemanticColors.workBackground)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear {
            moveAccessibilityFocus(to: .header)
        }
        .onDisappear {
            acknowledgeDeliveryFailureIfNeeded()
        }
    }

    private var showsForm: Bool {
        switch state {
        case .editing, .saving, .failed: true
        case .ready, .deliveryFailed: false
        }
    }

    private var hidesBackNavigation: Bool {
        switch state {
        case .saving, .ready, .deliveryFailed: true
        case .editing, .failed: false
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .editing:
            EmptyView()
        case .saving:
            AssetRoundsEvidenceCard {
                ProgressView("Saving correction")
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Target.minimumInteractiveHeight)
                    .accessibilityFocused($accessibilityFocus, equals: .saving)
                    .accessibilityIdentifier(Self.savingAccessibilityIdentifier)
            }
        case .failed:
            AssetRoundsStateLabel(
                kind: .error,
                text: Text("Correction couldn’t be saved. Nothing changed.")
            )
            .accessibilityLabel("Blocked: Correction couldn’t be saved. Nothing changed.")
            .accessibilityValue(Text(verbatim: String()))
            .accessibilityFocused($accessibilityFocus, equals: .failure)
            .accessibilityIdentifier(Self.failureAccessibilityIdentifier)
        case .ready(let currentReportID, let priorReportID):
            readyContent(
                currentReportID: currentReportID,
                priorReportID: priorReportID
            )
        case .deliveryFailed(let reportID, let priorReportID):
            AssetRoundsEvidenceCard {
                AssetRoundsStateLabel(
                    kind: .warning,
                    text: Text("Correction saved, but its PDF couldn’t be created. Retry from the saved report.")
                )
                .accessibilityLabel("Attention: Correction saved, but its PDF couldn’t be created. Retry from the saved report.")
                .accessibilityValue(Text(verbatim: String()))
                .accessibilityFocused($accessibilityFocus, equals: .failure)
                .accessibilityIdentifier(Self.failureAccessibilityIdentifier)

                Button("View prior report") {
                    acknowledgeDeliveryFailureIfNeeded(reportID: reportID)
                    didSelectReport(priorReportID)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(DesignTokens.SemanticColors.primaryAction)
                .controlSize(.large)
                .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                .accessibilityHint("Opens the immediately prior saved report.")
                .accessibilityIdentifier(Self.priorReportAccessibilityIdentifier)
            }
        }
    }

    private func readyContent(
        currentReportID: UUID,
        priorReportID: UUID?
    ) -> some View {
        AssetRoundsEvidenceCard {
            AssetRoundsStateLabel(
                kind: .completed,
                text: Text("Correction saved")
            )
            .accessibilityLabel("Complete: Correction saved")
            .accessibilityValue(Text(verbatim: String()))

            Text("The prior report and evidence remain unchanged.")
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($accessibilityFocus, equals: .ready)
                .accessibilityIdentifier(Self.readyAccessibilityIdentifier)

            if let priorReportID {
                Button("View prior report") {
                    didSelectReport(priorReportID)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(DesignTokens.SemanticColors.primaryAction)
                .controlSize(.large)
                .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                .accessibilityHint("Opens the immediately prior saved report.")
                .accessibilityIdentifier(Self.priorReportAccessibilityIdentifier)
            }

            Button("View corrected report") {
                didSelectReport(currentReportID)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.SemanticColors.primaryAction)
            .controlSize(.large)
            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
            .accessibilityHint("Opens the current corrected report.")
            .accessibilityIdentifier(Self.currentReportAccessibilityIdentifier)
        }
    }

    private func save() {
        guard state != .saving else { return }
        let submittedNote = normalizedNote
        guard normalizedCharacterCount <= 1_000 else {
            showValidation("Correction note must be 1,000 characters or fewer.")
            return
        }
        guard submittedNote != source.currentNote else {
            showValidation("Change the note before saving.")
            return
        }

        validationMessage = nil
        keyboardFocus = nil
        state = .saving
        moveAccessibilityFocus(to: .saving)
        Task { @MainActor in
            let minimumSavingPresentation = Task<Void, Never> {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            do {
                let result = try await coordinator.submitCorrection(
                    from: source,
                    note: submittedNote
                )
                await minimumSavingPresentation.value
                switch result {
                case .ready(let chain):
                    didProduceReady(chain)
                    state = .ready(
                        currentReportID: chain.current.reportID,
                        priorReportID: chain.ancestors.first?.reportID
                    )
                    moveAccessibilityFocus(to: .ready)
                case .pdfUnavailable(let reportID, let prior):
                    didPersistDeliveryFailure(reportID, prior)
                    state = .deliveryFailed(
                        reportID: reportID,
                        priorReportID: prior.reportID
                    )
                    moveAccessibilityFocus(to: .failure)
                }
            } catch {
                await minimumSavingPresentation.value
                state = .failed
                moveAccessibilityFocus(to: .failure)
            }
        }
    }

    private var normalizedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedCharacterCount: Int {
        normalizedNote?.count ?? 0
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        state = .editing
        Task { @MainActor in
            await Task.yield()
            keyboardFocus = .note
            accessibilityFocus = nil
            await Task.yield()
            accessibilityFocus = .validation
        }
    }

    private func moveAccessibilityFocus(to target: FocusTarget) {
        accessibilityFocus = nil
        Task { @MainActor in
            await Task.yield()
            accessibilityFocus = target
        }
    }

    private func acknowledgeDeliveryFailureIfNeeded(reportID: UUID? = nil) {
        guard !didAcknowledgeDeliveryFailure else { return }
        let persistedReportID: UUID?
        if let reportID {
            persistedReportID = reportID
        } else if case .deliveryFailed(let reportID, _) = state {
            persistedReportID = reportID
        } else {
            persistedReportID = nil
        }
        guard let persistedReportID else { return }
        didAcknowledgeDeliveryFailure = true
        try? coordinator.acknowledgePersistedPDFUnavailable(
            reportID: persistedReportID
        )
    }
}

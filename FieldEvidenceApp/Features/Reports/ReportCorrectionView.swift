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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    Text(BundledLocalizationCatalogV1.v30Text(.reportCorrectionHeading))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($accessibilityFocus, equals: .header)
                        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)

                    Text(BundledLocalizationCatalogV1.v30Text(.reportCorrectionDisclosure))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsForm {
                    WorklightCard {
                        Text(BundledLocalizationCatalogV1.v30Text(.reportCorrectionNoteLabel))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .accessibilityHidden(true)

                        TextField(BundledLocalizationCatalogV1.v30Text(.reportCorrectionNotePlaceholder), text: $note, axis: .vertical)
                            .lineLimit(4...8)
                            .padding(.horizontal, DesignTokens.Spacing.small)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: DesignTokens.Control.minimumHitSize,
                                alignment: .topLeading
                            )
                            .background(DesignTokens.Colors.surface)
                            .clipShape(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                                    .stroke(
                                        DesignTokens.Colors.essentialControlStroke,
                                        lineWidth: 1
                                    )
                            }
                            .textInputAutocapitalization(.sentences)
                            .focused($keyboardFocus, equals: .note)
                            .accessibilityFocused($accessibilityFocus, equals: .note)
                            .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.reportCorrectionNoteAccessibilityLabel))
                            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportCorrectionNoteAccessibilityHint))
                            .accessibilityIdentifier(Self.noteAccessibilityIdentifier)
                            .onChange(of: note) { _, _ in
                                validationMessage = nil
                                if state == .failed { state = .editing }
                            }

                        Text(BundledLocalizationCatalogV1.v30ReportCorrectionCharacterCount(count: normalizedCharacterCount))
                            .font(.caption)
                            .foregroundStyle(
                                normalizedCharacterCount > 1_000
                                    ? DesignTokens.Colors.blockedText
                                    : DesignTokens.Colors.secondaryText
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(Self.countAccessibilityIdentifier)
                    }
                }

                if let validationMessage {
                    WorklightStatusBadge(kind: .blocked, text: validationMessage)
                        .accessibilityFocused($accessibilityFocus, equals: .validation)
                        .accessibilityIdentifier(Self.validationAccessibilityIdentifier)
                }

                stateContent

                if showsForm {
                    Button(BundledLocalizationCatalogV1.v30Text(.reportCorrectionSaveAction), action: save)
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(state == .saving)
                        .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportCorrectionSaveAccessibilityHint))
                        .accessibilityIdentifier(Self.saveAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.reportCorrectionNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hidesBackNavigation)
        .background(DesignTokens.Colors.canvas)
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
            WorklightCard {
                ProgressView(BundledLocalizationCatalogV1.v30Text(.reportCorrectionSavingProgress))
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityFocused($accessibilityFocus, equals: .saving)
                    .accessibilityIdentifier(Self.savingAccessibilityIdentifier)
            }
        case .failed:
            WorklightStatusBadge(
                kind: .blocked,
                text: BundledLocalizationCatalogV1.v30Text(.reportCorrectionSaveFailedError)
            )
            .accessibilityFocused($accessibilityFocus, equals: .failure)
            .accessibilityIdentifier(Self.failureAccessibilityIdentifier)
        case .ready(let currentReportID, let priorReportID):
            readyContent(
                currentReportID: currentReportID,
                priorReportID: priorReportID
            )
        case .deliveryFailed(let reportID, let priorReportID):
            WorklightCard {
                WorklightStatusBadge(
                    kind: .attention,
                    text: BundledLocalizationCatalogV1.v30Text(.reportCorrectionPDFUnavailableError)
                )
                .accessibilityFocused($accessibilityFocus, equals: .failure)
                .accessibilityIdentifier(Self.failureAccessibilityIdentifier)

                Button(BundledLocalizationCatalogV1.v30Text(.reportCorrectionViewPriorReportAction)) {
                    acknowledgeDeliveryFailureIfNeeded(reportID: reportID)
                    didSelectReport(priorReportID)
                    dismiss()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportCorrectionViewPriorReportAccessibilityHint))
                .accessibilityIdentifier(Self.priorReportAccessibilityIdentifier)
            }
        }
    }

    private func readyContent(
        currentReportID: UUID,
        priorReportID: UUID?
    ) -> some View {
        WorklightCard {
            WorklightStatusBadge(kind: .complete, text: BundledLocalizationCatalogV1.v30Text(.reportCorrectionSavedBadge))

            Text(BundledLocalizationCatalogV1.v30Text(.reportCorrectionPriorReportPreservedMessage))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($accessibilityFocus, equals: .ready)
                .accessibilityIdentifier(Self.readyAccessibilityIdentifier)

            if let priorReportID {
                Button(BundledLocalizationCatalogV1.v30Text(.reportCorrectionViewPriorReportAction)) {
                    didSelectReport(priorReportID)
                    dismiss()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportCorrectionViewPriorReportAccessibilityHint))
                .accessibilityIdentifier(Self.priorReportAccessibilityIdentifier)
            }

            Button(BundledLocalizationCatalogV1.v30Text(.reportCorrectionViewCorrectedReportAction)) {
                didSelectReport(currentReportID)
                dismiss()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportCorrectionViewCorrectedReportAccessibilityHint))
            .accessibilityIdentifier(Self.currentReportAccessibilityIdentifier)
        }
    }

    private func save() {
        guard state != .saving else { return }
        let submittedNote = normalizedNote
        guard normalizedCharacterCount <= 1_000 else {
            showValidation(BundledLocalizationCatalogV1.v30Text(.reportCorrectionNoteLengthValidation))
            return
        }
        guard submittedNote != source.currentNote else {
            showValidation(BundledLocalizationCatalogV1.v30Text(.reportCorrectionNoteUnchangedValidation))
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

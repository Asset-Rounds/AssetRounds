import SwiftUI

/// A foreground-only C31 handoff surface. The view owns presentation state
/// only; the injected session owns source validation, the single system call,
/// and the copy-fallback boundary. It is intentionally not wired into the
/// application shell while the S10 surface reservation is active.
@MainActor
struct OperationalContactHandoffView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c31.handoff.screen"
    static let subjectAccessibilityIdentifier = "v23.p04.c31.handoff.subject"
    static let channelChooserAccessibilityIdentifier =
        "v23.p04.c31.handoff.channel-chooser"
    static let actionAccessibilityIdentifierPrefix =
        "v23.p04.c31.handoff.action."
    static let selectedActionAccessibilityIdentifier =
        "v23.p04.c31.handoff.selected-action"
    static let confirmationAccessibilityIdentifier =
        "v23.p04.c31.handoff.confirmation"
    static let statusAccessibilityIdentifier = "v23.p04.c31.handoff.status"
    static let unavailableAccessibilityIdentifier =
        "v23.p04.c31.handoff.unavailable"
    static let copyFallbackAccessibilityIdentifier =
        "v23.p04.c31.handoff.copy-fallback"
    static let boundaryAccessibilityIdentifier =
        "v23.p04.c31.handoff.truth-boundary"
    static let cancelAccessibilityIdentifier = "v23.p04.c31.handoff.cancel"

    /// This is deliberately stronger than the result badge: it stays visible
    /// while the chooser is open and prevents an accepted OS presentation from
    /// being mistaken for communication or navigation completion.
    static let truthBoundaryText =
        "Handed off to the system means only that iOS accepted presentation. It does not mean sent, delivered, called, answered, routed, arrived, verified, or consented."

    let session: OperationalContactHandoffSessionV1
    let subject: OperationalContactHandoffSubjectV1
    let restorationToken: OperationalContactHandoffRestorationTokenV1
    let onRestore: @MainActor (
        OperationalContactHandoffRestorationTokenV1
    ) -> Void
    let onDismiss: (@MainActor () -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var preparation: OperationalContactHandoffPreparationV1?
    @State private var selectedActionID: UUID?
    @State private var execution: OperationalContactHandoffExecutionV1?
    @State private var statusText: String?
    @State private var copyText: String?
    @State private var isPreparing = true
    @State private var isPerforming = false
    @State private var isConfirming = false
    @State private var didFinish = false
    @State private var handoffTask: Task<Void, Never>?
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum FocusTarget: Hashable {
        case title
        case status
    }

    private enum FinishDisposition {
        case cancelled
        case dismissed
    }

    init(
        session: OperationalContactHandoffSessionV1,
        subject: OperationalContactHandoffSubjectV1,
        restorationToken: OperationalContactHandoffRestorationTokenV1,
        onRestore: @escaping @MainActor (
            OperationalContactHandoffRestorationTokenV1
        ) -> Void = { _ in },
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.session = session
        self.subject = subject
        self.restorationToken = restorationToken
        self.onRestore = onRestore
        self.onDismiss = onDismiss
    }

    /// Label-compatible spelling for callers that describe the callback as a
    /// restoration hook. Both initializers carry the same opaque token.
    init(
        session: OperationalContactHandoffSessionV1,
        subject: OperationalContactHandoffSubjectV1,
        restorationToken: OperationalContactHandoffRestorationTokenV1,
        onRestoration: @escaping @MainActor (
            OperationalContactHandoffRestorationTokenV1
        ) -> Void,
        onDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.init(
            session: session,
            subject: subject,
            restorationToken: restorationToken,
            onRestore: onRestoration,
            onDismiss: onDismiss
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                truthBoundary
                content
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Operational handoff")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    finish(.cancelled, shouldDismiss: true)
                }
                .disabled(isPerforming)
                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
            }
        }
        .interactiveDismissDisabled(isPerforming)
        .task {
            await preparePresentation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            finish(.cancelled, shouldDismiss: false)
        }
        .onDisappear {
            // Covers an interactive dismissal or a caller-owned sheet close.
            finish(.dismissed, shouldDismiss: false)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            if let selectedAction {
                Button(
                    "Open \(channelLabel(for: selectedAction.kind))"
                ) {
                    handoffTask?.cancel()
                    handoffTask = Task {
                        await perform(selectedActionID: selectedAction.actionID)
                    }
                }
                .accessibilityIdentifier(Self.confirmationAccessibilityIdentifier)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let selectedAction {
                Text(
                    "Review \(channelLabel(for: selectedAction.kind)) for \(selectedAction.displayValue) before opening the system."
                )
            } else {
                Text("Choose a channel before confirming the handoff.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isPreparing {
            loadingContent
        } else if let preparation {
            switch preparation {
            case let .ready(presentation):
                readyContent(presentation)
            case let .unavailable(unavailable):
                unavailableContent(unavailable)
            }
        } else {
            unavailableContent(
                OperationalContactHandoffUnavailablePresentationV1(
                    disposition: .targetInvalid,
                    restorationToken: restorationToken
                )
            )
        }
    }

    private var loadingContent: some View {
        WorklightCard {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Control.minimumHitSize)
                .accessibilityLabel("Loading handoff options")
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).loading")

            Text("Loading the selected Site or Party…")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readyContent(
        _ presentation: OperationalContactHandoffPresentationV1
    ) -> some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            WorklightCard {
                Text(subjectLabel(for: presentation.snapshot.subject))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                Text(presentation.snapshot.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($accessibilityFocus, equals: .title)
                    .accessibilityIdentifier(Self.subjectAccessibilityIdentifier)

                Text(
                    presentation.snapshot.subject.isSite
                        ? "Choose Directions for this Site."
                        : "Choose a contact channel for this Party."
                )
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            WorklightCard {
                Text("Choose a channel")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(
                        Self.channelChooserAccessibilityIdentifier
                    )

                Text(
                    "Select one value, then confirm before opening the system."
                )
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(orderedActions, id: \.actionID) { action in
                    actionRow(action)
                }
            }

            if let selectedAction {
                selectedActionContent(selectedAction)
            }

            if let statusText {
                statusContent(statusText)
            }
        }
    }

    private func unavailableContent(
        _ unavailable: OperationalContactHandoffUnavailablePresentationV1
    ) -> some View {
        WorklightCard {
            Text("Handoff unavailable")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Label(unavailable.truthfulText, systemImage: "exclamationmark.triangle")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($accessibilityFocus, equals: .status)
                .accessibilityIdentifier(Self.unavailableAccessibilityIdentifier)

            Button("Close") {
                finish(.dismissed, shouldDismiss: true)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityIdentifier(
                "\(Self.unavailableAccessibilityIdentifier).close"
            )
        }
    }

    private func actionRow(
        _ action: OperationalContactHandoffActionPresentationV1
    ) -> some View {
        let selected = action.actionID == selectedActionID
        return Button {
            select(actionID: action.actionID)
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                Image(
                    systemName: selected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(
                    selected
                        ? DesignTokens.Colors.interactionAccent
                        : DesignTokens.Colors.secondaryText
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channelLabel(for: action.kind))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)

                    Text(action.displayValue)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if action.preferred {
                        Text("Preferred value")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.small)
            }
            .padding(.horizontal, DesignTokens.Spacing.small)
            .padding(.vertical, DesignTokens.Spacing.small)
            .frame(
                maxWidth: .infinity,
                minHeight: DesignTokens.Control.minimumHitSize,
                alignment: .leading
            )
            .background(
                selected
                    ? DesignTokens.Colors.accentContainer
                    : DesignTokens.Colors.surface
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                    .stroke(DesignTokens.Colors.essentialControlStroke)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(channelLabel(for: action.kind)), \(action.displayValue)"
        )
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Selects this handoff channel")
        .accessibilityIdentifier(
            Self.actionAccessibilityIdentifierPrefix
                + action.actionID.uuidString.lowercased()
        )
    }

    private func selectedActionContent(
        _ action: OperationalContactHandoffActionPresentationV1
    ) -> some View {
        WorklightCard {
            Text("Selected channel")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            Text("\(channelLabel(for: action.kind)): \(action.displayValue)")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.selectedActionAccessibilityIdentifier)

            Button("Review and open system") {
                isConfirming = true
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(isPerforming)
            .accessibilityIdentifier(
                "\(Self.selectedActionAccessibilityIdentifier).confirm"
            )

            if isPerforming {
                ProgressView("Opening system…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statusContent(_ text: String) -> some View {
        WorklightCard {
            Label(text, systemImage: "info.circle")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($accessibilityFocus, equals: .status)
                .accessibilityIdentifier(Self.statusAccessibilityIdentifier)

            if let execution,
               execution.copyFallbackAvailable,
               execution.result.disposition == .systemUnavailable
                   || execution.result.disposition == .systemRejected {
                Button("Copy current value") {
                    copyFallback(for: execution)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(
                    "Copies the valid current value without starting another handoff"
                )
                .accessibilityIdentifier(Self.copyFallbackAccessibilityIdentifier)
            }

            if let copyText {
                Label(copyText, systemImage: "doc.on.clipboard")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "\(Self.copyFallbackAccessibilityIdentifier).status"
                    )
            }
        }
    }

    private var truthBoundary: some View {
        Label(Self.truthBoundaryText, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(Self.boundaryAccessibilityIdentifier)
    }

    private var confirmationTitle: String {
        guard let selectedAction else { return "Confirm system handoff" }
        return "Confirm \(channelLabel(for: selectedAction.kind))"
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var presentation: OperationalContactHandoffPresentationV1? {
        guard case let .ready(value) = preparation else { return nil }
        return value
    }

    private var orderedActions: [OperationalContactHandoffActionPresentationV1] {
        guard let presentation else { return [] }
        return presentation.actions.sorted { lhs, rhs in
            if lhs.kind.rawValue != rhs.kind.rawValue {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            if lhs.preferred != rhs.preferred {
                return lhs.preferred && !rhs.preferred
            }
            if lhs.displayValue != rhs.displayValue {
                return lhs.displayValue < rhs.displayValue
            }
            return lhs.actionID.uuidString < rhs.actionID.uuidString
        }
    }

    private var selectedAction: OperationalContactHandoffActionPresentationV1? {
        guard let selectedActionID else { return nil }
        return orderedActions.first { $0.actionID == selectedActionID }
    }

    private func preparePresentation() async {
        let result = await session.prepare(
            subject: subject,
            restorationToken: restorationToken
        )
        guard !Task.isCancelled, !didFinish else { return }
        preparation = result
        isPreparing = false
        switch result {
        case .ready(_):
            moveAccessibilityFocus(to: .title)
        case let .unavailable(unavailable):
            statusText = unavailable.truthfulText
            moveAccessibilityFocus(to: .status)
        }
    }

    private func select(actionID: UUID) {
        guard !isPerforming else { return }
        let update = {
            selectedActionID = actionID
            execution = nil
            statusText = nil
            copyText = nil
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeInOut(duration: 0.18), update)
        }
    }

    private func perform(selectedActionID actionID: UUID) async {
        guard let presentation, !isPerforming else { return }
        isPerforming = true
        defer {
            isPerforming = false
            handoffTask = nil
        }
        copyText = nil
        do {
            let result = try await session.perform(
                sessionID: presentation.sessionID,
                actionID: actionID
            )
            guard !Task.isCancelled, !didFinish else {
                return
            }
            execution = result
            statusText = result.truthfulText
            moveAccessibilityFocus(to: .status)
        } catch {
            guard !didFinish else { return }
            execution = nil
            statusText =
                "The handoff could not be prepared. No system handoff was started."
            moveAccessibilityFocus(to: .status)
        }
    }

    private func copyFallback(
        for execution: OperationalContactHandoffExecutionV1
    ) {
        guard let presentation,
              execution.copyFallbackAvailable else {
            copyText = "Copy fallback is unavailable for this result."
            return
        }
        switch session.copyFallback(
            sessionID: presentation.sessionID,
            actionID: execution.actionID
        ) {
        case .copied:
            copyText =
                "Copied the current value. No call, message, or directions request was started."
        case .unavailable:
            copyText = "Copy fallback is unavailable for this result."
        }
        moveAccessibilityFocus(to: .status)
    }

    private func finish(
        _ disposition: FinishDisposition,
        shouldDismiss: Bool
    ) {
        guard !didFinish else { return }
        didFinish = true
        handoffTask?.cancel()
        handoffTask = nil
        let restoredToken: OperationalContactHandoffRestorationTokenV1
        if let presentation {
            let token: OperationalContactHandoffRestorationTokenV1?
            switch disposition {
            case .cancelled:
                token = session.cancel(sessionID: presentation.sessionID)
            case .dismissed:
                token = session.dismiss(sessionID: presentation.sessionID)
            }
            restoredToken = token ?? restorationToken
        } else {
            restoredToken = restorationToken
        }
        onRestore(restoredToken)
        onDismiss?()
        if shouldDismiss {
            dismiss()
        }
    }

    private func moveAccessibilityFocus(to target: FocusTarget) {
        Task { @MainActor in
            await Task.yield()
            guard !didFinish else { return }
            accessibilityFocus = target
        }
    }

    private func subjectLabel(
        for subject: OperationalContactHandoffSubjectV1
    ) -> String {
        subject.isSite ? "Selected Site" : "Selected Party"
    }

    private func channelLabel(for kind: SystemHandoffKindV1) -> String {
        switch kind {
        case .directions:
            "Directions"
        case .call:
            "Call"
        case .text:
            "Text"
        case .email:
            "Email"
        }
    }
}

private extension OperationalContactHandoffSubjectV1 {
    var isSite: Bool {
        if case .site = self { return true }
        return false
    }
}

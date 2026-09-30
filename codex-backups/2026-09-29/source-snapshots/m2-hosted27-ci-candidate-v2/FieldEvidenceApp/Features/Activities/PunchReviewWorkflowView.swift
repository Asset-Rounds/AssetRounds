import SwiftUI

/// A standalone, renderer-neutral C34 surface. The caller supplies canonical
/// review context and commands; this view neither creates installation truth
/// nor owns a report renderer, persistence, or navigation route.
@MainActor
struct PunchReviewWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c34.punch-review.screen"
    static let readinessAccessibilityIdentifier = "v23.p04.c34.punch-review.readiness"
    static let scopeAccessibilityIdentifier = "v23.p04.c34.punch-review.scope"
    static let recoveryAccessibilityIdentifier = "v23.p04.c34.punch-review.recovery"
    static let reportAccessibilityIdentifier = "v23.p04.c34.punch-review.report"
    static let statusAccessibilityIdentifier = "v23.p04.c34.punch-review.status"

    let coordinator: PunchReviewWorkflowCoordinatorV1
    let context: PunchReviewWorkflowContextV1
    let commands: [PunchReviewWorkflowCommandV1]
    let onAccepted: (@MainActor (ActivityContractAcceptanceResultV2) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isPerforming = false
    @State private var operationMessage: String?
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum FocusTarget: Hashable {
        case heading
        case errorSummary
        case operationStatus
    }

    init(
        coordinator: PunchReviewWorkflowCoordinatorV1,
        context: PunchReviewWorkflowContextV1,
        commands: [PunchReviewWorkflowCommandV1] = [],
        onAccepted: (@MainActor (ActivityContractAcceptanceResultV2) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.context = context
        self.commands = commands
        self.onAccepted = onAccepted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                if let projection {
                    readiness(projection)
                    preparation(projection)
                    execution(projection)
                    scopeAndRecheck(projection)
                    closeoutAndReport(projection)
                    operatingBoundaries
                } else {
                    invalidContext
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Punch review")
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = projection?.blockers.isEmpty == false ? .errorSummary : .heading
        }
        .onChange(of: operationMessage) { _, _ in
            accessibilityFocus = .operationStatus
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.medium
    }

    private var projection: PunchReviewWorkflowProjectionV1? {
        try? coordinator.projection(for: context)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Punch review workflow")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("Prepare and record the standalone review from its canonical activity record. Installation context is optional and read-only.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var invalidContext: some View {
        WorklightCard {
            Label("Punch review unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text("The current review record could not be validated. No workflow command is available from this screen.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($accessibilityFocus, equals: .errorSummary)
        .accessibilityIdentifier(Self.readinessAccessibilityIdentifier)
    }

    private func readiness(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Readiness", identifier: Self.readinessAccessibilityIdentifier)
            if projection.blockers.isEmpty {
                Label("Recorded readiness has no start blocker.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.informationText)
            } else {
                Text("Resolve every recorded blocker before starting.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .errorSummary)
                ForEach(projection.blockers, id: \.facetID) { blocker in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: blocker.kind.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                        Text(verbatim: blocker.reason)
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(blocker.kind.rawValue) blocker. \(blocker.reason)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func preparation(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Preparation", identifier: "\(Self.screenAccessibilityIdentifier).preparation")
            capabilityRow("Plan", disposition: projection.planDisposition)
            Label(
                projection.installationSnapshotAvailable
                    ? "An optional installation snapshot is available as read-only context."
                    : "No installation snapshot is present; standalone punch review remains available.",
                systemImage: projection.installationSnapshotAvailable ? "doc.text" : "doc.badge.ellipsis"
            )
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            Text("A missing plan or installation snapshot never fabricates evidence and does not create an installation dependency.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func execution(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Review execution", identifier: "\(Self.screenAccessibilityIdentifier).execution")
            stateLabel(projection.envelope.state)
            operationStatus

            switch projection.envelope.state {
            case .ready:
                commandButton(title: "Start punch review", command: command(named: .start), disabled: !projection.canStart)
                if !projection.canStart {
                    Text("Start is unavailable until recorded readiness blockers are resolved.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            case .inProgress:
                Text(nextScopeText(projection))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: "Pause punch review", command: command(named: .pause))
                commandButton(title: "Record interruption", command: interruptionRecoveryCommand)
            case .paused, .changesRequested:
                Text("The review is paused or changes were requested. Resume only with the current record and a supplied resume command.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: "Resume punch review", command: command(named: .resume))
            case .deferred, .unableToComplete, .cancelled:
                Text("This attempt is interrupted. Recover only by replaying the same supplied mutation identity.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                recoveryButton
            default:
                Text("This activity is not currently executable from the punch-review workflow surface.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func scopeAndRecheck(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Decisions, corrections, and rechecks", identifier: Self.scopeAccessibilityIdentifier)
            ForEach(projection.scope, id: \.definition.scopeItemID) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.definition.ordinal + 1). \(item.definition.title)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(decisionText(item.decision))
                        .font(.footnote)
                        .foregroundStyle(item.hasRecordedDecision ? DesignTokens.Colors.informationText : DesignTokens.Colors.secondaryText)
                    Text("\(item.unresolvedFindingCount) unresolved finding(s), \(item.resolvedFindingCount) resolved finding(s).")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(Self.scopeAccessibilityIdentifier).\(item.definition.scopeItemID)")
            }
            Text("\(projection.report.correctiveActionSHA256s.count) corrective action record(s) and \(projection.report.verifiedRecheckSHA256s.count) verified recheck record(s) are projected from canonical records.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("This screen does not resolve, approve, or hide findings. Record a basis variation only through a supplied canonical command.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: "Record basis variation", command: command(named: .recordBasisVariation))
        }
        .accessibilityElement(children: .contain)
    }

    private func closeoutAndReport(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Closeout and report projection", identifier: Self.reportAccessibilityIdentifier)
            Text(projection.canCloseout
                 ? "Every scope decision and required finding state is ready for the next recorded closeout action."
                 : "Closeout remains unavailable until every required scope decision and finding state is recorded.")
                .font(.body)
                .foregroundStyle(projection.canCloseout ? DesignTokens.Colors.informationText : DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: closeoutActionTitle(projection.nextCloseoutAction), command: command(named: .closeout), disabled: !projection.canCloseout)
            Label(
                projection.reportReady
                    ? "Recorded closeout is report-ready for the existing renderer."
                    : "No recorded closeout is report-ready.",
                systemImage: projection.reportReady ? "doc.text" : "doc.badge.ellipsis"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            Text("This view exposes a renderer-neutral projection only. Report-ready does not mean rendered, delivered, accepted, identity-verified, safe, compliant, or approved.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var operatingBoundaries: some View {
        WorklightCard {
            sectionHeading("Local operating boundaries", identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text("Offline: this view presents only the current local record and does not claim a network sync.")
            Text("Permissions: this view does not request camera, location, or other system permission.")
            if reduceMotion {
                Text("Reduce Motion is on. State changes are presented without added animation.")
            }
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var operationStatus: some View {
        if let operationMessage {
            Label(operationMessage, systemImage: "info.circle")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.informationText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($accessibilityFocus, equals: .operationStatus)
                .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
        }
    }

    private var recoveryButton: some View {
        Group {
            if let command = interruptionRecoveryCommand {
                Button("Retry recorded recovery") { perform(command, recovery: true) }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .disabled(isPerforming)
                    .accessibilityHint("Replays the same supplied mutation identity and returns its existing receipt or one accepted effect.")
                    .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
            } else {
                Text("No recovery command is supplied. Reopen from the canonical record; unrecorded scratch work is unavailable.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
            }
        }
    }

    @ViewBuilder
    private func commandButton(title: String, command: PunchReviewWorkflowCommandV1?, disabled: Bool = false) -> some View {
        if let command {
            Button(title) { perform(command) }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(disabled || isPerforming)
                .accessibilityHint("Uses the supplied canonical punch-review command.")
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text("\(title) is unavailable until its canonical command is supplied.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
    }

    private func sectionHeading(_ title: LocalizedStringKey, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func stateLabel(_ state: ActivityStateV2) -> some View {
        Label(state.rawValue.replacingOccurrences(of: "_", with: " "), systemImage: "circle.inset.filled")
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityElement(children: .combine)
    }

    private func capabilityRow(_ label: String, disposition: PunchReviewPlanDispositionV1) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.body.weight(.semibold))
            Spacer(minLength: DesignTokens.Spacing.small)
            Text(planText(disposition))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func planText(_ disposition: PunchReviewPlanDispositionV1) -> String {
        switch disposition {
        case .available: return "Available from its recorded reference"
        case .manualFallback: return "Manual fallback required"
        case .externalLocal: return "External local reference recorded"
        case .unavailable: return "Unavailable; use recorded manual fallback"
        }
    }

    private func nextScopeText(_ projection: PunchReviewWorkflowProjectionV1) -> String {
        guard let nextScopeItemID = projection.nextScopeItemID else {
            return "Every scope item has a recorded decision."
        }
        return "Next scope item requiring a decision: \(nextScopeItemID)."
    }

    private func decisionText(_ decision: PunchItemProjectionV1?) -> String {
        guard let decision else { return "No decision recorded" }
        return "Decision: \(decision.disposition.rawValue.replacingOccurrences(of: "_", with: " "))"
    }

    private func closeoutActionTitle(_ action: PunchReviewCloseoutActionV1?) -> String {
        switch action {
        case .recordFieldComplete: return "Record field completion"
        case .submitForReview: return "Submit recorded closeout for review"
        case .finalizeRecordedCloseout: return "Finalize recorded closeout"
        case .none: return "Validate closeout"
        }
    }

    private func command(named name: CommandName) -> PunchReviewWorkflowCommandV1? {
        commands.first { command in
            switch (name, command) {
            case (.start, .start), (.resume, .resume), (.pause, .pause),
                 (.recordBasisVariation, .recordBasisVariation), (.closeout, .closeout):
                return true
            default:
                return false
            }
        }
    }

    private var interruptionRecoveryCommand: PunchReviewWorkflowCommandV1? {
        commands.first { command in
            if case .interrupt = command { return true }
            return false
        }
    }

    private enum CommandName {
        case start, resume, pause, recordBasisVariation, closeout
    }

    private func commandIdentifier(_ command: PunchReviewWorkflowCommandV1) -> String {
        switch command {
        case .start: return "start"
        case .resume: return "resume"
        case .pause: return "pause"
        case .interrupt: return "interrupt"
        case .recordBasisVariation: return "basis-variation"
        case .closeout: return "closeout"
        }
    }

    private func perform(_ command: PunchReviewWorkflowCommandV1, recovery: Bool = false) {
        guard !isPerforming else { return }
        isPerforming = true
        operationMessage = recovery ? "Replaying the recorded recovery command…" : "Submitting the supplied punch-review command…"
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let result = try await (recovery
                    ? coordinator.recover(command, context: context)
                    : coordinator.execute(command, context: context))
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no acceptance is claimed."
                    return
                }
                operationMessage = "The canonical activity record accepted the command. Refresh from that record before continuing."
                onAccepted?(result)
            } catch is CancellationError {
                operationMessage = "The request was cancelled. Reload the canonical record before retrying; no acceptance is claimed."
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no acceptance is claimed."
                    return
                }
                operationMessage = "The supplied command was not accepted. The current record remains the source of truth."
            }
        }
    }
}

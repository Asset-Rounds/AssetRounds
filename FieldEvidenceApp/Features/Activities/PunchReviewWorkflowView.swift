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
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.punchReviewNavigationTitle))
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
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewIntroduction))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var invalidContext: some View {
        WorklightCard {
            Label(BundledLocalizationCatalogV1.v30Text(.punchReviewUnavailable), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewUnavailableMessage))
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
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.punchReviewReadiness), identifier: Self.readinessAccessibilityIdentifier)
            if projection.blockers.isEmpty {
                Label(BundledLocalizationCatalogV1.v30Text(.punchReviewNoStartBlocker), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.informationText)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.punchReviewResolveBlockers))
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
                    .accessibilityLabel(BundledLocalizationCatalogV1.v30PunchReviewBlockerAccessibility(kind: blocker.kind.rawValue, reason: blocker.reason))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func preparation(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.punchReviewPreparation), identifier: "\(Self.screenAccessibilityIdentifier).preparation")
            capabilityRow(BundledLocalizationCatalogV1.v30Text(.punchReviewPlan), disposition: projection.planDisposition)
            Label(
                projection.installationSnapshotAvailable
                    ? BundledLocalizationCatalogV1.v30Text(.punchReviewInstallationSnapshotAvailable)
                    : BundledLocalizationCatalogV1.v30Text(.punchReviewNoInstallationSnapshot),
                systemImage: projection.installationSnapshotAvailable ? "doc.text" : "doc.badge.ellipsis"
            )
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewPreparationNotice))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func execution(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.punchReviewExecution), identifier: "\(Self.screenAccessibilityIdentifier).execution")
            stateLabel(projection.envelope.state)
            operationStatus

            switch projection.envelope.state {
            case .ready:
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.punchReviewStart), command: command(named: .start), disabled: !projection.canStart)
                if !projection.canStart {
                    Text(BundledLocalizationCatalogV1.v30Text(.punchReviewStartUnavailable))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            case .inProgress:
                Text(nextScopeText(projection))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.punchReviewPause), command: command(named: .pause))
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.punchReviewRecordInterruption), command: interruptionRecoveryCommand)
            case .paused, .changesRequested:
                Text(BundledLocalizationCatalogV1.v30Text(.punchReviewPausedNotice))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.punchReviewResume), command: command(named: .resume))
            case .deferred, .unableToComplete, .cancelled:
                Text(BundledLocalizationCatalogV1.v30Text(.punchReviewInterruptedNotice))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                recoveryButton
            default:
                Text(BundledLocalizationCatalogV1.v30Text(.punchReviewNotExecutable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func scopeAndRecheck(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.punchReviewDecisionsCorrectionsRechecks), identifier: Self.scopeAccessibilityIdentifier)
            ForEach(projection.scope, id: \.definition.scopeItemID) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(BundledLocalizationCatalogV1.v30PunchReviewScopeItemOrdinal(ordinal: item.definition.ordinal + 1, title: item.definition.title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(decisionText(item.decision))
                        .font(.footnote)
                        .foregroundStyle(item.hasRecordedDecision ? DesignTokens.Colors.informationText : DesignTokens.Colors.secondaryText)
                    Text(BundledLocalizationCatalogV1.v30PunchReviewFindingCounts(unresolvedCount: item.unresolvedFindingCount, resolvedCount: item.resolvedFindingCount))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(Self.scopeAccessibilityIdentifier).\(item.definition.scopeItemID)")
            }
            Text(BundledLocalizationCatalogV1.v30PunchReviewProjectedRecordCounts(correctiveActionCount: projection.report.correctiveActionSHA256s.count, verifiedRecheckCount: projection.report.verifiedRecheckSHA256s.count))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewFindingsBoundary))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.punchReviewRecordBasisVariation), command: command(named: .recordBasisVariation))
        }
        .accessibilityElement(children: .contain)
    }

    private func closeoutAndReport(_ projection: PunchReviewWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.punchReviewCloseoutAndReportProjection), identifier: Self.reportAccessibilityIdentifier)
            Text(projection.canCloseout
                  ? BundledLocalizationCatalogV1.v30Text(.punchReviewCloseoutReady)
                  : BundledLocalizationCatalogV1.v30Text(.punchReviewCloseoutUnavailable))
                .font(.body)
                .foregroundStyle(projection.canCloseout ? DesignTokens.Colors.informationText : DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: closeoutActionTitle(projection.nextCloseoutAction), command: command(named: .closeout), disabled: !projection.canCloseout)
            Label(
                projection.reportReady
                    ? BundledLocalizationCatalogV1.v30Text(.punchReviewReportReady)
                    : BundledLocalizationCatalogV1.v30Text(.punchReviewReportNotReady),
                systemImage: projection.reportReady ? "doc.text" : "doc.badge.ellipsis"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewReportReadyBoundary))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var operatingBoundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.punchReviewLocalBoundaries), identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewOfflineBoundary))
            Text(BundledLocalizationCatalogV1.v30Text(.punchReviewPermissionsBoundary))
            if reduceMotion {
                Text(BundledLocalizationCatalogV1.v30Text(.punchReviewReduceMotionNotice))
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
                Button(BundledLocalizationCatalogV1.v30Text(.punchReviewRetryRecovery)) { perform(command, recovery: true) }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .disabled(isPerforming)
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.punchReviewRetryRecoveryHint))
                    .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.punchReviewNoRecoveryCommand))
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
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.punchReviewCommandHint))
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text(BundledLocalizationCatalogV1.v30PunchReviewCommandUnavailable(title: title))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
    }

    private func sectionHeading(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func stateLabel(_ state: ActivityStateV2) -> some View {
        Label(BundledLocalizationCatalogV1.v30PunchReviewState(state: state.rawValue.replacingOccurrences(of: "_", with: " ")), systemImage: "circle.inset.filled")
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
        case .available: return BundledLocalizationCatalogV1.v30Text(.punchReviewCapabilityAvailable)
        case .manualFallback: return BundledLocalizationCatalogV1.v30Text(.punchReviewCapabilityManualFallback)
        case .externalLocal: return BundledLocalizationCatalogV1.v30Text(.punchReviewCapabilityExternalLocal)
        case .unavailable: return BundledLocalizationCatalogV1.v30Text(.punchReviewCapabilityUnavailable)
        }
    }

    private func nextScopeText(_ projection: PunchReviewWorkflowProjectionV1) -> String {
        guard let nextScopeItemID = projection.nextScopeItemID else {
            return BundledLocalizationCatalogV1.v30Text(.punchReviewAllScopeItemsRecorded)
        }
        return BundledLocalizationCatalogV1.v30PunchReviewNextScopeItem(scopeItemID: nextScopeItemID)
    }

    private func decisionText(_ decision: PunchItemProjectionV1?) -> String {
        guard let decision else { return BundledLocalizationCatalogV1.v30Text(.punchReviewNoDecisionRecorded) }
        return BundledLocalizationCatalogV1.v30PunchReviewDecision(disposition: decision.disposition.rawValue.replacingOccurrences(of: "_", with: " "))
    }

    private func closeoutActionTitle(_ action: PunchReviewCloseoutActionV1?) -> String {
        switch action {
        case .recordFieldComplete: return BundledLocalizationCatalogV1.v30Text(.punchReviewRecordFieldCompletion)
        case .submitForReview: return BundledLocalizationCatalogV1.v30Text(.punchReviewSubmitCloseoutForReview)
        case .finalizeRecordedCloseout: return BundledLocalizationCatalogV1.v30Text(.punchReviewFinalizeCloseout)
        case .none: return BundledLocalizationCatalogV1.v30Text(.punchReviewValidateCloseout)
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
        operationMessage = recovery ? BundledLocalizationCatalogV1.v30Text(.punchReviewReplayingRecovery) : BundledLocalizationCatalogV1.v30Text(.punchReviewSubmittingCommand)
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let result = try await (recovery
                    ? coordinator.recover(command, context: context)
                    : coordinator.execute(command, context: context))
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.punchReviewRequestCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.punchReviewCommandAccepted)
                onAccepted?(result)
            } catch is CancellationError {
                operationMessage = BundledLocalizationCatalogV1.v30Text(.punchReviewRequestCancelled)
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.punchReviewRequestCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.punchReviewCommandNotAccepted)
            }
        }
    }
}

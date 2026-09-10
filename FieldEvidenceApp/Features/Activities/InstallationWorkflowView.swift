import SwiftUI

/// A bounded installation-workflow surface over the C33 coordinator. The
/// caller supplies only canonical context and prevalidated commands; this view
/// does not construct mutations, retain scratch work, or introduce a writer,
/// report renderer, route, or persistence owner.
@MainActor
struct InstallationWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c33.installation.screen"
    static let readinessAccessibilityIdentifier = "v23.p04.c33.installation.readiness"
    static let tasksAccessibilityIdentifier = "v23.p04.c33.installation.tasks"
    static let recoveryAccessibilityIdentifier = "v23.p04.c33.installation.recovery"
    static let reportAccessibilityIdentifier = "v23.p04.c33.installation.report"
    static let statusAccessibilityIdentifier = "v23.p04.c33.installation.status"

    let coordinator: InstallationWorkflowCoordinatorV1
    let context: InstallationWorkflowContextV1
    let commands: [InstallationWorkflowCommandV1]
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
        coordinator: InstallationWorkflowCoordinatorV1,
        context: InstallationWorkflowContextV1,
        commands: [InstallationWorkflowCommandV1] = [],
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
                    execution(projection)
                    taskList(projection)
                    captureAndVariation(projection)
                    optionalInputs(projection)
                    closeoutAndReport(projection)
                    operatingBoundaries
                } else {
                    invalidContext
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.installationWorkflowNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = projection?.blockers.isEmpty == false
                ? .errorSummary
                : .heading
        }
        .onChange(of: operationMessage) { _, _ in
            accessibilityFocus = .operationStatus
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var projection: InstallationWorkflowProjectionV1? {
        try? coordinator.projection(for: context)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)

            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowIntroduction))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var invalidContext: some View {
        WorklightCard {
            Label(BundledLocalizationCatalogV1.v30Text(.installationWorkflowUnavailable), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowUnavailableMessage))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($accessibilityFocus, equals: .errorSummary)
        .accessibilityIdentifier(Self.readinessAccessibilityIdentifier)
    }

    private func readiness(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.installationWorkflowReadiness), identifier: Self.readinessAccessibilityIdentifier)
            if projection.blockers.isEmpty {
                Label(BundledLocalizationCatalogV1.v30Text(.installationWorkflowNoStartBlocker), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .accessibilityElement(children: .combine)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowResolveBlockers))
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
                    .accessibilityLabel(BundledLocalizationCatalogV1.v30InstallationWorkflowBlockerAccessibility(kind: blocker.kind.rawValue, reason: blocker.reason))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func execution(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.installationWorkflowExecution), identifier: "\(Self.screenAccessibilityIdentifier).execution")
            stateLabel(projection.envelope.state)

            if let operationMessage {
                Label(operationMessage, systemImage: "info.circle")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($accessibilityFocus, equals: .operationStatus)
                    .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
            }

            switch projection.envelope.state {
            case .ready:
                commandButton(
                    title: BundledLocalizationCatalogV1.v30Text(.installationWorkflowStartInstallation),
                    command: command(named: .start),
                    disabled: !projection.canStart
                )
                if !projection.canStart {
                    Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowStartUnavailable))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            case .inProgress:
                Text(nextTaskText(projection))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.installationWorkflowPauseInstallation), command: command(named: .pause))
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.installationWorkflowRecordInterruption), command: interruptionRecoveryCommand)
            case .paused:
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowPausedNotice))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.installationWorkflowResumeInstallation), command: command(named: .resume))
            case .deferred, .unableToComplete, .cancelled:
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowInterruptedNotice))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                recoveryButton
            default:
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowNotExecutable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func taskList(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.installationWorkflowOrderedTasks), identifier: Self.tasksAccessibilityIdentifier)
            ForEach(projection.tasks, id: \.definition.taskID) { task in
                VStack(alignment: .leading, spacing: 2) {
                    Text(BundledLocalizationCatalogV1.v30InstallationWorkflowTaskOrdinal(ordinal: task.definition.ordinal + 1, title: task.definition.title))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(taskOutcomeText(task.currentResult?.outcome))
                        .font(.footnote)
                        .foregroundStyle(task.isTerminal ? DesignTokens.Colors.informationText : DesignTokens.Colors.secondaryText)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(BundledLocalizationCatalogV1.v30InstallationWorkflowTaskAccessibility(ordinal: task.definition.ordinal + 1, title: task.definition.title, outcome: taskOutcomeText(task.currentResult?.outcome)))
                .accessibilityIdentifier("\(Self.tasksAccessibilityIdentifier).\(task.definition.taskID)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func captureAndVariation(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.installationWorkflowAsBuiltAndVariations), identifier: "\(Self.screenAccessibilityIdentifier).as-built")
            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowAsBuiltNotice))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(projection.report.asBuiltSnapshotSHA256 == nil ? BundledLocalizationCatalogV1.v30Text(.installationWorkflowNoAsBuiltSnapshot) : BundledLocalizationCatalogV1.v30Text(.installationWorkflowAsBuiltSnapshotRecorded))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.installationWorkflowRecordTaskResult), command: command(named: .recordTaskResult))
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.installationWorkflowRecordAsBuiltFacts), command: command(named: .recordAsBuilt))
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.installationWorkflowRecordVariation), command: command(named: .recordVariation))
        }
        .accessibilityElement(children: .contain)
    }

    private func optionalInputs(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.installationWorkflowOptionalPlanAndScan), identifier: "\(Self.screenAccessibilityIdentifier).optional-inputs")
            capabilityRow(BundledLocalizationCatalogV1.v30Text(.installationWorkflowPlan), disposition: projection.planDisposition)
            capabilityRow(BundledLocalizationCatalogV1.v30Text(.installationWorkflowScan), disposition: projection.scanDisposition)
            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowOptionalInputNotice))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func closeoutAndReport(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.installationWorkflowCloseoutAndReporting), identifier: Self.reportAccessibilityIdentifier)
            if projection.canCloseout {
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowCloseoutReady))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowCloseoutUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            commandButton(
                title: closeoutActionTitle(projection.nextCloseoutAction),
                command: command(named: .closeout),
                disabled: !projection.canCloseout
            )

            let reportReady = projection.report.state == .finalized
                && projection.envelope.reviewState == .acceptedRecordedFacts
                && projection.report.closeoutSHA256 != nil
            Label(
                reportReady
                    ? BundledLocalizationCatalogV1.v30Text(.installationWorkflowReportReady)
                    : BundledLocalizationCatalogV1.v30Text(.installationWorkflowReportNotReady),
                systemImage: reportReady ? "doc.text" : "doc.badge.ellipsis"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowReportReadyBoundary))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var operatingBoundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.installationWorkflowLocalBoundaries), identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowOfflineBoundary))
            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowPermissionsBoundary))
            Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowProtectedDataBoundary))
            if reduceMotion {
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowReduceMotionNotice))
            }
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var recoveryButton: some View {
        Group {
            if let command = interruptionRecoveryCommand {
                Button(BundledLocalizationCatalogV1.v30Text(.installationWorkflowRetryRecovery)) {
                    perform(command, recovery: true)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(isPerforming)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.installationWorkflowRetryRecoveryHint))
                .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.installationWorkflowNoRecoveryCommand))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
            }
        }
    }

    @ViewBuilder
    private func commandButton(
        title: String,
        command: InstallationWorkflowCommandV1?,
        disabled: Bool = false
    ) -> some View {
        if let command {
            Button(title) { perform(command) }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(disabled || isPerforming)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.installationWorkflowCommandHint))
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text(BundledLocalizationCatalogV1.v30InstallationWorkflowCommandUnavailable(title: title))
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
        Label(BundledLocalizationCatalogV1.v30InstallationWorkflowState(state: state.rawValue.replacingOccurrences(of: "_", with: " ")), systemImage: "circle.inset.filled")
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityElement(children: .combine)
    }

    private func capabilityRow(
        _ label: String,
        disposition: InstallationOptionalCapabilityDispositionV1
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.body.weight(.semibold))
            Spacer(minLength: DesignTokens.Spacing.small)
            Text(capabilityText(disposition))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func capabilityText(_ disposition: InstallationOptionalCapabilityDispositionV1) -> String {
        switch disposition {
        case .available: return BundledLocalizationCatalogV1.v30Text(.installationWorkflowCapabilityAvailable)
        case .manualFallback: return BundledLocalizationCatalogV1.v30Text(.installationWorkflowCapabilityManualFallback)
        case .unavailable: return BundledLocalizationCatalogV1.v30Text(.installationWorkflowCapabilityUnavailable)
        }
    }

    private func nextTaskText(_ projection: InstallationWorkflowProjectionV1) -> String {
        guard let nextTaskID = projection.nextTaskID else {
            return BundledLocalizationCatalogV1.v30Text(.installationWorkflowAllTasksTerminal)
        }
        return BundledLocalizationCatalogV1.v30InstallationWorkflowNextTask(taskID: nextTaskID)
    }

    private func taskOutcomeText(_ outcome: InstallationTaskOutcomeV1?) -> String {
        guard let outcome else { return BundledLocalizationCatalogV1.v30Text(.installationWorkflowNotYetRecorded) }
        return BundledLocalizationCatalogV1.v30InstallationWorkflowTaskOutcome(outcome: outcome.rawValue.replacingOccurrences(of: "_", with: " "))
    }

    private func closeoutActionTitle(_ action: InstallationCloseoutActionV1?) -> String {
        switch action {
        case .recordFieldComplete: return BundledLocalizationCatalogV1.v30Text(.installationWorkflowRecordFieldCompletion)
        case .submitForReview: return BundledLocalizationCatalogV1.v30Text(.installationWorkflowSubmitCloseoutForReview)
        case .finalizeRecordedCloseout: return BundledLocalizationCatalogV1.v30Text(.installationWorkflowFinalizeCloseout)
        case .none: return BundledLocalizationCatalogV1.v30Text(.installationWorkflowValidateCloseout)
        }
    }

    private func command(named name: CommandName) -> InstallationWorkflowCommandV1? {
        commands.first { command in
            switch (name, command) {
            case (.start, .start), (.resume, .resume), (.pause, .pause),
                 (.recordTaskResult, .recordTaskResult), (.recordAsBuilt, .recordAsBuilt),
                 (.recordVariation, .recordVariation), (.closeout, .closeout): return true
            default: return false
            }
        }
    }

    private var interruptionRecoveryCommand: InstallationWorkflowCommandV1? {
        commands.first { command in
            if case .interrupt = command { return true }
            return false
        }
    }

    private enum CommandName {
        case start, resume, pause, recordTaskResult, recordAsBuilt, recordVariation, closeout
    }

    private func commandIdentifier(_ command: InstallationWorkflowCommandV1) -> String {
        switch command {
        case .start: return "start"
        case .resume: return "resume"
        case .pause: return "pause"
        case .interrupt: return "interrupt"
        case .recordTaskResult: return "task-result"
        case .recordAsBuilt: return "as-built"
        case .recordVariation: return "variation"
        case .closeout: return "closeout"
        }
    }

    private func perform(_ command: InstallationWorkflowCommandV1, recovery: Bool = false) {
        guard !isPerforming else { return }
        isPerforming = true
        operationMessage = recovery ? BundledLocalizationCatalogV1.v30Text(.installationWorkflowReplayingRecovery) : BundledLocalizationCatalogV1.v30Text(.installationWorkflowSubmittingCommand)
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let result: ActivityContractAcceptanceResultV2
                if recovery {
                    result = try await coordinator.recover(command, context: context)
                } else {
                    result = try await coordinator.execute(command, context: context)
                }
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.installationWorkflowRequestCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.installationWorkflowCommandAccepted)
                onAccepted?(result)
            } catch is CancellationError {
                operationMessage = BundledLocalizationCatalogV1.v30Text(.installationWorkflowRequestCancelled)
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.installationWorkflowRequestCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.installationWorkflowCommandNotAccepted)
            }
        }
    }
}

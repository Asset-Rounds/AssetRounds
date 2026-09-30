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
        .navigationTitle("Installation")
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
            Text("Installation workflow")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)

            Text("Recorded readiness, tasks, as-built facts, and closeout are shown from the current local activity record.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var invalidContext: some View {
        WorklightCard {
            Label("Installation workflow unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text("The current installation record could not be validated. No workflow command is available from this screen.")
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
            sectionHeading("Readiness", identifier: Self.readinessAccessibilityIdentifier)
            if projection.blockers.isEmpty {
                Label("Recorded readiness has no start blocker.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .accessibilityElement(children: .combine)
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

    private func execution(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Execution", identifier: "\(Self.screenAccessibilityIdentifier).execution")
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
                    title: "Start installation",
                    command: command(named: .start),
                    disabled: !projection.canStart
                )
                if !projection.canStart {
                    Text("Start is unavailable until recorded readiness blockers are resolved.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            case .inProgress:
                Text(nextTaskText(projection))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: "Pause installation", command: command(named: .pause))
                commandButton(title: "Record interruption", command: interruptionRecoveryCommand)
            case .paused:
                Text("The activity is paused. Resume only with the current record and a supplied resume command.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: "Resume installation", command: command(named: .resume))
            case .deferred, .unableToComplete, .cancelled:
                Text("This attempt is interrupted. Relaunch does not restore unrecorded scratch work; recover only by replaying the same supplied mutation identity.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                recoveryButton
            default:
                Text("This activity is not currently executable from the installation workflow surface.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func taskList(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Ordered tasks", identifier: Self.tasksAccessibilityIdentifier)
            ForEach(projection.tasks, id: \.definition.taskID) { task in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(task.definition.ordinal + 1). \(task.definition.title)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(taskOutcomeText(task.currentResult?.outcome))
                        .font(.footnote)
                        .foregroundStyle(task.isTerminal ? DesignTokens.Colors.informationText : DesignTokens.Colors.secondaryText)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Task \(task.definition.ordinal + 1). \(task.definition.title). \(taskOutcomeText(task.currentResult?.outcome))")
                .accessibilityIdentifier("\(Self.tasksAccessibilityIdentifier).\(task.definition.taskID)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func captureAndVariation(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("As-built and variations", identifier: "\(Self.screenAccessibilityIdentifier).as-built")
            Text("Capture as-built facts and a recorded variation only through supplied canonical commands. This screen does not invent placement, measurement, evidence, or variation facts.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(projection.report.asBuiltSnapshotSHA256 == nil ? "No as-built snapshot is recorded." : "An as-built snapshot is recorded for the current task-result heads.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            commandButton(title: "Record task result", command: command(named: .recordTaskResult))
            commandButton(title: "Record as-built facts", command: command(named: .recordAsBuilt))
            commandButton(title: "Record variation", command: command(named: .recordVariation))
        }
        .accessibilityElement(children: .contain)
    }

    private func optionalInputs(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Optional plan and scan", identifier: "\(Self.screenAccessibilityIdentifier).optional-inputs")
            capabilityRow("Plan", disposition: projection.planDisposition)
            capabilityRow("Scan", disposition: projection.scanDisposition)
            Text("When a plan or scan is unavailable, use only the existing recorded manual fallback. Availability is not evidence that a plan or scan succeeded.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func closeoutAndReport(_ projection: InstallationWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Closeout and reporting", identifier: Self.reportAccessibilityIdentifier)
            if projection.canCloseout {
                Text("All ordered tasks are terminal and an as-built snapshot is available for closeout validation.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Closeout remains unavailable until required terminal task results and as-built facts are recorded.")
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
                    ? "The accepted recorded closeout is report-ready for the existing renderer."
                    : "No accepted finalized closeout is report-ready.",
                systemImage: reportReady ? "doc.text" : "doc.badge.ellipsis"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            Text("Report-ready does not mean rendered, sent, delivered, received, reviewed, verified, safe, compliant, permitted, commissioned, approved, or in service.")
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
            Text("Permissions: this view does not request camera, location, or other system permission; unavailable capabilities remain explicit.")
            Text("Protected data and storage: resolve their recorded readiness blockers before starting; this view does not bypass them.")
            if reduceMotion {
                Text("Reduce Motion is on. State changes are presented without added animation.")
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
                Button("Retry recorded recovery") {
                    perform(command, recovery: true)
                }
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
    private func commandButton(
        title: String,
        command: InstallationWorkflowCommandV1?,
        disabled: Bool = false
    ) -> some View {
        if let command {
            Button(title) { perform(command) }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(disabled || isPerforming)
                .accessibilityHint("Uses the supplied canonical installation command.")
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
        case .available: return "Available from its recorded receipt"
        case .manualFallback: return "Manual fallback required"
        case .unavailable: return "Unavailable; use recorded manual fallback"
        }
    }

    private func nextTaskText(_ projection: InstallationWorkflowProjectionV1) -> String {
        guard let nextTaskID = projection.nextTaskID else {
            return "Every ordered task currently has a terminal recorded result."
        }
        return "Next recorded task: \(nextTaskID)."
    }

    private func taskOutcomeText(_ outcome: InstallationTaskOutcomeV1?) -> String {
        guard let outcome else { return "Not yet recorded" }
        return outcome.rawValue.replacingOccurrences(of: "_", with: " ")
    }

    private func closeoutActionTitle(_ action: InstallationCloseoutActionV1?) -> String {
        switch action {
        case .recordFieldComplete: return "Record field completion"
        case .submitForReview: return "Submit recorded closeout for review"
        case .finalizeRecordedCloseout: return "Finalize recorded closeout"
        case .none: return "Validate closeout"
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
        operationMessage = recovery ? "Replaying the recorded recovery command…" : "Submitting the supplied installation command…"
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

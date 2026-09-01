import SwiftUI

/// A narrow C38 surface over the existing scheduling coordinators. The host
/// supplies validated context and typed commands; this view does not author a
/// second recurrence grammar, exception writer, notification owner, or route.
@MainActor
struct AdvancedRecurrenceWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c38.advanced-recurrence.screen"
    static let summaryAccessibilityIdentifier = "v23.p04.c38.advanced-recurrence.summary"
    static let advancedAccessibilityIdentifier = "v23.p04.c38.advanced-recurrence.advanced"
    static let previewAccessibilityIdentifier = "v23.p04.c38.advanced-recurrence.preview"
    static let historyAccessibilityIdentifier = "v23.p04.c38.advanced-recurrence.history"
    static let statusAccessibilityIdentifier = "v23.p04.c38.advanced-recurrence.status"

    let coordinator: AdvancedRecurrenceWorkflowCoordinatorV1
    let context: AdvancedRecurrenceWorkflowContextV1
    let commands: [AdvancedRecurrenceWorkflowCommandV1]
    let onOutcome: (@MainActor (AdvancedRecurrenceWorkflowOutcomeV1) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showAdvancedDetails = false
    @State private var isPerforming = false
    @State private var operationMessage: String?
    @State private var recoverableCommand: AdvancedRecurrenceWorkflowCommandV1?
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum FocusTarget: Hashable {
        case heading
        case unavailable
        case status
    }

    init(
        coordinator: AdvancedRecurrenceWorkflowCoordinatorV1,
        context: AdvancedRecurrenceWorkflowContextV1,
        commands: [AdvancedRecurrenceWorkflowCommandV1] = [],
        onOutcome: (@MainActor (AdvancedRecurrenceWorkflowOutcomeV1) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.context = context
        self.commands = commands
        self.onOutcome = onOutcome
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                if let projection {
                    baseSchedule(projection)
                    advancedDisclosure(projection)
                    projectedHistory(projection)
                    boundaries
                } else {
                    unavailable
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Scheduling")
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = projection == nil ? .unavailable : .heading
        }
        .onChange(of: operationMessage) { _, _ in
            accessibilityFocus = .status
        }
    }

    private var projection: AdvancedRecurrenceWorkflowProjectionV1? {
        try? coordinator.project(context: context)
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Advanced recurrence")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)

            Text("Keep the base schedule simple. Reveal pattern and exception detail only when it is needed.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unavailable: some View {
        WorklightCard {
            Label("Advanced recurrence is unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text("The supplied schedule context could not be validated. No scheduling or reminder action is available from this screen.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($accessibilityFocus, equals: .unavailable)
        .accessibilityIdentifier(Self.summaryAccessibilityIdentifier)
    }

    private func baseSchedule(_ projection: AdvancedRecurrenceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Base schedule", identifier: Self.summaryAccessibilityIdentifier)
            summaryRow("Pattern", value: patternSummary(projection.pattern))
            summaryRow("Active dates", value: dateRangeSummary(projection.activeRange))
            summaryRow("Time zone", value: projection.ianaTimeZoneIdentifier)
            summaryRow("Preview evaluated", value: dateTimeSummary(projection.evaluatedAt))
            summaryRow("Clock basis", value: display(projection.clockDisposition.rawValue))

            if let next = projection.dueQueue.entries.first {
                summaryRow("Next projected run", value: nextRunSummary(next))
            } else {
                Text("There is no projected next run in the current record.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            Text("A projected run is not a scheduled task, completion, reminder set, or owner receipt.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func advancedDisclosure(_ projection: AdvancedRecurrenceWorkflowProjectionV1) -> some View {
        WorklightCard {
            DisclosureGroup(isExpanded: $showAdvancedDetails) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    summaryRow("Ambiguous local time", value: display(projection.ambiguousTimePolicy.rawValue))
                    summaryRow("Missing local time", value: display(projection.nonexistentTimePolicy.rawValue))
                    exceptionPreview(projection)
                    reminderState(projection.reminders)

                    if let recoverableCommand {
                        Button("Retry last supplied command") {
                            perform(recoverableCommand, recovery: true)
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(isPerforming)
                        .accessibilityHint("Replays the same supplied canonical command and relies on its existing mutation identity.")
                        .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.recover")
                    }

                    if let operationMessage {
                        Label(operationMessage, systemImage: "info.circle")
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.informationText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityFocused($accessibilityFocus, equals: .status)
                            .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
                    }
                }
                .padding(.top, DesignTokens.Spacing.small)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced exceptions and history controls")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    Text(showAdvancedDetails ? "Hide advanced recurrence details." : "Show advanced recurrence details on request.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            }
            .tint(DesignTokens.Colors.primaryText)
            .accessibilityIdentifier(Self.advancedAccessibilityIdentifier)
            .accessibilityHint("Reveals advanced recurrence, exception preview, and reminder projection detail.")
        }
        .accessibilityElement(children: .contain)
    }

    private func exceptionPreview(_ projection: AdvancedRecurrenceWorkflowProjectionV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading("Preview before commit", identifier: Self.previewAccessibilityIdentifier)
            Text("Preview shows the current skip, move, add, or override effects without writing a canonical exception.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if projection.exceptionPreview.effects.isEmpty {
                Text("The current preview has no affected occurrences.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(projection.exceptionPreview.effects.indices, id: \.self) { index in
                    let effect = projection.exceptionPreview.effects[index]
                    summaryRow(
                        "Projected effect \(index + 1)",
                        value: "\(display(effect.disposition.rawValue)); occurrence \(String(describing: effect.occurrenceID))"
                    )
                }
            }

            Text("Preview remains zero-write. Commit only with a separately supplied canonical command that carries this preview and frontier.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            commandButton("Preview supplied exception", command: command(named: .previewException))
            commandButton(
                "Commit supplied preview and exception",
                command: command(named: .commitException),
                disabled: !projection.canCommitExceptionChange
            )
        }
    }

    private func reminderState(_ state: AdvancedRecurrenceReminderStateV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading("Reminder projection", identifier: "\(Self.screenAccessibilityIdentifier).reminders")
            switch state {
            case let .available(reminders):
                summaryRow("Projected reminders", value: "\(reminders.reminders.count)")
                Text("A projection does not mean a reminder has been set. Reconciliation is available only through a supplied command and its owner receipt.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .suppressedForClockRollback:
                Label("Reminder reconciliation is suppressed because the clock basis moved backward.", systemImage: "clock.badge.exclamationmark")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
            commandButton("Reconcile supplied reminder projection", command: command(named: .reconcileReminders))
        }
    }

    private func projectedHistory(_ projection: AdvancedRecurrenceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Recorded occurrence history", identifier: Self.historyAccessibilityIdentifier)
            if projection.history.isEmpty {
                Text("No recorded occurrence history is available in the current local schedule record.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(projection.history, id: \.occurrenceID) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Occurrence \(String(describing: row.occurrenceID))")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        Text("Recorded action: \(display(row.action.rawValue)). Recorded state: \(display(row.state.rawValue)).")
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                        if let dueAt = row.effectiveDueAtUTC {
                            Text("Effective time: \(dateTimeSummary(dueAt)).")
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                        if let exceptionKind = row.exceptionKind {
                            Text("Recorded exception: \(display(exceptionKind.rawValue)).")
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                        if row.isImmutableHistory {
                            Text("This history row is immutable.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DesignTokens.Colors.primaryText)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }

            commandButton("Record supplied occurrence event", command: command(named: .recordOccurrence))
            commandButton("Preview supplied occurrence window", command: command(named: .previewGeneration))
            commandButton("Generate supplied frozen occurrence plan", command: command(named: .generate))
        }
        .accessibilityElement(children: .contain)
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading("Scheduling boundaries", identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text("This surface does not request calendar permission, create a cloud schedule, run in the background, or claim a server result.")
            Text("Use a supplied canonical command for any record or generation attempt. Read its owner receipt before treating a completion, schedule, or reminder as recorded.")
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
    private func commandButton(
        _ title: String,
        command: AdvancedRecurrenceWorkflowCommandV1?,
        disabled: Bool = false
    ) -> some View {
        if let command {
            Button(title) { perform(command) }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(disabled || isPerforming)
                .accessibilityHint("Uses the supplied canonical scheduling command.")
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text("\(title) is unavailable until its prevalidated canonical command is supplied.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeading(_ title: LocalizedStringKey, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Spacer(minLength: DesignTokens.Spacing.small)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func command(named kind: CommandKind) -> AdvancedRecurrenceWorkflowCommandV1? {
        commands.first { command in
            switch (kind, command) {
            case (.previewException, .previewException(_)),
                 (.previewGeneration, .previewGeneration(_)),
                 (.commitException, .commitException(_, _, _)),
                 (.recordOccurrence, .recordOccurrence(_, _)),
                 (.generate, .generate(_, _)),
                 (.reconcileReminders, .reconcileReminders):
                return true
            default:
                return false
            }
        }
    }

    private enum CommandKind {
        case previewException
        case previewGeneration
        case commitException
        case recordOccurrence
        case generate
        case reconcileReminders
    }

    private func commandIdentifier(_ command: AdvancedRecurrenceWorkflowCommandV1) -> String {
        switch command {
        case .previewException(_): return "preview-exception"
        case .previewGeneration(_): return "preview-generation"
        case .commitException(_, _, _): return "commit-exception"
        case .recordOccurrence(_, _): return "record-occurrence"
        case .generate(_, _): return "generate-occurrences"
        case .reconcileReminders: return "reconcile-reminders"
        }
    }

    private func perform(_ command: AdvancedRecurrenceWorkflowCommandV1, recovery: Bool = false) {
        guard !isPerforming else { return }
        isPerforming = true
        recoverableCommand = command
        operationMessage = "Submitting the supplied scheduling command…"
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let outcome: AdvancedRecurrenceWorkflowOutcomeV1
                if recovery {
                    outcome = try await coordinator.recover(command, context: context)
                } else {
                    outcome = try await coordinator.execute(command, context: context)
                }
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical schedule record before retrying; no effect is claimed."
                    return
                }
                operationMessage = outcomeText(outcome)
                onOutcome?(outcome)
            } catch is CancellationError {
                operationMessage = "The request was cancelled. Reload the canonical schedule record before retrying; no effect is claimed."
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical schedule record before retrying; no effect is claimed."
                    return
                }
                operationMessage = "The supplied command was not completed. No schedule, completion, reminder, calendar, cloud, or background result is claimed."
            }
        }
    }

    private func outcomeText(_ outcome: AdvancedRecurrenceWorkflowOutcomeV1) -> String {
        switch outcome {
        case .projected:
            return "The advanced exception preview was recalculated without a canonical exception commit."
        case .generationPreview:
            return "The supplied occurrence window was previewed without generating a canonical schedule record."
        case .exceptionCommitted:
            return "A canonical exception receipt was returned. The exception is saved or updated only as established by that receipt; reload the canonical schedule record."
        case .occurrenceRecorded:
            return "A canonical mutation receipt was returned. Reload the record before treating an occurrence state as recorded."
        case let .occurrencesGenerated(receipt):
            return receipt == nil
                ? "Generation returned no new canonical receipt. No schedule claim is inferred."
                : "A canonical generation receipt was returned. Reload the record before treating any projected run as scheduled."
        case .remindersReconciled:
            return "Reminder reconciliation returned a projection. This view does not claim that a reminder was set."
        }
    }

    private func patternSummary(_ pattern: AdvancedRecurrenceAuthoringPatternV1) -> String {
        switch pattern {
        case let .daily(interval): return "Every \(interval) day(s)"
        case let .weekly(interval, weekdays):
            return "Every \(interval) week(s) on \(weekdays.map { weekdayName($0) }.joined(separator: ", "))"
        case let .calendarDay(interval, day, missingDayPolicy):
            return "Every \(interval) month(s) on day \(day); \(display(missingDayPolicy.rawValue))"
        case let .weekday(interval, ordinal, weekday):
            return "Every \(interval) month(s), \(display(ordinal.rawValue)) \(weekdayName(weekday))"
        case let .lastDay(interval): return "Every \(interval) month(s) on the last day"
        }
    }

    private func nextRunSummary(_ entry: DueQueueEntryV1) -> String {
        let due = entry.effectiveDueAtUTC.map(dateTimeSummary) ?? "No resolved time"
        return "\(display(entry.state.rawValue)); \(due)"
    }

    private func dateRangeSummary(_ range: ScheduleLocalDateRangeV1) -> String {
        "\(range.startsOn.canonicalString) to \(range.endsOn.canonicalString)"
    }

    private func dateTimeSummary(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func weekdayName(_ day: ScheduleWeekdayV1) -> String {
        switch day {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    private func display(_ rawValue: String) -> String {
        rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    }
}

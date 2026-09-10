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
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceNavigationTitle))
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
            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)

            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unavailable: some View {
        WorklightCard {
            Label(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceUnavailable), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceUnavailableDescription))
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
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceBaseScheduleHeading), identifier: Self.summaryAccessibilityIdentifier)
            summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrencePattern), value: patternSummary(projection.pattern))
            summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceActiveDates), value: dateRangeSummary(projection.activeRange))
            summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceTimeZone), value: projection.ianaTimeZoneIdentifier)
            summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrencePreviewEvaluated), value: dateTimeSummary(projection.evaluatedAt))
            summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceClockBasis), value: display(projection.clockDisposition.rawValue))

            if let next = projection.dueQueue.entries.first {
                summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceNextRun), value: nextRunSummary(next))
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceNoNextRun))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceProjectedRunDescription))
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
                    summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceAmbiguousLocalTime), value: display(projection.ambiguousTimePolicy.rawValue))
                    summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceMissingLocalTime), value: display(projection.nonexistentTimePolicy.rawValue))
                    exceptionPreview(projection)
                    reminderState(projection.reminders)

                    if let recoverableCommand {
                        Button(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceRetryCommand)) {
                            perform(recoverableCommand, recovery: true)
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(isPerforming)
                        .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceRetryHint))
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
                    Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceAdvancedControlsHeading))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    Text(showAdvancedDetails ? BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceHideDetails) : BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceShowDetails))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            }
            .tint(DesignTokens.Colors.primaryText)
            .accessibilityIdentifier(Self.advancedAccessibilityIdentifier)
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceDetailsHint))
        }
        .accessibilityElement(children: .contain)
    }

    private func exceptionPreview(_ projection: AdvancedRecurrenceWorkflowProjectionV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.advancedRecurrencePreviewHeading), identifier: Self.previewAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrencePreviewDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if projection.exceptionPreview.effects.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceNoAffectedOccurrences))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(projection.exceptionPreview.effects.indices, id: \.self) { index in
                    let effect = projection.exceptionPreview.effects[index]
                    summaryRow(
                        BundledLocalizationCatalogV1.v30AdvancedRecurrenceProjectedEffect(index: index + 1),
                        value: BundledLocalizationCatalogV1.v30AdvancedRecurrenceEffectValue(disposition: display(effect.disposition.rawValue), occurrence: String(describing: effect.occurrenceID))
                    )
                }
            }

            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrencePreviewCommitDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            commandButton(BundledLocalizationCatalogV1.v30Text(.advancedRecurrencePreviewException), command: command(named: .previewException))
            commandButton(
                BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceCommitPreview),
                command: command(named: .commitException),
                disabled: !projection.canCommitExceptionChange
            )
        }
    }

    private func reminderState(_ state: AdvancedRecurrenceReminderStateV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceReminderHeading), identifier: "\(Self.screenAccessibilityIdentifier).reminders")
            switch state {
            case let .available(reminders):
                summaryRow(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceProjectedReminders), value: "\(reminders.reminders.count)")
                Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceReminderDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .suppressedForClockRollback:
                Label(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceReconciliationSuppressed), systemImage: "clock.badge.exclamationmark")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
            commandButton(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceReconcileReminders), command: command(named: .reconcileReminders))
        }
    }

    private func projectedHistory(_ projection: AdvancedRecurrenceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceHistoryHeading), identifier: Self.historyAccessibilityIdentifier)
            if projection.history.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceNoHistory))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(projection.history, id: \.occurrenceID) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BundledLocalizationCatalogV1.v30AdvancedRecurrenceOccurrence(occurrence: String(describing: row.occurrenceID)))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        Text(BundledLocalizationCatalogV1.v30AdvancedRecurrenceRecordedHistory(action: display(row.action.rawValue), state: display(row.state.rawValue)))
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                        if let dueAt = row.effectiveDueAtUTC {
                            Text(BundledLocalizationCatalogV1.v30AdvancedRecurrenceEffectiveTime(time: dateTimeSummary(dueAt)))
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                        if let exceptionKind = row.exceptionKind {
                            Text(BundledLocalizationCatalogV1.v30AdvancedRecurrenceRecordedException(exception: display(exceptionKind.rawValue)))
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                        if row.isImmutableHistory {
                            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceHistoryImmutable))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DesignTokens.Colors.primaryText)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }

            commandButton(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceRecordOccurrence), command: command(named: .recordOccurrence))
            commandButton(BundledLocalizationCatalogV1.v30Text(.advancedRecurrencePreviewOccurrenceWindow), command: command(named: .previewGeneration))
            commandButton(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceGenerateOccurrencePlan), command: command(named: .generate))
        }
        .accessibilityElement(children: .contain)
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceBoundariesHeading), identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceBoundariesDescription))
            Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceReceiptDescription))
            if reduceMotion {
                Text(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceReduceMotionDescription))
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
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceCommandHint))
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text(BundledLocalizationCatalogV1.v30AdvancedRecurrenceUnavailableCommand(title: title))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeading(_ title: String, identifier: String) -> some View {
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
        operationMessage = BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceSubmittingCommand)
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
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceCancelled)
                    return
                }
                operationMessage = outcomeText(outcome)
                onOutcome?(outcome)
            } catch is CancellationError {
                operationMessage = BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceCancelled)
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceCommandNotCompleted)
            }
        }
    }

    private func outcomeText(_ outcome: AdvancedRecurrenceWorkflowOutcomeV1) -> String {
        switch outcome {
        case .projected:
            return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceExceptionPreviewComplete)
        case .generationPreview:
            return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceOccurrencePreviewComplete)
        case .exceptionCommitted:
            return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceExceptionReceipt)
        case .occurrenceRecorded:
            return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceMutationReceipt)
        case let .occurrencesGenerated(receipt):
            return receipt == nil
                ? BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceGenerationNoReceipt)
                : BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceGenerationReceipt))
        case .remindersReconciled:
            return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceReminderReconciled)
        }
    }

    private func patternSummary(_ pattern: AdvancedRecurrenceAuthoringPatternV1) -> String {
        switch pattern {
        case let .daily(interval): return BundledLocalizationCatalogV1.v30AdvancedRecurrenceDaily(interval: interval)
        case let .weekly(interval, weekdays):
            return BundledLocalizationCatalogV1.v30AdvancedRecurrenceWeekly(interval: interval, weekdays: weekdays.map { weekdayName($0) }.joined(separator: ", "))
        case let .calendarDay(interval, day, missingDayPolicy):
            return BundledLocalizationCatalogV1.v30AdvancedRecurrenceMonthlyDay(interval: interval, day: day, missingDayPolicy: display(missingDayPolicy.rawValue))
        case let .weekday(interval, ordinal, weekday):
            return BundledLocalizationCatalogV1.v30AdvancedRecurrenceMonthlyOrdinal(interval: interval, ordinal: display(ordinal.rawValue), weekday: weekdayName(weekday))
        case let .lastDay(interval): return BundledLocalizationCatalogV1.v30AdvancedRecurrenceMonthlyLastDay(interval: interval)
        }
    }

    private func nextRunSummary(_ entry: DueQueueEntryV1) -> String {
        let due = entry.effectiveDueAtUTC.map(dateTimeSummary) ?? BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceNoResolvedTime)
        return BundledLocalizationCatalogV1.v30AdvancedRecurrenceNextRun(state: display(entry.state.rawValue), due: due)
    }

    private func dateRangeSummary(_ range: ScheduleLocalDateRangeV1) -> String {
        BundledLocalizationCatalogV1.v30AdvancedRecurrenceDateRange(start: range.startsOn.canonicalString, end: range.endsOn.canonicalString)
    }

    private func dateTimeSummary(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func weekdayName(_ day: ScheduleWeekdayV1) -> String {
        switch day {
        case .sunday: return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceSunday)
        case .monday: return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceMonday)
        case .tuesday: return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceTuesday)
        case .wednesday: return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceWednesday)
        case .thursday: return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceThursday)
        case .friday: return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceFriday)
        case .saturday: return BundledLocalizationCatalogV1.v30Text(.advancedRecurrenceSaturday)
        }
    }

    private func display(_ rawValue: String) -> String {
        rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    }
}

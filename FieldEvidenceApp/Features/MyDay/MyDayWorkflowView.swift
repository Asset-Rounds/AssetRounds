import SwiftUI

/// A contained C41 My Day surface over projections and explicit coordinator
/// intents. It does not own routing, persistence, prioritization, or schedule
/// mutation.
@MainActor
struct MyDayWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c41.my-day.screen"
    static let eligibleWorkAccessibilityIdentifier = "v23.p04.c41.my-day.eligible-work"
    static let planOrderAccessibilityIdentifier = "v23.p04.c41.my-day.plan-order"
    static let readinessAccessibilityIdentifier = "v23.p04.c41.my-day.readiness"
    static let durationAccessibilityIdentifier = "v23.p04.c41.my-day.duration"
    static let startResumeAccessibilityIdentifier = "v23.p04.c41.my-day.start-resume"
    static let carryoverAccessibilityIdentifier = "v23.p04.c41.my-day.carryover"
    static let reconciliationAccessibilityIdentifier = "v23.p04.c41.my-day.reconciliation-boundaries"

    let eligibleReferences: [MyDayEligibleReferenceV1]
    let draft: MyDayPlanDraftV1?
    let summary: MyDaySummaryProjectionV1?
    let savePreview: MyDaySavePreviewV1?
    let carryoverPreview: MyDayCarryoverPreviewV1?
    let onSelectEligible: @MainActor (MyDayEligibleReferenceV1) -> Void
    let onMove: @MainActor (MyDayAccessibleMoveV1) -> Void
    let onRequestRoute: @MainActor (MyDayExistingRouteIntentV1) -> Void
    let onPreviewCarryover: @MainActor () -> Void
    let onRefreshSummary: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?
    @State private var editMode: EditMode = .inactive

    private enum FocusTarget: Hashable {
        case heading
        case plan
        case reconciliation
    }

    init(
        eligibleReferences: [MyDayEligibleReferenceV1],
        draft: MyDayPlanDraftV1?,
        summary: MyDaySummaryProjectionV1?,
        savePreview: MyDaySavePreviewV1? = nil,
        carryoverPreview: MyDayCarryoverPreviewV1? = nil,
        onSelectEligible: @escaping @MainActor (MyDayEligibleReferenceV1) -> Void,
        onMove: @escaping @MainActor (MyDayAccessibleMoveV1) -> Void,
        onRequestRoute: @escaping @MainActor (MyDayExistingRouteIntentV1) -> Void,
        onPreviewCarryover: @escaping @MainActor () -> Void,
        onRefreshSummary: @escaping @MainActor () -> Void
    ) {
        self.eligibleReferences = eligibleReferences
        self.draft = draft
        self.summary = summary
        self.savePreview = savePreview
        self.carryoverPreview = carryoverPreview
        self.onSelectEligible = onSelectEligible
        self.onMove = onMove
        self.onRequestRoute = onRequestRoute
        self.onPreviewCarryover = onPreviewCarryover
        self.onRefreshSummary = onRefreshSummary
    }

    var body: some View {
        List {
            Section {
                heading
            }
            .listRowBackground(DesignTokens.Colors.canvas)

            Section {
                eligibleWork
            } header: {
                sectionHeading("Eligible work", identifier: Self.eligibleWorkAccessibilityIdentifier)
            }

            Section {
                planAndOrder
            } header: {
                sectionHeading("Plan and manual order", identifier: Self.planOrderAccessibilityIdentifier)
            }

            Section {
                readinessAndDuration
            } header: {
                sectionHeading("Derived readiness and duration", identifier: Self.readinessAccessibilityIdentifier)
            }

            Section {
                startResume
            } header: {
                sectionHeading("Start or resume", identifier: Self.startResumeAccessibilityIdentifier)
            }

            Section {
                carryover
            } header: {
                sectionHeading("Explicit carryover", identifier: Self.carryoverAccessibilityIdentifier)
            }

            Section {
                reconciliationAndBoundaries
            } header: {
                sectionHeading("Reconciliation and boundaries", identifier: Self.reconciliationAccessibilityIdentifier)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.canvas)
        .navigationTitle("My Day")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .environment(\.editMode, $editMode)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = draft == nil ? .plan : .heading
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            Text("My Day")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("Plan supplied eligible work in a manual order. Due, readiness, duration, completion, cancellation, and reopen information remains derived from its canonical source.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var eligibleWork: some View {
        WorklightCard {
            if eligibleReferences.isEmpty {
                Text("No eligible work is supplied. This view does not search for, schedule, or create work.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Selecting an item asks the supplied coordinator to update a zero-write draft only. It does not save a plan or change due work.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(eligibleReferences, id: \.stableKey) { reference in
                    Button("Select \(referenceLabel(reference))") {
                        onSelectEligible(reference)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier("\(Self.eligibleWorkAccessibilityIdentifier).\(reference.stableKey)")
                    .accessibilityHint("Requests selection for a zero-write My Day draft.")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var planAndOrder: some View {
        if let draft {
            Text("Order is manual. Drag with Reorder enabled, or use Move up and Move down. Derived cues never change this order.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(editMode.isEditing ? "Finish reordering" : "Reorder plan") {
                editMode = editMode.isEditing ? .inactive : .active
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityHint("Enables manual drag reordering. Accessible move controls remain available.")

            ForEach(Array(draft.items.enumerated()), id: \.element.membershipID) { index, item in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text("\(index + 1). \(referenceLabel(item.reference))")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    Text(item.estimate.map(estimateText) ?? "No duration estimate supplied")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    HStack {
                        Button("Move up") {
                            onMove(.up(membershipID: item.membershipID))
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(index == 0)
                        .accessibilityIdentifier("\(Self.planOrderAccessibilityIdentifier).move-up.\(item.membershipID.uuidString.lowercased())")
                        Button("Move down") {
                            onMove(.down(membershipID: item.membershipID))
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(index == draft.items.count - 1)
                        .accessibilityIdentifier("\(Self.planOrderAccessibilityIdentifier).move-down.\(item.membershipID.uuidString.lowercased())")
                    }
                }
                .accessibilityElement(children: .contain)
            }
            .onMove(perform: requestMove)

            Text(savePreview?.zeroWrite == true
                 ? "A zero-write save preview is supplied. Saving remains a separate explicit coordinator action."
                 : "No save preview is supplied. This view makes no saved-plan claim.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("No plan draft is supplied. Planning remains needs-attention and automatic prioritization is not used.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .accessibilityFocused($accessibilityFocus, equals: .plan)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readinessAndDuration: some View {
        WorklightCard {
            if let summary {
                valueRow("Plan duration", value: summary.totalEstimatedMinutes.map { "\($0) minutes" } ?? "No total estimate")
                    .accessibilityIdentifier(Self.durationAccessibilityIdentifier)
                valueRow("Partial readiness", value: summary.hasPartialReadiness ? "Some supplied work is not ready" : "No partial readiness indicated")
                valueRow("Unresolved exceptions", value: "\(summary.unresolvedExceptionCount)")
                Text("Due and readiness cues are derived at the supplied evaluation time. They do not prioritize, schedule, or mutate work.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(summary.items, id: \.item.membershipID) { item in
                    Text("\(referenceLabel(item.item.reference)): \(dueCueText(item.dueCue)); \(readinessText(item.readiness)); \(item.estimate.map(estimateText) ?? "no duration estimate")")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No derived readiness or duration projection is supplied. No due-state or schedule claim is made.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Refresh derived cues", action: onRefreshSummary)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .keyboardShortcut("r", modifiers: [.command])
                .accessibilityHint("Requests a fresh derived projection. It does not save or reorder the plan.")
        }
        .accessibilityElement(children: .contain)
    }

    private var startResume: some View {
        WorklightCard {
            if let summary {
                let intents = summary.items.compactMap(\.routeIntent)
                if intents.isEmpty {
                    Text("No supplied item currently has an existing Start or Resume route intent.")
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                } else {
                    Text("Start and Resume request an existing route only. This view does not claim the route opened or that work began.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(intents, id: \.reference.stableKey) { intent in
                        Button("\(intent.action == .start ? "Start" : "Resume") \(referenceLabel(intent.reference))") {
                            onRequestRoute(intent)
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .accessibilityIdentifier("\(Self.startResumeAccessibilityIdentifier).\(intent.reference.stableKey)")
                        .accessibilityHint("Requests the supplied existing route. It does not start or resume work by itself.")
                    }
                }
            } else {
                Text("Start and Resume are unavailable until a supplied derived projection identifies an existing route intent.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var carryover: some View {
        WorklightCard {
            Text("Carryover is explicit and only uses supplied eligible memberships. It never moves unfinished work across a date or time zone automatically.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(carryoverPreview?.zeroWrite == true
                 ? "A zero-write carryover preview is supplied. Commit and recovery remain separate coordinator actions."
                 : "No carryover preview is supplied. No work has been carried forward.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Preview explicit carryover", action: onPreviewCarryover)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .keyboardShortcut("c", modifiers: [.command])
                .accessibilityHint("Requests a zero-write carryover preview. It does not carry work forward.")
        }
        .accessibilityElement(children: .contain)
    }

    private var reconciliationAndBoundaries: some View {
        WorklightCard {
            if let summary {
                ForEach(summary.items, id: \.item.membershipID) { item in
                    Text("\(referenceLabel(item.item.reference)): \(statusText(item.status)); source state \(sourceStateText(item.sourceState)).")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No reconciliation projection is supplied. Completion, cancellation, and reopen status is not inferred.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            Text("Completion, cancellation, and reopen are reconciled from existing canonical sources. This contained surface does not alter schedule truth, create a route engine, send notifications, dispatch work, or write telemetry.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($accessibilityFocus, equals: .reconciliation)
            Text("Stable labels support VoiceOver, Voice Control, Switch Control, keyboard use, and RTL layout. At Accessibility text sizes, content reflows without truncation; Reduce Motion adds no state-change animation.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.small
    }

    private func requestMove(from source: IndexSet, to destination: Int) {
        guard let draft,
              source.count == 1,
              let sourceIndex = source.first,
              draft.items.indices.contains(sourceIndex),
              destination >= 0,
              destination <= draft.items.count else { return }
        let requestedIndex = destination > sourceIndex ? destination - 1 : destination
        guard draft.items.indices.contains(requestedIndex), requestedIndex != sourceIndex else { return }
        onMove(.toIndex(membershipID: draft.items[sourceIndex].membershipID, index: requestedIndex))
    }

    private func sectionHeading(_ title: LocalizedStringKey, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func valueRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.body.weight(.semibold))
            Spacer(minLength: DesignTokens.Spacing.small)
            Text(value)
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func referenceLabel(_ reference: MyDayEligibleReferenceV1) -> String {
        switch reference {
        case .workPacket:
            return "Work packet"
        case .roundSession:
            return "Round session"
        case .scheduleOccurrence:
            return "Scheduled occurrence"
        case .resumableDraft:
            return "Resumable draft"
        }
    }

    private func estimateText(_ estimate: MyDayEstimateV1) -> String {
        "\(estimate.wholeMinutes) minute estimate"
    }

    private func dueCueText(_ cue: MyDayDueCueV1) -> String {
        cue.rawValue.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    private func readinessText(_ readiness: MyDayReadinessV1) -> String {
        readiness.rawValue.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    private func statusText(_ status: MyDayWorkflowItemStatusV1) -> String {
        status.rawValue.lowercased()
    }

    private func sourceStateText(_ state: MyDaySourceStateV1) -> String {
        state.rawValue.lowercased()
    }
}

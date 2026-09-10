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
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.myDayEligibleWorkHeading), identifier: Self.eligibleWorkAccessibilityIdentifier)
            }

            Section {
                planAndOrder
            } header: {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.myDayPlanOrderHeading), identifier: Self.planOrderAccessibilityIdentifier)
            }

            Section {
                readinessAndDuration
            } header: {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.myDayReadinessHeading), identifier: Self.readinessAccessibilityIdentifier)
            }

            Section {
                startResume
            } header: {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.myDayStartResumeHeading), identifier: Self.startResumeAccessibilityIdentifier)
            }

            Section {
                carryover
            } header: {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.myDayCarryoverHeading), identifier: Self.carryoverAccessibilityIdentifier)
            }

            Section {
                reconciliationAndBoundaries
            } header: {
                sectionHeading(BundledLocalizationCatalogV1.v30Text(.myDayReconciliationHeading), identifier: Self.reconciliationAccessibilityIdentifier)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.canvas)
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.myDayNavigationTitle))
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
            Text(BundledLocalizationCatalogV1.v30Text(.myDayHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.myDayHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var eligibleWork: some View {
        WorklightCard {
            if eligibleReferences.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.myDayNoEligibleWork))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.myDayEligibleWorkDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(eligibleReferences, id: \.stableKey) { reference in
                    Button(BundledLocalizationCatalogV1.v30MyDaySelectReference(reference: referenceLabel(reference))) {
                        onSelectEligible(reference)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier("\(Self.eligibleWorkAccessibilityIdentifier).\(reference.stableKey)")
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.myDaySelectHint))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var planAndOrder: some View {
        if let draft {
            Text(BundledLocalizationCatalogV1.v30Text(.myDayOrderDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(editMode.isEditing ? BundledLocalizationCatalogV1.v30Text(.myDayFinishReordering) : BundledLocalizationCatalogV1.v30Text(.myDayReorderPlan)) {
                editMode = editMode.isEditing ? .inactive : .active
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.myDayReorderHint))

            ForEach(Array(draft.items.enumerated()), id: \.element.membershipID) { index, item in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text("\(index + 1). \(referenceLabel(item.reference))")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    Text(item.estimate.map(estimateText) ?? BundledLocalizationCatalogV1.v30Text(.myDayNoDurationEstimate))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    HStack {
                        Button(BundledLocalizationCatalogV1.v30Text(.myDayMoveUp)) {
                            onMove(.up(membershipID: item.membershipID))
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(index == 0)
                        .accessibilityIdentifier("\(Self.planOrderAccessibilityIdentifier).move-up.\(item.membershipID.uuidString.lowercased())")
                        Button(BundledLocalizationCatalogV1.v30Text(.myDayMoveDown)) {
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
                 ? BundledLocalizationCatalogV1.v30Text(.myDaySavePreviewAvailable)
                 : BundledLocalizationCatalogV1.v30Text(.myDayNoSavePreview))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(BundledLocalizationCatalogV1.v30Text(.myDayNoPlanDraft))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .accessibilityFocused($accessibilityFocus, equals: .plan)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readinessAndDuration: some View {
        WorklightCard {
            if let summary {
                valueRow(BundledLocalizationCatalogV1.v30Text(.myDayPlanDuration), value: summary.totalEstimatedMinutes.map { BundledLocalizationCatalogV1.v30MyDayMinutes(minutes: $0) } ?? BundledLocalizationCatalogV1.v30Text(.myDayNoTotalEstimate))
                    .accessibilityIdentifier(Self.durationAccessibilityIdentifier)
                valueRow(BundledLocalizationCatalogV1.v30Text(.myDayPartialReadiness), value: summary.hasPartialReadiness ? BundledLocalizationCatalogV1.v30Text(.myDaySomeWorkNotReady) : BundledLocalizationCatalogV1.v30Text(.myDayNoPartialReadiness))
                valueRow(BundledLocalizationCatalogV1.v30Text(.myDayUnresolvedExceptions), value: "\(summary.unresolvedExceptionCount)")
                Text(BundledLocalizationCatalogV1.v30Text(.myDayReadinessDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(summary.items, id: \.item.membershipID) { item in
                    Text(BundledLocalizationCatalogV1.v30MyDayItemReadiness(reference: referenceLabel(item.item.reference), dueCue: dueCueText(item.dueCue), readiness: readinessText(item.readiness), estimate: item.estimate.map(estimateText) ?? BundledLocalizationCatalogV1.v30Text(.myDayNoDurationEstimateLowercase)))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.myDayNoReadinessProjection))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(BundledLocalizationCatalogV1.v30Text(.myDayRefreshCues), action: onRefreshSummary)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .keyboardShortcut("r", modifiers: [.command])
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.myDayRefreshHint))
        }
        .accessibilityElement(children: .contain)
    }

    private var startResume: some View {
        WorklightCard {
            if let summary {
                let intents = summary.items.compactMap(\.routeIntent)
                if intents.isEmpty {
                    Text(BundledLocalizationCatalogV1.v30Text(.myDayNoRouteIntent))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                } else {
                    Text(BundledLocalizationCatalogV1.v30Text(.myDayStartResumeDescription))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(intents, id: \.reference.stableKey) { intent in
                        Button(BundledLocalizationCatalogV1.v30MyDayRouteAction(action: intent.action == .start ? BundledLocalizationCatalogV1.v30Text(.myDayStart) : BundledLocalizationCatalogV1.v30Text(.myDayResume), reference: referenceLabel(intent.reference))) {
                            onRequestRoute(intent)
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .accessibilityIdentifier("\(Self.startResumeAccessibilityIdentifier).\(intent.reference.stableKey)")
                        .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.myDayRouteHint))
                    }
                }
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.myDayStartResumeUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var carryover: some View {
        WorklightCard {
            Text(BundledLocalizationCatalogV1.v30Text(.myDayCarryoverDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(carryoverPreview?.zeroWrite == true
                 ? BundledLocalizationCatalogV1.v30Text(.myDayCarryoverPreviewAvailable)
                 : BundledLocalizationCatalogV1.v30Text(.myDayNoCarryoverPreview))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(BundledLocalizationCatalogV1.v30Text(.myDayPreviewCarryover), action: onPreviewCarryover)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .keyboardShortcut("c", modifiers: [.command])
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.myDayCarryoverHint))
        }
        .accessibilityElement(children: .contain)
    }

    private var reconciliationAndBoundaries: some View {
        WorklightCard {
            if let summary {
                ForEach(summary.items, id: \.item.membershipID) { item in
                    Text(BundledLocalizationCatalogV1.v30MyDayReconciliationItem(reference: referenceLabel(item.item.reference), status: statusText(item.status), sourceState: sourceStateText(item.sourceState)))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.myDayNoReconciliationProjection))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            Text(BundledLocalizationCatalogV1.v30Text(.myDayReconciliationDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($accessibilityFocus, equals: .reconciliation)
            Text(BundledLocalizationCatalogV1.v30Text(.myDayAccessibilityDescription))
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

    private func sectionHeading(_ title: String, identifier: String) -> some View {
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
            return BundledLocalizationCatalogV1.v30Text(.myDayWorkPacket)
        case .roundSession:
            return BundledLocalizationCatalogV1.v30Text(.myDayRoundSession)
        case .scheduleOccurrence:
            return BundledLocalizationCatalogV1.v30Text(.myDayScheduledOccurrence)
        case .resumableDraft:
            return BundledLocalizationCatalogV1.v30Text(.myDayResumableDraft)
        }
    }

    private func estimateText(_ estimate: MyDayEstimateV1) -> String {
        BundledLocalizationCatalogV1.v30MyDayMinuteEstimate(minutes: estimate.wholeMinutes)
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

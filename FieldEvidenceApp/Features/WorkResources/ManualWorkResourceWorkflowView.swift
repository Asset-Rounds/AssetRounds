import SwiftUI

/// C36's renderer-neutral manual-resource surface. The caller supplies the
/// complete canonical draft and typed commands; editing or viewing here never
/// creates a stock movement, writer, catalog, or accounting record.
@MainActor
struct ManualWorkResourceWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c36.manual-work-resource.screen"
    static let draftAccessibilityIdentifier = "v23.p04.c36.manual-work-resource.draft"
    static let stockAccessibilityIdentifier = "v23.p04.c36.manual-work-resource.stock"
    static let outputAccessibilityIdentifier = "v23.p04.c36.manual-work-resource.output"
    static let statusAccessibilityIdentifier = "v23.p04.c36.manual-work-resource.status"

    let coordinator: ManualWorkResourceWorkflowCoordinatorV1
    let context: ManualWorkResourceWorkflowContextV1
    let commands: [ManualWorkResourceWorkflowCommandV1]
    let onOutcome: (@MainActor (ManualWorkResourceWorkflowOutcomeV1) -> Void)?

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
        coordinator: ManualWorkResourceWorkflowCoordinatorV1,
        context: ManualWorkResourceWorkflowContextV1,
        commands: [ManualWorkResourceWorkflowCommandV1] = [],
        onOutcome: (@MainActor (ManualWorkResourceWorkflowOutcomeV1) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.context = context
        self.commands = commands
        self.onOutcome = onOutcome
    }

    var body: some View {
        let projection = coordinator.projection(context: context)

        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                truthBoundary
                draftEntry(projection)
                stockActions(projection)
                deterministicOutput(projection)
                operatingBoundaries
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear { accessibilityFocus = .heading }
        .onChange(of: operationMessage) { _, _ in
            accessibilityFocus = .operationStatus
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.medium
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var truthBoundary: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceDraftBoundaryHeading), identifier: Self.draftAccessibilityIdentifier)
            Label(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceDraftDoesNotChangeStock), systemImage: "pencil.line")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceDraftBoundaryDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func draftEntry(_ projection: ManualWorkResourceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceManualEntryHeading), identifier: "\(Self.draftAccessibilityIdentifier).entry")
            if projection.hasDraft {
                valueRow(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceTime), value: durationText(projection.duration))
                materials(projection.materials)
                valueRow(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceDirectCost), value: directCostText(projection.directCost))
                valueRow(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceSaveReadiness), value: projection.canSaveManualEntry ? BundledLocalizationCatalogV1.v30Text(.manualWorkResourceDraftSupplied) : BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNoSaveableDraft))
                commandButton(
                    title: BundledLocalizationCatalogV1.v30Text(.manualWorkResourceSaveEntry),
                    command: command(named: .saveManual),
                    disabled: !projection.canSaveManualEntry
                )
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNoDraft))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .errorSummary)
            }
            operationStatus
        }
        .accessibilityElement(children: .contain)
    }

    private func materials(_ values: [ManualMaterialLineV1]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceMaterials))
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
            if values.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNoMaterials))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(values, id: \.lineID) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.description)
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        Text(BundledLocalizationCatalogV1.v30ManualWorkResourceQuantity(quantity: exactDecimal(line.quantity.mantissa, scale: line.quantity.scale), unit: line.unit ?? BundledLocalizationCatalogV1.v30Text(.manualWorkResourceUnits)))
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                        if let reference = line.localPartReference {
                            Text(BundledLocalizationCatalogV1.v30ManualWorkResourceFrozenPartReference(name: reference.displayName))
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceManualMaterialNoStockEffect))
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func stockActions(_ projection: ManualWorkResourceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockActionsHeading), identifier: Self.stockAccessibilityIdentifier)
            Text(stockCapabilityText(projection.stockCapability))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if projection.stockCapability == .available {
                Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockActionsDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.manualWorkResourceUseStock), command: command(named: .useFromStock))
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.manualWorkResourceReturnStock), command: command(named: .returnToStock))
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNoStockCapabilityDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func deterministicOutput(_ projection: ManualWorkResourceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceOutputHeading), identifier: Self.outputAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceOutputDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceOutputBoundary))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockChanged), value: projection.stockChanged ? BundledLocalizationCatalogV1.v30Text(.manualWorkResourceRecorded) : BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNotClaimed))
            valueRow(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceSaved), value: projection.saved ? BundledLocalizationCatalogV1.v30Text(.manualWorkResourceRecorded) : BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNotClaimed))
        }
        .accessibilityElement(children: .contain)
    }

    private var operatingBoundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceBoundariesHeading), identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceBoundariesDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    @ViewBuilder
    private func commandButton(
        title: String,
        command: ManualWorkResourceWorkflowCommandV1?,
        disabled: Bool = false
    ) -> some View {
        if let command {
            Button(title) { perform(command) }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(disabled || isPerforming)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.manualWorkResourceCommandHint))
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text(BundledLocalizationCatalogV1.v30ManualWorkResourceUnavailableCommand(title: title))
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

    private func durationText(_ duration: ManualDurationV1?) -> String {
        guard let duration else { return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNoTime) }
        return BundledLocalizationCatalogV1.v30ManualWorkResourceMinutes(minutes: duration.minutes)
    }

    private func directCostText(_ directCost: DirectCostEntryV1?) -> String {
        guard let directCost else { return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceNoDirectCost) }
        let amount = directCost.amount
        return "\(amount.currencyCode) \(exactDecimal(amount.mantissa, scale: amount.minorUnitScale))"
    }

    private func exactDecimal(_ mantissa: Int64, scale: Int) -> String {
        let digits = String(mantissa)
        guard scale > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, scale - digits.count + 1)) + digits
        let split = padded.index(padded.endIndex, offsetBy: -scale)
        return String(padded[..<split]) + "." + String(padded[split...])
    }

    private func stockCapabilityText(_ capability: ManualWorkResourceStockCapabilityV1) -> String {
        switch capability {
        case .available:
            return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockAvailable)
        case .disabled:
            return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockDisabled)
        case .unavailable:
            return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockUnavailable)
        case .manualOnly:
            return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceManualOnly)
        }
    }

    private enum CommandName {
        case saveManual
        case useFromStock
        case returnToStock
    }

    private func command(named name: CommandName) -> ManualWorkResourceWorkflowCommandV1? {
        commands.first { command in
            switch (name, command) {
            case (.saveManual, .saveManual(_)),
                 (.useFromStock, .useFromStock(_)),
                 (.returnToStock, .returnToStock(_)):
                return true
            default:
                return false
            }
        }
    }

    private func commandIdentifier(_ command: ManualWorkResourceWorkflowCommandV1) -> String {
        switch command {
        case .saveManual(_): return "save-manual"
        case .useFromStock(_): return "use-stock"
        case .returnToStock(_): return "return-stock"
        }
    }

    private func perform(_ command: ManualWorkResourceWorkflowCommandV1) {
        guard !isPerforming else { return }
        isPerforming = true
        operationMessage = BundledLocalizationCatalogV1.v30Text(.manualWorkResourceSubmittingCommand)
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let outcome = try coordinator.execute(command, context: context)
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.manualWorkResourceCancelled)
                    return
                }
                operationMessage = outcomeText(outcome)
                onOutcome?(outcome)
            } catch is CancellationError {
                operationMessage = BundledLocalizationCatalogV1.v30Text(.manualWorkResourceCancelled)
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.manualWorkResourceCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.manualWorkResourceCommandNotCompleted)
            }
        }
    }

    private func outcomeText(_ outcome: ManualWorkResourceWorkflowOutcomeV1) -> String {
        switch outcome {
        case .manualSaved:
            return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceManualSaved)
        case .stockUsed:
            return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockUsed)
        case .stockReturned:
            return BundledLocalizationCatalogV1.v30Text(.manualWorkResourceStockReturned)
        }
    }
}

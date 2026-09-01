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
        .navigationTitle("Work resources")
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
            Text("Manual work resources")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("Review a supplied manual time, material, quantity, and direct-cost entry before an explicit canonical action.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var truthBoundary: some View {
        WorklightCard {
            sectionHeading("Draft and stock boundary", identifier: Self.draftAccessibilityIdentifier)
            Label("Editing a draft never changes stock.", systemImage: "pencil.line")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("A stock movement is attempted only by the explicit Use from stock or Return to stock action. A saved entry or stock movement is shown only after its durable receipt returns.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func draftEntry(_ projection: ManualWorkResourceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Manual entry", identifier: "\(Self.draftAccessibilityIdentifier).entry")
            if projection.hasDraft {
                valueRow("Time", value: durationText(projection.duration))
                materials(projection.materials)
                valueRow("Direct cost", value: directCostText(projection.directCost))
                valueRow("Save readiness", value: projection.canSaveManualEntry ? "Draft supplied" : "No saveable draft")
                commandButton(
                    title: "Save manual entry",
                    command: command(named: .saveManual),
                    disabled: !projection.canSaveManualEntry
                )
            } else {
                Text("No manual entry draft was supplied. No record can be saved from this surface.")
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
            Text("Materials")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
            if values.isEmpty {
                Text("No material lines supplied.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                ForEach(values, id: \.lineID) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.description)
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        Text("\(exactDecimal(line.quantity.mantissa, scale: line.quantity.scale)) \(line.unit ?? "units")")
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                        if let reference = line.localPartReference {
                            Text("Frozen part reference: \(reference.displayName)")
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Manual material line; no stock effect.")
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
            sectionHeading("Optional stock actions", identifier: Self.stockAccessibilityIdentifier)
            Text(stockCapabilityText(projection.stockCapability))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if projection.stockCapability == .available {
                Text("Use and Return require the supplied exact stock command. Return is linked to its accepted Use and cannot restore more than its remaining quantity.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: "Use from stock", command: command(named: .useFromStock))
                commandButton(title: "Return to stock", command: command(named: .returnToStock))
            } else {
                Text("Manual time, material, quantity, and direct-cost entry remains usable without stock capability.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func deterministicOutput(_ projection: ManualWorkResourceWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Deterministic output", identifier: Self.outputAccessibilityIdentifier)
            Text("The output projects the supplied canonical manual record. Compatible values are shown exactly; mixed units or currencies are not silently totalled.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("This is not a timer, inventory balance, invoice, tax, payroll, estimate, price authority, or accounting result.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow("Stock changed", value: projection.stockChanged ? "Recorded" : "Not claimed")
            valueRow("Saved", value: projection.saved ? "Recorded" : "Not claimed")
        }
        .accessibilityElement(children: .contain)
    }

    private var operatingBoundaries: some View {
        WorklightCard {
            sectionHeading("Operating boundaries", identifier: "\(Self.screenAccessibilityIdentifier).boundaries")
            Text("If a command is interrupted or rejected, reload the canonical record before retrying. This screen never infers a partial save or stock effect.")
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
                .accessibilityHint("Uses the supplied canonical manual-resource command.")
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text("\(title) is unavailable until its canonical command is supplied.")
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
        guard let duration else { return "No manual time" }
        return "\(duration.minutes) minute\(duration.minutes == 1 ? "" : "s")"
    }

    private func directCostText(_ directCost: DirectCostEntryV1?) -> String {
        guard let directCost else { return "No direct cost" }
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
            return "Stock capability is available for explicit, supplied actions."
        case .disabled:
            return "Stock capability is disabled. No stock action can be performed."
        case .unavailable:
            return "Stock capability is unavailable. No stock action can be performed."
        case .manualOnly:
            return "This workflow is manual-only. No stock action can be performed."
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
        operationMessage = "Submitting the supplied manual-resource command…"
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let outcome = try coordinator.execute(command, context: context)
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
                    return
                }
                operationMessage = outcomeText(outcome)
                onOutcome?(outcome)
            } catch is CancellationError {
                operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
                    return
                }
                operationMessage = "The supplied command was not completed. The current canonical record remains the source of truth."
            }
        }
    }

    private func outcomeText(_ outcome: ManualWorkResourceWorkflowOutcomeV1) -> String {
        switch outcome {
        case .manualSaved:
            return "The manual entry has a durable receipt. Reload the canonical record to show its current state."
        case .stockUsed:
            return "The explicit stock use and its frozen work-material successor have durable receipts. Reload the canonical record to show their current state."
        case .stockReturned:
            return "The explicit stock return and its work-material successor have durable receipts. Reload the canonical record to show their current state."
        }
    }
}

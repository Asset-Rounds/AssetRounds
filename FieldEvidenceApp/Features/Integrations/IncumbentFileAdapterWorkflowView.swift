import SwiftUI

/// C37's Data & Portability surface. It consumes the bounded C50/C08 workflow
/// only; it neither selects an incumbent profile nor creates a file, import,
/// provider connection, writer, or durable adapter state.
@MainActor
struct IncumbentFileAdapterWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c37.incumbent-adapter.screen"
    static let availabilityAccessibilityIdentifier = "v23.p04.c37.incumbent-adapter.availability"
    static let mappingAccessibilityIdentifier = "v23.p04.c37.incumbent-adapter.mapping"
    static let outputAccessibilityIdentifier = "v23.p04.c37.incumbent-adapter.output"
    static let statusAccessibilityIdentifier = "v23.p04.c37.incumbent-adapter.status"

    let coordinator: IncumbentFileAdapterWorkflowCoordinatorV1
    let context: IncumbentFileAdapterWorkflowContextV1
    let commands: [IncumbentFileAdapterWorkflowCommandV1]
    let onOutcome: (@MainActor (IncumbentFileAdapterWorkflowOutcomeV1) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var inboundPreview: IncumbentFileAdapterInboundPreviewV1?
    @State private var canonicalPreview: IncumbentFileAdapterC08ReentryV1?
    @State private var operationMessage: String?
    @State private var isPerforming = false
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum FocusTarget: Hashable {
        case heading
        case availability
        case error
        case operationStatus
    }

    init(
        coordinator: IncumbentFileAdapterWorkflowCoordinatorV1,
        context: IncumbentFileAdapterWorkflowContextV1,
        commands: [IncumbentFileAdapterWorkflowCommandV1] = [],
        onOutcome: (@MainActor (IncumbentFileAdapterWorkflowOutcomeV1) -> Void)? = nil
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
                    availability(projection)
                    if projection.state == .enabledExactProductionProfile {
                        selectedProfile(projection)
                        mappingAndDryRun(projection)
                        explicitExchangeActions(projection)
                    }
                    truthBoundary(projection)
                    operationStatus
                } else {
                    unavailableContext
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = projection?.state == .disabledNoSelectedProfile ? .availability : .heading
        }
        .onChange(of: operationMessage) { _, _ in
            accessibilityFocus = .operationStatus
        }
    }

    private var projection: IncumbentFileAdapterWorkflowProjectionV1? {
        try? coordinator.projection(context: context)
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.medium
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func availability(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterAvailabilityHeading), identifier: Self.availabilityAccessibilityIdentifier)
            switch projection.state {
            case .disabledNoSelectedProfile:
                Label(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNoProfile), systemImage: "nosign")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .availability)
                Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNoProfileDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .enabledExactProductionProfile:
                Label(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterProfileAvailable), systemImage: "checkmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterProfileAvailableDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func selectedProfile(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterProfileHeading), identifier: "\(Self.availabilityAccessibilityIdentifier).profile")
            valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterProfileToken), value: projection.providerDisplayToken ?? BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterUnavailable))
            valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterReleaseIdentity), value: shortDigest(projection.selectedReleaseSHA256))
            Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterProfileDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func mappingAndDryRun(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterMappingHeading), identifier: Self.mappingAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterMappingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let inboundPreview {
                valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPreviewRows), value: "\(inboundPreview.mapping.rowCount)")
                valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterIncludedFields), value: fieldList(inboundPreview.mapping.includedFields))
                valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterOmittedFields), value: fieldList(inboundPreview.mapping.omittedFields))
                valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterUnresolvedKeys), value: "\(inboundPreview.mapping.unresolvedStableKeys.count)")
                Text(inboundPreview.isZeroWrite
                     ? BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPreviewZeroWrites)
                     : BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPreviewNoDisposition))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNoFilePreview))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            if let canonicalPreview {
                Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCanonicalPreviewReady))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterBulkPlan), value: shortDigest(canonicalPreview.preview.bulkPlan.planSHA256))
            }
            if projection.canDetectParseOrMap {
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPreviewSuppliedFile), command: command(named: .previewInbound))
            }
            if projection.canPreviewCanonicalImport {
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPreviewCanonicalImport), command: command(named: .previewCanonicalImport))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func explicitExchangeActions(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterActionsHeading), identifier: Self.outputAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterActionsDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if projection.canCommitCanonicalImport {
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterBeginCanonicalImport), command: command(named: .beginCanonicalImport))
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCommitOrCancelCanonicalImport), command: command(named: .commitOrCancelCanonicalImport))
            }
            if projection.canExport {
                Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterExportDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPrepareExport), command: command(named: .export))
            }
            commandButton(title: BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterRecoverExchange), command: command(named: .recover))
        }
        .accessibilityElement(children: .contain)
    }

    private func truthBoundary(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterTruthBoundaryHeading), identifier: "\(Self.screenAccessibilityIdentifier).truth")
            Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterTruthBoundaryDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPreviewWritesState), value: projection.previewWritesCanonicalState ? BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterClaimed) : BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNo))
            valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterExportMeansSynced), value: projection.fileCreatedMeansSynced ? BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterClaimed) : BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNo))
            valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterExportMeansDelivered), value: projection.fileCreatedMeansDelivered ? BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterClaimed) : BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNo))
            valueRow(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterPreviewMeansImported), value: projection.previewMeansImported ? BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterClaimed) : BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNo))
        }
        .accessibilityElement(children: .contain)
    }

    private var unavailableContext: some View {
        WorklightCard {
            Label(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterUnavailableContext), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterUnavailableContextDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($accessibilityFocus, equals: .error)
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
        command: IncumbentFileAdapterWorkflowCommandV1?
    ) -> some View {
        if let command {
            Button(title) { perform(command) }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isPerforming)
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCommandHint))
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text(BundledLocalizationCatalogV1.v30IncumbentFileAdapterUnavailableCommand(title: title))
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

    private func fieldList(_ fields: [IncumbentCanonicalFieldV1]) -> String {
        guard !fields.isEmpty else { return BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterNone) }
        return fields.map(\.rawValue).joined(separator: ", ")
    }

    private func shortDigest(_ digest: String?) -> String {
        guard let digest, digest.count >= 12 else { return BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterUnavailable) }
        return String(digest.prefix(12)) + "…"
    }

    private enum CommandName {
        case previewInbound
        case previewCanonicalImport
        case beginCanonicalImport
        case commitOrCancelCanonicalImport
        case export
        case recover
    }

    private func command(named name: CommandName) -> IncumbentFileAdapterWorkflowCommandV1? {
        commands.first { command in
            switch (name, command) {
            case (.previewInbound, .previewInbound(_, _, _)),
                 (.previewCanonicalImport, .previewCanonicalImport(_)),
                 (.beginCanonicalImport, .beginCanonicalImport(_)),
                 (.commitOrCancelCanonicalImport, .commitOrCancelCanonicalImport(_)),
                 (.export, .export(_, _, _)),
                 (.recover, .recover(_, _, _, _, _, _)):
                return true
            default:
                return false
            }
        }
    }

    private func commandIdentifier(_ command: IncumbentFileAdapterWorkflowCommandV1) -> String {
        switch command {
        case .previewInbound(_, _, _): return "preview-inbound"
        case .previewCanonicalImport(_): return "preview-canonical-import"
        case .beginCanonicalImport(_): return "begin-canonical-import"
        case .commitOrCancelCanonicalImport(_): return "commit-or-cancel-canonical-import"
        case .export(_, _, _): return "prepare-export-bytes"
        case .recover(_, _, _, _, _, _): return "recover"
        }
    }

    private func perform(_ command: IncumbentFileAdapterWorkflowCommandV1) {
        guard !isPerforming else { return }
        isPerforming = true
        operationMessage = BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterSubmittingCommand)
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let outcome = try coordinator.execute(command)
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCancelled)
                    return
                }
                record(outcome)
                operationMessage = outcomeText(outcome, command: command)
                onOutcome?(outcome)
            } catch is CancellationError {
                operationMessage = BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCancelled)
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCancelled)
                    return
                }
                operationMessage = BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCommandNotCompleted)
            }
        }
    }

    private func record(_ outcome: IncumbentFileAdapterWorkflowOutcomeV1) {
        switch outcome {
        case let .inboundPreview(value):
            inboundPreview = value
        case let .canonicalPreview(value):
            canonicalPreview = value
        case .canonicalSession(_), .exported(_, _), .recovered(_):
            break
        }
    }

    private func outcomeText(
        _ outcome: IncumbentFileAdapterWorkflowOutcomeV1,
        command: IncumbentFileAdapterWorkflowCommandV1
    ) -> String {
        switch outcome {
        case .inboundPreview:
            return BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterMappingPreviewComplete)
        case .canonicalPreview:
            return BundledLocalizationCatalogV1.v30Text(.incumbentFileAdapterCanonicalPreviewComplete)
        case let .canonicalSession(session):
            if case .beginCanonicalImport(_) = command {
                return BundledLocalizationCatalogV1.v30IncumbentFileAdapterSessionRecorded(state: session.state.rawValue)
            }
            return BundledLocalizationCatalogV1.v30IncumbentFileAdapterSessionCurrent(state: session.state.rawValue)
        case let .exported(data, _):
            return BundledLocalizationCatalogV1.v30IncumbentFileAdapterExportPrepared(byteCount: data.count)
        case let .recovered(receipt):
            return BundledLocalizationCatalogV1.v30IncumbentFileAdapterRecoveryComplete(disposition: receipt.disposition.rawValue)
        }
    }
}

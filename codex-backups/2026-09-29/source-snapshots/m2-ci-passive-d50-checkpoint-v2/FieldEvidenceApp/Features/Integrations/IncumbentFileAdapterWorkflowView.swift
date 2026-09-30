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
        .navigationTitle("Data & Portability")
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
            Text("Data & Portability")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("A bounded local file adapter is available only when one exact profile is configured and proven.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func availability(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Adapter availability", identifier: Self.availabilityAccessibilityIdentifier)
            switch projection.state {
            case .disabledNoSelectedProfile:
                Label("No adapter profile is configured or proven.", systemImage: "nosign")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .availability)
                Text("File selection, import preview, import commit, export, and recovery actions are unavailable. This is a truthful disabled state, not a setup prompt.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .enabledExactProductionProfile:
                Label("One exact production profile is available.", systemImage: "checkmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Provider mechanics remain secondary. Every action below requires a supplied, exact canonical command.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func selectedProfile(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Exact profile", identifier: "\(Self.availabilityAccessibilityIdentifier).profile")
            valueRow("Profile token", value: projection.providerDisplayToken ?? "Unavailable")
            valueRow("Release identity", value: shortDigest(projection.selectedReleaseSHA256))
            Text("This token identifies the configured profile only. It does not establish a provider account, connection, acceptance, delivery, security, or success.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func mappingAndDryRun(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Mapping and dry run", identifier: Self.mappingAccessibilityIdentifier)
            Text("Detection, parsing, and mapping are deterministic preview work. Preview makes zero canonical writes and does not mean imported.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let inboundPreview {
                valueRow("Preview rows", value: "\(inboundPreview.mapping.rowCount)")
                valueRow("Included fields", value: fieldList(inboundPreview.mapping.includedFields))
                valueRow("Omitted fields", value: fieldList(inboundPreview.mapping.omittedFields))
                valueRow("Unresolved keys", value: "\(inboundPreview.mapping.unresolvedStableKeys.count)")
                Text(inboundPreview.isZeroWrite
                     ? "This preview made zero canonical writes."
                     : "No canonical write disposition is claimed.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            } else {
                Text("No supplied file has been previewed from this surface.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            if let canonicalPreview {
                Text("The C08 canonical-import preview is ready for an explicit begin or commit/cancel command. It is still not an import result.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                valueRow("Bulk plan", value: shortDigest(canonicalPreview.preview.bulkPlan.planSHA256))
            }
            if projection.canDetectParseOrMap {
                commandButton(title: "Preview supplied file", command: command(named: .previewInbound))
            }
            if projection.canPreviewCanonicalImport {
                commandButton(title: "Preview canonical import", command: command(named: .previewCanonicalImport))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func explicitExchangeActions(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Explicit exchange actions", identifier: Self.outputAccessibilityIdentifier)
            Text("Canonical import needs the supplied C08 re-entry, session, revision, and source identity. It is never inferred from a file preview.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if projection.canCommitCanonicalImport {
                commandButton(title: "Begin canonical import", command: command(named: .beginCanonicalImport))
                commandButton(title: "Commit or cancel canonical import", command: command(named: .commitOrCancelCanonicalImport))
            }
            if projection.canExport {
                Text("An export result prepares deterministic export bytes and a manifest locally. It never means synced, accepted, ordered, delivered, read, or processed by a provider.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                commandButton(title: "Prepare deterministic export bytes", command: command(named: .export))
            }
            commandButton(title: "Recover supplied exchange", command: command(named: .recover))
        }
        .accessibilityElement(children: .contain)
    }

    private func truthBoundary(_ projection: IncumbentFileAdapterWorkflowProjectionV1) -> some View {
        WorklightCard {
            sectionHeading("Truth boundary", identifier: "\(Self.screenAccessibilityIdentifier).truth")
            Text("No adapter profile is selected automatically, and no command here browses a provider, creates an account, opens a network connection, or claims a provider result.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            valueRow("Preview writes canonical state", value: projection.previewWritesCanonicalState ? "Claimed" : "No")
            valueRow("Prepared export means synced", value: projection.fileCreatedMeansSynced ? "Claimed" : "No")
            valueRow("Prepared export means delivered", value: projection.fileCreatedMeansDelivered ? "Claimed" : "No")
            valueRow("Preview means imported", value: projection.previewMeansImported ? "Claimed" : "No")
        }
        .accessibilityElement(children: .contain)
    }

    private var unavailableContext: some View {
        WorklightCard {
            Label("Data & Portability is unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.blockedText)
                .accessibilityAddTraits(.isHeader)
            Text("The current adapter context could not be validated. No import, export-byte preparation, or provider action is available.")
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
                .accessibilityHint("Uses the supplied exact file-adapter command.")
                .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).command.\(commandIdentifier(command))")
        } else {
            Text("\(title) is unavailable until its exact canonical command is supplied.")
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
        guard !fields.isEmpty else { return "None" }
        return fields.map(\.rawValue).joined(separator: ", ")
    }

    private func shortDigest(_ digest: String?) -> String {
        guard let digest, digest.count >= 12 else { return "Unavailable" }
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
        operationMessage = "Submitting the supplied file-adapter command…"
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let outcome = try coordinator.execute(command)
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
                    return
                }
                record(outcome)
                operationMessage = outcomeText(outcome, command: command)
                onOutcome?(outcome)
            } catch is CancellationError {
                operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
            } catch {
                guard !Task.isCancelled else {
                    operationMessage = "The request was cancelled. Reload the canonical record before retrying; no effect is claimed."
                    return
                }
                operationMessage = "The supplied command was not completed. No file, import, sync, delivery, or provider result is claimed."
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
            return "The deterministic mapping preview completed with zero canonical writes. It is not an import."
        case .canonicalPreview:
            return "The C08 canonical-import preview completed with zero canonical writes. An explicit later command is still required."
        case let .canonicalSession(session):
            if case .beginCanonicalImport(_) = command {
                return "The canonical-import session is recorded as \(session.state.rawValue). No import result is inferred."
            }
            return "The canonical-import session is now \(session.state.rawValue). Read the canonical record before claiming an import result."
        case let .exported(data, _):
            return "Deterministic export bytes and a manifest were prepared locally (\(data.count) byte(s)). This is not a sync, delivery, acceptance, order, or provider result."
        case let .recovered(receipt):
            return "Recovery completed with \(receipt.disposition.rawValue). It does not create a provider, delivery, or security claim."
        }
    }
}

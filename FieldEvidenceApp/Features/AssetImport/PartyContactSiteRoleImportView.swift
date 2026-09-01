import SwiftUI

/// Pre-S10 review surface for the C32 Party/contact/Site-role import.
///
/// The prepared artifact is already source-bound by the application layer. This
/// view only presents that binding, asks the incumbent coordinator for a
/// zero-write preview, and requires an explicit session start and commit. It
/// never parses or renders contact values and is intentionally not adopted by
/// the application shell until the reserved S10 boundary is accepted.
@MainActor
struct PartyContactSiteRoleImportView: View {
    static let activationEnabled = false
    static let adoptionEnabled = false
    static let acceptanceEnabled = false
    static let nativeEnabled = false
    static let hostedEnabled = false
    static let releaseEnabled = false
    static let uiAdoptionClaimed = false

    static let screenAccessibilityIdentifier = "v23.p04.c32.import.screen"
    static let headingAccessibilityIdentifier =
        "v23.p04.c32.import.heading"
    static let sourceManifestAccessibilityIdentifier =
        "v23.p04.c32.import.source-manifest"
    static let sourceFileAccessibilityIdentifierPrefix =
        "v23.p04.c32.import.source-file."
    static let bindingAccessibilityIdentifier =
        "v23.p04.c32.import.exact-binding"
    static let diagnosticsAccessibilityIdentifier =
        "v23.p04.c32.import.diagnostics"
    static let diagnosticAccessibilityIdentifierPrefix =
        "v23.p04.c32.import.diagnostic."
    static let previewAccessibilityIdentifier =
        "v23.p04.c32.import.preview"
    static let statusAccessibilityIdentifier =
        "v23.p04.c32.import.status"
    static let errorAccessibilityIdentifier =
        "v23.p04.c32.import.error"
    static let beginAccessibilityIdentifier =
        "v23.p04.c32.import.action.begin"
    static let commitAccessibilityIdentifier =
        "v23.p04.c32.import.action.commit"
    static let retryAccessibilityIdentifier =
        "v23.p04.c32.import.action.retry"
    static let cancelAccessibilityIdentifier =
        "v23.p04.c32.import.action.cancel"
    static let cleanupAccessibilityIdentifier =
        "v23.p04.c32.import.action.cleanup"
    static let boundaryAccessibilityIdentifier =
        "v23.p04.c32.import.truth-boundary"

    static let truthBoundaryText =
        "Preview only means that no canonical state has been written. A commit is explicit and uses one synthetic aggregate row and one canonical workspace command."
    static let contactSafeDiagnosticsText =
        "Contact-safe diagnostics show source metadata, row numbers, dispositions, and reason codes. Contact values are never rendered here."

    let coordinator: PartyContactSiteRoleImportCoordinatorV1
    let prepared: PartyContactSiteRoleImportPreparedV1
    let currentSourceSHA256: String
    let currentWorkspaceRevisionSHA256: String
    let sessionID: UUID
    let initialSession: BulkSessionV1?
    let onCancel: (@MainActor () -> Void)?
    let onCompletion: (@MainActor (BulkSessionV1) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var preview: ImportBulkPreviewV1?
    @State private var session: BulkSessionV1?
    @State private var phase: Phase = .loading
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var cleanupPending = false
    @State private var retryTarget: RetryTarget = .preview
    @State private var actionTask: Task<Void, Never>?
    @State private var didFinish = false
    @State private var cancellationRequested = false
    @State private var didNotifyCompletion = false
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum Phase: Equatable {
        case loading
        case beginning
        case previewReady
        case sessionReady
        case committing
        case cleaningUp
        case cancelling
        case completed
        case cancelled
        case failed
    }

    private enum RetryTarget: Equatable {
        case preview
        case begin
        case commit
        case cancel
        case cleanup
    }

    private enum FocusTarget: Hashable {
        case heading
        case firstIssue
        case status
        case error
    }

    private enum DiagnosticSeverity: Equatable {
        case information
        case warning
        case error

        var label: String {
            switch self {
            case .information: "Information"
            case .warning: "Warning"
            case .error: "Error"
            }
        }

        var iconName: String {
            switch self {
            case .information: "info.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }

        var color: Color {
            switch self {
            case .information: DesignTokens.Colors.informationText
            case .warning: DesignTokens.Colors.attentionText
            case .error: DesignTokens.Colors.blockedText
            }
        }
    }

    private enum Copy {
        static let heading = "Party, contact, and Site-role import"
        static let disclosure =
            "Review the exact selected files and deterministic outcomes before any canonical write."
        static let sources = "Selected source files"
        static let sourcesOrder =
            "The source order is fixed: parties, operational contacts, then Site roles."
        static let sourceSelection =
            "This prepared selection is immutable. Replacing a source requires a new prepared artifact."
        static let binding = "Exact import binding"
        static let bindingDisclosure =
            "These digests bind the source manifest, source rows, workspace revision, import plan, and synthetic command."
        static let diagnostics = "Grouped outcomes and diagnostics"
        static let diagnosticDisclosure =
            "Every diagnostic is identified by group, row number, disposition, and a stable reason code."
        static let noDiagnostics = "No source-row diagnostics were reported."
        static let preview = "Validated zero-write preview"
        static let previewPending = "Validating the prepared preview…"
        static let previewFailure =
            "The preview could not be validated. No canonical write occurs during preview."
        static let previewNoReceipt =
            "Preview does not claim a saved receipt, completion, rollback, or export."
        static let syntheticRow = "Synthetic aggregate row"
        static let canonicalTarget = "Target: nil (aggregate command)"
        static let begin = "Start import session"
        static let beginDisclosure =
            "Starting a session records resumable import progress; it does not write canonical Party, contact, or Site-role state."
        static let commit = "Commit import"
        static let commitDisclosure =
            "Commit is explicit and delegates one all-or-nothing canonical workspace command to the incumbent writer."
        static let retryPreview = "Retry preview validation"
        static let retryBegin = "Retry session start"
        static let retryCommit = "Retry commit or resume"
        static let retryCancel = "Retry cancellation and cleanup"
        static let retryCleanup = "Retry temporary-source cleanup"
        static let cancel = "Cancel import"
        static let cancelled =
            "Import cancelled. Temporary source material was discarded when cleanup was confirmed."
        static let cancelledBoundary =
            "Cancellation makes no completion claim and does not write canonical state."
        static let completed =
            "Import committed and the durable completion receipt was confirmed."
        static let completedCleanupPending =
            "Import committed and its durable receipt was confirmed. Temporary-source cleanup still needs confirmation."
        static let sessionReady =
            "The resumable session is ready. Review again, then explicitly commit."
        static let beginning = "Recording the resumable import session…"
        static let committing = "Committing or resuming the exact aggregate command…"
        static let cancelling = "Cancelling the session and discarding temporary source material…"
        static let cleanupComplete = "Temporary source material was discarded."
        static let genericFailure =
            "The result could not be confirmed. Review the durable session and retry; no contact values are shown here."
        static let retryDisclosure =
            "Retry uses the same prepared binding and does not infer success from an unconfirmed result."
        static let done = "Done"
        static let close = "Close"
        static let reducedMotion =
            "Motion is reduced; state changes remain available as text."
    }

    init(
        coordinator: PartyContactSiteRoleImportCoordinatorV1,
        prepared: PartyContactSiteRoleImportPreparedV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String,
        sessionID: UUID = UUID(),
        initialSession: BulkSessionV1? = nil,
        onCancel: (@MainActor () -> Void)? = nil,
        onCompletion: (@MainActor (BulkSessionV1) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.prepared = prepared
        self.currentSourceSHA256 = currentSourceSHA256
        self.currentWorkspaceRevisionSHA256 = currentWorkspaceRevisionSHA256
        self.sessionID = initialSession?.sessionID ?? sessionID
        self.initialSession = initialSession
        self.onCancel = onCancel
        self.onCompletion = onCompletion
        _session = State(initialValue: initialSession)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                truthBoundary
                sourceManifestCard
                bindingCard
                diagnosticsCard
                previewCard
                statusCards
                actionCard
            }
            .padding(DesignTokens.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Copy.heading)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .environment(\.layoutDirection, layoutDirection)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Copy.cancel, role: .cancel) {
                    cancelImport()
                }
                .disabled(isBusy || didFinish)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
            }
        }
        .interactiveDismissDisabled(isBusy)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .task {
            await loadPreview()
        }
        .onDisappear {
            handleDisappear()
        }
    }

    private var truthBoundary: some View {
        WorklightCard {
            Text(Copy.heading)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
                .accessibilityIdentifier(Self.headingAccessibilityIdentifier)

            Text(Copy.disclosure)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Label(Self.truthBoundaryText, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(Self.boundaryAccessibilityIdentifier)

            Text(Self.contactSafeDiagnosticsText)
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)

            if reduceMotion {
                Text(Copy.reducedMotion)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "\(Self.boundaryAccessibilityIdentifier).reduced-motion"
                    )
            }
        }
    }

    private var sourceManifestCard: some View {
        WorklightCard {
            Text(Copy.sources)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(Copy.sourcesOrder)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(orderedSourceFiles.enumerated()), id: \.offset) {
                index,
                file in
                sourceFileRow(index: index, file: file)
            }

            Text(Copy.sourceSelection)
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(Self.sourceManifestAccessibilityIdentifier)
    }

    private func sourceFileRow(
        index: Int,
        file: PartyContactSiteRoleImportSourceDescriptorV1
    ) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(DesignTokens.Colors.completeText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Source \(index + 1): \(sourceLabel(for: file.kind))")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(file.fileName)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(file.byteCount) bytes · SHA-256 \(file.sha256)")
                    .font(.caption.monospaced())
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.small / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Selected source \(index + 1), \(sourceLabel(for: file.kind)), \(file.fileName), \(file.byteCount) bytes, SHA-256 \(file.sha256)"
        )
        .accessibilityIdentifier(
            Self.sourceFileAccessibilityIdentifierPrefix
                + file.kind.rawValue.lowercased()
        )
    }

    private var bindingCard: some View {
        WorklightCard {
            Text(Copy.binding)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(Copy.bindingDisclosure)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            bindingLine(
                label: "Source manifest SHA-256",
                value: prepared.sourceManifest.manifestSHA256
            )
            bindingLine(
                label: "Source binding SHA-256",
                value: prepared.sourceBindingSHA256
            )
            bindingLine(
                label: "Expected source SHA-256",
                value: prepared.preview.importPlan.source.sourceSHA256
            )
            bindingLine(
                label: "Observed source SHA-256",
                value: currentSourceSHA256
            )
            bindingLine(
                label: "Expected workspace revision SHA-256",
                value: prepared.preview.importPlan.workspaceRevisionSHA256
            )
            bindingLine(
                label: "Observed workspace revision SHA-256",
                value: currentWorkspaceRevisionSHA256
            )
            bindingLine(
                label: "Import plan SHA-256",
                value: prepared.preview.importPlan.planSHA256
            )
            bindingLine(
                label: "Bulk plan SHA-256",
                value: prepared.preview.bulkPlan.planSHA256
            )

            if let row = prepared.preview.importPlan.rows.first {
                bindingLine(
                    label: "Synthetic row identity SHA-256",
                    value: row.identity.identitySHA256
                )
                if let command = row.commands.first {
                    bindingLine(
                        label: "Canonical command",
                        value: command.kind.rawValue
                    )
                    bindingLine(
                        label: "Command target",
                        value: command.targetStableID.map { $0.uuidString }
                            ?? Copy.canonicalTarget
                    )
                }
            }
        }
        .accessibilityIdentifier(Self.bindingAccessibilityIdentifier)
    }

    private func bindingLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var diagnosticsCard: some View {
        WorklightCard {
            Text(Copy.diagnostics)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(Copy.diagnosticDisclosure)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            diagnosticSummary

            if orderedDiagnostics.isEmpty {
                Label(Copy.noDiagnostics, systemImage: "checkmark.circle")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.completeText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(PartyContactSiteRoleImportGroupV1.allCases, id: \.rawValue) {
                    group in
                    let rows = diagnostics(for: group)
                    if !rows.isEmpty {
                        diagnosticGroup(group, rows: rows)
                    }
                }
            }
        }
        .accessibilityIdentifier(Self.diagnosticsAccessibilityIdentifier)
    }

    private var diagnosticSummary: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small / 2) {
            diagnosticCount(
                severity: .information,
                count: count(of: .information)
            )
            diagnosticCount(
                severity: .warning,
                count: count(of: .warning)
            )
            diagnosticCount(
                severity: .error,
                count: count(of: .error)
            )
        }
        .accessibilityIdentifier("\(Self.diagnosticsAccessibilityIdentifier).summary")
    }

    private func diagnosticCount(
        severity: DiagnosticSeverity,
        count: Int
    ) -> some View {
        Label(
            "\(severity.label): \(count)",
            systemImage: severity.iconName
        )
        .font(.body)
        .foregroundStyle(severity.color)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func diagnosticGroup(
        _ group: PartyContactSiteRoleImportGroupV1,
        rows: [PartyContactSiteRoleImportDispositionV1]
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small / 2) {
            Text(groupLabel(for: group))
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                diagnosticRow(row)
            }
        }
    }

    @ViewBuilder
    private func diagnosticRow(
        _ row: PartyContactSiteRoleImportDispositionV1
    ) -> some View {
        let severity = severity(for: row.disposition)
        let isFirstIssue = firstIssueKey == diagnosticKey(row)
        let content = HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            Image(systemName: severity.iconName)
                .foregroundStyle(severity.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "\(severity.label): row \(row.rowIndex), \(dispositionLabel(for: row.disposition))"
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

                Text("Reason: \(row.reason.rawValue)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Expected revision: \(row.expectedRevision)")
                    .font(.caption.monospaced())
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.small / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(severity.label), \(groupLabel(for: row.group)), row \(row.rowIndex), \(dispositionLabel(for: row.disposition)), reason \(row.reason.rawValue), expected revision \(row.expectedRevision)"
        )
        .accessibilityIdentifier(
            Self.diagnosticAccessibilityIdentifierPrefix + diagnosticKey(row)
        )

        if isFirstIssue {
            content.accessibilityFocused($accessibilityFocus, equals: .firstIssue)
        } else {
            content
        }
    }

    @ViewBuilder
    private var previewCard: some View {
        WorklightCard {
            Text(Copy.preview)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            if let preview {
                let rows = preview.importPlan.rows
                let commandCount = rows.reduce(0) { $0 + $1.commands.count }
                Label(
                    "Validated \(rows.count) synthetic row(s), \(commandCount) command(s), \(preview.bulkPlan.atomicity.rawValue)",
                    systemImage: "checkmark.circle"
                )
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.completeText)
                .fixedSize(horizontal: false, vertical: true)

                Text(Copy.previewNoReceipt)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    previewRow(index: index, row: row)
                }
            } else {
                Label(Copy.previewPending, systemImage: "hourglass")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
    }

    private func previewRow(index: Int, row: ImportPlanRowV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small / 2) {
            Text("\(Copy.syntheticRow) \(index + 1)")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Text("Disposition: \(dispositionLabel(for: row.disposition))")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Text("Reasons: \(row.reasons.map(\.rawValue).joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Row identity SHA-256: \(row.identity.identitySHA256)")
                .font(.caption.monospaced())
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(row.commands.enumerated()), id: \.offset) { commandIndex, command in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Command \(commandIndex + 1): \(command.kind.rawValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    Text(
                        command.targetStableID.map { "Target: \($0.uuidString)" }
                            ?? Copy.canonicalTarget
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.small / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Copy.syntheticRow) \(index + 1), disposition \(dispositionLabel(for: row.disposition)), reasons \(row.reasons.map(\.rawValue).joined(separator: ", ")), row identity \(row.identity.identitySHA256)"
        )
    }

    @ViewBuilder
    private var statusCards: some View {
        if phase == .loading {
            operationStatusCard(
                message: Copy.previewPending,
                kind: .information,
                icon: "hourglass"
            )
        }
        if phase == .beginning {
            operationStatusCard(
                message: Copy.beginning,
                kind: .information,
                icon: "arrow.down.circle"
            )
        }
        if phase == .committing {
            operationStatusCard(
                message: Copy.committing,
                kind: .information,
                icon: "arrow.triangle.2.circlepath"
            )
        }
        if phase == .cleaningUp {
            operationStatusCard(
                message: "Discarding temporary source material…",
                kind: .information,
                icon: "trash"
            )
        }
        if phase == .cancelling {
            operationStatusCard(
                message: Copy.cancelling,
                kind: .information,
                icon: "xmark.circle"
            )
        }
        if let statusMessage {
            operationStatusCard(
                message: statusMessage,
                kind: phase == .completed ? .complete : .information,
                icon: phase == .completed ? "checkmark.circle" : "info.circle"
            )
        }
        if let errorMessage {
            WorklightCard {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($accessibilityFocus, equals: .error)
                    .accessibilityIdentifier(Self.errorAccessibilityIdentifier)

                Text(Copy.retryDisclosure)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func operationStatusCard(
        message: String,
        kind: WorklightStatusKind,
        icon: String
    ) -> some View {
        WorklightCard {
            Label(message, systemImage: icon)
                .font(.body)
                .foregroundStyle(statusColor(for: kind))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($accessibilityFocus, equals: .status)
                .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
        }
    }

    private var actionCard: some View {
        WorklightCard {
            Text("Actions")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)

            if phase == .previewReady {
                Button(Copy.begin) {
                    beginSession()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isBusy || preview == nil)
                .accessibilityHint(Copy.beginDisclosure)
                .accessibilityIdentifier(Self.beginAccessibilityIdentifier)
            }

            if phase == .sessionReady {
                Button(Copy.commit) {
                    commitImport()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isBusy || session == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(Copy.commitDisclosure)
                .accessibilityIdentifier(Self.commitAccessibilityIdentifier)
            }

            if phase == .failed {
                Button(retryLabel) {
                    retry()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isBusy)
                .accessibilityHint(Copy.retryDisclosure)
                .accessibilityIdentifier(Self.retryAccessibilityIdentifier)
            }

            if phase == .completed && cleanupPending {
                Button(Copy.retryCleanup) {
                    retry()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(isBusy)
                .accessibilityIdentifier(Self.cleanupAccessibilityIdentifier)
            }

            if phase == .completed {
                Button(Copy.done) {
                    didFinish = true
                    dismiss()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier("\(Self.statusAccessibilityIdentifier).done")
            } else if phase == .cancelled {
                Button(Copy.close) {
                    didFinish = true
                    dismiss()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier("\(Self.statusAccessibilityIdentifier).close")
            } else {
                Button(Copy.cancel, role: .cancel) {
                    cancelImport()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(isBusy || didFinish)
                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
            }
        }
    }

    private var orderedSourceFiles: [PartyContactSiteRoleImportSourceDescriptorV1] {
        prepared.sourceManifest.files.sorted {
            if $0.kind.orderIndex != $1.kind.orderIndex {
                return $0.kind.orderIndex < $1.kind.orderIndex
            }
            return $0.fileName < $1.fileName
        }
    }

    private var orderedDiagnostics: [PartyContactSiteRoleImportDispositionV1] {
        prepared.contactSafeDiagnostics.sorted {
            if $0.group.rawValue != $1.group.rawValue {
                return groupOrder($0.group) < groupOrder($1.group)
            }
            if $0.rowIndex != $1.rowIndex {
                return $0.rowIndex < $1.rowIndex
            }
            return $0.rowSHA256 < $1.rowSHA256
        }
    }

    private var firstIssueKey: String? {
        orderedDiagnostics.first(where: {
            severity(for: $0.disposition) != .information
        }).map(diagnosticKey)
    }

    private var retryLabel: String {
        switch retryTarget {
        case .preview: Copy.retryPreview
        case .begin: Copy.retryBegin
        case .commit: Copy.retryCommit
        case .cancel: Copy.retryCancel
        case .cleanup: Copy.retryCleanup
        }
    }

    private var isBusy: Bool {
        switch phase {
        case .beginning, .committing, .cleaningUp, .cancelling:
            true
        default:
            false
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private func loadPreview() async {
        guard preview == nil, !didFinish, !cancellationRequested else {
            return
        }

        do {
            let value = try coordinator.preview(
                prepared,
                currentSourceSHA256: currentSourceSHA256,
                currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
            )
            guard !Task.isCancelled, !didFinish, !cancellationRequested else {
                return
            }
            preview = value
            if initialSession != nil {
                phase = .sessionReady
                statusMessage = Copy.sessionReady
            } else {
                phase = .previewReady
                statusMessage = importPreviewCopy(.previewOnly)
            }
            moveAccessibilityFocus(to: firstIssueKey == nil ? .heading : .firstIssue)
        } catch {
            guard !didFinish, !cancellationRequested else { return }
            phase = .failed
            retryTarget = .preview
            statusMessage = nil
            errorMessage = Copy.previewFailure
            moveAccessibilityFocus(to: .error)
        }
    }

    private func beginSession() {
        guard phase == .previewReady, preview != nil, !isBusy else { return }
        phase = .beginning
        statusMessage = nil
        errorMessage = nil
        actionTask = Task { @MainActor in
            defer { actionTask = nil }
            do {
                let value = try coordinator.begin(
                    sessionID: sessionID,
                    prepared: prepared,
                    currentSourceSHA256: currentSourceSHA256,
                    currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
                )
                guard !Task.isCancelled, !didFinish else { return }
                session = value
                phase = .sessionReady
                statusMessage = Copy.sessionReady
                retryTarget = .commit
                moveAccessibilityFocus(to: .status)
            } catch {
                guard !didFinish else { return }
                phase = .failed
                retryTarget = .begin
                errorMessage = Copy.genericFailure
                moveAccessibilityFocus(to: .error)
            }
        }
    }

    private func commitImport() {
        guard phase == .sessionReady, let session, !isBusy else { return }
        phase = .committing
        statusMessage = nil
        errorMessage = nil
        actionTask = Task { @MainActor in
            defer { actionTask = nil }
            do {
                let updated = try coordinator.commitOrResume(
                    session: session,
                    prepared: prepared,
                    currentSourceSHA256: currentSourceSHA256,
                    currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
                    cancellationRequested: false
                )
                guard !Task.isCancelled, !didFinish else { return }
                self.session = updated
                switch updated.state {
                case .completed:
                    phase = .completed
                    retryTarget = .cleanup
                    statusMessage = Copy.completed
                    do {
                        try coordinator.discardScratch(for: prepared)
                        cleanupPending = false
                    } catch {
                        cleanupPending = true
                        statusMessage = Copy.completedCleanupPending
                    }
                    if !didNotifyCompletion {
                        didNotifyCompletion = true
                        onCompletion?(updated)
                    }
                    moveAccessibilityFocus(to: .status)
                case .cancelled:
                    phase = .cancelled
                    statusMessage = Copy.cancelled
                    moveAccessibilityFocus(to: .status)
                case .active, .cancellationRequested:
                    phase = .sessionReady
                    retryTarget = .commit
                    statusMessage = Copy.sessionReady
                    moveAccessibilityFocus(to: .status)
                case .quarantinedChangedInput:
                    phase = .failed
                    retryTarget = .commit
                    errorMessage = Copy.genericFailure
                    moveAccessibilityFocus(to: .error)
                }
            } catch {
                guard !didFinish else { return }
                phase = .failed
                retryTarget = .commit
                errorMessage = Copy.genericFailure
                moveAccessibilityFocus(to: .error)
            }
        }
    }

    private func cancelImport() {
        guard !isBusy, !didFinish else { return }
        cancellationRequested = true
        phase = .cancelling
        statusMessage = nil
        errorMessage = nil
        actionTask = Task { @MainActor in
            defer { actionTask = nil }
            do {
                if let session,
                   (session.state == .active
                       || session.state == .cancellationRequested) {
                    self.session = try coordinator.commitOrResume(
                        session: session,
                        prepared: prepared,
                        currentSourceSHA256: currentSourceSHA256,
                        currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
                        cancellationRequested: true
                    )
                }
                try coordinator.discardScratch(for: prepared)
                guard !Task.isCancelled else { return }
                cancellationRequested = false
                didFinish = true
                phase = .cancelled
                statusMessage = "\(Copy.cancelled) \(Copy.cancelledBoundary)"
                onCancel?()
                dismiss()
            } catch {
                guard !didFinish else { return }
                cancellationRequested = false
                phase = .failed
                retryTarget = .cancel
                errorMessage = Copy.genericFailure
                moveAccessibilityFocus(to: .error)
            }
        }
    }

    private func retry() {
        guard !isBusy else { return }
        errorMessage = nil
        switch retryTarget {
        case .preview:
            phase = .loading
            statusMessage = nil
            actionTask = nil
            Task { @MainActor in await loadPreview() }
        case .begin:
            guard preview != nil else {
                retryTarget = .preview
                phase = .loading
                Task { @MainActor in await loadPreview() }
                return
            }
            phase = .previewReady
            beginSession()
        case .commit:
            if session != nil {
                phase = .sessionReady
                commitImport()
            } else {
                retryTarget = .begin
                phase = .previewReady
                beginSession()
            }
        case .cancel:
            cancellationRequested = false
            cancelImport()
        case .cleanup:
            retryScratchCleanup()
        }
    }

    private func retryScratchCleanup() {
        guard !isBusy else { return }
        phase = .cleaningUp
        statusMessage = nil
        actionTask = Task { @MainActor in
            defer { actionTask = nil }
            do {
                try coordinator.discardScratch(for: prepared)
                guard !Task.isCancelled, !didFinish else { return }
                cleanupPending = false
                phase = .completed
                statusMessage = Copy.cleanupComplete
                moveAccessibilityFocus(to: .status)
            } catch {
                guard !didFinish else { return }
                phase = .failed
                retryTarget = .cleanup
                errorMessage = Copy.genericFailure
                moveAccessibilityFocus(to: .error)
            }
        }
    }

    private func handleDisappear() {
        actionTask?.cancel()
        actionTask = nil
        guard !didFinish else { return }

        // A live session must be durably cancelled before its exact source
        // leases can be released. If begin was interrupted before the view
        // received its session, retain scratch for recovery rather than
        // deleting material that may still back a durable session.
        if phase == .beginning, session == nil {
            phase = .failed
            retryTarget = .cancel
            errorMessage = Copy.genericFailure
            return
        }

        if let session,
           session.state == .active || session.state == .cancellationRequested {
            cancellationRequested = true
            do {
                let updated = try coordinator.commitOrResume(
                    session: session,
                    prepared: prepared,
                    currentSourceSHA256: currentSourceSHA256,
                    currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
                    cancellationRequested: true
                )
                self.session = updated
                guard updated.state == .cancelled else {
                    phase = .failed
                    retryTarget = .cancel
                    errorMessage = Copy.genericFailure
                    return
                }
            } catch {
                phase = .failed
                retryTarget = .cancel
                errorMessage = Copy.genericFailure
                return
            }
        }

        do {
            try coordinator.discardScratch(for: prepared)
        } catch {
            phase = .failed
            retryTarget = .cancel
            errorMessage = Copy.genericFailure
            return
        }

        cancellationRequested = false
        didFinish = true
        if phase != .completed {
            phase = .cancelled
            statusMessage = "\(Copy.cancelled) \(Copy.cancelledBoundary)"
            onCancel?()
        }
    }

    private func moveAccessibilityFocus(to target: FocusTarget) {
        guard !didFinish else { return }
        Task { @MainActor in
            await Task.yield()
            guard !didFinish else { return }
            accessibilityFocus = target
        }
    }

    private func diagnostics(
        for group: PartyContactSiteRoleImportGroupV1
    ) -> [PartyContactSiteRoleImportDispositionV1] {
        orderedDiagnostics.filter { $0.group.rawValue == group.rawValue }
    }

    private func count(of severity: DiagnosticSeverity) -> Int {
        orderedDiagnostics.reduce(into: 0) { count, row in
            if self.severity(for: row.disposition) == severity {
                count += 1
            }
        }
    }

    private func statusColor(for kind: WorklightStatusKind) -> Color {
        switch kind.rawValue {
        case WorklightStatusKind.complete.rawValue:
            DesignTokens.Colors.completeText
        default:
            DesignTokens.Colors.primaryText
        }
    }

    private func severity(
        for disposition: ImportRowDispositionV1
    ) -> DiagnosticSeverity {
        switch disposition {
        case .create, .updateExactMatch:
            .information
        case .unchanged, .skippedByUser:
            .warning
        case .duplicateSource, .ambiguousTarget, .conflict, .invalid, .unsupported:
            .error
        }
    }

    private func dispositionLabel(
        for disposition: ImportRowDispositionV1
    ) -> String {
        switch disposition {
        case .create:
            importPreviewCopy(.create)
        case .updateExactMatch:
            importPreviewCopy(.update)
        case .unchanged:
            importPreviewCopy(.unchanged)
        case .duplicateSource:
            importPreviewCopy(.duplicate)
        case .ambiguousTarget:
            importPreviewCopy(.ambiguous)
        case .conflict:
            importPreviewCopy(.conflict)
        case .invalid:
            importPreviewCopy(.invalid)
        case .unsupported:
            importPreviewCopy(.unsupported)
        case .skippedByUser:
            importPreviewCopy(.skipped)
        }
    }

    private func importPreviewCopy(
        _ key: ImportBulkPreviewLocalizationKeyV1
    ) -> String {
        BundledLocalizationCatalogV1.importBulkPreviewLocalized(key)
    }

    private func sourceLabel(
        for kind: PartyContactSiteRoleImportSourceKindV1
    ) -> String {
        switch kind {
        case .parties: "Parties (PARTIES_V1)"
        case .partyContacts: "Operational contacts (PARTY_CONTACTS_V1)"
        case .sitePartyRoles: "Site roles (SITE_PARTY_ROLES_V1)"
        }
    }

    private func groupLabel(
        for group: PartyContactSiteRoleImportGroupV1
    ) -> String {
        switch group {
        case .parties: "Parties"
        case .contacts: "Operational contacts"
        case .siteRoles: "Site roles"
        }
    }

    private func groupOrder(
        _ group: PartyContactSiteRoleImportGroupV1
    ) -> Int {
        switch group {
        case .parties: 0
        case .contacts: 1
        case .siteRoles: 2
        }
    }

    private func diagnosticKey(
        _ row: PartyContactSiteRoleImportDispositionV1
    ) -> String {
        "\(row.group.rawValue.lowercased()).\(row.rowIndex).\(row.rowSHA256)"
    }
}

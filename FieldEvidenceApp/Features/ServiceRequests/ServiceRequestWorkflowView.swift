import SwiftUI

/// A presentation-only wrapper for the two preview contracts emitted by C40.
/// It exposes no mutation or decision behavior; the coordinator remains the
/// single source of domain truth.
enum ServiceRequestPreviewPresentationV1 {
    case manual(ServiceRequestManualPreviewV1)
    case portable(ServiceRequestImportPreviewV1)

    var sourceKind: ServiceRequestSourceKindV1 {
        switch self {
        case let .manual(preview):
            return preview.record.source
        case .portable:
            return .portableSubmission
        }
    }

    var zeroWrite: Bool {
        switch self {
        case let .manual(preview):
            return preview.zeroWrite
        case let .portable(preview):
            return preview.plan.zeroWrite
        }
    }

    var disposition: ServiceRequestImportDispositionV1? {
        switch self {
        case let .manual(preview):
            return preview.dispositionEvent?.disposition
        case let .portable(preview):
            return preview.plan.disposition
        }
    }

    var duplicateProjection: ServiceRequestDuplicateProjectionV1 {
        switch self {
        case let .manual(preview):
            return preview.duplicateProjection
        case let .portable(preview):
            return preview.plan.duplicateProjection
        }
    }

    var capabilityAssessment: ServiceRequestCapabilityAssessmentV1? {
        guard case let .portable(preview) = self else { return nil }
        return preview.plan.capabilityAssessment
    }
}

/// A contained C40 presentation over supplied service-request contracts.
/// It does not create drafts, preview imports, write records, create work, or
/// send a status artifact. Those effects remain explicit coordinator actions.
@MainActor
struct ServiceRequestWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c40.service-request.screen"
    static let modeAccessibilityIdentifier = "v23.p04.c40.service-request.mode"
    static let draftAccessibilityIdentifier = "v23.p04.c40.service-request.draft"
    static let duplicateAccessibilityIdentifier = "v23.p04.c40.service-request.duplicates"
    static let dispositionAccessibilityIdentifier = "v23.p04.c40.service-request.dispositions"
    static let workAccessibilityIdentifier = "v23.p04.c40.service-request.create-work"
    static let statusAccessibilityIdentifier = "v23.p04.c40.service-request.status"
    static let boundaryAccessibilityIdentifier = "v23.p04.c40.service-request.boundaries"

    let sourceKind: ServiceRequestSourceKindV1
    let preview: ServiceRequestPreviewPresentationV1?
    let stateProjection: ServiceRequestStateProjectionV1?
    let statusArtifact: ServiceRequestStatusArtifactV1?
    let onRefreshPreview: @MainActor () -> Void
    let onCreateWork: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?

    private enum FocusTarget: Hashable {
        case heading
        case needsTriage
        case status
    }

    init(
        sourceKind: ServiceRequestSourceKindV1,
        preview: ServiceRequestPreviewPresentationV1?,
        stateProjection: ServiceRequestStateProjectionV1?,
        statusArtifact: ServiceRequestStatusArtifactV1? = nil,
        onRefreshPreview: @escaping @MainActor () -> Void,
        onCreateWork: @escaping @MainActor () -> Void
    ) {
        self.sourceKind = sourceKind
        self.preview = preview
        self.stateProjection = stateProjection
        self.statusArtifact = statusArtifact
        self.onRefreshPreview = onRefreshPreview
        self.onCreateWork = onCreateWork
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                modeAndTruth
                draftAndPreview
                duplicateReasons
                dispositionChoices
                createWork
                customerSafeStatus
                boundaries
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Service request")
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = needsTriage ? .needsTriage : .heading
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var effectiveSourceKind: ServiceRequestSourceKindV1 {
        preview?.sourceKind ?? sourceKind
    }

    private var isPortable: Bool { effectiveSourceKind == .portableSubmission }

    private var currentState: ServiceRequestStateV1? {
        stateProjection?.state ?? statusArtifact?.state
    }

    private var needsTriage: Bool {
        guard let preview else { return true }
        return currentState == .openUntriaged || preview.disposition == nil
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Service request")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("Review a supplied request, its zero-write preview, and explicit next actions. Requester, contact, urgency, and source details remain unverified assertions.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeAndTruth: some View {
        WorklightCard {
            sectionHeading("Request mode", identifier: Self.modeAccessibilityIdentifier)
            Label(
                isPortable ? "Portable submission" : "Manual intake",
                systemImage: isPortable ? "tray.and.arrow.down" : "square.and.pencil"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityElement(children: .combine)
            Text(isPortable
                 ? "Portable data is supplied for review. This surface does not claim delivery, sender identity, portal access, monitoring, or a dispatch outcome."
                 : "Manual intake is a supplied local source. This surface does not claim a call, message, requester identity, contact verification, urgency verification, or dispatch.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var draftAndPreview: some View {
        WorklightCard {
            sectionHeading("Resumable draft and preview", identifier: Self.draftAccessibilityIdentifier)
            if let preview {
                Label("A supplied draft preview can be resumed.", systemImage: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .accessibilityElement(children: .combine)
                valueRow("Preview write status", value: preview.zeroWrite ? "Zero-write" : "Unavailable")
                valueRow(
                    "Requested disposition",
                    value: preview.disposition.map { dispositionText($0) } ?? "Needs triage"
                )
                valueRow(
                    "Capability",
                    value: preview.capabilityAssessment.map { capabilityText($0) } ?? "Not applicable to manual intake"
                )
                Text("Refreshing the supplied preview must remain zero-write. It does not accept, import, link, dispatch, or create work.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Needs triage before any action", systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .accessibilityFocused($accessibilityFocus, equals: .needsTriage)
                    .accessibilityElement(children: .combine)
                Text("No resumable preview was supplied. No request record, work, contact, receipt, or delivery effect is claimed.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Refresh zero-write preview", action: onRefreshPreview)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .keyboardShortcut("p", modifiers: [.command])
                .accessibilityHint("Requests only the supplied zero-write preview. No import or work action is performed.")
                .accessibilityIdentifier("\(Self.draftAccessibilityIdentifier).refresh-preview")
        }
        .accessibilityElement(children: .contain)
    }

    private var duplicateReasons: some View {
        WorklightCard {
            sectionHeading("Possible duplicates", identifier: Self.duplicateAccessibilityIdentifier)
            let candidates = preview?.duplicateProjection.candidates ?? []
            if candidates.isEmpty {
                Text("No supplied duplicate suggestions are available. This is not a uniqueness, search, or monitoring claim.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Suggestions are explainable and do not automatically merge, link, close, or replace any request.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(candidates, id: \.record.recordID) { candidate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggested request revision \(candidate.record.revision)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        ForEach(candidate.reasons, id: \.self) { reason in
                            Text(reason.explanation)
                                .font(.footnote)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var dispositionChoices: some View {
        WorklightCard {
            sectionHeading("Explicit dispositions", identifier: Self.dispositionAccessibilityIdentifier)
            Text("Choose only a separately supplied canonical disposition after reviewing the preview. This screen does not choose or persist one.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ServiceRequestImportDispositionV1.allCases, id: \.rawValue) { disposition in
                Text(dispositionText(disposition))
                    .font(.footnote)
                    .foregroundStyle(preview?.disposition == disposition
                                     ? DesignTokens.Colors.informationText
                                     : DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var createWork: some View {
        WorklightCard {
            sectionHeading("Create work", identifier: Self.workAccessibilityIdentifier)
            Text("Create work is separate from request intake and disposition. It requires a supplied canonical work action; this button does not claim assignment, dispatch, scheduling, monitoring, an SLA, or completion.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Create work from supplied request", action: onCreateWork)
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(needsTriage)
                .keyboardShortcut("w", modifiers: [.command])
                .accessibilityHint(needsTriage
                    ? "Unavailable while the request needs triage."
                    : "Requests the separately supplied canonical work action.")
                .accessibilityIdentifier(Self.workAccessibilityIdentifier)
            if needsTriage {
                Text("Create work is unavailable until a supplied preview and triage state are available.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var customerSafeStatus: some View {
        WorklightCard {
            sectionHeading("Customer-safe status and PDF handoff", identifier: Self.statusAccessibilityIdentifier)
            if let statusArtifact {
                valueRow(statusArtifact.title, value: statusArtifact.statusText)
                if let customerNote = statusArtifact.customerNote {
                    Text(customerNote)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("This supplied status artifact does not verify the requester, contact, urgency, delivery, dispatch, work completion, or service result.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let stateProjection {
                valueRow("Current request state", value: stateText(stateProjection.state))
                Text("This status is an existing canonical request-state projection. It does not verify the requester, contact, urgency, delivery, dispatch, work completion, or service result.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No canonical status is supplied. The request remains needs-triage and no external status is claimed.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(statusArtifact == nil
                 ? "A customer-safe PDF handoff is not supplied. This view cannot create, render, send, deliver, or confirm a PDF."
                 : "A customer-safe status artifact is supplied for the existing handoff route. It does not claim delivery, receipt, reading, identity verification, approval, or a service outcome.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityFocused($accessibilityFocus, equals: .status)
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading("Accessibility and boundaries", identifier: Self.boundaryAccessibilityIdentifier)
            Text("All controls have stable labels for VoiceOver, Voice Control, Switch Control, keyboard use, and RTL layout. At Accessibility text sizes, content reflows without relying on truncation.")
            Text("Errors move focus to needs-triage. Reduce Motion adds no state-change animation. This contained surface makes no network, portal, delivery, dispatch, SLA, monitoring, or contact-verification claim.")
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
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

    private func capabilityText(_ value: ServiceRequestCapabilityAssessmentV1) -> String {
        "Proof \(value.proofValidity.rawValue.replacingOccurrences(of: "_", with: " ")); import \(value.importEligibility.rawValue.replacingOccurrences(of: "_", with: " "))"
    }

    private func dispositionText(_ value: ServiceRequestImportDispositionV1) -> String {
        switch value {
        case .acceptAsNew: return "Accept as new"
        case .acceptAndLinkDuplicate: return "Accept and link duplicate"
        case .declineWithReason: return "Decline with reason"
        case .recordHistoryOnly: return "Record history only"
        case .keepQuarantined: return "Keep quarantined"
        case .discardUnimported: return "Discard unimported"
        }
    }

    private func stateText(_ value: ServiceRequestStateV1) -> String {
        switch value {
        case .openUntriaged: return "Open — needs triage"
        case .openAccepted: return "Open — accepted"
        case .handledByLinkedWork: return "Handled by linked work"
        case .declined: return "Declined"
        case .closedNoWork: return "Closed without work"
        case .superseded: return "Superseded"
        }
    }
}

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
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.serviceRequestNavigationTitle))
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
            Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestHeadingDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeAndTruth: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.serviceRequestModeHeading), identifier: Self.modeAccessibilityIdentifier)
            Label(
                isPortable ? BundledLocalizationCatalogV1.v30Text(.serviceRequestPortableSubmission) : BundledLocalizationCatalogV1.v30Text(.serviceRequestManualIntake),
                systemImage: isPortable ? "tray.and.arrow.down" : "square.and.pencil"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityElement(children: .combine)
            Text(isPortable
                 ? BundledLocalizationCatalogV1.v30Text(.serviceRequestPortableDescription)
                 : BundledLocalizationCatalogV1.v30Text(.serviceRequestManualDescription))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var draftAndPreview: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.serviceRequestDraftHeading), identifier: Self.draftAccessibilityIdentifier)
            if let preview {
                Label(BundledLocalizationCatalogV1.v30Text(.serviceRequestDraftAvailable), systemImage: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.informationText)
                    .accessibilityElement(children: .combine)
                valueRow(BundledLocalizationCatalogV1.v30Text(.serviceRequestPreviewWriteStatus), value: preview.zeroWrite ? BundledLocalizationCatalogV1.v30Text(.serviceRequestZeroWrite) : BundledLocalizationCatalogV1.v30Text(.serviceRequestUnavailable))
                valueRow(
                    BundledLocalizationCatalogV1.v30Text(.serviceRequestRequestedDisposition),
                    value: preview.disposition.map { dispositionText($0) } ?? BundledLocalizationCatalogV1.v30Text(.serviceRequestNeedsTriage)
                )
                valueRow(
                    BundledLocalizationCatalogV1.v30Text(.serviceRequestCapability),
                    value: preview.capabilityAssessment.map { capabilityText($0) } ?? BundledLocalizationCatalogV1.v30Text(.serviceRequestNotApplicableManualIntake)
                )
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestPreviewDescription))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(BundledLocalizationCatalogV1.v30Text(.serviceRequestNeedsTriageBeforeAction), systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .accessibilityFocused($accessibilityFocus, equals: .needsTriage)
                    .accessibilityElement(children: .combine)
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestNoPreview))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(BundledLocalizationCatalogV1.v30Text(.serviceRequestRefreshPreview), action: onRefreshPreview)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .keyboardShortcut("p", modifiers: [.command])
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.serviceRequestRefreshHint))
                .accessibilityIdentifier("\(Self.draftAccessibilityIdentifier).refresh-preview")
        }
        .accessibilityElement(children: .contain)
    }

    private var duplicateReasons: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.serviceRequestDuplicatesHeading), identifier: Self.duplicateAccessibilityIdentifier)
            let candidates = preview?.duplicateProjection.candidates ?? []
            if candidates.isEmpty {
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestNoDuplicates))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestDuplicatesDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(candidates, id: \.record.recordID) { candidate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BundledLocalizationCatalogV1.v30ServiceRequestSuggestedRevision(revision: String(candidate.record.revision)))
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
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionsHeading), identifier: Self.dispositionAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionsDescription))
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
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.serviceRequestCreateWorkHeading), identifier: Self.workAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestCreateWorkDescription))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(BundledLocalizationCatalogV1.v30Text(.serviceRequestCreateWork), action: onCreateWork)
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(needsTriage)
                .keyboardShortcut("w", modifiers: [.command])
                .accessibilityHint(needsTriage
                    ? BundledLocalizationCatalogV1.v30Text(.serviceRequestCreateWorkUnavailable)
                    : BundledLocalizationCatalogV1.v30Text(.serviceRequestCreateWorkHint))
                .accessibilityIdentifier(Self.workAccessibilityIdentifier)
            if needsTriage {
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestCreateWorkNoPreview))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var customerSafeStatus: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.serviceRequestStatusHeading), identifier: Self.statusAccessibilityIdentifier)
            if let statusArtifact {
                valueRow(statusArtifact.title, value: statusArtifact.statusText)
                if let customerNote = statusArtifact.customerNote {
                    Text(customerNote)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestStatusArtifactDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let stateProjection {
                valueRow(BundledLocalizationCatalogV1.v30Text(.serviceRequestCurrentState), value: stateText(stateProjection.state))
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestCurrentStateDescription))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestNoStatus))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(statusArtifact == nil
                 ? BundledLocalizationCatalogV1.v30Text(.serviceRequestNoPdfHandoff)
                 : BundledLocalizationCatalogV1.v30Text(.serviceRequestPdfHandoffAvailable))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityFocused($accessibilityFocus, equals: .status)
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.serviceRequestBoundariesHeading), identifier: Self.boundaryAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestAccessibilityDescription))
            Text(BundledLocalizationCatalogV1.v30Text(.serviceRequestBoundariesDescription))
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
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

    private func capabilityText(_ value: ServiceRequestCapabilityAssessmentV1) -> String {
        BundledLocalizationCatalogV1.v30ServiceRequestCapability(proof: value.proofValidity.rawValue.replacingOccurrences(of: "_", with: " "), eligibility: value.importEligibility.rawValue.replacingOccurrences(of: "_", with: " "))
    }

    private func dispositionText(_ value: ServiceRequestImportDispositionV1) -> String {
        switch value {
        case .acceptAsNew: return BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionAcceptAsNew)
        case .acceptAndLinkDuplicate: return BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionAcceptAndLinkDuplicate)
        case .declineWithReason: return BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionDeclineWithReason)
        case .recordHistoryOnly: return BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionRecordHistoryOnly)
        case .keepQuarantined: return BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionKeepQuarantined)
        case .discardUnimported: return BundledLocalizationCatalogV1.v30Text(.serviceRequestDispositionDiscardUnimported)
        }
    }

    private func stateText(_ value: ServiceRequestStateV1) -> String {
        switch value {
        case .openUntriaged: return BundledLocalizationCatalogV1.v30Text(.serviceRequestStateOpenUntriaged)
        case .openAccepted: return BundledLocalizationCatalogV1.v30Text(.serviceRequestStateOpenAccepted)
        case .handledByLinkedWork: return BundledLocalizationCatalogV1.v30Text(.serviceRequestStateHandledByLinkedWork)
        case .declined: return BundledLocalizationCatalogV1.v30Text(.serviceRequestStateDeclined)
        case .closedNoWork: return BundledLocalizationCatalogV1.v30Text(.serviceRequestStateClosedNoWork)
        case .superseded: return BundledLocalizationCatalogV1.v30Text(.serviceRequestStateSuperseded)
        }
    }
}

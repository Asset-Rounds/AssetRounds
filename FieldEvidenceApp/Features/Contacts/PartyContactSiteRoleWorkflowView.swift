import SwiftUI

/// A contained C42 presentation over supplied Party, contact, and Site-role
/// workflow previews. It owns no identity resolution, canonical write, route,
/// communication, permission, or telemetry effect.
@MainActor
struct PartyContactSiteRoleWorkflowView: View {
    static let screenAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.screen"
    static let partyAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.party"
    static let contactsAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.contacts"
    static let preferredAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.preferred"
    static let siteRoleAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.site-role"
    static let impactWarningsAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.impact-warnings"
    static let historyAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.history"
    static let reversalAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.reversal"
    static let boundariesAccessibilityIdentifier = "v23.p04.c42.party-contact-site-role.boundaries"

    let partyPreview: PartyWorkflowPreviewV1?
    let contactPreview: OperationalContactWorkflowPreviewV1?
    let siteRolePreview: SiteRoleWorkflowPreviewV1?
    let history: PartyContactSiteRoleHistoryProjectionV1?
    let onRequestPreview: @MainActor (PartyContactSiteRoleOperationV1) -> Void
    let onConfirmPartyRetirement: @MainActor (PartyWorkflowPreviewV1) -> Void
    let onConfirmContactRetirement: @MainActor (OperationalContactWorkflowPreviewV1) -> Void
    let onConfirmSiteRoleReversal: @MainActor (SiteRoleWorkflowPreviewV1) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?
    @State private var confirmation: ConfirmationTarget?

    private enum FocusTarget: Hashable {
        case heading
        case warning
        case confirmation
    }

    private enum ConfirmationTarget: Equatable {
        case partyRetirement
        case contactRetirement
        case siteRoleReversal
    }

    init(
        partyPreview: PartyWorkflowPreviewV1?,
        contactPreview: OperationalContactWorkflowPreviewV1?,
        siteRolePreview: SiteRoleWorkflowPreviewV1?,
        history: PartyContactSiteRoleHistoryProjectionV1?,
        onRequestPreview: @escaping @MainActor (PartyContactSiteRoleOperationV1) -> Void,
        onConfirmPartyRetirement: @escaping @MainActor (PartyWorkflowPreviewV1) -> Void,
        onConfirmContactRetirement: @escaping @MainActor (OperationalContactWorkflowPreviewV1) -> Void,
        onConfirmSiteRoleReversal: @escaping @MainActor (SiteRoleWorkflowPreviewV1) -> Void
    ) {
        self.partyPreview = partyPreview
        self.contactPreview = contactPreview
        self.siteRolePreview = siteRolePreview
        self.history = history
        self.onRequestPreview = onRequestPreview
        self.onConfirmPartyRetirement = onConfirmPartyRetirement
        self.onConfirmContactRetirement = onConfirmContactRetirement
        self.onConfirmSiteRoleReversal = onConfirmSiteRoleReversal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                partyActions
                contactActions
                preferredContacts
                siteRoleActions
                impactAndWarnings
                historicalSnapshots
                reversalAndConfirmation
                boundaries
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .background(DesignTokens.Colors.canvas)
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            accessibilityFocus = .heading
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowHeading))
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowIntroduction))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var partyActions: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowParty), identifier: Self.partyAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPartyNotice))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestPartyCreatePreview), operation: .createParty)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestPartyEditPreview), operation: .editParty)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestPartyRetirementPreview), operation: .retireParty)
        }
        .accessibilityElement(children: .contain)
    }

    private var contactActions: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowOperationalContacts), identifier: Self.contactsAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowContactsNotice))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestContactCreatePreview), operation: .createContact)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestContactEditPreview), operation: .editContact)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestContactRetirementPreview), operation: .retireContact)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestContactReactivationPreview), operation: .reactivateContact)
        }
        .accessibilityElement(children: .contain)
    }

    private var preferredContacts: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPreferredContactByKind), identifier: Self.preferredAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPreferredContactNotice))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let impact = contactPreview?.impact, !impact.preferredScopes.isEmpty {
                ForEach(impact.preferredScopes, id: \.partyContactPreferenceScopeIdentity) { scope in
                    Text(BundledLocalizationCatalogV1.v30PartyContactWorkflowPreferredScope(kind: scope.kind.rawValue.lowercased(), activeContactCount: scope.activeContactPointIDs.count))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowNoPreferredScope))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestPreferredContactPreview), operation: .setPreferredContact)
        }
        .accessibilityElement(children: .contain)
    }

    private var siteRoleActions: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowSiteRoleHistory), identifier: Self.siteRoleAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowSiteRoleNotice))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestSiteRoleAssignmentPreview), operation: .appendSiteRole)
            actionButton(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowRequestSiteRoleReversalPreview), operation: .reverseSiteRole)
        }
        .accessibilityElement(children: .contain)
    }

    private var impactAndWarnings: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowImpactPreviewAndWarnings), identifier: Self.impactWarningsAccessibilityIdentifier)
            if let impact {
                valueRow(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPreviewWriteStatus), value: zeroWrite ? BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowZeroWrite) : BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowUnavailable))
                valueRow(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowOperation), value: operationText(impact.operation))
                valueRow(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowCascadeCount), value: "\(impact.cascadeCount)")
                valueRow(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowIdentityMergeCount), value: "\(impact.identityMergeCount)")
                ForEach(impact.warnings, id: \.rawValue) { warning in
                    Label(warningText(warning), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.attentionText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityFocused($accessibilityFocus, equals: .warning)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowNoImpactPreview))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var historicalSnapshots: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowHistoricalSnapshots), identifier: Self.historyAccessibilityIdentifier)
            if let history {
                valueRow(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPartyRevisions), value: "\(history.partyRevisions.count)")
                valueRow(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowContactRevisions), value: "\(history.contactRevisions.count)")
                valueRow(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowSiteRoleEvents), value: "\(history.siteRoleEvents.count)")
                Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowHistoryNotice))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(history.partyRevisions, id: \.partyRevisionIdentity) { party in
                    Text(BundledLocalizationCatalogV1.v30PartyContactWorkflowPartySnapshot(name: party.displayName, revision: String(party.revision), state: party.state.rawValue.lowercased()))
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowNoHistoricalSnapshot))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var reversalAndConfirmation: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowReversalAndConfirmation), identifier: Self.reversalAccessibilityIdentifier)
            if siteRolePreview?.impact.operation == .reverseSiteRole {
                Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowReversalNotice))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowConfirmSiteRoleReversal)) {
                    confirmation = .siteRoleReversal
                    accessibilityFocus = .confirmation
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowNoSiteRoleReversalPreview))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            if partyPreview?.impact.operation == .retireParty {
                Button(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowReviewIrreversiblePartyRetirement)) {
                    confirmation = .partyRetirement
                    accessibilityFocus = .confirmation
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
            }
            if contactPreview?.impact.operation == .retireContact {
                Button(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowReviewReversibleContactRetirement)) {
                    confirmation = .contactRetirement
                    accessibilityFocus = .confirmation
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
            }

            confirmationPanel
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var confirmationPanel: some View {
        switch confirmation {
        case .partyRetirement:
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPartyRetirementConfirmation))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.attentionText)
                .accessibilityFocused($accessibilityFocus, equals: .confirmation)
            Button(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowConfirmPartyRetirement)) {
                if let partyPreview { onConfirmPartyRetirement(partyPreview) }
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
        case .contactRetirement:
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowContactRetirementConfirmation))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.attentionText)
                .accessibilityFocused($accessibilityFocus, equals: .confirmation)
            Button(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowConfirmContactRetirement)) {
                if let contactPreview { onConfirmContactRetirement(contactPreview) }
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
        case .siteRoleReversal:
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowSiteRoleReversalConfirmation))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.attentionText)
                .accessibilityFocused($accessibilityFocus, equals: .confirmation)
            Button(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowConfirmSiteRoleReversal)) {
                if let siteRolePreview { onConfirmSiteRoleReversal(siteRolePreview) }
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
        case nil:
            EmptyView()
        }
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowAccessibilityAndBoundaries), identifier: Self.boundariesAccessibilityIdentifier)
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowAccessibilityNotice))
            Text(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowBoundariesNotice))
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var impact: PartyContactSiteRoleImpactV1? {
        partyPreview?.impact ?? contactPreview?.impact ?? siteRolePreview?.impact
    }

    private var zeroWrite: Bool {
        partyPreview?.zeroWrite ?? contactPreview?.zeroWrite ?? siteRolePreview?.zeroWrite ?? false
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.medium
    }

    private func actionButton(_ title: String, operation: PartyContactSiteRoleOperationV1) -> some View {
        Button(title) { onRequestPreview(operation) }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPreviewHint))
            .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).preview.\(operation.rawValue.lowercased())")
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

    private func operationText(_ operation: PartyContactSiteRoleOperationV1) -> String {
        BundledLocalizationCatalogV1.v30PartyContactWorkflowOperation(operation: operation.rawValue.replacingOccurrences(of: "_", with: " ").lowercased())
    }

    private func warningText(_ warning: PartyContactSiteRoleWarningV1) -> String {
        switch warning {
        case .equalValuesRemainDistinct:
            return BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowEqualValuesWarning)
        case .noCascade:
            return BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowNoHiddenCascadeWarning)
        case .operationalPurposeOnly:
            return BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowOperationalPurposeWarning)
        case .customerAndSiteLabelsArePresentationOnly:
            return BundledLocalizationCatalogV1.v30Text(.partyContactWorkflowPresentationLabelsWarning)
        }
    }
}

private extension ServiceContactPreferredScopeV1 {
    var partyContactPreferenceScopeIdentity: String {
        "\(partyID.uuidString)|\(kind.rawValue)"
    }
}

private extension ServicePartyReferenceV1 {
    var partyRevisionIdentity: String {
        "\(partyID.uuidString)|\(revision)"
    }
}

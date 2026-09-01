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
        .navigationTitle("Parties and contacts")
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
            Text("Parties, contacts, and Site roles")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            Text("Review supplied, zero-write changes before any separate canonical action. Equal names, phone numbers, and email addresses remain distinct assertions, not identity proof.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var partyActions: some View {
        WorklightCard {
            sectionHeading("Party", identifier: Self.partyAccessibilityIdentifier)
            Text("Create and edit require a supplied preview. Party retirement is irreversible in this workflow and is never inferred from a contact or Site-role change.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            actionButton("Request Party create preview", operation: .createParty)
            actionButton("Request Party edit preview", operation: .editParty)
            actionButton("Request Party retirement preview", operation: .retireParty)
        }
        .accessibilityElement(children: .contain)
    }

    private var contactActions: some View {
        WorklightCard {
            sectionHeading("Operational contacts", identifier: Self.contactsAccessibilityIdentifier)
            Text("Contacts are local operational records. This surface neither accesses the system Contacts database nor logs communications, grants marketing permission, or verifies identity.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            actionButton("Request contact create preview", operation: .createContact)
            actionButton("Request contact edit preview", operation: .editContact)
            actionButton("Request contact retirement preview", operation: .retireContact)
            actionButton("Request contact reactivation preview", operation: .reactivateContact)
        }
        .accessibilityElement(children: .contain)
    }

    private var preferredContacts: some View {
        WorklightCard {
            sectionHeading("Preferred contact by kind", identifier: Self.preferredAccessibilityIdentifier)
            Text("Preferred status is scoped to one supplied Party and contact kind, such as phone or email. It does not make a person preferred for another kind or prove identity.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let impact = contactPreview?.impact, !impact.preferredScopes.isEmpty {
                ForEach(impact.preferredScopes, id: \.partyContactPreferenceScopeIdentity) { scope in
                    Text("Supplied \(scope.kind.rawValue.lowercased()) preference scope for one Party; active contacts: \(scope.activeContactPointIDs.count).")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No preferred-contact scope is supplied.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            actionButton("Request preferred-contact preview", operation: .setPreferredContact)
        }
        .accessibilityElement(children: .contain)
    }

    private var siteRoleActions: some View {
        WorklightCard {
            sectionHeading("Site-role history", identifier: Self.siteRoleAccessibilityIdentifier)
            Text("Assign and end Site roles through append-only supplied events. Customer is a presentation label for a Site; this view does not create a Party from that label.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            actionButton("Request Site-role assignment preview", operation: .appendSiteRole)
            actionButton("Request Site-role reversal preview", operation: .reverseSiteRole)
        }
        .accessibilityElement(children: .contain)
    }

    private var impactAndWarnings: some View {
        WorklightCard {
            sectionHeading("Impact preview and warnings", identifier: Self.impactWarningsAccessibilityIdentifier)
            if let impact {
                valueRow("Preview write status", value: zeroWrite ? "Zero-write" : "Unavailable")
                valueRow("Operation", value: operationText(impact.operation))
                valueRow("Cascade count", value: "\(impact.cascadeCount)")
                valueRow("Identity merge count", value: "\(impact.identityMergeCount)")
                ForEach(impact.warnings, id: \.rawValue) { warning in
                    Label(warningText(warning), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.attentionText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityFocused($accessibilityFocus, equals: .warning)
            } else {
                Text("No impact preview is supplied. No Party, contact, Site-role, preferred-contact, merge, cascade, or saved-change claim is made.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var historicalSnapshots: some View {
        WorklightCard {
            sectionHeading("Historical snapshots", identifier: Self.historyAccessibilityIdentifier)
            if let history {
                valueRow("Party revisions", value: "\(history.partyRevisions.count)")
                valueRow("Contact revisions", value: "\(history.contactRevisions.count)")
                valueRow("Site-role events", value: "\(history.siteRoleEvents.count)")
                Text("Party and contact history is caller-bounded; Site-role history is append-only. Each supplied snapshot remains historical context rather than current identity proof.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(history.partyRevisions, id: \.partyRevisionIdentity) { party in
                    Text("Party snapshot: \(party.displayName), revision \(party.revision), \(party.state.rawValue.lowercased()).")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No historical snapshot projection is supplied. This screen does not reconstruct or infer history.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var reversalAndConfirmation: some View {
        WorklightCard {
            sectionHeading("Reversal and confirmation", identifier: Self.reversalAccessibilityIdentifier)
            if siteRolePreview?.impact.operation == .reverseSiteRole {
                Text("The supplied Site-role reversal appends a successor tied to the prior role event; it does not erase the prior event.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Confirm and request Site-role reversal") {
                    confirmation = .siteRoleReversal
                    accessibilityFocus = .confirmation
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
            } else {
                Text("No Site-role reversal preview is supplied.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            if partyPreview?.impact.operation == .retireParty {
                Button("Review irreversible Party retirement") {
                    confirmation = .partyRetirement
                    accessibilityFocus = .confirmation
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
            }
            if contactPreview?.impact.operation == .retireContact {
                Button("Review reversible contact retirement") {
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
            Text("Party retirement is irreversible here. Confirming requests the supplied canonical action; this view does not claim it completed.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.attentionText)
                .accessibilityFocused($accessibilityFocus, equals: .confirmation)
            Button("Confirm and request Party retirement") {
                if let partyPreview { onConfirmPartyRetirement(partyPreview) }
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
        case .contactRetirement:
            Text("Contact retirement is reversible only through a separately supplied reactivation preview. Confirming requests the supplied canonical action; it does not claim completion.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.attentionText)
                .accessibilityFocused($accessibilityFocus, equals: .confirmation)
            Button("Confirm and request contact retirement") {
                if let contactPreview { onConfirmContactRetirement(contactPreview) }
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
        case .siteRoleReversal:
            Text("Site-role reversal preserves the historical predecessor and requests one supplied successor action. It does not erase history or claim completion.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.attentionText)
                .accessibilityFocused($accessibilityFocus, equals: .confirmation)
            Button("Confirm and request Site-role reversal") {
                if let siteRolePreview { onConfirmSiteRoleReversal(siteRolePreview) }
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
        case nil:
            EmptyView()
        }
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading("Accessibility and boundaries", identifier: Self.boundariesAccessibilityIdentifier)
            Text("Destructive review moves accessibility focus to the confirmation. Stable labels support VoiceOver, Voice Control, Switch Control, keyboard use, and RTL layout. At Accessibility text sizes, content reflows without truncation; Reduce Motion adds no state-change animation.")
            Text("No Contacts permission, auto-created Party, communication, marketing, network, telemetry, delivery, verification, or root-navigation claim is made by this contained surface.")
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
            .accessibilityHint("Requests only a supplied zero-write impact preview.")
            .accessibilityIdentifier("\(Self.screenAccessibilityIdentifier).preview.\(operation.rawValue.lowercased())")
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

    private func operationText(_ operation: PartyContactSiteRoleOperationV1) -> String {
        operation.rawValue.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    private func warningText(_ warning: PartyContactSiteRoleWarningV1) -> String {
        switch warning {
        case .equalValuesRemainDistinct:
            return "Equal values remain distinct; no identity merge is inferred."
        case .noCascade:
            return "No hidden cascade is included."
        case .operationalPurposeOnly:
            return "Operational purpose only; no communication or marketing permission is implied."
        case .customerAndSiteLabelsArePresentationOnly:
            return "Customer and Site labels are presentation labels only."
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

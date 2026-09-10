import SwiftUI

struct NewSignView: View {
    static let screenAccessibilityIdentifier = "s2.new-sign.screen"
    static let siteLabelAccessibilityIdentifier = "s2.new-sign.site-label"
    static let signLabelAccessibilityIdentifier = "s2.new-sign.sign-label"
    static let optionalToggleAccessibilityIdentifier = "s2.new-sign.optional-toggle"
    static let addressAccessibilityIdentifier = "s2.new-sign.address"
    static let timeZoneAccessibilityIdentifier = "s2.new-sign.time-zone"
    static let timeZoneConfirmAccessibilityIdentifier = "s2.new-sign.time-zone-confirm"
    static let errorAccessibilityIdentifier = "s2.new-sign.error"
    static let saveAccessibilityIdentifier = "s2.new-sign.save"
    static let siteChoiceAccessibilityIdentifier = "s7.4.new-sign.site-choice"
    static let newSiteAccessibilityIdentifier = "s7.4.new-sign.new-site"

    private enum Field: Hashable {
        case siteLabel
        case signLabel
        case timeZoneID
        case timeZoneConfirmation
    }

    private enum SiteChoice: Hashable {
        case new
        case existing(UUID)
    }

    let coordinator: FirstSignCoordinator
    let siteOptions: [FirstSignSiteOption]
    let accessBlocked: (DraftAccessDecisionV1) -> Void
    let didSave: (FirstSignSnapshot) -> Void

    @State private var siteLabel = ""
    @State private var signLabel = ""
    @State private var showsOptionalDetails = false
    @State private var address = ""
    @State private var timeZoneID = ""
    @State private var isTimeZoneConfirmed = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var siteChoice: SiteChoice
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityFocusedField: Field?

    init(
        coordinator: FirstSignCoordinator,
        siteOptions: [FirstSignSiteOption] = [],
        accessBlocked: @escaping (DraftAccessDecisionV1) -> Void = { _ in },
        didSave: @escaping (FirstSignSnapshot) -> Void
    ) {
        self.coordinator = coordinator
        self.siteOptions = siteOptions
        self.accessBlocked = accessBlocked
        self.didSave = didSave
        _siteChoice = State(
            initialValue: siteOptions.first.map { .existing($0.id) } ?? .new
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    Text(siteOptions.isEmpty ? BundledLocalizationCatalogV1.v30Text(.newSignAddFirstSign) : BundledLocalizationCatalogV1.v30Text(.newSignAddSign))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text(BundledLocalizationCatalogV1.v30Text(.newSignInstructions))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !siteOptions.isEmpty {
                    WorklightCard {
                        Text(BundledLocalizationCatalogV1.v30Text(.newSignCustomerOrSite))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)

                        Picker(BundledLocalizationCatalogV1.v30Text(.newSignCustomerOrSitePicker), selection: $siteChoice) {
                            ForEach(siteOptions) { option in
                                Text(option.label)
                                    .tag(SiteChoice.existing(option.id))
                            }
                            Text(BundledLocalizationCatalogV1.v30Text(.newSignNewSite))
                                .tag(SiteChoice.new)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier(Self.siteChoiceAccessibilityIdentifier)
                    }
                }

                WorklightCard {
                    if siteChoice == .new {
                        labeledField(
                            label: BundledLocalizationCatalogV1.v30Text(.newSignCustomerOrSiteName),
                            text: $siteLabel,
                            field: .siteLabel,
                            identifier: Self.siteLabelAccessibilityIdentifier
                        )
                    }

                    labeledField(
                        label: BundledLocalizationCatalogV1.v30Text(.newSignSignName),
                        text: $signLabel,
                        field: .signLabel,
                        identifier: Self.signLabelAccessibilityIdentifier
                    )
                }

                if siteChoice == .new {
                    WorklightCard {
                    Button {
                        withAnimation { showsOptionalDetails.toggle() }
                    } label: {
                        Label(
                            showsOptionalDetails ? BundledLocalizationCatalogV1.v30Text(.newSignHideOptionalDetails) : BundledLocalizationCatalogV1.v30Text(.newSignAddOptionalDetails),
                            systemImage: showsOptionalDetails ? "chevron.up" : "chevron.down"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(Self.optionalToggleAccessibilityIdentifier)

                    if showsOptionalDetails {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                            labeledField(
                                label: BundledLocalizationCatalogV1.v30Text(.newSignAddressOptional),
                                text: $address,
                                field: nil,
                                identifier: Self.addressAccessibilityIdentifier
                            )

                            labeledField(
                                label: BundledLocalizationCatalogV1.v30Text(.newSignTimeZoneIdentifierOptional),
                                text: $timeZoneID,
                                field: .timeZoneID,
                                identifier: Self.timeZoneAccessibilityIdentifier
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            Toggle(BundledLocalizationCatalogV1.v30Text(.newSignConfirmTimeZoneIdentifier), isOn: $isTimeZoneConfirmed)
                                .frame(
                                    minWidth: DesignTokens.Control.minimumHitSize,
                                    maxWidth: .infinity,
                                    minHeight: DesignTokens.Control.minimumHitSize,
                                    alignment: .leading
                                )
                                .contentShape(.interaction, Rectangle())
                                .contentShape(.accessibility, Rectangle())
                                .tint(DesignTokens.Colors.interactionAccent)
                                .accessibilityIdentifier(Self.timeZoneConfirmAccessibilityIdentifier)
                                .accessibilityFocused(
                                    $accessibilityFocusedField,
                                    equals: .timeZoneConfirmation
                                )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    }
                } else if let selectedSite {
                    WorklightCard {
                        Text(BundledLocalizationCatalogV1.v30NewSignUsingSelectedSite(siteLabel: selectedSite.label))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        if let address = selectedSite.address {
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                    }
                }

                if let errorMessage {
                    WorklightStatusBadge(kind: .blocked, text: errorMessage)
                        .accessibilityIdentifier(Self.errorAccessibilityIdentifier)
                }

                Button(isSaving ? BundledLocalizationCatalogV1.v30Text(.newSignSaving) : BundledLocalizationCatalogV1.v30Text(.newSignSaveAndStartCheck)) {
                    save()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isSaving)
                .accessibilityIdentifier(Self.saveAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.newSignNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }

    @ViewBuilder
    private func labeledField(
        label: String,
        text: Binding<String>,
        field: Field?,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

            if let field {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: field)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier)
                    .accessibilityFocused($accessibilityFocusedField, equals: field)
            } else {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }

        errorMessage = nil
        focusedField = nil
        accessibilityFocusedField = nil
        isSaving = true

        let input = FirstSignInput(
            existingSiteID: selectedSite?.id,
            siteLabel: siteLabel,
            signLabel: signLabel,
            address: address,
            timeZoneID: timeZoneID,
            isTimeZoneConfirmed: isTimeZoneConfirmed
        )

        Task {
            do {
                let snapshot = try await coordinator.create(input)
                isSaving = false
                didSave(snapshot)
            } catch let error as FirstSignCoordinatorError {
                isSaving = false
                handle(error)
            } catch {
                isSaving = false
                errorMessage = BundledLocalizationCatalogV1.v30Text(.newSignSaveFailure)
            }
        }
    }

    private func handle(_ error: FirstSignCoordinatorError) {
        switch error {
        case let .validation(field):
            focus(field)
        case .firstSignAlreadyExists:
            errorMessage = BundledLocalizationCatalogV1.v30Text(.newSignFirstSignAlreadyAdded)
        case let .accessDenied(decision):
            accessBlocked(decision)
        case .storedDataInvalid, .saveFailed:
            errorMessage = BundledLocalizationCatalogV1.v30Text(.newSignSaveFailure)
        }
    }

    private var selectedSite: FirstSignSiteOption? {
        guard case let .existing(id) = siteChoice else { return nil }
        return siteOptions.first { $0.id == id }
    }

    private func focus(_ field: FirstSignValidationField) {
        let target: Field
        let requestsKeyboardFocus: Bool

        switch field {
        case .siteLabel:
            errorMessage = BundledLocalizationCatalogV1.v30Text(.newSignEnterCustomerOrSiteName)
            target = .siteLabel
            requestsKeyboardFocus = true
        case .signLabel:
            errorMessage = BundledLocalizationCatalogV1.v30Text(.newSignEnterSignName)
            target = .signLabel
            requestsKeyboardFocus = true
        case .timeZoneID:
            showsOptionalDetails = true
            errorMessage = BundledLocalizationCatalogV1.v30Text(.newSignEnterTimeZoneIdentifier)
            target = .timeZoneID
            requestsKeyboardFocus = true
        case .timeZoneConfirmation:
            showsOptionalDetails = true
            errorMessage = BundledLocalizationCatalogV1.v30Text(.newSignConfirmTimeZoneIdentifierError)
            target = .timeZoneConfirmation
            requestsKeyboardFocus = false
        }

        Task { @MainActor in
            await Task.yield()
            focusedField = requestsKeyboardFocus ? target : nil
            accessibilityFocusedField = target
        }
    }
}

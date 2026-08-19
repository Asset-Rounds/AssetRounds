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
        AssetRoundsScreenFoundation {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                AssetRoundsEvidenceCard {
                    Text(siteOptions.isEmpty ? "Add your first sign" : "Add sign")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .accessibilityAddTraits(.isHeader)

                    Text("Choose a customer or site, then name the sign you check there.")
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !siteOptions.isEmpty {
                    AssetRoundsEvidenceCard {
                        Text("Customer / site")
                            .font(DesignTokens.Typography.fieldLabel)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)

                        Picker("Customer / site", selection: $siteChoice) {
                            ForEach(siteOptions) { option in
                                Text(option.label)
                                    .tag(SiteChoice.existing(option.id))
                            }
                            Text("New site")
                                .tag(SiteChoice.new)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier(Self.siteChoiceAccessibilityIdentifier)
                    }
                }

                AssetRoundsEvidenceCard {
                    if siteChoice == .new {
                        labeledField(
                            label: "Customer / site name",
                            text: $siteLabel,
                            field: .siteLabel,
                            identifier: Self.siteLabelAccessibilityIdentifier
                        )
                    }

                    labeledField(
                        label: "Sign name",
                        text: $signLabel,
                        field: .signLabel,
                        identifier: Self.signLabelAccessibilityIdentifier
                    )
                }

                if let errorMessage {
                    AssetRoundsStateLabel(kind: .error, text: Text(errorMessage))
                        .accessibilityLabel("Blocked: \(errorMessage)")
                        .accessibilityValue(Text(verbatim: String()))
                        .accessibilityIdentifier(Self.errorAccessibilityIdentifier)
                        .padding(.bottom, DesignTokens.Spacing.space16)
                }

                if siteChoice == .new {
                    AssetRoundsEvidenceCard {
                        AssetRoundsSecondaryAction(action: {
                            showsOptionalDetails.toggle()
                        }) {
                            Label(
                                showsOptionalDetails ? "Hide optional details" : "Add optional details",
                                systemImage: showsOptionalDetails ? "chevron.up" : "chevron.down"
                            )
                        }
                        .accessibilityLabel(
                            showsOptionalDetails ? "Hide optional details" : "Add optional details"
                        )
                        .accessibilityIdentifier(Self.optionalToggleAccessibilityIdentifier)
                        .accessibilityHidden(
                            errorMessage != nil &&
                                (focusedField == .siteLabel || focusedField == .signLabel)
                        )

                        if showsOptionalDetails {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                                labeledField(
                                    label: "Address (optional)",
                                    text: $address,
                                    field: nil,
                                    identifier: Self.addressAccessibilityIdentifier
                                )

                                labeledField(
                                    label: "IANA time-zone identifier (optional)",
                                    text: $timeZoneID,
                                    field: .timeZoneID,
                                    identifier: Self.timeZoneAccessibilityIdentifier
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                                Toggle("I confirm this exact time-zone identifier", isOn: $isTimeZoneConfirmed)
                                    .frame(
                                        minWidth: DesignTokens.Target.minimumInteractiveWidth,
                                        maxWidth: .infinity,
                                        minHeight: DesignTokens.Target.minimumInteractiveHeight,
                                        alignment: .leading
                                    )
                                    .contentShape(.interaction, Rectangle())
                                    .contentShape(.accessibility, Rectangle())
                                    .tint(DesignTokens.SemanticColors.primaryAction)
                                    .accessibilityIdentifier(Self.timeZoneConfirmAccessibilityIdentifier)
                                    .accessibilityFocused(
                                        $accessibilityFocusedField,
                                        equals: .timeZoneConfirmation
                                    )
                            }
                        }
                    }
                } else if let selectedSite {
                    AssetRoundsEvidenceCard {
                        Text("Using \(selectedSite.label)")
                            .font(DesignTokens.Typography.fieldLabel)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        if let address = selectedSite.address {
                            Text(address)
                                .font(DesignTokens.Typography.secondaryBody)
                                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                        }
                    }
                }

                    AssetRoundsPrimaryAction(action: save) {
                        Text(isSaving ? "Saving…" : "Save and start check")
                    }
                    .accessibilityLabel(isSaving ? "Saving…" : "Save and start check")
                    .disabled(isSaving)
                    .accessibilityIdentifier(Self.saveAccessibilityIdentifier)
                }
                .padding(.bottom, DesignTokens.Spacing.space16)
            }
            .scrollDismissesKeyboard(.never)
        }
        .navigationTitle("New sign")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }

    @ViewBuilder
    private func labeledField(
        label: String,
        text: Binding<String>,
        field: Field?,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(label)
                .font(DesignTokens.Typography.fieldLabel)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)

            if let field {
                TextField(
                    text: text,
                    prompt: Text(label)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                )
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: field)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier)
                    .accessibilityFocused($accessibilityFocusedField, equals: field)
            } else {
                TextField(
                    text: text,
                    prompt: Text(label)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                )
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
                errorMessage = "The sign could not be saved. Try again."
            }
        }
    }

    private func handle(_ error: FirstSignCoordinatorError) {
        switch error {
        case let .validation(field):
            focus(field)
        case .firstSignAlreadyExists:
            errorMessage = "The first sign has already been added."
        case let .accessDenied(decision):
            accessBlocked(decision)
        case .storedDataInvalid, .saveFailed:
            errorMessage = "The sign could not be saved. Try again."
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
            errorMessage = "Enter a customer or site name."
            target = .siteLabel
            requestsKeyboardFocus = true
        case .signLabel:
            errorMessage = "Enter a sign name."
            target = .signLabel
            requestsKeyboardFocus = true
        case .timeZoneID:
            showsOptionalDetails = true
            errorMessage = "Enter an exact IANA time-zone identifier."
            target = .timeZoneID
            requestsKeyboardFocus = true
        case .timeZoneConfirmation:
            showsOptionalDetails = true
            errorMessage = "Confirm the exact time-zone identifier."
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

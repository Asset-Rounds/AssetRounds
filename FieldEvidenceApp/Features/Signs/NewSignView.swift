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

    private enum Field: Hashable {
        case siteLabel
        case signLabel
        case timeZoneID
        case timeZoneConfirmation
    }

    let coordinator: FirstSignCoordinator
    let didSave: (FirstSignSnapshot) -> Void

    @State private var siteLabel = ""
    @State private var signLabel = ""
    @State private var showsOptionalDetails = false
    @State private var address = ""
    @State private var timeZoneID = ""
    @State private var isTimeZoneConfirmed = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityFocusedField: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    Text("Add your first sign")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("Name the customer or site and the sign you check there.")
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WorklightCard {
                    labeledField(
                        label: "Customer / site name",
                        text: $siteLabel,
                        field: .siteLabel,
                        identifier: Self.siteLabelAccessibilityIdentifier
                    )

                    labeledField(
                        label: "Sign name",
                        text: $signLabel,
                        field: .signLabel,
                        identifier: Self.signLabelAccessibilityIdentifier
                    )
                }

                WorklightCard {
                    Button {
                        withAnimation { showsOptionalDetails.toggle() }
                    } label: {
                        Label(
                            showsOptionalDetails ? "Hide optional details" : "Add optional details",
                            systemImage: showsOptionalDetails ? "chevron.up" : "chevron.down"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(Self.optionalToggleAccessibilityIdentifier)

                    if showsOptionalDetails {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
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

                if let errorMessage {
                    WorklightStatusBadge(kind: .blocked, text: errorMessage)
                        .accessibilityIdentifier(Self.errorAccessibilityIdentifier)
                }

                Button(isSaving ? "Saving…" : "Save and start check") {
                    save()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isSaving)
                .accessibilityIdentifier(Self.saveAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("New sign")
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
                    .accessibilityIdentifier(identifier)
                    .accessibilityFocused($accessibilityFocusedField, equals: field)
            } else {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
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
        case .storedDataInvalid, .saveFailed:
            errorMessage = "The sign could not be saved. Try again."
        }
    }

    private func focus(_ field: FirstSignValidationField) {
        switch field {
        case .siteLabel:
            errorMessage = "Enter a customer or site name."
            focusedField = .siteLabel
            accessibilityFocusedField = .siteLabel
        case .signLabel:
            errorMessage = "Enter a sign name."
            focusedField = .signLabel
            accessibilityFocusedField = .signLabel
        case .timeZoneID:
            showsOptionalDetails = true
            errorMessage = "Enter an exact IANA time-zone identifier."
            focusedField = .timeZoneID
            accessibilityFocusedField = .timeZoneID
        case .timeZoneConfirmation:
            showsOptionalDetails = true
            errorMessage = "Confirm the exact time-zone identifier."
            accessibilityFocusedField = .timeZoneConfirmation
        }
    }
}

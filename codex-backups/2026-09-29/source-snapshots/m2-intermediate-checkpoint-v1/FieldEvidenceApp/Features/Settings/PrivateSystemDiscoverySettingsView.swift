import SwiftUI

/// A contained, unadopted settings surface for C14's sole typed device-local
/// preference. Its owner supplies the persisted binding; this view does not
/// read or write a raw preference key and is deliberately not wired into the
/// S10 shell.
struct PrivateSystemDiscoverySettingsView: View {
    @State private var preference: PrivateSystemDiscoveryOptInV1
    private let preferencePort: any PrivateSystemDiscoveryPreferencePortV1
    private let selectedRealWorkspaceID: WorkspaceID?
    private let availability: AppIntentAvailabilityV1?

    init(
        preferencePort: any PrivateSystemDiscoveryPreferencePortV1,
        selectedRealWorkspaceID: WorkspaceID?,
        availability: AppIntentAvailabilityV1?
    ) {
        self.preferencePort = preferencePort
        _preference = State(initialValue: (try? preferencePort.readPrivateSystemDiscoveryOptIn()) ?? .disabled)
        self.selectedRealWorkspaceID = selectedRealWorkspaceID
        self.availability = availability
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    BundledLocalizationCatalogV1.privateSystemDiscoveryLocalized(.indexingToggle),
                    isOn: enabledBinding
                )
                .disabled(!canEnable)
                .accessibilityIdentifier(
                    PrivateSystemDiscoveryAccessibilityIDV1.indexingToggle.rawValue
                )
                .accessibilityHint(statusCopy)

                Text(statusCopy)
                    .accessibilityIdentifier(
                        PrivateSystemDiscoveryAccessibilityIDV1.indexingState.rawValue
                    )

                Text(BundledLocalizationCatalogV1.privateSystemDiscoveryLocalized(.practiceExcluded))
                    .accessibilityIdentifier(
                        PrivateSystemDiscoveryAccessibilityIDV1.practiceExclusion.rawValue
                    )
            } header: {
                Text(BundledLocalizationCatalogV1.privateSystemDiscoveryLocalized(.settingsHeading))
                    .accessibilityIdentifier(
                        PrivateSystemDiscoveryAccessibilityIDV1.settingsHeading.rawValue
                    )
            } footer: {
                Text(BundledLocalizationCatalogV1.privateSystemDiscoveryLocalized(.settingsDisclosure))
            }
        }
        .accessibilityIdentifier(
            PrivateSystemDiscoveryAccessibilityIDV1.settingsScreen.rawValue
        )
    }

    private var canEnable: Bool {
        guard let selectedRealWorkspaceID, let availability else { return false }
        return availability.workspaceID == selectedRealWorkspaceID && availability.available
    }

    private var statusCopy: String {
        if availability?.available == false {
            return BundledLocalizationCatalogV1.privateSystemDiscoveryLocalized(.indexingUnavailable)
        }
        return preference.isEnabled
            ? BundledLocalizationCatalogV1.privateSystemDiscoveryLocalized(.settingsDisclosure)
            : BundledLocalizationCatalogV1.privateSystemDiscoveryLocalized(.indexingDisabled)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { preference.isEnabled },
            set: { enabled in
                guard enabled, canEnable, let workspaceID = selectedRealWorkspaceID else {
                    persist(.disabled)
                    return
                }
                do {
                    persist(try .enabled(
                        workspaceID: workspaceID,
                        workspaceKind: .real
                    ))
                } catch {
                    // A malformed selected ID remains disabled and does not
                    // create a second preference representation.
                    persist(.disabled)
                }
            }
        )
    }

    private func persist(_ value: PrivateSystemDiscoveryOptInV1) {
        guard (try? preferencePort.writePrivateSystemDiscoveryOptIn(
            value,
            operationID: UUID()
        )) != nil else {
            return
        }
        preference = value
    }
}

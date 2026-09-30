import SwiftUI
import UIKit

@MainActor
struct ReminderSettingsSectionV1: View {
    static let sectionAccessibilityIdentifier = "v23.reminders.settings"
    static let enabledAccessibilityIdentifier = "v23.reminders.enabled"
    static let detailsAccessibilityIdentifier = "v23.reminders.details"

    let access: AppAccessPresentationV1.ReminderSettingsAccess
    @Environment(\.openURL) private var openURL
    @State private var snapshot: AppAccessPresentationV1.ReminderSettingsSnapshot?
    @State private var loadedAccessID: UUID?
    @State private var isBusy = false
    @State private var message: String?
    @State private var needsReconciliation = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space12) {
            Text("Reminders")
                .font(DesignTokens.Typography.sectionHeading)
                .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                .accessibilityAddTraits(.isHeader)

            Toggle("Scheduled reminders", isOn: Binding(
                get: { snapshot?.policy.isEnabled ?? false },
                set: { enabled in
                    guard let policy = snapshot?.policy else { return }
                    update(policy, enabled: enabled, detail: policy.detail)
                }))
                .tint(DesignTokens.SemanticColors.primaryAction)
                .disabled(snapshot == nil || isBusy)
                .accessibilityIdentifier(Self.enabledAccessibilityIdentifier)
                #if DEBUG
                .nativeScreenObservationWitnessV1(Self.enabledAccessibilityIdentifier)
                #endif

            Toggle("Show reminder details", isOn: Binding(
                get: { snapshot?.policy.detail == .details },
                set: { detailed in
                    guard let policy = snapshot?.policy else { return }
                    update(policy, enabled: policy.isEnabled, detail: detailed ? .details : .generic)
                }))
                .tint(DesignTokens.SemanticColors.primaryAction)
                .disabled(snapshot == nil || isBusy)
                .accessibilityIdentifier(Self.detailsAccessibilityIdentifier)
                #if DEBUG
                .nativeScreenObservationWitnessV1(Self.detailsAccessibilityIdentifier)
                #endif

            Text(snapshot?.appLockEnabled == true
                ? "App Lock keeps notification text private. Your detail preference applies when App Lock is off."
                : "Details show whether a Round or Work item is due, with its scheduled date, time and time zone.")
                .font(DesignTokens.Typography.secondaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let snapshot {
                if snapshot.authorization == .denied {
                    Text("Notifications are off in iOS Settings. You can still review every schedule in My Day.")
                        .font(DesignTokens.Typography.secondaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    AssetRoundsSecondaryAction("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .disabled(isBusy)
                } else if snapshot.authorization == .notDetermined && snapshot.policy.isEnabled {
                    AssetRoundsSecondaryAction("Allow notifications") { requestPermission() }
                        .disabled(isBusy)
                }
                AssetRoundsSecondaryAction(needsReconciliation ? "Retry reminders" : "Update reminders") {
                    perform { try await access.reconcileSavedPolicy() }
                }
                .disabled(isBusy)
                .accessibilityIdentifier("v23.reminders.reconcile")
            }

            if let message {
                Text(message)
                    .font(DesignTokens.Typography.secondaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("v23.reminders.status")
                if snapshot == nil {
                    AssetRoundsSecondaryAction("Refresh reminders") { Task { await refresh() } }
                        .disabled(isBusy)
                }
            }
        }
        .font(DesignTokens.Typography.primaryBody)
        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.sectionAccessibilityIdentifier)
        #if DEBUG
        .nativeScreenObservationWitnessV1(Self.sectionAccessibilityIdentifier)
        #endif
        .task(id: access.id) { await refresh() }
    }

    private func refresh() async {
        let id = access.id
        if loadedAccessID != id { needsReconciliation = false }
        loadedAccessID = id
        snapshot = nil
        isBusy = true
        defer { if loadedAccessID == id { isBusy = false } }
        do {
            let value = try await access.read()
            guard loadedAccessID == id, !Task.isCancelled else { return }
            snapshot = value
            message = needsReconciliation
                ? "Your saved preference is available. Retry to finish updating notifications."
                : nil
        } catch {
            if loadedAccessID == id && !Task.isCancelled {
                message = "Reminders are unavailable right now. Refresh to check your saved preference."
            }
        }
    }

    private func update(_ policy: DeviceLocalReminderPolicyV1, enabled: Bool,
                        detail: ReminderNotificationDetailV1) {
        perform { try await access.update(expected: policy, isEnabled: enabled, detail: detail) }
    }

    private func requestPermission() {
        perform { try await access.requestPermission() }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, loadedAccessID == access.id else { return }
        let id = access.id
        isBusy = true
        message = nil
        Task { @MainActor in
            defer { if loadedAccessID == id { isBusy = false } }
            do {
                try await action()
                let value = try await access.read()
                guard loadedAccessID == id else { return }
                snapshot = value
                needsReconciliation = false
                message = nil
            } catch {
                let saved = try? await access.read()
                guard loadedAccessID == id else { return }
                snapshot = saved
                needsReconciliation = true
                message = "Your preference may be saved, but notifications need attention. Retry to finish updating reminders."
            }
        }
    }
}

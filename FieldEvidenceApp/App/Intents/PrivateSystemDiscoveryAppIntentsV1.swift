import AppIntents
import Foundation

/// The selected workspace is retrieved only after the AppAccess gate. This
/// adapter is not a second settings store or a second source of workspace
/// truth; composition supplies the existing typed selected-workspace reader.
protocol PrivateSystemDiscoveryIntentWorkspacePortV1: Sendable {
    func selectedRealWorkspaceID() async -> WorkspaceID?
}

actor PrivateSystemDiscoveryIntentRuntimeRegistryV1 {
    static let shared = PrivateSystemDiscoveryIntentRuntimeRegistryV1()

    private var accessGate: (any AppAccessGatePortV1)?
    private var coordinator: PrivateSystemDiscoveryCoordinatorV1?
    private var workspace: (any PrivateSystemDiscoveryIntentWorkspacePortV1)?

    func install(
        accessGate: any AppAccessGatePortV1,
        coordinator: PrivateSystemDiscoveryCoordinatorV1,
        workspace: any PrivateSystemDiscoveryIntentWorkspacePortV1
    ) {
        self.accessGate = accessGate
        self.coordinator = coordinator
        self.workspace = workspace
    }

    func removeRuntime() {
        accessGate = nil
        coordinator = nil
        workspace = nil
    }

    func invoke(_ action: PrivateSystemDiscoveryActionV1) async -> PrivateSystemDiscoveryResultV1 {
        guard let accessGate, let coordinator, let workspace else {
            return .unavailable
        }
        do {
            try await accessGate.requireContentAccess()
        } catch {
            return .unlockRequired
        }
        guard let workspaceID = await workspace.selectedRealWorkspaceID() else {
            return .unavailable
        }
        do {
            let request = try PrivateSystemDiscoveryRequestV1(
                requestID: UUID(),
                workspaceID: workspaceID,
                action: action,
                requestedAt: Date()
            )
            return try await coordinator.execute(request)
        } catch {
            return .unavailable
        }
    }
}

/// The complete App Intent enumeration is closed and intentionally omits
/// search: search needs a private parameter, which cannot be resolved by the
/// system before an in-app access-gated request is established.
enum PrivateSystemDiscoveryAppIntentManifestV1 {
    static let actions: [PrivateSystemDiscoveryActionV1] = [
        .openAssets,
        .openReports,
        .openToday,
    ]
    static let searchRequiresInAppGatedParameterResolution = true
    static let allIntentsAreForegroundReadOrNavigation = true
    static let nonWhitelistedIntentsDiscoverable = false

    static func validate() throws {
        let discoveryManifest = try PrivateSystemDiscoveryManifestV1()
        let manifestActions = Set(discoveryManifest.actions.map(\.action))
        guard actions == actions.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(actions).count == actions.count,
              Set(actions).isSubset(of: manifestActions),
              !actions.contains(.searchWorkspace),
              searchRequiresInAppGatedParameterResolution,
              allIntentsAreForegroundReadOrNavigation,
              !nonWhitelistedIntentsDiscoverable else {
            throw PrivateSystemDiscoveryFailureV1.unsupportedAction
        }
    }
}

private enum PrivateSystemDiscoveryIntentResponseV1 {
    static func dialog(for result: PrivateSystemDiscoveryResultV1) -> IntentDialog {
        switch result {
        case .unlockRequired:
            return IntentDialog(stringLiteral: BundledLocalizationCatalogV1.privateSystemDiscoveryEnglish(.unlockRequired))
        case .unavailable, .navigation, .read:
            // Navigation/read details stay in the foreground app. The system
            // response remains generic and cannot disclose private existence.
            return IntentDialog(stringLiteral: BundledLocalizationCatalogV1.privateSystemDiscoveryEnglish(.unavailable))
        }
    }
}

protocol PrivateSystemDiscoveryForegroundIntentV1: AppIntent {
    static var action: PrivateSystemDiscoveryActionV1 { get }
}

extension PrivateSystemDiscoveryForegroundIntentV1 {
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try PrivateSystemDiscoveryAppIntentManifestV1.validate()
        let result = await PrivateSystemDiscoveryIntentRuntimeRegistryV1.shared.invoke(Self.action)
        return .result(dialog: PrivateSystemDiscoveryIntentResponseV1.dialog(for: result))
    }
}

struct OpenTodayPrivateSystemDiscoveryIntentV1: PrivateSystemDiscoveryForegroundIntentV1 {
    static let title: LocalizedStringResource = "private.system.discovery.intent.open-today"
    static let description = IntentDescription("Opens the private Today destination in the foreground app.")
    static let action = PrivateSystemDiscoveryActionV1.openToday
}

struct OpenAssetsPrivateSystemDiscoveryIntentV1: PrivateSystemDiscoveryForegroundIntentV1 {
    static let title: LocalizedStringResource = "private.system.discovery.intent.open-assets"
    static let description = IntentDescription("Opens the private Assets destination in the foreground app.")
    static let action = PrivateSystemDiscoveryActionV1.openAssets
}

struct OpenReportsPrivateSystemDiscoveryIntentV1: PrivateSystemDiscoveryForegroundIntentV1 {
    static let title: LocalizedStringResource = "private.system.discovery.intent.open-reports"
    static let description = IntentDescription("Opens the private Reports destination in the foreground app.")
    static let action = PrivateSystemDiscoveryActionV1.openReports
}

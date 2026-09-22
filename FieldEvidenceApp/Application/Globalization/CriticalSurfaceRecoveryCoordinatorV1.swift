import Foundation

/// Resolves display copy from existing semantic identifiers. Localized strings
/// are never notification/deep-link identifiers and never select an action.
enum CriticalSurfaceRecoveryCoordinatorV1 {
    static func presentation(for failure: RecoveryFailurePresentationV1,
                             strings: CriticalSurfaceLocalizationRegistryV1 = .init()) throws -> CriticalRecoveryPresentationV1 {
        try failure.validate()
        return .init(failure: failure, message: strings.failure(failure.code),
            primaryActionKey: actionKey(failure.primaryAction),
            fallbackActionKey: failure.fallbackAction.flatMap(actionKey),
            helpKey: failure.helpTopic.flatMap(helpKey))
    }

    static func actionKey(
        _ action: OperationalActionV1
    ) -> RecoveryCenterLocalizationKeyV1? {
        switch action {
        case .cancel: return .actionCancel
        case .chooseFile: return .actionChooseFile
        case .closeOtherOperation: return .actionCloseOtherOperation
        case .contactSupport: return .actionContactSupport
        case .freeStorage: return .actionFreeStorage
        case .none: return nil
        case .openSettings: return .actionOpenSettings
        case .retry: return .actionRetry
        case .restart: return .actionRestart
        case .resume: return .actionResume
        case .unlockDevice: return .actionUnlockDevice
        }
    }

    static func helpKey(
        _ topic: OperationalHelpTopicV1
    ) -> RecoveryCenterLocalizationKeyV1? {
        switch topic {
        case .backup: return .helpBackup
        case .commerce: return .helpCommerce
        case .diagnosticsReset: return .helpDiagnosticsReset
        case .permissions: return .helpPermissions
        case .reports: return .helpReports
        case .storage: return .helpStorage
        case .supportExport: return .helpSupportExport
        }
    }

}

struct CriticalRecoveryPresentationV1: Equatable, Sendable {
    let failure: RecoveryFailurePresentationV1
    let message: String
    let primaryActionKey: RecoveryCenterLocalizationKeyV1?
    let fallbackActionKey: RecoveryCenterLocalizationKeyV1?
    let helpKey: RecoveryCenterLocalizationKeyV1?
}

import Foundation

/// App-owned critical copy only. Failure codes, routes, permissions, exact
/// confirmation tokens and user-authored text remain with their existing owners.
struct CriticalSurfaceLocalizationRegistryV1 {
    let bundle: Bundle
    let languageLocale: Locale

    init(bundle: Bundle = .main, languageLocale: Locale? = nil) {
        self.bundle = bundle
        self.languageLocale = languageLocale ?? Locale(identifier:
            SystemLanguageResolverV1(bundle: bundle).resolve().effectiveLanguage.rawValue)
    }

    static func failureKey(_ code: OperationalFailureCodeV1) -> String {
        "v30.critical.failure." + code.rawValue.lowercased().replacingOccurrences(of: "_", with: "-")
    }

    static func failureEnglish(_ code: OperationalFailureCodeV1) -> String {
        switch code {
        case .backupExportFailed: return "The backup could not be exported."
        case .backupRestoreFailed: return "The backup could not be restored."
        case .backupSourceChanged: return "The backup source changed. Review it before trying again."
        case .capabilityUnavailable: return "This action is unavailable on this device."
        case .concurrentOperation: return "Another operation needs to finish before you continue."
        case .contentReadFailed: return "The required content could not be read."
        case .commerceUnavailable: return "Purchase information is unavailable. Try again when it is available."
        case .corruptOperationalStore: return "Recovery information could not be validated. Contact support."
        case .diagnosticsWriteFailed: return "Diagnostics could not be saved."
        case .exportCancelled: return "The export was cancelled."
        case .exportFailed: return "The export could not be completed."
        case .interrupted: return "The operation was interrupted. Review its current state before trying again."
        case .partialSafeState: return "Recovery is incomplete. Review the available recovery actions."
        case .permissionDenied: return "Permission was denied. Review access in Settings or use an available alternative."
        case .persistenceMigrationRequired: return "The local data store needs an update before you can continue."
        case .protectedDataUnavailable: return "Unlock this iPhone to access protected local data."
        case .reportRenderFailed: return "The report PDF could not be created."
        case .reportUnavailable: return "The report is unavailable. Review its recovery actions."
        case .requiredFileMissing: return "A required file is missing."
        case .restartRequired: return "Restart the app before continuing."
        case .resumeRequired: return "The operation needs to be resumed."
        case .storageCapacityInsufficient: return "There is not enough available storage for this operation."
        case .storageWriteFailed: return "The data could not be written to storage."
        case .unknown: return "The operation could not be completed. Review the available recovery actions."
        case .userCancelled: return "The operation was cancelled."
        }
    }

    func failure(_ code: OperationalFailureCodeV1) -> String {
        switch code {
        case .backupExportFailed:
            return String(localized: "v30.critical.failure.backup-export-failed", defaultValue: "The backup could not be exported.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: BACKUP_EXPORT_FAILED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .backupRestoreFailed:
            return String(localized: "v30.critical.failure.backup-restore-failed", defaultValue: "The backup could not be restored.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: BACKUP_RESTORE_FAILED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .backupSourceChanged:
            return String(localized: "v30.critical.failure.backup-source-changed", defaultValue: "The backup source changed. Review it before trying again.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: BACKUP_SOURCE_CHANGED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .capabilityUnavailable:
            return String(localized: "v30.critical.failure.capability-unavailable", defaultValue: "This action is unavailable on this device.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: CAPABILITY_UNAVAILABLE. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .concurrentOperation:
            return String(localized: "v30.critical.failure.concurrent-operation", defaultValue: "Another operation needs to finish before you continue.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: CONCURRENT_OPERATION. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .contentReadFailed:
            return String(localized: "v30.critical.failure.content-read-failed", defaultValue: "The required content could not be read.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: CONTENT_READ_FAILED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .commerceUnavailable:
            return String(localized: "v30.critical.failure.commerce-unavailable", defaultValue: "Purchase information is unavailable. Try again when it is available.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: COMMERCE_UNAVAILABLE. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .corruptOperationalStore:
            return String(localized: "v30.critical.failure.corrupt-operational-store", defaultValue: "Recovery information could not be validated. Contact support.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: CORRUPT_OPERATIONAL_STORE. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .diagnosticsWriteFailed:
            return String(localized: "v30.critical.failure.diagnostics-write-failed", defaultValue: "Diagnostics could not be saved.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: DIAGNOSTICS_WRITE_FAILED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .exportCancelled:
            return String(localized: "v30.critical.failure.export-cancelled", defaultValue: "The export was cancelled.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: EXPORT_CANCELLED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .exportFailed:
            return String(localized: "v30.critical.failure.export-failed", defaultValue: "The export could not be completed.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: EXPORT_FAILED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .interrupted:
            return String(localized: "v30.critical.failure.interrupted", defaultValue: "The operation was interrupted. Review its current state before trying again.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: INTERRUPTED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .partialSafeState:
            return String(localized: "v30.critical.failure.partial-safe-state", defaultValue: "Recovery is incomplete. Review the available recovery actions.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: PARTIAL_SAFE_STATE. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .permissionDenied:
            return String(localized: "v30.critical.failure.permission-denied", defaultValue: "Permission was denied. Review access in Settings or use an available alternative.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: PERMISSION_DENIED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .persistenceMigrationRequired:
            return String(localized: "v30.critical.failure.persistence-migration-required", defaultValue: "The local data store needs an update before you can continue.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: PERSISTENCE_MIGRATION_REQUIRED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .protectedDataUnavailable:
            return String(localized: "v30.critical.failure.protected-data-unavailable", defaultValue: "Unlock this iPhone to access protected local data.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: PROTECTED_DATA_UNAVAILABLE. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .reportRenderFailed:
            return String(localized: "v30.critical.failure.report-render-failed", defaultValue: "The report PDF could not be created.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: REPORT_RENDER_FAILED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .reportUnavailable:
            return String(localized: "v30.critical.failure.report-unavailable", defaultValue: "The report is unavailable. Review its recovery actions.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: REPORT_UNAVAILABLE. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .requiredFileMissing:
            return String(localized: "v30.critical.failure.required-file-missing", defaultValue: "A required file is missing.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: REQUIRED_FILE_MISSING. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .restartRequired:
            return String(localized: "v30.critical.failure.restart-required", defaultValue: "Restart the app before continuing.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: RESTART_REQUIRED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .resumeRequired:
            return String(localized: "v30.critical.failure.resume-required", defaultValue: "The operation needs to be resumed.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: RESUME_REQUIRED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .storageCapacityInsufficient:
            return String(localized: "v30.critical.failure.storage-capacity-insufficient", defaultValue: "There is not enough available storage for this operation.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: STORAGE_CAPACITY_INSUFFICIENT. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .storageWriteFailed:
            return String(localized: "v30.critical.failure.storage-write-failed", defaultValue: "The data could not be written to storage.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: STORAGE_WRITE_FAILED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .unknown:
            return String(localized: "v30.critical.failure.unknown", defaultValue: "The operation could not be completed. Review the available recovery actions.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: UNKNOWN. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        case .userCancelled:
            return String(localized: "v30.critical.failure.user-cancelled", defaultValue: "The operation was cancelled.",
                bundle: bundle, locale: languageLocale,
                comment: "Recovery failure: USER_CANCELLED. Visible and accessible status. No arguments. Preserve the exact failure or cancellation meaning; do not imply successful recovery, delivery, or saved data.")
        }
    }

    func status(label: String, state: String) -> String {
        let template = String(localized: "v30.critical.status-with-label", defaultValue: "%1$@: %2$@",
            bundle: bundle, locale: languageLocale,
            comment: "Recovery accessibility announcement. Arguments: localized status label and localized actual state. Both are already translated; allow order changes without changing state.")
        return String(format: template, locale: languageLocale, label, state)
    }

    func messageWithDetail(message: String, detail: String) -> String {
        let template = String(localized: "v30.critical.message-with-detail", defaultValue: "%1$@\n%2$@",
            bundle: bundle, locale: languageLocale,
            comment: "Failure summary followed by contextual recovery detail. Both arguments are already localized app-owned copy. Preserve both; no success claim.")
        return String(format: template, locale: languageLocale, message, detail)
    }

    func eraseInstructions(token: String) -> String {
        let template = String(localized: "v30.critical.erase-confirmation", defaultValue: "Type %@ to confirm.",
            bundle: bundle, locale: languageLocale,
            comment: "Destructive confirmation instruction and accessibility label. Argument is the exact required confirmation token: do not translate, case-fold, normalize, or change that token. Translating instructions never authorizes deletion.")
        return String(format: template, locale: languageLocale, token)
    }
}

enum CriticalPermissionPurposeV1: String, CaseIterable, Sendable {
    case camera = "NSCameraUsageDescription"
    case microphone = "NSMicrophoneUsageDescription"
    case speech = "NSSpeechRecognitionUsageDescription"

    var english: String {
        switch self {
        case .camera: return "Take photos or record short video evidence only when you choose a camera action. Media stays on this iPhone unless you explicitly export or share it."
        case .microphone: return "Record short audio evidence or transcribe voice details only when you choose those actions. Audio evidence stays on this iPhone unless you explicitly export or share it; voice-detail audio is temporary and not archived."
        case .speech: return "Transcribe user-triggered voice details on this iPhone into reviewable structured-work suggestions. You can type instead; voice audio is not archived or sent to a cloud recognition service."
        }
    }

    var capabilities: [CapabilityIDV1] {
        switch self {
        case .camera: return [.camera, .videoCapture]
        case .microphone: return [.microphone, .audioCapture]
        case .speech: return [.speechDictation]
        }
    }
}

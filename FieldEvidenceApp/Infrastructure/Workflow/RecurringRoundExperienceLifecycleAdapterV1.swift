import Foundation
import UserNotifications

/// The system boundary reports observations, never reconciliation receipts.
/// Opaque request identifiers and tokens are the only identifiers sent to iOS.
struct NotificationSystemRequestV1: Codable, Equatable, Sendable {
    let notification: AppLockGenericNotificationV1
    let fireAtUTC: Date

    func validate() throws {
        try notification.validate()
        guard UUID(uuidString: notification.requestID) != nil,
              fireAtUTC.timeIntervalSince1970.isFinite else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }
}

struct NotificationSystemObservationV1: Equatable, Sendable {
    let requestID: String
    /// Nil means an observed request has an unsupported or modified payload.
    let request: NotificationSystemRequestV1?
    let delivered: Bool
}

/// Device-local private correlation. None of these domain values is copied to
/// a system notification. Admissions survive interruption before an add reply.
struct NotificationPrivateMappingV1: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let reminder: ReminderEntryV1
        let request: NotificationSystemRequestV1
        var admissionID: UUID?
        var acknowledged: Bool
    }
    let schemaVersion: Int
    let operationID: UUID
    var source: NotificationSourceSnapshotV1
    let policy: DeviceLocalReminderPolicyV1
    let setting: AppLockStoredSettingSnapshotV1
    let controlSubjectSHA256: String?
    var entries: [Entry]
    var retiring: [NotificationSystemRequestV1]

    var ownedRequestIDs: [String] {
        (entries.map { $0.request.notification.requestID } + retiring.map { $0.notification.requestID }).sorted()
    }

    func validate() throws {
        guard schemaVersion == 1, operationID != SettingsValidationV1.zeroUUID,
              entries.count <= 64, retiring.count <= 64,
              Set(ownedRequestIDs).count == ownedRequestIDs.count,
              Set(entries.map { $0.reminder.notificationID }).count == entries.count,
              Set(entries.compactMap(\.admissionID)).count == entries.compactMap(\.admissionID).count,
              controlSubjectSHA256.map(CompatibilityCanonicalV1.validSHA256) ?? true else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try source.projection.validate()
        try policy.validate()
        for entry in entries {
            try entry.request.validate()
            guard source.projection.reminders.contains(entry.reminder),
                  entry.request.fireAtUTC == entry.reminder.fireAtUTC,
                  entry.admissionID != SettingsValidationV1.zeroUUID,
                  !entry.acknowledged || entry.admissionID == nil else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        try retiring.forEach { try $0.validate() }
    }
}

/// Content-blind irreversible publication revocation. It is an erase marker,
/// not a second notification journal or a replacement canonical policy.
struct NotificationEraseRevocationV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let operationID: UUID
    let rootIdentity: String

    func validate() throws {
        guard schemaVersion == 1, operationID != SettingsValidationV1.zeroUUID,
              !rootIdentity.isEmpty else { throw AppAccessContractFailureV1.configurationUnknown }
    }
}

@MainActor protocol NotificationSystemPortV1: AnyObject {
    func authorization() async throws -> LocalReminderAuthorizationV1
    func observations() async throws -> [NotificationSystemObservationV1]
    func add(_ request: NotificationSystemRequestV1) async throws
    func remove(_ requestIDs: [String]) async throws
}

/// A scheduling acknowledgement is not readback. Removal is also asynchronous
/// at the OS boundary; the owner must subsequently inspect actual absence.
@MainActor final class UserNotificationSystemAdapterV1: NotificationSystemPortV1 {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func authorization() async throws -> LocalReminderAuthorizationV1 {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }

    func observations() async throws -> [NotificationSystemObservationV1] {
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        return pending.map { Self.observation($0, delivered: false) }
            + delivered.map { Self.observation($0.request, delivered: true) }
    }

    func add(_ request: NotificationSystemRequestV1) async throws {
        try await center.add(Self.systemRequest(request))
    }

    static func systemRequest(_ request: NotificationSystemRequestV1) throws -> UNNotificationRequest {
        try request.validate()
        let content = UNMutableNotificationContent()
        content.title = request.notification.title
        content.body = request.notification.body
        content.userInfo = ["token": request.notification.opaqueCorrelationToken]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: request.fireAtUTC)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: request.notification.requestID,
            content: content, trigger: trigger)
    }

    func remove(_ requestIDs: [String]) async throws {
        center.removePendingNotificationRequests(withIdentifiers: requestIDs)
        center.removeDeliveredNotifications(withIdentifiers: requestIDs)
    }

    static func observation(_ request: UNNotificationRequest,
                                    delivered: Bool) -> NotificationSystemObservationV1 {
        let content = request.content
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats,
              let calendar = trigger.dateComponents.calendar,
              calendar.identifier == .gregorian,
              trigger.dateComponents.timeZone?.secondsFromGMT() == 0,
              let fire = calendar.date(from: trigger.dateComponents),
              content.userInfo.count == 1, let token = content.userInfo["token"] as? String,
              content.subtitle.isEmpty, content.attachments.isEmpty,
              content.categoryIdentifier.isEmpty, content.threadIdentifier.isEmpty,
              content.launchImageName.isEmpty, content.sound == nil, content.badge == nil,
              content.targetContentIdentifier == nil else {
            return .init(requestID: request.identifier, request: nil, delivered: delivered)
        }
        let value = NotificationSystemRequestV1(notification: .init(requestID: request.identifier,
            opaqueCorrelationToken: token, title: content.title, body: content.body), fireAtUTC: fire)
        guard let canonical = try? systemRequest(value),
              let canonicalTrigger = canonical.trigger as? UNCalendarNotificationTrigger,
              trigger.dateComponents == canonicalTrigger.dateComponents,
              content.interruptionLevel == canonical.content.interruptionLevel,
              content.relevanceScore == canonical.content.relevanceScore,
              content.summaryArgument == canonical.content.summaryArgument,
              content.summaryArgumentCount == canonical.content.summaryArgumentCount,
              content.filterCriteria == canonical.content.filterCriteria,
              // Include system metadata outside the reduced app payload, such as
              // content supplied by a communication intent. Fail closed on drift.
              content.isEqual(canonical.content) else {
            return .init(requestID: request.identifier, request: nil, delivered: delivered)
        }
        return .init(requestID: request.identifier, request: value, delivered: delivered)
    }
}

/// Shared across every physical owner of the same pinned root in this process.
/// Durable admissions remain authoritative when no corresponding task survives.
@MainActor private enum NotificationAddDrainV1 {
    private static var active: [String: Set<UUID>] = [:]
    private static var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    static func begin(root: String, admission: UUID) throws {
        guard active[root, default: []].insert(admission).inserted else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    static func finish(root: String, admission: UUID) {
        active[root]?.remove(admission)
        if active[root]?.isEmpty != false {
            active.removeValue(forKey: root)
            let ready = waiters.removeValue(forKey: root) ?? []
            ready.forEach { $0.resume() }
        }
    }

    static func isActive(root: String) -> Bool { active[root]?.isEmpty == false }

    static func wait(root: String) async {
        guard isActive(root: root) else { return }
        await withCheckedContinuation { waiters[root, default: []].append($0) }
    }
}

/// One unadopted production effect owns AppLock completion and ordinary C22
/// scheduling. Its required source opener remains unopened during bootstrap
/// and erase; it returns only the incumbent concrete canonical source owner.
@MainActor final class DeviceLocalNotificationOwnerV1: AppLockNotificationEffectPortV1,
    DeviceLocalAppLockSettingPortV1, DeviceLocalScheduleReminderPortV1 {
    typealias SourceOpener = @MainActor @Sendable (NotificationOperationAuthorizationV1) async throws -> ProductionMyDaySourceProviderV1
    private let control: AppLockNotificationControlStoreV1
    private let preferences: PreferencesAdapterV1
    private let system: any NotificationSystemPortV1
    private let openSource: SourceOpener
    private let clock: any ApplicationClock
    private var boundGate: AppAccessGateV1?

    init(control: AppLockNotificationControlStoreV1, preferences: PreferencesAdapterV1,
         system: any NotificationSystemPortV1, clock: any ApplicationClock,
         openSource: @escaping SourceOpener) {
        self.control = control; self.preferences = preferences; self.system = system
        self.clock = clock; self.openSource = openSource
    }

    func bindNotificationGateEffect(_ gate: AppAccessGateV1) async throws {
        if let boundGate {
            guard boundGate === gate else { throw AppAccessContractFailureV1.accessDenied }
        } else { boundGate = gate }
    }

    func loadJournalEffect() async throws -> AppLockNotificationJournalV1? { try control.loadControl()?.journal }

    func loadAuthenticationSubjectEffect() async throws -> NotificationOperationSubjectV1? {
        try control.loadControl().map(NotificationOperationSubjectV1.init(control:))
    }

    func readAppLockSetting() async -> DeviceLocalAppLockSettingReadV1 {
        do {
            guard let value = try preferences.readAppLockSettingSnapshot().setting else { return .absentDisabled }
            return .value(value)
        } catch { return .corruptOrAmbiguous }
    }

    func validatesLocalConfigurationEffect(_ setting: DeviceLocalAppLockSettingReadV1) async throws -> Bool {
        try control.requireNotificationPublicationAllowed()
        let stored = try preferences.readAppLockSettingSnapshot()
        let actual = try stored.setting.map(DeviceLocalAppLockSettingReadV1.value) ?? .absentDisabled
        guard actual == setting else { return false }
        guard let value = try control.loadControl() else {
            return actual == .absentDisabled || actual == .value(.init(isEnabled: false))
        }
        guard value.phase == .settingCommitted, stored == value.settingWrite.successor,
              try preferences.readStoredReminderPolicy() == value.settingWrite.expectedReminderPolicy else { return false }
        if value.journal.targetEnabled {
            return value.journal.disposition == .genericProjectionApplied || value.journal.disposition == .genericProjectionAdopted
        }
        return value.journal.disposition == .priorPolicyRebuilt
    }

    func prepareEnableEffect(operationID: UUID, expectedPredecessor: AppLockNotificationJournalV1?,
                             authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await prepare(operationID: operationID, target: true, expected: expectedPredecessor, authorization: authorization)
    }

    func prepareDisableEffect(operationID: UUID, expectedPredecessor: AppLockNotificationJournalV1?,
                              authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await prepare(operationID: operationID, target: false, expected: expectedPredecessor, authorization: authorization)
    }

    private func prepare(operationID: UUID, target: Bool, expected: AppLockNotificationJournalV1?,
                         authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await validate(authorization, target: target)
        let predecessor = try control.loadControl()
        guard predecessor?.journal == expected,
              try predecessor.map(NotificationOperationSubjectV1.init(control:)) == authorization.subject else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let policy = try currentPolicy()
        // No approved detailed content has been selected. Reject before any
        // preparation or OS effect; never reinterpret saved consent as generic.
        if !target { try requireSupportedPolicy(policy, appLockEnabled: false) }
        let source = try await source(for: authorization)
        let beforeMapping = try await configurationMapping(source: source, authorization: authorization)
        let snapshot: NotificationSourceSnapshotV1
        if let beforeMapping, beforeMapping.operationID == operationID {
            snapshot = beforeMapping.source
            try await source.validateNotificationSnapshot(snapshot, authorization: authorization)
        } else {
            snapshot = try await source.notificationSnapshot(authorization: authorization, evaluatedAt: clock.now())
        }
        try await validate(authorization, target: target)
        if let predecessor, predecessor.journal.operationID == operationID {
            guard predecessor.journal.targetEnabled == target,
                  let mapping = beforeMapping, mapping.operationID == operationID,
                  mapping.controlSubjectSHA256 == (try NotificationOperationSubjectV1(control: predecessor).immutableSHA256()) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try await source.validateNotificationSnapshot(mapping.source, authorization: authorization)
            try await validate(authorization, target: target)
            try verifyMapping(mapping, source: source, authorization: authorization, settingMayBeSuccessor: predecessor)
            return predecessor.journal
        }
        if let predecessor {
            guard predecessor.phase == .settingCommitted,
                  predecessor.journal.targetEnabled != target else { throw AppAccessContractFailureV1.effectMismatch }
        }
        guard !NotificationAddDrainV1.isActive(root: control.notificationRootIdentity),
              beforeMapping?.entries.allSatisfy({ $0.admissionID == nil }) ?? true else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let desired = policy.isEnabled ? snapshot.projection.reminders : []
        try requireSchedulable(desired)
        if !desired.isEmpty {
            let availability = try await system.authorization()
            try await validate(authorization, target: target)
            guard availability == .authorized else { throw AppAccessContractFailureV1.notificationReconciliationRequired }
        }
        let setting = try preferences.readAppLockSettingSnapshot()
        let plan = try preferences.planAppLockSettingWrite(expectedSetting: setting,
            expectedReminderPolicy: policy, target: .init(isEnabled: target), operationID: operationID)
        let historical = target ? policy : predecessor?.priorReminderPolicy ?? policy
        let entries: [NotificationPrivateMappingV1.Entry]
        if let beforeMapping, beforeMapping.operationID == operationID {
            // Recover only an exact mapping-first preparation, never regenerate
            // IDs or reinterpret its original source after interruption.
            guard beforeMapping.source == snapshot, beforeMapping.policy == policy,
                  beforeMapping.setting == setting,
                  beforeMapping.entries.map(\.reminder) == desired else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            entries = beforeMapping.entries
        } else { entries = try desired.map(makeEntry) }
        let journal = try AppLockNotificationJournalV1(operationID: operationID, targetEnabled: target,
            priorPolicy: historical.appLockReference(), projections: entries.map { $0.request.notification },
            disposition: target ? .enablingPrepared : .disablingPrepared)
        let candidate = try AppLockNotificationControlV1(journal: journal, priorReminderPolicy: historical, settingWrite: plan)
        if let beforeMapping, beforeMapping.operationID == operationID {
            guard beforeMapping.controlSubjectSHA256 == (try NotificationOperationSubjectV1(control: candidate).immutableSHA256()) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        let retiring = beforeMapping?.operationID == operationID ? beforeMapping?.retiring ?? []
            : (beforeMapping?.entries.map(\.request) ?? []) + (beforeMapping?.retiring ?? [])
        let mapping = NotificationPrivateMappingV1(schemaVersion: 1, operationID: operationID,
            source: snapshot, policy: policy, setting: setting,
            controlSubjectSHA256: try NotificationOperationSubjectV1(control: candidate).immutableSHA256(),
            entries: entries, retiring: retiring)
        try await source.validateNotificationSnapshot(snapshot, authorization: authorization)
        try await validate(authorization, target: target)
        return try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
          try AppLockNotificationTransactionFenceV1.perform {
            guard try currentPolicy() == policy, try preferences.readAppLockSettingSnapshot() == setting,
                  try control.loadControl() == predecessor else { throw AppAccessContractFailureV1.effectMismatch }
            if beforeMapping != mapping {
                try control.replacePrivateNotificationMapping(mapping, expected: beforeMapping)
            }
            return try control.prepareControl(journal: journal, priorReminderPolicy: historical,
                settingWrite: plan, expectedPredecessor: predecessor).journal
          }
        }
    }

    func publishGenericEffect(expected: AppLockNotificationJournalV1,
                              authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await reconcileControl(expected: expected, target: true, authorization: authorization)
    }

    func rebuildPriorPolicyEffect(expected: AppLockNotificationJournalV1,
                                  authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await reconcileControl(expected: expected, target: false, authorization: authorization)
    }

    private func reconcileControl(expected: AppLockNotificationJournalV1, target: Bool,
                                  authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        try await validate(authorization, target: target)
        let value = try exactControl(expected, authorization: authorization)
        if !target {
            try requireSupportedPolicy(currentPolicy(), appLockEnabled: false)
            guard value.phase == .settingCommitted,
                  try preferences.readAppLockSettingSnapshot() == value.settingWrite.successor else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
        let source = try await source(for: authorization)
        guard let mapping = try await configurationMapping(source: source, authorization: authorization),
              mapping.operationID == expected.operationID else { throw AppAccessContractFailureV1.notificationReconciliationRequired }
        try await reconcile(mapping, source: source, authorization: authorization, settingControl: value)
        try await validate(authorization, target: target)
        let latest = try exactControl(expected, authorization: authorization)
        let disposition: AppLockNotificationPrivacyDispositionV1 = target
            ? (expected.disposition == .genericProjectionAdopted ? .genericProjectionAdopted : .genericProjectionApplied)
            : .priorPolicyRebuilt
        let result = try AppLockNotificationJournalV1(operationID: expected.operationID, targetEnabled: target,
            priorPolicy: expected.priorPolicy, projections: expected.projections, disposition: disposition)
        return try control.recordJournal(result, expected: latest).journal
    }

    func writeAppLockSetting(_ value: DeviceLocalAppLockSettingV1, operationID: UUID,
                            authorization: NotificationOperationAuthorizationV1) async throws -> DeviceLocalAppLockSettingWriteReceiptV1 {
        try await validate(authorization, target: value.isEnabled)
        guard operationID == authorization.operationID, let subject = authorization.subject else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let current = try exactControl(subject.journal, authorization: authorization, allowAdvancedPhase: true)
        guard current.settingWrite.target == value else { throw AppAccessContractFailureV1.effectMismatch }
        // A completed journal cannot substitute for current OS evidence.
        if value.isEnabled {
            let source = try await source(for: authorization)
            guard let mapping = try await configurationMapping(source: source, authorization: authorization) else { throw AppAccessContractFailureV1.notificationReconciliationRequired }
            try await verifySystem(mapping, source: source, authorization: authorization, settingControl: current)
        }
        try await validate(authorization, target: value.isEnabled)
        let exact = try exactControl(current.journal, authorization: authorization)
        let adopted = try preferences.readAppLockSettingSnapshot() == exact.settingWrite.successor
        _ = try control.completeSetting(expected: exact)
        try await validate(authorization, target: value.isEnabled)
        return .init(operationID: operationID, value: value, adoptedExistingEffect: adopted)
    }

    func eraseAppLockSetting(operationID: UUID) async throws {
        let revocation = try control.beginNotificationErase(operationID: operationID)
        guard try control.loadControl() == nil, try control.loadPrivateNotificationMapping() == nil else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalAppLockSettingV1.key)
        try preferences.erase(descriptors: [descriptor], operationID: revocation.operationID)
    }

    func resolveOpaqueTokenEffect(_ token: String, now: Date,
                                  authorization: NotificationOperationAuthorizationV1) async throws -> String? {
        try await validate(authorization)
        let source = try await source(for: authorization)
        guard let mapping = try control.loadPrivateNotificationMapping() else { return nil }
        try await source.validateNotificationSnapshot(mapping.source, authorization: authorization)
        try await validate(authorization)
        try verifyMapping(mapping, source: source, authorization: authorization,
                          settingMayBeSuccessor: control.loadControl())
        guard now.timeIntervalSince1970.isFinite,
              let entry = mapping.entries.first(where: { $0.request.notification.opaqueCorrelationToken == token }),
              entry.acknowledged, entry.admissionID == nil else { return nil }
        // This is a private domain ID; no route is ever sent to the system.
        return entry.reminder.notificationID
    }

    func eraseNotificationsAndMappingsEffect(operationID: UUID) async throws {
        try await Self.erase(control: control, system: system, operationID: operationID)
    }

    func reconcile(_ projection: ReminderProjectionV1) async throws -> LocalReminderReconciliationV1 {
        let authorization = try await contentAuthorization()
        let source = try await source(for: authorization)
        let snapshot = try await source.notificationSnapshot(authorization: authorization, evaluatedAt: projection.evaluatedAt)
        guard snapshot.projection == projection else { throw MyDaySourceReadFailureV1.sourcesChanged }
        let policy = try currentPolicy()
        // A caller cannot turn a canonical due projection into renewed consent.
        // The opt-out route removes requests explicitly through removeAll.
        guard policy.isEnabled else { throw AppAccessContractFailureV1.accessDenied }
        let setting = try preferences.readAppLockSettingSnapshot()
        let localControl = try ordinaryControl(setting: setting)
        try requireSupportedPolicy(policy, appLockEnabled: setting.setting?.isEnabled == true)
        let before = try control.loadPrivateNotificationMapping()
        let observedSystem = try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
            try await self.system.observations()
        }
        let availability = try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
            try await self.system.authorization()
        }
        try await validate(authorization)
        guard try control.loadPrivateNotificationMapping() == before,
              try currentPolicy() == policy,
              try preferences.readAppLockSettingSnapshot() == setting,
              try control.loadControl() == localControl else { throw AppAccessContractFailureV1.effectMismatch }
        let observed = (before?.entries ?? []).compactMap { entry -> ReminderEntryV1? in
            let matches = observedSystem.filter { $0.requestID == entry.request.notification.requestID }
            return matches.count == 1 && matches[0].request == entry.request ? entry.reminder : nil
        }
        let plan = try LocalReminderReconciliationV1(projection: projection,
            observedReminderEntries: observed, authorization: availability)
        guard availability == .authorized else { return plan }
        try requireSchedulable(projection.reminders.filter { desired in
            !(before?.entries.contains(where: { $0.reminder == desired && observed.contains(desired) }) ?? false)
        })
        let mapping = try replacementMapping(before: before, source: snapshot, policy: policy,
            setting: setting, localControl: localControl, desired: projection.reminders, operationID: authorization.operationID)
        try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
            guard try self.currentPolicy() == policy, try self.preferences.readAppLockSettingSnapshot() == setting,
                  try self.control.loadControl() == localControl else { throw AppAccessContractFailureV1.effectMismatch }
            try self.control.replacePrivateNotificationMapping(mapping, expected: before)
        }
        try await reconcile(mapping, source: source, authorization: authorization, settingControl: localControl)
        return plan
    }

    func removeAll(workspaceID: WorkspaceID) async throws {
        let authorization = try await contentAuthorization()
        let source = try await source(for: authorization)
        let snapshot = try await source.notificationSnapshot(authorization: authorization, evaluatedAt: clock.now())
        guard snapshot.projection.workspaceID == workspaceID else { throw AppAccessContractFailureV1.accessDenied }
        let policy = try currentPolicy()
        let setting = try preferences.readAppLockSettingSnapshot()
        let localControl = try ordinaryControl(setting: setting)
        let before = try control.loadPrivateNotificationMapping()
        let mapping = try replacementMapping(before: before, source: snapshot, policy: policy,
            setting: setting, localControl: localControl, desired: [], operationID: authorization.operationID)
        try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
            guard try self.currentPolicy() == policy, try self.preferences.readAppLockSettingSnapshot() == setting,
                  try self.control.loadControl() == localControl else { throw AppAccessContractFailureV1.effectMismatch }
            try self.control.replacePrivateNotificationMapping(mapping, expected: before)
        }
        try await reconcile(mapping, source: source, authorization: authorization, settingControl: localControl)
    }

    private func contentAuthorization() async throws -> NotificationOperationAuthorizationV1 {
        guard let boundGate else { throw AppAccessContractFailureV1.accessDenied }
        let token = try await boundGate.beginContentRead(for: .render)
        let authorization = NotificationOperationAuthorizationV1(gate: boundGate, proof: .content(token),
            operationID: UUID(), subject: nil)
        try await validate(authorization)
        return authorization
    }

    private func ordinaryControl(setting: AppLockStoredSettingSnapshotV1) throws -> AppLockNotificationControlV1? {
        let value = try control.loadControl()
        if let value {
            guard value.phase == .settingCommitted, value.settingWrite.successor == setting else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        } else if setting.setting?.isEnabled == true {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        return value
    }

    private func replacementMapping(before: NotificationPrivateMappingV1?, source: NotificationSourceSnapshotV1,
                                    policy: DeviceLocalReminderPolicyV1, setting: AppLockStoredSettingSnapshotV1,
                                    localControl: AppLockNotificationControlV1?, desired: [ReminderEntryV1],
                                    operationID: UUID) throws -> NotificationPrivateMappingV1 {
        guard before?.entries.allSatisfy({ $0.admissionID == nil }) ?? true,
              !NotificationAddDrainV1.isActive(root: control.notificationRootIdentity) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let entries = try desired.map { reminder in
            try before?.entries.first(where: { $0.reminder == reminder }) ?? makeEntry(reminder)
        }
        let retained = Set(entries.map { $0.request.notification.requestID })
        let retiring = (before?.retiring ?? []) + (before?.entries.map(\.request) ?? [])
            .filter { !retained.contains($0.notification.requestID) }
        let result = NotificationPrivateMappingV1(schemaVersion: 1, operationID: operationID,
            source: source, policy: policy, setting: setting,
            controlSubjectSHA256: try localControl.map { try NotificationOperationSubjectV1(control: $0).immutableSHA256() },
            entries: entries, retiring: retiring)
        try result.validate()
        return result
    }

    /// The same source-free implementation serves actual EraseAll recovery.
    static func erase(control: AppLockNotificationControlStoreV1, system: any NotificationSystemPortV1,
                      operationID: UUID) async throws {
        let revocation = try control.beginNotificationErase(operationID: operationID)
        await NotificationAddDrainV1.wait(root: control.notificationRootIdentity)
        try control.verifyNotificationStorage()
        let mapping = try control.loadPrivateNotificationMapping()
        guard mapping?.entries.allSatisfy({ $0.admissionID == nil }) ?? true else {
            // A killed process may leave an unacknowledged system add. Neither
            // an absent runtime task nor an empty OS snapshot proves its drain.
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let journal = try control.loadControl()?.journal
        let owned = Set((mapping?.ownedRequestIDs ?? []) + (journal?.projections.map(\.requestID) ?? []))
        try await system.remove(owned.sorted())
        try control.verifyNotificationStorage()
        let observed = try await system.observations()
        try control.verifyNotificationStorage()
        guard !observed.contains(where: { owned.contains($0.requestID) }),
              !NotificationAddDrainV1.isActive(root: control.notificationRootIdentity),
              try control.loadPrivateNotificationMapping() == mapping,
              try control.loadControl()?.journal == journal else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try control.removeNotificationRecordsAfterErase(revocation)
    }

    private func validate(_ authorization: NotificationOperationAuthorizationV1, target: Bool? = nil) async throws {
        guard let boundGate, boundGate === authorization.gate else { throw AppAccessContractFailureV1.accessDenied }
        if let target { try await authorization.validateMutation(operationID: authorization.operationID, targetEnabled: target) }
        else { try await authorization.validateRead() }
        try control.requireNotificationPublicationAllowed()
    }

    private func source(for authorization: NotificationOperationAuthorizationV1) async throws -> ProductionMyDaySourceProviderV1 {
        try await validate(authorization)
        let source = try await openSource(authorization)
        try await validate(authorization)
        return source
    }

    private func currentPolicy() throws -> DeviceLocalReminderPolicyV1 {
        guard let policy = try preferences.readStoredReminderPolicy() else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        return policy
    }

    private func configurationMapping(source: ProductionMyDaySourceProviderV1,
                                      authorization: NotificationOperationAuthorizationV1) async throws -> NotificationPrivateMappingV1? {
        try await validate(authorization)
        guard let original = try control.loadPrivateNotificationMapping() else { return nil }
        // Only the original configuration operation may rebind its persisted
        // ephemeral writer identity. A new toggle derives its own fresh source.
        guard original.operationID == authorization.operationID else { return original }
        let snapshot = try await source.revalidatePersistedNotificationSnapshot(original.source, authorization: authorization)
        if snapshot == original.source { return original }
        var rebound = original
        rebound.source = snapshot
        try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
            if let current = try self.control.loadControl() {
                try self.verifyMapping(original, source: source, authorization: authorization,
                    settingMayBeSuccessor: current)
            } else {
                // A mapping-first interrupted prepare retains its subject hash;
                // prepare must match it to the exact setting plan before any OS
                // effect or control publication can follow this rebind.
                guard authorization.subject == nil, original.controlSubjectSHA256 != nil,
                      try self.preferences.readAppLockSettingSnapshot() == original.setting,
                      try self.currentPolicy() == original.policy else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            try self.control.replacePrivateNotificationMapping(rebound, expected: original)
        }
        return rebound
    }

    private func observe(_ mapping: NotificationPrivateMappingV1,
                         source: ProductionMyDaySourceProviderV1,
                         authorization: NotificationOperationAuthorizationV1,
                         settingControl: AppLockNotificationControlV1?) async throws -> [NotificationSystemObservationV1] {
        let observations = try await source.performNotificationEffect(snapshot: mapping.source, authorization: authorization) {
            try self.verifyMapping(mapping, source: source, authorization: authorization,
                                   settingMayBeSuccessor: settingControl)
            return try await self.system.observations()
        }
        try await validate(authorization)
        try verifyMapping(mapping, source: source, authorization: authorization,
                          settingMayBeSuccessor: settingControl)
        return observations
    }

    private func verifySystem(_ mapping: NotificationPrivateMappingV1,
                              source: ProductionMyDaySourceProviderV1,
                              authorization: NotificationOperationAuthorizationV1,
                              settingControl: AppLockNotificationControlV1?) async throws {
        let observed = try await observe(mapping, source: source, authorization: authorization, settingControl: settingControl)
        let retiring = Set(mapping.retiring.map { $0.notification.requestID })
        guard mapping.entries.allSatisfy({ $0.admissionID == nil && $0.acknowledged }),
              !observed.contains(where: { retiring.contains($0.requestID) }) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        for entry in mapping.entries {
            let matches = observed.filter { $0.requestID == entry.request.notification.requestID }
            guard matches.count == 1, matches[0].request == entry.request else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
    }

    private func reconcile(_ original: NotificationPrivateMappingV1,
                           source: ProductionMyDaySourceProviderV1,
                           authorization: NotificationOperationAuthorizationV1,
                           settingControl: AppLockNotificationControlV1?) async throws {
        var mapping = original
        guard mapping.entries.allSatisfy({ $0.admissionID == nil }),
              !NotificationAddDrainV1.isActive(root: control.notificationRootIdentity) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        if !mapping.retiring.isEmpty {
            let retiring = Set(mapping.retiring.map { $0.notification.requestID })
            try await source.performNotificationEffect(snapshot: mapping.source, authorization: authorization) {
                try self.verifyMapping(mapping, source: source, authorization: authorization,
                                       settingMayBeSuccessor: settingControl)
                try await self.system.remove(retiring.sorted())
            }
            let observed = try await observe(mapping, source: source, authorization: authorization, settingControl: settingControl)
            guard !observed.contains(where: { retiring.contains($0.requestID) }) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let previous = mapping
            mapping.retiring = []
            try control.replacePrivateNotificationMapping(mapping, expected: previous)
        }
        for index in mapping.entries.indices {
            let request = mapping.entries[index].request
            let observed = try await observe(mapping, source: source, authorization: authorization, settingControl: settingControl)
            let matches = observed.filter { $0.requestID == request.notification.requestID }
            if matches.count == 1, matches[0].request == request {
                let previous = mapping
                mapping.entries[index].acknowledged = true
                try control.replacePrivateNotificationMapping(mapping, expected: previous)
                continue
            }
            guard request.fireAtUTC > clock.now() else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let availability = try await source.performNotificationEffect(snapshot: mapping.source, authorization: authorization) {
                try self.verifyMapping(mapping, source: source, authorization: authorization,
                                       settingMayBeSuccessor: settingControl)
                return try await self.system.authorization()
            }
            try await validate(authorization)
            try verifyMapping(mapping, source: source, authorization: authorization, settingMayBeSuccessor: settingControl)
            guard availability == .authorized else { throw AppAccessContractFailureV1.notificationReconciliationRequired }
            let admission = UUID()
            let previous = mapping
            mapping.entries[index].admissionID = admission
            mapping.entries[index].acknowledged = false
            try control.replacePrivateNotificationMapping(mapping, expected: previous)
            let root = control.notificationRootIdentity
            try NotificationAddDrainV1.begin(root: root, admission: admission)
            do {
                defer { NotificationAddDrainV1.finish(root: root, admission: admission) }
                do {
                    try await source.performNotificationEffect(snapshot: mapping.source, authorization: authorization) {
                        try self.verifyMapping(mapping, source: source, authorization: authorization,
                                               settingMayBeSuccessor: settingControl)
                        // Remove a changed payload or duplicate before replacing
                        // this positively owned opaque request.
                        if !matches.isEmpty { try await self.system.remove([request.notification.requestID]) }
                        try await self.validate(authorization)
                        try await source.validateNotificationSnapshot(mapping.source, authorization: authorization)
                        try self.verifyMapping(mapping, source: source, authorization: authorization,
                                               settingMayBeSuccessor: settingControl)
                        try await self.system.add(request)
                    }
                    let after = try await observe(mapping, source: source, authorization: authorization, settingControl: settingControl)
                        .filter { $0.requestID == request.notification.requestID }
                    guard after.count == 1, after[0].request == request else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    try control.finishNotificationAdd(admissionID: admission,
                        requestID: request.notification.requestID, verifiedPresent: true)
                    mapping.entries[index].admissionID = nil
                    mapping.entries[index].acknowledged = true
                } catch {
                    // Cleanup retains the original admission until actual OS
                    // absence is observed, including after erase revocation.
                    try await system.remove([request.notification.requestID])
                    let remaining = try await system.observations()
                    try control.verifyNotificationStorage()
                    guard !remaining.contains(where: { $0.requestID == request.notification.requestID }) else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    try control.finishNotificationAdd(admissionID: admission,
                        requestID: request.notification.requestID, verifiedPresent: false)
                    throw error
                }
            }
        }
        try await verifySystem(mapping, source: source, authorization: authorization, settingControl: settingControl)
    }

    private func requireSupportedPolicy(_ policy: DeviceLocalReminderPolicyV1, appLockEnabled: Bool) throws {
        guard !policy.isEnabled || policy.detail == .generic || appLockEnabled else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }

    private func requireSchedulable(_ entries: [ReminderEntryV1]) throws {
        guard entries.count <= 64, entries.allSatisfy({ $0.fireAtUTC > clock.now() }) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }

    private func makeEntry(_ reminder: ReminderEntryV1) throws -> NotificationPrivateMappingV1.Entry {
        let request = NotificationSystemRequestV1(notification: .init(requestID: UUID().uuidString.lowercased(),
            opaqueCorrelationToken: CompatibilityCanonicalV1.sha256(Data(UUID().uuidString.utf8))), fireAtUTC: reminder.fireAtUTC)
        try request.validate()
        return .init(reminder: reminder, request: request, admissionID: nil, acknowledged: false)
    }

    private func exactControl(_ journal: AppLockNotificationJournalV1,
                              authorization: NotificationOperationAuthorizationV1,
                              allowAdvancedPhase: Bool = false) throws -> AppLockNotificationControlV1 {
        guard let current = try control.loadControl(), let subject = authorization.subject,
              subject.hasSameImmutableSubject(as: try .init(control: current)),
              current.journal.operationID == authorization.operationID,
              allowAdvancedPhase || current.journal == journal else { throw AppAccessContractFailureV1.effectMismatch }
        return current
    }

    private func verifyMapping(_ mapping: NotificationPrivateMappingV1, source: ProductionMyDaySourceProviderV1,
                               authorization: NotificationOperationAuthorizationV1,
                               settingMayBeSuccessor: AppLockNotificationControlV1? = nil) throws {
        try control.requireNotificationPublicationAllowed()
        try mapping.validate()
        guard try control.loadPrivateNotificationMapping() == mapping,
              try currentPolicy() == mapping.policy else { throw AppAccessContractFailureV1.effectMismatch }
        let setting = try preferences.readAppLockSettingSnapshot()
        if let settingMayBeSuccessor {
            guard try control.loadControl() == settingMayBeSuccessor,
                  mapping.controlSubjectSHA256 == (try NotificationOperationSubjectV1(control: settingMayBeSuccessor).immutableSHA256()),
                  setting == mapping.setting || setting == settingMayBeSuccessor.settingWrite.successor else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        } else {
            guard try control.loadControl() == nil, mapping.controlSubjectSHA256 == nil,
                  setting == mapping.setting else { throw AppAccessContractFailureV1.effectMismatch }
        }
    }
}

@MainActor protocol DeviceLocalScheduleReminderPortV1: AnyObject {
    func reconcile(_ projection: ReminderProjectionV1) async throws -> LocalReminderReconciliationV1
    func removeAll(workspaceID: WorkspaceID) async throws
}

/// Concrete reconciliation over an injected OS notification port. It owns no
/// database and a denial, eviction, or process kill cannot change due truth.
@MainActor final class DeviceLocalScheduleReminderReconcilerV1: LocalReminderReconciliationApplyingV1 {
    private let port: any DeviceLocalScheduleReminderPortV1
    init(port: any DeviceLocalScheduleReminderPortV1) { self.port = port }

    func reconcile(_ projection: ReminderProjectionV1) async throws -> LocalReminderReconciliationV1 {
        try await port.reconcile(projection)
    }

    func removeAll(workspaceID: WorkspaceID) async throws {
        try await port.removeAll(workspaceID: workspaceID)
    }
}

/// Recovery/query bridge over the incumbent journal-backed schedule adapter.
/// Callers must provide the exact historic values; there is no latest fallback.
@MainActor final class RecurringRoundExperienceLifecycleAdapterV1 {
    private let writer: any ScheduleCanonicalWritingV1
    init(writer: any ScheduleCanonicalWritingV1) { self.writer = writer }

    func acceptedStart(_ request: RecurringRoundStartRequestV1,
                       readiness: RecurringRoundStartReadinessV1,
                       currentRoundSession: RoundSessionV1? = nil,
                       exactWorkPacket: WorkPacketManifestV1? = nil) throws -> RecurringRoundStartReceiptV1? {
        try request.validate()
        try RecurringRoundStartFrontierBoundaryV1.validate(request: request,
            currentRoundSession: currentRoundSession, exactWorkPacket: exactWorkPacket)
        try readiness.requireReady()
        guard readiness.workspaceID == request.event.workspaceID,
              readiness.requestSHA256 == request.requestSHA256,
              readiness.workInstance == request.event.workInstance else {
            throw RecurringRoundExperienceFailureV1.staleSource
        }
        let mutation = try ScheduleMutationV1(workspaceID: request.event.workspaceID,
            mutationID: request.event.mutationID,
            payload: .startOccurrence(request.event, predecessor: request.predecessor,
                                      release: request.release))
        guard let receipt = try writer.acceptedScheduleMutation(mutation) else { return nil }
        return try .init(request: request, scheduleReceipt: receipt)
    }
}

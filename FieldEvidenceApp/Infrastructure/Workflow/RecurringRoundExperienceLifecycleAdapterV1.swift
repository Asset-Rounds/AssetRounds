import Foundation
import UserNotifications

/// Canonical display data only. The owner independently derives the expected
/// kind and text from its authenticated schedule source before any OS effect.
struct ReminderSystemDetailV1: Codable, Equatable, Sendable {
    let kind: ScheduledWorkKindV1
    let body: String

    var title: String { kind == .roundSession ? "Round due" : "Work due" }

    static func make(kind: ScheduledWorkKindV1, fireAtUTC: Date, frozenUTCOffsetSeconds: Int) throws -> Self {
        guard fireAtUTC.timeIntervalSince1970.isFinite,
              (-64_800...64_800).contains(frozenUTCOffsetSeconds), frozenUTCOffsetSeconds % 60 == 0,
              let zone = TimeZone(secondsFromGMT: frozenUTCOffsetSeconds) else { throw AppAccessContractFailureV1.invalidValue }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        let offset = String(format: "UTC%@%02d:%02d", frozenUTCOffsetSeconds < 0 ? "−" : "+",
            abs(frozenUTCOffsetSeconds) / 3600, (abs(frozenUTCOffsetSeconds) % 3600) / 60)
        let value = Self(kind: kind, body: "Due \(formatter.string(from: fireAtUTC)) (\(offset)). Open AssetRounds to review.")
        try value.validate()
        return value
    }

    static func make(kind: ScheduledWorkKindV1, fireAtUTC: Date,
                     timeZoneIdentifier: String) throws -> Self {
        guard fireAtUTC.timeIntervalSince1970.isFinite,
              let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let seconds = zone.secondsFromGMT(for: fireAtUTC)
        guard abs(seconds) <= 18 * 60 * 60, seconds % 60 == 0 else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        let offset = String(format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+",
                            abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
        let isUTCName = ["UTC", "Etc/UTC", "GMT", "Etc/GMT"].contains(timeZoneIdentifier)
        let abbreviation = seconds == 0 && isUTCName ? "UTC" : zone.abbreviation(for: fireAtUTC)
        let displayZone: String
        if let abbreviation,
           abbreviation.range(of: #"\A[A-Za-z]{1,8}\z"#, options: .regularExpression) != nil {
            displayZone = "\(abbreviation) (\(offset))"
        } else {
            displayZone = "(\(offset))"
        }
        let value = Self(kind: kind,
            body: "Due \(formatter.string(from: fireAtUTC)) \(displayZone). Open AssetRounds to review.")
        try value.validate()
        return value
    }

    static func observed(title: String, body: String) throws -> Self {
        let kind: ScheduledWorkKindV1
        switch title {
        case "Round due": kind = .roundSession
        case "Work due": kind = .workPacket
        default: throw AppAccessContractFailureV1.invalidValue
        }
        let value = Self(kind: kind, body: body)
        try value.validate()
        return value
    }

    func validate() throws {
        // Syntax is only an observation boundary. A valid but wrong date,
        // kind or offset must still fail the owner's source-derived equality.
        let pattern = #"\ADue (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([1-9]|[12][0-9]|3[01]), [0-9]{4} at ([1-9]|1[0-2]):[0-5][0-9] (AM|PM) ([A-Za-z]{1,8} )?\(UTC[+−](0[0-9]|1[0-8]):[0-5][0-9]\)\. Open AssetRounds to review\.\z"#
        guard body.utf8.count <= 160,
              body.range(of: pattern, options: .regularExpression) != nil else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }
}

/// The system boundary reports observations, never reconciliation receipts.
/// Opaque request identifiers and tokens are the only identifiers sent to iOS.
struct NotificationSystemRequestV1: Codable, Equatable, Sendable {
    let notification: AppLockGenericNotificationV1
    let fireAtUTC: Date
    let detail: ReminderSystemDetailV1?

    init(notification: AppLockGenericNotificationV1, fireAtUTC: Date,
         detail: ReminderSystemDetailV1? = nil) {
        self.notification = notification
        self.fireAtUTC = fireAtUTC
        self.detail = detail
    }

    var presentedTitle: String { detail?.title ?? notification.title }
    var presentedBody: String { detail?.body ?? notification.body }

    private enum CodingKeys: String, CodingKey { case notification, fireAtUTC, detail }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notification = try values.decode(AppLockGenericNotificationV1.self, forKey: .notification)
        fireAtUTC = try values.decode(Date.self, forKey: .fireAtUTC)
        detail = try values.decodeIfPresent(ReminderSystemDetailV1.self, forKey: .detail)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(notification, forKey: .notification)
        try values.encode(fireAtUTC, forKey: .fireAtUTC)
        try values.encodeIfPresent(detail, forKey: .detail)
    }

    func validate() throws {
        try notification.validate()
        try detail?.validate()
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
    var projectedAppLockEnabled: Bool? = nil

    static func expectedDetail(reminder: ReminderEntryV1, source: NotificationSourceSnapshotV1,
        policy: DeviceLocalReminderPolicyV1, appLockEnabled: Bool?) throws -> ReminderSystemDetailV1? {
        // Missing discriminator is a legacy generic mapping, never consent.
        guard appLockEnabled == false, policy.isEnabled, policy.detail == .details else { return nil }
        guard let copies = source.copySources,
              copies.count == source.projection.reminders.count,
              Set(copies.map(\.occurrenceID)).count == copies.count,
              Set(copies.map(\.occurrenceID)) == Set(source.projection.reminders.map(\.occurrenceID)) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let matches = copies.filter { $0.occurrenceID == reminder.occurrenceID }
        guard matches.count == 1, let copy = matches.first,
              copy.scheduleRelease.workspaceID == source.projection.workspaceID,
              copy.effectiveBasis.timeBasisSHA256 == copy.scheduleRelease.timeBasisSHA256,
              copy.effectiveBasis.resolvedAtUTC == reminder.fireAtUTC,
              let offset = copy.effectiveBasis.utcOffsetSeconds else { throw AppAccessContractFailureV1.effectMismatch }
        try copy.scheduleRelease.validate()
        try copy.effectiveBasis.validate()
        return try ReminderSystemDetailV1.make(kind: copy.kind, fireAtUTC: reminder.fireAtUTC,
            frozenUTCOffsetSeconds: offset)
    }

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
            let expected = try Self.expectedDetail(reminder: entry.reminder, source: source,
                policy: policy, appLockEnabled: projectedAppLockEnabled)
            guard entry.request.detail == expected else { throw AppAccessContractFailureV1.effectMismatch }
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

/// Durable predecessor ownership, published before the revocation marker.
/// It does not assert an OS drain. Its exact mapping/control digests prevent
/// a marker-only restart from inventing an empty owned set.
struct NotificationEraseOwnedLeafFactV1: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let mode: UInt32
    let links: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ fact: EraseColdControlLeafFactV1) {
        device = UInt64(fact.device)
        inode = UInt64(fact.inode)
        mode = UInt32(fact.mode)
        links = UInt64(fact.links)
        size = Int64(fact.size)
        modifiedSeconds = fact.modifiedSeconds
        modifiedNanoseconds = fact.modifiedNanoseconds
        changedSeconds = fact.changedSeconds
        changedNanoseconds = fact.changedNanoseconds
    }
}

struct NotificationEraseOwnedIDsProvenanceV1:
    Codable, Equatable, Sendable {
    let schemaVersion: Int
    let operationID: UUID
    let rootIdentity: String
    let mappingSHA256: String?
    let controlSHA256: String?
    let mappingFact: NotificationEraseOwnedLeafFactV1?
    let controlFact: NotificationEraseOwnedLeafFactV1?
    let ownedRequestIDs: [String]

    init(operationID: UUID, rootIdentity: String,
        mappingBytes: Data?, mappingFact: EraseColdControlLeafFactV1?,
        controlBytes: Data?, controlFact: EraseColdControlLeafFactV1?,
        ownedRequestIDs: Set<String>) throws {
        schemaVersion = 1
        self.operationID = operationID
        self.rootIdentity = rootIdentity
        mappingSHA256 = try mappingBytes.map {
            try CompatibilityCanonicalV1.sha256($0)
        }
        controlSHA256 = try controlBytes.map {
            try CompatibilityCanonicalV1.sha256($0)
        }
        self.mappingFact = mappingFact.map(NotificationEraseOwnedLeafFactV1.init)
        self.controlFact = controlFact.map(NotificationEraseOwnedLeafFactV1.init)
        self.ownedRequestIDs = ownedRequestIDs.sorted()
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 1,
              operationID != SettingsValidationV1.zeroUUID,
              !rootIdentity.isEmpty,
              ownedRequestIDs == ownedRequestIDs.sorted(),
              Set(ownedRequestIDs).count == ownedRequestIDs.count,
              ownedRequestIDs.allSatisfy({ !$0.isEmpty }),
              mappingSHA256.map(CompatibilityCanonicalV1.validSHA256)
                ?? true,
              controlSHA256.map(CompatibilityCanonicalV1.validSHA256)
                ?? true,
              (mappingSHA256 != nil) == (mappingFact != nil),
              (controlSHA256 != nil) == (controlFact != nil),
              mappingFact.map({ $0.links == 1 && $0.size > 0 }) ?? true,
              controlFact.map({ $0.links == 1 && $0.size > 0 }) ?? true else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
    }
}

/// Prospective cold-Erase replay data. Publication follows an actual OS
/// absence readback; a new process must remove and observe these exact IDs
/// again before it may unlink the notification mapping or a generation.
struct NotificationEraseDrainRecordV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let operationID: UUID
    let rootIdentity: String
    let revocationSHA256: String
    let ownedRequestIDs: [String]

    /// Canonical expected bytes may be derived before OS removal solely to
    /// classify a reserved interrupted temp prefix. Construction is not an
    /// OS-absence receipt; publication still requires the checked readback.
    init(revocation: NotificationEraseRevocationV1,
         ownedRequestIDs: Set<String>) throws {
        try revocation.validate()
        schemaVersion = 1
        operationID = revocation.operationID
        rootIdentity = revocation.rootIdentity
        revocationSHA256 = try CompatibilityCanonicalV1.sha256(
            CompatibilityCanonicalV1.encode(revocation))
        self.ownedRequestIDs = ownedRequestIDs.sorted()
        try validate(revocation: revocation)
    }

    func validate(revocation: NotificationEraseRevocationV1) throws {
        guard schemaVersion == 1,
              operationID == revocation.operationID,
              rootIdentity == revocation.rootIdentity,
              revocationSHA256 == (try CompatibilityCanonicalV1.sha256(
                CompatibilityCanonicalV1.encode(revocation))),
              ownedRequestIDs == ownedRequestIDs.sorted(),
              Set(ownedRequestIDs).count == ownedRequestIDs.count,
              ownedRequestIDs.allSatisfy({ !$0.isEmpty }) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }
}

@MainActor protocol NotificationSystemPortV1: AnyObject {
    func authorization() async throws -> LocalReminderAuthorizationV1
    func observations() async throws -> [NotificationSystemObservationV1]
    func add(_ request: NotificationSystemRequestV1) async throws
    func remove(_ requestIDs: [String]) async throws
}

/// A deliberate user action may request permission. Read-only system probes
/// do not acquire this capability through a permissive protocol default.
@MainActor protocol NotificationPermissionRequestingV1: NotificationSystemPortV1 {
    func requestAuthorization() async throws -> LocalReminderAuthorizationV1
}

/// A scheduling acknowledgement is not readback. Removal is also asynchronous
/// at the OS boundary; the owner must subsequently inspect actual absence.
@MainActor final class UserNotificationSystemAdapterV1: NotificationPermissionRequestingV1 {
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

    func requestAuthorization() async throws -> LocalReminderAuthorizationV1 {
        if try await authorization() == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert])
        }
        return try await authorization()
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
        content.title = request.presentedTitle
        content.body = request.presentedBody
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
        let generic = AppLockGenericNotificationV1(requestID: request.identifier,
            opaqueCorrelationToken: token)
        let detail: ReminderSystemDetailV1?
        if content.title == generic.title, content.body == generic.body {
            detail = nil
        } else {
            guard let observed = try? ReminderSystemDetailV1.observed(title: content.title, body: content.body) else {
                return .init(requestID: request.identifier, request: nil, delivered: delivered)
            }
            detail = observed
        }
        let value = NotificationSystemRequestV1(notification: generic, fireAtUTC: fire, detail: detail)
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

/// The Erase OS sequence needs only this retained control owner. Ordinary
/// notification publication continues to use its existing concrete store;
/// schema-2 cold recovery supplies a separate checked, operation-held owner.
@MainActor protocol NotificationEraseControlOwnerV1: AnyObject {
    var notificationRootIdentity: String { get }
    func beginNotificationErase(operationID: UUID) throws -> NotificationEraseRevocationV1
    func verifyNotificationStorage() throws
    func loadPrivateNotificationMapping() throws -> NotificationPrivateMappingV1?
    func loadControl() throws -> AppLockNotificationControlV1?
    func removeNotificationRecordsAfterErase(_ revocation: NotificationEraseRevocationV1) throws
    func requireNotificationEraseRevocation(_ revocation: NotificationEraseRevocationV1) throws
}

@MainActor protocol Schema2ColdNotificationEraseControlV1:
    NotificationEraseControlOwnerV1 {
    func reserveSchema2ColdOwnedIDs(
        operationID: UUID
    ) throws -> NotificationEraseOwnedIDsProvenanceV1
    func requireSchema2ColdOwnedIDs(
        _ provenance: NotificationEraseOwnedIDsProvenanceV1
    ) throws
    /// Marker readback permits predecessor mapping/control until the owned
    /// OS absence receipt authorizes their checked removal.
    func requireSchema2ColdRevocation(
        _ revocation: NotificationEraseRevocationV1
    ) throws
    func retainSchema2ColdOSAbsence(
        _ receipt: EraseSchema2ColdNotificationOSAbsenceReceiptV1
    ) throws
    func requireSchema2ColdOSAbsence(
        stage: EraseSchema2ColdNotificationMutationStageV1
    ) throws
    func loadSchema2ColdDrainRecord(
        revocation: NotificationEraseRevocationV1
    ) throws -> NotificationEraseDrainRecordV1?
    func publishSchema2ColdDrainRecord(
        _ record: NotificationEraseDrainRecordV1,
        revocation: NotificationEraseRevocationV1
    ) throws
    func requireSchema2ColdDrainRecord(
        _ record: NotificationEraseDrainRecordV1,
        revocation: NotificationEraseRevocationV1
    ) throws
}

/// Emitted only after the original notification owner completed its OS
/// absence readback and checked control removal. Physical tree admission is
/// separate and remains bound to the original Erase operation's first roster.
/// Issued only after the genuine system removal/readback found no owned
/// requests, the add drain ended, and mapping/control were revalidated.
/// It authorizes no filesystem effect without the retained Router owner.
@MainActor final class OriginalEraseNotificationOSAbsenceReceiptV1 {
    let revocation: NotificationEraseRevocationV1
    let mapping: NotificationPrivateMappingV1?
    let journal: AppLockNotificationJournalV1?
    let ownedRequestIDs: Set<String>
    private let control: any NotificationEraseControlOwnerV1

    fileprivate init(control: any NotificationEraseControlOwnerV1,
        revocation: NotificationEraseRevocationV1,
        mapping: NotificationPrivateMappingV1?,
        journal: AppLockNotificationJournalV1?,
        ownedRequestIDs: Set<String>) {
        self.control = control
        self.revocation = revocation
        self.mapping = mapping
        self.journal = journal
        self.ownedRequestIDs = ownedRequestIDs
    }

    func requireBound(control: any NotificationEraseControlOwnerV1,
        revocation: NotificationEraseRevocationV1) throws {
        guard self.control === control,
              self.revocation == revocation else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
    }
}

@MainActor final class OriginalEraseNotificationEffectReceiptV1 {
    private let control: any NotificationEraseControlOwnerV1
    let revocation: NotificationEraseRevocationV1

    fileprivate init(control: any NotificationEraseControlOwnerV1,
                     revocation: NotificationEraseRevocationV1) {
        self.control = control
        self.revocation = revocation
    }

    func requireBound(control: any NotificationEraseControlOwnerV1,
                      operationID: UUID) throws {
        guard self.control === control,
              revocation.operationID == operationID else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try control.requireNotificationEraseRevocation(revocation)
    }
}

/// Constructed at the actual OS readback boundary, after the mapping and
/// journal have been re-read unchanged. The private initializer prevents a
/// file-only record from impersonating a completed OS drain.
@MainActor final class EraseSchema2ColdNotificationOSAbsenceReceiptV1 {
    private let control: any Schema2ColdNotificationEraseControlV1
    let revocation: NotificationEraseRevocationV1
    let drainRecord: NotificationEraseDrainRecordV1

    fileprivate init(control: any Schema2ColdNotificationEraseControlV1,
                     revocation: NotificationEraseRevocationV1,
                     drainRecord: NotificationEraseDrainRecordV1) {
        self.control = control
        self.revocation = revocation
        self.drainRecord = drainRecord
    }

    func requireBound(to candidate: any Schema2ColdNotificationEraseControlV1,
                      operationID: UUID,
                      drainPublished: Bool) throws {
        try requireRetained(to: candidate, operationID: operationID)
        try candidate.requireSchema2ColdRevocation(revocation)
        if drainPublished {
            try candidate.requireSchema2ColdDrainRecord(
                drainRecord, revocation: revocation)
        }
    }

    /// Used only inside a Manifest mutation scope. The Manifest and concrete
    /// Storage effect recheck physical leaves there; re-entering the generic
    /// source reader would recursively demand stale in-flight root metadata.
    func requireRetained(
        to candidate: any Schema2ColdNotificationEraseControlV1,
        operationID: UUID
    ) throws {
        guard control === candidate,
              revocation.operationID == operationID,
              revocation.rootIdentity == candidate.notificationRootIdentity,
              !NotificationAddDrainV1.isActive(
                root: candidate.notificationRootIdentity) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }
}

extension AppLockNotificationControlStoreV1: NotificationEraseControlOwnerV1 {}

/// Created only after the concrete OS owner has observed absence of every
/// owned pending and delivered request and the control owner has retained the
/// revocation marker while removing mapping and journal records.
@MainActor final class EraseSchema2ColdNotificationDrainReceiptV1 {
    private let control: any Schema2ColdNotificationEraseControlV1
    private let revocation: NotificationEraseRevocationV1
    private let drainRecord: NotificationEraseDrainRecordV1

    fileprivate init(control: any Schema2ColdNotificationEraseControlV1,
                     revocation: NotificationEraseRevocationV1,
                     drainRecord: NotificationEraseDrainRecordV1) {
        self.control = control
        self.revocation = revocation
        self.drainRecord = drainRecord
    }

    func requireBound(to candidate: any Schema2ColdNotificationEraseControlV1,
                      operationID: UUID) throws {
        guard control === candidate,
              revocation.operationID == operationID,
              revocation.rootIdentity == candidate.notificationRootIdentity,
              !NotificationAddDrainV1.isActive(
                root: candidate.notificationRootIdentity) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try candidate.requireNotificationEraseRevocation(revocation)
        try candidate.requireSchema2ColdDrainRecord(
            drainRecord, revocation: revocation)
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
    // Keep the actual admission, store and OS owner with an uncertain add.
    // Recovery settles only this operation before releasing its own child SH.
    @MainActor private final class RetainedSchedulingAdmission {
        let control: AppLockNotificationControlStoreV1
        let system: any NotificationSystemPortV1
        let activity: OwnedStorageProducerActivityV1
        let rootIdentity: String
        let publication: AppLockNotificationControlStoreV1.NotificationSchedulingPublicationOwner
        let request: NotificationSystemRequestV1
        private(set) var completed = false
        private var settling = false

        init(control: AppLockNotificationControlStoreV1,
             system: any NotificationSystemPortV1,
             activity: OwnedStorageProducerActivityV1,
             publication: AppLockNotificationControlStoreV1.NotificationSchedulingPublicationOwner,
             request: NotificationSystemRequestV1) {
            self.control = control
            self.system = system
            self.activity = activity
            rootIdentity = control.notificationRootIdentity
            self.publication = publication
            self.request = request
        }

        private func requireOwnedPublication() throws {
            try activity.requireApplicationSupport(activity.applicationSupportURL)
            guard control.notificationRootIdentity == rootIdentity else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try control.requireNotificationSchedulingState(publication)
        }

        func settle() async throws {
            if completed { return }
            guard !settling else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            settling = true
            defer { settling = false }
            try requireOwnedPublication()
            // Abandon only the positively owned request from this exact
            // admission. A later normal reconciliation can schedule anew.
            try await system.remove([request.notification.requestID])
            try requireOwnedPublication()
            let observed = try await system.observations()
            try requireOwnedPublication()
            guard !observed.contains(where: {
                $0.requestID == request.notification.requestID
            }) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try control.settleNotificationSchedulingAbsent(publication)
            try control.requireNotificationSchedulingTerminal(publication, verifiedPresent: false)
            try control.retireNotificationSchedulingPublicationOwner(publication, verifiedPresent: false)
            activity.close()
            completed = true
        }
    }

    private static var retainedSchedulingAdmissions: [RetainedSchedulingAdmission] = []

    /// Called before cold recovery acquires Support EX. Only retained live
    /// admissions are considered; this never reconstructs an owner from disk.
    static func settleRetainedNotificationScheduling(applicationSupportURL: URL) async throws {
        let root = applicationSupportURL.standardizedFileURL
        let pending = retainedSchedulingAdmissions.filter {
            $0.activity.applicationSupportURL == root && !$0.completed
        }
        for admission in pending {
            try await admission.settle()
            retainedSchedulingAdmissions.removeAll { $0 === admission }
        }
    }

    private static func settleRetainedNotificationScheduling(
        control: AppLockNotificationControlStoreV1
    ) async throws {
        let pending = retainedSchedulingAdmissions.filter {
            $0.rootIdentity == control.notificationRootIdentity && !$0.completed
        }
        for admission in pending {
            try await admission.settle()
            retainedSchedulingAdmissions.removeAll { $0 === admission }
        }
    }

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

    private func validateForeground(_ authorization: NotificationOperationAuthorizationV1) async throws {
        guard case .content(let token) = authorization.proof else { throw AppAccessContractFailureV1.accessDenied }
        try await validate(authorization)
        try await authorization.gate.validateForegroundContentRead(token, for: .render)
    }

    func reminderAuthorization() async throws -> LocalReminderAuthorizationV1 {
        let authorization = try await contentAuthorization()
        return try await reminderAuthorization(authorization: authorization)
    }

    func reminderAuthorization(authorization: NotificationOperationAuthorizationV1) async throws -> LocalReminderAuthorizationV1 {
        try await validateForeground(authorization)
        let result = try await system.authorization()
        try await validateForeground(authorization)
        return result
    }

    /// Explicit request only; the original proof is never renewed after a prompt.
    func requestReminderAuthorization() async throws -> LocalReminderAuthorizationV1 {
        let authorization = try await contentAuthorization()
        return try await requestReminderAuthorization(authorization: authorization)
    }

    func requestReminderAuthorization(authorization: NotificationOperationAuthorizationV1) async throws -> LocalReminderAuthorizationV1 {
        let current = try await reminderAuthorization(authorization: authorization)
        guard current == .notDetermined else { return current }
        guard let requester = system as? any NotificationPermissionRequestingV1 else {
            throw AppAccessContractFailureV1.accessDenied
        }
        try await validateForeground(authorization)
        let result = try await requester.requestAuthorization()
        try await validateForeground(authorization)
        return result
    }

    func loadJournalEffect() async throws -> AppLockNotificationJournalV1? { try control.loadControl()?.journal }

    func loadAuthenticationSubjectEffect() async throws -> NotificationOperationSubjectV1? {
        try currentAuthenticationControl().map(NotificationOperationSubjectV1.init(control:))
    }

    /// A completed Preferences effect invalidates the old authentication subject
    /// even when its metadata publication was interrupted. Original incomplete
    /// toggle controls still use their existing authenticated recovery route.
    private func currentAuthenticationControl() throws -> AppLockNotificationControlV1? {
        guard let current = try control.loadControl() else {
            return try control.readyControlForReminderPolicy()
        }
        guard current.phase == .settingCommitted,
              current.journal.targetEnabled || current.journal.disposition == .priorPolicyRebuilt else { return current }
        return try control.readyControlForReminderPolicy()
    }

    func readAppLockSetting() async -> DeviceLocalAppLockSettingReadV1 {
        do {
            guard let value = try preferences.readAppLockSettingSnapshot().setting else { return .absentDisabled }
            return .value(value)
        } catch { return .corruptOrAmbiguous }
    }

    func bindReminderPolicyEdits(to gate: AppAccessGateV1) throws {
        try preferences.bindReminderPolicyEdits(to: gate, control: control)
    }

    func validatesLocalConfigurationEffect(_ setting: DeviceLocalAppLockSettingReadV1) async throws -> Bool {
        try control.requireNotificationPublicationAllowed()
        let stored = try preferences.readAppLockSettingSnapshot()
        let actual = try stored.setting.map(DeviceLocalAppLockSettingReadV1.value) ?? .absentDisabled
        guard actual == setting else { return false }
        let existing = try control.loadControl()
        // An interrupted toggle must still bootstrap into locked authenticated
        // recovery. Only completed controls can settle reminder-edit metadata.
        if let existing {
            guard existing.phase == .settingCommitted, stored == existing.settingWrite.successor,
                  existing.journal.targetEnabled || existing.journal.disposition == .priorPolicyRebuilt else { return false }
        }
        let value: AppLockNotificationControlV1
        do {
            guard let ready = try control.readyControlForReminderPolicy() else {
                return actual == .absentDisabled || actual == .value(.init(isEnabled: false))
            }
            value = ready
        } catch AppAccessContractFailureV1.effectMismatch {
            return false
        } catch AppAccessContractFailureV1.notificationReconciliationRequired {
            return false
        }
        guard value.phase == .settingCommitted, stored == value.settingWrite.successor,
              try preferences.readStoredReminderPolicy() == value.currentReminderPolicy else { return false }
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
        try await Self.settleRetainedNotificationScheduling(control: control)
        try await validate(authorization, target: target)
        let predecessor = try currentAuthenticationControl()
        guard predecessor?.journal == expected,
              try predecessor.map(NotificationOperationSubjectV1.init(control:)) == authorization.subject else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let policy: DeviceLocalReminderPolicyV1
        if let existing = try preferences.readStoredReminderPolicy() {
            policy = existing
        } else {
            // Only the authenticated first enable may create the existing
            // disabled generic default. Missing established policy is damage.
            guard target, predecessor == nil,
                  try preferences.readAppLockSettingSnapshot().setting == nil,
                  try control.loadPrivateNotificationMapping() == nil,
                  !NotificationAddDrainV1.isActive(root: control.notificationRootIdentity) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            policy = try preferences.readReminderPolicy()
        }
        // The authenticated source supplies copy; the target AppLock state
        // controls whether any detail may be projected.
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
        let setting = try preferences.readAppLockSettingSnapshot()
        if desired.contains(where: { $0.fireAtUTC <= clock.now() }) {
            try await removeForbiddenDetails(before: beforeMapping, snapshot: snapshot, source: source,
                policy: policy, setting: setting, localControl: predecessor,
                appLockEnabled: target, authorization: authorization)
        }
        try requireSchedulable(desired)
        if !desired.isEmpty {
            let availability = try await system.authorization()
            try await validate(authorization, target: target)
            guard availability == .authorized else { throw AppAccessContractFailureV1.notificationReconciliationRequired }
        }
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
        } else { entries = try desired.map { try makeEntry($0, source: snapshot, policy: policy, appLockEnabled: target) } }
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
            entries: entries, retiring: retiring, projectedAppLockEnabled: beforeMapping?.operationID == operationID ? beforeMapping?.projectedAppLockEnabled : target)
        try await source.validateNotificationSnapshot(snapshot, authorization: authorization)
        try await validate(authorization, target: target)
        return try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
          try AppLockNotificationTransactionFenceV1.perform {
            guard try currentPolicy() == policy, try preferences.readAppLockSettingSnapshot() == setting,
                  try currentAuthenticationControl() == predecessor else { throw AppAccessContractFailureV1.effectMismatch }
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
        try await Self.settleRetainedNotificationScheduling(control: control)
        try await validate(authorization, target: target)
        let value = try exactControl(expected, authorization: authorization)
        if !target {
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
        return try await reconcileSnapshot(snapshot, source: source, authorization: authorization)
    }

    func reconcileSavedReminderPolicy(authorization: NotificationOperationAuthorizationV1) async throws -> LocalReminderReconciliationV1? {
        try await validateForeground(authorization)
        let source = try await source(for: authorization)
        let snapshot = try await source.notificationSnapshot(authorization: authorization, evaluatedAt: clock.now())
        if try currentPolicy().isEnabled {
            let result = try await reconcileSnapshot(snapshot, source: source, authorization: authorization)
            try await validateForeground(authorization)
            return result
        }
        try await removeAll(snapshot: snapshot, source: source, authorization: authorization)
        try await validateForeground(authorization)
        return nil
    }

    private func reconcileSnapshot(_ snapshot: NotificationSourceSnapshotV1, source: ProductionMyDaySourceProviderV1,
                                   authorization: NotificationOperationAuthorizationV1) async throws -> LocalReminderReconciliationV1 {
        try await Self.settleRetainedNotificationScheduling(control: control)
        try await validate(authorization)
        let projection = snapshot.projection
        let policy = try currentPolicy()
        // A caller cannot turn a canonical due projection into renewed consent.
        // The opt-out route removes requests explicitly through removeAll.
        guard policy.isEnabled else { throw AppAccessContractFailureV1.accessDenied }
        let setting = try preferences.readAppLockSettingSnapshot()
        let localControl = try ordinaryControl(setting: setting)
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
        let locked = try setting.setting?.isEnabled == true
        let observed = try (before?.entries ?? []).compactMap { entry -> ReminderEntryV1? in
            guard projection.reminders.contains(entry.reminder) else { return nil }
            let expected = try NotificationPrivateMappingV1.expectedDetail(reminder: entry.reminder, source: snapshot,
                policy: policy, appLockEnabled: locked)
            let matches = observedSystem.filter { $0.requestID == entry.request.notification.requestID }
            return entry.request.detail == expected && matches.count == 1 && matches[0].request == entry.request ? entry.reminder : nil
        }
        let plan = try LocalReminderReconciliationV1(projection: projection,
            observedReminderEntries: observed, authorization: availability)
        let missing = projection.reminders.filter { !observed.contains($0) }
        if availability != .authorized || missing.contains(where: { $0.fireAtUTC <= clock.now() }) {
            // Privacy cleanup is independently useful even when delivery must
            // retain its original denial. Never report an expired request as
            // applied or manufacture a replacement fire time.
            try await removeForbiddenDetails(before: before, snapshot: snapshot, source: source,
                policy: policy, setting: setting, localControl: localControl,
                appLockEnabled: locked, authorization: authorization)
        }
        guard availability == .authorized else { return plan }
        try requireSchedulable(missing)
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

    /// Removal uses only IDs already owned by the exact durable mapping.
    /// Keep that mapping until normal reconciliation can replace it, so a
    /// failed readback or process interruption cannot lose cleanup ownership.
    private func removeForbiddenDetails(before: NotificationPrivateMappingV1?,
        snapshot: NotificationSourceSnapshotV1, source: ProductionMyDaySourceProviderV1,
        policy: DeviceLocalReminderPolicyV1, setting: AppLockStoredSettingSnapshotV1,
        localControl: AppLockNotificationControlV1?, appLockEnabled: Bool,
        authorization: NotificationOperationAuthorizationV1) async throws {
        guard appLockEnabled || !policy.isEnabled || policy.detail == .generic,
              let before else { return }
        let forbidden = Set((before.entries.map(\.request) + before.retiring)
            .filter { $0.detail != nil }.map { $0.notification.requestID })
        guard !forbidden.isEmpty else { return }
        let verify: () throws -> Void = {
            try self.control.requireNotificationPublicationAllowed()
            guard try self.control.loadPrivateNotificationMapping() == before,
                  try self.currentPolicy() == policy,
                  try self.preferences.readAppLockSettingSnapshot() == setting,
                  try self.control.loadControl() == localControl,
                  before.entries.allSatisfy({ $0.admissionID == nil }),
                  !NotificationAddDrainV1.isActive(root: self.control.notificationRootIdentity) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
        try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
            try verify()
            try await self.system.remove(forbidden.sorted())
        }
        let observed = try await source.performNotificationEffect(snapshot: snapshot, authorization: authorization) {
            try verify()
            return try await self.system.observations()
        }
        try verify()
        guard !observed.contains(where: { forbidden.contains($0.requestID) }) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }

    func removeAll(workspaceID: WorkspaceID) async throws {
        let authorization = try await contentAuthorization()
        let source = try await source(for: authorization)
        let snapshot = try await source.notificationSnapshot(authorization: authorization, evaluatedAt: clock.now())
        guard snapshot.projection.workspaceID == workspaceID else { throw AppAccessContractFailureV1.accessDenied }
        try await removeAll(snapshot: snapshot, source: source, authorization: authorization)
    }

    private func removeAll(snapshot: NotificationSourceSnapshotV1, source: ProductionMyDaySourceProviderV1,
                           authorization: NotificationOperationAuthorizationV1) async throws {
        try await validate(authorization)
        try await Self.settleRetainedNotificationScheduling(control: control)
        try await validate(authorization)
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
        let value = try control.readyControlForReminderPolicy()
        if let value {
            guard value.phase == .settingCommitted, value.settingWrite.successor == setting else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        } else if try setting.setting?.isEnabled == true {
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
        let locked = try setting.setting?.isEnabled == true
        let entries = try desired.map { reminder in
            let expected = try NotificationPrivateMappingV1.expectedDetail(reminder: reminder, source: source,
                policy: policy, appLockEnabled: locked)
            if let old = before?.entries.first(where: { $0.reminder == reminder && $0.request.detail == expected }) { return old }
            return try makeEntry(reminder, source: source, policy: policy, appLockEnabled: locked)
        }
        let retained = Set(entries.map { $0.request.notification.requestID })
        let retiring = (before?.retiring ?? []) + (before?.entries.map(\.request) ?? [])
            .filter { !retained.contains($0.notification.requestID) }
        let result = NotificationPrivateMappingV1(schemaVersion: 1, operationID: operationID,
            source: source, policy: policy, setting: setting,
            controlSubjectSHA256: try localControl.map { try NotificationOperationSubjectV1(control: $0).immutableSHA256() },
            entries: entries, retiring: retiring, projectedAppLockEnabled: locked)
        try result.validate()
        return result
    }

#if DEBUG
    private struct OriginalEraseFixedDiagnosticContextV1: Sendable {
        let operationID: UUID
        let controlIdentity: ObjectIdentifier
        let report: @MainActor @Sendable (String) -> Void
    }
    @TaskLocal private static var originalEraseFixedDiagnosticContext:
        OriginalEraseFixedDiagnosticContextV1?

    /// A lexical task scope, not a shared mutable reporter. The operation ID
    /// is used only to reject inherited callbacks belonging to another owner;
    /// it is never emitted or used to authorize an effect.
    static func withOriginalEraseFixedDiagnostics(
        operationID: UUID, control: any NotificationEraseControlOwnerV1,
        report: @escaping @MainActor @Sendable (String) -> Void,
        _ body: @MainActor () async throws -> OriginalEraseNotificationEffectReceiptV1
    ) async rethrows -> OriginalEraseNotificationEffectReceiptV1 {
        try await $originalEraseFixedDiagnosticContext.withValue(
            OriginalEraseFixedDiagnosticContextV1(operationID: operationID,
                controlIdentity: ObjectIdentifier(control), report: report), operation: body)
    }

    private static func traceOriginalEraseFixedDiagnostic(
        _ stage: String, operationID: UUID, control: any NotificationEraseControlOwnerV1) {
        guard let context = originalEraseFixedDiagnosticContext,
              context.operationID == operationID,
              context.controlIdentity == ObjectIdentifier(control) else { return }
        context.report(stage)
    }
#endif
    /// The same source-free implementation serves actual EraseAll recovery.
    static func erase(control: any NotificationEraseControlOwnerV1, system: any NotificationSystemPortV1,
                      operationID: UUID) async throws {
        _ = try await eraseOriginalOwner(
            control: control, system: system, operationID: operationID,
            beforeBegin: nil, afterBegin: nil,
            observedOwnedRefusal: nil, afterSuccess: nil)
    }

    /// The original Erase operation retains its EX and first physical roster
    /// across these synchronous callbacks. A failure in either callback is a
    /// failed effect, never a reusable observation from a later tree.
    static func eraseForOriginalRetainedOwner(
        control: any NotificationEraseControlOwnerV1,
        system: any NotificationSystemPortV1,
        operationID: UUID,
        beginMarker: (@MainActor () throws
            -> NotificationEraseRevocationV1)? = nil,
        removeRecords: (@MainActor (
            OriginalEraseNotificationOSAbsenceReceiptV1) throws -> Void)? = nil,
        beforeBegin: @escaping @MainActor () throws -> Void,
        afterBegin: (@MainActor (NotificationEraseRevocationV1) throws -> Void)? = nil,
        observedOwnedRefusal: (@MainActor (
            NotificationEraseRevocationV1, Set<String>, Set<String>
        ) throws -> Void)? = nil,
        afterSuccess: @escaping @MainActor (NotificationEraseRevocationV1) throws -> Void
    ) async throws -> OriginalEraseNotificationEffectReceiptV1 {
        let revocation = try await eraseOriginalOwner(
            control: control, system: system, operationID: operationID,
            beforeBegin: beforeBegin, afterBegin: afterBegin,
            observedOwnedRefusal: observedOwnedRefusal,
            afterSuccess: afterSuccess,
            originalBeginMarker: beginMarker,
            requiresOriginalBeginMarker: true,
            originalRemoveRecords: removeRecords,
            requiresOriginalRemoveRecords: true)
        try control.requireNotificationEraseRevocation(revocation)
        return OriginalEraseNotificationEffectReceiptV1(
            control: control, revocation: revocation)
    }

    static func eraseSchema2Cold(
        control: any Schema2ColdNotificationEraseControlV1,
        system: any NotificationSystemPortV1,
        operationID: UUID
    ) async throws -> EraseSchema2ColdNotificationDrainReceiptV1 {
        let revocation = try await eraseOriginalOwner(
            control: control, system: system, operationID: operationID,
            beforeBegin: nil, afterBegin: nil,
            observedOwnedRefusal: nil, afterSuccess: nil,
            coldControl: control)
        try control.requireNotificationEraseRevocation(revocation)
        guard let record = try control.loadSchema2ColdDrainRecord(
                revocation: revocation) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        return EraseSchema2ColdNotificationDrainReceiptV1(
            control: control, revocation: revocation,
            drainRecord: record)
    }

#if DEBUG
    /// Reports only the actual original OS readback refusal, after the same
    /// control/mapping/journal checks used for success. A caller cannot infer
    /// this fact from the error type or a later OS observation.
    static func eraseForOriginalColdExitForTesting(
        control: any NotificationEraseControlOwnerV1,
        system: any NotificationSystemPortV1,
        operationID: UUID,
        beforeBegin: @escaping @MainActor () throws -> Void,
        afterBegin: @escaping @MainActor (NotificationEraseRevocationV1) throws -> Void,
        observedOwnedRefusal: @escaping @MainActor (
            NotificationEraseRevocationV1, Set<String>, Set<String>
        ) throws -> Void,
        afterSuccess: @escaping @MainActor (NotificationEraseRevocationV1) throws -> Void
    ) async throws {
        _ = try await eraseOriginalOwner(
            control: control, system: system, operationID: operationID,
            beforeBegin: beforeBegin, afterBegin: afterBegin,
            observedOwnedRefusal: observedOwnedRefusal,
            afterSuccess: afterSuccess)
    }
#endif

    private static func eraseOriginalOwner(
        control: any NotificationEraseControlOwnerV1,
        system: any NotificationSystemPortV1,
        operationID: UUID,
        beforeBegin: (@MainActor () throws -> Void)?,
        afterBegin: (@MainActor (NotificationEraseRevocationV1) throws -> Void)?,
        observedOwnedRefusal: (@MainActor (
            NotificationEraseRevocationV1, Set<String>, Set<String>
        ) throws -> Void)?,
        afterSuccess: (@MainActor (NotificationEraseRevocationV1) throws -> Void)?,
        coldControl: (any Schema2ColdNotificationEraseControlV1)? = nil,
        originalBeginMarker: (@MainActor () throws
            -> NotificationEraseRevocationV1)? = nil,
        requiresOriginalBeginMarker: Bool = false,
        originalRemoveRecords: (@MainActor (
            OriginalEraseNotificationOSAbsenceReceiptV1) throws -> Void)? = nil,
        requiresOriginalRemoveRecords: Bool = false
    ) async throws -> NotificationEraseRevocationV1 {
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.before-begin.enter", operationID: operationID, control: control)
#endif
        try beforeBegin?()
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.before-begin.complete", operationID: operationID, control: control)
#endif
        guard !requiresOriginalBeginMarker ||
                originalBeginMarker != nil else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
        guard !requiresOriginalRemoveRecords ||
                originalRemoveRecords != nil else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.marker.enter", operationID: operationID, control: control)
#endif
        let firstCut: (
            NotificationEraseOwnedIDsProvenanceV1?,
            NotificationEraseRevocationV1)
        if let coldControl {
            // Both synchronous effects use the existing process-local
            // notification transaction fence. An in-process add cannot
            // publish between the owned-ID predecessor check and marker.
            firstCut = try
                AppLockNotificationTransactionFenceV1.perform {
                    let value = try coldControl.reserveSchema2ColdOwnedIDs(
                        operationID: operationID)
                    let marker = try control.beginNotificationErase(
                        operationID: operationID)
                    return (value, marker)
                }
        } else if let originalBeginMarker {
            // The original retained owner supplies its checked publication
            // under this same process fence. The ordinary AppLock publisher
            // remains unavailable to an original-mode control.
            firstCut = try
                AppLockNotificationTransactionFenceV1.perform {
                    (nil, try originalBeginMarker())
                }
        } else {
            firstCut = (nil, try control.beginNotificationErase(
                operationID: operationID))
        }
        let (provenance, revocation) = firstCut
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.marker.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.after-begin.enter", operationID: operationID, control: control)
#endif
        try afterBegin?(revocation)
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.after-begin.complete", operationID: operationID, control: control)
#endif
        if let provenance {
            try coldControl?.requireSchema2ColdOwnedIDs(provenance)
        }
        let priorDrain = try coldControl?.loadSchema2ColdDrainRecord(
            revocation: revocation)
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.drain.enter", operationID: operationID, control: control)
#endif
        await NotificationAddDrainV1.wait(root: control.notificationRootIdentity)
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.drain.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.storage-before.enter", operationID: operationID, control: control)
#endif
        try control.verifyNotificationStorage()
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.storage-before.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.mapping.enter", operationID: operationID, control: control)
#endif
        let mapping = try control.loadPrivateNotificationMapping()
        guard mapping?.entries.allSatisfy({ $0.admissionID == nil }) ?? true else {
            // A killed process may leave an unacknowledged system add. Neither
            // an absent runtime task nor an empty OS snapshot proves its drain.
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.mapping.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.journal.enter", operationID: operationID, control: control)
#endif
        let journal = try control.loadControl()?.journal
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.journal.complete", operationID: operationID, control: control)
#endif
        let predecessorOwned = Set((mapping?.ownedRequestIDs ?? []) +
            (journal?.projections.map(\.requestID) ?? []))
        if let provenance {
            guard predecessorOwned.isSubset(of:
                    Set(provenance.ownedRequestIDs)) else {
                throw AppAccessContractFailureV1
                    .notificationReconciliationRequired
            }
            try coldControl?.requireSchema2ColdOwnedIDs(provenance)
        }
        if let priorDrain {
            try priorDrain.validate(revocation: revocation)
            guard predecessorOwned.isSubset(of:
                    Set(priorDrain.ownedRequestIDs)),
                  provenance.map({ $0.ownedRequestIDs
                    == priorDrain.ownedRequestIDs }) ?? true else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        let owned = priorDrain.map { Set($0.ownedRequestIDs) }
            ?? provenance.map { Set($0.ownedRequestIDs) }
            ?? predecessorOwned
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.system-remove.enter", operationID: operationID, control: control)
#endif
        try await system.remove(owned.sorted())
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.system-remove.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.storage-after-remove.enter", operationID: operationID, control: control)
#endif
        try control.verifyNotificationStorage()
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.storage-after-remove.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.system-readback.enter", operationID: operationID, control: control)
#endif
        let observed = try await system.observations()
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.system-readback.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.storage-after-readback.enter", operationID: operationID, control: control)
#endif
        try control.verifyNotificationStorage()
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.storage-after-readback.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.owned-settlement.enter", operationID: operationID, control: control)
#endif
        let observedOwned = Set(observed.map(\.requestID)).intersection(owned)
        guard !NotificationAddDrainV1.isActive(root: control.notificationRootIdentity),
              try control.loadPrivateNotificationMapping() == mapping,
              try control.loadControl()?.journal == journal else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        if !observedOwned.isEmpty {
            try observedOwnedRefusal?(revocation, owned, observedOwned)
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.owned-settlement.complete", operationID: operationID, control: control)
#endif
        if let coldControl {
            let record = try NotificationEraseDrainRecordV1(
                revocation: revocation, ownedRequestIDs: owned)
            if let priorDrain, priorDrain != record {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try coldControl.retainSchema2ColdOSAbsence(
                EraseSchema2ColdNotificationOSAbsenceReceiptV1(
                    control: coldControl, revocation: revocation,
                    drainRecord: record))
            try coldControl.publishSchema2ColdDrainRecord(
                record, revocation: revocation)
            try coldControl.requireSchema2ColdDrainRecord(
                record, revocation: revocation)
        }
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.record-removal.enter", operationID: operationID, control: control)
#endif
        if let originalRemoveRecords {
            try originalRemoveRecords(
                OriginalEraseNotificationOSAbsenceReceiptV1(
                    control: control, revocation: revocation,
                    mapping: mapping, journal: journal,
                    ownedRequestIDs: owned))
        } else {
            try control.removeNotificationRecordsAfterErase(revocation)
        }
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.record-removal.complete", operationID: operationID, control: control)
#endif
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.after-success.enter", operationID: operationID, control: control)
#endif
        try afterSuccess?(revocation)
#if DEBUG
        traceOriginalEraseFixedDiagnostic("cleanup.notification.after-success.complete", operationID: operationID, control: control)
#endif
        return revocation
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
        let schedulingActivity = try control.acquireNotificationSchedulingActivity()
        var unsettledAdmission: RetainedSchedulingAdmission?
        defer {
            if let unsettledAdmission {
                Self.retainedSchedulingAdmissions.append(unsettledAdmission)
            } else {
                schedulingActivity.close()
            }
        }
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
            let publication = try control.makeNotificationSchedulingPublicationOwner(
                predecessor: previous, request: request, admissionID: admission,
                activity: schedulingActivity)
            let retained = RetainedSchedulingAdmission(control: control, system: system,
                activity: schedulingActivity, publication: publication, request: request)
            unsettledAdmission = retained
            let root = control.notificationRootIdentity
            var drainStarted = false
            do {
                defer {
                    if drainStarted { NotificationAddDrainV1.finish(root: root, admission: admission) }
                }
                try control.publishNotificationSchedulingAdmission(publication)
                try NotificationAddDrainV1.begin(root: root, admission: admission)
                drainStarted = true
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
                        try schedulingActivity.requireApplicationSupport(
                            schedulingActivity.applicationSupportURL)
                        try self.control.noteNotificationSchedulingAddAttempt(publication)
                        try await self.system.add(request)
                    }
                let after = try await observe(mapping, source: source, authorization: authorization, settingControl: settingControl)
                    .filter { $0.requestID == request.notification.requestID }
                guard after.count == 1, after[0].request == request else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                try control.finishNotificationSchedulingAdd(publication, verifiedPresent: true)
                try control.requireNotificationSchedulingTerminal(publication, verifiedPresent: true)
                try control.retireNotificationSchedulingPublicationOwner(publication, verifiedPresent: true)
                unsettledAdmission = nil
                mapping.entries[index].admissionID = nil
                mapping.entries[index].acknowledged = true
            } catch {
                // Retain exact publication ownership across failed staging,
                // admission, OS work and terminal durability checks.
                try await retained.settle()
                unsettledAdmission = nil
                throw error
            }
        }
        try await verifySystem(mapping, source: source, authorization: authorization, settingControl: settingControl)
    }

    private func requireSchedulable(_ entries: [ReminderEntryV1]) throws {
        guard entries.count <= 64, entries.allSatisfy({ $0.fireAtUTC > clock.now() }) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }

    private func makeEntry(_ reminder: ReminderEntryV1, source: NotificationSourceSnapshotV1,
                           policy: DeviceLocalReminderPolicyV1, appLockEnabled: Bool) throws -> NotificationPrivateMappingV1.Entry {
        let request = NotificationSystemRequestV1(notification: .init(requestID: UUID().uuidString.lowercased(),
            opaqueCorrelationToken: CompatibilityCanonicalV1.sha256(Data(UUID().uuidString.utf8))), fireAtUTC: reminder.fireAtUTC,
            detail: try NotificationPrivateMappingV1.expectedDetail(reminder: reminder, source: source,
                policy: policy, appLockEnabled: appLockEnabled))
        try request.validate()
        return .init(reminder: reminder, request: request, admissionID: nil, acknowledged: false)
    }

    private func exactControl(_ journal: AppLockNotificationJournalV1,
                              authorization: NotificationOperationAuthorizationV1,
                              allowAdvancedPhase: Bool = false) throws -> AppLockNotificationControlV1 {
        guard let current = try currentAuthenticationControl(), let subject = authorization.subject,
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
        if let projected = mapping.projectedAppLockEnabled {
            let effective: Bool
            if let value = settingMayBeSuccessor, mapping.operationID == value.journal.operationID {
                effective = value.journal.targetEnabled
            } else { effective = try setting.setting?.isEnabled ?? false }
            guard projected == effective else { throw AppAccessContractFailureV1.effectMismatch }
        }
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

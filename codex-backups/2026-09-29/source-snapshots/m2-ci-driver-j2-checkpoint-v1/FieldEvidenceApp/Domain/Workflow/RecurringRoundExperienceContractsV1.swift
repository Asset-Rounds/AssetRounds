import Foundation

enum RecurringRoundExperienceFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, wrongWorkspace, staleSource
    case reminderStateIsNotCanonical, invalidStartReceipt
}

enum RecurringRoundExperiencePersistenceBoundaryV1 {
    static let schemaVersion = 53
    static let activeModelCount = 168
    static let incumbentScheduleRowFamilyCount = 4
    static let addedRowFamilyCount = 0
}

enum ScheduleEditorRecurrenceKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case fixedCalendar = "FIXED_CALENDAR"
    case completionRelative = "COMPLETION_RELATIVE"
}

/// Derived editor state. Saving always appends a validated schedule release or
/// override through the incumbent schedule writer; this value is never stored.
struct ScheduleEditorStateV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let release: ScheduleDefinitionReleaseReferenceV1
    let recurrenceKind: ScheduleEditorRecurrenceKindV1
    let recurrence: ScheduleRecurrenceV1
    let visibleTimeBasis: FrozenScheduleTimeBasisV1
    let visibleStartUTC: Date
    let visibleEndUTC: Date?
    let visibleHorizonDays: Int
    let visibleMaximumOccurrenceCount: Int
    let visibleReadyLeadSeconds: Int64
    let visibleOverdueGraceSeconds: Int64
    let visibleSubject: WorkSubjectReferenceV1
    let visibleWorkDefinition: ScheduledWorkDefinitionReferenceV1
    let requiresExplicitSave: Bool
    let stateSHA256: String

    init(release value: ScheduleDefinitionReleaseV1) throws {
        try value.validate()
        let kind: ScheduleEditorRecurrenceKindV1
        switch value.recurrence {
        case .fixedCalendar: kind = .fixedCalendar
        case .completionRelative: kind = .completionRelative
        case .advanced: throw RecurringRoundExperienceFailureV1.invalidValue
        }
        workspaceID = value.workspaceID
        release = try .init(value)
        recurrenceKind = kind
        recurrence = value.recurrence
        visibleTimeBasis = value.timeBasis
        visibleStartUTC = value.startsAtUTC
        visibleEndUTC = value.endsAtUTC
        visibleHorizonDays = value.generationHorizonDays
        visibleMaximumOccurrenceCount = value.maximumGeneratedOccurrences
        visibleReadyLeadSeconds = value.readyLeadSeconds
        visibleOverdueGraceSeconds = value.overdueGraceSeconds
        visibleSubject = value.subject
        visibleWorkDefinition = value.workDefinition
        requiresExplicitSave = true
        stateSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID: workspaceID, release: release,
            recurrenceKind: kind, recurrence: recurrence, visibleTimeBasis: visibleTimeBasis,
            visibleStartUTC: visibleStartUTC, visibleEndUTC: visibleEndUTC,
            visibleHorizonDays: visibleHorizonDays,
            visibleMaximumOccurrenceCount: visibleMaximumOccurrenceCount,
            visibleReadyLeadSeconds: visibleReadyLeadSeconds,
            visibleOverdueGraceSeconds: visibleOverdueGraceSeconds,
            visibleSubject: visibleSubject, visibleWorkDefinition: visibleWorkDefinition,
            requiresExplicitSave: true))
        try validate()
    }

    func validate() throws {
        try release.validate(); try recurrence.validate(); try visibleTimeBasis.validate()
        try ScheduleLimitsV1.instant(visibleStartUTC); try visibleEndUTC.map(ScheduleLimitsV1.instant)
        try visibleSubject.validate(); try visibleWorkDefinition.validate()
        let expectedKind: ScheduleEditorRecurrenceKindV1
        switch recurrence { case .fixedCalendar: expectedKind = .fixedCalendar
        case .completionRelative: expectedKind = .completionRelative
        case .advanced: throw RecurringRoundExperienceFailureV1.invalidValue }
        guard workspaceID == release.workspaceID, expectedKind == recurrenceKind,
              visibleWorkDefinition.definitionWorkspaceID == workspaceID,
              (1...ScheduleLimitsV1.maximumHorizonDays).contains(visibleHorizonDays),
              (1...ScheduleLimitsV1.maximumGeneratedOccurrences).contains(visibleMaximumOccurrenceCount),
              visibleReadyLeadSeconds >= 0, visibleOverdueGraceSeconds >= 0,
              requiresExplicitSave,
              stateSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else {
            throw RecurringRoundExperienceFailureV1.invalidDigest
        }
    }
    private var basis: Basis { .init(workspaceID: workspaceID, release: release,
        recurrenceKind: recurrenceKind, recurrence: recurrence, visibleTimeBasis: visibleTimeBasis,
        visibleStartUTC: visibleStartUTC, visibleEndUTC: visibleEndUTC,
        visibleHorizonDays: visibleHorizonDays,
        visibleMaximumOccurrenceCount: visibleMaximumOccurrenceCount,
        visibleReadyLeadSeconds: visibleReadyLeadSeconds,
        visibleOverdueGraceSeconds: visibleOverdueGraceSeconds,
        visibleSubject: visibleSubject, visibleWorkDefinition: visibleWorkDefinition,
        requiresExplicitSave: requiresExplicitSave) }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let release: ScheduleDefinitionReleaseReferenceV1; let recurrenceKind: ScheduleEditorRecurrenceKindV1; let recurrence: ScheduleRecurrenceV1; let visibleTimeBasis: FrozenScheduleTimeBasisV1; let visibleStartUTC: Date; let visibleEndUTC: Date?; let visibleHorizonDays: Int; let visibleMaximumOccurrenceCount: Int; let visibleReadyLeadSeconds: Int64; let visibleOverdueGraceSeconds: Int64; let visibleSubject: WorkSubjectReferenceV1; let visibleWorkDefinition: ScheduledWorkDefinitionReferenceV1; let requiresExplicitSave: Bool }
}

enum OccurrenceDueReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case beforeReadyWindow = "UPCOMING_BEFORE_READY_WINDOW"
    case readyWindowOpen = "READY_WINDOW_OPEN"
    case dueWithinGrace = "DUE_WITHIN_GRACE"
    case overdueAfterGrace = "OVERDUE_AFTER_GRACE"
    case explicitlyDeferred = "EXPLICITLY_DEFERRED"
    case explicitlyMissed = "EXPLICITLY_MISSED"
    case explicitlySkipped = "EXPLICITLY_SKIPPED"
    case explicitlyCancelled = "EXPLICITLY_CANCELLED"
    case started = "STARTED"
    case completed = "COMPLETED"
}

struct OccurrenceDueQueueItemV1: Codable, Equatable, Sendable {
    let entry: DueQueueEntryV1
    let reason: OccurrenceDueReasonV1
}

struct OccurrenceDueQueueStateV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let evaluatedAt: Date
    let sourceClosureSHA256: String
    let items: [OccurrenceDueQueueItemV1]
    let stateSHA256: String

    init(projection: DueQueueProjectionV1) throws {
        workspaceID = projection.workspaceID; evaluatedAt = projection.evaluatedAt
        sourceClosureSHA256 = projection.sourceClosureSHA256
        items = try projection.entries.map { .init(entry: $0, reason: try Self.reason(for: $0.state)) }
        stateSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID: workspaceID,
            evaluatedAt: evaluatedAt, sourceClosureSHA256: sourceClosureSHA256, items: items))
        try validate()
    }
    func validate() throws {
        try ScheduleLimitsV1.instant(evaluatedAt); try ScheduleLimitsV1.digest(sourceClosureSHA256)
        for item in items {
            try item.entry.occurrenceID.validate(); try item.entry.scheduleRelease.validate()
            try item.entry.effectiveDueAtUTC.map(ScheduleLimitsV1.instant)
            try item.entry.workInstance?.validate()
        }
        guard items.count <= ScheduleLimitsV1.maximumGeneratedOccurrences,
              Set(items.map { $0.entry.occurrenceID }).count == items.count,
              items.allSatisfy({ $0.entry.scheduleRelease.workspaceID == workspaceID }),
              items == items.sorted(by: { ($0.entry.effectiveDueAtUTC ?? .distantFuture, $0.entry.occurrenceID) < ($1.entry.effectiveDueAtUTC ?? .distantFuture, $1.entry.occurrenceID) }),
              items.allSatisfy({ (try? Self.reason(for: $0.entry.state)) == $0.reason }),
              stateSHA256 == (try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID: workspaceID,
                evaluatedAt: evaluatedAt, sourceClosureSHA256: sourceClosureSHA256, items: items))) else {
            throw RecurringRoundExperienceFailureV1.invalidDigest
        }
    }
    private static func reason(for state: OccurrenceStateV1) throws -> OccurrenceDueReasonV1 {
        switch state { case .upcoming: return .beforeReadyWindow; case .ready: return .readyWindowOpen
        case .due: return .dueWithinGrace; case .overdue: return .overdueAfterGrace
        case .deferred: return .explicitlyDeferred; case .missed: return .explicitlyMissed
        case .skipped: return .explicitlySkipped; case .cancelled: return .explicitlyCancelled
        case .started: return .started; case .completed: return .completed }
    }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let evaluatedAt: Date; let sourceClosureSHA256: String; let items: [OccurrenceDueQueueItemV1] }
}

enum LocalReminderAuthorizationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case authorized = "AUTHORIZED", denied = "DENIED", notDetermined = "NOT_DETERMINED", unavailable = "UNAVAILABLE"
}
enum LocalReminderReconciliationDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case applied = "APPLIED", noChange = "NO_CHANGE", denied = "DENIED", unavailable = "UNAVAILABLE"
}

/// Device-local notification reconciliation. It cannot alter due-state truth.
struct LocalReminderReconciliationV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let dueQueueSHA256: String
    let reminderProjectionSHA256: String
    let authorization: LocalReminderAuthorizationV1
    let desiredNotificationIDs: [String]
    let desiredReminderEntries: [ReminderEntryV1]
    let observedNotificationIDs: [String]
    let observedReminderEntries: [ReminderEntryV1]
    let notificationIDsToRemove: [String]
    let reminderEntriesToApply: [ReminderEntryV1]
    let disposition: LocalReminderReconciliationDispositionV1
    let canonicalDueTruthChanged: Bool
    let reconciliationSHA256: String

    init(projection: ReminderProjectionV1, observedReminderEntries: [ReminderEntryV1], authorization: LocalReminderAuthorizationV1) throws {
        try projection.validate()
        let desired = projection.reminders.map(\.notificationID).sorted()
        let observedEntries = observedReminderEntries.sorted()
        let observed = observedEntries.map(\.notificationID).sorted()
        guard Set(desired).count == desired.count, Set(observed).count == observed.count,
              desired.count <= ScheduleLimitsV1.maximumGeneratedOccurrences,
              observed.count <= ScheduleLimitsV1.maximumGeneratedOccurrences else { throw RecurringRoundExperienceFailureV1.invalidValue }
        workspaceID = projection.workspaceID; dueQueueSHA256 = projection.dueQueueSHA256
        reminderProjectionSHA256 = projection.projectionSHA256; self.authorization = authorization
        desiredNotificationIDs = desired; desiredReminderEntries = projection.reminders.sorted()
        self.observedNotificationIDs = observed
        self.observedReminderEntries = observedEntries
        if authorization == .authorized {
            let desiredByID = Dictionary(uniqueKeysWithValues: projection.reminders.map { ($0.notificationID, $0) })
            let observedByID = Dictionary(uniqueKeysWithValues: observedEntries.map { ($0.notificationID, $0) })
            let changed = desired.filter { desiredByID[$0] != observedByID[$0] }
            notificationIDsToRemove = (observed.filter { desiredByID[$0] == nil } + changed.filter { observedByID[$0] != nil }).sorted()
            reminderEntriesToApply = changed.compactMap { desiredByID[$0] }.sorted()
            disposition = notificationIDsToRemove.isEmpty && reminderEntriesToApply.isEmpty ? .noChange : .applied
        } else {
            notificationIDsToRemove = []; reminderEntriesToApply = []
            disposition = authorization == .denied ? .denied : .unavailable
        }
        canonicalDueTruthChanged = false
        reconciliationSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID: workspaceID, dueQueueSHA256: dueQueueSHA256, reminderProjectionSHA256: reminderProjectionSHA256, authorization: authorization, desiredNotificationIDs: desiredNotificationIDs, desiredReminderEntries: desiredReminderEntries, observedNotificationIDs: observedNotificationIDs, observedReminderEntries: observedReminderEntries, notificationIDsToRemove: notificationIDsToRemove, reminderEntriesToApply: reminderEntriesToApply, disposition: disposition, canonicalDueTruthChanged: false))
        try validate()
    }
    func validate() throws {
        try ScheduleLimitsV1.digest(dueQueueSHA256); try ScheduleLimitsV1.digest(reminderProjectionSHA256)
        try desiredNotificationIDs.forEach(ScheduleLimitsV1.token)
        try observedNotificationIDs.forEach(ScheduleLimitsV1.token)
        try notificationIDsToRemove.forEach(ScheduleLimitsV1.token)
        try desiredReminderEntries.forEach { try ScheduleLimitsV1.token($0.notificationID); try $0.occurrenceID.validate(); try ScheduleLimitsV1.instant($0.fireAtUTC); try ScheduleLimitsV1.token($0.localizationKey) }
        try observedReminderEntries.forEach { try ScheduleLimitsV1.token($0.notificationID); try $0.occurrenceID.validate(); try ScheduleLimitsV1.instant($0.fireAtUTC); try ScheduleLimitsV1.token($0.localizationKey) }
        try reminderEntriesToApply.forEach { try ScheduleLimitsV1.token($0.notificationID); try $0.occurrenceID.validate(); try ScheduleLimitsV1.instant($0.fireAtUTC); try ScheduleLimitsV1.token($0.localizationKey) }
        let desired = Set(desiredNotificationIDs), observed = Set(observedNotificationIDs)
        let desiredByID = Dictionary(uniqueKeysWithValues: desiredReminderEntries.map { ($0.notificationID, $0) })
        let observedByID = Dictionary(uniqueKeysWithValues: observedReminderEntries.map { ($0.notificationID, $0) })
        let expectedChangedOrMissing = desired.filter { desiredByID[$0] != observedByID[$0] }.sorted()
        let expectedApplyEntries = expectedChangedOrMissing.compactMap { desiredByID[$0] }.sorted()
        let expectedRemoval = (observed.subtracting(desired).union(observed.intersection(Set(expectedChangedOrMissing)))).sorted()
        let authorized = authorization == .authorized
        let expectedDeniedDisposition: LocalReminderReconciliationDispositionV1 = authorization == .denied ? .denied : .unavailable
        guard !canonicalDueTruthChanged, desiredNotificationIDs == desiredNotificationIDs.sorted(), desiredReminderEntries == desiredReminderEntries.sorted(), desiredNotificationIDs == desiredReminderEntries.map(\.notificationID).sorted(), observedNotificationIDs == observedNotificationIDs.sorted(), observedReminderEntries == observedReminderEntries.sorted(), observedNotificationIDs == observedReminderEntries.map(\.notificationID).sorted(), notificationIDsToRemove == notificationIDsToRemove.sorted(), Set(desiredNotificationIDs).count == desiredNotificationIDs.count, Set(observedNotificationIDs).count == observedNotificationIDs.count,
              authorized ? (notificationIDsToRemove == expectedRemoval && reminderEntriesToApply == expectedApplyEntries && disposition == (expectedRemoval.isEmpty && expectedApplyEntries.isEmpty ? .noChange : .applied)) : (notificationIDsToRemove.isEmpty && reminderEntriesToApply.isEmpty && disposition == expectedDeniedDisposition),
              reconciliationSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else { throw RecurringRoundExperienceFailureV1.invalidDigest }
    }
    private var basis: Basis { .init(workspaceID: workspaceID, dueQueueSHA256: dueQueueSHA256, reminderProjectionSHA256: reminderProjectionSHA256, authorization: authorization, desiredNotificationIDs: desiredNotificationIDs, desiredReminderEntries: desiredReminderEntries, observedNotificationIDs: observedNotificationIDs, observedReminderEntries: observedReminderEntries, notificationIDsToRemove: notificationIDsToRemove, reminderEntriesToApply: reminderEntriesToApply, disposition: disposition, canonicalDueTruthChanged: canonicalDueTruthChanged) }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let dueQueueSHA256: String; let reminderProjectionSHA256: String; let authorization: LocalReminderAuthorizationV1; let desiredNotificationIDs: [String]; let desiredReminderEntries: [ReminderEntryV1]; let observedNotificationIDs: [String]; let observedReminderEntries: [ReminderEntryV1]; let notificationIDsToRemove: [String]; let reminderEntriesToApply: [ReminderEntryV1]; let disposition: LocalReminderReconciliationDispositionV1; let canonicalDueTruthChanged: Bool }
}

struct RecurringRoundStartRequestV1: Codable, Equatable, Sendable {
    let event: OccurrenceHistoryEventV1
    let predecessor: OccurrenceHistoryEventV1
    let release: ScheduleDefinitionReleaseV1
    let explicitUserConfirmation: Bool
    let requestSHA256: String
    init(event: OccurrenceHistoryEventV1, predecessor: OccurrenceHistoryEventV1,
         release: ScheduleDefinitionReleaseV1, explicitUserConfirmation: Bool) throws {
        self.event = event; self.predecessor = predecessor; self.release = release
        self.explicitUserConfirmation = explicitUserConfirmation
        requestSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(event: event, predecessor: predecessor, release: release, explicitUserConfirmation: explicitUserConfirmation))
        try validate()
    }
    func validate() throws {
        try release.validate(); try predecessor.validateIntrinsic(); try event.validate(predecessor: predecessor)
        guard explicitUserConfirmation, event.action == .start, event.workInstance != nil,
              event.workspaceID == release.workspaceID, predecessor.workspaceID == release.workspaceID,
              event.occurrenceID == predecessor.occurrenceID,
              event.scheduleRelease == (try ScheduleDefinitionReleaseReferenceV1(release)),
              requestSHA256 == (try ScheduleCanonicalCodecV1.sha256(basis)) else { throw RecurringRoundExperienceFailureV1.invalidValue }
    }
    private var basis: Basis { .init(event: event, predecessor: predecessor, release: release, explicitUserConfirmation: explicitUserConfirmation) }
    private struct Basis: Codable { let event: OccurrenceHistoryEventV1; let predecessor: OccurrenceHistoryEventV1; let release: ScheduleDefinitionReleaseV1; let explicitUserConfirmation: Bool }
}

struct RecurringRoundStartReceiptV1: Codable, Equatable, Sendable {
    let requestSHA256: String
    let scheduleReceipt: ScheduleMutationReceiptV1
    init(request: RecurringRoundStartRequestV1, scheduleReceipt: ScheduleMutationReceiptV1) throws {
        try request.validate(); self.requestSHA256 = request.requestSHA256; self.scheduleReceipt = scheduleReceipt
        let mutation = try ScheduleMutationV1(workspaceID: request.event.workspaceID, mutationID: request.event.mutationID, payload: .startOccurrence(request.event, predecessor: request.predecessor, release: request.release))
        let reconstructed = try ScheduleMutationReceiptV1(mutation: mutation, mutationReceipt: scheduleReceipt.mutationReceipt)
        guard scheduleReceipt == reconstructed,
              scheduleReceipt.mutationSHA256 == (try WorkspaceMutationCanonicalV1.sha256(mutation)) else { throw RecurringRoundExperienceFailureV1.invalidStartReceipt }
    }
    func validate(request: RecurringRoundStartRequestV1) throws {
        guard self == (try Self(request: request, scheduleReceipt: scheduleReceipt)) else {
            throw RecurringRoundExperienceFailureV1.invalidStartReceipt
        }
    }
}

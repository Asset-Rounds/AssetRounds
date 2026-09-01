import Foundation

@MainActor protocol DeviceLocalScheduleReminderPortV1: AnyObject {
    func authorization() async throws -> LocalReminderAuthorizationV1
    func scheduledReminders(workspaceID: WorkspaceID) async throws -> [ReminderEntryV1]
    func apply(workspaceID: WorkspaceID, remove notificationIDs: [String],
               add reminderEntries: [ReminderEntryV1]) async throws
    func removeAll(workspaceID: WorkspaceID) async throws
}

/// Concrete reconciliation over an injected OS notification port. It owns no
/// database and a denial, eviction, or process kill cannot change due truth.
@MainActor final class DeviceLocalScheduleReminderReconcilerV1: LocalReminderReconciliationApplyingV1 {
    private let port: any DeviceLocalScheduleReminderPortV1
    init(port: any DeviceLocalScheduleReminderPortV1) { self.port = port }

    func reconcile(_ projection: ReminderProjectionV1) async throws -> LocalReminderReconciliationV1 {
        let authorization = try await port.authorization()
        let observed = try await port.scheduledReminders(workspaceID: projection.workspaceID)
        let plan = try LocalReminderReconciliationV1(projection: projection,
            observedReminderEntries: observed, authorization: authorization)
        if plan.disposition == .applied {
            try await port.apply(workspaceID: projection.workspaceID,
                                 remove: plan.notificationIDsToRemove,
                                 add: plan.reminderEntriesToApply)
        }
        return plan
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

import Foundation

/// C28 lifecycle bridge. The journal is the replay authority and the existing
/// WorkspaceWriter remains the only canonical transaction boundary.
@MainActor final class ScheduleLifecycleAdapterV1: ScheduleCanonicalWritingV1 {
    private let writer: WorkspaceWriterV1
    private let journalStore: MutationJournalStoreV1

    init(writer: WorkspaceWriterV1, journalStore: MutationJournalStoreV1) {
        self.writer = writer
        self.journalStore = journalStore
    }

    func acceptedScheduleMutation(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1? {
        try journalStore.validateScheduleReferences(mutation)
        return try journalStore.acceptedScheduleMutation(mutation)
    }

    func applySchedule(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1 {
        try mutation.validate()
        try journalStore.validateScheduleReferences(mutation)
        if let accepted = try acceptedScheduleMutation(mutation) { return accepted }
        return try .init(mutation: mutation, mutationReceipt: writer.commitSchedule(mutation))
    }

    /// Relaunch-safe C51 reconciliation derives the same preview from durable
    /// C28/C51 inputs. No preview, timer, or recovery checkpoint is persisted.
    func recoverAdvancedProjection(definition: ScheduleDefinitionReleaseV1,
                                   binding: AdvancedScheduleReleaseBindingV1,
                                   calendar: ExceptionCalendarReleaseV1,
                                   overrideEvents: [ScheduleOverrideEventV1],
                                   occurrences: [ScheduleChangeOccurrenceInputV1],
                                   evaluatedRange: ScheduleLocalDateRangeV1,
                                   activeUpcomingWorkspaceCount: Int) throws -> ScheduleChangePreviewV1 {
        try ScheduleExceptionProjectionEngineV1.preview(definition: definition, binding: binding,
            calendar: calendar, existingOverrideEvents: overrideEvents, proposedOverride: nil,
            occurrences: occurrences, evaluatedRange: evaluatedRange,
            activeUpcomingWorkspaceCount: activeUpcomingWorkspaceCount)
    }

    static let c51RecoveryPersistsNoProjectionState = true
    static let c51UsesExistingCanonicalWriterOnly = true
}

/// Disposable reminder state. Permission or scheduling failure is surfaced and
/// never becomes canonical occurrence or notification truth.
protocol ScheduleReminderReconcilingV1: Sendable {
    func reconcile(_ projection: ReminderProjectionV1) async throws
    func removeAll(workspaceID: WorkspaceID) async throws
}

actor ScheduleReminderLifecycleV1 {
    private let reconciler: any ScheduleReminderReconcilingV1
    init(reconciler: any ScheduleReminderReconcilingV1) { self.reconciler = reconciler }
    func rebuild(_ projection: ReminderProjectionV1) async throws { try await reconciler.reconcile(projection) }
    func erase(workspaceID: WorkspaceID) async throws { try await reconciler.removeAll(workspaceID: workspaceID) }
}

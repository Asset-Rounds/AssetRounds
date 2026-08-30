import Foundation

/// C49 application boundary. It builds the sole C49 command and delegates the
/// durable mutation, receipt, journal, search invalidation, and replay work to
/// the existing WorkspaceWriterV1 boundary.
@MainActor
final class WorkResourceCoordinatorV1 {
    private let writer: WorkspaceWriterV1

    init(writer: WorkspaceWriterV1) { self.writer = writer }

    func append(_ entry: WorkResourceEntryV1) throws -> WorkResourceMutationReceiptV1 {
        try entry.validate()
        let mutation = try WorkResourceMutationV1(
            workspaceID: entry.workspaceID,
            mutationID: entry.mutationID,
            postImage: entry
        )
        let current = try writer.currentRevision()
        guard current.workspaceID == entry.workspaceID else {
            throw WorkResourceContractFailureV1.crossWorkspace
        }
        let concurrency = try mutation.concurrencyIdentity
        let currentEntityRevision = current.entityRevisions.first(where: {
            $0.identity == concurrency
        })?.revision ?? 0
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: concurrency,
                    revision: currentEntityRevision
                )
            ]
        )
        return try writer.commitWorkResource(mutation, expectedRevision: expected)
    }

    func append(
        entryID: UUID = UUID(),
        workspaceID: WorkspaceID,
        subject: WorkResourceSubjectV1,
        actor: ActorSnapshotV1,
        duration: ManualDurationV1? = nil,
        materials: [ManualMaterialLineV1] = [],
        directCost: DirectCostEntryV1? = nil,
        visibility: WorkResourceVisibilityV1 = .internalOnly,
        recordedAt: Date,
        expectedRevision: UInt64 = 0,
        supersedesEntryID: UUID? = nil,
        supersedesEntrySHA256: String? = nil
    ) throws -> WorkResourceMutationReceiptV1 {
        let mutationID = try writer.makeMutationID()
        let (revision, overflow) = expectedRevision.addingReportingOverflow(1)
        guard !overflow else { throw WorkResourceContractFailureV1.invalidRevision }
        let entry = try WorkResourceEntryV1(
            entryID: entryID,
            workspaceID: workspaceID,
            subject: subject,
            actor: actor,
            duration: duration,
            materials: materials,
            directCost: directCost,
            visibility: visibility,
            recordedAt: recordedAt,
            expectedRevision: expectedRevision,
            revision: revision,
            supersedesEntryID: supersedesEntryID,
            supersedesEntrySHA256: supersedesEntrySHA256,
            mutationID: mutationID
        )
        return try append(entry)
    }

    func void(
        predecessor: WorkResourceEntryV1,
        actor: ActorSnapshotV1,
        reason: String,
        recordedAt: Date
    ) throws -> WorkResourceMutationReceiptV1 {
        let mutationID = try writer.makeMutationID()
        let (revision, overflow) = predecessor.revision.addingReportingOverflow(1)
        guard !overflow else { throw WorkResourceContractFailureV1.invalidRevision }
        let entry = try WorkResourceEntryV1(
            entryID: UUID(), workspaceID: predecessor.workspaceID,
            subject: predecessor.subject, actor: actor,
            duration: predecessor.duration, materials: predecessor.materials,
            directCost: predecessor.directCost,
            visibility: predecessor.visibility, disposition: .voidedWithReason,
            voidReason: reason, recordedAt: recordedAt,
            expectedRevision: predecessor.revision,
            revision: revision,
            supersedesEntryID: predecessor.entryID,
            supersedesEntrySHA256: predecessor.entrySHA256,
            mutationID: mutationID
        )
        try entry.validateSuccessor(of: predecessor)
        return try append(entry)
    }
}

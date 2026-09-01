import Foundation

struct ImportBulkPreviewV1: Equatable, Sendable {
    let importPlan: ImportPlanV1
    let bulkPlan: BulkCommandPlanV1

    init(importPlan: ImportPlanV1, bulkPlan: BulkCommandPlanV1) throws {
        try importPlan.validate()
        try bulkPlan.validate(importPlan: importPlan)
        guard !importPlan.previewWritesCanonicalState else {
            throw ImportBulkFailureV1.invalidValue
        }
        self.importPlan = importPlan
        self.bulkPlan = bulkPlan
    }
}

struct ImportBulkMaterializerRegistrationV1: Sendable {
    let kind: ImportCommandKindV1
    let materializer: any ImportWorkspaceCommandMaterializingV1
    let allowedWorkspaceCommandKinds: Set<WorkspaceCommandKindV1>

    init(
        kind: ImportCommandKindV1,
        materializer: any ImportWorkspaceCommandMaterializingV1,
        allowedWorkspaceCommandKinds: Set<WorkspaceCommandKindV1>? = nil
    ) throws {
        let allowed = allowedWorkspaceCommandKinds ?? Self.legacyAllowedWorkspaceCommandKinds(for: kind)
        guard !allowed.isEmpty,
              !(kind.createsAggregate && allowedWorkspaceCommandKinds == nil) else {
            throw ImportBulkFailureV1.adapterCollision
        }
        self.kind = kind
        self.materializer = materializer
        self.allowedWorkspaceCommandKinds = allowed
    }

    private static func legacyAllowedWorkspaceCommandKinds(
        for kind: ImportCommandKindV1
    ) -> Set<WorkspaceCommandKindV1> {
        switch kind {
        case .createLocationNode:
            [.applyLocationHierarchyChange]
        case .createAsset:
            [.createFirstSign, .applyAssetSemantics]
        case .placeAsset:
            [.applyAssetPlacementChange]
        case .updateAssetExactKey:
            [.applyAssetSemantics]
        case .appendPlacementPose:
            [.applyPlacementPose]
        case .applyAtomicWorkspaceBundle:
            []
        }
    }
}

@MainActor
final class ImportBulkCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let lifecycle: ImportBulkLifecycleAdapterV1
    private let materializers: [ImportCommandKindV1: ImportBulkMaterializerRegistrationV1]

    /// ImportSourceV1 is external bounded scratch; zero canonical writes occur
    /// during preview and stable plan identities retain no source bytes.
    /// Deterministic export, formula/control neutralization, CSV formatting,
    /// and correction artifacts remain delegated to their incumbent seams.
    /// This coordinator accepts no alternate parser, renderer, or exporter.

    init(
        writer: WorkspaceWriterV1,
        lifecycle: ImportBulkLifecycleAdapterV1,
        materializers: [ImportBulkMaterializerRegistrationV1]
    ) throws {
        guard materializers.count == ImportCommandKindV1.allCases.count,
              Set(materializers.map(\.kind)) == Set(ImportCommandKindV1.allCases) else {
            throw ImportBulkFailureV1.adapterCollision
        }
        self.writer = writer
        self.lifecycle = lifecycle
        lifecycle.bind(writer: writer)
        self.materializers = Dictionary(uniqueKeysWithValues: materializers.map { ($0.kind, $0) })
    }

    /// Preview is validation-only: it never creates a session or calls writer.
    func preview(
        importPlan: ImportPlanV1,
        bulkPlan: BulkCommandPlanV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String
    ) throws -> ImportBulkPreviewV1 {
        try importPlan.validateCurrent(
            workspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
            sourceSHA256: currentSourceSHA256
        )
        return try ImportBulkPreviewV1(importPlan: importPlan, bulkPlan: bulkPlan)
    }

    func preview(
        importPlan: ImportPlanV1,
        bulkPlan: BulkCommandPlanV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String,
        accessGate: any AppAccessGatePortV1
    ) async throws -> ImportBulkPreviewV1 {
        _ = try await accessGate.requireContentAccess(for: .bulkImport)
        return try preview(
            importPlan: importPlan,
            bulkPlan: bulkPlan,
            currentSourceSHA256: currentSourceSHA256,
            currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
        )
    }

    /// C08 may hand a validated import artifact to C13 review, but it cannot
    /// materialize an alias or consolidation command.  This is intentionally
    /// typed rather than a new generic import command.
    func handoffToEntityIdentityResolution(
        plan: EntityIdentityResolutionPlanV1
    ) throws -> EntityIdentityResolutionPlanV1 {
        guard plan.workspaceID == (try writer.currentRevision()).workspaceID else {
            throw ImportBulkFailureV1.invalidValue
        }
        try plan.validate()
        return plan
    }

    /// Saving a reusable mapping is a C08 lifecycle mutation, never a direct
    /// SwiftData save. The adapter derives its deterministic mutation ID from
    /// the canonical profile digest and reuses the incumbent writer receipt.
    func saveMappingProfile(_ profile: ImportMappingProfileV1) throws {
        try profile.validate()
        guard profile.workspaceID == (try writer.currentRevision()).workspaceID else {
            throw ImportBulkFailureV1.invalidValue
        }
        try lifecycle.record(profile: profile)
    }

    func begin(
        sessionID: UUID,
        preview: ImportBulkPreviewV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String
    ) throws -> BulkSessionV1 {
        _ = try self.preview(
            importPlan: preview.importPlan,
            bulkPlan: preview.bulkPlan,
            currentSourceSHA256: currentSourceSHA256,
            currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
        )
        guard try lifecycle.durableSession(sessionID: sessionID) == nil else {
            throw ImportBulkFailureV1.adapterCollision
        }
        let session = try BulkSessionV1(
            sessionID: sessionID,
            workspaceID: preview.importPlan.workspaceID,
            bulkPlan: preview.bulkPlan,
            sourceSHA256: currentSourceSHA256,
            expectedWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
        )
        try lifecycle.record(session: session, replacing: nil)
        return session
    }

    func begin(
        sessionID: UUID,
        preview: ImportBulkPreviewV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String,
        accessGate: any AppAccessGatePortV1
    ) async throws -> BulkSessionV1 {
        _ = try await accessGate.requireContentAccess(for: .bulkImport)
        return try begin(
            sessionID: sessionID,
            preview: preview,
            currentSourceSHA256: currentSourceSHA256,
            currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256
        )
    }

    /// The incumbent writer has no batch-transaction API. C08 therefore
    /// accepts one writer transaction only: a one-row chunk, or the exact
    /// equivalent one-chunk all-or-nothing plan. Broader claims fail closed.
    func commitFirstMissingChunk(
        session: BulkSessionV1,
        importPlan: ImportPlanV1,
        bulkPlan: BulkCommandPlanV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String,
        cancellationRequested: Bool
    ) throws -> BulkSessionV1 {
        try importPlan.validateCurrent(
            workspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
            sourceSHA256: currentSourceSHA256
        )
        try bulkPlan.validate(importPlan: importPlan)
        try session.validateResumption(
            bulkPlan: bulkPlan,
            sourceSHA256: currentSourceSHA256,
            workspaceRevisionSHA256: currentWorkspaceRevisionSHA256
        )
        guard let durable = try lifecycle.durableSession(sessionID: session.sessionID),
              durable == session else {
            throw ImportBulkFailureV1.staleRevision
        }
        guard session.state == .active || session.state == .cancellationRequested else {
            throw ImportBulkFailureV1.invalidValue
        }
        guard let chunkIndex = try session.firstMissingReceiptChunkIndex(in: bulkPlan) else {
            return session
        }
        let chunk = bulkPlan.chunks[chunkIndex]
        let isOneTransactionAllOrNothing = bulkPlan.atomicity == .allOrNothing
            && bulkPlan.chunks.count == 1
        guard (bulkPlan.atomicity == .chunkedAtomic || isOneTransactionAllOrNothing),
              chunk.rowIdentitySHA256s.count == 1,
              chunk.mutationIDs.count == 1,
              let row = importPlan.rows.first(where: {
                  $0.identity.identitySHA256 == chunk.rowIdentitySHA256s[0]
              }), row.commands.count == 1 else {
            throw ImportBulkFailureV1.unsupportedSchema
        }

        if cancellationRequested || session.state == .cancellationRequested {
            let receipt = try bulkReceipt(
                bulkPlan: bulkPlan,
                chunkIndex: chunkIndex,
                expectedWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
                disposition: .cancelledBeforeCommit,
                committedMutationIDs: []
            )
            try lifecycle.record(receipt: receipt)
            let cancelled = try replacing(
                session: session,
                bulkPlan: bulkPlan,
                state: .cancelled,
                appending: receipt
            )
            try lifecycle.record(session: cancelled, replacing: session.sessionSHA256)
            return cancelled
        }

        // A process may terminate after the incumbent writer committed its
        // effect but before C08 persisted its immutable chunk receipt.  Probe
        // the writer's receipt authority first; never rematerialize the row
        // against a newer revision in that case.
        if try writer.durableReceipt(mutationID: chunk.mutationIDs[0]) != nil {
            return try recordCommittedChunk(
                session: session,
                bulkPlan: bulkPlan,
                chunkIndex: chunkIndex,
                expectedWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
                mutationID: chunk.mutationIDs[0]
            )
        }

        let command = row.commands[0]
        try lifecycle.validate(registrationFor: command.kind)
        guard let registration = materializers[command.kind] else {
            throw ImportBulkFailureV1.unsupportedSchema
        }
        let expected = WorkspaceExpectedRevisionV1(snapshot: try writer.currentRevision())
        let context = try ImportCommandMaterializationContextV1(
            plan: importPlan,
            rowIdentity: row.identity,
            row: row,
            command: command,
            chunkIndex: chunkIndex,
            mutationID: chunk.mutationIDs[0],
            expectedRevision: expected
        )
        let request = try registration.materializer.materializeValidated(context)
        guard registration.allowedWorkspaceCommandKinds.contains(request.command.kind) else {
            throw ImportBulkFailureV1.unsupportedSchema
        }

        _ = try writer.execute(request)
        guard try writer.durableReceipt(mutationID: request.mutationID) != nil else {
            throw ImportBulkFailureV1.staleRevision
        }
        return try recordCommittedChunk(
            session: session,
            bulkPlan: bulkPlan,
            chunkIndex: chunkIndex,
            expectedWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
            mutationID: request.mutationID
        )
    }

    func commitFirstMissingChunk(
        session: BulkSessionV1,
        importPlan: ImportPlanV1,
        bulkPlan: BulkCommandPlanV1,
        currentSourceSHA256: String,
        currentWorkspaceRevisionSHA256: String,
        cancellationRequested: Bool,
        accessGate: any AppAccessGatePortV1
    ) async throws -> BulkSessionV1 {
        _ = try await accessGate.requireContentAccess(for: .bulkImport)
        return try commitFirstMissingChunk(
            session: session,
            importPlan: importPlan,
            bulkPlan: bulkPlan,
            currentSourceSHA256: currentSourceSHA256,
            currentWorkspaceRevisionSHA256: currentWorkspaceRevisionSHA256,
            cancellationRequested: cancellationRequested
        )
    }

    private func recordCommittedChunk(
        session: BulkSessionV1,
        bulkPlan: BulkCommandPlanV1,
        chunkIndex: Int,
        expectedWorkspaceRevisionSHA256: String,
        mutationID: MutationIDV1
    ) throws -> BulkSessionV1 {
        if let existing = try lifecycle.durableReceipt(
            workspaceID: bulkPlan.workspaceID,
            bulkPlan: bulkPlan,
            chunkIndex: chunkIndex
        ) {
            guard existing.disposition == .committed,
                  existing.committedMutationIDs == [mutationID] else {
                throw ImportBulkFailureV1.changedInputQuarantined
            }
            let updated = try replacing(
                session: session,
                bulkPlan: bulkPlan,
                state: chunkIndex + 1 == bulkPlan.chunks.count ? .completed : .active,
                appending: existing
            )
            try lifecycle.record(session: updated, replacing: session.sessionSHA256)
            return updated
        }
        let receipt = try bulkReceipt(
            bulkPlan: bulkPlan,
            chunkIndex: chunkIndex,
            expectedWorkspaceRevisionSHA256: expectedWorkspaceRevisionSHA256,
            disposition: .committed,
            committedMutationIDs: [mutationID]
        )
        try lifecycle.record(receipt: receipt)
        let state: BulkSessionStateV1 = chunkIndex + 1 == bulkPlan.chunks.count ? .completed : .active
        let updated = try replacing(
            session: session,
            bulkPlan: bulkPlan,
            state: state,
            appending: receipt
        )
        try lifecycle.record(session: updated, replacing: session.sessionSHA256)
        return updated
    }

    private func replacing(
        session: BulkSessionV1,
        bulkPlan: BulkCommandPlanV1,
        state: BulkSessionStateV1,
        appending receipt: BulkCommitReceiptV1
    ) throws -> BulkSessionV1 {
        guard !session.chunkReceipts.contains(where: { $0.chunkIndex == receipt.chunkIndex }) else {
            throw ImportBulkFailureV1.adapterCollision
        }
        return try BulkSessionV1(
            sessionID: session.sessionID,
            workspaceID: session.workspaceID,
            bulkPlan: bulkPlan,
            sourceSHA256: session.sourceSHA256,
            expectedWorkspaceRevisionSHA256: session.expectedWorkspaceRevisionSHA256,
            state: state,
            chunkReceipts: (session.chunkReceipts + [receipt]).sorted()
        )
    }

    private func bulkReceipt(
        bulkPlan: BulkCommandPlanV1,
        chunkIndex: Int,
        expectedWorkspaceRevisionSHA256: String,
        disposition: BulkCommitDispositionV1,
        committedMutationIDs: [MutationIDV1]
    ) throws -> BulkCommitReceiptV1 {
        let receiptID = try ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "bulk-commit-receipt-v1",
            basis: BulkReceiptIDBasis(
                bulkPlanSHA256: bulkPlan.planSHA256,
                chunkIndex: chunkIndex,
                expectedWorkspaceRevisionSHA256: expectedWorkspaceRevisionSHA256,
                disposition: disposition,
                committedMutationIDs: committedMutationIDs
            )
        )
        return try BulkCommitReceiptV1(
            receiptID: receiptID,
            workspaceID: bulkPlan.workspaceID,
            bulkPlan: bulkPlan,
            chunkIndex: chunkIndex,
            expectedWorkspaceRevisionSHA256: expectedWorkspaceRevisionSHA256,
            disposition: disposition,
            committedMutationIDs: committedMutationIDs
        )
    }
}

private struct BulkReceiptIDBasis: Codable {
    let bulkPlanSHA256: String
    let chunkIndex: Int
    let expectedWorkspaceRevisionSHA256: String
    let disposition: BulkCommitDispositionV1
    let committedMutationIDs: [MutationIDV1]
}

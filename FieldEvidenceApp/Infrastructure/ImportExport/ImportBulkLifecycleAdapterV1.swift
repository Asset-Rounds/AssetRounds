import Foundation
import SwiftData

/// Main-actor lifecycle authority for the three enrolled C08 durable rows.
/// Source bytes, scratch parsing, previews, and correction staging never
/// reach this context.
@MainActor
final class ImportBulkLifecycleAdapterV1 {
    static let durableModelNames = [
        "ImportMappingProfileRowV1",
        "BulkSessionRowV1",
        "BulkCommitReceiptRowV1",
    ]

    private let registrations: [ImportAdapterRegistrationV1]
    private let modelContext: ModelContext
    private weak var writer: WorkspaceWriterV1?

    init(
        registrations: [ImportAdapterRegistrationV1],
        modelContext: ModelContext
    ) throws {
        try ImportAdapterRegistryV1.validate(registrations)
        let registeredKinds = Set(registrations.flatMap(\.commandKinds))
        guard registrations.count <= ImportBulkLimitsV1.maximumAdapterDependencies,
              registeredKinds == Set(ImportCommandKindV1.allCases),
              !registrations.contains(where: { $0.privacyClass == .prohibited }) else {
            throw ImportBulkFailureV1.adapterCollision
        }
        self.registrations = registrations
        self.modelContext = modelContext
    }

    /// Wiring occurs only from the coordinator that already owns the canonical
    /// writer. Keeping construction compatible with read-only lifecycle users
    /// avoids creating a second writer or persistence authority.
    func bind(writer: WorkspaceWriterV1) {
        self.writer = writer
    }

    func durableSession(sessionID: UUID) throws -> BulkSessionV1? {
        let rows = try modelContext.fetch(
            FetchDescriptor<BulkSessionRowV1>(predicate: #Predicate { $0.sessionID == sessionID })
        )
        guard rows.count <= 1 else { throw ImportBulkFailureV1.adapterCollision }
        guard let row = rows.first else { return nil }
        let value = try row.value()
        try value.validate()
        return value
    }

    func durableSession(
        sessionID: UUID,
        accessGate: any AppAccessGatePortV1
    ) async throws -> BulkSessionV1? {
        _ = try await accessGate.requireContentAccess(for: .bulkImport)
        return try durableSession(sessionID: sessionID)
    }

    /// Immutable receipt persistence is a canonical writer mutation. A retry
    /// reads back the exact immutable row before reissuing the same operation.
    func record(receipt: BulkCommitReceiptV1) throws {
        try receipt.validate()
        let rows = try modelContext.fetch(
            FetchDescriptor<BulkCommitReceiptRowV1>(predicate: #Predicate { $0.receiptID == receipt.receiptID })
        )
        guard rows.count <= 1 else { throw ImportBulkFailureV1.adapterCollision }
        if let existing = rows.first {
            guard try existing.value().receiptSHA256 == receipt.receiptSHA256 else {
                throw ImportBulkFailureV1.changedInputQuarantined
            }
            return
        }
        try execute(operation: .appendReceipt(receipt))
    }

    /// Closed lookup used by recovery. A receipt is addressed by its durable
    /// plan/chunk identity, not a display value or an incidental row order.
    func durableReceipt(
        workspaceID: WorkspaceID,
        bulkPlan: BulkCommandPlanV1,
        chunkIndex: Int
    ) throws -> BulkCommitReceiptV1? {
        try bulkPlan.validate()
        guard bulkPlan.chunks.indices.contains(chunkIndex) else {
            throw ImportBulkFailureV1.invalidValue
        }
        let workspaceRawValue = workspaceID.rawValue
        let bulkPlanID = bulkPlan.bulkPlanID
        let exactChunkIndex = chunkIndex
        let rows = try modelContext.fetch(
            FetchDescriptor<BulkCommitReceiptRowV1>(predicate: #Predicate {
                $0.workspaceID == workspaceRawValue
                    && $0.bulkPlanID == bulkPlanID
                    && $0.chunkIndex == exactChunkIndex
            })
        )
        guard rows.count <= 1 else { throw ImportBulkFailureV1.adapterCollision }
        guard let row = rows.first else { return nil }
        let value = try row.value()
        try value.validate()
        guard value.workspaceID == workspaceID,
              value.bulkPlanID == bulkPlan.bulkPlanID,
              value.bulkPlanSHA256 == bulkPlan.planSHA256,
              value.chunkIndex == chunkIndex,
              value.rowIdentitySHA256s == bulkPlan.chunks[chunkIndex].rowIdentitySHA256s,
              value.mutationIDs == bulkPlan.chunks[chunkIndex].mutationIDs else {
            throw ImportBulkFailureV1.changedInputQuarantined
        }
        return value
    }

    func record(session: BulkSessionV1, replacing expectedSessionSHA256: String?) throws {
        try session.validate()
        try expectedSessionSHA256.map(ImportBulkCanonicalCodecV1.requireDigest)
        let rows = try modelContext.fetch(
            FetchDescriptor<BulkSessionRowV1>(predicate: #Predicate { $0.sessionID == session.sessionID })
        )
        guard rows.count <= 1 else { throw ImportBulkFailureV1.adapterCollision }
        if let existing = rows.first {
            let prior = try existing.value()
            if prior.sessionSHA256 == session.sessionSHA256 { return }
            guard expectedSessionSHA256 == prior.sessionSHA256 else {
                throw ImportBulkFailureV1.changedInputQuarantined
            }
        } else {
            guard expectedSessionSHA256 == nil else {
                throw ImportBulkFailureV1.changedInputQuarantined
            }
        }
        try execute(operation: .advanceSession(
            session: session,
            expectedSessionSHA256: expectedSessionSHA256
        ))
    }

    func record(profile: ImportMappingProfileV1) throws {
        try profile.validate()
        let rows = try modelContext.fetch(FetchDescriptor<ImportMappingProfileRowV1>(
            predicate: #Predicate { $0.profileID == profile.profileID }
        ))
        guard rows.count <= 1 else { throw ImportBulkFailureV1.adapterCollision }
        if let existing = rows.first {
            let prior = try existing.value()
            if prior.profileSHA256 == profile.profileSHA256 { return }
            try execute(operation: .upsertMappingProfile(
                profile: profile,
                expectedProfileSHA256: prior.profileSHA256
            ))
        } else {
            try execute(operation: .upsertMappingProfile(
                profile: profile,
                expectedProfileSHA256: nil
            ))
        }
    }

    /// Same-digest retries are idempotent: public record methods read the
    /// exact durable row first, while this path owns the one journal-backed
    /// attempt for a previously absent effect.
    private func execute(operation: ImportBulkWorkspaceOperationV1) throws {
        guard let writer else { throw ImportBulkFailureV1.adapterCollision }
        let current = try writer.currentRevision()
        let identity = try operation.affectedIdentity
        let revision = current.entityRevisions.first(where: { $0.identity == identity })?.revision ?? 0
        let mutationID = try MutationIDV1(rawValue: ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "c08-workspace-lifecycle-v1",
            basis: C08ImportBulkMutationIDBasis(
                workspaceID: operation.workspaceID,
                kind: identity.kind.rawValue,
                id: identity.id,
                expectedRevision: revision
            )
        ))
        let mutation = try ImportBulkWorkspaceMutationV1(
            workspaceID: operation.workspaceID,
            expectedRevision: revision,
            mutationID: mutationID,
            operation: operation
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [.init(identity: identity, revision: revision)]
        )
        _ = try writer.execute(.init(
            mutationID: mutationID,
            expectedRevision: expected,
            command: .applyImportBulk(mutation)
        ))
    }

    func validate(registrationFor kind: ImportCommandKindV1) throws {
        guard registrations.contains(where: { $0.commandKinds.contains(kind) }) else {
            throw ImportBulkFailureV1.unsupportedSchema
        }
    }
}

private struct C08ImportBulkMutationIDBasis: Codable {
    let workspaceID: WorkspaceID
    let kind: String
    let id: UUID
    let expectedRevision: UInt64
}

enum ImportBulkLifecycleBoundaryV1 {
    /// Bounded scratch input is dropped on interruption; it is never a backup,
    /// restore, export, replay, rebuild, delete, or erase source. Those
    /// lifecycle operations consume only the enrolled canonical rows.
    static let sourceBytesAreScratchOnly = true
    static let previewsAreDerivedOnly = true
    static let correctionStagingIsNonpersistent = true
    static let canonicalWriterIsReused = true
    static let createsParallelStore = false
}

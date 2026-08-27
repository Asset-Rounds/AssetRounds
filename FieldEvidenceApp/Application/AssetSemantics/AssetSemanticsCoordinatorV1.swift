import Foundation

enum AssetSemanticsCoordinatorFailureV1: Error, Equatable, Sendable {
    case invalidPlan
    case staleRevision
    case missingDurableReceipt
    case receiptMismatch
}

/// Read/validation-only seam for C39.  Implementations may inspect the
/// durable semantic rows, but all writes still go through WorkspaceWriterV1.
@MainActor
protocol AssetSemanticLifecyclePortV1: AnyObject {
    func validate(_ mutation: AssetSemanticsMutationV1) throws
}

struct AssetSemanticsPreviewBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutation: AssetSemanticsMutationV1

    init(
        workspaceID: WorkspaceID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutation: AssetSemanticsMutationV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.mutation = mutation
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              expectedRevision.workspaceID == workspaceID,
              mutation.workspaceID == workspaceID else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        try mutation.validate()
        let target = try mutation.affectedIdentity
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expectedRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        guard expectedRevision.generationID != Self.zeroUUID,
              expectedRevision.workspaceRevision < UInt64.max,
              expectedByIdentity[target] == mutation.expectedAssetRevision else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// A C39 preview is immutable.  The operation ID identifies this plan while
/// the embedded MutationIDV1 is the idempotency identity consumed by the
/// canonical writer and journal.
struct AssetSemanticsChangePlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let mutationID: MutationIDV1
    let basis: AssetSemanticsPreviewBasisV1
    let planSHA256: String

    init(
        operationID: UUID,
        mutationID: MutationIDV1,
        basis: AssetSemanticsPreviewBasisV1
    ) throws {
        guard operationID != Self.zeroUUID else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        try basis.validate()
        guard basis.mutation.mutationID == mutationID else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.mutationID = mutationID
        self.basis = basis
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                operationID: operationID,
                mutationID: mutationID,
                basis: basis
            )
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              operationID != Self.zeroUUID,
              basis.mutation.mutationID == mutationID,
              MutationEnvelopeV1.isSHA256(planSHA256) else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
        try basis.validate()
        guard planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: schemaVersion,
                operationID: operationID,
                mutationID: mutationID,
                basis: basis
            )
        )) else {
            throw AssetSemanticsCoordinatorFailureV1.invalidPlan
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let operationID: UUID
        let mutationID: MutationIDV1
        let basis: AssetSemanticsPreviewBasisV1
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// The only application writer seam for C39 asset-semantic mutations.
@MainActor
final class AssetSemanticsCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let idSource: any ApplicationIDSource
    private let lifecycle: (any AssetSemanticLifecyclePortV1)?

    init(
        writer: WorkspaceWriterV1,
        idSource: any ApplicationIDSource,
        lifecycle: (any AssetSemanticLifecyclePortV1)? = nil
    ) {
        self.writer = writer
        self.idSource = idSource
        self.lifecycle = lifecycle
    }

    func makeMutationID() throws -> MutationIDV1 {
        try writer.makeMutationID()
    }

    func preview(
        _ basis: AssetSemanticsPreviewBasisV1
    ) throws -> AssetSemanticsChangePlanV1 {
        try basis.validate()
        let observed = try writer.currentRevision()
        guard try Self.revision(from: basis.expectedRevision) == observed else {
            throw AssetSemanticsCoordinatorFailureV1.staleRevision
        }
        try lifecycle?.validate(basis.mutation)
        guard try writer.currentRevision() == observed else {
            throw AssetSemanticsCoordinatorFailureV1.staleRevision
        }
        let plan = try AssetSemanticsChangePlanV1(
            operationID: idSource.makeID(),
            mutationID: basis.mutation.mutationID,
            basis: basis
        )
        guard try writer.currentRevision() == observed else {
            throw AssetSemanticsCoordinatorFailureV1.staleRevision
        }
        return plan
    }

    func preview(
        mutation: AssetSemanticsMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        workspaceID: WorkspaceID
    ) throws -> AssetSemanticsChangePlanV1 {
        try preview(
            AssetSemanticsPreviewBasisV1(
                workspaceID: workspaceID,
                expectedRevision: expectedRevision,
                mutation: mutation
            )
        )
    }

    func commit(
        _ plan: AssetSemanticsChangePlanV1
    ) throws -> AssetSemanticsChangeReceiptV1 {
        try plan.validate()
        try lifecycle?.validate(plan.basis.mutation)
        _ = try writer.execute(WorkspaceMutationRequestV1(
            mutationID: plan.mutationID,
            expectedRevision: plan.basis.expectedRevision,
            command: .applyAssetSemantics(plan.basis.mutation)
        ))
        guard let durableReceipt = try writer.durableReceipt(
            mutationID: plan.mutationID
        ) else {
            throw AssetSemanticsCoordinatorFailureV1.missingDurableReceipt
        }
        do {
            return try AssetSemanticsChangeReceiptV1(
                plan: plan,
                mutationReceipt: durableReceipt
            )
        } catch let failure as AssetSemanticsCoordinatorFailureV1 {
            throw failure
        } catch {
            throw AssetSemanticsCoordinatorFailureV1.receiptMismatch
        }
    }

    func commit(
        mutation: AssetSemanticsMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        workspaceID: WorkspaceID
    ) throws -> AssetSemanticsChangeReceiptV1 {
        try commit(preview(
            mutation: mutation,
            expectedRevision: expectedRevision,
            workspaceID: workspaceID
        ))
    }

    private static func revision(
        from expected: WorkspaceExpectedRevisionV1
    ) throws -> WorkspaceRevisionV1 {
        try WorkspaceRevisionV1(
            workspaceID: expected.workspaceID,
            generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID,
            revision: expected.workspaceRevision,
            entityRevisions: expected.entityRevisions
        )
    }
}

typealias AssetSemanticsPlanV1 = AssetSemanticsChangePlanV1
typealias AssetSemanticsReceiptV1 = AssetSemanticsChangeReceiptV1

import Foundation

enum AssetServiceReliabilityCoordinatorFailureV1: Error, Equatable, Sendable {
    case invalidExpectedRevision
    case receiptMismatch
}

/// A zero-write, fully scoped canonical mutation plan. The caller supplies a
/// writer-issued workspace snapshot; after payload IDs exist, the coordinator
/// narrows it to exactly the concurrency identities used by the bundle.
struct AssetServiceReliabilityCommitPlanV1: Equatable, Sendable {
    let bundle: ServiceReliabilityAtomicBundleV1
    let zeroWrite: Bool

    init(
        expectedRevision source: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        payloads: [ServiceReliabilityMutationPayloadV1]
    ) throws {
        let validatedSource = try WorkspaceExpectedRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            writerInstanceID: source.writerInstanceID,
            workspaceRevision: source.workspaceRevision,
            entityRevisions: source.entityRevisions
        )
        let known = Dictionary(
            uniqueKeysWithValues: validatedSource.entityRevisions.map { ($0.identity, $0.revision) }
        )
        let required = try payloads.map { payload in
            let identity = try payload.concurrencyIdentity
            let expected = payload.expectedEntityRevision
            guard known[identity, default: 0] == expected else {
                throw AssetServiceReliabilityCoordinatorFailureV1.invalidExpectedRevision
            }
            return WorkspaceEntityRevisionV1(identity: identity, revision: expected)
        }
        let scoped = try WorkspaceExpectedRevisionV1(
            workspaceID: validatedSource.workspaceID,
            generationID: validatedSource.generationID,
            writerInstanceID: validatedSource.writerInstanceID,
            workspaceRevision: validatedSource.workspaceRevision,
            entityRevisions: required
        )
        bundle = try ServiceReliabilityAtomicBundleV1(
            workspaceID: scoped.workspaceID,
            expectedRevision: scoped,
            mutationID: mutationID,
            payloads: payloads
        )
        zeroWrite = true
        try validate()
    }

    func validate() throws {
        try bundle.validateForCanonicalWriter()
        let concurrency = try bundle.concurrencyIdentities
        guard zeroWrite,
              bundle.expectedRevision.entityRevisions.count == concurrency.count,
              bundle.expectedRevision.entityRevisions.map(\.identity) == concurrency else {
            throw AssetServiceReliabilityCoordinatorFailureV1.invalidExpectedRevision
        }
    }
}

@MainActor
final class AssetServiceReliabilityCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let lifecycle: AssetServiceReliabilityLifecycleAdapterV1

    init(
        writer: WorkspaceWriterV1,
        lifecycle: AssetServiceReliabilityLifecycleAdapterV1
    ) {
        self.writer = writer
        self.lifecycle = lifecycle
    }

    func previewCommit(
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        payloads: [ServiceReliabilityMutationPayloadV1]
    ) throws -> AssetServiceReliabilityCommitPlanV1 {
        let current = try writer.currentRevision()
        guard current.workspaceID == expectedRevision.workspaceID,
              current.generationID == expectedRevision.generationID,
              current.writerInstanceID == expectedRevision.writerInstanceID,
              current.revision == expectedRevision.workspaceRevision else {
            throw AssetServiceReliabilityCoordinatorFailureV1.invalidExpectedRevision
        }
        return try AssetServiceReliabilityCommitPlanV1(
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            payloads: payloads
        )
    }

    /// WorkspaceWriterV1 is the only commit route and is idempotent by
    /// mutation ID. The typed receipt is revalidated against the exact plan.
    func commit(
        _ plan: AssetServiceReliabilityCommitPlanV1
    ) async throws -> ServiceReliabilityMutationReceiptV1 {
        try plan.validate()
        let receipt = try writer.commitServiceReliability(plan.bundle)
        try Self.validate(receipt, for: plan.bundle)
        return receipt
    }

    func importAccepted(_ bundles: [ServiceReliabilityAtomicBundleV1]) async throws {
        try await lifecycle.importAccepted(bundles)
    }

    func restoreAccepted(_ bundles: [ServiceReliabilityAtomicBundleV1]) async throws {
        try await lifecycle.restoreAccepted(bundles)
    }

    func replayAccepted(_ bundles: [ServiceReliabilityAtomicBundleV1]) async throws {
        try await lifecycle.replayAccepted(bundles)
    }

    func rebuildDerivedProjection(
        from bundles: [ServiceReliabilityAtomicBundleV1]
    ) async throws {
        try await lifecycle.rebuildDerivedProjection(from: bundles)
    }

    func erase(workspaceID: WorkspaceID) async throws {
        try await lifecycle.erase(workspaceID: workspaceID)
    }

    private static func validate(
        _ receipt: ServiceReliabilityMutationReceiptV1,
        for bundle: ServiceReliabilityAtomicBundleV1
    ) throws {
        try receipt.mutationReceipt.validate()
        let expected = receipt.mutationReceipt.expectedRevision
        let resulting = Dictionary(
            uniqueKeysWithValues: receipt.mutationReceipt.resultingRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let postImages = try bundle.mutationPostImages
        guard receipt.bundleSHA256 == bundle.bundleSHA256,
              receipt.mutationReceipt.mutationID == bundle.mutationID,
              receipt.mutationReceipt.identity.workspaceID == bundle.workspaceID,
              expected.workspaceID == bundle.expectedRevision.workspaceID,
              expected.generationID == bundle.expectedRevision.generationID,
              expected.workspaceRevision == bundle.expectedRevision.workspaceRevision,
              expected.entityRevisions == bundle.expectedRevision.entityRevisions,
              receipt.mutationReceipt.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.applyServiceReliability(bundle)
              )),
              receipt.postImages == postImages,
              receipt.mutationReceipt.postImages == postImages,
              try postImages.allSatisfy({ resulting[try $0.identity] == $0.revision }) else {
            throw AssetServiceReliabilityCoordinatorFailureV1.receiptMismatch
        }
    }
}

enum C53AssetServiceReliabilityApplicationBoundaryV1 {
    static let previewWritesWorkspace = false
    static let commitUsesExistingWorkspaceWriter = true
    static let createsSecondMutableTruth = false
    static let projectionIsRebuildable = true
    static let automaticExternalConditionImport = false
    static let automaticCauseConfirmation = false
    static let restorationGrantsOperationalAuthority = false
}

import Foundation

/// Lifecycle callbacks supplied by the existing canonical persistence and
/// device-lifecycle composition. They do not authorize another writer or row
/// store; every bundle has already been accepted by the sole workspace writer.
struct AssetServiceReliabilityLifecycleOperationsV1: Sendable {
    typealias Apply = @Sendable ([ServiceReliabilityAtomicBundleV1]) async throws -> Void
    typealias Erase = @Sendable (WorkspaceID) async throws -> Void

    let importAccepted: Apply
    let restoreAccepted: Apply
    let replayAccepted: Apply
    let rebuildDerivedProjection: Apply
    let eraseWorkspace: Erase
}

/// Stateless validation and lifecycle delegation for the C53 durable families.
/// Metric projections remain rebuildable values produced by the domain engine;
/// this adapter never persists them or mirrors canonical event truth.
actor AssetServiceReliabilityLifecycleAdapterV1 {
    private let operations: AssetServiceReliabilityLifecycleOperationsV1

    init(operations: AssetServiceReliabilityLifecycleOperationsV1) {
        self.operations = operations
    }

    func importAccepted(_ bundles: [ServiceReliabilityAtomicBundleV1]) async throws {
        try Self.validate(bundles)
        try await operations.importAccepted(bundles)
    }

    func restoreAccepted(_ bundles: [ServiceReliabilityAtomicBundleV1]) async throws {
        try Self.validate(bundles)
        try await operations.restoreAccepted(bundles)
    }

    func replayAccepted(_ bundles: [ServiceReliabilityAtomicBundleV1]) async throws {
        try Self.validate(bundles)
        try await operations.replayAccepted(bundles)
    }

    func rebuildDerivedProjection(
        from bundles: [ServiceReliabilityAtomicBundleV1]
    ) async throws {
        try Self.validate(bundles)
        try await operations.rebuildDerivedProjection(bundles)
    }

    func erase(workspaceID: WorkspaceID) async throws {
        try await operations.eraseWorkspace(workspaceID)
    }

    private static func validate(_ bundles: [ServiceReliabilityAtomicBundleV1]) throws {
        guard !bundles.isEmpty else { return }
        try bundles.forEach { try $0.validateForCanonicalWriter() }
        guard Set(bundles.map(\.workspaceID)).count == 1,
              Set(bundles.map(\.mutationID.rawValue)).count == bundles.count else {
            throw ServiceReliabilityFailureV1.invalidValue
        }
    }
}

enum C53AssetServiceReliabilityLifecycleBoundaryV1 {
    static let createsSecondWriter = false
    static let createsSecondMutableStore = false
    static let derivedProjectionIsPersistent = false
    static let importRestoreReplayRevalidateCanonicalBundles = true
    static let rebuildDelegatesToExistingLifecycleComposition = true
    static let eraseDelegatesToExistingLifecycleComposition = true
}

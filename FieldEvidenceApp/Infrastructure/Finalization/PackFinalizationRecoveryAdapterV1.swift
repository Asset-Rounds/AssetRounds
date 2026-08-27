import Foundation
import SwiftData

struct PackFinalizationRecoveryOutcomeV1: Equatable, Sendable {
    let summary: FinalizationRecoverySummary
    let workspaceID: WorkspaceID
    let generationID: UUID
    let packageRelease: PackageReleaseIdentityV1
    let preservesReservedLegacyRawWriteDebt: Bool
    let zeroFeatureWriteClosureClaimed: Bool
}

/// Ratcheted compatibility boundary over the S10-reserved recovery service.
/// It preserves the second declared raw-write debt until S10.6 reconciliation.
@MainActor
final class PackFinalizationRecoveryAdapterV1 {
    static let compatibilityOwner = "V23-P03-C08"
    static let expiresAfter = WorkspacePackageLifecycleCompatibilityV1.expiration

    private let dependencies: WorkspacePackageLifecycleDependenciesV1
    private let profile: WorkspacePackageLifecycleProfileV1
    private let service: FinalizationRecoveryService

    init(
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        profile: WorkspacePackageLifecycleProfileV1,
        legacyModelContext: ModelContext
    ) throws {
        guard try dependencies.profileRegistry.resolve(profile.release) == profile,
              profile.release.matches(profile.package) else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        self.dependencies = dependencies
        self.profile = profile
        service = FinalizationRecoveryService(
            modelContext: legacyModelContext,
            generationRootURL: dependencies.generationRootURL
        )
    }

    func reconcile() async throws -> PackFinalizationRecoveryOutcomeV1 {
        try Task.checkCancellation()
        let request = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: dependencies.workspaceID,
            generationID: dependencies.generationID,
            operation: .recover,
            identities: []
        )
        _ = try dependencies.queryClient.query(request)
        let summary = try await service.reconcile()
        return PackFinalizationRecoveryOutcomeV1(
            summary: summary,
            workspaceID: dependencies.workspaceID,
            generationID: dependencies.generationID,
            packageRelease: profile.release,
            preservesReservedLegacyRawWriteDebt: true,
            zeroFeatureWriteClosureClaimed: false
        )
    }
}

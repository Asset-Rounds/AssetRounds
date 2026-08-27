import Foundation
import SwiftData

struct PackFinalizationAdapterOutcomeV1: Equatable, Sendable {
    let finalization: FinalizationServiceOutcome
    let binding: PackFinalizationBindingV1
    let durableReceiptIdentity: MutationReceiptIdentityV1?
    let zeroFeatureWriteClosureClaimed: Bool
}

/// Ratcheted compatibility boundary over the S10-reserved finalizer.
///
/// This adapter expires only after accepted S10.6 reconciliation. Until then
/// the wrapped service remains one of the two declared raw-write debts, so a
/// missing WorkspaceWriter receipt is reported explicitly and never fabricated.
@MainActor
final class PackFinalizationAdapterV1 {
    static let compatibilityOwner = "V23-P03-C08"
    static let expiresAfter = WorkspacePackageLifecycleCompatibilityV1.expiration

    private let dependencies: WorkspacePackageLifecycleDependenciesV1
    private let profile: WorkspacePackageLifecycleProfileV1
    private let service: FinalizationService

    init(
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        profile: WorkspacePackageLifecycleProfileV1,
        legacyModelContext: ModelContext,
        intentStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil,
        failureInjection: FinalizationServiceFailureInjection? = nil
    ) throws {
        guard try dependencies.profileRegistry.resolve(profile.release) == profile,
              profile.release.matches(profile.package) else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        self.dependencies = dependencies
        self.profile = profile
        service = try FinalizationService(
            modelContext: legacyModelContext,
            signPack: profile.package,
            generationRootURL: dependencies.generationRootURL,
            intentStoreFailureInjection: intentStoreFailureInjection,
            failureInjection: failureInjection
        )
    }

    func finalize(
        _ input: FinalizationServiceInput,
        binding: PackFinalizationBindingV1
    ) async throws -> PackFinalizationAdapterOutcomeV1 {
        try Task.checkCancellation()
        guard binding.workspaceID == dependencies.workspaceID,
              binding.generationID == dependencies.generationID,
              binding.packageRelease == profile.release,
              binding.mutationID.rawValue == input.identifiers.mutationID,
              binding.preservesReservedLegacyRawWriteDebt else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: input.asset.id)
        let recordIdentity = try WorkspaceEntityIdentityV1(
            kind: .workflowRecord,
            id: input.draft.id
        )
        let request = try WorkspacePackageLifecycleQueryRequestV1(
            workspaceID: dependencies.workspaceID,
            generationID: dependencies.generationID,
            operation: .finalize,
            identities: [assetIdentity, recordIdentity]
        )
        let query = try dependencies.queryClient.query(request)
        guard query.existingIdentities == request.identities,
              query.packageBindings == [WorkspacePackageBindingV1(
                assetID: input.asset.id,
                packageID: profile.release.packageID,
                packageSchemaVersion: profile.release.schemaVersion,
                packageContentVersion: profile.release.contentVersion
              )] else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }

        let outcome = try await service.finalize(input)
        let durableReceipt = try dependencies.writer.durableReceipt(
            mutationID: binding.mutationID
        )
        guard durableReceipt?.identity == binding.durableReceiptIdentity else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        return PackFinalizationAdapterOutcomeV1(
            finalization: outcome,
            binding: binding,
            durableReceiptIdentity: durableReceipt?.identity,
            zeroFeatureWriteClosureClaimed: false
        )
    }
}

import Foundation
import SwiftData

@MainActor
struct ProductionSignWorkflow {
    let lifecycle: WorkspacePackageLifecycleDependenciesV1
    let firstSign: FirstSignCoordinator
    let checkRunner: CheckRunnerCoordinator
    let reportDelivery: ReportDeliveryCoordinator
    let reportHistory: ReportHistoryCoordinator
    let work: WorkCoordinator
    let deletion: WholeSignDeletionService
}

@MainActor
final class ProductionCompositionRoot {
    /// S10.6 owns shipping UI composition. C16 provides only gated overloads;
    /// legacy UI callers remain deliberately unaccepted until reconciliation.
    static let c16AccessGateProductionAdoptionComplete = false

    /// This composition is intentionally limited to the pre-auth metadata
    /// purge. It does not unlock, open a workspace, or adopt any S10 UI route.
    func makePreAuthenticationIngressStore(
        ownedStorageLedger: OwnedStorageLedgerV1
    ) -> any ProtectedIngressStoreV1 {
        let effects = OwnedStorageLedgerProtectedIngressEffectV1(ledger: ownedStorageLedger)
        return InjectedProtectedIngressStoreV1(effects: effects)
    }

    private let modelContext: ModelContext
    private let diagnosticsStore: DiagnosticsStore
    private let lifecycle: WorkspacePackageLifecycleDependenciesV1
    private let requirementEvaluatorRegistry: RequirementEvaluatorRegistryV1?

    init(
        storeSession: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1,
        requirementEvaluatorRegistry: RequirementEvaluatorRegistryV1? = nil
    ) throws {
        let dependencies = try storeSession.packageLifecycleDependencies(
            profileRegistry: profileRegistry
        )
        self.modelContext = storeSession.modelContext
        self.diagnosticsStore = diagnosticsStore
        self.requirementEvaluatorRegistry = requirementEvaluatorRegistry
        lifecycle = dependencies
    }

    func makeSignWorkflow(
        signPack: SignPack,
        requirementEvaluatorRegistry registryOverride: RequirementEvaluatorRegistryV1? = nil,
        accessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil
    ) throws -> ProductionSignWorkflow {
        let release = try PackageReleaseIdentityV1(package: signPack)
        let profile = try lifecycle.profileRegistry.resolve(release)
        guard profile.package == signPack, profile.release == release else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        let storagePreflight = StoragePreflightService()
        let checkRunner = try CheckRunnerCoordinator(
            modelContext: modelContext,
            packageLifecycleDependencies: lifecycle,
            packageLifecycleProfile: profile,
            diagnosticsStore: diagnosticsStore,
            storagePreflight: storagePreflight,
            requirementEvaluatorRegistry: registryOverride ?? requirementEvaluatorRegistry,
            draftAccessState: accessState
        )
        checkRunner.configureCapture(generationRootURL: lifecycle.generationRootURL)

        let reportDelivery = try ReportDeliveryCoordinator(
            modelContext: modelContext,
            lifecycleDependencies: lifecycle,
            lifecycleProfile: profile,
            diagnosticsStore: diagnosticsStore
        )
        let reportHistory = ReportHistoryCoordinator(
            modelContext: modelContext,
            deliveryCoordinator: reportDelivery
        )
        let work = try WorkCoordinator(
            modelContext: modelContext,
            signPack: signPack,
            generationRootURL: lifecycle.generationRootURL,
            checkRunnerCoordinator: checkRunner,
            storagePreflight: storagePreflight
        )
        let deletion = WholeSignDeletionService(
            modelContext: modelContext,
            lifecycleDependencies: lifecycle
        )
        let firstSign = try FirstSignCoordinator(
            modelContext: modelContext,
            diagnosticsStore: diagnosticsStore,
            packageLifecycleDependencies: lifecycle,
            packageLifecycleProfile: profile,
            accessState: accessState
        )
        return ProductionSignWorkflow(
            lifecycle: lifecycle,
            firstSign: firstSign,
            checkRunner: checkRunner,
            reportDelivery: reportDelivery,
            reportHistory: reportHistory,
            work: work,
            deletion: deletion
        )
    }

    /// Composition may create content-facing coordinators only after the
    /// caller has obtained a foreground app-access permit.
    func makeSignWorkflow(
        signPack: SignPack,
        requirementEvaluatorRegistry registryOverride: RequirementEvaluatorRegistryV1? = nil,
        accessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil,
        accessGate: any AppAccessGatePortV1
    ) async throws -> ProductionSignWorkflow {
        guard Self.c16AccessGateProductionAdoptionComplete
                == WorkspaceExperienceAppAccessAdoptionBoundaryV1.productionCallerAdoptionComplete else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        _ = try await accessGate.requireContentAccess(for: .render)
        return try makeSignWorkflow(
            signPack: signPack,
            requirementEvaluatorRegistry: registryOverride,
            accessState: accessState
        )
    }

}

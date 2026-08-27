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
    private let modelContext: ModelContext
    private let diagnosticsStore: DiagnosticsStore
    private let lifecycle: WorkspacePackageLifecycleDependenciesV1

    init(
        storeSession: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1
    ) throws {
        let dependencies = try storeSession.packageLifecycleDependencies(
            profileRegistry: profileRegistry
        )
        self.modelContext = storeSession.modelContext
        self.diagnosticsStore = diagnosticsStore
        lifecycle = dependencies
    }

    func makeSignWorkflow(
        signPack: SignPack,
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

}

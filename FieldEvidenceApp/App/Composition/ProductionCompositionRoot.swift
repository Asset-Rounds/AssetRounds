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

/// Production C30 adoption of the existing C45 label pipeline. The lifecycle
/// owns deterministic projection, resumable publication, canonical acceptance,
/// and exact accepted-byte export; it does not claim printing, sharing, or a
/// successful physical scan.
@MainActor
struct ProductionAssetLabelWorkflow {
    let lifecycle: AssetLabelLifecycleAdapterV1
    let generationEpoch: GenerationEpochV1
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
    private var assetLabelWorkflow: ProductionAssetLabelWorkflow?

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

    /// Composes the existing single-writer AssetLabel lifecycle over the
    /// current workspace generation. The generation publication adapter is
    /// supplied by the incumbent generation owner so this root cannot invent
    /// stale-writer authority. AppAccess is checked before any existing cached
    /// workflow can be returned or any content/render dependency is created.
    func makeAssetLabelWorkflow(
        generationEpoch: GenerationEpochV1,
        generationPublicationAdapter: GenerationLocalJobPublicationAdapterV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> ProductionAssetLabelWorkflow {
        guard Self.c16AccessGateProductionAdoptionComplete
                == WorkspaceExperienceAppAccessAdoptionBoundaryV1.productionCallerAdoptionComplete else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        _ = try await accessGate.requireContentAccess(for: .render)
        try generationEpoch.validate()
        guard generationEpoch.generationID == lifecycle.generationID else {
            throw GenerationLocalJobPublicationFailureV1.staleGeneration
        }
        if let existing = assetLabelWorkflow {
            guard existing.generationEpoch == generationEpoch else {
                throw GenerationLocalJobPublicationFailureV1.staleGeneration
            }
            return existing
        }

        let generationRootURL = lifecycle.generationRootURL
        let applicationSupportURL = generationRootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        let stagingRootURL = generationRootURL
            .appendingPathComponent("operational", isDirectory: true)
            .appendingPathComponent("local-job-staging-v1", isDirectory: true)
        let store = try LocalJobStoreV1(
            applicationSupportURL: applicationSupportURL,
            clock: lifecycle.clock,
            idSource: lifecycle.idSource
        )
        let generationFactory = StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        )
        let runner = try ResumableLocalJobRunnerV1(
            store: store,
            stagingRootURL: stagingRootURL,
            generationLeaseRegistry: try generationFactory.makeGenerationLeaseRegistry(),
            generationPublicationAdapter: generationPublicationAdapter,
            maximumConcurrency: 1
        )
        let contentStore = EvidenceBundleStore(generationRootURL: generationRootURL)
        let artifacts = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: stagingRootURL,
            contentStore: contentStore
        )
        let context = modelContext
        let workspaceID = lifecycle.workspaceID
        let authority = AssetLabelAuthoritativePlanAdapterV1 { plan in
            try Self.validateCurrentAssetLabelPlan(
                plan,
                workspaceID: workspaceID,
                modelContext: context
            )
        }
        let labelLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: lifecycle.writer,
            query: AcceptedLabelGenerationSnapshotQueryV1(modelContext: modelContext),
            jobs: runner,
            artifacts: artifacts
        )
        let workflow = ProductionAssetLabelWorkflow(
            lifecycle: labelLifecycle,
            generationEpoch: generationEpoch
        )
        assetLabelWorkflow = workflow
        return workflow
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

    private static func validateCurrentAssetLabelPlan(
        _ plan: AssetLabelGenerationPlanV1,
        workspaceID: WorkspaceID,
        modelContext: ModelContext
    ) throws {
        try plan.validate()
        guard plan.workspaceID == workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        for item in plan.items {
            let assetID = item.assetID
            let assets = try modelContext.fetch(FetchDescriptor<Asset>(
                predicate: #Predicate { $0.id == assetID }
            ))
            let assetIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
            let assetRevisionKey = assetIdentity.stableKey
            let assetRevisions = try modelContext.fetch(
                FetchDescriptor<EntityMutationRevisionRow>(
                    predicate: #Predicate { $0.stableIdentity == assetRevisionKey }
                )
            )
            guard assets.count == 1,
                  assetRevisions.count == 1,
                  let storedAssetRevision = assetRevisions.first?.revision,
                  storedAssetRevision > 0,
                  UInt64(storedAssetRevision) == item.assetRevision else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }

            let locatorID = item.locator.locatorID
            let locatorRows = try modelContext.fetch(FetchDescriptor<AssetLocatorRow>(
                predicate: #Predicate { $0.locatorID == locatorID }
            ))
            let receiptID = item.bindingReceiptID
            let receiptRows = try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>(
                predicate: #Predicate { $0.receiptID == receiptID }
            ))
            guard locatorRows.count == 1,
                  let locator = try locatorRows.first?.value(),
                  locator.workspaceID == workspaceID,
                  locator.assetID == item.assetID,
                  try locator.reference == item.locator,
                  locator.state == item.locatorState,
                  receiptRows.count == 1,
                  let receipt = try receiptRows.first?.value(),
                  receipt.workspaceID == workspaceID,
                  receipt.after == item.locator,
                  receipt.revision == item.bindingReceiptRevision,
                  receipt.receiptSHA256 == item.bindingReceiptSHA256 else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
    }

}

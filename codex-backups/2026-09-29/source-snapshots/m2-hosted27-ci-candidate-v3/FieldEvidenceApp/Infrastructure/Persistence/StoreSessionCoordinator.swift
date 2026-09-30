import Foundation
import Darwin
import SwiftData
import SwiftUI

/// Keeps a failed lease release reachable when construction could not return
/// a coordinator. The owner must retry release before opening another writer.
@MainActor
final class StoreSessionWriterCleanupFailureV1: Error {
    let operationFailure: Error
    let releaseFailure: Error
    private let leaseHandle: GenerationLeaseHandleV1

    init(leaseHandle: GenerationLeaseHandleV1, operationFailure: Error, releaseFailure: Error) {
        self.leaseHandle = leaseHandle
        self.operationFailure = operationFailure
        self.releaseFailure = releaseFailure
    }

    func retryRelease() throws {
        try leaseHandle.close()
    }
}

@MainActor
final class StoreSessionCoordinator: ObservableObject {
    @Published private(set) var uiGenerationToken: UInt64 = 0

    private var session: StoreGenerationSession
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileAuthority: any ApplicationFileAuthorityV1
    private var generationFactory: StoreGenerationFactory
    let lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1
    private var writerLeaseHandle: GenerationLeaseHandleV1
    private var writerFence: StaleWriterFenceV1
    private(set) var workspaceWriter: WorkspaceWriterV1
    private(set) var searchIndexStore: LocalSearchIndexStoreV1
    private(set) var searchServices: ProductionSearchServicesV1

    private final class ErasePreparationInstallation {
        weak var operation: EraseRouterOperationV1?
        let allocation: GenerationWriterAllocationAttemptV1
        init(operation: EraseRouterOperationV1, allocation: GenerationWriterAllocationAttemptV1) {
            self.operation = operation
            self.allocation = allocation
        }
    }
    private var erasePreparationInstallation: ErasePreparationInstallation?
    // The original Router's inventory capture closes new Whole Sign work even
    // before the Erase operation is fully bound. An interrupted capture stays
    // closed; only authenticated republication of its exact unadmitted owner
    // can reopen this service's producer admission.
    private var wholeSignDeletionSuspendedForErase = false
    private var wholeSignDeletionCaptureOperationID: UUID?
#if DEBUG
    private var erasePreparationSourceCapturedForTesting = false
#endif

    private enum TemporalAdmission: Equatable {
        case open
        case draining(UUID)
        case exclusive(UUID)
        case maintenance(UUID)
    }
    private static var temporalSessionOwners: [ObjectIdentifier: WeakTemporalSessionOwnerV1] = [:]
    private var temporalAdmission: TemporalAdmission = .open
    private var temporalAdmissionFailureID: UUID?
    private var temporalExclusiveOwner: StoreTemporalNormalizationExclusionV1?
    private var temporalProducerIDs: Set<UUID> = []
    private var temporalDrainWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

#if DEBUG
    /// Test convenience only. Production must use the throwing
    /// `init(validatingSession:)`: a damaged store (for example a corrupt
    /// receipt history) fails closed to maintenance instead of trapping.
    convenience init(
        session: StoreGenerationSession,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1(),
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1? = nil
    ) {
        let resolvedFactory: StoreGenerationFactory
        let binding: WriterBinding
        let searchIndexStore: LocalSearchIndexStoreV1
        let searchServices: ProductionSearchServicesV1
        let resolvedLifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1
        do {
            resolvedFactory = try session.validatedOpeningFactoryForWriter()
            resolvedLifecycleProfileRegistry = try lifecycleProfileRegistry
                ?? WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
            searchIndexStore = try LocalSearchIndexStoreV1(
                applicationSupportURL: Self.applicationSupportURL(for: session)
            )
            binding = try Self.makeWriter(
                session: session,
                clock: clock,
                idSource: idSource,
                fileAuthority: fileAuthority,
                generationFactory: resolvedFactory,
                lifecycleProfileRegistry: resolvedLifecycleProfileRegistry
            )
            do {
                searchServices = try Self.makeSearchServices(
                    session: session,
                    writer: binding.writer,
                    store: searchIndexStore
                )
            } catch {
                binding.writer.invalidate()
                try Self.releaseAfterFailure(binding.leaseHandle, operationFailure: error)
                throw error
            }
        } catch {
            preconditionFailure(
                "Store generation could not install its writer lease: \(error)"
            )
        }
        self.init(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: resolvedFactory,
            lifecycleProfileRegistry: resolvedLifecycleProfileRegistry,
            binding: binding,
            searchIndexStore: searchIndexStore,
            searchServices: searchServices
        )
    }
#endif

    convenience init(
        validatingSession session: StoreGenerationSession,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1(),
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1? = nil
    ) throws {
        try self.init(validatingSession: session, clock: clock, idSource: idSource,
                      fileAuthority: fileAuthority, lifecycleProfileRegistry: lifecycleProfileRegistry,
                      mutationJournalFailureInjection: nil)
    }

    #if DEBUG
    convenience init(
        validatingSessionForTesting session: StoreGenerationSession,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1(),
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1? = nil,
        mutationJournalFailureInjection: MutationJournalFailureInjectionV1
    ) throws {
        try self.init(validatingSession: session, clock: clock, idSource: idSource,
                      fileAuthority: fileAuthority, lifecycleProfileRegistry: lifecycleProfileRegistry,
                      mutationJournalFailureInjection: mutationJournalFailureInjection)
    }
    #endif

    private convenience init(
        validatingSession session: StoreGenerationSession,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1?,
        mutationJournalFailureInjection: MutationJournalFailureInjectionV1?
    ) throws {
        let resolvedFactory = try session.validatedOpeningFactoryForWriter()
        let resolvedLifecycleProfileRegistry = try lifecycleProfileRegistry
            ?? WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        let searchIndexStore = try LocalSearchIndexStoreV1(
            applicationSupportURL: Self.applicationSupportURL(for: session)
        )
        let binding = try Self.makeWriter(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: resolvedFactory,
            lifecycleProfileRegistry: resolvedLifecycleProfileRegistry,
            mutationJournalFailureInjection: mutationJournalFailureInjection
        )
        let searchServices: ProductionSearchServicesV1
        do {
            searchServices = try Self.makeSearchServices(
                session: session,
                writer: binding.writer,
                store: searchIndexStore
            )
        } catch {
            binding.writer.invalidate()
            try Self.releaseAfterFailure(binding.leaseHandle, operationFailure: error)
            throw error
        }
        self.init(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: resolvedFactory,
            lifecycleProfileRegistry: resolvedLifecycleProfileRegistry,
            binding: binding,
            searchIndexStore: searchIndexStore,
            searchServices: searchServices
        )
    }

    private init(
        session: StoreGenerationSession,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        generationFactory: StoreGenerationFactory,
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1,
        binding: WriterBinding,
        searchIndexStore: LocalSearchIndexStoreV1,
        searchServices: ProductionSearchServicesV1
    ) {
        self.session = session
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.generationFactory = generationFactory
        self.lifecycleProfileRegistry = lifecycleProfileRegistry
        self.writerLeaseHandle = binding.leaseHandle
        self.writerFence = binding.fence
        self.workspaceWriter = binding.writer
        self.searchIndexStore = searchIndexStore
        self.searchServices = searchServices
        registerTemporalOwner()
    }

    var modelContext: ModelContext {
        session.modelContext
    }

    var generationID: UUID {
        session.generationID
    }

    var generationRootURL: URL {
        session.generationRootURL
    }

    var workspaceID: WorkspaceID {
        session.workspaceID
    }

    var replicaID: ReplicaID {
        session.replicaID
    }

    var workspaceIdentity: WorkspaceReplicaIdentityV1 {
        session.workspaceIdentity
    }

    var workspaceQueryClient: any WorkspaceQueryClientV1 {
        workspaceWriter
    }

    /// Construction reads no private rows. Every snapshot obtains a fresh
    /// concrete access epoch and rejects this provider after session activation.
    func makeMyDaySourceProvider(accessGate: AppAccessGateV1) -> ProductionMyDaySourceProviderV1 {
        ProductionMyDaySourceProviderV1(session: self, accessGate: accessGate)
    }

    /// The planning executor shares this session's existing clock, ID source
    /// and writer identity. It acquires no context or access at construction.
    func makeMyDayPlanningCommitService(
        sourceProvider: ProductionMyDaySourceProviderV1
    ) -> ProductionMyDayPlanningCommitServiceV1 {
        ProductionMyDayPlanningCommitServiceV1(session: self, sourceProvider: sourceProvider,
            clock: clock, idSource: idSource)
    }

    /// Assessed round reads use this session's clock and exact generation root.
    /// The caller supplies the existing ledger so active reservations are not
    /// lost in a separate, empty admission ledger. Construction grants no access.
    func makeMyDaySourceProvider(
        accessGate: AppAccessGateV1,
        ownedStorageLedger: OwnedStorageLedgerV1
    ) -> ProductionMyDaySourceProviderV1 {
        let readiness = ProductionOfflineReadinessAuthorityV1(
            session: self,
            accessGate: accessGate,
            clock: clock,
            ownedStorageLedger: ownedStorageLedger,
            expectedApplicationSupportURL: Self.applicationSupportURL(for: session)
        )
        return ProductionMyDaySourceProviderV1(
            session: self,
            accessGate: accessGate,
            readinessAuthority: readiness
        )
    }

    /// Uses the app publication's single ledger for a derived round-readiness
    /// observation. Construction neither reads canonical rows nor reserves
    /// storage, and the authority retains no writer capability.
    func makeRoundReadinessAuthority(
        accessGate: AppAccessGateV1,
        ownedStorageLedger: OwnedStorageLedgerV1
    ) -> ProductionOfflineReadinessAuthorityV1 {
        ProductionOfflineReadinessAuthorityV1(
            session: self,
            accessGate: accessGate,
            clock: clock,
            ownedStorageLedger: ownedStorageLedger,
            expectedApplicationSupportURL: Self.applicationSupportURL(for: session)
        )
    }

    /// Constructs the one app-lifetime storage observer only when an
    /// authorized publication has supplied this exact active store.
    func makeRoundReadinessLedger() throws -> OwnedStorageLedgerV1 {
        try OwnedStorageLedgerV1(
            applicationSupportURL: Self.applicationSupportURL(for: session)
        )
    }

    /// C07's manual draft-ordering capability shares this exact active
    /// session, writer, clock and ID source. Construction grants no generic
    /// writer access and performs no canonical read or write.
    func makeRoundDraftOrderingService(accessGate: AppAccessGateV1) throws -> ProductionRoundDraftOrderingServiceV1 {
        try ProductionRoundDraftOrderingServiceV1(session: self, accessGate: accessGate,
            clock: clock, idSource: idSource)
    }

    /// C07's explicit start/pause/resume capability shares the active
    /// session's writer, clock and ID source; construction reads no rows.
    func makeRoundSessionTransitionService(accessGate: AppAccessGateV1) throws -> ProductionRoundSessionTransitionServiceV1 {
        try ProductionRoundSessionTransitionServiceV1(session: self, accessGate: accessGate,
            clock: clock, idSource: idSource)
    }

    func makeRepetitiveCaptureProgressService(
        transitions: ProductionRoundSessionTransitionServiceV1
    ) throws -> ProductionRepetitiveCaptureProgressServiceV2 {
        try .init(session: self, transitions: transitions, clock: clock, idSource: idSource)
    }

    /// Opening a live item retains the published Round's progress owner. This
    /// read-only factory does not construct staging or create a draft.
    func makeLiveCheckRunnerItemService(source: CheckRunnerRoundItemSourceV1,
        progress: ProductionRepetitiveCaptureProgressServiceV2) throws -> ProductionCheckRunnerItemDraftServiceV1 {
        try source.validate()
        guard source.roundAtEntry.workspaceID == workspaceID else { throw FieldDraftFailureV1.wrongWorkspace }
        try progress.validateCheckRunnerOwner(writer: workspaceWriter, modelContext: modelContext)
        let lifecycle = try packageLifecycleDependencies()
        let profile = try lifecycle.profileRegistry.resolve(source.legacyPackageIdentity)
        let binding = try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
            from: profile.package, stage: source.requestedEntry.stage)
        let sources = try ProductionOfflineReadinessSourceClosureV1(context: modelContext,
                                                                   workspaceID: workspaceID)
        guard let published = try sources.package(for: source.packageRelease),
              published.packageReleaseID == binding.packageReleaseID,
              published.packageID == binding.packageID,
              published.packageContentVersion == binding.packageContentVersion,
              published.packageSHA256 == binding.packageSHA256,
              published.workflowSHA256 == binding.workflowSHA256,
              try RoundPackageReleaseReferenceV1(published) == source.packageRelease else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let coordinator = try CheckRunnerCoordinator(modelContext: modelContext,
            packageLifecycleDependencies: lifecycle, packageLifecycleProfile: profile)
        coordinator.configureCapture(generationRootURL: generationRootURL)
        return try ProductionCheckRunnerItemDraftServiceV1(session: self, progress: progress,
            coordinator: coordinator, publishedRelease: published, clock: clock, ids: idSource,
            serviceContext: .live(source))
    }

    private struct LiveCheckRunnerItemBindingV1 {
        let assetID: UUID
        let lifecycle: WorkspacePackageLifecycleDependenciesV1
        let profile: WorkspacePackageLifecycleProfileV1
        let requestedEntry: CheckRunnerRequestedEntryV1
        let published: InspectionPackageReleaseV1
    }

    /// Read only. The item's package requirement fixes the stage; a recheck
    /// needs the asset's single recheck-due Issue. Ambiguity fails closed.
    private func liveCheckRunnerItemBinding(round: RoundSessionV1, itemID: UUID,
        progress: ProductionRepetitiveCaptureProgressServiceV2) throws -> LiveCheckRunnerItemBindingV1 {
        try progress.validateCheckRunnerOwner(writer: workspaceWriter, modelContext: modelContext)
        guard round.workspaceID == workspaceID,
              let item = round.items.first(where: { $0.itemID == itemID }) else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let assetID = item.selection.assetID
        let assets = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID }))
        guard assets.count == 1, let asset = assets.first else { throw FieldDraftFailureV1.missingContent }
        let lifecycle = try packageLifecycleDependencies()
        let profile = try lifecycle.profileRegistry.resolve(PackageReleaseIdentityV1(
            packageID: asset.packID, schemaVersion: asset.packSchemaVersion,
            contentVersion: asset.packContentVersion))
        let required = item.requirement.packageRelease
        let stages = try [WorkflowStage.check, .recheck].filter { stage in
            let binding = try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
                from: profile.package, stage: stage)
            return binding.packageReleaseID == required.packageReleaseID
                && binding.packageID == required.packageID
                && binding.packageContentVersion == required.packageContentVersion
                && binding.packageSHA256 == required.packageSHA256
                && binding.workflowSHA256 == required.workflowSHA256
        }
        guard stages.count == 1, let stage = stages.first else { throw ScanToWorkFailureV1.authorityMismatch }
        let requestedEntry: CheckRunnerRequestedEntryV1
        if stage == .recheck {
            let due = IssueStatus.recheckDue.rawValue
            let issues = try modelContext.fetch(FetchDescriptor<Issue>(predicate: #Predicate {
                $0.assetID == assetID && $0.status == due
            }))
            guard issues.count == 1, let issue = issues.first else { throw ScanToWorkFailureV1.authorityMismatch }
            requestedEntry = .recheck(issueID: issue.id)
        } else {
            requestedEntry = .check
        }
        let sources = try ProductionOfflineReadinessSourceClosureV1(context: modelContext,
                                                                   workspaceID: workspaceID)
        guard let published = try sources.package(for: required),
              try RoundPackageReleaseReferenceV1(published) == required else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return .init(assetID: assetID, lifecycle: lifecycle, profile: profile,
                     requestedEntry: requestedEntry, published: published)
    }

    /// Read only, before any launch or ENTRY write: the item must bind to one
    /// stage and its asset must have no canonical draft this Round did not begin.
    func validateLiveCheckRunnerItemEntry(round: RoundSessionV1, itemID: UUID,
        progress: ProductionRepetitiveCaptureProgressServiceV2) throws {
        let binding = try liveCheckRunnerItemBinding(round: round, itemID: itemID, progress: progress)
        let coordinator = try CheckRunnerCoordinator(modelContext: modelContext,
            packageLifecycleDependencies: binding.lifecycle, packageLifecycleProfile: binding.profile)
        guard try coordinator.existingDraft(assetID: binding.assetID) == nil else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
    }

    /// Read only: the frozen source for the Round's current ENTRY item. An
    /// existing parent for this exact source reopens through the historical
    /// ENTRY check and may own its Begin record; otherwise new-Begin admission
    /// applies unchanged. No draft, staging or Round effect.
    func captureLiveCheckRunnerItemSource(read: ProductionRepetitiveCaptureReadV2, itemID: UUID,
        progress: ProductionRepetitiveCaptureProgressServiceV2) throws -> CheckRunnerRoundItemSourceV1 {
        let binding = try liveCheckRunnerItemBinding(round: read.chain.currentRound, itemID: itemID,
                                                     progress: progress)
        let coordinator = try CheckRunnerCoordinator(modelContext: modelContext,
            packageLifecycleDependencies: binding.lifecycle, packageLifecycleProfile: binding.profile)
        let source = try CheckRunnerRoundItemSourceV1(read: read, itemID: itemID,
            publishedRelease: binding.published, signPack: binding.profile.package,
            requestedEntry: binding.requestedEntry)
        let service = try makeLiveCheckRunnerItemService(source: source, progress: progress)
        if let parent = try service.readCurrentDraft(source: source),
           let attempt = try CheckRunnerItemDraftCodecV1.validateCheckpoint(parent).field.begin.attempt {
            try coordinator.validateHistoricalCheckRunnerSource(source, read: read, progress: progress,
                publishedRelease: binding.published)
            let canonical = try coordinator.existingDraft(assetID: binding.assetID)
            guard attempt.source == source,
                  canonical == nil || canonical?.id == attempt.recordCommand.recordID else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
            return source
        }
        return try coordinator.captureFrozenBeginSource(read: read, progress: progress, itemID: itemID,
            publishedRelease: binding.published, requestedEntry: binding.requestedEntry)
    }

    /// The explicit backup operation reuses the incumbent source, publication
    /// and physical owners. This factory does not register a capture route.
    func makePhotoBackupService(parentCheckpoint: FieldDraftCheckpointV1,
                               accessGate: AppAccessGateV1,
                               staging: DraftAttachmentStagingAdapterV1) throws -> ProductionCheckRunnerItemDraftServiceV1 {
        let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(parentCheckpoint)
        guard parentCheckpoint.workspaceID == workspaceID else { throw FieldDraftFailureV1.invalidValue }
        let lifecycle = try packageLifecycleDependencies()
        let profile = try lifecycle.profileRegistry.resolve(parent.source.legacyPackageIdentity)
        let binding = try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
            from: profile.package, stage: parent.source.requestedEntry.stage)
        let sources = try ProductionOfflineReadinessSourceClosureV1(context: modelContext,
                                                                   workspaceID: workspaceID)
        guard let published = try sources.package(for: parent.source.packageRelease),
              published.packageReleaseID == binding.packageReleaseID,
              published.packageID == binding.packageID,
              published.packageContentVersion == binding.packageContentVersion,
              published.packageSHA256 == binding.packageSHA256,
              published.workflowSHA256 == binding.workflowSHA256,
              try RoundPackageReleaseReferenceV1(published) == parent.source.packageRelease else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let transitions = try makeRoundSessionTransitionService(accessGate: accessGate)
        let progress = try makeRepetitiveCaptureProgressService(transitions: transitions)
        let coordinator = try CheckRunnerCoordinator(modelContext: modelContext,
            packageLifecycleDependencies: lifecycle, packageLifecycleProfile: profile)
        coordinator.configureCapture(generationRootURL: generationRootURL)
        return try ProductionCheckRunnerItemDraftServiceV1(session: self, progress: progress,
            coordinator: coordinator, publishedRelease: published, clock: clock, ids: idSource,
            attachmentStaging: staging, serviceContext: .backup)
    }

    func dropSearchProjectionForRebuild() async throws {
        try await searchIndexStore.dropProjection(workspaceID: workspaceID.rawValue)
    }

    func rebuildSearchProjectionIfNeeded() async throws -> SearchIndexRebuildResultV1 {
        try await searchServices.rebuildCoordinator.rebuildIfNeeded()
    }

    func awaitSearchIndexLifecycle() async throws {
        // Synchronous writer/session hooks complete before their callers
        // return; this compatibility seam therefore has no pending work.
    }

    func executeAndSynchronizeSearchIndex(
        _ command: WorkspaceCommandV1
    ) async throws -> WorkspaceMutationOutcomeV1 {
        let outcome = try workspaceWriter.execute(command)
        try await awaitSearchIndexLifecycle()
        return outcome
    }

    func packageLifecycleDependencies(
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1
    ) throws -> WorkspacePackageLifecycleDependenciesV1 {
        guard profileRegistry == lifecycleProfileRegistry else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return try packageLifecycleDependencies()
    }

    func packageLifecycleDependencies() throws -> WorkspacePackageLifecycleDependenciesV1 {
        try WorkspacePackageLifecycleDependenciesV1(
            workspaceID: session.workspaceID,
            generationID: session.generationID,
            generationRootURL: session.generationRootURL,
            writer: workspaceWriter,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            profileRegistry: lifecycleProfileRegistry
        )
    }

    /// Binds live Whole Sign deletion to this published writer. The service
    /// receives the incumbent fence, never a second writer lease or registry.
    func wholeSignDeletionSharedFence(
        expectedContext: ModelContext,
        dependencies: WorkspacePackageLifecycleDependenciesV1
    ) throws -> StaleWriterFenceV1 {
        guard temporalPublicationIsAdmitted,
              !wholeSignDeletionSuspendedForErase,
              expectedContext === session.modelContext,
              dependencies.writer === workspaceWriter,
              dependencies.workspaceID == session.workspaceID,
              dependencies.generationID == session.generationID,
              dependencies.generationRootURL.standardizedFileURL
                == session.generationRootURL.standardizedFileURL,
              writerFence.writerLeaseToken == writerLeaseHandle.token,
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch.generationID == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: writerFence.retainedTemporalRegistry)
        try writerFence.validateCurrent()
        let revision = try workspaceWriter.currentRevision()
        guard revision.workspaceID == session.workspaceID,
              revision.generationID == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        return writerFence
    }

    /// The existing writer's G/fence covers only the synchronous journal
    /// checkpoint and SwiftData save. The service's admitted producer scope
    /// owns the surrounding async deletion and cleanup lifetime.
    func withWholeSignDeletionCommit<Value>(
        expectedContext: ModelContext,
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        expectedFence: StaleWriterFenceV1,
        _ operation: () throws -> Value
    ) throws -> Value {
        guard let producer = TemporalProducerTaskContextV1.operation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try producer.validate(for: self)
        guard try wholeSignDeletionSharedFence(
            expectedContext: expectedContext,
            dependencies: dependencies) === expectedFence else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        return try writerFence.withAuthorizedCommit {
            // The full activity validation above takes Registry G. While G
            // is held here, recheck only the same in-memory live scope.
            guard producer.isLiveScope(for: self),
                  temporalProducerIDs.contains(producer.id),
                  temporalPublicationIsAdmitted,
                  !wholeSignDeletionSuspendedForErase,
                  expectedContext === session.modelContext,
                  dependencies.writer === workspaceWriter,
                  dependencies.workspaceID == session.workspaceID,
                  dependencies.generationID == session.generationID,
                  dependencies.generationRootURL.standardizedFileURL
                    == session.generationRootURL.standardizedFileURL,
                  writerFence === expectedFence,
                  writerFence.writerLeaseToken == writerLeaseHandle.token else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            return try operation()
        }
    }

    /// Explicit owner teardown, including unpublished startup failure. A
    /// failed close remains retryable; invalidation never restores a writer.
    func invalidateAndReleaseWriter() throws {
        // Revocation is not completion of an awaited byte write. Keep the
        // physical writer lease until every real producer has settled.
        try requireTemporalOwnerIdle()
        workspaceWriter.invalidate()
        try writerLeaseHandle.close()
    }

    /// Reuses the journal's exact registry/fence instance. The operation is
    /// synchronous: no actor suspension or byte-copy work may hold this lock.
    var checkRunnerPhotoApplicationSupportURL: URL {
        Self.applicationSupportURL(for: session)
    }

    func withCheckRunnerPhotoPublication<Value>(
        expectedWriter: WorkspaceWriterV1, applicationSupportURL: URL,
        _ operation: () throws -> Value
    ) throws -> Value {
        guard temporalPublicationIsAdmitted,
              expectedWriter === workspaceWriter,
              applicationSupportURL.standardizedFileURL
                == generationFactory.restoreApplicationSupportURL.standardizedFileURL else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        return try writerFence.withAuthorizedCommit {
            guard temporalPublicationIsAdmitted,
                  expectedWriter === workspaceWriter,
                  !session.modelContext.hasChanges,
                  try workspaceWriter.currentRevision().generationID == session.generationID else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            return try operation()
        }
    }

    /// Resolves the current pointer's workspace identity through this
    /// coordinator's retained lease registry, so it is safe inside
    /// `withCheckRunnerPhotoPublication`. A fresh `StoreGenerationFactory`
    /// there opens a second mutation-lock descriptor whose blocking flock
    /// waits forever on the lock this same thread already holds.
    func currentWorkspaceIdentityWithinPublication(
        applicationSupportURL: URL, expectedGenerationID: UUID
    ) throws -> WorkspaceReplicaIdentityV1 {
        guard applicationSupportURL.standardizedFileURL
                == generationFactory.restoreApplicationSupportURL.standardizedFileURL else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        return try generationFactory.currentWorkspaceIdentity(
            expectedGenerationID: expectedGenerationID,
            authority: generationFactory.makeRestoreGenerationAuthority()
        )
    }

#if DEBUG
    /// Test convenience only; production activation uses `activateValidating`.
    func activate(session: StoreGenerationSession) {
        do {
            try activateValidating(session: session)
        } catch {
            preconditionFailure(
                "Store generation could not replace its writer lease: \(error)"
            )
        }
    }
#endif

    /// Retains only the inventory's weak observations and exact reader wrapper
    /// from this actual session; metadata cannot stand in for this capture.
    func captureEraseSession(in inventory: EraseReaderRetirementInventoryV1) throws {
        try requireTemporalOwnerIdle()
        guard !wholeSignDeletionSuspendedForErase else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: writerFence.retainedTemporalRegistry)
        try inventory.capture(session)
        wholeSignDeletionSuspendedForErase = true
    }

    /// The original Router's source session and this writer must have been
    /// opened through one retained provider before Erase moves either owner.
    /// Returning the actual session lets Router compare its maintenance input
    /// by reference; path or token-owner equality is insufficient.
    func requireOriginalEraseOpeningAuthority(
        factory expectedFactory: StoreGenerationFactory
    ) throws -> StoreGenerationSession {
        let opening = try session.validatedOpeningFactoryForWriter()
        guard generationFactory.sharesRegistryProvider(with: expectedFactory),
              opening.sharesRegistryProvider(with: expectedFactory) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let registry = try expectedFactory.makeGenerationLeaseRegistry()
        guard let epoch = session.generationEpoch,
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch == epoch,
              writerFence.retainedTemporalRegistry === registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writerLeaseHandle.requireExactRegistry(registry)
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: registry)
        let writerRevision = try workspaceWriter.currentRevision()
        guard writerRevision.generationID == session.generationID,
              writerRevision.workspaceID == session.workspaceID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return session
    }

#if DEBUG
    /// The V9_49 fixture seeds through the exact Router-published writer.
    /// This returns that writer's existing session; it allocates no lease or
    /// second container and cannot be used after admission/retirement begins.
    func sourceSessionForV949EraseFixture(
        router: StartupRouter
    ) throws -> StoreGenerationSession {
        guard case let .ready(published, _, _) = router.route,
              published === self,
              session.generationRootURL.standardizedFileURL
                == generationFactory.installedGenerationURL(
                    id: session.generationID).standardizedFileURL,
              let epoch = session.generationEpoch,
              epoch == writerLeaseHandle.token.epoch,
              writerLeaseHandle.token.role == .writer,
              try workspaceWriter.currentRevision().generationID
                == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireTemporalOwnerIdle()
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: writerFence.retainedTemporalRegistry)
        return session
    }
#endif

    /// Binds the unadmitted observer to this same original writer's retained
    /// registry. A nil Erase subject is intentional here: no Erase authority
    /// was issued, and no retirement binding may be fabricated for this path.
    func originalWriterSupportIdentityForUnadmittedErase(
        expectedWriter: WorkspaceWriterV1
    ) throws -> StoreApplicationSupportIdentity {
        let registry = writerFence.retainedTemporalRegistry
        guard expectedWriter === workspaceWriter,
              session.generationID == generationID,
              !session.modelContext.hasChanges,
              let epoch = session.generationEpoch,
              epoch == writerLeaseHandle.token.epoch,
              writerLeaseHandle.token.role == .writer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: registry)
        return try registry.originalSupportIdentityForUnadmittedErase()
    }

    /// Creates C05's production publication authority from this actual
    /// writer handle and its retained registry. No caller-supplied closure
    /// can claim the epoch or substitute another registry. The adapter's
    /// synchronous effect/readback executes under the registry's G lock.
    func makeOriginalC05JobBinding(
        expectedWriter: WorkspaceWriterV1,
        expectedEpoch: GenerationEpochV1
    ) throws -> (
        registry: GenerationLeaseRegistryV1,
        publication: GenerationLocalJobPublicationAdapterV1
    ) {
        try requireTemporalOwnerIdle()
        let registry = writerFence.retainedTemporalRegistry
        guard expectedWriter === workspaceWriter,
              session.generationEpoch == expectedEpoch,
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch == expectedEpoch else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: registry)
        let publication = try registry.makeBoundLocalJobPublicationAdapter(
            writerHandle: writerLeaseHandle,
            expectedEpoch: expectedEpoch)
        return (registry, publication)
    }

    /// Immutable association metadata, not retirement permission. The Router
    /// authenticates its ticket/mint and the consuming EX repeats live census.
    func eraseRetirementBinding(subject: EraseAllOperationSubjectV1,
        operationID: UUID, ownerMint: UUID) throws -> EraseRetirementBindingV1 {
        let support = generationFactory.restoreApplicationSupportURL.standardizedFileURL
        let registry = writerFence.retainedTemporalRegistry
        guard subject.applicationSupportURL.standardizedFileURL == support,
              subject.newGenerationID == session.generationID,
              let epoch = session.generationEpoch,
              epoch == writerLeaseHandle.token.epoch,
              writerLeaseHandle.token.role == .writer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(mutationRegistry: registry)
        var supportFacts = stat(), operationsFacts = stat()
        guard Darwin.lstat(support.path, &supportFacts) == 0,
              supportFacts.st_mode & S_IFMT == S_IFDIR,
              Int64(supportFacts.st_dev) == subject.applicationSupportDevice,
              UInt64(supportFacts.st_ino) == subject.applicationSupportInode,
              Darwin.lstat(support.appendingPathComponent("FieldEvidenceOperations").path,
                  &operationsFacts) == 0,
              operationsFacts.st_mode & S_IFMT == S_IFDIR else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let identity = StreamingArchiveRootIdentityV1(device: UInt64(operationsFacts.st_dev),
            inode: UInt64(operationsFacts.st_ino))
        try registry.requireTemporalEraseNamespace(identity)
        return EraseRetirementBindingV1(subject: subject, operationID: operationID,
            ownerMint: ownerMint, registryIdentity: identity, generationEpoch: epoch,
            workspaceIdentity: session.workspaceIdentity)
    }

    /// Captures the real original writer before any preparation reader is opened.
    func captureErasePreparationSource(operation: EraseRouterOperationV1) throws {
        try requireTemporalOwnerIdle()
        guard wholeSignDeletionSuspendedForErase,
              wholeSignDeletionCaptureOperationID == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        wholeSignDeletionCaptureOperationID = try operation.retainPreparationSourceWriter(
            writerLeaseHandle, coordinator: self)
#if DEBUG
        erasePreparationSourceCapturedForTesting = true
#endif
    }

    /// The Router calls this only while publishing the exact retained writer
    /// after a genuine unadmitted-Erase return and fresh access validation.
    /// An issued, failed or ambiguous Erase never receives this transition.
    func resumeWholeSignDeletionAfterAuthenticatedEraseReturn(
        expectedWriter: WorkspaceWriterV1,
        captureOperationID: UUID
    ) throws {
        try requireTemporalOwnerIdle()
        guard wholeSignDeletionSuspendedForErase,
              wholeSignDeletionCaptureOperationID == captureOperationID,
              expectedWriter === workspaceWriter,
              writerFence.writerLeaseToken == writerLeaseHandle.token,
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch.generationID == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: writerFence.retainedTemporalRegistry)
        try writerFence.validateCurrent()
        let revision = try workspaceWriter.currentRevision()
        guard revision.workspaceID == session.workspaceID,
              revision.generationID == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        wholeSignDeletionCaptureOperationID = nil
        wholeSignDeletionSuspendedForErase = false
    }

    /// The acknowledgement inspects the assigned pair, never token metadata alone.
    func requireErasePreparationInstalled(_ allocation: GenerationWriterAllocationAttemptV1,
        operation: EraseRouterOperationV1) throws {
        guard let installed = erasePreparationInstallation,
              installed.operation === operation, installed.allocation === allocation,
              let handle = allocation.allocatedHandle, handle === writerLeaseHandle,
              session.generationEpoch == allocation.generationEpoch,
              allocation.matches(registry: try generationFactory.makeGenerationLeaseRegistry()) else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        try operation.requirePreparationInstalledAssociation(allocation: allocation,
            coordinator: self, writer: workspaceWriter, session: session, factory: generationFactory)
    }

#if DEBUG
    /// The label fixture borrows the exact registry and epoch already owned
    /// by this Router-published writer. It can neither open a second registry
    /// nor acquire a new writer/Erase capability.
    func originalAssetLabelFixtureJobOwnerForTesting(
        expectedWriter: WorkspaceWriterV1
    ) throws -> (registry: GenerationLeaseRegistryV1, epoch: GenerationEpochV1) {
        try requireTemporalOwnerIdle()
        let registry = writerFence.retainedTemporalRegistry
        guard !erasePreparationSourceCapturedForTesting,
              expectedWriter === workspaceWriter,
              !session.modelContext.hasChanges,
              session.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              let epoch = session.generationEpoch,
              epoch.schemaVersion == GenerationEpochV1.currentSchemaVersion,
              epoch.generationID == session.generationID,
              epoch == writerLeaseHandle.token.epoch,
              writerLeaseHandle.token.role == .writer else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: registry
        )
        return (registry, epoch)
    }

    /// A context-free snapshot of the actual source or installed target. It
    /// is captured after the service frame returned, before the coordinator
    /// aggregate is consumed. No model owner escapes in the result.
    func captureOriginalEraseShutdownControl(
        operation: EraseRouterOperationV1
    ) throws -> (registry: GenerationLeaseRegistryV1,
                 writer: GenerationLeaseHandleV1,
                 supportURL: URL,
                 installed: Bool) {
        let registry = writerFence.retainedTemporalRegistry
        let installed = erasePreparationInstallation
        try operation.requireOriginalShutdownCoordinatorAssociation(
            coordinator: self, registry: registry,
            writerHandle: writerLeaseHandle, writer: workspaceWriter,
            session: session, installedAllocation: installed?.allocation,
            installedOperation: installed?.operation,
            factory: generationFactory)
        return (registry, writerLeaseHandle,
            Self.applicationSupportURL(for: session), installed != nil)
    }

    /// Split producer drain: it only closes admission and waits for admitted
    /// catch tails. The witness-bearing EX acquisition occurs later, after the
    /// retained registry has installed its selective closing fence.
    func closeProducerAdmissionForOriginalEraseShutdown() throws -> UUID {
        guard temporalAdmission == .open, temporalExclusiveOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let id = UUID()
        temporalAdmission = .draining(id)
        return id
    }

    func awaitProducersForOriginalEraseShutdown(_ id: UUID) async throws {
        guard temporalAdmission == .draining(id) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        await awaitTemporalProducerDrain(id: id)
        guard temporalAdmission == .draining(id), temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty, temporalExclusiveOwner == nil else {
            temporalAdmission = .maintenance(id)
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireOriginalEraseShutdownProducerDrain(_ id: UUID) throws {
        guard temporalAdmission == .draining(id), temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty, temporalExclusiveOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
#endif

    /// Original-ticket target construction. The operation retains allocation
    /// failures before publication; only the actual installed pair is retried.
    func activateForErasePreparation(session: StoreGenerationSession,
        generationFactory: StoreGenerationFactory, operation: EraseRouterOperationV1) throws {
        if let installed = erasePreparationInstallation {
            guard installed.operation === operation, self.session === session,
                  installed.allocation.matches(registry: try generationFactory.makeGenerationLeaseRegistry()) else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            try requireErasePreparationInstalled(installed.allocation, operation: operation)
            try operation.recordPreparationWriterInstalled(installed.allocation, coordinator: self)
            return
        }
        try requireTemporalOwnerIdle()
        try operation.requirePreparationWriterConstruction(session: session,
            factory: generationFactory, coordinator: self)
        guard session.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              let epoch = session.generationEpoch,
              Self.applicationSupportURL(for: session)
                == generationFactory.restoreApplicationSupportURL.standardizedFileURL else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let registry = try generationFactory.makeGenerationLeaseRegistry()
        let allocation = try registry.makeWriterAllocationAttempt(epoch: epoch)
        try operation.retainPreparationWriterAllocation(allocation, registry: registry,
            session: session, coordinator: self)
        var constructedWriter: WorkspaceWriterV1?
        var installationStarted = false
        do {
            let replacementSearchIndexStore = try LocalSearchIndexStoreV1(
                applicationSupportURL: Self.applicationSupportURL(for: session))
            try LocalSearchIndexStoreV1.synchronouslyDropProjection(
                workspaceID: session.workspaceID.rawValue,
                applicationSupportURL: Self.applicationSupportURL(for: session))
            let handle = try allocation.acquireWriterForErasePreparation(operation: operation)
            let binding = try Self.constructWriter(session: session, clock: clock, idSource: idSource,
                fileAuthority: fileAuthority, generationFactory: generationFactory,
                lifecycleProfileRegistry: lifecycleProfileRegistry, generationEpoch: epoch,
                rootIdentity: rootIdentity, registry: registry, leaseHandle: handle,
                mutationJournalFailureInjection: nil)
            constructedWriter = binding.writer
            try operation.observePreparationWriter(binding.writer, allocation: allocation)
            let replacementSearchServices = try Self.makeSearchServices(session: session,
                writer: binding.writer, store: replacementSearchIndexStore)
            try operation.requirePreparationWriterConstruction(session: session,
                factory: generationFactory, coordinator: self)
            try operation.beginPreparationWriterInstallation(allocation: allocation, coordinator: self)
            installationStarted = true
            try writerLeaseHandle.close()
            workspaceWriter.invalidate()
            self.session = session
            self.generationFactory = generationFactory
            searchIndexStore = replacementSearchIndexStore
            searchServices = replacementSearchServices
            writerLeaseHandle = binding.leaseHandle
            writerFence = binding.fence
            workspaceWriter = binding.writer
            erasePreparationInstallation = ErasePreparationInstallation(operation: operation,
                allocation: allocation)
            registerTemporalOwner()
            if uiGenerationToken < .max { uiGenerationToken += 1 }
            try operation.recordPreparationWriterInstalled(allocation, coordinator: self)
        } catch {
            if !installationStarted { constructedWriter?.invalidate() }
            allocation.sealForRetirement()
            // After the consuming boundary, a thrown old close is ambiguous.
            // The original Coordinator and retained target attempt both survive;
            // no rollback receipt or second allocation is authorized here.
            throw error
        }
    }

    func activateValidating(session: StoreGenerationSession) throws {
        try activateValidating(session: session, generationFactory: generationFactory)
    }

    /// Physical Erase removes the old registry namespace. Ordinary activation
    /// must keep its factory/fences; only completed cleanup replaces that owner.
    func activateAfterErasedCleanup(session: StoreGenerationSession) throws {
        let support = Self.applicationSupportURL(for: session)
        guard support == generationFactory.restoreApplicationSupportURL.standardizedFileURL,
              session.generationID == generationID,
              session.generationRootURL.standardizedFileURL == generationRootURL.standardizedFileURL,
              try generationFactory.currentGenerationID() == session.generationID,
              BackupRestoreService.isEmptyCurrent(session.modelContext),
              try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: support) else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        // If pre-cleanup retirement failed, the handle still rejects its
        // missing registry. Never reinterpret deletion as successful close.
        try invalidateAndReleaseWriter()
        let freshFactory = StoreGenerationFactory(applicationSupportURL: support)
        try activateValidating(session: session, generationFactory: freshFactory)
    }

    private func activateValidating(
        session: StoreGenerationSession,
        generationFactory: StoreGenerationFactory
    ) throws {
        // Refuse before projection cleanup or replacement writer creation.
        try requireTemporalOwnerIdle()
        guard Self.applicationSupportURL(for: session)
                == generationFactory.restoreApplicationSupportURL.standardizedFileURL else {
            throw GenerationLeaseRegistryFailureV1.invalidPath
        }
        let replacementSearchIndexStore = try LocalSearchIndexStoreV1(
            applicationSupportURL: Self.applicationSupportURL(for: session)
        )
        try LocalSearchIndexStoreV1.synchronouslyDropProjection(
            workspaceID: session.workspaceID.rawValue,
            applicationSupportURL: Self.applicationSupportURL(for: session)
        )
        let binding = try Self.makeWriter(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: generationFactory,
            lifecycleProfileRegistry: lifecycleProfileRegistry
        )
        let replacementSearchServices: ProductionSearchServicesV1
        do {
            replacementSearchServices = try Self.makeSearchServices(
                session: session,
                writer: binding.writer,
                store: replacementSearchIndexStore
            )
            try writerLeaseHandle.close()
        } catch {
            // The old coordinator remains owned by its caller. Only the
            // uninstalled replacement is invalidated and released here.
            binding.writer.invalidate()
            try Self.releaseAfterFailure(binding.leaseHandle, operationFailure: error)
            throw error
        }
        workspaceWriter.invalidate()
        self.session = session
        self.generationFactory = generationFactory
        searchIndexStore = replacementSearchIndexStore
        searchServices = replacementSearchServices
        writerLeaseHandle = binding.leaseHandle
        writerFence = binding.fence
        workspaceWriter = binding.writer
        registerTemporalOwner()
        if uiGenerationToken < .max {
            uiGenerationToken += 1
        }
    }

    func activateValidatingAndSynchronizeSearchIndex(
        session: StoreGenerationSession
    ) async throws {
        try activateValidating(session: session)
        try await awaitSearchIndexLifecycle()
    }

    private struct WriterBinding {
        let writer: WorkspaceWriterV1
        let leaseHandle: GenerationLeaseHandleV1
        let fence: StaleWriterFenceV1
    }

    private static func releaseAfterFailure(
        _ leaseHandle: GenerationLeaseHandleV1,
        operationFailure: Error
    ) throws {
        do {
            try leaseHandle.close()
        } catch {
            throw StoreSessionWriterCleanupFailureV1(
                leaseHandle: leaseHandle,
                operationFailure: operationFailure,
                releaseFailure: error
            )
        }
    }

    private static func makeWriter(
        session: StoreGenerationSession,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        generationFactory: StoreGenerationFactory,
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1,
        mutationJournalFailureInjection: MutationJournalFailureInjectionV1? = nil
    ) throws -> WriterBinding {
        guard session.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              let generationEpoch = session.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let registry = try generationFactory.makeGenerationLeaseRegistry()
        let leaseHandle = try registry.acquireHandle(
            epoch: generationEpoch,
            role: .writer
        )
        do {
            return try constructWriter(session: session, clock: clock, idSource: idSource,
                fileAuthority: fileAuthority, generationFactory: generationFactory,
                lifecycleProfileRegistry: lifecycleProfileRegistry, generationEpoch: generationEpoch,
                rootIdentity: rootIdentity, registry: registry, leaseHandle: leaseHandle,
                mutationJournalFailureInjection: mutationJournalFailureInjection)
        } catch {
            try releaseAfterFailure(leaseHandle, operationFailure: error)
            throw error
        }
    }

    /// Fixed construction mechanism shared with the genuine fresh-adoption
    /// owner. Ordinary callers keep their incumbent acquire/release behavior.
    private static func constructWriter(session: StoreGenerationSession,
        clock: any ApplicationClock, idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1, generationFactory: StoreGenerationFactory,
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1,
        generationEpoch: GenerationEpochV1, rootIdentity: ReportPDFAnchoredFile.RootIdentity,
        registry: GenerationLeaseRegistryV1, leaseHandle: GenerationLeaseHandleV1,
        mutationJournalFailureInjection: MutationJournalFailureInjectionV1?) throws -> WriterBinding {
        let writerLeaseToken = leaseHandle.token
        let staleWriterFence = try generationFactory.makeWriterFence(
            expectedGenerationEpoch: generationEpoch,
            writerLeaseToken: writerLeaseToken,
            registry: registry
        )
        let journalStore = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            failureInjection: mutationJournalFailureInjection,
            allowStateBootstrap: false,
            staleWriterFence: staleWriterFence
        )
        try MutationReceiptRecoveryServiceV1(
            store: journalStore
        ).recoverBeforeWriterActivation()
        let revision = try WorkspaceRevisionV1(
            workspaceID: session.workspaceID,
            generationID: session.generationID,
            revision: 0,
            entityRevisions: []
        )
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: revision,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            adapter: WorkspaceWriterAdapterV1(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                expectedRootIdentity: rootIdentity,
                lifecycleProfileRegistry: lifecycleProfileRegistry
            ),
            journalStore: journalStore,
            searchIndexInvalidation: { source in
                try LocalSearchIndexStoreV1.synchronouslyInvalidateAfterCanonicalCommit(
                    source: source,
                    applicationSupportURL: generationFactory.restoreApplicationSupportURL
                )
            }
        )
        return WriterBinding(writer: writer, leaseHandle: leaseHandle, fence: staleWriterFence)
    }

    /// Actual Router fresh-adoption entry. This uses its exact Factory/provider
    /// and retained allocation inventory; it never creates another Factory or
    /// disposes a failed writer while model aliases may still exist.
    static func makeForEraseFreshAdoption(session: StoreGenerationSession,
        generationFactory: StoreGenerationFactory, adoption: EraseFreshAdoptionOwnerV1,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1(),
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1) throws -> StoreSessionCoordinator {
        try adoption.requireWriterConstruction(session: session, factory: generationFactory)
        guard session.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              let epoch = session.generationEpoch else { throw GenerationLeaseRegistryFailureV1.staleGeneration }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let registry = try generationFactory.makeGenerationLeaseRegistry()
        let searchIndexStore = try LocalSearchIndexStoreV1(applicationSupportURL: generationFactory.restoreApplicationSupportURL)
        let allocation = try registry.makeWriterAllocationAttempt(epoch: epoch)
        try adoption.retainWriterAllocation(allocation) // before token/temp publication
        var constructedWriter: WorkspaceWriterV1?
        do {
            let handle = try allocation.acquireWriter(adoption: adoption)
            let binding = try constructWriter(session: session, clock: clock, idSource: idSource,
                fileAuthority: fileAuthority, generationFactory: generationFactory,
                lifecycleProfileRegistry: lifecycleProfileRegistry, generationEpoch: epoch,
                rootIdentity: rootIdentity, registry: registry, leaseHandle: handle,
                mutationJournalFailureInjection: nil)
            constructedWriter = binding.writer
            try adoption.observeConstructedWriter(binding.writer)
            let searchServices = try makeSearchServices(session: session, writer: binding.writer, store: searchIndexStore)
            try adoption.requireWriterConstruction(session: session, factory: generationFactory)
            return StoreSessionCoordinator(session: session, clock: clock, idSource: idSource,
                fileAuthority: fileAuthority, generationFactory: generationFactory,
                lifecycleProfileRegistry: lifecycleProfileRegistry, binding: binding,
                searchIndexStore: searchIndexStore, searchServices: searchServices)
        } catch {
            constructedWriter?.invalidate()
            allocation.sealForRetirement()
            // Exact attempt stays with the Router owner; its genuine weak drain
            // must settle after this synchronous frame unwinds before release.
            throw error
        }
    }

    private static func makeSearchServices(
        session: StoreGenerationSession,
        writer: WorkspaceWriterV1,
        store: LocalSearchIndexStoreV1
    ) throws -> ProductionSearchServicesV1 {
        try ProductionSearchServicesV1(
            store: store,
            modelContext: session.modelContext,
            workspaceID: session.workspaceID.rawValue,
            generationID: session.generationID,
            revisionProvider: {
                let revision = try writer.currentRevision()
                guard revision.workspaceID == session.workspaceID,
                      revision.generationID == session.generationID else {
                    throw WorkspaceMutationFailureV1.wrongGeneration
                }
                return try SearchSourceRevisionV1(
                    workspaceID: revision.workspaceID.rawValue,
                    generationID: revision.generationID,
                    commitRevision: revision.revision
                )
            }
        )
    }

    private static func applicationSupportURL(
        for session: StoreGenerationSession
    ) -> URL {
        session.generationRootURL
            .deletingLastPathComponent() // generations
            .deletingLastPathComponent() // FieldEvidenceData
            .deletingLastPathComponent() // Application Support root
            .standardizedFileURL
    }
}


/// Task-local nesting only reuses an already admitted operation from this
/// exact owner. It never admits new work or grants a generation publication.
private enum TemporalProducerTaskContextV1 {
    @TaskLocal static var operation: StoreTemporalProducerOperationV1?
}

@MainActor
fileprivate final class StoreTemporalProducerOperationV1 {
    let id = UUID()
    let owner: StoreSessionCoordinator
    let writer: WorkspaceWriterV1
    let activity: GenerationTemporalActivityHandleV1
    private var complete = false
    private var admittedScopes: UInt64 = 1

    init(owner: StoreSessionCoordinator, writer: WorkspaceWriterV1,
         activity: GenerationTemporalActivityHandleV1) {
        self.owner = owner; self.writer = writer; self.activity = activity
    }

    func isLiveScope(for expectedOwner: StoreSessionCoordinator) -> Bool {
        !complete && admittedScopes > 0 && owner === expectedOwner
            && writer === expectedOwner.workspaceWriter
    }

    func validate(for expectedOwner: StoreSessionCoordinator) throws {
        guard !complete, owner === expectedOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try owner.validateTemporalProducer(self)
    }

    func retainScope(for expectedOwner: StoreSessionCoordinator) throws {
        try validate(for: expectedOwner)
        let (next, overflow) = admittedScopes.addingReportingOverflow(1)
        guard !overflow else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        admittedScopes = next
    }

    func finish() {
        guard !complete, admittedScopes > 0 else { return }
        admittedScopes -= 1
        guard admittedScopes == 0 else { return }
        complete = true
        // The enclosing awaited operation and its error tail have returned.
        // Never call this from a cancellation handler.
        activity.close()
        owner.finishTemporalProducer(self)
    }
}

/// Retained activity for a real producer's detached work or prepared object.
/// It is lifetime/exclusion only, never content access or publication authority.
/// Construction requires the task-local operation admitted by this Coordinator.
final class StoreTemporalProducerResourceV1: @unchecked Sendable {
    let generationID: UUID
    let generationRootURL: URL
    let applicationSupportURL: URL
    private let operation: StoreTemporalProducerOperationV1
    private let activity: GenerationTemporalActivityHandleV1
    private let lock = NSLock()
    private var closed = false

    @MainActor
    fileprivate init(operation: StoreTemporalProducerOperationV1) throws {
        try operation.retainScope(for: operation.owner)
        self.operation = operation
        activity = operation.activity
        generationID = operation.owner.generationID
        generationRootURL = operation.owner.generationRootURL
        applicationSupportURL = operation.owner.checkRunnerPhotoApplicationSupportURL
    }

    func requireActive(forGenerationRoot root: URL) throws {
        try lock.withLock {
            guard !closed, root.standardizedFileURL == generationRootURL.standardizedFileURL else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try activity.requireLiveProducerResource()
        }
    }

    func requireApplicationSupport(_ root: URL) throws {
        try lock.withLock {
            guard !closed, root.standardizedFileURL == applicationSupportURL.standardizedFileURL else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try activity.requireLiveProducerResource()
        }
    }

    /// Continuation of this exact retained operation, including its genuine
    /// terminal work while root admission is draining. This cannot admit an
    /// unrelated operation or another Coordinator after closure begins.
    @MainActor
    func withRetainedProducer<Value: Sendable>(for owner: StoreSessionCoordinator,
        _ body: @MainActor () async throws -> Value) async throws -> Value {
        try lock.withLock {
            guard !closed else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try activity.requireLiveProducerResource()
        }
        try operation.retainScope(for: owner)
        defer { operation.finish() }
        return try await TemporalProducerTaskContextV1.$operation.withValue(operation) {
            try await body()
        }
    }

    /// Call only after the actual worker and its error tail have returned.
    /// Cancellation handlers must request cancellation, never close this owner.
    @MainActor
    func close() {
        let shouldFinish = lock.withLock {
            guard !closed else { return false }
            closed = true
            return true
        }
        if shouldFinish { operation.finish() }
    }

    deinit {
        // Conservative fallback for an abandoned retained value: keep the real
        // operation alive until the main actor actually removes its scope.
        // Normal completion uses explicit close, not deinit as a drain proof.
        let shouldFinish = lock.withLock {
            guard !closed else { return false }
            closed = true
            return true
        }
        if shouldFinish {
            let retainedOperation = operation
            Task { @MainActor in retainedOperation.finish() }
        }
    }
}

@MainActor
private final class WeakTemporalSessionOwnerV1 {
    weak var owner: StoreSessionCoordinator?
    init(_ owner: StoreSessionCoordinator) { self.owner = owner }
}

extension StoreSessionCoordinator {
    /// Every coordinator constructed with this actual writer discovers the
    /// same owner. The weak table cannot keep an unused session alive.
    static func temporalOwner(for writer: any TemporalEvidenceCanonicalWorkspaceWritingV1)
        -> StoreSessionCoordinator? {
        guard let writer = writer as? WorkspaceWriterV1 else { return nil }
        let key = ObjectIdentifier(writer)
        guard let value = temporalSessionOwners[key]?.owner,
              value.workspaceWriter === writer else {
            temporalSessionOwners.removeValue(forKey: key)
            return nil
        }
        return value
    }

    private func registerTemporalOwner() {
        Self.temporalSessionOwners = Self.temporalSessionOwners.filter { $0.value.owner != nil }
        Self.temporalSessionOwners[ObjectIdentifier(workspaceWriter)] = .init(self)
    }

    private func requireTemporalOwnerIdle() throws {
        guard temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              temporalAdmission == .open else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private var temporalPublicationIsAdmitted: Bool {
        if temporalAdmission == .open { return true }
        guard case .draining = temporalAdmission,
              let operation = TemporalProducerTaskContextV1.operation,
              operation.isLiveScope(for: self), temporalProducerIDs.contains(operation.id) else {
            return false
        }
        return true
    }

    private func beginTemporalProducer() throws -> StoreTemporalProducerOperationV1 {
        guard temporalAdmission == .open else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let registry = writerFence.retainedTemporalRegistry
        let activity = try registry.acquireTemporalProducerActivity(writer: writerLeaseHandle.token)
        do {
            try writerFence.validateCurrent()
            guard temporalAdmission == .open else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let operation = StoreTemporalProducerOperationV1(owner: self,
                writer: workspaceWriter, activity: activity)
            guard temporalProducerIDs.insert(operation.id).inserted else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            return operation
        } catch {
            activity.close()
            throw error
        }
    }

    fileprivate func validateTemporalProducer(_ operation: StoreTemporalProducerOperationV1) throws {
        guard operation.owner === self, operation.writer === workspaceWriter,
              temporalProducerIDs.contains(operation.id) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let registry = writerFence.retainedTemporalRegistry
        try registry.validateTemporalProducerActivity(operation.activity, writer: writerLeaseHandle.token)
        try writerFence.validateCurrent()
    }

    fileprivate func finishTemporalProducer(_ operation: StoreTemporalProducerOperationV1) {
        guard operation.owner === self, temporalProducerIDs.remove(operation.id) != nil else { return }
        guard temporalProducerIDs.isEmpty else { return }
        let waiters = temporalDrainWaiters
        temporalDrainWaiters.removeAll()
        for waiter in waiters.values { waiter.resume() }
    }

    /// Lifetime accounting, not mutation authority. No G is held around the
    /// body, and the ordinary writer/file ports retain all their own checks.
    /// Nested adapter calls may finish an admitted operation after admission
    /// closes; new task roots cannot enter that closed owner.
    func withTemporalProducer<Value: Sendable>(
        _ body: @MainActor () async throws -> Value
    ) async throws -> Value {
        if let existing = TemporalProducerTaskContextV1.operation {
            try existing.retainScope(for: self)
            defer { existing.finish() }
            return try await body()
        }
        let operation = try beginTemporalProducer()
        defer { operation.finish() }
        return try await TemporalProducerTaskContextV1.$operation.withValue(operation) {
            try await body()
        }
    }

    func withSynchronousTemporalProducer<Value>(
        _ body: () throws -> Value
    ) throws -> Value {
        if let existing = TemporalProducerTaskContextV1.operation {
            try existing.retainScope(for: self)
            defer { existing.finish() }
            return try body()
        }
        let operation = try beginTemporalProducer()
        defer { operation.finish() }
        return try TemporalProducerTaskContextV1.$operation.withValue(operation) { try body() }
    }

    /// A fixed lifetime extension of this exact already-admitted operation.
    /// No new task root can mint it after producer admission closes.
    func retainTemporalProducerResource() throws -> StoreTemporalProducerResourceV1 {
        guard let operation = TemporalProducerTaskContextV1.operation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.validate(for: self)
        return try StoreTemporalProducerResourceV1(operation: operation)
    }

    /// Cancellation does not release producer ownership. This waiter stays
    /// owned until actual work settles, then is removed/resumed exactly once.
    private func awaitTemporalProducerDrain(id: UUID) async {
        guard !temporalProducerIDs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            guard !temporalProducerIDs.isEmpty else { continuation.resume(); return }
            temporalDrainWaiters[id] = continuation
        }
    }
}


/// Actual owner-wide drain and EX lifetime. This is exclusion only; canonical
/// source/read/access and fixed-publication proof are separate requirements.
@MainActor
final class StoreTemporalNormalizationExclusionV1 {
    fileprivate var owner: StoreSessionCoordinator?
    fileprivate let id: UUID
    let registry: GenerationLeaseRegistryV1
    let retainedWriter: GenerationLeaseTokenV1
    fileprivate var writer: WorkspaceWriterV1?
    fileprivate let activity: GenerationTemporalActivityHandleV1
    fileprivate let physicalRoot: StoreTemporalPhysicalRootExclusionV1
    fileprivate var sourceOwner: TemporalNormalizationSourceOwnerV1?

    fileprivate init(owner: StoreSessionCoordinator, id: UUID,
                     registry: GenerationLeaseRegistryV1,
                     retainedWriter: GenerationLeaseTokenV1,
                     writer: WorkspaceWriterV1,
                     activity: GenerationTemporalActivityHandleV1,
                     physicalRoot: StoreTemporalPhysicalRootExclusionV1) {
        self.owner = owner; self.id = id; self.registry = registry
        self.retainedWriter = retainedWriter; self.writer = writer; self.activity = activity
        self.physicalRoot = physicalRoot
    }

    func revalidate() throws {
        guard let owner else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try owner.validateTemporalNormalizationExclusion(self)
    }

    func retainSourceSession(for coordinator: StoreSessionCoordinator) throws -> StoreGenerationSession {
        guard let owner, coordinator === owner else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try revalidate()
        return owner.temporalSourceSession(self)
    }

    func registerSourceOwner(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try revalidate()
        guard sourceOwner == nil, source.isBound(to: self) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        sourceOwner = source
    }

    func releaseSourceOwnerAfterDrain(_ source: TemporalNormalizationSourceOwnerV1) throws {
        guard sourceOwner === source, source.isBound(to: self) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try source.requireResourcesDrained()
        sourceOwner = nil
    }

    func acquireRetiredSourceReader(_ allocation: GenerationLeaseAllocationAttemptV1,
                                   source: TemporalNormalizationSourceOwnerV1) throws -> GenerationLeaseHandleV1 {
        try revalidate()
        guard sourceOwner === source, source.isBound(to: self) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try source.requireSourceReaderAllocation(allocation)
        return try allocation.acquireReaderWhileExcluded(activity: activity)
    }
    func closeRetiredSourceReader(_ allocation: GenerationLeaseAllocationAttemptV1,
                                 source: TemporalNormalizationSourceOwnerV1) throws {
        try revalidate()
        guard sourceOwner === source, source.isBound(to: self), allocation.sealedForRetirement else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try source.requireSourceReaderAllocation(allocation)
        try allocation.closeAfterDrain(activity: activity)
    }

    func observeSourceRegistry() throws -> TemporalGenerationRegistryObservationV1 {
        try revalidate()
        return try registry.observeTemporalNormalizationRegistry(activity)
    }

    func transferToEraseRetirement(binding: EraseRetirementBindingV1,
        drain: EraseSessionDrainWitnessV1, permit: TemporalNormalizationEraseTransferPermitV1) throws
        -> EraseRetirementExclusionV1 {
        guard let owner else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        return try owner.transferTemporalExclusionToErase(self, binding: binding, drain: drain, permit: permit)
    }

    /// Failure/resource shutdown only. This cannot publish readiness or reopen
    /// producer admission. The actual writer is invalidated before release.
    func closeForMaintenance() throws {
        guard let owner else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try owner.closeTemporalNormalizationForMaintenance(self)
    }
}

extension StoreSessionCoordinator {
    func retainedTemporalNormalizationExclusionForRetry() throws -> StoreTemporalNormalizationExclusionV1 {
        guard let value = temporalExclusiveOwner, value.owner === self,
              value.writer === workspaceWriter,
              temporalAdmission == .exclusive(value.id) || temporalAdmission == .maintenance(value.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return value
    }

    /// The only admission-closing route. Cancellation cannot skip the actual
    /// drain, release the writer or pretend the producer's catch tail ended.
    func drainTemporalProducersForNormalization() async throws -> StoreTemporalNormalizationExclusionV1 {
#if DEBUG
        print("V23_ERASE_EXCLUSION_V1 stage=entry admissionOpen=\(temporalAdmission == .open) retainedOwner=\(temporalExclusiveOwner != nil)")
#endif
        guard temporalAdmission == .open, temporalExclusiveOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let id = UUID()
        temporalAdmission = .draining(id)
        #if DEBUG
        print("V23_ERASE_EXCLUSION_V1 stage=producer-drain.enter")
        #endif
        await awaitTemporalProducerDrain(id: id)
        #if DEBUG
        print("V23_ERASE_EXCLUSION_V1 stage=producer-drain.complete")
        #endif
        do {
            guard temporalAdmission == .draining(id), temporalProducerIDs.isEmpty,
                  temporalDrainWaiters.isEmpty else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            // NB means no OS or actor wait while a foreign process still has
            // a producer handle. EX is acquired before taking G for census.
            let registry = writerFence.retainedTemporalRegistry
            #if DEBUG
            print("V23_ERASE_EXCLUSION_V1 stage=registry-activity.enter")
            #endif
            let activity = try registry.acquireTemporalNormalizationActivity(
                retainedWriter: writerLeaseHandle.token)
            #if DEBUG
            print("V23_ERASE_EXCLUSION_V1 stage=registry-activity.complete")
            #endif
            let physicalRoot: StoreTemporalPhysicalRootExclusionV1
            do {
                #if DEBUG
                print("V23_ERASE_EXCLUSION_V1 stage=physical-root.enter")
                #endif
                physicalRoot = try StoreTemporalPhysicalRootExclusionV1(
                    applicationSupportURL: Self.applicationSupportURL(for: session))
                #if DEBUG
                print("V23_ERASE_EXCLUSION_V1 stage=physical-root.complete")
                #endif
            } catch { activity.close(); throw error }
            let owned = StoreTemporalNormalizationExclusionV1(owner: self, id: id,
                registry: registry, retainedWriter: writerLeaseHandle.token,
                writer: workspaceWriter, activity: activity, physicalRoot: physicalRoot)
            temporalExclusiveOwner = owned
            temporalAdmission = .exclusive(id)
            #if DEBUG
            print("V23_ERASE_EXCLUSION_V1 stage=owned-revalidate.enter")
            #endif
            try owned.revalidate()
            #if DEBUG
            print("V23_ERASE_EXCLUSION_V1 stage=owned-revalidate.complete")
            #endif
            temporalAdmissionFailureID = nil
            return owned
        } catch {
            // The owner remains reachable and cannot accept new producers or
            // release/rebind its writer until a genuine exit proof settles.
            temporalAdmission = .maintenance(id)
            temporalAdmissionFailureID = id
            throw error
        }
    }

    /// Continues only this owner's recorded acquisition failure. Existing
    /// actual EX is retained, never replaced; no producer admission reopens.
    /// A writer-close failure is a different state and cannot enter here.
    func retryTemporalNormalizationExclusion() throws -> StoreTemporalNormalizationExclusionV1 {
        guard let id = temporalAdmissionFailureID, temporalAdmission == .maintenance(id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            let owned: StoreTemporalNormalizationExclusionV1
            if let retained = temporalExclusiveOwner {
                guard retained.id == id, retained.owner === self, retained.writer === workspaceWriter else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                owned = retained
            } else {
                let registry = writerFence.retainedTemporalRegistry
                let activity = try registry.acquireTemporalNormalizationActivity(retainedWriter: writerLeaseHandle.token)
                let root: StoreTemporalPhysicalRootExclusionV1
                do { root = try StoreTemporalPhysicalRootExclusionV1(applicationSupportURL: Self.applicationSupportURL(for: session)) }
                catch { activity.close(); throw error }
                owned = StoreTemporalNormalizationExclusionV1(owner: self, id: id, registry: registry,
                    retainedWriter: writerLeaseHandle.token, writer: workspaceWriter, activity: activity, physicalRoot: root)
                temporalExclusiveOwner = owned
            }
            temporalAdmission = .exclusive(id)
            try owned.revalidate()
            temporalAdmissionFailureID = nil
            return owned
        } catch {
            temporalAdmission = .maintenance(id)
            throw error
        }
    }

    fileprivate func validateTemporalNormalizationExclusion(
        _ exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard temporalExclusiveOwner === exclusion, exclusion.owner === self,
              exclusion.writer === workspaceWriter,
              exclusion.retainedWriter == writerLeaseHandle.token,
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(mutationRegistry: exclusion.registry)
        try exclusion.physicalRoot.revalidate(
            applicationSupportURL: Self.applicationSupportURL(for: session))
        try exclusion.registry.validateTemporalNormalizationActivity(
            exclusion.activity, retainedWriter: exclusion.retainedWriter)
        try exclusion.physicalRoot.revalidate(
            applicationSupportURL: Self.applicationSupportURL(for: session))
    }
}


extension StoreSessionCoordinator {
    fileprivate func temporalSourceSession(_ exclusion: StoreTemporalNormalizationExclusionV1)
        -> StoreGenerationSession {
        // Called only after this exact opaque exclusion revalidated the owner.
        session
    }

    fileprivate func closeTemporalNormalizationForMaintenance(
        _ exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard temporalExclusiveOwner === exclusion, exclusion.owner === self,
              exclusion.sourceOwner == nil,
              exclusion.writer === workspaceWriter,
              exclusion.retainedWriter == writerLeaseHandle.token,
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              temporalAdmission == .exclusive(exclusion.id)
                || temporalAdmission == .maintenance(exclusion.id) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        temporalAdmission = .maintenance(exclusion.id)
        temporalAdmissionFailureID = nil
        workspaceWriter.invalidate()
        // A failed physical lease close retains both actual exclusions and
        // the exact release attempt. No path reopens producer admission.
        try writerLeaseHandle.closeForTemporalMaintenance(activity: exclusion.activity)
        try exclusion.activity.closeCheckedForMaintenance()
        try exclusion.physicalRoot.closeCheckedForMaintenance()
        temporalExclusiveOwner = nil
    }
}


/// This physical exclusion is constructed only by the actual Coordinator's
/// closed-admission route. It is neither content access nor source authority.
/// Generic producers hold SH on this same existing Application Support inode.
@MainActor
final class StoreTemporalPhysicalRootExclusionV1 {
    private let applicationSupportURL: URL
    private var device: dev_t
    private var inode: ino_t
    private var descriptor: Int32
    private var checkedCloseUncertain = false

    // Retained by the cold Erase acquisition owner before opening or locking.
    fileprivate init(unacquiredColdRetirementAt url: URL) throws {
        guard url.isFileURL, !url.path.utf8.contains(0) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        applicationSupportURL = url.standardizedFileURL; device = 0; inode = 0; descriptor = -1
    }
    private var coldAcquisition = false
    private var coldLockHeld = false
    private var coldIdentityCaptured = false
    fileprivate func acquireColdRetirement() throws {
        guard !checkedCloseUncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        coldAcquisition = true
        if descriptor < 0 {
            descriptor = Darwin.open(applicationSupportURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
        if !coldIdentityCaptured {
            var held = stat()
            guard fstat(descriptor, &held) == 0, (held.st_mode & S_IFMT) == S_IFDIR else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            device = held.st_dev; inode = held.st_ino; coldIdentityCaptured = true
        }
        if !coldLockHeld {
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            coldLockHeld = true
        }
        try revalidate(applicationSupportURL: applicationSupportURL)
    }
    fileprivate func closeColdAcquisitionAfterFailure() throws {
        guard coldAcquisition, !checkedCloseUncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        guard descriptor >= 0 else { return }
        if coldLockHeld {
            guard flock(descriptor, LOCK_UN) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            coldLockHeld = false
        }
        let owned = descriptor; descriptor = -1
        guard Darwin.close(owned) == 0 else {
            checkedCloseUncertain = true; throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

#if DEBUG
    static func unacquiredOriginalEraseShutdown(at url: URL) throws
        -> StoreTemporalPhysicalRootExclusionV1 {
        try StoreTemporalPhysicalRootExclusionV1(unacquiredColdRetirementAt: url)
    }
    func acquireOriginalEraseShutdown() throws { try acquireColdRetirement() }
    func closeCheckedForOriginalEraseShutdown() throws { try closeCheckedForMaintenance() }
#endif

    fileprivate init(applicationSupportURL: URL) throws {
        guard applicationSupportURL.isFileURL, !applicationSupportURL.path.utf8.contains(0) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let root = applicationSupportURL.standardizedFileURL
        let opened = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard opened >= 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        var information = stat()
        guard Darwin.fstat(opened, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR,
              flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            _ = Darwin.close(opened)
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        self.applicationSupportURL = root
        descriptor = opened; device = information.st_dev; inode = information.st_ino
        do { try revalidate(applicationSupportURL: root) }
        catch { close(); throw error }
    }

    fileprivate func revalidate(applicationSupportURL expected: URL) throws {
        var held = stat(), named = stat()
        guard descriptor >= 0, expected.standardizedFileURL == applicationSupportURL,
              Darwin.fstat(descriptor, &held) == 0,
              Darwin.lstat(applicationSupportURL.path, &named) == 0,
              [held, named].allSatisfy({
                  $0.st_mode & S_IFMT == S_IFDIR && $0.st_dev == device && $0.st_ino == inode
              }) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
    }

    fileprivate func requireEraseSupport(_ subject: EraseAllOperationSubjectV1) throws {
        guard !checkedCloseUncertain,
              subject.applicationSupportURL.standardizedFileURL == applicationSupportURL,
              subject.applicationSupportDevice == Int64(device),
              subject.applicationSupportInode == UInt64(inode) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try revalidate(applicationSupportURL: applicationSupportURL)
    }
    fileprivate func requireOperationsAbsent() throws {
        guard !checkedCloseUncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try revalidate(applicationSupportURL: applicationSupportURL)
        var named = stat()
        guard Darwin.fstatat(descriptor, "FieldEvidenceOperations", &named, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
    }
    fileprivate func closeCheckedForMaintenance() throws {
        guard !checkedCloseUncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try revalidate(applicationSupportURL: applicationSupportURL)
        guard flock(descriptor, LOCK_UN) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        let owned = descriptor; descriptor = -1
        guard Darwin.close(owned) == 0 else {
            checkedCloseUncertain = true
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
#if DEBUG
    /// Post-retirement fault shutdown retains the original Operations name;
    /// this closes the *already held* physical-root exclusion, not a new one.
    func closeCheckedForPostRetiredEraseAbandonment() throws {
        try closeCheckedForMaintenance()
    }
#endif

    fileprivate func closeCheckedAfterNamespaceRemoval() throws {
        try requireOperationsAbsent()
        guard flock(descriptor, LOCK_UN) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        let owned = descriptor; descriptor = -1
        guard Darwin.close(owned) == 0 else {
            // A close error can leave descriptor ownership ambiguous. Do not
            // retry a possibly reused integer or report successful release.
            checkedCloseUncertain = true
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func close() {
        guard descriptor >= 0 else { return }
        let owned = descriptor; descriptor = -1
        _ = flock(owned, LOCK_UN)
        _ = Darwin.close(owned)
    }

    deinit {
        // Fallback only: explicit owner exit must drain every reader and pin
        // before disposal. Deallocation is never reported as successful drain.
        if descriptor >= 0 {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
    }
}


/// Genuine cold-start physical exclusion. It owns no Coordinator, writer or
/// source ModelContext. Empty census is freshly observed, never inferred from
/// a missing local session or from advisory flock success alone.
@MainActor
final class TemporalNormalizationColdExclusionV1 {
    private let operation: TemporalNormalizationColdOperationAuthorityV1
    private let applicationSupportURL: URL
    private var physicalRoot: StoreTemporalPhysicalRootExclusionV1?
    private var registry: GenerationLeaseRegistryV1?
    private var construction: TemporalColdRegistryConstructionV1?
    private var activity: GenerationTemporalActivityHandleV1?
    private var sourceOwner: TemporalNormalizationSourceOwnerV1?
    private var closed = false
    private init(applicationSupportURL: URL, operation: TemporalNormalizationColdOperationAuthorityV1) {
        self.applicationSupportURL = applicationSupportURL; self.operation = operation
    }
    static func acquire(applicationSupportURL: URL, operation: TemporalNormalizationColdOperationAuthorityV1,
        scope: TemporalNormalizationColdAccessScopeV1) throws -> TemporalNormalizationColdExclusionV1 {
        try scope.requireOperation(operation)
        let value = TemporalNormalizationColdExclusionV1(applicationSupportURL: applicationSupportURL,
            operation: operation)
        try operation.retainColdExclusion(value, scope: scope)
        try value.acquire(scope: scope)
        return value
    }
    func isBound(to expected: TemporalNormalizationColdOperationAuthorityV1) -> Bool { operation === expected }
    private func acquire(scope: TemporalNormalizationColdAccessScopeV1) throws {
        try scope.requireOperation(operation)
        physicalRoot = try StoreTemporalPhysicalRootExclusionV1(applicationSupportURL: applicationSupportURL)
        let construction = TemporalColdRegistryConstructionV1()
        self.construction = construction
        registry = try GenerationLeaseRegistryV1.openExistingForTemporalCold(
            applicationSupportURL: applicationSupportURL, operation: operation, scope: scope, construction: construction)
        guard let registry else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try registry.finishTemporalColdConstruction(operation: operation, scope: scope)
        self.construction = nil
        activity = try registry.acquireTemporalNormalizationActivity(retainedWriter: nil)
        try revalidateEmpty(scope: scope)
    }
    func revalidateEmpty(scope: TemporalNormalizationColdAccessScopeV1) throws {
        try scope.requireOperation(operation)
        guard !closed, let physicalRoot, let registry, let activity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try physicalRoot.revalidate(applicationSupportURL: applicationSupportURL)
        let observed = try registry.observeTemporalNormalizationRegistry(activity)
        guard observed.leases.isEmpty else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try physicalRoot.revalidate(applicationSupportURL: applicationSupportURL)
    }
    func retainedRegistryForSource() throws -> GenerationLeaseRegistryV1 {
        try revalidateSourceOwnership()
        guard let registry else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        return registry
    }
    func revalidateSourceOwnership() throws {
        guard !closed, let physicalRoot, let registry, let activity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try physicalRoot.revalidate(applicationSupportURL: applicationSupportURL)
        let observed = try registry.observeTemporalNormalizationRegistry(activity)
        guard !observed.leases.contains(where: { $0.role == .writer }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try physicalRoot.revalidate(applicationSupportURL: applicationSupportURL)
    }
    func observeSourceRegistry() throws -> TemporalGenerationRegistryObservationV1 {
        try revalidateSourceOwnership()
        guard let registry, let activity else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        return try registry.observeTemporalNormalizationRegistry(activity)
    }
    func registerSourceOwner(_ source: TemporalNormalizationSourceOwnerV1) throws {
        try revalidateSourceOwnership()
        guard sourceOwner == nil, source.isBound(to: self) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        sourceOwner = source
    }
    func releaseSourceOwnerAfterDrain(_ source: TemporalNormalizationSourceOwnerV1) throws {
        guard sourceOwner === source, source.isBound(to: self) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try source.requireResourcesDrained()
        sourceOwner = nil
    }
    func acquireSourceReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        source: TemporalNormalizationSourceOwnerV1) throws -> GenerationLeaseHandleV1 {
        try revalidateSourceOwnership()
        guard sourceOwner === source, source.isBound(to: self), let activity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try source.requireSourceReaderAllocation(allocation)
        return try allocation.acquireReaderWhileExcluded(activity: activity)
    }
    func closeSourceReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        source: TemporalNormalizationSourceOwnerV1) throws {
        try revalidateSourceOwnership()
        guard sourceOwner === source, source.isBound(to: self), allocation.sealedForRetirement,
              let activity else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try source.requireSourceReaderAllocation(allocation)
        try allocation.closeAfterDrain(activity: activity)
    }

    /// Failure keeps actual resources owned. A registered SOURCE must first
    /// dispose its worker/readers/pins and its exact durable reader allocation.
    func closeAfterFailure() throws {
        guard !closed else { return }
        guard sourceOwner == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if let registry {
            if activity == nil {
                activity = try registry.acquireTemporalNormalizationActivity(retainedWriter: nil)
            }
            guard let activity else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try registry.closeTemporalColdOwnerGuard(activity: activity)
            self.registry = nil
        }
        try activity?.closeAfterColdOwnerGuardRemoval(); activity = nil
        if let construction {
            guard let physicalRoot else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try physicalRoot.revalidate(applicationSupportURL: applicationSupportURL)
            try construction.closeUntransferred()
            self.construction = nil
        }
        try physicalRoot?.closeCheckedForMaintenance(); physicalRoot = nil
        closed = true
    }
}


extension StoreSessionCoordinator {
    fileprivate func transferTemporalExclusionToErase(_ exclusion: StoreTemporalNormalizationExclusionV1,
        binding: EraseRetirementBindingV1, drain: EraseSessionDrainWitnessV1,
        permit: TemporalNormalizationEraseTransferPermitV1) throws -> EraseRetirementExclusionV1 {
        try exclusion.revalidate()
        try permit.require(binding: binding, exclusion: exclusion, drain: drain)
        guard temporalExclusiveOwner === exclusion, exclusion.owner === self,
              exclusion.sourceOwner == nil, exclusion.writer === workspaceWriter,
              binding.generationEpoch == writerLeaseHandle.token.epoch,
              binding.workspaceIdentity == session.workspaceIdentity,
              drain.binding == binding, drain.observes(session: session),
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try exclusion.physicalRoot.requireEraseSupport(binding.subject)
        try exclusion.registry.requireTemporalEraseNamespace(binding.registryIdentity)
        var expected = [writerLeaseHandle.token]
        for reader in drain.capturedReaders {
            guard reader.token.role == .reader else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try reader.requireLiveTemporalIdentity(mutationRegistry: exclusion.registry)
            expected.append(reader.token)
        }
        for allocation in drain.capturedAllocations {
            guard allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            if let token = try allocation.observedRetirementToken(activity: exclusion.activity), !expected.contains(token) {
                expected.append(token)
            }
        }
        let observed = try exclusion.registry.observeTemporalNormalizationRegistry(exclusion.activity)
        guard Set(expected.map(\.leaseID)).count == expected.count,
              observed.leases.count == expected.count,
              observed.leases.allSatisfy({ expected.contains($0) }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let transferred = EraseRetirementExclusionV1(binding: binding, drain: drain,
            writer: writerLeaseHandle, registry: exclusion.registry,
            activity: exclusion.activity, physicalRoot: exclusion.physicalRoot)
        // No throwing edge follows consumption. No unlock/reacquire occurs.
        try permit.consume(binding: binding, exclusion: exclusion, drain: drain)
        workspaceWriter.invalidate()
        temporalAdmission = .maintenance(exclusion.id)
        temporalExclusiveOwner = nil
        exclusion.owner = nil; exclusion.writer = nil
        return transferred
    }
}

/// Context-free transfer of actual held exclusions and lease handles. This
/// object never retains a Coordinator, writer, session, factory, callback or
/// arbitrary Error. It does not mint a retirement/completion proof.
@MainActor
final class EraseRetirementExclusionV1 {
    private let binding: EraseRetirementBindingV1
    private let drain: EraseSessionDrainWitnessV1
    private enum WriterOwnership { case retained(GenerationLeaseHandleV1), absentAtColdAdmission }
    private let writer: WriterOwnership
    private let registry: GenerationLeaseRegistryV1
    private let activity: GenerationTemporalActivityHandleV1
    private let physicalRoot: StoreTemporalPhysicalRootExclusionV1
    private var closedReaderIDs = Set<ObjectIdentifier>()
    private var closedAllocationIDs = Set<ObjectIdentifier>()
    private var writerClosed = false
    private var released = false
    private var retirementStarted = false
    private var coldFailureClosing = false
#if DEBUG
    private var postRetiredColdClosed = false
#endif
    // Weak exact identities avoid EX -> witness -> attempt -> EX ownership cycles.
    // This pair is set only after the original strong witness and actual empty
    // census pass, and is never replaced or reset on a failed transfer.
    private weak var manifestTransferRetirement: ErasedRegistryRetirementProofV1?
    private weak var manifestTransferAttempt: EraseManifestRetirementAttemptV1?
    private var manifestTransferRegistered = false
    fileprivate init(binding: EraseRetirementBindingV1, drain: EraseSessionDrainWitnessV1,
        writer: GenerationLeaseHandleV1, registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1, physicalRoot: StoreTemporalPhysicalRootExclusionV1) {
        self.binding = binding; self.drain = drain; self.writer = .retained(writer); self.registry = registry
        self.activity = activity; self.physicalRoot = physicalRoot
    }
    fileprivate init(coldBinding binding: EraseRetirementBindingV1, drain: EraseSessionDrainWitnessV1,
        registry: GenerationLeaseRegistryV1, activity: GenerationTemporalActivityHandleV1,
        physicalRoot: StoreTemporalPhysicalRootExclusionV1) {
        self.binding = binding; self.drain = drain; writer = .absentAtColdAdmission
        self.registry = registry; self.activity = activity; self.physicalRoot = physicalRoot
    }
    fileprivate func requireColdAcquisitionRetry() throws {
        guard case .absentAtColdAdmission = writer, !released, !writerClosed, !retirementStarted, !coldFailureClosing,
              closedReaderIDs.isEmpty, closedAllocationIDs.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireLiveRegistry(binding: binding)
    }
    fileprivate func closeColdBeforeRetirement() throws {
        guard case .absentAtColdAdmission = writer, !retirementStarted else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if released { return }
        if !coldFailureClosing {
            try requireColdAcquisitionRetry()
            coldFailureClosing = true
        }
        try activity.closeCheckedForMaintenance()
        try physicalRoot.closeColdAcquisitionAfterFailure()
        released = true
    }
    func requireSupport(binding expected: EraseRetirementBindingV1) throws {
        guard !released, binding == expected else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try physicalRoot.requireEraseSupport(binding.subject)
    }
    func requireLiveRegistry(binding expected: EraseRetirementBindingV1) throws {
        try requireSupport(binding: expected)
        try registry.requireTemporalEraseNamespace(binding.registryIdentity)
        _ = try registry.observeTemporalNormalizationRegistry(activity)
    }
#if DEBUG
    /// Before alias drain, prove the actual original source reader is still
    /// captured and durably active through this transferred EX owner. This
    /// deliberately does not open another Registry or acquire ordinary SH.
    func requireCapturedOriginalReaderActiveForV949Fixture(
        session: StoreGenerationSession,
        reader: GenerationLeaseHandleV1
    ) throws {
        guard !released, !retirementStarted, !coldFailureClosing,
              let token = session.readerLeaseToken,
              token == reader.token, token.role == .reader,
              token.epoch.generationID == session.generationID,
              session.generationID != binding.subject.newGenerationID,
              drain.observes(session: session),
              drain.capturedReaders.contains(where: { $0 === reader }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireLiveRegistry(binding: binding)
        try reader.requireLiveTemporalIdentity(mutationRegistry: registry)
        let observed = try registry.observeTemporalNormalizationRegistry(activity)
        guard observed.leases.contains(token) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireSupport(binding: binding)
    }
#endif

    /// Pure prevalidation of the still-owned target reader after ORIGINAL
    /// aliases drain. Joined semantic validation is required separately before
    /// any close; this does not use the stronger close/completion witness gate.
    func requirePostDrainValidation(reader: GenerationLeaseHandleV1,
        proof: EraseSessionDrainWitnessV1) throws {
        guard proof === drain, !released, !retirementStarted, !coldFailureClosing,
              !writerClosed, closedReaderIDs.isEmpty, closedAllocationIDs.isEmpty,
              reader.token.role == .reader, reader.token.epoch == binding.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try proof.requireOriginalAliasesDrained(binding: binding, reader: reader)
        try requireLiveRegistry(binding: binding)
        try reader.requireLiveTemporalIdentity(mutationRegistry: registry)
        var expected: [GenerationLeaseTokenV1] = []
        switch writer {
        case .retained(let handle):
            try handle.requireLiveTemporalIdentity(mutationRegistry: registry)
            expected.append(handle.token)
        case .absentAtColdAdmission: break
        }
        for captured in drain.capturedReaders {
            guard captured.token.role == .reader else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try captured.requireLiveTemporalIdentity(mutationRegistry: registry)
            expected.append(captured.token)
        }
        for allocation in drain.capturedAllocations {
            guard allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            if let token = try allocation.observedRetirementToken(activity: activity), !expected.contains(token) {
                expected.append(token)
            }
        }
        let observed = try registry.observeTemporalNormalizationRegistry(activity)
        guard expected.contains(reader.token), Set(expected.map(\.leaseID)).count == expected.count,
              observed.leases.count == expected.count,
              observed.leases.allSatisfy({ expected.contains($0) }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try proof.requireOriginalAliasesDrained(binding: binding, reader: reader)
        try requireSupport(binding: binding)
    }

    func closeAllocationAfterDrain(allocation: GenerationLeaseAllocationAttemptV1,
                                  proof: EraseSessionDrainWitnessV1) throws {
        guard proof === drain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try proof.requireDrained(binding: binding, allocation: allocation)
        try requireLiveRegistry(binding: binding)
        let identity = ObjectIdentifier(allocation)
        guard !closedAllocationIDs.contains(identity) else { return }
        retirementStarted = true
        try allocation.closeAfterDrain(activity: activity)
        closedAllocationIDs.insert(identity)
        if let handle = allocation.allocatedHandle {
            closedReaderIDs.insert(ObjectIdentifier(handle))
        }
    }
    func closeReaderAfterDrain(handle: GenerationLeaseHandleV1, proof: EraseSessionDrainWitnessV1) throws {
        guard proof === drain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try proof.requireDrained(binding: binding, reader: handle)
        try requireLiveRegistry(binding: binding)
        let identity = ObjectIdentifier(handle)
        guard !closedReaderIDs.contains(identity) else { return }
        try handle.requireLiveTemporalIdentity(mutationRegistry: registry)
        retirementStarted = true
        try handle.closeForTemporalMaintenance(activity: activity)
        closedReaderIDs.insert(identity)
    }
    func closeWriterAfterDrain(proof: EraseSessionDrainWitnessV1) throws {
        guard proof === drain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try proof.requireDrained(binding: binding)
        try requireLiveRegistry(binding: binding)
        guard !writerClosed else { return }
        retirementStarted = true
        switch writer {
        case .retained(let handle):
            try handle.requireLiveTemporalIdentity(mutationRegistry: registry)
            try handle.closeForTemporalMaintenance(activity: activity)
        case .absentAtColdAdmission:
            guard try !registry.observeTemporalNormalizationRegistry(activity).leases.contains(where: { $0.role == .writer }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        writerClosed = true
    }
    func requireNoLeasesAfterDrain(proof: EraseSessionDrainWitnessV1) throws {
        guard proof === drain, writerClosed,
              drain.capturedAllocations.allSatisfy({ closedAllocationIDs.contains(ObjectIdentifier($0)) }),
              drain.capturedReaders.allSatisfy({ closedReaderIDs.contains(ObjectIdentifier($0)) }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try proof.requireDrained(binding: binding)
        try requireLiveRegistry(binding: binding)
        guard try registry.observeTemporalNormalizationRegistry(activity).leases.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
    /// Initial transfer admission still uses the complete joined witness.
    /// No namespace mutation occurs until both actual owners have registered
    /// this exact pair and advanced their own monotonic transfer phases.
    func beginManifestTransfer(retirement: ErasedRegistryRetirementProofV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard !manifestTransferRegistered, !released, !coldFailureClosing else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try retirement.requireInitialManifestTransfer(exclusion: self, attempt: attempt)
        try requireNoLeasesAfterDrain(proof: drain)
        try retirement.requireInitialManifestTransfer(exclusion: self, attempt: attempt)
        manifestTransferRetirement = retirement
        manifestTransferAttempt = attempt
        manifestTransferRegistered = true
    }

    /// The only moving-phase retry edge. The strong witness intentionally
    /// refuses an ambiguous manifest name, so it cannot be re-entered here.
    /// Actual completed handle closes, the retained pair, the proof's private
    /// phase and a fresh empty registry are all required independently.
    func requireManifestTransferRetry(retirement: ErasedRegistryRetirementProofV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard manifestTransferRegistered, manifestTransferRetirement === retirement,
              manifestTransferAttempt === attempt, !released, !coldFailureClosing,
              writerClosed,
              drain.capturedAllocations.allSatisfy({ closedAllocationIDs.contains(ObjectIdentifier($0)) }),
              drain.capturedReaders.allSatisfy({ closedReaderIDs.contains(ObjectIdentifier($0)) }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try retirement.requireManifestTransferOwnership(exclusion: self, attempt: attempt)
        try requireLiveRegistry(binding: binding)
        guard try registry.observeTemporalNormalizationRegistry(activity).leases.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try retirement.requireManifestTransferOwnership(exclusion: self, attempt: attempt)
        try requireSupport(binding: binding)
    }

    func releaseAfterNamespaceRemoval(binding expected: EraseRetirementBindingV1) throws {
        try requireSupport(binding: expected)
        guard writerClosed,
              drain.capturedAllocations.allSatisfy({ closedAllocationIDs.contains(ObjectIdentifier($0)) }),
              drain.capturedReaders.allSatisfy({ closedReaderIDs.contains(ObjectIdentifier($0)) }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try drain.requireDrained(binding: binding)
        try physicalRoot.requireOperationsAbsent()
        try activity.closeAfterNamespaceRemoval()
        try physicalRoot.closeCheckedAfterNamespaceRemoval()
        released = true
    }

#if DEBUG
    /// The old owner guard stays locked on its proved unlinked inode. Only
    /// the activity and support-root EX are checked closed by the existing
    /// namespace-removal release. No receipt or Erase-root cleanup follows.
    /// The original activity and physical-root EX remain held with Operations
    /// named. The proof/Registry selective fence authorizes their exact close.
    func closeBeforeNamespaceRemovalForTesting(
        proof: ErasedRegistryRetirementProofV1
    ) throws {
        guard !released, !postRetiredColdClosed,
              proof.binding == binding, writerClosed,
              drain.capturedAllocations.allSatisfy({
                  closedAllocationIDs.contains(ObjectIdentifier($0))
              }),
              drain.capturedReaders.allSatisfy({
                  closedReaderIDs.contains(ObjectIdentifier($0))
              }) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try registry.closePostRetiredEraseExclusion(
            proof: proof, activity: activity, physicalRoot: physicalRoot)
        postRetiredColdClosed = true
        released = true
    }

    func requirePostRetiredColdClosedForTesting(
        proof: ErasedRegistryRetirementProofV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        guard proof.binding == binding, registry === expected,
              released, postRetiredColdClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requirePostRetiredReadyForTesting(
        proof: ErasedRegistryRetirementProofV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        guard proof.binding == binding, registry === expected,
              !released, !postRetiredColdClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireNoLeasesAfterDrain(proof: drain)
    }

    func abandonAfterNamespaceRemovalForTesting(binding expected: EraseRetirementBindingV1) throws {
        guard !released, binding == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Drain's final validation still needs this exact registry. Poison it
        // after that synchronous release attempt, including any thrown close.
        defer { registry.poisonAfterEraseColdRestartAbandonmentForTesting() }
        try activity.requireUnlinkedOriginalOwnerGuardForEraseAbandonment()
        try releaseAfterNamespaceRemoval(binding: expected)
    }
#endif
}


/// Exact cold Erase partial owner. It holds physical resources and immutable
/// binding only; actual access remains in the separately retained Router scope.
@MainActor
final class EraseColdRetirementAcquisitionV1 {
    private let binding: EraseRetirementBindingV1
    private let registry: GenerationLeaseRegistryV1
    private let drain: EraseSessionDrainWitnessV1
    private var physicalRoot: StoreTemporalPhysicalRootExclusionV1?
    private var activityAttempt: GenerationTemporalColdActivityAcquisitionV1?
    private var result: EraseRetirementExclusionV1?
    private enum State { case acquiring, transferred, closed }
    private var state: State = .acquiring
    fileprivate init(binding: EraseRetirementBindingV1, registry: GenerationLeaseRegistryV1,
        drain: EraseSessionDrainWitnessV1) {
        self.binding = binding; self.registry = registry; self.drain = drain
    }
    func matches(binding expected: EraseRetirementBindingV1, registry expectedRegistry: GenerationLeaseRegistryV1,
        drain expectedDrain: EraseSessionDrainWitnessV1) -> Bool {
        binding == expected && registry === expectedRegistry && drain === expectedDrain
    }
    fileprivate func acquire(authority: EraseColdRetirementAuthorityV1,
        scope: EraseColdRetirementAccessScopeV1) throws -> EraseRetirementExclusionV1 {
        guard state == .acquiring else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try authority.requireAcquisition(binding: binding, registry: registry, drain: drain, scope: scope)
        if let result { try result.requireColdAcquisitionRetry() }
        if physicalRoot == nil {
            physicalRoot = try StoreTemporalPhysicalRootExclusionV1(unacquiredColdRetirementAt: binding.subject.applicationSupportURL)
        }
        guard let physicalRoot else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try physicalRoot.acquireColdRetirement()
        try physicalRoot.requireEraseSupport(binding.subject)
        try registry.requireTemporalEraseNamespace(binding.registryIdentity)
        if activityAttempt == nil { activityAttempt = registry.makeColdRetirementActivityAcquisition() }
        guard let activityAttempt else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        let activity = try activityAttempt.acquire()
        try authority.requireAcquisition(binding: binding, registry: registry, drain: drain, scope: scope)
        guard drain.binding == binding else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        // This is the real sealed inventory, not an empty-registry assumption.
        var expected: [GenerationLeaseTokenV1] = []
        for reader in drain.capturedReaders {
            guard reader.token.role == .reader else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try reader.requireLiveTemporalIdentity(mutationRegistry: registry)
            expected.append(reader.token)
        }
        for allocation in drain.capturedAllocations {
            guard allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            if let token = try allocation.observedRetirementToken(activity: activity), !expected.contains(token) {
                expected.append(token)
            }
        }
        let observed = try registry.observeTemporalNormalizationRegistry(activity)
        guard !observed.leases.contains(where: { $0.role == .writer }),
              Set(expected.map(\.leaseID)).count == expected.count,
              observed.leases.count == expected.count,
              observed.leases.allSatisfy({ expected.contains($0) }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try physicalRoot.requireEraseSupport(binding.subject)
        try authority.requireAcquisition(binding: binding, registry: registry, drain: drain, scope: scope)
        if let result { return result }
        let owned = EraseRetirementExclusionV1(coldBinding: binding, drain: drain,
            registry: registry, activity: activity, physicalRoot: physicalRoot)
        result = owned
        return owned
    }
    /// The Router calls this only after its actual retirement owner retains the
    /// exact result, immediately before detachment. No physical unlock occurs.
    func sealForRetirement(exclusion: EraseRetirementExclusionV1) throws {
        guard state == .acquiring, result === exclusion else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try exclusion.requireColdAcquisitionRetry()
        state = .transferred
    }
    func closeAfterFailure() throws {
        guard state != .transferred else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if state == .closed { return }
        if let result {
            try result.closeColdBeforeRetirement()
            self.result = nil
            activityAttempt = nil; physicalRoot = nil
        } else {
            try activityAttempt?.closeAfterFailure(); activityAttempt = nil
            try physicalRoot?.closeColdAcquisitionAfterFailure(); physicalRoot = nil
        }
        state = .closed
    }
}

extension EraseRetirementExclusionV1 {
    static func acquireCold(binding: EraseRetirementBindingV1, registry: GenerationLeaseRegistryV1,
        drain: EraseSessionDrainWitnessV1, authority: EraseColdRetirementAuthorityV1,
        scope: EraseColdRetirementAccessScopeV1) throws -> EraseRetirementExclusionV1 {
        try authority.requireAcquisition(binding: binding, registry: registry, drain: drain, scope: scope)
        let attempt: EraseColdRetirementAcquisitionV1
        if let retained = try authority.retainedAcquisition(binding: binding, registry: registry, drain: drain, scope: scope) {
            guard retained.matches(binding: binding, registry: registry, drain: drain) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            attempt = retained
        } else {
            attempt = EraseColdRetirementAcquisitionV1(binding: binding, registry: registry, drain: drain)
            try authority.retainAcquisition(attempt, binding: binding, registry: registry, drain: drain, scope: scope)
        }
        return try attempt.acquire(authority: authority, scope: scope)
    }
}

extension StoreTemporalNormalizationExclusionV1 {
    func requireOriginalAbandonmentScope(_ scope: TemporalNormalizationMutationScopeV1) throws {
        try revalidate()
        guard sourceOwner == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try scope.require(registry: registry, activity: activity)
    }
    func executeOriginalAbandonment(sourceSet: TemporalNormalizationRetainedSourceSetV1,
        originalAccess: TemporalNormalizationOriginalAccessScopeV1) throws -> OrphanFileCleanupSummary {
        try revalidate()
        guard sourceOwner == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        return try registry.executeTemporalOriginalAbandonment(sourceSet: sourceSet,
            activity: activity, originalAccess: originalAccess)
    }
}

extension TemporalNormalizationColdExclusionV1 {
    func requireOriginalAbandonmentScope(_ scope: TemporalNormalizationMutationScopeV1) throws {
        try revalidateSourceOwnership()
        guard sourceOwner == nil, let registry, let activity else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try scope.require(registry: registry, activity: activity)
    }
    func executeOriginalAbandonment(sourceSet: TemporalNormalizationRetainedSourceSetV1,
        originalAccess: TemporalNormalizationOriginalAccessScopeV1) throws -> OrphanFileCleanupSummary {
        try revalidateSourceOwnership()
        guard sourceOwner == nil, let registry, let activity else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        return try registry.executeTemporalOriginalAbandonment(sourceSet: sourceSet,
            activity: activity, originalAccess: originalAccess)
    }
}

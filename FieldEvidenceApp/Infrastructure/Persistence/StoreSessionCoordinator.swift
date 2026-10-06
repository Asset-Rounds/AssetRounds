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

/// The exact B writer allocation belongs to one original Restore operation.
/// It does not retain the A Coordinator, session, context, or container: those
/// are observed by the separate checked source-reader exit owner.
@MainActor
final class RestoreWriterTransitionOwnerV1 {
    let operationID: UUID
    let targetSession: StoreGenerationSession
    let targetFactory: StoreGenerationFactory
    let registry: GenerationLeaseRegistryV1
    let sourceReader: GenerationLeaseHandleV1
    let sourceWriter: GenerationLeaseHandleV1?
    let targetReader: GenerationLeaseHandleV1
    private(set) var allocation: GenerationWriterAllocationAttemptV1?
    private weak var constructedWriter: WorkspaceWriterV1?
    var constructedWriterForTransition: WorkspaceWriterV1? { constructedWriter }
    private enum Phase: Equatable { case captured, acquiring, constructed, uncertain }
    private var phase = Phase.captured

    init(operationID: UUID, targetSession: StoreGenerationSession,
         targetFactory: StoreGenerationFactory,
         sourceReader: GenerationLeaseHandleV1,
         sourceWriter: GenerationLeaseHandleV1?,
         targetReader: GenerationLeaseHandleV1) throws {
        let registry = try targetFactory.makeGenerationLeaseRegistry()
        guard let epoch = targetSession.generationEpoch,
              sourceReader.token.role == .reader,
              targetReader.token.role == .reader,
              targetReader.token.epoch == epoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try targetReader.requireExactRegistry(registry)
        try sourceReader.requireLiveTemporalIdentity(mutationRegistry: registry)
        if let sourceWriter {
            guard sourceWriter.token.role == .writer else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try sourceWriter.requireClosedForRestoreTransition()
        }
        try registry.requireExactRestoreTransitionLeases(
            [sourceReader, targetReader])
        self.operationID = operationID
        self.targetSession = targetSession
        self.targetFactory = targetFactory
        self.registry = registry
        self.sourceReader = sourceReader
        self.sourceWriter = sourceWriter
        self.targetReader = targetReader
    }

    func retainAllocation(_ value: GenerationWriterAllocationAttemptV1) throws {
        guard phase == .captured, allocation == nil,
              value.matches(registry: registry),
              value.generationEpoch == targetSession.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        allocation = value
        phase = .acquiring
    }

    func requireWriterAllocation(_ value: GenerationWriterAllocationAttemptV1,
                                 registry expected: GenerationLeaseRegistryV1) throws {
        guard phase == .acquiring, allocation === value,
              registry === expected,
              value.generationEpoch == targetSession.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try sourceWriter?.requireClosedForRestoreTransition()
        try targetReader.requireExactRegistry(registry)
        try sourceReader.requireLiveTemporalIdentity(mutationRegistry: registry)
    }

    func requireWriterLeaseCensus(_ observed: [GenerationLeaseTokenV1],
                                  registry expected: GenerationLeaseRegistryV1) throws {
        guard registry === expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireTokens(observed, equalTo: [sourceReader.token, targetReader.token])
    }

    func requirePublishedWriterLeaseCensus(_ observed: [GenerationLeaseTokenV1],
                                           token: GenerationLeaseTokenV1,
                                           registry expected: GenerationLeaseRegistryV1) throws {
        guard registry === expected, token.role == .writer,
              token.epoch == targetSession.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireTokens(observed, equalTo: [sourceReader.token, targetReader.token, token])
    }

    private func requireTokens(_ actual: [GenerationLeaseTokenV1],
                               equalTo expected: [GenerationLeaseTokenV1]) throws {
        guard actual.count == expected.count,
              Set(actual).count == actual.count,
              Set(actual) == Set(expected) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func observeConstructedWriter(_ value: WorkspaceWriterV1) throws {
        guard phase == .acquiring, constructedWriter == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        constructedWriter = value
        phase = .constructed
    }

    func sealFailure() {
        allocation?.sealForRetirement()
        phase = .uncertain
    }

    func requireFailedWriterDrained(_ value: GenerationWriterAllocationAttemptV1,
                                    registry expected: GenerationLeaseRegistryV1) throws {
        guard phase == .uncertain, allocation === value,
              registry === expected, constructedWriter == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireConstructed(_ coordinator: StoreSessionCoordinator) throws {
        guard phase == .constructed,
              coordinator.workspaceWriter === constructedWriter,
              coordinator.generationID == targetSession.generationID,
              coordinator.modelContext === targetSession.modelContext else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
}

@MainActor
final class StoreSessionCoordinator: ObservableObject {
#if DEBUG
    enum OriginalEraseJournalRecoveryProbeV1: Equatable {
        case foreignFence
        case wrongAllocation
        case completedReuse
        case failInsideCheckedScope
    }

    enum OriginalEraseJournalRecoveryProbeResultV1: Equatable {
        case rejectedBeforeBody
        case rejectedCompletedReuse
        case failedScopeBlockedOldClose
        case unexpected
    }
    private enum OriginalEraseJournalRecoveryProbeFailureV1: Error {
        case injected
    }

    /// One-shot, operation-bound development challenge. It is consumed before
    /// touching the actual recovery and never exposes a descriptor or mints
    /// production authority for a caller.
    static var originalEraseJournalRecoveryProbeForTesting:
        (operation: EraseRouterOperationV1,
         applicationSupportURL: URL,
         kind: OriginalEraseJournalRecoveryProbeV1,
         report: @MainActor (OriginalEraseJournalRecoveryProbeResultV1) -> Void)?
    private(set) var originalRecoveryRetainedSourceModelReadsForTesting = 0
#endif
    @Published private(set) var uiGenerationToken: UInt64 = 0

    private var session: StoreGenerationSession
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileAuthority: any ApplicationFileAuthorityV1
    private var generationFactory: StoreGenerationFactory
    let lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1
    private var writerLeaseHandle: GenerationLeaseHandleV1
    private var writerFence: StaleWriterFenceV1
    private var completedSessionLifetimeOwner: ColdEraseSchema2CompletedSessionLifetimeOwnerV1?
    private var completedSessionEraseProjection: ColdEraseSchema2CompletedSessionEraseProjectionV1?
    private(set) var workspaceWriter: WorkspaceWriterV1
    private(set) var searchIndexStore: LocalSearchIndexStoreV1
    private(set) var searchServices: ProductionSearchServicesV1
    private var originalC05JobOwnerSlot: ProductionC05JobOwnerSlotV1?
    // The original Erase captures the only producer slot before observing
    // either the C05 store or source-generation transient tree. A new Shell
    // cannot construct a producer between that observation and the marker.
    private var originalC05EraseCaptureID: UUID?

    private final class ErasePreparationInstallation {
        weak var operation: EraseRouterOperationV1?
        let allocation: GenerationWriterAllocationAttemptV1
        init(operation: EraseRouterOperationV1, allocation: GenerationWriterAllocationAttemptV1) {
            self.operation = operation
            self.allocation = allocation
        }
    }
    private var erasePreparationInstallation: ErasePreparationInstallation?
    private var originalErasePendingTargetWriter: WorkspaceWriterV1?
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
    private var originalEraseRecoveryOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1?
    private struct OriginalRecoveryTargetTransfer {
        let ownerID: UUID
        let operation: EraseRouterOperationV1
        let source: StoreGenerationSession
        let sourceWriter: WorkspaceWriterV1
        let sourceToken: GenerationLeaseTokenV1
        let registry: GenerationLeaseRegistryV1
        let targetGenerationID: UUID
    }
    private var originalRecoveryTargetTransfer: OriginalRecoveryTargetTransfer?
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
        if let owner = completedSessionLifetimeOwner {
            try owner.closeCurrentCompletedSessionBeforePhysicalWriterRelease(coordinator: self,
                writer: workspaceWriter)
        }
        workspaceWriter.invalidate()
        try writerLeaseHandle.close()
    }

    /// One-way A writer exit for the original Restore ticket. New producer
    /// admission remains closed; a failed durable close is retained uncertain
    /// and cannot be retried through ordinary activation.
    func closeWriterForOriginalRestoreTransition(
        source: StoreGenerationSession, drainID: UUID,
        expectedWriter: WorkspaceWriterV1
    ) throws -> GenerationLeaseHandleV1 {
        guard self.session === source,
              self.workspaceWriter === expectedWriter,
              temporalAdmission == .draining(drainID),
              temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty,
              temporalExclusiveOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        workspaceWriter.invalidate()
        do {
            try writerLeaseHandle.close()
            try writerLeaseHandle.requireClosedForRestoreTransition()
            temporalAdmission = .maintenance(drainID)
            return writerLeaseHandle
        } catch {
            temporalAdmission = .maintenance(drainID)
            throw error
        }
    }

    var restoreWriterLeaseHandleForTransition: GenerationLeaseHandleV1 {
        writerLeaseHandle
    }

    func beginOriginalRestoreProducerDrain(source: StoreGenerationSession,
                                           expectedWriter: WorkspaceWriterV1) throws -> UUID {
        guard self.session === source,
              workspaceWriter === expectedWriter,
              temporalAdmission == .open,
              temporalExclusiveOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let id = UUID()
        temporalAdmission = .draining(id)
        return id
    }

    func awaitOriginalRestoreProducerDrain(_ id: UUID) async throws {
        guard temporalAdmission == .draining(id) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        await awaitTemporalProducerDrain(id: id)
        guard temporalAdmission == .draining(id),
              temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty,
              temporalExclusiveOwner == nil else {
            temporalAdmission = .maintenance(id)
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
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

    /// This variant is for the original recovery ticket before a no-create
    /// observation. It checks the coordinator's opening provider and source
    /// token without calling provider.registry(), whose cache-miss branch
    /// constructs a Registry. The later held-EX inventory census validates
    /// the actual captured source reader wrapper against this retained G.
    private func originalEraseRecoverySourceWithoutRegistryConstruction(
        factory expectedFactory: StoreGenerationFactory
    ) throws -> StoreGenerationSession {
        let registry = writerFence.retainedTemporalRegistry
        guard generationFactory.sharesRegistryProvider(with: expectedFactory),
              let epoch = session.generationEpoch,
              let reader = session.readerLeaseToken,
              reader.role == .reader,
              reader.epoch == epoch,
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch == epoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try writerLeaseHandle.requireExactRegistry(registry)
        return session
    }

    /// Capture the original ready Restore source through the currently
    /// published writer, without manufacturing a session or a Registry.
    func requireOriginalRestoreSource(
        context expectedContext: ModelContext,
        generationID expectedID: UUID,
        factory expectedFactory: StoreGenerationFactory
    ) throws -> (session: StoreGenerationSession,
                 writer: WorkspaceWriterV1,
                 writerHandle: GenerationLeaseHandleV1) {
        guard session.modelContext === expectedContext,
              session.generationID == expectedID,
              generationFactory.sharesRegistryProvider(with: expectedFactory),
              try session.validatedOpeningFactoryForWriter()
                  .sharesRegistryProvider(with: expectedFactory),
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch == session.generationEpoch,
              try workspaceWriter.currentRevision().generationID == expectedID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let registry = try expectedFactory.makeGenerationLeaseRegistry()
        try writerLeaseHandle.requireExactRegistry(registry)
        try writerLeaseHandle.requireLiveTemporalIdentity(mutationRegistry: registry)
        try registry.validateActive(writerLeaseHandle.token, requiredRole: .writer)
        return (session, workspaceWriter, writerLeaseHandle)
    }

    /// Router has already attested B's exact pointer and retained A's source
    /// reader. A's writer is deliberately stale after that publication, so a
    /// second currentRevision() would reject the correct old owner. Check the
    /// original object, drain, provider and durable writer token instead;
    /// only the Router's same-ticket path consumes this result for close.
    func requireOriginalRestoreSourceAfterTargetPublication(
        context expectedContext: ModelContext,
        generationID expectedID: UUID,
        factory expectedFactory: StoreGenerationFactory,
        expectedWriter: WorkspaceWriterV1,
        expectedWriterHandle: GenerationLeaseHandleV1,
        drainID: UUID
    ) throws -> StoreGenerationSession {
        guard session.modelContext === expectedContext,
              session.generationID == expectedID,
              workspaceWriter === expectedWriter,
              writerLeaseHandle === expectedWriterHandle,
              temporalAdmission == .draining(drainID),
              temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty,
              temporalExclusiveOwner == nil,
              generationFactory.sharesRegistryProvider(with: expectedFactory),
              try session.validatedOpeningFactoryForWriter()
                .sharesRegistryProvider(with: expectedFactory),
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch == session.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let registry = try expectedFactory.makeGenerationLeaseRegistry()
        try writerLeaseHandle.requireExactRegistry(registry)
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: registry)
        try registry.validateActive(writerLeaseHandle.token,
            requiredRole: .writer)
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

    /// One source coordinator has one C05 runner/workflow owner across Shell
    /// reconstructions. The slot is installed synchronously before any C05
    /// store, runner or scratch allocation can suspend or fail.
    func originalC05JobOwnerSlot(
        expectedWriter: WorkspaceWriterV1,
        expectedEpoch: GenerationEpochV1
    ) throws -> ProductionC05JobOwnerSlotV1 {
        try requireTemporalOwnerIdle()
        guard originalC05EraseCaptureID == nil else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        guard expectedWriter === workspaceWriter,
              session.generationEpoch == expectedEpoch,
              writerLeaseHandle.token.epoch == expectedEpoch,
              writerLeaseHandle.token.role == .writer else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: writerFence.retainedTemporalRegistry)
        if let originalC05JobOwnerSlot {
            guard originalC05JobOwnerSlot.generationEpoch == expectedEpoch else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            return originalC05JobOwnerSlot
        }
        let slot = ProductionC05JobOwnerSlotV1(generationEpoch: expectedEpoch)
        originalC05JobOwnerSlot = slot
        return slot
    }

    func originalC05RunnerForErase() throws -> ResumableLocalJobRunnerV1? {
        try requireTemporalOwnerIdle()
        guard let originalC05JobOwnerSlot else { return nil }
        guard !originalC05JobOwnerSlot.isConstructing else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return originalC05JobOwnerSlot.runner
    }

    func captureOriginalC05RunnerForErase(
        operationID: UUID
    ) throws -> ResumableLocalJobRunnerV1? {
        try requireTemporalOwnerIdle()
        guard originalC05EraseCaptureID == nil,
              originalC05JobOwnerSlot?.isConstructing != true else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let originalC05JobOwnerSlot {
            guard originalC05JobOwnerSlot.generationEpoch == session.generationEpoch,
                  originalC05JobOwnerSlot.runner != nil,
                  originalC05JobOwnerSlot.workflow != nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        originalC05EraseCaptureID = operationID
        return originalC05JobOwnerSlot?.runner
    }

    func releaseOriginalC05CaptureAfterNoEffect(
        operationID: UUID
    ) throws {
        guard originalC05EraseCaptureID == operationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        originalC05EraseCaptureID = nil
    }

    func requireOriginalC05CapturedEpoch(
        operationID: UUID
    ) throws -> GenerationEpochV1 {
        guard originalC05EraseCaptureID == operationID,
              let epoch = session.generationEpoch,
              epoch.generationID == session.generationID else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        try writerLeaseHandle.requireLiveTemporalIdentity(
            mutationRegistry: writerFence.retainedTemporalRegistry)
        return epoch
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

    func requireOriginalEraseTargetInstalledUnderRetainedExclusion(
        _ allocation: GenerationWriterAllocationAttemptV1,
        session targetSession: StoreGenerationSession,
        operation: EraseRouterOperationV1,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard temporalExclusiveOwner === exclusion,
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              originalEraseRecoveryOwner == nil,
              originalRecoveryTargetTransfer == nil,
              originalErasePendingTargetWriter == nil,
              self.session === targetSession,
              writerFence.retainedTemporalRegistry === exclusion.registry,
              writerLeaseHandle === allocation.allocatedHandle else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireErasePreparationInstalled(allocation,
            operation: operation)
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

    /// Separate DEBUG route for a durable original Erase that acquired EX
    /// before pointer publication. The existing `.open` producer-close route
    /// cannot be called again. This captures only the same retained owner;
    /// Registry still proves its own selective-fence and locked lease facts.
    func captureRetainedOriginalEraseShutdownControl(
        operation: EraseRouterOperationV1,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws -> StoreOriginalEraseRetainedExclusionShutdownControlV1 {
        guard temporalExclusiveOwner === exclusion,
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              exclusion.owner === self,
              exclusion.writer === workspaceWriter,
              exclusion.retainedWriter == writerLeaseHandle.token else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let captured = try captureOriginalEraseShutdownControl(
            operation: operation)
        let (activity, physicalRoot) = try exclusion
            .requireRetainedOriginalEraseShutdownControls(
                coordinator: self, registry: captured.registry,
                writer: captured.writer)
        try physicalRoot.revalidate(
            applicationSupportURL: captured.supportURL)
        return StoreOriginalEraseRetainedExclusionShutdownControlV1(
            coordinator: self, exclusion: exclusion,
            registry: captured.registry, writer: captured.writer,
            activity: activity, physicalRoot: physicalRoot,
            supportURL: captured.supportURL,
            installed: captured.installed)
    }

    /// The Registry has already checked the same retained activity under G
    /// and captured the shutdown lease cohort. Transfer its two EX handles to
    /// the Router before breaking the Coordinator/exclusion ownership cycle.
    /// All fallible proofs precede the link changes; no descriptor is closed
    /// or producer admission reopened here.
    func detachRetainedOriginalEraseShutdownControl(
        _ control: StoreOriginalEraseRetainedExclusionShutdownControlV1,
        registryReceipt: OriginalEraseRetainedExclusionShutdownRegistryReceiptV1,
        operation: EraseRouterOperationV1
    ) throws {
        let exclusion = control.exclusion
        guard control.coordinator === self,
              temporalExclusiveOwner === exclusion,
              exclusion.owner === self,
              exclusion.writer === workspaceWriter,
              exclusion.sourceOwner == nil,
              exclusion.registry === control.registry,
              exclusion.activity === control.activity,
              exclusion.physicalRoot === control.physicalRoot,
              exclusion.retainedWriter == writerLeaseHandle.token,
              control.writer === writerLeaseHandle,
              control.supportURL == Self.applicationSupportURL(for: session),
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              registryReceipt.registry === control.registry,
              registryReceipt.activity === control.activity,
              registryReceipt.retainedWriter == control.writer.token else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let witness = try operation.requireOriginalShutdownRetainedExclusionDetachment(
            control, registryReceipt: registryReceipt)
        try registryReceipt.requireBound(
            registry: control.registry, witness: witness,
            activity: control.activity, retainedWriter: control.writer.token)
        try control.physicalRoot.revalidate(applicationSupportURL: control.supportURL)

        // This is the same terminal ownership projection used by the checked
        // Erase-retirement transfer. The Router now retains both EX handles.
        workspaceWriter.invalidate()
        temporalAdmission = .maintenance(exclusion.id)
        temporalAdmissionFailureID = nil
        temporalExclusiveOwner = nil
        exclusion.owner = nil
        exclusion.writer = nil
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

    /// The original P auxiliary observer borrows the same session's Support
    /// root in both DEBUG and production. The retained physical exclusion
    /// verifies its held/named inode around each synchronous scan.
    fileprivate var originalEraseAuxiliarySupportURL: URL {
        Self.applicationSupportURL(for: session)
    }

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
            try finishOriginalRecoveryTargetTransferIfPresent(
                operation: operation, installedSession: session)
            return
        }
        if originalRecoveryTargetTransfer == nil {
            try requireTemporalOwnerIdle()
        } else {
            try requireOriginalRecoveryTargetTransfer(
                operation: operation, targetSession: session)
        }
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
            try finishOriginalRecoveryTargetTransferIfPresent(
                operation: operation, installedSession: session)
        } catch {
            if !installationStarted { constructedWriter?.invalidate() }
            allocation.sealForRetirement()
            // After the consuming boundary, a thrown old close is ambiguous.
            // The original Coordinator and retained target attempt both survive;
            // no rollback receipt or second allocation is authorized here.
            throw error
        }
    }

    /// The original schema-2 P owner has already published its complete
    /// auxiliary pre-effect roster and retained the one actual EX/G activity.
    /// Search projection removal is deferred to a separate roster-bound
    /// auxiliary cleanup effect; this constructor and service assembly do not
    /// mutate the captured search tree.
    func activateForOriginalEraseUnderRetainedExclusion(
        session targetSession: StoreGenerationSession,
        generationFactory targetFactory: StoreGenerationFactory,
        operation: EraseRouterOperationV1
    ) throws {
#if DEBUG
        print("ORIGINAL_ACTIVATION_V1 stage=entry")
#endif
        if let installed = erasePreparationInstallation {
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=installed-reproof-enter")
#endif
            guard installed.operation === operation,
                  self.session === targetSession,
                  installed.allocation.matches(
                    registry: try targetFactory.makeGenerationLeaseRegistry()) else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            try requireErasePreparationInstalled(installed.allocation,
                operation: operation)
            try operation.recordPreparationWriterInstalled(
                installed.allocation, coordinator: self)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=installed-reproof-complete")
#endif
            return
        }
#if DEBUG
        print("ORIGINAL_ACTIVATION_V1 stage=owner-enter")
#endif
        let exclusion = try operation
            .requireOriginalErasePublishedAuxiliaryActivationOwner(
                session: targetSession, factory: targetFactory,
                coordinator: self)
#if DEBUG
        print("ORIGINAL_ACTIVATION_V1 stage=owner-complete")
#endif
        guard temporalExclusiveOwner === exclusion,
              exclusion.owner === self,
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              originalErasePendingTargetWriter == nil,
              targetSession.storeSchemaRelease
                == PersistentSchemaReleaseRegistryV1.activeRelease,
              let epoch = targetSession.generationEpoch,
              Self.applicationSupportURL(for: targetSession)
                == targetFactory.restoreApplicationSupportURL.standardizedFileURL
        else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let registry = exclusion.registry
#if DEBUG
        print("ORIGINAL_ACTIVATION_V1 stage=registry-binding-enter")
#endif
        guard try targetFactory.makeGenerationLeaseRegistry() === registry,
              writerFence.retainedTemporalRegistry === registry,
              writerLeaseHandle.token == exclusion.retainedWriter else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
#if DEBUG
        print("ORIGINAL_ACTIVATION_V1 stage=registry-binding-complete")
        print("ORIGINAL_ACTIVATION_V1 stage=root-identity-enter")
#endif
        let oldWriter = writerLeaseHandle
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(
            at: targetSession.generationRootURL)
#if DEBUG
        print("ORIGINAL_ACTIVATION_V1 stage=root-identity-complete")
        print("ORIGINAL_ACTIVATION_V1 stage=allocation-enter")
#endif
        let allocation = try registry.makeWriterAllocationAttempt(epoch: epoch)
        try operation.retainPreparationWriterAllocation(allocation,
            registry: registry, session: targetSession, coordinator: self)
        try operation.beginOriginalEraseWriterTransition(
            registry: registry, oldWriter: oldWriter,
            targetAllocation: allocation, coordinator: self)
#if DEBUG
        print("ORIGINAL_ACTIVATION_V1 stage=allocation-complete")
#endif
        do {
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=writer-lease-enter")
#endif
            let targetHandle = try allocation
                .acquireWriterForOriginalEraseUnderRetainedExclusion(
                    operation: operation, activity: exclusion.activity,
                    oldWriter: oldWriter)
            guard let writerProjection = allocation
                    .originalEraseRetainedWriterPublicationProjection else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.retainOriginalEraseWriterPublicationProjection(
                writerProjection, targetAllocation: allocation,
                targetHandle: targetHandle)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=writer-lease-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=writer-construction-enter")
#endif
            let binding = try Self.constructWriter(
                session: targetSession, clock: clock, idSource: idSource,
                fileAuthority: fileAuthority,
                generationFactory: targetFactory,
                lifecycleProfileRegistry: lifecycleProfileRegistry,
                generationEpoch: epoch, rootIdentity: rootIdentity,
                registry: registry, leaseHandle: targetHandle,
                mutationJournalFailureInjection: nil,
                diagnoseOriginalErase: true,
                originalEraseRecovery: .init(
                    activity: exclusion.activity, operation: operation,
                    targetAllocation: allocation,
                    oldWriter: oldWriter))
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=writer-construction-complete")
#endif
            originalErasePendingTargetWriter = binding.writer
            try operation.observePreparationWriter(binding.writer,
                allocation: allocation)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=writer-observed")
            print("ORIGINAL_ACTIVATION_V1 stage=search-services-enter")
#endif
            let targetSearchStore = try LocalSearchIndexStoreV1(
                applicationSupportURL: Self.applicationSupportURL(
                    for: targetSession))
            let targetSearchServices = try Self.makeSearchServices(
                session: targetSession, writer: binding.writer,
                store: targetSearchStore)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=search-services-complete")
#endif
            try operation.requirePreparationWriterConstruction(
                session: targetSession, factory: targetFactory,
                coordinator: self)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=construction-proof-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=old-close-enter")
#endif
            try operation.beginOriginalEraseSourceWriterClose(
                registry: registry, activity: exclusion.activity,
                targetAllocation: allocation)
            try registry.closeOriginalEraseSourceWriterAfterTargetPublication(
                oldWriter, targetAllocation: allocation,
                operation: operation, activity: exclusion.activity)
            guard let releaseProjection = allocation
                    .originalEraseRetainedOldWriterReleaseProjection else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.retainOriginalEraseOldWriterReleaseProjection(
                releaseProjection, targetAllocation: allocation,
                targetHandle: targetHandle)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=old-close-complete")
#endif
            try operation.beginPreparationWriterInstallation(
                allocation: allocation, coordinator: self)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=installation-enter")
#endif
            try projectOriginalErasePreparationWriterUnderRetainedExclusion(
                session: targetSession, generationFactory: targetFactory,
                allocation: allocation, targetWriter: binding.writer,
                targetFence: binding.fence,
                targetSearchStore: targetSearchStore,
                targetSearchServices: targetSearchServices,
                operation: operation, exclusion: exclusion)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=installation-complete")
#endif
            originalErasePendingTargetWriter = nil
            try operation.recordPreparationWriterInstalled(allocation,
                coordinator: self)
#if DEBUG
            print("ORIGINAL_ACTIVATION_V1 stage=operation-record-complete")
#endif
        } catch {
            // The operation, allocation, Registry and Coordinator retain the
            // exact partial owners. No ordinary allocation, writer release,
            // search drop, or EX reacquisition is attempted after a throw.
            allocation.sealForRetirement()
            throw error
        }
    }

    /// Terminal projection for a separately checked original Erase writer
    /// transition. The Registry has already published the target under this
    /// retained activity and checked-closed the old writer. No ordinary
    /// exclusion revalidation is possible while both leases are present.
    /// All fallible checks precede the synchronous association change.
    func projectOriginalErasePreparationWriterUnderRetainedExclusion(
        session targetSession: StoreGenerationSession,
        generationFactory targetFactory: StoreGenerationFactory,
        allocation: GenerationWriterAllocationAttemptV1,
        targetWriter: WorkspaceWriterV1,
        targetFence: StaleWriterFenceV1,
        targetSearchStore: LocalSearchIndexStoreV1,
        targetSearchServices: ProductionSearchServicesV1,
        operation: EraseRouterOperationV1,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        let registry = exclusion.registry
        guard temporalExclusiveOwner === exclusion,
              exclusion.owner === self,
              exclusion.writer === workspaceWriter,
              exclusion.retainedWriter == writerLeaseHandle.token,
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              exclusion.sourceOwner == nil,
              allocation.matches(registry: registry),
              let targetHandle = allocation.allocatedHandle,
              targetHandle.token == allocation.preparationPublishedToken,
              targetHandle.token.epoch == targetSession.generationEpoch,
              targetHandle.token.role == .writer,
              targetFence.retainedTemporalRegistry === registry,
              targetFactory.restoreApplicationSupportURL.standardizedFileURL
                == Self.applicationSupportURL(for: targetSession),
              generationFactory.sharesRegistryProvider(with: targetFactory),
              erasePreparationInstallation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireCompletedOriginalEraseWriterTransition(
            registry: registry, activity: exclusion.activity,
            targetAllocation: allocation)
        try exclusion.physicalRoot.revalidate(
            applicationSupportURL: Self.applicationSupportURL(for: session))
        try exclusion.requireOriginalEraseTargetWriterProjection(
            coordinator: self, registry: registry, activity: exclusion.activity,
            oldWriter: writerLeaseHandle, targetWriter: targetHandle)
        try exclusion.physicalRoot.revalidate(
            applicationSupportURL: Self.applicationSupportURL(for: session))
        let completedProjection: ColdEraseSchema2CompletedSessionEraseProjectionV1?
        if let owner = completedSessionLifetimeOwner {
            completedProjection = try owner.retainCompletedSessionEraseProjectionBeforeCoordinatorReplacement(
                coordinator: self, originalSession: self.session, originalWriter: workspaceWriter,
                originalHandle: writerLeaseHandle, originalFence: writerFence,
                targetSession: targetSession, targetWriter: targetWriter, targetHandle: targetHandle,
                targetFence: targetFence, factory: targetFactory, operation: operation,
                exclusion: exclusion, allocation: allocation)
            completedSessionEraseProjection = completedProjection // retain actual return before later throw
        } else { completedProjection = nil }
        // Arm the original source's physical close interval while its exact
        // session/context/container and old writer aliases are still owned.
        // The already completed writer publication and old lease close are
        // consumed; this does not republish or relabel either owner.
        try operation.prepareOriginalEraseSourceAliasRelease(coordinator: self)
        try operation.recordOriginalEraseWriterTransitionProjected(
            registry: registry, activity: exclusion.activity,
            targetAllocation: allocation)

        // These assignments have no throwing edge. Keep the same EX and G
        // activity, projecting only the operation's checked target pair.
        workspaceWriter.invalidate()
        self.session = targetSession
        generationFactory = targetFactory
        searchIndexStore = targetSearchStore
        searchServices = targetSearchServices
        writerLeaseHandle = targetHandle
        writerFence = targetFence
        workspaceWriter = targetWriter
        erasePreparationInstallation = ErasePreparationInstallation(
            operation: operation, allocation: allocation)
        completedProjection?.recordActualCoordinatorReplacement(coordinator: self,
            session: targetSession, writer: targetWriter, writerHandle: targetHandle, fence: targetFence)
        exclusion.recordOriginalEraseTargetWriterProjection(
            targetWriter: targetHandle, constructedWriter: targetWriter)
        registerTemporalOwner()
        if uiGenerationToken < .max { uiGenerationToken += 1 }
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

    private struct OriginalEraseWriterRecoveryOwner {
        let activity: GenerationTemporalActivityHandleV1
        let operation: EraseRouterOperationV1
        let targetAllocation: GenerationWriterAllocationAttemptV1
        let oldWriter: GenerationLeaseHandleV1
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
        mutationJournalFailureInjection: MutationJournalFailureInjectionV1?,
        diagnoseOriginalErase: Bool = false,
        originalEraseRecovery: OriginalEraseWriterRecoveryOwner? = nil,
        completedSchema2StartupOwner: ColdEraseSchema2CompletedStartupOwnerV1? = nil
    ) throws -> WriterBinding {
        let writerLeaseToken = leaseHandle.token
#if DEBUG
        if diagnoseOriginalErase {
            print("ORIGINAL_ACTIVATION_V1 stage=fence-enter")
        }
#endif
        let staleWriterFence: StaleWriterFenceV1
        if let owner = completedSchema2StartupOwner {
            staleWriterFence = try generationFactory.makeWriterFenceForSchema2ColdCompletedStartup(
                expectedGenerationEpoch: generationEpoch, writerLeaseToken: writerLeaseToken,
                registry: registry, owner: owner)
        } else {
            staleWriterFence = try generationFactory.makeWriterFence(
                expectedGenerationEpoch: generationEpoch,
                writerLeaseToken: writerLeaseToken,
                registry: registry
            )
        }
#if DEBUG
        if diagnoseOriginalErase {
            print("ORIGINAL_ACTIVATION_V1 stage=fence-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=journal-store-enter")
        }
#endif
        let journalStore = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            failureInjection: mutationJournalFailureInjection,
            allowStateBootstrap: false,
            staleWriterFence: staleWriterFence
        )
#if DEBUG
        if diagnoseOriginalErase {
            print("ORIGINAL_ACTIVATION_V1 stage=journal-store-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=journal-recovery-enter")
        }
#endif
        let recovery = MutationReceiptRecoveryServiceV1(store: journalStore)
        if let owner = originalEraseRecovery {
#if DEBUG
            var selectedProbe:
                (kind: OriginalEraseJournalRecoveryProbeV1,
                 report: @MainActor (OriginalEraseJournalRecoveryProbeResultV1) -> Void)?
            if let candidate = Self.originalEraseJournalRecoveryProbeForTesting,
               candidate.operation === owner.operation,
               candidate.applicationSupportURL.standardizedFileURL
                    == Self.applicationSupportURL(for: session).standardizedFileURL {
                selectedProbe = (candidate.kind, candidate.report)
                Self.originalEraseJournalRecoveryProbeForTesting = nil
            }
            if let selectedProbe {
                switch selectedProbe.kind {
                case .foreignFence:
                    let foreign = try generationFactory.makeWriterFence(
                        expectedGenerationEpoch: owner.oldWriter.token.epoch,
                        writerLeaseToken: owner.oldWriter.token,
                        registry: registry)
                    var bodyEntered = false
                    var accepted = false
                    do {
                        _ = try foreign.withAuthorizedOriginalEraseWriterRecovery(
                            activity: owner.activity, operation: owner.operation,
                            targetAllocation: owner.targetAllocation,
                            targetHandle: leaseHandle) {
                            bodyEntered = true
                        }
                        accepted = true
                    } catch {
                        selectedProbe.report(!bodyEntered
                            && (error as? GenerationLeaseRegistryFailureV1) == .uncertainOwner
                            ? .rejectedBeforeBody : .unexpected)
                    }
                    if accepted {
                        selectedProbe.report(.unexpected)
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                case .wrongAllocation:
                    let foreign = try registry.makeWriterAllocationAttempt(
                        epoch: generationEpoch)
                    defer { foreign.sealForRetirement() }
                    var accepted = false
                    do {
                        try owner.operation.beginOriginalEraseWriterRecovery(
                            registry: registry, activity: owner.activity,
                            targetAllocation: foreign, targetHandle: leaseHandle)
                        accepted = true
                    } catch {
                        selectedProbe.report((error as? GenerationLeaseRegistryFailureV1)
                            == .uncertainOwner ? .rejectedBeforeBody : .unexpected)
                    }
                    if accepted {
                        selectedProbe.report(.unexpected)
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                case .completedReuse, .failInsideCheckedScope:
                    break
                }
            }
#endif
            try owner.operation.beginOriginalEraseWriterRecovery(
                registry: registry, activity: owner.activity,
                targetAllocation: owner.targetAllocation,
                targetHandle: leaseHandle)
            do {
#if DEBUG
                if let selectedProbe,
                   selectedProbe.kind == .failInsideCheckedScope {
                    do {
                        _ = try staleWriterFence
                            .withAuthorizedOriginalEraseWriterRecovery(
                                activity: owner.activity, operation: owner.operation,
                                targetAllocation: owner.targetAllocation,
                                targetHandle: leaseHandle) {
                                throw OriginalEraseJournalRecoveryProbeFailureV1.injected
                            }
                        selectedProbe.report(.unexpected)
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    } catch OriginalEraseJournalRecoveryProbeFailureV1.injected {
                        let blocked = (try? owner.operation
                            .beginOriginalEraseSourceWriterClose(
                                registry: registry, activity: owner.activity,
                                targetAllocation: owner.targetAllocation)) == nil
                        selectedProbe.report(blocked
                            ? .failedScopeBlockedOldClose : .unexpected)
                        throw OriginalEraseJournalRecoveryProbeFailureV1.injected
                    }
                }
#endif
                let receipt = try recovery
                    .recoverBeforeOriginalEraseTargetWriterActivation(
                    activity: owner.activity, operation: owner.operation,
                    targetAllocation: owner.targetAllocation,
                    targetHandle: leaseHandle)
                try owner.operation.finishOriginalEraseWriterRecovery(
                    receipt, registry: registry, activity: owner.activity,
                    targetAllocation: owner.targetAllocation,
                    targetHandle: leaseHandle)
#if DEBUG
                if let selectedProbe,
                   selectedProbe.kind == .completedReuse {
                    var accepted = false
                    do {
                        try owner.operation.beginOriginalEraseWriterRecovery(
                            registry: registry, activity: owner.activity,
                            targetAllocation: owner.targetAllocation,
                            targetHandle: leaseHandle)
                        accepted = true
                    } catch {
                        selectedProbe.report((error as? GenerationLeaseRegistryFailureV1)
                            == .uncertainOwner
                            ? .rejectedCompletedReuse : .unexpected)
                    }
                    if accepted {
                        selectedProbe.report(.unexpected)
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                }
#endif
            } catch {
                owner.operation.failOriginalEraseWriterRecovery()
                throw error
            }
        } else {
            try recovery.recoverBeforeWriterActivation()
        }
#if DEBUG
        if diagnoseOriginalErase {
            print("ORIGINAL_ACTIVATION_V1 stage=journal-recovery-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=revision-enter")
        }
#endif
        let revision = try WorkspaceRevisionV1(
            workspaceID: session.workspaceID,
            generationID: session.generationID,
            revision: 0,
            entityRevisions: []
        )
#if DEBUG
        if diagnoseOriginalErase {
            print("ORIGINAL_ACTIVATION_V1 stage=revision-complete")
            print("ORIGINAL_ACTIVATION_V1 stage=writer-object-enter")
        }
#endif
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
#if DEBUG
        if diagnoseOriginalErase {
            print("ORIGINAL_ACTIVATION_V1 stage=writer-object-complete")
        }
#endif
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

    /// The post-Erase typed allocation shares the sole real writer/fence
    /// constructor. It never borrows an Original/retirement writer handle.
    static func makeForSchema2ColdCompletedStartup(session: StoreGenerationSession,
        generationFactory: StoreGenerationFactory, owner: ColdEraseSchema2CompletedStartupOwnerV1,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1(),
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1) throws -> StoreSessionCoordinator {
        try owner.requireWriterConstruction(session: session, factory: generationFactory)
        guard session.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              let epoch = session.generationEpoch else { throw GenerationLeaseRegistryFailureV1.staleGeneration }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let registry = try generationFactory.makeGenerationLeaseRegistry()
        let searchIndexStore = try LocalSearchIndexStoreV1(applicationSupportURL: generationFactory.restoreApplicationSupportURL)
        let allocation = try registry.makeWriterAllocationAttempt(epoch: epoch)
        try owner.retainWriterAllocation(allocation)
        var constructedWriter: WorkspaceWriterV1?
        do {
            let handle = try allocation.acquireWriterForSchema2ColdCompletedStartup(owner: owner)
            let binding = try constructWriter(session: session, clock: clock, idSource: idSource,
                fileAuthority: fileAuthority, generationFactory: generationFactory,
                lifecycleProfileRegistry: lifecycleProfileRegistry, generationEpoch: epoch,
                rootIdentity: rootIdentity, registry: registry, leaseHandle: handle,
                mutationJournalFailureInjection: nil, completedSchema2StartupOwner: owner)
            constructedWriter = binding.writer
            try owner.observeConstructedWriter(binding.writer)
            let searchServices = try makeSearchServices(session: session, writer: binding.writer, store: searchIndexStore)
            try owner.requireWriterConstruction(session: session, factory: generationFactory)
            return StoreSessionCoordinator(session: session, clock: clock, idSource: idSource,
                fileAuthority: fileAuthority, generationFactory: generationFactory,
                lifecycleProfileRegistry: lifecycleProfileRegistry, binding: binding,
                searchIndexStore: searchIndexStore, searchServices: searchServices)
        } catch {
            constructedWriter?.invalidate()
            allocation.sealForRetirement()
            throw error // exact typed attempt remains with the actual Router owner
        }
    }

    func transferCompletedSchema2StartupFenceLifecycle(owner: ColdEraseSchema2CompletedStartupOwnerV1,
        receiver: ColdEraseSchema2CompletedStartupPublicationReceiverV1) throws {
        try owner.requireCompletedStartupLeaseOwnershipConsumed(registry: writerFence.retainedTemporalRegistry)
        try receiver.requireTransferredRegistry(registry: writerFence.retainedTemporalRegistry, owner: owner)
        try writerFence.transferCompletedStartupPublishedLifecycle(owner: owner, receiver: receiver)
    }

    /// Pure actual-object association. Live recovery still enters the same
    /// writer fence through its existing authorized mutation/read engine.
    func requireCompletedSchema2StartupAssociation(session expectedSession: StoreGenerationSession,
        writer expectedWriter: WorkspaceWriterV1, writerHandle expectedHandle: GenerationLeaseHandleV1,
        registry: GenerationLeaseRegistryV1, factory: StoreGenerationFactory) throws {
        guard session === expectedSession, workspaceWriter === expectedWriter,
              writerLeaseHandle === expectedHandle,
              generationFactory.sharesRegistryProvider(with: factory),
              writerFence.retainedTemporalRegistry === registry,
              writerFence.writerLeaseToken == expectedHandle.token,
              writerFence.expectedGenerationEpoch == expectedSession.generationEpoch,
              expectedHandle.token.role == .writer,
              expectedHandle.token.epoch == expectedSession.generationEpoch,
              expectedHandle.token.ownerID == registry.ownerID,
              generationID == expectedSession.generationID,
              workspaceIdentity == expectedSession.workspaceIdentity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expectedHandle.requireExactRegistry(registry)
    }

    /// Restore creates B through its actual opening provider after A's writer
    /// has durably closed. The Router owns the allocation before publication;
    /// a thrown constructor leaves the attempt and original B session pinned.
    static func makeForOriginalRestoreTransition(
        owner: RestoreWriterTransitionOwnerV1,
        lifecycleProfileRegistry: WorkspacePackageLifecycleProfileRegistryV1?,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1()
    ) throws -> StoreSessionCoordinator {
        let session = owner.targetSession
        let factory = owner.targetFactory
        let resolvedLifecycleProfileRegistry = try lifecycleProfileRegistry
            ?? WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        guard session.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              let epoch = session.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(
            at: session.generationRootURL)
        let registry = owner.registry
        let allocation = try registry.makeWriterAllocationAttempt(epoch: epoch)
        try owner.retainAllocation(allocation)
        var constructedWriter: WorkspaceWriterV1?
        do {
            let handle = try allocation.acquireWriterForRestoreTransition(owner: owner)
            let binding = try constructWriter(session: session, clock: clock,
                idSource: idSource, fileAuthority: fileAuthority,
                generationFactory: factory,
                lifecycleProfileRegistry: resolvedLifecycleProfileRegistry,
                generationEpoch: epoch, rootIdentity: rootIdentity,
                registry: registry, leaseHandle: handle,
                mutationJournalFailureInjection: nil)
            constructedWriter = binding.writer
            try owner.observeConstructedWriter(binding.writer)
            let store = try LocalSearchIndexStoreV1(
                applicationSupportURL: factory.restoreApplicationSupportURL)
            let search = try makeSearchServices(
                session: session, writer: binding.writer, store: store)
            let coordinator = StoreSessionCoordinator(session: session,
                clock: clock, idSource: idSource, fileAuthority: fileAuthority,
                generationFactory: factory,
                lifecycleProfileRegistry: resolvedLifecycleProfileRegistry,
                binding: binding, searchIndexStore: store,
                searchServices: search)
            try owner.requireConstructed(coordinator)
            return coordinator
        } catch {
            constructedWriter?.invalidate()
            owner.sealFailure()
            // The attempt remains with Router. The caller may dispose it only
            // after the throwing frame and all weak construction aliases drain.
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
    /// Path data for the checked Search writer. Its authority comes only from
    /// the operation-retained EX/G and the scoped held Support descriptor.
    var originalEraseAuxiliarySearchSupportURL: URL {
        originalEraseAuxiliarySupportURL
    }

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
    private(set) var retainedWriter: GenerationLeaseTokenV1
    fileprivate var writer: WorkspaceWriterV1?
    fileprivate let activity: GenerationTemporalActivityHandleV1
    fileprivate let physicalRoot: StoreTemporalPhysicalRootExclusionV1
    fileprivate var sourceOwner: TemporalNormalizationSourceOwnerV1?
    private var originalEraseWriterTransitionProjected = false

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

    func requireOriginalEraseAuxiliaryPhaseActivity(
        registry expectedRegistry: GenerationLeaseRegistryV1,
        coordinator: StoreSessionCoordinator,
        writer expectedWriter: GenerationLeaseTokenV1
    ) throws -> GenerationTemporalActivityHandleV1 {
        guard owner === coordinator,
              registry === expectedRegistry,
              retainedWriter == expectedWriter else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try revalidate()
        return activity
    }

    func matchesOriginalEraseAuxiliaryPhase(
        registry expectedRegistry: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1,
        writer expectedWriter: GenerationLeaseTokenV1
    ) -> Bool {
        owner != nil && registry === expectedRegistry
            && activity === expectedActivity
            && retainedWriter == expectedWriter
    }

    /// Pure SAME retained EX DATA. The caller separately proves its actual
    /// original-Erase projection; this accessor does not reenter G, perform
    /// an ordinary writer census, acquire a handle or authorize IO.
    /// Identity-only association for the narrowly closed physical transition.
    /// The actual root's checked revalidation remains a separate owner proof.
    var physicalRootForOriginalEraseTransition: StoreTemporalPhysicalRootExclusionV1 { physicalRoot }

    func requireRetainedCurrentOriginalEraseActivity(
        coordinator: StoreSessionCoordinator,
        registry expectedRegistry: GenerationLeaseRegistryV1
    ) throws -> GenerationTemporalActivityHandleV1 {
        guard owner === coordinator, registry === expectedRegistry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return activity
    }

    /// Pure identity check for a Registry caller that already holds G. It
    /// deliberately does not invoke `revalidate`, whose ordinary writer
    /// census is invalid during this one operation's two-writer cut.
    func matchesOriginalEraseWriterTransition(
        registry expectedRegistry: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1,
        oldWriter: GenerationLeaseHandleV1
    ) -> Bool {
        owner != nil && registry === expectedRegistry && activity === expectedActivity
            && retainedWriter == oldWriter.token && !originalEraseWriterTransitionProjected
    }

    /// Outside G only. Router captures this *actual* retained activity before
    /// any target writer effect; the Registry later compares the full locked
    /// cohort without reopening or replacing the EX handle.
    func requireOriginalEraseWriterTransitionActivity(
        registry expectedRegistry: GenerationLeaseRegistryV1,
        oldWriter: GenerationLeaseHandleV1,
        coordinator: StoreSessionCoordinator
    ) throws -> GenerationTemporalActivityHandleV1 {
        guard owner === coordinator,
              matchesOriginalEraseWriterTransition(registry: expectedRegistry,
                  activity: activity, oldWriter: oldWriter),
              sourceOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try revalidate()
        return activity
    }

#if DEBUG
    /// The original Erase already owns these exact EX handles. The checked
    /// interrupted-shutdown path borrows their identities; it never acquires
    /// another Registry activity or Support root lock.
    fileprivate func requireRetainedOriginalEraseShutdownControls(
        coordinator: StoreSessionCoordinator,
        registry expectedRegistry: GenerationLeaseRegistryV1,
        writer expectedWriter: GenerationLeaseHandleV1
    ) throws -> (GenerationTemporalActivityHandleV1,
                 StoreTemporalPhysicalRootExclusionV1) {
        guard owner === coordinator, sourceOwner == nil,
              registry === expectedRegistry,
              retainedWriter == expectedWriter.token,
              writer === coordinator.workspaceWriter else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try revalidate()
        return (activity, physicalRoot)
    }
#endif

    /// Proof only. The Coordinator commits its complete target association
    /// and this exclusion's writer projection together after this returns.
    fileprivate func requireOriginalEraseTargetWriterProjection(
        coordinator: StoreSessionCoordinator,
        registry expectedRegistry: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1,
        oldWriter: GenerationLeaseHandleV1,
        targetWriter: GenerationLeaseHandleV1
    ) throws {
        guard owner === coordinator, sourceOwner == nil,
              matchesOriginalEraseWriterTransition(registry: expectedRegistry,
                  activity: expectedActivity, oldWriter: oldWriter),
              !originalEraseWriterTransitionProjected,
              targetWriter.token.role == .writer,
              targetWriter.token.ownerID == oldWriter.token.ownerID,
              targetWriter.token != oldWriter.token else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try oldWriter.requireClosedForOriginalEraseWriterTransition(registry: expectedRegistry)
        try targetWriter.requireLiveTemporalIdentity(mutationRegistry: expectedRegistry)
        try registry.validateTemporalNormalizationActivity(activity,
            retainedWriter: targetWriter.token)
    }

    fileprivate func recordOriginalEraseTargetWriterProjection(
        targetWriter: GenerationLeaseHandleV1,
        constructedWriter: WorkspaceWriterV1
    ) {
        retainedWriter = targetWriter.token
        writer = constructedWriter
        originalEraseWriterTransitionProjected = true
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

#if DEBUG
/// Private original-owner receipt for a shutdown that reuses the already-held
/// EX. It is data/identity only; Registry must still install the selective
/// closing fence and reprove the complete locked lease census.
@MainActor
final class StoreOriginalEraseRetainedExclusionShutdownControlV1 {
    let coordinator: StoreSessionCoordinator
    let exclusion: StoreTemporalNormalizationExclusionV1
    let registry: GenerationLeaseRegistryV1
    let writer: GenerationLeaseHandleV1
    let activity: GenerationTemporalActivityHandleV1
    let physicalRoot: StoreTemporalPhysicalRootExclusionV1
    let supportURL: URL
    let installed: Bool

    fileprivate init(coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        registry: GenerationLeaseRegistryV1,
        writer: GenerationLeaseHandleV1,
        activity: GenerationTemporalActivityHandleV1,
        physicalRoot: StoreTemporalPhysicalRootExclusionV1,
        supportURL: URL, installed: Bool) {
        self.coordinator = coordinator; self.exclusion = exclusion
        self.registry = registry; self.writer = writer
        self.activity = activity; self.physicalRoot = physicalRoot
        self.supportURL = supportURL; self.installed = installed
    }
}
#endif

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

#if DEBUG
struct OriginalRecoveryProjectionEntryObservationForTestingV1: Equatable {
    let operationPresent: Bool
    let ownerPresent: Bool
    let operationDetached: Bool?
    let ownerUncertain: Bool?
    let failed: Bool
    let firstComparisonEntries: Int
    let observerEntries: Int
    let continuationEntries: Int
    let sourceStoreEntries: Int
    let borrowedSupportBodyEntries: Int
    let bodyEntries: Int
}
#endif

/// Carries the final checked-close first-image projection across the Q
/// continuation. It never grants a new effect or a fresh baseline.
@MainActor
final class OriginalRecoveryPostPointerAuxiliaryProjectionV1 {
    private weak var operation: EraseRouterOperationV1?
    private weak var owner: StoreOriginalEraseRecoveryPreOpenOwnerV1?
    private let observer: EraseSchema2ColdAuxiliaryFirstObserverV1
    private let first: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    private let projected: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    private var failed = false
#if DEBUG
    private var originalFirstComparisonEntriesForTesting = 0
    private var projectedObserverEntriesForTesting = 0
    private var continuationEntriesForTesting = 0
    private var sourceStoreEntriesForTesting = 0
    private var borrowedSupportBodyEntriesForTesting = 0
    private var bodyEntriesForTesting = 0

    enum WrapperEntryForTesting { case continuation, sourceStore, borrowedSupportBody, body }

    fileprivate func recordWrapperEntryForTesting(_ entry: WrapperEntryForTesting) {
        switch entry {
        case .continuation: continuationEntriesForTesting += 1
        case .sourceStore: sourceStoreEntriesForTesting += 1
        case .borrowedSupportBody: borrowedSupportBodyEntriesForTesting += 1
        case .body: bodyEntriesForTesting += 1
        }
    }

    func entryObservationForTesting() -> OriginalRecoveryProjectionEntryObservationForTestingV1 {
        OriginalRecoveryProjectionEntryObservationForTestingV1(
            operationPresent: operation != nil, ownerPresent: owner != nil,
            operationDetached: operation?.detached,
            ownerUncertain: owner.map { $0.state == .uncertain }, failed: failed,
            firstComparisonEntries: originalFirstComparisonEntriesForTesting,
            observerEntries: projectedObserverEntriesForTesting,
            continuationEntries: continuationEntriesForTesting,
            sourceStoreEntries: sourceStoreEntriesForTesting,
            borrowedSupportBodyEntries: borrowedSupportBodyEntriesForTesting,
            bodyEntries: bodyEntriesForTesting)
    }
#endif

    fileprivate init(operation: EraseRouterOperationV1,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        first: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        projected: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot) {
        self.operation = operation
        self.owner = owner
        self.observer = observer
        self.first = first
        self.projected = projected
    }

    /// This receipt can be consumed for a reader only if the recovery
    /// observer's first image is exactly the immutable original P image.
    /// Earlier Operations mutations require their own typed projection.
    /// Association admission is pure: foreign, expired and detached callbacks
    /// refuse before source/FD access or either owner's uncertainty mutation.
    func requireUndetachedAssociation(
        operation expectedOperation: EraseRouterOperationV1?,
        owner expectedOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1?
    ) throws {
        guard let actualOperation = operation, let actualOwner = owner,
              let expectedOperation, let expectedOwner,
              actualOperation === expectedOperation,
              actualOwner === expectedOwner,
              !actualOperation.detached, !expectedOperation.detached else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try actualOwner.requireUndetachedOriginalRecoveryOperation(expectedOperation)
    }

    func requireOriginalPFirst(
        _ expected: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        operation expectedOperation: EraseRouterOperationV1,
        owner expectedOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws {
        try requireUndetachedAssociation(operation: expectedOperation,
            owner: expectedOwner)
#if DEBUG
        originalFirstComparisonEntriesForTesting += 1
#endif
        guard !failed, first == expected else {
            failed = true
            expectedOwner.poisonOnUncertainScratch()
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requireReaderStartingImage(
        originalP: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        operation expectedOperation: EraseRouterOperationV1,
        owner expectedOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        support: Int32
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        try requireOriginalPFirst(originalP, operation: expectedOperation,
            owner: expectedOwner)
        try requireProjected(operation: expectedOperation,
            owner: expectedOwner, support: support)
        return projected
    }

    func requireProjected(operation expectedOperation: EraseRouterOperationV1,
        owner expectedOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        support: Int32) throws {
        try requireUndetachedAssociation(operation: expectedOperation,
            owner: expectedOwner)
        guard !failed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
#if DEBUG
            projectedObserverEntriesForTesting += 1
#endif
            try observer.requirePostPointerOperationsProjected(
                first: first, projected: projected, support: support)
        } catch {
            failed = true
            expectedOwner.poisonOnUncertainScratch()
            throw error
        }
    }
}

/// Keeps the original operation's first auxiliary image through the admission
/// await. Parent descriptors and the observer are retained before any scan;
/// only checked ScratchData lease receipts may project that first image.
/// Neither a later survivor scan nor this data owner grants effect authority.
@MainActor
final class StoreOriginalEraseRecoveryAuxiliaryContinuityV1 {
    private struct Parent {
        let descriptor: Int32
        let path: URL?
        let first: stat?
    }

    private weak var operation: EraseRouterOperationV1?
    private weak var coordinator: StoreSessionCoordinator?
    private let supportURL: URL
    private let cachesURL: URL
    private let temporaryURL: URL
    private let observer = EraseSchema2ColdAuxiliaryFirstObserverV1()
    private var support: Parent?
    private var caches: Parent?
    private var temporary: Parent?
    private var first: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var receipts:
        [ScratchDataLeaseStoreV1.OriginalEraseExclusiveSourceReadReceiptV1] = []
    private var captureAttempted = false
    private var captureInFlight = false
    private var reproofFailed = false
    private var closeAttempted = false
    private var closed = false
    private var uncertainDescriptors: [Int32] = []

    init(operation: EraseRouterOperationV1,
         coordinator: StoreSessionCoordinator,
         supportURL: URL, cachesURL: URL, temporaryURL: URL) throws {
        guard supportURL.isFileURL, cachesURL.isFileURL,
              temporaryURL.isFileURL else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        self.operation = operation
        self.coordinator = coordinator
        self.supportURL = supportURL.standardizedFileURL
        self.cachesURL = cachesURL.standardizedFileURL
        self.temporaryURL = temporaryURL.standardizedFileURL
    }

    private func requireOperation(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws -> EraseRouterOperationV1 {
        guard let operation, let coordinator,
              !closed, !closeAttempted, !reproofFailed,
              uncertainDescriptors.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireOriginalRecoveryAuxiliaryContinuity(
            self, owner: owner, coordinator: coordinator)
        return operation
    }

    func captureFirst(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        _ = try requireOperation(owner)
        guard let intent = owner.observation?.intent,
              let preparation = owner.observation?.preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard !captureAttempted, !captureInFlight,
              first == nil, support == nil, caches == nil,
              temporary == nil,
              intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared,
              preparation.matches(intent) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        captureAttempted = true
        captureInFlight = true
        let value = try owner.withExclusiveSourceScratch { _ in
            try owner.withCheckedSupportInsideOriginalRecoveryG { borrowed, _ in
                support = try openSupport(borrowed)
                caches = try openParent(cachesURL) { self.caches = $0 }
                temporary = try openParent(temporaryURL) {
                    self.temporary = $0
                }
                try requireParents(borrowedSupport: borrowed)
                guard let support, let caches, let temporary else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                let observed = try observer.captureFirst(
                    support: support.descriptor,
                    caches: caches.descriptor,
                    temporary: temporary.descriptor,
                    applicationSupportURL: supportURL, retainingOriginalScratchImage: true)
                try requireParents(borrowedSupport: borrowed)
                return observed
            }
        }
        first = value
        captureInFlight = false
        _ = try requireOperation(owner)
        try owner.bindOriginalScratchContinuity(self)
        return value
    }

    /// Original DATA only. Rechecks the strong operation association and the
    /// real owner's held G, then the complete current first/prior projection.
    func originalScratchImageInsideOriginalRecoveryG(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws -> ScratchDataLeaseStoreV1.OriginalEraseScratchImageV1 {
        _ = try requireOperation(owner)
        try owner.requireHeldInsideOriginalRecoveryG()
        _ = try requireProjectedInsideOriginalRecoveryG(owner: owner)
        let image = try receipts.last?.afterScratchImage ?? observer.originalScratchFirstImage()
        _ = try requireOperation(owner)
        try owner.requireHeldInsideOriginalRecoveryG()
        return image
    }

    /// The checked Store callback is nonthrowing. Any mismatched receipt is
    /// retained but seals this owner as failed; later reproof cannot resume.
    func retainScratchSettlement(
        _ receipt: ScratchDataLeaseStoreV1
            .OriginalEraseExclusiveSourceReadReceiptV1,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) {
        receipts.append(receipt)
        do {
            _ = try requireOperation(owner)
            try owner.requireHeldInsideOriginalRecoveryG()
            try receipt.requireCheckedSettlement()
            guard let operation, let first,
                  captureAttempted, !captureInFlight,
                  !closeAttempted, !closed, !reproofFailed,
                  receipt.ownerOperationID ==
                    operation.originalRecoveryPrivateCopyOperationID,
                  receipts.filter({ $0.leaseID == receipt.leaseID }).count == 1,
                  receipts.filter({ $0.leaseName == receipt.leaseName }).count == 1,
                  case .present(let operationsFact, _) = first.operations,
                  receipt.operationsFact == operationsFact,
                  receipt.operationsNames ==
                    first.operationsChildren.keys.sorted(),
                  let scratch = first.operationsChildren["ScratchDataV1"],
                  case .directory(let firstFact, let firstDigest) = scratch else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            if receipts.count == 1 {
                guard receipt.beforeScratchRootFact == firstFact,
                      receipt.beforeScratchDigest == firstDigest,
                      receipt.beforeScratchImage == (try observer.originalScratchFirstImage()) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            } else {
                let prior = receipts[receipts.count - 2]
                guard receipt.beforeScratchRootFact ==
                        prior.afterScratchRootFact,
                      receipt.beforeScratchDigest ==
                        prior.afterScratchDigest,
                      receipt.beforeScratchImage == prior.afterScratchImage else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
        } catch {
            reproofFailed = true
        }
    }

    func requireProjected(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        try owner.withExclusiveSourceScratch { _ in
            let value = try requireProjectedInsideOriginalRecoveryG(owner: owner)
            // Service may replace the pre-open owner after its real admission
            // await. Bind only after this same retained first/prior image and
            // the operation's current owner have passed actual EX/G reproof.
            try owner.bindOriginalScratchContinuity(self)
            return value
        }
    }

    /// Called only from the enclosing owner's already-held Registry G.
    /// The owner proves G and Support EX without recursively acquiring G.
    func requireProjectedInsideOriginalRecoveryG(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        _ = try requireOperation(owner)
        guard captureAttempted, !captureInFlight,
              let first, support != nil, caches != nil,
              temporary != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            let observed = try owner.withCheckedSupportInsideOriginalRecoveryG {
                    borrowed, _ in
                    try requireParents(borrowedSupport: borrowed)
                    guard let support, let caches, let temporary else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    let value: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
                    if receipts.isEmpty {
                        try observer.requireUnchanged(
                            support: support.descriptor,
                            caches: caches.descriptor,
                            temporary: temporary.descriptor)
                        value = try observer.firstObservation()
                    } else {
                        value = try observer.requireScratchProjected(
                            receipts, support: support.descriptor,
                            caches: caches.descriptor,
                            temporary: temporary.descriptor)
                    }
                    try requireParents(borrowedSupport: borrowed)
                    return value
            }
            guard try observer.firstObservation() == first else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return observed
        } catch {
            reproofFailed = true
            throw error
        }
    }

    func closeCheckedAfterFirstPointerPhase(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) throws -> OriginalRecoveryPostPointerAuxiliaryProjectionV1 {
        let operation = try requireOperation(owner)
        guard owner.publishedIntentForTargetTransfer?.phase == .pointerSwitched,
              captureAttempted, !captureInFlight,
              !closeAttempted, !closed, !reproofFailed,
              uncertainDescriptors.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // The Store's checked P→Q receipt permits only the Erase control
        // postimage and proves Support's full Fact and names unchanged. The
        // auxiliary observer excludes Erase itself, so rewalk every first
        // noncontrol child and the exact ScratchData receipt projection now,
        // before any held parent descriptor can be released.
        try owner.requireObservationUnchanged()
        let projected = try requireProjected(owner: owner)
        guard let first else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireNamedParentsAfterPointerPhase()
        closeAttempted = true
        for descriptor in [temporary?.descriptor, caches?.descriptor,
                           support?.descriptor].compactMap({ $0 }) {
            guard Darwin.close(descriptor) == 0 else {
                uncertainDescriptors.append(descriptor)
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        temporary = nil; caches = nil; support = nil
        closed = true
        return OriginalRecoveryPostPointerAuxiliaryProjectionV1(
            operation: operation, owner: owner, observer: observer,
            first: first, projected: projected)
    }

    var isCheckedClosed: Bool {
        closed && closeAttempted && uncertainDescriptors.isEmpty &&
            support == nil && caches == nil && temporary == nil
    }

    private func openSupport(_ borrowed: Int32) throws -> Parent {
        let descriptor = Darwin.openat(borrowed, ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let pending = Parent(descriptor: descriptor, path: supportURL,
            first: nil)
        support = pending
        var borrowedFact = stat(), held = stat(), named = stat()
        guard Darwin.fstat(borrowed, &borrowedFact) == 0,
              Darwin.fstat(descriptor, &held) == 0,
              Darwin.lstat(supportURL.path, &named) == 0,
              Self.sameFullFact(borrowedFact, held),
              Self.sameFullFact(held, named),
              held.st_mode & S_IFMT == S_IFDIR else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let result = Parent(descriptor: descriptor, path: supportURL,
            first: held)
        support = result
        return result
    }

    private func openParent(
        _ path: URL, retain: (Parent) -> Void
    ) throws -> Parent {
        let descriptor = Darwin.open(path.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        retain(Parent(descriptor: descriptor, path: path, first: nil))
        var held = stat(), named = stat()
        guard Darwin.fstat(descriptor, &held) == 0,
              Darwin.lstat(path.path, &named) == 0,
              Self.sameFullFact(held, named),
              held.st_mode & S_IFMT == S_IFDIR,
              held.st_nlink > 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let result = Parent(descriptor: descriptor, path: path,
            first: held)
        retain(result)
        return result
    }

    private func requireParents(borrowedSupport: Int32) throws {
        guard let support, let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        for parent in [support, caches, temporary] {
            guard let path = parent.path, let first = parent.first else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var held = stat(), named = stat()
            guard Darwin.fstat(parent.descriptor, &held) == 0,
                  Darwin.lstat(path.path, &named) == 0,
                  Self.sameFullFact(held, named),
                  held.st_dev == first.st_dev,
                  held.st_ino == first.st_ino,
                  held.st_mode == first.st_mode,
                  held.st_uid == first.st_uid,
                  held.st_gid == first.st_gid,
                  held.st_mode & S_IFMT == S_IFDIR else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        var borrowed = stat(), retained = stat()
        guard Darwin.fstat(borrowedSupport, &borrowed) == 0,
              Darwin.fstat(support.descriptor, &retained) == 0,
              Self.sameFullFact(borrowed, retained) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private func requireNamedParentsAfterPointerPhase() throws {
        guard let support, let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        for parent in [support, caches, temporary] {
            guard let path = parent.path, let first = parent.first else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var held = stat(), named = stat()
            guard Darwin.fstat(parent.descriptor, &held) == 0,
                  Darwin.lstat(path.path, &named) == 0,
                  Self.sameFullFact(held, named),
                  held.st_dev == first.st_dev,
                  held.st_ino == first.st_ino,
                  held.st_mode == first.st_mode,
                  held.st_uid == first.st_uid,
                  held.st_gid == first.st_gid,
                  held.st_mode & S_IFMT == S_IFDIR else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
    }

    private static func sameFullFact(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino &&
            a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
            a.st_gid == b.st_gid && a.st_nlink == b.st_nlink &&
            a.st_size == b.st_size &&
            a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
            a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
            a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec &&
            a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}

/// A read-only original-Erase recovery exclusion. This is deliberately not a
/// normalization owner: it cannot invalidate the ready writer, publish an
/// Erase effect, or stand in for the later private source validation.
@MainActor
final class StoreOriginalEraseRecoveryPreOpenOwnerV1 {
    private weak var coordinator: StoreSessionCoordinator?
    private weak var operation: EraseRouterOperationV1?
    fileprivate let id: UUID
    let source: StoreGenerationSession
    fileprivate let writer: WorkspaceWriterV1
    fileprivate let writerToken: GenerationLeaseTokenV1
    fileprivate let registry: GenerationLeaseRegistryV1
    fileprivate let supportURL: URL
    fileprivate var acquisition: GenerationOriginalEraseRecoveryActivityAcquisitionV1?
    fileprivate var activity: GenerationTemporalActivityHandleV1?
    fileprivate var root: StoreTemporalPhysicalRootExclusionV1?
    let retainedOriginalExclusion:
        StoreTemporalNormalizationExclusionV1?
    private var uncertainPolicyDescriptors: [Int32] = []
    private let intentIO = EraseAbortCheckedSnapshotIOV1()
    private weak var originalScratchContinuity: StoreOriginalEraseRecoveryAuxiliaryContinuityV1?
    private(set) var observation: EraseIntentStore.OriginalRecoveryObservation?
    private var projectedControlPolicyObservation:
        EraseIntentStore.OriginalRecoveryObservation?
    private var publishedObservation: EraseIntentStore.OriginalRecoveryObservation?
    fileprivate var publishedIntentForTargetTransfer: EraseIntentV1? {
        publishedObservation?.intent
    }
    fileprivate enum State { case captured, held, closing, released, uncertain }
    fileprivate var state = State.captured
#if DEBUG
    var originalRecoveryUncertainForTesting: Bool { state == .uncertain }
#endif

    fileprivate init(coordinator: StoreSessionCoordinator,
                     operation: EraseRouterOperationV1,
                     source: StoreGenerationSession,
                     writer: WorkspaceWriterV1,
                     writerToken: GenerationLeaseTokenV1,
                     registry: GenerationLeaseRegistryV1,
                     supportURL: URL,
                     retainedOriginalExclusion:
                        StoreTemporalNormalizationExclusionV1? = nil) {
        self.coordinator = coordinator; self.operation = operation
        self.id = retainedOriginalExclusion?.id ?? UUID()
        self.source = source; self.writer = writer
        self.writerToken = writerToken
        self.registry = registry; self.supportURL = supportURL
        self.retainedOriginalExclusion = retainedOriginalExclusion
    }

    /// Reject stale or foreign callbacks before they consult source models.
    func requireUndetachedOriginalRecoveryOperation(
        _ expectedOperation: EraseRouterOperationV1
    ) throws {
        guard operation === expectedOperation, !expectedOperation.detached else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Pure binding/settlement reproof before the exact EX transfer and Router
    /// consume this model-owning association. This EX already exists, so the
    /// retained-recovery detach path cannot await another acquisition.
    /// This grants no filesystem effect or replacement retirement authority.
    func requireReleasedForOriginalRetirementImage(
        operation expectedOperation: EraseRouterOperationV1,
        coordinator expectedCoordinator: StoreSessionCoordinator,
        exclusion expectedExclusion: StoreTemporalNormalizationExclusionV1,
        binding: EraseRetirementBindingV1,
        transferredExclusion: EraseRetirementExclusionV1?
    ) throws {
        try requireUndetachedOriginalRecoveryOperation(expectedOperation)
        guard coordinator === expectedCoordinator, state == .released,
              uncertainPolicyDescriptors.isEmpty,
              publishedObservation?.intent?.phase == .pointerSwitched,
              retainedOriginalExclusion === expectedExclusion,
              expectedExclusion.id == id,
              expectedExclusion.registry === registry,
              expectedExclusion.activity === activity,
              expectedExclusion.physicalRoot === root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let transferredExclusion {
            // A failed aggregate detach retains the already consumed exact
            // EX successor. Retry must reprove that same transfer, not demand
            // the coordinator/writer which it legitimately consumed.
            try transferredExclusion.requireOriginalRecoveryImageTransfer(
                binding: binding, originalExclusion: expectedExclusion)
        } else {
            guard expectedExclusion.owner === expectedCoordinator,
                  expectedExclusion.writer === expectedCoordinator.workspaceWriter else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try intentIO.requireSettled()
    }

    /// Pure identity check for the physical root's synchronous borrowed FD.
    /// The enclosing owner/Registry scopes provide the substantive census;
    /// this callback must not acquire G while G may already be held.
    fileprivate func requireRetainedOriginalPhysicalBorrow(
        _ expectedRoot: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard state == .held || state == .closing,
              let retainedOriginalExclusion,
              let coordinator, let operation,
              retainedOriginalExclusion.owner === coordinator,
              retainedOriginalExclusion.physicalRoot === expectedRoot,
              root === expectedRoot,
              activity === retainedOriginalExclusion.activity,
              retainedOriginalExclusion.registry === registry,
              retainedOriginalExclusion.retainedWriter == writerToken,
              operation.retainedOriginalEraseRecoveryExclusionIdentity(
                coordinator: coordinator) === retainedOriginalExclusion else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try coordinator.requireRetainedOriginalRecoveryBorrow(
            owner: self, exclusion: retainedOriginalExclusion,
            root: expectedRoot)
    }

    func requireRetainedOriginalRecoveryStoreEffect(
        registry expectedRegistry: GenerationLeaseRegistryV1,
        activity expectedActivity: GenerationTemporalActivityHandleV1,
        support expectedRoot: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard state == .held,
              let retainedOriginalExclusion,
              retainedOriginalExclusion.registry === expectedRegistry,
              retainedOriginalExclusion.activity === expectedActivity,
              retainedOriginalExclusion.physicalRoot === expectedRoot,
              self.activity === expectedActivity,
              root === expectedRoot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireRetainedOriginalPhysicalBorrow(expectedRoot)
    }

    /// Constructs the no-create authority with this owner's retained provider.
    /// Neither the provider nor an effect capability escapes to the Service.
    func makeOriginalRecoveryNoCreateAuthority(
        factory: StoreGenerationFactory,
        observation expected: EraseIntentStore.OriginalRecoveryObservation
    ) throws -> StoreRestoreGenerationAuthority {
        try requireHeld()
        guard observation == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try factory.makeOriginalEraseRecoveryNoCreateAuthority(
            expectedApplicationSupportIdentity: StoreApplicationSupportIdentity(
                device: dev_t(expected.supportDevice),
                inode: ino_t(expected.supportInode)),
            retainedRegistry: registry)
    }

    func requireHeld() throws {
        guard state == .held, uncertainPolicyDescriptors.isEmpty,
              let coordinator, let operation,
              let activity, let root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try intentIO.requireSettled()
        try coordinator.requireOriginalEraseRecoveryPreOpenOwner(self,
            operation: operation, activity: activity, root: root)
    }

    /// Used only inside the Registry's already-held G. Calling requireHeld()
    /// there would try to reacquire G and deadlock. The enclosing Registry
    /// scope performs the checked complete census on both sides of the body.
    func requireHeldInsideOriginalRecoveryG() throws {
        guard state == .held, uncertainPolicyDescriptors.isEmpty,
              let coordinator, let operation, let root,
              activity != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try intentIO.requireSettled()
        try coordinator.requireOriginalEraseRecoveryInsideG(
            self, operation: operation, root: root)
    }

    func withCheckedSupportInsideOriginalRecoveryG<Value>(
        _ body: (Int32, EraseAbortCheckedSnapshotIOV1) throws -> Value
    ) throws -> Value {
        try requireHeldInsideOriginalRecoveryG()
        guard let root else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        let value = try root.withOriginalEraseRecoverySupport(at: supportURL) {
            try body($0, intentIO)
        }
        try intentIO.requireSettled()
        try requireHeldInsideOriginalRecoveryG()
        return value
    }

    fileprivate func bindOriginalScratchContinuity(
        _ continuity: StoreOriginalEraseRecoveryAuxiliaryContinuityV1
    ) throws {
        guard originalScratchContinuity == nil || originalScratchContinuity === continuity,
              let operation, let coordinator else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireOriginalRecoveryAuxiliaryContinuity(
            continuity, owner: self, coordinator: coordinator)
        originalScratchContinuity = continuity
    }

    func requireOriginalScratchImageInsideOriginalRecoveryG() throws
        -> ScratchDataLeaseStoreV1.OriginalEraseScratchImageV1 {
        try requireHeldInsideOriginalRecoveryG()
        guard let continuity = originalScratchContinuity,
              let operation, let coordinator else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireOriginalRecoveryAuxiliaryContinuity(
            continuity, owner: self, coordinator: coordinator)
        let image = try continuity.originalScratchImageInsideOriginalRecoveryG(owner: self)
        try operation.requireOriginalRecoveryAuxiliaryContinuity(
            continuity, owner: self, coordinator: coordinator)
        try requireHeldInsideOriginalRecoveryG()
        return image
    }

    func requireObservationUnchangedInsideOriginalRecoveryG() throws {
        try requireHeldInsideOriginalRecoveryG()
        guard let expected = publishedObservation
                ?? projectedControlPolicyObservation ?? observation, let root,
              try EraseIntentStore.observeOriginalRecoveryNoCreate(
                  support: root, applicationSupportURL: supportURL,
                  io: intentIO,
                  retainUncertainDescriptor: { [self] in uncertainPolicyDescriptors.append($0) })
                  == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireHeldInsideOriginalRecoveryG()
    }

    func poisonOnUncertainScratch() {
        state = .uncertain
        coordinator?.retainUncertainOriginalEraseRecovery(self)
    }

    /// No constructor, policy setter, pending promotion or repair is allowed
    /// before this observation. The same held Support FD is used at reproof.
    func observeIntentAndPreparation() throws
        -> EraseIntentStore.OriginalRecoveryObservation {
        try requireHeld()
        guard let root, let operation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let value = try EraseIntentStore.observeOriginalRecoveryNoCreate(
            support: root, applicationSupportURL: supportURL, io: intentIO,
            retainUncertainDescriptor: { [self] in uncertainPolicyDescriptors.append($0) })
        try operation.bindOriginalRecoveryObservation(value, owner: self)
        observation = value
        try requireHeld()
        return value
    }

    func requireObservationUnchanged() throws {
        try requireHeld()
        guard let expected = publishedObservation
                ?? projectedControlPolicyObservation ?? observation, let root,
              try EraseIntentStore.observeOriginalRecoveryNoCreate(
                  support: root, applicationSupportURL: supportURL, io: intentIO,
                  retainUncertainDescriptor: { [self] in uncertainPolicyDescriptors.append($0) })
                  == expected else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireHeld()
    }

    func observedCurrentGenerationID() throws -> UUID {
        try withExclusiveSourceScratch { _ in
            try withCheckedSupportInsideOriginalRecoveryG { support, io in
                try io.withOpen(parent: support, name: "FieldEvidenceData",
                                flags: O_RDONLY | O_DIRECTORY) { data in
                    let (bytes, _) = try io.control(parent: data,
                        name: "current.json")
                    let envelope = try CurrentPointerCodecV1.decode(bytes)
                    guard let id = UUID(uuidString: envelope.generationID) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    return id
                }
            }
        }
    }

    private struct OriginalRecoveryTargetControls: Equatable {
        struct Leaf: Equatable { let bytes: Data; let identity: String }
        struct DirectoryFact: Equatable {
            let device: dev_t
            let inode: ino_t
            let mode: mode_t
            let owner: uid_t
            let group: gid_t
            let links: nlink_t
            let size: off_t
            let modifiedSeconds: Int64
            let modifiedNanoseconds: Int64
            let changedSeconds: Int64
            let changedNanoseconds: Int64

            init(_ value: stat) throws {
                guard value.st_mode & S_IFMT == S_IFDIR else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                device = value.st_dev
                inode = value.st_ino
                mode = value.st_mode
                owner = value.st_uid
                group = value.st_gid
                links = value.st_nlink
                size = value.st_size
                modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
                modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
                changedSeconds = Int64(value.st_ctimespec.tv_sec)
                changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
            }

            var fullText: String {
                "\(device)|\(inode)|\(mode)|\(owner)|\(group)|\(links)|\(size)|\(modifiedSeconds)|\(modifiedNanoseconds)|\(changedSeconds)|\(changedNanoseconds)"
            }
        }
        let dataDirectory: DirectoryFact
        let operationsDirectory: DirectoryFact
        let migrationDirectory: DirectoryFact
        let dataNames: [String]
        let operationsNames: [String]
        let migrationNames: [String]
        let current: Leaf
        let retired: Leaf
        let migrationLeaves: [String: Leaf]
    }

    /// The first target-current observation is a complete checked, no-create
    /// control census under the original EX/G. A policy request cannot mint a
    /// fresh baseline: every callback re-reads the same names, identities and
    /// bytes, including every non-target migration control and manifest.
    func requireOriginalRecoveryTargetControls(
        intent: EraseIntentV1,
        expectedAuxiliary: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    ) throws -> StoreGenerationManifestV1 {
        guard intent.schemaVersion == 2,
              let target = intent.targetPointer,
              target.generationID == intent.newGenerationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let targetName = "manifest-" + target.generationID.uuidString.lowercased() + ".json"
        let dataURL = supportURL.appendingPathComponent("FieldEvidenceData", isDirectory: true)
        let operationsURL = supportURL.appendingPathComponent(
            "FieldEvidenceOperations", isDirectory: true)
        let migrationURL = operationsURL.appendingPathComponent(
            "schema-migration", isDirectory: true)
        func admittedMigrationName(_ name: String) -> Bool {
            if ["journal.json", "prepared-migration.json", "aggregate.json"].contains(name) {
                return true
            }
            guard name.hasPrefix("manifest-"), name.hasSuffix(".json") else { return false }
            let text = String(name.dropFirst("manifest-".count).dropLast(".json".count))
            return UUID(uuidString: text)?.uuidString.lowercased() == text
        }
        return try withExclusiveSourceScratch { _ in
            try withCheckedSupportInsideOriginalRecoveryG { support, io in
                func directoryFact(parent: Int32, name: String, opened: Int32) throws
                    -> OriginalRecoveryTargetControls.DirectoryFact {
                    var held = stat()
                    var named = stat()
                    guard Darwin.fstat(opened, &held) == 0,
                          Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    let heldFact = try OriginalRecoveryTargetControls.DirectoryFact(held)
                    guard heldFact == (try OriginalRecoveryTargetControls.DirectoryFact(named)) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    return heldFact
                }
                func read() throws -> OriginalRecoveryTargetControls {
                    try io.withOpen(parent: support, name: "FieldEvidenceData",
                                    flags: O_RDONLY | O_DIRECTORY) { data in
                        let dataFact = try directoryFact(
                            parent: support, name: "FieldEvidenceData", opened: data)
                        let dataNames = try io.names(in: data)
                        let (currentBytes, currentIdentity) = try io.control(
                            parent: data, name: "current.json")
                        let (retiredBytes, retiredIdentity) = try io.control(
                            parent: data, name: "retired.json")
                        return try io.withOpen(parent: support,
                            name: "FieldEvidenceOperations",
                            flags: O_RDONLY | O_DIRECTORY) { operations in
                            let operationsFact = try directoryFact(
                                parent: support, name: "FieldEvidenceOperations",
                                opened: operations)
                            let operationsNames = try io.names(in: operations)
                            guard operationsNames.contains("schema-migration") else {
                                throw GenerationLeaseRegistryFailureV1.uncertainOwner
                            }
                            return try io.withOpen(parent: operations,
                                name: "schema-migration",
                                flags: O_RDONLY | O_DIRECTORY) { migration in
                                let migrationFact = try directoryFact(
                                    parent: operations, name: "schema-migration",
                                    opened: migration)
                                let names = try io.names(in: migration)
                                guard names.allSatisfy(admittedMigrationName),
                                      names.contains(targetName) else {
                                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                                }
                                var leaves: [String: OriginalRecoveryTargetControls.Leaf] = [:]
                                for name in names {
                                    let (bytes, identity) = try io.control(parent: migration,
                                                                            name: name)
                                    leaves[name] = .init(bytes: bytes, identity: identity)
                                    if name.hasPrefix("manifest-") {
                                        let decoded = try StoreGenerationManifestV1
                                            .decodeCanonical(from: bytes)
                                        guard "manifest-" + decoded.generationID
                                            .uuidString.lowercased() + ".json" == name else {
                                            throw GenerationLeaseRegistryFailureV1.uncertainOwner
                                        }
                                    }
                                }
                                guard try io.names(in: migration) == names,
                                      try io.names(in: operations) == operationsNames,
                                      try io.names(in: data) == dataNames,
                                      try directoryFact(parent: operations,
                                          name: "schema-migration", opened: migration)
                                          == migrationFact,
                                      try directoryFact(parent: support,
                                          name: "FieldEvidenceOperations", opened: operations)
                                          == operationsFact,
                                      try directoryFact(parent: support,
                                          name: "FieldEvidenceData", opened: data)
                                          == dataFact else {
                                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                                }
                                return OriginalRecoveryTargetControls(
                                    dataDirectory: dataFact,
                                    operationsDirectory: operationsFact,
                                    migrationDirectory: migrationFact,
                                    dataNames: dataNames,
                                    operationsNames: operationsNames,
                                    migrationNames: names,
                                    current: .init(bytes: currentBytes,
                                        identity: currentIdentity),
                                    retired: .init(bytes: retiredBytes,
                                        identity: retiredIdentity),
                                    migrationLeaves: leaves)
                            }
                        }
                    }
                }
                let first = try read()
                guard case .present(let firstOperationsFact, _) =
                        expectedAuxiliary.operations,
                      first.operationsDirectory.fullText == firstOperationsFact,
                      first.operationsNames ==
                        expectedAuxiliary.operationsChildren.keys.sorted() else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                let envelope = try CurrentPointerCodecV1.decode(first.current.bytes)
                let expected = try CurrentGenerationPointerV3(
                    generationID: target.generationID,
                    generationManifestSHA256: target.generationManifestSHA256,
                    workspaceID: WorkspaceID(rawValue: target.workspaceID),
                    replicaID: ReplicaID(rawValue: target.replicaID),
                    knownReplicaIDs: Set(target.knownReplicaIDs.map { ReplicaID(rawValue: $0) }),
                    storeSchemaVersion: PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major)
                guard case .v3(let actual, _) = envelope, actual == expected,
                      let leaf = first.migrationLeaves[targetName],
                      StoreMigrationCanonicalJSONV1.sha256(leaf.bytes)
                        == target.generationManifestSHA256 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                let manifest = try StoreGenerationManifestV1.decodeCanonical(from: leaf.bytes)
                guard manifest.generationID == target.generationID,
                      manifest.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                func unchanged() throws -> Bool {
                    guard try read() == first else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    return true
                }
                let retain: (Int32) -> Void = { [self] in uncertainPolicyDescriptors.append($0) }
                _ = try ProtectedFilePolicyV1.verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .durableDirectory, at: dataURL,
                    retainUncertainDescriptor: retain, unchangedWitness: unchanged)
                _ = try ProtectedFilePolicyV1.verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .generationPointer, at: dataURL.appendingPathComponent("current.json"),
                    retainUncertainDescriptor: retain, unchangedWitness: unchanged)
                _ = try ProtectedFilePolicyV1.verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .generationPointer, at: dataURL.appendingPathComponent("retired.json"),
                    retainUncertainDescriptor: retain, unchangedWitness: unchanged)
                _ = try ProtectedFilePolicyV1.verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .stagingDirectory, at: migrationURL,
                    retainUncertainDescriptor: retain, unchangedWitness: unchanged)
                for name in first.migrationNames {
                    _ = try ProtectedFilePolicyV1.verifyEraseColdTemporalPolicyWithCheckedRequest(
                        .journal, at: migrationURL.appendingPathComponent(name),
                        retainUncertainDescriptor: retain, unchangedWitness: unchanged)
                }
                _ = try unchanged()
                return manifest
            }
        }
    }

    /// The source copy is a synchronous one-operation read. The Registry
    /// retains G across the body; the already-held activity and Support EX
    /// remain this owner's, and the same no-create intent witness is rechecked
    /// on either side without adopting a new baseline.
    func withExclusiveSourceScratch<Value>(
        _ body: (OriginalEraseExclusiveScratchPermitV1) throws -> Value
    ) throws -> Value {
        try requireObservationUnchanged()
        guard let activity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            let value = try registry.withOriginalEraseRecoveryExclusiveScratchPermit(
                owner: self, activity: activity, retainedWriter: writerToken, body)
            try requireObservationUnchanged()
            return value
        } catch {
            poisonOnUncertainScratch()
            throw error
        }
    }

    /// The source has already passed two independent, same-operation private
    /// validations. The first canonical phase CAS is the sole effect allowed
    /// by this checked scope; the intent store uses this owner's descriptor
    /// quarantine and is closed before G is released.
    /// Publishes the original P owner's durable retired-pointer intent before
    /// Factory may create `.retired.json.restore-next`. This stage does not
    /// advance P or grant the subsequent pointer writer a raw-byte permit.
    /// The Store's private receipt is retained by the original operation only
    /// after the checked, same-inode publication and postimage have settled.
    func publishOriginalRecoveryRetiredCommitment(
        expected: EraseIntentV1,
        namespace: OriginalEraseRecoveryNamespaceSnapshotV1,
        replacementBytes: Data,
        sourceAuthority: StoreRestoreGenerationAuthority,
        sourceTreeDigest: String,
        targetTreeDigest: String,
        auxiliaryContinuity: StoreOriginalEraseRecoveryAuxiliaryContinuityV1,
        provisionalSourcePolicy: OriginalRecoveryProvisionalPolicyV1,
        priorRetired: [EraseAllService.OriginalRecoveryPriorRetiredCopyV1],
        externalSource: OriginalEraseRecoveryExternalSnapshotV1,
        externalReads: [OriginalEraseRecoveryExternalReadV1]
    ) throws -> EraseIntentStore.OriginalRecoveryRetiredCommitmentReceiptV1 {
        try requireObservationUnchanged()
        guard let observation, observation.intent == expected,
              expected.schemaVersion == 2,
              expected.phase == .emptyGenerationPrepared,
              namespace.retiredState == .prior,
              let activity, let root, let operation,
              retainedOriginalExclusion != nil,
              try sourceAuthority.originalRecoveryRetiredReplacementBytes(
                  intent: expected, namespace: namespace) == replacementBytes,
              try sourceAuthority.originalRecoveryNamespaceSnapshot(
                  intent: expected) == namespace,
              try sourceAuthority.originalRecoverySourceTreeDigest(
                  id: expected.oldGenerationID) == sourceTreeDigest,
              try sourceAuthority.originalRecoveryEmptyTargetTreeDigest(
                  id: expected.newGenerationID) == targetTreeDigest else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let store = try operation.requireOriginalRecoveryFirstEffectStore(
            owner: self, expected: expected)
        let expectedPriorIDs = expected.generationIDsToDelete.filter {
            $0 != expected.oldGenerationID
        }
        guard priorRetired.map({ $0.image.generationID }) == expectedPriorIDs else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            let receipt = try registry.withOriginalEraseRecoveryRetiredCommitmentPermit(
                owner: self, activity: activity,
                retainedWriter: writerToken) { permit in
                try requireObservationUnchangedInsideOriginalRecoveryG()
                guard try sourceAuthority.originalRecoveryNamespaceSnapshot(
                        intent: expected) == namespace,
                      try sourceAuthority.originalRecoverySourceTreeDigest(
                        id: expected.oldGenerationID) == sourceTreeDigest,
                      try sourceAuthority.originalRecoveryEmptyTargetTreeDigest(
                        id: expected.newGenerationID) == targetTreeDigest else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try sourceAuthority.requireOriginalRecoveryExternalSnapshot(
                    externalSource)
                try sourceAuthority.requireOriginalRecoveryProvisionalPolicyUnchanged(
                    provisionalSourcePolicy)
                for prior in priorRetired {
                    try prior.image.requireUnchangedInsideOriginalG(
                        intent: expected, owner: self,
                        authority: sourceAuthority)
                    try sourceAuthority.requireOriginalRecoveryProvisionalPolicyUnchanged(
                        prior.policy)
                }
                var byPath = [String: OriginalEraseRecoveryExternalReadV1]()
                for read in externalReads + priorRetired.flatMap({ $0.reads }) {
                    let key = read.family.rawValue + ":" + read.path
                    if let first = byPath[key] {
                        guard first.kind == read.kind,
                              first.policy == read.policy else {
                            throw GenerationLeaseRegistryFailureV1.uncertainOwner
                        }
                        byPath[key] = OriginalEraseRecoveryExternalReadV1(
                            family: first.family, path: first.path,
                            kind: first.kind,
                            maximum: min(first.maximum, read.maximum),
                            policy: first.policy)
                    } else { byPath[key] = read }
                }
                try sourceAuthority.requireOriginalRecoveryExternalReadsUnchanged(
                    byPath.values.sorted {
                        ($0.family.rawValue, $0.path) <
                            ($1.family.rawValue, $1.path)
                    }, snapshot: externalSource)
                _ = try auxiliaryContinuity
                    .requireProjectedInsideOriginalRecoveryG(owner: self)
                try requireObservationUnchangedInsideOriginalRecoveryG()
                let receipt = try store.publishOriginalRecoveryRetiredCommitment(
                    namespace: namespace, replacementBytes: replacementBytes,
                    sourceAuthority: sourceAuthority,
                    operation: operation, owner: self,
                    registry: registry, activity: activity,
                    permit: permit, support: root,
                    firstObservation: observation, io: intentIO,
                    retainUncertainDescriptor: { [self] in
                        uncertainPolicyDescriptors.append($0)
                    })
                let projected = try receipt.requirePublishedObservation(
                    firstObservation: observation,
                    operation: operation, owner: self,
                    namespace: namespace,
                    replacementBytes: replacementBytes)
                projectedControlPolicyObservation = projected
                guard try sourceAuthority.originalRecoveryNamespaceSnapshot(
                        intent: expected) == namespace else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                _ = try auxiliaryContinuity
                    .requireProjectedInsideOriginalRecoveryG(owner: self)
                try requireObservationUnchangedInsideOriginalRecoveryG()
                return receipt
            }
            try operation.retainOriginalRecoveryRetiredCommitment(
                receipt, store: store, owner: self,
                namespace: namespace, replacementBytes: replacementBytes)
            try requireObservationUnchanged()
            return receipt
        } catch {
            poisonOnUncertainScratch()
            throw error
        }
    }

    /// The source has already passed two independent, same-operation private
    /// validations. The first canonical phase CAS is the sole effect allowed
    /// by this checked scope; the intent store uses this owner's descriptor
    /// quarantine and is closed before G is released.
    @MainActor
    struct OriginalRecoveryRetiredPublicationV1 {
        let commitment:
            EraseIntentStore.OriginalRecoveryRetiredCommitmentReceiptV1
        let stage: OriginalEraseRecoveryRetiredStageReceiptV1
        let stageIdentity:
            EraseIntentStore.OriginalRecoveryRetiredStageIdentityReceiptV1
        let canonical: OriginalEraseRecoveryRetiredCanonicalReceiptV1
        let firstNamespace: OriginalEraseRecoveryNamespaceSnapshotV1
        let replacementBytes: Data

        func requirePublishedInsideG(
            owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
            operation: EraseRouterOperationV1,
            authority: StoreRestoreGenerationAuthority
        ) throws {
            try commitment.requireBound(operation: operation, owner: owner,
                namespace: firstNamespace,
                replacementBytes: replacementBytes)
            try stageIdentity.requireBound(operation: operation,
                owner: owner, commitment: commitment, stage: stage,
                namespace: firstNamespace,
                replacementBytes: replacementBytes)
            try canonical.requirePublishedPostimage(authority: authority,
                operation: operation, owner: owner,
                namespace: firstNamespace,
                replacementBytes: replacementBytes)
        }

        func requirePhysicalInsideG(
            authority: StoreRestoreGenerationAuthority
        ) throws {
            try authority.requireOriginalRecoveryRetiredCanonical(canonical,
                namespace: firstNamespace,
                replacementBytes: replacementBytes)
        }
    }

    /// After the distinct pre-temp commitment, one lexical retained EX/G
    /// interval creates the private stage, records its inode durably, then
    /// renames and swaps only that inode into the canonical retired pointer.
    /// The returned physical result is re-proved in the next G before P→Q.
    func publishOriginalRecoveryRetiredCanonical(
        expected: EraseIntentV1,
        namespace: OriginalEraseRecoveryNamespaceSnapshotV1,
        replacementBytes: Data,
        commitment:
            EraseIntentStore.OriginalRecoveryRetiredCommitmentReceiptV1,
        sourceAuthority: StoreRestoreGenerationAuthority,
        sourceTreeDigest: String,
        targetTreeDigest: String,
        auxiliaryContinuity: StoreOriginalEraseRecoveryAuxiliaryContinuityV1,
        provisionalSourcePolicy: OriginalRecoveryProvisionalPolicyV1,
        priorRetired: [EraseAllService.OriginalRecoveryPriorRetiredCopyV1],
        externalSource: OriginalEraseRecoveryExternalSnapshotV1,
        externalReads: [OriginalEraseRecoveryExternalReadV1]
    ) throws -> OriginalRecoveryRetiredPublicationV1 {
        try requireObservationUnchanged()
        guard let observation, observation.intent == expected,
              expected.schemaVersion == 2,
              expected.phase == .emptyGenerationPrepared,
              namespace.retiredState == .prior,
              let activity, let root, let operation,
              retainedOriginalExclusion != nil,
              try sourceAuthority.originalRecoveryRetiredReplacementBytes(
                  intent: expected, namespace: namespace) == replacementBytes
        else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let store = try operation.requireOriginalRecoveryFirstEffectStore(
            owner: self, expected: expected)
        let expectedPrior = expected.generationIDsToDelete.filter {
            $0 != expected.oldGenerationID
        }
        guard priorRetired.map({ $0.image.generationID }) == expectedPrior else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        var byPath = [String: OriginalEraseRecoveryExternalReadV1]()
        for read in externalReads + priorRetired.flatMap({ $0.reads }) {
            let key = read.family.rawValue + ":" + read.path
            if let first = byPath[key] {
                guard first.kind == read.kind,
                      first.policy == read.policy else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                byPath[key] = OriginalEraseRecoveryExternalReadV1(
                    family: first.family, path: first.path,
                    kind: first.kind,
                    maximum: min(first.maximum, read.maximum),
                    policy: first.policy)
            } else { byPath[key] = read }
        }
        let allReads = byPath.values.sorted {
            ($0.family.rawValue, $0.path) < ($1.family.rawValue, $1.path)
        }
        do {
            let result = try registry.withOriginalEraseRecoveryRetiredStagePermit(
                owner: self, activity: activity,
                retainedWriter: writerToken) { permit in
                @MainActor func reproveSources() throws {
                    try requireObservationUnchangedInsideOriginalRecoveryG()
                    guard try sourceAuthority.originalRecoverySourceTreeDigest(
                            id: expected.oldGenerationID) == sourceTreeDigest,
                          try sourceAuthority.originalRecoveryEmptyTargetTreeDigest(
                            id: expected.newGenerationID) == targetTreeDigest else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    try sourceAuthority.requireOriginalRecoveryExternalSnapshot(
                        externalSource)
                    try sourceAuthority.requireOriginalRecoveryExternalReadsUnchanged(
                        allReads, snapshot: externalSource)
                    try sourceAuthority.requireOriginalRecoveryProvisionalPolicyUnchanged(
                        provisionalSourcePolicy)
                    for prior in priorRetired {
                        try prior.image.requireUnchangedInsideOriginalG(
                            intent: expected, owner: self,
                            authority: sourceAuthority)
                        try sourceAuthority.requireOriginalRecoveryProvisionalPolicyUnchanged(
                            prior.policy)
                    }
                    _ = try auxiliaryContinuity
                        .requireProjectedInsideOriginalRecoveryG(owner: self)
                }
                try commitment.requireBound(operation: operation,
                    owner: self, namespace: namespace,
                    replacementBytes: replacementBytes)
                guard try sourceAuthority.originalRecoveryNamespaceSnapshot(
                    intent: expected) == namespace else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try reproveSources()
                let stage = try sourceAuthority
                    .prepareOriginalRecoveryRetiredPrivateStage(
                        intent: expected, namespace: namespace,
                        replacementBytes: replacementBytes,
                        commitment: commitment, operation: operation,
                        owner: self, permit: permit)
                try reproveSources()
                let identity = try store
                    .publishOriginalRecoveryRetiredStageIdentity(
                        stage: stage, sourceAuthority: sourceAuthority,
                        commitment: commitment, namespace: namespace,
                        replacementBytes: replacementBytes,
                        operation: operation, owner: self,
                        registry: registry, activity: activity,
                        permit: permit, support: root, io: intentIO,
                        retainUncertainDescriptor: { [self] in
                            uncertainPolicyDescriptors.append($0)
                        })
                guard let controlBefore = projectedControlPolicyObservation else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                projectedControlPolicyObservation = try identity
                    .requirePublishedObservation(
                        firstObservation: controlBefore,
                        operation: operation, owner: self,
                        commitment: commitment, stage: stage,
                        namespace: namespace,
                        replacementBytes: replacementBytes)
                try reproveSources()
                let temporary = try sourceAuthority
                    .publishOriginalRecoveryRetiredNamedTemporary(
                        intent: expected, namespace: namespace,
                        replacementBytes: replacementBytes,
                        commitment: commitment, stage: stage,
                        stageIdentity: identity, operation: operation,
                        owner: self, permit: permit)
                try reproveSources()
                let canonical = try sourceAuthority
                    .publishOriginalRecoveryRetiredCanonical(
                        intent: expected, namespace: namespace,
                        replacementBytes: replacementBytes,
                        commitment: commitment, stage: stage,
                        stageIdentity: identity, temporary: temporary,
                        operation: operation, owner: self, permit: permit)
                let result = OriginalRecoveryRetiredPublicationV1(
                    commitment: commitment, stage: stage,
                    stageIdentity: identity, canonical: canonical,
                    firstNamespace: namespace,
                    replacementBytes: replacementBytes)
                try result.requirePublishedInsideG(owner: self,
                    operation: operation, authority: sourceAuthority)
                try reproveSources()
                return result
            }
            try requireObservationUnchanged()
            return result
        } catch {
            poisonOnUncertainScratch()
            throw error
        }
    }

    struct FirstPointerPhaseResultV1 {
        let intent: EraseIntentV1
        let sources: [OriginalRecoveryCompletedSourcePolicyV1]
        let external: OriginalRecoveryCompletedExternalPolicyV1
        fileprivate init(intent: EraseIntentV1,
            sources: [OriginalRecoveryCompletedSourcePolicyV1],
            external: OriginalRecoveryCompletedExternalPolicyV1) {
            self.intent = intent; self.sources = sources; self.external = external
        }
    }

    func publishFirstPointerPhase(
        expected: EraseIntentV1,
        preparation: ErasePreparationV2?,
        sourceAuthority: StoreRestoreGenerationAuthority,
        auxiliaryContinuity:
            StoreOriginalEraseRecoveryAuxiliaryContinuityV1,
        provisionalSourcePolicy: OriginalRecoveryProvisionalPolicyV1,
        priorRetired: [EraseAllService.OriginalRecoveryPriorRetiredCopyV1],
        externalSource: OriginalEraseRecoveryExternalSnapshotV1,
        externalReads: [OriginalEraseRecoveryExternalReadV1],
        targetTreeDigest: String? = nil,
        retiredPublication: OriginalRecoveryRetiredPublicationV1? = nil
    ) throws -> FirstPointerPhaseResultV1 {
        try requireObservationUnchanged()
        guard let observation, observation.intent == expected,
              observation.preparation == preparation,
              expected.schemaVersion == 2,
              expected.phase == .emptyGenerationPrepared,
              provisionalSourcePolicy.generationID == expected.oldGenerationID,
              let activity, let root, let operation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let retainedAuxiliaryStore: EraseIntentStore?
        if retainedOriginalExclusion != nil {
            retainedAuxiliaryStore = try operation
                .requireOriginalRecoveryFirstEffectStore(
                    owner: self, expected: expected)
        } else {
            retainedAuxiliaryStore = nil
        }
        let expectedPriorIDs = expected.generationIDsToDelete.filter {
            $0 != expected.oldGenerationID
        }
        guard priorRetired.map({ $0.image.generationID }) == expectedPriorIDs else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        for prior in priorRetired {
            guard prior.policy.generationID == prior.image.generationID,
                  prior.policy.treeDigest == prior.image.sourceTreeDigest,
                  prior.external == externalSource else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        let switched = expected.advancing(to: .pointerSwitched)
        var completedSources = [OriginalRecoveryCompletedSourcePolicyV1]()
        var completedExternal: OriginalRecoveryCompletedExternalPolicyV1?
        do {
            let post = try registry.withOriginalEraseRecoveryFirstEffectPermit(
                owner: self, activity: activity,
                retainedWriter: writerToken) { permit in
                try requireObservationUnchangedInsideOriginalRecoveryG()
                if retainedOriginalExclusion != nil {
                    guard let targetTreeDigest,
                          try sourceAuthority.originalRecoveryEmptyTargetTreeDigest(
                            id: expected.newGenerationID)
                            == targetTreeDigest else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    if let retiredPublication {
                        try retiredPublication.requirePublishedInsideG(
                            owner: self, operation: operation,
                            authority: sourceAuthority)
                    } else {
                        guard try sourceAuthority.originalRecoveryNamespaceSnapshot(
                            intent: expected).retiredState == .complete else {
                            throw GenerationLeaseRegistryFailureV1.uncertainOwner
                        }
                    }
                } else if retiredPublication != nil {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try sourceAuthority.requireOriginalRecoveryExternalSnapshot(
                    externalSource)
                // Authenticate every retained source before the first policy
                // request. Never accept a roster assembled from survivors.
                for prior in priorRetired {
                    try prior.image.requireUnchangedInsideOriginalG(
                        intent: expected, owner: self, authority: sourceAuthority)
                    try sourceAuthority.requireOriginalRecoveryProvisionalPolicyUnchanged(
                        prior.policy)
                }
                try sourceAuthority.requireOriginalRecoveryProvisionalPolicyUnchanged(
                    provisionalSourcePolicy)
                var byPath = [String: OriginalEraseRecoveryExternalReadV1]()
                for read in externalReads + priorRetired.flatMap({ $0.reads }) {
                    let key = read.family.rawValue + ":" + read.path
                    if let first = byPath[key] {
                        guard first.kind == read.kind, first.policy == read.policy else {
                            throw GenerationLeaseRegistryFailureV1.uncertainOwner
                        }
                        byPath[key] = OriginalEraseRecoveryExternalReadV1(
                            family: first.family, path: first.path, kind: first.kind,
                            maximum: min(first.maximum, read.maximum), policy: first.policy)
                    } else { byPath[key] = read }
                }
                let allReads = byPath.values.sorted {
                    ($0.family.rawValue, $0.path) < ($1.family.rawValue, $1.path)
                }
                try sourceAuthority.requireOriginalRecoveryExternalReadsUnchanged(
                    allReads, snapshot: externalSource)
                try requireObservationUnchangedInsideOriginalRecoveryG()
                // Rewalk the operation's first auxiliary image and its exact
                // checked ScratchData receipt chain under this same G, before
                // any policy setter or canonical Store phase effect begins.
                _ = try auxiliaryContinuity
                    .requireProjectedInsideOriginalRecoveryG(owner: self)
                completedSources.append(try sourceAuthority.originalRecoveryCompletePolicyRequests(
                    provisionalSourcePolicy, permit: permit, owner: self))
                for prior in priorRetired {
                    completedSources.append(try sourceAuthority.originalRecoveryCompletePolicyRequests(
                        prior.policy, permit: permit, owner: self))
                }
                completedExternal = try sourceAuthority.originalRecoveryCompleteExternalPolicyRequests(
                    allReads, snapshot: externalSource,
                    permit: permit, owner: self)
                try requireObservationUnchangedInsideOriginalRecoveryG()
                for receipt in completedSources {
                    try sourceAuthority.requireOriginalRecoveryCompletedSourcePolicy(receipt)
                }
                guard let completedExternal else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try sourceAuthority.requireOriginalRecoveryCompletedExternalPolicy(completedExternal)
                let policyProjected = try EraseIntentStore
                    .completeOriginalRecoveryObservedPoliciesForFirstEffect(
                        support: root, applicationSupportURL: supportURL,
                        io: intentIO,
                        expected: projectedControlPolicyObservation
                            ?? observation,
                        permit: permit,
                        retainUncertainDescriptor: { [self] in
                            uncertainPolicyDescriptors.append($0)
                        })
                projectedControlPolicyObservation = policyProjected
                try requireObservationUnchangedInsideOriginalRecoveryG()
                if let store = retainedAuxiliaryStore {
                    let receipt = try store
                        .replaceOriginalEraseAuxiliaryPhaseForOriginalRecovery(
                            expected: expected, with: switched,
                            operation: operation, owner: self,
                            registry: registry, activity: activity,
                            permit: permit, support: root,
                            firstObservation: policyProjected,
                            io: intentIO,
                            retainUncertainDescriptor: { [self] in
                                uncertainPolicyDescriptors.append($0)
                            })
                    let value = try EraseIntentStore.observeOriginalRecoveryNoCreate(
                        support: root, applicationSupportURL: supportURL,
                        io: intentIO,
                        retainUncertainDescriptor: { [self] in
                            uncertainPolicyDescriptors.append($0)
                        })
                    try receipt.requirePublishedObservation(
                        value, expected: policyProjected, store: store)
                    guard value.intent == switched,
                          value.preparation == preparation,
                          value.supportDevice == observation.supportDevice,
                          value.supportInode == observation.supportInode else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    try retiredPublication?.requirePhysicalInsideG(
                        authority: sourceAuthority)
                    return value
                }
                let store = try EraseIntentStore(
                    applicationSupportURL: supportURL,
                    expectedApplicationSupportIdentity:
                        StoreApplicationSupportIdentity(
                            device: dev_t(observation.supportDevice),
                            inode: ino_t(observation.supportInode)),
                    originalRecoveryCheckedIO: intentIO)
                do {
                    let receipt = try store.replaceForOriginalRecoveryFirstEffect(
                        expected: expected, with: switched, permit: permit,
                        support: root, firstObservation: policyProjected)
                    let value = try EraseIntentStore.observeOriginalRecoveryNoCreate(
                        support: root, applicationSupportURL: supportURL,
                        io: intentIO,
                        retainUncertainDescriptor: { [self] in
                            uncertainPolicyDescriptors.append($0)
                        })
                    try receipt.requirePublishedObservation(
                        value, expected: policyProjected, store: store)
                    guard value.intent == switched,
                          value.preparation == preparation,
                          value.supportDevice == observation.supportDevice,
                          value.supportInode == observation.supportInode else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    try store.closeCheckedForOriginalRecovery()
                    return value
                } catch {
                    _ = try? store.closeCheckedForOriginalRecovery()
                    throw error
                }
            }
            if let retainedAuxiliaryStore {
                try operation.recordOriginalEraseAuxiliaryPhaseProjection(
                    store: retainedAuxiliaryStore, expected: expected,
                    replacement: switched)
            }
            publishedObservation = post
            projectedControlPolicyObservation = nil
            guard let completedExternal,
                  completedSources.map({ $0.generationID })
                    == [expected.oldGenerationID] + expectedPriorIDs else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return FirstPointerPhaseResultV1(intent: switched,
                sources: completedSources, external: completedExternal)
        } catch {
            poisonOnUncertainScratch()
            throw error
        }
    }

    /// A canonical effect must never reopen admission to the old writer.
    /// Close both checked exclusions, retaining the coordinator in maintenance
    /// until this exact operation installs its single target writer.
    func closeAfterFirstPointerPhaseForTargetInstallation(
        operation expectedOperation: EraseRouterOperationV1
    ) throws {
        guard let post = publishedObservation,
              let coordinator, let operation, operation === expectedOperation,
              let root, let activity, state == .held else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let current = try EraseIntentStore.observeOriginalRecoveryNoCreate(
            support: root, applicationSupportURL: supportURL, io: intentIO,
            retainUncertainDescriptor: { [self] in
                uncertainPolicyDescriptors.append($0)
            })
        guard current == post else {
            poisonOnUncertainScratch()
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        state = .closing
        do {
            try coordinator.closeOriginalEraseRecoveryAfterFirstEffect(self,
                operation: operation, activity: activity, root: root)
            state = .released
        } catch {
            state = .uncertain
            throw error
        }
    }

    /// Releases a validation-only owner before an awaited admission. Any
    /// ambiguous close remains retained in Coordinator maintenance state.
    func closeReadOnlyBeforeAdmission() throws {
        try requireObservationUnchanged()
        guard let coordinator, let operation, let root, let activity,
              state == .held else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        state = .closing
        try coordinator.closeOriginalEraseRecoveryReadOnly(self,
            operation: operation, activity: activity, root: root)
        state = .released
    }
}

extension StoreSessionCoordinator {
    fileprivate func requireRetainedOriginalRecoveryBorrow(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        root: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard originalEraseRecoveryOwner === owner,
              temporalExclusiveOwner === exclusion,
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty,
              exclusion.physicalRoot === root,
              exclusion.activity === owner.activity,
              session === owner.source,
              workspaceWriter === owner.writer,
              writerLeaseHandle.token == owner.writerToken,
              writerFence.retainedTemporalRegistry === owner.registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    fileprivate func requireOriginalEraseRecoveryInsideG(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        root: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard originalEraseRecoveryOwner === owner,
              temporalAdmission == .exclusive(owner.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              session === owner.source,
              workspaceWriter === owner.writer,
              writerLeaseHandle.token == owner.writerToken,
              writerFence.retainedTemporalRegistry === owner.registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        try writerLeaseHandle.requireExactRegistry(owner.registry)
        try root.withOriginalEraseRecoverySupport(at: owner.supportURL) { _ in () }
    }

    fileprivate func retainUncertainOriginalEraseRecovery(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
    ) {
        if originalEraseRecoveryOwner === owner {
            temporalAdmission = .maintenance(owner.id)
        }
    }

    /// Capture original opening authority before closing producer admission.
    /// This Erase task may not drain itself; the actual original ticket binds
    /// the owner before either EX descriptor is opened.
    func beginOriginalEraseRecoveryPreOpen(
        operation: EraseRouterOperationV1,
        factory: StoreGenerationFactory
    ) async throws -> StoreOriginalEraseRecoveryPreOpenOwnerV1 {
        guard TemporalProducerTaskContextV1.operation == nil,
              originalEraseRecoveryOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        let retained = try operation
            .requireOriginalEraseRecoveryRetainedExclusion(coordinator: self)
        if let retained {
            guard temporalExclusiveOwner === retained,
                  temporalAdmission == .exclusive(retained.id),
                  temporalProducerIDs.isEmpty,
                  temporalDrainWaiters.isEmpty,
                  retained.owner === self,
                  retained.writer === workspaceWriter,
                  retained.retainedWriter == writerLeaseHandle.token,
                  retained.registry === writerFence.retainedTemporalRegistry else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let source = try originalEraseRecoverySourceWithoutRegistryConstruction(
                factory: factory)
            let owner = StoreOriginalEraseRecoveryPreOpenOwnerV1(
                coordinator: self, operation: operation, source: source,
                writer: workspaceWriter, writerToken: writerLeaseHandle.token,
                registry: retained.registry,
                supportURL: Self.applicationSupportURL(for: source),
                retainedOriginalExclusion: retained)
            try operation.retainOriginalRecoveryPreOpenOwner(owner,
                coordinator: self)
            originalEraseRecoveryOwner = owner
            owner.activity = retained.activity
            owner.root = retained.physicalRoot
            owner.state = .held
            do {
                try retained.physicalRoot.bindRetainedOriginalRecoveryBorrow(
                    owner, exclusion: retained)
                try owner.requireHeld()
                return owner
            } catch {
                owner.state = .uncertain
                temporalAdmission = .maintenance(retained.id)
                throw error
            }
        }
        guard temporalAdmission == .open,
              temporalExclusiveOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let source = try originalEraseRecoverySourceWithoutRegistryConstruction(
            factory: factory)
        let registry = writerFence.retainedTemporalRegistry
        let owner = StoreOriginalEraseRecoveryPreOpenOwnerV1(
            coordinator: self, operation: operation, source: source,
            writer: workspaceWriter, writerToken: writerLeaseHandle.token,
            registry: registry,
            supportURL: Self.applicationSupportURL(for: source))
        try operation.retainOriginalRecoveryPreOpenOwner(owner, coordinator: self)
        originalEraseRecoveryOwner = owner
        temporalAdmission = .draining(owner.id)
        await awaitTemporalProducerDrain(id: owner.id)
        do {
            guard temporalAdmission == .draining(owner.id),
                  temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
                  originalEraseRecoveryOwner === owner else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let acquisition = try registry.makeOriginalEraseRecoveryCheckedAcquisition(
                retainedWriter: owner.writerToken)
            owner.acquisition = acquisition
            let activity = try acquisition.acquire()
            owner.activity = activity
            let root = try StoreTemporalPhysicalRootExclusionV1(
                unacquiredColdRetirementAt: owner.supportURL)
            owner.root = root
            try root.acquireColdRetirement()
            temporalAdmission = .exclusive(owner.id)
            owner.state = .held
            try owner.requireHeld()
            return owner
        } catch {
            temporalAdmission = .maintenance(owner.id)
            owner.state = .uncertain
            throw error
        }
    }

    fileprivate func requireOriginalEraseRecoveryPreOpenOwner(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        activity: GenerationTemporalActivityHandleV1,
        root: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard originalEraseRecoveryOwner === owner,
              temporalAdmission == .exclusive(owner.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              session === owner.source,
              workspaceWriter === owner.writer,
              writerLeaseHandle.token == owner.writerToken,
              writerFence.retainedTemporalRegistry === owner.registry,
              owner.source.generationEpoch == owner.writerToken.epoch else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        try writerLeaseHandle.requireExactRegistry(owner.registry)
        let census = try owner.registry.observeOriginalEraseRecoveryRegistry(
            activity: activity, retainedWriter: owner.writerToken)
        try operation.requireOriginalRecoveryPreOpenCensus(
            census.leases, registry: owner.registry,
            sourceWriter: writerLeaseHandle)
        try root.withOriginalEraseRecoverySupport(at: owner.supportURL) { _ in () }
    }

    fileprivate func closeOriginalEraseRecoveryReadOnly(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        activity: GenerationTemporalActivityHandleV1,
        root: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard originalEraseRecoveryOwner === owner,
              temporalAdmission == .exclusive(owner.id) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let retained = owner.retainedOriginalExclusion {
            // A validation-only release does not release the original
            // operation's EX or reopen producer admission across await.
            try requireRetainedOriginalRecoveryBorrow(owner: owner,
                exclusion: retained, root: root)
            guard activity === retained.activity else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.releaseOriginalRecoveryPreOpenOwner(owner,
                coordinator: self)
            originalEraseRecoveryOwner = nil
            return
        }
        temporalAdmission = .maintenance(owner.id)
        do {
            // The root and Registry EX are the two retained physical owners.
            // A failed checked close cannot reopen producer admission.
            try root.closeCheckedForMaintenance()
            try activity.closeCheckedForOriginalEraseRecovery()
            guard session === owner.source,
                  workspaceWriter === owner.writer,
                  writerLeaseHandle.token == owner.writerToken,
                  writerFence.retainedTemporalRegistry === owner.registry,
                  owner.source.generationEpoch == owner.writerToken.epoch else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try writerLeaseHandle.requireExactRegistry(owner.registry)
            try operation.releaseOriginalRecoveryPreOpenOwner(owner,
                coordinator: self)
            originalEraseRecoveryOwner = nil
            temporalAdmission = .open
        } catch {
            owner.state = .uncertain
            throw error
        }
    }

    fileprivate func closeOriginalEraseRecoveryAfterFirstEffect(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        activity: GenerationTemporalActivityHandleV1,
        root: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        guard originalEraseRecoveryOwner === owner,
              originalRecoveryTargetTransfer == nil,
              temporalAdmission == .exclusive(owner.id),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              session === owner.source,
              workspaceWriter === owner.writer,
              writerLeaseHandle.token == owner.writerToken,
              writerFence.retainedTemporalRegistry === owner.registry,
              let intent = owner.publishedIntentForTargetTransfer,
              intent.phase == .pointerSwitched,
              intent.oldGenerationID == owner.source.generationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        if let retained = owner.retainedOriginalExclusion {
            // The original operation still owns the only EX/G. Its target
            // installation uses the typed old→target writer transition;
            // the maintenance transfer belongs only to a newly acquired
            // recovery observer.
            try requireRetainedOriginalRecoveryBorrow(owner: owner,
                exclusion: retained, root: root)
            guard activity === retained.activity else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.releaseOriginalRecoveryPreOpenOwner(owner,
                coordinator: self)
            originalEraseRecoveryOwner = nil
            return
        }
        temporalAdmission = .maintenance(owner.id)
        do {
            try root.closeCheckedForMaintenance()
            try activity.closeCheckedForOriginalEraseRecovery()
            try writerLeaseHandle.requireExactRegistry(owner.registry)
            try operation.releaseOriginalRecoveryPreOpenOwner(owner,
                coordinator: self)
            originalEraseRecoveryOwner = nil
            originalRecoveryTargetTransfer = OriginalRecoveryTargetTransfer(
                ownerID: owner.id, operation: operation,
                source: owner.source, sourceWriter: owner.writer,
                sourceToken: owner.writerToken, registry: owner.registry,
                targetGenerationID: intent.newGenerationID)
        } catch {
            owner.state = .uncertain
            throw error
        }
    }

    private func requireOriginalRecoveryTargetTransfer(
        operation: EraseRouterOperationV1,
        targetSession: StoreGenerationSession
    ) throws {
        guard let transfer = originalRecoveryTargetTransfer,
              transfer.operation === operation,
              temporalAdmission == .maintenance(transfer.ownerID),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              originalEraseRecoveryOwner == nil,
              session === transfer.source,
              workspaceWriter === transfer.sourceWriter,
              writerLeaseHandle.token == transfer.sourceToken,
              writerFence.retainedTemporalRegistry === transfer.registry,
              targetSession.generationID == transfer.targetGenerationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        try writerLeaseHandle.requireExactRegistry(transfer.registry)
    }

    /// The post-CAS presence checks may reuse only this exact original
    /// operation's checked source proof while producer admission remains in
    /// maintenance. They cannot mint a new source baseline or live old reader.
    func requireOriginalRecoveryTargetTransfer(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        intent: EraseIntentV1
    ) throws {
        try owner.requireUndetachedOriginalRecoveryOperation(operation)
        guard let transfer = originalRecoveryTargetTransfer,
              owner.state == .released,
              owner.publishedIntentForTargetTransfer == intent,
              transfer.ownerID == owner.id,
              transfer.operation === operation,
              transfer.source === owner.source,
              transfer.sourceWriter === owner.writer,
              transfer.sourceToken == owner.writerToken,
              transfer.registry === owner.registry,
              transfer.targetGenerationID == intent.newGenerationID,
              intent.phase == .pointerSwitched,
              temporalAdmission == .maintenance(transfer.ownerID),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              originalEraseRecoveryOwner == nil,
              session === transfer.source,
              workspaceWriter === transfer.sourceWriter,
              writerLeaseHandle.token == transfer.sourceToken,
              writerFence.retainedTemporalRegistry === transfer.registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        try writerLeaseHandle.requireExactRegistry(transfer.registry)
    }

    /// Same-process original retry keeps the original operation's EX through
    /// target installation. Its post-CAS source proof remains tied to that
    /// exact owner rather than the separate maintenance-transfer protocol.
    func requireOriginalRecoveryRetainedSourceContinuation(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        intent: EraseIntentV1
    ) throws {
        try owner.requireUndetachedOriginalRecoveryOperation(operation)
        guard let exclusion = owner.retainedOriginalExclusion,
              owner.state == .released,
              owner.publishedIntentForTargetTransfer == intent,
              intent.phase == .pointerSwitched,
              originalRecoveryTargetTransfer == nil,
              originalEraseRecoveryOwner == nil,
              temporalExclusiveOwner === exclusion,
              temporalAdmission == .exclusive(exclusion.id),
              temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty,
              exclusion.owner === self,
              exclusion.physicalRoot === owner.root,
              exclusion.activity === owner.activity,
              exclusion.registry === owner.registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
#if DEBUG
        originalRecoveryRetainedSourceModelReadsForTesting += 1
#endif
        guard session === owner.source,
              workspaceWriter === owner.writer,
              writerLeaseHandle.token == owner.writerToken,
              writerFence.retainedTemporalRegistry === owner.registry else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        try writerLeaseHandle.requireExactRegistry(owner.registry)
        try exclusion.revalidate()
    }

    /// One synchronous, read-only post-Q proof around a transferred-prior
    /// source read. The released pre-open owner cannot reenter its held path;
    /// the original Router and Registry supply the same retained EX and G.
    func withOriginalRecoveryPostPointerOperationsReproof<Value>(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        intent: EraseIntentV1,
        projection: OriginalRecoveryPostPointerAuxiliaryProjectionV1,
        _ body: () throws -> Value
    ) throws -> Value {
        try projection.requireUndetachedAssociation(operation: operation,
            owner: owner)
#if DEBUG
        projection.recordWrapperEntryForTesting(.continuation)
#endif
        try requireOriginalRecoveryRetainedSourceContinuation(
            owner: owner, operation: operation, intent: intent)
        guard let exclusion = owner.retainedOriginalExclusion,
              let activity = owner.activity,
              let root = owner.root,
              exclusion.owner === self,
              exclusion.registry === owner.registry,
              exclusion.activity === activity,
              exclusion.physicalRoot === root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
#if DEBUG
        projection.recordWrapperEntryForTesting(.sourceStore)
#endif
        let store = try operation.requireOriginalRecoveryProjectedAuxiliaryStore(
            coordinator: self, switched: intent)
        do {
            return try operation.withOriginalRecoveryPostPointerAuxiliaryRead(
                registry: owner.registry, activity: activity,
                store: store, intent: intent, coordinator: self) {
                try root.withOriginalErasePostPointerRetainedSupport(
                    owner: owner, coordinator: self,
                    operation: operation, intent: intent) { support in
#if DEBUG
                    // This is support-body entry after named FD revalidation;
                    // it does not prove every later physical-root check passed.
                    projection.recordWrapperEntryForTesting(.borrowedSupportBody)
#endif
                    try projection.requireProjected(
                        operation: operation, owner: owner, support: support)
#if DEBUG
                    projection.recordWrapperEntryForTesting(.body)
#endif
                    let result = try body()
                    try projection.requireProjected(
                        operation: operation, owner: owner, support: support)
                    return result
                }
            }
        } catch {
            owner.poisonOnUncertainScratch()
            throw error
        }
    }

    private func finishOriginalRecoveryTargetTransferIfPresent(
        operation: EraseRouterOperationV1,
        installedSession: StoreGenerationSession
    ) throws {
        guard let transfer = originalRecoveryTargetTransfer else { return }
        guard transfer.operation === operation,
              temporalAdmission == .maintenance(transfer.ownerID),
              temporalProducerIDs.isEmpty, temporalDrainWaiters.isEmpty,
              originalEraseRecoveryOwner == nil,
              session === installedSession,
              session.generationID == transfer.targetGenerationID,
              erasePreparationInstallation?.operation === operation,
              writerFence.retainedTemporalRegistry === transfer.registry,
              writerLeaseHandle.token.role == .writer,
              writerLeaseHandle.token.epoch.generationID
                == transfer.targetGenerationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireRecoveryExecution(coordinator: self)
        originalRecoveryTargetTransfer = nil
        temporalAdmission = .open
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
    private var uncertainCloseDescriptor: Int32?
    private var coldTerminalUnlockResult: Int32?
    private var coldTerminalUnlockErrno: Int32?
    private var coldTerminalCloseResult: Int32?
    private var coldTerminalCloseErrno: Int32?
    private weak var retainedOriginalRecoveryBorrowOwner:
        StoreOriginalEraseRecoveryPreOpenOwnerV1?

    fileprivate func bindRetainedOriginalRecoveryBorrow(
        _ owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard exclusion.physicalRoot === self,
              owner.retainedOriginalExclusion === exclusion,
              descriptor >= 0, !checkedCloseUncertain,
              !coldAcquisition else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try owner.requireRetainedOriginalPhysicalBorrow(self)
        retainedOriginalRecoveryBorrowOwner = owner
    }

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
            uncertainCloseDescriptor = owned
            checkedCloseUncertain = true; throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

#if DEBUG
    static func unacquiredOriginalEraseShutdown(at url: URL) throws
        -> StoreTemporalPhysicalRootExclusionV1 {
        try StoreTemporalPhysicalRootExclusionV1(unacquiredColdRetirementAt: url)
    }
    func acquireOriginalEraseShutdown() throws { try acquireColdRetirement() }
    func requireHeldOriginalEraseShutdownForExclusiveScratch(at url: URL) throws {
        guard coldAcquisition, coldLockHeld, coldIdentityCaptured,
              !checkedCloseUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try revalidate(applicationSupportURL: url)
    }
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

    /// Forward the ORIGINAL-Erase physical transition's same root-witness
    /// check without acquiring an owner, activity, lock or descriptor.
    func revalidateForOriginalErasePhysicalTransition(applicationSupportURL expected: URL) throws {
        try revalidate(applicationSupportURL: expected)
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

    /// Borrow the already locked Support descriptor only for one synchronous
    /// original-owner auxiliary observation. The caller cannot acquire or
    /// replace this EX, and both edges reprove its held/named inode.
    fileprivate func withHeldOriginalEraseAuxiliarySupport<T>(
        at expected: URL,
        _ body: @MainActor (Int32) throws -> T
    ) throws -> T {
        guard !checkedCloseUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try revalidate(applicationSupportURL: expected)
        let outcome = Result<T, Error> { try body(descriptor) }
        try revalidate(applicationSupportURL: expected)
        return try outcome.get()
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
    fileprivate func requireSchema2ColdSupport(device expectedDevice: dev_t,
        inode expectedInode: ino_t) throws {
        guard !checkedCloseUncertain, descriptor >= 0,
              device == expectedDevice, inode == expectedInode,
              coldAcquisition, coldLockHeld else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try revalidate(applicationSupportURL: applicationSupportURL)
    }

    /// A no-create observation may borrow this already held Support-root FD.
    /// The caller cannot retain the integer beyond its synchronous closure.
    func withOriginalEraseRecoverySupport<Value>(
        at expected: URL, _ body: (Int32) throws -> Value
    ) throws -> Value {
        guard !checkedCloseUncertain else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if !(coldAcquisition && coldLockHeld && coldIdentityCaptured) {
            guard let retainedOriginalRecoveryBorrowOwner else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try retainedOriginalRecoveryBorrowOwner
                .requireRetainedOriginalPhysicalBorrow(self)
        }
        try revalidate(applicationSupportURL: expected)
        let value = try body(descriptor)
        try revalidate(applicationSupportURL: expected)
        if !(coldAcquisition && coldLockHeld && coldIdentityCaptured) {
            guard let retainedOriginalRecoveryBorrowOwner else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try retainedOriginalRecoveryBorrowOwner
                .requireRetainedOriginalPhysicalBorrow(self)
        }
        return value
    }

    /// The original retained EX survives the pre-open owner's one-way
    /// release at Q. Borrow its same Support FD only under the Coordinator's
    /// exact released-owner continuation proof; the ordinary held-owner
    /// borrow remains strict for every other route.
    func withOriginalErasePostPointerRetainedSupport<Value>(
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        coordinator: StoreSessionCoordinator,
        operation: EraseRouterOperationV1,
        intent: EraseIntentV1,
        _ body: (Int32) throws -> Value
    ) throws -> Value {
        try owner.requireUndetachedOriginalRecoveryOperation(operation)
        guard !checkedCloseUncertain,
              owner.root === self,
              owner.retainedOriginalExclusion?.physicalRoot === self else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try coordinator.requireOriginalRecoveryRetainedSourceContinuation(
            owner: owner, operation: operation, intent: intent)
        try revalidate(applicationSupportURL: owner.supportURL)
        let outcome = Result<Value, Error> {
            try body(descriptor)
        }
        try revalidate(applicationSupportURL: owner.supportURL)
        try coordinator.requireOriginalRecoveryRetainedSourceContinuation(
            owner: owner, operation: operation, intent: intent)
        return try outcome.get()
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
            uncertainCloseDescriptor = owned
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

    /// Distinct cold terminal close. Latch and detach before either syscall;
    /// a failed unlock or close leaves its original descriptor retained as
    /// uncertainty and deinit cannot retry a potentially reused integer.
    fileprivate func closeColdTerminalAfterNamespaceRemovalChecked() throws {
        guard coldAcquisition, coldLockHeld, coldIdentityCaptured,
              descriptor >= 0, !checkedCloseUncertain, uncertainCloseDescriptor == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireOperationsAbsent()
        let owned = descriptor
        descriptor = -1
        uncertainCloseDescriptor = owned
        checkedCloseUncertain = true
        let unlock = flock(owned, LOCK_UN)
        let unlockErrno = errno
        coldTerminalUnlockResult = unlock; coldTerminalUnlockErrno = unlockErrno
        guard unlock == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        coldLockHeld = false
        let closed = Darwin.close(owned)
        let closeErrno = errno
        coldTerminalCloseResult = closed; coldTerminalCloseErrno = closeErrno
        guard closed == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        uncertainCloseDescriptor = nil
        checkedCloseUncertain = false
    }

    fileprivate func requireColdTerminalCheckedClosed() throws {
        guard coldAcquisition, coldIdentityCaptured, !coldLockHeld,
              descriptor < 0, !checkedCloseUncertain, uncertainCloseDescriptor == nil,
              coldTerminalUnlockResult == 0, coldTerminalCloseResult == 0,
              coldTerminalUnlockErrno != nil, coldTerminalCloseErrno != nil else {
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

/// Data-only first auxiliary parent owner for an authentic original schema-2
/// P operation. Router retains this object before its first open; a failed
/// scan or ambiguous close remains operation-owned and cannot be recaptured.
/// It never constructs a Store, publishes a roster, or authorizes deletion.
@MainActor
final class StoreOriginalEraseAuxiliaryFirstCaptureOwnerV1 {
    private struct Parent {
        let descriptor: Int32
        let path: URL
        let first: stat?
    }

    private let cachesURL: URL
    private let temporaryURL: URL
    private let observer: EraseSchema2ColdAuxiliaryFirstObserverV1
    private var caches: Parent?
    private var temporary: Parent?
    private var attempted = false
    private var inFlight = false
    private var firstSnapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var rosterCaptureAttempted = false
    private var rosterCaptureInFlight = false
    private var rosterReproofInFlight = false
    private var rosterReproofFailed = false
    private var firstRoster: EraseSchema2ColdAuxiliaryPhysicalRosterV1?
    private var readerStartingSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var readerStartingProjectionFailed = false
    private var readerProjectionAttempted = false
    private var readerProjectionInFlight = false
    private var readerProjectionFailed = false
    private var readerProjectedSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var writerProjectionAttempted = false
    private var writerProjectionInFlight = false
    private var writerProjectionFailed = false
    private var writerProjectedSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var oldCloseProjectionAttempted = false
    private var oldCloseProjectionInFlight = false
    private var oldCloseProjectionFailed = false
    private var oldCloseProjectedSnapshot:
        EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
    private var postwriterBorrowInFlight = false
    private var postwriterBorrowFailed = false

    init(cachesURL: URL, temporaryURL: URL,
         observer: EraseSchema2ColdAuxiliaryFirstObserverV1) throws {
        guard cachesURL.isFileURL, temporaryURL.isFileURL,
              !cachesURL.path.utf8.contains(0),
              !temporaryURL.path.utf8.contains(0) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        self.cachesURL = cachesURL.standardizedFileURL
        self.temporaryURL = temporaryURL.standardizedFileURL
        self.observer = observer
    }

    func captureFirst(
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        try operation.requireOriginalEraseAuxiliaryFirstCaptureOwner(
            self, observer: observer, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation, store: store)
        guard !attempted, !inFlight,
              caches == nil, temporary == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        attempted = true
        inFlight = true
        caches = try openParent(cachesURL) { self.caches = $0 }
        temporary = try openParent(temporaryURL) { self.temporary = $0 }
        guard let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireParent(caches)
        try requireParent(temporary)
        let supportURL = coordinator.originalEraseAuxiliarySupportURL
        let outcome = Result<EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot, Error> {
            try exclusion.physicalRoot.withHeldOriginalEraseAuxiliarySupport(
                at: supportURL) { support in
                try observer.captureFirst(support: support,
                    caches: caches.descriptor,
                    temporary: temporary.descriptor,
                    applicationSupportURL: supportURL)
            }
        }
        try operation.requireOriginalEraseAuxiliaryFirstCaptureOwner(
            self, observer: observer, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation, store: store)
        try requireParent(caches)
        try requireParent(temporary)
        let snapshot = try outcome.get()
        firstSnapshot = snapshot
        inFlight = false
        return snapshot
    }

    func requireFirst() throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        guard attempted, !inFlight, let firstSnapshot,
              let caches, let temporary,
              try observer.firstObservation() == firstSnapshot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireParent(caches)
        try requireParent(temporary)
        return firstSnapshot
    }

    /// The original P operation owns the walker before it borrows any held
    /// parent descriptor. A failed scan stays latched to this owner; it may
    /// not mint a roster from whatever survivors a later call finds.
    func captureFirstPhysicalRoster(
        capture: EraseSchema2OriginalAuxiliaryRosterCaptureV1,
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore
    ) throws -> EraseSchema2ColdAuxiliaryPhysicalRosterV1 {
        let snapshot = try requireFirst()
        try operation.requireOriginalEraseAuxiliaryRosterCapture(
            capture, owner: self, observer: observer,
            snapshot: snapshot, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation, store: store)
        guard !rosterCaptureAttempted, !rosterCaptureInFlight,
              firstRoster == nil, let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        rosterCaptureAttempted = true
        rosterCaptureInFlight = true
        try requireParent(caches)
        try requireParent(temporary)
        let supportURL = coordinator.originalEraseAuxiliarySupportURL
        let outcome = Result<EraseSchema2ColdAuxiliaryPhysicalRosterV1, Error> {
            try exclusion.physicalRoot.withHeldOriginalEraseAuxiliarySupport(
                at: supportURL) { support in
                try capture.captureFirst(intent: intent,
                    preparation: preparation, observer: observer,
                    snapshot: snapshot, support: support,
                    caches: caches.descriptor,
                    temporary: temporary.descriptor)
            }
        }
        try operation.requireOriginalEraseAuxiliaryRosterCapture(
            capture, owner: self, observer: observer,
            snapshot: snapshot, coordinator: coordinator,
            exclusion: exclusion, intent: intent,
            preparation: preparation, store: store)
        try requireParent(caches)
        try requireParent(temporary)
        let roster = try outcome.get()
        firstRoster = roster
        rosterCaptureInFlight = false
        return roster
    }

    /// Store can request this only through the same Router-held original P
    /// seal. This rereads complete first trees through the original EX and
    /// retained parent FDs, never a fresh survivor baseline.
    func requireSameFirstPhysicalRoster(
        capture: EraseSchema2OriginalAuxiliaryRosterCaptureV1,
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2
    ) throws -> EraseSchema2ColdAuxiliaryPhysicalRosterV1 {
        guard rosterCaptureAttempted, !rosterCaptureInFlight,
              !rosterReproofInFlight, !rosterReproofFailed,
              let firstRoster, let caches, let temporary,
              let snapshot = firstSnapshot else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        rosterReproofInFlight = true
        do {
            try operation.requireOriginalAuxiliaryRosterPhysicalReproof(
                capture: capture, owner: self, observer: observer,
                snapshot: snapshot, coordinator: coordinator,
                exclusion: exclusion, intent: intent,
                preparation: preparation)
            try requireParent(caches)
            try requireParent(temporary)
            let supportURL = coordinator.originalEraseAuxiliarySupportURL
            let observed = try exclusion.physicalRoot
                .withHeldOriginalEraseAuxiliarySupport(at: supportURL) { support in
                    try capture.requireSameFirstSourceFacts(intent: intent,
                        preparation: preparation, observer: observer,
                        snapshot: snapshot, support: support,
                        caches: caches.descriptor,
                        temporary: temporary.descriptor)
                }
            try requireParent(caches)
            try requireParent(temporary)
            guard observed.canonicalSHA256 == firstRoster.canonicalSHA256,
                  observed.canonicalBytes == firstRoster.canonicalBytes else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            rosterReproofInFlight = false
            return observed
        } catch {
            rosterReproofFailed = true
            throw error
        }
    }

    /// Normal original Erase has no recovery Scratch projection. Its reader
    /// starts from the genuine unchanged P image, rewalked twice through the
    /// same held parents under EX and the Registry's actual G.
    func requireOriginalReaderStartingUnchanged(
        originalP: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        allocation: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        guard firstSnapshot == originalP,
              readerStartingSnapshot == nil,
              !readerStartingProjectionFailed,
              !readerProjectionAttempted,
              !readerProjectionInFlight,
              !readerProjectionFailed,
              rosterCaptureAttempted, !rosterCaptureInFlight,
              !rosterReproofInFlight, !rosterReproofFailed,
              firstRoster != nil,
              let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            try operation.requireOriginalEraseTargetReaderNormalStartingOwner(
                originalP: originalP, allocation: allocation,
                owner: self, observer: observer, coordinator: coordinator,
                exclusion: exclusion, registry: registry, activity: activity)
            guard try requireFirst() == originalP else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let supportURL = coordinator.originalEraseAuxiliarySupportURL
            try exclusion.physicalRoot.withHeldOriginalEraseAuxiliarySupport(
                at: supportURL) { support in
                try observer.requireUnchanged(support: support,
                    caches: caches.descriptor, temporary: temporary.descriptor)
            }
            try operation.requireOriginalEraseTargetReaderNormalStartingOwner(
                originalP: originalP, allocation: allocation,
                owner: self, observer: observer, coordinator: coordinator,
                exclusion: exclusion, registry: registry, activity: activity)
            guard try requireFirst() == originalP else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            readerStartingSnapshot = originalP
            return originalP
        } catch {
            readerStartingProjectionFailed = true
            throw error
        }
    }

    /// Before any reader-record O_EXCL, rewalk the sealed Scratch-projected
    /// Operations image under the retained EX and the Registry's actual G.
    /// The first P image remains immutable; no survivor is adopted.
    func requireOriginalReaderStartingProjected(
        _ sealed: OriginalRecoveryPostPointerAuxiliaryProjectionV1,
        recoveryOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        originalP: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        allocation: GenerationLeaseAllocationAttemptV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        try sealed.requireUndetachedAssociation(operation: operation,
            owner: recoveryOwner)
        guard firstSnapshot == originalP,
              readerStartingSnapshot == nil,
              !readerStartingProjectionFailed,
              !readerProjectionAttempted,
              !readerProjectionInFlight,
              !readerProjectionFailed,
              let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do {
            try operation.requireOriginalEraseTargetReaderStartingProjectionOwner(
                sealed, recoveryOwner: recoveryOwner,
                allocation: allocation, owner: self,
                coordinator: coordinator, exclusion: exclusion,
                registry: registry, activity: activity)
            try requireParent(caches)
            try requireParent(temporary)
            let supportURL = coordinator.originalEraseAuxiliarySupportURL
            let starting = try exclusion.physicalRoot
                .withHeldOriginalEraseAuxiliarySupport(at: supportURL) { support in
                    try observer.requireOriginalRecoveryReaderStartingImage(
                        sealed, operation: operation, owner: recoveryOwner,
                        support: support, caches: caches.descriptor,
                        temporary: temporary.descriptor)
                }
            try operation.requireOriginalEraseTargetReaderStartingProjectionOwner(
                sealed, recoveryOwner: recoveryOwner,
                allocation: allocation, owner: self,
                coordinator: coordinator, exclusion: exclusion,
                registry: registry, activity: activity)
            try requireParent(caches)
            try requireParent(temporary)
            readerStartingSnapshot = starting
            return starting
        } catch {
            readerStartingProjectionFailed = true
            throw error
        }
    }

    /// The original operation's checked reader publication projects only
    /// generation-leases from the immutable first Operations image. Retain
    /// this attempt before borrowing the same held Support/Cache/Temp parents;
    /// a failed projection cannot be retried from a later survivor image.
    func requireOriginalReaderProjected(
        _ projection: OriginalEraseRetainedTargetReaderProjectionV1,
        allocation: GenerationLeaseAllocationAttemptV1,
        handle: GenerationLeaseHandleV1,
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        #if DEBUG
        FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=coordinator.reader-projection-enter\n".utf8))
        #endif
        guard rosterCaptureAttempted, !rosterCaptureInFlight,
              !rosterReproofInFlight, !rosterReproofFailed,
              firstRoster != nil, firstSnapshot != nil,
              let starting = readerStartingSnapshot,
              !readerStartingProjectionFailed,
              !readerProjectionAttempted, !readerProjectionInFlight,
              !readerProjectionFailed,
              readerProjectedSnapshot == nil,
              let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        readerProjectionAttempted = true
        readerProjectionInFlight = true
        do {
            try operation.requireOriginalEraseTargetReaderProjectionOwner(
                projection, allocation: allocation, handle: handle,
                owner: self, coordinator: coordinator,
                exclusion: exclusion)
            try requireParent(caches)
            try requireParent(temporary)
            #if DEBUG
            FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=coordinator.reader-owner-bound\n".utf8))
            #endif
            let supportURL = coordinator.originalEraseAuxiliarySupportURL
            #if DEBUG
            FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=coordinator.reader-parent-bound\n".utf8))
            #endif
            let projected = try exclusion.physicalRoot
                .withHeldOriginalEraseAuxiliarySupport(at: supportURL) { support in
                    try observer.requireOriginalReaderProjected(
                        projection, starting: starting, support: support,
                        caches: caches.descriptor,
                        temporary: temporary.descriptor)
                }
            try operation.requireOriginalEraseTargetReaderProjectionOwner(
                projection, allocation: allocation, handle: handle,
                owner: self, coordinator: coordinator,
                exclusion: exclusion)
            try requireParent(caches)
            try requireParent(temporary)
            #if DEBUG
            FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=coordinator.reader-observer-complete\n".utf8))
            #endif
            readerProjectedSnapshot = projected
            readerProjectionInFlight = false
            return projected
        } catch {
            #if DEBUG
            FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=coordinator.reader-projection-failed\n".utf8))
            #endif
            readerProjectionFailed = true
            throw error
        }
    }

    func requireOriginalWriterProjected(
        reader: OriginalEraseRetainedTargetReaderProjectionV1,
        writer: OriginalEraseRetainedWriterPublicationProjectionV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1,
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        guard readerProjectedSnapshot != nil,
              let starting = readerStartingSnapshot,
              !readerStartingProjectionFailed,
              !readerProjectionInFlight, !readerProjectionFailed,
              !writerProjectionAttempted, !writerProjectionInFlight,
              !writerProjectionFailed, writerProjectedSnapshot == nil,
              let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        writerProjectionAttempted = true
        writerProjectionInFlight = true
        do {
            try operation.requireOriginalEraseWriterProjectionOwner(
                writer, targetAllocation: targetAllocation,
                targetHandle: targetHandle, owner: self,
                coordinator: coordinator, exclusion: exclusion)
            try requireParent(caches)
            try requireParent(temporary)
            let supportURL = coordinator.originalEraseAuxiliarySupportURL
            let projected = try exclusion.physicalRoot
                .withHeldOriginalEraseAuxiliarySupport(at: supportURL) { support in
                    try observer.requireOriginalWriterProjected(
                        reader: reader, writer: writer,
                        starting: starting, support: support, caches: caches.descriptor,
                        temporary: temporary.descriptor)
                }
            try operation.requireOriginalEraseWriterProjectionOwner(
                writer, targetAllocation: targetAllocation,
                targetHandle: targetHandle, owner: self,
                coordinator: coordinator, exclusion: exclusion)
            try requireParent(caches)
            try requireParent(temporary)
            writerProjectedSnapshot = projected
            writerProjectionInFlight = false
            return projected
        } catch {
            writerProjectionFailed = true
            throw error
        }
    }

    func requireOriginalOldWriterCloseProjected(
        reader: OriginalEraseRetainedTargetReaderProjectionV1,
        writer: OriginalEraseRetainedWriterPublicationProjectionV1,
        release: OriginalEraseRetainedOldWriterReleaseProjectionV1,
        targetAllocation: GenerationWriterAllocationAttemptV1,
        targetHandle: GenerationLeaseHandleV1,
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1
    ) throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        guard writerProjectedSnapshot != nil,
              let starting = readerStartingSnapshot,
              !readerStartingProjectionFailed,
              !writerProjectionInFlight, !writerProjectionFailed,
              !oldCloseProjectionAttempted,
              !oldCloseProjectionInFlight, !oldCloseProjectionFailed,
              oldCloseProjectedSnapshot == nil,
              let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        oldCloseProjectionAttempted = true
        oldCloseProjectionInFlight = true
        do {
            try operation.requireOriginalEraseOldWriterCloseProjectionOwner(
                release, targetAllocation: targetAllocation,
                targetHandle: targetHandle, owner: self,
                coordinator: coordinator, exclusion: exclusion)
            try requireParent(caches)
            try requireParent(temporary)
            let supportURL = coordinator.originalEraseAuxiliarySupportURL
            let projected = try exclusion.physicalRoot
                .withHeldOriginalEraseAuxiliarySupport(at: supportURL) { support in
                    try observer.requireOriginalOldWriterCloseProjected(
                        reader: reader, writer: writer,
                        release: release, starting: starting,
                        support: support,
                        caches: caches.descriptor,
                        temporary: temporary.descriptor)
                }
            try operation.requireOriginalEraseOldWriterCloseProjectionOwner(
                release, targetAllocation: targetAllocation,
                targetHandle: targetHandle, owner: self,
                coordinator: coordinator, exclusion: exclusion)
            try requireParent(caches)
            try requireParent(temporary)
            oldCloseProjectedSnapshot = projected
            oldCloseProjectionInFlight = false
            return projected
        } catch {
            oldCloseProjectionFailed = true
            throw error
        }
    }

    /// Borrow exactly the three parents retained by the original P capture.
    /// The immutable first image and checked reader/writer projections remain
    /// the comparison source; this callback cannot create a survivor baseline.
    func withOriginalErasePostwriterAuxiliaryParents<T>(
        operation: EraseRouterOperationV1,
        coordinator: StoreSessionCoordinator,
        exclusion: StoreTemporalNormalizationExclusionV1,
        policyPermit: OriginalEraseAuxiliaryScratchControlPolicyPermitV1? = nil,
        notificationPolicyPermit:
            OriginalEraseNotificationRootPolicyPermitV1? = nil,
        notificationMarkerPermit:
            OriginalEraseNotificationMarkerPermitV1? = nil,
        notificationRemovalPermit:
            OriginalEraseNotificationRemovalPermitV1? = nil,
        scratchCleanupScope: OriginalEraseScratchCleanupHeldGScopeV1? = nil,
        _ body: @MainActor (Int32, Int32, Int32) throws -> T
    ) throws -> T {
        try operation.requireOriginalErasePostwriterAuxiliaryParentOwner(
            self, coordinator: coordinator, exclusion: exclusion,
            policyPermit: policyPermit,
            notificationPolicyPermit: notificationPolicyPermit,
            notificationMarkerPermit: notificationMarkerPermit,
            notificationRemovalPermit: notificationRemovalPermit,
            scratchCleanupScope: scratchCleanupScope)
        guard oldCloseProjectedSnapshot != nil,
              !oldCloseProjectionInFlight, !oldCloseProjectionFailed,
              !postwriterBorrowInFlight, !postwriterBorrowFailed,
              let caches, let temporary else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        postwriterBorrowInFlight = true
        do {
            try requireParent(caches)
            try requireParent(temporary)
            let value = try exclusion.physicalRoot
                .withHeldOriginalEraseAuxiliarySupport(
                    at: coordinator.originalEraseAuxiliarySupportURL) { support in
                    try body(support, caches.descriptor,
                        temporary.descriptor)
                }
            try operation.requireOriginalErasePostwriterAuxiliaryParentOwner(
                self, coordinator: coordinator, exclusion: exclusion,
            policyPermit: policyPermit,
            notificationPolicyPermit: notificationPolicyPermit,
            notificationMarkerPermit: notificationMarkerPermit,
            notificationRemovalPermit: notificationRemovalPermit,
            scratchCleanupScope: scratchCleanupScope)
            try requireParent(caches)
            try requireParent(temporary)
            postwriterBorrowInFlight = false
            return value
        } catch {
            postwriterBorrowFailed = true
            throw error
        }
    }

    private func openParent(
        _ path: URL, retain: (Parent) -> Void
    ) throws -> Parent {
        let descriptor = Darwin.open(path.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        retain(Parent(descriptor: descriptor, path: path, first: nil))
        var held = stat(), named = stat()
        guard Darwin.fstat(descriptor, &held) == 0,
              Darwin.lstat(path.path, &named) == 0,
              Self.sameFact(held, named),
              held.st_mode & S_IFMT == S_IFDIR,
              held.st_nlink > 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return Parent(descriptor: descriptor, path: path, first: held)
    }

    private func requireParent(_ parent: Parent) throws {
        guard let first = parent.first else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        var held = stat(), named = stat()
        guard Darwin.fstat(parent.descriptor, &held) == 0,
              Darwin.lstat(parent.path.path, &named) == 0,
              Self.sameFact(held, named),
              held.st_dev == first.st_dev,
              held.st_ino == first.st_ino,
              held.st_mode == first.st_mode,
              held.st_uid == first.st_uid,
              held.st_gid == first.st_gid,
              held.st_mode & S_IFMT == S_IFDIR,
              held.st_nlink > 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private static func sameFact(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino
            && a.st_mode == b.st_mode && a.st_nlink == b.st_nlink
            && a.st_uid == b.st_uid && a.st_gid == b.st_gid
            && a.st_size == b.st_size
            && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec
            && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
            && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec
            && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}

/// Schema-2 cold Erase retains the existing Support-root physical exclusion
/// independently of Operations. This remains valid when a historical late
/// recursive cut has already removed Registry and the whole Operations root.
/// It grants no Erase intent, writer, or target authority by itself.
@MainActor
final class EraseSchema2ColdPhysicalExclusionV1 {
    private weak var operation: EraseColdPreparationOperationV1?
    private let applicationSupportURL: URL
    private enum Phase: Equatable {
        case registered, acquiring, held, transferred, uncertain, closed
    }
    private var phase: Phase = .registered
    private var root: StoreTemporalPhysicalRootExclusionV1?
    private var scratchBorrowedParents: ColdEraseScratchBorrowedParentsV1?
    private weak var transferredRetirement: EraseRetirementExclusionV1?

    func transferToColdPostGenerationRetirement(binding: EraseRetirementBindingV1,
        drain: EraseSessionDrainWitnessV1, registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        operation expected: EraseColdPreparationOperationV1)
        throws -> EraseRetirementExclusionV1 {
        guard phase == .held, operation === expected, let actualRoot = root,
              transferredRetirement == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expected.requireColdSchema2ExclusionTransferAdmission(original: self,
            binding: binding, drain: drain, registry: registry, activity: activity)
        try drain.requireDrained(binding: binding)
        try actualRoot.requireEraseSupport(binding.subject)
        if let scratchBorrowedParents { try scratchBorrowedParents.requireCheckedRevoked() }
        // Consume this wrapper before the same handles enter their successor.
        // Failure close and ordinary requireHeld are now permanently disabled.
        phase = .transferred
        root = nil
        let successor = EraseRetirementExclusionV1(schema2ColdBinding: binding,
            drain: drain, registry: registry, activity: activity,
            physicalRoot: actualRoot, original: self, operation: expected)
        transferredRetirement = successor
        try expected.retainColdSchema2TransferredExclusion(successor, original: self,
            binding: binding, drain: drain, registry: registry, activity: activity)
        try successor.requireSupport(binding: binding)
        return successor
    }

    fileprivate func requireTransferredColdBinding(_ successor: EraseRetirementExclusionV1,
        operation expected: EraseColdPreparationOperationV1) throws {
        guard phase == .transferred, root == nil, operation === expected,
              transferredRetirement === successor else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// Lend the same actual held EX and retained Manifest parents. This entry
    /// neither acquires a lock nor copies authority from descriptor integers.
    func withColdScratchBorrowedParents<Value>(
        manifest: EraseSchema2ColdManifestOwnerV1,
        projection: EraseSchema2ColdPostGenerationProjectionV1,
        store: EraseIntentStore, operation: EraseColdPreparationOperationV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1,
        _ body: (ColdEraseScratchBorrowedParentsV1) throws -> Value) throws -> Value {
        guard phase == .held, self.operation === operation,
              scratchBorrowedParents == nil, let root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try scope.requireOrigin(operation: operation, store: store)
        try scope.requireHeld()
        try root.requireSchema2ColdSupport(device: projection.supportFact.device,
            inode: projection.supportFact.inode)
        return try root.withOriginalEraseRecoverySupport(at: applicationSupportURL) { support in
            try manifest.withColdScratchRetainedParents(projection: projection,
                store: store, operation: operation, scope: scope) { caches, temporary, operations in
                let loan = ColdEraseScratchBorrowedParentsV1(exclusion: self,
                    manifest: manifest, operation: operation, scope: scope,
                    support: support, caches: caches, temporary: temporary,
                    operations: operations, supportFact: projection.supportFact)
                scratchBorrowedParents = loan // before any helper capture/IO
                try operation.retainColdScratchBorrowedParents(loan, scope: scope)
                do {
                    try loan.requireBound(operation: operation, scope: scope)
                    let value = try body(loan)
                    try loan.requireBound(operation: operation, scope: scope)
                    try operation.requireColdScratchBorrowedParentsSettled(loan)
                    loan.revokeChecked()
                    return value
                } catch {
                    loan.poison()
                    operation.poisonColdScratchOwner()
                    throw error
                }
            }
        }
    }

    fileprivate func requireColdScratchBorrowedParents(
        _ loan: ColdEraseScratchBorrowedParentsV1,
        operation: EraseColdPreparationOperationV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1,
        supportFact: EraseColdControlLeafFactV1) throws {
        guard phase == .held, self.operation === operation,
              scratchBorrowedParents === loan, let root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try scope.requireNonrecursiveCurrentFrame()
        try root.requireSchema2ColdSupport(device: supportFact.device,
            inode: supportFact.inode)
    }

    init(applicationSupportURL: URL,
         operation: EraseColdPreparationOperationV1) throws {
        guard applicationSupportURL.isFileURL else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        self.operation = operation
    }

    func acquire(expectedDevice: dev_t, expectedInode: ino_t) throws {
        guard phase == .registered, let operation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireSchema2ColdPhysicalExclusion(self)
        phase = .acquiring
        let captured = try StoreTemporalPhysicalRootExclusionV1(
            unacquiredColdRetirementAt: applicationSupportURL)
        root = captured // retain before its first descriptor or lock acquisition
        do {
            try captured.acquireColdRetirement()
            try captured.requireSchema2ColdSupport(device: expectedDevice,
                inode: expectedInode)
            phase = .held
        } catch {
            // The exact acquisition remains held, including a possible EX.
            // A later checked terminal exit must not adopt a new FD number.
            throw error
        }
    }

    func requireHeld(expectedDevice: dev_t, expectedInode: ino_t) throws {
        guard phase == .held, let operation, let root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireSchema2ColdPhysicalExclusion(self)
        try root.requireSchema2ColdSupport(device: expectedDevice,
            inode: expectedInode)
    }

    func requireOperationsAbsent(expectedDevice: dev_t,
        expectedInode: ino_t) throws {
        try requireHeld(expectedDevice: expectedDevice,
            expectedInode: expectedInode)
        try root?.requireOperationsAbsent()
    }

    func closeAfterFailureChecked() throws {
        guard phase == .acquiring || phase == .held, let root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Make every ambiguous unlock/close terminal for this operation.
        phase = .uncertain
        try root.closeColdAcquisitionAfterFailure()
        phase = .closed
    }

    func closeAfterNamespaceRemovalChecked(expectedDevice: dev_t,
        expectedInode: ino_t) throws {
        try requireOperationsAbsent(expectedDevice: expectedDevice,
            expectedInode: expectedInode)
        guard let root else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        phase = .uncertain
        try root.closeCheckedAfterNamespaceRemoval()
        phase = .closed
    }
}


/// Actual same-EX descriptor loan, privately issued by the physical owner.
/// No parent FD is owned by this object; its only effect is permanent lexical
/// fencing. All opened children belong to retained checked engine resources.
@MainActor final class ColdEraseScratchBorrowedParentsV1 {
    let support: Int32
    let caches: Int32
    let temporary: Int32
    let operations: Int32
    private enum State: Equatable { case active, revoked, uncertain }
    private var state: State = .active
    private let exclusion: EraseSchema2ColdPhysicalExclusionV1
    private let manifest: EraseSchema2ColdManifestOwnerV1
    private weak var operation: EraseColdPreparationOperationV1?
    private let scope: ColdEraseScratchCleanupHeldGScopeV1
    private let supportFact: EraseColdControlLeafFactV1

    fileprivate init(exclusion: EraseSchema2ColdPhysicalExclusionV1,
        manifest: EraseSchema2ColdManifestOwnerV1,
        operation: EraseColdPreparationOperationV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1,
        support: Int32, caches: Int32, temporary: Int32,
        operations: Int32, supportFact: EraseColdControlLeafFactV1) {
        self.exclusion = exclusion; self.manifest = manifest
        self.operation = operation; self.scope = scope
        self.support = support; self.caches = caches
        self.temporary = temporary; self.operations = operations
        self.supportFact = supportFact
    }

    func requireBound(operation: EraseColdPreparationOperationV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1) throws {
        do {
            guard state == .active, self.operation === operation, self.scope === scope else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireColdScratchBorrowedParents(self, scope: scope)
            try exclusion.requireColdScratchBorrowedParents(self, operation: operation,
                scope: scope, supportFact: supportFact)
            try manifest.requireColdScratchRetainedParents(support: support,
                caches: caches, temporary: temporary, operations: operations,
                operation: operation, scope: scope)
            try scope.requireNonrecursiveCurrentFrame()
        } catch { poison(); throw error }
    }

    fileprivate func revokeChecked() { state = .revoked }
    fileprivate func requireCheckedRevoked() throws {
        guard state == .revoked else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
    }
    /// Revocation is a one-way lexical fence. This join uses the actual retained
    /// loan and owner identities; revoked parent descriptors are never re-read.
    func requireCheckedColdScratchLoanRevoked(
        operation: EraseColdPreparationOperationV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1) throws {
        guard state == .revoked, self.operation === operation, self.scope === scope else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
    fileprivate func poison() {
        state = .uncertain
        operation?.poisonColdScratchOwner()
        scope.poisonOnUncertainCleanup()
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
    private weak var schema2ColdOriginal: EraseSchema2ColdPhysicalExclusionV1?
    private weak var schema2ColdOperation: EraseColdPreparationOperationV1?
    private var isSchema2ColdTransfer = false
    private var coldTerminalReleaseStarted = false
    private weak var coldTerminalReleaseProof: ColdEraseSchema2TerminalReleaseProofV1?
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

    fileprivate init(schema2ColdBinding binding: EraseRetirementBindingV1,
        drain: EraseSessionDrainWitnessV1, registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        physicalRoot: StoreTemporalPhysicalRootExclusionV1,
        original: EraseSchema2ColdPhysicalExclusionV1,
        operation: EraseColdPreparationOperationV1) {
        self.binding = binding; self.drain = drain; writer = .absentAtColdAdmission
        self.registry = registry; self.activity = activity; self.physicalRoot = physicalRoot
        schema2ColdOriginal = original; schema2ColdOperation = operation
        isSchema2ColdTransfer = true
    }
    /// Exact comparison DATA for a pre-detach retry. This cannot authorize
    /// model drain, resource close, deletion or a second exclusion transfer.
    fileprivate func requireOriginalRecoveryImageTransfer(
        binding expected: EraseRetirementBindingV1,
        originalExclusion: StoreTemporalNormalizationExclusionV1
    ) throws {
        guard case .retained = writer, binding == expected,
              registry === originalExclusion.registry,
              activity === originalExclusion.activity,
              physicalRoot === originalExclusion.physicalRoot,
              originalExclusion.owner == nil, originalExclusion.writer == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
    fileprivate func requireColdAcquisitionRetry() throws {
        guard !isSchema2ColdTransfer, case .absentAtColdAdmission = writer, !released, !writerClosed, !retirementStarted, !coldFailureClosing,
              closedReaderIDs.isEmpty, closedAllocationIDs.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireLiveRegistry(binding: binding)
    }
    fileprivate func closeColdBeforeRetirement() throws {
        guard !isSchema2ColdTransfer, case .absentAtColdAdmission = writer, !retirementStarted else {
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
        if isSchema2ColdTransfer {
            guard let schema2ColdOperation, let schema2ColdOriginal else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try schema2ColdOriginal.requireTransferredColdBinding(self, operation: schema2ColdOperation)
            try schema2ColdOperation.requireColdSchema2TransferredExclusion(self,
                original: schema2ColdOriginal, binding: binding, drain: drain,
                registry: registry, activity: activity)
        }
        try physicalRoot.requireEraseSupport(binding.subject)
    }
    func requireLiveRegistry(binding expected: EraseRetirementBindingV1) throws {
        try requireSupport(binding: expected)
        if isSchema2ColdTransfer {
            guard let schema2ColdOperation else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            _ = try registry.observeColdSchema2RetirementRegistry(operation: schema2ColdOperation,
                activity: activity, exclusion: self, binding: binding, witness: drain)
            return
        }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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

    /// Continuous schema-2 EX release has its own genuine terminal proof.
    /// It cannot enter any Original Manifest/adoption or maintenance wrapper.
    @MainActor
    func releaseColdSchema2AfterNamespaceRemoval(proof: ColdEraseSchema2TerminalReleaseProofV1) throws {
        guard isSchema2ColdTransfer, case .absentAtColdAdmission = writer,
              !released, !coldFailureClosing, !coldTerminalReleaseStarted,
              schema2ColdOriginal != nil, schema2ColdOperation != nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try proof.requireBeforeExRelease(exclusion: self, registry: registry,
            activity: activity, binding: binding, witness: drain)
        try physicalRoot.requireEraseSupport(binding.subject)
        try physicalRoot.requireOperationsAbsent()
        coldTerminalReleaseStarted = true // permanently before activity/EX IO
        coldTerminalReleaseProof = proof
        try activity.closeColdSchema2AfterNamespaceRemoval(proof: proof,
            exclusion: self, binding: binding, witness: drain)
        try activity.requireColdSchema2TerminalCheckedClosed(proof: proof)
        try physicalRoot.requireOperationsAbsent()
        try physicalRoot.closeColdTerminalAfterNamespaceRemovalChecked()
        try physicalRoot.requireColdTerminalCheckedClosed()
        released = true
        try proof.recordCheckedExRelease(exclusion: self)
    }

    @MainActor
    func requireColdTerminalReleased(proof: ColdEraseSchema2TerminalReleaseProofV1) throws {
        guard isSchema2ColdTransfer, released, coldTerminalReleaseStarted,
              coldTerminalReleaseProof === proof, !coldFailureClosing else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try activity.requireColdSchema2TerminalCheckedClosed(proof: proof)
        try physicalRoot.requireColdTerminalCheckedClosed()
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        guard proof.binding == binding, registry === expected,
              released, postRetiredColdClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    func requirePostRetiredReadyForTesting(
        proof: ErasedRegistryRetirementProofV1,
        registry expected: GenerationLeaseRegistryV1
    ) throws {
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        guard proof.binding == binding, registry === expected,
              !released, !postRetiredColdClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireNoLeasesAfterDrain(proof: drain)
    }

    func abandonAfterNamespaceRemovalForTesting(binding expected: EraseRetirementBindingV1) throws {
        guard !isSchema2ColdTransfer else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
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

/// One original Erase Search publication. Router retains this object before
/// the first effect. The complete Search tree comes from the durable original
/// P auxiliary roster; no current survivor tree can become its baseline.
/// All filesystem work is synchronous under the retained Support EX, Registry
/// G, and the Search publication fence. A failed write/close stays here.
@MainActor
final class OriginalEraseAuxiliarySearchWriterV1 {
    private enum Stage: Equatable { case retained, inFlight, published, uncertain }
    private let firstTree: EraseSchema2ColdAuxiliaryPhysicalRosterV1.Tree
    private let supportURL: URL
    private let firstSupportNames: [String]
    private let firstSupportFact: String
    private let supportDevice: Int64
    private let supportInode: UInt64
    private let supportMode: UInt32
    private let supportUser: UInt32
    private let supportGroup: UInt32
    private let io = EraseAbortCheckedSnapshotIOV1()
    private var policyUncertainDescriptors: [Int32] = []
    private var stage: Stage = .retained
    private var rootPolicyDisposition:
        ProtectedFileVerificationDispositionV1?
    private var filePolicyDisposition:
        ProtectedFileVerificationDispositionV1?
    private var canonicalPolicyDisposition:
        ProtectedFileVerificationDispositionV1?
    private var createdRootStableFact: String?
    private(set) var publishedBytes: Data?
    private(set) var projectedNodes:
        [EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node]?
    private(set) var projectedSupportFact: String?

    init(firstRoster: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
         supportURL: URL) throws {
        guard supportURL.isFileURL,
              let search = firstRoster.record.trees.first(where: {
                  $0.key == "support/" + LocalSearchIndexStoreV1.directoryName
              }),
              search.state == "present" || search.state == "absent",
              !((search.nodes ?? []).contains {
                  $0.path == ".projection.json.erase-next"
              }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        firstTree = search
        self.supportURL = supportURL.standardizedFileURL
        firstSupportNames = firstRoster.record.firstSupportNames
        firstSupportFact = firstRoster.record.firstSupportFact
        supportDevice = firstRoster.record.supportDevice
        supportInode = firstRoster.record.supportInode
        supportMode = firstRoster.record.supportMode
        supportUser = firstRoster.record.supportUser
        supportGroup = firstRoster.record.supportGroup
    }

    func requireRetained(firstRoster: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
                         supportURL expectedURL: URL) throws {
        guard stage == .retained,
              expectedURL.standardizedFileURL == supportURL,
              firstRoster.record.trees.first(where: {
                  $0.key == "support/" + LocalSearchIndexStoreV1.directoryName
              }) == firstTree,
              policyUncertainDescriptors.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try io.requireSettled()
    }

    /// Called once from the Search fence while the original operation holds
    /// G and borrows its first Support descriptor. No actor hop occurs while
    /// these locks are held. The returned bytes are the actual checked file
    /// readback, not an authorization inferred from an encoded envelope.
    func publishEmpty(_ emptyBytes: Data, supportFD: Int32) throws -> Data {
        guard stage == .retained, !emptyBytes.isEmpty,
              emptyBytes.count <= LocalSearchIndexStoreV1.maximumStoreBytes,
              policyUncertainDescriptors.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        stage = .inFlight
        do {
            try requireSupport(supportFD, searchCreated: false)
            guard try fullFact(supportFD) == firstSupportFact else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try requireFirstTree(supportFD: supportFD)
            let rootName = LocalSearchIndexStoreV1.directoryName
            let rootURL = supportURL.appendingPathComponent(rootName,
                isDirectory: true)
            if firstTree.state == "absent" {
                guard Darwin.mkdirat(supportFD, rootName, 0o700) == 0,
                      Darwin.fsync(supportFD) == 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                var created = stat()
                guard Darwin.fstatat(supportFD, rootName, &created,
                    AT_SYMLINK_NOFOLLOW) == 0,
                      created.st_mode & S_IFMT == S_IFDIR,
                      created.st_uid == Darwin.getuid(),
                      created.st_gid == Darwin.getgid(),
                      createdRootStableFact == nil else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                createdRootStableFact = stableDirectoryFact(created)
                try requireSupport(supportFD, searchCreated: true)
            }
            let after = try io.withOpen(parent: supportFD, name: rootName,
                flags: O_RDONLY | O_DIRECTORY | O_NONBLOCK) { rootFD in
                try requireRootIdentity(rootFD: rootFD,
                    supportFD: supportFD)
                rootPolicyDisposition = try requireRootPolicy(rootFD: rootFD,
                    supportFD: supportFD, rootURL: rootURL)
                let tempName = ".projection.json.erase-next"
                let canonicalName = LocalSearchIndexStoreV1.fileName
                let tempURL = rootURL.appendingPathComponent(tempName)
                try requireAbsent(parent: rootFD, name: tempName)
                try io.withOpen(parent: rootFD, name: tempName,
                    flags: O_WRONLY | O_CREAT | O_EXCL | O_NONBLOCK,
                    mode: 0o600) { temporaryFD in
                    try writeAll(emptyBytes, to: temporaryFD)
                    guard Darwin.fsync(temporaryFD) == 0 else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                }
                guard Darwin.fsync(rootFD) == 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try requireNamedBytes(emptyBytes, parent: rootFD,
                    name: tempName)
                filePolicyDisposition = try ProtectedFilePolicyV1
                    .applyAndVerifyEraseColdPrivateWithCheckedClose(
                        .searchIndex, at: tempURL,
                        retainUncertainDescriptor: { value in
                            self.policyUncertainDescriptors.append(value)
                        }, authorityCheck: {
                            try self.requireSupport(supportFD,
                                searchCreated: self.firstTree.state == "absent")
                            try self.requireRootIdentity(rootFD: rootFD,
                                supportFD: supportFD)
                            try self.requireNamedBytes(emptyBytes,
                                parent: rootFD, name: tempName)
                        })
                try requireNamedBytes(emptyBytes, parent: rootFD,
                    name: tempName)
                try requireSupport(supportFD,
                    searchCreated: firstTree.state == "absent")
                try requireRootIdentity(rootFD: rootFD,
                    supportFD: supportFD)
                try requireUnchangedFirstChildren(
                    supportFD: supportFD, allowingTemporary: tempName)
                var temporaryFact = stat()
                guard Darwin.fstatat(rootFD, tempName,
                    &temporaryFact, AT_SYMLINK_NOFOLLOW) == 0,
                      temporaryFact.st_mode & S_IFMT == S_IFREG,
                      temporaryFact.st_nlink == 1 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                guard Darwin.renameat(rootFD, tempName,
                    rootFD, canonicalName) == 0,
                      Darwin.fsync(rootFD) == 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try requireAbsent(parent: rootFD, name: tempName)
                var canonicalFact = stat()
                guard Darwin.fstatat(rootFD, canonicalName,
                    &canonicalFact, AT_SYMLINK_NOFOLLOW) == 0,
                      canonicalFact.st_dev == temporaryFact.st_dev,
                      canonicalFact.st_ino == temporaryFact.st_ino,
                      canonicalFact.st_mode == temporaryFact.st_mode,
                      canonicalFact.st_nlink == 1 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try requireNamedBytes(emptyBytes, parent: rootFD,
                    name: canonicalName)
                try requireRootIdentity(rootFD: rootFD,
                    supportFD: supportFD)
                let canonicalURL = rootURL.appendingPathComponent(
                    canonicalName)
                let canonicalWitness = try stableNamedFileWitness(
                    emptyBytes, parent: rootFD, name: canonicalName)
                canonicalPolicyDisposition = try ProtectedFilePolicyV1
                    .verifyEraseColdTemporalPolicyWithCheckedRequest(
                        .searchIndex, at: canonicalURL,
                        retainUncertainDescriptor: { value in
                            self.policyUncertainDescriptors.append(value)
                        }, unchangedWitness: {
                            let observed = try self.stableNamedFileWitness(
                                emptyBytes, parent: rootFD,
                                name: canonicalName)
                            guard observed == canonicalWitness else {
                                throw GenerationLeaseRegistryFailureV1
                                    .uncertainOwner
                            }
                            return observed
                        })
                try requireRootIdentity(rootFD: rootFD,
                    supportFD: supportFD)
                return try requireProjectedTree(
                    supportFD: supportFD, canonicalBytes: emptyBytes)
            }
            try io.requireSettled()
            try requireSupport(supportFD,
                searchCreated: firstTree.state == "absent")
            guard policyUncertainDescriptors.isEmpty else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            projectedSupportFact = try fullFact(supportFD)
            projectedNodes = after
            publishedBytes = emptyBytes
            stage = .published
            return emptyBytes
        } catch {
            stage = .uncertain
            throw error
        }
    }

    func requirePublished(_ expectedBytes: Data,
                          supportFD: Int32) throws {
        guard stage == .published,
              publishedBytes == expectedBytes,
              let projectedNodes,
              let projectedSupportFact,
              rootPolicyDisposition != nil,
              filePolicyDisposition != nil,
              canonicalPolicyDisposition != nil,
              policyUncertainDescriptors.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try io.requireSettled()
        try requireSupport(supportFD,
            searchCreated: firstTree.state == "absent")
        guard try fullFact(supportFD) == projectedSupportFact else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard try requireProjectedTree(supportFD: supportFD,
                    canonicalBytes: expectedBytes) == projectedNodes else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private func requireFirstTree(supportFD: Int32) throws {
        let name = LocalSearchIndexStoreV1.directoryName
        if firstTree.state == "absent" {
            try requireAbsent(parent: supportFD, name: name)
            return
        }
        let (digest, nodes) = try observeTree(supportFD: supportFD)
        guard digest == firstTree.digest,
              nodes == firstTree.nodes else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private func requireRootIdentity(rootFD: Int32,
                                     supportFD: Int32) throws {
        var held = stat(), named = stat()
        guard Darwin.fstat(rootFD, &held) == 0,
              Darwin.fstatat(supportFD,
                  LocalSearchIndexStoreV1.directoryName,
                  &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_mode & S_IFMT == S_IFDIR,
              held.st_dev == named.st_dev,
              held.st_ino == named.st_ino,
              held.st_mode == named.st_mode,
              held.st_uid == named.st_uid,
              held.st_gid == named.st_gid,
              held.st_uid == Darwin.getuid(),
              held.st_gid == Darwin.getgid() else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if firstTree.state == "present" {
            guard let root = firstTree.nodes?.first else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard stableFact(root.fact, matches: held),
                  let firstRootFact = firstTree.rootFact,
                  firstStableRootFact(firstRootFact,
                    matches: held) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        } else if firstTree.state == "absent" {
            guard let createdRootStableFact,
                  createdRootStableFact
                    == stableDirectoryFact(held) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
    }

    private func requireSupport(_ descriptor: Int32,
                                searchCreated: Bool) throws {
        var held = stat(), named = stat()
        guard Darwin.fstat(descriptor, &held) == 0,
              Darwin.lstat(supportURL.path, &named) == 0,
              held.st_mode & S_IFMT == S_IFDIR,
              held.st_dev == named.st_dev,
              held.st_ino == named.st_ino,
              held.st_mode == named.st_mode,
              held.st_uid == named.st_uid,
              held.st_gid == named.st_gid,
              Int64(held.st_dev) == supportDevice,
              UInt64(held.st_ino) == supportInode,
              UInt32(held.st_mode) == supportMode,
              UInt32(held.st_uid) == supportUser,
              UInt32(held.st_gid) == supportGroup else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let names = try io.names(in: descriptor)
        let expected = searchCreated
            ? Array(Set(firstSupportNames).union([
                LocalSearchIndexStoreV1.directoryName])).sorted()
            : firstSupportNames
        guard names == expected,
              projectedLinks(first: firstSupportFact,
                  firstCount: firstSupportNames.count,
                  currentCount: names.count,
                  actual: UInt64(held.st_nlink),
                  linkIndex: 5) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private func fullFact(_ descriptor: Int32) throws -> String {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0,
              value.st_mode & S_IFMT == S_IFDIR else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return [String(value.st_dev), String(value.st_ino),
                String(value.st_mode), String(value.st_uid),
                String(value.st_gid), String(value.st_nlink),
                String(value.st_size),
                String(value.st_mtimespec.tv_sec),
                String(value.st_mtimespec.tv_nsec),
                String(value.st_ctimespec.tv_sec),
                String(value.st_ctimespec.tv_nsec)]
            .joined(separator: "|")
    }

    private func requireRootPolicy(rootFD: Int32,
                                   supportFD: Int32,
                                   rootURL: URL) throws
        -> ProtectedFileVerificationDispositionV1 {
        let witness = try stableDirectoryWitness(rootFD)
        let check: () throws -> String = {
            try self.requireRootIdentity(rootFD: rootFD,
                supportFD: supportFD)
            let current = try self.stableDirectoryWitness(rootFD)
            guard current == witness else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return current
        }
        if firstTree.state == "absent" {
            let disposition = try ProtectedFilePolicyV1
                .applyAndVerifyEraseColdPrivateWithCheckedClose(
                    .stagingDirectory, at: rootURL,
                    retainUncertainDescriptor: { value in
                        self.policyUncertainDescriptors.append(value)
                    }, authorityCheck: { _ = try check() })
            guard policyUncertainDescriptors.isEmpty else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return disposition
        } else {
            let disposition = try ProtectedFilePolicyV1
                .verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .stagingDirectory, at: rootURL,
                    retainUncertainDescriptor: { value in
                        self.policyUncertainDescriptors.append(value)
                    }, unchangedWitness: check)
            guard policyUncertainDescriptors.isEmpty else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return disposition
        }
    }

    private func stableDirectoryWitness(_ descriptor: Int32) throws -> String {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0,
              value.st_mode & S_IFMT == S_IFDIR else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return stableDirectoryFact(value)
    }

    private func stableDirectoryFact(_ value: stat) -> String {
        [String(value.st_dev), String(value.st_ino),
                String(value.st_mode), String(value.st_uid),
                String(value.st_gid)].joined(separator: "|")
    }

    private func stableFact(_ encoded: String,
                            matches value: stat) -> Bool {
        let fields = encoded.split(separator: "|",
            omittingEmptySubsequences: false)
        guard fields.count == 9 else { return false }
        return fields[0] == Substring(String(value.st_dev))
            && fields[1] == Substring(String(value.st_ino))
            && fields[2] == Substring(String(value.st_mode))
    }

    private func firstStableRootFact(_ encoded: String,
                                     matches value: stat) -> Bool {
        let fields = encoded.split(separator: "|",
            omittingEmptySubsequences: false)
        guard fields.count == 11 else { return false }
        return fields[0] == Substring(String(value.st_dev))
            && fields[1] == Substring(String(value.st_ino))
            && fields[2] == Substring(String(value.st_mode))
            && fields[3] == Substring(String(value.st_uid))
            && fields[4] == Substring(String(value.st_gid))
    }

    private func requireAbsent(parent: Int32, name: String) throws {
        var named = stat()
        guard Darwin.fstatat(parent, name, &named,
            AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor,
                    base.advanced(by: offset), buffer.count - offset)
                if written > 0 { offset += written }
                else if written < 0 && errno == EINTR { continue }
                else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            }
        }
    }

    private func requireNamedBytes(_ expected: Data,
                                   parent: Int32, name: String) throws {
        try io.withOpen(parent: parent, name: name,
            flags: O_RDONLY | O_NONBLOCK) { descriptor in
            var held = stat(), named = stat()
            guard Darwin.fstat(descriptor, &held) == 0,
                  Darwin.fstatat(parent, name, &named,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  held.st_mode & S_IFMT == S_IFREG,
                  held.st_dev == named.st_dev,
                  held.st_ino == named.st_ino,
                  held.st_mode == named.st_mode,
                  held.st_mode & 0o777 == 0o600,
                  held.st_uid == named.st_uid,
                  held.st_gid == named.st_gid,
                  held.st_nlink == 1, named.st_nlink == 1,
                  held.st_size == off_t(expected.count),
                  named.st_size == held.st_size else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var actual = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.read(descriptor, $0.baseAddress, $0.count)
                }
                if count > 0 {
                    actual.append(contentsOf: buffer.prefix(count))
                    guard actual.count <= expected.count else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                } else if count == 0 { break }
                else if errno != EINTR {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            guard actual == expected,
                  Darwin.fstat(descriptor, &held) == 0,
                  Darwin.fstatat(parent, name, &named,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  held.st_dev == named.st_dev,
                  held.st_ino == named.st_ino,
                  held.st_size == off_t(expected.count) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
    }

    private func stableNamedFileWitness(_ expected: Data,
        parent: Int32, name: String) throws -> String {
        try requireNamedBytes(expected, parent: parent, name: name)
        var value = stat()
        guard Darwin.fstatat(parent, name, &value,
            AT_SYMLINK_NOFOLLOW) == 0,
              value.st_mode & S_IFMT == S_IFREG,
              value.st_nlink == 1 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return [String(value.st_dev), String(value.st_ino),
                String(value.st_mode), String(value.st_uid),
                String(value.st_gid), String(value.st_size),
                String(value.st_mtimespec.tv_sec),
                String(value.st_mtimespec.tv_nsec)]
            .joined(separator: "|")
    }

    private func observeTree(supportFD: Int32) throws
        -> (String, [EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node]) {
        var nodes: [EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node] = []
        let digest = try io.postRetiredTree(parent: supportFD,
            name: LocalSearchIndexStoreV1.directoryName,
            observeNode: {
                path, kind, fact, members, sha in
                nodes.append(.init(path: path, kind: kind,
                    fact: fact, members: members, sha256: sha))
            })
        nodes.sort {
            $0.path.utf8.lexicographicallyPrecedes($1.path.utf8)
        }
        return (digest, nodes)
    }

    private func requireUnchangedFirstChildren(
        supportFD: Int32, allowingTemporary temp: String
    ) throws {
        let (_, nodes) = try observeTree(supportFD: supportFD)
        guard let first = firstTree.nodes,
              nodes.first?.path == "" else {
            if firstTree.state == "absent",
               nodes.map(\.path) == ["", temp],
               nodes.first?.kind == "directory",
               nodes.last?.kind == "file",
               let links = nodes.first.flatMap({ linkCount($0.fact) }),
               links == 2 || links == 3 { return }
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let byPath = Dictionary(uniqueKeysWithValues:
            nodes.map { ($0.path, $0) })
        for node in first where !node.path.isEmpty {
            guard byPath[node.path] == node else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        guard Set(nodes.map(\.path)) == Set(first.map(\.path)).union([temp]),
              let initialRoot = first.first,
              let currentRoot = nodes.first,
              sameStableDirectoryFact(initialRoot.fact,
                currentRoot.fact),
              let links = linkCount(currentRoot.fact),
              projectedLinks(first: initialRoot.fact,
                  firstCount: initialRoot.members?.count ?? 0,
                  currentCount: currentRoot.members?.count ?? 0,
                  actual: links, linkIndex: 3) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    private func requireProjectedTree(supportFD: Int32,
        canonicalBytes: Data) throws
        -> [EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node] {
        try io.withOpen(parent: supportFD,
            name: LocalSearchIndexStoreV1.directoryName,
            flags: O_RDONLY | O_DIRECTORY | O_NONBLOCK) { rootFD in
            try requireRootIdentity(rootFD: rootFD, supportFD: supportFD)
        }
        let (_, nodes) = try observeTree(supportFD: supportFD)
        let first = firstTree.nodes ?? []
        let byPath = Dictionary(uniqueKeysWithValues:
            nodes.map { ($0.path, $0) })
        let canonical = LocalSearchIndexStoreV1.fileName
        let expectedPaths = Set(first.map(\.path)).union(["", canonical])
        guard Set(nodes.map(\.path)) == expectedPaths,
              let root = byPath[""],
              let file = byPath[canonical],
              file.kind == "file",
              file.sha256 == StoreMigrationCanonicalJSONV1
                .sha256(canonicalBytes),
              (firstTree.state == "absent"
                || (first.first.map { initialRoot in
                    sameStableDirectoryFact(initialRoot.fact, root.fact)
                    && linkCount(root.fact).map { links in
                        projectedLinks(first: initialRoot.fact,
                            firstCount: initialRoot.members?.count ?? 0,
                            currentCount: root.members?.count ?? 0,
                            actual: links, linkIndex: 3)
                    } == true
                } ?? false)) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        for node in first where !node.path.isEmpty
            && node.path != canonical {
            guard byPath[node.path] == node else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        if firstTree.state == "absent" {
            guard root.kind == "directory",
                  let links = linkCount(root.fact),
                  links == 2 || links == 3 else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try io.withOpen(parent: supportFD,
            name: LocalSearchIndexStoreV1.directoryName,
            flags: O_RDONLY | O_DIRECTORY | O_NONBLOCK) { rootFD in
            try requireRootIdentity(rootFD: rootFD, supportFD: supportFD)
        }
        return nodes
    }

    private func sameStableDirectoryFact(_ before: String,
        _ after: String) -> Bool {
        let lhs = before.split(separator: "|",
            omittingEmptySubsequences: false)
        let rhs = after.split(separator: "|",
            omittingEmptySubsequences: false)
        guard lhs.count == 9, rhs.count == 9 else { return false }
        return [0, 1, 2].allSatisfy { lhs[$0] == rhs[$0] }
    }

    private func linkCount(_ fact: String) -> UInt64? {
        let fields = fact.split(separator: "|",
            omittingEmptySubsequences: false)
        guard fields.count == 9 else { return nil }
        return UInt64(fields[3])
    }

    private func projectedLinks(first: String,
        firstCount: Int, currentCount: Int,
        actual: UInt64, linkIndex: Int) -> Bool {
        let fields = first.split(separator: "|",
            omittingEmptySubsequences: false)
        guard fields.count == (linkIndex == 5 ? 11 : 9),
              let original = UInt64(fields[linkIndex]),
              original == 2 || original == 2 + UInt64(firstCount) else {
            return false
        }
        if original == 2 && actual == 2 { return true }
        return original == 2 + UInt64(firstCount)
            && actual == 2 + UInt64(currentCount)
    }
}

extension StoreSessionCoordinator {
    /// Lends only the first, still locked Support descriptor to the synchronous
    /// checked Search publisher. Router and Registry hold the same original
    /// operation/EX/G; this helper cannot open a new root or acquire EX.
    func withOriginalEraseAuxiliarySearchSupport<T>(
        exclusion: StoreTemporalNormalizationExclusionV1,
        _ body: (Int32) throws -> T
    ) throws -> T {
        guard originalEraseAuxiliarySupportURL.isFileURL else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try exclusion.physicalRoot
            .withHeldOriginalEraseAuxiliarySupport(
                at: originalEraseAuxiliarySupportURL, body)
    }
}

// COMPLETED_SESSION_LIFETIME_COORDINATOR_DATA_V1_BEGIN
extension StoreSessionCoordinator {
    func retainCompletedSessionLifetimeOwnerBeforeReadyJoin(
        _ owner: ColdEraseSchema2CompletedSessionLifetimeOwnerV1) throws {
        guard completedSessionLifetimeOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        completedSessionLifetimeOwner = owner // before all fallible DATA joins
    }
    func requireCompletedSessionLifetimeCoordinatorData(
        _ owner: ColdEraseSchema2CompletedSessionLifetimeOwnerV1,
        session expectedSession: StoreGenerationSession, writer expectedWriter: WorkspaceWriterV1,
        writerHandle expectedHandle: GenerationLeaseHandleV1,
        registry: GenerationLeaseRegistryV1, factory: StoreGenerationFactory) throws {
        guard completedSessionLifetimeOwner === owner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireCompletedSchema2StartupAssociation(session: expectedSession,
            writer: expectedWriter, writerHandle: expectedHandle, registry: registry, factory: factory)
    }
}
// COMPLETED_SESSION_LIFETIME_COORDINATOR_DATA_V1_END

// COMPLETED_SESSION_CURRENT_COORDINATOR_V1_BEGIN
extension StoreSessionCoordinator {
    struct CompletedCurrentSessionComponentsV1 {
        let session: StoreGenerationSession
        let writer: WorkspaceWriterV1
        let writerHandle: GenerationLeaseHandleV1
        let fence: StaleWriterFenceV1
        let factory: StoreGenerationFactory
    }
    func requireCompletedSessionCurrentCoordinatorComponents(
        _ owner: ColdEraseSchema2CompletedSessionLifetimeOwnerV1,
        registry: GenerationLeaseRegistryV1, factory: StoreGenerationFactory) throws -> CompletedCurrentSessionComponentsV1 {
        try requireCompletedSessionCurrentCoordinatorData(owner, session: session,
            writer: workspaceWriter, writerHandle: writerLeaseHandle, fence: writerFence,
            registry: registry, factory: factory)
        return CompletedCurrentSessionComponentsV1(session: session, writer: workspaceWriter,
            writerHandle: writerLeaseHandle, fence: writerFence, factory: generationFactory)
    }
    func requireCompletedSessionCurrentCoordinatorData(
        _ owner: ColdEraseSchema2CompletedSessionLifetimeOwnerV1,
        session expectedSession: StoreGenerationSession, writer expectedWriter: WorkspaceWriterV1,
        writerHandle expectedHandle: GenerationLeaseHandleV1, fence expectedFence: StaleWriterFenceV1,
        registry: GenerationLeaseRegistryV1, factory: StoreGenerationFactory) throws {
        guard completedSessionLifetimeOwner === owner, session === expectedSession,
              workspaceWriter === expectedWriter, writerLeaseHandle === expectedHandle,
              writerFence === expectedFence, writerFence.retainedTemporalRegistry === registry,
              generationFactory.sharesRegistryProvider(with: factory),
              generationFactory.restoreApplicationSupportURL == factory.restoreApplicationSupportURL,
              writerFence.writerLeaseToken == expectedHandle.token,
              writerFence.expectedGenerationEpoch == expectedSession.generationEpoch,
              expectedHandle.token.role == .writer, expectedHandle.token.ownerID == registry.ownerID,
              expectedHandle.token.epoch == expectedSession.generationEpoch,
              workspaceIdentity == expectedSession.workspaceIdentity,
              generationID == expectedSession.generationID else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // Logical invalidation does not close the physical wrapper. Teardown
        // proves this SAME wrapper/census until its actual later lease close.
        try expectedHandle.requireExactRegistry(registry)
    }
    func closeCompletedSessionLifetimeBeforeEraseTransfer(operation: EraseRouterOperationV1,
        exclusion: StoreTemporalNormalizationExclusionV1, binding: EraseRetirementBindingV1,
        drain: EraseSessionDrainWitnessV1, permit: TemporalNormalizationEraseTransferPermitV1) throws {
        guard let owner = completedSessionLifetimeOwner else { return } // actual ordinary origin only
        guard temporalExclusiveOwner === exclusion, exclusion.owner === self,
              exclusion.writer === workspaceWriter, exclusion.retainedWriter == writerLeaseHandle.token,
              temporalAdmission == .exclusive(exclusion.id), temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty, let installed = erasePreparationInstallation,
              installed.operation === operation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try owner.closeCurrentCompletedSessionBeforeSelectedEraseTransfer(coordinator: self,
            operation: operation, exclusion: exclusion, binding: binding, drain: drain, permit: permit)
    }
    func requireCompletedSessionEraseProjectionCoordinatorData(
        _ projection: ColdEraseSchema2CompletedSessionEraseProjectionV1,
        owner: ColdEraseSchema2CompletedSessionLifetimeOwnerV1,
        operation: EraseRouterOperationV1, allocation: GenerationWriterAllocationAttemptV1,
        targetSession: StoreGenerationSession, targetWriter: WorkspaceWriterV1,
        targetHandle: GenerationLeaseHandleV1, targetFence: StaleWriterFenceV1,
        registry: GenerationLeaseRegistryV1, factory: StoreGenerationFactory,
        exclusion: StoreTemporalNormalizationExclusionV1) throws {
        guard completedSessionLifetimeOwner === owner, completedSessionEraseProjection === projection,
              let installed = erasePreparationInstallation, installed.operation === operation,
              installed.allocation === allocation, session === targetSession,
              workspaceWriter === targetWriter, writerLeaseHandle === targetHandle,
              writerFence === targetFence, temporalExclusiveOwner === exclusion,
              exclusion.owner === self, exclusion.writer === targetWriter,
              exclusion.registry === registry, exclusion.retainedWriter == targetHandle.token,
              temporalAdmission == .exclusive(exclusion.id), temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty, exclusion.sourceOwner == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try requireCompletedSessionCurrentCoordinatorData(owner, session: targetSession,
            writer: targetWriter, writerHandle: targetHandle, fence: targetFence,
            registry: registry, factory: factory)
    }
    func completedSessionLifetimeOwnerForCurrentSession() -> ColdEraseSchema2CompletedSessionLifetimeOwnerV1? {
        completedSessionLifetimeOwner // actual privately retained origin, not an authority check
    }
}
// COMPLETED_SESSION_CURRENT_COORDINATOR_V1_END

extension StoreSessionCoordinator {
    func requireCompletedSessionBeforeOriginalEraseReplacementData(
        _ owner: ColdEraseSchema2CompletedSessionLifetimeOwnerV1,
        originalSession: StoreGenerationSession, originalWriter: WorkspaceWriterV1,
        originalHandle: GenerationLeaseHandleV1, originalFence: StaleWriterFenceV1,
        registry: GenerationLeaseRegistryV1, factory: StoreGenerationFactory,
        exclusion: StoreTemporalNormalizationExclusionV1, operation: EraseRouterOperationV1,
        allocation: GenerationWriterAllocationAttemptV1) throws {
        guard completedSessionLifetimeOwner === owner, session === originalSession,
              workspaceWriter === originalWriter, writerLeaseHandle === originalHandle,
              writerFence === originalFence, writerFence.retainedTemporalRegistry === registry,
              generationFactory.sharesRegistryProvider(with: factory),
              temporalExclusiveOwner === exclusion, exclusion.owner === self,
              exclusion.writer === originalWriter, exclusion.registry === registry,
              temporalAdmission == .exclusive(exclusion.id), temporalProducerIDs.isEmpty,
              temporalDrainWaiters.isEmpty, erasePreparationInstallation == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireCompletedOriginalEraseWriterTransition(registry: registry,
            activity: exclusion.activity, targetAllocation: allocation)
        try originalHandle.requireClosedForOriginalEraseWriterTransition(registry: registry)
    }
}

import Darwin
import CryptoKit
import Foundation

enum SurveySessionEraseAllEnrollmentV1{static func validate()throws{try SurveySessionDeletionLedgerPolicyV1.validate();guard SurveySessionEraseIntentEnrollmentV1.schemaVersion==25,SurveySessionEraseIntentEnrollmentV1.removesAllFiveFamilies else{throw DeletionLedgerFailureV2.invalidSchemaVersion}}}

enum C30EvidenceContextEraseAllPolicyV1 {
    static let persistentSchemaVersion = 30
    static let recordsSchemaVersion = 29
    static let durableRowCount = 2
    static let clearsOnlyWorkspaceRows = true
    static let clearsDerivedProjection = true

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard persistentSchemaVersion == 30, recordsSchemaVersion == 29,
              durableRowCount == 2, clearsOnlyWorkspaceRows,
              clearsDerivedProjection else { throw EraseAllServiceError.invalidAuthority }
        guard try context.fetchCount(FetchDescriptor<EvidenceContextRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PairedObservationLinkRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum C31LightingEraseAllServiceBoundaryV1 {
    static let eraseClearsAllFiveDurableFamilies = true
    static let eraseDoesNotClaimExternalAvailability = true
    static let diagnosticsRemainAggregateOnly = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try C31LightingEraseIntentBoundaryV1.validate(
            records: records,
            workspaceID: workspaceID
        )
        guard eraseClearsAllFiveDurableFamilies,
              eraseDoesNotClaimExternalAvailability,
              diagnosticsRemainAggregateOnly else {
            throw LightingContractFailureV1.invalidValue
        }
    }
}
import SwiftData

enum IntegrationProjectionEraseAllPolicyV1 {
    static func validate() throws {
        try KernelDeletionEraseRegistryV4.validateIntegrationProjectionLifecycle()
    }

    static func purge(
        store: any IntegrationProjectionOperationalStoreV1,
        workspaceID: WorkspaceID
    ) async throws {
        try await store.dropDerivedProjection(
            consumerID: nil,
            workspaceID: workspaceID
        )
    }
}

enum FunctionalRelationshipEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(
            FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()
        ) == 0, try context.fetchCount(
            FetchDescriptor<AssetFunctionalRelationshipEventRow>()
        ) == 0 else { throw EraseAllServiceError.invalidAuthority }
    }
}

enum EvidenceAssuranceEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<EvidenceVisibilityRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ClaimEvidenceLinkRow>()) == 0,
              try context.fetchCount(FetchDescriptor<AssuranceManifestRow>()) == 0,
              try context.fetchCount(FetchDescriptor<AttestationRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum InspectionReviewEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<InspectionReviewTransitionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ReviewDispositionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ChangeRequestRow>()) == 0,
              try context.fetchCount(FetchDescriptor<CorrectiveActionPolicyRow>()) == 0,
              try context.fetchCount(FetchDescriptor<CorrectiveActionEventRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum WorkPacketEraseAllPolicyV1{static func validatePublishedEmptyGeneration(_ context:ModelContext)throws{guard try context.fetchCount(FetchDescriptor<WorkPacketManifestRow>())==0,try context.fetchCount(FetchDescriptor<WorkItemClaimRow>())==0,try context.fetchCount(FetchDescriptor<WorkLeaseRow>())==0,try context.fetchCount(FetchDescriptor<WorkReleaseRow>())==0,try context.fetchCount(FetchDescriptor<WorkHandoffRow>())==0 else{throw EraseAllServiceError.invalidAuthority}}}

enum FieldDraftEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()) == 0,
              try context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()) == 0,
              try context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()) == 0,
              try context.fetchCount(FetchDescriptor<DraftContentReservationRow>()) == 0,
              try context.fetchCount(FetchDescriptor<DraftCommitReceiptRow>()) == 0,
              try context.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum PackageEvolutionEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<PromotedPackageReleaseRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PackageSandboxRunRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PackagePromotionReceiptRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ActivePackageRegistryPointerRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum MeasurementIntegrityEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<InstrumentReferenceRow>()) == 0,
              try context.fetchCount(FetchDescriptor<CalibrationStatusSnapshotRow>()) == 0,
              try context.fetchCount(FetchDescriptor<MeasurementCaptureRow>()) == 0,
              try context.fetchCount(FetchDescriptor<MeasurementSeriesRow>()) == 0,
              try context.fetchCount(FetchDescriptor<MeasurementQualityAssessmentRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum PrivacyTransformEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<PrivacyTransformPolicyRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PrivacyRegionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PrivacyTransformManifestRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PrivacyReviewReceiptRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}
enum ClientCapabilityEraseAllPolicyV1{static func validatePublishedEmptyGeneration(_ context:ModelContext)throws{guard try context.fetchCount(FetchDescriptor<ClientCapabilityProfileRow>())==0,try context.fetchCount(FetchDescriptor<PackageLifecyclePolicyRow>())==0,try context.fetchCount(FetchDescriptor<PackageLifecycleDispositionRow>())==0,try context.fetchCount(FetchDescriptor<ClientCapabilityAdmissionDecisionRow>())==0 else{throw EraseAllServiceError.invalidAuthority}}}
enum FieldReferenceEraseAllPolicyV1{static func validatePublishedEmptyGeneration(_ context:ModelContext)throws{guard try context.fetchCount(FetchDescriptor<FieldReferenceReleaseRow>())==0,try context.fetchCount(FetchDescriptor<FieldReferenceBindingRow>())==0 else{throw EraseAllServiceError.invalidAuthority}}}
enum AccessibleDocumentEraseAllPolicyV1{static func validatePublishedEmptyGeneration(_ context:ModelContext)throws{guard try context.fetchCount(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>())==0 else{throw EraseAllServiceError.invalidAuthority}}}
enum SurveyDefinitionEraseAllPolicyV1{static func validatePublishedEmptyGeneration(_ context:ModelContext)throws{guard try context.fetchCount(FetchDescriptor<SurveyDefinitionIdentityRow>())==0,try context.fetchCount(FetchDescriptor<SurveyDefinitionReleaseRow>())==0 else{throw EraseAllServiceError.invalidAuthority}}}
enum SurveySessionEraseAllPolicyV1{static func validatePublishedEmptyGeneration(_ context:ModelContext)throws{guard try context.fetchCount(FetchDescriptor<SurveySessionRow>())==0,try context.fetchCount(FetchDescriptor<FactCaptureRow>())==0,try context.fetchCount(FetchDescriptor<ProvisionalSubjectRow>())==0,try context.fetchCount(FetchDescriptor<SubjectPromotionReceiptRow>())==0,try context.fetchCount(FetchDescriptor<SurveyPublicationSnapshotRow>())==0 else{throw EraseAllServiceError.invalidAuthority}}}
enum AssetLocatorEraseAllPolicyV1 {
    static let persistentSchemaVersion = 26
    static let recordsSchemaVersion = 25
    static let durableFamilyCount = 2
    static let privateKeyMaterialExported = false
    static let cloneForkSourceSignatureActive = false

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        try AssetLocatorDeletionLedgerPolicyV1.validate()
        guard try context.fetchCount(FetchDescriptor<AssetLocatorRow>()) == 0,
              try context.fetchCount(FetchDescriptor<LocatorBindingReceiptRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

/// Schedule releases and occurrence history are workspace-owned canonical
/// rows. A newly published erase generation must contain neither family;
/// due/reminder projections are derived and are not erased as durable truth.
enum ScheduleEraseAllPolicyV1 {
    static let persistentSchemaVersion = 27
    static let recordsSchemaVersion = 26
    static let durableFamilyCount = 2
    static let projectionsAreDerived = true
    static let notificationStateIsTruth = false

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard persistentSchemaVersion == 27,
              recordsSchemaVersion == 26,
              durableFamilyCount == 2,
              projectionsAreDerived,
              !notificationStateIsTruth,
              try context.fetchCount(FetchDescriptor<ScheduleDefinitionReleaseRow>()) == 0,
              try context.fetchCount(FetchDescriptor<OccurrenceHistoryEventRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum PlanEraseAllPolicyV1 {
    static let persistentSchemaVersion = 28
    static let recordsSchemaVersion = 27
    static let durableModelCount = 4
    static let durableFamilyCount = 4
    static let previewsAndRegistriesAreDerived = true

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard persistentSchemaVersion == PlanPersistenceEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion == PlanPersistenceEnrollmentV1.recordsSchemaVersion,
              durableModelCount == PlanPersistenceEnrollmentV1.durableModelCount,
              durableFamilyCount == PlanPersistenceEnrollmentV1.durableModelCount,
              previewsAndRegistriesAreDerived,
              try context.fetchCount(FetchDescriptor<PlanDocumentRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PlanRevisionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PlanPlacementRow>()) == 0,
              try context.fetchCount(FetchDescriptor<RebaseReceiptRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum PlacementPoseEraseAllPolicyV1 {
    static let persistentSchemaVersion = 29
    static let recordsSchemaVersion = 28
    static let durableFamilyCount = 2
    static let derivedProjectionStorage = "NONPERSISTENT_REBUILD"
    static let workspaceEraseClearsCanonicalRows = true
    static let ordinaryDeletionPreservesHistory = true

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard persistentSchemaVersion == PlacementPosePersistenceEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion == PlacementPosePersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount == PlacementPosePersistenceEnrollmentV1.durableModelCount,
              derivedProjectionStorage == "NONPERSISTENT_REBUILD",
              workspaceEraseClearsCanonicalRows,
              ordinaryDeletionPreservesHistory,
              try context.fetchCount(FetchDescriptor<AssetPoseEventRow>()) == 0,
              try context.fetchCount(FetchDescriptor<SpatialAnchorObservationRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try PlacementPoseDeletionLedgerPolicyV1.validate()
    }
}

enum EraseAllServiceError: Error, Equatable {
    case contextHasChanges
    case invalidAuthority
    case invalidConfirmation
    case recoveryRequired
    case injectedFailure
}

struct EraseAllOutcome {
    let session: StoreGenerationSession
    let cleanupDeferred: Bool
}

enum EraseAllFailurePoint: CaseIterable, Equatable, Sendable {
    case afterEmptyGenerationDirectoryCreate
    case beforePreparedWrite
    case afterPreparedWrite
    case beforePointerSwitch
    case afterPointerSwitch
    case beforePointerPhaseWrite
    case afterPointerPhaseWrite
    case beforeSessionActivation
    case afterSessionActivation
    case beforeSessionPhaseWrite
    case afterSessionPhaseWrite
    case beforeCleanup
    case afterCleanup
    case beforeCleanupPhaseWrite
    case afterCleanupPhaseWrite
    case beforeJournalRemoval
}

@MainActor
private enum EraseAllLifecycleRouteV1 {
    case live(dependencies: WorkspacePackageLifecycleDependenciesV1)
    case expiringCompatibility(posture: String)

    func validate(generationRootURL: URL, generationID: UUID) throws {
        let root = generationRootURL.standardizedFileURL
        switch self {
        case .live(let dependencies):
            guard dependencies.generationID == generationID,
                  dependencies.generationRootURL.standardizedFileURL == root,
                  dependencies.generationRootURL.isFileURL else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .expiringCompatibility(let posture):
            guard posture == WorkspacePackageLifecycleCompatibilityV1.expiration else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }
}

private enum EraseAllLifecycleCheckpointV1 {
    case live(WorkspaceRevisionV1)
    case compatibility
}

@MainActor
final class EraseAllFailureInjection {
    private var pending: EraseAllFailurePoint?

    init(failOnceAt point: EraseAllFailurePoint) {
        pending = point
    }

    func consume(_ point: EraseAllFailurePoint) -> Bool {
        guard pending == point else { return false }
        pending = nil
        return true
    }
}

@MainActor
final class EraseGenerationDrainProof {
    private weak var priorContext: ModelContext?
    private weak var priorContainer: ModelContainer?

    init(priorContext: ModelContext) {
        self.priorContext = priorContext
        self.priorContainer = priorContext.container
    }

    var isDrained: Bool {
        priorContext == nil && priorContainer == nil
    }
}

@MainActor
final class EraseAllService {
    static let requiredConfirmation = "ERASE"

    private let applicationSupportURL: URL
    private let cachesDirectoryURL: URL
    private let temporaryDirectoryURL: URL
    private let generationFactory: StoreGenerationFactory
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let bundleIdentifier: String
    private let makeUUID: () -> UUID
    private let sleeper: any ApplicationSleeper
    private let failureInjection: EraseAllFailureInjection?

    init(
        applicationSupportURL: URL,
        cachesDirectoryURL: URL? = nil,
        temporaryDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier
            ?? "com.palatis3.fieldrecord",
        makeUUID: @escaping () -> UUID = UUID.init,
        sleeper: any ApplicationSleeper = SystemApplicationSleeper(),
        failureInjection: EraseAllFailureInjection? = nil
    ) {
        let support = applicationSupportURL.standardizedFileURL
        self.applicationSupportURL = support
        self.cachesDirectoryURL = (
            cachesDirectoryURL
                ?? support.deletingLastPathComponent()
                    .appendingPathComponent("Caches", isDirectory: true)
        ).standardizedFileURL
        self.temporaryDirectoryURL = (
            temporaryDirectoryURL ?? fileManager.temporaryDirectory
        ).standardizedFileURL
        self.generationFactory = StoreGenerationFactory(
            applicationSupportURL: support,
            fileManager: fileManager
        )
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.bundleIdentifier = bundleIdentifier
        self.makeUUID = makeUUID
        self.sleeper = sleeper
        self.failureInjection = failureInjection
    }

    func erase(
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> EraseAllOutcome {
        try await erase(
            confirmation: confirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnosticsStore,
            activate: activate,
            lifecycleRoute: .expiringCompatibility(
                posture: WorkspacePackageLifecycleCompatibilityV1.expiration
            )
        )
    }

    func erase(
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,
        lifecycleDependencies dependencies: WorkspacePackageLifecycleDependenciesV1
    ) async throws -> EraseAllOutcome {
        try await erase(
            confirmation: confirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnosticsStore,
            activate: activate,
            lifecycleRoute: .live(dependencies: dependencies)
        )
    }

    private func erase(
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,
        lifecycleRoute: EraseAllLifecycleRouteV1
    ) async throws -> EraseAllOutcome {
        try IntegrationProjectionEraseAllPolicyV1.validate()
        guard confirmation == Self.requiredConfirmation else {
            throw EraseAllServiceError.invalidConfirmation
        }
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
        try lifecycleRoute.validate(
            generationRootURL: coordinator.generationRootURL,
            generationID: coordinator.generationID
        )
        let auxiliary = try makeAuxiliaryAuthority()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()
        let applicationSupportIdentity = auxiliary.applicationSupportRootIdentity

        let generationAuthority = try generationFactory
            .makeRestoreGenerationAuthority(
                expectedApplicationSupportIdentity: applicationSupportIdentity
            )
        let drainProof = EraseGenerationDrainProof(
            priorContext: coordinator.modelContext
        )
        let oldGenerationID = coordinator.generationID
        let oldGenerationRootURL = coordinator.generationRootURL
        let priorRetired = try generationAuthority.retiredGenerationIDs()
        try validateCurrentAuthority(
            coordinator: coordinator,
            expectedID: oldGenerationID,
            expectedRootURL: oldGenerationRootURL,
            retiredIDs: priorRetired,
            authority: generationAuthority
        )
        try validateKernelEraseMappings()
        let lifecycleCheckpoint: EraseAllLifecycleCheckpointV1
        switch lifecycleRoute {
        case .live(let dependencies):
            lifecycleCheckpoint = .live(
                try validatePackageLifecycleScope(
                    dependencies: dependencies,
                    coordinator: coordinator
                )
            )
        case .expiringCompatibility:
            lifecycleCheckpoint = .compatibility
        }
        try auxiliary.verifyTargets()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()

        let oldPointer = try frozenCurrentPointer(
            expectedGenerationID: oldGenerationID,
            authority: generationAuthority
        )
        let sourceLedger = try generationFactory
            .currentGenerationDeletionLedgerProof(
                expectedPointer: oldPointer,
                authority: generationAuthority
            )
        let newGenerationID = makeUUID()
        let eraseID = makeUUID()
        let generationIDsToDelete = (priorRetired + [oldGenerationID]).sorted(
            by: Self.idOrder
        )
        guard newGenerationID != eraseID,
              !generationIDsToDelete.contains(newGenerationID),
              !oldPointer.knownReplicaIDs.contains(newGenerationID),
              !oldPointer.knownReplicaIDs.contains(eraseID),
              newGenerationID != oldPointer.workspaceID,
              newGenerationID != oldPointer.replicaID,
              eraseID != oldPointer.workspaceID,
              eraseID != oldPointer.replicaID,
              oldPointer.generationID == oldGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        let targetIdentity = try freshEraseIdentity(excluding: Set(
            generationIDsToDelete
                + oldPointer.knownReplicaIDs
                + [
                    eraseID,
                    newGenerationID,
                    oldPointer.workspaceID,
                    oldPointer.replicaID,
                ]
        ))
        let initialPreparation = ErasePreparationV2(
            oldPointer: oldPointer,
            sourceLedger: sourceLedger,
            targetGenerationID: newGenerationID,
            targetWorkspaceID: targetIdentity.workspaceID.rawValue,
            targetReplicaID: targetIdentity.replicaID.rawValue,
            targetPointer: nil
        )

        var createdIntent = false
        var frozenIntent: EraseIntentV1?
        var frozenPreparation = initialPreparation
        var intentStore: EraseIntentStore?
        do {
            let store = try EraseIntentStore(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager,
                expectedApplicationSupportIdentity: applicationSupportIdentity
            )
            guard try store.load() == nil,
                  try store.loadPreparation() == nil else {
                throw EraseAllServiceError.recoveryRequired
            }
            try store.createPreparation(initialPreparation)
            intentStore = store
            let created = try generationFactory.createEmptyEraseGeneration(
                id: newGenerationID,
                expectedOldPointer: oldPointer,
                identity: targetIdentity,
                authority: generationAuthority
            )
            let boundPreparation = initialPreparation.binding(
                targetPointer: created.pointer
            )
            try store.replacePreparation(
                expected: initialPreparation,
                with: boundPreparation
            )
            frozenPreparation = boundPreparation
            try inject(.afterEmptyGenerationDirectoryCreate)
            let expectedEmptyLedger = try emptyLedgerProof()
            guard created.ledgerProof == expectedEmptyLedger,
                  created.pointer.workspaceID
                    == targetIdentity.workspaceID.rawValue,
                  created.pointer.replicaID
                    == targetIdentity.replicaID.rawValue,
                  created.pointer.knownReplicaIDs
                    == [targetIdentity.replicaID.rawValue] else {
                throw EraseAllServiceError.invalidAuthority
            }
            if case let .live(expectedRevision) = lifecycleCheckpoint {
                try validateEraseCommand(
                    lifecycleRoute: lifecycleRoute,
                    coordinator: coordinator,
                    eraseID: eraseID,
                    targetGenerationID: newGenerationID,
                    oldPointer: oldPointer,
                    expectedEmptyLedger: expectedEmptyLedger,
                    expectedRevision: expectedRevision
                )
            }
            let intent = EraseIntentV1(
                auxiliaryRoots: EraseIntentV1.canonicalAuxiliaryRoots,
                eraseID: eraseID,
                generationIDsToDelete: generationIDsToDelete,
                newGenerationID: newGenerationID,
                oldGenerationID: oldGenerationID,
                phase: .emptyGenerationPrepared,
                schemaVersion: 2,
                oldPointer: oldPointer,
                sourceLedger: sourceLedger,
                targetEmptyProof: EraseEmptyGenerationProofV2(
                    contentRecordCount: 0,
                    deletionLedgerEntryCount: 0
                ),
                targetPointer: created.pointer
            )
            frozenIntent = intent
            guard EraseIntentCodecV1.valid(intent) else {
                throw EraseAllServiceError.invalidAuthority
            }
            let emptySession = try validatedEmptySession(
                id: newGenerationID,
                identity: targetIdentity,
                expectedEmptyLedger: expectedEmptyLedger,
                authority: generationAuthority
            )
            try MutationJournalStoreV1(
                modelContext: emptySession.modelContext,
                identity: targetIdentity,
                generationID: newGenerationID
            ).clearForErase(
                expectedWorkspaceID: targetIdentity.workspaceID,
                expectedGenerationID: newGenerationID
            )
            _ = try validatedEmptySession(
                id: newGenerationID,
                identity: targetIdentity,
                expectedEmptyLedger: expectedEmptyLedger,
                authority: generationAuthority
            )
            try requirePreparedPresence(intent, authority: generationAuthority)
            try auxiliary.requireNoRestoreIntent()

            try inject(.beforePreparedWrite)
            guard try store.load() == nil,
                  try store.loadPreparation() == frozenPreparation else {
                throw EraseAllServiceError.recoveryRequired
            }
            try store.create(intent)
            createdIntent = true
            try inject(.afterPreparedWrite)

            guard let intentStore else {
                throw EraseAllServiceError.invalidAuthority
            }
            let session = try await advanceToActivatedSession(
                intent,
                authority: generationAuthority,
                intentStore: intentStore,
                activate: activate
            )
            guard coordinator.generationID == session.generationID,
                  coordinator.generationRootURL.standardizedFileURL
                    == session.generationRootURL.standardizedFileURL,
                  coordinator.modelContext === session.modelContext else {
                throw EraseAllServiceError.recoveryRequired
            }
            guard try await waitForDrain(drainProof) else {
                return EraseAllOutcome(
                    session: session,
                    cleanupDeferred: true
                )
            }
            let activated = intent.advancing(to: .sessionActivated)
            let completed = try await completeCleanup(
                activated,
                session: session,
                authority: generationAuthority,
                auxiliary: auxiliary,
                diagnosticsStore: diagnosticsStore,
                intentStore: intentStore
            )
            return EraseAllOutcome(
                session: completed,
                cleanupDeferred: false
            )
        } catch {
            if !createdIntent {
                var ownsUnjournaledGeneration = true
                if let intentStore {
                    do {
                        if let stored = try intentStore.load() {
                            guard let frozenIntent,
                                  stored == frozenIntent else {
                                throw EraseAllServiceError.recoveryRequired
                            }
                            ownsUnjournaledGeneration = false
                        }
                    } catch {
                        throw EraseAllServiceError.recoveryRequired
                    }
                }
                do {
                    if ownsUnjournaledGeneration,
                       let intentStore,
                       let preparation = try intentStore.loadPreparation() {
                        guard preparation == frozenPreparation
                                || preparation == initialPreparation else {
                            throw EraseAllServiceError.recoveryRequired
                        }
                        try discardPreparation(
                            preparation,
                            authority: generationAuthority
                        )
                        try intentStore.removePreparation(expected: preparation)
                    }
                    if ownsUnjournaledGeneration {
                        try auxiliary.removeEraseRootIfEmpty()
                    }
                } catch {
                    throw EraseAllServiceError.recoveryRequired
                }
            }
            throw error
        }
    }

    /// Runs before Restore and ordinary pointer maintenance. A nonnil result
    /// is the one reopened empty generation that startup must activate.
    func reconcileAtStartup(
        diagnosticsStore: DiagnosticsStore
    ) async throws -> StoreGenerationSession? {
        var supportStatus = stat()
        let supportResult = applicationSupportURL.path.withCString {
            lstat($0, &supportStatus)
        }
        if supportResult != 0 {
            guard errno == ENOENT else {
                throw EraseAllServiceError.invalidAuthority
            }
            return nil
        }
        guard (supportStatus.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        let auxiliary = try makeAuxiliaryAuthority()
        let intentStore = try EraseIntentStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        let intent = try intentStore.load()
        let preparation = try intentStore.loadPreparation()
        guard let intent else {
            if let preparation {
                let authority = try generationFactory
                    .makeRestoreGenerationAuthority(
                        expectedApplicationSupportIdentity:
                            auxiliary.applicationSupportRootIdentity
                    )
                try auxiliary.verifyTargets()
                try auxiliary.requireNoRestoreIntent()
                try discardPreparation(preparation, authority: authority)
                try intentStore.removePreparation(expected: preparation)
            }
            try auxiliary.removeEraseRootIfEmpty()
            return nil
        }
        guard EraseIntentCodecV1.valid(intent) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if intent.schemaVersion == 2 {
            if let preparation {
                guard preparation.matches(intent) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else if intent.phase != .cleanupComplete {
                throw EraseAllServiceError.invalidAuthority
            }
        } else if preparation != nil {
            throw EraseAllServiceError.invalidAuthority
        }
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        try auxiliary.verifyTargets()
        try requireRecoveryPresence(intent, authority: authority)

        let session: StoreGenerationSession
        switch intent.phase {
        case .emptyGenerationPrepared:
            session = try await advanceToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                activate: { _ in }
            )
        case .pointerSwitched:
            session = try await advancePointerPhaseToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                activate: { _ in }
            )
        case .sessionActivated:
            try requireActivatedCurrent(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        case .cleanupComplete:
            try requireCleanupPresence(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        }

        let activated = intent.phase == .cleanupComplete
            ? intent
            : intent.advancing(to: .sessionActivated)
        return try await completeCleanup(
            activated,
            session: session,
            authority: authority,
            auxiliary: auxiliary,
            diagnosticsStore: diagnosticsStore,
            intentStore: intentStore
        )
    }

    func validateMaintenanceEntry(_ session: StoreGenerationSession) throws {
        let coordinator = StoreSessionCoordinator(session: session)
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
        let auxiliary = try makeAuxiliaryAuthority()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        let retired = try authority.retiredGenerationIDs()
        try validateCurrentAuthority(
            coordinator: coordinator,
            expectedID: session.generationID,
            expectedRootURL: session.generationRootURL,
            retiredIDs: retired,
            authority: authority
        )
        try auxiliary.verifyTargets()
    }
}

private extension EraseAllService {
    func validatePackageLifecycleScope(
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        coordinator: StoreSessionCoordinator
    ) throws -> WorkspaceRevisionV1 {
        guard dependencies.workspaceID == coordinator.workspaceID,
              dependencies.generationID == coordinator.generationID,
              dependencies.generationRootURL.standardizedFileURL
                == coordinator.generationRootURL.standardizedFileURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        do {
            let request = try WorkspacePackageLifecycleQueryRequestV1(
                workspaceID: dependencies.workspaceID,
                generationID: dependencies.generationID,
                operation: .erase,
                identities: []
            )
            let result = try dependencies.queryClient.query(request)
            let current = try dependencies.queryClient.currentRevision()
            guard result.workspaceID == dependencies.workspaceID,
                  result.generationID == dependencies.generationID,
                  result.operation == .erase,
                  result.existingIdentities.isEmpty,
                  result.packageBindings.isEmpty,
                  result.revision == current,
                  current.workspaceID == coordinator.workspaceID,
                  current.generationID == coordinator.generationID else {
                throw EraseAllServiceError.invalidAuthority
            }
            return current
        } catch let error as EraseAllServiceError {
            throw error
        } catch {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func validateEraseCommand(
        lifecycleRoute: EraseAllLifecycleRouteV1,
        coordinator: StoreSessionCoordinator,
        eraseID: UUID,
        targetGenerationID: UUID,
        oldPointer: RestorePointerIdentityV1,
        expectedEmptyLedger: DeletionLedgerProofV2,
        expectedRevision: WorkspaceRevisionV1
    ) throws {
        guard case let .live(dependencies) = lifecycleRoute,
              dependencies.workspaceID == coordinator.workspaceID,
              dependencies.generationID == coordinator.generationID,
              try dependencies.queryClient.currentRevision() == expectedRevision else {
            throw EraseAllServiceError.invalidAuthority
        }
        let command = WorkspaceCommandV1.eraseWorkspace(
            EraseWorkspaceMutationV1(
                eraseID: eraseID,
                targetGenerationID: targetGenerationID,
                oldPointerDigest: try WorkspaceMutationCanonicalV1.sha256(oldPointer),
                emptyLedgerDigest: try WorkspaceMutationCanonicalV1.sha256(expectedEmptyLedger)
            )
        )
        let request = WorkspaceMutationRequestV1(
            mutationID: try MutationIDV1(rawValue: eraseID),
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: expectedRevision),
            command: command
        )
        guard request.command.kind == .eraseWorkspace,
              case let .eraseWorkspace(value) = request.command,
              value.eraseID == eraseID,
              value.targetGenerationID == targetGenerationID,
              value.oldPointerDigest.utf8.count == 64,
              value.emptyLedgerDigest.utf8.count == 64 else {
            throw EraseAllServiceError.invalidAuthority
        }
        // The generation switch remains the authoritative effect. The live
        // writer and query establish the immutable command identity before
        // the existing crash-safe erase journal publishes that switch.
        _ = dependencies.writer
    }

    func makeAuxiliaryAuthority() throws -> EraseAuxiliaryAuthority {
        guard bundleIdentifier == "com.palatis3.fieldrecord" else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try EraseAuxiliaryAuthority(
            applicationSupportURL: applicationSupportURL,
            cachesDirectoryURL: cachesDirectoryURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
    }

    func validateCurrentAuthority(
        coordinator: StoreSessionCoordinator,
        expectedID: UUID,
        expectedRootURL: URL,
        retiredIDs: [UUID],
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
        let installed = try authority.installedGenerationNames()
        let expectedNames = Set((retiredIDs + [expectedID]).map(Self.canonical))
        guard try generationFactory.currentGenerationID(authority: authority)
                == expectedID,
              !retiredIDs.contains(expectedID),
              Set(installed) == expectedNames,
              generationFactory.installedGenerationURL(id: expectedID)
                == expectedRootURL.standardizedFileURL,
              try ReportPDFAnchoredFile.rootIdentity(at: expectedRootURL)
                == ReportPDFAnchoredFile.rootIdentity(
                    at: generationFactory.installedGenerationURL(id: expectedID)
                ),
              try authority.restoreGenerationNames().isEmpty,
              try authority.importStagingNames().isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        try validateFrozenGeneration(
            id: expectedID,
            modelContext: coordinator.modelContext,
            generationRootURL: expectedRootURL,
            authority: authority
        )
        for id in retiredIDs {
            let retiredSession = try generationFactory.openInstalledGeneration(
                id: id,
                authority: authority
            )
            try validateFrozenGeneration(
                id: id,
                modelContext: retiredSession.modelContext,
                generationRootURL: retiredSession.generationRootURL,
                authority: authority
            )
        }
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
    }

    func requirePreparedPresence(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let expected = Set(
            (intent.generationIDsToDelete + [intent.newGenerationID])
                .map(Self.canonical)
        )
        guard Set(try authority.installedGenerationNames()) == expected,
              try generationFactory.currentGenerationID(authority: authority)
                == intent.oldGenerationID,
              try authority.retiredGenerationIDs()
                == priorRetiredIDs(intent) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if intent.schemaVersion == 2 {
            try requireSourceLedgerBinding(intent, authority: authority)
            _ = try validatedEmptySession(
                id: intent.newGenerationID,
                identity: try targetIdentity(intent),
                expectedEmptyLedger: try expectedEmptyLedger(intent),
                authority: authority
            )
        }
    }

    func requireRecoveryPresence(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let installed = Set(try authority.installedGenerationNames())
        let all = Set(
            (intent.generationIDsToDelete + [intent.newGenerationID])
                .map(Self.canonical)
        )
        guard installed.contains(Self.canonical(intent.newGenerationID)),
              installed.isSubset(of: all),
              try authority.restoreGenerationNames().isEmpty,
              try authority.importStagingNames().isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        switch intent.phase {
        case .emptyGenerationPrepared, .pointerSwitched:
            guard installed == all else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .sessionActivated, .cleanupComplete:
            break
        }
        let currentID = try generationFactory.currentGenerationID(
            authority: authority
        )
        if intent.schemaVersion == 2 {
            if currentID == intent.oldGenerationID {
                try requireSourceLedgerBinding(intent, authority: authority)
                _ = try validatedEmptySession(
                    id: intent.newGenerationID,
                    identity: try targetIdentity(intent),
                    expectedEmptyLedger: try expectedEmptyLedger(intent),
                    authority: authority
                )
            } else if currentID == intent.newGenerationID {
                _ = try requirePublishedEmptySession(
                    intent,
                    authority: authority
                )
            } else {
                throw EraseAllServiceError.invalidAuthority
            }
        } else {
            _ = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        }
        for id in intent.generationIDsToDelete
        where installed.contains(Self.canonical(id)) {
            let session = try generationFactory.openInstalledGeneration(
                id: id,
                authority: authority
            )
            try validateFrozenGeneration(
                id: id,
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                authority: authority
            )
        }
    }

    func advanceToActivatedSession(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> StoreGenerationSession {
        try inject(.beforePointerSwitch)
        try normalizePointerAndRetired(intent, authority: authority)
        try inject(.afterPointerSwitch)

        let switched = intent.advancing(to: .pointerSwitched)
        try inject(.beforePointerPhaseWrite)
        if intent.phase == .emptyGenerationPrepared {
            try intentStore.replace(expected: intent, with: switched)
        }
        try inject(.afterPointerPhaseWrite)
        return try await advancePointerPhaseToActivatedSession(
            switched,
            authority: authority,
            intentStore: intentStore,
            activate: activate
        )
    }

    func advancePointerPhaseToActivatedSession(
        _ switched: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> StoreGenerationSession {
        try normalizePointerAndRetired(switched, authority: authority)
        try requireNewCurrent(switched, authority: authority)
        let session: StoreGenerationSession
        if switched.schemaVersion == 2 {
            session = try requirePublishedEmptySession(
                switched,
                authority: authority
            )
        } else {
            session = try validatedEmptySession(
                id: switched.newGenerationID,
                authority: authority
            )
        }
        try inject(.beforeSessionActivation)
        await activate(session)
        await Task.yield()
        try inject(.afterSessionActivation)

        let activated = switched.advancing(to: .sessionActivated)
        try inject(.beforeSessionPhaseWrite)
        try intentStore.replace(expected: switched, with: activated)
        try inject(.afterSessionPhaseWrite)
        return session
    }

    func normalizePointerAndRetired(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let current = try generationFactory.currentGenerationID(authority: authority)
        if current == intent.oldGenerationID {
            if intent.schemaVersion == 2 {
                try requireSourceLedgerBinding(intent, authority: authority)
                guard let oldPointer = intent.oldPointer,
                      let targetPointer = intent.targetPointer else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try generationFactory.publishEmptyEraseGeneration(
                    expectedOldPointer: oldPointer,
                    targetPointer: targetPointer,
                    expectedEmptyLedger: try expectedEmptyLedger(intent),
                    authority: authority
                )
            } else {
                try generationFactory.switchCurrentGeneration(
                    expected: intent.oldGenerationID,
                    to: intent.newGenerationID,
                    authority: authority
                )
            }
        } else if current != intent.newGenerationID {
            throw EraseAllServiceError.invalidAuthority
        } else if intent.schemaVersion == 2 {
            _ = try requirePublishedEmptySession(intent, authority: authority)
        }
        let retired = try authority.retiredGenerationIDs()
        let prior = priorRetiredIDs(intent)
        if retired == prior {
            try generationFactory.replaceRetiredGenerationIDs(
                expected: prior,
                with: intent.generationIDsToDelete,
                currentID: intent.newGenerationID,
                authority: authority
            )
        } else if retired != intent.generationIDsToDelete {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireNewCurrent(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID,
              try authority.retiredGenerationIDs()
                == intent.generationIDsToDelete else {
            throw EraseAllServiceError.invalidAuthority
        }
        if intent.schemaVersion == 2 {
            _ = try requirePublishedEmptySession(intent, authority: authority)
        }
    }

    func requireActivatedCurrent(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let retired = try authority.retiredGenerationIDs()
        let installed = Set(try authority.installedGenerationNames())
        let newName = Self.canonical(intent.newGenerationID)
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID,
              retired == intent.generationIDsToDelete
                || (retired.isEmpty && installed == [newName]) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if intent.schemaVersion == 2 {
            _ = try requirePublishedEmptySession(intent, authority: authority)
        }
    }

    func completeCleanup(
        _ value: EraseIntentV1,
        session: StoreGenerationSession,
        authority: StoreRestoreGenerationAuthority,
        auxiliary: EraseAuxiliaryAuthority,
        diagnosticsStore: DiagnosticsStore,
        intentStore: EraseIntentStore
    ) async throws -> StoreGenerationSession {
        let activated: EraseIntentV1
        if value.phase == .cleanupComplete {
            activated = value.advancing(to: .sessionActivated)
        } else {
            activated = value
        }
        guard activated.phase == .sessionActivated,
              session.generationID == activated.newGenerationID,
              BackupRestoreService.isEmptyCurrent(session.modelContext) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if activated.schemaVersion == 2 {
            let ledger = try DeletionLedgerStore(
                context: session.modelContext
            ).snapshot()
            guard ledger.entries.isEmpty,
                  try ledgerProof(ledger) == expectedEmptyLedger(activated) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }

        if value.phase != .cleanupComplete {
            try inject(.beforeCleanup)
        }
        try cleanupGenerations(activated, authority: authority)
        try requireCleanupPresence(
            activated.advancing(to: .cleanupComplete),
            authority: authority
        )
        // Canonical generation deletion remains the Erase authority above.
        // Device-operational history and operation-scoped scratch are local
        // auxiliary state: clear them explicitly and fail closed before the
        // intent can advance to cleanupComplete. Reconstructing the scratch
        // adapter on retry keeps this step idempotent after an interruption.
        let scratchDataLeaseStore = try ScratchDataLeaseStoreV1(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            clock: Date.init
        )
        try await scratchDataLeaseStore.eraseScratchData()
        try auxiliary.removeFrozenTargets()
        userDefaults.removePersistentDomain(forName: bundleIdentifier)
        // Recreate through a fresh adapter after removing the old anchored
        // directory. This publishes the canonical V2 operational envelope;
        // writing DiagnosticsV1.zero directly would leave legacy bytes for a
        // later migration and would not prove the Erase result at this edge.
        let replacementDiagnosticsStore = DiagnosticsStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        try await replacementDiagnosticsStore.resetOperationalSupport()
        let diagnosticsZeroSnapshot = try await replacementDiagnosticsStore
            .operationalSupportSnapshot()
        guard diagnosticsZeroSnapshot.schemaVersion
                == DeviceOperationalSupportStoreSchemaV2.version,
              diagnosticsZeroSnapshot.counters == .zero,
              diagnosticsZeroSnapshot.health.failures.isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        let diagnosticsZero = try canonicalDiagnosticsZero(
            diagnosticsZeroSnapshot
        )
        await diagnosticsStore.acceptDescriptorErasedZero()
        guard await diagnosticsStore.isExactlyZero(),
              (userDefaults.persistentDomain(forName: bundleIdentifier) ?? [:])
                .isEmpty,
              BackupRestoreService.isEmptyCurrent(session.modelContext) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try auxiliary.verifyTargetsRemovedExceptDiagnostics()
        try auxiliary.verifyDiagnostics(
            expectedData: diagnosticsZero
        )
        if value.phase != .cleanupComplete {
            try inject(.afterCleanup)
        }

        let completed = activated.advancing(to: .cleanupComplete)
        if value.phase != .cleanupComplete {
            try inject(.beforeCleanupPhaseWrite)
            try intentStore.replace(expected: activated, with: completed)
            try inject(.afterCleanupPhaseWrite)
        }
        if completed.schemaVersion == 2 {
            if let preparation = try intentStore.loadPreparation() {
                guard preparation.matches(completed) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try intentStore.removePreparation(expected: preparation)
            } else if value.phase != .cleanupComplete {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try inject(.beforeJournalRemoval)
        try intentStore.remove(expected: completed)
        try auxiliary.removeEraseRootIfEmpty()
        return session
    }

    func cleanupGenerations(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        let initialRetired = try authority.retiredGenerationIDs()
        guard initialRetired == intent.generationIDsToDelete
                || initialRetired.isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        let allowedNames = Set(
            (intent.generationIDsToDelete + [intent.newGenerationID])
                .map(Self.canonical)
        )
        guard Set(try authority.installedGenerationNames())
                .isSubset(of: allowedNames),
              try authority.installedGenerationNames().contains(
                Self.canonical(intent.newGenerationID)
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for id in intent.generationIDsToDelete {
            let name = Self.canonical(id)
            if try authority.installedGenerationNames().contains(name) {
                try generationFactory.removeInstalledGeneration(
                    id: id,
                    keeping: intent.newGenerationID,
                    authority: authority
                )
            }
        }
        guard Set(try authority.installedGenerationNames())
                == [Self.canonical(intent.newGenerationID)] else {
            throw EraseAllServiceError.invalidAuthority
        }
        if initialRetired == intent.generationIDsToDelete {
            try generationFactory.replaceRetiredGenerationIDs(
                expected: initialRetired,
                with: [],
                currentID: intent.newGenerationID,
                authority: authority
            )
        } else if !initialRetired.isEmpty {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireCleanupPresence(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let currentSession: StoreGenerationSession
        if intent.schemaVersion == 2 {
            currentSession = try requirePublishedEmptySession(
                intent,
                authority: authority
            )
        } else {
            currentSession = try generationFactory.openInstalledGeneration(
                id: intent.newGenerationID,
                authority: authority
            )
        }
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID,
              try authority.retiredGenerationIDs().isEmpty,
              Set(try authority.installedGenerationNames())
                == [Self.canonical(intent.newGenerationID)],
              BackupRestoreService.isEmptyCurrent(
                currentSession.modelContext
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func validatedEmptySession(
        id: UUID,
        identity: WorkspaceReplicaIdentityV1? = nil,
        expectedEmptyLedger: DeletionLedgerProofV2? = nil,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        let session: StoreGenerationSession
        if let identity {
            session = try generationFactory.openInstalledGeneration(
                id: id,
                identity: identity,
                authority: authority
            )
        } else {
            session = try generationFactory.openInstalledGeneration(
                id: id,
                authority: authority
            )
        }
        let tree = try authority.installedTree(id: id)
        let allowedFiles: Set<String> = [
            "model.sqlite",
            "model.sqlite-shm",
            "model.sqlite-wal",
        ]
        guard BackupRestoreService.isEmptyCurrent(session.modelContext),
              tree.directories.isEmpty,
              tree.files.contains("model.sqlite"),
              tree.files.isSubset(of: allowedFiles) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try EvidenceAssuranceEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        try InspectionReviewEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        try WorkPacketEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try FieldDraftEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try PackageEvolutionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try ClientCapabilityEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try PrivacyTransformEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try MeasurementIntegrityEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try FieldReferenceEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try AccessibleDocumentEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try SurveyDefinitionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try SurveySessionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try AssetLocatorEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try ScheduleEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try PlanEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        try PlacementPoseEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        if let identity {
            let history = try MutationJournalStoreV1(
                modelContext: session.modelContext,
                identity: identity,
                generationID: id
            ).exportSnapshot()
            guard history.workspaceRevision == 0,
                  history.lastLocalSequence == 0,
                  history.receipts.isEmpty,
                  history.quarantines.isEmpty,
                  history.entityRevisions.isEmpty else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        if let expectedEmptyLedger {
            let ledger = try DeletionLedgerStore(
                context: session.modelContext
            ).snapshot()
            guard ledger.entries.isEmpty,
                  try ledgerProof(ledger) == expectedEmptyLedger else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        return session
    }

    func validateFrozenGeneration(
        id: UUID,
        modelContext: ModelContext,
        generationRootURL: URL,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard !modelContext.hasChanges,
              generationRootURL.standardizedFileURL
                == generationFactory.installedGenerationURL(id: id) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if !BackupRestoreService.isEmptyCurrent(modelContext) {
            _ = try BackupRestoreService.currentSummary(
                modelContext: modelContext,
                generationRootURL: generationRootURL
            )
        }
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        var expectedDirectories = Set<String>()
        var expectedFiles: Set<String> = ["model.sqlite"]
        if !evidence.isEmpty { expectedDirectories.insert("evidence") }
        for value in evidence {
            expectedDirectories.insert("evidence/\(Self.canonical(value.id))")
            expectedFiles.insert(value.relativePath)
            expectedFiles.insert(value.thumbnailRelativePath)
        }
        if !reports.isEmpty { expectedDirectories.insert("snapshots") }
        if reports.contains(where: { $0.pdfRelativePath != nil }) {
            expectedDirectories.insert("pdfs")
        }
        for value in reports {
            expectedFiles.insert(value.snapshotRelativePath)
            if let path = value.pdfRelativePath { expectedFiles.insert(path) }
        }
        let allowedStagingDirectories: Set<String> = [
            ".staging",
            ".staging/evidence",
            ".staging/pdfs",
            ".staging/snapshots",
        ]
        let optionalFiles: Set<String> = [
            "model.sqlite-shm",
            "model.sqlite-wal",
        ]
        let tree = try authority.installedTree(id: id)
        guard expectedDirectories.isSubset(of: tree.directories),
              tree.directories.isSubset(
                of: expectedDirectories.union(allowedStagingDirectories)
              ),
              expectedFiles.isSubset(of: tree.files),
              tree.files.isSubset(of: expectedFiles.union(optionalFiles)),
              !modelContext.hasChanges else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func priorRetiredIDs(_ intent: EraseIntentV1) -> [UUID] {
        intent.generationIDsToDelete.filter { $0 != intent.oldGenerationID }
    }

    func frozenCurrentPointer(
        expectedGenerationID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> RestorePointerIdentityV1 {
        let current = try generationFactory.currentGenerationPointerV3(
            expectedGenerationID: expectedGenerationID,
            authority: authority
        )
        guard let generationID = UUID(uuidString: current.generationID),
              generationID == expectedGenerationID,
              let workspaceID = UUID(uuidString: current.workspaceID),
              let replicaID = UUID(uuidString: current.replicaID) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let knownReplicaIDs = current.knownReplicaIDs.compactMap {
            UUID(uuidString: $0)
        }
        guard knownReplicaIDs.count == current.knownReplicaIDs.count else {
            throw EraseAllServiceError.invalidAuthority
        }
        return RestorePointerIdentityV1(
            generationID: generationID,
            generationManifestSHA256: current.generationManifestSHA256,
            knownReplicaIDs: Set(knownReplicaIDs),
            workspaceID: workspaceID,
            replicaID: replicaID
        )
    }

    func freshEraseIdentity(
        excluding unavailable: Set<UUID>
    ) throws -> WorkspaceReplicaIdentityV1 {
        let zero = UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        )
        for _ in 0..<16 {
            let workspaceID = makeUUID()
            let replicaID = makeUUID()
            guard workspaceID != zero,
                  replicaID != zero,
                  workspaceID != replicaID,
                  !unavailable.contains(workspaceID),
                  !unavailable.contains(replicaID) else {
                continue
            }
            return try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: workspaceID),
                replicaID: ReplicaID(rawValue: replicaID)
            )
        }
        throw EraseAllServiceError.invalidAuthority
    }

    func targetIdentity(
        _ intent: EraseIntentV1
    ) throws -> WorkspaceReplicaIdentityV1 {
        guard let pointer = intent.targetPointer else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: pointer.workspaceID),
            replicaID: ReplicaID(rawValue: pointer.replicaID)
        )
    }

    func ledgerProof(_ ledger: DeletionLedgerV2) throws -> DeletionLedgerProofV2 {
        try DeletionLedgerProofV2(
            entryCount: ledger.entries.count,
            canonicalSHA256: SHA256.hash(
                data: try ledger.canonicalData()
            ).map { String(format: "%02x", $0) }.joined()
        )
    }

    func emptyLedgerProof() throws -> DeletionLedgerProofV2 {
        try ledgerProof(.empty)
    }

    func expectedEmptyLedger(
        _ intent: EraseIntentV1
    ) throws -> DeletionLedgerProofV2 {
        guard intent.schemaVersion == 2,
              intent.targetEmptyProof == EraseEmptyGenerationProofV2(
                  contentRecordCount: 0,
                  deletionLedgerEntryCount: 0
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try emptyLedgerProof()
    }

    func requireSourceLedgerBinding(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard let oldPointer = intent.oldPointer,
              let expected = intent.sourceLedger,
              try generationFactory.currentGenerationDeletionLedgerProof(
                  expectedPointer: oldPointer,
                  authority: authority
              ) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requirePublishedEmptySession(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        guard let oldPointer = intent.oldPointer,
              let targetPointer = intent.targetPointer else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try generationFactory.requirePublishedEmptyEraseGeneration(
            oldPointer: oldPointer,
            targetPointer: targetPointer,
            expectedEmptyLedger: try expectedEmptyLedger(intent),
            authority: authority
        )
    }

    func discardPreparation(
        _ preparation: ErasePreparationV2,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard try generationFactory.currentGenerationDeletionLedgerProof(
            expectedPointer: preparation.oldPointer,
            authority: authority
        ) == preparation.sourceLedger else {
            throw EraseAllServiceError.invalidAuthority
        }
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(
                rawValue: preparation.targetWorkspaceID
            ),
            replicaID: ReplicaID(rawValue: preparation.targetReplicaID)
        )
        try generationFactory.discardPreparedEmptyEraseGeneration(
            expectedOldPointer: preparation.oldPointer,
            targetGenerationID: preparation.targetGenerationID,
            targetIdentity: identity,
            expectedEmptyLedger: try emptyLedgerProof(),
            authority: authority
        )
    }

    func inject(_ point: EraseAllFailurePoint) throws {
        if failureInjection?.consume(point) == true {
            throw EraseAllServiceError.injectedFailure
        }
    }

    func canonicalDiagnosticsZero(
        _ snapshot: DeviceOperationalSupportSnapshotV2
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func canonical(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        canonical(lhs) < canonical(rhs)
    }

    func waitForDrain(_ proof: EraseGenerationDrainProof) async throws -> Bool {
        for _ in 0..<200 {
            if proof.isDrained { return true }
            await Task.yield()
            do {
                try await sleeper.sleep(for: .milliseconds(10))
            } catch is CancellationError {
                return proof.isDrained
            }
        }
        return proof.isDrained
    }
}

private final class EraseAuxiliaryAuthority {
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private struct RegularFileValue {
        let data: Data
        let identity: Identity
    }

    private let applicationSupportURL: URL
    private let cachesDirectoryURL: URL
    private let temporaryDirectoryURL: URL
    private let applicationSupportDescriptor: Int32
    private let cachesDescriptor: Int32
    private let temporaryDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let cachesIdentity: Identity
    private let temporaryIdentity: Identity

    var applicationSupportRootIdentity: StoreApplicationSupportIdentity {
        StoreApplicationSupportIdentity(
            device: applicationSupportIdentity.device,
            inode: applicationSupportIdentity.inode
        )
    }

    init(
        applicationSupportURL: URL,
        cachesDirectoryURL: URL,
        temporaryDirectoryURL: URL
    ) throws {
        let support = applicationSupportURL.standardizedFileURL
        let caches = cachesDirectoryURL.standardizedFileURL
        let temporary = temporaryDirectoryURL.standardizedFileURL
        guard support.isFileURL, caches.isFileURL, temporary.isFileURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        let supportDescriptor = Darwin.open(
            support.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard supportDescriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        var retained = [supportDescriptor]
        var succeeded = false
        defer {
            if !succeeded {
                for descriptor in retained.reversed() {
                    _ = Darwin.close(descriptor)
                }
            }
        }
        let cachesDescriptor = Darwin.open(
            caches.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard cachesDescriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        retained.append(cachesDescriptor)
        let temporaryDescriptor = Darwin.open(
            temporary.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard temporaryDescriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        retained.append(temporaryDescriptor)

        self.applicationSupportURL = support
        self.cachesDirectoryURL = caches
        self.temporaryDirectoryURL = temporary
        self.applicationSupportDescriptor = supportDescriptor
        self.cachesDescriptor = cachesDescriptor
        self.temporaryDescriptor = temporaryDescriptor
        self.applicationSupportIdentity = try Self.identity(supportDescriptor)
        self.cachesIdentity = try Self.identity(cachesDescriptor)
        self.temporaryIdentity = try Self.identity(temporaryDescriptor)
        succeeded = true
    }

    deinit {
        _ = Darwin.close(temporaryDescriptor)
        _ = Darwin.close(cachesDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func verifyTargets() throws {
        try verify()
        for name in [
            "FieldEvidenceRestore",
            "FieldEvidenceOperations",
            "FieldEvidenceCommerce",
            "FieldEvidenceDiagnostics",
            "FieldEvidenceErase",
            LocalSearchIndexStoreV1.directoryName,
        ] {
            try Self.requireAbsentOrValidDirectory(
                parent: applicationSupportDescriptor,
                name: name
            )
        }
        try Self.requireAbsentOrValidDirectory(
            parent: cachesDescriptor,
            name: "FieldEvidenceApp"
        )
        try Self.requireAbsentOrValidDirectory(
            parent: temporaryDescriptor,
            name: "FieldEvidenceApp"
        )
        try verify()
    }

    func requireNoEraseIntent() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.names(in: descriptor).isEmpty else {
            throw EraseAllServiceError.recoveryRequired
        }
        try verify()
    }

    func requireNoRestoreIntent() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceRestore",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT {
            try verify()
            return
        }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try !Self.itemExists(parent: descriptor, name: "restore.json"),
              try !Self.itemExists(
                parent: descriptor,
                name: ".restore.json.next"
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
    }

    func removeFrozenTargets() throws {
        try verifyTargets()
        for name in [
            "FieldEvidenceRestore",
            "FieldEvidenceOperations",
            "FieldEvidenceCommerce",
            "FieldEvidenceDiagnostics",
            LocalSearchIndexStoreV1.directoryName,
        ] {
            try Self.removeDirectoryIfPresent(
                parent: applicationSupportDescriptor,
                name: name
            )
        }
        try Self.removeDirectoryIfPresent(
            parent: cachesDescriptor,
            name: "FieldEvidenceApp"
        )
        try Self.removeDirectoryIfPresent(
            parent: temporaryDescriptor,
            name: "FieldEvidenceApp"
        )
        try verify()
    }

    func verifyTargetsRemovedExceptDiagnostics() throws {
        try verify()
        for name in [
            "FieldEvidenceRestore",
            "FieldEvidenceOperations",
            "FieldEvidenceCommerce",
            LocalSearchIndexStoreV1.directoryName,
        ] {
            guard try !Self.itemExists(
                parent: applicationSupportDescriptor,
                name: name
            ) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard try !Self.itemExists(
            parent: cachesDescriptor,
            name: "FieldEvidenceApp"
        ),
              try !Self.itemExists(
                parent: temporaryDescriptor,
                name: "FieldEvidenceApp"
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try Self.requireAbsentOrDirectory(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceDiagnostics"
        )
        try verify()
    }

    func verifyDiagnostics(expectedData: Data) throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceDiagnostics",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        let expectedDirectory = try Self.identity(descriptor)
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                relativePath: "FieldEvidenceDiagnostics",
                within: applicationSupportURL
            ) {
                try self.verify()
                guard try Self.identity(descriptor) == expectedDirectory,
                      try Self.directoryIdentity(
                          parent: self.applicationSupportDescriptor,
                          name: "FieldEvidenceDiagnostics"
                      ) == expectedDirectory else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        } catch {
            throw EraseAllServiceError.invalidAuthority
        }
        let file = Darwin.openat(
            descriptor,
            "counters.json",
            O_RDONLY | O_NOFOLLOW
        )
        guard file >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(file) }
        let expectedFile = try Self.regularFileIdentity(file)
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                .diagnostics,
                relativePath: "FieldEvidenceDiagnostics/counters.json",
                within: applicationSupportURL
            ) {
                try self.verify()
                guard try Self.identity(descriptor) == expectedDirectory,
                      try Self.regularFileIdentity(file) == expectedFile,
                      try Self.directoryIdentity(
                          parent: self.applicationSupportDescriptor,
                          name: "FieldEvidenceDiagnostics"
                      ) == expectedDirectory else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try Self.verifyRegularFilePath(
                    parent: descriptor,
                    name: "counters.json",
                    expected: expectedFile
                )
            }
        } catch {
            throw EraseAllServiceError.invalidAuthority
        }
        let published = try Self.readRegularFileValue(
            parent: descriptor,
            name: "counters.json"
        )
        guard try Self.names(in: descriptor) == ["counters.json"],
              published.identity == expectedFile,
              published.data == expectedData else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
    }

    func createZeroDiagnostics(data: Data) throws {
        try verify()
        guard Darwin.mkdirat(
            applicationSupportDescriptor,
            "FieldEvidenceDiagnostics",
            mode_t(0o700)
        ) == 0,
              Darwin.fsync(applicationSupportDescriptor) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        let directory = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceDiagnostics",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard directory >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(directory) }
        let expectedDirectory = try Self.identity(directory)
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                relativePath: "FieldEvidenceDiagnostics",
                within: applicationSupportURL
            ) {
                try self.verify()
                guard try Self.identity(directory) == expectedDirectory,
                      try Self.directoryIdentity(
                          parent: self.applicationSupportDescriptor,
                          name: "FieldEvidenceDiagnostics"
                      ) == expectedDirectory else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        } catch {
            throw EraseAllServiceError.invalidAuthority
        }
        let file = Darwin.openat(
            directory,
            "counters.json",
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard file >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(file) }
        let expectedFile: Identity
        do {
            expectedFile = try Self.regularFileIdentity(file)
        } catch {
            throw error
        }
        do {
            do {
                try ProtectedFilePolicyV1.applyAndVerify(
                    .diagnostics,
                    relativePath: "FieldEvidenceDiagnostics/counters.json",
                    within: applicationSupportURL
                ) {
                    try self.verify()
                    guard try Self.identity(directory) == expectedDirectory,
                          try Self.regularFileIdentity(file) == expectedFile,
                          try Self.directoryIdentity(
                              parent: self.applicationSupportDescriptor,
                              name: "FieldEvidenceDiagnostics"
                          ) == expectedDirectory else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try Self.verifyRegularFilePath(
                        parent: directory,
                        name: "counters.json",
                        expected: expectedFile
                    )
                }
            } catch {
                throw EraseAllServiceError.invalidAuthority
            }
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(
                        file,
                        base.advanced(by: offset),
                        raw.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else if errno != EINTR {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            }
            guard Darwin.fsync(file) == 0 else {
                throw EraseAllServiceError.invalidAuthority
            }
        } catch {
            try? Self.removeRegularFileIfExact(
                parent: directory,
                name: "counters.json",
                expected: expectedFile,
                expectedDirectory: expectedDirectory
            )
            throw error
        }
        do {
            guard Darwin.fsync(directory) == 0,
                  try Self.directoryIdentity(
                    parent: applicationSupportDescriptor,
                    name: "FieldEvidenceDiagnostics"
                  ) == expectedDirectory,
                  try Self.names(in: directory) == ["counters.json"] else {
                throw EraseAllServiceError.invalidAuthority
            }
            let published = try Self.readRegularFileValue(
                parent: directory,
                name: "counters.json"
            )
            guard published.identity == expectedFile,
                  published.data == data else {
                throw EraseAllServiceError.invalidAuthority
            }
            try verify()
            try ProtectedFilePolicyV1.applyAndVerify(
                .diagnostics,
                relativePath: "FieldEvidenceDiagnostics/counters.json",
                within: applicationSupportURL
            ) {
                try self.verify()
                guard try Self.identity(directory) == expectedDirectory,
                      try Self.regularFileIdentity(file) == expectedFile else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try Self.verifyRegularFilePath(
                    parent: directory,
                    name: "counters.json",
                    expected: expectedFile
                )
            }
            try verify()
        } catch {
            try? Self.removeRegularFileIfExact(
                parent: directory,
                name: "counters.json",
                expected: expectedFile,
                expectedDirectory: expectedDirectory
            )
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func removeEraseRootIfEmpty() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.names(in: descriptor).isEmpty,
              Darwin.unlinkat(
                applicationSupportDescriptor,
                "FieldEvidenceErase",
                AT_REMOVEDIR
              ) == 0,
              Darwin.fsync(applicationSupportDescriptor) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
    }

    private func verify() throws {
        try Self.require(applicationSupportDescriptor, applicationSupportIdentity)
        try Self.require(cachesDescriptor, cachesIdentity)
        try Self.require(temporaryDescriptor, temporaryIdentity)
        try Self.requirePath(applicationSupportURL, applicationSupportIdentity)
        try Self.requirePath(cachesDirectoryURL, cachesIdentity)
        try Self.requirePath(temporaryDirectoryURL, temporaryIdentity)
    }

    private static func removeDirectoryIfPresent(
        parent: Int32,
        name: String
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        let expected: Identity
        do {
            expected = try identity(descriptor)
            try removeContents(descriptor)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
        _ = Darwin.close(descriptor)
        guard try directoryIdentity(parent: parent, name: name) == expected,
              Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0,
              Darwin.fsync(parent) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func removeContents(_ directory: Int32) throws {
        for name in try names(in: directory) {
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw EraseAllServiceError.invalidAuthority
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                try removeDirectoryIfPresent(parent: directory, name: name)
            case S_IFREG:
                guard info.st_nlink == 1,
                      Darwin.unlinkat(directory, name, 0) == 0 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            default:
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard Darwin.fsync(directory) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func requireAbsentOrDirectory(
        parent: Int32,
        name: String
    ) throws {
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else {
                throw EraseAllServiceError.invalidAuthority
            }
            return
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func requireAbsentOrValidDirectory(
        parent: Int32,
        name: String
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        let expected = try identity(descriptor)
        try validateContents(descriptor)
        guard try directoryIdentity(parent: parent, name: name) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func validateContents(_ directory: Int32) throws {
        for name in try names(in: directory) {
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw EraseAllServiceError.invalidAuthority
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let child = Darwin.openat(
                    directory,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                do {
                    let opened = try identity(child)
                    guard opened.device == info.st_dev,
                          opened.inode == info.st_ino else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try validateContents(child)
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
            case S_IFREG:
                guard info.st_nlink == 1 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            default:
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    private static func itemExists(parent: Int32, name: String) throws -> Bool {
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            return true
        }
        guard errno == ENOENT else {
            throw EraseAllServiceError.invalidAuthority
        }
        return false
    }

    private static func directoryIdentity(
        parent: Int32,
        name: String
    ) throws -> Identity {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        return try identity(descriptor)
    }

    private static func names(in descriptor: Int32) throws -> [String] {
        let independent = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard independent >= 0,
              let directory = Darwin.fdopendir(independent) else {
            if independent >= 0 { _ = Darwin.close(independent) }
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.closedir(directory) }
        var result = [String]()
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { result.append(name) }
            errno = 0
        }
        guard errno == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        return result.sorted()
    }

    private static func readRegularFileValue(
        parent: Int32,
        name: String
    ) throws -> RegularFileValue {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw EraseAllServiceError.invalidAuthority
        }
        let expected = Identity(device: info.st_dev, inode: info.st_ino)
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                result.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1,
              Identity(device: after.st_dev, inode: after.st_ino) == expected,
              after.st_size == info.st_size,
              result.count == Int(after.st_size) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return RegularFileValue(data: result, identity: expected)
    }

    private static func regularFileIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw EraseAllServiceError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func verifyRegularFilePath(
        parent: Int32,
        name: String,
        expected: Identity
    ) throws {
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Identity(device: info.st_dev, inode: info.st_ino) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func removeRegularFileIfExact(
        parent: Int32,
        name: String,
        expected: Identity,
        expectedDirectory: Identity
    ) throws {
        guard try identity(parent) == expectedDirectory else {
            throw EraseAllServiceError.invalidAuthority
        }
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { return }
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try regularFileIdentity(descriptor) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
        var current = stat()
        guard Darwin.fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              (current.st_mode & S_IFMT) == S_IFREG,
              current.st_nlink == 1,
              Identity(device: current.st_dev, inode: current.st_ino) == expected,
              Darwin.unlinkat(parent, name, 0) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        guard Darwin.fsync(parent) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        var absent = stat()
        guard Darwin.fstatat(parent, name, &absent, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func require(
        _ descriptor: Int32,
        _ expected: Identity
    ) throws {
        guard try identity(descriptor) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func requirePath(
        _ url: URL,
        _ expected: Identity
    ) throws {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try identity(descriptor) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Deletion_EraseAllService {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

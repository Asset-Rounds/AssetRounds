import Darwin
import CryptoKit
import Foundation

#if DEBUG
/// Measurement only. Fixed stage labels and process RSS cannot expose source
/// paths or payloads and never participate in an Erase authority decision.
enum CompletedAbortRSSStageV1: String {
    case prealiasEntry, prealiasExact, prealiasCanonical, prealiasPhysical
    case postcloseEntry, postcloseSource, postclosePhysical
    case privateCopyStart, privateCopyFiles, privateCopyCopied
    case privateCopyIntegrity, privateCopyRead, privateCopyClosed
    case postclosePrivateRead, postcloseFinalSource, postcloseFinalPhysical

    static func record(_ stage: Self) {
        var value = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0, &count)
            }
        }
        let resident = status == KERN_SUCCESS
            ? String(value.resident_size / 1024) : "unavailable"
        FileHandle.standardError.write(Data((
            "ERASE_COMPLETED_ABORT_RSS_V1 stage=" + stage.rawValue
            + " residentKiB=" + resident + "\n").utf8))
    }
}
#endif

enum C50IncumbentFileExchangeEraseAllBoundaryV1 {
    static let removesAppOwnedScratch = true
    static let removesAppOwnedQuarantine = true
    static let recallsEscapedFiles = false
    static let disablesOrRewritesInstalledProfileRelease = false
}

enum PrivateSystemDiscoveryEraseAllServiceBoundaryV1 {
    static func erase(
        operationID: PrivateSystemDiscoveryOperationIDV1,
        index: any PrivateSystemDiscoveryIndexLifecyclePortV1,
        now: Date
    ) async throws {
        try PrivateSystemDiscoveryEraseIntentBoundaryV1.validate()
        try await index.eraseAll(operationID: operationID, now: now)
    }

    static func dropAfterRestoreOrReplay(
        operationID: PrivateSystemDiscoveryOperationIDV1,
        index: any PrivateSystemDiscoveryIndexLifecyclePortV1
    ) async throws {
        try operationID.validate()
        guard operationID.operation == .removal else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        // Restore/replay uses the same durable, idempotent global-removal
        // state machine as Erase, while remaining derived-only and creating no
        // canonical deletion or backup rows.
        try await index.eraseAll(operationID: operationID, now: Date())
    }
}

protocol EncryptedPortableEnvelopeEraseScratchV1: Sendable {
    func eraseEncryptedPortableEnvelopeScratch() async throws
}

enum C54EncryptedPortableEnvelopeEraseAllBoundaryV1 {
    static let removesAppOwnedAttemptScratch = true
    static let clearsMemoryOnlySecrets = true
    static let recallsEscapedFiles = false
    static let revokesAlreadySharedBytes = false
    static let createsCanonicalDeletionRows = false

    static func eraseScratch(
        using authority: any EncryptedPortableEnvelopeEraseScratchV1
    ) async throws {
        try await authority.eraseEncryptedPortableEnvelopeScratch()
    }

    static func validate() -> Bool {
        removesAppOwnedAttemptScratch
            && clearsMemoryOnlySecrets
            && !recallsEscapedFiles
            && !revokesAlreadySharedBytes
            && !createsCanonicalDeletionRows
    }
}

enum C34SceneNavigationEraseAllBoundaryV1 {
    static func validate() throws {
        guard C34SceneNavigationDeviceLifecycleBoundaryV1.validate() else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

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

enum C49WorkResourceEraseAllBoundaryV1 {
    static let replacementGenerationContainsNoCarriedWorkResourceRows = true
    static let embeddedDirectCostsDisappearWithTheirRows = true
    static let derivedIndexesRequireNoIndependentEraseTruth = true
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

enum LightingDayInventoryEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(
            FetchDescriptor<LightingDayInventoryWorkflowRowV1>()
        ) == 0 else { throw EraseAllServiceError.invalidAuthority }
    }
}

enum LightingNightWorkflowEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<LightingNightWorkflowRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
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
enum ServiceRequestEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        try ServiceRequestPersistenceEnrollmentV1.validate()
        try C52ServiceRequestKernelDeletionEraseEnrollmentV1.validate()
        guard try context.fetchCount(FetchDescriptor<ServiceRequestRecordRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ServiceRequestDispositionEventRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ServiceRequestWorkLinkEventRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}
enum AssetServiceReliabilityEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        try AssetServiceReliabilityPersistenceEnrollmentV1.validate()
        guard C53AssetServiceReliabilityEraseIntentBoundaryV1.validate(),
              try context.fetchCount(FetchDescriptor<AssetServiceIncidentRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ServiceImpactSegmentRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ServiceCauseAssertionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ServiceRemedyAssertionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ServiceRepairIntervalRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ServiceRestorationAssertionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<QualifiedServiceExposureRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}
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
    static let durableFamilyCount = 4
    static let embeddedClosureComponentCount = 6
    static let projectionsAreDerived = true
    static let notificationStateIsTruth = false

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard persistentSchemaVersion == 27,
              recordsSchemaVersion == 26,
              durableFamilyCount == 4,
              embeddedClosureComponentCount == C51ScheduleBackupClosureV1.embeddedCanonicalComponents.count,
              ScheduleEraseBoundaryV1.erasePublishesNoPartialCalendarOverrideOrBasisClosure,
              projectionsAreDerived,
              !notificationStateIsTruth,
              try context.fetchCount(FetchDescriptor<ScheduleDefinitionReleaseRow>()) == 0,
              try context.fetchCount(FetchDescriptor<OccurrenceHistoryEventRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ExceptionCalendarReleaseRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ScheduleOverrideEventRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

enum C57MyDayEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<MyDayCarryoverReceiptRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

/// The activated post-Erase generation must contain neither V43 metadata
/// family. The generation swap owns physical row and content removal; this
/// verifier prevents an old association/sequence chain from being resurrected.
enum EvidenceMetadataEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        try EvidenceMetadataKernelDeletionEraseEnrollmentV1.validate()
        guard try context.fetchCount(
            FetchDescriptor<EvidenceAssociationEventRowV1>()
        ) == 0,
        try context.fetchCount(
            FetchDescriptor<EvidenceSequenceRevisionRowV1>()
        ) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

/// Shop-report profiles are immutable workspace-local history. A workspace
/// erase publishes a new V44 generation and therefore must carry no profile
/// rows or surviving active-profile frontier.
enum C04ShopReportProfileEraseAllPolicyV1 {
    static let persistentSchemaVersion = 44
    static let recordsSchemaVersion = 43
    static let durableFamilyCount = 1

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        try C04ShopReportProfileKernelDeletionEraseEnrollmentV1.validate()
        guard persistentSchemaVersion
                == C04ShopReportProfileBackupEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion
                == C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount
                == C04ShopReportProfileBackupEnrollmentV1.durableFamilyCount,
              try context.fetchCount(FetchDescriptor<ShopReportProfileRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

/// Round sessions retain item completion only as immutable history during
/// ordinary asset deletion. A full workspace erase produces a V45 generation
/// with no retained round-session rows.
enum C05RoundSessionEraseAllPolicyV1 {
    static let persistentSchemaVersion = 45
    static let recordsSchemaVersion = 44
    static let durableFamilyCount = 1
    static let ordinaryAssetDeletionPreservesSessionHistory = true

    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        try C05RoundSessionKernelDeletionEraseEnrollmentV1.validate()
        guard persistentSchemaVersion
                == C05RoundSessionBackupEnrollmentV1.persistentSchemaVersion,
              recordsSchemaVersion
                == C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion,
              durableFamilyCount
                == C05RoundSessionBackupEnrollmentV1.durableFamilyCount,
              ordinaryAssetDeletionPreservesSessionHistory,
              try context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()) == 0 else {
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

/// Retains actual exclusions and exact unclosed resources while every strong
/// SwiftData alias leaves its owning scope. No arbitrary Error is retained.
@MainActor
final class EraseSessionRetirementV1 {
    enum Phase: Equatable { case waitingForAliases, closingLeases, closeFailed, retired }
    enum FailureBoundary: String { case readerAllocation, readerLease, writerLease, emptyCensus }
    private(set) var phase: Phase = .waitingForAliases
    private(set) var failureBoundary: FailureBoundary?
    let binding: EraseRetirementBindingV1
    private let exclusion: EraseRetirementExclusionV1
    private let drain: EraseSessionDrainWitnessV1
    private let frozenIntent: EraseIntentV1
    private var pendingAllocations: [GenerationLeaseAllocationAttemptV1]
    private var pendingReaders: [GenerationLeaseHandleV1]
    private var proof: ErasedRegistryRetirementProofV1?

    fileprivate init(exclusion: EraseRetirementExclusionV1, drain: EraseSessionDrainWitnessV1,
                     intent: EraseIntentV1, intentStore: EraseIntentStore,
                     observation: EraseIntentStore.RetirementObservation) throws {
        guard EraseIntentCodecV1.valid(intent),
              intent.phase == .sessionActivated || intent.phase == .cleanupComplete,
              intent.eraseID == drain.binding.subject.eraseID,
              intent.newGenerationID == drain.binding.subject.newGenerationID,
              observation.intent == intent else {
            throw EraseAllServiceError.invalidAuthority
        }
        try exclusion.requireSupport(binding: drain.binding)
        try intentStore.requireRetirementObservation(observation)
        frozenIntent = intent
        binding = drain.binding
        self.exclusion = exclusion
        self.drain = drain
        pendingAllocations = drain.capturedAllocations
        let allocated = drain.capturedAllocations.compactMap { $0.allocatedHandle }
        pendingReaders = drain.capturedReaders.filter { reader in
            !allocated.contains(where: { $0 === reader })
        }
    }

    func ownsProof(_ value: ErasedRegistryRetirementProofV1) -> Bool {
        phase == .retired && proof === value
    }

    /// This is called only after the context-bearing producer/service frames
    /// have returned. A retained original or private reader remains pending.
    func validateAndAdvance(factory: StoreGenerationFactory,
        authority: StoreRestoreGenerationAuthority, targetReader: GenerationLeaseHandleV1,
        manifestScope: EraseCurrentManifestScopeV1) async throws -> ErasedRegistryRetirementProofV1? {
        if let proof { return proof }
        guard drain.isActuallyDrained else { return nil }
        guard try await factory.validateOrResumeEraseTargetAfterOriginalDrain(binding: binding,
            reader: targetReader, drain: drain, exclusion: exclusion, authority: authority,
            intent: frozenIntent, manifestScope: manifestScope) else { return nil }
        return try advanceAfterActualDrain()
    }

    /// Nil means actual aliases still exist, not a timeout or retry success.
    /// The same owner must remain reachable across cancellation and failure.
    func advanceAfterActualDrain() throws -> ErasedRegistryRetirementProofV1? {
        if let proof { return proof }
        try exclusion.requireSupport(binding: binding)
        guard drain.isActuallyDrained else { return nil }
        phase = .closingLeases
        do {
            while let allocation = pendingAllocations.first {
                failureBoundary = .readerAllocation
                try exclusion.closeAllocationAfterDrain(allocation: allocation, proof: drain)
                pendingAllocations.removeFirst()
            }
            while let reader = pendingReaders.first {
                failureBoundary = .readerLease
                try exclusion.closeReaderAfterDrain(handle: reader, proof: drain)
                pendingReaders.removeFirst()
            }
            failureBoundary = .writerLease
            try exclusion.closeWriterAfterDrain(proof: drain)
            failureBoundary = .emptyCensus
            try exclusion.requireNoLeasesAfterDrain(proof: drain)
            let value = ErasedRegistryRetirementProofV1(binding: binding,
                exclusion: exclusion, drain: drain, frozenIntent: frozenIntent)
            proof = value
            failureBoundary = nil
            phase = .retired
            return value
        } catch {
            // Exact remaining handles/attempts and exclusion stay in this owner.
            // Error values from arbitrary adapters cannot retain old contexts.
            phase = .closeFailed
            throw EraseAllServiceError.recoveryRequired
        }
    }
}

/// A consuming, operation-bound physical retirement capability. Metadata
/// alone cannot create it. Removal retry retains the same capability and EX.
@MainActor
final class ErasedRegistryRetirementProofV1 {
    private enum Phase: Equatable {
        case ready, manifestPreparing, readyWithOriginalManifest, manifestMoving, manifestPreserved
        case removingNamespace, namespaceRemoved, releasingManifestResources, released
        case abandonmentPending, abandoned, closeUncertain
        case preDeletionAbandonPending, preDeletionAbandoned
    }
    let binding: EraseRetirementBindingV1
    private let exclusion: EraseRetirementExclusionV1
    private let drain: EraseSessionDrainWitnessV1
    private let frozenIntent: EraseIntentV1
    private var phase: Phase = .ready
    private var manifestAttempt: EraseManifestRetirementAttemptV1?
    private var manifestStore: StoreMigrationJournalStoreV1?
    private var freshFactoryClaimed = false
#if DEBUG
    // The checked close still calls the real manifest witness, which requires
    // the physically accurate `.namespaceRemoved` phase. This separate latch
    // makes the abandon entry one-way before that synchronous close begins.
    private var abandonmentReleaseEntered = false
#endif

    fileprivate init(binding: EraseRetirementBindingV1,
                     exclusion: EraseRetirementExclusionV1,
                     drain: EraseSessionDrainWitnessV1, frozenIntent: EraseIntentV1) {
        self.binding = binding
        self.exclusion = exclusion
        self.drain = drain
        self.frozenIntent = frozenIntent
    }

    func prepareManifestRetirement(using store: StoreMigrationJournalStoreV1) throws
        -> EraseManifestRetirementAttemptV1 {
        if phase == .readyWithOriginalManifest || phase == .manifestMoving || phase == .manifestPreserved {
            guard manifestStore === store, let attempt = manifestAttempt,
                  attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
                throw EraseAllServiceError.invalidAuthority
            }
            return attempt // exact retained retry owner, never another constructor
        }
        if phase == .ready {
            try requireCurrentGenerationValidation()
            let attempt = try store.makeEraseManifestRetirementAttempt(binding: binding,
                exclusion: exclusion, retirement: self)
            manifestAttempt = attempt
            manifestStore = store
            phase = .manifestPreparing // retained before any descriptor acquisition
        }
        guard phase == .manifestPreparing, manifestStore === store,
              let attempt = manifestAttempt else { throw EraseAllServiceError.invalidAuthority }
        try attempt.observeOriginalAfterRegistration(retirement: self)
        try drain.registerManifestRetirement(attempt, retirement: self,
            exclusion: exclusion, store: store)
        phase = .readyWithOriginalManifest
        return attempt
    }

    func requireManifestAttemptCreation(exclusion expected: EraseRetirementExclusionV1,
        binding expectedBinding: EraseRetirementBindingV1) throws {
        guard expected === exclusion, binding == expectedBinding, phase == .ready,
              manifestAttempt == nil, manifestStore == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireCurrentGenerationValidation()
    }

    func requireManifestPreparation(exclusion expected: EraseRetirementExclusionV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard expected === exclusion, phase == .manifestPreparing,
              manifestAttempt === attempt,
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
        // The witness still uses its original immutable manifest observation
        // here. Attachment happens only after exact original capture succeeds.
        try exclusion.requireNoLeasesAfterDrain(proof: drain)
    }

    func requireManifestRegistration(witness expectedWitness: EraseSessionDrainWitnessV1,
        attempt: EraseManifestRetirementAttemptV1, store: StoreMigrationJournalStoreV1,
        exclusion expectedExclusion: EraseRetirementExclusionV1) throws {
        guard drain === expectedWitness, manifestStore === store else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireManifestPreparation(exclusion: expectedExclusion, attempt: attempt)
    }

    func requireInitialManifestTransfer(exclusion expected: EraseRetirementExclusionV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard expected === exclusion, phase == .readyWithOriginalManifest,
              manifestAttempt === attempt,
              drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireManifestTransferOwnership(exclusion expected: EraseRetirementExclusionV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard expected === exclusion,
              phase == .manifestMoving || phase == .manifestPreserved,
              manifestAttempt === attempt,
              drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Deliberately no generic witness call in this retained moving phase.
    }

    func beginManifestTransfer(attempt: EraseManifestRetirementAttemptV1) throws {
        try requireInitialManifestTransfer(exclusion: exclusion, attempt: attempt)
        try exclusion.beginManifestTransfer(retirement: self, attempt: attempt)
        phase = .manifestMoving // no throwing operation after core registration
    }

    func recordManifestPreserved(attempt: EraseManifestRetirementAttemptV1) throws {
        guard phase == .manifestMoving || phase == .manifestPreserved else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireManifestTransferOwnership(exclusion: exclusion, attempt: attempt)
        try exclusion.requireManifestTransferRetry(retirement: self, attempt: attempt)
        try attempt.requirePreserved(binding: binding, exclusion: exclusion, retirement: self)
        phase = .manifestPreserved
    }

    func requireManifestNamespaceRemovalAdmission(exclusion expected: EraseRetirementExclusionV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard expected === exclusion, phase == .manifestPreserved,
              manifestAttempt === attempt, drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
        // The complete original control set is still required at this edge.
        try exclusion.requireNoLeasesAfterDrain(proof: drain)
    }

    func requireManifestNamespaceRetirementOwnership(exclusion expected: EraseRetirementExclusionV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard expected === exclusion,
              phase == .removingNamespace || phase == .namespaceRemoved,
              manifestAttempt === attempt, drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
        // This is exact consumed removal ownership, not proof that arbitrary
        // missing controls were valid or that the current manifest is absent.
    }

    func requireManifestResourceRelease(exclusion expected: EraseRetirementExclusionV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard expected === exclusion, phase == .releasingManifestResources,
              manifestAttempt === attempt, drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Actual EX release has already succeeded. No read/access is granted.
    }

    fileprivate func beginFrozenTargetRemoval(using auxiliary: EraseAuxiliaryAuthority) throws {
        let support = auxiliary.applicationSupportRootIdentity
        guard phase == .manifestPreserved,
              Int64(support.device) == binding.subject.applicationSupportDevice,
              UInt64(support.inode) == binding.subject.applicationSupportInode,
              let attempt = manifestAttempt else { throw EraseAllServiceError.invalidAuthority }
        try exclusion.requireSupport(binding: binding)
        try drain.requireDrained(binding: binding)
        try attempt.sealOriginalNamespaceForRemoval(retirement: self)
        phase = .removingNamespace // no throwing/await gap after consuming seal
    }

    fileprivate func removeFrozenTargets(using auxiliary: EraseAuxiliaryAuthority) throws {
        let support = auxiliary.applicationSupportRootIdentity
        guard Int64(support.device) == binding.subject.applicationSupportDevice,
              UInt64(support.inode) == binding.subject.applicationSupportInode else {
            throw EraseAllServiceError.invalidAuthority
        }
        if phase == .manifestPreserved { try beginFrozenTargetRemoval(using: auxiliary) }
        guard phase == .removingNamespace else { throw EraseAllServiceError.invalidAuthority }
        try exclusion.requireSupport(binding: binding)
        try drain.requireDrained(binding: binding)
        try auxiliary.removeFrozenTargets(expectedOperationsIdentity: binding.registryIdentity)
        try requireOperationsAbsent()
        phase = .namespaceRemoved
    }

    func requireCurrentGenerationValidation() throws {
        guard phase == .ready || phase == .readyWithOriginalManifest || phase == .manifestPreserved else {
            throw EraseAllServiceError.invalidAuthority
        }
        try exclusion.requireNoLeasesAfterDrain(proof: drain)
    }

    func readPointer(using authority: StoreRestoreGenerationAuthority, name: String) throws -> Data {
        try requireCurrentGenerationValidation()
        let data = try authority.readPointerForEraseRetirement(name: name,
            binding: binding, exclusion: exclusion)
        try requireCurrentGenerationValidation()
        return data
    }

    func readCurrentManifest(using store: StoreMigrationJournalStoreV1,
        generationID: UUID, expectedDigest: String) throws -> StoreGenerationManifestV1 {
        try requireCurrentGenerationValidation()
        guard generationID == binding.subject.newGenerationID,
              expectedDigest == binding.generationEpoch.generationManifestSHA256 else {
            throw EraseAllServiceError.invalidAuthority
        }
        let manifest: StoreGenerationManifestV1
        if let attempt = manifestAttempt {
            guard manifestStore === store else { throw EraseAllServiceError.invalidAuthority }
            manifest = try attempt.requireCurrentManifest(binding: binding, exclusion: exclusion)
        } else {
            manifest = try store.readManifestForEraseRetirement(
                targetGenerationID: generationID, expectedDigest: expectedDigest,
                binding: binding, exclusion: exclusion)
        }
        try requireCurrentGenerationValidation()
        return manifest
    }

    func requireGenerationDeletion(id: UUID, keeping currentID: UUID) throws {
        try requireCurrentGenerationValidation()
        guard currentID == frozenIntent.newGenerationID, id != currentID,
              frozenIntent.generationIDsToDelete.contains(id) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireRetiredPointerClear(expected: [UUID], currentID: UUID) throws {
        try requireCurrentGenerationValidation()
        guard currentID == frozenIntent.newGenerationID,
              expected == frozenIntent.generationIDsToDelete else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    /// The only journal bypass of ordinary registry acquisition is this fixed
    /// sessionActivated -> cleanupComplete CAS after actual namespace removal.
    func requireCleanupPhaseWrite(expected: EraseIntentV1,
                                  replacement: EraseIntentV1) throws {
#if DEBUG
        guard !abandonmentReleaseEntered else { throw EraseAllServiceError.invalidAuthority }
#endif
        guard phase == .namespaceRemoved,
              expected.eraseID == binding.subject.eraseID,
              expected.newGenerationID == binding.subject.newGenerationID,
              expected == frozenIntent.advancing(to: .sessionActivated),
              expected.phase == .sessionActivated,
              replacement == expected.advancing(to: .cleanupComplete) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try drain.requireDrained(binding: binding)
        try requireOperationsAbsent()
    }

    func requireCompletionControlRemoval(expected: EraseIntentV1) throws {
#if DEBUG
        guard !abandonmentReleaseEntered else { throw EraseAllServiceError.invalidAuthority }
#endif
        guard phase == .namespaceRemoved,
              expected == frozenIntent.advancing(to: .cleanupComplete) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireNamespaceAbsent()
    }

    func requireAlreadyAbsentPreparation(expected: EraseIntentV1) throws {
        try requireCompletionControlRemoval(expected: expected)
        guard frozenIntent.phase == .cleanupComplete else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireNamespaceAbsent() throws {
        guard phase == .namespaceRemoved else { throw EraseAllServiceError.invalidAuthority }
        try drain.requireDrained(binding: binding)
        try requireOperationsAbsent()
    }

    fileprivate func releaseAfterCompletion() throws {
#if DEBUG
        guard !abandonmentReleaseEntered else { throw EraseAllServiceError.invalidAuthority }
#endif
        if phase == .namespaceRemoved {
            try requireNamespaceAbsent()
            let eraseRoot = binding.subject.applicationSupportURL
                .appendingPathComponent("FieldEvidenceErase", isDirectory: true)
            var information = stat()
            guard Darwin.lstat(eraseRoot.path, &information) != 0, errno == ENOENT else {
                throw EraseAllServiceError.invalidAuthority
            }
            // Strong drain still observes the actual held manifest descriptors
            // through this final support-EX release. Closing them comes after.
            try exclusion.releaseAfterNamespaceRemoval(binding: binding)
            phase = .releasingManifestResources
        }
        guard phase == .releasingManifestResources, let attempt = manifestAttempt else {
            throw EraseAllServiceError.invalidAuthority
        }
        try attempt.closeAfterExclusionRelease(retirement: self)
        phase = .released
    }

#if DEBUG
    /// This point is after genuine semantic validation/lease retirement,
    /// before any old-generation unlink or manifest namespace transfer.
    func requireReadyForPreDeletionAbandonmentForTesting(
        registry: GenerationLeaseRegistryV1
    ) throws {
        guard phase == .ready, manifestAttempt == nil,
              manifestStore == nil, !freshFactoryClaimed,
              !abandonmentReleaseEntered else {
            throw EraseAllServiceError.invalidAuthority
        }
        try exclusion.requirePostRetiredReadyForTesting(
            proof: self, registry: registry)
    }

    func requirePreDeletionAbandonmentPendingForTesting(
        registry: GenerationLeaseRegistryV1
    ) throws {
        guard phase == .preDeletionAbandonPending else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requirePreDeletionExclusionClosedForTesting(
        registry: GenerationLeaseRegistryV1
    ) throws {
        try requirePreDeletionAbandonmentPendingForTesting(registry: registry)
        try exclusion.requirePostRetiredColdClosedForTesting(
            proof: self, registry: registry)
    }

    func abandonBeforeDeletionForTesting(
        registry: GenerationLeaseRegistryV1
    ) throws {
        // The exact witness/empty census was checked before the Registry
        // installed its selective fence; it cannot be reentered outside scope.
        guard phase == .ready, manifestAttempt == nil,
              manifestStore == nil, !freshFactoryClaimed else {
            throw EraseAllServiceError.invalidAuthority
        }
        phase = .preDeletionAbandonPending
        do {
            try exclusion.closeBeforeNamespaceRemovalForTesting(proof: self)
            try registry.unlinkPostRetiredEraseOwnerGuard(proof: self)
            phase = .preDeletionAbandoned
        } catch {
            phase = .closeUncertain
            throw error
        }
    }

    /// A test-host cold restart boundary after real lease retirement and
    /// namespace removal. It does not remove the Erase root or finish Erase.
    fileprivate func requireReadyForLateAbandonmentForTesting() throws {
        guard phase == .namespaceRemoved, !abandonmentReleaseEntered else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireNamespaceAbsent()
    }

    fileprivate func abandonAfterNamespaceRemovalForTesting() throws {
        try requireReadyForLateAbandonmentForTesting()
        // Keep the physical phase at `.namespaceRemoved` until the actual
        // existing release returns: the retained validation attempt calls
        // requireManifestNamespaceRetirementOwnership during its final drain
        // and must still see this exact consumed namespace phase. Router,
        // operation and outer cleanup have already been terminal-poisoned.
        abandonmentReleaseEntered = true
        do {
            try exclusion.abandonAfterNamespaceRemovalForTesting(binding: binding)
            phase = .abandoned
        } catch {
            phase = .closeUncertain
            throw error
        }
    }
#endif

    func consumeFreshFactoryCreation() throws {
        guard phase == .released, !freshFactoryClaimed else {
            throw EraseAllServiceError.invalidAuthority
        }
        freshFactoryClaimed = true
    }

    private func requireOperationsAbsent() throws {
        try exclusion.requireSupport(binding: binding)
        let root = binding.subject.applicationSupportURL
            .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
        var information = stat()
        guard Darwin.lstat(root.path, &information) != 0, errno == ENOENT else {
            throw EraseAllServiceError.invalidAuthority
        }
        try exclusion.requireSupport(binding: binding)
    }
}

struct EraseAllOutcome {
    /// The original Router retains actual retirement ownership. No session
    /// whose reader namespace is being retired can escape as a usable result.
    let operation: EraseRouterOperationV1
}

struct EraseAllOperationSubjectV1: Equatable, Sendable {
    let eraseID: UUID
    let newGenerationID: UUID
    let applicationSupportURL: URL
    let applicationSupportDevice: Int64
    let applicationSupportInode: UInt64

    fileprivate init(
        eraseID: UUID,
        newGenerationID: UUID,
        applicationSupportURL: URL,
        applicationSupportDevice: Int64,
        applicationSupportInode: UInt64
    ) {
        self.eraseID = eraseID
        self.newGenerationID = newGenerationID
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        self.applicationSupportDevice = applicationSupportDevice
        self.applicationSupportInode = applicationSupportInode
    }
}

struct CompletedEraseReceiptV1: Sendable {
    let subject: EraseAllOperationSubjectV1
    let reservation: AppAccessGateV1.EraseAdoptionToken?

    fileprivate init(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken?
    ) {
        self.subject = subject
        self.reservation = reservation
    }
}

struct AbortedEraseAdmissionReceiptV1: Sendable {
    let subject: EraseAllOperationSubjectV1
    let reservation: AppAccessGateV1.EraseAdoptionToken
    let originalGenerationID: UUID

    fileprivate init(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken,
        originalGenerationID: UUID
    ) {
        self.subject = subject
        self.reservation = reservation
        self.originalGenerationID = originalGenerationID
    }

#if DEBUG
    /// Compares only the original synchronous callback's concrete authority.
    /// The reservation's equality includes its unforgeable gate owner, mint,
    /// and configuration revision; this receipt is not a general Equatable.
    func matchesExactOriginalAuthority(_ other: Self) -> Bool {
        subject == other.subject && reservation == other.reservation
            && originalGenerationID == other.originalGenerationID
    }
#endif
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
    case afterSessionRetirementBeforeCleanup
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

#if DEBUG
    func isPending(_ point: EraseAllFailurePoint) -> Bool { pending == point }
#endif

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
    /// Defaults may be injected with an isolated suite in tests. The app
    /// identity remains independently fixed by `bundleIdentifier`.
    private let defaultsDomainName: String
    private let makeUUID: () -> UUID
    private let sleeper: any ApplicationSleeper
    private let failureInjection: EraseAllFailureInjection?
    private let sceneNavigationStatePort: (any SceneNavigationDeviceStatePortV1)?
    private let privateSystemDiscoveryIndex: (any PrivateSystemDiscoveryIndexLifecyclePortV1)?
    private let notificationSystem: any NotificationSystemPortV1
    private let admitErase: (@MainActor (EraseAllOperationSubjectV1) async throws -> AppAccessGateV1.EraseAdoptionToken)?
    private let didCompleteErase: (@MainActor (CompletedEraseReceiptV1) -> Void)?
    private let didAbortEraseAdmission: (@MainActor (AbortedEraseAdmissionReceiptV1) -> Void)?
    private var admittedSubject: EraseAllOperationSubjectV1?
    private var admittedReservation: AppAccessGateV1.EraseAdoptionToken?

#if DEBUG
    var erasePhaseDiagnosticForTesting: (@MainActor (String) -> Void)?
    /// Hostile fixture observes only the newly owned private scratch copy.
    /// It cannot select or obtain the original generation source FD.
    var completedAbortPrivateCopyMutationForTesting:
        (@MainActor (URL) throws -> Void)?
    /// Runs only after the private SwiftData aliases have drained; it proves
    /// the exclusive cleanup refuses a substituted child before any unlink.
    var completedAbortPrivateCopyPostReadMutationForTesting:
        (@MainActor (URL) throws -> Void)?
    /// One-shot fixture seam after the real old-generation deletion and
    /// before retired-pointer clear. A test may leave an exact crash cut and
    /// throw; the same retained operation then performs the real retry.
    var afterOldGenerationDeletionBeforeRetiredPointerClearForTesting:
        (@MainActor () throws -> Void)?
    /// The genuine cold Service's fresh retained-source context supplies a
    /// value-only before/after refusal readback. Test code never receives its
    /// ModelContext or retains a reader across the failed cold attempt.
    var v949RetainedSourceReadbackForTesting:
        (@MainActor (V949ColdSourceReadbackV1,
            V949ColdSourceReadbackV1) -> Void)?
    /// Opt-in only for the two genuine S6 original-owner cold-exit fixtures.
    /// The witness is captured before the first effect-capable await and
    /// remains retained if any later control or descriptor close is uncertain.
    var enableOriginalColdExitWitnessForTesting = false
    /// Set before the first opt-in observation. A throwing observer may own an
    /// ambiguously closed descriptor, so this exact original frame remains
    /// host-retained even when no completed witness can be installed.
    private var originalColdExitAttempt: (
        operation: EraseRouterOperationV1,
        auxiliary: EraseAuxiliaryAuthority,
        authority: StoreRestoreGenerationAuthority
    )?
    private var originalColdExitFrame: EraseOriginalColdExitFrameV1?
    private var eraseDiagnosticPhase = "not-entered"
    private var interruptedOriginalPreparationFault: EraseAllFailurePoint?
    private var originalFrameIntentStore: EraseIntentStore?
    private var originalFrameExpectedIntent: EraseIntentV1?
    private var originalFrameEmittedAbort = false
    private weak var originalFrameOperation: EraseRouterOperationV1?
    private var originalEraseFrameActive = false
    private weak var originalPreparedForPostRetired: EraseCleanupAfterRetirementV1?
    private var postRetiredServiceAbandoned = false

    func requirePostRetiredOriginalServiceForTesting(
        operation: EraseRouterOperationV1
    ) throws {
        guard !originalEraseFrameActive, !postRetiredServiceAbandoned,
              originalFrameOperation === operation,
              let prepared = originalPreparedForPostRetired,
              operation.ownsPostRetiredPreparedForTesting(prepared) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    /// Observe the sealed pre-deletion marker through the exact original
    /// prepared owner; this never creates a replacement notification store.
    func requirePostRetiredOriginalNotificationForTesting(
        operation: EraseRouterOperationV1
    ) throws {
        try requirePostRetiredOriginalServiceForTesting(operation: operation)
        guard let prepared = originalPreparedForPostRetired else {
            throw EraseAllServiceError.invalidAuthority
        }
        try prepared.requireOriginalPostEffectNotificationForTesting()
    }

    func poisonPostRetiredOriginalServiceForTesting(
        operation: EraseRouterOperationV1
    ) throws {
        try requirePostRetiredOriginalServiceForTesting(operation: operation)
        postRetiredServiceAbandoned = true
    }

    func requirePristineOriginalPreparedColdExitForTesting(
        operation: EraseRouterOperationV1,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken
    ) throws {
        guard !originalEraseFrameActive, !postRetiredServiceAbandoned,
              !originalFrameEmittedAbort,
              originalFrameOperation === operation,
              let prepared = originalPreparedForPostRetired,
              operation.ownsPostRetiredPreparedForTesting(prepared),
              originalColdExitFrame != nil,
              let store = originalFrameIntentStore,
              let expectedIntent = originalFrameExpectedIntent,
              expectedIntent.eraseID == subject.eraseID,
              expectedIntent.newGenerationID == subject.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        try store.requireLiveOriginalColdShutdownIntent(
            sameOperationAs: expectedIntent)
        try prepared.requirePristineOriginalPreparedColdExitForTesting(
            subject: subject, expectedReservation: reservation)
    }

    func poisonPristineOriginalPreparedColdExitForTesting(
        operation: EraseRouterOperationV1,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken
    ) throws {
        try requirePristineOriginalPreparedColdExitForTesting(
            operation: operation, subject: subject,
            reservation: reservation)
        guard let prepared = originalPreparedForPostRetired else {
            throw EraseAllServiceError.invalidAuthority
        }
        try prepared.beginPristineOriginalPreparedColdExitForTesting(
            subject: subject, expectedReservation: reservation)
        postRetiredServiceAbandoned = true
    }
    private var expectedCompletedAbortFault: EraseAllFailurePoint?
    private weak var expectedCompletedAbortOperation: EraseRouterOperationV1?
    private var completedAbortFrame: CompletedAbortFrame?

    private final class CompletedAbortFrame {
        let nonce = UUID()
        let expectedFault: EraseAllFailurePoint
        let operation: EraseRouterOperationV1
        let auxiliary: EraseAuxiliaryAuthority
        let generationAuthority: StoreRestoreGenerationAuthority
        var oldPointer: RestorePointerIdentityV1?
        var sourceLedger: DeletionLedgerProofV2?
        var sourceManifestMigrationID: UUID?
        var sourceManifestRelease: PersistentSchemaReleaseV1?
        var priorRetired: [UUID] = []
        var targetID: UUID?
        var sourceBytes: EraseCompletedAbortSourceBytesV1?
        var deliveredAbort: AbortedEraseAdmissionReceiptV1?
        var deliveredAbortCount = 0
        var canonicalBeforeAliasRelease: EraseCompletedAbortCanonicalSourceV1?
        var physicalBeforeAliasRelease: CompletedAbortSQLitePhysicalImageV1?
        let protectedIngressOrigin: String?
        var uncertain = false

        init(expectedFault: EraseAllFailurePoint,
             operation: EraseRouterOperationV1,
             auxiliary: EraseAuxiliaryAuthority,
             generationAuthority: StoreRestoreGenerationAuthority) throws {
            self.expectedFault = expectedFault
            self.operation = operation
            self.auxiliary = auxiliary
            self.generationAuthority = generationAuthority
            protectedIngressOrigin = try auxiliary.completedAbortProtectedIngressTree()
        }

        func requireProtectedIngressUnchanged() throws {
            guard try auxiliary.completedAbortProtectedIngressTree()
                    == protectedIngressOrigin else {
                throw EraseAllServiceError.invalidAuthority
            }
        }

        private func report(_ stage: String) {
            FileHandle.standardError.write(Data((
                "ERASE_COMPLETED_ABORT_PROOF_V1 stage=" + stage + "\n"
            ).utf8))
        }

        private func reportSourceDifference(
            expected: EraseCompletedAbortSourceBytesV1,
            observed: EraseCompletedAbortSourceBytesV1
        ) {
            // Every emitted word is a fixed field or ownership category. The
            // compared paths, identities, bytes and digests never leave this frame.
            func identityFields(_ first: String, _ second: String,
                                prefix: String) -> [String] {
                let lhs = first.split(separator: "|", omittingEmptySubsequences: false)
                let rhs = second.split(separator: "|", omittingEmptySubsequences: false)
                guard lhs.count == 9, rhs.count == 9 else {
                    return [prefix + "-shape"]
                }
                let labels = ["device", "inode", "mode", "links", "size",
                              "mtime-seconds", "mtime-nanoseconds",
                              "ctime-seconds", "ctime-nanoseconds"]
                return labels.indices.compactMap { index in
                    lhs[index] == rhs[index] ? nil : prefix + "-" + labels[index]
                }
            }
            var differences: [String] = []
            if expected.current != observed.current {
                differences.append("current-bytes")
            }
            differences += identityFields(expected.currentIdentity,
                                          observed.currentIdentity,
                                          prefix: "current")
            if expected.retired != observed.retired {
                differences.append("retired-bytes")
            }
            differences += identityFields(expected.retiredIdentity,
                                          observed.retiredIdentity,
                                          prefix: "retired")
            if expected.sourceTreeDigest != observed.sourceTreeDigest {
                differences.append("source-tree")
                let paths = Set(expected.sourceNodes.keys)
                    .union(observed.sourceNodes.keys).sorted()
                if let first = paths.first(where: {
                    expected.sourceNodes[$0] != observed.sourceNodes[$0]
                }) {
                    let before = expected.sourceNodes[first]
                    let after = observed.sourceNodes[first]
                    let node = after ?? before
                    let nodeType = node?.nodeType == "directory"
                        ? GenerationOwnedPathV1.NodeType.directory
                        : GenerationOwnedPathV1.NodeType.regularFile
                    let ownedKind = first.isEmpty ? "generation-root" :
                        ((try? GenerationOwnedPathV1.classify(
                            first, nodeType: nodeType))?.kind.rawValue ?? "unknown")
                    let fixedFields = ["device", "inode", "mode", "nlink",
                                       "size", "mtime", "ctime", "membership", "sha256"]
                    let changedFields: [String]
                    if before == nil { changedFields = ["node-added"] }
                    else if after == nil { changedFields = ["node-removed"] }
                    else {
                        changedFields = fixedFields.filter {
                            before?.fields[$0] != after?.fields[$0]
                        }
                    }
                    differences.append("node-" + (node?.nodeType == "directory"
                        ? "directory" : "file"))
                    differences.append("owned-" + ownedKind)
                    differences += changedFields.map { "field-" + $0 }
                } else {
                    differences.append("node-facts-equal")
                }
            }
            report("no-effect.source-difference." + differences.joined(separator: ","))
        }

        func bindSource(oldPointer: RestorePointerIdentityV1,
                        sourceLedger: DeletionLedgerProofV2,
                        priorRetired: [UUID],
                        before: EraseCompletedAbortSourceBytesV1?,
                        after: EraseCompletedAbortSourceBytesV1?) {
            self.oldPointer = oldPointer
            self.sourceLedger = sourceLedger
            self.priorRetired = priorRetired
            guard let before, let after, before == after else {
                if before == nil {
                    report("source.before-unavailable")
                } else if after == nil {
                    report("source.after-unavailable")
                } else if let before, let after {
                    if before.current != after.current {
                        report("source.current-bytes-different")
                    } else if before.currentIdentity != after.currentIdentity {
                        report("source.current-identity-different")
                    } else if before.retired != after.retired {
                        report("source.retired-bytes-different")
                    } else if before.retiredIdentity != after.retiredIdentity {
                        report("source.retired-identity-different")
                    } else if before.sourceTreeDigest != after.sourceTreeDigest {
                        report("source.tree-different")
                    } else {
                        report("source.other-difference")
                    }
                }
                uncertain = true
                return
            }
            sourceBytes = before
        }

        func observeSourceManifest(_ manifest: StoreGenerationManifestV1) {
            guard sourceManifestMigrationID == nil,
                  sourceManifestRelease == nil else {
                report("source-manifest-observed-more-than-once")
                uncertain = true
                return
            }
            sourceManifestMigrationID = manifest.migrationID
            sourceManifestRelease = manifest.storeSchemaRelease
        }

        func bindTarget(_ targetID: UUID) {
            self.targetID = targetID
            do { try generationAuthority.requireCompletedAbortTargetAbsent(targetID) }
            catch {
                report("target-absence-binding-failed")
                uncertain = true
            }
        }

        func recordAbort(_ receipt: AbortedEraseAdmissionReceiptV1) {
            deliveredAbortCount += 1
            if deliveredAbortCount == 1 { deliveredAbort = receipt }
            else { uncertain = true }
        }

        func requireReceipt(_ receipt: AbortedEraseAdmissionReceiptV1,
                            operation expected: EraseRouterOperationV1) throws {
            guard operation === expected, deliveredAbortCount == 1,
                  deliveredAbort?.matchesExactOriginalAuthority(receipt) == true,
                  receipt.originalGenerationID == oldPointer?.generationID,
                  receipt.subject.newGenerationID == targetID else {
                throw EraseAllServiceError.invalidAuthority
            }
        }

        func requireNoEffect(_ receipt: AbortedEraseAdmissionReceiptV1,
                             operation expected: EraseRouterOperationV1) throws {
            var stage = "receipt"
            do {
                try requireReceipt(receipt, operation: expected)
                stage = "bound-source"
                guard !uncertain, let oldPointer, let sourceBytes, let targetID else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "protected-ingress-before"
                try requireProtectedIngressUnchanged()
                stage = "erase-root-before"
                try auxiliary.requireEraseRootAbsentForAbortedAdmission()
                stage = "target-before"
                try generationAuthority.requireCompletedAbortTargetAbsent(targetID)
                stage = "source-bytes"
                let observed = try generationAuthority.snapshotCompletedAbortSource(
                    id: oldPointer.generationID, oldPointer: oldPointer,
                    priorRetired: priorRetired)
                guard observed == sourceBytes else {
                    reportSourceDifference(expected: sourceBytes, observed: observed)
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "erase-root-after"
                try auxiliary.requireEraseRootAbsentForAbortedAdmission()
                stage = "target-after"
                try generationAuthority.requireCompletedAbortTargetAbsent(targetID)
                stage = "protected-ingress-after"
                try requireProtectedIngressUnchanged()
            } catch {
                report("no-effect." + stage + "." + String(reflecting: type(of: error)))
                throw error
            }
        }

        /// The five-fact pre-alias proof remains exact. After a checked
        /// SwiftData teardown, only the three already-present SQLite leaves
        /// may change size, timestamps, or bytes; their names, source inodes,
        /// modes and link counts remain fixed. Every other source/control
        /// fact, including generation membership, stays byte-identical.
        func postCloseSource(
            _ receipt: AbortedEraseAdmissionReceiptV1,
            operation expected: EraseRouterOperationV1
        ) throws -> EraseCompletedAbortSourceBytesV1 {
            try requireReceipt(receipt, operation: expected)
            guard !uncertain, canonicalBeforeAliasRelease != nil,
                  let oldPointer, let sourceBytes, let targetID else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireProtectedIngressUnchanged()
            try auxiliary.requireEraseRootAbsentForAbortedAdmission()
            try generationAuthority.requireCompletedAbortTargetAbsent(targetID)
            let observed = try generationAuthority.snapshotCompletedAbortSource(
                id: oldPointer.generationID, oldPointer: oldPointer,
                priorRetired: priorRetired)
            guard observed.current == sourceBytes.current,
                  observed.currentIdentity == sourceBytes.currentIdentity,
                  observed.retired == sourceBytes.retired,
                  observed.retiredIdentity == sourceBytes.retiredIdentity,
                  Set(observed.sourceNodes.keys) == Set(sourceBytes.sourceNodes.keys),
                  observed.sourceNodes["model.sqlite"] != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            let sqlite: Set<String> = ["model.sqlite", "model.sqlite-wal", "model.sqlite-shm"]
            let stableSQLiteFields = ["device", "inode", "mode", "nlink"]
            let allSQLiteFields: Set<String> = ["device", "inode", "mode", "nlink",
                                                 "size", "mtime", "ctime", "sha256"]
            for (path, before) in sourceBytes.sourceNodes {
                guard let after = observed.sourceNodes[path] else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if sqlite.contains(path) {
                    guard before.nodeType == "file", after.nodeType == "file",
                          Set(before.fields.keys) == allSQLiteFields,
                          Set(after.fields.keys) == allSQLiteFields,
                          stableSQLiteFields.allSatisfy({
                              before.fields[$0] == after.fields[$0]
                          }) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                } else if before != after {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            try auxiliary.requireEraseRootAbsentForAbortedAdmission()
            try generationAuthority.requireCompletedAbortTargetAbsent(targetID)
            try requireProtectedIngressUnchanged()
            return observed
        }
    }

    func expectCompletedAbortColdShutdownForTesting(
        _ point: EraseAllFailurePoint, operation: EraseRouterOperationV1
    ) throws {
        guard !originalEraseFrameActive,
              point == .afterEmptyGenerationDirectoryCreate
                || point == .beforePreparedWrite else {
            throw EraseAllServiceError.invalidAuthority
        }
        expectedCompletedAbortFault = point
        expectedCompletedAbortOperation = operation
    }

    func requireCompletedAbortColdShutdownForTesting(
        _ point: EraseAllFailurePoint, operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard !originalEraseFrameActive,
              interruptedOriginalPreparationFault == point,
              originalFrameOperation === operation,
              originalFrameEmittedAbort,
              let frame = completedAbortFrame,
              frame.expectedFault == point else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.requireReceipt(receipt, operation: operation)
    }

    func requireCompletedAbortNoEffectForTesting(
        operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard !originalEraseFrameActive,
              let frame = completedAbortFrame,
              originalFrameOperation === operation else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.requireNoEffect(receipt, operation: operation)
    }

    /// The original callback and operation remain bound after checked source
    /// closure. The exact five-fact source is separately proved at pre-alias
    /// seal; this receipt check alone grants no post-close source acceptance.
    func requireCompletedAbortReceiptForExclusiveScratch(
        operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        guard !originalEraseFrameActive,
              let frame = completedAbortFrame,
              originalFrameOperation === operation else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.requireReceipt(receipt, operation: operation)
    }

    /// Called inside the original G scope while AppAccess still retains its
    /// exact original coordinator. This first repeats the unchanged five-fact
    /// source proof, then records the full V53 committed rows and mutation
    /// history as value types. No new owner, session or reader is constructed.
    func sealCompletedAbortCanonicalBeforeAliasReleaseForTesting(
        operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        var diagnosticStage = "authority"
        do {
        guard !originalEraseFrameActive,
              let frame = completedAbortFrame,
              originalFrameOperation === operation,
              frame.canonicalBeforeAliasRelease == nil,
              frame.physicalBeforeAliasRelease == nil,
              let pointer = frame.oldPointer,
              let migrationID = frame.sourceManifestMigrationID,
              frame.sourceManifestRelease == .v53,
              coordinator.generationID == pointer.generationID,
              coordinator.generationRootURL.standardizedFileURL
                == generationFactory.installedGenerationURL(
                    id: pointer.generationID).standardizedFileURL,
              coordinator.workspaceID.rawValue == pointer.workspaceID,
              coordinator.replicaID.rawValue == pointer.replicaID else {
            throw EraseAllServiceError.invalidAuthority
        }
        CompletedAbortRSSStageV1.record(.prealiasEntry)
        diagnosticStage = "no-effect-before"
        try frame.requireNoEffect(receipt, operation: operation)
        CompletedAbortRSSStageV1.record(.prealiasExact)
        diagnosticStage = "canonical-source"
        // This synchronous pool releases SwiftData/Foundation export temporaries
        // while the original context and EX/G remain held by their owners.
        // The returned canonical values remain strongly retained by `baseline`.
        let baseline = try autoreleasepool {
            try generationFactory.completedAbortCanonicalSource(
                in: coordinator.modelContext,
                generationRootURL: coordinator.generationRootURL,
                generationID: pointer.generationID,
                migrationID: migrationID,
                expectedIdentity: coordinator.workspaceIdentity)
        }
        CompletedAbortRSSStageV1.record(.prealiasCanonical)
        guard let source = frame.sourceBytes else {
            throw EraseAllServiceError.invalidAuthority
        }
        diagnosticStage = "physical-source"
        let physical = try frame.generationAuthority.completedAbortSQLitePhysicalImage(
            id: pointer.generationID, treeDigest: source.sourceTreeDigest)
        CompletedAbortRSSStageV1.record(.prealiasPhysical)
        diagnosticStage = "no-effect-after"
        try frame.requireNoEffect(receipt, operation: operation)
        frame.canonicalBeforeAliasRelease = baseline
        frame.physicalBeforeAliasRelease = physical
        } catch {
            FileHandle.standardError.write(Data((
                "ERASE_COMPLETED_ABORT_PREALIAS_V1 stage=" + diagnosticStage + "\n"
            ).utf8))
            throw error
        }
    }

    /// After all original aliases and reader/writer handles have checked
    /// closed, the original EX/G operation permits one private source read.
    /// Exact controls and every non-SQLite node are checked before and after
    /// the copy. A changed SQLite representation is accepted only if the
    /// copied committed rows, entire receipt history, and V53 integrity
    /// validation are equal to the sealed pre-alias source.
    func requireCompletedAbortPostCloseNoEffectForTesting(
        operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1,
        permit: CompletedAbortExclusiveScratchPermitV1
    ) throws {
        try permit.requireHeld()
        guard !originalEraseFrameActive,
              let frame = completedAbortFrame,
              originalFrameOperation === operation,
              let pointer = frame.oldPointer,
              let migrationID = frame.sourceManifestMigrationID,
              frame.sourceManifestRelease == .v53,
              let expected = frame.canonicalBeforeAliasRelease,
              let beforePhysical = frame.physicalBeforeAliasRelease,
              expected.workspaceIdentity.workspaceID.rawValue == pointer.workspaceID,
              expected.workspaceIdentity.replicaID.rawValue == pointer.replicaID else {
            throw EraseAllServiceError.invalidAuthority
        }
        CompletedAbortRSSStageV1.record(.postcloseEntry)
        let before = try frame.postCloseSource(receipt, operation: operation)
        CompletedAbortRSSStageV1.record(.postcloseSource)
        let afterPhysical = try frame.generationAuthority.completedAbortSQLitePhysicalImage(
            id: pointer.generationID, treeDigest: before.sourceTreeDigest)
        try beforePhysical.requireOwnedCloseTransition(to: afterPhysical)
        CompletedAbortRSSStageV1.record(.postclosePhysical)
        let observed = try generationFactory
            .completedAbortCanonicalSourceFromExclusiveCopy(
                generationID: pointer.generationID,
                migrationID: migrationID,
                expectedIdentity: expected.workspaceIdentity,
                expectedTreeDigest: before.sourceTreeDigest,
                operationID: receipt.subject.eraseID,
                sourceAuthority: frame.generationAuthority,
                permit: permit,
                requireProtectedIngressUnchanged: {
                    try frame.requireProtectedIngressUnchanged()
                },
                afterCopyBeforeReadForTesting:
                    completedAbortPrivateCopyMutationForTesting,
                afterReadBeforeCleanupForTesting:
                    completedAbortPrivateCopyPostReadMutationForTesting)
        CompletedAbortRSSStageV1.record(.postclosePrivateRead)
        guard observed == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
        let after = try frame.postCloseSource(receipt, operation: operation)
        CompletedAbortRSSStageV1.record(.postcloseFinalSource)
        let finalPhysical = try frame.generationAuthority.completedAbortSQLitePhysicalImage(
            id: pointer.generationID, treeDigest: after.sourceTreeDigest)
        CompletedAbortRSSStageV1.record(.postcloseFinalPhysical)
        guard after == before,
              after.sourceNodes == before.sourceNodes,
              finalPhysical == afterPhysical else {
            throw EraseAllServiceError.invalidAuthority
        }
        try permit.requireHeld()
    }

    func requireCompletedAbortFreshLedgerForTesting(
        operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1,
        coordinator: StoreSessionCoordinator,
        witness: EraseOriginalShutdownWitnessV1,
        registry: GenerationLeaseRegistryV1
    ) throws {
        try requireCompletedAbortNoEffectForTesting(
            operation: operation, receipt: receipt)
        guard let frame = completedAbortFrame,
              let expected = frame.sourceLedger,
              let sourceBytes = frame.sourceBytes,
              let manifestMigrationID = frame.sourceManifestMigrationID,
              let manifestRelease = frame.sourceManifestRelease,
              coordinator.generationID == receipt.originalGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        try generationFactory.requireFreshCompletedAbortSourceLedger(
            coordinator: coordinator, witness: witness,
            registry: registry, sourceAuthority: frame.generationAuthority,
            sourceBytes: sourceBytes,
            manifestMigrationID: manifestMigrationID,
            manifestRelease: manifestRelease,
            expected: expected,
            reproveOriginal: {
                try frame.requireNoEffect(receipt, operation: operation)
            })
        try requireCompletedAbortNoEffectForTesting(
            operation: operation, receipt: receipt)
    }

    /// The configured original service records the consumed injection, after
    /// its entire synchronous/async frame has returned. A caller's enum alone
    /// cannot attest that the original Erase stopped at that fault boundary.
    func requireInterruptedOriginalPreparationFaultForTesting(
        _ expected: EraseAllFailurePoint,
        operation: EraseRouterOperationV1
    ) throws {
        guard !originalEraseFrameActive,
              originalFrameOperation === operation,
              interruptedOriginalPreparationFault == expected,
              !originalFrameEmittedAbort,
              let store = originalFrameIntentStore,
              let expectedIntent = originalFrameExpectedIntent else {
            throw EraseAllServiceError.invalidAuthority
        }
        try store.requireLiveOriginalColdShutdownIntent(
            sameOperationAs: expectedIntent)
    }

    /// The retired-authority fixture returns the authenticated durable value
    /// from this exact original frame. It never constructs a reparative Store.
    func interruptedRetiredAuthorityIntentForTesting(
        _ expected: EraseAllFailurePoint,
        operation: EraseRouterOperationV1
    ) throws -> EraseIntentV1 {
        let phase: EraseIntentPhaseV1
        switch expected {
        case .afterPreparedWrite, .beforePointerSwitch,
             .afterPointerSwitch, .beforePointerPhaseWrite:
            phase = .emptyGenerationPrepared
        case .afterPointerPhaseWrite, .beforeSessionActivation,
             .afterSessionActivation, .beforeSessionPhaseWrite:
            phase = .pointerSwitched
        case .afterSessionPhaseWrite, .beforeCleanup:
            phase = .sessionActivated
        default:
            throw EraseAllServiceError.invalidAuthority
        }
        guard !originalEraseFrameActive,
              originalFrameOperation === operation,
              interruptedOriginalPreparationFault == expected,
              !originalFrameEmittedAbort,
              let store = originalFrameIntentStore,
              let expectedIntent = originalFrameExpectedIntent else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try store.readLiveOriginalColdShutdownIntent(
            sameOperationAs: expectedIntent, requiringPhase: phase)
    }

    /// Capture the actual original frame before its Router releases the old
    /// guard/EX. The later test owner may reprove this immutable binding, but
    /// it may never mint a baseline from bytes observed after handoff.
    func capturePostHandoffHostileSourceForTesting(
        operation: EraseRouterOperationV1
    ) throws -> V949OriginalEraseSourceBindingV1 {
        let persisted = try interruptedRetiredAuthorityIntentForTesting(
            .afterPointerSwitch, operation: operation)
        guard enableOriginalColdExitWitnessForTesting,
              let frame = originalColdExitFrame,
              persisted.oldGenerationID != persisted.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try frame.capturePostHandoffHostileSource(
            operation: operation, intent: persisted)
    }

    /// Called only by the retained original operation under its physical EX
    /// and Registry G, before the first checked source reader/writer close.
    func beginV949OwnedSourceCloseTransitionForTesting(
        _ binding: V949OriginalEraseSourceBindingV1,
        operation: EraseRouterOperationV1
    ) throws {
        let intent = try interruptedRetiredAuthorityIntentForTesting(
            .afterPointerSwitch, operation: operation)
        guard originalFrameOperation === operation,
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.beginOwnedSourceCloseTransition(
            binding: binding, operation: operation, intent: intent)
    }

    /// Called after all actual source aliases and leases checked-close, but
    /// before the original G/EX/guard release. Failure leaves that owner held.
    func completeV949OwnedSourceCloseTransitionForTesting(
        _ binding: V949OriginalEraseSourceBindingV1,
        operation: EraseRouterOperationV1
    ) throws {
        let intent = try interruptedRetiredAuthorityIntentForTesting(
            .afterPointerSwitch, operation: operation)
        guard originalFrameOperation === operation,
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.completeOwnedSourceCloseTransition(
            binding: binding, operation: operation, intent: intent)
    }

    /// A distinct, one-use transition for the newly retained fixture reader.
    /// Its owner calls these only inside its fresh Registry G and Support EX,
    /// before the hostile callback receives the opened SwiftData session.
    func beginV949OwnedReaderOpenTransitionForTesting(
        _ witness: V949PostHandoffHostileFixtureWitnessV1,
        owner: V949RetiredSourceFixtureOwnerV1
    ) throws {
        try owner.requireReaderOpenProofAuthority(witness)
        guard witness.originalService === self,
              originalFrameOperation === witness.operation,
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        let intent = try interruptedRetiredAuthorityIntentForTesting(
            .afterPointerSwitch, operation: witness.operation)
        try frame.beginOwnedReaderOpenTransition(binding: witness.binding,
            operation: witness.operation, intent: intent)
    }

    func completeV949OwnedReaderOpenTransitionForTesting(
        _ witness: V949PostHandoffHostileFixtureWitnessV1,
        owner: V949RetiredSourceFixtureOwnerV1
    ) throws {
        try owner.requireReaderOpenProofAuthority(witness)
        guard witness.originalService === self,
              originalFrameOperation === witness.operation,
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        let intent = try interruptedRetiredAuthorityIntentForTesting(
            .afterPointerSwitch, operation: witness.operation)
        try frame.completeOwnedReaderOpenTransition(binding: witness.binding,
            operation: witness.operation, intent: intent)
    }

    func requireV949PostHandoffOriginalSourceUnchanged(
        _ binding: V949OriginalEraseSourceBindingV1,
        operation: EraseRouterOperationV1
    ) throws {
        guard originalFrameOperation === operation,
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.requireV949OriginalSourceUnchanged(binding,
            operation: operation)
    }

    func requireV949PostHandoffControlsUnchanged(
        _ binding: V949OriginalEraseSourceBindingV1,
        operation: EraseRouterOperationV1
    ) throws {
        guard originalFrameOperation === operation,
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.requireV949ControlsUnchanged(binding,
            operation: operation)
    }

    func requireOriginalNotificationReadbackRefusalForColdExitForTesting(
        operation: EraseRouterOperationV1,
        subject: EraseAllOperationSubjectV1
    ) throws {
        guard !originalEraseFrameActive,
              originalFrameOperation === operation,
              !originalFrameEmittedAbort,
              let frame = originalColdExitFrame,
              let store = originalFrameIntentStore,
              let expectedIntent = originalFrameExpectedIntent,
              expectedIntent.eraseID == subject.eraseID,
              expectedIntent.newGenerationID == subject.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        try store.requireLiveOriginalColdShutdownIntent(
            sameOperationAs: expectedIntent)
        try frame.requireOriginalNotificationRefusal(
            operation: operation, subject: subject)
    }

    func poisonOriginalNotificationReadbackRefusalForColdExitForTesting(
        operation: EraseRouterOperationV1,
        subject: EraseAllOperationSubjectV1
    ) throws {
        guard !postRetiredServiceAbandoned else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireOriginalNotificationReadbackRefusalForColdExitForTesting(
            operation: operation, subject: subject)
        postRetiredServiceAbandoned = true
    }
#endif

    private func traceErasePhase(_ phase: String) {
#if DEBUG
        guard let diagnostic = erasePhaseDiagnosticForTesting else { return }
        eraseDiagnosticPhase = phase
        diagnostic(phase)
#endif
    }

    private var eraseFactoryPhaseDiagnostic: (@MainActor (String) -> Void)? {
#if DEBUG
        guard let diagnostic = erasePhaseDiagnosticForTesting else { return nil }
        return { [self] phase in
            if phase.hasPrefix("ERASE_FILE_SNAPSHOT_V1 ") {
                diagnostic(phase)
            } else {
                traceErasePhase(phase)
            }
        }
#else
        return nil
#endif
    }

    private func traceEraseOriginalFailure(_ error: Error) {
#if DEBUG
        guard let diagnostic = erasePhaseDiagnosticForTesting else { return }
        diagnostic("original-failure.phase." + eraseDiagnosticPhase
            + ".type." + String(reflecting: type(of: error)))
#endif
    }

    init(
        applicationSupportURL: URL,
        cachesDirectoryURL: URL? = nil,
        temporaryDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier
            ?? "com.palatis3.fieldrecord",
        defaultsDomainName: String? = nil,
        makeUUID: @escaping () -> UUID = UUID.init,
        sleeper: any ApplicationSleeper = SystemApplicationSleeper(),
        failureInjection: EraseAllFailureInjection? = nil,
        sceneNavigationStatePort: (any SceneNavigationDeviceStatePortV1)? = nil,
        privateSystemDiscoveryIndex: (any PrivateSystemDiscoveryIndexLifecyclePortV1)? = PrivateSystemDiscoveryIndexRuntimeV1.shared,
        notificationSystem: (any NotificationSystemPortV1)? = nil,
        admitErase: (@MainActor (EraseAllOperationSubjectV1) async throws -> AppAccessGateV1.EraseAdoptionToken)? = nil,
        didCompleteErase: (@MainActor (CompletedEraseReceiptV1) -> Void)? = nil,
        didAbortEraseAdmission: (@MainActor (AbortedEraseAdmissionReceiptV1) -> Void)? = nil
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
        self.defaultsDomainName = defaultsDomainName ?? bundleIdentifier
        self.makeUUID = makeUUID
        self.sleeper = sleeper
        self.failureInjection = failureInjection
        self.sceneNavigationStatePort = sceneNavigationStatePort
        self.privateSystemDiscoveryIndex = privateSystemDiscoveryIndex
        self.notificationSystem = notificationSystem ?? UserNotificationSystemAdapterV1()
        self.admitErase = admitErase
        self.didCompleteErase = didCompleteErase
        self.didAbortEraseAdmission = didAbortEraseAdmission
    }

    /// Configuration only. The Router supplies its actual provider/inventory
    /// before execution; no ticket, lease or cleanup authority is minted here.
    /// Copying preserves injected service behavior until its original scopes
    /// and callbacks can be released at the explicit detach boundary.
    func configuredForRetirement(factory: StoreGenerationFactory,
        inventory: EraseReaderRetirementInventoryV1) throws -> EraseAllService {
        guard admittedSubject == nil, admittedReservation == nil,
              factory.restoreApplicationSupportURL.standardizedFileURL == applicationSupportURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        return EraseAllService(copying: self,
            generationFactory: try factory.capturingEraseReaders(in: inventory))
    }

    func configuredForColdRetirement(factory: StoreGenerationFactory,
        inventory: EraseReaderRetirementInventoryV1) throws -> EraseAllService {
        guard admittedSubject == nil, admittedReservation == nil,
              factory.restoreApplicationSupportURL.standardizedFileURL == applicationSupportURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        try factory.requireEraseReaderInventory(inventory)
        return EraseAllService(copying: self, generationFactory: factory)
    }

    private init(copying service: EraseAllService, generationFactory: StoreGenerationFactory) {
        applicationSupportURL = service.applicationSupportURL
        cachesDirectoryURL = service.cachesDirectoryURL
        temporaryDirectoryURL = service.temporaryDirectoryURL
        self.generationFactory = generationFactory
        fileManager = service.fileManager
        userDefaults = service.userDefaults
        bundleIdentifier = service.bundleIdentifier
        defaultsDomainName = service.defaultsDomainName
        makeUUID = service.makeUUID
        sleeper = service.sleeper
        failureInjection = service.failureInjection
        sceneNavigationStatePort = service.sceneNavigationStatePort
        privateSystemDiscoveryIndex = service.privateSystemDiscoveryIndex
        notificationSystem = service.notificationSystem
        admitErase = service.admitErase
        didCompleteErase = service.didCompleteErase
        didAbortEraseAdmission = service.didAbortEraseAdmission
#if DEBUG
        enableOriginalColdExitWitnessForTesting =
            service.enableOriginalColdExitWitnessForTesting
        erasePhaseDiagnosticForTesting = service.erasePhaseDiagnosticForTesting
        v949RetainedSourceReadbackForTesting =
            service.v949RetainedSourceReadbackForTesting
        completedAbortPrivateCopyMutationForTesting =
            service.completedAbortPrivateCopyMutationForTesting
        completedAbortPrivateCopyPostReadMutationForTesting =
            service.completedAbortPrivateCopyPostReadMutationForTesting
#endif
    }

    func erase(
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        operation: EraseRouterOperationV1,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> EraseAllOutcome {
        try await erase(
            confirmation: confirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnosticsStore,
            activate: activate,
            operation: operation,
            lifecycleRoute: .expiringCompatibility(
                posture: WorkspacePackageLifecycleCompatibilityV1.expiration
            )
        )
    }

    func erase(
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        operation: EraseRouterOperationV1,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,
        lifecycleDependencies dependencies: WorkspacePackageLifecycleDependenciesV1
    ) async throws -> EraseAllOutcome {
        try await erase(
            confirmation: confirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnosticsStore,
            activate: activate,
            operation: operation,
            lifecycleRoute: .live(dependencies: dependencies)
        )
    }

    private func erase(
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,
        operation: EraseRouterOperationV1,
        lifecycleRoute: EraseAllLifecycleRouteV1
    ) async throws -> EraseAllOutcome {
#if DEBUG
        guard !originalEraseFrameActive, !postRetiredServiceAbandoned,
              originalColdExitAttempt == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        let completedAbortPoint = expectedCompletedAbortOperation === operation
            ? expectedCompletedAbortFault : nil
        expectedCompletedAbortFault = nil
        expectedCompletedAbortOperation = nil
        completedAbortFrame = nil
        originalEraseFrameActive = true
        originalFrameOperation = operation
        interruptedOriginalPreparationFault = nil
        originalFrameIntentStore = nil
        originalFrameExpectedIntent = nil
        originalFrameEmittedAbort = false
        defer { originalEraseFrameActive = false }
#endif
        try operation.requireLiveExecution(coordinator: coordinator)
        try generationFactory.requireEraseReaderInventory(operation.inventory)
        try operation.beginPreparationServiceFrame(coordinator: coordinator)
        defer { operation.endPreparationServiceFrame() }
        traceErasePhase("entry.integration-projections")
        try IntegrationProjectionEraseAllPolicyV1.validate()
        traceErasePhase("entry.scene-navigation")
        try C34SceneNavigationEraseAllBoundaryV1.validate()
        guard confirmation == Self.requiredConfirmation else {
            throw EraseAllServiceError.invalidConfirmation
        }
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
        traceErasePhase("entry.lifecycle-route")
        try lifecycleRoute.validate(
            generationRootURL: coordinator.generationRootURL,
            generationID: coordinator.generationID
        )
        traceErasePhase("entry.auxiliary")
        let auxiliary = try makeAuxiliaryAuthority()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()
        let applicationSupportIdentity = auxiliary.applicationSupportRootIdentity

        traceErasePhase("entry.generation-authority")
        let generationAuthority = try generationFactory
            .makeRestoreGenerationAuthority(
                expectedApplicationSupportIdentity: applicationSupportIdentity
            )
#if DEBUG
        if enableOriginalColdExitWitnessForTesting {
            originalColdExitAttempt = (
                operation, auxiliary, generationAuthority)
        }
        if let completedAbortPoint {
            completedAbortFrame = try CompletedAbortFrame(
                expectedFault: completedAbortPoint, operation: operation,
                auxiliary: auxiliary, generationAuthority: generationAuthority)
        }
#endif
        let oldGenerationID = coordinator.generationID
        let oldGenerationRootURL = coordinator.generationRootURL
        traceErasePhase("entry.retired-inventory")
        let priorRetired = try generationAuthority.retiredGenerationIDs()
        traceErasePhase("entry.current-authority")
        try validateCurrentAuthority(
            coordinator: coordinator,
            expectedID: oldGenerationID,
            expectedRootURL: oldGenerationRootURL,
            retiredIDs: priorRetired,
            authority: generationAuthority
        )
        traceErasePhase("entry.kernel-mappings")
        try validateKernelEraseMappings()
        traceErasePhase("entry.package-lifecycle")
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
        traceErasePhase("entry.auxiliary-reverify")
        try auxiliary.verifyTargets()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()

        traceErasePhase("entry.frozen-pointer")
        let oldPointer = try frozenCurrentPointer(
            expectedGenerationID: oldGenerationID,
            authority: generationAuthority
        )
#if DEBUG
        if enableOriginalColdExitWitnessForTesting {
            guard sceneNavigationStatePort == nil,
                  let discovery = privateSystemDiscoveryIndex
                    as? PrivateSystemDiscoveryIndexStoreV1,
                  discovery === PrivateSystemDiscoveryIndexRuntimeV1.shared else {
                throw EraseAllServiceError.invalidAuthority
            }
            let frame = try EraseOriginalColdExitFrameV1(
                operation: operation, authority: generationAuthority,
                auxiliary: auxiliary, oldGenerationID: oldGenerationID,
                userDefaults: userDefaults,
                defaultsDomainName: defaultsDomainName)
            originalColdExitFrame = frame
            guard let physicalOwner = discovery
                    .originalErasePhysicalOwnerForTesting else {
                throw EraseAllServiceError.invalidAuthority
            }
            let discoveryBeforeFirstAwait = try physicalOwner
                .originalErasePhysicalSnapshotForTesting()
            let discoveryAfterActorHop = try await discovery
                .originalErasePhysicalSnapshotForTesting()
            guard discoveryAfterActorHop == discoveryBeforeFirstAwait else {
                throw EraseAllServiceError.invalidAuthority
            }
            try frame.bindOriginalDiscoveryOwner(
                discovery, snapshot: discoveryBeforeFirstAwait)
        }
#endif
#if DEBUG
        let completedAbortBefore: EraseCompletedAbortSourceBytesV1?
        if completedAbortFrame != nil {
            completedAbortBefore = try? generationAuthority.snapshotCompletedAbortSource(
                id: oldGenerationID, oldPointer: oldPointer,
                priorRetired: priorRetired)
        } else { completedAbortBefore = nil }
#endif
        traceErasePhase("entry.source-ledger")
#if DEBUG
        let completedObservation = completedAbortFrame
        let originalColdObservation = originalColdExitFrame
        let sourceManifestObservation: ((StoreGenerationManifestV1) -> Void)?
        if completedObservation != nil || originalColdObservation != nil {
            sourceManifestObservation = { manifest in
                completedObservation?.observeSourceManifest(manifest)
                originalColdObservation?.observeSourceManifest(manifest)
            }
        } else {
            sourceManifestObservation = nil
        }
        // Compare every named read stage with the one immutable original
        // source-tree fact. A later observation is never a new baseline.
        let originalSourceTreeForStages = completedAbortBefore?.sourceTreeDigest
            ?? originalColdObservation?.sourceTreeDigestForDiagnostic()
        var reportedFirstSourceStage = false
        let sourceTreeStageObservation: (@MainActor (String) -> Void)?
        if completedObservation != nil || originalColdObservation != nil {
            sourceTreeStageObservation = { stage in
                guard !reportedFirstSourceStage else { return }
                guard let originalSourceTreeForStages else {
                    reportedFirstSourceStage = true
                    FileHandle.standardError.write(Data(
                        "ERASE_SOURCE_STAGE_V1 first=baseline-unavailable\n".utf8))
                    return
                }
                do {
                    let observed = try generationAuthority
                        .originalEraseSourceTreeForColdExitForTesting(
                            id: oldGenerationID)
                    guard observed == originalSourceTreeForStages else {
                        reportedFirstSourceStage = true
                        FileHandle.standardError.write(Data(
                            ("ERASE_SOURCE_STAGE_V1 first=" + stage + "\n").utf8))
                        return
                    }
                } catch {
                    reportedFirstSourceStage = true
                    FileHandle.standardError.write(Data(
                        ("ERASE_SOURCE_STAGE_V1 first=" + stage
                            + ".scan-unavailable\n").utf8))
                }
            }
        } else {
            sourceTreeStageObservation = nil
        }
#else
        let sourceManifestObservation: ((StoreGenerationManifestV1) -> Void)? = nil
        let sourceTreeStageObservation: (@MainActor (String) -> Void)? = nil
#endif
        // DEBUG traces the actual captured factory's read stages when a test
        // has requested Erase diagnostics. The value copy retains the same
        // registry provider and reader inventory; no authority is replaced.
#if DEBUG
        var sourceLedgerFactory = generationFactory
        sourceLedgerFactory.coldOpenDiagnosticForTesting = erasePhaseDiagnosticForTesting != nil
#else
        let sourceLedgerFactory = generationFactory
#endif
        let sourceLedger = try sourceLedgerFactory
            .currentGenerationDeletionLedgerProof(
                expectedPointer: oldPointer,
                authority: generationAuthority,
                observeManifest: sourceManifestObservation,
                observeSourceTreeStage: sourceTreeStageObservation
            )
#if DEBUG
        try originalColdExitFrame?.bindOriginalSourceSemantics(
            pointer: oldPointer, ledger: sourceLedger)
#endif
#if DEBUG
        if let completedAbortFrame {
            let after = try? generationAuthority.snapshotCompletedAbortSource(
                id: oldGenerationID, oldPointer: oldPointer,
                priorRetired: priorRetired)
            completedAbortFrame.bindSource(
                oldPointer: oldPointer, sourceLedger: sourceLedger,
                priorRetired: priorRetired,
                before: completedAbortBefore, after: after)
        }
#endif
        let newGenerationID = makeUUID()
#if DEBUG
        completedAbortFrame?.bindTarget(newGenerationID)
        try originalColdExitFrame?.bindTargetAbsence(newGenerationID)
#endif
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
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
        traceErasePhase("entry.fresh-identity")
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
        let subject = makeOperationSubject(
            eraseID: eraseID,
            newGenerationID: newGenerationID,
            auxiliary: auxiliary
        )
        let reservation: AppAccessGateV1.EraseAdoptionToken?
        do {
            traceErasePhase("entry.admit")
            reservation = try await admit(subject)
            traceErasePhase("entry.revalidate-admission")
            try revalidateAdmission(
                subject: subject,
                auxiliary: auxiliary,
                coordinator: coordinator,
                oldGenerationID: oldGenerationID,
                oldGenerationRootURL: oldGenerationRootURL,
                priorRetired: priorRetired,
                oldPointer: oldPointer,
                sourceLedger: sourceLedger,
                lifecycleRoute: lifecycleRoute,
                lifecycleCheckpoint: lifecycleCheckpoint
            )
        } catch {
            traceEraseOriginalFailure(error)
            let originalFailure = error
            let aborted = abortedAdmissionIfProven(
                subject: subject,
                reservation: admittedReservation,
                originalGenerationID: oldGenerationID,
                auxiliary: auxiliary,
                priorRetired: priorRetired,
                oldPointer: oldPointer,
                sourceLedger: sourceLedger,
                targetGenerationID: newGenerationID
            )
            operation.endPreparationServiceFrame()
            try operation.disposeFailedPreparationAllocations()
            try operation.requireFailedPreparationDisposed()
            if let aborted { deliverProvenAbortedAdmission(aborted) }
            throw originalFailure
        }

        var createdIntent = false
        var frozenIntent: EraseIntentV1?
        var frozenPreparation = initialPreparation
        var intentStore: EraseIntentStore?
        do {
            traceErasePhase("prepare.intent-store")
            let store = try EraseIntentStore(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager,
                expectedApplicationSupportIdentity: applicationSupportIdentity
            )
            guard try store.load() == nil,
                  try store.loadPreparation() == nil else {
                throw EraseAllServiceError.recoveryRequired
            }
            traceErasePhase("prepare.create")
            try store.createPreparation(initialPreparation)
            intentStore = store
#if DEBUG
            originalFrameIntentStore = store
#endif
            traceErasePhase("prepare.empty-generation")
            let created = try generationFactory.createEmptyEraseGeneration(
                id: newGenerationID,
                expectedOldPointer: oldPointer,
                identity: targetIdentity,
                authority: generationAuthority
            )
#if DEBUG
            traceErasePhase("prepare.empty-generation.factory-returned")
            try originalColdExitFrame?.bindCreatedTargetManifest(created.pointer)
            traceErasePhase("prepare.empty-generation.original-bind-returned")
#endif
            let boundPreparation = initialPreparation.binding(
                targetPointer: created.pointer
            )
            traceErasePhase("prepare.bind")
            try store.replacePreparation(
                expected: initialPreparation,
                with: boundPreparation
            )
            frozenPreparation = boundPreparation
            try inject(.afterEmptyGenerationDirectoryCreate)
            traceErasePhase("prepare.empty-ledger")
            let expectedEmptyLedger = try emptyLedgerProof()
            guard created.ledgerProof == expectedEmptyLedger,
                  created.pointer.workspaceID
                    == targetIdentity.workspaceID.rawValue,
                  created.pointer.replicaID
                    == targetIdentity.replicaID.rawValue,
                  created.pointer.knownReplicaIDs
                    == [targetIdentity.replicaID.rawValue] else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
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
#if DEBUG
            originalFrameExpectedIntent = intent
#endif
            guard EraseIntentCodecV1.valid(intent) else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
            // The factory clears journal state before sealing the target manifest.
            // Do not repeat that journal save after sealing. Release each
            // validation session before the physical-manifest verification.
            traceErasePhase("prepare.validate-empty")
            try autoreleasepool {
                _ = try validatedEmptySession(
                    id: newGenerationID,
                    identity: targetIdentity,
                    expectedEmptyLedger: expectedEmptyLedger,
                    authority: generationAuthority
                )
            }
            traceErasePhase("prepare.revalidate-empty")
            try autoreleasepool {
                _ = try validatedEmptySession(
                    id: newGenerationID,
                    identity: targetIdentity,
                    expectedEmptyLedger: expectedEmptyLedger,
                    authority: generationAuthority
                )
            }
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
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
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
            let activityContractProjections = ActivityContractDerivedProjectionBridgeV2(
                searchStore: coordinator.searchIndexStore,
                searchRebuildCoordinator: coordinator.searchServices.rebuildCoordinator
            )
            traceErasePhase("projection.local-purge.begin")
#if DEBUG
            if let originalColdExitFrame {
                let expected = try await coordinator.searchIndexStore
                    .purgeWorkspaceForOriginalEraseColdExitForTesting(
                        oldPointer.workspaceID,
                        validateOriginalPreimage: {
                            try originalColdExitFrame.beforeSearchReplacement()
                        },
                        validatePublishedEmpty: { expected in
                            try originalColdExitFrame.afterSearchReplacement(
                                expectedBytes: expected)
                        })
                guard expected != nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try originalColdExitFrame.requireSearchPublished()
            } else {
                try await activityContractProjections.purgeActivityContractProjections(.init(
                    workspaceID: WorkspaceID(rawValue: oldPointer.workspaceID),
                    activityID: nil,
                    axes: [.shared, .installation, .punch],
                    event: .erase
                ))
            }
#else
            try await activityContractProjections.purgeActivityContractProjections(.init(
                workspaceID: WorkspaceID(rawValue: oldPointer.workspaceID),
                activityID: nil,
                axes: [.shared, .installation, .punch],
                event: .erase
            ))
#endif
            traceErasePhase("projection.local-purge.end")
            if let privateSystemDiscoveryIndex {
                let operationID = try privateSystemDiscoveryOperationID(intent)
                traceErasePhase("projection.private-discovery.begin")
#if DEBUG
                if let originalColdExitFrame {
                    guard let originalDiscovery = privateSystemDiscoveryIndex
                            as? PrivateSystemDiscoveryIndexStoreV1,
                          originalDiscovery === PrivateSystemDiscoveryIndexRuntimeV1.shared
                    else { throw EraseAllServiceError.invalidAuthority }
                    try await originalDiscovery
                        .eraseAllForOriginalColdExitForTesting(
                            operationID: operationID,
                            now: Date(),
                            beforeEffect: { snapshot in
                                try originalColdExitFrame.beforeDiscoveryEffect(
                                    snapshot)
                            },
                            afterEffect: { snapshot in
                                try originalColdExitFrame.afterDiscoveryEffect(
                                    snapshot)
                            })
                } else {
                    try await privateSystemDiscoveryIndex.eraseAll(
                        operationID: operationID, now: Date())
                }
#else
                try await privateSystemDiscoveryIndex.eraseAll(
                    operationID: operationID,
                    now: Date()
                )
#endif
                traceErasePhase("projection.private-discovery.end")
            }
            let activated = intent.advancing(to: .sessionActivated)
            #if DEBUG
            traceErasePhase("retirement.binding.enter")
            #endif
            let binding = try operation.requirePreparing(coordinator: coordinator)
            #if DEBUG
            traceErasePhase("retirement.binding.complete")
            #endif
            #if DEBUG
            traceErasePhase("cleanup.prepare.enter")
            #endif
            let prepared = try await prepareCleanupForRetirement(activated, session: session,
                authority: generationAuthority, auxiliary: auxiliary, diagnosticsStore: diagnosticsStore,
                intentStore: intentStore, binding: binding, inventory: operation.inventory,
                reservation: reservation)
    #if DEBUG
        originalPreparedForPostRetired = prepared
#endif
        try operation.retainPrepared(prepared)
            #if DEBUG
            traceErasePhase("cleanup.prepare.complete")
            #endif
            #if DEBUG
            traceErasePhase("retirement.detach.enter")
            #endif
            try await operation.detach(coordinator: coordinator)
            #if DEBUG
            traceErasePhase("retirement.detach.complete")
            #endif
            return EraseAllOutcome(operation: operation)
        } catch {
            traceEraseOriginalFailure(error)
            if !createdIntent {
                let originalFailure = error
                try operation.requirePreparationRollback()
                var ownsUnjournaledGeneration = true
                var aborted: AbortedEraseAdmissionReceiptV1?
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
                        traceEraseOriginalFailure(error)
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
                        aborted = abortedAdmissionIfProven(
                            subject: subject,
                            reservation: reservation,
                            originalGenerationID: oldGenerationID,
                            auxiliary: auxiliary,
                            priorRetired: priorRetired,
                            oldPointer: oldPointer,
                            sourceLedger: sourceLedger,
                            targetGenerationID: newGenerationID
                        )
                    }
                } catch {
                    traceEraseOriginalFailure(error)
                    throw EraseAllServiceError.recoveryRequired
                }
                operation.endPreparationServiceFrame()
                try operation.disposeFailedPreparationAllocations()
                try operation.requireFailedPreparationDisposed()
                if let aborted { deliverProvenAbortedAdmission(aborted) }
                throw originalFailure
            }
            throw error
        }
    }

    /// Runs before Restore and ordinary pointer maintenance. A nonnil result
    /// is the one reopened empty generation that startup must activate.
    func reconcileForOriginalErase(diagnosticsStore: DiagnosticsStore,
        coordinator: StoreSessionCoordinator, operation: EraseRouterOperationV1,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void) async throws -> EraseAllOutcome? {
#if DEBUG
        guard !originalEraseFrameActive, !postRetiredServiceAbandoned,
              originalColdExitAttempt == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        expectedCompletedAbortFault = nil
        expectedCompletedAbortOperation = nil
        completedAbortFrame = nil
        originalEraseFrameActive = true
        originalFrameOperation = operation
        interruptedOriginalPreparationFault = nil
        originalFrameIntentStore = nil
        originalFrameExpectedIntent = nil
        originalFrameEmittedAbort = false
        defer { originalEraseFrameActive = false }
#endif
        try operation.requireRecoveryExecution(coordinator: coordinator)
        try generationFactory.requireEraseReaderInventory(operation.inventory)
        try operation.beginPreparationServiceFrame(coordinator: coordinator)
        defer { operation.endPreparationServiceFrame() }
        traceErasePhase("recovery.support")
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
        traceErasePhase("recovery.auxiliary")
        let auxiliary = try makeAuxiliaryAuthority()
        let intentStore = try EraseIntentStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        traceErasePhase("recovery.intent")
        let intent = try intentStore.load()
        let preparation = try intentStore.loadPreparation()
#if DEBUG
        originalFrameIntentStore = intentStore
        originalFrameExpectedIntent = intent
#endif
        guard let intent else {
            try operation.requirePreparationRollback()
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
        traceErasePhase("recovery.intent-contract")
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
        traceErasePhase("recovery.authority")
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        traceErasePhase("recovery.targets")
        try auxiliary.verifyTargets()
        try requireRecoveryPresence(intent, authority: authority)
        let subject = makeOperationSubject(
            eraseID: intent.eraseID,
            newGenerationID: intent.newGenerationID,
            auxiliary: auxiliary
        )
        traceErasePhase("recovery.admission")
        let reservation = try await admit(subject)
        traceErasePhase("recovery.admission-revalidation")
        try revalidateRecoveryAdmission(
            subject: subject,
            intent: intent,
            preparation: preparation,
            auxiliary: auxiliary,
            intentStore: intentStore
        )

        let session: StoreGenerationSession
        switch intent.phase {
        case .emptyGenerationPrepared:
            session = try await advanceToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                activate: activate
            )
        case .pointerSwitched:
            session = try await advancePointerPhaseToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                activate: activate
            )
        case .sessionActivated:
            traceErasePhase("recovery.activated-current")
            try requireActivatedCurrent(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        case .cleanupComplete:
            traceErasePhase("recovery.cleanup-presence")
            try requireCleanupPresence(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        }

        if intent.phase == .sessionActivated || intent.phase == .cleanupComplete {
            await activate(session)
        }
        guard coordinator.generationID == session.generationID,
              coordinator.modelContext === session.modelContext,
              coordinator.generationRootURL.standardizedFileURL == session.generationRootURL.standardizedFileURL else {
            throw EraseAllServiceError.recoveryRequired
        }
        let activated = intent.phase == .cleanupComplete
            ? intent
            : intent.advancing(to: .sessionActivated)
        if let privateSystemDiscoveryIndex {
            try await privateSystemDiscoveryIndex.eraseAll(
                operationID: try privateSystemDiscoveryOperationID(intent),
                now: Date()
            )
        }
        let binding = try operation.requirePreparing(coordinator: coordinator)
        let prepared = try await prepareCleanupForRetirement(activated, session: session,
            authority: authority, auxiliary: auxiliary, diagnosticsStore: diagnosticsStore,
            intentStore: intentStore, binding: binding, inventory: operation.inventory,
            reservation: reservation)
#if DEBUG
        originalPreparedForPostRetired = prepared
#endif
        try operation.retainPrepared(prepared)
        try await operation.detach(coordinator: coordinator)
        return EraseAllOutcome(operation: operation)
    }

    func reconcileAtStartup(
        diagnosticsStore: DiagnosticsStore
    ) async throws -> StoreGenerationSession? {
#if DEBUG
        guard !postRetiredServiceAbandoned,
              originalColdExitAttempt == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
#endif
        traceErasePhase("recovery.support")
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
        traceErasePhase("recovery.auxiliary")
        let auxiliary = try makeAuxiliaryAuthority()
        let intentStore = try EraseIntentStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        traceErasePhase("recovery.intent")
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
        traceErasePhase("recovery.intent-contract")
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
        traceErasePhase("recovery.authority")
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        traceErasePhase("recovery.targets")
        try auxiliary.verifyTargets()
        try requireRecoveryPresence(intent, authority: authority)
        let subject = makeOperationSubject(
            eraseID: intent.eraseID,
            newGenerationID: intent.newGenerationID,
            auxiliary: auxiliary
        )
        traceErasePhase("recovery.admission")
        let reservation = try await admit(subject)
        traceErasePhase("recovery.admission-revalidation")
        try revalidateRecoveryAdmission(
            subject: subject,
            intent: intent,
            preparation: preparation,
            auxiliary: auxiliary,
            intentStore: intentStore
        )

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
            traceErasePhase("recovery.activated-current")
            try requireActivatedCurrent(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        case .cleanupComplete:
            traceErasePhase("recovery.cleanup-presence")
            try requireCleanupPresence(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        }

        let activated = intent.phase == .cleanupComplete
            ? intent
            : intent.advancing(to: .sessionActivated)
        if let privateSystemDiscoveryIndex {
            try await privateSystemDiscoveryIndex.eraseAll(
                operationID: try privateSystemDiscoveryOperationID(intent),
                now: Date()
            )
        }
        return try await completeCleanup(
            activated,
            session: session,
            authority: authority,
            auxiliary: auxiliary,
            diagnosticsStore: diagnosticsStore,
            intentStore: intentStore,
            subject: subject,
            reservation: reservation
        )
    }

    // Genuine startup operation only. It retains all readers for retirement
    // and routes preparation rollback through its own drain witnesses.
    func prepareColdRetirement(
        diagnosticsStore: DiagnosticsStore, operation: EraseColdPreparationOperationV1
    ) async throws -> Bool {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        traceErasePhase("recovery.support")
        var supportStatus = stat()
        let supportResult = applicationSupportURL.path.withCString {
            lstat($0, &supportStatus)
        }
        if supportResult != 0 {
            guard errno == ENOENT else {
                throw EraseAllServiceError.invalidAuthority
            }
            return false
        }
        guard (supportStatus.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        traceErasePhase("recovery.auxiliary")
        let auxiliary = try makeAuxiliaryAuthority()
        let intentStore = try EraseIntentStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        traceErasePhase("recovery.intent")
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
                let identity = try WorkspaceReplicaIdentityV1(
                    workspaceID: WorkspaceID(rawValue: preparation.targetWorkspaceID),
                    replicaID: ReplicaID(rawValue: preparation.targetReplicaID))
                let rollback = EraseColdPreparationRollbackV1(preparation: preparation,
                    targetIdentity: identity, emptyLedger: try emptyLedgerProof(),
                    authority: authority, auxiliary: auxiliary, intentStore: intentStore)
                try operation.retainRollback(rollback)
                return false
            }
            try auxiliary.removeEraseRootIfEmpty()
            return false
        }
        traceErasePhase("recovery.intent-contract")
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
        traceErasePhase("recovery.authority")
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        traceErasePhase("recovery.targets")
        try auxiliary.verifyTargets()
        try requireRecoveryPresence(intent, authority: authority)
        let subject = makeOperationSubject(
            eraseID: intent.eraseID,
            newGenerationID: intent.newGenerationID,
            auxiliary: auxiliary
        )
        // Genuine cold startup owns access; no old original-operation
        // reservation or receipt is minted for an on-disk intent.
        try revalidateRecoveryAdmission(subject: subject, intent: intent,
            preparation: preparation, auxiliary: auxiliary, intentStore: intentStore)

        let session: StoreGenerationSession
        switch intent.phase {
        case .emptyGenerationPrepared:
            session = try await advanceColdToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                operation: operation
            )
        case .pointerSwitched:
            session = try await advanceColdPointerPhaseToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                operation: operation
            )
        case .sessionActivated:
            traceErasePhase("recovery.activated-current")
            try requireActivatedCurrent(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        case .cleanupComplete:
            traceErasePhase("recovery.cleanup-presence")
            try requireCleanupPresence(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        }

        let activated = intent.phase == .cleanupComplete
            ? intent
            : intent.advancing(to: .sessionActivated)
        try operation.requireServiceAccess()
        if let privateSystemDiscoveryIndex {
            try await privateSystemDiscoveryIndex.eraseAll(
                operationID: try privateSystemDiscoveryOperationID(intent),
                now: Date()
            )
        }
        try operation.requireServiceAccess()
        let binding = try operation.bindValidatedTarget(subject: subject, session: session)
        let prepared = try await prepareColdCleanupForRetirement(activated, session: session,
            authority: authority, auxiliary: auxiliary, diagnosticsStore: diagnosticsStore,
            intentStore: intentStore, binding: binding, inventory: operation.inventory,
            reservation: nil, operation: operation)
        try operation.requireServiceAccess()
        try operation.retainPrepared(prepared, intentStore: intentStore, intent: activated)
        return true
    }

    /// Called only by the factory's fixed, leased, synchronous retired read.
    /// The opaque capability rejects any other context or an expired scope.
    func validatePreexistingRetiredGeneration(
        session: StoreGenerationSession,
        validation: ErasePreexistingRetiredSourceValidationV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try validation.revalidate(modelContext: session.modelContext)
        try validateFrozenGeneration(id: session.generationID,
            modelContext: session.modelContext, generationRootURL: session.generationRootURL,
            workspaceIdentity: validation.workspaceIdentity, authority: authority,
            preexistingRetiredValidation: validation)
    }

    func validateRecoveryRetiredGeneration(
        session: StoreGenerationSession,
        validation: EraseRecoveryRetiredSourceValidationV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try validation.revalidate(modelContext: session.modelContext)
        try validateFrozenGeneration(id: session.generationID,
            modelContext: session.modelContext, generationRootURL: session.generationRootURL,
            workspaceIdentity: validation.workspaceIdentity, authority: authority,
            recoveryRetiredValidation: validation)
    }

    func validateMaintenanceEntry(_ session: StoreGenerationSession) throws {
        // Fails closed: an uninstallable writer (e.g. corrupt receipt history)
        // makes Erase ineligible instead of trapping on every maintenance launch.
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
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
    func makeOperationSubject(
        eraseID: UUID,
        newGenerationID: UUID,
        auxiliary: EraseAuxiliaryAuthority
    ) -> EraseAllOperationSubjectV1 {
        let identity = auxiliary.applicationSupportRootIdentity
        return EraseAllOperationSubjectV1(
            eraseID: eraseID,
            newGenerationID: newGenerationID,
            applicationSupportURL: applicationSupportURL,
            applicationSupportDevice: Int64(identity.device),
            applicationSupportInode: UInt64(identity.inode)
        )
    }

    func admit(
        _ subject: EraseAllOperationSubjectV1
    ) async throws -> AppAccessGateV1.EraseAdoptionToken? {
        guard admittedSubject == nil, admittedReservation == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        let reservation = try await admitErase?(subject)
        admittedSubject = subject
        admittedReservation = reservation
        return reservation
    }

    func completedReceipt(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken?,
        eraseID: UUID,
        newGenerationID: UUID
    ) -> CompletedEraseReceiptV1? {
        guard didCompleteErase != nil else { return nil }
        guard admittedSubject == subject,
              admittedReservation == reservation,
              admittedReservation?.subject == subject || reservation == nil,
              subject.eraseID == eraseID,
              subject.newGenerationID == newGenerationID else {
            return nil
        }
        return CompletedEraseReceiptV1(
            subject: subject,
            reservation: reservation
        )
    }

    func abortedAdmissionIfProven(
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken?,
        originalGenerationID: UUID,
        auxiliary: EraseAuxiliaryAuthority,
        priorRetired: [UUID],
        oldPointer: RestorePointerIdentityV1,
        sourceLedger: DeletionLedgerProofV2,
        targetGenerationID: UUID
    ) -> AbortedEraseAdmissionReceiptV1? {
        guard let reservation,
              didAbortEraseAdmission != nil,
              admittedSubject == subject,
              admittedReservation == reservation,
              reservation.subject == subject else { return nil }
        do {
            guard makeOperationSubject(
                eraseID: subject.eraseID,
                newGenerationID: subject.newGenerationID,
                auxiliary: auxiliary
            ) == subject else { return nil }
            // Absence under the retained support descriptor proves that no
            // intent or preparation leaf remains, without recreating the
            // namespace after checked rollback removed it.
            try auxiliary.requireEraseRootAbsentForAbortedAdmission()
            try auxiliary.verifyTargets()
            try auxiliary.requireNoEraseIntent()
            try auxiliary.requireNoRestoreIntent()
            let authority = try generationFactory.makeRestoreGenerationAuthority(
                expectedApplicationSupportIdentity: auxiliary.applicationSupportRootIdentity
            )
            guard try frozenCurrentPointer(
                expectedGenerationID: originalGenerationID,
                authority: authority
            ) == oldPointer,
            try generationFactory.currentGenerationDeletionLedgerProof(
                expectedPointer: oldPointer,
                authority: authority
            ) == sourceLedger,
            try authority.retiredGenerationIDs() == priorRetired,
            !(try authority.installedGenerationNames()).contains(
                Self.canonical(targetGenerationID)
            ) else { return nil }
            try auxiliary.requireEraseRootAbsentForAbortedAdmission()
            return AbortedEraseAdmissionReceiptV1(
                subject: subject,
                reservation: reservation,
                originalGenerationID: originalGenerationID
            )
        } catch {
            return nil
        }
    }

    private func deliverProvenAbortedAdmission(_ receipt: AbortedEraseAdmissionReceiptV1) {
#if DEBUG
        originalFrameEmittedAbort = true
        completedAbortFrame?.recordAbort(receipt)
#endif
        didAbortEraseAdmission?(receipt)
    }

    func revalidateAdmission(
        subject: EraseAllOperationSubjectV1,
        auxiliary: EraseAuxiliaryAuthority,
        coordinator: StoreSessionCoordinator,
        oldGenerationID: UUID,
        oldGenerationRootURL: URL,
        priorRetired: [UUID],
        oldPointer: RestorePointerIdentityV1,
        sourceLedger: DeletionLedgerProofV2,
        lifecycleRoute: EraseAllLifecycleRouteV1,
        lifecycleCheckpoint: EraseAllLifecycleCheckpointV1
    ) throws {
        guard makeOperationSubject(
            eraseID: subject.eraseID,
            newGenerationID: subject.newGenerationID,
            auxiliary: auxiliary
        ) == subject else {
            throw EraseAllServiceError.invalidAuthority
        }
        try auxiliary.verifyTargets()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity: auxiliary.applicationSupportRootIdentity
        )
        try validateCurrentAuthority(
            coordinator: coordinator,
            expectedID: oldGenerationID,
            expectedRootURL: oldGenerationRootURL,
            retiredIDs: priorRetired,
            authority: authority
        )
        guard try frozenCurrentPointer(
            expectedGenerationID: oldGenerationID,
            authority: authority
        ) == oldPointer,
        try generationFactory.currentGenerationDeletionLedgerProof(
            expectedPointer: oldPointer,
            authority: authority
        ) == sourceLedger else {
            throw EraseAllServiceError.invalidAuthority
        }
        try lifecycleRoute.validate(
            generationRootURL: coordinator.generationRootURL,
            generationID: coordinator.generationID
        )
        switch (lifecycleRoute, lifecycleCheckpoint) {
        case let (.live(dependencies), .live(expectedRevision)):
            guard try validatePackageLifecycleScope(
                dependencies: dependencies,
                coordinator: coordinator
            ) == expectedRevision else {
                throw EraseAllServiceError.invalidAuthority
            }
        case (.expiringCompatibility, .compatibility):
            break
        default:
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func revalidateRecoveryAdmission(
        subject: EraseAllOperationSubjectV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2?,
        auxiliary: EraseAuxiliaryAuthority,
        intentStore: EraseIntentStore
    ) throws {
        guard makeOperationSubject(
            eraseID: intent.eraseID,
            newGenerationID: intent.newGenerationID,
            auxiliary: auxiliary
        ) == subject,
        try intentStore.load() == intent,
        try intentStore.loadPreparation() == preparation else {
            throw EraseAllServiceError.invalidAuthority
        }
        if intent.schemaVersion == 2 {
            guard preparation?.matches(intent) == true || intent.phase == .cleanupComplete,
                  preparation != nil || intent.phase == .cleanupComplete else {
                throw EraseAllServiceError.invalidAuthority
            }
        } else if preparation != nil {
            throw EraseAllServiceError.invalidAuthority
        }
        try auxiliary.verifyTargets()
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity: auxiliary.applicationSupportRootIdentity
        )
        try requireRecoveryPresence(intent, authority: authority)
    }

    func validateKernelEraseMappings() throws {
        do {
            try KernelDeletionEraseRegistryV4.validate()
        } catch {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    struct PrivateSystemDiscoveryEraseBindingV1: Codable {
        let schemaVersion: Int
        let operation: String
        let eraseID: UUID
        let workspaceID: WorkspaceID
        let oldGenerationID: UUID
        let newGenerationID: UUID
    }

    func privateSystemDiscoveryOperationID(
        _ intent: EraseIntentV1
    ) throws -> PrivateSystemDiscoveryOperationIDV1 {
        guard let oldPointer = intent.oldPointer else {
            throw EraseAllServiceError.invalidAuthority
        }
        let workspaceID = WorkspaceID(rawValue: oldPointer.workspaceID)
        let inputSHA256 = CompatibilityCanonicalV1.sha256(
            try CompatibilityCanonicalV1.encode(PrivateSystemDiscoveryEraseBindingV1(
                schemaVersion: 1,
                operation: "GLOBAL_ERASE_DERIVED_INDEX_DROP_V1",
                eraseID: intent.eraseID,
                workspaceID: workspaceID,
                oldGenerationID: intent.oldGenerationID,
                newGenerationID: intent.newGenerationID
            ))
        )
        return try PrivateSystemDiscoveryOperationIDV1(
            rawValue: intent.eraseID,
            operation: .removal,
            workspaceID: workspaceID,
            inputSHA256: inputSHA256
        )
    }

    func validatePackageLifecycleScope(
        dependencies: WorkspacePackageLifecycleDependenciesV1,
        coordinator: StoreSessionCoordinator
    ) throws -> WorkspaceRevisionV1 {
        traceErasePhase("lifecycle.dependencies")
        guard dependencies.workspaceID == coordinator.workspaceID,
              dependencies.generationID == coordinator.generationID,
              dependencies.generationRootURL.standardizedFileURL
                == coordinator.generationRootURL.standardizedFileURL else {
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
        do {
            traceErasePhase("lifecycle.request")
            let request = try WorkspacePackageLifecycleQueryRequestV1(
                workspaceID: dependencies.workspaceID,
                generationID: dependencies.generationID,
                operation: .erase,
                identities: []
            )
            traceErasePhase("lifecycle.query")
            let result = try dependencies.queryClient.query(request)
            traceErasePhase("lifecycle.current-revision")
            let current = try dependencies.queryClient.currentRevision()
            traceErasePhase("lifecycle.result")
            guard result.workspaceID == dependencies.workspaceID,
                  result.generationID == dependencies.generationID,
                  result.operation == .erase,
                  result.existingIdentities.isEmpty,
                  result.packageBindings.isEmpty,
                  result.revision == current,
                  current.workspaceID == coordinator.workspaceID,
                  current.generationID == coordinator.generationID else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
            return current
        } catch let error as EraseAllServiceError {
            traceEraseOriginalFailure(error)
            throw error
        } catch {
            traceEraseOriginalFailure(error)
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
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
        traceErasePhase("current.installed-inventory")
        let installed = try authority.installedGenerationNames()
        let expectedNames = Set((retiredIDs + [expectedID]).map(Self.canonical))
        traceErasePhase("current.pointer-and-roots")
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
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
        traceErasePhase("current.frozen-generation")
        try validateFrozenGeneration(
            id: expectedID,
            modelContext: coordinator.modelContext,
            generationRootURL: expectedRootURL,
            workspaceIdentity: coordinator.workspaceIdentity,
            authority: authority
        )
        traceErasePhase("current.retired-generations")
        for id in retiredIDs {
            try generationFactory.validatePreexistingRetiredGenerationForErase(
                id: id, expectedCurrentID: expectedID, expectedRetiredIDs: retiredIDs,
                authority: authority, service: self)
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
        traceErasePhase("recovery.presence.inventory")
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
        traceErasePhase("recovery.presence.current")
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
                traceErasePhase("recovery.presence.published-empty")
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
            if intent.schemaVersion == 2, id != intent.oldGenerationID {
                traceErasePhase("recovery.presence.preexisting-retired")
                try generationFactory.validateRecoveryRetiredGenerationForErase(
                    id: id, intent: intent, authority: authority, service: self)
                continue
            }
            if intent.schemaVersion == 2,
               id == intent.oldGenerationID,
               currentID == intent.newGenerationID {
                traceErasePhase("recovery.presence.retained-source")
                traceErasePhase("recovery.retained.acquire.enter")
                let validation = try EraseRetainedSourceValidationV1.acquire(
                    intent: intent, generationFactory: generationFactory,
                    authority: authority
                )
                traceErasePhase("recovery.retained.acquire.complete")
                traceErasePhase("recovery.retained.open.enter")
                let session = try generationFactory.openInstalledGeneration(
                    id: id, identity: validation.workspaceIdentity, authority: authority
                )
                traceErasePhase("recovery.retained.open.complete")
                #if DEBUG
                traceErasePhase("recovery.retained.readback.enter")
                let v949Before = try v949RetainedSourceReadbackForTesting.map {
                    _ in try V949ColdSourceReadbackV1.capture(
                        session.modelContext)
                }
                traceErasePhase("recovery.retained.readback.complete")
                #endif
                traceErasePhase("recovery.retained.validate.enter")
                do {
                    try validateFrozenGeneration(
                        id: id, modelContext: session.modelContext,
                        generationRootURL: session.generationRootURL,
                        workspaceIdentity: session.workspaceIdentity,
                        authority: authority, retainedEraseValidation: validation
                    )
                } catch {
                    #if DEBUG
                    if let v949Before,
                       let callback = v949RetainedSourceReadbackForTesting {
                        let after = try V949ColdSourceReadbackV1.capture(
                            session.modelContext)
                        callback(v949Before, after)
                    }
                    #endif
                    throw error
                }
                traceErasePhase("recovery.retained.validate.complete")
                continue
            }
            let session = try generationFactory.openInstalledGeneration(
                id: id,
                authority: authority
            )
            try validateFrozenGeneration(
                id: id,
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                workspaceIdentity: session.workspaceIdentity,
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

    func advanceColdToActivatedSession(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        operation: EraseColdPreparationOperationV1
    ) async throws -> StoreGenerationSession {
        try operation.requireServiceAccess()
        try inject(.beforePointerSwitch)
        try normalizePointerAndRetired(intent, authority: authority)
        try inject(.afterPointerSwitch)

        let switched = intent.advancing(to: .pointerSwitched)
        try inject(.beforePointerPhaseWrite)
        if intent.phase == .emptyGenerationPrepared {
            try intentStore.replace(expected: intent, with: switched)
        }
        try inject(.afterPointerPhaseWrite)
        return try await advanceColdPointerPhaseToActivatedSession(
            switched,
            authority: authority,
            intentStore: intentStore,
            operation: operation
        )
    }

    func advanceColdPointerPhaseToActivatedSession(
        _ switched: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        operation: EraseColdPreparationOperationV1
    ) async throws -> StoreGenerationSession {
        try operation.requireServiceAccess()
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
        await Task.yield()
        try operation.requireServiceAccess()
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
#if DEBUG
        try originalColdExitFrame?.beforePointerPublication(intent)
#endif
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
#if DEBUG
        try originalColdExitFrame?.afterPointerPublication(intent)
#endif
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

    /// The incumbent complete empty-graph and schema2 ledger predicates,
    /// shared by preparation and the fixed private post-drain validator. This
    /// does not create a lease, writer, session or authority from a context.
    static func requireEmptyEraseContent(context: ModelContext,
        generationID: UUID, activated: EraseIntentV1) throws {
        guard activated.phase == .sessionActivated,
              generationID == activated.newGenerationID,
              BackupRestoreService.isEmptyCurrent(context) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if activated.schemaVersion == 2 {
            let ledger = try DeletionLedgerStore(context: context).snapshot()
            guard ledger.entries.isEmpty else { throw EraseAllServiceError.invalidAuthority }
            let proof = try DeletionLedgerProofV2(entryCount: ledger.entries.count,
                canonicalSHA256: SHA256.hash(data: try ledger.canonicalData())
                    .map { String(format: "%02x", $0) }.joined())
            guard activated.targetEmptyProof == EraseEmptyGenerationProofV2(
                contentRecordCount: 0, deletionLedgerEntryCount: 0) else {
                throw EraseAllServiceError.invalidAuthority
            }
            let empty = DeletionLedgerV2.empty
            let expected = try DeletionLedgerProofV2(entryCount: empty.entries.count,
                canonicalSHA256: SHA256.hash(data: try empty.canonicalData())
                    .map { String(format: "%02x", $0) }.joined())
            guard proof == expected else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    /// The post-drain private-copy route cannot repair or mutate rows. Repeat
    /// every incumbent published-empty policy plus its zero mutation history.
    internal static func requireEmptyErasePublishedGraph(context: ModelContext,
        generationID: UUID, identity: WorkspaceReplicaIdentityV1,
        activated: EraseIntentV1) throws {
        try requireEmptyEraseContent(context: context, generationID: generationID, activated: activated)
        try EvidenceAssuranceEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try InspectionReviewEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try WorkPacketEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try FieldDraftEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try PackageEvolutionEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try ClientCapabilityEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try PrivacyTransformEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try MeasurementIntegrityEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try FieldReferenceEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try AccessibleDocumentEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try SurveyDefinitionEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try SurveySessionEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try AssetLocatorEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try ScheduleEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try C57MyDayEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try EvidenceMetadataEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try C04ShopReportProfileEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try C05RoundSessionEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try EvidenceQualityEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try FastSurveyInboxEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try ReinspectionExceptionEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try EntityIdentityResolutionEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try PracticeWorkspaceProvenanceEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try LightingDayInventoryEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try LightingNightWorkflowEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try ServiceRequestEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try AssetServiceReliabilityEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try PlanEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        try PlacementPoseEraseAllPolicyV1.validatePublishedEmptyGeneration(context)
        guard try context.fetchCount(FetchDescriptor<ActivitySessionEnvelopeRow>()) == 0,
              try context.fetchCount(FetchDescriptor<ActivityStateTransitionRow>()) == 0,
              try context.fetchCount(FetchDescriptor<InstallationTaskResultRow>()) == 0,
              try context.fetchCount(FetchDescriptor<InstallationAsBuiltSnapshotRow>()) == 0,
              try context.fetchCount(FetchDescriptor<PunchReviewBasisSnapshotRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try C47ActivityContractKernelDeletionEnrollmentV2.validate()
        guard try context.fetchCount(FetchDescriptor<ImportMappingProfileRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<BulkSessionRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<BulkCommitReceiptRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try C08ImportBulkKernelDeletionEraseEnrollmentV1.validate()
        let history = try MutationJournalStoreV1(modelContext: context,
            identity: identity, generationID: generationID, allowStateBootstrap: false).exportSnapshot()
        guard history.workspaceRevision == 0, history.lastLocalSequence == 0,
              history.receipts.isEmpty, history.quarantines.isEmpty,
              history.entityRevisions.isEmpty, !context.hasChanges else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func completeCleanup(
        _ value: EraseIntentV1,
        session: StoreGenerationSession,
        authority: StoreRestoreGenerationAuthority,
        auxiliary: EraseAuxiliaryAuthority,
        diagnosticsStore: DiagnosticsStore,
        intentStore: EraseIntentStore,
        subject: EraseAllOperationSubjectV1,
        reservation: AppAccessGateV1.EraseAdoptionToken?
    ) async throws -> StoreGenerationSession {
        traceErasePhase("cleanup.session-and-content")
        let activated: EraseIntentV1
        if value.phase == .cleanupComplete {
            activated = value.advancing(to: .sessionActivated)
        } else {
            activated = value
        }
        if activated.schemaVersion == 2 { traceErasePhase("cleanup.empty-ledger") }
        try Self.requireEmptyEraseContent(context: session.modelContext,
            generationID: session.generationID, activated: activated)

        if value.phase != .cleanupComplete {
            try inject(.beforeCleanup)
        }
        // This source-free path uses the same physical owner as scheduling.
        // Revocation is persisted before the first suspension in erase(), and
        // no generation, mapping, or preference cleanup can pass its drain.
        traceErasePhase("cleanup.notification-control")
        let notificationPreferences = PreferencesAdapterV1(defaults: userDefaults)
        let notificationControl = try AppLockNotificationControlStoreV1(
            applicationSupportURL: applicationSupportURL, preferences: notificationPreferences)
        traceErasePhase("cleanup.notification-drain")
        try await DeviceLocalNotificationOwnerV1.erase(control: notificationControl,
            system: notificationSystem, operationID: activated.eraseID)
        traceErasePhase("cleanup.generations")
        try cleanupGenerations(activated, authority: authority)
        traceErasePhase("cleanup.presence")
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
        try sceneNavigationStatePort?.eraseSceneNavigationData()
        try PortableExchangeProtectedFilePolicyV2.validate()
        let portableExchangeStore = try PortableExchangeSessionStoreV2(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let portableExchangeReceipt = try await portableExchangeStore.erase(
            operationID: activated.eraseID
        )
        try portableExchangeReceipt.validate()
        guard try await portableExchangeStore.sessions(in: nil).isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        // C45 render attempts live under each generation's jobs directory.
        // `cleanupGenerations` above removes that complete generation-owned
        // scratch namespace; there is no application-support-level C45 root.
        let ratingStore = PreferencesAdapterV1(defaults: userDefaults)
        try AppLockNotificationTransactionFenceV1.perform {
            try notificationControl.verifyNotificationStorage()
            guard try notificationControl.loadControl() == nil,
                  try notificationControl.loadPrivateNotificationMapping() == nil else {
                throw EraseAllServiceError.recoveryRequired
            }
            // Keep the sole current manifest outside Operations while Erase
            // requires that entire auxiliary root to remain absent at return.
            try StoreMigrationJournalStoreV1(applicationSupportURL: applicationSupportURL)
                .preserveCurrentManifestForErase(expectedGenerationID: activated.newGenerationID)
            try auxiliary.removeFrozenTargets()
            try ratingStore.preparePreferencesForCompletedErase(
                operationID: activated.eraseID,
                persistentDomainName: defaultsDomainName
            )
        }
        // The one post-wipe Defaults value is an installation-only cooldown,
        // written through the sole preferences owner. Its CAS receipt and
        // read-back are required before Erase may publish cleanupComplete.
        // Recovery retains only an exact same-erase sole-domain ledger, so an
        // interruption here cannot restart or shorten the cooldown; every
        // other domain shape is wiped before this replacement is written.
        let ratingCoordinator = try RatingEligibilityCoordinatorV1(
            store: ratingStore,
            nativeRequest: AppStoreRatingRequestAdapterV1(),
            clock: SystemApplicationClock()
        )
        let ratingErase = try await ratingCoordinator.applyCompletedErase(
            eraseOperationID: activated.eraseID,
            erasedAt: Date()
        )
        guard case .current(let ratingLedger) = try await ratingStore.load(),
              ratingLedger.attempts.isEmpty,
              case .erasedCooldown(_, let suppressUntil) = ratingLedger.origin,
              suppressUntil == ratingErase.suppressUntil,
              ratingErase.receipt.operationID == activated.eraseID,
              ratingErase.receipt.resultingRevision == ratingLedger.revision,
              ratingErase.receipt.stateSHA256 == ratingLedger.stateSHA256 else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Recreate through a fresh adapter after removing the old anchored
        // directory. This publishes the canonical current operational
        // envelope; writing DiagnosticsV1.zero directly would leave legacy
        // bytes and would not prove the Erase result at this edge.
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
        let feedbackZeroSnapshot = try await replacementDiagnosticsStore
            .supportFeedbackDraftSnapshot()
        guard feedbackZeroSnapshot.state == .empty,
              feedbackZeroSnapshot.draft == nil,
              !feedbackZeroSnapshot.safeCopyAvailable else {
            throw EraseAllServiceError.invalidAuthority
        }
        let diagnosticsZero = try await replacementDiagnosticsStore
            .canonicalOperationalSupportEnvelopeDataV3()
        await diagnosticsStore.acceptDescriptorErasedZero()
        guard await diagnosticsStore.isExactlyZero(),
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
        // The journal replacement retains its migration-reservation guard,
        // which opens a fresh Operations registry. Remove that control state
        // while the durable Erase intent still excludes ordinary activity.
        // A cleanupComplete recovery repeats this boundary before publishing.
        traceErasePhase("cleanup.final-control-removal")
        try auxiliary.removeCompletionControlRoot()
        try auxiliary.verifyTargetsRemovedExceptDiagnostics()
        try auxiliary.verifyDiagnostics(expectedData: diagnosticsZero)
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
        traceErasePhase("cleanup.final-roots-verified")
        try auxiliary.verifyTargetsRemovedExceptDiagnostics()
        if let receipt = completedReceipt(
            subject: subject,
            reservation: reservation,
            eraseID: completed.eraseID,
            newGenerationID: completed.newGenerationID
        ) {
            didCompleteErase?(receipt)
        }
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
        traceErasePhase("empty.open")
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
        traceErasePhase("empty.tree")
        let tree = try authority.installedTree(id: id)
        let allowedFiles: Set<String> = [
            "model.sqlite",
            "model.sqlite-shm",
            "model.sqlite-wal",
        ]
        traceErasePhase("empty.rows-and-tree")
        guard BackupRestoreService.isEmptyCurrent(session.modelContext),
              tree.directories.isEmpty,
              tree.files.contains("model.sqlite"),
              tree.files.isSubset(of: allowedFiles) else {
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
        traceErasePhase("empty.identity-policy")
        if let identity {
            // The reset path is whole-workspace only. This public adapter owns
            // the C16 row and is idempotent when the fresh generation is REAL.
            try WorkspaceExperienceLifecycleAdapterV1(
                modelContext: session.modelContext,
                workspaceID: identity.workspaceID
            ).eraseWorkspaceRows()
        }
        traceErasePhase("empty.policy.EvidenceAssuranceEraseAllPolicyV1")
        try EvidenceAssuranceEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.InspectionReviewEraseAllPolicyV1")
        try InspectionReviewEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.WorkPacketEraseAllPolicyV1")
        try WorkPacketEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.FieldDraftEraseAllPolicyV1")
        try FieldDraftEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.PackageEvolutionEraseAllPolicyV1")
        try PackageEvolutionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.ClientCapabilityEraseAllPolicyV1")
        try ClientCapabilityEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.PrivacyTransformEraseAllPolicyV1")
        try PrivacyTransformEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.MeasurementIntegrityEraseAllPolicyV1")
        try MeasurementIntegrityEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.FieldReferenceEraseAllPolicyV1")
        try FieldReferenceEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.AccessibleDocumentEraseAllPolicyV1")
        try AccessibleDocumentEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.SurveyDefinitionEraseAllPolicyV1")
        try SurveyDefinitionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.SurveySessionEraseAllPolicyV1")
        try SurveySessionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.AssetLocatorEraseAllPolicyV1")
        try AssetLocatorEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.ScheduleEraseAllPolicyV1")
        try ScheduleEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.C57MyDayEraseAllPolicyV1")
        try C57MyDayEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.EvidenceMetadataEraseAllPolicyV1")
        try EvidenceMetadataEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.C04ShopReportProfileEraseAllPolicyV1")
        try C04ShopReportProfileEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.C05RoundSessionEraseAllPolicyV1")
        try C05RoundSessionEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.EvidenceQualityEraseAllPolicyV1")
        try EvidenceQualityEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.FastSurveyInboxEraseAllPolicyV1")
        try FastSurveyInboxEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.ReinspectionExceptionEraseAllPolicyV1")
        try ReinspectionExceptionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.EntityIdentityResolutionEraseAllPolicyV1")
        try EntityIdentityResolutionEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.PracticeWorkspaceProvenanceEraseAllPolicyV1")
        try PracticeWorkspaceProvenanceEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.LightingDayInventoryEraseAllPolicyV1")
        try LightingDayInventoryEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.LightingNightWorkflowEraseAllPolicyV1")
        try LightingNightWorkflowEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.ServiceRequestEraseAllPolicyV1")
        try ServiceRequestEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.AssetServiceReliabilityEraseAllPolicyV1")
        try AssetServiceReliabilityEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        traceErasePhase("empty.policy.PlanEraseAllPolicyV1")
        try PlanEraseAllPolicyV1.validatePublishedEmptyGeneration(session.modelContext)
        traceErasePhase("empty.policy.PlacementPoseEraseAllPolicyV1")
        try PlacementPoseEraseAllPolicyV1.validatePublishedEmptyGeneration(
            session.modelContext
        )
        try validateActivityContractEraseClosure(session: session)
        try validateImportBulkEraseClosure(session: session)
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
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
        }
        traceErasePhase("empty.ledger")
        if let expectedEmptyLedger {
            let ledger = try DeletionLedgerStore(
                context: session.modelContext
            ).snapshot()
            guard ledger.entries.isEmpty,
                  try ledgerProof(ledger) == expectedEmptyLedger else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
        }
        return session
    }

    func validateFrozenGeneration(
        id: UUID,
        modelContext: ModelContext,
        generationRootURL: URL,
        workspaceIdentity: WorkspaceReplicaIdentityV1,
        authority: StoreRestoreGenerationAuthority,
        retainedEraseValidation: EraseRetainedSourceValidationV1? = nil,
        preexistingRetiredValidation: ErasePreexistingRetiredSourceValidationV1? = nil,
        recoveryRetiredValidation: EraseRecoveryRetiredSourceValidationV1? = nil
    ) throws {
        traceErasePhase("frozen.context-and-root")
        guard !modelContext.hasChanges,
              generationRootURL.standardizedFileURL
                == generationFactory.installedGenerationURL(id: id) else {
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
        let contentRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
        traceErasePhase("frozen.summary")
        if let validation = recoveryRetiredValidation {
            guard retainedEraseValidation == nil, preexistingRetiredValidation == nil,
                  generationRootURL.standardizedFileURL == validation.generationRootURL,
                  workspaceIdentity == validation.workspaceIdentity else {
                throw EraseAllServiceError.invalidAuthority
            }
            try validation.revalidate(modelContext: modelContext)
        }
        if let validation = preexistingRetiredValidation {
            guard retainedEraseValidation == nil,
                  generationRootURL.standardizedFileURL == validation.generationRootURL,
                  workspaceIdentity == validation.workspaceIdentity else {
                throw EraseAllServiceError.invalidAuthority
            }
            try validation.revalidate(modelContext: modelContext)
        }
        if let validation = retainedEraseValidation {
            guard generationRootURL.standardizedFileURL == validation.generationRootURL,
                  workspaceIdentity == validation.workspaceIdentity else {
                throw EraseAllServiceError.invalidAuthority
            }
            try validation.revalidate(modelContext: modelContext)
        }
        // The generic empty predicate does not enumerate temporal rows. Even
        // an otherwise-empty store must authenticate their complete receipt and
        // byte closure before any original path can enter the inventory.
        let temporalClips = try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>())
            .map { try $0.value() }
        var temporalDerivatives: [TemporalEvidenceDerivativeV1] = []
        var authenticatedHistory: MutationHistorySnapshotV1?
        var authenticatedJournal: MutationJournalStoreV1?
        if recoveryRetiredValidation != nil || preexistingRetiredValidation != nil || !temporalClips.isEmpty || !BackupRestoreService.isEmptyCurrent(modelContext) {
            do {
                if let validation = recoveryRetiredValidation {
                    _ = try BackupRestoreService.recoveryRetiredEraseSummary(
                        modelContext: modelContext, validation: validation)
                } else if let validation = preexistingRetiredValidation {
                    _ = try BackupRestoreService.preexistingRetiredEraseSummary(
                        modelContext: modelContext, validation: validation)
                } else if let validation = retainedEraseValidation {
                    _ = try BackupRestoreService.retainedEraseSummary(
                        modelContext: modelContext, validation: validation
                    )
                } else {
                    _ = try BackupRestoreService.currentSummary(
                        modelContext: modelContext,
                        generationRootURL: generationRootURL
                    )
                }
                // The session/retained authority supplies identity; the state row
                // must agree, and cannot authorize its own namespace. No writer,
                // bootstrap or current-only factory is opened for a retired source.
                let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                guard states.count == 1, let state = states.first,
                      state.generationID == id,
                      state.workspaceID == workspaceIdentity.workspaceID.rawValue,
                      state.activeReplicaID == workspaceIdentity.replicaID.rawValue else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let journal = try MutationJournalStoreV1(modelContext: modelContext,
                    identity: workspaceIdentity, generationID: id, allowStateBootstrap: false)
                let history = try journal.exportSnapshot()
                temporalDerivatives = try TemporalEvidenceWholeGenerationEraseV1.registeredDerivatives(
                    history: history, workspaceID: workspaceIdentity.workspaceID)
                authenticatedJournal = journal
                authenticatedHistory = history
            } catch {
                traceErasePhase("frozen.summary.failure." + String(reflecting: type(of: error)))
                throw error
            }
        }
        traceErasePhase("frozen.model-fetches")
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let acceptedLabelSnapshots = try modelContext.fetch(
            FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()
        ).map { try $0.value() }
        var expectedDirectories = Set<String>()
        var expectedFiles: Set<String> = ["model.sqlite"]
        // The complete current/retained summary above authenticates these rows,
        // their receipt closure and anchored original bytes. Enroll only those
        // exact required members; clip derivative IDs grant no file authority.
        for clip in temporalClips {
            let path = try TemporalEvidenceBackupMemberV1.original(for: clip)
            let workspace = clip.workspaceID.rawValue.uuidString.lowercased()
            expectedDirectories.formUnion([
                "content", "content/\(workspace)",
                "content/\(workspace)/\(clip.original.contentID)",
            ])
            expectedFiles.insert(path)
        }
        // Finalization startup owns this empty root before any Report exists.
        // Its descendants still require the exact report-backed file inventory.
        var optionalDirectories: Set<String> = ["snapshots"]
        var optionalFiles = Set<String>()
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
        for snapshot in acceptedLabelSnapshots
            where snapshot.disposition == .activeSourceWorkspace {
            let binding = snapshot.outputReceipt.publicationBinding
            try binding.validate(manifest: snapshot.manifest)
            let workspace = snapshot.workspaceID.rawValue.uuidString.lowercased()
            guard binding.workspaceID == snapshot.workspaceID else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
            optionalDirectories.insert("content")
            optionalDirectories.insert("content/\(workspace)")
            optionalDirectories.insert("content/\(workspace)/.asset-label-publications")
            optionalDirectories.insert(
                "content/\(workspace)/.asset-label-publications/\(binding.jobID.rawValue.uuidString.lowercased())"
            )
            optionalFiles.insert(
                "content/\(workspace)/.asset-label-publications/\(binding.jobID.rawValue.uuidString.lowercased())/publication.json"
            )
            for artifact in binding.publishedArtifacts {
                let directory = "content/\(workspace)/\(artifact.reference.contentID)"
                optionalDirectories.insert(directory)
                optionalFiles.insert("\(directory)/original.bin")
            }
        }
        let allowedStagingDirectories: Set<String> = [
            ".staging",
            ".staging/evidence",
            ".staging/pdfs",
            ".staging/snapshots",
        ]
        optionalFiles.formUnion([
            "model.sqlite-shm",
            "model.sqlite-wal",
        ])
        traceErasePhase("frozen.installed-tree")
        let tree = try authority.installedTree(id: id)
        traceErasePhase("frozen.label-inventory")
        let contentStore = EvidenceBundleStore(
            generationRootURL: generationRootURL,
            fileManager: fileManager,
            expectedGenerationRootIdentity: contentRootIdentity
        )
        var presentDerivatives: [ContentReferenceV1] = []
        var ownedContent: [String: ContentReferenceV1] = [:]
        for clip in temporalClips {
            // Preserve incumbent original-sharing validation in the exporter;
            // this map only prevents derivative/original role aliasing.
            ownedContent[clip.original.contentID] = clip.original
        }
        for derivative in temporalDerivatives {
            try derivative.locator.validate(against: derivative.content)
            if let prior = ownedContent[derivative.content.contentID], prior != derivative.content {
                throw EraseAllServiceError.invalidAuthority
            }
            ownedContent[derivative.content.contentID] = derivative.content
            let workspace = derivative.content.workspaceID
            let directory = "content/\(workspace)/\(derivative.content.contentID)"
            let path = "\(directory)/original.bin"
            // Exact incumbent orphan cleanup removes the object directory but
            // leaves these two parents. It does not leave an empty object.
            optionalDirectories.formUnion(["content", "content/\(workspace)"])
            if tree.files.contains(path) {
                guard try contentStore.resolveContentReference(derivative.content) == derivative.content else {
                    throw EraseAllServiceError.invalidAuthority
                }
                expectedDirectories.formUnion(["content", "content/\(workspace)", directory])
                expectedFiles.insert(path)
                presentDerivatives.append(derivative.content)
            } else if tree.directories.contains(directory) {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        for snapshot in acceptedLabelSnapshots
            where snapshot.disposition == .activeSourceWorkspace {
            let binding = snapshot.outputReceipt.publicationBinding
            let workspace = snapshot.workspaceID.rawValue.uuidString.lowercased()
            var ownedDirectories: Set<String> = [
                "content/\(workspace)/.asset-label-publications/\(binding.jobID.rawValue.uuidString.lowercased())",
            ]
            var ownedFiles: Set<String> = [
                "content/\(workspace)/.asset-label-publications/\(binding.jobID.rawValue.uuidString.lowercased())/publication.json",
            ]
            for artifact in binding.publishedArtifacts {
                let directory = "content/\(workspace)/\(artifact.reference.contentID)"
                ownedDirectories.insert(directory)
                ownedFiles.insert("\(directory)/original.bin")
            }
            let isPresent = !ownedDirectories.isDisjoint(with: tree.directories)
                || !ownedFiles.isDisjoint(with: tree.files)
            guard !isPresent
                    || (ownedDirectories.isSubset(of: tree.directories)
                        && ownedFiles.isSubset(of: tree.files)) else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
            if isPresent {
                guard let readback = try contentStore.readAssetLabelArtifacts(
                    jobID: binding.jobID
                ),
                      readback.plan == snapshot.plan,
                      readback.projection.manifest == snapshot.manifest,
                      readback.publishedArtifacts == binding.publishedArtifacts else {
                    traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        traceErasePhase("frozen.inventory-predicate")
        guard expectedDirectories.isSubset(of: tree.directories),
              tree.directories.isSubset(
                of: expectedDirectories.union(allowedStagingDirectories)
                    .union(optionalDirectories)
              ),
              expectedFiles.isSubset(of: tree.files),
              tree.files.isSubset(of: expectedFiles.union(optionalFiles)),
              !modelContext.hasChanges else {
#if DEBUG
            if erasePhaseDiagnosticForTesting != nil {
                // Observe only the failed boundary's retained values. No paths,
                // payloads, model refetches or filesystem reads are emitted.
                let contextClean: Bool = !modelContext.hasChanges
                let allowedDirectories: Set<String> = expectedDirectories
                    .union(allowedStagingDirectories).union(optionalDirectories)
                let allowedFiles: Set<String> = expectedFiles.union(optionalFiles)
                let missingDirectories: Set<String> = expectedDirectories.subtracting(tree.directories)
                let unexpectedDirectories: Set<String> = tree.directories.subtracting(allowedDirectories)
                let missingFiles: Set<String> = expectedFiles.subtracting(tree.files)
                let unexpectedFiles: Set<String> = tree.files.subtracting(allowedFiles)
                traceErasePhase("frozen.failure.expectedDirectoriesPresent=\(missingDirectories.isEmpty)")
                traceErasePhase("frozen.failure.directoriesAllowed=\(unexpectedDirectories.isEmpty)")
                traceErasePhase("frozen.failure.expectedFilesPresent=\(missingFiles.isEmpty)")
                traceErasePhase("frozen.failure.filesAllowed=\(unexpectedFiles.isEmpty)")
                traceErasePhase("frozen.failure.contextClean=\(contextClean)")
                traceErasePhase("frozen.failure.missingDirectories=\(missingDirectories.count).unexpectedDirectories=\(unexpectedDirectories.count).missingFiles=\(missingFiles.count).unexpectedFiles=\(unexpectedFiles.count)")
                let modelFilePresent: Bool = tree.files.contains("model.sqlite")
                let activeLabels: Int = acceptedLabelSnapshots.filter { $0.disposition == .activeSourceWorkspace }.count
                traceErasePhase("frozen.failure.modelFilePresent=\(modelFilePresent).evidenceRows=\(evidence.count).reportRows=\(reports.count).activeLabels=\(activeLabels)")
                let families: [String] = ["evidence", "snapshots", "pdfs", "content", ".staging", ".staging/evidence", ".staging/snapshots", ".staging/pdfs", ".staging/evidence-derivatives"]
                for family in families {
                    let directories: Int = unexpectedDirectories.filter { $0 == family || $0.hasPrefix(family + "/") }.count
                    let files: Int = unexpectedFiles.filter { $0 == family || $0.hasPrefix(family + "/") }.count
                    let rootPresent: Bool = unexpectedDirectories.contains(family)
                    traceErasePhase("frozen.failure.family=\(family).directories=\(directories).files=\(files).rootPresent=\(rootPresent)")
                }
            }
#endif
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
        // Reprove the observed inventory and authenticated history after all
        // readback/diagnostic boundaries, before any generation disposal.
        for content in presentDerivatives {
            guard try contentStore.resolveContentReference(content) == content else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL) == contentRootIdentity,
              try authority.installedTree(id: id) == tree,
              !modelContext.hasChanges else { throw EraseAllServiceError.invalidAuthority }
        if let journal = authenticatedJournal, let history = authenticatedHistory {
            guard try journal.exportSnapshot() == history else { throw EraseAllServiceError.invalidAuthority }
        }
        if let validation = recoveryRetiredValidation {
            try validation.revalidate(modelContext: modelContext)
        }
        if let validation = preexistingRetiredValidation {
            try validation.revalidate(modelContext: modelContext)
        }
        if let validation = retainedEraseValidation {
            try validation.revalidate(modelContext: modelContext)
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
            authority: authority,
            diagnosticPhase: eraseFactoryPhaseDiagnostic
        )
    }

    func inject(_ point: EraseAllFailurePoint) throws {
        if failureInjection?.consume(point) == true {
#if DEBUG
            switch point {
            case .afterEmptyGenerationDirectoryCreate, .beforePreparedWrite,
                 .afterPreparedWrite, .beforePointerSwitch, .afterPointerSwitch,
                 .beforePointerPhaseWrite, .afterPointerPhaseWrite,
                 .beforeSessionActivation, .afterSessionActivation,
                 .beforeSessionPhaseWrite, .afterSessionPhaseWrite, .beforeCleanup:
                interruptedOriginalPreparationFault = point
            default: break
            }
#endif
            throw EraseAllServiceError.injectedFailure
        }
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

#if DEBUG
private struct ErasePostRetiredAuxiliarySnapshotV1: Equatable {
    let supportNames: [String]
    let roots: [String: String]
    let operationsBeforeRelease: String?
}

private struct EraseOriginalSearchPhysicalStateV1: Equatable {
    let rootDevice: dev_t?
    let rootInode: ino_t?
    let projectionBytes: Data?
    let projectionIdentity: String?
}

private struct EraseOriginalScratchPhysicalStateV1: Equatable {
    let operationsDevice: dev_t
    let operationsInode: ino_t
    let scratchDevice: dev_t?
    let scratchInode: ino_t?
}

private struct EraseOriginalExchangePhysicalStateV1: Equatable {
    let rootDevice: dev_t?
    let rootInode: ino_t?
    let envelopeBytes: Data?
    let names: [String]
}

/// Read-only DEBUG facts used to classify a failed full-tree equality check.
/// Names and digests stay in memory; diagnostics print fixed categories only.
private struct EraseSchemaMigrationDiagnosticFactV1: Equatable {
    let kind: String
    let identity: String
    let modeAndLinks: String
    let size: String
    let modified: String
    let changed: String
    let contentDigest: String
}

private struct EraseSchemaMigrationDiagnosticSnapshotV1 {
    let rootIdentity: String
    let rootMode: String
    let rootLinks: UInt64
    let entries: [String: EraseSchemaMigrationDiagnosticFactV1]

    func firstDifference(from other: Self) -> String {
        if rootIdentity != other.rootIdentity { return "root-identity" }
        if rootMode != other.rootMode { return "root-mode" }
        if rootLinks != other.rootLinks { return "root-links" }
        guard Set(entries.keys) == Set(other.entries.keys) else {
            return "entry-membership"
        }
        for name in entries.keys.sorted() {
            guard let before = entries[name], let after = other.entries[name] else {
                return "entry-membership"
            }
            if before.kind != after.kind { return "entry-kind" }
            if before.identity != after.identity { return "entry-identity" }
            if before.modeAndLinks != after.modeAndLinks { return "entry-mode-links" }
            if before.size != after.size { return "entry-size" }
            if before.modified != after.modified { return "entry-mtime" }
            if before.changed != after.changed { return "entry-ctime" }
            if before.contentDigest != after.contentDigest { return "entry-content" }
        }
        return "no-shallow-difference"
    }
}

#if DEBUG
/// Immutable facts read from the genuine original Erase frame before the
/// checked owner transfer. No caller can recreate these from later disk bytes.
struct V949OriginalEraseSourceBindingV1 {
    let oldGenerationID: UUID
    let newGenerationID: UUID
    let eraseID: UUID
    let sourceTreeDigest: String
    let sourcePointer: RestorePointerIdentityV1
    let publishedControls: EraseOriginalColdExitControlsV1
    let sourceManifestSHA256: String
    let targetManifestSHA256: String
}

/// Raw value observations used only by the V9_49 hostile cold-refusal tests.
/// These preserve the original clip, receipt, and kernel assertions without
/// letting test code retain a fresh cold ModelContext or reader wrapper.
struct V949ColdSourceReadbackV1: Equatable {
    let rawClipRows: [[String]]
    let clipCanonicalBytes: [Data]
    let receiptByIdentity: [[Data]]
    let receiptBySequence: [[Data]]
    let kernel: [[[String]]]

    @MainActor
    static func capture(_ context: ModelContext) throws
        -> V949ColdSourceReadbackV1 {
        guard !context.hasChanges else {
            throw EraseAllServiceError.invalidAuthority
        }
        let clipRows = try context.fetch(
            FetchDescriptor<TemporalEvidenceClipRow>())
        guard Set(clipRows.map(\.clipID)).count == clipRows.count else {
            throw EraseAllServiceError.invalidAuthority
        }
        let clipsByIdentity = clipRows.sorted {
            $0.clipID.uuidString < $1.clipID.uuidString
        }
        let receiptRows = try context.fetch(
            FetchDescriptor<MutationReceiptRow>())
        let states = try context.fetch(
            FetchDescriptor<WorkspaceMutationStateRow>())
        let revisions = try context.fetch(
            FetchDescriptor<EntityMutationRevisionRow>())
        let quarantines = try context.fetch(
            FetchDescriptor<MutationQuarantineRow>())
        func receiptBytes(_ row: MutationReceiptRow) -> [Data] {
            [row.envelopeData, row.receiptData,
             row.reversalBasisData ?? Data(),
             row.semanticReversalData ?? Data()]
        }
        return V949ColdSourceReadbackV1(
            rawClipRows: clipsByIdentity.map {
                [$0.clipID.uuidString, $0.workspaceID.uuidString,
                 $0.sessionID.uuidString, String($0.revision),
                 $0.mutationID.uuidString, $0.originalContentID,
                 $0.originalSHA256, $0.clipSHA256,
                 $0.canonicalData.base64EncodedString()]
            },
            clipCanonicalBytes: clipRows.map(\.canonicalData)
                .sorted { $0.lexicographicallyPrecedes($1) },
            receiptByIdentity: receiptRows.sorted {
                $0.receiptIdentity < $1.receiptIdentity
            }.map(receiptBytes),
            receiptBySequence: receiptRows.sorted {
                $0.localSequence < $1.localSequence
            }.map(receiptBytes),
            kernel: [
                states.sorted {
                    $0.workspaceID.uuidString < $1.workspaceID.uuidString
                }.map {
                    [$0.workspaceID.uuidString, $0.generationID.uuidString,
                     $0.activeReplicaID.uuidString,
                     String($0.workspaceRevision),
                     String($0.lastLocalSequence),
                     $0.mutableSemanticSHA256 ?? "nil"]
                },
                revisions.sorted {
                    $0.stableIdentity < $1.stableIdentity
                }.map {
                    [$0.stableIdentity, $0.kind,
                     $0.entityID.uuidString, String($0.revision),
                     $0.externalProjectionSHA256 ?? "nil"]
                },
                quarantines.sorted {
                    $0.workspaceMutationKey < $1.workspaceMutationKey
                }.map {
                    [$0.workspaceID.uuidString, $0.mutationID.uuidString,
                     $0.workspaceMutationKey, $0.identityDomain,
                     $0.acceptedIdentitySHA256,
                     $0.conflictingIdentitySHA256,
                     String($0.detectedAt.timeIntervalSinceReferenceDate.bitPattern)]
                },
            ])
    }
}
#endif

/// DEBUG-only source-bound observation for the two S6 checked cold exits.
/// The callback is invoked by the original Search actor immediately before
/// its real replacement. This owner remains retained through an uncertain
/// handoff; its first source digest is never updated by a later read.
private final class EraseOriginalColdExitFrameV1: @unchecked Sendable {
    enum Stage: Equatable {
        case sourceBound, searchPublished, notificationRefused,
             scratchConstructed, scratchErased, exchangePublished,
             uncertain
    }
    private let operation: EraseRouterOperationV1
    private let authority: StoreRestoreGenerationAuthority
    private let auxiliary: EraseAuxiliaryAuthority
    private let oldGenerationID: UUID
    private let sourceTree: String
    private let sourceTreeNodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]
    private var preCloseSQLiteImage: CompletedAbortSQLitePhysicalImageV1?
    private var validatedPostCloseSourceTree: String?
    private var preReaderOpenSQLiteImage: CompletedAbortSQLitePhysicalImageV1?
    private var preReaderOpenSourceNodes:
        [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]?
    private var validatedPostReaderOpenSourceTree: String?
    private let controlsOrigin: EraseOriginalColdExitControlsV1
    private var controlsPublished: EraseOriginalColdExitControlsV1?
    private let userDefaults: UserDefaults
    private let defaultsDomainName: String
    private let defaultsOrigin: NSDictionary?
    private var oldPointer: RestorePointerIdentityV1?
    private var sourceLedger: DeletionLedgerProofV2?
    private var sourceManifest: StoreGenerationManifestV1?
    private var manifestObservationCount = 0
    private var targetGenerationID: UUID?
    private let schemaMigrationOrigin: String
    private let schemaMigrationSourceRootLinks: UInt64
    private let schemaMigrationDiagnosticOrigin: EraseSchemaMigrationDiagnosticSnapshotV1?
    private var targetManifestPointer: RestorePointerIdentityV1?
    private var targetManifestIdentity: String?
    private let auxiliaryOrigin: ErasePostRetiredAuxiliarySnapshotV1
    private let searchOrigin: EraseOriginalSearchPhysicalStateV1
    private let scratchOrigin: EraseOriginalScratchPhysicalStateV1
    private let notificationOrigin:
        EraseOriginalNotificationPhysicalSnapshotV1
    private let exchangeOrigin: EraseOriginalExchangePhysicalStateV1
    private let unrelatedOperationsDigest: String
    private let lock = NSRecursiveLock()
    private var stage: Stage = .sourceBound
    private var searchExpectedBytes: Data?
    private var constructedScratch: EraseOriginalScratchPhysicalStateV1?
    private var scratchOwner: ScratchDataLeaseStoreV1?
    private var notificationControl: AppLockNotificationControlStoreV1?
    private var notificationBeforeEffect:
        EraseOriginalNotificationPhysicalSnapshotV1?
    private var notificationAfterRevocation:
        EraseOriginalNotificationPhysicalSnapshotV1?
    private var notificationAfterSuccess:
        EraseOriginalNotificationPhysicalSnapshotV1?
    private var notificationRefusal: (
        revocation: NotificationEraseRevocationV1,
        owned: Set<String>, observedOwned: Set<String>)?
    private var exchangeLayout: EraseOriginalExchangePhysicalStateV1?
    private var exchangeExpectedBytes: Data?
    private var exchangeOwner: PortableExchangeSessionStoreV2?
    private var discoveryOwner: PrivateSystemDiscoveryIndexStoreV1?
    private var discoveryOrigin: PrivateSystemDiscoveryFileStateStoreV1
        .OriginalErasePhysicalSnapshot?
    private var discoveryAfter: PrivateSystemDiscoveryFileStateStoreV1
        .OriginalErasePhysicalSnapshot?
    private var sourceReadObservation:
        EraseOriginalColdExitContextObservationV1?

    func sourceTreeDigestForDiagnostic() -> String {
        sourceTree
    }

    func capturePostHandoffHostileSource(
        operation expected: EraseRouterOperationV1,
        intent: EraseIntentV1
    ) throws -> V949OriginalEraseSourceBindingV1 {
        try lock.withLock {
            // This witness is captured at the actual afterPointerSwitch cut.
            // Search, notification, scratch and Exchange effects have not run;
            // the later .exchangePublished cleanup predicate is deliberately
            // separate and remains strict for a prepared retirement.
            try requireEarlyPointerPublishedTransition(intent)
            guard operation === expected,
                  intent.oldGenerationID == oldGenerationID,
                  intent.newGenerationID == targetGenerationID,
                  let publishedControls = controlsPublished,
                  let sourceManifest,
                  let oldPointer,
                  let targetManifestPointer,
                  sourceManifest.generationID == oldGenerationID else {
                throw EraseAllServiceError.invalidAuthority
            }
            return V949OriginalEraseSourceBindingV1(
                oldGenerationID: oldGenerationID,
                newGenerationID: intent.newGenerationID,
                eraseID: intent.eraseID,
                sourceTreeDigest: sourceTree,
                sourcePointer: oldPointer,
                publishedControls: publishedControls,
                sourceManifestSHA256: try sourceManifest.canonicalSHA256(),
                targetManifestSHA256:
                    targetManifestPointer.generationManifestSHA256)
        }
    }

    private func requireEarlyPointerPublishedTransition(
        _ intent: EraseIntentV1
    ) throws {
        guard stage == .sourceBound,
              validatedPostCloseSourceTree == nil,
              intent.phase == .emptyGenerationPrepared,
              intent.oldGenerationID == oldGenerationID,
              intent.oldPointer == oldPointer,
              intent.sourceLedger == sourceLedger,
              intent.newGenerationID == targetGenerationID,
              intent.targetPointer == targetManifestPointer,
              targetManifestIdentity != nil,
              controlsPublished != nil,
              searchExpectedBytes == nil,
              discoveryAfter == nil,
              notificationAfterSuccess == nil,
              scratchOwner == nil,
              exchangeOwner == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireSourceUnchanged()
        try requireUnrelatedOperationsUnchanged()
        try requireDefaultsUnchanged()
        try requirePublishedControlsUnchanged()
        try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
            auxiliaryOrigin, allowing: [])
        guard try auxiliary.originalEraseSearchStateForTesting() == searchOrigin,
              try auxiliary.originalEraseEmptyScratchStateForTesting() == scratchOrigin,
              try auxiliary.originalEraseNotificationStateForTesting() == notificationOrigin,
              try auxiliary.originalEraseExchangeStateForTesting() == exchangeOrigin else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireV949OriginalSourceUnchanged(
        _ binding: V949OriginalEraseSourceBindingV1,
        operation expected: EraseRouterOperationV1
    ) throws {
        try lock.withLock {
            guard stage == .sourceBound,
                  operation === expected,
                  binding.oldGenerationID == oldGenerationID,
                  binding.newGenerationID == targetGenerationID,
                  binding.sourcePointer == oldPointer,
                  binding.sourceTreeDigest == sourceTree,
                  controlsPublished == binding.publishedControls,
                  try sourceManifest?.canonicalSHA256()
                    == binding.sourceManifestSHA256,
                  targetManifestPointer?.generationManifestSHA256
                    == binding.targetManifestSHA256 else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
        }
    }

    func requireV949ControlsUnchanged(
        _ binding: V949OriginalEraseSourceBindingV1,
        operation expected: EraseRouterOperationV1
    ) throws {
        try lock.withLock {
            guard stage == .sourceBound,
                  operation === expected,
                  binding.oldGenerationID == oldGenerationID,
                  binding.newGenerationID == targetGenerationID,
                  binding.sourcePointer == oldPointer,
                  controlsPublished == binding.publishedControls,
                  try sourceManifest?.canonicalSHA256()
                    == binding.sourceManifestSHA256,
                  targetManifestPointer?.generationManifestSHA256
                    == binding.targetManifestSHA256 else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requirePublishedControlsUnchanged()
        }
    }

    init(operation: EraseRouterOperationV1,
         authority: StoreRestoreGenerationAuthority,
         auxiliary: EraseAuxiliaryAuthority,
         oldGenerationID: UUID,
         userDefaults: UserDefaults,
         defaultsDomainName: String) throws {
        self.operation = operation
        self.authority = authority
        self.auxiliary = auxiliary
        self.oldGenerationID = oldGenerationID
        self.userDefaults = userDefaults
        self.defaultsDomainName = defaultsDomainName
        defaultsOrigin = try Self.snapshotDefaults(
            userDefaults, domain: defaultsDomainName)
        controlsOrigin = try authority
            .originalEraseControlsForColdExitForTesting()
        let sourceObservation = try authority
            .originalEraseSourceTreeObservationForColdExitForTesting(
                id: oldGenerationID)
        sourceTree = sourceObservation.digest
        sourceTreeNodes = sourceObservation.nodes
        auxiliaryOrigin = try auxiliary.postRetiredSnapshot()
        searchOrigin = try auxiliary.originalEraseSearchStateForTesting()
        scratchOrigin = try auxiliary.originalEraseEmptyScratchStateForTesting()
        notificationOrigin = try auxiliary
            .originalEraseNotificationStateForTesting()
        exchangeOrigin = try auxiliary.originalEraseExchangeStateForTesting()
        unrelatedOperationsDigest = try auxiliary
            .originalEraseUnrelatedOperationsDigestForTesting()
        let schemaMigrationSource = try auxiliary
            .originalEraseSchemaMigrationSourceSnapshotForTesting()
        schemaMigrationOrigin = schemaMigrationSource.digest
        schemaMigrationSourceRootLinks = schemaMigrationSource.rootLinks
        schemaMigrationDiagnosticOrigin = try? auxiliary
            .originalEraseSchemaMigrationDiagnosticSnapshotForTesting()
        try requireSourceUnchanged()
        try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
            auxiliaryOrigin, allowing: [])
        guard try auxiliary.originalEraseSearchStateForTesting() == searchOrigin else {
            throw EraseAllServiceError.invalidAuthority
        }
        guard try auxiliary.originalEraseNotificationStateForTesting()
                == notificationOrigin else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireDefaultsUnchanged()
    }

    private static func snapshotDefaults(
        _ defaults: UserDefaults, domain: String
    ) throws -> NSDictionary? {
        guard let value = defaults.persistentDomain(forName: domain) else {
            return nil
        }
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: value, format: .binary, options: 0)
        guard let copy = try PropertyListSerialization.propertyList(
            from: bytes, options: [], format: nil) as? NSDictionary else {
            throw EraseAllServiceError.invalidAuthority
        }
        return copy
    }

    func requireDefaultsUnchanged() throws {
        let after = try Self.snapshotDefaults(
            userDefaults, domain: defaultsDomainName)
        guard (defaultsOrigin == nil && after == nil)
                || (defaultsOrigin?.isEqual(after) == true) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    /// The source root is already bound by the original Erase frame. The
    /// only tolerated physical delta is an authenticated SQLite close: same
    /// named inodes and non-SQLite tree, with the full committed page image
    /// and surviving WAL prefix checked by the shared physical validator.
    private func requireOwnedSQLiteNodeTransition(
        from baseline: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode],
        to observed: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode],
        allowingSHMModificationTime: Bool
    ) throws {
        var old = [String: EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]()
        var new = [String: EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]()
        for node in baseline {
            guard old.updateValue(node, forKey: node.path) == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        for node in observed {
            guard new.updateValue(node, forKey: node.path) == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard Set(old.keys) == Set(new.keys) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for (path, before) in old {
            guard let after = new[path] else {
                throw EraseAllServiceError.invalidAuthority
            }
            let a = before.fact, b = after.fact
            guard a.st_dev == b.st_dev, a.st_ino == b.st_ino,
                  a.st_mode == b.st_mode, a.st_nlink == b.st_nlink else {
                throw EraseAllServiceError.invalidAuthority
            }
            switch path {
            case "model.sqlite", "model.sqlite-wal":
                // Page and WAL content/length changes are verified below by
                // the preclose image, not accepted from this fresh scan.
                break
            case "model.sqlite-shm":
                // SQLite may rewrite its shared index. Reader open may also
                // change its mtime; neither grants a new durable page image.
                guard a.st_size == b.st_size,
                      (allowingSHMModificationTime ||
                       (a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
                        a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec)) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            default:
                guard a.st_size == b.st_size,
                      a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec,
                      a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec,
                      a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec,
                      a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec,
                      before.sha256 == after.sha256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
    }

    func beginOwnedSourceCloseTransition(
        binding: V949OriginalEraseSourceBindingV1,
        operation expected: EraseRouterOperationV1,
        intent: EraseIntentV1
    ) throws {
        try lock.withLock {
            guard operation === expected, preCloseSQLiteImage == nil,
                  validatedPostCloseSourceTree == nil,
                  binding.sourceTreeDigest == sourceTree,
                  binding.eraseID == intent.eraseID else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireEarlyPointerPublishedTransition(intent)
            let before = try authority
                .originalEraseSQLitePhysicalImageForColdExitForTesting(
                    id: oldGenerationID)
            guard before.tree == sourceTree else {
                throw EraseAllServiceError.invalidAuthority
            }
            preCloseSQLiteImage = before.image
        }
    }

    func completeOwnedSourceCloseTransition(
        binding: V949OriginalEraseSourceBindingV1,
        operation expected: EraseRouterOperationV1,
        intent: EraseIntentV1
    ) throws {
        try lock.withLock {
            guard operation === expected,
                  let preCloseSQLiteImage,
                  validatedPostCloseSourceTree == nil,
                  binding.sourceTreeDigest == sourceTree,
                  binding.eraseID == intent.eraseID,
                  intent.phase == .emptyGenerationPrepared,
                  intent.oldGenerationID == oldGenerationID,
                  intent.newGenerationID == targetGenerationID,
                  intent.oldPointer == oldPointer,
                  intent.sourceLedger == sourceLedger,
                  intent.targetPointer == targetManifestPointer else {
                throw EraseAllServiceError.invalidAuthority
            }
            let after = try authority
                .originalEraseSQLitePhysicalImageForColdExitForTesting(
                    id: oldGenerationID)
            try requireOwnedSQLiteNodeTransition(from: sourceTreeNodes,
                to: after.nodes, allowingSHMModificationTime: false)
            try preCloseSQLiteImage.requireOwnedCloseTransition(to: after.image)
            try requirePublishedControlsUnchanged()
            try requireDefaultsUnchanged()
            validatedPostCloseSourceTree = after.tree
        }
    }

    func beginOwnedReaderOpenTransition(
        binding: V949OriginalEraseSourceBindingV1,
        operation expected: EraseRouterOperationV1,
        intent: EraseIntentV1
    ) throws {
        try lock.withLock {
            guard operation === expected, stage == .sourceBound,
                  let validatedPostCloseSourceTree,
                  preReaderOpenSQLiteImage == nil,
                  validatedPostReaderOpenSourceTree == nil,
                  binding.sourceTreeDigest == sourceTree,
                  binding.eraseID == intent.eraseID,
                  intent.phase == .emptyGenerationPrepared,
                  intent.oldGenerationID == oldGenerationID,
                  intent.newGenerationID == targetGenerationID,
                  intent.oldPointer == oldPointer,
                  intent.sourceLedger == sourceLedger,
                  intent.targetPointer == targetManifestPointer else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireV949OriginalSourceUnchanged(binding,
                operation: expected)
            let before = try authority
                .originalEraseSQLitePhysicalImageForColdExitForTesting(
                    id: oldGenerationID)
            guard before.tree == validatedPostCloseSourceTree else {
                throw EraseAllServiceError.invalidAuthority
            }
            preReaderOpenSQLiteImage = before.image
            preReaderOpenSourceNodes = before.nodes
        }
    }

    func completeOwnedReaderOpenTransition(
        binding: V949OriginalEraseSourceBindingV1,
        operation expected: EraseRouterOperationV1,
        intent: EraseIntentV1
    ) throws {
        try lock.withLock {
            guard operation === expected, stage == .sourceBound,
                  let preReaderOpenSQLiteImage,
                  let preReaderOpenSourceNodes,
                  validatedPostCloseSourceTree != nil,
                  validatedPostReaderOpenSourceTree == nil,
                  binding.sourceTreeDigest == sourceTree,
                  binding.eraseID == intent.eraseID,
                  intent.phase == .emptyGenerationPrepared,
                  intent.oldGenerationID == oldGenerationID,
                  intent.newGenerationID == targetGenerationID,
                  intent.oldPointer == oldPointer,
                  intent.sourceLedger == sourceLedger,
                  intent.targetPointer == targetManifestPointer else {
                throw EraseAllServiceError.invalidAuthority
            }
            let after = try authority
                .originalEraseSQLitePhysicalImageForColdExitForTesting(
                    id: oldGenerationID)
            try requireOwnedSQLiteNodeTransition(from: preReaderOpenSourceNodes,
                to: after.nodes, allowingSHMModificationTime: true)
            // This pure validator accepts only the same complete committed
            // page vector and authenticated WAL prefix, irrespective of the
            // mechanism that caused SQLite's checkpoint representation.
            try preReaderOpenSQLiteImage.requireOwnedCloseTransition(
                to: after.image)
            try requirePublishedControlsUnchanged()
            try requireDefaultsUnchanged()
            validatedPostReaderOpenSourceTree = after.tree
        }
    }

    private func reportSourceTreeDifference(
        _ observed: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]
    ) {
        func category(_ path: String) -> String {
            if path.isEmpty { return "root" }
            let leaf = path.split(separator: "/").last.map(String.init) ?? ""
            switch leaf {
            case "model.sqlite": return "sqlite"
            case "model.sqlite-wal": return "wal"
            case "model.sqlite-shm": return "shm"
            default: return "other"
            }
        }
        let labels = ["membership", "device", "inode", "mode", "nlink",
                      "size", "mtime-seconds", "mtime-nanoseconds",
                      "ctime-seconds", "ctime-nanoseconds", "bytes"]
        var changes = [String: Set<String>]()
        var beforeByPath = [String: EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]()
        var afterByPath = [String: EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]()
        for node in sourceTreeNodes {
            if beforeByPath.updateValue(node, forKey: node.path) != nil {
                changes[category(node.path), default: []].insert("membership")
            }
        }
        for node in observed {
            if afterByPath.updateValue(node, forKey: node.path) != nil {
                changes[category(node.path), default: []].insert("membership")
            }
        }
        for path in Set(beforeByPath.keys).union(afterByPath.keys) {
            let group = category(path)
            guard let old = beforeByPath[path], let new = afterByPath[path] else {
                changes[group, default: []].insert("membership")
                continue
            }
            let a = old.fact, b = new.fact
            if a.st_dev != b.st_dev { changes[group, default: []].insert("device") }
            if a.st_ino != b.st_ino { changes[group, default: []].insert("inode") }
            if a.st_mode != b.st_mode { changes[group, default: []].insert("mode") }
            if a.st_nlink != b.st_nlink { changes[group, default: []].insert("nlink") }
            if a.st_size != b.st_size { changes[group, default: []].insert("size") }
            if a.st_mtimespec.tv_sec != b.st_mtimespec.tv_sec {
                changes[group, default: []].insert("mtime-seconds")
            }
            if a.st_mtimespec.tv_nsec != b.st_mtimespec.tv_nsec {
                changes[group, default: []].insert("mtime-nanoseconds")
            }
            if a.st_ctimespec.tv_sec != b.st_ctimespec.tv_sec {
                changes[group, default: []].insert("ctime-seconds")
            }
            if a.st_ctimespec.tv_nsec != b.st_ctimespec.tv_nsec {
                changes[group, default: []].insert("ctime-nanoseconds")
            }
            if old.sha256 != new.sha256 {
                changes[group, default: []].insert("bytes")
            }
        }
        for group in ["root", "sqlite", "wal", "shm", "other"] {
            let fields = labels.filter { changes[group, default: []].contains($0) }
                .joined(separator: ",")
            FileHandle.standardError.write(Data((
                "V949_ORIGINAL_SOURCE_TREE_DIFFERENCE_V2 category=" + group
                    + " fields=" + (fields.isEmpty ? "none" : fields) + "\n").utf8))
        }
    }

    func requireSourceUnchanged() throws {
        let observed: (digest: String,
            nodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode])
        do {
            observed = try authority
                .originalEraseSourceTreeObservationForColdExitForTesting(
                    id: oldGenerationID)
        } catch {
            FileHandle.standardError.write(Data(
                "V949_ORIGINAL_SOURCE_PHYSICAL_V1 stage=tree-observation-failed\n".utf8))
            throw error
        }
        let expectedTree = lock.withLock {
            validatedPostReaderOpenSourceTree
                ?? validatedPostCloseSourceTree ?? sourceTree
        }
        guard observed.digest == expectedTree else {
            reportSourceTreeDifference(observed.nodes)
            FileHandle.standardError.write(Data(
                "V949_ORIGINAL_SOURCE_PHYSICAL_V1 stage=tree-different\n".utf8))
            throw EraseAllServiceError.invalidAuthority
        }
        if controlsPublished != nil {
            do {
                try requirePublishedControlsUnchanged()
            } catch {
                FileHandle.standardError.write(Data(
                    "V949_ORIGINAL_SOURCE_PHYSICAL_V1 stage=published-controls-failed\n".utf8))
                throw error
            }
        }
    }

    func observeSourceManifest(_ manifest: StoreGenerationManifestV1) {
        lock.withLock {
            manifestObservationCount += 1
            if manifestObservationCount == 1 { sourceManifest = manifest }
        }
    }

    func bindOriginalSourceSemantics(
        pointer: RestorePointerIdentityV1,
        ledger: DeletionLedgerProofV2
    ) throws {
        var stage = "pointer-construction"
        do {
            // RestorePointerIdentityV1 intentionally omits the pointer's schema
            // version. Reconstruct the exact canonical V3 control with the active
            // release, then compare its bytes and the source manifest digest.
            let currentPointer = try CurrentGenerationPointerV3(
                generationID: pointer.generationID,
                generationManifestSHA256: pointer.generationManifestSHA256,
                workspaceID: WorkspaceID(rawValue: pointer.workspaceID),
                replicaID: ReplicaID(rawValue: pointer.replicaID),
                knownReplicaIDs: Set(pointer.knownReplicaIDs.map { ReplicaID(rawValue: $0) }),
                storeSchemaVersion: PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major)
            try lock.withLock {
                stage = "manifest-binding"
                guard manifestObservationCount == 1,
                      let sourceManifest,
                      sourceManifest.generationID == oldGenerationID,
                      pointer.generationID == oldGenerationID,
                      sourceManifest.storeSchemaRelease
                        == PersistentSchemaReleaseRegistryV1.activeRelease,
                      try sourceManifest.canonicalSHA256()
                        == pointer.generationManifestSHA256,
                      oldPointer == nil, sourceLedger == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "ledger-validate"
                try ledger.validate()
                stage = "source-physical"
                try requireSourceUnchanged()
                stage = "canonical-pointer"
                guard controlsOrigin.current == (try currentPointer.canonicalData()) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "control-snapshot"
                guard try authority.originalEraseControlsForColdExitForTesting()
                        == controlsOrigin else {
                    throw EraseAllServiceError.invalidAuthority
                }
                oldPointer = pointer
                sourceLedger = ledger
            }
        } catch {
            FileHandle.standardError.write(Data((
                "V949_ORIGINAL_SOURCE_BIND_V1 stage=" + stage
                    + " errorType=" + String(reflecting: type(of: error)) + "\n"
            ).utf8))
            throw error
        }
    }

    func beforePointerPublication(_ intent: EraseIntentV1) throws {
        try lock.withLock {
            if controlsPublished != nil {
                try requirePublishedControlsUnchanged()
                return
            }
            guard stage == .sourceBound,
                  let oldPointer,
                  intent.oldPointer == oldPointer,
                  intent.targetPointer != nil,
                  targetGenerationID == intent.newGenerationID else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try requireDefaultsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin, allowing: [])
            guard try authority.originalEraseControlsForColdExitForTesting()
                    == controlsOrigin else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func afterPointerPublication(_ intent: EraseIntentV1) throws {
        try lock.withLock {
            if controlsPublished != nil {
                try requirePublishedControlsUnchanged()
                return
            }
            guard stage == .sourceBound,
                  let target = intent.targetPointer else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            controlsPublished = try authority
                .requireOriginalErasePublishedControlsForColdExitForTesting(
                    target: target,
                    retiredIDs: intent.generationIDsToDelete)
        }
    }

    private func requirePublishedControlsUnchanged() throws {
        guard let controlsPublished,
              try authority.originalEraseControlsForColdExitForTesting()
                == controlsPublished else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func bindTargetAbsence(_ id: UUID) throws {
        var stage = "target-binding"
        do {
            try lock.withLock {
                guard oldPointer != nil, sourceLedger != nil,
                      targetGenerationID == nil, id != oldGenerationID else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "target-absence"
                try authority.requireCompletedAbortTargetAbsent(id)
                stage = "source-physical"
                try requireSourceUnchanged()
                stage = "schema-migration"
                guard try auxiliary.originalEraseSchemaMigrationDigestForTesting()
                        == schemaMigrationOrigin else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "target-manifest"
                try auxiliary.requireOriginalEraseTargetManifestAbsentForTesting(id)
                targetGenerationID = id
            }
        } catch {
            FileHandle.standardError.write(Data((
                "V949_ORIGINAL_TARGET_BIND_V1 stage=" + stage
                    + " errorType=" + String(reflecting: type(of: error)) + "\n"
            ).utf8))
            throw error
        }
    }

    func bindCreatedTargetManifest(_ pointer: RestorePointerIdentityV1) throws {
        var stage = "target-binding"
        do {
            try lock.withLock {
                guard targetGenerationID == pointer.generationID,
                      targetManifestPointer == nil,
                      targetManifestIdentity == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "schema-migration"
                let targetManifest = try auxiliary
                    .originalEraseSchemaMigrationExpectedTargetManifestForTesting(
                        pointer, sourceRootLinks: schemaMigrationSourceRootLinks)
                guard targetManifest.digest == schemaMigrationOrigin else {
                    let category: String
                    var rootLinkCounts = ""
                    if let schemaMigrationDiagnosticOrigin,
                       let current = try? auxiliary
                        .originalEraseSchemaMigrationDiagnosticSnapshotForTesting(
                            excludingTarget: pointer.generationID) {
                        category = schemaMigrationDiagnosticOrigin
                            .firstDifference(from: current)
                        if category == "root-links" {
                            let before = schemaMigrationDiagnosticOrigin.rootLinks
                            let after = current.rootLinks
                            let delta = after >= before
                                ? "+" + String(after - before)
                                : "-" + String(before - after)
                            rootLinkCounts = " beforeLinks=" + String(before)
                                + " afterLinks=" + String(after)
                                + " delta=" + delta
                        }
                    } else {
                        category = "snapshot-unavailable"
                    }
                    FileHandle.standardError.write(Data((
                        "V949_SCHEMA_MIGRATION_DIFFERENCE_V1 category="
                            + category + rootLinkCounts + "\n"
                    ).utf8))
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = "target-manifest"
                targetManifestIdentity = targetManifest.identity
                targetManifestPointer = pointer
                stage = "unrelated-operations"
                try requireUnrelatedOperationsUnchanged()
            }
        } catch {
            FileHandle.standardError.write(Data((
                "V949_ORIGINAL_CREATED_BIND_V1 stage=" + stage + "\n"
            ).utf8))
            throw error
        }
    }

    func requireUnrelatedOperationsUnchanged() throws {
        guard try auxiliary.originalEraseUnrelatedOperationsDigestForTesting()
                == unrelatedOperationsDigest else {
            throw EraseAllServiceError.invalidAuthority
        }
        if let targetManifestPointer, let targetManifestIdentity {
            let observed = try auxiliary
                .originalEraseSchemaMigrationExpectedTargetManifestForTesting(
                    targetManifestPointer,
                    sourceRootLinks: schemaMigrationSourceRootLinks)
            guard observed.digest == schemaMigrationOrigin,
                  observed.identity == targetManifestIdentity else {
                throw EraseAllServiceError.invalidAuthority
            }
        } else {
            guard try auxiliary.originalEraseSchemaMigrationDigestForTesting()
                    == schemaMigrationOrigin else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func beforeSearchReplacement() throws {
        try lock.withLock {
            guard stage == .sourceBound else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try requireDefaultsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin, allowing: [])
            guard try auxiliary.originalEraseSearchStateForTesting()
                    == searchOrigin else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func afterSearchReplacement(expectedBytes: Data) throws {
        try lock.withLock {
            guard stage == .sourceBound else {
                throw EraseAllServiceError.invalidAuthority
            }
            do {
                try requireSourceUnchanged()
                try requireUnrelatedOperationsUnchanged()
                try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                    auxiliaryOrigin,
                    allowing: [LocalSearchIndexStoreV1.directoryName])
                let after = try auxiliary.originalEraseSearchStateForTesting()
                guard after.projectionBytes == expectedBytes,
                      after.projectionIdentity != searchOrigin.projectionIdentity,
                      searchOrigin.rootDevice == nil
                        || (after.rootDevice == searchOrigin.rootDevice
                            && after.rootInode == searchOrigin.rootInode) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                searchExpectedBytes = expectedBytes
                stage = .searchPublished
            } catch {
                stage = .uncertain
                throw error
            }
        }
    }

    func requireSearchPublished() throws {
        try lock.withLock {
            guard stage == .searchPublished,
                  let searchExpectedBytes else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin,
                allowing: [LocalSearchIndexStoreV1.directoryName])
            guard try auxiliary.originalEraseSearchStateForTesting()
                    .projectionBytes == searchExpectedBytes else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func bindOriginalDiscoveryOwner(
        _ owner: PrivateSystemDiscoveryIndexStoreV1,
        snapshot: PrivateSystemDiscoveryFileStateStoreV1
            .OriginalErasePhysicalSnapshot
    ) throws {
        try lock.withLock {
            guard stage == .sourceBound,
                  discoveryOwner == nil, discoveryOrigin == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin, allowing: [])
            discoveryOwner = owner
            discoveryOrigin = snapshot
        }
    }

    func beforeDiscoveryEffect(
        _ snapshot: PrivateSystemDiscoveryFileStateStoreV1
            .OriginalErasePhysicalSnapshot
    ) throws {
        try lock.withLock {
            guard stage == .searchPublished,
                  discoveryOrigin == snapshot,
                  discoveryAfter == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSearchPublished()
        }
    }

    func afterDiscoveryEffect(
        _ snapshot: PrivateSystemDiscoveryFileStateStoreV1
            .OriginalErasePhysicalSnapshot
    ) throws {
        try lock.withLock {
            guard stage == .searchPublished,
                  discoveryOrigin != nil,
                  discoveryAfter == nil,
                  snapshot.rootDevice == discoveryOrigin?.rootDevice,
                  snapshot.rootInode == discoveryOrigin?.rootInode,
                  snapshot.data != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSearchPublished()
            discoveryAfter = snapshot
        }
    }

    /// Called again at checked host transfer. The actor's original held
    /// durable root is read without recovery, and the same original source
    /// witness is rechecked after the actor hop. No later state is a baseline.
    func requireOriginalDiscoveryAfterUnchanged() async throws {
        let (owner, after) = try lock.withLock { () throws -> (
            PrivateSystemDiscoveryIndexStoreV1,
            PrivateSystemDiscoveryFileStateStoreV1.OriginalErasePhysicalSnapshot
        ) in
            guard stage == .searchPublished || stage == .notificationRefused
                    || stage == .scratchConstructed || stage == .scratchErased
                    || stage == .exchangePublished,
                  let discoveryOwner, let discoveryAfter else {
                throw EraseAllServiceError.invalidAuthority
            }
            return (discoveryOwner, discoveryAfter)
        }
        guard try await owner.originalErasePhysicalSnapshotForTesting()
                == after else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireSourceUnchanged()
        try requireUnrelatedOperationsUnchanged()
    }

    private func requireEffectPostimageForSourceRead() throws {
        try lock.withLock {
            guard stage == .notificationRefused
                    || stage == .exchangePublished,
                  sourceManifest != nil, sourceLedger != nil,
                  targetGenerationID != nil,
                  discoveryAfter != nil,
                  let searchExpectedBytes,
                  controlsPublished != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try requireDefaultsUnchanged()
            try requirePublishedControlsUnchanged()
            let changed: Set<String> = stage == .exchangePublished
                ? [LocalSearchIndexStoreV1.directoryName,
                    PortableExchangeSessionStoreLayoutV2.directoryName]
                : [LocalSearchIndexStoreV1.directoryName]
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin, allowing: changed)
            guard try auxiliary.originalEraseSearchStateForTesting()
                    .projectionBytes == searchExpectedBytes else {
                throw EraseAllServiceError.invalidAuthority
            }
            if stage == .notificationRefused {
                guard let notificationControl,
                      let notificationAfterRevocation,
                      try notificationControl
                        .originalErasePhysicalSnapshotForTesting()
                        == notificationAfterRevocation else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            if stage == .exchangePublished {
                guard let notificationControl,
                      let notificationAfterSuccess,
                      try notificationControl
                        .originalErasePhysicalSnapshotForTesting()
                        == notificationAfterSuccess else {
                    throw EraseAllServiceError.invalidAuthority
                }
                guard let exchangeExpectedBytes, let exchangeLayout,
                      try auxiliary.originalEraseEmptyScratchStateForTesting()
                        .scratchInode == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let actual = try auxiliary.originalEraseExchangeStateForTesting()
                guard actual.rootDevice == exchangeLayout.rootDevice,
                      actual.rootInode == exchangeLayout.rootInode,
                      actual.envelopeBytes == exchangeExpectedBytes,
                      actual.names == (exchangeLayout.names + [
                        PortableExchangeSessionStoreLayoutV2.envelopeFileName
                      ]).sorted() else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
    }

    @MainActor
    func requireFreshOriginalSourceLedger(
        factory: StoreGenerationFactory
    ) throws {
        let (manifest, ledger) = try lock.withLock { () throws -> (
            StoreGenerationManifestV1, DeletionLedgerProofV2
        ) in
            guard sourceReadObservation == nil,
                  let sourceManifest, let sourceLedger else {
                throw EraseAllServiceError.invalidAuthority
            }
            return (sourceManifest, sourceLedger)
        }
        try requireEffectPostimageForSourceRead()
        try factory.requireFreshRetiredOriginalSourceLedgerForColdExit(
            sourceGenerationID: oldGenerationID,
            manifestMigrationID: manifest.migrationID,
            manifestRelease: manifest.storeSchemaRelease,
            expected: ledger, sourceAuthority: authority,
            retainObservation: { observation in
                try self.lock.withLock {
                    guard self.sourceReadObservation == nil else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    self.sourceReadObservation = observation
                }
            },
            reproveOriginal: { try self.requireEffectPostimageForSourceRead() })
    }

    func requireFreshOriginalSourceReaderDrained() throws {
        try lock.withLock {
            guard let sourceReadObservation else {
                throw EraseAllServiceError.invalidAuthority
            }
            try sourceReadObservation.requireDrained()
        }
        try requireEffectPostimageForSourceRead()
    }

    func beforeScratchConstruction() throws {
        try lock.withLock {
            guard stage == .searchPublished else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSearchPublished()
            guard try auxiliary.originalEraseEmptyScratchStateForTesting()
                    == scratchOrigin else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func retainOriginalNotificationControl(
        _ control: AppLockNotificationControlStoreV1
    ) throws {
        try lock.withLock {
            guard stage == .searchPublished, notificationControl == nil,
                  discoveryAfter != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            notificationControl = control
            do {
                try requireSearchPublished()
                let afterConstruction = try control
                    .originalErasePhysicalSnapshotForTesting()
                if notificationOrigin.rootDevice == nil {
                    guard afterConstruction.rootDevice != nil,
                          afterConstruction.rootInode != nil,
                          afterConstruction.names.isEmpty,
                          afterConstruction.eraseBytes == nil else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                } else {
                    guard afterConstruction.rootDevice
                            == notificationOrigin.rootDevice,
                          afterConstruction.rootInode
                            == notificationOrigin.rootInode,
                          afterConstruction.names == notificationOrigin.names,
                          afterConstruction.unchangedLeavesDigest
                            == notificationOrigin.unchangedLeavesDigest,
                          afterConstruction.eraseBytes
                            == notificationOrigin.eraseBytes,
                          afterConstruction.eraseIdentity
                            == notificationOrigin.eraseIdentity else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
                guard afterConstruction.eraseBytes == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                notificationBeforeEffect = afterConstruction
            } catch {
                stage = .uncertain
                throw error
            }
        }
    }

    func beforeOriginalNotificationRevocation() throws {
        try lock.withLock {
            guard stage == .searchPublished,
                  let notificationControl, let notificationBeforeEffect,
                  notificationAfterRevocation == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSearchPublished()
            guard try notificationControl
                    .originalErasePhysicalSnapshotForTesting()
                    == notificationBeforeEffect else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func afterOriginalNotificationRevocation(
        _ revocation: NotificationEraseRevocationV1
    ) throws {
        try lock.withLock {
            guard stage == .searchPublished,
                  let notificationControl,
                  let notificationBeforeEffect,
                  notificationAfterRevocation == nil,
                  notificationBeforeEffect.eraseBytes == nil,
                  revocation.rootIdentity
                    == notificationControl.notificationRootIdentity else {
                throw EraseAllServiceError.invalidAuthority
            }
            let expected = try CompatibilityCanonicalV1.encode(revocation)
            let actual = try notificationControl
                .originalErasePhysicalSnapshotForTesting()
            guard actual.rootDevice == notificationBeforeEffect.rootDevice,
                  actual.rootInode == notificationBeforeEffect.rootInode,
                  actual.unchangedLeavesDigest
                    == notificationBeforeEffect.unchangedLeavesDigest,
                  actual.eraseBytes == expected,
                  actual.eraseIdentity != nil,
                  actual.names == (notificationBeforeEffect.names
                    + [AppLockNotificationControlStoreV1.eraseName]).sorted()
            else { throw EraseAllServiceError.invalidAuthority }
            try requireSearchPublished()
            notificationAfterRevocation = actual
        }
    }

    func recordOriginalNotificationRefusal(
        revocation: NotificationEraseRevocationV1,
        owned: Set<String>, observedOwned: Set<String>,
        subject: EraseAllOperationSubjectV1
    ) throws {
        try lock.withLock {
            guard stage == .searchPublished,
                  let notificationControl,
                  revocation.operationID == subject.eraseID,
                  revocation.rootIdentity
                    == notificationControl.notificationRootIdentity,
                  !owned.isEmpty, !observedOwned.isEmpty,
                  observedOwned.isSubset(of: owned),
                  notificationRefusal == nil,
                  let notificationAfterRevocation else {
                throw EraseAllServiceError.invalidAuthority
            }
            let actual = try notificationControl
                .originalErasePhysicalSnapshotForTesting()
            guard actual == notificationAfterRevocation else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSearchPublished()
            self.notificationRefusal = (revocation, owned, observedOwned)
            stage = .notificationRefused
        }
    }

    func afterOriginalNotificationSuccess(
        _ revocation: NotificationEraseRevocationV1
    ) throws {
        try lock.withLock {
            guard stage == .searchPublished,
                  let notificationControl,
                  notificationAfterRevocation != nil,
                  notificationAfterSuccess == nil,
                  revocation.rootIdentity
                    == notificationControl.notificationRootIdentity else {
                throw EraseAllServiceError.invalidAuthority
            }
            let actual = try notificationControl
                .originalErasePhysicalSnapshotForTesting()
            guard actual.rootDevice == notificationAfterRevocation?.rootDevice,
                  actual.rootInode == notificationAfterRevocation?.rootInode,
                  actual.names == [AppLockNotificationControlStoreV1.eraseName],
                  actual.eraseBytes
                    == (try CompatibilityCanonicalV1.encode(revocation)) else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSearchPublished()
            notificationAfterSuccess = actual
        }
    }

    func requireOriginalNotificationRefusal(
        operation: EraseRouterOperationV1,
        subject: EraseAllOperationSubjectV1
    ) throws {
        try lock.withLock {
            guard self.operation === operation, stage == .notificationRefused,
                  let notificationRefusal,
                  oldPointer != nil, sourceLedger != nil,
                  sourceManifest != nil,
                  targetGenerationID == subject.newGenerationID,
                  notificationRefusal.revocation.operationID == subject.eraseID,
                  let notificationControl,
                  let notificationAfterRevocation,
                  notificationRefusal.revocation.rootIdentity
                    == notificationControl.notificationRootIdentity else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try requireDefaultsUnchanged()
            try requirePublishedControlsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin,
                allowing: [LocalSearchIndexStoreV1.directoryName])
            guard try auxiliary.originalEraseSearchStateForTesting()
                    .projectionBytes == searchExpectedBytes else {
                throw EraseAllServiceError.invalidAuthority
            }
            guard try notificationControl
                    .originalErasePhysicalSnapshotForTesting()
                    == notificationAfterRevocation else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func afterScratchConstruction(_ owner: ScratchDataLeaseStoreV1) throws {
        try lock.withLock {
            guard stage == .searchPublished, scratchOwner == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            // Retain the real descriptor owner before any later proof can
            // throw; an uncertain constructor/close never drops its aliases.
            scratchOwner = owner
            do {
                try requireSearchPublished()
                let now = try auxiliary.originalEraseEmptyScratchStateForTesting()
                guard now.operationsDevice == scratchOrigin.operationsDevice,
                      now.operationsInode == scratchOrigin.operationsInode,
                      now.scratchDevice != nil,
                      now.scratchInode != nil,
                      scratchOrigin.scratchInode == nil
                        || now.scratchInode == scratchOrigin.scratchInode else {
                    throw EraseAllServiceError.invalidAuthority
                }
                constructedScratch = now
                stage = .scratchConstructed
            } catch {
                stage = .uncertain
                throw error
            }
        }
    }

    func afterScratchErase(_ owner: ScratchDataLeaseStoreV1) throws {
        try lock.withLock {
            guard stage == .scratchConstructed,
                  scratchOwner === owner,
                  constructedScratch != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            do {
                try requireSourceUnchanged()
                try requireUnrelatedOperationsUnchanged()
                try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                    auxiliaryOrigin,
                    allowing: [LocalSearchIndexStoreV1.directoryName])
                let now = try auxiliary.originalEraseEmptyScratchStateForTesting()
                guard now.operationsDevice == scratchOrigin.operationsDevice,
                      now.operationsInode == scratchOrigin.operationsInode,
                      now.scratchDevice == nil,
                      now.scratchInode == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = .scratchErased
            } catch {
                stage = .uncertain
                throw error
            }
        }
    }

    func retainAndCheckExchangeBeforeLoad(
        _ owner: PortableExchangeSessionStoreV2
    ) throws {
        try lock.withLock {
            guard stage == .scratchErased, exchangeOwner == nil,
                  exchangeOrigin.rootDevice == nil,
                  exchangeOrigin.rootInode == nil,
                  exchangeOrigin.envelopeBytes == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            exchangeOwner = owner
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin,
                allowing: [LocalSearchIndexStoreV1.directoryName])
            guard try auxiliary.originalEraseExchangeStateForTesting()
                    == exchangeOrigin else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func checkExchangeBeforePublish(
        predecessor: Data, successor: Data
    ) throws {
        try lock.withLock {
            guard stage == .scratchErased,
                  exchangeOwner != nil,
                  exchangeLayout == nil,
                  exchangeExpectedBytes == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin,
                allowing: [LocalSearchIndexStoreV1.directoryName,
                    PortableExchangeSessionStoreLayoutV2.directoryName])
            let prior = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                PortableExchangeSessionEnvelopeV2.self, from: predecessor)
            let next = try StoreMigrationCanonicalJSONV1.decodeCanonical(
                PortableExchangeSessionEnvelopeV2.self, from: successor)
            guard prior.sessions.isEmpty, prior.quarantine.isEmpty,
                  next.sessions.isEmpty, next.quarantine.isEmpty else {
                throw EraseAllServiceError.invalidAuthority
            }
            let actual = try auxiliary.originalEraseExchangeStateForTesting()
            let expectedNames = [
                PortableExchangeSessionStoreLayoutV2.payloadDirectoryName,
                PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName,
                PortableExchangeSessionStoreLayoutV2.quarantineDirectoryName
            ].sorted()
            guard actual.rootDevice != nil, actual.rootInode != nil,
                  actual.envelopeBytes == nil,
                  actual.names == expectedNames else {
                throw EraseAllServiceError.invalidAuthority
            }
            exchangeLayout = actual
            exchangeExpectedBytes = successor
        }
    }

    func checkExchangeAfterPublish(successor: Data) throws {
        try lock.withLock {
            guard stage == .scratchErased,
                  let exchangeLayout,
                  exchangeExpectedBytes == successor else {
                throw EraseAllServiceError.invalidAuthority
            }
            do {
                try requireSourceUnchanged()
                try requireUnrelatedOperationsUnchanged()
                try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                    auxiliaryOrigin,
                    allowing: [LocalSearchIndexStoreV1.directoryName,
                        PortableExchangeSessionStoreLayoutV2.directoryName])
                let actual = try auxiliary.originalEraseExchangeStateForTesting()
                guard actual.rootDevice == exchangeLayout.rootDevice,
                      actual.rootInode == exchangeLayout.rootInode,
                      actual.envelopeBytes == successor,
                      actual.names == (exchangeLayout.names + [
                        PortableExchangeSessionStoreLayoutV2.envelopeFileName
                      ]).sorted() else {
                    throw EraseAllServiceError.invalidAuthority
                }
                stage = .exchangePublished
            } catch {
                stage = .uncertain
                throw error
            }
        }
    }

    func requirePreparedTransition() throws {
        try lock.withLock {
            guard stage == .exchangePublished,
                  exchangeOwner != nil,
                  scratchOwner != nil,
                  exchangeExpectedBytes != nil,
                  notificationAfterSuccess != nil,
                  oldPointer != nil, sourceLedger != nil,
                  sourceManifest != nil, controlsPublished != nil,
                  targetGenerationID != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireSourceUnchanged()
            try requireUnrelatedOperationsUnchanged()
            try requireDefaultsUnchanged()
            try requirePublishedControlsUnchanged()
            try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                auxiliaryOrigin,
                allowing: [LocalSearchIndexStoreV1.directoryName,
                    PortableExchangeSessionStoreLayoutV2.directoryName])
        }
    }
}
#endif

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

#if DEBUG
    private let postRetiredIO = EraseAbortCheckedSnapshotIOV1()
    // An uncertain diagnostic close cannot poison the authoritative IO owner.
    private let schemaMigrationDiagnosticIO = EraseAbortCheckedSnapshotIOV1()

    /// The Search actor is the sole effect owner; this observation is only a
    /// held-support-root physical check. Unknown siblings are never adopted
    /// as part of the actor's expected empty-envelope transition.
    func originalEraseSearchStateForTesting() throws -> EraseOriginalSearchPhysicalStateV1 {
        try verify()
        let name = LocalSearchIndexStoreV1.directoryName
        var named = stat()
        let present = Darwin.fstatat(
            applicationSupportDescriptor, name, &named, AT_SYMLINK_NOFOLLOW)
        if present != 0, errno == ENOENT {
            return EraseOriginalSearchPhysicalStateV1(
                rootDevice: nil, rootInode: nil,
                projectionBytes: nil, projectionIdentity: nil)
        }
        guard present == 0, named.st_mode & S_IFMT == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor, name: name,
            flags: O_RDONLY | O_DIRECTORY
        ) { directory in
            var held = stat(), namedAfter = stat()
            guard Darwin.fstat(directory, &held) == 0,
                  held.st_dev == named.st_dev, held.st_ino == named.st_ino,
                  Darwin.fstatat(applicationSupportDescriptor, name,
                                 &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                  namedAfter.st_dev == held.st_dev,
                  namedAfter.st_ino == held.st_ino else {
                throw EraseAllServiceError.invalidAuthority
            }
            let names = try postRetiredIO.names(in: directory)
            guard names.isEmpty || names == [LocalSearchIndexStoreV1.fileName] else {
                throw EraseAllServiceError.invalidAuthority
            }
            let value = names.isEmpty ? nil : try postRetiredIO.control(
                parent: directory, name: LocalSearchIndexStoreV1.fileName)
            guard try postRetiredIO.names(in: directory) == names else {
                throw EraseAllServiceError.invalidAuthority
            }
            return EraseOriginalSearchPhysicalStateV1(
                rootDevice: held.st_dev, rootInode: held.st_ino,
                projectionBytes: value?.0, projectionIdentity: value?.1)
        }
    }

    func requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
        _ origin: ErasePostRetiredAuxiliarySnapshotV1,
        allowing changed: Set<String>
    ) throws {
        let current = try postRetiredSnapshot()
        let controlRoots: Set<String> = [
            "FieldEvidenceData", "FieldEvidenceErase", "FieldEvidenceOperations"
        ]
        guard Set(origin.supportNames).subtracting(controlRoots).subtracting(changed)
                == Set(current.supportNames).subtracting(controlRoots).subtracting(changed),
              origin.roots.filter({ !changed.contains($0.key) })
                == current.roots.filter({ !changed.contains($0.key) }) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    /// Registry proves generation-leases, notification owner proves its own
    /// control root, Scratch proves its one create/remove edge, and the
    /// original frame separately proves the one schema-migration manifest
    /// created by the genuine empty-generation factory.
    /// Every other Operations child remains bound to the original frame.
    func originalEraseUnrelatedOperationsDigestForTesting() throws -> String {
        try verify()
        let value = try postRetiredIO.postRetiredTree(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            excluding: [
                "generation-leases", "AppLockNotificationControlV1",
                "ScratchDataV1", "schema-migration"
            ],
            ignoringDirectoryMetadata: [""])
        try verify()
        return value
    }

    /// A bounded, checked-close read alongside the full-tree digest. It does
    /// not authorize any transition; a failed optional diagnostic cannot make
    /// the authoritative digest pass. Unknown node kinds remain unavailable.
    func originalEraseSchemaMigrationDiagnosticSnapshotForTesting(
        excludingTarget targetID: UUID? = nil
    ) throws -> EraseSchemaMigrationDiagnosticSnapshotV1 {
        try verify()
        let snapshot = try schemaMigrationDiagnosticIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            try schemaMigrationDiagnosticIO.withOpen(
                parent: operations, name: "schema-migration",
                flags: O_RDONLY | O_DIRECTORY
            ) { migration in
                var root = stat(), namedRoot = stat()
                guard Darwin.fstat(migration, &root) == 0,
                      root.st_mode & S_IFMT == S_IFDIR,
                      Darwin.fstatat(operations, "schema-migration",
                          &namedRoot, AT_SYMLINK_NOFOLLOW) == 0,
                      namedRoot.st_dev == root.st_dev,
                      namedRoot.st_ino == root.st_ino else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let rootIdentity = "\(root.st_dev)|\(root.st_ino)"
                let rootMode = String(root.st_mode)
                let rootLinks = UInt64(root.st_nlink)
                let originalNames = try schemaMigrationDiagnosticIO.names(in: migration)
                let excluded = targetID.map {
                    "manifest-\($0.uuidString.lowercased()).json"
                }
                var entries: [String: EraseSchemaMigrationDiagnosticFactV1] = [:]
                for name in originalNames where name != excluded {
                    var node = stat()
                    guard Darwin.fstatat(migration, name, &node,
                        AT_SYMLINK_NOFOLLOW) == 0 else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    let kind: String
                    let digest: String
                    switch node.st_mode & S_IFMT {
                    case S_IFREG:
                        kind = "file"
                        let bytes = try schemaMigrationDiagnosticIO.control(
                            parent: migration, name: name,
                            maximum: 32 * 1024 * 1024).0
                        digest = StoreMigrationCanonicalJSONV1.sha256(bytes)
                    case S_IFDIR:
                        kind = "directory"
                        digest = try schemaMigrationDiagnosticIO.postRetiredTree(
                            parent: migration, name: name)
                    default:
                        throw EraseAllServiceError.invalidAuthority
                    }
                    entries[name] = EraseSchemaMigrationDiagnosticFactV1(
                        kind: kind,
                        identity: "\(node.st_dev)|\(node.st_ino)",
                        modeAndLinks: "\(node.st_mode)|\(node.st_nlink)",
                        size: String(node.st_size),
                        modified: "\(node.st_mtimespec.tv_sec)|\(node.st_mtimespec.tv_nsec)",
                        changed: "\(node.st_ctimespec.tv_sec)|\(node.st_ctimespec.tv_nsec)",
                        contentDigest: digest)
                }
                var rootAfter = stat(), namedAfter = stat()
                guard try schemaMigrationDiagnosticIO.names(in: migration)
                        == originalNames,
                      Darwin.fstat(migration, &rootAfter) == 0,
                      Darwin.fstatat(operations, "schema-migration",
                          &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                      rootAfter.st_dev == root.st_dev,
                      rootAfter.st_ino == root.st_ino,
                      rootAfter.st_mode == root.st_mode,
                      rootAfter.st_nlink == root.st_nlink,
                      namedAfter.st_dev == root.st_dev,
                      namedAfter.st_ino == root.st_ino else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return EraseSchemaMigrationDiagnosticSnapshotV1(
                    rootIdentity: rootIdentity,
                    rootMode: rootMode, rootLinks: rootLinks, entries: entries)
            }
        }
        try verify()
        return snapshot
    }

    func originalEraseSchemaMigrationDigestForTesting(
        excludingTarget targetID: UUID? = nil
    ) throws -> String {
        try verify()
        let value = try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            let excluded = Set(targetID.map {
                ["manifest-\($0.uuidString.lowercased()).json"]
            } ?? [])
            return try postRetiredIO.postRetiredTree(
                parent: operations, name: "schema-migration",
                excluding: excluded,
                ignoringDirectoryMetadata: [""])
        }
        try verify()
        return value
    }

    /// One checked tree walk binds the source digest and its root link count.
    /// A separate optional diagnostic snapshot never supplies authority here.
    func originalEraseSchemaMigrationSourceSnapshotForTesting()
        throws -> (digest: String, rootLinks: UInt64) {
        try verify()
        let value = try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            var rootLinks: UInt64?
            let digest = try postRetiredIO.postRetiredTree(
                parent: operations, name: "schema-migration",
                ignoringDirectoryMetadata: [""],
                observedRootLinks: { rootLinks = $0 })
            guard let rootLinks else {
                throw EraseAllServiceError.invalidAuthority
            }
            return (digest: digest, rootLinks: rootLinks)
        }
        try verify()
        return value
    }

    /// The only normalized root-link transition follows an authentic
    /// operation-bound target manifest. The checked walk still hashes every
    /// other directory and file fact and excludes only that target leaf.
    func originalEraseSchemaMigrationExpectedTargetManifestForTesting(
        _ pointer: RestorePointerIdentityV1,
        sourceRootLinks: UInt64
    ) throws -> (digest: String, identity: String) {
        let identity = try originalEraseTargetManifestForTesting(pointer)
        try verify()
        let digest = try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            try postRetiredIO.postRetiredTree(
                parent: operations, name: "schema-migration",
                excluding: ["manifest-\(pointer.generationID.uuidString.lowercased()).json"],
                ignoringDirectoryMetadata: [""],
                normalizingSingleTargetManifestRootLinksFrom: sourceRootLinks)
        }
        try verify()
        return (digest: digest, identity: identity)
    }

    func originalEraseTargetManifestForTesting(
        _ pointer: RestorePointerIdentityV1
    ) throws -> String {
        try verify()
        let identity = try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            try postRetiredIO.withOpen(
                parent: operations, name: "schema-migration",
                flags: O_RDONLY | O_DIRECTORY
            ) { migration in
                let name = "manifest-\(pointer.generationID.uuidString.lowercased()).json"
                let (data, identity) = try postRetiredIO.control(
                    parent: migration, name: name, maximum: 32 * 1024 * 1024)
                let manifest = try StoreGenerationManifestV1.decodeCanonical(
                    from: data)
                guard manifest.generationID == pointer.generationID,
                      manifest.storeSchemaRelease
                        == PersistentSchemaReleaseRegistryV1.activeRelease,
                      StoreMigrationCanonicalJSONV1.sha256(data)
                        == pointer.generationManifestSHA256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return identity
            }
        }
        try verify()
        return identity
    }

    func requireOriginalEraseTargetManifestAbsentForTesting(_ id: UUID) throws {
        try verify()
        try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            try postRetiredIO.withOpen(
                parent: operations, name: "schema-migration",
                flags: O_RDONLY | O_DIRECTORY
            ) { migration in
                let name = "manifest-\(id.uuidString.lowercased()).json"
                var value = stat()
                guard Darwin.fstatat(migration, name, &value,
                                     AT_SYMLINK_NOFOLLOW) != 0,
                      errno == ENOENT else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        try verify()
    }

    func originalEraseNotificationStateForTesting() throws
        -> EraseOriginalNotificationPhysicalSnapshotV1 {
        try verify()
        return try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            try AppLockNotificationControlStoreV1
                .originalErasePhysicalSnapshotForTesting(
                    operationsDescriptor: operations, io: postRetiredIO)
        }
    }

    /// Only an absent or exactly empty ScratchDataV1 root is admitted by the
    /// two S6 fixtures. A live lease/tombstone is genuine work and refuses
    /// this narrow host-boundary seam rather than being silently discarded.
    func originalEraseEmptyScratchStateForTesting() throws
        -> EraseOriginalScratchPhysicalStateV1 {
        try verify()
        return try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY
        ) { operations in
            var parent = stat(), namedParent = stat()
            guard Darwin.fstat(operations, &parent) == 0,
                  Darwin.fstatat(applicationSupportDescriptor,
                                 "FieldEvidenceOperations", &namedParent,
                                 AT_SYMLINK_NOFOLLOW) == 0,
                  parent.st_mode & S_IFMT == S_IFDIR,
                  parent.st_dev == namedParent.st_dev,
                  parent.st_ino == namedParent.st_ino else {
                throw EraseAllServiceError.invalidAuthority
            }
            var scratch = stat()
            let found = Darwin.fstatat(
                operations, "ScratchDataV1", &scratch, AT_SYMLINK_NOFOLLOW)
            if found != 0, errno == ENOENT {
                return EraseOriginalScratchPhysicalStateV1(
                    operationsDevice: parent.st_dev,
                    operationsInode: parent.st_ino,
                    scratchDevice: nil, scratchInode: nil)
            }
            guard found == 0, scratch.st_mode & S_IFMT == S_IFDIR else {
                throw EraseAllServiceError.invalidAuthority
            }
            return try postRetiredIO.withOpen(
                parent: operations, name: "ScratchDataV1",
                flags: O_RDONLY | O_DIRECTORY
            ) { root in
                var held = stat(), named = stat()
                guard Darwin.fstat(root, &held) == 0,
                      Darwin.fstatat(operations, "ScratchDataV1",
                                     &named, AT_SYMLINK_NOFOLLOW) == 0,
                      held.st_dev == scratch.st_dev,
                      held.st_ino == scratch.st_ino,
                      named.st_dev == held.st_dev,
                      named.st_ino == held.st_ino,
                      try postRetiredIO.names(in: root).isEmpty else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return EraseOriginalScratchPhysicalStateV1(
                    operationsDevice: parent.st_dev,
                    operationsInode: parent.st_ino,
                    scratchDevice: held.st_dev,
                    scratchInode: held.st_ino)
            }
        }
    }

    /// The two S6 fixtures admit only an absent original Exchange root and
    /// its exact owned empty-layout successor. No journal, migration receipt,
    /// payload, capability, quarantine child or foreign name is accepted.
    func originalEraseExchangeStateForTesting() throws
        -> EraseOriginalExchangePhysicalStateV1 {
        try verify()
        let rootName = PortableExchangeSessionStoreLayoutV2.directoryName
        var named = stat()
        let found = Darwin.fstatat(
            applicationSupportDescriptor, rootName, &named, AT_SYMLINK_NOFOLLOW)
        if found != 0, errno == ENOENT {
            return EraseOriginalExchangePhysicalStateV1(
                rootDevice: nil, rootInode: nil,
                envelopeBytes: nil, names: [])
        }
        guard found == 0, named.st_mode & S_IFMT == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try postRetiredIO.withOpen(
            parent: applicationSupportDescriptor, name: rootName,
            flags: O_RDONLY | O_DIRECTORY
        ) { root in
            var held = stat()
            guard Darwin.fstat(root, &held) == 0,
                  held.st_dev == named.st_dev,
                  held.st_ino == named.st_ino else {
                throw EraseAllServiceError.invalidAuthority
            }
            let names = try postRetiredIO.names(in: root)
            let ownedDirectories = [
                PortableExchangeSessionStoreLayoutV2.payloadDirectoryName,
                PortableExchangeSessionStoreLayoutV2.capabilityDirectoryName,
                PortableExchangeSessionStoreLayoutV2.quarantineDirectoryName
            ]
            let allowed = Set(ownedDirectories + [
                PortableExchangeSessionStoreLayoutV2.envelopeFileName])
            guard Set(names).isSubset(of: allowed) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for child in ownedDirectories where names.contains(child) {
                try postRetiredIO.withOpen(
                    parent: root, name: child,
                    flags: O_RDONLY | O_DIRECTORY
                ) { directory in
                    guard try postRetiredIO.names(in: directory).isEmpty else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            }
            let envelopeName = PortableExchangeSessionStoreLayoutV2.envelopeFileName
            let envelope = names.contains(envelopeName)
                ? try postRetiredIO.control(parent: root, name: envelopeName).0
                : nil
            guard try postRetiredIO.names(in: root) == names else {
                throw EraseAllServiceError.invalidAuthority
            }
            return EraseOriginalExchangePhysicalStateV1(
                rootDevice: held.st_dev, rootInode: held.st_ino,
                envelopeBytes: envelope, names: names)
        }
    }

    /// Observes only original-held auxiliary roots. Operations is checked
    /// before control release; its authorized guard transition is proved by
    /// the Registry and is not called equal after unlink.
    /// The original Service frame binds this sibling before its injected
    /// failure. The exclusive SOURCE copy only observes it under the same
    /// retained Support root and original G/EX; it never adopts or repairs it.
    func completedAbortProtectedIngressTree() throws -> String? {
        try verify()
        let name = "FieldEvidenceOperations"
        var operations = stat()
        let present = Darwin.fstatat(applicationSupportDescriptor,
            name, &operations, AT_SYMLINK_NOFOLLOW)
        if present != 0 {
            guard errno == ENOENT else { throw EraseAllServiceError.invalidAuthority }
            return nil
        }
        guard operations.st_mode & S_IFMT == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try postRetiredIO.withOpen(parent: applicationSupportDescriptor,
            name: name, flags: O_RDONLY | O_DIRECTORY) { operationsFD in
            var sibling = stat()
            let found = Darwin.fstatat(operationsFD,
                "ProtectedIngressReceiptsV1", &sibling, AT_SYMLINK_NOFOLLOW)
            if found != 0 {
                guard errno == ENOENT else { throw EraseAllServiceError.invalidAuthority }
                return nil
            }
            guard sibling.st_mode & S_IFMT == S_IFDIR else {
                throw EraseAllServiceError.invalidAuthority
            }
            let observed = try postRetiredIO.postRetiredTree(
                parent: operationsFD, name: "ProtectedIngressReceiptsV1")
            var after = stat()
            guard Darwin.fstatat(operationsFD,
                      "ProtectedIngressReceiptsV1", &after,
                      AT_SYMLINK_NOFOLLOW) == 0,
                  after.st_dev == sibling.st_dev,
                  after.st_ino == sibling.st_ino,
                  after.st_mode == sibling.st_mode,
                  after.st_nlink == sibling.st_nlink else {
                throw EraseAllServiceError.invalidAuthority
            }
            try verify()
            return observed
        }
    }

    func postRetiredSnapshot() throws -> ErasePostRetiredAuxiliarySnapshotV1 {
        try verify()
        func optionalTree(_ parent: Int32, _ name: String) throws -> String? {
            var value = stat()
            let result = Darwin.fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW)
            if result != 0, errno == ENOENT { return nil }
            guard result == 0, value.st_mode & S_IFMT == S_IFDIR else {
                throw EraseAllServiceError.invalidAuthority
            }
            return try postRetiredIO.postRetiredTree(parent: parent, name: name)
        }
        let supportNames = try postRetiredIO.names(in: applicationSupportDescriptor)
        let targets = [
            "FieldEvidenceRestore", "FieldEvidenceCommerce",
            "FieldEvidenceDiagnostics", LocalSearchIndexStoreV1.directoryName,
            PortableExchangeSessionStoreLayoutV2.directoryName,
            LocalJobStoreSchemaV1.directoryName
        ]
        // Every Application Support entry must have one original held-root
        // owner in this witness. Data belongs to generation authority, Erase
        // to the original IntentStore, Operations to the partitioned
        // auxiliary/Registry/notification owners, and these six to auxiliary.
        // An unfamiliar root cannot be accepted as an opaque unchanged name.
        let assignedSupportNames = Set(targets).union([
            "FieldEvidenceData", "FieldEvidenceErase",
            "FieldEvidenceOperations"
        ])
        guard Set(supportNames).isSubset(of: assignedSupportNames) else {
            throw EraseAllServiceError.invalidAuthority
        }
        var roots: [String: String] = [:]
        for name in targets {
            roots[name] = try optionalTree(applicationSupportDescriptor, name)
        }
        roots["Caches/FieldEvidenceApp"] = try optionalTree(
            cachesDescriptor, "FieldEvidenceApp")
        roots["Temporary/FieldEvidenceApp"] = try optionalTree(
            temporaryDescriptor, "FieldEvidenceApp")
        let operations = try optionalTree(
            applicationSupportDescriptor, "FieldEvidenceOperations")
        guard try postRetiredIO.names(in: applicationSupportDescriptor) == supportNames,
              try optionalTree(applicationSupportDescriptor,
                  "FieldEvidenceOperations") == operations else {
            throw EraseAllServiceError.invalidAuthority
        }
        for name in targets {
            guard try optionalTree(applicationSupportDescriptor, name)
                    == roots[name] else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard try optionalTree(cachesDescriptor, "FieldEvidenceApp")
                  == roots["Caches/FieldEvidenceApp"],
              try optionalTree(temporaryDescriptor, "FieldEvidenceApp")
                  == roots["Temporary/FieldEvidenceApp"] else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
        return ErasePostRetiredAuxiliarySnapshotV1(
            supportNames: supportNames, roots: roots,
            operationsBeforeRelease: operations)
    }
#endif

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

    // A completed pre-intent abort must observe the actual Erase namespace
    // absent. Opening EraseIntentStore here would create that namespace.
    func requireEraseRootAbsentForAbortedAdmission() throws {
        func requireHeldAndNamed(_ descriptor: Int32, _ url: URL,
                                 _ expected: Identity) throws {
            try Self.require(descriptor, expected)
            var named = stat()
            guard Darwin.lstat(url.path, &named) == 0,
                  named.st_mode & S_IFMT == S_IFDIR,
                  named.st_dev == expected.device,
                  named.st_ino == expected.inode else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try requireHeldAndNamed(applicationSupportDescriptor,
                                applicationSupportURL, applicationSupportIdentity)
        try requireHeldAndNamed(cachesDescriptor, cachesDirectoryURL, cachesIdentity)
        try requireHeldAndNamed(temporaryDescriptor, temporaryDirectoryURL, temporaryIdentity)
        var named = stat()
        let result = Darwin.fstatat(applicationSupportDescriptor,
                                    "FieldEvidenceErase", &named,
                                    AT_SYMLINK_NOFOLLOW)
        let lookupError = errno
        guard result != 0, lookupError == ENOENT else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireHeldAndNamed(applicationSupportDescriptor,
                                applicationSupportURL, applicationSupportIdentity)
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
            PortableExchangeSessionStoreLayoutV2.directoryName,
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

    func removeFrozenTargets(expectedOperationsIdentity: StreamingArchiveRootIdentityV1? = nil) throws {
        try verifyTargets()
        for name in [
            "FieldEvidenceRestore",
            "FieldEvidenceOperations",
            "FieldEvidenceCommerce",
            "FieldEvidenceDiagnostics",
            LocalSearchIndexStoreV1.directoryName,
            PortableExchangeSessionStoreLayoutV2.directoryName,
        ] {
            try Self.removeDirectoryIfPresent(
                parent: applicationSupportDescriptor,
                name: name,
                expectedRootIdentity: name == "FieldEvidenceOperations" ? expectedOperationsIdentity : nil
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
            PortableExchangeSessionStoreLayoutV2.directoryName,
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

    func removeCompletionControlRoot() throws {
        try verify()
        try Self.removeDirectoryIfPresent(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceOperations"
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
        name: String,
        expectedRootIdentity: StreamingArchiveRootIdentityV1? = nil
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
            if let expectedRootIdentity {
                guard UInt64(bitPattern: Int64(expected.device)) == expectedRootIdentity.device,
                      UInt64(expected.inode) == expectedRootIdentity.inode else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
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
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                throw EraseAllServiceError.invalidAuthority
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


// MARK: - C33 temporal evidence Erase closure

enum TemporalEvidenceEraseAllEnrollmentV1 {
    static let durableRows = TemporalEvidenceKernelDeletionEnrollmentV1.durableRowNames
    static let clearsCanonicalContent = true
    static let clearsScratchAndQuarantine = true
    static let leavesSearchProjection = false

    static func validate() throws {
        try TemporalEvidenceKernelDeletionEnrollmentV1.validate()
        guard durableRows.count == 2, clearsCanonicalContent,
              clearsScratchAndQuarantine, !leavesSearchProjection else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}


@MainActor
extension EraseAllService {
    /// Exact post-Erase proof for the newly activated generation. The generic
    /// generation swap performs deletion; this check prevents C33 rows or the
    /// canonical content namespace from surviving it unnoticed.
    func validateTemporalEvidenceEraseClosure(
        session: StoreGenerationSession
    ) throws {
        guard try session.modelContext.fetchCount(
            FetchDescriptor<TemporalEvidenceClipRow>()
        ) == 0,
        try session.modelContext.fetchCount(
            FetchDescriptor<TimecodedEvidenceAnchorRow>()
        ) == 0 else { throw EraseAllServiceError.invalidAuthority }
        let contentRoot = session.generationRootURL.appendingPathComponent(
            "content", isDirectory: true
        )
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: contentRoot.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue,
                  try FileManager.default.contentsOfDirectory(atPath: contentRoot.path).isEmpty else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try TemporalEvidenceEraseAllEnrollmentV1.validate()
    }

    func validateAcceptedLabelEraseClosure(
        session: StoreGenerationSession
    ) throws {
        guard try session.modelContext.fetchCount(
            FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()
        ) == 0 else { throw EraseAllServiceError.invalidAuthority }
        try C45AcceptedLabelKernelDeletionEnrollmentV1.validate()
    }

    func validateOperationalContactEraseClosure(
        session: StoreGenerationSession
    ) throws {
        guard try session.modelContext.fetchCount(
            FetchDescriptor<ServiceContactPointRow>()
        ) == 0,
        try session.modelContext.fetchCount(
            FetchDescriptor<SystemHandoffIntentRow>()
        ) == 0 else { throw EraseAllServiceError.invalidAuthority }
        try C46OperationalContactKernelDeletionEnrollmentV1.validate()
    }

    func validateActivityContractEraseClosure(
        session: StoreGenerationSession
    ) throws {
        guard try session.modelContext.fetchCount(FetchDescriptor<ActivitySessionEnvelopeRow>()) == 0,
              try session.modelContext.fetchCount(FetchDescriptor<ActivityStateTransitionRow>()) == 0,
              try session.modelContext.fetchCount(FetchDescriptor<InstallationTaskResultRow>()) == 0,
              try session.modelContext.fetchCount(FetchDescriptor<InstallationAsBuiltSnapshotRow>()) == 0,
              try session.modelContext.fetchCount(FetchDescriptor<PunchReviewBasisSnapshotRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try C47ActivityContractKernelDeletionEnrollmentV2.validate()
    }

    func validateImportBulkEraseClosure(session: StoreGenerationSession) throws {
        guard try session.modelContext.fetchCount(FetchDescriptor<ImportMappingProfileRowV1>()) == 0,
              try session.modelContext.fetchCount(FetchDescriptor<BulkSessionRowV1>()) == 0,
              try session.modelContext.fetchCount(FetchDescriptor<BulkCommitReceiptRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try C08ImportBulkKernelDeletionEraseEnrollmentV1.validate()
    }
}

enum C45AcceptedLabelEraseAllBoundaryV1 { static let deletesAcceptedSnapshotRows=true;static let deletesLeasedLabelScratch=true }

enum EvidenceQualityEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<EvidenceQualityRuleSetRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<EvidenceQualityAssessmentRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<EvidenceQualityWaiverRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try EvidenceQualityKernelDeletionEraseEnrollmentV1.validate()
    }
}

enum FastSurveyInboxEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<CaptureInboxItemRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<CapturePromotionRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<SnippetRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<SnippetInsertionHistoryRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try FastSurveyInboxKernelDeletionEraseEnrollmentV1.validate()
    }
}

enum ReinspectionExceptionEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<ReinspectionPlanRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<UnchangedAttestationRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<ReinspectionExceptionMutationReceiptRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try ReinspectionExceptionKernelDeletionEraseEnrollmentV1.validate()
    }
}

enum EntityIdentityResolutionEraseAllPolicyV1 {
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<EntityAliasLinkRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<EntityConsolidationReceiptRowV1>()) == 0,
              try context.fetchCount(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try EntityIdentityResolutionKernelDeletionEraseEnrollmentV1.validate()
    }
}

enum PracticeWorkspaceProvenanceEraseAllPolicyV1 {
    /// Erase is the only C16 destructive operation for the durable row. A
    /// subsequent starter install must be an explicit, separate command.
    static func validatePublishedEmptyGeneration(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try PracticeWorkspaceKernelDeletionEraseEnrollmentV1.validate()
    }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-erase

#if DEBUG
/// Captured on the genuine post-retirement Service frame *before* injecting
/// the fault. Every component belongs to the original retained owner.
private final class ErasePostRetiredFaultWitnessV1 {
    let proof: ErasedRegistryRetirementProofV1
    let generation: ErasePostRetiredGenerationSnapshotV1
    let auxiliary: ErasePostRetiredAuxiliarySnapshotV1
    let intent: ErasePostRetiredIntentSnapshotV1
    let notification: ErasePostRetiredNotificationSnapshotV1
    let defaults: NSDictionary?
    init(proof: ErasedRegistryRetirementProofV1,
         generation: ErasePostRetiredGenerationSnapshotV1,
         auxiliary: ErasePostRetiredAuxiliarySnapshotV1,
         intent: ErasePostRetiredIntentSnapshotV1,
         notification: ErasePostRetiredNotificationSnapshotV1,
         defaults: NSDictionary?) {
        self.proof = proof; self.generation = generation
        self.auxiliary = auxiliary; self.intent = intent
        self.notification = notification; self.defaults = defaults
    }
}

/// The pristine prepared owner has no injected failure. This binds the exact
/// post-effect controls only after the original source frame and the fresh
/// read-only source semantic proof have both succeeded under its real EX.
private final class EraseOriginalColdExitPreDeletionWitnessV1 {
    let proof: ErasedRegistryRetirementProofV1
    let generation: ErasePostRetiredGenerationSnapshotV1
    let auxiliary: ErasePostRetiredAuxiliarySnapshotV1
    let intent: ErasePostRetiredIntentSnapshotV1
    let defaults: NSDictionary?

    init(proof: ErasedRegistryRetirementProofV1,
         generation: ErasePostRetiredGenerationSnapshotV1,
         auxiliary: ErasePostRetiredAuxiliarySnapshotV1,
         intent: ErasePostRetiredIntentSnapshotV1,
         defaults: NSDictionary?) {
        self.proof = proof
        self.generation = generation
        self.auxiliary = auxiliary
        self.intent = intent
        self.defaults = defaults
    }
}
#endif

/// The post-detach cleanup owns filesystem/configuration resources only.
/// Scene, discovery, notification-system and lifecycle callbacks finish before
/// this object is formed; it retains no service, session or ModelContext.
@MainActor
final class EraseCleanupAfterRetirementV1 {
    private enum Phase: Equatable { case prepared, generationsRemoved, manifestPreserved, removingNamespace, namespaceRemoved,
        preferencesPrepared, diagnosticsVerified, phaseWritten, preparationRemoved,
        intentRemoved, eraseRootRemoved, released, abandonmentPending, abandoned, closeUncertain }
    let binding: EraseRetirementBindingV1
    private let intent: EraseIntentV1
    private let factory: StoreGenerationFactory
    private let authority: StoreRestoreGenerationAuthority
    private let auxiliary: EraseAuxiliaryAuthority
    private let intentStore: EraseIntentStore
    private let observation: EraseIntentStore.RetirementObservation
    private let manifestScope: EraseCurrentManifestScopeV1
    private let targetReader: GenerationLeaseHandleV1
    private let diagnosticsStore: DiagnosticsStore
    private let notificationControl: AppLockNotificationControlStoreV1
    private let userDefaults: UserDefaults
    private let defaultsDomainName: String
    private let fileManager: FileManager
    private let failureInjection: EraseAllFailureInjection?
    private let reservation: AppAccessGateV1.EraseAdoptionToken?
    private var exclusion: EraseRetirementExclusionV1?
    private(set) var retirement: EraseSessionRetirementV1?
    private(set) var proof: ErasedRegistryRetirementProofV1?
    private var receipt: CompletedEraseReceiptV1?
    // Captured aliases remain subject to the actual weak drain before delivery.
    private var completion: (@MainActor (CompletedEraseReceiptV1) -> Void)?
    private var diagnosticsZero: Data?
    private var phase: Phase = .prepared
    private var running = false
#if DEBUG
    private var interruptedLateFault: EraseAllFailurePoint?
    private var coldCleanupProofObservationForTesting: (@MainActor (String) -> Void)?

    fileprivate func installColdCleanupProofObservationForTesting(
        _ observation: (@MainActor (String) -> Void)?
    ) throws {
        guard phase == .prepared,
              coldCleanupProofObservationForTesting == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        coldCleanupProofObservationForTesting = observation
    }

    private var afterOldGenerationDeletionBeforeRetiredPointerClearForTesting:
        (@MainActor () throws -> Void)?

    fileprivate func installRetiredPointerCutHookForTesting(
        _ hook: @escaping @MainActor () throws -> Void
    ) throws {
        guard phase == .prepared,
              afterOldGenerationDeletionBeforeRetiredPointerClearForTesting == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        afterOldGenerationDeletionBeforeRetiredPointerClearForTesting = hook
    }
    private var interruptedPostRetiredFault = false
    private var postRetiredWitness: ErasePostRetiredFaultWitnessV1?
    private var originalPostEffectNotification: ErasePostRetiredNotificationSnapshotV1?

    /// Seal the genuine OS-success revocation marker before the original
    /// Service returns and before an interruption fixture may alter its inode.
    fileprivate func sealOriginalPostEffectNotificationForTesting(
        _ witnessedAfterOSReadback: ErasePostRetiredNotificationSnapshotV1
    ) throws {
        guard phase == .prepared, originalPostEffectNotification == nil,
              try notificationControl.postRetiredSnapshot(subject: binding.subject)
                == witnessedAfterOSReadback else {
            throw EraseAllServiceError.invalidAuthority
        }
        originalPostEffectNotification = witnessedAfterOSReadback
    }

    fileprivate func requireOriginalPostEffectNotificationForTesting() throws {
        guard phase == .prepared, let originalPostEffectNotification else {
            throw EraseAllServiceError.invalidAuthority
        }
        let observed = try notificationControl.postRetiredSnapshot(
            subject: binding.subject)
        guard observed == originalPostEffectNotification else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
    private var originalColdExitFrame: EraseOriginalColdExitFrameV1?
    private var originalColdExitPreDeletionWitness:
        EraseOriginalColdExitPreDeletionWitnessV1?
    private var pristineColdExitRequested = false

    fileprivate func retainOriginalColdExitFrameForTesting(
        _ frame: EraseOriginalColdExitFrameV1
    ) throws {
        guard phase == .prepared, originalColdExitFrame == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        try frame.requirePreparedTransition()
        originalColdExitFrame = frame
    }

    fileprivate func requireOriginalColdExitFrameForTesting() throws
        -> EraseOriginalColdExitFrameV1 {
        guard phase == .prepared, let originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        try originalColdExitFrame.requirePreparedTransition()
        return originalColdExitFrame
    }

    /// Observe the published target through this prepared cleanup's original
    /// held generation authority. A fresh Factory would contend with the
    /// transferred Erase EX and would not prove the same physical owner.
    func requirePublishedTargetForV949Fixture() throws -> UUID {
        guard !running, phase == .prepared, retirement != nil,
              exclusion != nil, proof == nil, receipt == nil,
              intent.phase == .sessionActivated,
              binding.subject.eraseID == intent.eraseID,
              binding.subject.newGenerationID == intent.newGenerationID,
              let target = intent.targetPointer,
              target.generationID == intent.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        _ = try authority.requireOriginalErasePublishedControlsForColdExitForTesting(
            target: target, retiredIDs: intent.generationIDsToDelete)
        return target.generationID
    }

    func requirePristineOriginalPreparedColdExitForTesting(
        subject: EraseAllOperationSubjectV1,
        expectedReservation: AppAccessGateV1.EraseAdoptionToken
    ) throws {
        guard !running, phase == .prepared, proof == nil,
              originalColdExitPreDeletionWitness == nil,
              interruptedLateFault == nil,
              !interruptedPostRetiredFault,
              retirement != nil, exclusion != nil,
              binding.subject == subject,
              reservation == expectedReservation,
              expectedReservation.subject == subject,
              intent.phase == .sessionActivated,
              receipt == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        _ = try requireOriginalColdExitFrameForTesting()
        try intentStore.requireRetirementObservation(observation)
    }

    func beginPristineOriginalPreparedColdExitForTesting(
        subject: EraseAllOperationSubjectV1,
        expectedReservation: AppAccessGateV1.EraseAdoptionToken
    ) throws {
        guard !pristineColdExitRequested else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requirePristineOriginalPreparedColdExitForTesting(
            subject: subject, expectedReservation: expectedReservation)
        pristineColdExitRequested = true
    }

    func retirePristineOriginalForColdExitForTesting(
        subject: EraseAllOperationSubjectV1,
        expectedReservation: AppAccessGateV1.EraseAdoptionToken,
        registry: GenerationLeaseRegistryV1
    ) async throws -> (ErasedRegistryRetirementProofV1, String) {
        guard pristineColdExitRequested else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requirePristineOriginalPreparedColdExitForTesting(
            subject: subject, expectedReservation: expectedReservation)
        guard let retirement,
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        running = true
        defer { running = false }
        do {
            try await frame.requireOriginalDiscoveryAfterUnchanged()
            try frame.requireFreshOriginalSourceLedger(factory: factory)
            try frame.requireFreshOriginalSourceReaderDrained()
            guard let actual = try await retirement.validateAndAdvance(
                factory: factory, authority: authority,
                targetReader: targetReader,
                manifestScope: manifestScope) else {
                throw EraseAllServiceError.recoveryRequired
            }
            proof = actual
            try frame.requireFreshOriginalSourceReaderDrained()
            try await frame.requireOriginalDiscoveryAfterUnchanged()
            try actual.requireReadyForPreDeletionAbandonmentForTesting(
                registry: registry)
            let generation = try authority.snapshotPostRetiredEraseGenerations(
                newID: intent.newGenerationID,
                deleting: intent.generationIDsToDelete)
            let auxiliarySnapshot = try auxiliary.postRetiredSnapshot()
            guard let operationsDigest = auxiliarySnapshot.operationsBeforeRelease else {
                throw EraseAllServiceError.invalidAuthority
            }
            let intentSnapshot = try intentStore.postRetiredSnapshot(
                observation: observation)
            originalColdExitPreDeletionWitness =
                EraseOriginalColdExitPreDeletionWitnessV1(
                    proof: actual, generation: generation,
                    auxiliary: auxiliarySnapshot, intent: intentSnapshot,
                    defaults: try defaultsSnapshotForPostRetiredFault())
            return (actual, operationsDigest)
        } catch {
            phase = .closeUncertain
            throw error
        }
    }

    func abandonPristineOriginalForColdExitForTesting(
        subject: EraseAllOperationSubjectV1,
        expectedReservation: AppAccessGateV1.EraseAdoptionToken,
        registry: GenerationLeaseRegistryV1
    ) throws {
        guard !running, phase == .prepared,
              binding.subject == subject,
              reservation == expectedReservation,
              let originalColdExitPreDeletionWitness,
              let proof,
              proof === originalColdExitPreDeletionWitness.proof,
              let retirement, retirement.ownsProof(proof),
              let frame = originalColdExitFrame else {
            throw EraseAllServiceError.invalidAuthority
        }
        phase = .abandonmentPending
        do {
            try frame.requireFreshOriginalSourceReaderDrained()
            try proof.abandonBeforeDeletionForTesting(registry: registry)
            try frame.requireFreshOriginalSourceReaderDrained()
            let witness = originalColdExitPreDeletionWitness
            let generation = try authority.snapshotPostRetiredEraseGenerations(
                newID: intent.newGenerationID,
                deleting: intent.generationIDsToDelete)
            let auxiliaryAfter = try auxiliary.postRetiredSnapshot()
            let intentAfter = try intentStore.postRetiredSnapshot(
                observation: observation)
            let defaultsAfter = try defaultsSnapshotForPostRetiredFault()
            guard generation == witness.generation,
                  auxiliaryAfter.supportNames == witness.auxiliary.supportNames,
                  auxiliaryAfter.roots == witness.auxiliary.roots,
                  intentAfter == witness.intent,
                  ((defaultsAfter == nil && witness.defaults == nil)
                    || defaultsAfter?.isEqual(witness.defaults) == true) else {
                throw EraseAllServiceError.invalidAuthority
            }
            phase = .abandoned
        } catch {
            phase = .closeUncertain
            throw error
        }
    }
#endif

    fileprivate init(binding: EraseRetirementBindingV1, intent: EraseIntentV1,
        factory: StoreGenerationFactory, authority: StoreRestoreGenerationAuthority,
        auxiliary: EraseAuxiliaryAuthority, intentStore: EraseIntentStore,
        observation: EraseIntentStore.RetirementObservation,
        manifestScope: EraseCurrentManifestScopeV1, targetReader: GenerationLeaseHandleV1,
        diagnosticsStore: DiagnosticsStore, notificationControl: AppLockNotificationControlStoreV1,
        userDefaults: UserDefaults, defaultsDomainName: String, fileManager: FileManager,
        failureInjection: EraseAllFailureInjection?, reservation: AppAccessGateV1.EraseAdoptionToken?,
        completion: (@MainActor (CompletedEraseReceiptV1) -> Void)?) {
        self.binding = binding; self.intent = intent; self.factory = factory
        self.authority = authority; self.auxiliary = auxiliary; self.intentStore = intentStore
        self.observation = observation; self.manifestScope = manifestScope; self.targetReader = targetReader
        self.diagnosticsStore = diagnosticsStore; self.notificationControl = notificationControl
        self.userDefaults = userDefaults; self.defaultsDomainName = defaultsDomainName
        self.fileManager = fileManager; self.failureInjection = failureInjection; self.reservation = reservation
        self.completion = completion
    }

    /// Register the actual consuming transfer before a subsequent check can
    /// throw. A failed constructor leaves this exact EX retained for retry.
    func retainTransferredExclusion(_ value: EraseRetirementExclusionV1,
        drain: EraseSessionDrainWitnessV1) throws -> EraseSessionRetirementV1 {
        guard drain.binding == binding, phase == .prepared,
              exclusion == nil || exclusion === value else { throw EraseAllServiceError.invalidAuthority }
        exclusion = value
        if let retirement { return retirement }
        let actual = try EraseSessionRetirementV1(exclusion: value, drain: drain,
            intent: intent, intentStore: intentStore, observation: observation)
        retirement = actual
        return actual
    }

#if DEBUG
    private func defaultsSnapshotForPostRetiredFault() throws -> NSDictionary? {
        guard let domain = userDefaults.persistentDomain(forName: defaultsDomainName) else {
            return nil
        }
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: domain, format: .binary, options: 0)
        guard let copy = try PropertyListSerialization.propertyList(
            from: bytes, options: [], format: nil) as? NSDictionary else {
            throw EraseAllServiceError.invalidAuthority
        }
        return copy
    }

    private func capturePostRetiredFaultWitness(
        proof: ErasedRegistryRetirementProofV1
    ) throws -> ErasePostRetiredFaultWitnessV1 {
        guard phase == .prepared, postRetiredWitness == nil,
              !interruptedPostRetiredFault,
              intent.phase == .sessionActivated, reservation != nil,
              let retirement, retirement.ownsProof(proof) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try proof.requireCurrentGenerationValidation()
        try intentStore.requireRetirementObservation(observation)
        try auxiliary.verifyTargets()
        let generation = try authority.snapshotPostRetiredEraseGenerations(
            newID: intent.newGenerationID, deleting: intent.generationIDsToDelete)
        let auxiliarySnapshot = try auxiliary.postRetiredSnapshot()
        let intentSnapshot = try intentStore.postRetiredSnapshot(observation: observation)
        guard let originalPostEffectNotification else {
            throw EraseAllServiceError.invalidAuthority
        }
        let notification = try notificationControl.postRetiredSnapshot(
            subject: binding.subject)
        guard notification == originalPostEffectNotification else {
            throw EraseAllServiceError.invalidAuthority
        }
        let defaults = try defaultsSnapshotForPostRetiredFault()
        try proof.requireCurrentGenerationValidation()
        try intentStore.requireRetirementObservation(observation)
        return ErasePostRetiredFaultWitnessV1(
            proof: proof, generation: generation,
            auxiliary: auxiliarySnapshot, intent: intentSnapshot,
            notification: notification, defaults: defaults)
    }

    private func requirePostRetiredFaultWitness(
        _ witness: ErasePostRetiredFaultWitnessV1,
        operationsMustMatch: Bool
    ) throws {
        guard postRetiredWitness === witness, proof === witness.proof,
              let retirement, retirement.ownsProof(witness.proof) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let generation = try authority.snapshotPostRetiredEraseGenerations(
            newID: intent.newGenerationID, deleting: intent.generationIDsToDelete)
        let auxiliarySnapshot = try auxiliary.postRetiredSnapshot()
        let intentSnapshot = try intentStore.postRetiredSnapshot(observation: observation)
        let notification = try notificationControl.postRetiredSnapshot(
            subject: binding.subject)
        let defaults = try defaultsSnapshotForPostRetiredFault()
        guard generation == witness.generation,
              auxiliarySnapshot.supportNames == witness.auxiliary.supportNames,
              auxiliarySnapshot.roots == witness.auxiliary.roots,
              (!operationsMustMatch || auxiliarySnapshot.operationsBeforeRelease
                  == witness.auxiliary.operationsBeforeRelease),
              intentSnapshot == witness.intent,
              notification == witness.notification,
              ((defaults == nil && witness.defaults == nil)
                  || defaults?.isEqual(witness.defaults) == true) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
#endif

    private func inject(_ point: EraseAllFailurePoint) throws {
        if failureInjection?.consume(point) == true {
#if DEBUG
            switch point {
            case .afterSessionRetirementBeforeCleanup:
                interruptedPostRetiredFault = true
            case .afterCleanup, .beforeCleanupPhaseWrite, .afterCleanupPhaseWrite, .beforeJournalRemoval:
                interruptedLateFault = point
            default: break
            }
#endif
            throw EraseAllServiceError.injectedFailure
        }
    }

#if DEBUG
    func postRetiredOperationsDigestForTesting() throws -> String {
        guard interruptedPostRetiredFault,
              let digest = postRetiredWitness?.auxiliary.operationsBeforeRelease else {
            throw EraseAllServiceError.invalidAuthority
        }
        return digest
    }

    func requireInterruptedPostRetiredFaultForAbandonmentForTesting(
        subject: EraseAllOperationSubjectV1,
        reservation expectedReservation: AppAccessGateV1.EraseAdoptionToken,
        registry: GenerationLeaseRegistryV1
    ) throws {
        guard !running, phase == .prepared,
              interruptedPostRetiredFault,
              let witness = postRetiredWitness,
              let proof, proof === witness.proof,
              let retirement, retirement.ownsProof(proof),
              binding.subject == subject,
              reservation == expectedReservation,
              expectedReservation.subject == subject,
              receipt == nil else { throw EraseAllServiceError.invalidAuthority }
        try proof.requireReadyForPreDeletionAbandonmentForTesting(registry: registry)
        try requirePostRetiredFaultWitness(witness, operationsMustMatch: true)
    }

    func abandonInterruptedPostRetiredFaultForTesting(
        subject: EraseAllOperationSubjectV1,
        reservation expectedReservation: AppAccessGateV1.EraseAdoptionToken,
        registry: GenerationLeaseRegistryV1
    ) throws {
        guard phase == .prepared, interruptedPostRetiredFault,
              let witness = postRetiredWitness,
              let proof, proof === witness.proof,
              binding.subject == subject,
              reservation == expectedReservation,
              receipt == nil else { throw EraseAllServiceError.invalidAuthority }
        phase = .abandonmentPending
        do {
            try proof.abandonBeforeDeletionForTesting(registry: registry)
            // The original callback closure remains retained and inert so
            // dropping captures cannot masquerade as a checked alias drain.
            try requirePostRetiredFaultWitness(
                witness, operationsMustMatch: false)
            phase = .abandoned
        } catch {
            phase = .closeUncertain
            throw error
        }
    }

    /// Poison callback and receipt before releasing the genuine EX. A failed
    /// close remains terminal and keeps every actual owner reachable.
    func requireInterruptedLateFaultForAbandonmentForTesting(_ expected: EraseAllFailurePoint,
        subject: EraseAllOperationSubjectV1,
        reservation expectedReservation: AppAccessGateV1.EraseAdoptionToken) throws {
        guard !running, interruptedLateFault == expected,
              binding.subject == subject, reservation == expectedReservation,
              let retirement, let proof, retirement.ownsProof(proof) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let expectedPhase: Phase
        switch expected {
        case .afterCleanup, .beforeCleanupPhaseWrite: expectedPhase = .diagnosticsVerified
        case .afterCleanupPhaseWrite: expectedPhase = .phaseWritten
        case .beforeJournalRemoval: expectedPhase = .preparationRemoved
        default: throw EraseAllServiceError.invalidAuthority
        }
        guard phase == expectedPhase else { throw EraseAllServiceError.invalidAuthority }
        try proof.requireReadyForLateAbandonmentForTesting()
    }

    func abandonInterruptedLateFaultForTesting(_ expected: EraseAllFailurePoint,
        subject: EraseAllOperationSubjectV1,
        reservation expectedReservation: AppAccessGateV1.EraseAdoptionToken) throws {
        try requireInterruptedLateFaultForAbandonmentForTesting(expected,
            subject: subject, reservation: expectedReservation)
        guard let proof else { throw EraseAllServiceError.invalidAuthority }
        phase = .abandonmentPending
        completion = nil
        receipt = nil
        do {
            try proof.abandonAfterNamespaceRemovalForTesting()
            phase = .abandoned
        } catch {
            phase = .closeUncertain
            throw error
        }
    }
#endif

    /// Returns false only for still-live observed model aliases. No timer,
    /// yield count, cancellation or deinit is accepted as successful drain.
    func advance() async throws -> Bool {
        guard !running, let retirement else { throw EraseAllServiceError.invalidAuthority }
#if DEBUG
        guard phase != .abandonmentPending, phase != .abandoned,
              phase != .closeUncertain,
              !pristineColdExitRequested else {
            throw EraseAllServiceError.invalidAuthority
        }
#endif
        if phase == .released { return true }
        running = true
        defer { running = false }
        if proof == nil {
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=target-validation-enter")
#endif
            guard let actual = try await retirement.validateAndAdvance(factory: factory,
                authority: authority, targetReader: targetReader, manifestScope: manifestScope) else { return false }
            proof = actual
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=target-validation-complete")
#endif
        }
        guard let proof, retirement.ownsProof(proof) else { throw EraseAllServiceError.invalidAuthority }
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=retirement-proof-complete")
#endif
        let completed = intent.advancing(to: .cleanupComplete)
        if phase == .prepared {
            // The original protected semantic read and actual lease retirement
            // are complete. Bind all unchanged bytes before the fault escapes.
#if DEBUG
            if failureInjection?.isPending(.afterSessionRetirementBeforeCleanup) == true {
                do {
                    postRetiredWitness = try capturePostRetiredFaultWitness(proof: proof)
                } catch {
                    phase = .closeUncertain
                    throw error
                }
            }
#endif
            try inject(.afterSessionRetirementBeforeCleanup)
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=current-pointer-enter")
#endif
            guard try factory.currentGenerationIDForEraseRetirement(authority: authority,
                retirement: proof, manifestScope: manifestScope) == intent.newGenerationID else {
                throw EraseAllServiceError.invalidAuthority
            }
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=current-pointer-complete")
#endif
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=retired-pointer-enter")
#endif
            let retired = try factory.retiredGenerationIDsForEraseRetirement(
                authority: authority, retirement: proof,
                expected: intent.generationIDsToDelete, currentID: intent.newGenerationID)
            guard retired == intent.generationIDsToDelete || retired.isEmpty else {
                throw EraseAllServiceError.invalidAuthority
            }
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=retired-pointer-complete")
#endif
            let allowed = Set((intent.generationIDsToDelete + [intent.newGenerationID]).map { $0.uuidString.lowercased() })
            let actual = Set(try authority.installedGenerationNames())
            guard actual.isSubset(of: allowed), actual.contains(intent.newGenerationID.uuidString.lowercased()) else {
                throw EraseAllServiceError.invalidAuthority
            }
            // The retired pointer can be empty only after the original writer
            // proved all frozen old generation names absent.  A same-byte
            // replacement cannot make an earlier generation deletion vanish.
            if retired.isEmpty {
                guard actual == [intent.newGenerationID.uuidString.lowercased()] else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=installed-names-complete")
#endif
            for id in intent.generationIDsToDelete {
                if try authority.installedGenerationNames().contains(id.uuidString.lowercased()) {
                    try authority.removeInstalledGenerationForEraseRetirement(id: id,
                        keeping: intent.newGenerationID, retirement: proof)
                }
            }
            guard Set(try authority.installedGenerationNames()) == [intent.newGenerationID.uuidString.lowercased()] else {
                throw EraseAllServiceError.invalidAuthority
            }
#if DEBUG
            if let hook = afterOldGenerationDeletionBeforeRetiredPointerClearForTesting {
                // Clear before invoking it: a simulated interruption cannot
                // run the test mutation a second time on the retained retry.
                afterOldGenerationDeletionBeforeRetiredPointerClearForTesting = nil
                try hook()
            }
#endif
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=generation-removal-complete")
#endif
            try authority.clearRetiredGenerationsForEraseRetirement(
                expected: intent.generationIDsToDelete,
                currentID: intent.newGenerationID, retirement: proof)
            guard try factory.retiredGenerationIDsForEraseRetirement(
                authority: authority, retirement: proof,
                expected: intent.generationIDsToDelete, currentID: intent.newGenerationID).isEmpty else {
                throw EraseAllServiceError.invalidAuthority
            }
            phase = .generationsRemoved
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=retired-clear-complete")
#endif
        }
        if phase == .generationsRemoved {
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=manifest-preserve-enter")
#endif
            try factory.preserveEraseManifest(scope: manifestScope, retirement: proof)
            phase = .manifestPreserved
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=manifest-preserve-complete")
#endif
        }
        let ratingStore = PreferencesAdapterV1(defaults: userDefaults)
        if phase == .manifestPreserved {
            try AppLockNotificationTransactionFenceV1.perform {
                try notificationControl.verifyNotificationStorage()
                guard try notificationControl.loadControl() == nil,
                      try notificationControl.loadPrivateNotificationMapping() == nil else {
                    throw EraseAllServiceError.recoveryRequired
                }
#if DEBUG
                print("C46_ERASE_ADVANCE_V1 stage=namespace-begin-enter")
#endif
                try proof.beginFrozenTargetRemoval(using: auxiliary)
                phase = .removingNamespace
            }
        }
        if phase == .removingNamespace {
            try AppLockNotificationTransactionFenceV1.perform {
#if DEBUG
                print("C46_ERASE_ADVANCE_V1 stage=namespace-remove-enter")
#endif
                try proof.removeFrozenTargets(using: auxiliary)
            }
            phase = .namespaceRemoved
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=namespace-remove-complete")
#endif
        }
        if phase == .namespaceRemoved {
            try proof.requireNamespaceAbsent()
            try AppLockNotificationTransactionFenceV1.perform {
                try ratingStore.preparePreferencesForCompletedErase(operationID: intent.eraseID,
                    persistentDomainName: defaultsDomainName)
            }
            phase = .preferencesPrepared
        }
        if phase == .preferencesPrepared {
            try proof.requireNamespaceAbsent()
            let rating = try RatingEligibilityCoordinatorV1(store: ratingStore,
                nativeRequest: AppStoreRatingRequestAdapterV1(), clock: SystemApplicationClock())
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=rating-enter")
#endif
            let result = try await rating.applyCompletedErase(eraseOperationID: intent.eraseID, erasedAt: Date())
            guard case .current(let ledger) = try await ratingStore.load(), ledger.attempts.isEmpty,
                  case .erasedCooldown(_, let suppressUntil) = ledger.origin,
                  suppressUntil == result.suppressUntil, result.receipt.operationID == intent.eraseID,
                  result.receipt.resultingRevision == ledger.revision,
                  result.receipt.stateSHA256 == ledger.stateSHA256 else { throw EraseAllServiceError.invalidAuthority }
            let replacement = DiagnosticsStore(applicationSupportURL: binding.subject.applicationSupportURL,
                fileManager: fileManager)
            try await replacement.resetOperationalSupport()
            let zero = try await replacement.operationalSupportSnapshot()
            guard zero.schemaVersion == DeviceOperationalSupportStoreSchemaV2.version,
                  zero.counters == .zero, zero.health.failures.isEmpty else { throw EraseAllServiceError.invalidAuthority }
            let feedback = try await replacement.supportFeedbackDraftSnapshot()
            guard feedback.state == .empty, feedback.draft == nil, !feedback.safeCopyAvailable else {
                throw EraseAllServiceError.invalidAuthority
            }
            let bytes = try await replacement.canonicalOperationalSupportEnvelopeDataV3()
            await diagnosticsStore.acceptDescriptorErasedZero()
            guard await diagnosticsStore.isExactlyZero() else { throw EraseAllServiceError.invalidAuthority }
            try proof.requireNamespaceAbsent()
            try auxiliary.verifyTargetsRemovedExceptDiagnostics()
            try auxiliary.verifyDiagnostics(expectedData: bytes)
            diagnosticsZero = bytes
            phase = .diagnosticsVerified
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=diagnostics-complete")
#endif
            if intent.phase != .cleanupComplete { try inject(.afterCleanup) }
        }
        if phase == .diagnosticsVerified {
            if intent.phase != .cleanupComplete {
                try inject(.beforeCleanupPhaseWrite)
                try intentStore.replaceAfterRegistryRetirement(expected: intent,
                    with: completed, retirement: proof)
            }
            phase = .phaseWritten
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=phase-write-complete")
#endif
            if intent.phase != .cleanupComplete { try inject(.afterCleanupPhaseWrite) }
        }
        if phase == .phaseWritten {
            try proof.requireNamespaceAbsent()
            guard let diagnosticsZero else { throw EraseAllServiceError.invalidAuthority }
            try auxiliary.verifyTargetsRemovedExceptDiagnostics()
            try auxiliary.verifyDiagnostics(expectedData: diagnosticsZero)
            if completed.schemaVersion == 2 {
                try intentStore.removePreparationAfterRegistryRetirement(expectedIntent: completed, retirement: proof)
            }
            phase = .preparationRemoved
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=preparation-remove-complete")
#endif
        }
        if phase == .preparationRemoved {
            // Retain the real same-process completion authority before removing
            // its durable intent. Publication still requires the released proof.
            if let reservation {
                guard reservation.subject == binding.subject else { throw EraseAllServiceError.invalidAuthority }
                receipt = CompletedEraseReceiptV1(subject: binding.subject, reservation: reservation)
            }
            try inject(.beforeJournalRemoval)
            try intentStore.removeAfterRegistryRetirement(expected: completed, retirement: proof)
            phase = .intentRemoved
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=intent-remove-complete")
#endif
        }
        if phase == .intentRemoved {
            try auxiliary.removeEraseRootIfEmpty()
            try auxiliary.verifyTargetsRemovedExceptDiagnostics()
            try proof.requireNamespaceAbsent()
#if DEBUG
            // The cold Router has not yet performed ordinary ready startup.
            // Observe only after the existing checked cleanup predicates pass.
            coldCleanupProofObservationForTesting?("cleanup.pre-ready-roots-absent")
#endif
            phase = .eraseRootRemoved
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=erase-root-remove-complete")
#endif
        }
        if phase == .eraseRootRemoved {
            try proof.releaseAfterCompletion()
            phase = .released
#if DEBUG
        print("C46_ERASE_ADVANCE_V1 stage=release-complete")
#endif
            // Clear before the synchronous call, so reentry cannot repeat it.
            if let receipt, let callback = completion {
                completion = nil
                callback(receipt)
            } else { completion = nil }
        }
        return phase == .released
    }

    func completedReceipt() throws -> CompletedEraseReceiptV1? {
        guard phase == .released else { throw EraseAllServiceError.invalidAuthority }
        return receipt
    }
}

private extension EraseAllService {
    /// Complete callback-bearing cleanup work before the Router transfers EX
    /// and returns from every original service/lifecycle frame.
    func prepareCleanupForRetirement(_ value: EraseIntentV1, session: StoreGenerationSession,
        authority: StoreRestoreGenerationAuthority, auxiliary: EraseAuxiliaryAuthority,
        diagnosticsStore: DiagnosticsStore, intentStore: EraseIntentStore,
        binding: EraseRetirementBindingV1, inventory: EraseReaderRetirementInventoryV1,
        reservation: AppAccessGateV1.EraseAdoptionToken?) async throws -> EraseCleanupAfterRetirementV1 {
        guard value.eraseID == binding.subject.eraseID,
              value.newGenerationID == binding.subject.newGenerationID,
              value.phase == .sessionActivated || value.phase == .cleanupComplete,
              reservation == nil || reservation?.subject == binding.subject else {
            throw EraseAllServiceError.invalidAuthority
        }
        try Self.requireEmptyErasePublishedGraph(context: session.modelContext,
            generationID: session.generationID, identity: session.workspaceIdentity,
            activated: value.advancing(to: .sessionActivated))
        if value.phase != .cleanupComplete { try inject(.beforeCleanup) }
        let preferences = PreferencesAdapterV1(defaults: userDefaults)
        let notifications = try AppLockNotificationControlStoreV1(
            applicationSupportURL: applicationSupportURL, preferences: preferences)
#if DEBUG
        var originalNotificationAfterOSReadback: ErasePostRetiredNotificationSnapshotV1?
        if let originalColdExitFrame {
            try originalColdExitFrame.retainOriginalNotificationControl(notifications)
            try await DeviceLocalNotificationOwnerV1
                .eraseForOriginalColdExitForTesting(
                    control: notifications, system: notificationSystem,
                    operationID: value.eraseID,
                    beforeBegin: {
                        try originalColdExitFrame
                            .beforeOriginalNotificationRevocation()
                    },
                    afterBegin: { revocation in
                        try originalColdExitFrame
                            .afterOriginalNotificationRevocation(revocation)
                    },
                    observedOwnedRefusal: { revocation, owned, observedOwned in
                        try originalColdExitFrame.recordOriginalNotificationRefusal(
                            revocation: revocation, owned: owned,
                            observedOwned: observedOwned,
                            subject: binding.subject)
                    },
                    afterSuccess: { revocation in
                        try originalColdExitFrame
                            .afterOriginalNotificationSuccess(revocation)
                        originalNotificationAfterOSReadback = try notifications
                            .postRetiredSnapshot(subject: binding.subject)
                    })
        } else {
            // The same source-free OS effect publishes the marker. Capture its
            // exact post-readback inode before later awaited cleanup can run.
            try await DeviceLocalNotificationOwnerV1.eraseForOriginalColdExitForTesting(
                control: notifications, system: notificationSystem,
                operationID: value.eraseID,
                beforeBegin: {}, afterBegin: { _ in },
                observedOwnedRefusal: { _, _, _ in },
                afterSuccess: { _ in
                    originalNotificationAfterOSReadback = try notifications
                        .postRetiredSnapshot(subject: binding.subject)
                })
        }
        guard let originalNotificationAfterOSReadback else {
            throw EraseAllServiceError.invalidAuthority
        }
#else
        try await DeviceLocalNotificationOwnerV1.erase(control: notifications,
            system: notificationSystem, operationID: value.eraseID)
#endif
        #if DEBUG
        try originalColdExitFrame?.beforeScratchConstruction()
        #endif
        let scratch = try ScratchDataLeaseStoreV1(applicationSupportURL: applicationSupportURL,
            fileManager: fileManager, clock: Date.init)
        #if DEBUG
        try originalColdExitFrame?.afterScratchConstruction(scratch)
        #endif
        try await scratch.eraseScratchData()
        #if DEBUG
        try originalColdExitFrame?.afterScratchErase(scratch)
        #endif
        try sceneNavigationStatePort?.eraseSceneNavigationData()
        try PortableExchangeProtectedFilePolicyV2.validate()
        let exchange = try PortableExchangeSessionStoreV2(applicationSupportURL: applicationSupportURL,
            fileManager: fileManager)
        let exchangeReceipt: PortableExchangeEraseReceiptV2
#if DEBUG
        if let originalColdExitFrame {
            let result = try await exchange.eraseForOriginalColdExitForTesting(
                operationID: value.eraseID,
                beforeLoad: {
                    try originalColdExitFrame
                        .retainAndCheckExchangeBeforeLoad(exchange)
                },
                beforePublish: { predecessor, successor in
                    try originalColdExitFrame.checkExchangeBeforePublish(
                        predecessor: predecessor, successor: successor)
                },
                afterPublish: { successor in
                    try originalColdExitFrame.checkExchangeAfterPublish(
                        successor: successor)
                })
            exchangeReceipt = result.receipt
        } else {
            exchangeReceipt = try await exchange.erase(operationID: value.eraseID)
        }
#else
        exchangeReceipt = try await exchange.erase(operationID: value.eraseID)
#endif
        try exchangeReceipt.validate()
        guard try await exchange.sessions(in: nil).isEmpty else { throw EraseAllServiceError.invalidAuthority }
        #if DEBUG
        traceErasePhase("cleanup.target-reader.enter")
        #endif
        let reader = try generationFactory.captureEraseTargetReader(session: session,
            inventory: inventory, binding: binding)
        #if DEBUG
        traceErasePhase("cleanup.target-reader.complete")
        #endif
        #if DEBUG
        traceErasePhase("cleanup.manifest.enter")
        #endif
        let scope = try generationFactory.captureEraseCurrentManifest(binding: binding, authority: authority)
        #if DEBUG
        traceErasePhase("cleanup.manifest.complete")
        #endif
        #if DEBUG
        traceErasePhase("cleanup.intent-observation.enter")
        #endif
        let observation = try intentStore.captureRetirementObservation(expected: value)
        #if DEBUG
        traceErasePhase("cleanup.intent-observation.complete")
        #endif
        let prepared = EraseCleanupAfterRetirementV1(binding: binding, intent: value, factory: generationFactory,
            authority: authority, auxiliary: auxiliary, intentStore: intentStore, observation: observation,
            manifestScope: scope, targetReader: reader, diagnosticsStore: diagnosticsStore,
            notificationControl: notifications, userDefaults: userDefaults, defaultsDomainName: defaultsDomainName,
            fileManager: fileManager, failureInjection: failureInjection, reservation: reservation,
            completion: didCompleteErase)
#if DEBUG
        try prepared.sealOriginalPostEffectNotificationForTesting(
            originalNotificationAfterOSReadback)
        if let hook = afterOldGenerationDeletionBeforeRetiredPointerClearForTesting {
            try prepared.installRetiredPointerCutHookForTesting(hook)
        }
        if let originalColdExitFrame {
            try prepared.retainOriginalColdExitFrameForTesting(originalColdExitFrame)
        }
#endif
        return prepared
    }
}

private extension EraseAllService {
    func prepareColdCleanupForRetirement(_ value: EraseIntentV1, session: StoreGenerationSession,
        authority: StoreRestoreGenerationAuthority, auxiliary: EraseAuxiliaryAuthority,
        diagnosticsStore: DiagnosticsStore, intentStore: EraseIntentStore,
        binding: EraseRetirementBindingV1, inventory: EraseReaderRetirementInventoryV1,
        reservation: AppAccessGateV1.EraseAdoptionToken?, operation: EraseColdPreparationOperationV1) async throws -> EraseCleanupAfterRetirementV1 {
        try operation.requireServiceAccess()
        guard reservation == nil else { throw EraseAllServiceError.invalidAuthority }
        guard value.eraseID == binding.subject.eraseID,
              value.newGenerationID == binding.subject.newGenerationID,
              value.phase == .sessionActivated || value.phase == .cleanupComplete,
              reservation == nil || reservation?.subject == binding.subject else {
            throw EraseAllServiceError.invalidAuthority
        }
        try Self.requireEmptyErasePublishedGraph(context: session.modelContext,
            generationID: session.generationID, identity: session.workspaceIdentity,
            activated: value.advancing(to: .sessionActivated))
        if value.phase != .cleanupComplete { try inject(.beforeCleanup) }
        let preferences = PreferencesAdapterV1(defaults: userDefaults)
        let notifications = try AppLockNotificationControlStoreV1(
            applicationSupportURL: applicationSupportURL, preferences: preferences)
        try await DeviceLocalNotificationOwnerV1.erase(control: notifications,
            system: notificationSystem, operationID: value.eraseID)
        try operation.requireServiceAccess()
        let scratch = try ScratchDataLeaseStoreV1(applicationSupportURL: applicationSupportURL,
            fileManager: fileManager, clock: Date.init)
        try await scratch.eraseScratchData()
        try operation.requireServiceAccess()
        try sceneNavigationStatePort?.eraseSceneNavigationData()
        try PortableExchangeProtectedFilePolicyV2.validate()
        let exchange = try PortableExchangeSessionStoreV2(applicationSupportURL: applicationSupportURL,
            fileManager: fileManager)
        let exchangeReceipt = try await exchange.erase(operationID: value.eraseID)
        try operation.requireServiceAccess()
        try exchangeReceipt.validate()
        guard try await exchange.sessions(in: nil).isEmpty else { throw EraseAllServiceError.invalidAuthority }
        try operation.requireServiceAccess()
        let reader = try generationFactory.captureEraseTargetReader(session: session,
            inventory: inventory, binding: binding)
        let scope = try generationFactory.captureEraseCurrentManifest(binding: binding, authority: authority)
        let observation = try intentStore.captureRetirementObservation(expected: value)
        let prepared = EraseCleanupAfterRetirementV1(binding: binding, intent: value, factory: generationFactory,
            authority: authority, auxiliary: auxiliary, intentStore: intentStore, observation: observation,
            manifestScope: scope, targetReader: reader, diagnosticsStore: diagnosticsStore,
            notificationControl: notifications, userDefaults: userDefaults, defaultsDomainName: defaultsDomainName,
            fileManager: fileManager, failureInjection: failureInjection, reservation: reservation,
            completion: nil)
#if DEBUG
        try prepared.installColdCleanupProofObservationForTesting(
            erasePhaseDiagnosticForTesting)
#endif
        return prepared
    }
}

/// Retains actual cold rollback authority, never a session or callback. Target
/// validation and fresh source-under-G validation use distinct drained cohorts.
@MainActor
final class EraseColdPreparationRollbackV1 {
    private enum Phase { case targetValidation, targetReaders, sourceRemoval, sourceReaders, controls, eraseRoot, complete }
    private var phase: Phase = .targetValidation
    private let preparation: ErasePreparationV2
    private let targetIdentity: WorkspaceReplicaIdentityV1
    private let emptyLedger: DeletionLedgerProofV2
    private let authority: StoreRestoreGenerationAuthority
    private let auxiliary: EraseAuxiliaryAuthority
    private let intentStore: EraseIntentStore
    private var validation: ErasePreparedGenerationDiscardV1?
    private var removalCompleted = false
    private var preparationRemovalStarted = false
    private var preparationRemoved = false

    fileprivate init(preparation: ErasePreparationV2, targetIdentity: WorkspaceReplicaIdentityV1,
        emptyLedger: DeletionLedgerProofV2, authority: StoreRestoreGenerationAuthority,
        auxiliary: EraseAuxiliaryAuthority, intentStore: EraseIntentStore) {
        self.preparation = preparation; self.targetIdentity = targetIdentity
        self.emptyLedger = emptyLedger; self.authority = authority
        self.auxiliary = auxiliary; self.intentStore = intentStore
    }

    func requireSourceRemoval(_ expected: ErasePreparedGenerationDiscardV1) throws {
        guard phase == .sourceReaders, validation === expected, !removalCompleted else {
            throw EraseAllServiceError.invalidAuthority
        }
        guard try intentStore.load() == nil,
              try intentStore.loadPreparation() == preparation else {
            throw EraseAllServiceError.invalidAuthority
        }
        try auxiliary.verifyTargets()
        try auxiliary.requireNoRestoreIntent()
    }

    func advance(operation: EraseColdPreparationOperationV1) async throws -> Bool {
        if phase == .complete { return true }
        if phase == .targetValidation {
            let factory = try operation.configuredFactory()
            try await operation.beginRollbackFrame()
            phase = .targetReaders
            do {
                defer { operation.endServiceFrame() }
                guard try intentStore.load() == nil,
                      try intentStore.loadPreparation() == preparation,
                      try factory.currentGenerationDeletionLedgerProof(
                        expectedPointer: preparation.oldPointer, authority: authority) == preparation.sourceLedger else {
                    throw EraseAllServiceError.invalidAuthority
                }
                validation = try factory.prepareErasePreparationDiscard(
                    expectedOldPointer: preparation.oldPointer,
                    targetGenerationID: preparation.targetGenerationID,
                    targetIdentity: targetIdentity, expectedEmptyLedger: emptyLedger,
                    authority: authority, coldOperation: operation)
            }
        }
        if phase == .targetReaders {
            try operation.disposeFailedReaders()
            try operation.restartAfterDisposedReaders()
            guard validation != nil else { phase = .targetValidation; return false }
            phase = .sourceRemoval
        }
        if phase == .sourceRemoval {
            guard let validation else { throw EraseAllServiceError.invalidAuthority }
            let factory = try operation.configuredFactory()
            try await operation.beginRollbackFrame()
            phase = .sourceReaders
            do {
                defer { operation.endServiceFrame() }
                try factory.completeColdErasePreparationDiscard(validation,
                    sourceLedger: preparation.sourceLedger, operation: operation)
                removalCompleted = true
            }
        }
        if phase == .sourceReaders {
            try operation.disposeFailedReaders()
            try operation.restartAfterDisposedReaders()
            guard removalCompleted else { phase = .sourceRemoval; return false }
            phase = .controls
        }
        if phase == .controls {
            guard try intentStore.load() == nil else { throw EraseAllServiceError.invalidAuthority }
            if !preparationRemoved {
                if let current = try intentStore.loadPreparation() {
                    guard current == preparation else { throw EraseAllServiceError.invalidAuthority }
                    preparationRemovalStarted = true
                    try intentStore.removePreparation(expected: preparation)
                } else if !preparationRemovalStarted {
                    throw EraseAllServiceError.invalidAuthority
                }
                preparationRemoved = true
            }
            let presence = try authority.presence(id: preparation.targetGenerationID)
            guard !presence.installed, !presence.staging else { throw EraseAllServiceError.invalidAuthority }
            phase = .eraseRoot
        }
        if phase == .eraseRoot {
            try auxiliary.removeEraseRootIfEmpty()
            phase = .complete
        }
        return phase == .complete
    }
}

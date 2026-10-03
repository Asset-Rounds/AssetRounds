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
        guard drain.isActuallyDrained else {
#if DEBUG
            FileHandle.standardError.write(Data(
                ("C46_ERASE_DRAIN_CENSUS_V1 " + drain.fixedDrainCensusForTesting() + "\n").utf8))
#endif
            return nil
        }
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
    private var terminalAuthorityClose: EraseGenerationAuthorityTerminalCloseReceiptV1?
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

    /// Only the retained manifest attempt and drained EX can authorize closing
    /// the generation authority before its original Restore names disappear.
    func requireTerminalAuthorityCloseAdmission() throws {
        guard phase == .manifestPreserved, terminalAuthorityClose == nil,
              let attempt = manifestAttempt,
              drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try attempt.requirePreserved(binding: binding, exclusion: exclusion,
            retirement: self)
        try exclusion.requireSupport(binding: binding)
        try exclusion.requireNoLeasesAfterDrain(proof: drain)
        try drain.requireDrained(binding: binding)
    }

    func retainTerminalAuthorityClose(_ completed: EraseGenerationAuthorityTerminalCloseReceiptV1,
        cleanup: EraseCleanupAfterRetirementV1,
        authority: StoreRestoreGenerationAuthority) throws {
        guard phase == .manifestPreserved, terminalAuthorityClose == nil,
              let attempt = manifestAttempt, drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self),
              completed.matches(proof: self, cleanup: cleanup, authority: authority),
              completed.matchesSourceOwner(proof: self, authority: authority,
                binding: binding) else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Closing the original authority has already consumed its FDs. Retain
        // that genuine result before a fresh post-close observation can fail.
        terminalAuthorityClose = completed
        try drain.registerTerminalSourceOwner(completed, retirement: self, authority: authority)
        try exclusion.requireSupport(binding: binding)
        try exclusion.requireNoLeasesAfterDrain(proof: drain)
        try drain.requireDrained(binding: binding)
    }

    /// Exact post-close source ownership only. The manifest owner performs
    /// fresh physical readbacks; this does not cache or grant a drain result.
    func requirePostCloseSourceValidationOwnership(
        attempt: EraseManifestRetirementAttemptV1,
        exclusion expectedExclusion: EraseRetirementExclusionV1,
        binding expectedBinding: EraseRetirementBindingV1,
        receipt: EraseGenerationAuthorityTerminalCloseReceiptV1,
        authority: StoreRestoreGenerationAuthority) throws {
        guard phase == .manifestPreserved || phase == .removingNamespace || phase == .namespaceRemoved,
              binding == expectedBinding, exclusion === expectedExclusion,
              terminalAuthorityClose === receipt, manifestAttempt === attempt,
              drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion, retirement: self),
              receipt.matchesSourceOwner(proof: self, authority: authority, binding: binding) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

#if DEBUG
    /// Fixed genuine-owner probes return DATA only. No test receives the
    /// authority, retained descriptor, EX or manifest attempt from this seam.
    fileprivate func postCloseSourceControlsReadbackForTesting(
        authority: StoreRestoreGenerationAuthority, pointerData: Data,
        foreignOwner: ErasedRegistryRetirementProofV1?
    ) throws -> ErasePostCloseSourceControlsReadbackV1 {
        guard phase == .manifestPreserved, let attempt = manifestAttempt,
              let receipt = terminalAuthorityClose else {
            throw EraseAllServiceError.invalidAuthority
        }
        try drain.requireDrained(binding: binding)
        _ = try attempt.requirePostCloseSourceControls(binding: binding,
            exclusion: exclusion, retirement: self, receipt: receipt,
            authority: authority, expectedPointerData: pointerData)
        let closedReaderRefused: Bool
        print("C46_ERASE_POST_CLOSE_PROBE_V1 stage=closed-reader-refusal-enter")
        do {
            _ = try authority.readPointerForEraseRetirement(name: "current.json",
                expectedData: pointerData, binding: binding, exclusion: exclusion)
            closedReaderRefused = false
        } catch StoreGenerationFailure.dataPointerInvalid {
            closedReaderRefused = true
        }
        print("C46_ERASE_POST_CLOSE_PROBE_V1 stage=closed-reader-refusal-complete")
        var foreignReceiptRefused: Bool?, foreignBindingRefused: Bool?
        if let foreignOwner {
            guard foreignOwner !== self, foreignOwner.binding != binding,
                  let foreignReceipt = foreignOwner.terminalAuthorityClose else {
                throw EraseAllServiceError.invalidAuthority
            }
            do {
                _ = try attempt.requirePostCloseSourceControls(binding: binding,
                    exclusion: exclusion, retirement: self, receipt: foreignReceipt,
                    authority: authority, expectedPointerData: pointerData)
                foreignReceiptRefused = false
            } catch StoreMigrationFailure.invalidIdentity {
                foreignReceiptRefused = true
            }
            do {
                _ = try attempt.requirePostCloseSourceControls(binding: foreignOwner.binding,
                    exclusion: exclusion, retirement: self, receipt: receipt,
                    authority: authority, expectedPointerData: pointerData)
                foreignBindingRefused = false
            } catch StoreMigrationFailure.invalidIdentity {
                foreignBindingRefused = true
            }
        }
        try drain.requireDrained(binding: binding)
        return ErasePostCloseSourceControlsReadbackV1(sameOwnerSourceValidated: true,
            closedAuthorityReaderRefused: closedReaderRefused,
            foreignReceiptRefused: foreignReceiptRefused,
            foreignBindingRefused: foreignBindingRefused)
    }
#endif

    /// The transferred original EX still owns the complete drained cohort
    /// after the generation authority closes and before namespace removal.
    /// This is the last admissible read/checked-close point for its retained
    /// Notification control descriptors.
    func requireOriginalNotificationTerminalCloseAdmission() throws {
        guard phase == .manifestPreserved,
              terminalAuthorityClose?.matches(proof: self) == true,
              let attempt = manifestAttempt,
              drain.observesManifestRetirement(attempt),
              attempt.matches(binding: binding, exclusion: exclusion,
                  retirement: self) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try exclusion.requireSupport(binding: binding)
        try exclusion.requireNoLeasesAfterDrain(proof: drain)
        try drain.requireDrained(binding: binding)
    }

    func requireManifestNamespaceRemovalAdmission(exclusion expected: EraseRetirementExclusionV1,
        attempt: EraseManifestRetirementAttemptV1) throws {
        guard expected === exclusion, phase == .manifestPreserved,
              manifestAttempt === attempt, drain.observesManifestRetirement(attempt),
              terminalAuthorityClose?.matches(proof: self) == true,
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
              terminalAuthorityClose?.matches(proof: self) == true,
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
              UInt64(support.inode) == binding.subject.applicationSupportInode,
              terminalAuthorityClose?.matches(proof: self) == true else {
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
        guard terminalAuthorityClose == nil,
              phase == .ready || phase == .readyWithOriginalManifest || phase == .manifestPreserved else {
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
    /// Receives only labels from the closed source-literal diagnostic set.
    /// Unlike the verbose phase callback, this never enables Factory output.
    var schema2ColdFixedStageForTesting: (@MainActor (String) -> Void)?
    /// Closed error-family label from the actual fresh-R forward catch.
    var schema2ColdRForwardFailureForTesting: (@MainActor (String) -> Void)?
    /// Observes the genuine retained target session and reader immediately
    /// before the cold intent phase CAS. The existing fault point follows it.
    var schema2ColdBeforeSessionPhaseCASForTesting:
        (@MainActor (StoreGenerationSession) -> Void)?
    /// First authenticated R entry: observes only the actual retained
    /// target session after checked live open, before displaced-P cleanup.
    var schema2ColdActivatedEntrySessionForTesting:
        (@MainActor (StoreGenerationSession) -> Void)?
    /// Runs only after a real rostered generation-root unlink has a checked
    /// complete survivor receipt. Throwing simulates an interruption between
    /// this owned effect and the next postorder slot.
    var schema2ColdAfterGenerationUnlinkForTesting:
        (@MainActor (UUID, Int) throws -> Void)?
    /// Fires after the retained cold owner has checked actual notification
    /// removal and OS absence, before the first rostered generation unlink.
    var schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting:
        (@MainActor () throws -> Void)?
    /// DEBUG interruption at the real reserved-temp writer, after a durable
    /// O_EXCL create or one-byte strict prefix and before its policy request.
    var schema2ColdNotificationTemporaryFaultForTesting:
        (@MainActor (EraseSchema2ColdNotificationMutationStageV1,
            EraseSchema2ColdNotificationTemporaryFaultCutV1)
            throws -> Void)?
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
    /// A foreign real completed proof is used only by fixed refusal probes.
    /// The one-shot observer sees DATA after actual terminal close/source
    /// validation; any fixture mutation is checked again by ordinary cleanup.
    var postCloseSourceForeignOwnerForTesting: ErasedRegistryRetirementProofV1?
    var afterTerminalSourceValidationForTesting:
        (@MainActor (ErasePostCloseSourceControlsReadbackV1) throws -> Void)?
    /// Captured during genuine preparation; fires once before all fresh
    /// fixed auxiliary-retirement validation, never inside an IO fence.
    var beforeOriginalAuxiliaryRetirementValidationForTesting:
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
    private(set) var eraseFixedPhaseForTesting = "before-service-entry"
    private(set) var eraseFixedPhaseHistoryForTesting: [String] = []
    private(set) var erasePreparedFailureCategoryForTesting = "none"
    private(set) var erasePreparedRollbackStateForTesting = "not-attempted"
    private enum EraseOriginalCatchBoundaryForTesting: String {
        case admission, preIntentPreparation, publishedIntentPreparation, outerC05
    }
    private(set) var eraseFirstCatchBoundaryForTesting = "none"
    private(set) var eraseFirstCatchCategoryForTesting = "none"
    private static let eraseFixedPhaseLabelsForTesting: Set<String> = [
        "cleanup.empty-ledger",
        "cleanup.final-control-removal",
        "cleanup.final-roots-verified",
        "cleanup.generations",
        "cleanup.intent-observation.complete",
        "cleanup.intent-observation.enter",
        "cleanup.manifest.complete",
        "cleanup.manifest.enter",
        "cleanup.notification-control",
        "cleanup.notification-drain",
        "cleanup.prepare.complete",
        "cleanup.prepare.enter",
        "cleanup.binding.enter",
        "cleanup.empty-graph.enter",
        "cleanup.notification.enter",
        "cleanup.notification.complete",
        "original.failure.erase.context-has-changes",
        "original.failure.erase.invalid-authority",
        "original.failure.erase.invalid-confirmation",
        "original.failure.erase.recovery-required",
        "original.failure.erase.injected-failure",
        "cleanup.notification.constructor.enter",
        "cleanup.notification.constructor.complete",
        "cleanup.notification.root-policy.enter",
        "cleanup.notification.root-policy.complete",
        "cleanup.notification.publisher.enter",
        "cleanup.notification.publisher.complete",
        "cleanup.notification.before-begin.enter",
        "cleanup.notification.before-begin.complete",
        "cleanup.notification.marker.enter",
        "cleanup.notification.marker.complete",
        "cleanup.notification.after-begin.enter",
        "cleanup.notification.after-begin.complete",
        "cleanup.notification.drain.enter",
        "cleanup.notification.drain.complete",
        "cleanup.notification.storage-before.enter",
        "cleanup.notification.storage-before.complete",
        "cleanup.notification.mapping.enter",
        "cleanup.notification.mapping.complete",
        "cleanup.notification.journal.enter",
        "cleanup.notification.journal.complete",
        "cleanup.notification.system-remove.enter",
        "cleanup.notification.system-remove.complete",
        "cleanup.notification.storage-after-remove.enter",
        "cleanup.notification.storage-after-remove.complete",
        "cleanup.notification.system-readback.enter",
        "cleanup.notification.system-readback.complete",
        "cleanup.notification.storage-after-readback.enter",
        "cleanup.notification.storage-after-readback.complete",
        "cleanup.notification.owned-settlement.enter",
        "cleanup.notification.owned-settlement.complete",
        "cleanup.notification.record-removal.enter",
        "cleanup.notification.record-removal.complete",
        "cleanup.notification.after-success.enter",
        "cleanup.notification.after-success.complete",
        "original.failure.app-access.invalid-value",
        "original.failure.app-access.invalid-transition",
        "original.failure.app-access.stale-attempt",
        "original.failure.app-access.access-denied",
        "original.failure.app-access.configuration-unknown",
        "original.failure.app-access.ingress-limit-exceeded",
        "original.failure.app-access.ingress-not-found",
        "original.failure.app-access.ingress-already-terminal",
        "original.failure.app-access.notification-reconciliation-required",
        "original.failure.app-access.effect-mismatch",
        "original.search.canonical-binding.enter",
        "original.search.checked-publication.enter",
        "original.search.checked-publication.reproved",
        "original.search.checked-publication.complete",
        "cleanup.scratch-construction.enter",
        "cleanup.original-scratch-loan.enter",
        "cleanup.original-scratch-loan.complete",
        "cleanup.scratch-erase.enter",
        "cleanup.presence",
        "cleanup.session-and-content",
        "cleanup.target-reader.complete",
        "cleanup.target-reader.enter",
        "current.frozen-generation",
        "current.installed-inventory",
        "current.pointer-and-roots",
        "current.retired-generations",
        "empty.identity-policy",
        "empty.ledger",
        "empty.open",
        "empty.policy.AccessibleDocumentEraseAllPolicyV1",
        "empty.policy.AssetLocatorEraseAllPolicyV1",
        "empty.policy.AssetServiceReliabilityEraseAllPolicyV1",
        "empty.policy.C04ShopReportProfileEraseAllPolicyV1",
        "empty.policy.C05RoundSessionEraseAllPolicyV1",
        "empty.policy.C57MyDayEraseAllPolicyV1",
        "empty.policy.ClientCapabilityEraseAllPolicyV1",
        "empty.policy.EntityIdentityResolutionEraseAllPolicyV1",
        "empty.policy.EvidenceAssuranceEraseAllPolicyV1",
        "empty.policy.EvidenceMetadataEraseAllPolicyV1",
        "empty.policy.EvidenceQualityEraseAllPolicyV1",
        "empty.policy.FastSurveyInboxEraseAllPolicyV1",
        "empty.policy.FieldDraftEraseAllPolicyV1",
        "empty.policy.FieldReferenceEraseAllPolicyV1",
        "empty.policy.InspectionReviewEraseAllPolicyV1",
        "empty.policy.LightingDayInventoryEraseAllPolicyV1",
        "empty.policy.LightingNightWorkflowEraseAllPolicyV1",
        "empty.policy.MeasurementIntegrityEraseAllPolicyV1",
        "empty.policy.PackageEvolutionEraseAllPolicyV1",
        "empty.policy.PlacementPoseEraseAllPolicyV1",
        "empty.policy.PlanEraseAllPolicyV1",
        "empty.policy.PracticeWorkspaceProvenanceEraseAllPolicyV1",
        "empty.policy.PrivacyTransformEraseAllPolicyV1",
        "empty.policy.ReinspectionExceptionEraseAllPolicyV1",
        "empty.policy.ScheduleEraseAllPolicyV1",
        "empty.policy.ServiceRequestEraseAllPolicyV1",
        "empty.policy.SurveyDefinitionEraseAllPolicyV1",
        "empty.policy.SurveySessionEraseAllPolicyV1",
        "empty.policy.WorkPacketEraseAllPolicyV1",
        "empty.rows-and-tree",
        "empty.tree",
        "entry.admit",
        "entry.auxiliary",
        "entry.auxiliary-reverify",
        "entry.current-authority",
        "entry.fresh-identity",
        "entry.frozen-pointer",
        "entry.generation-authority",
        "entry.integration-projections",
        "entry.kernel-mappings",
        "entry.lifecycle-route",
        "entry.package-lifecycle",
        "entry.retired-inventory",
        "entry.revalidate-admission",
        "entry.scene-navigation",
        "entry.source-ledger",
        "frozen.context-and-root",
        "frozen.installed-tree",
        "frozen.inventory-predicate",
        "frozen.label-inventory",
        "frozen.model-fetches",
        "frozen.summary",
        "lifecycle.current-revision",
        "lifecycle.dependencies",
        "lifecycle.query",
        "lifecycle.request",
        "lifecycle.result",
        "prepare.bind",
        "prepare.create",
        "prepare.empty-generation",
        "prepare.empty-generation.factory-returned",
        "prepare.empty-generation.original-bind-returned",
        "prepare.empty-ledger",
        "prepare.intent-store",
        "prepare.revalidate-empty",
        "prepare.validate-empty",
        "prepare.original-aux.capture.begin",
        "prepare.original-aux.capture.complete",
        "prepare.original-aux.physical.begin",
        "prepare.original-aux.physical.complete",
        "prepare.original-aux.seal.begin",
        "prepare.original-aux.seal.complete",
        "prepare.original-aux.publish.begin",
        "prepare.original-aux.publish.complete",
        "prepare.original-aux.bind.begin",
        "prepare.original-aux.bind.complete",
        "prepare.original-aux.activate.begin",
        "prepare.original-aux.activate.complete",
        "original.exclusion.acquired",
        "original.exclusion.post-router",
        "original.exclusion.post-controls",
        "original.exclusion.revalidated",
        "original.aux.capture.enter",
        "original.aux.exclusion-returned",
        "original.aux.first-guard-passed",
        "original.aux.owner-created",
        "original.aux.snapshot-captured",
        "original.normalize.current-observed",
        "original.normalize.current-effect-complete",
        "original.normalize.retired-observed",
        "original.normalize.retired-effect-complete",
        "projection.local-purge.begin",
        "projection.local-purge.end",
        "projection.private-discovery.begin",
        "projection.private-discovery.end",
        "recovery.activated-current",
        "recovery.original.frame-enter",
        "recovery.original.frame-complete",
        "recovery.original.preflight-enter",
        "recovery.original.preflight-complete",
        "recovery.original.first.owner-enter",
        "recovery.original.first.owner-held",
        "recovery.original.first.controls-enter",
        "recovery.original.first.controls-read",
        "recovery.original.first.intent-classified",
        "recovery.original.first.authority-enter",
        "recovery.original.first.authority-held",
        "recovery.original.first.aux-enter",
        "recovery.original.first.aux-owner-retained",
        "recovery.original.first.aux-captured",
        "recovery.original.first.old-enter",
        "recovery.original.first.old-valid",
        "recovery.original.first.target-enter",
        "recovery.original.first.target-valid",
        "recovery.original.first.prior-enter",
        "recovery.original.first.prior-valid",
        "recovery.original.first.namespace-enter",
        "recovery.original.first.namespace-captured",
        "recovery.original.first.aux-reproof-enter",
        "recovery.original.first.aux-reproof-complete",
        "recovery.original.first.close-enter",
        "recovery.original.first.authority-closed",
        "recovery.original.first.closed",
        "recovery.original.first.admit-enter",
        "recovery.original.first.admit-returned",
        "recovery.original.old.owner-pre-enter",
        "recovery.original.old.owner-pre-complete",
        "recovery.original.old.aux-pre-enter",
        "recovery.original.old.aux-pre-complete",
        "recovery.original.old.digest-enter",
        "recovery.original.old.digest-complete",
        "recovery.original.old.external-enter",
        "recovery.original.old.external-complete",
        "recovery.original.old.manifest-enter",
        "recovery.original.old.manifest-complete",
        "recovery.original.old.private-copy-enter",
        "recovery.original.old.private-copy-complete",
        "recovery.original.old.callback-enter",
        "recovery.original.old.validation-enter",
        "recovery.original.old.validation-complete",
        "recovery.original.old.frozen-enter",
        "recovery.original.old.frozen-complete",
        "recovery.original.old.reads-enter",
        "recovery.original.old.reads-complete",
        "recovery.original.old.callback-complete",
        "recovery.original.old.aux-post-enter",
        "recovery.original.old.aux-post-complete",
        "recovery.original.old.owner-post-enter",
        "recovery.original.old.owner-post-complete",
        "recovery.original.old.digest-post-enter",
        "recovery.original.old.digest-post-complete",
        "recovery.original.old.external-post-enter",
        "recovery.original.old.external-post-complete",
        "recovery.original.old.policy-enter",
        "recovery.original.old.policy-complete",
        "recovery.original.old.factory.owner-enter",
        "recovery.original.old.factory.owner-complete",
        "recovery.original.old.factory.files-enter",
        "recovery.original.old.factory.files-complete",
        "recovery.original.old.factory.request-enter",
        "recovery.original.old.factory.request-complete",
        "recovery.original.old.factory.scratch-enter",
        "recovery.original.old.factory.scratch-complete",
        "recovery.original.old.factory.read-enter",
        "recovery.original.old.factory.copy-enter",
        "recovery.original.old.factory.copy-complete",
        "recovery.original.old.factory.input-proofs-enter",
        "recovery.original.old.factory.input-proofs-complete",
        "recovery.original.old.factory.shm-integrity-enter",
        "recovery.original.old.factory.shm-integrity-complete",
        "recovery.original.old.factory.container-enter",
        "recovery.original.old.factory.container-complete",
        "recovery.original.old.factory.callback-enter",
        "recovery.original.old.factory.callback-complete",
        "recovery.original.old.factory.postinput-enter",
        "recovery.original.old.factory.postinput-complete",
        "recovery.original.old.factory.final-owner-enter",
        "recovery.original.old.factory.final-owner-complete",
        "recovery.original.old.factory.final-files-enter",
        "recovery.original.old.factory.final-files-complete",
        "recovery.original.old.scratch.permit-enter",
        "recovery.original.old.scratch.permit-complete",
        "recovery.original.old.scratch.ingress-enter",
        "recovery.original.old.scratch.ingress-complete",
        "recovery.original.old.scratch.store-enter",
        "recovery.original.old.scratch.store-complete",
        "recovery.original.old.scratch.lock-enter",
        "recovery.original.old.scratch.lock-complete",
        "recovery.original.old.scratch.first-cut-enter",
        "recovery.original.old.scratch.first-cut-complete",
        "recovery.original.old.scratch.lease-enter",
        "recovery.original.old.scratch.lease-complete",
        "recovery.original.old.scratch.directory-enter",
        "recovery.original.old.scratch.directory-complete",
        "recovery.original.old.scratch.metadata-enter",
        "recovery.original.old.scratch.metadata-complete",
        "recovery.original.old.scratch.callback-enter",
        "recovery.original.old.scratch.callback-returned",
        "recovery.original.old.scratch.callback-failed",
        "recovery.original.old.scratch.drain-enter",
        "recovery.original.old.scratch.drain-complete",
        "recovery.original.old.scratch.reader-close-enter",
        "recovery.original.old.scratch.reader-close-complete",
        "recovery.original.old.scratch.release-enter",
        "recovery.original.old.scratch.release-complete",
        "recovery.original.old.scratch.final-cut-enter",
        "recovery.original.old.scratch.final-cut-complete",
        "recovery.original.old.scratch.authority-close-enter",
        "recovery.original.old.scratch.authority-close-complete",
        "recovery.original.old.scratch.io-settle-enter",
        "recovery.original.old.scratch.io-settle-complete",
        "recovery.original.old.scratch.final-ingress-enter",
        "recovery.original.old.scratch.final-ingress-complete",
        "recovery.original.old.scratch.receipt-enter",
        "recovery.original.old.scratch.receipt-complete",
        "recovery.original.old.failure.scratch-invalid-root",
        "recovery.original.old.failure.scratch-invalid-lease",
        "recovery.original.old.failure.scratch-lease-collision",
        "recovery.original.old.failure.scratch-lease-expired",
        "recovery.original.old.failure.scratch-size-limit",
        "recovery.original.old.failure.scratch-protected-data",
        "recovery.original.old.failure.scratch-capacity",
        "recovery.original.old.failure.generation-pointer",
        "recovery.original.old.failure.generation-missing",
        "recovery.original.old.failure.registry",
        "recovery.original.old.failure.policy",
        "recovery.original.old.failure.erase",
        "recovery.original.old.failure.other",
        "recovery.admission",
        "recovery.admission-revalidation",
        "recovery.authority",
        "recovery.auxiliary",
        "recovery.cleanup-presence",
        "recovery.intent",
        "recovery.intent-contract",
        "recovery.presence.current",
        "recovery.presence.inventory",
        "recovery.presence.preexisting-retired",
        "recovery.presence.published-empty",
        "recovery.presence.transferred-prior-enter",
        "recovery.presence.retained-source",
        "recovery.retained.acquire.complete",
        "recovery.retained.acquire.enter",
        "recovery.retained.open.complete",
        "recovery.retained.open.enter",
        "recovery.retained.readback.complete",
        "recovery.retained.readback.enter",
        "recovery.retained.validate.complete",
        "recovery.retained.validate.enter",
        "recovery.schema2.store-retained",
        "recovery.schema2.manifest-open",
        "recovery.schema2.target-snapshot",
        "recovery.schema2.operations-captured",
        "recovery.schema2.late-controls-captured",
        "recovery.schema2.registry-census",
        "recovery.schema2.phase-cut",
        "recovery.schema2.source-admission",
        "recovery.schema2.old-valid",
        "recovery.schema2.target-private-valid",
        "recovery.schema2.target-live-session",
        "recovery.schema2.p-forward.enter",
        "recovery.schema2.p-forward.before-cas",
        "recovery.schema2.p-forward.cas-settled",
        "recovery.schema2.p-forward.router-proof",
        "recovery.schema2.p-forward.manifest-projected",
        "recovery.schema2.p-forward.method-complete",
        "recovery.schema2.p-forward.explicit-refusal",
        "recovery.schema2.r-forward.enter",
        "recovery.schema2.r-forward.continuation",
        "recovery.schema2.r-forward.private-reproof",
        "recovery.schema2.r-forward.final-pointer",
        "recovery.schema2.r-forward.live-open",
        "recovery.schema2.r-forward.session-bound",
        "recovery.schema2.r-forward.temp-settled",
        "recovery.schema2.r-forward.entry-complete",
        "recovery.schema2.r-forward.roster-enter",
        "recovery.schema2.r-forward.roster-published",
        "recovery.schema2.r-forward.notification-enter",
        "recovery.schema2.r-forward.notification-controls",
        "recovery.schema2.r-forward.notification-owner",
        "recovery.schema2.r-forward.notification-system",
        "recovery.schema2.r-forward.notification-drained",
        "recovery.support",
        "recovery.targets",
        "retirement.binding.complete",
        "retirement.binding.enter",
        "retirement.detach.complete",
        "retirement.detach.enter",
    ]
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

#if DEBUG
    private static func originalOldDiagnosticFailureLabel(_ error: Error) -> String {
        if let failure = error as? ScratchDataLeaseStoreFailureV1 {
            switch failure {
            case .invalidRoot: return "recovery.original.old.failure.scratch-invalid-root"
            case .invalidLease: return "recovery.original.old.failure.scratch-invalid-lease"
            case .leaseCollision: return "recovery.original.old.failure.scratch-lease-collision"
            case .leaseExpired: return "recovery.original.old.failure.scratch-lease-expired"
            case .sizeLimitExceeded: return "recovery.original.old.failure.scratch-size-limit"
            case .protectedDataUnavailable: return "recovery.original.old.failure.scratch-protected-data"
            case .insufficientCapacity: return "recovery.original.old.failure.scratch-capacity"
            }
        }
        if let failure = error as? StoreGenerationFailure {
            switch failure {
            case .dataPointerInvalid: return "recovery.original.old.failure.generation-pointer"
            case .dataGenerationMissing: return "recovery.original.old.failure.generation-missing"
            }
        }
        if error is EraseAllServiceError { return "recovery.original.old.failure.erase" }
        return "recovery.original.old.failure.other"
    }
#endif

    private func traceErasePhase(_ phase: String) {
#if DEBUG
        // Only source-literal labels can reach the test; forwarded Factory
        // diagnostics and interpolated values never become output.
        if Self.eraseFixedPhaseLabelsForTesting.contains(phase) {
            eraseFixedPhaseForTesting = phase
            schema2ColdFixedStageForTesting?(phase)
            if !phase.hasPrefix("empty.policy.") {
                eraseFixedPhaseHistoryForTesting.append(phase)
                if eraseFixedPhaseHistoryForTesting.count > 32 {
                    eraseFixedPhaseHistoryForTesting.removeFirst()
                }
            }
        }
        guard let diagnostic = erasePhaseDiagnosticForTesting else { return }
        eraseDiagnosticPhase = phase
        diagnostic(phase)
#endif
    }

#if DEBUG
    private func reportSchema2ColdPForwardFailure(_ error: Error) {
        let category: String
        if error is GenerationLeaseRegistryFailureV1 {
            category = "registry"
        } else if error is StoreMigrationFailure {
            category = "migration"
        } else if error is ProtectedFilePolicyError {
            category = "policy"
        } else if error is StoreGenerationFailure {
            category = "generation"
        } else if error is EraseAllServiceError {
            category = "erase"
        } else {
            category = "other"
        }
        print("V23_C05_P_FORWARD_DIAG_V1 stage=\(eraseFixedPhaseForTesting) family=\(category)")
    }

    private func reportSchema2ColdRForwardFailure(_ error: Error) {
        let category: String
        if error is GenerationLeaseRegistryFailureV1 {
            category = "registry"
        } else if error is StoreMigrationFailure {
            category = "migration"
        } else if error is ProtectedFilePolicyError {
            category = "policy"
        } else if error is StoreGenerationFailure {
            category = "generation"
        } else if error is EraseAllServiceError {
            category = "erase"
        } else {
            category = "other"
        }
        schema2ColdRForwardFailureForTesting?(category)
    }
#endif

#if DEBUG
    private func recordOriginalCatchForTesting(
        _ error: Error, boundary: EraseOriginalCatchBoundaryForTesting
    ) {
        guard eraseFirstCatchBoundaryForTesting == "none" else { return }
        eraseFirstCatchBoundaryForTesting = boundary.rawValue
        switch error {
        case AppAccessContractFailureV1.staleAttempt:
            eraseFirstCatchCategoryForTesting = "app-access-stale"
        case EraseAllServiceError.invalidAuthority:
            eraseFirstCatchCategoryForTesting = "erase-invalid-authority"
        case EraseAllServiceError.recoveryRequired:
            eraseFirstCatchCategoryForTesting = "erase-recovery-required"
        case EraseAllServiceError.injectedFailure:
            eraseFirstCatchCategoryForTesting = "erase-injected"
        case is DeletionLedgerFailureV2:
            eraseFirstCatchCategoryForTesting = "deletion-ledger"
        case is StoreGenerationFailure:
            eraseFirstCatchCategoryForTesting = "store-generation"
        default:
            eraseFirstCatchCategoryForTesting = "other"
        }
    }
#endif

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

#if DEBUG
    private enum OriginalScratchLoanDiagnosticBoundary: String {
        case routerCall = "router-call"
        case receiptSettlement = "receipt-settlement"
        case debugAfterScratchFrame = "debug-after-scratch-frame"
    }

    /// Diagnostic-only classification; never formats an error value or payload.
    private func originalScratchLoanDiagnosticError(
        _ error: Error
    ) -> (type: String, category: String) {
        if let failure = error as? GenerationLeaseRegistryFailureV1 {
            let category: String
            switch failure {
            case .invalidContract: category = "invalid-contract"
            case .invalidPath: category = "invalid-path"
            case .invalidIdentity: category = "invalid-identity"
            case .corruptRegistry: category = "corrupt-registry"
            case .registryLimitExceeded: category = "registry-limit-exceeded"
            case .duplicateLease: category = "duplicate-lease"
            case .leaseNotActive: category = "lease-not-active"
            case .wrongLeaseRole: category = "wrong-lease-role"
            case .staleGeneration: category = "stale-generation"
            case .uncertainOwner: category = "uncertain-owner"
            case .protectedDataUnavailable: category = "protected-data-unavailable"
            }
            return ("GenerationLeaseRegistryFailureV1", category)
        }
        if let failure = error as? EraseIntentStoreError {
            let category: String
            switch failure {
            case .retirementPolicyEffectUnavailable: category = "retirement-policy-effect-unavailable"
            case .invalidAuthority: category = "invalid-authority"
            case .invalidIntent: category = "invalid-intent"
            case .invalidPreparation: category = "invalid-preparation"
            case .intentAlreadyExists: category = "intent-already-exists"
            case .intentMissing: category = "intent-missing"
            case .intentMismatch: category = "intent-mismatch"
            case .preparationAlreadyExists: category = "preparation-already-exists"
            case .preparationMissing: category = "preparation-missing"
            case .preparationMismatch: category = "preparation-mismatch"
            case .writeFailed: category = "write-failed"
            case .cleanupFailed: category = "cleanup-failed"
            }
            return ("EraseIntentStoreError", category)
        }
        if let failure = error as? ScratchDataLeaseStoreFailureV1 {
            let category: String
            switch failure {
            case .invalidRoot: category = "invalid-root"
            case .invalidLease: category = "invalid-lease"
            case .leaseCollision: category = "lease-collision"
            case .leaseExpired: category = "lease-expired"
            case .sizeLimitExceeded: category = "size-limit-exceeded"
            case .protectedDataUnavailable: category = "protected-data-unavailable"
            case .insufficientCapacity: category = "insufficient-capacity"
            }
            return ("ScratchDataLeaseStoreFailureV1", category)
        }
        if let failure = error as? AppAccessContractFailureV1 {
            let category: String
            switch failure {
            case .invalidValue: category = "invalid-value"
            case .invalidTransition: category = "invalid-transition"
            case .staleAttempt: category = "stale-attempt"
            case .accessDenied: category = "access-denied"
            case .configurationUnknown: category = "configuration-unknown"
            case .ingressLimitExceeded: category = "ingress-limit-exceeded"
            case .ingressNotFound: category = "ingress-not-found"
            case .ingressAlreadyTerminal: category = "ingress-already-terminal"
            case .notificationReconciliationRequired: category = "notification-reconciliation-required"
            case .effectMismatch: category = "effect-mismatch"
            }
            return ("AppAccessContractFailureV1", category)
        }
        if let failure = error as? EraseAllServiceError {
            let category: String
            switch failure {
            case .contextHasChanges: category = "context-has-changes"
            case .invalidAuthority: category = "invalid-authority"
            case .invalidConfirmation: category = "invalid-confirmation"
            case .recoveryRequired: category = "recovery-required"
            case .injectedFailure: category = "injected-failure"
            }
            return ("EraseAllServiceError", category)
        }
        if let failure = error as? ProtectedFilePolicyError {
            let category: String
            switch failure {
            case .invalidURL: category = "invalid-url"
            case .invalidRelativePath: category = "invalid-relative-path"
            case .missing: category = "missing"
            case .symbolicLink: category = "symbolic-link"
            case .invalidType: category = "invalid-type"
            case .hardLink: category = "hard-link"
            case .identityChanged: category = "identity-changed"
            case .attributeWriteFailed: category = "attribute-write-failed"
            case .resourceValueMismatch: category = "resource-value-mismatch"
            case .protectedDataUnavailable: category = "protected-data-unavailable"
            }
            return ("ProtectedFilePolicyError", category)
        }
        if let failure = error as? StoreGenerationFailure {
            let category: String
            switch failure {
            case .dataPointerInvalid: category = "data-pointer-invalid"
            case .dataGenerationMissing: category = "data-generation-missing"
            }
            return ("StoreGenerationFailure", category)
        }
        if let failure = error as? StoreMigrationFailure {
            let category: String
            switch failure {
            case .invalidContract: category = "invalid-contract"
            case .invalidPhaseTransition: category = "invalid-phase-transition"
            case .invalidDigest: category = "invalid-digest"
            case .invalidIdentity: category = "invalid-identity"
            case .invalidPath: category = "invalid-path"
            case .canonicalEncodingFailed: category = "canonical-encoding-failed"
            case .canonicalDecodingFailed: category = "canonical-decoding-failed"
            case .digestMismatch: category = "digest-mismatch"
            case .injectedFault(_): category = "injected-fault"
            case .maintenanceRequired(_): category = "maintenance-required"
            }
            return ("StoreMigrationFailure", category)
        }
        let runtimeType = String(reflecting: type(of: error))
        let prefix = runtimeType.utf8.prefix(97)
        let safeType: String
        if !prefix.isEmpty, prefix.count <= 96, prefix.allSatisfy({ byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122) || byte == 46 || byte == 95
        }) {
            safeType = runtimeType
        } else {
            safeType = "unclassified"
        }
        return (safeType, "other")
    }

    private func reportOriginalScratchLoanFailure(
        _ error: Error,
        boundary: OriginalScratchLoanDiagnosticBoundary,
        operation: EraseRouterOperationV1
    ) {
        let diagnostic = originalScratchLoanDiagnosticError(error)
        let savedStep = operation.originalScratchLoanDiagnosticSavedFailureStep?.rawValue
            ?? "none"
        print("V23_ORIGINAL_SCRATCH_LOAN_DIAG_V1 boundary=\(boundary.rawValue) step=\(operation.originalScratchLoanDiagnosticStep.rawValue) saved-step=\(savedStep) type=\(diagnostic.type) category=\(diagnostic.category)")
    }
#endif

    private func traceEraseOriginalFailure(_ error: Error) {
#if DEBUG
        if let failure = error as? AppAccessContractFailureV1 {
            let label: String
            switch failure {
            case .invalidValue: label = "original.failure.app-access.invalid-value"
            case .invalidTransition: label = "original.failure.app-access.invalid-transition"
            case .staleAttempt: label = "original.failure.app-access.stale-attempt"
            case .accessDenied: label = "original.failure.app-access.access-denied"
            case .configurationUnknown: label = "original.failure.app-access.configuration-unknown"
            case .ingressLimitExceeded: label = "original.failure.app-access.ingress-limit-exceeded"
            case .ingressNotFound: label = "original.failure.app-access.ingress-not-found"
            case .ingressAlreadyTerminal: label = "original.failure.app-access.ingress-already-terminal"
            case .notificationReconciliationRequired: label = "original.failure.app-access.notification-reconciliation-required"
            case .effectMismatch: label = "original.failure.app-access.effect-mismatch"
            }
            let failedStage = eraseFixedPhaseForTesting
            traceErasePhase(label)
            print("V23_C05_ORIGINAL_APP_ACCESS_ERROR_DIAG_V1 case=\(label) stage=\(failedStage)")
        }
        if let failure = error as? EraseAllServiceError {
            let label: String
            switch failure {
            case .contextHasChanges: label = "original.failure.erase.context-has-changes"
            case .invalidAuthority: label = "original.failure.erase.invalid-authority"
            case .invalidConfirmation: label = "original.failure.erase.invalid-confirmation"
            case .recoveryRequired: label = "original.failure.erase.recovery-required"
            case .injectedFailure: label = "original.failure.erase.injected-failure"
            }
            let failedStage = eraseFixedPhaseForTesting
            traceErasePhase(label)
            print("V23_C05_ORIGINAL_ERASE_ERROR_DIAG_V1 case=\(label) stage=\(failedStage)")
        }
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
        schema2ColdFixedStageForTesting =
            service.schema2ColdFixedStageForTesting
        schema2ColdRForwardFailureForTesting =
            service.schema2ColdRForwardFailureForTesting
        schema2ColdBeforeSessionPhaseCASForTesting =
            service.schema2ColdBeforeSessionPhaseCASForTesting
        schema2ColdActivatedEntrySessionForTesting =
            service.schema2ColdActivatedEntrySessionForTesting
        schema2ColdAfterGenerationUnlinkForTesting =
            service.schema2ColdAfterGenerationUnlinkForTesting
        schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting =
            service.schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting
        schema2ColdNotificationTemporaryFaultForTesting =
            service.schema2ColdNotificationTemporaryFaultForTesting
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
        operation.originalAuxiliaryFixedStageForTesting = { [weak self] stage in
            self?.traceErasePhase(stage)
        }
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
        // A failed, fully returned OS add may retain its producer SH until
        // exact admission cleanup succeeds. Settle it before requesting EX.
        try await DeviceLocalNotificationOwnerV1.settleRetainedNotificationScheduling(
            applicationSupportURL: applicationSupportURL)
        try operation.requireLiveExecution(coordinator: coordinator)
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

        // Capture the sole coordinator-owned producer before any source read.
        // The capture also denies a new Shell from constructing a second C05
        // owner while this original Erase is between witness and marker.
        let hasOriginalC05Runner = try operation.captureOriginalC05Producer(
            coordinator: coordinator)
        var c05PendingMarkerAttempted = false
        var deferredC05AbortReceipt: AbortedEraseAdmissionReceiptV1?
        var eraseIntentPublicationAttempted = false
        var provenNoEffectAfterIntentAttempt = false
        do {
        let originalC05Snapshot:
            LocalJobStoreV1.OriginalEraseNoRepairSnapshotV1?
        if hasOriginalC05Runner {
            try await operation.beginOriginalC05ObservationFence(
                coordinator: coordinator,
                expectedSupportIdentity: applicationSupportIdentity)
            originalC05Snapshot = try await operation
                .requireOriginalC05ObservationFence(coordinator: coordinator)
        } else {
            try await operation.requireAbsentOriginalC05Store(
                coordinator: coordinator,
                applicationSupportURL: applicationSupportURL,
                expectedSupportIdentity: applicationSupportIdentity)
            originalC05Snapshot = nil
        }
        let originalC05Epoch = originalC05Snapshot == nil ? nil
            : try operation.requireOriginalC05CapturedEpoch(
                coordinator: coordinator)
        let originalC05Jobs = try originalC05Snapshot?.authenticatedJobs()

        traceErasePhase("entry.generation-authority")
        let generationAuthority = try generationFactory
            .makeRestoreGenerationAuthority(
                expectedApplicationSupportIdentity: applicationSupportIdentity,
                c05SourceGenerationID: originalC05Snapshot == nil
                    ? nil : coordinator.generationID,
                c05SourceEpoch: originalC05Epoch,
                c05SourceJobs: originalC05Jobs
            )
        let originalC05TransientWitness = try originalC05Snapshot.map { _ in
            try generationAuthority.c05SourceTransientWitness(
                id: coordinator.generationID)
        }
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
            authority: generationAuthority,
            originalC05TransientWitness: originalC05TransientWitness
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
        let originalC05Drain: EraseC05JobDrainV3?
        if let originalC05Snapshot {
            guard let originalC05TransientWitness else {
                throw EraseAllServiceError.invalidAuthority
            }
            originalC05Drain = EraseC05JobDrainV3(
                eraseID: eraseID,
                sourceGenerationID: oldGenerationID,
                sourceGenerationIDsToDelete: generationIDsToDelete,
                sourceManifestSHA256: oldPointer.generationManifestSHA256,
                supportDevice: UInt64(applicationSupportIdentity.device),
                supportInode: UInt64(applicationSupportIdentity.inode),
                sourceStoreDevice: originalC05Snapshot.rootDevice,
                sourceStoreInode: originalC05Snapshot.rootInode,
                sourceEnvelopeBytes: originalC05Snapshot.envelopeBytes,
                sourceReceiptBytes: originalC05Snapshot.receiptBytes,
                sourceTransientSHA256: originalC05TransientWitness.sha256,
                phase: .pending,
                completedEnvelopeBytes: nil,
                completedReceiptBytes: nil,
                drainedTransientSHA256: nil)
            try originalC05Drain?.validate()
        } else {
            originalC05Drain = nil
        }
        let initialPreparation = ErasePreparationV2(
            oldPointer: oldPointer,
            sourceLedger: sourceLedger,
            targetGenerationID: newGenerationID,
            targetWorkspaceID: targetIdentity.workspaceID.rawValue,
            targetReplicaID: targetIdentity.replicaID.rawValue,
            targetPointer: nil,
            c05JobDrainV3: originalC05Drain
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
                originalC05Epoch: originalC05Epoch,
                originalC05Jobs: originalC05Jobs,
                originalC05TransientWitness: originalC05TransientWitness,
                lifecycleRoute: lifecycleRoute,
                lifecycleCheckpoint: lifecycleCheckpoint
            )
            if let originalC05Snapshot {
                guard try await operation.requireOriginalC05ObservationFence(
                    coordinator: coordinator) == originalC05Snapshot,
                    try generationAuthority.c05SourceTransientWitness(
                        id: oldGenerationID) == originalC05TransientWitness else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else {
                try await operation.revalidateAbsentOriginalC05Store(
                    coordinator: coordinator)
            }
        } catch {
#if DEBUG
            recordOriginalCatchForTesting(error, boundary: .admission)
#endif
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
                originalC05Epoch: originalC05Epoch,
                originalC05Jobs: originalC05Jobs,
                originalC05TransientWitness: originalC05TransientWitness,
                targetGenerationID: newGenerationID
            )
            operation.endPreparationServiceFrame()
            try operation.disposeFailedPreparationAllocations()
            try operation.requireFailedPreparationDisposed()
            if let aborted {
                if hasOriginalC05Runner {
                    deferredC05AbortReceipt = aborted
                } else {
                    deliverProvenAbortedAdmission(aborted)
                }
            }
            throw originalFailure
        }

        var createdIntent = false
        var frozenIntent: EraseIntentV1?
        var frozenPreparation = initialPreparation
        var preparationBasis = initialPreparation
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
            if originalC05Drain != nil {
                // An uncertain create may already have published the marker.
                // Never reopen producer admission after this attempt.
                c05PendingMarkerAttempted = true
            }
            try store.createPreparation(initialPreparation)
            intentStore = store
#if DEBUG
            originalFrameIntentStore = store
#endif
            if originalC05Drain != nil {
                let drainAuthority = try operation
                    .requireDurableOriginalC05PendingPreparation(
                        coordinator: coordinator, store: store,
                        expected: initialPreparation, eraseID: eraseID)
                try await operation.drainOriginalC05AfterPendingPreparation(
                    coordinator: coordinator, authority: drainAuthority)
                let emptyStore = try await operation.requireOriginalC05StoreEmpty(
                    coordinator: coordinator)
                let afterJobDrain = try generationAuthority
                    .c05SourceTransientWitness(id: oldGenerationID)
                try generationAuthority.removeEmptyOriginalC05Parents(
                    id: oldGenerationID,
                    expectedAfterJobDrain: afterJobDrain)
                let afterParentRemoval = try generationAuthority
                    .c05SourceTransientWitness(id: oldGenerationID)
                guard afterParentRemoval.directories.isEmpty,
                      afterParentRemoval.files.isEmpty else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try validateCurrentAuthority(
                    coordinator: coordinator,
                    expectedID: oldGenerationID,
                    expectedRootURL: oldGenerationRootURL,
                    retiredIDs: priorRetired,
                    authority: generationAuthority)
                guard try sourceLedgerFactory
                    .currentGenerationDeletionLedgerProof(
                        expectedPointer: oldPointer,
                        authority: generationAuthority) == sourceLedger else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let completedPreparation = try initialPreparation
                    .recordingC05JobDrain(
                        with: emptyStore,
                        absentTransientSHA256: afterParentRemoval.sha256)
                try store.replacePreparation(
                    expected: initialPreparation,
                    with: completedPreparation)
                preparationBasis = completedPreparation
                frozenPreparation = completedPreparation
                try await operation.removeOriginalC05DrainedRoot(
                    coordinator: coordinator, store: store,
                    expected: completedPreparation)
                let rootRemovedPreparation = try completedPreparation
                    .recordingC05RootRemoved()
                try store.replacePreparation(
                    expected: completedPreparation,
                    with: rootRemovedPreparation)
                preparationBasis = rootRemovedPreparation
                frozenPreparation = rootRemovedPreparation
                try await operation.retireOriginalC05EffectsAfterRootRemoved(
                    coordinator: coordinator, store: store,
                    expected: rootRemovedPreparation)
                // Cold V3 replay and the exact source-owner alias drain are
                // still required before the existing target/intent path.
                throw EraseAllServiceError.recoveryRequired
            }
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
            let boundPreparation = preparationBasis.binding(
                targetPointer: created.pointer
            )
            traceErasePhase("prepare.bind")
            try store.replacePreparation(
                expected: preparationBasis,
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
            // A checked create can leave a durable or uncertain intent even
            // when it throws. The outer no-effect producer release is no
            // longer valid after this point without a proved abort.
            eraseIntentPublicationAttempted = true
            try store.create(intent)
            createdIntent = true
            try inject(.afterPreparedWrite)

            if intent.schemaVersion == 2 {
                traceErasePhase("prepare.original-aux.capture.begin")
                _ = try await operation
                    .captureOriginalEraseAuxiliaryFirstObservation(
                        intent: intent, preparation: frozenPreparation,
                        store: store, coordinator: coordinator,
                        cachesDirectoryURL: cachesDirectoryURL,
                        temporaryDirectoryURL: temporaryDirectoryURL)
                traceErasePhase("prepare.original-aux.capture.complete")
                traceErasePhase("prepare.original-aux.physical.begin")
                _ = try operation.captureOriginalEraseAuxiliaryPhysicalRoster(
                    intent: intent, preparation: frozenPreparation,
                    store: store, coordinator: coordinator)
                traceErasePhase("prepare.original-aux.physical.complete")
                traceErasePhase("prepare.original-aux.seal.begin")
                let seal = try operation.sealOriginalEraseAuxiliaryPhysicalRoster(
                    intent: intent, preparation: frozenPreparation,
                    store: store, coordinator: coordinator)
                traceErasePhase("prepare.original-aux.seal.complete")
                traceErasePhase("prepare.original-aux.publish.begin")
                let receipt = try store.publishOriginalEraseAuxiliaryRoster(
                    seal: seal, intent: intent,
                    preparation: frozenPreparation,
                    operation: operation, coordinator: coordinator)
                traceErasePhase("prepare.original-aux.publish.complete")
                traceErasePhase("prepare.original-aux.bind.begin")
                _ = try operation.bindOriginalEraseAuxiliaryRosterPublication(
                    seal: seal, receipt: receipt,
                    intent: intent, preparation: frozenPreparation,
                    store: store, coordinator: coordinator)
                traceErasePhase("prepare.original-aux.bind.complete")
            }

            guard let intentStore else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
            traceErasePhase("prepare.original-aux.activate.begin")
            let session = try await advanceToActivatedSession(
                intent,
                authority: generationAuthority,
                intentStore: intentStore,
                originalAuxiliaryOperation: intent.schemaVersion == 2
                    ? operation : nil,
                activate: activate
            )
            traceErasePhase("prepare.original-aux.activate.complete")
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
            if intent.schemaVersion == 2 {
                try await prepareOriginalEraseCheckedSearch(
                    intent.advancing(to: .sessionActivated),
                    operation: operation, intentStore: intentStore,
                    coordinator: coordinator)
            } else {
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
            }
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
                reservation: reservation, coordinator: coordinator,
                originalAuxiliaryOperation: operation)
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
#if DEBUG
            recordOriginalCatchForTesting(error, boundary: createdIntent
                ? .publishedIntentPreparation : .preIntentPreparation)
#endif
            traceEraseOriginalFailure(error)
            if c05PendingMarkerAttempted {
                // Publication might have succeeded even when its checked
                // write threw. Any C05 drain is forward-only from here;
                // never discard the pending marker or emit no-effect abort.
                throw EraseAllServiceError.recoveryRequired
            }
            if !createdIntent {
                let originalFailure = error
#if DEBUG
                switch error {
                case AppAccessContractFailureV1.staleAttempt:
                    erasePreparedFailureCategoryForTesting = "app-access-stale"
                case EraseAllServiceError.invalidAuthority:
                    erasePreparedFailureCategoryForTesting = "erase-invalid-authority"
                case EraseAllServiceError.recoveryRequired:
                    erasePreparedFailureCategoryForTesting = "erase-recovery-required"
                case is DeletionLedgerFailureV2:
                    erasePreparedFailureCategoryForTesting = "deletion-ledger"
                case is StoreGenerationFailure:
                    erasePreparedFailureCategoryForTesting = "store-generation"
                default:
                    erasePreparedFailureCategoryForTesting = "other"
                }
                erasePreparedRollbackStateForTesting = "attempted"
#endif
                try operation.requirePreparationRollback()
#if DEBUG
                erasePreparedRollbackStateForTesting = "completed"
#endif
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
                if let aborted {
                    provenNoEffectAfterIntentAttempt = true
                    deliverProvenAbortedAdmission(aborted)
                }
                throw originalFailure
            }
            throw error
        }
        } catch {
#if DEBUG
            recordOriginalCatchForTesting(error, boundary: .outerC05)
#endif
            if !c05PendingMarkerAttempted &&
                (!eraseIntentPublicationAttempted || provenNoEffectAfterIntentAttempt) {
                try await operation.releaseOriginalC05ProducerAfterNoEffect(
                    coordinator: coordinator)
                if let deferredC05AbortReceipt {
                    deliverProvenAbortedAdmission(deferredC05AbortReceipt)
                }
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
        traceErasePhase("recovery.original.frame-enter")
        try operation.requireRecoveryExecution(coordinator: coordinator)
        try generationFactory.requireEraseReaderInventory(operation.inventory)
        try operation.beginPreparationServiceFrame(coordinator: coordinator)
        defer { operation.endPreparationServiceFrame() }
        traceErasePhase("recovery.original.frame-complete")
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
        // This is an original-operation retry, not cold startup. Classify a
        // no-intent preparation under an original-owned, no-repair reader
        // before EraseIntentStore can promote or remove a pending leaf.
        let eraseRoot = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceErase", isDirectory: true)
        func originalNamedLeafExists(_ name: String) throws -> Bool {
            var item = stat()
            let result = Darwin.lstat(
                eraseRoot.appendingPathComponent(name).path, &item)
            if result == 0 { return true }
            guard errno == ENOENT else {
                throw EraseAllServiceError.invalidAuthority
            }
            return false
        }
        var originalNoIntentPreparation: ErasePreparationV2?
        var originalNoIntentReader: EraseC05ColdPreparationJournalReaderV1?
        traceErasePhase("recovery.original.preflight-enter")
        let noIntentAtPreflight = try !originalNamedLeafExists("erase.json")
        if noIntentAtPreflight {
            // An incomplete canonical journal write has no no-effect
            // rollback authority, especially after C05's V3 PENDING edge.
            guard !(try originalNamedLeafExists(".erase.json.next")),
                  !(try originalNamedLeafExists(".preparation.json.next")) else {
                throw EraseAllServiceError.recoveryRequired
            }
            if try originalNamedLeafExists("preparation.json") {
                let reader = EraseC05ColdPreparationJournalReaderV1()
                try operation.retainOriginalC05NoRepairReader(
                    reader, coordinator: coordinator,
                    applicationSupportURL: applicationSupportURL)
                try reader.openExisting(
                    applicationSupportURL: applicationSupportURL,
                    operation: operation, coordinator: coordinator)
                let observed = try reader.readPreparation(
                    operation: operation, coordinator: coordinator).preparation
                if observed.c05JobDrainV3 != nil {
                    throw EraseAllServiceError.recoveryRequired
                }
                originalNoIntentReader = reader
                originalNoIntentPreparation = observed
            }
        }
        traceErasePhase("recovery.original.preflight-complete")
        // This is the sole pre-repair path for a schema-2 target-current
        // original recovery. It authenticates the original under its retained
        // EX/G before any ordinary store constructor or old live opening.
        var checkedOriginal = try await validateOriginalRecoverySourceAcrossAdmission(
            coordinator: coordinator, operation: operation)
        if var validatedOriginal = checkedOriginal {
            do {
                var retiredPublication:
                    StoreOriginalEraseRecoveryPreOpenOwnerV1
                        .OriginalRecoveryRetiredPublicationV1?
                if validatedOriginal.owner.retainedOriginalExclusion != nil,
                   validatedOriginal.namespace.retiredState == .prior {
                    let replacement = try validatedOriginal.authority
                        .originalRecoveryRetiredReplacementBytes(
                            intent: validatedOriginal.intent,
                            namespace: validatedOriginal.namespace)
                    let targetDigest =
                        validatedOriginal.originalTargetTreeDigest
                    let commitment = try validatedOriginal.owner
                        .publishOriginalRecoveryRetiredCommitment(
                            expected: validatedOriginal.intent,
                            namespace: validatedOriginal.namespace,
                            replacementBytes: replacement,
                            sourceAuthority: validatedOriginal.authority,
                            sourceTreeDigest:
                                validatedOriginal.originalSourceTreeDigest,
                            targetTreeDigest: targetDigest,
                            auxiliaryContinuity:
                                validatedOriginal.auxiliaryContinuity,
                            provisionalSourcePolicy:
                                validatedOriginal.provisionalSourcePolicy,
                            priorRetired: validatedOriginal.priorRetired,
                            externalSource: validatedOriginal.external,
                            externalReads: validatedOriginal.externalReads)
                    retiredPublication = try validatedOriginal.owner
                        .publishOriginalRecoveryRetiredCanonical(
                            expected: validatedOriginal.intent,
                            namespace: validatedOriginal.namespace,
                            replacementBytes: replacement,
                            commitment: commitment,
                            sourceAuthority: validatedOriginal.authority,
                            sourceTreeDigest:
                                validatedOriginal.originalSourceTreeDigest,
                            targetTreeDigest: targetDigest,
                            auxiliaryContinuity:
                                validatedOriginal.auxiliaryContinuity,
                            provisionalSourcePolicy:
                                validatedOriginal.provisionalSourcePolicy,
                            priorRetired: validatedOriginal.priorRetired,
                            externalSource: validatedOriginal.external,
                            externalReads: validatedOriginal.externalReads)
                }
                guard validatedOriginal.owner.retainedOriginalExclusion == nil
                        || validatedOriginal.namespace.retiredState == .complete
                        || retiredPublication != nil else {
                    throw EraseAllServiceError.recoveryRequired
                }
                let phaseResult = try validatedOriginal.owner.publishFirstPointerPhase(
                    expected: validatedOriginal.intent,
                    preparation: validatedOriginal.preparation,
                    sourceAuthority: validatedOriginal.authority,
                    auxiliaryContinuity:
                        validatedOriginal.auxiliaryContinuity,
                    provisionalSourcePolicy:
                        validatedOriginal.provisionalSourcePolicy,
                    priorRetired: validatedOriginal.priorRetired,
                    externalSource: validatedOriginal.external,
                    externalReads: validatedOriginal.externalReads,
                    targetTreeDigest:
                        validatedOriginal.originalTargetTreeDigest,
                    retiredPublication: retiredPublication)
                try validatedOriginal.owner.requireObservationUnchanged()
                guard phaseResult.intent == validatedOriginal.intent.advancing(to: .pointerSwitched) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                for receipt in phaseResult.sources {
                    try validatedOriginal.authority.requireOriginalRecoveryCompletedSourcePolicy(receipt)
                }
                try validatedOriginal.authority.requireOriginalRecoveryCompletedExternalPolicy(
                    phaseResult.external)
                validatedOriginal.completedPolicyPhase = phaseResult
                let postPointerProjection = try validatedOriginal
                    .auxiliaryContinuity.closeCheckedAfterFirstPointerPhase(
                        owner: validatedOriginal.owner)
                if validatedOriginal.owner.retainedOriginalExclusion != nil {
                    try operation.retainOriginalRecoveryPostPointerAuxiliaryProjection(
                        postPointerProjection, owner: validatedOriginal.owner,
                        coordinator: coordinator)
                }
                validatedOriginal.postPointerAuxiliaryProjection =
                    postPointerProjection
                try operation.releaseOriginalRecoveryAuxiliaryContinuity(
                    validatedOriginal.auxiliaryContinuity,
                    owner: validatedOriginal.owner,
                    coordinator: coordinator)
                try validatedOriginal.authority.closeCheckedForOriginalRecovery()
                try validatedOriginal.owner
                    .closeAfterFirstPointerPhaseForTargetInstallation(
                        operation: operation)
                checkedOriginal = validatedOriginal
            } catch {
                validatedOriginal.owner.poisonOnUncertainScratch()
                throw error
            }
        }
        traceErasePhase("recovery.auxiliary")
        let auxiliary = try makeAuxiliaryAuthority()
        let intentStore: EraseIntentStore
        if let checkedOriginal,
           checkedOriginal.owner.retainedOriginalExclusion != nil {
            intentStore = try operation
                .requireOriginalRecoveryProjectedAuxiliaryStore(
                    coordinator: coordinator,
                    switched: checkedOriginal.intent.advancing(
                        to: .pointerSwitched))
        } else {
            intentStore = try EraseIntentStore(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager,
                expectedApplicationSupportIdentity:
                    auxiliary.applicationSupportRootIdentity,
                originalNoRepairExistingRoot: noIntentAtPreflight
            )
        }
        traceErasePhase("recovery.intent")
        let intent: EraseIntentV1?
        let preparation: ErasePreparationV2?
        if noIntentAtPreflight {
            try intentStore.requireOriginalNoIntentControlsNoRepair(
                preparationExpected: originalNoIntentPreparation != nil)
            if let originalNoIntentReader {
                guard try originalNoIntentReader.currentOriginalPreparation(
                    operation: operation, coordinator: coordinator)
                        == originalNoIntentPreparation else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            intent = nil
            preparation = originalNoIntentPreparation
        } else {
            intent = try intentStore.load()
            preparation = try intentStore.loadPreparation()
        }
#if DEBUG
        originalFrameIntentStore = intentStore
        originalFrameExpectedIntent = intent
#endif
        guard let intent else {
            if noIntentAtPreflight {
                try intentStore.requireOriginalNoIntentControlsNoRepair(
                    preparationExpected: preparation != nil)
            }
            if let originalNoIntentReader, let preparation {
                try operation.requirePreparationRollbackWithOriginalNoRepairReader(
                    originalNoIntentReader, coordinator: coordinator,
                    expected: preparation)
            } else {
                try operation.requirePreparationRollback()
            }
            if let preparation {
                // V3 C05 effects are forward-only after PENDING publication.
                // The historical schema-2 discard must never consume them.
                guard preparation.c05JobDrainV3 == nil else {
                    throw EraseAllServiceError.recoveryRequired
                }
                let authority = try generationFactory
                    .makeRestoreGenerationAuthority(
                        expectedApplicationSupportIdentity:
                            auxiliary.applicationSupportRootIdentity
                    )
                try auxiliary.verifyTargets()
                try auxiliary.requireNoRestoreIntent()
                if let originalNoIntentReader {
                    let reproveOriginalPreparation: @MainActor () throws -> Void = {
                        try intentStore.requireOriginalNoIntentControlsNoRepair(
                            preparationExpected: true)
                        guard try originalNoIntentReader.currentOriginalPreparation(
                            operation: operation, coordinator: coordinator)
                                == preparation else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                    }
                    try reproveOriginalPreparation()
                    try discardPreparation(preparation, authority: authority,
                        reproveBeforeDestructiveEffect: reproveOriginalPreparation)
                    try reproveOriginalPreparation()
                    let held = try originalNoIntentReader.originalHeldPreparationIdentity(
                        operation: operation, coordinator: coordinator)
                    try intentStore.removePreparation(expected: preparation,
                        requiredHeldIdentity: held)
                    try operation.closeOriginalC05NoRepairReaderChecked(
                        originalNoIntentReader, coordinator: coordinator)
                } else {
                    try discardPreparation(preparation, authority: authority)
                    try intentStore.removePreparation(expected: preparation)
                }
            }
            try auxiliary.removeEraseRootIfEmpty()
            return nil
        }
        traceErasePhase("recovery.intent-contract")
        guard EraseIntentCodecV1.valid(intent) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if let checkedOriginal {
            guard intent == checkedOriginal.intent.advancing(
                to: .pointerSwitched),
                  preparation == checkedOriginal.preparation else {
                throw EraseAllServiceError.invalidAuthority
            }
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
        try requireRecoveryPresence(intent, authority: authority,
            operation: operation,
            originalRecoveryContinuation: checkedOriginal,
            coordinator: coordinator)
        let subject = makeOperationSubject(
            eraseID: intent.eraseID,
            newGenerationID: intent.newGenerationID,
            auxiliary: auxiliary
        )
        traceErasePhase("recovery.admission")
        let reservation: AppAccessGateV1.EraseAdoptionToken?
        if let checkedOriginal {
            guard checkedOriginal.subject == subject else {
                throw EraseAllServiceError.invalidAuthority
            }
            reservation = checkedOriginal.reservation
        } else {
            reservation = try await admit(subject)
        }
        traceErasePhase("recovery.admission-revalidation")
        try revalidateRecoveryAdmission(
            subject: subject,
            intent: intent,
            preparation: preparation,
            auxiliary: auxiliary,
            intentStore: intentStore,
            originalRecoveryContinuation: checkedOriginal,
            coordinator: coordinator, operation: operation
        )
        // Coordinator's typed maintenance transfer, not this local owner
        // reference, carries the source until the target writer installs.
        let retainedOriginalForward =
            checkedOriginal?.owner.retainedOriginalExclusion != nil
        checkedOriginal = nil

        let session: StoreGenerationSession
        switch intent.phase {
        case .emptyGenerationPrepared:
            session = try await advanceToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                originalAuxiliaryOperation: retainedOriginalForward
                    ? operation : nil,
                activate: activate
            )
        case .pointerSwitched:
            session = try await advancePointerPhaseToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                originalAuxiliaryOperation: retainedOriginalForward
                    ? operation : nil,
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
        if retainedOriginalForward {
            try await prepareOriginalEraseCheckedSearch(activated,
                operation: operation, intentStore: intentStore,
                coordinator: coordinator)
        }
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
            reservation: reservation, coordinator: coordinator,
            originalAuxiliaryOperation: operation)
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
                // A V3 pending/drained/root-removed preparation cannot take
                // the old no-effect rollback path on cold startup.
                guard preparation.c05JobDrainV3 == nil else {
                    throw EraseAllServiceError.recoveryRequired
                }
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

    /// A suspended private target validation resumes on the exact retained
    /// cold operation. The one-shot control/manifest/Registry constructors
    /// are never replayed, and no new snapshot is accepted as a baseline.
    func resumeSchema2ColdTargetValidation(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        let (bound, store, manifest, source, exclusion,
            registry, activity) = try operation
            .requireSchema2ColdTargetContinuation()
        guard bound.observed.intent == bound.intent,
              bound.intent.phase == .sessionActivated
                || bound.intent.phase == .cleanupComplete,
              try store.load() == bound.observed.intent,
              try store.loadPreparation()
                == bound.observed.preparation else {
            throw EraseAllServiceError.invalidAuthority
        }
        let supportIdentity = try store.schema2ColdSupportIdentity(
            operation: operation)
        try exclusion.requireHeld(expectedDevice: supportIdentity.device,
            expectedInode: supportIdentity.inode)
        try operation.requireServiceAccess()
        try manifest.requireCapturedOperationsOwners(
            bound.operationsNames, operation: operation)
        try source.withHeldTargetRoot { _ in () }
        if let registry, let activity,
           let expected = bound.registryTokens {
            guard try registry.observeEraseSchema2ColdRegistry(
                operation: operation, activity: activity)
                == expected else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireSchema2ColdPredecessorGuards(
                registry: registry)
        } else if registry != nil || activity != nil
            || bound.registryTokens != nil {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        guard try await generationFactory
            .validateOrResumeSchema2ColdTarget(
                source: source,
                snapshot: bound.generation,
                intent: bound.intent,
                temporaryDirectoryURL: temporaryDirectoryURL,
                operation: operation) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.requireServiceAccess()
        let retained = try operation.requireSchema2ColdTargetContinuation()
        guard retained.1 === store, retained.2 === manifest,
              retained.3 === source, retained.4 === exclusion,
              retained.5 === registry, retained.6 === activity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try exclusion.requireHeld(expectedDevice: supportIdentity.device,
            expectedInode: supportIdentity.inode)
        try manifest.requireCapturedOperationsOwners(
            bound.operationsNames, operation: operation)
        try source.withHeldTargetRoot { _ in () }
        guard try store.load() == bound.observed.intent,
              try store.loadPreparation()
                == bound.observed.preparation else {
            throw EraseAllServiceError.invalidAuthority
        }
        if let registry, let activity,
           let expected = bound.registryTokens {
            guard try registry.observeEraseSchema2ColdRegistry(
                operation: operation, activity: activity)
                == expected else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.requireSchema2ColdPredecessorGuards(
                registry: registry)
        }
        // Target validation alone cannot dispose of old controls or publish
        // completion. The remaining positive phase is separately required.
        throw EraseAllServiceError.recoveryRequired
    }

    // Genuine startup operation only. It retains all readers for retirement
    // and routes preparation rollback through its own drain witnesses.
    func prepareColdRetirement(
        diagnosticsStore: DiagnosticsStore, operation: EraseColdPreparationOperationV1
    ) async throws -> Bool {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        // This only resumes actual in-memory admissions, before freezing the
        // first control observation or acquiring this cold operation's EX.
        try await DeviceLocalNotificationOwnerV1.settleRetainedNotificationScheduling(
            applicationSupportURL: applicationSupportURL)
        try operation.requireServiceAccess()
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
        // Retain the exact support/control owner before the first open. This
        // classification never creates the Erase root, repairs a temporary,
        // or delegates authority to a pathname-only lstat result.
        let controls = EraseColdExistingControlObservationV1()
        try operation.retainColdControlObservation(controls)
        let observed: EraseColdExistingControlObservationV1.Snapshot
        do {
            observed = try controls.openExisting(
                applicationSupportURL: applicationSupportURL,
                operation: operation)
        } catch {
            let observationFailure = error
            try operation.closeColdControlObservationChecked()
            throw observationFailure
        }
        if !observed.eraseRootExists {
            try operation.closeColdControlObservationChecked()
            return false
        }
        if observed.preparation?.c05JobDrainV3 != nil {
            // The positive V3 scanner/Runner/owner exit remains unavailable.
            try operation.closeColdControlObservationChecked()
            throw EraseAllServiceError.recoveryRequired
        }
        if observed.intent != nil || observed.preparation != nil {
            // Transfer the exact already observed root descriptors to the
            // operation-retained no-repair store. A later schema-2 route must
            // use this owner, never the ordinary creating constructor.
            let store = try EraseIntentStore(coldObservation: controls,
                snapshot: observed, operation: operation)
            try operation.retainSchema2ColdIntentStore(store)
            traceErasePhase("recovery.schema2.store-retained")
            guard try store.load() == observed.intent,
                  try store.loadPreparation() == observed.preparation else {
                throw EraseAllServiceError.invalidAuthority
            }
            let sourceIdentity = try store.schema2ColdSupportIdentity(
                operation: operation)
            let physicalExclusion = try EraseSchema2ColdPhysicalExclusionV1(
                applicationSupportURL: applicationSupportURL,
                operation: operation)
            try operation.retainSchema2ColdPhysicalExclusion(
                physicalExclusion)
            try physicalExclusion.acquire(
                expectedDevice: sourceIdentity.device,
                expectedInode: sourceIdentity.inode)
            try operation.bindSchema2ColdPhysicalExclusion(
                physicalExclusion, device: sourceIdentity.device,
                inode: sourceIdentity.inode)
            try physicalExclusion.requireHeld(
                expectedDevice: sourceIdentity.device,
                expectedInode: sourceIdentity.inode)
            let expectedCurrentPointer: RestorePointerIdentityV1
            if let intent = observed.intent {
                guard intent.schemaVersion == 2,
                      let selected = intent.phase == .emptyGenerationPrepared
                        ? intent.oldPointer : intent.targetPointer else {
                    throw EraseAllServiceError.invalidAuthority
                }
                expectedCurrentPointer = selected
            } else if let preparation = observed.preparation {
                expectedCurrentPointer = preparation.oldPointer
            } else {
                throw EraseAllServiceError.invalidAuthority
            }
            let manifestOwner = EraseSchema2ColdManifestOwnerV1()
            try operation.retainSchema2ColdManifestOwner(manifestOwner)
            try manifestOwner.openExisting(
                applicationSupportURL: applicationSupportURL,
                expectedSupportDevice: sourceIdentity.device,
                expectedSupportInode: sourceIdentity.inode,
                phase: observed.intent?.phase,
                operation: operation)
            traceErasePhase("recovery.schema2.manifest-open")
            let frozenCurrent: EraseSchema2ColdTargetSnapshotV1
            if let intent = observed.intent,
               intent.phase == .emptyGenerationPrepared ||
                intent.phase == .pointerSwitched ||
                intent.phase == .sessionActivated ||
                intent.phase == .cleanupComplete {
                _ = try manifestOwner.readCurrentManifestForSchema2Cold(
                    intent: intent, operation: operation)
                _ = try manifestOwner.readGenerationInventory(
                    operation: operation)
                frozenCurrent = try manifestOwner.observeSchema2ColdTarget(
                    intent: intent, operation: operation)
            } else {
                let current = try generationFactory.observeSchema2ColdCurrent(
                    expectedPointer: expectedCurrentPointer,
                    manifestOwner: manifestOwner,
                    operation: operation)
                frozenCurrent = EraseSchema2ColdTargetSnapshotV1(
                    currentPointer: current.pointer,
                    pointer: current.pointer,
                    manifest: current.manifest,
                    retiredGenerationIDs: current.retiredGenerationIDs,
                    installedGenerationIDs: current.installedGenerationIDs)
            }
            guard let currentID = UUID(uuidString:
                    frozenCurrent.currentPointer.generationID),
                  currentID.uuidString.lowercased()
                    == frozenCurrent.currentPointer.generationID,
                  frozenCurrent.installedGenerationIDs.contains(
                    currentID) else {
                throw EraseAllServiceError.invalidAuthority
            }
            traceErasePhase("recovery.schema2.target-snapshot")
            if let intent = observed.intent,
               intent.phase == .sessionActivated
                || intent.phase == .cleanupComplete {
                let targetOnly: Set<UUID> = [intent.newGenerationID]
                let frozenIDs = Set(intent.generationIDsToDelete)
                    .union(targetOnly)
                guard frozenCurrent.installedGenerationIDs
                        .isSubset(of: frozenIDs),
                      (frozenCurrent.retiredGenerationIDs
                        == intent.generationIDsToDelete
                        || (frozenCurrent.retiredGenerationIDs.isEmpty
                            && frozenCurrent.installedGenerationIDs
                                == targetOnly)) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if intent.phase == .cleanupComplete {
                    guard frozenCurrent.retiredGenerationIDs.isEmpty,
                          frozenCurrent.installedGenerationIDs
                            == targetOnly else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            }
            var targetSource: EraseSchema2ColdTargetSourceV1?
            if let intent = observed.intent,
               (intent.phase == .pointerSwitched
                || intent.phase == .sessionActivated
                || intent.phase == .cleanupComplete
                || (intent.phase == .emptyGenerationPrepared
                    && frozenCurrent.currentPointer
                        == frozenCurrent.pointer)) {
                guard frozenCurrent.pointer.generationID
                    == intent.newGenerationID.uuidString.lowercased() else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if intent.phase == .emptyGenerationPrepared {
                    guard let preparation = observed.preparation else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.requireSchema2ColdPreparedTargetCurrentControls(
                        intent: intent, preparation: preparation)
                }
                // Capture the held target before the old-source private read
                // can suspend. A post-await survivor can never replace it.
                let capturedTarget = try manifestOwner.captureTargetSource(
                    id: intent.newGenerationID, operation: operation)
                targetSource = capturedTarget
                if intent.phase == .emptyGenerationPrepared {
                    try capturedTarget.capturePreparedTargetFirstTree()
                }
            }
            let survivingOperations = try manifestOwner.captureOperationsOwners(
                operation: operation)
            try manifestOwner.requireCapturedOperationsOwners(
                survivingOperations, operation: operation)
            traceErasePhase("recovery.schema2.operations-captured")
            guard try store.load() == observed.intent,
                  try store.loadPreparation() == observed.preparation else {
                throw EraseAllServiceError.invalidAuthority
            }
            if let intent = observed.intent,
               intent.phase == .sessionActivated || intent.phase == .cleanupComplete {
                try manifestOwner.captureLateNotificationControl(
                    eraseID: intent.eraseID, operation: operation)
                try manifestOwner.captureLateFinalizationControl(
                    deletedGenerationIDs: Set(intent.generationIDsToDelete),
                    operation: operation)
                try manifestOwner.captureLateDeletionControl(
                    deletedGenerationIDs: Set(intent.generationIDsToDelete),
                    operation: operation)
                try manifestOwner.captureLateMigrationControl(
                    generationIDsToDelete:
                        Set(intent.generationIDsToDelete),
                    targetGenerationID: intent.newGenerationID,
                    operation: operation)
            }
            traceErasePhase("recovery.schema2.late-controls-captured")
            try physicalExclusion.requireHeld(
                expectedDevice: sourceIdentity.device,
                expectedInode: sourceIdentity.inode)
            var retainedRegistry: GenerationLeaseRegistryV1?
            var retainedActivity: GenerationTemporalActivityHandleV1?
            var originalColdTokens: [GenerationLeaseTokenV1]?
            var firstActivatedPhaseCut:
                EraseIntentStore.Schema2ColdPhaseCASCutV1?
            if survivingOperations.contains("generation-leases") {
                let construction = TemporalColdRegistryConstructionV1()
                try operation.retainSchema2ColdRegistryConstruction(
                    construction)
                let registry = try GenerationLeaseRegistryV1
                    .openExistingForEraseSchema2Cold(
                        applicationSupportURL: applicationSupportURL,
                        operation: operation,
                        construction: construction)
                retainedRegistry = registry
                let acquisition = registry
                    .makeColdRetirementActivityAcquisition()
                try operation.retainSchema2ColdActivityAcquisition(
                    acquisition, registry: registry)
                let activity = try acquisition.acquireForEraseSchema2Cold(
                    operation: operation)
                try operation.retainSchema2ColdActivity(activity,
                    registry: registry)
                retainedActivity = activity
                let coldTokens: [GenerationLeaseTokenV1]
                if let intent = observed.intent,
                   let preparation = observed.preparation,
                   intent.schemaVersion == 2,
                   intent.phase == .pointerSwitched ||
                     intent.phase == .sessionActivated {
                    coldTokens = try registry
                        .settleEraseSchema2ColdRecordedTargetReader(
                            intent: intent, preparation: preparation,
                            manifest: manifestOwner,
                            operation: operation, activity: activity)
                    guard try registry.observeEraseSchema2ColdRegistry(
                            operation: operation, activity: activity)
                            == coldTokens else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                } else {
                    coldTokens = try registry
                        .observeEraseSchema2ColdRegistry(
                            operation: operation, activity: activity)
                }
                originalColdTokens = coldTokens
                if let intent = observed.intent {
                    let frozenIDs = Set(intent.generationIDsToDelete)
                        .union([intent.newGenerationID])
                    guard coldTokens.allSatisfy({ token in
                        frozenIDs.contains(token.epoch.generationID)
                            && (token.epoch.generationID != intent.newGenerationID
                                || token.epoch.generationManifestSHA256
                                    == frozenCurrent.pointer.generationManifestSHA256)
                    }) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                }
                if let intent = observed.intent,
                   let preparation = observed.preparation,
                   intent.schemaVersion == 2,
                   intent.phase == .emptyGenerationPrepared ||
                     intent.phase == .pointerSwitched ||
                     intent.phase == .sessionActivated,
                   intent.phase != .emptyGenerationPrepared ||
                     frozenCurrent.currentPointer == frozenCurrent.pointer,
                   preparation.matches(intent) {
                    // This G/EX census precedes every retained old or
                    // previously retired source FD. A later R cut may have
                    // removed the old root while other frozen IDs survive.
                    try operation.bindSchema2ColdOriginalTokenCensus(
                        coldTokens, registry: registry,
                        activity: activity)
                }
                _ = try registry.probeEraseSchema2ColdPredecessors(
                    operation: operation, activity: activity,
                    expectedTokens: coldTokens)
                traceErasePhase("recovery.schema2.registry-census")
                if let intent = observed.intent,
                   intent.phase == .sessionActivated,
                   observed.preparation != nil {
                    let pending = intent.advancing(to: .pointerSwitched)
                    try registry.withEraseSchema2ColdUnchangedTokens(
                        operation: operation, activity: activity,
                        expectedTokens: coldTokens) {
                        firstActivatedPhaseCut = try store
                            .requireSchema2ColdPhaseCASCut(
                                expected: pending,
                                replacement: intent,
                                operation: operation)
                    }
                    guard let firstActivatedPhaseCut,
                          case .published = firstActivatedPhaseCut else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    traceErasePhase("recovery.schema2.phase-cut")
                }
                if observed.opaqueIntentNextPresent {
                    guard let intent = observed.intent,
                          intent.phase == .pointerSwitched ||
                            intent.phase == .sessionActivated else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    let pending = intent.advancing(to: .pointerSwitched)
                    let published = pending.advancing(
                        to: .sessionActivated)
                    try registry.withEraseSchema2ColdUnchangedTokens(
                        operation: operation, activity: activity,
                        expectedTokens: coldTokens) {
                        // This only classifies the opaque retained cut. No
                        // private-copy or installed effect starts if the
                        // reserved name is not exact P/R provenance.
                        _ = try store.requireSchema2ColdPhaseCASCut(
                            expected: pending,
                            replacement: published,
                            operation: operation)
                    }
                }
            } else {
                // Historical late cuts may have already removed Registry.
                // The held Support EX above remains the only physical
                // exclusion; no replacement Registry or lease is minted.
                guard observed.intent?.phase == .sessionActivated ||
                        observed.intent?.phase == .cleanupComplete else {
                    throw EraseAllServiceError.invalidAuthority
                }
                guard !observed.opaqueIntentNextPresent else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            if observed.opaqueRosterPresent ||
                observed.opaqueRosterNextPresent {
                // A durable R roster can survive loss of model.sqlite in a
                // prior checked unlink. Decode it as data before any old or
                // retired semantic opening; the real target session and a
                // complete global survivor-prefix proof follow below.
                guard observed.opaqueRosterPresent,
                      !observed.opaqueRosterNextPresent,
                      !observed.opaqueIntentNextPresent,
                      let intent = observed.intent,
                      let preparation = observed.preparation,
                      intent.schemaVersion == 2,
                      intent.phase == .sessionActivated,
                      let targetSource,
                      let registry = retainedRegistry,
                      let activity = retainedActivity,
                      let tokens = originalColdTokens,
                      let phaseCut = firstActivatedPhaseCut else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try await resumeSchema2ColdPublishedRosterReplay(
                    observed: observed, intent: intent,
                    preparation: preparation,
                    snapshot: frozenCurrent, targetSource: targetSource,
                    operationsNames: survivingOperations,
                    registryTokens: tokens, phaseCut: phaseCut,
                    store: store, manifest: manifestOwner,
                    registry: registry, activity: activity,
                    operation: operation)
                throw EraseAllServiceError.recoveryRequired
            }
            let originalPresent = observed.intent.map {
                frozenCurrent.installedGenerationIDs.contains($0.oldGenerationID)
            } ?? false
            traceErasePhase("recovery.schema2.source-admission")
            if let intent = observed.intent,
               intent.phase == .emptyGenerationPrepared,
               frozenCurrent.currentPointer == frozenCurrent.pointer,
               !originalPresent {
                throw EraseAllServiceError.invalidAuthority
            }
            if let intent = observed.intent,
               intent.phase == .pointerSwitched,
               !originalPresent {
                throw EraseAllServiceError.invalidAuthority
            }
            var preparedFirstAuxiliaryObserver:
                EraseSchema2ColdAuxiliaryFirstObserverV1?
            if originalPresent,
               let phase = observed.intent?.phase,
               phase == .pointerSwitched || phase == .sessionActivated ||
                 (phase == .emptyGenerationPrepared &&
                    frozenCurrent.currentPointer == frozenCurrent.pointer) {
                guard let intent = observed.intent,
                      let preparation = observed.preparation,
                      let oldPointer = intent.oldPointer,
                      let registry = retainedRegistry,
                      let activity = retainedActivity,
                      let tokens = originalColdTokens else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let oldSource = try manifestOwner.captureRetainedOriginalSource(
                    id: intent.oldGenerationID,
                    expectedOldPointer: oldPointer,
                    intent: intent, preparation: preparation,
                    operation: operation)
                try operation.retainSchema2ColdOriginalContinuation(
                    EraseSchema2ColdOriginalContinuationV1(
                        observed: observed, intent: intent,
                        preparation: preparation,
                        generation: frozenCurrent,
                        operationsNames: survivingOperations,
                        registryTokens: tokens,
                        phaseCut: firstActivatedPhaseCut))
                if intent.phase == .emptyGenerationPrepared {
                    // Retain the checked IO owner before the first borrowed
                    // descriptor scan and before either private source await.
                    let observer = EraseSchema2ColdAuxiliaryFirstObserverV1()
                    try operation.retainSchema2ColdAuxiliaryFirstObserver(
                        observer, store: store, manifest: manifestOwner)
                    let first = try manifestOwner
                        .withHeldSchema2ColdAuxiliaryCapture(
                            cachesDirectoryURL: cachesDirectoryURL,
                            temporaryDirectoryURL: temporaryDirectoryURL,
                            operation: operation) { support, caches, temporary in
                            try observer.captureFirst(support: support,
                                caches: caches, temporary: temporary,
                                applicationSupportURL: applicationSupportURL)
                        }
                    try operation.bindSchema2ColdAuxiliaryFirstObservation(
                        first, observer: observer, store: store,
                        manifest: manifestOwner)
                    preparedFirstAuxiliaryObserver = observer
                }
                guard try registry.observeEraseSchema2ColdRegistry(
                        operation: operation, activity: activity) == tokens else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                guard try await validateOrResumeSchema2ColdRetainedSource(
                    intent: intent, intentStore: store,
                    source: oldSource, operation: operation) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                if intent.phase == .emptyGenerationPrepared {
                    guard let observer = preparedFirstAuxiliaryObserver else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try manifestOwner.requireSchema2ColdPreparedAuxiliaryUnchanged(
                        observer: observer, operation: operation)
                    try manifestOwner.requireSchema2ColdTargetSnapshot(
                        frozenCurrent, intent: intent, operation: operation)
                    guard let targetSource else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.requireSchema2ColdTargetSource(targetSource)
                    try targetSource.requirePreparedTargetFirstTreeUnchanged()
                }
                try physicalExclusion.requireHeld(
                    expectedDevice: sourceIdentity.device,
                    expectedInode: sourceIdentity.inode)
                try manifestOwner.requireCapturedOperationsOwners(
                    survivingOperations, operation: operation)
                guard try registry.observeEraseSchema2ColdRegistry(
                        operation: operation, activity: activity) == tokens else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try operation.requireSchema2ColdOriginalContinuation()
                try operation.completeSchema2ColdOriginalValidation()
                traceErasePhase("recovery.schema2.old-valid")
                if intent.phase == .emptyGenerationPrepared {
                    guard let targetSource,
                          let observer = preparedFirstAuxiliaryObserver,
                          let originalTokens = originalColdTokens else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.requireSchema2ColdPreparedTargetCurrentControls(
                        intent: intent, preparation: preparation)
                    guard try store.load() == intent,
                          try store.loadPreparation() == preparation,
                          try registry.observeEraseSchema2ColdRegistry(
                            operation: operation, activity: activity)
                            == originalTokens else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    guard try await generationFactory
                        .validateOrResumeSchema2ColdPreparedTargetCurrent(
                            source: targetSource,
                            snapshot: frozenCurrent,
                            intent: intent,
                            temporaryDirectoryURL: temporaryDirectoryURL,
                            operation: operation) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    try physicalExclusion.requireHeld(
                        expectedDevice: sourceIdentity.device,
                        expectedInode: sourceIdentity.inode)
                    try manifestOwner.requireCapturedOperationsOwners(
                        survivingOperations, operation: operation)
                    try manifestOwner.requireSchema2ColdTargetSnapshot(
                        frozenCurrent, intent: intent, operation: operation)
                    try operation.requireSchema2ColdTargetSource(targetSource)
                    try targetSource.requirePreparedTargetFirstTreeUnchanged()
                    try operation.requireSchema2ColdPreparedTargetCurrentControls(
                        intent: intent, preparation: preparation)
                    guard try store.load() == intent,
                          try store.loadPreparation() == preparation,
                          try registry.observeEraseSchema2ColdRegistry(
                            operation: operation, activity: activity)
                            == originalTokens,
                          let completed = operation
                            .schema2ColdPreparedTargetValidationAttempt else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    try operation.bindSchema2ColdPreparedTargetPrivateValidated(
                        source: targetSource, snapshot: frozenCurrent,
                        attempt: completed)
                    try manifestOwner.requireSchema2ColdPreparedAuxiliaryUnchanged(
                        observer: observer, operation: operation)
                    let firstAuxiliary = try observer.firstObservation()
                    let auxiliary = try manifestOwner
                        .decodeSchema2ColdObservedPreparedOriginalAuxiliaryRoster(
                            intent: intent, preparation: preparation,
                            store: store, observer: observer,
                            snapshot: firstAuxiliary, operation: operation)
                    try operation.retainSchema2ColdPreparedOriginalAuxiliaryObservation(
                        auxiliary, store: store, manifest: manifestOwner)
                    traceErasePhase(
                        "recovery.schema2.prepared-target-private-valid")
                }
            }
            if let intent = observed.intent,
               intent.phase == .pointerSwitched ||
                intent.phase == .sessionActivated {
                if let preparation = observed.preparation,
                   retainedRegistry != nil {
                    guard let tokens = originalColdTokens else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.retainSchema2ColdRetiredContinuation(
                        EraseSchema2ColdRetiredContinuationV1(
                            observed: observed, intent: intent,
                            preparation: preparation,
                            generation: frozenCurrent,
                            operationsNames: survivingOperations,
                            registryTokens: tokens,
                            phaseCut: firstActivatedPhaseCut))
                    try await validateOrResumeSchema2ColdRetiredSources(
                        operation: operation)
                } else {
                    // With Registry already retired, no surviving frozen
                    // generation may be opened or silently omitted.
                    guard frozenCurrent.installedGenerationIDs
                        .isDisjoint(with: Set(intent.generationIDsToDelete)) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            }
            if let targetSource, let intent = observed.intent,
               intent.phase != .emptyGenerationPrepared {
                if intent.phase == .pointerSwitched {
                    guard let preparation = observed.preparation,
                          let registry = retainedRegistry,
                          let activity = retainedActivity,
                          let tokens = originalColdTokens else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.retainSchema2ColdPreactivationContinuation(
                        EraseSchema2ColdPreactivationContinuationV1(
                            observed: observed, intent: intent,
                            preparation: preparation,
                            generation: frozenCurrent,
                            operationsNames: survivingOperations,
                            registryTokens: tokens))
                    guard try registry.observeEraseSchema2ColdRegistry(
                        operation: operation, activity: activity)
                            == tokens else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    guard try await generationFactory
                        .validateOrResumeSchema2ColdPreactivationTarget(
                            source: targetSource,
                            snapshot: frozenCurrent,
                            intent: intent,
                            temporaryDirectoryURL: temporaryDirectoryURL,
                            operation: operation) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    guard let completed = operation
                        .schema2ColdTargetValidationAttempt else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.bindSchema2ColdPreactivationValidated(
                        snapshot: frozenCurrent, attempt: completed)
                } else if intent.phase == .sessionActivated,
                          originalPresent {
                    guard let preparation = observed.preparation,
                          let registry = retainedRegistry,
                          let activity = retainedActivity,
                          let tokens = originalColdTokens,
                          let phaseCut = firstActivatedPhaseCut else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.retainSchema2ColdActivatedEntryContinuation(
                        EraseSchema2ColdActivatedEntryContinuationV1(
                            observed: observed, intent: intent,
                            preparation: preparation,
                            generation: frozenCurrent,
                            operationsNames: survivingOperations,
                            registryTokens: tokens,
                            phaseCut: phaseCut, replayRoster: nil))
                    guard try registry.observeEraseSchema2ColdRegistry(
                            operation: operation, activity: activity)
                            == tokens,
                          try await generationFactory
                            .validateOrResumeSchema2ColdTarget(
                                source: targetSource,
                                snapshot: frozenCurrent,
                                intent: intent,
                                temporaryDirectoryURL: temporaryDirectoryURL,
                                operation: operation) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                    guard let completed = operation
                        .schema2ColdTargetValidationAttempt else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try operation.bindSchema2ColdActivatedEntryValidated(
                        snapshot: frozenCurrent, attempt: completed)
                    traceErasePhase("recovery.schema2.target-private-valid")
                } else {
                    try operation.retainSchema2ColdTargetContinuation(
                        EraseSchema2ColdTargetContinuationV1(
                            observed: observed, intent: intent,
                            generation: frozenCurrent,
                            operationsNames: survivingOperations,
                            registryTokens: originalColdTokens))
                    guard try await generationFactory
                        .validateOrResumeSchema2ColdTarget(
                            source: targetSource,
                            snapshot: frozenCurrent,
                            intent: intent,
                            temporaryDirectoryURL: temporaryDirectoryURL,
                            operation: operation) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                }
            }
            // Private target validation suspends. Its result is a property of
            // the captured target, not an authorization to advance Erase from
            // a newly observed source or a changed operational namespace.
            try physicalExclusion.requireHeld(
                expectedDevice: sourceIdentity.device,
                expectedInode: sourceIdentity.inode)
            try manifestOwner.requireCapturedOperationsOwners(
                survivingOperations, operation: operation)
            if let registry = retainedRegistry,
               let activity = retainedActivity,
               let originalColdTokens {
                guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == originalColdTokens else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                try operation.requireSchema2ColdPredecessorGuards(
                    registry: registry)
            } else if retainedRegistry != nil || retainedActivity != nil
                || originalColdTokens != nil {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            if observed.intent?.phase == .pointerSwitched {
                traceErasePhase("recovery.schema2.p-forward.enter")
                do {
                    _ = try advanceSchema2ColdPointerSwitchedPhase(
                        operation: operation)
                } catch {
#if DEBUG
                    reportSchema2ColdPForwardFailure(error)
#endif
                    throw error
                }
                // Durable session activation is complete. The distinct
                // sessionActivated cleanup/roster chain must consume this
                // same operation; this frame cannot claim final Erase.
                traceErasePhase("recovery.schema2.p-forward.explicit-refusal")
#if DEBUG
                print("V23_C05_P_FORWARD_DIAG_V1 stage=explicit-refusal family=erase")
#endif
                throw EraseAllServiceError.recoveryRequired
            }
            if observed.intent?.phase == .sessionActivated,
               originalPresent {
                traceErasePhase("recovery.schema2.r-forward.enter")
                do {
                    _ = try advanceSchema2ColdActivatedEntry(
                        operation: operation)
                    // Continue under the same retained Service frame. A
                    // fresh process must not repeat R entry indefinitely.
                    try await continueSchema2ColdActivatedEntryAfterSession(
                        operation: operation)
                } catch {
#if DEBUG
                    reportSchema2ColdRForwardFailure(error)
#endif
                    throw error
                }
            }
            // Later phases still require their distinct typed forward owner.
            // Retain the transferred owner on refusal; do not close/reopen it.
            throw EraseAllServiceError.recoveryRequired
        }
        try controls.requireCaptured(observed, operation: operation)
        // An authenticated empty no-intent root is not a completed Erase.
        // Keep its exact reader on the cold operation for startup publication
        // reproof; name-based removal cannot identify the captured inode.
        try operation.retainEmptyNoWorkObservation(observed)
        return false
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
                guard preparation.c05JobDrainV3 == nil else {
                    throw EraseAllServiceError.recoveryRequired
                }
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
        originalC05Epoch: GenerationEpochV1? = nil,
        originalC05Jobs: [ResumableLocalJobV1]? = nil,
        originalC05TransientWitness:
            StoreRestoreGenerationAuthority.C05GenerationTransientWitnessV1? = nil,
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
            if let originalC05TransientWitness {
                guard try authority.c05SourceTransientWitness(
                    id: originalGenerationID) == originalC05TransientWitness else {
                    return nil
                }
            }
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
        originalC05Epoch: GenerationEpochV1? = nil,
        originalC05Jobs: [ResumableLocalJobV1]? = nil,
        originalC05TransientWitness:
            StoreRestoreGenerationAuthority.C05GenerationTransientWitnessV1? = nil,
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
        intentStore: EraseIntentStore,
        originalRecoveryContinuation: OriginalRecoveryValidatedSourceV1? = nil,
        coordinator: StoreSessionCoordinator? = nil,
        operation: EraseRouterOperationV1? = nil
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
        try requireRecoveryPresence(intent, authority: authority,
            operation: operation,
            originalRecoveryContinuation: originalRecoveryContinuation,
            coordinator: coordinator)
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
        authority: StoreRestoreGenerationAuthority,
        originalC05TransientWitness:
            StoreRestoreGenerationAuthority.C05GenerationTransientWitnessV1? = nil
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
            authority: authority,
            originalC05TransientWitness: originalC05TransientWitness
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

    private struct OriginalRecoveryCopiedContentV1 {
        let policy: OriginalRecoveryProvisionalPolicyV1
        let external: OriginalEraseRecoveryExternalSnapshotV1
        let reads: [OriginalEraseRecoveryExternalReadV1]
    }

    private func validateRetainedSourceFromOriginalRecoveryCopy(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        auxiliaryContinuity:
            StoreOriginalEraseRecoveryAuxiliaryContinuityV1? = nil
    ) throws -> OriginalRecoveryCopiedContentV1 {
        traceErasePhase("recovery.original-private-source.enter")
        guard intent.schemaVersion == 2,
              intent.oldPointer != nil,
              intent.targetPointer != nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        traceErasePhase("recovery.original.old.owner-pre-enter")
        try owner.requireObservationUnchanged()
        traceErasePhase("recovery.original.old.owner-pre-complete")
        if owner.observation?.intent?.phase == .emptyGenerationPrepared {
            guard auxiliaryContinuity != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        traceErasePhase("recovery.original.old.aux-pre-enter")
        _ = try auxiliaryContinuity?.requireProjected(owner: owner)
        traceErasePhase("recovery.original.old.aux-pre-complete")
        traceErasePhase("recovery.original.old.digest-enter")
        let treeDigest = try authority.originalRecoverySourceTreeDigest(
            id: intent.oldGenerationID)
        traceErasePhase("recovery.original.old.digest-complete")
        traceErasePhase("recovery.original.old.external-enter")
        let external = try owner.withExclusiveSourceScratch { _ in
            try authority.originalRecoveryExternalSnapshot()
        }
        traceErasePhase("recovery.original.old.external-complete")
        traceErasePhase("recovery.original.old.manifest-enter")
        let manifest = try EraseRetainedCopiedSourceValidationV1
            .checkedSourceManifest(intent: intent, owner: owner)
        traceErasePhase("recovery.original.old.manifest-complete")
        traceErasePhase("recovery.original.old.private-copy-enter")
#if DEBUG
        let privateSourceDiagnostic: (@MainActor (String) -> Void)? = {
            [self] stage in traceErasePhase(stage)
        }
#else
        let privateSourceDiagnostic: (@MainActor (String) -> Void)? = nil
#endif
        let reads = try generationFactory.withOriginalEraseRecoveryPrivateSource(
            owner: owner,
            authority: authority,
            generationID: intent.oldGenerationID,
            treeDigest: treeDigest,
            migrationID: manifest.migrationID,
            operationID: operation.originalRecoveryPrivateCopyOperationID,
            diagnosticPhase: privateSourceDiagnostic,
            onCheckedScratchSettlement: auxiliaryContinuity.map { retained in
                { receipt in retained.retainScratchSettlement(receipt,
                    owner: owner) }
            }
        ) { context, copyModelURL in
            traceErasePhase("recovery.original.old.callback-enter")
            traceErasePhase("recovery.original.old.validation-enter")
            let validation = try EraseRetainedCopiedSourceValidationV1(
                intent: intent, generationFactory: generationFactory,
                owner: owner, authority: authority,
                copyModelURL: copyModelURL,
                sourceTreeDigest: treeDigest,
                externalSnapshot: external)
            traceErasePhase("recovery.original.old.validation-complete")
            traceErasePhase("recovery.original.old.frozen-enter")
            try validateFrozenGeneration(
                id: intent.oldGenerationID,
                modelContext: context,
                generationRootURL: validation.generationRootURL,
                workspaceIdentity: validation.workspaceIdentity,
                authority: authority,
                retainedEraseValidation: validation)
            traceErasePhase("recovery.original.old.frozen-complete")
            traceErasePhase("recovery.original.old.reads-enter")
            let observations = try validation.checkedExternalReadObservations()
            traceErasePhase("recovery.original.old.reads-complete")
            traceErasePhase("recovery.original.old.callback-complete")
            return observations
        }
        traceErasePhase("recovery.original.old.private-copy-complete")
        traceErasePhase("recovery.original.old.aux-post-enter")
        _ = try auxiliaryContinuity?.requireProjected(owner: owner)
        traceErasePhase("recovery.original.old.aux-post-complete")
        traceErasePhase("recovery.original.old.owner-post-enter")
        try owner.requireObservationUnchanged()
        traceErasePhase("recovery.original.old.owner-post-complete")
        traceErasePhase("recovery.original.old.digest-post-enter")
        guard try authority.originalRecoverySourceTreeDigest(
            id: intent.oldGenerationID) == treeDigest else {
            throw EraseAllServiceError.invalidAuthority
        }
        traceErasePhase("recovery.original.old.digest-post-complete")
        traceErasePhase("recovery.original.old.external-post-enter")
        try owner.withExclusiveSourceScratch { _ in
            try authority.requireOriginalRecoveryExternalSnapshot(external)
        }
        traceErasePhase("recovery.original.old.external-post-complete")
        // This is a typed pending-or-strict observation, not policy admission.
        // The first-effect G scope must make fresh checked requests after all
        // post-admission semantic and target proofs have passed.
        traceErasePhase("recovery.original.old.policy-enter")
        let policy = try owner.withExclusiveSourceScratch { _ in
            try owner.requireObservationUnchangedInsideOriginalRecoveryG()
            return try authority.originalRecoveryProvisionalPolicy(
                id: intent.oldGenerationID, treeDigest: treeDigest)
        }
        traceErasePhase("recovery.original.old.policy-complete")
        traceErasePhase("recovery.original-private-source.complete")
        return .init(policy: policy, external: external, reads: reads)
    }

    internal struct OriginalRecoveryPriorRetiredCopyV1 {
        let image: OriginalEraseRecoveryPriorRetiredImageV1
        let semantic: EraseRetainedCopiedSourceValidationV1.PriorRetiredSemanticImage
        let policy: OriginalRecoveryProvisionalPolicyV1
        let external: OriginalEraseRecoveryExternalSnapshotV1
        let reads: [OriginalEraseRecoveryExternalReadV1]
    }

    /// Read each prior-retired generation through the original owner's private
    /// copy path. This is a validation result, not first-effect authorization.
    private func validatePriorRetiredFromOriginalRecoveryCopy(
        id: UUID, intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        auxiliaryContinuity:
            StoreOriginalEraseRecoveryAuxiliaryContinuityV1
    ) throws -> OriginalRecoveryPriorRetiredCopyV1 {
        traceErasePhase("recovery.original-prior-retired-copy.enter")
        let firstAuxiliary = try auxiliaryContinuity.requireProjected(owner: owner)
        let image = try OriginalEraseRecoveryPriorRetiredImageV1.capture(
            id: id, intent: intent, owner: owner, authority: authority,
            expectedAuxiliary: firstAuxiliary)
        let external = try owner.withExclusiveSourceScratch { _ in
            try authority.originalRecoveryExternalSnapshot()
        }
        let copied = try generationFactory.withOriginalEraseRecoveryPrivateSource(
            owner: owner, authority: authority, generationID: id,
            treeDigest: image.sourceTreeDigest,
            migrationID: image.manifest.migrationID,
            operationID: operation.originalRecoveryPrivateCopyOperationID,
            onCheckedScratchSettlement: { receipt in
                auxiliaryContinuity.retainScratchSettlement(receipt,
                    owner: owner)
            }
        ) { context, copyModelURL in
            let validation = try EraseRetainedCopiedSourceValidationV1(
                priorRetired: image, intent: intent,
                generationFactory: generationFactory, owner: owner,
                authority: authority, modelContext: context,
                copyModelURL: copyModelURL, externalSnapshot: external)
            try validateFrozenGeneration(
                id: id, modelContext: context,
                generationRootURL: validation.generationRootURL,
                workspaceIdentity: validation.workspaceIdentity,
                authority: authority, retainedEraseValidation: validation)
            let semantic = try validation.checkedPriorRetiredSemanticImage(in: context)
            let reads = try validation.checkedExternalReadObservations()
            return (semantic, reads)
        }
        _ = try auxiliaryContinuity.requireProjected(owner: owner)
        let policy = try owner.withExclusiveSourceScratch { _ in
            try image.requireUnchangedInsideOriginalG(
                intent: intent, owner: owner, authority: authority)
            try authority.requireOriginalRecoveryExternalSnapshot(external)
            return try authority.originalRecoveryProvisionalPolicy(
                id: id, treeDigest: image.sourceTreeDigest)
        }
        try owner.requireObservationUnchanged()
        traceErasePhase("recovery.original-prior-retired-copy.complete")
        return .init(image: image, semantic: copied.0, policy: policy,
                     external: external, reads: copied.1)
    }

    /// The target-current generation is authenticated from a private copy
    /// before the first phase CAS. All complete empty-row policies share the
    /// ordinary activation predicate, but this copy forbids state bootstrap
    /// and never opens or writes the installed target's ModelContainer.
    func validateOriginalRecoveryTargetFromCopy(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        operation: EraseRouterOperationV1,
        auxiliaryContinuity:
            StoreOriginalEraseRecoveryAuxiliaryContinuityV1
    ) throws -> String {
        guard intent.schemaVersion == 2,
              let target = intent.targetPointer,
              target.generationID == intent.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        let firstAuxiliary = try auxiliaryContinuity.requireProjected(owner: owner)
        let manifest = try owner.requireOriginalRecoveryTargetControls(
            intent: intent, expectedAuxiliary: firstAuxiliary)
        let digest = try authority.originalRecoveryEmptyTargetTreeDigest(
            id: intent.newGenerationID)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: target.workspaceID),
            replicaID: ReplicaID(rawValue: target.replicaID))
        try generationFactory.withOriginalEraseRecoveryPrivateSource(
            owner: owner, authority: authority,
            generationID: intent.newGenerationID,
            treeDigest: digest, migrationID: manifest.migrationID,
            operationID: operation.originalRecoveryPrivateCopyOperationID,
            onCheckedScratchSettlement: { receipt in
                auxiliaryContinuity.retainScratchSettlement(receipt,
                    owner: owner)
            }
        ) { context, _ in
            guard !context.hasChanges,
                  BackupRestoreService.isEmptyCurrent(context) else {
                throw EraseAllServiceError.invalidAuthority
            }
            try generationFactory.requireOriginalRecoveryTargetManifestSemanticDigest(
                in: context, manifest: manifest)
            try validateEmptyGenerationRows(
                modelContext: context, id: intent.newGenerationID,
                identity: identity,
                expectedEmptyLedger: try expectedEmptyLedger(intent),
                allowStateBootstrap: false)
            guard !context.hasChanges else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        _ = try auxiliaryContinuity.requireProjected(owner: owner)
        try owner.requireObservationUnchanged()
        guard try authority.originalRecoveryEmptyTargetTreeDigest(
            id: intent.newGenerationID) == digest else {
            throw EraseAllServiceError.invalidAuthority
        }
        let finalAuxiliary = try auxiliaryContinuity.requireProjected(owner: owner)
        _ = try owner.requireOriginalRecoveryTargetControls(
            intent: intent, expectedAuxiliary: finalAuxiliary)
        return digest
    }

    /// Dependency for the target-current, source-retained original recovery
    /// branch. It cannot be called from the current route until the first
    /// phase effect can consume the returned EX without reopening old-writer
    /// producer admission. The owner, not this value, retains uncertain FDs.
    struct OriginalRecoveryValidatedSourceV1 {
        var completedPolicyPhase:
            StoreOriginalEraseRecoveryPreOpenOwnerV1.FirstPointerPhaseResultV1? = nil
        var postPointerAuxiliaryProjection:
            OriginalRecoveryPostPointerAuxiliaryProjectionV1? = nil
        let owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
        let auxiliaryContinuity:
            StoreOriginalEraseRecoveryAuxiliaryContinuityV1
        let authority: StoreRestoreGenerationAuthority
        let intent: EraseIntentV1
        let preparation: ErasePreparationV2?
        let subject: EraseAllOperationSubjectV1
        let reservation: AppAccessGateV1.EraseAdoptionToken?
        let originalSourceTreeDigest: String
        let originalTargetTreeDigest: String
        let priorRetired: [OriginalRecoveryPriorRetiredCopyV1]
        let namespace: OriginalEraseRecoveryNamespaceSnapshotV1
        let provisionalSourcePolicy: OriginalRecoveryProvisionalPolicyV1
        let external: OriginalEraseRecoveryExternalSnapshotV1
        let externalReads: [OriginalEraseRecoveryExternalReadV1]
    }

    func validateOriginalRecoverySourceAcrossAdmission(
        coordinator: StoreSessionCoordinator,
        operation: EraseRouterOperationV1
    ) async throws -> OriginalRecoveryValidatedSourceV1? {
        func noCreateAuthority(
            observation: EraseIntentStore.OriginalRecoveryObservation,
            owner: StoreOriginalEraseRecoveryPreOpenOwnerV1
        ) throws -> StoreRestoreGenerationAuthority {
            try owner.makeOriginalRecoveryNoCreateAuthority(
                factory: generationFactory, observation: observation)
        }
        traceErasePhase("recovery.original.first.owner-enter")
        let first = try await coordinator.beginOriginalEraseRecoveryPreOpen(
            operation: operation, factory: generationFactory)
        traceErasePhase("recovery.original.first.owner-held")
        let observed: EraseIntentStore.OriginalRecoveryObservation
        traceErasePhase("recovery.original.first.controls-enter")
        do { observed = try first.observeIntentAndPreparation() }
        catch { first.poisonOnUncertainScratch(); throw error }
        traceErasePhase("recovery.original.first.controls-read")
        if observed.intent == nil {
            try first.closeReadOnlyBeforeAdmission()
            return nil
        }
        guard let intent = observed.intent,
              EraseIntentCodecV1.valid(intent) else {
            first.poisonOnUncertainScratch()
            throw EraseAllServiceError.invalidAuthority
        }
        if intent.schemaVersion != 2
            || intent.oldPointer == nil
            || intent.targetPointer == nil {
            try first.closeReadOnlyBeforeAdmission()
            return nil
        }
        if try first.observedCurrentGenerationID() != intent.newGenerationID {
            try first.closeReadOnlyBeforeAdmission()
            return nil
        }
        guard intent.phase == .emptyGenerationPrepared else {
            try first.closeReadOnlyBeforeAdmission()
            return nil
        }
        guard observed.preparation?.matches(intent) == true else {
            first.poisonOnUncertainScratch()
            throw EraseAllServiceError.invalidAuthority
        }
        traceErasePhase("recovery.original.first.intent-classified")
        let subject = EraseAllOperationSubjectV1(
            eraseID: intent.eraseID,
            newGenerationID: intent.newGenerationID,
            applicationSupportURL: applicationSupportURL,
            applicationSupportDevice: observed.supportDevice,
            applicationSupportInode: observed.supportInode)
        let firstAuthority: StoreRestoreGenerationAuthority
        traceErasePhase("recovery.original.first.authority-enter")
        do { firstAuthority = try noCreateAuthority(
            observation: observed, owner: first) }
        catch { first.poisonOnUncertainScratch(); throw error }
        traceErasePhase("recovery.original.first.authority-held")
        let auxiliaryContinuity:
            StoreOriginalEraseRecoveryAuxiliaryContinuityV1
        traceErasePhase("recovery.original.first.aux-enter")
        do {
            let retained = try StoreOriginalEraseRecoveryAuxiliaryContinuityV1(
                operation: operation, coordinator: coordinator,
                supportURL: applicationSupportURL,
                cachesURL: cachesDirectoryURL,
                temporaryURL: temporaryDirectoryURL)
            try operation.retainOriginalRecoveryAuxiliaryContinuity(
                retained, owner: first, coordinator: coordinator)
            auxiliaryContinuity = retained
            traceErasePhase("recovery.original.first.aux-owner-retained")
            let firstAuxiliary = try retained.captureFirst(owner: first)
            if first.retainedOriginalExclusion != nil {
                try operation.requireOriginalRecoveryAuxiliaryFirstMatchesOriginalP(
                    firstAuxiliary, owner: first, coordinator: coordinator)
            }
            traceErasePhase("recovery.original.first.aux-captured")
        } catch {
            _ = try? firstAuthority.closeCheckedForOriginalRecovery()
            first.poisonOnUncertainScratch()
            throw error
        }
        let firstNamespace: OriginalEraseRecoveryNamespaceSnapshotV1
        let firstCopiedContent: OriginalRecoveryCopiedContentV1
        let firstTargetTreeDigest: String
        let firstPriorRetired: [OriginalRecoveryPriorRetiredCopyV1]
        do {
            traceErasePhase("recovery.original.first.old-enter")
            let copied: OriginalRecoveryCopiedContentV1
            do {
                copied = try validateRetainedSourceFromOriginalRecoveryCopy(
                    intent, authority: firstAuthority,
                    owner: first, operation: operation,
                    auxiliaryContinuity: auxiliaryContinuity)
            } catch {
#if DEBUG
                traceErasePhase(Self.originalOldDiagnosticFailureLabel(error))
#endif
                throw error
            }
            traceErasePhase("recovery.original.first.old-valid")
            traceErasePhase("recovery.original.first.target-enter")
            let targetDigest = try validateOriginalRecoveryTargetFromCopy(
                intent, authority: firstAuthority,
                owner: first, operation: operation,
                auxiliaryContinuity: auxiliaryContinuity)
            traceErasePhase("recovery.original.first.target-valid")
            traceErasePhase("recovery.original.first.prior-enter")
            let priorRetired = try priorRetiredIDs(intent).map { id in
                try validatePriorRetiredFromOriginalRecoveryCopy(
                    id: id, intent: intent, authority: firstAuthority,
                    owner: first, operation: operation,
                    auxiliaryContinuity: auxiliaryContinuity)
            }
            traceErasePhase("recovery.original.first.prior-valid")
            traceErasePhase("recovery.original.first.namespace-enter")
            let namespace = try first.withExclusiveSourceScratch { _ in
                try firstAuthority.originalRecoveryNamespaceSnapshot(intent: intent)
            }
            traceErasePhase("recovery.original.first.namespace-captured")
            traceErasePhase("recovery.original.first.aux-reproof-enter")
            _ = try auxiliaryContinuity.requireProjected(owner: first)
            traceErasePhase("recovery.original.first.aux-reproof-complete")
            traceErasePhase("recovery.original.first.close-enter")
            try firstAuthority.closeCheckedForOriginalRecovery()
            traceErasePhase("recovery.original.first.authority-closed")
            try first.closeReadOnlyBeforeAdmission()
            traceErasePhase("recovery.original.first.closed")
            firstNamespace = namespace
            firstCopiedContent = copied
            firstTargetTreeDigest = targetDigest
            firstPriorRetired = priorRetired
        } catch {
            _ = try? firstAuthority.closeCheckedForOriginalRecovery()
            first.poisonOnUncertainScratch()
            throw error
        }
        traceErasePhase("recovery.original.first.admit-enter")
        let reservation = try await admit(subject)
        traceErasePhase("recovery.original.first.admit-returned")
        let second = try await coordinator.beginOriginalEraseRecoveryPreOpen(
            operation: operation, factory: generationFactory)
        let post: EraseIntentStore.OriginalRecoveryObservation
        do { post = try second.observeIntentAndPreparation() }
        catch { second.poisonOnUncertainScratch(); throw error }
        guard post == observed else {
            second.poisonOnUncertainScratch()
            throw EraseAllServiceError.invalidAuthority
        }
        do { _ = try auxiliaryContinuity.requireProjected(owner: second) }
        catch { second.poisonOnUncertainScratch(); throw error }
        let authority: StoreRestoreGenerationAuthority
        do { authority = try noCreateAuthority(observation: post, owner: second) }
        catch { second.poisonOnUncertainScratch(); throw error }
        do {
            let copied = try validateRetainedSourceFromOriginalRecoveryCopy(
                intent, authority: authority,
                owner: second, operation: operation,
                auxiliaryContinuity: auxiliaryContinuity)
            let targetDigest = try validateOriginalRecoveryTargetFromCopy(
                intent, authority: authority,
                owner: second, operation: operation,
                auxiliaryContinuity: auxiliaryContinuity)
            let priorRetired = try priorRetiredIDs(intent).map { id in
                try validatePriorRetiredFromOriginalRecoveryCopy(
                    id: id, intent: intent, authority: authority,
                    owner: second, operation: operation,
                    auxiliaryContinuity: auxiliaryContinuity)
            }
            guard priorRetired.count == firstPriorRetired.count else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (before, after) in zip(firstPriorRetired, priorRetired) {
                guard before.image == after.image,
                      before.semantic == after.semantic,
                      before.policy.sameObservedSource(as: after.policy),
                      before.external == after.external,
                      before.reads == after.reads else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            let namespace = try second.withExclusiveSourceScratch { _ in
                try authority.originalRecoveryNamespaceSnapshot(intent: intent)
            }
            _ = try auxiliaryContinuity.requireProjected(owner: second)
            guard namespace == firstNamespace,
                  targetDigest == firstTargetTreeDigest,
                  copied.policy.sameObservedSource(
                    as: firstCopiedContent.policy),
                  copied.external == firstCopiedContent.external,
                  copied.reads == firstCopiedContent.reads else {
                throw EraseAllServiceError.invalidAuthority
            }
            let digest = try authority.originalRecoverySourceTreeDigest(
                id: intent.oldGenerationID)
            try second.requireObservationUnchanged()
            return OriginalRecoveryValidatedSourceV1(
                owner: second, auxiliaryContinuity: auxiliaryContinuity,
                authority: authority,
                intent: intent, preparation: post.preparation,
                subject: subject, reservation: reservation,
                originalSourceTreeDigest: digest,
                originalTargetTreeDigest: firstTargetTreeDigest,
                priorRetired: priorRetired,
                namespace: namespace,
                provisionalSourcePolicy: copied.policy,
                external: copied.external,
                externalReads: copied.reads)
        } catch {
            _ = try? authority.closeCheckedForOriginalRecovery()
            second.poisonOnUncertainScratch()
            throw error
        }
    }

    func requireRecoveryPresence(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        originalRecoveryOwner: StoreOriginalEraseRecoveryPreOpenOwnerV1? = nil,
        operation: EraseRouterOperationV1? = nil,
        originalRecoveryContinuation: OriginalRecoveryValidatedSourceV1? = nil,
        coordinator: StoreSessionCoordinator? = nil
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
        // Genuine retained-original Q checks its immutable P→Q control
        // postimage before any source read, while the first writer cohort is
        // still exact. The same check runs after those reads below.
        let deferOriginalPublishedTargetCheck =
            originalRecoveryContinuation?.owner.retainedOriginalExclusion != nil
            && intent.schemaVersion == 2
            && intent.phase == .pointerSwitched
        func requireRetainedPublishedTarget() throws {
            guard let original = originalRecoveryContinuation,
                  let coordinator, let operation,
                  let projection = original.postPointerAuxiliaryProjection,
                  intent.targetPointer?.generationID == intent.newGenerationID else {
                throw EraseAllServiceError.invalidAuthority
            }
            try coordinator.withOriginalRecoveryPostPointerOperationsReproof(
                owner: original.owner, operation: operation,
                intent: intent, projection: projection) {
                let pointerReceipt = try operation
                    .requireOriginalEraseRetiredPointerReceiptFromIssuer()
                try authority.requireOriginalRecoveryPublishedControls(
                    receipt: pointerReceipt, intent: intent)
                try authority.requireOriginalRecoveryTransferredSourceTree(
                    id: intent.newGenerationID,
                    expectedDigest: original.originalTargetTreeDigest)
            }
        }
        let currentID: UUID
        if deferOriginalPublishedTargetCheck {
            try requireRetainedPublishedTarget()
            currentID = intent.newGenerationID
        } else {
            currentID = try generationFactory.currentGenerationID(
                authority: authority)
        }
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
                if !deferOriginalPublishedTargetCheck {
                    _ = try requirePublishedEmptySession(
                        intent,
                        authority: authority
                    )
                }
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
            if let original = originalRecoveryContinuation {
                guard intent.schemaVersion == 2,
                      currentID == intent.newGenerationID,
                      let coordinator, let operation,
                      let completed = original.completedPolicyPhase,
                      completed.intent == intent,
                      intent == original.intent.advancing(to: .pointerSwitched),
                      completed.sources.filter({ $0.generationID == id }).count == 1,
                      let receipt = completed.sources.first(where: { $0.generationID == id }) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let prior = original.priorRetired.first(where: { $0.image.generationID == id })
                guard id == intent.oldGenerationID || prior != nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if original.owner.retainedOriginalExclusion != nil {
                    try coordinator.requireOriginalRecoveryRetainedSourceContinuation(
                        owner: original.owner, operation: operation,
                        intent: intent)
                } else {
                    try coordinator.requireOriginalRecoveryTargetTransfer(
                        owner: original.owner, operation: operation,
                        intent: intent)
                }
                if original.owner.retainedOriginalExclusion != nil {
                    guard let projected = original.postPointerAuxiliaryProjection else {
                        throw EraseAllServiceError.invalidAuthority
                    }
#if DEBUG
                    traceErasePhase("recovery.presence.transferred-prior-enter")
#endif
                    try coordinator.withOriginalRecoveryPostPointerOperationsReproof(
                        owner: original.owner, operation: operation,
                        intent: intent, projection: projected) {
                        try authority.requireOriginalRecoveryTransferredCompletedSource(
                            receipt, originalAuthority: original.authority,
                            expectedOriginalDigest: prior?.image.sourceTreeDigest
                                ?? original.originalSourceTreeDigest,
                            namespace: original.namespace,
                            supportFact: original.external.support,
                            priorImage: prior?.image)
                    }
                } else {
                    try authority.requireOriginalRecoveryTransferredCompletedSource(
                        receipt, originalAuthority: original.authority,
                        expectedOriginalDigest: prior?.image.sourceTreeDigest
                            ?? original.originalSourceTreeDigest,
                        namespace: original.namespace,
                        supportFact: original.external.support,
                        priorImage: prior?.image)
                }
                if original.owner.retainedOriginalExclusion != nil {
                    try coordinator.requireOriginalRecoveryRetainedSourceContinuation(
                        owner: original.owner, operation: operation,
                        intent: intent)
                } else {
                    try coordinator.requireOriginalRecoveryTargetTransfer(
                        owner: original.owner, operation: operation,
                        intent: intent)
                }
                continue
            }
            if intent.schemaVersion == 2, id != intent.oldGenerationID {
                traceErasePhase("recovery.presence.preexisting-retired")
                try generationFactory.validateRecoveryRetiredGenerationForErase(
                    id: id, intent: intent, authority: authority, service: self)
                continue
            }
            if intent.schemaVersion == 2,
               id == intent.oldGenerationID,
               currentID == intent.newGenerationID {
                if let originalRecoveryOwner, let operation {
                    try validateRetainedSourceFromOriginalRecoveryCopy(
                        intent, authority: authority,
                        owner: originalRecoveryOwner,
                        operation: operation)
                    continue
                }
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
        if deferOriginalPublishedTargetCheck {
            traceErasePhase("recovery.presence.published-empty")
            try requireRetainedPublishedTarget()
        }
    }

    func advanceToActivatedSession(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        originalAuxiliaryOperation: EraseRouterOperationV1? = nil,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> StoreGenerationSession {
        try inject(.beforePointerSwitch)
        try normalizePointerAndRetired(intent, authority: authority,
            originalAuxiliaryOperation: originalAuxiliaryOperation,
            originalAuxiliaryStore: originalAuxiliaryOperation == nil
                ? nil : intentStore)
        try inject(.afterPointerSwitch)

        let switched = intent.advancing(to: .pointerSwitched)
        try inject(.beforePointerPhaseWrite)
        if intent.phase == .emptyGenerationPrepared {
            if let originalAuxiliaryOperation {
#if DEBUG
                traceErasePhase("original.phase-cas.store-enter")
#endif
                do {
                    try intentStore.replaceOriginalEraseAuxiliaryPhase(
                        expected: intent, with: switched,
                        operation: originalAuxiliaryOperation)
                } catch {
#if DEBUG
                    switch error {
                    case EraseIntentStoreError.invalidAuthority:
                        traceErasePhase("original.phase-cas.error.invalid-authority")
                    case EraseIntentStoreError.intentMismatch:
                        traceErasePhase("original.phase-cas.error.intent-mismatch")
                    case EraseIntentStoreError.writeFailed:
                        traceErasePhase("original.phase-cas.error.write-failed")
                    case EraseIntentStoreError.cleanupFailed:
                        traceErasePhase("original.phase-cas.error.cleanup-failed")
                    case EraseIntentStoreError.retirementPolicyEffectUnavailable:
                        traceErasePhase("original.phase-cas.error.retirement-policy")
                    case EraseIntentStoreError.invalidIntent:
                        traceErasePhase("original.phase-cas.error.invalid-intent")
                    case EraseIntentStoreError.invalidPreparation:
                        traceErasePhase("original.phase-cas.error.invalid-preparation")
                    case EraseIntentStoreError.intentAlreadyExists:
                        traceErasePhase("original.phase-cas.error.intent-exists")
                    case EraseIntentStoreError.intentMissing:
                        traceErasePhase("original.phase-cas.error.intent-missing")
                    case EraseIntentStoreError.preparationAlreadyExists:
                        traceErasePhase("original.phase-cas.error.preparation-exists")
                    case EraseIntentStoreError.preparationMissing:
                        traceErasePhase("original.phase-cas.error.preparation-missing")
                    case EraseIntentStoreError.preparationMismatch:
                        traceErasePhase("original.phase-cas.error.preparation-mismatch")
                    default:
                        traceErasePhase("original.phase-cas.error.other")
                    }
#endif
                    throw error
                }
#if DEBUG
                traceErasePhase("original.phase-cas.store-returned")
#endif
                try originalAuxiliaryOperation
                    .recordOriginalEraseAuxiliaryPhaseProjection(
                        store: intentStore, expected: intent,
                        replacement: switched)
#if DEBUG
                traceErasePhase("original.phase-cas.router-projected")
#endif
            } else {
                try intentStore.replace(expected: intent, with: switched)
            }
        }
        try inject(.afterPointerPhaseWrite)
        return try await advancePointerPhaseToActivatedSession(
            switched,
            authority: authority,
            intentStore: intentStore,
            originalAuxiliaryOperation: originalAuxiliaryOperation,
            activate: activate
        )
    }

    func advancePointerPhaseToActivatedSession(
        _ switched: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        originalAuxiliaryOperation: EraseRouterOperationV1? = nil,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> StoreGenerationSession {
        if originalAuxiliaryOperation != nil {
            // The authenticated original after-pointer-switch cut already
            // published both pointer and retired metadata before its fault.
            // A partial cut requires a distinct checked owner for that write;
            // this retained-source continuation only reobserves the postimage.
            try requireNewCurrent(switched, authority: authority,
                originalAuxiliaryOperation: originalAuxiliaryOperation)
        } else {
            try normalizePointerAndRetired(switched, authority: authority)
        }
        try requireNewCurrent(switched, authority: authority,
            originalAuxiliaryOperation: originalAuxiliaryOperation)
        let session: StoreGenerationSession
        if switched.schemaVersion == 2 {
            session = try requirePublishedEmptySession(
                switched,
                authority: authority,
                originalAuxiliaryOperation: originalAuxiliaryOperation
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
        if let originalAuxiliaryOperation {
            try originalAuxiliaryOperation
                .requireOriginalEraseTargetInstalledBeforePhaseCAS(session)
        }
        try inject(.afterSessionActivation)

        let activated = switched.advancing(to: .sessionActivated)
        try inject(.beforeSessionPhaseWrite)
        if let originalAuxiliaryOperation {
            try intentStore.replaceOriginalEraseAuxiliaryPhase(
                expected: switched, with: activated,
                operation: originalAuxiliaryOperation)
            try originalAuxiliaryOperation
                .recordOriginalEraseAuxiliaryPhaseProjection(
                    store: intentStore, expected: switched,
                    replacement: activated)
        } else {
            try intentStore.replace(expected: switched, with: activated)
        }
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
        authority: StoreRestoreGenerationAuthority,
        originalAuxiliaryOperation: EraseRouterOperationV1? = nil,
        originalAuxiliaryStore: EraseIntentStore? = nil
    ) throws {
#if DEBUG
        try originalColdExitFrame?.beforePointerPublication(intent)
#endif
        let current: UUID
        if let originalAuxiliaryOperation,
           let issued = try originalAuxiliaryOperation
                .observedOriginalEraseCurrentIDIfPublished(
                    authority: authority) {
            current = issued
        } else {
            current = try generationFactory.currentGenerationID(
                authority: authority)
        }
#if DEBUG
        if originalEraseFrameActive {
            traceErasePhase("original.normalize.current-observed")
        }
#endif
        if current == intent.oldGenerationID {
            if intent.schemaVersion == 2 {
                if let originalAuxiliaryOperation,
                   let originalAuxiliaryStore {
                    try originalAuxiliaryOperation
                        .requireOriginalEraseRetainedSourceLedgerBeforePointer(
                            intent: intent, store: originalAuxiliaryStore,
                            factory: generationFactory, authority: authority)
                } else {
                    try requireSourceLedgerBinding(intent, authority: authority)
                }
                guard let oldPointer = intent.oldPointer,
                      let targetPointer = intent.targetPointer else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if let originalAuxiliaryOperation,
                   let originalAuxiliaryStore {
                    try generationFactory
                        .publishEmptyEraseGenerationForOriginalRetainedExclusion(
                            expectedOldPointer: oldPointer,
                            targetPointer: targetPointer,
                            expectedEmptyLedger: try expectedEmptyLedger(intent),
                            authority: authority, intent: intent,
                            store: originalAuxiliaryStore,
                            operation: originalAuxiliaryOperation)
                } else {
                    try generationFactory.publishEmptyEraseGeneration(
                        expectedOldPointer: oldPointer,
                        targetPointer: targetPointer,
                        expectedEmptyLedger: try expectedEmptyLedger(intent),
                        authority: authority)
                }
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
            if let originalAuxiliaryOperation {
                _ = try originalAuxiliaryOperation
                    .requireOriginalEraseCurrentPointerReceipt(
                        authority: authority)
            } else {
                _ = try requirePublishedEmptySession(intent, authority: authority)
            }
        }
#if DEBUG
        if originalEraseFrameActive {
            traceErasePhase("original.normalize.current-effect-complete")
        }
#endif
        let retired: [UUID]
        if let originalAuxiliaryOperation,
           let issued = try originalAuxiliaryOperation
                .observedOriginalEraseRetiredIDsIfPublished(
                    authority: authority) {
            retired = issued
        } else {
            retired = try authority.retiredGenerationIDs()
        }
#if DEBUG
        if originalEraseFrameActive {
            traceErasePhase("original.normalize.retired-observed")
        }
#endif
        let prior = priorRetiredIDs(intent)
        if retired == prior {
            if let originalAuxiliaryOperation,
               let originalAuxiliaryStore {
                try generationFactory
                    .replaceRetiredGenerationIDsForOriginalRetainedExclusion(
                        expected: prior,
                        with: intent.generationIDsToDelete,
                        currentID: intent.newGenerationID,
                        authority: authority, intent: intent,
                        store: originalAuxiliaryStore,
                        operation: originalAuxiliaryOperation)
            } else {
                try generationFactory.replaceRetiredGenerationIDs(
                    expected: prior,
                    with: intent.generationIDsToDelete,
                    currentID: intent.newGenerationID,
                    authority: authority)
            }
        } else if retired != intent.generationIDsToDelete {
            throw EraseAllServiceError.invalidAuthority
        } else if let originalAuxiliaryOperation {
            _ = try originalAuxiliaryOperation
                .requireOriginalEraseRetiredPointerReceipt(
                    authority: authority)
        }
#if DEBUG
        if originalEraseFrameActive {
            traceErasePhase("original.normalize.retired-effect-complete")
        }
#endif
#if DEBUG
        try originalColdExitFrame?.afterPointerPublication(intent)
#endif
    }

    func requireNewCurrent(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        originalAuxiliaryOperation: EraseRouterOperationV1? = nil
    ) throws {
        if intent.schemaVersion == 2, let originalAuxiliaryOperation {
            let receipt = try originalAuxiliaryOperation
                .requireOriginalEraseRetiredPointerReceiptFromIssuer()
            guard try receipt.currentGenerationID()
                    == intent.newGenerationID,
                  try receipt.retiredGenerationIDs()
                    == intent.generationIDsToDelete,
                  let target = intent.targetPointer,
                  target.generationID == intent.newGenerationID else {
                throw EraseAllServiceError.invalidAuthority
            }
            // The issuer-bound receipt supplies the immutable original Q
            // controls. The distinct recovery authority independently reads
            // their exact held/named full postimage without any repair path.
            try authority.requireOriginalRecoveryPublishedControls(
                receipt: receipt, intent: intent)
        } else {
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

    /// A pointer-switched target is semantically empty before a real target
    /// session exists. Reuse every published-empty row, ledger, policy and
    /// history predicate, while keeping this proof explicitly preactivation.
    /// The projected phase is an input to those pure predicates only; this
    /// method never constructs or attests an activated session.
    static func requireEmptyErasePreactivationGraph(
        context: ModelContext,
        generationID: UUID,
        identity: WorkspaceReplicaIdentityV1,
        switched: EraseIntentV1
    ) throws {
        guard switched.schemaVersion == 2,
              switched.phase == .pointerSwitched else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireEmptyErasePublishedGraph(
            context: context, generationID: generationID,
            identity: identity,
            activated: switched.advancing(to: .sessionActivated))
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
        try validateEmptyGenerationRows(
            modelContext: session.modelContext, id: id,
            identity: identity, expectedEmptyLedger: expectedEmptyLedger,
            allowStateBootstrap: true)
        return session
    }

    /// The same complete empty-generation row/policy/ledger predicate is used
    /// by ordinary activation and the original recovery's private copy. The
    /// private branch forbids state bootstrap and any live target write.
    func validateEmptyGenerationRows(
        modelContext: ModelContext, id: UUID,
        identity: WorkspaceReplicaIdentityV1?,
        expectedEmptyLedger: DeletionLedgerProofV2?,
        allowStateBootstrap: Bool
    ) throws {
        traceErasePhase("empty.policy.EvidenceAssuranceEraseAllPolicyV1")
        try EvidenceAssuranceEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.InspectionReviewEraseAllPolicyV1")
        try InspectionReviewEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.WorkPacketEraseAllPolicyV1")
        try WorkPacketEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.FieldDraftEraseAllPolicyV1")
        try FieldDraftEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.PackageEvolutionEraseAllPolicyV1")
        try PackageEvolutionEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.ClientCapabilityEraseAllPolicyV1")
        try ClientCapabilityEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.PrivacyTransformEraseAllPolicyV1")
        try PrivacyTransformEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.MeasurementIntegrityEraseAllPolicyV1")
        try MeasurementIntegrityEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.FieldReferenceEraseAllPolicyV1")
        try FieldReferenceEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.AccessibleDocumentEraseAllPolicyV1")
        try AccessibleDocumentEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.SurveyDefinitionEraseAllPolicyV1")
        try SurveyDefinitionEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.SurveySessionEraseAllPolicyV1")
        try SurveySessionEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.AssetLocatorEraseAllPolicyV1")
        try AssetLocatorEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.ScheduleEraseAllPolicyV1")
        try ScheduleEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.C57MyDayEraseAllPolicyV1")
        try C57MyDayEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.EvidenceMetadataEraseAllPolicyV1")
        try EvidenceMetadataEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.C04ShopReportProfileEraseAllPolicyV1")
        try C04ShopReportProfileEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.C05RoundSessionEraseAllPolicyV1")
        try C05RoundSessionEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.EvidenceQualityEraseAllPolicyV1")
        try EvidenceQualityEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.FastSurveyInboxEraseAllPolicyV1")
        try FastSurveyInboxEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.ReinspectionExceptionEraseAllPolicyV1")
        try ReinspectionExceptionEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.EntityIdentityResolutionEraseAllPolicyV1")
        try EntityIdentityResolutionEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.PracticeWorkspaceProvenanceEraseAllPolicyV1")
        try PracticeWorkspaceProvenanceEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.LightingDayInventoryEraseAllPolicyV1")
        try LightingDayInventoryEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.LightingNightWorkflowEraseAllPolicyV1")
        try LightingNightWorkflowEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.ServiceRequestEraseAllPolicyV1")
        try ServiceRequestEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.AssetServiceReliabilityEraseAllPolicyV1")
        try AssetServiceReliabilityEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        traceErasePhase("empty.policy.PlanEraseAllPolicyV1")
        try PlanEraseAllPolicyV1.validatePublishedEmptyGeneration(modelContext)
        traceErasePhase("empty.policy.PlacementPoseEraseAllPolicyV1")
        try PlacementPoseEraseAllPolicyV1.validatePublishedEmptyGeneration(
            modelContext
        )
        try validateActivityContractEraseClosure(modelContext: modelContext)
        try validateImportBulkEraseClosure(modelContext: modelContext)
        if let identity {
            let history = try MutationJournalStoreV1(
                modelContext: modelContext,
                identity: identity,
                generationID: id, allowStateBootstrap: allowStateBootstrap
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
                context: modelContext
            ).snapshot()
            guard ledger.entries.isEmpty,
                  try ledgerProof(ledger) == expectedEmptyLedger else {
                traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    func validateFrozenGeneration(
        id: UUID,
        modelContext: ModelContext,
        generationRootURL: URL,
        workspaceIdentity: WorkspaceReplicaIdentityV1,
        authority: StoreRestoreGenerationAuthority?,
        retainedEraseValidation: (any EraseRetainedSourceValidationAuthorityV1)? = nil,
        preexistingRetiredValidation: ErasePreexistingRetiredSourceValidationV1? = nil,
        recoveryRetiredValidation: EraseRecoveryRetiredSourceValidationV1? = nil,
        originalC05TransientWitness:
            StoreRestoreGenerationAuthority.C05GenerationTransientWitnessV1? = nil,
        coldRetainedSource: (any EraseSchema2ColdPrivateReadableSourceV1)? = nil
    ) throws {
        guard (authority == nil) != (coldRetainedSource == nil),
              coldRetainedSource == nil ||
                (retainedEraseValidation != nil &&
                 preexistingRetiredValidation == nil &&
                 recoveryRetiredValidation == nil) else {
            throw EraseAllServiceError.invalidAuthority
        }
        func checkedOriginalTree() throws ->
            (tree: StoreRestoreGenerationAuthority.Tree, digest: String?) {
            if let source = coldRetainedSource {
                try source.requireOriginalUnchanged()
                let observed = try source.checkedOriginalTree()
                let directories = Set(observed.nodes.compactMap { node in
                    node.path.isEmpty || node.fact.st_mode & S_IFMT != S_IFDIR
                        ? nil : node.path
                })
                let files = Set(observed.nodes.compactMap { node in
                    node.fact.st_mode & S_IFMT == S_IFREG ? node.path : nil
                })
                return (StoreRestoreGenerationAuthority.Tree(
                    directories: directories, files: files), observed.digest)
            }
            guard let authority else {
                throw EraseAllServiceError.invalidAuthority
            }
            return (try authority.installedTree(id: id), nil)
        }
        traceErasePhase("frozen.context-and-root")
        guard !modelContext.hasChanges,
              generationRootURL.standardizedFileURL
                == generationFactory.installedGenerationURL(id: id) else {
            traceErasePhase("authority.failure.line.\(#line)"); throw EraseAllServiceError.invalidAuthority
        }
        func checkedContentRootIdentity() throws
            -> ReportPDFAnchoredFile.RootIdentity {
            if coldRetainedSource != nil {
                guard let retainedEraseValidation = retainedEraseValidation as? EraseRetainedSourceValidationV1 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return try retainedEraseValidation.checkedColdRootIdentity()
            }
            if let copied = retainedEraseValidation as? EraseRetainedCopiedSourceValidationV1 {
                return try copied.checkedRootIdentity()
            }
            return try ReportPDFAnchoredFile.rootIdentity(
                at: generationRootURL)
        }
        let contentRootIdentity = try checkedContentRootIdentity()
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
        if recoveryRetiredValidation != nil ||
            preexistingRetiredValidation != nil ||
            retainedEraseValidation != nil || !temporalClips.isEmpty ||
            !BackupRestoreService.isEmptyCurrent(modelContext) {
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
        let initialTree = try checkedOriginalTree()
        let tree = initialTree.tree
        if let coldRetainedSource {
            guard try coldRetainedSource.checkedOriginalC05TransientWitness()
                    == originalC05TransientWitness else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        if let originalC05TransientWitness {
            if let authority {
                guard try authority.c05SourceTransientWitness(id: id)
                        == originalC05TransientWitness else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            guard originalC05TransientWitness.directories.isSubset(
                    of: tree.directories),
                  originalC05TransientWitness.files.isSubset(of: tree.files) else {
                throw EraseAllServiceError.invalidAuthority
            }
            optionalDirectories.formUnion(
                originalC05TransientWitness.directories)
            optionalFiles.formUnion(originalC05TransientWitness.files)
        }
        traceErasePhase("frozen.label-inventory")
        let contentStore: EvidenceBundleStore? = coldRetainedSource == nil
            ? EvidenceBundleStore(
                generationRootURL: generationRootURL,
                fileManager: fileManager,
                expectedGenerationRootIdentity: contentRootIdentity)
            : nil
        func resolveContent(_ reference: ContentReferenceV1) throws
            -> ContentReferenceV1? {
            if let coldRetainedSource {
                try coldRetainedSource.requireOriginalUnchanged()
                guard let retainedEraseValidation = retainedEraseValidation as? EraseRetainedSourceValidationV1 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return try retainedEraseValidation.resolveColdContentReference(
                    reference)
            }
            guard let contentStore else { throw EraseAllServiceError.invalidAuthority }
            if let copied = retainedEraseValidation as? EraseRetainedCopiedSourceValidationV1 {
                return try copied.checkedContentReference(reference)
            }
            return try contentStore.resolveContentReference(reference)
        }
        func readLabelArtifacts(_ jobID: LocalJobIDV1) throws
            -> AssetLabelPublishedContentReadbackV1? {
            if let coldRetainedSource {
                try coldRetainedSource.requireOriginalUnchanged()
                guard let retainedEraseValidation = retainedEraseValidation as? EraseRetainedSourceValidationV1 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return try retainedEraseValidation.readColdAssetLabelArtifacts(
                    jobID: jobID)
            }
            guard let contentStore else { throw EraseAllServiceError.invalidAuthority }
            if let copied = retainedEraseValidation as? EraseRetainedCopiedSourceValidationV1 {
                return try contentStore.readAssetLabelArtifactsChecked(
                    jobID: jobID, files: tree.files,
                    read: { path, maximum in
                        try copied.checkedSourceBytes(path, maximum: maximum)
                    })
            }
            return try contentStore.readAssetLabelArtifacts(jobID: jobID)
        }
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
                guard try resolveContent(derivative.content) == derivative.content else {
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
                guard let readback = try readLabelArtifacts(binding.jobID),
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
            guard try resolveContent(content) == content else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        let finalTree = try checkedOriginalTree()
        let finalContentRootIdentity = try checkedContentRootIdentity()
        guard finalContentRootIdentity == contentRootIdentity,
              finalTree.tree == tree,
              finalTree.digest == initialTree.digest,
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

    /// A historical schema-2 cold Erase never opens the original SQLite as a
    /// SwiftData store. The exact original owner supplies the physical tree
    /// and content authority; only its operation-owned disposable copy supplies
    /// the ModelContext for the unchanged complete semantic validator.
    func validateOrResumeSchema2ColdRetainedSource(
        intent: EraseIntentV1,
        intentStore: EraseIntentStore,
        source: EraseSchema2ColdRetainedSourceV1,
        operation: EraseColdPreparationOperationV1
    ) async throws -> Bool {
        guard intent.schemaVersion == 2,
              intent.phase == .emptyGenerationPrepared
                || intent.phase == .pointerSwitched
                || intent.phase == .sessionActivated,
              source.generationID == intent.oldGenerationID,
              try intentStore.load() == intent else {
            throw EraseAllServiceError.invalidAuthority
        }
        try operation.requireSchema2ColdIntentStore(intentStore)
        try operation.requireSchema2ColdRetainedSource(source)
        try source.requireOriginalUnchanged()
        return try await generationFactory.validateOrResumeSchema2ColdRetainedSource(
            source: source, intent: intent,
            temporaryDirectoryURL: temporaryDirectoryURL,
            operation: operation,
            validate: { context, attempt in
                let validation = try EraseRetainedSourceValidationV1.acquireCold(
                    intent: intent, generationFactory: self.generationFactory,
                    intentStore: intentStore, source: source,
                    attempt: attempt, operation: operation)
                try self.validateFrozenGeneration(
                    id: intent.oldGenerationID,
                    modelContext: context,
                    generationRootURL: source.generationRootURL,
                    workspaceIdentity: source.workspaceIdentity,
                    authority: nil,
                    retainedEraseValidation: validation,
                    originalC05TransientWitness:
                        try source.checkedOriginalC05TransientWitness(),
                    coldRetainedSource: source)
            })
    }

    /// Each additional present frozen generation is read from its own exact
    /// held root. Its checked disposable context supplies the same complete
    /// frozen-row, history, content and export validation as the old source;
    /// the operation keeps every source and attempt through alias drain.
    func validateOrResumeSchema2ColdRetiredSource(
        intent: EraseIntentV1,
        intentStore: EraseIntentStore,
        source: EraseSchema2ColdRetiredSourceV1,
        operation: EraseColdPreparationOperationV1
    ) async throws -> Bool {
        guard intent.schemaVersion == 2,
              intent.phase == .pointerSwitched ||
                intent.phase == .sessionActivated,
              intent.generationIDsToDelete.contains(source.generationID),
              source.generationID != intent.oldGenerationID,
              source.generationID != intent.newGenerationID,
              try intentStore.load() == intent else {
            throw EraseAllServiceError.invalidAuthority
        }
        try operation.requireSchema2ColdIntentStore(intentStore)
        try operation.requireSchema2ColdRetiredSource(source)
        try source.requireOriginalUnchanged()
        return try await generationFactory.validateOrResumeSchema2ColdRetiredSource(
            source: source, intent: intent,
            temporaryDirectoryURL: temporaryDirectoryURL,
            operation: operation,
            validate: { context, attempt in
                let validation = try EraseRetainedSourceValidationV1
                    .acquireColdRetired(intent: intent,
                        generationFactory: self.generationFactory,
                        intentStore: intentStore, source: source,
                        attempt: attempt, operation: operation,
                        modelContext: context)
                try self.validateFrozenGeneration(
                    id: source.generationID,
                    modelContext: context,
                    generationRootURL: source.generationRootURL,
                    workspaceIdentity: validation.workspaceIdentity,
                    authority: nil,
                    retainedEraseValidation: validation,
                    originalC05TransientWitness:
                        try source.checkedOriginalC05TransientWitness(),
                    coldRetainedSource: source)
            })
    }

    /// The first retained Registry G/Support EX and installed-name census
    /// classifies every other frozen ID. On retry this uses the same map and
    /// each same operation-owned private attempt; it never opens a second
    /// root or adopts a post-await inventory as a fresh baseline.
    func validateOrResumeSchema2ColdRetiredSources(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        let (continuation, store, manifest, exclusion, registry, activity) =
            try operation.requireSchema2ColdRetiredContinuation()
        let identity = try store.schema2ColdSupportIdentity(
            operation: operation)
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try manifest.requireCapturedOperationsOwners(
            continuation.operationsNames, operation: operation)
        guard try store.load() == continuation.intent,
              try store.loadPreparation() == continuation.preparation,
              try registry.observeEraseSchema2ColdRegistry(
                operation: operation, activity: activity)
                == continuation.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if !operation.hasSchema2ColdRetiredSourceMap {
            _ = try manifest.captureRetainedRetiredSources(
                intent: continuation.intent,
                preparation: continuation.preparation,
                operation: operation)
        }
        let sources = try operation.requireSchema2ColdRetiredSourceMap()
        for id in sources.keys.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }) {
            guard let source = sources[id],
                  try await validateOrResumeSchema2ColdRetiredSource(
                    intent: continuation.intent, intentStore: store,
                    source: source, operation: operation) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try exclusion.requireHeld(expectedDevice: identity.device,
                expectedInode: identity.inode)
            try manifest.requireCapturedOperationsOwners(
                continuation.operationsNames, operation: operation)
            guard try store.load() == continuation.intent,
                  try store.loadPreparation() == continuation.preparation,
                  try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == continuation.registryTokens else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try source.requireOriginalUnchanged()
        }
        try operation.completeSchema2ColdRetiredValidation(
            intent: continuation.intent)
        _ = try operation.requireSchema2ColdValidatedGenerationTrees()
    }

}

extension EraseAllService {
    /// Expose only this exact preactivation graph predicate to the retained
    /// cold Factory constructor. The implementation remains the same private
    /// semantic check used before the pointer effect.
    static func requireSchema2ColdPreactivationGraph(
        context: ModelContext,
        generationID: UUID,
        identity: WorkspaceReplicaIdentityV1,
        switched: EraseIntentV1
    ) throws {
        try requireEmptyErasePreactivationGraph(
            context: context, generationID: generationID,
            identity: identity, switched: switched)
    }

    /// Complete one historical schema-2 pointer-switched cut on its first
    /// retained cold operation. The target private proof precedes either
    /// current/retired effect, then an actual target ModelContainer/session
    /// with a checked reader precedes the durable intent phase CAS. This is
    /// not cleanup completion or writer publication.
    func advanceSchema2ColdPointerSwitchedPhase(
        operation: EraseColdPreparationOperationV1
    ) throws -> StoreGenerationSession {
        let (continuation, store, manifest, source,
            registry, activity) = try operation
                .requireSchema2ColdPreactivationContinuation()
        let intent = continuation.intent
        let snapshot = continuation.generation
        guard intent.schemaVersion == 2,
              intent.phase == .pointerSwitched,
              try store.load() == intent,
              try store.loadPreparation() == continuation.preparation,
              let completed = operation.schema2ColdTargetValidationAttempt,
              completed.isCheckedClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if let activated = operation.schema2ColdActivatedTargetAttempt {
            try operation.requireSchema2ColdActivatedTargetAttempt(activated)
            try operation.requireSchema2ColdTargetReaderTokenCensus(
                registry: registry)
        } else {
            guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == continuation.registryTokens else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try completed.requireCompletedPreactivation(
            source: source, snapshot: snapshot, intent: intent)
        try manifest.requireCapturedOperationsOwners(
            continuation.operationsNames, operation: operation)
        if operation.hasSchema2ColdTargetPointerPublished {
            _ = try operation.requireSchema2ColdPreactivationValidated(
                source: source, intent: intent)
            try manifest.requireSchema2ColdOwnPublishedSnapshot(
                snapshot, intent: intent, operation: operation)
        } else {
            let firstCut = try manifest.observeAllowedCurrentCut(
                intent: intent, operation: operation)
            switch firstCut {
            case .old:
                try operation.publishSchema2ColdTargetPointer(
                    intent: intent, source: source)
            case .target:
                try operation.retainSchema2ColdAlreadyPublishedTargetPointer(
                    intent: intent, source: source)
            }
        }
        if operation.hasSchema2ColdFinalRetiredPublished {
            try manifest.requireSchema2ColdFinalPointerCut(
                intent: intent, operation: operation)
        } else {
            let priorRetired = intent.generationIDsToDelete
                .filter { $0 != intent.oldGenerationID }
            if snapshot.retiredGenerationIDs == priorRetired {
                try operation.publishSchema2ColdFinalRetired(
                    intent: intent, source: source)
            } else if snapshot.retiredGenerationIDs
                == intent.generationIDsToDelete {
                try operation.retainSchema2ColdAlreadyFinalRetired(
                    intent: intent, source: source)
            } else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: operation)
        let session = try generationFactory
            .openSchema2ColdActivatedTargetSession(
                source: source, snapshot: snapshot,
                intent: intent, registry: registry,
                activity: activity, operation: operation)
        guard try operation.requireSchema2ColdActivatedTargetSession()
                === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        traceErasePhase("recovery.schema2.target-live-session")
        try inject(.beforeSessionActivation)
        guard try operation.requireSchema2ColdActivatedTargetSession()
                === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try inject(.afterSessionActivation)
#if DEBUG
        schema2ColdBeforeSessionPhaseCASForTesting?(session)
#endif
        traceErasePhase("recovery.schema2.p-forward.before-cas")
        try inject(.beforeSessionPhaseWrite)
        let activated = intent.advancing(to: .sessionActivated)
        try store.replaceSchema2ColdPointerPhase(
            expected: intent, with: activated,
            operation: operation)
        traceErasePhase("recovery.schema2.p-forward.cas-settled")
        guard try operation.requireSchema2ColdPointerPhasePublished(
                expected: activated, store: store) === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        traceErasePhase("recovery.schema2.p-forward.router-proof")
        try manifest.projectSchema2ColdRetainedSourcesAfterOwnPhaseCAS(
            firstIntent: intent, replacement: activated,
            store: store, operation: operation)
        traceErasePhase("recovery.schema2.p-forward.manifest-projected")
        try inject(.afterSessionPhaseWrite)
        traceErasePhase("recovery.schema2.p-forward.method-complete")
        return session
    }

    /// A fresh authenticated R entry has a different durable first cut from
    /// the P operation. It opens one actual target session with a checked
    /// reader, then settles only the displaced exact P temporary. It never
    /// reruns pointer publication or the P→R intent CAS.
    func advanceSchema2ColdActivatedEntry(
        operation: EraseColdPreparationOperationV1
    ) throws -> StoreGenerationSession {
        let (first, store, manifest, source, registry, activity) =
            try operation.requireSchema2ColdActivatedEntryContinuation()
        traceErasePhase("recovery.schema2.r-forward.continuation")
        guard first.intent.schemaVersion == 2,
              first.intent.phase == .sessionActivated,
              try store.load() == first.intent,
              try store.loadPreparation() == first.preparation,
              operation.hasSchema2ColdActivatedEntryValidated,
              let privateAttempt = operation
                .schema2ColdTargetValidationAttempt,
              privateAttempt.isCheckedClosed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if operation.schema2ColdActivatedTargetAttempt == nil {
            guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == first.registryTokens else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        } else {
            try operation.requireSchema2ColdTargetReaderTokenCensus(
                registry: registry)
        }
        try privateAttempt.requireCompletedActivated(
            source: source, snapshot: first.generation,
            intent: first.intent)
        traceErasePhase("recovery.schema2.r-forward.private-reproof")
        try manifest.requireCapturedOperationsOwners(
            first.operationsNames, operation: operation)
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: first.intent, operation: operation)
        traceErasePhase("recovery.schema2.r-forward.final-pointer")
        let session = try generationFactory
            .openSchema2ColdActivatedTargetSession(
                source: source, snapshot: first.generation,
                intent: first.intent, registry: registry,
                activity: activity, operation: operation)
        traceErasePhase("recovery.schema2.r-forward.live-open")
        guard try operation.requireSchema2ColdActivatedTargetSession()
                === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        traceErasePhase("recovery.schema2.r-forward.session-bound")
        if !operation.hasSchema2ColdActivatedEntryTempSettled {
            try store.settleSchema2ColdActivatedEntryTemporary(
                pending: first.intent.advancing(to: .pointerSwitched),
                published: first.intent, operation: operation)
        }
        guard try operation.requireSchema2ColdActivatedEntryTempSettled(
                store: store) === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        traceErasePhase("recovery.schema2.r-forward.temp-settled")
#if DEBUG
        schema2ColdActivatedEntrySessionForTesting?(session)
#endif
        return session
    }

    /// A fresh R cut with a canonical prospective roster must never reopen
    /// a partially deleted original SQLite tree. The roster is first only
    /// data; the retained actual target session and complete checked global
    /// survivor prefix turn it into this operation's deletion authority.
    private func resumeSchema2ColdPublishedRosterReplay(
        observed: EraseColdExistingControlObservationV1.Snapshot,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        snapshot: EraseSchema2ColdTargetSnapshotV1,
        targetSource: EraseSchema2ColdTargetSourceV1,
        operationsNames: Set<String>,
        registryTokens: [GenerationLeaseTokenV1],
        phaseCut: EraseIntentStore.Schema2ColdPhaseCASCutV1,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1,
        registry: GenerationLeaseRegistryV1,
        activity: GenerationTemporalActivityHandleV1,
        operation: EraseColdPreparationOperationV1
    ) async throws {
        guard case .published(displacedBytes: nil,
                displacedFact: nil) = phaseCut,
              snapshot.currentPointer == snapshot.pointer,
              try registry.observeEraseSchema2ColdRegistry(
                  operation: operation, activity: activity)
                  == registryTokens else {
            throw EraseAllServiceError.invalidAuthority
        }
        let roster = try manifest.decodeSchema2ColdObservedRoster(
            intent: intent, preparation: preparation,
            store: store, operation: operation)
        try operation.retainSchema2ColdDecodedRosterForReplay(
            roster, store: store)
        try operation.retainSchema2ColdActivatedEntryContinuation(
            EraseSchema2ColdActivatedEntryContinuationV1(
                observed: observed, intent: intent,
                preparation: preparation, generation: snapshot,
                operationsNames: operationsNames,
                registryTokens: registryTokens,
                phaseCut: phaseCut, replayRoster: roster))
        guard try await generationFactory
            .validateOrResumeSchema2ColdTarget(
                source: targetSource, snapshot: snapshot,
                intent: intent,
                temporaryDirectoryURL: temporaryDirectoryURL,
                operation: operation),
              let completed = operation
                .schema2ColdTargetValidationAttempt else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try operation.bindSchema2ColdActivatedEntryValidated(
            snapshot: snapshot, attempt: completed)
        _ = try advanceSchema2ColdActivatedEntry(operation: operation)
        try admitOrRequireSchema2ColdObservedRoster(
            operation: operation, roster: roster,
            intent: intent, preparation: preparation,
            store: store, manifest: manifest)
        try await advanceSchema2ColdRosteredGenerationDeletion(
            operation: operation, roster: roster,
            store: store, manifest: manifest)
    }

    private func admitOrRequireSchema2ColdObservedRoster(
        operation: EraseColdPreparationOperationV1,
        roster: EraseSchema2ColdDeletionRosterV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws {
        if operation.hasSchema2ColdPublishedRoster {
            let held = try operation.requireSchema2ColdPublishedRoster(
                store: store)
            guard held.canonicalBytes == roster.canonicalBytes,
                  held.canonicalSHA256 == roster.canonicalSHA256,
                  held.recordFileFact == roster.recordFileFact else {
                throw EraseAllServiceError.invalidAuthority
            }
            return
        }
        let executor: EraseSchema2ColdCheckedDeletionExecutorV1
        if operation.hasSchema2ColdDeletionExecutor {
            executor = try operation.requireSchema2ColdDeletionExecutor(
                roster: roster, store: store)
        } else {
            let created = EraseSchema2ColdCheckedDeletionExecutorV1(
                roster: roster, operation: operation)
            try operation.retainSchema2ColdDeletionExecutor(
                created, roster: roster, store: store)
            executor = created
        }
        _ = try manifest.admitExistingSchema2ColdDeletionRoster(
            roster, intent: intent, preparation: preparation,
            store: store, operation: operation, executor: executor)
    }

    /// Retry retains the first R bytes, original owner, private target copy,
    /// actual reader allocation, and session. No new control or Registry
    /// constructor is admitted after an interrupted effect.
    func resumeSchema2ColdActivatedEntry(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        let (first, store, manifest, source, registry, activity) =
            try operation.requireSchema2ColdActivatedEntryContinuation()
        guard first.intent.phase == .sessionActivated,
              try store.load() == first.intent,
              try store.loadPreparation() == first.preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if !operation.hasSchema2ColdActivatedEntryValidated {
            try manifest.requireSchema2ColdTargetSnapshot(
                first.generation, intent: first.intent,
                operation: operation)
            guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == first.registryTokens,
                  try await generationFactory
                    .validateOrResumeSchema2ColdTarget(
                        source: source, snapshot: first.generation,
                        intent: first.intent,
                        temporaryDirectoryURL: temporaryDirectoryURL,
                        operation: operation),
                  let completed = operation
                    .schema2ColdTargetValidationAttempt else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.bindSchema2ColdActivatedEntryValidated(
                snapshot: first.generation, attempt: completed)
        } else {
            _ = try operation.requireSchema2ColdActivatedEntryValidated(
                source: source, intent: first.intent)
        }
        _ = try advanceSchema2ColdActivatedEntry(operation: operation)
        try await continueSchema2ColdActivatedEntryAfterSession(
            operation: operation)
    }

    /// Shared first-entry and same-owner retry tail. The caller has already
    /// proved the actual target session and settled the exact P temporary;
    /// this helper never starts a second Service frame or opens a new owner.
    private func continueSchema2ColdActivatedEntryAfterSession(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        let (first, store, manifest, _, _, _) =
            try operation.requireSchema2ColdActivatedEntryContinuation()
        guard first.intent.phase == .sessionActivated,
              try store.load() == first.intent,
              try store.loadPreparation() == first.preparation,
              operation.hasSchema2ColdActivatedEntryValidated else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        _ = try operation.requireSchema2ColdActivatedEntryTempSettled(
            store: store)
        traceErasePhase("recovery.schema2.r-forward.entry-complete")
        traceErasePhase("recovery.schema2.r-forward.roster-enter")
        let roster: EraseSchema2ColdDeletionRosterV1
        if let observed = first.replayRoster {
            try admitOrRequireSchema2ColdObservedRoster(
                operation: operation, roster: observed,
                intent: first.intent,
                preparation: first.preparation,
                store: store, manifest: manifest)
            roster = observed
        } else {
            roster = try publishOrRequireSchema2ColdDeletionRoster(
                operation: operation, intent: first.intent,
                preparation: first.preparation, store: store,
                manifest: manifest)
        }
        traceErasePhase("recovery.schema2.r-forward.roster-published")
        traceErasePhase("recovery.schema2.r-forward.notification-enter")
        try await advanceSchema2ColdRosteredGenerationDeletion(
            operation: operation, roster: roster,
            store: store, manifest: manifest)
        // The rostered generation cleanup is complete. Later auxiliary,
        // completion-receipt, and ready publication retain separate owners.
        throw EraseAllServiceError.recoveryRequired
    }

    /// A same-operation retry after the exact P→R publication may re-enter
    /// only with the original preparation, held target session and checked
    /// reader. The later cold cleanup owner consumes this typed continuation;
    /// no fresh ordinary Store/Registry constructor is permitted here.
    func resumeSchema2ColdActivatedForward(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        let (intent, store, session, preparation, manifest,
            source, registry, _) = try operation
                .requireSchema2ColdActivatedForwardContinuation()
        guard intent.schemaVersion == 2,
              intent.phase == .sessionActivated,
              preparation.c05JobDrainV3 == nil,
              try store.load() == intent,
              try operation.requireSchema2ColdPointerPhasePublished(
                  expected: intent, store: store) === session else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try manifest.requireSchema2ColdFinalPointerCut(
            intent: intent, operation: operation)
        try operation.requireSchema2ColdTargetReaderTokenCensus(
            registry: registry)
        try operation.requireSchema2ColdTargetSource(source)
        let roster = try publishOrRequireSchema2ColdDeletionRoster(
            operation: operation, intent: intent,
            preparation: preparation, store: store,
            manifest: manifest)
        try await advanceSchema2ColdRosteredGenerationDeletion(
            operation: operation, roster: roster,
            store: store, manifest: manifest)
        // Auxiliary and ready publication remain separately bound after
        // exact checked rostered generation cleanup.
        throw EraseAllServiceError.recoveryRequired
    }

    /// Only the first operation may publish a prospective deletion record.
    /// A retry reuses its exact checked publication receipt; it cannot mint a
    /// second roster from the generation tree after any unlink.
    private func publishOrRequireSchema2ColdDeletionRoster(
        operation: EraseColdPreparationOperationV1,
        intent: EraseIntentV1,
        preparation: ErasePreparationV2,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) throws -> EraseSchema2ColdDeletionRosterV1 {
        if operation.hasSchema2ColdPublishedRoster {
            return try operation.requireSchema2ColdPublishedRoster(
                store: store)
        }
        let roster = try manifest.publishSchema2ColdDeletionRoster(
            intent: intent, preparation: preparation,
            store: store, operation: operation)
        try operation.requireSchema2ColdRosterStepOwner(
            roster: roster, store: store)
        return roster
    }

    /// Every step is derived from the same canonical postorder record. The
    /// Manifest owner brackets the concrete Factory executor with held
    /// generations/Erase/EX/G proofs and projects only a checked receipt.
    private func advanceSchema2ColdRosteredGenerationDeletion(
        operation: EraseColdPreparationOperationV1,
        roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) async throws {
        // The same retained notification owner performs real OS removal and
        // absence readback before any generation directory is unlinked.
        try await requireSchema2ColdNotificationsDrained(
            operation: operation, roster: roster,
            store: store, manifest: manifest)
        try operation.requireSchema2ColdNotificationDrained(
            store: store)
        if !operation.hasSchema2ColdDeletionSourcesClosed {
            try operation.closeSchema2ColdValidatedSourcesForDeletion(
                roster: roster, store: store)
        }
        let executor: EraseSchema2ColdCheckedDeletionExecutorV1
        if operation.hasSchema2ColdDeletionExecutor {
            executor = try operation.requireSchema2ColdDeletionExecutor(
                roster: roster, store: store)
        } else {
            let created = EraseSchema2ColdCheckedDeletionExecutorV1(
                roster: roster, operation: operation)
            try operation.retainSchema2ColdDeletionExecutor(
                created, roster: roster, store: store)
            executor = created
        }
        var progress = try manifest.requireSchema2ColdDeletionProgress(
            roster: roster, store: store, operation: operation)
#if DEBUG
        if progress == 0, try roster.step(at: progress) != nil {
            try schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting?()
        }
#endif
        while try roster.step(at: progress) != nil {
            try operation.requireSchema2ColdNotificationDrained(
                store: store)
            let receipt = try manifest.advanceSchema2ColdRosteredDeletion(
                roster: roster, store: store,
                operation: operation, executor: executor)
            guard receipt.beforeDeletedCount == progress,
                  receipt.afterDeletedCount == progress + 1,
                  receipt.checkedSettled else {
                throw EraseAllServiceError.invalidAuthority
            }
            progress = receipt.afterDeletedCount
#if DEBUG
            if receipt.step.path.isEmpty {
                try schema2ColdAfterGenerationUnlinkForTesting?(
                    receipt.step.generationID, progress)
            }
#endif
            await Task.yield()
            guard try manifest.requireSchema2ColdDeletionProgress(
                    roster: roster, store: store,
                    operation: operation) == progress else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    private func requireSchema2ColdNotificationsDrained(
        operation: EraseColdPreparationOperationV1,
        roster: EraseSchema2ColdDeletionRosterV1,
        store: EraseIntentStore,
        manifest: EraseSchema2ColdManifestOwnerV1
    ) async throws {
        let intent = try store.load()
        guard let intent, intent.phase == .sessionActivated,
              roster.record.eraseID
                == intent.eraseID.uuidString.lowercased() else {
            throw EraseAllServiceError.invalidAuthority
        }
        guard let preparation = try store.loadPreparation() else {
            throw EraseAllServiceError.invalidAuthority
        }
        try operation.requireSchema2ColdOriginalControls(
            intent: intent, preparation: preparation)
        traceErasePhase("recovery.schema2.r-forward.notification-controls")
        if operation.hasSchema2ColdNotificationDrainReceipt {
            try operation.requireSchema2ColdNotificationDrained(
                store: store)
            return
        }
        let control: any Schema2ColdNotificationEraseControlV1
        let source: EraseSchema2ColdNotificationSourceV1
        if operation.hasSchema2ColdNotificationControl {
            (control, source) = try operation
                .requireSchema2ColdNotificationControl(store: store)
        } else {
            source = try manifest.captureSchema2ColdNotificationOwner(
                intent: intent, preparation: preparation,
                operation: operation)
            let created = EraseSchema2ColdNotificationControlV1(
                source: source, operation: operation)
            #if DEBUG
            created.temporaryFaultForTesting =
                schema2ColdNotificationTemporaryFaultForTesting
            #endif
            try operation.retainSchema2ColdNotificationControl(
                created, source: source, store: store)
            control = created
        }
        traceErasePhase("recovery.schema2.r-forward.notification-owner")
        traceErasePhase("recovery.schema2.r-forward.notification-system")
        let receipt = try await DeviceLocalNotificationOwnerV1
            .eraseSchema2Cold(control: control,
                system: notificationSystem,
                operationID: intent.eraseID)
        traceErasePhase("recovery.schema2.r-forward.notification-drained")
        try operation.retainSchema2ColdNotificationDrainReceipt(
            receipt, control: control, source: source,
            store: store)
        try operation.requireSchema2ColdNotificationDrained(
            store: store)
    }

    /// Reuse only the first operation's target copy and held control frame.
    /// Router calls this before any new cold constructor after alias drain.
    func resumeSchema2ColdPreactivationTargetValidation(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        let (continuation, store, manifest, source,
            registry, activity) = try operation
                .requireSchema2ColdPreactivationContinuation()
        guard continuation.intent.phase == .pointerSwitched,
              try store.load() == continuation.intent,
              try store.loadPreparation() == continuation.preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        if operation.schema2ColdActivatedTargetAttempt != nil {
            try operation.requireSchema2ColdTargetReaderTokenCensus(
                registry: registry)
        } else {
            guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == continuation.registryTokens else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try manifest.requireCapturedOperationsOwners(
            continuation.operationsNames, operation: operation)
        if operation.hasSchema2ColdPreactivationValidated {
            _ = try operation.requireSchema2ColdPreactivationValidated(
                source: source, intent: continuation.intent)
        } else {
            try manifest.requireSchema2ColdTargetSnapshot(
                continuation.generation,
                intent: continuation.intent, operation: operation)
            guard try await generationFactory
                .validateOrResumeSchema2ColdPreactivationTarget(
                    source: source,
                    snapshot: continuation.generation,
                    intent: continuation.intent,
                    temporaryDirectoryURL: temporaryDirectoryURL,
                    operation: operation) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard let completed = operation
                .schema2ColdTargetValidationAttempt else {
                throw EraseAllServiceError.invalidAuthority
            }
            try operation.bindSchema2ColdPreactivationValidated(
                snapshot: continuation.generation, attempt: completed)
        }
        _ = try advanceSchema2ColdPointerSwitchedPhase(
            operation: operation)
        // The same first operation now holds a genuinely activated target
        // session and exact R intent. Separate typed cleanup consumes it.
        throw EraseAllServiceError.recoveryRequired
    }

    /// Resume only the same operation-retained private source attempt. The
    /// Router enters this path before any fresh control/store construction.
    /// Completing this read is not, by itself, a completed Erase receipt.
    func resumeSchema2ColdRetainedSourceValidation(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        let (continuation, store, manifest, source, exclusion,
            registry, activity) = try operation.requireSchema2ColdOriginalContinuation()
        let identity = try store.schema2ColdSupportIdentity(
            operation: operation)
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try manifest.requireCapturedOperationsOwners(
            continuation.operationsNames, operation: operation)
        guard try store.load() == continuation.intent,
              try store.loadPreparation() == continuation.preparation,
              try registry.observeEraseSchema2ColdRegistry(
                  operation: operation, activity: activity)
                == continuation.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try source.requireOriginalUnchanged()
        guard try await validateOrResumeSchema2ColdRetainedSource(
            intent: continuation.intent, intentStore: store,
            source: source, operation: operation) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try manifest.requireCapturedOperationsOwners(
            continuation.operationsNames, operation: operation)
        guard try registry.observeEraseSchema2ColdRegistry(
                operation: operation, activity: activity)
                == continuation.registryTokens,
              try store.load() == continuation.intent,
              try store.loadPreparation() == continuation.preparation else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try source.requireOriginalUnchanged()
        try operation.completeSchema2ColdOriginalValidation()
        try operation.retainSchema2ColdRetiredContinuation(
            EraseSchema2ColdRetiredContinuationV1(
                observed: continuation.observed,
                intent: continuation.intent,
                preparation: continuation.preparation,
                generation: continuation.generation,
                operationsNames: continuation.operationsNames,
                registryTokens: continuation.registryTokens,
                phaseCut: continuation.phaseCut))
        try await validateOrResumeSchema2ColdRetiredSources(
            operation: operation)
        if continuation.intent.phase == .pointerSwitched {
            let (same, targetSource) = try operation
                .requireSchema2ColdTargetAfterOriginal()
            guard same.intent == continuation.intent,
                  same.preparation == continuation.preparation,
                  same.generation.currentPointer
                    == continuation.generation.currentPointer,
                  same.generation.pointer == continuation.generation.pointer,
                  same.generation.manifest == continuation.generation.manifest,
                  same.generation.installedGenerationIDs
                    == continuation.generation.installedGenerationIDs,
                  same.generation.retiredGenerationIDs
                    == continuation.generation.retiredGenerationIDs else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.retainSchema2ColdPreactivationContinuation(
                EraseSchema2ColdPreactivationContinuationV1(
                    observed: continuation.observed,
                    intent: continuation.intent,
                    preparation: continuation.preparation,
                    generation: continuation.generation,
                    operationsNames: continuation.operationsNames,
                    registryTokens: continuation.registryTokens))
            guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == continuation.registryTokens,
                  try await generationFactory
                    .validateOrResumeSchema2ColdPreactivationTarget(
                        source: targetSource,
                        snapshot: continuation.generation,
                        intent: continuation.intent,
                        temporaryDirectoryURL: temporaryDirectoryURL,
                        operation: operation) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard let completed = operation
                .schema2ColdTargetValidationAttempt else {
                throw EraseAllServiceError.invalidAuthority
            }
            try operation.bindSchema2ColdPreactivationValidated(
                snapshot: continuation.generation,
                attempt: completed)
        }
        if continuation.intent.phase == .sessionActivated {
            let (same, targetSource) = try operation
                .requireSchema2ColdTargetAfterOriginal()
            guard same.intent == continuation.intent,
                  same.preparation == continuation.preparation,
                  same.generation.pointer == continuation.generation.pointer,
                  same.generation.manifest == continuation.generation.manifest,
                  same.generation.installedGenerationIDs
                    == continuation.generation.installedGenerationIDs,
                  same.generation.retiredGenerationIDs
                    == continuation.generation.retiredGenerationIDs else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.retainSchema2ColdTargetContinuation(
                EraseSchema2ColdTargetContinuationV1(
                    observed: continuation.observed,
                    intent: continuation.intent,
                    generation: continuation.generation,
                    operationsNames: continuation.operationsNames,
                    registryTokens: continuation.registryTokens))
            guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == continuation.registryTokens else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard try await generationFactory.validateOrResumeSchema2ColdTarget(
                    source: targetSource,
                    snapshot: continuation.generation,
                    intent: continuation.intent,
                    temporaryDirectoryURL: temporaryDirectoryURL,
                    operation: operation) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try exclusion.requireHeld(expectedDevice: identity.device,
                expectedInode: identity.inode)
            try manifest.requireCapturedOperationsOwners(
                continuation.operationsNames, operation: operation)
            guard try registry.observeEraseSchema2ColdRegistry(
                    operation: operation, activity: activity)
                    == continuation.registryTokens else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
    }

    /// A private retired copy may outlive one startup await while its weak
    /// SwiftData aliases drain. Resume the exact retained sources and then
    /// hand the same first snapshot to the already typed target continuation.
    func resumeSchema2ColdRetiredSourcesValidation(
        operation: EraseColdPreparationOperationV1
    ) async throws {
        try await operation.beginServiceFrame()
        defer { operation.endServiceFrame() }
        try await validateOrResumeSchema2ColdRetiredSources(
            operation: operation)
        let (continuation, source) = try operation
            .requireSchema2ColdTargetAfterRetiredValidation()
        let (same, store, manifest, exclusion, registry, activity) =
            try operation.requireSchema2ColdRetiredContinuation()
        guard same.intent == continuation.intent,
              same.preparation == continuation.preparation,
              same.generation.pointer == continuation.generation.pointer,
              same.generation.manifest == continuation.generation.manifest,
              same.registryTokens == continuation.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let identity = try store.schema2ColdSupportIdentity(
            operation: operation)
        try exclusion.requireHeld(expectedDevice: identity.device,
            expectedInode: identity.inode)
        try manifest.requireCapturedOperationsOwners(
            continuation.operationsNames, operation: operation)
        guard try registry.observeEraseSchema2ColdRegistry(
                operation: operation, activity: activity)
                == continuation.registryTokens else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        switch continuation.intent.phase {
        case .pointerSwitched:
            try operation.retainSchema2ColdPreactivationContinuation(
                EraseSchema2ColdPreactivationContinuationV1(
                    observed: continuation.observed,
                    intent: continuation.intent,
                    preparation: continuation.preparation,
                    generation: continuation.generation,
                    operationsNames: continuation.operationsNames,
                    registryTokens: continuation.registryTokens))
            guard try await generationFactory
                .validateOrResumeSchema2ColdPreactivationTarget(
                    source: source,
                    snapshot: continuation.generation,
                    intent: continuation.intent,
                    temporaryDirectoryURL: temporaryDirectoryURL,
                    operation: operation),
                  let completed = operation
                    .schema2ColdTargetValidationAttempt else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.bindSchema2ColdPreactivationValidated(
                snapshot: continuation.generation,
                attempt: completed)
        case .sessionActivated:
            guard let cut = continuation.phaseCut,
                  case .published = cut else {
                throw EraseAllServiceError.invalidAuthority
            }
            try operation.retainSchema2ColdActivatedEntryContinuation(
                EraseSchema2ColdActivatedEntryContinuationV1(
                    observed: continuation.observed,
                    intent: continuation.intent,
                    preparation: continuation.preparation,
                    generation: continuation.generation,
                    operationsNames: continuation.operationsNames,
                    registryTokens: continuation.registryTokens,
                    phaseCut: cut, replayRoster: nil))
            guard try await generationFactory
                .validateOrResumeSchema2ColdTarget(
                    source: source,
                    snapshot: continuation.generation,
                    intent: continuation.intent,
                    temporaryDirectoryURL: temporaryDirectoryURL,
                    operation: operation),
                  let completed = operation
                    .schema2ColdTargetValidationAttempt else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try operation.bindSchema2ColdActivatedEntryValidated(
                snapshot: continuation.generation,
                attempt: completed)
        default:
            throw EraseAllServiceError.invalidAuthority
        }
    }

}

private extension EraseAllService {
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
        authority: StoreRestoreGenerationAuthority,
        originalAuxiliaryOperation: EraseRouterOperationV1? = nil
    ) throws -> StoreGenerationSession {
        guard let oldPointer = intent.oldPointer,
              let targetPointer = intent.targetPointer else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try generationFactory.requirePublishedEmptyEraseGeneration(
            oldPointer: oldPointer,
            targetPointer: targetPointer,
            expectedEmptyLedger: try expectedEmptyLedger(intent),
            authority: authority,
            originalRetainedEraseOperation: originalAuxiliaryOperation
        )
    }

    func discardPreparation(
        _ preparation: ErasePreparationV2,
        authority: StoreRestoreGenerationAuthority,
        reproveBeforeDestructiveEffect: (@MainActor () throws -> Void)? = nil
    ) throws {
        try reproveBeforeDestructiveEffect?()
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
            diagnosticPhase: eraseFactoryPhaseDiagnostic,
            reproveBeforeDestructiveEffect: reproveBeforeDestructiveEffect
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
    private var originalScratchCleanupReceipt: OriginalEraseScratchCleanupReceiptV1?
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
              scratchOwner == nil, originalScratchCleanupReceipt == nil,
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

    /// The same original diagnostics consume the actual private effect
    /// receipt instead of requiring a new ordinary Scratch descriptor owner.
    /// Source/Search/unrelated-tree and final named-absence checks are retained.
    @MainActor
    func afterOriginalScratchCleanup(
        _ receipt: OriginalEraseScratchCleanupReceiptV1,
        operation: EraseRouterOperationV1
    ) throws {
        try lock.withLock {
            guard stage == .searchPublished, self.operation === operation,
                  scratchOwner == nil, originalScratchCleanupReceipt == nil,
                  receipt.operationID == operation.operationID else {
                throw EraseAllServiceError.invalidAuthority
            }
            // Retain concrete actual settlement before later proof can fail.
            originalScratchCleanupReceipt = receipt
            do {
                try receipt.requireCheckedSettlement()
                guard receipt.finalImage.scratch == nil,
                      receipt.finalImage.ingress == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try requireSearchPublished()
                try requireSourceUnchanged()
                try requireUnrelatedOperationsUnchanged()
                try auxiliary.requireOriginalEraseOtherAuxiliaryUnchangedForTesting(
                    auxiliaryOrigin,
                    allowing: [LocalSearchIndexStoreV1.directoryName])
                let now = try auxiliary.originalEraseEmptyScratchStateForTesting()
                guard now.operationsDevice == scratchOrigin.operationsDevice,
                      now.operationsInode == scratchOrigin.operationsInode,
                      now.scratchDevice == nil, now.scratchInode == nil else {
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

    @MainActor
    func requirePreparedTransition() throws {
        try lock.withLock {
            guard stage == .exchangePublished,
                  exchangeOwner != nil,
                  scratchOwner != nil || originalScratchCleanupReceipt != nil,
                  exchangeExpectedBytes != nil,
                  notificationAfterSuccess != nil,
                  oldPointer != nil, sourceLedger != nil,
                  sourceManifest != nil, controlsPublished != nil,
                  targetGenerationID != nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            if let originalScratchCleanupReceipt {
                guard originalScratchCleanupReceipt.operationID == operation.operationID else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try originalScratchCleanupReceipt.requireCheckedSettlement()
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
        try validateActivityContractEraseClosure(modelContext: session.modelContext)
    }

    func validateActivityContractEraseClosure(
        modelContext: ModelContext
    ) throws {
        guard try modelContext.fetchCount(FetchDescriptor<ActivitySessionEnvelopeRow>()) == 0,
              try modelContext.fetchCount(FetchDescriptor<ActivityStateTransitionRow>()) == 0,
              try modelContext.fetchCount(FetchDescriptor<InstallationTaskResultRow>()) == 0,
              try modelContext.fetchCount(FetchDescriptor<InstallationAsBuiltSnapshotRow>()) == 0,
              try modelContext.fetchCount(FetchDescriptor<PunchReviewBasisSnapshotRow>()) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try C47ActivityContractKernelDeletionEnrollmentV2.validate()
    }

    func validateImportBulkEraseClosure(session: StoreGenerationSession) throws {
        try validateImportBulkEraseClosure(modelContext: session.modelContext)
    }

    func validateImportBulkEraseClosure(modelContext: ModelContext) throws {
        guard try modelContext.fetchCount(FetchDescriptor<ImportMappingProfileRowV1>()) == 0,
              try modelContext.fetchCount(FetchDescriptor<BulkSessionRowV1>()) == 0,
              try modelContext.fetchCount(FetchDescriptor<BulkCommitReceiptRowV1>()) == 0 else {
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
/// Scalar results from the genuine post-close owner. These are observations,
/// never capabilities or substitute cleanup/admission results.
struct ErasePostCloseSourceControlsReadbackV1 {
    let sameOwnerSourceValidated: Bool
    let closedAuthorityReaderRefused: Bool
    let foreignReceiptRefused: Bool?
    let foreignBindingRefused: Bool?
}

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
    private enum Phase: Equatable { case prepared, generationsRemoved, manifestPreserved, authorityClosed, notificationClosed, removingNamespace, namespaceRemoved,
        preferencesPrepared, diagnosticsVerified, phaseWritten, auxiliaryRemoved, preparationRemoved,
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
    private let originalNotificationTerminalClose:
        OriginalEraseNotificationTerminalCloseWitnessV1?
    private let originalAuxiliaryRetirementData:
        EraseIntentStore.OriginalAuxiliaryRetirementDataV1?
    private let userDefaults: UserDefaults
    private let defaultsDomainName: String
    private let fileManager: FileManager
    private let failureInjection: EraseAllFailureInjection?
    private let reservation: AppAccessGateV1.EraseAdoptionToken?
    private var exclusion: EraseRetirementExclusionV1?
    private(set) var retirement: EraseSessionRetirementV1?
    private(set) var proof: ErasedRegistryRetirementProofV1?
    private var terminalAuthorityClose: EraseGenerationAuthorityTerminalCloseReceiptV1?
    private var receipt: CompletedEraseReceiptV1?
    // Captured aliases remain subject to the actual weak drain before delivery.
    private var completion: (@MainActor (CompletedEraseReceiptV1) -> Void)?
    private var diagnosticsZero: Data?
    private var phase: Phase = .prepared
    private var running = false

    func requireTerminalAuthorityCloseAdmission(
        authority expectedAuthority: StoreRestoreGenerationAuthority,
        proof expectedProof: ErasedRegistryRetirementProofV1
    ) throws {
        guard running, phase == .manifestPreserved,
              authority === expectedAuthority, proof === expectedProof,
              terminalAuthorityClose == nil,
              let retirement, retirement.ownsProof(expectedProof),
              exclusion != nil, binding == expectedProof.binding else {
            throw EraseAllServiceError.invalidAuthority
        }
        try expectedProof.requireTerminalAuthorityCloseAdmission()
    }
#if DEBUG
    private var interruptedLateFault: EraseAllFailurePoint?
    private var coldCleanupProofObservationForTesting: (@MainActor (String) -> Void)?
    private var beforeOriginalAuxiliaryRetirementValidationForTesting:
        (@MainActor () throws -> Void)?

    fileprivate func installOriginalAuxiliaryRetirementHookForTesting(
        _ hook: @escaping @MainActor () throws -> Void
    ) throws {
        guard phase == .prepared,
              beforeOriginalAuxiliaryRetirementValidationForTesting == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        beforeOriginalAuxiliaryRetirementValidationForTesting = hook
    }

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

    private var postCloseSourceForeignOwnerForTesting: ErasedRegistryRetirementProofV1?
    private var afterTerminalSourceValidationForTesting:
        (@MainActor (ErasePostCloseSourceControlsReadbackV1) throws -> Void)?

    fileprivate func installPostCloseSourceControlsHookForTesting(
        foreignOwner: ErasedRegistryRetirementProofV1?,
        hook: @escaping @MainActor (ErasePostCloseSourceControlsReadbackV1) throws -> Void
    ) throws {
        guard phase == .prepared, postCloseSourceForeignOwnerForTesting == nil,
              afterTerminalSourceValidationForTesting == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        postCloseSourceForeignOwnerForTesting = foreignOwner
        afterTerminalSourceValidationForTesting = hook
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
        originalNotificationTerminalClose:
            OriginalEraseNotificationTerminalCloseWitnessV1? = nil,
        originalAuxiliaryRetirementData:
            EraseIntentStore.OriginalAuxiliaryRetirementDataV1? = nil,
        userDefaults: UserDefaults, defaultsDomainName: String, fileManager: FileManager,
        failureInjection: EraseAllFailureInjection?, reservation: AppAccessGateV1.EraseAdoptionToken?,
        completion: (@MainActor (CompletedEraseReceiptV1) -> Void)?) {
        self.binding = binding; self.intent = intent; self.factory = factory
        self.authority = authority; self.auxiliary = auxiliary; self.intentStore = intentStore
        self.observation = observation; self.manifestScope = manifestScope; self.targetReader = targetReader
        self.diagnosticsStore = diagnosticsStore; self.notificationControl = notificationControl
        self.originalNotificationTerminalClose = originalNotificationTerminalClose
        self.originalAuxiliaryRetirementData = originalAuxiliaryRetirementData
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
        guard phase != .closeUncertain else { throw EraseAllServiceError.invalidAuthority }
#if DEBUG
        guard phase != .abandonmentPending, phase != .abandoned,
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
        if phase == .manifestPreserved {
            do {
                let completedClose = try authority.closeCheckedForEraseRetirement(
                    cleanup: self, proof: proof)
#if DEBUG
                print("C46_ERASE_ADVANCE_V1 stage=authority-close-returned")
#endif
                try proof.retainTerminalAuthorityClose(completedClose,
                    cleanup: self, authority: authority)
                terminalAuthorityClose = completedClose
#if DEBUG
                if let hook = afterTerminalSourceValidationForTesting {
                    // Clear before invocation. No retry repeats the probes or
                    // mutation, and no callback return replaces fresh drain.
                    afterTerminalSourceValidationForTesting = nil
                    let observed = try proof.postCloseSourceControlsReadbackForTesting(
                        authority: authority,
                        pointerData: manifestScope.postClosePointerDataForTesting,
                        foreignOwner: postCloseSourceForeignOwnerForTesting)
                    try hook(observed)
                }
#endif
                phase = .authorityClosed
            } catch {
                if authority.eraseRetirementTerminalCloseAttempted {
                    phase = .closeUncertain
                }
                throw error
            }
        }
        let ratingStore = PreferencesAdapterV1(defaults: userDefaults)
        if phase == .authorityClosed {
            guard terminalAuthorityClose?.matches(proof: proof,
                cleanup: self, authority: authority) == true else {
                throw EraseAllServiceError.invalidAuthority
            }
            try AppLockNotificationTransactionFenceV1.perform {
                try notificationControl.verifyNotificationStorage()
                guard try notificationControl.loadControl() == nil,
                      try notificationControl.loadPrivateNotificationMapping() == nil else {
                    throw EraseAllServiceError.recoveryRequired
                }
                if let originalNotificationTerminalClose {
                    var closeStarted = false
                    do {
                        try proof.requireOriginalNotificationTerminalCloseAdmission()
                        try originalNotificationTerminalClose.requireBeforeClose(
                            control: notificationControl,
                            eraseID: intent.eraseID)
                        try originalNotificationTerminalClose.beginClose()
                        closeStarted = true
                        try notificationControl.closeCheckedForOriginalErase()
                        try originalNotificationTerminalClose.finishCheckedClose(
                            control: notificationControl)
                        phase = .notificationClosed
                    } catch {
                        if closeStarted { phase = .closeUncertain }
                        throw error
                    }
                } else {
#if DEBUG
                print("C46_ERASE_ADVANCE_V1 stage=namespace-begin-enter")
#endif
                try proof.beginFrozenTargetRemoval(using: auxiliary)
                phase = .removingNamespace
                }
            }
        }
        if phase == .notificationClosed {
            guard let originalNotificationTerminalClose else {
                throw EraseAllServiceError.invalidAuthority
            }
            try originalNotificationTerminalClose.requireClosed(
                control: notificationControl, eraseID: intent.eraseID)
            try proof.requireOriginalNotificationTerminalCloseAdmission()
            try AppLockNotificationTransactionFenceV1.perform {
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
#if DEBUG
            // Clear before firing. Every freshness check below runs after this
            // hostile seam; the hook supplies neither a permit nor an outcome.
            if let hook = beforeOriginalAuxiliaryRetirementValidationForTesting {
                beforeOriginalAuxiliaryRetirementValidationForTesting = nil
                try hook()
            }
            print("ORIGINAL_AUX_RETIREMENT_V1 stage=entry")
#endif
            try proof.requireNamespaceAbsent()
            guard let diagnosticsZero else { throw EraseAllServiceError.invalidAuthority }
            try auxiliary.verifyTargetsRemovedExceptDiagnostics()
            try auxiliary.verifyDiagnostics(expectedData: diagnosticsZero)
            try intentStore.removeOriginalAuxiliaryAfterRegistryRetirement(
                expected: completed, retirement: proof, data: originalAuxiliaryRetirementData)
            phase = .auxiliaryRemoved
#if DEBUG
            print("ORIGINAL_AUX_RETIREMENT_V1 stage=complete")
#endif
        }
        if phase == .auxiliaryRemoved {
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
    /// Initial and retained live forward preparation share the same checked
    /// Search writer/publication before notification. Cached actor state is
    /// discarded only after an actual publication or its checked reproof.
    func prepareOriginalEraseCheckedSearch(
        _ activated: EraseIntentV1,
        operation: EraseRouterOperationV1,
        intentStore: EraseIntentStore,
        coordinator: StoreSessionCoordinator
    ) async throws {
        guard activated.schemaVersion == 2,
              activated.phase == .sessionActivated,
              let oldPointer = activated.oldPointer else {
            throw EraseAllServiceError.invalidAuthority
        }
#if DEBUG
        traceErasePhase("original.search.canonical-binding.enter")
#endif
        let expectedSearchFile = coordinator
            .originalEraseAuxiliarySearchSupportURL
            .appendingPathComponent(LocalSearchIndexStoreV1.directoryName,
                isDirectory: true)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
            .standardizedFileURL
        guard await coordinator.searchIndexStore.originalEraseCanonicalFileURL()
                == expectedSearchFile,
              await coordinator.searchIndexStore
                .originalEraseCachedWorkspaceAllowsPurge(oldPointer.workspaceID)
        else {
            throw EraseAllServiceError.invalidAuthority
        }
        let continuation = try operation
            .prepareOriginalEraseAuxiliarySearchContinuation(
                expected: activated, store: intentStore,
                coordinator: coordinator)
        switch continuation {
        case .retained(let searchWriter):
#if DEBUG
            traceErasePhase("original.search.checked-publication.enter")
            if let originalColdExitFrame {
                let expected = try operation
                    .publishOriginalEraseAuxiliaryEmptySearch(
                        writer: searchWriter, store: intentStore,
                        coordinator: coordinator,
                        beforeCheckedEffect: {
                            try originalColdExitFrame.beforeSearchReplacement()
                        }, afterCheckedEffect: { bytes in
                            try originalColdExitFrame.afterSearchReplacement(
                                expectedBytes: bytes)
                        })
                guard !expected.isEmpty else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try originalColdExitFrame.requireSearchPublished()
            } else {
                _ = try operation.publishOriginalEraseAuxiliaryEmptySearch(
                    writer: searchWriter, store: intentStore,
                    coordinator: coordinator)
            }
#else
            _ = try operation.publishOriginalEraseAuxiliaryEmptySearch(
                writer: searchWriter, store: intentStore,
                coordinator: coordinator)
#endif
        case .published:
            try operation.requireOriginalEraseAuxiliarySearchPublished(
                store: intentStore, coordinator: coordinator)
#if DEBUG
            try originalColdExitFrame?.requireSearchPublished()
            traceErasePhase("original.search.checked-publication.reproved")
#endif
        }
        await coordinator.searchIndexStore
            .discardCacheAfterOriginalEraseCheckedPublication()
#if DEBUG
        traceErasePhase("original.search.checked-publication.complete")
#endif
    }

    /// Complete callback-bearing cleanup work before the Router transfers EX
    /// and returns from every original service/lifecycle frame.
    func prepareCleanupForRetirement(_ value: EraseIntentV1, session: StoreGenerationSession,
        authority: StoreRestoreGenerationAuthority, auxiliary: EraseAuxiliaryAuthority,
        diagnosticsStore: DiagnosticsStore, intentStore: EraseIntentStore,
        binding: EraseRetirementBindingV1, inventory: EraseReaderRetirementInventoryV1,
        reservation: AppAccessGateV1.EraseAdoptionToken?,
        coordinator: StoreSessionCoordinator,
        originalAuxiliaryOperation: EraseRouterOperationV1?) async throws -> EraseCleanupAfterRetirementV1 {
#if DEBUG
        traceErasePhase("cleanup.binding.enter")
#endif
        guard value.eraseID == binding.subject.eraseID,
              value.newGenerationID == binding.subject.newGenerationID,
              value.phase == .sessionActivated || value.phase == .cleanupComplete,
              reservation == nil || reservation?.subject == binding.subject else {
            throw EraseAllServiceError.invalidAuthority
        }
#if DEBUG
        traceErasePhase("cleanup.empty-graph.enter")
#endif
        try Self.requireEmptyErasePublishedGraph(context: session.modelContext,
            generationID: session.generationID, identity: session.workspaceIdentity,
            activated: value.advancing(to: .sessionActivated))
        if value.phase != .cleanupComplete { try inject(.beforeCleanup) }
#if DEBUG
        traceErasePhase("cleanup.notification.enter")
#endif
        let preferences = PreferencesAdapterV1(defaults: userDefaults)
        if let originalAuxiliaryOperation {
#if DEBUG
            traceErasePhase("cleanup.notification.root-policy.enter")
#endif
            do {
                _ = try originalAuxiliaryOperation.settleOriginalEraseNotificationRootPolicy(
                    store: intentStore, coordinator: coordinator)
            } catch {
                traceEraseOriginalFailure(error)
                throw error
            }
#if DEBUG
            traceErasePhase("cleanup.notification.root-policy.complete")
#endif
        }
#if DEBUG
        traceErasePhase("cleanup.notification.constructor.enter")
#endif
        let notifications: AppLockNotificationControlStoreV1
        if let originalAuxiliaryOperation {
            do {
                notifications = try originalAuxiliaryOperation.bindOriginalEraseNotificationControl(
                    applicationSupportURL: applicationSupportURL, preferences: preferences,
                    store: intentStore, coordinator: coordinator)
            } catch {
                traceEraseOriginalFailure(error)
                throw error
            }
        } else {
            notifications = try AppLockNotificationControlStoreV1(
                applicationSupportURL: applicationSupportURL, preferences: preferences)
        }
#if DEBUG
        traceErasePhase("cleanup.notification.constructor.complete")
        var originalNotificationAfterOSReadback: ErasePostRetiredNotificationSnapshotV1?
#endif
        if let originalAuxiliaryOperation {
            do {
#if DEBUG
                if let originalColdExitFrame {
                    try originalColdExitFrame.retainOriginalNotificationControl(
                        notifications)
                }
                traceErasePhase("cleanup.notification.publisher.enter")
#endif
#if DEBUG
                let receipt = try await DeviceLocalNotificationOwnerV1
                    .withOriginalEraseFixedDiagnostics(operationID: value.eraseID, control: notifications,
                        report: { [weak self] stage in self?.traceErasePhase(stage) }) {
                    try await DeviceLocalNotificationOwnerV1
                    .eraseForOriginalRetainedOwner(
                        control: notifications, system: notificationSystem,
                        operationID: value.eraseID,
                        beginMarker: {
                            try originalAuxiliaryOperation
                                .publishOriginalEraseAuxiliaryNotificationMarker(
                                    control: notifications,
                                    coordinator: coordinator,
                                    store: intentStore)
                        },
                        removeRecords: { absence in
                            try originalAuxiliaryOperation
                                .removeOriginalEraseAuxiliaryNotificationRecords(
                                    absence, control: notifications,
                                    coordinator: coordinator,
                                    store: intentStore)
                        },
                        beforeBegin: {
                            try originalAuxiliaryOperation
                                .beginOriginalEraseAuxiliaryNotification(
                                    control: notifications,
                                    coordinator: coordinator,
                                    store: intentStore)
#if DEBUG
                            try self.originalColdExitFrame?
                                .beforeOriginalNotificationRevocation()
#endif
                        }, afterBegin: { revocation in
#if DEBUG
                            try self.originalColdExitFrame?
                                .afterOriginalNotificationRevocation(revocation)
#endif
                        }, observedOwnedRefusal: { revocation, owned,
                            observedOwned in
#if DEBUG
                            try self.originalColdExitFrame?
                                .recordOriginalNotificationRefusal(
                                    revocation: revocation, owned: owned,
                                    observedOwned: observedOwned,
                                    subject: binding.subject)
#endif
                        }, afterSuccess: { revocation in
                            try originalAuxiliaryOperation
                                .observeOriginalEraseAuxiliaryNotificationSuccess(
                                    revocation, control: notifications,
                                    coordinator: coordinator)
#if DEBUG
                            try self.originalColdExitFrame?
                                .afterOriginalNotificationSuccess(revocation)
                            originalNotificationAfterOSReadback = try notifications
                                .postRetiredSnapshot(subject: binding.subject)
#endif
                        })
                }
#else
                let receipt = try await DeviceLocalNotificationOwnerV1
                    .eraseForOriginalRetainedOwner(
                        control: notifications, system: notificationSystem,
                        operationID: value.eraseID,
                        beginMarker: {
                            try originalAuxiliaryOperation
                                .publishOriginalEraseAuxiliaryNotificationMarker(
                                    control: notifications,
                                    coordinator: coordinator,
                                    store: intentStore)
                        },
                        removeRecords: { absence in
                            try originalAuxiliaryOperation
                                .removeOriginalEraseAuxiliaryNotificationRecords(
                                    absence, control: notifications,
                                    coordinator: coordinator,
                                    store: intentStore)
                        },
                        beforeBegin: {
                            try originalAuxiliaryOperation
                                .beginOriginalEraseAuxiliaryNotification(
                                    control: notifications,
                                    coordinator: coordinator,
                                    store: intentStore)
#if DEBUG
                            try self.originalColdExitFrame?
                                .beforeOriginalNotificationRevocation()
#endif
                        }, afterBegin: { revocation in
#if DEBUG
                            try self.originalColdExitFrame?
                                .afterOriginalNotificationRevocation(revocation)
#endif
                        }, observedOwnedRefusal: { revocation, owned,
                            observedOwned in
#if DEBUG
                            try self.originalColdExitFrame?
                                .recordOriginalNotificationRefusal(
                                    revocation: revocation, owned: owned,
                                    observedOwned: observedOwned,
                                    subject: binding.subject)
#endif
                        }, afterSuccess: { revocation in
                            try originalAuxiliaryOperation
                                .observeOriginalEraseAuxiliaryNotificationSuccess(
                                    revocation, control: notifications,
                                    coordinator: coordinator)
#if DEBUG
                            try self.originalColdExitFrame?
                                .afterOriginalNotificationSuccess(revocation)
                            originalNotificationAfterOSReadback = try notifications
                                .postRetiredSnapshot(subject: binding.subject)
#endif
                        })
#endif
#if DEBUG
                traceErasePhase("cleanup.notification.publisher.complete")
#endif
                try originalAuxiliaryOperation
                    .finishOriginalEraseAuxiliaryNotification(
                        receipt, control: notifications,
                        coordinator: coordinator)
            } catch {
                traceEraseOriginalFailure(error)
                originalAuxiliaryOperation
                    .failOriginalEraseAuxiliaryNotification()
                throw error
            }
        } else {
#if DEBUG
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
        }
#if DEBUG
        traceErasePhase("cleanup.notification.complete")
        try originalColdExitFrame?.beforeScratchConstruction()
        traceErasePhase("cleanup.scratch-construction.enter")
#endif
        if let originalAuxiliaryOperation {
#if DEBUG
            var originalScratchLoanBoundary: OriginalScratchLoanDiagnosticBoundary = .routerCall
#endif
            do {
#if DEBUG
                traceErasePhase("cleanup.original-scratch-loan.enter")
#endif
                let scratchReceipt = try originalAuxiliaryOperation
                    .eraseOriginalScratchForRetainedOwner(
                        store: intentStore, coordinator: coordinator)
#if DEBUG
                originalScratchLoanBoundary = .receiptSettlement
#endif
                try scratchReceipt.requireCheckedSettlement()
#if DEBUG
                originalScratchLoanBoundary = .debugAfterScratchFrame
                try originalColdExitFrame?.afterOriginalScratchCleanup(
                    scratchReceipt, operation: originalAuxiliaryOperation)
                traceErasePhase("cleanup.original-scratch-loan.complete")
#endif
            } catch {
#if DEBUG
                reportOriginalScratchLoanFailure(error,
                    boundary: originalScratchLoanBoundary,
                    operation: originalAuxiliaryOperation)
#endif
                originalAuxiliaryOperation.failOriginalEraseScratchCleanupEffect()
                traceEraseOriginalFailure(error)
                throw error
            }
        } else {
            let scratch = try ScratchDataLeaseStoreV1(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager, clock: Date.init)
#if DEBUG
            try originalColdExitFrame?.afterScratchConstruction(scratch)
            traceErasePhase("cleanup.scratch-erase.enter")
#endif
            try await scratch.eraseScratchData()
#if DEBUG
            try originalColdExitFrame?.afterScratchErase(scratch)
#endif
        }
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
        let terminalNotification = try originalAuxiliaryOperation?
            .makeOriginalEraseNotificationTerminalCloseWitness(
                control: notifications, coordinator: coordinator)
        let auxiliaryRetirementData: EraseIntentStore.OriginalAuxiliaryRetirementDataV1?
        if value.schemaVersion == 2, let originalAuxiliaryOperation {
            auxiliaryRetirementData = try intentStore.captureOriginalAuxiliaryRetirementData(
                expected: value, operation: originalAuxiliaryOperation)
        } else {
            auxiliaryRetirementData = nil
        }
        let prepared = EraseCleanupAfterRetirementV1(binding: binding, intent: value, factory: generationFactory,
            authority: authority, auxiliary: auxiliary, intentStore: intentStore, observation: observation,
            manifestScope: scope, targetReader: reader, diagnosticsStore: diagnosticsStore,
            notificationControl: notifications,
            originalNotificationTerminalClose: terminalNotification,
            originalAuxiliaryRetirementData: auxiliaryRetirementData,
            userDefaults: userDefaults, defaultsDomainName: defaultsDomainName,
            fileManager: fileManager, failureInjection: failureInjection, reservation: reservation,
            completion: didCompleteErase)
#if DEBUG
        guard let originalNotificationAfterOSReadback else {
            throw EraseAllServiceError.invalidAuthority
        }
        try prepared.sealOriginalPostEffectNotificationForTesting(
            originalNotificationAfterOSReadback)
        if let hook = afterOldGenerationDeletionBeforeRetiredPointerClearForTesting {
            try prepared.installRetiredPointerCutHookForTesting(hook)
        }
        if let hook = afterTerminalSourceValidationForTesting {
            try prepared.installPostCloseSourceControlsHookForTesting(
                foreignOwner: postCloseSourceForeignOwnerForTesting, hook: hook)
        } else {
            guard postCloseSourceForeignOwnerForTesting == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        if let hook = beforeOriginalAuxiliaryRetirementValidationForTesting {
            try prepared.installOriginalAuxiliaryRetirementHookForTesting(hook)
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

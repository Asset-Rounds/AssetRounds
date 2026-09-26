import CryptoKit
import Darwin
import Foundation

enum C34SceneNavigationBackupExportBoundaryV1 {
    static func validate() throws {
        guard C34SceneNavigationDeviceLifecycleBoundaryV1.validate() else {
            throw SceneNavigationFailureV1.invalidSnapshot
        }
    }
}

enum C50IncumbentFileExchangeBackupExportBoundaryV1 {
    static let exportsAdapterProfileState = false
    static let exportsLeasedInputBytes = false
    static let exportsQuarantineBytes = false
    static let exportsSecurityBookmarksOrExternalPaths = false
    static let exportedAdapterFilesAreDerivedEscapedCopies = true
}
import SwiftData

enum IntegrationProjectionBackupExportExclusionV1 {
    static func validate() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        try coverage.validate()
        guard !coverage.backupIncluded, !coverage.exportIncluded,
              !IntegrationProjectionSchemaV1.canonicalBackupIncluded,
              !IntegrationProjectionSchemaV1.canonicalExportIncluded else {
            throw BackupExportServiceError.invalidAuthority
        }
    }
}

enum BackupExportServiceError: Error, Equatable {
    case invalidGeneration
    case contextHasChanges
    case invalidAuthority
    case stalePreview
    case destinationInvalid
    case destinationExists
    case cancelled
    case insufficientStorage
    case sourceChanged
    case cleanupFailed
    case writeFailed
    case generationLeaseLost
}

/// Read-only authority for the immediate source of a persisted schema-2 Erase.
/// It never owns a context or container, so validation cannot prevent old-session drain.
@MainActor
final class EraseRetainedSourceValidationV1 {
    let generationRootURL: URL
    let workspaceIdentity: WorkspaceReplicaIdentityV1

    private let intent: EraseIntentV1
    private let generationFactory: StoreGenerationFactory
    private let authority: StoreRestoreGenerationAuthority
    private let intentStore: EraseIntentStore
    private let manifestStore: StoreMigrationJournalStoreV1
    private let manifest: StoreGenerationManifestV1
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let targetRootIdentity: ReportPDFAnchoredFile.RootIdentity

    private init(
        intent: EraseIntentV1,
        generationFactory: StoreGenerationFactory,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        manifestStore: StoreMigrationJournalStoreV1,
        manifest: StoreGenerationManifestV1,
        workspaceIdentity: WorkspaceReplicaIdentityV1,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity,
        targetRootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) {
        self.intent = intent
        self.generationFactory = generationFactory
        self.authority = authority
        self.intentStore = intentStore
        self.manifestStore = manifestStore
        self.manifest = manifest
        self.workspaceIdentity = workspaceIdentity
        self.rootIdentity = rootIdentity
        self.targetRootIdentity = targetRootIdentity
        generationRootURL = generationFactory.installedGenerationURL(
            id: intent.oldGenerationID
        )
    }

    static func acquire(
        intent: EraseIntentV1,
        generationFactory: StoreGenerationFactory,
        authority: StoreRestoreGenerationAuthority
    ) throws -> EraseRetainedSourceValidationV1 {
        guard intent.schemaVersion == 2,
              EraseIntentCodecV1.valid(intent),
              let oldPointer = intent.oldPointer else {
            throw BackupExportServiceError.invalidGeneration
        }
        try authority.verify()
        let applicationSupportURL = generationFactory.restoreApplicationSupportURL
        try requireSettledIntent(applicationSupportURL: applicationSupportURL)
        let intentStore = try EraseIntentStore(applicationSupportURL: applicationSupportURL)
        guard try intentStore.load() == intent else {
            throw BackupExportServiceError.invalidGeneration
        }
        let rootIdentity = try requireRoot(
            id: intent.oldGenerationID, generationFactory: generationFactory,
            authority: authority
        )
        let targetRootIdentity = try requireRoot(
            id: intent.newGenerationID, generationFactory: generationFactory,
            authority: authority
        )
        _ = try requireTargetPointer(
            intent: intent, generationFactory: generationFactory, authority: authority
        )
        let manifestStore = try StoreMigrationJournalStoreV1(
            applicationSupportURL: applicationSupportURL
        )
        let manifest = try manifestStore.loadManifest(
            targetGenerationID: oldPointer.generationID,
            expectedDigest: oldPointer.generationManifestSHA256
        )
        guard manifest.generationID == intent.oldGenerationID,
              manifest.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease else {
            throw BackupExportServiceError.invalidGeneration
        }
        let validation = EraseRetainedSourceValidationV1(
            intent: intent, generationFactory: generationFactory, authority: authority,
            intentStore: intentStore, manifestStore: manifestStore, manifest: manifest,
            workspaceIdentity: try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: oldPointer.workspaceID),
                replicaID: ReplicaID(rawValue: oldPointer.replicaID)
            ),
            rootIdentity: rootIdentity, targetRootIdentity: targetRootIdentity
        )
        try validation.revalidateControls()
        return validation
    }

    func revalidate(modelContext: ModelContext) throws {
        try revalidateControls()
        let configurations = Array(modelContext.container.configurations)
        guard !modelContext.hasChanges,
              configurations.count == 1,
              !configurations[0].isStoredInMemoryOnly,
              configurations[0].url.standardizedFileURL
                == generationRootURL.appendingPathComponent("model.sqlite").standardizedFileURL else {
            throw BackupExportServiceError.invalidGeneration
        }
        let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count == 1, let state = states.first,
              state.generationID == intent.oldGenerationID,
              state.workspaceID == workspaceIdentity.workspaceID.rawValue,
              state.activeReplicaID == workspaceIdentity.replicaID.rawValue,
              let expectedLedger = intent.sourceLedger else {
            throw BackupExportServiceError.invalidGeneration
        }
        let ledger = try DeletionLedgerStore(context: modelContext).snapshot()
        let actualLedger = try DeletionLedgerProofV2(
            entryCount: ledger.entries.count,
            canonicalSHA256: StoreMigrationCanonicalJSONV1.sha256(try ledger.canonicalData())
        )
        guard actualLedger == expectedLedger, !modelContext.hasChanges else {
            throw BackupExportServiceError.invalidGeneration
        }
        try revalidateControls()
    }

    private func revalidateControls() throws {
        try authority.verify()
        try Self.requireSettledIntent(
            applicationSupportURL: generationFactory.restoreApplicationSupportURL
        )
        guard try intentStore.load() == intent,
              let oldPointer = intent.oldPointer,
              try Self.requireRoot(
                  id: intent.oldGenerationID, generationFactory: generationFactory,
                  authority: authority
              ) == rootIdentity,
              try Self.requireRoot(
                  id: intent.newGenerationID, generationFactory: generationFactory,
                  authority: authority
              ) == targetRootIdentity,
              try manifestStore.loadManifest(
                  targetGenerationID: oldPointer.generationID,
                  expectedDigest: oldPointer.generationManifestSHA256
              ) == manifest else {
            throw BackupExportServiceError.invalidGeneration
        }
        _ = try Self.requireTargetPointer(
            intent: intent, generationFactory: generationFactory, authority: authority
        )
        try authority.verify()
    }

    private static func requireTargetPointer(
        intent: EraseIntentV1,
        generationFactory: StoreGenerationFactory,
        authority: StoreRestoreGenerationAuthority
    ) throws -> CurrentGenerationPointerV3 {
        guard let target = intent.targetPointer else {
            throw BackupExportServiceError.invalidGeneration
        }
        let actual = try generationFactory.currentGenerationPointerV3(
            expectedGenerationID: intent.newGenerationID, authority: authority
        )
        let expected = try CurrentGenerationPointerV3(
            generationID: target.generationID,
            generationManifestSHA256: target.generationManifestSHA256,
            workspaceID: WorkspaceID(rawValue: target.workspaceID),
            replicaID: ReplicaID(rawValue: target.replicaID),
            knownReplicaIDs: Set(target.knownReplicaIDs.map { ReplicaID(rawValue: $0) }),
            storeSchemaVersion: PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major
        )
        guard actual == expected else {
            throw BackupExportServiceError.invalidGeneration
        }
        return actual
    }

    private static func requireRoot(
        id: UUID,
        generationFactory: StoreGenerationFactory,
        authority: StoreRestoreGenerationAuthority
    ) throws -> ReportPDFAnchoredFile.RootIdentity {
        let observed = try ReportPDFAnchoredFile.rootIdentity(
            at: generationFactory.installedGenerationURL(id: id)
        )
        let authenticated = try authority.restoreGenerationRootIdentity(id: id, staging: false)
        guard UInt64(observed.device) == authenticated.device,
              UInt64(observed.inode) == authenticated.inode else {
            throw BackupExportServiceError.invalidGeneration
        }
        return observed
    }

    /// Recovery settles interrupted journal writes before this capability is acquired.
    /// Reject missing/pending authority here rather than letting load initialize or repair it.
    private static func requireSettledIntent(applicationSupportURL: URL) throws {
        let app = Darwin.open(applicationSupportURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard app >= 0 else { throw BackupExportServiceError.invalidGeneration }
        defer { _ = Darwin.close(app) }
        let erase = Darwin.openat(app, "FieldEvidenceErase", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard erase >= 0 else { throw BackupExportServiceError.invalidGeneration }
        defer { _ = Darwin.close(erase) }
        var canonical = stat()
        var pending = stat()
        guard Darwin.fstatat(erase, "erase.json", &canonical, AT_SYMLINK_NOFOLLOW) == 0,
              (canonical.st_mode & S_IFMT) == S_IFREG,
              canonical.st_nlink == 1,
              Darwin.fstatat(erase, ".erase.json.next", &pending, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else {
            throw BackupExportServiceError.invalidGeneration
        }
    }
}

struct BackupCanonicalCheckpointBasisV1: Equatable, Sendable {
    let workspaceIdentity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let packageReleases: [PackageReleaseIdentityV1]
    let workspaceRevision: UInt64
    let lastLocalSequence: UInt64
    let recordsData: Data
    let semanticRecordsData: Data
    let memberInventory: [V4BackupEntryV1]
}

@MainActor
enum BackupPackageLifecycleRouteV1 {
    case live(WorkspacePackageLifecycleDependenciesV1)
    case expiringCompatibility(BackupPackageCompatibilityPostureV1)
}

enum C30EvidenceContextBackupExportPolicyV1 {
    static let exportsCanonicalRows = true
    static let exportsDerivedProjection = false
    static let exportsProviderOwnedState = false
    static let preservesHistoricReports = true

    static func validate(_ values: EvidenceContextBackupRecordSetV1) throws {
        guard exportsCanonicalRows, !exportsDerivedProjection,
              !exportsProviderOwnedState, preservesHistoricReports else {
            throw BackupExportServiceError.invalidGeneration
        }
        _ = try C30EvidenceContextBackupEncoderV1.encode(values)
    }
}

@MainActor
final class BackupExportService {
    private static let checkpointBasisPreviewID = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))
    private static let checkpointBasisExportedAt = Date(timeIntervalSince1970: 0)

    private struct Rows {
        let surveySessions:[SurveySessionRow];let factCaptures:[FactCaptureRow];let provisionalSubjects:[ProvisionalSubjectRow];let subjectPromotionReceipts:[SubjectPromotionReceiptRow];let surveyPublicationSnapshots:[SurveyPublicationSnapshotRow]
        let surveyDefinitionIdentities:[SurveyDefinitionIdentityRow]
        let surveyDefinitionReleases:[SurveyDefinitionReleaseRow]
        let accessibleDocumentAssessmentReceipts:[AccessibleDocumentAssessmentReceiptRow]
        let assetLocators: [AssetLocatorRow]
        let locatorBindingReceipts: [LocatorBindingReceiptRow]
        let scheduleDefinitionReleases: [ScheduleDefinitionReleaseRow]
        let occurrenceHistoryEvents: [OccurrenceHistoryEventRow]
        let exceptionCalendarReleases: [ExceptionCalendarReleaseRow]
        let scheduleOverrideEvents: [ScheduleOverrideEventRow]
        let planDocuments: [PlanDocumentRow]
        let planRevisions: [PlanRevisionRow]
        let planPlacements: [PlanPlacementRow]
        let rebaseReceipts: [RebaseReceiptRow]
        let poseEvents: [AssetPoseEventRow]
        let spatialAnchorObservations: [SpatialAnchorObservationRow]
        let evidenceContexts: [EvidenceContextRow]
        let pairedObservationLinks: [PairedObservationLinkRow]
        let lightingSystems: [LightingSystemRow]
        let lightingObservations: [LightingObservationRow]
        let lightingIssues: [LightingIssueRow]
        let lightingPlans: [MeasurementPlanRow]
        let lightingClaims: [LightingClaimStateRow]
        let lightingDayInventoryWorkflows: [LightingDayInventoryWorkflowRowV1]
        let lightingNightWorkflows: [LightingNightWorkflowRowV1]
        let assistanceAcceptanceReceipts: [AssistanceAcceptanceReceiptRow]
        let temporalEvidenceClips: [TemporalEvidenceClipRow]
        let timecodedEvidenceAnchors: [TimecodedEvidenceAnchorRow]
        let acceptedLabelGenerationSnapshots: [AcceptedLabelGenerationSnapshotRow]
        let serviceContactPoints: [ServiceContactPointRow]
        let systemHandoffIntents: [SystemHandoffIntentRow]
        let activitySessionEnvelopes: [ActivitySessionEnvelopeRow]
        let activityStateTransitions: [ActivityStateTransitionRow]
        let installationTaskResults: [InstallationTaskResultRow]
        let installationAsBuiltSnapshots: [InstallationAsBuiltSnapshotRow]
        let punchReviewBasisSnapshots: [PunchReviewBasisSnapshotRow]
         let serviceRequestRecords: [ServiceRequestRecordRow]
         let serviceRequestDispositionEvents: [ServiceRequestDispositionEventRow]
         let serviceRequestWorkLinkEvents: [ServiceRequestWorkLinkEventRow]
         let serviceReliabilityIncidents: [AssetServiceIncidentRow]
         let serviceImpactSegments: [ServiceImpactSegmentRow]
         let serviceCauseAssertions: [ServiceCauseAssertionRow]
         let serviceRemedyAssertions: [ServiceRemedyAssertionRow]
         let serviceRepairIntervals: [ServiceRepairIntervalRow]
         let serviceRestorationAssertions: [ServiceRestorationAssertionRow]
         let qualifiedServiceExposures: [QualifiedServiceExposureRow]
        let fieldReferenceReleases:[FieldReferenceReleaseRow]
        let fieldReferenceBindings:[FieldReferenceBindingRow]
        let recoverabilityVerificationReceipts:[RecoverabilityVerificationReceiptRow]
        let clientCapabilityProfiles:[ClientCapabilityProfileRow];let packageLifecyclePolicies:[PackageLifecyclePolicyRow];let packageLifecycleDispositions:[PackageLifecycleDispositionRow];let clientCapabilityAdmissionDecisions:[ClientCapabilityAdmissionDecisionRow]
        let privacyTransformPolicies: [PrivacyTransformPolicyRow]
        let privacyRegions: [PrivacyRegionRow]
        let privacyTransformManifests: [PrivacyTransformManifestRow]
        let privacyReviewReceipts: [PrivacyReviewReceiptRow]
        let instrumentReferences: [InstrumentReferenceRow]
        let calibrationStatusSnapshots: [CalibrationStatusSnapshotRow]
        let measurementCaptures: [MeasurementCaptureRow]
        let measurementSeries: [MeasurementSeriesRow]
        let measurementQualityAssessments: [MeasurementQualityAssessmentRow]
        let promotedPackageReleases: [PromotedPackageReleaseRow]
        let packageSandboxRuns: [PackageSandboxRunRow]
        let packagePromotionReceipts: [PackagePromotionReceiptRow]
        let activePackageRegistryPointers: [ActivePackageRegistryPointerRow]
        let fieldDraftCheckpoints: [FieldDraftCheckpointRow]
        let attachmentStagingItems: [AttachmentStagingItemRow]
        let draftCommitSagas: [DraftCommitSagaRow]
        let draftContentReservations: [DraftContentReservationRow]
        let draftCommitReceipts: [DraftCommitReceiptRow]
        let draftDiscardReceipts: [DraftDiscardReceiptRow]
        let workPacketManifests:[WorkPacketManifestRow];let workItemClaims:[WorkItemClaimRow]
        let workLeases:[WorkLeaseRow];let workReleases:[WorkReleaseRow];let workHandoffs:[WorkHandoffRow]
        let inspectionReviewTransitions: [InspectionReviewTransitionRow]
        let reviewDispositions: [ReviewDispositionRow]
        let changeRequests: [ChangeRequestRow]
        let correctiveActionPolicies: [CorrectiveActionPolicyRow]
        let correctiveActionEvents: [CorrectiveActionEventRow]
        let evidenceVisibilities: [EvidenceVisibilityRow]
        let claimEvidenceLinks: [ClaimEvidenceLinkRow]
        let assuranceManifests: [AssuranceManifestRow]
        let attestations: [AttestationRow]
        let functionalRelationshipDescriptors: [FunctionalRelationshipTypeDescriptorRow]
        let functionalRelationshipEvents: [AssetFunctionalRelationshipEventRow]
        let authoritySourceReleases: [AuthoritySourceReleaseRow]
        let requirementBasisBindings: [RequirementBasisBindingRow]
        let applicabilityContextSnapshots: [ApplicabilityContextSnapshotRow]
        let assessmentScopeSnapshots: [AssessmentScopeSnapshotRow]
        let severityScaleReleases: [SeverityScaleReleaseRow]
        let findingClassificationBindings: [FindingClassificationBindingRow]
        let measurementProtocolReleases: [MeasurementProtocolReleaseRow]
        let derivedFactEvaluatorDescriptors: [DerivedFactEvaluatorDescriptorRow]
        let derivedFactProvenances: [DerivedFactProvenanceRow]
        let assetCompositionEdges: [AssetCompositionEdgeRow]
        let assetCompositionEvents: [AssetCompositionEventRow]
        let assetPlacementEvents: [AssetPlacementEventRow]
        let assetKindBindingEvents: [AssetKindBindingEventRow]
        let assetWorkflowCapabilityBindingEvents: [AssetWorkflowCapabilityBindingEventRow]
        let assetProductIdentities: [AssetProductIdentityRow]
        let assetLifecycleEvents: [AssetLifecycleEventRow]
        let assetSuccessorLinks: [AssetSuccessorLinkRow]
        let workSubjectScopeSnapshots: [WorkSubjectScopeSnapshotRow]
        let sites: [Site]
        let assets: [Asset]
        let records: [WorkflowRecord]
        let observationAndTime: [UUID: ObservationAndTimeRow]
        let evidence: [EvidenceFile]
        let issues: [Issue]
        let locationHierarchyEvents: [LocationHierarchyEventRow]
        let locationMigrationReceipts: [LocationMigrationReceiptRow]
        let locationNodes: [LocationNodeRow]
        let packets: [Packet]
        let serviceParties: [ServicePartyRow]
        let sitePartyRoleEvents: [SitePartyRoleEventRow]
        let actorSnapshots: [ActorSnapshotRow]
        let qualificationSnapshots: [QualificationSnapshotRow]
        let signoffSnapshots: [SignoffSnapshotRow]
        let reports: [Report]
        let requirementAssurance: [RequirementAssuranceRow]
        let savedSmartViews: [SavedSmartViewRowV1]
    }

    private struct StreamingSource: Equatable, Sendable {
        enum Location: Equatable, Sendable {
            case generatedRecords
            case generatedPortableExchangeSnapshot
            case generatedPhotoMetadata(String)
            case generationRelative(String)
            case draftRelative(String)
        }

        let path: String
        let mimeType: String
        let byteCount: Int
        let sha256: String
        let location: Location
    }

    private struct StreamingPrepared: Equatable, Sendable {
        let preview: BackupExportPreviewV1
        let manifest: V4BackupManifestV1
        let manifestData: Data
        let recordsData: Data
        let portableExchangeSnapshotData: Data
        let mutationHistory: MutationHistorySnapshotV1
        let checkpointBasis: BackupCanonicalCheckpointBasisV1
        let sources: [StreamingSource]
        let photoHistory: CheckRunnerPhotoBackupHistoryV1
        let generatedPhotoMetadata: [String: Data]
    }

    private struct PhotoStreamingSnapshot: Equatable, Sendable {
        let history: CheckRunnerPhotoBackupHistoryV1
        let raw: [DraftPhotoRawBackupSnapshotV1]
        let media: [CheckRunnerPhotoMediaBackupChildSnapshotV1]
    }

    private enum PhotoRawVerification {
        case existing(DraftPhotoBackupPreparedVerificationV1)
        case absent(DraftPhotoBackupAbsentRootPreparedVerificationV1)

        func withVerificationLock<T>(_ body: () throws -> T) throws -> T {
            switch self {
            case .existing(let value): return try value.withVerificationLock(body)
            case .absent(let value): return try value.withVerificationLock(body)
            }
        }
    }

    private struct PhotoExportFreeze {
        let prepared: StreamingPrepared
        let revision: WorkspaceRevisionV1
        let rawVerification: PhotoRawVerification
        let mediaVerification: CheckRunnerPhotoMediaBackupPreparedVerificationV1
        let observedSources: [ObservedStreamingSource]
    }

    private struct ObservedStreamingSource: Sendable {
        let entry: StreamingArchiveWriteEntryV1
        let observation: StreamingArchiveSourceObservationV1
    }

    private struct OwnedStagingSource: Sendable {
        let url: URL
        let device: UInt64
        let inode: UInt64
    }

    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let lifecycleRoute: BackupPackageLifecycleRouteV1
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity?
    private let storagePreflight: StoragePreflightService
    private let archiveLimits: StreamingArchiveLimitsV1
    private let archiveService: StreamingArchiveService
    private let now: () -> Date
    private let makeUUID: @Sendable () -> UUID
    private let appVersion: () -> String
    private let appBuild: () -> String
    private let fileManager: FileManager
    private let generationLeaseValidation: @Sendable () throws -> Void
    private var prepared: PreparedV4BackupV1?
    private var streamingPrepared: StreamingPrepared?
    private var retainedEraseValidation: EraseRetainedSourceValidationV1?
    /// Set only for the synchronous body of `validateFrozenCanonical`.
    private var lockedPublicationStore: StoreSessionCoordinator?
#if DEBUG
    var afterArchivePublicationForTesting: (@MainActor () throws -> Void)?
#endif

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        lifecycleRoute: BackupPackageLifecycleRouteV1,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        archiveLimits: StreamingArchiveLimitsV1 = .card17,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        },
        appBuild: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "0"
        },
        fileManager: FileManager = .default,
        generationLeaseValidation: @escaping @Sendable () throws -> Void = {}
    ) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.lifecycleRoute = lifecycleRoute
        self.storagePreflight = storagePreflight
        self.archiveLimits = archiveLimits
        self.archiveService = StreamingArchiveService(
            limits: archiveLimits,
            makeOperationID: makeUUID
        )
        self.now = now
        self.makeUUID = makeUUID
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.fileManager = fileManager
        self.generationLeaseValidation = generationLeaseValidation
        let root = generationRootURL.standardizedFileURL
        let dataRoot = root.deletingLastPathComponent().deletingLastPathComponent()
        if root.isFileURL,
           root.deletingLastPathComponent().lastPathComponent == "generations",
           dataRoot.lastPathComponent == "FieldEvidenceData",
           let id = UUID(uuidString: root.lastPathComponent),
           id.uuidString.lowercased() == root.lastPathComponent {
            rootIdentity = try? ReportPDFAnchoredFile.rootIdentity(at: root)
        } else {
            rootIdentity = nil
        }
    }

    convenience init(
        modelContext: ModelContext,
        generationRootURL: URL,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        archiveLimits: StreamingArchiveLimitsV1 = .card17,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        },
        appBuild: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "0"
        },
        fileManager: FileManager = .default,
        generationLeaseValidation: @escaping @Sendable () throws -> Void = {}
    ) {
        self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            lifecycleRoute: .live(lifecycleDependencies),
            storagePreflight: storagePreflight,
            archiveLimits: archiveLimits,
            now: now,
            makeUUID: makeUUID,
            appVersion: appVersion,
            appBuild: appBuild,
            fileManager: fileManager,
            generationLeaseValidation: generationLeaseValidation
        )
    }

    convenience init(
        modelContext: ModelContext,
        generationRootURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        archiveLimits: StreamingArchiveLimitsV1 = .card17,
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
        },
        appBuild: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "0"
        },
        fileManager: FileManager = .default,
        generationLeaseValidation: @escaping @Sendable () throws -> Void = {},
        compatibilityPosture: BackupPackageCompatibilityPostureV1 = .frozenLegacyCallersOnly
    ) {
        self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            lifecycleRoute: .expiringCompatibility(compatibilityPosture),
            storagePreflight: storagePreflight,
            archiveLimits: archiveLimits,
            now: now,
            makeUUID: makeUUID,
            appVersion: appVersion,
            appBuild: appBuild,
            fileManager: fileManager,
            generationLeaseValidation: generationLeaseValidation
        )
    }

    static func prepareRetainedEraseSummary(
        modelContext: ModelContext,
        validation: EraseRetainedSourceValidationV1
    ) throws -> BackupExportPreviewV1 {
        try validation.revalidate(modelContext: modelContext)
        let exporter = BackupExportService(
            modelContext: modelContext,
            generationRootURL: validation.generationRootURL,
            compatibilityPosture: .frozenLegacyCallersOnly
        )
        exporter.retainedEraseValidation = validation
        let preview = try exporter.prepare()
        try validation.revalidate(modelContext: modelContext)
        return preview
    }

    func prepare() throws -> BackupExportPreviewV1 {
        try C34SceneNavigationBackupExportBoundaryV1.validate()
        try validateGenerationLease()
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        let value = try buildStreamingPrepared(
            previewID: makeUUID(),
            exportedAt: now()
        )
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        streamingPrepared = value
        try validateGenerationLease()
        return value.preview
    }

    /// Compatibility alias for callers introduced with the V23 streaming
    /// archive. All shipping preparation now selects the current writer.
    func prepareStreaming() throws -> BackupExportPreviewV1 {
        try prepare()
    }

    func canonicalCheckpointBasis() throws -> BackupCanonicalCheckpointBasisV1 {
        try validateGenerationLease()
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        let value = try buildStreamingPrepared(
            previewID: Self.checkpointBasisPreviewID,
            exportedAt: Self.checkpointBasisExportedAt
        )
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        try validateGenerationLease()
        return value.checkpointBasis
    }

    /// Test-only compatibility fixture seam for producing the historic V1
    /// directory package. Shipping call sites must use `prepare()`.
    func prepareCompatibilityFixtureLegacyDirectoryPackage() throws -> BackupExportPreviewV1 {
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        let value = try buildPrepared(
            previewID: makeUUID(),
            exportedAt: now()
        )
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        prepared = value
        return value.preview
    }

    func export(
        previewID: UUID,
        to destinationDirectoryURL: URL
    ) throws -> URL {
        try validateLifecycleScope(try fetchRows(), operation: .exportOpen)
        return try exportStreaming(
            previewID: previewID,
            to: destinationDirectoryURL,
            cancellation: .none
        )
    }

    /// Test-only compatibility fixture seam for producing the historic V1
    /// directory package. Shipping call sites must use `export(previewID:to:)`.
    func exportCompatibilityFixtureLegacyDirectoryPackage(
        previewID: UUID,
        to destinationDirectoryURL: URL
    ) throws -> URL {
        try validateLifecycleScope(try fetchRows(), operation: .exportOpen)
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        guard let frozen = prepared, frozen.preview.id == previewID else {
            throw BackupExportServiceError.stalePreview
        }
        let rebuilt = try buildPrepared(
            previewID: previewID,
            exportedAt: frozen.manifest.exportedAt
        )
        guard rebuilt == frozen else {
            throw BackupExportServiceError.stalePreview
        }
        guard destinationDirectoryURL.isFileURL else {
            throw BackupExportServiceError.destinationInvalid
        }

        let destination = destinationDirectoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: destination.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw BackupExportServiceError.destinationInvalid
        }
        do {
            try storagePreflight.checkBackupExport(
                declaredPayloadByteCount: Int64(frozen.preview.declaredPayloadByteCount),
                onVolumeContaining: destination
            )
        } catch {
            throw error
        }

        let packageURL = destination.appendingPathComponent(
            "AssetRounds.fieldrecordbackup",
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw BackupExportServiceError.destinationExists
        }
        let wrapper = try makeFileWrapper(frozen)
        var coordinationError: NSError?
        var writeError: Error?
        var writtenPackageURL: URL?
        NSFileCoordinator().coordinate(
            writingItemAt: destination,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedDirectory in
            let coordinatedPackage = coordinatedDirectory.appendingPathComponent(
                packageURL.lastPathComponent,
                isDirectory: true
            )
            do {
                guard !fileManager.fileExists(atPath: coordinatedPackage.path) else {
                    throw BackupExportServiceError.destinationExists
                }
                try wrapper.write(
                    to: coordinatedPackage,
                    options: .atomic,
                    originalContentsURL: nil
                )
                writtenPackageURL = coordinatedPackage
                try verifyPackage(frozen, at: coordinatedPackage)
            } catch {
                writeError = error
            }
        }
        if coordinationError != nil {
            if let writtenPackageURL,
               fileManager.fileExists(atPath: writtenPackageURL.path) {
                try? fileManager.removeItem(at: writtenPackageURL)
            }
            throw BackupExportServiceError.writeFailed
        }
        if let writeError {
            if let writtenPackageURL,
               fileManager.fileExists(atPath: writtenPackageURL.path) {
                try? fileManager.removeItem(at: writtenPackageURL)
            }
            if let typed = writeError as? BackupExportServiceError {
                throw typed
            }
            throw BackupExportServiceError.writeFailed
        }
        prepared = nil
        return packageURL
    }

    /// Compatibility alias for callers introduced with the V23 streaming
    /// archive. `export(previewID:to:)` uses this same current writer.
    func export(previewID: UUID, to destinationDirectoryURL: URL,
        contentAccess: AppAccessPresentationV1.ContentAccess,
        cancellation: StreamingArchiveCancellationV1 = .none) async throws -> URL {
        try C34SceneNavigationBackupExportBoundaryV1.validate()
        guard !Task.isCancelled else { throw BackupExportServiceError.cancelled }
        do { try cancellation.checkpoint() }
        catch StreamingArchiveFailureV1.cancelled { throw BackupExportServiceError.cancelled }
        let operation = try contentAccess.beginBackupOperation(modelContext: modelContext,
            generationRootURL: generationRootURL)
        try validateLifecycleScope(try fetchRows(), operation: .exportOpen)
        let freeze: PhotoExportFreeze
        do { freeze = try await freezePhotoExport(previewID: previewID, operation: operation) }
        catch is CancellationError { throw BackupExportServiceError.cancelled }
        let generationRoot = generationRootURL
        let pinnedRoot = rootIdentity
        let capacity = storagePreflight
        let limits = archiveLimits
        let writer = archiveService
        let lease = generationLeaseValidation
        let value = freeze.prepared
        let task = Task.detached(priority: .userInitiated) {
            let taskCancellation = StreamingArchiveCancellationV1 {
                try StreamingArchiveCancellationV1.task.checkpoint()
                try cancellation.checkpoint()
            }
            return try Self.publishStreaming(value, to: destinationDirectoryURL, generationRootURL: generationRoot,
                pinnedRootIdentity: pinnedRoot, storagePreflight: capacity, archiveLimits: limits,
                archiveService: writer, cancellation: taskCancellation, generationLeaseValidation: lease)
        }
        let receipt = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        do {
#if DEBUG
            try afterArchivePublicationForTesting?()
#endif
            try StreamingArchiveCancellationV1.task.checkpoint()
            try cancellation.checkpoint()
            try operation.withAuthorization { store in
                try store.withCheckRunnerPhotoPublication(expectedWriter: store.workspaceWriter,
                    applicationSupportURL: store.checkRunnerPhotoApplicationSupportURL) {
                    try freeze.rawVerification.withVerificationLock {
                        try freeze.mediaVerification.withVerificationLock {
                            guard try store.workspaceWriter.currentRevision() == freeze.revision else {
                                throw BackupExportServiceError.stalePreview
                            }
                            try validateFrozenCanonical(freeze.prepared, publicationStore: store)
                            for source in freeze.observedSources {
                                try StreamingArchiveCancellationV1.task.checkpoint()
                                try cancellation.checkpoint()
                                guard try archiveService.sourceObservation(source.entry) == source.observation else {
                                    throw BackupExportServiceError.sourceChanged
                                }
                            }
                            try validateGenerationLease()
                            try StreamingArchiveCancellationV1.task.checkpoint()
                        }
                    }
                }
            }
            streamingPrepared = nil
            return receipt.archiveURL
        } catch {
            let cleanup = Task.detached(priority: .userInitiated) {
                try Self.removeOwnedPublishedArchive(receipt, within: destinationDirectoryURL)
            }
            guard (try? await cleanup.value) != nil else { throw BackupExportServiceError.cleanupFailed }
            throw Self.mapStreamingExportError(error)
        }
    }

    func exportStreaming(
        previewID: UUID,
        to destinationDirectoryURL: URL,
        cancellation: StreamingArchiveCancellationV1 = .none
    ) throws -> URL {
        try validateLifecycleScope(try fetchRows(), operation: .exportOpen)
        try validateGenerationLease()
        guard !modelContext.hasChanges else {
            throw BackupExportServiceError.contextHasChanges
        }
        guard let frozen = streamingPrepared,
              frozen.preview.id == previewID else {
            throw BackupExportServiceError.stalePreview
        }
        let rebuilt = try buildStreamingPrepared(
            previewID: previewID,
            exportedAt: frozen.manifest.exportedAt
        )
        guard rebuilt == frozen, !modelContext.hasChanges else {
            throw BackupExportServiceError.stalePreview
        }
        guard frozen.photoHistory.children.isEmpty else { throw BackupExportServiceError.invalidAuthority }
        let receipt = try Self.publishStreaming(
            frozen, to: destinationDirectoryURL, generationRootURL: generationRootURL,
            pinnedRootIdentity: rootIdentity, storagePreflight: storagePreflight,
            archiveLimits: archiveLimits, archiveService: archiveService,
            cancellation: cancellation, generationLeaseValidation: generationLeaseValidation
        )
        do {
            try validateGenerationLease()
            guard !modelContext.hasChanges else { throw BackupExportServiceError.stalePreview }
            streamingPrepared = nil
            return receipt.archiveURL
        } catch {
            guard (try? Self.removeOwnedPublishedArchive(receipt, within: destinationDirectoryURL)) != nil else {
                throw BackupExportServiceError.cleanupFailed
            }
            throw Self.mapStreamingExportError(error)
        }
    }

    /// One value-only publication kernel serves synchronous compatibility
    /// callers and the explicit asynchronous backup action.
    private nonisolated static func publishStreaming(
        _ frozen: StreamingPrepared,
        to destinationDirectoryURL: URL,
        generationRootURL: URL,
        pinnedRootIdentity: ReportPDFAnchoredFile.RootIdentity?,
        storagePreflight: StoragePreflightService,
        archiveLimits: StreamingArchiveLimitsV1,
        archiveService: StreamingArchiveService,
        cancellation: StreamingArchiveCancellationV1,
        generationLeaseValidation: @Sendable () throws -> Void
    ) throws -> StreamingArchiveWriteReceiptV1 {
        let destination = destinationDirectoryURL.standardizedFileURL
        guard destinationDirectoryURL.isFileURL,
              try Self.itemType(at: destination) == .directory else {
            throw BackupExportServiceError.destinationInvalid
        }
        do {
            try storagePreflight.checkBackupExport(
                declaredPayloadByteCount: Int64(frozen.preview.declaredPayloadByteCount),
                onVolumeContaining: destination
            )
        } catch {
            throw Self.mapStreamingExportError(error)
        }

        let packageURL = destination.appendingPathComponent(
            "AssetRounds.fieldrecordbackup",
            isDirectory: false
        )
        guard try Self.itemType(at: packageURL) == nil else {
            throw BackupExportServiceError.destinationExists
        }
        let stagingRoot: URL
        guard let pinnedGenerationRootIdentity = pinnedRootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        do {
            stagingRoot = try StoreGenerationFactory.backupImportStagingDirectory(
                containing: generationRootURL
            )
            guard try Self.itemType(at: stagingRoot) == .directory else {
                throw BackupExportServiceError.invalidGeneration
            }
            let verifyStagingAuthority = {
                guard try Self.itemType(at: stagingRoot) == .directory,
                      try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                        == pinnedGenerationRootIdentity else {
                    throw BackupExportServiceError.invalidGeneration
                }
            }
            try verifyStagingAuthority()
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: stagingRoot)
            try verifyStagingAuthority()
        } catch let error as BackupExportServiceError {
            throw error
        } catch {
            throw BackupExportServiceError.invalidGeneration
        }

        let stagingRootDescriptor = Darwin.open(
            stagingRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard stagingRootDescriptor >= 0 else {
            throw BackupExportServiceError.invalidGeneration
        }
        defer { _ = Darwin.close(stagingRootDescriptor) }
        var stagingRootInformation = stat()
        guard Darwin.fstat(stagingRootDescriptor, &stagingRootInformation) == 0,
              (stagingRootInformation.st_mode & S_IFMT) == S_IFDIR else {
            throw BackupExportServiceError.invalidGeneration
        }
        let stagingRootIdentity = StreamingArchiveRootIdentityV1(
            device: UInt64(stagingRootInformation.st_dev),
            inode: UInt64(stagingRootInformation.st_ino)
        )
        let generationSourceRootIdentity = StreamingArchiveRootIdentityV1(
            device: UInt64(pinnedGenerationRootIdentity.device),
            inode: UInt64(pinnedGenerationRootIdentity.inode)
        )
        let draftSourceRoot = generationRootURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,isDirectory:true)
        let draftDescriptor = Darwin.open(draftSourceRoot.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
        var draftInfo = stat()
        let hasDraftSources = frozen.sources.contains { if case .draftRelative = $0.location{return true};return false }
        guard !hasDraftSources || (draftDescriptor >= 0 && Darwin.fstat(draftDescriptor,&draftInfo)==0 && (draftInfo.st_mode&S_IFMT)==S_IFDIR) else { if draftDescriptor>=0{Darwin.close(draftDescriptor)};throw BackupExportServiceError.invalidGeneration }
        if draftDescriptor>=0{Darwin.close(draftDescriptor)}
        let draftSourceRootIdentity = StreamingArchiveRootIdentityV1(device:UInt64(draftInfo.st_dev),inode:UInt64(draftInfo.st_ino))

        let manifestSource = stagingRoot.appendingPathComponent(
            ".backup-export-\(Self.uuid(frozen.preview.id))-manifest.json"
        )
        let recordsSource = stagingRoot.appendingPathComponent(
            ".backup-export-\(Self.uuid(frozen.preview.id))-records.json"
        )
        let portableExchangeSnapshotSource = stagingRoot.appendingPathComponent(
            ".backup-export-\(Self.uuid(frozen.preview.id))-portable-exchange.json"
        )
        var createdSources = [OwnedStagingSource]()
        var publishedReceipt: StreamingArchiveWriteReceiptV1?
        do {
            createdSources.append(try Self.writeOwnedStagingSource(
                frozen.manifestData,
                to: manifestSource,
                expectedRootIdentity: stagingRootIdentity,
                archiveLimits: archiveLimits
            ))
            createdSources.append(try Self.writeOwnedStagingSource(
                frozen.recordsData,
                to: recordsSource,
                expectedRootIdentity: stagingRootIdentity,
                archiveLimits: archiveLimits
            ))
            createdSources.append(try Self.writeOwnedStagingSource(
                frozen.portableExchangeSnapshotData,
                to: portableExchangeSnapshotSource,
                expectedRootIdentity: stagingRootIdentity,
                archiveLimits: archiveLimits
            ))
            var generatedPhotoNames: [String: String] = [:]
            for (offset, path) in frozen.generatedPhotoMetadata.keys.sorted().enumerated() {
                guard let bytes = frozen.generatedPhotoMetadata[path] else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let name = ".backup-export-\(Self.uuid(frozen.preview.id))-photo-\(offset).json"
                createdSources.append(try Self.writeOwnedStagingSource(bytes,
                    to: stagingRoot.appendingPathComponent(name),
                    expectedRootIdentity: stagingRootIdentity, archiveLimits: archiveLimits))
                generatedPhotoNames[path] = name
            }
            try generationLeaseValidation()

            var entries = [StreamingArchiveWriteEntryV1(
                path: "manifest.json",
                mimeType: "application/json",
                sourceRootURL: stagingRoot,
                sourceRelativePath: manifestSource.lastPathComponent,
                expectedSourceRootIdentity: stagingRootIdentity,
                expectedUncompressedByteCount: Int64(frozen.manifestData.count),
                expectedContentSHA256: CanonicalJSONV1.sha256(frozen.manifestData),
                compression: .stored
            )]
            entries.append(contentsOf: try frozen.sources.map { source in
                let sourceRootURL: URL
                let sourceRelativePath: String
                let expectedSourceRootIdentity: StreamingArchiveRootIdentityV1
                switch source.location {
                case .generatedRecords:
                    sourceRootURL = stagingRoot
                    sourceRelativePath = recordsSource.lastPathComponent
                    expectedSourceRootIdentity = stagingRootIdentity
                case .generatedPortableExchangeSnapshot:
                    sourceRootURL = stagingRoot
                    sourceRelativePath = portableExchangeSnapshotSource.lastPathComponent
                    expectedSourceRootIdentity = stagingRootIdentity
                case .generatedPhotoMetadata(let path):
                    guard let name = generatedPhotoNames[path] else {
                        throw BackupExportServiceError.invalidAuthority
                    }
                    sourceRootURL = stagingRoot
                    sourceRelativePath = name
                    expectedSourceRootIdentity = stagingRootIdentity
                case .generationRelative(let relativePath):
                    sourceRootURL = generationRootURL
                    sourceRelativePath = relativePath
                    expectedSourceRootIdentity = generationSourceRootIdentity
                case .draftRelative(let relativePath):
                    sourceRootURL = draftSourceRoot
                    sourceRelativePath = relativePath
                    expectedSourceRootIdentity = draftSourceRootIdentity
                }
                return StreamingArchiveWriteEntryV1(
                    path: source.path,
                    mimeType: source.mimeType,
                    sourceRootURL: sourceRootURL,
                    sourceRelativePath: sourceRelativePath,
                    expectedSourceRootIdentity: expectedSourceRootIdentity,
                    expectedUncompressedByteCount: Int64(source.byteCount),
                    expectedContentSHA256: source.sha256,
                    compression: .stored
                )
            })
            let plan = StreamingArchiveWritePlanV1(
                entries: entries,
                stagingDirectoryURL: stagingRoot
            )
            var coordinationError: NSError?
            var coordinatedResult: Result<StreamingArchiveWriteReceiptV1, Error>?
            NSFileCoordinator().coordinate(
                writingItemAt: destination,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedDirectory in
                let coordinatedPackage = coordinatedDirectory.appendingPathComponent(
                    packageURL.lastPathComponent,
                    isDirectory: false
                )
                coordinatedResult = Result {
                    try archiveService.write(
                        plan,
                        to: coordinatedPackage,
                        cancellation: cancellation,
                        storageCheck: { requiredBytes in
                            try storagePreflight.checkBackupExport(
                                declaredPayloadByteCount: requiredBytes,
                                onVolumeContaining: coordinatedDirectory
                            )
                        }
                    )
                }
            }
            guard coordinationError == nil, let coordinatedResult else {
                throw BackupExportServiceError.writeFailed
            }
            let receipt = try coordinatedResult.get()
            publishedReceipt = receipt
            try generationLeaseValidation()
            guard receipt.index.entries.map(\.path) == entries
                    .sorted(by: { Self.utf8Less($0.path, $1.path) })
                    .map(\.path),
                  receipt.index.uncompressedPayloadByteCount
                    == Int64(frozen.manifestData.count)
                        + Int64(frozen.preview.declaredPayloadByteCount),
                  try StreamingArchiveService.hasFormatMagic(at: receipt.archiveURL) else {
                throw BackupExportServiceError.writeFailed
            }
            try Self.cleanupOwnedStagingSources(
                createdSources,
                within: stagingRoot,
                directoryDescriptor: stagingRootDescriptor,
                expectedRootIdentity: stagingRootIdentity
            )
            createdSources.removeAll()
            return receipt
        } catch {
            let original = error
            let cleaned = (try? Self.cleanupOwnedStagingSources(
                createdSources,
                within: stagingRoot,
                directoryDescriptor: stagingRootDescriptor,
                expectedRootIdentity: stagingRootIdentity
            )) != nil
            if let publishedReceipt,
               (try? Self.removeOwnedPublishedArchive(publishedReceipt, within: destination)) == nil {
                throw BackupExportServiceError.cleanupFailed
            }
            guard cleaned else { throw BackupExportServiceError.cleanupFailed }
            throw Self.mapStreamingExportError(original)
        }
    }
}

private extension BackupExportService {
    /// The only quiescence allowed by an explicit backup action is acknowledging
    /// an already-published raw file or marked pair. Every actor hop retains
    /// the original access publication and exact expected writer interval.
    private func freezePhotoExport(previewID: UUID,
        operation: AppAccessPresentationV1.BackupOperationAccess) async throws -> PhotoExportFreeze {
        guard let frozen = streamingPrepared, frozen.preview.id == previewID,
              let rootIdentity else { throw BackupExportServiceError.stalePreview }
        let store = try operation.withAuthorization { $0 }
        let initialRevision = try operation.withAuthorization { try $0.workspaceWriter.currentRevision() }
        var current = try buildStreamingPrepared(previewID: previewID, exportedAt: frozen.manifest.exportedAt)
        guard current == frozen else { throw BackupExportServiceError.stalePreview }
        var revision = initialRevision
        func validateInterval() throws {
            guard !Task.isCancelled else { throw BackupExportServiceError.cancelled }
            try operation.withAuthorization { currentStore in
                guard currentStore === store, try currentStore.workspaceWriter.currentRevision() == revision,
                      revision.revision == current.mutationHistory.workspaceRevision else {
                    throw BackupExportServiceError.stalePreview
                }
            }
        }
        try validateInterval()
        let support = store.checkRunnerPhotoApplicationSupportURL
        let rootObservation = try DraftAttachmentStagingAdapterV1.observePhotoBackupRoot(
            applicationSupportURL: support, workspaceID: current.photoHistory.sourceWorkspaceID)

        func acknowledge(_ mutationID: MutationIDV1?) throws {
            let observed = try operation.withAuthorization { try $0.workspaceWriter.currentRevision() }
            let (expected, overflow) = revision.revision.addingReportingOverflow(mutationID == nil ? 0 : 1)
            guard !overflow, observed.workspaceID == revision.workspaceID,
                  observed.generationID == revision.generationID,
                  observed.writerInstanceID == revision.writerInstanceID,
                  observed.revision == expected else { throw BackupExportServiceError.stalePreview }
            let rebuilt = try buildStreamingPrepared(previewID: previewID, exportedAt: frozen.manifest.exportedAt)
            try Self.validatePhotoAcknowledgement(from: current.mutationHistory,
                to: rebuilt.mutationHistory, mutationID: mutationID)
            current = rebuilt; revision = observed
            try validateInterval()
        }

        if case .existing(let staging) = rootObservation {
            let childIDs = current.photoHistory.children.map { $0.currentCheckpoint.draftID }
            for childID in childIDs {
                try validateInterval()
                guard var child = current.photoHistory.children.first(where: { $0.currentCheckpoint.draftID == childID }) else {
                    throw BackupExportServiceError.stalePreview
                }
                let service = try operation.makePhotoService(parentCheckpoint: child.parentCheckpoint, staging: staging)
                if case .awaitingRawStage = child.payload.phase {
                    let result = try await service.adoptExistingRawPhotoForBackup(
                        parentDraftID: child.parentCheckpoint.draftID, childDraftID: childID, authorizing: operation)
                    try acknowledge(result?.envelope.mutationID)
                    guard let updated = current.photoHistory.children.first(where: { $0.currentCheckpoint.draftID == childID }) else {
                        throw BackupExportServiceError.stalePreview
                    }
                    child = updated
                }
                if case .rawReady = child.payload.phase {
                    let result = try await service.adoptExistingPhotoPairForBackup(
                        parentDraftID: child.parentCheckpoint.draftID, childDraftID: childID, authorizing: operation)
                    try acknowledge(result?.mutationID)
                }
            }
        }

        var rawSnapshots: [DraftPhotoRawBackupSnapshotV1] = []
        let children = current.photoHistory.children
        let canonicalStages = try fetchRows().attachmentStagingItems.map { try $0.value() }
        let childStageIDs = Dictionary(uniqueKeysWithValues: children.map {
            ($0.currentCheckpoint.draftID, $0.payload.phase.intent.stageID)
        })
        let rawVerification: PhotoRawVerification
        switch rootObservation {
        case .existing(let staging):
            for child in children {
                guard let raw = child.raw else { continue }
                let snapshot = try await staging.readPhotoBackupSnapshot(raw: raw, committingCheckpoint: child.committingCheckpoint)
                try validateInterval()
                rawSnapshots.append(snapshot)
            }
            let committing = Dictionary(uniqueKeysWithValues: children.compactMap { child in
                child.committingCheckpoint.map { (child.currentCheckpoint.draftID, $0) }
            })
            let value = try await staging.preparePhotoBackupVerification(rawSnapshots,
                committingCheckpoints: committing, canonicalStages: canonicalStages, childStageIDs: childStageIDs)
            try validateInterval()
            rawVerification = .existing(value)
        case .absent(let observation):
            guard children.allSatisfy({ $0.raw == nil }) else { throw BackupExportServiceError.invalidAuthority }
            rawVerification = .absent(try observation.preparePhotoBackupVerification(
                canonicalStages: canonicalStages, childStageIDs: childStageIDs))
        }
        let mediaStore = EvidenceBundleStore(generationRootURL: generationRootURL)
        let mediaVerification = try await mediaStore.prepareCheckRunnerPhotoBackupMedia(
            children: children, expectedGenerationRootIdentity: rootIdentity)
        try validateInterval()
        let snapshot = PhotoStreamingSnapshot(history: current.photoHistory, raw: rawSnapshots,
            media: mediaVerification.snapshots)
        let ready = try buildStreamingPrepared(previewID: previewID, exportedAt: frozen.manifest.exportedAt,
            photoSnapshot: snapshot)
        guard ready.mutationHistory == current.mutationHistory,
              ready.recordsData == current.recordsData else { throw BackupExportServiceError.stalePreview }
        try validateInterval()
        let observations = try observeStreamingSources(ready)
        try validateInterval()
        return PhotoExportFreeze(prepared: ready, revision: revision,
            rawVerification: rawVerification, mediaVerification: mediaVerification,
            observedSources: observations)
    }

    private func observeStreamingSources(_ prepared: StreamingPrepared) throws -> [ObservedStreamingSource] {
        guard let rootIdentity else { throw BackupExportServiceError.invalidGeneration }
        let generationIdentity = StreamingArchiveRootIdentityV1(device: UInt64(rootIdentity.device), inode: UInt64(rootIdentity.inode))
        let draftRoot = generationRootURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName, isDirectory: true)
        var draftIdentity: StreamingArchiveRootIdentityV1?
        var result: [ObservedStreamingSource] = []
        for source in prepared.sources {
            let root: URL, relative: String, identity: StreamingArchiveRootIdentityV1
            switch source.location {
            case .generatedRecords, .generatedPortableExchangeSnapshot, .generatedPhotoMetadata:
                continue
            case .generationRelative(let path):
                root = generationRootURL; relative = path; identity = generationIdentity
            case .draftRelative(let path):
                if draftIdentity == nil {
                    let descriptor = Darwin.open(draftRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    guard descriptor >= 0 else { throw BackupExportServiceError.invalidGeneration }
                    defer { Darwin.close(descriptor) }
                    var information = stat()
                    guard Darwin.fstat(descriptor, &information) == 0, (information.st_mode & S_IFMT) == S_IFDIR else {
                        throw BackupExportServiceError.invalidGeneration
                    }
                    draftIdentity = .init(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
                }
                guard let draftIdentity else { throw BackupExportServiceError.invalidGeneration }
                root = draftRoot; relative = path; identity = draftIdentity
            }
            let entry = StreamingArchiveWriteEntryV1(path: source.path, mimeType: source.mimeType,
                sourceRootURL: root, sourceRelativePath: relative, expectedSourceRootIdentity: identity,
                expectedUncompressedByteCount: Int64(source.byteCount), expectedContentSHA256: source.sha256,
                compression: .stored)
            result.append(.init(entry: entry, observation: try archiveService.sourceObservation(entry)))
        }
        return result
    }

    /// Runs only inside `withCheckRunnerPhotoPublication`. Every nested
    /// identity read (including fetchRows/makeRecords) is resolved through
    /// that same coordinator's registry, never a fresh one.
    private func validateFrozenCanonical(_ prepared: StreamingPrepared,
        publicationStore: StoreSessionCoordinator) throws {
        guard lockedPublicationStore == nil else { throw BackupExportServiceError.stalePreview }
        lockedPublicationStore = publicationStore
        defer { lockedPublicationStore = nil }
        guard !modelContext.hasChanges,
              try currentStreamingWorkspaceIdentity() == prepared.checkpointBasis.workspaceIdentity,
              try currentStreamingGenerationID() == prepared.checkpointBasis.generationID else {
            throw BackupExportServiceError.stalePreview
        }
        let history = try MutationJournalStoreV1(modelContext: modelContext,
            identity: prepared.checkpointBasis.workspaceIdentity,
            generationID: prepared.checkpointBasis.generationID).exportSnapshot()
        guard history == prepared.mutationHistory else { throw BackupExportServiceError.stalePreview }
        let rows = try fetchRows()
        let ledger = try DeletionLedgerStore(context: modelContext).snapshot()
        let records = try makeRecords(rows, deletionLedger: ledger, mutationHistory: history)
        guard try BackupCanonicalEncoderV1().encodeRecords(records).data == prepared.recordsData,
              try portableExchangeBackupSnapshotData(snapshotID: prepared.preview.id,
                createdAt: prepared.manifest.exportedAt) == prepared.portableExchangeSnapshotData,
              !modelContext.hasChanges else { throw BackupExportServiceError.stalePreview }
    }

    nonisolated static func validatePhotoAcknowledgement(from before: MutationHistorySnapshotV1,
        to after: MutationHistorySnapshotV1, mutationID: MutationIDV1?) throws {
        guard let mutationID else {
            guard before == after else { throw BackupExportServiceError.stalePreview }
            return
        }
        let (revision, revisionOverflow) = before.workspaceRevision.addingReportingOverflow(1)
        let (sequence, sequenceOverflow) = before.lastLocalSequence.addingReportingOverflow(1)
        guard !revisionOverflow, !sequenceOverflow, after.workspaceRevision == revision,
              after.lastLocalSequence == sequence, after.quarantines == before.quarantines,
              after.receipts.count == before.receipts.count + 1 else { throw BackupExportServiceError.stalePreview }
        // Full original records, including reversal bytes, remain byte-for-byte.
        var remaining = after.receipts
        for original in before.receipts {
            guard let index = remaining.firstIndex(of: original) else { throw BackupExportServiceError.stalePreview }
            remaining.remove(at: index)
        }
        guard remaining.count == 1 else { throw BackupExportServiceError.stalePreview }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(MutationEnvelopeV1.self, from: remaining[0].envelopeData)
        let receipt = try decoder.decode(MutationReceiptV1.self, from: remaining[0].receiptData)
        guard try WorkspaceMutationCanonicalV1.data(envelope) == remaining[0].envelopeData,
              try WorkspaceMutationCanonicalV1.data(receipt) == remaining[0].receiptData else {
            throw BackupExportServiceError.stalePreview
        }
        let original = try FieldDraftCommittedEvidenceV1(envelope: envelope, receipt: receipt)
        guard original.envelope.mutationID == mutationID else { throw BackupExportServiceError.stalePreview }
    }

    private func buildStreamingPrepared(
        previewID: UUID,
        exportedAt: Date,
        photoSnapshot: PhotoStreamingSnapshot? = nil
    ) throws -> StreamingPrepared {
#if DEBUG
        var backupTracePhase = "identity"
        var backupTraceCompleted = false
        defer {
            if !backupTraceCompleted {
                FileHandle.standardError.write(Data(
                    "BackupExportService.buildStreamingPrepared failure phase=\(backupTracePhase)\n".utf8
                ))
            }
        }
#endif
        guard let rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        let sourceIdentity = try currentStreamingWorkspaceIdentity()
        let generationID = try currentStreamingGenerationID()
#if DEBUG
        backupTracePhase = "rows"
#endif
        let rows = try fetchRows()
#if DEBUG
        backupTracePhase = "lifecycle-backup"
#endif
        try validateLifecycleScope(rows, operation: .backup)
#if DEBUG
        backupTracePhase = "lifecycle-archive"
#endif
        try validateLifecycleScope(rows, operation: .archive)
#if DEBUG
        backupTracePhase = "deletion-ledger"
#endif
        let deletionLedger: DeletionLedgerV2
        do {
            deletionLedger = try DeletionLedgerStore(context: modelContext).snapshot()
            try validateDeletionLedger(deletionLedger, rows: rows)
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
#if DEBUG
        backupTracePhase = "graph"
#endif
        try validateGraph(rows, deletionLedger: deletionLedger)
#if DEBUG
        backupTracePhase = "mutation-history"
#endif
        let mutationHistory: MutationHistorySnapshotV1
        do {
            mutationHistory = try MutationJournalStoreV1(
                modelContext: modelContext,
                identity: sourceIdentity,
                generationID: generationID
            ).exportSnapshot()
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
#if DEBUG
        backupTracePhase = "records"
#endif
        let records = try makeRecords(
            rows,
            deletionLedger: deletionLedger,
            mutationHistory: mutationHistory
        )
        let source = V4BackupSourceV1(
            appBuild: appBuild(), appVersion: appVersion(),
            persistentSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,
            replicaID: sourceIdentity.replicaID.rawValue,
            recordsSchemaVersion: records.recordsSchemaVersion,
            sourceGenerationID: generationID, workspaceID: sourceIdentity.workspaceID.rawValue)
        let photoHistory = try CheckRunnerPhotoBackupHistoryV1.project(source: source, records: records)
        guard photoSnapshot.map({ $0.history == photoHistory }) ?? true else {
            throw BackupExportServiceError.stalePreview
        }
        var parentFinalizationsByReport: [UUID: [CheckRunnerItemFinalizationEvidenceV1]] = [:]
        for parent in photoHistory.parentFinalizations {
            guard !Task.isCancelled else { throw BackupExportServiceError.cancelled }
            let profile = try lifecycleProfile(parent.editing.parent.source.legacyPackageIdentity)
            try parent.validatePreparedOutcome(profile: profile)
            if parent.target != nil {
                let reportID = parent.attempt.identifiers.reportID
                let reports = records.reports.filter { $0.id == reportID }
                guard reports.count == 1, let report = reports.first else { throw BackupExportServiceError.invalidAuthority }
                try parent.validateTargetReport(report)
                parentFinalizationsByReport[reportID, default: []].append(parent)
            }
        }
        let photoChildIDs = Set(photoHistory.children.map { $0.currentCheckpoint.draftID })
        let photoEvidenceIDs = Set(photoHistory.children.compactMap { $0.targetRecords?.evidence.id })
        var generatedPhotoMetadata: [String: Data] = [:]
#if DEBUG
        backupTracePhase = "canonical-records"
#endif
        let recordsData: Data
        let semanticRecordsData: Data
        let portableExchangeSnapshotData: Data
        do {
            recordsData = try BackupCanonicalEncoderV1().encodeRecords(records).data
#if DEBUG
            backupTracePhase = "canonical-semantic"
#endif
            semanticRecordsData = try BackupCanonicalEncoderV1()
                .encodeSemanticRecords(records).data
#if DEBUG
            backupTracePhase = "portable-exchange"
#endif
            portableExchangeSnapshotData = try portableExchangeBackupSnapshotData(
                snapshotID: previewID,
                createdAt: exportedAt
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
#if DEBUG
        backupTracePhase = "record-budgets"
#endif
        guard Int64(recordsData.count) <= archiveLimits.maximumUncompressedEntryByteCount,
              Int64(semanticRecordsData.count)
                <= archiveLimits.maximumUncompressedEntryByteCount else {
            throw BackupExportServiceError.invalidAuthority
        }

#if DEBUG
        backupTracePhase = "content-inventory"
#endif
        var sources = [StreamingSource(
            path: "records.json",
            mimeType: "application/json",
            byteCount: recordsData.count,
            sha256: CanonicalJSONV1.sha256(recordsData),
            location: .generatedRecords
        )]
        sources.append(StreamingSource(
            path: PortableExchangeBackupMemberV2.path,
            mimeType: PortableExchangeBackupMemberV2.mimeType,
            byteCount: portableExchangeSnapshotData.count,
            sha256: CanonicalJSONV1.sha256(portableExchangeSnapshotData),
            location: .generatedPortableExchangeSnapshot
        ))
        let normalizer = MediaNormalizerV1()
        for evidence in rows.evidence.sorted(by: { Self.uuid($0.id) < Self.uuid($1.id) }) {
            guard !Task.isCancelled else {
                throw BackupExportServiceError.cancelled
            }
            try validateGenerationLease()
            let canonicalID = Self.uuid(evidence.id)
            guard evidence.relativePath == "evidence/\(canonicalID)/original.jpg",
                  evidence.thumbnailRelativePath
                    == "evidence/\(canonicalID)/thumbnail.jpg",
                  evidence.mimeType == "image/jpeg",
                  evidence.byteCount >= 0,
                  evidence.thumbnailByteCount >= 0,
                  Int64(evidence.byteCount)
                    <= archiveLimits.maximumUncompressedEntryByteCount,
                  Int64(evidence.thumbnailByteCount)
                    <= archiveLimits.maximumUncompressedEntryByteCount else {
                throw BackupExportServiceError.invalidAuthority
            }
            if !photoEvidenceIDs.contains(evidence.id) {
            do {
                let original = try boundedStreamingRead(
                    evidence.relativePath,
                    expectedByteCount: Int64(evidence.byteCount),
                    expectedSHA256: evidence.sha256,
                    rootIdentity: rootIdentity
                )
                _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
            }
            do {
                let thumbnail = try boundedStreamingRead(
                    evidence.thumbnailRelativePath,
                    expectedByteCount: Int64(evidence.thumbnailByteCount),
                    expectedSHA256: evidence.thumbnailSHA256,
                    rootIdentity: rootIdentity
                )
                _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            }
            }
            sources.append(.init(
                path: V4BackupEvidenceMemberKeyV1.original(evidence.id),
                mimeType: "image/jpeg",
                byteCount: evidence.byteCount,
                sha256: evidence.sha256,
                location: .generationRelative(evidence.relativePath)
            ))
            sources.append(.init(
                path: V4BackupEvidenceMemberKeyV1.thumbnail(evidence.id),
                mimeType: "image/jpeg",
                byteCount: evidence.thumbnailByteCount,
                sha256: evidence.thumbnailSHA256,
                location: .generationRelative(evidence.thumbnailRelativePath)
            ))
        }

        var archivedTemporalOriginalPaths = Set<String>()
        for clip in try rows.temporalEvidenceClips.map({ try $0.value() }).sorted(by: {
            $0.clipID.uuidString.lowercased() < $1.clipID.uuidString.lowercased()
        }) {
            try clip.validateIntrinsic()
            let path = try TemporalEvidenceBackupMemberV1.original(for: clip)
            guard clip.original.byteLength >= 0,
                  clip.original.byteLength <= archiveLimits.maximumUncompressedEntryByteCount,
                  let digest = clip.original.digests.digest(for: .sha256)?.hexadecimalValue else {
                throw BackupExportServiceError.invalidAuthority
            }
            _ = try boundedStreamingRead(
                path,
                expectedByteCount: clip.original.byteLength,
                expectedSHA256: digest,
                rootIdentity: rootIdentity
            )
            if archivedTemporalOriginalPaths.insert(path).inserted {
                sources.append(.init(
                    path: path,
                    mimeType: clip.original.mediaType,
                    byteCount: Int(clip.original.byteLength),
                    sha256: digest,
                    location: .generationRelative(path)
                ))
            } else {
                guard let existing = sources.first(where: { $0.path == path }),
                      existing.byteCount == Int(clip.original.byteLength),
                      existing.sha256 == digest,
                      existing.mimeType == clip.original.mediaType else {
                    throw BackupExportServiceError.invalidAuthority
                }
            }
        }

        for member in try evidenceDerivativeMembers(records, rootIdentity: rootIdentity) {
            sources.append(.init(
                path: member.path,
                mimeType: member.mimeType,
                byteCount: member.data.count,
                sha256: CanonicalJSONV1.sha256(member.data),
                location: .generationRelative(member.path)
            ))
        }

        for item in try rows.attachmentStagingItems.map({try $0.value()}).sorted(by:{$0.stageID.uuidString<$1.stageID.uuidString}){
            guard !photoChildIDs.contains(item.draftID) else { continue }
            guard let byteCount=item.actualByteCount else{continue}
            guard byteCount >= 0, byteCount <= Int64(FieldDraftLimitsV1.maximumPayloadBytes) else {
                throw BackupExportServiceError.invalidAuthority
            }
            let relative=DraftAttachmentStagingAdapterV1.relativeDataPath(draftID:item.draftID,stageID:item.stageID)
            let draftRoot=generationRootURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,isDirectory:true)
            let bytes=try Data(contentsOf:draftRoot.appendingPathComponent(relative),options:.mappedIfSafe)
            let expectedSHA=item.contentReference?.digests.digest(for:.sha256)?.hexadecimalValue ?? (item.contentDigest?.algorithm == .sha256 ? item.contentDigest?.hexadecimalValue:nil)
            guard bytes.count==Int(byteCount),let expectedSHA,CanonicalJSONV1.sha256(bytes)==expectedSHA else{throw BackupExportServiceError.invalidAuthority}
            sources.append(.init(path:"draft-staging/\(Self.uuid(item.draftID))/\(Self.uuid(item.stageID)).bin",mimeType:"application/octet-stream",byteCount:bytes.count,sha256:expectedSHA,location:.draftRelative(relative)))
        }

        if let photoSnapshot {
            let additions = try photoStreamingSources(photoSnapshot)
            generatedPhotoMetadata = additions.metadata
            for source in additions.sources {
                if let existing = sources.first(where: { $0.path == source.path }) {
                    guard existing == source else { throw BackupExportServiceError.invalidAuthority }
                } else { sources.append(source) }
            }
        }

        for report in rows.reports.sorted(by: { Self.uuid($0.id) < Self.uuid($1.id) }) {
            guard !Task.isCancelled else {
                throw BackupExportServiceError.cancelled
            }
            try validateGenerationLease()
            let profile = try lifecycleProfile(for: report, rows: rows)
            let delivery: ReportDeliveryCoordinator
            do {
                delivery = try ReportDeliveryCoordinator(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    signPack: profile.package,
                    expectedRootIdentity: rootIdentity
                )
                try delivery.validateRecoveryAuthority(id: report.id)
            }
            catch { throw BackupExportServiceError.invalidAuthority }
            let canonicalID = Self.uuid(report.id)
            guard (report.snapshotSchemaVersion == 1
                    || report.snapshotSchemaVersion == 2),
                  report.snapshotRelativePath == "snapshots/\(canonicalID).json" else {
                throw BackupExportServiceError.invalidAuthority
            }
            let snapshotByteCount: Int = try {
                let snapshot = try boundedStreamingRead(
                    report.snapshotRelativePath,
                    expectedByteCount: nil,
                    expectedSHA256: report.snapshotSHA256,
                    rootIdentity: rootIdentity
                )
                if let parents = parentFinalizationsByReport[report.id] {
                    let decoded = try ReportSnapshotEncoderV1().decode(snapshot)
                    for parent in parents { try parent.validateTargetSnapshot(decoded) }
                }
                return snapshot.count
            }()
            sources.append(.init(
                path: report.snapshotRelativePath,
                mimeType: "application/json",
                byteCount: snapshotByteCount,
                sha256: report.snapshotSHA256,
                location: .generationRelative(report.snapshotRelativePath)
            ))
            switch ReportPDFState(rawValue: report.pdfState) {
            case .ready:
                let path = "pdfs/\(canonicalID).pdf"
                guard report.pdfRelativePath == path,
                      let expectedHash = report.pdfSHA256 else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let pdf = try boundedStreamingRead(
                    path,
                    expectedByteCount: nil,
                    expectedSHA256: expectedHash,
                    rootIdentity: rootIdentity
                )
                guard pdf.starts(with: Data("%PDF-".utf8)) else {
                    throw BackupExportServiceError.invalidAuthority
                }
                sources.append(.init(
                    path: path,
                    mimeType: "application/pdf",
                    byteCount: pdf.count,
                    sha256: expectedHash,
                    location: .generationRelative(path)
                ))
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else {
                    throw BackupExportServiceError.invalidAuthority
                }
            case nil:
                throw BackupExportServiceError.invalidAuthority
            }
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity,
              try currentStreamingWorkspaceIdentity() == sourceIdentity,
              try DeletionLedgerStore(context: modelContext).snapshot()
                == deletionLedger,
              try MutationJournalStoreV1(
                  modelContext: modelContext,
                  identity: sourceIdentity,
                  generationID: generationID
              ).exportSnapshot() == mutationHistory,
              !modelContext.hasChanges else {
            throw BackupExportServiceError.invalidGeneration
        }

        sources.sort { Self.utf8Less($0.path, $1.path) }
#if DEBUG
        backupTracePhase = "budget"
#endif
        guard sources.count + 1 <= archiveLimits.maximumEntryCount else {
            throw BackupExportServiceError.invalidAuthority
        }
        var declaredPayloadByteCount = 0
        let entries = try sources.map { source -> V4BackupEntryV1 in
            let (next, overflow) = declaredPayloadByteCount.addingReportingOverflow(
                source.byteCount
            )
            guard !overflow else {
                throw BackupExportServiceError.invalidAuthority
            }
            guard Int64(next) <= archiveLimits.maximumUncompressedAggregateByteCount else {
                throw BackupExportServiceError.invalidAuthority
            }
            declaredPayloadByteCount = next
            return V4BackupEntryV1(
                byteCount: source.byteCount,
                mimeType: source.mimeType,
                path: source.path,
                sha256: source.sha256
            )
        }
#if DEBUG
        backupTracePhase = "manifest"
#endif
        let packs = try manifestPacks(rows)
        let packageReleases: [PackageReleaseIdentityV1]
        do {
            packageReleases = try packs.map {
                try PackageReleaseIdentityV1(
                    packageID: $0.packID,
                    schemaVersion: $0.schemaVersion,
                    contentVersion: $0.contentVersion
                )
            }.sorted()
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 4,
            consumedEvaluationRootIDs: rows.packets
                .filter(\.evaluationCounted)
                .map(\.stableRootID)
                .sorted { Self.uuid($0) < Self.uuid($1) },
            declaredPayloadByteCount: declaredPayloadByteCount,
            entries: entries,
            exportedAt: exportedAt,
            packs: packs,
            source: source
        )
        let manifestData: Data
#if DEBUG
        backupTracePhase = "canonical-manifest"
#endif
        do {
            manifestData = try BackupCanonicalEncoderV1().encodeManifest(manifest).data
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
#if DEBUG
        backupTracePhase = "manifest-budgets"
#endif
        guard manifestData.count <= archiveLimits.maximumIndexByteCount,
              Int64(manifestData.count)
                <= archiveLimits.maximumUncompressedEntryByteCount else {
            throw BackupExportServiceError.invalidAuthority
        }
        let checkpointBasis = BackupCanonicalCheckpointBasisV1(
            workspaceIdentity: sourceIdentity,
            generationID: generationID,
            persistentSchemaVersion: manifest.source.persistentSchemaVersion,
            recordsSchemaVersion: manifest.source.recordsSchemaVersion,
            packageReleases: packageReleases,
            workspaceRevision: mutationHistory.workspaceRevision,
            lastLocalSequence: mutationHistory.lastLocalSequence,
            recordsData: recordsData,
            semanticRecordsData: semanticRecordsData,
            memberInventory: entries
        )
#if DEBUG
        backupTraceCompleted = true
#endif
        return StreamingPrepared(
            preview: .init(
                id: previewID,
                signCount: rows.assets.count,
                reportCount: rows.reports.count,
                photoCount: rows.evidence.count,
                declaredPayloadByteCount: declaredPayloadByteCount
            ),
            manifest: manifest,
            manifestData: manifestData,
            recordsData: recordsData,
            portableExchangeSnapshotData: portableExchangeSnapshotData,
            mutationHistory: mutationHistory,
            checkpointBasis: checkpointBasis,
            sources: sources,
            photoHistory: photoHistory,
            generatedPhotoMetadata: generatedPhotoMetadata
        )
    }

    private func photoStreamingSources(_ snapshot: PhotoStreamingSnapshot) throws
        -> (sources: [StreamingSource], metadata: [String: Data]) {
        let children = snapshot.history.children
        guard Set(snapshot.raw.map { $0.raw.readyItem.draftID }).count == snapshot.raw.count,
              Set(snapshot.media.map(\.childDraftID)).count == snapshot.media.count,
              Set(snapshot.raw.map { $0.raw.readyItem.draftID }) == Set(children.filter { $0.raw != nil }.map { $0.currentCheckpoint.draftID }),
              Set(snapshot.media.map(\.childDraftID)) == Set(children.map { $0.currentCheckpoint.draftID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        var sources: [String: StreamingSource] = [:]
        var metadata: [String: Data] = [:]
        func include(_ source: StreamingSource) throws {
            if let old = sources[source.path], old != source { throw BackupExportServiceError.invalidAuthority }
            sources[source.path] = source
        }
        for raw in snapshot.raw {
            let childID = raw.raw.readyItem.draftID
            let stageID = raw.raw.intent.stageID
            let relative = DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: childID, stageID: stageID)
            func key(_ role: CheckRunnerPhotoBackupMemberKeyV1.Role) -> String {
                CheckRunnerPhotoBackupMemberKeyV1(childDraftID: childID, stageID: stageID, role: role).path
            }
            let witness = try FieldDraftCanonicalCodecV1.encode(raw.raw)
            let entry = try FieldDraftCanonicalCodecV1.encode(raw.physicalEntry)
            metadata[key(.rawPublication)] = witness
            metadata[key(.physicalEntry)] = entry
            try include(.init(path: key(.rawBytes), mimeType: "application/octet-stream",
                byteCount: Int(raw.raw.inspection.sourceByteCount),
                sha256: raw.raw.inspection.sourceSHA256.hexadecimalValue, location: .draftRelative(relative)))
            let witnessRelative = (relative as NSString).deletingLastPathComponent + "/raw-publication.json"
            try include(.init(path: key(.rawPublication), mimeType: "application/json",
                byteCount: witness.count, sha256: CanonicalJSONV1.sha256(witness), location: .draftRelative(witnessRelative)))
            try include(.init(path: key(.physicalEntry), mimeType: "application/json",
                byteCount: entry.count, sha256: CanonicalJSONV1.sha256(entry), location: .generatedPhotoMetadata(key(.physicalEntry))))
        }
        for media in snapshot.media {
            if let marker = media.markerBytes {
                let key = CheckRunnerPhotoBackupMemberKeyV1(childDraftID: media.childDraftID,
                    stageID: media.stageID, role: .stagedPublication)
                metadata[key.path] = marker
            }
            for file in media.files {
                try include(.init(path: file.entry.path, mimeType: file.entry.mimeType,
                    byteCount: file.entry.byteCount, sha256: file.entry.sha256,
                    location: .generationRelative(file.generationRelativePath)))
            }
        }
        let entries = sources.mapValues { V4BackupEntryV1(byteCount: $0.byteCount,
            mimeType: $0.mimeType, path: $0.path, sha256: $0.sha256) }
        var ownedPaths = Set<String>()
        for child in children {
            let plan = try CheckRunnerPhotoBackupPhysicalPlanV1.resolve(child: child,
                descriptors: entries, metadata: { path in
                    guard let bytes = metadata[path] else { throw BackupExportServiceError.invalidAuthority }
                    return bytes
                })
            ownedPaths.formUnion(plan.entries.map(\.path))
        }
        // Shared immutable originals are emitted once, and still need at least
        // one complete authenticated child plan to claim their ownership.
        guard ownedPaths == Set(sources.keys) else { throw BackupExportServiceError.invalidAuthority }
        let generated = metadata.filter { path, _ in
            guard let source = sources[path] else { return false }
            if case .generatedPhotoMetadata = source.location { return true }
            return false
        }
        return (sources.values.sorted { Self.utf8Less($0.path, $1.path) }, generated)
    }

    /// While `lockedPublicationStore` is set (only inside
    /// `withCheckRunnerPhotoPublication`, which holds the generation mutation
    /// lock), the identity is resolved through that coordinator's retained
    /// registry. A fresh factory there self-deadlocks on the lock's flock.
    func currentStreamingWorkspaceIdentity() throws -> WorkspaceReplicaIdentityV1 {
        if let validation = retainedEraseValidation {
            try validation.revalidate(modelContext: modelContext)
            guard generationRootURL == validation.generationRootURL else {
                throw BackupExportServiceError.invalidGeneration
            }
            return validation.workspaceIdentity
        }
        let generationID = try currentStreamingGenerationID()
        let applicationSupportURL = generationRootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        do {
            if let publicationStore = lockedPublicationStore {
                return try publicationStore.currentWorkspaceIdentityWithinPublication(
                    applicationSupportURL: applicationSupportURL,
                    expectedGenerationID: generationID)
            }
            return try StoreGenerationFactory(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            ).currentWorkspaceIdentity(expectedGenerationID: generationID)
        } catch {
            throw BackupExportServiceError.invalidGeneration
        }
    }

    func currentStreamingGenerationID() throws -> UUID {
        guard let generationID = UUID(uuidString: generationRootURL.lastPathComponent),
              generationID.uuidString.lowercased()
                == generationRootURL.lastPathComponent else {
            throw BackupExportServiceError.invalidGeneration
        }
        return generationID
    }

    func portableExchangeBackupSnapshotData(
        snapshotID: UUID,
        createdAt: Date
    ) throws -> Data {
        try PortableExchangeProtectedFilePolicyV2.validate()
        let applicationSupportURL = generationRootURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try PortableExchangeSessionStoreV2.snapshotForBackup(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        let normalized = try PortableExchangeBackupSnapshotV2(
            snapshotID: snapshotID,
            createdAt: createdAt,
            sessions: source.sessions,
            immutablePayloads: source.immutablePayloads,
            protectedCapabilityArtifacts: source.protectedCapabilityArtifacts
        )
        let data = try StoreMigrationCanonicalJSONV1.encode(normalized)
        guard data.count <= PortableExchangeBackupMemberV2.maximumByteCount,
              Int64(data.count) <= archiveLimits.maximumUncompressedEntryByteCount else {
            throw BackupExportServiceError.invalidAuthority
        }
        return data
    }

    func buildPrepared(
        previewID: UUID,
        exportedAt: Date
    ) throws -> PreparedV4BackupV1 {
#if DEBUG
        var legacyBackupTracePhase: String = "identity"
        var legacyBackupTraceCompleted: Bool = false
        defer {
            if !legacyBackupTraceCompleted {
                FileHandle.standardError.write(Data("BackupExportService.buildPrepared failure phase=\(legacyBackupTracePhase)\n".utf8))
            }
        }
#endif
        guard let rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity else {
            throw BackupExportServiceError.invalidGeneration
        }
#if DEBUG
        legacyBackupTracePhase = "rows"
#endif
        let rows = try fetchRows()
#if DEBUG
        legacyBackupTracePhase = "lifecycle-backup"
#endif
        try validateLifecycleScope(rows, operation: .backup)
#if DEBUG
        legacyBackupTracePhase = "lifecycle-archive"
#endif
        try validateLifecycleScope(rows, operation: .archive)
#if DEBUG
        legacyBackupTracePhase = "deletion-ledger"
#endif
        let deletionLedger: DeletionLedgerV2
        do {
            deletionLedger = try DeletionLedgerStore(context: modelContext).snapshot()
            try validateDeletionLedger(deletionLedger, rows: rows)
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
#if DEBUG
        legacyBackupTracePhase = "graph"
#endif
        try validateGraph(rows, deletionLedger: deletionLedger)
#if DEBUG
        legacyBackupTracePhase = "records"
#endif
        let records = try makeRecords(rows)
#if DEBUG
        legacyBackupTracePhase = "canonical-records"
#endif
        let recordsData: Data
        do {
            recordsData = try BackupCanonicalEncoderV1().encodeRecords(records).data
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }

#if DEBUG
        legacyBackupTracePhase = "content-inventory"
#endif
        var members = [V4BackupPackageMemberV1(
            path: "records.json",
            mimeType: "application/json",
            data: recordsData
        )]
        let normalizer = MediaNormalizerV1()
        for evidence in rows.evidence.sorted(by: { Self.uuid($0.id) < Self.uuid($1.id) }) {
            let canonicalID = Self.uuid(evidence.id)
            guard evidence.relativePath == "evidence/\(canonicalID)/original.jpg",
                  evidence.thumbnailRelativePath
                    == "evidence/\(canonicalID)/thumbnail.jpg",
                  evidence.mimeType == "image/jpeg",
                  evidence.byteCount >= 0,
                  evidence.thumbnailByteCount >= 0 else {
                throw BackupExportServiceError.invalidAuthority
            }
            let original = try anchoredRead(evidence.relativePath, rootIdentity: rootIdentity)
            let thumbnail = try anchoredRead(
                evidence.thumbnailRelativePath,
                rootIdentity: rootIdentity
            )
            guard original.count == evidence.byteCount,
                  thumbnail.count == evidence.thumbnailByteCount,
                  CanonicalJSONV1.sha256(original) == evidence.sha256,
                  CanonicalJSONV1.sha256(thumbnail) == evidence.thumbnailSHA256 else {
                throw BackupExportServiceError.invalidAuthority
            }
            do {
                _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
                _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            } catch {
                throw BackupExportServiceError.invalidAuthority
            }
            members.append(.init(
                path: V4BackupEvidenceMemberKeyV1.original(evidence.id),
                mimeType: "image/jpeg",
                data: original
            ))
            members.append(.init(
                path: V4BackupEvidenceMemberKeyV1.thumbnail(evidence.id),
                mimeType: "image/jpeg",
                data: thumbnail
            ))
        }

        for member in try evidenceDerivativeMembers(records, rootIdentity: rootIdentity) {
            members.append(.init(path: member.path, mimeType: member.mimeType, data: member.data))
        }

        for item in try rows.attachmentStagingItems.map({ try $0.value() }).sorted(by: { Self.uuid($0.stageID) < Self.uuid($1.stageID) }) {
            guard let byteCount = item.actualByteCount else { continue }
            let relative = DraftAttachmentStagingAdapterV1.relativeDataPath(draftID:item.draftID,stageID:item.stageID)
            let dataRoot = generationRootURL.deletingLastPathComponent().deletingLastPathComponent()
            let url = dataRoot.appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,isDirectory:true).appendingPathComponent(relative)
            let bytes = try Data(contentsOf:url,options:.mappedIfSafe)
            let expectedSHA = item.contentReference?.digests.digest(for:.sha256)?.hexadecimalValue
                ?? (item.contentDigest?.algorithm == .sha256 ? item.contentDigest?.hexadecimalValue : nil)
            guard bytes.count == Int(byteCount), let expectedSHA,
                  CanonicalJSONV1.sha256(bytes) == expectedSHA else { throw BackupExportServiceError.invalidAuthority }
            members.append(.init(path:"draft-staging/\(Self.uuid(item.draftID))/\(Self.uuid(item.stageID)).bin",mimeType:"application/octet-stream",data:bytes))
        }

        for report in rows.reports.sorted(by: { Self.uuid($0.id) < Self.uuid($1.id) }) {
            let profile = try lifecycleProfile(for: report, rows: rows)
            let delivery: ReportDeliveryCoordinator
            do {
                delivery = try ReportDeliveryCoordinator(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    signPack: profile.package,
                    expectedRootIdentity: rootIdentity
                )
                try delivery.validateRecoveryAuthority(id: report.id)
            }
            catch { throw BackupExportServiceError.invalidAuthority }
            let canonicalID = Self.uuid(report.id)
            guard (report.snapshotSchemaVersion == 1
                    || report.snapshotSchemaVersion == 2),
                  report.snapshotRelativePath == "snapshots/\(canonicalID).json" else {
                throw BackupExportServiceError.invalidAuthority
            }
            let snapshot = try anchoredRead(
                report.snapshotRelativePath,
                rootIdentity: rootIdentity
            )
            guard CanonicalJSONV1.sha256(snapshot) == report.snapshotSHA256 else {
                throw BackupExportServiceError.invalidAuthority
            }
            members.append(.init(
                path: "snapshots/\(canonicalID).json",
                mimeType: "application/json",
                data: snapshot
            ))
            switch ReportPDFState(rawValue: report.pdfState) {
            case .ready:
                guard report.pdfRelativePath == "pdfs/\(canonicalID).pdf",
                      let expectedHash = report.pdfSHA256 else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let pdf = try anchoredRead(
                    "pdfs/\(canonicalID).pdf",
                    rootIdentity: rootIdentity
                )
                guard CanonicalJSONV1.sha256(pdf) == expectedHash,
                      pdf.starts(with: Data("%PDF-".utf8)) else {
                    throw BackupExportServiceError.invalidAuthority
                }
                members.append(.init(
                    path: "pdfs/\(canonicalID).pdf",
                    mimeType: "application/pdf",
                    data: pdf
                ))
            case .pending, .failed:
                guard report.pdfRelativePath == nil, report.pdfSHA256 == nil else {
                    throw BackupExportServiceError.invalidAuthority
                }
            case nil:
                throw BackupExportServiceError.invalidAuthority
            }
        }
#if DEBUG
        legacyBackupTracePhase = "root-revalidation"
#endif
        guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity,
              !modelContext.hasChanges else {
            throw BackupExportServiceError.invalidGeneration
        }

#if DEBUG
        legacyBackupTracePhase = "member-budgets"
#endif
        members.sort { $0.path < $1.path }
        var entries: [V4BackupEntryV1] = []
        var declaredPayloadByteCount = 0
        for member in members {
            let (next, overflow) = declaredPayloadByteCount.addingReportingOverflow(
                member.data.count
            )
            guard !overflow else {
                throw BackupExportServiceError.invalidAuthority
            }
            declaredPayloadByteCount = next
            entries.append(.init(
                byteCount: member.data.count,
                mimeType: member.mimeType,
                path: member.path,
                sha256: CanonicalJSONV1.sha256(member.data)
            ))
        }
#if DEBUG
        legacyBackupTracePhase = "manifest"
#endif
        let packs = try manifestPacks(rows)
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 1,
            consumedEvaluationRootIDs: rows.packets
                .filter(\.evaluationCounted)
                .map(\.stableRootID)
                .sorted { Self.uuid($0) < Self.uuid($1) },
            declaredPayloadByteCount: declaredPayloadByteCount,
            entries: entries,
            exportedAt: exportedAt,
            packs: packs,
            source: .init(
                appBuild: appBuild(),
                appVersion: appVersion(),
                persistentSchemaVersion: 1,
                recordsSchemaVersion: 1
            )
        )
#if DEBUG
        legacyBackupTracePhase = "canonical-manifest"
#endif
        do { _ = try BackupCanonicalEncoderV1().encodeManifest(manifest) }
        catch { throw BackupExportServiceError.invalidAuthority }
#if DEBUG
        legacyBackupTraceCompleted = true
#endif
        return PreparedV4BackupV1(
            preview: .init(
                id: previewID,
                signCount: rows.assets.count,
                reportCount: rows.reports.count,
                photoCount: rows.evidence.count,
                declaredPayloadByteCount: declaredPayloadByteCount
            ),
            records: records,
            manifest: manifest,
            members: members
        )
    }

    struct StreamingSourceSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
        let byteCount: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    struct StreamingDirectoryIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    struct OpenedStreamingSource {
        let descriptor: Int32
        let ancestorDescriptors: [Int32]
        let ancestorIdentities: [StreamingDirectoryIdentity]
    }

    func boundedStreamingRead(
        _ relativePath: String,
        expectedByteCount: Int64?,
        expectedSHA256: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> Data {
        guard validRelativePath(relativePath),
              expectedByteCount.map({
                  $0 >= 0 && $0 <= archiveLimits.maximumUncompressedEntryByteCount
              }) ?? true else {
            throw BackupExportServiceError.invalidAuthority
        }
        let opened = try openStreamingSource(
            relativePath,
            rootIdentity: rootIdentity
        )
        defer {
            _ = Darwin.close(opened.descriptor)
            for descriptor in opened.ancestorDescriptors.reversed() {
                _ = Darwin.close(descriptor)
            }
        }
        let before = try streamingSourceSnapshot(opened.descriptor)
        guard before.byteCount >= 0,
              before.byteCount <= archiveLimits.maximumUncompressedEntryByteCount,
              before.byteCount <= Int64(Int.max),
              expectedByteCount.map({ $0 == before.byteCount }) ?? true else {
            throw BackupExportServiceError.invalidAuthority
        }

        var data = Data()
        data.reserveCapacity(Int(before.byteCount))
        var buffer = [UInt8](repeating: 0, count: archiveLimits.bufferByteCount)
        var remaining = Int64(before.byteCount)
        while remaining > 0 {
            guard !Task.isCancelled else {
                throw BackupExportServiceError.cancelled
            }
            let requested = min(buffer.count, Int(remaining))
            let count: Int = buffer.withUnsafeMutableBytes { raw in
                var result: Int
                repeat {
                    result = Darwin.read(opened.descriptor, raw.baseAddress, requested)
                } while result < 0 && errno == EINTR
                return result
            }
            guard count > 0 else {
                throw BackupExportServiceError.invalidAuthority
            }
            data.append(contentsOf: buffer[0..<count])
            remaining -= Int64(count)
        }
        var eofByte: UInt8 = 0
        let eofCount = withUnsafeMutablePointer(to: &eofByte) { pointer in
            var result: Int
            repeat {
                result = Darwin.read(opened.descriptor, pointer, 1)
            } while result < 0 && errno == EINTR
            return result
        }
        guard eofCount == 0,
              try streamingSourceSnapshot(opened.descriptor) == before,
              try streamingDirectoryIdentities(opened.ancestorDescriptors)
                == opened.ancestorIdentities,
              try streamingPathSnapshot(
                  relativePath,
                  rootIdentity: rootIdentity
              ) == before,
              try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                == rootIdentity,
              data.count == Int(before.byteCount),
              CanonicalJSONV1.sha256(data) == expectedSHA256 else {
            throw BackupExportServiceError.invalidAuthority
        }
        return data
    }

    func openStreamingSource(
        _ relativePath: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> OpenedStreamingSource {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let rootDescriptor = Darwin.open(
            generationRootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw BackupExportServiceError.invalidGeneration
        }
        var ancestorDescriptors = [rootDescriptor]
        do {
            var rootInformation = stat()
            guard Darwin.fstat(rootDescriptor, &rootInformation) == 0,
                  (rootInformation.st_mode & S_IFMT) == S_IFDIR,
                  rootInformation.st_dev == rootIdentity.device,
                  rootInformation.st_ino == rootIdentity.inode else {
                throw BackupExportServiceError.invalidGeneration
            }
            for component in components.dropLast() {
                let child = Darwin.openat(
                    ancestorDescriptors[ancestorDescriptors.count - 1],
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw BackupExportServiceError.invalidAuthority
                }
                var childInformation = stat()
                guard Darwin.fstat(child, &childInformation) == 0,
                      (childInformation.st_mode & S_IFMT) == S_IFDIR else {
                    _ = Darwin.close(child)
                    throw BackupExportServiceError.invalidAuthority
                }
                ancestorDescriptors.append(child)
            }
            guard let leaf = components.last else {
                throw BackupExportServiceError.invalidAuthority
            }
            let file = Darwin.openat(
                ancestorDescriptors[ancestorDescriptors.count - 1],
                leaf,
                O_RDONLY | O_NOFOLLOW
            )
            guard file >= 0 else {
                throw BackupExportServiceError.invalidAuthority
            }
            let identities: [StreamingDirectoryIdentity]
            do {
                identities = try streamingDirectoryIdentities(
                    ancestorDescriptors
                )
            } catch {
                _ = Darwin.close(file)
                throw error
            }
            return OpenedStreamingSource(
                descriptor: file,
                ancestorDescriptors: ancestorDescriptors,
                ancestorIdentities: identities
            )
        } catch {
            for descriptor in ancestorDescriptors.reversed() {
                _ = Darwin.close(descriptor)
            }
            throw error
        }
    }

    func streamingDirectoryIdentities(
        _ descriptors: [Int32]
    ) throws -> [StreamingDirectoryIdentity] {
        try descriptors.map { descriptor in
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  (information.st_mode & S_IFMT) == S_IFDIR else {
                throw BackupExportServiceError.invalidAuthority
            }
            return StreamingDirectoryIdentity(
                device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino)
            )
        }
    }

    func streamingSourceSnapshot(_ descriptor: Int32) throws -> StreamingSourceSnapshot {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1 else {
            throw BackupExportServiceError.invalidAuthority
        }
        return StreamingSourceSnapshot(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino),
            linkCount: UInt64(information.st_nlink),
            byteCount: Int64(information.st_size),
            modifiedSeconds: Int64(information.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(information.st_mtimespec.tv_nsec),
            changedSeconds: Int64(information.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(information.st_ctimespec.tv_nsec)
        )
    }

    func streamingPathSnapshot(
        _ relativePath: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> StreamingSourceSnapshot {
        let opened = try openStreamingSource(
            relativePath,
            rootIdentity: rootIdentity
        )
        defer {
            _ = Darwin.close(opened.descriptor)
            for descriptor in opened.ancestorDescriptors.reversed() {
                _ = Darwin.close(descriptor)
            }
        }
        guard try streamingDirectoryIdentities(opened.ancestorDescriptors)
                == opened.ancestorIdentities else {
            throw BackupExportServiceError.invalidAuthority
        }
        return try streamingSourceSnapshot(opened.descriptor)
    }

    func anchoredRead(
        _ relativePath: String,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> Data {
        guard validRelativePath(relativePath) else {
            throw BackupExportServiceError.invalidAuthority
        }
        do {
            return try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(relativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    func evidenceDerivativeMembers(
        _ records: V4BackupRecordsV1,
        rootIdentity: ReportPDFAnchoredFile.RootIdentity
    ) throws -> [(path: String, mimeType: String, data: Data)] {
        guard records.recordsSchemaVersion >= C05EvidenceMetadataBackupEnrollmentV1.recordsSchemaVersion else {
            return []
        }
        var contentKeys = Set<String>()
        for event in records.evidenceAssociationEvents {
            for contentID in [event.contentID, event.previousContentID].compactMap({ $0 }) {
                contentKeys.insert("\(event.workspaceID)|\(contentID)")
            }
        }
        var result: [(path: String, mimeType: String, data: Data)] = []
        for key in contentKeys.sorted() {
            let components = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard components.count == 2 else { throw BackupExportServiceError.invalidAuthority }
            let directory = "content/\(components[0])/\(components[1])"
            let markerPath = "\(directory)/derivative-publication.json"
            guard try Self.itemType(at: generationRootURL.appendingPathComponent(markerPath)) != nil else {
                continue // Incumbent original/temporal content has its existing archive owner.
            }
            let markerData = try anchoredRead(markerPath, rootIdentity: rootIdentity)
            let marker = try EvidenceCurationCanonicalCodecV1.decode(
                EvidenceDerivativePublicationMarkerV1.self,
                from: markerData
            )
            try marker.validate()
            guard marker.workspaceID.rawValue.uuidString.lowercased() == components[0],
                  marker.result.derivative.contentID == components[1],
                  marker.result.derivative.workspaceID == components[0],
                  let digest = marker.result.derivative.digests.digest(for: .sha256) else {
                throw BackupExportServiceError.invalidAuthority
            }
            let bytesPath = "\(directory)/original.bin"
            let bytes = try anchoredRead(bytesPath, rootIdentity: rootIdentity)
            guard Int64(bytes.count) == marker.result.derivative.byteLength,
                  CanonicalJSONV1.sha256(bytes) == digest.hexadecimalValue else {
                throw BackupExportServiceError.invalidAuthority
            }
            result.append((markerPath, "application/json", markerData))
            result.append((bytesPath, marker.result.derivative.mediaType, bytes))
        }
        return result.sorted { $0.path < $1.path }
    }

    private func fetchRows() throws -> Rows {
        do {
            return Rows(
                surveySessions:try modelContext.fetch(FetchDescriptor<SurveySessionRow>()),factCaptures:try modelContext.fetch(FetchDescriptor<FactCaptureRow>()),provisionalSubjects:try modelContext.fetch(FetchDescriptor<ProvisionalSubjectRow>()),subjectPromotionReceipts:try modelContext.fetch(FetchDescriptor<SubjectPromotionReceiptRow>()),surveyPublicationSnapshots:try modelContext.fetch(FetchDescriptor<SurveyPublicationSnapshotRow>()),
                surveyDefinitionIdentities:try modelContext.fetch(FetchDescriptor<SurveyDefinitionIdentityRow>()),
                surveyDefinitionReleases:try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>()),
                 accessibleDocumentAssessmentReceipts:try modelContext.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>()),
                 assetLocators: try modelContext.fetch(FetchDescriptor<AssetLocatorRow>()),
                 locatorBindingReceipts: try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>()),
                 scheduleDefinitionReleases: try modelContext.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>()),
                 occurrenceHistoryEvents: try modelContext.fetch(FetchDescriptor<OccurrenceHistoryEventRow>()),
                 exceptionCalendarReleases: try modelContext.fetch(FetchDescriptor<ExceptionCalendarReleaseRow>()),
                 scheduleOverrideEvents: try modelContext.fetch(FetchDescriptor<ScheduleOverrideEventRow>()),
                 planDocuments: try modelContext.fetch(FetchDescriptor<PlanDocumentRow>()),
                 planRevisions: try modelContext.fetch(FetchDescriptor<PlanRevisionRow>()),
                 planPlacements: try modelContext.fetch(FetchDescriptor<PlanPlacementRow>()),
                 rebaseReceipts: try modelContext.fetch(FetchDescriptor<RebaseReceiptRow>()),
                 poseEvents: try modelContext.fetch(FetchDescriptor<AssetPoseEventRow>()),
                 spatialAnchorObservations: try modelContext.fetch(FetchDescriptor<SpatialAnchorObservationRow>()),
                 evidenceContexts: try modelContext.fetch(FetchDescriptor<EvidenceContextRow>()),
                 pairedObservationLinks: try modelContext.fetch(FetchDescriptor<PairedObservationLinkRow>()),
                 lightingSystems: try modelContext.fetch(FetchDescriptor<LightingSystemRow>()),
                 lightingObservations: try modelContext.fetch(FetchDescriptor<LightingObservationRow>()),
                 lightingIssues: try modelContext.fetch(FetchDescriptor<LightingIssueRow>()),
                 lightingPlans: try modelContext.fetch(FetchDescriptor<MeasurementPlanRow>()),
                 lightingClaims: try modelContext.fetch(FetchDescriptor<LightingClaimStateRow>()),
                 lightingDayInventoryWorkflows: try modelContext.fetch(FetchDescriptor<LightingDayInventoryWorkflowRowV1>()),
                 lightingNightWorkflows: try modelContext.fetch(FetchDescriptor<LightingNightWorkflowRowV1>()),
                 assistanceAcceptanceReceipts: try modelContext.fetch(FetchDescriptor<AssistanceAcceptanceReceiptRow>()),
                 temporalEvidenceClips: try modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>()),
                 timecodedEvidenceAnchors: try modelContext.fetch(FetchDescriptor<TimecodedEvidenceAnchorRow>()),
                  acceptedLabelGenerationSnapshots: try modelContext.fetch(FetchDescriptor<AcceptedLabelGenerationSnapshotRow>()),
                  serviceContactPoints: try modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()),
                  systemHandoffIntents: try modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()),
                  activitySessionEnvelopes: try modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()),
                  activityStateTransitions: try modelContext.fetch(FetchDescriptor<ActivityStateTransitionRow>()),
                  installationTaskResults: try modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>()),
                  installationAsBuiltSnapshots: try modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()),
                  punchReviewBasisSnapshots: try modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()),
                   serviceRequestRecords: try modelContext.fetch(FetchDescriptor<ServiceRequestRecordRow>()),
                   serviceRequestDispositionEvents: try modelContext.fetch(FetchDescriptor<ServiceRequestDispositionEventRow>()),
                   serviceRequestWorkLinkEvents: try modelContext.fetch(FetchDescriptor<ServiceRequestWorkLinkEventRow>()),
                  serviceReliabilityIncidents: try modelContext.fetch(FetchDescriptor<AssetServiceIncidentRow>()),
                  serviceImpactSegments: try modelContext.fetch(FetchDescriptor<ServiceImpactSegmentRow>()),
                  serviceCauseAssertions: try modelContext.fetch(FetchDescriptor<ServiceCauseAssertionRow>()),
                  serviceRemedyAssertions: try modelContext.fetch(FetchDescriptor<ServiceRemedyAssertionRow>()),
                  serviceRepairIntervals: try modelContext.fetch(FetchDescriptor<ServiceRepairIntervalRow>()),
                  serviceRestorationAssertions: try modelContext.fetch(FetchDescriptor<ServiceRestorationAssertionRow>()),
                  qualifiedServiceExposures: try modelContext.fetch(FetchDescriptor<QualifiedServiceExposureRow>()),
                 fieldReferenceReleases:try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>()),
                fieldReferenceBindings:try modelContext.fetch(FetchDescriptor<FieldReferenceBindingRow>()),
                recoverabilityVerificationReceipts:try modelContext.fetch(FetchDescriptor<RecoverabilityVerificationReceiptRow>()),
                clientCapabilityProfiles:try modelContext.fetch(FetchDescriptor<ClientCapabilityProfileRow>()),packageLifecyclePolicies:try modelContext.fetch(FetchDescriptor<PackageLifecyclePolicyRow>()),packageLifecycleDispositions:try modelContext.fetch(FetchDescriptor<PackageLifecycleDispositionRow>()),clientCapabilityAdmissionDecisions:try modelContext.fetch(FetchDescriptor<ClientCapabilityAdmissionDecisionRow>()),
                privacyTransformPolicies: try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>()),
                privacyRegions: try modelContext.fetch(FetchDescriptor<PrivacyRegionRow>()),
                privacyTransformManifests: try modelContext.fetch(FetchDescriptor<PrivacyTransformManifestRow>()),
                privacyReviewReceipts: try modelContext.fetch(FetchDescriptor<PrivacyReviewReceiptRow>()),
                instrumentReferences: try modelContext.fetch(FetchDescriptor<InstrumentReferenceRow>()),
                calibrationStatusSnapshots: try modelContext.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()),
                measurementCaptures: try modelContext.fetch(FetchDescriptor<MeasurementCaptureRow>()),
                measurementSeries: try modelContext.fetch(FetchDescriptor<MeasurementSeriesRow>()),
                measurementQualityAssessments: try modelContext.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>()),
                promotedPackageReleases: try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()),
                packageSandboxRuns: try modelContext.fetch(FetchDescriptor<PackageSandboxRunRow>()),
                packagePromotionReceipts: try modelContext.fetch(FetchDescriptor<PackagePromotionReceiptRow>()),
                activePackageRegistryPointers: try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()),
                fieldDraftCheckpoints: try modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>()),
                attachmentStagingItems: try modelContext.fetch(FetchDescriptor<AttachmentStagingItemRow>()),
                draftCommitSagas: try modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>()),
                draftContentReservations: try modelContext.fetch(FetchDescriptor<DraftContentReservationRow>()),
                draftCommitReceipts: try modelContext.fetch(FetchDescriptor<DraftCommitReceiptRow>()),
                draftDiscardReceipts: try modelContext.fetch(FetchDescriptor<DraftDiscardReceiptRow>()),
                workPacketManifests:try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>()),workItemClaims:try modelContext.fetch(FetchDescriptor<WorkItemClaimRow>()),workLeases:try modelContext.fetch(FetchDescriptor<WorkLeaseRow>()),workReleases:try modelContext.fetch(FetchDescriptor<WorkReleaseRow>()),workHandoffs:try modelContext.fetch(FetchDescriptor<WorkHandoffRow>()),
                inspectionReviewTransitions: try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()),
                reviewDispositions: try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>()),
                changeRequests: try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()),
                correctiveActionPolicies: try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>()),
                correctiveActionEvents: try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>()),
                evidenceVisibilities: try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>()),
                claimEvidenceLinks: try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>()),
                assuranceManifests: try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>()),
                attestations: try modelContext.fetch(FetchDescriptor<AttestationRow>()),
                functionalRelationshipDescriptors: try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()),
                functionalRelationshipEvents: try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>()),
                authoritySourceReleases: try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>()),
                requirementBasisBindings: try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>()),
                applicabilityContextSnapshots: try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()),
                assessmentScopeSnapshots: try modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>()),
                severityScaleReleases: try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>()),
                findingClassificationBindings: try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>()),
                measurementProtocolReleases: try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()),
                derivedFactEvaluatorDescriptors: try modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()),
                derivedFactProvenances: try modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>()),
                assetCompositionEdges: try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>()),
                assetCompositionEvents: try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>()),
                assetPlacementEvents: try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>()),
                assetKindBindingEvents: try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>()),
                assetWorkflowCapabilityBindingEvents: try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>()),
                assetProductIdentities: try modelContext.fetch(FetchDescriptor<AssetProductIdentityRow>()),
                assetLifecycleEvents: try modelContext.fetch(FetchDescriptor<AssetLifecycleEventRow>()),
                assetSuccessorLinks: try modelContext.fetch(FetchDescriptor<AssetSuccessorLinkRow>()),
                workSubjectScopeSnapshots: try modelContext.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>()),
                sites: try modelContext.fetch(FetchDescriptor<Site>()),
                assets: try modelContext.fetch(FetchDescriptor<Asset>()),
                records: try modelContext.fetch(FetchDescriptor<WorkflowRecord>()),
                observationAndTime: try ObservationAndTimeRowStoreV1.validatedIndex(
                    in: modelContext
                ),
                evidence: try modelContext.fetch(FetchDescriptor<EvidenceFile>()),
                issues: try modelContext.fetch(FetchDescriptor<Issue>()),
                locationHierarchyEvents: try modelContext.fetch(FetchDescriptor<LocationHierarchyEventRow>()),
                locationMigrationReceipts: try modelContext.fetch(FetchDescriptor<LocationMigrationReceiptRow>()),
                locationNodes: try modelContext.fetch(FetchDescriptor<LocationNodeRow>()),
                packets: try modelContext.fetch(FetchDescriptor<Packet>()),
                serviceParties: try modelContext.fetch(FetchDescriptor<ServicePartyRow>()),
                sitePartyRoleEvents: try modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>()),
                actorSnapshots: try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>()),
                qualificationSnapshots: try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>()),
                signoffSnapshots: try modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>()),
                reports: try modelContext.fetch(FetchDescriptor<Report>()),
                requirementAssurance: try modelContext.fetch(
                    FetchDescriptor<RequirementAssuranceRow>()
                ),
                savedSmartViews: try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>())
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func validateGraph(
        _ rows: Rows,
        deletionLedger: DeletionLedgerV2
    ) throws {
        let sourceIdentity = try currentStreamingWorkspaceIdentity()
        do {
            guard C34SceneNavigationKernelBackupRestoreBoundaryV1.validate() else {
                throw BackupExportServiceError.invalidAuthority
            }
            try KernelBackupRestoreRegistryV4.validate()
            let schema = try KernelPersistenceV4Schema.descriptor()
            guard schema.runtimePosture == .dormantStatic,
                  !schema.activationEnabled else {
                throw BackupExportServiceError.invalidAuthority
            }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        guard unique(rows.sites.map(\.id)),
              unique(rows.assets.map(\.id)),
              unique(rows.records.map(\.id)),
              unique(rows.evidence.map(\.id)),
              unique(rows.issues.map(\.id)),
              unique(rows.packets.map(\.id)),
              unique(rows.packets.map(\.stableRootID)),
              unique(rows.reports.map(\.id)),
              unique(rows.requirementAssurance.map(\.workflowRecordID)),
              Set(rows.requirementAssurance.map(\.workflowRecordID))
                == Set(rows.records.map(\.id)),
              unique(rows.savedSmartViews.map(\.id)),
              unique(rows.serviceParties.map(\.partyID)),
              unique(rows.sitePartyRoleEvents.map(\.eventID)),
              unique(rows.actorSnapshots.map(\.snapshotID)),
              unique(rows.qualificationSnapshots.map(\.snapshotID)),
              unique(rows.signoffSnapshots.map(\.snapshotID)),
              unique(rows.assetKindBindingEvents.map(\.eventID)),
              unique(rows.assetWorkflowCapabilityBindingEvents.map(\.eventID)),
              unique(rows.assetProductIdentities.map(\.identityID)),
              unique(rows.assetLifecycleEvents.map(\.eventID)),
              unique(rows.assetSuccessorLinks.map(\.linkID)),
              unique(rows.workSubjectScopeSnapshots.map(\.snapshotID)),
              rows.sites.allSatisfy({ $0.schemaVersion == 1 }),
              rows.assets.allSatisfy({ $0.schemaVersion == 1 }),
              rows.records.allSatisfy({ $0.schemaVersion == 1 }),
              rows.evidence.allSatisfy({ $0.schemaVersion == 1 }),
              rows.issues.allSatisfy({ $0.schemaVersion == 1 }),
              rows.packets.allSatisfy({ $0.schemaVersion == 1 }),
              rows.reports.allSatisfy({ $0.schemaVersion == 1 }),
              rows.requirementAssurance.allSatisfy({
                  (try? $0.snapshot()) != nil
                      && $0.workspaceID == sourceIdentity.workspaceID.rawValue
              }),
              rows.savedSmartViews.allSatisfy({
                  guard let descriptor = try? $0.descriptor() else { return false }
                  return descriptor.workspaceID == sourceIdentity.workspaceID.rawValue
                      && $0.id == descriptor.id
                      && $0.workspaceStableKey == SavedSmartViewRowV1.key(
                          workspaceID: descriptor.workspaceID,
                          stableID: descriptor.stableID
                      )
              }),
              rows.serviceParties.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.sitePartyRoleEvents.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.actorSnapshots.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.qualificationSnapshots.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.signoffSnapshots.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.assetKindBindingEvents.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.assetWorkflowCapabilityBindingEvents.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.assetProductIdentities.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.assetLifecycleEvents.allSatisfy({ (try? $0.value())?.record.workspaceID == sourceIdentity.workspaceID }),
              rows.assetSuccessorLinks.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }),
              rows.workSubjectScopeSnapshots.allSatisfy({ (try? $0.value())?.workspaceID == sourceIdentity.workspaceID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        do {
            let poseEvents = try rows.poseEvents.map { try $0.value() }
            let anchorObservations = try rows.spatialAnchorObservations.map { try $0.value() }
            guard poseEvents.allSatisfy({ $0.workspaceID == sourceIdentity.workspaceID }),
                  anchorObservations.allSatisfy({ $0.workspaceID == sourceIdentity.workspaceID }),
                  Set(poseEvents.map(\.eventID)).count == poseEvents.count,
                  Set(anchorObservations.map(\.observationID)).count == anchorObservations.count else {
                throw BackupExportServiceError.invalidAuthority
            }
            let poseRecords = try (poseEvents.map {
                V29BackupPlacementPoseRecordV1(
                    kind: .poseEvent,
                    id: $0.eventID,
                    workspaceID: $0.workspaceID.rawValue,
                    revision: $0.revision,
                    canonicalData: try PlacementPoseCanonicalCodecV1.encode($0)
                )
            } + anchorObservations.map {
                V29BackupPlacementPoseRecordV1(
                    kind: .spatialAnchorObservation,
                    id: $0.observationID,
                    workspaceID: $0.workspaceID.rawValue,
                    revision: $0.revision,
                    canonicalData: try PlacementPoseCanonicalCodecV1.encode($0)
                )
            }).sorted {
                "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                    < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
            }
            _ = try PlacementPoseBackupRecordSetV1.decode(poseRecords)
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        _ = try assetLocatorRecords(rows)
        try validateAssetSemanticRows(rows, deletionLedger: deletionLedger)
        try validateFieldDraftRows(rows, workspaceID: sourceIdentity.workspaceID)
        let packageClosure = try PackageEvolutionLifecycleClosureV1(
            promotedReleases: try rows.promotedPackageReleases.map { try $0.value() },
            sandboxRuns: try rows.packageSandboxRuns.map { try $0.value() },
            promotionReceipts: try rows.packagePromotionReceipts.map { try $0.value() },
            activePointers: try rows.activePackageRegistryPointers.map { try $0.value() }
        )
        try PackageEvolutionLifecycleAdapterV1.validateBackupRestore(packageClosure)
        let siteIDs = Set(rows.sites.map(\.id))
        let assetIDs = Set(rows.assets.map(\.id))
        let recordIDs = Set(rows.records.map(\.id))
        let issueIDs = Set(rows.issues.map(\.id))
        let packetIDs = Set(rows.packets.map(\.id))
        let recordsByID = Dictionary(uniqueKeysWithValues: rows.records.map { ($0.id, $0) })
        let issuesByID = Dictionary(uniqueKeysWithValues: rows.issues.map { ($0.id, $0) })
        let packetsByID = Dictionary(uniqueKeysWithValues: rows.packets.map { ($0.id, $0) })
        let reportsByID = Dictionary(uniqueKeysWithValues: rows.reports.map { ($0.id, $0) })
        let profilesByAsset: [UUID: WorkspacePackageLifecycleProfileV1]
        do {
            profilesByAsset = try Dictionary(uniqueKeysWithValues: rows.assets.map { asset in
                let release = try PackageReleaseIdentityV1(
                    packageID: asset.packID,
                    schemaVersion: asset.packSchemaVersion,
                    contentVersion: asset.packContentVersion
                )
                return (asset.id, try lifecycleProfile(release))
            })
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        let validRecordRelationships = rows.records.allSatisfy { record in
            guard let revisionKind = WorkflowRevisionKind(rawValue: record.revisionKind),
                  let state = WorkflowState(rawValue: record.state),
                  let profile = profilesByAsset[record.assetID],
                  let stage = try? profile.stage(record.stage),
                  (state == .draft && record.outcomeKey == nil)
                    || (state == .completed
                        && stage.outcomeKeys.contains(record.outcomeKey ?? "")),
                  let revisionRoot = recordsByID[record.recordRevisionRootID],
                  revisionRoot.assetID == record.assetID,
                  revisionRoot.revisionKind == WorkflowRevisionKind.original.rawValue,
                  revisionRoot.recordRevisionRootID == revisionRoot.id,
                  revisionRoot.revisesRecordID == nil,
                  revisionRoot.evidenceSourceRecordID == nil,
                  record.parentRecordID.map({
                      recordsByID[$0]?.assetID == record.assetID
                  }) ?? true,
                  record.issueID.map({ issuesByID[$0]?.assetID == record.assetID }) ?? true,
                  record.packetID.map({ packetsByID[$0] != nil }) ?? true else {
                return false
            }
            switch revisionKind {
            case .original:
                return record.recordRevisionRootID == record.id
                    && record.revisesRecordID == nil
                    && record.evidenceSourceRecordID == nil
            case .clericalCorrection:
                guard let revisedID = record.revisesRecordID,
                      let sourceID = record.evidenceSourceRecordID,
                      let revised = recordsByID[revisedID],
                      let source = recordsByID[sourceID] else {
                    return false
                }
                return record.recordRevisionRootID != record.id
                    && revised.assetID == record.assetID
                    && revised.recordRevisionRootID == record.recordRevisionRootID
                    && source.id == record.recordRevisionRootID
                    && source.assetID == record.assetID
                    && record.parentRecordID == revised.parentRecordID
                    && record.issueID == revised.issueID
                    && record.packetID == revised.packetID
            }
        }
        let validPacketOwnership = rows.packets.allSatisfy { packet in
            var owners = Set<UUID>()
            if let currentID = packet.currentRecordID,
               let current = recordsByID[currentID] {
                owners.insert(current.assetID)
            }
            for record in rows.records where record.packetID == packet.id {
                owners.insert(record.assetID)
            }
            for report in rows.reports where report.packetID == packet.id {
                guard let source = recordsByID[report.sourceRecordID] else { return false }
                owners.insert(source.assetID)
            }
            return packet.currentRecordID == nil ? owners.isEmpty : owners.count == 1
        }
        guard rows.assets.allSatisfy({ asset in
                  siteIDs.contains(asset.siteID)
                    && profilesByAsset[asset.id] != nil
              }),
              rows.records.allSatisfy({ record in
                  let profile = profilesByAsset[record.assetID]
                  return assetIDs.contains(record.assetID)
                    && record.packetID.map(packetIDs.contains) ?? true
                    && record.issueID.map(issueIDs.contains) ?? true
                    && record.parentRecordID.map(recordIDs.contains) ?? true
                    && record.revisesRecordID.map(recordIDs.contains) ?? true
                    && record.evidenceSourceRecordID.map(recordIDs.contains) ?? true
                    && recordIDs.contains(record.recordRevisionRootID)
                    && WorkflowRevisionKind(rawValue: record.revisionKind) != nil
                    && WorkflowStage(rawValue: record.stage) != nil
                    && WorkflowState(rawValue: record.state) != nil
                    && record.draftStepKey.map({ WorkflowDraftStep(rawValue: $0) != nil }) ?? true
                    && record.packID == profile?.release.packageID
                    && record.packSchemaVersion == profile?.release.schemaVersion
                    && record.packContentVersion == profile?.release.contentVersion
                    && record.pdfTemplateID == profile?.pdfTemplate.id
                    && record.pdfTemplateVersion == profile?.pdfTemplate.version
              }),
              validRecordRelationships,
              rows.evidence.allSatisfy({ evidence in
                  guard let owner = recordsByID[evidence.recordID],
                        let profile = profilesByAsset[owner.assetID] else {
                      return false
                  }
                  return profile.evidencePurposes.contains {
                      $0.key == evidence.purposeKey
                  }
              }),
              rows.issues.allSatisfy({ issue in
                  let profile = profilesByAsset[issue.assetID]
                  return assetIDs.contains(issue.assetID)
                    && recordsByID[issue.openedByRecordID]?.assetID == issue.assetID
                    && profile?.package.issueLabels.contains(where: {
                        $0.key == issue.labelKey
                            && $0.display == issue.labelDisplaySnapshot
                    }) == true
                    && issue.resolvedByRecordID.map({
                        recordsByID[$0]?.assetID == issue.assetID
                    }) ?? true
                    && IssueStatus(rawValue: issue.status) != nil
              }),
              validPacketOwnership,
              rows.packets.allSatisfy({ packet in
                  if let current = packet.currentRecordID {
                      return packet.contentDeletedAt == nil
                        && rows.records.filter({ $0.id == current }).count == 1
                        && rows.records.first(where: { $0.id == current })?.packetID
                            == packet.id
                  }
                  return packet.evaluationCounted
                    && packet.contentDeletedAt != nil
                    && !rows.records.contains(where: { $0.packetID == packet.id })
                    && !rows.reports.contains(where: { $0.packetID == packet.id })
              }),
              rows.reports.allSatisfy({ report in
                  packetIDs.contains(report.packetID)
                    && recordIDs.contains(report.sourceRecordID)
                    && report.replacesReportID.map({ replacedID in
                        guard let replaced = reportsByID[replacedID] else { return false }
                        return replaced.packetID == report.packetID
                            && replaced.createdAt <= report.createdAt
                    }) ?? true
                    && ReportPDFState(rawValue: report.pdfState) != nil
              }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        try requireAcyclic(rows.records, id: \.id, next: \.parentRecordID)
        try requireAcyclic(rows.records, id: \.id, next: \.revisesRecordID)
        try requireAcyclic(rows.reports, id: \.id, next: \.replacesReportID)
        guard unique(rows.records.compactMap(\.revisesRecordID)),
              unique(rows.reports.compactMap(\.replacesReportID)) else {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func validateFieldDraftRows(_ rows: Rows, workspaceID: WorkspaceID) throws {
        let checkpoints = try rows.fieldDraftCheckpoints.map { try $0.value() }
        let stages = try rows.attachmentStagingItems.map { try $0.value() }
        let sagas = try rows.draftCommitSagas.map { try $0.value() }
        let reservations = try rows.draftContentReservations.map { try $0.value() }
        let commitReceipts = try rows.draftCommitReceipts.map { try $0.value() }
        let discardReceipts = try rows.draftDiscardReceipts.map { try $0.value() }
        let checkpointByID = Dictionary(uniqueKeysWithValues: checkpoints.map { ($0.draftID, $0) })
        let stageByID = Dictionary(uniqueKeysWithValues: stages.map { ($0.stageID, $0) })
        let sagaByID = Dictionary(uniqueKeysWithValues: sagas.map { ($0.sagaID, $0) })
        let reservationByID = Dictionary(uniqueKeysWithValues: reservations.map { ($0.reservationID, $0) })
        guard (checkpoints.map(\.workspaceID) + stages.map(\.workspaceID) + sagas.map(\.workspaceID)
                + reservations.map(\.workspaceID) + commitReceipts.map(\.workspaceID)
                + discardReceipts.map(\.workspaceID)).allSatisfy({ $0 == workspaceID }),
              checkpoints.allSatisfy({ checkpoint in checkpoint.stageIDs.allSatisfy { stageByID[$0]?.draftID == checkpoint.draftID } }),
              stages.allSatisfy({ checkpointByID[$0.draftID]?.stageIDs.contains($0.stageID) == true }),
              reservations.allSatisfy({ reservation in stageByID[reservation.stageID]?.draftID == reservation.draftID && checkpointByID[reservation.draftID] != nil }),
              sagas.allSatisfy({ checkpointByID[$0.draftID] != nil && ($0.predecessorSagaID == nil || sagaByID[$0.predecessorSagaID!]?.draftID == $0.draftID) }),
              commitReceipts.allSatisfy({ sagaByID[$0.sagaID]?.draftID == $0.draftID }),
              discardReceipts.allSatisfy({ receipt in receipt.disposedStageIDs.allSatisfy { stageByID[$0]?.draftID == receipt.draftID } && receipt.quarantinedReservationIDs.allSatisfy { reservationByID[$0]?.draftID == receipt.draftID } })
        else { throw BackupExportServiceError.invalidAuthority }
    }

    private func lifecycleProfile(
        for report: Report,
        rows: Rows
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        guard let record = rows.records.first(where: { $0.id == report.sourceRecordID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        do {
            return try lifecycleProfile(
                PackageReleaseIdentityV1(
                    packageID: record.packID,
                    schemaVersion: record.packSchemaVersion,
                    contentVersion: record.packContentVersion
                )
            )
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func validateLifecycleScope(
        _ rows: Rows,
        operation: WorkspacePackageLifecycleOperationV1
    ) throws {
        try IntegrationProjectionBackupExportExclusionV1.validate()
        guard case let .live(lifecycleDependencies) = lifecycleRoute else {
            guard case let .expiringCompatibility(posture) = lifecycleRoute,
                  posture == .frozenLegacyCallersOnly else {
                throw BackupExportServiceError.invalidAuthority
            }
            return
        }
        guard lifecycleDependencies.generationRootURL.standardizedFileURL
                == generationRootURL,
              lifecycleDependencies.generationID == (try currentStreamingGenerationID()),
              lifecycleDependencies.workspaceID
                == (try currentStreamingWorkspaceIdentity()).workspaceID else {
            throw BackupExportServiceError.invalidAuthority
        }
        let pairs: [(WorkspaceEntityKindV1, UUID)] =
            rows.sites.map { (.site, $0.id) }
            + rows.assets.map { (.asset, $0.id) }
            + rows.records.map { (.workflowRecord, $0.id) }
            + rows.evidence.map { (.evidenceFile, $0.id) }
            + rows.issues.map { (.issue, $0.id) }
            + rows.packets.map { (.packet, $0.id) }
            + rows.reports.map { (.report, $0.id) }
            + rows.savedSmartViews.map { (.savedSmartView, $0.id) }
        let identities: [WorkspaceEntityIdentityV1]
        do {
            identities = try pairs.map { try .init(kind: $0.0, id: $0.1) }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        let initial = try lifecycleDependencies.writer.currentRevision()
        guard initial.workspaceID == lifecycleDependencies.workspaceID,
              initial.generationID == lifecycleDependencies.generationID else {
            throw BackupExportServiceError.invalidAuthority
        }
        for start in stride(from: 0, to: identities.count, by: 256) {
            let slice = Array(identities[start..<min(start + 256, identities.count)])
            let request: WorkspacePackageLifecycleQueryRequestV1
            do {
                request = try .init(
                    workspaceID: lifecycleDependencies.workspaceID,
                    generationID: lifecycleDependencies.generationID,
                    operation: operation,
                    identities: slice
                )
                let result = try lifecycleDependencies.writer.query(request)
                guard result.existingIdentities == request.identities,
                      result.revision.revision == initial.revision else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let expectedBindings = rows.assets.filter { asset in
                    slice.contains(where: { $0.kind == .asset && $0.id == asset.id })
                }.map {
                    WorkspacePackageBindingV1(
                        assetID: $0.id,
                        packageID: $0.packID,
                        packageSchemaVersion: $0.packSchemaVersion,
                        packageContentVersion: $0.packContentVersion
                    )
                }.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
                guard result.packageBindings == expectedBindings else {
                    throw BackupExportServiceError.invalidAuthority
                }
            } catch {
                throw BackupExportServiceError.invalidAuthority
            }
        }
        guard try lifecycleDependencies.writer.currentRevision() == initial else {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func lifecycleProfile(
        _ release: PackageReleaseIdentityV1
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        do {
            switch lifecycleRoute {
            case let .live(dependencies):
                return try dependencies.profileRegistry.resolve(release)
            case let .expiringCompatibility(posture):
                guard posture == .frozenLegacyCallersOnly else {
                    throw BackupExportServiceError.invalidAuthority
                }
                let profile = try WorkspacePackageLifecycleCompatibilityV1
                    .legacyV3Profile(package: .illuminatedSignV1)
                guard profile.release == release else {
                    throw BackupExportServiceError.invalidAuthority
                }
                return profile
            }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func manifestPacks(_ rows: Rows) throws -> [V4BackupPackV1] {
        do {
            let releases = try rows.assets.map {
                try PackageReleaseIdentityV1(
                    packageID: $0.packID,
                    schemaVersion: $0.packSchemaVersion,
                    contentVersion: $0.packContentVersion
                )
            } + rows.records.map {
                try PackageReleaseIdentityV1(
                    packageID: $0.packID,
                    schemaVersion: $0.packSchemaVersion,
                    contentVersion: $0.packContentVersion
                )
            } + rows.assetKindBindingEvents.map {
                try $0.value().catalogRelease.packageRelease
            } + rows.assetWorkflowCapabilityBindingEvents.map {
                try $0.value().workflowPackageRelease
            } + rows.workSubjectScopeSnapshots.flatMap {
                let value = try $0.value()
                let bindingReleases = value.semanticBindings.flatMap {
                    [$0.catalogRelease.packageRelease] + $0.workflowPackageReleases
                }
                let relationshipReleases = value.subjects.compactMap(
                    \.functionalRelationship
                ).flatMap {
                    [$0.packageRelease, $0.semanticCatalogRelease.packageRelease]
                }
                return bindingReleases + relationshipReleases
            }
            return Set(releases).sorted().map {
                V4BackupPackV1(
                    contentVersion: $0.contentVersion,
                    packID: $0.packageID,
                    schemaVersion: $0.schemaVersion
                )
            }
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func makeRecords(
        _ rows: Rows,
        deletionLedger: DeletionLedgerV2? = nil,
        mutationHistory: MutationHistorySnapshotV1? = nil
    ) throws -> V4BackupRecordsV1 {
        // Journal snapshots retain numeric replica sequence order. Archive records
        // use the incumbent lexical receipt identity order without rewriting bytes.
        let archiveMutationHistory = try mutationHistory.map { history in
            guard history.schemaVersion == MutationHistorySnapshotV1.schemaVersion else {
                throw BackupExportServiceError.invalidAuthority
            }
            return try BackupCanonicalEncoderV1.archiveOrderedMutationHistory(history)
        }
        let sourceIdentity = try currentStreamingWorkspaceIdentity()
        func includedLocationRecords(
            _ build: () throws -> [V5BackupLocationRecordV1]
        ) rethrows -> [V5BackupLocationRecordV1] {
            guard mutationHistory != nil else { return [] }
            return try build()
        }
        let assetCompositionEdges = try includedLocationRecords { try rows.assetCompositionEdges.map {
            _ = try $0.value()
            return .init(id: $0.id, canonicalData: $0.canonicalData)
        }.sorted { $0.id.uuidString < $1.id.uuidString } }
        let assetCompositionEvents = try includedLocationRecords { try rows.assetCompositionEvents.map {
            _ = try $0.value()
            return .init(id: $0.id, canonicalData: $0.canonicalData)
        }.sorted { $0.id.uuidString < $1.id.uuidString } }
        let assetPlacementEvents = try includedLocationRecords { try rows.assetPlacementEvents.map {
            _ = try $0.value()
            return .init(id: $0.id, canonicalData: $0.canonicalData)
        }.sorted { $0.id.uuidString < $1.id.uuidString } }
        let locationMigrationReceipts = try includedLocationRecords { try rows.locationMigrationReceipts.map {
            _ = try $0.value()
            return .init(id: $0.candidateGenerationID, canonicalData: $0.canonicalData)
        }.sorted { $0.id.uuidString < $1.id.uuidString } }
        let locationHierarchyEvents = try includedLocationRecords { try rows.locationHierarchyEvents.map {
            _ = try $0.values()
            return .init(
                id: $0.operationID,
                canonicalData: $0.planData,
                secondaryCanonicalData: $0.receiptData
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString } }
        let locationNodes = try includedLocationRecords { try rows.locationNodes.map {
            _ = try $0.value()
            return .init(id: $0.id, canonicalData: $0.canonicalData)
        }.sorted { $0.id.uuidString < $1.id.uuidString } }
        let assetSemantics = mutationHistory == nil ? [] : try assetSemanticRecords(rows)
        let authorityCriterion = mutationHistory == nil ? [] : try authorityCriterionRecords(rows)
        let functionalRelationships = mutationHistory == nil ? [] : try functionalRelationshipRecords(rows)
        let evidenceAssurance = mutationHistory == nil ? [] : try evidenceAssuranceRecords(rows)
        let inspectionReview = mutationHistory == nil ? [] : try inspectionReviewRecords(rows)
        let workPackets = mutationHistory == nil ? [] : try workPacketRecords(rows)
        let fieldDrafts = mutationHistory == nil ? [] : try fieldDraftRecords(rows)
        let packageEvolution = mutationHistory == nil ? [] : try packageEvolutionRecords(rows)
        let measurementIntegrity = mutationHistory == nil ? [] : try measurementIntegrityRecords(rows)
        let privacyTransforms = mutationHistory == nil ? [] : try privacyTransformRecords(rows)
        let clientCapabilities = mutationHistory == nil ? [] : try clientCapabilityRecords(rows)
        let recoverabilityReceipts = mutationHistory == nil ? [] : try recoverabilityReceiptRecords(rows)
        let fieldReferences = mutationHistory == nil ? [] : try fieldReferenceRecords(rows)
        let accessibleDocumentAssessments = mutationHistory == nil ? [] : try accessibleDocumentAssessmentRecords(rows)
        let surveyDefinitions=try mutationHistory.map{try surveyDefinitionRecords(rows,history:$0)} ?? []
        let guidedSurveys=try mutationHistory.map{_ in try guidedSurveyRecords(rows)} ?? []
        let assetLocators = mutationHistory == nil ? [] : try assetLocatorRecords(rows)
        let schedules = mutationHistory == nil ? [] : try scheduleRecords(rows)
        let plans = mutationHistory == nil ? [] : try planRecords(rows)
        let placementPoses = try placementPoseRecords(rows)
        let lighting = mutationHistory == nil ? [] : try lightingRecords(rows)
        let assistanceAcceptanceReceipts = mutationHistory == nil ? [] : try rows.assistanceAcceptanceReceipts
            .map { try V32BackupAssistanceAcceptanceRecordV1($0.value()) }
            .sorted { $0.receiptID.uuidString.lowercased() < $1.receiptID.uuidString.lowercased() }
        let temporalEvidence = mutationHistory == nil ? [] : try (
            rows.temporalEvidenceClips.map { try V33BackupTemporalEvidenceRecordV1($0.value()) }
            + rows.timecodedEvidenceAnchors.map { try V33BackupTemporalEvidenceRecordV1($0.value()) }
        ).sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
        let acceptedLabelGenerationSnapshots = mutationHistory == nil ? [] : try rows.acceptedLabelGenerationSnapshots
            .map { try V34BackupAcceptedLabelSnapshotRecordV1($0.value()) }
            .sorted { ($0.workspaceID.uuidString, $0.snapshotID.uuidString) < ($1.workspaceID.uuidString, $1.snapshotID.uuidString) }
        let operationalContacts = mutationHistory == nil ? [] : try (
            rows.serviceContactPoints.map { try V35BackupOperationalContactRecordV1($0.value()) }
            + rows.systemHandoffIntents.map { try V35BackupOperationalContactRecordV1($0.value()) }
        ).sorted { ($0.kind.rawValue, $0.workspaceID.uuidString, $0.id.uuidString) < ($1.kind.rawValue, $1.workspaceID.uuidString, $1.id.uuidString) }
        let activityContracts = mutationHistory == nil ? [] : try (
            rows.activitySessionEnvelopes.map { try V36BackupActivityContractRecordV2($0.value()) }
            + rows.activityStateTransitions.map { try V36BackupActivityContractRecordV2($0.value()) }
            + rows.installationTaskResults.map { try V36BackupActivityContractRecordV2($0.value()) }
            + rows.installationAsBuiltSnapshots.map { try V36BackupActivityContractRecordV2($0.value()) }
            + rows.punchReviewBasisSnapshots.map { try V36BackupActivityContractRecordV2($0.value()) }
        ).sorted { ($0.kind.rawValue, $0.workspaceID.uuidString, $0.id.uuidString)
            < ($1.kind.rawValue, $1.workspaceID.uuidString, $1.id.uuidString) }
        let workResources = mutationHistory == nil ? [] : try WorkResourceRowQueryV1(
            modelContext: modelContext
        ).entries(workspaceID: sourceIdentity.workspaceID)
            .map(V37BackupWorkResourceRecordV1.init)
            .sorted { ($0.workspaceID.uuidString, $0.entryID.uuidString)
                < ($1.workspaceID.uuidString, $1.entryID.uuidString) }
        let serviceRequests = mutationHistory == nil ? [] : try rows.serviceRequestRecords
            .map { try V38BackupServiceRequestRecordV1($0.value()) }
            .sorted { ($0.workspaceID.uuidString, $0.recordID.uuidString, $0.revision)
                < ($1.workspaceID.uuidString, $1.recordID.uuidString, $1.revision) }
        let serviceRequestDispositionEvents = mutationHistory == nil ? [] : try rows.serviceRequestDispositionEvents
            .map { try V38BackupServiceRequestDispositionEventV1($0.value()) }
            .sorted { ($0.workspaceID.uuidString, $0.eventID.uuidString)
                < ($1.workspaceID.uuidString, $1.eventID.uuidString) }
        let serviceRequestWorkLinkEvents = mutationHistory == nil ? [] : try rows.serviceRequestWorkLinkEvents
            .map { try V38BackupServiceRequestWorkLinkEventV1($0.value()) }
            .sorted { ($0.workspaceID.uuidString, $0.eventID.uuidString)
                < ($1.workspaceID.uuidString, $1.eventID.uuidString) }
        let reliabilityOrder: (V39BackupServiceReliabilityRecordV1, V39BackupServiceReliabilityRecordV1) -> Bool = {
            ($0.kind.rawValue, $0.workspaceID.uuidString, $0.lineageID.uuidString, $0.revision, $0.eventID.uuidString)
                < ($1.kind.rawValue, $1.workspaceID.uuidString, $1.lineageID.uuidString, $1.revision, $1.eventID.uuidString)
        }
        let serviceReliabilityIncidents = mutationHistory == nil ? [] : try rows.serviceReliabilityIncidents
            .map { try V39BackupAssetServiceIncidentRecordV1($0.value()) }
            .sorted(by: reliabilityOrder)
        let serviceImpactSegments = mutationHistory == nil ? [] : try rows.serviceImpactSegments
            .map { try V39BackupServiceImpactSegmentRecordV1($0.value()) }
            .sorted(by: reliabilityOrder)
        let serviceCauseAssertions = mutationHistory == nil ? [] : try rows.serviceCauseAssertions
            .map { try V39BackupServiceCauseAssertionRecordV1($0.value()) }
            .sorted(by: reliabilityOrder)
        let serviceRemedyAssertions = mutationHistory == nil ? [] : try rows.serviceRemedyAssertions
            .map { try V39BackupServiceRemedyAssertionRecordV1($0.value()) }
            .sorted(by: reliabilityOrder)
        let serviceRepairIntervals = mutationHistory == nil ? [] : try rows.serviceRepairIntervals
            .map { try V39BackupServiceRepairIntervalRecordV1($0.value()) }
            .sorted(by: reliabilityOrder)
        let serviceRestorationAssertions = mutationHistory == nil ? [] : try rows.serviceRestorationAssertions
            .map { try V39BackupServiceRestorationAssertionRecordV1($0.value()) }
            .sorted(by: reliabilityOrder)
        let qualifiedServiceExposures = mutationHistory == nil ? [] : try rows.qualifiedServiceExposures
            .map { try V39BackupQualifiedServiceExposureRecordV1($0.value()) }
            .sorted(by: reliabilityOrder)
        let serviceReliabilityReceipts = try C53ServiceReliabilityBackupEnrollmentV1.receiptRecords(
            from: mutationHistory
        )
        let partsStockSnapshot = try mutationHistory.map { _ in
            try PartsStockLifecycleAdapterV1(modelContext: modelContext).snapshotForBackup(
                workspaceID: try currentStreamingWorkspaceIdentity().workspaceID
            )
        }
        let myDayPlans = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<MyDayPlanRowV1>())
            .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
            .map { try $0.value() }
            .sorted { ($0.key, $0.planID.uuidString, $0.revision)
                < ($1.key, $1.planID.uuidString, $1.revision) }
        let myDayCarryoverReceipts = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>())
            .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
            .map { try $0.value() }
            .sorted { ($0.committedAt, $0.receiptSHA256) < ($1.committedAt, $1.receiptSHA256) }
        let nonactivePlanReferences = try C57MyDayBackupEnrollmentV1
            .exactNonactiveReferences(for: myDayPlans)
        let evidenceAssociationEvents = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<EvidenceAssociationEventRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue.uuidString.lowercased() }
            .sorted { ($0.workspaceID, $0.associationEventID) < ($1.workspaceID, $1.associationEventID) }
        let evidenceSequenceRevisions = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<EvidenceSequenceRevisionRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == sourceIdentity.workspaceID }
            .sorted { EvidenceSequenceRevisionRowV1.rowID(sequenceID: $0.sequenceID, revision: $0.revision)
                < EvidenceSequenceRevisionRowV1.rowID(sequenceID: $1.sequenceID, revision: $1.revision) }
        let shopReportProfiles = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<ShopReportProfileRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == sourceIdentity.workspaceID }
            .sorted { ($0.profileID.uuidString, $0.revision, $0.mutationID.rawValue.uuidString)
                < ($1.profileID.uuidString, $1.revision, $1.mutationID.rawValue.uuidString) }
        let roundSessions = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<RoundSessionRevisionRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == sourceIdentity.workspaceID }
            .sorted { ($0.sessionID.uuidString, $0.revision, $0.mutationID.rawValue.uuidString)
                < ($1.sessionID.uuidString, $1.revision, $1.mutationID.rawValue.uuidString) }
        let importMappingProfiles = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<ImportMappingProfileRowV1>()).map { try $0.value() }
            .filter { $0.workspaceID == sourceIdentity.workspaceID }
            .sorted { $0.profileID.uuidString < $1.profileID.uuidString }
        let bulkSessions = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<BulkSessionRowV1>()).map { try $0.value() }
            .filter { $0.workspaceID == sourceIdentity.workspaceID }
            .sorted { $0.sessionID.uuidString < $1.sessionID.uuidString }
        let bulkCommitReceipts = mutationHistory == nil ? [] : try modelContext
            .fetch(FetchDescriptor<BulkCommitReceiptRowV1>()).map { try $0.value() }
            .filter { $0.workspaceID == sourceIdentity.workspaceID }
            .sorted { $0.receiptID.uuidString < $1.receiptID.uuidString }
        let evidenceQuality: EvidenceQualityBackupSnapshotV1? = try {
            guard mutationHistory != nil else { return nil }
            let ruleSetRows = try modelContext.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
            let ruleSetValues = try ruleSetRows.map { row in
                (try row.value(), try EvidenceQualityBackupEffectProvenanceV1(
                    mutationID: row.mutationID, writerInstanceID: row.writerInstanceID
                ))
            }
            let ruleSets = ruleSetValues.map(\.0)
            let ruleSetsByID = Dictionary(uniqueKeysWithValues: ruleSets.map { ($0.ruleSetID, $0) })
            let assessmentRows = try modelContext.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
            let assessmentValues = try assessmentRows
                .compactMap { row -> (EvidenceQualityAssessmentV1, EvidenceQualityBackupEffectProvenanceV1)? in
                    for ruleSet in ruleSetsByID.values {
                        if let value = try? row.value(ruleSet: ruleSet) {
                            return (value, try EvidenceQualityBackupEffectProvenanceV1(
                                mutationID: row.mutationID, writerInstanceID: row.writerInstanceID
                            ))
                        }
                    }
                    return nil
                }
            let assessments = assessmentValues.map(\.0)
            guard assessments.count == assessmentRows.count else {
                throw BackupExportServiceError.invalidAuthority
            }
            let assessmentsByID = Dictionary(uniqueKeysWithValues: assessments.map { ($0.assessmentID, $0) })
            let waiverRows = try modelContext.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
            let waiverValues = try waiverRows
                .compactMap { row -> (EvidenceQualityWaiverV1, EvidenceQualityBackupEffectProvenanceV1)? in
                    for assessment in assessmentsByID.values {
                        if let value = try? row.value(assessment: assessment) {
                            return (value, try EvidenceQualityBackupEffectProvenanceV1(
                                mutationID: row.mutationID, writerInstanceID: row.writerInstanceID
                            ))
                        }
                    }
                    return nil
                }
            let waivers = waiverValues.map(\.0)
            guard waivers.count == waiverRows.count else {
                throw BackupExportServiceError.invalidAuthority
            }
            let receipts = try modelContext.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try $0.value() }
            return try .init(
                ruleSets: ruleSets, assessments: assessments, waivers: waivers, receipts: receipts,
                effectProvenance: ruleSetValues.map(\.1) + assessmentValues.map(\.1) + waiverValues.map(\.1)
            )
        }()
        let fastSurveyInbox: FastSurveyInboxBackupSnapshotV1? = try {
            guard mutationHistory != nil else { return nil }
            let source = FastSurveyInboxLifecycleAdapterV1(
                modelContext: modelContext, workspaceID: sourceIdentity.workspaceID
            )
            let snapshot = try source.snapshot()
            let itemProvenance = try modelContext.fetch(FetchDescriptor<CaptureInboxItemRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try FastSurveyInboxBackupEffectProvenanceV1(
                    mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                    writerInstanceID: $0.writerInstanceID
                ) }
            let promotionProvenance = try modelContext.fetch(FetchDescriptor<CapturePromotionRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try FastSurveyInboxBackupEffectProvenanceV1(
                    mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                    writerInstanceID: $0.writerInstanceID
                ) }
            let snippetProvenance = try modelContext.fetch(FetchDescriptor<SnippetRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try FastSurveyInboxBackupEffectProvenanceV1(
                    mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                    writerInstanceID: $0.writerInstanceID
                ) }
            let insertionProvenance = try modelContext.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try FastSurveyInboxBackupEffectProvenanceV1(
                    mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                    writerInstanceID: $0.writerInstanceID
                ) }
            return try .init(inboxItems: snapshot.inboxItems, promotions: snapshot.promotions,
                             snippets: snapshot.snippets, snippetInsertions: snapshot.snippetInsertions,
                             receipts: snapshot.receipts,
                             effectProvenance: itemProvenance + promotionProvenance + snippetProvenance + insertionProvenance)
        }()
        let reinspectionExceptionQueue: ReinspectionExceptionQueueBackupSnapshotV1? = try {
            guard mutationHistory != nil else { return nil }
            let source = ReinspectionExceptionQueueLifecycleAdapterV1(
                modelContext: modelContext, workspaceID: sourceIdentity.workspaceID
            )
            let planProvenance = try modelContext.fetch(FetchDescriptor<ReinspectionPlanRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try ReinspectionExceptionBackupEffectProvenanceV1(
                    mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                    writerInstanceID: $0.writerInstanceID
                ) }
            let attestationProvenance = try modelContext.fetch(FetchDescriptor<UnchangedAttestationRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try ReinspectionExceptionBackupEffectProvenanceV1(
                    mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                    writerInstanceID: $0.writerInstanceID
                ) }
            let acknowledgementProvenance = try modelContext.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try ReinspectionExceptionBackupEffectProvenanceV1(
                    mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                    writerInstanceID: $0.writerInstanceID
                ) }
            return try source.backupSnapshot(
                effectProvenance: planProvenance + attestationProvenance + acknowledgementProvenance
            )
        }()
        let entityIdentityResolution: EntityIdentityResolutionBackupSnapshotV1? = try {
            guard mutationHistory != nil else { return nil }
            let aliases = try modelContext.fetch(FetchDescriptor<EntityAliasLinkRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try $0.value() }
            let consolidations = try modelContext.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try $0.value() }
            let receipts = try modelContext.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
                .map { try $0.value() }
            let generations = Set(receipts.map(\.generationID))
            guard generations.count <= 1 else { throw BackupExportServiceError.invalidAuthority }
            return try EntityIdentityResolutionBackupSnapshotV1(
                workspaceID: sourceIdentity.workspaceID,
                generationID: generations.first ?? currentStreamingGenerationID(),
                aliasLinks: aliases,
                consolidationReceipts: consolidations,
                mutationReceipts: receipts
            )
        }()
        let practiceWorkspaceProvenance: PracticeWorkspaceBackupSnapshotV1? = try {
            let rows = try modelContext.fetch(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>())
                .filter { $0.workspaceID == sourceIdentity.workspaceID.rawValue }
            guard rows.count <= 1 else { throw BackupExportServiceError.invalidAuthority }
            guard let row = rows.first else { return nil }
            guard mutationHistory != nil else { throw BackupExportServiceError.invalidAuthority }
            return try PracticeWorkspaceBackupSnapshotV1(provenance: row.value())
        }()
        let contextValues = try EvidenceContextBackupRecordSetV1(
            contexts: rows.evidenceContexts.map { try $0.value() },
            pairedObservationLinks: rows.pairedObservationLinks.map { try $0.value() })
        let contextRecords = try C30EvidenceContextBackupEncoderV1.encode(contextValues)
        _ = try EvidenceContextBackupRecordSetV1.decode(contextRecords)
        guard contextRecords.allSatisfy({ $0.workspaceID == sourceIdentity.workspaceID.rawValue }),
              contextRecords.isEmpty || mutationHistory != nil else {
            throw BackupExportServiceError.invalidAuthority
        }
        let result = V4BackupRecordsV1(
            guidedSurveys:guidedSurveys,
            assetLocators: assetLocators,
            schedules: schedules,
            plans: plans,
            placementPoses: placementPoses,
            accessibleDocumentAssessments:accessibleDocumentAssessments,
            surveyDefinitions:surveyDefinitions,
            fieldReferences:fieldReferences,
            recoverabilityReceipts:recoverabilityReceipts,
            clientCapabilities: clientCapabilities,
            privacyTransforms: privacyTransforms,
            measurementIntegrity: measurementIntegrity,
            packageEvolution: packageEvolution,
            fieldDrafts: fieldDrafts,
            workPackets:workPackets,
            inspectionReview: inspectionReview,
            evidenceAssurance: evidenceAssurance,
            functionalRelationships: functionalRelationships,
            authorityCriterion: authorityCriterion,
            assetSemantics: assetSemantics,
            assetCompositionEdges: assetCompositionEdges,
            assetCompositionEvents: assetCompositionEvents,
            assetPlacementEvents: assetPlacementEvents,
            assets: rows.assets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID,
                    packID: $0.packID, packSchemaVersion: $0.packSchemaVersion,
                    packContentVersion: $0.packContentVersion, label: $0.label,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            deletionLedger: deletionLedger,
            evidenceFiles: rows.evidence.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, recordID: $0.recordID,
                    purposeKey: $0.purposeKey, relativePath: $0.relativePath,
                    mimeType: $0.mimeType, byteCount: $0.byteCount,
                    sha256: $0.sha256, createdAt: $0.createdAt,
                    thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount,
                    thumbnailSHA256: $0.thumbnailSHA256
                )
            }.sorted(by: dtoOrder),
            issues: rows.issues.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, assetID: $0.assetID,
                    openedByRecordID: $0.openedByRecordID, labelKey: $0.labelKey,
                    labelDisplaySnapshot: $0.labelDisplaySnapshot, status: $0.status,
                    resolvedByRecordID: $0.resolvedByRecordID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            locationHierarchyEvents: locationHierarchyEvents,
            locationMigrationReceipts: locationMigrationReceipts,
            locationNodes: locationNodes,
            mutationHistory: archiveMutationHistory,
            packets: rows.packets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    stableRootID: $0.stableRootID,
                    currentRecordID: $0.currentRecordID,
                    evaluationCounted: $0.evaluationCounted,
                    contentDeletedAt: $0.contentDeletedAt, createdAt: $0.createdAt
                )
            }.sorted(by: dtoOrder),
            partyAccountability: try partyAccountabilityRecords(rows),
            recordsSchemaVersion: mutationHistory == nil
                ? (deletionLedger == nil ? 1 : 2)
                : LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
            reports: rows.reports.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    packetID: $0.packetID, sourceRecordID: $0.sourceRecordID,
                    snapshotSchemaVersion: $0.snapshotSchemaVersion,
                    snapshotRelativePath: $0.snapshotRelativePath,
                    snapshotSHA256: $0.snapshotSHA256, pdfState: $0.pdfState,
                    pdfRelativePath: $0.pdfRelativePath, pdfSHA256: $0.pdfSHA256,
                    createdAt: $0.createdAt, replacesReportID: $0.replacesReportID
                )
            }.sorted(by: dtoOrder),
            requirementAssurance: try (mutationHistory == nil ? []
                : rows.requirementAssurance.map(V8BackupRequirementAssuranceRecordV1.init))
                .sorted { $0.workflowRecordID.uuidString < $1.workflowRecordID.uuidString },
            savedSmartViews: try (mutationHistory == nil ? [] : rows.savedSmartViews.map {
                try V7BackupSavedSmartViewRecordV1($0.descriptor())
            }).sorted { $0.id.uuidString < $1.id.uuidString },
            sites: rows.sites.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, label: $0.label,
                    address: $0.address, timeZoneID: $0.timeZoneID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted(by: dtoOrder),
            workflowRecords: try rows.records.map { record in
                guard let companion = rows.observationAndTime[record.id] else {
                    throw BackupExportServiceError.invalidAuthority
                }
                return workflowDTO(record, observationAndTime: companion)
            }.sorted(by: dtoOrder),
            evidenceContexts: contextRecords.filter { $0.kind == .evidenceContext },
            pairedObservationLinks: contextRecords.filter { $0.kind == .pairedObservationLink },
            lighting: lighting,
            lightingDayInventoryWorkflows: try lightingDayInventoryRecords(rows),
            lightingNightWorkflows: try lightingNightWorkflowRecords(rows),
            assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,
            temporalEvidence: temporalEvidence,
            acceptedLabelGenerationSnapshots: acceptedLabelGenerationSnapshots,
            operationalContacts: operationalContacts,
            activityContracts: activityContracts,
            workResources: workResources,
             serviceRequests: serviceRequests,
             serviceRequestDispositionEvents: serviceRequestDispositionEvents,
             serviceRequestWorkLinkEvents: serviceRequestWorkLinkEvents,
             serviceReliabilityIncidents: serviceReliabilityIncidents,
             serviceImpactSegments: serviceImpactSegments,
             serviceCauseAssertions: serviceCauseAssertions,
             serviceRemedyAssertions: serviceRemedyAssertions,
             serviceRepairIntervals: serviceRepairIntervals,
             serviceRestorationAssertions: serviceRestorationAssertions,
             qualifiedServiceExposures: qualifiedServiceExposures,
             serviceReliabilityReceipts: serviceReliabilityReceipts,
             partsStockSnapshot: partsStockSnapshot,
             myDayPlans: myDayPlans,
             myDayCarryoverReceipts: myDayCarryoverReceipts,
             nonactivePlanReferences: nonactivePlanReferences,
             evidenceAssociationEvents: evidenceAssociationEvents,
             evidenceSequenceRevisions: evidenceSequenceRevisions,
             shopReportProfiles: shopReportProfiles,
             roundSessions: roundSessions,
             importMappingProfiles: importMappingProfiles,
             bulkSessions: bulkSessions,
             bulkCommitReceipts: bulkCommitReceipts,
             evidenceQuality: evidenceQuality,
             fastSurveyInbox: fastSurveyInbox,
             reinspectionExceptionQueue: reinspectionExceptionQueue,
             entityIdentityResolution: entityIdentityResolution,
             practiceWorkspaceProvenance: practiceWorkspaceProvenance
         )
        try result.validateC30EvidenceContextClosure()
        return result
    }

    private func inspectionReviewRecords(
        _ rows: Rows
    ) throws -> [V14BackupInspectionReviewRecordV1] {
        var result: [V14BackupInspectionReviewRecordV1] = []
        result += try rows.inspectionReviewTransitions.map { let v = try $0.value(); return .init(
            kind: .reviewTransition, id: v.transitionID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try InspectionReviewCanonicalCodecV1.encode(v)) }
        result += try rows.reviewDispositions.map { let v = try $0.value(); return .init(
            kind: .reviewDisposition, id: v.dispositionID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try InspectionReviewCanonicalCodecV1.encode(v)) }
        result += try rows.changeRequests.map { let v = try $0.value(); return .init(
            kind: .changeRequest, id: v.requestRevisionID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try InspectionReviewCanonicalCodecV1.encode(v)) }
        result += try rows.correctiveActionPolicies.map { let v = try $0.value(); return .init(
            kind: .correctiveActionPolicy, id: v.releaseID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try InspectionReviewCanonicalCodecV1.encode(v)) }
        result += try rows.correctiveActionEvents.map { let v = try $0.value(); return .init(
            kind: .correctiveActionEvent, id: v.eventID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try InspectionReviewCanonicalCodecV1.encode(v)) }
        return result.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    private func workPacketRecords(_ rows:Rows)throws->[V15BackupWorkPacketRecordV1]{
        var result:[V15BackupWorkPacketRecordV1]=[]
        result += try rows.workPacketManifests.map{let v=try $0.value();return .init(kind:.manifest,id:v.manifestID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try WorkPacketCanonicalCodecV1.encode(v))}
        result += try rows.workItemClaims.map{let v=try $0.value();return .init(kind:.claim,id:v.claimID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try WorkPacketCanonicalCodecV1.encode(v))}
        result += try rows.workLeases.map{let v=try $0.value();return .init(kind:.lease,id:v.leaseID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try WorkPacketCanonicalCodecV1.encode(v))}
        result += try rows.workReleases.map{let v=try $0.value();return .init(kind:.release,id:v.releaseID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try WorkPacketCanonicalCodecV1.encode(v))}
        result += try rows.workHandoffs.map{let v=try $0.value();return .init(kind:.handoff,id:v.handoffID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try WorkPacketCanonicalCodecV1.encode(v))}
        return result.sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"}
    }

    private func fieldDraftRecords(_ rows: Rows) throws -> [V16BackupFieldDraftRecordV1] {
        var result: [V16BackupFieldDraftRecordV1] = []
        result += try rows.fieldDraftCheckpoints.map { let v = try $0.value(); return .init(kind: .checkpoint, id: v.draftID, workspaceID: v.workspaceID.rawValue, revision: v.draftRevision, canonicalData: try FieldDraftCanonicalCodecV1.encode(v)) }
        result += try rows.attachmentStagingItems.map { let v = try $0.value(); return .init(kind: .stagingItem, id: v.stageID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try FieldDraftCanonicalCodecV1.encode(v)) }
        result += try rows.draftCommitSagas.map { let v = try $0.value(); return .init(kind: .commitSaga, id: v.sagaID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try FieldDraftCanonicalCodecV1.encode(v)) }
        result += try rows.draftContentReservations.map { let v = try $0.value(); return .init(kind: .contentReservation, id: v.reservationID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try FieldDraftCanonicalCodecV1.encode(v)) }
        result += try rows.draftCommitReceipts.map { let v = try $0.value(); return .init(kind: .commitReceipt, id: v.receiptID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try FieldDraftCanonicalCodecV1.encode(v)) }
        result += try rows.draftDiscardReceipts.map { let v = try $0.value(); return .init(kind: .discardReceipt, id: v.receiptID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try FieldDraftCanonicalCodecV1.encode(v)) }
        return result.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    private func packageEvolutionRecords(_ rows: Rows) throws -> [V17BackupPackageEvolutionRecordV1] {
        var result: [V17BackupPackageEvolutionRecordV1] = []
        result += try rows.promotedPackageReleases.map { let v = try $0.value(); return .init(kind: .promotedRelease, id: v.releaseRecordID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PackageEvolutionCanonicalCodecV1.encode(v)) }
        result += try rows.packageSandboxRuns.map { let v = try $0.value(); return .init(kind: .sandboxRun, id: v.runID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PackageEvolutionCanonicalCodecV1.encode(v)) }
        result += try rows.packagePromotionReceipts.map { let v = try $0.value(); return .init(kind: .promotionReceipt, id: v.receiptID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PackageEvolutionCanonicalCodecV1.encode(v)) }
        result += try rows.activePackageRegistryPointers.map { let v = try $0.value(); return .init(kind: .activePointer, id: v.pointerID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PackageEvolutionCanonicalCodecV1.encode(v)) }
        return result.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    private func measurementIntegrityRecords(_ rows: Rows) throws -> [V18BackupMeasurementIntegrityRecordV1] {
        var result:[V18BackupMeasurementIntegrityRecordV1]=[]
        result += try rows.instrumentReferences.map{let v=try $0.value();return .init(kind:.instrumentReference,id:v.referenceID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode(v))}
        result += try rows.calibrationStatusSnapshots.map{let v=try $0.value();return .init(kind:.calibrationSnapshot,id:v.snapshotID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode(v))}
        result += try rows.measurementCaptures.map{let v=try $0.value();return .init(kind:.measurementCapture,id:v.captureID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode(v))}
        result += try rows.measurementSeries.map{let v=try $0.value();return .init(kind:.measurementSeries,id:v.snapshotID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode(v))}
        result += try rows.measurementQualityAssessments.map{let v=try $0.value();return .init(kind:.qualityAssessment,id:v.assessmentID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode(v))}
        return result.sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"}
    }

    private func privacyTransformRecords(_ rows: Rows) throws -> [V19BackupPrivacyTransformRecordV1] {
        var result: [V19BackupPrivacyTransformRecordV1] = []
        let policies = try Dictionary(uniqueKeysWithValues: rows.privacyTransformPolicies.map { let v = try $0.value(); return (v.policyID, v) })
        result += try rows.privacyTransformPolicies.map { let v = try $0.value(); return .init(kind: .policy, id: v.policyID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(v)) }
        result += try rows.privacyRegions.map { let v = try $0.value(); return .init(kind: .region, id: v.regionID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(v)) }
        let manifests = try Dictionary(uniqueKeysWithValues: rows.privacyTransformManifests.map { row in
            guard let policy = policies[row.policyID] else { throw BackupExportServiceError.invalidAuthority }
            let value = try row.value(policy: policy)
            return (value.manifestID, value)
        })
        result += try manifests.values.map { v in .init(kind: .manifest, id: v.manifestID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(v)) }
        result += try rows.privacyReviewReceipts.map { row in
            guard let manifest = manifests[row.manifestID], let policy = policies[row.policyID] else { throw BackupExportServiceError.invalidAuthority }
            let v = try row.value(manifest: manifest, policy: policy)
            return .init(kind: .reviewReceipt, id: v.receiptID, workspaceID: v.workspaceID.rawValue, revision: v.revision, canonicalData: try PrivacyTransformCanonicalCodecV1.encode(v))
        }
        return result.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    private func clientCapabilityRecords(_ rows:Rows)throws->[V20BackupClientCapabilityRecordV1]{
        let releases=try Dictionary(uniqueKeysWithValues:rows.promotedPackageReleases.map{let v=try $0.value();return(v.packageRelease.packageReleaseID,v.packageRelease)})
        let profiles=try Dictionary(uniqueKeysWithValues:rows.clientCapabilityProfiles.map{let v=try $0.value();return(v.profileID,v)})
        let policies=try Dictionary(uniqueKeysWithValues:rows.packageLifecyclePolicies.map{row in guard let release=releases[row.packageReleaseID]else{throw BackupExportServiceError.invalidAuthority};let v=try row.value(release:release);return(v.policyID,v)})
        let dispositions=try Dictionary(uniqueKeysWithValues:rows.packageLifecycleDispositions.map{row in guard let release=releases[row.packageReleaseID]else{throw BackupExportServiceError.invalidAuthority};let v=try row.value(release:release);return(v.dispositionID,v)})
        var result:[V20BackupClientCapabilityRecordV1]=try profiles.values.map{.init(kind:.profile,id:$0.profileID,workspaceID:$0.workspaceID.rawValue,revision:$0.revision,canonicalData:try ClientCapabilityCanonicalCodecV1.encode($0))}+policies.values.map{.init(kind:.policy,id:$0.policyID,workspaceID:$0.workspaceID.rawValue,revision:$0.revision,canonicalData:try ClientCapabilityCanonicalCodecV1.encode($0))}+dispositions.values.map{.init(kind:.disposition,id:$0.dispositionID,workspaceID:$0.workspaceID.rawValue,revision:$0.revision,canonicalData:try ClientCapabilityCanonicalCodecV1.encode($0))}
        result += try rows.clientCapabilityAdmissionDecisions.map{row in guard let profile=profiles[row.profileID],let policy=policies[row.policyID],let disposition=dispositions[row.dispositionID],let release=releases[row.packageReleaseID]else{throw BackupExportServiceError.invalidAuthority};let v=try row.value(profile:profile,policy:policy,disposition:disposition,release:release);return .init(kind:.admissionDecision,id:v.decisionID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try ClientCapabilityCanonicalCodecV1.encode(v))};return result.sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"}
    }

    private func recoverabilityReceiptRecords(_ rows:Rows)throws->[V21BackupRecoverabilityReceiptRecordV1]{
        try rows.recoverabilityVerificationReceipts.map{let value=try $0.value();return .init(id:value.receiptID,workspaceID:value.workspaceID.rawValue,revision:value.revision,canonicalData:try RecoverabilityVerificationCanonicalCodecV1.encode(value))}.sorted{$0.id.uuidString<$1.id.uuidString}
    }

    private func fieldReferenceRecords(_ rows:Rows)throws->[V22BackupFieldReferenceRecordV1]{
        let releases=try Dictionary(uniqueKeysWithValues:rows.fieldReferenceReleases.map{row in let value=try row.value();return(value.releaseID,value)})
        var result=try releases.values.map{V22BackupFieldReferenceRecordV1(kind:.release,id:$0.releaseID,workspaceID:$0.workspaceID.rawValue,revision:$0.revision,canonicalData:try FieldReferencePackCanonicalCodecV1.encode($0))}
        result += try rows.fieldReferenceBindings.map{row in guard let release=releases[row.releaseID]else{throw BackupExportServiceError.invalidAuthority};let value=try row.value(release:release);return V22BackupFieldReferenceRecordV1(kind:.binding,id:value.bindingID,workspaceID:value.workspaceID.rawValue,revision:value.revision,canonicalData:try FieldReferencePackCanonicalCodecV1.encode(value))}
        return result.sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"}
    }

    private func accessibleDocumentAssessmentRecords(_ rows:Rows)throws->[V23BackupAccessibleDocumentAssessmentRecordV1]{
        try rows.accessibleDocumentAssessmentReceipts.map{let value=try $0.value();return .init(id:value.receiptID,workspaceID:value.workspaceID.rawValue,revision:value.revision,canonicalData:try AccessibleDocumentCanonicalCodecV1.encode(value))}.sorted{$0.id.uuidString<$1.id.uuidString}
    }

    private func surveyDefinitionRecords(_ rows:Rows,history:MutationHistorySnapshotV1)throws->[V24BackupSurveyDefinitionRecordV1]{
        let releases=try Dictionary(uniqueKeysWithValues:rows.surveyDefinitionReleases.map{let value=try $0.value();return(value.releaseID,value)})
        let events=try history.receipts.compactMap{record->(UUID,SurveyDefinitionLifecycleEventV1)? in let envelope=try MutationEnvelopeV1.decodeCanonical(from:record.envelopeData);guard case let .applySurveyDefinition(mutation)=envelope.command else{return nil};try mutation.validate();return(mutation.event.eventID,mutation.event)};guard Set(events.map(\.0)).count==events.count else{throw BackupExportServiceError.invalidAuthority};let eventByID=Dictionary(uniqueKeysWithValues:events)
        var result=try releases.values.map{V24BackupSurveyDefinitionRecordV1(kind:.release,id:$0.releaseID,workspaceID:$0.workspaceID.rawValue,revision:$0.revision,canonicalData:try SurveyDefinitionCanonicalCodecV1.encode($0))}
        result += try rows.surveyDefinitionIdentities.map{row in
            guard let release=releases[row.currentReleaseID],let historic=eventByID[row.latestLifecycleEventID]else{throw BackupExportServiceError.invalidAuthority}
            let value=try row.value()
            if historic.workspaceID==value.workspaceID{try value.validate(currentRelease:release,event:historic)}else{
                let local=try LocalActorReferenceV1(actorReferenceID:historic.actor.actor.actorReferenceID,workspaceID:value.workspaceID,partyID:historic.actor.actor.partyID,displayName:historic.actor.actor.displayName)
                let actor=try ActorSnapshotV1(snapshotID:historic.actor.snapshotID,workspaceID:value.workspaceID,actor:local,responsibility:historic.actor.responsibility,displayNameAtTime:historic.actor.displayNameAtTime,capturedAt:historic.actor.capturedAt)
                let rebound=try SurveyDefinitionLifecycleEventV1(eventID:historic.eventID,workspaceID:value.workspaceID,definitionID:historic.definitionID,action:historic.action,priorState:historic.priorState,resultingState:historic.resultingState,release:SurveyDefinitionReleaseReferenceV1(release),predecessorEventID:historic.predecessorEventID,predecessorEventSHA256:historic.predecessorEventSHA256,sourceDefinitionID:historic.sourceDefinitionID,sourceReleaseID:historic.sourceReleaseID,sourceReleaseSHA256:historic.sourceReleaseSHA256,sourceArchiveSHA256:historic.sourceArchiveSHA256,semanticDiffSHA256:historic.semanticDiffSHA256,actor:actor,recordedAt:historic.recordedAt,revision:historic.revision,mutationID:historic.mutationID)
                try value.validate(currentRelease:release,event:rebound)
            }
            return .init(kind:.identity,id:value.definitionID,workspaceID:value.workspaceID.rawValue,revision:value.revision,canonicalData:try SurveyDefinitionCanonicalCodecV1.encode(value))
        };return result.sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"}
    }
    private func guidedSurveyRecords(_ rows:Rows)throws->[V25BackupGuidedSurveyRecordV1]{
        try (
            rows.surveySessions.map{let v=try $0.value();return .init(kind:.session,id:v.sessionID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try SurveySessionCanonicalCodecV1.encode(v))}
            + rows.factCaptures.map{let v=try $0.value();return .init(kind:.factCapture,id:v.captureID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try SurveySessionCanonicalCodecV1.encode(v))}
            + rows.provisionalSubjects.map{let v=try $0.value();return .init(kind:.provisionalSubject,id:v.provisionalSubjectID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try SurveySessionCanonicalCodecV1.encode(v))}
            + rows.subjectPromotionReceipts.map{let v=try $0.value();return .init(kind:.subjectPromotionReceipt,id:v.receiptID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try SurveySessionCanonicalCodecV1.encode(v))}
            + rows.surveyPublicationSnapshots.map{let v=try $0.value();return .init(kind:.publicationSnapshot,id:v.snapshotID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try SurveySessionCanonicalCodecV1.encode(v))}
        ).sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"}
    }

    private func assetLocatorRecords(_ rows: Rows) throws -> [V26BackupAssetLocatorRecordV1] {
        let workspaceID = try currentStreamingWorkspaceIdentity().workspaceID
        let locators = try rows.assetLocators.map { row in
            let value = try row.value()
            guard value.workspaceID == workspaceID else {
                throw BackupExportServiceError.invalidAuthority
            }
            return V26BackupAssetLocatorRecordV1(
                kind: .locator, id: value.locatorID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try AssetLocatorCanonicalCodecV1.encode(value)
            )
        }
        let receipts = try rows.locatorBindingReceipts.map { row in
            let value = try row.value()
            guard value.workspaceID == workspaceID else {
                throw BackupExportServiceError.invalidAuthority
            }
            return V26BackupAssetLocatorRecordV1(
                kind: .bindingReceipt, id: value.receiptID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try AssetLocatorCanonicalCodecV1.encode(value)
            )
        }
        let records = (locators + receipts).sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        try AssetLocatorLifecycleClosureV1(
            locators: try rows.assetLocators.map { try $0.value() },
            receipts: try rows.locatorBindingReceipts.map { try $0.value() }
        ).validate()
        return records
    }

    private func scheduleRecords(_ rows: Rows) throws -> [V27BackupScheduleRecordV1] {
        guard C51ScheduleBackupClosureV1.preservedV27RecordBytes,
              C51ScheduleBackupClosureV1.persistedRecordKindCount == 4
        else { throw BackupExportServiceError.invalidAuthority }
        let definitions = try rows.scheduleDefinitionReleases.map { try $0.value() }
        let history = try rows.occurrenceHistoryEvents.map { try $0.value() }
        let calendars = try rows.exceptionCalendarReleases.map { try $0.value() }
        let overrides = try rows.scheduleOverrideEvents.map { try $0.value() }
        guard !definitions.isEmpty || !history.isEmpty || !calendars.isEmpty || !overrides.isEmpty else { return [] }
        let workspaceID = try currentStreamingWorkspaceIdentity().workspaceID
        guard definitions.allSatisfy({ $0.workspaceID == workspaceID }),
              history.allSatisfy({ $0.workspaceID == workspaceID }),
              calendars.allSatisfy({ $0.workspaceID == workspaceID }),
              overrides.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        do {
            try ScheduleLifecycleClosureV1(
                definitions: definitions, history: history
            ).validate()
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        guard C51ScheduleBackupClosureV1.validatesAdvancedCalendarReferences(
            definitions: definitions, calendars: calendars
        ) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let releaseRows = try definitions.map { value in
            V27BackupScheduleRecordV1(
                kind: .scheduleRelease, id: value.releaseID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(value)
            )
        }
        let historyRows = try history.map { value in
            V27BackupScheduleRecordV1(
                kind: .occurrenceHistory, id: value.eventID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(value)
            )
        }
        let calendarRows = try calendars.map { value in
            V27BackupScheduleRecordV1(
                kind: .exceptionCalendarRelease, id: value.releaseID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(value)
            )
        }
        let overrideRows = try overrides.map { value in
            V27BackupScheduleRecordV1(
                kind: .scheduleOverrideEvent, id: value.eventID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try ScheduleCanonicalCodecV1.data(value)
            )
        }
        let records = (releaseRows + historyRows + calendarRows + overrideRows).sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        guard C51ScheduleBackupClosureV1.validatesEnvelope(records) else {
            throw BackupExportServiceError.invalidAuthority
        }
        return records
    }

    private func planRecords(_ rows: Rows) throws -> [V28BackupPlanRecordV1] {
        let documents = try rows.planDocuments.map { try $0.value() }
        let revisions = try rows.planRevisions.map { try $0.value() }
        let placements = try rows.planPlacements.map { try $0.value() }
        let receipts = try rows.rebaseReceipts.map { try $0.value() }
        guard !documents.isEmpty || !revisions.isEmpty || !placements.isEmpty || !receipts.isEmpty else {
            return []
        }
        let workspaceID = try currentStreamingWorkspaceIdentity().workspaceID
        guard documents.allSatisfy({ $0.workspaceID == workspaceID }),
              revisions.allSatisfy({ $0.workspaceID == workspaceID }),
              placements.allSatisfy({ $0.workspaceID == workspaceID }),
              receipts.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let closure = PlanLifecycleClosureV1(
            documentHistory: documents,
            revisionHistory: revisions,
            placementHistory: placements,
            receipts: receipts
        )
        try closure.validate()

        var frameByID: [UUID: (value: SpatialReferenceFrameV1, revision: UInt64)] = [:]
        for revision in revisions {
            for frame in revision.spatialFrames {
                if let existing = frameByID[frame.frameID], existing.value != frame {
                    throw BackupExportServiceError.invalidAuthority
                }
                frameByID[frame.frameID] = (frame, revision.revision)
            }
        }
        let documentRecords = try documents.map {
            V28BackupPlanRecordV1(
                kind: .document, id: $0.planDocumentID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try PlanCanonicalCodecV1.encode($0)
            )
        }
        let revisionRecords = try revisions.map {
            V28BackupPlanRecordV1(
                kind: .revision, id: $0.planRevisionID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try PlanCanonicalCodecV1.encode($0)
            )
        }
        let frameRecords = try frameByID.values.map {
            V28BackupPlanRecordV1(
                kind: .spatialFrame, id: $0.value.frameID,
                workspaceID: workspaceID.rawValue, revision: $0.revision,
                canonicalData: try PlanCanonicalCodecV1.encode($0.value)
            )
        }
        let placementRecords = try placements.map {
            V28BackupPlanRecordV1(
                kind: .placement, id: $0.placementID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try PlanCanonicalCodecV1.encode($0)
            )
        }
        let receiptRecords = try receipts.map {
            V28BackupPlanRecordV1(
                kind: .rebaseReceipt, id: $0.receiptID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try PlanCanonicalCodecV1.encode($0)
            )
        }
        let result = (documentRecords + revisionRecords + frameRecords + placementRecords + receiptRecords).sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        _ = try PlanBackupRecordSetV1.decode(result)
        return result
    }

    private func placementPoseRecords(
        _ rows: Rows
    ) throws -> [V29BackupPlacementPoseRecordV1] {
        let events = try rows.poseEvents.map { try $0.value() }
        let observations = try rows.spatialAnchorObservations.map { try $0.value() }
        let workspaceID = try currentStreamingWorkspaceIdentity().workspaceID
        guard events.allSatisfy({ $0.workspaceID == workspaceID }),
              observations.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let eventRecords = try events.map {
            V29BackupPlacementPoseRecordV1(
                kind: .poseEvent,
                id: $0.eventID,
                workspaceID: $0.workspaceID.rawValue,
                revision: $0.revision,
                canonicalData: try PlacementPoseCanonicalCodecV1.encode($0)
            )
        }
        let observationRecords = try observations.map {
            V29BackupPlacementPoseRecordV1(
                kind: .spatialAnchorObservation,
                id: $0.observationID,
                workspaceID: $0.workspaceID.rawValue,
                revision: $0.revision,
                canonicalData: try PlacementPoseCanonicalCodecV1.encode($0)
            )
        }
        let result = (eventRecords + observationRecords).sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        do {
            _ = try PlacementPoseBackupRecordSetV1.decode(result)
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        return result
    }

    private func lightingRecords(
        _ rows: Rows
    ) throws -> [V31BackupLightingRecordV1] {
        let workspaceID = try currentStreamingWorkspaceIdentity().workspaceID
        let systems = try rows.lightingSystems.map { try $0.value() }
        let observations = try rows.lightingObservations.map { try $0.value() }
        let issues = try rows.lightingIssues.map { try $0.value() }
        let plans = try rows.lightingPlans.map { try $0.value() }
        let claims = try rows.lightingClaims.map { try $0.value() }
        guard systems.allSatisfy({ $0.workspaceID == workspaceID }),
              observations.allSatisfy({ $0.workspaceID == workspaceID }),
              issues.allSatisfy({ $0.workspaceID == workspaceID }),
              plans.allSatisfy({ $0.workspaceID == workspaceID }),
              claims.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        var result = try systems.map {
            V31BackupLightingRecordV1(
                kind: .lightingSystem, id: $0.recordID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try LightingCanonicalCodecV1.encode($0)
            )
        }
        result += try observations.map {
            V31BackupLightingRecordV1(
                kind: .lightingObservation, id: $0.recordID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try LightingCanonicalCodecV1.encode($0)
            )
        }
        result += try issues.map {
            V31BackupLightingRecordV1(
                kind: .lightingIssue, id: $0.recordID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try LightingCanonicalCodecV1.encode($0)
            )
        }
        result += try plans.map {
            V31BackupLightingRecordV1(
                kind: .measurementPlan, id: $0.recordID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try LightingCanonicalCodecV1.encode($0)
            )
        }
        result += try claims.map {
            V31BackupLightingRecordV1(
                kind: .lightingClaim, id: $0.recordID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try LightingCanonicalCodecV1.encode($0)
            )
        }
        result.sort {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        do {
            _ = try LightingBackupRecordSetV1.decode(result)
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
        return result
    }

    private func lightingDayInventoryRecords(
        _ rows: Rows
    ) throws -> [V52BackupLightingDayInventoryRecordV1] {
        let workspaceID = try currentStreamingWorkspaceIdentity().workspaceID
        let values = try rows.lightingDayInventoryWorkflows.map { try $0.value() }
        guard values.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let result = try values.map {
            V52BackupLightingDayInventoryRecordV1(
                kind: .workflow, id: $0.recordID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try LightingDayInventoryCanonicalCodecV1.encode($0)
            )
        }.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        _ = try LightingDayInventoryBackupRecordSetV1.decode(result)
        return result
    }

    private func lightingNightWorkflowRecords(
        _ rows: Rows
    ) throws -> [V53BackupLightingNightWorkflowRecordV1] {
        let workspaceID = try currentStreamingWorkspaceIdentity().workspaceID
        let values = try rows.lightingNightWorkflows.map { try $0.value() }
        guard values.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let result = try values.map {
            V53BackupLightingNightWorkflowRecordV1(
                kind: .workflow, id: $0.recordID,
                workspaceID: $0.workspaceID.rawValue, revision: $0.revision,
                canonicalData: try LightingCanonicalCodecV1.encode($0)
            )
        }.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        _ = try LightingNightWorkflowBackupRecordSetV1.decode(result)
        return result
    }

    private func functionalRelationshipRecords(
        _ rows: Rows
    ) throws -> [V12BackupFunctionalRelationshipRecordV1] {
        var result: [V12BackupFunctionalRelationshipRecordV1] = []
        result += try rows.functionalRelationshipDescriptors.map {
            let value = try $0.value()
            return .init(kind: .descriptor, id: value.descriptorReleaseID,
                         workspaceID: value.workspaceID.rawValue, revision: value.revision,
                         canonicalData: try FunctionalRelationshipCanonicalCodecV1.encode(value))
        }
        result += try rows.functionalRelationshipEvents.map {
            let value = try $0.value()
            return .init(kind: .event, id: value.eventID,
                         workspaceID: value.workspaceID.rawValue, revision: value.revision,
                         canonicalData: try FunctionalRelationshipCanonicalCodecV1.encode(value))
        }
        return result.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    private func evidenceAssuranceRecords(
        _ rows: Rows
    ) throws -> [V13BackupEvidenceAssuranceRecordV1] {
        var result: [V13BackupEvidenceAssuranceRecordV1] = []
        result += try rows.evidenceVisibilities.map { let v = try $0.value(); return .init(
            kind: .visibility, id: v.visibilityID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try EvidenceAssuranceCanonicalCodecV1.encode(v)) }
        result += try rows.claimEvidenceLinks.map { let v = try $0.value(); return .init(
            kind: .evidenceLink, id: v.linkID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try EvidenceAssuranceCanonicalCodecV1.encode(v)) }
        result += try rows.assuranceManifests.map { let v = try $0.value(); return .init(
            kind: .manifest, id: v.manifestID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try EvidenceAssuranceCanonicalCodecV1.encode(v)) }
        result += try rows.attestations.map { let v = try $0.value(); return .init(
            kind: .attestation, id: v.attestationID, workspaceID: v.workspaceID.rawValue,
            revision: v.revision, canonicalData: try EvidenceAssuranceCanonicalCodecV1.encode(v)) }
        return result.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    private func partyAccountabilityRecords(
        _ rows: Rows
    ) throws -> [V9BackupPartyAccountabilityRecordV1] {
        var result: [V9BackupPartyAccountabilityRecordV1] = []
        result += try rows.serviceParties.map {
            let value = try $0.value()
            return .init(kind: .serviceParty, id: value.partyID,
                         workspaceID: value.workspaceID.rawValue,
                         revision: value.revision, canonicalData: $0.canonicalData)
        }
        result += try rows.sitePartyRoleEvents.map {
            let value = try $0.value()
            return .init(kind: .sitePartyRoleEvent, id: value.eventID,
                         workspaceID: value.workspaceID.rawValue,
                         revision: value.revision, canonicalData: $0.canonicalData)
        }
        result += try rows.actorSnapshots.map {
            let value = try $0.value()
            return .init(kind: .actorSnapshot, id: value.snapshotID,
                         workspaceID: value.workspaceID.rawValue,
                         revision: nil, canonicalData: $0.canonicalData)
        }
        result += try rows.qualificationSnapshots.map {
            let value = try $0.value()
            return .init(kind: .qualificationSnapshot, id: value.snapshotID,
                         workspaceID: value.workspaceID.rawValue,
                         revision: nil, canonicalData: $0.canonicalData)
        }
        result += try rows.signoffSnapshots.map {
            let value = try $0.value()
            return .init(kind: .signoffSnapshot, id: value.snapshotID,
                         workspaceID: value.workspaceID.rawValue,
                         revision: value.subjectRevision, canonicalData: $0.canonicalData)
        }
        return result.sorted {
            let lhs = "\($0.kind.rawValue)\u{0}\($0.id.uuidString)"
            let rhs = "\($1.kind.rawValue)\u{0}\($1.id.uuidString)"
            return lhs < rhs
        }
    }

    private func assetSemanticRecords(
        _ rows: Rows
    ) throws -> [V10BackupAssetSemanticRecordV1] {
        var result: [V10BackupAssetSemanticRecordV1] = []
        result += try rows.assetKindBindingEvents.map {
            let value = try $0.value()
            return .init(kind: .kindBindingEvent, id: value.eventID,
                         workspaceID: value.workspaceID.rawValue, revision: value.revision,
                         canonicalData: $0.canonicalData)
        }
        result += try rows.assetWorkflowCapabilityBindingEvents.map {
            let value = try $0.value()
            return .init(kind: .workflowCapabilityBindingEvent, id: value.eventID,
                         workspaceID: value.workspaceID.rawValue, revision: value.revision,
                         canonicalData: $0.canonicalData)
        }
        result += try rows.assetProductIdentities.map {
            let value = try $0.value()
            return .init(kind: .productIdentity, id: value.identityID,
                         workspaceID: value.workspaceID.rawValue, revision: value.revision,
                         canonicalData: $0.canonicalData)
        }
        result += try rows.assetLifecycleEvents.map {
            let value = try $0.value()
            return .init(kind: .lifecycleEvent, id: value.record.eventID,
                         workspaceID: value.record.workspaceID.rawValue,
                         revision: value.record.revision, canonicalData: $0.canonicalData)
        }
        result += try rows.assetSuccessorLinks.map {
            let value = try $0.value()
            return .init(kind: .successorLink, id: value.linkID,
                         workspaceID: value.workspaceID.rawValue, revision: value.revision,
                         canonicalData: $0.canonicalData)
        }
        result += try rows.workSubjectScopeSnapshots.map {
            let value = try $0.value()
            return .init(kind: .workSubjectScopeSnapshot, id: value.snapshotID,
                         workspaceID: value.workspaceID.rawValue, revision: value.workspaceRevision,
                         canonicalData: $0.canonicalData)
        }
        return result.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString)"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)"
        }
    }

    private func authorityCriterionRecords(
        _ rows: Rows
    ) throws -> [V11BackupAuthorityCriterionRecordV1] {
        var result: [V11BackupAuthorityCriterionRecordV1] = []
        result += try rows.authoritySourceReleases.map { let v = try $0.value(); return .init(kind: .authoritySourceRelease, id: v.releaseID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.requirementBasisBindings.map { let v = try $0.value(); return .init(kind: .requirementBasisBinding, id: v.bindingID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.applicabilityContextSnapshots.map { let v = try $0.value(); return .init(kind: .applicabilityContextSnapshot, id: v.snapshotID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.assessmentScopeSnapshots.map { let v = try $0.value(); return .init(kind: .assessmentScopeSnapshot, id: v.snapshotID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.severityScaleReleases.map { let v = try $0.value(); return .init(kind: .severityScaleRelease, id: v.releaseID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.findingClassificationBindings.map { let v = try $0.value(); return .init(kind: .findingClassificationBinding, id: v.bindingID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.measurementProtocolReleases.map { let v = try $0.value(); return .init(kind: .measurementProtocolRelease, id: v.releaseID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.derivedFactEvaluatorDescriptors.map { let v = try $0.value(); return .init(kind: .derivedFactEvaluatorDescriptor, id: v.descriptorID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        result += try rows.derivedFactProvenances.map { let v = try $0.value(); return .init(kind: .derivedFactProvenance, id: v.provenanceID, workspaceID: v.workspaceID.rawValue, canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(v)) }
        return result.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    private func validateAssetSemanticRows(
        _ rows: Rows,
        deletionLedger: DeletionLedgerV2
    ) throws {
        do {
            let kinds = try Dictionary(uniqueKeysWithValues: rows.assetKindBindingEvents.map {
                let value = try $0.value(); return (value.eventID, value)
            })
            let workflows = try Dictionary(uniqueKeysWithValues: rows.assetWorkflowCapabilityBindingEvents.map {
                let value = try $0.value(); return (value.eventID, value)
            })
            let identities = try Dictionary(uniqueKeysWithValues: rows.assetProductIdentities.map {
                let value = try $0.value(); return (value.identityID, value)
            })
            let lifecycle = try Dictionary(uniqueKeysWithValues: rows.assetLifecycleEvents.map {
                let value = try $0.value(); return (value.record.eventID, value)
            })
            let successors = try Dictionary(uniqueKeysWithValues: rows.assetSuccessorLinks.map {
                let value = try $0.value(); return (value.linkID, value)
            })
            let scopes = try rows.workSubjectScopeSnapshots.map { try $0.value() }
            let deletedAssetIDs = Set(deletionLedger.entries.compactMap {
                $0.identity.kind == .asset ? $0.identity.id : nil
            })
            let deletedSiteIDs = Set(deletionLedger.entries.compactMap {
                $0.identity.kind == .site ? $0.identity.id : nil
            })
            let assetIDs = Set(rows.assets.map(\.id)).union(deletedAssetIDs)
            let siteIDs = Set(rows.sites.map(\.id)).union(deletedSiteIDs)
            let locationIDs = Set(rows.locationNodes.map(\.id))
            guard kinds.values.allSatisfy({ value in
                      assetIDs.contains(value.assetID)
                        && (value.predecessorEventID.map { id in
                            kinds[id].map { $0.assetID == value.assetID && $0.revision < value.revision } == true
                        } ?? true)
                  }), workflows.values.allSatisfy({ value in
                      guard let kind = kinds[value.kindBindingEventID] else { return false }
                      return assetIDs.contains(value.assetID) && kind.assetID == value.assetID
                        && kind.revision == value.kindBindingRevision
                        && (value.predecessorEventID.map { id in
                            workflows[id].map { $0.assetID == value.assetID && $0.revision < value.revision } == true
                        } ?? true)
                  }), identities.values.allSatisfy({ value in
                      assetIDs.contains(value.assetID)
                        && (value.predecessorIdentityID.map { id in
                            identities[id].map { $0.assetID == value.assetID && $0.revision < value.revision } == true
                        } ?? true)
                  }), successors.values.allSatisfy({ value in
                      assetIDs.contains(value.predecessorAssetID)
                        && assetIDs.contains(value.successorAssetID)
                        && (value.predecessorLinkID.map { id in
                            successors[id].map { $0.revision < value.revision } == true
                        } ?? true)
                  }) else { throw BackupExportServiceError.invalidAuthority }
            try AssetSuccessorLinkV1.validateAcyclic(Array(successors.values))
            for value in lifecycle.values {
                guard assetIDs.contains(value.record.assetID),
                      value.record.predecessorEventID.map({ id in
                          lifecycle[id].map {
                              $0.record.assetID == value.record.assetID
                                && $0.record.revision < value.record.revision
                          } == true
                      }) ?? true else { throw BackupExportServiceError.invalidAuthority }
                if value.kind == .classificationChangedRecorded {
                    guard let id = value.record.kindBindingEventID, let kind = kinds[id] else {
                        throw BackupExportServiceError.invalidAuthority
                    }
                    try value.validateAtomicReference(kindBinding: kind)
                } else if value.kind == .replacedRecorded {
                    guard let id = value.record.successorLinkID, let link = successors[id] else {
                        throw BackupExportServiceError.invalidAuthority
                    }
                    try value.validateAtomicReference(successorLink: link)
                }
            }
            let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
            guard scopes.allSatisfy({ value in
                siteIDs.contains(value.siteID) && value.subjects.allSatisfy { subject in
                    switch subject.kind {
                    case .site: return subject.subjectID == value.siteID
                    case .locationNode: return locationIDs.contains(subject.subjectID)
                    case .asset: return assetIDs.contains(subject.subjectID)
                    case .compositionComponent:
                        return subject.subjectID != zero
                            && subject.ownerAssetID.map(assetIDs.contains) == true
                    case .functionalRelationship:
                        guard subject.ownerAssetID == nil,
                              let relationship = subject.functionalRelationship,
                              relationship.relationshipID == subject.subjectID,
                              relationship.relationshipRevision == subject.revision,
                              relationship.descriptorReleaseID != zero,
                              relationship.descriptorReleaseRevision > 0,
                              AssetSemanticValidationV1.validPackageRelease(
                                  relationship.packageRelease
                              ),
                              AssetSemanticValidationV1.validPackageRelease(
                                  relationship.semanticCatalogRelease.packageRelease
                              ),
                              (try? relationship.semanticCatalogRelease.validate()) != nil,
                              AssetSemanticValidationV1.validIdentifier(
                                  relationship.semanticID, maximumBytes: 160
                              ) else { return false }
                        return true
                    }
                } && value.semanticBindings.allSatisfy { binding in
                    kinds[binding.kindBindingEventID].map {
                        $0.assetID == binding.assetID
                            && $0.revision == binding.kindBindingRevision
                            && $0.catalogRelease == binding.catalogRelease
                            && $0.semanticID == binding.semanticID
                    } == true
                }
            }) else { throw BackupExportServiceError.invalidAuthority }
        } catch let error as BackupExportServiceError {
            throw error
        } catch {
            throw BackupExportServiceError.invalidAuthority
        }
    }

    private func validateDeletionLedger(_ ledger: DeletionLedgerV2, rows: Rows) throws {
        try ledger.validate()
        guard ledger.entries.count <= DeletionLedgerV2.maximumEntryCount else {
            throw BackupExportServiceError.invalidAuthority
        }
        let deleted = Set(ledger.entries.map(\.identity))
        func identity(_ kind: DeletionRecordKindV2, _ id: UUID) throws
            -> DeletionIdentityV2 {
            try DeletionIdentityV2(kind: kind, id: id)
        }
        guard try rows.sites.allSatisfy({
                  !deleted.contains(try identity(.site, $0.id))
              }),
              try rows.assets.allSatisfy({
                  !deleted.contains(try identity(.asset, $0.id))
              }),
              try rows.records.allSatisfy({
                  !deleted.contains(try identity(.workflowRecord, $0.id))
              }),
              try rows.evidence.allSatisfy({
                  !deleted.contains(try identity(.evidenceFile, $0.id))
              }),
              try rows.issues.allSatisfy({
                  !deleted.contains(try identity(.issue, $0.id))
              }),
              try rows.reports.allSatisfy({
                  !deleted.contains(try identity(.report, $0.id))
              }) else {
            throw BackupExportServiceError.invalidAuthority
        }
        let byIdentity = Dictionary(
            uniqueKeysWithValues: ledger.entries.map { ($0.identity, $0) }
        )
        for packet in rows.packets {
            let packetIdentity = try identity(.packet, packet.id)
            if packet.currentRecordID == nil {
                guard packet.evaluationCounted,
                      let deletedAt = packet.contentDeletedAt,
                      byIdentity[packetIdentity]?.deletedAt == deletedAt else {
                    throw BackupExportServiceError.invalidAuthority
                }
            } else if byIdentity[packetIdentity] != nil {
                throw BackupExportServiceError.invalidAuthority
            }
        }
    }

    func workflowDTO(
        _ value: WorkflowRecord,
        observationAndTime: ObservationAndTimeRow
    ) -> V4BackupWorkflowRecordDTO {
        .init(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID, issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage, state: value.state,
            draftStepKey: value.draftStepKey, startedAt: value.startedAt,
            completedAt: value.completedAt, observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID, utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey, couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID,
            observationBasisV1Data: observationAndTime.observationBasisV1Data,
            temporalContextV1Data: observationAndTime.temporalContextV1Data
        )
    }
}

private extension BackupExportService {
    func makeFileWrapper(_ value: PreparedV4BackupV1) throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let manifestData = try BackupCanonicalEncoderV1().encodeManifest(value.manifest).data
        try add(
            V4BackupPackageMemberV1(
                path: "manifest.json", mimeType: "application/json", data: manifestData
            ),
            to: root
        )
        for member in value.members { try add(member, to: root) }
        return root
    }

    func add(_ member: V4BackupPackageMemberV1, to root: FileWrapper) throws {
        let components = member.path.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw BackupExportServiceError.invalidAuthority
        }
        var directory = root
        for component in components.dropLast() {
            if let existing = directory.fileWrappers?[component] {
                guard existing.isDirectory else {
                    throw BackupExportServiceError.invalidAuthority
                }
                directory = existing
            } else {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = component
                directory.addFileWrapper(child)
                directory = child
            }
        }
        let leaf = FileWrapper(regularFileWithContents: member.data)
        leaf.preferredFilename = components.last
        guard directory.fileWrappers?[components.last!] == nil else {
            throw BackupExportServiceError.invalidAuthority
        }
        directory.addFileWrapper(leaf)
    }

    func verifyPackage(_ value: PreparedV4BackupV1, at url: URL) throws {
        let expectedManifest = try BackupCanonicalEncoderV1().encodeManifest(
            value.manifest
        ).data
        let expected = Dictionary(uniqueKeysWithValues:
            [("manifest.json", expectedManifest)]
                + value.members.map { ($0.path, $0.data) }
        )
        let wrapper = try FileWrapper(url: url, options: [.immediate])
        var actual: [String: Data] = [:]
        try flatten(wrapper, prefix: "", into: &actual)
        guard actual == expected else {
            throw BackupExportServiceError.writeFailed
        }
    }

    func flatten(
        _ wrapper: FileWrapper,
        prefix: String,
        into output: inout [String: Data]
    ) throws {
        guard !wrapper.isSymbolicLink else {
            throw BackupExportServiceError.writeFailed
        }
        if wrapper.isRegularFile {
            guard !prefix.isEmpty, let data = wrapper.regularFileContents,
                  output[prefix] == nil else {
                throw BackupExportServiceError.writeFailed
            }
            output[prefix] = data
            return
        }
        guard wrapper.isDirectory, let children = wrapper.fileWrappers else {
            throw BackupExportServiceError.writeFailed
        }
        for (name, child) in children {
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                throw BackupExportServiceError.writeFailed
            }
            let childPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            try flatten(child, prefix: childPath, into: &output)
        }
    }

    func validRelativePath(_ value: String) -> Bool {
        value == value.precomposedStringWithCanonicalMapping
            && !value.hasPrefix("/")
            && value.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    enum LocalItemType { case directory, regular }

    nonisolated static func itemType(at url: URL) throws -> LocalItemType? {
        var information = stat()
        if Darwin.lstat(url.standardizedFileURL.path, &information) != 0 {
            if errno == ENOENT { return nil }
            throw BackupExportServiceError.destinationInvalid
        }
        switch information.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFREG:
            guard information.st_nlink == 1 else {
                throw BackupExportServiceError.destinationInvalid
            }
            return .regular
        default:
            throw BackupExportServiceError.destinationInvalid
        }
    }

    private nonisolated static func writeOwnedStagingSource(
        _ data: Data,
        to url: URL,
        expectedRootIdentity: StreamingArchiveRootIdentityV1,
        archiveLimits: StreamingArchiveLimitsV1
    ) throws -> OwnedStagingSource {
        let value = url.standardizedFileURL
        let stagingRoot = value.deletingLastPathComponent()
        guard value.lastPathComponent.hasPrefix(".backup-export-"),
              value.lastPathComponent.hasSuffix(".json"),
              Int64(data.count) <= archiveLimits.maximumUncompressedEntryByteCount,
              try Self.itemType(at: value) == nil else {
            throw BackupExportServiceError.invalidAuthority
        }
        let parent = Darwin.open(
            stagingRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parent >= 0 else {
            throw BackupExportServiceError.invalidGeneration
        }
        defer { _ = Darwin.close(parent) }
        var parentInformation = stat()
        guard Darwin.fstat(parent, &parentInformation) == 0,
              (parentInformation.st_mode & S_IFMT) == S_IFDIR,
              UInt64(parentInformation.st_dev) == expectedRootIdentity.device,
              UInt64(parentInformation.st_ino) == expectedRootIdentity.inode else {
            throw BackupExportServiceError.invalidGeneration
        }
        let descriptor = Darwin.openat(
            parent,
            value.lastPathComponent,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw BackupExportServiceError.writeFailed
        }
        var initialInformation = stat()
        guard Darwin.fstat(descriptor, &initialInformation) == 0 else {
            _ = Darwin.close(descriptor)
            throw BackupExportServiceError.cleanupFailed
        }
        let expectedDevice = initialInformation.st_dev
        let expectedInode = initialInformation.st_ino
        guard (initialInformation.st_mode & S_IFMT) == S_IFREG,
              initialInformation.st_nlink == 1,
              initialInformation.st_size == 0 else {
            _ = Darwin.close(descriptor)
            var current = stat()
            if Darwin.fstatat(
                parent,
                value.lastPathComponent,
                &current,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
               current.st_dev == expectedDevice,
               current.st_ino == expectedInode {
                _ = Darwin.unlinkat(parent, value.lastPathComponent, 0)
                _ = Darwin.fsync(parent)
            }
            throw BackupExportServiceError.writeFailed
        }
        var keep = false
        defer {
            _ = Darwin.close(descriptor)
            if !keep {
                var current = stat()
                if Darwin.fstatat(
                    parent,
                    value.lastPathComponent,
                    &current,
                    AT_SYMLINK_NOFOLLOW
                ) == 0,
                   (current.st_mode & S_IFMT) == S_IFREG,
                   current.st_nlink == 1,
                   current.st_dev == expectedDevice,
                   current.st_ino == expectedInode {
                    _ = Darwin.unlinkat(parent, value.lastPathComponent, 0)
                    _ = Darwin.fsync(parent)
                }
            }
        }
        try ProtectedFilePolicyV1.applyAndVerify(
            .stagingFile,
            relativePath: value.lastPathComponent,
            within: stagingRoot
        ) {
            let currentRootDescriptor = Darwin.open(
                stagingRoot.path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard currentRootDescriptor >= 0 else {
                throw BackupExportServiceError.sourceChanged
            }
            defer { _ = Darwin.close(currentRootDescriptor) }
            var currentRoot = stat()
            var current = stat()
            var currentPath = stat()
            guard Darwin.fstat(currentRootDescriptor, &currentRoot) == 0,
                  (currentRoot.st_mode & S_IFMT) == S_IFDIR,
                  UInt64(currentRoot.st_dev) == expectedRootIdentity.device,
                  UInt64(currentRoot.st_ino) == expectedRootIdentity.inode,
                  Darwin.fstat(descriptor, &current) == 0,
                  current.st_dev == expectedDevice,
                  current.st_ino == expectedInode,
                  current.st_nlink == 1,
                  current.st_size == 0,
                  Darwin.fstatat(
                    currentRootDescriptor,
                    value.lastPathComponent,
                    &currentPath,
                    AT_SYMLINK_NOFOLLOW
                  ) == 0,
                  (currentPath.st_mode & S_IFMT) == S_IFREG,
                  currentPath.st_dev == expectedDevice,
                  currentPath.st_ino == expectedInode,
                  currentPath.st_nlink == 1,
                  currentPath.st_size == 0 else {
                throw BackupExportServiceError.sourceChanged
            }
        }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let requested = min(
                    archiveLimits.bufferByteCount,
                    raw.count - offset
                )
                var count: Int
                repeat {
                    count = Darwin.write(
                        descriptor,
                        raw.baseAddress?.advanced(by: offset),
                        requested
                    )
                } while count < 0 && errno == EINTR
                guard count > 0 else {
                    throw BackupExportServiceError.writeFailed
                }
                offset += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw BackupExportServiceError.writeFailed
        }
        var information = stat()
        var pathInformation = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_dev == expectedDevice,
              information.st_ino == expectedInode,
              information.st_size == Int64(data.count),
              Darwin.fstatat(
                parent,
                value.lastPathComponent,
                &pathInformation,
                AT_SYMLINK_NOFOLLOW
              ) == 0,
              pathInformation.st_dev == expectedDevice,
              pathInformation.st_ino == expectedInode,
              pathInformation.st_nlink == 1,
              pathInformation.st_size == Int64(data.count) else {
            throw BackupExportServiceError.writeFailed
        }
        guard Darwin.fsync(parent) == 0 else {
            throw BackupExportServiceError.writeFailed
        }
        keep = true
        return OwnedStagingSource(
            url: value,
            device: UInt64(expectedDevice),
            inode: UInt64(expectedInode)
        )
    }

    private nonisolated static func cleanupOwnedStagingSources(
        _ sources: [OwnedStagingSource],
        within stagingRootURL: URL,
        directoryDescriptor: Int32,
        expectedRootIdentity: StreamingArchiveRootIdentityV1
    ) throws {
        let root = stagingRootURL.standardizedFileURL
        var rootInformation = stat()
        guard Darwin.fstat(directoryDescriptor, &rootInformation) == 0,
              (rootInformation.st_mode & S_IFMT) == S_IFDIR,
              UInt64(rootInformation.st_dev) == expectedRootIdentity.device,
              UInt64(rootInformation.st_ino) == expectedRootIdentity.inode else {
            throw BackupExportServiceError.cleanupFailed
        }
        for source in sources.reversed() {
            let value = source.url.standardizedFileURL
            let name = value.lastPathComponent
            guard value.deletingLastPathComponent() == root,
                  name.hasPrefix(".backup-export-"),
                  name.hasSuffix(".json") else {
                throw BackupExportServiceError.cleanupFailed
            }
            var information = stat()
            if Darwin.fstatat(
                directoryDescriptor,
                name,
                &information,
                AT_SYMLINK_NOFOLLOW
            ) != 0 {
                guard errno == ENOENT else {
                    throw BackupExportServiceError.cleanupFailed
                }
                continue
            }
            guard (information.st_mode & S_IFMT) == S_IFREG,
                  information.st_nlink == 1,
                  UInt64(information.st_dev) == source.device,
                  UInt64(information.st_ino) == source.inode,
                  Darwin.unlinkat(directoryDescriptor, name, 0) == 0 else {
                throw BackupExportServiceError.cleanupFailed
            }
        }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw BackupExportServiceError.cleanupFailed
        }
    }

    nonisolated static func removeOwnedPublishedArchive(
        _ receipt: StreamingArchiveWriteReceiptV1,
        within destinationDirectoryURL: URL,
        beforePrivateClaim: (() throws -> Void)? = nil
    ) throws {
        let value = receipt.archiveURL.standardizedFileURL
        let parentURL = destinationDirectoryURL.standardizedFileURL
        guard value.deletingLastPathComponent() == parentURL,
              value.lastPathComponent == "AssetRounds.fieldrecordbackup" else {
            throw BackupExportServiceError.cleanupFailed
        }
        let parent = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw BackupExportServiceError.cleanupFailed }
        defer { _ = Darwin.close(parent) }
        var directory = stat()
        var file = stat()
        let expected = receipt.publicationSnapshot
        guard Darwin.fstat(parent, &directory) == 0,
              (directory.st_mode & S_IFMT) == S_IFDIR,
              UInt64(directory.st_dev) == receipt.publicationParentIdentity.device,
              UInt64(directory.st_ino) == receipt.publicationParentIdentity.inode,
              Darwin.fstatat(parent, value.lastPathComponent, &file, AT_SYMLINK_NOFOLLOW) == 0,
              (file.st_mode & S_IFMT) == S_IFREG, file.st_nlink == 1,
              UInt64(file.st_dev) == expected.device, UInt64(file.st_ino) == expected.inode,
              Int64(file.st_size) == receipt.archiveByteCount,
              Int64(file.st_size) == expected.byteCount,
              Int64(file.st_mtimespec.tv_sec) == expected.modifiedSeconds,
              Int64(file.st_mtimespec.tv_nsec) == expected.modifiedNanoseconds,
              Int64(file.st_ctimespec.tv_sec) == expected.changedSeconds,
              Int64(file.st_ctimespec.tv_nsec) == expected.changedNanoseconds else {
            throw BackupExportServiceError.cleanupFailed
        }
        try beforePrivateClaim?()
        let operationName = ".backup-export-cleanup-\(UUID().uuidString.lowercased())"
        guard Darwin.mkdirat(parent, operationName, mode_t(0o700)) == 0 else {
            throw BackupExportServiceError.cleanupFailed
        }
        let operation = Darwin.openat(parent, operationName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard operation >= 0 else {
            // Without a retained identity we cannot claim or remove this name.
            throw BackupExportServiceError.cleanupFailed
        }
        defer { Darwin.close(operation) }
        var privateDirectory = stat()
        guard Darwin.fstat(operation, &privateDirectory) == 0,
              (privateDirectory.st_mode & S_IFMT) == S_IFDIR else {
            throw BackupExportServiceError.cleanupFailed
        }
        func removeEmptyOperation() throws {
            var named = stat()
            guard Darwin.fstatat(parent, operationName, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_dev == privateDirectory.st_dev, named.st_ino == privateDirectory.st_ino,
                  (named.st_mode & S_IFMT) == S_IFDIR,
                  Darwin.unlinkat(parent, operationName, AT_REMOVEDIR) == 0,
                  Darwin.fsync(parent) == 0 else { throw BackupExportServiceError.cleanupFailed }
        }
        // Claim the name atomically inside an exclusive private directory.
        // The moved inode, not a prior stat of the public name, decides deletion.
        guard Darwin.renameatx_np(parent, value.lastPathComponent, operation, "archive", UInt32(RENAME_EXCL)) == 0 else {
            try? removeEmptyOperation()
            throw BackupExportServiceError.cleanupFailed
        }
        do {
            let descriptor = Darwin.openat(operation, "archive", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard descriptor >= 0 else { throw BackupExportServiceError.cleanupFailed }
            defer { Darwin.close(descriptor) }
            var moved = stat()
            guard Darwin.fstat(descriptor, &moved) == 0,
                  (moved.st_mode & S_IFMT) == S_IFREG, moved.st_nlink == 1,
                  UInt64(moved.st_dev) == expected.device, UInt64(moved.st_ino) == expected.inode,
                  Int64(moved.st_size) == receipt.archiveByteCount,
                  Int64(moved.st_mtimespec.tv_sec) == expected.modifiedSeconds,
                  Int64(moved.st_mtimespec.tv_nsec) == expected.modifiedNanoseconds else {
                throw BackupExportServiceError.cleanupFailed
            }
            var hasher = SHA256()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            var total: Int64 = 0
            while total < receipt.archiveByteCount {
                let requested = Int(min(Int64(buffer.count), receipt.archiveByteCount - total))
                var count: Int
                repeat { count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, requested) } }
                while count < 0 && errno == EINTR
                guard count > 0 else { throw BackupExportServiceError.cleanupFailed }
                buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
                total += Int64(count)
            }
            var after = stat(), named = stat()
            guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == receipt.archiveSHA256,
                  Darwin.fstat(descriptor, &after) == 0,
                  Darwin.fstatat(operation, "archive", &named, AT_SYMLINK_NOFOLLOW) == 0,
                  after.st_dev == moved.st_dev, after.st_ino == moved.st_ino, after.st_nlink == 1,
                  after.st_size == moved.st_size, after.st_mtimespec.tv_sec == moved.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == moved.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == moved.st_ctimespec.tv_sec,
                  after.st_ctimespec.tv_nsec == moved.st_ctimespec.tv_nsec,
                  named.st_dev == moved.st_dev, named.st_ino == moved.st_ino, named.st_nlink == 1,
                  Darwin.fsync(operation) == 0, Darwin.fsync(parent) == 0 else {
                throw BackupExportServiceError.cleanupFailed
            }
            guard Darwin.unlinkat(operation, "archive", 0) == 0, Darwin.fsync(operation) == 0 else {
                throw BackupExportServiceError.cleanupFailed
            }
        } catch {
            // Never overwrite a newly occupied public destination. If restoring
            // the claimed file is impossible, retain it in the private directory.
            if Darwin.renameatx_np(operation, "archive", parent, value.lastPathComponent, UInt32(RENAME_EXCL)) == 0 {
                _ = Darwin.fsync(operation); _ = Darwin.fsync(parent)
                try? removeEmptyOperation()
            }
            throw BackupExportServiceError.cleanupFailed
        }
        try removeEmptyOperation()
    }

    nonisolated static func mapStreamingExportError(_ error: Error) -> BackupExportServiceError {
        if error is GenerationLeaseRegistryFailureV1 {
            return .generationLeaseLost
        }
        if let typed = error as? BackupExportServiceError { return typed }
        if let storage = error as? StoragePreflightError {
            if case .insufficientCapacity = storage { return .insufficientStorage }
            return .writeFailed
        }
        guard let failure = error as? StreamingArchiveFailureV1 else {
            return .writeFailed
        }
        switch failure {
        case .cancelled:
            return .cancelled
        case .insufficientStorage:
            return .insufficientStorage
        case .sourceChanged, .contentMismatch:
            return .sourceChanged
        case .cleanupFailed:
            return .cleanupFailed
        case .destinationExists:
            return .destinationExists
        default:
            return .writeFailed
        }
    }

    func validateGenerationLease() throws {
        do {
            try generationLeaseValidation()
        } catch {
            throw BackupExportServiceError.generationLeaseLost
        }
    }

    nonisolated static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }

    func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    nonisolated static func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }

    func dtoOrder<T>(_ lhs: T, _ rhs: T) -> Bool where T: Identifiable, T.ID == UUID {
        Self.uuid(lhs.id) < Self.uuid(rhs.id)
    }

    func requireAcyclic<T>(
        _ values: [T],
        id: KeyPath<T, UUID>,
        next: KeyPath<T, UUID?>
    ) throws {
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0[keyPath: id], $0) })
        for value in values {
            var seen = Set<UUID>()
            var cursor: UUID? = value[keyPath: id]
            while let current = cursor {
                guard seen.insert(current).inserted, let row = byID[current] else {
                    throw BackupExportServiceError.invalidAuthority
                }
                cursor = row[keyPath: next]
            }
        }
    }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-backup
enum C52ServiceRequestBackupExportBoundaryV1 {
    static let recordsSchemaVersion = 38
    static let exportsAcceptedSourceBytes = true
    static let exportsCanonicalHistory = true
    static let exportsRawCapability = false
    static let exportsDerivedDuplicateProjection = false
}

enum C53ServiceReliabilityBackupExportBoundaryV1 {
    static let recordsSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.recordsSchemaVersion
    static let persistentSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.targetPersistentSchemaVersion
    static let exportsAllSevenSourceFamilies = true
    static let exportsMutationHistoryReceipts = true
    static let exportsDerivedMetricProjection = false
    static let exportsRawCapability = false
    static let preservesReliabilityIdentityEpoch = true
}

enum C55PartsStockBackupExportBoundaryV1 {
    static let recordsSchemaVersion = C55PartsStockBackupEnrollmentV1.recordsSchemaVersion
    static let persistentSchemaVersion = C55PartsStockBackupEnrollmentV1.persistentSchemaVersion
    static let exportsOneCanonicalSnapshot = true
    static let exportsAllSevenDurableFamilies = true
}

#if DEBUG
extension BackupExportService {
    nonisolated static func removeOwnedPublishedArchiveForTesting(
        receipt: StreamingArchiveWriteReceiptV1,
        within destinationDirectoryURL: URL,
        beforePrivateClaim: (() throws -> Void)? = nil
    ) throws {
        try removeOwnedPublishedArchive(receipt, within: destinationDirectoryURL,
            beforePrivateClaim: beforePrivateClaim)
    }
}
#endif

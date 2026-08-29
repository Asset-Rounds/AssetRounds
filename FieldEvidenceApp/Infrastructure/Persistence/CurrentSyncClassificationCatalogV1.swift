import Foundation
import SwiftData

enum CurrentFilesystemBackupDispositionV1: String, Equatable, Sendable {
    case included = "INCLUDED"
    case excluded = "EXCLUDED"
    case notApplicable = "NOT_APPLICABLE"
}

enum CurrentRebuildDispositionV1: String, Equatable, Sendable {
    case rebuildFromCanonicalDependencies = "REBUILD_FROM_CANONICAL_DEPENDENCIES"
    case unavailableAtThisHead = "UNAVAILABLE_AT_THIS_HEAD"
    case notApplicable = "NOT_APPLICABLE"
}

enum CurrentReplayDispositionV1: String, Equatable, Sendable {
    case immutableMutationHistory = "IMMUTABLE_MUTATION_HISTORY"
    case recoveryStateMachine = "RECOVERY_STATE_MACHINE"
    case notApplicable = "NOT_APPLICABLE"
}

struct CurrentSyncLifecycleRouteV1: Equatable, Sendable {
    let subject: SyncSubjectIdentityV1
    let filesystemBackup: CurrentFilesystemBackupDispositionV1
    let semanticBackup: ReplicationBackupDispositionV1
    let portableExport: ReplicationExportDispositionV1
    let deletion: ReplicationDeleteDispositionV1
    let erase: ReplicationEraseDispositionV1
    let rebuild: CurrentRebuildDispositionV1
    let replay: CurrentReplayDispositionV1
}

enum CurrentRepresentationAuthorityV1: String, Equatable, Sendable {
    case canonicalRow = "CANONICAL_ROW"
    case derivedPersistedRow = "DERIVED_PERSISTED_ROW"
    case localRecoveryRow = "LOCAL_RECOVERY_ROW"
    case portableProjection = "PORTABLE_PROJECTION"
    case persistedDeviceStore = "PERSISTED_DEVICE_STORE"
    case nonpersistentView = "NONPERSISTENT_VIEW"
}

struct CurrentRepresentationRuleV1: Equatable, Sendable {
    let source: SyncSubjectIdentityV1
    let representation: SyncSubjectIdentityV1
    let sourceAuthority: CurrentRepresentationAuthorityV1
    let representationAuthority: CurrentRepresentationAuthorityV1
}

enum CurrentSyncClassificationCatalogFailureV1: Error, Equatable {
    case invalidInventory
    case invalidBaseline
    case invalidLifecycleRoute
    case unexpectedSearchImplementation
    case unexpectedSecretOrKeychain
}

/// Repository-derived current-kind catalog for the C03 domain registry.
///
/// `SyncClassificationRegistryV1` remains the closed domain baseline. This
/// adapter proves that baseline is an exact subset of every kind shipped by
/// the current repository and adds infrastructure-only lifecycle routes that
/// do not belong in the transport-neutral domain contract.
struct CurrentSyncClassificationCatalogV1: Sendable {
    static let persistentModelNames = [
        "Asset", "DeletionLedgerRow", "EntityMutationRevisionRow", "EvidenceFile",
        "Issue", "MutationQuarantineRow", "MutationReceiptRow", "ObservationAndTimeRow", "Packet",
        "PersistentSchemaReleaseMarker", "Report", "Site", "WorkflowRecord",
        "WorkspaceMutationStateRow",
    ]

    /// Frozen V5 public baseline remains available to sealed Kernel V4 and
    /// prior tooling. Runtime V6 consumers use this additive inventory.
    static let v6PersistentModelNames = [
        "AssetCompositionEdgeRow", "AssetCompositionEventRow",
        "AssetPlacementEventRow", "LocationHierarchyEventRow",
        "LocationMigrationReceiptRow", "LocationNodeRow",
    ]
    static let v7PersistentModelNames = ["SavedSmartView"]
    static let v8PersistentModelNames = ["RequirementAssuranceRow"]
    static let v9PersistentModelNames = [
        "ActorSnapshotRow", "QualificationSnapshotRow", "ServicePartyRow",
        "SignoffSnapshotRow", "SitePartyRoleEventRow",
    ]
    static let v10PersistentModelNames = [
        "AssetKindBindingEventRow", "AssetLifecycleEventRow",
        "AssetProductIdentityRow", "AssetSuccessorLinkRow",
        "AssetWorkflowCapabilityBindingEventRow", "WorkSubjectScopeSnapshotRow",
    ]
    static let v11PersistentModelNames = [
        "ApplicabilityContextSnapshotRow", "AssessmentScopeSnapshotRow",
        "AuthoritySourceReleaseRow", "DerivedFactEvaluatorDescriptorRow",
        "DerivedFactProvenanceRow", "FindingClassificationBindingRow",
        "MeasurementProtocolReleaseRow", "RequirementBasisBindingRow",
        "SeverityScaleReleaseRow",
    ]
    static let v12PersistentModelNames = [
        "AssetFunctionalRelationshipEventRow", "FunctionalRelationshipTypeDescriptorRow",
    ]
    static let v13PersistentModelNames=["AssuranceManifestRow","AttestationRow","ClaimEvidenceLinkRow","EvidenceVisibilityRow"]
    static let v14PersistentModelNames=["ChangeRequestRow","CorrectiveActionEventRow","CorrectiveActionPolicyRow","InspectionReviewTransitionRow","ReviewDispositionRow"]
    static let v15PersistentModelNames=["WorkHandoffRow","WorkItemClaimRow","WorkLeaseRow","WorkPacketManifestRow","WorkReleaseRow"]
    static let v16PersistentModelNames=["AttachmentStagingItemRow","DraftCommitReceiptRow","DraftCommitSagaRow","DraftContentReservationRow","DraftDiscardReceiptRow","FieldDraftCheckpointRow"]
    static let v17PersistentModelNames=["ActivePackageRegistryPointerRow","PackagePromotionReceiptRow","PackageSandboxRunRow","PromotedPackageReleaseRow"]
    static let v18PersistentModelNames=["CalibrationStatusSnapshotRow","InstrumentReferenceRow","MeasurementCaptureRow","MeasurementQualityAssessmentRow","MeasurementSeriesRow"]
    static let v19PersistentModelNames=["PrivacyRegionRow","PrivacyReviewReceiptRow","PrivacyTransformManifestRow","PrivacyTransformPolicyRow"]
    static let v20PersistentModelNames=["ClientCapabilityAdmissionDecisionRow","ClientCapabilityProfileRow","PackageLifecycleDispositionRow","PackageLifecyclePolicyRow"]
    static let v21PersistentModelNames=["RecoverabilityVerificationReceiptRow"]
    static let v22PersistentModelNames=["FieldReferenceBindingRow","FieldReferenceReleaseRow"]
    static let v23PersistentModelNames=["AccessibleDocumentAssessmentReceiptRow"]
    static let v24PersistentModelNames=["SurveyDefinitionIdentityRow","SurveyDefinitionReleaseRow"]
    static let v25PersistentModelNames=["FactCaptureRow","ProvisionalSubjectRow","SubjectPromotionReceiptRow","SurveyPublicationSnapshotRow","SurveySessionRow"]
    static let v26PersistentModelNames=["AssetLocatorRow","LocatorBindingReceiptRow"]
    static let v27PersistentModelNames=["OccurrenceHistoryEventRow","ScheduleDefinitionReleaseRow"]
    static let v28PersistentModelNames=["PlanDocumentRow","PlanPlacementRow","PlanRevisionRow","RebaseReceiptRow"]
    static let v29PersistentModelNames=["AssetPoseEventRow","SpatialAnchorObservationRow"]
    static let v30PersistentModelNames=["EvidenceContextRow","PairedObservationLinkRow"]
    static let v31PersistentModelNames=["LightingSystemRow","LightingObservationRow","LightingIssueRow","MeasurementPlanRow","LightingClaimStateRow"]
    static let v32PersistentModelNames=["AssistanceAcceptanceReceiptRow"]
    static let v33PersistentModelNames=["TemporalEvidenceClipRow","TimecodedEvidenceAnchorRow"]
    static let v34PersistentModelNames=["AcceptedLabelGenerationSnapshotRow"]
    static let activePersistentModelNames =
        (persistentModelNames + v6PersistentModelNames + v7PersistentModelNames
            + v8PersistentModelNames + v9PersistentModelNames + v10PersistentModelNames
            + v11PersistentModelNames + v12PersistentModelNames + v13PersistentModelNames + v14PersistentModelNames + v15PersistentModelNames + v16PersistentModelNames + v17PersistentModelNames + v18PersistentModelNames + v19PersistentModelNames + v20PersistentModelNames + v21PersistentModelNames + v22PersistentModelNames + v23PersistentModelNames + v24PersistentModelNames + v25PersistentModelNames + v26PersistentModelNames + v27PersistentModelNames + v28PersistentModelNames + v29PersistentModelNames + v30PersistentModelNames + v31PersistentModelNames + v32PersistentModelNames + v33PersistentModelNames + v34PersistentModelNames).sorted()

    static let ownedFileClassNames = [
        "cache", "commerceEntitlementCache", "database", "databaseSHM", "databaseWAL",
        "diagnostics", "durableDirectory", "generationLeaseControl",
        "generationLeaseControlTemporary", "generationLeaseDirectory",
        "generationLeaseOwnerLock", "generationPointer", "generationPointerTemporary",
        "journal", "journalTemporary", "mediaOriginal", "mediaThumbnail", "reportPDF",
        "reportSnapshot", "restoreStaging", "scratch", "stagingDirectory", "stagingFile",
        "temporaryFile", "searchIndex",
    ]

    static let portableContentProjectionNames = [
        "DeletionLedgerV2",
        "MutationHistorySnapshotV1",
        "ObservationBasisV1",
        "ReportSnapshotV1",
        "StreamingArchiveIndexV1",
        "TemporalContextV1",
        "V4BackupAssetDTO",
        "V4BackupEvidenceFileDTO",
        "V4BackupIssueDTO",
        "V4BackupManifestV1",
        "V4BackupPacketDTO",
        "V4BackupRecordsV1",
        "V4BackupReportDTO",
        "V4BackupSiteDTO",
        "V4BackupWorkflowRecordDTO",
        "V5BackupLocationRecordV1",
        "SavedSmartViewDescriptorV1",
        "RequirementAssuranceSnapshotV1",
        "RequirementEvaluationV1",
        "CompletionDecisionV1",
        "IntegrityFindingV1",
        "ServicePartyReferenceV1",
        "SitePartyRoleEventV1",
        "ActorSnapshotV1",
        "QualificationSnapshotV1",
        "SignoffSnapshotV1",
        "AssetSemanticCatalogReleaseV1",
        "AssetKindDefinitionV1",
        "AssetKindBindingEventV1",
        "AssetWorkflowCapabilityBindingEventV1",
        "AssetProductIdentityV1",
        "AssetLifecycleEventV1",
        "AssetSuccessorLinkV1",
        "WorkSubjectScopeSnapshotV1",
        "AuthoritySourceReleaseV1", "RequirementBasisBindingV1",
        "ApplicabilityContextSnapshotV1", "AssessmentScopeSnapshotV1",
        "SeverityScaleReleaseV1", "FindingClassificationBindingV1",
        "MeasurementProtocolReleaseV1", "DerivedFactEvaluatorDescriptorV1",
        "DerivedFactProvenanceV1",
        "FunctionalRelationshipTypeDescriptorV1",
        "AssetFunctionalRelationshipEventV1",
        "CurrentFunctionalRelationshipProjectionV1",
        "FunctionalRelationshipDispositionPreviewV1",
        "CompletedFunctionalRelationshipSnapshotV1",
        "EvidenceVisibilityV1","ClaimEvidenceLinkV1","AssuranceProjectionPreviewV1","AssuranceManifestV1","AttestationV1",
        "InspectionReviewTransitionV1","ReviewDispositionV1","ChangeRequestV1","CorrectiveActionPolicyV1","CorrectiveActionEventV1","InspectionReviewProjectionV1","CorrectiveActionProjectionV1",
        "WorkPacketManifestV1","WorkItemClaimV1","WorkLeaseV1","WorkReleaseV1","WorkHandoffV1","WorkPacketProjectionV1",
        "FieldDraftCheckpointV1","AttachmentStagingItemV1","DraftCommitSagaV1","DraftContentReservationV1","DraftCommitReceiptV1","DraftDiscardReceiptV1","DraftRecoveryProjectionV1",
        "PromotedPackageReleaseV1","PackageSandboxRunV1","PackagePromotionReceiptV1","ActivePackageRegistryPointerV1","PackageEvolutionLifecycleClosureV1","PackageSemanticDiffV1","DraftUpgradePlanV1",
        "InstrumentReferenceV1","CalibrationStatusSnapshotV1","MeasurementCaptureV1","MeasurementSeriesV1","MeasurementQualityAssessmentV1",
        "PrivacyTransformPolicyV1","PrivacyRegionV1","PrivacyTransformManifestV1","PrivacyReviewReceiptV1","PrivacyProjectionV1","PrivacyTransformLifecycleClosureV1",
        "ClientCapabilityProfileV1","ClientCapabilityAdmissionDecisionV1","PackageLifecyclePolicyV1","PackageLifecycleDispositionV1","ClientCapabilityAdmissionEvaluatorV1","ClientCapabilityLifecycleClosureV1",
        "RecoverabilityVerificationReceiptV1",
        "FieldReferenceReleaseV1","FieldReferenceBindingV1",
        "AccessibleDocumentAssessmentReceiptV1",
        "SurveyDefinitionIdentityV1","SurveyDefinitionReleaseV1",
        "SurveySessionV1","FactCaptureV1","ProvisionalSubjectV1","SubjectPromotionReceiptV1","SurveyPublicationSnapshotV1","SurveySessionLifecycleClosureV1",
        "AssetLocatorV1","LocatorBindingReceiptV1","AssetLocatorLifecycleClosureV1",
        "ScheduleDefinitionReleaseV1","OccurrenceHistoryEventV1",
        "AssistanceAcceptanceReceiptV1",
        "TemporalEvidenceClipV1","TimecodedEvidenceAnchorV1",
    ]

    static let derivedIndexNames = [
        "ReportHistoryIndexValue",
        "SearchIndexProjectionV1",
        "reportHistoryChronology",
    ]

    /// C17's provider-neutral event projection, registry, cache, checkpoint,
    /// and conformance consumer are disposable derived state.  They are
    /// intentionally classified as projections here so the source of truth
    /// remains accepted mutation receipts and journal history.
    static let c17IntegrationProjectionNames = [
        "IntegrationConformanceConsumerV1",
        "IntegrationContractRegistryV1",
        "IntegrationEventProjectionV1",
        "IntegrationEventV1",
        "IntegrationProjectionCheckpointStoreV1",
        "ProjectionCheckpointV1",
    ]

    static let derivedProjectionNames = [
        "EntityMutationRevisionSemanticV1",
        "MutationQuarantineSemanticV1",
        "MutationReceiptSemanticV1",
        "ObservationAndTimeMigrationReceiptV1",
        "ObservationAndTimeSemanticV1",
        "StoreSemanticEnvelopeV3",
        "StoreSemanticEnvelopeV4",
        "StoreSemanticEnvelopeV5",
        "StoreSemanticEnvelopeV6",
        "StoreSemanticEnvelopeV7",
        "StoreSemanticEnvelopeV8",
        "StoreSemanticEnvelopeV9",
        "StoreSemanticEnvelopeV10",
        "StoreSemanticEnvelopeV11",
        "StoreSemanticEnvelopeV12",
        "StoreSemanticEnvelopeV13",
        "StoreSemanticEnvelopeV14",
        "StoreSemanticEnvelopeV15",
        "StoreSemanticEnvelopeV16",
        "StoreSemanticEnvelopeV17",
        "StoreSemanticEnvelopeV18",
        "StoreSemanticEnvelopeV19",
        "StoreSemanticEnvelopeV20",
        "StoreSemanticEnvelopeV21",
        "RecoverabilityVerificationStagingV1",
        "RecoverabilityFreshnessProjectionV1",
        "RecoverabilityVerificationLifecycleV1",
        "StoreSemanticEnvelopeV22","FieldReferenceOfflineReadinessV1","FieldReferencePackLifecycleV1",
        "StoreSemanticEnvelopeV23","AccessibleDocumentSemanticTreeV1","AccessibleDocumentLifecycleV1",
        "StoreSemanticEnvelopeV24","SurveyDefinitionSemanticDiffV1","SurveyDefinitionAdoptionPreviewV1","SurveyTemplateQuarantineAssessmentV1",
        "StoreSemanticEnvelopeV25",
        "StoreSemanticEnvelopeV26","LocatorBindingPreviewV1","LocatorResolutionV1",
        "StoreSemanticEnvelopeV27","OccurrenceGenerationPlanV1","DueQueueProjectionV1","ReminderProjectionV1",
        "StoreSemanticEnvelopeV28","PlanDocumentV1","PlanRevisionV1","SpatialReferenceFrameV1","PlanPlacementV1","RebasePreviewV1","RebaseReceiptV1",
        "StoreSemanticEnvelopeV29","PoseAxisDescriptorRegistryV1","AssetPoseCurrentTipV1","CompletedPlacementPoseSnapshotV1",
        "StoreSemanticEnvelopeV30","EvidenceContextV1","PairedObservationLinkV1","StoreSemanticEnvelopeV31","LightingTopologyV1","LightingDuePreviewV1","StoreSemanticEnvelopeV32","StoreSemanticEnvelopeV33","StoreSemanticEnvelopeV34",
        "WorkspaceMutationStateSemanticV1",
        "entityMutationRevision",
        "workspaceMutationState",
    ] + c17IntegrationProjectionNames

    /// Proposals are workspace-scoped scratch only. They are declared so the
    /// lifecycle catalog can prove their absence from schema, backup, export,
    /// search, sync, journal history, diagnostics, and durable rejection data.
    static let ephemeralProjectionNames = ["AssistanceProposalV1", "AssistanceCapabilityScratchV1", "TemporalEvidenceCaptureScratchV1"]

    static let journalRecoveryNames = [
        "CurrentGenerationPointerV2",
        "CurrentGenerationPointerV3",
        "DeletionIntentV1",
        "EraseIntentV1",
        "ErasePreparationV2",
        "FinalizationIntentV1",
        "MutationEnvelopeV1",
        "MutationHistoryQuarantineRecordV1",
        "MutationReceiptV1",
        "SurveyDefinitionLifecycleEventV1",
        "TemporalEvidenceDerivativeV1",
        "TemporalEvidenceRetentionEventV1",
        "PreparedMigrationEnvelopeV1",
        "RestoreIntentV1",
        "ReversalBasisV1",
        "SemanticReversalReceiptV1",
        "StoreGenerationManifestV1",
        "StoreMigrationJournalV1",
        "deletionIntent",
        "eraseIntent",
        "finalizationIntent",
        "mutationReceipt",
        "restoreIntent",
        "storeMigration",
    ]

    static let diagnosticNames = [
        "DiagnosticExportV1",
        "DiagnosticsLogEvent",
        "DiagnosticsV1",
        "DeviceOperationalSupportSnapshotV2",
        "DeviceOperationalSupportStoreV1",
        "DeviceOperationalSupportStoreV2",
        "LaunchTimeMillisecondsV1",
        "MetricKitSummaryV1",
        "OperationalFailureV1",
        "PurchaseResultHistogram",
        "ScratchDataLeaseStoreV1",
        "SystemHealthDiagnosticsV1",
        "diagnosticCounters",
    ]

    static let declaredSearchImplementationPresent = true

    /// The accepted portable-secret inventory is explicitly empty and the
    /// application has no Keychain-backed secret at this head.
    static let secretNames: [String] = []
    static let declaredKeychainUsage = false

    /// Canonical mutation rows and their portable snapshot are distinct
    /// representations. Export never promotes the projection into row truth.
    static var mutationHistoryRepresentationRules: [CurrentRepresentationRuleV1] {
        get throws {
            let projection = try subject(
                category: .projection,
                name: "MutationHistorySnapshotV1"
            )
            return try [
                ("EntityMutationRevisionRow", CurrentRepresentationAuthorityV1.derivedPersistedRow),
                ("MutationQuarantineRow", CurrentRepresentationAuthorityV1.localRecoveryRow),
                ("MutationReceiptRow", CurrentRepresentationAuthorityV1.canonicalRow),
                ("WorkspaceMutationStateRow", CurrentRepresentationAuthorityV1.derivedPersistedRow),
            ].map { name, authority in
                CurrentRepresentationRuleV1(
                    source: try subject(category: .persistentModel, name: name),
                    representation: projection,
                    sourceAuthority: authority,
                    representationAuthority: .portableProjection
                )
            }
        }
    }

    /// The V1 name is a legacy schema/interface declaration. V2 is the sole
    /// persisted operational-support store kind; bounded snapshots, failures,
    /// exports, counters, and summaries are nonpersistent views.
    static var diagnosticRepresentationRules: [CurrentRepresentationRuleV1] {
        get throws {
            let store = try subject(
                category: .diagnostic,
                name: "DeviceOperationalSupportStoreV2"
            )
            return try diagnosticNames
                .filter { $0 != "DeviceOperationalSupportStoreV2"
                          && $0 != "ScratchDataLeaseStoreV1" }
                .map {
                    CurrentRepresentationRuleV1(
                        source: store,
                        representation: try subject(category: .diagnostic, name: $0),
                        sourceAuthority: .persistedDeviceStore,
                        representationAuthority: .nonpersistentView
                    )
                }
        }
    }

    let registrations: [SyncClassificationRegistrationV1]
    let lifecycleRoutes: [CurrentSyncLifecycleRouteV1]
    let persistentModelSubjects: [SyncSubjectIdentityV1]
    let ownedFileClassSubjects: [SyncSubjectIdentityV1]
    let portableContentProjectionSubjects: [SyncSubjectIdentityV1]
    let derivedIndexProjectionSubjects: [SyncSubjectIdentityV1]
    let journalRecoverySubjects: [SyncSubjectIdentityV1]
    let diagnosticSubjects: [SyncSubjectIdentityV1]
    let secretSubjects: [SyncSubjectIdentityV1]
    let searchImplementationPresent: Bool
    let keychainUsageDeclared: Bool

    static var current: CurrentSyncClassificationCatalogV1 {
        get throws {
            let baseline = try SyncClassificationRegistryV1.registrations
            let additions = try makeAdditionalRegistrations()
            let registrations = (baseline + additions).sorted {
                $0.subject.canonicalKey < $1.subject.canonicalKey
            }
            let routes = try registrations.map(makeLifecycleRoute).sorted {
                $0.subject.canonicalKey < $1.subject.canonicalKey
            }
            let persistentSubjects = try subjects(
                category: .persistentModel,
                names: activePersistentModelNames
            )
            let ownedFileSubjects = try subjects(
                category: .ownedFileClass,
                names: ownedFileClassNames
            )
            let portableSubjects = try subjects(
                category: .projection,
                names: portableContentProjectionNames
            )
            let derivedSubjects = try subjects(
                category: .index,
                names: derivedIndexNames
            ) + (try subjects(
                category: .projection,
                names: derivedProjectionNames
            )) + (try subjects(
                category: .projection,
                names: ephemeralProjectionNames
            ))
            let journalSubjects = try subjects(
                category: .journal,
                names: journalRecoveryNames
            )
            let diagnostics = try subjects(
                category: .diagnostic,
                names: diagnosticNames
            )
            let secrets = try subjects(category: .secret, names: secretNames)
            return try CurrentSyncClassificationCatalogV1(
                registrations: registrations,
                lifecycleRoutes: routes,
                persistentModelSubjects: persistentSubjects,
                ownedFileClassSubjects: ownedFileSubjects,
                portableContentProjectionSubjects: portableSubjects,
                derivedIndexProjectionSubjects: derivedSubjects,
                journalRecoverySubjects: journalSubjects,
                diagnosticSubjects: diagnostics,
                secretSubjects: secrets,
                searchImplementationPresent: Self.declaredSearchImplementationPresent,
                keychainUsageDeclared: Self.declaredKeychainUsage
            )
        }
    }

    init(
        registrations: [SyncClassificationRegistrationV1],
        lifecycleRoutes: [CurrentSyncLifecycleRouteV1],
        persistentModelSubjects: [SyncSubjectIdentityV1],
        ownedFileClassSubjects: [SyncSubjectIdentityV1],
        portableContentProjectionSubjects: [SyncSubjectIdentityV1],
        derivedIndexProjectionSubjects: [SyncSubjectIdentityV1],
        journalRecoverySubjects: [SyncSubjectIdentityV1],
        diagnosticSubjects: [SyncSubjectIdentityV1],
        secretSubjects: [SyncSubjectIdentityV1],
        searchImplementationPresent: Bool,
        keychainUsageDeclared: Bool
    ) throws {
        self.registrations = registrations
        self.lifecycleRoutes = lifecycleRoutes
        self.persistentModelSubjects = persistentModelSubjects
        self.ownedFileClassSubjects = ownedFileClassSubjects
        self.portableContentProjectionSubjects = portableContentProjectionSubjects
        self.derivedIndexProjectionSubjects = derivedIndexProjectionSubjects
        self.journalRecoverySubjects = journalRecoverySubjects
        self.diagnosticSubjects = diagnosticSubjects
        self.secretSubjects = secretSubjects
        self.searchImplementationPresent = searchImplementationPresent
        self.keychainUsageDeclared = keychainUsageDeclared
        try validate()
    }

    func registration(
        for subject: SyncSubjectIdentityV1
    ) throws -> SyncClassificationRegistrationV1 {
        let matches = registrations.filter { $0.subject == subject }
        guard matches.count == 1, let value = matches.first else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        return value
    }

    func lifecycleRoute(
        for subject: SyncSubjectIdentityV1
    ) throws -> CurrentSyncLifecycleRouteV1 {
        let matches = lifecycleRoutes.filter { $0.subject == subject }
        guard matches.count == 1, let value = matches.first else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
        }
        return value
    }

    func validate() throws {
        try SyncClassificationRegistryV1.validate()
        guard !registrations.isEmpty,
              registrations.count <= SyncClassificationRegistryV1.maximumRegistrationCount else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        let registrationKeys = registrations.map(\.subject.canonicalKey)
        guard registrationKeys == registrationKeys.sorted(),
              Set(registrationKeys).count == registrationKeys.count else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        try registrations.forEach { try $0.validate() }

        let bySubject = Dictionary(
            uniqueKeysWithValues: registrations.map { ($0.subject, $0) }
        )
        for baseline in try SyncClassificationRegistryV1.registrations {
            guard bySubject[baseline.subject] == baseline else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidBaseline
            }
        }

        try validatePersistentModels()
        try validateOwnedFileClasses()
        try requireExactCategory(
            persistentModelSubjects,
            category: .persistentModel,
            expectedNames: Self.activePersistentModelNames
        )
        try requireExactCategory(
            ownedFileClassSubjects,
            category: .ownedFileClass,
            expectedNames: Self.ownedFileClassNames
        )
        try requireExactCategory(
            portableContentProjectionSubjects,
            category: .projection,
            expectedNames: Self.portableContentProjectionNames
        )
        let expectedDerived = try Self.subjects(
            category: .index,
            names: Self.derivedIndexNames
        ) + (try Self.subjects(
            category: .projection,
            names: Self.derivedProjectionNames
        )) + (try Self.subjects(
            category: .projection,
            names: Self.ephemeralProjectionNames
        ))
        guard Set(derivedIndexProjectionSubjects) == Set(expectedDerived),
              derivedIndexProjectionSubjects.count == expectedDerived.count else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        try requireExactCategory(
            journalRecoverySubjects,
            category: .journal,
            expectedNames: Self.journalRecoveryNames
        )
        try requireExactCategory(
            diagnosticSubjects,
            category: .diagnostic,
            expectedNames: Self.diagnosticNames
        )
        guard secretSubjects.isEmpty,
              SyncClassificationRegistryV1.declaredSecretSubjects.isEmpty,
              !keychainUsageDeclared else {
            throw CurrentSyncClassificationCatalogFailureV1.unexpectedSecretOrKeychain
        }
        guard searchImplementationPresent else {
            throw CurrentSyncClassificationCatalogFailureV1.unexpectedSearchImplementation
        }

        let declaredSubjects = Set(
            persistentModelSubjects
            + ownedFileClassSubjects
            + portableContentProjectionSubjects
            + derivedIndexProjectionSubjects
            + journalRecoverySubjects
            + diagnosticSubjects
            + secretSubjects
        )
        guard declaredSubjects == Set(registrations.map(\.subject)),
              lifecycleRoutes.map(\.subject.canonicalKey) == registrationKeys else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        try lifecycleRoutes.forEach { route in
            let policy = try registration(for: route.subject).replicationPolicy
            guard route.semanticBackup == policy.backup,
                  route.portableExport == policy.export,
                  route.deletion == policy.deletion,
                  route.erase == policy.erase else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
            if route.subject.category == .ownedFileClass {
                guard let kind = OwnedFileKindV1(rawValue: route.subject.stableName),
                      route.filesystemBackup == (
                        ProtectedFilePolicyV1.isExcludedFromBackup(for: kind)
                            ? .excluded : .included
                      ) else {
                    throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
                }
            } else if route.filesystemBackup != .notApplicable {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
        }

        let mutationRules = try Self.mutationHistoryRepresentationRules
        guard mutationRules.count == 4,
              Set(mutationRules.map(\.source)).count == mutationRules.count,
              mutationRules.allSatisfy({ rule in
                  rule.sourceAuthority == .canonicalRow
                      || rule.sourceAuthority == .derivedPersistedRow
                      || rule.sourceAuthority == .localRecoveryRow
              }),
              mutationRules.allSatisfy({
                  $0.representationAuthority == .portableProjection
              }) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        let diagnosticRules = try Self.diagnosticRepresentationRules
        let diagnosticViewNames = Set(diagnosticRules.map { $0.representation.stableName })
        guard diagnosticViewNames == Set(Self.diagnosticNames).subtracting([
            "DeviceOperationalSupportStoreV2", "ScratchDataLeaseStoreV1",
        ]) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        let supportStore = try Self.subject(
            category: .diagnostic,
            name: "DeviceOperationalSupportStoreV2"
        )
        let scratchStore = try Self.subject(
            category: .diagnostic,
            name: "ScratchDataLeaseStoreV1"
        )
        guard try registration(for: supportStore).replicationPolicy.persistence == .ownedFile,
              try registration(for: scratchStore).replicationPolicy.persistence == .ownedFile,
              try diagnosticRules.allSatisfy({ rule in
                  try registration(for: rule.representation)
                      .replicationPolicy.persistence == .nonpersistent
              }) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }

        // These two assertions prevent filesystem-backup eligibility from
        // being confused with portable semantic backup/export eligibility.
        let database = try Self.subject(category: .ownedFileClass, name: "database")
        let databaseRoute = try lifecycleRoute(for: database)
        guard databaseRoute.filesystemBackup == .included,
              databaseRoute.semanticBackup == .exclude,
              databaseRoute.portableExport == .exclude else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
        }
        let records = try Self.subject(category: .projection, name: "V4BackupRecordsV1")
        let recordsRoute = try lifecycleRoute(for: records)
        guard recordsRoute.filesystemBackup == .notApplicable,
              recordsRoute.semanticBackup == .includeCanonical,
              recordsRoute.portableExport == .portableCanonical else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
        }

        // Card 28 support state is device-operational, never workspace truth.
        // Its concrete store/projections and scratch-lease adapter must remain
        // local-device authorities and ineligible for Cloud transport, backup,
        // or portable export. The generic owned scratch/diagnostics file kinds
        // are independently required to stay excluded from transport and
        // filesystem backup.
        for name in Self.diagnosticNames {
            let subject = try Self.subject(category: .diagnostic, name: name)
            let registration = try registration(for: subject)
            let route = try lifecycleRoute(for: subject)
            guard registration.classification == .privateDeviceOnly,
                  registration.replicationPolicy.authority == .localDevice,
                  registration.replicationPolicy.transport == .excluded,
                  registration.replicationPolicy.bootstrap == .destinationLocal,
                  route.filesystemBackup == .notApplicable,
                  route.semanticBackup == .exclude,
                  route.portableExport == .exclude else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
        }
        for name in ["diagnostics", "scratch"] {
            let subject = try Self.subject(category: .ownedFileClass, name: name)
            let registration = try registration(for: subject)
            let route = try lifecycleRoute(for: subject)
            guard registration.replicationPolicy.transport == .excluded,
                  route.filesystemBackup == .excluded,
                  route.semanticBackup == .exclude,
                  route.portableExport == .exclude else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
        }
    }

    static func validatePersistentModels() throws {
        try validatePersistentModelsImplementation()
    }
}

private extension CurrentSyncClassificationCatalogV1 {
    enum AdditionalProfile {
        case portableProjection
        case immutableContent
        case replicatedContent
        case derivedProjection
        case replicatedMutationHistory
        case recoveryJournal
        case privateDiagnostic
        case ephemeralWorkspaceScratch
    }

    struct AdditionalSpec {
        let category: SyncSubjectCategoryV1
        let name: String
        let profile: AdditionalProfile
        let dependencies: [SyncSubjectIdentityV1]
    }

    static func makeAdditionalRegistrations() throws -> [SyncClassificationRegistrationV1] {
        let baselineKeys = Set(
            try SyncClassificationRegistryV1.registrations.map(\.subject.canonicalKey)
        )
        var specs: [AdditionalSpec] = []

        specs.append(AdditionalSpec(
            category: .persistentModel,
            name: "ObservationAndTimeRow",
            profile: .replicatedContent,
            dependencies: [
                try subject(category: .persistentModel, name: "WorkflowRecord")
            ]
        ))
        for name in v6PersistentModelNames {
            let mutable = ["LocationNodeRow", "AssetCompositionEdgeRow"].contains(name)
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: mutable ? .replicatedContent : .replicatedMutationHistory,
                dependencies: try locationPersistentDependencies(for: name)
            ))
        }
        for name in v7PersistentModelNames {
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: .replicatedContent,
                dependencies: []
            ))
        }
        for name in v8PersistentModelNames {
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: .replicatedContent,
                dependencies: [try subject(category: .persistentModel, name: "WorkflowRecord")]
            ))
        }
        for name in v9PersistentModelNames {
            let mutable = name == "ServicePartyRow"
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: mutable ? .replicatedContent : .replicatedMutationHistory,
                dependencies: try partyPersistentDependencies(for: name)
            ))
        }
        for name in v10PersistentModelNames {
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: .replicatedMutationHistory,
                dependencies: try assetSemanticPersistentDependencies(for: name)
            ))
        }
        for name in v11PersistentModelNames {
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: .replicatedMutationHistory,
                dependencies: try authorityCriterionPersistentDependencies(for: name)
            ))
        }
        for name in v12PersistentModelNames {
            specs.append(AdditionalSpec(
                category: .persistentModel, name: name,
                profile: .replicatedMutationHistory,
                dependencies: try functionalRelationshipPersistentDependencies(for: name)
            ))
        }
        for name in v13PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:try evidenceAssurancePersistentDependencies(for:name)))}
        for name in v14PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v15PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v16PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v17PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v18PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v19PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v20PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v21PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v22PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v23PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[]))}
        for name in v24PersistentModelNames {
            let isIdentity=name=="SurveyDefinitionIdentityRow"
            let dependencies=isIdentity
                ? (try subjects(category:.persistentModel,names:["SurveyDefinitionReleaseRow"]))
                    + [try subject(category:.journal,name:"SurveyDefinitionLifecycleEventV1")]
                : []
            specs.append(AdditionalSpec(
                category:.persistentModel,
                name:name,
                profile:isIdentity ? .replicatedContent:.replicatedMutationHistory,
                dependencies:dependencies
            ))
        }
        for name in v25PersistentModelNames{let dependencies:[SyncSubjectIdentityV1];switch name{case "FactCaptureRow","SurveyPublicationSnapshotRow":dependencies=[try subject(category:.persistentModel,name:"SurveySessionRow")];case "SubjectPromotionReceiptRow":dependencies=[try subject(category:.persistentModel,name:"ProvisionalSubjectRow")];default:dependencies=[]};specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:dependencies))}
        for name in v26PersistentModelNames{let dependencies=name=="LocatorBindingReceiptRow" ? [try subject(category:.persistentModel,name:"AssetLocatorRow")]:[];specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:dependencies))}
        for name in v27PersistentModelNames{let dependencies=name=="OccurrenceHistoryEventRow" ? [try subject(category:.persistentModel,name:"ScheduleDefinitionReleaseRow")]:[];specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:dependencies))}
        for name in v28PersistentModelNames{let dependencies:[SyncClassificationSubjectV1];switch name{case "PlanRevisionRow":dependencies=[try subject(category:.persistentModel,name:"PlanDocumentRow"),try subject(category:.persistentModel,name:"FieldReferenceReleaseRow")];case "PlanPlacementRow":dependencies=[try subject(category:.persistentModel,name:"PlanRevisionRow"),try subject(category:.persistentModel,name:"LocatorBindingReceiptRow")];case "RebaseReceiptRow":dependencies=[try subject(category:.persistentModel,name:"PlanRevisionRow"),try subject(category:.persistentModel,name:"PlanPlacementRow")];default:dependencies=[]};specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:dependencies))}
        for name in v29PersistentModelNames{let dependencies:[SyncClassificationSubjectV1]=name=="SpatialAnchorObservationRow" ? [try subject(category:.persistentModel,name:"PlanRevisionRow")]:[];specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:dependencies))}
        for name in v30PersistentModelNames{let dependencies:[SyncClassificationSubjectV1]=name=="PairedObservationLinkRow" ? [try subject(category:.persistentModel,name:"EvidenceContextRow")]:[];specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:dependencies))}
        for name in v31PersistentModelNames{let dependencies:[SyncClassificationSubjectV1]=name=="LightingSystemRow" ? []:[try subject(category:.persistentModel,name:"LightingSystemRow")];specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:dependencies))}
        for name in v32PersistentModelNames{specs.append(AdditionalSpec(category:.persistentModel,name:name,profile:.replicatedMutationHistory,dependencies:[try subject(category:.persistentModel,name:"MutationReceiptRow")]))}

        for name in portableContentProjectionNames {
            let profile: AdditionalProfile = name == "ReportSnapshotV1"
                ? .immutableContent : .portableProjection
            specs.append(AdditionalSpec(
                category: .projection,
                name: name,
                profile: profile,
                dependencies: try projectionDependencies(for: name)
            ))
        }
        for name in derivedIndexNames {
            specs.append(AdditionalSpec(
                category: .index,
                name: name,
                profile: .derivedProjection,
                dependencies: try contentModelSubjects()
            ))
        }
        for name in derivedProjectionNames {
            specs.append(AdditionalSpec(
                category: .projection,
                name: name,
                profile: .derivedProjection,
                dependencies: try semanticDependencies(for: name)
            ))
        }
        for name in ephemeralProjectionNames {
            specs.append(AdditionalSpec(
                category: .projection,
                name: name,
                profile: .ephemeralWorkspaceScratch,
                dependencies: []
            ))
        }
        let replicatedHistory = Set([
            "MutationEnvelopeV1", "MutationHistoryQuarantineRecordV1",
            "MutationReceiptV1", "ReversalBasisV1", "SemanticReversalReceiptV1",
            "SurveyDefinitionLifecycleEventV1",
        ])
        for name in journalRecoveryNames {
            specs.append(AdditionalSpec(
                category: .journal,
                name: name,
                profile: replicatedHistory.contains(name)
                    ? .replicatedMutationHistory : .recoveryJournal,
                dependencies: name == "SurveyDefinitionLifecycleEventV1"
                    ? [try subject(category:.persistentModel,name:"MutationReceiptRow")]
                    : []
            ))
        }
        for name in diagnosticNames {
            // DiagnosticExportV1 is the bounded in-app preparation, not the
            // user-directed external Files/share effect. It remains device
            // local and is never a sync or portable-semantic-export subject.
            specs.append(AdditionalSpec(
                category: .diagnostic,
                name: name,
                profile: .privateDiagnostic,
                dependencies: []
            ))
        }

        return try specs.compactMap { spec in
            let subject = try subject(category: spec.category, name: spec.name)
            guard !baselineKeys.contains(subject.canonicalKey) else { return nil }
            return try registration(
                subject: subject,
                profile: spec.profile,
                dependencies: spec.dependencies
            )
        }.sorted { $0.subject.canonicalKey < $1.subject.canonicalKey }
    }

    static func registration(
        subject: SyncSubjectIdentityV1,
        profile: AdditionalProfile,
        dependencies: [SyncSubjectIdentityV1]
    ) throws -> SyncClassificationRegistrationV1 {
        let classification: SyncClassificationV1
        let authority: ReplicationAuthorityV1
        let persistence: ReplicationPersistenceV1
        let transport: ReplicationTransportV1
        let bootstrap: ReplicationBootstrapV1
        let privacy: ReplicationPrivacyV1
        let retention: ReplicationRetentionV1
        let backup: ReplicationBackupDispositionV1
        let export: ReplicationExportDispositionV1
        let deletion: ReplicationDeleteDispositionV1
        let erase: ReplicationEraseDispositionV1
        let rule: ConflictRuleV1
        let maximumBytes: Int64

        switch profile {
        case .portableProjection:
            classification = .derivedRebuildable
            authority = .derivedFromCanonicalInputs
            persistence = .nonpersistent
            transport = .excluded
            bootstrap = .rebuildFromDependencies
            privacy = .workspaceData
            retention = .rebuildable
            backup = .includeCanonical
            export = .portableCanonical
            deletion = .rebuild
            erase = .rebuildAfterErase
            rule = .derivedRebuild
            maximumBytes = 1_073_741_824
        case .immutableContent:
            classification = .contentBlob
            authority = .immutableContentWriter
            persistence = .ownedFile
            transport = .futureBoundedBlobEligible
            bootstrap = .immutableHistory
            privacy = .workspaceContentBlob
            retention = .immutableHistoryUntilErase
            backup = .includeImmutableHistory
            export = .portableImmutableHistory
            deletion = .canonicalDelete
            erase = .clearWithWorkspace
            rule = .immutableVersion
            maximumBytes = 134_217_728
        case .replicatedContent:
            classification = .replicated
            authority = .workspaceWriter
            persistence = .swiftDataRecord
            transport = .futureAcceptedMutationEligible
            bootstrap = .canonicalSnapshot
            privacy = .workspaceData
            retention = .untilCanonicalDeleteOrErase
            backup = .includeCanonical
            export = .portableCanonical
            deletion = .canonicalDelete
            erase = .clearWithWorkspace
            rule = .exactRevisionManual
            maximumBytes = 16_777_216
        case .derivedProjection:
            classification = .derivedRebuildable
            authority = .derivedFromCanonicalInputs
            persistence = .nonpersistent
            transport = .excluded
            bootstrap = .rebuildFromDependencies
            privacy = .workspaceData
            retention = .rebuildable
            backup = .rebuildAfterRestore
            export = .exclude
            deletion = .rebuild
            erase = .rebuildAfterErase
            rule = .derivedRebuild
            maximumBytes = 16_777_216
        case .replicatedMutationHistory:
            classification = .replicated
            authority = .workspaceWriter
            persistence = .swiftDataRecord
            transport = .futureAcceptedMutationEligible
            bootstrap = .immutableHistory
            privacy = .workspaceData
            retention = .immutableHistoryUntilErase
            backup = .includeImmutableHistory
            export = .portableImmutableHistory
            deletion = .localAuthority
            erase = .clearWithWorkspace
            rule = .stableIDAppendUnion
            maximumBytes = 16_777_216
        case .recoveryJournal:
            classification = .localOnly
            authority = .localDevice
            persistence = .ownedFile
            transport = .excluded
            bootstrap = .destinationLocal
            privacy = .workspaceData
            retention = .operationScoped
            backup = .exclude
            export = .exclude
            deletion = .operationCleanup
            erase = .clearWithWorkspace
            rule = .localOnly
            maximumBytes = 16_777_216
        case .privateDiagnostic:
            classification = .privateDeviceOnly
            authority = .localDevice
            persistence = [
                "DeviceOperationalSupportStoreV2",
                "ScratchDataLeaseStoreV1",
            ].contains(subject.stableName) ? .ownedFile : .nonpersistent
            transport = .excluded
            bootstrap = .destinationLocal
            privacy = .noncustomerDiagnostic
            retention = .localDeviceRetained
            backup = .exclude
            export = .exclude
            deletion = .localAuthority
            erase = .localAuthority
            rule = .localOnly
            maximumBytes = 4_194_304
        case .ephemeralWorkspaceScratch:
            classification = .localOnly
            authority = .localDevice
            persistence = .nonpersistent
            transport = .excluded
            bootstrap = .destinationLocal
            privacy = .workspaceData
            retention = .operationScoped
            backup = .exclude
            export = .exclude
            deletion = .operationCleanup
            erase = .clearWithWorkspace
            rule = .localOnly
            maximumBytes = 1_048_576
        }

        let sortedDependencies = dependencies.sorted { $0.canonicalKey < $1.canonicalKey }
        let policy = try ReplicationPolicyV1(
            policyID: "current." + subject.canonicalKey.replacingOccurrences(of: ":", with: "."),
            authority: authority,
            persistence: persistence,
            transport: transport,
            bootstrap: bootstrap,
            privacy: privacy,
            retention: retention,
            codec: try ReplicationCodecV1(
                codecID: "current." + subject.stableName,
                readableVersions: [1],
                currentWriteVersion: 1
            ),
            sizeLimit: .boundedBytes(maximumBytes),
            dependencies: sortedDependencies,
            backup: backup,
            export: export,
            deletion: deletion,
            erase: erase
        )
        return try SyncClassificationRegistrationV1(
            subject: subject,
            classification: classification,
            replicationPolicy: policy,
            conflictPolicy: try ConflictPolicyV1(
                policyID: "current." + subject.canonicalKey.replacingOccurrences(of: ":", with: "."),
                rule: rule
            )
        )
    }

    static func makeLifecycleRoute(
        _ registration: SyncClassificationRegistrationV1
    ) throws -> CurrentSyncLifecycleRouteV1 {
        let filesystemBackup: CurrentFilesystemBackupDispositionV1
        if registration.subject.category == .ownedFileClass {
            guard let kind = OwnedFileKindV1(rawValue: registration.subject.stableName) else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
            filesystemBackup = ProtectedFilePolicyV1.isExcludedFromBackup(for: kind)
                ? .excluded : .included
        } else {
            filesystemBackup = .notApplicable
        }

        let rebuild: CurrentRebuildDispositionV1
        switch registration.classification {
        case .derivedRebuildable:
            rebuild = .rebuildFromCanonicalDependencies
        default:
            rebuild = .notApplicable
        }

        let replay: CurrentReplayDispositionV1
        if registration.subject.category == .journal {
            switch registration.classification {
            case .replicated:
                replay = .immutableMutationHistory
            default:
                replay = .recoveryStateMachine
            }
        } else if registration.subject.category == .persistentModel,
                  registration.subject.stableName == "MutationReceiptRow" {
            replay = .immutableMutationHistory
        } else {
            replay = .notApplicable
        }

        return CurrentSyncLifecycleRouteV1(
            subject: registration.subject,
            filesystemBackup: filesystemBackup,
            semanticBackup: registration.replicationPolicy.backup,
            portableExport: registration.replicationPolicy.export,
            deletion: registration.replicationPolicy.deletion,
            erase: registration.replicationPolicy.erase,
            rebuild: rebuild,
            replay: replay
        )
    }

    static func projectionDependencies(
        for name: String
    ) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "DeletionLedgerV2":
            return [try subject(category: .persistentModel, name: "DeletionLedgerRow")]
        case "MutationHistorySnapshotV1":
            return try subjects(category: .persistentModel, names: [
                "EntityMutationRevisionRow", "MutationQuarantineRow",
                "MutationReceiptRow", "WorkspaceMutationStateRow",
            ])
        case "ObservationBasisV1", "TemporalContextV1":
            return [try subject(category: .persistentModel, name: "ObservationAndTimeRow")]
        case "ReportSnapshotV1":
            return try contentModelSubjects()
        case "StreamingArchiveIndexV1":
            return [try subject(category: .projection, name: "V4BackupManifestV1")]
        case "V4BackupAssetDTO":
            return [try subject(category: .persistentModel, name: "Asset")]
        case "V4BackupEvidenceFileDTO":
            return [try subject(category: .persistentModel, name: "EvidenceFile")]
        case "V4BackupIssueDTO":
            return [try subject(category: .persistentModel, name: "Issue")]
        case "V4BackupPacketDTO":
            return [try subject(category: .persistentModel, name: "Packet")]
        case "V4BackupReportDTO":
            return [try subject(category: .persistentModel, name: "Report")]
        case "V4BackupSiteDTO":
            return [try subject(category: .persistentModel, name: "Site")]
        case "V4BackupWorkflowRecordDTO":
            return try subjects(category: .persistentModel, names: [
                "ObservationAndTimeRow", "WorkflowRecord",
            ])
        case "V4BackupRecordsV1", "V4BackupManifestV1":
            return try contentModelSubjects()
        case "V5BackupLocationRecordV1":
            return try subjects(category: .persistentModel, names: v6PersistentModelNames)
        case "SavedSmartViewDescriptorV1":
            return [try subject(category: .persistentModel, name: "SavedSmartView")]
        case "RequirementAssuranceSnapshotV1", "RequirementEvaluationV1",
             "CompletionDecisionV1", "IntegrityFindingV1":
            return [try subject(category: .persistentModel, name: "RequirementAssuranceRow")]
        case "ServicePartyReferenceV1":
            return [try subject(category: .persistentModel, name: "ServicePartyRow")]
        case "SitePartyRoleEventV1":
            return [try subject(category: .persistentModel, name: "SitePartyRoleEventRow")]
        case "ActorSnapshotV1":
            return [try subject(category: .persistentModel, name: "ActorSnapshotRow")]
        case "QualificationSnapshotV1":
            return [try subject(category: .persistentModel, name: "QualificationSnapshotRow")]
        case "SignoffSnapshotV1":
            return [try subject(category: .persistentModel, name: "SignoffSnapshotRow")]
        case "AssetSemanticCatalogReleaseV1", "AssetKindDefinitionV1":
            return []
        case "AssetKindBindingEventV1":
            return [try subject(category: .persistentModel, name: "AssetKindBindingEventRow")]
        case "AssetWorkflowCapabilityBindingEventV1":
            return [try subject(category: .persistentModel, name: "AssetWorkflowCapabilityBindingEventRow")]
        case "AssetProductIdentityV1":
            return [try subject(category: .persistentModel, name: "AssetProductIdentityRow")]
        case "AssetLifecycleEventV1":
            return [try subject(category: .persistentModel, name: "AssetLifecycleEventRow")]
        case "AssetSuccessorLinkV1":
            return [try subject(category: .persistentModel, name: "AssetSuccessorLinkRow")]
        case "WorkSubjectScopeSnapshotV1":
            return [try subject(category: .persistentModel, name: "WorkSubjectScopeSnapshotRow")]
        case "AuthoritySourceReleaseV1": return [try subject(category: .persistentModel, name: "AuthoritySourceReleaseRow")]
        case "RequirementBasisBindingV1": return [try subject(category: .persistentModel, name: "RequirementBasisBindingRow")]
        case "ApplicabilityContextSnapshotV1": return [try subject(category: .persistentModel, name: "ApplicabilityContextSnapshotRow")]
        case "AssessmentScopeSnapshotV1": return [try subject(category: .persistentModel, name: "AssessmentScopeSnapshotRow")]
        case "SeverityScaleReleaseV1": return [try subject(category: .persistentModel, name: "SeverityScaleReleaseRow")]
        case "FindingClassificationBindingV1": return [try subject(category: .persistentModel, name: "FindingClassificationBindingRow")]
        case "MeasurementProtocolReleaseV1": return [try subject(category: .persistentModel, name: "MeasurementProtocolReleaseRow")]
        case "DerivedFactEvaluatorDescriptorV1": return [try subject(category: .persistentModel, name: "DerivedFactEvaluatorDescriptorRow")]
        case "DerivedFactProvenanceV1": return [try subject(category: .persistentModel, name: "DerivedFactProvenanceRow")]
        case "FunctionalRelationshipTypeDescriptorV1": return [try subject(category: .persistentModel, name: "FunctionalRelationshipTypeDescriptorRow")]
        case "AssetFunctionalRelationshipEventV1": return [try subject(category: .persistentModel, name: "AssetFunctionalRelationshipEventRow")]
        case "CurrentFunctionalRelationshipProjectionV1", "FunctionalRelationshipDispositionPreviewV1":
            return try subjects(category: .persistentModel, names: ["FunctionalRelationshipTypeDescriptorRow", "AssetFunctionalRelationshipEventRow"])
        case "CompletedFunctionalRelationshipSnapshotV1":
            return try subjects(category: .persistentModel, names: ["FunctionalRelationshipTypeDescriptorRow", "AssetFunctionalRelationshipEventRow"])
        case "EvidenceVisibilityV1":return[try subject(category:.persistentModel,name:"EvidenceVisibilityRow")]
        case "ClaimEvidenceLinkV1":return[try subject(category:.persistentModel,name:"ClaimEvidenceLinkRow")]
        case "AssuranceManifestV1":return[try subject(category:.persistentModel,name:"AssuranceManifestRow")]
        case "AttestationV1":return[try subject(category:.persistentModel,name:"AttestationRow")]
        case "AssuranceProjectionPreviewV1":return try subjects(category:.persistentModel,names:["ClaimEvidenceLinkRow","EvidenceVisibilityRow"])
        case "InspectionReviewTransitionV1":return[try subject(category:.persistentModel,name:"InspectionReviewTransitionRow")]
        case "ReviewDispositionV1":return[try subject(category:.persistentModel,name:"ReviewDispositionRow")]
        case "ChangeRequestV1":return[try subject(category:.persistentModel,name:"ChangeRequestRow")]
        case "CorrectiveActionPolicyV1":return[try subject(category:.persistentModel,name:"CorrectiveActionPolicyRow")]
        case "CorrectiveActionEventV1":return[try subject(category:.persistentModel,name:"CorrectiveActionEventRow")]
        case "InspectionReviewProjectionV1":return try subjects(category:.persistentModel,names:["InspectionReviewTransitionRow","ReviewDispositionRow","ChangeRequestRow"])
        case "CorrectiveActionProjectionV1":return try subjects(category:.persistentModel,names:["CorrectiveActionPolicyRow","CorrectiveActionEventRow"])
        case "WorkPacketManifestV1":return[try subject(category:.persistentModel,name:"WorkPacketManifestRow")]
        case "WorkItemClaimV1":return[try subject(category:.persistentModel,name:"WorkItemClaimRow")]
        case "WorkLeaseV1":return[try subject(category:.persistentModel,name:"WorkLeaseRow")]
        case "WorkReleaseV1":return[try subject(category:.persistentModel,name:"WorkReleaseRow")]
        case "WorkHandoffV1":return[try subject(category:.persistentModel,name:"WorkHandoffRow")]
        case "WorkPacketProjectionV1":return try subjects(category:.persistentModel,names:v15PersistentModelNames)
        case "FieldDraftCheckpointV1":return[try subject(category:.persistentModel,name:"FieldDraftCheckpointRow")]
        case "AttachmentStagingItemV1":return[try subject(category:.persistentModel,name:"AttachmentStagingItemRow")]
        case "DraftCommitSagaV1":return[try subject(category:.persistentModel,name:"DraftCommitSagaRow")]
        case "DraftContentReservationV1":return[try subject(category:.persistentModel,name:"DraftContentReservationRow")]
        case "DraftCommitReceiptV1":return[try subject(category:.persistentModel,name:"DraftCommitReceiptRow")]
        case "DraftDiscardReceiptV1":return[try subject(category:.persistentModel,name:"DraftDiscardReceiptRow")]
        case "DraftRecoveryProjectionV1":return try subjects(category:.persistentModel,names:v16PersistentModelNames)
        case "PromotedPackageReleaseV1":return[try subject(category:.persistentModel,name:"PromotedPackageReleaseRow")]
        case "PackageSandboxRunV1":return[try subject(category:.persistentModel,name:"PackageSandboxRunRow")]
        case "PackagePromotionReceiptV1":return[try subject(category:.persistentModel,name:"PackagePromotionReceiptRow")]
        case "ActivePackageRegistryPointerV1":return[try subject(category:.persistentModel,name:"ActivePackageRegistryPointerRow")]
        case "PackageEvolutionLifecycleClosureV1":return try subjects(category:.persistentModel,names:v17PersistentModelNames)
        case "InstrumentReferenceV1":return[try subject(category:.persistentModel,name:"InstrumentReferenceRow")]
        case "CalibrationStatusSnapshotV1":return[try subject(category:.persistentModel,name:"CalibrationStatusSnapshotRow")]
        case "MeasurementCaptureV1":return[try subject(category:.persistentModel,name:"MeasurementCaptureRow")]
        case "MeasurementSeriesV1":return[try subject(category:.persistentModel,name:"MeasurementSeriesRow")]
        case "MeasurementQualityAssessmentV1":return[try subject(category:.persistentModel,name:"MeasurementQualityAssessmentRow")]
        case "PrivacyTransformPolicyV1":return[try subject(category:.persistentModel,name:"PrivacyTransformPolicyRow")]
        case "PrivacyRegionV1":return[try subject(category:.persistentModel,name:"PrivacyRegionRow")]
        case "PrivacyTransformManifestV1":return[try subject(category:.persistentModel,name:"PrivacyTransformManifestRow")]
        case "PrivacyReviewReceiptV1":return[try subject(category:.persistentModel,name:"PrivacyReviewReceiptRow")]
        case "PrivacyProjectionV1":return try subjects(category:.persistentModel,names:v19PersistentModelNames)
        case "PrivacyTransformLifecycleClosureV1":return try subjects(category:.persistentModel,names:v19PersistentModelNames)
        case "ClientCapabilityProfileV1":return[try subject(category:.persistentModel,name:"ClientCapabilityProfileRow")]
        case "ClientCapabilityAdmissionDecisionV1":return[try subject(category:.persistentModel,name:"ClientCapabilityAdmissionDecisionRow")]
        case "PackageLifecyclePolicyV1":return[try subject(category:.persistentModel,name:"PackageLifecyclePolicyRow")]
        case "PackageLifecycleDispositionV1":return[try subject(category:.persistentModel,name:"PackageLifecycleDispositionRow")]
        case "ClientCapabilityAdmissionEvaluatorV1","ClientCapabilityLifecycleClosureV1":return try subjects(category:.persistentModel,names:v20PersistentModelNames)
        case "RecoverabilityVerificationReceiptV1":return[try subject(category:.persistentModel,name:"RecoverabilityVerificationReceiptRow")]
        case "FieldReferenceReleaseV1":return[try subject(category:.persistentModel,name:"FieldReferenceReleaseRow")]
        case "FieldReferenceBindingV1":return[try subject(category:.persistentModel,name:"FieldReferenceBindingRow")]
        case "AccessibleDocumentAssessmentReceiptV1":return[try subject(category:.persistentModel,name:"AccessibleDocumentAssessmentReceiptRow")]
        case "SurveyDefinitionIdentityV1":return[try subject(category:.persistentModel,name:"SurveyDefinitionIdentityRow")]
        case "SurveyDefinitionReleaseV1":return[try subject(category:.persistentModel,name:"SurveyDefinitionReleaseRow")]
        case "SurveySessionV1":return[try subject(category:.persistentModel,name:"SurveySessionRow")]
        case "FactCaptureV1":return[try subject(category:.persistentModel,name:"FactCaptureRow")]
        case "ProvisionalSubjectV1":return[try subject(category:.persistentModel,name:"ProvisionalSubjectRow")]
        case "SubjectPromotionReceiptV1":return[try subject(category:.persistentModel,name:"SubjectPromotionReceiptRow")]
        case "SurveyPublicationSnapshotV1":return[try subject(category:.persistentModel,name:"SurveyPublicationSnapshotRow")]
        case "SurveySessionLifecycleClosureV1":return try subjects(category:.persistentModel,names:v25PersistentModelNames)
        case "AssetLocatorV1":return[try subject(category:.persistentModel,name:"AssetLocatorRow")]
        case "LocatorBindingReceiptV1":return[try subject(category:.persistentModel,name:"LocatorBindingReceiptRow")]
        case "AssetLocatorLifecycleClosureV1":return try subjects(category:.persistentModel,names:v26PersistentModelNames)
        case "ScheduleDefinitionReleaseV1":return[try subject(category:.persistentModel,name:"ScheduleDefinitionReleaseRow")]
        case "OccurrenceHistoryEventV1":return[try subject(category:.persistentModel,name:"OccurrenceHistoryEventRow"),try subject(category:.persistentModel,name:"ScheduleDefinitionReleaseRow")]
        case "AssistanceAcceptanceReceiptV1":return[try subject(category:.persistentModel,name:"AssistanceAcceptanceReceiptRow")]
        case "OccurrenceGenerationPlanV1","DueQueueProjectionV1","ReminderProjectionV1":return try subjects(category:.persistentModel,names:v27PersistentModelNames)
        case "PackageSemanticDiffV1","DraftUpgradePlanV1":return []
        default:
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func semanticDependencies(
        for name: String
    ) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "EntityMutationRevisionSemanticV1", "entityMutationRevision":
            return [try subject(category: .persistentModel, name: "EntityMutationRevisionRow")]
        case "MutationQuarantineSemanticV1":
            return [try subject(category: .persistentModel, name: "MutationQuarantineRow")]
        case "MutationReceiptSemanticV1":
            return [try subject(category: .persistentModel, name: "MutationReceiptRow")]
        case "WorkspaceMutationStateSemanticV1", "workspaceMutationState":
            return [try subject(category: .persistentModel, name: "WorkspaceMutationStateRow")]
        case "ObservationAndTimeMigrationReceiptV1", "ObservationAndTimeSemanticV1":
            return [
                try subject(category: .persistentModel, name: "WorkflowRecord"),
                try subject(category: .persistentModel, name: "ObservationAndTimeRow"),
            ]
        case "StoreSemanticEnvelopeV3", "StoreSemanticEnvelopeV4", "StoreSemanticEnvelopeV5":
            return try subjects(category: .persistentModel, names: persistentModelNames)
        case "StoreSemanticEnvelopeV6":
            return try subjects(
                category: .persistentModel,
                names: persistentModelNames + v6PersistentModelNames
            )
        case "StoreSemanticEnvelopeV7":
            return try subjects(
                category: .persistentModel,
                names: persistentModelNames + v6PersistentModelNames + v7PersistentModelNames
            )
        case "StoreSemanticEnvelopeV8":
            return try subjects(category: .persistentModel, names:
                persistentModelNames + v6PersistentModelNames + v7PersistentModelNames + v8PersistentModelNames)
        case "StoreSemanticEnvelopeV9":
            return try subjects(category: .persistentModel, names:
                persistentModelNames + v6PersistentModelNames + v7PersistentModelNames
                    + v8PersistentModelNames + v9PersistentModelNames)
        case "StoreSemanticEnvelopeV10":
            return try subjects(category: .persistentModel, names:
                persistentModelNames + v6PersistentModelNames + v7PersistentModelNames
                    + v8PersistentModelNames + v9PersistentModelNames + v10PersistentModelNames)
        case "StoreSemanticEnvelopeV11":
            return try subjects(category: .persistentModel, names:
                persistentModelNames + v6PersistentModelNames + v7PersistentModelNames
                    + v8PersistentModelNames + v9PersistentModelNames + v10PersistentModelNames
                    + v11PersistentModelNames)
        case "StoreSemanticEnvelopeV12":
            return try subjects(category:.persistentModel,names:persistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames)
        case "StoreSemanticEnvelopeV13":return try subjects(category:.persistentModel,names:persistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames+v13PersistentModelNames)
        case "StoreSemanticEnvelopeV14":return try subjects(category:.persistentModel,names:persistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames+v13PersistentModelNames+v14PersistentModelNames)
        case "StoreSemanticEnvelopeV15":return try subjects(category:.persistentModel,names:persistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames+v13PersistentModelNames+v14PersistentModelNames+v15PersistentModelNames)
        case "StoreSemanticEnvelopeV16":return try subjects(category:.persistentModel,names:persistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames+v13PersistentModelNames+v14PersistentModelNames+v15PersistentModelNames+v16PersistentModelNames)
        case "StoreSemanticEnvelopeV17":return try subjects(category:.persistentModel,names:persistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames+v13PersistentModelNames+v14PersistentModelNames+v15PersistentModelNames+v16PersistentModelNames+v17PersistentModelNames)
        case "StoreSemanticEnvelopeV18":return try subjects(category:.persistentModel,names:persistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames+v13PersistentModelNames+v14PersistentModelNames+v15PersistentModelNames+v16PersistentModelNames+v17PersistentModelNames+v18PersistentModelNames)
        case "StoreSemanticEnvelopeV19":return try subjects(category:.persistentModel,names:(v1PersistentModelNames+v2PersistentModelNames+v3PersistentModelNames+v4PersistentModelNames+v5PersistentModelNames+v6PersistentModelNames+v7PersistentModelNames+v8PersistentModelNames+v9PersistentModelNames+v10PersistentModelNames+v11PersistentModelNames+v12PersistentModelNames+v13PersistentModelNames+v14PersistentModelNames+v15PersistentModelNames+v16PersistentModelNames+v17PersistentModelNames+v18PersistentModelNames+v19PersistentModelNames))
        case "StoreSemanticEnvelopeV20":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!(v21PersistentModelNames+v22PersistentModelNames+v23PersistentModelNames+v24PersistentModelNames+v25PersistentModelNames+v26PersistentModelNames).contains($0)})
        case "StoreSemanticEnvelopeV21":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!(v22PersistentModelNames+v23PersistentModelNames+v24PersistentModelNames+v25PersistentModelNames+v26PersistentModelNames).contains($0)})
        case "RecoverabilityVerificationStagingV1","RecoverabilityFreshnessProjectionV1","RecoverabilityVerificationLifecycleV1":return[try subject(category:.persistentModel,name:"RecoverabilityVerificationReceiptRow")]
        case "StoreSemanticEnvelopeV22":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!(v23PersistentModelNames+v24PersistentModelNames+v25PersistentModelNames+v26PersistentModelNames).contains($0)})
        case "StoreSemanticEnvelopeV23":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!(v24PersistentModelNames+v25PersistentModelNames+v26PersistentModelNames).contains($0)})
        case "StoreSemanticEnvelopeV24":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!(v25PersistentModelNames+v26PersistentModelNames).contains($0)})
        case "StoreSemanticEnvelopeV25":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!v26PersistentModelNames.contains($0)})
        case "StoreSemanticEnvelopeV26":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!v27PersistentModelNames.contains($0)})
        case "StoreSemanticEnvelopeV27":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!(v28PersistentModelNames+v29PersistentModelNames).contains($0)})
        case "StoreSemanticEnvelopeV28":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!v29PersistentModelNames.contains($0)})
        case "StoreSemanticEnvelopeV29":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!v30PersistentModelNames.contains($0)})
        case "StoreSemanticEnvelopeV30":return try subjects(category:.persistentModel,names:activePersistentModelNames)
        case "StoreSemanticEnvelopeV31":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!v32PersistentModelNames.contains($0)})
        case "StoreSemanticEnvelopeV32":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!(v33PersistentModelNames+v34PersistentModelNames).contains($0)})
        case "StoreSemanticEnvelopeV33":return try subjects(category:.persistentModel,names:activePersistentModelNames.filter{!v34PersistentModelNames.contains($0)})
        case "StoreSemanticEnvelopeV34":return try subjects(category:.persistentModel,names:activePersistentModelNames)
        case "PlanDocumentV1","PlanRevisionV1","SpatialReferenceFrameV1","PlanPlacementV1","RebasePreviewV1","RebaseReceiptV1":return try subjects(category:.persistentModel,names:v28PersistentModelNames)
        case "PoseAxisDescriptorRegistryV1","AssetPoseCurrentTipV1","CompletedPlacementPoseSnapshotV1":return try subjects(category:.persistentModel,names:v29PersistentModelNames)
        case "EvidenceContextV1","PairedObservationLinkV1":return try subjects(category:.persistentModel,names:v30PersistentModelNames)
        case "LightingTopologyV1","LightingDuePreviewV1":return try subjects(category:.persistentModel,names:v31PersistentModelNames)
        case "LocatorBindingPreviewV1","LocatorResolutionV1":return try subjects(category:.persistentModel,names:v26PersistentModelNames)
        case "AccessibleDocumentSemanticTreeV1","AccessibleDocumentLifecycleV1":return try subjects(category:.persistentModel,names:v23PersistentModelNames)
        case "SurveyDefinitionSemanticDiffV1":return[try subject(category:.persistentModel,name:"SurveyDefinitionReleaseRow")]
        case "SurveyDefinitionAdoptionPreviewV1":return try subjects(category:.persistentModel,names:v24PersistentModelNames)
        case "SurveyTemplateQuarantineAssessmentV1":return[]
        case "FieldReferenceOfflineReadinessV1","FieldReferencePackLifecycleV1":return try subjects(category:.persistentModel,names:v22PersistentModelNames)
        case "IntegrationConformanceConsumerV1", "IntegrationContractRegistryV1",
             "IntegrationEventProjectionV1", "IntegrationEventV1",
             "IntegrationProjectionCheckpointStoreV1", "ProjectionCheckpointV1":
            return [try subject(category: .journal, name: "MutationReceiptV1")]
        default:
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func contentModelSubjects() throws -> [SyncSubjectIdentityV1] {
        try subjects(category: .persistentModel, names: [
            "Asset", "EvidenceFile", "Issue", "ObservationAndTimeRow", "Packet",
            "Report", "Site", "WorkflowRecord",
        ])
    }

    static func locationPersistentDependencies(
        for name: String
    ) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "LocationNodeRow":
            return [try subject(category: .persistentModel, name: "Site")]
        case "LocationHierarchyEventRow":
            return try subjects(category: .persistentModel, names: ["LocationNodeRow", "Site"])
        case "AssetPlacementEventRow":
            return try subjects(category: .persistentModel, names: ["Asset", "LocationNodeRow", "Site"])
        case "AssetCompositionEdgeRow", "AssetCompositionEventRow":
            return [try subject(category: .persistentModel, name: "Asset")]
        case "LocationMigrationReceiptRow":
            return try subjects(category: .persistentModel, names: ["Asset", "AssetPlacementEventRow", "Site"])
        default:
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func partyPersistentDependencies(for name: String) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "ServicePartyRow": return []
        case "SitePartyRoleEventRow":
            return try subjects(category: .persistentModel, names: ["ServicePartyRow", "Site"])
        case "ActorSnapshotRow":
            return [try subject(category: .persistentModel, name: "ServicePartyRow")]
        case "QualificationSnapshotRow": return []
        case "SignoffSnapshotRow":
            return try subjects(category: .persistentModel, names: ["ActorSnapshotRow", "QualificationSnapshotRow", "ServicePartyRow"])
        default: throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func assetSemanticPersistentDependencies(for name: String) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "AssetKindBindingEventRow", "AssetProductIdentityRow":
            return [try subject(category: .persistentModel, name: "Asset")]
        case "AssetWorkflowCapabilityBindingEventRow":
            return try subjects(category: .persistentModel, names: ["Asset", "AssetKindBindingEventRow"])
        case "AssetLifecycleEventRow":
            return try subjects(category: .persistentModel, names: ["Asset", "AssetKindBindingEventRow", "AssetSuccessorLinkRow"])
        case "AssetSuccessorLinkRow":
            return [try subject(category: .persistentModel, name: "Asset")]
        case "WorkSubjectScopeSnapshotRow":
            return try subjects(category: .persistentModel, names: ["Asset", "LocationNodeRow", "Site"])
        default:
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func authorityCriterionPersistentDependencies(for name: String) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "AuthoritySourceReleaseRow", "AssessmentScopeSnapshotRow",
             "SeverityScaleReleaseRow", "MeasurementProtocolReleaseRow",
             "DerivedFactEvaluatorDescriptorRow":
            return []
        case "RequirementBasisBindingRow":
            return [try subject(category: .persistentModel, name: "AuthoritySourceReleaseRow")]
        case "ApplicabilityContextSnapshotRow":
            return [try subject(category: .persistentModel, name: "RequirementBasisBindingRow")]
        case "FindingClassificationBindingRow":
            return [try subject(category: .persistentModel, name: "SeverityScaleReleaseRow")]
        case "DerivedFactProvenanceRow":
            return try subjects(category: .persistentModel, names: [
                "DerivedFactEvaluatorDescriptorRow", "MeasurementProtocolReleaseRow",
            ])
        default: throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func functionalRelationshipPersistentDependencies(for name: String) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "FunctionalRelationshipTypeDescriptorRow": return []
        case "AssetFunctionalRelationshipEventRow":
            return try subjects(category: .persistentModel, names: [
                "Asset", "FunctionalRelationshipTypeDescriptorRow",
                "AssetKindBindingEventRow", "AssetWorkflowCapabilityBindingEventRow",
            ])
        default: throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }
    static func evidenceAssurancePersistentDependencies(for name:String)throws->[SyncSubjectIdentityV1]{switch name{case "EvidenceVisibilityRow":return[];case "ClaimEvidenceLinkRow":return[try subject(category:.persistentModel,name:"EvidenceVisibilityRow")];case "AssuranceManifestRow":return try subjects(category:.persistentModel,names:["ClaimEvidenceLinkRow","EvidenceVisibilityRow"]);case "AttestationRow":return[try subject(category:.persistentModel,name:"AssuranceManifestRow")];default:throw CurrentSyncClassificationCatalogFailureV1.invalidInventory}}

    static func validatePersistentModelsImplementation() throws {
        let frozenV5: [any PersistentModel.Type] = [
            Site.self,
            Asset.self,
            WorkflowRecord.self,
            EvidenceFile.self,
            Issue.self,
            Packet.self,
            Report.self,
            PersistentSchemaReleaseMarker.self,
            DeletionLedgerRow.self,
            MutationReceiptRow.self,
            MutationQuarantineRow.self,
            WorkspaceMutationStateRow.self,
            EntityMutationRevisionRow.self,
            ObservationAndTimeRow.self,
        ]
        let expected = frozenV5 + [
            LocationNodeRow.self,
            LocationHierarchyEventRow.self,
            AssetPlacementEventRow.self,
            AssetCompositionEdgeRow.self,
            AssetCompositionEventRow.self,
            LocationMigrationReceiptRow.self,
            SavedSmartViewRowV1.self,
            RequirementAssuranceRow.self,
            ServicePartyRow.self,
            SitePartyRoleEventRow.self,
            ActorSnapshotRow.self,
            QualificationSnapshotRow.self,
            SignoffSnapshotRow.self,
            AssetKindBindingEventRow.self,
            AssetWorkflowCapabilityBindingEventRow.self,
            AssetProductIdentityRow.self,
            AssetLifecycleEventRow.self,
            AssetSuccessorLinkRow.self,
            WorkSubjectScopeSnapshotRow.self,
            AuthoritySourceReleaseRow.self,
            RequirementBasisBindingRow.self,
            ApplicabilityContextSnapshotRow.self,
            AssessmentScopeSnapshotRow.self,
            SeverityScaleReleaseRow.self,
            FindingClassificationBindingRow.self,
            MeasurementProtocolReleaseRow.self,
            DerivedFactEvaluatorDescriptorRow.self,
            DerivedFactProvenanceRow.self,
            FunctionalRelationshipTypeDescriptorRow.self,
            AssetFunctionalRelationshipEventRow.self,
            EvidenceVisibilityRow.self,ClaimEvidenceLinkRow.self,AssuranceManifestRow.self,AttestationRow.self,
            InspectionReviewTransitionRow.self,ReviewDispositionRow.self,ChangeRequestRow.self,CorrectiveActionPolicyRow.self,CorrectiveActionEventRow.self,
            WorkPacketManifestRow.self,WorkItemClaimRow.self,WorkLeaseRow.self,WorkReleaseRow.self,WorkHandoffRow.self,
            FieldDraftCheckpointRow.self,AttachmentStagingItemRow.self,DraftCommitSagaRow.self,DraftContentReservationRow.self,DraftCommitReceiptRow.self,DraftDiscardReceiptRow.self,
            PromotedPackageReleaseRow.self,PackageSandboxRunRow.self,PackagePromotionReceiptRow.self,ActivePackageRegistryPointerRow.self,
            InstrumentReferenceRow.self,CalibrationStatusSnapshotRow.self,MeasurementCaptureRow.self,MeasurementSeriesRow.self,MeasurementQualityAssessmentRow.self,
            PrivacyTransformPolicyRow.self,PrivacyRegionRow.self,PrivacyTransformManifestRow.self,PrivacyReviewReceiptRow.self,
            ClientCapabilityProfileRow.self,ClientCapabilityAdmissionDecisionRow.self,PackageLifecyclePolicyRow.self,PackageLifecycleDispositionRow.self,
            RecoverabilityVerificationReceiptRow.self,
            FieldReferenceReleaseRow.self,FieldReferenceBindingRow.self,
            AccessibleDocumentAssessmentReceiptRow.self,
            SurveyDefinitionIdentityRow.self,SurveyDefinitionReleaseRow.self,
            SurveySessionRow.self,FactCaptureRow.self,ProvisionalSubjectRow.self,SubjectPromotionReceiptRow.self,SurveyPublicationSnapshotRow.self,
            AssetLocatorRow.self,LocatorBindingReceiptRow.self,
            ScheduleDefinitionReleaseRow.self,OccurrenceHistoryEventRow.self,
            PlanDocumentRow.self,PlanRevisionRow.self,PlanPlacementRow.self,RebaseReceiptRow.self,
            AssetPoseEventRow.self,SpatialAnchorObservationRow.self,
            EvidenceContextRow.self,PairedObservationLinkRow.self,
            LightingSystemRow.self,LightingObservationRow.self,LightingIssueRow.self,MeasurementPlanRow.self,LightingClaimStateRow.self,
            AssistanceAcceptanceReceiptRow.self,
            TemporalEvidenceClipRow.self,TimecodedEvidenceAnchorRow.self,
            AcceptedLabelGenerationSnapshotRow.self,
        ]
        let runtimeNames = PersistentSchemaV34.models.map { modelType in
            String(describing: modelType)
                .split(separator: ".")
                .last
                .map(String.init) ?? ""
        }.sorted()
        let frozenNames = PersistentSchemaV5.models.map { modelType in
            String(describing: modelType).split(separator: ".").last.map(String.init) ?? ""
        }.sorted()
        guard PersistentSchemaV5.models.count == frozenV5.count,
              Set(PersistentSchemaV5.models.map { ObjectIdentifier($0) })
                == Set(frozenV5.map { ObjectIdentifier($0) }),
              frozenNames == persistentModelNames,
              PersistentSchemaV34.models.count == 113,
              PersistentSchemaV34.models.count == expected.count,
              Set(PersistentSchemaV34.models.map { ObjectIdentifier($0) })
                == Set(expected.map { ObjectIdentifier($0) }),
              runtimeNames.count == Set(runtimeNames).count,
              runtimeNames.allSatisfy(ReplicationContractValidationV1.validToken),
              runtimeNames == activePersistentModelNames,
              Set(persistentModelNames)
                == Set(SyncClassificationRegistryV1.persistentModelNames + ["ObservationAndTimeRow"]) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func validateOwnedFileClasses() throws {
        let observed = OwnedFileKindV1.allCases.map(\.rawValue).sorted()
        guard observed == ownedFileClassNames,
              ownedFileClassNames == SyncClassificationRegistryV1.ownedFileClassNames else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    func requireExactCategory(
        _ subjects: [SyncSubjectIdentityV1],
        category: SyncSubjectCategoryV1,
        expectedNames: [String]
    ) throws {
        guard subjects.allSatisfy({ $0.category == category }),
              subjects.map(\.stableName).sorted() == expectedNames.sorted(),
              Set(subjects).count == subjects.count else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func subjects(
        category: SyncSubjectCategoryV1,
        names: [String]
    ) throws -> [SyncSubjectIdentityV1] {
        try names.map { try subject(category: category, name: $0) }
            .sorted { $0.canonicalKey < $1.canonicalKey }
    }

    static func subject(
        category: SyncSubjectCategoryV1,
        name: String
    ) throws -> SyncSubjectIdentityV1 {
        try SyncSubjectIdentityV1(category: category, stableName: name)
    }
}

enum C45AcceptedLabelSyncBoundaryV1 { static let acceptedSnapshotIsDeviceLocalDurable=true;static let projectionBytesAreSynced=false }

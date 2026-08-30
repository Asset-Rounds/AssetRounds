import Foundation
import SwiftData

enum PersistentReferenceStorageDisposition: String, Equatable, Sendable {
    case none = "NONE"
    case applicationGovernedScalarUUID = "APPLICATION_GOVERNED_SCALAR_UUID"
}

enum PersistentSwiftDataDeleteRuleDisposition: String, Equatable, Sendable {
    case noneNoSwiftDataRelationship = "NONE_NO_SWIFTDATA_RELATIONSHIP"
}

enum PersistentScalarReferenceTargetModel: String, Equatable, Sendable {
    case site = "Site"
    case asset = "Asset"
    case workflowRecord = "WorkflowRecord"
    case evidenceFile = "EvidenceFile"
    case issue = "Issue"
    case packet = "Packet"
    case report = "Report"
}

struct PersistentScalarReferenceRegistration: Equatable, Sendable {
    let field: String
    let targetModel: PersistentScalarReferenceTargetModel
}

enum PersistentApplicationDeleteDisposition: String, Equatable, Sendable {
    case preserveEmptySiteUnlessExplicitlyDeleted =
        "PRESERVE_EMPTY_SITE_UNLESS_EXPLICITLY_DELETED"
    case deleteSelectedAssetAfterDependents =
        "DELETE_SELECTED_ASSET_AFTER_DEPENDENTS"
    case deleteSelectedAssetWorkflowRecords =
        "DELETE_SELECTED_ASSET_WORKFLOW_RECORDS"
    case deleteSelectedRecordEvidence =
        "DELETE_SELECTED_RECORD_EVIDENCE"
    case deleteSelectedAssetIssues =
        "DELETE_SELECTED_ASSET_ISSUES"
    case deleteUncountedPacketOrTombstoneCountedPacket =
        "DELETE_UNCOUNTED_PACKET_OR_TOMBSTONE_COUNTED_PACKET"
    case deleteSelectedPacketReports =
        "DELETE_SELECTED_PACKET_REPORTS"
}

struct PersistentModelRegistration {
    let stableName: String
    let modelType: any PersistentModel.Type
    let scalarReferences: [PersistentScalarReferenceRegistration]
    let referenceStorageDisposition: PersistentReferenceStorageDisposition
    let swiftDataDeleteRuleDisposition: PersistentSwiftDataDeleteRuleDisposition
    let applicationDeleteRuleOwner: String
    let applicationDeleteDisposition: PersistentApplicationDeleteDisposition

    var scalarReferenceFields: [String] {
        scalarReferences.map(\.field)
    }
}

enum PersistentModelCatalog {
    static let applicationDeleteRuleOwner =
        "WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)"

    static let registrations: [PersistentModelRegistration] = [
        PersistentModelRegistration(
            stableName: "Site",
            modelType: Site.self,
            scalarReferences: [],
            referenceStorageDisposition: .none,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition:
                .preserveEmptySiteUnlessExplicitlyDeleted
        ),
        PersistentModelRegistration(
            stableName: "Asset",
            modelType: Asset.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "siteID",
                    targetModel: .site
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedAssetAfterDependents
        ),
        PersistentModelRegistration(
            stableName: "WorkflowRecord",
            modelType: WorkflowRecord.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "assetID",
                    targetModel: .asset
                ),
                PersistentScalarReferenceRegistration(
                    field: "packetID",
                    targetModel: .packet
                ),
                PersistentScalarReferenceRegistration(
                    field: "issueID",
                    targetModel: .issue
                ),
                PersistentScalarReferenceRegistration(
                    field: "parentRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "recordRevisionRootID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "revisesRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "evidenceSourceRecordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedAssetWorkflowRecords
        ),
        PersistentModelRegistration(
            stableName: "EvidenceFile",
            modelType: EvidenceFile.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "recordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedRecordEvidence
        ),
        PersistentModelRegistration(
            stableName: "Issue",
            modelType: Issue.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "assetID",
                    targetModel: .asset
                ),
                PersistentScalarReferenceRegistration(
                    field: "openedByRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "resolvedByRecordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedAssetIssues
        ),
        PersistentModelRegistration(
            stableName: "Packet",
            modelType: Packet.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "stableRootID",
                    targetModel: .packet
                ),
                PersistentScalarReferenceRegistration(
                    field: "currentRecordID",
                    targetModel: .workflowRecord
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition:
                .deleteUncountedPacketOrTombstoneCountedPacket
        ),
        PersistentModelRegistration(
            stableName: "Report",
            modelType: Report.self,
            scalarReferences: [
                PersistentScalarReferenceRegistration(
                    field: "packetID",
                    targetModel: .packet
                ),
                PersistentScalarReferenceRegistration(
                    field: "sourceRecordID",
                    targetModel: .workflowRecord
                ),
                PersistentScalarReferenceRegistration(
                    field: "replacesReportID",
                    targetModel: .report
                ),
            ],
            referenceStorageDisposition: .applicationGovernedScalarUUID,
            swiftDataDeleteRuleDisposition: .noneNoSwiftDataRelationship,
            applicationDeleteRuleOwner: applicationDeleteRuleOwner,
            applicationDeleteDisposition: .deleteSelectedPacketReports
        ),
    ]

    static var models: [any PersistentModel.Type] {
        registrations.map(\.modelType)
    }

}

enum PersistentSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentModelCatalog.models
    }

    static func makeSchema() -> Schema {
        Schema(models, version: versionIdentifier)
    }
}

@Model
final class PersistentSchemaReleaseMarker {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var releaseID: String
    var predecessorReleaseID: String?
    var migrationID: UUID?

    init(
        id: UUID,
        schemaVersion: Int,
        releaseID: String,
        predecessorReleaseID: String? = nil,
        migrationID: UUID? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.releaseID = releaseID
        self.predecessorReleaseID = predecessorReleaseID
        self.migrationID = migrationID
    }
}

/// Successor with one directly persisted release marker. The release registry
/// below owns the active V1-to-V2 migration plan.
enum PersistentSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentModelCatalog.models + [PersistentSchemaReleaseMarker.self]
    }
}

/// V3 adds only the privacy-minimal append-only deletion ledger. The seven
/// content models and the V2 release marker retain their exact model types.
enum PersistentSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV2.models + [DeletionLedgerRow.self]
    }
}

/// V4 adds the durable local mutation journal and revision state. Existing
/// content and deletion-ledger model identities remain unchanged.
enum PersistentSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV3.models + [
            MutationReceiptRow.self,
            MutationQuarantineRow.self,
            WorkspaceMutationStateRow.self,
            EntityMutationRevisionRow.self,
        ]
    }
}

/// V5 preserves every V4 model identity and adds a separately versioned
/// companion row for the canonical observation/time pair.
enum PersistentSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV4.models + [ObservationAndTimeRow.self]
    }
}

/// V6 preserves the frozen V5 fourteen-model universe and adds the closed
/// location hierarchy, immutable placement/composition history, and migration
/// receipt rows owned by Card 41.
enum PersistentSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV5.models + [
            LocationNodeRow.self,
            LocationHierarchyEventRow.self,
            AssetPlacementEventRow.self,
            AssetCompositionEdgeRow.self,
            AssetCompositionEventRow.self,
            LocationMigrationReceiptRow.self,
        ]
    }
}

/// V7 is the canonical WorkspaceID-scoped saved-smart-view successor. The
/// search index remains a separate derived file and is intentionally absent.
enum PersistentSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV6.models + [SavedSmartViewRowV1.self]
    }
}

/// V8 adds exactly one canonical assurance companion per WorkflowRecord. The
/// derived search index remains outside SwiftData and no fifth search root is
/// introduced.
enum PersistentSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        PersistentSchemaV7.models + [RequirementAssuranceRow.self]
    }
}

/// V9 adds only C38 party/accountability truth. A migrated V8 generation starts
/// with empty collections: legacy Site labels are not fabricated as parties.
enum PersistentSchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)
    static var models: [any PersistentModel.Type] {
        PersistentSchemaV8.models + [
            ServicePartyRow.self, SitePartyRoleEventRow.self,
            ActorSnapshotRow.self, QualificationSnapshotRow.self,
            SignoffSnapshotRow.self,
        ]
    }
}

/// V10 adds C39 asset-semantic history while retaining `Asset` as the one
/// physical identity row. StoreGenerationFactory performs the deterministic
/// legacy sign-kind/package-binding backfill after cloning the V9 generation.
enum PersistentSchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)
    static var models: [any PersistentModel.Type] {
        PersistentSchemaV9.models + [
            AssetKindBindingEventRow.self,
            AssetWorkflowCapabilityBindingEventRow.self,
            AssetProductIdentityRow.self,
            AssetLifecycleEventRow.self,
            AssetSuccessorLinkRow.self,
            WorkSubjectScopeSnapshotRow.self,
        ]
    }
}

/// V11 adds only explicitly authored C40 authority, applicability, severity,
/// measurement, and derivation records. Migration from V10 is deliberately
/// empty because no such fact can be inferred from legacy workspace bytes.
enum PersistentSchemaV11: VersionedSchema {
    static let versionIdentifier = Schema.Version(11, 0, 0)
    static var models: [any PersistentModel.Type] {
        PersistentSchemaV10.models + [
            AuthoritySourceReleaseRow.self,
            RequirementBasisBindingRow.self,
            ApplicabilityContextSnapshotRow.self,
            AssessmentScopeSnapshotRow.self,
            SeverityScaleReleaseRow.self,
            FindingClassificationBindingRow.self,
            MeasurementProtocolReleaseRow.self,
            DerivedFactEvaluatorDescriptorRow.self,
            DerivedFactProvenanceRow.self,
        ]
    }
}

/// V12 adds C41's immutable descriptor and relationship-event histories. The
/// current functional topology remains a deterministic projection of events.
enum PersistentSchemaV12: VersionedSchema {
    static let versionIdentifier = Schema.Version(12, 0, 0)
    static var models: [any PersistentModel.Type] {
        PersistentSchemaV11.models + [
            FunctionalRelationshipTypeDescriptorRow.self,
            AssetFunctionalRelationshipEventRow.self,
        ]
    }
}

enum PersistentSchemaV13: VersionedSchema {
    static let versionIdentifier = Schema.Version(13, 0, 0)
    static var models: [any PersistentModel.Type] { PersistentSchemaV12.models + [
        EvidenceVisibilityRow.self, ClaimEvidenceLinkRow.self,
        AssuranceManifestRow.self, AttestationRow.self,
    ] }
}
enum PersistentSchemaV14:VersionedSchema{static let versionIdentifier=Schema.Version(14,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV13.models+[InspectionReviewTransitionRow.self,ReviewDispositionRow.self,ChangeRequestRow.self,CorrectiveActionPolicyRow.self,CorrectiveActionEventRow.self]}}
enum PersistentSchemaV15:VersionedSchema{static let versionIdentifier=Schema.Version(15,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV14.models+[WorkPacketManifestRow.self,WorkItemClaimRow.self,WorkLeaseRow.self,WorkReleaseRow.self,WorkHandoffRow.self]}}
enum PersistentSchemaV16:VersionedSchema{static let versionIdentifier=Schema.Version(16,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV15.models+[FieldDraftCheckpointRow.self,AttachmentStagingItemRow.self,DraftCommitSagaRow.self,DraftContentReservationRow.self,DraftCommitReceiptRow.self,DraftDiscardReceiptRow.self]}}
enum PersistentSchemaV17:VersionedSchema{static let versionIdentifier=Schema.Version(17,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV16.models+[PromotedPackageReleaseRow.self,PackageSandboxRunRow.self,PackagePromotionReceiptRow.self,ActivePackageRegistryPointerRow.self]}}
enum PersistentSchemaV18:VersionedSchema{static let versionIdentifier=Schema.Version(18,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV17.models+[InstrumentReferenceRow.self,CalibrationStatusSnapshotRow.self,MeasurementCaptureRow.self,MeasurementSeriesRow.self,MeasurementQualityAssessmentRow.self]}}
enum PersistentSchemaV19:VersionedSchema{static let versionIdentifier=Schema.Version(19,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV18.models+[PrivacyTransformPolicyRow.self,PrivacyRegionRow.self,PrivacyTransformManifestRow.self,PrivacyReviewReceiptRow.self]}}
enum PersistentSchemaV20:VersionedSchema{static let versionIdentifier=Schema.Version(20,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV19.models+[ClientCapabilityProfileRow.self,ClientCapabilityAdmissionDecisionRow.self,PackageLifecyclePolicyRow.self,PackageLifecycleDispositionRow.self]}}
enum PersistentSchemaV21:VersionedSchema{static let versionIdentifier=Schema.Version(21,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV20.models+[RecoverabilityVerificationReceiptRow.self]}}
enum PersistentSchemaV22:VersionedSchema{static let versionIdentifier=Schema.Version(22,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV21.models+[FieldReferenceReleaseRow.self,FieldReferenceBindingRow.self]}}
enum PersistentSchemaV23:VersionedSchema{static let versionIdentifier=Schema.Version(23,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV22.models+[AccessibleDocumentAssessmentReceiptRow.self]}}
enum PersistentSchemaV24:VersionedSchema{static let versionIdentifier=Schema.Version(24,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV23.models+[SurveyDefinitionIdentityRow.self,SurveyDefinitionReleaseRow.self]}}
enum PersistentSchemaV25:VersionedSchema{static let versionIdentifier=Schema.Version(25,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV24.models+[SurveySessionRow.self,FactCaptureRow.self,ProvisionalSubjectRow.self,SubjectPromotionReceiptRow.self,SurveyPublicationSnapshotRow.self]}}
enum PersistentSchemaV26:VersionedSchema{static let versionIdentifier=Schema.Version(26,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV25.models+[AssetLocatorRow.self,LocatorBindingReceiptRow.self]}}
enum PersistentSchemaV27:VersionedSchema{static let versionIdentifier=Schema.Version(27,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV26.models+[ScheduleDefinitionReleaseRow.self,OccurrenceHistoryEventRow.self]}}
enum PersistentSchemaV28:VersionedSchema{static let versionIdentifier=Schema.Version(28,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV27.models+[PlanDocumentRow.self,PlanRevisionRow.self,PlanPlacementRow.self,RebaseReceiptRow.self]}}
enum PersistentSchemaV29:VersionedSchema{static let versionIdentifier=Schema.Version(29,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV28.models+[AssetPoseEventRow.self,SpatialAnchorObservationRow.self]}}
enum PersistentSchemaV30:VersionedSchema{static let versionIdentifier=Schema.Version(30,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV29.models+[EvidenceContextRow.self,PairedObservationLinkRow.self]}}
enum PersistentSchemaV31:VersionedSchema{static let versionIdentifier=Schema.Version(31,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV30.models+[LightingSystemRow.self,LightingObservationRow.self,LightingIssueRow.self,MeasurementPlanRow.self,LightingClaimStateRow.self]}}
enum PersistentSchemaV32:VersionedSchema{static let versionIdentifier=Schema.Version(32,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV31.models+[AssistanceAcceptanceReceiptRow.self]}}
enum PersistentSchemaV33:VersionedSchema{static let versionIdentifier=Schema.Version(33,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV32.models+[TemporalEvidenceClipRow.self,TimecodedEvidenceAnchorRow.self]}}
enum PersistentSchemaV34:VersionedSchema{static let versionIdentifier=Schema.Version(34,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV33.models+[AcceptedLabelGenerationSnapshotRow.self]}}
enum PersistentSchemaV35:VersionedSchema{static let versionIdentifier=Schema.Version(35,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV34.models+[ServiceContactPointRow.self,SystemHandoffIntentRow.self]}}
enum PersistentSchemaV36:VersionedSchema{static let versionIdentifier=Schema.Version(36,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV35.models+[ActivitySessionEnvelopeRow.self,ActivityStateTransitionRow.self,InstallationTaskResultRow.self,InstallationAsBuiltSnapshotRow.self,PunchReviewBasisSnapshotRow.self]}}
enum PersistentSchemaV37:VersionedSchema{static let versionIdentifier=Schema.Version(37,0,0);static var models:[any PersistentModel.Type]{PersistentSchemaV36.models+[ManualWorkResourceRecordRow.self]}}

enum PersistentSchemaMigrationStageV1: String, Equatable, Sendable {
    case bootstrap = "BOOTSTRAP"
    case lightweight = "LIGHTWEIGHT"
    case custom = "CUSTOM"
}

/// Card 29 versions the lifecycle-policy contract independently from the
/// SwiftData model universe. It intentionally binds V1 policy to store V5 and
/// does not invent a V6 schema or entity.
enum PersistentLifecycleContractReleaseV1: String, Codable, Equatable, Sendable {
    case v1 = "PERSISTENT_LIFECYCLE_POLICY_V1"

    var schemaVersion: Int { 1 }
    var boundStoreRelease: PersistentSchemaReleaseV1 { .v5 }
    var predecessor: PersistentLifecycleContractReleaseV1? { nil }
}

enum PersistentLifecycleContractReleaseRegistryV1 {
    static let releases: [PersistentLifecycleContractReleaseV1] = [.v1]
    static let activeRelease: PersistentLifecycleContractReleaseV1 = .v1

    static func validate() throws {
        guard releases == [.v1],
              activeRelease == .v1,
              activeRelease.schemaVersion == PersistentKindLifecycleRegistryV1.schemaVersion,
              activeRelease.rawValue == PersistentKindLifecycleRegistryV1.schemaID,
              activeRelease.boundStoreRelease == .v5,
              activeRelease.predecessor == nil else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidActiveRelease
        }
    }
}

/// Stable release identity used by manifests/journals as well as the runtime
/// registry. The descriptor values are computed from the canonical schemas so
/// a persisted release cannot silently acquire a second source of truth.
enum PersistentSchemaReleaseV1: String, Codable, Equatable, Sendable {
    case v1 = "V1"
    case v2 = "V2"
    case v3 = "V3"
    case v4 = "V4"
    case v5 = "V5"
    case v6 = "V6"
    case v7 = "V7"
    case v8 = "V8"
    case v9 = "V9"
    case v10 = "V10"
    case v11 = "V11"
    case v12 = "V12"
    case v13 = "V13"
    case v14 = "V14"
    case v15 = "V15"
    case v16 = "V16"
    case v17 = "V17"
    case v18 = "V18"
    case v19 = "V19"
    case v20 = "V20"
    case v21 = "V21"
    case v22 = "V22"
    case v23 = "V23"
    case v24 = "V24"
    case v25 = "V25"
    case v26 = "V26"
    case v27 = "V27"
    case v28 = "V28"
    case v29 = "V29"
    case v30 = "V30"
    case v31 = "V31"
    case v32 = "V32"
    case v33 = "V33"
    case v34 = "V34"
    case v35 = "V35"
    case v36 = "V36"
    case v37 = "V37"

    var compatibilityID: String {
        switch self {
        case .v1: return "FIELD_EVIDENCE_SCHEMA_V1"
        case .v2: return "FIELD_EVIDENCE_SCHEMA_V2"
        case .v3: return "FIELD_EVIDENCE_SCHEMA_V3_TOMBSTONES"
        case .v4: return "FIELD_EVIDENCE_SCHEMA_V4_MUTATION_RECEIPTS"
        case .v5: return "FIELD_EVIDENCE_SCHEMA_V5_OBSERVATION_AND_TIME"
        case .v6: return "FIELD_EVIDENCE_SCHEMA_V6_LOCATION_PLACEMENT_COMPOSITION"
        case .v7: return "FIELD_EVIDENCE_SCHEMA_V7_SAVED_SMART_VIEW_DESCRIPTOR"
        case .v8: return "FIELD_EVIDENCE_SCHEMA_V8_REQUIREMENT_ASSURANCE"
        case .v9: return "FIELD_EVIDENCE_SCHEMA_V9_PARTY_ACCOUNTABILITY"
        case .v10: return "FIELD_EVIDENCE_SCHEMA_V10_ASSET_SEMANTICS"
        case .v11: return "PERSISTENT_SCHEMA_V11_AUTHORITY_CRITERION_DERIVATION"
        case .v12: return "PERSISTENT_SCHEMA_V12_FUNCTIONAL_RELATIONSHIP_HISTORY"
        case .v13: return "PERSISTENT_SCHEMA_V13_EVIDENCE_ASSURANCE_HISTORY"
        case .v14:return "PERSISTENT_SCHEMA_V14_REVIEW_CORRECTIVE_HISTORY"
        case .v15:return "PERSISTENT_SCHEMA_V15_WORK_PACKET_HISTORY"
        case .v16:return "PERSISTENT_SCHEMA_V16_FIELD_DRAFT_RESILIENCE"
        case .v17:return "PERSISTENT_SCHEMA_V17_PACKAGE_EVOLUTION"
        case .v18:return "MEASUREMENT_INTEGRITY_V1"
        case .v19:return "PRIVACY_TRANSFORM_V1"
        case .v20:return "CLIENT_CAPABILITY_NEGOTIATION_V1"
        case .v21:return "RECOVERABILITY_VERIFICATION_V1"
        case .v22:return "FIELD_REFERENCE_PACK_V1"
        case .v23:return "ACCESSIBLE_DOCUMENT_ASSESSMENT_V1"
        case .v24:return "SURVEY_DEFINITION_V1"
        case .v25:return "GUIDED_SURVEY_SESSION_V1"
        case .v26:return "ASSET_LOCATOR_V1"
        case .v27:return "DETERMINISTIC_SCHEDULE_V1"
        case .v28:return "PLAN_DOCUMENT_V1"
        case .v29:return "PLACEMENT_POSE_V1"
        case .v30:return "EVIDENCE_CONTEXT_V1"
        case .v31:return "EXTERIOR_LIGHTING_PACKAGE_V1"
        case .v32:return "ASSISTANCE_ACCEPTANCE_RECEIPT_V1"
        case .v33:return "TEMPORAL_EVIDENCE_V1"
        case .v34:return "ASSET_LABEL_ACCEPTED_GENERATION_V1"
        case .v35:return "OPERATIONAL_CONTACT_V1"
        case .v36:return "ACTIVITY_CONTRACT_FAMILIES_V2"
        case .v37:return "WORK_RESOURCE_ENTRY_V1"
        }
    }

    var versionIdentifier: Schema.Version {
        switch self {
        case .v1: return PersistentSchemaV1.versionIdentifier
        case .v2: return PersistentSchemaV2.versionIdentifier
        case .v3: return PersistentSchemaV3.versionIdentifier
        case .v4: return PersistentSchemaV4.versionIdentifier
        case .v5: return PersistentSchemaV5.versionIdentifier
        case .v6: return PersistentSchemaV6.versionIdentifier
        case .v7: return PersistentSchemaV7.versionIdentifier
        case .v8: return PersistentSchemaV8.versionIdentifier
        case .v9: return PersistentSchemaV9.versionIdentifier
        case .v10: return PersistentSchemaV10.versionIdentifier
        case .v11: return PersistentSchemaV11.versionIdentifier
        case .v12: return PersistentSchemaV12.versionIdentifier
        case .v13: return PersistentSchemaV13.versionIdentifier
        case .v14:return PersistentSchemaV14.versionIdentifier
        case .v15:return PersistentSchemaV15.versionIdentifier
        case .v16:return PersistentSchemaV16.versionIdentifier
        case .v17:return PersistentSchemaV17.versionIdentifier
        case .v18:return PersistentSchemaV18.versionIdentifier
        case .v19:return PersistentSchemaV19.versionIdentifier
        case .v20:return PersistentSchemaV20.versionIdentifier
        case .v21:return PersistentSchemaV21.versionIdentifier
        case .v22:return PersistentSchemaV22.versionIdentifier
        case .v23:return PersistentSchemaV23.versionIdentifier
        case .v24:return PersistentSchemaV24.versionIdentifier
        case .v25:return PersistentSchemaV25.versionIdentifier
        case .v26:return PersistentSchemaV26.versionIdentifier
        case .v27:return PersistentSchemaV27.versionIdentifier
        case .v28:return PersistentSchemaV28.versionIdentifier
        case .v29:return PersistentSchemaV29.versionIdentifier
        case .v30:return PersistentSchemaV30.versionIdentifier
        case .v31:return PersistentSchemaV31.versionIdentifier
        case .v32:return PersistentSchemaV32.versionIdentifier
        case .v33:return PersistentSchemaV33.versionIdentifier
        case .v34:return PersistentSchemaV34.versionIdentifier
        case .v35:return PersistentSchemaV35.versionIdentifier
        case .v36:return PersistentSchemaV36.versionIdentifier
        case .v37:return PersistentSchemaV37.versionIdentifier
        }
    }

    var predecessorVersionIdentifier: Schema.Version? {
        switch self {
        case .v1: return nil
        case .v2: return PersistentSchemaV1.versionIdentifier
        case .v3: return PersistentSchemaV2.versionIdentifier
        case .v4: return PersistentSchemaV3.versionIdentifier
        case .v5: return PersistentSchemaV4.versionIdentifier
        case .v6: return PersistentSchemaV5.versionIdentifier
        case .v7: return PersistentSchemaV6.versionIdentifier
        case .v8: return PersistentSchemaV7.versionIdentifier
        case .v9: return PersistentSchemaV8.versionIdentifier
        case .v10: return PersistentSchemaV9.versionIdentifier
        case .v11: return PersistentSchemaV10.versionIdentifier
        case .v12: return PersistentSchemaV11.versionIdentifier
        case .v13: return PersistentSchemaV12.versionIdentifier
        case .v14:return PersistentSchemaV13.versionIdentifier
        case .v15:return PersistentSchemaV14.versionIdentifier
        case .v16:return PersistentSchemaV15.versionIdentifier
        case .v17:return PersistentSchemaV16.versionIdentifier
        case .v18:return PersistentSchemaV17.versionIdentifier
        case .v19:return PersistentSchemaV18.versionIdentifier
        case .v20:return PersistentSchemaV19.versionIdentifier
        case .v21:return PersistentSchemaV20.versionIdentifier
        case .v22:return PersistentSchemaV21.versionIdentifier
        case .v23:return PersistentSchemaV22.versionIdentifier
        case .v24:return PersistentSchemaV23.versionIdentifier
        case .v25:return PersistentSchemaV24.versionIdentifier
        case .v26:return PersistentSchemaV25.versionIdentifier
        case .v27:return PersistentSchemaV26.versionIdentifier
        case .v28:return PersistentSchemaV27.versionIdentifier
        case .v29:return PersistentSchemaV28.versionIdentifier
        case .v30:return PersistentSchemaV29.versionIdentifier
        case .v31:return PersistentSchemaV30.versionIdentifier
        case .v32:return PersistentSchemaV31.versionIdentifier
        case .v33:return PersistentSchemaV32.versionIdentifier
        case .v34:return PersistentSchemaV33.versionIdentifier
        case .v35:return PersistentSchemaV34.versionIdentifier
        case .v36:return PersistentSchemaV35.versionIdentifier
        case .v37:return PersistentSchemaV36.versionIdentifier
        }
    }

    var models: [any PersistentModel.Type] {
        switch self {
        case .v1: return PersistentSchemaV1.models
        case .v2: return PersistentSchemaV2.models
        case .v3: return PersistentSchemaV3.models
        case .v4: return PersistentSchemaV4.models
        case .v5: return PersistentSchemaV5.models
        case .v6: return PersistentSchemaV6.models
        case .v7: return PersistentSchemaV7.models
        case .v8: return PersistentSchemaV8.models
        case .v9: return PersistentSchemaV9.models
        case .v10: return PersistentSchemaV10.models
        case .v11: return PersistentSchemaV11.models
        case .v12: return PersistentSchemaV12.models
        case .v13: return PersistentSchemaV13.models
        case .v14:return PersistentSchemaV14.models
        case .v15:return PersistentSchemaV15.models
        case .v16:return PersistentSchemaV16.models
        case .v17:return PersistentSchemaV17.models
        case .v18:return PersistentSchemaV18.models
        case .v19:return PersistentSchemaV19.models
        case .v20:return PersistentSchemaV20.models
        case .v21:return PersistentSchemaV21.models
        case .v22:return PersistentSchemaV22.models
        case .v23:return PersistentSchemaV23.models
        case .v24:return PersistentSchemaV24.models
        case .v25:return PersistentSchemaV25.models
        case .v26:return PersistentSchemaV26.models
        case .v27:return PersistentSchemaV27.models
        case .v28:return PersistentSchemaV28.models
        case .v29:return PersistentSchemaV29.models
        case .v30:return PersistentSchemaV30.models
        case .v31:return PersistentSchemaV31.models
        case .v32:return PersistentSchemaV32.models
        case .v33:return PersistentSchemaV33.models
        case .v34:return PersistentSchemaV34.models
        case .v35:return PersistentSchemaV35.models
        case .v36:return PersistentSchemaV36.models
        case .v37:return PersistentSchemaV37.models
        }
    }

    var migrationStage: PersistentSchemaMigrationStageV1 {
        switch self {
        case .v1: return .bootstrap
        case .v2, .v3, .v4: return .lightweight
        case .v5, .v6, .v7, .v8, .v9, .v10, .v11, .v12, .v13, .v14, .v15, .v16, .v17, .v18, .v19, .v20, .v21, .v22, .v23, .v24, .v25, .v26, .v27, .v28, .v29, .v30, .v31, .v32, .v33, .v34, .v35, .v36, .v37: return .custom
        }
    }
}

enum PersistentSchemaReleaseRegistryErrorV1: Error, Equatable, Sendable {
    case invalidReleaseCount
    case emptyCompatibilityID
    case duplicateCompatibilityID
    case duplicateVersionIdentifier
    case unorderedVersionIdentifiers
    case invalidBootstrapRelease
    case invalidSuccessorRelease
    case invalidActiveRelease
    case unknownVersion
}

enum PersistentSchemaMigrationPlanV1: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV1.self, PersistentSchemaV2.self]
    }

    static let migrateV1ToV2 = MigrationStage.lightweight(
        fromVersion: PersistentSchemaV1.self,
        toVersion: PersistentSchemaV2.self
    )

    static var stages: [MigrationStage] {
        [migrateV1ToV2]
    }
}

enum PersistentSchemaMigrationPlanV2: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV2.self, PersistentSchemaV3.self]
    }

    static let migrateV2ToV3 = MigrationStage.lightweight(
        fromVersion: PersistentSchemaV2.self,
        toVersion: PersistentSchemaV3.self
    )

    static var stages: [MigrationStage] {
        [migrateV2ToV3]
    }
}

enum PersistentSchemaMigrationPlanV3: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV3.self, PersistentSchemaV4.self]
    }

    static let migrateV3ToV4 = MigrationStage.lightweight(
        fromVersion: PersistentSchemaV3.self,
        toVersion: PersistentSchemaV4.self
    )

    static var stages: [MigrationStage] { [migrateV3ToV4] }
}

enum PersistentSchemaMigrationPlanV4: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV4.self, PersistentSchemaV5.self]
    }

    static let migrateV4ToV5 = MigrationStage.custom(
        fromVersion: PersistentSchemaV4.self,
        toVersion: PersistentSchemaV5.self,
        willMigrate: nil,
        didMigrate: { context in
            var descriptor = FetchDescriptor<WorkflowRecord>()
            descriptor.fetchLimit = ObservationAndTimeRowStoreV1.maximumRows + 1
            let records = try context.fetch(descriptor)
            guard records.count <= ObservationAndTimeRowStoreV1.maximumRows else {
                throw ObservationAndTimeRowFailureV1.rowLimitExceeded
            }
            for record in records {
                context.insert(try ObservationAndTimeStoreMigrationV1.row(
                    for: record
                ))
            }
            if context.hasChanges {
                try context.save()
            }
        }
    )

    static var stages: [MigrationStage] { [migrateV4ToV5] }
}

enum PersistentSchemaMigrationPlanV5: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV5.self, PersistentSchemaV6.self]
    }

    // Generation- and workspace-bound baseline rows are inserted and
    // revalidated by StoreGenerationFactory after SwiftData has advanced the
    // cloned store. Keeping the schema stage side-effect free prevents it from
    // fabricating generation identity that is unavailable to this callback.
    static let migrateV5ToV6 = MigrationStage.custom(
        fromVersion: PersistentSchemaV5.self,
        toVersion: PersistentSchemaV6.self,
        willMigrate: nil,
        didMigrate: { _ in }
    )

    static var stages: [MigrationStage] { [migrateV5ToV6] }
}

enum PersistentSchemaMigrationPlanV6: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV6.self, PersistentSchemaV7.self]
    }

    // V7 adds an empty canonical collection. Saved views are created only by
    // the WorkspaceWriter after migration, never fabricated by the migration.
    static let migrateV6ToV7 = MigrationStage.custom(
        fromVersion: PersistentSchemaV6.self,
        toVersion: PersistentSchemaV7.self,
        willMigrate: nil,
        didMigrate: { _ in }
    )

    static var stages: [MigrationStage] { [migrateV6ToV7] }
}

enum PersistentSchemaMigrationPlanV7: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistentSchemaV7.self, PersistentSchemaV8.self]
    }

    // StoreGenerationFactory performs the identity-bound deterministic
    // assurance backfill after SwiftData advances the cloned store.
    static let migrateV7ToV8 = MigrationStage.custom(
        fromVersion: PersistentSchemaV7.self,
        toVersion: PersistentSchemaV8.self,
        willMigrate: nil,
        didMigrate: { _ in }
    )

    static var stages: [MigrationStage] { [migrateV7ToV8] }
}

enum PersistentSchemaMigrationPlanV8: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PersistentSchemaV8.self, PersistentSchemaV9.self] }
    // The containing StoreGenerationFactory clones the source first. No party,
    // actor, role, qualification, or signoff is inferable from legacy bytes.
    static let migrateV8ToV9 = MigrationStage.custom(
        fromVersion: PersistentSchemaV8.self,
        toVersion: PersistentSchemaV9.self,
        willMigrate: nil,
        didMigrate: { _ in }
    )
    static var stages: [MigrationStage] { [migrateV8ToV9] }
}

enum PersistentSchemaMigrationPlanV9: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PersistentSchemaV9.self, PersistentSchemaV10.self] }
    // The factory owns the copy-on-write clone and inserts only deterministic
    // legacy semantic/package bindings derived from existing Asset values.
    static let migrateV9ToV10 = MigrationStage.custom(
        fromVersion: PersistentSchemaV9.self,
        toVersion: PersistentSchemaV10.self,
        willMigrate: nil,
        didMigrate: { _ in }
    )
    static var stages: [MigrationStage] { [migrateV9ToV10] }
}

enum PersistentSchemaMigrationPlanV10: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PersistentSchemaV10.self, PersistentSchemaV11.self] }
    static let migrateV10ToV11 = MigrationStage.custom(
        fromVersion: PersistentSchemaV10.self,
        toVersion: PersistentSchemaV11.self,
        willMigrate: nil,
        didMigrate: { _ in }
    )
    static var stages: [MigrationStage] { [migrateV10ToV11] }
}

enum PersistentSchemaMigrationPlanV11: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PersistentSchemaV11.self, PersistentSchemaV12.self] }
    // No functional relationship can be inferred from legacy workspace data.
    static let migrateV11ToV12 = MigrationStage.custom(
        fromVersion: PersistentSchemaV11.self,
        toVersion: PersistentSchemaV12.self,
        willMigrate: nil,
        didMigrate: { _ in }
    )
    static var stages: [MigrationStage] { [migrateV11ToV12] }
}

enum PersistentSchemaMigrationPlanV12: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PersistentSchemaV12.self, PersistentSchemaV13.self] }
    static let migrateV12ToV13 = MigrationStage.custom(
        fromVersion: PersistentSchemaV12.self, toVersion: PersistentSchemaV13.self,
        willMigrate: nil, didMigrate: { _ in }
    )
    static var stages: [MigrationStage] { [migrateV12ToV13] }
}
enum PersistentSchemaMigrationPlanV13:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV13.self,PersistentSchemaV14.self]};static let migrateV13ToV14=MigrationStage.custom(fromVersion:PersistentSchemaV13.self,toVersion:PersistentSchemaV14.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV13ToV14]}}
enum PersistentSchemaMigrationPlanV14:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV14.self,PersistentSchemaV15.self]};static let migrateV14ToV15=MigrationStage.custom(fromVersion:PersistentSchemaV14.self,toVersion:PersistentSchemaV15.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV14ToV15]}}
enum PersistentSchemaMigrationPlanV15:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV15.self,PersistentSchemaV16.self]};static let migrateV15ToV16=MigrationStage.custom(fromVersion:PersistentSchemaV15.self,toVersion:PersistentSchemaV16.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV15ToV16]}}
enum PersistentSchemaMigrationPlanV16:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV16.self,PersistentSchemaV17.self]};static let migrateV16ToV17=MigrationStage.custom(fromVersion:PersistentSchemaV16.self,toVersion:PersistentSchemaV17.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV16ToV17]}}
enum PersistentSchemaMigrationPlanV17:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV17.self,PersistentSchemaV18.self]};static let migrateV17ToV18=MigrationStage.custom(fromVersion:PersistentSchemaV17.self,toVersion:PersistentSchemaV18.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV17ToV18]}}
enum PersistentSchemaMigrationPlanV18:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV18.self,PersistentSchemaV19.self]};static let migrateV18ToV19=MigrationStage.custom(fromVersion:PersistentSchemaV18.self,toVersion:PersistentSchemaV19.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV18ToV19]}}
enum PersistentSchemaMigrationPlanV19:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV19.self,PersistentSchemaV20.self]};static let migrateV19ToV20=MigrationStage.custom(fromVersion:PersistentSchemaV19.self,toVersion:PersistentSchemaV20.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV19ToV20]}}
enum PersistentSchemaMigrationPlanV20:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV20.self,PersistentSchemaV21.self]};static let migrateV20ToV21=MigrationStage.custom(fromVersion:PersistentSchemaV20.self,toVersion:PersistentSchemaV21.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV20ToV21]}}
enum PersistentSchemaMigrationPlanV21:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV21.self,PersistentSchemaV22.self]};static let migrateV21ToV22=MigrationStage.custom(fromVersion:PersistentSchemaV21.self,toVersion:PersistentSchemaV22.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV21ToV22]}}
enum PersistentSchemaMigrationPlanV22:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV22.self,PersistentSchemaV23.self]};static let migrateV22ToV23=MigrationStage.custom(fromVersion:PersistentSchemaV22.self,toVersion:PersistentSchemaV23.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV22ToV23]}}
enum PersistentSchemaMigrationPlanV23:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV23.self,PersistentSchemaV24.self]};static let migrateV23ToV24=MigrationStage.custom(fromVersion:PersistentSchemaV23.self,toVersion:PersistentSchemaV24.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV23ToV24]}}
enum PersistentSchemaMigrationPlanV24:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV24.self,PersistentSchemaV25.self]};static let migrateV24ToV25=MigrationStage.custom(fromVersion:PersistentSchemaV24.self,toVersion:PersistentSchemaV25.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV24ToV25]}}
enum PersistentSchemaMigrationPlanV25:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV25.self,PersistentSchemaV26.self]};static let migrateV25ToV26=MigrationStage.custom(fromVersion:PersistentSchemaV25.self,toVersion:PersistentSchemaV26.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV25ToV26]}}
enum PersistentSchemaMigrationPlanV26:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV26.self,PersistentSchemaV27.self]};static let migrateV26ToV27=MigrationStage.custom(fromVersion:PersistentSchemaV26.self,toVersion:PersistentSchemaV27.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV26ToV27]}}
enum PersistentSchemaMigrationPlanV27:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV27.self,PersistentSchemaV28.self]};static let migrateV27ToV28=MigrationStage.custom(fromVersion:PersistentSchemaV27.self,toVersion:PersistentSchemaV28.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV27ToV28]}}
enum PersistentSchemaMigrationPlanV28:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV28.self,PersistentSchemaV29.self]};static let migrateV28ToV29=MigrationStage.custom(fromVersion:PersistentSchemaV28.self,toVersion:PersistentSchemaV29.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV28ToV29]}}
enum PersistentSchemaMigrationPlanV29:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV29.self,PersistentSchemaV30.self]};static let migrateV29ToV30=MigrationStage.custom(fromVersion:PersistentSchemaV29.self,toVersion:PersistentSchemaV30.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV29ToV30]}}
enum PersistentSchemaMigrationPlanV30:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV30.self,PersistentSchemaV31.self]};static let migrateV30ToV31=MigrationStage.custom(fromVersion:PersistentSchemaV30.self,toVersion:PersistentSchemaV31.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV30ToV31]}}
enum PersistentSchemaMigrationPlanV31:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV31.self,PersistentSchemaV32.self]};static let migrateV31ToV32=MigrationStage.custom(fromVersion:PersistentSchemaV31.self,toVersion:PersistentSchemaV32.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV31ToV32]}}
enum PersistentSchemaMigrationPlanV32:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV32.self,PersistentSchemaV33.self]};static let migrateV32ToV33=MigrationStage.custom(fromVersion:PersistentSchemaV32.self,toVersion:PersistentSchemaV33.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV32ToV33]}}
enum PersistentSchemaMigrationPlanV33:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV33.self,PersistentSchemaV34.self]};static let migrateV33ToV34=MigrationStage.custom(fromVersion:PersistentSchemaV33.self,toVersion:PersistentSchemaV34.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV33ToV34]}}
enum PersistentSchemaMigrationPlanV34:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV34.self,PersistentSchemaV35.self]};static let migrateV34ToV35=MigrationStage.custom(fromVersion:PersistentSchemaV34.self,toVersion:PersistentSchemaV35.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV34ToV35]}}
enum PersistentSchemaMigrationPlanV35:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV35.self,PersistentSchemaV36.self]};static let migrateV35ToV36=MigrationStage.custom(fromVersion:PersistentSchemaV35.self,toVersion:PersistentSchemaV36.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV35ToV36]}}
enum PersistentSchemaMigrationPlanV36:SchemaMigrationPlan{static var schemas:[any VersionedSchema.Type]{[PersistentSchemaV36.self,PersistentSchemaV37.self]};static let migrateV36ToV37=MigrationStage.custom(fromVersion:PersistentSchemaV36.self,toVersion:PersistentSchemaV37.self,willMigrate:nil,didMigrate:{_ in});static var stages:[MigrationStage]{[migrateV36ToV37]}}

enum PersistentSchemaReleaseRegistryV1 {
    static let v1CompatibilityID = PersistentSchemaReleaseV1.v1.compatibilityID
    static let v2CompatibilityID = PersistentSchemaReleaseV1.v2.compatibilityID
    static let v3CompatibilityID = PersistentSchemaReleaseV1.v3.compatibilityID
    static let v4CompatibilityID = PersistentSchemaReleaseV1.v4.compatibilityID
    static let v5CompatibilityID = PersistentSchemaReleaseV1.v5.compatibilityID
    static let v6CompatibilityID = PersistentSchemaReleaseV1.v6.compatibilityID
    static let v7CompatibilityID = PersistentSchemaReleaseV1.v7.compatibilityID
    static let v8CompatibilityID = PersistentSchemaReleaseV1.v8.compatibilityID
    static let v9CompatibilityID = PersistentSchemaReleaseV1.v9.compatibilityID
    static let v10CompatibilityID = PersistentSchemaReleaseV1.v10.compatibilityID
    static let v11CompatibilityID = PersistentSchemaReleaseV1.v11.compatibilityID
    static let v12CompatibilityID = PersistentSchemaReleaseV1.v12.compatibilityID
    static let v13CompatibilityID = PersistentSchemaReleaseV1.v13.compatibilityID
    static let v14CompatibilityID=PersistentSchemaReleaseV1.v14.compatibilityID
    static let v15CompatibilityID=PersistentSchemaReleaseV1.v15.compatibilityID
    static let v16CompatibilityID=PersistentSchemaReleaseV1.v16.compatibilityID
    static let v17CompatibilityID=PersistentSchemaReleaseV1.v17.compatibilityID
    static let v18CompatibilityID=PersistentSchemaReleaseV1.v18.compatibilityID
    static let v19CompatibilityID=PersistentSchemaReleaseV1.v19.compatibilityID
    static let v20CompatibilityID=PersistentSchemaReleaseV1.v20.compatibilityID
    static let v21CompatibilityID=PersistentSchemaReleaseV1.v21.compatibilityID
    static let v22CompatibilityID=PersistentSchemaReleaseV1.v22.compatibilityID
    static let v23CompatibilityID=PersistentSchemaReleaseV1.v23.compatibilityID
    static let v24CompatibilityID=PersistentSchemaReleaseV1.v24.compatibilityID
    static let v25CompatibilityID=PersistentSchemaReleaseV1.v25.compatibilityID
    static let v26CompatibilityID=PersistentSchemaReleaseV1.v26.compatibilityID
    static let v27CompatibilityID=PersistentSchemaReleaseV1.v27.compatibilityID
    static let v28CompatibilityID=PersistentSchemaReleaseV1.v28.compatibilityID
    static let v29CompatibilityID=PersistentSchemaReleaseV1.v29.compatibilityID
    static let v30CompatibilityID=PersistentSchemaReleaseV1.v30.compatibilityID
    static let v31CompatibilityID=PersistentSchemaReleaseV1.v31.compatibilityID
    static let v32CompatibilityID=PersistentSchemaReleaseV1.v32.compatibilityID
    static let v33CompatibilityID=PersistentSchemaReleaseV1.v33.compatibilityID
    static let v34CompatibilityID=PersistentSchemaReleaseV1.v34.compatibilityID
    static let v35CompatibilityID=PersistentSchemaReleaseV1.v35.compatibilityID
    static let v36CompatibilityID=PersistentSchemaReleaseV1.v36.compatibilityID
    static let v37CompatibilityID=PersistentSchemaReleaseV1.v37.compatibilityID
    static let v2MarkerIDString = "00000000-0000-0000-0000-000000000002"
    static let v2MarkerID = UUID(uuidString: v2MarkerIDString)!

    static let releases: [PersistentSchemaReleaseV1] = [.v1,.v2,.v3,.v4,.v5,.v6,.v7,.v8,.v9,.v10,.v11,.v12,.v13,.v14,.v15,.v16,.v17,.v18,.v19,.v20,.v21,.v22,.v23,.v24,.v25,.v26,.v27,.v28,.v29,.v30,.v31,.v32,.v33,.v34,.v35,.v36,.v37]

    static let activeVersionIdentifier=PersistentSchemaV37.versionIdentifier;static let activeCompatibilityID=v37CompatibilityID

    static var activeRelease: PersistentSchemaReleaseV1 {
        .v37
    }

    static var activeReleaseDescriptor: PersistentSchemaReleaseV1 {
        activeRelease
    }

    static var activeMigrationPlan: any SchemaMigrationPlan.Type {
        PersistentSchemaMigrationPlanV36.self
    }

    static func validate() throws {
        try PersistentLifecycleContractReleaseRegistryV1.validate()
        try validate(releases)
    }

    static func validate(
        _ candidate: [PersistentSchemaReleaseV1]
    ) throws {
        guard candidate.count == 37 else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidReleaseCount
        }

        guard candidate.allSatisfy({ !$0.compatibilityID.isEmpty }) else {
            throw PersistentSchemaReleaseRegistryErrorV1.emptyCompatibilityID
        }
        guard Set(candidate.map(\.compatibilityID)).count == candidate.count else {
            throw PersistentSchemaReleaseRegistryErrorV1.duplicateCompatibilityID
        }

        let versions = candidate.map(\.versionIdentifier)
        guard Set(versions).count == versions.count else {
            throw PersistentSchemaReleaseRegistryErrorV1.duplicateVersionIdentifier
        }
        guard zip(versions, versions.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw PersistentSchemaReleaseRegistryErrorV1.unorderedVersionIdentifiers
        }

        let expectedV1ModelIDs = PersistentModelCatalog.models.map {
            ObjectIdentifier($0)
        }
        let expectedV2ModelIDs = expectedV1ModelIDs + [
            ObjectIdentifier(PersistentSchemaReleaseMarker.self)
        ]
        let expectedV3ModelIDs = expectedV2ModelIDs + [
            ObjectIdentifier(DeletionLedgerRow.self)
        ]
        let expectedV4ModelIDs = expectedV3ModelIDs + [
            ObjectIdentifier(MutationReceiptRow.self),
            ObjectIdentifier(MutationQuarantineRow.self),
            ObjectIdentifier(WorkspaceMutationStateRow.self),
            ObjectIdentifier(EntityMutationRevisionRow.self),
        ]
        let expectedV5ModelIDs = expectedV4ModelIDs + [
            ObjectIdentifier(ObservationAndTimeRow.self)
        ]
        let expectedV6ModelIDs = expectedV5ModelIDs + [
            ObjectIdentifier(LocationNodeRow.self),
            ObjectIdentifier(LocationHierarchyEventRow.self),
            ObjectIdentifier(AssetPlacementEventRow.self),
            ObjectIdentifier(AssetCompositionEdgeRow.self),
            ObjectIdentifier(AssetCompositionEventRow.self),
            ObjectIdentifier(LocationMigrationReceiptRow.self),
        ]
        let expectedV7ModelIDs = expectedV6ModelIDs + [
            ObjectIdentifier(SavedSmartViewRowV1.self),
        ]
        let expectedV8ModelIDs = expectedV7ModelIDs + [
            ObjectIdentifier(RequirementAssuranceRow.self),
        ]
        let expectedV9ModelIDs = expectedV8ModelIDs + [
            ObjectIdentifier(ServicePartyRow.self), ObjectIdentifier(SitePartyRoleEventRow.self),
            ObjectIdentifier(ActorSnapshotRow.self), ObjectIdentifier(QualificationSnapshotRow.self),
            ObjectIdentifier(SignoffSnapshotRow.self),
        ]
        let expectedV10ModelIDs = expectedV9ModelIDs + [
            ObjectIdentifier(AssetKindBindingEventRow.self),
            ObjectIdentifier(AssetWorkflowCapabilityBindingEventRow.self),
            ObjectIdentifier(AssetProductIdentityRow.self),
            ObjectIdentifier(AssetLifecycleEventRow.self),
            ObjectIdentifier(AssetSuccessorLinkRow.self),
            ObjectIdentifier(WorkSubjectScopeSnapshotRow.self),
        ]
        let expectedV11ModelIDs = expectedV10ModelIDs + [
            ObjectIdentifier(AuthoritySourceReleaseRow.self),
            ObjectIdentifier(RequirementBasisBindingRow.self),
            ObjectIdentifier(ApplicabilityContextSnapshotRow.self),
            ObjectIdentifier(AssessmentScopeSnapshotRow.self),
            ObjectIdentifier(SeverityScaleReleaseRow.self),
            ObjectIdentifier(FindingClassificationBindingRow.self),
            ObjectIdentifier(MeasurementProtocolReleaseRow.self),
            ObjectIdentifier(DerivedFactEvaluatorDescriptorRow.self),
            ObjectIdentifier(DerivedFactProvenanceRow.self),
        ]
        let expectedV12ModelIDs = expectedV11ModelIDs + [
            ObjectIdentifier(FunctionalRelationshipTypeDescriptorRow.self),
            ObjectIdentifier(AssetFunctionalRelationshipEventRow.self),
        ]
        let expectedV13ModelIDs = expectedV12ModelIDs + [
            ObjectIdentifier(EvidenceVisibilityRow.self), ObjectIdentifier(ClaimEvidenceLinkRow.self),
            ObjectIdentifier(AssuranceManifestRow.self), ObjectIdentifier(AttestationRow.self),
        ]
        let expectedV14ModelIDs=expectedV13ModelIDs+[ObjectIdentifier(InspectionReviewTransitionRow.self),ObjectIdentifier(ReviewDispositionRow.self),ObjectIdentifier(ChangeRequestRow.self),ObjectIdentifier(CorrectiveActionPolicyRow.self),ObjectIdentifier(CorrectiveActionEventRow.self)]
        let expectedV15ModelIDs=expectedV14ModelIDs+[ObjectIdentifier(WorkPacketManifestRow.self),ObjectIdentifier(WorkItemClaimRow.self),ObjectIdentifier(WorkLeaseRow.self),ObjectIdentifier(WorkReleaseRow.self),ObjectIdentifier(WorkHandoffRow.self)]
        let expectedV16ModelIDs=expectedV15ModelIDs+[ObjectIdentifier(FieldDraftCheckpointRow.self),ObjectIdentifier(AttachmentStagingItemRow.self),ObjectIdentifier(DraftCommitSagaRow.self),ObjectIdentifier(DraftContentReservationRow.self),ObjectIdentifier(DraftCommitReceiptRow.self),ObjectIdentifier(DraftDiscardReceiptRow.self)]
        let expectedV17ModelIDs=expectedV16ModelIDs+[ObjectIdentifier(PromotedPackageReleaseRow.self),ObjectIdentifier(PackageSandboxRunRow.self),ObjectIdentifier(PackagePromotionReceiptRow.self),ObjectIdentifier(ActivePackageRegistryPointerRow.self)]

        guard candidate[0] == .v1,
              candidate[0].versionIdentifier == PersistentSchemaV1.versionIdentifier,
              candidate[0].compatibilityID == v1CompatibilityID,
              candidate[0].predecessorVersionIdentifier == nil,
              candidate[0].models.count == 7,
              candidate[0].models.map({ ObjectIdentifier($0) })
                  == expectedV1ModelIDs,
              candidate[0].migrationStage == .bootstrap else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidBootstrapRelease
        }

        guard candidate[1] == .v2,
              candidate[1].versionIdentifier == PersistentSchemaV2.versionIdentifier,
              candidate[1].compatibilityID == v2CompatibilityID,
              candidate[1].predecessorVersionIdentifier == PersistentSchemaV1.versionIdentifier,
              candidate[1].models.count == 8,
              candidate[1].models.map({ ObjectIdentifier($0) })
                  == expectedV2ModelIDs,
              PersistentSchemaV1.models.map({ ObjectIdentifier($0) })
                  == expectedV1ModelIDs,
              PersistentSchemaV2.models.map({ ObjectIdentifier($0) })
                  == expectedV2ModelIDs,
              Array(expectedV2ModelIDs.dropLast()) == expectedV1ModelIDs,
              expectedV1ModelIDs != expectedV2ModelIDs,
              expectedV2ModelIDs.last
                  == ObjectIdentifier(PersistentSchemaReleaseMarker.self),
              v2MarkerIDString == v2MarkerIDString.lowercased(),
              v2MarkerID.uuidString.lowercased() == v2MarkerIDString,
              candidate[1].migrationStage == .lightweight else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[2] == .v3,
              candidate[2].versionIdentifier == PersistentSchemaV3.versionIdentifier,
              candidate[2].compatibilityID == v3CompatibilityID,
              candidate[2].predecessorVersionIdentifier == PersistentSchemaV2.versionIdentifier,
              candidate[2].models.count == 9,
              candidate[2].models.map({ ObjectIdentifier($0) }) == expectedV3ModelIDs,
              Array(expectedV3ModelIDs.dropLast()) == expectedV2ModelIDs,
              expectedV3ModelIDs.last == ObjectIdentifier(DeletionLedgerRow.self),
              candidate[2].migrationStage == .lightweight else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[3] == .v4,
              candidate[3].versionIdentifier == PersistentSchemaV4.versionIdentifier,
              candidate[3].compatibilityID == v4CompatibilityID,
              candidate[3].predecessorVersionIdentifier == PersistentSchemaV3.versionIdentifier,
              candidate[3].models.count == 13,
              candidate[3].models.map({ ObjectIdentifier($0) }) == expectedV4ModelIDs,
              Array(expectedV4ModelIDs.dropLast(4)) == expectedV3ModelIDs,
              candidate[3].migrationStage == .lightweight else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[4] == .v5,
              candidate[4].versionIdentifier == PersistentSchemaV5.versionIdentifier,
              candidate[4].compatibilityID == v5CompatibilityID,
              candidate[4].predecessorVersionIdentifier == PersistentSchemaV4.versionIdentifier,
              candidate[4].models.count == 14,
              candidate[4].models.map({ ObjectIdentifier($0) }) == expectedV5ModelIDs,
              PersistentSchemaV5.models.map({ ObjectIdentifier($0) }) == expectedV5ModelIDs,
              Array(expectedV5ModelIDs.dropLast()) == expectedV4ModelIDs,
              expectedV5ModelIDs.last == ObjectIdentifier(ObservationAndTimeRow.self),
              candidate[4].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[5] == .v6,
              candidate[5].versionIdentifier == PersistentSchemaV6.versionIdentifier,
              candidate[5].compatibilityID == v6CompatibilityID,
              candidate[5].predecessorVersionIdentifier == PersistentSchemaV5.versionIdentifier,
              candidate[5].models.count == 20,
              candidate[5].models.map({ ObjectIdentifier($0) }) == expectedV6ModelIDs,
              PersistentSchemaV6.models.map({ ObjectIdentifier($0) }) == expectedV6ModelIDs,
              Array(expectedV6ModelIDs.dropLast(6)) == expectedV5ModelIDs,
              candidate[5].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[6] == .v7,
              candidate[6].versionIdentifier == PersistentSchemaV7.versionIdentifier,
              candidate[6].compatibilityID == v7CompatibilityID,
              candidate[6].predecessorVersionIdentifier == PersistentSchemaV6.versionIdentifier,
              candidate[6].models.count == 21,
              candidate[6].models.map({ ObjectIdentifier($0) }) == expectedV7ModelIDs,
              PersistentSchemaV7.models.map({ ObjectIdentifier($0) }) == expectedV7ModelIDs,
              Array(expectedV7ModelIDs.dropLast()) == expectedV6ModelIDs,
              expectedV7ModelIDs.last == ObjectIdentifier(SavedSmartViewRowV1.self),
              candidate[6].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[7] == .v8,
              candidate[7].versionIdentifier == PersistentSchemaV8.versionIdentifier,
              candidate[7].compatibilityID == v8CompatibilityID,
              candidate[7].predecessorVersionIdentifier == PersistentSchemaV7.versionIdentifier,
              candidate[7].models.count == 22,
              candidate[7].models.map({ ObjectIdentifier($0) }) == expectedV8ModelIDs,
              PersistentSchemaV8.models.map({ ObjectIdentifier($0) }) == expectedV8ModelIDs,
              Array(expectedV8ModelIDs.dropLast()) == expectedV7ModelIDs,
              expectedV8ModelIDs.last == ObjectIdentifier(RequirementAssuranceRow.self),
              candidate[7].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[8] == .v9,
              candidate[8].versionIdentifier == PersistentSchemaV9.versionIdentifier,
              candidate[8].compatibilityID == v9CompatibilityID,
              candidate[8].predecessorVersionIdentifier == PersistentSchemaV8.versionIdentifier,
              candidate[8].models.count == 27,
              candidate[8].models.map({ ObjectIdentifier($0) }) == expectedV9ModelIDs,
              Array(expectedV9ModelIDs.dropLast(5)) == expectedV8ModelIDs,
              candidate[8].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[9] == .v10,
              candidate[9].versionIdentifier == PersistentSchemaV10.versionIdentifier,
              candidate[9].compatibilityID == v10CompatibilityID,
              candidate[9].predecessorVersionIdentifier == PersistentSchemaV9.versionIdentifier,
              candidate[9].models.count == 33,
              candidate[9].models.map({ ObjectIdentifier($0) }) == expectedV10ModelIDs,
              PersistentSchemaV10.models.map({ ObjectIdentifier($0) }) == expectedV10ModelIDs,
              Array(expectedV10ModelIDs.dropLast(6)) == expectedV9ModelIDs,
              candidate[9].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[10] == .v11,
              candidate[10].versionIdentifier == PersistentSchemaV11.versionIdentifier,
              candidate[10].compatibilityID == v11CompatibilityID,
              candidate[10].predecessorVersionIdentifier == PersistentSchemaV10.versionIdentifier,
              candidate[10].models.count == 42,
              candidate[10].models.map({ ObjectIdentifier($0) }) == expectedV11ModelIDs,
              PersistentSchemaV11.models.map({ ObjectIdentifier($0) }) == expectedV11ModelIDs,
              Array(expectedV11ModelIDs.dropLast(9)) == expectedV10ModelIDs,
              candidate[10].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[11] == .v12,
              candidate[11].versionIdentifier == PersistentSchemaV12.versionIdentifier,
              candidate[11].compatibilityID == v12CompatibilityID,
              candidate[11].predecessorVersionIdentifier == PersistentSchemaV11.versionIdentifier,
              candidate[11].models.count == 44,
              candidate[11].models.map({ ObjectIdentifier($0) }) == expectedV12ModelIDs,
              PersistentSchemaV12.models.map({ ObjectIdentifier($0) }) == expectedV12ModelIDs,
              Array(expectedV12ModelIDs.dropLast(2)) == expectedV11ModelIDs,
              candidate[11].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }

        guard candidate[12] == .v13,
              candidate[12].versionIdentifier == PersistentSchemaV13.versionIdentifier,
              candidate[12].compatibilityID == v13CompatibilityID,
              candidate[12].predecessorVersionIdentifier == PersistentSchemaV12.versionIdentifier,
              candidate[12].models.count == 48,
              candidate[12].models.map({ ObjectIdentifier($0) }) == expectedV13ModelIDs,
              PersistentSchemaV13.models.map({ ObjectIdentifier($0) }) == expectedV13ModelIDs,
              Array(expectedV13ModelIDs.dropLast(4)) == expectedV12ModelIDs,
              candidate[12].migrationStage == .custom else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease
        }
        guard candidate[13] == .v14,candidate[13].versionIdentifier==PersistentSchemaV14.versionIdentifier,candidate[13].compatibilityID==v14CompatibilityID,candidate[13].predecessorVersionIdentifier==PersistentSchemaV13.versionIdentifier,candidate[13].models.count==53,candidate[13].models.map({ObjectIdentifier($0)})==expectedV14ModelIDs,PersistentSchemaV14.models.map({ObjectIdentifier($0)})==expectedV14ModelIDs,Array(expectedV14ModelIDs.dropLast(5))==expectedV13ModelIDs,candidate[13].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        guard candidate[14] == .v15,candidate[14].versionIdentifier==PersistentSchemaV15.versionIdentifier,candidate[14].compatibilityID==v15CompatibilityID,candidate[14].predecessorVersionIdentifier==PersistentSchemaV14.versionIdentifier,candidate[14].models.count==58,candidate[14].models.map({ObjectIdentifier($0)})==expectedV15ModelIDs,PersistentSchemaV15.models.map({ObjectIdentifier($0)})==expectedV15ModelIDs,Array(expectedV15ModelIDs.dropLast(5))==expectedV14ModelIDs,candidate[14].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        guard candidate[15] == .v16,candidate[15].versionIdentifier==PersistentSchemaV16.versionIdentifier,candidate[15].compatibilityID==v16CompatibilityID,candidate[15].predecessorVersionIdentifier==PersistentSchemaV15.versionIdentifier,candidate[15].models.count==64,candidate[15].models.map({ObjectIdentifier($0)})==expectedV16ModelIDs,PersistentSchemaV16.models.map({ObjectIdentifier($0)})==expectedV16ModelIDs,Array(expectedV16ModelIDs.dropLast(6))==expectedV15ModelIDs,candidate[15].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        guard candidate[16] == .v17,candidate[16].versionIdentifier==PersistentSchemaV17.versionIdentifier,candidate[16].compatibilityID==v17CompatibilityID,candidate[16].predecessorVersionIdentifier==PersistentSchemaV16.versionIdentifier,candidate[16].models.count==68,candidate[16].models.map({ObjectIdentifier($0)})==expectedV17ModelIDs,PersistentSchemaV17.models.map({ObjectIdentifier($0)})==expectedV17ModelIDs,Array(expectedV17ModelIDs.dropLast(4))==expectedV16ModelIDs,candidate[16].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV18ModelIDs = PersistentSchemaV18.models.map { ObjectIdentifier($0) }
        guard candidate[17] == .v18,candidate[17].versionIdentifier==PersistentSchemaV18.versionIdentifier,candidate[17].compatibilityID==v18CompatibilityID,candidate[17].predecessorVersionIdentifier==PersistentSchemaV17.versionIdentifier,candidate[17].models.count==73,candidate[17].models.map({ObjectIdentifier($0)})==expectedV18ModelIDs,Array(expectedV18ModelIDs.dropLast(5))==expectedV17ModelIDs,candidate[17].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV19ModelIDs=PersistentSchemaV19.models.map{ObjectIdentifier($0)}
        guard candidate[18] == .v19,candidate[18].versionIdentifier==PersistentSchemaV19.versionIdentifier,candidate[18].compatibilityID==v19CompatibilityID,candidate[18].predecessorVersionIdentifier==PersistentSchemaV18.versionIdentifier,candidate[18].models.count==77,candidate[18].models.map({ObjectIdentifier($0)})==expectedV19ModelIDs,Array(expectedV19ModelIDs.dropLast(4))==expectedV18ModelIDs,candidate[18].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV20ModelIDs=PersistentSchemaV20.models.map{ObjectIdentifier($0)}
        guard candidate[19] == .v20,candidate[19].versionIdentifier==PersistentSchemaV20.versionIdentifier,candidate[19].compatibilityID==v20CompatibilityID,candidate[19].predecessorVersionIdentifier==PersistentSchemaV19.versionIdentifier,candidate[19].models.count==81,candidate[19].models.map({ObjectIdentifier($0)})==expectedV20ModelIDs,Array(expectedV20ModelIDs.dropLast(4))==expectedV19ModelIDs,candidate[19].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV21ModelIDs=PersistentSchemaV21.models.map{ObjectIdentifier($0)}
        guard candidate[20] == .v21,candidate[20].versionIdentifier==PersistentSchemaV21.versionIdentifier,candidate[20].compatibilityID==v21CompatibilityID,candidate[20].predecessorVersionIdentifier==PersistentSchemaV20.versionIdentifier,candidate[20].models.count==82,candidate[20].models.map({ObjectIdentifier($0)})==expectedV21ModelIDs,Array(expectedV21ModelIDs.dropLast())==expectedV20ModelIDs,candidate[20].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV22ModelIDs=PersistentSchemaV22.models.map{ObjectIdentifier($0)}
        guard candidate[21] == .v22,candidate[21].versionIdentifier==PersistentSchemaV22.versionIdentifier,candidate[21].compatibilityID==v22CompatibilityID,candidate[21].predecessorVersionIdentifier==PersistentSchemaV21.versionIdentifier,candidate[21].models.count==84,candidate[21].models.map({ObjectIdentifier($0)})==expectedV22ModelIDs,Array(expectedV22ModelIDs.dropLast(2))==expectedV21ModelIDs,candidate[21].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV23ModelIDs=PersistentSchemaV23.models.map{ObjectIdentifier($0)}
        guard candidate[22] == .v23,candidate[22].versionIdentifier==PersistentSchemaV23.versionIdentifier,candidate[22].compatibilityID==v23CompatibilityID,candidate[22].predecessorVersionIdentifier==PersistentSchemaV22.versionIdentifier,candidate[22].models.count==85,candidate[22].models.map({ObjectIdentifier($0)})==expectedV23ModelIDs,Array(expectedV23ModelIDs.dropLast())==expectedV22ModelIDs,candidate[22].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV24ModelIDs=PersistentSchemaV24.models.map{ObjectIdentifier($0)}
        guard candidate[23] == .v24,candidate[23].versionIdentifier==PersistentSchemaV24.versionIdentifier,candidate[23].compatibilityID==v24CompatibilityID,candidate[23].predecessorVersionIdentifier==PersistentSchemaV23.versionIdentifier,candidate[23].models.count==87,candidate[23].models.map({ObjectIdentifier($0)})==expectedV24ModelIDs,Array(expectedV24ModelIDs.dropLast(2))==expectedV23ModelIDs,candidate[23].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV25ModelIDs=PersistentSchemaV25.models.map{ObjectIdentifier($0)}
        guard candidate[24] == .v25,candidate[24].versionIdentifier==PersistentSchemaV25.versionIdentifier,candidate[24].compatibilityID==v25CompatibilityID,candidate[24].predecessorVersionIdentifier==PersistentSchemaV24.versionIdentifier,candidate[24].models.count==92,candidate[24].models.map({ObjectIdentifier($0)})==expectedV25ModelIDs,Array(expectedV25ModelIDs.dropLast(5))==expectedV24ModelIDs,candidate[24].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV26ModelIDs=PersistentSchemaV26.models.map{ObjectIdentifier($0)}
        guard candidate[25] == .v26,candidate[25].versionIdentifier==PersistentSchemaV26.versionIdentifier,candidate[25].compatibilityID==v26CompatibilityID,candidate[25].predecessorVersionIdentifier==PersistentSchemaV25.versionIdentifier,candidate[25].models.count==94,candidate[25].models.map({ObjectIdentifier($0)})==expectedV26ModelIDs,Array(expectedV26ModelIDs.dropLast(2))==expectedV25ModelIDs,candidate[25].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV27ModelIDs=PersistentSchemaV27.models.map{ObjectIdentifier($0)}
        guard candidate[26] == .v27,candidate[26].versionIdentifier==PersistentSchemaV27.versionIdentifier,candidate[26].compatibilityID==v27CompatibilityID,candidate[26].predecessorVersionIdentifier==PersistentSchemaV26.versionIdentifier,candidate[26].models.count==96,candidate[26].models.map({ObjectIdentifier($0)})==expectedV27ModelIDs,Array(expectedV27ModelIDs.dropLast(2))==expectedV26ModelIDs,candidate[26].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV28ModelIDs=PersistentSchemaV28.models.map{ObjectIdentifier($0)}
        guard candidate[27] == .v28,candidate[27].versionIdentifier==PersistentSchemaV28.versionIdentifier,candidate[27].compatibilityID==v28CompatibilityID,candidate[27].predecessorVersionIdentifier==PersistentSchemaV27.versionIdentifier,candidate[27].models.count==100,candidate[27].models.map({ObjectIdentifier($0)})==expectedV28ModelIDs,Array(expectedV28ModelIDs.dropLast(4))==expectedV27ModelIDs,candidate[27].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV29ModelIDs=PersistentSchemaV29.models.map{ObjectIdentifier($0)}
        guard candidate[28] == .v29,candidate[28].versionIdentifier==PersistentSchemaV29.versionIdentifier,candidate[28].compatibilityID==v29CompatibilityID,candidate[28].predecessorVersionIdentifier==PersistentSchemaV28.versionIdentifier,candidate[28].models.count==102,candidate[28].models.map({ObjectIdentifier($0)})==expectedV29ModelIDs,Array(expectedV29ModelIDs.dropLast(2))==expectedV28ModelIDs,candidate[28].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV30ModelIDs=PersistentSchemaV30.models.map{ObjectIdentifier($0)}
        guard candidate[29] == .v30,candidate[29].versionIdentifier==PersistentSchemaV30.versionIdentifier,candidate[29].compatibilityID==v30CompatibilityID,candidate[29].predecessorVersionIdentifier==PersistentSchemaV29.versionIdentifier,candidate[29].models.count==104,candidate[29].models.map({ObjectIdentifier($0)})==expectedV30ModelIDs,Array(expectedV30ModelIDs.dropLast(2))==expectedV29ModelIDs,candidate[29].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV31ModelIDs=PersistentSchemaV31.models.map{ObjectIdentifier($0)}
        guard candidate[30] == .v31,candidate[30].versionIdentifier==PersistentSchemaV31.versionIdentifier,candidate[30].compatibilityID==v31CompatibilityID,candidate[30].predecessorVersionIdentifier==PersistentSchemaV30.versionIdentifier,candidate[30].models.count==109,candidate[30].models.map({ObjectIdentifier($0)})==expectedV31ModelIDs,Array(expectedV31ModelIDs.dropLast(5))==expectedV30ModelIDs,candidate[30].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV32ModelIDs=PersistentSchemaV32.models.map{ObjectIdentifier($0)}
        guard candidate[31] == .v32,candidate[31].versionIdentifier==PersistentSchemaV32.versionIdentifier,candidate[31].compatibilityID==v32CompatibilityID,candidate[31].predecessorVersionIdentifier==PersistentSchemaV31.versionIdentifier,candidate[31].models.count==110,candidate[31].models.map({ObjectIdentifier($0)})==expectedV32ModelIDs,Array(expectedV32ModelIDs.dropLast())==expectedV31ModelIDs,candidate[31].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV33ModelIDs=PersistentSchemaV33.models.map{ObjectIdentifier($0)}
        guard candidate[32] == .v33,candidate[32].versionIdentifier==PersistentSchemaV33.versionIdentifier,candidate[32].compatibilityID==v33CompatibilityID,candidate[32].predecessorVersionIdentifier==PersistentSchemaV32.versionIdentifier,candidate[32].models.count==112,candidate[32].models.map({ObjectIdentifier($0)})==expectedV33ModelIDs,Array(expectedV33ModelIDs.dropLast(2))==expectedV32ModelIDs,candidate[32].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV34ModelIDs=PersistentSchemaV34.models.map{ObjectIdentifier($0)}
        guard candidate[33] == .v34,candidate[33].versionIdentifier==PersistentSchemaV34.versionIdentifier,candidate[33].compatibilityID==v34CompatibilityID,candidate[33].predecessorVersionIdentifier==PersistentSchemaV33.versionIdentifier,candidate[33].models.count==113,candidate[33].models.map({ObjectIdentifier($0)})==expectedV34ModelIDs,Array(expectedV34ModelIDs.dropLast())==expectedV33ModelIDs,candidate[33].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV35ModelIDs=PersistentSchemaV35.models.map{ObjectIdentifier($0)}
        guard candidate[34] == .v35,candidate[34].versionIdentifier==PersistentSchemaV35.versionIdentifier,candidate[34].compatibilityID==v35CompatibilityID,candidate[34].predecessorVersionIdentifier==PersistentSchemaV34.versionIdentifier,candidate[34].models.count==115,candidate[34].models.map({ObjectIdentifier($0)})==expectedV35ModelIDs,Array(expectedV35ModelIDs.dropLast(2))==expectedV34ModelIDs,candidate[34].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV36ModelIDs=PersistentSchemaV36.models.map{ObjectIdentifier($0)}
        guard candidate[35] == .v36,candidate[35].versionIdentifier==PersistentSchemaV36.versionIdentifier,candidate[35].compatibilityID==v36CompatibilityID,candidate[35].predecessorVersionIdentifier==PersistentSchemaV35.versionIdentifier,candidate[35].models.count==120,candidate[35].models.map({ObjectIdentifier($0)})==expectedV36ModelIDs,Array(expectedV36ModelIDs.dropLast(5))==expectedV35ModelIDs,candidate[35].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}
        let expectedV37ModelIDs=PersistentSchemaV37.models.map{ObjectIdentifier($0)}
        guard candidate[36] == .v37,candidate[36].versionIdentifier==PersistentSchemaV37.versionIdentifier,candidate[36].compatibilityID==v37CompatibilityID,candidate[36].predecessorVersionIdentifier==PersistentSchemaV36.versionIdentifier,candidate[36].models.count==121,candidate[36].models.map({ObjectIdentifier($0)})==expectedV37ModelIDs,Array(expectedV37ModelIDs.dropLast(1))==expectedV36ModelIDs,candidate[36].migrationStage == .custom else{throw PersistentSchemaReleaseRegistryErrorV1.invalidSuccessorRelease}

        guard activeRelease == .v37,activeVersionIdentifier==candidate[36].versionIdentifier,activeCompatibilityID==candidate[36].compatibilityID,
              PersistentSchemaMigrationPlanV1.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV1.schemas[0])
                  == ObjectIdentifier(PersistentSchemaV1.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV1.schemas[1])
                  == ObjectIdentifier(PersistentSchemaV2.self),
              PersistentSchemaMigrationPlanV1.stages.count == 1,
              PersistentSchemaMigrationPlanV2.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV2.schemas[0])
                  == ObjectIdentifier(PersistentSchemaV2.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV2.schemas[1])
                  == ObjectIdentifier(PersistentSchemaV3.self),
              PersistentSchemaMigrationPlanV2.stages.count == 1,
              PersistentSchemaMigrationPlanV3.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV3.schemas[0]) == ObjectIdentifier(PersistentSchemaV3.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV3.schemas[1]) == ObjectIdentifier(PersistentSchemaV4.self),
              PersistentSchemaMigrationPlanV3.stages.count == 1,
              PersistentSchemaMigrationPlanV4.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV4.schemas[0]) == ObjectIdentifier(PersistentSchemaV4.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV4.schemas[1]) == ObjectIdentifier(PersistentSchemaV5.self),
              PersistentSchemaMigrationPlanV4.stages.count == 1,
              PersistentSchemaMigrationPlanV5.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV5.schemas[0]) == ObjectIdentifier(PersistentSchemaV5.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV5.schemas[1]) == ObjectIdentifier(PersistentSchemaV6.self),
              PersistentSchemaMigrationPlanV5.stages.count == 1,
              PersistentSchemaMigrationPlanV6.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV6.schemas[0]) == ObjectIdentifier(PersistentSchemaV6.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV6.schemas[1]) == ObjectIdentifier(PersistentSchemaV7.self),
              PersistentSchemaMigrationPlanV6.stages.count == 1,
              PersistentSchemaMigrationPlanV7.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV7.schemas[0]) == ObjectIdentifier(PersistentSchemaV7.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV7.schemas[1]) == ObjectIdentifier(PersistentSchemaV8.self),
              PersistentSchemaMigrationPlanV7.stages.count == 1,
              PersistentSchemaMigrationPlanV8.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV8.schemas[0]) == ObjectIdentifier(PersistentSchemaV8.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV8.schemas[1]) == ObjectIdentifier(PersistentSchemaV9.self),
              PersistentSchemaMigrationPlanV8.stages.count == 1,
              PersistentSchemaMigrationPlanV9.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV9.schemas[0]) == ObjectIdentifier(PersistentSchemaV9.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV9.schemas[1]) == ObjectIdentifier(PersistentSchemaV10.self),
              PersistentSchemaMigrationPlanV9.stages.count == 1,
              PersistentSchemaMigrationPlanV10.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV10.schemas[0]) == ObjectIdentifier(PersistentSchemaV10.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV10.schemas[1]) == ObjectIdentifier(PersistentSchemaV11.self),
              PersistentSchemaMigrationPlanV10.stages.count == 1,
              PersistentSchemaMigrationPlanV11.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV11.schemas[0]) == ObjectIdentifier(PersistentSchemaV11.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV11.schemas[1]) == ObjectIdentifier(PersistentSchemaV12.self),
              PersistentSchemaMigrationPlanV11.stages.count == 1,
              PersistentSchemaMigrationPlanV12.schemas.count == 2,
              ObjectIdentifier(PersistentSchemaMigrationPlanV12.schemas[0]) == ObjectIdentifier(PersistentSchemaV12.self),
              ObjectIdentifier(PersistentSchemaMigrationPlanV12.schemas[1]) == ObjectIdentifier(PersistentSchemaV13.self),
              PersistentSchemaMigrationPlanV12.stages.count == 1,
              PersistentSchemaMigrationPlanV13.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV13.schemas[0])==ObjectIdentifier(PersistentSchemaV13.self),ObjectIdentifier(PersistentSchemaMigrationPlanV13.schemas[1])==ObjectIdentifier(PersistentSchemaV14.self),PersistentSchemaMigrationPlanV13.stages.count==1,
              PersistentSchemaMigrationPlanV14.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV14.schemas[0])==ObjectIdentifier(PersistentSchemaV14.self),ObjectIdentifier(PersistentSchemaMigrationPlanV14.schemas[1])==ObjectIdentifier(PersistentSchemaV15.self),PersistentSchemaMigrationPlanV14.stages.count==1,
              PersistentSchemaMigrationPlanV15.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV15.schemas[0])==ObjectIdentifier(PersistentSchemaV15.self),ObjectIdentifier(PersistentSchemaMigrationPlanV15.schemas[1])==ObjectIdentifier(PersistentSchemaV16.self),PersistentSchemaMigrationPlanV15.stages.count==1,
              PersistentSchemaMigrationPlanV16.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV16.schemas[0])==ObjectIdentifier(PersistentSchemaV16.self),ObjectIdentifier(PersistentSchemaMigrationPlanV16.schemas[1])==ObjectIdentifier(PersistentSchemaV17.self),PersistentSchemaMigrationPlanV16.stages.count==1,
              PersistentSchemaMigrationPlanV17.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV17.schemas[0])==ObjectIdentifier(PersistentSchemaV17.self),ObjectIdentifier(PersistentSchemaMigrationPlanV17.schemas[1])==ObjectIdentifier(PersistentSchemaV18.self),PersistentSchemaMigrationPlanV17.stages.count==1,
              PersistentSchemaMigrationPlanV18.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV18.schemas[0])==ObjectIdentifier(PersistentSchemaV18.self),ObjectIdentifier(PersistentSchemaMigrationPlanV18.schemas[1])==ObjectIdentifier(PersistentSchemaV19.self),PersistentSchemaMigrationPlanV18.stages.count==1,
              PersistentSchemaMigrationPlanV19.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV19.schemas[0])==ObjectIdentifier(PersistentSchemaV19.self),ObjectIdentifier(PersistentSchemaMigrationPlanV19.schemas[1])==ObjectIdentifier(PersistentSchemaV20.self),PersistentSchemaMigrationPlanV19.stages.count==1,
              PersistentSchemaMigrationPlanV20.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV20.schemas[0])==ObjectIdentifier(PersistentSchemaV20.self),ObjectIdentifier(PersistentSchemaMigrationPlanV20.schemas[1])==ObjectIdentifier(PersistentSchemaV21.self),PersistentSchemaMigrationPlanV20.stages.count==1,
              PersistentSchemaMigrationPlanV21.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV21.schemas[0])==ObjectIdentifier(PersistentSchemaV21.self),ObjectIdentifier(PersistentSchemaMigrationPlanV21.schemas[1])==ObjectIdentifier(PersistentSchemaV22.self),PersistentSchemaMigrationPlanV21.stages.count==1,
              PersistentSchemaMigrationPlanV22.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV22.schemas[0])==ObjectIdentifier(PersistentSchemaV22.self),ObjectIdentifier(PersistentSchemaMigrationPlanV22.schemas[1])==ObjectIdentifier(PersistentSchemaV23.self),PersistentSchemaMigrationPlanV22.stages.count==1,
              PersistentSchemaMigrationPlanV23.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV23.schemas[0])==ObjectIdentifier(PersistentSchemaV23.self),ObjectIdentifier(PersistentSchemaMigrationPlanV23.schemas[1])==ObjectIdentifier(PersistentSchemaV24.self),PersistentSchemaMigrationPlanV23.stages.count==1,
              PersistentSchemaMigrationPlanV24.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV24.schemas[0])==ObjectIdentifier(PersistentSchemaV24.self),ObjectIdentifier(PersistentSchemaMigrationPlanV24.schemas[1])==ObjectIdentifier(PersistentSchemaV25.self),PersistentSchemaMigrationPlanV24.stages.count==1,
              PersistentSchemaMigrationPlanV25.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV25.schemas[0])==ObjectIdentifier(PersistentSchemaV25.self),ObjectIdentifier(PersistentSchemaMigrationPlanV25.schemas[1])==ObjectIdentifier(PersistentSchemaV26.self),PersistentSchemaMigrationPlanV25.stages.count==1,
              PersistentSchemaMigrationPlanV26.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV26.schemas[0])==ObjectIdentifier(PersistentSchemaV26.self),ObjectIdentifier(PersistentSchemaMigrationPlanV26.schemas[1])==ObjectIdentifier(PersistentSchemaV27.self),PersistentSchemaMigrationPlanV26.stages.count==1,
              PersistentSchemaMigrationPlanV27.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV27.schemas[0])==ObjectIdentifier(PersistentSchemaV27.self),ObjectIdentifier(PersistentSchemaMigrationPlanV27.schemas[1])==ObjectIdentifier(PersistentSchemaV28.self),PersistentSchemaMigrationPlanV27.stages.count==1,
              PersistentSchemaMigrationPlanV28.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV28.schemas[0])==ObjectIdentifier(PersistentSchemaV28.self),ObjectIdentifier(PersistentSchemaMigrationPlanV28.schemas[1])==ObjectIdentifier(PersistentSchemaV29.self),PersistentSchemaMigrationPlanV28.stages.count==1,
              PersistentSchemaMigrationPlanV29.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV29.schemas[0])==ObjectIdentifier(PersistentSchemaV29.self),ObjectIdentifier(PersistentSchemaMigrationPlanV29.schemas[1])==ObjectIdentifier(PersistentSchemaV30.self),PersistentSchemaMigrationPlanV29.stages.count==1,
              PersistentSchemaMigrationPlanV30.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV30.schemas[0])==ObjectIdentifier(PersistentSchemaV30.self),ObjectIdentifier(PersistentSchemaMigrationPlanV30.schemas[1])==ObjectIdentifier(PersistentSchemaV31.self),PersistentSchemaMigrationPlanV30.stages.count==1,
              PersistentSchemaMigrationPlanV31.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV31.schemas[0])==ObjectIdentifier(PersistentSchemaV31.self),ObjectIdentifier(PersistentSchemaMigrationPlanV31.schemas[1])==ObjectIdentifier(PersistentSchemaV32.self),PersistentSchemaMigrationPlanV31.stages.count==1,
              PersistentSchemaMigrationPlanV32.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV32.schemas[0])==ObjectIdentifier(PersistentSchemaV32.self),ObjectIdentifier(PersistentSchemaMigrationPlanV32.schemas[1])==ObjectIdentifier(PersistentSchemaV33.self),PersistentSchemaMigrationPlanV32.stages.count==1,
              PersistentSchemaMigrationPlanV33.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV33.schemas[0])==ObjectIdentifier(PersistentSchemaV33.self),ObjectIdentifier(PersistentSchemaMigrationPlanV33.schemas[1])==ObjectIdentifier(PersistentSchemaV34.self),PersistentSchemaMigrationPlanV33.stages.count==1,
              PersistentSchemaMigrationPlanV34.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV34.schemas[0])==ObjectIdentifier(PersistentSchemaV34.self),ObjectIdentifier(PersistentSchemaMigrationPlanV34.schemas[1])==ObjectIdentifier(PersistentSchemaV35.self),PersistentSchemaMigrationPlanV34.stages.count==1,
              PersistentSchemaMigrationPlanV35.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV35.schemas[0])==ObjectIdentifier(PersistentSchemaV35.self),ObjectIdentifier(PersistentSchemaMigrationPlanV35.schemas[1])==ObjectIdentifier(PersistentSchemaV36.self),PersistentSchemaMigrationPlanV35.stages.count==1,
              PersistentSchemaMigrationPlanV36.schemas.count==2,ObjectIdentifier(PersistentSchemaMigrationPlanV36.schemas[0])==ObjectIdentifier(PersistentSchemaV36.self),ObjectIdentifier(PersistentSchemaMigrationPlanV36.schemas[1])==ObjectIdentifier(PersistentSchemaV37.self),PersistentSchemaMigrationPlanV36.stages.count==1 else {
            throw PersistentSchemaReleaseRegistryErrorV1.invalidActiveRelease
        }
    }

    static func release(
        for versionIdentifier: Schema.Version
    ) throws -> PersistentSchemaReleaseV1 {
        try validate()
        guard let release = releases.first(where: {
            $0.versionIdentifier == versionIdentifier
        }) else {
            throw PersistentSchemaReleaseRegistryErrorV1.unknownVersion
        }
        return release
    }

    static func schema(
        for versionIdentifier: Schema.Version
    ) throws -> Schema {
        let release = try release(for: versionIdentifier)
        return Schema(release.models, version: release.versionIdentifier)
    }

    static func activeSchema() throws -> Schema {
        try validate()
        return Schema(PersistentSchemaV37.models,version:PersistentSchemaV37.versionIdentifier)
    }
}

/// C48 enrolls the portable review exchange as a nonpersistent staging
/// boundary. The SwiftData release remains V36 with the V35 record contract;
/// no exchange/session row is added to this schema.
enum C48PortableReviewSchemaBoundaryV1 {
    static let persistentSchemaVersion = 36
    static let recordsSchemaVersion = 35
    static let canonicalSwiftDataSchemaChanged = false
    static let newPersistentRowCount = 0
    static let sessionStoreIsNonpersistent = true
    static let portableExchangeHasSwiftDataModel = false
}

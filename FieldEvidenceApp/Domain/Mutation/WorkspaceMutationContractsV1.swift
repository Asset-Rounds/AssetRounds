import CryptoKit
import Foundation

struct MutationIDV1: Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) throws {
        guard rawValue != Self.zero else { throw WorkspaceMutationContractFailureV1.invalidID }
        self.rawValue = rawValue
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(UUID.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum C50IncumbentWorkspaceMutationBoundaryV1 {
    static let addsWorkspaceCommand = false
    static let addsWorkspaceEntityKind = false
    static let previewIsZeroWrite = true
    static let acceptedImportDelegatesToExistingCanonicalMutation = true
}

enum WorkspaceEntityKindV1: String, CaseIterable, Codable, Sendable {
    case site
    case asset
    case locationNode
    case assetPlacementEvent
    case assetCompositionEdge
    case assetCompositionEvent
    case savedSmartView
    case serviceParty
    case serviceContactPoint
    case systemHandoffIntent
    case activitySessionEnvelope
    case activityStateTransition
    case installationTaskResult
    case installationAsBuiltSnapshot
    case punchReviewBasisSnapshot
    case workResourceEntry
    case localPartDefinition
    case stockStorageLocation
    case stockBalanceStream
    case stockMovementEvent
    case stockUseReceipt
    case stockUseReversalReceipt
    case stockReturnReceipt
    case stockAbandonment
    case myDayPlan
    case myDayCarryoverReceipt
    case serviceRequestRecord
    case serviceRequestDispositionEvent
    case serviceRequestWorkLinkEvent
    case assetServiceIncident
    case serviceImpactSegment
    case serviceCauseAssertion
    case serviceRemedyAssertion
    case serviceRepairInterval
    case serviceRestorationAssertion
    case qualifiedServiceExposure
    case sitePartyRoleEvent
    case actorSnapshot
    case qualificationSnapshot
    case signoffSnapshot
    case authoritySourceRelease
    case requirementBasisBinding
    case applicabilityContextSnapshot
    case assessmentScopeSnapshot
    case severityScaleRelease
    case findingClassificationBinding
    case measurementProtocolRelease
    case derivedFactEvaluatorDescriptor
    case derivedFactProvenance
    case functionalRelationshipTypeDescriptor
    case assetFunctionalRelationshipEvent
    case evidenceVisibility
    case claimEvidenceLink
    case evidenceAssociationEvent
    case evidenceSequenceRevision
    case shopReportProfile
    case roundSession
    case importMappingProfile
    case bulkSession
    case bulkCommitReceipt
    case assuranceManifest
    case attestation
    case inspectionReviewTransition
    case reviewDisposition
    case changeRequest
    case correctiveActionPolicy
    case correctiveActionEvent
    case workPacketManifest
    case workItemClaim
    case workLease
    case workRelease
    case workHandoff
    case fieldDraftCheckpoint
    case attachmentStagingItem
    case draftCommitSaga
    case draftContentReservation
    case draftCommitReceipt
    case draftDiscardReceipt
    case promotedPackageRelease
    case packageSandboxRun
    case packagePromotionReceipt
    case activePackageRegistryPointer
    case instrumentReference
    case calibrationStatusSnapshot
    case measurementCapture
    case measurementSeries
    case measurementQualityAssessment
    case privacyTransformPolicy
    case privacyRegion
    case privacyTransformManifest
    case privacyReviewReceipt
    case clientCapabilityProfile
    case clientCapabilityAdmissionDecision
    case packageLifecyclePolicy
    case packageLifecycleDisposition
    case fieldReferenceRelease
    case fieldReferenceBinding
    case accessibleDocumentAssessmentReceipt
    case surveyDefinitionIdentity
    case surveyDefinitionRelease
    case surveySession
    case factCapture
    case provisionalSubject
    case subjectPromotionReceipt
    case surveyPublicationSnapshot
    case assetLocator
    case locatorBindingReceipt
    case scheduleDefinitionRelease
    case occurrenceHistoryEvent
    case exceptionCalendarRelease
    case scheduleOverrideEvent
    case planDocument
    case planRevision
    case planPlacement
    case planRebaseReceipt
    case assetPoseEvent
    case spatialAnchorObservation
    case evidenceContext
    case pairedObservationLink
    case lightingSystem
    case lightingObservation
    case lightingIssue
    case lightingMeasurementPlan
    case lightingClaimState
    case temporalEvidenceClip
    case timecodedEvidenceAnchor
    case acceptedLabelGenerationSnapshot
    case workflowRecord
    case evidenceFile
    case issue
    case packet
    case report
    case deletionLedgerEntry
    case evidenceQualityRuleSet
    case evidenceQualityAssessment
    case evidenceQualityWaiverEvent
}

struct WorkspaceEntityIdentityV1: Codable, Hashable, Sendable {
    let kind: WorkspaceEntityKindV1
    let id: UUID

    init(kind: WorkspaceEntityKindV1, id: UUID) throws {
        guard id != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw WorkspaceMutationContractFailureV1.invalidID
        }
        self.kind = kind
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(WorkspaceEntityKindV1.self, forKey: .kind),
            id: container.decode(UUID.self, forKey: .id)
        )
    }

    func encode(to encoder: Encoder) throws {
        _ = try Self(kind: kind, id: id)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
    }

    var stableKey: String { "\(kind.rawValue):\(id.uuidString.lowercased())" }
}

/// Virtual, deterministic per-part/location balance concurrency stream. It is
/// never a persisted row or postimage identity; its sole purpose is to keep
/// stock movement CAS independent from storage-catalog revisions and from
/// other parts stored at the same location.
enum StockBalanceStreamIdentityV1 {
    private struct Basis: Codable { let partID: UUID; let locationID: UUID }
    static func id(partID: UUID, locationID: UUID) throws -> UUID {
        let digest = Array(SHA256.hash(data: try WorkspaceMutationCanonicalV1.data(Basis(partID: partID, locationID: locationID))))
        let value = UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7], digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
        guard value != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) else { throw WorkspaceMutationContractFailureV1.invalidID }
        return value
    }
    static func entity(partID: UUID, locationID: UUID) throws -> WorkspaceEntityIdentityV1 { try .init(kind: .stockBalanceStream, id: id(partID: partID, locationID: locationID)) }
}

struct WorkspaceEntityRevisionV1: Codable, Equatable, Sendable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
}

struct WorkspaceRevisionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let writerInstanceID: UUID
    let revision: UInt64
    let entityRevisions: [WorkspaceEntityRevisionV1]

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        writerInstanceID: UUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
        revision: UInt64,
        entityRevisions: [WorkspaceEntityRevisionV1]
    ) throws {
        guard generationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw WorkspaceMutationContractFailureV1.invalidID
        }
        let ordered = entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey }
        guard Set(ordered.map(\.identity)).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.duplicateEntityRevision
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.writerInstanceID = writerInstanceID
        self.revision = revision
        self.entityRevisions = ordered
    }
}

struct WorkspaceExpectedRevisionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let writerInstanceID: UUID
    let workspaceRevision: UInt64
    let entityRevisions: [WorkspaceEntityRevisionV1]

    init(snapshot: WorkspaceRevisionV1) {
        workspaceID = snapshot.workspaceID
        generationID = snapshot.generationID
        writerInstanceID = snapshot.writerInstanceID
        workspaceRevision = snapshot.revision
        entityRevisions = snapshot.entityRevisions
    }

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        writerInstanceID: UUID,
        workspaceRevision: UInt64,
        entityRevisions: [WorkspaceEntityRevisionV1]
    ) throws {
        let validated = try WorkspaceRevisionV1(
            workspaceID: workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            revision: workspaceRevision,
            entityRevisions: entityRevisions
        )
        self.init(snapshot: validated)
    }
}

struct FirstSignMutationV1: Codable, Equatable, Sendable {
    struct NewSiteV1: Codable, Equatable, Sendable {
        let id: UUID
        let label: String
        let address: String?
        let timeZoneID: String?
    }

    let siteID: UUID
    let newSite: NewSiteV1?
    let assetID: UUID
    let assetLabel: String
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
    let createdAt: Date
    /// Nil only for decoding/replaying the frozen pre-V6 command shape. Every
    /// live V6 caller supplies all three placement fields atomically.
    let initialPlacementMutationID: MutationIDV1?
    let initialPlacementEventID: UUID?
    let initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1?

    init(
        siteID: UUID,
        newSite: NewSiteV1?,
        assetID: UUID,
        assetLabel: String,
        packID: String,
        packSchemaVersion: Int,
        packContentVersion: Int,
        createdAt: Date,
        initialPlacementMutationID: MutationIDV1? = nil,
        initialPlacementEventID: UUID? = nil,
        initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1? = nil
    ) {
        self.siteID = siteID
        self.newSite = newSite
        self.assetID = assetID
        self.assetLabel = assetLabel
        self.packID = packID
        self.packSchemaVersion = packSchemaVersion
        self.packContentVersion = packContentVersion
        self.createdAt = createdAt
        self.initialPlacementMutationID = initialPlacementMutationID
        self.initialPlacementEventID = initialPlacementEventID
        self.initialPhysicalEpisodeID = initialPhysicalEpisodeID
    }
}

struct CheckDraftMutationV1: Codable, Equatable, Sendable {
    let recordID: UUID
    let assetID: UUID
    let issueID: UUID?
    let parentRecordID: UUID?
    let stage: String
    let draftStepKey: String?
    let startedAt: Date
    let observedAtUTC: Date?
    let timeZoneID: String?
    let utcOffsetMinutes: Int?
    let localDate: String?
    let localTime: String?
    let afterDarkAcknowledgementKey: String?
    let afterDarkAcknowledgementCopy: String?
    let afterDarkAcknowledgementVersion: String?
    let afterDarkAcknowledgementAccepted: Bool?
    let safePositionAcknowledgementKey: String?
    let safePositionAcknowledgementCopy: String?
    let safePositionAcknowledgementVersion: String?
    let safePositionAcknowledgementAccepted: Bool?
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
    let pdfTemplateID: String
    let pdfTemplateVersion: Int
    /// Optional only for decoding/replaying pre-ObservationAndTimeSchemaV1
    /// commands. New callers submit both values atomically.
    let observationBasis: ObservationBasisV1?
    let temporalContext: TemporalContextV1?

    init(
        recordID: UUID,
        assetID: UUID,
        issueID: UUID?,
        parentRecordID: UUID?,
        stage: String,
        draftStepKey: String?,
        startedAt: Date,
        observedAtUTC: Date?,
        timeZoneID: String?,
        utcOffsetMinutes: Int?,
        localDate: String?,
        localTime: String?,
        afterDarkAcknowledgementKey: String?,
        afterDarkAcknowledgementCopy: String?,
        afterDarkAcknowledgementVersion: String?,
        afterDarkAcknowledgementAccepted: Bool?,
        safePositionAcknowledgementKey: String?,
        safePositionAcknowledgementCopy: String?,
        safePositionAcknowledgementVersion: String?,
        safePositionAcknowledgementAccepted: Bool?,
        packID: String,
        packSchemaVersion: Int,
        packContentVersion: Int,
        pdfTemplateID: String,
        pdfTemplateVersion: Int,
        observationBasis: ObservationBasisV1? = nil,
        temporalContext: TemporalContextV1? = nil
    ) {
        self.recordID = recordID
        self.assetID = assetID
        self.issueID = issueID
        self.parentRecordID = parentRecordID
        self.stage = stage
        self.draftStepKey = draftStepKey
        self.startedAt = startedAt
        self.observedAtUTC = observedAtUTC
        self.timeZoneID = timeZoneID
        self.utcOffsetMinutes = utcOffsetMinutes
        self.localDate = localDate
        self.localTime = localTime
        self.afterDarkAcknowledgementKey = afterDarkAcknowledgementKey
        self.afterDarkAcknowledgementCopy = afterDarkAcknowledgementCopy
        self.afterDarkAcknowledgementVersion = afterDarkAcknowledgementVersion
        self.afterDarkAcknowledgementAccepted = afterDarkAcknowledgementAccepted
        self.safePositionAcknowledgementKey = safePositionAcknowledgementKey
        self.safePositionAcknowledgementCopy = safePositionAcknowledgementCopy
        self.safePositionAcknowledgementVersion = safePositionAcknowledgementVersion
        self.safePositionAcknowledgementAccepted = safePositionAcknowledgementAccepted
        self.packID = packID
        self.packSchemaVersion = packSchemaVersion
        self.packContentVersion = packContentVersion
        self.pdfTemplateID = pdfTemplateID
        self.pdfTemplateVersion = pdfTemplateVersion
        self.observationBasis = observationBasis
        self.temporalContext = temporalContext
    }
}

struct CheckEvidenceMutationV1: Codable, Equatable, Sendable {
    let evidenceID: UUID
    let draftID: UUID
    let purposeKey: String
    let relativePath: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int
    let thumbnailSHA256: String
    let nextDraftStepKey: String
    let createdAt: Date
}

struct SiteTimeZoneMutationV1: Codable, Equatable, Sendable {
    let siteID: UUID
    let timeZoneID: String
    let confirmedAt: Date
}

struct ArchiveEntitiesMutationV1: Codable, Equatable, Sendable {
    let identities: [WorkspaceEntityIdentityV1]
    let reason: String
}

struct DeleteAssetMutationV1: Codable, Equatable, Sendable {
    let deletionID: UUID
    let assetID: UUID
    let planDigest: String
}

struct DeleteSiteMutationV1: Codable, Equatable, Sendable {
    let deletionID: UUID
    let siteID: UUID
    let planDigest: String
}

struct EraseWorkspaceMutationV1: Codable, Equatable, Sendable {
    let eraseID: UUID
    let targetGenerationID: UUID
    let oldPointerDigest: String
    let emptyLedgerDigest: String
}

struct FinalizeCheckMutationV1: Codable, Equatable, Sendable {
    let finalizationMutationID: UUID
    let assetID: UUID
    let recordID: UUID
    let packetID: UUID
    let reportID: UUID
    let issueID: UUID?
    let semanticDigest: String
    let contentDigests: [String]
}

struct FinalizeCorrectionMutationV1: Codable, Equatable, Sendable {
    let finalizationMutationID: UUID
    let assetID: UUID
    let correctionRecordID: UUID
    let revisesRecordID: UUID
    let packetID: UUID
    let reportID: UUID
    let replacesReportID: UUID
    let semanticDigest: String
}

struct RecordWorkMutationV1: Codable, Equatable, Sendable {
    let workMutationID: UUID
    let assetID: UUID
    let issueID: UUID
    let recordID: UUID
    let evidenceIDs: [UUID]
    let semanticDigest: String
}

struct RestoreWorkspaceMutationV1: Codable, Equatable, Sendable {
    let restoreID: UUID
    let mode: String
    let sourceArchiveDigest: String
    let targetGenerationID: UUID
}

struct LocationHierarchyMutationV1: Codable, Equatable, Sendable {
    let plan: LocationHierarchyChangePlanV1
    let placementChanges: [AssetPlacementChangePlanV1]

    init(plan: LocationHierarchyChangePlanV1, placementChanges: [AssetPlacementChangePlanV1]) throws {
        try plan.validate()
        let ordered = placementChanges.sorted { $0.basis.assetID.uuidString < $1.basis.assetID.uuidString }
        guard ordered == placementChanges,
              Set(ordered.map(\.basis.assetID)).count == ordered.count,
              ordered.map(\.basis.assetID) == plan.bindingChangedAssetIDs,
              ordered.allSatisfy({
                  $0.operationID == plan.operationID
                    && $0.mutationID.rawValue == plan.operationID
                    && $0.basis.workspaceID == plan.workspaceID
                    && plan.continuityByAssetID[$0.basis.assetID] == $0.basis.reviewedContinuity
              }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.plan = plan
        self.placementChanges = ordered
    }
}

enum SavedSmartViewMutationDispositionV1: String, Codable, Equatable, Sendable {
    case upsert = "UPSERT"
    case delete = "DELETE"
}

/// The sole canonical smart-view mutation payload. Query text may occur only
/// inside the workspace-owned descriptor; device preferences store only a
/// stable selected-view ID.
struct SavedSmartViewMutationV1: Codable, Equatable, Sendable {
    let disposition: SavedSmartViewMutationDispositionV1
    let workspaceID: UUID
    let id: UUID
    let stableID: String
    let expectedDescriptorRevision: UInt64
    let mutationID: UUID
    let descriptor: SavedSmartViewDescriptorV1?

    init(upserting descriptor: SavedSmartViewDescriptorV1) throws {
        try descriptor.validate()
        disposition = .upsert
        workspaceID = descriptor.workspaceID
        id = descriptor.id
        stableID = descriptor.stableID
        expectedDescriptorRevision = descriptor.revision - 1
        mutationID = descriptor.mutationID
        self.descriptor = descriptor
        try validate()
    }

    init(
        deletingID id: UUID,
        workspaceID: UUID,
        stableID: String,
        expectedDescriptorRevision: UInt64,
        mutationID: UUID
    ) throws {
        disposition = .delete
        self.workspaceID = workspaceID
        self.id = id
        self.stableID = stableID
        self.expectedDescriptorRevision = expectedDescriptorRevision
        self.mutationID = mutationID
        descriptor = nil
        try validate()
    }

    func validate() throws {
        guard workspaceID != SearchContractValidationV1.zeroUUID,
              id != SearchContractValidationV1.zeroUUID,
              mutationID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(stableID) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        switch disposition {
        case .upsert:
            guard let descriptor,
                  descriptor.origin == .userSaved,
                  descriptor.workspaceID == workspaceID,
                  descriptor.id == id,
                  descriptor.stableID == stableID,
                  descriptor.mutationID == mutationID,
                  expectedDescriptorRevision < UInt64.max,
                  descriptor.revision == expectedDescriptorRevision + 1 else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            try descriptor.validate()
        case .delete:
            guard descriptor == nil,
                  expectedDescriptorRevision > 0,
                  !stableID.hasPrefix("builtin.search.") else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
        }
    }
}

/// Replaces the single typed assurance companion for an existing workflow
/// record. The command deliberately reuses the workflow-record mutation
/// identity so receipts, replay and tombstones do not acquire a new root.
struct RequirementAssuranceMutationV1: Codable, Equatable, Sendable {
    let snapshot: RequirementAssuranceSnapshotV1
    let expectedEvaluatedRevision: UInt64
    let mutationID: UUID

    init(
        snapshot: RequirementAssuranceSnapshotV1,
        expectedEvaluatedRevision: UInt64,
        mutationID: UUID
    ) throws {
        self.snapshot = snapshot
        self.expectedEvaluatedRevision = expectedEvaluatedRevision
        self.mutationID = mutationID
        try validate()
    }

    func validate() throws {
        try snapshot.validate()
        guard mutationID != SearchContractValidationV1.zeroUUID,
              expectedEvaluatedRevision < UInt64.max,
              snapshot.evaluatedRevision == expectedEvaluatedRevision + 1 else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }
}

enum PartyAccountabilityMutationV1: Codable, Equatable, Sendable {
    case recordParty(ServicePartyReferenceV1)
    case appendSiteRole(SitePartyRoleEventV1)
    case appendActorSnapshot(ActorSnapshotV1)
    case appendQualificationSnapshot(QualificationSnapshotV1)
    case appendSignoff(SignoffSnapshotV1)

    var workspaceID: WorkspaceID {
        switch self {
        case let .recordParty(v): v.workspaceID
        case let .appendSiteRole(v): v.workspaceID
        case let .appendActorSnapshot(v): v.workspaceID
        case let .appendQualificationSnapshot(v): v.workspaceID
        case let .appendSignoff(v): v.workspaceID
        }
    }
    var mutationID: MutationIDV1? {
        switch self {
        case let .recordParty(v): v.mutationID
        case let .appendSiteRole(v): v.mutationID
        case .appendActorSnapshot, .appendQualificationSnapshot: nil
        case let .appendSignoff(v): v.mutationID
        }
    }
    func validate() throws {
        switch self {
        case let .recordParty(v): try v.validate()
        case let .appendSiteRole(v): try v.validate()
        case let .appendActorSnapshot(v): try v.validate()
        case let .appendQualificationSnapshot(v): try v.validate()
        case let .appendSignoff(v): try v.validate()
        }
    }
    var affectedIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .recordParty(v): try .init(kind: .serviceParty, id: v.partyID)
            case let .appendSiteRole(v): try .init(kind: .sitePartyRoleEvent, id: v.eventID)
            case let .appendActorSnapshot(v): try .init(kind: .actorSnapshot, id: v.snapshotID)
            case let .appendQualificationSnapshot(v): try .init(kind: .qualificationSnapshot, id: v.snapshotID)
            case let .appendSignoff(v): try .init(kind: .signoffSnapshot, id: v.snapshotID)
            }
        }
    }

}

/// The one writer payload for C39 asset-semantic history.  The physical
/// Asset row remains the mutation identity; all semantic records are carried
/// as one command and therefore share one expected aggregate revision and
/// MutationID.  Classification and replacement deliberately have no
/// standalone lifecycle form here: their companion facts are admitted only
/// through the atomic pair operations.
enum AssetSemanticsMutationOperationV1: String, Codable, CaseIterable, Sendable {
    case appendKindBinding = "APPEND_KIND_BINDING"
    case appendWorkflowCapabilityBinding = "APPEND_WORKFLOW_CAPABILITY_BINDING"
    case appendProductIdentity = "APPEND_PRODUCT_IDENTITY"
    case appendLifecycle = "APPEND_LIFECYCLE"
    case classifyKindAndLifecycle = "CLASSIFY_KIND_AND_LIFECYCLE"
    case replaceWithSuccessor = "REPLACE_WITH_SUCCESSOR"
    case captureWorkSubjectScope = "CAPTURE_WORK_SUBJECT_SCOPE"
}

struct AssetSemanticsMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let assetID: UUID
    let expectedAssetRevision: UInt64
    let mutationID: MutationIDV1
    let operation: AssetSemanticsMutationOperationV1
    let kindBinding: AssetKindBindingEventV1?
    let workflowCapabilityBinding: AssetWorkflowCapabilityBindingEventV1?
    let productIdentity: AssetProductIdentityV1?
    let lifecycleEvent: AssetLifecycleEventV1?
    let successorLink: AssetSuccessorLinkV1?
    let workSubjectScope: WorkSubjectScopeSnapshotV1?

    init(
        workspaceID: WorkspaceID,
        assetID: UUID,
        expectedAssetRevision: UInt64,
        mutationID: MutationIDV1,
        operation: AssetSemanticsMutationOperationV1,
        kindBinding: AssetKindBindingEventV1? = nil,
        workflowCapabilityBinding: AssetWorkflowCapabilityBindingEventV1? = nil,
        productIdentity: AssetProductIdentityV1? = nil,
        lifecycleEvent: AssetLifecycleEventV1? = nil,
        successorLink: AssetSuccessorLinkV1? = nil,
        workSubjectScope: WorkSubjectScopeSnapshotV1? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.assetID = assetID
        self.expectedAssetRevision = expectedAssetRevision
        self.mutationID = mutationID
        self.operation = operation
        self.kindBinding = kindBinding
        self.workflowCapabilityBinding = workflowCapabilityBinding
        self.productIdentity = productIdentity
        self.lifecycleEvent = lifecycleEvent
        self.successorLink = successorLink
        self.workSubjectScope = workSubjectScope
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != Self.zeroUUID,
              assetID != Self.zeroUUID,
              expectedAssetRevision < UInt64.max else {
            throw AssetSemanticContractFailureV1.invalidValue
        }

        let records = [
            kindBinding.map { $0.eventID },
            workflowCapabilityBinding.map { $0.eventID },
            productIdentity.map { $0.identityID },
            lifecycleEvent.map { $0.record.eventID },
            successorLink.map { $0.linkID },
            workSubjectScope.map { $0.snapshotID },
        ].compactMap { $0 }
        guard Set(records).count == records.count else {
            throw AssetSemanticContractFailureV1.duplicateValue
        }

        if let value = kindBinding {
            try value.validate()
            try validateCommon(
                workspace: value.workspaceID,
                asset: value.assetID,
                mutation: value.mutationID,
                revision: value.revision
            )
        }
        if let value = workflowCapabilityBinding {
            try value.validate()
            try validateCommon(
                workspace: value.workspaceID,
                asset: value.assetID,
                mutation: value.mutationID,
                revision: value.revision
            )
        }
        if let value = productIdentity {
            try value.validate()
            try validateCommon(
                workspace: value.workspaceID,
                asset: value.assetID,
                mutation: value.mutationID,
                revision: value.revision
            )
        }
        if let value = lifecycleEvent {
            try value.validate()
            try validateCommon(
                workspace: value.record.workspaceID,
                asset: value.record.assetID,
                mutation: value.record.mutationID,
                revision: value.record.revision
            )
        }
        if let value = successorLink {
            try value.validate()
            try validateCommon(
                workspace: value.workspaceID,
                asset: value.predecessorAssetID,
                mutation: value.mutationID,
                revision: value.revision
            )
        }
        if let value = workSubjectScope {
            try value.validate()
            guard value.workspaceID == workspaceID else {
                throw AssetSemanticContractFailureV1.crossWorkspaceReference
            }
            let scopedAssetIDs = Set(value.subjects.flatMap { subject -> [UUID] in
                switch subject.kind {
                case .asset:
                    return [subject.subjectID]
                case .compositionComponent, .functionalRelationship:
                    return subject.ownerAssetID.map { [$0] } ?? []
                case .site, .locationNode:
                    return []
                }
            })
            guard scopedAssetIDs.contains(assetID)
                    || value.semanticBindings.contains(where: { $0.assetID == assetID }) else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
        }

        switch operation {
        case .appendKindBinding:
            guard kindBinding != nil,
                  workflowCapabilityBinding == nil,
                  productIdentity == nil,
                  lifecycleEvent == nil,
                  successorLink == nil,
                  workSubjectScope == nil else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            try requireNextRevision(kindBinding?.revision)
        case .appendWorkflowCapabilityBinding:
            guard kindBinding == nil,
                  workflowCapabilityBinding != nil,
                  productIdentity == nil,
                  lifecycleEvent == nil,
                  successorLink == nil,
                  workSubjectScope == nil else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            try requireNextRevision(workflowCapabilityBinding?.revision)
        case .appendProductIdentity:
            guard kindBinding == nil,
                  workflowCapabilityBinding == nil,
                  productIdentity != nil,
                  lifecycleEvent == nil,
                  successorLink == nil,
                  workSubjectScope == nil else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            try requireNextRevision(productIdentity?.revision)
        case .appendLifecycle:
            guard kindBinding == nil,
                  workflowCapabilityBinding == nil,
                  productIdentity == nil,
                  let lifecycleEvent,
                  successorLink == nil,
                  workSubjectScope == nil,
                  lifecycleEvent.kind != .classificationChangedRecorded,
                  lifecycleEvent.kind != .replacedRecorded else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
            try requireNextRevision(lifecycleEvent.record.revision)
        case .classifyKindAndLifecycle:
            guard let kindBinding,
                  let lifecycleEvent,
                  workflowCapabilityBinding == nil,
                  productIdentity == nil,
                  successorLink == nil,
                  workSubjectScope == nil,
                  lifecycleEvent.kind == .classificationChangedRecorded,
                  kindBinding.revision == lifecycleEvent.record.revision,
                  kindBinding.recordedAt == lifecycleEvent.record.recordedAt else {
                throw AssetSemanticContractFailureV1.invalidAtomicReference
            }
            try lifecycleEvent.validateAtomicReference(kindBinding: kindBinding)
            try requireNextRevision(kindBinding.revision)
        case .replaceWithSuccessor:
            guard kindBinding == nil,
                  workflowCapabilityBinding == nil,
                  productIdentity == nil,
                  let lifecycleEvent,
                  let successorLink,
                  workSubjectScope == nil,
                  lifecycleEvent.kind == .replacedRecorded,
                  successorLink.revision == lifecycleEvent.record.revision,
                  successorLink.recordedAt == lifecycleEvent.record.recordedAt else {
                throw AssetSemanticContractFailureV1.invalidAtomicReference
            }
            try lifecycleEvent.validateAtomicReference(successorLink: successorLink)
            try requireNextRevision(successorLink.revision)
        case .captureWorkSubjectScope:
            guard kindBinding == nil,
                  workflowCapabilityBinding == nil,
                  productIdentity == nil,
                  lifecycleEvent == nil,
                  successorLink == nil,
                  workSubjectScope != nil else {
                throw AssetSemanticContractFailureV1.invalidValue
            }
        }
    }

    var affectedIdentity: WorkspaceEntityIdentityV1 {
        get throws { try WorkspaceEntityIdentityV1(kind: .asset, id: assetID) }
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }

    private func validateCommon(
        workspace: WorkspaceID,
        asset: UUID,
        mutation: MutationIDV1,
        revision: UInt64
    ) throws {
        guard workspace == workspaceID,
              asset == assetID,
              mutation == mutationID,
              revision > 0,
              Self.isFiniteDate(recordedDate(for: operation)) else {
            throw AssetSemanticContractFailureV1.crossWorkspaceReference
        }
    }

    private func requireNextRevision(_ revision: UInt64?) throws {
        guard let revision,
              expectedAssetRevision < UInt64.max,
              revision == expectedAssetRevision + 1 else {
            throw AssetSemanticContractFailureV1.invalidValue
        }
    }

    private func recordedDate(for operation: AssetSemanticsMutationOperationV1) -> Date {
        switch operation {
        case .appendKindBinding:
            return kindBinding?.recordedAt ?? .distantPast
        case .appendWorkflowCapabilityBinding:
            return workflowCapabilityBinding?.recordedAt ?? .distantPast
        case .appendProductIdentity:
            return productIdentity?.recordedAt ?? .distantPast
        case .appendLifecycle, .classifyKindAndLifecycle:
            return lifecycleEvent?.record.recordedAt ?? .distantPast
        case .replaceWithSuccessor:
            return successorLink?.recordedAt ?? .distantPast
        case .captureWorkSubjectScope:
            return workSubjectScope?.recordedAt ?? .distantPast
        }
    }

    private static func isFiniteDate(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }

    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// Closed C40 mutation payload. Each case carries the complete immutable
/// canonical post-image; writers never reconstruct authority or criterion
/// meaning from scalar command metadata.
enum AuthorityCriterionMutationPayloadV1: Codable, Equatable, Sendable {
    case appendAuthoritySource(AuthoritySourceReleaseV1)
    case supersedeAuthoritySource(AuthoritySourceReleaseV1)
    case appendRequirementBasis(RequirementBasisBindingV1)
    case supersedeRequirementBasis(RequirementBasisBindingV1)
    case appendApplicabilityContext(ApplicabilityContextSnapshotV1)
    case supersedeApplicabilityContext(ApplicabilityContextSnapshotV1)
    case appendAssessmentScope(AssessmentScopeSnapshotV1)
    case supersedeAssessmentScope(AssessmentScopeSnapshotV1)
    case appendSeverityScale(SeverityScaleReleaseV1)
    case supersedeSeverityScale(SeverityScaleReleaseV1)
    case appendFindingClassification(FindingClassificationBindingV1)
    case supersedeFindingClassification(FindingClassificationBindingV1)
    case appendMeasurementProtocol(MeasurementProtocolReleaseV1)
    case supersedeMeasurementProtocol(MeasurementProtocolReleaseV1)
    case appendEvaluatorDescriptor(DerivedFactEvaluatorDescriptorV1)
    case supersedeEvaluatorDescriptor(DerivedFactEvaluatorDescriptorV1)
    case appendDerivedFact(DerivedFactProvenanceV1)
    case supersedeDerivedFact(DerivedFactProvenanceV1)

    var workspaceID: WorkspaceID {
        switch self {
        case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v): v.workspaceID
        case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v): v.workspaceID
        case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v): v.workspaceID
        case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v): v.workspaceID
        case let .appendSeverityScale(v), let .supersedeSeverityScale(v): v.workspaceID
        case let .appendFindingClassification(v), let .supersedeFindingClassification(v): v.workspaceID
        case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v): v.workspaceID
        case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v): v.workspaceID
        case let .appendDerivedFact(v), let .supersedeDerivedFact(v): v.workspaceID
        }
    }

    var mutationID: MutationIDV1 {
        switch self {
        case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v): v.mutationID
        case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v): v.mutationID
        case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v): v.mutationID
        case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v): v.mutationID
        case let .appendSeverityScale(v), let .supersedeSeverityScale(v): v.mutationID
        case let .appendFindingClassification(v), let .supersedeFindingClassification(v): v.mutationID
        case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v): v.mutationID
        case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v): v.mutationID
        case let .appendDerivedFact(v), let .supersedeDerivedFact(v): v.mutationID
        }
    }

    var revision: UInt64 {
        switch self {
        case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v): v.revision
        case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v): v.revision
        case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v): v.revision
        case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v): v.revision
        case let .appendSeverityScale(v), let .supersedeSeverityScale(v): v.revision
        case let .appendFindingClassification(v), let .supersedeFindingClassification(v): v.revision
        case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v): v.revision
        case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v): v.revision
        case let .appendDerivedFact(v), let .supersedeDerivedFact(v): v.revision
        }
    }

    var semanticSHA256: String {
        switch self {
        case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v): v.releaseSHA256
        case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v): v.bindingSHA256
        case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v): v.snapshotSHA256
        case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v): v.snapshotSHA256
        case let .appendSeverityScale(v), let .supersedeSeverityScale(v): v.releaseSHA256
        case let .appendFindingClassification(v), let .supersedeFindingClassification(v): v.bindingSHA256
        case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v): v.releaseSHA256
        case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v): v.descriptorSHA256
        case let .appendDerivedFact(v), let .supersedeDerivedFact(v): v.provenanceSHA256
        }
    }

    var affectedIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v):
                try .init(kind: .authoritySourceRelease, id: v.releaseID)
            case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v):
                try .init(kind: .requirementBasisBinding, id: v.bindingID)
            case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v):
                try .init(kind: .applicabilityContextSnapshot, id: v.snapshotID)
            case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v):
                try .init(kind: .assessmentScopeSnapshot, id: v.snapshotID)
            case let .appendSeverityScale(v), let .supersedeSeverityScale(v):
                try .init(kind: .severityScaleRelease, id: v.releaseID)
            case let .appendFindingClassification(v), let .supersedeFindingClassification(v):
                try .init(kind: .findingClassificationBinding, id: v.bindingID)
            case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v):
                try .init(kind: .measurementProtocolRelease, id: v.releaseID)
            case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v):
                try .init(kind: .derivedFactEvaluatorDescriptor, id: v.descriptorID)
            case let .appendDerivedFact(v), let .supersedeDerivedFact(v):
                try .init(kind: .derivedFactProvenance, id: v.provenanceID)
            }
        }
    }

    var predecessorIdentity: WorkspaceEntityIdentityV1? {
        get throws {
            switch self {
            case .appendAuthoritySource, .appendRequirementBasis,
                 .appendApplicabilityContext, .appendAssessmentScope,
                 .appendSeverityScale, .appendFindingClassification,
                 .appendMeasurementProtocol, .appendEvaluatorDescriptor,
                 .appendDerivedFact:
                nil
            case let .supersedeAuthoritySource(v):
                try v.supersedesReleaseID.map { try WorkspaceEntityIdentityV1(kind: .authoritySourceRelease, id: $0) }
            case let .supersedeRequirementBasis(v):
                try v.supersedesBindingID.map { try WorkspaceEntityIdentityV1(kind: .requirementBasisBinding, id: $0) }
            case let .supersedeApplicabilityContext(v):
                try v.supersedesSnapshotID.map { try WorkspaceEntityIdentityV1(kind: .applicabilityContextSnapshot, id: $0) }
            case let .supersedeAssessmentScope(v):
                try v.supersedesSnapshotID.map { try WorkspaceEntityIdentityV1(kind: .assessmentScopeSnapshot, id: $0) }
            case let .supersedeSeverityScale(v):
                try v.supersedesReleaseID.map { try WorkspaceEntityIdentityV1(kind: .severityScaleRelease, id: $0) }
            case let .supersedeFindingClassification(v):
                try v.supersedesBindingID.map { try WorkspaceEntityIdentityV1(kind: .findingClassificationBinding, id: $0) }
            case let .supersedeMeasurementProtocol(v):
                try v.supersedesReleaseID.map { try WorkspaceEntityIdentityV1(kind: .measurementProtocolRelease, id: $0) }
            case let .supersedeEvaluatorDescriptor(v):
                try v.supersedesDescriptorID.map { try WorkspaceEntityIdentityV1(kind: .derivedFactEvaluatorDescriptor, id: $0) }
            case let .supersedeDerivedFact(v):
                try v.predecessorProvenanceID.map { try WorkspaceEntityIdentityV1(kind: .derivedFactProvenance, id: $0) }
            }
        }
    }

    var isSupersession: Bool {
        switch self {
        case .supersedeAuthoritySource, .supersedeRequirementBasis,
             .supersedeApplicabilityContext, .supersedeAssessmentScope,
             .supersedeSeverityScale, .supersedeFindingClassification,
             .supersedeMeasurementProtocol, .supersedeEvaluatorDescriptor,
             .supersedeDerivedFact:
            true
        default:
            false
        }
    }

    func validate() throws {
        switch self {
        case let .appendAuthoritySource(v): try v.validate(); guard v.supersedesReleaseID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeAuthoritySource(v): try v.validate(); guard v.supersedesReleaseID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendRequirementBasis(v): try v.validate(); guard v.supersedesBindingID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeRequirementBasis(v): try v.validate(); guard v.supersedesBindingID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendApplicabilityContext(v): try v.validate(); guard v.supersedesSnapshotID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeApplicabilityContext(v): try v.validate(); guard v.supersedesSnapshotID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendAssessmentScope(v): try v.validate(); guard v.supersedesSnapshotID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeAssessmentScope(v): try v.validate(); guard v.supersedesSnapshotID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendSeverityScale(v): try v.validate(); guard v.supersedesReleaseID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeSeverityScale(v): try v.validate(); guard v.supersedesReleaseID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendFindingClassification(v): try v.validate(); guard v.supersedesBindingID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeFindingClassification(v): try v.validate(); guard v.supersedesBindingID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendMeasurementProtocol(v): try v.validate(); guard v.supersedesReleaseID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeMeasurementProtocol(v): try v.validate(); guard v.supersedesReleaseID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendEvaluatorDescriptor(v): try v.validate(); guard v.supersedesDescriptorID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeEvaluatorDescriptor(v): try v.validate(); guard v.supersedesDescriptorID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .appendDerivedFact(v): try v.validate(); guard v.predecessorProvenanceID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeDerivedFact(v): try v.validate(); guard v.predecessorProvenanceID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        }
    }
}

struct AuthorityCriterionMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let expectedRevision: UInt64
    let mutationID: MutationIDV1
    let postImage: AuthorityCriterionMutationPayloadV1

    init(
        workspaceID: WorkspaceID,
        expectedRevision: UInt64,
        mutationID: MutationIDV1,
        postImage: AuthorityCriterionMutationPayloadV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.mutationID = mutationID
        self.postImage = postImage
        try validate()
    }

    func validate() throws {
        try postImage.validate()
        let predecessor = try postImage.predecessorIdentity
        let validRevision: Bool
        if predecessor == nil {
            validRevision = !postImage.isSupersession
                && expectedRevision == 0
                && postImage.revision == 1
        } else {
            validRevision = postImage.isSupersession
                && expectedRevision > 0
                && expectedRevision < UInt64.max
                && postImage.revision == expectedRevision + 1
        }
        guard schemaVersion == Self.schemaVersion,
              workspaceID == postImage.workspaceID,
              mutationID == postImage.mutationID,
              validRevision,
              MutationEnvelopeV1.isSHA256(postImage.semanticSHA256) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    var affectedIdentity: WorkspaceEntityIdentityV1 { get throws { try postImage.affectedIdentity } }
    var concurrencyIdentity: WorkspaceEntityIdentityV1 {
        get throws { try postImage.predecessorIdentity ?? postImage.affectedIdentity }
    }
    func canonicalData() throws -> Data { try validate(); return try WorkspaceMutationCanonicalV1.data(self) }
    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        return value
    }
}

enum FunctionalRelationshipMutationPayloadV1: Codable, Equatable, Sendable {
    case appendDescriptor(FunctionalRelationshipTypeDescriptorV1)
    case supersedeDescriptor(FunctionalRelationshipTypeDescriptorV1)
    case addRelationship(AssetFunctionalRelationshipEventV1)
    case endRelationship(AssetFunctionalRelationshipEventV1)
    case supersedeRelationship(AssetFunctionalRelationshipEventV1)

    var workspaceID: WorkspaceID {
        switch self {
        case let .appendDescriptor(v), let .supersedeDescriptor(v): v.workspaceID
        case let .addRelationship(v), let .endRelationship(v), let .supersedeRelationship(v): v.workspaceID
        }
    }
    var mutationID: MutationIDV1 {
        switch self {
        case let .appendDescriptor(v), let .supersedeDescriptor(v): v.mutationID
        case let .addRelationship(v), let .endRelationship(v), let .supersedeRelationship(v): v.mutationID
        }
    }
    var revision: UInt64 {
        switch self {
        case let .appendDescriptor(v), let .supersedeDescriptor(v): v.revision
        case let .addRelationship(v), let .endRelationship(v), let .supersedeRelationship(v): v.revision
        }
    }
    var semanticSHA256: String {
        switch self {
        case let .appendDescriptor(v), let .supersedeDescriptor(v): v.descriptorSHA256
        case let .addRelationship(v), let .endRelationship(v), let .supersedeRelationship(v): v.eventSHA256
        }
    }
    var affectedIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .appendDescriptor(v), let .supersedeDescriptor(v):
                try .init(kind: .functionalRelationshipTypeDescriptor, id: v.descriptorReleaseID)
            case let .addRelationship(v), let .endRelationship(v), let .supersedeRelationship(v):
                try .init(kind: .assetFunctionalRelationshipEvent, id: v.eventID)
            }
        }
    }
    var predecessorIdentity: WorkspaceEntityIdentityV1? {
        get throws {
            switch self {
            case .appendDescriptor, .addRelationship: nil
            case let .supersedeDescriptor(v):
                try v.supersedesDescriptorReleaseID.map {
                    try .init(kind: .functionalRelationshipTypeDescriptor, id: $0)
                }
            case let .endRelationship(v), let .supersedeRelationship(v):
                try v.predecessorEventID.map {
                    try .init(kind: .assetFunctionalRelationshipEvent, id: $0)
                }
            }
        }
    }
    func validate() throws {
        switch self {
        case let .appendDescriptor(v): try v.validate(); guard v.supersedesDescriptorReleaseID == nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeDescriptor(v): try v.validate(); guard v.supersedesDescriptorReleaseID != nil else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .addRelationship(v): try v.validate(); guard v.action == .added else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .endRelationship(v): try v.validate(); guard v.action == .ended else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case let .supersedeRelationship(v): try v.validate(); guard v.action == .superseded else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        }
    }
}

struct FunctionalRelationshipMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let expectedRevision: UInt64
    let mutationID: MutationIDV1
    let postImage: FunctionalRelationshipMutationPayloadV1

    init(workspaceID: WorkspaceID, expectedRevision: UInt64, mutationID: MutationIDV1,
         postImage: FunctionalRelationshipMutationPayloadV1) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision; self.mutationID = mutationID; self.postImage = postImage
        try validate()
    }
    func validate() throws {
        try postImage.validate()
        let predecessor = try postImage.predecessorIdentity
        guard schemaVersion == Self.schemaVersion, workspaceID == postImage.workspaceID,
              mutationID == postImage.mutationID,
              (predecessor == nil ? (expectedRevision == 0 && postImage.revision == 1)
                : (expectedRevision > 0 && expectedRevision < UInt64.max && postImage.revision == expectedRevision + 1)),
              MutationEnvelopeV1.isSHA256(postImage.semanticSHA256) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        switch postImage {
        case let .addRelationship(v), let .endRelationship(v), let .supersedeRelationship(v):
            guard v.expectedRelationshipRevision == expectedRevision else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
        default: break
        }
    }
    var affectedIdentity: WorkspaceEntityIdentityV1 { get throws { try postImage.affectedIdentity } }
    var concurrencyIdentity: WorkspaceEntityIdentityV1 { get throws { try postImage.predecessorIdentity ?? postImage.affectedIdentity } }
    func canonicalData() throws -> Data { try validate(); return try WorkspaceMutationCanonicalV1.data(self) }
    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }
    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(Self.self, from: data); try value.validate()
        guard try value.canonicalData() == data else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        return value
    }
}

enum EvidenceAssuranceMutationPayloadV1: Codable, Equatable, Sendable {
    case appendVisibility(EvidenceVisibilityV1)
    case supersedeVisibility(EvidenceVisibilityV1)
    case appendLink(ClaimEvidenceLinkV1)
    case supersedeLink(ClaimEvidenceLinkV1)
    case appendManifest(manifest: AssuranceManifestV1, preview: AssuranceProjectionPreviewV1)
    case supersedeManifest(manifest: AssuranceManifestV1, preview: AssuranceProjectionPreviewV1)
    case recordAttestation(value: AttestationV1, manifest: AssuranceManifestV1)
    case supersedeAttestation(value: AttestationV1, manifest: AssuranceManifestV1)
    case voidAttestation(value: AttestationV1, manifest: AssuranceManifestV1)

    var workspaceID: WorkspaceID { switch self { case let .appendVisibility(v),let .supersedeVisibility(v):v.workspaceID;case let .appendLink(v),let .supersedeLink(v):v.workspaceID;case let .appendManifest(v,_),let .supersedeManifest(v,_):v.workspaceID;case let .recordAttestation(v,_),let .supersedeAttestation(v,_),let .voidAttestation(v,_):v.workspaceID } }
    var mutationID: MutationIDV1 { switch self { case let .appendVisibility(v),let .supersedeVisibility(v):v.mutationID;case let .appendLink(v),let .supersedeLink(v):v.mutationID;case let .appendManifest(v,_),let .supersedeManifest(v,_):v.mutationID;case let .recordAttestation(v,_),let .supersedeAttestation(v,_),let .voidAttestation(v,_):v.mutationID } }
    var revision: UInt64 { switch self { case let .appendVisibility(v),let .supersedeVisibility(v):v.revision;case let .appendLink(v),let .supersedeLink(v):v.revision;case let .appendManifest(v,_),let .supersedeManifest(v,_):v.revision;case let .recordAttestation(v,_),let .supersedeAttestation(v,_),let .voidAttestation(v,_):v.revision } }
    var semanticSHA256:String { switch self {case let .appendVisibility(v),let .supersedeVisibility(v):v.visibilitySHA256;case let .appendLink(v),let .supersedeLink(v):v.linkSHA256;case let .appendManifest(v,_),let .supersedeManifest(v,_):v.manifestSHA256;case let .recordAttestation(v,_),let .supersedeAttestation(v,_),let .voidAttestation(v,_):v.attestationSHA256} }
    var affectedIdentity:WorkspaceEntityIdentityV1 { get throws { switch self {case let .appendVisibility(v),let .supersedeVisibility(v):try .init(kind:.evidenceVisibility,id:v.visibilityID);case let .appendLink(v),let .supersedeLink(v):try .init(kind:.claimEvidenceLink,id:v.linkID);case let .appendManifest(v,_),let .supersedeManifest(v,_):try .init(kind:.assuranceManifest,id:v.manifestID);case let .recordAttestation(v,_),let .supersedeAttestation(v,_),let .voidAttestation(v,_):try .init(kind:.attestation,id:v.attestationID)} } }
    var predecessorIdentity:WorkspaceEntityIdentityV1? { get throws { switch self {case .appendVisibility,.appendLink,.appendManifest,.recordAttestation:nil;case let .supersedeVisibility(v):try v.supersedesVisibilityID.map{try .init(kind:.evidenceVisibility,id:$0)};case let .supersedeLink(v):try v.supersedesLinkID.map{try .init(kind:.claimEvidenceLink,id:$0)};case let .supersedeManifest(v,_):try v.supersedesManifestID.map{try .init(kind:.assuranceManifest,id:$0)};case let .supersedeAttestation(v,_),let .voidAttestation(v,_):try v.supersedesAttestationID.map{try .init(kind:.attestation,id:$0)}} } }
    func validate() throws { switch self {case let .appendVisibility(v):try v.validate();guard v.supersedesVisibilityID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .supersedeVisibility(v):try v.validate();guard v.supersedesVisibilityID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendLink(v):try v.validate();guard v.supersedesLinkID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .supersedeLink(v):try v.validate();guard v.supersedesLinkID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendManifest(v,p):try v.validateFresh(preview:p);guard v.supersedesManifestID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .supersedeManifest(v,p):try v.validateFresh(preview:p);guard v.supersedesManifestID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .recordAttestation(v,m):try v.validate(manifest:m);guard v.action == .recorded else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .supersedeAttestation(v,m):try v.validate(manifest:m);guard v.action == .superseded else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .voidAttestation(v,m):try v.validate(manifest:m);guard v.action == .voided else{throw WorkspaceMutationContractFailureV1.invalidPlan}} }
}

struct EvidenceAssuranceMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:UInt64;let mutationID:MutationIDV1;let postImage:EvidenceAssuranceMutationPayloadV1
    init(workspaceID:WorkspaceID,expectedRevision:UInt64,mutationID:MutationIDV1,postImage:EvidenceAssuranceMutationPayloadV1)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.postImage=postImage;try validate()}
    func validate()throws{try postImage.validate();let predecessor=try postImage.predecessorIdentity;guard schemaVersion==Self.schemaVersion,workspaceID==postImage.workspaceID,mutationID==postImage.mutationID,(predecessor == nil ? expectedRevision==0 && postImage.revision==1 : expectedRevision>0 && expectedRevision<UInt64.max && postImage.revision==expectedRevision+1),MutationEnvelopeV1.isSHA256(postImage.semanticSHA256)else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    var affectedIdentity:WorkspaceEntityIdentityV1{get throws{try postImage.affectedIdentity}};var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{try postImage.predecessorIdentity ?? postImage.affectedIdentity}}
    func canonicalData()throws->Data{try validate();return try WorkspaceMutationCanonicalV1.data(self)};func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}
}
struct InspectionReviewAtomicBundleV1:Codable,Equatable,Sendable{let transition:InspectionReviewTransitionV1;let disposition:ReviewDispositionV1?;let changeRequests:[ChangeRequestV1];init(transition:InspectionReviewTransitionV1,disposition:ReviewDispositionV1?=nil,changeRequests:[ChangeRequestV1]=[])throws{self.transition=transition;self.disposition=disposition;self.changeRequests=changeRequests.sorted{$0.requestRevisionID.uuidString<$1.requestRevisionID.uuidString};try validate()}func validate()throws{try transition.validate();try disposition?.validate();try changeRequests.forEach{$0.validate()};guard changeRequests.count<=InspectionReviewLimitsV1.maximumItems,Set(changeRequests.map(\.requestRevisionID)).count==changeRequests.count,transition.dispositionID==disposition?.dispositionID,transition.changeRequestIDs==changeRequests.map(\.requestID).sorted{$0.uuidString<$1.uuidString},disposition.map({$0.workspaceID==transition.workspaceID&&$0.reviewID==transition.reviewID&&$0.subject==transition.subject&&$0.reviewRevision==transition.revision&&$0.mutationID==transition.mutationID&&$0.changeRequestIDs==transition.changeRequestIDs}) ?? transition.dispositionID==nil,changeRequests.allSatisfy{$0.workspaceID==transition.workspaceID&&$0.reviewID==transition.reviewID&&$0.reviewRevision==transition.revision&&$0.mutationID==transition.mutationID}else{throw WorkspaceMutationContractFailureV1.invalidPlan}}}
enum InspectionReviewMutationPayloadV1:Codable,Equatable,Sendable{case applyReviewBundle(InspectionReviewAtomicBundleV1);case appendCorrectivePolicy(CorrectiveActionPolicyV1);case supersedeCorrectivePolicy(CorrectiveActionPolicyV1);case appendCorrectiveEvent(CorrectiveActionEventV1);case appendCorrectiveEventSuccessor(CorrectiveActionEventV1)
var workspaceID:WorkspaceID{switch self{case let .applyReviewBundle(v):v.transition.workspaceID;case let .appendCorrectivePolicy(v),let .supersedeCorrectivePolicy(v):v.workspaceID;case let .appendCorrectiveEvent(v),let .appendCorrectiveEventSuccessor(v):v.workspaceID}}
var mutationID:MutationIDV1{switch self{case let .applyReviewBundle(v):v.transition.mutationID;case let .appendCorrectivePolicy(v),let .supersedeCorrectivePolicy(v):v.mutationID;case let .appendCorrectiveEvent(v),let .appendCorrectiveEventSuccessor(v):v.mutationID}}
var revision:UInt64{switch self{case let .applyReviewBundle(v):v.transition.revision;case let .appendCorrectivePolicy(v),let .supersedeCorrectivePolicy(v):v.revision;case let .appendCorrectiveEvent(v),let .appendCorrectiveEventSuccessor(v):v.revision}}
var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{switch self{case let .applyReviewBundle(v):var result=[try WorkspaceEntityIdentityV1(kind:.inspectionReviewTransition,id:v.transition.transitionID)];if let d=v.disposition{result.append(try .init(kind:.reviewDisposition,id:d.dispositionID))};result += try v.changeRequests.map{try .init(kind:.changeRequest,id:$0.requestRevisionID)};return result.sorted{$0.stableKey<$1.stableKey};case let .appendCorrectivePolicy(v),let .supersedeCorrectivePolicy(v):return[try .init(kind:.correctiveActionPolicy,id:v.releaseID)];case let .appendCorrectiveEvent(v),let .appendCorrectiveEventSuccessor(v):return[try .init(kind:.correctiveActionEvent,id:v.eventID)]}}}
var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{switch self{case let .applyReviewBundle(v):var result=[try WorkspaceEntityIdentityV1(kind:.inspectionReviewTransition,id:v.transition.predecessorTransitionID ?? v.transition.transitionID)];if let d=v.disposition{result.append(try .init(kind:.reviewDisposition,id:d.supersedesDispositionID ?? d.dispositionID))};result += try v.changeRequests.map{try WorkspaceEntityIdentityV1(kind:.changeRequest,id:$0.supersedesRequestRevisionID ?? $0.requestRevisionID)};return result.sorted{$0.stableKey<$1.stableKey};default:return[try predecessorIdentity ?? affectedIdentities[0]]}}}
var predecessorIdentity:WorkspaceEntityIdentityV1?{get throws{switch self{case let .applyReviewBundle(v):return try v.transition.predecessorTransitionID.map{try .init(kind:.inspectionReviewTransition,id:$0)};case .appendCorrectivePolicy,.appendCorrectiveEvent:return nil;case let .supersedeCorrectivePolicy(v):return try v.supersedesReleaseID.map{try .init(kind:.correctiveActionPolicy,id:$0)};case let .appendCorrectiveEventSuccessor(v):return try v.predecessorEventID.map{try .init(kind:.correctiveActionEvent,id:$0)}}}}
func validate()throws{switch self{case let .applyReviewBundle(v):try v.validate();case let .appendCorrectivePolicy(v):try v.validate();guard v.supersedesReleaseID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .supersedeCorrectivePolicy(v):try v.validate();guard v.supersedesReleaseID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendCorrectiveEvent(v):try v.validate();guard v.predecessorEventID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendCorrectiveEventSuccessor(v):try v.validate();guard v.predecessorEventID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}}}}
struct InspectionReviewMutationV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:UInt64;let mutationID:MutationIDV1;let postImage:InspectionReviewMutationPayloadV1;init(workspaceID:WorkspaceID,expectedRevision:UInt64,mutationID:MutationIDV1,postImage:InspectionReviewMutationPayloadV1)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.postImage=postImage;try validate()}func validate()throws{try postImage.validate();let p=try postImage.predecessorIdentity;guard schemaVersion==Self.schemaVersion,workspaceID==postImage.workspaceID,mutationID==postImage.mutationID,(p==nil ? expectedRevision==0&&postImage.revision==1:expectedRevision>0&&expectedRevision<UInt64.max&&postImage.revision==expectedRevision+1)else{throw WorkspaceMutationContractFailureV1.invalidPlan}}var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{try postImage.affectedIdentities}}var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{try postImage.concurrencyIdentities}}var affectedIdentity:WorkspaceEntityIdentityV1{get throws{switch postImage{case let .applyReviewBundle(b):try .init(kind:.inspectionReviewTransition,id:b.transition.transitionID);default:try affectedIdentities[0]}}}var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{try postImage.predecessorIdentity ?? affectedIdentity}}func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}}

enum WorkPacketMutationPayloadV1:Codable,Equatable,Sendable{case appendManifest(WorkPacketManifestV1);case appendClaim(WorkItemClaimV1);case supersedeClaim(WorkItemClaimV1);case appendLease(WorkLeaseV1);case supersedeLease(WorkLeaseV1);case recordRelease(WorkReleaseV1);case recordHandoff(WorkHandoffV1)
var workspaceID:WorkspaceID{switch self{case let .appendManifest(v):v.workspaceID;case let .appendClaim(v),let .supersedeClaim(v):v.workspaceID;case let .appendLease(v),let .supersedeLease(v):v.workspaceID;case let .recordRelease(v):v.workspaceID;case let .recordHandoff(v):v.workspaceID}}
var mutationID:MutationIDV1{switch self{case let .appendManifest(v):v.mutationID;case let .appendClaim(v),let .supersedeClaim(v):v.mutationID;case let .appendLease(v),let .supersedeLease(v):v.mutationID;case let .recordRelease(v):v.mutationID;case let .recordHandoff(v):v.mutationID}}
var revision:UInt64{switch self{case let .appendManifest(v):v.revision;case let .appendClaim(v),let .supersedeClaim(v):v.revision;case let .appendLease(v),let .supersedeLease(v):v.revision;case let .recordRelease(v):v.revision;case let .recordHandoff(v):v.revision}}
var affectedIdentity:WorkspaceEntityIdentityV1{get throws{switch self{case let .appendManifest(v):try .init(kind:.workPacketManifest,id:v.manifestID);case let .appendClaim(v),let .supersedeClaim(v):try .init(kind:.workItemClaim,id:v.claimID);case let .appendLease(v),let .supersedeLease(v):try .init(kind:.workLease,id:v.leaseID);case let .recordRelease(v):try .init(kind:.workRelease,id:v.releaseID);case let .recordHandoff(v):try .init(kind:.workHandoff,id:v.handoffID)}}}
var predecessorIdentity:WorkspaceEntityIdentityV1?{get throws{switch self{case .appendManifest,.appendClaim,.appendLease,.recordRelease,.recordHandoff:nil;case let .supersedeClaim(v):try v.supersedesClaimID.map{try .init(kind:.workItemClaim,id:$0)};case let .supersedeLease(v):try v.supersedesLeaseID.map{try .init(kind:.workLease,id:$0)}}}}
func validate()throws{switch self{case let .appendManifest(v):try v.validate();case let .appendClaim(v):try v.validate();guard v.supersedesClaimID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .supersedeClaim(v):try v.validate();guard v.supersedesClaimID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendLease(v):try v.validate();guard v.supersedesLeaseID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .supersedeLease(v):try v.validate();guard v.supersedesLeaseID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .recordRelease(v):try v.validate();case let .recordHandoff(v):try v.validate()}}}
struct WorkPacketMutationV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:UInt64;let mutationID:MutationIDV1;let postImage:WorkPacketMutationPayloadV1;init(workspaceID:WorkspaceID,expectedRevision:UInt64,mutationID:MutationIDV1,postImage:WorkPacketMutationPayloadV1)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.postImage=postImage;try validate()}func validate()throws{try postImage.validate();let p=try postImage.predecessorIdentity;guard schemaVersion==Self.schemaVersion,workspaceID==postImage.workspaceID,mutationID==postImage.mutationID,(p==nil ? expectedRevision==0&&postImage.revision==1:expectedRevision>0&&expectedRevision<UInt64.max&&postImage.revision==expectedRevision+1)else{throw WorkspaceMutationContractFailureV1.invalidPlan}}var affectedIdentity:WorkspaceEntityIdentityV1{get throws{try postImage.affectedIdentity}}var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{try postImage.predecessorIdentity ?? postImage.affectedIdentity}}func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}}

enum FieldDraftMutationPayloadV1:Codable,Equatable,Sendable{
    case createCheckpoint(FieldDraftCheckpointV1),reviseCheckpoint(FieldDraftCheckpointV1)
    case appendStagingItem(AttachmentStagingItemV1),reviseStagingItem(AttachmentStagingItemV1)
    case appendCommitSaga(DraftCommitSagaV1),advanceCommitSaga(DraftCommitSagaV1)
    case appendContentReservation(DraftContentReservationV1),reviseContentReservation(DraftContentReservationV1)
    case applyCommitTerminal(DraftCommitTerminalBundleV1,expectedSagaRevision:UInt64)
    case applyDiscardTerminal(DraftDiscardTerminalBundleV1)
    var workspaceID:WorkspaceID{switch self{case let .createCheckpoint(v),let .reviseCheckpoint(v):v.workspaceID;case let .appendStagingItem(v),let .reviseStagingItem(v):v.workspaceID;case let .appendCommitSaga(v),let .advanceCommitSaga(v):v.workspaceID;case let .appendContentReservation(v),let .reviseContentReservation(v):v.workspaceID;case let .applyCommitTerminal(v,_):v.workspaceID;case let .applyDiscardTerminal(v):v.workspaceID}}
    var mutationID:MutationIDV1{switch self{case let .createCheckpoint(v),let .reviseCheckpoint(v):v.mutationID;case let .appendStagingItem(v),let .reviseStagingItem(v):v.mutationID;case let .appendCommitSaga(v),let .advanceCommitSaga(v):v.mutationID;case let .appendContentReservation(v),let .reviseContentReservation(v):v.mutationID;case let .applyCommitTerminal(v,_):v.mutationID;case let .applyDiscardTerminal(v):v.mutationID}}
    var revision:UInt64{switch self{case let .createCheckpoint(v),let .reviseCheckpoint(v):v.draftRevision;case let .appendStagingItem(v),let .reviseStagingItem(v):v.revision;case let .appendCommitSaga(v),let .advanceCommitSaga(v):v.revision;case let .appendContentReservation(v),let .reviseContentReservation(v):v.revision;case let .applyCommitTerminal(v,_):v.committedCheckpoint.draftRevision;case let .applyDiscardTerminal(v):v.discardedCheckpoint.draftRevision}}
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch self{case let .createCheckpoint(v),let .reviseCheckpoint(v):values=[try .init(kind:.fieldDraftCheckpoint,id:v.draftID)];case let .appendStagingItem(v),let .reviseStagingItem(v):values=[try .init(kind:.attachmentStagingItem,id:v.stageID)];case let .appendCommitSaga(v),let .advanceCommitSaga(v):values=[try .init(kind:.draftCommitSaga,id:v.sagaID)];case let .appendContentReservation(v),let .reviseContentReservation(v):values=[try .init(kind:.draftContentReservation,id:v.reservationID)];case let .applyCommitTerminal(v,_):values=[try .init(kind:.draftCommitSaga,id:v.retiredSaga.sagaID),try .init(kind:.fieldDraftCheckpoint,id:v.committedCheckpoint.draftID),try .init(kind:.draftCommitReceipt,id:v.receipt.receiptID)];case let .applyDiscardTerminal(v):values=[try .init(kind:.fieldDraftCheckpoint,id:v.discardedCheckpoint.draftID),try .init(kind:.draftDiscardReceipt,id:v.receipt.receiptID)]};return values.sorted{$0.stableKey<$1.stableKey}}}
    var predecessorIdentity:WorkspaceEntityIdentityV1?{get throws{switch self{case .createCheckpoint,.appendStagingItem,.appendCommitSaga,.appendContentReservation,.applyCommitTerminal,.applyDiscardTerminal:return nil;case let .reviseCheckpoint(v):return try .init(kind:.fieldDraftCheckpoint,id:v.draftID);case let .reviseStagingItem(v):return try .init(kind:.attachmentStagingItem,id:v.stageID);case let .advanceCommitSaga(v):return try v.predecessorSagaID.map{try .init(kind:.draftCommitSaga,id:$0)};case let .reviseContentReservation(v):return try .init(kind:.draftContentReservation,id:v.reservationID)}}}
    func validate()throws{switch self{case let .createCheckpoint(v):try v.validate();guard v.draftRevision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .reviseCheckpoint(v):try v.validate();guard v.draftRevision>1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendStagingItem(v):try v.validate();guard v.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .reviseStagingItem(v):try v.validate();guard v.revision>1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendCommitSaga(v):try v.validate();guard v.predecessorSagaID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .advanceCommitSaga(v):try v.validate();guard v.predecessorSagaID != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .appendContentReservation(v):try v.validate();guard v.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .reviseContentReservation(v):try v.validate();guard v.revision>1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .applyCommitTerminal(v,expectedSagaRevision):try v.validate();guard expectedSagaRevision>0,expectedSagaRevision<UInt64.max,v.retiredSaga.revision==expectedSagaRevision+1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .applyDiscardTerminal(v):try v.validate()}}
}
struct FieldDraftMutationV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:UInt64;let expectedBaseCanonicalRevision:UInt64;let mutationID:MutationIDV1;let postImage:FieldDraftMutationPayloadV1;init(workspaceID:WorkspaceID,expectedRevision:UInt64,expectedBaseCanonicalRevision:UInt64,mutationID:MutationIDV1,postImage:FieldDraftMutationPayloadV1)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.expectedRevision=expectedRevision;self.expectedBaseCanonicalRevision=expectedBaseCanonicalRevision;self.mutationID=mutationID;self.postImage=postImage;try validate()}func validate()throws{try postImage.validate();guard schemaVersion==Self.schemaVersion,workspaceID==postImage.workspaceID,mutationID==postImage.mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan};switch postImage{case let .applyCommitTerminal(bundle,expectedSaga):guard expectedRevision>0,expectedRevision<UInt64.max,bundle.committedCheckpoint.draftRevision==expectedRevision+1,bundle.committedCheckpoint.baseCanonicalRevision==expectedBaseCanonicalRevision,expectedSaga>0 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .applyDiscardTerminal(bundle):guard expectedRevision>0,expectedRevision<UInt64.max,bundle.discardedCheckpoint.draftRevision==expectedRevision+1,bundle.discardedCheckpoint.baseCanonicalRevision==expectedBaseCanonicalRevision else{throw WorkspaceMutationContractFailureV1.invalidPlan};default:let predecessor=try postImage.predecessorIdentity;guard predecessor==nil ? expectedRevision==0&&postImage.revision==1:expectedRevision>0&&expectedRevision<UInt64.max&&postImage.revision==expectedRevision+1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}};if case let .reviseCheckpoint(value)=postImage{guard value.baseCanonicalRevision==expectedBaseCanonicalRevision else{throw WorkspaceMutationContractFailureV1.invalidPlan}}}var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{try postImage.affectedIdentities}}var affectedIdentity:WorkspaceEntityIdentityV1{get throws{let values=try affectedIdentities;guard values.count==1,let value=values.first else{throw WorkspaceMutationContractFailureV1.invalidPlan};return value}}var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch postImage{case let .applyCommitTerminal(bundle,_):guard let predecessor=bundle.retiredSaga.predecessorSagaID else{throw WorkspaceMutationContractFailureV1.invalidPlan};values=[try .init(kind:.draftCommitSaga,id:predecessor),try .init(kind:.fieldDraftCheckpoint,id:bundle.committedCheckpoint.draftID),try .init(kind:.draftCommitReceipt,id:bundle.receipt.receiptID)];case let .applyDiscardTerminal(bundle):values=[try .init(kind:.fieldDraftCheckpoint,id:bundle.discardedCheckpoint.draftID),try .init(kind:.draftDiscardReceipt,id:bundle.receipt.receiptID)];default:let affected=try affectedIdentities;guard affected.count==1,let identity=affected.first else{throw WorkspaceMutationContractFailureV1.invalidPlan};values=[try postImage.predecessorIdentity ?? identity]};return values.sorted{$0.stableKey<$1.stableKey}}}var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{let values=try concurrencyIdentities;guard values.count==1,let value=values.first else{throw WorkspaceMutationContractFailureV1.invalidPlan};return value}}func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{switch postImage{case let .applyCommitTerminal(_,expectedSaga):if identity.kind == .draftCommitSaga{return expectedSaga};if identity.kind == .fieldDraftCheckpoint{return expectedRevision};if identity.kind == .draftCommitReceipt{return 0};case .applyDiscardTerminal:if identity.kind == .fieldDraftCheckpoint{return expectedRevision};if identity.kind == .draftDiscardReceipt{return 0};default:return expectedRevision};throw WorkspaceMutationContractFailureV1.invalidPlan}func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}}

struct PackagePromotionMutationV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedPointerRevision:UInt64;let mutationID:MutationIDV1;let promotedRelease:PromotedPackageReleaseV1;let sandboxRun:PackageSandboxRunV1;let semanticDiff:PackageSemanticDiffV1;let predecessorPointer:ActivePackageRegistryPointerV1?;let resultingPointer:ActivePackageRegistryPointerV1;let actor:ActorSnapshotV1;let receipt:PackagePromotionReceiptV1;init(workspaceID:WorkspaceID,expectedPointerRevision:UInt64,mutationID:MutationIDV1,bundle:PackagePromotionAtomicBundleV1)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.expectedPointerRevision=expectedPointerRevision;self.mutationID=mutationID;promotedRelease=bundle.promotedRelease;sandboxRun=bundle.sandboxRun;semanticDiff=bundle.semanticDiff;predecessorPointer=bundle.predecessorPointer;resultingPointer=bundle.resultingPointer;actor=bundle.actor;receipt=bundle.receipt;try validate()}func validate()throws{let bundle=PackagePromotionAtomicBundleV1(promotedRelease:promotedRelease,sandboxRun:sandboxRun,semanticDiff:semanticDiff,predecessorPointer:predecessorPointer,resultingPointer:resultingPointer,actor:actor,receipt:receipt);try bundle.validate();guard schemaVersion==Self.schemaVersion,workspaceID==promotedRelease.workspaceID,workspaceID==sandboxRun.workspaceID,workspaceID==resultingPointer.workspaceID,workspaceID==receipt.workspaceID,mutationID==promotedRelease.mutationID,mutationID==sandboxRun.mutationID,mutationID==resultingPointer.mutationID,mutationID==receipt.mutationID,resultingPointer.promotionReceiptID==receipt.receiptID,(predecessorPointer == nil ? expectedPointerRevision==0&&resultingPointer.revision==1 : expectedPointerRevision>0&&expectedPointerRevision<UInt64.max&&predecessorPointer?.revision==expectedPointerRevision&&resultingPointer.revision==expectedPointerRevision+1)else{throw WorkspaceMutationContractFailureV1.invalidPlan}}var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{try[.init(kind:.promotedPackageRelease,id:promotedRelease.releaseRecordID),.init(kind:.packageSandboxRun,id:sandboxRun.runID),.init(kind:.packagePromotionReceipt,id:receipt.receiptID),.init(kind:.activePackageRegistryPointer,id:resultingPointer.pointerID)].sorted{$0.stableKey<$1.stableKey}}}var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{var values=try affectedIdentities;let pointer=try WorkspaceEntityIdentityV1(kind:.activePackageRegistryPointer,id:predecessorPointer?.pointerID ?? resultingPointer.pointerID);values.removeAll{$0.kind == .activePackageRegistryPointer};values.append(pointer);return values.sorted{$0.stableKey<$1.stableKey}}}func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{identity.kind == .activePackageRegistryPointer ? expectedPointerRevision:0}func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}}

enum MeasurementIntegrityMutationPayloadV1:Codable,Equatable,Sendable{
    case instrument(InstrumentReferenceV1),calibration(CalibrationStatusSnapshotV1),capture(MeasurementCaptureV1),series(MeasurementSeriesV1),quality(MeasurementQualityAssessmentV1)
    var workspaceID:WorkspaceID{switch self{case let .instrument(v):v.workspaceID;case let .calibration(v):v.workspaceID;case let .capture(v):v.workspaceID;case let .series(v):v.workspaceID;case let .quality(v):v.workspaceID}}
    var mutationID:MutationIDV1{switch self{case let .instrument(v):v.mutationID;case let .calibration(v):v.mutationID;case let .capture(v):v.mutationID;case let .series(v):v.mutationID;case let .quality(v):v.mutationID}}
    var revision:UInt64{switch self{case let .instrument(v):v.revision;case let .calibration(v):v.revision;case let .capture(v):v.revision;case let .series(v):v.revision;case let .quality(v):v.revision}}
    var identity:WorkspaceEntityIdentityV1{get throws{switch self{case let .instrument(v):try .init(kind:.instrumentReference,id:v.referenceID);case let .calibration(v):try .init(kind:.calibrationStatusSnapshot,id:v.snapshotID);case let .capture(v):try .init(kind:.measurementCapture,id:v.captureID);case let .series(v):try .init(kind:.measurementSeries,id:v.snapshotID);case let .quality(v):try .init(kind:.measurementQualityAssessment,id:v.assessmentID)}}}
    var predecessorIdentity:WorkspaceEntityIdentityV1?{get throws{switch self{case let .instrument(v):try v.supersedesReferenceID.map{try .init(kind:.instrumentReference,id:$0)};case let .calibration(v):try v.supersedesSnapshotID.map{try .init(kind:.calibrationStatusSnapshot,id:$0)};case let .capture(v):try v.supersedesCaptureID.map{try .init(kind:.measurementCapture,id:$0)};case let .series(v):try v.supersedesSnapshotID.map{try .init(kind:.measurementSeries,id:$0)};case let .quality(v):try v.supersedesAssessmentID.map{try .init(kind:.measurementQualityAssessment,id:$0)}}}
    var digest:String{switch self{case let .instrument(v):v.referenceSHA256;case let .calibration(v):v.snapshotSHA256;case let .capture(v):v.captureSHA256;case let .series(v):v.seriesSHA256;case let .quality(v):v.assessmentSHA256}}
    func validate()throws{switch self{case let .instrument(v):try v.validate();case let .calibration(v):try v.validate();case let .capture(v):try v.validate();case let .series(v):try v.validate();case let .quality(v):try v.validate()}}
}
extension MeasurementIntegrityAtomicBundleV1{var mutationPayloads:[MeasurementIntegrityMutationPayloadV1]{instruments.map(MeasurementIntegrityMutationPayloadV1.instrument)+calibrations.map(MeasurementIntegrityMutationPayloadV1.calibration)+captures.map(MeasurementIntegrityMutationPayloadV1.capture)+series.map(MeasurementIntegrityMutationPayloadV1.series)+assessments.map(MeasurementIntegrityMutationPayloadV1.quality)}}
struct MeasurementIntegrityMutationV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let bundle:MeasurementIntegrityAtomicBundleV1
    init(bundle:MeasurementIntegrityAtomicBundleV1)throws{schemaVersion=Self.schemaVersion;workspaceID=bundle.workspaceID;mutationID=bundle.mutationID;self.bundle=bundle;try validate()}
    func validate()throws{
        try bundle.validate()
        let payloads=bundle.mutationPayloads
        var affected=Set<String>();var concurrency=Set<String>()
        for payload in payloads{
            try payload.validate()
            let identity=try payload.identity
            let predecessor=try payload.predecessorIdentity
            guard affected.insert(identity.stableKey).inserted,
                  concurrency.insert((predecessor ?? identity).stableKey).inserted,
                  predecessor == nil ? payload.revision==1:payload.revision>1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}
        }
        guard schemaVersion==Self.schemaVersion,workspaceID==bundle.workspaceID,mutationID==bundle.mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    }
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{try bundle.mutationPayloads.map{try $0.identity}.sorted{$0.stableKey<$1.stableKey}}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{try bundle.mutationPayloads.map{try $0.predecessorIdentity ?? $0.identity}.sorted{$0.stableKey<$1.stableKey}}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{
        for payload in bundle.mutationPayloads{
            let predecessor=try payload.predecessorIdentity
            if (predecessor ?? (try payload.identity))==identity{return predecessor == nil ? 0:payload.revision-1}
        }
        throw WorkspaceMutationContractFailureV1.invalidPlan
    }
    func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}
}
enum PrivacyTransformMutationV1:Codable,Equatable,Sendable{
    case policy(PrivacyTransformPolicyV1)
    case publish(policy:PrivacyTransformPolicyV1,regions:[PrivacyRegionV1],manifest:PrivacyTransformManifestV1)
    case review(value:PrivacyReviewReceiptV1,manifest:PrivacyTransformManifestV1,policy:PrivacyTransformPolicyV1)
    var workspaceID:WorkspaceID{switch self{case let .policy(v):v.workspaceID;case let .publish(_,_,v):v.workspaceID;case let .review(v,_,_):v.workspaceID}}
    var mutationID:MutationIDV1{switch self{case let .policy(v):v.mutationID;case let .publish(_,_,v):v.mutationID;case let .review(v,_,_):v.mutationID}}
    func validate()throws{switch self{case let .policy(value):try value.validate();guard value.supersedesPolicyID != nil || value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .publish(policy,regions,manifest):try PrivacyTransformLifecycleClosureV1(policy:policy,regions:regions,manifest:manifest,review:nil).validate();guard (manifest.supersedesManifestID != nil || manifest.revision==1),regions==manifest.orderedRegions,regions.allSatisfy({$0.mutationID==mutationID})else{throw WorkspaceMutationContractFailureV1.invalidPlan};case let .review(value,manifest,policy):try value.validate(manifest:manifest,policy:policy);guard value.supersedesReceiptID != nil || value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}}}
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{switch self{case let .policy(v):return[try .init(kind:.privacyTransformPolicy,id:v.policyID)];case let .publish(_,regions,manifest):return try ([.init(kind:.privacyTransformManifest,id:manifest.manifestID)]+regions.map{try .init(kind:.privacyRegion,id:$0.regionID)}).sorted{$0.stableKey<$1.stableKey};case let .review(value,_,_):return[try .init(kind:.privacyReviewReceipt,id:value.receiptID)]}}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{switch self{case let .policy(v):return[try .init(kind:.privacyTransformPolicy,id:v.supersedesPolicyID ?? v.policyID)];case let .publish(_,regions,manifest):return try ([.init(kind:.privacyTransformManifest,id:manifest.supersedesManifestID ?? manifest.manifestID)]+regions.map{try .init(kind:.privacyRegion,id:$0.regionID)}).sorted{$0.stableKey<$1.stableKey};case let .review(value,_,_):return[try .init(kind:.privacyReviewReceipt,id:value.supersedesReceiptID ?? value.receiptID)]}}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{switch self{case let .policy(value):if identity.kind == .privacyTransformPolicy{return value.supersedesPolicyID==nil ? 0:value.revision-1};case let .publish(_,_,manifest):switch identity.kind{case .privacyRegion:return 0;case .privacyTransformManifest:return manifest.supersedesManifestID==nil ? 0:manifest.revision-1;default:break};case let .review(value,_,_):if identity.kind == .privacyReviewReceipt{return value.supersedesReceiptID==nil ? 0:value.revision-1}};throw WorkspaceMutationContractFailureV1.invalidPlan}
    func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}
}
enum ClientCapabilityMutationV1:Codable,Equatable,Sendable{
    case profile(ClientCapabilityProfileV1)
    case policy(value:PackageLifecyclePolicyV1,release:InspectionPackageReleaseV1)
    case disposition(value:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1)
    case admission(value:ClientCapabilityAdmissionDecisionV1,profile:ClientCapabilityProfileV1,policy:PackageLifecyclePolicyV1,disposition:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1)
    var workspaceID:WorkspaceID{switch self{case let .profile(v):v.workspaceID;case let .policy(v,_):v.workspaceID;case let .disposition(v,_):v.workspaceID;case let .admission(v,_,_,_,_):v.workspaceID}}
    var mutationID:MutationIDV1{switch self{case let .profile(v):v.mutationID;case let .policy(v,_):v.mutationID;case let .disposition(v,_):v.mutationID;case let .admission(v,_,_,_,_):v.mutationID}}
    func validate()throws{switch self{case let .profile(v):try v.validate();case let .policy(v,r):try v.validate(release:r);case let .disposition(v,r):try v.validate(release:r);case let .admission(v,p,policy,d,r):try ClientCapabilityLifecycleClosureV1(profile:p,policy:policy,disposition:d,decision:v,release:r).validate()}}
    var affectedIdentity:WorkspaceEntityIdentityV1{get throws{switch self{case let .profile(v):return try .init(kind:.clientCapabilityProfile,id:v.profileID);case let .policy(v,_):return try .init(kind:.packageLifecyclePolicy,id:v.policyID);case let .disposition(v,_):return try .init(kind:.packageLifecycleDisposition,id:v.dispositionID);case let .admission(v,_,_,_,_):return try .init(kind:.clientCapabilityAdmissionDecision,id:v.decisionID)}}}
    var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{switch self{case let .profile(v):return try .init(kind:.clientCapabilityProfile,id:v.supersedesProfileID ?? v.profileID);case let .policy(v,_):return try .init(kind:.packageLifecyclePolicy,id:v.supersedesPolicyID ?? v.policyID);case let .disposition(v,_):return try .init(kind:.packageLifecycleDisposition,id:v.supersedesDispositionID ?? v.dispositionID);case let .admission(v,_,_,_,_):return try .init(kind:.clientCapabilityAdmissionDecision,id:v.decisionID)}}}
    var revision:UInt64{switch self{case let .profile(v):v.revision;case let .policy(v,_):v.revision;case let .disposition(v,_):v.revision;case let .admission(v,_,_,_,_):v.revision}}
    var release:InspectionPackageReleaseV1?{switch self{case .profile:return nil;case let .policy(_,r),let .disposition(_,r),let .admission(_,_,_,_,r):return r}}
    var expectedRevision:UInt64{revision-1}
    func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}
}

enum FieldReferenceMutationV1:Codable,Equatable,Sendable{
    case importRelease(FieldReferenceReleaseV1)
    case bind(value:FieldReferenceBindingV1,release:FieldReferenceReleaseV1)
    var workspaceID:WorkspaceID{switch self{case let .importRelease(v):v.workspaceID;case let .bind(v,_):v.workspaceID}}
    var mutationID:MutationIDV1{switch self{case let .importRelease(v):v.mutationID;case let .bind(v,_):v.mutationID}}
    var revision:UInt64{switch self{case let .importRelease(v):v.revision;case let .bind(v,_):v.revision}}
    var expectedRevision:UInt64{revision-1}
    var affectedIdentity:WorkspaceEntityIdentityV1{get throws{switch self{case let .importRelease(v):return try .init(kind:.fieldReferenceRelease,id:v.releaseID);case let .bind(v,_):return try .init(kind:.fieldReferenceBinding,id:v.bindingID)}}}
    var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{switch self{case let .importRelease(v):return try .init(kind:.fieldReferenceRelease,id:v.supersedesReleaseID ?? v.releaseID);case let .bind(v,_):return try .init(kind:.fieldReferenceBinding,id:v.supersedesBindingID ?? v.bindingID)}}}
    func validate()throws{switch self{case let .importRelease(v):try v.validate();case let .bind(v,r):try v.validate(release:r)}}
    func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}
}

struct AccessibleDocumentMutationV1:Codable,Equatable,Sendable{let receipt:AccessibleDocumentAssessmentReceiptV1;var workspaceID:WorkspaceID{receipt.workspaceID};var mutationID:MutationIDV1{receipt.mutationID};var revision:UInt64{receipt.revision};var expectedRevision:UInt64{revision-1};var affectedIdentity:WorkspaceEntityIdentityV1{get throws{try .init(kind:.accessibleDocumentAssessmentReceipt,id:receipt.receiptID)}};var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{try .init(kind:.accessibleDocumentAssessmentReceipt,id:receipt.supersedesReceiptID ?? receipt.receiptID)}};func validate()throws{try receipt.validateIntrinsic()};func canonicalSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}}

enum SurveyDefinitionMutationPayloadV1: Codable, Equatable, Sendable {
    case apply(identity: SurveyDefinitionIdentityV1, release: SurveyDefinitionReleaseV1, event: SurveyDefinitionLifecycleEventV1)
}

struct SurveyDefinitionMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let identity: SurveyDefinitionIdentityV1
    let release: SurveyDefinitionReleaseV1
    let event: SurveyDefinitionLifecycleEventV1

    init(identity: SurveyDefinitionIdentityV1, release: SurveyDefinitionReleaseV1, event: SurveyDefinitionLifecycleEventV1) throws {
        schemaVersion = Self.schemaVersion
        self.identity = identity
        self.release = release
        self.event = event
        try validate()
    }

    var workspaceID: WorkspaceID { identity.workspaceID }
    var mutationID: MutationIDV1 { identity.mutationID }
    var revision: UInt64 { identity.revision }
    var expectedRevision: UInt64 { revision - 1 }
    var appendsRelease: Bool { event.action != .publish && event.action != .retire }
    var payload: SurveyDefinitionMutationPayloadV1 { .apply(identity: identity, release: release, event: event) }
    var affectedIdentities: [WorkspaceEntityIdentityV1] { get throws { var values=[try WorkspaceEntityIdentityV1(kind:.surveyDefinitionIdentity,id:identity.definitionID)];if appendsRelease{values.append(try .init(kind:.surveyDefinitionRelease,id:release.releaseID))};return values.sorted{$0.stableKey<$1.stableKey} } }
    var concurrencyIdentities: [WorkspaceEntityIdentityV1] { get throws { var values=[try WorkspaceEntityIdentityV1(kind:.surveyDefinitionIdentity,id:identity.definitionID)];if appendsRelease{values.append(try .init(kind:.surveyDefinitionRelease,id:release.supersedesReleaseID ?? release.releaseID))};return values.sorted{$0.stableKey<$1.stableKey} } }
    func expectedRevision(for concurrencyIdentity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        switch concurrencyIdentity.kind {
        case .surveyDefinitionIdentity: return expectedRevision
        case .surveyDefinitionRelease where appendsRelease: return release.revision - 1
        default: throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    func validate() throws {
        try identity.validate(currentRelease: release, event: event)
        guard schemaVersion == Self.schemaVersion,
              identity.workspaceID == release.workspaceID,
              identity.mutationID == event.mutationID,
              identity.revision == event.revision,
              revision > 0,
              !appendsRelease || identity.mutationID == release.mutationID else { throw WorkspaceMutationContractFailureV1.invalidPlan }
    }

    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }

}

enum SurveySessionMutationPayloadV1: Codable, Equatable, Sendable {
    case applySession(SurveySessionV1, definition: SurveyDefinitionReleaseV1, publication: SurveyPublicationSnapshotV1?)
    case captureFact(FactCaptureV1, session: SurveySessionV1, definition: SurveyDefinitionReleaseV1, predecessors: [FactCaptureV1])
    case applyProvisionalSubject(ProvisionalSubjectV1)
    case promoteSubject(ProvisionalSubjectV1, receipt: SubjectPromotionReceiptV1, preview: SubjectPromotionPreviewV1, predecessor: SubjectPromotionReceiptV1?)
    case publish(SurveySessionV1, snapshot: SurveyPublicationSnapshotV1, definition: SurveyDefinitionReleaseV1, captures: [FactCaptureV1])
}

struct SurveySessionMutationV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let mutationID: MutationIDV1; let payload: SurveySessionMutationPayloadV1
    init(workspaceID:WorkspaceID,mutationID:MutationIDV1,payload:SurveySessionMutationPayloadV1)throws{self.workspaceID=workspaceID;self.mutationID=mutationID;self.payload=payload;try validate()}
    func validate()throws{switch payload{
    case let .applySession(v,d,p):try v.validate(definition:d);guard v.workspaceID==workspaceID,v.mutationID==mutationID,p==nil,v.transition != .complete else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .captureFact(v,s,d,prior):if prior.isEmpty{try v.validate(session:s,definition:d)}else{try v.validateSuccessor(of:prior,session:s,definition:d)};guard v.workspaceID==workspaceID,v.mutationID==mutationID,s.state == .draft || s.state == .amended else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .applyProvisionalSubject(v):try v.validate();guard v.workspaceID==workspaceID,v.mutationID==mutationID,(v.revision == 1 ? v.state == .active : (v.state == .active || v.state == .archived)) else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .promoteSubject(v,r,p,old):try v.validate();try r.validate(preview:p,predecessor:old);guard v.workspaceID==workspaceID,r.workspaceID==workspaceID,v.mutationID==mutationID,r.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .publish(s,p,d,c):try p.validate(session:s,definition:d,captures:c);guard s.workspaceID==workspaceID,p.workspaceID==workspaceID,s.mutationID==mutationID,p.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    }
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{switch payload{
    case let .applySession(v,_,_):return[try .init(kind:.surveySession,id:v.sessionID)]
    case let .captureFact(v,_,_,_):return[try .init(kind:.factCapture,id:v.captureID)]
    case let .applyProvisionalSubject(v):return[try .init(kind:.provisionalSubject,id:v.provisionalSubjectID)]
    case let .promoteSubject(v,r,_,_):return try [.init(kind:.provisionalSubject,id:v.provisionalSubjectID),.init(kind:.subjectPromotionReceipt,id:r.receiptID)].sorted{$0.stableKey<$1.stableKey}
    case let .publish(s,p,_,_):return try [.init(kind:.surveySession,id:s.sessionID),.init(kind:.surveyPublicationSnapshot,id:p.snapshotID)].sorted{$0.stableKey<$1.stableKey}}}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{switch payload{
    case let .applySession(v,_,_):return[try .init(kind:.surveySession,id:v.sessionID)]
    case let .captureFact(v,s,_,prior):var values:[WorkspaceEntityIdentityV1];if prior.isEmpty{values=[try .init(kind:.factCapture,id:v.captureID)]}else{values=try prior.map{try .init(kind:.factCapture,id:$0.captureID)}};values.append(try .init(kind:.surveySession,id:s.sessionID));guard Set(values).count==values.count else{throw WorkspaceMutationContractFailureV1.invalidPlan};return values.sorted{$0.stableKey<$1.stableKey}
    case let .applyProvisionalSubject(v):return[try .init(kind:.provisionalSubject,id:v.provisionalSubjectID)]
    case let .promoteSubject(v,r,_,old):return try [.init(kind:.provisionalSubject,id:v.provisionalSubjectID),.init(kind:.subjectPromotionReceipt,id:old?.receiptID ?? r.receiptID)].sorted{$0.stableKey<$1.stableKey}
    case let .publish(s,p,_,_):return try [.init(kind:.surveySession,id:s.sessionID),.init(kind:.surveyPublicationSnapshot,id:p.supersedesSnapshotID ?? p.snapshotID)].sorted{$0.stableKey<$1.stableKey}}}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{switch payload{
    case let .applySession(v,_,_):return v.revision-1
    case let .captureFact(v,s,_,prior):if identity.kind == .surveySession,identity.id == s.sessionID{return s.revision};if prior.isEmpty,identity.kind == .factCapture,identity.id == v.captureID{return v.revision-1};guard identity.kind == .factCapture,let predecessor=prior.first(where:{$0.captureID==identity.id})else{throw WorkspaceMutationContractFailureV1.invalidPlan};return predecessor.revision
    case let .applyProvisionalSubject(v):return v.revision-1
    case let .promoteSubject(v,r,_,old):if identity.kind == .provisionalSubject{return v.revision-1};if identity.kind == .subjectPromotionReceipt{return old?.revision ?? 0}
    case let .publish(s,p,_,_):if identity.kind == .surveySession{return s.revision-1};if identity.kind == .surveyPublicationSnapshot{return p.revision-1}}
    throw WorkspaceMutationContractFailureV1.invalidPlan}
}

enum AssetLocatorMutationPayloadV1:Codable,Equatable,Sendable{
    case bind(AssetLocatorV1,receipt:LocatorBindingReceiptV1,predecessorReceipt:LocatorBindingReceiptV1?)
    case transition(AssetLocatorV1,receipt:LocatorBindingReceiptV1,predecessorLocator:AssetLocatorV1,predecessorReceipt:LocatorBindingReceiptV1?)
    case replace(AssetLocatorV1,replacement:AssetLocatorV1,receipt:LocatorBindingReceiptV1,predecessorLocator:AssetLocatorV1,predecessorReceipt:LocatorBindingReceiptV1?)
}
struct AssetLocatorMutationV1:Codable,Equatable,Sendable{
    let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let payload:AssetLocatorMutationPayloadV1
    init(workspaceID:WorkspaceID,mutationID:MutationIDV1,payload:AssetLocatorMutationPayloadV1)throws{self.workspaceID=workspaceID;self.mutationID=mutationID;self.payload=payload;try validate()}
    func validate()throws{switch payload{
    case let .bind(value,receipt,predecessorReceipt):let preview=try receipt.reconstructedPreview;try value.validate();try preview.validate(before:nil,after:value,replacement:nil);try receipt.validate(preview:preview,predecessor:predecessorReceipt);try Self.validateManualShortCodeNamespace(target:value,receipt:receipt);guard predecessorReceipt == nil,value.workspaceID==workspaceID,value.mutationID==mutationID,value.state == .active,value.revision==1,receipt.workspaceID==workspaceID,receipt.mutationID==mutationID,receipt.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .transition(value,receipt,prior,predecessorReceipt):let preview=try receipt.reconstructedPreview;try value.validateSuccessor(of:prior);try preview.validate(before:prior,after:value,replacement:nil);try receipt.validate(preview:preview,predecessor:predecessorReceipt);let expectedState:AssetLocatorStateV1;switch preview.action{case .rebind:try Self.validateManualShortCodeNamespace(target:value,receipt:receipt);expectedState = .active;case .rotateSigningKey:expectedState = .active;case .retire:expectedState = .retired;case .revoke:expectedState = .revoked;case .bind,.replace:throw WorkspaceMutationContractFailureV1.invalidPlan};guard value.workspaceID==workspaceID,value.mutationID==mutationID,value.state==expectedState,receipt.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .replace(value,replacement,receipt,prior,predecessorReceipt):let preview=try receipt.reconstructedPreview;try value.validateSuccessor(of:prior);try replacement.validate();try preview.validate(before:prior,after:value,replacement:replacement);try receipt.validate(preview:preview,predecessor:predecessorReceipt);try Self.validateManualShortCodeNamespace(target:replacement,receipt:receipt);guard value.workspaceID==workspaceID,replacement.workspaceID==workspaceID,value.mutationID==mutationID,replacement.mutationID==mutationID,value.state == .replaced,value.replacedByLocatorID==replacement.locatorID,replacement.locatorID != value.locatorID,replacement.state == .active,replacement.revision==1,receipt.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    }
    private static func validateManualShortCodeNamespace(target:AssetLocatorV1,receipt:LocatorBindingReceiptV1)throws{
        let reserved:Bool
        if case .externalKey(let key)=target.representation { reserved=key.namespaceID==ManualShortCodeV1.externalKeyNamespace } else { reserved=false }
        if reserved {
            guard let code=receipt.manualShortCodeIssuance,
                  target.representation == .externalKey(try code.externalKey()) else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
        } else if receipt.manualShortCodeIssuance != nil {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch payload{case let .bind(value,receipt,_),let .transition(value,receipt,_,_):values=[try .init(kind:.assetLocator,id:value.locatorID),try .init(kind:.locatorBindingReceipt,id:receipt.receiptID)];case let .replace(value,replacement,receipt,_,_):values=[try .init(kind:.assetLocator,id:value.locatorID),try .init(kind:.assetLocator,id:replacement.locatorID),try .init(kind:.locatorBindingReceipt,id:receipt.receiptID)]};return values.sorted{$0.stableKey<$1.stableKey}}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch payload{case let .bind(value,receipt,predecessorReceipt):values=[try .init(kind:.assetLocator,id:value.locatorID),try .init(kind:.locatorBindingReceipt,id:predecessorReceipt?.receiptID ?? receipt.receiptID)];case let .transition(_,receipt,prior,predecessorReceipt):values=[try .init(kind:.assetLocator,id:prior.locatorID),try .init(kind:.locatorBindingReceipt,id:predecessorReceipt?.receiptID ?? receipt.receiptID)];case let .replace(_,replacement,receipt,prior,predecessorReceipt):values=[try .init(kind:.assetLocator,id:prior.locatorID),try .init(kind:.assetLocator,id:replacement.locatorID),try .init(kind:.locatorBindingReceipt,id:predecessorReceipt?.receiptID ?? receipt.receiptID)]};return values.sorted{$0.stableKey<$1.stableKey}}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{switch payload{case let .bind(value,_,predecessorReceipt):if identity.kind == .assetLocator&&identity.id==value.locatorID{return 0};if identity.kind == .locatorBindingReceipt{return predecessorReceipt?.revision ?? 0};case let .transition(_,_,prior,predecessorReceipt):if identity.kind == .assetLocator&&identity.id==prior.locatorID{return prior.revision};if identity.kind == .locatorBindingReceipt{return predecessorReceipt?.revision ?? 0};case let .replace(_,replacement,_,prior,predecessorReceipt):if identity.kind == .assetLocator&&identity.id==prior.locatorID{return prior.revision};if identity.kind == .assetLocator&&identity.id==replacement.locatorID{return 0};if identity.kind == .locatorBindingReceipt{return predecessorReceipt?.revision ?? 0}};throw WorkspaceMutationContractFailureV1.invalidPlan}
}

enum ScheduleMutationPayloadV1:Codable,Equatable,Sendable{
    case appendRelease(ScheduleDefinitionReleaseV1,predecessor:ScheduleDefinitionReleaseV1?)
    case appendExceptionCalendarRelease(ExceptionCalendarReleaseV1,predecessor:ExceptionCalendarReleaseV1?)
    /// `ScheduleOverrideEventV1.expectedOverrideFrontierSHA256` fences the
    /// exact active stream used to prepare this append at the sole writer.
    case appendOverrideEvent(ScheduleOverrideEventV1,predecessor:ScheduleOverrideEventV1?,release:ScheduleDefinitionReleaseV1)
    case appendOccurrenceEvent(OccurrenceHistoryEventV1,predecessor:OccurrenceHistoryEventV1?,release:ScheduleDefinitionReleaseV1)
    case startOccurrence(OccurrenceHistoryEventV1,predecessor:OccurrenceHistoryEventV1,release:ScheduleDefinitionReleaseV1)
    case generateOccurrences(release:ScheduleDefinitionReleaseV1,plan:OccurrenceGenerationPlanV1,events:[OccurrenceHistoryEventV1])
}
struct ScheduleMutationV1:Codable,Equatable,Sendable{
    let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let payload:ScheduleMutationPayloadV1
    init(workspaceID:WorkspaceID,mutationID:MutationIDV1,payload:ScheduleMutationPayloadV1)throws{self.workspaceID=workspaceID;self.mutationID=mutationID;self.payload=payload;try validate()}
    func validate()throws{switch payload{
    case let .appendRelease(value,predecessor):try value.validate();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,value.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .appendExceptionCalendarRelease(value,predecessor):try value.validate();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,value.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .appendOverrideEvent(value,predecessor,release):try value.validate();try release.validate();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,value.mutationID==mutationID,release.workspaceID==workspaceID,value.scheduleRelease == (try ScheduleDefinitionReleaseReferenceV1(release)) else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .appendOccurrenceEvent(value,predecessor,release):try release.validate();try value.validate(predecessor:predecessor);guard release.workspaceID==workspaceID,value.workspaceID==workspaceID,value.mutationID==mutationID,value.action != .start,value.scheduleRelease==(try ScheduleDefinitionReleaseReferenceV1(release)) else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .startOccurrence(value,predecessor,release):try release.validate();try value.validate(predecessor:predecessor);guard release.workspaceID==workspaceID,value.workspaceID==workspaceID,value.mutationID==mutationID,value.action == .start,value.workInstance != nil,value.scheduleRelease==(try ScheduleDefinitionReleaseReferenceV1(release)) else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .generateOccurrences(release,plan,events):try release.validate();try plan.validate(definition:release);try events.forEach{$0.validate(predecessor:nil)};var candidates:[OccurrenceIDV1:OccurrenceGenerationCandidateV1]=[:];for candidate in plan.candidates{guard candidates.updateValue(candidate,forKey:candidate.occurrenceID)==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard release.workspaceID==workspaceID,plan.workspaceID==workspaceID,events.count==plan.candidates.count,events.count<=release.maximumGeneratedOccurrences,Set(events.map(\.eventID)).count==events.count,Set(events.map(\.occurrenceID)).count==events.count,events.allSatisfy({event in guard let candidate=candidates[event.occurrenceID] else{return false};return event.workspaceID==workspaceID&&event.mutationID==mutationID&&event.action == .generated&&event.scheduleRelease==plan.scheduleRelease&&event.nominalBasis==candidate.nominalBasis&&event.effectiveBasis==candidate.effectiveBasis&&event.identityPredecessorOccurrenceID==candidate.predecessorOccurrenceID&&event.identityCompletionEventSHA256==candidate.completionEventSHA256}) else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    }
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch payload{case let .appendRelease(value,_):values=[try .init(kind:.scheduleDefinitionRelease,id:value.releaseID)];case let .appendExceptionCalendarRelease(value,_):values=[try .init(kind:.exceptionCalendarRelease,id:value.releaseID)];case let .appendOverrideEvent(value,_,_):values=[try .init(kind:.scheduleOverrideEvent,id:value.eventID)];case let .appendOccurrenceEvent(value,_,_),let .startOccurrence(value,_,_):values=[try .init(kind:.occurrenceHistoryEvent,id:value.eventID)];case let .generateOccurrences(_,_,events):values=try events.map{try .init(kind:.occurrenceHistoryEvent,id:$0.eventID)}};let ordered=values.sorted{$0.stableKey<$1.stableKey};guard ordered.count<=MutationReceiptV1.maximumPostImageCount,Set(ordered).count==ordered.count else{throw WorkspaceMutationContractFailureV1.invalidPlan};return ordered}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{switch payload{case let .appendRelease(value,predecessor):return [try .init(kind:.scheduleDefinitionRelease,id:predecessor?.releaseID ?? value.releaseID)];case let .appendExceptionCalendarRelease(value,predecessor):return [try .init(kind:.exceptionCalendarRelease,id:predecessor?.releaseID ?? value.releaseID)];case let .appendOverrideEvent(value,predecessor,_):return [try .init(kind:.scheduleOverrideEvent,id:predecessor?.eventID ?? value.eventID)];case let .appendOccurrenceEvent(value,predecessor,_):return [try .init(kind:.occurrenceHistoryEvent,id:predecessor?.eventID ?? value.eventID)];case let .startOccurrence(_,predecessor,_):return [try .init(kind:.occurrenceHistoryEvent,id:predecessor.eventID)];case let .generateOccurrences(_,_,events):return try events.map{try .init(kind:.occurrenceHistoryEvent,id:$0.eventID)}.sorted{$0.stableKey<$1.stableKey}}}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{switch payload{case let .appendRelease(value,predecessor):guard identity.kind == .scheduleDefinitionRelease,identity.id==(predecessor?.releaseID ?? value.releaseID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return predecessor?.revision ?? 0;case let .appendExceptionCalendarRelease(value,predecessor):guard identity.kind == .exceptionCalendarRelease,identity.id==(predecessor?.releaseID ?? value.releaseID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return predecessor?.revision ?? 0;case let .appendOverrideEvent(value,predecessor,_):guard identity.kind == .scheduleOverrideEvent,identity.id==(predecessor?.eventID ?? value.eventID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return predecessor?.revision ?? 0;case let .appendOccurrenceEvent(value,predecessor,_):guard identity.kind == .occurrenceHistoryEvent,identity.id==(predecessor?.eventID ?? value.eventID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return predecessor?.revision ?? 0;case let .startOccurrence(_,predecessor,_):guard identity.kind == .occurrenceHistoryEvent,identity.id==predecessor.eventID else{throw WorkspaceMutationContractFailureV1.invalidPlan};return predecessor.revision;case let .generateOccurrences(_,_,events):guard identity.kind == .occurrenceHistoryEvent,events.contains(where:{$0.eventID==identity.id})else{throw WorkspaceMutationContractFailureV1.invalidPlan};return 0}}
}

enum PlanMutationPayloadV1:Codable,Equatable,Sendable{
    case appendDocument(PlanDocumentV1,predecessor:PlanDocumentV1?)
    case appendRevision(PlanRevisionV1,predecessor:PlanRevisionV1?,document:PlanDocumentV1)
    case appendPlacement(PlanPlacementV1,predecessor:PlanPlacementV1?,planRevision:PlanRevisionV1)
    case applyRebase(newRevision:PlanRevisionV1,predecessorRevision:PlanRevisionV1,placements:[PlanPlacementV1],predecessorPlacements:[PlanPlacementV1],receipt:RebaseReceiptV1,predecessorReceipt:RebaseReceiptV1?,poseEffects:PlacementPoseMutationV1?)
    case recordRebaseRejection(receipt:RebaseReceiptV1,predecessorReceipt:RebaseReceiptV1?)
}
extension PlanMutationPayloadV1{var newRevisionForReference:PlanRevisionReferenceV1?{get throws{if case let .applyRebase(value,_,_,_,_,_,_)=self{return try value.reference};return nil}}}
struct PlanMutationV1:Codable,Equatable,Sendable{
    let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let payload:PlanMutationPayloadV1
    init(workspaceID:WorkspaceID,mutationID:MutationIDV1,payload:PlanMutationPayloadV1)throws{self.workspaceID=workspaceID;self.mutationID=mutationID;self.payload=payload;try validate()}
    func validate()throws{switch payload{
    case let .appendDocument(value,predecessor):try value.validateIntrinsic();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,value.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .appendRevision(value,predecessor,document):try value.validateIntrinsic();try document.validateIntrinsic();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,document.workspaceID==workspaceID,value.planDocument==(try document.reference),value.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .appendPlacement(value,predecessor,planRevision):try value.validateIntrinsic();try planRevision.validateIntrinsic();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,planRevision.workspaceID==workspaceID,value.planRevision==(try planRevision.reference),value.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}
    case let .applyRebase(newRevision,priorRevision,placements,priors,receipt,predecessorReceipt,poseEffects):try newRevision.validateSuccessor(of:priorRevision);try receipt.validateIntrinsic();guard newRevision.workspaceID==workspaceID,newRevision.mutationID==mutationID,receipt.workspaceID==workspaceID,receipt.mutationID==mutationID,receipt.decision == .approved,receipt.resultingRevision==(try newRevision.reference),placements.count==priors.count,placements.count<=PlanLimitsV1.maximumPlacements,Set(placements.map(\.placementID)).count==placements.count,Set(priors.map(\.placementID))==Set(placements.map(\.placementID)),receipt.canonicalPlanMutationSHA256 != nil else{throw WorkspaceMutationContractFailureV1.invalidPlan};let old=Dictionary(uniqueKeysWithValues:priors.map{($0.placementID,$0)});for value in placements{guard let predecessor=old[value.placementID] else{throw WorkspaceMutationContractFailureV1.invalidPlan};try value.validateSuccessor(of:predecessor);guard value.workspaceID==workspaceID,value.mutationID==mutationID,value.planRevision==(try newRevision.reference)else{throw WorkspaceMutationContractFailureV1.invalidPlan}};if let poseEffects{try poseEffects.validate();guard poseEffects.workspaceID==workspaceID,poseEffects.mutationID==mutationID,poseEffects.observations.isEmpty,poseEffects.events.allSatisfy({$0.source == .planRebase})else{throw WorkspaceMutationContractFailureV1.invalidPlan}};if let predecessorReceipt{guard predecessorReceipt.revision<UInt64.max,receipt.revision==predecessorReceipt.revision+1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}}else{guard receipt.revision==1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    case let .recordRebaseRejection(receipt,predecessorReceipt):try receipt.validateIntrinsic();guard receipt.workspaceID==workspaceID,receipt.mutationID==mutationID,receipt.decision == .rejected else{throw WorkspaceMutationContractFailureV1.invalidPlan};if let predecessorReceipt{try predecessorReceipt.validateIntrinsic();guard predecessorReceipt.revision<UInt64.max,receipt.receiptID != predecessorReceipt.receiptID,receipt.workspaceID==predecessorReceipt.workspaceID,receipt.revision==predecessorReceipt.revision+1,receipt.supersedesReceiptSHA256==predecessorReceipt.receiptSHA256,receipt.mutationID != predecessorReceipt.mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}}else{guard receipt.revision==1,receipt.supersedesReceiptSHA256==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    }}
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch payload{case let .appendDocument(v,_):values=[try .init(kind:.planDocument,id:v.planDocumentID)];case let .appendRevision(v,_,_):values=[try .init(kind:.planRevision,id:v.planRevisionID)];case let .appendPlacement(v,_,_):values=[try .init(kind:.planPlacement,id:v.placementID)];case let .applyRebase(v,_,p,_,r,_,poseEffects):values=[try .init(kind:.planRevision,id:v.planRevisionID)]+(try p.map{try .init(kind:.planPlacement,id:$0.placementID)})+[try .init(kind:.planRebaseReceipt,id:r.receiptID)]+(try poseEffects?.affectedIdentities ?? []);case let .recordRebaseRejection(r,_):values=[try .init(kind:.planRebaseReceipt,id:r.receiptID)]};let result=values.sorted{$0.stableKey<$1.stableKey};guard result.count<=MutationReceiptV1.maximumPostImageCount,Set(result).count==result.count else{throw WorkspaceMutationContractFailureV1.invalidPlan};return result}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch payload{case let .appendDocument(v,p):values=[try .init(kind:.planDocument,id:p?.planDocumentID ?? v.planDocumentID)];case let .appendRevision(v,p,_):values=[try .init(kind:.planRevision,id:p?.planRevisionID ?? v.planRevisionID)];case let .appendPlacement(v,p,_):values=[try .init(kind:.planPlacement,id:p?.placementID ?? v.placementID)];case let .applyRebase(v,p,p2,p1,r,pr,poseEffects):values=[try .init(kind:.planRevision,id:p.planRevisionID)]+(try p1.map{try .init(kind:.planPlacement,id:$0.placementID)})+[try .init(kind:.planRebaseReceipt,id:pr?.receiptID ?? r.receiptID)]+(try poseEffects?.concurrencyIdentities ?? []);_ = v;_ = p2;case let .recordRebaseRejection(r,pr):values=[try .init(kind:.planRebaseReceipt,id:pr?.receiptID ?? r.receiptID)]};let ordered=values.sorted{$0.stableKey<$1.stableKey};guard Set(ordered).count==ordered.count else{throw WorkspaceMutationContractFailureV1.invalidPlan};return ordered}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{switch payload{case let .appendDocument(v,p):guard identity.kind == .planDocument,identity.id==(p?.planDocumentID ?? v.planDocumentID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return p?.revision ?? 0;case let .appendRevision(v,p,_):guard identity.kind == .planRevision,identity.id==(p?.planRevisionID ?? v.planRevisionID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return p?.revision ?? 0;case let .appendPlacement(v,p,_):guard identity.kind == .planPlacement,identity.id==(p?.placementID ?? v.placementID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return p?.revision ?? 0;case let .applyRebase(_,prior,_,priors,receipt,priorReceipt,poseEffects):if identity.kind == .planRevision&&identity.id==prior.planRevisionID{return prior.revision};if identity.kind == .planPlacement,let value=priors.first(where:{$0.placementID==identity.id}){return value.revision};if identity.kind == .planRebaseReceipt&&identity.id==(priorReceipt?.receiptID ?? receipt.receiptID){return priorReceipt?.revision ?? 0};if let poseEffects{return try poseEffects.expectedRevision(for:identity)};throw WorkspaceMutationContractFailureV1.invalidPlan;case let .recordRebaseRejection(receipt,prior):guard identity.kind == .planRebaseReceipt,identity.id==(prior?.receiptID ?? receipt.receiptID)else{throw WorkspaceMutationContractFailureV1.invalidPlan};return prior?.revision ?? 0}}
}

struct PlacementPoseMutationV1:Codable,Equatable,Sendable{
    let workspaceID:WorkspaceID;let mutationID:MutationIDV1
    let events:[AssetPoseEventV1];let eventPredecessors:[AssetPoseEventV1?]
    let observations:[SpatialAnchorObservationV1];let observationPredecessors:[SpatialAnchorObservationV1?]
    let admissionClosure:PlacementPoseAdmissionClosureV1
    init(workspaceID:WorkspaceID,mutationID:MutationIDV1,events:[AssetPoseEventV1],eventPredecessors:[AssetPoseEventV1?],observations:[SpatialAnchorObservationV1]=[],observationPredecessors:[SpatialAnchorObservationV1?]=[],admissionClosure:PlacementPoseAdmissionClosureV1)throws{self.workspaceID=workspaceID;self.mutationID=mutationID;self.events=events;self.eventPredecessors=eventPredecessors;self.observations=observations;self.observationPredecessors=observationPredecessors;self.admissionClosure=admissionClosure;try validate()}
    func validate()throws{guard !events.isEmpty||!observations.isEmpty,events.count==eventPredecessors.count,observations.count==observationPredecessors.count,events.count+observations.count<=MutationReceiptV1.maximumPostImageCount,Set(events.map(\.eventID)).count==events.count,Set(observations.map(\.observationID)).count==observations.count,admissionClosure.workspaceID==workspaceID else{throw WorkspaceMutationContractFailureV1.invalidPlan};try admissionClosure.validate(events:events,observations:observations);for (value,predecessor) in zip(events,eventPredecessors){try value.validateIntrinsic();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1,value.predecessor==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,value.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}};for (value,predecessor) in zip(observations,observationPredecessors){try value.validateIntrinsic();if let predecessor{try value.validateSuccessor(of:predecessor)}else{guard value.revision==1,value.predecessorObservationID==nil,value.predecessorSHA256==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard value.workspaceID==workspaceID,value.mutationID==mutationID else{throw WorkspaceMutationContractFailureV1.invalidPlan}}}
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{let values=(try events.map{try WorkspaceEntityIdentityV1(kind:.assetPoseEvent,id:$0.eventID)})+(try observations.map{try WorkspaceEntityIdentityV1(kind:.spatialAnchorObservation,id:$0.observationID)});return values.sorted{$0.stableKey<$1.stableKey}}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{var values:[WorkspaceEntityIdentityV1]=[];for (value,predecessor) in zip(events,eventPredecessors){values.append(try .init(kind:.assetPoseEvent,id:predecessor?.eventID ?? value.eventID))};for (value,predecessor) in zip(observations,observationPredecessors){values.append(try .init(kind:.spatialAnchorObservation,id:predecessor?.observationID ?? value.observationID))};let ordered=values.sorted{$0.stableKey<$1.stableKey};guard Set(ordered).count==ordered.count else{throw WorkspaceMutationContractFailureV1.invalidPlan};return ordered}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{if identity.kind == .assetPoseEvent,let index=events.indices.first(where:{(eventPredecessors[$0]?.eventID ?? events[$0].eventID)==identity.id}){return eventPredecessors[index]?.revision ?? 0};if identity.kind == .spatialAnchorObservation,let index=observations.indices.first(where:{(observationPredecessors[$0]?.observationID ?? observations[$0].observationID)==identity.id}){return observationPredecessors[index]?.revision ?? 0};throw WorkspaceMutationContractFailureV1.invalidPlan}}
}

extension EvidenceContextWriteOperationV1{
    var affectedIdentity:WorkspaceEntityIdentityV1{get throws{switch self{case let .appendContext(value,_):return try .init(kind:.evidenceContext,id:value.contextID);case let .appendPair(value,_):return try .init(kind:.pairedObservationLink,id:value.linkID)}}}
    var concurrencyIdentity:WorkspaceEntityIdentityV1{get throws{switch self{case let .appendContext(value,predecessor):return try .init(kind:.evidenceContext,id:predecessor?.contextID ?? value.contextID);case let .appendPair(value,predecessor):return try .init(kind:.pairedObservationLink,id:predecessor?.linkID ?? value.linkID)}}}
    var revision:UInt64{switch self{case .appendContext(let value,_):return value.revision;case .appendPair(let value,_):return value.revision}}
    var semanticSHA256:String{switch self{case .appendContext(let value,_):return value.contextSHA256;case .appendPair(let value,_):return value.linkSHA256}}
    var expectedRevision:UInt64{switch self{case .appendContext(_,let predecessor):return predecessor?.revision ?? 0;case .appendPair(_,let predecessor):return predecessor?.revision ?? 0}}
}

extension LightingWriteOperationV1 {
    var affectedIdentity: WorkspaceEntityIdentityV1 { get throws { switch self {
    case let .appendSystem(v,_,_): return try .init(kind:.lightingSystem,id:v.recordID)
    case let .appendObservation(v,_,_): return try .init(kind:.lightingObservation,id:v.recordID)
    case let .appendIssue(v,_,_): return try .init(kind:.lightingIssue,id:v.recordID)
    case let .appendMeasurementPlan(v,_,_): return try .init(kind:.lightingMeasurementPlan,id:v.recordID)
    case let .appendClaim(v,_,_): return try .init(kind:.lightingClaimState,id:v.recordID) } } }
    var concurrencyIdentity: WorkspaceEntityIdentityV1 { get throws { switch self {
    case let .appendSystem(v,p,_): return try .init(kind:.lightingSystem,id:p?.recordID ?? v.recordID)
    case let .appendObservation(v,p,_): return try .init(kind:.lightingObservation,id:p?.recordID ?? v.recordID)
    case let .appendIssue(v,p,_): return try .init(kind:.lightingIssue,id:p?.recordID ?? v.recordID)
    case let .appendMeasurementPlan(v,p,_): return try .init(kind:.lightingMeasurementPlan,id:p?.recordID ?? v.recordID)
    case let .appendClaim(v,p,_): return try .init(kind:.lightingClaimState,id:p?.recordID ?? v.recordID) } } }
    var expectedRevision: UInt64 { switch self { case .appendSystem(_,let p,_):p?.revision ?? 0;case .appendObservation(_,let p,_):p?.revision ?? 0;case .appendIssue(_,let p,_):p?.revision ?? 0;case .appendMeasurementPlan(_,let p,_):p?.revision ?? 0;case .appendClaim(_,let p,_):p?.revision ?? 0 } }
    var revision: UInt64 { switch self { case .appendSystem(let v,_,_):v.revision;case .appendObservation(let v,_,_):v.revision;case .appendIssue(let v,_,_):v.revision;case .appendMeasurementPlan(let v,_,_):v.revision;case .appendClaim(let v,_,_):v.revision } }
}

enum TemporalEvidenceMutationPayloadV1: Codable, Equatable, Sendable {
    case acceptClip(TemporalEvidenceClipV1, review:TemporalEvidenceCaptureReviewV1, predecessor: TemporalEvidenceClipV1?)
    case appendAnchor(TimecodedEvidenceAnchorV1, clip: TemporalEvidenceClipV1, predecessor: TimecodedEvidenceAnchorV1?)
    case registerDerivative(TemporalEvidenceClipV1, derivative:TemporalEvidenceDerivativeV1, predecessorClip:TemporalEvidenceClipV1, predecessorDerivative:TemporalEvidenceDerivativeV1?)
    case applyRetention(TemporalEvidenceClipV1, event:TemporalEvidenceRetentionEventV1, predecessorClip:TemporalEvidenceClipV1, predecessorEvent:TemporalEvidenceRetentionEventV1?)
    case removeClip(event:TemporalEvidenceRetentionEventV1, clips:[TemporalEvidenceClipV1], anchors:[TimecodedEvidenceAnchorV1], derivatives:[TemporalEvidenceDerivativeV1], predecessorEvent:TemporalEvidenceRetentionEventV1?)

    var workspaceID:WorkspaceID{switch self{case .acceptClip(let v,_,_),.registerDerivative(let v,_,_,_),.applyRetention(let v,_,_,_):v.workspaceID;case .appendAnchor(let v,_,_):v.workspaceID;case .removeClip(let e,_,_,_,_):e.workspaceID}}
    var mutationID:MutationIDV1{switch self{case .acceptClip(let v,_,_),.registerDerivative(let v,_,_,_),.applyRetention(let v,_,_,_):v.mutationID;case .appendAnchor(let v,_,_):v.mutationID;case .removeClip(let e,_,_,_,_):e.mutationID}}
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{let values:[WorkspaceEntityIdentityV1];switch self{case .acceptClip(let v,_,_),.registerDerivative(let v,_,_,_),.applyRetention(let v,_,_,_):values=[try .init(kind:.temporalEvidenceClip,id:v.clipID)];case .appendAnchor(let v,_,_):values=[try .init(kind:.timecodedEvidenceAnchor,id:v.anchorID)];case .removeClip(_,let clips,let anchors,_,_):values=try clips.map{try .init(kind:.temporalEvidenceClip,id:$0.clipID)}+anchors.map{try .init(kind:.timecodedEvidenceAnchor,id:$0.anchorID)}};let ordered=values.sorted{$0.stableKey<$1.stableKey};guard !ordered.isEmpty,Set(ordered).count==ordered.count,ordered.count<=MutationReceiptV1.maximumPostImageCount else{throw WorkspaceMutationContractFailureV1.invalidPlan};return ordered}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{switch self{case .acceptClip(let v,_,let p):return[try .init(kind:.temporalEvidenceClip,id:p?.clipID ?? v.clipID)];case .registerDerivative(_,_,let p,_),.applyRetention(_,_,let p,_):return[try .init(kind:.temporalEvidenceClip,id:p.clipID)];case .appendAnchor(let v,_,let p):return[try .init(kind:.timecodedEvidenceAnchor,id:p?.anchorID ?? v.anchorID)];case .removeClip:return try affectedIdentities}}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{switch self{case .acceptClip(_,_,let p):guard identity == (try concurrencyIdentities)[0]else{break};return p?.revision ?? 0;case .registerDerivative(_,_,let p,_),.applyRetention(_,_,let p,_):guard identity == (try concurrencyIdentities)[0]else{break};return p.revision;case .appendAnchor(_,_,let p):guard identity == (try concurrencyIdentities)[0]else{break};return p?.revision ?? 0;case .removeClip(_,let clips,let anchors,_,_):if identity.kind == .temporalEvidenceClip,let value=clips.first(where:{$0.clipID==identity.id}){return value.revision};if identity.kind == .timecodedEvidenceAnchor,let value=anchors.first(where:{$0.anchorID==identity.id}){return value.revision}};throw WorkspaceMutationContractFailureV1.invalidPlan}
    func validate()throws{switch self{case .acceptClip(let value,let review,let predecessor):try value.validateIntrinsic();try review.validate();guard review.workspaceID==value.workspaceID,review.clipID==value.clipID,review.decision == .accept,review.reviewedAt==value.acceptedAt else{throw WorkspaceMutationContractFailureV1.invalidPlan};if let predecessor{try predecessor.validateIntrinsic();guard value.workspaceID==predecessor.workspaceID,value.supersedesClipID==predecessor.clipID,value.revision==predecessor.revision+1,value.original==predecessor.original,value.originalProvenance==predecessor.originalProvenance,value.locator==predecessor.locator else{throw WorkspaceMutationContractFailureV1.invalidPlan}}else{guard value.revision==1,value.supersedesClipID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
        case .appendAnchor(let value,let clip,let predecessor):try value.validate(clip:clip);if let predecessor{try predecessor.validateIntrinsic();guard value.workspaceID==predecessor.workspaceID,value.clipID==predecessor.clipID,value.supersedesAnchorID==predecessor.anchorID,value.predecessorAnchorSHA256==predecessor.anchorSHA256,value.revision==predecessor.revision+1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}}else{guard value.revision==1,value.supersedesAnchorID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
        case .registerDerivative(let successor,let derivative,let predecessor,let priorDerivative):try predecessor.validateIntrinsic();try successor.validateIntrinsic();try derivative.validate(clip:predecessor);if let priorDerivative{try priorDerivative.validate(clip:predecessor);guard derivative.supersedesDerivativeID==priorDerivative.derivativeID,derivative.revision==priorDerivative.revision+1}else{guard derivative.revision==1,derivative.supersedesDerivativeID==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}};guard successor.supersedesClipID==predecessor.clipID,successor.revision==predecessor.revision+1,successor.original==predecessor.original,successor.target==predecessor.target,successor.derivativeReferences.contains(where:{$0.derivativeID==derivative.derivativeID&&$0.derivativeSHA256==derivative.derivativeSHA256}),successor.retentionReference==predecessor.retentionReference else{throw WorkspaceMutationContractFailureV1.invalidPlan}
        case .applyRetention(let successor,let event,let predecessor,let priorEvent):try predecessor.validateIntrinsic();try successor.validateIntrinsic();try event.validate(clip:predecessor);try Self.validateRetentionChain(event,predecessor:predecessor,priorEvent:priorEvent);let referencesMatch=event.disposition == .retain ? successor.derivativeReferences==predecessor.derivativeReferences : successor.derivativeReferences.isEmpty;guard event.disposition == .retain || event.disposition == .removeRegenerableDerivatives,referencesMatch,successor.supersedesClipID==predecessor.clipID,successor.revision==predecessor.revision+1,successor.original==predecessor.original,successor.target==predecessor.target,successor.retentionReference?.eventID==event.eventID,successor.retentionReference?.eventSHA256==event.eventSHA256 else{throw WorkspaceMutationContractFailureV1.invalidPlan}
        case .removeClip(let event,let clips,let anchors,let derivatives,let priorEvent):try clips.forEach{$0.validateIntrinsic()};guard !clips.isEmpty,Set(clips.map(\.clipID)).count==clips.count,Set(anchors.map(\.anchorID)).count==anchors.count,Set(derivatives.map(\.derivativeID)).count==derivatives.count,let predecessor=clips.first(where:{$0.clipID==event.clipID&&$0.revision==event.clipRevision&&$0.clipSHA256==event.clipSHA256})else{throw WorkspaceMutationContractFailureV1.invalidPlan};try event.validate(clip:predecessor);try Self.validateRetentionChain(event,predecessor:predecessor,priorEvent:priorEvent);let byID=Dictionary(uniqueKeysWithValues:clips.map{($0.clipID,$0)});try anchors.forEach{guard let clip=byID[$0.clipID]else{throw WorkspaceMutationContractFailureV1.invalidPlan};try $0.validate(clip:clip)};try derivatives.forEach{guard let clip=byID[$0.clipID]else{throw WorkspaceMutationContractFailureV1.invalidPlan};try $0.validate(clip:clip)};guard event.disposition == .deleteClip || event.disposition == .eraseWorkspace,clips.allSatisfy({$0.workspaceID==event.workspaceID&&$0.revision<UInt64.max}),anchors.allSatisfy({$0.workspaceID==event.workspaceID}),derivatives.allSatisfy({$0.workspaceID==event.workspaceID}) else{throw WorkspaceMutationContractFailureV1.invalidPlan}}}
    private static func validateRetentionChain(_ event:TemporalEvidenceRetentionEventV1,predecessor:TemporalEvidenceClipV1,priorEvent:TemporalEvidenceRetentionEventV1?)throws{if let priorEvent{try priorEvent.validate(clip:predecessor);guard event.supersedesEventID==priorEvent.eventID,event.predecessorEventSHA256==priorEvent.eventSHA256,event.revision==priorEvent.revision+1 else{throw WorkspaceMutationContractFailureV1.invalidPlan}}else{guard event.revision==1,event.supersedesEventID==nil,event.predecessorEventSHA256==nil else{throw WorkspaceMutationContractFailureV1.invalidPlan}}}
}

struct TemporalEvidenceMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:WorkspaceExpectedRevisionV1;let mutationID:MutationIDV1;let payload:TemporalEvidenceMutationPayloadV1
    init(workspaceID:WorkspaceID,expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,payload:TemporalEvidenceMutationPayloadV1)throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.payload=payload;try validate()}
    func validate()throws{try payload.validate();let targets=try payload.concurrencyIdentities;guard schemaVersion==Self.schemaVersion,workspaceID==payload.workspaceID,workspaceID==expectedRevision.workspaceID,mutationID==payload.mutationID,expectedRevision.entityRevisions.filter({targets.contains($0.identity)}).count==targets.count,try targets.allSatisfy({identity in expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision == payload.expectedRevision(for:identity)})else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    var affectedIdentities:[WorkspaceEntityIdentityV1]{get throws{try payload.affectedIdentities}}
    var concurrencyIdentities:[WorkspaceEntityIdentityV1]{get throws{try payload.concurrencyIdentities}}
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{try payload.expectedRevision(for:identity)}
    var mutationPostImages:[MutationPostImageV1]{get throws{let concurrency=try payload.concurrencyIdentities;switch payload{case .acceptClip(let v,_,_),.registerDerivative(let v,_,_,_),.applyRetention(let v,_,_,_):return[.temporalEvidenceClip(id:v.clipID,concurrencyIdentity:concurrency[0],revision:v.revision,semanticSHA256:v.clipSHA256)];case .appendAnchor(let v,_,_):return[.timecodedEvidenceAnchor(id:v.anchorID,concurrencyIdentity:concurrency[0],revision:v.revision,semanticSHA256:v.anchorSHA256)];case .removeClip(let event,let clips,let anchors,_,_):return try (clips.map{let identity=try WorkspaceEntityIdentityV1(kind:.temporalEvidenceClip,id:$0.clipID);return MutationPostImageV1.tombstone(identity:identity,revision:$0.revision+1,semanticSHA256:event.eventSHA256)}+anchors.map{let identity=try WorkspaceEntityIdentityV1(kind:.timecodedEvidenceAnchor,id:$0.anchorID);return MutationPostImageV1.tombstone(identity:identity,revision:$0.revision+1,semanticSHA256:event.eventSHA256)}).sorted{try $0.identity.stableKey<$1.identity.stableKey}}}}
    func canonicalWorkspaceMutationRequest()throws->WorkspaceMutationRequestV1{try validate();return .init(mutationID:mutationID,expectedRevision:expectedRevision,command:.applyTemporalEvidence(self))}
}

extension AssetLabelMutationV1 {
    var affectedIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            try WorkspaceEntityIdentityV1(
                kind: .acceptedLabelGenerationSnapshot,
                id: snapshot.snapshotID
            )
        }
    }

    func validateForCanonicalMutation() throws {
        try validate()
        let identity = try affectedIdentity
        guard expectedRevision.entityRevisions.first(where: {
            $0.identity == identity
        })?.revision == 0 else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    var mutationPostImage: MutationPostImageV1 {
        get throws {
            try validateForCanonicalMutation()
            let identity = try affectedIdentity
            return .acceptedLabelGenerationSnapshot(
                id: snapshot.snapshotID,
                concurrencyIdentity: identity,
                revision: snapshot.revision,
                semanticSHA256: snapshot.snapshotSHA256
            )
        }
    }

    func canonicalWorkspaceMutationRequest() throws -> WorkspaceMutationRequestV1 {
        try validateForCanonicalMutation()
        return try WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            command: .applyAssetLabel(self)
        )
    }
}

extension ActivityContractMutationV2 {
    var affectedIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            var values = [try WorkspaceEntityIdentityV1(
                kind: .activitySessionEnvelope,
                id: successorEnvelope.activityID
            )]
            if let transition {
                values.append(try .init(kind: .activityStateTransition, id: transition.transitionID))
            }
            values += try installationTaskResults.map {
                try .init(kind: .installationTaskResult, id: $0.resultID)
            }
            if let installationAsBuiltSnapshot {
                values.append(try .init(kind: .installationAsBuiltSnapshot, id: installationAsBuiltSnapshot.snapshotID))
            }
            if let punchReviewBasisSnapshot {
                values.append(try .init(kind: .punchReviewBasisSnapshot, id: punchReviewBasisSnapshot.basisID))
            }
            let ordered = values.sorted { $0.stableKey < $1.stableKey }
            guard ordered.count <= MutationReceiptV1.maximumPostImageCount,
                  Set(ordered).count == ordered.count else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return ordered
        }
    }

    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            try affectedIdentities
        }
    }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        guard (try concurrencyIdentities).contains(identity) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        if let revision = expectedRevision.entityRevisions.first(where: { $0.identity == identity })?.revision {
            return revision
        }
        guard identity.kind != .activitySessionEnvelope else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return 0
    }

    var mutationPostImages: [MutationPostImageV1] {
        get throws {
            let envelopeIdentity = try WorkspaceEntityIdentityV1(
                kind: .activitySessionEnvelope,
                id: successorEnvelope.activityID
            )
            var values: [MutationPostImageV1] = [
                .activitySessionEnvelope(
                    id: successorEnvelope.activityID,
                    concurrencyIdentity: envelopeIdentity,
                    revision: successorEnvelope.revision,
                    semanticSHA256: successorEnvelope.envelopeSHA256
                )
            ]
            if let transition {
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .activityStateTransition,
                    id: transition.transitionID
                )
                values.append(.activityStateTransition(
                    id: transition.transitionID,
                    concurrencyIdentity: identity,
                    revision: transition.revision,
                    semanticSHA256: transition.transitionSHA256
                ))
            }
            values += try installationTaskResults.map { result in
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .installationTaskResult,
                    id: result.resultID
                )
                return .installationTaskResult(
                    id: result.resultID,
                    concurrencyIdentity: identity,
                    revision: result.revision,
                    semanticSHA256: result.resultSHA256
                )
            }
            if let installationAsBuiltSnapshot {
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .installationAsBuiltSnapshot,
                    id: installationAsBuiltSnapshot.snapshotID
                )
                values.append(.installationAsBuiltSnapshot(
                    id: installationAsBuiltSnapshot.snapshotID,
                    concurrencyIdentity: identity,
                    revision: installationAsBuiltSnapshot.revision,
                    semanticSHA256: installationAsBuiltSnapshot.snapshotSHA256
                ))
            }
            if let punchReviewBasisSnapshot {
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .punchReviewBasisSnapshot,
                    id: punchReviewBasisSnapshot.basisID
                )
                values.append(.punchReviewBasisSnapshot(
                    id: punchReviewBasisSnapshot.basisID,
                    concurrencyIdentity: identity,
                    revision: punchReviewBasisSnapshot.revision,
                    semanticSHA256: punchReviewBasisSnapshot.basisSHA256
                ))
            }
            let ordered = try values.sorted { try $0.identity.stableKey < $1.identity.stableKey }
            guard ordered.count <= MutationReceiptV1.maximumPostImageCount,
                  Set(try ordered.map { try $0.identity }).count == ordered.count,
                  Set(try ordered.map { try $0.concurrencyIdentity }).count == ordered.count,
                  try ordered.allSatisfy({ try $0.identity == $0.concurrencyIdentity }) else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return ordered
        }
    }

    func validateForCanonicalMutation() throws {
        try validate()
        let identities = try concurrencyIdentities
        let activityIdentity = try WorkspaceEntityIdentityV1(
            kind: .activitySessionEnvelope,
            id: successorEnvelope.activityID
        )
        let expectedByIdentity = Dictionary(uniqueKeysWithValues: expectedRevision.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        guard expectedRevision.workspaceID == workspaceID,
              expectedByIdentity.count == expectedRevision.entityRevisions.count,
              expectedByIdentity[activityIdentity] == (predecessorEnvelope?.revision ?? 0),
              identities.filter({ $0 != activityIdentity }).allSatisfy({
                  expectedByIdentity[$0, default: 0] == 0
              }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    func canonicalWorkspaceMutationRequest() throws -> WorkspaceMutationRequestV1 {
        try validateForCanonicalMutation()
        return try WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            command: .applyActivityContract(self)
        )
    }
}

/// The canonical writer accepts only the apply-to-C14 branch of portable
/// review. History-only, discard, and quarantine remain device-local session
/// operations and must never masquerade as workspace mutations.
struct PortableReviewMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let plan: ExternalReviewImportPlanV1
    let importReceipt: ExternalReviewImportReceiptV1
    let inspectionReviewMutation: InspectionReviewMutationV1

    init(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1,
        plan: ExternalReviewImportPlanV1,
        importReceipt: ExternalReviewImportReceiptV1,
        inspectionReviewMutation: InspectionReviewMutationV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.mutationID = mutationID
        self.plan = plan
        self.importReceipt = importReceipt
        self.inspectionReviewMutation = inspectionReviewMutation
        try validate()
    }

    var affectedIdentities: [WorkspaceEntityIdentityV1] { get throws { try inspectionReviewMutation.affectedIdentities } }
    var concurrencyIdentities: [WorkspaceEntityIdentityV1] { get throws { try inspectionReviewMutation.concurrencyIdentities } }
    var mutationPostImages: [MutationPostImageV1] { get throws { try inspectionReviewMutation.postImage.mutationPostImages } }
    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        guard (try concurrencyIdentities).contains(identity) else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        guard let image = try mutationPostImages.first(where: { try $0.concurrencyIdentity == identity }),
              image.revision > 0 else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        return image.revision - 1
    }

    func validate() throws {
        try plan.validate()
        try importReceipt.validate()
        try inspectionReviewMutation.validate()
        let c14EffectDigest = Data(SHA256.hash(data: try WorkspaceMutationCanonicalV1.data(inspectionReviewMutation)))
        guard schemaVersion == Self.schemaVersion,
              plan.basisWorkspaceRevision < UInt64.max,
              plan.disposition == .exactPendingDecision,
              plan.decision == .acceptAndApply,
              plan.proofAssessment.applicationEligibility == .eligible,
              plan.mutationID == mutationID,
              importReceipt.workspaceID == workspaceID,
              importReceipt.basisWorkspaceRevision == plan.basisWorkspaceRevision,
              importReceipt.responseRecordID == plan.responseRecord.recordID,
              importReceipt.canonicalResponseSHA256 == plan.responseRecord.canonicalResponse.sha256,
              importReceipt.mutationID == mutationID,
              importReceipt.decision == .acceptAndApply,
              importReceipt.proofAssessment == plan.proofAssessment,
              importReceipt.effectDigest == c14EffectDigest,
              importReceipt.appliedWorkspaceRevision == plan.basisWorkspaceRevision + 1,
              inspectionReviewMutation.workspaceID == workspaceID,
              inspectionReviewMutation.mutationID == mutationID,
              !(try affectedIdentities).isEmpty else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        switch plan.responseRecord.source {
        case .portableFile:
            guard plan.proofAssessment.proofValidity == .valid else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        case .originRecordedElsewhere:
            guard plan.proofAssessment.proofValidity == .unavailable else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        }
        guard case let .applyReviewBundle(bundle) = inspectionReviewMutation.postImage,
              bundle.transition.mutationID == mutationID,
              bundle.transition.workspaceID == workspaceID else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        try PortableReviewC14ReconciliationV1.validate(plan: plan, bundle: bundle)
    }

    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }
}

/// The sole canonical append-only writer command for C49. Direct cost is an
/// optional immutable field of the same postimage, never a second ledger.
struct WorkResourceMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let postImage: WorkResourceEntryV1

    init(workspaceID: WorkspaceID, mutationID: MutationIDV1, postImage: WorkResourceEntryV1) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.mutationID = mutationID
        self.postImage = postImage
        try validate()
    }

    var affectedIdentity: WorkspaceEntityIdentityV1 { get throws { try .init(kind: .workResourceEntry, id: postImage.entryID) } }
    var affectedIdentities: [WorkspaceEntityIdentityV1] { get throws { [try affectedIdentity] } }
    var concurrencyIdentity: WorkspaceEntityIdentityV1 { get throws {
        if let predecessor = postImage.supersedesEntryID { return try .init(kind: .workResourceEntry, id: predecessor) }
        return try affectedIdentity
    } }
    var concurrencyIdentities: [WorkspaceEntityIdentityV1] { get throws { [try concurrencyIdentity] } }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        guard identity == (try concurrencyIdentity) else { throw WorkspaceMutationContractFailureV1.invalidPlan }
        return postImage.expectedRevision
    }

    var mutationPostImage: MutationPostImageV1 { get throws {
        try .workResourceEntry(id: postImage.entryID, concurrencyIdentity: concurrencyIdentity, revision: postImage.revision, semanticSHA256: postImage.entrySHA256)
    } }
    var mutationPostImages: [MutationPostImageV1] { get throws { [try mutationPostImage] } }

    func validate() throws {
        try postImage.validate()
        let next = postImage.expectedRevision.addingReportingOverflow(1)
        guard schemaVersion == Self.schemaVersion,
              workspaceID == postImage.workspaceID,
              mutationID == postImage.mutationID,
              !next.overflow,
              postImage.revision == next.partialValue else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }

    func canonicalWorkspaceMutationRequest(
        expectedRevision: WorkspaceExpectedRevisionV1
    ) throws -> WorkspaceMutationRequestV1 {
        try validate()
        let concurrency = try concurrencyIdentity
        guard expectedRevision.workspaceID == workspaceID,
              expectedRevision.entityRevisions.count == 1,
              expectedRevision.entityRevisions.first?.identity == concurrency,
              expectedRevision.entityRevisions.first?.revision == postImage.expectedRevision else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return try WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            command: .applyWorkResource(self)
        )
    }
}

// MARK: - C55 parts-stock sole-writer bridge

extension PartsStockMutationV1 {
    private func image(_ id: UUID, _ kind: WorkspaceEntityKindV1, _ concurrency: WorkspaceEntityIdentityV1, _ revision: UInt64, _ digest: String) -> MutationPostImageV1 {
        .partsStock(id: id, kind: kind, concurrencyIdentity: concurrency, revision: revision, semanticSHA256: digest)
    }

    var affectedIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            switch self {
            case let .upsertPart(value): return [try .init(kind: .localPartDefinition, id: value.partID)]
            case let .retirePart(value): return [try .init(kind: .localPartDefinition, id: value.archivedPartSuccessor.partID)]
            case let .upsertLocation(value, _): return [try .init(kind: .stockStorageLocation, id: value.locationID)]
            case let .appendMovement(value): return [try .init(kind: .stockMovementEvent, id: value.movementID)]
            case let .transfer(value): return try [
                .init(kind: .stockMovementEvent, id: value.outbound.movementID),
                .init(kind: .stockMovementEvent, id: value.inbound.movementID)
            ].sorted { $0.stableKey < $1.stableKey }
            case let .use(value): return try [
                .init(kind: .stockMovementEvent, id: value.movement.movementID),
                .init(kind: .stockUseReceipt, id: value.receiptID),
                .init(kind: .workResourceEntry, id: value.workResourceSuccessor.entryID)
            ].sorted { $0.stableKey < $1.stableKey }
            case let .reverseUse(value): return try [.init(kind: .stockMovementEvent, id: value.reversalMovement.movementID), .init(kind: .stockUseReversalReceipt, id: value.receiptID), .init(kind: .workResourceEntry, id: value.workResourceSuccessor.entryID)].sorted { $0.stableKey < $1.stableKey }
            case let .returnAgainstUse(value): return try [
                .init(kind: .stockMovementEvent, id: value.returnMovement.movementID),
                .init(kind: .stockReturnReceipt, id: value.receiptID),
                .init(kind: .workResourceEntry, id: value.workResourceSuccessor.entryID)
            ].sorted { $0.stableKey < $1.stableKey }
            case let .abandon(value): return try ([
                .init(kind: .localPartDefinition, id: value.archivedPartSuccessor.partID)
            ] + value.dispositions.map { try .init(kind: .stockAbandonment, id: $0.dispositionID) }).sorted { $0.stableKey < $1.stableKey }
            }
        }
    }

    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            switch self {
            case let .upsertPart(value): return [try .init(kind: .localPartDefinition, id: value.partID)]
            case let .retirePart(value): return [try .init(kind: .localPartDefinition, id: value.archivedPartSuccessor.partID)]
            case let .upsertLocation(value, _): return [try .init(kind: .stockStorageLocation, id: value.locationID)]
            case let .appendMovement(value): return [try StockBalanceStreamIdentityV1.entity(partID: value.part.partID, locationID: value.locationID)]
            case let .transfer(value): return try [
                StockBalanceStreamIdentityV1.entity(partID: value.outbound.part.partID, locationID: value.outbound.locationID),
                StockBalanceStreamIdentityV1.entity(partID: value.inbound.part.partID, locationID: value.inbound.locationID)
            ].sorted { $0.stableKey < $1.stableKey }
            case let .use(value): return try [
                StockBalanceStreamIdentityV1.entity(partID: value.movement.part.partID, locationID: value.movement.locationID),
                .init(kind: .stockUseReceipt, id: value.receiptID),
                .init(kind: .workResourceEntry, id: value.workResourceSuccessor.supersedesEntryID ?? value.workResourceSuccessor.entryID)
            ].sorted { $0.stableKey < $1.stableKey }
            case let .reverseUse(value): return try [StockBalanceStreamIdentityV1.entity(partID: value.reversalMovement.part.partID, locationID: value.reversalMovement.locationID), .init(kind: .stockUseReversalReceipt, id: value.receiptID), .init(kind: .workResourceEntry, id: value.workResourceSuccessor.supersedesEntryID ?? value.workResourceSuccessor.entryID)].sorted { $0.stableKey < $1.stableKey }
            case let .returnAgainstUse(value): return try [
                StockBalanceStreamIdentityV1.entity(partID: value.returnMovement.part.partID, locationID: value.returnMovement.locationID),
                .init(kind: .stockReturnReceipt, id: value.receiptID),
                .init(kind: .workResourceEntry, id: value.workResourceSuccessor.supersedesEntryID ?? value.workResourceSuccessor.entryID)
            ].sorted { $0.stableKey < $1.stableKey }
            case let .abandon(value): return try ([ .init(kind: .localPartDefinition, id: value.archivedPartSuccessor.partID) ] + value.dispositions.map { try .init(kind: .stockAbandonment, id: $0.dispositionID) }).sorted { $0.stableKey < $1.stableKey }
            }
        }
    }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        switch self {
        case let .upsertPart(value):
            guard identity == (try .init(kind: .localPartDefinition, id: value.partID)), value.revision > 0 else { throw WorkspaceMutationContractFailureV1.invalidPlan }
            return value.revision - 1
        case let .retirePart(value):
            let successor = value.archivedPartSuccessor
            guard identity == (try .init(kind: .localPartDefinition, id: successor.partID)), successor.revision > 0 else { throw WorkspaceMutationContractFailureV1.invalidPlan }
            return successor.revision - 1
        case let .abandon(value):
            let successor = value.archivedPartSuccessor
            if identity == (try .init(kind: .localPartDefinition, id: successor.partID)) { guard successor.revision > 0 else { throw WorkspaceMutationContractFailureV1.invalidPlan }; return successor.revision - 1 }
            if value.dispositions.contains(where: { $0.dispositionID == identity.id }) && identity.kind == .stockAbandonment { return 0 }
            throw WorkspaceMutationContractFailureV1.invalidPlan
        case let .upsertLocation(value, _):
            guard identity == (try .init(kind: .stockStorageLocation, id: value.locationID)), value.revision > 0 else { throw WorkspaceMutationContractFailureV1.invalidPlan }
            return value.revision - 1
        case let .appendMovement(value):
            guard identity == (try StockBalanceStreamIdentityV1.entity(partID: value.part.partID, locationID: value.locationID)) else { throw WorkspaceMutationContractFailureV1.invalidPlan }; return value.expectedLocationRevision
        case let .transfer(value):
            if identity == (try StockBalanceStreamIdentityV1.entity(partID: value.outbound.part.partID, locationID: value.outbound.locationID)) { return value.outbound.expectedLocationRevision }
            if identity == (try StockBalanceStreamIdentityV1.entity(partID: value.inbound.part.partID, locationID: value.inbound.locationID)) { return value.inbound.expectedLocationRevision }
        case let .use(value):
            if identity == (try StockBalanceStreamIdentityV1.entity(partID: value.movement.part.partID, locationID: value.movement.locationID)) { return value.movement.expectedLocationRevision }
            if identity == (try .init(kind: .workResourceEntry, id: value.workResourceSuccessor.supersedesEntryID ?? value.workResourceSuccessor.entryID)) { return value.workResourceSuccessor.expectedRevision }
            if identity == (try .init(kind: .stockUseReceipt, id: value.receiptID)) { return 0 }
        case let .reverseUse(value):
            if identity == (try StockBalanceStreamIdentityV1.entity(partID: value.reversalMovement.part.partID, locationID: value.reversalMovement.locationID)) { return value.reversalMovement.expectedLocationRevision }
            if identity == (try .init(kind: .workResourceEntry, id: value.workResourceSuccessor.supersedesEntryID ?? value.workResourceSuccessor.entryID)) { return value.workResourceSuccessor.expectedRevision }
            if identity == (try .init(kind: .stockUseReversalReceipt, id: value.receiptID)) { return 0 }
        case let .returnAgainstUse(value):
            if identity == (try StockBalanceStreamIdentityV1.entity(partID: value.returnMovement.part.partID, locationID: value.returnMovement.locationID)) { return value.returnMovement.expectedLocationRevision }
            if identity == (try .init(kind: .workResourceEntry, id: value.workResourceSuccessor.supersedesEntryID ?? value.workResourceSuccessor.entryID)) { return value.workResourceSuccessor.expectedRevision }
            if identity == (try .init(kind: .stockReturnReceipt, id: value.receiptID)) { return 0 }
        }
        throw WorkspaceMutationContractFailureV1.invalidPlan
    }

    var mutationPostImages: [MutationPostImageV1] {
        get throws {
            switch self {
            case let .upsertPart(v): return [image(v.partID, .localPartDefinition, try .init(kind: .localPartDefinition, id: v.partID), v.revision, v.partSHA256)]
            case let .retirePart(v): let successor = v.archivedPartSuccessor; return [image(successor.partID, .localPartDefinition, try .init(kind: .localPartDefinition, id: successor.partID), successor.revision, successor.partSHA256)]
            case let .upsertLocation(v, _): return [image(v.locationID, .stockStorageLocation, try .init(kind: .stockStorageLocation, id: v.locationID), v.revision, try PartsStockCanonicalCodecV1.sha256(v))]
            case let .appendMovement(v): return [image(v.movementID, .stockMovementEvent, try StockBalanceStreamIdentityV1.entity(partID: v.part.partID, locationID: v.locationID), v.locationRevision, v.eventSHA256)]
            case let .transfer(v): return try [
                image(v.outbound.movementID, .stockMovementEvent, StockBalanceStreamIdentityV1.entity(partID: v.outbound.part.partID, locationID: v.outbound.locationID), v.outbound.locationRevision, v.outbound.eventSHA256),
                image(v.inbound.movementID, .stockMovementEvent, StockBalanceStreamIdentityV1.entity(partID: v.inbound.part.partID, locationID: v.inbound.locationID), v.inbound.locationRevision, v.inbound.eventSHA256)
            ].sorted { try $0.identity.stableKey < $1.identity.stableKey }
            case let .use(v): return try [
                image(v.movement.movementID, .stockMovementEvent, StockBalanceStreamIdentityV1.entity(partID: v.movement.part.partID, locationID: v.movement.locationID), v.movement.locationRevision, v.movement.eventSHA256),
                image(v.receiptID, .stockUseReceipt, .init(kind: .stockUseReceipt, id: v.receiptID), 1, v.receiptSHA256),
                .workResourceEntry(id: v.workResourceSuccessor.entryID, concurrencyIdentity: .init(kind: .workResourceEntry, id: v.workResourceSuccessor.supersedesEntryID ?? v.workResourceSuccessor.entryID), revision: v.workResourceSuccessor.revision, semanticSHA256: v.workResourceSuccessor.entrySHA256)
            ].sorted { try $0.identity.stableKey < $1.identity.stableKey }
            case let .reverseUse(v): return try [image(v.reversalMovement.movementID, .stockMovementEvent, StockBalanceStreamIdentityV1.entity(partID: v.reversalMovement.part.partID, locationID: v.reversalMovement.locationID), v.reversalMovement.locationRevision, v.reversalMovement.eventSHA256), image(v.receiptID, .stockUseReversalReceipt, .init(kind: .stockUseReversalReceipt, id: v.receiptID), 1, v.receiptSHA256), .workResourceEntry(id: v.workResourceSuccessor.entryID, concurrencyIdentity: .init(kind: .workResourceEntry, id: v.workResourceSuccessor.supersedesEntryID ?? v.workResourceSuccessor.entryID), revision: v.workResourceSuccessor.revision, semanticSHA256: v.workResourceSuccessor.entrySHA256)].sorted { try $0.identity.stableKey < $1.identity.stableKey }
            case let .returnAgainstUse(v): return try [
                image(v.returnMovement.movementID, .stockMovementEvent, StockBalanceStreamIdentityV1.entity(partID: v.returnMovement.part.partID, locationID: v.returnMovement.locationID), v.returnMovement.locationRevision, v.returnMovement.eventSHA256),
                image(v.receiptID, .stockReturnReceipt, .init(kind: .stockReturnReceipt, id: v.receiptID), 1, v.receiptSHA256),
                .workResourceEntry(id: v.workResourceSuccessor.entryID, concurrencyIdentity: .init(kind: .workResourceEntry, id: v.workResourceSuccessor.supersedesEntryID ?? v.workResourceSuccessor.entryID), revision: v.workResourceSuccessor.revision, semanticSHA256: v.workResourceSuccessor.entrySHA256)
            ].sorted { try $0.identity.stableKey < $1.identity.stableKey }
            case let .abandon(v): return try ([image(v.archivedPartSuccessor.partID, .localPartDefinition, .init(kind: .localPartDefinition, id: v.archivedPartSuccessor.partID), v.archivedPartSuccessor.revision, v.archivedPartSuccessor.partSHA256)] + v.dispositions.map { image($0.dispositionID, .stockAbandonment, try .init(kind: .stockAbandonment, id: $0.dispositionID), 1, try PartsStockCanonicalCodecV1.sha256($0)) }).sorted { try $0.identity.stableKey < $1.identity.stableKey }
            }
        }
    }
}

// MARK: - C52 canonical service-request mutation bridge

extension ServiceRequestMutationPayloadV1 {
    var affectedIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .appendRecord(value):
                return try .init(kind: .serviceRequestRecord, id: value.recordID)
            case let .appendDisposition(value):
                return try .init(kind: .serviceRequestDispositionEvent, id: value.eventID)
            case let .appendWorkLink(value), let .appendWorkLinkReversal(value):
                return try .init(kind: .serviceRequestWorkLinkEvent, id: value.eventID)
            }
        }
    }

    var concurrencyIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .appendRecord(value):
                return try .init(kind: .serviceRequestRecord, id: value.recordID)
            case let .appendDisposition(value):
                return try .init(kind: .serviceRequestDispositionEvent, id: value.predecessorEventID ?? value.eventID)
            case let .appendWorkLink(value), let .appendWorkLinkReversal(value):
                return try .init(kind: .serviceRequestWorkLinkEvent, id: value.predecessorEventID ?? value.eventID)
            }
        }
    }

    var expectedEntityRevision: UInt64 {
        switch self {
        case let .appendRecord(value): return value.revision - 1
        case let .appendDisposition(value): return value.revision - 1
        case let .appendWorkLink(value), let .appendWorkLinkReversal(value): return value.revision - 1
        }
    }

    var mutationPostImage: MutationPostImageV1 {
        get throws {
            switch self {
            case let .appendRecord(value):
                return try .serviceRequestRecord(
                    id: value.recordID, concurrencyIdentity: concurrencyIdentity,
                    revision: value.revision, semanticSHA256: value.recordSHA256
                )
            case let .appendDisposition(value):
                return try .serviceRequestDispositionEvent(
                    id: value.eventID, concurrencyIdentity: concurrencyIdentity,
                    revision: value.revision, semanticSHA256: value.eventSHA256
                )
            case let .appendWorkLink(value), let .appendWorkLinkReversal(value):
                return try .serviceRequestWorkLinkEvent(
                    id: value.eventID, concurrencyIdentity: concurrencyIdentity,
                    revision: value.revision, semanticSHA256: value.eventSHA256
                )
            }
        }
    }
}

extension ServiceRequestMutationV1 {
    var affectedIdentities: [WorkspaceEntityIdentityV1] {
        get throws { try payloads.map(\.affectedIdentity).sorted { $0.stableKey < $1.stableKey } }
    }
    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws { try payloads.map(\.concurrencyIdentity).sorted { $0.stableKey < $1.stableKey } }
    }
    var mutationPostImages: [MutationPostImageV1] {
        get throws { try payloads.map(\.mutationPostImage).sorted { try $0.identity.stableKey < $1.identity.stableKey } }
    }
    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        guard let payload = try payloads.first(where: { try $0.concurrencyIdentity == identity }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return payload.expectedEntityRevision
    }
    func validateForCanonicalWriter() throws {
        try validate()
        let affected = try affectedIdentities
        let concurrency = try concurrencyIdentities
        guard affected.count <= MutationReceiptV1.maximumPostImageCount,
              Set(affected).count == affected.count,
              Set(concurrency).count == concurrency.count,
              expectedRevision.entityRevisions.count == concurrency.count,
              try concurrency.allSatisfy({ identity in
                  expectedRevision.entityRevisions.first(where: { $0.identity == identity })?.revision
                      == self.expectedRevision(for: identity)
              }) else { throw WorkspaceMutationContractFailureV1.invalidPlan }
    }
}

// MARK: - C53 append-only asset-service reliability mutation bridge

extension ServiceReliabilityMutationPayloadV1 {
    var workspaceID:WorkspaceID { switch self {case .incident(let v):v.workspaceID;case .impact(let v):v.workspaceID;case .cause(let v):v.workspaceID;case .remedy(let v):v.workspaceID;case .repair(let v):v.workspaceID;case .restoration(let v):v.workspaceID;case .exposure(let v):v.workspaceID} }
    var mutationID:MutationIDV1 { switch self {case .incident(let v):v.mutationID;case .impact(let v):v.mutationID;case .cause(let v):v.mutationID;case .remedy(let v):v.mutationID;case .repair(let v):v.mutationID;case .restoration(let v):v.mutationID;case .exposure(let v):v.mutationID} }
    var eventID:UUID { switch self {case .incident(let v):v.eventID;case .impact(let v):v.eventID;case .cause(let v):v.eventID;case .remedy(let v):v.eventID;case .repair(let v):v.eventID;case .restoration(let v):v.eventID;case .exposure(let v):v.eventID} }
    var predecessorReference:ServiceReliabilityEventReferenceV1? { switch self {case .incident(let v):v.predecessor;case .impact(let v):v.predecessor;case .cause(let v):v.predecessor;case .remedy(let v):v.predecessor;case .repair(let v):v.predecessor;case .restoration(let v):v.predecessor;case .exposure(let v):v.predecessor} }
    var predecessorEventID:UUID? { switch self {case .incident(let v):v.predecessor?.eventID;case .impact(let v):v.predecessor?.eventID;case .cause(let v):v.predecessor?.eventID;case .remedy(let v):v.predecessor?.eventID;case .repair(let v):v.predecessor?.eventID;case .restoration(let v):v.predecessor?.eventID;case .exposure(let v):v.predecessor?.eventID} }
    var revision:UInt64 { switch self {case .incident(let v):v.revision;case .impact(let v):v.revision;case .cause(let v):v.revision;case .remedy(let v):v.revision;case .repair(let v):v.revision;case .restoration(let v):v.revision;case .exposure(let v):v.revision} }
    var eventSHA256:String { switch self {case .incident(let v):v.eventSHA256;case .impact(let v):v.eventSHA256;case .cause(let v):v.eventSHA256;case .remedy(let v):v.eventSHA256;case .repair(let v):v.eventSHA256;case .restoration(let v):v.eventSHA256;case .exposure(let v):v.eventSHA256} }
    var entityKind:WorkspaceEntityKindV1 { switch self {case .incident:.assetServiceIncident;case .impact:.serviceImpactSegment;case .cause:.serviceCauseAssertion;case .remedy:.serviceRemedyAssertion;case .repair:.serviceRepairInterval;case .restoration:.serviceRestorationAssertion;case .exposure:.qualifiedServiceExposure} }
    var affectedIdentity:WorkspaceEntityIdentityV1 { get throws { try .init(kind:entityKind,id:eventID) } }
    var concurrencyIdentity:WorkspaceEntityIdentityV1 { get throws { try .init(kind:entityKind,id:predecessorEventID ?? eventID) } }
    var expectedEntityRevision:UInt64 { revision-1 }
    var mutationPostImage:MutationPostImageV1 { get throws {
        let c=try concurrencyIdentity
        switch self {case .incident:return .assetServiceIncident(id:eventID,concurrencyIdentity:c,revision:revision,semanticSHA256:eventSHA256);case .impact:return .serviceImpactSegment(id:eventID,concurrencyIdentity:c,revision:revision,semanticSHA256:eventSHA256);case .cause:return .serviceCauseAssertion(id:eventID,concurrencyIdentity:c,revision:revision,semanticSHA256:eventSHA256);case .remedy:return .serviceRemedyAssertion(id:eventID,concurrencyIdentity:c,revision:revision,semanticSHA256:eventSHA256);case .repair:return .serviceRepairInterval(id:eventID,concurrencyIdentity:c,revision:revision,semanticSHA256:eventSHA256);case .restoration:return .serviceRestorationAssertion(id:eventID,concurrencyIdentity:c,revision:revision,semanticSHA256:eventSHA256);case .exposure:return .qualifiedServiceExposure(id:eventID,concurrencyIdentity:c,revision:revision,semanticSHA256:eventSHA256)}
    } }
}

extension ServiceReliabilityAtomicBundleV1 {
    var affectedIdentities:[WorkspaceEntityIdentityV1] { get throws { try payloads.map(\.affectedIdentity).sorted{$0.stableKey<$1.stableKey} } }
    var concurrencyIdentities:[WorkspaceEntityIdentityV1] { get throws { try payloads.map(\.concurrencyIdentity).sorted{$0.stableKey<$1.stableKey} } }
    var mutationPostImages:[MutationPostImageV1] { get throws { try payloads.map(\.mutationPostImage).sorted{try $0.identity.stableKey<$1.identity.stableKey} } }
    func expectedRevision(for identity:WorkspaceEntityIdentityV1)throws->UInt64{guard let p=try payloads.first(where:{try $0.concurrencyIdentity==identity})else{throw WorkspaceMutationContractFailureV1.invalidPlan};return p.expectedEntityRevision}
    func validateForCanonicalWriter()throws{try validate();let affected=try affectedIdentities,concurrency=try concurrencyIdentities;guard Set(affected).count==affected.count,Set(concurrency).count==concurrency.count,expectedRevision.entityRevisions.filter({concurrency.contains($0.identity)}).count==concurrency.count,try concurrency.allSatisfy({identity in expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision==(try self.expectedRevision(for:identity))})else{throw WorkspaceMutationContractFailureV1.invalidPlan}}
    func canonicalWorkspaceMutationRequest()throws->WorkspaceMutationRequestV1{try validateForCanonicalWriter();return .init(mutationID:mutationID,expectedRevision:expectedRevision,command:.applyServiceReliability(self))}
}

// MARK: - C57 My Day sole-writer bridge

/// My Day's domain command owns only plan membership/order/estimate. This
/// bridge supplies the incumbent writer's workspace and entity CAS envelope;
/// source work/schedule state is deliberately absent from postimages.
struct MyDayMutationV1: Codable, Equatable, Sendable {
    let command: MyDayCommandV1
    let expectedRevision: WorkspaceExpectedRevisionV1

    init(command: MyDayCommandV1, expectedRevision: WorkspaceExpectedRevisionV1) throws {
        self.command = command
        self.expectedRevision = expectedRevision
        try validate()
    }

    var workspaceID: WorkspaceID { command.workspaceID }
    var mutationID: MutationIDV1 { command.mutationID }

    var resultingPlan: MyDayPlanV1 {
        switch command {
        case .save(let successor, _): return successor
        case .carryover(_, _, let target, _): return target
        }
    }

    var carryoverReceipt: MyDayCarryoverReceiptV1? {
        if case let .carryover(_, _, _, receipt) = command { return receipt }
        return nil
    }

    /// The receipt has no separately allocated identifier. Its command
    /// mutation ID is already a workspace-unique stable identifier and keeps
    /// replay, persistence, and postimage identity aligned.
    var carryoverReceiptID: UUID? { carryoverReceipt == nil ? nil : mutationID.rawValue }

    var affectedIdentities: [WorkspaceEntityIdentityV1] {
        get throws { try mutationPostImages.map { try $0.identity } }
    }

    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            var values = [try WorkspaceEntityIdentityV1(kind: .myDayPlan, id: resultingPlan.planID)]
            if case let .carryover(_, source, _, _) = command {
                values.append(try .init(kind: .myDayPlan, id: source.planID))
            }
            if let receiptID = carryoverReceiptID {
                values.append(try .init(kind: .myDayCarryoverReceipt, id: receiptID))
            }
            return Array(Set(values)).sorted { $0.stableKey < $1.stableKey }
        }
    }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        guard try concurrencyIdentities.contains(identity),
              let value = expectedRevision.entityRevisions.first(where: { $0.identity == identity }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return value.revision
    }

    var mutationPostImages: [MutationPostImageV1] {
        get throws {
            let planIdentity = try WorkspaceEntityIdentityV1(kind: .myDayPlan, id: resultingPlan.planID)
            var values: [MutationPostImageV1] = [
                .myDayPlan(
                    id: resultingPlan.planID,
                    concurrencyIdentity: planIdentity,
                    revision: resultingPlan.revision,
                    semanticSHA256: resultingPlan.planSHA256
                )
            ]
            if let receipt = carryoverReceipt, let receiptID = carryoverReceiptID {
                let receiptIdentity = try WorkspaceEntityIdentityV1(kind: .myDayCarryoverReceipt, id: receiptID)
                values.append(.myDayCarryoverReceipt(
                    id: receiptID,
                    concurrencyIdentity: receiptIdentity,
                    revision: 1,
                    semanticSHA256: receipt.receiptSHA256
                ))
            }
            return try values.sorted { try $0.identity.stableKey < $1.identity.stableKey }
        }
    }

    func validate() throws {
        try command.validate()
        guard expectedRevision.workspaceID == workspaceID else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        switch command {
        case let .save(successor, predecessor):
            try successor.validate(predecessor: predecessor)
        case let .carryover(plan, source, target, receipt):
            try plan.validate()
            try receipt.validate(plan: plan, source: source, target: target)
            let targetBaseRevision = plan.expectedTargetPlan?.revision ?? 0
            let (targetRevision, overflow) = targetBaseRevision.addingReportingOverflow(1)
            guard plan.sourcePlan == (try MyDayPlanReferenceV1(source)),
                  plan.targetKey == target.key,
                  target.predecessorPlanSHA256 == plan.expectedTargetPlan?.planSHA256,
                  plan.expectedTargetPlan.map({ target.planID == $0.planID }) ?? true,
                  !overflow,
                  target.revision == targetRevision else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
        }
        let concurrency = try concurrencyIdentities
        let images = try mutationPostImages
        let affected = try images.map { try $0.identity }
        guard images.count <= MutationReceiptV1.maximumPostImageCount,
              Set(concurrency).count == concurrency.count,
              Set(affected).count == affected.count,
              expectedRevision.entityRevisions.count == concurrency.count,
              Set(expectedRevision.entityRevisions.map(\.identity)) == Set(concurrency),
              try concurrency.allSatisfy({ identity in
                  let expected = try self.expectedRevision(for: identity)
                  guard expected < UInt64.max else { return false }
                  if identity.kind == .myDayCarryoverReceipt { return expected == 0 }
                  if case let .carryover(_, source, _, _) = command,
                     identity.kind == .myDayPlan,
                     identity.id == source.planID {
                      return expected == source.revision
                  }
                  return resultingPlan.revision == expected + 1
              }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    func canonicalWorkspaceMutationRequest() throws -> WorkspaceMutationRequestV1 {
        try validate()
        return .init(mutationID: mutationID, expectedRevision: expectedRevision, command: .applyMyDay(self))
    }
}

extension EvidenceMetadataMutationV1 {
    static func associationEntityIdentity(
        workspaceID: String,
        evidenceID: String
    ) throws -> WorkspaceEntityIdentityV1 {
        let digest = SHA256.hash(data: Data("\(workspaceID)|\(evidenceID)".utf8))
        let bytes = Array(digest)
        let identifier = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return try .init(kind: .evidenceAssociationEvent, id: identifier)
    }

    var affectedIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            try [
                Self.associationEntityIdentity(
                    workspaceID: associationEvent.workspaceID,
                    evidenceID: associationEvent.evidenceID
                ),
                .init(kind: .evidenceSequenceRevision, id: sequenceSuccessor.sequenceID),
            ].sorted { $0.stableKey < $1.stableKey }
        }
    }

    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            return try [
                Self.associationEntityIdentity(
                    workspaceID: associationEvent.workspaceID,
                    evidenceID: associationEvent.evidenceID
                ),
                .init(kind: .evidenceSequenceRevision, id: sequenceSuccessor.sequenceID),
            ].sorted { $0.stableKey < $1.stableKey }
        }
    }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        switch identity.kind {
        case .evidenceAssociationEvent:
            guard let revision = UInt64(exactly: associationEvent.expectedEvidenceRevision),
                  try concurrencyIdentities.contains(identity) else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return revision
        case .evidenceSequenceRevision:
            guard identity.id == sequenceSuccessor.sequenceID else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return expectedSequenceRevision
        default:
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }
}

struct RoundSessionMutationV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: UInt64
    let mutationID: MutationIDV1
    let session: RoundSessionV1

    init(workspaceID: WorkspaceID, expectedRevision: UInt64, mutationID: MutationIDV1, session: RoundSessionV1) throws {
        try session.validateIntrinsic()
        guard expectedRevision < UInt64.max, workspaceID == session.workspaceID,
              mutationID == session.mutationID, session.revision == expectedRevision + 1,
              (expectedRevision == 0) == (session.predecessor == nil),
              session.predecessor?.revision == expectedRevision else { throw RoundSessionFailureV1.staleRevision }
        self.workspaceID = workspaceID; self.expectedRevision = expectedRevision
        self.mutationID = mutationID; self.session = session
    }
    var affectedIdentity: WorkspaceEntityIdentityV1 { get throws { try .init(kind: .roundSession, id: session.sessionID) } }
    var concurrencyIdentity: WorkspaceEntityIdentityV1 { get throws { try .init(kind: .roundSession, id: session.sessionID) } }
    func validate() throws { _ = try Self(workspaceID: workspaceID, expectedRevision: expectedRevision, mutationID: mutationID, session: session) }
    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }
    private enum CodingKeys: String, CodingKey, CaseIterable { case workspaceID, expectedRevision, mutationID, session }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), expectedRevision: c.decode(UInt64.self, forKey: .expectedRevision), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), session: c.decode(RoundSessionV1.self, forKey: .session))
    }
}

/// The C08 lifecycle has one canonical writer route.  Import rows are never
/// independently saved: each request carries exactly one bounded operation,
/// its caller supplied mutation identity, and the revision scope that fences
/// the affected durable row.
enum ImportBulkWorkspaceOperationV1: Codable, Equatable, Sendable {
    case upsertMappingProfile(profile: ImportMappingProfileV1, expectedProfileSHA256: String?)
    case advanceSession(session: BulkSessionV1, expectedSessionSHA256: String?)
    case appendReceipt(BulkCommitReceiptV1)

    var workspaceID: WorkspaceID {
        switch self {
        case let .upsertMappingProfile(profile, _): profile.workspaceID
        case let .advanceSession(session, _): session.workspaceID
        case let .appendReceipt(value): value.workspaceID
        }
    }

    var affectedIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .upsertMappingProfile(profile, _):
                try .init(kind: .importMappingProfile, id: profile.profileID)
            case let .advanceSession(session, _):
                try .init(kind: .bulkSession, id: session.sessionID)
            case let .appendReceipt(value):
                try .init(kind: .bulkCommitReceipt, id: value.receiptID)
            }
        }
    }
}

struct ImportBulkWorkspaceMutationV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: UInt64
    let mutationID: MutationIDV1
    let operation: ImportBulkWorkspaceOperationV1

    init(
        workspaceID: WorkspaceID,
        expectedRevision: UInt64,
        mutationID: MutationIDV1,
        operation: ImportBulkWorkspaceOperationV1
    ) throws {
        guard workspaceID == operation.workspaceID, expectedRevision < UInt64.max else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        switch operation {
        case let .upsertMappingProfile(profile, expectedProfileSHA256):
            try profile.validate()
            try expectedProfileSHA256.map(ImportBulkCanonicalCodecV1.requireDigest)
        case let .advanceSession(session, expectedSessionSHA256):
            try session.validate()
            try expectedSessionSHA256.map(ImportBulkCanonicalCodecV1.requireDigest)
        case let .appendReceipt(receipt):
            try receipt.validate()
        }
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.mutationID = mutationID
        self.operation = operation
    }

    var affectedIdentity: WorkspaceEntityIdentityV1 { get throws { try operation.affectedIdentity } }
    var concurrencyIdentity: WorkspaceEntityIdentityV1 { get throws { try operation.affectedIdentity } }
    func validate() throws {
        _ = try Self(workspaceID: workspaceID, expectedRevision: expectedRevision, mutationID: mutationID, operation: operation)
    }
}

enum WorkspaceCommandV1: Codable, Equatable, Sendable {
    case createFirstSign(FirstSignMutationV1)
    case createCheckDraft(CheckDraftMutationV1)
    case acceptCheckEvidence(CheckEvidenceMutationV1)
    case updateSiteTimeZone(SiteTimeZoneMutationV1)
    case deleteAsset(DeleteAssetMutationV1)
    case deleteSite(DeleteSiteMutationV1)
    case eraseWorkspace(EraseWorkspaceMutationV1)
    case finalizeCheck(FinalizeCheckMutationV1)
    case finalizeCorrection(FinalizeCorrectionMutationV1)
    case recordWork(RecordWorkMutationV1)
    case restoreWorkspace(RestoreWorkspaceMutationV1)
    case archiveEntities(ArchiveEntitiesMutationV1)
    case applyLocationHierarchyChange(LocationHierarchyMutationV1)
    case applyAssetPlacementChange(AssetPlacementChangePlanV1)
    case applyAssetCompositionChange(AssetCompositionChangePlanV1)
    case applySavedSmartView(SavedSmartViewMutationV1)
    case applyRequirementAssurance(RequirementAssuranceMutationV1)
    case applyPartyAccountability(PartyAccountabilityMutationV1)
    case applyAssetSemantics(AssetSemanticsMutationV1)
    case applyAuthorityCriterion(AuthorityCriterionMutationV1)
    case applyFunctionalRelationship(FunctionalRelationshipMutationV1)
    case applyEvidenceAssurance(EvidenceAssuranceMutationV1)
    case applyInspectionReview(InspectionReviewMutationV1)
    case applyWorkPacket(WorkPacketMutationV1)
    case applyFieldDraft(FieldDraftMutationV1)
    case applyPackagePromotion(PackagePromotionMutationV1)
    case applyMeasurementIntegrity(MeasurementIntegrityMutationV1)
    case applyPrivacyTransform(PrivacyTransformMutationV1)
    case applyEvidenceMetadata(EvidenceMetadataMutationV1)
    case applyClientCapability(ClientCapabilityMutationV1)
    case applyFieldReference(FieldReferenceMutationV1)
    case applyAccessibleDocumentAssessment(AccessibleDocumentMutationV1)
    case applySurveyDefinition(SurveyDefinitionMutationV1)
    case applySurveySession(SurveySessionMutationV1)
    case applyAssetLocator(AssetLocatorMutationV1)
    case applySchedule(ScheduleMutationV1)
    case applyPlan(PlanMutationV1)
    case applyPlacementPose(PlacementPoseMutationV1)
    case applyEvidenceContext(EvidenceContextWriteOperationV1)
    case applyLighting(LightingWriteOperationV1)
    case applyAssistanceAcceptance(AssistanceAcceptanceRequestV1)
    case applyTemporalEvidence(TemporalEvidenceMutationV1)
    case applyAssetLabel(AssetLabelMutationV1)
    case applyOperationalContact(OperationalContactMutationV1)
    case applyActivityContract(ActivityContractMutationV2)
    case applyPortableReview(PortableReviewMutationV1)
    case applyWorkResource(WorkResourceMutationV1)
    case applyPartsStock(PartsStockMutationV1)
    case applyMyDay(MyDayMutationV1)
    case applyServiceRequest(ServiceRequestMutationV1)
    case applyServiceReliability(ServiceReliabilityAtomicBundleV1)
    case applyShopReportProfile(ShopReportProfileMutationV1)
    case applyRoundSession(RoundSessionMutationV1)
    case applyImportBulk(ImportBulkWorkspaceMutationV1)
    case applyEvidenceQuality(EvidenceQualityMutationCommandV1)

    var kind: WorkspaceCommandKindV1 {
        switch self {
        case .createFirstSign: .createFirstSign
        case .createCheckDraft: .createCheckDraft
        case .acceptCheckEvidence: .acceptCheckEvidence
        case .updateSiteTimeZone: .updateSiteTimeZone
        case .deleteAsset: .deleteAsset
        case .deleteSite: .deleteSite
        case .eraseWorkspace: .eraseWorkspace
        case .finalizeCheck: .finalizeCheck
        case .finalizeCorrection: .finalizeCorrection
        case .recordWork: .recordWork
        case .restoreWorkspace: .restoreWorkspace
        case .archiveEntities: .archiveEntities
        case .applyLocationHierarchyChange: .applyLocationHierarchyChange
        case .applyAssetPlacementChange: .applyAssetPlacementChange
        case .applyAssetCompositionChange: .applyAssetCompositionChange
        case .applySavedSmartView: .applySavedSmartView
        case .applyRequirementAssurance: .applyRequirementAssurance
        case .applyPartyAccountability: .applyPartyAccountability
        case .applyAssetSemantics: .applyAssetSemantics
        case .applyAuthorityCriterion: .applyAuthorityCriterion
        case .applyFunctionalRelationship: .applyFunctionalRelationship
        case .applyEvidenceAssurance: .applyEvidenceAssurance
        case .applyInspectionReview:.applyInspectionReview
        case .applyWorkPacket:.applyWorkPacket
        case .applyFieldDraft:.applyFieldDraft
        case .applyPackagePromotion:.applyPackagePromotion
        case .applyMeasurementIntegrity:.applyMeasurementIntegrity
        case .applyPrivacyTransform:.applyPrivacyTransform
        case .applyEvidenceMetadata:.applyEvidenceMetadata
        case .applyClientCapability:.applyClientCapability
        case .applyFieldReference:.applyFieldReference
        case .applyAccessibleDocumentAssessment:.applyAccessibleDocumentAssessment
        case .applySurveyDefinition:.applySurveyDefinition
        case .applySurveySession:.applySurveySession
        case .applyAssetLocator:.applyAssetLocator
        case .applySchedule:.applySchedule
        case .applyPlan:.applyPlan
        case .applyPlacementPose:.applyPlacementPose
        case .applyEvidenceContext:.applyEvidenceContext
        case .applyLighting:.applyLighting
        case .applyAssistanceAcceptance:.applyAssistanceAcceptance
        case .applyTemporalEvidence:.applyTemporalEvidence
        case .applyAssetLabel:.applyAssetLabel
        case .applyOperationalContact:.applyOperationalContact
        case .applyActivityContract:.applyActivityContract
        case .applyPortableReview:.applyPortableReview
        case .applyWorkResource:.applyWorkResource
        case .applyPartsStock:.applyPartsStock
        case .applyMyDay:.applyMyDay
        case .applyServiceRequest:.applyServiceRequest
        case .applyServiceReliability:.applyServiceReliability
        case .applyShopReportProfile:.applyShopReportProfile
        case .applyRoundSession:.applyRoundSession
        case .applyImportBulk: .applyImportBulk
        case .applyEvidenceQuality: .applyEvidenceQuality
        }
    }
}

enum WorkspaceCommandKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case createFirstSign = "create_first_sign"
    case createCheckDraft = "begin_check_draft"
    case acceptCheckEvidence = "capture_evidence"
    case updateSiteTimeZone = "confirm_site_timezone"
    case deleteAsset = "delete_asset"
    case deleteSite = "delete_site"
    case eraseWorkspace = "erase_workspace"
    case finalizeCheck = "finalize_check"
    case finalizeCorrection = "finalize_correction"
    case recordWork = "record_work"
    case restoreWorkspace = "restore_workspace"
    case archiveEntities = "archive_entities_preview_compensation"
    case applyLocationHierarchyChange = "apply_location_hierarchy_change"
    case applyAssetPlacementChange = "apply_asset_placement_change"
    case applyAssetCompositionChange = "apply_asset_composition_change"
    case applySavedSmartView = "apply_saved_smart_view"
    case applyRequirementAssurance = "apply_requirement_assurance"
    case applyPartyAccountability = "apply_party_accountability"
    case applyAssetSemantics = "apply_asset_semantics"
    case applyAuthorityCriterion = "apply_authority_criterion"
    case applyFunctionalRelationship = "apply_functional_relationship"
    case applyEvidenceAssurance = "apply_evidence_assurance"
    case applyInspectionReview="apply_inspection_review"
    case applyWorkPacket="apply_work_packet"
    case applyFieldDraft="apply_field_draft"
    case applyPackagePromotion="apply_package_promotion"
    case applyMeasurementIntegrity="apply_measurement_integrity"
    case applyPrivacyTransform="apply_privacy_transform"
    case applyEvidenceMetadata="apply_evidence_metadata_v1"
    case applyClientCapability="apply_client_capability"
    case applyFieldReference="apply_field_reference"
    case applyAccessibleDocumentAssessment="apply_accessible_document_assessment"
    case applySurveyDefinition="apply_survey_definition"
    case applySurveySession="apply_survey_session"
    case applyAssetLocator="apply_asset_locator"
    case applySchedule="apply_schedule"
    case applyPlan="apply_plan"
    case applyPlacementPose="apply_placement_pose"
    case applyEvidenceContext="apply_evidence_context"
    case applyLighting="apply_lighting"
    case applyAssistanceAcceptance="apply_assistance_acceptance"
    case applyTemporalEvidence="apply_temporal_evidence"
    case applyAssetLabel="apply_asset_label"
    case applyOperationalContact="apply_operational_contact"
    case applyActivityContract="apply_activity_contract_v2"
    case applyPortableReview="apply_portable_review_v1"
    case applyWorkResource="apply_work_resource_v1"
    case applyPartsStock="apply_parts_stock_v1"
    case applyMyDay="apply_my_day_v1"
    case applyServiceRequest="apply_service_request_v1"
    case applyServiceReliability="apply_service_reliability_v1"
    case applyShopReportProfile="apply_shop_report_profile_v1"
    case applyRoundSession="apply_round_session_v1"
    case applyImportBulk="apply_import_bulk_v1"
    case applyEvidenceQuality="apply_evidence_quality_v1"
}

extension EvidenceQualityMutationCommandV1 {
    /// One immutable C10 event maps to one family-qualified writer target.
    /// The journal receipt is intentionally not an independent target/store.
    func affectedIdentityForCanonicalWriter() throws -> WorkspaceEntityIdentityV1 {
        try validate()
        switch payload {
        case let .putRuleSet(value):
            return try .init(kind: .evidenceQualityRuleSet, id: value.ruleSetID)
        case let .recordAssessment(value):
            return try .init(kind: .evidenceQualityAssessment, id: value.assessmentID)
        case let .recordWaiver(value):
            return try .init(kind: .evidenceQualityWaiverEvent, id: value.waiverEventID)
        }
    }
}

extension WorkspaceCommandV1 {
    func canonicalLocationAffectedIdentities() throws -> [WorkspaceEntityIdentityV1]? {
        let values: [WorkspaceEntityIdentityV1]
        switch self {
        case let .applyLocationHierarchyChange(value):
            let nodeIDs = Set(value.plan.beforeNodes.map(\.id)).union(value.plan.afterNodes.map(\.id))
            var result = try nodeIDs.map { try WorkspaceEntityIdentityV1(kind: .locationNode, id: $0) }
            for placement in value.placementChanges {
                result.append(try .init(kind: .asset, id: placement.basis.assetID))
                result.append(try .init(kind: .assetPlacementEvent, id: placement.newEventID))
                result += try placement.poseEvents.map { try .init(kind: .assetPoseEvent, id: $0.eventID) }
            }
            values = result
        case let .applyAssetPlacementChange(plan):
            values = try [.init(kind: .asset, id: plan.basis.assetID), .init(kind: .assetPlacementEvent, id: plan.newEventID)]
                + plan.poseEvents.map { try .init(kind: .assetPoseEvent, id: $0.eventID) }
        case let .applyAssetCompositionChange(plan):
            values = try [.init(kind: .assetCompositionEdge, id: plan.event.edge.id), .init(kind: .assetCompositionEvent, id: plan.event.id)]
        default:
            return nil
        }
        let ordered = values.sorted { $0.stableKey < $1.stableKey }
        guard ordered.count <= MutationReceiptV1.maximumPostImageCount,
              Set(ordered).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return ordered
    }
}

extension AssetPlacementChangePlanV1 {
    var placementPoseMutation: PlacementPoseMutationV1? {
        get throws {
            guard !poseEvents.isEmpty else { return nil }
            guard let poseAdmissionClosure else{throw WorkspaceMutationContractFailureV1.invalidPlan}
            return try PlacementPoseMutationV1(
                workspaceID: basis.workspaceID,
                mutationID: mutationID,
                events: poseEvents,
                eventPredecessors: poseEventPredecessors.map(Optional.some),
                admissionClosure:poseAdmissionClosure
            )
        }
    }
}

extension LocationHierarchyMutationV1 {
    var placementPoseMutation: PlacementPoseMutationV1? {
        get throws {
            let events=placementChanges.flatMap(\.poseEvents)
            guard !events.isEmpty else{return nil}
            let closures=placementChanges.compactMap(\.poseAdmissionClosure)
            guard closures.count==placementChanges.filter({!$0.poseEvents.isEmpty}).count else{throw WorkspaceMutationContractFailureV1.invalidPlan}
            let admissionClosure=try PlacementPoseAdmissionClosureV1.merging(closures)
            return try PlacementPoseMutationV1(
                workspaceID:plan.workspaceID,
                mutationID:MutationIDV1(rawValue:plan.operationID),
                events:events,
                eventPredecessors:placementChanges.flatMap(\.poseEventPredecessors).map(Optional.some),
                admissionClosure:admissionClosure
            )
        }
    }
}

struct WorkspaceMutationRequestV1: Codable, Equatable, Sendable {
    let mutationID: MutationIDV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let command: WorkspaceCommandV1
}

struct OwnedStorageAttemptIDV1: Hashable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let mutationID: MutationIDV1

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        mutationID: MutationIDV1
    ) throws {
        guard workspaceID.rawValue != Self.zero,
              generationID != Self.zero else {
            throw WorkspaceMutationContractFailureV1.invalidID
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.mutationID = mutationID
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

struct OwnedStorageVolumeIdentityV1: Equatable, Hashable, Sendable {
    let device: UInt64
}

struct OwnedStorageReservationV1: Equatable, Sendable {
    let attemptID: OwnedStorageAttemptIDV1
    let requiredBytes: Int64
    let volumeIdentity: OwnedStorageVolumeIdentityV1
}

protocol WorkspaceStorageAdmissionPortV1: AnyObject {
    func reserve(
        attemptID: OwnedStorageAttemptIDV1,
        requiredBytes: Int64
    ) throws -> OwnedStorageReservationV1
    func release(reservation: OwnedStorageReservationV1)
}

enum WorkspaceStorageEstimateV1 {
    /// Bounded allowance for the journal, SQLite pages and sidecars written by
    /// one canonical transaction. Existing feature-specific preflight
    /// estimates remain unchanged and additive.
    static let canonicalMutationAllowanceBytes: Int64 = 1_048_576

    static func requiredBytes(for command: WorkspaceCommandV1) throws -> Int64 {
        var required = canonicalMutationAllowanceBytes
        if case let .acceptCheckEvidence(value) = command {
            guard value.byteCount >= 0, value.thumbnailByteCount >= 0 else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            let (content, contentOverflow) = Int64(value.byteCount)
                .addingReportingOverflow(Int64(value.thumbnailByteCount))
            let (total, totalOverflow) = required.addingReportingOverflow(content)
            guard !contentOverflow, !totalOverflow, total >= 0 else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            required = total
        }
        return required
    }
}

struct WorkspaceMutationEffectV1: Codable, Equatable, Sendable {
    let affectedEntities: [WorkspaceEntityIdentityV1]
    let temporaryRelativePath: String

    init(affectedEntities: [WorkspaceEntityIdentityV1], temporaryRelativePath: String) throws {
        let ordered = affectedEntities.sorted { $0.stableKey < $1.stableKey }
        guard Set(ordered).count == ordered.count,
              !temporaryRelativePath.isEmpty,
              !temporaryRelativePath.hasPrefix("/"),
              !temporaryRelativePath.contains("..") else {
            throw WorkspaceMutationContractFailureV1.invalidEffect
        }
        self.affectedEntities = ordered
        self.temporaryRelativePath = temporaryRelativePath
    }
}

/// Process-local evidence only. C02 owns durable mutation receipts.
struct WorkspaceMutationOutcomeV1: Equatable, Sendable {
    let mutationID: MutationIDV1
    let commandDigest: String
    let occurredAt: Date
    let before: WorkspaceRevisionV1
    let after: WorkspaceRevisionV1
    let effect: WorkspaceMutationEffectV1
}

enum WorkspaceMutationFailureV1: Error, Equatable {
    case writerInvalidated
    case wrongWriterInstance
    case wrongWorkspace
    case wrongGeneration
    case staleWorkspaceRevision
    case staleEntityRevision(WorkspaceEntityIdentityV1)
    case mutationIDQuarantined
    case idempotencyCapacityReached
    case revisionOverflow
    case unsupportedCommand
    case invalidCommand
    case invalidEnvelope
    case invalidReceipt
    case invalidReversal
    case receiptHistoryCorrupt
    case sequenceCollision
    case storageAdmissionFailed
    case persistenceFailed
}

enum WorkspaceMutationContractFailureV1: Error, Equatable {
    case invalidID
    case duplicateEntityRevision
    case invalidEffect
    case invalidPlan
}

@MainActor
protocol WorkspaceQueryClientV1: AnyObject {
    func currentRevision() throws -> WorkspaceRevisionV1
    func query(
        _ request: WorkspacePackageLifecycleQueryRequestV1
    ) throws -> WorkspacePackageLifecycleQueryResultV1
}

enum WorkspacePackageLifecycleOperationV1: String, Codable, CaseIterable, Sendable {
    case acknowledge = "ACKNOWLEDGE"
    case archive = "ARCHIVE"
    case backup = "BACKUP"
    case capture = "CAPTURE"
    case complete = "COMPLETE"
    case delete = "DELETE"
    case erase = "ERASE"
    case exportOpen = "EXPORT_OPEN"
    case finalize = "FINALIZE"
    case query = "QUERY"
    case recover = "RECOVER"
    case reportPDF = "REPORT_PDF"
    case restore = "RESTORE"
}

struct PackageReleaseIdentityV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let packageID: String
    let schemaVersion: Int
    let contentVersion: Int

    init(packageID: String, schemaVersion: Int, contentVersion: Int) throws {
        guard !packageID.isEmpty,
              packageID == packageID.trimmingCharacters(in: .whitespacesAndNewlines),
              schemaVersion > 0, contentVersion > 0 else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.packageID = packageID
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
    }

    init(package: SignPack) throws {
        try self.init(
            packageID: package.packID,
            schemaVersion: package.schemaVersion,
            contentVersion: package.contentVersion
        )
    }

    func matches(_ package: SignPack) -> Bool {
        packageID == package.packID
            && schemaVersion == package.schemaVersion
            && contentVersion == package.contentVersion
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.packageID != rhs.packageID { return lhs.packageID < rhs.packageID }
        if lhs.schemaVersion != rhs.schemaVersion { return lhs.schemaVersion < rhs.schemaVersion }
        return lhs.contentVersion < rhs.contentVersion
    }
}

enum WorkspacePackageOutcomeRoleV1: String, Codable, CaseIterable, Hashable, Sendable {
    case noFinding = "NO_FINDING"
    case findingObserved = "FINDING_OBSERVED"
    case couldNotVerify = "COULD_NOT_VERIFY"
    case resolved = "RESOLVED"
    case findingStillPresent = "FINDING_STILL_PRESENT"
    case originalResolvedDifferentFinding = "ORIGINAL_RESOLVED_DIFFERENT_FINDING"
    case workRecorded = "WORK_RECORDED"
}

struct WorkspacePackageOutcomeProfileV1: Equatable, Sendable {
    let key: String
    let display: String
    let role: WorkspacePackageOutcomeRoleV1

    init(key: String, display: String, role: WorkspacePackageOutcomeRoleV1) throws {
        guard !key.isEmpty, key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              !display.isEmpty, display == display.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.key = key
        self.display = display
        self.role = role
    }
}

enum WorkspacePackageEvidenceRoleV1: String, Codable, CaseIterable, Hashable, Sendable {
    case captureRequired = "CAPTURE_REQUIRED"
    case captureSupplementary = "CAPTURE_SUPPLEMENTARY"
    case workSupplementary = "WORK_SUPPLEMENTARY"
}

struct WorkspacePackageEvidenceProfileV1: Equatable, Sendable {
    let key: String
    let role: WorkspacePackageEvidenceRoleV1

    init(key: String, role: WorkspacePackageEvidenceRoleV1) throws {
        guard !key.isEmpty, key == key.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.key = key
        self.role = role
    }
}

struct WorkspacePackageStageProfileV1: Equatable, Sendable {
    let stageKey: String
    let stageDisplay: String
    let outcomes: [WorkspacePackageOutcomeProfileV1]

    var outcomeKeys: [String] { outcomes.map(\.key) }

    init(
        stageKey: String,
        stageDisplay: String,
        outcomes: [WorkspacePackageOutcomeProfileV1]
    ) throws {
        guard !stageKey.isEmpty, !outcomes.isEmpty,
              Set(outcomes.map(\.key)).count == outcomes.count,
              Set(outcomes.map(\.role)).count == outcomes.count,
              outcomes.allSatisfy({ !$0.key.isEmpty }),
              stageKey == stageKey.trimmingCharacters(in: .whitespacesAndNewlines),
              !stageDisplay.isEmpty,
              stageDisplay == stageDisplay.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.stageKey = stageKey
        self.stageDisplay = stageDisplay
        self.outcomes = outcomes
    }
}

struct WorkspacePackageLifecycleProfileV1: Equatable, Sendable {
    let package: SignPack
    let release: PackageReleaseIdentityV1
    let stages: [WorkspacePackageStageProfileV1]
    let evidencePurposes: [WorkspacePackageEvidenceProfileV1]
    let requiredAcknowledgementKeys: [String]
    let pdfTemplate: PDFTemplateReferenceV1

    init(
        package: SignPack,
        release: PackageReleaseIdentityV1,
        stages: [WorkspacePackageStageProfileV1],
        evidencePurposes: [WorkspacePackageEvidenceProfileV1],
        requiredAcknowledgementKeys: [String],
        pdfTemplate: PDFTemplateReferenceV1
    ) throws {
        let packageStages = package.stageDisplays
        let packageOutcomes = package.outcomeDisplays
        let packagePurposeKeys = package.evidencePurposes.map(\.key)
        let profileOutcomes = stages.flatMap(\.outcomes)
        let packageStageProfiles = stages.filter { profile in
            packageStages.contains {
                $0.key == profile.stageKey && $0.display == profile.stageDisplay
            }
        }
        let supplementalStages = stages.filter { !packageStageProfiles.contains($0) }
        let packageOutcomeProfiles = packageStageProfiles.flatMap(\.outcomes)
        let profilePurposeKeys = evidencePurposes.map(\.key)
        let supportsWork = evidencePurposes.contains { $0.role == .workSupplementary }
        let declaredOutcomeKeys = Set(packageOutcomes.map(\.key))
        let packageOutcomesAreCovered = declaredOutcomeKeys.isSubset(
            of: Set(packageOutcomeProfiles.map(\.key))
        )
        let packageOutcomeMappingsAreExact = packageOutcomeProfiles.allSatisfy { profile in
            packageOutcomes.contains { $0.key == profile.key && $0.display == profile.display }
        }
        let repeatedOutcomeMappingsAreConsistent = Dictionary(
            grouping: packageOutcomeProfiles,
            by: \.key
        ).values.allSatisfy { values in
            Set(values.map(\.role)).count == 1 && Set(values.map(\.display)).count == 1
        }
        guard release.matches(package),
              packageStageProfiles.map({ "\($0.stageKey)\u{0}\($0.stageDisplay)" })
                == packageStages.map({ "\($0.key)\u{0}\($0.display)" }),
              Set(stages.map(\.stageKey)).count == stages.count,
              packageOutcomesAreCovered,
              packageOutcomeMappingsAreExact,
              repeatedOutcomeMappingsAreConsistent,
              supplementalStages.count == (supportsWork ? 1 : 0),
              supplementalStages.first.map({ $0.outcomes.count == 1 && $0.outcomes[0].role == .workRecorded }) ?? !supportsWork,
              supplementalStages.allSatisfy({ supplemental in
                  !packageStages.contains(where: {
                      $0.key == supplemental.stageKey || $0.display == supplemental.stageDisplay
                  }) && supplemental.outcomes.allSatisfy({ outcome in
                      !packageOutcomes.contains(where: {
                          $0.key == outcome.key || $0.display == outcome.display
                      })
                  })
              }),
              evidencePurposes.contains(where: { $0.role == .captureRequired }),
              profilePurposeKeys == packagePurposeKeys,
              Set(profilePurposeKeys).count == profilePurposeKeys.count,
              Set(requiredAcknowledgementKeys).count == requiredAcknowledgementKeys.count,
              requiredAcknowledgementKeys == package.acknowledgements.map(\.key),
              !pdfTemplate.id.isEmpty, pdfTemplate.version > 0 else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.package = package
        self.release = release
        self.stages = stages
        self.evidencePurposes = evidencePurposes
        self.requiredAcknowledgementKeys = requiredAcknowledgementKeys
        self.pdfTemplate = pdfTemplate
    }

    func stage(_ key: String) throws -> WorkspacePackageStageProfileV1 {
        guard let value = stages.first(where: { $0.stageKey == key }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return value
    }

    func evidencePurposes(
        for role: WorkspacePackageEvidenceRoleV1
    ) -> [WorkspacePackageEvidenceProfileV1] {
        evidencePurposes.filter { $0.role == role }
    }

    func evidencePurposeKeys(for role: WorkspacePackageEvidenceRoleV1) -> [String] {
        evidencePurposes(for: role).map(\.key)
    }
}

struct WorkspacePackageLifecycleProfileRegistryV1: Sendable {
    private let profiles: [WorkspacePackageLifecycleProfileV1]

    init(profiles: [WorkspacePackageLifecycleProfileV1]) throws {
        let ordered = profiles.sorted { $0.release < $1.release }
        guard !ordered.isEmpty,
              Set(ordered.map(\.release)).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.profiles = ordered
    }

    func resolve(
        _ release: PackageReleaseIdentityV1
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        guard let value = profiles.first(where: { $0.release == release }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return value
    }
}

enum WorkspacePackageLifecycleCompatibilityV1 {
    static let expiration = "AFTER_ACCEPTED_S10_6_RECONCILIATION"

    static func legacyV3Profile(
        package: SignPack
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        let baseOutcomeRoles: [String: WorkspacePackageOutcomeRoleV1] = [
            "no_visible_issue": .noFinding,
            "visible_issue": .findingObserved,
            "could_not_verify": .couldNotVerify,
        ]
        let recheckOutcomeRoles: [String: WorkspacePackageOutcomeRoleV1] = [
            "resolved": .resolved,
            "issue_still_visible": .findingStillPresent,
            "original_resolved_different_issue": .originalResolvedDifferentFinding,
        ]
        let purposeRoles: [String: WorkspacePackageEvidenceRoleV1] = [
            "wide_context": .captureRequired,
            "close_detail": .captureRequired,
            "work_context": .workSupplementary,
        ]
        let stageKeys = package.stageDisplays.map(\.key)
        let outcomeKeys = package.outcomeDisplays.map(\.key)
        let purposeKeys = package.evidencePurposes.map(\.key)
        let acknowledgementKeys = package.acknowledgements.map(\.key)
        let baseOutcomeKeys = Set(baseOutcomeRoles.keys)
        let completeOutcomeKeys = baseOutcomeKeys.union(recheckOutcomeRoles.keys)
        let hasRecheckOutcomes = Set(outcomeKeys) == completeOutcomeKeys
        let hasWorkPurpose = purposeKeys.contains("work_context")
        guard legacyPackageStructureIsValid(package),
              Set(stageKeys) == Set(["check"]) || Set(stageKeys) == Set(["check", "recheck"]),
              Set(stageKeys).count == stageKeys.count,
              Set(outcomeKeys) == baseOutcomeKeys || hasRecheckOutcomes,
              !hasRecheckOutcomes || stageKeys.contains("recheck"),
              Set(purposeKeys) == Set(["wide_context", "close_detail"])
                || Set(purposeKeys) == Set(["wide_context", "close_detail", "work_context"]),
              Set(acknowledgementKeys) == Set(["safe_authorized_position"])
                || Set(acknowledgementKeys) == Set(["after_dark", "safe_authorized_position"]) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        let outcomesByKey = Dictionary(
            uniqueKeysWithValues: package.outcomeDisplays.map { ($0.key, $0) }
        )
        func outcome(
            _ key: String,
            role: WorkspacePackageOutcomeRoleV1
        ) throws -> WorkspacePackageOutcomeProfileV1 {
            guard let entry = outcomesByKey[key] else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return try WorkspacePackageOutcomeProfileV1(
                key: entry.key,
                display: entry.display,
                role: role
            )
        }
        var stages: [WorkspacePackageStageProfileV1] = []
        for entry in package.stageDisplays {
            let mappings: [(String, WorkspacePackageOutcomeRoleV1)]
            switch entry.key {
            case "check":
                mappings = [
                    ("no_visible_issue", .noFinding),
                    ("visible_issue", .findingObserved),
                    ("could_not_verify", .couldNotVerify),
                ]
            case "recheck" where hasRecheckOutcomes:
                mappings = [
                    ("could_not_verify", .couldNotVerify),
                    ("resolved", .resolved),
                    ("issue_still_visible", .findingStillPresent),
                    ("original_resolved_different_issue", .originalResolvedDifferentFinding),
                ]
            case "recheck":
                mappings = [
                    ("no_visible_issue", .noFinding),
                    ("visible_issue", .findingObserved),
                    ("could_not_verify", .couldNotVerify),
                ]
            default:
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            stages.append(try WorkspacePackageStageProfileV1(
                stageKey: entry.key,
                stageDisplay: entry.display,
                outcomes: try mappings.map { try outcome($0.0, role: $0.1) }
            ))
        }
        if hasWorkPurpose {
            stages.append(try WorkspacePackageStageProfileV1(
                stageKey: "work",
                stageDisplay: "Work",
                outcomes: [
                    try WorkspacePackageOutcomeProfileV1(
                        key: "work_recorded",
                        display: "Work recorded",
                        role: .workRecorded
                    ),
                ]
            ))
        }
        return try WorkspacePackageLifecycleProfileV1(
            package: package,
            release: PackageReleaseIdentityV1(package: package),
            stages: stages,
            evidencePurposes: try package.evidencePurposes.map { purpose in
                guard let role = purposeRoles[purpose.key] else {
                    throw WorkspaceMutationContractFailureV1.invalidPlan
                }
                return try WorkspacePackageEvidenceProfileV1(key: purpose.key, role: role)
            },
            requiredAcknowledgementKeys: acknowledgementKeys,
            pdfTemplate: PDFTemplateReferenceV1(
                id: "field.evidence.pdf.worklight.v1",
                version: 1
            )
        )
    }

    static func legacyV3Registry(
        package: SignPack
    ) throws -> WorkspacePackageLifecycleProfileRegistryV1 {
        try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: [legacyV3Profile(package: package)]
        )
    }

    static func shippingProfile() throws -> WorkspacePackageLifecycleProfileV1 {
        try legacyV3Profile(package: .illuminatedSignV1)
    }

    static func shippingRegistry() throws -> WorkspacePackageLifecycleProfileRegistryV1 {
        try WorkspacePackageLifecycleProfileRegistryV1(profiles: [shippingProfile()])
    }

    private static func legacyPackageStructureIsValid(_ package: SignPack) -> Bool {
        func valid(_ value: String) -> Bool {
            !value.isEmpty
                && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && value.unicodeScalars.allSatisfy {
                    !CharacterSet.controlCharacters.contains($0) || $0.value == 10
                }
        }
        func unique(_ values: [String]) -> Bool {
            Set(values).count == values.count
        }
        let registries = [
            package.stageDisplays,
            package.outcomeDisplays,
            package.issueLabels,
            package.couldNotVerifyReasons.entries,
        ]
        return package.schemaVersion > 0
            && package.contentVersion > 0
            && valid(package.packID)
            && valid(package.nouns.asset.singular)
            && valid(package.nouns.asset.plural)
            && valid(package.nouns.check.singular)
            && valid(package.nouns.check.plural)
            && valid(package.nouns.issue.singular)
            && valid(package.nouns.issue.plural)
            && valid(package.couldNotVerifyReasons.version)
            && valid(package.disclaimer)
            && registries.allSatisfy { entries in
                !entries.isEmpty
                    && unique(entries.map(\.key))
                    && entries.allSatisfy { valid($0.key) && valid($0.display) }
            }
            && !package.evidencePurposes.isEmpty
            && unique(package.evidencePurposes.map(\.key))
            && package.evidencePurposes.allSatisfy {
                valid($0.key) && valid($0.display) && valid($0.instruction)
            }
            && !package.acknowledgements.isEmpty
            && unique(package.acknowledgements.map(\.key))
            && package.acknowledgements.allSatisfy {
                valid($0.key) && valid($0.copy) && valid($0.version)
            }
    }
}

struct WorkspacePackageLifecycleQueryRequestV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let operation: WorkspacePackageLifecycleOperationV1
    let identities: [WorkspaceEntityIdentityV1]

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        operation: WorkspacePackageLifecycleOperationV1,
        identities: [WorkspaceEntityIdentityV1]
    ) throws {
        let ordered = identities.sorted { $0.stableKey < $1.stableKey }
        guard generationID != Self.zero,
              identities.count <= 256,
              Set(ordered).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.operation = operation
        self.identities = ordered
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

struct WorkspacePackageBindingV1: Equatable, Sendable {
    let assetID: UUID
    let packageID: String
    let packageSchemaVersion: Int
    let packageContentVersion: Int
}

struct WorkspacePackageLifecycleQueryResultV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let operation: WorkspacePackageLifecycleOperationV1
    let revision: WorkspaceRevisionV1
    let existingIdentities: [WorkspaceEntityIdentityV1]
    let packageBindings: [WorkspacePackageBindingV1]

    init(
        request: WorkspacePackageLifecycleQueryRequestV1,
        revision: WorkspaceRevisionV1,
        existingIdentities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    ) throws {
        let identities = existingIdentities.sorted { $0.stableKey < $1.stableKey }
        let bindings = packageBindings.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
        let existingAssetIDs = Set(identities.compactMap {
            $0.kind == .asset ? $0.id : nil
        })
        guard revision.workspaceID == request.workspaceID,
              revision.generationID == request.generationID,
              Set(identities).count == identities.count,
              Set(identities).isSubset(of: Set(request.identities)),
              Set(bindings.map(\.assetID)).count == bindings.count,
              bindings.allSatisfy({
                  existingAssetIDs.contains($0.assetID)
                    && !$0.packageID.isEmpty
                    && $0.packageID == $0.packageID.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.packageSchemaVersion > 0
                    && $0.packageContentVersion > 0
              }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        workspaceID = request.workspaceID
        generationID = request.generationID
        operation = request.operation
        self.revision = revision
        self.existingIdentities = identities
        self.packageBindings = bindings
    }
}

@MainActor
struct WorkspacePackageLifecycleDependenciesV1 {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let generationRootURL: URL
    let writer: WorkspaceWriterV1
    let queryClient: any WorkspaceQueryClientV1
    let clock: any ApplicationClock
    let idSource: any ApplicationIDSource
    let fileAuthority: any ApplicationFileAuthorityV1
    let profileRegistry: WorkspacePackageLifecycleProfileRegistryV1

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        generationRootURL: URL,
        writer: WorkspaceWriterV1,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1
    ) throws {
        let revision = try writer.currentRevision()
        guard revision.workspaceID == workspaceID,
              revision.generationID == generationID,
              generationRootURL.isFileURL else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.writer = writer
        queryClient = writer
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.profileRegistry = profileRegistry
    }
}

enum MutationReversalDispositionV1: String, Codable, Sendable {
    case reversible = "REVERSIBLE"
    case compensatable = "COMPENSATABLE"
    case irreversible = "IRREVERSIBLE"
}

struct MutationReversalPolicyV1: Codable, Equatable, Sendable {
    let commandKind: WorkspaceCommandKindV1
    let disposition: MutationReversalDispositionV1
    let stableReason: String
}

enum MutationReversalPolicyRegistryV1 {
    static let version = 1

    static let policies: [MutationReversalPolicyV1] = [
        .init(commandKind: .createFirstSign, disposition: .compensatable, stableReason: "dependency_checked_delete_only"),
        .init(commandKind: .createCheckDraft, disposition: .reversible, stableReason: "archive_unfinalized_draft"),
        .init(commandKind: .acceptCheckEvidence, disposition: .irreversible, stableReason: "immutable_evidence_original"),
        .init(commandKind: .updateSiteTimeZone, disposition: .reversible, stableReason: "restore_prior_timezone_if_unchanged"),
        .init(commandKind: .deleteAsset, disposition: .irreversible, stableReason: "deletion_ledger_and_purged_content"),
        .init(commandKind: .deleteSite, disposition: .irreversible, stableReason: "explicit_site_deletion"),
        .init(commandKind: .eraseWorkspace, disposition: .irreversible, stableReason: "erase_cannot_be_reversed"),
        .init(commandKind: .finalizeCheck, disposition: .irreversible, stableReason: "finalized_artifact_amendment_only"),
        .init(commandKind: .finalizeCorrection, disposition: .irreversible, stableReason: "correction_supersession_only"),
        .init(commandKind: .recordWork, disposition: .irreversible, stableReason: "completed_work_supersession_only"),
        .init(commandKind: .restoreWorkspace, disposition: .irreversible, stableReason: "generation_restore_cannot_be_reversed"),
        .init(commandKind: .archiveEntities, disposition: .compensatable, stableReason: "append_semantic_successor_only"),
        .init(commandKind: .applyLocationHierarchyChange, disposition: .compensatable, stableReason: "append_hierarchy_successor_only"),
        .init(commandKind: .applyAssetPlacementChange, disposition: .compensatable, stableReason: "append_placement_successor_only"),
        .init(commandKind: .applyAssetCompositionChange, disposition: .compensatable, stableReason: "append_composition_successor_only"),
        .init(commandKind: .applySavedSmartView, disposition: .compensatable, stableReason: "replace_or_delete_saved_smart_view"),
        .init(commandKind: .applyRequirementAssurance, disposition: .compensatable, stableReason: "replace_typed_requirement_assurance"),
        .init(commandKind: .applyPartyAccountability, disposition: .compensatable, stableReason: "append_accountability_successor_only"),
        .init(commandKind: .applyAssetSemantics, disposition: .compensatable, stableReason: "append_asset_semantic_pair_only"),
        .init(commandKind: .applyAuthorityCriterion, disposition: .compensatable, stableReason: "append_authority_criterion_successor_only"),
        .init(commandKind: .applyFunctionalRelationship, disposition: .compensatable, stableReason: "append_functional_relationship_successor_only"),
        .init(commandKind: .applyEvidenceAssurance, disposition: .compensatable, stableReason: "append_evidence_assurance_successor_only"),
        .init(commandKind:.applyInspectionReview,disposition:.compensatable,stableReason:"append_review_corrective_successor_only"),
        .init(commandKind:.applyWorkPacket,disposition:.compensatable,stableReason:"append_work_packet_history_only"),
        .init(commandKind:.applyFieldDraft,disposition:.compensatable,stableReason:"append_field_draft_successor_only"),
        .init(commandKind:.applyPackagePromotion,disposition:.compensatable,stableReason:"append_package_promotion_successor_only"),
        .init(commandKind:.applyMeasurementIntegrity,disposition:.compensatable,stableReason:"append_measurement_integrity_successor_only"),
        .init(commandKind:.applyPrivacyTransform,disposition:.irreversible,stableReason:"append_privacy_transform_forward_fix_only"),
        .init(commandKind:.applyEvidenceMetadata,disposition:.compensatable,stableReason:"append_evidence_association_and_sequence_successor_only"),
        .init(commandKind:.applyClientCapability,disposition:.irreversible,stableReason:"append_client_capability_forward_fix_only"),
        .init(commandKind:.applyFieldReference,disposition:.irreversible,stableReason:"append_field_reference_forward_fix_only"),
        .init(commandKind:.applyAccessibleDocumentAssessment,disposition:.irreversible,stableReason:"append_accessible_document_assessment_successor_only"),
        .init(commandKind:.applySurveyDefinition,disposition:.compensatable,stableReason:"append_survey_definition_successor_only"),
        .init(commandKind:.applySurveySession,disposition:.compensatable,stableReason:"append_survey_session_successor_only"),
        .init(commandKind:.applyAssetLocator,disposition:.compensatable,stableReason:"append_asset_locator_successor_only"),
        .init(commandKind:.applySchedule,disposition:.compensatable,stableReason:"append_schedule_successor_only"),
        .init(commandKind:.applyPlan,disposition:.compensatable,stableReason:"append_plan_history_successor_only"),
        .init(commandKind:.applyPlacementPose,disposition:.compensatable,stableReason:"append_pose_history_successor_only"),
        .init(commandKind:.applyEvidenceContext,disposition:.compensatable,stableReason:"append_evidence_context_history_successor_only"),
        .init(commandKind:.applyLighting,disposition:.compensatable,stableReason:"append_lighting_history_successor_only"),
        .init(commandKind:.applyAssistanceAcceptance,disposition:.compensatable,stableReason:"explicit_review_expected_revision_target_mutation"),
        .init(commandKind:.applyTemporalEvidence,disposition:.compensatable,stableReason:"immutable_original_with_governed_successor_or_tombstone_retention"),
        .init(commandKind:.applyAssetLabel,disposition:.compensatable,stableReason:"immutable_accepted_label_snapshot_with_historic_reprint_only"),
        .init(commandKind:.applyOperationalContact,disposition:.compensatable,stableReason:"append_contact_successor_or_retirement_only"),
        .init(commandKind:.applyActivityContract,disposition:.compensatable,stableReason:"append_activity_contract_successor_only"),
        .init(commandKind:.applyPortableReview,disposition:.compensatable,stableReason:"append_existing_c14_review_successor_only"),
        .init(commandKind:.applyWorkResource,disposition:.compensatable,stableReason:"append_work_resource_successor_only"),
        .init(commandKind:.applyPartsStock,disposition:.compensatable,stableReason:"append_stock_movement_and_atomic_work_resource_successor_only"),
        .init(commandKind:.applyMyDay,disposition:.compensatable,stableReason:"append_my_day_plan_successor_and_carryover_receipt_only"),
        .init(commandKind:.applyServiceRequest,disposition:.compensatable,stableReason:"append_request_history_or_explicit_unlink_reversal_only"),
        .init(commandKind:.applyServiceReliability,disposition:.compensatable,stableReason:"append_incident_impact_cause_remedy_repair_restoration_or_exposure_successor_only"),
        .init(commandKind:.applyShopReportProfile,disposition:.compensatable,stableReason:"append_shop_report_profile_successor_only"),
        .init(commandKind:.applyRoundSession,disposition:.compensatable,stableReason:"append_round_session_successor_only"),
        .init(commandKind:.applyImportBulk,disposition:.compensatable,stableReason:"incumbent_import_bulk_append_or_replace_contract"),
        .init(commandKind:.applyEvidenceQuality,disposition:.irreversible,stableReason:"immutable_evidence_quality_assessment_and_waiver_history_forward_fix_only"),
    ]

    static func policy(for kind: WorkspaceCommandKindV1) throws -> MutationReversalPolicyV1 {
        guard policies.count == WorkspaceCommandKindV1.allCases.count,
              Set(policies.map(\.commandKind)).count == policies.count,
              let policy = policies.first(where: { $0.commandKind == kind }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return policy
    }
}

struct SemanticReversalValueV1: Codable, Equatable, Sendable {
    let key: String
    let value: String
}

struct SemanticReversalDependencyV1: Codable, Equatable, Sendable {
    let predecessor: WorkspaceEntityIdentityV1
    let successor: WorkspaceEntityIdentityV1
}

struct SemanticReversalPlanV1: Equatable, Sendable {
    static let maximumItems = 256
    static let maximumTextLength = 4_096

    let schemaVersion: Int
    let mutationID: MutationIDV1
    let commandKind: WorkspaceCommandKindV1
    let disposition: MutationReversalDispositionV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let prospectiveTargets: [WorkspaceEntityIdentityV1]
    let requiredSemanticValues: [SemanticReversalValueV1]
    let contentReferences: [String]
    let dependencyGraph: [SemanticReversalDependencyV1]
    let conflicts: [String]
    let compensatingCommands: [WorkspaceCommandV1]
    let planDigest: String

    init(
        mutationID: MutationIDV1,
        commandKind: WorkspaceCommandKindV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        prospectiveTargets: [WorkspaceEntityIdentityV1],
        requiredSemanticValues: [SemanticReversalValueV1],
        contentReferences: [String],
        dependencyGraph: [SemanticReversalDependencyV1],
        conflicts: [String],
        compensatingCommands: [WorkspaceCommandV1]
    ) throws {
        let policy = try MutationReversalPolicyRegistryV1.policy(for: commandKind)
        let counts = [prospectiveTargets.count, requiredSemanticValues.count, contentReferences.count,
                      dependencyGraph.count, conflicts.count, compensatingCommands.count]
        guard counts.allSatisfy({ $0 <= Self.maximumItems }),
              requiredSemanticValues.allSatisfy({ !$0.key.isEmpty && $0.key.count <= Self.maximumTextLength && $0.value.count <= Self.maximumTextLength }),
              (contentReferences + conflicts).allSatisfy({ !$0.isEmpty && $0.count <= Self.maximumTextLength }),
              policy.disposition != .irreversible || compensatingCommands.isEmpty else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        let targets = prospectiveTargets.sorted { $0.stableKey < $1.stableKey }
        let values = requiredSemanticValues.sorted { ($0.key, $0.value) < ($1.key, $1.value) }
        let references = contentReferences.sorted()
        let dependencies = dependencyGraph.sorted {
            ($0.predecessor.stableKey, $0.successor.stableKey) < ($1.predecessor.stableKey, $1.successor.stableKey)
        }
        let sortedConflicts = conflicts.sorted()
        let basis = DigestBasis(
            schemaVersion: 1,
            mutationID: mutationID,
            commandKind: commandKind,
            disposition: policy.disposition,
            expectedRevision: expectedRevision,
            prospectiveTargets: targets,
            requiredSemanticValues: values,
            contentReferences: references,
            dependencyGraph: dependencies,
            conflicts: sortedConflicts,
            compensatingCommands: compensatingCommands
        )
        schemaVersion = 1
        self.mutationID = mutationID
        self.commandKind = commandKind
        disposition = policy.disposition
        self.expectedRevision = expectedRevision
        self.prospectiveTargets = targets
        self.requiredSemanticValues = values
        self.contentReferences = references
        self.dependencyGraph = dependencies
        self.conflicts = sortedConflicts
        self.compensatingCommands = compensatingCommands
        planDigest = try WorkspaceMutationCanonicalV1.sha256(basis)
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let mutationID: MutationIDV1
        let commandKind: WorkspaceCommandKindV1
        let disposition: MutationReversalDispositionV1
        let expectedRevision: WorkspaceExpectedRevisionV1
        let prospectiveTargets: [WorkspaceEntityIdentityV1]
        let requiredSemanticValues: [SemanticReversalValueV1]
        let contentReferences: [String]
        let dependencyGraph: [SemanticReversalDependencyV1]
        let conflicts: [String]
        let compensatingCommands: [WorkspaceCommandV1]
    }
}

struct MutationBoundaryClosureReceiptV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let writerType: String
    let writersPerWorkspaceGeneration: Int
    let unreservedProductionFeatureOwnedInsertSaveDeleteCount: Int
    let deferredReservedDirectWritePaths: [String]
    let fullyClosed: Bool
    let reconciliationRequired: Bool
    let temporaryAdapterType: String
    let durableMutationSchemaPresent: Bool

    static let kernel = MutationBoundaryClosureReceiptV1(
        schemaVersion: 1,
        writerType: "WorkspaceWriterV1",
        writersPerWorkspaceGeneration: 1,
        unreservedProductionFeatureOwnedInsertSaveDeleteCount: 0,
        deferredReservedDirectWritePaths: [
            "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
            "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        ],
        fullyClosed: false,
        reconciliationRequired: true,
        temporaryAdapterType: "WorkspaceWriterAdapterV1",
        durableMutationSchemaPresent: true
    )
}

enum WorkspaceMutationCanonicalV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }
}

extension WorkspaceID: Codable {
    private enum CodingKeys: String, CodingKey { case rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rawValue: try container.decode(UUID.self, forKey: .rawValue))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}

/// C34 scene navigation is device-operational state, never workspace truth.
/// This assertion is intentionally derived from the canonical kind registries
/// so a later route/scene persistence case fails conformance instead of
/// silently acquiring mutation authority.
enum C34SceneNavigationCanonicalExclusionV1 {
    static let routeResolutionMutationCount = 0
    static let routeRestorationMutationCount = 0

    static func validate() -> Bool {
        let reserved = ["route", "navigation", "scene"]
        let hasEntityKind = WorkspaceEntityKindV1.allCases.contains { kind in
            reserved.contains { kind.rawValue.lowercased().contains($0) }
        }
        let hasCommandKind = WorkspaceCommandKindV1.allCases.contains { kind in
            reserved.contains { kind.rawValue.lowercased().contains($0) }
        }
        let lifecycle = SceneNavigationLifecycleDispositionV1()
        return !hasEntityKind && !hasCommandKind
            && routeResolutionMutationCount == 0
            && routeRestorationMutationCount == 0
            && !lifecycle.workspaceTruth
            && !lifecycle.journalIncluded
            && !lifecycle.searchIncluded
    }
}

extension ReplicaID: Codable {
    private enum CodingKeys: String, CodingKey { case rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rawValue: container.decode(UUID.self, forKey: .rawValue))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-command

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

enum WorkspaceEntityKindV1: String, CaseIterable, Codable, Sendable {
    case site
    case asset
    case locationNode
    case assetPlacementEvent
    case assetCompositionEdge
    case assetCompositionEvent
    case savedSmartView
    case serviceParty
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
    case workflowRecord
    case evidenceFile
    case issue
    case packet
    case report
    case deletionLedgerEntry
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
    case applyClientCapability(ClientCapabilityMutationV1)

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
        case .applyClientCapability:.applyClientCapability
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
    case applyClientCapability="apply_client_capability"
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
            }
            values = result
        case let .applyAssetPlacementChange(plan):
            values = try [.init(kind: .asset, id: plan.basis.assetID), .init(kind: .assetPlacementEvent, id: plan.newEventID)]
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
        .init(commandKind:.applyClientCapability,disposition:.irreversible,stableReason:"append_client_capability_forward_fix_only"),
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

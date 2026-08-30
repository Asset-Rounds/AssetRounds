import Foundation

enum WorkPacketScheduleCoordinatorBoundaryV1 { static let startRequiresScheduleMutation = true }

enum C51WorkPacketScheduleCoordinatorBoundaryV1 {
    static let scheduleClosureMetadataIsDerivedOnly = true
    static let coordinatorOwnsNoOccurrenceWriter = true
    static let canonicalScheduleStartRemainsExplicit = true

    static func validate(_ metadata: C51ScheduleClosureMetadataV1) throws {
        try metadata.validate()
    }
}

/// Application bridge to the sole WorkspaceWriter. A conformer must route
/// these values through its canonical expected-revision mutation command and
/// return the durable workspace receipt; it may not persist independently.
@MainActor protocol WorkPacketManifestWritingV1: AnyObject {
    func append(manifest: WorkPacketManifestV1) throws -> MutationReceiptV1
    func append(claim: WorkItemClaimV1) throws -> MutationReceiptV1
    func append(lease: WorkLeaseV1) throws -> MutationReceiptV1
    func append(release: WorkReleaseV1) throws -> MutationReceiptV1
    func append(handoff: WorkHandoffV1) throws -> MutationReceiptV1
}

@MainActor final class WorkPacketManifestCoordinatorV1 {
    private let writer: any WorkPacketManifestWritingV1
    private let lifecycle: WorkPacketManifestLifecycleAdapterV1

    init(
        writer: any WorkPacketManifestWritingV1,
        lifecycle: WorkPacketManifestLifecycleAdapterV1
    ) {
        self.writer = writer
        self.lifecycle = lifecycle
    }

    func append(manifest: WorkPacketManifestV1) throws -> MutationReceiptV1 {
        try manifest.validate()
        return try writer.append(manifest: manifest)
    }

    func claim(
        _ claim: WorkItemClaimV1,
        manifest: WorkPacketManifestV1
    ) throws -> MutationReceiptV1 {
        try manifest.validate(); try claim.validate()
        guard claim.workspaceID == manifest.workspaceID,
              claim.manifest == (try WorkPacketManifestReferenceV1(manifest)),
              manifest.items.contains(where: {
                  $0.itemID == claim.item.itemID
                    && $0.kind == claim.item.itemKind
                    && $0.expectedRevision == claim.item.expectedRevision
                    && $0.itemSHA256 == claim.item.itemSHA256
              }) else { throw WorkPacketFailureV1.invalidValue }
        return try writer.append(claim: claim)
    }

    func lease(
        _ lease: WorkLeaseV1,
        claim: WorkItemClaimV1,
        at instant: Date
    ) throws -> MutationReceiptV1 {
        try claim.validate(); try lease.validate()
        guard try lease.isActive(at: instant),
              lease.workspaceID == claim.workspaceID,
              lease.claimID == claim.claimID,
              lease.item == claim.item,
              lease.holder.actor == claim.holder.actor,
              instant >= claim.claimedAt else { throw WorkPacketFailureV1.leaseExpired }
        return try writer.append(lease: lease)
    }

    func release(
        _ release: WorkReleaseV1,
        claim: WorkItemClaimV1,
        lease: WorkLeaseV1
    ) throws -> MutationReceiptV1 {
        try release.validate(claim: claim, lease: lease)
        return try writer.append(release: release)
    }

    func handoff(
        _ handoff: WorkHandoffV1,
        release: WorkReleaseV1
    ) throws -> MutationReceiptV1 {
        try handoff.validate(release: release)
        return try writer.append(handoff: handoff)
    }

    func projection(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        at instant: Date
    ) throws -> WorkPacketProjectionV1 {
        try lifecycle.projection(
            workspaceID: workspaceID,
            manifestID: manifestID,
            at: instant
        )
    }

    /// Validates the C23 binding/readiness inputs before returning the normal
    /// work-packet projection. The binding remains owned by the field-
    /// reference writer; this application seam performs no second write.
    func projectionWithFieldReferences(
        workspaceID: WorkspaceID,
        manifestID: UUID,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1],
        subjectState: FieldReferenceSubjectStateV1 = .active,
        at instant: Date
    ) throws -> WorkPacketFieldReferenceProjectionV1 {
        try lifecycle.projectionWithFieldReferences(
            workspaceID: workspaceID,
            manifestID: manifestID,
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness,
            subjectState: subjectState,
            at: instant
        )
    }

    /// Appends a manifest only after proving that each supplied binding is
    /// for the exact packet generation. Binding writes themselves use the
    /// dedicated field-reference coordinator.
    func append(
        manifest: WorkPacketManifestV1,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1],
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> MutationReceiptV1 {
        try manifest.validate()
        let projection = try WorkPacketFieldReferenceProjectionV1(
            projection: try WorkPacketProjectionBuilderV1.rebuild(
                workspaceID: manifest.workspaceID,
                manifest: manifest,
                claims: [], leases: [], releases: [], handoffs: [], at: manifest.createdAt
            ),
            manifest: manifest,
            bindings: fieldReferenceBindings,
            releases: fieldReferenceReleases,
            readiness: fieldReferenceReadiness,
            subjectState: subjectState
        )
        try projection.validate()
        return try writer.append(manifest: manifest)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_WorkPacket_WorkPacketManifestCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_WorkPacket_WorkPacketManifestCoordinatorV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Application_WorkPacket_WorkPacketManifestCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/WorkPacket/WorkPacketManifestCoordinatorV1.swift", role: .workPacket)
}

enum C31LightingConsumerBoundary_Application_WorkPacket_WorkPacketManifestCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/work-packet-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}
// MARK: - C32 assistance work packet boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_WorkPacket_WorkPacketManifestCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalDoesNotAlterReleasedWorkPacket = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceBoundary_Application_WorkPacket_WorkPacketManifestCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row129 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_WorkPacket_WorkPacketManifestCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

enum C34RouteAdoptionBoundary_WorkPacketManifestCoordinatorV1 {
    static let workDestination = NavigationDestinationV1.work
    static let canonicalTargetType = NavigationTargetV1.self
    static let canonicalMutationCount = 0
    static let startsAutomaticWork = false
}

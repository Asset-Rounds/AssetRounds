import Foundation

struct MutationReceiptIdentityV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID
    let localSequence: UInt64

    init(workspaceID: WorkspaceID, replicaID: ReplicaID, localSequence: UInt64) {
        self.workspaceID = workspaceID
        self.replicaID = replicaID
        self.localSequence = localSequence
    }

    func validate() throws {
        guard localSequence > 0,
              (try? WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: replicaID
              )) != nil else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID, replicaID, localSequence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        replicaID = try container.decode(ReplicaID.self, forKey: .replicaID)
        localSequence = try container.decode(UInt64.self, forKey: .localSequence)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(replicaID, forKey: .replicaID)
        try container.encode(localSequence, forKey: .localSequence)
    }

    var stableKey: String {
        "\(workspaceID.rawValue.uuidString.lowercased()):\(replicaID.rawValue.uuidString.lowercased()):\(localSequence)"
    }
}

enum MutationWorkspaceKeyV1 {
    static func value(workspaceID: WorkspaceID, mutationID: MutationIDV1) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased()):\(mutationID.rawValue.uuidString.lowercased())"
    }
}

enum MutationQuarantineIdentityDomainV1: String, Codable, Equatable, Sendable {
    case mutationEnvelope = "MUTATION_ENVELOPE"
    case semanticReversalReplayIdentity = "SEMANTIC_REVERSAL_REPLAY_IDENTITY"
}

enum MutationPostImageV1: Codable, Equatable, Sendable {
    case site(id: UUID, revision: UInt64, semanticSHA256: String)
    case asset(id: UUID, revision: UInt64, semanticSHA256: String)
    case locationNode(id: UUID, revision: UInt64, semanticSHA256: String)
    case assetPlacementEvent(id: UUID, revision: UInt64, semanticSHA256: String)
    case assetCompositionEdge(id: UUID, revision: UInt64, semanticSHA256: String)
    case assetCompositionEvent(id: UUID, revision: UInt64, semanticSHA256: String)
    case savedSmartView(id: UUID, revision: UInt64, semanticSHA256: String)
    case serviceParty(id: UUID, revision: UInt64, semanticSHA256: String)
    case sitePartyRoleEvent(id: UUID, revision: UInt64, semanticSHA256: String)
    case actorSnapshot(id: UUID, revision: UInt64, semanticSHA256: String)
    case qualificationSnapshot(id: UUID, revision: UInt64, semanticSHA256: String)
    case signoffSnapshot(id: UUID, revision: UInt64, semanticSHA256: String)
    case authoritySourceRelease(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case requirementBasisBinding(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case applicabilityContextSnapshot(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case assessmentScopeSnapshot(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case severityScaleRelease(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case findingClassificationBinding(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case measurementProtocolRelease(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case derivedFactEvaluatorDescriptor(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case derivedFactProvenance(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case functionalRelationshipTypeDescriptor(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case assetFunctionalRelationshipEvent(id: UUID, relationshipID: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case evidenceVisibility(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case claimEvidenceLink(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case assuranceManifest(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case attestation(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case inspectionReviewTransition(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case reviewDisposition(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case changeRequest(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case correctiveActionPolicy(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case correctiveActionEvent(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case workPacketManifest(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case workItemClaim(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case workLease(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case workRelease(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case workHandoff(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case fieldDraftCheckpoint(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case attachmentStagingItem(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case draftCommitSaga(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case draftContentReservation(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case draftCommitReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case draftDiscardReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case promotedPackageRelease(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case packageSandboxRun(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case packagePromotionReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case activePackageRegistryPointer(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case instrumentReference(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case calibrationStatusSnapshot(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case measurementCapture(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case measurementSeries(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case measurementQualityAssessment(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case privacyTransformPolicy(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case privacyRegion(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case privacyTransformManifest(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case privacyReviewReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case clientCapabilityProfile(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case clientCapabilityAdmissionDecision(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case packageLifecyclePolicy(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case packageLifecycleDisposition(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case fieldReferenceRelease(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case fieldReferenceBinding(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case accessibleDocumentAssessmentReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case surveyDefinitionIdentity(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case surveyDefinitionRelease(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case surveySession(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case factCapture(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case provisionalSubject(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case subjectPromotionReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case surveyPublicationSnapshot(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case assetLocator(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case locatorBindingReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case scheduleDefinitionRelease(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case occurrenceHistoryEvent(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case planDocument(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case planRevision(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case planPlacement(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case planRebaseReceipt(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case assetPoseEvent(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case spatialAnchorObservation(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case evidenceContext(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case pairedObservationLink(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case lightingSystem(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case lightingObservation(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case lightingIssue(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case lightingMeasurementPlan(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case lightingClaimState(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case temporalEvidenceClip(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case timecodedEvidenceAnchor(id:UUID,concurrencyIdentity:WorkspaceEntityIdentityV1,revision:UInt64,semanticSHA256:String)
    case workflowRecord(id: UUID, revision: UInt64, semanticSHA256: String)
    case evidenceFile(id: UUID, revision: UInt64, semanticSHA256: String)
    case issue(id: UUID, revision: UInt64, semanticSHA256: String)
    case packet(id: UUID, revision: UInt64, semanticSHA256: String)
    case report(id: UUID, revision: UInt64, semanticSHA256: String)
    case deletionLedgerEntry(id: UUID, revision: UInt64, semanticSHA256: String)
    case tombstone(identity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)

    var identity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .site(id, _, _): return try .init(kind: .site, id: id)
            case let .asset(id, _, _): return try .init(kind: .asset, id: id)
            case let .locationNode(id, _, _): return try .init(kind: .locationNode, id: id)
            case let .assetPlacementEvent(id, _, _): return try .init(kind: .assetPlacementEvent, id: id)
            case let .assetCompositionEdge(id, _, _): return try .init(kind: .assetCompositionEdge, id: id)
            case let .assetCompositionEvent(id, _, _): return try .init(kind: .assetCompositionEvent, id: id)
            case let .savedSmartView(id, _, _): return try .init(kind: .savedSmartView, id: id)
            case let .serviceParty(id, _, _): return try .init(kind: .serviceParty, id: id)
            case let .sitePartyRoleEvent(id, _, _): return try .init(kind: .sitePartyRoleEvent, id: id)
            case let .actorSnapshot(id, _, _): return try .init(kind: .actorSnapshot, id: id)
            case let .qualificationSnapshot(id, _, _): return try .init(kind: .qualificationSnapshot, id: id)
            case let .signoffSnapshot(id, _, _): return try .init(kind: .signoffSnapshot, id: id)
            case let .authoritySourceRelease(id, _, _, _): return try .init(kind: .authoritySourceRelease, id: id)
            case let .requirementBasisBinding(id, _, _, _): return try .init(kind: .requirementBasisBinding, id: id)
            case let .applicabilityContextSnapshot(id, _, _, _): return try .init(kind: .applicabilityContextSnapshot, id: id)
            case let .assessmentScopeSnapshot(id, _, _, _): return try .init(kind: .assessmentScopeSnapshot, id: id)
            case let .severityScaleRelease(id, _, _, _): return try .init(kind: .severityScaleRelease, id: id)
            case let .findingClassificationBinding(id, _, _, _): return try .init(kind: .findingClassificationBinding, id: id)
            case let .measurementProtocolRelease(id, _, _, _): return try .init(kind: .measurementProtocolRelease, id: id)
            case let .derivedFactEvaluatorDescriptor(id, _, _, _): return try .init(kind: .derivedFactEvaluatorDescriptor, id: id)
            case let .derivedFactProvenance(id, _, _, _): return try .init(kind: .derivedFactProvenance, id: id)
            case let .functionalRelationshipTypeDescriptor(id, _, _, _): return try .init(kind: .functionalRelationshipTypeDescriptor, id: id)
            case let .assetFunctionalRelationshipEvent(id, _, _, _, _): return try .init(kind: .assetFunctionalRelationshipEvent, id: id)
            case let .evidenceVisibility(id,_,_,_):return try .init(kind:.evidenceVisibility,id:id)
            case let .claimEvidenceLink(id,_,_,_):return try .init(kind:.claimEvidenceLink,id:id)
            case let .assuranceManifest(id,_,_,_):return try .init(kind:.assuranceManifest,id:id)
            case let .attestation(id,_,_,_):return try .init(kind:.attestation,id:id)
            case let .inspectionReviewTransition(id,_,_,_):return try .init(kind:.inspectionReviewTransition,id:id)
            case let .reviewDisposition(id,_,_,_):return try .init(kind:.reviewDisposition,id:id)
            case let .changeRequest(id,_,_,_):return try .init(kind:.changeRequest,id:id)
            case let .correctiveActionPolicy(id,_,_,_):return try .init(kind:.correctiveActionPolicy,id:id)
            case let .correctiveActionEvent(id,_,_,_):return try .init(kind:.correctiveActionEvent,id:id)
            case let .workPacketManifest(id,_,_,_):return try .init(kind:.workPacketManifest,id:id)
            case let .workItemClaim(id,_,_,_):return try .init(kind:.workItemClaim,id:id)
            case let .workLease(id,_,_,_):return try .init(kind:.workLease,id:id)
            case let .workRelease(id,_,_,_):return try .init(kind:.workRelease,id:id)
            case let .workHandoff(id,_,_,_):return try .init(kind:.workHandoff,id:id)
            case let .fieldDraftCheckpoint(id,_,_,_):return try .init(kind:.fieldDraftCheckpoint,id:id)
            case let .attachmentStagingItem(id,_,_,_):return try .init(kind:.attachmentStagingItem,id:id)
            case let .draftCommitSaga(id,_,_,_):return try .init(kind:.draftCommitSaga,id:id)
            case let .draftContentReservation(id,_,_,_):return try .init(kind:.draftContentReservation,id:id)
            case let .draftCommitReceipt(id,_,_,_):return try .init(kind:.draftCommitReceipt,id:id)
            case let .draftDiscardReceipt(id,_,_,_):return try .init(kind:.draftDiscardReceipt,id:id)
            case let .promotedPackageRelease(id,_,_,_):return try .init(kind:.promotedPackageRelease,id:id)
            case let .packageSandboxRun(id,_,_,_):return try .init(kind:.packageSandboxRun,id:id)
            case let .packagePromotionReceipt(id,_,_,_):return try .init(kind:.packagePromotionReceipt,id:id)
            case let .activePackageRegistryPointer(id,_,_,_):return try .init(kind:.activePackageRegistryPointer,id:id)
            case let .instrumentReference(id,_,_,_):return try .init(kind:.instrumentReference,id:id)
            case let .calibrationStatusSnapshot(id,_,_,_):return try .init(kind:.calibrationStatusSnapshot,id:id)
            case let .measurementCapture(id,_,_,_):return try .init(kind:.measurementCapture,id:id)
            case let .measurementSeries(id,_,_,_):return try .init(kind:.measurementSeries,id:id)
            case let .measurementQualityAssessment(id,_,_,_):return try .init(kind:.measurementQualityAssessment,id:id)
            case let .privacyTransformPolicy(id,_,_,_):return try .init(kind:.privacyTransformPolicy,id:id)
            case let .privacyRegion(id,_,_,_):return try .init(kind:.privacyRegion,id:id)
            case let .privacyTransformManifest(id,_,_,_):return try .init(kind:.privacyTransformManifest,id:id)
            case let .privacyReviewReceipt(id,_,_,_):return try .init(kind:.privacyReviewReceipt,id:id)
            case let .clientCapabilityProfile(id,_,_,_):return try .init(kind:.clientCapabilityProfile,id:id)
            case let .clientCapabilityAdmissionDecision(id,_,_,_):return try .init(kind:.clientCapabilityAdmissionDecision,id:id)
            case let .packageLifecyclePolicy(id,_,_,_):return try .init(kind:.packageLifecyclePolicy,id:id)
            case let .packageLifecycleDisposition(id,_,_,_):return try .init(kind:.packageLifecycleDisposition,id:id)
            case let .fieldReferenceRelease(id,_,_,_):return try .init(kind:.fieldReferenceRelease,id:id)
            case let .fieldReferenceBinding(id,_,_,_):return try .init(kind:.fieldReferenceBinding,id:id)
            case let .accessibleDocumentAssessmentReceipt(id,_,_,_):return try .init(kind:.accessibleDocumentAssessmentReceipt,id:id)
            case let .surveyDefinitionIdentity(id,_,_,_):return try .init(kind:.surveyDefinitionIdentity,id:id)
            case let .surveyDefinitionRelease(id,_,_,_):return try .init(kind:.surveyDefinitionRelease,id:id)
            case let .surveySession(id,_,_,_):return try .init(kind:.surveySession,id:id)
            case let .factCapture(id,_,_,_):return try .init(kind:.factCapture,id:id)
            case let .provisionalSubject(id,_,_,_):return try .init(kind:.provisionalSubject,id:id)
            case let .subjectPromotionReceipt(id,_,_,_):return try .init(kind:.subjectPromotionReceipt,id:id)
            case let .surveyPublicationSnapshot(id,_,_,_):return try .init(kind:.surveyPublicationSnapshot,id:id)
            case let .assetLocator(id,_,_,_):return try .init(kind:.assetLocator,id:id)
            case let .locatorBindingReceipt(id,_,_,_):return try .init(kind:.locatorBindingReceipt,id:id)
            case let .scheduleDefinitionRelease(id,_,_,_):return try .init(kind:.scheduleDefinitionRelease,id:id)
            case let .occurrenceHistoryEvent(id,_,_,_):return try .init(kind:.occurrenceHistoryEvent,id:id)
            case let .planDocument(id,_,_,_):return try .init(kind:.planDocument,id:id)
            case let .planRevision(id,_,_,_):return try .init(kind:.planRevision,id:id)
            case let .planPlacement(id,_,_,_):return try .init(kind:.planPlacement,id:id)
            case let .planRebaseReceipt(id,_,_,_):return try .init(kind:.planRebaseReceipt,id:id)
            case let .assetPoseEvent(id,_,_,_):return try .init(kind:.assetPoseEvent,id:id)
            case let .spatialAnchorObservation(id,_,_,_):return try .init(kind:.spatialAnchorObservation,id:id)
            case let .evidenceContext(id,_,_,_):return try .init(kind:.evidenceContext,id:id)
            case let .pairedObservationLink(id,_,_,_):return try .init(kind:.pairedObservationLink,id:id)
            case let .lightingSystem(id,_,_,_):return try .init(kind:.lightingSystem,id:id)
            case let .lightingObservation(id,_,_,_):return try .init(kind:.lightingObservation,id:id)
            case let .lightingIssue(id,_,_,_):return try .init(kind:.lightingIssue,id:id)
            case let .lightingMeasurementPlan(id,_,_,_):return try .init(kind:.lightingMeasurementPlan,id:id)
            case let .lightingClaimState(id,_,_,_):return try .init(kind:.lightingClaimState,id:id)
            case let .temporalEvidenceClip(id,_,_,_):return try .init(kind:.temporalEvidenceClip,id:id)
            case let .timecodedEvidenceAnchor(id,_,_,_):return try .init(kind:.timecodedEvidenceAnchor,id:id)
            case let .workflowRecord(id, _, _): return try .init(kind: .workflowRecord, id: id)
            case let .evidenceFile(id, _, _): return try .init(kind: .evidenceFile, id: id)
            case let .issue(id, _, _): return try .init(kind: .issue, id: id)
            case let .packet(id, _, _): return try .init(kind: .packet, id: id)
            case let .report(id, _, _): return try .init(kind: .report, id: id)
            case let .deletionLedgerEntry(id, _, _): return try .init(kind: .deletionLedgerEntry, id: id)
            case let .tombstone(identity, _, _): return identity
            }
        }
    }

    var semanticSHA256: String {
        switch self {
        case let .accessibleDocumentAssessmentReceipt(_,_,_,value),let .surveyDefinitionIdentity(_,_,_,value),let .surveyDefinitionRelease(_,_,_,value),let .surveySession(_,_,_,value),let .factCapture(_,_,_,value),let .provisionalSubject(_,_,_,value),let .subjectPromotionReceipt(_,_,_,value),let .surveyPublicationSnapshot(_,_,_,value),let .assetLocator(_,_,_,value),let .locatorBindingReceipt(_,_,_,value),let .scheduleDefinitionRelease(_,_,_,value),let .occurrenceHistoryEvent(_,_,_,value),let .planDocument(_,_,_,value),let .planRevision(_,_,_,value),let .planPlacement(_,_,_,value),let .planRebaseReceipt(_,_,_,value),let .assetPoseEvent(_,_,_,value),let .spatialAnchorObservation(_,_,_,value),let .evidenceContext(_,_,_,value),let .pairedObservationLink(_,_,_,value),let .lightingSystem(_,_,_,value),let .lightingObservation(_,_,_,value),let .lightingIssue(_,_,_,value),let .lightingMeasurementPlan(_,_,_,value),let .lightingClaimState(_,_,_,value),let .temporalEvidenceClip(_,_,_,value),let .timecodedEvidenceAnchor(_,_,_,value):return value
        case let .site(_, _, value), let .asset(_, _, value), let .locationNode(_, _, value),
             let .assetPlacementEvent(_, _, value), let .assetCompositionEdge(_, _, value),
             let .assetCompositionEvent(_, _, value), let .savedSmartView(_, _, value),
             let .serviceParty(_, _, value), let .sitePartyRoleEvent(_, _, value),
             let .actorSnapshot(_, _, value), let .qualificationSnapshot(_, _, value),
             let .signoffSnapshot(_, _, value),
             let .authoritySourceRelease(_, _, _, value), let .requirementBasisBinding(_, _, _, value),
             let .applicabilityContextSnapshot(_, _, _, value), let .assessmentScopeSnapshot(_, _, _, value),
             let .severityScaleRelease(_, _, _, value), let .findingClassificationBinding(_, _, _, value),
             let .measurementProtocolRelease(_, _, _, value), let .derivedFactEvaluatorDescriptor(_, _, _, value),
             let .derivedFactProvenance(_, _, _, value),
             let .functionalRelationshipTypeDescriptor(_, _, _, value),
             let .assetFunctionalRelationshipEvent(_, _, _, _, value),
             let .evidenceVisibility(_,_,_,value),let .claimEvidenceLink(_,_,_,value),
             let .assuranceManifest(_,_,_,value),let .attestation(_,_,_,value),
             let .inspectionReviewTransition(_,_,_,value),let .reviewDisposition(_,_,_,value),let .changeRequest(_,_,_,value),let .correctiveActionPolicy(_,_,_,value),let .correctiveActionEvent(_,_,_,value),
             let .workPacketManifest(_,_,_,value),let .workItemClaim(_,_,_,value),let .workLease(_,_,_,value),let .workRelease(_,_,_,value),let .workHandoff(_,_,_,value),
             let .fieldDraftCheckpoint(_,_,_,value),let .attachmentStagingItem(_,_,_,value),let .draftCommitSaga(_,_,_,value),let .draftContentReservation(_,_,_,value),let .draftCommitReceipt(_,_,_,value),let .draftDiscardReceipt(_,_,_,value),let .promotedPackageRelease(_,_,_,value),let .packageSandboxRun(_,_,_,value),let .packagePromotionReceipt(_,_,_,value),let .activePackageRegistryPointer(_,_,_,value),let .instrumentReference(_,_,_,value),let .calibrationStatusSnapshot(_,_,_,value),let .measurementCapture(_,_,_,value),let .measurementSeries(_,_,_,value),let .measurementQualityAssessment(_,_,_,value),let .privacyTransformPolicy(_,_,_,value),let .privacyRegion(_,_,_,value),let .privacyTransformManifest(_,_,_,value),let .privacyReviewReceipt(_,_,_,value),let .clientCapabilityProfile(_,_,_,value),let .clientCapabilityAdmissionDecision(_,_,_,value),let .packageLifecyclePolicy(_,_,_,value),let .packageLifecycleDisposition(_,_,_,value),let .fieldReferenceRelease(_,_,_,value),let .fieldReferenceBinding(_,_,_,value),
             let .workflowRecord(_, _, value),
             let .evidenceFile(_, _, value), let .issue(_, _, value), let .packet(_, _, value),
             let .report(_, _, value), let .deletionLedgerEntry(_, _, value),
             let .tombstone(_, _, value): return value
        }
    }

    var concurrencyIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .authoritySourceRelease(_, value, _, _):
                guard value.kind == .authoritySourceRelease else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .requirementBasisBinding(_, value, _, _):
                guard value.kind == .requirementBasisBinding else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .applicabilityContextSnapshot(_, value, _, _):
                guard value.kind == .applicabilityContextSnapshot else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .assessmentScopeSnapshot(_, value, _, _):
                guard value.kind == .assessmentScopeSnapshot else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .severityScaleRelease(_, value, _, _):
                guard value.kind == .severityScaleRelease else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .findingClassificationBinding(_, value, _, _):
                guard value.kind == .findingClassificationBinding else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .measurementProtocolRelease(_, value, _, _):
                guard value.kind == .measurementProtocolRelease else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .derivedFactEvaluatorDescriptor(_, value, _, _):
                guard value.kind == .derivedFactEvaluatorDescriptor else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .derivedFactProvenance(_, value, _, _):
                guard value.kind == .derivedFactProvenance else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .functionalRelationshipTypeDescriptor(_, value, _, _):
                guard value.kind == .functionalRelationshipTypeDescriptor else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .assetFunctionalRelationshipEvent(_, _, value, _, _):
                guard value.kind == .assetFunctionalRelationshipEvent else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .evidenceVisibility(_,value,_,_):guard value.kind == .evidenceVisibility else{throw WorkspaceMutationFailureV1.invalidReceipt};return value
            case let .claimEvidenceLink(_,value,_,_):guard value.kind == .claimEvidenceLink else{throw WorkspaceMutationFailureV1.invalidReceipt};return value
            case let .assuranceManifest(_,value,_,_):guard value.kind == .assuranceManifest else{throw WorkspaceMutationFailureV1.invalidReceipt};return value
            case let .attestation(_,value,_,_):guard value.kind == .attestation else{throw WorkspaceMutationFailureV1.invalidReceipt};return value
            case let .inspectionReviewTransition(_,v,_,_):guard v.kind == .inspectionReviewTransition else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .reviewDisposition(_,v,_,_):guard v.kind == .reviewDisposition else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .changeRequest(_,v,_,_):guard v.kind == .changeRequest else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .correctiveActionPolicy(_,v,_,_):guard v.kind == .correctiveActionPolicy else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .correctiveActionEvent(_,v,_,_):guard v.kind == .correctiveActionEvent else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .workPacketManifest(_,v,_,_):guard v.kind == .workPacketManifest else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .workItemClaim(_,v,_,_):guard v.kind == .workItemClaim else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .workLease(_,v,_,_):guard v.kind == .workLease else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .workRelease(_,v,_,_):guard v.kind == .workRelease else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .workHandoff(_,v,_,_):guard v.kind == .workHandoff else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .fieldDraftCheckpoint(_,v,_,_):guard v.kind == .fieldDraftCheckpoint else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .attachmentStagingItem(_,v,_,_):guard v.kind == .attachmentStagingItem else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .draftCommitSaga(_,v,_,_):guard v.kind == .draftCommitSaga else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .draftContentReservation(_,v,_,_):guard v.kind == .draftContentReservation else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .draftCommitReceipt(_,v,_,_):guard v.kind == .draftCommitReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .draftDiscardReceipt(_,v,_,_):guard v.kind == .draftDiscardReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .promotedPackageRelease(_,v,_,_):guard v.kind == .promotedPackageRelease else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .packageSandboxRun(_,v,_,_):guard v.kind == .packageSandboxRun else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .packagePromotionReceipt(_,v,_,_):guard v.kind == .packagePromotionReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .activePackageRegistryPointer(_,v,_,_):guard v.kind == .activePackageRegistryPointer else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .instrumentReference(_,v,_,_):guard v.kind == .instrumentReference else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .calibrationStatusSnapshot(_,v,_,_):guard v.kind == .calibrationStatusSnapshot else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .measurementCapture(_,v,_,_):guard v.kind == .measurementCapture else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .measurementSeries(_,v,_,_):guard v.kind == .measurementSeries else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .measurementQualityAssessment(_,v,_,_):guard v.kind == .measurementQualityAssessment else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .privacyTransformPolicy(_,v,_,_):guard v.kind == .privacyTransformPolicy else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .privacyRegion(_,v,_,_):guard v.kind == .privacyRegion else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .privacyTransformManifest(_,v,_,_):guard v.kind == .privacyTransformManifest else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .privacyReviewReceipt(_,v,_,_):guard v.kind == .privacyReviewReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .clientCapabilityProfile(_,v,_,_):guard v.kind == .clientCapabilityProfile else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .clientCapabilityAdmissionDecision(_,v,_,_):guard v.kind == .clientCapabilityAdmissionDecision else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .packageLifecyclePolicy(_,v,_,_):guard v.kind == .packageLifecyclePolicy else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .packageLifecycleDisposition(_,v,_,_):guard v.kind == .packageLifecycleDisposition else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .fieldReferenceRelease(_,v,_,_):guard v.kind == .fieldReferenceRelease else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .fieldReferenceBinding(_,v,_,_):guard v.kind == .fieldReferenceBinding else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .accessibleDocumentAssessmentReceipt(_,v,_,_):guard v.kind == .accessibleDocumentAssessmentReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .surveyDefinitionIdentity(_,v,_,_):guard v.kind == .surveyDefinitionIdentity else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .surveyDefinitionRelease(_,v,_,_):guard v.kind == .surveyDefinitionRelease else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .surveySession(_,v,_,_):guard v.kind == .surveySession else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .factCapture(_,v,_,_):guard v.kind == .factCapture else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .provisionalSubject(_,v,_,_):guard v.kind == .provisionalSubject else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .subjectPromotionReceipt(_,v,_,_):guard v.kind == .subjectPromotionReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .surveyPublicationSnapshot(_,v,_,_):guard v.kind == .surveyPublicationSnapshot else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .assetLocator(_,v,_,_):guard v.kind == .assetLocator else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .locatorBindingReceipt(_,v,_,_):guard v.kind == .locatorBindingReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .scheduleDefinitionRelease(_,v,_,_):guard v.kind == .scheduleDefinitionRelease else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .occurrenceHistoryEvent(_,v,_,_):guard v.kind == .occurrenceHistoryEvent else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .planDocument(_,v,_,_):guard v.kind == .planDocument else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .planRevision(_,v,_,_):guard v.kind == .planRevision else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .planPlacement(_,v,_,_):guard v.kind == .planPlacement else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .planRebaseReceipt(_,v,_,_):guard v.kind == .planRebaseReceipt else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .assetPoseEvent(_,v,_,_):guard v.kind == .assetPoseEvent else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .spatialAnchorObservation(_,v,_,_):guard v.kind == .spatialAnchorObservation else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .evidenceContext(_,v,_,_):guard v.kind == .evidenceContext else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .pairedObservationLink(_,v,_,_):guard v.kind == .pairedObservationLink else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .lightingSystem(_,v,_,_):guard v.kind == .lightingSystem else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .lightingObservation(_,v,_,_):guard v.kind == .lightingObservation else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .lightingIssue(_,v,_,_):guard v.kind == .lightingIssue else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .lightingMeasurementPlan(_,v,_,_):guard v.kind == .lightingMeasurementPlan else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .lightingClaimState(_,v,_,_):guard v.kind == .lightingClaimState else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .temporalEvidenceClip(_,v,_,_):guard v.kind == .temporalEvidenceClip else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            case let .timecodedEvidenceAnchor(_,v,_,_):guard v.kind == .timecodedEvidenceAnchor else{throw WorkspaceMutationFailureV1.invalidReceipt};return v
            default:
                return try identity
            }
        }
    }

    var revision: UInt64 {
        switch self {
        case let .accessibleDocumentAssessmentReceipt(_,_,value,_),let .surveyDefinitionIdentity(_,_,value,_),let .surveyDefinitionRelease(_,_,value,_),let .surveySession(_,_,value,_),let .factCapture(_,_,value,_),let .provisionalSubject(_,_,value,_),let .subjectPromotionReceipt(_,_,value,_),let .surveyPublicationSnapshot(_,_,value,_),let .assetLocator(_,_,value,_),let .locatorBindingReceipt(_,_,value,_),let .scheduleDefinitionRelease(_,_,value,_),let .occurrenceHistoryEvent(_,_,value,_),let .planDocument(_,_,value,_),let .planRevision(_,_,value,_),let .planPlacement(_,_,value,_),let .planRebaseReceipt(_,_,value,_),let .assetPoseEvent(_,_,value,_),let .spatialAnchorObservation(_,_,value,_),let .evidenceContext(_,_,value,_),let .pairedObservationLink(_,_,value,_),let .lightingSystem(_,_,value,_),let .lightingObservation(_,_,value,_),let .lightingIssue(_,_,value,_),let .lightingMeasurementPlan(_,_,value,_),let .lightingClaimState(_,_,value,_),let .temporalEvidenceClip(_,_,value,_),let .timecodedEvidenceAnchor(_,_,value,_):return value
        case let .site(_, value, _), let .asset(_, value, _),
             let .locationNode(_, value, _), let .assetPlacementEvent(_, value, _),
             let .assetCompositionEdge(_, value, _), let .assetCompositionEvent(_, value, _),
             let .savedSmartView(_, value, _),
             let .serviceParty(_, value, _), let .sitePartyRoleEvent(_, value, _),
             let .actorSnapshot(_, value, _), let .qualificationSnapshot(_, value, _),
             let .signoffSnapshot(_, value, _),
             let .authoritySourceRelease(_, _, value, _), let .requirementBasisBinding(_, _, value, _),
             let .applicabilityContextSnapshot(_, _, value, _), let .assessmentScopeSnapshot(_, _, value, _),
             let .severityScaleRelease(_, _, value, _), let .findingClassificationBinding(_, _, value, _),
             let .measurementProtocolRelease(_, _, value, _), let .derivedFactEvaluatorDescriptor(_, _, value, _),
             let .derivedFactProvenance(_, _, value, _),
             let .functionalRelationshipTypeDescriptor(_, _, value, _),
             let .assetFunctionalRelationshipEvent(_, _, _, value, _),
             let .evidenceVisibility(_,_,value,_),let .claimEvidenceLink(_,_,value,_),
             let .assuranceManifest(_,_,value,_),let .attestation(_,_,value,_),
             let .inspectionReviewTransition(_,_,value,_),let .reviewDisposition(_,_,value,_),let .changeRequest(_,_,value,_),let .correctiveActionPolicy(_,_,value,_),let .correctiveActionEvent(_,_,value,_),
             let .workPacketManifest(_,_,value,_),let .workItemClaim(_,_,value,_),let .workLease(_,_,value,_),let .workRelease(_,_,value,_),let .workHandoff(_,_,value,_),
             let .fieldDraftCheckpoint(_,_,value,_),let .attachmentStagingItem(_,_,value,_),let .draftCommitSaga(_,_,value,_),let .draftContentReservation(_,_,value,_),let .draftCommitReceipt(_,_,value,_),let .draftDiscardReceipt(_,_,value,_),let .promotedPackageRelease(_,_,value,_),let .packageSandboxRun(_,_,value,_),let .packagePromotionReceipt(_,_,value,_),let .activePackageRegistryPointer(_,_,value,_),let .instrumentReference(_,_,value,_),let .calibrationStatusSnapshot(_,_,value,_),let .measurementCapture(_,_,value,_),let .measurementSeries(_,_,value,_),let .measurementQualityAssessment(_,_,value,_),let .privacyTransformPolicy(_,_,value,_),let .privacyRegion(_,_,value,_),let .privacyTransformManifest(_,_,value,_),let .privacyReviewReceipt(_,_,value,_),let .clientCapabilityProfile(_,_,value,_),let .clientCapabilityAdmissionDecision(_,_,value,_),let .packageLifecyclePolicy(_,_,value,_),let .packageLifecycleDisposition(_,_,value,_),let .fieldReferenceRelease(_,_,value,_),let .fieldReferenceBinding(_,_,value,_),
             let .workflowRecord(_, value, _), let .evidenceFile(_, value, _),
             let .issue(_, value, _), let .packet(_, value, _),
             let .report(_, value, _), let .deletionLedgerEntry(_, value, _),
             let .tombstone(_, value, _): return value
        }
    }
}

struct MutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumPostImageCount = 1_024

    let schemaVersion: Int
    let identity: MutationReceiptIdentityV1
    let mutationID: MutationIDV1
    let envelopeSHA256: String
    let commandBodySHA256: String
    let expectedRevision: MutationPortableExpectedRevisionV1
    let resultingRevision: MutationPortableExpectedRevisionV1
    let postImages: [MutationPostImageV1]
    let contentDependencyIDs: [String]
    let resultSHA256: String
    let sourceKind: MutationSourceKindV1
    let causationMutationID: MutationIDV1?
    let correlationID: UUID?
    let reversesMutationID: MutationIDV1?
    let committedAt: Date

    init(
        identity: MutationReceiptIdentityV1,
        envelope: MutationEnvelopeV1,
        resultingRevision: MutationPortableExpectedRevisionV1,
        postImages: [MutationPostImageV1],
        reversesMutationID: MutationIDV1? = nil,
        committedAt: Date
    ) throws {
        guard identity.workspaceID == envelope.workspaceID,
              identity.replicaID == envelope.replicaID else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        let ordered = try postImages.sorted { try $0.identity.stableKey < $1.identity.stableKey }
        let result = ResultDigestBasis(resultingRevision: resultingRevision, postImages: ordered)
        schemaVersion = Self.schemaVersion
        self.identity = identity
        mutationID = envelope.mutationID
        envelopeSHA256 = try envelope.canonicalSHA256()
        commandBodySHA256 = envelope.commandBodySHA256
        expectedRevision = envelope.expectedRevision
        self.resultingRevision = resultingRevision
        self.postImages = ordered
        contentDependencyIDs = envelope.contentDependencyIDs
        resultSHA256 = try WorkspaceMutationCanonicalV1.sha256(result)
        sourceKind = envelope.sourceKind
        causationMutationID = envelope.causationMutationID
        correlationID = envelope.correlationID
        self.reversesMutationID = reversesMutationID
        self.committedAt = committedAt
        try validate()
    }

    func validate() throws {
        try expectedRevision.validate()
        try resultingRevision.validate()
        try identity.validate()
        let identities = try postImages.map { try $0.identity }
        let concurrencyIdentities = try postImages.map { try $0.concurrencyIdentity }
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expectedRevision.entityRevisions.map { ($0.identity, $0.revision) }
        )
        let resultingByIdentity = Dictionary(
            uniqueKeysWithValues: resultingRevision.entityRevisions.map { ($0.identity, $0.revision) }
        )
        guard schemaVersion == Self.schemaVersion,
              identity.workspaceID == expectedRevision.workspaceID,
              expectedRevision.workspaceID == resultingRevision.workspaceID,
              expectedRevision.generationID == resultingRevision.generationID,
              expectedRevision.workspaceRevision < .max,
              resultingRevision.workspaceRevision == expectedRevision.workspaceRevision + 1,
              identity.localSequence > 0,
              !postImages.isEmpty,
              postImages.count <= Self.maximumPostImageCount,
              Set(identities).count == identities.count,
              Set(concurrencyIdentities).count == concurrencyIdentities.count,
              identities.map(\.stableKey) == identities.map(\.stableKey).sorted(),
              postImages.allSatisfy({ image in
                  guard let identity = try? image.identity,
                        let concurrencyIdentity = try? image.concurrencyIdentity,
                        let before = expectedByIdentity[concurrencyIdentity],
                        before < .max else { return false }
                  return image.revision == before + 1
                    && resultingByIdentity[identity] == image.revision
              }),
              contentDependencyIDs.count <= MutationEnvelopeV1.maximumDependencyCount,
              contentDependencyIDs == contentDependencyIDs.sorted(),
              Set(contentDependencyIDs).count == contentDependencyIDs.count,
              contentDependencyIDs.allSatisfy(MutationEnvelopeV1.validBoundedToken),
              postImages.allSatisfy({ MutationEnvelopeV1.isSHA256($0.semanticSHA256) }),
              MutationEnvelopeV1.isSHA256(envelopeSHA256),
              MutationEnvelopeV1.isSHA256(commandBodySHA256),
              MutationEnvelopeV1.isSHA256(resultSHA256),
              resultSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                ResultDigestBasis(resultingRevision: resultingRevision, postImages: postImages)
              )), committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    func canonicalData() throws -> Data { try validate(); return try WorkspaceMutationCanonicalV1.data(self) }
    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else { throw WorkspaceMutationFailureV1.invalidReceipt }
        return value
    }

    private struct ResultDigestBasis: Codable {
        let resultingRevision: MutationPortableExpectedRevisionV1
        let postImages: [MutationPostImageV1]
    }
}

extension MutationReceiptV1 {
    /// C17 projection input is an immutable view of accepted journal receipts.
    /// Keep its bound equal to the integration/checkpoint limit so a caller
    /// cannot turn the derived projection into an unbounded history reader.
    static let maximumAcceptedProjectionCount =
        ChangeJournalLimitsV1.productionMaximumEntitiesPerCheckpoint

    /// Validates and orders accepted receipts using the same ordering basis as
    /// `IntegrationEventProjectionV1`. This helper only reads and validates
    /// receipt values; it never creates or changes canonical mutation truth.
    static func orderedAcceptedProjectionReceipts(
        _ receipts: [MutationReceiptV1],
        workspaceID: WorkspaceID? = nil
    ) throws -> [MutationReceiptV1] {
        try IntegrationEventJournalCoverageV1().validate()
        guard receipts.count <= Self.maximumAcceptedProjectionCount else {
            throw ChangeJournalFailureV1.limitExceeded
        }

        for receipt in receipts {
            try receipt.validate()
            if let workspaceID, receipt.identity.workspaceID != workspaceID {
                throw ChangeJournalFailureV1.wrongWorkspace
            }
        }

        let ordered = receipts.sorted { lhs, rhs in
            if lhs.resultingRevision.workspaceRevision != rhs.resultingRevision.workspaceRevision {
                return lhs.resultingRevision.workspaceRevision < rhs.resultingRevision.workspaceRevision
            }
            if lhs.identity.stableKey != rhs.identity.stableKey {
                return lhs.identity.stableKey < rhs.identity.stableKey
            }
            return lhs.mutationID.rawValue.uuidString.lowercased()
                < rhs.mutationID.rawValue.uuidString.lowercased()
        }

        var receiptIdentities = Set<MutationReceiptIdentityV1>()
        var mutationKeys = Set<String>()
        var workspaceRevisions = Set<UInt64>()
        for receipt in ordered {
            guard receiptIdentities.insert(receipt.identity).inserted,
                  mutationKeys.insert(
                    MutationWorkspaceKeyV1.value(
                        workspaceID: receipt.identity.workspaceID,
                        mutationID: receipt.mutationID
                    )
                  ).inserted else {
                throw ChangeJournalFailureV1.duplicateValue
            }
            guard workspaceRevisions.insert(receipt.resultingRevision.workspaceRevision).inserted else {
                throw ChangeJournalFailureV1.duplicateValue
            }
        }
        return ordered
    }
}

/// A typed C39 receipt envelope around the journal-owned receipt.  The
/// journal remains the only durable receipt writer; this value merely binds
/// the receipt back to the exact preview plan and the single Asset identity.
struct AssetSemanticsChangeReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let planSHA256: String
    let mutationReceipt: MutationReceiptV1
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let affectedIdentity: WorkspaceEntityIdentityV1
    let committedAt: Date
    let receiptSHA256: String

    init(
        plan: AssetSemanticsChangePlanV1,
        mutationReceipt: MutationReceiptV1
    ) throws {
        try plan.validate()
        try mutationReceipt.validate()
        let identity = try plan.basis.mutation.affectedIdentity
        let expected = try MutationPortableExpectedRevisionV1(
            plan.basis.expectedRevision
        )
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expected.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let commandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyAssetSemantics(plan.basis.mutation)
        )
        guard mutationReceipt.mutationID == plan.mutationID,
              mutationReceipt.identity.workspaceID == plan.basis.workspaceID,
              mutationReceipt.expectedRevision == expected,
              mutationReceipt.commandBodySHA256 == commandBodySHA256,
              mutationReceipt.sourceKind == .localUser,
              let expectedEntityRevision = expectedByIdentity[identity],
              expected.workspaceRevision < UInt64.max,
              expectedEntityRevision < UInt64.max,
              mutationReceipt.resultingRevision.workspaceRevision
                  == expected.workspaceRevision + 1,
              mutationReceipt.resultingRevision.entityRevisions.contains(
                  where: {
                      $0.identity == identity
                          && $0.revision == expectedEntityRevision + 1
                  }
              ),
              mutationReceipt.postImages.count == 1,
              let postImage = mutationReceipt.postImages.first,
              (try? postImage.identity) == identity,
              postImage.revision == expectedEntityRevision + 1 else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }

        schemaVersion = Self.schemaVersion
        planSHA256 = plan.planSHA256
        self.mutationReceipt = mutationReceipt
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        affectedIdentity = identity
        committedAt = mutationReceipt.committedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                planSHA256: plan.planSHA256,
                mutationReceiptIdentity: mutationReceipt.identity,
                mutationReceiptSHA256: mutationReceiptSHA256,
                affectedIdentity: identity,
                committedAt: committedAt
            )
        )
    }

    func validate() throws {
        try mutationReceipt.validate()
        let resultingRevision = mutationReceipt.resultingRevision.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        let postImage = mutationReceipt.postImages.first
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(planSHA256),
              mutationReceipt.identity == mutationReceiptIdentity,
              mutationReceiptSHA256 == (try mutationReceipt.canonicalSHA256()),
              mutationReceipt.sourceKind == .localUser,
              mutationReceipt.postImages.count == 1,
              let postImage,
              (try? postImage.identity) == affectedIdentity,
              resultingRevision == postImage.revision,
              committedAt == mutationReceipt.committedAt,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      planSHA256: planSHA256,
                      mutationReceiptIdentity: mutationReceiptIdentity,
                      mutationReceiptSHA256: mutationReceiptSHA256,
                      affectedIdentity: affectedIdentity,
                      committedAt: committedAt
                  )
              )),
              committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let planSHA256: String
        let mutationReceiptIdentity: MutationReceiptIdentityV1
        let mutationReceiptSHA256: String
        let affectedIdentity: WorkspaceEntityIdentityV1
        let committedAt: Date
    }
}

extension AuthorityCriterionMutationPayloadV1 {
    var mutationPostImage: MutationPostImageV1 {
        get throws {
            let concurrencyIdentity = try predecessorIdentity ?? affectedIdentity
            switch self {
            case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v):
                .authoritySourceRelease(id: v.releaseID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.releaseSHA256)
            case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v):
                .requirementBasisBinding(id: v.bindingID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.bindingSHA256)
            case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v):
                .applicabilityContextSnapshot(id: v.snapshotID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.snapshotSHA256)
            case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v):
                .assessmentScopeSnapshot(id: v.snapshotID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.snapshotSHA256)
            case let .appendSeverityScale(v), let .supersedeSeverityScale(v):
                .severityScaleRelease(id: v.releaseID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.releaseSHA256)
            case let .appendFindingClassification(v), let .supersedeFindingClassification(v):
                .findingClassificationBinding(id: v.bindingID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.bindingSHA256)
            case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v):
                .measurementProtocolRelease(id: v.releaseID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.releaseSHA256)
            case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v):
                .derivedFactEvaluatorDescriptor(id: v.descriptorID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.descriptorSHA256)
            case let .appendDerivedFact(v), let .supersedeDerivedFact(v):
                .derivedFactProvenance(id: v.provenanceID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.provenanceSHA256)
            }
        }
    }
}

extension FunctionalRelationshipMutationPayloadV1 {
    var mutationPostImage: MutationPostImageV1 {
        get throws {
            let concurrencyIdentity = try predecessorIdentity ?? affectedIdentity
            switch self {
            case let .appendDescriptor(v), let .supersedeDescriptor(v):
                .functionalRelationshipTypeDescriptor(
                    id: v.descriptorReleaseID,
                    concurrencyIdentity: concurrencyIdentity,
                    revision: v.revision,
                    semanticSHA256: v.descriptorSHA256
                )
            case let .addRelationship(v), let .endRelationship(v), let .supersedeRelationship(v):
                .assetFunctionalRelationshipEvent(
                    id: v.eventID,
                    relationshipID: v.relationshipID,
                    concurrencyIdentity: concurrencyIdentity,
                    revision: v.revision,
                    semanticSHA256: v.eventSHA256
                )
            }
        }
    }
}

extension EvidenceAssuranceMutationPayloadV1 {
    var mutationPostImage:MutationPostImageV1 { get throws { let c=try predecessorIdentity ?? affectedIdentity;switch self{case let .appendVisibility(v),let .supersedeVisibility(v):.evidenceVisibility(id:v.visibilityID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.visibilitySHA256);case let .appendLink(v),let .supersedeLink(v):.claimEvidenceLink(id:v.linkID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.linkSHA256);case let .appendManifest(v,_),let .supersedeManifest(v,_):.assuranceManifest(id:v.manifestID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.manifestSHA256);case let .recordAttestation(v,_),let .supersedeAttestation(v,_),let .voidAttestation(v,_):.attestation(id:v.attestationID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.attestationSHA256)} } }
}
extension InspectionReviewMutationPayloadV1{var mutationPostImages:[MutationPostImageV1]{get throws{var images:[MutationPostImageV1]=[];switch self{case let .applyReviewBundle(b):let t=b.transition;let ti=try WorkspaceEntityIdentityV1(kind:.inspectionReviewTransition,id:t.predecessorTransitionID ?? t.transitionID);images.append(.inspectionReviewTransition(id:t.transitionID,concurrencyIdentity:ti,revision:t.revision,semanticSHA256:t.transitionSHA256));if let d=b.disposition{let di=try WorkspaceEntityIdentityV1(kind:.reviewDisposition,id:d.supersedesDispositionID ?? d.dispositionID);images.append(.reviewDisposition(id:d.dispositionID,concurrencyIdentity:di,revision:d.revision,semanticSHA256:d.dispositionSHA256))};for r in b.changeRequests{let ri=try WorkspaceEntityIdentityV1(kind:.changeRequest,id:r.supersedesRequestRevisionID ?? r.requestRevisionID);images.append(.changeRequest(id:r.requestRevisionID,concurrencyIdentity:ri,revision:r.revision,semanticSHA256:r.requestSHA256))};case let .appendCorrectivePolicy(v),let .supersedeCorrectivePolicy(v):let c=try predecessorIdentity ?? affectedIdentities[0];images=[.correctiveActionPolicy(id:v.releaseID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.policySHA256)];case let .appendCorrectiveEvent(v),let .appendCorrectiveEventSuccessor(v):let c=try predecessorIdentity ?? affectedIdentities[0];images=[.correctiveActionEvent(id:v.eventID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.eventSHA256)]};return try images.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}var mutationPostImage:MutationPostImageV1{get throws{let values=try mutationPostImages;guard values.count==1,let value=values.first else{throw WorkspaceMutationFailureV1.invalidCommand};return value}}}

extension WorkPacketMutationPayloadV1{var mutationPostImage:MutationPostImageV1{get throws{let c=try predecessorIdentity ?? affectedIdentity;switch self{case let .appendManifest(v):.workPacketManifest(id:v.manifestID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.manifestSHA256);case let .appendClaim(v),let .supersedeClaim(v):.workItemClaim(id:v.claimID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.claimSHA256);case let .appendLease(v),let .supersedeLease(v):.workLease(id:v.leaseID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.leaseSHA256);case let .recordRelease(v):.workRelease(id:v.releaseID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.releaseSHA256);case let .recordHandoff(v):.workHandoff(id:v.handoffID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.handoffSHA256)}}}}
extension FieldDraftMutationPayloadV1{var mutationPostImages:[MutationPostImageV1]{get throws{let images:[MutationPostImageV1];switch self{case let .createCheckpoint(v),let .reviseCheckpoint(v):let c=try predecessorIdentity ?? affectedIdentities[0];images=[.fieldDraftCheckpoint(id:v.draftID,concurrencyIdentity:c,revision:v.draftRevision,semanticSHA256:v.checkpointSHA256)];case let .appendStagingItem(v),let .reviseStagingItem(v):let c=try predecessorIdentity ?? affectedIdentities[0];images=[.attachmentStagingItem(id:v.stageID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.stageSHA256)];case let .appendCommitSaga(v),let .advanceCommitSaga(v):let c=try predecessorIdentity ?? affectedIdentities[0];images=[.draftCommitSaga(id:v.sagaID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.sagaSHA256)];case let .appendContentReservation(v),let .reviseContentReservation(v):let c=try predecessorIdentity ?? affectedIdentities[0];images=[.draftContentReservation(id:v.reservationID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.reservationSHA256)];case let .applyCommitTerminal(v,_):guard let predecessor=v.retiredSaga.predecessorSagaID else{throw WorkspaceMutationFailureV1.invalidCommand};images=[.draftCommitSaga(id:v.retiredSaga.sagaID,concurrencyIdentity:try .init(kind:.draftCommitSaga,id:predecessor),revision:v.retiredSaga.revision,semanticSHA256:v.retiredSaga.sagaSHA256),.fieldDraftCheckpoint(id:v.committedCheckpoint.draftID,concurrencyIdentity:try .init(kind:.fieldDraftCheckpoint,id:v.committedCheckpoint.draftID),revision:v.committedCheckpoint.draftRevision,semanticSHA256:v.committedCheckpoint.checkpointSHA256),.draftCommitReceipt(id:v.receipt.receiptID,concurrencyIdentity:try .init(kind:.draftCommitReceipt,id:v.receipt.receiptID),revision:v.receipt.revision,semanticSHA256:v.receipt.receiptSHA256)];case let .applyDiscardTerminal(v):images=[.fieldDraftCheckpoint(id:v.discardedCheckpoint.draftID,concurrencyIdentity:try .init(kind:.fieldDraftCheckpoint,id:v.discardedCheckpoint.draftID),revision:v.discardedCheckpoint.draftRevision,semanticSHA256:v.discardedCheckpoint.checkpointSHA256),.draftDiscardReceipt(id:v.receipt.receiptID,concurrencyIdentity:try .init(kind:.draftDiscardReceipt,id:v.receipt.receiptID),revision:v.receipt.revision,semanticSHA256:v.receipt.receiptSHA256)]};return try images.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}var mutationPostImage:MutationPostImageV1{get throws{let values=try mutationPostImages;guard values.count==1,let value=values.first else{throw WorkspaceMutationFailureV1.invalidCommand};return value}}}
extension PackagePromotionMutationV1{var mutationPostImages:[MutationPostImageV1]{get throws{let identities=try affectedIdentities,concurrency=try concurrencyIdentities;func c(_ kind:WorkspaceEntityKindV1)throws->WorkspaceEntityIdentityV1{guard let value=concurrency.first(where:{$0.kind==kind})else{throw WorkspaceMutationFailureV1.invalidCommand};return value};let values:[MutationPostImageV1]=[.promotedPackageRelease(id:promotedRelease.releaseRecordID,concurrencyIdentity:try c(.promotedPackageRelease),revision:promotedRelease.revision,semanticSHA256:promotedRelease.releaseRecordSHA256),.packageSandboxRun(id:sandboxRun.runID,concurrencyIdentity:try c(.packageSandboxRun),revision:sandboxRun.revision,semanticSHA256:sandboxRun.runSHA256),.packagePromotionReceipt(id:receipt.receiptID,concurrencyIdentity:try c(.packagePromotionReceipt),revision:receipt.revision,semanticSHA256:receipt.receiptSHA256),.activePackageRegistryPointer(id:resultingPointer.pointerID,concurrencyIdentity:try c(.activePackageRegistryPointer),revision:resultingPointer.revision,semanticSHA256:resultingPointer.pointerSHA256)];guard try values.map({try $0.identity})==identities else{throw WorkspaceMutationFailureV1.invalidCommand};return values}}}
extension MeasurementIntegrityMutationPayloadV1{var mutationPostImage:MutationPostImageV1{get throws{let c=try predecessorIdentity ?? identity;switch self{case let .instrument(v):return .instrumentReference(id:v.referenceID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.referenceSHA256);case let .calibration(v):return .calibrationStatusSnapshot(id:v.snapshotID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.snapshotSHA256);case let .capture(v):return .measurementCapture(id:v.captureID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.captureSHA256);case let .series(v):return .measurementSeries(id:v.snapshotID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.seriesSHA256);case let .quality(v):return .measurementQualityAssessment(id:v.assessmentID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.assessmentSHA256)}}}}
extension MeasurementIntegrityMutationV1{var mutationPostImages:[MutationPostImageV1]{get throws{try bundle.mutationPayloads.map{try $0.mutationPostImage}.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}}
extension PrivacyTransformMutationV1{var mutationPostImages:[MutationPostImageV1]{get throws{let values:[MutationPostImageV1];switch self{case let .policy(value):values=[try .privacyTransformPolicy(id:value.policyID,concurrencyIdentity:.init(kind:.privacyTransformPolicy,id:value.supersedesPolicyID ?? value.policyID),revision:value.revision,semanticSHA256:value.policySHA256)];case let .publish(_,regions,manifest):values=try [.privacyTransformManifest(id:manifest.manifestID,concurrencyIdentity:.init(kind:.privacyTransformManifest,id:manifest.supersedesManifestID ?? manifest.manifestID),revision:manifest.revision,semanticSHA256:manifest.manifestSHA256)]+regions.map{try .privacyRegion(id:$0.regionID,concurrencyIdentity:.init(kind:.privacyRegion,id:$0.regionID),revision:$0.revision,semanticSHA256:$0.regionSHA256)};case let .review(value,_,_):values=[try .privacyReviewReceipt(id:value.receiptID,concurrencyIdentity:.init(kind:.privacyReviewReceipt,id:value.supersedesReceiptID ?? value.receiptID),revision:value.revision,semanticSHA256:value.receiptSHA256)]};return try values.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}}
extension ClientCapabilityMutationV1{var mutationPostImage:MutationPostImageV1{get throws{let c=try concurrencyIdentity;switch self{case let .profile(v):return .clientCapabilityProfile(id:v.profileID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.profileSHA256);case let .policy(v,_):return .packageLifecyclePolicy(id:v.policyID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.policySHA256);case let .disposition(v,_):return .packageLifecycleDisposition(id:v.dispositionID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.dispositionSHA256);case let .admission(v,_,_,_,_):return .clientCapabilityAdmissionDecision(id:v.decisionID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.decisionSHA256)}}}}
extension FieldReferenceMutationV1{var mutationPostImage:MutationPostImageV1{get throws{let c=try concurrencyIdentity;switch self{case let .importRelease(v):return .fieldReferenceRelease(id:v.releaseID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.releaseSHA256);case let .bind(v,_):return .fieldReferenceBinding(id:v.bindingID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.bindingSHA256)}}}}
extension AccessibleDocumentMutationV1{var mutationPostImage:MutationPostImageV1{get throws{try .accessibleDocumentAssessmentReceipt(id:receipt.receiptID,concurrencyIdentity:concurrencyIdentity,revision:receipt.revision,semanticSHA256:receipt.receiptSHA256)}}}
extension SurveyDefinitionMutationV1 {
    var mutationPostImages: [MutationPostImageV1] { get throws {
        let concurrency = try concurrencyIdentities
        guard let identityConcurrency = concurrency.first(where: { $0.kind == .surveyDefinitionIdentity }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        var values:[MutationPostImageV1] = [.surveyDefinitionIdentity(id: identity.definitionID, concurrencyIdentity: identityConcurrency, revision: identity.revision, semanticSHA256: identity.identitySHA256)]
        if appendsRelease {
            guard let releaseConcurrency = concurrency.first(where: { $0.kind == .surveyDefinitionRelease }) else { throw WorkspaceMutationFailureV1.invalidCommand }
            values.append(.surveyDefinitionRelease(id: release.releaseID, concurrencyIdentity: releaseConcurrency, revision: release.revision, semanticSHA256: release.releaseSHA256))
        }
        return try values.sorted { try $0.identity.stableKey < $1.identity.stableKey }
    } }
}

extension SurveySessionMutationV1 {
    var mutationPostImages:[MutationPostImageV1]{get throws{let c=try concurrencyIdentities;func id(_ kind:WorkspaceEntityKindV1)throws->WorkspaceEntityIdentityV1{guard let v=c.first(where:{$0.kind==kind})else{throw WorkspaceMutationFailureV1.invalidCommand};return v};let values:[MutationPostImageV1];switch payload{
    case let .applySession(v,_,_):values=[.surveySession(id:v.sessionID,concurrencyIdentity:try id(.surveySession),revision:v.revision,semanticSHA256:v.sessionSHA256)]
    case let .captureFact(v,_,_,_):values=[.factCapture(id:v.captureID,concurrencyIdentity:try id(.factCapture),revision:v.revision,semanticSHA256:v.captureSHA256)]
    case let .applyProvisionalSubject(v):values=[.provisionalSubject(id:v.provisionalSubjectID,concurrencyIdentity:try id(.provisionalSubject),revision:v.revision,semanticSHA256:v.subjectSHA256)]
    case let .promoteSubject(v,r,_,_):values=[.provisionalSubject(id:v.provisionalSubjectID,concurrencyIdentity:try id(.provisionalSubject),revision:v.revision,semanticSHA256:v.subjectSHA256),.subjectPromotionReceipt(id:r.receiptID,concurrencyIdentity:try id(.subjectPromotionReceipt),revision:r.revision,semanticSHA256:r.receiptSHA256)]
    case let .publish(s,p,_,_):values=[.surveySession(id:s.sessionID,concurrencyIdentity:try id(.surveySession),revision:s.revision,semanticSHA256:s.sessionSHA256),.surveyPublicationSnapshot(id:p.snapshotID,concurrencyIdentity:try id(.surveyPublicationSnapshot),revision:p.revision,semanticSHA256:p.snapshotSHA256)]};return try values.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}
}

struct SurveySessionMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;init(mutation:SurveySessionMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applySurveySession(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{row in row.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try image.identity)})?.revision==image.revision}),affected==images.compactMap{try? $0.identity} else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try WorkspaceMutationCanonicalV1.sha256(mutation);self.mutationReceipt=mutationReceipt}}

struct TemporalEvidenceMutationReceiptV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let receiptSHA256:String
    init(mutation:TemporalEvidenceMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages,resulting=Dictionary(uniqueKeysWithValues:mutationReceipt.resultingRevision.entityRevisions.map{($0.identity,$0.revision)});guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyTemporalEvidence(mutation))),mutationReceipt.postImages==images,mutationReceipt.expectedRevision.workspaceID==mutation.expectedRevision.workspaceID,mutationReceipt.expectedRevision.generationID==mutation.expectedRevision.generationID,mutationReceipt.expectedRevision.writerInstanceID==mutation.expectedRevision.writerInstanceID,mutationReceipt.expectedRevision.workspaceRevision==mutation.expectedRevision.workspaceRevision,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision==(try mutation.expectedRevision(for:identity))}),try images.allSatisfy({resulting[try $0.identity]==$0.revision}),affected==images.compactMap({try? $0.identity})else{throw WorkspaceMutationFailureV1.invalidReceipt};schemaVersion=Self.schemaVersion;mutationSHA256=try WorkspaceMutationCanonicalV1.sha256(mutation);self.mutationReceipt=mutationReceipt;receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,mutationSHA256:mutationSHA256,mutationReceiptSHA256:WorkspaceMutationCanonicalV1.sha256(mutationReceipt)))}
    func validate(mutation:TemporalEvidenceMutationV1)throws{let expected=try Self(mutation:mutation,mutationReceipt:mutationReceipt);guard expected==self else{throw WorkspaceMutationFailureV1.invalidReceipt}}
    private struct Basis:Codable{let schemaVersion:Int;let mutationSHA256,mutationReceiptSHA256:String}
}

extension AssetLocatorMutationV1{var mutationPostImages:[MutationPostImageV1]{get throws{let concurrency=try concurrencyIdentities;func c(_ kind:WorkspaceEntityKindV1,_ id:UUID)throws->WorkspaceEntityIdentityV1{guard let value=concurrency.first(where:{$0.kind==kind&&$0.id==id}) ?? (kind == .locatorBindingReceipt ? concurrency.first(where:{$0.kind==kind}):nil)else{throw WorkspaceMutationFailureV1.invalidCommand};return value};let values:[MutationPostImageV1];switch payload{case let .bind(locator,receipt,_):values=[.assetLocator(id:locator.locatorID,concurrencyIdentity:try c(.assetLocator,locator.locatorID),revision:locator.revision,semanticSHA256:locator.locatorSHA256),.locatorBindingReceipt(id:receipt.receiptID,concurrencyIdentity:try c(.locatorBindingReceipt,receipt.receiptID),revision:receipt.revision,semanticSHA256:receipt.receiptSHA256)];case let .transition(locator,receipt,prior,_):values=[.assetLocator(id:locator.locatorID,concurrencyIdentity:try c(.assetLocator,prior.locatorID),revision:locator.revision,semanticSHA256:locator.locatorSHA256),.locatorBindingReceipt(id:receipt.receiptID,concurrencyIdentity:try c(.locatorBindingReceipt,receipt.receiptID),revision:receipt.revision,semanticSHA256:receipt.receiptSHA256)];case let .replace(locator,replacement,receipt,prior,_):values=[.assetLocator(id:locator.locatorID,concurrencyIdentity:try c(.assetLocator,prior.locatorID),revision:locator.revision,semanticSHA256:locator.locatorSHA256),.assetLocator(id:replacement.locatorID,concurrencyIdentity:try c(.assetLocator,replacement.locatorID),revision:replacement.revision,semanticSHA256:replacement.locatorSHA256),.locatorBindingReceipt(id:receipt.receiptID,concurrencyIdentity:try c(.locatorBindingReceipt,receipt.receiptID),revision:receipt.revision,semanticSHA256:receipt.receiptSHA256)]};return try values.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}}
struct AssetLocatorMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;init(mutation:AssetLocatorMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages,resulting=Dictionary(uniqueKeysWithValues:mutationReceipt.resultingRevision.entityRevisions.map{($0.identity,$0.revision)});guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyAssetLocator(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{row in row.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in resulting[try image.identity]==image.revision}),affected==images.compactMap({try? $0.identity})else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try WorkspaceMutationCanonicalV1.sha256(mutation);self.mutationReceipt=mutationReceipt}}

extension ScheduleMutationV1{var mutationPostImages:[MutationPostImageV1]{get throws{let concurrency=try concurrencyIdentities;func c(_ kind:WorkspaceEntityKindV1,_ id:UUID)throws->WorkspaceEntityIdentityV1{guard let value=concurrency.first(where:{$0.kind==kind&&$0.id==id}) ?? concurrency.first(where:{$0.kind==kind})else{throw WorkspaceMutationFailureV1.invalidCommand};return value};let values:[MutationPostImageV1];switch payload{case let .appendRelease(value,_):values=[.scheduleDefinitionRelease(id:value.releaseID,concurrencyIdentity:try c(.scheduleDefinitionRelease,value.releaseID),revision:value.revision,semanticSHA256:value.releaseSHA256)];case let .appendOccurrenceEvent(value,_,_),let .startOccurrence(value,_,_):values=[.occurrenceHistoryEvent(id:value.eventID,concurrencyIdentity:try c(.occurrenceHistoryEvent,value.eventID),revision:value.revision,semanticSHA256:value.eventSHA256)];case let .generateOccurrences(_,_,events):values=try events.map{.occurrenceHistoryEvent(id:$0.eventID,concurrencyIdentity:try c(.occurrenceHistoryEvent,$0.eventID),revision:$0.revision,semanticSHA256:$0.eventSHA256)}};return try values.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}}
struct ScheduleMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;init(mutation:ScheduleMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages,resulting=Dictionary(uniqueKeysWithValues:mutationReceipt.resultingRevision.entityRevisions.map{($0.identity,$0.revision)});guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applySchedule(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{row in row.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in resulting[try image.identity]==image.revision}),affected==images.compactMap({try? $0.identity})else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try WorkspaceMutationCanonicalV1.sha256(mutation);self.mutationReceipt=mutationReceipt}}

/// Typed C40 receipt binding the journal-owned receipt to the exact canonical
/// authority/criterion post-image. It does not introduce a second receipt
/// writer or infer authority meaning from the persisted scalar fields.
struct AuthorityCriterionMutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let mutationSHA256: String
    let mutationReceipt: MutationReceiptV1
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let affectedIdentity: WorkspaceEntityIdentityV1
    let predecessorIdentity: WorkspaceEntityIdentityV1?
    let concurrencyIdentity: WorkspaceEntityIdentityV1
    let postImageSHA256: String
    let committedAt: Date
    let receiptSHA256: String

    init(
        mutation: AuthorityCriterionMutationV1,
        mutationReceipt: MutationReceiptV1
    ) throws {
        try mutation.validate()
        try mutationReceipt.validate()
        let affectedIdentity = try mutation.affectedIdentity
        let predecessorIdentity = try mutation.postImage.predecessorIdentity
        let concurrencyIdentity = try mutation.concurrencyIdentity
        let commandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyAuthorityCriterion(mutation)
        )
        let expectedEntityRevision = mutationReceipt.expectedRevision.entityRevisions
            .first(where: { $0.identity == concurrencyIdentity })?.revision
        let resultingEntityRevision = mutationReceipt.resultingRevision.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        let expectedPostImage = try mutation.postImage.mutationPostImage
        guard mutationReceipt.mutationID == mutation.mutationID,
              mutationReceipt.identity.workspaceID == mutation.workspaceID,
              mutationReceipt.commandBodySHA256 == commandBodySHA256,
              mutationReceipt.sourceKind == .localUser,
              expectedEntityRevision == mutation.expectedRevision,
              resultingEntityRevision == mutation.postImage.revision,
              mutationReceipt.postImages == [expectedPostImage] else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }

        schemaVersion = Self.schemaVersion
        mutationSHA256 = try mutation.canonicalSHA256()
        self.mutationReceipt = mutationReceipt
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        self.affectedIdentity = affectedIdentity
        self.predecessorIdentity = predecessorIdentity
        self.concurrencyIdentity = concurrencyIdentity
        postImageSHA256 = mutation.postImage.semanticSHA256
        committedAt = mutationReceipt.committedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                mutationSHA256: mutationSHA256,
                mutationReceiptIdentity: mutationReceipt.identity,
                mutationReceiptSHA256: mutationReceiptSHA256,
                affectedIdentity: affectedIdentity,
                predecessorIdentity: predecessorIdentity,
                concurrencyIdentity: concurrencyIdentity,
                postImageSHA256: postImageSHA256,
                committedAt: committedAt
            )
        )
    }

    func validate() throws {
        try mutationReceipt.validate()
        let expectedConcurrencyRevision = mutationReceipt.expectedRevision.entityRevisions
            .first(where: { $0.identity == concurrencyIdentity })?.revision
        let resultingAffectedRevision = mutationReceipt.resultingRevision.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        let validRevisionBinding: Bool
        if predecessorIdentity == nil {
            validRevisionBinding = expectedConcurrencyRevision == 0
                && mutationReceipt.postImages.first?.revision == 1
        } else {
            validRevisionBinding = expectedConcurrencyRevision.map {
                $0 > 0 && $0 < UInt64.max
                    && mutationReceipt.postImages.first?.revision == $0 + 1
            } == true
        }
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(mutationSHA256),
              mutationReceipt.identity == mutationReceiptIdentity,
              mutationReceiptSHA256 == (try mutationReceipt.canonicalSHA256()),
              mutationReceipt.sourceKind == .localUser,
              mutationReceipt.postImages.count == 1,
              let postImage = mutationReceipt.postImages.first,
              (try? postImage.identity) == affectedIdentity,
              (try? postImage.concurrencyIdentity) == concurrencyIdentity,
              (predecessorIdentity ?? affectedIdentity) == concurrencyIdentity,
              predecessorIdentity.map({ $0 != affectedIdentity }) ?? true,
              validRevisionBinding,
              resultingAffectedRevision == postImage.revision,
              postImage.semanticSHA256 == postImageSHA256,
              MutationEnvelopeV1.isSHA256(postImageSHA256),
              committedAt == mutationReceipt.committedAt,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                DigestBasis(
                    schemaVersion: schemaVersion,
                    mutationSHA256: mutationSHA256,
                    mutationReceiptIdentity: mutationReceiptIdentity,
                    mutationReceiptSHA256: mutationReceiptSHA256,
                    affectedIdentity: affectedIdentity,
                    predecessorIdentity: predecessorIdentity,
                    concurrencyIdentity: concurrencyIdentity,
                    postImageSHA256: postImageSHA256,
                    committedAt: committedAt
                )
              )),
              committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let mutationSHA256: String
        let mutationReceiptIdentity: MutationReceiptIdentityV1
        let mutationReceiptSHA256: String
        let affectedIdentity: WorkspaceEntityIdentityV1
        let predecessorIdentity: WorkspaceEntityIdentityV1?
        let concurrencyIdentity: WorkspaceEntityIdentityV1
        let postImageSHA256: String
        let committedAt: Date
    }
}

struct FunctionalRelationshipMutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let mutationSHA256: String
    let mutationReceipt: MutationReceiptV1
    let affectedIdentity: WorkspaceEntityIdentityV1
    let predecessorIdentity: WorkspaceEntityIdentityV1?
    let concurrencyIdentity: WorkspaceEntityIdentityV1
    let postImageSHA256: String
    let receiptSHA256: String

    init(mutation: FunctionalRelationshipMutationV1, mutationReceipt: MutationReceiptV1) throws {
        try mutation.validate(); try mutationReceipt.validate()
        let affected = try mutation.affectedIdentity
        let predecessor = try mutation.postImage.predecessorIdentity
        let concurrency = try mutation.concurrencyIdentity
        let postImage = try mutation.postImage.mutationPostImage
        guard mutationReceipt.mutationID == mutation.mutationID,
              mutationReceipt.identity.workspaceID == mutation.workspaceID,
              mutationReceipt.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyFunctionalRelationship(mutation))),
              mutationReceipt.expectedRevision.entityRevisions.first(where: { $0.identity == concurrency })?.revision == mutation.expectedRevision,
              mutationReceipt.resultingRevision.entityRevisions.first(where: { $0.identity == affected })?.revision == mutation.postImage.revision,
              mutationReceipt.postImages == [postImage] else { throw WorkspaceMutationFailureV1.invalidReceipt }
        schemaVersion = Self.schemaVersion
        mutationSHA256 = try mutation.canonicalSHA256()
        self.mutationReceipt = mutationReceipt
        affectedIdentity = affected; predecessorIdentity = predecessor; concurrencyIdentity = concurrency
        postImageSHA256 = mutation.postImage.semanticSHA256
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, mutationSHA256: mutationSHA256,
            mutationReceiptSHA256: mutationReceipt.canonicalSHA256(), affectedIdentity: affected,
            predecessorIdentity: predecessor, concurrencyIdentity: concurrency,
            postImageSHA256: postImageSHA256
        ))
    }

    func validate() throws {
        try mutationReceipt.validate()
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(mutationSHA256),
              mutationReceipt.postImages.count == 1,
              let postImage = mutationReceipt.postImages.first,
              (try postImage.identity) == affectedIdentity,
              (try postImage.concurrencyIdentity) == concurrencyIdentity,
              (predecessorIdentity ?? affectedIdentity) == concurrencyIdentity,
              postImage.semanticSHA256 == postImageSHA256,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
                schemaVersion: schemaVersion, mutationSHA256: mutationSHA256,
                mutationReceiptSHA256: mutationReceipt.canonicalSHA256(), affectedIdentity: affectedIdentity,
                predecessorIdentity: predecessorIdentity, concurrencyIdentity: concurrencyIdentity,
                postImageSHA256: postImageSHA256
              ))) else { throw WorkspaceMutationFailureV1.invalidReceipt }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let mutationSHA256: String; let mutationReceiptSHA256: String
        let affectedIdentity: WorkspaceEntityIdentityV1; let predecessorIdentity: WorkspaceEntityIdentityV1?
        let concurrencyIdentity: WorkspaceEntityIdentityV1; let postImageSHA256: String
    }
}

struct EvidenceAssuranceMutationReceiptV1:Codable,Equatable,Sendable{
    let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentity:WorkspaceEntityIdentityV1;let predecessorIdentity:WorkspaceEntityIdentityV1?;let concurrencyIdentity:WorkspaceEntityIdentityV1;let postImageSHA256:String
    init(mutation:EvidenceAssuranceMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let a=try mutation.affectedIdentity;let p=try mutation.postImage.predecessorIdentity;let c=try mutation.concurrencyIdentity;let image=try mutation.postImage.mutationPostImage;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyEvidenceAssurance(mutation))),mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==c})?.revision==mutation.expectedRevision,mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==a})?.revision==mutation.postImage.revision,mutationReceipt.postImages==[image]else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt;affectedIdentity=a;predecessorIdentity=p;concurrencyIdentity=c;postImageSHA256=mutation.postImage.semanticSHA256}
    func validate()throws{try mutationReceipt.validate();guard MutationEnvelopeV1.isSHA256(mutationSHA256),mutationReceipt.postImages.count==1,let image=mutationReceipt.postImages.first,(try image.identity)==affectedIdentity,(try image.concurrencyIdentity)==concurrencyIdentity,(predecessorIdentity ?? affectedIdentity)==concurrencyIdentity,image.semanticSHA256==postImageSHA256 else{throw WorkspaceMutationFailureV1.invalidReceipt}}
}
struct InspectionReviewMutationReceiptV1:Codable,Equatable,Sendable{
    let mutationSHA256:String
    let mutationReceipt:MutationReceiptV1
    let affectedIdentities:[WorkspaceEntityIdentityV1]
    let concurrencyIdentities:[WorkspaceEntityIdentityV1]
    init(mutation:InspectionReviewMutationV1,mutationReceipt:MutationReceiptV1)throws{
        try mutation.validate();try mutationReceipt.validate()
        let affected=try mutation.affectedIdentities
        let images=try mutation.postImage.mutationPostImages
        let concurrency=try images.map{$0.concurrencyIdentity}.sorted{$0.stableKey<$1.stableKey}
        let expectedRevisions=mutationReceipt.expectedRevision.entityRevisions
        let resultingRevisions=mutationReceipt.resultingRevision.entityRevisions
        guard Set(expectedRevisions.map(\.identity)).count==expectedRevisions.count,
              Set(resultingRevisions.map(\.identity)).count==resultingRevisions.count else{throw WorkspaceMutationFailureV1.invalidReceipt}
        let expected=Dictionary(uniqueKeysWithValues:expectedRevisions.map{($0.identity,$0.revision)})
        let resulting=Dictionary(uniqueKeysWithValues:resultingRevisions.map{($0.identity,$0.revision)})
        guard concurrency==(try mutation.concurrencyIdentities),Set(concurrency).count==concurrency.count,
              mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,
              mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyInspectionReview(mutation))),
              try images.allSatisfy{expected[try $0.concurrencyIdentity]==$0.revision-1&&resulting[try $0.identity]==$0.revision},
              mutationReceipt.postImages==images else{throw WorkspaceMutationFailureV1.invalidReceipt}
        mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt
        affectedIdentities=affected;concurrencyIdentities=concurrency;try validate()
    }
    func validate()throws{
        try mutationReceipt.validate()
        let imageAffected=try mutationReceipt.postImages.map{$0.identity}
        let imageConcurrency=try mutationReceipt.postImages.map{$0.concurrencyIdentity}.sorted{$0.stableKey<$1.stableKey}
        guard MutationEnvelopeV1.isSHA256(mutationSHA256),imageAffected==affectedIdentities,
              affectedIdentities==affectedIdentities.sorted(by:{$0.stableKey<$1.stableKey}),Set(affectedIdentities).count==affectedIdentities.count,
              concurrencyIdentities==imageConcurrency,concurrencyIdentities==concurrencyIdentities.sorted(by:{$0.stableKey<$1.stableKey}),
              Set(concurrencyIdentities).count==concurrencyIdentities.count else{throw WorkspaceMutationFailureV1.invalidReceipt}
    }
}

struct WorkPacketMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentity:WorkspaceEntityIdentityV1;let concurrencyIdentity:WorkspaceEntityIdentityV1;init(mutation:WorkPacketMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let a=try mutation.affectedIdentity;let c=try mutation.concurrencyIdentity;let image=try mutation.postImage.mutationPostImage;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyWorkPacket(mutation))),mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==c})?.revision==mutation.expectedRevision,mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==a})?.revision==mutation.postImage.revision,mutationReceipt.postImages==[image]else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt;affectedIdentity=a;concurrencyIdentity=c}}
struct FieldDraftMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentities:[WorkspaceEntityIdentityV1];let concurrencyIdentities:[WorkspaceEntityIdentityV1];init(mutation:FieldDraftMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.postImage.mutationPostImages;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyFieldDraft(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try image.identity)})?.revision==image.revision})else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt;affectedIdentities=affected;concurrencyIdentities=concurrency}}
struct PackagePromotionMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentities:[WorkspaceEntityIdentityV1];let concurrencyIdentities:[WorkspaceEntityIdentityV1];init(mutation:PackagePromotionMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyPackagePromotion(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try image.identity)})?.revision==image.revision})else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt;affectedIdentities=affected;concurrencyIdentities=concurrency}}
struct MeasurementIntegrityMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentities:[WorkspaceEntityIdentityV1];let concurrencyIdentities:[WorkspaceEntityIdentityV1];init(mutation:MeasurementIntegrityMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyMeasurementIntegrity(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try image.identity)})?.revision==image.revision})else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt;affectedIdentities=affected;concurrencyIdentities=concurrency}}
struct PrivacyTransformMutationReceiptV1:Codable,Equatable,Sendable{
    let mutationSHA256:String
    let mutationReceipt:MutationReceiptV1
    let affectedIdentities:[WorkspaceEntityIdentityV1]
    let concurrencyIdentities:[WorkspaceEntityIdentityV1]
    init(mutation:PrivacyTransformMutationV1,mutationReceipt:MutationReceiptV1)throws{
        try mutation.validate();try mutationReceipt.validate()
        let images=try mutation.mutationPostImages
        let affected=try images.map{$0.identity}.sorted{$0.stableKey<$1.stableKey}
        let concurrency=try images.map{$0.concurrencyIdentity}.sorted{$0.stableKey<$1.stableKey}
        let expected=Dictionary(uniqueKeysWithValues:mutationReceipt.expectedRevision.entityRevisions.map{($0.identity,$0.revision)})
        let resulting=Dictionary(uniqueKeysWithValues:mutationReceipt.resultingRevision.entityRevisions.map{($0.identity,$0.revision)})
        guard affected==(try mutation.affectedIdentities),concurrency==(try mutation.concurrencyIdentities),
              Set(affected).count==affected.count,Set(concurrency).count==concurrency.count,
              Set(expected.keys)==Set(concurrency),
              mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,
              mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyPrivacyTransform(mutation))),
              try concurrency.allSatisfy{expected[$0]==(try mutation.expectedRevision(for:$0))},
              try images.allSatisfy{resulting[try $0.identity]==$0.revision},mutationReceipt.postImages==images else{throw WorkspaceMutationFailureV1.invalidReceipt}
        mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt
        affectedIdentities=affected;concurrencyIdentities=concurrency;try validate()
    }
    func validate()throws{
        try mutationReceipt.validate()
        let imageAffected=try mutationReceipt.postImages.map{$0.identity}.sorted{$0.stableKey<$1.stableKey}
        let imageConcurrency=try mutationReceipt.postImages.map{$0.concurrencyIdentity}.sorted{$0.stableKey<$1.stableKey}
        guard MutationEnvelopeV1.isSHA256(mutationSHA256),affectedIdentities==imageAffected,
              concurrencyIdentities==imageConcurrency,Set(affectedIdentities).count==affectedIdentities.count,
              Set(concurrencyIdentities).count==concurrencyIdentities.count else{throw WorkspaceMutationFailureV1.invalidReceipt}
    }
}
struct ClientCapabilityMutationReceiptV1:Codable,Equatable,Sendable{
    let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentity:WorkspaceEntityIdentityV1;let concurrencyIdentity:WorkspaceEntityIdentityV1
    init(mutation:ClientCapabilityMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentity,concurrency=try mutation.concurrencyIdentity,image=try mutation.mutationPostImage;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyClientCapability(mutation))),mutationReceipt.expectedRevision.entityRevisions.count==1,mutationReceipt.expectedRevision.entityRevisions.first?.identity==concurrency,mutationReceipt.expectedRevision.entityRevisions.first?.revision==mutation.expectedRevision,mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==affected})?.revision==mutation.revision,mutationReceipt.postImages==[image]else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt;affectedIdentity=affected;concurrencyIdentity=concurrency}
}

struct FieldReferenceMutationReceiptV1:Codable,Equatable,Sendable{
    let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentity:WorkspaceEntityIdentityV1;let concurrencyIdentity:WorkspaceEntityIdentityV1
    init(mutation:FieldReferenceMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentity,concurrency=try mutation.concurrencyIdentity,image=try mutation.mutationPostImage;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyFieldReference(mutation))),mutationReceipt.expectedRevision.entityRevisions.count==1,mutationReceipt.expectedRevision.entityRevisions.first?.identity==concurrency,mutationReceipt.expectedRevision.entityRevisions.first?.revision==mutation.expectedRevision,mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==affected})?.revision==mutation.revision,mutationReceipt.postImages==[image]else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt;affectedIdentity=affected;concurrencyIdentity=concurrency}
}
struct AccessibleDocumentMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;init(mutation:AccessibleDocumentMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentity,concurrency=try mutation.concurrencyIdentity,image=try mutation.mutationPostImage;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyAccessibleDocumentAssessment(mutation))),mutationReceipt.expectedRevision.entityRevisions.count==1,mutationReceipt.expectedRevision.entityRevisions.first?.identity==concurrency,mutationReceipt.expectedRevision.entityRevisions.first?.revision==mutation.expectedRevision,mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==affected})?.revision==mutation.revision,mutationReceipt.postImages==[image]else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try mutation.canonicalSHA256();self.mutationReceipt=mutationReceipt}}
struct SurveyDefinitionMutationReceiptV1: Codable, Equatable, Sendable {
    let mutationSHA256: String
    let mutationReceipt: MutationReceiptV1
    let affectedIdentities: [WorkspaceEntityIdentityV1]
    let concurrencyIdentities: [WorkspaceEntityIdentityV1]

    init(mutation: SurveyDefinitionMutationV1, mutationReceipt: MutationReceiptV1) throws {
        try mutation.validate(); try mutationReceipt.validate()
        mutationSHA256 = try mutation.canonicalSHA256()
        self.mutationReceipt = mutationReceipt
        affectedIdentities = try mutation.affectedIdentities
        concurrencyIdentities = try mutation.concurrencyIdentities
        try validate(mutation: mutation)
    }

    func validate(mutation: SurveyDefinitionMutationV1) throws {
        try mutation.validate(); try mutationReceipt.validate()
        let images = try mutation.mutationPostImages
        let expected = Dictionary(uniqueKeysWithValues: mutationReceipt.expectedRevision.entityRevisions.map { ($0.identity, $0.revision) })
        let resulting = Dictionary(uniqueKeysWithValues: mutationReceipt.resultingRevision.entityRevisions.map { ($0.identity, $0.revision) })
        guard mutationSHA256 == (try mutation.canonicalSHA256()),
              mutationReceipt.mutationID == mutation.mutationID,
              mutationReceipt.identity.workspaceID == mutation.workspaceID,
              mutationReceipt.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applySurveyDefinition(mutation))),
              mutationReceipt.postImages == images,
              affectedIdentities == (try mutation.affectedIdentities),
              concurrencyIdentities == (try mutation.concurrencyIdentities),
              try concurrencyIdentities.allSatisfy({ expected[$0] == (try mutation.expectedRevision(for: $0)) }),
              try images.allSatisfy({ resulting[try $0.identity] == $0.revision }) else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }
}

struct MutationHistoryReceiptRecordV1: Codable, Equatable, Sendable {
    let envelopeData: Data
    let receiptData: Data
    let reversalBasisData: Data?
    let semanticReversalData: Data?
}

struct MutationHistoryQuarantineRecordV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: UUID
    let identityDomain: MutationQuarantineIdentityDomainV1
    let acceptedIdentitySHA256: String
    let conflictingIdentitySHA256: String
    let detectedAt: Date
}

struct MutationHistoryEntityRevisionV1: Codable, Equatable, Sendable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let externalProjectionSHA256: String?

    init(
        identity: WorkspaceEntityIdentityV1,
        revision: UInt64,
        externalProjectionSHA256: String? = nil
    ) {
        self.identity = identity
        self.revision = revision
        self.externalProjectionSHA256 = externalProjectionSHA256
    }
}

struct MutationHistorySnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceRevision: UInt64
    let lastLocalSequence: UInt64
    let receipts: [MutationHistoryReceiptRecordV1]
    let quarantines: [MutationHistoryQuarantineRecordV1]
    let entityRevisions: [MutationHistoryEntityRevisionV1]

    init(
        workspaceRevision: UInt64,
        lastLocalSequence: UInt64,
        receipts: [MutationHistoryReceiptRecordV1],
        quarantines: [MutationHistoryQuarantineRecordV1],
        entityRevisions: [MutationHistoryEntityRevisionV1]
    ) {
        schemaVersion = Self.schemaVersion
        self.workspaceRevision = workspaceRevision
        self.lastLocalSequence = lastLocalSequence
        self.receipts = receipts
        self.quarantines = quarantines
        self.entityRevisions = entityRevisions
    }
}

enum MutationHistoryRestoreIdentityV1: Equatable, Sendable {
    case preserve
    case destination(WorkspaceReplicaIdentityV1, generationID: UUID)
}

extension PlanMutationV1{
    var mutationPostImages:[MutationPostImageV1]{get throws{let concurrency=try concurrencyIdentities;func c(_ kind:WorkspaceEntityKindV1,_ id:UUID)throws->WorkspaceEntityIdentityV1{guard let value=concurrency.first(where:{$0.kind==kind&&$0.id==id}) ?? concurrency.first(where:{$0.kind==kind})else{throw WorkspaceMutationFailureV1.invalidCommand};return value};let values:[MutationPostImageV1];switch payload{case let .appendDocument(v,_):values=[.planDocument(id:v.planDocumentID,concurrencyIdentity:try c(.planDocument,v.planDocumentID),revision:v.revision,semanticSHA256:v.documentSHA256)];case let .appendRevision(v,_,_):values=[.planRevision(id:v.planRevisionID,concurrencyIdentity:try c(.planRevision,v.planRevisionID),revision:v.revision,semanticSHA256:v.revisionSHA256)];case let .appendPlacement(v,_,_):values=[.planPlacement(id:v.placementID,concurrencyIdentity:try c(.planPlacement,v.placementID),revision:v.revision,semanticSHA256:v.placementSHA256)];case let .applyRebase(v,_,placements,_,receipt,_,pose):values=[.planRevision(id:v.planRevisionID,concurrencyIdentity:try c(.planRevision,v.planRevisionID),revision:v.revision,semanticSHA256:v.revisionSHA256)]+(try placements.map{.planPlacement(id:$0.placementID,concurrencyIdentity:try c(.planPlacement,$0.placementID),revision:$0.revision,semanticSHA256:$0.placementSHA256)})+[.planRebaseReceipt(id:receipt.receiptID,concurrencyIdentity:try c(.planRebaseReceipt,receipt.receiptID),revision:receipt.revision,semanticSHA256:receipt.receiptSHA256)]+(try pose?.mutationPostImages ?? []);case let .recordRebaseRejection(receipt,_):values=[.planRebaseReceipt(id:receipt.receiptID,concurrencyIdentity:try c(.planRebaseReceipt,receipt.receiptID),revision:receipt.revision,semanticSHA256:receipt.receiptSHA256)]};return try values.sorted{try $0.identity.stableKey<$1.identity.stableKey}}}
}
struct PlanMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentities:[WorkspaceEntityIdentityV1];let concurrencyIdentities:[WorkspaceEntityIdentityV1];init(mutation:PlanMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyPlan(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try image.identity)})?.revision==image.revision})else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try WorkspaceMutationCanonicalV1.sha256(mutation);self.mutationReceipt=mutationReceipt;affectedIdentities=affected;concurrencyIdentities=concurrency}}

extension PlacementPoseMutationV1{
    var mutationPostImages:[MutationPostImageV1]{get throws{let concurrency=try concurrencyIdentities;func c(_ kind:WorkspaceEntityKindV1,_ newID:UUID,_ predecessorID:UUID?)throws->WorkspaceEntityIdentityV1{let id=predecessorID ?? newID;guard let value=concurrency.first(where:{$0.kind==kind&&$0.id==id})else{throw WorkspaceMutationFailureV1.invalidCommand};return value};let eventImages=try zip(events,eventPredecessors).map{value,prior in MutationPostImageV1.assetPoseEvent(id:value.eventID,concurrencyIdentity:try c(.assetPoseEvent,value.eventID,prior?.eventID),revision:value.revision,semanticSHA256:value.eventSHA256)};let observationImages=try zip(observations,observationPredecessors).map{value,prior in MutationPostImageV1.spatialAnchorObservation(id:value.observationID,concurrencyIdentity:try c(.spatialAnchorObservation,value.observationID,prior?.observationID),revision:value.revision,semanticSHA256:value.observationSHA256)};return try (eventImages+observationImages).sorted{try $0.identity.stableKey<$1.identity.stableKey}}
    }
}
struct PlacementPoseMutationReceiptV1:Codable,Equatable,Sendable{let mutationSHA256:String;let mutationReceipt:MutationReceiptV1;let affectedIdentities:[WorkspaceEntityIdentityV1];let concurrencyIdentities:[WorkspaceEntityIdentityV1];init(mutation:PlacementPoseMutationV1,mutationReceipt:MutationReceiptV1)throws{try mutation.validate();try mutationReceipt.validate();let affected=try mutation.affectedIdentities,concurrency=try mutation.concurrencyIdentities,images=try mutation.mutationPostImages;guard mutationReceipt.mutationID==mutation.mutationID,mutationReceipt.identity.workspaceID==mutation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyPlacementPose(mutation))),mutationReceipt.postImages==images,try concurrency.allSatisfy({identity in mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==identity})?.revision == (try mutation.expectedRevision(for:identity))}),try images.allSatisfy({image in mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try image.identity)})?.revision==image.revision})else{throw WorkspaceMutationFailureV1.invalidReceipt};mutationSHA256=try WorkspaceMutationCanonicalV1.sha256(mutation);self.mutationReceipt=mutationReceipt;affectedIdentities=affected;concurrencyIdentities=concurrency}}

extension EvidenceContextWriteOperationV1{
    var mutationPostImage:MutationPostImageV1{get throws{switch self{case let .appendContext(value,predecessor):return .evidenceContext(id:value.contextID,concurrencyIdentity:try .init(kind:.evidenceContext,id:predecessor?.contextID ?? value.contextID),revision:value.revision,semanticSHA256:value.contextSHA256);case let .appendPair(value,predecessor):return .pairedObservationLink(id:value.linkID,concurrencyIdentity:try .init(kind:.pairedObservationLink,id:predecessor?.linkID ?? value.linkID),revision:value.revision,semanticSHA256:value.linkSHA256)}}}
}
struct EvidenceContextMutationReceiptV1:Codable,Equatable,Sendable{let operationSHA256:String;let mutationReceipt:MutationReceiptV1;init(operation:EvidenceContextWriteOperationV1,mutationReceipt:MutationReceiptV1)throws{try operation.validate();try mutationReceipt.validate();let image=try operation.mutationPostImage;guard mutationReceipt.mutationID==operation.mutationID,mutationReceipt.identity.workspaceID==operation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyEvidenceContext(operation))),mutationReceipt.postImages==[image],mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==(try operation.concurrencyIdentity)})?.revision==operation.expectedRevision,mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try operation.affectedIdentity)})?.revision==operation.revision else{throw WorkspaceMutationFailureV1.invalidReceipt};operationSHA256=try EvidenceContextCanonicalCodecV1.sha256(operation);self.mutationReceipt=mutationReceipt}}

extension LightingWriteOperationV1 { var mutationPostImage:MutationPostImageV1 { get throws { let c=try concurrencyIdentity;switch self {case let .appendSystem(v,_,_):return .lightingSystem(id:v.recordID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.systemSHA256);case let .appendObservation(v,_,_):return .lightingObservation(id:v.recordID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.observationSHA256);case let .appendIssue(v,_,_):return .lightingIssue(id:v.recordID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.issueSHA256);case let .appendMeasurementPlan(v,_,_):return .lightingMeasurementPlan(id:v.recordID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.planSHA256);case let .appendClaim(v,_,_):return .lightingClaimState(id:v.recordID,concurrencyIdentity:c,revision:v.revision,semanticSHA256:v.claimSHA256)}} } }
struct LightingMutationReceiptV1:Codable,Equatable,Sendable { let operationSHA256:String;let mutationReceipt:MutationReceiptV1;init(operation:LightingWriteOperationV1,mutationReceipt:MutationReceiptV1)throws{try operation.validate();try mutationReceipt.validate();let image=try operation.mutationPostImage;guard mutationReceipt.mutationID==operation.mutationID,mutationReceipt.identity.workspaceID==operation.workspaceID,mutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyLighting(operation))),mutationReceipt.postImages==[image],mutationReceipt.expectedRevision.entityRevisions.first(where:{$0.identity==(try operation.concurrencyIdentity)})?.revision==operation.expectedRevision,mutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==(try operation.affectedIdentity)})?.revision==operation.revision else{throw WorkspaceMutationFailureV1.invalidReceipt};operationSHA256=try LightingCanonicalCodecV1.sha256(operation);self.mutationReceipt=mutationReceipt} }
// MARK: - C32 assistance mutation receipt boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Mutation_MutationReceiptV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptanceReceiptBindsCanonicalMutationReceipt = true

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

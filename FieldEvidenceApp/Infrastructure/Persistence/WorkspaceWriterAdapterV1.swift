import Foundation
import SwiftData

/// Applies content changes without saving. MutationJournalStoreV1 owns the
/// single atomic save containing content, revisions, and immutable receipt.
@MainActor
final class WorkspaceWriterAdapterV1: WorkspaceWriterAdapterPortV1 {
    let requiresInitialPlacementForFirstSign = true
    static let supportedCommandKinds: Set<WorkspaceCommandKindV1> = [
        .createFirstSign,
        .createCheckDraft,
        .acceptCheckEvidence,
        .updateSiteTimeZone,
    ]
    static let locationSupportedCommandKinds: Set<WorkspaceCommandKindV1> = [
        .applyLocationHierarchyChange,
        .applyAssetPlacementChange,
        .applyAssetCompositionChange,
    ]
    static let activeSupportedCommandKinds = supportedCommandKinds.union(locationSupportedCommandKinds)
        .union([
            .applySavedSmartView,
            .applyRequirementAssurance,
            .applyPartyAccountability,
            .applyAssetSemantics,
            .applyAuthorityCriterion,
            .applyFunctionalRelationship,
            .applyEvidenceAssurance,
            .applyInspectionReview,
        ])

    private let modelContext: ModelContext
    private let assetSemanticLifecycleAdapter: AssetSemanticLifecycleAdapterV1

    init(
        modelContext: ModelContext,
        assetSemanticLifecycleAdapter: AssetSemanticLifecycleAdapterV1? = nil
    ) {
        self.modelContext = modelContext
        if let assetSemanticLifecycleAdapter {
            self.assetSemanticLifecycleAdapter = assetSemanticLifecycleAdapter
        } else {
            let catalogRegistry = try? AssetSemanticCatalogRegistryV1(
                release: BundledInspectionPackageRegistryV2.shippingAssetSemanticCatalog()
            )
            self.assetSemanticLifecycleAdapter = AssetSemanticLifecycleAdapterV1(
                modelContext: modelContext,
                catalogRegistry: catalogRegistry
            )
        }
    }

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard !modelContext.hasChanges else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        do {
            _ = try ObservationAndTimeRowStoreV1.validatedIndex(in: modelContext)
        } catch {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        switch command {
        case let .createFirstSign(value):
            return try createFirstSign(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .createCheckDraft(value):
            return try createCheckDraft(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .acceptCheckEvidence(value):
            return try acceptCheckEvidence(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .updateSiteTimeZone(value):
            return try updateSiteTimeZone(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyLocationHierarchyChange(value):
            let hierarchy = try applyLocationHierarchyChange(
                value.plan,
                placementChanges: value.placementChanges,
                temporaryRelativePath: temporaryRelativePath
            )
            var affected = hierarchy.affectedEntities
            for placement in value.placementChanges {
                affected += try applyAssetPlacementChange(
                    placement,
                    occurredAt: occurredAt,
                    temporaryRelativePath: temporaryRelativePath
                ).affectedEntities
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: affected,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyAssetPlacementChange(plan):
            return try applyAssetPlacementChange(plan, occurredAt: occurredAt, temporaryRelativePath: temporaryRelativePath)
        case let .applyAssetCompositionChange(plan):
            return try applyAssetCompositionChange(plan, temporaryRelativePath: temporaryRelativePath)
        case let .applySavedSmartView(value):
            return try applySavedSmartView(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyRequirementAssurance(value):
            return try applyRequirementAssurance(
                value,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyPartyAccountability(value):
            return try applyPartyAccountability(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyAssetSemantics(value):
            return try assetSemanticLifecycleAdapter.apply(
                value,
                temporaryRelativePath: temporaryRelativePath
            )
        case let .applyAuthorityCriterion(value):
            return try applyAuthorityCriterion(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyFunctionalRelationship(value):
            return try applyFunctionalRelationship(value, temporaryRelativePath: temporaryRelativePath)
        case let .applyEvidenceAssurance(value):return try applyEvidenceAssurance(value,temporaryRelativePath:temporaryRelativePath)
        case let .applyInspectionReview(value):return try applyInspectionReview(value,temporaryRelativePath:temporaryRelativePath)
        case .deleteAsset,
             .deleteSite,
             .eraseWorkspace,
             .finalizeCheck,
             .finalizeCorrection,
             .recordWork,
             .restoreWorkspace,
             .archiveEntities:
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
    }

    private func applyInspectionReview(_ mutation:InspectionReviewMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{
        do{
            try mutation.validate();let affected=try mutation.affectedIdentities
            for identity in affected{guard try !inspectionReviewRowExists(identity)else{throw WorkspaceMutationFailureV1.sequenceCollision}}
            if let predecessor=try mutation.postImage.predecessorIdentity{
                let prior=try inspectionReviewRevision(predecessor)
                guard prior.workspaceID==mutation.workspaceID,prior.revision==mutation.expectedRevision,prior.revision<UInt64.max,mutation.postImage.revision==prior.revision+1,try !inspectionReviewSuccessorExists(predecessor)else{throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)}
                try validateInspectionReviewSuccessor(mutation.postImage,predecessor:predecessor)
            }
            switch mutation.postImage{
            case let .applyReviewBundle(b):let v=b.transition;try requireExactActor(v.actor);let candidateTransitions=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).map{try $0.value()}+[v];let candidateDispositions=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>()).map{try $0.value()}+(b.disposition.map{[$0]} ?? []);let candidateRequests=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()).map{try $0.value()}+b.changeRequests;_ = try InspectionReviewProjectionBuilderV1.rebuild(workspaceID:v.workspaceID,reviewID:v.reviewID,transitions:candidateTransitions,dispositions:candidateDispositions,changeRequests:candidateRequests);if let d=b.disposition{try requireExactActor(d.reviewer);if let id=d.assuranceManifestID{let manifest=try requireAssuranceManifest(id,workspaceID:d.workspaceID);guard manifest.revision==d.assuranceManifestRevision,manifest.manifestSHA256==d.assuranceManifestSHA256 else{throw WorkspaceMutationFailureV1.invalidCommand}};if let predecessor=d.supersedesDispositionID{let predecessorRows=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==predecessor}));guard predecessorRows.count==1,let predecessorValue=try predecessorRows.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try d.validateSuccessor(of:predecessorValue);try requireInspectionReviewSuccessor(.reviewDisposition,predecessor,valueRevision:d.revision,workspaceID:d.workspaceID)};modelContext.insert(try ReviewDispositionRow(d))};for r in b.changeRequests{try requireExactActor(r.requester);if let resolution=r.resolution{try requireExactActor(resolution.resolver)};if let predecessor=r.supersedesRequestRevisionID{try requireInspectionReviewSuccessor(.changeRequest,predecessor,valueRevision:r.revision,workspaceID:r.workspaceID)};modelContext.insert(try ChangeRequestRow(r))};modelContext.insert(try InspectionReviewTransitionRow(v))
            case let .appendCorrectivePolicy(v),let .supersedeCorrectivePolicy(v):modelContext.insert(try CorrectiveActionPolicyRow(v))
            case let .appendCorrectiveEvent(v),let .appendCorrectiveEventSuccessor(v):let policy=try requireCorrectivePolicy(v.policy.releaseID,workspaceID:v.workspaceID);guard try CorrectiveActionPolicyReferenceV1(policy)==v.policy else{throw WorkspaceMutationFailureV1.invalidCommand};try requireExactActor(v.recorder);if let verifier=v.verifier{try requireExactActor(verifier)};if v.predecessorEventID==nil{try v.validateAdmission(policy:policy)};modelContext.insert(try CorrectiveActionEventRow(v))
            }
            return try WorkspaceMutationEffectV1(affectedEntities:affected,temporaryRelativePath:temporaryRelativePath)
        }catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}
    }
    private func inspectionReviewRowExists(_ i:WorkspaceEntityIdentityV1)throws->Bool{let id=i.id;switch i.kind{case .inspectionReviewTransition:return try uniquePresence(modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>(predicate:#Predicate{$0.transitionID==id})));case .reviewDisposition:return try uniquePresence(modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==id})));case .changeRequest:return try uniquePresence(modelContext.fetch(FetchDescriptor<ChangeRequestRow>(predicate:#Predicate{$0.requestRevisionID==id})));case .correctiveActionPolicy:return try uniquePresence(modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id})));case .correctiveActionEvent:return try uniquePresence(modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate:#Predicate{$0.eventID==id})));default:return false}}
    private func inspectionReviewRevision(_ i:WorkspaceEntityIdentityV1)throws->(workspaceID:WorkspaceID,revision:UInt64){let id=i.id;switch i.kind{case .inspectionReviewTransition:let r=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>(predicate:#Predicate{$0.transitionID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .reviewDisposition:let r=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .changeRequest:let r=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>(predicate:#Predicate{$0.requestRevisionID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .correctiveActionPolicy:let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .correctiveActionEvent:let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate:#Predicate{$0.eventID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func inspectionReviewSuccessorExists(_ p:WorkspaceEntityIdentityV1)throws->Bool{let id=p.id;let count:Int;switch p.kind{case .inspectionReviewTransition:count=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).map{try $0.value()}.filter{$0.predecessorTransitionID==id}.count;case .reviewDisposition:count=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>()).map{try $0.value()}.filter{$0.supersedesDispositionID==id}.count;case .changeRequest:count=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()).map{try $0.value()}.filter{$0.supersedesRequestRevisionID==id}.count;case .correctiveActionPolicy:count=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>()).map{try $0.value()}.filter{$0.supersedesReleaseID==id}.count;case .correctiveActionEvent:count=try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>()).map{try $0.value()}.filter{$0.predecessorEventID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}
    private func validateInspectionReviewSuccessor(_ payload:InspectionReviewMutationPayloadV1,predecessor:WorkspaceEntityIdentityV1)throws{let id=predecessor.id;switch payload{case let .applyReviewBundle(b):let r=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>(predicate:#Predicate{$0.transitionID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try b.transition.validateSuccessor(of:p);case let .supersedeCorrectivePolicy(v):let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);case let .appendCorrectiveEventSuccessor(v):let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate:#Predicate{$0.eventID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};let policy=try requireCorrectivePolicy(v.policy.releaseID,workspaceID:v.workspaceID);try v.validateSuccessor(of:p,policy:policy);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func requireInspectionReviewSuccessor(_ kind:WorkspaceEntityKindV1,_ predecessorID:UUID,valueRevision:UInt64,workspaceID:WorkspaceID)throws{let identity=try WorkspaceEntityIdentityV1(kind:kind,id:predecessorID);let prior=try inspectionReviewRevision(identity);guard prior.workspaceID==workspaceID,prior.revision<UInt64.max,valueRevision==prior.revision+1,try !inspectionReviewSuccessorExists(identity)else{throw WorkspaceMutationFailureV1.staleEntityRevision(identity)}}
    private func requireCorrectivePolicy(_ id:UUID,workspaceID:WorkspaceID)throws->CorrectiveActionPolicyV1{let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id}));guard r.count==1,let v=try r.first?.value(),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireReviewBindings(reviewID:UUID,workspaceID:WorkspaceID,subject:InspectionReviewSubjectReferenceV1,reviewRevision:UInt64,mutationID:MutationIDV1,dispositionID:UUID?,changeRequestIDs:[UUID])throws{try requireCurrentChangeRequests(changeRequestIDs,reviewID:reviewID,workspaceID:workspaceID);if let id=dispositionID{let rows=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==id}));guard rows.count==1,let v=try rows.first?.value(),v.workspaceID==workspaceID,v.reviewID==reviewID,v.subject==subject,v.reviewRevision==reviewRevision,v.mutationID==mutationID else{throw WorkspaceMutationFailureV1.invalidCommand}}}
    private func requireCurrentChangeRequests(_ ids:[UUID],reviewID:UUID,workspaceID:WorkspaceID)throws{let all=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()).map{try $0.value()};for id in ids{let matching=all.filter{$0.requestID==id};guard let head=matching.max(by:{$0.revision<$1.revision}),head.workspaceID==workspaceID,head.reviewID==reviewID else{throw WorkspaceMutationFailureV1.invalidCommand}}}

    private func applyEvidenceAssurance(_ mutation:EvidenceAssuranceMutationV1,temporaryRelativePath:String)throws->WorkspaceMutationEffectV1{
        do{try mutation.validate();let affected=try mutation.affectedIdentity;guard try !evidenceAssuranceRowExists(affected)else{throw WorkspaceMutationFailureV1.sequenceCollision};if let predecessor=try mutation.postImage.predecessorIdentity{let prior=try evidenceAssuranceRevision(predecessor);guard prior.workspaceID==mutation.workspaceID,prior.revision==mutation.expectedRevision,prior.revision<UInt64.max,mutation.postImage.revision==prior.revision+1,try !evidenceAssuranceSuccessorExists(predecessor)else{throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)};try validateEvidenceAssuranceSuccessor(mutation.postImage,predecessor:predecessor)}
            switch mutation.postImage{case let .appendVisibility(v),let .supersedeVisibility(v):modelContext.insert(try EvidenceVisibilityRow(v));case let .appendLink(v),let .supersedeLink(v):let visibility=try requireEvidenceVisibility(v.visibilityID,workspaceID:v.workspaceID);try v.validate(visibility:visibility);modelContext.insert(try ClaimEvidenceLinkRow(v));case let .appendManifest(v,p),let .supersedeManifest(v,p):try requireFreshAssurancePreview(p);try v.validateFresh(preview:p);modelContext.insert(try AssuranceManifestRow(v));case let .recordAttestation(v,m),let .supersedeAttestation(v,m),let .voidAttestation(v,m):let stored=try requireAssuranceManifest(v.manifestID,workspaceID:v.workspaceID);guard stored==m else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validate(manifest:stored);modelContext.insert(try AttestationRow(v))}
            return try WorkspaceMutationEffectV1(affectedEntities:[affected],temporaryRelativePath:temporaryRelativePath)
        }catch let f as WorkspaceMutationFailureV1{modelContext.rollback();throw f}catch{modelContext.rollback();throw WorkspaceMutationFailureV1.invalidCommand}
    }
    private func evidenceAssuranceRowExists(_ i:WorkspaceEntityIdentityV1)throws->Bool{let id=i.id;switch i.kind{case .evidenceVisibility:return try uniquePresence(modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id})));case .claimEvidenceLink:return try uniquePresence(modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.linkID==id})));case .assuranceManifest:return try uniquePresence(modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id})));case .attestation:return try uniquePresence(modelContext.fetch(FetchDescriptor<AttestationRow>(predicate:#Predicate{$0.attestationID==id})));default:return false}}
    private func evidenceAssuranceRevision(_ i:WorkspaceEntityIdentityV1)throws->(workspaceID:WorkspaceID,revision:UInt64){let id=i.id;switch i.kind{case .evidenceVisibility:let r=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .claimEvidenceLink:let r=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.linkID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .assuranceManifest:let r=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);case .attestation:let r=try modelContext.fetch(FetchDescriptor<AttestationRow>(predicate:#Predicate{$0.attestationID==id}));guard r.count==1,let v=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};return(v.workspaceID,v.revision);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func evidenceAssuranceSuccessorExists(_ p:WorkspaceEntityIdentityV1)throws->Bool{let id=p.id;let count:Int;switch p.kind{case .evidenceVisibility:count=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>()).map{try $0.value()}.filter{$0.supersedesVisibilityID==id}.count;case .claimEvidenceLink:count=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>()).map{try $0.value()}.filter{$0.supersedesLinkID==id}.count;case .assuranceManifest:count=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>()).map{try $0.value()}.filter{$0.supersedesManifestID==id}.count;case .attestation:count=try modelContext.fetch(FetchDescriptor<AttestationRow>()).map{try $0.value()}.filter{$0.supersedesAttestationID==id}.count;default:throw WorkspaceMutationFailureV1.invalidCommand};guard count<=1 else{throw WorkspaceMutationFailureV1.persistenceFailed};return count==1}
    private func validateEvidenceAssuranceSuccessor(_ payload:EvidenceAssuranceMutationPayloadV1,predecessor:WorkspaceEntityIdentityV1)throws{let id=predecessor.id;switch payload{case let .supersedeVisibility(v):let r=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);case let .supersedeLink(v):let r=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.linkID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};let visibility=try requireEvidenceVisibility(v.visibilityID,workspaceID:v.workspaceID);try v.validateSuccessor(of:p,visibility:visibility);case let .supersedeManifest(v,_):let r=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);case let .supersedeAttestation(v,_),let .voidAttestation(v,_):let r=try modelContext.fetch(FetchDescriptor<AttestationRow>(predicate:#Predicate{$0.attestationID==id}));guard r.count==1,let p=try r.first?.value()else{throw WorkspaceMutationFailureV1.invalidCommand};try v.validateSuccessor(of:p);default:throw WorkspaceMutationFailureV1.invalidCommand}}
    private func requireEvidenceVisibility(_ id:UUID,workspaceID:WorkspaceID)throws->EvidenceVisibilityV1{let r=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id}));guard r.count==1,let v=try r.first?.value(),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireAssuranceManifest(_ id:UUID,workspaceID:WorkspaceID)throws->AssuranceManifestV1{let r=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard r.count==1,let v=try r.first?.value(),v.workspaceID==workspaceID else{throw WorkspaceMutationFailureV1.invalidCommand};return v}
    private func requireFreshAssurancePreview(_ preview:AssuranceProjectionPreviewV1)throws{let raw=preview.workspaceID.rawValue;let all=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.workspaceID==raw})).map{try $0.value()};let superseded=Set(all.compactMap(\.supersedesLinkID));let current=all.filter{!superseded.contains($0.linkID)&&$0.decision.audience==preview.audience};let rebuilt=try AssuranceProjectionPreviewV1(previewID:preview.previewID,workspaceID:preview.workspaceID,audience:preview.audience,snapshotSHA256:preview.snapshotSHA256,projectionVersion:preview.projectionVersion,links:current,createdAt:preview.createdAt);guard rebuilt==preview else{throw WorkspaceMutationFailureV1.invalidCommand}}

    private func applyFunctionalRelationship(
        _ mutation: FunctionalRelationshipMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let affected = try mutation.affectedIdentity
            guard try !functionalRelationshipRowExists(affected) else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }
            if let predecessor = try mutation.postImage.predecessorIdentity {
                let prior = try functionalRelationshipValue(predecessor)
                guard prior.workspaceID == mutation.workspaceID,
                      prior.revision == mutation.expectedRevision,
                      prior.revision < UInt64.max,
                      mutation.postImage.revision == prior.revision + 1,
                      try !functionalRelationshipSuccessorExists(predecessor) else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)
                }
                switch mutation.postImage {
                case let .supersedeDescriptor(value):
                    let id = predecessor.id
                    let rows = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(predicate: #Predicate { $0.descriptorReleaseID == id }))
                    guard rows.count == 1, let priorValue = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
                    try value.validateSuccessor(of: priorValue)
                case let .endRelationship(value), let .supersedeRelationship(value):
                    let id = predecessor.id
                    let rows = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate: #Predicate { $0.eventID == id }))
                    guard rows.count == 1, let priorValue = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
                    try value.validateSuccessor(of: priorValue)
                default: throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            switch mutation.postImage {
            case let .appendDescriptor(value), let .supersedeDescriptor(value):
                modelContext.insert(try FunctionalRelationshipTypeDescriptorRow(value))
            case let .addRelationship(value), let .endRelationship(value), let .supersedeRelationship(value):
                let descriptorID = value.descriptor.descriptorReleaseID
                let descriptors = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(
                    predicate: #Predicate { $0.descriptorReleaseID == descriptorID }
                ))
                guard descriptors.count == 1, let descriptorRow = descriptors.first else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let descriptor = try descriptorRow.value()
                guard descriptor.workspaceID == value.workspaceID,
                      value.descriptor == FunctionalRelationshipDescriptorReferenceV1(descriptor) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let source = try functionalRelationshipEndpoint(value.sourceAssetID, workspaceID: value.workspaceID)
                let target = try functionalRelationshipEndpoint(value.targetAssetID, workspaceID: value.workspaceID)
                let existing = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>())
                    .map { try $0.value() }.filter { $0.workspaceID == value.workspaceID }
                try FunctionalRelationshipProjectionBuilderV1.validateCandidate(
                    value, source: source, target: target, descriptor: descriptor,
                    existingCurrent: try FunctionalRelationshipProjectionBuilderV1.rebuild(
                        workspaceID: value.workspaceID,
                        events: existing,
                        descriptors: try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()).map { try $0.value() }.filter { $0.workspaceID == value.workspaceID }
                    ).currentRelationships
                )
                modelContext.insert(try AssetFunctionalRelationshipEventRow(value))
            }
            return try WorkspaceMutationEffectV1(
                affectedEntities: [affected], temporaryRelativePath: temporaryRelativePath
            )
        } catch let failure as WorkspaceMutationFailureV1 { modelContext.rollback(); throw failure }
        catch { modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func functionalRelationshipEndpoint(
        _ assetID: UUID, workspaceID: WorkspaceID
    ) throws -> FunctionalRelationshipEndpointSnapshotV1 {
        let assets = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID }))
        guard assets.count == 1, let asset = assets.first else { throw WorkspaceMutationFailureV1.invalidCommand }
        let kindValues = try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>())
            .map { try $0.value() }.filter { $0.assetID == assetID && $0.workspaceID == workspaceID }
        guard let kind = kindValues.max(by: { $0.revision < $1.revision }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let workflowValues = try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>())
            .map { try $0.value() }.filter {
                $0.assetID == assetID && $0.workspaceID == workspaceID
                    && $0.kindBindingEventID == kind.eventID && $0.disposition == .bound
            }
        let capabilities = workflowValues.max(by: { $0.revision < $1.revision })?.capabilityIDs ?? []
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        let key = identity.stableKey
        let revisions = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>(predicate: #Predicate { $0.stableIdentity == key }))
        guard revisions.count == 1, let rawRevision = revisions.first?.revision, rawRevision > 0 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return try FunctionalRelationshipEndpointSnapshotV1(
            assetID: assetID, workspaceID: workspaceID, siteID: asset.siteID,
            assetRevision: UInt64(rawRevision), kindBindingEventID: kind.eventID,
            kindBindingRevision: kind.revision, catalogRelease: kind.catalogRelease,
            semanticID: kind.semanticID, capabilityIDs: capabilities
        )
    }

    private func functionalRelationshipRowExists(_ identity: WorkspaceEntityIdentityV1) throws -> Bool {
        let id = identity.id
        switch identity.kind {
        case .functionalRelationshipTypeDescriptor:
            return try uniquePresence(modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(predicate: #Predicate { $0.descriptorReleaseID == id })))
        case .assetFunctionalRelationshipEvent:
            return try uniquePresence(modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate: #Predicate { $0.eventID == id })))
        default: return false
        }
    }

    private func functionalRelationshipValue(
        _ identity: WorkspaceEntityIdentityV1
    ) throws -> (workspaceID: WorkspaceID, revision: UInt64) {
        let id = identity.id
        switch identity.kind {
        case .functionalRelationshipTypeDescriptor:
            let rows = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(predicate: #Predicate { $0.descriptorReleaseID == id }))
            guard rows.count == 1, let value = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
            return (value.workspaceID, value.revision)
        case .assetFunctionalRelationshipEvent:
            let rows = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate: #Predicate { $0.eventID == id }))
            guard rows.count == 1, let value = try rows.first?.value() else { throw WorkspaceMutationFailureV1.invalidCommand }
            return (value.workspaceID, value.revision)
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func functionalRelationshipSuccessorExists(_ predecessor: WorkspaceEntityIdentityV1) throws -> Bool {
        let id = predecessor.id
        let count: Int
        switch predecessor.kind {
        case .functionalRelationshipTypeDescriptor:
            count = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>())
                .map { try $0.value() }.filter { $0.supersedesDescriptorReleaseID == id }.count
        case .assetFunctionalRelationshipEvent:
            count = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>())
                .map { try $0.value() }.filter { $0.predecessorEventID == id }.count
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return count == 1
    }

    private func applyAuthorityCriterion(
        _ mutation: AuthorityCriterionMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        do {
            try mutation.validate()
            let identity = try mutation.affectedIdentity
            try validateAuthorityCriterionReferences(mutation.postImage)
            if let predecessor = try mutation.postImage.predecessorIdentity {
                let prior = try authorityCriterionRevision(predecessor)
                guard prior.workspaceID == mutation.workspaceID,
                      prior.revision < UInt64.max,
                      prior.revision + 1 == mutation.postImage.revision else {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(predecessor)
                }
                guard try !authorityCriterionSuccessorExists(predecessor) else {
                    throw WorkspaceMutationFailureV1.sequenceCollision
                }
            }
            guard try !authorityCriterionRowExists(identity) else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }
            switch mutation.postImage {
            case .appendAuthoritySource(let v), .supersedeAuthoritySource(let v): modelContext.insert(try AuthoritySourceReleaseRow(v))
            case .appendRequirementBasis(let v), .supersedeRequirementBasis(let v): modelContext.insert(try RequirementBasisBindingRow(v))
            case .appendApplicabilityContext(let v), .supersedeApplicabilityContext(let v): modelContext.insert(try ApplicabilityContextSnapshotRow(v))
            case .appendAssessmentScope(let v), .supersedeAssessmentScope(let v): modelContext.insert(try AssessmentScopeSnapshotRow(v))
            case .appendSeverityScale(let v), .supersedeSeverityScale(let v): modelContext.insert(try SeverityScaleReleaseRow(v))
            case .appendFindingClassification(let v), .supersedeFindingClassification(let v): modelContext.insert(try FindingClassificationBindingRow(v))
            case .appendMeasurementProtocol(let v), .supersedeMeasurementProtocol(let v): modelContext.insert(try MeasurementProtocolReleaseRow(v))
            case .appendEvaluatorDescriptor(let v), .supersedeEvaluatorDescriptor(let v): modelContext.insert(try DerivedFactEvaluatorDescriptorRow(v))
            case .appendDerivedFact(let v), .supersedeDerivedFact(let v): modelContext.insert(try DerivedFactProvenanceRow(v))
            }
            return try WorkspaceMutationEffectV1(affectedEntities: [identity], temporaryRelativePath: temporaryRelativePath)
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback(); throw failure
        } catch {
            modelContext.rollback(); throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func authorityCriterionRowExists(_ identity: WorkspaceEntityIdentityV1) throws -> Bool {
        let id = identity.id
        switch identity.kind {
        case .authoritySourceRelease: return try uniquePresence(modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>(predicate: #Predicate { $0.releaseID == id })))
        case .requirementBasisBinding: return try uniquePresence(modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>(predicate: #Predicate { $0.bindingID == id })))
        case .applicabilityContextSnapshot: return try uniquePresence(modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>(predicate: #Predicate { $0.snapshotID == id })))
        case .assessmentScopeSnapshot: return try uniquePresence(modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>(predicate: #Predicate { $0.snapshotID == id })))
        case .severityScaleRelease: return try uniquePresence(modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>(predicate: #Predicate { $0.releaseID == id })))
        case .findingClassificationBinding: return try uniquePresence(modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>(predicate: #Predicate { $0.bindingID == id })))
        case .measurementProtocolRelease: return try uniquePresence(modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>(predicate: #Predicate { $0.releaseID == id })))
        case .derivedFactEvaluatorDescriptor: return try uniquePresence(modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>(predicate: #Predicate { $0.descriptorID == id })))
        case .derivedFactProvenance: return try uniquePresence(modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>(predicate: #Predicate { $0.provenanceID == id })))
        default: return false
        }
    }

    private func uniquePresence<T>(_ rows: [T]) throws -> Bool {
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return rows.count == 1
    }

    private func authorityCriterionSuccessorExists(
        _ predecessor: WorkspaceEntityIdentityV1
    ) throws -> Bool {
        let id = predecessor.id
        let count: Int
        switch predecessor.kind {
        case .authoritySourceRelease:
            count = try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>()).map { try $0.value() }.filter { $0.supersedesReleaseID == id }.count
        case .requirementBasisBinding:
            count = try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>()).map { try $0.value() }.filter { $0.supersedesBindingID == id }.count
        case .applicabilityContextSnapshot:
            count = try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()).map { try $0.value() }.filter { $0.supersedesSnapshotID == id }.count
        case .assessmentScopeSnapshot:
            count = try modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>()).map { try $0.value() }.filter { $0.supersedesSnapshotID == id }.count
        case .severityScaleRelease:
            count = try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>()).map { try $0.value() }.filter { $0.supersedesReleaseID == id }.count
        case .findingClassificationBinding:
            count = try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>()).map { try $0.value() }.filter { $0.supersedesBindingID == id }.count
        case .measurementProtocolRelease:
            count = try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).map { try $0.value() }.filter { $0.supersedesReleaseID == id }.count
        case .derivedFactEvaluatorDescriptor:
            count = try modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()).map { try $0.value() }.filter { $0.supersedesDescriptorID == id }.count
        case .derivedFactProvenance:
            count = try modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>()).map { try $0.value() }.filter { $0.predecessorProvenanceID == id }.count
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
        return count == 1
    }

    private func authorityCriterionRevision(
        _ identity: WorkspaceEntityIdentityV1
    ) throws -> (workspaceID: WorkspaceID, revision: UInt64) {
        let id = identity.id
        switch identity.kind {
        case .authoritySourceRelease:
            let r=try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .requirementBasisBinding:
            let r=try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>(predicate:#Predicate{$0.bindingID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .applicabilityContextSnapshot:
            let r=try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>(predicate:#Predicate{$0.snapshotID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .assessmentScopeSnapshot:
            let r=try modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>(predicate:#Predicate{$0.snapshotID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .severityScaleRelease:
            let r=try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .findingClassificationBinding:
            let r=try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>(predicate:#Predicate{$0.bindingID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .measurementProtocolRelease:
            let r=try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .derivedFactEvaluatorDescriptor:
            let r=try modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>(predicate:#Predicate{$0.descriptorID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        case .derivedFactProvenance:
            let r=try modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>(predicate:#Predicate{$0.provenanceID == id})); guard r.count==1,let v=try r.first?.value() else{throw WorkspaceMutationFailureV1.invalidCommand}; return(v.workspaceID,v.revision)
        default: throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private func validateAuthorityCriterionReferences(
        _ payload: AuthorityCriterionMutationPayloadV1
    ) throws {
        func require(_ kind: WorkspaceEntityKindV1, _ id: UUID, _ workspaceID: WorkspaceID) throws {
            let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
            let stored = try authorityCriterionRevision(identity)
            guard stored.workspaceID == workspaceID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        switch payload {
        case .appendAuthoritySource, .supersedeAuthoritySource,
             .appendSeverityScale, .supersedeSeverityScale,
             .appendEvaluatorDescriptor, .supersedeEvaluatorDescriptor:
            break
        case .appendRequirementBasis(let v), .supersedeRequirementBasis(let v):
            try require(.authoritySourceRelease, v.authorityReleaseID, v.workspaceID)
            try requireExactActor(v.selectedBy)
        case .appendApplicabilityContext(let v), .supersedeApplicabilityContext(let v):
            try requireExactWorkSubjectScope(v.workSubjectScope)
            try requireExactActor(v.actor)
            if let qualification = v.qualification { try requireExactQualification(qualification) }
            for basis in v.basisBindings { try requireExactRequirementBasis(basis) }
        case .appendAssessmentScope(let v), .supersedeAssessmentScope(let v):
            try require(.applicabilityContextSnapshot, v.applicabilityContextID, v.workspaceID)
            try requireExactWorkSubjectScope(v.workSubjectScope)
        case .appendFindingClassification(let v), .supersedeFindingClassification(let v):
            try require(.applicabilityContextSnapshot, v.applicabilityContextID, v.workspaceID)
            try require(.assessmentScopeSnapshot, v.assessmentScopeID, v.workspaceID)
            if let releaseID = v.severityScaleReleaseID {
                let scale = try requireSeverityScale(releaseID, workspaceID: v.workspaceID)
                guard let levelID = v.severityLevelID,
                      scale.levels.contains(where: { $0.levelID == levelID }) else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
        case .appendMeasurementProtocol(let v), .supersedeMeasurementProtocol(let v):
            try require(.derivedFactEvaluatorDescriptor, v.evaluatorDescriptorID, v.workspaceID)
        case .appendDerivedFact(let v), .supersedeDerivedFact(let v):
            try require(.measurementProtocolRelease, v.protocolReleaseID, v.workspaceID)
            try require(.derivedFactEvaluatorDescriptor, v.evaluatorDescriptorID, v.workspaceID)
        }
    }

    private func requireExactActor(_ expected: ActorSnapshotV1) throws {
        let id = expected.snapshotID
        let rows = try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireExactQualification(_ expected: QualificationSnapshotV1) throws {
        let id = expected.snapshotID
        let rows = try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireExactWorkSubjectScope(_ expected: WorkSubjectScopeSnapshotV1) throws {
        let id = expected.snapshotID
        let rows = try modelContext.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireExactRequirementBasis(_ expected: RequirementBasisBindingV1) throws {
        let id = expected.bindingID
        let rows = try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>(predicate: #Predicate { $0.bindingID == id }))
        guard rows.count == 1, let row = rows.first,
              try row.value() == expected else { throw WorkspaceMutationFailureV1.invalidCommand }
    }

    private func requireSeverityScale(
        _ releaseID: UUID,
        workspaceID: WorkspaceID
    ) throws -> SeverityScaleReleaseV1 {
        let rows = try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>(predicate: #Predicate { $0.releaseID == releaseID }))
        guard rows.count == 1, let row = rows.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let value = try row.value()
        guard value.workspaceID == workspaceID else { throw WorkspaceMutationFailureV1.invalidCommand }
        return value
    }

    func queryExisting(
        identities: [WorkspaceEntityIdentityV1]
    ) throws -> (
        identities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    ) {
        guard !modelContext.hasChanges,
              identities.count <= 256,
              Set(identities).count == identities.count else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        var existing: [WorkspaceEntityIdentityV1] = []
        var bindings: [WorkspacePackageBindingV1] = []
        let deletionLedgerRows: [DeletionLedgerRow]
        let deletionLedgerIdentities: [DeletionIdentityV2]
        if identities.contains(where: { $0.kind == .deletionLedgerEntry }) {
            deletionLedgerRows = try modelContext.fetch(FetchDescriptor<DeletionLedgerRow>())
            guard Set(deletionLedgerRows.map(\.typedID)).count == deletionLedgerRows.count else {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            do {
                deletionLedgerIdentities = try deletionLedgerRows.map {
                    try DeletionIdentityV2(typedID: $0.typedID)
                }
            } catch {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
        } else {
            deletionLedgerRows = []
            deletionLedgerIdentities = []
        }
        for identity in identities {
            let id = identity.id
            let exists: Bool
            switch identity.kind {
            case .site:
                let values = try modelContext.fetch(FetchDescriptor<Site>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .asset:
                let assets = try modelContext.fetch(FetchDescriptor<Asset>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard assets.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = assets.count == 1
                if let asset = assets.first {
                    bindings.append(WorkspacePackageBindingV1(
                        assetID: asset.id,
                        packageID: asset.packID,
                        packageSchemaVersion: asset.packSchemaVersion,
                        packageContentVersion: asset.packContentVersion
                    ))
                }
            case .locationNode:
                let values = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetPlacementEvent:
                let values = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetCompositionEdge:
                let values = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .assetCompositionEvent:
                let values = try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(predicate: #Predicate { $0.id == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .savedSmartView:
                let values = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .serviceParty:
                let values = try modelContext.fetch(FetchDescriptor<ServicePartyRow>(predicate: #Predicate { $0.partyID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .sitePartyRoleEvent:
                let values = try modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>(predicate: #Predicate { $0.eventID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .actorSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .qualificationSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .signoffSnapshot:
                let values = try modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }; exists = values.count == 1
            case .authoritySourceRelease, .requirementBasisBinding,
                 .applicabilityContextSnapshot, .assessmentScopeSnapshot,
                 .severityScaleRelease, .findingClassificationBinding,
                 .measurementProtocolRelease, .derivedFactEvaluatorDescriptor,
                 .derivedFactProvenance:
                exists = try authorityCriterionRowExists(identity)
            case .workflowRecord:
                let values = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .evidenceFile:
                let values = try modelContext.fetch(FetchDescriptor<EvidenceFile>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .issue:
                let values = try modelContext.fetch(FetchDescriptor<Issue>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .packet:
                let values = try modelContext.fetch(FetchDescriptor<Packet>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .report:
                let values = try modelContext.fetch(FetchDescriptor<Report>(
                    predicate: #Predicate { $0.id == id }
                ))
                guard values.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
                exists = values.count == 1
            case .deletionLedgerEntry:
                let matches = deletionLedgerIdentities.filter { $0.id == identity.id }
                guard matches.count <= 1 else {
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
                exists = matches.count == 1
            }
            if exists { existing.append(identity) }
        }
        return (
            existing.sorted { $0.stableKey < $1.stableKey },
            bindings.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
        )
    }

    func createFirstSign(
        _ value: FirstSignMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard value.assetLabel == value.assetLabel.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.assetLabel.isEmpty,
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              Self.isFinite(value.createdAt),
              value.newSite == nil || value.newSite?.id == value.siteID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementFields = [
            value.initialPlacementMutationID != nil,
            value.initialPlacementEventID != nil,
            value.initialPhysicalEpisodeID != nil,
        ]
        guard placementFields.allSatisfy({ $0 }) || placementFields.allSatisfy({ !$0 }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        let siteID = value.siteID
        let existingSites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        if value.newSite == nil {
            guard existingSites.count == 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        } else {
            guard existingSites.isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        }

        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite {
            guard site.label == site.label.trimmingCharacters(in: .whitespacesAndNewlines),
                  !site.label.isEmpty else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id))
        }
        if let placementEventID = value.initialPlacementEventID {
            guard try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
                predicate: #Predicate { $0.id == placementEventID }
            )).isEmpty else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            identities.append(try WorkspaceEntityIdentityV1(
                kind: .assetPlacementEvent,
                id: placementEventID
            ))
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )

        if let site = value.newSite {
            modelContext.insert(Site(
                id: site.id,
                label: site.label,
                address: site.address,
                timeZoneID: site.timeZoneID,
                createdAt: value.createdAt
            ))
        }
        modelContext.insert(Asset(
            id: value.assetID,
            siteID: value.siteID,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            label: value.assetLabel,
            createdAt: value.createdAt
        ))
        if let mutationID = value.initialPlacementMutationID,
           let eventID = value.initialPlacementEventID,
           let episodeID = value.initialPhysicalEpisodeID {
            let siteDisplay = value.newSite?.label ?? existingSites[0].label
            let event = try AssetPlacementEventV1(
                id: eventID,
                workspaceID: try currentWorkspaceID(),
                assetID: value.assetID,
                siteID: value.siteID,
                locationNodeID: nil,
                predecessorEventID: nil,
                source: .manual,
                physicalEpisodeID: episodeID,
                continuity: .samePhysicalInstallation,
                pathSnapshot: try LocationPathSnapshotV1(
                    siteID: value.siteID,
                    siteDisplay: siteDisplay,
                    nodes: []
                ),
                mutationID: mutationID,
                occurredAt: occurredAt
            )
            try AssetPlacementHistoryV1.validate([event])
            modelContext.insert(try AssetPlacementEventRow(event))
        }
        return effect
    }

    private func currentWorkspaceID() throws -> WorkspaceID {
        let states = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        guard states.count == 1, let state = states.first else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        return WorkspaceID(rawValue: state.workspaceID)
    }

    func createCheckDraft(
        _ value: CheckDraftMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard let stage = WorkflowStage(rawValue: value.stage),
              !value.packID.isEmpty,
              value.packSchemaVersion > 0,
              value.packContentVersion > 0,
              !value.pdfTemplateID.isEmpty,
              value.pdfTemplateVersion > 0,
              Self.isFinite(value.startedAt),
              value.observedAtUTC.map({ Self.isFinite($0) }) ?? true else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        guard (value.observationBasis == nil) == (value.temporalContext == nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let observationBasisData: Data
        let temporalContextData: Data
        do {
            if let observationBasis = value.observationBasis,
               let temporalContext = value.temporalContext {
                try Self.requireLegacyTimeProjectionMatches(
                    temporalContext,
                    command: value
                )
                observationBasisData = try ObservationAndTimeCodecV1.encode(
                    observationBasis
                )
                temporalContextData = try ObservationAndTimeCodecV1.encode(
                    temporalContext
                )
            } else {
                let migratedBasis = try ObservationAndTimeLegacyMigrationV1.observationBasis(
                    couldNotVerifyKey: nil,
                    displaySnapshot: nil,
                    registryVersion: nil
                )
                let migratedTemporal = try ObservationAndTimeLegacyMigrationV1.temporalContext(
                    observedAtUTC: value.observedAtUTC,
                    recordedAtUTC: value.startedAt,
                    timeZoneID: value.timeZoneID,
                    utcOffsetMinutes: value.utcOffsetMinutes,
                    localDate: value.localDate,
                    localTime: value.localTime
                )
                guard let migratedBasis, let migratedTemporal else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                observationBasisData = try ObservationAndTimeCodecV1.encode(migratedBasis)
                temporalContextData = try ObservationAndTimeCodecV1.encode(migratedTemporal)
            }
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftStep: WorkflowDraftStep?
        if let key = value.draftStepKey {
            guard let parsed = WorkflowDraftStep(rawValue: key) else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            draftStep = parsed
        } else {
            draftStep = nil
        }
        guard (stage == .work && draftStep == nil)
                || (stage != .work && draftStep != nil) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let recordID = value.recordID
        guard try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let assetID = value.assetID
        guard try modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )).count == 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.recordID)
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [identity],
            temporaryRelativePath: temporaryRelativePath
        )
        modelContext.insert(WorkflowRecord(
            id: value.recordID,
            assetID: value.assetID,
            packetID: nil,
            issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordID,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: stage,
            state: .draft,
            draftStepKey: draftStep,
            startedAt: value.startedAt,
            completedAt: nil,
            observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: nil,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: nil,
            finalizationMutationID: nil
        ))
        modelContext.insert(try ObservationAndTimeRow(
            recordID: value.recordID,
            observationBasisV1Data: observationBasisData,
            temporalContextV1Data: temporalContextData
        ))
        let workspaceID = try currentWorkspaceID().rawValue
        modelContext.insert(try RequirementAssuranceRow.blockingUnknownBackfill(
            workflowRecordID: value.recordID,
            workspaceID: workspaceID,
            evaluatedRevision: 1,
            requirementID: "legacy_assurance_unknown",
            requirementVersion: 1,
            requirementTypeID: "legacy_assurance_unknown",
            policySHA256: StoreMigrationCanonicalJSONV1.sha256(
                Data("legacy-assurance-unknown-v1".utf8)
            ),
            mutationID: value.recordID,
            timestamp: value.startedAt
        ))
        return effect
    }

    private static func requireLegacyTimeProjectionMatches(
        _ temporal: TemporalContextV1,
        command: CheckDraftMutationV1
    ) throws {
        try temporal.validate()
        guard temporal.occurredAtUTC == command.observedAtUTC,
              temporal.localDate == command.localDate,
              temporal.localTime == command.localTime,
              temporal.ianaTimeZoneIdentifier == command.timeZoneID else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let expectedOffsetSeconds: Int?
        if let minutes = command.utcOffsetMinutes {
            let (seconds, overflow) = minutes.multipliedReportingOverflow(
                by: 60
            )
            guard !overflow else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            expectedOffsetSeconds = seconds
        } else {
            expectedOffsetSeconds = nil
        }
        guard temporal.utcOffsetSeconds == expectedOffsetSeconds else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func acceptCheckEvidence(
        _ value: CheckEvidenceMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard WorkflowDraftStep(rawValue: value.nextDraftStepKey) != nil,
              value.byteCount >= 0,
              value.thumbnailByteCount >= 0,
              Self.isSHA256(value.sha256),
              Self.isSHA256(value.thumbnailSHA256),
              Self.isSafeRelativePath(value.relativePath),
              Self.isSafeRelativePath(value.thumbnailRelativePath),
              !value.mimeType.isEmpty,
              !value.purposeKey.isEmpty,
              Self.isFinite(value.createdAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let draftID = value.draftID
        let drafts = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == draftID }
        ))
        guard drafts.count == 1,
              let draft = drafts.first,
              draft.state == WorkflowState.draft.rawValue else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let evidenceID = value.evidenceID
        guard try modelContext.fetch(FetchDescriptor<EvidenceFile>(
            predicate: #Predicate { $0.id == evidenceID }
        )).isEmpty else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let identities = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: value.draftID),
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: value.evidenceID),
        ]
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: identities,
            temporaryRelativePath: temporaryRelativePath
        )
        draft.draftStepKey = value.nextDraftStepKey
        modelContext.insert(EvidenceFile(
            id: value.evidenceID,
            recordID: value.draftID,
            purposeKey: value.purposeKey,
            relativePath: value.relativePath,
            mimeType: value.mimeType,
            byteCount: value.byteCount,
            sha256: value.sha256,
            createdAt: value.createdAt,
            thumbnailRelativePath: value.thumbnailRelativePath,
            thumbnailByteCount: value.thumbnailByteCount,
            thumbnailSHA256: value.thumbnailSHA256
        ))
        return effect
    }

    func updateSiteTimeZone(
        _ value: SiteTimeZoneMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard TimeZone(identifier: value.timeZoneID) != nil,
              Self.isFinite(value.confirmedAt) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let siteID = value.siteID
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count == 1, let site = sites.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let effect = try WorkspaceMutationEffectV1(
            affectedEntities: [try WorkspaceEntityIdentityV1(kind: .site, id: siteID)],
            temporaryRelativePath: temporaryRelativePath
        )
        site.timeZoneID = value.timeZoneID
        site.updatedAt = value.confirmedAt
        return effect
    }

    func rollback() {
        assetSemanticLifecycleAdapter.rollback()
        modelContext.rollback()
    }

    private func applyLocationHierarchyChange(
        _ plan: LocationHierarchyChangePlanV1,
        placementChanges: [AssetPlacementChangePlanV1],
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try plan.validate()
        let workspaceID = plan.workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(
            predicate: #Predicate { $0.workspaceID == workspaceID }
        ))
        let current = try rows.map { try $0.value() }
        let affectedIDs = Set(plan.beforeNodes.map(\.id)).union(plan.afterNodes.map(\.id))
        let currentAffected = current.filter { affectedIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        guard currentAffected == plan.beforeNodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementEvents = try modelContext.fetch(
            FetchDescriptor<AssetPlacementEventRow>(predicate: #Predicate { $0.workspaceID == workspaceID })
        ).map { try $0.value() }
        let immutablePlacementReferencedNodeIDs = placementEvents.compactMap(\.locationNodeID)
            .sorted { $0.uuidString < $1.uuidString }
        guard Array(Set(immutablePlacementReferencedNodeIDs)).sorted(by: { $0.uuidString < $1.uuidString })
                == plan.immutablePlacementReferencedNodeIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let unaffected = current.filter { !affectedIDs.contains($0.id) }
        let resultingNodes = unaffected + plan.afterNodes
        try LocationHierarchyPolicyV1.validate(resultingNodes)
        let sites = try modelContext.fetch(FetchDescriptor<Site>())
        let siteDisplayByID = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0.label) })
        let liveAssetIDs = Set(try modelContext.fetch(FetchDescriptor<Asset>()).map(\.id))
        let placementPredecessorIDs = Set(placementEvents.compactMap(\.predecessorEventID))
        let liveTips = placementEvents.filter {
            liveAssetIDs.contains($0.assetID) && !placementPredecessorIDs.contains($0.id)
        }
        guard Set(liveTips.map(\.assetID)).count == liveTips.count,
              Set(liveTips.map(\.assetID)) == liveAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementChangesByAssetID = Dictionary(
            uniqueKeysWithValues: placementChanges.map { ($0.basis.assetID, $0) }
        )
        var expectedPathChanges: [AssetLocationPathChangeV1] = []
        for tip in liveTips {
            guard let beforeSiteDisplay = siteDisplayByID[tip.siteID] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let beforePath = try makeLocationPath(
                siteID: tip.siteID,
                siteDisplay: beforeSiteDisplay,
                nodeID: tip.locationNodeID,
                nodes: current
            )
            let change = placementChangesByAssetID[tip.assetID]
            let afterSiteID = change?.basis.proposedSiteID ?? tip.siteID
            let afterNodeID = change?.basis.proposedLocationNodeID ?? tip.locationNodeID
            guard let afterSiteDisplay = siteDisplayByID[afterSiteID] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let afterPath = try makeLocationPath(
                siteID: afterSiteID,
                siteDisplay: afterSiteDisplay,
                nodeID: afterNodeID,
                nodes: resultingNodes
            )
            if beforePath != afterPath {
                expectedPathChanges.append(try AssetLocationPathChangeV1(
                    assetID: tip.assetID,
                    beforePath: beforePath,
                    afterPath: afterPath
                ))
            }
            if let change {
                guard change.basis.currentPlacement == tip,
                      change.basis.proposedPath == afterPath else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
        }
        expectedPathChanges.sort()
        guard expectedPathChanges == plan.assetPathChanges,
              expectedPathChanges.map(\.assetID) == plan.affectedAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: plan.afterNodes.map { ($0.id, $0) })
        for id in affectedIDs {
            if let value = afterByID[id], let row = rowsByID[id] {
                let replacement = try LocationNodeRow(value)
                row.workspaceID = replacement.workspaceID; row.siteID = replacement.siteID
                row.parentNodeID = replacement.parentNodeID; row.kind = replacement.kind
                row.label = replacement.label; row.shortCode = replacement.shortCode
                row.siblingOrder = replacement.siblingOrder; row.state = replacement.state
                row.revision = replacement.revision; row.mutationID = replacement.mutationID
                row.occurredAt = replacement.occurredAt
                row.canonicalData = replacement.canonicalData
            } else if let value = afterByID[id] {
                modelContext.insert(try LocationNodeRow(value))
            } else if let row = rowsByID[id] {
                modelContext.delete(row)
            }
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: try affectedIDs.map { try .init(kind: .locationNode, id: $0) },
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applyAssetPlacementChange(
        _ plan: AssetPlacementChangePlanV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        let rebuilt = try AssetPlacementChangePlanV1(
            operationID: plan.operationID,
            mutationID: plan.mutationID,
            basis: plan.basis,
            newEventID: plan.newEventID,
            resultingPhysicalEpisodeID: plan.resultingPhysicalEpisodeID,
            componentContributions: plan.componentContributions
        )
        guard rebuilt == plan else { throw WorkspaceMutationFailureV1.invalidCommand }
        let assetID = plan.basis.assetID
        let assets = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID }))
        guard assets.count == 1, let asset = assets.first else { throw WorkspaceMutationFailureV1.invalidCommand }
        let placementRows = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
            predicate: #Predicate { $0.assetID == assetID }
        ))
        let placements = try placementRows.map { try $0.value() }
        let predecessorIDs = Set(placements.compactMap(\.predecessorEventID))
        let tips = placements.filter { !predecessorIDs.contains($0.id) }
        let newEventID = plan.newEventID
        guard tips.count <= 1, tips.first == plan.basis.currentPlacement,
              asset.siteID == (plan.basis.currentPlacement?.siteID ?? plan.basis.proposedSiteID),
              try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(
                predicate: #Predicate { $0.id == newEventID }
              )).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        let exactPath = try currentLocationPath(
            workspaceID: plan.basis.workspaceID,
            siteID: plan.basis.proposedSiteID,
            nodeID: plan.basis.proposedLocationNodeID
        )
        guard exactPath == plan.basis.proposedPath else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let event = try AssetPlacementEventV1(
            id: plan.newEventID,
            workspaceID: plan.basis.workspaceID,
            assetID: assetID,
            siteID: plan.basis.proposedSiteID,
            locationNodeID: plan.basis.proposedLocationNodeID,
            predecessorEventID: plan.basis.currentPlacement?.id,
            source: plan.basis.source,
            physicalEpisodeID: plan.resultingPhysicalEpisodeID,
            continuity: plan.basis.reviewedContinuity,
            pathSnapshot: plan.basis.proposedPath,
            mutationID: plan.mutationID,
            occurredAt: occurredAt
        )
        try AssetPlacementHistoryV1.validate(placements + [event])
        asset.siteID = event.siteID
        asset.updatedAt = occurredAt
        modelContext.insert(try AssetPlacementEventRow(event))
        return try WorkspaceMutationEffectV1(
            affectedEntities: try [
                .init(kind: .asset, id: assetID),
                .init(kind: .assetPlacementEvent, id: event.id),
            ],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func currentLocationPath(
        workspaceID: WorkspaceID,
        siteID: UUID,
        nodeID: UUID?
    ) throws -> LocationPathSnapshotV1 {
        let sites = try modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        ))
        guard sites.count == 1, let site = sites.first else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let rawWorkspaceID = workspaceID.rawValue
        let nodes = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(
            predicate: #Predicate { $0.workspaceID == rawWorkspaceID }
        )).map { try $0.value() }
        try LocationHierarchyPolicyV1.validate(nodes)
        return try makeLocationPath(
            siteID: siteID,
            siteDisplay: site.label,
            nodeID: nodeID,
            nodes: nodes
        )
    }

    private func makeLocationPath(
        siteID: UUID,
        siteDisplay: String,
        nodeID: UUID?,
        nodes: [LocationNodeV1]
    ) throws -> LocationPathSnapshotV1 {
        guard let nodeID else {
            return try LocationPathSnapshotV1(siteID: siteID, siteDisplay: siteDisplay, nodes: [])
        }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var cursorID: UUID? = nodeID
        var visited = Set<UUID>()
        var reversed: [LocationPathComponentV1] = []
        while let id = cursorID {
            guard visited.insert(id).inserted, let node = byID[id], node.siteID == siteID,
                  node.state == .active else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            reversed.append(try LocationPathComponentV1(
                nodeID: node.id,
                kind: node.kind,
                label: node.label,
                shortCode: node.shortCode,
                revision: node.revision
            ))
            cursorID = node.parentNodeID
        }
        return try LocationPathSnapshotV1(
            siteID: siteID,
            siteDisplay: siteDisplay,
            nodes: Array(reversed.reversed())
        )
    }

    private func applyAssetCompositionChange(
        _ plan: AssetCompositionChangePlanV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try plan.validate()
        let event = plan.event
        let eventID = event.id
        guard try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(
            predicate: #Predicate { $0.id == eventID }
        )).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
        let edgeID = event.edge.id
        let edgeRows = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>(
            predicate: #Predicate { $0.id == edgeID }
        ))
        guard edgeRows.count <= 1 else { throw WorkspaceMutationFailureV1.invalidCommand }
        let priorEvents = try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(
            predicate: #Predicate { $0.edgeID == edgeID }
        ))
        let priorValues = try priorEvents.map {
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEventV1.self, from: $0.canonicalData)
            try value.validate()
            return value
        }
        let predecessorIDs = Set(priorValues.compactMap(\.predecessorEventID))
        let tips = priorValues.filter { !predecessorIDs.contains($0.id) }
        let priorRevision: UInt64
        if let prior = edgeRows.first {
            guard prior.revision >= 0, prior.revision < Int64.max else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            priorRevision = UInt64(prior.revision)
        } else {
            priorRevision = 0
        }
        guard tips.count <= 1, tips.first?.id == event.predecessorEventID,
              event.edge.revision == priorRevision + 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        try AssetCompositionHistoryV1.validate(priorValues + [event], currentEdge: event.edge)
        let allEdges = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>()).map {
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEdgeV1.self, from: $0.canonicalData)
            try value.validate()
            return value
        }
        let resultingEdges = (allEdges.filter { $0.id != edgeID } + [event.edge]).filter(\.isActive).sorted { $0.id.uuidString < $1.id.uuidString }
        let liveAssetIDs = Set(try modelContext.fetch(FetchDescriptor<Asset>()).map(\.id))
        let placementValues = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>()).map { try $0.value() }
        let allPredecessors = Set(placementValues.compactMap(\.predecessorEventID))
        let placementTips = placementValues.filter {
            liveAssetIDs.contains($0.assetID) && !allPredecessors.contains($0.id)
        }
        guard Set(placementTips.map(\.assetID)).count == placementTips.count,
              Set(placementTips.map(\.assetID)) == liveAssetIDs else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let placementByAsset = Dictionary(uniqueKeysWithValues: placementTips.map { ($0.assetID, $0) })
        guard plan.currentPlacementByAssetID.allSatisfy({ placementByAsset[$0.key] == $0.value }),
              resultingEdges == plan.resultingActiveEdges else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        try AssetCompositionPolicyV1.validate(edges: resultingEdges, placementByAssetID: placementByAsset)
        if let row = edgeRows.first {
            let replacement = try AssetCompositionEdgeRow(event.edge)
            row.workspaceID = replacement.workspaceID; row.parentAssetID = replacement.parentAssetID
            row.childAssetID = replacement.childAssetID; row.relationship = replacement.relationship
            row.isActive = replacement.isActive; row.revision = replacement.revision
            row.edgeSHA256 = replacement.edgeSHA256; row.canonicalData = replacement.canonicalData
        } else {
            modelContext.insert(try AssetCompositionEdgeRow(event.edge))
        }
        modelContext.insert(try AssetCompositionEventRow(event))
        return try WorkspaceMutationEffectV1(
            affectedEntities: try [
                .init(kind: .assetCompositionEdge, id: event.edge.id),
                .init(kind: .assetCompositionEvent, id: event.id),
            ],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applySavedSmartView(
        _ mutation: SavedSmartViewMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try mutation.validate()
        let id = mutation.id
        let stableKey = SavedSmartViewRowV1.key(
            workspaceID: mutation.workspaceID,
            stableID: mutation.stableID
        )
        let byID = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
            predicate: #Predicate { $0.id == id }
        ))
        let byStableKey = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
            predicate: #Predicate { $0.workspaceStableKey == stableKey }
        ))
        guard byID.count <= 1, byStableKey.count <= 1,
              Set((byID + byStableKey).map(\.id)).count <= 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let existing = byID.first ?? byStableKey.first
        if let existing {
            guard existing.id == id,
                  existing.workspaceStableKey == stableKey,
                  existing.workspaceID == mutation.workspaceID,
                  existing.stableID == mutation.stableID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        let existingDescriptor = try existing?.descriptor()
        switch mutation.disposition {
        case .upsert:
            guard let descriptor = mutation.descriptor,
                  descriptor.origin == .userSaved,
                  existingDescriptor.map({
                      $0.revision == mutation.expectedDescriptorRevision
                  })
                    ?? (mutation.expectedDescriptorRevision == 0) else {
                throw WorkspaceMutationFailureV1.staleEntityRevision(
                    try .init(kind: .savedSmartView, id: id)
                )
            }
            if let existing { modelContext.delete(existing) }
            modelContext.insert(try SavedSmartViewRowV1(descriptor))
        case .delete:
            guard let existing,
                  existingDescriptor?.origin == .userSaved,
                  existingDescriptor?.revision == mutation.expectedDescriptorRevision,
                  existing.workspaceID == mutation.workspaceID,
                  existing.stableID == mutation.stableID else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            modelContext.delete(existing)
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: [.init(kind: .savedSmartView, id: id)],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applyRequirementAssurance(
        _ mutation: RequirementAssuranceMutationV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try mutation.validate()
        let recordID = mutation.snapshot.workflowRecordID
        var recordDescriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.id == recordID }
        )
        recordDescriptor.fetchLimit = 2
        let records = try modelContext.fetch(recordDescriptor)
        guard records.count == 1 else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }

        var assuranceDescriptor = FetchDescriptor<RequirementAssuranceRow>(
            predicate: #Predicate { $0.workflowRecordID == recordID }
        )
        assuranceDescriptor.fetchLimit = 2
        let rows = try modelContext.fetch(assuranceDescriptor)
        guard rows.count <= 1 else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        if let row = rows.first {
            do {
                try row.replace(
                    with: mutation.snapshot,
                    expectedRevision: mutation.expectedEvaluatedRevision,
                    mutationID: mutation.mutationID,
                    updatedAt: occurredAt
                )
            } catch RequirementAssuranceFailureV1.staleRevision {
                throw WorkspaceMutationFailureV1.staleEntityRevision(
                    try .init(kind: .workflowRecord, id: recordID)
                )
            }
        } else {
            guard mutation.expectedEvaluatedRevision == 0 else {
                throw WorkspaceMutationFailureV1.staleEntityRevision(
                    try .init(kind: .workflowRecord, id: recordID)
                )
            }
            modelContext.insert(try RequirementAssuranceRow(
                snapshot: mutation.snapshot,
                mutationID: mutation.mutationID,
                createdAt: occurredAt,
                updatedAt: occurredAt
            ))
        }
        return try WorkspaceMutationEffectV1(
            affectedEntities: [.init(kind: .workflowRecord, id: recordID)],
            temporaryRelativePath: temporaryRelativePath
        )
    }

    private func applyPartyAccountability(
        _ mutation: PartyAccountabilityMutationV1,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        try mutation.validate()
        let identity = try mutation.affectedIdentity
        switch mutation {
        case let .recordParty(value):
            let partyID = value.partyID
            var descriptor = FetchDescriptor<ServicePartyRow>(predicate: #Predicate { $0.partyID == partyID })
            descriptor.fetchLimit = 2
            let rows = try modelContext.fetch(descriptor)
            guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.persistenceFailed }
            if let row = rows.first {
                let prior = try row.value()
                guard prior.revision < UInt64.max else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                do {
                    try value.validateSuccessor(of: prior)
                    try row.replace(with: value, expectedRevision: prior.revision)
                } catch PartyAccountabilityFailureV1.staleRevision {
                    throw WorkspaceMutationFailureV1.staleEntityRevision(identity)
                } catch {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } else if value.revision != 1 {
                throw WorkspaceMutationFailureV1.invalidCommand
            } else {
                modelContext.insert(try ServicePartyRow(value))
            }
        case let .appendSiteRole(value):
            let eventID = value.eventID
            let siteID = value.siteID
            let partyID = value.partyID
            var duplicate = FetchDescriptor<SitePartyRoleEventRow>(predicate: #Predicate { $0.eventID == eventID })
            duplicate.fetchLimit = 1
            guard try modelContext.fetch(duplicate).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            var site = FetchDescriptor<Site>(predicate: #Predicate { $0.id == siteID }); site.fetchLimit = 1
            var party = FetchDescriptor<ServicePartyRow>(predicate: #Predicate { $0.partyID == partyID }); party.fetchLimit = 1
            guard try modelContext.fetch(site).count == 1,
                  let partyValue = try modelContext.fetch(party).first?.value(),
                  partyValue.workspaceID == value.workspaceID else { throw WorkspaceMutationFailureV1.invalidCommand }
            let predecessor: SitePartyRoleEventV1?
            if let predecessorID = value.supersedesEventID {
                var d = FetchDescriptor<SitePartyRoleEventRow>(predicate: #Predicate { $0.eventID == predecessorID }); d.fetchLimit = 1
                guard let row = try modelContext.fetch(d).first else { throw WorkspaceMutationFailureV1.invalidCommand }
                predecessor = try row.value()
            } else { predecessor = nil }
            modelContext.insert(try SitePartyRoleEventRow(value, predecessor: predecessor))
        case let .appendActorSnapshot(value):
            let snapshotID = value.snapshotID
            var d = FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == snapshotID }); d.fetchLimit = 1
            guard try modelContext.fetch(d).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            if let partyID = value.actor.partyID {
                var partyDescriptor = FetchDescriptor<ServicePartyRow>(
                    predicate: #Predicate { $0.partyID == partyID }
                )
                partyDescriptor.fetchLimit = 2
                let partyRows = try modelContext.fetch(partyDescriptor)
                guard partyRows.count == 1 else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
                let party = try partyRows[0].value()
                do {
                    try value.actor.validatePartyReference(party)
                } catch {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            modelContext.insert(try ActorSnapshotRow(value))
        case let .appendQualificationSnapshot(value):
            let snapshotID = value.snapshotID
            var d = FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == snapshotID }); d.fetchLimit = 1
            guard try modelContext.fetch(d).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            modelContext.insert(try QualificationSnapshotRow(value))
        case let .appendSignoff(value):
            let snapshotID = value.snapshotID
            var d = FetchDescriptor<SignoffSnapshotRow>(predicate: #Predicate { $0.snapshotID == snapshotID }); d.fetchLimit = 1
            guard try modelContext.fetch(d).isEmpty else { throw WorkspaceMutationFailureV1.invalidCommand }
            if let embeddedActor = value.roleAssertion?.actor {
                let actorID = embeddedActor.snapshotID
                var actorDescriptor = FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == actorID })
                actorDescriptor.fetchLimit = 2
                let actorRows = try modelContext.fetch(actorDescriptor)
                guard actorRows.count == 1,
                      try actorRows[0].value() == embeddedActor else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            if let embeddedQualification = value.qualification {
                let qualificationID = embeddedQualification.snapshotID
                var qualificationDescriptor = FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == qualificationID })
                qualificationDescriptor.fetchLimit = 2
                let qualificationRows = try modelContext.fetch(qualificationDescriptor)
                guard qualificationRows.count == 1,
                      try qualificationRows[0].value() == embeddedQualification else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            }
            let predecessor: SignoffSnapshotV1?
            if let predecessorID = value.supersedesSnapshotID {
                var p = FetchDescriptor<SignoffSnapshotRow>(predicate: #Predicate { $0.snapshotID == predecessorID }); p.fetchLimit = 1
                guard let row = try modelContext.fetch(p).first else { throw WorkspaceMutationFailureV1.invalidCommand }
                predecessor = try row.value()
            } else { predecessor = nil }
            modelContext.insert(try SignoffSnapshotRow(value, predecessor: predecessor))
        }
        return try WorkspaceMutationEffectV1(affectedEntities: [identity], temporaryRelativePath: temporaryRelativePath)
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("..") && !value.contains("\\")
    }

    private static func isFinite(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }
}

import Foundation

struct TemporalEvidenceAdmissionSnapshotV1: Equatable, Sendable {
    let expectedRevision: WorkspaceExpectedRevisionV1
    let profile: TemporalEvidenceLimitProfileV1
    let clipsForRequirement: Int
    let clipsForSession: Int
    let availableByteCount: UInt64
    let evaluatedAt: Date
    init(expectedRevision:WorkspaceExpectedRevisionV1,profile:TemporalEvidenceLimitProfileV1,clipsForRequirement:Int,clipsForSession:Int,availableByteCount:UInt64,evaluatedAt:Date)throws{self.expectedRevision=expectedRevision;self.profile=profile;self.clipsForRequirement=clipsForRequirement;self.clipsForSession=clipsForSession;self.availableByteCount=availableByteCount;self.evaluatedAt=evaluatedAt;try validate()}
    func validate()throws{try profile.validate();guard expectedRevision.workspaceID.rawValue != TemporalEvidenceValidationV1.zeroUUID,clipsForRequirement>=0,clipsForSession>=clipsForRequirement,evaluatedAt.timeIntervalSinceReferenceDate.isFinite else{throw TemporalEvidenceContractFailureV1.invalidValue}}
    func validate(clip:TemporalEvidenceClipV1,requiredBytes:UInt64)throws{try validate();try clip.validate(profile:profile);guard clip.workspaceID==expectedRevision.workspaceID,clip.target.definitionRelease==profile.definitionRelease,clipsForRequirement<profile.maximumClipsPerRequirement,clipsForSession<profile.maximumClipsPerSession,availableByteCount>=profile.minimumFreeByteCount,requiredBytes<=availableByteCount-profile.minimumFreeByteCount else{throw TemporalEvidenceContractFailureV1.insufficientStorage}}
}

protocol TemporalEvidenceAdmissionResolvingV1: Sendable {
    func currentAdmission(for clip:TemporalEvidenceClipV1) async throws -> TemporalEvidenceAdmissionSnapshotV1
}

struct TemporalEvidenceAuthoritativeAdmissionStateV1:Sendable{let revision:WorkspaceExpectedRevisionV1;let session:SurveySessionV1;let definition:SurveyDefinitionReleaseV1;let packageRelease:InspectionPackageReleaseV1;let profile:TemporalEvidenceLimitProfileV1;let clipsForRequirement:Int;let clipsForSession:Int;let availableByteCount:UInt64;let evaluatedAt:Date}
@MainActor protocol TemporalEvidenceAuthoritativeAdmissionReadingV1:AnyObject{func readCurrentAdmission(for clip:TemporalEvidenceClipV1)throws->TemporalEvidenceAuthoritativeAdmissionStateV1}
@MainActor final class TemporalEvidenceTrustedAdmissionAuthorityV1:TemporalEvidenceAdmissionResolvingV1{
    private let reader:any TemporalEvidenceAuthoritativeAdmissionReadingV1
    init(reader:any TemporalEvidenceAuthoritativeAdmissionReadingV1){self.reader=reader}
    func currentAdmission(for clip:TemporalEvidenceClipV1)async throws->TemporalEvidenceAdmissionSnapshotV1{try clip.validateIntrinsic();let state=try reader.readCurrentAdmission(for:clip);try state.session.validate(definition:state.definition);try state.profile.validate();guard state.session.workspaceID==clip.workspaceID,state.session.sessionID==clip.target.sessionID,state.session.revision==clip.target.sessionRevision,state.session.sessionSHA256==clip.target.sessionSHA256,state.session.authority.definitionRelease==clip.target.definitionRelease,state.session.authority.packageRelease==(try SurveyPackageReleaseReferenceV1(state.packageRelease)),state.profile.definitionRelease==clip.target.definitionRelease,state.profile.packageRelease==state.session.authority.packageRelease,state.definition.sections.flatMap(\.facts).contains(where:{$0.factID==clip.target.factID}),clip.target.repeatCoordinates.allSatisfy({(try? $0.validate()) != nil}),state.revision.workspaceID==clip.workspaceID,state.evaluatedAt.timeIntervalSinceReferenceDate.isFinite else{throw TemporalEvidenceContractFailureV1.staleSource};return try .init(expectedRevision:state.revision,profile:state.profile,clipsForRequirement:state.clipsForRequirement,clipsForSession:state.clipsForSession,availableByteCount:state.availableByteCount,evaluatedAt:state.evaluatedAt)}
}

protocol TemporalEvidenceScratchLifecycleV1: Sendable {
    func acquire(_ request:CapabilityScratchLeaseRequestV1) async throws -> CapabilityScratchLeaseV1
    func write(_ data:Data,named:String,lease:CapabilityScratchLeaseV1) async throws -> URL
    func finish(lease:CapabilityScratchLeaseV1,disposition:ScratchPublicationDispositionV1,immutableContentReceiptDigest:String?) async throws -> ScratchPublicationLinkageReceiptV1
    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1
}

struct TemporalEvidenceScratchBindingV1:Equatable,Sendable{let request:CapabilityScratchLeaseRequestV1;let lease:CapabilityScratchLeaseV1;let mutationID:MutationIDV1;let contentID:String;let contentSHA256:String;init(request:CapabilityScratchLeaseRequestV1,lease:CapabilityScratchLeaseV1,mutationID:MutationIDV1,contentID:String,contentSHA256:String)throws{self.request=request;self.lease=lease;self.mutationID=mutationID;self.contentID=contentID;self.contentSHA256=contentSHA256;guard request.leaseID==lease.leaseID,request.purpose==lease.purpose,request.operationID==mutationID.rawValue,ContentContractValidationV1.validID(contentID),MutationEnvelopeV1.isSHA256(contentSHA256)else{throw TemporalEvidenceContractFailureV1.invalidValue}}}
enum TemporalEvidencePromotionRecoveryStateV1:String,Codable,CaseIterable,Sendable{case prepared="PREPARED";case originalPromoted="ORIGINAL_PROMOTED";case canonicalCommitted="CANONICAL_COMMITTED";case finished="FINISHED";case quarantined="QUARANTINED"}
struct TemporalEvidencePromotionReservationV1:Equatable,Sendable{let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let contentID:String;let contentSHA256:String;let binding:TemporalEvidenceScratchBindingV1;let state:TemporalEvidencePromotionRecoveryStateV1;init(workspaceID:WorkspaceID,mutationID:MutationIDV1,contentID:String,contentSHA256:String,binding:TemporalEvidenceScratchBindingV1,state:TemporalEvidencePromotionRecoveryStateV1)throws{self.workspaceID=workspaceID;self.mutationID=mutationID;self.contentID=contentID;self.contentSHA256=contentSHA256;self.binding=binding;self.state=state;guard mutationID==binding.mutationID,contentID==binding.contentID,contentSHA256==binding.contentSHA256 else{throw TemporalEvidenceContractFailureV1.invalidValue}}}
protocol TemporalEvidencePromotionRecoveryPortV1:Sendable{func prepare(_ reservation:TemporalEvidencePromotionReservationV1)async throws;func transition(_ reservation:TemporalEvidencePromotionReservationV1,to:TemporalEvidencePromotionRecoveryStateV1)async throws;func reservation(workspaceID:WorkspaceID,mutationID:MutationIDV1)async throws->TemporalEvidencePromotionReservationV1?;func recoverPending()async throws->[TemporalEvidencePromotionReservationV1];func promotedContentExists(_ reservation:TemporalEvidencePromotionReservationV1)async throws->Bool;func adoptCommittedContent(_ reservation:TemporalEvidencePromotionReservationV1,receiptSHA256:String)async throws;func removeUncommittedContent(_ reservation:TemporalEvidencePromotionReservationV1)async throws;func remove(_ reservation:TemporalEvidencePromotionReservationV1)async throws}

protocol TemporalEvidenceImmutableContentPromotingV1: Sendable {
    func promote(bytes:Data,clip:TemporalEvidenceClipV1) async throws -> DraftImmutableContentWriteReceiptV1
}

@MainActor protocol TemporalEvidenceRetentionContentCleaningV1:AnyObject{
    func removeCommittedContent(for mutation:TemporalEvidenceMutationV1,receipt:TemporalEvidenceMutationReceiptV1)async throws
}

enum TemporalEvidenceRetentionCleanupStateV1:String,Codable,Sendable{case prepared="PREPARED";case canonicalCommitted="CANONICAL_COMMITTED"}
struct TemporalEvidenceRetentionCleanupReservationV1:Codable,Equatable,Sendable{let mutation:TemporalEvidenceMutationV1;let state:TemporalEvidenceRetentionCleanupStateV1;let receiptSHA256:String?;init(mutation:TemporalEvidenceMutationV1,state:TemporalEvidenceRetentionCleanupStateV1,receiptSHA256:String?=nil)throws{self.mutation=mutation;self.state=state;self.receiptSHA256=receiptSHA256;try validate()};func validate()throws{try mutation.validate();guard case .removeClip=mutation.payload,(state == .prepared)==(receiptSHA256==nil),receiptSHA256.map(MutationEnvelopeV1.isSHA256) ?? true else{throw TemporalEvidenceContractFailureV1.invalidValue}}}
protocol TemporalEvidenceRetentionCleanupRecoveryPortV1:Sendable{func prepareCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws;func markCleanupCommitted(_ reservation:TemporalEvidenceRetentionCleanupReservationV1,receiptSHA256:String)async throws;func pendingCleanups()async throws->[TemporalEvidenceRetentionCleanupReservationV1];func finishCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws}

@MainActor protocol TemporalEvidenceCanonicalWorkspaceWritingV1: AnyObject {
    func commitTemporalEvidence(_ mutation:TemporalEvidenceMutationV1)throws->TemporalEvidenceMutationReceiptV1
    func temporalEvidenceReceipt(mutationID:MutationIDV1)throws->MutationReceiptV1?
}

struct TemporalEvidenceAcceptanceRequestV1: Equatable, Sendable {
    let clip:TemporalEvidenceClipV1
    let profile:TemporalEvidenceLimitProfileV1
    let review:TemporalEvidenceCaptureReviewV1
    let expectedRevision:WorkspaceExpectedRevisionV1
    let scratchBinding:TemporalEvidenceScratchBindingV1
    let admissionReceipt:TemporalEvidenceIncrementalAdmissionReceiptV1
    let completedBytes:Data
    init(clip:TemporalEvidenceClipV1,profile:TemporalEvidenceLimitProfileV1,review:TemporalEvidenceCaptureReviewV1,expectedRevision:WorkspaceExpectedRevisionV1,scratchBinding:TemporalEvidenceScratchBindingV1,admissionReceipt:TemporalEvidenceIncrementalAdmissionReceiptV1,completedBytes:Data)throws{self.clip=clip;self.profile=profile;self.review=review;self.expectedRevision=expectedRevision;self.scratchBinding=scratchBinding;self.admissionReceipt=admissionReceipt;self.completedBytes=completedBytes;try validate()}
    func validate()throws{try clip.validate(profile:profile);try review.validate();try admissionReceipt.validateTerminal(facts:clip.facts,profile:profile);guard review.workspaceID==clip.workspaceID,review.clipID==clip.clipID,review.decision == .accept,review.reviewedAt==clip.acceptedAt,expectedRevision.workspaceID==clip.workspaceID,scratchBinding.mutationID==clip.mutationID,scratchBinding.contentID==clip.original.contentID,scratchBinding.contentSHA256==clip.original.digests.digest(for:.sha256)?.hexadecimalValue,scratchBinding.request.requestedByteCount==profile.limit(for:clip.facts.kind).maximumByteCount,!completedBytes.isEmpty,UInt64(completedBytes.count)==clip.facts.byteCount else{throw TemporalEvidenceContractFailureV1.invalidValue};let observed=try ContentIntegrityV1.observe(workspaceID:clip.original.workspaceID,contentID:clip.original.contentID,data:completedBytes,mediaType:clip.original.mediaType,algorithms:[.sha256]);guard observed.digests.digest(for:.sha256)==clip.original.digests.digest(for:.sha256)else{throw TemporalEvidenceContractFailureV1.digestMismatch}}
    var mutation:TemporalEvidenceMutationV1{get throws{try .init(workspaceID:clip.workspaceID,expectedRevision:expectedRevision,mutationID:clip.mutationID,payload:.acceptClip(clip,review:review,predecessor:nil))}}
}

struct TemporalEvidenceAcceptanceReceiptV1: Equatable, Sendable {
    let requestSHA256:String
    let contentReceipt:DraftImmutableContentWriteReceiptV1
    let mutationReceipt:TemporalEvidenceMutationReceiptV1
    let scratchReceipt:ScratchPublicationLinkageReceiptV1
    init(request:TemporalEvidenceAcceptanceRequestV1,contentReceipt:DraftImmutableContentWriteReceiptV1,mutationReceipt:TemporalEvidenceMutationReceiptV1,scratchReceipt:ScratchPublicationLinkageReceiptV1)throws{try request.validate();try mutationReceipt.validate(mutation:request.mutation);guard contentReceipt.workspaceID==request.clip.workspaceID,contentReceipt.contentID==request.clip.original.contentID,contentReceipt.digest==request.clip.original.digests.digest(for:.sha256),contentReceipt.byteLength==request.clip.original.byteLength,contentReceipt.mediaType==request.clip.original.mediaType,contentReceipt.mutationID==request.clip.mutationID,scratchReceipt.leaseID==request.scratchBinding.lease.leaseID,scratchReceipt.operationID==request.scratchBinding.request.operationID,scratchReceipt.disposition == .acceptedIntoImmutableContent,scratchReceipt.immutableContentReceiptDigest==mutationReceipt.receiptSHA256 else{throw TemporalEvidenceContractFailureV1.digestMismatch};requestSHA256=try WorkspaceMutationCanonicalV1.sha256(request.mutation);self.contentReceipt=contentReceipt;self.mutationReceipt=mutationReceipt;self.scratchReceipt=scratchReceipt}
}

@MainActor final class TemporalEvidenceCoordinatorV1 {
    private let writer:any TemporalEvidenceCanonicalWorkspaceWritingV1
    private let content:any TemporalEvidenceImmutableContentPromotingV1
    private let scratch:any TemporalEvidenceScratchLifecycleV1
    private let admission:any TemporalEvidenceAdmissionResolvingV1
    private let recovery:any TemporalEvidencePromotionRecoveryPortV1
    private let cleanupRecovery:any TemporalEvidenceRetentionCleanupRecoveryPortV1
    private let contentCleanup:any TemporalEvidenceRetentionContentCleaningV1
    init(writer:any TemporalEvidenceCanonicalWorkspaceWritingV1,content:any TemporalEvidenceImmutableContentPromotingV1,scratch:any TemporalEvidenceScratchLifecycleV1,admission:any TemporalEvidenceAdmissionResolvingV1,recovery:any TemporalEvidencePromotionRecoveryPortV1,cleanupRecovery:any TemporalEvidenceRetentionCleanupRecoveryPortV1,contentCleanup:any TemporalEvidenceRetentionContentCleaningV1){self.writer=writer;self.content=content;self.scratch=scratch;self.admission=admission;self.recovery=recovery;self.cleanupRecovery=cleanupRecovery;self.contentCleanup=contentCleanup}

    func acquireScratch(leaseID:UUID,mutationID:MutationIDV1,contentID:String,contentSHA256:String,profile:TemporalEvidenceLimitProfileV1,kind:TemporalEvidenceMediaKindV1,createdAt:Date,expiresAt:Date)async throws->TemporalEvidenceScratchBindingV1{try profile.validate();let request=try CapabilityScratchLeaseRequestV1(leaseID:leaseID,operationID:mutationID.rawValue,purpose:.capture,requestedByteCount:profile.limit(for:kind).maximumByteCount,createdAt:createdAt,expiresAt:expiresAt);let lease=try await scratch.acquire(request);return try .init(request:request,lease:lease,mutationID:mutationID,contentID:contentID,contentSHA256:contentSHA256)}

    func accept(_ request:TemporalEvidenceAcceptanceRequestV1)async throws->TemporalEvidenceAcceptanceReceiptV1{
        try request.validate();let mutation=try request.mutation
        let prepared=try TemporalEvidencePromotionReservationV1(workspaceID:request.clip.workspaceID,mutationID:mutation.mutationID,contentID:request.clip.original.contentID,contentSHA256:request.scratchBinding.contentSHA256,binding:request.scratchBinding,state:.prepared)
        if let existing=try writer.temporalEvidenceReceipt(mutationID:mutation.mutationID){
            let canonical=try TemporalEvidenceMutationReceiptV1(mutation:mutation,mutationReceipt:existing)
            let contentReceipt=try await content.promote(bytes:request.completedBytes,clip:request.clip)
            let scratchReceipt=try await scratch.finish(lease:request.scratchBinding.lease,disposition:.acceptedIntoImmutableContent,immutableContentReceiptDigest:canonical.receiptSHA256)
            let result=try TemporalEvidenceAcceptanceReceiptV1(request:request,contentReceipt:contentReceipt,mutationReceipt:canonical,scratchReceipt:scratchReceipt);if let pending=try await recovery.reservation(workspaceID:request.clip.workspaceID,mutationID:mutation.mutationID){try await recovery.adoptCommittedContent(pending,receiptSHA256:canonical.receiptSHA256);try await recovery.transition(pending,to:.finished);try await recovery.remove(pending)};return result
        }
        try await recovery.prepare(prepared)
        do{let snapshot=try await admission.currentAdmission(for:request.clip);try snapshot.validate(clip:request.clip,requiredBytes:request.clip.facts.byteCount);guard snapshot.expectedRevision==request.expectedRevision,snapshot.profile==request.profile,snapshot.evaluatedAt<=request.clip.acceptedAt else{throw TemporalEvidenceContractFailureV1.staleSource};let contentReceipt=try await content.promote(bytes:request.completedBytes,clip:request.clip);try await recovery.transition(prepared,to:.originalPromoted);let canonical=try writer.commitTemporalEvidence(mutation);try await recovery.transition(prepared,to:.canonicalCommitted);let scratchReceipt=try await scratch.finish(lease:request.scratchBinding.lease,disposition:.acceptedIntoImmutableContent,immutableContentReceiptDigest:canonical.receiptSHA256);try await recovery.transition(prepared,to:.finished);try await recovery.remove(prepared);return try .init(request:request,contentReceipt:contentReceipt,mutationReceipt:canonical,scratchReceipt:scratchReceipt)}catch{try? await recovery.transition(prepared,to:.quarantined);throw error}
    }

    func reject(lease:CapabilityScratchLeaseV1)async throws->ScratchPublicationLinkageReceiptV1{try await scratch.finish(lease:lease,disposition:.rejected,immutableContentReceiptDigest:nil)}
    func cancel(lease:CapabilityScratchLeaseV1)async throws->ScratchPublicationLinkageReceiptV1{try await scratch.finish(lease:lease,disposition:.cancelled,immutableContentReceiptDigest:nil)}
    func expire(lease:CapabilityScratchLeaseV1)async throws->ScratchPublicationLinkageReceiptV1{try await scratch.finish(lease:lease,disposition:.expired,immutableContentReceiptDigest:nil)}
    func fail(lease:CapabilityScratchLeaseV1)async throws->ScratchPublicationLinkageReceiptV1{try await scratch.finish(lease:lease,disposition:.failed,immutableContentReceiptDigest:nil)}
    func recoverAfterInterruption()async throws->ScratchDataLeaseRecoverySummaryV1{for pending in try await recovery.recoverPending(){if let receipt=try writer.temporalEvidenceReceipt(mutationID:pending.mutationID){let digest=try receipt.canonicalSHA256();try await recovery.adoptCommittedContent(pending,receiptSHA256:digest);let scratchReceipt=try await scratch.finish(lease:pending.binding.lease,disposition:.acceptedIntoImmutableContent,immutableContentReceiptDigest:digest);guard scratchReceipt.leaseID==pending.binding.lease.leaseID,scratchReceipt.operationID==pending.binding.request.operationID else{throw TemporalEvidenceContractFailureV1.digestMismatch};try await recovery.transition(pending,to:.finished);try await recovery.remove(pending)}else{guard pending.state != .canonicalCommitted else{throw TemporalEvidenceContractFailureV1.interruption};if pending.state == .prepared{if try await recovery.promotedContentExists(pending){try await recovery.removeUncommittedContent(pending)}}else if pending.state == .originalPromoted || pending.state == .quarantined{try await recovery.removeUncommittedContent(pending)};let scratchReceipt=try await scratch.finish(lease:pending.binding.lease,disposition:.failed,immutableContentReceiptDigest:nil);guard scratchReceipt.leaseID==pending.binding.lease.leaseID,scratchReceipt.operationID==pending.binding.request.operationID else{throw TemporalEvidenceContractFailureV1.digestMismatch};try await recovery.transition(pending,to:.finished);try await recovery.remove(pending)}};_ = try await recoverPendingRetentionCleanup();return try await scratch.recoverAfterInterruption()}
    func recoverPendingRetentionCleanup()async throws->Int{let values=try await cleanupRecovery.pendingCleanups();for pending in values{if let generic=try writer.temporalEvidenceReceipt(mutationID:pending.mutation.mutationID){let receipt=try TemporalEvidenceMutationReceiptV1(mutation:pending.mutation,mutationReceipt:generic);try await cleanupRecovery.markCleanupCommitted(pending,receiptSHA256:receipt.receiptSHA256);try await contentCleanup.removeCommittedContent(for:pending.mutation,receipt:receipt);try await cleanupRecovery.finishCleanup(pending)}else{guard pending.state == .prepared else{throw TemporalEvidenceContractFailureV1.interruption};try await cleanupRecovery.finishCleanup(pending)}};return values.count}

    func appendAnchor(_ anchor:TimecodedEvidenceAnchorV1,clip:TemporalEvidenceClipV1,predecessor:TimecodedEvidenceAnchorV1?,expectedRevision:WorkspaceExpectedRevisionV1)throws->TemporalEvidenceMutationReceiptV1{let mutation=try TemporalEvidenceMutationV1(workspaceID:clip.workspaceID,expectedRevision:expectedRevision,mutationID:anchor.mutationID,payload:.appendAnchor(anchor,clip:clip,predecessor:predecessor));if let existing=try writer.temporalEvidenceReceipt(mutationID:anchor.mutationID){return try .init(mutation:mutation,mutationReceipt:existing)};return try writer.commitTemporalEvidence(mutation)}
    func validateDerivativeReplacement(_ value:TemporalEvidenceDerivativeV1,clip:TemporalEvidenceClipV1,predecessor:TemporalEvidenceDerivativeV1?)throws{try value.validate(clip:clip);if let predecessor{try predecessor.validate(clip:clip);guard value.supersedesDerivativeID==predecessor.derivativeID,value.revision==predecessor.revision+1,value.kind==predecessor.kind else{throw TemporalEvidenceContractFailureV1.invalidTransition}}else{guard value.revision==1,value.supersedesDerivativeID==nil else{throw TemporalEvidenceContractFailureV1.invalidTransition}}}
    func validateRetention(_ value:TemporalEvidenceRetentionEventV1,clip:TemporalEvidenceClipV1,predecessor:TemporalEvidenceRetentionEventV1?)throws{try value.validate(clip:clip);if let predecessor{try predecessor.validate(clip:clip);guard value.supersedesEventID==predecessor.eventID,value.predecessorEventSHA256==predecessor.eventSHA256,value.revision==predecessor.revision+1 else{throw TemporalEvidenceContractFailureV1.invalidTransition}}else{guard value.revision==1,value.supersedesEventID==nil else{throw TemporalEvidenceContractFailureV1.invalidTransition}}}
    func registerDerivative(_ derivative:TemporalEvidenceDerivativeV1,successor:TemporalEvidenceClipV1,predecessorClip:TemporalEvidenceClipV1,predecessorDerivative:TemporalEvidenceDerivativeV1?,expectedRevision:WorkspaceExpectedRevisionV1)throws->TemporalEvidenceMutationReceiptV1{try validateDerivativeReplacement(derivative,clip:predecessorClip,predecessor:predecessorDerivative);let mutation=try TemporalEvidenceMutationV1(workspaceID:successor.workspaceID,expectedRevision:expectedRevision,mutationID:successor.mutationID,payload:.registerDerivative(successor,derivative:derivative,predecessorClip:predecessorClip,predecessorDerivative:predecessorDerivative));if let existing=try writer.temporalEvidenceReceipt(mutationID:mutation.mutationID){return try .init(mutation:mutation,mutationReceipt:existing)};return try writer.commitTemporalEvidence(mutation)}
    func applyRetention(_ event:TemporalEvidenceRetentionEventV1,successor:TemporalEvidenceClipV1,predecessorClip:TemporalEvidenceClipV1,predecessorEvent:TemporalEvidenceRetentionEventV1?,expectedRevision:WorkspaceExpectedRevisionV1)throws->TemporalEvidenceMutationReceiptV1{try validateRetention(event,clip:predecessorClip,predecessor:predecessorEvent);let mutation=try TemporalEvidenceMutationV1(workspaceID:successor.workspaceID,expectedRevision:expectedRevision,mutationID:successor.mutationID,payload:.applyRetention(successor,event:event,predecessorClip:predecessorClip,predecessorEvent:predecessorEvent));if let existing=try writer.temporalEvidenceReceipt(mutationID:mutation.mutationID){return try .init(mutation:mutation,mutationReceipt:existing)};return try writer.commitTemporalEvidence(mutation)}
    func removeClip(_ event:TemporalEvidenceRetentionEventV1,clips:[TemporalEvidenceClipV1],anchors:[TimecodedEvidenceAnchorV1],derivatives:[TemporalEvidenceDerivativeV1],predecessorEvent:TemporalEvidenceRetentionEventV1?,expectedRevision:WorkspaceExpectedRevisionV1)async throws->TemporalEvidenceMutationReceiptV1{guard let predecessor=clips.first(where:{$0.clipID==event.clipID})else{throw TemporalEvidenceContractFailureV1.invalidTransition};try validateRetention(event,clip:predecessor,predecessor:predecessorEvent);guard event.disposition == .deleteClip || event.disposition == .eraseWorkspace else{throw TemporalEvidenceContractFailureV1.invalidTransition};let mutation=try TemporalEvidenceMutationV1(workspaceID:event.workspaceID,expectedRevision:expectedRevision,mutationID:event.mutationID,payload:.removeClip(event:event,clips:clips,anchors:anchors,derivatives:derivatives,predecessorEvent:predecessorEvent)),pending=try TemporalEvidenceRetentionCleanupReservationV1(mutation:mutation,state:.prepared);try await cleanupRecovery.prepareCleanup(pending);let receipt:TemporalEvidenceMutationReceiptV1;if let existing=try writer.temporalEvidenceReceipt(mutationID:mutation.mutationID){receipt=try .init(mutation:mutation,mutationReceipt:existing)}else{receipt=try writer.commitTemporalEvidence(mutation)};try await cleanupRecovery.markCleanupCommitted(pending,receiptSHA256:receipt.receiptSHA256);try await contentCleanup.removeCommittedContent(for:mutation,receipt:receipt);try await cleanupRecovery.finishCleanup(pending);return receipt}
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row184 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_Content_TemporalEvidenceCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Application_Content_TemporalEvidenceCoordinatorV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

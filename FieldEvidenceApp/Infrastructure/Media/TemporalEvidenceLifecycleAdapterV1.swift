import Foundation

struct TemporalEvidenceScratchLifecycleAdapterV1: TemporalEvidenceScratchLifecycleV1, Sendable {
    private let base:any CapabilityScratchLeasePortV1
    init(base:any CapabilityScratchLeasePortV1){self.base=base}
    func acquire(_ request:CapabilityScratchLeaseRequestV1)async throws->CapabilityScratchLeaseV1{guard request.purpose == .capture else{throw TemporalEvidenceContractFailureV1.invalidValue};return try await base.acquire(request)}
    func write(_ data:Data,named:String,lease:CapabilityScratchLeaseV1)async throws->URL{guard lease.purpose == .capture,!data.isEmpty else{throw TemporalEvidenceContractFailureV1.invalidValue};return try await base.write(data,named:named,lease:lease)}
    func finish(lease:CapabilityScratchLeaseV1,disposition:ScratchPublicationDispositionV1,immutableContentReceiptDigest:String?)async throws->ScratchPublicationLinkageReceiptV1{guard lease.purpose == .capture else{throw TemporalEvidenceContractFailureV1.invalidValue};return try await base.finish(lease:lease,disposition:disposition,immutableContentReceiptDigest:immutableContentReceiptDigest)}
    func recoverAfterInterruption()async throws->ScratchDataLeaseRecoverySummaryV1{try await base.recoverAfterInterruption()}
}

struct TemporalEvidenceExistingContentPromotionAdapterV1:TemporalEvidenceImmutableContentPromotingV1,Sendable{
    private let writer:any DraftImmutableContentWriterV1
    init(writer:any DraftImmutableContentWriterV1){self.writer=writer}
    func promote(bytes:Data,clip:TemporalEvidenceClipV1)async throws->DraftImmutableContentWriteReceiptV1{try clip.validateIntrinsic();guard Int64(bytes.count)==clip.original.byteLength,let digest=clip.original.digests.digest(for:.sha256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};let request=try DraftImmutableContentWriteRequestV1(workspaceID:clip.workspaceID,contentID:clip.original.contentID,digest:digest,byteLength:clip.original.byteLength,mediaType:clip.original.mediaType,mutationID:clip.mutationID,createdAt:clip.original.createdAt);let receipt=try await writer.persistImmutableOriginal(bytes:bytes,request:request);try receipt.validate(request:request,bytes:bytes);guard receipt.locatorID==clip.locator.locatorID,receipt.relativePath==request.relativePath else{throw TemporalEvidenceContractFailureV1.digestMismatch};return receipt}
}

typealias TemporalEvidenceSessionLookupV1 = @MainActor @Sendable (WorkspaceID,UUID)throws->SurveySessionV1?
typealias TemporalEvidenceDefinitionLookupV1 = @MainActor @Sendable (SurveyDefinitionReleaseReferenceV1)throws->SurveyDefinitionReleaseV1?
typealias TemporalEvidencePackageLookupV1 = @MainActor @Sendable (SurveyPackageReleaseReferenceV1)throws->InspectionPackageReleaseV1?
typealias TemporalEvidenceProfileLookupV1 = @MainActor @Sendable (UUID,UInt64)throws->TemporalEvidenceLimitProfileV1?
typealias TemporalEvidenceClipLookupV1 = @MainActor @Sendable (WorkspaceID,UUID)throws->[TemporalEvidenceClipV1]
typealias TemporalEvidenceAvailableBytesLookupV1 = @MainActor @Sendable (WorkspaceID)throws->UInt64

/// Live admission reader: revision and clock always come from the canonical
/// workspace dependencies; released/session rows and storage facts are
/// mandatory exact readers supplied by that same production composition.
@MainActor final class TemporalEvidenceCanonicalAdmissionReaderV1:TemporalEvidenceAuthoritativeAdmissionReadingV1{
    private let dependencies:WorkspacePackageLifecycleDependenciesV1
    private let session:TemporalEvidenceSessionLookupV1
    private let definition:TemporalEvidenceDefinitionLookupV1
    private let packageRelease:TemporalEvidencePackageLookupV1
    private let profile:TemporalEvidenceProfileLookupV1
    private let clips:TemporalEvidenceClipLookupV1
    private let availableBytes:TemporalEvidenceAvailableBytesLookupV1
    init(dependencies:WorkspacePackageLifecycleDependenciesV1,session:@escaping TemporalEvidenceSessionLookupV1,definition:@escaping TemporalEvidenceDefinitionLookupV1,packageRelease:@escaping TemporalEvidencePackageLookupV1,profile:@escaping TemporalEvidenceProfileLookupV1,clips:@escaping TemporalEvidenceClipLookupV1,availableBytes:@escaping TemporalEvidenceAvailableBytesLookupV1){self.dependencies=dependencies;self.session=session;self.definition=definition;self.packageRelease=packageRelease;self.profile=profile;self.clips=clips;self.availableBytes=availableBytes}
    func readCurrentAdmission(for clip:TemporalEvidenceClipV1)throws->TemporalEvidenceAuthoritativeAdmissionStateV1{
        try clip.validateIntrinsic();guard clip.workspaceID==dependencies.workspaceID,let currentSession=try session(clip.workspaceID,clip.target.sessionID),let currentDefinition=try definition(clip.target.definitionRelease),let currentPackage=try packageRelease(currentSession.authority.packageRelease),let currentProfile=try profile(clip.limitProfileID,clip.limitProfileRevision)else{throw TemporalEvidenceContractFailureV1.staleSource}
        let revision=try dependencies.writer.currentRevision();guard revision.workspaceID==clip.workspaceID,revision.generationID==dependencies.generationID,currentProfile==clip.limitProfile else{throw TemporalEvidenceContractFailureV1.staleSource}
        let history=try clips(clip.workspaceID,clip.target.sessionID);try history.forEach{$0.validateIntrinsic()};guard history.allSatisfy({$0.workspaceID==clip.workspaceID&&$0.target.sessionID==clip.target.sessionID}),Set(history.map(\.clipID)).count==history.count else{throw TemporalEvidenceContractFailureV1.staleSource};let superseded=Set(history.compactMap(\.supersedesClipID)),currentClips=history.filter{!superseded.contains($0.clipID)};guard Set(currentClips.map{$0.original.contentID}).count==currentClips.count else{throw TemporalEvidenceContractFailureV1.staleSource}
        try SurveyTemporalEvidenceBindingV1.validate(clip:clip,profile:currentProfile,session:currentSession,definition:currentDefinition,existingClips:currentClips)
        let requirementCount=currentClips.filter{$0.target.factID==clip.target.factID&&$0.target.repeatCoordinates==clip.target.repeatCoordinates}.count
        return TemporalEvidenceAuthoritativeAdmissionStateV1(revision:.init(snapshot:revision),session:currentSession,definition:currentDefinition,packageRelease:currentPackage,profile:currentProfile,clipsForRequirement:requirementCount,clipsForSession:currentClips.count,availableByteCount:try availableBytes(clip.workspaceID),evaluatedAt:dependencies.clock.now())
    }
}

typealias TemporalEvidencePromotedContentVerificationV1 = @Sendable (WorkspaceID,String,String)async throws->Bool
typealias TemporalEvidencePromotedContentRemovalV1 = @Sendable (WorkspaceID,String,String)async throws->Void

@MainActor protocol TemporalEvidenceRetentionContentCleanupResolvingV1:AnyObject{func removeCommittedContent(for mutation:TemporalEvidenceMutationV1,receipt:TemporalEvidenceMutationReceiptV1)async throws}
@MainActor final class TemporalEvidenceRetentionContentCleanupAdapterV1:TemporalEvidenceRetentionContentCleaningV1{
    private let resolver:any TemporalEvidenceRetentionContentCleanupResolvingV1
    init(resolver:any TemporalEvidenceRetentionContentCleanupResolvingV1){self.resolver=resolver}
    func removeCommittedContent(for mutation:TemporalEvidenceMutationV1,receipt:TemporalEvidenceMutationReceiptV1)async throws{try mutation.validate();try receipt.validate(mutation:mutation);guard case .removeClip=mutation.payload else{throw TemporalEvidenceContractFailureV1.invalidTransition};try await resolver.removeCommittedContent(for:mutation,receipt:receipt)}
}

actor TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1:TemporalEvidenceRetentionCleanupRecoveryPortV1{
    private let workspaceID:WorkspaceID
    private let manifestURL:URL
    private let fileManager:FileManager
    init(generationRootURL:URL,workspaceID:WorkspaceID,fileManager:FileManager = .default)throws{guard generationRootURL.isFileURL else{throw TemporalEvidenceContractFailureV1.invalidValue};self.workspaceID=workspaceID;self.fileManager=fileManager;let root=generationRootURL.standardizedFileURL.appendingPathComponent("operational",isDirectory:true).appendingPathComponent("temporal-evidence-promotion-v1",isDirectory:true);try fileManager.createDirectory(at:root,withIntermediateDirectories:true);manifestURL=root.appendingPathComponent(workspaceID.rawValue.uuidString.lowercased()+"-retention-cleanup.json",isDirectory:false)}
    func prepareCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws{guard reservation.mutation.workspaceID==workspaceID,reservation.state == .prepared else{throw TemporalEvidenceContractFailureV1.invalidTransition};var values=try load();if let old=values.first(where:{$0.mutation.mutationID==reservation.mutation.mutationID}){guard old==reservation else{throw TemporalEvidenceContractFailureV1.invalidTransition};return};values.append(reservation);try save(values)}
    func markCleanupCommitted(_ reservation:TemporalEvidenceRetentionCleanupReservationV1,receiptSHA256:String)async throws{guard MutationEnvelopeV1.isSHA256(receiptSHA256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};var values=try load();guard let index=values.firstIndex(where:{$0.mutation.mutationID==reservation.mutation.mutationID}),values[index].mutation==reservation.mutation else{throw TemporalEvidenceContractFailureV1.interruption};if values[index].state == .canonicalCommitted{guard values[index].receiptSHA256==receiptSHA256 else{throw TemporalEvidenceContractFailureV1.digestMismatch};return};values[index]=try .init(mutation:reservation.mutation,state:.canonicalCommitted,receiptSHA256:receiptSHA256);try save(values)}
    func pendingCleanups()async throws->[TemporalEvidenceRetentionCleanupReservationV1]{try load().sorted{$0.mutation.mutationID.rawValue.uuidString<$1.mutation.mutationID.rawValue.uuidString}}
    func finishCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws{var values=try load();guard let index=values.firstIndex(where:{$0.mutation.mutationID==reservation.mutation.mutationID})else{return};guard values[index].mutation==reservation.mutation else{throw TemporalEvidenceContractFailureV1.invalidTransition};values.remove(at:index);try save(values)}
    private func load()throws->[TemporalEvidenceRetentionCleanupReservationV1]{guard fileManager.fileExists(atPath:manifestURL.path)else{return[]};let data=try Data(contentsOf:manifestURL,options:.mappedIfSafe);guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};let values=try JSONDecoder().decode([TemporalEvidenceRetentionCleanupReservationV1].self,from:data);try values.forEach{$0.validate()};guard values.allSatisfy({$0.mutation.workspaceID==workspaceID}),Set(values.map{$0.mutation.mutationID}).count==values.count else{throw TemporalEvidenceContractFailureV1.digestMismatch};return values}
    private func save(_ values:[TemporalEvidenceRetentionCleanupReservationV1])throws{let sorted=values.sorted{$0.mutation.mutationID.rawValue.uuidString<$1.mutation.mutationID.rawValue.uuidString};let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let data=try encoder.encode(sorted);guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};try data.write(to:manifestURL,options:[.atomic,.completeFileProtectionUnlessOpen])}
}

/// Bounded operational manifest under the existing generation root. It is
/// recovery metadata only: canonical clip/anchor truth remains in the generic
/// workspace writer and immutable bytes remain in the existing content store.
actor TemporalEvidencePromotionRecoveryFileAdapterV1:TemporalEvidencePromotionRecoveryPortV1{
    private struct Record:Codable,Equatable{let workspaceID:UUID;let mutationID:UUID;let contentID:String;let contentSHA256:String;let requestLeaseID:UUID;let operationID:UUID;let purpose:CapabilityScratchPurposeV1;let requestedByteCount:UInt64;let createdAt:Date;let expiresAt:Date;let leaseID:UUID;let relativeDirectory:String;let state:TemporalEvidencePromotionRecoveryStateV1
        init(_ value:TemporalEvidencePromotionReservationV1,state:TemporalEvidencePromotionRecoveryStateV1?=nil){workspaceID=value.workspaceID.rawValue;mutationID=value.mutationID.rawValue;contentID=value.contentID;contentSHA256=value.contentSHA256;requestLeaseID=value.binding.request.leaseID;operationID=value.binding.request.operationID;purpose=value.binding.request.purpose;requestedByteCount=value.binding.request.requestedByteCount;createdAt=value.binding.request.createdAt;expiresAt=value.binding.request.expiresAt;leaseID=value.binding.lease.leaseID;relativeDirectory=value.binding.lease.relativeDirectory;self.state=state ?? value.state}
        func value()throws->TemporalEvidencePromotionReservationV1{let workspace=try WorkspaceID(rawValue:workspaceID),mutation=try MutationIDV1(rawValue:mutationID),request=try CapabilityScratchLeaseRequestV1(leaseID:requestLeaseID,operationID:operationID,purpose:purpose,requestedByteCount:requestedByteCount,createdAt:createdAt,expiresAt:expiresAt),lease=CapabilityScratchLeaseV1(leaseID:leaseID,purpose:purpose,relativeDirectory:relativeDirectory),binding=try TemporalEvidenceScratchBindingV1(request:request,lease:lease,mutationID:mutation,contentID:contentID,contentSHA256:contentSHA256);return try .init(workspaceID:workspace,mutationID:mutation,contentID:contentID,contentSHA256:contentSHA256,binding:binding,state:state)}
    }
    private let workspaceID:WorkspaceID
    private let manifestURL:URL
    private let fileManager:FileManager
    private let verify:TemporalEvidencePromotedContentVerificationV1
    private let delete:TemporalEvidencePromotedContentRemovalV1
    init(generationRootURL:URL,workspaceID:WorkspaceID,fileManager:FileManager = .default,verify:@escaping TemporalEvidencePromotedContentVerificationV1,remove:@escaping TemporalEvidencePromotedContentRemovalV1)throws{guard generationRootURL.isFileURL else{throw TemporalEvidenceContractFailureV1.invalidValue};self.workspaceID=workspaceID;self.fileManager=fileManager;self.verify=verify;delete=remove;let root=generationRootURL.standardizedFileURL.appendingPathComponent("operational",isDirectory:true).appendingPathComponent("temporal-evidence-promotion-v1",isDirectory:true);try fileManager.createDirectory(at:root,withIntermediateDirectories:true);manifestURL=root.appendingPathComponent(workspaceID.rawValue.uuidString.lowercased()+".json",isDirectory:false)}
    func prepare(_ reservation:TemporalEvidencePromotionReservationV1)async throws{guard reservation.workspaceID==workspaceID,reservation.state == .prepared else{throw TemporalEvidenceContractFailureV1.invalidTransition};var records=try load();if let old=records.first(where:{$0.mutationID==reservation.mutationID.rawValue}){guard old==Record(reservation)else{throw TemporalEvidenceContractFailureV1.invalidTransition};return};records.append(Record(reservation));try save(records)}
    func transition(_ reservation:TemporalEvidencePromotionReservationV1,to state:TemporalEvidencePromotionRecoveryStateV1)async throws{var records=try load();guard let index=records.firstIndex(where:{$0.workspaceID==reservation.workspaceID.rawValue&&$0.mutationID==reservation.mutationID.rawValue})else{throw TemporalEvidenceContractFailureV1.interruption};let current=records[index],same=Record(reservation,state:current.state);guard current==same,Self.permits(current.state,state)else{throw TemporalEvidenceContractFailureV1.invalidTransition};records[index]=Record(reservation,state:state);try save(records)}
    func reservation(workspaceID:WorkspaceID,mutationID:MutationIDV1)async throws->TemporalEvidencePromotionReservationV1?{guard workspaceID==self.workspaceID else{throw TemporalEvidenceContractFailureV1.wrongWorkspace};return try load().first(where:{$0.mutationID==mutationID.rawValue})?.value()}
    func recoverPending()async throws->[TemporalEvidencePromotionReservationV1]{try load().filter{$0.state != .finished}.sorted{$0.mutationID.uuidString<$1.mutationID.uuidString}.map{try $0.value()}}
    func promotedContentExists(_ reservation:TemporalEvidencePromotionReservationV1)async throws->Bool{guard reservation.workspaceID==workspaceID else{throw TemporalEvidenceContractFailureV1.wrongWorkspace};return try await verify(reservation.workspaceID,reservation.contentID,reservation.contentSHA256)}
    func adoptCommittedContent(_ reservation:TemporalEvidencePromotionReservationV1,receiptSHA256:String)async throws{guard MutationEnvelopeV1.isSHA256(receiptSHA256),try await verify(reservation.workspaceID,reservation.contentID,reservation.contentSHA256)else{throw TemporalEvidenceContractFailureV1.digestMismatch}}
    func removeUncommittedContent(_ reservation:TemporalEvidencePromotionReservationV1)async throws{guard reservation.workspaceID==workspaceID else{throw TemporalEvidenceContractFailureV1.wrongWorkspace};try await delete(reservation.workspaceID,reservation.contentID,reservation.contentSHA256)}
    func remove(_ reservation:TemporalEvidencePromotionReservationV1)async throws{var records=try load();guard let index=records.firstIndex(where:{$0.mutationID==reservation.mutationID.rawValue})else{return};guard records[index].state == .finished else{throw TemporalEvidenceContractFailureV1.invalidTransition};records.remove(at:index);try save(records)}
    private static func permits(_ from:TemporalEvidencePromotionRecoveryStateV1,_ to:TemporalEvidencePromotionRecoveryStateV1)->Bool{if from==to{return true};switch(from,to){case(.prepared,.originalPromoted),(.prepared,.quarantined),(.prepared,.finished),(.originalPromoted,.canonicalCommitted),(.originalPromoted,.quarantined),(.originalPromoted,.finished),(.canonicalCommitted,.finished),(.quarantined,.finished):return true;default:return false}}
    private func load()throws->[Record]{guard fileManager.fileExists(atPath:manifestURL.path)else{return[]};let data=try Data(contentsOf:manifestURL,options:.mappedIfSafe);guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};let values=try JSONDecoder().decode([Record].self,from:data);guard Set(values.map{$0.mutationID}).count==values.count,values.allSatisfy({$0.workspaceID==workspaceID.rawValue})else{throw TemporalEvidenceContractFailureV1.digestMismatch};return values}
    private func save(_ records:[Record])throws{let sorted=records.sorted{$0.mutationID.uuidString<$1.mutationID.uuidString};let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let data=try encoder.encode(sorted);guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};try data.write(to:manifestURL,options:[.atomic,.completeFileProtectionUnlessOpen])}
}

/// C33 has no microphone/camera provider. This actor is only the bounded
/// scratch/content lifecycle bridge consumed by the later explicit-intent UI.
@MainActor final class TemporalEvidenceLifecycleAdapterV1 {
    let scratch:TemporalEvidenceScratchLifecycleAdapterV1
    let content:TemporalEvidenceExistingContentPromotionAdapterV1
    let coordinator:TemporalEvidenceCoordinatorV1
    init(writer:any TemporalEvidenceCanonicalWorkspaceWritingV1,scratchLeases:any CapabilityScratchLeasePortV1,contentWriter:any DraftImmutableContentWriterV1,admissionReader:TemporalEvidenceCanonicalAdmissionReaderV1,recovery:any TemporalEvidencePromotionRecoveryPortV1,cleanupRecovery:any TemporalEvidenceRetentionCleanupRecoveryPortV1,contentCleanup:any TemporalEvidenceRetentionContentCleaningV1){let scratch=TemporalEvidenceScratchLifecycleAdapterV1(base:scratchLeases),content=TemporalEvidenceExistingContentPromotionAdapterV1(writer:contentWriter);self.scratch=scratch;self.content=content;coordinator=TemporalEvidenceCoordinatorV1(writer:writer,content:content,scratch:scratch,admission:TemporalEvidenceTrustedAdmissionAuthorityV1(reader:admissionReader),recovery:recovery,cleanupRecovery:cleanupRecovery,contentCleanup:contentCleanup)}
    convenience init(dependencies:WorkspacePackageLifecycleDependenciesV1,scratchLeases:any CapabilityScratchLeasePortV1,contentWriter:any DraftImmutableContentWriterV1,admissionReader:TemporalEvidenceCanonicalAdmissionReaderV1,recovery:any TemporalEvidencePromotionRecoveryPortV1,cleanupRecovery:any TemporalEvidenceRetentionCleanupRecoveryPortV1,contentCleanup:any TemporalEvidenceRetentionContentCleaningV1){self.init(writer:dependencies.writer,scratchLeases:scratchLeases,contentWriter:contentWriter,admissionReader:admissionReader,recovery:recovery,cleanupRecovery:cleanupRecovery,contentCleanup:contentCleanup)}
    func recoverAfterInterruption()async throws->ScratchDataLeaseRecoverySummaryV1{try await coordinator.recoverAfterInterruption()}
    func recoverPendingRetentionCleanup()async throws->Int{try await coordinator.recoverPendingRetentionCleanup()}
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row185 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Media_TemporalEvidenceLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

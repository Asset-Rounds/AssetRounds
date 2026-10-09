import Darwin
import Foundation

struct TemporalEvidenceScratchLifecycleAdapterV1: TemporalEvidenceScratchLifecycleV1, Sendable {
    private let base:any CapabilityScratchLeasePortV1
    private let producerOwner: StoreSessionCoordinator?
    init(base:any CapabilityScratchLeasePortV1, producerOwner: StoreSessionCoordinator? = nil){self.base=base;self.producerOwner=producerOwner}
    private func withProducerLifetime<Value: Sendable>(
        _ operation: @MainActor () async throws -> Value
    ) async throws -> Value {
        if let producerOwner { return try await producerOwner.withTemporalProducer(operation) }
        #if DEBUG
        return try await operation()
        #else
        throw GenerationLeaseRegistryFailureV1.uncertainOwner
        #endif
    }
    func acquire(_ request:CapabilityScratchLeaseRequestV1)async throws->CapabilityScratchLeaseV1{return try await withProducerLifetime { guard request.purpose == .capture else{throw TemporalEvidenceContractFailureV1.invalidValue};return try await base.acquire(request) }}
    func write(_ data:Data,named:String,lease:CapabilityScratchLeaseV1)async throws->URL{return try await withProducerLifetime { guard lease.purpose == .capture,!data.isEmpty else{throw TemporalEvidenceContractFailureV1.invalidValue};return try await base.write(data,named:named,lease:lease) }}
    func finish(lease:CapabilityScratchLeaseV1,disposition:ScratchPublicationDispositionV1,immutableContentReceiptDigest:String?)async throws->ScratchPublicationLinkageReceiptV1{return try await withProducerLifetime { guard lease.purpose == .capture else{throw TemporalEvidenceContractFailureV1.invalidValue};return try await base.finish(lease:lease,disposition:disposition,immutableContentReceiptDigest:immutableContentReceiptDigest) }}
    func recoverAfterInterruption()async throws->ScratchDataLeaseRecoverySummaryV1{return try await withProducerLifetime { try await base.recoverAfterInterruption() }}
}

struct TemporalEvidenceExistingContentPromotionAdapterV1:TemporalEvidenceImmutableContentPromotingV1,Sendable{
    private let writer:any DraftImmutableContentWriterV1
    private let producerOwner: StoreSessionCoordinator?
    init(writer:any DraftImmutableContentWriterV1, producerOwner: StoreSessionCoordinator? = nil){self.writer=writer;self.producerOwner=producerOwner}
    private func withProducerLifetime<Value: Sendable>(
        _ operation: @MainActor () async throws -> Value
    ) async throws -> Value {
        if let producerOwner { return try await producerOwner.withTemporalProducer(operation) }
        #if DEBUG
        return try await operation()
        #else
        throw GenerationLeaseRegistryFailureV1.uncertainOwner
        #endif
    }
    func promote(bytes:Data,clip:TemporalEvidenceClipV1)async throws->DraftImmutableContentWriteReceiptV1{return try await withProducerLifetime { try clip.validateIntrinsic();guard Int64(bytes.count)==clip.original.byteLength,let digest=clip.original.digests.digest(for:.sha256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};let request=try DraftImmutableContentWriteRequestV1(workspaceID:clip.workspaceID,contentID:clip.original.contentID,digest:digest,byteLength:clip.original.byteLength,mediaType:clip.original.mediaType,mutationID:clip.mutationID,createdAt:clip.original.createdAt);let receipt=try await writer.persistImmutableOriginal(bytes:bytes,request:request);try receipt.validate(request:request,bytes:bytes);guard receipt.locatorID==clip.locator.locatorID,receipt.relativePath==request.relativePath else{throw TemporalEvidenceContractFailureV1.digestMismatch};return receipt }}
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
        let history=try clips(clip.workspaceID,clip.target.sessionID);try history.forEach{try $0.validateIntrinsic()};guard history.allSatisfy({$0.workspaceID==clip.workspaceID&&$0.target.sessionID==clip.target.sessionID}),Set(history.map(\.clipID)).count==history.count else{throw TemporalEvidenceContractFailureV1.staleSource};let superseded=Set(history.compactMap(\.supersedesClipID)),currentClips=history.filter{!superseded.contains($0.clipID)};guard Set(currentClips.map{$0.original.contentID}).count==currentClips.count else{throw TemporalEvidenceContractFailureV1.staleSource}
        try SurveyTemporalEvidenceBindingV1.validate(clip:clip,profile:currentProfile,session:currentSession,definition:currentDefinition,existingClips:currentClips)
        let requirementCount=currentClips.filter{$0.target.factID==clip.target.factID&&$0.target.repeatCoordinates==clip.target.repeatCoordinates}.count
        return TemporalEvidenceAuthoritativeAdmissionStateV1(revision:.init(snapshot:revision),session:currentSession,definition:currentDefinition,packageRelease:currentPackage,profile:currentProfile,clipsForRequirement:requirementCount,clipsForSession:currentClips.count,availableByteCount:try availableBytes(clip.workspaceID),evaluatedAt:dependencies.clock.now())
    }
}

typealias TemporalEvidencePromotedContentVerificationV1 = @Sendable (WorkspaceID,String,String)async throws->Bool
typealias TemporalEvidencePromotedContentRemovalV1 = @Sendable (WorkspaceID,String,String)async throws->Void

enum TemporalEvidenceOperationalJournalReadBoundaryV1: Equatable, Sendable {
    case afterLeafStat
    case afterOpen
    case accumulatedRead(Int)
}

typealias TemporalEvidenceOperationalJournalReadBoundaryHookV1 = @Sendable (TemporalEvidenceOperationalJournalReadBoundaryV1) throws -> Void

@MainActor protocol TemporalEvidenceRetentionContentCleanupResolvingV1:AnyObject{func removeCommittedContent(for mutation:TemporalEvidenceMutationV1,receipt:TemporalEvidenceMutationReceiptV1)async throws}
@MainActor final class TemporalEvidenceRetentionContentCleanupAdapterV1:TemporalEvidenceRetentionContentCleaningV1{
    private let resolver:any TemporalEvidenceRetentionContentCleanupResolvingV1
    init(resolver:any TemporalEvidenceRetentionContentCleanupResolvingV1){self.resolver=resolver}
    func removeCommittedContent(for mutation:TemporalEvidenceMutationV1,receipt:TemporalEvidenceMutationReceiptV1)async throws{try mutation.validate();try receipt.validate(mutation:mutation);guard case .removeClip=mutation.payload else{throw TemporalEvidenceContractFailureV1.invalidTransition};try await resolver.removeCommittedContent(for:mutation,receipt:receipt)}
}

actor TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1:TemporalEvidenceRetentionCleanupRecoveryPortV1{
    private let workspaceID:WorkspaceID
    private let storage:TemporalEvidenceOperationalJournalStorageV1
    private let manifestName:String
    init(generationRootURL:URL,workspaceID:WorkspaceID,fileManager:FileManager = .default,readBoundary:TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil,publicationBoundary:TemporalEvidenceOperationalPublicationBoundaryHookV2? = nil)throws{guard generationRootURL.isFileURL else{throw TemporalEvidenceContractFailureV1.invalidValue};_ = fileManager;self.workspaceID=workspaceID;storage=try .init(generationRootURL:generationRootURL,readBoundary:readBoundary,publicationBoundary:publicationBoundary);manifestName=workspaceID.rawValue.uuidString.lowercased()+"-retention-cleanup.json"}
    func prepareCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws{guard reservation.mutation.workspaceID==workspaceID,reservation.state == .prepared else{throw TemporalEvidenceContractFailureV1.invalidTransition};try mutate { values in if let old=values.first(where:{$0.mutation.mutationID==reservation.mutation.mutationID}){guard old==reservation else{throw TemporalEvidenceContractFailureV1.invalidTransition};return};values.append(reservation);}}
    func markCleanupCommitted(_ reservation:TemporalEvidenceRetentionCleanupReservationV1,receiptSHA256:String)async throws{guard MutationEnvelopeV1.isSHA256(receiptSHA256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};try mutate { values in guard let index=values.firstIndex(where:{$0.mutation.mutationID==reservation.mutation.mutationID}),values[index].mutation==reservation.mutation else{throw TemporalEvidenceContractFailureV1.interruption};if values[index].state == .canonicalCommitted{guard values[index].receiptSHA256==receiptSHA256 else{throw TemporalEvidenceContractFailureV1.digestMismatch};return};values[index]=try .init(mutation:reservation.mutation,state:.canonicalCommitted,receiptSHA256:receiptSHA256);}}
    func pendingCleanups()async throws->[TemporalEvidenceRetentionCleanupReservationV1]{try load().sorted{$0.mutation.mutationID.rawValue.uuidString<$1.mutation.mutationID.rawValue.uuidString}}
    func finishCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws{try mutate { values in guard let index=values.firstIndex(where:{$0.mutation.mutationID==reservation.mutation.mutationID})else{return};guard values[index].mutation==reservation.mutation else{throw TemporalEvidenceContractFailureV1.invalidTransition};values.remove(at:index);}}
    private func load()throws->[TemporalEvidenceRetentionCleanupReservationV1]{guard let data=try storage.read(manifestName)else{return[]};guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};let values=try JSONDecoder().decode([TemporalEvidenceRetentionCleanupReservationV1].self,from:data);try values.forEach{try $0.validate()};guard values.allSatisfy({$0.mutation.workspaceID==workspaceID}),Set(values.map{$0.mutation.mutationID}).count==values.count else{throw TemporalEvidenceContractFailureV1.digestMismatch};return values}
    private func mutate(_ body: (inout [TemporalEvidenceRetentionCleanupReservationV1]) throws -> Void) throws {
        try storage.mutate(manifestName) { data in
            var values = try data.map { try JSONDecoder().decode([TemporalEvidenceRetentionCleanupReservationV1].self, from: $0) } ?? []
            try body(&values)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(values.sorted { $0.mutation.mutationID.rawValue.uuidString < $1.mutation.mutationID.rawValue.uuidString })
        }
    }
}

/// Bounded operational manifest under the existing generation root. It is
/// recovery metadata only: canonical clip/anchor truth remains in the generic
/// workspace writer and immutable bytes remain in the existing content store.
/// Concrete operational preparation/read surface. It owns the same private M1
/// storage and codec as full recovery, but grants no content verification,
/// removal, canonical admission or normalization publication authority.
/// A per-instance admission lock rejects overlap/reentry before the existing
/// cross-process storage flock is entered. Contention throws interruption.
final class TemporalEvidencePromotionJournalV1: Sendable {
    fileprivate typealias Record = TemporalEvidencePromotionRecoveryFileAdapterV1.Record
    private let admission = NSLock()
    private let workspaceID: WorkspaceID
    private let storage: TemporalEvidenceOperationalJournalStorageV1
    private let manifestName: String

    init(generationRootURL: URL, workspaceID: WorkspaceID,
         fileManager: FileManager = .default,
         readBoundary: TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil,
         publicationBoundary: TemporalEvidenceOperationalPublicationBoundaryHookV2? = nil,
         createsAncestors: Bool = true) throws {
        guard generationRootURL.isFileURL else { throw TemporalEvidenceContractFailureV1.invalidValue }
        _ = fileManager
        self.workspaceID = workspaceID
        storage = try .init(generationRootURL: generationRootURL,
            readBoundary: readBoundary, publicationBoundary: publicationBoundary,
            createsAncestors: createsAncestors)
        manifestName = workspaceID.rawValue.uuidString.lowercased() + ".json"
    }
    func prepare(_ reservation:TemporalEvidencePromotionReservationV1)throws{guard reservation.workspaceID==workspaceID,reservation.state == .prepared else{throw TemporalEvidenceContractFailureV1.invalidTransition};try mutate { records in if let old=records.first(where:{$0.mutationID==reservation.mutationID.rawValue}){guard old==Record(reservation)else{throw TemporalEvidenceContractFailureV1.invalidTransition};return};records.append(Record(reservation));}}
    func reservation(workspaceID:WorkspaceID,mutationID:MutationIDV1)throws->TemporalEvidencePromotionReservationV1?{guard workspaceID==self.workspaceID else{throw TemporalEvidenceContractFailureV1.wrongWorkspace};return try load().first(where:{$0.mutationID==mutationID.rawValue})?.value()}
    func recoverPending()throws->[TemporalEvidencePromotionReservationV1]{try load().filter{$0.state != .finished}.sorted{$0.mutationID.uuidString<$1.mutationID.uuidString}.map{try $0.value()}}
    fileprivate func load()throws->[Record]{try withJournalAccess { guard let data=try storage.read(manifestName)else{return[]};guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};let values=try JSONDecoder().decode([Record].self,from:data);try values.forEach{_ = try $0.value()};guard Set(values.map{$0.mutationID}).count==values.count,values.allSatisfy({$0.workspaceID==workspaceID.rawValue})else{throw TemporalEvidenceContractFailureV1.digestMismatch};return values }}
    fileprivate func validateStoredReservation(_ reservation:TemporalEvidencePromotionReservationV1)throws->Record{guard reservation.workspaceID==workspaceID,let current=try load().first(where:{$0.mutationID==reservation.mutationID.rawValue}),current == Record(reservation,state:current.state)else{throw TemporalEvidenceContractFailureV1.interruption};return current}
    fileprivate func mutate(_ body: (inout [Record]) throws -> Void) throws {
        try withJournalAccess {
        try storage.mutate(manifestName) { data in
            var records = try data.map { try JSONDecoder().decode([Record].self, from: $0) } ?? []
            try body(&records)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(records.sorted { $0.mutationID.uuidString < $1.mutationID.uuidString })
        }
        }
    }

    /// flock on one descriptor does not serialize callers sharing that FD.
    /// Refuse contention, including synchronous hook reentry, before storage
    /// access. Never wait for a hook that may itself be waiting for this call.
    private func withJournalAccess<Value>(_ body: () throws -> Value) throws -> Value {
        guard admission.try() else { throw TemporalEvidenceContractFailureV1.interruption }
        defer { admission.unlock() }
        return try body()
    }
}

actor TemporalEvidencePromotionRecoveryFileAdapterV1:TemporalEvidencePromotionRecoveryPortV1{
    fileprivate struct Record:Codable,Equatable{let workspaceID:UUID;let mutationID:UUID;let contentID:String;let contentSHA256:String;let requestLeaseID:UUID;let operationID:UUID;let purpose:CapabilityScratchPurposeV1;let requestedByteCount:UInt64;let createdAt:Date;let expiresAt:Date;let leaseID:UUID;let relativeDirectory:String;let state:TemporalEvidencePromotionRecoveryStateV1
        init(_ value:TemporalEvidencePromotionReservationV1,state:TemporalEvidencePromotionRecoveryStateV1?=nil){workspaceID=value.workspaceID.rawValue;mutationID=value.mutationID.rawValue;contentID=value.contentID;contentSHA256=value.contentSHA256;requestLeaseID=value.binding.request.leaseID;operationID=value.binding.request.operationID;purpose=value.binding.request.purpose;requestedByteCount=value.binding.request.requestedByteCount;createdAt=value.binding.request.createdAt;expiresAt=value.binding.request.expiresAt;leaseID=value.binding.lease.leaseID;relativeDirectory=value.binding.lease.relativeDirectory;self.state=state ?? value.state}
        func value()throws->TemporalEvidencePromotionReservationV1{let workspace=try WorkspaceID(rawValue:workspaceID),mutation=try MutationIDV1(rawValue:mutationID),request=try CapabilityScratchLeaseRequestV1(leaseID:requestLeaseID,operationID:operationID,purpose:purpose,requestedByteCount:requestedByteCount,createdAt:createdAt,expiresAt:expiresAt),lease=CapabilityScratchLeaseV1(leaseID:leaseID,purpose:purpose,relativeDirectory:relativeDirectory),binding=try TemporalEvidenceScratchBindingV1(request:request,lease:lease,mutationID:mutation,contentID:contentID,contentSHA256:contentSHA256);return try .init(workspaceID:workspace,mutationID:mutation,contentID:contentID,contentSHA256:contentSHA256,binding:binding,state:state)}
    }
    private let workspaceID:WorkspaceID
    private let journal: TemporalEvidencePromotionJournalV1
    private let verify:TemporalEvidencePromotedContentVerificationV1
    private let delete:TemporalEvidencePromotedContentRemovalV1
    private var cleanupFences:Set<UUID> = []
    init(generationRootURL:URL,workspaceID:WorkspaceID,fileManager:FileManager = .default,readBoundary:TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil,publicationBoundary:TemporalEvidenceOperationalPublicationBoundaryHookV2? = nil,createsAncestors:Bool = true,verify:@escaping TemporalEvidencePromotedContentVerificationV1,remove:@escaping TemporalEvidencePromotedContentRemovalV1)throws{
        self.workspaceID = workspaceID
        journal = try TemporalEvidencePromotionJournalV1(generationRootURL: generationRootURL,
            workspaceID: workspaceID, fileManager: fileManager, readBoundary: readBoundary,
            publicationBoundary: publicationBoundary, createsAncestors: createsAncestors)
        self.verify = verify; delete = remove
    }
    func prepare(_ reservation:TemporalEvidencePromotionReservationV1)async throws{try journal.prepare(reservation)}
    func transition(_ reservation:TemporalEvidencePromotionReservationV1,to state:TemporalEvidencePromotionRecoveryStateV1)async throws{guard !cleanupFences.contains(reservation.mutationID.rawValue) else{throw TemporalEvidenceContractFailureV1.interruption};try mutate { records in guard let index=records.firstIndex(where:{$0.workspaceID==reservation.workspaceID.rawValue&&$0.mutationID==reservation.mutationID.rawValue})else{throw TemporalEvidenceContractFailureV1.interruption};let current=records[index],same=Record(reservation,state:current.state);guard current==same,Self.permits(current.state,state)else{throw TemporalEvidenceContractFailureV1.invalidTransition};records[index]=Record(reservation,state:state);}}
    func reservation(workspaceID:WorkspaceID,mutationID:MutationIDV1)async throws->TemporalEvidencePromotionReservationV1?{try journal.reservation(workspaceID:workspaceID,mutationID:mutationID)}
    func recoverPending()async throws->[TemporalEvidencePromotionReservationV1]{try journal.recoverPending()}
    func promotedContentExists(_ reservation:TemporalEvidencePromotionReservationV1)async throws->Bool{let before=try validateStoredReservation(reservation);let exists=try await verify(reservation.workspaceID,reservation.contentID,reservation.contentSHA256);guard try validateStoredReservation(reservation) == before else{throw TemporalEvidenceContractFailureV1.interruption};return exists}
    func adoptCommittedContent(_ reservation:TemporalEvidencePromotionReservationV1,receiptSHA256:String)async throws{let before=try validateStoredReservation(reservation);guard MutationEnvelopeV1.isSHA256(receiptSHA256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};let exists=try await verify(reservation.workspaceID,reservation.contentID,reservation.contentSHA256);guard try validateStoredReservation(reservation) == before else{throw TemporalEvidenceContractFailureV1.interruption};guard exists else{throw TemporalEvidenceContractFailureV1.digestMismatch}}
    func removeUncommittedContent(_ reservation:TemporalEvidencePromotionReservationV1)async throws{let current=try validateStoredReservation(reservation);guard current.state != .canonicalCommitted,current.state != .finished,!cleanupFences.contains(reservation.mutationID.rawValue)else{throw TemporalEvidenceContractFailureV1.interruption};if current.state != .quarantined{try mutate { records in guard let index=records.firstIndex(where:{$0.mutationID==reservation.mutationID.rawValue}),records[index] == current else{throw TemporalEvidenceContractFailureV1.interruption};records[index]=Record(reservation,state:.quarantined);}};cleanupFences.insert(reservation.mutationID.rawValue);defer{cleanupFences.remove(reservation.mutationID.rawValue)};try await delete(reservation.workspaceID,reservation.contentID,reservation.contentSHA256);let reread=try validateStoredReservation(reservation);guard reread.state == .quarantined else{throw TemporalEvidenceContractFailureV1.interruption}}
    func remove(_ reservation:TemporalEvidencePromotionReservationV1)async throws{try mutate { records in guard let index=records.firstIndex(where:{$0.mutationID==reservation.mutationID.rawValue})else{return};guard reservation.workspaceID == workspaceID, records[index] == Record(reservation,state:.finished) else{throw TemporalEvidenceContractFailureV1.invalidTransition};records.remove(at:index);}}
    fileprivate static func permits(_ from:TemporalEvidencePromotionRecoveryStateV1,_ to:TemporalEvidencePromotionRecoveryStateV1)->Bool{if from==to{return true};switch(from,to){case(.prepared,.originalPromoted),(.prepared,.quarantined),(.prepared,.finished),(.originalPromoted,.canonicalCommitted),(.originalPromoted,.quarantined),(.originalPromoted,.finished),(.canonicalCommitted,.finished),(.quarantined,.finished):return true;default:return false}}
    private func validateStoredReservation(_ reservation:TemporalEvidencePromotionReservationV1)throws->Record {
        try journal.validateStoredReservation(reservation)
    }
    private func mutate(_ body: (inout [Record]) throws -> Void) throws {
        try journal.mutate(body)
    }
}

/// This port removes an exact backing lease without manufacturing a receipt.
/// Callers still owe canonical history and generation-authority admission.
struct TemporalEvidenceScratchRecoveryAdapterV1: TemporalEvidenceScratchRecoveryV1 {
    private let scratch: any ScratchDataLeasePortV1
    init(scratch: any ScratchDataLeasePortV1) { self.scratch = scratch }

    func removeRecoveredScratch(binding: TemporalEvidenceScratchBindingV1) async throws {
        let request = binding.request, lease = binding.lease
        guard request.purpose == .capture, lease.purpose == .capture,
              request.leaseID == lease.leaseID,
              request.operationID == binding.mutationID.rawValue,
              lease.relativeDirectory == "capture-" + lease.leaseID.uuidString.lowercased() else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        _ = try TemporalEvidenceScratchBindingV1(
            request: request, lease: lease, mutationID: binding.mutationID,
            contentID: binding.contentID, contentSHA256: binding.contentSHA256
        )
        let backingRequest = try ScratchDataLeaseRequestV1(
            leaseID: request.leaseID, purpose: .capture, owner: .capture,
            ownerOperationID: request.operationID, requestedByteCount: request.requestedByteCount,
            createdAt: request.createdAt, expiresAt: request.expiresAt,
            protection: .complete, backupPolicy: .excluded
        )
        let backing = try ScratchDataLeaseV1(request: backingRequest, relativeDirectory: lease.relativeDirectory)
        // The store does not persist this terminal enum. No disposition/receipt
        // is inferred from physical absence, including a second cold cleanup.
        try await scratch.releaseScratchLease(backing, terminal: .recoveredExpired)
    }
}

enum TemporalEvidenceOperationalPublicationBoundaryV2: String, CaseIterable, Sendable {
    case reservedDirectory, protectedDirectory, openedPayload, protectedPayload
    case partialPayload, durablePayload, beforePublication, published, durablePublication
    case removedDisplacedPayload, removedReservation
}
typealias TemporalEvidenceOperationalPublicationBoundaryHookV2 =
    @Sendable (TemporalEvidenceOperationalPublicationBoundaryV2) throws -> Void

struct TemporalEvidenceOperationalPublicationRecoverySummaryV2: Equatable, Sendable {
    let removedPublicationCount: Int
    let retainedEmptyCreation: Bool
}

/// Standalone private-storage recovery only. Not a ready-to-Erase token.
/// Actual current/retained generation and canonical ownership composition is
/// mandatory at the later application integration boundary.
enum TemporalEvidenceOperationalJournalRecoveryV2 {
    static func recoverExistingPublications(generationRootURL: URL) throws
        -> TemporalEvidenceOperationalPublicationRecoverySummaryV2 {
        let storage = try TemporalEvidenceOperationalJournalStorageV1(
            generationRootURL: generationRootURL, createsAncestors: false
        )
        return try storage.recover()
    }
}

private struct TemporalJournalKeyV2: Equatable {
    let workspace: UUID
    let retention: Bool
    var name: String { workspace.uuidString.lowercased() + (retention ? "-retention-cleanup.json" : ".json") }
    init(name: String) throws {
        let retention = name.hasSuffix("-retention-cleanup.json")
        let suffix = retention ? "-retention-cleanup.json" : ".json"
        guard name.hasSuffix(suffix), let id = UUID(uuidString: String(name.dropLast(suffix.count))),
              id != TemporalEvidenceValidationV1.zeroUUID else { throw TemporalEvidenceContractFailureV1.interruption }
        workspace = id; self.retention = retention
        guard self.name == name else { throw TemporalEvidenceContractFailureV1.interruption }
    }
    init(workspace: UUID, retention: Bool) { self.workspace = workspace; self.retention = retention }
}

/// Full typed manifests, not a generic arbitrary-bytes publication API.
private enum TemporalJournalCodecV2 {
    typealias Record = TemporalEvidencePromotionRecoveryFileAdapterV1.Record
    static func promotion(_ data: Data, key: TemporalJournalKeyV2) throws -> [Record] {
        let values = try JSONDecoder().decode([Record].self, from: data)
        try values.forEach { _ = try $0.value() }
        guard values.allSatisfy({ $0.workspaceID == key.workspace }),
              Set(values.map(\.mutationID)).count == values.count else { throw TemporalEvidenceContractFailureV1.digestMismatch }
        return values
    }
    static func retention(_ data: Data, key: TemporalJournalKeyV2) throws -> [TemporalEvidenceRetentionCleanupReservationV1] {
        let values = try JSONDecoder().decode([TemporalEvidenceRetentionCleanupReservationV1].self, from: data)
        try values.forEach { try $0.validate() }
        guard values.allSatisfy({ $0.mutation.workspaceID.rawValue == key.workspace }),
              Set(values.map { $0.mutation.mutationID }).count == values.count else { throw TemporalEvidenceContractFailureV1.digestMismatch }
        return values
    }
    static func validate(_ data: Data, key: TemporalJournalKeyV2, canonical: Bool = false) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded: Data
        if key.retention {
            encoded = try encoder.encode(retention(data, key: key).sorted { $0.mutation.mutationID.rawValue.uuidString < $1.mutation.mutationID.rawValue.uuidString })
        } else {
            encoded = try encoder.encode(promotion(data, key: key).sorted { $0.mutationID.uuidString < $1.mutationID.uuidString })
        }
        guard !canonical || encoded == data else { throw TemporalEvidenceContractFailureV1.digestMismatch }
    }
    static func equalValues(_ first: Data, _ second: Data, key: TemporalJournalKeyV2) throws -> Bool {
        if key.retention {
            return try retention(first, key: key).sorted { $0.mutation.mutationID.rawValue.uuidString < $1.mutation.mutationID.rawValue.uuidString }
                == retention(second, key: key).sorted { $0.mutation.mutationID.rawValue.uuidString < $1.mutation.mutationID.rawValue.uuidString }
        }
        return try promotion(first, key: key).sorted { $0.mutationID.uuidString < $1.mutationID.uuidString }
            == promotion(second, key: key).sorted { $0.mutationID.uuidString < $1.mutationID.uuidString }
    }
    static func transition(from predecessor: Data?, to successor: Data, key: TemporalJournalKeyV2) throws {
        try validate(successor, key: key, canonical: true)
        let empty = Data("[]".utf8)
        if key.retention {
            let old = try retention(predecessor ?? empty, key: key), new = try retention(successor, key: key)
            let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.mutation.mutationID, $0) })
            let newMap = Dictionary(uniqueKeysWithValues: new.map { ($0.mutation.mutationID, $0) })
            let changed = Set(oldMap.keys).union(newMap.keys).filter { oldMap[$0] != newMap[$0] }
            guard changed.count == 1, let id = changed.first else { throw TemporalEvidenceContractFailureV1.invalidTransition }
            switch (oldMap[id], newMap[id]) {
            case (nil, let next?): guard next.state == .prepared else { throw TemporalEvidenceContractFailureV1.invalidTransition }
            case (let prior?, let next?):
                guard prior.mutation == next.mutation, prior.state == .prepared,
                      next.state == .canonicalCommitted else { throw TemporalEvidenceContractFailureV1.invalidTransition }
            case (.some(_), nil): break // Existing prepared cancellation/committed finish semantics.
            default: throw TemporalEvidenceContractFailureV1.invalidTransition
            }
        } else {
            let old = try promotion(predecessor ?? empty, key: key), new = try promotion(successor, key: key)
            let oldMap = Dictionary(uniqueKeysWithValues: old.map { ($0.mutationID, $0) })
            let newMap = Dictionary(uniqueKeysWithValues: new.map { ($0.mutationID, $0) })
            let changed = Set(oldMap.keys).union(newMap.keys).filter { oldMap[$0] != newMap[$0] }
            guard changed.count == 1, let id = changed.first else { throw TemporalEvidenceContractFailureV1.invalidTransition }
            switch (oldMap[id], newMap[id]) {
            case (nil, let next?): guard next.state == .prepared else { throw TemporalEvidenceContractFailureV1.invalidTransition }
            case (let prior?, let next?):
                guard prior == Record(try next.value(), state: prior.state),
                      TemporalEvidencePromotionRecoveryFileAdapterV1.permits(prior.state, next.state) else { throw TemporalEvidenceContractFailureV1.invalidTransition }
            case (let prior?, nil): guard prior.state == .finished else { throw TemporalEvidenceContractFailureV1.invalidTransition }
            default: throw TemporalEvidenceContractFailureV1.invalidTransition
            }
        }
    }
}

/// Root-descriptor advisory ownership serializes all concrete instances, not
/// just an actor mailbox. This is deliberately distinct from generation G.
/// No await, canonical/content callback, or nested storage lock occurs here.
private final class TemporalEvidenceOperationalJournalStorageV1: @unchecked Sendable {
    private struct Identity: Equatable { let device: dev_t; let inode: ino_t }
    private struct Leaf: Equatable { let identity: Identity; let data: Data }
    private struct Slot: Equatable {
        let name: String
        let key: TemporalJournalKeyV2
        let predecessor: String
        let successor: String
        let length: Int
        init(name: String) throws {
            // UUID contains hyphens; fixed components before/after it are parsed
            // by byte positions, with a final canonical full-name comparison.
            let bytes = Array(name.utf8)
            guard bytes.count <= 181, name.hasPrefix(".tp2-"), bytes.count >= 48 else { throw TemporalEvidenceContractFailureV1.interruption }
            let kind = String(decoding: bytes[5..<6], as: UTF8.self)
            guard bytes[6] == 45, bytes[43] == 45,
                  let workspace = UUID(uuidString: String(decoding: bytes[7..<43], as: UTF8.self)),
                  workspace != TemporalEvidenceValidationV1.zeroUUID,
                  kind == "p" || kind == "r" else { throw TemporalEvidenceContractFailureV1.interruption }
            let tail = String(decoding: bytes[44...], as: UTF8.self).split(separator: "-", omittingEmptySubsequences: false)
            guard tail.count == 3, let count = Int(tail[2]), (1...Self.maximumBytes).contains(count) else { throw TemporalEvidenceContractFailureV1.interruption }
            key = .init(workspace: workspace, retention: kind == "r")
            predecessor = String(tail[0]); successor = String(tail[1]); length = count
            guard (predecessor == "n" || Self.digestSpelling(predecessor)), Self.digestSpelling(successor),
                  name == Self.spelling(key: key, predecessor: predecessor, successor: successor, length: length) else { throw TemporalEvidenceContractFailureV1.interruption }
            self.name = name
        }
        static let maximumBytes = 1_048_576
        static func digestSpelling(_ value: String) -> Bool { value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        static func spelling(key: TemporalJournalKeyV2, predecessor: String, successor: String, length: Int) -> String {
            ".tp2-\(key.retention ? "r" : "p")-\(key.workspace.uuidString.lowercased())-\(predecessor)-\(successor)-\(length)"
        }
    }
    private struct SlotProof: Equatable { let slot: Slot; let identity: Identity; let payload: Leaf? }
    private struct Census: Equatable { let manifests: [String: Leaf]; let transaction: SlotProof? }
    private let rootURL: URL
    private let root: Int32
    private let rootIdentity: Identity
    private let components = ["operational", "temporal-evidence-promotion-v1"]
    private let readBoundary: TemporalEvidenceOperationalJournalReadBoundaryHookV1?
    private let publicationBoundary: TemporalEvidenceOperationalPublicationBoundaryHookV2?
    private var pinnedDirectories: [Identity]?
    private var retainedEmptyCreation = false
    // Set only on a fresh no-create instance by the fixed observation entry.
    // The object never escapes that entry; producer/recovery instances retain
    // the incumbent policy behavior.
    private var normalizationObservationOnly = false
    private var normalizationPolicyObservations: [String: TemporalPolicyObservationV1] = [:]

    private func inspectPolicy(_ kind: OwnedFileKindV1, at url: URL) throws {
        if normalizationObservationOnly {
            let observed = try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url)
            if let prior = normalizationPolicyObservations[url.path], prior != observed {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            normalizationPolicyObservations[url.path] = observed
        } else { try ProtectedFilePolicyV1.verify(kind, at: url) }
    }
    private static let maxManifests = 256
    private static let maxFileBytes = 1_048_576
    private static let maxSettledBytes = 15 * 1_048_576
    private static let maxTotalBytes = 16 * 1_048_576

    init(generationRootURL: URL, readBoundary: TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil,
         publicationBoundary: TemporalEvidenceOperationalPublicationBoundaryHookV2? = nil,
         createsAncestors: Bool = true) throws {
        guard generationRootURL.isFileURL else { throw TemporalEvidenceContractFailureV1.invalidValue }
        rootURL = generationRootURL.standardizedFileURL
        self.readBoundary = readBoundary; self.publicationBoundary = publicationBoundary
        let descriptor = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.invalidValue }
        do { rootIdentity = try Self.directoryIdentity(descriptor) }
        catch { _ = Darwin.close(descriptor); throw error }
        root = descriptor
        if createsAncestors { try locked { _ = try withDirectory(create: true) { _, _ in () } } }
    }
    deinit { _ = Darwin.close(root) }

    func read(_ name: String) throws -> Data? {
        _ = try TemporalJournalKeyV2(name: name)
        return try locked {
            try withDirectory(create: false) { directory, expected in
                let census = try inspect(directory, expected: expected)
                guard census.transaction == nil else { throw TemporalEvidenceContractFailureV1.interruption }
                return census.manifests[name]?.data
            } ?? nil
        }
    }

    func mutate(_ name: String, _ transform: (Data?) throws -> Data) throws {
        let key = try TemporalJournalKeyV2(name: name)
        try locked {
            guard let completed = try withDirectory(create: false, body: { directory, expected in
                let before = try inspect(directory, expected: expected)
                guard before.transaction == nil else { throw TemporalEvidenceContractFailureV1.interruption }
                let old = before.manifests[name]?.data
                let new = try transform(old)
                guard new.count <= Self.maxFileBytes else { throw TemporalEvidenceContractFailureV1.limitExceeded }
                if new == old || (old == nil && new == Data("[]".utf8)) { return true }
                if let old, try TemporalJournalCodecV2.equalValues(old, new, key: key) { return true }
                try TemporalJournalCodecV2.transition(from: old, to: new, key: key)
                let settled = before.manifests.values.reduce(0) { $0 + $1.data.count }
                guard settled - (old?.count ?? 0) + new.count <= Self.maxSettledBytes,
                      settled + new.count <= Self.maxTotalBytes,
                      before.manifests.count + (old == nil ? 1 : 0) <= Self.maxManifests else { throw TemporalEvidenceContractFailureV1.limitExceeded }
                try publish(new, key: key, before: before, directory: directory, expected: expected)
                return true
            }) else { throw TemporalEvidenceContractFailureV1.interruption }
            _ = completed
        }
    }

    func recover() throws -> TemporalEvidenceOperationalPublicationRecoverySummaryV2 {
        try locked {
            retainedEmptyCreation = false
            let recovered: Int? = try withDirectory(create: false) { directory, expected in
                let before = try inspect(directory, expected: expected)
                guard let proof = before.transaction else { return 0 }
                try validateRecovery(proof, census: before, directory: directory)
                // Re-read complete bytes, names, links and policies before any unlink.
                guard try inspect(directory, expected: expected) == before else { throw TemporalEvidenceContractFailureV1.interruption }
                try removeSlot(proof, directory: directory, expected: expected, manifests: before.manifests)
                return 1
            }
            return .init(removedPublicationCount: recovered ?? 0, retainedEmptyCreation: retainedEmptyCreation)
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try reproveRoot()
        guard flock(root, LOCK_EX | LOCK_NB) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        defer { _ = flock(root, LOCK_UN) }
        try reproveRoot()
        let result = try body()
        try reproveRoot()
        return result
    }

    private func withDirectory<T>(create: Bool, permitsUnprotectedEmptyCreation: Bool = true, body: (Int32, [Identity]) throws -> T) throws -> T? {
        guard !normalizationObservationOnly || !create else { throw TemporalEvidenceContractFailureV1.interruption }
        try reproveRoot()
        var parent = root, path = rootURL
        var opened: [Int32] = [], expected = [rootIdentity]
        defer { opened.reversed().forEach { _ = Darwin.close($0) } }
        for component in components {
            path.appendPathComponent(component, isDirectory: true)
            var next = Darwin.openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            var created = false
            if next < 0 && errno == ENOENT {
                if !create {
                    guard pinnedDirectories == nil else { throw TemporalEvidenceContractFailureV1.interruption }
                    return nil
                }
                guard Darwin.mkdirat(parent, component, 0o700) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
                created = true
                next = Darwin.openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
            opened.append(next)
            let identity = try Self.directoryIdentity(next)
            expected.append(identity)
            let parentFD = parent, directoryFD = next, directoryURL = path
            let chain = expected
            let proof = {
                try self.reprovePrefix(chain)
                guard try Self.directoryIdentity(directoryFD) == identity,
                      try Self.directoryIdentity(parent: parentFD, name: component) == identity else { throw TemporalEvidenceContractFailureV1.interruption }
            }
            try proof()
            let empty = try Self.names(next, limit: 1, stopAtLimit: true).isEmpty
            if create && (created || empty) {
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directoryURL, authorityCheck: proof)
                guard Darwin.fsync(next) == 0, Darwin.fsync(parent) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
            } else {
                do { try inspectPolicy(.stagingDirectory, at: directoryURL) }
                catch ProtectedFilePolicyError.resourceValueMismatch where permitsUnprotectedEmptyCreation && empty && !create && pinnedDirectories == nil {
                    retainedEmptyCreation = true
                    return nil
                }
            }
            try proof()
            parent = next
        }
        if let pinnedDirectories { guard expected == pinnedDirectories else { throw TemporalEvidenceContractFailureV1.interruption } }
        else { pinnedDirectories = expected }
        let result = try body(parent, expected)
        try reprove(parent: parent, expected: expected)
        return result
    }

    private func inspect(_ directory: Int32, expected: [Identity]) throws -> Census {
        try reprove(parent: directory, expected: expected)
        let names = try Self.names(directory, limit: Self.maxManifests + 1)
        var manifestNames: [String] = [], slot: Slot?
        var total = 0
        // Bound counts and stat sizes BEFORE reading/decoding/allocating buffers.
        for name in names {
            if name.hasPrefix(".tp2-") {
                guard slot == nil else { throw TemporalEvidenceContractFailureV1.interruption }
                slot = try Slot(name: name)
                _ = try Self.directoryIdentity(parent: directory, name: name)
            } else {
                _ = try TemporalJournalKeyV2(name: name)
                guard manifestNames.count < Self.maxManifests else { throw TemporalEvidenceContractFailureV1.limitExceeded }
                let info = try Self.regularStatus(parent: directory, name: name)
                total = try Self.addBytes(total, info.st_size, limit: Self.maxSettledBytes)
                manifestNames.append(name)
            }
        }
        var payloadInfo: stat?
        if let slot {
            let fd = try Self.openDirectory(parent: directory, name: slot.name)
            defer { _ = Darwin.close(fd) }
            let children = try Self.names(fd, limit: 1)
            guard children.isEmpty || children == ["payload"] else { throw TemporalEvidenceContractFailureV1.interruption }
            if !children.isEmpty {
                payloadInfo = try Self.regularStatus(parent: fd, name: "payload")
                total = try Self.addBytes(total, payloadInfo!.st_size, limit: Self.maxTotalBytes)
            }
        }
        var manifests: [String: Leaf] = [:]
        for name in manifestNames.sorted() {
            let key = try TemporalJournalKeyV2(name: name)
            let leaf = try readLeaf(parent: directory, name: name, url: journalURL.appendingPathComponent(name), kind: .journal)
            try TemporalJournalCodecV2.validate(leaf.data, key: key)
            manifests[name] = leaf
        }
        var transaction: SlotProof?
        if let slot {
            let fd = try Self.openDirectory(parent: directory, name: slot.name)
            defer { _ = Darwin.close(fd) }
            let identity = try Self.directoryIdentity(fd)
            let url = journalURL.appendingPathComponent(slot.name)
            let payload: Leaf?
            if payloadInfo != nil {
                try inspectPolicy(.stagingDirectory, at: url)
                payload = try readLeaf(parent: fd, name: "payload", url: url.appendingPathComponent("payload"), kind: .journalTemporary, permitsEmptyCreation: true)
            } else { payload = nil }
            guard try Self.directoryIdentity(parent: directory, name: slot.name) == identity,
                  try Self.names(fd, limit: 1) == (payload == nil ? [] : ["payload"]) else { throw TemporalEvidenceContractFailureV1.interruption }
            transaction = .init(slot: slot, identity: identity, payload: payload)
        }
        let observedTotal = manifests.values.reduce(0) { $0 + $1.data.count } + (transaction?.payload?.data.count ?? 0)
        guard observedTotal == total, try Self.names(directory, limit: Self.maxManifests + 1) == names else { throw TemporalEvidenceContractFailureV1.interruption }
        try reprove(parent: directory, expected: expected)
        return .init(manifests: manifests, transaction: transaction)
    }

    private func validateRecovery(_ proof: SlotProof, census: Census, directory: Int32) throws {
        let slot = proof.slot, current = census.manifests[slot.key.name]?.data
        let currentSHA = current.map(Self.digest) ?? "n"
        if currentSHA == slot.predecessor {
            let settled = census.manifests.values.reduce(0) { $0 + $1.data.count }
            guard settled + slot.length <= Self.maxTotalBytes else { throw TemporalEvidenceContractFailureV1.limitExceeded }
            if let payload = proof.payload?.data {
                guard payload.count <= slot.length else { throw TemporalEvidenceContractFailureV1.interruption }
                if payload.count == slot.length {
                    guard Self.digest(payload) == slot.successor else { throw TemporalEvidenceContractFailureV1.digestMismatch }
                    try TemporalJournalCodecV2.transition(from: current, to: payload, key: slot.key)
                }
            }
        } else if currentSHA == slot.successor, let current {
            guard current.count == slot.length else { throw TemporalEvidenceContractFailureV1.digestMismatch }
            try TemporalJournalCodecV2.validate(current, key: slot.key, canonical: true)
            if slot.predecessor == "n" { try TemporalJournalCodecV2.transition(from: nil, to: current, key: slot.key) }
            try inspectPolicy(.stagingDirectory, at: journalURL.appendingPathComponent(slot.name))
            if let payload = proof.payload?.data {
                guard slot.predecessor != "n", Self.digest(payload) == slot.predecessor else { throw TemporalEvidenceContractFailureV1.digestMismatch }
                try TemporalJournalCodecV2.transition(from: payload, to: current, key: slot.key)
            }
        } else { throw TemporalEvidenceContractFailureV1.interruption }
        guard try Self.directoryIdentity(parent: directory, name: slot.name) == proof.identity else { throw TemporalEvidenceContractFailureV1.interruption }
    }

    private func publish(_ data: Data, key: TemporalJournalKeyV2, before: Census, directory: Int32, expected: [Identity]) throws {
        guard try inspect(directory, expected: expected) == before else { throw TemporalEvidenceContractFailureV1.interruption }
        let old = before.manifests[key.name]
        let slot = try Slot(name: Slot.spelling(key: key, predecessor: old.map { Self.digest($0.data) } ?? "n", successor: Self.digest(data), length: data.count))
        guard Darwin.mkdirat(directory, slot.name, 0o700) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        let fd = try Self.openDirectory(parent: directory, name: slot.name)
        defer { _ = Darwin.close(fd) }
        let identity = try Self.directoryIdentity(fd), url = journalURL.appendingPathComponent(slot.name)
        let proveSlot = {
            try self.reprove(parent: directory, expected: expected)
            guard try Self.directoryIdentity(fd) == identity,
                  try Self.directoryIdentity(parent: directory, name: slot.name) == identity else { throw TemporalEvidenceContractFailureV1.interruption }
        }
        guard Darwin.fsync(directory) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        try publicationBoundary?(.reservedDirectory)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: url, authorityCheck: proveSlot)
        guard Darwin.fsync(fd) == 0, Darwin.fsync(directory) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        try publicationBoundary?(.protectedDirectory)
        try proveSlot()
        let payload = Darwin.openat(fd, "payload", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard payload >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        defer { _ = Darwin.close(payload) }
        let payloadIdentity = try Self.regularIdentity(payload)
        var written = 0
        let provePayload = {
            try proveSlot()
            var info = stat()
            guard Darwin.fstat(payload, &info) == 0, info.st_size == off_t(written),
                  try Self.regularIdentity(payload) == payloadIdentity,
                  try Self.regularIdentity(parent: fd, name: "payload") == payloadIdentity else { throw TemporalEvidenceContractFailureV1.interruption }
        }
        try publicationBoundary?(.openedPayload)
        try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: url.appendingPathComponent("payload"), authorityCheck: provePayload)
        guard Darwin.fsync(payload) == 0, Darwin.fsync(fd) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        try publicationBoundary?(.protectedPayload)
        try provePayload()
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw TemporalEvidenceContractFailureV1.invalidValue }
            while written < bytes.count {
                // Always expose a genuine nonempty partial state, even for [].
                let request = written == 0 ? 1 : min(64 * 1024, bytes.count - written)
                let count = Darwin.write(payload, base.advanced(by: written), request)
                if count > 0 {
                    written += count
                    if written == 1 { try publicationBoundary?(.partialPayload) }
                    try provePayload()
                } else if count < 0 && errno == EINTR { continue }
                else { throw TemporalEvidenceContractFailureV1.interruption }
            }
        }
        guard Darwin.fsync(payload) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        try provePayload()
        let prepared = try inspect(directory, expected: expected)
        guard prepared.manifests == before.manifests, let preparedSlot = prepared.transaction,
              preparedSlot.slot == slot, preparedSlot.identity == identity,
              preparedSlot.payload == Leaf(identity: payloadIdentity, data: data) else { throw TemporalEvidenceContractFailureV1.interruption }
        try validateRecovery(preparedSlot, census: prepared, directory: directory)
        try publicationBoundary?(.durablePayload)
        try publicationBoundary?(.beforePublication)
        guard try inspect(directory, expected: expected) == prepared else { throw TemporalEvidenceContractFailureV1.interruption }
        guard Darwin.renameatx_np(fd, "payload", directory, key.name, UInt32(old == nil ? RENAME_EXCL : RENAME_SWAP)) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        try publicationBoundary?(.published)
        guard Darwin.fsync(fd) == 0, Darwin.fsync(directory) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        try proveSlot()
        let published = try inspect(directory, expected: expected)
        var expectedManifests = before.manifests
        expectedManifests[key.name] = Leaf(identity: payloadIdentity, data: data)
        guard published.manifests == expectedManifests, let displaced = published.transaction,
              displaced.identity == identity, displaced.slot == slot, displaced.payload == old else { throw TemporalEvidenceContractFailureV1.interruption }
        try validateRecovery(displaced, census: published, directory: directory)
        try publicationBoundary?(.durablePublication)
        guard try inspect(directory, expected: expected) == published else { throw TemporalEvidenceContractFailureV1.interruption }
        try removeSlot(displaced, directory: directory, expected: expected, manifests: published.manifests)
    }

    private func removeSlot(_ proof: SlotProof, directory: Int32, expected: [Identity], manifests: [String: Leaf]) throws {
        try reprove(parent: directory, expected: expected)
        let fd = try Self.openDirectory(parent: directory, name: proof.slot.name)
        defer { _ = Darwin.close(fd) }
        guard try Self.directoryIdentity(fd) == proof.identity else { throw TemporalEvidenceContractFailureV1.interruption }
        if let payload = proof.payload {
            let observed = try readLeaf(parent: fd, name: "payload", url: journalURL.appendingPathComponent(proof.slot.name).appendingPathComponent("payload"), kind: .journalTemporary, permitsEmptyCreation: true)
            guard observed == payload, try Self.names(fd, limit: 1) == ["payload"],
                  try Self.directoryIdentity(parent: directory, name: proof.slot.name) == proof.identity else { throw TemporalEvidenceContractFailureV1.interruption }
            // The final payload read invokes an injected read boundary and
            // performs URL policy readback. Its held slot FD alone cannot prove
            // that the slot is still below the named root/ancestor chain.
            try reprove(parent: directory, expected: expected)
            let finalCensus = try inspect(directory, expected: expected)
            guard finalCensus.manifests == manifests, finalCensus.transaction == proof else {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            try validateRecovery(proof, census: finalCensus, directory: directory)
            try reprove(parent: directory, expected: expected)
            guard try Self.regularIdentity(parent: fd, name: "payload") == payload.identity,
                  try Self.directoryIdentity(parent: directory, name: proof.slot.name) == proof.identity else {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            guard Darwin.unlinkat(fd, "payload", 0) == 0, Darwin.fsync(fd) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        }
        try publicationBoundary?(.removedDisplacedPayload)
        let afterPayload = try inspect(directory, expected: expected)
        guard afterPayload.manifests == manifests,
              afterPayload.transaction == SlotProof(slot: proof.slot, identity: proof.identity, payload: nil) else {
            throw TemporalEvidenceContractFailureV1.interruption
        }
        try validateRecovery(afterPayload.transaction!, census: afterPayload, directory: directory)
        try reprove(parent: directory, expected: expected)
        guard try Self.directoryIdentity(parent: directory, name: proof.slot.name) == proof.identity,
              try Self.names(fd, limit: 1).isEmpty,
              Darwin.unlinkat(directory, proof.slot.name, AT_REMOVEDIR) == 0,
              Darwin.fsync(directory) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        try publicationBoundary?(.removedReservation)
        try reprove(parent: directory, expected: expected)
    }

    private var journalURL: URL { components.reduce(rootURL) { $0.appendingPathComponent($1, isDirectory: true) } }
    private func readLeaf(parent: Int32, name: String, url: URL, kind: OwnedFileKindV1, permitsEmptyCreation: Bool = false) throws -> Leaf {
        let observed = try Self.regularStatus(parent: parent, name: name)
        let identity = Identity(device: observed.st_dev, inode: observed.st_ino)
        try readBoundary?(.afterLeafStat)
        let fd = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        defer { _ = Darwin.close(fd) }
        guard try Self.regularIdentity(fd) == identity, try Self.regularIdentity(parent: parent, name: name) == identity else { throw TemporalEvidenceContractFailureV1.interruption }
        try readBoundary?(.afterOpen)
        var opened = stat()
        guard Darwin.fstat(fd, &opened) == 0, opened.st_size == observed.st_size,
              try Self.regularIdentity(fd) == identity, try Self.regularIdentity(parent: parent, name: name) == identity else {
            throw TemporalEvidenceContractFailureV1.interruption
        }
        if !permitsEmptyCreation || observed.st_size != 0 { try inspectPolicy(kind, at: url) }
        // Never read bytes through the zero-length pre-policy exception. A
        // concurrent growth is denied, not retroactively called a partial file.
        if observed.st_size == 0 {
            var empty = stat()
            guard Darwin.fstat(fd, &empty) == 0, empty.st_size == 0,
                  try Self.regularIdentity(fd) == identity, try Self.regularIdentity(parent: parent, name: name) == identity else {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            return .init(identity: identity, data: Data())
        }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                guard count <= Self.maxFileBytes - data.count else { throw TemporalEvidenceContractFailureV1.limitExceeded }
                data.append(contentsOf: buffer.prefix(count))
                try readBoundary?(.accumulatedRead(data.count))
            } else if count == 0 { break }
            else if errno != EINTR { throw TemporalEvidenceContractFailureV1.interruption }
        }
        var final = stat()
        guard Darwin.fstat(fd, &final) == 0, final.st_size == observed.st_size, final.st_size == off_t(data.count),
              try Self.regularIdentity(fd) == identity, try Self.regularIdentity(parent: parent, name: name) == identity else { throw TemporalEvidenceContractFailureV1.interruption }
        if !data.isEmpty || !permitsEmptyCreation { try inspectPolicy(kind, at: url) }
        return .init(identity: identity, data: data)
    }
    private static func digest(_ data: Data) -> String { KernelCanonicalHashV1.sha256(data).lowercased() }
    private static func addBytes(_ total: Int, _ size: off_t, limit: Int) throws -> Int {
        guard size >= 0, size <= maxFileBytes, total <= limit, size <= off_t(limit - total) else { throw TemporalEvidenceContractFailureV1.limitExceeded }
        return total + Int(size)
    }
    private static func names(_ descriptor: Int32, limit: Int, stopAtLimit: Bool = false) throws -> [String] {
        // Open a new description: dup would share directory position with the
        // long-lived owner, and could incorrectly turn a second census empty.
        let fresh = Darwin.openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fresh >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        guard let stream = Darwin.fdopendir(fresh) else { _ = Darwin.close(fresh); throw TemporalEvidenceContractFailureV1.interruption }
        defer { Darwin.closedir(stream) }
        var values: [String] = []
        while true {
            errno = 0
            guard let entry = Darwin.readdir(stream) else {
                guard errno == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard !name.isEmpty, name.utf8.count <= Int(NAME_MAX), values.count < limit else { throw TemporalEvidenceContractFailureV1.limitExceeded }
            values.append(name)
            if stopAtLimit && values.count == limit { return values }
        }
        return values.sorted()
    }
    private func reproveRoot() throws {
        guard try Self.directoryIdentity(root) == rootIdentity,
              try Self.directoryIdentity(at: rootURL) == rootIdentity else { throw TemporalEvidenceContractFailureV1.interruption }
    }
    private func reprovePrefix(_ expected: [Identity]) throws {
        try reproveRoot()
        var descriptor = root, descriptors: [Int32] = []
        defer { descriptors.reversed().forEach { _ = Darwin.close($0) } }
        for index in 1..<expected.count {
            let next = try Self.openDirectory(parent: descriptor, name: components[index - 1])
            descriptors.append(next)
            guard try Self.directoryIdentity(next) == expected[index] else { throw TemporalEvidenceContractFailureV1.interruption }
            descriptor = next
        }
    }
    private func reprove(parent: Int32, expected: [Identity]) throws {
        try reprovePrefix(expected)
        guard try Self.directoryIdentity(parent) == expected.last else { throw TemporalEvidenceContractFailureV1.interruption }
    }
    private static func openDirectory(parent: Int32, name: String) throws -> Int32 {
        let fd = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        return fd
    }
    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw TemporalEvidenceContractFailureV1.interruption }
        return .init(device: info.st_dev, inode: info.st_ino)
    }
    private static func directoryIdentity(at url: URL) throws -> Identity {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        defer { _ = Darwin.close(fd) }
        return try directoryIdentity(fd)
    }
    private static func directoryIdentity(parent: Int32, name: String) throws -> Identity {
        let fd = try openDirectory(parent: parent, name: name)
        defer { _ = Darwin.close(fd) }
        return try directoryIdentity(fd)
    }
    private static func regularStatus(parent: Int32, name: String) throws -> stat {
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size >= 0,
              info.st_size <= maxFileBytes else { throw TemporalEvidenceContractFailureV1.interruption }
        return info
    }
    private static func regularIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size >= 0, info.st_size <= maxFileBytes else { throw TemporalEvidenceContractFailureV1.interruption }
        return .init(device: info.st_dev, inode: info.st_ino)
    }
    private static func regularIdentity(parent: Int32, name: String) throws -> Identity {
        let info = try regularStatus(parent: parent, name: name)
        return .init(device: info.st_dev, inode: info.st_ino)
    }
}

/// C33 has no microphone/camera provider. This actor is only the bounded
/// scratch/content lifecycle bridge consumed by the later explicit-intent UI.
@MainActor final class TemporalEvidenceLifecycleAdapterV1 {
    let scratch:TemporalEvidenceScratchLifecycleAdapterV1
    let content:TemporalEvidenceExistingContentPromotionAdapterV1
    let coordinator:TemporalEvidenceCoordinatorV1
    init(writer:any TemporalEvidenceCanonicalWorkspaceWritingV1,scratchLeases:any CapabilityScratchLeasePortV1,contentWriter:any DraftImmutableContentWriterV1,admissionReader:TemporalEvidenceCanonicalAdmissionReaderV1,recovery:any TemporalEvidencePromotionRecoveryPortV1,cleanupRecovery:any TemporalEvidenceRetentionCleanupRecoveryPortV1,contentCleanup:any TemporalEvidenceRetentionContentCleaningV1){let producerOwner=StoreSessionCoordinator.temporalOwner(for:writer);let scratch=TemporalEvidenceScratchLifecycleAdapterV1(base:scratchLeases,producerOwner:producerOwner),content=TemporalEvidenceExistingContentPromotionAdapterV1(writer:contentWriter,producerOwner:producerOwner);self.scratch=scratch;self.content=content;coordinator=TemporalEvidenceCoordinatorV1(writer:writer,content:content,scratch:scratch,admission:TemporalEvidenceTrustedAdmissionAuthorityV1(reader:admissionReader),recovery:recovery,cleanupRecovery:cleanupRecovery,contentCleanup:contentCleanup)}
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

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Media_TemporalEvidenceLifecycleAdapterV1_swift {
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


/// Complete M1 observation, including FINISHED manifests and the registered
/// pending slot. This value is data only; it cannot authorize a publication.
struct TemporalOperationalJournalObservationV1: Sendable {
    struct Manifest: Sendable {
        let name: String
        let canonicalData: Data
        let promotions: [TemporalEvidencePromotionReservationV1]
        let retentions: [TemporalEvidenceRetentionCleanupReservationV1]
        fileprivate init(name: String, canonicalData: Data,
                         promotions: [TemporalEvidencePromotionReservationV1],
                         retentions: [TemporalEvidenceRetentionCleanupReservationV1]) {
            self.name = name; self.canonicalData = canonicalData
            self.promotions = promotions; self.retentions = retentions
        }
    }
    struct PendingPublication: Sendable {
        enum State: Sendable { case unpublishedPartial, unpublishedComplete, published }
        let directoryName: String
        let targetManifestName: String
        let predecessorSHA256: String?
        let successorSHA256: String
        let successorByteCount: Int
        let payloadData: Data?
        let state: State
        /// A complete payload is either the unpublished successor or the
        /// displaced predecessor. Neither is silently treated as the winner.
        let completePayload: Manifest?
        fileprivate init(directoryName: String, targetManifestName: String,
                         predecessorSHA256: String?, successorSHA256: String,
                         successorByteCount: Int, payloadData: Data?, state: State,
                         completePayload: Manifest?) {
            self.directoryName = directoryName; self.targetManifestName = targetManifestName
            self.predecessorSHA256 = predecessorSHA256; self.successorSHA256 = successorSHA256
            self.successorByteCount = successorByteCount; self.payloadData = payloadData
            self.state = state; self.completePayload = completePayload
        }
    }
    let generationRootURL: URL
    let namespaceExists: Bool
    let policyObservations: [String: TemporalPolicyObservationV1]
    let published: [Manifest]
    let pending: PendingPublication?
    fileprivate init(generationRootURL: URL, namespaceExists: Bool,
                     published: [Manifest], pending: PendingPublication?,
                     policyObservations: [String: TemporalPolicyObservationV1]) {
        self.generationRootURL = generationRootURL; self.namespaceExists = namespaceExists
        self.published = published; self.pending = pending
        self.policyObservations = policyObservations
    }

    /// Synchronous preparation, run off main and outside G/namespace locks.
    /// The caller already owns activity EX. No constructor creates ancestors,
    /// no policy is repaired and no M1 recovery method is called here.
    static func prepare(generationRootURL: URL) throws -> Self {
        let storage = try TemporalEvidenceOperationalJournalStorageV1(
            generationRootURL: generationRootURL, createsAncestors: false)
        return try storage.prepareNormalizationObservation()
    }
}

extension TemporalEvidenceOperationalJournalStorageV1 {
    fileprivate func prepareNormalizationObservation() throws -> TemporalOperationalJournalObservationV1 {
        guard !normalizationObservationOnly, pinnedDirectories == nil else {
            throw TemporalEvidenceContractFailureV1.interruption
        }
        normalizationObservationOnly = true
        // This fresh reader is never returned. Keep observation-only for its
        // remaining lifetime even if a read throws; no reset can enable writes.
        try reproveRoot()
        let observation = try withDirectory(create: false, permitsUnprotectedEmptyCreation: false) {
            directory, expected in
            let before = try inspect(directory, expected: expected)
            if let slot = before.transaction {
                try validateRecovery(slot, census: before, directory: directory)
            }
            func manifest(_ name: String, _ data: Data) throws -> TemporalOperationalJournalObservationV1.Manifest {
                let key = try TemporalJournalKeyV2(name: name)
                if key.retention {
                    return .init(name: name, canonicalData: data, promotions: [],
                        retentions: try TemporalJournalCodecV2.retention(data, key: key))
                }
                return .init(name: name, canonicalData: data,
                    promotions: try TemporalJournalCodecV2.promotion(data, key: key).map { try $0.value() },
                    retentions: [])
            }
            let published = try before.manifests.keys.sorted().map { name in
                try manifest(name, before.manifests[name]!.data)
            }
            let pending: TemporalOperationalJournalObservationV1.PendingPublication?
            if let proof = before.transaction {
                let slot = proof.slot
                let currentSHA = before.manifests[slot.key.name].map { Self.digest($0.data) } ?? "n"
                let state: TemporalOperationalJournalObservationV1.PendingPublication.State
                let complete: TemporalOperationalJournalObservationV1.Manifest?
                if currentSHA == slot.successor {
                    state = .published
                    complete = try proof.payload.map { try manifest(slot.key.name, $0.data) }
                } else if let payload = proof.payload, payload.data.count == slot.length {
                    state = .unpublishedComplete
                    complete = try manifest(slot.key.name, payload.data)
                } else {
                    state = .unpublishedPartial
                    complete = nil
                }
                pending = .init(directoryName: slot.name, targetManifestName: slot.key.name,
                    predecessorSHA256: slot.predecessor == "n" ? nil : slot.predecessor,
                    successorSHA256: slot.successor, successorByteCount: slot.length,
                    payloadData: proof.payload?.data, state: state, completePayload: complete)
            } else { pending = nil }
            // Complete second census prevents an observed partial family from
            // being returned as a settled snapshot. No effect follows here.
            guard try inspect(directory, expected: expected) == before else {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            return TemporalOperationalJournalObservationV1(generationRootURL: rootURL,
                namespaceExists: true, published: published, pending: pending,
                policyObservations: normalizationPolicyObservations)
        }
        try reproveRoot()
        return observation ?? .init(generationRootURL: rootURL, namespaceExists: false,
                                    published: [], pending: nil, policyObservations: normalizationPolicyObservations)
    }
}

extension TemporalOperationalJournalObservationV1 {
    /// Exact incumbent settled codecs, used only after the source owner retained
    /// the actual complete no-M1 namespace. These values still grant no access.
    static func decodeRetainedSettled(generationRootURL: URL, manifests: [String: Data],
        policyObservations: [String: TemporalPolicyObservationV1]) throws -> Self {
        guard manifests.count <= 256 else { throw TemporalEvidenceContractFailureV1.limitExceeded }
        var total = 0
        let published = try manifests.keys.sorted().map { name -> Manifest in
            let key = try TemporalJournalKeyV2(name: name)
            let data = manifests[name]!
            guard data.count <= 1_048_576, total <= 15 * 1_048_576 - data.count else {
                throw TemporalEvidenceContractFailureV1.limitExceeded
            }
            total += data.count
            if key.retention {
                return .init(name: name, canonicalData: data, promotions: [],
                    retentions: try TemporalJournalCodecV2.retention(data, key: key))
            }
            return .init(name: name, canonicalData: data,
                promotions: try TemporalJournalCodecV2.promotion(data, key: key).map { try $0.value() }, retentions: [])
        }
        return .init(generationRootURL: generationRootURL, namespaceExists: true,
            published: published, pending: nil, policyObservations: policyObservations)
    }
}

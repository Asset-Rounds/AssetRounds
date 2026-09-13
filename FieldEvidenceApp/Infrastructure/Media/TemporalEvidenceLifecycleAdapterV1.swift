import Darwin
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
    init(generationRootURL:URL,workspaceID:WorkspaceID,fileManager:FileManager = .default,readBoundary:TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil)throws{guard generationRootURL.isFileURL else{throw TemporalEvidenceContractFailureV1.invalidValue};_ = fileManager;self.workspaceID=workspaceID;storage=try .init(generationRootURL:generationRootURL,readBoundary:readBoundary);manifestName=workspaceID.rawValue.uuidString.lowercased()+"-retention-cleanup.json"}
    func prepareCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws{guard reservation.mutation.workspaceID==workspaceID,reservation.state == .prepared else{throw TemporalEvidenceContractFailureV1.invalidTransition};var values=try load();if let old=values.first(where:{$0.mutation.mutationID==reservation.mutation.mutationID}){guard old==reservation else{throw TemporalEvidenceContractFailureV1.invalidTransition};return};values.append(reservation);try save(values)}
    func markCleanupCommitted(_ reservation:TemporalEvidenceRetentionCleanupReservationV1,receiptSHA256:String)async throws{guard MutationEnvelopeV1.isSHA256(receiptSHA256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};var values=try load();guard let index=values.firstIndex(where:{$0.mutation.mutationID==reservation.mutation.mutationID}),values[index].mutation==reservation.mutation else{throw TemporalEvidenceContractFailureV1.interruption};if values[index].state == .canonicalCommitted{guard values[index].receiptSHA256==receiptSHA256 else{throw TemporalEvidenceContractFailureV1.digestMismatch};return};values[index]=try .init(mutation:reservation.mutation,state:.canonicalCommitted,receiptSHA256:receiptSHA256);try save(values)}
    func pendingCleanups()async throws->[TemporalEvidenceRetentionCleanupReservationV1]{try load().sorted{$0.mutation.mutationID.rawValue.uuidString<$1.mutation.mutationID.rawValue.uuidString}}
    func finishCleanup(_ reservation:TemporalEvidenceRetentionCleanupReservationV1)async throws{var values=try load();guard let index=values.firstIndex(where:{$0.mutation.mutationID==reservation.mutation.mutationID})else{return};guard values[index].mutation==reservation.mutation else{throw TemporalEvidenceContractFailureV1.invalidTransition};values.remove(at:index);try save(values)}
    private func load()throws->[TemporalEvidenceRetentionCleanupReservationV1]{guard let data=try storage.read(manifestName)else{return[]};guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};let values=try JSONDecoder().decode([TemporalEvidenceRetentionCleanupReservationV1].self,from:data);try values.forEach{try $0.validate()};guard values.allSatisfy({$0.mutation.workspaceID==workspaceID}),Set(values.map{$0.mutation.mutationID}).count==values.count else{throw TemporalEvidenceContractFailureV1.digestMismatch};return values}
    private func save(_ values:[TemporalEvidenceRetentionCleanupReservationV1])throws{let sorted=values.sorted{$0.mutation.mutationID.rawValue.uuidString<$1.mutation.mutationID.rawValue.uuidString};let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let data=try encoder.encode(sorted);guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};try storage.replace(data,named:manifestName)}
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
    private let storage:TemporalEvidenceOperationalJournalStorageV1
    private let manifestName:String
    private let verify:TemporalEvidencePromotedContentVerificationV1
    private let delete:TemporalEvidencePromotedContentRemovalV1
    private var cleanupFences:Set<UUID> = []
    init(generationRootURL:URL,workspaceID:WorkspaceID,fileManager:FileManager = .default,readBoundary:TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil,verify:@escaping TemporalEvidencePromotedContentVerificationV1,remove:@escaping TemporalEvidencePromotedContentRemovalV1)throws{guard generationRootURL.isFileURL else{throw TemporalEvidenceContractFailureV1.invalidValue};_ = fileManager;self.workspaceID=workspaceID;storage=try .init(generationRootURL:generationRootURL,readBoundary:readBoundary);manifestName=workspaceID.rawValue.uuidString.lowercased()+".json";self.verify=verify;delete=remove}
    func prepare(_ reservation:TemporalEvidencePromotionReservationV1)async throws{guard reservation.workspaceID==workspaceID,reservation.state == .prepared else{throw TemporalEvidenceContractFailureV1.invalidTransition};var records=try load();if let old=records.first(where:{$0.mutationID==reservation.mutationID.rawValue}){guard old==Record(reservation)else{throw TemporalEvidenceContractFailureV1.invalidTransition};return};records.append(Record(reservation));try save(records)}
    func transition(_ reservation:TemporalEvidencePromotionReservationV1,to state:TemporalEvidencePromotionRecoveryStateV1)async throws{guard !cleanupFences.contains(reservation.mutationID.rawValue) else{throw TemporalEvidenceContractFailureV1.interruption};var records=try load();guard let index=records.firstIndex(where:{$0.workspaceID==reservation.workspaceID.rawValue&&$0.mutationID==reservation.mutationID.rawValue})else{throw TemporalEvidenceContractFailureV1.interruption};let current=records[index],same=Record(reservation,state:current.state);guard current==same,Self.permits(current.state,state)else{throw TemporalEvidenceContractFailureV1.invalidTransition};records[index]=Record(reservation,state:state);try save(records)}
    func reservation(workspaceID:WorkspaceID,mutationID:MutationIDV1)async throws->TemporalEvidencePromotionReservationV1?{guard workspaceID==self.workspaceID else{throw TemporalEvidenceContractFailureV1.wrongWorkspace};return try load().first(where:{$0.mutationID==mutationID.rawValue})?.value()}
    func recoverPending()async throws->[TemporalEvidencePromotionReservationV1]{try load().filter{$0.state != .finished}.sorted{$0.mutationID.uuidString<$1.mutationID.uuidString}.map{try $0.value()}}
    func promotedContentExists(_ reservation:TemporalEvidencePromotionReservationV1)async throws->Bool{try validateStoredReservation(reservation);let exists=try await verify(reservation.workspaceID,reservation.contentID,reservation.contentSHA256);try validateStoredReservation(reservation);return exists}
    func adoptCommittedContent(_ reservation:TemporalEvidencePromotionReservationV1,receiptSHA256:String)async throws{try validateStoredReservation(reservation);guard MutationEnvelopeV1.isSHA256(receiptSHA256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};let exists=try await verify(reservation.workspaceID,reservation.contentID,reservation.contentSHA256);try validateStoredReservation(reservation);guard exists else{throw TemporalEvidenceContractFailureV1.digestMismatch}}
    func removeUncommittedContent(_ reservation:TemporalEvidencePromotionReservationV1)async throws{let current=try validateStoredReservation(reservation);guard current.state != .canonicalCommitted,current.state != .finished,!cleanupFences.contains(reservation.mutationID.rawValue)else{throw TemporalEvidenceContractFailureV1.interruption};if current.state != .quarantined{var records=try load();guard let index=records.firstIndex(where:{$0.mutationID==reservation.mutationID.rawValue}),records[index] == current else{throw TemporalEvidenceContractFailureV1.interruption};records[index]=Record(reservation,state:.quarantined);try save(records)};cleanupFences.insert(reservation.mutationID.rawValue);defer{cleanupFences.remove(reservation.mutationID.rawValue)};try await delete(reservation.workspaceID,reservation.contentID,reservation.contentSHA256);let reread=try validateStoredReservation(reservation);guard reread.state == .quarantined else{throw TemporalEvidenceContractFailureV1.interruption}}
    func remove(_ reservation:TemporalEvidencePromotionReservationV1)async throws{var records=try load();guard let index=records.firstIndex(where:{$0.mutationID==reservation.mutationID.rawValue})else{return};guard records[index].state == .finished else{throw TemporalEvidenceContractFailureV1.invalidTransition};records.remove(at:index);try save(records)}
    private static func permits(_ from:TemporalEvidencePromotionRecoveryStateV1,_ to:TemporalEvidencePromotionRecoveryStateV1)->Bool{if from==to{return true};switch(from,to){case(.prepared,.originalPromoted),(.prepared,.quarantined),(.prepared,.finished),(.originalPromoted,.canonicalCommitted),(.originalPromoted,.quarantined),(.originalPromoted,.finished),(.canonicalCommitted,.finished),(.quarantined,.finished):return true;default:return false}}
    private func load()throws->[Record]{guard let data=try storage.read(manifestName)else{return[]};guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};let values=try JSONDecoder().decode([Record].self,from:data);try values.forEach{_ = try $0.value()};guard Set(values.map{$0.mutationID}).count==values.count,values.allSatisfy({$0.workspaceID==workspaceID.rawValue})else{throw TemporalEvidenceContractFailureV1.digestMismatch};return values}
    private func validateStoredReservation(_ reservation:TemporalEvidencePromotionReservationV1)throws->Record{guard reservation.workspaceID==workspaceID,let current=try load().first(where:{$0.mutationID==reservation.mutationID.rawValue}),current == Record(reservation,state:current.state)else{throw TemporalEvidenceContractFailureV1.interruption};return current}
    private func save(_ records:[Record])throws{let sorted=records.sorted{$0.mutationID.uuidString<$1.mutationID.uuidString};let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];let data=try encoder.encode(sorted);guard data.count<=1_048_576 else{throw TemporalEvidenceContractFailureV1.limitExceeded};try storage.replace(data,named:manifestName)}
}

/// Pins the existing generation root and resolves the temporal operational
/// directory only below that descriptor.  URL paths remain an identity check,
/// never the authority used for a journal read or mutation.
private final class TemporalEvidenceOperationalJournalStorageV1: @unchecked Sendable {
    private struct Identity: Equatable { let device: dev_t; let inode: ino_t }
    private let rootURL: URL
    private let root: Int32
    private let rootIdentity: Identity
    private let components = ["operational", "temporal-evidence-promotion-v1"]
    private let readBoundary: TemporalEvidenceOperationalJournalReadBoundaryHookV1?
    private var pinnedDirectories: [Identity]?

    init(generationRootURL: URL, readBoundary: TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil) throws {
        rootURL = generationRootURL.standardizedFileURL
        self.readBoundary = readBoundary
        let descriptor = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.invalidValue }
        do { rootIdentity = try Self.directoryIdentity(descriptor) }
        catch { _ = Darwin.close(descriptor); throw TemporalEvidenceContractFailureV1.invalidValue }
        root = descriptor
        pinnedDirectories = nil
        do { try withJournalDirectory { _, _ in } }
        catch { throw error }
    }

    deinit { _ = Darwin.close(root) }

    func read(_ name: String) throws -> Data? {
        try validLeaf(name)
        return try withJournalDirectory { parent, expected in
            try self.reprove(parent: parent, expected: expected)
            var info = stat()
            if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == -1 {
                guard errno == ENOENT else { throw TemporalEvidenceContractFailureV1.interruption }
                try self.reprove(parent: parent, expected: expected)
                return nil
            }
            guard Self.isRegular(info), info.st_nlink == 1, info.st_size >= 0,
                  info.st_size <= 1_048_576 else { throw TemporalEvidenceContractFailureV1.interruption }
            let observed = Identity(device: info.st_dev, inode: info.st_ino)
            try self.readBoundary?(.afterLeafStat)
            let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
            guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
            defer { _ = Darwin.close(descriptor) }
            var opened = stat()
            guard Darwin.fstat(descriptor, &opened) == 0, Self.isRegular(opened), opened.st_nlink == 1,
                  opened.st_size >= 0, opened.st_size <= 1_048_576 else {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            let identity = Identity(device: opened.st_dev, inode: opened.st_ino)
            guard identity == observed, try Self.identity(parent: parent, name: name) == identity else {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            try self.readBoundary?(.afterOpen)
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
                if count > 0 {
                    guard count <= 1_048_576 - data.count else { throw TemporalEvidenceContractFailureV1.limitExceeded }
                    data.append(contentsOf: buffer.prefix(count))
                    try self.readBoundary?(.accumulatedRead(data.count))
                }
                else if count == 0 { break }
                else if errno != EINTR { throw TemporalEvidenceContractFailureV1.interruption }
            }
            var final = stat()
            guard Darwin.fstat(descriptor, &final) == 0, Self.isRegular(final), final.st_nlink == 1,
                  final.st_size >= 0, final.st_size <= 1_048_576, final.st_size == Int64(data.count),
                  try Self.regularIdentity(descriptor) == identity,
                  try Self.identity(parent: parent, name: name) == identity else {
                throw TemporalEvidenceContractFailureV1.interruption
            }
            try self.reprove(parent: parent, expected: expected)
            return data
        }
    }

    func replace(_ data: Data, named name: String) throws {
        try validLeaf(name)
        try withJournalDirectory { parent, expected in
            try self.reprove(parent: parent, expected: expected)
            let temporary = ".temporal-journal-\(UUID().uuidString.lowercased()).tmp"
            let descriptor = Darwin.openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
            guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
            let temporaryIdentity: Identity
            do { temporaryIdentity = try Self.regularIdentity(descriptor) }
            catch { _ = Darwin.close(descriptor); _ = Darwin.unlinkat(parent, temporary, 0); throw error }
            var open = true
            defer { if open { _ = Darwin.close(descriptor) } }
            do {
                try data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    var offset = 0
                    while offset < raw.count {
                        let count = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
                        if count > 0 { offset += count }
                        else if count < 0, errno == EINTR { continue }
                        else { throw TemporalEvidenceContractFailureV1.interruption }
                    }
                }
                guard Darwin.fsync(descriptor) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
                guard Darwin.close(descriptor) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
                open = false
                try self.reprove(parent: parent, expected: expected)
                var existing = stat()
                let hasExisting = Darwin.fstatat(parent, name, &existing, AT_SYMLINK_NOFOLLOW) == 0
                if hasExisting { guard Self.isRegular(existing), existing.st_nlink == 1 else { throw TemporalEvidenceContractFailureV1.interruption } }
                else { guard errno == ENOENT else { throw TemporalEvidenceContractFailureV1.interruption } }
                let displacedIdentity: Identity?
                if hasExisting {
                    let observed = Identity(device: existing.st_dev, inode: existing.st_ino)
                    let pinned = try Self.identity(parent: parent, name: name)
                    guard pinned == observed else { throw TemporalEvidenceContractFailureV1.interruption }
                    displacedIdentity = pinned
                } else {
                    displacedIdentity = nil
                }
                let flags: UInt32 = hasExisting ? UInt32(RENAME_SWAP) : UInt32(RENAME_EXCL)
                guard Darwin.renameatx_np(parent, temporary, parent, name, flags) == 0 else {
                    throw TemporalEvidenceContractFailureV1.interruption
                }
                let published: Identity? = try? Self.identity(parent: parent, name: name)
                let displaced: Identity? = hasExisting ? (try? Self.identity(parent: parent, name: temporary)) : nil
                guard let published, published == temporaryIdentity,
                      (!hasExisting || displaced == displacedIdentity),
                      Darwin.fsync(parent) == 0 else {
                    try self.restoreOrRetainAfterFailedPublication(
                        parent: parent, name: name, temporary: temporary,
                        publishedIdentity: temporaryIdentity, displacedIdentity: displacedIdentity
                    )
                    throw TemporalEvidenceContractFailureV1.interruption
                }
                if let displacedIdentity {
                    guard try Self.identity(parent: parent, name: temporary) == displacedIdentity,
                          Darwin.unlinkat(parent, temporary, 0) == 0,
                          Darwin.fsync(parent) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
                }
                try self.reprove(parent: parent, expected: expected)
            } catch {
                if open { _ = Darwin.close(descriptor); open = false }
                if let identity = try? Self.identity(parent: parent, name: temporary), identity == temporaryIdentity { _ = Darwin.unlinkat(parent, temporary, 0); _ = Darwin.fsync(parent) }
                throw error
            }
        }
    }

    private func withJournalDirectory<T>(_ body: (Int32, [Identity]) throws -> T) throws -> T {
        try reproveRoot()
        var descriptor = Darwin.dup(root)
        guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        var descriptors = [descriptor]; var expected = [try Self.directoryIdentity(descriptor)]
        defer { descriptors.reversed().forEach { _ = Darwin.close($0) } }
        for component in components {
            var next = Darwin.openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if next < 0, errno == ENOENT {
                guard Darwin.mkdirat(descriptor, component, mode_t(0o700)) == 0 || errno == EEXIST,
                      Darwin.fsync(descriptor) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
                next = Darwin.openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            }
            guard next >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
            descriptors.append(next); expected.append(try Self.directoryIdentity(next)); descriptor = next
        }
        if let pinnedDirectories {
            guard expected == pinnedDirectories else { throw TemporalEvidenceContractFailureV1.interruption }
        } else {
            pinnedDirectories = expected
        }
        let result = try body(descriptor, expected)
        try reprove(parent: descriptor, expected: expected)
        return result
    }

    private func reprove(parent: Int32, expected: [Identity]) throws {
        try reproveRoot()
        guard let expectedParent = expected.last,
              try Self.directoryIdentity(parent) == expectedParent else { throw TemporalEvidenceContractFailureV1.interruption }
        var descriptor = Darwin.dup(root)
        guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        defer { _ = Darwin.close(descriptor) }
        for (index, component) in components.enumerated() {
            let next = Darwin.openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }
            guard try Self.directoryIdentity(next) == expected[index + 1] else {
                _ = Darwin.close(next)
                throw TemporalEvidenceContractFailureV1.interruption
            }
            _ = Darwin.close(descriptor)
            descriptor = next
        }
    }

    /// A swap may have already published our file when a hostile leaf changes.
    /// Restore only when both post-swap names still prove the exact identities;
    /// otherwise retain both leaves for recovery rather than deleting a foreign
    /// entry or pretending the race did not occur.
    private func restoreOrRetainAfterFailedPublication(
        parent: Int32, name: String, temporary: String, publishedIdentity: Identity,
        displacedIdentity: Identity?
    ) throws {
        guard let displacedIdentity,
              (try? Self.identity(parent: parent, name: name)) == publishedIdentity,
              (try? Self.identity(parent: parent, name: temporary)) == displacedIdentity else { return }
        guard Darwin.renameatx_np(parent, name, parent, temporary, UInt32(RENAME_SWAP)) == 0,
              Darwin.fsync(parent) == 0,
              try Self.identity(parent: parent, name: name) == displacedIdentity,
              try Self.identity(parent: parent, name: temporary) == publishedIdentity,
              Darwin.unlinkat(parent, temporary, 0) == 0,
              Darwin.fsync(parent) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
    }

    private func reproveRoot() throws {
        guard try Self.directoryIdentity(root) == rootIdentity,
              try Self.directoryIdentity(at: rootURL) == rootIdentity else { throw TemporalEvidenceContractFailureV1.interruption }
    }
    private func validLeaf(_ value: String) throws { guard !value.isEmpty, !value.contains("/"), value != ".", value != ".." else { throw TemporalEvidenceContractFailureV1.invalidValue } }
    private static func isRegular(_ info: stat) -> Bool { (info.st_mode & S_IFMT) == S_IFREG }
    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity { var info = stat(); guard Darwin.fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { throw TemporalEvidenceContractFailureV1.interruption }; return .init(device: info.st_dev, inode: info.st_ino) }
    private static func directoryIdentity(at url: URL) throws -> Identity { let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW); guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }; defer { _ = Darwin.close(descriptor) }; return try directoryIdentity(descriptor) }
    private static func regularIdentity(_ descriptor: Int32) throws -> Identity { var info = stat(); guard Darwin.fstat(descriptor, &info) == 0, isRegular(info), info.st_nlink == 1 else { throw TemporalEvidenceContractFailureV1.interruption }; return .init(device: info.st_dev, inode: info.st_ino) }
    private static func identity(parent: Int32, name: String) throws -> Identity { let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW); guard descriptor >= 0 else { throw TemporalEvidenceContractFailureV1.interruption }; defer { _ = Darwin.close(descriptor) }; return try regularIdentity(descriptor) }
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

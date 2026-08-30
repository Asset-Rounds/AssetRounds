import CryptoKit
import Foundation

enum EncryptedPortableEnvelopeStoragePurposeV1:String,Equatable,Sendable{case seal="SEAL";case open="OPEN";case reopenBeforeShare="REOPEN_BEFORE_SHARE"}
enum EncryptedPortableEnvelopeExecutionModeV1:String,Equatable,Sendable{case new="NEW";case retry="RETRY"}
enum EncryptedPortableEnvelopeEffectV1:String,Equatable,Sendable{case completed="COMPLETED";case noEffect="NO_EFFECT"}

struct EncryptedPortableEnvelopeOperationIdentityV1:Equatable,Hashable,Sendable{
    let workspaceID:WorkspaceID;let attemptID:UUID;let mutationID:MutationIDV1;let createdAt:Date;let expiresAt:Date
    init(workspaceID:WorkspaceID,attemptID:UUID,mutationID:MutationIDV1,createdAt:Date,expiresAt:Date)throws{let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));guard workspaceID.rawValue != zero,attemptID != zero,createdAt.timeIntervalSinceReferenceDate.isFinite,expiresAt.timeIntervalSinceReferenceDate.isFinite,expiresAt>createdAt else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};self.workspaceID=workspaceID;self.attemptID=attemptID;self.mutationID=mutationID;self.createdAt=createdAt;self.expiresAt=expiresAt}
}

struct EncryptedPortableEnvelopeTopologyV1:Equatable,Sendable{
    let innerKind:EncryptedPortableEnvelopeInnerKindV1;let innerProtocolVersion:EncryptedPortableEnvelopeInnerProtocolVersionV1;let plaintextByteCount:UInt64;let frameCount:UInt32;let envelopeByteCount:UInt64
    init(innerKind:EncryptedPortableEnvelopeInnerKindV1,innerProtocolVersion:EncryptedPortableEnvelopeInnerProtocolVersionV1,plaintextByteCount:UInt64,limits:EncryptedPortableEnvelopeResourceLimitsV1)throws{try limits.validate();let profile=EncryptedEnvelopeAEADProfileV1.released;let count=try EncryptedPortableEnvelopePublicHeaderV1.canonicalFrameCount(plaintextByteCount:plaintextByteCount,frameByteLimit:UInt64(profile.framePlaintextByteLimit));guard count<=limits.maximumFrameCount,plaintextByteCount<=limits.maximumPlaintextByteCount else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};let perFrame=UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount)+UInt64(profile.authenticationTagByteCount);let(framing,fo)=UInt64(count).multipliedReportingOverflow(by:perFrame);let(withHeader,ho)=plaintextByteCount.addingReportingOverflow(UInt64(EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount));let(total,to)=withHeader.addingReportingOverflow(framing);guard !fo,!ho,!to,total<=limits.maximumEnvelopeByteCount else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};self.innerKind=innerKind;self.innerProtocolVersion=innerProtocolVersion;self.plaintextByteCount=plaintextByteCount;frameCount=count;envelopeByteCount=total}
}

final class EncryptedPortableEnvelopeCancellationTokenV1:EncryptedEnvelopeCancellationCheckingV1,@unchecked Sendable{
    private let lock=NSLock();private var cancelled=false
    func cancel(){lock.withLock{cancelled=true}}
    func checkCancellation()throws{if lock.withLock({cancelled}){throw EncryptedPortableEnvelopeFailureV1.cancelled}}
    var isCancellationRequested:Bool{lock.withLock{cancelled}}
}

struct EncryptedPortableEnvelopeSealResourcesV1:Sendable{let operation:EncryptedPortableEnvelopeOperationIdentityV1;let envelopeScratch:any EncryptedEnvelopeProtectedScratchSinkV1;let reopenPlaintextScratch:any EncryptedEnvelopeProtectedScratchSinkV1;let cancellation:EncryptedPortableEnvelopeCancellationTokenV1}
struct EncryptedPortableEnvelopeOpenResourcesV1:Sendable{let operation:EncryptedPortableEnvelopeOperationIdentityV1;let plaintextScratch:any EncryptedEnvelopeProtectedScratchSinkV1;let cancellation:EncryptedPortableEnvelopeCancellationTokenV1}
struct EncryptedPortableEnvelopeFinalizedSealV1:Sendable{let source:any EncryptedEnvelopeBoundedSeekableSourceV1;let receipt:EncryptedEnvelopeSealReceiptV1}

protocol EncryptedPortableEnvelopeCryptographicPortV1:Sendable{
    func structuralPreflight(source:any EncryptedEnvelopeBoundedSeekableSourceV1,limits:EncryptedPortableEnvelopeResourceLimitsV1,cancellation:any EncryptedEnvelopeCancellationCheckingV1)throws->EncryptedEnvelopeStructuralPreflightReceiptV1
    func sealStreaming(innerSource:any EncryptedEnvelopeBoundedSeekableSourceV1,innerKind:EncryptedPortableEnvelopeInnerKindV1,innerProtocolVersion:EncryptedPortableEnvelopeInnerProtocolVersionV1,reviewProtectionMode:ReviewExchangeProtectionV1?,passphrase:EphemeralPassphraseV1,context:EncryptedEnvelopeOperationReceiptContextV1,limits:EncryptedPortableEnvelopeResourceLimitsV1,envelopeScratch:any EncryptedEnvelopeProtectedScratchSinkV1,reopenPlaintextScratch:any EncryptedEnvelopeProtectedScratchSinkV1,validateSourceInner:EncryptedEnvelopeStreamingInnerValidatorV1,validateReopenedInner:EncryptedEnvelopeStreamingInnerValidatorV1,cancellation:any EncryptedEnvelopeCancellationCheckingV1)throws->EncryptedPortableEnvelopeStreamingSealResultV1
    func openStreaming(envelopeSource:any EncryptedEnvelopeBoundedSeekableSourceV1,passphrase:EphemeralPassphraseV1,context:EncryptedEnvelopeOperationReceiptContextV1,limits:EncryptedPortableEnvelopeResourceLimitsV1,plaintextScratch:any EncryptedEnvelopeProtectedScratchSinkV1,validateInner:EncryptedEnvelopeStreamingInnerValidatorV1,cancellation:any EncryptedEnvelopeCancellationCheckingV1)throws->EncryptedPortableEnvelopeStreamingOpenResultV1
}

protocol EncryptedPortableEnvelopePublishedSourceV1:EncryptedEnvelopeBoundedSeekableSourceV1{var isIndependentFromProtectedScratch:Bool{get}}
/// A publication remains private until `commitPublication`; a throwing stage or
/// commit must leave no externally visible artifact. Rollback is total and nonthrowing.
protocol EncryptedPortableEnvelopePublicationTransactionV1:AnyObject,Sendable{var stagedSource:any EncryptedPortableEnvelopePublishedSourceV1{get};func commitPublication()async throws;func rollbackPublication()async}
protocol EncryptedPortableEnvelopeSharePublishingV1:Sendable{func stageEncryptedEnvelope(source:any EncryptedEnvelopeBoundedSeekableSourceV1,byteCount:UInt64,filename:String,shareTitle:String,cancellation:any EncryptedEnvelopeCancellationCheckingV1)async throws->any EncryptedPortableEnvelopePublicationTransactionV1}
protocol EncryptedPortableEnvelopeAttemptLifecycleV1:AnyObject,Sendable{
    func claimSecret(operation:EncryptedPortableEnvelopeOperationIdentityV1,secret:EphemeralPassphraseV1)async throws->EncryptedPortableEnvelopeCancellationTokenV1
    func prepareSeal(operation:EncryptedPortableEnvelopeOperationIdentityV1,topology:EncryptedPortableEnvelopeTopologyV1)async throws->EncryptedPortableEnvelopeSealResourcesV1
    func prepareOpen(operation:EncryptedPortableEnvelopeOperationIdentityV1,preflight:EncryptedEnvelopeStructuralPreflightReceiptV1)async throws->EncryptedPortableEnvelopeOpenResourcesV1
    func publishAndCleanupSeal(resources:EncryptedPortableEnvelopeSealResourcesV1,facts:EncryptedEnvelopeSealCryptographicFactsV1)async throws->EncryptedPortableEnvelopeFinalizedSealV1
    func cleanupOpen(resources:EncryptedPortableEnvelopeOpenResourcesV1,facts:EncryptedEnvelopeOpenCryptographicFactsV1)async throws
    func completeOpenFinalization(operation:EncryptedPortableEnvelopeOperationIdentityV1,cancellation:EncryptedPortableEnvelopeCancellationTokenV1)async throws
    func abandonOpenFinalization(operation:EncryptedPortableEnvelopeOperationIdentityV1)async
    func abort(operation:EncryptedPortableEnvelopeOperationIdentityV1)async throws
}
protocol EncryptedPortableEnvelopeLegacyClearReaderV1:Sendable{func readLegacyClear(source:any EncryptedEnvelopeBoundedSeekableSourceV1,kind:EncryptedPortableEnvelopeInnerKindV1,version:EncryptedPortableEnvelopeInnerProtocolVersionV1)throws}
/// Staging may copy only to private, noncanonical state. Commit is atomic and a
/// throwing commit leaves no canonical mutation; rollback is total even after commit.
protocol EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1:AnyObject,Sendable{func commit()async throws;func rollback()async}
protocol EncryptedPortableEnvelopeAuthenticatedInnerConsumerV1:Sendable{func stageAuthenticatedInner(source:any EncryptedEnvelopeBoundedSeekableSourceV1,kind:EncryptedPortableEnvelopeInnerKindV1,version:EncryptedPortableEnvelopeInnerProtocolVersionV1)async throws->any EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1}

struct EncryptedPortableEnvelopeInnerDispatchV1:Sendable{
    struct Binding:Sendable{let version:EncryptedPortableEnvelopeInnerProtocolVersionV1;let validate:EncryptedEnvelopeStreamingInnerValidatorV1}
    let workspaceBackup:Binding;let reviewRequest:Binding;let reviewResponse:Binding
    init(workspaceBackup:Binding,reviewRequest:Binding,reviewResponse:Binding){self.workspaceBackup=workspaceBackup;self.reviewRequest=reviewRequest;self.reviewResponse=reviewResponse}
    func validateSource(source:any EncryptedEnvelopeBoundedSeekableSourceV1,kind:EncryptedPortableEnvelopeInnerKindV1,version:EncryptedPortableEnvelopeInnerProtocolVersionV1)throws{let binding=try resolved(kind:kind,version:version);guard try source.encryptedEnvelopeByteCount()<=EncryptedPortableEnvelopeResourceLimitsV1.maximumOperationalPlaintextByteCount else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};try binding.validate(source,kind,version)}
    func validateReopened(source:any EncryptedEnvelopeBoundedSeekableSourceV1,kind:EncryptedPortableEnvelopeInnerKindV1,version:EncryptedPortableEnvelopeInnerProtocolVersionV1)throws{let binding=try resolved(kind:kind,version:version);try binding.validate(source,kind,version)}
    private func resolved(kind:EncryptedPortableEnvelopeInnerKindV1,version:EncryptedPortableEnvelopeInnerProtocolVersionV1)throws->Binding{let binding:Binding;switch kind{case .workspaceBackup:binding=workspaceBackup;case .reviewRequest:binding=reviewRequest;case .reviewResponse:binding=reviewResponse};guard binding.version == version else{throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol};return binding}
}

struct EncryptedPortableEnvelopeSealRequestV1:Sendable{let operation:EncryptedPortableEnvelopeOperationIdentityV1;let source:any EncryptedEnvelopeBoundedSeekableSourceV1;let innerKind:EncryptedPortableEnvelopeInnerKindV1;let innerProtocolVersion:EncryptedPortableEnvelopeInnerProtocolVersionV1;let reviewProtectionMode:ReviewExchangeProtectionV1?;let passphrase:EphemeralPassphraseV1;let receiptContext:EncryptedEnvelopeOperationReceiptContextV1;let limits:EncryptedPortableEnvelopeResourceLimitsV1;let executionMode:EncryptedPortableEnvelopeExecutionModeV1}
struct EncryptedPortableEnvelopeOpenRequestV1:Sendable{let operation:EncryptedPortableEnvelopeOperationIdentityV1;let source:any EncryptedEnvelopeBoundedSeekableSourceV1;let passphrase:EphemeralPassphraseV1;let receiptContext:EncryptedEnvelopeOperationReceiptContextV1;let limits:EncryptedPortableEnvelopeResourceLimitsV1;let executionMode:EncryptedPortableEnvelopeExecutionModeV1}
struct EncryptedPortableEnvelopeSealOutcomeV1:Sendable{let effect:EncryptedPortableEnvelopeEffectV1;let source:(any EncryptedEnvelopeBoundedSeekableSourceV1)?;let receipt:EncryptedEnvelopeSealReceiptV1?;let filename:String?;let shareTitle:String?}
struct EncryptedPortableEnvelopeOpenOutcomeV1:Sendable{let effect:EncryptedPortableEnvelopeEffectV1;let receipt:EncryptedEnvelopeOpenReceiptV1?}

private struct EncryptedPortableEnvelopeRequestIdentityV1:Equatable,Sendable{let sourceSHA256:Data;let sourceByteCount:UInt64;let innerKind:EncryptedPortableEnvelopeInnerKindV1;let innerProtocolVersion:EncryptedPortableEnvelopeInnerProtocolVersionV1;let reviewProtectionMode:ReviewExchangeProtectionV1?;let passphraseOwnerID:UUID;let limits:EncryptedPortableEnvelopeResourceLimitsV1;let context:EncryptedEnvelopeOperationReceiptContextV1}
private enum EncryptedPortableEnvelopeTerminalOutcomeV1:Sendable{case seal(EncryptedPortableEnvelopeRequestIdentityV1,EncryptedPortableEnvelopeSealOutcomeV1);case open(EncryptedPortableEnvelopeRequestIdentityV1,EncryptedPortableEnvelopeOpenOutcomeV1);var identity:EncryptedPortableEnvelopeRequestIdentityV1{switch self{case .seal(let value,_),.open(let value,_):value}}}

actor EncryptedPortableEnvelopeCoordinatorV1{
    private let crypto:any EncryptedPortableEnvelopeCryptographicPortV1;private let lifecycle:any EncryptedPortableEnvelopeAttemptLifecycleV1;private let validateSourceInner:EncryptedEnvelopeStreamingInnerValidatorV1;private let validateReopenedInner:EncryptedEnvelopeStreamingInnerValidatorV1;private let innerConsumer:any EncryptedPortableEnvelopeAuthenticatedInnerConsumerV1;private let legacyClearReader:any EncryptedPortableEnvelopeLegacyClearReaderV1;private var terminal:[EncryptedPortableEnvelopeOperationIdentityV1:EncryptedPortableEnvelopeTerminalOutcomeV1]=[:];private var failureReceipts:[EncryptedPortableEnvelopeOperationIdentityV1:EncryptedEnvelopeFailureReceiptV1]=[:];private var busy:Set<EncryptedPortableEnvelopeOperationIdentityV1>=[];private var waiters:[EncryptedPortableEnvelopeOperationIdentityV1:[CheckedContinuation<Void,Never>]]=[:]
    init(crypto:any EncryptedPortableEnvelopeCryptographicPortV1,lifecycle:any EncryptedPortableEnvelopeAttemptLifecycleV1,innerDispatch:EncryptedPortableEnvelopeInnerDispatchV1,innerConsumer:any EncryptedPortableEnvelopeAuthenticatedInnerConsumerV1,legacyClearReader:any EncryptedPortableEnvelopeLegacyClearReaderV1){self.crypto=crypto;self.lifecycle=lifecycle;self.validateSourceInner={source,kind,version in try innerDispatch.validateSource(source:source,kind:kind,version:version)};self.validateReopenedInner={source,kind,version in try innerDispatch.validateReopened(source:source,kind:kind,version:version)};self.innerConsumer=innerConsumer;self.legacyClearReader=legacyClearReader}

    func seal(_ request:EncryptedPortableEnvelopeSealRequestV1)async throws->EncryptedPortableEnvelopeSealOutcomeV1{await acquire(request.operation);defer{release(request.operation)};return try await sealLocked(request)}

    private func sealLocked(_ request:EncryptedPortableEnvelopeSealRequestV1)async throws->EncryptedPortableEnvelopeSealOutcomeV1{
        let cancellation=try await claim(operation:request.operation,secret:request.passphrase)
        do{
            try Self.validateContext(request.receiptContext,for:request.operation)
            try Self.validateReviewMode(kind:request.innerKind,mode:request.reviewProtectionMode)
            let byteCount=try request.source.encryptedEnvelopeByteCount()
            let topology=try EncryptedPortableEnvelopeTopologyV1(innerKind:request.innerKind,innerProtocolVersion:request.innerProtocolVersion,plaintextByteCount:byteCount,limits:request.limits)
            let identity=try Self.requestIdentity(source:request.source,kind:request.innerKind,version:request.innerProtocolVersion,reviewProtectionMode:request.reviewProtectionMode,passphrase:request.passphrase,limits:request.limits,context:request.receiptContext,cancellation:cancellation)
            if let cached=try cachedSeal(operation:request.operation,identity:identity){try await lifecycle.abort(operation:request.operation);return cached}
            if request.executionMode == .retry{try await lifecycle.abort(operation:request.operation);return .init(effect:.noEffect,source:nil,receipt:nil,filename:nil,shareTitle:nil)}
            let resources=try await lifecycle.prepareSeal(operation:request.operation,topology:topology)
            let result=try crypto.sealStreaming(innerSource:request.source,innerKind:request.innerKind,innerProtocolVersion:request.innerProtocolVersion,reviewProtectionMode:request.reviewProtectionMode,passphrase:request.passphrase,context:request.receiptContext,limits:request.limits,envelopeScratch:resources.envelopeScratch,reopenPlaintextScratch:resources.reopenPlaintextScratch,validateSourceInner:validateSourceInner,validateReopenedInner:validateReopenedInner,cancellation:resources.cancellation)
            guard result.facts.plaintextSHA256 == identity.sourceSHA256,result.publicHeader.declaredPlaintextByteCount == identity.sourceByteCount else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout}
            let finalized=try await lifecycle.publishAndCleanupSeal(resources:resources,facts:result.facts)
            let receipt=finalized.receipt
            let filename=try EncryptedPortableEnvelopeFilenameV1.neutralFileName(innerKind:result.publicHeader.innerKind,publicEnvelopeID:result.publicHeader.publicEnvelopeID)
            let title=try EncryptedPortableEnvelopeFilenameV1.neutralShareTitle(innerKind:result.publicHeader.innerKind,publicEnvelopeID:result.publicHeader.publicEnvelopeID)
            guard receipt.neutralFilename == filename,receipt.neutralShareTitle == title else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader}
            let outcome=EncryptedPortableEnvelopeSealOutcomeV1(effect:.completed,source:finalized.source,receipt:receipt,filename:filename,shareTitle:title)
            terminal[request.operation] = .seal(identity,outcome)
            return outcome
        }catch{let failure=await finalizedFailure(operation:request.operation,context:request.receiptContext,error:error);throw failure}
    }

    func open(_ request:EncryptedPortableEnvelopeOpenRequestV1)async throws->EncryptedPortableEnvelopeOpenOutcomeV1{await acquire(request.operation);defer{release(request.operation)};return try await openLocked(request)}

    private func openLocked(_ request:EncryptedPortableEnvelopeOpenRequestV1)async throws->EncryptedPortableEnvelopeOpenOutcomeV1{
        let entryCancellation=try await claim(operation:request.operation,secret:request.passphrase)
        do{
            try Self.validateContext(request.receiptContext,for:request.operation)
            let preflight=try crypto.structuralPreflight(source:request.source,limits:request.limits,cancellation:entryCancellation)
            let headerBytes=try Self.readExactly(source:request.source,atOffset:0,byteCount:EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount)
            let header=try EncryptedPortableEnvelopeBinaryCodecV1.decodePublicHeader(headerBytes)
            let identity=try Self.requestIdentity(source:request.source,kind:header.innerKind,version:header.innerProtocolVersion,reviewProtectionMode:header.reviewProtectionMode,passphrase:request.passphrase,limits:request.limits,context:request.receiptContext,cancellation:entryCancellation)
            if let cached=try cachedOpen(operation:request.operation,identity:identity){try await lifecycle.abort(operation:request.operation);return cached}
            if request.executionMode == .retry{try await lifecycle.abort(operation:request.operation);return .init(effect:.noEffect,receipt:nil)}
            let resources=try await lifecycle.prepareOpen(operation:request.operation,preflight:preflight)
            let result=try crypto.openStreaming(envelopeSource:request.source,passphrase:request.passphrase,context:request.receiptContext,limits:request.limits,plaintextScratch:resources.plaintextScratch,validateInner:validateReopenedInner,cancellation:resources.cancellation)
            guard result.facts.encryptedFileSHA256 == identity.sourceSHA256,result.facts.envelopeByteCount == identity.sourceByteCount else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout}
            let transaction=try await innerConsumer.stageAuthenticatedInner(source:resources.plaintextScratch,kind:result.publicHeader.innerKind,version:result.publicHeader.innerProtocolVersion)
            do{
                try await lifecycle.cleanupOpen(resources:resources,facts:result.facts)
                let receipt=try EncryptedEnvelopeOpenReceiptV1(finalizing:result.facts)
                try resources.cancellation.checkCancellation()
                try await transaction.commit()
                try resources.cancellation.checkCancellation()
                try await lifecycle.completeOpenFinalization(operation:resources.operation,cancellation:resources.cancellation)
                let outcome=EncryptedPortableEnvelopeOpenOutcomeV1(effect:.completed,receipt:receipt)
                terminal[request.operation] = .open(identity,outcome)
                return outcome
            }catch{await transaction.rollback();await lifecycle.abandonOpenFinalization(operation:resources.operation);throw error}
        }catch{let failure=await finalizedFailure(operation:request.operation,context:request.receiptContext,error:error);throw failure}
    }

    func protectReviewResponse(request:EncryptedPortableEnvelopeOpenRequestV1,response:EncryptedPortableEnvelopeSealRequestV1)async throws->EncryptedPortableEnvelopeSealOutcomeV1{
        guard request.operation != response.operation,
              request.operation.attemptID != response.operation.attemptID else{throw EncryptedPortableEnvelopeExternalFailureV1.wrongPassphraseOrDamagedEnvelope}
        let operations=[request.operation,response.operation].sorted{$0.attemptID.uuidString<$1.attemptID.uuidString}
        for operation in operations{await acquire(operation)}
        defer{for operation in operations.reversed(){release(operation)}}
        _ = try await claim(operation:request.operation,secret:request.passphrase)
        do{
            _ = try await claim(operation:response.operation,secret:response.passphrase)
            try ReviewExchangeProtectionV1.passphraseEncryptedV1.validateSamePassphraseOwner(request:request.passphrase,response:response.passphrase)
            guard response.innerKind == .reviewResponse,response.reviewProtectionMode == .passphraseEncryptedV1 else{throw EncryptedPortableEnvelopeExternalFailureV1.unsupportedRelease}
            let opened=try await openLocked(request)
            guard opened.effect == .completed,opened.receipt?.innerKind == .reviewRequest,opened.receipt?.reviewProtectionMode == .passphraseEncryptedV1 else{try await lifecycle.abort(operation:response.operation);return .init(effect:.noEffect,source:nil,receipt:nil,filename:nil,shareTitle:nil)}
            return try await sealLocked(response)
        }catch{try? await lifecycle.abort(operation:request.operation);try? await lifecycle.abort(operation:response.operation);throw error}
    }

    func readLegacyClear(source:any EncryptedEnvelopeBoundedSeekableSourceV1,kind:EncryptedPortableEnvelopeInnerKindV1,version:EncryptedPortableEnvelopeInnerProtocolVersionV1,protection:ReviewExchangeProtectionV1)throws{guard protection == .clearWithExplicitWarning,protection.displaysCleartextWarning,ReviewExchangeProtectionV1.legacyClearReadersRemainAvailable else{throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol};try validateReopenedInner(source,kind,version);try legacyClearReader.readLegacyClear(source:source,kind:kind,version:version)}
    func terminalOutcomeCount()->Int{terminal.count}
    func failureReceipt(for operation:EncryptedPortableEnvelopeOperationIdentityV1)->EncryptedEnvelopeFailureReceiptV1?{failureReceipts[operation]}
    func cancel(operation:EncryptedPortableEnvelopeOperationIdentityV1)async throws{try await lifecycle.abort(operation:operation)}

    private func claim(operation:EncryptedPortableEnvelopeOperationIdentityV1,secret:EphemeralPassphraseV1)async throws->EncryptedPortableEnvelopeCancellationTokenV1{do{return try await lifecycle.claimSecret(operation:operation,secret:secret)}catch{secret.clear();throw EncryptedEnvelopeErrorCategoryV1.externalFailure(for:error)}}
    private func finalizedFailure(operation:EncryptedPortableEnvelopeOperationIdentityV1,context:EncryptedEnvelopeOperationReceiptContextV1,error:Error)async->EncryptedPortableEnvelopeExternalFailureV1{let failure=EncryptedEnvelopeErrorCategoryV1.externalFailure(for:error);do{try await lifecycle.abort(operation:operation);if context.operationID == operation.mutationID.rawValue,context.attemptID == operation.attemptID{failureReceipts[operation]=try EncryptedEnvelopeFailureReceiptV1(context:context,failure:failure,cleanupDisposition:.completed)}}catch{return EncryptedEnvelopeErrorCategoryV1.externalFailure(for:error)};return failure}

    private func cachedSeal(operation:EncryptedPortableEnvelopeOperationIdentityV1,identity:EncryptedPortableEnvelopeRequestIdentityV1)throws->EncryptedPortableEnvelopeSealOutcomeV1?{guard let value=terminal[operation] else{return nil};guard value.identity == identity,case .seal(_,let outcome)=value else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader};if let source=outcome.source,let receipt=outcome.receipt{guard try source.encryptedEnvelopeByteCount() == receipt.envelopeByteCount,try Self.sha256(source:source,expectedByteCount:receipt.envelopeByteCount) == receipt.encryptedFileSHA256 else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout}};return outcome}
    private func cachedOpen(operation:EncryptedPortableEnvelopeOperationIdentityV1,identity:EncryptedPortableEnvelopeRequestIdentityV1)throws->EncryptedPortableEnvelopeOpenOutcomeV1?{guard let value=terminal[operation] else{return nil};guard value.identity == identity,case .open(_,let outcome)=value else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader};return outcome}
    private static func requestIdentity(source:any EncryptedEnvelopeBoundedSeekableSourceV1,kind:EncryptedPortableEnvelopeInnerKindV1,version:EncryptedPortableEnvelopeInnerProtocolVersionV1,reviewProtectionMode:ReviewExchangeProtectionV1?,passphrase:EphemeralPassphraseV1,limits:EncryptedPortableEnvelopeResourceLimitsV1,context:EncryptedEnvelopeOperationReceiptContextV1,cancellation:any EncryptedEnvelopeCancellationCheckingV1)throws->EncryptedPortableEnvelopeRequestIdentityV1{let byteCount=try source.encryptedEnvelopeByteCount();var hasher=SHA256();var offset:UInt64=0;while offset<byteCount{try cancellation.checkCancellation();let count=Int(min(UInt64(1_048_576),byteCount-offset));hasher.update(data:try readExactly(source:source,atOffset:offset,byteCount:count));offset += UInt64(count)};return .init(sourceSHA256:Data(hasher.finalize()),sourceByteCount:byteCount,innerKind:kind,innerProtocolVersion:version,reviewProtectionMode:reviewProtectionMode,passphraseOwnerID:passphrase.memoryOwnerID,limits:limits,context:context)}
    private static func readExactly(source:any EncryptedEnvelopeBoundedSeekableSourceV1,atOffset:UInt64,byteCount:Int)throws->Data{guard byteCount>=0,byteCount<=1_048_576 else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};let total=try source.encryptedEnvelopeByteCount();let(end,overflow)=atOffset.addingReportingOverflow(UInt64(byteCount));guard !overflow,end<=total else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout};let bytes=try source.readExactly(atOffset:atOffset,byteCount:byteCount);guard bytes.count == byteCount else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout};return bytes}
    private static func sha256(source:any EncryptedEnvelopeBoundedSeekableSourceV1,expectedByteCount:UInt64)throws->Data{guard try source.encryptedEnvelopeByteCount() == expectedByteCount else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout};var hasher=SHA256();var offset:UInt64=0;while offset<expectedByteCount{let count=Int(min(UInt64(1_048_576),expectedByteCount-offset));hasher.update(data:try readExactly(source:source,atOffset:offset,byteCount:count));offset += UInt64(count)};return Data(hasher.finalize())}
    private static func validateReviewMode(kind:EncryptedPortableEnvelopeInnerKindV1,mode:ReviewExchangeProtectionV1?)throws{switch kind{case .workspaceBackup:guard mode == nil else{throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol};case .reviewRequest,.reviewResponse:guard mode == .passphraseEncryptedV1 else{throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol}}}
    private static func validateContext(_ context:EncryptedEnvelopeOperationReceiptContextV1,for operation:EncryptedPortableEnvelopeOperationIdentityV1)throws{guard context.operationID == operation.mutationID.rawValue,context.attemptID == operation.attemptID else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader}}
    private func acquire(_ operation:EncryptedPortableEnvelopeOperationIdentityV1)async{if !busy.contains(operation){busy.insert(operation);return};await withCheckedContinuation{waiters[operation,default:[]].append($0)}}
    private func release(_ operation:EncryptedPortableEnvelopeOperationIdentityV1){if var queued=waiters[operation],!queued.isEmpty{let next=queued.removeFirst();waiters[operation]=queued.isEmpty ? nil:queued;next.resume()}else{busy.remove(operation);waiters[operation]=nil}}
}

enum C54EncryptedPortableEnvelopeCoordinatorBoundaryV1{
    static let maximumSourceReadBytes=1_048_576
    // Compatibility token: topologyAndResourcePreflightBeforeKDFAllocationPreviewOrWrite=true
    static let topologyAndResourcePreflightBeforeKDFAllocationPreviewOrWrite = true
    static let fullOuterAuthenticationBeforeSingleHostileInnerValidation=true
    static let finalReceiptAfterPublicationAndCleanup=true
    static let exactSameSessionRetryIsIdempotent=true
    static let absentRelaunchRetryReturnsNoEffect=true
    static let encryptedReviewResponseUsesSamePassphrase=true
    static let legacyClearReaderRequiresExplicitWarning=true
    static let createsStoreOrCanonicalWriter=false
}

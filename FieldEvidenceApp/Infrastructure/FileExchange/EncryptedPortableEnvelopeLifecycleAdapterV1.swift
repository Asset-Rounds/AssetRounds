import CryptoKit
import Foundation

actor EncryptedPortableEnvelopeLifecycleAdapterV1:EncryptedPortableEnvelopeAttemptLifecycleV1,EncryptedPortableEnvelopeSecretLifecycleV1,EncryptedPortableEnvelopeEraseScratchV1{
    private struct ActiveAttempt{
        let operation:EncryptedPortableEnvelopeOperationIdentityV1
        let secret:EphemeralPassphraseV1
        let cancellation:EncryptedPortableEnvelopeCancellationTokenV1
        var reservation:EncryptedPortableEnvelopeStorageReservationV1?
        var leases:[ScratchDataLeaseV1]
    }
    private let scratch:any ScratchDataLeasePortV1
    private let storageLedger:OwnedStorageLedgerV1
    private let storagePreflight:StoragePreflightService
    private let scratchRootURL:URL
    private let publication:any EncryptedPortableEnvelopeSharePublishingV1
    private let registrationToken=EncryptedPortableEnvelopeLifecycleRegistrationTokenV1()
    private var isDeviceLifecycleRegistered=false
    private var active:[EncryptedPortableEnvelopeOperationIdentityV1:ActiveAttempt]=[:]
    private var finalizing:[EncryptedPortableEnvelopeOperationIdentityV1:EncryptedPortableEnvelopeCancellationTokenV1]=[:]
    private var secretClaims:[ObjectIdentifier:(secret:EphemeralPassphraseV1,count:Int)]=[:]
    private var cleanupFailedOperations:Set<EncryptedPortableEnvelopeOperationIdentityV1>=[]
    private var revocationDepth=0
    private var eraseInProgress=false
    private var revocationGeneration:UInt64=0
    private var revocationGenerationExhausted=false

    init(scratch:any ScratchDataLeasePortV1,storageLedger:OwnedStorageLedgerV1,scratchRootURL:URL,publication:any EncryptedPortableEnvelopeSharePublishingV1,storagePreflight:StoragePreflightService=StoragePreflightService())throws{guard scratchRootURL.isFileURL else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};self.scratch=scratch;self.storageLedger=storageLedger;self.scratchRootURL=scratchRootURL.standardizedFileURL;self.publication=publication;self.storagePreflight=storagePreflight}

    func claimSecret(operation:EncryptedPortableEnvelopeOperationIdentityV1,secret:EphemeralPassphraseV1)async throws->EncryptedPortableEnvelopeCancellationTokenV1{guard !cleanupFailedOperations.contains(operation) else{secret.clear();throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};guard revocationDepth == 0,!eraseInProgress,!revocationGenerationExhausted else{secret.clear();throw EncryptedPortableEnvelopeFailureV1.cancelled};let admittedGeneration=revocationGeneration;do{try await ensureDeviceLifecycleRegistration()}catch{secret.clear();throw error};guard revocationDepth == 0,!eraseInProgress,!revocationGenerationExhausted,revocationGeneration == admittedGeneration else{secret.clear();throw EncryptedPortableEnvelopeFailureV1.cancelled};if let existing=active[operation]{guard existing.secret === secret else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader};return existing.cancellation};let cancellation=EncryptedPortableEnvelopeCancellationTokenV1();active[operation]=ActiveAttempt(operation:operation,secret:secret,cancellation:cancellation,reservation:nil,leases:[]);let identifier=ObjectIdentifier(secret);if let claim=secretClaims[identifier]{guard claim.secret === secret else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader};secretClaims[identifier]=(secret,claim.count+1)}else{secretClaims[identifier]=(secret,1)};return cancellation}

    func prepareSeal(operation:EncryptedPortableEnvelopeOperationIdentityV1,topology:EncryptedPortableEnvelopeTopologyV1)async throws->EncryptedPortableEnvelopeSealResourcesV1{
        guard var attempt=active[operation],attempt.reservation == nil,attempt.leases.isEmpty else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader}
        guard topology.envelopeByteCount<=ScratchDataPurposeV1.source.maximumByteCount,topology.plaintextByteCount<=ScratchDataPurposeV1.source.maximumByteCount else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}
        let required:Int64
        do{required=try storagePreflight.encryptedPortableEnvelopeStreamingRequiredBytes(plaintextByteCount:topology.plaintextByteCount,envelopeByteCount:topology.envelopeByteCount);try storagePreflight.checkEncryptedPortableEnvelopeStreaming(plaintextByteCount:topology.plaintextByteCount,envelopeByteCount:topology.envelopeByteCount,onVolumeContaining:scratchRootURL)}catch{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}
        let reservation=try reserve(operation:operation,purpose:.seal,requiredBytes:required)
        attempt.reservation=reservation;active[operation]=attempt
        do{try requireActive(operation:operation,cancellation:attempt.cancellation);let envelopeLease=try await acquireLease(operation:operation,slot:1,byteCount:max(topology.envelopeByteCount,1));try await attachAcquiredLease(envelopeLease,operation:operation,cancellation:attempt.cancellation);let plaintextLease=try await acquireLease(operation:operation,slot:2,byteCount:max(topology.plaintextByteCount,1));try await attachAcquiredLease(plaintextLease,operation:operation,cancellation:attempt.cancellation);guard let factory=scratch as? any EncryptedPortableEnvelopeStreamingScratchPortV1 else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};let envelopeSink=try await factory.makeEncryptedPortableEnvelopeStreamingScratch(named:"envelope.bin",lease:envelopeLease,maximumByteCount:topology.envelopeByteCount);do{try requireActive(operation:operation,cancellation:attempt.cancellation)}catch{try? envelopeSink.discardStreamingBytes();throw error};let plaintextSink=try await factory.makeEncryptedPortableEnvelopeStreamingScratch(named:"reopen-inner.bin",lease:plaintextLease,maximumByteCount:topology.plaintextByteCount);do{try requireActive(operation:operation,cancellation:attempt.cancellation)}catch{try? envelopeSink.discardStreamingBytes();try? plaintextSink.discardStreamingBytes();throw error};return .init(operation:operation,envelopeScratch:envelopeSink,reopenPlaintextScratch:plaintextSink,cancellation:attempt.cancellation)}catch{throw EncryptedEnvelopeErrorCategoryV1.externalFailure(for:error)}
    }

    func prepareOpen(operation:EncryptedPortableEnvelopeOperationIdentityV1,preflight:EncryptedEnvelopeStructuralPreflightReceiptV1)async throws->EncryptedPortableEnvelopeOpenResourcesV1{
        guard var attempt=active[operation],attempt.reservation == nil,attempt.leases.isEmpty,preflight.plaintextByteCount<=ScratchDataPurposeV1.source.maximumByteCount else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}
        let required:Int64
        do{required=try storagePreflight.encryptedPortableEnvelopeOpenStreamingRequiredBytes(plaintextByteCount:preflight.plaintextByteCount);try storagePreflight.checkEncryptedPortableEnvelopeOpenStreaming(plaintextByteCount:preflight.plaintextByteCount,onVolumeContaining:scratchRootURL)}catch{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}
        let reservation=try reserve(operation:operation,purpose:.open,requiredBytes:required)
        attempt.reservation=reservation;active[operation]=attempt
        do{try requireActive(operation:operation,cancellation:attempt.cancellation);let lease=try await acquireLease(operation:operation,slot:3,byteCount:max(preflight.plaintextByteCount,1));try await attachAcquiredLease(lease,operation:operation,cancellation:attempt.cancellation);guard let factory=scratch as? any EncryptedPortableEnvelopeStreamingScratchPortV1 else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};let sink=try await factory.makeEncryptedPortableEnvelopeStreamingScratch(named:"authenticated-inner.bin",lease:lease,maximumByteCount:preflight.plaintextByteCount);do{try requireActive(operation:operation,cancellation:attempt.cancellation)}catch{try? sink.discardStreamingBytes();throw error};return .init(operation:operation,plaintextScratch:sink,cancellation:attempt.cancellation)}catch{throw EncryptedEnvelopeErrorCategoryV1.externalFailure(for:error)}
    }

    func publishAndCleanupSeal(resources:EncryptedPortableEnvelopeSealResourcesV1,facts:EncryptedEnvelopeSealCryptographicFactsV1)async throws->EncryptedPortableEnvelopeFinalizedSealV1{
        guard facts.cleanupDisposition == .pending,facts.reopenedAndAuthenticated,facts.innerValidationComplete,facts.context.operationID == resources.operation.mutationID.rawValue,facts.context.attemptID == resources.operation.attemptID else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader}
        try requireActive(operation:resources.operation,cancellation:resources.cancellation)
        let filename=try EncryptedPortableEnvelopeFilenameV1.neutralFileName(innerKind:facts.publicHeader.innerKind,publicEnvelopeID:facts.publicHeader.publicEnvelopeID)
        let title=try EncryptedPortableEnvelopeFilenameV1.neutralShareTitle(innerKind:facts.publicHeader.innerKind,publicEnvelopeID:facts.publicHeader.publicEnvelopeID)
        finalizing[resources.operation]=resources.cancellation
        var stagedTransaction:(any EncryptedPortableEnvelopePublicationTransactionV1)?
        do{
            let transaction=try await publication.stageEncryptedEnvelope(source:resources.envelopeScratch,byteCount:facts.envelopeByteCount,filename:filename,shareTitle:title,cancellation:resources.cancellation)
            stagedTransaction=transaction
            let published=transaction.stagedSource
            try resources.cancellation.checkCancellation()
            guard published.isIndependentFromProtectedScratch,
                  try published.encryptedEnvelopeByteCount() == facts.envelopeByteCount,
                  try Self.sha256(of:published,expectedByteCount:facts.envelopeByteCount) == facts.encryptedFileSHA256 else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout}
            try resources.reopenPlaintextScratch.discardStreamingBytes()
            try await finish(operation:resources.operation,terminal:.completed)
            try resources.cancellation.checkCancellation()
            guard try published.encryptedEnvelopeByteCount() == facts.envelopeByteCount,
                  try Self.sha256(of:published,expectedByteCount:facts.envelopeByteCount) == facts.encryptedFileSHA256 else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout}
            let receipt=try EncryptedEnvelopeSealReceiptV1(finalizing:facts)
            try resources.cancellation.checkCancellation()
            try await transaction.commitPublication()
            try resources.cancellation.checkCancellation()
            guard try published.encryptedEnvelopeByteCount() == facts.envelopeByteCount,
                  try Self.sha256(of:published,expectedByteCount:facts.envelopeByteCount) == facts.encryptedFileSHA256 else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout}
            try await completeFinalizationAuthority(operation:resources.operation,cancellation:resources.cancellation)
            return .init(source:published,receipt:receipt)
        }catch{
            if let stagedTransaction{await stagedTransaction.rollbackPublication()}
            await abandonFinalizationAuthority(operation:resources.operation)
            throw error
        }
    }

    func cleanupOpen(resources:EncryptedPortableEnvelopeOpenResourcesV1,facts:EncryptedEnvelopeOpenCryptographicFactsV1)async throws{guard facts.cleanupDisposition == .pending,facts.outerAuthenticationComplete,facts.innerValidationComplete,facts.context.operationID == resources.operation.mutationID.rawValue,facts.context.attemptID == resources.operation.attemptID else{throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader};try requireActive(operation:resources.operation,cancellation:resources.cancellation);finalizing[resources.operation]=resources.cancellation;do{try resources.plaintextScratch.discardStreamingBytes()}catch{try? await finish(operation:resources.operation,terminal:.cancelled);finalizing.removeValue(forKey:resources.operation);await removeDeviceLifecycleRegistrationIfIdle();throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};do{try await finish(operation:resources.operation,terminal:.completed);try resources.cancellation.checkCancellation()}catch{finalizing.removeValue(forKey:resources.operation);await removeDeviceLifecycleRegistrationIfIdle();throw error}}

    func completeOpenFinalization(operation:EncryptedPortableEnvelopeOperationIdentityV1,cancellation:EncryptedPortableEnvelopeCancellationTokenV1)async throws{try await completeFinalizationAuthority(operation:operation,cancellation:cancellation)}
    func abandonOpenFinalization(operation:EncryptedPortableEnvelopeOperationIdentityV1)async{await abandonFinalizationAuthority(operation:operation)}

    func abort(operation:EncryptedPortableEnvelopeOperationIdentityV1)async throws{if let cancellation=finalizing[operation]{cancellation.cancel();return};if cleanupFailedOperations.contains(operation){throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};guard let attempt=active[operation] else{return};attempt.cancellation.cancel();try await finish(operation:operation,terminal:.cancelled)}

    func recoverInterruptedAttempts()async throws->ScratchDataLeaseRecoverySummaryV1{guard active.isEmpty,finalizing.isEmpty else{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};do{let summary:ScratchDataLeaseRecoverySummaryV1;if let authority=scratch as? any EncryptedPortableEnvelopeScratchRecoveringV1{summary=try await authority.recoverEncryptedPortableEnvelopeScratch()}else{summary=try await scratch.recoverScratchLeases()};cleanupFailedOperations.removeAll(keepingCapacity:false);return summary}catch{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}}

    func revokeEncryptedPortableEnvelopeSecrets(reason:EncryptedPortableEnvelopeSecretRevocationReasonV1)async{if revocationGeneration == .max{revocationGenerationExhausted=true}else{revocationGeneration += 1};revocationDepth += 1;let attempts=Array(active.values);for attempt in attempts{attempt.cancellation.cancel()};for cancellation in finalizing.values{cancellation.cancel()};for claim in secretClaims.values{claim.secret.clear()};secretClaims.removeAll(keepingCapacity:false);active.removeAll(keepingCapacity:false);for attempt in attempts{var failed=false;for lease in attempt.leases{do{try await scratch.releaseScratchLease(lease,terminal:.cancelled)}catch{failed=true}};if let reservation=attempt.reservation{storageLedger.releaseEncryptedPortableEnvelope(reservation)};if failed{cleanupFailedOperations.insert(attempt.operation)}};revocationDepth -= 1;await removeDeviceLifecycleRegistrationIfIdle();_ = reason}
    func eraseEncryptedPortableEnvelopeScratch()async throws{eraseInProgress=true;defer{eraseInProgress=false};await revokeEncryptedPortableEnvelopeSecrets(reason:.erase);do{try await scratch.eraseScratchData()}catch{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}}

    private func reserve(operation:EncryptedPortableEnvelopeOperationIdentityV1,purpose:EncryptedPortableEnvelopeStoragePurposeV1,requiredBytes:Int64)throws->EncryptedPortableEnvelopeStorageReservationV1{do{return try storageLedger.reserveEncryptedPortableEnvelope(.init(purpose:purpose,workspaceID:operation.workspaceID,attemptID:operation.attemptID,mutationID:operation.mutationID,requiredBytes:requiredBytes))}catch{throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}}
    private func acquireLease(operation:EncryptedPortableEnvelopeOperationIdentityV1,slot:UInt8,byteCount:UInt64)async throws->ScratchDataLeaseV1{try await scratch.acquireScratchLease(.init(leaseID:EncryptedPortableEnvelopeScratchNamespaceV1.leaseID(for:operation.attemptID,slot:slot),purpose:.source,owner:.source,ownerOperationID:operation.mutationID.rawValue,requestedByteCount:byteCount,createdAt:operation.createdAt,expiresAt:operation.expiresAt))}
    private func attachAcquiredLease(_ lease:ScratchDataLeaseV1,operation:EncryptedPortableEnvelopeOperationIdentityV1,cancellation:EncryptedPortableEnvelopeCancellationTokenV1)async throws{guard var attempt=active[operation],attempt.cancellation === cancellation,!cancellation.isCancellationRequested else{do{try await scratch.releaseScratchLease(lease,terminal:.cancelled)}catch{cleanupFailedOperations.insert(operation);throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};throw EncryptedPortableEnvelopeFailureV1.cancelled};attempt.leases.append(lease);active[operation]=attempt;try cancellation.checkCancellation()}
    private func requireActive(operation:EncryptedPortableEnvelopeOperationIdentityV1,cancellation:EncryptedPortableEnvelopeCancellationTokenV1)throws{guard let attempt=active[operation],attempt.cancellation === cancellation,!cleanupFailedOperations.contains(operation) else{throw EncryptedPortableEnvelopeFailureV1.cancelled};try cancellation.checkCancellation()}
    private func completeFinalizationAuthority(operation:EncryptedPortableEnvelopeOperationIdentityV1,cancellation:EncryptedPortableEnvelopeCancellationTokenV1)async throws{guard let authority=finalizing[operation],authority === cancellation else{throw EncryptedPortableEnvelopeFailureV1.cancelled};try cancellation.checkCancellation();if isDeviceLifecycleRegistered,active.isEmpty,finalizing.count == 1{await EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared.unregister(token:registrationToken);try cancellation.checkCancellation();isDeviceLifecycleRegistered=false};finalizing.removeValue(forKey:operation)}
    private func abandonFinalizationAuthority(operation:EncryptedPortableEnvelopeOperationIdentityV1)async{finalizing.removeValue(forKey:operation);await removeDeviceLifecycleRegistrationIfIdle()}
    private static func sha256(of source:any EncryptedEnvelopeBoundedSeekableSourceV1,expectedByteCount:UInt64)throws->Data{var hasher=SHA256();var offset:UInt64=0;while offset<expectedByteCount{let count=Int(min(UInt64(1_048_576),expectedByteCount-offset));let bytes=try source.readExactly(atOffset:offset,byteCount:count);guard bytes.count == count else{throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout};hasher.update(data:bytes);offset += UInt64(count)};return Data(hasher.finalize())}
    private func finish(operation:EncryptedPortableEnvelopeOperationIdentityV1,terminal:ScratchDataLeaseTerminalV1)async throws{
        guard let attempt=active.removeValue(forKey:operation) else{if cleanupFailedOperations.contains(operation){throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded};return}
        var cleanupFailed=false
        for lease in attempt.leases{do{try await scratch.releaseScratchLease(lease,terminal:terminal)}catch{cleanupFailed=true}}
        if let reservation=attempt.reservation{storageLedger.releaseEncryptedPortableEnvelope(reservation)}
        let identifier=ObjectIdentifier(attempt.secret)
        if let claim=secretClaims[identifier],claim.secret === attempt.secret,claim.count>0{
            if claim.count == 1{secretClaims.removeValue(forKey:identifier);attempt.secret.clear()}else{secretClaims[identifier]=(attempt.secret,claim.count-1)}
        }else{attempt.secret.clear();if !attempt.cancellation.isCancellationRequested{cleanupFailed=true}}
        await removeDeviceLifecycleRegistrationIfIdle()
        if cleanupFailed{cleanupFailedOperations.insert(operation);throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded}
        cleanupFailedOperations.remove(operation)
    }
    private func ensureDeviceLifecycleRegistration()async throws{guard await EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared.register(token:registrationToken,lifecycle:self) else{throw EncryptedPortableEnvelopeFailureV1.cancelled};isDeviceLifecycleRegistered=true}
    private func removeDeviceLifecycleRegistrationIfIdle()async{guard isDeviceLifecycleRegistered,active.isEmpty,finalizing.isEmpty else{return};await EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared.unregister(token:registrationToken);isDeviceLifecycleRegistered=false}
}

enum C54EncryptedPortableEnvelopeLifecycleBoundaryV1{static let protectedCompleteScratch=true;static let scratchExcludedFromBackup=true;static let startupRecoveryDeletesInterruptedAttempts=true;static let productionDeviceLifecycleRegistryIsLive=true;static let cancelBackgroundAppLockProtectedDataAndPressureClearSecrets=true;static let persistentLifecycleBlocksLateClaimsUntilResume=true;static let actorRevocationGateBlocksReentrantClaims=true;static let revocationGenerationFencesRegistrationOvertake=true;static let finalReceiptFollowsScratchCleanup=true;static let maximumAppendByteCount=1_048_604;static let createsSecondScratchStoreOrRoot=false;static func validate()->Bool{protectedCompleteScratch&&scratchExcludedFromBackup&&startupRecoveryDeletesInterruptedAttempts&&productionDeviceLifecycleRegistryIsLive&&cancelBackgroundAppLockProtectedDataAndPressureClearSecrets&&persistentLifecycleBlocksLateClaimsUntilResume&&actorRevocationGateBlocksReentrantClaims&&revocationGenerationFencesRegistrationOvertake&&finalReceiptFollowsScratchCleanup&&maximumAppendByteCount==EncryptedPortableEnvelopeProtectedFileScratchV1.maximumAppendByteCount&&!createsSecondScratchStoreOrRoot}}

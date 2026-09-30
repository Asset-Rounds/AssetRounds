import Foundation

struct InjectedOnDeviceSpeechCapabilityAdapterV1:SpeechCapabilityAdapterV1{
    typealias Permission=@Sendable ()async throws->SpeechPermissionDispositionV1
    typealias RequestPermission=@Sendable ()async throws->SpeechPermissionDispositionV1
    typealias Dictate=@Sendable (OnDeviceDictationRequestV1)async throws->OnDeviceDictationProposalV1
    private let permission:Permission;private let microphone:RequestPermission
    private let recognition:RequestPermission;private let dictate:Dictate
    init(permission:@escaping Permission,requestMicrophone:@escaping RequestPermission,
         requestSpeechRecognition:@escaping RequestPermission,dictate:@escaping Dictate){
        self.permission=permission;microphone=requestMicrophone;recognition=requestSpeechRecognition
        self.dictate=dictate
    }
    func permissionDisposition()async throws->SpeechPermissionDispositionV1{try await permission()}
    func requestMicrophonePermission()async throws->SpeechPermissionDispositionV1{try await microphone()}
    func requestSpeechRecognitionPermission()async throws->SpeechPermissionDispositionV1{try await recognition()}
    func dictateOnDevice(_ request:OnDeviceDictationRequestV1)async throws->OnDeviceDictationProposalV1{
        try request.validate();return try await dictate(request)
    }
}

struct InjectedOneShotLocationCapabilityAdapterV1:OneShotLocationCapabilityAdapterV1{
    typealias Permission=@Sendable ()async throws->LocationPermissionDispositionV1
    typealias RequestPermission=@Sendable ()async throws->LocationPermissionDispositionV1
    typealias Locate=@Sendable (OneShotLocationRequestV1)async throws->OneShotLocationProposalV1
    private let permission:Permission;private let requester:RequestPermission;private let locate:Locate
    private let store:LocalContentStoreV1?
    init(permission:@escaping Permission,requestWhenInUse:@escaping RequestPermission,
         store:LocalContentStoreV1?=nil,locate:@escaping Locate){self.permission=permission;requester=requestWhenInUse;self.store=store;self.locate=locate}
    func permissionDisposition()async throws->LocationPermissionDispositionV1{try await permission()}
    func requestWhenInUsePermission()async throws->LocationPermissionDispositionV1{try await requester()}
    func requestOneShotForegroundLocation(_ request:OneShotLocationRequestV1)async throws->OneShotLocationProposalV1{
        try request.validate();guard request.foreground,request.explicitUserAction else{throw DictationLocationProposalFailureV1.backgroundUseForbidden}
        try DictationLocationProposalContentIntegrityBoundaryV1.validateOneShotLocationSource(request:request)
        if let store{try DictationLocationProposalLocalContentStoreBoundaryV1.validateOneShotLocationSource(request:request,store:store)}
        return try await locate(request)
    }
}

@MainActor final class AssistanceDictationAudioScratchLifecycleV1:DictationAudioScratchLifecycleV1{
    typealias Prepare=@MainActor (OnDeviceDictationRequestV1)async throws->Void
    private let prepareOperation:Prepare
    private let assistanceScratch:any AssistanceScratchDiscardingV1
    init(assistanceScratch:any AssistanceScratchDiscardingV1,prepare:@escaping Prepare){
        self.assistanceScratch=assistanceScratch;prepareOperation=prepare
    }
    convenience init(assistanceScratch:any AssistanceScratchDiscardingV1,
                     store:LocalContentStoreV1){
        self.init(assistanceScratch:assistanceScratch){request in
            let scratch=try AssistanceCapabilityScratchV1(proposalID:request.requestID,
                source:request.scratchSource)
            try DictationLocationProposalContentIntegrityBoundaryV1.validateDictationAudioScratch(
                request:request,scratch:scratch)
            try DictationLocationProposalLocalContentStoreBoundaryV1.validateDictationAudioScratch(
                request:request,scratch:scratch,store:store)
        }
    }
    func prepare(_ request:OnDeviceDictationRequestV1)async throws{
        try request.validate();try await prepareOperation(request)
    }
    func discardAfterFailedDictation(_ request:OnDeviceDictationRequestV1)async throws{
        try request.validate()
        try await assistanceScratch.finishAssistanceScratch(proposalID:request.requestID,
            source:request.scratchSource,disposition:.failed,immutableContentReceiptDigest:nil)
    }
}

enum DictationLocationProposalLifecycleBoundaryV1{
    static let persistentSchemaVersion=53
    static let activeModelCount=168
    static let addedDurableRows=0
    static let latestTargetFallbackAllowed=false
    static let backgroundLocationAllowed=false
    static let serverSpeechFallbackAllowed=false
    static let productionAdoptionEnabled=false
}

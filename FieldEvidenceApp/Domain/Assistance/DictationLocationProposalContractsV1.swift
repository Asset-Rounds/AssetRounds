import Foundation

enum DictationLocationProposalFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, unavailable, permissionDenied
    case serverFallbackForbidden, backgroundUseForbidden, staleTarget
}

enum DictationLocationPersistenceBoundaryV1 {
    static let schemaVersion = 53
    static let activeModelCount = 168
    static let addedDurableRowCount = 0
    static let acceptanceRowName = "AssistanceAcceptanceReceiptRow"
    static let productionAdoptionEnabled = false
}

enum AssistedCaptureActivationV1: String, Codable, Hashable, Sendable {
    case preparedDisabled = "PREPARED_DISABLED"
    case enabledOnDevice = "ENABLED_ON_DEVICE"
}

enum CapabilityPermissionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notDetermined = "NOT_DETERMINED"
    case denied = "DENIED"
    case restricted = "RESTRICTED"
    case authorized = "AUTHORIZED"
    case unavailable = "UNAVAILABLE"
}

/// Microphone and speech recognition remain independently requestable and
/// observable. A denial in either domain never disables location or typing.
struct SpeechPermissionDispositionV1: Codable, Equatable, Hashable, Sendable {
    let microphone: CapabilityPermissionDispositionV1
    let speechRecognition: CapabilityPermissionDispositionV1
    let observedAt: Date

    init(microphone: CapabilityPermissionDispositionV1,
         speechRecognition: CapabilityPermissionDispositionV1,
         observedAt: Date) throws {
        try AssistanceLimitsV1.instant(observedAt)
        self.microphone = microphone
        self.speechRecognition = speechRecognition
        self.observedAt = observedAt
    }

    var permitsOnDeviceDictation: Bool {
        microphone == .authorized && speechRecognition == .authorized
    }
}

struct LocationPermissionDispositionV1: Codable, Equatable, Hashable, Sendable {
    let whenInUse: CapabilityPermissionDispositionV1
    let observedAt: Date

    init(whenInUse: CapabilityPermissionDispositionV1, observedAt: Date) throws {
        try AssistanceLimitsV1.instant(observedAt)
        self.whenInUse = whenInUse
        self.observedAt = observedAt
    }

    var permitsOneShotForegroundLocation: Bool { whenInUse == .authorized }
}

struct DictationLocationCapabilityPolicyV1: Codable, Equatable, Sendable {
    let dictationPolicy: AssistanceCapabilityPolicyV1
    let locationPolicy: AssistanceCapabilityPolicyV1
    let dictationActivation: AssistedCaptureActivationV1
    let locationActivation: AssistedCaptureActivationV1
    let supportedDictationLocales: [String]
    let maximumTranscriptUTF8Bytes: Int
    let maximumHorizontalAccuracyMillimeters: UInt64
    let policySHA256: String

    init(dictationPolicy: AssistanceCapabilityPolicyV1,
         locationPolicy: AssistanceCapabilityPolicyV1,
         dictationActivation: AssistedCaptureActivationV1 = .preparedDisabled,
         locationActivation: AssistedCaptureActivationV1 = .preparedDisabled,
         supportedDictationLocales: [String],
         maximumTranscriptUTF8Bytes: Int = ResponseValueV1.maximumTextUTF8Bytes,
         maximumHorizontalAccuracyMillimeters: UInt64 = 100_000) throws {
        try dictationPolicy.validate(); try locationPolicy.validate()
        let locales = supportedDictationLocales.sorted()
        try locales.forEach(AssistanceLimitsV1.token)
        let dictationParity = (dictationActivation == .preparedDisabled && !dictationPolicy.enabled)
            || (dictationActivation == .enabledOnDevice && dictationPolicy.enabled)
        let locationParity = (locationActivation == .preparedDisabled && !locationPolicy.enabled)
            || (locationActivation == .enabledOnDevice && locationPolicy.enabled)
        guard dictationPolicy.capability.capabilityID == "DICTATION_FIELD_PROPOSAL",
              locationPolicy.capability.capabilityID == "ONE_SHOT_LOCATION_PROPOSAL",
              dictationParity, locationParity, !locales.isEmpty,
              Set(locales).count == locales.count,
              (1...ResponseValueV1.maximumTextUTF8Bytes).contains(maximumTranscriptUTF8Bytes),
              maximumHorizontalAccuracyMillimeters > 0,
              dictationPolicy.manualFallback == .typeManually,
              locationPolicy.manualFallback == .typeManually else {
            throw DictationLocationProposalFailureV1.invalidValue
        }
        self.dictationPolicy = dictationPolicy; self.locationPolicy = locationPolicy
        self.dictationActivation = dictationActivation; self.locationActivation = locationActivation
        self.supportedDictationLocales = locales
        self.maximumTranscriptUTF8Bytes = maximumTranscriptUTF8Bytes
        self.maximumHorizontalAccuracyMillimeters = maximumHorizontalAccuracyMillimeters
        policySHA256 = try AssistanceCanonicalCodecV1.sha256(Basis(
            dictationPolicy: dictationPolicy, locationPolicy: locationPolicy,
            dictationActivation: dictationActivation, locationActivation: locationActivation,
            supportedDictationLocales: locales,
            maximumTranscriptUTF8Bytes: maximumTranscriptUTF8Bytes,
            maximumHorizontalAccuracyMillimeters: maximumHorizontalAccuracyMillimeters))
    }

    func validate() throws {
        guard self == (try Self(dictationPolicy: dictationPolicy,
            locationPolicy: locationPolicy, dictationActivation: dictationActivation,
            locationActivation: locationActivation,
            supportedDictationLocales: supportedDictationLocales,
            maximumTranscriptUTF8Bytes: maximumTranscriptUTF8Bytes,
            maximumHorizontalAccuracyMillimeters: maximumHorizontalAccuracyMillimeters)) else {
            throw DictationLocationProposalFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable {
        let dictationPolicy: AssistanceCapabilityPolicyV1
        let locationPolicy: AssistanceCapabilityPolicyV1
        let dictationActivation: AssistedCaptureActivationV1
        let locationActivation: AssistedCaptureActivationV1
        let supportedDictationLocales: [String]
        let maximumTranscriptUTF8Bytes: Int
        let maximumHorizontalAccuracyMillimeters: UInt64
    }
}

struct OnDeviceDictationRequestV1: Codable, Equatable, Sendable {
    let requestID: UUID
    let workspaceID: WorkspaceID
    let target: AssistanceTargetV1
    let scratchSource: AssistanceSourceReferenceV1
    let localeIdentifier: String
    let recognitionRequestRevision: UInt64
    let explicitUserAction: Bool
    let requestedAt: Date
    let requestSHA256: String

    init(requestID: UUID, workspaceID: WorkspaceID, target: AssistanceTargetV1,
         scratchSource: AssistanceSourceReferenceV1, localeIdentifier: String,
         recognitionRequestRevision:UInt64,explicitUserAction: Bool, requestedAt: Date) throws {
        try AssistanceLimitsV1.id(requestID); try target.validate(); try scratchSource.validate()
        try AssistanceLimitsV1.token(localeIdentifier); try AssistanceLimitsV1.instant(requestedAt)
        guard target.workspaceID == workspaceID, scratchSource.kind == .leasedScratch,
              recognitionRequestRevision > 0,
              explicitUserAction else { throw DictationLocationProposalFailureV1.invalidValue }
        self.requestID=requestID;self.workspaceID=workspaceID;self.target=target
        self.scratchSource=scratchSource;self.localeIdentifier=localeIdentifier
        self.recognitionRequestRevision=recognitionRequestRevision
        self.explicitUserAction=explicitUserAction;self.requestedAt=requestedAt
        requestSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(requestID:requestID,
            workspaceID:workspaceID,target:target,scratchSource:scratchSource,
            localeIdentifier:localeIdentifier,recognitionRequestRevision:recognitionRequestRevision,
            explicitUserAction:explicitUserAction,
            requestedAt:requestedAt))
    }

    func validate() throws {
        guard self == (try Self(requestID:requestID,workspaceID:workspaceID,target:target,
            scratchSource:scratchSource,localeIdentifier:localeIdentifier,
            recognitionRequestRevision:recognitionRequestRevision,
            explicitUserAction:explicitUserAction,requestedAt:requestedAt)) else {
            throw DictationLocationProposalFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable { let requestID:UUID;let workspaceID:WorkspaceID;let target:AssistanceTargetV1;let scratchSource:AssistanceSourceReferenceV1;let localeIdentifier:String;let recognitionRequestRevision:UInt64;let explicitUserAction:Bool;let requestedAt:Date }
}

struct OnDeviceDictationProposalV1: Codable, Equatable, Sendable {
    let request: OnDeviceDictationRequestV1
    let permission: SpeechPermissionDispositionV1
    let providerVersion: String
    let transcriptRevision:UInt64
    let audioRevision:UInt64
    let transcript: String
    let maximumTranscriptUTF8Bytes:Int
    let proposal: AssistanceProposalV1
    let processedOnDevice: Bool
    let networkAccessUsed: Bool
    let temporaryAudioRetained: Bool
    let proposalEvidenceSHA256: String

    init(request: OnDeviceDictationRequestV1, permission:SpeechPermissionDispositionV1,
         providerVersion: String,
         transcriptRevision:UInt64,audioRevision:UInt64,
         transcript: String, proposal: AssistanceProposalV1,
         maximumTranscriptUTF8Bytes: Int) throws {
        try request.validate();try AssistanceLimitsV1.token(providerVersion);try proposal.validate()
        guard permission.permitsOnDeviceDictation,permission.observedAt>=request.requestedAt,
              permission.observedAt<=proposal.createdAt,
              transcriptRevision > 0,audioRevision == request.scratchSource.revision,
              !transcript.isEmpty,
              transcript == transcript.trimmingCharacters(in: .whitespacesAndNewlines),
              transcript.utf8.count <= maximumTranscriptUTF8Bytes,
              proposal.proposalID == request.requestID,
              proposal.capability.capabilityID == "DICTATION_FIELD_PROPOSAL",
              proposal.capability.localeIdentifier == request.localeIdentifier,
              proposal.target == request.target, proposal.source == request.scratchSource,
              proposal.value == .text(transcript),
              proposal.privacyClass == .sensitiveWorkData else {
            throw DictationLocationProposalFailureV1.invalidValue
        }
        self.request=request;self.permission=permission;self.providerVersion=providerVersion
        self.transcriptRevision=transcriptRevision;self.audioRevision=audioRevision;self.transcript=transcript
        self.maximumTranscriptUTF8Bytes=maximumTranscriptUTF8Bytes
        self.proposal=proposal;processedOnDevice=true;networkAccessUsed=false
        temporaryAudioRetained=false
        proposalEvidenceSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(
            request:request,permission:permission,providerVersion:providerVersion,
            transcriptRevision:transcriptRevision,audioRevision:audioRevision,transcript:transcript,
            proposal:proposal,maximumTranscriptUTF8Bytes:maximumTranscriptUTF8Bytes,
            processedOnDevice:true,networkAccessUsed:false,temporaryAudioRetained:false))
    }

    func validate(policy: DictationLocationCapabilityPolicyV1) throws {
        try validateIntrinsic();try policy.validate()
        guard maximumTranscriptUTF8Bytes==policy.maximumTranscriptUTF8Bytes,
              policy.dictationActivation == .enabledOnDevice,
              policy.supportedDictationLocales.contains(request.localeIdentifier) else {
            throw DictationLocationProposalFailureV1.invalidDigest
        }
    }
    func validateIntrinsic()throws{
        guard self == (try Self(request:request,permission:permission,providerVersion:providerVersion,
            transcriptRevision:transcriptRevision,audioRevision:audioRevision,
            transcript:transcript,proposal:proposal,
            maximumTranscriptUTF8Bytes:maximumTranscriptUTF8Bytes)) else {
            throw DictationLocationProposalFailureV1.invalidDigest
        }
    }

    private struct Basis: Codable { let request:OnDeviceDictationRequestV1;let permission:SpeechPermissionDispositionV1;let providerVersion:String;let transcriptRevision:UInt64;let audioRevision:UInt64;let transcript:String;let proposal:AssistanceProposalV1;let maximumTranscriptUTF8Bytes:Int;let processedOnDevice:Bool;let networkAccessUsed:Bool;let temporaryAudioRetained:Bool }
}

enum OneShotLocationSourceV1: String, Codable, Hashable, Sendable {
    case coreLocationWhenInUse = "CORE_LOCATION_WHEN_IN_USE"
    case locationButton = "LOCATION_BUTTON"
}

enum LocationAccuracyAuthorizationV1: String, Codable, Hashable, Sendable {
    case reduced = "REDUCED"
    case full = "FULL"
}

struct OneShotLocationObservationV1: Codable, Equatable, Hashable, Sendable {
    let latitudeMicrodegrees: Int32
    let longitudeMicrodegrees: Int32
    let observedAt: Date
    let horizontalAccuracyMillimeters: UInt64
    let verticalAccuracyMillimeters: UInt64?
    let source: OneShotLocationSourceV1
    let accuracyAuthorization: LocationAccuracyAuthorizationV1

    init(latitudeMicrodegrees:Int32,longitudeMicrodegrees:Int32,observedAt:Date,
         horizontalAccuracyMillimeters:UInt64,verticalAccuracyMillimeters:UInt64?,
         source:OneShotLocationSourceV1,accuracyAuthorization:LocationAccuracyAuthorizationV1)throws{
        try AssistanceLimitsV1.instant(observedAt)
        guard (-90_000_000...90_000_000).contains(latitudeMicrodegrees),
              (-180_000_000...180_000_000).contains(longitudeMicrodegrees),
              horizontalAccuracyMillimeters > 0,
              verticalAccuracyMillimeters.map({$0 > 0}) ?? true else {
            throw DictationLocationProposalFailureV1.invalidValue
        }
        self.latitudeMicrodegrees=latitudeMicrodegrees;self.longitudeMicrodegrees=longitudeMicrodegrees
        self.observedAt=observedAt;self.horizontalAccuracyMillimeters=horizontalAccuracyMillimeters
        self.verticalAccuracyMillimeters=verticalAccuracyMillimeters;self.source=source
        self.accuracyAuthorization=accuracyAuthorization
    }
}

struct OneShotLocationRequestV1: Codable, Equatable, Sendable {
    let requestID:UUID;let workspaceID:WorkspaceID;let target:AssistanceTargetV1
    let source:AssistanceSourceReferenceV1;let foreground:Bool;let explicitUserAction:Bool
    let requestedAt:Date;let requestSHA256:String
    init(requestID:UUID,workspaceID:WorkspaceID,target:AssistanceTargetV1,
         source:AssistanceSourceReferenceV1,foreground:Bool,explicitUserAction:Bool,
         requestedAt:Date)throws{
        try AssistanceLimitsV1.id(requestID);try target.validate();try source.validate();try AssistanceLimitsV1.instant(requestedAt)
        guard target.workspaceID==workspaceID,source.kind == .deviceObservation,
              foreground,explicitUserAction else{throw DictationLocationProposalFailureV1.backgroundUseForbidden}
        self.requestID=requestID;self.workspaceID=workspaceID;self.target=target;self.source=source
        self.foreground=foreground;self.explicitUserAction=explicitUserAction;self.requestedAt=requestedAt
        requestSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(requestID:requestID,workspaceID:workspaceID,target:target,source:source,foreground:foreground,explicitUserAction:explicitUserAction,requestedAt:requestedAt))
    }
    func validate()throws{guard self == (try Self(requestID:requestID,workspaceID:workspaceID,target:target,source:source,foreground:foreground,explicitUserAction:explicitUserAction,requestedAt:requestedAt))else{throw DictationLocationProposalFailureV1.invalidDigest}}
    private struct Basis:Codable{let requestID:UUID;let workspaceID:WorkspaceID;let target:AssistanceTargetV1;let source:AssistanceSourceReferenceV1;let foreground:Bool;let explicitUserAction:Bool;let requestedAt:Date}
}

struct OneShotLocationProposalV1: Codable, Equatable, Sendable {
    let request:OneShotLocationRequestV1
    let permission:LocationPermissionDispositionV1
    let observation:OneShotLocationObservationV1
    let manualEquivalentValue:ResponseValueV1
    let proposal:AssistanceProposalV1
    let maximumHorizontalAccuracyMillimeters:UInt64
    let proposalEvidenceSHA256:String
    init(request:OneShotLocationRequestV1,permission:LocationPermissionDispositionV1,
         observation:OneShotLocationObservationV1,
         manualEquivalentValue:ResponseValueV1,proposal:AssistanceProposalV1,
         maximumHorizontalAccuracyMillimeters:UInt64)throws{
        try request.validate();try manualEquivalentValue.validate();try proposal.validate()
        guard permission.permitsOneShotForegroundLocation,permission.observedAt>=request.requestedAt,
              permission.observedAt<=observation.observedAt,
              observation.observedAt>=request.requestedAt,
              observation.horizontalAccuracyMillimeters<=maximumHorizontalAccuracyMillimeters,
              proposal.proposalID==request.requestID,
              proposal.capability.capabilityID=="ONE_SHOT_LOCATION_PROPOSAL",
              proposal.target==request.target,proposal.source==request.source,
              proposal.value==manualEquivalentValue,
              proposal.privacyClass == .preciseLocation else{throw DictationLocationProposalFailureV1.invalidValue}
        self.request=request;self.permission=permission;self.observation=observation;self.manualEquivalentValue=manualEquivalentValue
        self.proposal=proposal;self.maximumHorizontalAccuracyMillimeters=maximumHorizontalAccuracyMillimeters
        proposalEvidenceSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(request:request,permission:permission,
            observation:observation,manualEquivalentValue:manualEquivalentValue,proposal:proposal,
            maximumHorizontalAccuracyMillimeters:maximumHorizontalAccuracyMillimeters))
    }
    func validate(policy:DictationLocationCapabilityPolicyV1)throws{
        try validateIntrinsic();try policy.validate()
        guard maximumHorizontalAccuracyMillimeters==policy.maximumHorizontalAccuracyMillimeters,
              policy.locationActivation == .enabledOnDevice else{throw DictationLocationProposalFailureV1.invalidDigest}
    }
    func validateIntrinsic()throws{
        guard self == (try Self(request:request,permission:permission,observation:observation,
            manualEquivalentValue:manualEquivalentValue,proposal:proposal,
            maximumHorizontalAccuracyMillimeters:maximumHorizontalAccuracyMillimeters))else{throw DictationLocationProposalFailureV1.invalidDigest}
    }
    private struct Basis:Codable{let request:OneShotLocationRequestV1;let permission:LocationPermissionDispositionV1;let observation:OneShotLocationObservationV1;let manualEquivalentValue:ResponseValueV1;let proposal:AssistanceProposalV1;let maximumHorizontalAccuracyMillimeters:UInt64}
}

enum DictationLocationReviewDispositionV1:String,Codable,Hashable,Sendable{
    case accepted="ACCEPTED",edited="EDITED",rejected="REJECTED"
}

struct DictationLocationProposalReviewV1:Codable,Equatable,Sendable{
    let originalProposalID:UUID;let originalEvidenceSHA256:String
    let disposition:DictationLocationReviewDispositionV1
    let reviewedValue:ResponseValueV1?;let reviewedBy:ActorSnapshotV1;let reviewedAt:Date
    let reviewSHA256:String
    init(originalProposalID:UUID,originalEvidenceSHA256:String,
         originalValue:ResponseValueV1,disposition:DictationLocationReviewDispositionV1,
         reviewedValue:ResponseValueV1?,reviewedBy:ActorSnapshotV1,reviewedAt:Date)throws{
        try AssistanceLimitsV1.id(originalProposalID);try AssistanceLimitsV1.digest(originalEvidenceSHA256)
        try originalValue.validate();try reviewedValue?.validate();try reviewedBy.validate();try AssistanceLimitsV1.instant(reviewedAt)
        guard (disposition == .rejected)==(reviewedValue==nil),
              (disposition != .rejected)==(reviewedValue != nil),
              disposition != .accepted || reviewedValue==originalValue,
              disposition != .edited || reviewedValue != originalValue else{throw DictationLocationProposalFailureV1.invalidValue}
        self.originalProposalID=originalProposalID;self.originalEvidenceSHA256=originalEvidenceSHA256
        self.disposition=disposition;self.reviewedValue=reviewedValue;self.reviewedBy=reviewedBy;self.reviewedAt=reviewedAt
        reviewSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(originalProposalID:originalProposalID,
            originalEvidenceSHA256:originalEvidenceSHA256,originalValue:originalValue,
            disposition:disposition,reviewedValue:reviewedValue,reviewedBy:reviewedBy,reviewedAt:reviewedAt))
    }
    func validate(originalProposalID:UUID,evidenceSHA256:String,originalValue:ResponseValueV1)throws{
        guard self == (try Self(originalProposalID:originalProposalID,
            originalEvidenceSHA256:evidenceSHA256,originalValue:originalValue,
            disposition:disposition,reviewedValue:reviewedValue,reviewedBy:reviewedBy,
            reviewedAt:reviewedAt))else{throw DictationLocationProposalFailureV1.invalidDigest}
    }
    private struct Basis:Codable{let originalProposalID:UUID;let originalEvidenceSHA256:String;let originalValue:ResponseValueV1;let disposition:DictationLocationReviewDispositionV1;let reviewedValue:ResponseValueV1?;let reviewedBy:ActorSnapshotV1;let reviewedAt:Date}
}

/// Pure admission closure used before the canonical writer is invoked. It
/// accepts no lifecycle or writer dependency, so a forged review cannot cause
/// a partial effect before validation fails.
enum DictationLocationReviewedAcceptanceV1{
    static func validate(dictation:OnDeviceDictationProposalV1,
        review:DictationLocationProposalReviewV1,acceptedProposal:AssistanceProposalV1,
        targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        context:AssistanceProposalEvaluationContextV1)throws{
        try dictation.validateIntrinsic()
        guard dictation.permission.permitsOnDeviceDictation else{throw DictationLocationProposalFailureV1.permissionDenied}
        try validate(original:dictation.proposal,evidenceSHA256:dictation.proposalEvidenceSHA256,
            review:review,acceptedProposal:acceptedProposal,targetMutation:targetMutation,
            expectedRevision:expectedRevision,mutationID:mutationID,context:context)
    }
    static func validate(location:OneShotLocationProposalV1,
        review:DictationLocationProposalReviewV1,acceptedProposal:AssistanceProposalV1,
        targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        context:AssistanceProposalEvaluationContextV1)throws{
        try location.validateIntrinsic()
        guard location.permission.permitsOneShotForegroundLocation else{throw DictationLocationProposalFailureV1.permissionDenied}
        try validate(original:location.proposal,evidenceSHA256:location.proposalEvidenceSHA256,
            review:review,acceptedProposal:acceptedProposal,targetMutation:targetMutation,
            expectedRevision:expectedRevision,mutationID:mutationID,context:context)
    }
    private static func validate(original:AssistanceProposalV1,evidenceSHA256:String,
        review:DictationLocationProposalReviewV1,acceptedProposal:AssistanceProposalV1,
        targetMutation:AssistanceCanonicalTargetMutationV1,
        expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
        context:AssistanceProposalEvaluationContextV1)throws{
        try original.validate();try acceptedProposal.validate();try context.validate()
        try review.validate(originalProposalID:original.proposalID,
            evidenceSHA256:evidenceSHA256,originalValue:original.value)
        let identityAndValueMatch:Bool
        switch review.disposition{
        case .accepted:
            identityAndValueMatch = acceptedProposal==original && review.reviewedValue==original.value
        case .edited:
            identityAndValueMatch = acceptedProposal.proposalID != original.proposalID
                && acceptedProposal.value==review.reviewedValue
                && acceptedProposal.createdAt==review.reviewedAt
        case .rejected:
            identityAndValueMatch=false
        }
        guard identityAndValueMatch,review.reviewedBy.workspaceID==original.target.workspaceID,
              review.reviewedAt>=original.createdAt,review.reviewedAt<original.expiresAt,
              acceptedProposal.capability==original.capability,
              acceptedProposal.target==original.target,acceptedProposal.source==original.source,
              acceptedProposal.privacyClass==original.privacyClass,
              acceptedProposal.expiresAt==original.expiresAt,
              expectedRevision.workspaceID==original.target.workspaceID,
              expectedRevision.entityRevisions.contains(where:{
                  $0.identity==original.target.entity && $0.revision==original.target.revision
              }),targetMutation.workspaceID==original.target.workspaceID,
              targetMutation.mutationID==mutationID,
              context.workspaceID==original.target.workspaceID,
              context.targetRevision==original.target.revision,
              context.currentSource==original.source,
              try acceptedProposal.expiryReason(in:context)==nil else{
            throw DictationLocationProposalFailureV1.staleTarget
        }
        try targetMutation.validate(proposal:acceptedProposal,expectedRevision:expectedRevision,
            mutationID:mutationID,acceptedBy:review.reviewedBy,acceptedAt:review.reviewedAt)
    }
}

enum DictationManualFallbackV1:String,Codable,CaseIterable,Hashable,Sendable{
    case keyboard="KEYBOARD",paste="PASTE"
}
enum LocationManualFallbackV1:String,Codable,CaseIterable,Hashable,Sendable{
    case address="MANUAL_ADDRESS",coordinates="MANUAL_COORDINATES",planPin="PLAN_PIN"
}

enum DictationLocationProposalOutcomeV1: Equatable, Sendable {
    case manualDictation([DictationManualFallbackV1])
    case manualLocation([LocationManualFallbackV1])
    case dictation(OnDeviceDictationProposalV1)
    case location(OneShotLocationProposalV1)
}

protocol SpeechCapabilityAdapterV1: Sendable {
    func permissionDisposition() async throws -> SpeechPermissionDispositionV1
    func requestMicrophonePermission() async throws -> SpeechPermissionDispositionV1
    func requestSpeechRecognitionPermission() async throws -> SpeechPermissionDispositionV1
    func dictateOnDevice(_ request:OnDeviceDictationRequestV1)async throws->OnDeviceDictationProposalV1
}

protocol OneShotLocationCapabilityAdapterV1: Sendable {
    func permissionDisposition() async throws -> LocationPermissionDispositionV1
    func requestWhenInUsePermission() async throws -> LocationPermissionDispositionV1
    func requestOneShotForegroundLocation(_ request:OneShotLocationRequestV1)async throws->OneShotLocationProposalV1
}

@MainActor protocol DictationAudioScratchLifecycleV1: AnyObject {
    func prepare(_ request:OnDeviceDictationRequestV1)async throws
    func discardAfterFailedDictation(_ request:OnDeviceDictationRequestV1)async throws
}

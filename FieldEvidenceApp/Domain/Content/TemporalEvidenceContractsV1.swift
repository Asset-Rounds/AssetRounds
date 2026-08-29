import Foundation
enum TemporalEvidenceValidationV1 { static let zeroUUID=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) }

enum TemporalEvidenceContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case wrongWorkspace
    case staleSource
    case limitExceeded
    case insufficientStorage
    case unsupportedMedia
    case immutableOriginal
    case invalidDerivative
    case invalidTransition
    case digestMismatch
    case interruption
}

enum TemporalEvidenceMediaKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case audio = "AUDIO"
    case video = "VIDEO"
}

struct TemporalEvidenceCodecV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let container: String
    let codec: String
    let mediaType: String

    init(container: String, codec: String, mediaType: String) throws {
        guard Self.token(container), Self.token(codec), ContentContractValidationV1.validMediaType(mediaType) else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        self.container = container
        self.codec = codec
        self.mediaType = mediaType
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableKey < rhs.stableKey }
    var stableKey: String { "\(container)|\(codec)|\(mediaType)" }
    private static func token(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TemporalEvidenceReportProjectionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case typedLinkOnly = "TYPED_LINK_ONLY"
    case typedLinkWithDerivativePreview = "TYPED_LINK_WITH_DERIVATIVE_PREVIEW"
}

enum TemporalEvidenceStopReasonV1:String,Codable,CaseIterable,Hashable,Sendable{case durationBound="DURATION_BOUND";case byteBound="BYTE_BOUND";case requirementCountBound="REQUIREMENT_COUNT_BOUND";case sessionCountBound="SESSION_COUNT_BOUND";case insufficientStorage="INSUFFICIENT_STORAGE";case codecUnavailable="CODEC_UNAVAILABLE";case permissionDenied="PERMISSION_DENIED";case protectedDataUnavailable="PROTECTED_DATA_UNAVAILABLE";case interruption="INTERRUPTION";case backgrounded="BACKGROUNDED";case cancelled="CANCELLED"}

enum TemporalEvidenceReviewDecisionV1:String,Codable,CaseIterable,Hashable,Sendable{case accept="ACCEPT";case reject="REJECT";case cancel="CANCEL"}
struct TemporalEvidenceCaptureReviewV1:Codable,Equatable,Sendable{let reviewID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let decision:TemporalEvidenceReviewDecisionV1;let reviewer:ActorSnapshotV1;let reviewedAt:Date;let reviewSHA256:String
    init(reviewID:UUID,workspaceID:WorkspaceID,clipID:UUID,decision:TemporalEvidenceReviewDecisionV1,reviewer:ActorSnapshotV1,reviewedAt:Date)throws{self.reviewID=reviewID;self.workspaceID=workspaceID;self.clipID=clipID;self.decision=decision;self.reviewer=reviewer;self.reviewedAt=reviewedAt;reviewSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(reviewID:reviewID,workspaceID:workspaceID,clipID:clipID,decision:decision,reviewer:reviewer,reviewedAt:reviewedAt));try validate()}
    func validate()throws{try reviewer.validate();guard reviewID != TemporalEvidenceValidationV1.zeroUUID,clipID != TemporalEvidenceValidationV1.zeroUUID,reviewer.workspaceID==workspaceID,reviewedAt.timeIntervalSinceReferenceDate.isFinite,reviewSHA256==(try WorkspaceMutationCanonicalV1.sha256(Basis(reviewID:reviewID,workspaceID:workspaceID,clipID:clipID,decision:decision,reviewer:reviewer,reviewedAt:reviewedAt))) else{throw TemporalEvidenceContractFailureV1.invalidValue}}
    private struct Basis:Codable{let reviewID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let decision:TemporalEvidenceReviewDecisionV1;let reviewer:ActorSnapshotV1;let reviewedAt:Date}
}

struct TemporalEvidenceMediaLimitV1: Codable, Equatable, Sendable {
    let kind: TemporalEvidenceMediaKindV1
    let maximumDurationMilliseconds: UInt64
    let maximumByteCount: UInt64
    let acceptedCodecs: [TemporalEvidenceCodecV1]
    let maximumPixelWidth: Int?
    let maximumPixelHeight: Int?

    init(kind: TemporalEvidenceMediaKindV1, maximumDurationMilliseconds: UInt64,
         maximumByteCount: UInt64, acceptedCodecs: [TemporalEvidenceCodecV1],
         maximumPixelWidth: Int? = nil, maximumPixelHeight: Int? = nil) throws {
        self.kind = kind
        self.maximumDurationMilliseconds = maximumDurationMilliseconds
        self.maximumByteCount = maximumByteCount
        self.acceptedCodecs = acceptedCodecs.sorted()
        self.maximumPixelWidth = maximumPixelWidth
        self.maximumPixelHeight = maximumPixelHeight
        try validate()
    }

    func validate() throws {
        guard maximumDurationMilliseconds > 0, maximumDurationMilliseconds <= 3_600_000,
              maximumByteCount > 0, maximumByteCount <= 4_294_967_296,
              !acceptedCodecs.isEmpty, acceptedCodecs.count <= 32,
              Set(acceptedCodecs).count == acceptedCodecs.count,
              acceptedCodecs == acceptedCodecs.sorted() else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        switch kind {
        case .audio:
            guard maximumPixelWidth == nil, maximumPixelHeight == nil,acceptedCodecs.allSatisfy({$0.mediaType.hasPrefix("audio/")}) else {
                throw TemporalEvidenceContractFailureV1.invalidValue
            }
        case .video:
            guard let width = maximumPixelWidth, let height = maximumPixelHeight,acceptedCodecs.allSatisfy({$0.mediaType.hasPrefix("video/")}),
                  (1...16_384).contains(width), (1...16_384).contains(height) else {
                throw TemporalEvidenceContractFailureV1.invalidValue
            }
        }
    }
}

struct TemporalEvidenceLimitProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let profileID: UUID
    let revision: UInt64
    let packageRelease: SurveyPackageReleaseReferenceV1
    let definitionRelease: SurveyDefinitionReleaseReferenceV1
    let audio: TemporalEvidenceMediaLimitV1
    let video: TemporalEvidenceMediaLimitV1
    let maximumClipsPerRequirement: Int
    let maximumClipsPerSession: Int
    let minimumFreeByteCount: UInt64
    let reportProjection: TemporalEvidenceReportProjectionV1
    let requiresAccessibleDescription: Bool
    let requiresManualTranscript: Bool
    let profileSHA256: String

    init(profileID: UUID, revision: UInt64, packageRelease: SurveyPackageReleaseReferenceV1,
         definitionRelease: SurveyDefinitionReleaseReferenceV1,
         audio: TemporalEvidenceMediaLimitV1, video: TemporalEvidenceMediaLimitV1,
         maximumClipsPerRequirement: Int, maximumClipsPerSession: Int,
         minimumFreeByteCount: UInt64, reportProjection: TemporalEvidenceReportProjectionV1,
         requiresAccessibleDescription: Bool, requiresManualTranscript: Bool) throws {
        schemaVersion = Self.schemaVersion; self.profileID = profileID; self.revision = revision
        self.packageRelease = packageRelease; self.definitionRelease = definitionRelease
        self.audio = audio; self.video = video
        self.maximumClipsPerRequirement = maximumClipsPerRequirement
        self.maximumClipsPerSession = maximumClipsPerSession
        self.minimumFreeByteCount = minimumFreeByteCount; self.reportProjection = reportProjection
        self.requiresAccessibleDescription = requiresAccessibleDescription
        self.requiresManualTranscript = requiresManualTranscript
        profileSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, profileID: profileID, revision: revision,
            packageRelease: packageRelease, definitionRelease: definitionRelease,
            audio: audio, video: video, maximumClipsPerRequirement: maximumClipsPerRequirement,
            maximumClipsPerSession: maximumClipsPerSession, minimumFreeByteCount: minimumFreeByteCount,
            reportProjection: reportProjection, requiresAccessibleDescription: requiresAccessibleDescription,
            requiresManualTranscript: requiresManualTranscript))
        try validate()
    }

    func validate() throws {
        try packageRelease.validate(); try definitionRelease.validate(); try audio.validate(); try video.validate()
        guard schemaVersion == Self.schemaVersion, profileID != TemporalEvidenceValidationV1.zeroUUID, revision > 0,
              packageRelease.packageID.count > 0, audio.kind == .audio, video.kind == .video,
              (1...64).contains(maximumClipsPerRequirement),
              maximumClipsPerRequirement <= maximumClipsPerSession,
              maximumClipsPerSession <= 512, minimumFreeByteCount > 0,
              profileSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
    func limit(for kind: TemporalEvidenceMediaKindV1) -> TemporalEvidenceMediaLimitV1 { kind == .audio ? audio : video }
    private var basis: Basis { .init(schemaVersion:schemaVersion,profileID:profileID,revision:revision,packageRelease:packageRelease,definitionRelease:definitionRelease,audio:audio,video:video,maximumClipsPerRequirement:maximumClipsPerRequirement,maximumClipsPerSession:maximumClipsPerSession,minimumFreeByteCount:minimumFreeByteCount,reportProjection:reportProjection,requiresAccessibleDescription:requiresAccessibleDescription,requiresManualTranscript:requiresManualTranscript) }
    private struct Basis: Codable { let schemaVersion:Int;let profileID:UUID;let revision:UInt64;let packageRelease:SurveyPackageReleaseReferenceV1;let definitionRelease:SurveyDefinitionReleaseReferenceV1;let audio,video:TemporalEvidenceMediaLimitV1;let maximumClipsPerRequirement,maximumClipsPerSession:Int;let minimumFreeByteCount:UInt64;let reportProjection:TemporalEvidenceReportProjectionV1;let requiresAccessibleDescription,requiresManualTranscript:Bool }
}

extension TemporalEvidenceLimitProfileV1{
    func rebound(packageRelease:SurveyPackageReleaseReferenceV1,definitionRelease:SurveyDefinitionReleaseReferenceV1,revision:UInt64)throws->Self{guard revision>self.revision else{throw TemporalEvidenceContractFailureV1.invalidTransition};return try .init(profileID:profileID,revision:revision,packageRelease:packageRelease,definitionRelease:definitionRelease,audio:audio,video:video,maximumClipsPerRequirement:maximumClipsPerRequirement,maximumClipsPerSession:maximumClipsPerSession,minimumFreeByteCount:minimumFreeByteCount,reportProjection:reportProjection,requiresAccessibleDescription:requiresAccessibleDescription,requiresManualTranscript:requiresManualTranscript)}
}

struct TemporalEvidenceTargetV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let sessionID: UUID
    let sessionRevision: UInt64
    let sessionSHA256: String
    let definitionRelease: SurveyDefinitionReleaseReferenceV1
    let factID: String
    let repeatCoordinates: [SurveyRepeatCoordinateV1]

    init(workspaceID:WorkspaceID,sessionID:UUID,sessionRevision:UInt64,sessionSHA256:String,
         definitionRelease:SurveyDefinitionReleaseReferenceV1,factID:String,
         repeatCoordinates:[SurveyRepeatCoordinateV1]=[]) throws {
        self.workspaceID=workspaceID;self.sessionID=sessionID;self.sessionRevision=sessionRevision
        self.sessionSHA256=sessionSHA256;self.definitionRelease=definitionRelease;self.factID=factID
        self.repeatCoordinates=repeatCoordinates.sorted();try validate()
    }
    func validate()throws{try definitionRelease.validate();try repeatCoordinates.forEach{$0.validate()};guard sessionID != TemporalEvidenceValidationV1.zeroUUID,sessionRevision>0,MutationEnvelopeV1.isSHA256(sessionSHA256),SurveyDefinitionLimitsV1.token(factID),repeatCoordinates==repeatCoordinates.sorted(),Set(repeatCoordinates).count==repeatCoordinates.count else{throw TemporalEvidenceContractFailureV1.invalidValue}}
}

struct TemporalEvidenceMediaFactsV1: Codable, Equatable, Sendable {
    let kind: TemporalEvidenceMediaKindV1
    let durationMilliseconds: UInt64
    let byteCount: UInt64
    let codec: TemporalEvidenceCodecV1
    let pixelWidth: Int?
    let pixelHeight: Int?
    init(kind:TemporalEvidenceMediaKindV1,durationMilliseconds:UInt64,byteCount:UInt64,codec:TemporalEvidenceCodecV1,pixelWidth:Int?=nil,pixelHeight:Int?=nil)throws{self.kind=kind;self.durationMilliseconds=durationMilliseconds;self.byteCount=byteCount;self.codec=codec;self.pixelWidth=pixelWidth;self.pixelHeight=pixelHeight;try validate()}
    func validate()throws{guard durationMilliseconds>0,byteCount>0 else{throw TemporalEvidenceContractFailureV1.invalidValue};switch kind{case .audio:guard pixelWidth==nil&&pixelHeight==nil&&codec.mediaType.hasPrefix("audio/") else{throw TemporalEvidenceContractFailureV1.invalidValue};case .video:guard let w=pixelWidth,let h=pixelHeight,w>0,h>0,codec.mediaType.hasPrefix("video/") else{throw TemporalEvidenceContractFailureV1.invalidValue}}}
    func validate(against limit:TemporalEvidenceMediaLimitV1)throws{try validate();try limit.validate();guard kind==limit.kind,durationMilliseconds<=limit.maximumDurationMilliseconds,byteCount<=limit.maximumByteCount,limit.acceptedCodecs.contains(codec),(pixelWidth.map{$0 <= (limit.maximumPixelWidth ?? 0)} ?? true),(pixelHeight.map{$0 <= (limit.maximumPixelHeight ?? 0)} ?? true)else{throw TemporalEvidenceContractFailureV1.limitExceeded}}
}

struct TemporalEvidenceIncrementalAdmissionReceiptV1:Codable,Equatable,Sendable{let profileSHA256:String;let kind:TemporalEvidenceMediaKindV1;let codec:TemporalEvidenceCodecV1;let pixelWidth:Int?;let pixelHeight:Int?;let observedDurationMilliseconds:UInt64;let observedByteCount:UInt64;let remainingDurationMilliseconds:UInt64;let remainingByteCount:UInt64;let sequence:UInt64;let captureCompleted:Bool;let terminalStopReason:TemporalEvidenceStopReasonV1?
    init(profile:TemporalEvidenceLimitProfileV1,kind:TemporalEvidenceMediaKindV1,codec:TemporalEvidenceCodecV1,pixelWidth:Int?=nil,pixelHeight:Int?=nil,observedDurationMilliseconds:UInt64,observedByteCount:UInt64,sequence:UInt64,captureCompleted:Bool=false,prior:Self?=nil)throws{let limit=profile.limit(for:kind);try limit.validate();let hitDuration=observedDurationMilliseconds>=limit.maximumDurationMilliseconds,hitBytes=observedByteCount>=limit.maximumByteCount,resolutionValid=kind == .audio ? (pixelWidth==nil&&pixelHeight==nil) : (pixelWidth.map{$0>0&&$0<=(limit.maximumPixelWidth ?? 0)} ?? false)&&(pixelHeight.map{$0>0&&$0<=(limit.maximumPixelHeight ?? 0)} ?? false);guard resolutionValid,limit.acceptedCodecs.contains(codec),sequence>0,(!hitDuration && !hitBytes)||captureCompleted,prior.map({$0.profileSHA256==profile.profileSHA256&&$0.kind==kind&&$0.codec==codec&&$0.pixelWidth==pixelWidth&&$0.pixelHeight==pixelHeight&&$0.sequence+1==sequence&&observedDurationMilliseconds >= $0.observedDurationMilliseconds&&observedByteCount >= $0.observedByteCount&&!$0.captureCompleted&&$0.terminalStopReason==nil}) ?? (sequence==1)else{throw TemporalEvidenceContractFailureV1.invalidTransition};profileSHA256=profile.profileSHA256;self.kind=kind;self.codec=codec;self.pixelWidth=pixelWidth;self.pixelHeight=pixelHeight;self.observedDurationMilliseconds=min(observedDurationMilliseconds,limit.maximumDurationMilliseconds);self.observedByteCount=min(observedByteCount,limit.maximumByteCount);remainingDurationMilliseconds=limit.maximumDurationMilliseconds-self.observedDurationMilliseconds;remainingByteCount=limit.maximumByteCount-self.observedByteCount;self.sequence=sequence;self.captureCompleted=captureCompleted;if hitDuration{terminalStopReason = .durationBound}else if hitBytes{terminalStopReason = .byteBound}else{terminalStopReason=nil};try validate(profile:profile)}
    func validate(profile:TemporalEvidenceLimitProfileV1)throws{let limit=profile.limit(for:kind),resolutionValid=kind == .audio ? (pixelWidth==nil&&pixelHeight==nil) : (pixelWidth.map{$0>0&&$0<=(limit.maximumPixelWidth ?? 0)} ?? false)&&(pixelHeight.map{$0>0&&$0<=(limit.maximumPixelHeight ?? 0)} ?? false);guard resolutionValid,profileSHA256==profile.profileSHA256,limit.acceptedCodecs.contains(codec),sequence>0,observedDurationMilliseconds<=limit.maximumDurationMilliseconds,observedByteCount<=limit.maximumByteCount,remainingDurationMilliseconds==limit.maximumDurationMilliseconds-observedDurationMilliseconds,remainingByteCount==limit.maximumByteCount-observedByteCount,(terminalStopReason==nil)||(captureCompleted&&terminalStopReason == .durationBound&&remainingDurationMilliseconds==0)||(captureCompleted&&terminalStopReason == .byteBound&&remainingByteCount==0)else{throw TemporalEvidenceContractFailureV1.limitExceeded}}
    func validateTerminal(facts:TemporalEvidenceMediaFactsV1,profile:TemporalEvidenceLimitProfileV1)throws{try validate(profile:profile);try facts.validate(against:profile.limit(for:kind));guard captureCompleted,facts.kind==kind,facts.codec==codec,facts.pixelWidth==pixelWidth,facts.pixelHeight==pixelHeight,facts.durationMilliseconds==observedDurationMilliseconds,facts.byteCount==observedByteCount else{throw TemporalEvidenceContractFailureV1.staleSource}}
}

struct TemporalEvidenceDerivativeReferenceV1:Codable,Equatable,Hashable,Comparable,Sendable{let derivativeID:UUID;let revision:UInt64;let derivativeSHA256:String;let kind:TemporalEvidenceDerivativeKindV1;static func <(l:Self,r:Self)->Bool{l.derivativeID.uuidString<r.derivativeID.uuidString};func validate()throws{guard derivativeID != TemporalEvidenceValidationV1.zeroUUID,revision>0,MutationEnvelopeV1.isSHA256(derivativeSHA256)else{throw TemporalEvidenceContractFailureV1.invalidValue}}}
struct TemporalEvidenceRetentionReferenceV1:Codable,Equatable,Hashable,Sendable{let eventID:UUID;let revision:UInt64;let eventSHA256:String;let disposition:TemporalEvidenceRetentionDispositionV1;func validate()throws{guard eventID != TemporalEvidenceValidationV1.zeroUUID,revision>0,MutationEnvelopeV1.isSHA256(eventSHA256)else{throw TemporalEvidenceContractFailureV1.invalidValue}}}

struct TemporalEvidenceClipV1: Codable, Equatable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let clipID:UUID;let workspaceID:WorkspaceID;let target:TemporalEvidenceTargetV1
    let original:ContentReferenceV1;let originalProvenance:ContentOriginalProvenanceV1;let locator:ContentLocatorV1
    let facts:TemporalEvidenceMediaFactsV1;let limitProfile:TemporalEvidenceLimitProfileV1
    let accessibleDescription:String;let manualTranscript:String?;let recordedBy:ActorSnapshotV1;let capturedAt:Date;let acceptedAt:Date
    let derivativeReferences:[TemporalEvidenceDerivativeReferenceV1];let retentionReference:TemporalEvidenceRetentionReferenceV1?
    let supersedesClipID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let clipSHA256:String
    init(clipID:UUID,workspaceID:WorkspaceID,target:TemporalEvidenceTargetV1,original:ContentReferenceV1,originalProvenance:ContentOriginalProvenanceV1,locator:ContentLocatorV1,facts:TemporalEvidenceMediaFactsV1,profile:TemporalEvidenceLimitProfileV1,accessibleDescription:String,manualTranscript:String?=nil,derivativeReferences:[TemporalEvidenceDerivativeReferenceV1]=[],retentionReference:TemporalEvidenceRetentionReferenceV1?=nil,recordedBy:ActorSnapshotV1,capturedAt:Date,acceptedAt:Date,supersedesClipID:UUID?=nil,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.clipID=clipID;self.workspaceID=workspaceID;self.target=target;self.original=original;self.originalProvenance=originalProvenance;self.locator=locator;self.facts=facts;limitProfile=profile;self.accessibleDescription=accessibleDescription;self.manualTranscript=manualTranscript;self.derivativeReferences=derivativeReferences.sorted();self.retentionReference=retentionReference;self.recordedBy=recordedBy;self.capturedAt=capturedAt;self.acceptedAt=acceptedAt;self.supersedesClipID=supersedesClipID;self.revision=revision;self.mutationID=mutationID;clipSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,clipID:clipID,workspaceID:workspaceID,target:target,original:original,originalProvenance:originalProvenance,locator:locator,facts:facts,limitProfile:profile,accessibleDescription:accessibleDescription,manualTranscript:manualTranscript,derivativeReferences:self.derivativeReferences,retentionReference:retentionReference,recordedBy:recordedBy,capturedAt:capturedAt,acceptedAt:acceptedAt,supersedesClipID:supersedesClipID,revision:revision,mutationID:mutationID));try validate(profile:profile)}
    var limitProfileID:UUID{limitProfile.profileID};var limitProfileRevision:UInt64{limitProfile.revision};var limitProfileSHA256:String{limitProfile.profileSHA256}
    func validate(profile:TemporalEvidenceLimitProfileV1)throws{try validateIntrinsic();guard limitProfile==profile else{throw TemporalEvidenceContractFailureV1.staleSource}}
    func validateIntrinsic()throws{try target.validate();try facts.validate();try limitProfile.validate();try facts.validate(against:limitProfile.limit(for:facts.kind));try originalProvenance.validateTemporalEvidence(original:original);try locator.validate(against:original);try derivativeReferences.forEach{$0.validate()};try retentionReference?.validate();try recordedBy.validate();let ws=workspaceID.rawValue.uuidString.lowercased();guard schemaVersion==Self.schemaVersion,clipID != TemporalEvidenceValidationV1.zeroUUID,target.workspaceID==workspaceID,target.definitionRelease==limitProfile.definitionRelease,!limitProfile.requiresAccessibleDescription||!accessibleDescription.isEmpty,!limitProfile.requiresManualTranscript||(manualTranscript?.isEmpty==false),original.workspaceID==ws,original.byteRole == .immutableOriginal,original.byteLength==Int64(facts.byteCount),original.mediaType==facts.codec.mediaType,original.digests.digest(for:.sha256) != nil,originalProvenance.workspaceID==ws,originalProvenance.contentID==original.contentID,locator.workspaceID==ws,derivativeReferences==derivativeReferences.sorted(),Set(derivativeReferences.map(\.derivativeID)).count==derivativeReferences.count,recordedBy.workspaceID==workspaceID,capturedAt.timeIntervalSinceReferenceDate.isFinite,acceptedAt.timeIntervalSinceReferenceDate.isFinite,acceptedAt>=capturedAt,accessibleDescription.utf8.count<=4096,(manualTranscript?.utf8.count ?? 0)<=65_536,revision>0,(revision==1)==(supersedesClipID==nil),supersedesClipID != clipID,clipSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw TemporalEvidenceContractFailureV1.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,clipID:clipID,workspaceID:workspaceID,target:target,original:original,originalProvenance:originalProvenance,locator:locator,facts:facts,limitProfile:limitProfile,accessibleDescription:accessibleDescription,manualTranscript:manualTranscript,derivativeReferences:derivativeReferences,retentionReference:retentionReference,recordedBy:recordedBy,capturedAt:capturedAt,acceptedAt:acceptedAt,supersedesClipID:supersedesClipID,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let clipID:UUID;let workspaceID:WorkspaceID;let target:TemporalEvidenceTargetV1;let original:ContentReferenceV1;let originalProvenance:ContentOriginalProvenanceV1;let locator:ContentLocatorV1;let facts:TemporalEvidenceMediaFactsV1;let limitProfile:TemporalEvidenceLimitProfileV1;let accessibleDescription:String;let manualTranscript:String?;let derivativeReferences:[TemporalEvidenceDerivativeReferenceV1];let retentionReference:TemporalEvidenceRetentionReferenceV1?;let recordedBy:ActorSnapshotV1;let capturedAt,acceptedAt:Date;let supersedesClipID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

extension ContentOriginalProvenanceV1 { fileprivate func validateTemporalEvidence(original:ContentReferenceV1)throws{guard workspaceID==original.workspaceID,contentID==original.contentID,original.digests.digest(for:contentDigest.algorithm)==contentDigest else{throw TemporalEvidenceContractFailureV1.digestMismatch}} }

struct TimecodedEvidenceAnchorV1: Codable, Equatable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let anchorID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let clipRevision:UInt64;let clipSHA256:String;let sourceContentID:String;let sourceSHA256:String;let offsetMilliseconds:UInt64;let label:String;let note:String?;let author:ActorSnapshotV1;let recordedAt:Date;let supersedesAnchorID:UUID?;let predecessorAnchorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let anchorSHA256:String
    init(anchorID:UUID,clip:TemporalEvidenceClipV1,offsetMilliseconds:UInt64,label:String,note:String?=nil,author:ActorSnapshotV1,recordedAt:Date,supersedesAnchorID:UUID?=nil,predecessorAnchorSHA256:String?=nil,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.anchorID=anchorID;workspaceID=clip.workspaceID;clipID=clip.clipID;clipRevision=clip.revision;clipSHA256=clip.clipSHA256;sourceContentID=clip.original.contentID;guard let digest=clip.original.digests.digest(for:.sha256)?.hexadecimalValue else{throw TemporalEvidenceContractFailureV1.digestMismatch};sourceSHA256=digest;self.offsetMilliseconds=offsetMilliseconds;self.label=label;self.note=note;self.author=author;self.recordedAt=recordedAt;self.supersedesAnchorID=supersedesAnchorID;self.predecessorAnchorSHA256=predecessorAnchorSHA256;self.revision=revision;self.mutationID=mutationID;anchorSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,anchorID:anchorID,workspaceID:clip.workspaceID,clipID:clip.clipID,clipRevision:clip.revision,clipSHA256:clip.clipSHA256,sourceContentID:clip.original.contentID,sourceSHA256:digest,offsetMilliseconds:offsetMilliseconds,label:label,note:note,author:author,recordedAt:recordedAt,supersedesAnchorID:supersedesAnchorID,predecessorAnchorSHA256:predecessorAnchorSHA256,revision:revision,mutationID:mutationID));try validate(clip:clip)}
    func validate(clip:TemporalEvidenceClipV1)throws{try clip.validateIntrinsic();try validateIntrinsic();guard workspaceID==clip.workspaceID,clipID==clip.clipID,clipRevision==clip.revision,clipSHA256==clip.clipSHA256,sourceContentID==clip.original.contentID,sourceSHA256==clip.original.digests.digest(for:.sha256)?.hexadecimalValue,offsetMilliseconds<=clip.facts.durationMilliseconds else{throw TemporalEvidenceContractFailureV1.staleSource}}
    func validateIntrinsic()throws{try author.validate();guard schemaVersion==Self.schemaVersion,anchorID != TemporalEvidenceValidationV1.zeroUUID,clipID != TemporalEvidenceValidationV1.zeroUUID,clipRevision>0,MutationEnvelopeV1.isSHA256(clipSHA256),ContentContractValidationV1.validID(sourceContentID),MutationEnvelopeV1.isSHA256(sourceSHA256),!label.isEmpty,label.utf8.count<=256,(note?.utf8.count ?? 0)<=4096,author.workspaceID==workspaceID,recordedAt.timeIntervalSinceReferenceDate.isFinite,revision>0,(revision==1)==(supersedesAnchorID==nil&&predecessorAnchorSHA256==nil),(revision>1)==(supersedesAnchorID != nil&&predecessorAnchorSHA256 != nil),supersedesAnchorID != anchorID,predecessorAnchorSHA256.map(MutationEnvelopeV1.isSHA256) ?? true,anchorSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw TemporalEvidenceContractFailureV1.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,anchorID:anchorID,workspaceID:workspaceID,clipID:clipID,clipRevision:clipRevision,clipSHA256:clipSHA256,sourceContentID:sourceContentID,sourceSHA256:sourceSHA256,offsetMilliseconds:offsetMilliseconds,label:label,note:note,author:author,recordedAt:recordedAt,supersedesAnchorID:supersedesAnchorID,predecessorAnchorSHA256:predecessorAnchorSHA256,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let anchorID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let clipRevision:UInt64;let clipSHA256,sourceContentID,sourceSHA256:String;let offsetMilliseconds:UInt64;let label:String;let note:String?;let author:ActorSnapshotV1;let recordedAt:Date;let supersedesAnchorID:UUID?;let predecessorAnchorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1}
}

enum TemporalEvidenceDerivativeKindV1:String,Codable,CaseIterable,Hashable,Sendable{case thumbnail="THUMBNAIL";case waveform="WAVEFORM"}
struct TemporalEvidenceDerivativeV1:Codable,Equatable,Sendable{static let schemaVersion=1;static let maximumThumbnailBytes:Int64=2*1024*1024;static let maximumWaveformBytes:Int64=4*1024*1024;let schemaVersion:Int;let derivativeID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let clipRevision:UInt64;let clipSHA256:String;let source:ContentSourceBindingV1;let content:ContentReferenceV1;let locator:ContentLocatorV1;let kind:TemporalEvidenceDerivativeKindV1;let generatorID:String;let generatorVersion:String;let provenance:ContentDerivativeProvenanceV1;let supersedesDerivativeID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let derivativeSHA256:String
    init(derivativeID:UUID,clip:TemporalEvidenceClipV1,content:ContentReferenceV1,locator:ContentLocatorV1,kind:TemporalEvidenceDerivativeKindV1,generatorID:String,generatorVersion:String,provenance:ContentDerivativeProvenanceV1,supersedesDerivativeID:UUID?=nil,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.derivativeID=derivativeID;workspaceID=clip.workspaceID;clipID=clip.clipID;clipRevision=clip.revision;clipSHA256=clip.clipSHA256;guard let digest=clip.original.digests.digest(for:.sha256)else{throw TemporalEvidenceContractFailureV1.digestMismatch};source=try .init(contentID:clip.original.contentID,digest:digest);self.content=content;self.locator=locator;self.kind=kind;self.generatorID=generatorID;self.generatorVersion=generatorVersion;self.provenance=provenance;self.supersedesDerivativeID=supersedesDerivativeID;self.revision=revision;self.mutationID=mutationID;derivativeSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,derivativeID:derivativeID,workspaceID:clip.workspaceID,clipID:clip.clipID,clipRevision:clip.revision,clipSHA256:clip.clipSHA256,source:source,content:content,locator:locator,kind:kind,generatorID:generatorID,generatorVersion:generatorVersion,provenance:provenance,supersedesDerivativeID:supersedesDerivativeID,revision:revision,mutationID:mutationID));try validate(clip:clip)}
    func validate(clip:TemporalEvidenceClipV1)throws{try validateIntrinsic();guard workspaceID==clip.workspaceID,clipID==clip.clipID,clipRevision==clip.revision,clipSHA256==clip.clipSHA256,source.contentID==clip.original.contentID,clip.original.digests.digest(for:source.digest.algorithm)==source.digest,(kind == .waveform && clip.facts.kind == .audio)||(kind == .thumbnail && clip.facts.kind == .video) else{throw TemporalEvidenceContractFailureV1.staleSource}}
    func validateIntrinsic()throws{try locator.validate(against:content);let checkedSource=try ContentSourceBindingV1(contentID:source.contentID,digest:source.digest),checkedProvenance=try ContentDerivativeProvenanceV1(provenanceID:provenance.provenanceID,workspaceID:provenance.workspaceID,sources:provenance.sources,derivativeContentID:provenance.derivativeContentID,derivativeDigest:provenance.derivativeDigest,transform:provenance.transform,metadataSanitizerID:provenance.metadataSanitizerID,metadataSanitizerVersion:provenance.metadataSanitizerVersion,createdAt:provenance.createdAt);let ws=workspaceID.rawValue.uuidString.lowercased(),digest=content.digests.digest(for:provenance.derivativeDigest.algorithm);guard checkedSource==source,checkedProvenance==provenance,schemaVersion==Self.schemaVersion,derivativeID != TemporalEvidenceValidationV1.zeroUUID,clipID != TemporalEvidenceValidationV1.zeroUUID,clipRevision>0,MutationEnvelopeV1.isSHA256(clipSHA256),content.workspaceID==ws,content.byteRole == .derivative,content.contentID != source.contentID,content.digests.digest(for:.sha256) != nil,locator.workspaceID==ws,ContentContractValidationV1.validID(generatorID),ContentContractValidationV1.validVersion(generatorVersion),provenance.workspaceID==ws,provenance.sources==[source],provenance.derivativeContentID==content.contentID,digest==provenance.derivativeDigest,revision>0,(revision==1)==(supersedesDerivativeID==nil),supersedesDerivativeID != derivativeID,derivativeSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw TemporalEvidenceContractFailureV1.invalidDerivative};switch(kind,provenance.transform){case(.thumbnail,.thumbnail(let value)):guard content.mediaType.lowercased().hasPrefix("image/"),content.byteLength<=Self.maximumThumbnailBytes,value.rendererID==generatorID,value.rendererVersion==generatorVersion else{throw TemporalEvidenceContractFailureV1.invalidDerivative};case(.waveform,.waveform(let value)):guard content.mediaType.lowercased().hasPrefix("image/"),content.byteLength<=Self.maximumWaveformBytes,value.rendererID==generatorID,value.rendererVersion==generatorVersion else{throw TemporalEvidenceContractFailureV1.invalidDerivative};default:throw TemporalEvidenceContractFailureV1.invalidDerivative}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,derivativeID:derivativeID,workspaceID:workspaceID,clipID:clipID,clipRevision:clipRevision,clipSHA256:clipSHA256,source:source,content:content,locator:locator,kind:kind,generatorID:generatorID,generatorVersion:generatorVersion,provenance:provenance,supersedesDerivativeID:supersedesDerivativeID,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let derivativeID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let clipRevision:UInt64;let clipSHA256:String;let source:ContentSourceBindingV1;let content:ContentReferenceV1;let locator:ContentLocatorV1;let kind:TemporalEvidenceDerivativeKindV1;let generatorID,generatorVersion:String;let provenance:ContentDerivativeProvenanceV1;let supersedesDerivativeID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}}

enum TemporalEvidenceRetentionDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case retain="RETAIN";case removeRegenerableDerivatives="REMOVE_REGENERABLE_DERIVATIVES";case deleteClip="DELETE_CLIP";case eraseWorkspace="ERASE_WORKSPACE"}
struct TemporalEvidenceRetentionEventV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let clipRevision:UInt64;let clipSHA256:String;let disposition:TemporalEvidenceRetentionDispositionV1;let policySHA256:String;let actor:ActorSnapshotV1;let occurredAt:Date;let supersedesEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,clip:TemporalEvidenceClipV1,disposition:TemporalEvidenceRetentionDispositionV1,policySHA256:String,actor:ActorSnapshotV1,occurredAt:Date,supersedesEventID:UUID?=nil,predecessorEventSHA256:String?=nil,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;workspaceID=clip.workspaceID;clipID=clip.clipID;clipRevision=clip.revision;clipSHA256=clip.clipSHA256;self.disposition=disposition;self.policySHA256=policySHA256;self.actor=actor;self.occurredAt=occurredAt;self.supersedesEventID=supersedesEventID;self.predecessorEventSHA256=predecessorEventSHA256;self.revision=revision;self.mutationID=mutationID;eventSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,eventID:eventID,workspaceID:clip.workspaceID,clipID:clip.clipID,clipRevision:clip.revision,clipSHA256:clip.clipSHA256,disposition:disposition,policySHA256:policySHA256,actor:actor,occurredAt:occurredAt,supersedesEventID:supersedesEventID,predecessorEventSHA256:predecessorEventSHA256,revision:revision,mutationID:mutationID));try validate(clip:clip)}
    func validate(clip:TemporalEvidenceClipV1)throws{try validateIntrinsic();guard workspaceID==clip.workspaceID,clipID==clip.clipID,clipRevision==clip.revision,clipSHA256==clip.clipSHA256 else{throw TemporalEvidenceContractFailureV1.staleSource}}
    func validateIntrinsic()throws{try actor.validate();guard schemaVersion==Self.schemaVersion,eventID != TemporalEvidenceValidationV1.zeroUUID,clipID != TemporalEvidenceValidationV1.zeroUUID,clipRevision>0,MutationEnvelopeV1.isSHA256(clipSHA256),MutationEnvelopeV1.isSHA256(policySHA256),actor.workspaceID==workspaceID,occurredAt.timeIntervalSinceReferenceDate.isFinite,revision>0,(revision==1)==(supersedesEventID==nil&&predecessorEventSHA256==nil),(revision>1)==(supersedesEventID != nil&&predecessorEventSHA256 != nil),supersedesEventID != eventID,predecessorEventSHA256.map(MutationEnvelopeV1.isSHA256) ?? true,eventSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw TemporalEvidenceContractFailureV1.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,workspaceID:workspaceID,clipID:clipID,clipRevision:clipRevision,clipSHA256:clipSHA256,disposition:disposition,policySHA256:policySHA256,actor:actor,occurredAt:occurredAt,supersedesEventID:supersedesEventID,predecessorEventSHA256:predecessorEventSHA256,revision:revision,mutationID:mutationID)};private struct Basis:Codable{let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let clipID:UUID;let clipRevision:UInt64;let clipSHA256:String;let disposition:TemporalEvidenceRetentionDispositionV1;let policySHA256:String;let actor:ActorSnapshotV1;let occurredAt:Date;let supersedesEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1}}

extension TemporalEvidenceDerivativeV1{var reference:TemporalEvidenceDerivativeReferenceV1{get throws{let v=TemporalEvidenceDerivativeReferenceV1(derivativeID:derivativeID,revision:revision,derivativeSHA256:derivativeSHA256,kind:kind);try v.validate();return v}}}
extension TemporalEvidenceRetentionEventV1{var reference:TemporalEvidenceRetentionReferenceV1{get throws{let v=TemporalEvidenceRetentionReferenceV1(eventID:eventID,revision:revision,eventSHA256:eventSHA256,disposition:disposition);try v.validate();return v}}}
extension TemporalEvidenceClipV1{func successor(clipID:UUID,profile:TemporalEvidenceLimitProfileV1,derivativeReferences:[TemporalEvidenceDerivativeReferenceV1]?=nil,retentionReference:TemporalEvidenceRetentionReferenceV1?=nil,mutationID:MutationIDV1)throws->Self{guard revision<UInt64.max else{throw TemporalEvidenceContractFailureV1.invalidTransition};return try .init(clipID:clipID,workspaceID:workspaceID,target:target,original:original,originalProvenance:originalProvenance,locator:locator,facts:facts,profile:profile,accessibleDescription:accessibleDescription,manualTranscript:manualTranscript,derivativeReferences:derivativeReferences ?? self.derivativeReferences,retentionReference:retentionReference ?? self.retentionReference,recordedBy:recordedBy,capturedAt:capturedAt,acceptedAt:acceptedAt,supersedesClipID:self.clipID,revision:revision+1,mutationID:mutationID)}}
extension TemporalEvidenceClipV1{
    func rebound(to workspaceID:WorkspaceID,target:TemporalEvidenceTargetV1,recordedBy:ActorSnapshotV1)throws->Self{guard target.definitionRelease==limitProfile.definitionRelease else{throw TemporalEvidenceContractFailureV1.staleSource};return try rebound(to:workspaceID,target:target,frozenProfile:limitProfile,recordedBy:recordedBy)}
    func rebound(to workspaceID:WorkspaceID,target:TemporalEvidenceTargetV1,profile:TemporalEvidenceLimitProfileV1,recordedBy:ActorSnapshotV1)throws->Self{try profile.validate();guard target.definitionRelease==profile.definitionRelease else{throw TemporalEvidenceContractFailureV1.staleSource};return try rebound(to:workspaceID,target:target,frozenProfile:profile,recordedBy:recordedBy)}
    func rebound(to workspaceID:WorkspaceID,target:TemporalEvidenceTargetV1,packageRelease:SurveyPackageReleaseReferenceV1,profileRevision:UInt64,recordedBy:ActorSnapshotV1)throws->Self{let profile=try limitProfile.rebound(packageRelease:packageRelease,definitionRelease:target.definitionRelease,revision:profileRevision);return try rebound(to:workspaceID,target:target,frozenProfile:profile,recordedBy:recordedBy)}
    private func rebound(to workspaceID:WorkspaceID,target:TemporalEvidenceTargetV1,frozenProfile:TemporalEvidenceLimitProfileV1,recordedBy:ActorSnapshotV1)throws->Self{let ws=workspaceID.rawValue.uuidString.lowercased();let reboundOriginal=try ContentReferenceV1(workspaceID:ws,contentID:original.contentID,byteLength:original.byteLength,mediaType:original.mediaType,digests:original.digests,byteRole:original.byteRole,createdAt:original.createdAt);let reboundProvenance=try ContentOriginalProvenanceV1(provenanceID:originalProvenance.provenanceID,workspaceID:ws,contentID:originalProvenance.contentID,contentDigest:originalProvenance.contentDigest,origin:originalProvenance.origin,recordedAt:originalProvenance.recordedAt);let reboundLocator=try ContentLocatorV1(locatorID:locator.locatorID,workspaceID:ws,contentID:locator.contentID,locatorRevision:locator.locatorRevision,contentDigest:locator.contentDigest,expectedByteLength:locator.expectedByteLength);let value=try Self(rebindingClipID:clipID,workspaceID:workspaceID,target:target,original:reboundOriginal,originalProvenance:reboundProvenance,locator:reboundLocator,facts:facts,limitProfile:frozenProfile,accessibleDescription:accessibleDescription,manualTranscript:manualTranscript,derivativeReferences:derivativeReferences,retentionReference:retentionReference,recordedBy:recordedBy,capturedAt:capturedAt,acceptedAt:acceptedAt,supersedesClipID:supersedesClipID,revision:revision,mutationID:mutationID);try value.validateIntrinsic();return value}
    private init(rebindingClipID clipID:UUID,workspaceID:WorkspaceID,target:TemporalEvidenceTargetV1,original:ContentReferenceV1,originalProvenance:ContentOriginalProvenanceV1,locator:ContentLocatorV1,facts:TemporalEvidenceMediaFactsV1,limitProfile:TemporalEvidenceLimitProfileV1,accessibleDescription:String,manualTranscript:String?,derivativeReferences:[TemporalEvidenceDerivativeReferenceV1],retentionReference:TemporalEvidenceRetentionReferenceV1?,recordedBy:ActorSnapshotV1,capturedAt:Date,acceptedAt:Date,supersedesClipID:UUID?,revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.clipID=clipID;self.workspaceID=workspaceID;self.target=target;self.original=original;self.originalProvenance=originalProvenance;self.locator=locator;self.facts=facts;self.limitProfile=limitProfile;self.accessibleDescription=accessibleDescription;self.manualTranscript=manualTranscript;self.derivativeReferences=derivativeReferences.sorted();self.retentionReference=retentionReference;self.recordedBy=recordedBy;self.capturedAt=capturedAt;self.acceptedAt=acceptedAt;self.supersedesClipID=supersedesClipID;self.revision=revision;self.mutationID=mutationID;clipSHA256=try WorkspaceMutationCanonicalV1.sha256(basis)}
}
extension TimecodedEvidenceAnchorV1{func rebound(to workspaceID:WorkspaceID,clip:TemporalEvidenceClipV1,author:ActorSnapshotV1)throws->Self{guard workspaceID==clip.workspaceID else{throw TemporalEvidenceContractFailureV1.wrongWorkspace};return try .init(anchorID:anchorID,clip:clip,offsetMilliseconds:offsetMilliseconds,label:label,note:note,author:author,recordedAt:recordedAt,supersedesAnchorID:supersedesAnchorID,predecessorAnchorSHA256:predecessorAnchorSHA256,revision:revision,mutationID:mutationID)}}

enum TemporalEvidenceCanonicalCodecV1 {
    static let maximumCanonicalBytes = 1_048_576
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try WorkspaceMutationCanonicalV1.data(value)
        guard !data.isEmpty, data.count <= maximumCanonicalBytes else {
            throw TemporalEvidenceContractFailureV1.limitExceeded
        }
        return data
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumCanonicalBytes else { throw TemporalEvidenceContractFailureV1.limitExceeded }
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970
        let value=try decoder.decode(type,from:data)
        if let clip=value as? TemporalEvidenceClipV1{try clip.validateIntrinsic()}
        if let anchor=value as? TimecodedEvidenceAnchorV1{try anchor.validateIntrinsic()}
        if let derivative=value as? TemporalEvidenceDerivativeV1{try derivative.validateIntrinsic()}
        if let retention=value as? TemporalEvidenceRetentionEventV1{try retention.validateIntrinsic()}
        guard try encode(value)==data else{throw TemporalEvidenceContractFailureV1.digestMismatch}
        return value
    }
}

enum TemporalEvidencePersistenceEnrollmentV1{static let persistentSchemaVersion=33;static let recordsSchemaVersion=32;static let durableModelCount=2;static let persistentFamilies=["TemporalEvidenceClipRow","TimecodedEvidenceAnchorRow"];static let derivativePersistence="CANONICAL_MUTATION_JOURNAL_ENVELOPE_AND_EXISTING_CONTENT_STORE";static let retentionPersistence="CANONICAL_MUTATION_JOURNAL_ENVELOPE";static let scratchPersistence="NONPERSISTENT_BACKUP_EXCLUDED";static let writer="SOLE_CANONICAL_WORKSPACE_WRITER";static let immutableOriginalsAreRewritten=false;static let automaticTranscriptionEnabled=false;static let secondByteStoreAllowed=false}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row182 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

import Foundation

enum OCRProposalFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, explicitActionRequired, capabilityUnavailable
    case unsupportedLanguage, staleTarget, sourceChanged, cloudProviderForbidden
}

enum OCRProposalPersistenceBoundaryV1 {
    static let schemaVersion = 53
    static let activeModelCount = 168
    static let addedDurableRowCount = 0
    static let acceptanceRowName = "AssistanceAcceptanceReceiptRow"
    static let activationEnabled = false
}

enum OCRFeatureActivationV1: String, Codable, Hashable, Sendable {
    case preparedDisabled = "PREPARED_DISABLED"
    /// Contract-only execution state for an explicitly injected, on-device
    /// provider. The bundled feature policy never selects this state in C23.
    case enabledOnDevice = "ENABLED_ON_DEVICE"
}

struct OCRCapabilityPolicyV1: Codable, Equatable, Sendable {
    let assistancePolicy: AssistanceCapabilityPolicyV1
    let activation: OCRFeatureActivationV1
    let supportedLanguageIdentifiers: [String]
    let maximumObservationCount: Int
    let maximumRecognizedTextBytes: Int
    let manualFallback: ManualFallbackActionV1
    let policySHA256: String

    init(assistancePolicy: AssistanceCapabilityPolicyV1,
         activation: OCRFeatureActivationV1 = .preparedDisabled,
         supportedLanguageIdentifiers: [String], maximumObservationCount: Int = 128,
         maximumRecognizedTextBytes: Int = 8_192) throws {
        try assistancePolicy.validate()
        let languages = supportedLanguageIdentifiers.sorted()
        try languages.forEach(AssistanceLimitsV1.token)
        let activationMatchesCapability =
            (activation == .preparedDisabled && !assistancePolicy.enabled) ||
            (activation == .enabledOnDevice && assistancePolicy.enabled)
        guard assistancePolicy.capability.capabilityID == "OCR_FIELD_PROPOSAL",
              activationMatchesCapability, !languages.isEmpty, Set(languages).count == languages.count,
              (1...128).contains(maximumObservationCount),
              (1...8_192).contains(maximumRecognizedTextBytes),
              assistancePolicy.manualFallback != .noFallback else { throw OCRProposalFailureV1.invalidValue }
        self.assistancePolicy = assistancePolicy; self.activation = activation
        self.supportedLanguageIdentifiers = languages
        self.maximumObservationCount = maximumObservationCount
        self.maximumRecognizedTextBytes = maximumRecognizedTextBytes
        manualFallback = assistancePolicy.manualFallback
        policySHA256 = try AssistanceCanonicalCodecV1.sha256(Basis(assistancePolicy: assistancePolicy,
            activation: activation, supportedLanguageIdentifiers: languages,
            maximumObservationCount: maximumObservationCount,
            maximumRecognizedTextBytes: maximumRecognizedTextBytes,
            manualFallback: assistancePolicy.manualFallback))
    }
    func validate() throws {
        guard self == (try Self(assistancePolicy: assistancePolicy,
            activation: activation,
            supportedLanguageIdentifiers: supportedLanguageIdentifiers,
            maximumObservationCount: maximumObservationCount,
            maximumRecognizedTextBytes: maximumRecognizedTextBytes))
        else { throw OCRProposalFailureV1.invalidDigest }
    }
    private struct Basis: Codable { let assistancePolicy: AssistanceCapabilityPolicyV1; let activation: OCRFeatureActivationV1; let supportedLanguageIdentifiers: [String]; let maximumObservationCount: Int; let maximumRecognizedTextBytes: Int; let manualFallback: ManualFallbackActionV1 }
}

struct OCRNormalizedCropV1: Codable, Equatable, Hashable, Sendable {
    let xBasisPoints: Int; let yBasisPoints: Int
    let widthBasisPoints: Int; let heightBasisPoints: Int
    func validate() throws {
        guard (0...9_999).contains(xBasisPoints), (0...9_999).contains(yBasisPoints),
              (1...10_000).contains(widthBasisPoints), (1...10_000).contains(heightBasisPoints),
              xBasisPoints + widthBasisPoints <= 10_000,
              yBasisPoints + heightBasisPoints <= 10_000 else { throw OCRProposalFailureV1.invalidValue }
    }
}

struct OCRTextObservationV1: Codable, Equatable, Hashable, Sendable {
    let observationID: UUID
    let recognizedText: String
    let confidence: AssistanceConfidenceV1
    let crop: OCRNormalizedCropV1
    func validate(maximumTextBytes: Int) throws {
        try AssistanceLimitsV1.id(observationID); try crop.validate()
        guard !recognizedText.isEmpty, recognizedText == recognizedText.trimmingCharacters(in: .whitespacesAndNewlines),
              recognizedText.utf8.count <= maximumTextBytes else { throw OCRProposalFailureV1.invalidValue }
    }
}

struct OCRExtractionRequestV1: Codable, Equatable, Sendable {
    let requestID: UUID
    let workspaceID: WorkspaceID
    let target: AssistanceTargetV1
    let source: AssistanceSourceReferenceV1
    let sourceCrop: OCRNormalizedCropV1
    let requestedLanguageIdentifiers: [String]
    let packageCustomWords: [String]
    let packageCustomWordsSHA256: String
    let explicitUserAction: Bool
    let requestedAt: Date
    let requestSHA256: String

    init(requestID: UUID, workspaceID: WorkspaceID, target: AssistanceTargetV1,
         source: AssistanceSourceReferenceV1, sourceCrop: OCRNormalizedCropV1,
         requestedLanguageIdentifiers: [String], packageCustomWords: [String],
         explicitUserAction: Bool, requestedAt: Date) throws {
        let languages = requestedLanguageIdentifiers.sorted(), words = packageCustomWords.sorted()
        try AssistanceLimitsV1.id(requestID); try target.validate(); try source.validate(); try sourceCrop.validate()
        try languages.forEach(AssistanceLimitsV1.token); try words.forEach(AssistanceLimitsV1.token)
        try AssistanceLimitsV1.instant(requestedAt)
        guard target.workspaceID == workspaceID, explicitUserAction, !languages.isEmpty,
              Set(languages).count == languages.count, Set(words).count == words.count,
              words.count <= 512 else { throw OCRProposalFailureV1.explicitActionRequired }
        self.requestID=requestID;self.workspaceID=workspaceID;self.target=target;self.source=source
        self.sourceCrop=sourceCrop;self.requestedLanguageIdentifiers=languages;self.packageCustomWords=words
        packageCustomWordsSHA256=try AssistanceCanonicalCodecV1.sha256(words)
        self.explicitUserAction=explicitUserAction;self.requestedAt=requestedAt
        requestSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(requestID:requestID,workspaceID:workspaceID,target:target,source:source,sourceCrop:sourceCrop,requestedLanguageIdentifiers:languages,packageCustomWords:words,packageCustomWordsSHA256:packageCustomWordsSHA256,explicitUserAction:explicitUserAction,requestedAt:requestedAt))
        try validate()
    }
    func validate() throws {
        guard self == (try Self(requestID:requestID,workspaceID:workspaceID,target:target,source:source,sourceCrop:sourceCrop,requestedLanguageIdentifiers:requestedLanguageIdentifiers,packageCustomWords:packageCustomWords,explicitUserAction:explicitUserAction,requestedAt:requestedAt)) else { throw OCRProposalFailureV1.invalidDigest }
    }
    private struct Basis: Codable { let requestID:UUID;let workspaceID:WorkspaceID;let target:AssistanceTargetV1;let source:AssistanceSourceReferenceV1;let sourceCrop:OCRNormalizedCropV1;let requestedLanguageIdentifiers:[String];let packageCustomWords:[String];let packageCustomWordsSHA256:String;let explicitUserAction:Bool;let requestedAt:Date }
}

struct OCRProposalEvidenceV1: Codable, Equatable, Sendable {
    let request: OCRExtractionRequestV1
    let frameworkIdentifier: String
    let frameworkRevision: Int
    let recognitionRequestRevision: Int
    let configuredLanguageIdentifiers: [String]
    let maximumRecognizedTextBytes: Int
    let observation: OCRTextObservationV1
    let proposal: AssistanceProposalV1
    let customWordsAreHintsOnly: Bool
    let processedOnDevice: Bool
    let networkAccessUsed: Bool
    let evidenceSHA256: String

    init(request: OCRExtractionRequestV1, frameworkIdentifier: String,
         frameworkRevision: Int, recognitionRequestRevision: Int,
         configuredLanguageIdentifiers: [String], maximumRecognizedTextBytes: Int,
         observation: OCRTextObservationV1,
         proposal: AssistanceProposalV1) throws {
        try request.validate();try proposal.validate()
        let languages=configuredLanguageIdentifiers.sorted();try languages.forEach(AssistanceLimitsV1.token)
        try AssistanceLimitsV1.token(frameworkIdentifier)
        guard (1...8_192).contains(maximumRecognizedTextBytes) else { throw OCRProposalFailureV1.invalidValue }
        try observation.validate(maximumTextBytes:maximumRecognizedTextBytes)
        let metadataSHA = try Self.metadataSHA256(request:request,frameworkIdentifier:frameworkIdentifier,
            frameworkRevision:frameworkRevision,recognitionRequestRevision:recognitionRequestRevision,
            configuredLanguageIdentifiers:languages,maximumRecognizedTextBytes:maximumRecognizedTextBytes,
            observation:observation)
        let expectedQuality = try AssistanceQualityMetadataV1(metricID:"OCR_EVIDENCE_V1",ratingID:metadataSHA)
        guard frameworkIdentifier == "APPLE_VISION", frameworkRevision>0,recognitionRequestRevision>0,
              !languages.isEmpty,Set(languages).count==languages.count,
              languages == request.requestedLanguageIdentifiers,
              observation.crop == request.sourceCrop,
              proposal.target==request.target,proposal.source==request.source,
              proposal.value == .text(observation.recognizedText),proposal.confidence==observation.confidence,
              proposal.quality==expectedQuality else { throw OCRProposalFailureV1.invalidValue }
        self.request=request;self.frameworkIdentifier=frameworkIdentifier;self.frameworkRevision=frameworkRevision
        self.recognitionRequestRevision=recognitionRequestRevision;self.configuredLanguageIdentifiers=languages
        self.maximumRecognizedTextBytes=maximumRecognizedTextBytes
        self.observation=observation;self.proposal=proposal;customWordsAreHintsOnly=true
        processedOnDevice=true;networkAccessUsed=false
        evidenceSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(request:request,frameworkIdentifier:frameworkIdentifier,frameworkRevision:frameworkRevision,recognitionRequestRevision:recognitionRequestRevision,configuredLanguageIdentifiers:languages,maximumRecognizedTextBytes:maximumRecognizedTextBytes,observation:observation,proposal:proposal,customWordsAreHintsOnly:true,processedOnDevice:true,networkAccessUsed:false))
        try validate()
    }
    func validate() throws {
        guard self == (try Self(request:request,frameworkIdentifier:frameworkIdentifier,
            frameworkRevision:frameworkRevision,recognitionRequestRevision:recognitionRequestRevision,
            configuredLanguageIdentifiers:configuredLanguageIdentifiers,
            maximumRecognizedTextBytes:maximumRecognizedTextBytes,observation:observation,
            proposal:proposal)) else { throw OCRProposalFailureV1.invalidDigest }
    }
    func validate(policy:OCRCapabilityPolicyV1)throws{
        try validate();try policy.validate()
        guard maximumRecognizedTextBytes == policy.maximumRecognizedTextBytes,
              configuredLanguageIdentifiers.allSatisfy({policy.supportedLanguageIdentifiers.contains($0)})
        else{throw OCRProposalFailureV1.invalidValue}
    }
    static func metadataSHA256(request:OCRExtractionRequestV1,frameworkIdentifier:String,
        frameworkRevision:Int,recognitionRequestRevision:Int,
        configuredLanguageIdentifiers:[String],maximumRecognizedTextBytes:Int,
        observation:OCRTextObservationV1)throws->String{
        try AssistanceCanonicalCodecV1.sha256(Metadata(request:request,frameworkIdentifier:frameworkIdentifier,
            frameworkRevision:frameworkRevision,recognitionRequestRevision:recognitionRequestRevision,
            configuredLanguageIdentifiers:configuredLanguageIdentifiers.sorted(),
            maximumRecognizedTextBytes:maximumRecognizedTextBytes,observation:observation))
    }
    private var basis:Basis{.init(request:request,frameworkIdentifier:frameworkIdentifier,frameworkRevision:frameworkRevision,recognitionRequestRevision:recognitionRequestRevision,configuredLanguageIdentifiers:configuredLanguageIdentifiers,maximumRecognizedTextBytes:maximumRecognizedTextBytes,observation:observation,proposal:proposal,customWordsAreHintsOnly:customWordsAreHintsOnly,processedOnDevice:processedOnDevice,networkAccessUsed:networkAccessUsed)}
    private struct Basis:Codable{let request:OCRExtractionRequestV1;let frameworkIdentifier:String;let frameworkRevision:Int;let recognitionRequestRevision:Int;let configuredLanguageIdentifiers:[String];let maximumRecognizedTextBytes:Int;let observation:OCRTextObservationV1;let proposal:AssistanceProposalV1;let customWordsAreHintsOnly:Bool;let processedOnDevice:Bool;let networkAccessUsed:Bool}
    private struct Metadata:Codable{let request:OCRExtractionRequestV1;let frameworkIdentifier:String;let frameworkRevision:Int;let recognitionRequestRevision:Int;let configuredLanguageIdentifiers:[String];let maximumRecognizedTextBytes:Int;let observation:OCRTextObservationV1}
}

enum OCRFieldReviewDispositionV1: String, Codable, Hashable, Sendable { case accepted="ACCEPTED",edited="EDITED",rejected="REJECTED" }
struct OCRFieldReviewV1: Codable, Equatable, Sendable {
    let evidenceSHA256:String;let proposalID:UUID;let disposition:OCRFieldReviewDispositionV1
    let reviewedValue:ResponseValueV1?;let reviewedBy:ActorSnapshotV1;let reviewedAt:Date
    let reviewSHA256:String
    init(evidence:OCRProposalEvidenceV1,disposition:OCRFieldReviewDispositionV1,reviewedValue:ResponseValueV1?,reviewedBy:ActorSnapshotV1,reviewedAt:Date)throws{try evidence.validate();try reviewedBy.validate();try reviewedValue?.validate();guard reviewedBy.workspaceID==evidence.request.workspaceID,reviewedBy.responsibility == .reviewedBy,reviewedAt>=evidence.proposal.createdAt,reviewedAt<evidence.proposal.expiresAt,(disposition == .rejected)==(reviewedValue==nil),(disposition != .rejected) == (reviewedValue != nil),(disposition == .accepted ? reviewedValue==evidence.proposal.value : true),(disposition == .edited ? reviewedValue != evidence.proposal.value : true) else{throw OCRProposalFailureV1.invalidValue};evidenceSHA256=evidence.evidenceSHA256;proposalID=evidence.proposal.proposalID;self.disposition=disposition;self.reviewedValue=reviewedValue;self.reviewedBy=reviewedBy;self.reviewedAt=reviewedAt;reviewSHA256=try AssistanceCanonicalCodecV1.sha256(Basis(evidenceSHA256:evidence.evidenceSHA256,proposalID:evidence.proposal.proposalID,disposition:disposition,reviewedValue:reviewedValue,reviewedBy:reviewedBy,reviewedAt:reviewedAt))}
    func validate(evidence:OCRProposalEvidenceV1)throws{guard self == (try Self(evidence:evidence,disposition:disposition,reviewedValue:reviewedValue,reviewedBy:reviewedBy,reviewedAt:reviewedAt))else{throw OCRProposalFailureV1.invalidDigest}}
    private struct Basis:Codable{let evidenceSHA256:String;let proposalID:UUID;let disposition:OCRFieldReviewDispositionV1;let reviewedValue:ResponseValueV1?;let reviewedBy:ActorSnapshotV1;let reviewedAt:Date}
}

enum OCRProposalOutcomeV1: Equatable, Sendable {
    case manualFallback(ManualFallbackActionV1)
    case proposals([OCRProposalEvidenceV1])
}

protocol OCRProposalExtractingV1: Sendable {
    func extract(_ request: OCRExtractionRequestV1) async throws -> [OCRProposalEvidenceV1]
}

@MainActor protocol OCRProposalScratchLifecycleV1: AnyObject {
    /// Validates the exact source/crop and, for leased scratch, binds the
    /// incumbent lease to `requestID` before any provider content access.
    func prepare(_ request: OCRExtractionRequestV1) async throws
    /// Idempotently terminates only extraction failures. Presented proposal
    /// accept/reject/cancel/expiry cleanup remains owned by AssistanceLifecycle.
    func discardAfterFailedExtraction(_ request: OCRExtractionRequestV1) async throws
}

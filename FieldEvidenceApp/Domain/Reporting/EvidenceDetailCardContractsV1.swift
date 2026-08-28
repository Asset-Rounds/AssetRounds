import Foundation

enum EvidenceDetailSensitivityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case audienceSafe = "AUDIENCE_SAFE"
    case privateNote = "PRIVATE_NOTE"
    case originalMedia = "ORIGINAL_MEDIA"
    case contactData = "CONTACT_DATA"
    case directCost = "DIRECT_COST"
    case capabilitySecret = "CAPABILITY_SECRET"
    case localIdentifier = "LOCAL_IDENTIFIER"
    case diagnostic = "DIAGNOSTIC"
}

enum EvidenceDetailAccessibleAlternateTextPolicyV1{
    static let automaticDescriptionAllowed=false
    static let allowedProvenance=AccessibleAlternateTextProvenanceV1.allCases
}

enum AudiencePrivacyDetectorDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case pass = "PASS"
    case blocked = "BLOCKED"
}

enum AudiencePrivacyFindingKindV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case prohibitedField = "PROHIBITED_FIELD"
    case prohibitedAnnotation = "PROHIBITED_ANNOTATION"
    case prohibitedReferenceLabel = "PROHIBITED_REFERENCE_LABEL"
    case prohibitedSemanticText = "PROHIBITED_SEMANTIC_TEXT"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum AudiencePrivacyLexicalDetectorV1 {
    private static let prohibitedFragments = [
        "c:\\", "capability-secret", "contact-canary", "cost-canary", "diagnostic-canary", "file://",
        "http://", "https://",
        "local-id-canary", "original-canary", "private-canary", "secret-canary", "verified-person-canary",
        "\\users\\", "/users/",
    ]

    static func containsProhibitedPattern(in values: [String]) -> Bool {
        values.contains { value in
            let folded = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return prohibitedFragments.contains(where: folded.contains)
        }
    }

    /// C41 relationship facts have a narrower customer-safe claim boundary
    /// than ordinary evidence text. Keep it opt-in by field ID so existing
    /// cards retain their established wording while relationship cards cannot
    /// turn an association into an ownership, authorization, compliance,
    /// safety, telemetry, or remote claim.
    static func isFunctionalRelationshipFieldID(_ fieldID: String) -> Bool {
        let normalized = fieldID
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return normalized == "functional_relationship"
            || normalized.hasPrefix("functional_relationship_")
    }

    static func containsProhibitedFunctionalRelationshipClaim(in values: [String]) -> Bool {
        FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(in: values)
    }
}

enum AuthorityCriterionClaimVocabularyV1 {
    private static let prohibitedPhrases: [String] = [
        // C40 forbids app-origin legal, jurisdiction, compliance, safety,
        // licensing, web-update, evaluator, unit-system, package, and S10
        // claims. Normalize punctuation below so hyphenated hostile canaries
        // cannot bypass this closed vocabulary.
        "approved by ahj",
        "ahj",
        "certified",
        "certified by",
        "certified copy",
        "compliant",
        "is certified",
        "is compliant",
        "is safe",
        "safe",
        "safe to use",
        "safe compliant certified copy leak",
        "legal research",
        "legal research engine",
        "gps derived jurisdiction",
        "gps jurisdiction",
        "automatic legal precedence",
        "automatic legal precedence or ahj selection",
        "automatic ahj selection",
        "ahj selection",
        "automatic compliance",
        "compliance score",
        "safety score",
        "licensed source",
        "licensed source text",
        "web updated standard",
        "web updated standards",
        "user authored evaluator",
        "user authored script",
        "evaluator or script",
        "full ucum",
        "second unit system",
        "second reference store",
        "package specific table",
        "package specific writer",
        "s10 release",
        "s10 brand approval",
        "brand approval",
        "professional",
        "professional qualification",
        "qualified professional",
        "professional claim",
    ]

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let normalized = value
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: " ")
            let bounded = " \(normalized) "
            return prohibitedPhrases.contains { bounded.contains(" \($0) ") }
        }
    }
}

struct AudiencePrivacyPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let policyID: String
    let policyVersion: Int
    let audience: ReportAudienceV1
    let prohibitedCanaries: [String]
    let policySHA256: String

    init(
        policyID: String,
        policyVersion: Int,
        audience: ReportAudienceV1,
        prohibitedCanaries: [String]
    ) throws {
        guard SnapshotProjectionValidationV1.validID(policyID), policyVersion > 0,
              audience != .customerSafe || !prohibitedCanaries.isEmpty,
              prohibitedCanaries == prohibitedCanaries.sorted(),
              Set(prohibitedCanaries).count == prohibitedCanaries.count,
              prohibitedCanaries.allSatisfy(SnapshotProjectionValidationV1.validText) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.audience = audience
        self.prohibitedCanaries = prohibitedCanaries
        policySHA256 = try Self.digest(
            policyID: policyID,
            policyVersion: policyVersion,
            audience: audience,
            prohibitedCanaries: prohibitedCanaries
        )
    }

    private struct DigestPayload: Encodable {
        let schemaVersion: Int
        let policyID: String
        let policyVersion: Int
        let audience: ReportAudienceV1
        let prohibitedCanaries: [String]
    }

    private static func digest(
        policyID: String,
        policyVersion: Int,
        audience: ReportAudienceV1,
        prohibitedCanaries: [String]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return KernelCanonicalHashV1.sha256(try encoder.encode(DigestPayload(
            schemaVersion: schemaVersion,
            policyID: policyID,
            policyVersion: policyVersion,
            audience: audience,
            prohibitedCanaries: prohibitedCanaries
        )))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, policyID, policyVersion, audience, prohibitedCanaries, policySHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let encodedSchema = try values.decode(Int.self, forKey: .schemaVersion)
        let encodedDigest = try values.decode(String.self, forKey: .policySHA256)
        guard encodedSchema == Self.schemaVersion else { throw SnapshotProjectionFailureV1.invalidValue }
        try self.init(
            policyID: values.decode(String.self, forKey: .policyID),
            policyVersion: values.decode(Int.self, forKey: .policyVersion),
            audience: values.decode(ReportAudienceV1.self, forKey: .audience),
            prohibitedCanaries: values.decode([String].self, forKey: .prohibitedCanaries)
        )
        guard policySHA256 == encodedDigest else { throw SnapshotProjectionFailureV1.missingBinding }
        try validate()
    }
}

struct EvidenceDetailFieldV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let fieldID: String
    let label: String
    let value: String
    let sensitivity: EvidenceDetailSensitivityV1

    static func < (lhs: EvidenceDetailFieldV1, rhs: EvidenceDetailFieldV1) -> Bool {
        lhs.fieldID < rhs.fieldID
    }

    init(fieldID: String, label: String, value: String, sensitivity: EvidenceDetailSensitivityV1) throws {
        guard SnapshotProjectionValidationV1.validID(fieldID),
              SnapshotProjectionValidationV1.validText(label),
              SnapshotProjectionValidationV1.validText(value) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        self.fieldID = fieldID
        self.label = label
        self.value = value
        self.sensitivity = sensitivity
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case fieldID, label, value, sensitivity }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fieldID: values.decode(String.self, forKey: .fieldID),
            label: values.decode(String.self, forKey: .label),
            value: values.decode(String.self, forKey: .value),
            sensitivity: values.decode(EvidenceDetailSensitivityV1.self, forKey: .sensitivity)
        )
        try validate()
    }
}

struct EvidenceDetailCardProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let profileID: String
    let profileRelease: Int
    let audience: ReportAudienceV1
    let outputScopeID: String
    let privacyTransformID: String
    let privacyTransformVersion: Int
    let markupProfileID: String
    let markupProfileVersion: Int
    let localeIdentifier: String
    let displayProfileID: String
    let rendererVersion: String
    let audiencePrivacyPolicy: AudiencePrivacyPolicyV1
    let includedFieldIDs: [String]
    let limitationsText: String

    init(
        profileID: String,
        profileRelease: Int,
        audience: ReportAudienceV1,
        outputScopeID: String,
        privacyTransformID: String,
        privacyTransformVersion: Int,
        markupProfileID: String,
        markupProfileVersion: Int,
        localeIdentifier: String,
        displayProfileID: String,
        rendererVersion: String,
        audiencePrivacyPolicy: AudiencePrivacyPolicyV1,
        includedFieldIDs: [String],
        limitationsText: String
    ) throws {
        let ids = [profileID, outputScopeID, privacyTransformID, markupProfileID, displayProfileID, rendererVersion]
        guard ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              profileRelease > 0, privacyTransformVersion > 0, markupProfileVersion > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              audiencePrivacyPolicy.audience == audience,
              !includedFieldIDs.isEmpty,
              includedFieldIDs == includedFieldIDs.sorted(),
              Set(includedFieldIDs).count == includedFieldIDs.count,
              includedFieldIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              SnapshotProjectionValidationV1.validText(limitationsText),
              limitationsText.contains("does not verify capture time, location, or person") else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.profileRelease = profileRelease
        self.audience = audience
        self.outputScopeID = outputScopeID
        self.privacyTransformID = privacyTransformID
        self.privacyTransformVersion = privacyTransformVersion
        self.markupProfileID = markupProfileID
        self.markupProfileVersion = markupProfileVersion
        self.localeIdentifier = localeIdentifier
        self.displayProfileID = displayProfileID
        self.rendererVersion = rendererVersion
        self.audiencePrivacyPolicy = audiencePrivacyPolicy
        self.includedFieldIDs = includedFieldIDs
        self.limitationsText = limitationsText
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, profileID, profileRelease, audience, outputScopeID
        case privacyTransformID, privacyTransformVersion, markupProfileID, markupProfileVersion
        case localeIdentifier, displayProfileID, rendererVersion, audiencePrivacyPolicy
        case includedFieldIDs, limitationsText
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try self.init(
            profileID: values.decode(String.self, forKey: .profileID),
            profileRelease: values.decode(Int.self, forKey: .profileRelease),
            audience: values.decode(ReportAudienceV1.self, forKey: .audience),
            outputScopeID: values.decode(String.self, forKey: .outputScopeID),
            privacyTransformID: values.decode(String.self, forKey: .privacyTransformID),
            privacyTransformVersion: values.decode(Int.self, forKey: .privacyTransformVersion),
            markupProfileID: values.decode(String.self, forKey: .markupProfileID),
            markupProfileVersion: values.decode(Int.self, forKey: .markupProfileVersion),
            localeIdentifier: values.decode(String.self, forKey: .localeIdentifier),
            displayProfileID: values.decode(String.self, forKey: .displayProfileID),
            rendererVersion: values.decode(String.self, forKey: .rendererVersion),
            audiencePrivacyPolicy: values.decode(AudiencePrivacyPolicyV1.self, forKey: .audiencePrivacyPolicy),
            includedFieldIDs: values.decode([String].self, forKey: .includedFieldIDs),
            limitationsText: values.decode(String.self, forKey: .limitationsText)
        )
        try validate()
    }
}

struct ReviewedEvidenceMarkupV1: Codable, Equatable, Sendable {
    let markupID: String
    let sourcePrivacyDigest: String
    let orderedAnnotations: [String]
    let orderedReferenceLabels: [String]

    init(
        markupID: String,
        sourcePrivacyDigest: String,
        orderedAnnotations: [String],
        orderedReferenceLabels: [String]
    ) throws {
        guard SnapshotProjectionValidationV1.validID(markupID),
              KernelCanonicalHashV1.validSHA256(sourcePrivacyDigest),
              orderedAnnotations.count <= 128,
              orderedReferenceLabels.count <= 256,
              orderedAnnotations.allSatisfy({ SnapshotProjectionValidationV1.validText($0) }),
              orderedReferenceLabels.allSatisfy({ SnapshotProjectionValidationV1.validText($0) }) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        self.markupID = markupID
        self.sourcePrivacyDigest = sourcePrivacyDigest
        self.orderedAnnotations = orderedAnnotations
        self.orderedReferenceLabels = orderedReferenceLabels
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case markupID, sourcePrivacyDigest, orderedAnnotations, orderedReferenceLabels
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            markupID: values.decode(String.self, forKey: .markupID),
            sourcePrivacyDigest: values.decode(String.self, forKey: .sourcePrivacyDigest),
            orderedAnnotations: values.decode([String].self, forKey: .orderedAnnotations),
            orderedReferenceLabels: values.decode([String].self, forKey: .orderedReferenceLabels)
        )
        try validate()
    }
}

struct EvidenceDetailCardV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let cardID: String
    let workspaceID: String
    let evidenceID: String
    let outputScopeID: String
    let profileID: String
    let profileSHA256: String
    let profile: EvidenceDetailCardProfileV1
    let audience: ReportAudienceV1
    let privacyTransformID: String
    let privacyTransformVersion: Int
    let localeIdentifier: String
    let displayProfileID: String
    let rendererVersion: String
    let audiencePrivacyPolicyID: String
    let audiencePrivacyPolicyVersion: Int
    let audiencePrivacyPolicySHA256: String
    let audiencePrivacyPolicy: AudiencePrivacyPolicyV1
    let privacyTransformedSHA256: String
    let reviewedMarkupID: String
    let reviewedMarkupSHA256: String
    let reviewedMarkup: ReviewedEvidenceMarkupV1
    let fields: [EvidenceDetailFieldV1]
    let outputReferences: [OutputScopedContentReferenceV1]
    let annotations: [String]
    let referenceLabels: [String]
    let limitationsText: String

    init(
        cardID: String,
        workspaceID: String,
        evidenceID: String,
        profile: EvidenceDetailCardProfileV1,
        privacyTransformedSHA256: String,
        reviewedMarkup: ReviewedEvidenceMarkupV1,
        fields: [EvidenceDetailFieldV1],
        outputReferences: [OutputScopedContentReferenceV1]
    ) throws {
        guard [cardID, workspaceID, evidenceID].allSatisfy(SnapshotProjectionValidationV1.validID),
              KernelCanonicalHashV1.validSHA256(privacyTransformedSHA256),
              reviewedMarkup.sourcePrivacyDigest == privacyTransformedSHA256,
              !fields.isEmpty, fields == fields.sorted(), Set(fields.map(\.fieldID)).count == fields.count,
              Set(fields.map(\.fieldID)).isSubset(of: Set(profile.includedFieldIDs)),
              outputReferences == outputReferences.sorted(),
              Set(outputReferences.map(\.outputReferenceID)).count == outputReferences.count,
              reviewedMarkup.orderedReferenceLabels.count == outputReferences.count,
              outputReferences.allSatisfy({
                $0.outputScopeID == profile.outputScopeID
                    && $0.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(
                        Data("\(workspaceID)|\(profile.outputScopeID)".utf8)
                    )
                    && SnapshotProjectionValidationV1.validID($0.outputReferenceID)
                    && KernelCanonicalHashV1.validSHA256($0.workspaceBindingSHA256)
                    && KernelCanonicalHashV1.validSHA256($0.contentSHA256)
                    && SnapshotProjectionValidationV1.validText($0.mediaType)
              }) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        if profile.audience == .customerSafe,
           (fields.contains(where: { $0.sensitivity != .audienceSafe })
            || outputReferences.contains(where: { $0.byteRole != .derivative })) {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        schemaVersion = Self.schemaVersion
        self.cardID = cardID
        self.workspaceID = workspaceID
        self.evidenceID = evidenceID
        outputScopeID = profile.outputScopeID
        profileID = profile.profileID
        profileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(profile))
        self.profile = profile
        audience = profile.audience
        privacyTransformID = profile.privacyTransformID
        privacyTransformVersion = profile.privacyTransformVersion
        localeIdentifier = profile.localeIdentifier
        displayProfileID = profile.displayProfileID
        rendererVersion = profile.rendererVersion
        audiencePrivacyPolicyID = profile.audiencePrivacyPolicy.policyID
        audiencePrivacyPolicyVersion = profile.audiencePrivacyPolicy.policyVersion
        audiencePrivacyPolicySHA256 = profile.audiencePrivacyPolicy.policySHA256
        audiencePrivacyPolicy = profile.audiencePrivacyPolicy
        self.privacyTransformedSHA256 = privacyTransformedSHA256
        reviewedMarkupID = reviewedMarkup.markupID
        reviewedMarkupSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(reviewedMarkup))
        self.reviewedMarkup = reviewedMarkup
        self.fields = fields
        self.outputReferences = outputReferences
        annotations = reviewedMarkup.orderedAnnotations
        referenceLabels = reviewedMarkup.orderedReferenceLabels
        limitationsText = profile.limitationsText
        try validate()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, cardID, workspaceID, evidenceID, outputScopeID, profileID, profileSHA256, profile
        case audience, privacyTransformID, privacyTransformVersion, localeIdentifier, displayProfileID, rendererVersion
        case audiencePrivacyPolicyID, audiencePrivacyPolicyVersion, audiencePrivacyPolicySHA256, audiencePrivacyPolicy
        case privacyTransformedSHA256, reviewedMarkupID, reviewedMarkupSHA256, reviewedMarkup, fields, outputReferences
        case annotations, referenceLabels, limitationsText
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        let cardID = try values.decode(String.self, forKey: .cardID)
        let workspaceID = try values.decode(String.self, forKey: .workspaceID)
        let evidenceID = try values.decode(String.self, forKey: .evidenceID)
        let outputScopeID = try values.decode(String.self, forKey: .outputScopeID)
        let profileID = try values.decode(String.self, forKey: .profileID)
        let profileSHA256 = try values.decode(String.self, forKey: .profileSHA256)
        let profile = try values.decode(EvidenceDetailCardProfileV1.self, forKey: .profile)
        let audience = try values.decode(ReportAudienceV1.self, forKey: .audience)
        let privacyTransformID = try values.decode(String.self, forKey: .privacyTransformID)
        let privacyTransformVersion = try values.decode(Int.self, forKey: .privacyTransformVersion)
        let localeIdentifier = try values.decode(String.self, forKey: .localeIdentifier)
        let displayProfileID = try values.decode(String.self, forKey: .displayProfileID)
        let rendererVersion = try values.decode(String.self, forKey: .rendererVersion)
        let audiencePrivacyPolicyID = try values.decode(String.self, forKey: .audiencePrivacyPolicyID)
        let audiencePrivacyPolicyVersion = try values.decode(Int.self, forKey: .audiencePrivacyPolicyVersion)
        let audiencePrivacyPolicySHA256 = try values.decode(String.self, forKey: .audiencePrivacyPolicySHA256)
        let audiencePrivacyPolicy = try values.decode(AudiencePrivacyPolicyV1.self, forKey: .audiencePrivacyPolicy)
        let privacyTransformedSHA256 = try values.decode(String.self, forKey: .privacyTransformedSHA256)
        let reviewedMarkupID = try values.decode(String.self, forKey: .reviewedMarkupID)
        let reviewedMarkupSHA256 = try values.decode(String.self, forKey: .reviewedMarkupSHA256)
        let reviewedMarkup = try values.decode(ReviewedEvidenceMarkupV1.self, forKey: .reviewedMarkup)
        let fields = try values.decode([EvidenceDetailFieldV1].self, forKey: .fields)
        let outputReferences = try values.decode([OutputScopedContentReferenceV1].self, forKey: .outputReferences)
        let annotations = try values.decode([String].self, forKey: .annotations)
        let referenceLabels = try values.decode([String].self, forKey: .referenceLabels)
        let limitationsText = try values.decode(String.self, forKey: .limitationsText)
        let ids = [cardID, workspaceID, evidenceID, outputScopeID, profileID, privacyTransformID,
                   displayProfileID, rendererVersion, audiencePrivacyPolicyID, reviewedMarkupID]
        guard schemaVersion == Self.schemaVersion,
              ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              privacyTransformVersion > 0, audiencePrivacyPolicyVersion > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              [profileSHA256, audiencePrivacyPolicySHA256, privacyTransformedSHA256, reviewedMarkupSHA256]
                .allSatisfy(KernelCanonicalHashV1.validSHA256),
              profile.profileID == profileID,
              profile.outputScopeID == outputScopeID,
              profile.audience == audience,
              profile.privacyTransformID == privacyTransformID,
              profile.privacyTransformVersion == privacyTransformVersion,
              profile.localeIdentifier == localeIdentifier,
              profile.displayProfileID == displayProfileID,
              profile.rendererVersion == rendererVersion,
              audiencePrivacyPolicy.policyID == audiencePrivacyPolicyID,
              audiencePrivacyPolicy.policyVersion == audiencePrivacyPolicyVersion,
              audiencePrivacyPolicy.policySHA256 == audiencePrivacyPolicySHA256,
              audiencePrivacyPolicy.audience == audience,
              reviewedMarkup.markupID == reviewedMarkupID,
              reviewedMarkup.sourcePrivacyDigest == privacyTransformedSHA256,
              reviewedMarkup.orderedAnnotations == annotations,
              reviewedMarkup.orderedReferenceLabels == referenceLabels,
              !fields.isEmpty, fields == fields.sorted(), Set(fields.map(\.fieldID)).count == fields.count,
              outputReferences == outputReferences.sorted(),
              Set(outputReferences.map(\.outputReferenceID)).count == outputReferences.count,
              referenceLabels.count == outputReferences.count,
              annotations.count <= 128, referenceLabels.count <= 256,
              (annotations + referenceLabels + [limitationsText]).allSatisfy(SnapshotProjectionValidationV1.validText),
              outputReferences.allSatisfy({
                  $0.outputScopeID == outputScopeID
                    && $0.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(
                        Data("\(workspaceID)|\(outputScopeID)".utf8)
                    )
                    && SnapshotProjectionValidationV1.validID($0.outputReferenceID)
                    && KernelCanonicalHashV1.validSHA256($0.workspaceBindingSHA256)
                    && KernelCanonicalHashV1.validSHA256($0.contentSHA256)
                    && SnapshotProjectionValidationV1.validText($0.mediaType)
              }) else { throw SnapshotProjectionFailureV1.invalidValue }
        if audience == .customerSafe,
           (fields.contains(where: { $0.sensitivity != .audienceSafe })
            || outputReferences.contains(where: { $0.byteRole != .derivative })) {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        self.schemaVersion = schemaVersion
        self.cardID = cardID
        self.workspaceID = workspaceID
        self.evidenceID = evidenceID
        self.outputScopeID = outputScopeID
        self.profileID = profileID
        self.profileSHA256 = profileSHA256
        self.profile = profile
        self.audience = audience
        self.privacyTransformID = privacyTransformID
        self.privacyTransformVersion = privacyTransformVersion
        self.localeIdentifier = localeIdentifier
        self.displayProfileID = displayProfileID
        self.rendererVersion = rendererVersion
        self.audiencePrivacyPolicyID = audiencePrivacyPolicyID
        self.audiencePrivacyPolicyVersion = audiencePrivacyPolicyVersion
        self.audiencePrivacyPolicySHA256 = audiencePrivacyPolicySHA256
        self.audiencePrivacyPolicy = audiencePrivacyPolicy
        self.privacyTransformedSHA256 = privacyTransformedSHA256
        self.reviewedMarkupID = reviewedMarkupID
        self.reviewedMarkupSHA256 = reviewedMarkupSHA256
        self.reviewedMarkup = reviewedMarkup
        self.fields = fields
        self.outputReferences = outputReferences
        self.annotations = annotations
        self.referenceLabels = referenceLabels
        self.limitationsText = limitationsText
        try validate()
    }
}

struct PostMarkupAudiencePrivacyDetectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let detectorID: String
    let detectorVersion: Int
    let audience: ReportAudienceV1
    let policyID: String
    let policyVersion: Int
    let policySHA256: String
    let cardSHA256: String
    let semanticText: String
    let semanticTextSHA256: String
    let composedOutput: Data
    let composedOutputSHA256: String
    let disposition: AudiencePrivacyDetectorDispositionV1
    let findingKinds: [AudiencePrivacyFindingKindV1]

    init(
        detectorID: String,
        detectorVersion: Int,
        policy: AudiencePrivacyPolicyV1,
        card: EvidenceDetailCardV1,
        semanticText: String,
        composedOutput: Data
    ) throws {
        guard SnapshotProjectionValidationV1.validID(detectorID), detectorVersion > 0,
              policy.audience == card.audience,
              policy.policyID == card.audiencePrivacyPolicyID,
              policy.policyVersion == card.audiencePrivacyPolicyVersion,
              policy.policySHA256 == card.audiencePrivacyPolicySHA256,
              SnapshotProjectionValidationV1.validText(semanticText),
              !composedOutput.isEmpty,
              composedOutput.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var findings = Set<AudiencePrivacyFindingKindV1>()
        if card.audience == .customerSafe {
            let fieldText = card.fields.flatMap { [$0.label, $0.value] }
            let composedText = String(decoding: composedOutput, as: UTF8.self)
            let hasFunctionalRelationshipFields = card.fields.contains {
                AudiencePrivacyLexicalDetectorV1.isFunctionalRelationshipFieldID($0.fieldID)
            }
            let relationshipClaimIn = { (values: [String]) in
                hasFunctionalRelationshipFields
                    && AudiencePrivacyLexicalDetectorV1
                        .containsProhibitedFunctionalRelationshipClaim(in: values)
            }
            if card.fields.contains(where: { $0.sensitivity != .audienceSafe }) {
                findings.insert(.prohibitedField)
            }
            if policy.containsProhibitedCanary(in: fieldText)
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: fieldText)
                || relationshipClaimIn(fieldText) {
                findings.insert(.prohibitedField)
            }
            if policy.containsProhibitedCanary(in: card.annotations)
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: card.annotations)
                || relationshipClaimIn(card.annotations) {
                findings.insert(.prohibitedAnnotation)
            }
            if policy.containsProhibitedCanary(in: card.referenceLabels)
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: card.referenceLabels)
                || relationshipClaimIn(card.referenceLabels) {
                findings.insert(.prohibitedReferenceLabel)
            }
            if policy.containsProhibitedCanary(in: [semanticText, composedText])
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: [semanticText, composedText])
                || relationshipClaimIn([semanticText, composedText]) {
                findings.insert(.prohibitedSemanticText)
            }
        }
        schemaVersion = Self.schemaVersion
        self.detectorID = detectorID
        self.detectorVersion = detectorVersion
        audience = card.audience
        policyID = policy.policyID
        policyVersion = policy.policyVersion
        policySHA256 = policy.policySHA256
        cardSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(card))
        self.semanticText = semanticText
        semanticTextSHA256 = KernelCanonicalHashV1.sha256(Data(semanticText.utf8))
        self.composedOutput = composedOutput
        composedOutputSHA256 = KernelCanonicalHashV1.sha256(composedOutput)
        findingKinds = findings.sorted()
        disposition = findings.isEmpty ? .pass : .blocked
        try validate()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, detectorID, detectorVersion, audience, policyID, policyVersion, policySHA256
        case cardSHA256, semanticText, semanticTextSHA256, composedOutput, composedOutputSHA256
        case disposition, findingKinds
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        let detectorID = try values.decode(String.self, forKey: .detectorID)
        let detectorVersion = try values.decode(Int.self, forKey: .detectorVersion)
        let audience = try values.decode(ReportAudienceV1.self, forKey: .audience)
        let policyID = try values.decode(String.self, forKey: .policyID)
        let policyVersion = try values.decode(Int.self, forKey: .policyVersion)
        let policySHA256 = try values.decode(String.self, forKey: .policySHA256)
        let cardSHA256 = try values.decode(String.self, forKey: .cardSHA256)
        let semanticText = try values.decode(String.self, forKey: .semanticText)
        let semanticTextSHA256 = try values.decode(String.self, forKey: .semanticTextSHA256)
        let composedOutput = try values.decode(Data.self, forKey: .composedOutput)
        let composedOutputSHA256 = try values.decode(String.self, forKey: .composedOutputSHA256)
        let disposition = try values.decode(AudiencePrivacyDetectorDispositionV1.self, forKey: .disposition)
        let findingKinds = try values.decode([AudiencePrivacyFindingKindV1].self, forKey: .findingKinds)
        guard schemaVersion == Self.schemaVersion,
              SnapshotProjectionValidationV1.validID(detectorID), detectorVersion > 0,
              SnapshotProjectionValidationV1.validID(policyID), policyVersion > 0,
              SnapshotProjectionValidationV1.validText(semanticText),
              semanticTextSHA256 == KernelCanonicalHashV1.sha256(Data(semanticText.utf8)),
              !composedOutput.isEmpty,
              composedOutput.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              composedOutputSHA256 == KernelCanonicalHashV1.sha256(composedOutput),
              (!AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: [semanticText])
                || (disposition == .blocked && findingKinds.contains(.prohibitedSemanticText))),
              [policySHA256, cardSHA256, semanticTextSHA256, composedOutputSHA256]
                .allSatisfy(KernelCanonicalHashV1.validSHA256),
              findingKinds == findingKinds.sorted(), Set(findingKinds).count == findingKinds.count,
              (disposition == .pass) == findingKinds.isEmpty else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        self.schemaVersion = schemaVersion
        self.detectorID = detectorID
        self.detectorVersion = detectorVersion
        self.audience = audience
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.policySHA256 = policySHA256
        self.cardSHA256 = cardSHA256
        self.semanticText = semanticText
        self.semanticTextSHA256 = semanticTextSHA256
        self.composedOutput = composedOutput
        self.composedOutputSHA256 = composedOutputSHA256
        self.disposition = disposition
        self.findingKinds = findingKinds
        try validate()
    }
}

struct FinalAudiencePrivacyConfirmationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let confirmationID: String
    let workspaceID: String
    let outputScopeID: String
    let profileID: String
    let sourceSnapshotSHA256: String
    let profileSHA256: String
    let privacyTransformSHA256: String
    let reviewedMarkupSHA256: String
    let semanticSHA256: String
    let semanticTextSHA256: String
    let cardSHA256: String
    let card: EvidenceDetailCardV1
    let audience: ReportAudienceV1
    let localeIdentifier: String
    let displayProfileID: String
    let rendererVersion: String
    let audiencePrivacyPolicyID: String
    let audiencePrivacyPolicyVersion: Int
    let audiencePrivacyPolicySHA256: String
    let composedOutputSHA256: String
    let privacyTransformAppliedBeforeMarkup: Bool
    let userConfirmedExactComposedBytes: Bool
    let detectorID: String
    let detectorVersion: Int
    let detectorDisposition: AudiencePrivacyDetectorDispositionV1
    let detection: PostMarkupAudiencePrivacyDetectionV1
    let captureTimeVerified: Bool
    let locationVerified: Bool
    let personVerified: Bool
    let deliveryVerified: Bool
    let approvalVerified: Bool
    let securityVerified: Bool
    let historicalRewriteClaimed: Bool

    init(
        confirmationID: String,
        sourceSnapshotSHA256: String,
        semanticSHA256: String,
        composedOutputSHA256: String,
        card: EvidenceDetailCardV1,
        detection: PostMarkupAudiencePrivacyDetectionV1,
        userConfirmedExactComposedBytes: Bool
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let cardSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(card))
        guard SnapshotProjectionValidationV1.validID(confirmationID),
              [sourceSnapshotSHA256, semanticSHA256, composedOutputSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              userConfirmedExactComposedBytes,
              detection.disposition == .pass,
              detection.findingKinds.isEmpty,
              detection.audience == card.audience,
              detection.policyID == card.audiencePrivacyPolicyID,
              detection.policyVersion == card.audiencePrivacyPolicyVersion,
              detection.policySHA256 == card.audiencePrivacyPolicySHA256,
              detection.cardSHA256 == cardSHA256,
              detection.composedOutputSHA256 == composedOutputSHA256 else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        schemaVersion = Self.schemaVersion
        self.confirmationID = confirmationID
        workspaceID = card.workspaceID
        outputScopeID = card.outputScopeID
        profileID = card.profileID
        self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        profileSHA256 = card.profileSHA256
        privacyTransformSHA256 = card.privacyTransformedSHA256
        reviewedMarkupSHA256 = card.reviewedMarkupSHA256
        self.semanticSHA256 = semanticSHA256
        semanticTextSHA256 = detection.semanticTextSHA256
        self.cardSHA256 = cardSHA256
        self.card = card
        audience = card.audience
        localeIdentifier = card.localeIdentifier
        displayProfileID = card.displayProfileID
        rendererVersion = card.rendererVersion
        audiencePrivacyPolicyID = card.audiencePrivacyPolicyID
        audiencePrivacyPolicyVersion = card.audiencePrivacyPolicyVersion
        audiencePrivacyPolicySHA256 = card.audiencePrivacyPolicySHA256
        self.composedOutputSHA256 = composedOutputSHA256
        privacyTransformAppliedBeforeMarkup = true
        self.userConfirmedExactComposedBytes = userConfirmedExactComposedBytes
        detectorID = detection.detectorID
        detectorVersion = detection.detectorVersion
        detectorDisposition = detection.disposition
        self.detection = detection
        captureTimeVerified = false
        locationVerified = false
        personVerified = false
        deliveryVerified = false
        approvalVerified = false
        securityVerified = false
        historicalRewriteClaimed = false
        try validate()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, confirmationID, workspaceID, outputScopeID, profileID, sourceSnapshotSHA256
        case profileSHA256, privacyTransformSHA256, reviewedMarkupSHA256, semanticSHA256, semanticTextSHA256
        case cardSHA256, card, audience
        case localeIdentifier, displayProfileID, rendererVersion
        case audiencePrivacyPolicyID, audiencePrivacyPolicyVersion, audiencePrivacyPolicySHA256
        case composedOutputSHA256, privacyTransformAppliedBeforeMarkup, userConfirmedExactComposedBytes
        case detectorID, detectorVersion, detectorDisposition, detection, captureTimeVerified, locationVerified
        case personVerified, deliveryVerified, approvalVerified, securityVerified, historicalRewriteClaimed
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        confirmationID = try values.decode(String.self, forKey: .confirmationID)
        workspaceID = try values.decode(String.self, forKey: .workspaceID)
        outputScopeID = try values.decode(String.self, forKey: .outputScopeID)
        profileID = try values.decode(String.self, forKey: .profileID)
        sourceSnapshotSHA256 = try values.decode(String.self, forKey: .sourceSnapshotSHA256)
        profileSHA256 = try values.decode(String.self, forKey: .profileSHA256)
        privacyTransformSHA256 = try values.decode(String.self, forKey: .privacyTransformSHA256)
        reviewedMarkupSHA256 = try values.decode(String.self, forKey: .reviewedMarkupSHA256)
        semanticSHA256 = try values.decode(String.self, forKey: .semanticSHA256)
        semanticTextSHA256 = try values.decode(String.self, forKey: .semanticTextSHA256)
        cardSHA256 = try values.decode(String.self, forKey: .cardSHA256)
        card = try values.decode(EvidenceDetailCardV1.self, forKey: .card)
        audience = try values.decode(ReportAudienceV1.self, forKey: .audience)
        localeIdentifier = try values.decode(String.self, forKey: .localeIdentifier)
        displayProfileID = try values.decode(String.self, forKey: .displayProfileID)
        rendererVersion = try values.decode(String.self, forKey: .rendererVersion)
        audiencePrivacyPolicyID = try values.decode(String.self, forKey: .audiencePrivacyPolicyID)
        audiencePrivacyPolicyVersion = try values.decode(Int.self, forKey: .audiencePrivacyPolicyVersion)
        audiencePrivacyPolicySHA256 = try values.decode(String.self, forKey: .audiencePrivacyPolicySHA256)
        composedOutputSHA256 = try values.decode(String.self, forKey: .composedOutputSHA256)
        privacyTransformAppliedBeforeMarkup = try values.decode(Bool.self, forKey: .privacyTransformAppliedBeforeMarkup)
        userConfirmedExactComposedBytes = try values.decode(Bool.self, forKey: .userConfirmedExactComposedBytes)
        detectorID = try values.decode(String.self, forKey: .detectorID)
        detectorVersion = try values.decode(Int.self, forKey: .detectorVersion)
        detectorDisposition = try values.decode(AudiencePrivacyDetectorDispositionV1.self, forKey: .detectorDisposition)
        detection = try values.decode(PostMarkupAudiencePrivacyDetectionV1.self, forKey: .detection)
        captureTimeVerified = try values.decode(Bool.self, forKey: .captureTimeVerified)
        locationVerified = try values.decode(Bool.self, forKey: .locationVerified)
        personVerified = try values.decode(Bool.self, forKey: .personVerified)
        deliveryVerified = try values.decode(Bool.self, forKey: .deliveryVerified)
        approvalVerified = try values.decode(Bool.self, forKey: .approvalVerified)
        securityVerified = try values.decode(Bool.self, forKey: .securityVerified)
        historicalRewriteClaimed = try values.decode(Bool.self, forKey: .historicalRewriteClaimed)
        let ids = [confirmationID, workspaceID, outputScopeID, profileID, displayProfileID, rendererVersion,
                   audiencePrivacyPolicyID, detectorID]
        let digests = [sourceSnapshotSHA256, profileSHA256, privacyTransformSHA256, reviewedMarkupSHA256,
                       semanticSHA256, semanticTextSHA256, cardSHA256,
                       audiencePrivacyPolicySHA256, composedOutputSHA256]
        guard schemaVersion == Self.schemaVersion, ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              digests.allSatisfy(KernelCanonicalHashV1.validSHA256),
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              audiencePrivacyPolicyVersion > 0, detectorVersion > 0,
              detection.detectorID == detectorID,
              detection.detectorVersion == detectorVersion,
              detection.disposition == detectorDisposition,
              detection.policyID == audiencePrivacyPolicyID,
              detection.policyVersion == audiencePrivacyPolicyVersion,
              detection.policySHA256 == audiencePrivacyPolicySHA256,
              detection.cardSHA256 == cardSHA256,
              detection.audience == audience,
              detection.semanticTextSHA256 == semanticTextSHA256,
              detection.composedOutputSHA256 == composedOutputSHA256,
              !card.audiencePrivacyPolicy.containsProhibitedCanary(in: [detection.semanticText]),
              card.workspaceID == workspaceID,
              card.outputScopeID == outputScopeID,
              card.profileID == profileID,
              card.profileSHA256 == profileSHA256,
              card.privacyTransformedSHA256 == privacyTransformSHA256,
              card.reviewedMarkupSHA256 == reviewedMarkupSHA256,
              card.audience == audience,
              privacyTransformAppliedBeforeMarkup, userConfirmedExactComposedBytes,
              detectorDisposition == .pass,
              !captureTimeVerified, !locationVerified, !personVerified, !deliveryVerified,
              !approvalVerified, !securityVerified, !historicalRewriteClaimed else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        try validate()
    }
}

struct EvidenceDetailCardRenderReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: String
    let snapshotID: String
    let cardID: String
    let outputScopeID: String
    let audience: ReportAudienceV1
    let sourceSnapshotSHA256: String
    let profileSHA256: String
    let privacyTransformSHA256: String
    let reviewedMarkupSHA256: String
    let semanticSHA256: String
    let semanticTextSHA256: String
    let composedOutputSHA256: String
    let confirmationID: String
    let confirmation: FinalAudiencePrivacyConfirmationV1
    let limitationsPresented: Bool
    let captureTimeVerified: Bool
    let locationVerified: Bool
    let personVerified: Bool

    init(
        receiptID: String,
        snapshotID: String,
        sourceSnapshotSHA256: String,
        semanticSHA256: String,
        card: EvidenceDetailCardV1,
        composedOutputSHA256: String,
        confirmation: FinalAudiencePrivacyConfirmationV1
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let cardSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(card))
        guard [receiptID, snapshotID].allSatisfy(SnapshotProjectionValidationV1.validID),
              [sourceSnapshotSHA256, semanticSHA256, composedOutputSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              confirmation.workspaceID == card.workspaceID,
              confirmation.outputScopeID == card.outputScopeID,
              confirmation.profileID == card.profileID,
              confirmation.sourceSnapshotSHA256 == sourceSnapshotSHA256,
              confirmation.profileSHA256 == card.profileSHA256,
              confirmation.privacyTransformSHA256 == card.privacyTransformedSHA256,
              confirmation.reviewedMarkupSHA256 == card.reviewedMarkupSHA256,
              confirmation.semanticSHA256 == semanticSHA256,
              confirmation.cardSHA256 == cardSHA256,
              confirmation.audience == card.audience,
              confirmation.localeIdentifier == card.localeIdentifier,
              confirmation.displayProfileID == card.displayProfileID,
              confirmation.rendererVersion == card.rendererVersion,
              confirmation.audiencePrivacyPolicyID == card.audiencePrivacyPolicyID,
              confirmation.audiencePrivacyPolicyVersion == card.audiencePrivacyPolicyVersion,
              confirmation.audiencePrivacyPolicySHA256 == card.audiencePrivacyPolicySHA256,
              confirmation.composedOutputSHA256 == composedOutputSHA256,
              confirmation.privacyTransformAppliedBeforeMarkup,
              confirmation.userConfirmedExactComposedBytes,
              confirmation.detectorDisposition == .pass else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.snapshotID = snapshotID
        cardID = card.cardID
        outputScopeID = card.outputScopeID
        audience = card.audience
        self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        profileSHA256 = card.profileSHA256
        privacyTransformSHA256 = card.privacyTransformedSHA256
        reviewedMarkupSHA256 = card.reviewedMarkupSHA256
        self.semanticSHA256 = semanticSHA256
        semanticTextSHA256 = confirmation.semanticTextSHA256
        self.composedOutputSHA256 = composedOutputSHA256
        confirmationID = confirmation.confirmationID
        self.confirmation = confirmation
        limitationsPresented = true
        captureTimeVerified = false
        locationVerified = false
        personVerified = false
        try validate()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, receiptID, snapshotID, cardID, outputScopeID, audience, sourceSnapshotSHA256
        case profileSHA256, privacyTransformSHA256, reviewedMarkupSHA256, semanticSHA256, semanticTextSHA256
        case composedOutputSHA256, confirmationID, confirmation, limitationsPresented, captureTimeVerified
        case locationVerified, personVerified
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        receiptID = try values.decode(String.self, forKey: .receiptID)
        snapshotID = try values.decode(String.self, forKey: .snapshotID)
        cardID = try values.decode(String.self, forKey: .cardID)
        outputScopeID = try values.decode(String.self, forKey: .outputScopeID)
        audience = try values.decode(ReportAudienceV1.self, forKey: .audience)
        sourceSnapshotSHA256 = try values.decode(String.self, forKey: .sourceSnapshotSHA256)
        profileSHA256 = try values.decode(String.self, forKey: .profileSHA256)
        privacyTransformSHA256 = try values.decode(String.self, forKey: .privacyTransformSHA256)
        reviewedMarkupSHA256 = try values.decode(String.self, forKey: .reviewedMarkupSHA256)
        semanticSHA256 = try values.decode(String.self, forKey: .semanticSHA256)
        semanticTextSHA256 = try values.decode(String.self, forKey: .semanticTextSHA256)
        composedOutputSHA256 = try values.decode(String.self, forKey: .composedOutputSHA256)
        confirmationID = try values.decode(String.self, forKey: .confirmationID)
        confirmation = try values.decode(FinalAudiencePrivacyConfirmationV1.self, forKey: .confirmation)
        limitationsPresented = try values.decode(Bool.self, forKey: .limitationsPresented)
        captureTimeVerified = try values.decode(Bool.self, forKey: .captureTimeVerified)
        locationVerified = try values.decode(Bool.self, forKey: .locationVerified)
        personVerified = try values.decode(Bool.self, forKey: .personVerified)
        guard schemaVersion == Self.schemaVersion,
              [receiptID, snapshotID, cardID, outputScopeID, confirmationID]
                .allSatisfy(SnapshotProjectionValidationV1.validID),
              [sourceSnapshotSHA256, profileSHA256, privacyTransformSHA256, reviewedMarkupSHA256,
               semanticSHA256, semanticTextSHA256, composedOutputSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              confirmation.confirmationID == confirmationID,
              confirmation.card.cardID == cardID,
              confirmation.outputScopeID == outputScopeID,
              confirmation.audience == audience,
              confirmation.sourceSnapshotSHA256 == sourceSnapshotSHA256,
              confirmation.profileSHA256 == profileSHA256,
              confirmation.privacyTransformSHA256 == privacyTransformSHA256,
              confirmation.reviewedMarkupSHA256 == reviewedMarkupSHA256,
              confirmation.semanticSHA256 == semanticSHA256,
              confirmation.semanticTextSHA256 == semanticTextSHA256,
              confirmation.composedOutputSHA256 == composedOutputSHA256,
              limitationsPresented, !captureTimeVerified, !locationVerified, !personVerified else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try validate()
    }
}

enum EvidenceDetailComposerV1 {
    static func privacyTransform(
        fields: [EvidenceDetailFieldV1],
        profile: EvidenceDetailCardProfileV1
    ) throws -> (fields: [EvidenceDetailFieldV1], digest: String) {
        let selected = fields.filter { profile.includedFieldIDs.contains($0.fieldID) }
        let transformed: [EvidenceDetailFieldV1]
        switch profile.audience {
        case .internalUse:
            transformed = selected
        case .customerSafe:
            transformed = selected.filter { $0.sensitivity == .audienceSafe }
        }
        let sorted = transformed.sorted()
        guard !sorted.isEmpty, Set(sorted.map(\.fieldID)).count == sorted.count else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(sorted)
        return (sorted, KernelCanonicalHashV1.sha256(data))
    }

    static func compose(
        cardID: String,
        workspaceID: String,
        evidenceID: String,
        fields: [EvidenceDetailFieldV1],
        profile: EvidenceDetailCardProfileV1,
        markupID: String,
        annotations: [String],
        referenceLabels: [String],
        outputReferences: [OutputScopedContentReferenceV1]
    ) throws -> EvidenceDetailCardV1 {
        let transformed = try privacyTransform(fields: fields, profile: profile)
        let markup = try ReviewedEvidenceMarkupV1(
            markupID: markupID,
            sourcePrivacyDigest: transformed.digest,
            orderedAnnotations: annotations,
            orderedReferenceLabels: referenceLabels
        )
        return try EvidenceDetailCardV1(
            cardID: cardID,
            workspaceID: workspaceID,
            evidenceID: evidenceID,
            profile: profile,
            privacyTransformedSHA256: transformed.digest,
            reviewedMarkup: markup,
            fields: transformed.fields,
            outputReferences: outputReferences
        )
    }

    static func detectPostMarkupPrivacy(
        card: EvidenceDetailCardV1,
        policy: AudiencePrivacyPolicyV1,
        semanticText: String,
        composedOutput: Data,
        detectorID: String,
        detectorVersion: Int
    ) throws -> PostMarkupAudiencePrivacyDetectionV1 {
        try PostMarkupAudiencePrivacyDetectionV1(
            detectorID: detectorID,
            detectorVersion: detectorVersion,
            policy: policy,
            card: card,
            semanticText: semanticText,
            composedOutput: composedOutput
        )
    }
}

extension AudiencePrivacyPolicyV1 {
    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SnapshotProjectionValidationV1.validID(policyID), policyVersion > 0,
              audience != .customerSafe || !prohibitedCanaries.isEmpty,
              prohibitedCanaries == prohibitedCanaries.sorted(),
              Set(prohibitedCanaries).count == prohibitedCanaries.count,
              prohibitedCanaries.allSatisfy(SnapshotProjectionValidationV1.validText),
              policySHA256 == (try Self.digest(
                policyID: policyID,
                policyVersion: policyVersion,
                audience: audience,
                prohibitedCanaries: prohibitedCanaries
              )) else { throw SnapshotProjectionFailureV1.missingBinding }
    }

    func containsProhibitedCanary(in values: [String]) -> Bool {
        let canaries = prohibitedCanaries.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        return values.contains { value in
            let folded = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return canaries.contains(where: folded.contains)
        }
    }
}

extension EvidenceDetailFieldV1 {
    func validate() throws {
        guard SnapshotProjectionValidationV1.validID(fieldID),
              SnapshotProjectionValidationV1.validText(label),
              SnapshotProjectionValidationV1.validText(value) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

extension EvidenceDetailCardProfileV1 {
    func validate() throws {
        try audiencePrivacyPolicy.validate()
        let ids = [profileID, outputScopeID, privacyTransformID, markupProfileID, displayProfileID, rendererVersion]
        guard schemaVersion == Self.schemaVersion,
              ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              profileRelease > 0, privacyTransformVersion > 0, markupProfileVersion > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              audiencePrivacyPolicy.audience == audience,
              !includedFieldIDs.isEmpty, includedFieldIDs == includedFieldIDs.sorted(),
              Set(includedFieldIDs).count == includedFieldIDs.count,
              includedFieldIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              SnapshotProjectionValidationV1.validText(limitationsText),
              limitationsText.contains("does not verify capture time, location, or person") else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

extension ReviewedEvidenceMarkupV1 {
    func validate() throws {
        guard SnapshotProjectionValidationV1.validID(markupID),
              KernelCanonicalHashV1.validSHA256(sourcePrivacyDigest),
              orderedAnnotations.count <= 128, orderedReferenceLabels.count <= 256,
              orderedAnnotations.allSatisfy(SnapshotProjectionValidationV1.validText),
              orderedReferenceLabels.allSatisfy(SnapshotProjectionValidationV1.validText) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

extension EvidenceDetailCardV1 {
    func validate() throws {
        try profile.validate()
        try audiencePrivacyPolicy.validate()
        try reviewedMarkup.validate()
        try fields.forEach { try $0.validate() }
        try outputReferences.forEach { try $0.validate() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expectedProfileSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(profile))
        let expectedPrivacySHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(fields))
        let expectedMarkupSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(reviewedMarkup))
        let ids = [cardID, workspaceID, evidenceID, outputScopeID, profileID, privacyTransformID,
                   displayProfileID, rendererVersion, audiencePrivacyPolicyID, reviewedMarkupID]
        guard schemaVersion == Self.schemaVersion,
              ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              privacyTransformVersion > 0, audiencePrivacyPolicyVersion > 0,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              profileSHA256 == expectedProfileSHA256,
              privacyTransformedSHA256 == expectedPrivacySHA256,
              reviewedMarkupSHA256 == expectedMarkupSHA256,
              [profileSHA256, audiencePrivacyPolicySHA256, privacyTransformedSHA256, reviewedMarkupSHA256]
                .allSatisfy(KernelCanonicalHashV1.validSHA256),
              profile.profileID == profileID,
              profile.outputScopeID == outputScopeID,
              profile.audience == audience,
              profile.privacyTransformID == privacyTransformID,
              profile.privacyTransformVersion == privacyTransformVersion,
              profile.localeIdentifier == localeIdentifier,
              profile.displayProfileID == displayProfileID,
              profile.rendererVersion == rendererVersion,
              profile.audiencePrivacyPolicy == audiencePrivacyPolicy,
              fields.allSatisfy({ profile.includedFieldIDs.contains($0.fieldID) }),
              reviewedMarkup.markupID == reviewedMarkupID,
              reviewedMarkup.sourcePrivacyDigest == privacyTransformedSHA256,
              reviewedMarkup.orderedAnnotations == annotations,
              reviewedMarkup.orderedReferenceLabels == referenceLabels,
              audiencePrivacyPolicy.policyID == audiencePrivacyPolicyID,
              audiencePrivacyPolicy.policyVersion == audiencePrivacyPolicyVersion,
              audiencePrivacyPolicy.policySHA256 == audiencePrivacyPolicySHA256,
              audiencePrivacyPolicy.audience == audience,
              !fields.isEmpty, fields == fields.sorted(), Set(fields.map(\.fieldID)).count == fields.count,
              outputReferences == outputReferences.sorted(),
              Set(outputReferences.map(\.outputReferenceID)).count == outputReferences.count,
              referenceLabels.count == outputReferences.count,
              annotations.count <= 128, referenceLabels.count <= 256,
              (annotations + referenceLabels + [limitationsText]).allSatisfy(SnapshotProjectionValidationV1.validText),
              outputReferences.allSatisfy({
                let namespace = KernelCanonicalHashV1.sha256(
                    Data("\(workspaceID)|\(outputScopeID)|\($0.contentSHA256)".utf8)
                )
                let expectedPrefix = "out-\(namespace.prefix(16))-"
                return $0.outputScopeID == outputScopeID
                    && $0.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(
                        Data("\(workspaceID)|\(outputScopeID)".utf8)
                    )
                    && $0.outputReferenceID.hasPrefix(expectedPrefix)
                    && SnapshotProjectionValidationV1.validID($0.outputReferenceID)
                    && KernelCanonicalHashV1.validSHA256($0.workspaceBindingSHA256)
                    && KernelCanonicalHashV1.validSHA256($0.contentSHA256)
                    && SnapshotProjectionValidationV1.validText($0.mediaType)
              }) else { throw SnapshotProjectionFailureV1.invalidValue }
        if audience == .customerSafe,
           (fields.contains(where: { $0.sensitivity != .audienceSafe })
            || outputReferences.contains(where: { $0.byteRole != .derivative })
            || audiencePrivacyPolicy.containsProhibitedCanary(
                in: fields.flatMap { [$0.label, $0.value] } + annotations + referenceLabels + [limitationsText]
            )
            || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                in: fields.flatMap { [$0.label, $0.value] } + annotations + referenceLabels + [limitationsText]
            )) {
            throw SnapshotProjectionFailureV1.privacyViolation
        }

        let functionalRelationshipText = fields
            .filter { AudiencePrivacyLexicalDetectorV1.isFunctionalRelationshipFieldID($0.fieldID) }
            .flatMap { [$0.label, $0.value] }
        if audience == .customerSafe,
           !functionalRelationshipText.isEmpty,
           AudiencePrivacyLexicalDetectorV1.containsProhibitedFunctionalRelationshipClaim(
               in: functionalRelationshipText + annotations + referenceLabels + [limitationsText]
           ) {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

// MARK: - C23 field-reference report guard

/// Evidence cards may carry the C23 projection as bounded report metadata.
/// This guard keeps restricted reference material, locators, license notices,
/// and bound-subject identity out of the card projection.
enum EvidenceDetailFieldReferenceProjectionGuardV1 {
    static let metadataOnly = true
    static let excludesReferenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true
    static let excludesObservationClaims = true
    static let excludesComplianceClaims = true

    static func validate(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> FieldReferenceReportProjectionV1 {
        try projection.validate()
        guard metadataOnly,
              excludesReferenceBytes,
              excludesPrivateLocators,
              excludesLicenseSecrets,
              excludesSubjectIdentity,
              excludesObservationClaims,
              excludesComplianceClaims,
              projection.restrictedContentOmitted,
              !FieldReferenceLocalizationPolicyV1.containsProhibitedClaim(
                  in: [
                      FieldReferenceLocalizationKeyV1.heading.englishDefaultValue,
                      FieldReferenceLocalizationKeyV1.nextStep.englishDefaultValue,
                  ]
              ),
              !FieldReferenceLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: [FieldReferenceLocalizationKeyV1.heading.englishDefaultValue]
              ) else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return projection
    }

    static func accessibilityIDs() -> [String] {
        FieldReferenceAccessibilityPolicyV1.semanticIDs.sorted()
    }
}

extension EvidenceDetailCardV1 {
    func c23ValidateFieldReferenceProjection(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> FieldReferenceReportProjectionV1 {
        try EvidenceDetailFieldReferenceProjectionGuardV1.validate(projection)
    }
}

// MARK: - C21 capability admission card guard

enum EvidenceDetailClientCapabilityProjectionGuardV1 {
    static let metadataOnly = true
    static let closedAdmissionValuesOnly = true
    static let immutableHistoricDisplay = true
    static let excludesDeviceIdentity = true
    static let excludesUserIdentity = true
    static let excludesEndpointProviderAccount = true
    static let excludesRemoteDeliveryAcknowledgement = true
    static let excludesPackagePayload = true

    static func validate(
        _ projection: ClientCapabilityReportProjectionV1,
        audience: ReportAudienceV1 = .customerSafe
    ) throws {
        try projection.validate()
        guard metadataOnly,
              closedAdmissionValuesOnly,
              immutableHistoricDisplay,
              excludesDeviceIdentity,
              excludesUserIdentity,
              excludesEndpointProviderAccount,
              excludesRemoteDeliveryAcknowledgement,
              excludesPackagePayload,
              !ClientCapabilityLocalizationPolicyV1.containsProhibitedClaim(
                  in: [
                      ClientCapabilityLocalizationKeyV1.heading.englishDefaultValue,
                      ClientCapabilityLocalizationKeyV1.nextStep.englishDefaultValue,
                  ]
              ),
              !ClientCapabilityLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: [ClientCapabilityLocalizationKeyV1.heading.englishDefaultValue]
              ) else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        guard audience == .customerSafe || audience == .internalUse else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

extension EvidenceDetailCardV1 {
    func c21ValidateClientCapabilityProjection(
        _ projection: ClientCapabilityReportProjectionV1,
        operation: PackageLifecycleOperationV1 = .view,
        allowsWrite: Bool = false
    ) throws -> ClientCapabilityReportProjectionV1 {
        try EvidenceDetailClientCapabilityProjectionGuardV1.validate(
            projection,
            audience: audience
        )
        try ClientCapabilityReportConsumerPolicyV1.require(
            projection,
            operation: operation,
            allowsWrite: allowsWrite
        )
        return projection
    }
}

extension PostMarkupAudiencePrivacyDetectionV1 {
    func validate() throws {
        let composedText = String(decoding: composedOutput, as: UTF8.self)
        guard schemaVersion == Self.schemaVersion,
              SnapshotProjectionValidationV1.validID(detectorID), detectorVersion > 0,
              SnapshotProjectionValidationV1.validID(policyID), policyVersion > 0,
              SnapshotProjectionValidationV1.validText(semanticText),
              semanticTextSHA256 == KernelCanonicalHashV1.sha256(Data(semanticText.utf8)),
              !composedOutput.isEmpty,
              composedOutput.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              composedOutputSHA256 == KernelCanonicalHashV1.sha256(composedOutput),
              (!AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: [semanticText, composedText])
                || (disposition == .blocked && findingKinds.contains(.prohibitedSemanticText))),
              [policySHA256, cardSHA256, semanticTextSHA256, composedOutputSHA256]
                .allSatisfy(KernelCanonicalHashV1.validSHA256),
              findingKinds == findingKinds.sorted(), Set(findingKinds).count == findingKinds.count,
              (disposition == .pass) == findingKinds.isEmpty else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }

    func validate(card: EvidenceDetailCardV1) throws {
        try validate()
        let fieldText = card.fields.flatMap { [$0.label, $0.value] }
        let composedText = String(decoding: composedOutput, as: UTF8.self)
        var expected = Set<AudiencePrivacyFindingKindV1>()
        if card.audience == .customerSafe {
            if card.fields.contains(where: { $0.sensitivity != .audienceSafe })
                || card.audiencePrivacyPolicy.containsProhibitedCanary(in: fieldText)
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: fieldText) {
                expected.insert(.prohibitedField)
            }
            if card.audiencePrivacyPolicy.containsProhibitedCanary(in: card.annotations)
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: card.annotations) {
                expected.insert(.prohibitedAnnotation)
            }
            if card.audiencePrivacyPolicy.containsProhibitedCanary(in: card.referenceLabels)
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: card.referenceLabels) {
                expected.insert(.prohibitedReferenceLabel)
            }
            if card.audiencePrivacyPolicy.containsProhibitedCanary(in: [semanticText, composedText])
                || AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: [semanticText, composedText]) {
                expected.insert(.prohibitedSemanticText)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard audience == card.audience,
              policyID == card.audiencePrivacyPolicyID,
              policyVersion == card.audiencePrivacyPolicyVersion,
              policySHA256 == card.audiencePrivacyPolicySHA256,
              cardSHA256 == KernelCanonicalHashV1.sha256(try encoder.encode(card)),
              findingKinds == expected.sorted(),
              (disposition == .pass) == expected.isEmpty else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

extension FinalAudiencePrivacyConfirmationV1 {
    func validate() throws {
        try card.validate()
        try detection.validate(card: card)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expectedCardSHA256 = KernelCanonicalHashV1.sha256(try encoder.encode(card))
        let ids = [confirmationID, workspaceID, outputScopeID, profileID, displayProfileID, rendererVersion,
                   audiencePrivacyPolicyID, detectorID]
        let digests = [sourceSnapshotSHA256, profileSHA256, privacyTransformSHA256, reviewedMarkupSHA256,
                       semanticSHA256, semanticTextSHA256, cardSHA256,
                       audiencePrivacyPolicySHA256, composedOutputSHA256]
        guard schemaVersion == Self.schemaVersion, ids.allSatisfy(SnapshotProjectionValidationV1.validID),
              digests.allSatisfy(KernelCanonicalHashV1.validSHA256),
              cardSHA256 == expectedCardSHA256,
              SnapshotProjectionValidationV1.validText(localeIdentifier), localeIdentifier.utf8.count <= 64,
              audiencePrivacyPolicyVersion > 0, detectorVersion > 0,
              detection.detectorID == detectorID,
              detection.detectorVersion == detectorVersion,
              detection.disposition == detectorDisposition,
              detection.policyID == audiencePrivacyPolicyID,
              detection.policyVersion == audiencePrivacyPolicyVersion,
              detection.policySHA256 == audiencePrivacyPolicySHA256,
              detection.cardSHA256 == cardSHA256,
              detection.audience == audience,
              detection.semanticTextSHA256 == semanticTextSHA256,
              detection.composedOutputSHA256 == composedOutputSHA256,
              !card.audiencePrivacyPolicy.containsProhibitedCanary(in: [detection.semanticText]),
              card.workspaceID == workspaceID,
              card.outputScopeID == outputScopeID,
              card.profileID == profileID,
              card.profileSHA256 == profileSHA256,
              card.privacyTransformedSHA256 == privacyTransformSHA256,
              card.reviewedMarkupSHA256 == reviewedMarkupSHA256,
              card.audience == audience,
              privacyTransformAppliedBeforeMarkup, userConfirmedExactComposedBytes,
              detectorDisposition == .pass,
              !captureTimeVerified, !locationVerified, !personVerified, !deliveryVerified,
              !approvalVerified, !securityVerified, !historicalRewriteClaimed else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

extension EvidenceDetailCardRenderReceiptV1 {
    func validate() throws {
        try confirmation.validate()
        guard schemaVersion == Self.schemaVersion,
              [receiptID, snapshotID, cardID, outputScopeID, confirmationID]
                .allSatisfy(SnapshotProjectionValidationV1.validID),
              [sourceSnapshotSHA256, profileSHA256, privacyTransformSHA256, reviewedMarkupSHA256,
               semanticSHA256, semanticTextSHA256, composedOutputSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              confirmation.confirmationID == confirmationID,
              confirmation.card.cardID == cardID,
              confirmation.outputScopeID == outputScopeID,
              confirmation.audience == audience,
              confirmation.sourceSnapshotSHA256 == sourceSnapshotSHA256,
              confirmation.profileSHA256 == profileSHA256,
              confirmation.privacyTransformSHA256 == privacyTransformSHA256,
              confirmation.reviewedMarkupSHA256 == reviewedMarkupSHA256,
              confirmation.semanticSHA256 == semanticSHA256,
              confirmation.semanticTextSHA256 == semanticTextSHA256,
              confirmation.composedOutputSHA256 == composedOutputSHA256,
              limitationsPresented, !captureTimeVerified, !locationVerified, !personVerified else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

/// Boundary guard used by the C13 report projector.  A card is renderable
/// only when its evidence identity is explicitly included by the assurance
/// link for the requested audience; omitted links expose only their typed
/// limitation and never their card content.
enum EvidenceDetailAssuranceProjectionGuardV1 {
    static func validateIncludedCard(
        _ card: EvidenceDetailCardV1,
        link: ClaimEvidenceLinkV1,
        audience: EvidenceAudienceV1
    ) throws {
        try card.validate()
        try link.validate(visibility: link.visibility)
        guard audience == .internalReview || card.audience == .customerSafe,
              link.decision.audience == audience,
              link.decision.disposition == .included,
              link.evidenceID == card.evidenceID,
              UUID(uuidString: card.workspaceID) == link.workspaceID.rawValue else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        if audience == .customerReport {
            guard card.fields.allSatisfy({ $0.sensitivity == .audienceSafe }),
                  card.outputReferences.allSatisfy({ $0.byteRole == .derivative }),
                  !card.audiencePrivacyPolicy.containsProhibitedCanary(
                    in: card.fields.flatMap { [$0.label, $0.value] }
                        + card.annotations + card.referenceLabels + [card.limitationsText]
                  ),
                  !AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(
                    in: card.fields.flatMap { [$0.label, $0.value] }
                        + card.annotations + card.referenceLabels + [card.limitationsText]
                  ) else {
                throw SnapshotProjectionFailureV1.privacyViolation
            }
        }
    }

    static func omissionLabel(for link: ClaimEvidenceLinkV1) -> String {
        "Evidence omitted: \(link.decision.limitation.rawValue)"
    }
}

/// C14 review/change/action evidence references remain bounded to the frozen
/// completed-snapshot boundary. This guard is deliberately separate from the
/// customer-facing card guard: a review history may retain exact provenance
/// digests, but it must never make actor snapshots, reasons, or raw evidence
/// content renderable as a detail card.
enum EvidenceDetailInspectionReviewProjectionGuardV1 {
    static let excludesActorPrivateDetail = true
    static let excludesReviewReasons = true
    static let excludesEvidenceContent = true
    static let requiresExactC13Binding = true

    static func validateHistory(
        _ history: CompletedInspectionReviewHistorySnapshotV1,
        assurance: ReportEvidenceAssuranceProjectionV1?
    ) throws {
        try history.validate()
        let allowedDigests: Set<String> = [
            history.binding.completedSnapshotSHA256,
            history.binding.c13AssuranceSHA256,
            history.binding.c38AccountabilitySHA256,
            history.binding.c40AuthorityCriterionSHA256,
            history.binding.c41FunctionalRelationshipsSHA256,
        ]
        for request in history.changeRequests {
            if let resolution = request.resolution {
                for reference in resolution.evidence {
                    try validateReference(
                        reference,
                        history: history,
                        assurance: assurance,
                        allowedDigests: allowedDigests
                    )
                }
            }
        }
        for action in history.correctiveActions {
            for reference in action.closureEvidence {
                try validateReference(
                    reference,
                    history: history,
                    assurance: assurance,
                    allowedDigests: allowedDigests
                )
            }
        }
    }

    private static func validateReference(
        _ reference: ReviewEvidenceReferenceV1,
        history: CompletedInspectionReviewHistorySnapshotV1,
        assurance: ReportEvidenceAssuranceProjectionV1?,
        allowedDigests: Set<String>
    ) throws {
        try reference.validate()
        guard allowedDigests.contains(reference.sha256) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        guard reference.kind == .claimEvidenceLink else { return }
        guard let assurance else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        try assurance.validate()
        let links = assurance.preview.includedLinks + assurance.preview.excludedLinks
        guard links.contains(where: { link in
            let referenceMatches = reference.referenceID == link.linkID.uuidString.lowercased()
                || reference.referenceID == (link.evidenceID ?? "")
            let digestMatches = reference.sha256 == link.linkSHA256
                || reference.sha256 == (link.evidenceSHA256 ?? "")
            return referenceMatches && digestMatches
                && link.workspaceID == history.workspaceID
                && reference.revision == link.revision
        }) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
    }
}

/// C15 packet coordination is provenance for a report, not evidence detail.
/// Keep this boundary explicit so a packet projection cannot accidentally make
/// actor snapshots, lease data, result links, or collision digests renderable
/// as an evidence card.
enum EvidenceDetailWorkPacketProjectionGuardV1 {
    static let excludesActorPrivateDetail = true
    static let excludesLeaseAndClaimData = true
    static let excludesResultAndEvidenceContent = true
    static let excludesAuthorizationAndTelemetry = true

    static func validate(
        _ projection: ReportWorkPacketProjectionV1,
        sourceSnapshotSHA256: String
    ) throws {
        try projection.validate()
        guard KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256),
              projection.sourceSnapshotSHA256 == sourceSnapshotSHA256,
              excludesActorPrivateDetail,
              excludesLeaseAndClaimData,
              excludesResultAndEvidenceContent,
              excludesAuthorizationAndTelemetry else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

/// C19 measurement detail is a value/provenance summary, never a raw
/// evidence-card escape hatch. The projection omits the operator snapshot,
/// opaque serial, response payload, and content references before rendering.
enum EvidenceDetailMeasurementIntegrityProjectionGuardV1 {
    static let excludesOpaqueSerial = true
    static let excludesOperatorIdentity = true
    static let excludesRawResponse = true
    static let excludesEvidenceLocators = true
    static let excludesUnsupportedClaims = true
    static let requiresExactFixedPointValues = true

    static func validate(
        _ projection: MeasurementIntegrityReportProjectionV1,
        audience: ReportAudienceV1 = .customerSafe
    ) throws {
        try projection.validate()
        guard excludesOpaqueSerial, excludesOperatorIdentity, excludesRawResponse,
              excludesEvidenceLocators, excludesUnsupportedClaims,
              requiresExactFixedPointValues,
              !MeasurementIntegrityLocalizationPolicyV1.containsProhibitedClaim(
                  in: displayFacts(projection, audience: audience)
              ),
              !MeasurementIntegrityLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: displayFacts(projection, audience: audience)
              ) else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }

    private static func displayFacts(
        _ projection: MeasurementIntegrityReportProjectionV1,
        audience: ReportAudienceV1
    ) -> [String] {
        var values = [
            MeasurementIntegrityLocalizationKeyV1.heading.englishDefaultValue,
            MeasurementIntegrityLocalizationKeyV1.captureValue.englishDefaultValue,
            MeasurementIntegrityLocalizationKeyV1.captureUnit.englishDefaultValue,
            projection.enteredUnitID,
            projection.canonicalUnitID,
            audience.rawValue,
        ]
        if let result = projection.qualityResult {
            values.append(MeasurementIntegrityLocalizationKeyV1.qualityResultKey(result).englishDefaultValue)
        }
        values.append(contentsOf: projection.qualityReasonCodes.map {
            MeasurementIntegrityLocalizationKeyV1.qualityReasonKey($0).englishDefaultValue
        })
        return values
    }
}

// MARK: - C20 audience-safe derivative guard

enum EvidenceDetailPrivacyTransformProjectionGuardV1 {
    static let requiresApprovedReview = true
    static let requiresCurrentDerivative = true
    static let requiresExplicitRedactionDeclaration = true
    static let derivativeOnly = true
    static let excludesOriginalReferences = true
    static let excludesOriginalBytes = true
    static let excludesReviewerIdentity = true
    static let excludesReviewRationale = true

    static func validate(
        _ projection: PrivacyTransformReportProjectionV1,
        audience: ReportAudienceV1 = .customerSafe
    ) throws {
        try projection.validate()
        guard projection.reportAudience == audience,
              projection.isAudienceSafe,
              requiresApprovedReview,
              requiresCurrentDerivative,
              requiresExplicitRedactionDeclaration,
              derivativeOnly,
              excludesOriginalReferences,
              excludesOriginalBytes,
              excludesReviewerIdentity,
              excludesReviewRationale,
              !PrivacyTransformLocalizationPolicyV1.containsProhibitedClaim(
                  in: [PrivacyTransformLocalizationKeyV1.heading.englishDefaultValue,
                       PrivacyTransformLocalizationKeyV1.nextStep.englishDefaultValue]
              ),
              !PrivacyTransformLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: [PrivacyTransformLocalizationKeyV1.heading.englishDefaultValue]
              ) else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

extension EvidenceDetailCardV1 {
    /// Ensures an evidence card references only the approved derivative. A
    /// separate original-content authorization is intentionally not inferred.
    func c20ValidatePrivacyTransformProjection(
        _ projection: PrivacyTransformReportProjectionV1
    ) throws -> PrivacyTransformReportProjectionV1 {
        try EvidenceDetailPrivacyTransformProjectionGuardV1.validate(
            projection,
            audience: audience
        )
        guard privacyTransformedSHA256 == projection.derivativeSHA256,
              outputReferences.allSatisfy({ $0.byteRole == .derivative }) else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return projection
    }
}

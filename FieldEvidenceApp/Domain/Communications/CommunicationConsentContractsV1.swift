import Foundation

// C44 is a static contract boundary. It contains no subscriber repository,
// operational contact bridge, provider implementation, network path, or send API.

enum CommunicationConsentContractFailureV1: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidValue
    case invalidDigest
    case nonCanonicalData
    case duplicateValue
    case purposeNotEligible
    case consentNotAffirmative
    case comparisonReviewRequired
    case sourceForbidden
    case disclosureMismatch
    case invalidSuccessor
    case suppressionRequired
    case providerForbidden
    case issuanceForbidden
}

private struct CommunicationConsentDynamicCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

private enum CommunicationConsentClosedCodingV1 {
    static func require<K: CodingKey & CaseIterable>(
        _ decoder: any Decoder,
        _ keys: K.Type
    ) throws where K.AllCases: Collection {
        let expected = Set(keys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CommunicationConsentDynamicCodingKeyV1.self)
        guard Set(container.allKeys.map(\.stringValue)).isSubset(of: expected) else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
    }
}

enum CommunicationConsentCanonicalCodecV1 {
    static let maximumCanonicalByteCount = 1_048_576

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard !data.isEmpty, data.count <= maximumCanonicalByteCount else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
        return data
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumCanonicalByteCount else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        KernelCanonicalHashV1.sha256(try encode(value))
    }
}

private enum CommunicationConsentValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func uuid(_ value: UUID) throws {
        guard value != zeroUUID else { throw CommunicationConsentContractFailureV1.invalidIdentifier }
    }

    static func identifier(_ value: String, maximumBytes: Int = 160) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CommunicationConsentContractFailureV1.invalidIdentifier
        }
    }

    static func text(_ value: String, maximumBytes: Int = 4_096) throws {
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
    }

    static func exactAddress(_ value: String) throws {
        guard !value.isEmpty,
              value.utf8.count <= 512,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
    }

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
    }

    static func instant(_ value: Date) throws {
        let milliseconds = value.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds <= Double(Int64.max) else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
    }

    static func sortedUniqueIdentifiers(
        _ values: [String], maximumCount: Int, allowEmpty: Bool = false
    ) throws {
        guard values.count <= maximumCount, allowEmpty || !values.isEmpty else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
        try values.forEach(identifier)
        guard values == values.sorted(), Set(values).count == values.count else {
            throw CommunicationConsentContractFailureV1.duplicateValue
        }
    }

    static func isImmediateSuccessor(_ revision: UInt64, of predecessor: UInt64) -> Bool {
        let (expected, overflow) = predecessor.addingReportingOverflow(1)
        return !overflow && expected == revision
    }

    static func nontransactional(_ purpose: CommunicationPurposeV1) throws {
        guard purpose != .transactionalOrSupport else {
            throw CommunicationConsentContractFailureV1.purposeNotEligible
        }
    }
}

enum CommunicationPurposeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case newsletter = "NEWSLETTER"
    case productUpdate = "PRODUCT_UPDATE"
    case researchInvitation = "RESEARCH_INVITATION"
    case transactionalOrSupport = "TRANSACTIONAL_OR_SUPPORT"
}

enum CommunicationChannelV1: String, Codable, CaseIterable, Hashable, Sendable {
    case email = "EMAIL"
}

enum CommunicationCollectionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case disabledNoSubscriberCollectionOrTransmission =
        "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION"
}

enum CommunicationActivationGateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case disabledNoSubscriberCollectionOrTransmission =
        "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION"
}

enum CommunicationOwnerActivationDecisionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notProposed = "NOT_PROPOSED"
    case rejected = "REJECTED"
    case ownerAcceptedPendingSeparateImplementationCard =
        "OWNER_ACCEPTED_PENDING_SEPARATE_IMPLEMENTATION_CARD"
}

enum ContactAddressComparisonResultV1: String, Codable, CaseIterable, Hashable, Sendable {
    case exactMatch = "EXACT_MATCH"
    case distinct = "DISTINCT"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum ContactAddressCollisionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case reviewRequired = "REVIEW_REQUIRED"
}

enum CommunicationConsentEligibilityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case eligibleExplicitIndependentEnrollment = "ELIGIBLE_EXPLICIT_INDEPENDENT_ENROLLMENT"
    case reviewRequired = "REVIEW_REQUIRED"
    case ineligibleTransactionalOrSupport = "INELIGIBLE_TRANSACTIONAL_OR_SUPPORT"
    case ineligibleNonaffirmative = "INELIGIBLE_NONAFFIRMATIVE"
    case ineligibleSource = "INELIGIBLE_SOURCE"
    case ineligibleDisclosure = "INELIGIBLE_DISCLOSURE"
    case ineligibleLawfulBasis = "INELIGIBLE_LAWFUL_BASIS"
}

enum ContactSourceKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case controlledBackendAffirmativeEnrollment = "CONTROLLED_BACKEND_AFFIRMATIVE_ENROLLMENT"
    case providerHostedAffirmativeEnrollment = "PROVIDER_HOSTED_AFFIRMATIVE_ENROLLMENT"
    case separatelyAuthorizedResearchInvitationEnrollment =
        "SEPARATELY_AUTHORIZED_RESEARCH_INVITATION_ENROLLMENT"
}

enum CommunicationAffirmativeMethodV1: String, Codable, CaseIterable, Hashable, Sendable {
    case explicitUncheckedControl = "EXPLICIT_UNCHECKED_CONTROL"
    case providerHostedConfirmation = "PROVIDER_HOSTED_CONFIRMATION"
    case documentedIndependentResearchInvitationEnrollment =
        "DOCUMENTED_INDEPENDENT_RESEARCH_INVITATION_ENROLLMENT"
}

enum CommunicationActorCapacityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case documentedSelfAssertion = "DOCUMENTED_SELF_ASSERTION"
    case documentedAuthorizedRepresentativeAssertion = "DOCUMENTED_AUTHORIZED_REPRESENTATIVE_ASSERTION"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum CommunicationVerificationStatusV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unverified = "UNVERIFIED"
    case pending = "PENDING"
    case verified = "VERIFIED"
    case failed = "FAILED"
    case expired = "EXPIRED"
}

enum CommunicationLawfulBasisDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case documentedAffirmativeConsent = "DOCUMENTED_AFFIRMATIVE_CONSENT"
    case ownerReviewRequired = "OWNER_REVIEW_REQUIRED"
    case unsupported = "UNSUPPORTED"
}

enum MarketingContactStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case affirmativeEnrollmentRecorded = "AFFIRMATIVE_ENROLLMENT_RECORDED"
    case verificationPending = "VERIFICATION_PENDING"
    case verifiedPendingSeparateActivation = "VERIFIED_PENDING_SEPARATE_ACTIVATION"
    case withdrawn = "WITHDRAWN"
    case expired = "EXPIRED"
    case suppressed = "SUPPRESSED"
}

enum CommunicationPreferenceStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case enrolled = "ENROLLED"
    case withdrawn = "WITHDRAWN"
}

enum CommunicationPreferenceEvaluationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case eligiblePendingSeparateActivation = "ELIGIBLE_PENDING_SEPARATE_ACTIVATION"
    case withdrawn = "WITHDRAWN"
    case expired = "EXPIRED"
    case suppressed = "SUPPRESSED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum CommunicationWithdrawalReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case requested = "REQUESTED"
    case addressChanged = "ADDRESS_CHANGED"
    case complaint = "COMPLAINT"
    case bounce = "BOUNCE"
    case consentExpired = "CONSENT_EXPIRED"
}

enum SuppressionTokenClassificationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case contactInfoPseudonymousNotAnonymous = "CONTACT_INFO_PSEUDONYMOUS_NOT_ANONYMOUS"
}

enum SuppressionRetentionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ownerReviewedMinimumDoNotContact = "OWNER_REVIEWED_MINIMUM_DO_NOT_CONTACT"
    case ownerReviewRequired = "OWNER_REVIEW_REQUIRED"
}

enum CommunicationSuppressionEvaluationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case blocked = "BLOCKED"
    case notMatched = "NOT_MATCHED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum EmailServiceProviderBindingDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unboundNoSelectedProvider = "UNBOUND_NO_SELECTED_PROVIDER"
}

struct ExactCommunicationAddressV1: Codable, Equatable, Hashable, Sendable {
    let channel: CommunicationChannelV1
    let exactEnteredValue: String

    init(channel: CommunicationChannelV1 = .email, exactEnteredValue: String) throws {
        self.channel = channel
        self.exactEnteredValue = exactEnteredValue
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.exactAddress(exactEnteredValue)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case channel, exactEnteredValue }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            exactEnteredValue: c.decode(String.self, forKey: .exactEnteredValue)
        )
    }
}

struct ContactComparisonPolicyReferenceV1: Codable, Equatable, Hashable, Sendable {
    let policyID: UUID
    let revision: UInt64
    let policySHA256: String

    init(policyID: UUID, revision: UInt64, policySHA256: String) throws {
        self.policyID = policyID; self.revision = revision; self.policySHA256 = policySHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(policyID)
        try CommunicationConsentValidationV1.digest(policySHA256)
        guard revision > 0 else { throw CommunicationConsentContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case policyID, revision, policySHA256 }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            policyID: c.decode(UUID.self, forKey: .policyID),
            revision: c.decode(UInt64.self, forKey: .revision),
            policySHA256: c.decode(String.self, forKey: .policySHA256)
        )
    }
}

struct ContactComparisonPolicyReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let policyID: UUID
    let revision: UInt64
    let exactByteIdentityOnly: Bool
    let plusTagCollision: ContactAddressCollisionDispositionV1
    let localPartCaseCollision: ContactAddressCollisionDispositionV1
    let unicodeCollision: ContactAddressCollisionDispositionV1
    let providerCompatibilityReviewRequired: Bool
    let effectiveAt: Date
    let supersedes: ContactComparisonPolicyReferenceV1?
    let policySHA256: String

    init(
        policyID: UUID,
        revision: UInt64,
        effectiveAt: Date,
        supersedes: ContactComparisonPolicyReferenceV1? = nil
    ) throws {
        let digestBasis = Basis(
            schemaVersion: Self.schemaVersion,
            policyID: policyID,
            revision: revision,
            exactByteIdentityOnly: true,
            plusTagCollision: .reviewRequired,
            localPartCaseCollision: .reviewRequired,
            unicodeCollision: .reviewRequired,
            providerCompatibilityReviewRequired: true,
            effectiveAt: effectiveAt,
            supersedes: supersedes
        )
        schemaVersion = Self.schemaVersion; self.policyID = policyID; self.revision = revision
        exactByteIdentityOnly = true; plusTagCollision = .reviewRequired
        localPartCaseCollision = .reviewRequired; unicodeCollision = .reviewRequired
        providerCompatibilityReviewRequired = true; self.effectiveAt = effectiveAt
        self.supersedes = supersedes
        policySHA256 = try CommunicationConsentCanonicalCodecV1.sha256(digestBasis)
        try validate()
    }

    var reference: ContactComparisonPolicyReferenceV1 {
        get throws { try .init(policyID: policyID, revision: revision, policySHA256: policySHA256) }
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(policyID)
        try CommunicationConsentValidationV1.instant(effectiveAt)
        try supersedes?.validate()
        guard schemaVersion == Self.schemaVersion,
              revision > 0,
              exactByteIdentityOnly,
              plusTagCollision == .reviewRequired,
              localPartCaseCollision == .reviewRequired,
              unicodeCollision == .reviewRequired,
              providerCompatibilityReviewRequired,
              (revision == 1) == (supersedes == nil),
              policySHA256 == (try CommunicationConsentCanonicalCodecV1.sha256(basis)) else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
        if let supersedes {
            guard supersedes.policyID == policyID,
                  CommunicationConsentValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CommunicationConsentContractFailureV1.invalidSuccessor
            }
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, policyID: policyID, revision: revision,
        exactByteIdentityOnly: exactByteIdentityOnly, plusTagCollision: plusTagCollision,
        localPartCaseCollision: localPartCaseCollision, unicodeCollision: unicodeCollision,
        providerCompatibilityReviewRequired: providerCompatibilityReviewRequired,
        effectiveAt: effectiveAt, supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let policyID: UUID; let revision: UInt64
        let exactByteIdentityOnly: Bool
        let plusTagCollision: ContactAddressCollisionDispositionV1
        let localPartCaseCollision: ContactAddressCollisionDispositionV1
        let unicodeCollision: ContactAddressCollisionDispositionV1
        let providerCompatibilityReviewRequired: Bool
        let effectiveAt: Date; let supersedes: ContactComparisonPolicyReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, policyID, revision, exactByteIdentityOnly, plusTagCollision
        case localPartCaseCollision, unicodeCollision, providerCompatibilityReviewRequired
        case effectiveAt, supersedes, policySHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(Bool.self, forKey: .exactByteIdentityOnly),
              try c.decode(ContactAddressCollisionDispositionV1.self, forKey: .plusTagCollision) == .reviewRequired,
              try c.decode(ContactAddressCollisionDispositionV1.self, forKey: .localPartCaseCollision) == .reviewRequired,
              try c.decode(ContactAddressCollisionDispositionV1.self, forKey: .unicodeCollision) == .reviewRequired,
              try c.decode(Bool.self, forKey: .providerCompatibilityReviewRequired) else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        let value = try Self(
            policyID: c.decode(UUID.self, forKey: .policyID),
            revision: c.decode(UInt64.self, forKey: .revision),
            effectiveAt: c.decode(Date.self, forKey: .effectiveAt),
            supersedes: c.decodeIfPresent(ContactComparisonPolicyReferenceV1.self, forKey: .supersedes)
        )
        guard value.policySHA256 == c.decode(String.self, forKey: .policySHA256) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct ContactSourceReferenceV1: Codable, Equatable, Hashable, Sendable {
    let sourceID: UUID
    let revision: UInt64
    let kind: ContactSourceKindV1
    let sourceSHA256: String

    init(sourceID: UUID, revision: UInt64, kind: ContactSourceKindV1, sourceSHA256: String) throws {
        self.sourceID = sourceID; self.revision = revision; self.kind = kind
        self.sourceSHA256 = sourceSHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(sourceID)
        try CommunicationConsentValidationV1.digest(sourceSHA256)
        guard revision > 0 else { throw CommunicationConsentContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case sourceID, revision, kind, sourceSHA256 }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceID: c.decode(UUID.self, forKey: .sourceID),
            revision: c.decode(UInt64.self, forKey: .revision),
            kind: c.decode(ContactSourceKindV1.self, forKey: .kind),
            sourceSHA256: c.decode(String.self, forKey: .sourceSHA256)
        )
    }
}

struct ContactSourceV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sourceID: UUID
    let revision: UInt64
    let kind: ContactSourceKindV1
    let releaseID: String
    let ownerReadableDescription: String
    let requiresIndependentAffirmativeEnrollment: Bool
    let prohibitsOperationalContactImport: Bool
    let effectiveAt: Date
    let supersedes: ContactSourceReferenceV1?
    let sourceSHA256: String

    init(
        sourceID: UUID,
        revision: UInt64,
        kind: ContactSourceKindV1,
        releaseID: String,
        ownerReadableDescription: String,
        effectiveAt: Date,
        supersedes: ContactSourceReferenceV1? = nil
    ) throws {
        let digestBasis = Basis(
            schemaVersion: Self.schemaVersion, sourceID: sourceID, revision: revision,
            kind: kind, releaseID: releaseID, ownerReadableDescription: ownerReadableDescription,
            requiresIndependentAffirmativeEnrollment: true,
            prohibitsOperationalContactImport: true, effectiveAt: effectiveAt, supersedes: supersedes
        )
        schemaVersion = Self.schemaVersion; self.sourceID = sourceID; self.revision = revision
        self.kind = kind; self.releaseID = releaseID
        self.ownerReadableDescription = ownerReadableDescription
        requiresIndependentAffirmativeEnrollment = true; prohibitsOperationalContactImport = true
        self.effectiveAt = effectiveAt; self.supersedes = supersedes
        sourceSHA256 = try CommunicationConsentCanonicalCodecV1.sha256(digestBasis)
        try validate()
    }

    var reference: ContactSourceReferenceV1 {
        get throws { try .init(sourceID: sourceID, revision: revision, kind: kind, sourceSHA256: sourceSHA256) }
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(sourceID)
        try CommunicationConsentValidationV1.identifier(releaseID)
        try CommunicationConsentValidationV1.text(ownerReadableDescription)
        try CommunicationConsentValidationV1.instant(effectiveAt)
        try supersedes?.validate()
        guard schemaVersion == Self.schemaVersion, revision > 0,
              requiresIndependentAffirmativeEnrollment, prohibitsOperationalContactImport,
              (revision == 1) == (supersedes == nil),
              sourceSHA256 == (try CommunicationConsentCanonicalCodecV1.sha256(basis)) else {
            throw CommunicationConsentContractFailureV1.sourceForbidden
        }
        if let supersedes {
            guard supersedes.sourceID == sourceID, supersedes.kind == kind,
                  CommunicationConsentValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CommunicationConsentContractFailureV1.invalidSuccessor
            }
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, sourceID: sourceID, revision: revision, kind: kind,
        releaseID: releaseID, ownerReadableDescription: ownerReadableDescription,
        requiresIndependentAffirmativeEnrollment: requiresIndependentAffirmativeEnrollment,
        prohibitsOperationalContactImport: prohibitsOperationalContactImport,
        effectiveAt: effectiveAt, supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let sourceID: UUID; let revision: UInt64; let kind: ContactSourceKindV1
        let releaseID: String; let ownerReadableDescription: String
        let requiresIndependentAffirmativeEnrollment: Bool; let prohibitsOperationalContactImport: Bool
        let effectiveAt: Date; let supersedes: ContactSourceReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sourceID, revision, kind, releaseID, ownerReadableDescription
        case requiresIndependentAffirmativeEnrollment, prohibitsOperationalContactImport
        case effectiveAt, supersedes, sourceSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(Bool.self, forKey: .requiresIndependentAffirmativeEnrollment),
              try c.decode(Bool.self, forKey: .prohibitsOperationalContactImport) else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        let value = try Self(
            sourceID: c.decode(UUID.self, forKey: .sourceID),
            revision: c.decode(UInt64.self, forKey: .revision),
            kind: c.decode(ContactSourceKindV1.self, forKey: .kind),
            releaseID: c.decode(String.self, forKey: .releaseID),
            ownerReadableDescription: c.decode(String.self, forKey: .ownerReadableDescription),
            effectiveAt: c.decode(Date.self, forKey: .effectiveAt),
            supersedes: c.decodeIfPresent(ContactSourceReferenceV1.self, forKey: .supersedes)
        )
        guard value.sourceSHA256 == c.decode(String.self, forKey: .sourceSHA256) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct ConsentDisclosureReferenceV1: Codable, Equatable, Hashable, Sendable {
    let disclosureID: UUID
    let revision: UInt64
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let topics: [String]
    let localeIdentifier: String
    let disclosureSHA256: String

    init(
        disclosureID: UUID,
        revision: UInt64,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1,
        topics: [String],
        localeIdentifier: String,
        disclosureSHA256: String
    ) throws {
        self.disclosureID = disclosureID; self.revision = revision; self.purpose = purpose
        self.channel = channel; self.topics = topics; self.localeIdentifier = localeIdentifier
        self.disclosureSHA256 = disclosureSHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(disclosureID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.sortedUniqueIdentifiers(topics, maximumCount: 64)
        try CommunicationConsentValidationV1.identifier(localeIdentifier)
        try CommunicationConsentValidationV1.digest(disclosureSHA256)
        guard revision > 0 else { throw CommunicationConsentContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case disclosureID, revision, purpose, channel, topics, localeIdentifier, disclosureSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            disclosureID: c.decode(UUID.self, forKey: .disclosureID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            topics: c.decode([String].self, forKey: .topics),
            localeIdentifier: c.decode(String.self, forKey: .localeIdentifier),
            disclosureSHA256: c.decode(String.self, forKey: .disclosureSHA256)
        )
    }
}

struct ConsentDisclosureReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let disclosureID: UUID
    let revision: UInt64
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let topics: [String]
    let localeIdentifier: String
    let disclosureText: String
    let statesIndependentAffirmativeEnrollment: Bool
    let statesPurposeNontransitivity: Bool
    let statesWithdrawalAvailable: Bool
    let effectiveAt: Date
    let supersedes: ConsentDisclosureReferenceV1?
    let disclosureSHA256: String

    init(
        disclosureID: UUID,
        revision: UInt64,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1 = .email,
        topics: [String],
        localeIdentifier: String,
        disclosureText: String,
        effectiveAt: Date,
        supersedes: ConsentDisclosureReferenceV1? = nil
    ) throws {
        let orderedTopics = topics.sorted()
        let digestBasis = Basis(
            schemaVersion: Self.schemaVersion, disclosureID: disclosureID, revision: revision,
            purpose: purpose, channel: channel, topics: orderedTopics,
            localeIdentifier: localeIdentifier, disclosureText: disclosureText,
            statesIndependentAffirmativeEnrollment: true,
            statesPurposeNontransitivity: true, statesWithdrawalAvailable: true,
            effectiveAt: effectiveAt, supersedes: supersedes
        )
        schemaVersion = Self.schemaVersion; self.disclosureID = disclosureID; self.revision = revision
        self.purpose = purpose; self.channel = channel; self.topics = orderedTopics
        self.localeIdentifier = localeIdentifier; self.disclosureText = disclosureText
        statesIndependentAffirmativeEnrollment = true; statesPurposeNontransitivity = true
        statesWithdrawalAvailable = true; self.effectiveAt = effectiveAt; self.supersedes = supersedes
        disclosureSHA256 = try CommunicationConsentCanonicalCodecV1.sha256(digestBasis)
        try validate()
    }

    var reference: ConsentDisclosureReferenceV1 {
        get throws { try .init(
            disclosureID: disclosureID, revision: revision, purpose: purpose, channel: channel,
            topics: topics, localeIdentifier: localeIdentifier, disclosureSHA256: disclosureSHA256
        ) }
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(disclosureID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.sortedUniqueIdentifiers(topics, maximumCount: 64)
        try CommunicationConsentValidationV1.identifier(localeIdentifier)
        try CommunicationConsentValidationV1.text(disclosureText, maximumBytes: 32_768)
        try CommunicationConsentValidationV1.instant(effectiveAt)
        try supersedes?.validate()
        guard schemaVersion == Self.schemaVersion, revision > 0,
              statesIndependentAffirmativeEnrollment, statesPurposeNontransitivity,
              statesWithdrawalAvailable, (revision == 1) == (supersedes == nil),
              disclosureSHA256 == (try CommunicationConsentCanonicalCodecV1.sha256(basis)) else {
            throw CommunicationConsentContractFailureV1.disclosureMismatch
        }
        if let supersedes {
            guard supersedes.disclosureID == disclosureID,
                  supersedes.purpose == purpose, supersedes.channel == channel,
                  CommunicationConsentValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CommunicationConsentContractFailureV1.invalidSuccessor
            }
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, disclosureID: disclosureID, revision: revision,
        purpose: purpose, channel: channel, topics: topics, localeIdentifier: localeIdentifier,
        disclosureText: disclosureText,
        statesIndependentAffirmativeEnrollment: statesIndependentAffirmativeEnrollment,
        statesPurposeNontransitivity: statesPurposeNontransitivity,
        statesWithdrawalAvailable: statesWithdrawalAvailable,
        effectiveAt: effectiveAt, supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let disclosureID: UUID; let revision: UInt64
        let purpose: CommunicationPurposeV1; let channel: CommunicationChannelV1
        let topics: [String]; let localeIdentifier: String; let disclosureText: String
        let statesIndependentAffirmativeEnrollment: Bool
        let statesPurposeNontransitivity: Bool; let statesWithdrawalAvailable: Bool
        let effectiveAt: Date; let supersedes: ConsentDisclosureReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, disclosureID, revision, purpose, channel, topics, localeIdentifier
        case disclosureText, statesIndependentAffirmativeEnrollment, statesPurposeNontransitivity
        case statesWithdrawalAvailable, effectiveAt, supersedes, disclosureSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(Bool.self, forKey: .statesIndependentAffirmativeEnrollment),
              try c.decode(Bool.self, forKey: .statesPurposeNontransitivity),
              try c.decode(Bool.self, forKey: .statesWithdrawalAvailable) else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        let value = try Self(
            disclosureID: c.decode(UUID.self, forKey: .disclosureID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            topics: c.decode([String].self, forKey: .topics),
            localeIdentifier: c.decode(String.self, forKey: .localeIdentifier),
            disclosureText: c.decode(String.self, forKey: .disclosureText),
            effectiveAt: c.decode(Date.self, forKey: .effectiveAt),
            supersedes: c.decodeIfPresent(ConsentDisclosureReferenceV1.self, forKey: .supersedes)
        )
        guard value.disclosureSHA256 == c.decode(String.self, forKey: .disclosureSHA256) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct CommunicationConsentingActorV1: Codable, Equatable, Hashable, Sendable {
    let actorAssertionID: String
    let capacity: CommunicationActorCapacityV1
    let assertionRecordedAt: Date

    init(
        actorAssertionID: String,
        capacity: CommunicationActorCapacityV1,
        assertionRecordedAt: Date
    ) throws {
        self.actorAssertionID = actorAssertionID; self.capacity = capacity
        self.assertionRecordedAt = assertionRecordedAt
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.identifier(actorAssertionID)
        try CommunicationConsentValidationV1.instant(assertionRecordedAt)
        guard capacity != .reviewRequired else {
            throw CommunicationConsentContractFailureV1.consentNotAffirmative
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actorAssertionID, capacity, assertionRecordedAt
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            actorAssertionID: c.decode(String.self, forKey: .actorAssertionID),
            capacity: c.decode(CommunicationActorCapacityV1.self, forKey: .capacity),
            assertionRecordedAt: c.decode(Date.self, forKey: .assertionRecordedAt)
        )
    }
}

struct CommunicationVerificationV1: Codable, Equatable, Hashable, Sendable {
    let status: CommunicationVerificationStatusV1
    let verifiedAt: Date?

    init(status: CommunicationVerificationStatusV1, verifiedAt: Date? = nil) throws {
        self.status = status; self.verifiedAt = verifiedAt
        try validate()
    }

    func validate() throws {
        if let verifiedAt { try CommunicationConsentValidationV1.instant(verifiedAt) }
        guard (status == .verified) == (verifiedAt != nil) else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case status, verifiedAt }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            status: c.decode(CommunicationVerificationStatusV1.self, forKey: .status),
            verifiedAt: c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        )
    }
}

struct CommunicationJurisdictionBasisV1: Codable, Equatable, Hashable, Sendable {
    let jurisdictionCode: String
    let disposition: CommunicationLawfulBasisDispositionV1
    let documentationSHA256: String?

    init(
        jurisdictionCode: String,
        disposition: CommunicationLawfulBasisDispositionV1,
        documentationSHA256: String? = nil
    ) throws {
        self.jurisdictionCode = jurisdictionCode; self.disposition = disposition
        self.documentationSHA256 = documentationSHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.identifier(jurisdictionCode)
        if let documentationSHA256 { try CommunicationConsentValidationV1.digest(documentationSHA256) }
        guard disposition == .documentedAffirmativeConsent, documentationSHA256 != nil else {
            throw CommunicationConsentContractFailureV1.consentNotAffirmative
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case jurisdictionCode, disposition, documentationSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            jurisdictionCode: c.decode(String.self, forKey: .jurisdictionCode),
            disposition: c.decode(CommunicationLawfulBasisDispositionV1.self, forKey: .disposition),
            documentationSHA256: c.decodeIfPresent(String.self, forKey: .documentationSHA256)
        )
    }
}

struct CommunicationWithdrawalEventV1: Codable, Equatable, Hashable, Sendable {
    let eventID: UUID
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let reason: CommunicationWithdrawalReasonV1
    let requestedBy: CommunicationConsentingActorV1
    let occurredAt: Date
    let recordedAt: Date

    init(
        eventID: UUID,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1 = .email,
        reason: CommunicationWithdrawalReasonV1,
        requestedBy: CommunicationConsentingActorV1,
        occurredAt: Date,
        recordedAt: Date
    ) throws {
        self.eventID = eventID; self.purpose = purpose; self.channel = channel
        self.reason = reason; self.requestedBy = requestedBy
        self.occurredAt = occurredAt; self.recordedAt = recordedAt
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(eventID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try requestedBy.validate()
        try CommunicationConsentValidationV1.instant(occurredAt)
        try CommunicationConsentValidationV1.instant(recordedAt)
        guard recordedAt >= occurredAt else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case eventID, purpose, channel, reason, requestedBy, occurredAt, recordedAt
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            eventID: c.decode(UUID.self, forKey: .eventID),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            reason: c.decode(CommunicationWithdrawalReasonV1.self, forKey: .reason),
            requestedBy: c.decode(CommunicationConsentingActorV1.self, forKey: .requestedBy),
            occurredAt: c.decode(Date.self, forKey: .occurredAt),
            recordedAt: c.decode(Date.self, forKey: .recordedAt)
        )
    }
}

struct CommunicationConsentReferenceV1: Codable, Equatable, Hashable, Sendable {
    let receiptID: UUID
    let revision: UInt64
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let topics: [String]
    let address: ExactCommunicationAddressV1
    let comparisonPolicy: ContactComparisonPolicyReferenceV1
    let consentSHA256: String

    init(
        receiptID: UUID,
        revision: UInt64,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1,
        topics: [String],
        address: ExactCommunicationAddressV1,
        comparisonPolicy: ContactComparisonPolicyReferenceV1,
        consentSHA256: String
    ) throws {
        self.receiptID = receiptID; self.revision = revision; self.purpose = purpose
        self.channel = channel; self.topics = topics; self.address = address
        self.comparisonPolicy = comparisonPolicy; self.consentSHA256 = consentSHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(receiptID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.sortedUniqueIdentifiers(topics, maximumCount: 64)
        try address.validate()
        try comparisonPolicy.validate()
        try CommunicationConsentValidationV1.digest(consentSHA256)
        guard revision > 0, channel == address.channel else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case receiptID, revision, purpose, channel, topics, address
        case comparisonPolicy, consentSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            receiptID: c.decode(UUID.self, forKey: .receiptID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            topics: c.decode([String].self, forKey: .topics),
            address: c.decode(ExactCommunicationAddressV1.self, forKey: .address),
            comparisonPolicy: c.decode(ContactComparisonPolicyReferenceV1.self, forKey: .comparisonPolicy),
            consentSHA256: c.decode(String.self, forKey: .consentSHA256)
        )
    }
}

struct CommunicationConsentReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: UUID
    let revision: UInt64
    let address: ExactCommunicationAddressV1
    let comparisonPolicy: ContactComparisonPolicyReferenceV1
    let purpose: CommunicationPurposeV1
    let topics: [String]
    let consentingActor: CommunicationConsentingActorV1
    let source: ContactSourceReferenceV1
    let disclosure: ConsentDisclosureReferenceV1
    let presentedLocaleIdentifier: String
    let affirmativeMethod: CommunicationAffirmativeMethodV1
    let occurredAt: Date
    let recordedAt: Date
    let verification: CommunicationVerificationV1
    let jurisdictionBasis: CommunicationJurisdictionBasisV1
    let expiresAt: Date?
    let predecessor: CommunicationConsentReferenceV1?
    let withdrawalHistory: [CommunicationWithdrawalEventV1]
    let collectionDisposition: CommunicationCollectionDispositionV1
    let consentSHA256: String

    init(
        receiptID: UUID,
        revision: UInt64,
        address: ExactCommunicationAddressV1,
        comparisonPolicy: ContactComparisonPolicyReferenceV1,
        purpose: CommunicationPurposeV1,
        topics: [String],
        consentingActor: CommunicationConsentingActorV1,
        source: ContactSourceReferenceV1,
        disclosure: ConsentDisclosureReferenceV1,
        presentedLocaleIdentifier: String,
        affirmativeMethod: CommunicationAffirmativeMethodV1,
        occurredAt: Date,
        recordedAt: Date,
        verification: CommunicationVerificationV1,
        jurisdictionBasis: CommunicationJurisdictionBasisV1,
        expiresAt: Date? = nil,
        predecessor: CommunicationConsentReferenceV1? = nil,
        withdrawalHistory: [CommunicationWithdrawalEventV1] = []
    ) throws {
        let orderedTopics = topics.sorted()
        let orderedWithdrawals = withdrawalHistory.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            return $0.eventID.uuidString < $1.eventID.uuidString
        }
        let digestBasis = Basis(
            schemaVersion: Self.schemaVersion, receiptID: receiptID, revision: revision,
            address: address, comparisonPolicy: comparisonPolicy,
            purpose: purpose, topics: orderedTopics, consentingActor: consentingActor,
            source: source, disclosure: disclosure,
            presentedLocaleIdentifier: presentedLocaleIdentifier,
            affirmativeMethod: affirmativeMethod, occurredAt: occurredAt, recordedAt: recordedAt,
            verification: verification, jurisdictionBasis: jurisdictionBasis, expiresAt: expiresAt,
            predecessor: predecessor, withdrawalHistory: orderedWithdrawals,
            collectionDisposition: .disabledNoSubscriberCollectionOrTransmission
        )
        schemaVersion = Self.schemaVersion; self.receiptID = receiptID; self.revision = revision
        self.address = address; self.comparisonPolicy = comparisonPolicy
        self.purpose = purpose; self.topics = orderedTopics; self.consentingActor = consentingActor
        self.source = source; self.disclosure = disclosure
        self.presentedLocaleIdentifier = presentedLocaleIdentifier; self.affirmativeMethod = affirmativeMethod
        self.occurredAt = occurredAt; self.recordedAt = recordedAt; self.verification = verification
        self.jurisdictionBasis = jurisdictionBasis; self.expiresAt = expiresAt
        self.predecessor = predecessor; self.withdrawalHistory = orderedWithdrawals
        collectionDisposition = .disabledNoSubscriberCollectionOrTransmission
        consentSHA256 = try CommunicationConsentCanonicalCodecV1.sha256(digestBasis)
        try validate()
    }

    var reference: CommunicationConsentReferenceV1 {
        get throws { try .init(
            receiptID: receiptID, revision: revision, purpose: purpose, channel: address.channel,
            topics: topics, address: address, comparisonPolicy: comparisonPolicy,
            consentSHA256: consentSHA256
        ) }
    }

    var channel: CommunicationChannelV1 { address.channel }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(receiptID)
        try address.validate(); try comparisonPolicy.validate()
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.sortedUniqueIdentifiers(topics, maximumCount: 64)
        try consentingActor.validate(); try source.validate(); try disclosure.validate()
        try CommunicationConsentValidationV1.identifier(presentedLocaleIdentifier)
        try CommunicationConsentValidationV1.instant(occurredAt)
        try CommunicationConsentValidationV1.instant(recordedAt)
        try verification.validate(); try jurisdictionBasis.validate()
        if let expiresAt { try CommunicationConsentValidationV1.instant(expiresAt) }
        try predecessor?.validate(); try withdrawalHistory.forEach { try $0.validate() }
        let sourceAndMethodMatch: Bool
        switch source.kind {
        case .controlledBackendAffirmativeEnrollment:
            sourceAndMethodMatch = affirmativeMethod == .explicitUncheckedControl
        case .providerHostedAffirmativeEnrollment:
            sourceAndMethodMatch = affirmativeMethod == .providerHostedConfirmation
        case .separatelyAuthorizedResearchInvitationEnrollment:
            sourceAndMethodMatch = purpose == .researchInvitation
                && affirmativeMethod == .documentedIndependentResearchInvitationEnrollment
        }
        guard schemaVersion == Self.schemaVersion, revision > 0,
              sourceAndMethodMatch,
              address.channel == disclosure.channel,
              purpose == disclosure.purpose,
              topics == disclosure.topics,
              presentedLocaleIdentifier == disclosure.localeIdentifier,
              recordedAt >= occurredAt,
              consentingActor.assertionRecordedAt <= recordedAt,
              verification.verifiedAt.map({ $0 >= occurredAt && $0 <= recordedAt }) ?? true,
              expiresAt.map({ $0 > occurredAt }) ?? true,
              (revision == 1) == (predecessor == nil),
              withdrawalHistory == withdrawalHistory.sorted(by: {
                if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
                return $0.eventID.uuidString < $1.eventID.uuidString
              }),
              Set(withdrawalHistory.map(\.eventID)).count == withdrawalHistory.count,
              withdrawalHistory.allSatisfy({
                $0.purpose == purpose && $0.channel == address.channel
                    && $0.occurredAt >= occurredAt && $0.recordedAt >= $0.occurredAt
              }),
              collectionDisposition == .disabledNoSubscriberCollectionOrTransmission,
              consentSHA256 == (try CommunicationConsentCanonicalCodecV1.sha256(basis)) else {
            throw CommunicationConsentContractFailureV1.consentNotAffirmative
        }
        if let predecessor {
            guard predecessor.receiptID == receiptID,
                  predecessor.purpose == purpose,
                  predecessor.channel == address.channel,
                  predecessor.topics == topics,
                  predecessor.address == address,
                  predecessor.comparisonPolicy == comparisonPolicy,
                  CommunicationConsentValidationV1.isImmediateSuccessor(
                    revision, of: predecessor.revision
                  ) else {
                throw CommunicationConsentContractFailureV1.invalidSuccessor
            }
        }
    }

    func validateSuccessor(of old: Self) throws {
        try validate(); try old.validate()
        let oldReference = try old.reference
        guard predecessor == oldReference,
              receiptID == old.receiptID,
              address == old.address,
              comparisonPolicy == old.comparisonPolicy,
              purpose == old.purpose,
              topics == old.topics,
              consentingActor == old.consentingActor,
              source == old.source,
              disclosure == old.disclosure,
              presentedLocaleIdentifier == old.presentedLocaleIdentifier,
              affirmativeMethod == old.affirmativeMethod,
              occurredAt == old.occurredAt,
              verification == old.verification,
              jurisdictionBasis == old.jurisdictionBasis,
              expiresAt == old.expiresAt,
              Array(withdrawalHistory.prefix(old.withdrawalHistory.count)) == old.withdrawalHistory,
              withdrawalHistory.count >= old.withdrawalHistory.count else {
            throw CommunicationConsentContractFailureV1.invalidSuccessor
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, receiptID: receiptID, revision: revision,
        address: address, comparisonPolicy: comparisonPolicy,
        purpose: purpose, topics: topics, consentingActor: consentingActor, source: source,
        disclosure: disclosure, presentedLocaleIdentifier: presentedLocaleIdentifier,
        affirmativeMethod: affirmativeMethod, occurredAt: occurredAt, recordedAt: recordedAt,
        verification: verification, jurisdictionBasis: jurisdictionBasis, expiresAt: expiresAt,
        predecessor: predecessor, withdrawalHistory: withdrawalHistory,
        collectionDisposition: collectionDisposition
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let receiptID: UUID; let revision: UInt64
        let address: ExactCommunicationAddressV1
        let comparisonPolicy: ContactComparisonPolicyReferenceV1
        let purpose: CommunicationPurposeV1; let topics: [String]
        let consentingActor: CommunicationConsentingActorV1; let source: ContactSourceReferenceV1
        let disclosure: ConsentDisclosureReferenceV1; let presentedLocaleIdentifier: String
        let affirmativeMethod: CommunicationAffirmativeMethodV1
        let occurredAt: Date; let recordedAt: Date; let verification: CommunicationVerificationV1
        let jurisdictionBasis: CommunicationJurisdictionBasisV1; let expiresAt: Date?
        let predecessor: CommunicationConsentReferenceV1?
        let withdrawalHistory: [CommunicationWithdrawalEventV1]
        let collectionDisposition: CommunicationCollectionDispositionV1
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, receiptID, revision, address, comparisonPolicy
        case purpose, topics, consentingActor, source, disclosure, presentedLocaleIdentifier
        case affirmativeMethod, occurredAt, recordedAt, verification, jurisdictionBasis
        case expiresAt, predecessor, withdrawalHistory, collectionDisposition, consentSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(CommunicationCollectionDispositionV1.self, forKey: .collectionDisposition)
                == .disabledNoSubscriberCollectionOrTransmission else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        let value = try Self(
            receiptID: c.decode(UUID.self, forKey: .receiptID),
            revision: c.decode(UInt64.self, forKey: .revision),
            address: c.decode(ExactCommunicationAddressV1.self, forKey: .address),
            comparisonPolicy: c.decode(ContactComparisonPolicyReferenceV1.self, forKey: .comparisonPolicy),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            topics: c.decode([String].self, forKey: .topics),
            consentingActor: c.decode(CommunicationConsentingActorV1.self, forKey: .consentingActor),
            source: c.decode(ContactSourceReferenceV1.self, forKey: .source),
            disclosure: c.decode(ConsentDisclosureReferenceV1.self, forKey: .disclosure),
            presentedLocaleIdentifier: c.decode(String.self, forKey: .presentedLocaleIdentifier),
            affirmativeMethod: c.decode(CommunicationAffirmativeMethodV1.self, forKey: .affirmativeMethod),
            occurredAt: c.decode(Date.self, forKey: .occurredAt),
            recordedAt: c.decode(Date.self, forKey: .recordedAt),
            verification: c.decode(CommunicationVerificationV1.self, forKey: .verification),
            jurisdictionBasis: c.decode(CommunicationJurisdictionBasisV1.self, forKey: .jurisdictionBasis),
            expiresAt: c.decodeIfPresent(Date.self, forKey: .expiresAt),
            predecessor: c.decodeIfPresent(CommunicationConsentReferenceV1.self, forKey: .predecessor),
            withdrawalHistory: c.decode([CommunicationWithdrawalEventV1].self, forKey: .withdrawalHistory)
        )
        guard value.consentSHA256 == c.decode(String.self, forKey: .consentSHA256) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct MarketingContactReferenceV1: Codable, Equatable, Hashable, Sendable {
    let contactID: UUID
    let revision: UInt64
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let contactSHA256: String

    init(
        contactID: UUID,
        revision: UInt64,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1,
        contactSHA256: String
    ) throws {
        self.contactID = contactID; self.revision = revision; self.purpose = purpose
        self.channel = channel; self.contactSHA256 = contactSHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(contactID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.digest(contactSHA256)
        guard revision > 0 else { throw CommunicationConsentContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contactID, revision, purpose, channel, contactSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            contactID: c.decode(UUID.self, forKey: .contactID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            contactSHA256: c.decode(String.self, forKey: .contactSHA256)
        )
    }
}

struct MarketingContactV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let contactID: UUID
    let revision: UInt64
    let address: ExactCommunicationAddressV1
    let comparisonPolicy: ContactComparisonPolicyReferenceV1
    let purpose: CommunicationPurposeV1
    let topics: [String]
    let consent: CommunicationConsentReferenceV1
    let state: MarketingContactStateV1
    let recordedAt: Date
    let supersedes: MarketingContactReferenceV1?
    let collectionDisposition: CommunicationCollectionDispositionV1
    let contactSHA256: String

    init(
        contactID: UUID,
        revision: UInt64,
        address: ExactCommunicationAddressV1,
        comparisonPolicy: ContactComparisonPolicyReferenceV1,
        purpose: CommunicationPurposeV1,
        topics: [String],
        consent: CommunicationConsentReferenceV1,
        state: MarketingContactStateV1,
        recordedAt: Date,
        supersedes: MarketingContactReferenceV1? = nil
    ) throws {
        let orderedTopics = topics.sorted()
        let digestBasis = Basis(
            schemaVersion: Self.schemaVersion, contactID: contactID, revision: revision,
            address: address, comparisonPolicy: comparisonPolicy, purpose: purpose,
            topics: orderedTopics, consent: consent, state: state, recordedAt: recordedAt,
            supersedes: supersedes,
            collectionDisposition: .disabledNoSubscriberCollectionOrTransmission
        )
        schemaVersion = Self.schemaVersion; self.contactID = contactID; self.revision = revision
        self.address = address; self.comparisonPolicy = comparisonPolicy; self.purpose = purpose
        self.topics = orderedTopics; self.consent = consent; self.state = state
        self.recordedAt = recordedAt; self.supersedes = supersedes
        collectionDisposition = .disabledNoSubscriberCollectionOrTransmission
        contactSHA256 = try CommunicationConsentCanonicalCodecV1.sha256(digestBasis)
        try validate()
    }

    var reference: MarketingContactReferenceV1 {
        get throws { try .init(
            contactID: contactID, revision: revision, purpose: purpose,
            channel: address.channel, contactSHA256: contactSHA256
        ) }
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(contactID)
        try address.validate(); try comparisonPolicy.validate()
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.sortedUniqueIdentifiers(topics, maximumCount: 64)
        try consent.validate(); try CommunicationConsentValidationV1.instant(recordedAt)
        try supersedes?.validate()
        guard schemaVersion == Self.schemaVersion, revision > 0,
              consent.purpose == purpose, consent.channel == address.channel,
              consent.topics == topics, consent.address == address,
              consent.comparisonPolicy == comparisonPolicy,
              (revision == 1) == (supersedes == nil),
              collectionDisposition == .disabledNoSubscriberCollectionOrTransmission,
              contactSHA256 == (try CommunicationConsentCanonicalCodecV1.sha256(basis)) else {
            throw CommunicationConsentContractFailureV1.consentNotAffirmative
        }
        if let supersedes {
            guard supersedes.contactID == contactID,
                  supersedes.purpose == purpose, supersedes.channel == address.channel,
                  CommunicationConsentValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CommunicationConsentContractFailureV1.invalidSuccessor
            }
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, contactID: contactID, revision: revision,
        address: address, comparisonPolicy: comparisonPolicy, purpose: purpose,
        topics: topics, consent: consent, state: state, recordedAt: recordedAt,
        supersedes: supersedes, collectionDisposition: collectionDisposition
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let contactID: UUID; let revision: UInt64
        let address: ExactCommunicationAddressV1
        let comparisonPolicy: ContactComparisonPolicyReferenceV1
        let purpose: CommunicationPurposeV1; let topics: [String]
        let consent: CommunicationConsentReferenceV1; let state: MarketingContactStateV1
        let recordedAt: Date; let supersedes: MarketingContactReferenceV1?
        let collectionDisposition: CommunicationCollectionDispositionV1
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, contactID, revision, address, comparisonPolicy, purpose, topics
        case consent, state, recordedAt, supersedes, collectionDisposition, contactSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(CommunicationCollectionDispositionV1.self, forKey: .collectionDisposition)
                == .disabledNoSubscriberCollectionOrTransmission else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        let value = try Self(
            contactID: c.decode(UUID.self, forKey: .contactID),
            revision: c.decode(UInt64.self, forKey: .revision),
            address: c.decode(ExactCommunicationAddressV1.self, forKey: .address),
            comparisonPolicy: c.decode(ContactComparisonPolicyReferenceV1.self, forKey: .comparisonPolicy),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            topics: c.decode([String].self, forKey: .topics),
            consent: c.decode(CommunicationConsentReferenceV1.self, forKey: .consent),
            state: c.decode(MarketingContactStateV1.self, forKey: .state),
            recordedAt: c.decode(Date.self, forKey: .recordedAt),
            supersedes: c.decodeIfPresent(MarketingContactReferenceV1.self, forKey: .supersedes)
        )
        guard value.contactSHA256 == c.decode(String.self, forKey: .contactSHA256) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct SuppressionRecordReferenceV1: Codable, Equatable, Hashable, Sendable {
    let recordID: UUID
    let revision: UInt64
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let recordSHA256: String

    init(
        recordID: UUID,
        revision: UInt64,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1,
        recordSHA256: String
    ) throws {
        self.recordID = recordID; self.revision = revision; self.purpose = purpose
        self.channel = channel; self.recordSHA256 = recordSHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(recordID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.digest(recordSHA256)
        guard revision > 0 else { throw CommunicationConsentContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordID, revision, purpose, channel, recordSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            recordID: c.decode(UUID.self, forKey: .recordID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            recordSHA256: c.decode(String.self, forKey: .recordSHA256)
        )
    }
}

struct ServiceSideKeyedSuppressionTokenV1: Codable, Equatable, Hashable, Sendable {
    let serviceAuthorityID: String
    let keyReleaseID: String
    let opaqueToken: String
    let classification: SuppressionTokenClassificationV1

    init(serviceAuthorityID: String, keyReleaseID: String, opaqueToken: String) throws {
        self.serviceAuthorityID = serviceAuthorityID; self.keyReleaseID = keyReleaseID
        self.opaqueToken = opaqueToken
        classification = .contactInfoPseudonymousNotAnonymous
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.identifier(serviceAuthorityID)
        try CommunicationConsentValidationV1.identifier(keyReleaseID)
        try CommunicationConsentValidationV1.identifier(opaqueToken, maximumBytes: 512)
        guard opaqueToken.hasPrefix("KST1."),
              classification == .contactInfoPseudonymousNotAnonymous else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case serviceAuthorityID, keyReleaseID, opaqueToken, classification
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(SuppressionTokenClassificationV1.self, forKey: .classification)
                == .contactInfoPseudonymousNotAnonymous else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        try self.init(
            serviceAuthorityID: c.decode(String.self, forKey: .serviceAuthorityID),
            keyReleaseID: c.decode(String.self, forKey: .keyReleaseID),
            opaqueToken: c.decode(String.self, forKey: .opaqueToken)
        )
    }
}

struct SuppressionRetentionDecisionV1: Codable, Equatable, Hashable, Sendable {
    let disposition: SuppressionRetentionDispositionV1
    let ownerDecisionBasisSHA256: String?
    let reviewedAt: Date?
    let expiresAt: Date?

    init(
        disposition: SuppressionRetentionDispositionV1,
        ownerDecisionBasisSHA256: String? = nil,
        reviewedAt: Date? = nil,
        expiresAt: Date? = nil
    ) throws {
        self.disposition = disposition; self.ownerDecisionBasisSHA256 = ownerDecisionBasisSHA256
        self.reviewedAt = reviewedAt; self.expiresAt = expiresAt
        try validate()
    }

    func validate() throws {
        if let ownerDecisionBasisSHA256 { try CommunicationConsentValidationV1.digest(ownerDecisionBasisSHA256) }
        if let reviewedAt { try CommunicationConsentValidationV1.instant(reviewedAt) }
        if let expiresAt { try CommunicationConsentValidationV1.instant(expiresAt) }
        switch disposition {
        case .ownerReviewedMinimumDoNotContact:
            guard ownerDecisionBasisSHA256 != nil, let reviewedAt,
                  expiresAt.map({ $0 > reviewedAt }) ?? true else {
                throw CommunicationConsentContractFailureV1.invalidValue
            }
        case .ownerReviewRequired:
            guard ownerDecisionBasisSHA256 == nil, reviewedAt == nil, expiresAt == nil else {
                throw CommunicationConsentContractFailureV1.invalidValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case disposition, ownerDecisionBasisSHA256, reviewedAt, expiresAt
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            disposition: c.decode(SuppressionRetentionDispositionV1.self, forKey: .disposition),
            ownerDecisionBasisSHA256: c.decodeIfPresent(String.self, forKey: .ownerDecisionBasisSHA256),
            reviewedAt: c.decodeIfPresent(Date.self, forKey: .reviewedAt),
            expiresAt: c.decodeIfPresent(Date.self, forKey: .expiresAt)
        )
    }
}

struct SuppressionRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let recordID: UUID
    let revision: UInt64
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let token: ServiceSideKeyedSuppressionTokenV1
    let source: ContactSourceReferenceV1
    let reason: CommunicationWithdrawalReasonV1
    let withdrawalOccurredAt: Date
    let comparisonPolicy: ContactComparisonPolicyReferenceV1
    let retentionDecision: SuppressionRetentionDecisionV1
    let supersedes: SuppressionRecordReferenceV1?
    let collectionDisposition: CommunicationCollectionDispositionV1
    let recordSHA256: String

    init(
        recordID: UUID,
        revision: UInt64,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1 = .email,
        token: ServiceSideKeyedSuppressionTokenV1,
        source: ContactSourceReferenceV1,
        reason: CommunicationWithdrawalReasonV1,
        withdrawalOccurredAt: Date,
        comparisonPolicy: ContactComparisonPolicyReferenceV1,
        retentionDecision: SuppressionRetentionDecisionV1,
        supersedes: SuppressionRecordReferenceV1? = nil
    ) throws {
        let digestBasis = Basis(
            schemaVersion: Self.schemaVersion, recordID: recordID, revision: revision,
            purpose: purpose, channel: channel, token: token, source: source, reason: reason,
            withdrawalOccurredAt: withdrawalOccurredAt, comparisonPolicy: comparisonPolicy,
            retentionDecision: retentionDecision, supersedes: supersedes,
            collectionDisposition: .disabledNoSubscriberCollectionOrTransmission
        )
        schemaVersion = Self.schemaVersion; self.recordID = recordID; self.revision = revision
        self.purpose = purpose; self.channel = channel; self.token = token; self.source = source
        self.reason = reason; self.withdrawalOccurredAt = withdrawalOccurredAt
        self.comparisonPolicy = comparisonPolicy; self.retentionDecision = retentionDecision
        self.supersedes = supersedes
        collectionDisposition = .disabledNoSubscriberCollectionOrTransmission
        recordSHA256 = try CommunicationConsentCanonicalCodecV1.sha256(digestBasis)
        try validate()
    }

    var reference: SuppressionRecordReferenceV1 {
        get throws { try .init(
            recordID: recordID, revision: revision, purpose: purpose,
            channel: channel, recordSHA256: recordSHA256
        ) }
    }

    func validateSuccessor(of old: Self) throws {
        try validate(); try old.validate()
        guard supersedes == (try old.reference),
              recordID == old.recordID,
              purpose == old.purpose,
              channel == old.channel,
              token == old.token,
              source == old.source,
              reason == old.reason,
              withdrawalOccurredAt == old.withdrawalOccurredAt,
              comparisonPolicy == old.comparisonPolicy else {
            throw CommunicationConsentContractFailureV1.invalidSuccessor
        }
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(recordID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try token.validate(); try source.validate()
        try CommunicationConsentValidationV1.instant(withdrawalOccurredAt)
        try comparisonPolicy.validate(); try retentionDecision.validate(); try supersedes?.validate()
        guard schemaVersion == Self.schemaVersion, revision > 0,
              retentionDecision.disposition == .ownerReviewedMinimumDoNotContact,
              (revision == 1) == (supersedes == nil),
              collectionDisposition == .disabledNoSubscriberCollectionOrTransmission,
              recordSHA256 == (try CommunicationConsentCanonicalCodecV1.sha256(basis)) else {
            throw CommunicationConsentContractFailureV1.suppressionRequired
        }
        if let supersedes {
            guard supersedes.recordID == recordID, supersedes.purpose == purpose,
                  supersedes.channel == channel,
                  CommunicationConsentValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CommunicationConsentContractFailureV1.invalidSuccessor
            }
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, recordID: recordID, revision: revision,
        purpose: purpose, channel: channel, token: token, source: source, reason: reason,
        withdrawalOccurredAt: withdrawalOccurredAt, comparisonPolicy: comparisonPolicy,
        retentionDecision: retentionDecision, supersedes: supersedes,
        collectionDisposition: collectionDisposition
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let recordID: UUID; let revision: UInt64
        let purpose: CommunicationPurposeV1; let channel: CommunicationChannelV1
        let token: ServiceSideKeyedSuppressionTokenV1; let source: ContactSourceReferenceV1
        let reason: CommunicationWithdrawalReasonV1; let withdrawalOccurredAt: Date
        let comparisonPolicy: ContactComparisonPolicyReferenceV1
        let retentionDecision: SuppressionRetentionDecisionV1
        let supersedes: SuppressionRecordReferenceV1?
        let collectionDisposition: CommunicationCollectionDispositionV1
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, recordID, revision, purpose, channel, token, source, reason
        case withdrawalOccurredAt, comparisonPolicy, retentionDecision, supersedes
        case collectionDisposition, recordSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(CommunicationCollectionDispositionV1.self, forKey: .collectionDisposition)
                == .disabledNoSubscriberCollectionOrTransmission else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        let value = try Self(
            recordID: c.decode(UUID.self, forKey: .recordID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            token: c.decode(ServiceSideKeyedSuppressionTokenV1.self, forKey: .token),
            source: c.decode(ContactSourceReferenceV1.self, forKey: .source),
            reason: c.decode(CommunicationWithdrawalReasonV1.self, forKey: .reason),
            withdrawalOccurredAt: c.decode(Date.self, forKey: .withdrawalOccurredAt),
            comparisonPolicy: c.decode(ContactComparisonPolicyReferenceV1.self, forKey: .comparisonPolicy),
            retentionDecision: c.decode(SuppressionRetentionDecisionV1.self, forKey: .retentionDecision),
            supersedes: c.decodeIfPresent(SuppressionRecordReferenceV1.self, forKey: .supersedes)
        )
        guard value.recordSHA256 == c.decode(String.self, forKey: .recordSHA256) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct CommunicationPreferenceReferenceV1: Codable, Equatable, Hashable, Sendable {
    let preferenceID: UUID
    let revision: UInt64
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let preferenceSHA256: String

    init(
        preferenceID: UUID,
        revision: UInt64,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1,
        preferenceSHA256: String
    ) throws {
        self.preferenceID = preferenceID; self.revision = revision; self.purpose = purpose
        self.channel = channel; self.preferenceSHA256 = preferenceSHA256
        try validate()
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(preferenceID)
        try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.digest(preferenceSHA256)
        guard revision > 0 else { throw CommunicationConsentContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case preferenceID, revision, purpose, channel, preferenceSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            preferenceID: c.decode(UUID.self, forKey: .preferenceID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            preferenceSHA256: c.decode(String.self, forKey: .preferenceSHA256)
        )
    }
}

struct CommunicationPreferenceV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let preferenceID: UUID
    let revision: UInt64
    let consent: CommunicationConsentReferenceV1
    let purpose: CommunicationPurposeV1
    let channel: CommunicationChannelV1
    let topics: [String]
    let state: CommunicationPreferenceStateV1
    let changedBy: CommunicationConsentingActorV1
    let changedAt: Date
    let suppression: SuppressionRecordReferenceV1?
    let predecessor: CommunicationPreferenceReferenceV1?
    let collectionDisposition: CommunicationCollectionDispositionV1
    let preferenceSHA256: String

    init(
        preferenceID: UUID,
        revision: UInt64,
        consent: CommunicationConsentReferenceV1,
        purpose: CommunicationPurposeV1,
        channel: CommunicationChannelV1 = .email,
        topics: [String],
        state: CommunicationPreferenceStateV1,
        changedBy: CommunicationConsentingActorV1,
        changedAt: Date,
        suppression: SuppressionRecordReferenceV1? = nil,
        predecessor: CommunicationPreferenceReferenceV1? = nil
    ) throws {
        let orderedTopics = topics.sorted()
        let digestBasis = Basis(
            schemaVersion: Self.schemaVersion, preferenceID: preferenceID, revision: revision,
            consent: consent, purpose: purpose, channel: channel, topics: orderedTopics,
            state: state, changedBy: changedBy, changedAt: changedAt,
            suppression: suppression, predecessor: predecessor,
            collectionDisposition: .disabledNoSubscriberCollectionOrTransmission
        )
        schemaVersion = Self.schemaVersion; self.preferenceID = preferenceID; self.revision = revision
        self.consent = consent; self.purpose = purpose; self.channel = channel
        self.topics = orderedTopics; self.state = state; self.changedBy = changedBy
        self.changedAt = changedAt; self.suppression = suppression; self.predecessor = predecessor
        collectionDisposition = .disabledNoSubscriberCollectionOrTransmission
        preferenceSHA256 = try CommunicationConsentCanonicalCodecV1.sha256(digestBasis)
        try validate()
    }

    var reference: CommunicationPreferenceReferenceV1 {
        get throws { try .init(
            preferenceID: preferenceID, revision: revision, purpose: purpose,
            channel: channel, preferenceSHA256: preferenceSHA256
        ) }
    }

    func validateSuccessor(of old: Self) throws {
        try validate(); try old.validate()
        guard predecessor == (try old.reference),
              preferenceID == old.preferenceID,
              consent.receiptID == old.consent.receiptID,
              purpose == old.purpose,
              channel == old.channel,
              topics == old.topics,
              old.state != .withdrawn || state == .withdrawn else {
            throw CommunicationConsentContractFailureV1.invalidSuccessor
        }
    }

    func validate() throws {
        try CommunicationConsentValidationV1.uuid(preferenceID)
        try consent.validate(); try CommunicationConsentValidationV1.nontransactional(purpose)
        try CommunicationConsentValidationV1.sortedUniqueIdentifiers(topics, maximumCount: 64)
        try changedBy.validate(); try CommunicationConsentValidationV1.instant(changedAt)
        try suppression?.validate(); try predecessor?.validate()
        let suppressionMatches = suppression.map {
            $0.purpose == purpose && $0.channel == channel
        } ?? false
        guard schemaVersion == Self.schemaVersion, revision > 0,
              consent.purpose == purpose, consent.channel == channel, consent.topics == topics,
              (state == .withdrawn) == suppressionMatches,
              (revision == 1) == (predecessor == nil),
              collectionDisposition == .disabledNoSubscriberCollectionOrTransmission,
              preferenceSHA256 == (try CommunicationConsentCanonicalCodecV1.sha256(basis)) else {
            throw CommunicationConsentContractFailureV1.suppressionRequired
        }
        if let predecessor {
            guard predecessor.preferenceID == preferenceID,
                  predecessor.purpose == purpose, predecessor.channel == channel,
                  CommunicationConsentValidationV1.isImmediateSuccessor(
                    revision, of: predecessor.revision
                  ) else {
                throw CommunicationConsentContractFailureV1.invalidSuccessor
            }
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, preferenceID: preferenceID, revision: revision,
        consent: consent, purpose: purpose, channel: channel, topics: topics,
        state: state, changedBy: changedBy, changedAt: changedAt,
        suppression: suppression, predecessor: predecessor,
        collectionDisposition: collectionDisposition
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let preferenceID: UUID; let revision: UInt64
        let consent: CommunicationConsentReferenceV1; let purpose: CommunicationPurposeV1
        let channel: CommunicationChannelV1; let topics: [String]
        let state: CommunicationPreferenceStateV1; let changedBy: CommunicationConsentingActorV1
        let changedAt: Date; let suppression: SuppressionRecordReferenceV1?
        let predecessor: CommunicationPreferenceReferenceV1?
        let collectionDisposition: CommunicationCollectionDispositionV1
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, preferenceID, revision, consent, purpose, channel, topics
        case state, changedBy, changedAt, suppression, predecessor
        case collectionDisposition, preferenceSHA256
    }
    init(from decoder: any Decoder) throws {
        try CommunicationConsentClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(CommunicationCollectionDispositionV1.self, forKey: .collectionDisposition)
                == .disabledNoSubscriberCollectionOrTransmission else {
            throw CommunicationConsentContractFailureV1.nonCanonicalData
        }
        let value = try Self(
            preferenceID: c.decode(UUID.self, forKey: .preferenceID),
            revision: c.decode(UInt64.self, forKey: .revision),
            consent: c.decode(CommunicationConsentReferenceV1.self, forKey: .consent),
            purpose: c.decode(CommunicationPurposeV1.self, forKey: .purpose),
            channel: c.decode(CommunicationChannelV1.self, forKey: .channel),
            topics: c.decode([String].self, forKey: .topics),
            state: c.decode(CommunicationPreferenceStateV1.self, forKey: .state),
            changedBy: c.decode(CommunicationConsentingActorV1.self, forKey: .changedBy),
            changedAt: c.decode(Date.self, forKey: .changedAt),
            suppression: c.decodeIfPresent(SuppressionRecordReferenceV1.self, forKey: .suppression),
            predecessor: c.decodeIfPresent(CommunicationPreferenceReferenceV1.self, forKey: .predecessor)
        )
        guard value.preferenceSHA256 == c.decode(String.self, forKey: .preferenceSHA256) else {
            throw CommunicationConsentContractFailureV1.invalidDigest
        }
        self = value
    }
}

/// C44 exposes an application-owned future port shape with no operational
/// methods. Release code has no conformer and cannot enroll, reconcile, or send.
protocol EmailServiceProviderAdapterV1: Sendable {
    var bindingDisposition: EmailServiceProviderBindingDispositionV1 { get }
    var collectionDisposition: CommunicationCollectionDispositionV1 { get }
}

enum CommunicationRuntimeBoundaryV1 {
    static let collectionDisposition: CommunicationCollectionDispositionV1 =
        .disabledNoSubscriberCollectionOrTransmission
    static let activationGate: CommunicationActivationGateV1 =
        .disabledNoSubscriberCollectionOrTransmission
    static let ownerDecision: CommunicationOwnerActivationDecisionV1 = .notProposed
    static let durableModelCount = 0
    static let subscriberCollectionEnabled = false
    static let subscriberPersistenceEnabled = false
    static let providerBound = false
    static let providerTransmissionEnabled = false
    static let networkOrEndpointEnabled = false
    static let backgroundTaskEnabled = false
    static let operationalContactBridgeEnabled = false
    static let customerLearningBridgeEnabled = false
    static let remoteActivationEnabled = false

    static func validate() throws {
        guard collectionDisposition == .disabledNoSubscriberCollectionOrTransmission,
              activationGate == .disabledNoSubscriberCollectionOrTransmission,
              ownerDecision == .notProposed,
              durableModelCount == 0,
              !subscriberCollectionEnabled,
              !subscriberPersistenceEnabled,
              !providerBound,
              !providerTransmissionEnabled,
              !networkOrEndpointEnabled,
              !backgroundTaskEnabled,
              !operationalContactBridgeEnabled,
              !customerLearningBridgeEnabled,
              !remoteActivationEnabled else {
            throw CommunicationConsentContractFailureV1.providerForbidden
        }
    }
}

enum ZeroSubscriberTransmissionEvidenceDispositionV1: String, Codable, CaseIterable, Sendable {
    case pendingExactCandidateArchiveRuntimeNativeEvidence =
        "PENDING_EXACT_CANDIDATE_ARCHIVE_RUNTIME_NATIVE_EVIDENCE"
}

/// Deliberately uninhabited in C44. Static documents, synthetic observations,
/// and opaque digests cannot mint a final zero-subscriber conformance receipt.
enum ZeroSubscriberTransmissionConformanceReceiptV1 {
    static let issuanceDisposition: ZeroSubscriberTransmissionEvidenceDispositionV1 =
        .pendingExactCandidateArchiveRuntimeNativeEvidence
    static let collectionDisposition: CommunicationCollectionDispositionV1 =
        .disabledNoSubscriberCollectionOrTransmission
    static let authorizesIssuance = false

    static func requireIssuanceAuthority() throws -> Never {
        throw CommunicationConsentContractFailureV1.issuanceForbidden
    }
}

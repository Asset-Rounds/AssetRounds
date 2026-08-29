import Foundation

@testable import FieldEvidenceApp

enum SyntheticCommunicationEnrollmentSourceV1: Equatable, Sendable {
    case governed(ContactSourceReferenceV1)
    case transactionalReceipt
    case supportRequest
    case incidentNotice
    case workspaceInvitation
    case purchaseRecord
    case feedbackMessage
    case diagnosticAttachment
    case fieldResearchParticipation
    case customerLearningAggregate
    case appStoreAggregate
}

struct SyntheticCommunicationConsentInputV1: Equatable, Sendable {
    let purpose: CommunicationPurposeV1
    let topics: [String]
    let source: SyntheticCommunicationEnrollmentSourceV1
    let affirmativeMethod: CommunicationAffirmativeMethodV1?
    let affirmative: Bool
    let prechecked: Bool
    let inferred: Bool
    let actorCapacity: CommunicationActorCapacityV1
    let lawfulBasis: CommunicationLawfulBasisDispositionV1
    let presentedDisclosure: ConsentDisclosureReferenceV1?
    let currentDisclosure: ConsentDisclosureReferenceV1
    let presentedLocaleIdentifier: String

    init(
        purpose: CommunicationPurposeV1,
        topics: [String],
        source: SyntheticCommunicationEnrollmentSourceV1,
        affirmativeMethod: CommunicationAffirmativeMethodV1?,
        affirmative: Bool,
        prechecked: Bool = false,
        inferred: Bool = false,
        actorCapacity: CommunicationActorCapacityV1 = .documentedSelfAssertion,
        lawfulBasis: CommunicationLawfulBasisDispositionV1 = .documentedAffirmativeConsent,
        presentedDisclosure: ConsentDisclosureReferenceV1?,
        currentDisclosure: ConsentDisclosureReferenceV1,
        presentedLocaleIdentifier: String
    ) {
        self.purpose = purpose
        self.topics = topics.sorted()
        self.source = source
        self.affirmativeMethod = affirmativeMethod
        self.affirmative = affirmative
        self.prechecked = prechecked
        self.inferred = inferred
        self.actorCapacity = actorCapacity
        self.lawfulBasis = lawfulBasis
        self.presentedDisclosure = presentedDisclosure
        self.currentDisclosure = currentDisclosure
        self.presentedLocaleIdentifier = presentedLocaleIdentifier
    }
}

enum SyntheticCommunicationAttemptBoundaryV1: String, Codable, CaseIterable, Sendable {
    case beforeEvaluation = "BEFORE_EVALUATION"
    case afterEvaluation = "AFTER_EVALUATION"
    case beforeProviderBoundary = "BEFORE_PROVIDER_BOUNDARY"
    case providerUnavailable = "PROVIDER_UNAVAILABLE"
}

struct SyntheticCommunicationAttemptV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let purpose: CommunicationPurposeV1
    let consentSHA256: String
    let suppressionRecordSHA256: String?
    let boundary: SyntheticCommunicationAttemptBoundaryV1
}

struct SyntheticCommunicationAttemptResultV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let activationGate: CommunicationActivationGateV1
    let collectionDisposition: CommunicationCollectionDispositionV1
    let providerBinding: EmailServiceProviderBindingDispositionV1
    let providerCallCount: Int
    let persistedSubscriberCount: Int
    let transmittedMessageCount: Int
    let retryDisposition: String
}

/// Pure C44 test-target evaluator. It accepts only caller-supplied descriptors
/// and synthetic values. It has no clock, storage, identity, credential,
/// endpoint, provider, network, diagnostics, or application-runtime dependency.
enum CommunicationConsentSyntheticEvaluatorV1 {
    static func compare(
        _ lhs: ExactCommunicationAddressV1,
        _ rhs: ExactCommunicationAddressV1,
        policy: ContactComparisonPolicyReleaseV1
    ) throws -> ContactAddressComparisonResultV1 {
        try lhs.validate()
        try rhs.validate()
        try policy.validate()
        guard lhs.channel == rhs.channel else { return .distinct }
        if lhs.exactEnteredValue == rhs.exactEnteredValue { return .exactMatch }
        if reviewComparisonKey(lhs.exactEnteredValue)
            == reviewComparisonKey(rhs.exactEnteredValue) {
            return .reviewRequired
        }
        return .distinct
    }

    static func eligibility(
        _ input: SyntheticCommunicationConsentInputV1
    ) throws -> CommunicationConsentEligibilityV1 {
        try input.currentDisclosure.validate()
        try input.presentedDisclosure?.validate()
        if input.purpose == .transactionalOrSupport {
            return .ineligibleTransactionalOrSupport
        }
        guard input.affirmative, !input.prechecked, !input.inferred,
              input.affirmativeMethod != nil else {
            return .ineligibleNonaffirmative
        }
        guard case let .governed(source) = input.source else {
            return .ineligibleSource
        }
        try source.validate()
        guard sourcePermits(
            purpose: input.purpose,
            source: source.kind,
            method: input.affirmativeMethod
        ) else {
            return .ineligibleSource
        }
        guard input.actorCapacity != .reviewRequired,
              input.lawfulBasis == .documentedAffirmativeConsent else {
            return .ineligibleLawfulBasis
        }
        guard let disclosure = input.presentedDisclosure,
              disclosure == input.currentDisclosure,
              disclosure.purpose == input.purpose,
              disclosure.topics == input.topics,
              disclosure.localeIdentifier == input.presentedLocaleIdentifier else {
            return .ineligibleDisclosure
        }
        return .eligibleExplicitIndependentEnrollment
    }

    static func marketingContactState(
        eligibility: CommunicationConsentEligibilityV1,
        verification: CommunicationVerificationStatusV1,
        withdrawn: Bool,
        expired: Bool,
        suppressed: Bool
    ) -> MarketingContactStateV1? {
        guard eligibility == .eligibleExplicitIndependentEnrollment else { return nil }
        if suppressed { return .suppressed }
        if withdrawn { return .withdrawn }
        if expired || verification == .expired { return .expired }
        if verification == .verified { return .verifiedPendingSeparateActivation }
        if verification == .pending { return .verificationPending }
        return .affirmativeEnrollmentRecorded
    }

    static func evaluatePreference(
        _ preference: CommunicationPreferenceV1,
        consent: CommunicationConsentReceiptV1,
        suppression: SuppressionRecordV1?,
        evaluatedAt: Date
    ) throws -> CommunicationPreferenceEvaluationV1 {
        try preference.validate()
        try consent.validate()
        if preference.purpose != consent.purpose
            || preference.channel != consent.channel
            || preference.consent != (try consent.reference) {
            return .reviewRequired
        }
        if let suppression {
            try suppression.validate()
            guard preference.suppression == (try suppression.reference),
                  suppression.purpose == preference.purpose,
                  suppression.channel == preference.channel else {
                return .reviewRequired
            }
            return .suppressed
        }
        if preference.state == .withdrawn || !consent.withdrawalHistory.isEmpty {
            return .withdrawn
        }
        if let expiresAt = consent.expiresAt, evaluatedAt >= expiresAt { return .expired }
        return .eligiblePendingSeparateActivation
    }

    static func evaluateSuppression(
        candidateToken: ServiceSideKeyedSuppressionTokenV1?,
        record: SuppressionRecordV1
    ) throws -> CommunicationSuppressionEvaluationV1 {
        try record.validate()
        guard let candidateToken else { return .reviewRequired }
        try candidateToken.validate()
        guard candidateToken.serviceAuthorityID == record.token.serviceAuthorityID,
              candidateToken.keyReleaseID == record.token.keyReleaseID else {
            return .reviewRequired
        }
        return candidateToken == record.token ? .blocked : .notMatched
    }

    static func deterministicNoTransmissionResult(
        for attempt: SyntheticCommunicationAttemptV1
    ) throws -> SyntheticCommunicationAttemptResultV1 {
        let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard attempt.operationID != zeroUUID,
              attempt.consentSHA256.count == 64,
              attempt.consentSHA256.allSatisfy({ $0.isHexDigit }),
              attempt.suppressionRecordSHA256.map({
                  $0.count == 64 && $0.allSatisfy { $0.isHexDigit }
              }) ?? true else {
            throw CommunicationConsentContractFailureV1.invalidValue
        }
        return SyntheticCommunicationAttemptResultV1(
            operationID: attempt.operationID,
            activationGate: .disabledNoSubscriberCollectionOrTransmission,
            collectionDisposition: .disabledNoSubscriberCollectionOrTransmission,
            providerBinding: .unboundNoSelectedProvider,
            providerCallCount: 0,
            persistedSubscriberCount: 0,
            transmittedMessageCount: 0,
            retryDisposition: "BYTE_IDENTICAL_RESULT_OR_NO_EFFECT"
        )
    }

    static func canonicalResultData(
        _ result: SyntheticCommunicationAttemptResultV1
    ) throws -> Data {
        try CommunicationConsentCanonicalCodecV1.encode(result)
    }

    private static func sourcePermits(
        purpose: CommunicationPurposeV1,
        source: ContactSourceKindV1,
        method: CommunicationAffirmativeMethodV1?
    ) -> Bool {
        switch purpose {
        case .newsletter, .productUpdate:
            return (source == .controlledBackendAffirmativeEnrollment
                    && method == .explicitUncheckedControl)
                || (source == .providerHostedAffirmativeEnrollment
                    && method == .providerHostedConfirmation)
        case .researchInvitation:
            return source == .separatelyAuthorizedResearchInvitationEnrollment
                && method == .documentedIndependentResearchInvitationEnrollment
        case .transactionalOrSupport:
            return false
        }
    }

    private static func reviewComparisonKey(_ value: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping.lowercased()
        guard let at = normalized.lastIndex(of: "@") else { return normalized }
        var local = String(normalized[..<at])
        let domain = String(normalized[normalized.index(after: at)...])
        if let plus = local.firstIndex(of: "+") { local = String(local[..<plus]) }
        return "\(local)@\(domain)"
    }
}

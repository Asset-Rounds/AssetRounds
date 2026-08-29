import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C44CommunicationConsentCorpusV1: Decodable {
    struct Purpose: Decodable {
        let purpose: String
        let createsMarketingContact: Bool
        let independentAffirmativeEnrollmentRequired: Bool
        let consentNontransitive: Bool
        let transactionalExclusionOnly: Bool
    }

    struct TruthCase: Decodable {
        let caseID: String
        let purpose: String
        let source: String
        let affirmative: Bool
        let prechecked: Bool
        let inferred: Bool
        let disclosureReleaseID: String
        let presentedLocale: String
        let verificationStatus: String
        let expectedDisposition: String
    }

    struct NormalizationCase: Decodable {
        let caseID: String
        let enteredAddress: String
        let comparisonAddress: String
        let policyReleaseID: String
        let collisionDisposition: String
    }

    struct DisclosureRelease: Decodable {
        let releaseID: String
        let version: Int
        let digest: String
        let locales: [String]
        let immutable: Bool
        let superseded: Bool
    }

    struct SuppressionCase: Decodable {
        let caseID: String
        let purpose: String
        let channel: String
        let tokenKind: String
        let plainHashForbidden: Bool
        let deleteReimportDisposition: String
        let audienceUseForbidden: Bool
    }

    struct ArchiveProof: Decodable {
        let surface: String
        let disposition: String
        let forbiddenFindings: [String]
        let repositoryScanPathCount: Int?
        let repositoryScanPathSetSHA256: String?
        let repositoryScanAggregateContentSHA256: String?
        let repositoryScanDependencyInventorySHA256: String?
        let repositoryScanDigest: String?
        let repositoryScanProhibitedFindingCount: Int?
    }

    struct Lifecycle: Decodable {
        let persistence: String
        let contracts: String
        let providerPort: String
        let runtimeStorage: String
        let runtimeProvider: String
        let runtimeNetwork: String
        let retry: String
        let rollback: String
        let supersession: String
    }

    struct Invariants: Decodable {
        let purposeConsentNontransitive: Bool
        let transactionalNeverCreatesMarketingContact: Bool
        let operationalContactsNeverConvert: Bool
        let exactEnteredAddressPreserved: Bool
        let normalizationPolicyVersioned: Bool
        let collisionsRequireReview: Bool
        let disclosureReleaseAndLocalePinned: Bool
        let withdrawalAppendOnly: Bool
        let suppressionSurvivesDeleteAndReimport: Bool
        let plainHashForbidden: Bool
        let suppressionNotAudience: Bool
        let providerPortUnbound: Bool
        let providerSecretsAbsentFromApp: Bool
        let noSubscriberPersistence: Bool
        let noNetworkTransmission: Bool
        let configCannotActivate: Bool
        let ownerAcceptanceRequired: Bool
        let adAudienceEquivalenceForbidden: Bool

        var all: [Bool] {
            [
                purposeConsentNontransitive, transactionalNeverCreatesMarketingContact,
                operationalContactsNeverConvert, exactEnteredAddressPreserved,
                normalizationPolicyVersioned, collisionsRequireReview,
                disclosureReleaseAndLocalePinned, withdrawalAppendOnly,
                suppressionSurvivesDeleteAndReimport, plainHashForbidden,
                suppressionNotAudience, providerPortUnbound, providerSecretsAbsentFromApp,
                noSubscriberPersistence, noNetworkTransmission, configCannotActivate,
                ownerAcceptanceRequired, adAudienceEquivalenceForbidden,
            ]
        }
    }

    struct StatusFlags: Decodable {
        let native: Bool
        let hosted: Bool
        let adoption: Bool
        let acceptance: Bool
        let release: Bool

        var all: [Bool] { [native, hosted, adoption, acceptance, release] }
    }

    let schema: String
    let schemaVersion: Int
    let cardID: String
    let classification: String
    let collectionDisposition: String
    let purposes: [Purpose]
    let consentTruthTable: [TruthCase]
    let normalizationCases: [NormalizationCase]
    let disclosureReleases: [DisclosureRelease]
    let suppressionCases: [SuppressionCase]
    let hostileCases: [String]
    let archiveProofs: [ArchiveProof]
    let lifecycle: Lifecycle
    let invariants: Invariants
    let evidenceIDs: [String]
    let statusFlags: StatusFlags
}

private struct C44FixtureV1 {
    let policy: ContactComparisonPolicyReleaseV1
    let source: ContactSourceV1
    let disclosure: ConsentDisclosureReleaseV1
    let address: ExactCommunicationAddressV1
    let actor: CommunicationConsentingActorV1
    let verification: CommunicationVerificationV1
    let jurisdiction: CommunicationJurisdictionBasisV1
    let consent: CommunicationConsentReceiptV1
}

private struct C44UnboundProviderDescriptorV1: EmailServiceProviderAdapterV1 {
    let bindingDisposition: EmailServiceProviderBindingDispositionV1 =
        .unboundNoSelectedProvider
    let collectionDisposition: CommunicationCollectionDispositionV1 =
        .disabledNoSubscriberCollectionOrTransmission
}

final class V9_51CommunicationConsentTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private let digestA = String(repeating: "a", count: 64)

    func testV23P03C44G01IndependentAffirmativeEnrollmentCreatesOnlyExactPurposeMarketingContact() throws {
        let corpus = try loadCorpus()
        try assertCorpusBoundary(corpus)
        let fixture = try makeFixture()
        let input = try eligibleInput(fixture)

        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(input),
            .eligibleExplicitIndependentEnrollment
        )
        XCTAssertEqual(
            CommunicationConsentSyntheticEvaluatorV1.marketingContactState(
                eligibility: .eligibleExplicitIndependentEnrollment,
                verification: fixture.verification.status,
                withdrawn: false,
                expired: false,
                suppressed: false
            ),
            .verifiedPendingSeparateActivation
        )

        let contact = try MarketingContactV1(
            contactID: uuid(20),
            revision: 1,
            address: fixture.address,
            comparisonPolicy: fixture.policy.reference,
            purpose: .newsletter,
            topics: fixture.disclosure.topics,
            consent: fixture.consent.reference,
            state: .verifiedPendingSeparateActivation,
            recordedAt: instant.addingTimeInterval(30)
        )
        XCTAssertEqual(contact.address.exactEnteredValue, "Owner+Field@example.invalid")
        XCTAssertEqual(contact.purpose, .newsletter)
        XCTAssertEqual(contact.collectionDisposition, .disabledNoSubscriberCollectionOrTransmission)
        XCTAssertEqual(contact.consent, try fixture.consent.reference)

        let encoded = try CommunicationConsentCanonicalCodecV1.encode(contact)
        XCTAssertEqual(
            try CommunicationConsentCanonicalCodecV1.decode(MarketingContactV1.self, from: encoded),
            contact
        )
        XCTAssertEqual(
            try CommunicationConsentCanonicalCodecV1.sha256(contact),
            try CommunicationConsentCanonicalCodecV1.sha256(
                CommunicationConsentCanonicalCodecV1.decode(MarketingContactV1.self, from: encoded)
            )
        )

        let productDisclosure = try makeDisclosure(
            id: uuid(31), purpose: .productUpdate, topics: ["TOPIC.PRODUCT.RELEASES"]
        )
        let crossPurpose = SyntheticCommunicationConsentInputV1(
            purpose: .productUpdate,
            topics: productDisclosure.topics,
            source: .governed(try fixture.source.reference),
            affirmativeMethod: .explicitUncheckedControl,
            affirmative: true,
            presentedDisclosure: try fixture.disclosure.reference,
            currentDisclosure: try productDisclosure.reference,
            presentedLocaleIdentifier: "en-US"
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(crossPurpose),
            .ineligibleDisclosure
        )
        XCTAssertThrowsError(try MarketingContactV1(
            contactID: uuid(21),
            revision: 1,
            address: fixture.address,
            comparisonPolicy: fixture.policy.reference,
            purpose: .productUpdate,
            topics: productDisclosure.topics,
            consent: fixture.consent.reference,
            state: .verifiedPendingSeparateActivation,
            recordedAt: instant.addingTimeInterval(30)
        ))

        XCTAssertNoThrow(try CommunicationRuntimeBoundaryV1.validate())
        XCTAssertEqual(CommunicationRuntimeBoundaryV1.durableModelCount, 0)
        XCTAssertFalse(CommunicationRuntimeBoundaryV1.subscriberCollectionEnabled)
        XCTAssertFalse(CommunicationRuntimeBoundaryV1.subscriberPersistenceEnabled)
        XCTAssertFalse(CommunicationRuntimeBoundaryV1.providerBound)
        XCTAssertFalse(CommunicationRuntimeBoundaryV1.providerTransmissionEnabled)
        let providerDescriptor = C44UnboundProviderDescriptorV1()
        XCTAssertEqual(providerDescriptor.bindingDisposition, .unboundNoSelectedProvider)
        XCTAssertEqual(
            providerDescriptor.collectionDisposition,
            .disabledNoSubscriberCollectionOrTransmission
        )
    }

    func testV23P03C44A01TransactionalOperationalAndResearchSourcesNeverInferMarketingConsent() throws {
        let fixture = try makeFixture()
        let governed = try eligibleInput(fixture)
        let operationalSources: [SyntheticCommunicationEnrollmentSourceV1] = [
            .transactionalReceipt, .supportRequest, .incidentNotice, .workspaceInvitation,
            .purchaseRecord, .feedbackMessage, .diagnosticAttachment,
            .fieldResearchParticipation, .customerLearningAggregate, .appStoreAggregate,
        ]
        for source in operationalSources {
            let input = SyntheticCommunicationConsentInputV1(
                purpose: .newsletter,
                topics: governed.topics,
                source: source,
                affirmativeMethod: .explicitUncheckedControl,
                affirmative: true,
                presentedDisclosure: governed.presentedDisclosure,
                currentDisclosure: governed.currentDisclosure,
                presentedLocaleIdentifier: governed.presentedLocaleIdentifier
            )
            XCTAssertEqual(
                try CommunicationConsentSyntheticEvaluatorV1.eligibility(input),
                .ineligibleSource,
                "Operational source \(source) must never become enrollment"
            )
        }

        let transactional = SyntheticCommunicationConsentInputV1(
            purpose: .transactionalOrSupport,
            topics: governed.topics,
            source: .transactionalReceipt,
            affirmativeMethod: .explicitUncheckedControl,
            affirmative: true,
            presentedDisclosure: governed.presentedDisclosure,
            currentDisclosure: governed.currentDisclosure,
            presentedLocaleIdentifier: governed.presentedLocaleIdentifier
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(transactional),
            .ineligibleTransactionalOrSupport
        )
        XCTAssertNil(CommunicationConsentSyntheticEvaluatorV1.marketingContactState(
            eligibility: .ineligibleTransactionalOrSupport,
            verification: .verified,
            withdrawn: false,
            expired: false,
            suppressed: false
        ))

        let inferredResearch = SyntheticCommunicationConsentInputV1(
            purpose: .researchInvitation,
            topics: ["TOPIC.RESEARCH.INTERVIEW"],
            source: .fieldResearchParticipation,
            affirmativeMethod: nil,
            affirmative: false,
            inferred: true,
            presentedDisclosure: nil,
            currentDisclosure: try makeDisclosure(
                id: uuid(32), purpose: .researchInvitation,
                topics: ["TOPIC.RESEARCH.INTERVIEW"]
            ).reference,
            presentedLocaleIdentifier: "en-US"
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(inferredResearch),
            .ineligibleNonaffirmative
        )

        let prechecked = SyntheticCommunicationConsentInputV1(
            purpose: governed.purpose,
            topics: governed.topics,
            source: governed.source,
            affirmativeMethod: governed.affirmativeMethod,
            affirmative: true,
            prechecked: true,
            presentedDisclosure: governed.presentedDisclosure,
            currentDisclosure: governed.currentDisclosure,
            presentedLocaleIdentifier: governed.presentedLocaleIdentifier
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(prechecked),
            .ineligibleNonaffirmative
        )

        let corpus = try loadCorpus()
        let allowed = Set(CommunicationConsentEligibilityV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.consentTruthTable.allSatisfy {
            allowed.contains($0.expectedDisposition)
        })
        XCTAssertTrue(Set(corpus.consentTruthTable.map(\.expectedDisposition)).isSuperset(of: [
            CommunicationConsentEligibilityV1.eligibleExplicitIndependentEnrollment.rawValue,
            CommunicationConsentEligibilityV1.reviewRequired.rawValue,
            CommunicationConsentEligibilityV1.ineligibleTransactionalOrSupport.rawValue,
            CommunicationConsentEligibilityV1.ineligibleNonaffirmative.rawValue,
            CommunicationConsentEligibilityV1.ineligibleSource.rawValue,
            CommunicationConsentEligibilityV1.ineligibleDisclosure.rawValue,
            CommunicationConsentEligibilityV1.ineligibleLawfulBasis.rawValue,
        ]))
    }

    func testV23P03C44H01NormalizationCollisionsStaleDisclosureAndCrossPurposeReuseFailClosed() throws {
        let fixture = try makeFixture()
        let exactCopy = try ExactCommunicationAddressV1(
            exactEnteredValue: fixture.address.exactEnteredValue
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.compare(
                fixture.address, exactCopy, policy: fixture.policy
            ),
            .exactMatch
        )
        for candidate in [
            "owner@example.invalid",
            "owner+field@example.invalid",
            "OWNER+FIELD@EXAMPLE.INVALID",
        ] {
            XCTAssertEqual(
                try CommunicationConsentSyntheticEvaluatorV1.compare(
                    fixture.address,
                    ExactCommunicationAddressV1(exactEnteredValue: candidate),
                    policy: fixture.policy
                ),
                .reviewRequired
            )
        }
        let composed = try ExactCommunicationAddressV1(exactEnteredValue: "café@example.invalid")
        let decomposed = try ExactCommunicationAddressV1(exactEnteredValue: "café@example.invalid")
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.compare(
                composed, decomposed, policy: fixture.policy
            ),
            .reviewRequired
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.compare(
                fixture.address,
                ExactCommunicationAddressV1(exactEnteredValue: "different@example.invalid"),
                policy: fixture.policy
            ),
            .distinct
        )

        let policyV2 = try ContactComparisonPolicyReleaseV1(
            policyID: fixture.policy.policyID,
            revision: 2,
            effectiveAt: instant.addingTimeInterval(100),
            supersedes: fixture.policy.reference
        )
        XCTAssertNotEqual(policyV2.policySHA256, fixture.policy.policySHA256)
        XCTAssertEqual(policyV2.supersedes, try fixture.policy.reference)
        XCTAssertEqual(fixture.policy.revision, 1)

        let disclosureV2 = try ConsentDisclosureReleaseV1(
            disclosureID: fixture.disclosure.disclosureID,
            revision: 2,
            purpose: fixture.disclosure.purpose,
            topics: fixture.disclosure.topics,
            localeIdentifier: "en-US",
            disclosureText: "Version two: independent newsletter enrollment and withdrawal.",
            effectiveAt: instant.addingTimeInterval(100),
            supersedes: fixture.disclosure.reference
        )
        let stale = SyntheticCommunicationConsentInputV1(
            purpose: .newsletter,
            topics: fixture.disclosure.topics,
            source: .governed(try fixture.source.reference),
            affirmativeMethod: .explicitUncheckedControl,
            affirmative: true,
            presentedDisclosure: try fixture.disclosure.reference,
            currentDisclosure: try disclosureV2.reference,
            presentedLocaleIdentifier: "en-US"
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(stale),
            .ineligibleDisclosure
        )
        let wrongLocale = SyntheticCommunicationConsentInputV1(
            purpose: .newsletter,
            topics: disclosureV2.topics,
            source: stale.source,
            affirmativeMethod: stale.affirmativeMethod,
            affirmative: true,
            presentedDisclosure: try disclosureV2.reference,
            currentDisclosure: try disclosureV2.reference,
            presentedLocaleIdentifier: "fr-FR"
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(wrongLocale),
            .ineligibleDisclosure
        )
        let uncertainLaw = SyntheticCommunicationConsentInputV1(
            purpose: stale.purpose,
            topics: stale.topics,
            source: stale.source,
            affirmativeMethod: stale.affirmativeMethod,
            affirmative: true,
            actorCapacity: .reviewRequired,
            lawfulBasis: .ownerReviewRequired,
            presentedDisclosure: try disclosureV2.reference,
            currentDisclosure: try disclosureV2.reference,
            presentedLocaleIdentifier: "en-US"
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.eligibility(uncertainLaw),
            .ineligibleLawfulBasis
        )

        XCTAssertThrowsError(try CommunicationPreferenceV1(
            preferenceID: uuid(40),
            revision: 1,
            consent: fixture.consent.reference,
            purpose: .productUpdate,
            topics: ["TOPIC.PRODUCT.RELEASES"],
            state: .enrolled,
            changedBy: fixture.actor,
            changedAt: instant.addingTimeInterval(30)
        ))
        XCTAssertTrue((try loadCorpus()).hostileCases.contains("TRANSACTIONAL_COPY_CONTAINING_MARKETING"))
    }

    func testV23P03C44I01WithdrawalSuppressionAndProviderRetryRemainIdempotentWithoutTransmission() throws {
        let fixture = try makeFixture()
        let withdrawal = try CommunicationWithdrawalEventV1(
            eventID: uuid(50),
            purpose: .newsletter,
            reason: .requested,
            requestedBy: fixture.actor,
            occurredAt: instant.addingTimeInterval(40),
            recordedAt: instant.addingTimeInterval(41)
        )
        let withdrawnConsent = try CommunicationConsentReceiptV1(
            receiptID: fixture.consent.receiptID,
            revision: 2,
            address: fixture.address,
            comparisonPolicy: fixture.policy.reference,
            purpose: .newsletter,
            topics: fixture.disclosure.topics,
            consentingActor: fixture.actor,
            source: fixture.source.reference,
            disclosure: fixture.disclosure.reference,
            presentedLocaleIdentifier: "en-US",
            affirmativeMethod: .explicitUncheckedControl,
            occurredAt: fixture.consent.occurredAt,
            recordedAt: instant.addingTimeInterval(42),
            verification: fixture.verification,
            jurisdictionBasis: fixture.jurisdiction,
            predecessor: fixture.consent.reference,
            withdrawalHistory: [withdrawal]
        )
        XCTAssertNoThrow(try withdrawnConsent.validateSuccessor(of: fixture.consent))
        XCTAssertEqual(withdrawnConsent.withdrawalHistory, [withdrawal])

        let token = try ServiceSideKeyedSuppressionTokenV1(
            serviceAuthorityID: "OWNER-CONTROLLED-SUPPRESSION-SERVICE",
            keyReleaseID: "KEY-RELEASE-7",
            opaqueToken: "KST1.opaque-owner-reviewed-token"
        )
        XCTAssertEqual(token.classification, .contactInfoPseudonymousNotAnonymous)
        let retention = try SuppressionRetentionDecisionV1(
            disposition: .ownerReviewedMinimumDoNotContact,
            ownerDecisionBasisSHA256: digestA,
            reviewedAt: instant.addingTimeInterval(43)
        )
        let suppression = try SuppressionRecordV1(
            recordID: uuid(51),
            revision: 1,
            purpose: .newsletter,
            token: token,
            source: fixture.source.reference,
            reason: .requested,
            withdrawalOccurredAt: withdrawal.occurredAt,
            comparisonPolicy: fixture.policy.reference,
            retentionDecision: retention
        )
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.evaluateSuppression(
                candidateToken: token, record: suppression
            ),
            .blocked
        )
        let afterSyntheticDeleteAndReimport = try CommunicationConsentSyntheticEvaluatorV1
            .evaluateSuppression(candidateToken: token, record: suppression)
        XCTAssertEqual(afterSyntheticDeleteAndReimport, .blocked)
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.evaluateSuppression(
                candidateToken: nil, record: suppression
            ),
            .reviewRequired
        )
        XCTAssertThrowsError(try ServiceSideKeyedSuppressionTokenV1(
            serviceAuthorityID: "LOCAL",
            keyReleaseID: "PLAIN-HASH",
            opaqueToken: digestA
        ))

        let preferenceV1 = try CommunicationPreferenceV1(
            preferenceID: uuid(52),
            revision: 1,
            consent: fixture.consent.reference,
            purpose: .newsletter,
            topics: fixture.disclosure.topics,
            state: .enrolled,
            changedBy: fixture.actor,
            changedAt: instant.addingTimeInterval(30)
        )
        let preferenceV2 = try CommunicationPreferenceV1(
            preferenceID: preferenceV1.preferenceID,
            revision: 2,
            consent: withdrawnConsent.reference,
            purpose: .newsletter,
            topics: fixture.disclosure.topics,
            state: .withdrawn,
            changedBy: fixture.actor,
            changedAt: instant.addingTimeInterval(44),
            suppression: suppression.reference,
            predecessor: preferenceV1.reference
        )
        XCTAssertNoThrow(try preferenceV2.validateSuccessor(of: preferenceV1))
        XCTAssertEqual(
            try CommunicationConsentSyntheticEvaluatorV1.evaluatePreference(
                preferenceV2,
                consent: withdrawnConsent,
                suppression: suppression,
                evaluatedAt: instant.addingTimeInterval(45)
            ),
            .suppressed
        )

        for boundary in SyntheticCommunicationAttemptBoundaryV1.allCases {
            let attempt = SyntheticCommunicationAttemptV1(
                operationID: uuid(60),
                purpose: .newsletter,
                consentSHA256: withdrawnConsent.consentSHA256,
                suppressionRecordSHA256: suppression.recordSHA256,
                boundary: boundary
            )
            let first = try CommunicationConsentSyntheticEvaluatorV1
                .deterministicNoTransmissionResult(for: attempt)
            let retry = try CommunicationConsentSyntheticEvaluatorV1
                .deterministicNoTransmissionResult(for: attempt)
            XCTAssertEqual(first, retry)
            XCTAssertEqual(
                try CommunicationConsentSyntheticEvaluatorV1.canonicalResultData(first),
                try CommunicationConsentSyntheticEvaluatorV1.canonicalResultData(retry)
            )
            XCTAssertEqual(first.providerCallCount, 0)
            XCTAssertEqual(first.persistedSubscriberCount, 0)
            XCTAssertEqual(first.transmittedMessageCount, 0)
            XCTAssertEqual(first.providerBinding, .unboundNoSelectedProvider)
        }
    }

    func testV23P03C44R01ArchiveRuntimeRollbackAndSupersessionPreserveZeroSubscriberPosture() throws {
        let corpus = try loadCorpus()
        // This is deliberately synthetic scanner-unit input. It is not a copy of,
        // discovery of, or claim about the shipping repository or dependency graph.
        let syntheticCategoryDocument = try ZeroSubscriberStaticDocumentV1(
            path: "SyntheticFixtures/DisabledDescriptor.swift",
            text: "enum SyntheticDisabledDescriptor { static let durableModelCount = 0 }"
        )
        let firstSyntheticScan = try ZeroSubscriberTransmissionConformanceScannerV1.scan(
            documents: [syntheticCategoryDocument]
        )
        let retrySyntheticScan = try ZeroSubscriberTransmissionConformanceScannerV1.scan(
            documents: [syntheticCategoryDocument]
        )
        XCTAssertEqual(firstSyntheticScan, retrySyntheticScan)
        XCTAssertTrue(firstSyntheticScan.isStaticSourceConformant)
        XCTAssertEqual(firstSyntheticScan.evidenceScope, .suppliedStaticDocumentsOnly)
        XCTAssertFalse(firstSyntheticScan.claimsReleaseArchiveInspection)
        XCTAssertFalse(firstSyntheticScan.claimsRuntimeNetworkObservation)
        let syntheticEvidence = try firstSyntheticScan.conformanceEvidence()
        XCTAssertEqual(syntheticEvidence.scope, .suppliedStaticDocumentsOnly)
        XCTAssertEqual(syntheticEvidence.scannedPaths, ["SyntheticFixtures/DisabledDescriptor.swift"])
        XCTAssertFalse(syntheticEvidence.claimsReleaseArchiveInspection)
        XCTAssertFalse(syntheticEvidence.claimsRuntimeNetworkObservation)

        let hostile = try ZeroSubscriberTransmissionConformanceScannerV1.scan([
            ZeroSubscriberStaticDocumentV1(
                path: "Sources/Forbidden.swift",
                text: "let subscriberRepository = MarketingSendQueue()"
            ),
        ])
        XCTAssertFalse(hostile.isStaticSourceConformant)
        XCTAssertFalse(hostile.findings.isEmpty)
        XCTAssertThrowsError(try hostile.conformanceEvidence())

        XCTAssertEqual(
            corpus.archiveProofs.map(\.surface),
            [
                "DEPENDENCY", "ARCHIVE", "LINK", "RESOURCE", "STRING", "ROUTE",
                "SETTINGS", "BACKGROUND_TASK", "CREDENTIAL", "ENDPOINT", "RUNTIME_NETWORK",
            ]
        )
        let dependencyProof = try XCTUnwrap(corpus.archiveProofs.first)
        XCTAssertEqual(dependencyProof.disposition, "STATIC_SOURCE_SCAN_CLEAN")
        XCTAssertEqual(dependencyProof.repositoryScanPathCount, 350)
        XCTAssertEqual(
            dependencyProof.repositoryScanPathSetSHA256,
            "5cde2690c42fbb057eaed8f6c84ac8d5cedc60105480a6caf5ee024f62b171a2"
        )
        XCTAssertEqual(
            dependencyProof.repositoryScanAggregateContentSHA256,
            "f601e4e503666e1e6f1bbdcb02e4e1e8413b84d64e9e96d648088819b8f6df87"
        )
        XCTAssertEqual(
            dependencyProof.repositoryScanDependencyInventorySHA256,
            "7dd6dcb0920f4832d6edc0f015f1153f92e38db0cf3a1af402c7a3e42f9414de"
        )
        XCTAssertEqual(
            dependencyProof.repositoryScanDigest,
            "0905bfebecf976d914cfcd83f3e0fbbbad97e7a0b2e570ca07e72c9338b24419"
        )
        XCTAssertEqual(dependencyProof.repositoryScanProhibitedFindingCount, 0)
        XCTAssertTrue(corpus.archiveProofs.dropFirst().allSatisfy {
            $0.disposition == "PENDING_NOT_ACCEPTING" && $0.forbiddenFindings.isEmpty
        })
        XCTAssertTrue(corpus.statusFlags.all.allSatisfy { !$0 })
        XCTAssertEqual(corpus.lifecycle.rollback, "REMOVE_UNACTIVATED_CONTRACT_AND_TEST_CHANGES")
        XCTAssertEqual(
            corpus.lifecycle.supersession,
            "IMMUTABLE_RELEASES_SUPERSEDED_NOT_REWRITTEN"
        )

        let fixture = try makeFixture()
        let successor = try ContactSourceV1(
            sourceID: fixture.source.sourceID,
            revision: 2,
            kind: fixture.source.kind,
            releaseID: "SOURCE.CONTROLLED.V2",
            ownerReadableDescription: "Successor static source policy.",
            effectiveAt: instant.addingTimeInterval(100),
            supersedes: fixture.source.reference
        )
        XCTAssertEqual(successor.supersedes, try fixture.source.reference)
        XCTAssertNotEqual(successor.sourceSHA256, fixture.source.sourceSHA256)
        XCTAssertEqual(fixture.source.revision, 1)

        XCTAssertNoThrow(try CommunicationRuntimeBoundaryV1.validate())
        XCTAssertEqual(
            ZeroSubscriberTransmissionConformanceReceiptV1.issuanceDisposition,
            .pendingExactCandidateArchiveRuntimeNativeEvidence
        )
        XCTAssertEqual(
            ZeroSubscriberTransmissionConformanceReceiptV1.collectionDisposition,
            .disabledNoSubscriberCollectionOrTransmission
        )
        XCTAssertFalse(ZeroSubscriberTransmissionConformanceReceiptV1.authorizesIssuance)
        XCTAssertThrowsError(
            try ZeroSubscriberTransmissionConformanceReceiptV1.requireIssuanceAuthority()
        ) { error in
            XCTAssertEqual(error as? CommunicationConsentContractFailureV1, .issuanceForbidden)
        }
    }

    private func makeFixture() throws -> C44FixtureV1 {
        let policy = try ContactComparisonPolicyReleaseV1(
            policyID: uuid(1), revision: 1, effectiveAt: instant
        )
        let source = try ContactSourceV1(
            sourceID: uuid(2),
            revision: 1,
            kind: .controlledBackendAffirmativeEnrollment,
            releaseID: "SOURCE.CONTROLLED.V1",
            ownerReadableDescription: "Independent unchecked newsletter enrollment.",
            effectiveAt: instant
        )
        let disclosure = try makeDisclosure(
            id: uuid(3), purpose: .newsletter, topics: ["TOPIC.FIELD.NOTES"]
        )
        let address = try ExactCommunicationAddressV1(
            exactEnteredValue: "Owner+Field@example.invalid"
        )
        let actor = try CommunicationConsentingActorV1(
            actorAssertionID: "ACTOR.SELF.ASSERTION.1",
            capacity: .documentedSelfAssertion,
            assertionRecordedAt: instant
        )
        let verification = try CommunicationVerificationV1(
            status: .verified,
            verifiedAt: instant.addingTimeInterval(10)
        )
        let jurisdiction = try CommunicationJurisdictionBasisV1(
            jurisdictionCode: "US-OWNER-REVIEWED",
            disposition: .documentedAffirmativeConsent,
            documentationSHA256: digestA
        )
        let consent = try CommunicationConsentReceiptV1(
            receiptID: uuid(4),
            revision: 1,
            address: address,
            comparisonPolicy: policy.reference,
            purpose: .newsletter,
            topics: disclosure.topics,
            consentingActor: actor,
            source: source.reference,
            disclosure: disclosure.reference,
            presentedLocaleIdentifier: "en-US",
            affirmativeMethod: .explicitUncheckedControl,
            occurredAt: instant,
            recordedAt: instant.addingTimeInterval(20),
            verification: verification,
            jurisdictionBasis: jurisdiction
        )
        return C44FixtureV1(
            policy: policy, source: source, disclosure: disclosure, address: address,
            actor: actor, verification: verification, jurisdiction: jurisdiction,
            consent: consent
        )
    }

    private func eligibleInput(
        _ fixture: C44FixtureV1
    ) throws -> SyntheticCommunicationConsentInputV1 {
        SyntheticCommunicationConsentInputV1(
            purpose: .newsletter,
            topics: fixture.disclosure.topics,
            source: .governed(try fixture.source.reference),
            affirmativeMethod: .explicitUncheckedControl,
            affirmative: true,
            presentedDisclosure: try fixture.disclosure.reference,
            currentDisclosure: try fixture.disclosure.reference,
            presentedLocaleIdentifier: "en-US"
        )
    }

    private func makeDisclosure(
        id: UUID,
        purpose: CommunicationPurposeV1,
        topics: [String]
    ) throws -> ConsentDisclosureReleaseV1 {
        try ConsentDisclosureReleaseV1(
            disclosureID: id,
            revision: 1,
            purpose: purpose,
            topics: topics,
            localeIdentifier: "en-US",
            disclosureText: "Independent purpose-scoped enrollment; withdrawal is available.",
            effectiveAt: instant
        )
    }

    private func uuid(_ suffix: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, suffix
        ))
    }

    private func loadCorpus() throws -> C44CommunicationConsentCorpusV1 {
        let url = Bundle(for: Self.self).url(
            forResource: "V22P03C44CommunicationConsentCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V22/Communications"
        ) ?? Bundle(for: Self.self).url(
            forResource: "V22P03C44CommunicationConsentCorpusV1",
            withExtension: "json"
        )
        guard let url else { throw CommunicationConsentContractFailureV1.invalidValue }
        return try JSONDecoder().decode(C44CommunicationConsentCorpusV1.self, from: Data(contentsOf: url))
    }

    private func assertCorpusBoundary(_ corpus: C44CommunicationConsentCorpusV1) throws {
        XCTAssertEqual(corpus.schema, "V22P03C44CommunicationConsentCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C44")
        XCTAssertEqual(corpus.classification, "PREPARE_NOW")
        XCTAssertEqual(
            corpus.collectionDisposition,
            CommunicationCollectionDispositionV1
                .disabledNoSubscriberCollectionOrTransmission.rawValue
        )
        XCTAssertEqual(corpus.purposes.map(\.purpose), CommunicationPurposeV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.purposes.allSatisfy(\.consentNontransitive))
        XCTAssertEqual(corpus.normalizationCases.count, 3)
        XCTAssertTrue(corpus.normalizationCases.allSatisfy {
            $0.collisionDisposition == ContactAddressComparisonResultV1.reviewRequired.rawValue
        })
        XCTAssertTrue(corpus.disclosureReleases.allSatisfy {
            $0.immutable && $0.digest.count == 64 && !$0.locales.isEmpty
        })
        XCTAssertTrue(corpus.suppressionCases.allSatisfy {
            $0.tokenKind == SuppressionTokenClassificationV1
                .contactInfoPseudonymousNotAnonymous.rawValue
                && $0.plainHashForbidden
                && $0.deleteReimportDisposition == CommunicationSuppressionEvaluationV1.blocked.rawValue
                && $0.audienceUseForbidden
        })
        XCTAssertTrue(corpus.invariants.all.allSatisfy { $0 })
        XCTAssertEqual(
            corpus.evidenceIDs,
            [
                "V23-P03-C44-G01", "V23-P03-C44-A01", "V23-P03-C44-H01",
                "V23-P03-C44-I01", "V23-P03-C44-R01",
            ]
        )
        XCTAssertEqual(corpus.lifecycle.persistence, "NONPERSISTENT")
        XCTAssertEqual(corpus.lifecycle.runtimeStorage, "NONE")
        XCTAssertEqual(corpus.lifecycle.runtimeProvider, "NONE")
        XCTAssertEqual(corpus.lifecycle.runtimeNetwork, "NONE")
        XCTAssertEqual(corpus.lifecycle.retry, "BYTE_IDENTICAL_RESULT_OR_NO_EFFECT")
    }
}

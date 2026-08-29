import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C43CustomerLearningCorpusV1: Decodable {
    struct Question: Decodable {
        let questionID: String
        let version: Int
        let decisionID: String
        let purpose: String
        let allowedSourceKinds: [String]
        let exclusions: [String]
    }

    struct MetricDefinition: Decodable {
        let metricID: String
        let version: Int
        let questionID: String
        let decisionID: String
        let numeratorID: String
        let denominatorID: String
        let formula: String
        let unit: String
        let sourceKind: String
        let sourceReleaseID: String
        let privacyThreshold: Int
        let missingDataDisposition: String
        let noncausalInterpretation: String
        let observationWindowDays: Int
        let attributionWindowDays: Int
        let exclusions: [String]
    }

    struct SourceSeparation: Decodable {
        let sourceKind: String
        let releaseID: String
        let provenance: String
        let privacyThreshold: Int
        let eligibility: String
        let refreshLagDays: Int
        let missingness: String
        let nonjoinable: Bool
        let userLevelLinkageForbidden: Bool
    }

    struct ActivationDecision: Decodable {
        let state: String
        let ownerAcceptanceRequired: Bool
        let configCannotActivate: Bool
        let expires: Bool
    }

    struct ArchiveProof: Decodable {
        let surface: String
        let disposition: String
        let forbiddenFindings: [String]
    }

    struct Lifecycle: Decodable {
        let persistence: String
        let catalog: String
        let evaluator: String
        let runtimeStorage: String
        let runtimeProvider: String
        let runtimeNetwork: String
        let retry: String
        let rollback: String
        let supersession: String
    }

    struct Invariants: Decodable {
        let fourSourcesNonjoinable: Bool
        let userLevelLinkageForbidden: Bool
        let missingNeverZero: Bool
        let thresholdSuppressesSmallCohort: Bool
        let evaluatorSyntheticOnly: Bool
        let noProductionReceiptReader: Bool
        let noWorkflowFrictionInput: Bool
        let noDiagnosticsInput: Bool
        let noIdentityInput: Bool
        let noNetwork: Bool
        let noPersistence: Bool
        let noRuntimeProvider: Bool
        let configCannotActivate: Bool
        let ownerAcceptanceRequired: Bool
        let noOperationalMetricBridge: Bool
        let noScreenNameIdentity: Bool
        let noCausalClaim: Bool

        var all: [Bool] {
            [
                fourSourcesNonjoinable, userLevelLinkageForbidden, missingNeverZero,
                thresholdSuppressesSmallCohort, evaluatorSyntheticOnly,
                noProductionReceiptReader, noWorkflowFrictionInput, noDiagnosticsInput,
                noIdentityInput, noNetwork, noPersistence, noRuntimeProvider,
                configCannotActivate, ownerAcceptanceRequired, noOperationalMetricBridge,
                noScreenNameIdentity, noCausalClaim,
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
    let questions: [Question]
    let metricDefinitions: [MetricDefinition]
    let sourceSeparation: [SourceSeparation]
    let activationDecision: ActivationDecision
    let hostileCases: [String]
    let archiveProofs: [ArchiveProof]
    let lifecycle: Lifecycle
    let invariants: Invariants
    let evidenceIDs: [String]
    let statusFlags: StatusFlags
}

private struct C43CustomerLearningFixtureV1 {
    let acquisitionVocabulary: AcquisitionSourceVocabularyV1
    let questions: [CustomerLearningQuestionV1]
    let metrics: [CustomerLearningMetricDefinitionV1]
    let sources: [MeasurementSourceDescriptorV1]
    let catalog: CustomerLearningCatalogReleaseV1

    func metric(for questionID: String) throws -> CustomerLearningMetricDefinitionV1 {
        guard let value = metrics.first(where: { $0.question.questionID == questionID }) else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        return value
    }

    func source(_ kind: MeasurementSourceKindV1) throws -> MeasurementSourceDescriptorV1 {
        guard let value = sources.first(where: { $0.kind == kind }) else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        return value
    }
}

final class V9_50CustomerLearningMeasurementTests: XCTestCase {
    private let digestA = String(repeating: "a", count: 64)
    private let releasedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testV23P03C43G01StaticCatalogRemainsZeroCollectionAndPurposeBound() throws {
        let corpus = try loadCorpus()
        try assertCorpusBoundary(corpus)
        let fixture = try makeFixture()

        XCTAssertEqual(fixture.catalog.collectionDisposition, .disabledNoCollection)
        XCTAssertEqual(fixture.questions.count, 8)
        XCTAssertEqual(fixture.metrics.count, 8)
        XCTAssertEqual(
            fixture.questions.map(\.questionID),
            CustomerLearningInitialCatalogV1.requiredQuestionIDs
        )
        XCTAssertEqual(
            Set(fixture.sources.map(\.kind)),
            Set(MeasurementSourceKindV1.allCases)
        )
        XCTAssertTrue(fixture.sources.allSatisfy { $0.userLinkage == .forbidden })
        XCTAssertEqual(
            try fixture.source(.appStoreConnectAggregate).aggregation,
            .providerPrivacyThresholded
        )
        XCTAssertEqual(
            try fixture.source(.explicitFieldResearch).aggregation,
            .ownerAggregatedResearch
        )
        XCTAssertEqual(
            try fixture.source(.rebuildableOperationalReceiptProjection).aggregation,
            .rebuildableSyntheticOnly
        )
        XCTAssertEqual(
            try fixture.source(.futureConsentedProductAnalytics).aggregation,
            .futureConsentedAggregate
        )
        XCTAssertTrue(fixture.metrics.allSatisfy {
            $0.numeratorSemanticOutcomeID.hasPrefix("OUTCOME.")
                && $0.denominatorSemanticPopulationID.hasPrefix("POPULATION.")
                && !$0.noncausalInterpretation.isEmpty
        })
        XCTAssertTrue(fixture.questions.allSatisfy {
            Set($0.exclusions) == Set(CustomerLearningRequiredExclusionV1.allCases)
        })

        let encoded = try CustomerLearningCanonicalCodecV1.encode(fixture.catalog)
        XCTAssertEqual(
            try CustomerLearningCanonicalCodecV1.decode(
                CustomerLearningCatalogReleaseV1.self,
                from: encoded
            ),
            fixture.catalog
        )
        XCTAssertEqual(
            try CustomerLearningCanonicalCodecV1.sha256(fixture.catalog),
            try CustomerLearningCanonicalCodecV1.sha256(
                CustomerLearningCanonicalCodecV1.decode(
                    CustomerLearningCatalogReleaseV1.self,
                    from: encoded
                )
            )
        )
        XCTAssertNoThrow(try CustomerLearningRuntimeBoundaryV1.validate())
        XCTAssertEqual(CustomerLearningRuntimeBoundaryV1.durableModelCount, 0)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.eventPersistenceEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.productionReceiptProjectionReaderEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.runtimeInvokerEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.networkOrProviderEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.crossSourceJoinEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.metricDefinitionBridgeEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.remoteActivationEnabled)

        let proposed = try makeActivationDecision(catalog: fixture.catalog, disposition: .proposed)
        XCTAssertFalse(proposed.authorizesRuntimeCollection)
        XCTAssertEqual(try proposed.gate(at: releasedAt.addingTimeInterval(60)), .disabledProposed)
    }

    func testV23P03C43A01MissingThresholdAndDelayedSourcesRemainUnknownOrSuppressed() throws {
        let fixture = try makeFixture()
        let metric = try fixture.metric(
            for: CustomerLearningInitialCatalogV1.firstRealJobCompletionQuestionID
        )
        let source = metric.source

        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: nil,
                    denominator: nil,
                    observedCohortSize: nil
                )
            ),
            .unknown(.missingSourceReport)
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: nil,
                    denominator: nil,
                    observedCohortSize: nil,
                    unknownReason: .delayedSourceReport
                )
            ),
            .unknown(.delayedSourceReport)
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: 3,
                    denominator: 9,
                    observedCohortSize: 9
                )
            ),
            .suppressed(.privacyThreshold)
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: 5,
                    denominator: 10,
                    observedCohortSize: 10,
                    providerSuppressed: true
                )
            ),
            .suppressed(.providerSuppressed)
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: 5,
                    denominator: 10,
                    observedCohortSize: 10
                )
            ),
            .known(try MeasurementRationalV1(numerator: 5_000, denominator: 1))
        )

        let ratioMetric = try syntheticMetric(
            basedOn: metric,
            metricID: "METRIC.SYNTHETIC.RATIO",
            formula: .ratio,
            unit: .ratio
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: ratioMetric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: 2,
                    denominator: 4,
                    observedCohortSize: 10
                )
            ),
            .known(try MeasurementRationalV1(numerator: 1, denominator: 2))
        )
        let countMetric = try syntheticMetric(
            basedOn: metric,
            metricID: "METRIC.SYNTHETIC.COUNT",
            formula: .count,
            unit: .count
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: countMetric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: 12,
                    denominator: 99,
                    observedCohortSize: 10
                )
            ),
            .known(try MeasurementRationalV1(numerator: 12, denominator: 1))
        )
        XCTAssertThrowsError(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: source,
                    numerator: Int64.max,
                    denominator: Int64.max,
                    observedCohortSize: 10
                )
            )
        ) { error in
            XCTAssertEqual(error as? CustomerLearningContractFailureV1, .arithmeticOverflow)
        }
        XCTAssertThrowsError(
            try SyntheticCustomerLearningScalarV1(
                source: source,
                numerator: 0,
                denominator: 0,
                observedCohortSize: 0
            )
        ) { error in
            XCTAssertEqual(error as? CustomerLearningContractFailureV1, .invalidValue)
        }

        let smallCohort = try syntheticReceipts(
            source: source,
            metric: metric,
            denominatorCount: 9,
            numeratorCount: 6
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                syntheticReceipts: smallCohort
            ),
            .suppressed(.privacyThreshold)
        )
        let eligible = try syntheticReceipts(
            source: source,
            metric: metric,
            denominatorCount: 10,
            numeratorCount: 5
        )
        let excluded = try SyntheticCustomerLearningReceiptValueV1(
            syntheticReceiptID: "SYNTHETIC.RECEIPT.PRACTICE",
            source: source,
            semanticOutcomeIDs: [
                metric.denominatorSemanticPopulationID,
                metric.numeratorSemanticOutcomeID,
            ].sorted(),
            population: .practice
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                syntheticReceipts: eligible + [excluded]
            ),
            .known(try MeasurementRationalV1(numerator: 5_000, denominator: 1))
        )
    }

    func testV23P03C43H01ForbiddenIdentityJoinsActivationAndRuntimeProvidersFailClosed() throws {
        let hostileCases = Set(try loadCorpus().hostileCases)
        let timeZoneHostileCase = "CLOCK_OR_TIME_ZONE_CHANGE"
        XCTAssertTrue(hostileCases.contains(timeZoneHostileCase))
        XCTAssertTrue(Set([
            "DENOMINATOR_DRIFT",
            "CAMPAIGN_LABEL_RENAME",
            "SMALL_COHORT",
            "DELAYED_OR_MISSING_APP_STORE_REPORT",
            "OPT_IN_POPULATION_BIAS",
            "DUPLICATE_SYNTHETIC_RECEIPT",
            "CLOCK_OR_TIME_ZONE_CHANGE",
            "CUSTOMER_TEXT_AS_DIMENSION",
            "HASHED_EMAIL_OR_DEVICE_ID_AS_ANONYMOUS",
            "TRANSITIVE_ANALYTICS_SDK",
            "HIDDEN_CRASH_OR_SUPPORT_LOGGING_REUSE",
            "REMOTE_ENABLE_FLAG",
            "CORRELATION_MEANS_CAUSATION_COPY",
        ]).isSubset(of: hostileCases))
        let fixture = try makeFixture()
        let metric = try fixture.metric(
            for: CustomerLearningInitialCatalogV1.firstRealJobCompletionQuestionID
        )
        let wrongSource = try fixture.source(.explicitFieldResearch).reference
        XCTAssertThrowsError(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                scalar: SyntheticCustomerLearningScalarV1(
                    source: wrongSource,
                    numerator: 1,
                    denominator: 10,
                    observedCohortSize: 10
                )
            )
        ) { error in
            XCTAssertEqual(error as? CustomerLearningContractFailureV1, .sourceJoinForbidden)
        }

        let duplicate = try SyntheticCustomerLearningReceiptValueV1(
            syntheticReceiptID: "SYNTHETIC.RECEIPT.DUPLICATE",
            source: metric.source,
            semanticOutcomeIDs: [metric.denominatorSemanticPopulationID]
        )
        XCTAssertThrowsError(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                syntheticReceipts: [duplicate, duplicate]
            )
        ) { error in
            XCTAssertEqual(error as? CustomerLearningContractFailureV1, .duplicateValue)
        }
        let unsupported = try SyntheticCustomerLearningReceiptValueV1(
            syntheticReceiptID: "SYNTHETIC.RECEIPT.UNSUPPORTED_DENOMINATOR",
            source: metric.source,
            semanticOutcomeIDs: [metric.denominatorSemanticPopulationID],
            population: .unsupportedDenominator
        )
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                syntheticReceipts: [unsupported]
            ),
            .unknown(.unsupportedDenominator)
        )

        XCTAssertThrowsError(
            try makeActivationDecision(
                catalog: fixture.catalog,
                disposition: .ownerAcceptedPendingSeparateImplementationCard,
                includeOwnerAcceptance: false
            )
        ) { error in
            XCTAssertEqual(error as? CustomerLearningContractFailureV1, .activationForbidden)
        }
        let ownerAccepted = try makeActivationDecision(
            catalog: fixture.catalog,
            disposition: .ownerAcceptedPendingSeparateImplementationCard,
            includeOwnerAcceptance: true
        )
        XCTAssertFalse(ownerAccepted.authorizesRuntimeCollection)
        XCTAssertEqual(
            try ownerAccepted.gate(at: releasedAt.addingTimeInterval(120)),
            .disabledSeparateImplementationRequired
        )

        let hostileDocument = try ZeroCollectionStaticDocumentV1(
            path: "SyntheticHostile/CustomerLearningRuntime.swift",
            text: """
            import FirebaseAnalytics
            let store = ProductEventStore()
            let analyticsEndpoint = "https://collector.invalid/analytics"
            let uploader = BGTaskScheduler.shared
            let campaignToken = "synthetic"
            let advertisingIdentifier = "synthetic"
            let hashedEmail = "synthetic"
            """
        )
        let scan = try ZeroCollectionConformanceScannerV1.scan(documents: [hostileDocument])
        XCTAssertEqual(
            scan.findings.map(\.kind.rawValue).sorted(),
            ZeroCollectionStaticFindingKindV1.allCases.map(\.rawValue).sorted()
        )
        XCTAssertFalse(scan.isStaticSourceConformant)
        XCTAssertThrowsError(try scan.conformanceEvidence()) { error in
            XCTAssertEqual(
                error as? ZeroCollectionConformanceScannerFailureV1,
                .prohibitedPathFound
            )
        }

        let observationHostiles: [() throws -> Void] = [
            { _ = try ZeroCollectionObservationV1(analyticsAttributionAdSDKCount: 1) },
            { _ = try ZeroCollectionObservationV1(productEventStoreCount: 1) },
            { _ = try ZeroCollectionObservationV1(endpointDomainCount: 1) },
            { _ = try ZeroCollectionObservationV1(backgroundUploaderTaskCount: 1) },
            { _ = try ZeroCollectionObservationV1(advertisingIdentifierUseCount: 1) },
            { _ = try ZeroCollectionObservationV1(fingerprintUseCount: 1) },
            { _ = try ZeroCollectionObservationV1(stableCrossAppDevicePersonIDCount: 1) },
            { _ = try ZeroCollectionObservationV1(campaignTokenHandlerCount: 1) },
            { _ = try ZeroCollectionObservationV1(hiddenExperimentAssignmentCount: 1) },
            { _ = try ZeroCollectionObservationV1(productionReceiptProjectionReaderCount: 1) },
            { _ = try ZeroCollectionObservationV1(collectionTransmissionCount: 1) },
            { _ = try ZeroCollectionObservationV1(trackingCount: 1) },
            { _ = try ZeroCollectionObservationV1(privacyManifestCollectedDataTypeCount: 1) },
            { _ = try ZeroCollectionObservationV1(privacyManifestTracking: true) },
            { _ = try ZeroCollectionObservationV1(privacyManifestTrackingDomainCount: 1) },
        ]
        for hostile in observationHostiles {
            XCTAssertThrowsError(try hostile()) { error in
                XCTAssertEqual(error as? CustomerLearningContractFailureV1, .collectionForbidden)
            }
        }
    }

    func testV23P03C43I01SyntheticEvaluationIsDeterministicAndLeavesNoRuntimeState() throws {
        let fixture = try makeFixture()
        let metric = try fixture.metric(
            for: CustomerLearningInitialCatalogV1.reportPreviewSuccessQuestionID
        )
        let receipts = try syntheticReceipts(
            source: metric.source,
            metric: metric,
            denominatorCount: 10,
            numeratorCount: 7
        )

        let interruptedPrefixes = [0, 1, 5, 9]
        for prefixCount in interruptedPrefixes {
            let prefix = Array(receipts.prefix(prefixCount))
            let prefixResult = try CustomerLearningSyntheticEvaluatorV1.evaluate(
                metric: metric,
                syntheticReceipts: prefix
            )
            if prefixCount == 0 {
                XCTAssertEqual(prefixResult, .unknown(.ineligiblePopulation))
            } else {
                XCTAssertEqual(prefixResult, .suppressed(.privacyThreshold))
            }
        }

        let first = try CustomerLearningSyntheticEvaluatorV1.evaluate(
            metric: metric,
            syntheticReceipts: receipts
        )
        let retried = try CustomerLearningSyntheticEvaluatorV1.evaluate(
            metric: metric,
            syntheticReceipts: receipts
        )
        XCTAssertEqual(first, retried)
        XCTAssertEqual(
            try CustomerLearningSyntheticEvaluatorV1.canonicalResultData(first),
            try CustomerLearningSyntheticEvaluatorV1.canonicalResultData(retried)
        )
        XCTAssertEqual(
            first,
            .known(try MeasurementRationalV1(numerator: 7_000, denominator: 1))
        )

        let clean = try ZeroCollectionConformanceScannerV1.scan(documents: [
            ZeroCollectionStaticDocumentV1(
                path: "SyntheticInput/StaticCatalog.swift",
                text: "let collectionDisposition = \"DISABLED_NO_COLLECTION\""
            ),
        ])
        XCTAssertTrue(clean.isStaticSourceConformant)
        if case .suppliedStaticDocumentsOnly = clean.evidenceScope {
            // Exact static-only evidence scope is required.
        } else {
            XCTFail("Synthetic evaluation must not claim a stronger evidence scope")
        }
        XCTAssertFalse(clean.claimsReleaseArchiveInspection)
        XCTAssertFalse(clean.claimsRuntimeNetworkObservation)
        XCTAssertThrowsError(try ZeroCollectionConformanceScannerV1.scan(documents: [])) {
            XCTAssertEqual(error as? ZeroCollectionConformanceScannerFailureV1, .emptyInput)
        }
        let duplicateDocument = try ZeroCollectionStaticDocumentV1(
            path: "SyntheticInput/Duplicate.swift",
            text: "let value = 1"
        )
        XCTAssertThrowsError(
            try ZeroCollectionConformanceScannerV1.scan(
                documents: [duplicateDocument, duplicateDocument]
            )
        ) { error in
            XCTAssertEqual(error as? ZeroCollectionConformanceScannerFailureV1, .duplicatePath)
        }

        XCTAssertEqual(CustomerLearningRuntimeBoundaryV1.durableModelCount, 0)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.eventPersistenceEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.runtimeInvokerEnabled)
        XCTAssertFalse(CustomerLearningRuntimeBoundaryV1.networkOrProviderEnabled)
    }

    func testV23P03C43R01ArchiveRuntimeRollbackAndSupersessionPreserveZeroCollection() throws {
        let corpus = try loadCorpus()
        let first = try makeFixture()
        let firstBytes = try CustomerLearningCanonicalCodecV1.encode(first.catalog)
        let successor = try makeFixture(
            catalogRevision: 2,
            supersedes: first.catalog.reference,
            releasedAt: releasedAt.addingTimeInterval(1_000)
        )
        XCTAssertEqual(first.catalog.collectionDisposition, .disabledNoCollection)
        XCTAssertEqual(successor.catalog.collectionDisposition, .disabledNoCollection)
        XCTAssertNotEqual(first.catalog.catalogSHA256, successor.catalog.catalogSHA256)
        XCTAssertEqual(try CustomerLearningCanonicalCodecV1.encode(first.catalog), firstBytes)
        XCTAssertEqual(successor.catalog.supersedes, try first.catalog.reference)

        let rejected = try makeActivationDecision(
            catalog: successor.catalog,
            disposition: .rejected
        )
        XCTAssertEqual(try rejected.gate(at: releasedAt.addingTimeInterval(2_000)), .disabledRejected)
        XCTAssertEqual(
            try rejected.gate(at: releasedAt.addingTimeInterval(40 * 86_400)),
            .disabledExpired
        )
        XCTAssertFalse(rejected.authorizesRuntimeCollection)

        let staticScan = try ZeroCollectionConformanceScannerV1.scan(documents: [
            ZeroCollectionStaticDocumentV1(
                path: "SyntheticEvidence/ProjectDependencyGraph.txt",
                text: "No analytics, attribution, advertising, provider, event-store, or runtime invoker product dependency."
            ),
        ])
        let staticEvidence = try staticScan.conformanceEvidence()
        if case .suppliedStaticDocumentsOnly = staticEvidence.scope {
            // Exact static-only evidence scope is required.
        } else {
            XCTFail("Static evidence must not claim archive or runtime inspection")
        }
        XCTAssertFalse(staticEvidence.claimsReleaseArchiveInspection)
        XCTAssertFalse(staticEvidence.claimsRuntimeNetworkObservation)

        XCTAssertEqual(
            ZeroCollectionConformanceReceiptV1.issuanceDisposition,
            .pendingExactCandidateArchiveRuntimeNativeEvidence
        )
        XCTAssertEqual(
            ZeroCollectionConformanceReceiptV1.collectionDisposition,
            .disabledNoCollection
        )
        XCTAssertFalse(ZeroCollectionConformanceReceiptV1.authorizesIssuance)
        XCTAssertThrowsError(
            try ZeroCollectionConformanceReceiptV1.requireIssuanceAuthority()
        ) { error in
            XCTAssertEqual(error as? CustomerLearningContractFailureV1, .collectionForbidden)
        }

        XCTAssertEqual(
            Set(corpus.archiveProofs.map(\.surface)),
            Set(["DEPENDENCY", "LINK", "STRING", "DOMAIN", "BACKGROUND_TASK", "RUNTIME_NETWORK"])
        )
        XCTAssertEqual(
            corpus.archiveProofs.first(where: { $0.surface == "DEPENDENCY" })?.disposition,
            "STATIC_SOURCE_SCAN_CLEAN"
        )
        XCTAssertTrue(corpus.archiveProofs
            .filter { $0.surface != "DEPENDENCY" }
            .allSatisfy { $0.disposition == "PENDING_NOT_ACCEPTING" })
        XCTAssertTrue(corpus.archiveProofs.allSatisfy { $0.forbiddenFindings.isEmpty })
        XCTAssertEqual(corpus.lifecycle.persistence, "NONPERSISTENT")
        XCTAssertEqual(corpus.lifecycle.rollback, "REMOVE_UNACTIVATED_CONTRACT_AND_TEST_CHANGES")
        XCTAssertEqual(corpus.lifecycle.supersession, "IMMUTABLE_RELEASES_SUPERSEDED_NOT_REWRITTEN")
        XCTAssertTrue(corpus.statusFlags.all.allSatisfy { !$0 })
    }

    private func loadCorpus() throws -> C43CustomerLearningCorpusV1 {
        let bundled = Bundle(for: Self.self).url(
            forResource: "V22P03C43CustomerLearningCorpusV1",
            withExtension: "json"
        )
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/V22/CustomerLearning/V22P03C43CustomerLearningCorpusV1.json"
            )
        return try JSONDecoder().decode(
            C43CustomerLearningCorpusV1.self,
            from: Data(contentsOf: bundled ?? source)
        )
    }

    private func assertCorpusBoundary(_ corpus: C43CustomerLearningCorpusV1) throws {
        XCTAssertEqual(corpus.schema, "V22P03C43CustomerLearningCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C43")
        XCTAssertEqual(corpus.classification, "PREPARE_NOW")
        XCTAssertEqual(corpus.collectionDisposition, "DISABLED_NO_COLLECTION")
        XCTAssertEqual(corpus.questions.count, 8)
        XCTAssertEqual(corpus.metricDefinitions.count, 8)
        XCTAssertEqual(
            Set(corpus.sourceSeparation.map(\.sourceKind)),
            Set(MeasurementSourceKindV1.allCases.map(\.rawValue))
        )
        XCTAssertTrue(corpus.sourceSeparation.allSatisfy {
            $0.nonjoinable && $0.userLevelLinkageForbidden && $0.privacyThreshold > 0
                && !$0.provenance.isEmpty && !$0.eligibility.isEmpty
                && !$0.missingness.isEmpty && $0.refreshLagDays >= 0
        })
        XCTAssertEqual(
            Set(corpus.sourceSeparation.map(\.releaseID)).count,
            MeasurementSourceKindV1.allCases.count
        )
        XCTAssertTrue(corpus.questions.allSatisfy {
            $0.version == 1 && !$0.questionID.isEmpty && !$0.decisionID.isEmpty
                && !$0.purpose.isEmpty && !$0.allowedSourceKinds.isEmpty
                && !$0.exclusions.isEmpty
        })
        XCTAssertTrue(corpus.metricDefinitions.allSatisfy {
            $0.version == 1 && $0.formula == MeasurementFormulaV1.percentageBasisPoints.rawValue
                && $0.unit == MeasurementUnitV1.basisPoints.rawValue
                && $0.privacyThreshold > 0 && $0.missingDataDisposition == "UNKNOWN"
                && !$0.metricID.isEmpty && !$0.questionID.isEmpty && !$0.decisionID.isEmpty
                && !$0.numeratorID.isEmpty && !$0.denominatorID.isEmpty
                && !$0.sourceKind.isEmpty && !$0.sourceReleaseID.isEmpty
                && !$0.noncausalInterpretation.isEmpty
                && $0.observationWindowDays > 0 && $0.attributionWindowDays > 0
                && !$0.exclusions.isEmpty
        })
        XCTAssertEqual(corpus.activationDecision.state, "UNACTIVATED_OWNER_ACCEPTANCE_REQUIRED")
        XCTAssertTrue(corpus.activationDecision.ownerAcceptanceRequired)
        XCTAssertTrue(corpus.activationDecision.configCannotActivate)
        XCTAssertTrue(corpus.activationDecision.expires)
        XCTAssertGreaterThanOrEqual(corpus.hostileCases.count, 12)
        XCTAssertEqual(corpus.lifecycle.catalog, "STATIC_VERSIONED_POLICY")
        XCTAssertEqual(corpus.lifecycle.evaluator, "SYNTHETIC_TEST_TARGET_ONLY")
        XCTAssertEqual(corpus.lifecycle.runtimeStorage, "NONE")
        XCTAssertEqual(corpus.lifecycle.runtimeProvider, "NONE")
        XCTAssertEqual(corpus.lifecycle.runtimeNetwork, "NONE")
        XCTAssertEqual(corpus.lifecycle.retry, "BYTE_IDENTICAL_RESULT_OR_NO_EFFECT")
        XCTAssertTrue(corpus.invariants.all.allSatisfy { $0 })
        XCTAssertEqual(corpus.evidenceIDs, [
            "V23-P03-C43-G01", "V23-P03-C43-A01", "V23-P03-C43-H01",
            "V23-P03-C43-I01", "V23-P03-C43-R01",
        ])
        XCTAssertTrue(corpus.statusFlags.all.allSatisfy { !$0 })

        let raw = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        "Fixtures/V22/CustomerLearning/V22P03C43CustomerLearningCorpusV1.json"
                    ))
            ) as? [String: Any]
        )
        XCTAssertEqual(Set(raw.keys), Set([
            "schema", "schemaVersion", "cardID", "classification", "collectionDisposition",
            "questions", "metricDefinitions", "sourceSeparation", "activationDecision",
            "hostileCases", "archiveProofs", "lifecycle", "invariants", "evidenceIDs",
            "statusFlags",
        ]))
    }

    private func makeFixture(
        catalogRevision: UInt64 = 1,
        supersedes: CustomerLearningCatalogReferenceV1? = nil,
        releasedAt: Date? = nil
    ) throws -> C43CustomerLearningFixtureV1 {
        let vocabulary = try AcquisitionSourceVocabularyV1(
            vocabularyID: UUID(uuidString: "43000000-0000-0000-0000-000000000001")!,
            revision: 1,
            definitions: [
                AcquisitionSourceDefinitionV1(
                    semanticID: "ACQUISITION.DIRECT",
                    ownerReadableName: "Direct or unavailable aggregate source"
                ),
                AcquisitionSourceDefinitionV1(
                    semanticID: "ACQUISITION.OWNER_DECLARED_CAMPAIGN",
                    ownerReadableName: "Owner-declared external aggregate campaign"
                ),
            ]
        )
        let sourceKinds = MeasurementSourceKindV1.allCases
        var sources: [MeasurementSourceDescriptorV1] = []
        for (index, kind) in sourceKinds.enumerated() {
            let definition: (
                MeasurementAggregationV1,
                MeasurementPrivacyThresholdV1,
                MeasurementMissingDataPolicyV1,
                AcquisitionSourceVocabularyReferenceV1?
            )
            switch kind {
            case .appStoreConnectAggregate:
                definition = (
                    .providerPrivacyThresholded,
                    try MeasurementPrivacyThresholdV1(kind: .providerEnforcedUnknown),
                    .unknown,
                    try vocabulary.reference
                )
            case .explicitFieldResearch:
                definition = (
                    .ownerAggregatedResearch,
                    try MeasurementPrivacyThresholdV1(kind: .minimumCohort, minimumCohortSize: 5),
                    .unknown,
                    nil
                )
            case .rebuildableOperationalReceiptProjection:
                definition = (
                    .rebuildableSyntheticOnly,
                    try MeasurementPrivacyThresholdV1(kind: .minimumCohort, minimumCohortSize: 10),
                    .unknown,
                    nil
                )
            case .futureConsentedProductAnalytics:
                definition = (
                    .futureConsentedAggregate,
                    try MeasurementPrivacyThresholdV1(kind: .minimumCohort, minimumCohortSize: 25),
                    .unknown,
                    nil
                )
            }
            sources.append(try MeasurementSourceDescriptorV1(
                sourceID: UUID(uuidString: String(
                    format: "43000000-0000-0000-0000-%012d",
                    index + 10
                ))!,
                kind: kind,
                revision: 1,
                provenance: "Static vendor-neutral source contract for \(kind.rawValue).",
                aggregation: definition.0,
                privacyThreshold: definition.1,
                eligibility: "Synthetic fixture or owner-operated aggregate only.",
                refreshLag: try MeasurementRefreshLagV1(
                    minimumHours: UInt32(index),
                    maximumHours: UInt32(index + 24)
                ),
                missingDataPolicy: definition.2,
                acquisitionVocabulary: definition.3
            ))
        }
        let orderedSources = sources.sorted { $0.kind.rawValue < $1.kind.rawValue }
        let sourceByKind = Dictionary(uniqueKeysWithValues: orderedSources.map { ($0.kind, $0) })

        let questions = try CustomerLearningInitialCatalogV1.requiredQuestionIDs.map { questionID in
            guard let purpose = CustomerLearningInitialCatalogV1.expectedPurpose(for: questionID) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            return try CustomerLearningQuestionV1(
                questionID: questionID,
                revision: 1,
                purpose: purpose,
                decisionSemanticID: "DECISION.\(questionID)",
                ownerPrompt: "Owner-readable static learning question for \(questionID)."
            )
        }
        let metrics = try questions.map { question in
            let sourceKind: MeasurementSourceKindV1
            switch question.purpose {
            case .acquisitionSourceMix, .productPageConversion:
                sourceKind = .appStoreConnectAggregate
            case .ownerFieldResearchThemes:
                sourceKind = .explicitFieldResearch
            case .sevenDayAggregateReturn, .thirtyDayAggregateReturn:
                sourceKind = .futureConsentedProductAnalytics
            case .firstRealJobCompletion, .offlineReadyRoundCompletion, .reportPreviewSuccess:
                sourceKind = .rebuildableOperationalReceiptProjection
            }
            guard let source = sourceByKind[sourceKind] else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            return try CustomerLearningMetricDefinitionV1(
                metricID: "METRIC.\(question.questionID)",
                revision: 1,
                question: question.reference,
                decisionSemanticID: question.decisionSemanticID,
                numeratorSemanticOutcomeID: "OUTCOME.\(question.questionID).SUCCESS",
                denominatorSemanticPopulationID: "POPULATION.\(question.questionID).ELIGIBLE",
                eligibilitySemanticIDs: ["ELIGIBLE.\(question.questionID)"],
                observationWindow: MeasurementWindowV1(
                    anchorSemanticID: "WINDOW.\(question.questionID).OBSERVATION",
                    durationDays: 30
                ),
                attributionWindow: MeasurementWindowV1(
                    anchorSemanticID: "WINDOW.\(question.questionID).ATTRIBUTION",
                    durationDays: 30
                ),
                source: source.reference,
                formula: .percentageBasisPoints,
                unit: .basisPoints,
                privacyThreshold: source.privacyThreshold,
                missingDataPolicy: source.missingDataPolicy,
                noncausalInterpretation: "This descriptive aggregate does not establish causation."
            )
        }
        let catalog = try CustomerLearningCatalogReleaseV1(
            catalogID: UUID(uuidString: "43000000-0000-0000-0000-000000000050")!,
            revision: catalogRevision,
            acquisitionVocabulary: vocabulary,
            questions: questions,
            metrics: metrics,
            sources: orderedSources,
            releasedAt: releasedAt ?? self.releasedAt,
            supersedes: supersedes
        )
        return .init(
            acquisitionVocabulary: vocabulary,
            questions: questions,
            metrics: metrics,
            sources: orderedSources,
            catalog: catalog
        )
    }

    private func makeActivationDecision(
        catalog: CustomerLearningCatalogReleaseV1,
        disposition: MeasurementActivationDispositionV1,
        includeOwnerAcceptance: Bool = false
    ) throws -> MeasurementActivationDecisionV1 {
        let createdAt = catalog.releasedAt.addingTimeInterval(10)
        let ownerAcceptance = includeOwnerAcceptance ? try MeasurementOwnerAcceptanceV1(
            ownerAuthorityID: "OWNER.C43",
            acceptedAt: createdAt.addingTimeInterval(10),
            acceptanceBasisSHA256: digestA
        ) : nil
        return try MeasurementActivationDecisionV1(
            decisionID: UUID(uuidString: "43000000-0000-0000-0000-000000000080")!,
            revision: 1,
            catalog: catalog.reference,
            decisionToImproveSemanticID: "DECISION.FUTURE.C43.ACTIVATION",
            minimumFieldSemanticIDs: ["FIELD.CONSENT", "FIELD.PURPOSE"],
            minimumEventSemanticIDs: ["EVENT.CONSENTED.AGGREGATE"],
            purposes: [.firstRealJobCompletion],
            governance: MeasurementActivationGovernanceV1(
                lawfulConsentBasis: "Explicit owner-reviewed consent basis required.",
                population: "Future explicitly consented aggregate population only.",
                destinationsAndProcessors: [
                    MeasurementDestinationProcessorV1(
                        destinationID: "PROCESSOR.FUTURE.UNSELECTED",
                        processorName: "No processor selected",
                        dataCategoryIDs: ["CATEGORY.AGGREGATE.PRODUCT_EVENT"],
                        processingPurpose: "Dormant contract planning only."
                    ),
                ],
                aggregationPolicy: "Privacy-thresholded aggregate only.",
                retentionPolicy: "Owner review required before activation.",
                withdrawalPolicy: "Withdrawal behavior required before activation.",
                deleteExportErasePolicy: "Delete, export, and Erase behavior required.",
                privacyPolicySHA256: digestA,
                appPrivacyAnswersSHA256: digestA,
                threatModelSHA256: digestA,
                securityReviewSHA256: digestA,
                offlineFailurePolicy: "No collection while offline or failed.",
                releaseMembershipSHA256: digestA,
                experimentGuardrails: "No hidden assignment and no causal claim.",
                killSwitchAndRemovalPath: "Separate implementation must include complete removal."
            ),
            disposition: disposition,
            ownerAcceptance: ownerAcceptance,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(30 * 86_400)
        )
    }

    private func syntheticReceipts(
        source: MeasurementSourceReferenceV1,
        metric: CustomerLearningMetricDefinitionV1,
        denominatorCount: Int,
        numeratorCount: Int
    ) throws -> [SyntheticCustomerLearningReceiptValueV1] {
        guard denominatorCount >= 0, numeratorCount >= 0, numeratorCount <= denominatorCount else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        return try (0..<denominatorCount).map { index in
            var outcomes = [metric.denominatorSemanticPopulationID]
            if index < numeratorCount { outcomes.append(metric.numeratorSemanticOutcomeID) }
            return try SyntheticCustomerLearningReceiptValueV1(
                syntheticReceiptID: String(format: "SYNTHETIC.RECEIPT.%04d", index),
                source: source,
                semanticOutcomeIDs: outcomes.sorted()
            )
        }
    }

    private func syntheticMetric(
        basedOn metric: CustomerLearningMetricDefinitionV1,
        metricID: String,
        formula: MeasurementFormulaV1,
        unit: MeasurementUnitV1
    ) throws -> CustomerLearningMetricDefinitionV1 {
        try CustomerLearningMetricDefinitionV1(
            metricID: metricID,
            revision: 1,
            question: metric.question,
            decisionSemanticID: metric.decisionSemanticID,
            numeratorSemanticOutcomeID: metric.numeratorSemanticOutcomeID,
            denominatorSemanticPopulationID: metric.denominatorSemanticPopulationID,
            eligibilitySemanticIDs: metric.eligibilitySemanticIDs,
            exclusions: metric.exclusions,
            observationWindow: metric.observationWindow,
            attributionWindow: metric.attributionWindow,
            source: metric.source,
            formula: formula,
            unit: unit,
            privacyThreshold: metric.privacyThreshold,
            missingDataPolicy: metric.missingDataPolicy,
            noncausalInterpretation: metric.noncausalInterpretation
        )
    }

}

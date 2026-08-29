import Foundation

@testable import FieldEvidenceApp

enum SyntheticCustomerLearningPopulationV1: String, Codable, CaseIterable, Sendable {
    case eligible = "ELIGIBLE"
    case practice = "PRACTICE"
    case syntheticTestDiagnostic = "SYNTHETIC_TEST_DIAGNOSTIC"
    case customerContent = "CUSTOMER_CONTENT"
    case unsupportedDenominator = "UNSUPPORTED_DENOMINATOR"
    case silentlyInferredPeople = "SILENTLY_INFERRED_PEOPLE"
}

struct SyntheticCustomerLearningScalarV1: Equatable, Sendable {
    let source: MeasurementSourceReferenceV1
    let numerator: Int64?
    let denominator: Int64?
    let observedCohortSize: UInt64?
    let providerSuppressed: Bool
    let unknownReason: MeasurementUnknownReasonV1

    init(
        source: MeasurementSourceReferenceV1,
        numerator: Int64?,
        denominator: Int64?,
        observedCohortSize: UInt64?,
        providerSuppressed: Bool = false,
        unknownReason: MeasurementUnknownReasonV1 = .missingSourceReport
    ) throws {
        try source.validate()
        guard numerator.map({ $0 >= 0 }) ?? true,
              denominator.map({ $0 > 0 }) ?? true,
              observedCohortSize.map({ $0 <= 1_000_000 }) ?? true else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        self.source = source
        self.numerator = numerator
        self.denominator = denominator
        self.observedCohortSize = observedCohortSize
        self.providerSuppressed = providerSuppressed
        self.unknownReason = unknownReason
    }
}

struct SyntheticCustomerLearningReceiptValueV1: Equatable, Sendable {
    let syntheticReceiptID: String
    let source: MeasurementSourceReferenceV1
    let semanticOutcomeIDs: [String]
    let population: SyntheticCustomerLearningPopulationV1

    init(
        syntheticReceiptID: String,
        source: MeasurementSourceReferenceV1,
        semanticOutcomeIDs: [String],
        population: SyntheticCustomerLearningPopulationV1 = .eligible
    ) throws {
        let orderedOutcomes = semanticOutcomeIDs.sorted()
        guard Self.isIdentifier(syntheticReceiptID),
              !orderedOutcomes.isEmpty,
              orderedOutcomes.count <= 64,
              orderedOutcomes == semanticOutcomeIDs,
              Set(orderedOutcomes).count == orderedOutcomes.count,
              orderedOutcomes.allSatisfy(Self.isIdentifier) else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        try source.validate()
        self.syntheticReceiptID = syntheticReceiptID
        self.source = source
        self.semanticOutcomeIDs = orderedOutcomes
        self.population = population
    }

    private static func isIdentifier(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        return !value.isEmpty
            && value.utf8.count <= 160
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

/// Pure test-target evaluator for explicitly synthetic scalars and receipt-like
/// values. It has no reader, clock, identity, persistence, provider, network,
/// diagnostics, workflow-friction, or application-runtime dependency.
/// Missing input remains UNKNOWN, a cohort below privacyThreshold is SUPPRESSED,
/// and retrying the same bounded input is deterministic.
enum CustomerLearningSyntheticEvaluatorV1 {
    static let maximumSyntheticReceiptCount = 1_000_000

    static func evaluate(
        metric: CustomerLearningMetricDefinitionV1,
        scalar: SyntheticCustomerLearningScalarV1
    ) throws -> MeasurementEvaluationResultV1 {
        try metric.validate()
        guard scalar.source == metric.source else {
            throw CustomerLearningContractFailureV1.sourceJoinForbidden
        }
        return try evaluateSyntheticValue(
            formula: metric.formula,
            privacyThreshold: metric.privacyThreshold,
            missingDataPolicy: metric.missingDataPolicy,
            numerator: scalar.numerator,
            denominator: scalar.denominator,
            observedCohortSize: scalar.observedCohortSize,
            providerSuppressed: scalar.providerSuppressed,
            unknownReason: scalar.unknownReason
        )
    }

    static func evaluate(
        metric: CustomerLearningMetricDefinitionV1,
        syntheticReceipts: [SyntheticCustomerLearningReceiptValueV1]
    ) throws -> MeasurementEvaluationResultV1 {
        try metric.validate()
        guard syntheticReceipts.count <= maximumSyntheticReceiptCount else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let receiptIDs = syntheticReceipts.map(\.syntheticReceiptID)
        guard Set(receiptIDs).count == receiptIDs.count else {
            throw CustomerLearningContractFailureV1.duplicateValue
        }
        guard syntheticReceipts.allSatisfy({ $0.source == metric.source }) else {
            throw CustomerLearningContractFailureV1.sourceJoinForbidden
        }
        if syntheticReceipts.contains(where: { $0.population == .unsupportedDenominator }) {
            return .unknown(.unsupportedDenominator)
        }

        let eligible = syntheticReceipts.filter { $0.population == .eligible }
        let denominator = eligible.filter {
            $0.semanticOutcomeIDs.contains(metric.denominatorSemanticPopulationID)
        }.count
        guard denominator > 0 else { return .unknown(.ineligiblePopulation) }
        let numerator = eligible.filter {
            $0.semanticOutcomeIDs.contains(metric.numeratorSemanticOutcomeID)
                && $0.semanticOutcomeIDs.contains(metric.denominatorSemanticPopulationID)
        }.count
        return try evaluateSyntheticValue(
            formula: metric.formula,
            privacyThreshold: metric.privacyThreshold,
            missingDataPolicy: metric.missingDataPolicy,
            numerator: Int64(numerator),
            denominator: Int64(denominator),
            observedCohortSize: UInt64(denominator)
        )
    }

    private static func evaluateSyntheticValue(
        formula: MeasurementFormulaV1,
        privacyThreshold: MeasurementPrivacyThresholdV1,
        missingDataPolicy: MeasurementMissingDataPolicyV1,
        numerator: Int64?,
        denominator: Int64?,
        observedCohortSize: UInt64?,
        providerSuppressed: Bool = false,
        unknownReason: MeasurementUnknownReasonV1 = .missingSourceReport
    ) throws -> MeasurementEvaluationResultV1 {
        if providerSuppressed { return .suppressed(.providerSuppressed) }
        guard let numerator, let denominator else {
            switch missingDataPolicy {
            case .unknown:
                return .unknown(unknownReason)
            case .suppressed:
                return .suppressed(.providerSuppressed)
            }
        }
        guard numerator >= 0, denominator > 0 else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        switch privacyThreshold.kind {
        case .providerEnforcedUnknown:
            break
        case .minimumCohort:
            guard let observedCohortSize else { return .unknown(.missingSourceReport) }
            guard let minimum = privacyThreshold.minimumCohortSize else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            if observedCohortSize < minimum { return .suppressed(.privacyThreshold) }
        }

        let rational: MeasurementRationalV1
        switch formula {
        case .ratio:
            guard numerator <= denominator else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            rational = try MeasurementRationalV1(
                numerator: numerator,
                denominator: denominator
            )
        case .percentageBasisPoints:
            guard numerator <= denominator else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            let (scaledNumerator, overflow) = numerator.multipliedReportingOverflow(by: 10_000)
            guard !overflow else {
                throw CustomerLearningContractFailureV1.arithmeticOverflow
            }
            rational = try MeasurementRationalV1(
                numerator: scaledNumerator,
                denominator: denominator
            )
        case .count:
            rational = try MeasurementRationalV1(numerator: numerator, denominator: 1)
        }
        return .known(rational)
    }

    static func canonicalResultData(
        _ result: MeasurementEvaluationResultV1
    ) throws -> Data {
        try CustomerLearningCanonicalCodecV1.encode(result)
    }
}

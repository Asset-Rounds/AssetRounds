import Foundation

enum OperationsMetricsFailureV1: Error, Equatable, Sendable {
    case invalidDefinition
    case invalidProjection
    case definitionOutputDisagreement
    case unsupportedMetricVersion
    case duplicateSourceEvent
    case arithmeticOverflow
    case corruptDerivedState
}

enum OperationsMetricDefinitionIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case qualifiedRecordedUnplannedMTBF = "QUALIFIED_RECORDED_UNPLANNED_MTBF_V1"
    case qualifiedRecordedUnplannedFullInterruptionAvailability =
        "QUALIFIED_RECORDED_UNPLANNED_FULL_INTERRUPTION_AVAILABILITY_V1"
}

enum OperationsMetricUnitV1: String, Codable, Hashable, Sendable {
    case milliseconds = "MILLISECONDS"
    case componentCount = "MAXIMAL_DOWNTIME_COMPONENT_COUNT"
    case qualifiedExposureMilliseconds = "QUALIFIED_EXPOSURE_MILLISECONDS"
}

enum OperationsMetricFormulaV1: String, Codable, Hashable, Sendable {
    case operatingExposurePerQualifyingFailureStart =
        "OPERATING_EXPOSURE_MILLISECONDS_PER_QUALIFYING_FAILURE_START"
    case operatingExposureOverQualifiedExposure =
        "OPERATING_EXPOSURE_MILLISECONDS_OVER_QUALIFIED_EXPOSURE_MILLISECONDS"
}

enum OperationsMetricInputFilterV1: String, Codable, Hashable, Sendable {
    case completeQualifiedExposure = "COMPLETE_QUALIFIED_SERVICE_EXPOSURE"
    case explicitPlannedNonserviceExclusions = "EXPLICIT_PLANNED_NONSERVICE_EXCLUSIONS"
    case exactUnplannedFullInterruption = "EXACT_UNPLANNED_FULL_INTERRUPTION"
}

enum OperationsMetricExcludedFilterV1: String, Codable, Hashable, Sendable {
    case plannedInterruption = "PLANNED_INTERRUPTION_OVER_INCLUDED_EXPOSURE"
    case unknownOrigin = "UNKNOWN_ORIGIN"
    case unknownImpact = "UNKNOWN_IMPACT"
    case uncertainOrOpenInterval = "UNCERTAIN_OR_OPEN_INTERVAL"
    case incompleteCoverage = "INCOMPLETE_COVERAGE"
    case replacementOrResetAmbiguity = "REPLACEMENT_OR_RESET_AMBIGUITY"
    case unresolvedOverlap = "UNRESOLVED_OVERLAP"
}

enum OperationsMetricTimeBasisV1: String, Codable, Hashable, Sendable {
    case observationWindowAsOf = "HALF_OPEN_OBSERVATION_WINDOW_WITH_EXPLICIT_AS_OF"
}

enum OperationsMetricUnavailableDispositionV1: String, Codable, Hashable, Sendable {
    case unavailableWithoutInference = "UNAVAILABLE_WITHOUT_INFERENCE_OR_INFINITY"
}

enum OperationsMetricFailureStartPredicateV1: String, Codable, Hashable, Sendable {
    case exactInWindowTransitionIntoUnplannedFullInterruption =
        "EXACT_IN_WINDOW_TRANSITION_INTO_UNPLANNED_FULL_INTERRUPTION_COMPONENT"
    case notApplicable = "NOT_APPLICABLE"
}

struct MetricDefinitionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    static let currentDefinitionVersion = 1

    let schemaVersion: Int
    let identifier: OperationsMetricDefinitionIDV1
    let version: Int
    let persistenceMode: String
    let numeratorUnit: OperationsMetricUnitV1
    let denominatorUnit: OperationsMetricUnitV1
    let formula: OperationsMetricFormulaV1
    let includedFilters: [OperationsMetricInputFilterV1]
    let excludedFilters: [OperationsMetricExcludedFilterV1]
    let timeBasis: OperationsMetricTimeBasisV1
    let unavailableDisposition: OperationsMetricUnavailableDispositionV1
    let failureStartPredicate: OperationsMetricFailureStartPredicateV1
    let definitionSHA256: String

    init(
        identifier: OperationsMetricDefinitionIDV1,
        numeratorUnit: OperationsMetricUnitV1,
        denominatorUnit: OperationsMetricUnitV1
    ) throws {
        let resolvedFormula: OperationsMetricFormulaV1 = identifier == .qualifiedRecordedUnplannedMTBF
            ? .operatingExposurePerQualifyingFailureStart
            : .operatingExposureOverQualifiedExposure
        let resolvedIncludedFilters: [OperationsMetricInputFilterV1] = [
            .completeQualifiedExposure, .explicitPlannedNonserviceExclusions, .exactUnplannedFullInterruption
        ]
        let resolvedExcludedFilters: [OperationsMetricExcludedFilterV1] = [
            .plannedInterruption, .unknownOrigin, .unknownImpact, .uncertainOrOpenInterval,
            .incompleteCoverage, .replacementOrResetAmbiguity, .unresolvedOverlap
        ]
        let resolvedFailureStartPredicate: OperationsMetricFailureStartPredicateV1 =
            identifier == .qualifiedRecordedUnplannedMTBF
                ? .exactInWindowTransitionIntoUnplannedFullInterruption
                : .notApplicable
        let resolvedTimeBasis = OperationsMetricTimeBasisV1.observationWindowAsOf
        let resolvedUnavailableDisposition = OperationsMetricUnavailableDispositionV1.unavailableWithoutInference
        schemaVersion = Self.schemaVersion
        self.identifier = identifier
        version = Self.currentDefinitionVersion
        persistenceMode = OperationsMetricsContractV1.persistenceMode
        self.numeratorUnit = numeratorUnit
        self.denominatorUnit = denominatorUnit
        formula = resolvedFormula
        includedFilters = resolvedIncludedFilters
        excludedFilters = resolvedExcludedFilters
        timeBasis = resolvedTimeBasis
        unavailableDisposition = resolvedUnavailableDisposition
        failureStartPredicate = resolvedFailureStartPredicate
        definitionSHA256 = try ServiceReliabilityCanonicalCodecV1.sha256(
            Basis(
                schemaVersion: Self.schemaVersion,
                identifier: identifier,
                version: Self.currentDefinitionVersion,
                persistenceMode: OperationsMetricsContractV1.persistenceMode,
                numeratorUnit: numeratorUnit,
                denominatorUnit: denominatorUnit,
                formula: resolvedFormula,
                includedFilters: resolvedIncludedFilters,
                excludedFilters: resolvedExcludedFilters,
                timeBasis: resolvedTimeBasis,
                unavailableDisposition: resolvedUnavailableDisposition,
                failureStartPredicate: resolvedFailureStartPredicate
            )
        )
        try validate()
    }

    func validate() throws {
        try ServiceReliabilityLimitsV1.digest(definitionSHA256)
        guard schemaVersion == Self.schemaVersion,
              version == Self.currentDefinitionVersion,
              persistenceMode == OperationsMetricsContractV1.persistenceMode,
              includedFilters == [.completeQualifiedExposure, .explicitPlannedNonserviceExclusions,
                                  .exactUnplannedFullInterruption],
              excludedFilters == [.plannedInterruption, .unknownOrigin, .unknownImpact, .uncertainOrOpenInterval,
                                  .incompleteCoverage, .replacementOrResetAmbiguity, .unresolvedOverlap],
              timeBasis == .observationWindowAsOf,
              unavailableDisposition == .unavailableWithoutInference,
              definitionSHA256 == (try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else { throw OperationsMetricsFailureV1.invalidDefinition }

        switch identifier {
        case .qualifiedRecordedUnplannedMTBF:
            guard numeratorUnit == .milliseconds, denominatorUnit == .componentCount,
                  formula == .operatingExposurePerQualifyingFailureStart,
                  failureStartPredicate == .exactInWindowTransitionIntoUnplannedFullInterruption
            else { throw OperationsMetricsFailureV1.invalidDefinition }
        case .qualifiedRecordedUnplannedFullInterruptionAvailability:
            guard numeratorUnit == .milliseconds, denominatorUnit == .qualifiedExposureMilliseconds,
                  formula == .operatingExposureOverQualifiedExposure,
                  failureStartPredicate == .notApplicable
            else { throw OperationsMetricsFailureV1.invalidDefinition }
        }
    }

    private var basis: Basis {
        .init(
            schemaVersion: schemaVersion,
            identifier: identifier,
            version: version,
            persistenceMode: persistenceMode,
            numeratorUnit: numeratorUnit,
            denominatorUnit: denominatorUnit,
            formula: formula,
            includedFilters: includedFilters,
            excludedFilters: excludedFilters,
            timeBasis: timeBasis,
            unavailableDisposition: unavailableDisposition,
            failureStartPredicate: failureStartPredicate
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let identifier: OperationsMetricDefinitionIDV1
        let version: Int
        let persistenceMode: String
        let numeratorUnit: OperationsMetricUnitV1
        let denominatorUnit: OperationsMetricUnitV1
        let formula: OperationsMetricFormulaV1
        let includedFilters: [OperationsMetricInputFilterV1]
        let excludedFilters: [OperationsMetricExcludedFilterV1]
        let timeBasis: OperationsMetricTimeBasisV1
        let unavailableDisposition: OperationsMetricUnavailableDispositionV1
        let failureStartPredicate: OperationsMetricFailureStartPredicateV1
    }
}

enum OperationsMetricsContractV1 {
    static let schema = "OPERATIONS_METRICS_V1"
    static let persistenceMode = "DERIVED_ONLY"
    static let canonicalTruthOwner = "C53_SERVICE_RELIABILITY_CANONICAL_EVENTS"
    static let dropAndRebuildDisposition = "DROP_DERIVED_AND_REBUILD_FROM_C53"
    static let backupDisposition = "EXCLUDED_DERIVED_REBUILD"
    static let retryDisposition = "REBUILD_FROM_UNIQUE_CANONICAL_EVENT_ID_AND_REVISION"
    static func metricDefinitions() throws -> [MetricDefinitionV1] {
        [
            try .init(
                identifier: .qualifiedRecordedUnplannedMTBF,
                numeratorUnit: .milliseconds,
                denominatorUnit: .componentCount
            ),
            try .init(
                identifier: .qualifiedRecordedUnplannedFullInterruptionAvailability,
                numeratorUnit: .milliseconds,
                denominatorUnit: .qualifiedExposureMilliseconds
            )
        ]
    }

    static func definition(for identifier: OperationsMetricDefinitionIDV1) throws -> MetricDefinitionV1 {
        let definitions = try metricDefinitions()
        guard let definition = definitions.first(where: { $0.identifier == identifier })
        else { throw OperationsMetricsFailureV1.unsupportedMetricVersion }
        try definition.validate()
        return definition
    }

    static func validateRegistry() throws {
        try OperationsMetricsClaimBoundaryV1.validate()
        let definitions = try metricDefinitions()
        guard definitions.count == OperationsMetricDefinitionIDV1.allCases.count,
              definitions.map(\.identifier) == OperationsMetricDefinitionIDV1.allCases,
              Set(definitions.map(\.definitionSHA256)).count == definitions.count,
              schema == "OPERATIONS_METRICS_V1",
              persistenceMode == "DERIVED_ONLY"
        else { throw OperationsMetricsFailureV1.invalidDefinition }
        try definitions.forEach { try $0.validate() }
    }
}

enum OperationsMetricsClaimBoundaryV1 {
    static let derivesOnlyFromC53CanonicalInputs = true
    static let infersExposureFromAppAge = false
    static let infersExposureFromAssetAge = false
    static let infersExposureFromWorkCounts = false
    static let infersUptimeFromAbsentFailures = false
    static let bridgesCustomerLearningMetricDefinition = false
    static let writesCanonicalTruth = false
    static let grantsOptimisticCompletionClaim = false

    static func validate() throws {
        guard derivesOnlyFromC53CanonicalInputs,
              !infersExposureFromAppAge,
              !infersExposureFromAssetAge,
              !infersExposureFromWorkCounts,
              !infersUptimeFromAbsentFailures,
              !bridgesCustomerLearningMetricDefinition,
              !writesCanonicalTruth,
              !grantsOptimisticCompletionClaim
        else { throw OperationsMetricsFailureV1.invalidDefinition }
    }
}

import CryptoKit
import Dispatch
import Foundation

@testable import FieldEvidenceApp

enum CrossMarketConformanceFailureV1: Error, Equatable {
    case invalidValue
    case limitExceeded
    case nonCanonicalOrder
    case preconditionRejected
    case invariantViolated(ModelInvariantV1)
    case partialReceipt
    case releaseLeak(String)
}

enum ModelOperationKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case append = "APPEND"
    case supersede = "SUPERSEDE"
    case rejectStaleRevision = "REJECT_STALE_REVISION"
    case canonicalRoundTrip = "CANONICAL_ROUND_TRIP"
    case interruptBeforeEffect = "INTERRUPT_BEFORE_EFFECT"
    case interruptAfterEffectBeforeReceipt = "INTERRUPT_AFTER_EFFECT_BEFORE_RECEIPT"
    case replay = "REPLAY"
    case backupRestore = "BACKUP_RESTORE"
    case cloneFork = "CLONE_FORK"
    case deleteErase = "DELETE_ERASE"
    case rebuildProjection = "REBUILD_PROJECTION"
    case verifyReleaseExclusion = "VERIFY_RELEASE_EXCLUSION"
}

enum ModelExpectedDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case accepted = "ACCEPTED"
    case rejectedPrecondition = "REJECTED_PRECONDITION"
    case interruptedNoEffect = "INTERRUPTED_NO_EFFECT"
    case interruptedRecoverableEffect = "INTERRUPTED_RECOVERABLE_EFFECT"
    case idempotentReplay = "IDEMPOTENT_REPLAY"
}

enum ModelInvariantV1: String, CaseIterable, Codable, Hashable, Sendable {
    case canonicalBytesStable = "CANONICAL_BYTES_STABLE"
    case oneWriterReceipt = "ONE_WRITER_RECEIPT"
    case immutableHistory = "IMMUTABLE_HISTORY"
    case replayConverges = "REPLAY_CONVERGES"
    case noScratchOrphan = "NO_SCRATCH_ORPHAN"
    case boundedExecution = "BOUNDED_EXECUTION"
    case releaseExcluded = "RELEASE_EXCLUDED"
}

enum CrossMarketArchetypeCapabilityV1: String, CaseIterable, Codable, Hashable, Sendable {
    case siteLocationCompositionArea = "SITE_LOCATION_COMPOSITION_AREA"
    case criterionConflict = "CRITERION_CONFLICT"
    case findingCorrectiveRecheck = "FINDING_CORRECTIVE_RECHECK"
    case attributionSignoff = "ATTRIBUTION_SIGNOFF"
    case reportProjection = "REPORT_PROJECTION"
    case controllerZoneTopology = "CONTROLLER_ZONE_TOPOLOGY"
    case preventiveMaintenance = "PREVENTIVE_MAINTENANCE"
    case exactMeasurement = "EXACT_MEASUREMENT"
    case sharedComponent = "SHARED_COMPONENT"
    case boundedCardinality = "BOUNDED_CARDINALITY"
}

enum ModelMeasurementUnitV1: String, Codable, Equatable, Sendable {
    case lux = "LUX"
    case squareMillimetres = "SQUARE_MILLIMETRES"
}

struct ModelExactQuantityV1: Codable, Equatable, Sendable {
    let numerator: Int64
    let denominator: Int64
    let unit: ModelMeasurementUnitV1

    init(numerator: Int64, denominator: Int64, unit: ModelMeasurementUnitV1) throws {
        guard (0...1_000_000_000).contains(numerator),
              (1...1_000_000_000).contains(denominator),
              Self.greatestCommonDivisor(numerator, denominator) == 1 else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        self.numerator = numerator
        self.denominator = denominator
        self.unit = unit
    }

    func validate() throws {
        _ = try Self(numerator: numerator, denominator: denominator, unit: unit)
    }

    private static func greatestCommonDivisor(_ left: Int64, _ right: Int64) -> Int64 {
        var a = left
        var b = right
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(a, 1)
    }
}

struct ModelRunBoundsV1: Codable, Equatable, Sendable {
    static let hardMaximumCases = 512
    static let hardMaximumOperations = 4_096
    static let hardMaximumShrinkSteps = 256
    static let hardMaximumScratchBytes = 16 * 1_024 * 1_024
    static let hardMaximumDurationMilliseconds = 30_000

    let maximumCases: Int
    let maximumOperationsPerCase: Int
    let maximumShrinkSteps: Int
    let maximumScratchBytes: Int
    let maximumDurationMilliseconds: Int

    func validate() throws {
        guard (1...Self.hardMaximumCases).contains(maximumCases),
              (1...Self.hardMaximumOperations).contains(maximumOperationsPerCase),
              (0...Self.hardMaximumShrinkSteps).contains(maximumShrinkSteps),
              (1...Self.hardMaximumScratchBytes).contains(maximumScratchBytes),
              (1...Self.hardMaximumDurationMilliseconds).contains(maximumDurationMilliseconds) else {
            throw CrossMarketConformanceFailureV1.limitExceeded
        }
    }
}

struct ModelOperationV1: Codable, Equatable, Sendable {
    let ordinal: Int
    let kind: ModelOperationKindV1
    let entityKind: WorkspaceEntityKindV1?
    let entityID: UUID?
    let expectedRevision: UInt64?
    let resultingRevision: UInt64?
    let mutationID: MutationIDV1?
    let payloadSHA256: String
    let expectedDisposition: ModelExpectedDispositionV1

    init(
        ordinal: Int, kind: ModelOperationKindV1,
        entityKind: WorkspaceEntityKindV1? = nil, entityID: UUID? = nil,
        expectedRevision: UInt64? = nil, resultingRevision: UInt64? = nil,
        mutationID: MutationIDV1? = nil, payloadSHA256: String,
        expectedDisposition: ModelExpectedDispositionV1
    ) throws {
        self.ordinal = ordinal
        self.kind = kind
        self.entityKind = entityKind
        self.entityID = entityID
        self.expectedRevision = expectedRevision
        self.resultingRevision = resultingRevision
        self.mutationID = mutationID
        self.payloadSHA256 = payloadSHA256
        self.expectedDisposition = expectedDisposition
        try validate()
    }

    func validate() throws {
        let entityOperation = [.append, .supersede, .rejectStaleRevision].contains(kind)
        guard ordinal > 0, CrossMarketCanonicalV1.isSHA256(payloadSHA256),
              (entityKind == nil) == (entityID == nil),
              !entityOperation || (entityKind != nil && mutationID != nil && expectedRevision != nil),
              resultingRevision.map({ $0 > 0 }) ?? true else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        switch kind {
        case .append, .supersede:
            guard expectedDisposition == .accepted, let expectedRevision,
                  expectedRevision < .max, resultingRevision == expectedRevision + 1 else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        case .rejectStaleRevision:
            guard expectedDisposition == .rejectedPrecondition, resultingRevision == nil else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        default:
            guard entityKind == nil, entityID == nil, expectedRevision == nil,
                  resultingRevision == nil, mutationID == nil else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        }
    }

    func replacingOrdinal(_ value: Int) throws -> ModelOperationV1 {
        try .init(ordinal: value, kind: kind, entityKind: entityKind, entityID: entityID,
                  expectedRevision: expectedRevision, resultingRevision: resultingRevision,
                  mutationID: mutationID, payloadSHA256: payloadSHA256,
                  expectedDisposition: expectedDisposition)
    }
}

struct ModelSemanticEntityV1: Codable, Equatable, Sendable {
    let kind: WorkspaceEntityKindV1
    let id: UUID
    let contentSHA256: String
    var stableKey: String { "\(kind.rawValue)|\(id.uuidString.lowercased())" }

    func validate() throws {
        guard id != CrossMarketCanonicalV1.zeroUUID,
              CrossMarketCanonicalV1.isSHA256(contentSHA256) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }
}

enum CrossMarketArchetypeStateV1: Codable, Equatable, Sendable {
    case compositeAreaSafety(CompositeAreaSafetyModelV1)
    case controllerZoneDistribution(ControllerZoneDistributionModelV1)

    func validate() throws {
        switch self {
        case let .compositeAreaSafety(model): try model.validate()
        case let .controllerZoneDistribution(model): try model.validate()
        }
        let entities = try semanticEntities()
        try entities.forEach { try $0.validate() }
        guard !entities.isEmpty, Set(entities.map(\.stableKey)).count == entities.count,
              entities == entities.sorted(by: { $0.stableKey < $1.stableKey }) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    func semanticEntities() throws -> [ModelSemanticEntityV1] {
        switch self {
        case let .compositeAreaSafety(model): return try model.semanticEntities()
        case let .controllerZoneDistribution(model): return try model.semanticEntities()
        }
    }
}

struct MinimizedCounterexampleV1: Codable, Equatable, Sendable {
    let invariant: ModelInvariantV1
    let originalOperationCount: Int
    let operations: [ModelOperationV1]
    let shrinkStepCount: Int

    func validate(bounds: ModelRunBoundsV1) throws {
        guard !operations.isEmpty, operations.count <= originalOperationCount,
              (0...bounds.maximumShrinkSteps).contains(shrinkStepCount),
              operations.map(\.ordinal) == Array(1...operations.count) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        try operations.forEach { try $0.validate() }
    }

    func validate(
        bounds: ModelRunBoundsV1,
        preserving fingerprint: ModelFailureFingerprintV1
    ) throws {
        try validate(bounds: bounds)
        let identities = operations.map(ModelCausalOperationIdentityV1.init)
        guard invariant == fingerprint.invariant,
              identities.contains(fingerprint.faultingOperation),
              fingerprint.causalOperations.allSatisfy(identities.contains) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        if invariant == .replayConverges {
            guard let interruptionIndex = operations.firstIndex(where: {
                      $0.kind == .interruptAfterEffectBeforeReceipt
                  }),
                  let replayIndex = operations.firstIndex(where: { $0.kind == .replay }),
                  interruptionIndex < replayIndex else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        }
        if let duplicateMutationID = fingerprint.duplicateMutationID {
            let pair = operations.filter { $0.mutationID == duplicateMutationID }
            guard pair.count == 2,
                  pair.map(ModelCausalOperationIdentityV1.init).allSatisfy(
                    fingerprint.causalOperations.contains
                  ) else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        }
    }
}

enum ModelFaultBoundaryV1: String, Codable, Equatable, Sendable {
    case entityMutation = "ENTITY_MUTATION"
    case staleRevision = "STALE_REVISION"
    case canonicalCodec = "CANONICAL_CODEC"
    case backupRestore = "BACKUP_RESTORE"
    case cloneFork = "CLONE_FORK"
    case interruptionBeforeEffect = "INTERRUPTION_BEFORE_EFFECT"
    case interruptionAfterEffect = "INTERRUPTION_AFTER_EFFECT"
    case replay = "REPLAY"
    case projectionRebuild = "PROJECTION_REBUILD"
    case deleteErase = "DELETE_ERASE"
    case releaseExclusion = "RELEASE_EXCLUSION"
    case caseFinalization = "CASE_FINALIZATION"
}

struct ModelCausalOperationIdentityV1: Codable, Equatable, Sendable {
    let kind: ModelOperationKindV1
    let entityKind: WorkspaceEntityKindV1?
    let entityID: UUID?
    let expectedRevision: UInt64?
    let resultingRevision: UInt64?
    let mutationID: MutationIDV1?
    let payloadSHA256: String

    init(_ operation: ModelOperationV1) {
        kind = operation.kind
        entityKind = operation.entityKind
        entityID = operation.entityID
        expectedRevision = operation.expectedRevision
        resultingRevision = operation.resultingRevision
        mutationID = operation.mutationID
        payloadSHA256 = operation.payloadSHA256
    }

    func validate() throws {
        guard CrossMarketCanonicalV1.isSHA256(payloadSHA256),
              (entityKind == nil) == (entityID == nil) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }
}

struct ModelFailureFingerprintV1: Codable, Equatable, Sendable {
    let invariant: ModelInvariantV1
    let faultBoundary: ModelFaultBoundaryV1
    let causeCode: String
    let faultingOperation: ModelCausalOperationIdentityV1
    let causalOperations: [ModelCausalOperationIdentityV1]
    let duplicateMutationID: MutationIDV1?
    let fingerprintSHA256: String

    init(
        invariant: ModelInvariantV1,
        faultBoundary: ModelFaultBoundaryV1,
        causeCode: String,
        faultingOperation: ModelCausalOperationIdentityV1,
        causalOperations: [ModelCausalOperationIdentityV1],
        duplicateMutationID: MutationIDV1?
    ) throws {
        self.invariant = invariant
        self.faultBoundary = faultBoundary
        self.causeCode = causeCode
        self.faultingOperation = faultingOperation
        self.causalOperations = causalOperations
        self.duplicateMutationID = duplicateMutationID
        fingerprintSHA256 = try CrossMarketCanonicalV1.sha256(Basis(
            invariant: invariant, faultBoundary: faultBoundary,
            causeCode: causeCode, faultingOperation: faultingOperation,
            causalOperations: causalOperations, duplicateMutationID: duplicateMutationID
        ))
        try validate()
    }

    func validate() throws {
        try faultingOperation.validate()
        try causalOperations.forEach { try $0.validate() }
        let causalDigests = try causalOperations.map {
            try CrossMarketCanonicalV1.sha256($0)
        }
        guard !causeCode.isEmpty, causeCode.utf8.count <= 128,
              !causalOperations.isEmpty,
              causalOperations.contains(faultingOperation),
              Set(causalDigests).count == causalOperations.count,
              fingerprintSHA256 == (try CrossMarketCanonicalV1.sha256(basis)) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        if invariant == .replayConverges {
            guard causalOperations.contains(where: {
                      $0.kind == .interruptAfterEffectBeforeReceipt
                  }),
                  causalOperations.contains(where: { $0.kind == .replay }) else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        }
        if let duplicateMutationID {
            let duplicatePair = causalOperations.filter {
                $0.mutationID == duplicateMutationID
            }
            guard duplicatePair.count == 2 else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        }
    }

    private var basis: Basis {
        .init(invariant: invariant, faultBoundary: faultBoundary,
              causeCode: causeCode, faultingOperation: faultingOperation,
              causalOperations: causalOperations, duplicateMutationID: duplicateMutationID)
    }

    private struct Basis: Codable {
        let invariant: ModelInvariantV1
        let faultBoundary: ModelFaultBoundaryV1
        let causeCode: String
        let faultingOperation: ModelCausalOperationIdentityV1
        let causalOperations: [ModelCausalOperationIdentityV1]
        let duplicateMutationID: MutationIDV1?
    }
}

struct ModelFailingDiagnosticReceiptV1: Codable, Equatable, Sendable {
    let archetypeID: String
    let seed: UInt64
    let generatorVersion: String
    let bounds: ModelRunBoundsV1
    let sourceScenarioSHA256: String
    let fingerprint: ModelFailureFingerprintV1
    let counterexample: MinimizedCounterexampleV1
    let receiptSHA256: String

    init(
        archetypeID: String, seed: UInt64, bounds: ModelRunBoundsV1,
        sourceScenarioSHA256: String, fingerprint: ModelFailureFingerprintV1,
        counterexample: MinimizedCounterexampleV1
    ) throws {
        self.archetypeID = archetypeID
        self.seed = seed
        generatorVersion = ModelRunReceiptV1.generatorVersion
        self.bounds = bounds
        self.sourceScenarioSHA256 = sourceScenarioSHA256
        self.fingerprint = fingerprint
        self.counterexample = counterexample
        receiptSHA256 = try CrossMarketCanonicalV1.sha256(Basis(
            archetypeID: archetypeID, seed: seed,
            generatorVersion: ModelRunReceiptV1.generatorVersion,
            bounds: bounds, sourceScenarioSHA256: sourceScenarioSHA256,
            fingerprint: fingerprint, counterexample: counterexample
        ))
        try validate()
    }

    func validate() throws {
        try bounds.validate()
        try fingerprint.validate()
        try counterexample.validate(bounds: bounds, preserving: fingerprint)
        guard !archetypeID.isEmpty, archetypeID.utf8.count <= 128,
              generatorVersion == ModelRunReceiptV1.generatorVersion,
              CrossMarketCanonicalV1.isSHA256(sourceScenarioSHA256),
              receiptSHA256 == (try CrossMarketCanonicalV1.sha256(basis)) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    private var basis: Basis {
        .init(archetypeID: archetypeID, seed: seed, generatorVersion: generatorVersion,
              bounds: bounds, sourceScenarioSHA256: sourceScenarioSHA256,
              fingerprint: fingerprint, counterexample: counterexample)
    }

    private struct Basis: Codable {
        let archetypeID: String
        let seed: UInt64
        let generatorVersion: String
        let bounds: ModelRunBoundsV1
        let sourceScenarioSHA256: String
        let fingerprint: ModelFailureFingerprintV1
        let counterexample: MinimizedCounterexampleV1
    }
}

struct ModelConformanceRunFailureV1: Error, Equatable {
    let cause: CrossMarketConformanceFailureV1
    let fingerprint: ModelFailureFingerprintV1
    let counterexample: MinimizedCounterexampleV1
    let diagnosticReceipt: ModelFailingDiagnosticReceiptV1
}

struct ModelRunReceiptV1: Codable, Equatable, Sendable {
    static let generatorVersion = "C42.MODEL.GENERATOR.V1"

    let archetypeID: String
    let seed: UInt64
    let generatorVersion: String
    let bounds: ModelRunBoundsV1
    let operations: [ModelOperationV1]
    let executedCaseCount: Int
    let executedOperationCount: Int
    let caseResultSHA256s: [String]
    let preconditionRejectionCount: Int
    let expectedInvariant: ModelInvariantV1
    let minimizedCounterexample: MinimizedCounterexampleV1?
    let normalizedResultSHA256: String
    let scratchBytesRemoved: Int
    let scratchCleanupComplete: Bool
    let acceptanceCredit: Bool
    let receiptSHA256: String

    init(
        archetypeID: String, seed: UInt64, bounds: ModelRunBoundsV1,
        operations: [ModelOperationV1], executedCaseCount: Int,
        executedOperationCount: Int, caseResultSHA256s: [String],
        preconditionRejectionCount: Int, expectedInvariant: ModelInvariantV1,
        minimizedCounterexample: MinimizedCounterexampleV1? = nil,
        normalizedResultSHA256: String, scratchBytesRemoved: Int,
        scratchCleanupComplete: Bool = true
    ) throws {
        self.archetypeID = archetypeID
        self.seed = seed
        generatorVersion = Self.generatorVersion
        self.bounds = bounds
        self.operations = operations
        self.executedCaseCount = executedCaseCount
        self.executedOperationCount = executedOperationCount
        self.caseResultSHA256s = caseResultSHA256s
        self.preconditionRejectionCount = preconditionRejectionCount
        self.expectedInvariant = expectedInvariant
        self.minimizedCounterexample = minimizedCounterexample
        self.normalizedResultSHA256 = normalizedResultSHA256
        self.scratchBytesRemoved = scratchBytesRemoved
        self.scratchCleanupComplete = scratchCleanupComplete
        acceptanceCredit = false
        receiptSHA256 = try CrossMarketCanonicalV1.sha256(Basis(
            archetypeID: archetypeID, seed: seed, generatorVersion: Self.generatorVersion,
            bounds: bounds, operations: operations, executedCaseCount: executedCaseCount,
            executedOperationCount: executedOperationCount, caseResultSHA256s: caseResultSHA256s,
            preconditionRejectionCount: preconditionRejectionCount,
            expectedInvariant: expectedInvariant, minimizedCounterexample: minimizedCounterexample,
            normalizedResultSHA256: normalizedResultSHA256,
            scratchBytesRemoved: scratchBytesRemoved,
            scratchCleanupComplete: scratchCleanupComplete, acceptanceCredit: false
        ))
        try validate()
    }

    func validate() throws {
        try bounds.validate()
        try operations.forEach { try $0.validate() }
        try minimizedCounterexample?.validate(bounds: bounds)
        let maximumExecuted = bounds.maximumCases * bounds.maximumOperationsPerCase
        guard !archetypeID.isEmpty, archetypeID.utf8.count <= 128,
              generatorVersion == Self.generatorVersion, !operations.isEmpty,
              operations.count <= bounds.maximumOperationsPerCase,
              operations.map(\.ordinal) == Array(1...operations.count),
              executedCaseCount == bounds.maximumCases,
              caseResultSHA256s.count == executedCaseCount,
              caseResultSHA256s.allSatisfy(CrossMarketCanonicalV1.isSHA256),
              (1...maximumExecuted).contains(executedOperationCount),
              (0...executedOperationCount).contains(preconditionRejectionCount),
              CrossMarketCanonicalV1.isSHA256(normalizedResultSHA256),
              (1...bounds.maximumScratchBytes).contains(scratchBytesRemoved),
              scratchCleanupComplete, !acceptanceCredit,
              minimizedCounterexample.map({ $0.invariant == expectedInvariant }) ?? true,
              receiptSHA256 == (try CrossMarketCanonicalV1.sha256(basis)) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    private var basis: Basis {
        .init(archetypeID: archetypeID, seed: seed, generatorVersion: generatorVersion,
              bounds: bounds, operations: operations, executedCaseCount: executedCaseCount,
              executedOperationCount: executedOperationCount, caseResultSHA256s: caseResultSHA256s,
              preconditionRejectionCount: preconditionRejectionCount,
              expectedInvariant: expectedInvariant, minimizedCounterexample: minimizedCounterexample,
              normalizedResultSHA256: normalizedResultSHA256,
              scratchBytesRemoved: scratchBytesRemoved,
              scratchCleanupComplete: scratchCleanupComplete, acceptanceCredit: acceptanceCredit)
    }

    private struct Basis: Codable {
        let archetypeID: String; let seed: UInt64; let generatorVersion: String
        let bounds: ModelRunBoundsV1; let operations: [ModelOperationV1]
        let executedCaseCount: Int; let executedOperationCount: Int
        let caseResultSHA256s: [String]; let preconditionRejectionCount: Int
        let expectedInvariant: ModelInvariantV1
        let minimizedCounterexample: MinimizedCounterexampleV1?
        let normalizedResultSHA256: String; let scratchBytesRemoved: Int
        let scratchCleanupComplete: Bool; let acceptanceCredit: Bool
    }
}

struct DeterministicRegressionPromotionReceiptV1: Codable, Equatable, Sendable {
    let sourceDiagnosticReceipt: ModelFailingDiagnosticReceiptV1
    let sourceFailingDiagnosticReceiptSHA256: String
    let promotedFixtureRelativePath: String
    let promotedFixtureSHA256: String
    let counterexample: MinimizedCounterexampleV1
    let invariant: ModelInvariantV1
    let promotionVersion: String
    let receiptSHA256: String

    init(
        sourceDiagnosticReceipt: ModelFailingDiagnosticReceiptV1,
        promotedFixtureRelativePath: String,
        promotedFixtureSHA256: String,
        bounds: ModelRunBoundsV1
    ) throws {
        self.sourceDiagnosticReceipt = sourceDiagnosticReceipt
        sourceFailingDiagnosticReceiptSHA256 = sourceDiagnosticReceipt.receiptSHA256
        self.promotedFixtureRelativePath = promotedFixtureRelativePath
        self.promotedFixtureSHA256 = promotedFixtureSHA256
        counterexample = sourceDiagnosticReceipt.counterexample
        invariant = sourceDiagnosticReceipt.fingerprint.invariant
        promotionVersion = "C42.REGRESSION.PROMOTION.V1"
        receiptSHA256 = try CrossMarketCanonicalV1.sha256(Basis(
            sourceDiagnosticReceipt: sourceDiagnosticReceipt,
            sourceFailingDiagnosticReceiptSHA256: sourceDiagnosticReceipt.receiptSHA256,
            promotedFixtureRelativePath: promotedFixtureRelativePath,
            promotedFixtureSHA256: promotedFixtureSHA256,
            counterexample: sourceDiagnosticReceipt.counterexample,
            invariant: sourceDiagnosticReceipt.fingerprint.invariant,
            promotionVersion: "C42.REGRESSION.PROMOTION.V1"
        ))
        try validate(bounds: bounds)
    }

    func validate(bounds: ModelRunBoundsV1) throws {
        try sourceDiagnosticReceipt.validate()
        try counterexample.validate(
            bounds: bounds, preserving: sourceDiagnosticReceipt.fingerprint
        )
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        let fixtureRoot = sourceRoot
            .appendingPathComponent("FieldEvidenceAppTests/Fixtures", isDirectory: true)
            .standardizedFileURL
        let fixtureURL = sourceRoot
            .appendingPathComponent(promotedFixtureRelativePath, isDirectory: false)
            .standardizedFileURL
        let fixtureRootPrefix = fixtureRoot.path.hasSuffix("/")
            ? fixtureRoot.path : fixtureRoot.path + "/"
        guard sourceDiagnosticReceipt.bounds == bounds,
              sourceFailingDiagnosticReceiptSHA256 == sourceDiagnosticReceipt.receiptSHA256,
              CrossMarketCanonicalV1.isSHA256(sourceFailingDiagnosticReceiptSHA256),
              CrossMarketCanonicalV1.isSHA256(promotedFixtureSHA256),
              promotedFixtureRelativePath.hasPrefix("FieldEvidenceAppTests/Fixtures/"),
              !promotedFixtureRelativePath.contains(".."),
              fixtureURL.path.hasPrefix(fixtureRootPrefix),
              let fixtureBytes = try? Data(contentsOf: fixtureURL, options: [.mappedIfSafe]),
              CrossMarketCanonicalV1.sha256(rawData: fixtureBytes) == promotedFixtureSHA256,
              counterexample == sourceDiagnosticReceipt.counterexample,
              invariant == sourceDiagnosticReceipt.fingerprint.invariant,
              counterexample.invariant == invariant,
              receiptSHA256 == (try CrossMarketCanonicalV1.sha256(basis)) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    private var basis: Basis {
        .init(sourceDiagnosticReceipt: sourceDiagnosticReceipt,
              sourceFailingDiagnosticReceiptSHA256: sourceFailingDiagnosticReceiptSHA256,
              promotedFixtureRelativePath: promotedFixtureRelativePath,
              promotedFixtureSHA256: promotedFixtureSHA256,
              counterexample: counterexample, invariant: invariant,
              promotionVersion: promotionVersion)
    }

    private struct Basis: Codable {
        let sourceDiagnosticReceipt: ModelFailingDiagnosticReceiptV1
        let sourceFailingDiagnosticReceiptSHA256: String
        let promotedFixtureRelativePath: String
        let promotedFixtureSHA256: String
        let counterexample: MinimizedCounterexampleV1
        let invariant: ModelInvariantV1
        let promotionVersion: String
    }
}

struct CrossMarketArchetypeScenarioV1: Codable, Equatable, Sendable {
    let archetypeID: String
    let archetypeVersion: Int
    let seed: UInt64
    let bounds: ModelRunBoundsV1
    let operations: [ModelOperationV1]
    let operationAlphabet: [ModelOperationKindV1]
    let semanticState: CrossMarketArchetypeStateV1
    let capabilities: [CrossMarketArchetypeCapabilityV1]
    let expectedInvariants: [ModelInvariantV1]

    init(
        archetypeID: String, archetypeVersion: Int, seed: UInt64,
        bounds: ModelRunBoundsV1, operations: [ModelOperationV1],
        operationAlphabet: [ModelOperationKindV1]? = nil,
        semanticState: CrossMarketArchetypeStateV1,
        capabilities: [CrossMarketArchetypeCapabilityV1],
        expectedInvariants: [ModelInvariantV1]
    ) {
        self.archetypeID = archetypeID
        self.archetypeVersion = archetypeVersion
        self.seed = seed
        self.bounds = bounds
        self.operations = operations
        self.operationAlphabet = operationAlphabet
            ?? Array(Set(operations.map(\.kind))).sorted(by: { $0.rawValue < $1.rawValue })
        self.semanticState = semanticState
        self.capabilities = capabilities
        self.expectedInvariants = expectedInvariants
    }

    func validate() throws {
        try bounds.validate()
        try semanticState.validate()
        try operations.forEach { try $0.validate() }
        let semanticKeys = Set(try semanticState.semanticEntities().map(\.stableKey))
        let appendedKeys = operations.compactMap { operation -> String? in
            guard operation.kind == .append, let kind = operation.entityKind,
                  let id = operation.entityID else { return nil }
            return "\(kind.rawValue)|\(id.uuidString.lowercased())"
        }
        let expectedAlphabet = Array(Set(operations.map(\.kind)))
            .sorted { $0.rawValue < $1.rawValue }
        guard archetypeVersion == 1, !archetypeID.isEmpty, !operations.isEmpty,
              operations.count <= bounds.maximumOperationsPerCase,
              operations.map(\.ordinal) == Array(1...operations.count),
              Set(appendedKeys) == semanticKeys,
              operationAlphabet == expectedAlphabet, !capabilities.isEmpty,
              capabilities == capabilities.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(capabilities).count == capabilities.count,
              expectedInvariants == expectedInvariants.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(expectedInvariants).count == expectedInvariants.count else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }
}

struct SeededModelGeneratorV1: Sendable {
    private(set) var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func uuid() -> UUID {
        let high = next(), low = next()
        let bytes: [UInt8] = (0..<8).map {
            UInt8(truncatingIfNeeded: high >> UInt64($0 * 8))
        } + (0..<8).map {
            UInt8(truncatingIfNeeded: low >> UInt64($0 * 8))
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

enum CrossMarketScenarioFactoryV1 {
    static func operation(
        _ ordinal: Int, _ kind: ModelOperationKindV1,
        generator: inout SeededModelGeneratorV1,
        entityKind: WorkspaceEntityKindV1? = nil, entityID: UUID? = nil,
        expectedRevision: UInt64? = nil, resultingRevision: UInt64? = nil,
        disposition: ModelExpectedDispositionV1 = .accepted
    ) throws -> ModelOperationV1 {
        let mutationID: MutationIDV1? = [.append, .supersede, .rejectStaleRevision].contains(kind)
            ? try MutationIDV1(rawValue: generator.uuid()) : nil
        let payload = try CrossMarketCanonicalV1.sha256(OperationBasis(
            ordinal: ordinal, kind: kind, entityKind: entityKind, entityID: entityID,
            expectedRevision: expectedRevision, resultingRevision: resultingRevision,
            nonce: generator.next(), disposition: disposition
        ))
        return try .init(ordinal: ordinal, kind: kind, entityKind: entityKind,
                         entityID: entityID, expectedRevision: expectedRevision,
                         resultingRevision: resultingRevision, mutationID: mutationID,
                         payloadSHA256: payload, expectedDisposition: disposition)
    }

    private struct OperationBasis: Codable {
        let ordinal: Int; let kind: ModelOperationKindV1
        let entityKind: WorkspaceEntityKindV1?; let entityID: UUID?
        let expectedRevision: UInt64?; let resultingRevision: UInt64?
        let nonce: UInt64; let disposition: ModelExpectedDispositionV1
    }
}

struct ModelEntityHeadV1: Codable, Equatable, Sendable {
    let kind: WorkspaceEntityKindV1
    let id: UUID
    let revision: UInt64
    let semanticSHA256: String
    var stableKey: String { "\(kind.rawValue)|\(id.uuidString.lowercased())" }
}

private struct ModelAppliedMutationV1: Codable, Equatable {
    let mutationID: MutationIDV1
    let operationKind: ModelOperationKindV1
    let entityKey: String
    let resultingRevision: UInt64
    let resultSHA256: String
}

private struct ModelPendingEffectV1: Codable, Equatable {
    let operationOrdinal: Int
    let effectSHA256: String
}

private struct ModelMachineStateV1: Codable, Equatable {
    var heads: [String: ModelEntityHeadV1] = [:]
    var immutableHistory: [ModelAppliedMutationV1] = []
    var projection: [ModelEntityHeadV1] = []
    var appliedMutationIDs: [MutationIDV1] = []
    var deletionLedgerMutationIDs: [MutationIDV1] = []
    var pendingEffect: ModelPendingEffectV1?
    var effectReceipts: [String] = []
    var erased = false
}

private struct ModelCaseExecutionV1: Codable, Equatable {
    let caseIndex: Int
    let selectedOperationSHA256: String
    let finalStateSHA256: String
    let semanticStateSHA256: String
    let rejectedPreconditions: Int
    let executedOperationCount: Int
    let scratchBytesRemoved: Int
}

private struct ModelExecutionFaultV1: Error, Equatable {
    let cause: CrossMarketConformanceFailureV1
    let fingerprint: ModelFailureFingerprintV1
}

enum ModelConformanceRunnerV1 {
    static func replay(
        _ diagnosticReceipt: ModelFailingDiagnosticReceiptV1,
        in sourceScenario: CrossMarketArchetypeScenarioV1
    ) throws -> ModelFailureFingerprintV1 {
        try diagnosticReceipt.validate()
        try sourceScenario.validate()
        guard diagnosticReceipt.archetypeID == sourceScenario.archetypeID,
              diagnosticReceipt.seed == sourceScenario.seed,
              diagnosticReceipt.bounds == sourceScenario.bounds,
              diagnosticReceipt.sourceScenarioSHA256
                == (try CrossMarketCanonicalV1.sha256(sourceScenario)) else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        let interval = UInt64(sourceScenario.bounds.maximumDurationMilliseconds) * 1_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds.addingReportingOverflow(interval)
        guard !deadline.overflow else { throw CrossMarketConformanceFailureV1.limitExceeded }
        do {
            _ = try executeCase(
                semanticState: sourceScenario.semanticState,
                operations: diagnosticReceipt.counterexample.operations,
                caseIndex: 0,
                expectedInvariant: diagnosticReceipt.fingerprint.invariant,
                bounds: sourceScenario.bounds,
                deadlineNanoseconds: deadline.partialValue
            )
        } catch let fault as ModelExecutionFaultV1 {
            guard fault.fingerprint == diagnosticReceipt.fingerprint else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
            return fault.fingerprint
        }
        throw CrossMarketConformanceFailureV1.invalidValue
    }

    static func run(
        _ scenario: CrossMarketArchetypeScenarioV1,
        expectedInvariant: ModelInvariantV1
    ) throws -> ModelRunReceiptV1 {
        try scenario.validate()
        guard scenario.expectedInvariants.contains(expectedInvariant) else {
            throw CrossMarketConformanceFailureV1.invariantViolated(expectedInvariant)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        let interval = UInt64(scenario.bounds.maximumDurationMilliseconds) * 1_000_000
        let deadline = start.addingReportingOverflow(interval)
        guard !deadline.overflow else { throw CrossMarketConformanceFailureV1.limitExceeded }

        var caseDigests: [String] = []
        var rejectedCount = 0
        var executedCount = 0
        var removedScratchBytes = 0
        for caseIndex in 0..<scenario.bounds.maximumCases {
            try enforceDuration(deadline.partialValue)
            let selected = selectedOperations(for: scenario, caseIndex: caseIndex)
            guard !selected.isEmpty,
                  selected.count <= scenario.bounds.maximumOperationsPerCase else {
                throw CrossMarketConformanceFailureV1.limitExceeded
            }
            do {
                let result = try executeCase(
                    semanticState: scenario.semanticState, operations: selected,
                    caseIndex: caseIndex, expectedInvariant: expectedInvariant,
                    bounds: scenario.bounds,
                    deadlineNanoseconds: deadline.partialValue
                )
                caseDigests.append(try CrossMarketCanonicalV1.sha256(CaseEnvelope(
                    semanticState: scenario.semanticState, execution: result
                )))
                rejectedCount += result.rejectedPreconditions
                executedCount += result.executedOperationCount
                removedScratchBytes = max(removedScratchBytes, result.scratchBytesRemoved)
            } catch let fault as ModelExecutionFaultV1 {
                let counterexample = try minimizedCounterexample(
                    semanticState: scenario.semanticState, operations: selected,
                    matching: fault.fingerprint, bounds: scenario.bounds,
                    deadlineNanoseconds: deadline.partialValue
                )
                let diagnostic = try ModelFailingDiagnosticReceiptV1(
                    archetypeID: scenario.archetypeID, seed: scenario.seed,
                    bounds: scenario.bounds,
                    sourceScenarioSHA256: CrossMarketCanonicalV1.sha256(scenario),
                    fingerprint: fault.fingerprint, counterexample: counterexample
                )
                throw ModelConformanceRunFailureV1(
                    cause: fault.cause, fingerprint: fault.fingerprint,
                    counterexample: counterexample, diagnosticReceipt: diagnostic
                )
            } catch let cause as CrossMarketConformanceFailureV1 {
                throw cause
            }
        }

        let normalized = try CrossMarketCanonicalV1.sha256(CaseResultsBasis(
            archetypeID: scenario.archetypeID, seed: scenario.seed,
            semanticStateSHA256: CrossMarketCanonicalV1.sha256(scenario.semanticState),
            caseResultSHA256s: caseDigests
        ))
        return try ModelRunReceiptV1(
            archetypeID: scenario.archetypeID, seed: scenario.seed, bounds: scenario.bounds,
            operations: scenario.operations, executedCaseCount: caseDigests.count,
            executedOperationCount: executedCount, caseResultSHA256s: caseDigests,
            preconditionRejectionCount: rejectedCount, expectedInvariant: expectedInvariant,
            normalizedResultSHA256: normalized, scratchBytesRemoved: removedScratchBytes
        )
    }

    private static func selectedOperations(
        for scenario: CrossMarketArchetypeScenarioV1, caseIndex: Int
    ) -> [ModelOperationV1] {
        guard caseIndex > 0 else { return scenario.operations }
        var generator = SeededModelGeneratorV1(
            seed: scenario.seed &+ UInt64(caseIndex) &* 0xD134_2543_DE82_EF95
        )
        let required: Set<ModelOperationKindV1> = [
            .append, .supersede, .rejectStaleRevision,
            .interruptAfterEffectBeforeReceipt, .replay,
            .deleteErase, .verifyReleaseExclusion,
        ]
        return scenario.operations.filter { operation in
            required.contains(operation.kind) || generator.next() & 1 == 0
        }
    }

    private static func executeCase(
        semanticState: CrossMarketArchetypeStateV1,
        operations: [ModelOperationV1], caseIndex: Int,
        expectedInvariant: ModelInvariantV1,
        bounds: ModelRunBoundsV1, deadlineNanoseconds: UInt64
    ) throws -> ModelCaseExecutionV1 {
        let semanticByKey = Dictionary(uniqueKeysWithValues:
            try semanticState.semanticEntities().map { ($0.stableKey, $0) }
        )
        var state = ModelMachineStateV1()
        var scratch: Data?
        var rejectedCount = 0
        var removedScratchBytes = 0
        var appliedOperationByMutationID: [MutationIDV1: ModelCausalOperationIdentityV1] = [:]

        for operation in operations {
            try enforceDuration(deadlineNanoseconds)
            do {
                try operation.validate()
                switch operation.kind {
            case .append, .supersede:
                guard let kind = operation.entityKind, let id = operation.entityID,
                      let expected = operation.expectedRevision,
                      let resulting = operation.resultingRevision,
                      let mutationID = operation.mutationID else {
                    throw CrossMarketConformanceFailureV1.invalidValue
                }
                let key = "\(kind.rawValue)|\(id.uuidString.lowercased())"
                guard let semantic = semanticByKey[key] else {
                    throw CrossMarketConformanceFailureV1.invalidValue
                }
                if let prior = appliedOperationByMutationID[mutationID] {
                    let faulting = ModelCausalOperationIdentityV1(operation)
                    throw ModelExecutionFaultV1(
                        cause: .preconditionRejected,
                        fingerprint: try failureFingerprint(
                            invariant: expectedInvariant,
                            cause: .preconditionRejected,
                            faultingOperation: operation,
                            operations: operations,
                            duplicatePair: (prior, faulting),
                            duplicateMutationID: mutationID
                        )
                    )
                }
                guard (state.heads[key]?.revision ?? 0) == expected,
                      !state.deletionLedgerMutationIDs.contains(mutationID) else {
                    throw CrossMarketConformanceFailureV1.preconditionRejected
                }
                let resultDigest = try CrossMarketCanonicalV1.sha256(SemanticRevisionBasis(
                    contentSHA256: semantic.contentSHA256,
                    operationSHA256: operation.payloadSHA256, revision: resulting
                ))
                state.heads[key] = .init(kind: kind, id: id, revision: resulting,
                                         semanticSHA256: resultDigest)
                state.appliedMutationIDs.append(mutationID)
                appliedOperationByMutationID[mutationID] = .init(operation)
                state.immutableHistory.append(.init(
                    mutationID: mutationID, operationKind: operation.kind,
                    entityKey: key, resultingRevision: resulting,
                    resultSHA256: resultDigest
                ))
                state.erased = false
            case .rejectStaleRevision:
                guard let kind = operation.entityKind, let id = operation.entityID,
                      let expected = operation.expectedRevision,
                      let actual = state.heads[
                        "\(kind.rawValue)|\(id.uuidString.lowercased())"
                      ]?.revision,
                      actual != expected,
                      operation.expectedDisposition == .rejectedPrecondition else {
                    throw CrossMarketConformanceFailureV1.invariantViolated(.immutableHistory)
                }
                rejectedCount += 1
            case .canonicalRoundTrip:
                try require(operation, disposition: .accepted)
                let bytes = try boundedCanonicalData(state, bounds: bounds)
                let restored = try CrossMarketCanonicalV1.decode(ModelMachineStateV1.self, from: bytes)
                guard restored == state else {
                    throw CrossMarketConformanceFailureV1.invariantViolated(.canonicalBytesStable)
                }
                state = restored
                removedScratchBytes = max(removedScratchBytes, bytes.count)
            case .backupRestore:
                try require(operation, disposition: .accepted)
                guard scratch == nil else { throw CrossMarketConformanceFailureV1.invalidValue }
                let before = state
                scratch = try boundedCanonicalData(before, bounds: bounds)
                state = ModelMachineStateV1()
                guard let bytes = scratch else { throw CrossMarketConformanceFailureV1.invalidValue }
                state = try CrossMarketCanonicalV1.decode(ModelMachineStateV1.self, from: bytes)
                guard state == before else {
                    throw CrossMarketConformanceFailureV1.invariantViolated(.canonicalBytesStable)
                }
                removedScratchBytes = max(removedScratchBytes, bytes.count)
                scratch = nil
            case .cloneFork:
                try require(operation, disposition: .accepted)
                let source = state
                let bytes = try boundedCanonicalData(source, bounds: bounds)
                var clone = try CrossMarketCanonicalV1.decode(ModelMachineStateV1.self, from: bytes)
                clone.heads.removeAll()
                clone.projection.removeAll()
                clone.erased = true
                guard state == source, clone != source else {
                    throw CrossMarketConformanceFailureV1.invariantViolated(.immutableHistory)
                }
                removedScratchBytes = max(removedScratchBytes, bytes.count)
                state.effectReceipts.append(try CrossMarketCanonicalV1.sha256(clone))
            case .interruptBeforeEffect:
                try require(operation, disposition: .interruptedNoEffect)
                guard state.pendingEffect == nil else {
                    throw CrossMarketConformanceFailureV1.partialReceipt
                }
            case .interruptAfterEffectBeforeReceipt:
                try require(operation, disposition: .interruptedRecoverableEffect)
                guard state.pendingEffect == nil else {
                    throw CrossMarketConformanceFailureV1.partialReceipt
                }
                state.pendingEffect = .init(
                    operationOrdinal: operation.ordinal,
                    effectSHA256: try CrossMarketCanonicalV1.sha256(PendingEffectBasis(
                        caseIndex: caseIndex, operationSHA256: operation.payloadSHA256,
                        stateSHA256: CrossMarketCanonicalV1.sha256(state)
                    ))
                )
            case .replay:
                try require(operation, disposition: .idempotentReplay)
                guard let pending = state.pendingEffect else {
                    throw CrossMarketConformanceFailureV1.invariantViolated(.replayConverges)
                }
                state.effectReceipts.append(pending.effectSHA256)
                state.pendingEffect = nil
            case .rebuildProjection:
                try require(operation, disposition: .accepted)
                state.projection = state.heads.values.sorted { $0.stableKey < $1.stableKey }
                guard state.projection.count == state.heads.count else {
                    throw CrossMarketConformanceFailureV1.invariantViolated(.immutableHistory)
                }
            case .deleteErase:
                try require(operation, disposition: .accepted)
                guard state.pendingEffect == nil else {
                    throw CrossMarketConformanceFailureV1.partialReceipt
                }
                state.deletionLedgerMutationIDs.append(contentsOf: state.appliedMutationIDs)
                state.deletionLedgerMutationIDs.sort {
                    $0.rawValue.uuidString < $1.rawValue.uuidString
                }
                state.appliedMutationIDs.removeAll()
                state.heads.removeAll()
                state.immutableHistory.removeAll()
                state.projection.removeAll()
                state.effectReceipts.removeAll()
                state.erased = true
            case .verifyReleaseExclusion:
                try require(operation, disposition: .accepted)
                guard state.erased, state.heads.isEmpty, state.immutableHistory.isEmpty,
                      state.projection.isEmpty, state.appliedMutationIDs.isEmpty,
                      state.pendingEffect == nil, scratch == nil else {
                    throw CrossMarketConformanceFailureV1.invariantViolated(.releaseExcluded)
                }
                }
            } catch let fault as ModelExecutionFaultV1 {
                throw fault
            } catch let cause as CrossMarketConformanceFailureV1 {
                if cause == .limitExceeded { throw cause }
                throw ModelExecutionFaultV1(
                    cause: cause,
                    fingerprint: try failureFingerprint(
                        invariant: expectedInvariant, cause: cause,
                        faultingOperation: operation, operations: operations,
                        duplicatePair: nil, duplicateMutationID: nil
                    )
                )
            }
        }

        if state.pendingEffect != nil {
            let operation = operations[operations.count - 1]
            throw ModelExecutionFaultV1(
                cause: .partialReceipt,
                fingerprint: try failureFingerprint(
                    invariant: expectedInvariant, cause: .partialReceipt,
                    faultingOperation: operation, operations: operations,
                    duplicatePair: nil, duplicateMutationID: nil,
                    boundaryOverride: .caseFinalization
                )
            )
        }
        if scratch != nil {
            let cause = CrossMarketConformanceFailureV1.invariantViolated(.noScratchOrphan)
            let operation = operations[operations.count - 1]
            throw ModelExecutionFaultV1(
                cause: cause,
                fingerprint: try failureFingerprint(
                    invariant: expectedInvariant, cause: cause,
                    faultingOperation: operation, operations: operations,
                    duplicatePair: nil, duplicateMutationID: nil,
                    boundaryOverride: .caseFinalization
                )
            )
        }
        return ModelCaseExecutionV1(
            caseIndex: caseIndex,
            selectedOperationSHA256: try CrossMarketCanonicalV1.sha256(
                operations.map(OperationDigestBasis.init)
            ),
            finalStateSHA256: try CrossMarketCanonicalV1.sha256(state),
            semanticStateSHA256: try CrossMarketCanonicalV1.sha256(semanticState),
            rejectedPreconditions: rejectedCount,
            executedOperationCount: operations.count,
            scratchBytesRemoved: removedScratchBytes
        )
    }

    private static func minimizedCounterexample(
        semanticState: CrossMarketArchetypeStateV1,
        operations: [ModelOperationV1],
        matching fingerprint: ModelFailureFingerprintV1,
        bounds: ModelRunBoundsV1, deadlineNanoseconds: UInt64
    ) throws -> MinimizedCounterexampleV1 {
        let originalCount = operations.count
        var candidate = try renumber(operations)
        var steps = 0
        var granularity = 2
        while candidate.count > 1, steps < bounds.maximumShrinkSteps {
            try enforceDuration(deadlineNanoseconds)
            let chunkSize = max(1, (candidate.count + granularity - 1) / granularity)
            var removedFailingChunk = false
            var start = 0
            while start < candidate.count, steps < bounds.maximumShrinkSteps {
                let end = min(candidate.count, start + chunkSize)
                var trial = candidate
                trial.removeSubrange(start..<end)
                steps += 1
                if !trial.isEmpty {
                    trial = try renumber(trial)
                    let trialIdentities = trial.map(ModelCausalOperationIdentityV1.init)
                    guard fingerprint.causalOperations.allSatisfy(trialIdentities.contains) else {
                        start += chunkSize
                        continue
                    }
                    do {
                        _ = try executeCase(
                            semanticState: semanticState, operations: trial, caseIndex: 0,
                            expectedInvariant: fingerprint.invariant,
                            bounds: bounds, deadlineNanoseconds: deadlineNanoseconds
                        )
                    } catch let trialFault as ModelExecutionFaultV1
                        where trialFault.fingerprint == fingerprint {
                        candidate = trial
                        granularity = max(2, granularity - 1)
                        removedFailingChunk = true
                        break
                    } catch is ModelExecutionFaultV1 {
                        // A different failure is not a valid reduction.
                    } catch let cause as CrossMarketConformanceFailureV1 {
                        if cause == .limitExceeded { throw cause }
                    }
                }
                start += chunkSize
            }
            if !removedFailingChunk {
                if granularity >= candidate.count { break }
                granularity = min(candidate.count, granularity * 2)
            }
        }
        let reproducedFingerprint: Bool
        do {
            _ = try executeCase(
                semanticState: semanticState, operations: candidate, caseIndex: 0,
                expectedInvariant: fingerprint.invariant,
                bounds: bounds, deadlineNanoseconds: deadlineNanoseconds
            )
            reproducedFingerprint = false
        } catch let finalFault as ModelExecutionFaultV1 {
            reproducedFingerprint = finalFault.fingerprint == fingerprint
        }
        guard reproducedFingerprint else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        let result = MinimizedCounterexampleV1(
            invariant: fingerprint.invariant, originalOperationCount: originalCount,
            operations: candidate, shrinkStepCount: steps
        )
        try result.validate(bounds: bounds, preserving: fingerprint)
        return result
    }

    private static func failureFingerprint(
        invariant: ModelInvariantV1,
        cause: CrossMarketConformanceFailureV1,
        faultingOperation: ModelOperationV1,
        operations: [ModelOperationV1],
        duplicatePair: (
            ModelCausalOperationIdentityV1,
            ModelCausalOperationIdentityV1
        )?,
        duplicateMutationID: MutationIDV1?,
        boundaryOverride: ModelFaultBoundaryV1? = nil
    ) throws -> ModelFailureFingerprintV1 {
        var required: [ModelCausalOperationIdentityV1] = []
        func include(_ identity: ModelCausalOperationIdentityV1) {
            if !required.contains(identity) { required.append(identity) }
        }
        if invariant == .replayConverges {
            guard let interruption = operations.first(where: {
                      $0.kind == .interruptAfterEffectBeforeReceipt
                  }),
                  let interruptionIndex = operations.firstIndex(where: {
                      $0.kind == .interruptAfterEffectBeforeReceipt
                  }),
                  let replay = operations[operations.index(after: interruptionIndex)...]
                    .first(where: { $0.kind == .replay }) else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
            include(.init(interruption))
            include(.init(replay))
        }
        if let duplicatePair {
            include(duplicatePair.0)
            include(duplicatePair.1)
        }
        include(.init(faultingOperation))

        let operationIdentities = operations.map(ModelCausalOperationIdentityV1.init)
        let orderedCausalOperations = operationIdentities.filter(required.contains)
        return try ModelFailureFingerprintV1(
            invariant: invariant,
            faultBoundary: boundaryOverride ?? faultBoundary(for: faultingOperation.kind),
            causeCode: causeCode(for: cause),
            faultingOperation: .init(faultingOperation),
            causalOperations: orderedCausalOperations,
            duplicateMutationID: duplicateMutationID
        )
    }

    private static func faultBoundary(
        for kind: ModelOperationKindV1
    ) -> ModelFaultBoundaryV1 {
        switch kind {
        case .append, .supersede: return .entityMutation
        case .rejectStaleRevision: return .staleRevision
        case .canonicalRoundTrip: return .canonicalCodec
        case .backupRestore: return .backupRestore
        case .cloneFork: return .cloneFork
        case .interruptBeforeEffect: return .interruptionBeforeEffect
        case .interruptAfterEffectBeforeReceipt: return .interruptionAfterEffect
        case .replay: return .replay
        case .rebuildProjection: return .projectionRebuild
        case .deleteErase: return .deleteErase
        case .verifyReleaseExclusion: return .releaseExclusion
        }
    }

    private static func causeCode(
        for cause: CrossMarketConformanceFailureV1
    ) -> String {
        switch cause {
        case .invalidValue: return "INVALID_VALUE"
        case .limitExceeded: return "LIMIT_EXCEEDED"
        case .nonCanonicalOrder: return "NON_CANONICAL_ORDER"
        case .preconditionRejected: return "PRECONDITION_REJECTED"
        case let .invariantViolated(invariant):
            return "INVARIANT_VIOLATED:\(invariant.rawValue)"
        case .partialReceipt: return "PARTIAL_RECEIPT"
        case let .releaseLeak(surface): return "RELEASE_LEAK:\(surface)"
        }
    }

    private static func renumber(_ operations: [ModelOperationV1]) throws -> [ModelOperationV1] {
        try operations.enumerated().map { try $0.element.replacingOrdinal($0.offset + 1) }
    }

    private static func boundedCanonicalData<T: Encodable>(
        _ value: T, bounds: ModelRunBoundsV1
    ) throws -> Data {
        let bytes = try CrossMarketCanonicalV1.data(value)
        guard bytes.count <= bounds.maximumScratchBytes else {
            throw CrossMarketConformanceFailureV1.limitExceeded
        }
        return bytes
    }

    private static func require(
        _ operation: ModelOperationV1, disposition: ModelExpectedDispositionV1
    ) throws {
        guard operation.expectedDisposition == disposition else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    private static func enforceDuration(_ deadlineNanoseconds: UInt64) throws {
        guard DispatchTime.now().uptimeNanoseconds <= deadlineNanoseconds else {
            throw CrossMarketConformanceFailureV1.limitExceeded
        }
    }

    private struct CaseEnvelope: Codable {
        let semanticState: CrossMarketArchetypeStateV1
        let execution: ModelCaseExecutionV1
    }

    private struct SemanticRevisionBasis: Codable {
        let contentSHA256: String
        let operationSHA256: String
        let revision: UInt64
    }

    private struct PendingEffectBasis: Codable {
        let caseIndex: Int
        let operationSHA256: String
        let stateSHA256: String
    }

    private struct OperationDigestBasis: Codable {
        let ordinal: Int
        let kind: ModelOperationKindV1
        let payloadSHA256: String

        init(_ operation: ModelOperationV1) {
            ordinal = operation.ordinal
            kind = operation.kind
            payloadSHA256 = operation.payloadSHA256
        }
    }

    private struct CaseResultsBasis: Codable {
        let archetypeID: String
        let seed: UInt64
        let semanticStateSHA256: String
        let caseResultSHA256s: [String]
    }
}

enum CrossMarketCanonicalV1 {
    static let maximumCanonicalBytes = 16 * 1_024 * 1_024
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let result = try encoder.encode(value)
        guard result.count <= maximumCanonicalBytes else {
            throw CrossMarketConformanceFailureV1.limitExceeded
        }
        return result
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumCanonicalBytes else {
            throw CrossMarketConformanceFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(type, from: data)
        guard try self.data(value) == data else {
            throw CrossMarketConformanceFailureV1.nonCanonicalOrder
        }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(rawData: Data) -> String {
        SHA256.hash(data: rawData).map { String(format: "%02x", $0) }.joined()
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

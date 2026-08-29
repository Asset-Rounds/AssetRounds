import Foundation

// C43 is a static, vendor-neutral contract boundary. None of the declarations in
// this file is a workspace record, an event sink, or authority to collect data.

enum CustomerLearningContractFailureV1: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidValue
    case invalidDigest
    case nonCanonicalData
    case duplicateValue
    case arithmeticOverflow
    case sourceJoinForbidden
    case collectionForbidden
    case activationForbidden
}

private struct CustomerLearningDynamicCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

private enum CustomerLearningClosedCodingV1 {
    static func require<K: CodingKey & CaseIterable>(
        _ decoder: any Decoder,
        _ keys: K.Type
    ) throws where K.AllCases: Collection {
        let expected = Set(keys.allCases.map(\.stringValue))
        let container = try decoder.container(keyedBy: CustomerLearningDynamicCodingKeyV1.self)
        guard Set(container.allKeys.map(\.stringValue)).isSubset(of: expected) else {
            throw CustomerLearningContractFailureV1.nonCanonicalData
        }
    }
}

enum CustomerLearningCanonicalCodecV1 {
    static let maximumCanonicalByteCount = 1_048_576

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard !data.isEmpty, data.count <= maximumCanonicalByteCount else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        return data
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumCanonicalByteCount else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else {
            throw CustomerLearningContractFailureV1.nonCanonicalData
        }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        KernelCanonicalHashV1.sha256(try encode(value))
    }
}

private enum CustomerLearningValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func identifier(_ value: String, maximumBytes: Int = 160) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CustomerLearningContractFailureV1.invalidIdentifier
        }
    }

    static func text(_ value: String, maximumBytes: Int = 4_096) throws {
        guard !value.isEmpty,
              value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
    }

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
    }

    static func gitObject(_ value: String) throws {
        guard value.count == 40,
              value.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
    }

    static func instant(_ value: Date) throws {
        let milliseconds = value.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds <= Double(Int64.max) else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
    }

    static func sortedUniqueIdentifiers(
        _ values: [String],
        maximumCount: Int,
        allowEmpty: Bool = false
    ) throws -> [String] {
        guard values.count <= maximumCount, allowEmpty || !values.isEmpty else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        try values.forEach(identifier)
        let ordered = values.sorted()
        guard ordered == values, Set(values).count == values.count else {
            throw CustomerLearningContractFailureV1.duplicateValue
        }
        return values
    }

    static func uuid(_ value: UUID) throws {
        guard value != zeroUUID else { throw CustomerLearningContractFailureV1.invalidIdentifier }
    }

    static func isImmediateSuccessor(_ revision: UInt64, of predecessor: UInt64) -> Bool {
        let (expectedRevision, overflow) = predecessor.addingReportingOverflow(1)
        return !overflow && expectedRevision == revision
    }
}

enum MeasurementPurposeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case acquisitionSourceMix = "ACQUISITION_SOURCE_MIX"
    case productPageConversion = "PRODUCT_PAGE_CONVERSION"
    case firstRealJobCompletion = "FIRST_REAL_JOB_COMPLETION"
    case offlineReadyRoundCompletion = "OFFLINE_READY_ROUND_COMPLETION"
    case reportPreviewSuccess = "REPORT_PREVIEW_SUCCESS"
    case sevenDayAggregateReturn = "SEVEN_DAY_AGGREGATE_RETURN"
    case thirtyDayAggregateReturn = "THIRTY_DAY_AGGREGATE_RETURN"
    case ownerFieldResearchThemes = "OWNER_FIELD_RESEARCH_THEMES"
}

enum MeasurementSourceKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case appStoreConnectAggregate = "APP_STORE_CONNECT_AGGREGATE"
    case explicitFieldResearch = "EXPLICIT_FIELD_RESEARCH"
    case rebuildableOperationalReceiptProjection = "REBUILDABLE_OPERATIONAL_RECEIPT_PROJECTION"
    case futureConsentedProductAnalytics = "FUTURE_CONSENTED_PRODUCT_ANALYTICS"
}

enum MeasurementCollectionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case disabledNoCollection = "DISABLED_NO_COLLECTION"
}

enum CustomerLearningRequiredExclusionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case practice = "PRACTICE"
    case syntheticTestDiagnostic = "SYNTHETIC_TEST_DIAGNOSTIC"
    case customerContent = "CUSTOMER_CONTENT"
    case unsupportedDenominator = "UNSUPPORTED_DENOMINATOR"
    case silentlyInferredPeople = "SILENTLY_INFERRED_PEOPLE"
}

enum MeasurementAggregationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case providerPrivacyThresholded = "PROVIDER_PRIVACY_THRESHOLDED"
    case ownerAggregatedResearch = "OWNER_AGGREGATED_RESEARCH"
    case rebuildableSyntheticOnly = "REBUILDABLE_SYNTHETIC_ONLY"
    case futureConsentedAggregate = "FUTURE_CONSENTED_AGGREGATE"
}

enum MeasurementUserLinkageDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case forbidden = "USER_LEVEL_LINKAGE_FORBIDDEN"
}

enum MeasurementMissingDataPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unknown = "UNKNOWN"
    case suppressed = "SUPPRESSED"
}

enum MeasurementPrivacyThresholdKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case providerEnforcedUnknown = "PROVIDER_ENFORCED_UNKNOWN"
    case minimumCohort = "MINIMUM_COHORT"
}

struct MeasurementPrivacyThresholdV1: Codable, Equatable, Hashable, Sendable {
    let kind: MeasurementPrivacyThresholdKindV1
    let minimumCohortSize: UInt64?

    init(kind: MeasurementPrivacyThresholdKindV1, minimumCohortSize: UInt64? = nil) throws {
        self.kind = kind
        self.minimumCohortSize = minimumCohortSize
        try validate()
    }

    func validate() throws {
        switch kind {
        case .providerEnforcedUnknown:
            guard minimumCohortSize == nil else { throw CustomerLearningContractFailureV1.invalidValue }
        case .minimumCohort:
            guard let minimumCohortSize, minimumCohortSize > 0, minimumCohortSize <= 1_000_000 else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, minimumCohortSize }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: c.decode(MeasurementPrivacyThresholdKindV1.self, forKey: .kind),
            minimumCohortSize: c.decodeIfPresent(UInt64.self, forKey: .minimumCohortSize)
        )
    }
}

struct MeasurementRefreshLagV1: Codable, Equatable, Hashable, Sendable {
    let minimumHours: UInt32
    let maximumHours: UInt32?

    init(minimumHours: UInt32, maximumHours: UInt32?) throws {
        self.minimumHours = minimumHours
        self.maximumHours = maximumHours
        try validate()
    }

    func validate() throws {
        guard minimumHours <= 24 * 365,
              maximumHours.map({ $0 >= minimumHours && $0 <= 24 * 365 }) ?? true else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case minimumHours, maximumHours }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            minimumHours: c.decode(UInt32.self, forKey: .minimumHours),
            maximumHours: c.decodeIfPresent(UInt32.self, forKey: .maximumHours)
        )
    }
}

struct MeasurementWindowV1: Codable, Equatable, Hashable, Sendable {
    let anchorSemanticID: String
    let durationDays: UInt16
    let graceDays: UInt16

    init(anchorSemanticID: String, durationDays: UInt16, graceDays: UInt16 = 0) throws {
        self.anchorSemanticID = anchorSemanticID
        self.durationDays = durationDays
        self.graceDays = graceDays
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(anchorSemanticID)
        guard durationDays > 0, durationDays <= 3_650, graceDays <= 365 else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case anchorSemanticID, durationDays, graceDays }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            anchorSemanticID: c.decode(String.self, forKey: .anchorSemanticID),
            durationDays: c.decode(UInt16.self, forKey: .durationDays),
            graceDays: c.decode(UInt16.self, forKey: .graceDays)
        )
    }
}

struct MeasurementRationalV1: Codable, Equatable, Hashable, Sendable {
    let numerator: Int64
    let denominator: Int64

    init(numerator: Int64, denominator: Int64) throws {
        guard numerator >= 0, denominator > 0 else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let divisor = Self.greatestCommonDivisor(UInt64(numerator), UInt64(denominator))
        self.numerator = numerator / Int64(divisor)
        self.denominator = denominator / Int64(divisor)
    }

    private static func greatestCommonDivisor(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        var a = lhs
        var b = rhs
        while b != 0 { let remainder = a % b; a = b; b = remainder }
        return max(a, 1)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case numerator, denominator }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            numerator: c.decode(Int64.self, forKey: .numerator),
            denominator: c.decode(Int64.self, forKey: .denominator)
        )
    }
}

enum MeasurementFormulaV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ratio = "RATIO"
    case percentageBasisPoints = "PERCENTAGE_BASIS_POINTS"
    case count = "COUNT"
}

enum MeasurementUnknownReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case missingSourceReport = "MISSING_SOURCE_REPORT"
    case delayedSourceReport = "DELAYED_SOURCE_REPORT"
    case unsupportedDenominator = "UNSUPPORTED_DENOMINATOR"
    case ineligiblePopulation = "INELIGIBLE_POPULATION"
}

enum MeasurementSuppressionReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case privacyThreshold = "PRIVACY_THRESHOLD"
    case providerSuppressed = "PROVIDER_SUPPRESSED"
}

enum MeasurementEvaluationResultV1: Codable, Equatable, Hashable, Sendable {
    case known(MeasurementRationalV1)
    case unknown(MeasurementUnknownReasonV1)
    case suppressed(MeasurementSuppressionReasonV1)

    private enum Kind: String, Codable { case known = "KNOWN", unknown = "UNKNOWN", suppressed = "SUPPRESSED" }
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, value, unknownReason, suppressionReason }

    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .known:
            guard c.contains(.value), try c.decodeNil(forKey: .unknownReason), try c.decodeNil(forKey: .suppressionReason) else {
                throw CustomerLearningContractFailureV1.nonCanonicalData
            }
            self = .known(try c.decode(MeasurementRationalV1.self, forKey: .value))
        case .unknown:
            guard try c.decodeNil(forKey: .value), c.contains(.unknownReason), try c.decodeNil(forKey: .suppressionReason) else {
                throw CustomerLearningContractFailureV1.nonCanonicalData
            }
            self = .unknown(try c.decode(MeasurementUnknownReasonV1.self, forKey: .unknownReason))
        case .suppressed:
            guard try c.decodeNil(forKey: .value), try c.decodeNil(forKey: .unknownReason), c.contains(.suppressionReason) else {
                throw CustomerLearningContractFailureV1.nonCanonicalData
            }
            self = .suppressed(try c.decode(MeasurementSuppressionReasonV1.self, forKey: .suppressionReason))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .known(let value):
            try c.encode(Kind.known, forKey: .kind); try c.encode(value, forKey: .value)
            try c.encodeNil(forKey: .unknownReason); try c.encodeNil(forKey: .suppressionReason)
        case .unknown(let reason):
            try c.encode(Kind.unknown, forKey: .kind); try c.encodeNil(forKey: .value)
            try c.encode(reason, forKey: .unknownReason); try c.encodeNil(forKey: .suppressionReason)
        case .suppressed(let reason):
            try c.encode(Kind.suppressed, forKey: .kind); try c.encodeNil(forKey: .value)
            try c.encodeNil(forKey: .unknownReason); try c.encode(reason, forKey: .suppressionReason)
        }
    }
}

struct CustomerLearningQuestionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let questionID: String
    let revision: UInt64
    let questionSHA256: String

    init(questionID: String, revision: UInt64, questionSHA256: String) throws {
        self.questionID = questionID; self.revision = revision; self.questionSHA256 = questionSHA256
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(questionID)
        guard revision > 0 else { throw CustomerLearningContractFailureV1.invalidValue }
        try CustomerLearningValidationV1.digest(questionSHA256)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case questionID, revision, questionSHA256 }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questionID = try c.decode(String.self, forKey: .questionID)
        revision = try c.decode(UInt64.self, forKey: .revision)
        questionSHA256 = try c.decode(String.self, forKey: .questionSHA256)
        try validate()
    }
}

struct AcquisitionSourceVocabularyReferenceV1: Codable, Equatable, Hashable, Sendable {
    let vocabularyID: UUID
    let revision: UInt64
    let vocabularySHA256: String

    init(vocabularyID: UUID, revision: UInt64, vocabularySHA256: String) throws {
        self.vocabularyID = vocabularyID; self.revision = revision; self.vocabularySHA256 = vocabularySHA256
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(vocabularyID)
        guard revision > 0 else { throw CustomerLearningContractFailureV1.invalidValue }
        try CustomerLearningValidationV1.digest(vocabularySHA256)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case vocabularyID, revision, vocabularySHA256 }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vocabularyID = try c.decode(UUID.self, forKey: .vocabularyID)
        revision = try c.decode(UInt64.self, forKey: .revision)
        vocabularySHA256 = try c.decode(String.self, forKey: .vocabularySHA256)
        try validate()
    }
}

struct MeasurementSourceReferenceV1: Codable, Equatable, Hashable, Sendable {
    let sourceID: UUID
    let kind: MeasurementSourceKindV1
    let revision: UInt64
    let sourceSHA256: String

    init(sourceID: UUID, kind: MeasurementSourceKindV1, revision: UInt64, sourceSHA256: String) throws {
        self.sourceID = sourceID; self.kind = kind; self.revision = revision; self.sourceSHA256 = sourceSHA256
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(sourceID)
        guard revision > 0 else { throw CustomerLearningContractFailureV1.invalidValue }
        try CustomerLearningValidationV1.digest(sourceSHA256)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case sourceID, kind, revision, sourceSHA256 }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try c.decode(UUID.self, forKey: .sourceID)
        kind = try c.decode(MeasurementSourceKindV1.self, forKey: .kind)
        revision = try c.decode(UInt64.self, forKey: .revision)
        sourceSHA256 = try c.decode(String.self, forKey: .sourceSHA256)
        try validate()
    }
}

struct AcquisitionSourceDefinitionV1: Codable, Equatable, Hashable, Sendable {
    let semanticID: String
    let ownerReadableName: String
    let definitionSHA256: String

    init(semanticID: String, ownerReadableName: String) throws {
        self.semanticID = semanticID
        self.ownerReadableName = ownerReadableName
        definitionSHA256 = try CustomerLearningCanonicalCodecV1.sha256(Basis(
            semanticID: semanticID, ownerReadableName: ownerReadableName
        ))
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(semanticID)
        try CustomerLearningValidationV1.text(ownerReadableName, maximumBytes: 240)
        guard definitionSHA256 == (try CustomerLearningCanonicalCodecV1.sha256(Basis(
            semanticID: semanticID, ownerReadableName: ownerReadableName
        ))) else { throw CustomerLearningContractFailureV1.invalidDigest }
    }

    private struct Basis: Codable { let semanticID: String; let ownerReadableName: String }
    private enum CodingKeys: String, CodingKey, CaseIterable { case semanticID, ownerReadableName, definitionSHA256 }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try Self(
            semanticID: c.decode(String.self, forKey: .semanticID),
            ownerReadableName: c.decode(String.self, forKey: .ownerReadableName)
        )
        guard value.definitionSHA256 == c.decode(String.self, forKey: .definitionSHA256) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct AcquisitionSourceVocabularyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let vocabularyID: UUID
    let revision: UInt64
    let definitions: [AcquisitionSourceDefinitionV1]
    let supersedes: AcquisitionSourceVocabularyReferenceV1?
    let vocabularySHA256: String

    init(
        vocabularyID: UUID,
        revision: UInt64,
        definitions: [AcquisitionSourceDefinitionV1],
        supersedes: AcquisitionSourceVocabularyReferenceV1? = nil
    ) throws {
        let ordered = definitions.sorted { $0.semanticID < $1.semanticID }
        schemaVersion = Self.schemaVersion
        self.vocabularyID = vocabularyID
        self.revision = revision
        self.definitions = ordered
        self.supersedes = supersedes
        vocabularySHA256 = try CustomerLearningCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            vocabularyID: vocabularyID,
            revision: revision,
            definitions: ordered,
            supersedes: supersedes
        ))
        try validate()
    }

    var reference: AcquisitionSourceVocabularyReferenceV1 {
        get throws { try .init(vocabularyID: vocabularyID, revision: revision, vocabularySHA256: vocabularySHA256) }
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(vocabularyID)
        guard schemaVersion == Self.schemaVersion,
              revision > 0,
              !definitions.isEmpty,
              definitions.count <= 128,
              definitions == definitions.sorted(by: { $0.semanticID < $1.semanticID }),
              Set(definitions.map(\.semanticID)).count == definitions.count else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        try definitions.forEach { try $0.validate() }
        if revision == 1 {
            guard supersedes == nil else { throw CustomerLearningContractFailureV1.invalidValue }
        } else {
            guard let supersedes,
                  supersedes.vocabularyID == vocabularyID,
                  CustomerLearningValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            try supersedes.validate()
        }
        guard vocabularySHA256 == (try CustomerLearningCanonicalCodecV1.sha256(Basis(
            schemaVersion: schemaVersion,
            vocabularyID: vocabularyID,
            revision: revision,
            definitions: definitions,
            supersedes: supersedes
        ))) else { throw CustomerLearningContractFailureV1.invalidDigest }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let vocabularyID: UUID
        let revision: UInt64
        let definitions: [AcquisitionSourceDefinitionV1]
        let supersedes: AcquisitionSourceVocabularyReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, vocabularyID, revision, definitions, supersedes, vocabularySHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let value = try Self(
            vocabularyID: c.decode(UUID.self, forKey: .vocabularyID),
            revision: c.decode(UInt64.self, forKey: .revision),
            definitions: c.decode([AcquisitionSourceDefinitionV1].self, forKey: .definitions),
            supersedes: c.decodeIfPresent(AcquisitionSourceVocabularyReferenceV1.self, forKey: .supersedes)
        )
        guard value.vocabularySHA256 == c.decode(String.self, forKey: .vocabularySHA256) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct MeasurementSourceDescriptorV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sourceID: UUID
    let kind: MeasurementSourceKindV1
    let revision: UInt64
    let provenance: String
    let aggregation: MeasurementAggregationV1
    let privacyThreshold: MeasurementPrivacyThresholdV1
    let eligibility: String
    let refreshLag: MeasurementRefreshLagV1
    let missingDataPolicy: MeasurementMissingDataPolicyV1
    let userLinkage: MeasurementUserLinkageDispositionV1
    let acquisitionVocabulary: AcquisitionSourceVocabularyReferenceV1?
    let supersedes: MeasurementSourceReferenceV1?
    let sourceSHA256: String

    init(
        sourceID: UUID,
        kind: MeasurementSourceKindV1,
        revision: UInt64,
        provenance: String,
        aggregation: MeasurementAggregationV1,
        privacyThreshold: MeasurementPrivacyThresholdV1,
        eligibility: String,
        refreshLag: MeasurementRefreshLagV1,
        missingDataPolicy: MeasurementMissingDataPolicyV1,
        userLinkage: MeasurementUserLinkageDispositionV1 = .forbidden,
        acquisitionVocabulary: AcquisitionSourceVocabularyReferenceV1? = nil,
        supersedes: MeasurementSourceReferenceV1? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        self.sourceID = sourceID; self.kind = kind; self.revision = revision
        self.provenance = provenance; self.aggregation = aggregation
        self.privacyThreshold = privacyThreshold; self.eligibility = eligibility
        self.refreshLag = refreshLag; self.missingDataPolicy = missingDataPolicy
        self.userLinkage = userLinkage; self.acquisitionVocabulary = acquisitionVocabulary
        self.supersedes = supersedes
        sourceSHA256 = try CustomerLearningCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            sourceID: sourceID,
            kind: kind,
            revision: revision,
            provenance: provenance,
            aggregation: aggregation,
            privacyThreshold: privacyThreshold,
            eligibility: eligibility,
            refreshLag: refreshLag,
            missingDataPolicy: missingDataPolicy,
            userLinkage: userLinkage,
            acquisitionVocabulary: acquisitionVocabulary,
            supersedes: supersedes
        ))
        try validate()
    }

    var reference: MeasurementSourceReferenceV1 {
        get throws { try .init(sourceID: sourceID, kind: kind, revision: revision, sourceSHA256: sourceSHA256) }
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(sourceID)
        try CustomerLearningValidationV1.text(provenance)
        try CustomerLearningValidationV1.text(eligibility)
        try privacyThreshold.validate(); try refreshLag.validate()
        guard schemaVersion == Self.schemaVersion, revision > 0, userLinkage == .forbidden else {
            throw CustomerLearningContractFailureV1.sourceJoinForbidden
        }
        switch kind {
        case .appStoreConnectAggregate:
            guard aggregation == .providerPrivacyThresholded, acquisitionVocabulary != nil else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
        case .explicitFieldResearch:
            guard aggregation == .ownerAggregatedResearch, acquisitionVocabulary == nil else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
        case .rebuildableOperationalReceiptProjection:
            guard aggregation == .rebuildableSyntheticOnly, acquisitionVocabulary == nil else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
        case .futureConsentedProductAnalytics:
            guard aggregation == .futureConsentedAggregate, acquisitionVocabulary == nil else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
        }
        try acquisitionVocabulary?.validate()
        if revision == 1 {
            guard supersedes == nil else { throw CustomerLearningContractFailureV1.invalidValue }
        } else {
            guard let supersedes,
                  supersedes.sourceID == sourceID,
                  supersedes.kind == kind,
                  CustomerLearningValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            try supersedes.validate()
        }
        guard sourceSHA256 == (try CustomerLearningCanonicalCodecV1.sha256(basis)) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, sourceID: sourceID, kind: kind, revision: revision,
        provenance: provenance, aggregation: aggregation, privacyThreshold: privacyThreshold,
        eligibility: eligibility, refreshLag: refreshLag, missingDataPolicy: missingDataPolicy,
        userLinkage: userLinkage, acquisitionVocabulary: acquisitionVocabulary, supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let sourceID: UUID; let kind: MeasurementSourceKindV1; let revision: UInt64
        let provenance: String; let aggregation: MeasurementAggregationV1
        let privacyThreshold: MeasurementPrivacyThresholdV1; let eligibility: String
        let refreshLag: MeasurementRefreshLagV1; let missingDataPolicy: MeasurementMissingDataPolicyV1
        let userLinkage: MeasurementUserLinkageDispositionV1
        let acquisitionVocabulary: AcquisitionSourceVocabularyReferenceV1?
        let supersedes: MeasurementSourceReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sourceID, kind, revision, provenance, aggregation, privacyThreshold, eligibility
        case refreshLag, missingDataPolicy, userLinkage, acquisitionVocabulary, supersedes, sourceSHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let value = try Self(
            sourceID: c.decode(UUID.self, forKey: .sourceID),
            kind: c.decode(MeasurementSourceKindV1.self, forKey: .kind),
            revision: c.decode(UInt64.self, forKey: .revision),
            provenance: c.decode(String.self, forKey: .provenance),
            aggregation: c.decode(MeasurementAggregationV1.self, forKey: .aggregation),
            privacyThreshold: c.decode(MeasurementPrivacyThresholdV1.self, forKey: .privacyThreshold),
            eligibility: c.decode(String.self, forKey: .eligibility),
            refreshLag: c.decode(MeasurementRefreshLagV1.self, forKey: .refreshLag),
            missingDataPolicy: c.decode(MeasurementMissingDataPolicyV1.self, forKey: .missingDataPolicy),
            userLinkage: c.decode(MeasurementUserLinkageDispositionV1.self, forKey: .userLinkage),
            acquisitionVocabulary: c.decodeIfPresent(AcquisitionSourceVocabularyReferenceV1.self, forKey: .acquisitionVocabulary),
            supersedes: c.decodeIfPresent(MeasurementSourceReferenceV1.self, forKey: .supersedes)
        )
        guard value.sourceSHA256 == c.decode(String.self, forKey: .sourceSHA256) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct CustomerLearningQuestionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let questionID: String
    let revision: UInt64
    let purpose: MeasurementPurposeV1
    let decisionSemanticID: String
    let ownerPrompt: String
    let exclusions: [CustomerLearningRequiredExclusionV1]
    let supersedes: CustomerLearningQuestionReferenceV1?
    let questionSHA256: String

    init(
        questionID: String,
        revision: UInt64,
        purpose: MeasurementPurposeV1,
        decisionSemanticID: String,
        ownerPrompt: String,
        exclusions: [CustomerLearningRequiredExclusionV1] = CustomerLearningRequiredExclusionV1.allCases,
        supersedes: CustomerLearningQuestionReferenceV1? = nil
    ) throws {
        let orderedExclusions = exclusions.sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion
        self.questionID = questionID; self.revision = revision; self.purpose = purpose
        self.decisionSemanticID = decisionSemanticID; self.ownerPrompt = ownerPrompt
        self.exclusions = orderedExclusions; self.supersedes = supersedes
        questionSHA256 = try CustomerLearningCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            questionID: questionID,
            revision: revision,
            purpose: purpose,
            decisionSemanticID: decisionSemanticID,
            ownerPrompt: ownerPrompt,
            exclusions: orderedExclusions,
            supersedes: supersedes
        ))
        try validate()
    }

    var reference: CustomerLearningQuestionReferenceV1 {
        get throws { try .init(questionID: questionID, revision: revision, questionSHA256: questionSHA256) }
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(questionID)
        try CustomerLearningValidationV1.identifier(decisionSemanticID)
        try CustomerLearningValidationV1.text(ownerPrompt)
        guard schemaVersion == Self.schemaVersion,
              revision > 0,
              exclusions == exclusions.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(exclusions) == Set(CustomerLearningRequiredExclusionV1.allCases) else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        if revision == 1 {
            guard supersedes == nil else { throw CustomerLearningContractFailureV1.invalidValue }
        } else {
            guard let supersedes,
                  supersedes.questionID == questionID,
                  CustomerLearningValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            try supersedes.validate()
        }
        guard questionSHA256 == (try CustomerLearningCanonicalCodecV1.sha256(basis)) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, questionID: questionID, revision: revision, purpose: purpose,
        decisionSemanticID: decisionSemanticID, ownerPrompt: ownerPrompt, exclusions: exclusions,
        supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let questionID: String; let revision: UInt64; let purpose: MeasurementPurposeV1
        let decisionSemanticID: String; let ownerPrompt: String
        let exclusions: [CustomerLearningRequiredExclusionV1]; let supersedes: CustomerLearningQuestionReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, questionID, revision, purpose, decisionSemanticID, ownerPrompt, exclusions, supersedes
        case questionSHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let value = try Self(
            questionID: c.decode(String.self, forKey: .questionID),
            revision: c.decode(UInt64.self, forKey: .revision),
            purpose: c.decode(MeasurementPurposeV1.self, forKey: .purpose),
            decisionSemanticID: c.decode(String.self, forKey: .decisionSemanticID),
            ownerPrompt: c.decode(String.self, forKey: .ownerPrompt),
            exclusions: c.decode([CustomerLearningRequiredExclusionV1].self, forKey: .exclusions),
            supersedes: c.decodeIfPresent(CustomerLearningQuestionReferenceV1.self, forKey: .supersedes)
        )
        guard value.questionSHA256 == c.decode(String.self, forKey: .questionSHA256) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
        self = value
    }
}

enum MeasurementUnitV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ratio = "RATIO"
    case basisPoints = "BASIS_POINTS"
    case count = "COUNT"
}

struct CustomerLearningMetricReferenceV1: Codable, Equatable, Hashable, Sendable {
    let metricID: String
    let revision: UInt64
    let metricSHA256: String

    init(metricID: String, revision: UInt64, metricSHA256: String) throws {
        self.metricID = metricID; self.revision = revision; self.metricSHA256 = metricSHA256
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(metricID)
        guard revision > 0 else { throw CustomerLearningContractFailureV1.invalidValue }
        try CustomerLearningValidationV1.digest(metricSHA256)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case metricID, revision, metricSHA256 }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            metricID: c.decode(String.self, forKey: .metricID),
            revision: c.decode(UInt64.self, forKey: .revision),
            metricSHA256: c.decode(String.self, forKey: .metricSHA256)
        )
    }
}

struct CustomerLearningMetricDefinitionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let metricID: String
    let revision: UInt64
    let question: CustomerLearningQuestionReferenceV1
    let decisionSemanticID: String
    let numeratorSemanticOutcomeID: String
    let denominatorSemanticPopulationID: String
    let eligibilitySemanticIDs: [String]
    let exclusions: [CustomerLearningRequiredExclusionV1]
    let observationWindow: MeasurementWindowV1
    let attributionWindow: MeasurementWindowV1
    let source: MeasurementSourceReferenceV1
    let formula: MeasurementFormulaV1
    let unit: MeasurementUnitV1
    let privacyThreshold: MeasurementPrivacyThresholdV1
    let missingDataPolicy: MeasurementMissingDataPolicyV1
    let noncausalInterpretation: String
    let supersedes: CustomerLearningMetricReferenceV1?
    let metricSHA256: String

    init(
        metricID: String,
        revision: UInt64,
        question: CustomerLearningQuestionReferenceV1,
        decisionSemanticID: String,
        numeratorSemanticOutcomeID: String,
        denominatorSemanticPopulationID: String,
        eligibilitySemanticIDs: [String],
        exclusions: [CustomerLearningRequiredExclusionV1] = CustomerLearningRequiredExclusionV1.allCases,
        observationWindow: MeasurementWindowV1,
        attributionWindow: MeasurementWindowV1,
        source: MeasurementSourceReferenceV1,
        formula: MeasurementFormulaV1,
        unit: MeasurementUnitV1,
        privacyThreshold: MeasurementPrivacyThresholdV1,
        missingDataPolicy: MeasurementMissingDataPolicyV1,
        noncausalInterpretation: String,
        supersedes: CustomerLearningMetricReferenceV1? = nil
    ) throws {
        let orderedEligibilitySemanticIDs = eligibilitySemanticIDs.sorted()
        let orderedExclusions = exclusions.sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion
        self.metricID = metricID; self.revision = revision; self.question = question
        self.decisionSemanticID = decisionSemanticID
        self.numeratorSemanticOutcomeID = numeratorSemanticOutcomeID
        self.denominatorSemanticPopulationID = denominatorSemanticPopulationID
        self.eligibilitySemanticIDs = orderedEligibilitySemanticIDs
        self.exclusions = orderedExclusions
        self.observationWindow = observationWindow; self.attributionWindow = attributionWindow
        self.source = source; self.formula = formula; self.unit = unit
        self.privacyThreshold = privacyThreshold; self.missingDataPolicy = missingDataPolicy
        self.noncausalInterpretation = noncausalInterpretation
        self.supersedes = supersedes
        metricSHA256 = try CustomerLearningCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            metricID: metricID,
            revision: revision,
            question: question,
            decisionSemanticID: decisionSemanticID,
            numeratorSemanticOutcomeID: numeratorSemanticOutcomeID,
            denominatorSemanticPopulationID: denominatorSemanticPopulationID,
            eligibilitySemanticIDs: orderedEligibilitySemanticIDs,
            exclusions: orderedExclusions,
            observationWindow: observationWindow,
            attributionWindow: attributionWindow,
            source: source,
            formula: formula,
            unit: unit,
            privacyThreshold: privacyThreshold,
            missingDataPolicy: missingDataPolicy,
            noncausalInterpretation: noncausalInterpretation,
            supersedes: supersedes
        ))
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(metricID)
        try question.validate(); try CustomerLearningValidationV1.identifier(decisionSemanticID)
        try CustomerLearningValidationV1.identifier(numeratorSemanticOutcomeID)
        try CustomerLearningValidationV1.identifier(denominatorSemanticPopulationID)
        _ = try CustomerLearningValidationV1.sortedUniqueIdentifiers(
            eligibilitySemanticIDs, maximumCount: 64
        )
        try observationWindow.validate(); try attributionWindow.validate(); try source.validate()
        try privacyThreshold.validate()
        try CustomerLearningValidationV1.text(noncausalInterpretation)
        try supersedes?.validate()
        guard schemaVersion == Self.schemaVersion,
              revision > 0,
              exclusions == exclusions.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(exclusions) == Set(CustomerLearningRequiredExclusionV1.allCases),
              (revision == 1) == (supersedes == nil),
              Self.unit(for: formula) == unit,
              metricSHA256 == (try CustomerLearningCanonicalCodecV1.sha256(basis)) else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        if let supersedes {
            guard supersedes.metricID == metricID,
                  CustomerLearningValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
        }
    }

    var reference: CustomerLearningMetricReferenceV1 {
        get throws { try .init(metricID: metricID, revision: revision, metricSHA256: metricSHA256) }
    }

    private static func unit(for formula: MeasurementFormulaV1) -> MeasurementUnitV1 {
        switch formula { case .ratio: return .ratio; case .percentageBasisPoints: return .basisPoints; case .count: return .count }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, metricID: metricID, revision: revision, question: question,
        decisionSemanticID: decisionSemanticID, numeratorSemanticOutcomeID: numeratorSemanticOutcomeID,
        denominatorSemanticPopulationID: denominatorSemanticPopulationID,
        eligibilitySemanticIDs: eligibilitySemanticIDs, exclusions: exclusions,
        observationWindow: observationWindow, attributionWindow: attributionWindow, source: source,
        formula: formula, unit: unit, privacyThreshold: privacyThreshold,
        missingDataPolicy: missingDataPolicy, noncausalInterpretation: noncausalInterpretation,
        supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let metricID: String; let revision: UInt64
        let question: CustomerLearningQuestionReferenceV1; let decisionSemanticID: String
        let numeratorSemanticOutcomeID: String; let denominatorSemanticPopulationID: String
        let eligibilitySemanticIDs: [String]; let exclusions: [CustomerLearningRequiredExclusionV1]
        let observationWindow: MeasurementWindowV1; let attributionWindow: MeasurementWindowV1
        let source: MeasurementSourceReferenceV1; let formula: MeasurementFormulaV1; let unit: MeasurementUnitV1
        let privacyThreshold: MeasurementPrivacyThresholdV1; let missingDataPolicy: MeasurementMissingDataPolicyV1
        let noncausalInterpretation: String; let supersedes: CustomerLearningMetricReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, metricID, revision, question, decisionSemanticID, numeratorSemanticOutcomeID
        case denominatorSemanticPopulationID, eligibilitySemanticIDs, exclusions, observationWindow
        case attributionWindow, source, formula, unit, privacyThreshold, missingDataPolicy
        case noncausalInterpretation, supersedes, metricSHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let value = try Self(
            metricID: c.decode(String.self, forKey: .metricID),
            revision: c.decode(UInt64.self, forKey: .revision),
            question: c.decode(CustomerLearningQuestionReferenceV1.self, forKey: .question),
            decisionSemanticID: c.decode(String.self, forKey: .decisionSemanticID),
            numeratorSemanticOutcomeID: c.decode(String.self, forKey: .numeratorSemanticOutcomeID),
            denominatorSemanticPopulationID: c.decode(String.self, forKey: .denominatorSemanticPopulationID),
            eligibilitySemanticIDs: c.decode([String].self, forKey: .eligibilitySemanticIDs),
            exclusions: c.decode([CustomerLearningRequiredExclusionV1].self, forKey: .exclusions),
            observationWindow: c.decode(MeasurementWindowV1.self, forKey: .observationWindow),
            attributionWindow: c.decode(MeasurementWindowV1.self, forKey: .attributionWindow),
            source: c.decode(MeasurementSourceReferenceV1.self, forKey: .source),
            formula: c.decode(MeasurementFormulaV1.self, forKey: .formula),
            unit: c.decode(MeasurementUnitV1.self, forKey: .unit),
            privacyThreshold: c.decode(MeasurementPrivacyThresholdV1.self, forKey: .privacyThreshold),
            missingDataPolicy: c.decode(MeasurementMissingDataPolicyV1.self, forKey: .missingDataPolicy),
            noncausalInterpretation: c.decode(String.self, forKey: .noncausalInterpretation),
            supersedes: c.decodeIfPresent(CustomerLearningMetricReferenceV1.self, forKey: .supersedes)
        )
        guard value.metricSHA256 == c.decode(String.self, forKey: .metricSHA256) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct CustomerLearningCatalogReferenceV1: Codable, Equatable, Hashable, Sendable {
    let catalogID: UUID
    let revision: UInt64
    let catalogSHA256: String
    let collectionDisposition: MeasurementCollectionDispositionV1

    init(
        catalogID: UUID,
        revision: UInt64,
        catalogSHA256: String,
        collectionDisposition: MeasurementCollectionDispositionV1 = .disabledNoCollection
    ) throws {
        self.catalogID = catalogID; self.revision = revision; self.catalogSHA256 = catalogSHA256
        self.collectionDisposition = collectionDisposition
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(catalogID)
        guard revision > 0, collectionDisposition == .disabledNoCollection else {
            throw CustomerLearningContractFailureV1.collectionForbidden
        }
        try CustomerLearningValidationV1.digest(catalogSHA256)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case catalogID, revision, catalogSHA256, collectionDisposition
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            catalogID: c.decode(UUID.self, forKey: .catalogID),
            revision: c.decode(UInt64.self, forKey: .revision),
            catalogSHA256: c.decode(String.self, forKey: .catalogSHA256),
            collectionDisposition: c.decode(MeasurementCollectionDispositionV1.self, forKey: .collectionDisposition)
        )
    }
}

enum CustomerLearningInitialCatalogV1 {
    static let acquisitionSourceMixQuestionID = "ACQUISITION_SOURCE_MIX"
    static let productPageConversionQuestionID = "PRODUCT_PAGE_CONVERSION"
    static let firstRealJobCompletionQuestionID = "FIRST_REAL_JOB_COMPLETION"
    static let offlineReadyRoundCompletionQuestionID = "OFFLINE_READY_ROUND_COMPLETION"
    static let reportPreviewSuccessQuestionID = "REPORT_PREVIEW_SUCCESS"
    static let sevenDayReturnQuestionID = "SEVEN_DAY_RETURN"
    static let thirtyDayReturnQuestionID = "THIRTY_DAY_RETURN"
    static let ownerFieldResearchThemesQuestionID = "OWNER_FIELD_RESEARCH_THEMES"

    static let requiredQuestionIDs = [
        acquisitionSourceMixQuestionID, firstRealJobCompletionQuestionID,
        offlineReadyRoundCompletionQuestionID, ownerFieldResearchThemesQuestionID,
        productPageConversionQuestionID, reportPreviewSuccessQuestionID,
        sevenDayReturnQuestionID, thirtyDayReturnQuestionID
    ].sorted()

    static func expectedPurpose(for questionID: String) -> MeasurementPurposeV1? {
        switch questionID {
        case acquisitionSourceMixQuestionID: return .acquisitionSourceMix
        case productPageConversionQuestionID: return .productPageConversion
        case firstRealJobCompletionQuestionID: return .firstRealJobCompletion
        case offlineReadyRoundCompletionQuestionID: return .offlineReadyRoundCompletion
        case reportPreviewSuccessQuestionID: return .reportPreviewSuccess
        case sevenDayReturnQuestionID: return .sevenDayAggregateReturn
        case thirtyDayReturnQuestionID: return .thirtyDayAggregateReturn
        case ownerFieldResearchThemesQuestionID: return .ownerFieldResearchThemes
        default: return nil
        }
    }

    static func expectedSourceKind(for questionID: String) -> MeasurementSourceKindV1? {
        switch questionID {
        case acquisitionSourceMixQuestionID, productPageConversionQuestionID:
            return .appStoreConnectAggregate
        case ownerFieldResearchThemesQuestionID:
            return .explicitFieldResearch
        case firstRealJobCompletionQuestionID, offlineReadyRoundCompletionQuestionID,
             reportPreviewSuccessQuestionID:
            return .rebuildableOperationalReceiptProjection
        case sevenDayReturnQuestionID, thirtyDayReturnQuestionID:
            return .futureConsentedProductAnalytics
        default:
            return nil
        }
    }
}

struct CustomerLearningCatalogReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let catalogID: UUID
    let revision: UInt64
    let acquisitionVocabulary: AcquisitionSourceVocabularyV1
    let questions: [CustomerLearningQuestionV1]
    let metrics: [CustomerLearningMetricDefinitionV1]
    let sources: [MeasurementSourceDescriptorV1]
    let collectionDisposition: MeasurementCollectionDispositionV1
    let releasedAt: Date
    let supersedes: CustomerLearningCatalogReferenceV1?
    let catalogSHA256: String

    init(
        catalogID: UUID,
        revision: UInt64,
        acquisitionVocabulary: AcquisitionSourceVocabularyV1,
        questions: [CustomerLearningQuestionV1],
        metrics: [CustomerLearningMetricDefinitionV1],
        sources: [MeasurementSourceDescriptorV1],
        collectionDisposition: MeasurementCollectionDispositionV1 = .disabledNoCollection,
        releasedAt: Date,
        supersedes: CustomerLearningCatalogReferenceV1? = nil
    ) throws {
        let orderedQuestions = questions.sorted { $0.questionID < $1.questionID }
        let orderedMetrics = metrics.sorted { $0.metricID < $1.metricID }
        let orderedSources = sources.sorted { $0.kind.rawValue < $1.kind.rawValue }
        schemaVersion = Self.schemaVersion
        self.catalogID = catalogID; self.revision = revision
        self.acquisitionVocabulary = acquisitionVocabulary
        self.questions = orderedQuestions
        self.metrics = orderedMetrics
        self.sources = orderedSources
        self.collectionDisposition = collectionDisposition; self.releasedAt = releasedAt
        self.supersedes = supersedes
        catalogSHA256 = try CustomerLearningCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            catalogID: catalogID,
            revision: revision,
            acquisitionVocabulary: acquisitionVocabulary,
            questions: orderedQuestions,
            metrics: orderedMetrics,
            sources: orderedSources,
            collectionDisposition: collectionDisposition,
            releasedAt: releasedAt,
            supersedes: supersedes
        ))
        try validate()
    }

    var reference: CustomerLearningCatalogReferenceV1 {
        get throws { try .init(
            catalogID: catalogID,
            revision: revision,
            catalogSHA256: catalogSHA256,
            collectionDisposition: collectionDisposition
        ) }
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(catalogID); try CustomerLearningValidationV1.instant(releasedAt)
        try acquisitionVocabulary.validate(); try questions.forEach { try $0.validate() }
        try metrics.forEach { try $0.validate() }; try sources.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              revision > 0,
              collectionDisposition == .disabledNoCollection,
              questions.count == CustomerLearningInitialCatalogV1.requiredQuestionIDs.count,
              metrics.count == CustomerLearningInitialCatalogV1.requiredQuestionIDs.count,
              sources.count == MeasurementSourceKindV1.allCases.count,
              questions == questions.sorted(by: { $0.questionID < $1.questionID }),
              metrics == metrics.sorted(by: { $0.metricID < $1.metricID }),
              sources == sources.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }),
              Set(questions.map(\.questionID)).count == questions.count,
              Set(metrics.map(\.metricID)).count == metrics.count,
              Set(questions.map(\.questionID)) == Set(CustomerLearningInitialCatalogV1.requiredQuestionIDs),
              Set(metrics.map(\.question.questionID)) == Set(CustomerLearningInitialCatalogV1.requiredQuestionIDs),
              Set(sources.map(\.kind)) == Set(MeasurementSourceKindV1.allCases),
              Set(sources.map(\.sourceID)).count == sources.count else {
            throw CustomerLearningContractFailureV1.collectionForbidden
        }
        let questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.questionID, $0) })
        for requiredID in CustomerLearningInitialCatalogV1.requiredQuestionIDs {
            guard let question = questionsByID[requiredID],
                  question.purpose == CustomerLearningInitialCatalogV1.expectedPurpose(for: requiredID) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
        }
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.sourceID, $0) })
        let vocabularyReference = try acquisitionVocabulary.reference
        for source in sources {
            if source.kind == .appStoreConnectAggregate {
                guard source.acquisitionVocabulary == vocabularyReference else {
                    throw CustomerLearningContractFailureV1.invalidValue
                }
            }
        }
        for metric in metrics {
            guard let question = questionsByID[metric.question.questionID],
                  (try question.reference) == metric.question,
                  question.decisionSemanticID == metric.decisionSemanticID,
                  let source = sourcesByID[metric.source.sourceID],
                  (try source.reference) == metric.source,
                  source.privacyThreshold == metric.privacyThreshold,
                  source.missingDataPolicy == metric.missingDataPolicy,
                  let expectedSourceKind = CustomerLearningInitialCatalogV1.expectedSourceKind(
                    for: question.questionID
                  ),
                  expectedSourceKind == source.kind else {
                throw CustomerLearningContractFailureV1.sourceJoinForbidden
            }
        }
        if revision == 1 {
            guard supersedes == nil else { throw CustomerLearningContractFailureV1.invalidValue }
        } else {
            guard let supersedes,
                  supersedes.catalogID == catalogID,
                  CustomerLearningValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            try supersedes.validate()
        }
        guard catalogSHA256 == (try CustomerLearningCanonicalCodecV1.sha256(basis)) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, catalogID: catalogID, revision: revision,
        acquisitionVocabulary: acquisitionVocabulary, questions: questions, metrics: metrics,
        sources: sources, collectionDisposition: collectionDisposition, releasedAt: releasedAt,
        supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let catalogID: UUID; let revision: UInt64
        let acquisitionVocabulary: AcquisitionSourceVocabularyV1
        let questions: [CustomerLearningQuestionV1]; let metrics: [CustomerLearningMetricDefinitionV1]
        let sources: [MeasurementSourceDescriptorV1]
        let collectionDisposition: MeasurementCollectionDispositionV1; let releasedAt: Date
        let supersedes: CustomerLearningCatalogReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, catalogID, revision, acquisitionVocabulary, questions, metrics, sources
        case collectionDisposition, releasedAt, supersedes, catalogSHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let value = try Self(
            catalogID: c.decode(UUID.self, forKey: .catalogID),
            revision: c.decode(UInt64.self, forKey: .revision),
            acquisitionVocabulary: c.decode(AcquisitionSourceVocabularyV1.self, forKey: .acquisitionVocabulary),
            questions: c.decode([CustomerLearningQuestionV1].self, forKey: .questions),
            metrics: c.decode([CustomerLearningMetricDefinitionV1].self, forKey: .metrics),
            sources: c.decode([MeasurementSourceDescriptorV1].self, forKey: .sources),
            collectionDisposition: c.decode(MeasurementCollectionDispositionV1.self, forKey: .collectionDisposition),
            releasedAt: c.decode(Date.self, forKey: .releasedAt),
            supersedes: c.decodeIfPresent(CustomerLearningCatalogReferenceV1.self, forKey: .supersedes)
        )
        guard value.catalogSHA256 == c.decode(String.self, forKey: .catalogSHA256) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct MeasurementDestinationProcessorV1: Codable, Equatable, Hashable, Sendable {
    let destinationID: String
    let processorName: String
    let dataCategoryIDs: [String]
    let processingPurpose: String

    init(
        destinationID: String,
        processorName: String,
        dataCategoryIDs: [String],
        processingPurpose: String
    ) throws {
        self.destinationID = destinationID; self.processorName = processorName
        self.dataCategoryIDs = dataCategoryIDs.sorted(); self.processingPurpose = processingPurpose
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(destinationID)
        try CustomerLearningValidationV1.text(processorName, maximumBytes: 240)
        _ = try CustomerLearningValidationV1.sortedUniqueIdentifiers(dataCategoryIDs, maximumCount: 64)
        try CustomerLearningValidationV1.text(processingPurpose)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case destinationID, processorName, dataCategoryIDs, processingPurpose
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            destinationID: c.decode(String.self, forKey: .destinationID),
            processorName: c.decode(String.self, forKey: .processorName),
            dataCategoryIDs: c.decode([String].self, forKey: .dataCategoryIDs),
            processingPurpose: c.decode(String.self, forKey: .processingPurpose)
        )
    }
}

struct MeasurementActivationGovernanceV1: Codable, Equatable, Sendable {
    let lawfulConsentBasis: String
    let population: String
    let destinationsAndProcessors: [MeasurementDestinationProcessorV1]
    let aggregationPolicy: String
    let retentionPolicy: String
    let withdrawalPolicy: String
    let deleteExportErasePolicy: String
    let privacyPolicySHA256: String
    let appPrivacyAnswersSHA256: String
    let threatModelSHA256: String
    let securityReviewSHA256: String
    let offlineFailurePolicy: String
    let releaseMembershipSHA256: String
    let experimentGuardrails: String
    let killSwitchAndRemovalPath: String

    init(
        lawfulConsentBasis: String,
        population: String,
        destinationsAndProcessors: [MeasurementDestinationProcessorV1],
        aggregationPolicy: String,
        retentionPolicy: String,
        withdrawalPolicy: String,
        deleteExportErasePolicy: String,
        privacyPolicySHA256: String,
        appPrivacyAnswersSHA256: String,
        threatModelSHA256: String,
        securityReviewSHA256: String,
        offlineFailurePolicy: String,
        releaseMembershipSHA256: String,
        experimentGuardrails: String,
        killSwitchAndRemovalPath: String
    ) throws {
        self.lawfulConsentBasis = lawfulConsentBasis; self.population = population
        self.destinationsAndProcessors = destinationsAndProcessors.sorted { $0.destinationID < $1.destinationID }
        self.aggregationPolicy = aggregationPolicy; self.retentionPolicy = retentionPolicy
        self.withdrawalPolicy = withdrawalPolicy; self.deleteExportErasePolicy = deleteExportErasePolicy
        self.privacyPolicySHA256 = privacyPolicySHA256; self.appPrivacyAnswersSHA256 = appPrivacyAnswersSHA256
        self.threatModelSHA256 = threatModelSHA256; self.securityReviewSHA256 = securityReviewSHA256
        self.offlineFailurePolicy = offlineFailurePolicy; self.releaseMembershipSHA256 = releaseMembershipSHA256
        self.experimentGuardrails = experimentGuardrails; self.killSwitchAndRemovalPath = killSwitchAndRemovalPath
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.text(lawfulConsentBasis)
        try CustomerLearningValidationV1.text(population)
        try CustomerLearningValidationV1.text(aggregationPolicy)
        try CustomerLearningValidationV1.text(retentionPolicy)
        try CustomerLearningValidationV1.text(withdrawalPolicy)
        try CustomerLearningValidationV1.text(deleteExportErasePolicy)
        try CustomerLearningValidationV1.text(offlineFailurePolicy)
        try CustomerLearningValidationV1.text(experimentGuardrails)
        try CustomerLearningValidationV1.text(killSwitchAndRemovalPath)
        try CustomerLearningValidationV1.digest(privacyPolicySHA256)
        try CustomerLearningValidationV1.digest(appPrivacyAnswersSHA256)
        try CustomerLearningValidationV1.digest(threatModelSHA256)
        try CustomerLearningValidationV1.digest(securityReviewSHA256)
        try CustomerLearningValidationV1.digest(releaseMembershipSHA256)
        guard !destinationsAndProcessors.isEmpty,
              destinationsAndProcessors.count <= 32,
              destinationsAndProcessors == destinationsAndProcessors.sorted(by: { $0.destinationID < $1.destinationID }),
              Set(destinationsAndProcessors.map(\.destinationID)).count == destinationsAndProcessors.count else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        try destinationsAndProcessors.forEach { try $0.validate() }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case lawfulConsentBasis, population, destinationsAndProcessors, aggregationPolicy, retentionPolicy
        case withdrawalPolicy, deleteExportErasePolicy, privacyPolicySHA256, appPrivacyAnswersSHA256
        case threatModelSHA256, securityReviewSHA256, offlineFailurePolicy, releaseMembershipSHA256
        case experimentGuardrails, killSwitchAndRemovalPath
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lawfulConsentBasis: c.decode(String.self, forKey: .lawfulConsentBasis),
            population: c.decode(String.self, forKey: .population),
            destinationsAndProcessors: c.decode([MeasurementDestinationProcessorV1].self, forKey: .destinationsAndProcessors),
            aggregationPolicy: c.decode(String.self, forKey: .aggregationPolicy),
            retentionPolicy: c.decode(String.self, forKey: .retentionPolicy),
            withdrawalPolicy: c.decode(String.self, forKey: .withdrawalPolicy),
            deleteExportErasePolicy: c.decode(String.self, forKey: .deleteExportErasePolicy),
            privacyPolicySHA256: c.decode(String.self, forKey: .privacyPolicySHA256),
            appPrivacyAnswersSHA256: c.decode(String.self, forKey: .appPrivacyAnswersSHA256),
            threatModelSHA256: c.decode(String.self, forKey: .threatModelSHA256),
            securityReviewSHA256: c.decode(String.self, forKey: .securityReviewSHA256),
            offlineFailurePolicy: c.decode(String.self, forKey: .offlineFailurePolicy),
            releaseMembershipSHA256: c.decode(String.self, forKey: .releaseMembershipSHA256),
            experimentGuardrails: c.decode(String.self, forKey: .experimentGuardrails),
            killSwitchAndRemovalPath: c.decode(String.self, forKey: .killSwitchAndRemovalPath)
        )
    }
}

struct MeasurementOwnerAcceptanceV1: Codable, Equatable, Hashable, Sendable {
    let ownerAuthorityID: String
    let acceptedAt: Date
    let acceptanceBasisSHA256: String

    init(ownerAuthorityID: String, acceptedAt: Date, acceptanceBasisSHA256: String) throws {
        self.ownerAuthorityID = ownerAuthorityID; self.acceptedAt = acceptedAt
        self.acceptanceBasisSHA256 = acceptanceBasisSHA256
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.identifier(ownerAuthorityID)
        try CustomerLearningValidationV1.instant(acceptedAt)
        try CustomerLearningValidationV1.digest(acceptanceBasisSHA256)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case ownerAuthorityID, acceptedAt, acceptanceBasisSHA256 }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ownerAuthorityID: c.decode(String.self, forKey: .ownerAuthorityID),
            acceptedAt: c.decode(Date.self, forKey: .acceptedAt),
            acceptanceBasisSHA256: c.decode(String.self, forKey: .acceptanceBasisSHA256)
        )
    }
}

enum MeasurementActivationDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case proposed = "PROPOSED"
    case rejected = "REJECTED"
    case ownerAcceptedPendingSeparateImplementationCard = "OWNER_ACCEPTED_PENDING_SEPARATE_IMPLEMENTATION_CARD"
}

enum MeasurementActivationGateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case disabledProposed = "DISABLED_PROPOSED"
    case disabledRejected = "DISABLED_REJECTED"
    case disabledExpired = "DISABLED_EXPIRED"
    case disabledSeparateImplementationRequired = "DISABLED_SEPARATE_IMPLEMENTATION_REQUIRED"
}

struct MeasurementActivationDecisionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let decisionID: UUID
    let revision: UInt64
    let disposition: MeasurementActivationDispositionV1
    let collectionDisposition: MeasurementCollectionDispositionV1
    let createdAt: Date
    let expiresAt: Date
    let decisionSHA256: String

    init(
        decisionID: UUID,
        revision: UInt64,
        disposition: MeasurementActivationDispositionV1,
        collectionDisposition: MeasurementCollectionDispositionV1,
        createdAt: Date,
        expiresAt: Date,
        decisionSHA256: String
    ) throws {
        self.decisionID = decisionID; self.revision = revision; self.disposition = disposition
        self.collectionDisposition = collectionDisposition; self.createdAt = createdAt; self.expiresAt = expiresAt
        self.decisionSHA256 = decisionSHA256
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(decisionID)
        try CustomerLearningValidationV1.instant(createdAt); try CustomerLearningValidationV1.instant(expiresAt)
        guard revision > 0, collectionDisposition == .disabledNoCollection, createdAt < expiresAt else {
            throw CustomerLearningContractFailureV1.activationForbidden
        }
        try CustomerLearningValidationV1.digest(decisionSHA256)
    }

    func gate(at evaluatedAt: Date) throws -> MeasurementActivationGateV1 {
        try validate(); try CustomerLearningValidationV1.instant(evaluatedAt)
        guard evaluatedAt >= createdAt else { throw CustomerLearningContractFailureV1.activationForbidden }
        if evaluatedAt >= expiresAt { return .disabledExpired }
        switch disposition {
        case .proposed: return .disabledProposed
        case .rejected: return .disabledRejected
        case .ownerAcceptedPendingSeparateImplementationCard: return .disabledSeparateImplementationRequired
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case decisionID, revision, disposition, collectionDisposition, createdAt, expiresAt, decisionSHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            decisionID: c.decode(UUID.self, forKey: .decisionID),
            revision: c.decode(UInt64.self, forKey: .revision),
            disposition: c.decode(MeasurementActivationDispositionV1.self, forKey: .disposition),
            collectionDisposition: c.decode(MeasurementCollectionDispositionV1.self, forKey: .collectionDisposition),
            createdAt: c.decode(Date.self, forKey: .createdAt),
            expiresAt: c.decode(Date.self, forKey: .expiresAt),
            decisionSHA256: c.decode(String.self, forKey: .decisionSHA256)
        )
    }
}

struct MeasurementActivationDecisionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumLifetimeDays: TimeInterval = 365
    let schemaVersion: Int
    let decisionID: UUID
    let revision: UInt64
    let catalog: CustomerLearningCatalogReferenceV1
    let decisionToImproveSemanticID: String
    let minimumFieldSemanticIDs: [String]
    let minimumEventSemanticIDs: [String]
    let purposes: [MeasurementPurposeV1]
    let governance: MeasurementActivationGovernanceV1
    let disposition: MeasurementActivationDispositionV1
    let ownerAcceptance: MeasurementOwnerAcceptanceV1?
    let collectionDisposition: MeasurementCollectionDispositionV1
    let createdAt: Date
    let expiresAt: Date
    let supersedes: MeasurementActivationDecisionReferenceV1?
    let decisionSHA256: String

    init(
        decisionID: UUID,
        revision: UInt64,
        catalog: CustomerLearningCatalogReferenceV1,
        decisionToImproveSemanticID: String,
        minimumFieldSemanticIDs: [String],
        minimumEventSemanticIDs: [String],
        purposes: [MeasurementPurposeV1],
        governance: MeasurementActivationGovernanceV1,
        disposition: MeasurementActivationDispositionV1,
        ownerAcceptance: MeasurementOwnerAcceptanceV1? = nil,
        collectionDisposition: MeasurementCollectionDispositionV1 = .disabledNoCollection,
        createdAt: Date,
        expiresAt: Date,
        supersedes: MeasurementActivationDecisionReferenceV1? = nil
    ) throws {
        let orderedMinimumFieldSemanticIDs = minimumFieldSemanticIDs.sorted()
        let orderedMinimumEventSemanticIDs = minimumEventSemanticIDs.sorted()
        let orderedPurposes = purposes.sorted { $0.rawValue < $1.rawValue }
        schemaVersion = Self.schemaVersion; self.decisionID = decisionID; self.revision = revision
        self.catalog = catalog; self.decisionToImproveSemanticID = decisionToImproveSemanticID
        self.minimumFieldSemanticIDs = orderedMinimumFieldSemanticIDs
        self.minimumEventSemanticIDs = orderedMinimumEventSemanticIDs
        self.purposes = orderedPurposes; self.governance = governance
        self.disposition = disposition; self.ownerAcceptance = ownerAcceptance
        self.collectionDisposition = collectionDisposition; self.createdAt = createdAt; self.expiresAt = expiresAt
        self.supersedes = supersedes
        decisionSHA256 = try CustomerLearningCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            decisionID: decisionID,
            revision: revision,
            catalog: catalog,
            decisionToImproveSemanticID: decisionToImproveSemanticID,
            minimumFieldSemanticIDs: orderedMinimumFieldSemanticIDs,
            minimumEventSemanticIDs: orderedMinimumEventSemanticIDs,
            purposes: orderedPurposes,
            governance: governance,
            disposition: disposition,
            ownerAcceptance: ownerAcceptance,
            collectionDisposition: collectionDisposition,
            createdAt: createdAt,
            expiresAt: expiresAt,
            supersedes: supersedes
        ))
        try validate()
    }

    var reference: MeasurementActivationDecisionReferenceV1 {
        get throws { try .init(
            decisionID: decisionID,
            revision: revision,
            disposition: disposition,
            collectionDisposition: collectionDisposition,
            createdAt: createdAt,
            expiresAt: expiresAt,
            decisionSHA256: decisionSHA256
        ) }
    }

    var authorizesRuntimeCollection: Bool { false }

    func gate(at evaluatedAt: Date) throws -> MeasurementActivationGateV1 {
        try validate(); try CustomerLearningValidationV1.instant(evaluatedAt)
        guard evaluatedAt >= createdAt else { throw CustomerLearningContractFailureV1.activationForbidden }
        if evaluatedAt >= expiresAt { return .disabledExpired }
        switch disposition {
        case .proposed: return .disabledProposed
        case .rejected: return .disabledRejected
        case .ownerAcceptedPendingSeparateImplementationCard: return .disabledSeparateImplementationRequired
        }
    }

    func validate() throws {
        try CustomerLearningValidationV1.uuid(decisionID); try catalog.validate()
        try CustomerLearningValidationV1.identifier(decisionToImproveSemanticID)
        _ = try CustomerLearningValidationV1.sortedUniqueIdentifiers(minimumFieldSemanticIDs, maximumCount: 128)
        _ = try CustomerLearningValidationV1.sortedUniqueIdentifiers(minimumEventSemanticIDs, maximumCount: 128)
        try governance.validate(); try CustomerLearningValidationV1.instant(createdAt)
        try CustomerLearningValidationV1.instant(expiresAt); try ownerAcceptance?.validate()
        guard schemaVersion == Self.schemaVersion,
              revision > 0,
              !purposes.isEmpty,
              purposes.count <= MeasurementPurposeV1.allCases.count,
              purposes == purposes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(purposes).count == purposes.count,
              collectionDisposition == .disabledNoCollection,
              createdAt < expiresAt,
              expiresAt.timeIntervalSince(createdAt) <= Self.maximumLifetimeDays * 86_400,
              !authorizesRuntimeCollection else {
            throw CustomerLearningContractFailureV1.activationForbidden
        }
        switch disposition {
        case .ownerAcceptedPendingSeparateImplementationCard:
            guard let ownerAcceptance,
                  ownerAcceptance.acceptedAt >= createdAt,
                  ownerAcceptance.acceptedAt < expiresAt else {
                throw CustomerLearningContractFailureV1.activationForbidden
            }
        case .proposed, .rejected:
            guard ownerAcceptance == nil else { throw CustomerLearningContractFailureV1.activationForbidden }
        }
        if revision == 1 {
            guard supersedes == nil else { throw CustomerLearningContractFailureV1.invalidValue }
        } else {
            guard let supersedes,
                  supersedes.decisionID == decisionID,
                  CustomerLearningValidationV1.isImmediateSuccessor(
                    revision, of: supersedes.revision
                  ) else {
                throw CustomerLearningContractFailureV1.invalidValue
            }
            try supersedes.validate()
        }
        guard decisionSHA256 == (try CustomerLearningCanonicalCodecV1.sha256(basis)) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
    }

    private var basis: Basis { .init(
        schemaVersion: schemaVersion, decisionID: decisionID, revision: revision, catalog: catalog,
        decisionToImproveSemanticID: decisionToImproveSemanticID,
        minimumFieldSemanticIDs: minimumFieldSemanticIDs, minimumEventSemanticIDs: minimumEventSemanticIDs,
        purposes: purposes, governance: governance, disposition: disposition, ownerAcceptance: ownerAcceptance,
        collectionDisposition: collectionDisposition, createdAt: createdAt, expiresAt: expiresAt, supersedes: supersedes
    ) }
    private struct Basis: Codable {
        let schemaVersion: Int; let decisionID: UUID; let revision: UInt64
        let catalog: CustomerLearningCatalogReferenceV1; let decisionToImproveSemanticID: String
        let minimumFieldSemanticIDs: [String]; let minimumEventSemanticIDs: [String]
        let purposes: [MeasurementPurposeV1]; let governance: MeasurementActivationGovernanceV1
        let disposition: MeasurementActivationDispositionV1; let ownerAcceptance: MeasurementOwnerAcceptanceV1?
        let collectionDisposition: MeasurementCollectionDispositionV1; let createdAt: Date; let expiresAt: Date
        let supersedes: MeasurementActivationDecisionReferenceV1?
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, decisionID, revision, catalog, decisionToImproveSemanticID
        case minimumFieldSemanticIDs, minimumEventSemanticIDs, purposes, governance, disposition
        case ownerAcceptance, collectionDisposition, createdAt, expiresAt, supersedes, decisionSHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw CustomerLearningContractFailureV1.invalidValue
        }
        let value = try Self(
            decisionID: c.decode(UUID.self, forKey: .decisionID),
            revision: c.decode(UInt64.self, forKey: .revision),
            catalog: c.decode(CustomerLearningCatalogReferenceV1.self, forKey: .catalog),
            decisionToImproveSemanticID: c.decode(String.self, forKey: .decisionToImproveSemanticID),
            minimumFieldSemanticIDs: c.decode([String].self, forKey: .minimumFieldSemanticIDs),
            minimumEventSemanticIDs: c.decode([String].self, forKey: .minimumEventSemanticIDs),
            purposes: c.decode([MeasurementPurposeV1].self, forKey: .purposes),
            governance: c.decode(MeasurementActivationGovernanceV1.self, forKey: .governance),
            disposition: c.decode(MeasurementActivationDispositionV1.self, forKey: .disposition),
            ownerAcceptance: c.decodeIfPresent(MeasurementOwnerAcceptanceV1.self, forKey: .ownerAcceptance),
            collectionDisposition: c.decode(MeasurementCollectionDispositionV1.self, forKey: .collectionDisposition),
            createdAt: c.decode(Date.self, forKey: .createdAt),
            expiresAt: c.decode(Date.self, forKey: .expiresAt),
            supersedes: c.decodeIfPresent(MeasurementActivationDecisionReferenceV1.self, forKey: .supersedes)
        )
        guard value.decisionSHA256 == c.decode(String.self, forKey: .decisionSHA256) else {
            throw CustomerLearningContractFailureV1.invalidDigest
        }
        self = value
    }
}

struct ZeroCollectionScanEvidenceV1: Codable, Equatable, Hashable, Sendable {
    let candidateHead: String
    let candidateTree: String
    let archiveSHA256: String
    let dependencyScanSHA256: String
    let linkedBinaryScanSHA256: String
    let stringScanSHA256: String
    let domainScanSHA256: String
    let backgroundTaskScanSHA256: String
    let privacyManifestSHA256: String
    let runtimeNetworkObservationSHA256: String

    init(
        candidateHead: String,
        candidateTree: String,
        archiveSHA256: String,
        dependencyScanSHA256: String,
        linkedBinaryScanSHA256: String,
        stringScanSHA256: String,
        domainScanSHA256: String,
        backgroundTaskScanSHA256: String,
        privacyManifestSHA256: String,
        runtimeNetworkObservationSHA256: String
    ) throws {
        self.candidateHead = candidateHead; self.candidateTree = candidateTree
        self.archiveSHA256 = archiveSHA256; self.dependencyScanSHA256 = dependencyScanSHA256
        self.linkedBinaryScanSHA256 = linkedBinaryScanSHA256; self.stringScanSHA256 = stringScanSHA256
        self.domainScanSHA256 = domainScanSHA256; self.backgroundTaskScanSHA256 = backgroundTaskScanSHA256
        self.privacyManifestSHA256 = privacyManifestSHA256
        self.runtimeNetworkObservationSHA256 = runtimeNetworkObservationSHA256
        try validate()
    }

    func validate() throws {
        try CustomerLearningValidationV1.gitObject(candidateHead)
        try CustomerLearningValidationV1.gitObject(candidateTree)
        try [archiveSHA256, dependencyScanSHA256, linkedBinaryScanSHA256, stringScanSHA256,
             domainScanSHA256, backgroundTaskScanSHA256, privacyManifestSHA256,
             runtimeNetworkObservationSHA256].forEach(CustomerLearningValidationV1.digest)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case candidateHead, candidateTree, archiveSHA256, dependencyScanSHA256, linkedBinaryScanSHA256
        case stringScanSHA256, domainScanSHA256, backgroundTaskScanSHA256, privacyManifestSHA256
        case runtimeNetworkObservationSHA256
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            candidateHead: c.decode(String.self, forKey: .candidateHead),
            candidateTree: c.decode(String.self, forKey: .candidateTree),
            archiveSHA256: c.decode(String.self, forKey: .archiveSHA256),
            dependencyScanSHA256: c.decode(String.self, forKey: .dependencyScanSHA256),
            linkedBinaryScanSHA256: c.decode(String.self, forKey: .linkedBinaryScanSHA256),
            stringScanSHA256: c.decode(String.self, forKey: .stringScanSHA256),
            domainScanSHA256: c.decode(String.self, forKey: .domainScanSHA256),
            backgroundTaskScanSHA256: c.decode(String.self, forKey: .backgroundTaskScanSHA256),
            privacyManifestSHA256: c.decode(String.self, forKey: .privacyManifestSHA256),
            runtimeNetworkObservationSHA256: c.decode(String.self, forKey: .runtimeNetworkObservationSHA256)
        )
    }
}

struct ZeroCollectionObservationV1: Codable, Equatable, Hashable, Sendable {
    let analyticsAttributionAdSDKCount: UInt32
    let productEventStoreCount: UInt32
    let endpointDomainCount: UInt32
    let backgroundUploaderTaskCount: UInt32
    let advertisingIdentifierUseCount: UInt32
    let fingerprintUseCount: UInt32
    let stableCrossAppDevicePersonIDCount: UInt32
    let campaignTokenHandlerCount: UInt32
    let hiddenExperimentAssignmentCount: UInt32
    let productionReceiptProjectionReaderCount: UInt32
    let collectionTransmissionCount: UInt32
    let trackingCount: UInt32
    let privacyManifestCollectedDataTypeCount: UInt32
    let privacyManifestTracking: Bool
    let privacyManifestTrackingDomainCount: UInt32

    init(
        analyticsAttributionAdSDKCount: UInt32 = 0,
        productEventStoreCount: UInt32 = 0,
        endpointDomainCount: UInt32 = 0,
        backgroundUploaderTaskCount: UInt32 = 0,
        advertisingIdentifierUseCount: UInt32 = 0,
        fingerprintUseCount: UInt32 = 0,
        stableCrossAppDevicePersonIDCount: UInt32 = 0,
        campaignTokenHandlerCount: UInt32 = 0,
        hiddenExperimentAssignmentCount: UInt32 = 0,
        productionReceiptProjectionReaderCount: UInt32 = 0,
        collectionTransmissionCount: UInt32 = 0,
        trackingCount: UInt32 = 0,
        privacyManifestCollectedDataTypeCount: UInt32 = 0,
        privacyManifestTracking: Bool = false,
        privacyManifestTrackingDomainCount: UInt32 = 0
    ) throws {
        self.analyticsAttributionAdSDKCount = analyticsAttributionAdSDKCount
        self.productEventStoreCount = productEventStoreCount; self.endpointDomainCount = endpointDomainCount
        self.backgroundUploaderTaskCount = backgroundUploaderTaskCount
        self.advertisingIdentifierUseCount = advertisingIdentifierUseCount; self.fingerprintUseCount = fingerprintUseCount
        self.stableCrossAppDevicePersonIDCount = stableCrossAppDevicePersonIDCount
        self.campaignTokenHandlerCount = campaignTokenHandlerCount
        self.hiddenExperimentAssignmentCount = hiddenExperimentAssignmentCount
        self.productionReceiptProjectionReaderCount = productionReceiptProjectionReaderCount
        self.collectionTransmissionCount = collectionTransmissionCount; self.trackingCount = trackingCount
        self.privacyManifestCollectedDataTypeCount = privacyManifestCollectedDataTypeCount
        self.privacyManifestTracking = privacyManifestTracking
        self.privacyManifestTrackingDomainCount = privacyManifestTrackingDomainCount
        try validate()
    }

    func validate() throws {
        let counts = [analyticsAttributionAdSDKCount, productEventStoreCount, endpointDomainCount,
                      backgroundUploaderTaskCount, advertisingIdentifierUseCount, fingerprintUseCount,
                      stableCrossAppDevicePersonIDCount, campaignTokenHandlerCount, hiddenExperimentAssignmentCount,
                      productionReceiptProjectionReaderCount, collectionTransmissionCount, trackingCount,
                      privacyManifestCollectedDataTypeCount, privacyManifestTrackingDomainCount]
        guard counts.allSatisfy({ $0 == 0 }), !privacyManifestTracking else {
            throw CustomerLearningContractFailureV1.collectionForbidden
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case analyticsAttributionAdSDKCount, productEventStoreCount, endpointDomainCount
        case backgroundUploaderTaskCount, advertisingIdentifierUseCount, fingerprintUseCount
        case stableCrossAppDevicePersonIDCount, campaignTokenHandlerCount, hiddenExperimentAssignmentCount
        case productionReceiptProjectionReaderCount, collectionTransmissionCount, trackingCount
        case privacyManifestCollectedDataTypeCount, privacyManifestTracking, privacyManifestTrackingDomainCount
    }
    init(from decoder: any Decoder) throws {
        try CustomerLearningClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            analyticsAttributionAdSDKCount: c.decode(UInt32.self, forKey: .analyticsAttributionAdSDKCount),
            productEventStoreCount: c.decode(UInt32.self, forKey: .productEventStoreCount),
            endpointDomainCount: c.decode(UInt32.self, forKey: .endpointDomainCount),
            backgroundUploaderTaskCount: c.decode(UInt32.self, forKey: .backgroundUploaderTaskCount),
            advertisingIdentifierUseCount: c.decode(UInt32.self, forKey: .advertisingIdentifierUseCount),
            fingerprintUseCount: c.decode(UInt32.self, forKey: .fingerprintUseCount),
            stableCrossAppDevicePersonIDCount: c.decode(UInt32.self, forKey: .stableCrossAppDevicePersonIDCount),
            campaignTokenHandlerCount: c.decode(UInt32.self, forKey: .campaignTokenHandlerCount),
            hiddenExperimentAssignmentCount: c.decode(UInt32.self, forKey: .hiddenExperimentAssignmentCount),
            productionReceiptProjectionReaderCount: c.decode(UInt32.self, forKey: .productionReceiptProjectionReaderCount),
            collectionTransmissionCount: c.decode(UInt32.self, forKey: .collectionTransmissionCount),
            trackingCount: c.decode(UInt32.self, forKey: .trackingCount),
            privacyManifestCollectedDataTypeCount: c.decode(UInt32.self, forKey: .privacyManifestCollectedDataTypeCount),
            privacyManifestTracking: c.decode(Bool.self, forKey: .privacyManifestTracking),
            privacyManifestTrackingDomainCount: c.decode(UInt32.self, forKey: .privacyManifestTrackingDomainCount)
        )
    }
}

enum ZeroCollectionConformanceIssuanceDispositionV1: String, Codable, CaseIterable, Sendable {
    case pendingExactCandidateArchiveRuntimeNativeEvidence =
        "PENDING_EXACT_CANDIDATE_ARCHIVE_RUNTIME_NATIVE_EVIDENCE"
}

/// Deliberately uninhabited in C43. Static documents, synthetic observations,
/// and opaque digests can describe pending evidence, but none can mint a final
/// zero-collection conformance receipt. A separately authorized card must change
/// this declaration before issuance can exist.
enum ZeroCollectionConformanceReceiptV1 {
    static let issuanceDisposition: ZeroCollectionConformanceIssuanceDispositionV1 =
        .pendingExactCandidateArchiveRuntimeNativeEvidence
    static let collectionDisposition: MeasurementCollectionDispositionV1 = .disabledNoCollection
    static let authorizesIssuance = false

    static func requireIssuanceAuthority() throws -> Never {
        throw CustomerLearningContractFailureV1.collectionForbidden
    }
}

enum CustomerLearningRuntimeBoundaryV1 {
    static let collectionDisposition: MeasurementCollectionDispositionV1 = .disabledNoCollection
    static let durableModelCount = 0
    static let eventPersistenceEnabled = false
    static let productionReceiptProjectionReaderEnabled = false
    static let runtimeInvokerEnabled = false
    static let networkOrProviderEnabled = false
    static let crossSourceJoinEnabled = false
    static let metricDefinitionBridgeEnabled = false
    static let remoteActivationEnabled = false

    static func validate() throws {
        guard collectionDisposition == .disabledNoCollection,
              durableModelCount == 0,
              !eventPersistenceEnabled,
              !productionReceiptProjectionReaderEnabled,
              !runtimeInvokerEnabled,
              !networkOrProviderEnabled,
              !crossSourceJoinEnabled,
              !metricDefinitionBridgeEnabled,
              !remoteActivationEnabled else {
            throw CustomerLearningContractFailureV1.collectionForbidden
        }
    }
}

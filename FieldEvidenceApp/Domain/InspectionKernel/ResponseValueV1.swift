import Foundation

enum ResponseValueKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case noValue = "NO_VALUE"
    case notApplicable = "NOT_APPLICABLE"
    case boolean = "BOOLEAN"
    case triState = "TRI_STATE"
    case singleOption = "SINGLE_OPTION"
    case multipleOptions = "MULTIPLE_OPTIONS"
    case text = "TEXT"
    case localDate = "LOCAL_DATE"
    case localTime = "LOCAL_TIME"
    case instant = "INSTANT"
    case duration = "DURATION"
    case integer = "INTEGER"
    case decimal = "DECIMAL"
    case measurement = "MEASUREMENT"
    case entityReference = "ENTITY_REFERENCE"
    case contentReference = "CONTENT_REFERENCE"
}

enum C26SurveyResponseSemanticsV1 {
    static let inspectionOutcomeKinds:Set<ResponseValueKindV1>=[]
    static func validate(_ value:ResponseValueV1,for fact:FactDefinitionV1)throws{try value.validate();try fact.validate();guard SurveyDefinitionStaticValidationV1.response(value,isCompatibleWith:fact)else{throw SurveySessionFailureV1.wrongDefinition}}
    static func isExplicitUnknownOrNotObserved(_ value:ResponseValueV1)->Bool{value == .triState(.unknown)||value == .triState(.notObserved)}
}

enum ResponseTriStateV1: String, CaseIterable, Codable, Sendable {
    case trueValue = "TRUE"
    case falseValue = "FALSE"
    case unknown = "UNKNOWN"
    case notObserved = "NOT_OBSERVED"
}

extension ResponseValueV1 {
    func validateSurveyObservation(for fact: FactDefinitionV1) throws {
        try fact.validate(); try validate()
        if fact.kind == .booleanObservation {
            guard case .triState = self else { throw ResponseContractFailureV1.invalidValue }
        }
    }
}

struct ResponseLocalDateV1: Codable, Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        guard (1...9_999).contains(year), (1...12).contains(month), day >= 1,
              day <= Self.days(month: month, year: year) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.year = year
        self.month = month
        self.day = day
    }

    private static func days(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let leap = year.isMultiple(of: 400)
                || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

struct ResponseLocalTimeV1: Codable, Equatable, Sendable {
    let hour: Int
    let minute: Int
    let second: Int
    let millisecond: Int

    init(hour: Int, minute: Int, second: Int, millisecond: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute),
              (0...59).contains(second), (0...999).contains(millisecond) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.hour = hour
        self.minute = minute
        self.second = second
        self.millisecond = millisecond
    }
}

struct ResponseInstantV1: Codable, Equatable, Sendable {
    static let minimumEpochMilliseconds: Int64 = -62_135_596_800_000
    static let maximumEpochMilliseconds: Int64 = 253_402_300_799_999
    let epochMilliseconds: Int64

    init(epochMilliseconds: Int64) throws {
        guard (Self.minimumEpochMilliseconds...Self.maximumEpochMilliseconds)
            .contains(epochMilliseconds) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.epochMilliseconds = epochMilliseconds
    }
}

struct ResponseDurationV1: Codable, Equatable, Sendable {
    static let maximumMilliseconds: Int64 = 315_576_000_000
    let milliseconds: Int64

    init(milliseconds: Int64) throws {
        guard (0...Self.maximumMilliseconds).contains(milliseconds) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.milliseconds = milliseconds
    }
}

struct ResponseEntityReferenceV1: Codable, Equatable, Sendable {
    let entityKindID: String
    let entityID: String

    init(entityKindID: String, entityID: String) throws {
        guard ResponseIdentifierValidationV1.valid(entityKindID),
              ResponseIdentifierValidationV1.valid(entityID) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.entityKindID = entityKindID
        self.entityID = entityID
    }
}

// C05 owns the future ContentReferenceV1 object and byte lifecycle. C03 stores
// only its bounded stable identity so it does not pre-implement that contract.
struct ResponseContentReferenceIDV1: Codable, Equatable, Sendable {
    let rawValue: String
    init(_ rawValue: String) throws {
        guard ResponseIdentifierValidationV1.valid(rawValue) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.rawValue = rawValue
    }
}

enum ResponseValueV1: Codable, Equatable, Sendable {
    static let maximumTextUTF8Bytes = 4_096
    static let maximumOptionCount = 128

    case noValue
    case notApplicable(reasonID: String)
    case boolean(Bool)
    case triState(ResponseTriStateV1)
    case singleOption(String)
    case multipleOptions([String])
    case text(String)
    case localDate(ResponseLocalDateV1)
    case localTime(ResponseLocalTimeV1)
    case instant(ResponseInstantV1)
    case duration(ResponseDurationV1)
    case integer(Int64)
    case decimal(ExactDecimalV1)
    case measurement(ExactMeasurementV1)
    case entityReference(ResponseEntityReferenceV1)
    case contentReference(ResponseContentReferenceIDV1)

    var kind: ResponseValueKindV1 {
        switch self {
        case .noValue: return .noValue
        case .notApplicable: return .notApplicable
        case .boolean: return .boolean
        case .triState: return .triState
        case .singleOption: return .singleOption
        case .multipleOptions: return .multipleOptions
        case .text: return .text
        case .localDate: return .localDate
        case .localTime: return .localTime
        case .instant: return .instant
        case .duration: return .duration
        case .integer: return .integer
        case .decimal: return .decimal
        case .measurement: return .measurement
        case .entityReference: return .entityReference
        case .contentReference: return .contentReference
        }
    }

    func validate() throws {
        switch self {
        case .noValue:
            break
        case .notApplicable(let reasonID), .singleOption(let reasonID):
            guard ResponseIdentifierValidationV1.valid(reasonID) else {
                throw ResponseContractFailureV1.invalidValue
            }
        case .boolean, .triState, .localDate, .localTime, .instant, .duration, .integer:
            break
        case .multipleOptions(let values):
            guard !values.isEmpty, values.count <= Self.maximumOptionCount,
                  values == values.sorted(), Set(values).count == values.count,
                  values.allSatisfy(ResponseIdentifierValidationV1.valid) else {
                throw ResponseContractFailureV1.cardinalityViolation
            }
        case .text(let value):
            guard value.utf8.count <= Self.maximumTextUTF8Bytes else {
                throw ResponseContractFailureV1.limitExceeded
            }
        case .decimal(let value):
            _ = try ExactDecimalV1(mantissa: value.mantissa, scale: value.scale)
        case .measurement(let value):
            try value.validate()
        case .entityReference(let value):
            _ = try ResponseEntityReferenceV1(
                entityKindID: value.entityKindID,
                entityID: value.entityID
            )
        case .contentReference(let value):
            _ = try ResponseContentReferenceIDV1(value.rawValue)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, reasonID, boolean, triState, optionID, optionIDs, text
        case localDate, localTime, instant, duration, integer, decimal
        case measurement, entityReference, contentReference
    }

    init(from decoder: any Decoder) throws {
        let dynamic = try decoder.container(keyedBy: ResponseDynamicCodingKeyV1.self)
        guard let kindKey = ResponseDynamicCodingKeyV1(stringValue: CodingKeys.kind.rawValue),
              dynamic.contains(kindKey) else {
            throw ResponseContractFailureV1.invalidValue
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(ResponseValueKindV1.self, forKey: .kind)
        func require(_ payload: CodingKeys?) throws {
            var expected = Set([CodingKeys.kind.rawValue])
            if let payload { expected.insert(payload.rawValue) }
            let observed = Set(dynamic.allKeys.map(\.stringValue))
            guard observed == expected else { throw ResponseContractFailureV1.invalidValue }
        }
        switch kind {
        case .noValue:
            try require(nil); self = .noValue
        case .notApplicable:
            try require(.reasonID); self = .notApplicable(reasonID: try c.decode(String.self, forKey: .reasonID))
        case .boolean:
            try require(.boolean); self = .boolean(try c.decode(Bool.self, forKey: .boolean))
        case .triState:
            try require(.triState); self = .triState(try c.decode(ResponseTriStateV1.self, forKey: .triState))
        case .singleOption:
            try require(.optionID); self = .singleOption(try c.decode(String.self, forKey: .optionID))
        case .multipleOptions:
            try require(.optionIDs); self = .multipleOptions(try c.decode([String].self, forKey: .optionIDs))
        case .text:
            try require(.text); self = .text(try c.decode(String.self, forKey: .text))
        case .localDate:
            try require(.localDate); self = .localDate(try c.decode(ResponseLocalDateV1.self, forKey: .localDate))
        case .localTime:
            try require(.localTime); self = .localTime(try c.decode(ResponseLocalTimeV1.self, forKey: .localTime))
        case .instant:
            try require(.instant); self = .instant(try c.decode(ResponseInstantV1.self, forKey: .instant))
        case .duration:
            try require(.duration); self = .duration(try c.decode(ResponseDurationV1.self, forKey: .duration))
        case .integer:
            try require(.integer); self = .integer(try c.decode(Int64.self, forKey: .integer))
        case .decimal:
            try require(.decimal); self = .decimal(try c.decode(ExactDecimalV1.self, forKey: .decimal))
        case .measurement:
            try require(.measurement); self = .measurement(try c.decode(ExactMeasurementV1.self, forKey: .measurement))
        case .entityReference:
            try require(.entityReference); self = .entityReference(try c.decode(ResponseEntityReferenceV1.self, forKey: .entityReference))
        case .contentReference:
            try require(.contentReference); self = .contentReference(try c.decode(ResponseContentReferenceIDV1.self, forKey: .contentReference))
        }
        try validate()
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .noValue: break
        case .notApplicable(let value): try c.encode(value, forKey: .reasonID)
        case .boolean(let value): try c.encode(value, forKey: .boolean)
        case .triState(let value): try c.encode(value, forKey: .triState)
        case .singleOption(let value): try c.encode(value, forKey: .optionID)
        case .multipleOptions(let value): try c.encode(value, forKey: .optionIDs)
        case .text(let value): try c.encode(value, forKey: .text)
        case .localDate(let value): try c.encode(value, forKey: .localDate)
        case .localTime(let value): try c.encode(value, forKey: .localTime)
        case .instant(let value): try c.encode(value, forKey: .instant)
        case .duration(let value): try c.encode(value, forKey: .duration)
        case .integer(let value): try c.encode(value, forKey: .integer)
        case .decimal(let value): try c.encode(value, forKey: .decimal)
        case .measurement(let value): try c.encode(value, forKey: .measurement)
        case .entityReference(let value): try c.encode(value, forKey: .entityReference)
        case .contentReference(let value): try c.encode(value, forKey: .contentReference)
        }
    }
}

enum ResponseValueCanonicalCodecV1 {
    static let maximumCanonicalBytes = 1_048_576

    static func encode(_ value: ResponseValueV1) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximumCanonicalBytes else {
            throw ResponseContractFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> ResponseValueV1 {
        guard !data.isEmpty, data.count <= maximumCanonicalBytes else {
            throw ResponseContractFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(ResponseValueV1.self, from: data)
        guard try encode(value) == data else { throw ResponseContractFailureV1.invalidValue }
        return value
    }
}

struct ResponseDynamicCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

// MARK: - C19 measurement capture bridge

extension ResponseValueV1 {
    /// Returns the exact fixed-point measurement only when the response is a
    /// measurement value. Imported and derived measurements remain valid
    /// response values, but are not accepted as a local C19 capture source.
    var c19Measurement: ExactMeasurementV1? {
        guard case let .measurement(value) = self else { return nil }
        return value
    }

    func c19LocalMeasurement() throws -> ExactMeasurementV1 {
        guard case let .measurement(value) = self,
              value.isLocalMeasurementCaptureSource else {
            throw MeasurementIntegrityFailureV1.unsupportedSource
        }
        try value.validate()
        return value
    }

    func c19ValidateMeasurementEquality(_ expected: ExactMeasurementV1) throws {
        let actual = try c19LocalMeasurement()
        guard actual == expected else {
            throw MeasurementIntegrityFailureV1.invalidValue
        }
    }
}

// MARK: - C20 reviewed-derivative projection boundary

/// C20's privacy decision is a projection gate, not a compliance or
/// classification decision.  Keeping the common validation here gives every
/// response/evidence consumer the same fail-closed source, policy, audience,
/// review, and derivative-digest checks.
enum C20PrivacyProjectionBridgeV1 {
    static func decision(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> PrivacyProjectionDecisionV1 {
        try PrivacyTransformLifecycleClosureV1(
            policy: policy,
            regions: manifest.orderedRegions,
            manifest: manifest,
            review: review
        ).validate()
        return try PrivacyProjectionV1.decide(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }

    static func requireAllowed(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        let result = try decision(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
        guard let derivative = result.derivative, result.denial == nil else {
            switch result.denial {
            case .some(.missingReview): throw PrivacyTransformFailureV1.reviewRequired
            case .some(.rejected): throw PrivacyTransformFailureV1.rejected
            case .some(.stale), .some(.sourceChanged): throw PrivacyTransformFailureV1.staleDerivative
            case .some(.wrongAudience): throw PrivacyTransformFailureV1.wrongAudience
            case .some(.wrongPolicy): throw PrivacyTransformFailureV1.wrongPolicy
            case .some(.digestMismatch): throw PrivacyTransformFailureV1.digestMismatch
            case .some(.metadataNotSanitized): throw PrivacyTransformFailureV1.metadataNotSanitized
            case .none: throw PrivacyTransformFailureV1.invalidValue
            }
        }
        guard derivative == manifest.derivative,
              derivative.byteRole == .derivative,
              derivative.digests.digest(for: .sha256)?.hexadecimalValue
                  == manifest.derivativeSHA256 else {
            throw PrivacyTransformFailureV1.digestMismatch
        }
        return derivative
    }
}

extension ResponseValueV1 {
    /// Validates that this response names exactly the reviewed, current C20
    /// derivative. Original references and unreviewed/stale derivatives never
    /// become audience-safe response evidence.
    func c20ValidateReviewedDerivative(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        try validate()
        guard case let .contentReference(reference) = self,
              reference.rawValue == manifest.derivative.contentID else {
            throw PrivacyTransformFailureV1.invalidValue
        }
        return try C20PrivacyProjectionBridgeV1.requireAllowed(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }
}

enum ResponseClosedCodingV1 {
    static func requireExact(_ decoder: any Decoder, keys: [String]) throws {
        let c = try decoder.container(keyedBy: ResponseDynamicCodingKeyV1.self)
        guard Set(c.allKeys.map(\.stringValue)) == Set(keys) else {
            throw ResponseContractFailureV1.invalidValue
        }
    }

    static func requireClosed(
        _ decoder: any Decoder,
        allowed: [String],
        required: [String]
    ) throws {
        let c = try decoder.container(keyedBy: ResponseDynamicCodingKeyV1.self)
        let observed = Set(c.allKeys.map(\.stringValue))
        guard observed.isSubset(of: Set(allowed)), Set(required).isSubset(of: observed) else {
            throw ResponseContractFailureV1.invalidValue
        }
    }
}

extension ResponseLocalDateV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case year, month, day }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(year: c.decode(Int.self, forKey: .year), month: c.decode(Int.self, forKey: .month), day: c.decode(Int.self, forKey: .day))
    }
}

extension ResponseLocalTimeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case hour, minute, second, millisecond }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(hour: c.decode(Int.self, forKey: .hour), minute: c.decode(Int.self, forKey: .minute), second: c.decode(Int.self, forKey: .second), millisecond: c.decode(Int.self, forKey: .millisecond))
    }
}

extension ResponseInstantV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case epochMilliseconds }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(epochMilliseconds: c.decode(Int64.self, forKey: .epochMilliseconds))
    }
}

extension ResponseDurationV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case milliseconds }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(milliseconds: c.decode(Int64.self, forKey: .milliseconds))
    }
}

extension ResponseEntityReferenceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case entityKindID, entityID }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(entityKindID: c.decode(String.self, forKey: .entityKindID), entityID: c.decode(String.self, forKey: .entityID))
    }
}

extension ResponseContentReferenceIDV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case rawValue }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(c.decode(String.self, forKey: .rawValue))
    }
}

enum C47ActivityContractCompatibility_FieldEvidenceApp_Domain_InspectionKernel_ResponseValueV1_swift {
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

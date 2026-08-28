import Foundation

enum ResponseContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case unknownKind
    case incompatibleVersion
    case limitExceeded
    case arithmeticOverflow
    case precisionLoss
    case unsupportedUnit
    case dimensionMismatch
    case rangeViolation
    case cardinalityViolation
    case duplicateIdentity
    case hashMismatch
    case invalidTransition
    case publicationInterrupted
}

struct ExactDecimalV1: Codable, Equatable, Hashable, Sendable {
    static let maximumScale = 9
    let mantissa: Int64
    let scale: Int

    init(mantissa: Int64, scale: Int) throws {
        guard (0...Self.maximumScale).contains(scale) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.mantissa = mantissa
        self.scale = scale
    }

    func compared(to other: ExactDecimalV1) throws -> ComparisonResult {
        let commonScale = max(scale, other.scale)
        let lhs = try rescaledExactly(to: commonScale)
        let rhs = try other.rescaledExactly(to: commonScale)
        if lhs.mantissa < rhs.mantissa { return .orderedAscending }
        if lhs.mantissa > rhs.mantissa { return .orderedDescending }
        return .orderedSame
    }

    func rescaledExactly(to targetScale: Int) throws -> ExactDecimalV1 {
        guard (0...Self.maximumScale).contains(targetScale) else {
            throw ResponseContractFailureV1.invalidValue
        }
        if targetScale == scale { return self }
        if targetScale > scale {
            let factor = try ExactIntegerMathV1.powerOfTen(targetScale - scale)
            return try ExactDecimalV1(
                mantissa: ExactIntegerMathV1.multiply(mantissa, factor),
                scale: targetScale
            )
        }
        let divisor = try ExactIntegerMathV1.powerOfTen(scale - targetScale)
        guard mantissa % divisor == 0 else {
            throw ResponseContractFailureV1.precisionLoss
        }
        return try ExactDecimalV1(mantissa: mantissa / divisor, scale: targetScale)
    }
}

struct ExactRationalV1: Codable, Equatable, Hashable, Sendable {
    let numerator: Int64
    let denominator: Int64

    init(numerator: Int64, denominator: Int64) throws {
        guard denominator > 0 else { throw ResponseContractFailureV1.invalidValue }
        self.numerator = numerator
        self.denominator = denominator
    }
}

enum MeasurementDimensionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case dimensionless = "DIMENSIONLESS"
    case length = "LENGTH"
    case illuminance = "ILLUMINANCE"
    case duration = "DURATION"
    case temperature = "TEMPERATURE"
    case pressure = "PRESSURE"
    case electricPotential = "ELECTRIC_POTENTIAL"
    case electricCurrent = "ELECTRIC_CURRENT"
    case electricResistance = "ELECTRIC_RESISTANCE"
}

struct UnitDefinitionV1: Codable, Equatable, Hashable, Sendable {
    let unitID: String
    let dimension: MeasurementDimensionV1
    let canonicalUnitID: String
    let multiplier: ExactRationalV1
    let offset: ExactRationalV1
    let canonicalScale: Int

    init(
        unitID: String,
        dimension: MeasurementDimensionV1,
        canonicalUnitID: String,
        multiplier: ExactRationalV1,
        offset: ExactRationalV1,
        canonicalScale: Int
    ) throws {
        guard ResponseIdentifierValidationV1.valid(unitID),
              ResponseIdentifierValidationV1.valid(canonicalUnitID),
              (0...ExactDecimalV1.maximumScale).contains(canonicalScale) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.unitID = unitID
        self.dimension = dimension
        self.canonicalUnitID = canonicalUnitID
        self.multiplier = multiplier
        self.offset = offset
        self.canonicalScale = canonicalScale
    }
}

enum KernelUnitRegistryV1 {
    static let schemaVersion = 1
    static let policyVersion = "KERNEL_UNIT_POLICY_V1"
    static let noFloatPersistence = true

    static let definitions: [UnitDefinitionV1] = {
        func rational(_ n: Int64, _ d: Int64 = 1) -> ExactRationalV1 {
            // Every literal below has a positive compile-time denominator.
            try! ExactRationalV1(numerator: n, denominator: d)
        }
        func unit(
            _ id: String,
            _ dimension: MeasurementDimensionV1,
            _ canonical: String,
            _ multiplier: ExactRationalV1,
            _ offset: ExactRationalV1 = rational(0),
            _ scale: Int
        ) -> UnitDefinitionV1 {
            // Frozen literals are validated again by validateFrozenRegistry().
            try! UnitDefinitionV1(
                unitID: id,
                dimension: dimension,
                canonicalUnitID: canonical,
                multiplier: multiplier,
                offset: offset,
                canonicalScale: scale
            )
        }
        return [
            unit("1", .dimensionless, "1", rational(1), 9),
            unit("A", .electricCurrent, "A", rational(1), 9),
            unit("[degF]", .temperature, "K", rational(5, 9), rational(45_967, 180), 6),
            unit("[fc_i]", .illuminance, "lx", rational(1_076_391, 100_000), 5),
            unit("[ft_i]", .length, "m", rational(381, 1_250), 9),
            unit("[in_i]", .length, "m", rational(127, 5_000), 9),
            unit("Cel", .temperature, "K", rational(1), rational(27_315, 100), 6),
            unit("K", .temperature, "K", rational(1), 6),
            unit("Ohm", .electricResistance, "Ohm", rational(1), 9),
            unit("V", .electricPotential, "V", rational(1), 9),
            unit("cm", .length, "m", rational(1, 100), 9),
            unit("h", .duration, "s", rational(3_600), 3),
            unit("lx", .illuminance, "lx", rational(1), 5),
            unit("m", .length, "m", rational(1), 9),
            unit("min", .duration, "s", rational(60), 3),
            unit("mm", .length, "m", rational(1, 1_000), 9),
            unit("ms", .duration, "s", rational(1, 1_000), 3),
            unit("kPa", .pressure, "kPa", rational(1), 9),
            unit("psi", .pressure, "kPa", rational(6_894_757_293, 1_000_000_000), 9),
            unit("s", .duration, "s", rational(1), 3),
        ].sorted { $0.unitID < $1.unitID }
    }()

    static func definition(unitID: String) throws -> UnitDefinitionV1 {
        let matches = definitions.filter { $0.unitID == unitID }
        guard matches.count == 1, let value = matches.first else {
            throw ResponseContractFailureV1.unsupportedUnit
        }
        return value
    }

    static func validateFrozenRegistry() throws {
        guard definitions.map(\.unitID) == definitions.map(\.unitID).sorted(),
              Set(definitions.map(\.unitID)).count == definitions.count else {
            throw ResponseContractFailureV1.duplicateIdentity
        }
        for value in definitions {
            guard try definition(unitID: value.canonicalUnitID).dimension == value.dimension,
                  value.multiplier.denominator > 0,
                  value.offset.denominator > 0 else {
                throw ResponseContractFailureV1.dimensionMismatch
            }
        }
    }
}

enum TiesToEvenRoundingDispositionV1: String, CaseIterable, Codable, Sendable {
    case exact = "EXACT"
    case nearestTowardZero = "NEAREST_TOWARD_ZERO"
    case nearestAwayFromZero = "NEAREST_AWAY_FROM_ZERO"
    case tieEvenUnchanged = "TIE_EVEN_UNCHANGED"
    case tieEvenAdjusted = "TIE_EVEN_ADJUSTED"
}

struct ExactRoundingReceiptV1: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let policy: String
    let sourceNumerator: Int64
    let sourceDenominator: Int64
    let targetScale: Int
    let truncatedMantissa: Int64
    let remainder: Int64
    let roundedMantissa: Int64
    let disposition: TiesToEvenRoundingDispositionV1
}

struct ExactConversionResultV1: Equatable, Hashable, Sendable {
    let canonicalValue: ExactDecimalV1
    let receipt: ExactRoundingReceiptV1
}

enum ExactUnitConverterV1 {
    static func convert(
        _ value: ExactDecimalV1,
        from unitID: String,
        policyVersion: String = KernelUnitRegistryV1.policyVersion
    ) throws -> ExactConversionResultV1 {
        guard policyVersion == KernelUnitRegistryV1.policyVersion else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        let unit = try KernelUnitRegistryV1.definition(unitID: unitID)
        let decimalDenominator = try ExactIntegerMathV1.powerOfTen(value.scale)
        let multipliedNumerator = try ExactIntegerMathV1.multiply(
            value.mantissa,
            unit.multiplier.numerator
        )
        let convertedDenominator = try ExactIntegerMathV1.multiply(
            decimalDenominator,
            unit.multiplier.denominator
        )
        let lhs = try ExactIntegerMathV1.multiply(
            multipliedNumerator,
            unit.offset.denominator
        )
        let rhsBase = try ExactIntegerMathV1.multiply(
            unit.offset.numerator,
            convertedDenominator
        )
        let numerator = try ExactIntegerMathV1.add(lhs, rhsBase)
        let denominator = try ExactIntegerMathV1.multiply(
            convertedDenominator,
            unit.offset.denominator
        )
        return try rounded(
            numerator: numerator,
            denominator: denominator,
            targetScale: unit.canonicalScale
        )
    }

    static func rounded(
        numerator: Int64,
        denominator: Int64,
        targetScale: Int
    ) throws -> ExactConversionResultV1 {
        guard denominator > 0 else { throw ResponseContractFailureV1.invalidValue }
        let factor = try ExactIntegerMathV1.powerOfTen(targetScale)
        let scaled = try ExactIntegerMathV1.multiply(numerator, factor)
        let quotient = scaled / denominator
        let remainder = scaled % denominator
        if remainder == 0 {
            return try result(
                numerator: numerator, denominator: denominator, targetScale: targetScale,
                quotient: quotient, remainder: remainder, rounded: quotient, disposition: .exact
            )
        }
        guard remainder != Int64.min else { throw ResponseContractFailureV1.arithmeticOverflow }
        let magnitude = Swift.abs(remainder)
        let doubled = try ExactIntegerMathV1.multiply(magnitude, 2)
        let direction: Int64 = scaled < 0 ? -1 : 1
        let roundedValue: Int64
        let disposition: TiesToEvenRoundingDispositionV1
        if doubled < denominator {
            roundedValue = quotient
            disposition = .nearestTowardZero
        } else if doubled > denominator {
            roundedValue = try ExactIntegerMathV1.add(quotient, direction)
            disposition = .nearestAwayFromZero
        } else if quotient.isMultiple(of: 2) {
            roundedValue = quotient
            disposition = .tieEvenUnchanged
        } else {
            roundedValue = try ExactIntegerMathV1.add(quotient, direction)
            disposition = .tieEvenAdjusted
        }
        return try result(
            numerator: numerator, denominator: denominator, targetScale: targetScale,
            quotient: quotient, remainder: remainder, rounded: roundedValue,
            disposition: disposition
        )
    }

    private static func result(
        numerator: Int64,
        denominator: Int64,
        targetScale: Int,
        quotient: Int64,
        remainder: Int64,
        rounded: Int64,
        disposition: TiesToEvenRoundingDispositionV1
    ) throws -> ExactConversionResultV1 {
        ExactConversionResultV1(
            canonicalValue: try ExactDecimalV1(mantissa: rounded, scale: targetScale),
            receipt: ExactRoundingReceiptV1(
                schemaVersion: 1,
                policy: "TIES_TO_EVEN_V1",
                sourceNumerator: numerator,
                sourceDenominator: denominator,
                targetScale: targetScale,
                truncatedMantissa: quotient,
                remainder: remainder,
                roundedMantissa: rounded,
                disposition: disposition
            )
        )
    }
}

enum MeasurementSourceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case manualEntry = "MANUAL_ENTRY"
    case instrumentObserved = "INSTRUMENT_OBSERVED"
    case imported = "IMPORTED"
    case derived = "DERIVED"
}

extension MeasurementSourceV1 {
    /// C19 capture is deliberately local/manual. Imported and derived values
    /// remain valid C03/C40 values but cannot masquerade as a field capture.
    var isLocalMeasurementCaptureSource: Bool {
        self == .manualEntry || self == .instrumentObserved
    }
}

struct ExactMeasurementV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let enteredValue: ExactDecimalV1
    let enteredUnitID: String
    let canonicalValue: ExactDecimalV1
    let canonicalUnitID: String
    let dimension: MeasurementDimensionV1
    let precisionScale: Int
    let uncertaintyCanonical: ExactDecimalV1?
    let source: MeasurementSourceV1
    let captureMethodID: String
    let conversionPolicyVersion: String
    let roundingReceipt: ExactRoundingReceiptV1

    init(
        enteredValue: ExactDecimalV1,
        enteredUnitID: String,
        precisionScale: Int,
        uncertaintyCanonical: ExactDecimalV1?,
        source: MeasurementSourceV1,
        captureMethodID: String,
        conversionPolicyVersion: String = KernelUnitRegistryV1.policyVersion
    ) throws {
        guard (0...ExactDecimalV1.maximumScale).contains(precisionScale),
              ResponseIdentifierValidationV1.valid(captureMethodID),
              uncertaintyCanonical.map({ $0.mantissa >= 0 }) ?? true else {
            throw ResponseContractFailureV1.invalidValue
        }
        guard precisionScale == enteredValue.scale else {
            throw ResponseContractFailureV1.precisionLoss
        }
        let definition = try KernelUnitRegistryV1.definition(unitID: enteredUnitID)
        let conversion = try ExactUnitConverterV1.convert(
            enteredValue,
            from: enteredUnitID,
            policyVersion: conversionPolicyVersion
        )
        schemaVersion = Self.schemaVersion
        self.enteredValue = enteredValue
        self.enteredUnitID = enteredUnitID
        canonicalValue = conversion.canonicalValue
        canonicalUnitID = definition.canonicalUnitID
        dimension = definition.dimension
        self.precisionScale = precisionScale
        self.uncertaintyCanonical = uncertaintyCanonical
        self.source = source
        self.captureMethodID = captureMethodID
        self.conversionPolicyVersion = conversionPolicyVersion
        roundingReceipt = conversion.receipt
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        let expected = try ExactMeasurementV1(
            enteredValue: enteredValue,
            enteredUnitID: enteredUnitID,
            precisionScale: precisionScale,
            uncertaintyCanonical: uncertaintyCanonical,
            source: source,
            captureMethodID: captureMethodID,
            conversionPolicyVersion: conversionPolicyVersion
        )
        guard expected == self else { throw ResponseContractFailureV1.invalidValue }
    }
}

enum ExactIntegerMathV1 {
    static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw ResponseContractFailureV1.arithmeticOverflow }
        return result.partialValue
    }

    static func multiply(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw ResponseContractFailureV1.arithmeticOverflow }
        return result.partialValue
    }

    static func powerOfTen(_ exponent: Int) throws -> Int64 {
        guard (0...ExactDecimalV1.maximumScale).contains(exponent) else {
            throw ResponseContractFailureV1.invalidValue
        }
        var value: Int64 = 1
        for _ in 0..<exponent { value = try multiply(value, 10) }
        return value
    }
}

enum ResponseIdentifierValidationV1 {
    static let maximumUTF8Bytes = 128
    static func valid(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumUTF8Bytes else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x2E
                || $0 == 0x5F || $0 == 0x5B || $0 == 0x5D
        }
    }
}

extension ExactDecimalV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case mantissa, scale }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(mantissa: c.decode(Int64.self, forKey: .mantissa), scale: c.decode(Int.self, forKey: .scale))
    }
}

extension ExactRationalV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case numerator, denominator }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(numerator: c.decode(Int64.self, forKey: .numerator), denominator: c.decode(Int64.self, forKey: .denominator))
    }
}

extension UnitDefinitionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case unitID, dimension, canonicalUnitID, multiplier, offset, canonicalScale
    }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            unitID: c.decode(String.self, forKey: .unitID),
            dimension: c.decode(MeasurementDimensionV1.self, forKey: .dimension),
            canonicalUnitID: c.decode(String.self, forKey: .canonicalUnitID),
            multiplier: c.decode(ExactRationalV1.self, forKey: .multiplier),
            offset: c.decode(ExactRationalV1.self, forKey: .offset),
            canonicalScale: c.decode(Int.self, forKey: .canonicalScale)
        )
    }
}

extension ExactRoundingReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, policy, sourceNumerator, sourceDenominator, targetScale
        case truncatedMantissa, remainder, roundedMantissa, disposition
    }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        policy = try c.decode(String.self, forKey: .policy)
        sourceNumerator = try c.decode(Int64.self, forKey: .sourceNumerator)
        sourceDenominator = try c.decode(Int64.self, forKey: .sourceDenominator)
        targetScale = try c.decode(Int.self, forKey: .targetScale)
        truncatedMantissa = try c.decode(Int64.self, forKey: .truncatedMantissa)
        remainder = try c.decode(Int64.self, forKey: .remainder)
        roundedMantissa = try c.decode(Int64.self, forKey: .roundedMantissa)
        disposition = try c.decode(TiesToEvenRoundingDispositionV1.self, forKey: .disposition)
        guard schemaVersion == 1, policy == "TIES_TO_EVEN_V1",
              sourceDenominator > 0,
              (0...ExactDecimalV1.maximumScale).contains(targetScale) else {
            throw ResponseContractFailureV1.invalidValue
        }
    }
}

extension ExactMeasurementV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, enteredValue, enteredUnitID, canonicalValue, canonicalUnitID
        case dimension, precisionScale, uncertaintyCanonical, source, captureMethodID
        case conversionPolicyVersion, roundingReceipt
    }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        let expected = try Self.init(
            enteredValue: c.decode(ExactDecimalV1.self, forKey: .enteredValue),
            enteredUnitID: c.decode(String.self, forKey: .enteredUnitID),
            precisionScale: c.decode(Int.self, forKey: .precisionScale),
            uncertaintyCanonical: c.decodeIfPresent(ExactDecimalV1.self, forKey: .uncertaintyCanonical),
            source: c.decode(MeasurementSourceV1.self, forKey: .source),
            captureMethodID: c.decode(String.self, forKey: .captureMethodID),
            conversionPolicyVersion: c.decode(String.self, forKey: .conversionPolicyVersion)
        )
        guard expected.canonicalValue == c.decode(ExactDecimalV1.self, forKey: .canonicalValue),
              expected.canonicalUnitID == c.decode(String.self, forKey: .canonicalUnitID),
              expected.dimension == c.decode(MeasurementDimensionV1.self, forKey: .dimension),
              expected.roundingReceipt == c.decode(ExactRoundingReceiptV1.self, forKey: .roundingReceipt) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self = expected
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(enteredValue, forKey: .enteredValue)
        try c.encode(enteredUnitID, forKey: .enteredUnitID)
        try c.encode(canonicalValue, forKey: .canonicalValue)
        try c.encode(canonicalUnitID, forKey: .canonicalUnitID)
        try c.encode(dimension, forKey: .dimension)
        try c.encode(precisionScale, forKey: .precisionScale)
        if let uncertaintyCanonical {
            try c.encode(uncertaintyCanonical, forKey: .uncertaintyCanonical)
        } else {
            try c.encodeNil(forKey: .uncertaintyCanonical)
        }
        try c.encode(source, forKey: .source)
        try c.encode(captureMethodID, forKey: .captureMethodID)
        try c.encode(conversionPolicyVersion, forKey: .conversionPolicyVersion)
        try c.encode(roundingReceipt, forKey: .roundingReceipt)
    }
}

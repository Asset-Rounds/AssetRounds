import Foundation

struct ResponseCardinalityV1: Codable, Equatable, Sendable {
    static let maximumResponses = 128
    let minimum: Int
    let maximum: Int

    init(minimum: Int, maximum: Int) throws {
        guard minimum >= 0, maximum >= minimum,
              maximum <= Self.maximumResponses else {
            throw ResponseContractFailureV1.cardinalityViolation
        }
        self.minimum = minimum
        self.maximum = maximum
    }
}

extension ResponseFieldDefinitionV1 {
    func validateSurveyFact(_ fact: FactDefinitionV1) throws {
        try fact.validate(); try validate()
        guard fieldID == fact.factID else { throw ResponseContractFailureV1.invalidValue }
        let permitted: Set<ResponseValueKindV1>
        switch fact.kind {
        case .instruction: permitted = [.noValue]
        case .shortText, .longText: permitted = [.text]
        case .integer: permitted = [.integer]
        case .decimal: permitted = [.decimal]
        case .measurement: permitted = [.measurement]
        case .booleanObservation: permitted = [.triState]
        case .singleChoice: permitted = [.singleOption]
        case .multipleChoice: permitted = [.multipleOptions]
        case .date: permitted = [.localDate]
        case .time: permitted = [.localTime]
        case .subjectReference, .locator: permitted = [.entityReference]
        case .oneShotLocation, .normalizedPlanPlacement, .evidenceRequest: permitted = [.contentReference]
        case .repeatableGroup: permitted = [.noValue]
        case .attributedAcknowledgement: permitted = [.boolean]
        }
        guard permitted.contains(valueKind) else { throw ResponseContractFailureV1.invalidValue }
    }
}

struct ResponseFieldDefinitionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let fieldID: String
    let packageReleaseID: String
    let workflowSHA256: String
    let valueKind: ResponseValueKindV1
    let cardinality: ResponseCardinalityV1
    let allowsNotApplicable: Bool
    let allowsUnknownTriState: Bool
    let maximumTextUTF8Bytes: Int?
    let allowedOptionIDs: [String]
    let minimumNumericValue: ExactDecimalV1?
    let maximumNumericValue: ExactDecimalV1?
    let measurementDimension: MeasurementDimensionV1?
    let allowedUnitIDs: [String]
    let maximumPrecisionScale: Int?
    let maximumUncertaintyCanonical: ExactDecimalV1?
    let repeatNodeID: String?
    let allowedEntityKindIDs: [String]

    init(
        fieldID: String,
        packageReleaseID: String,
        workflowSHA256: String,
        valueKind: ResponseValueKindV1,
        cardinality: ResponseCardinalityV1,
        allowsNotApplicable: Bool = false,
        allowsUnknownTriState: Bool = true,
        maximumTextUTF8Bytes: Int? = nil,
        allowedOptionIDs: [String] = [],
        minimumNumericValue: ExactDecimalV1? = nil,
        maximumNumericValue: ExactDecimalV1? = nil,
        measurementDimension: MeasurementDimensionV1? = nil,
        allowedUnitIDs: [String] = [],
        maximumPrecisionScale: Int? = nil,
        maximumUncertaintyCanonical: ExactDecimalV1? = nil,
        repeatNodeID: String? = nil,
        allowedEntityKindIDs: [String] = []
    ) throws {
        schemaVersion = Self.schemaVersion
        self.fieldID = fieldID
        self.packageReleaseID = packageReleaseID
        self.workflowSHA256 = workflowSHA256
        self.valueKind = valueKind
        self.cardinality = cardinality
        self.allowsNotApplicable = allowsNotApplicable
        self.allowsUnknownTriState = allowsUnknownTriState
        self.maximumTextUTF8Bytes = maximumTextUTF8Bytes
        self.allowedOptionIDs = allowedOptionIDs
        self.minimumNumericValue = minimumNumericValue
        self.maximumNumericValue = maximumNumericValue
        self.measurementDimension = measurementDimension
        self.allowedUnitIDs = allowedUnitIDs
        self.maximumPrecisionScale = maximumPrecisionScale
        self.maximumUncertaintyCanonical = maximumUncertaintyCanonical
        self.repeatNodeID = repeatNodeID
        self.allowedEntityKindIDs = allowedEntityKindIDs
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        guard ResponseIdentifierValidationV1.valid(fieldID),
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              KernelCanonicalHashV1.validSHA256(workflowSHA256),
              valueKind != .noValue, valueKind != .notApplicable,
              repeatNodeID.map(ResponseIdentifierValidationV1.valid) ?? true,
              allowedOptionIDs == allowedOptionIDs.sorted(),
              Set(allowedOptionIDs).count == allowedOptionIDs.count,
              allowedOptionIDs.allSatisfy(ResponseIdentifierValidationV1.valid),
              allowedUnitIDs == allowedUnitIDs.sorted(),
              Set(allowedUnitIDs).count == allowedUnitIDs.count,
              allowedEntityKindIDs == allowedEntityKindIDs.sorted(),
              Set(allowedEntityKindIDs).count == allowedEntityKindIDs.count,
              allowedEntityKindIDs.allSatisfy(ResponseIdentifierValidationV1.valid) else {
            throw ResponseContractFailureV1.invalidValue
        }
        _ = try ResponseCardinalityV1(
            minimum: cardinality.minimum,
            maximum: cardinality.maximum
        )
        if let minimumNumericValue, let maximumNumericValue,
           try minimumNumericValue.compared(to: maximumNumericValue) == .orderedDescending {
            throw ResponseContractFailureV1.rangeViolation
        }
        if let maximumUncertaintyCanonical, maximumUncertaintyCanonical.mantissa < 0 {
            throw ResponseContractFailureV1.rangeViolation
        }
        switch valueKind {
        case .singleOption, .multipleOptions:
            guard !allowedOptionIDs.isEmpty else {
                throw ResponseContractFailureV1.invalidValue
            }
        default:
            guard allowedOptionIDs.isEmpty else {
                throw ResponseContractFailureV1.invalidValue
            }
        }
        if valueKind == .text {
            guard let maximumTextUTF8Bytes,
                  (0...ResponseValueV1.maximumTextUTF8Bytes).contains(maximumTextUTF8Bytes) else {
                throw ResponseContractFailureV1.limitExceeded
            }
        } else if maximumTextUTF8Bytes != nil {
            throw ResponseContractFailureV1.invalidValue
        }
        if valueKind == .measurement {
            guard let measurementDimension, !allowedUnitIDs.isEmpty,
                  let maximumPrecisionScale,
                  (0...ExactDecimalV1.maximumScale).contains(maximumPrecisionScale) else {
                throw ResponseContractFailureV1.invalidValue
            }
            for unitID in allowedUnitIDs {
                guard try KernelUnitRegistryV1.definition(unitID: unitID).dimension
                    == measurementDimension else {
                    throw ResponseContractFailureV1.dimensionMismatch
                }
            }
        } else if measurementDimension != nil || !allowedUnitIDs.isEmpty
                    || maximumPrecisionScale != nil || maximumUncertaintyCanonical != nil {
            throw ResponseContractFailureV1.invalidValue
        }
        if valueKind == .entityReference {
            guard !allowedEntityKindIDs.isEmpty else {
                throw ResponseContractFailureV1.invalidValue
            }
        } else if !allowedEntityKindIDs.isEmpty {
            throw ResponseContractFailureV1.invalidValue
        }
        let numericKinds: Set<ResponseValueKindV1> = [.integer, .decimal, .measurement]
        if !numericKinds.contains(valueKind),
           minimumNumericValue != nil || maximumNumericValue != nil {
            throw ResponseContractFailureV1.invalidValue
        }
    }
}

struct RepeatResponseBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let repeatInstanceID: RepeatInstanceIDV1
    let repeatNodeID: String
    let stableOrder: Int
    let activity: WorkflowPathActivityV1
    let packageReleaseID: String
    let workflowSHA256: String

    init(
        instanceState: RepeatInstanceStateV1,
        packageReleaseID: String,
        workflowSHA256: String
    ) throws {
        schemaVersion = Self.schemaVersion
        repeatInstanceID = instanceState.instanceID
        repeatNodeID = instanceState.repeatNodeID
        stableOrder = instanceState.stableOrder
        activity = instanceState.activity
        self.packageReleaseID = packageReleaseID
        self.workflowSHA256 = workflowSHA256
        try validate()
    }

    var satisfiesCompletion: Bool { activity == .active }
    var includedInReporting: Bool { activity == .active }
    var requiresReview: Bool { activity == .reactivationReviewRequired }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              ResponseIdentifierValidationV1.valid(repeatInstanceID.rawValue),
              ResponseIdentifierValidationV1.valid(repeatNodeID),
              stableOrder >= 0, stableOrder < WorkflowGrammarLimitsV1.maximumRepeatCount,
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              KernelCanonicalHashV1.validSHA256(workflowSHA256) else {
            throw ResponseContractFailureV1.invalidValue
        }
    }
}

struct BoundResponseValueV1: Codable, Equatable, Sendable {
    let fieldID: String
    let value: ResponseValueV1
    let repeatBinding: RepeatResponseBindingV1?

    init(
        fieldID: String,
        value: ResponseValueV1,
        repeatBinding: RepeatResponseBindingV1? = nil
    ) throws {
        guard ResponseIdentifierValidationV1.valid(fieldID) else {
            throw ResponseContractFailureV1.invalidValue
        }
        self.fieldID = fieldID
        self.value = value
        self.repeatBinding = repeatBinding
        try value.validate()
        try repeatBinding?.validate()
    }

    var stableIdentity: String {
        "\(fieldID)|\(repeatBinding?.repeatInstanceID.rawValue ?? "NONREPEAT")"
    }
}

enum ResponseFieldValidatorV1 {
    static func validate(
        _ response: BoundResponseValueV1,
        against definition: ResponseFieldDefinitionV1
    ) throws {
        try definition.validate()
        try response.value.validate()
        guard response.fieldID == definition.fieldID else {
            throw ResponseContractFailureV1.invalidValue
        }
        if let repeatNodeID = definition.repeatNodeID {
            guard let binding = response.repeatBinding,
                  binding.repeatNodeID == repeatNodeID,
                  binding.packageReleaseID == definition.packageReleaseID,
                  binding.workflowSHA256 == definition.workflowSHA256 else {
                throw ResponseContractFailureV1.hashMismatch
            }
        } else if response.repeatBinding != nil {
            throw ResponseContractFailureV1.invalidValue
        }
        switch response.value {
        case .noValue:
            guard definition.cardinality.minimum == 0 else {
                throw ResponseContractFailureV1.cardinalityViolation
            }
            return
        case .notApplicable:
            guard definition.allowsNotApplicable else {
                throw ResponseContractFailureV1.invalidValue
            }
            return
        default:
            guard response.value.kind == definition.valueKind else {
                throw ResponseContractFailureV1.invalidValue
            }
        }
        switch response.value {
        case .triState(.unknown):
            guard definition.allowsUnknownTriState else {
                throw ResponseContractFailureV1.invalidValue
            }
        case .singleOption(let optionID):
            guard definition.allowedOptionIDs.contains(optionID) else {
                throw ResponseContractFailureV1.invalidValue
            }
        case .multipleOptions(let optionIDs):
            guard Set(optionIDs).isSubset(of: Set(definition.allowedOptionIDs)) else {
                throw ResponseContractFailureV1.invalidValue
            }
        case .text(let text):
            guard let maximum = definition.maximumTextUTF8Bytes,
                  text.utf8.count <= maximum else {
                throw ResponseContractFailureV1.limitExceeded
            }
        case .integer(let integer):
            try validateNumeric(try ExactDecimalV1(mantissa: integer, scale: 0), definition)
        case .decimal(let decimal):
            try validateNumeric(decimal, definition)
        case .measurement(let measurement):
            try measurement.validate()
            guard measurement.dimension == definition.measurementDimension else {
                throw ResponseContractFailureV1.dimensionMismatch
            }
            guard definition.allowedUnitIDs.contains(measurement.enteredUnitID) else {
                throw ResponseContractFailureV1.unsupportedUnit
            }
            guard measurement.precisionScale <= (definition.maximumPrecisionScale ?? -1) else {
                throw ResponseContractFailureV1.precisionLoss
            }
            if let maximum = definition.maximumUncertaintyCanonical,
               let uncertainty = measurement.uncertaintyCanonical,
               try uncertainty.compared(to: maximum) == .orderedDescending {
                throw ResponseContractFailureV1.rangeViolation
            }
            try validateNumeric(measurement.canonicalValue, definition)
        case .entityReference(let reference):
            guard definition.allowedEntityKindIDs.contains(reference.entityKindID) else {
                throw ResponseContractFailureV1.invalidValue
            }
        default:
            break
        }
    }

    static func validateCollection(
        _ responses: [BoundResponseValueV1],
        definitions: [ResponseFieldDefinitionV1]
    ) throws {
        guard responses.count <= ResponseCardinalityV1.maximumResponses,
              definitions.map(\.fieldID) == definitions.map(\.fieldID).sorted(),
              Set(definitions.map(\.fieldID)).count == definitions.count,
              Set(responses.map(\.stableIdentity)).count == responses.count else {
            throw ResponseContractFailureV1.duplicateIdentity
        }
        var bindingByInstanceID: [String: RepeatResponseBindingV1] = [:]
        var instanceByOrder: [String: String] = [:]
        for response in responses {
            guard let binding = response.repeatBinding else { continue }
            let instanceID = binding.repeatInstanceID.rawValue
            if let prior = bindingByInstanceID[instanceID], prior != binding {
                throw ResponseContractFailureV1.duplicateIdentity
            }
            bindingByInstanceID[instanceID] = binding
            let orderKey = "\(binding.packageReleaseID)|\(binding.workflowSHA256)|\(binding.repeatNodeID)|\(binding.stableOrder)"
            if let priorID = instanceByOrder[orderKey], priorID != instanceID {
                throw ResponseContractFailureV1.duplicateIdentity
            }
            instanceByOrder[orderKey] = instanceID
        }
        let byField = Dictionary(uniqueKeysWithValues: definitions.map { ($0.fieldID, $0) })
        for response in responses {
            guard let definition = byField[response.fieldID] else {
                throw ResponseContractFailureV1.invalidValue
            }
            try validate(response, against: definition)
        }
        for definition in definitions {
            let count = responses.filter { response in
                guard response.fieldID == definition.fieldID else { return false }
                if case .noValue = response.value { return false }
                return true
            }.count
            guard (definition.cardinality.minimum...definition.cardinality.maximum).contains(count) else {
                throw ResponseContractFailureV1.cardinalityViolation
            }
        }
    }

    static func canonicalOrder(
        _ responses: [BoundResponseValueV1],
        definitions: [ResponseFieldDefinitionV1]
    ) throws -> [BoundResponseValueV1] {
        try validateCollection(responses, definitions: definitions)
        return responses.sorted {
            let lhsOrder = $0.repeatBinding?.stableOrder ?? -1
            let rhsOrder = $1.repeatBinding?.stableOrder ?? -1
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return $0.stableIdentity < $1.stableIdentity
        }
    }

    private static func validateNumeric(
        _ value: ExactDecimalV1,
        _ definition: ResponseFieldDefinitionV1
    ) throws {
        if let minimum = definition.minimumNumericValue,
           try value.compared(to: minimum) == .orderedAscending {
            throw ResponseContractFailureV1.rangeViolation
        }
        if let maximum = definition.maximumNumericValue,
           try value.compared(to: maximum) == .orderedDescending {
            throw ResponseContractFailureV1.rangeViolation
        }
    }
}

// MARK: - C19 measurement capture bridge

extension ResponseFieldValidatorV1 {
    /// Validates the C19 fixed-point capture against the exact field contract
    /// while retaining the existing response validator as the sole field
    /// admission path.
    static func validateMeasurementCapture(
        _ capture: MeasurementCaptureV1,
        against definition: ResponseFieldDefinitionV1
    ) throws {
        try definition.validate()
        guard definition.valueKind == .measurement else {
            throw MeasurementIntegrityFailureV1.invalidValue
        }
        try capture.validate(fieldDefinition: definition)
        try capture.response.value.c19ValidateMeasurementEquality(capture.measurement)
    }
}

extension ResponseFieldDefinitionV1 {
    func validateMeasurementCapture(_ capture: MeasurementCaptureV1) throws {
        try ResponseFieldValidatorV1.validateMeasurementCapture(capture, against: self)
    }
}

// MARK: - C20 reviewed-derivative response binding

extension ResponseFieldValidatorV1 {
    /// Content responses are admitted through the existing field validator,
    /// then require the exact C20 reviewed derivative before they can be used
    /// by an audience projection. This does not alter response persistence or
    /// make a privacy/compliance decision.
    static func c20ValidateReviewedDerivative(
        _ response: BoundResponseValueV1,
        against definition: ResponseFieldDefinitionV1,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        try validate(response, against: definition)
        guard definition.valueKind == .contentReference else {
            throw PrivacyTransformFailureV1.invalidValue
        }
        return try response.value.c20ValidateReviewedDerivative(
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

extension ResponseFieldDefinitionV1 {
    func c20ValidateReviewedDerivative(
        _ response: BoundResponseValueV1,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        try ResponseFieldValidatorV1.c20ValidateReviewedDerivative(
            response,
            against: self,
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

struct KernelResponseRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let contractSchema: String
    let responseKinds: [String]
    let unitPolicyVersion: String
    let unitIDs: [String]
    let fieldDefinitions: [ResponseFieldDefinitionV1]

    init(fieldDefinitions: [ResponseFieldDefinitionV1]) throws {
        schemaVersion = Self.schemaVersion
        contractSchema = "KERNEL_RESPONSE_V1"
        responseKinds = ResponseValueKindV1.allCases.map(\.rawValue).sorted()
        unitPolicyVersion = KernelUnitRegistryV1.policyVersion
        unitIDs = KernelUnitRegistryV1.definitions.map(\.unitID)
        self.fieldDefinitions = fieldDefinitions.sorted { $0.fieldID < $1.fieldID }
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              contractSchema == "KERNEL_RESPONSE_V1",
              responseKinds == ResponseValueKindV1.allCases.map(\.rawValue).sorted(),
              unitPolicyVersion == KernelUnitRegistryV1.policyVersion,
              unitIDs == KernelUnitRegistryV1.definitions.map(\.unitID),
              fieldDefinitions.map(\.fieldID) == fieldDefinitions.map(\.fieldID).sorted(),
              Set(fieldDefinitions.map(\.fieldID)).count == fieldDefinitions.count else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        try KernelUnitRegistryV1.validateFrozenRegistry()
        try fieldDefinitions.forEach { try $0.validate() }
    }
}

struct KernelResponseRegistryPublicationReceiptV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let canonicalSHA256: String
    let canonicalByteCount: Int
    let fieldCount: Int
    let complete: Bool
}

enum KernelResponseRegistryCanonicalCodecV1 {
    static let maximumCanonicalBytes = 1_048_576
    static func encode(_ value: KernelResponseRegistryV1) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximumCanonicalBytes else {
            throw ResponseContractFailureV1.limitExceeded
        }
        return data
    }
    static func decode(_ data: Data) throws -> KernelResponseRegistryV1 {
        guard !data.isEmpty, data.count <= maximumCanonicalBytes else {
            throw ResponseContractFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(KernelResponseRegistryV1.self, from: data)
        guard try encode(value) == data else { throw ResponseContractFailureV1.invalidValue }
        return value
    }
}

enum KernelResponseRegistryPublisherV1 {
    enum Boundary: String, CaseIterable, Sendable {
        case beforeValidation = "BEFORE_VALIDATION"
        case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
        case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
    }
    typealias Interruption = @Sendable (Boundary) throws -> Void

    static func publish(
        fieldDefinitions: [ResponseFieldDefinitionV1],
        interruption: Interruption = { _ in }
    ) throws -> (registry: KernelResponseRegistryV1, receipt: KernelResponseRegistryPublicationReceiptV1) {
        try interruption(.beforeValidation)
        let registry = try KernelResponseRegistryV1(fieldDefinitions: fieldDefinitions)
        let bytes = try KernelResponseRegistryCanonicalCodecV1.encode(registry)
        try interruption(.afterValidationBeforePublication)
        let receipt = KernelResponseRegistryPublicationReceiptV1(
            schemaVersion: 1,
            canonicalSHA256: KernelCanonicalHashV1.sha256(bytes),
            canonicalByteCount: bytes.count,
            fieldCount: registry.fieldDefinitions.count,
            complete: true
        )
        try interruption(.afterPublicationBeforeReceipt)
        return (registry, receipt)
    }

    static func recover(
        canonicalData: Data,
        receipt: KernelResponseRegistryPublicationReceiptV1
    ) throws -> KernelResponseRegistryV1 {
        guard receipt.schemaVersion == 1, receipt.complete,
              receipt.canonicalByteCount == canonicalData.count,
              receipt.canonicalSHA256 == KernelCanonicalHashV1.sha256(canonicalData) else {
            throw ResponseContractFailureV1.hashMismatch
        }
        let registry = try KernelResponseRegistryCanonicalCodecV1.decode(canonicalData)
        guard receipt.fieldCount == registry.fieldDefinitions.count else {
            throw ResponseContractFailureV1.hashMismatch
        }
        return registry
    }
}

enum KernelResponseLifecycleV1 {
    static let mode = "DECLARATION_ONLY"
    static let schema = "KERNEL_RESPONSE_V1"
    static let persistent = false
    static let writerCommandRequired = false
    static let canonicalQueryRequired = false
    static let migrationRequired = false
    static let backupRestoreRequired = false
    static let cloneForkRequired = false
    static let importExportRequired = false
    static let journalReplayRequired = false
    static let searchRebuildReplayRequired = false
    static let deleteEraseRequired = false
    static let retentionRequired = false
    static let compatibilityWriteRequired = false
    static let downgradePolicy = "DORMANT_REVERT_ALLOWED"
    static let forwardFixRequired = false
    static let interruption = "ZERO_OR_COMPLETE"
    static let idempotentReceipt = "EXACT_CANONICAL_BYTES_ADOPTION"
    static let repeatReactivationDisposition = "REACTIVATION_REVIEW_REQUIRED"
    static let shippingAdoption = "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION"
}

extension ResponseCardinalityV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case minimum, maximum }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(minimum: c.decode(Int.self, forKey: .minimum), maximum: c.decode(Int.self, forKey: .maximum))
    }
}

extension ResponseFieldDefinitionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, fieldID, packageReleaseID, workflowSHA256, valueKind
        case cardinality, allowsNotApplicable, allowsUnknownTriState, maximumTextUTF8Bytes
        case allowedOptionIDs, minimumNumericValue, maximumNumericValue, measurementDimension
        case allowedUnitIDs, maximumPrecisionScale, maximumUncertaintyCanonical
        case repeatNodeID, allowedEntityKindIDs
    }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        try self.init(
            fieldID: c.decode(String.self, forKey: .fieldID),
            packageReleaseID: c.decode(String.self, forKey: .packageReleaseID),
            workflowSHA256: c.decode(String.self, forKey: .workflowSHA256),
            valueKind: c.decode(ResponseValueKindV1.self, forKey: .valueKind),
            cardinality: c.decode(ResponseCardinalityV1.self, forKey: .cardinality),
            allowsNotApplicable: c.decode(Bool.self, forKey: .allowsNotApplicable),
            allowsUnknownTriState: c.decode(Bool.self, forKey: .allowsUnknownTriState),
            maximumTextUTF8Bytes: c.decodeIfPresent(Int.self, forKey: .maximumTextUTF8Bytes),
            allowedOptionIDs: c.decode([String].self, forKey: .allowedOptionIDs),
            minimumNumericValue: c.decodeIfPresent(ExactDecimalV1.self, forKey: .minimumNumericValue),
            maximumNumericValue: c.decodeIfPresent(ExactDecimalV1.self, forKey: .maximumNumericValue),
            measurementDimension: c.decodeIfPresent(MeasurementDimensionV1.self, forKey: .measurementDimension),
            allowedUnitIDs: c.decode([String].self, forKey: .allowedUnitIDs),
            maximumPrecisionScale: c.decodeIfPresent(Int.self, forKey: .maximumPrecisionScale),
            maximumUncertaintyCanonical: c.decodeIfPresent(ExactDecimalV1.self, forKey: .maximumUncertaintyCanonical),
            repeatNodeID: c.decodeIfPresent(String.self, forKey: .repeatNodeID),
            allowedEntityKindIDs: c.decode([String].self, forKey: .allowedEntityKindIDs)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(fieldID, forKey: .fieldID)
        try c.encode(packageReleaseID, forKey: .packageReleaseID)
        try c.encode(workflowSHA256, forKey: .workflowSHA256)
        try c.encode(valueKind, forKey: .valueKind)
        try c.encode(cardinality, forKey: .cardinality)
        try c.encode(allowsNotApplicable, forKey: .allowsNotApplicable)
        try c.encode(allowsUnknownTriState, forKey: .allowsUnknownTriState)
        try Self.encodeOptional(maximumTextUTF8Bytes, key: .maximumTextUTF8Bytes, into: &c)
        try c.encode(allowedOptionIDs, forKey: .allowedOptionIDs)
        try Self.encodeOptional(minimumNumericValue, key: .minimumNumericValue, into: &c)
        try Self.encodeOptional(maximumNumericValue, key: .maximumNumericValue, into: &c)
        try Self.encodeOptional(measurementDimension, key: .measurementDimension, into: &c)
        try c.encode(allowedUnitIDs, forKey: .allowedUnitIDs)
        try Self.encodeOptional(maximumPrecisionScale, key: .maximumPrecisionScale, into: &c)
        try Self.encodeOptional(maximumUncertaintyCanonical, key: .maximumUncertaintyCanonical, into: &c)
        try Self.encodeOptional(repeatNodeID, key: .repeatNodeID, into: &c)
        try c.encode(allowedEntityKindIDs, forKey: .allowedEntityKindIDs)
    }

    private static func encodeOptional<T: Encodable>(
        _ value: T?,
        key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value { try container.encode(value, forKey: key) }
        else { try container.encodeNil(forKey: key) }
    }
}

extension RepeatResponseBindingV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, repeatInstanceID, repeatNodeID, stableOrder, activity
        case packageReleaseID, workflowSHA256
    }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        let state = try RepeatInstanceStateV1(
            instanceID: c.decode(RepeatInstanceIDV1.self, forKey: .repeatInstanceID),
            repeatNodeID: c.decode(String.self, forKey: .repeatNodeID),
            stableOrder: c.decode(Int.self, forKey: .stableOrder),
            activity: c.decode(WorkflowPathActivityV1.self, forKey: .activity)
        )
        try self.init(
            instanceState: state,
            packageReleaseID: c.decode(String.self, forKey: .packageReleaseID),
            workflowSHA256: c.decode(String.self, forKey: .workflowSHA256)
        )
    }
}

extension BoundResponseValueV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case fieldID, value, repeatBinding }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireClosed(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            required: [CodingKeys.fieldID.rawValue, CodingKeys.value.rawValue]
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fieldID: c.decode(String.self, forKey: .fieldID),
            value: c.decode(ResponseValueV1.self, forKey: .value),
            repeatBinding: c.decodeIfPresent(RepeatResponseBindingV1.self, forKey: .repeatBinding)
        )
    }
}

extension KernelResponseRegistryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, contractSchema, responseKinds, unitPolicyVersion, unitIDs, fieldDefinitions
    }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .contractSchema) == "KERNEL_RESPONSE_V1",
              try c.decode([String].self, forKey: .responseKinds) == ResponseValueKindV1.allCases.map(\.rawValue).sorted(),
              try c.decode(String.self, forKey: .unitPolicyVersion) == KernelUnitRegistryV1.policyVersion,
              try c.decode([String].self, forKey: .unitIDs) == KernelUnitRegistryV1.definitions.map(\.unitID) else {
            throw ResponseContractFailureV1.incompatibleVersion
        }
        try self.init(fieldDefinitions: c.decode([ResponseFieldDefinitionV1].self, forKey: .fieldDefinitions))
    }
}

extension KernelResponseRegistryPublicationReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, canonicalSHA256, canonicalByteCount, fieldCount, complete
    }
    init(from decoder: any Decoder) throws {
        try ResponseClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        canonicalSHA256 = try c.decode(String.self, forKey: .canonicalSHA256)
        canonicalByteCount = try c.decode(Int.self, forKey: .canonicalByteCount)
        fieldCount = try c.decode(Int.self, forKey: .fieldCount)
        complete = try c.decode(Bool.self, forKey: .complete)
        guard schemaVersion == 1, KernelCanonicalHashV1.validSHA256(canonicalSHA256),
              canonicalByteCount > 0, fieldCount >= 0, complete else {
            throw ResponseContractFailureV1.invalidValue
        }
    }
}

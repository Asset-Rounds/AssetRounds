import Foundation

enum GuidedSurveyContractManifestBoundaryV1 {
    static let projectionTypeID = "SurveyPublicationReportProjectionV1"
    static let surveyOutcomeSemantics = "COMPLETION_ONLY_NO_PASS_FAIL"
}

enum C50IncumbentContractManifestBoundaryV1 {
    static let adapterExportIsDerived = true
    static let selectedProfileEvidenceIsNonpersistent = true
    static let providerSuccessClaimIsForbidden = true
}

enum C47ActivityContractConformance_FieldEvidenceApp_Domain_Reporting_ContractManifestV1_swift {
    static let integrationRole = "REPORT_CONTRACT_MANIFEST"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingReportInfrastructure = true
    static let createsSecondRendererWriterOrStore = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

private struct ContractManifestCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension ContractManifestV1{
    func accessibleDocumentManifestSHA256()throws->String{try validate();return try WorkspaceMutationCanonicalV1.sha256(self)}
}

private enum ContractManifestDecodingV1 {
    static func rejectUnknownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
        let keys = try decoder.container(keyedBy: ContractManifestCodingKeyV1.self).allKeys.map(\.stringValue)
        guard Set(keys).isSubset(of: allowed) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

enum ContractUnknownFieldPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case reject = "REJECT"
    case preserve = "PRESERVE"
}

enum ContractEnumPolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case closed = "CLOSED"
    case preserveUnknown = "PRESERVE_UNKNOWN"
}

enum ContractScalarKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case base64Bytes = "BASE64_BYTES"
    case string = "STRING"
    case integer = "INTEGER"
    case boolean = "BOOLEAN"
    case utcInstant = "UTC_INSTANT"
    case sha256 = "SHA256"
    case object = "OBJECT"
    case array = "ARRAY"
    case enumeration = "ENUM"
}

struct ContractFieldDefinitionV1: Codable, Equatable, Hashable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fieldID, jsonName, kind, arrayElementKind, required, nullable, referencedTypeID
        case minimumInteger, maximumInteger, maximumUTF8Bytes, maximumItems, ordered, uniqueItems
    }

    let fieldID: String
    let jsonName: String
    let kind: ContractScalarKindV1
    let arrayElementKind: ContractScalarKindV1?
    let required: Bool
    let nullable: Bool
    let referencedTypeID: String?
    let minimumInteger: Int64?
    let maximumInteger: Int64?
    let maximumUTF8Bytes: Int?
    let maximumItems: Int?
    let ordered: Bool
    let uniqueItems: Bool

    static func < (lhs: ContractFieldDefinitionV1, rhs: ContractFieldDefinitionV1) -> Bool {
        lhs.fieldID < rhs.fieldID
    }

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fieldID = try values.decode(String.self, forKey: .fieldID)
        jsonName = try values.decode(String.self, forKey: .jsonName)
        kind = try values.decode(ContractScalarKindV1.self, forKey: .kind)
        arrayElementKind = try ClosedContractDecodingV1.decodeOptional(
            ContractScalarKindV1.self, from: values, forKey: .arrayElementKind
        )
        required = try values.decode(Bool.self, forKey: .required)
        nullable = try values.decode(Bool.self, forKey: .nullable)
        referencedTypeID = try ClosedContractDecodingV1.decodeOptional(
            String.self, from: values, forKey: .referencedTypeID
        )
        minimumInteger = try ClosedContractDecodingV1.decodeOptional(
            Int64.self, from: values, forKey: .minimumInteger
        )
        maximumInteger = try ClosedContractDecodingV1.decodeOptional(
            Int64.self, from: values, forKey: .maximumInteger
        )
        maximumUTF8Bytes = try ClosedContractDecodingV1.decodeOptional(
            Int.self, from: values, forKey: .maximumUTF8Bytes
        )
        maximumItems = try ClosedContractDecodingV1.decodeOptional(
            Int.self, from: values, forKey: .maximumItems
        )
        ordered = try values.decode(Bool.self, forKey: .ordered)
        uniqueItems = try values.decode(Bool.self, forKey: .uniqueItems)
        try validate()
    }

    init(
        fieldID: String,
        jsonName: String,
        kind: ContractScalarKindV1,
        arrayElementKind: ContractScalarKindV1? = nil,
        required: Bool,
        nullable: Bool = false,
        referencedTypeID: String? = nil,
        minimumInteger: Int64? = nil,
        maximumInteger: Int64? = nil,
        maximumUTF8Bytes: Int? = nil,
        maximumItems: Int? = nil,
        ordered: Bool = false,
        uniqueItems: Bool = false
    ) throws {
        self.fieldID = fieldID
        self.jsonName = jsonName
        self.kind = kind
        self.arrayElementKind = arrayElementKind
        self.required = required
        self.nullable = nullable
        self.referencedTypeID = referencedTypeID
        self.minimumInteger = minimumInteger
        self.maximumInteger = maximumInteger
        self.maximumUTF8Bytes = maximumUTF8Bytes
        self.maximumItems = maximumItems
        self.ordered = ordered
        self.uniqueItems = uniqueItems
        try validate()
    }

    func validate() throws {
        let hasValidJSONName = !jsonName.isEmpty && jsonName.utf8.count <= 128
            && jsonName.utf8.allSatisfy {
                (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
                    || (0x30...0x39).contains($0) || $0 == 0x5F
        }
        let hasIntegerBounds = minimumInteger != nil || maximumInteger != nil
        let isReferenceKind = kind == .object || kind == .enumeration
        let hasValidReferenceShape: Bool
        if isReferenceKind {
            hasValidReferenceShape = referencedTypeID != nil
        } else if kind == .array {
            hasValidReferenceShape = true
        } else {
            hasValidReferenceShape = referencedTypeID == nil
        }
        guard SnapshotProjectionValidationV1.validID(fieldID), hasValidJSONName,
              !(nullable && !required),
              !hasIntegerBounds || kind == .integer,
              !(kind == .integer && minimumInteger != nil && maximumInteger != nil && minimumInteger! > maximumInteger!),
              maximumUTF8Bytes.map({ $0 > 0 }) ?? true,
              maximumUTF8Bytes == nil || kind == .string || kind == .base64Bytes,
              referencedTypeID.map(SnapshotProjectionValidationV1.validID) ?? true,
              hasValidReferenceShape,
              (kind == .array) == (arrayElementKind != nil),
              kind == .array || (maximumItems == nil && !ordered && !uniqueItems),
              kind != .array || (maximumItems.map({ $0 > 0 }) == true),
              arrayElementKind != .array,
              kind != .array || {
                  guard let elementKind = arrayElementKind else { return false }
                  let elementUsesReference = elementKind == .object || elementKind == .enumeration
                  return elementUsesReference == (referencedTypeID != nil)
              }() else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

// MARK: - C25 report consumer manifest boundary

enum SurveyDefinitionContractManifestBoundaryV1 {
    static let persistentSchema = "PERSISTENT_SCHEMA_V24_SURVEY_DEFINITION_IDENTITY_AND_RELEASE"
    static let durableFamilies = [
        "SurveyDefinitionIdentityV1",
        "SurveyDefinitionReleaseV1",
    ]
    static let lifecycleBytesRemainInExistingMutationEnvelope = true
    static let semanticDiffPersistence = "NONPERSISTENT"
    static let adoptionPreviewPersistence = "NONPERSISTENT"
    static let reportProjectionPersistence = "DERIVED_ONLY"
    static let reportProjectionVersion = SurveyDefinitionConsumerPolicyV1.projectionVersion
    static let historicArtifactsImmutable = true
    static let addsNoStorageTable = true
    static let addsNoSecondWriter = true

    static func validate() throws {
        guard durableFamilies == [
                "SurveyDefinitionIdentityV1",
                "SurveyDefinitionReleaseV1",
            ],
            lifecycleBytesRemainInExistingMutationEnvelope,
            semanticDiffPersistence == "NONPERSISTENT",
            adoptionPreviewPersistence == "NONPERSISTENT",
            reportProjectionPersistence == "DERIVED_ONLY",
            historicArtifactsImmutable,
            addsNoStorageTable,
            addsNoSecondWriter else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
    }
}

struct ContractObjectDefinitionV1: Codable, Equatable, Hashable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case typeID, version, unknownFieldPolicy, fields }

    let typeID: String
    let version: Int
    let unknownFieldPolicy: ContractUnknownFieldPolicyV1
    let fields: [ContractFieldDefinitionV1]

    static func < (lhs: ContractObjectDefinitionV1, rhs: ContractObjectDefinitionV1) -> Bool {
        lhs.typeID < rhs.typeID
    }

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        typeID = try values.decode(String.self, forKey: .typeID)
        version = try values.decode(Int.self, forKey: .version)
        unknownFieldPolicy = try values.decode(ContractUnknownFieldPolicyV1.self, forKey: .unknownFieldPolicy)
        fields = try values.decode([ContractFieldDefinitionV1].self, forKey: .fields)
        try validate()
    }

    init(
        typeID: String,
        version: Int,
        unknownFieldPolicy: ContractUnknownFieldPolicyV1,
        fields: [ContractFieldDefinitionV1]
    ) throws {
        self.typeID = typeID
        self.version = version
        self.unknownFieldPolicy = unknownFieldPolicy
        self.fields = fields
        try validate()
    }

    func validate() throws {
        guard SnapshotProjectionValidationV1.validID(typeID), version > 0,
              !fields.isEmpty, fields == fields.sorted(),
              Set(fields.map(\.fieldID)).count == fields.count,
              Set(fields.map(\.jsonName)).count == fields.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try fields.forEach { try $0.validate() }
    }
}

struct ContractEnumDefinitionV1: Codable, Equatable, Hashable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case typeID, version, policy, knownValues }

    let typeID: String
    let version: Int
    let policy: ContractEnumPolicyV1
    let knownValues: [String]

    static func < (lhs: ContractEnumDefinitionV1, rhs: ContractEnumDefinitionV1) -> Bool {
        lhs.typeID < rhs.typeID
    }

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        typeID = try values.decode(String.self, forKey: .typeID)
        version = try values.decode(Int.self, forKey: .version)
        policy = try values.decode(ContractEnumPolicyV1.self, forKey: .policy)
        knownValues = try values.decode([String].self, forKey: .knownValues)
        try validate()
    }

    init(typeID: String, version: Int, policy: ContractEnumPolicyV1, knownValues: [String]) throws {
        self.typeID = typeID
        self.version = version
        self.policy = policy
        self.knownValues = knownValues
        try validate()
    }

    func validate() throws {
        guard SnapshotProjectionValidationV1.validID(typeID), version > 0,
              !knownValues.isEmpty, knownValues == knownValues.sorted(),
              Set(knownValues).count == knownValues.count,
              knownValues.allSatisfy({
                  $0.utf8.count <= 128 && SnapshotProjectionValidationV1.validText($0)
              }) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

struct ContractCodecRuleV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case codecVersion, canonicalJSON, integerEncoding, timeEncoding, nullEncoding, binaryEncoding
        case stringNormalization, formatAssertion
    }

    let codecVersion: Int
    let canonicalJSON: String
    let integerEncoding: String
    let timeEncoding: String
    let nullEncoding: String
    let binaryEncoding: String
    let stringNormalization: String
    let formatAssertion: Bool

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        codecVersion = try values.decode(Int.self, forKey: .codecVersion)
        canonicalJSON = try values.decode(String.self, forKey: .canonicalJSON)
        integerEncoding = try values.decode(String.self, forKey: .integerEncoding)
        timeEncoding = try values.decode(String.self, forKey: .timeEncoding)
        nullEncoding = try values.decode(String.self, forKey: .nullEncoding)
        binaryEncoding = try values.decode(String.self, forKey: .binaryEncoding)
        stringNormalization = try values.decode(String.self, forKey: .stringNormalization)
        formatAssertion = try values.decode(Bool.self, forKey: .formatAssertion)
        try validate()
    }

    init(codecVersion: Int) throws {
        guard codecVersion == 1 else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        self.codecVersion = codecVersion
        canonicalJSON = "UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE"
        integerEncoding = "BASE10_INTEGER_NO_EXPONENT"
        timeEncoding = "UTC_RFC3339_MILLISECONDS_Z"
        nullEncoding = "EXPLICIT_NULL_ONLY_WHEN_REQUIRED_NULLABLE"
        binaryEncoding = "RFC4648_BASE64_PADDED"
        stringNormalization = "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED"
        formatAssertion = false
        try validate()
    }

    func validate() throws {
        guard codecVersion == 1,
              canonicalJSON == "UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE",
              integerEncoding == "BASE10_INTEGER_NO_EXPONENT",
              timeEncoding == "UTC_RFC3339_MILLISECONDS_Z",
              nullEncoding == "EXPLICIT_NULL_ONLY_WHEN_REQUIRED_NULLABLE",
              binaryEncoding == "RFC4648_BASE64_PADDED",
              stringNormalization == "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED",
              !formatAssertion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
    }
}

struct ContractCompatibilityRuleV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case minimumReaderVersion, maximumReaderVersion, unknownObjectFields, publishedVersionsImmutable
    }

    let minimumReaderVersion: Int
    let maximumReaderVersion: Int
    let unknownObjectFields: ContractUnknownFieldPolicyV1
    let publishedVersionsImmutable: Bool

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimumReaderVersion = try values.decode(Int.self, forKey: .minimumReaderVersion)
        maximumReaderVersion = try values.decode(Int.self, forKey: .maximumReaderVersion)
        unknownObjectFields = try values.decode(ContractUnknownFieldPolicyV1.self, forKey: .unknownObjectFields)
        publishedVersionsImmutable = try values.decode(Bool.self, forKey: .publishedVersionsImmutable)
        try validate()
    }

    init(minimumReaderVersion: Int, maximumReaderVersion: Int, unknownObjectFields: ContractUnknownFieldPolicyV1) throws {
        guard minimumReaderVersion > 0, maximumReaderVersion >= minimumReaderVersion else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        self.minimumReaderVersion = minimumReaderVersion
        self.maximumReaderVersion = maximumReaderVersion
        self.unknownObjectFields = unknownObjectFields
        publishedVersionsImmutable = true
        try validate()
    }

    func validate() throws {
        guard minimumReaderVersion > 0, maximumReaderVersion >= minimumReaderVersion,
              publishedVersionsImmutable else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

struct ContractManifestV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, manifestID, manifestVersion, persistentContractSchema, codec, compatibility
        case objects, enums, reportSectionRegistry
    }

    static let schemaVersion = 1
    static let persistentContractSchema = "KERNEL_SNAPSHOT_V1"
    let schemaVersion: Int
    let manifestID: String
    let manifestVersion: Int
    let persistentContractSchema: String
    let codec: ContractCodecRuleV1
    let compatibility: ContractCompatibilityRuleV1
    let objects: [ContractObjectDefinitionV1]
    let enums: [ContractEnumDefinitionV1]
    let reportSectionRegistry: ReportSectionRegistryV1

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        manifestID = try values.decode(String.self, forKey: .manifestID)
        manifestVersion = try values.decode(Int.self, forKey: .manifestVersion)
        persistentContractSchema = try values.decode(String.self, forKey: .persistentContractSchema)
        codec = try values.decode(ContractCodecRuleV1.self, forKey: .codec)
        compatibility = try values.decode(ContractCompatibilityRuleV1.self, forKey: .compatibility)
        objects = try values.decode([ContractObjectDefinitionV1].self, forKey: .objects)
        enums = try values.decode([ContractEnumDefinitionV1].self, forKey: .enums)
        reportSectionRegistry = try values.decode(ReportSectionRegistryV1.self, forKey: .reportSectionRegistry)
        try validate()
    }

    init(
        manifestID: String,
        manifestVersion: Int,
        codec: ContractCodecRuleV1,
        compatibility: ContractCompatibilityRuleV1,
        objects: [ContractObjectDefinitionV1],
        enums: [ContractEnumDefinitionV1],
        reportSectionRegistry: ReportSectionRegistryV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.manifestID = manifestID
        self.manifestVersion = manifestVersion
        persistentContractSchema = Self.persistentContractSchema
        self.codec = codec
        self.compatibility = compatibility
        self.objects = objects
        self.enums = enums
        self.reportSectionRegistry = reportSectionRegistry
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              persistentContractSchema == Self.persistentContractSchema,
              SnapshotProjectionValidationV1.validID(manifestID), manifestVersion > 0,
              !objects.isEmpty, objects == objects.sorted(),
              Set(objects.map(\.typeID)).count == objects.count,
              enums == enums.sorted(), Set(enums.map(\.typeID)).count == enums.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try codec.validate()
        try compatibility.validate()
        try objects.forEach { try $0.validate() }
        try enums.forEach { try $0.validate() }
        try Self.validate(reportSectionRegistry)

        let objectTypeIDs = Set(objects.map(\.typeID))
        let enumTypeIDs = Set(enums.map(\.typeID))
        guard objectTypeIDs.isDisjoint(with: enumTypeIDs) else {
            throw SnapshotProjectionFailureV1.duplicateIdentity
        }
        for field in objects.flatMap(\.fields) {
            let effectiveKind: ContractScalarKindV1
            if field.kind == .array {
                guard let arrayElementKind = field.arrayElementKind else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
                effectiveKind = arrayElementKind
            } else {
                effectiveKind = field.kind
            }
            switch effectiveKind {
            case .object:
                guard field.referencedTypeID.map(objectTypeIDs.contains) == true else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
            case .enumeration:
                guard field.referencedTypeID.map(enumTypeIDs.contains) == true else {
                    throw SnapshotProjectionFailureV1.missingBinding
                }
            default:
                guard field.referencedTypeID == nil else {
                    throw SnapshotProjectionFailureV1.invalidValue
                }
            }
        }
    }

    private static func validate(_ registry: ReportSectionRegistryV1) throws {
        guard registry.schemaVersion == ReportSectionRegistryV1.schemaVersion,
              SnapshotProjectionValidationV1.validID(registry.registryID), registry.registryVersion > 0,
              !registry.sections.isEmpty,
              registry.sections.map(\.order) == Array(0..<registry.sections.count),
              Set(registry.sections.map(\.sectionID)).count == registry.sections.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        for section in registry.sections {
            guard SnapshotProjectionValidationV1.validID(section.sectionID), section.version > 0,
                  section.order >= 0, !section.supportedFormats.isEmpty,
                  section.supportedFormats == section.supportedFormats.sorted(by: { $0.rawValue < $1.rawValue }),
                  Set(section.supportedFormats).count == section.supportedFormats.count else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
        }
        let required = registry.requiredSectionIDs
        guard Set(["identity", "limitations", "provenance", "supersession", "manifest"]).isSubset(of: required) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
    }
}

struct OpenJSONSchemaProjectionV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, manifestID, manifestVersion, manifestSHA256, dialect, schemaID, schemaSHA256, networkFetchRequired
    }

    static let schemaVersion = 1
    let schemaVersion: Int
    let manifestID: String
    let manifestVersion: Int
    let manifestSHA256: String
    let dialect: String
    let schemaID: String
    let schemaSHA256: String
    let networkFetchRequired: Bool

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        manifestID = try values.decode(String.self, forKey: .manifestID)
        manifestVersion = try values.decode(Int.self, forKey: .manifestVersion)
        manifestSHA256 = try values.decode(String.self, forKey: .manifestSHA256)
        dialect = try values.decode(String.self, forKey: .dialect)
        schemaID = try values.decode(String.self, forKey: .schemaID)
        schemaSHA256 = try values.decode(String.self, forKey: .schemaSHA256)
        networkFetchRequired = try values.decode(Bool.self, forKey: .networkFetchRequired)
        try validate()
    }

    init(
        manifestID: String,
        manifestVersion: Int,
        manifestSHA256: String,
        schemaID: String,
        schemaSHA256: String
    ) throws {
        guard SnapshotProjectionValidationV1.validID(manifestID), manifestVersion > 0,
              [manifestSHA256, schemaSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              schemaID.hasPrefix("https://schemas.assetrounds.local/") else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.manifestID = manifestID
        self.manifestVersion = manifestVersion
        self.manifestSHA256 = manifestSHA256
        dialect = "https://json-schema.org/draft/2020-12/schema"
        self.schemaID = schemaID
        self.schemaSHA256 = schemaSHA256
        networkFetchRequired = false
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SnapshotProjectionValidationV1.validID(manifestID), manifestVersion > 0,
              [manifestSHA256, schemaSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              dialect == "https://json-schema.org/draft/2020-12/schema",
              schemaID.hasPrefix("https://schemas.assetrounds.local/"),
              !networkFetchRequired else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

struct ContractSchemaDerivationReceiptV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, receiptID, manifestSHA256, schemaSHA256, repeatedGenerationByteIdentical
        case officialMetaSchemaValid, independentInstanceValidationOwner, releaseDependencyAdded
    }

    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: String
    let manifestSHA256: String
    let schemaSHA256: String
    let repeatedGenerationByteIdentical: Bool
    let officialMetaSchemaValid: Bool
    let independentInstanceValidationOwner: String
    let releaseDependencyAdded: Bool

    init(from decoder: Decoder) throws {
        try ContractManifestDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        receiptID = try values.decode(String.self, forKey: .receiptID)
        manifestSHA256 = try values.decode(String.self, forKey: .manifestSHA256)
        schemaSHA256 = try values.decode(String.self, forKey: .schemaSHA256)
        repeatedGenerationByteIdentical = try values.decode(Bool.self, forKey: .repeatedGenerationByteIdentical)
        officialMetaSchemaValid = try values.decode(Bool.self, forKey: .officialMetaSchemaValid)
        independentInstanceValidationOwner = try values.decode(String.self, forKey: .independentInstanceValidationOwner)
        releaseDependencyAdded = try values.decode(Bool.self, forKey: .releaseDependencyAdded)
        try validate()
    }

    init(
        receiptID: String,
        manifestSHA256: String,
        schemaSHA256: String,
        observedRepeatedGenerationByteIdentical: Bool,
        observedOfficialMetaSchemaValid: Bool
    ) throws {
        schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.manifestSHA256 = manifestSHA256
        self.schemaSHA256 = schemaSHA256
        repeatedGenerationByteIdentical = observedRepeatedGenerationByteIdentical
        officialMetaSchemaValid = observedOfficialMetaSchemaValid
        independentInstanceValidationOwner = "V23-P03-C10"
        releaseDependencyAdded = false
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SnapshotProjectionValidationV1.validID(receiptID),
              [manifestSHA256, schemaSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              repeatedGenerationByteIdentical, officialMetaSchemaValid,
              independentInstanceValidationOwner == "V23-P03-C10",
              !releaseDependencyAdded else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

// MARK: - C27 asset-locator consumer boundary

/// The C27 report consumer binds to the canonical locator contracts without
/// placing the opaque locator representation in a public report manifest.
enum AssetLocatorContractManifestBoundaryV1 {
    static let locatorTypeID = "AssetLocatorV1"
    static let resolutionTypeID = "LocatorResolutionV1"
    static let bindingReceiptTypeID = "LocatorBindingReceiptV1"
    static let persistentSchemaCompatibilityID = "ASSET_LOCATOR_V1"
    static let reportSectionID = "asset.locator"
    static let resolutionIsDerivedOnly = true
    static let historicInterpretationIsImmutable = true
    static let opaqueInputExcluded = true
    static let privateKeyMaterialExcluded = true
    static let permissionClaimsExcluded = true
    static let networkResolutionClaimsExcluded = true

    static func validate() throws {
        guard locatorTypeID == "AssetLocatorV1",
              resolutionTypeID == "LocatorResolutionV1",
              bindingReceiptTypeID == "LocatorBindingReceiptV1",
              persistentSchemaCompatibilityID == "ASSET_LOCATOR_V1",
              reportSectionID == "asset.locator",
              resolutionIsDerivedOnly, historicInterpretationIsImmutable,
              opaqueInputExcluded, privateKeyMaterialExcluded,
              permissionClaimsExcluded, networkResolutionClaimsExcluded else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

extension ContractManifestV1 {
    func validateAssetLocatorConsumerContract() throws -> Self {
        try validate()
        try AssetLocatorContractManifestBoundaryV1.validate()
        return self
    }
}

// MARK: - C28 schedule contract manifest boundary

/// The schedule report section consumes the canonical V27 release/history
/// families. Due/reminder projections are disposable and are never promoted
/// into the manifest's durable contract surface.
enum ScheduleContractManifestBoundaryV1 {
    static let contractTypeIDs = [
        "ScheduleDefinitionReleaseV1",
        "OccurrenceIDV1",
        "OccurrenceStateV1",
        "ScheduleExceptionV1",
        "DueQueueProjectionV1",
        "ReminderProjectionV1",
    ]
    static let persistentSchema = "PERSISTENT_SCHEMA_V27_SCHEDULE_RELEASE_AND_OCCURRENCE_HISTORY"
    static let durableFamilies = [
        "ScheduleDefinitionReleaseV1",
        "OccurrenceHistoryEventV1",
    ]
    static let derivedFamilies = [
        "DueQueueProjectionV1",
        "ReminderProjectionV1",
        "ScheduleGenerationPlanV1",
    ]
    static let reportProjectionVersion = "SCHEDULE_REPORT_PROJECTION_V1"
    static let notificationDeliveryIsTruth = false
    static let historicDisplayIsImmutable = true
    static let generationIsBounded = true
    static let noSecondWriter = true

    static func validate() throws {
        guard contractTypeIDs == [
                  "ScheduleDefinitionReleaseV1",
                  "OccurrenceIDV1",
                  "OccurrenceStateV1",
                  "ScheduleExceptionV1",
                  "DueQueueProjectionV1",
                  "ReminderProjectionV1",
              ],
              durableFamilies == [
                  "ScheduleDefinitionReleaseV1",
                  "OccurrenceHistoryEventV1",
              ],
              derivedFamilies == [
                  "DueQueueProjectionV1",
                  "ReminderProjectionV1",
                  "ScheduleGenerationPlanV1",
              ],
              persistentSchema == "PERSISTENT_SCHEMA_V27_SCHEDULE_RELEASE_AND_OCCURRENCE_HISTORY",
              reportProjectionVersion == ScheduleReportProjectionV1.projectionVersion,
              !notificationDeliveryIsTruth,
              historicDisplayIsImmutable,
              generationIsBounded,
              noSecondWriter else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

enum AdvancedScheduleContractManifestBoundaryV1 {
    static let durableFamilies = [
        "ExceptionCalendarReleaseV1", "ScheduleOverrideEventV1",
        "ScheduleChangeReceiptV1",
    ]
    static let derivedFamilies = [
        "OccurrenceScheduleBasisV2", "ScheduleChangePreviewV1",
        "AdvancedScheduleReportProjectionV1",
        "AdvancedScheduleOccurrenceSearchRecordV1",
    ]
    static let noSecondWriter = true
    static let reportProjectionVersion = AdvancedScheduleReportProjectionV1.projectionVersion
    static func validate() throws {
        guard durableFamilies == ["ExceptionCalendarReleaseV1", "ScheduleOverrideEventV1",
                                  "ScheduleChangeReceiptV1"],
              derivedFamilies == ["OccurrenceScheduleBasisV2", "ScheduleChangePreviewV1",
                                  "AdvancedScheduleReportProjectionV1",
                                  "AdvancedScheduleOccurrenceSearchRecordV1"],
              noSecondWriter,
              reportProjectionVersion == "ADVANCED_SCHEDULE_REPORT_PROJECTION_V1" else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

extension ContractManifestV1 {
    func validateScheduleConsumerContract() throws -> Self {
        try validate()
        try ScheduleContractManifestBoundaryV1.validate()
        return self
    }
}

// MARK: - C29 versioned plan/rebase consumer boundary

enum PlanContractManifestBoundaryV1 {
    static let contractTypeIDs = [
        "PlanDocumentV1",
        "PlanRevisionV1",
        "SpatialReferenceFrameV1",
        "PlanPlacementV1",
        "PlanRebaseComponentV1",
        "PlanRebaseComponentRegistryV1",
        "RebasePreviewV1",
        "RebaseReceiptV1",
        "PlanLifecycleClosureV1",
    ]
    static let durableFamilies = [
        "PlanDocumentV1",
        "PlanRevisionV1",
        "PlanPlacementV1",
    ]
    static let derivedFamilies = [
        "RebasePreviewV1",
        "RebaseReceiptV1",
        "PlanReportProjectionV1",
    ]
    static let reportProjectionVersion = PlanReportProjectionV1.projectionVersion
    static let persistentBoundary = "C29_PLAN_KIND_INVENTORY_BEFORE_FIRST_WRITE"
    static let normalizedCoordinatesAreCanonical = true
    static let previewIsNotApplied = true
    static let historicDisplayIsFrozen = true
    static let noSecondWriter = true

    static func validate() throws {
        guard contractTypeIDs == [
                  "PlanDocumentV1",
                  "PlanRevisionV1",
                  "SpatialReferenceFrameV1",
                  "PlanPlacementV1",
                  "PlanRebaseComponentV1",
                  "PlanRebaseComponentRegistryV1",
                  "RebasePreviewV1",
                  "RebaseReceiptV1",
                  "PlanLifecycleClosureV1",
              ],
              durableFamilies == [
                  "PlanDocumentV1",
                  "PlanRevisionV1",
                  "PlanPlacementV1",
              ],
              derivedFamilies == [
                  "RebasePreviewV1",
                  "RebaseReceiptV1",
                  "PlanReportProjectionV1",
              ],
              reportProjectionVersion == PlanReportProjectionV1.projectionVersion,
              persistentBoundary == "C29_PLAN_KIND_INVENTORY_BEFORE_FIRST_WRITE",
              normalizedCoordinatesAreCanonical,
              previewIsNotApplied,
              historicDisplayIsFrozen,
              noSecondWriter else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

extension ContractManifestV1 {
    func validatePlanConsumerContract() throws -> Self {
        try validate()
        try PlanContractManifestBoundaryV1.validate()
        return self
    }
}

// MARK: - C37 placement-pose report consumer boundary

/// The C37 consumer registers the canonical pose/event families and the
/// derived report projection without promoting display text, search rows, or
/// rebase previews into durable truth.
enum PlacementPoseContractManifestBoundaryV1 {
    static let contractTypeIDs = [
        "PoseAxisDescriptorV1",
        "PlacementPoseV1",
        "AssetPoseEventReferenceV1",
        "AssetPoseEventV1",
        "SpatialAnchorObservationV1",
        "PosePlacementDispositionComponentV1",
        "PoseFrameRebaseComponentV1",
        "CompletedPlacementPoseSnapshotV1",
        "C37PlacementPoseReportProjectionV1",
    ]
    static let durableFamilies = [
        "AssetPoseEventV1",
        "SpatialAnchorObservationV1",
    ]
    static let derivedFamilies = [
        "AssetPoseCurrentTipV1",
        "CompletedPlacementPoseSnapshotV1",
        "C37PlacementPoseReportProjectionV1",
    ]
    static let reportProjectionVersion = C37PlacementPoseReportProjectionV1.projectionVersion
    static let persistentSchema = "PLACEMENT_POSE_V1"
    static let currentAndHistoryAreRecordedFacts = true
    static let historicDisplayIsFrozen = true
    static let rebasePreviewIsNotApplied = true
    static let sensorAndNetworkInputsExcluded = true
    static let actorIdentityAndPrivateLocatorsExcluded = true
    static let noSecondWriter = true

    static func validate() throws {
        guard contractTypeIDs == [
                  "PoseAxisDescriptorV1",
                  "PlacementPoseV1",
                  "AssetPoseEventReferenceV1",
                  "AssetPoseEventV1",
                  "SpatialAnchorObservationV1",
                  "PosePlacementDispositionComponentV1",
                  "PoseFrameRebaseComponentV1",
                  "CompletedPlacementPoseSnapshotV1",
                  "C37PlacementPoseReportProjectionV1",
              ],
              durableFamilies == [
                  "AssetPoseEventV1",
                  "SpatialAnchorObservationV1",
              ],
              derivedFamilies == [
                  "AssetPoseCurrentTipV1",
                  "CompletedPlacementPoseSnapshotV1",
                  "C37PlacementPoseReportProjectionV1",
              ],
              reportProjectionVersion == C37PlacementPoseReportProjectionV1.projectionVersion,
              persistentSchema == "PLACEMENT_POSE_V1",
              currentAndHistoryAreRecordedFacts,
              historicDisplayIsFrozen,
              rebasePreviewIsNotApplied,
              sensorAndNetworkInputsExcluded,
              actorIdentityAndPrivateLocatorsExcluded,
              noSecondWriter else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
    }
}

extension ContractManifestV1 {
    func validatePlacementPoseConsumerContract() throws -> Self {
        try validate()
        try PlacementPoseContractManifestBoundaryV1.validate()
        return self
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Reporting_ContractManifestV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift", role: .report)
}

enum C31LightingContractManifestBoundaryV1 {
    static let contractID = "lighting.report.projection.v1"
    static let sourceContract = "LightingSystemV1"
    static let supportedFacts = [
        "topology", "observation", "issue", "measurement", "criterion", "safety_stop",
    ]
    static let unsupportedClaims = [
        "operational_state", "safety_certification", "security_certification",
        "compliance", "ada", "ies", "survey_grade",
    ]
    static let historicDisplayFrozen = true
    static let manualOfflinePathPreserved = true
}
// MARK: - C32 assistance contract manifest boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Reporting_ContractManifestV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let assistanceLifecycleIsManifestBound = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Domain_Reporting_ContractManifestV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

enum C45AcceptedLabelContractManifestBoundaryV1 { static let durableFamily="AcceptedLabelGenerationSnapshotRow";static let derivedOutputIsNotContractManifestTruth=true }

enum C46OperationalContactContractManifestBoundaryV1{
    static let durableFamilies=OperationalContactPersistenceEnrollmentV1.persistentFamilies
    static let defaultExportEnabled=PartyContactsCSVContractV1.defaultExportEnabled
    static let customerContactValuesAreReportSafe=false
    static let systemOutcomeCreatesCommunicationClaim=false
    static func validate()throws{guard durableFamilies==["ServiceContactPointRow","SystemHandoffIntentRow"],!defaultExportEnabled,!customerContactValuesAreReportSafe,!systemOutcomeCreatesCommunicationClaim else{throw SnapshotProjectionFailureV1.invalidValue}}
}

enum C48PortableReviewContractManifestBoundaryV1 {
    static let manifestDeclaresDerivedFieldsOnly = true
    static let allowedDerivedFieldIDs = C48PortableReviewDerivedHistoryProjectionV1.allowedFieldIDs
    static let capabilityProofAndResponseBytesAreNotManifestFields = true
    static let workspaceAndReplicaIdentityAreNotManifestFields = true
    static let externalIdentityIsSelfAssertedOnly = true

    static func validateFieldIDs(_ values: [String]) throws {
        try C48PortableReviewDerivedHistoryProjectionV1.validateFieldIDs(values)
    }
}

// MARK: - C49 work-resource manifest fields

enum C49WorkResourceContractManifestBoundaryV1 {
    static let derivedFieldIDs = [
        "duration_minutes", "material_description", "material_unit",
        "material_quantity", "direct_cost_total", "currency_code"
    ]
    static let rawStockFieldIDsAreForbidden = true
    static let liveInventoryFieldIDsAreForbidden = true
    static let sourceBytesAreForbidden = true

    static func validate(_ projection: C49WorkResourceReportProjectionV1) throws {
        try C49WorkResourceProjectionSupportV1.validate(projection)
        guard derivedFieldIDs.count == Set(derivedFieldIDs).count else {
            throw C49WorkResourceProjectionFailureV1.nonCanonical
        }
    }
}

// MARK: - C34 route snapshot privacy and reporting exclusion

enum C34RouteSnapshotContractManifestV1 {
    static let snapshotType: Any.Type = SceneNavigationSnapshotV1.self
    static let lifecycleType: Any.Type = SceneNavigationLifecycleDispositionV1.self
    static let reportProjectionFieldIDs: [String] = []
    static let customerContentCategoriesExcluded = [
        "model_blob", "draft_value", "note", "evidence_bytes", "secret",
        "user_entered_display_text", "search_query",
    ]
    static let snapshotBytesExcludedFromReports = true
    static let snapshotBytesExcludedFromExports = true
    static let routeIdentifiersExcludedFromDiagnostics = true
    static let routeSnapshotContainsCustomerContent = false
    static let routeSnapshotContainsSecrets = false

    static func validate(_ lifecycle: SceneNavigationLifecycleDispositionV1 = .init()) -> Bool {
        !lifecycle.workspaceTruth
            && !lifecycle.reportIncluded
            && !lifecycle.exportIncluded
            && !routeSnapshotContainsCustomerContent
            && !routeSnapshotContainsSecrets
            && reportProjectionFieldIDs.isEmpty
            && Set(customerContentCategoriesExcluded).count == customerContentCategoriesExcluded.count
    }
}

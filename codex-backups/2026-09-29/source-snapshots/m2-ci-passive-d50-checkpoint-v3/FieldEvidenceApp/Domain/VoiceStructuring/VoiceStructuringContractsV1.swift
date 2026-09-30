import CryptoKit
import Foundation

enum VoiceStructuringFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case invalidSpan
    case duplicateField
    case incompleteReview
    case expired
    case incompatibleGrammar
}

protocol VoiceStructuringCanonicalValidatingV1 {
    func validate() throws
}

enum VoiceStructuringLimitsV1 {
    static let maximumTranscriptUTF8Bytes = 32_768
    static let maximumFields = 64
    static let maximumUnmatchedClauses = 64
    static let maximumGrammarReleases = 32
    static let maximumAliases = 256
    static let maximumAlternatives = 16
    static let maximumTextUTF8Bytes = 4_096
    static let maximumTokenUTF8Bytes = 128
    static let maximumCanonicalBytes = 262_144
    static let maximumLifetime: TimeInterval = 30 * 60

    static let forbiddenScalars = Set<UInt32>([
        0x061c, 0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x202a, 0x202b,
        0x202c, 0x202d, 0x202e, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069,
        0xfeff,
    ])

    static func identifier(_ value: String, maximum: Int = maximumTokenUTF8Bytes) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let permitted = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:/-")
        guard value == trimmed, value == value.precomposedStringWithCanonicalMapping,
              !value.isEmpty, value.utf8.count <= maximum,
              value.unicodeScalars.allSatisfy({ permitted.contains($0) }),
              !value.unicodeScalars.contains(where: { forbiddenScalars.contains($0.value) }) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }

    static func userText(_ value: String, maximum: Int = maximumTextUTF8Bytes) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == trimmed, value == value.precomposedStringWithCanonicalMapping,
              !value.isEmpty, value.utf8.count <= maximum,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
                      || forbiddenScalars.contains($0.value)
              }) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }

    static func normalizedPhrase(_ value: String, localeIdentifier: String) throws -> String {
        try userText(value, maximum: maximumTokenUTF8Bytes)
        let normalized = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: localeIdentifier)
        ).precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty else { throw VoiceStructuringFailureV1.invalidValue }
        return normalized
    }

    static func digest(_ value: String) throws {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw VoiceStructuringFailureV1.invalidDigest
        }
    }

    fileprivate static func transcriptSHA256(_ transcript: String) -> String {
        SHA256.hash(data: Data(transcript.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func instant(_ value: Date) throws {
        guard value.timeIntervalSince1970.isFinite else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }
}

enum VoiceStructuredFieldKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case noteText = "NOTE_TEXT"
    case findingText = "FINDING_TEXT"
    case allowedEnum = "ALLOWED_ENUM"
    case exactNumberAndUnit = "EXACT_NUMBER_AND_UNIT"
    case duration = "DURATION"
    case materialDescriptionAndQuantity = "MATERIAL_DESCRIPTION_AND_QUANTITY"
}

enum VoiceStructuringSemanticPurposeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case note = "note"
    case findingTitle = "finding.title"
    case findingDescription = "finding.description"
    case explicitPriority = "finding.priority"
    case explicitCondition = "finding.condition"
    case numberAndUnit = "explicit.numberAndUnit"
    case duration = "duration"
    case freeMaterialDescriptionAndQuantity = "material.descriptionAndQuantity"

    var requiredKind: VoiceStructuredFieldKindV1 {
        switch self {
        case .note: return .noteText
        case .findingTitle, .findingDescription: return .findingText
        case .explicitPriority, .explicitCondition: return .allowedEnum
        case .numberAndUnit: return .exactNumberAndUnit
        case .duration: return .duration
        case .freeMaterialDescriptionAndQuantity: return .materialDescriptionAndQuantity
        }
    }
}

enum VoiceStructuredUnitV1: String, Codable, CaseIterable, Hashable, Sendable {
    case each = "EACH"
    case percent = "PERCENT"
    case millimeter = "MILLIMETER"
    case centimeter = "CENTIMETER"
    case meter = "METER"
    case inch = "INCH"
    case foot = "FOOT"
    case gram = "GRAM"
    case kilogram = "KILOGRAM"
    case ounce = "OUNCE"
    case pound = "POUND"
    case milliliter = "MILLILITER"
    case liter = "LITER"
    case gallon = "GALLON"
}

enum VoiceStructuringResolutionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case exact = "EXACT_EXPLICIT_GRAMMAR"
    case ambiguous = "AMBIGUOUS_REQUIRES_MANUAL_ENTRY"
    case unsupported = "UNSUPPORTED"
}

struct VoiceTranscriptUTF8SpanV1: Codable, Equatable, Hashable, Sendable {
    let start: Int
    let length: Int

    init(start: Int, length: Int) throws {
        guard start >= 0, length > 0 else { throw VoiceStructuringFailureV1.invalidSpan }
        self.start = start
        self.length = length
    }

    var end: Int {
        let (value, overflow) = start.addingReportingOverflow(length)
        return overflow ? Int.max : value
    }

    func validate(in transcript: String) throws {
        let bytes = transcript.utf8
        let (validatedEnd, overflow) = start.addingReportingOverflow(length)
        guard !overflow, validatedEnd >= start, validatedEnd <= bytes.count,
              let lowerUTF8 = bytes.index(bytes.startIndex, offsetBy: start, limitedBy: bytes.endIndex),
              let upperUTF8 = bytes.index(bytes.startIndex, offsetBy: validatedEnd, limitedBy: bytes.endIndex),
              String.Index(lowerUTF8, within: transcript) != nil,
              String.Index(upperUTF8, within: transcript) != nil else {
            throw VoiceStructuringFailureV1.invalidSpan
        }
    }
}

struct VoiceExactDecimalV1: Codable, Equatable, Hashable, Sendable {
    let mantissa: Int64
    let scale: Int
    let unit: VoiceStructuredUnitV1

    init(mantissa: Int64, scale: Int, unit: VoiceStructuredUnitV1) throws {
        guard (0...3).contains(scale), unit != .each || scale == 0 else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        self.mantissa = mantissa
        self.scale = scale
        self.unit = unit
    }

    func validate() throws { _ = try Self(mantissa: mantissa, scale: scale, unit: unit) }
}

struct VoiceMaterialProposalValueV1: Codable, Equatable, Hashable, Sendable {
    let description: String
    let quantity: VoiceExactDecimalV1?

    init(description: String, quantity: VoiceExactDecimalV1?) throws {
        try VoiceStructuringLimitsV1.userText(description)
        try quantity?.validate()
        guard quantity.map({ $0.mantissa > 0 }) ?? true else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        self.description = description
        self.quantity = quantity
    }

    func validate() throws { _ = try Self(description: description, quantity: quantity) }
}

enum VoiceStructuredFieldValueV1: Codable, Equatable, Hashable, Sendable {
    case text(String)
    case allowedEnum(String)
    case exactNumber(VoiceExactDecimalV1)
    case durationSeconds(UInt64)
    case material(VoiceMaterialProposalValueV1)

    func validate(for kind: VoiceStructuredFieldKindV1) throws {
        switch (kind, self) {
        case (.noteText, .text(let value)), (.findingText, .text(let value)):
            try VoiceStructuringLimitsV1.userText(value)
        case (.allowedEnum, .allowedEnum(let value)):
            try VoiceStructuringLimitsV1.identifier(value)
        case (.exactNumberAndUnit, .exactNumber(let value)):
            try value.validate()
        case (.duration, .durationSeconds(let seconds)):
            guard seconds > 0, seconds <= 31_536_000 else { throw VoiceStructuringFailureV1.invalidValue }
        case (.materialDescriptionAndQuantity, .material(let value)):
            try value.validate()
        default:
            throw VoiceStructuringFailureV1.invalidValue
        }
    }
}

struct VoiceStructuringAliasV1: Codable, Equatable, Hashable, Sendable {
    let spokenAlias: String
    let fieldID: String
    let fieldKind: VoiceStructuredFieldKindV1
    let allowedEnumWords: [String]

    init(
        spokenAlias: String,
        fieldID: String,
        fieldKind: VoiceStructuredFieldKindV1,
        allowedEnumWords: [String] = []
    ) throws {
        try VoiceStructuringLimitsV1.userText(spokenAlias, maximum: VoiceStructuringLimitsV1.maximumTokenUTF8Bytes)
        try VoiceStructuringLimitsV1.identifier(fieldID)
        guard allowedEnumWords.count <= VoiceStructuringLimitsV1.maximumAliases,
              Set(allowedEnumWords).count == allowedEnumWords.count,
              (fieldKind == .allowedEnum) == !allowedEnumWords.isEmpty else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        try allowedEnumWords.forEach {
            try VoiceStructuringLimitsV1.userText($0, maximum: VoiceStructuringLimitsV1.maximumTokenUTF8Bytes)
        }
        let normalizedWords = try allowedEnumWords.map {
            try VoiceStructuringLimitsV1.normalizedPhrase($0, localeIdentifier: "en_US_POSIX")
        }
        guard normalizedWords == normalizedWords.sorted(),
              Set(normalizedWords).count == normalizedWords.count else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        self.spokenAlias = spokenAlias
        self.fieldID = fieldID
        self.fieldKind = fieldKind
        self.allowedEnumWords = allowedEnumWords
    }

    func validate() throws {
        _ = try Self(spokenAlias: spokenAlias, fieldID: fieldID, fieldKind: fieldKind,
                     allowedEnumWords: allowedEnumWords)
    }
}

/// Closed, released deterministic grammar. Adding aliases or locale behavior
/// requires a new version and digest; callers cannot inject a runtime grammar.
struct VoiceStructuringGrammarReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let grammarID: String
    let version: UInt64
    let localeIdentifier: String
    let aliases: [VoiceStructuringAliasV1]
    let releasedAt: Date

    init(
        grammarID: String,
        version: UInt64,
        localeIdentifier: String,
        aliases: [VoiceStructuringAliasV1],
        releasedAt: Date
    ) throws {
        schemaVersion = Self.schemaVersion
        self.grammarID = grammarID
        self.version = version
        self.localeIdentifier = localeIdentifier
        self.aliases = aliases
        self.releasedAt = releasedAt
        try validate()
    }

    func validate() throws {
        try VoiceStructuringLimitsV1.identifier(grammarID)
        try VoiceStructuringLimitsV1.identifier(localeIdentifier)
        try VoiceStructuringLimitsV1.instant(releasedAt)
        try aliases.forEach { try $0.validate() }
        let normalizedAliases = try aliases.map {
            try VoiceStructuringLimitsV1.normalizedPhrase(
                $0.spokenAlias,
                localeIdentifier: localeIdentifier
            )
        }
        guard aliases.map(\.spokenAlias) == normalizedAliases else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        let keys = zip(normalizedAliases, aliases).map { "\($0.0)|\($0.1.fieldID)" }
        guard schemaVersion == Self.schemaVersion, version > 0,
              !aliases.isEmpty, aliases.count <= VoiceStructuringLimitsV1.maximumAliases,
              Set(normalizedAliases).count == normalizedAliases.count,
              Set(keys).count == keys.count,
              keys == keys.sorted() else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        var kindsByFieldID: [String: VoiceStructuredFieldKindV1] = [:]
        var allEnumWords: [String] = []
        for alias in aliases {
            if let prior = kindsByFieldID[alias.fieldID], prior != alias.fieldKind {
                throw VoiceStructuringFailureV1.invalidValue
            }
            kindsByFieldID[alias.fieldID] = alias.fieldKind
            let enumWords = try alias.allowedEnumWords.map {
                try VoiceStructuringLimitsV1.normalizedPhrase(
                    $0,
                    localeIdentifier: localeIdentifier
                )
            }
            guard alias.allowedEnumWords == enumWords,
                  enumWords == enumWords.sorted(),
                  Set(enumWords).count == enumWords.count else {
                throw VoiceStructuringFailureV1.invalidValue
            }
            allEnumWords.append(contentsOf: enumWords)
        }
        guard Set(allEnumWords).count == allEnumWords.count else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }

    var releaseSHA256: String { get throws { try VoiceStructuringCanonicalCodecV1.sha256(self) } }

    func validateAllowedEnumValue(_ value: String, for fieldID: String) throws {
        try validate()
        try VoiceStructuringLimitsV1.identifier(fieldID)
        let releasedWords = aliases
            .filter { $0.fieldID == fieldID && $0.fieldKind == .allowedEnum }
            .flatMap(\.allowedEnumWords)
        guard !releasedWords.isEmpty else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        let normalizedReleasedWords = try releasedWords.map {
            try VoiceStructuringLimitsV1.normalizedPhrase(
                $0,
                localeIdentifier: localeIdentifier
            )
        }
        let normalizedValue = try VoiceStructuringLimitsV1.normalizedPhrase(
            value,
            localeIdentifier: localeIdentifier
        )
        guard value == normalizedValue,
              Set(normalizedReleasedWords).count == normalizedReleasedWords.count,
              Set(normalizedReleasedWords).contains(normalizedValue) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }
}

struct VoiceStructuringSemanticFieldV1: Codable, Equatable, Hashable, Sendable {
    let purpose: VoiceStructuringSemanticPurposeV1
    var fieldID: String { purpose.rawValue }
    var kind: VoiceStructuredFieldKindV1 { purpose.requiredKind }

    init(purpose: VoiceStructuringSemanticPurposeV1) {
        self.purpose = purpose
    }

    func validate() throws {
        try VoiceStructuringLimitsV1.identifier(fieldID)
    }
}

struct VoiceStructuringGrammarRegistryEntryV1: Codable, Equatable, Sendable {
    let release: VoiceStructuringGrammarReleaseV1
    let releaseSHA256: String
    let semanticFields: [VoiceStructuringSemanticFieldV1]

    init(
        release: VoiceStructuringGrammarReleaseV1,
        semanticFields: [VoiceStructuringSemanticFieldV1]
    ) throws {
        self.release = release
        releaseSHA256 = try release.releaseSHA256
        self.semanticFields = semanticFields
        try validate()
    }

    func validate() throws {
        try release.validate()
        try VoiceStructuringLimitsV1.digest(releaseSHA256)
        try semanticFields.forEach { try $0.validate() }
        let orderedFields = semanticFields.sorted { $0.fieldID < $1.fieldID }
        let releaseFields = Dictionary(
            release.aliases.map { ($0.fieldID, $0.fieldKind) },
            uniquingKeysWith: { first, _ in first }
        )
        guard releaseSHA256 == (try release.releaseSHA256),
              !semanticFields.isEmpty,
              semanticFields == orderedFields,
              Set(semanticFields.map(\.fieldID)).count == semanticFields.count,
              Set(semanticFields.map(\.purpose)).count == semanticFields.count,
              releaseFields.count == semanticFields.count,
              semanticFields.allSatisfy({ releaseFields[$0.fieldID] == $0.kind }) else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
    }
}

/// A composition-root-owned closed registry. Structuring services resolve only
/// exact registered release tuples and never accept caller-provided grammars.
struct VoiceStructuringGrammarRegistryV1: Codable, Equatable, Sendable {
    let entries: [VoiceStructuringGrammarRegistryEntryV1]

    init(entries: [VoiceStructuringGrammarRegistryEntryV1]) throws {
        self.entries = entries
        try validate()
    }

    func validate() throws {
        guard !entries.isEmpty,
              entries.count <= VoiceStructuringLimitsV1.maximumGrammarReleases else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        try entries.forEach { try $0.validate() }
        let keys = entries.map {
            "\($0.release.grammarID)|\($0.release.version)|\($0.release.localeIdentifier)|\($0.releaseSHA256)"
        }
        let releaseCoordinates = entries.map {
            "\($0.release.grammarID)|\($0.release.version)|\($0.release.localeIdentifier)"
        }
        guard keys == keys.sorted(), Set(keys).count == keys.count,
              Set(releaseCoordinates).count == releaseCoordinates.count else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
    }

    func resolve(
        grammarID: String,
        version: UInt64,
        localeIdentifier: String,
        releaseSHA256: String
    ) throws -> VoiceStructuringGrammarReleaseV1 {
        try VoiceStructuringLimitsV1.identifier(grammarID)
        try VoiceStructuringLimitsV1.identifier(localeIdentifier)
        try VoiceStructuringLimitsV1.digest(releaseSHA256)
        guard let entry = entries.first(where: {
            $0.release.grammarID == grammarID
                && $0.release.version == version
                && $0.release.localeIdentifier == localeIdentifier
                && $0.releaseSHA256 == releaseSHA256
        }) else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        try entry.validate()
        return entry.release
    }

    func resolve(
        grammarID: String,
        version: UInt64,
        localeIdentifier: String
    ) throws -> VoiceStructuringGrammarReleaseV1 {
        let matches = entries.filter {
            $0.release.grammarID == grammarID
                && $0.release.version == version
                && $0.release.localeIdentifier == localeIdentifier
        }
        guard matches.count == 1 else { throw VoiceStructuringFailureV1.incompatibleGrammar }
        try matches[0].validate()
        return matches[0].release
    }
}

struct VoiceProposalContextV1: Codable, Equatable, Sendable {
    let capability: AssistanceCapabilityReferenceV1
    let workspaceID: WorkspaceID
    let entity: WorkspaceEntityIdentityV1
    let targetRevision: UInt64
    let source: AssistanceSourceReferenceV1
    let packageReleaseSHA256: String?
    let definitionReleaseSHA256: String?

    init(
        capability: AssistanceCapabilityReferenceV1,
        workspaceID: WorkspaceID,
        entity: WorkspaceEntityIdentityV1,
        targetRevision: UInt64,
        source: AssistanceSourceReferenceV1,
        packageReleaseSHA256: String? = nil,
        definitionReleaseSHA256: String? = nil
    ) throws {
        self.capability = capability
        self.workspaceID = workspaceID
        self.entity = entity
        self.targetRevision = targetRevision
        self.source = source
        self.packageReleaseSHA256 = packageReleaseSHA256
        self.definitionReleaseSHA256 = definitionReleaseSHA256
        try validate()
    }

    func validate() throws {
        try capability.validate()
        _ = try WorkspaceEntityIdentityV1(kind: entity.kind, id: entity.id)
        try source.validate()
        try packageReleaseSHA256.map(VoiceStructuringLimitsV1.digest)
        try definitionReleaseSHA256.map(VoiceStructuringLimitsV1.digest)
        guard targetRevision > 0 else { throw VoiceStructuringFailureV1.invalidValue }
    }
}

struct StructuredVoiceFieldProposalV1: Codable, Equatable, Sendable {
    let fieldID: String
    let kind: VoiceStructuredFieldKindV1
    let sourceSpan: VoiceTranscriptUTF8SpanV1
    let resolution: VoiceStructuringResolutionV1
    let proposedValue: VoiceStructuredFieldValueV1?
    let alternatives: [VoiceStructuredFieldValueV1]

    init(
        fieldID: String,
        kind: VoiceStructuredFieldKindV1,
        sourceSpan: VoiceTranscriptUTF8SpanV1,
        resolution: VoiceStructuringResolutionV1,
        proposedValue: VoiceStructuredFieldValueV1?,
        alternatives: [VoiceStructuredFieldValueV1] = []
    ) throws {
        self.fieldID = fieldID
        self.kind = kind
        self.sourceSpan = sourceSpan
        self.resolution = resolution
        self.proposedValue = proposedValue
        self.alternatives = alternatives
        try validate()
    }

    func validate() throws {
        try VoiceStructuringLimitsV1.identifier(fieldID)
        try proposedValue?.validate(for: kind)
        try alternatives.forEach { try $0.validate(for: kind) }
        guard alternatives.count <= VoiceStructuringLimitsV1.maximumAlternatives,
              Set(alternatives).count == alternatives.count,
              proposedValue.map({ !alternatives.contains($0) }) ?? true else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        switch resolution {
        case .exact:
            guard proposedValue != nil, alternatives.isEmpty else { throw VoiceStructuringFailureV1.invalidValue }
            if case .material(let material)? = proposedValue {
                guard material.quantity != nil else { throw VoiceStructuringFailureV1.invalidValue }
            }
        case .ambiguous:
            guard !alternatives.isEmpty else { throw VoiceStructuringFailureV1.invalidValue }
            if proposedValue == nil {
                guard kind == .materialDescriptionAndQuantity,
                      alternatives.allSatisfy({ alternative in
                          if case .material(let material) = alternative {
                              return material.quantity == nil
                          }
                          return false
                      }) else {
                    throw VoiceStructuringFailureV1.invalidValue
                }
            }
        case .unsupported:
            guard proposedValue == nil, alternatives.isEmpty else {
                throw VoiceStructuringFailureV1.invalidValue
            }
        }
    }
}

enum VoiceUnmatchedClauseReasonV1: String, Codable, CaseIterable, Sendable {
    case noExplicitGrammarMatch = "NO_EXPLICIT_GRAMMAR_MATCH"
    case multipleExplicitGrammarMatches = "MULTIPLE_EXPLICIT_GRAMMAR_MATCHES"
    case valueOutsideClosedGrammar = "VALUE_OUTSIDE_CLOSED_GRAMMAR"
    case rejectedByFieldValidation = "REJECTED_BY_FIELD_VALIDATION"
}

struct VoiceUnmatchedClauseV1: Codable, Equatable, Sendable {
    let occurrenceID: String
    let sourceSpan: VoiceTranscriptUTF8SpanV1
    let resolution: VoiceStructuringResolutionV1
    let reason: VoiceUnmatchedClauseReasonV1

    init(
        occurrenceID: String,
        sourceSpan: VoiceTranscriptUTF8SpanV1,
        resolution: VoiceStructuringResolutionV1,
        reason: VoiceUnmatchedClauseReasonV1
    ) throws {
        try VoiceStructuringLimitsV1.identifier(occurrenceID)
        guard resolution == .ambiguous || resolution == .unsupported else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        self.occurrenceID = occurrenceID
        self.sourceSpan = sourceSpan
        self.resolution = resolution
        self.reason = reason
    }

    func validate() throws {
        _ = try Self(
            occurrenceID: occurrenceID,
            sourceSpan: sourceSpan,
            resolution: resolution,
            reason: reason
        )
    }
}

struct StructuredVoiceProposalV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let proposalID: UUID
    let grammarID: String
    let grammarVersion: UInt64
    let grammarReleaseSHA256: String
    let localeIdentifier: String
    let context: VoiceProposalContextV1
    let transcript: String
    let transcriptSHA256: String
    let fields: [StructuredVoiceFieldProposalV1]
    let unmatchedClauses: [VoiceUnmatchedClauseV1]
    let createdAt: Date
    let expiresAt: Date

    init(
        proposalID: UUID,
        grammar: VoiceStructuringGrammarReleaseV1,
        context: VoiceProposalContextV1,
        transcript: String,
        fields: [StructuredVoiceFieldProposalV1],
        unmatchedClauses: [VoiceUnmatchedClauseV1],
        createdAt: Date,
        expiresAt: Date
    ) throws {
        schemaVersion = Self.schemaVersion
        self.proposalID = proposalID
        grammarID = grammar.grammarID
        grammarVersion = grammar.version
        grammarReleaseSHA256 = try grammar.releaseSHA256
        localeIdentifier = grammar.localeIdentifier
        self.context = context
        self.transcript = transcript
        transcriptSHA256 = VoiceStructuringLimitsV1.transcriptSHA256(transcript)
        self.fields = fields
        self.unmatchedClauses = unmatchedClauses
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        try validate(grammar: grammar)
    }

    func validate() throws {
        try validateCommon()
    }

    func validate(grammar: VoiceStructuringGrammarReleaseV1) throws {
        try validateCommon()
        try grammar.validate()
        guard grammarID == grammar.grammarID, grammarVersion == grammar.version,
              localeIdentifier == grammar.localeIdentifier,
              localeIdentifier == context.capability.localeIdentifier,
              grammarReleaseSHA256 == (try grammar.releaseSHA256) else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        let grammarFields = Dictionary(
            grammar.aliases.map { ($0.fieldID, $0.fieldKind) },
            uniquingKeysWith: { first, _ in first }
        )
        guard fields.allSatisfy({ grammarFields[$0.fieldID] == $0.kind }) else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        for field in fields where field.kind == .allowedEnum {
            let values = [field.proposedValue].compactMap { $0 } + field.alternatives
            for value in values {
                guard case .allowedEnum(let word) = value else {
                    throw VoiceStructuringFailureV1.invalidValue
                }
                try grammar.validateAllowedEnumValue(word, for: field.fieldID)
            }
        }
    }

    func requireCurrent(at instant: Date, context current: VoiceProposalContextV1) throws {
        try VoiceStructuringLimitsV1.instant(instant)
        try current.validate()
        guard instant < expiresAt, current == context else { throw VoiceStructuringFailureV1.expired }
    }

    var proposalSHA256: String { get throws { try VoiceStructuringCanonicalCodecV1.sha256(self) } }

    private func validateCommon() throws {
        try VoiceStructuringLimitsV1.identifier(grammarID)
        try VoiceStructuringLimitsV1.identifier(localeIdentifier)
        try VoiceStructuringLimitsV1.digest(grammarReleaseSHA256)
        try VoiceStructuringLimitsV1.digest(transcriptSHA256)
        try context.validate()
        try VoiceStructuringLimitsV1.userText(
            transcript,
            maximum: VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes
        )
        try VoiceStructuringLimitsV1.instant(createdAt)
        try VoiceStructuringLimitsV1.instant(expiresAt)
        try fields.forEach { try $0.validate(); try $0.sourceSpan.validate(in: transcript) }
        try unmatchedClauses.forEach {
            try $0.validate()
            try $0.sourceSpan.validate(in: transcript)
        }
        let orderedFields = fields.sorted {
            ($0.sourceSpan.start, $0.sourceSpan.end, $0.fieldID)
                < ($1.sourceSpan.start, $1.sourceSpan.end, $1.fieldID)
        }
        guard fields == orderedFields else { throw VoiceStructuringFailureV1.invalidSpan }
        for index in fields.indices.dropFirst() {
            guard fields[index].sourceSpan.start >= fields[index - 1].sourceSpan.end else {
                throw VoiceStructuringFailureV1.invalidSpan
            }
        }
        let orderedClauses = unmatchedClauses.sorted {
            ($0.sourceSpan.start, $0.sourceSpan.end, $0.occurrenceID)
                < ($1.sourceSpan.start, $1.sourceSpan.end, $1.occurrenceID)
        }
        guard unmatchedClauses == orderedClauses else {
            throw VoiceStructuringFailureV1.invalidSpan
        }
        let occupiedSpans = (fields.map { ($0.sourceSpan.start, $0.sourceSpan.end) }
            + unmatchedClauses.map { ($0.sourceSpan.start, $0.sourceSpan.end) })
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        for index in occupiedSpans.indices.dropFirst() {
            guard occupiedSpans[index].0 >= occupiedSpans[index - 1].1 else {
                throw VoiceStructuringFailureV1.invalidSpan
            }
        }
        guard schemaVersion == Self.schemaVersion, proposalID != UUID.zero,
              grammarVersion > 0,
              localeIdentifier == context.capability.localeIdentifier,
              transcript.utf8.count <= VoiceStructuringLimitsV1.maximumTranscriptUTF8Bytes,
              transcriptSHA256 == VoiceStructuringLimitsV1.transcriptSHA256(transcript),
              context.source.contentSHA256 == transcriptSHA256,
              !fields.isEmpty || !unmatchedClauses.isEmpty,
              fields.count <= VoiceStructuringLimitsV1.maximumFields,
              unmatchedClauses.count <= VoiceStructuringLimitsV1.maximumUnmatchedClauses,
              Set(fields.map(\.fieldID)).count == fields.count,
              Set(unmatchedClauses.map(\.occurrenceID)).count == unmatchedClauses.count,
              expiresAt > createdAt,
              expiresAt.timeIntervalSince(createdAt) <= VoiceStructuringLimitsV1.maximumLifetime else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }
}

enum VoiceProposalFieldReviewDispositionV1: String, Codable, CaseIterable, Sendable {
    case accept = "ACCEPT"
    case edit = "EDIT"
    case reject = "REJECT"
}

struct VoiceProposalFieldReviewV1: Codable, Equatable, Sendable {
    let fieldID: String
    let disposition: VoiceProposalFieldReviewDispositionV1
    let reviewedValue: VoiceStructuredFieldValueV1?

    init(
        fieldID: String,
        disposition: VoiceProposalFieldReviewDispositionV1,
        reviewedValue: VoiceStructuredFieldValueV1?
    ) throws {
        try VoiceStructuringLimitsV1.identifier(fieldID)
        guard (disposition == .reject) == (reviewedValue == nil) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        self.fieldID = fieldID
        self.disposition = disposition
        self.reviewedValue = reviewedValue
    }

    func validate() throws {
        try VoiceStructuringLimitsV1.identifier(fieldID)
        guard (disposition == .reject) == (reviewedValue == nil) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }
}

struct VoiceProposalReviewPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let proposalID: UUID
    let proposalSHA256: String
    let fieldReviews: [VoiceProposalFieldReviewV1]
    let reviewedAt: Date

    init(
        proposal: StructuredVoiceProposalV1,
        fieldReviews: [VoiceProposalFieldReviewV1],
        reviewedAt: Date
    ) throws {
        schemaVersion = Self.schemaVersion
        proposalID = proposal.proposalID
        proposalSHA256 = try proposal.proposalSHA256
        self.fieldReviews = fieldReviews
        self.reviewedAt = reviewedAt
        try validate(against: proposal)
    }

    func validate() throws {
        try VoiceStructuringLimitsV1.digest(proposalSHA256)
        try VoiceStructuringLimitsV1.instant(reviewedAt)
        try fieldReviews.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion, proposalID != UUID.zero,
              fieldReviews.count <= VoiceStructuringLimitsV1.maximumFields,
              Set(fieldReviews.map(\.fieldID)).count == fieldReviews.count else {
            throw VoiceStructuringFailureV1.invalidValue
        }
    }

    func validate(against proposal: StructuredVoiceProposalV1) throws {
        try validate()
        try proposal.validate()
        try VoiceStructuringLimitsV1.digest(proposalSHA256)
        try VoiceStructuringLimitsV1.instant(reviewedAt)
        let candidates = Dictionary(uniqueKeysWithValues: proposal.fields.map { ($0.fieldID, $0) })
        guard schemaVersion == Self.schemaVersion, proposalID == proposal.proposalID,
              proposalSHA256 == (try proposal.proposalSHA256),
              fieldReviews.count == proposal.fields.count,
              fieldReviews.map(\.fieldID) == proposal.fields.map(\.fieldID),
              Set(fieldReviews.map(\.fieldID)) == Set(candidates.keys),
              reviewedAt >= proposal.createdAt,
              reviewedAt < proposal.expiresAt else {
            throw VoiceStructuringFailureV1.incompleteReview
        }
        for review in fieldReviews {
            guard let candidate = candidates[review.fieldID] else {
                throw VoiceStructuringFailureV1.incompleteReview
            }
            switch review.disposition {
            case .accept:
                guard candidate.resolution == .exact,
                      let proposedValue = candidate.proposedValue,
                      review.reviewedValue == proposedValue else {
                    throw VoiceStructuringFailureV1.invalidValue
                }
            case .edit:
                guard let value = review.reviewedValue else { throw VoiceStructuringFailureV1.invalidValue }
                try value.validate(for: candidate.kind)
            case .reject:
                guard review.reviewedValue == nil else { throw VoiceStructuringFailureV1.invalidValue }
            }
        }
    }

    func validate(
        against proposal: StructuredVoiceProposalV1,
        grammar: VoiceStructuringGrammarReleaseV1
    ) throws {
        try proposal.validate(grammar: grammar)
        try validate(against: proposal)
        let candidates = Dictionary(uniqueKeysWithValues: proposal.fields.map { ($0.fieldID, $0) })
        for review in fieldReviews {
            guard let candidate = candidates[review.fieldID] else {
                throw VoiceStructuringFailureV1.incompleteReview
            }
            guard candidate.kind == .allowedEnum else { continue }
            guard let reviewedValue = review.reviewedValue,
                  case .allowedEnum(let word) = reviewedValue else {
                if review.disposition == .reject { continue }
                throw VoiceStructuringFailureV1.invalidValue
            }
            try grammar.validateAllowedEnumValue(word, for: candidate.fieldID)
        }
    }

    var planSHA256: String { get throws { try VoiceStructuringCanonicalCodecV1.sha256(self) } }

    func validateForConsumption(
        against proposal: StructuredVoiceProposalV1,
        registry: VoiceStructuringGrammarRegistryV1,
        currentContext: VoiceProposalContextV1,
        at instant: Date
    ) throws {
        try registry.validate()
        let grammar = try registry.resolve(
            grammarID: proposal.grammarID,
            version: proposal.grammarVersion,
            localeIdentifier: proposal.localeIdentifier,
            releaseSHA256: proposal.grammarReleaseSHA256
        )
        try proposal.requireCurrent(at: instant, context: currentContext)
        try validate(against: proposal, grammar: grammar)
        guard reviewedAt <= instant else { throw VoiceStructuringFailureV1.invalidValue }
    }
}

enum VoiceStructuringCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try WorkspaceMutationCanonicalV1.data(value)
        guard !data.isEmpty, data.count <= VoiceStructuringLimitsV1.maximumCanonicalBytes else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        return data
    }

    static func decode<T: Decodable & Encodable & VoiceStructuringCanonicalValidatingV1>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        guard !data.isEmpty, data.count <= VoiceStructuringLimitsV1.maximumCanonicalBytes else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        try value.validate()
        guard try encode(value) == data else { throw VoiceStructuringFailureV1.invalidValue }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        _ = try encode(value)
        return try WorkspaceMutationCanonicalV1.sha256(value)
    }

    static func decodeProposal(
        from data: Data,
        registry: VoiceStructuringGrammarRegistryV1,
        currentContext: VoiceProposalContextV1,
        at instant: Date
    ) throws -> StructuredVoiceProposalV1 {
        try registry.validate()
        let proposal = try decodeUnchecked(StructuredVoiceProposalV1.self, from: data)
        let grammar = try registry.resolve(
            grammarID: proposal.grammarID,
            version: proposal.grammarVersion,
            localeIdentifier: proposal.localeIdentifier,
            releaseSHA256: proposal.grammarReleaseSHA256
        )
        try proposal.validate(grammar: grammar)
        try proposal.requireCurrent(at: instant, context: currentContext)
        return proposal
    }

    static func decodeReviewPlan(
        from data: Data,
        proposal: StructuredVoiceProposalV1,
        registry: VoiceStructuringGrammarRegistryV1,
        currentContext: VoiceProposalContextV1,
        at instant: Date
    ) throws -> VoiceProposalReviewPlanV1 {
        let plan = try decodeUnchecked(VoiceProposalReviewPlanV1.self, from: data)
        try plan.validateForConsumption(
            against: proposal,
            registry: registry,
            currentContext: currentContext,
            at: instant
        )
        return plan
    }

    private static func decodeUnchecked<T: Decodable & Encodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        guard !data.isEmpty, data.count <= VoiceStructuringLimitsV1.maximumCanonicalBytes else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw VoiceStructuringFailureV1.invalidValue }
        return value
    }
}

enum VoiceStructuringNonpersistentLifecycleV1 {
    static let persistentFamilyCount = 0
    static let canonicalWritePermitted = false
    static let backupSearchReportJournalEnrollmentPermitted = false
    static let scratchDeletedAfterReviewExpiryOrCancellation = true
    static let reusesAssistanceContextAndLifecycleAuthority = true
    static let directAssistanceProposalPayloadPermitted = false
}

extension VoiceStructuringGrammarReleaseV1: VoiceStructuringCanonicalValidatingV1 {}
extension VoiceStructuringSemanticFieldV1: VoiceStructuringCanonicalValidatingV1 {}
extension VoiceStructuringGrammarRegistryEntryV1: VoiceStructuringCanonicalValidatingV1 {}
extension VoiceStructuringGrammarRegistryV1: VoiceStructuringCanonicalValidatingV1 {}
extension VoiceProposalContextV1: VoiceStructuringCanonicalValidatingV1 {}
extension StructuredVoiceFieldProposalV1: VoiceStructuringCanonicalValidatingV1 {}
extension VoiceUnmatchedClauseV1: VoiceStructuringCanonicalValidatingV1 {}

private extension UUID {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

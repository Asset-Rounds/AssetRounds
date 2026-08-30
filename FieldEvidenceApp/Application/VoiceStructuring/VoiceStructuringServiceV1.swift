import Foundation
import CryptoKit

protocol VoiceStructuredProposalAuthenticatingV1: Sendable {
    func validateDeterministicProposal(_ proposal: StructuredVoiceProposalV1) throws
}

/// Pure, bounded C56 parser. Capture, permissions, audio, persistence, and
/// canonical acceptance remain owned by their existing adapters.
struct VoiceStructuringServiceV1: Sendable, VoiceStructuredProposalAuthenticatingV1 {
    typealias Clock = @Sendable () -> Date
    typealias IDSource = @Sendable () -> UUID

    private static let maximumClauses = 64
    private static let maximumTokensPerClause = 128
    private static let maximumTextUTF8Bytes = 4_096
    private static let lifetime: TimeInterval = 30 * 60

    let grammar: VoiceStructuringGrammarReleaseV1
    let semanticFields: [VoiceStructuringSemanticFieldV1]
    private let now: Clock
    private let makeID: IDSource

    init(
        registry: VoiceStructuringGrammarRegistryV1,
        grammarID: String,
        version: UInt64,
        localeIdentifier: String,
        releaseSHA256: String,
        now: @escaping Clock = { Date() },
        makeID: @escaping IDSource = { UUID() }
    ) throws {
        try registry.validate()
        let matchingEntries = registry.entries.filter {
            $0.release.grammarID == grammarID
                && $0.release.version == version
                && $0.release.localeIdentifier == localeIdentifier
                && $0.releaseSHA256 == releaseSHA256
        }
        guard matchingEntries.count == 1, let entry = matchingEntries.first else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        try entry.validate()
        let grammar = try registry.resolve(
            grammarID: grammarID,
            version: version,
            localeIdentifier: localeIdentifier,
            releaseSHA256: releaseSHA256
        )
        try grammar.validate()
        guard grammar == entry.release else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        self.grammar = grammar
        semanticFields = entry.semanticFields
        self.now = now
        self.makeID = makeID
    }

    func structure(
        transcript: String,
        context: VoiceProposalContextV1
    ) throws -> StructuredVoiceProposalV1 {
        let createdAt = now()
        guard createdAt.timeIntervalSince1970.isFinite else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        let proposalID = makeID()
        guard proposalID != Self.zeroUUID else { throw VoiceStructuringFailureV1.invalidValue }
        return try buildDeterministicProposal(
            transcript: transcript,
            context: context,
            proposalID: proposalID,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(Self.lifetime)
        )
    }

    func validateDeterministicProposal(_ proposal: StructuredVoiceProposalV1) throws {
        try proposal.validate()
        let rebuilt = try buildDeterministicProposal(
            transcript: proposal.transcript,
            context: proposal.context,
            proposalID: proposal.proposalID,
            createdAt: proposal.createdAt,
            expiresAt: proposal.expiresAt
        )
        let rebuiltData = try VoiceStructuringCanonicalCodecV1.encode(rebuilt)
        let proposalData = try VoiceStructuringCanonicalCodecV1.encode(proposal)
        guard rebuilt == proposal, rebuiltData == proposalData else {
            throw VoiceStructuringFailureV1.invalidDigest
        }
    }

    private func buildDeterministicProposal(
        transcript: String,
        context: VoiceProposalContextV1,
        proposalID: UUID,
        createdAt: Date,
        expiresAt: Date
    ) throws -> StructuredVoiceProposalV1 {
        try grammar.validate()
        try context.validate()
        guard !transcript.isEmpty, transcript.utf8.count <= 32_768 else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        guard Self.supportedLocaleIdentifiers.contains(grammar.localeIdentifier),
              context.capability.localeIdentifier == grammar.localeIdentifier else {
            throw VoiceStructuringFailureV1.incompatibleGrammar
        }
        guard context.source.contentSHA256 == Self.rawTranscriptSHA256(transcript) else {
            throw VoiceStructuringFailureV1.invalidDigest
        }
        let releasedSemantics = Dictionary(
            uniqueKeysWithValues: semanticFields.map { ($0.fieldID, $0.kind) }
        )
        for alias in grammar.aliases {
            guard releasedSemantics[alias.fieldID] == alias.fieldKind else {
                throw VoiceStructuringFailureV1.incompatibleGrammar
            }
        }
        guard createdAt.timeIntervalSince1970.isFinite else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        guard expiresAt == createdAt.addingTimeInterval(Self.lifetime) else {
            throw VoiceStructuringFailureV1.invalidValue
        }
        guard proposalID != Self.zeroUUID else { throw VoiceStructuringFailureV1.invalidValue }

        let clauses = try Self.clauses(in: transcript)
        let aliases = grammar.aliases.sorted {
            let lhs = ($0.spokenAlias.lowercased(), $0.fieldID, $0.fieldKind.rawValue)
            let rhs = ($1.spokenAlias.lowercased(), $1.fieldID, $1.fieldKind.rawValue)
            return lhs < rhs
        }
        var byField: [String: [(StructuredVoiceFieldProposalV1, Clause)]] = [:]
        var unmatched: [VoiceUnmatchedClauseV1] = []
        for clause in clauses {
            let matches = Self.matches(
                clause.text, aliases: aliases, localeIdentifier: grammar.localeIdentifier
            )
            guard matches.count == 1, let match = matches.first else {
                unmatched.append(try Self.unmatched(
                    clause,
                    resolution: matches.isEmpty ? .unsupported : .ambiguous,
                    reason: matches.isEmpty
                        ? .noExplicitGrammarMatch : .multipleExplicitGrammarMatches
                ))
                continue
            }
            let valueStart = clause.start + match.valueStart
            let valueBytes = Array(clause.text.utf8.dropFirst(match.valueStart))
            let valueText = String(decoding: valueBytes, as: UTF8.self)
            let span = try VoiceTranscriptUTF8SpanV1(start: valueStart, length: valueBytes.count)
            let parsed = try Self.parse(
                valueText, alias: match.alias, localeIdentifier: grammar.localeIdentifier
            )
            guard parsed.resolution != .unsupported, parsed.proposed != nil else {
                unmatched.append(try Self.unmatched(
                    clause, resolution: parsed.resolution,
                    reason: parsed.resolution == .ambiguous
                        ? .valueOutsideClosedGrammar : .rejectedByFieldValidation
                ))
                continue
            }
            let field = try StructuredVoiceFieldProposalV1(
                fieldID: match.alias.fieldID,
                kind: match.alias.fieldKind,
                sourceSpan: span,
                resolution: parsed.resolution,
                proposedValue: parsed.proposed,
                alternatives: parsed.alternatives
            )
            byField[match.alias.fieldID, default: []].append((field, clause))
        }

        var fields: [StructuredVoiceFieldProposalV1] = []
        for fieldID in byField.keys.sorted() {
            guard let candidates = byField[fieldID], let first = candidates.first else { continue }
            if candidates.count == 1 {
                fields.append(first.0)
            } else {
                unmatched += try candidates.map {
                    try Self.unmatched(
                        $0.1, resolution: .ambiguous,
                        reason: .multipleExplicitGrammarMatches
                    )
                }
            }
        }
        fields.sort {
            ($0.sourceSpan.start, $0.fieldID, $0.kind.rawValue)
                < ($1.sourceSpan.start, $1.fieldID, $1.kind.rawValue)
        }
        unmatched.sort {
            ($0.sourceSpan.start, $0.sourceSpan.end, $0.occurrenceID)
                < ($1.sourceSpan.start, $1.sourceSpan.end, $1.occurrenceID)
        }
        return try StructuredVoiceProposalV1(
            proposalID: proposalID,
            grammar: grammar,
            context: context,
            transcript: transcript,
            fields: fields,
            unmatchedClauses: unmatched,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    private struct Clause {
        let occurrenceID: String
        let start: Int
        let text: String
    }

    private struct AliasMatch {
        let alias: VoiceStructuringAliasV1
        let valueStart: Int
    }

    private struct Parsed {
        let resolution: VoiceStructuringResolutionV1
        let proposed: VoiceStructuredFieldValueV1?
        let alternatives: [VoiceStructuredFieldValueV1]
    }

    private static func clauses(in transcript: String) throws -> [Clause] {
        let bytes = Array(transcript.utf8)
        var ranges: [Range<Int>] = []
        var start = 0
        for index in bytes.indices where bytes[index] == 0x0a || bytes[index] == 0x3b {
            ranges.append(start..<index); start = index + 1
        }
        ranges.append(start..<bytes.count)
        guard ranges.count <= maximumClauses else { throw VoiceStructuringFailureV1.invalidValue }
        return ranges.enumerated().compactMap { ordinal, range in
            var lower = range.lowerBound, upper = range.upperBound
            while lower < upper, isASCIISpace(bytes[lower]) { lower += 1 }
            while upper > lower, isASCIISpace(bytes[upper - 1]) { upper -= 1 }
            guard lower < upper else { return nil }
            return Clause(
                occurrenceID: "clause-\(ordinal + 1)",
                start: lower,
                text: String(decoding: bytes[lower..<upper], as: UTF8.self)
            )
        }
    }

    private static func matches(
        _ clause: String,
        aliases: [VoiceStructuringAliasV1],
        localeIdentifier: String
    ) -> [AliasMatch] {
        let bytes = Array(clause.utf8)
        var separatorStart: Int?
        var separatorEnd: Int?
        for index in bytes.indices {
            if bytes[index] == 0x3a || bytes[index] == 0x3d {
                separatorStart = index; separatorEnd = index + 1; break
            }
            if index >= 1, index + 2 < bytes.count,
               isASCIISpace(bytes[index - 1]),
               (bytes[index] == 0x69 || bytes[index] == 0x49),
               (bytes[index + 1] == 0x73 || bytes[index + 1] == 0x53),
               isASCIISpace(bytes[index + 2]) {
                separatorStart = index - 1; separatorEnd = index + 2; break
            }
        }
        guard var labelEnd = separatorStart, var valueStart = separatorEnd else { return [] }
        while labelEnd > 0, isASCIISpace(bytes[labelEnd - 1]) { labelEnd -= 1 }
        while valueStart < bytes.count, isASCIISpace(bytes[valueStart]) { valueStart += 1 }
        guard labelEnd > 0, valueStart < bytes.count else { return [] }
        let label = String(decoding: bytes[..<labelEnd], as: UTF8.self)
        let normalizedLabel = normalizedPhrase(label, localeIdentifier: localeIdentifier)
        return aliases.compactMap {
            normalizedPhrase($0.spokenAlias, localeIdentifier: localeIdentifier) == normalizedLabel
                ? AliasMatch(alias: $0, valueStart: valueStart) : nil
        }
    }

    private static func unmatched(
        _ clause: Clause,
        resolution: VoiceStructuringResolutionV1,
        reason: VoiceUnmatchedClauseReasonV1
    ) throws -> VoiceUnmatchedClauseV1 {
        try VoiceUnmatchedClauseV1(
            occurrenceID: clause.occurrenceID,
            sourceSpan: VoiceTranscriptUTF8SpanV1(
                start: clause.start, length: clause.text.utf8.count
            ),
            resolution: resolution,
            reason: reason
        )
    }

    private static func parse(
        _ text: String,
        alias: VoiceStructuringAliasV1,
        localeIdentifier: String
    ) throws -> Parsed {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty, words.count <= maximumTokensPerClause else { return unsupported }
        switch alias.fieldKind {
        case .noteText, .findingText:
            guard text.utf8.count <= maximumTextUTF8Bytes else { return unsupported }
            return Parsed(resolution: .exact, proposed: .text(text), alternatives: [])
        case .allowedEnum:
            let normalizedValue = normalizedPhrase(text, localeIdentifier: "en_US_POSIX")
            let matches = alias.allowedEnumWords.filter {
                normalizedPhrase($0, localeIdentifier: "en_US_POSIX") == normalizedValue
            }.sorted()
            guard let first = matches.first else { return unsupported }
            let values = matches.map(VoiceStructuredFieldValueV1.allowedEnum)
            return Parsed(resolution: values.count == 1 ? .exact : .ambiguous,
                          proposed: values[0], alternatives: Array(values.dropFirst()))
        case .exactNumberAndUnit:
            guard words.count == 2,
                  let decimal = try exactDecimal(
                    words[0], unit: words[1], locale: localeIdentifier
                  ) else {
                return unsupported
            }
            return Parsed(resolution: .exact, proposed: .exactNumber(decimal), alternatives: [])
        case .duration:
            guard words.count == 2,
                  let seconds = durationSeconds(
                    words[0], unit: words[1], locale: localeIdentifier
                  ) else {
                return unsupported
            }
            return Parsed(resolution: .exact, proposed: .durationSeconds(seconds), alternatives: [])
        case .materialDescriptionAndQuantity:
            let beginsWithNumericToken = words.first.map(Self.looksNumeric) ?? false
            if beginsWithNumericToken {
                guard words.count >= 3 else { return unsupported }
                guard let quantity = try exactDecimal(
                    words[0], unit: words[1], locale: localeIdentifier
                ), quantity.mantissa > 0,
                   quantity.unit != .each || quantity.scale == 0 else {
                    return unsupported
                }
                let description = words.dropFirst(2).joined(separator: " ")
                guard !description.isEmpty else { return unsupported }
                return Parsed(resolution: .exact,
                              proposed: .material(try VoiceMaterialProposalValueV1(
                                description: description, quantity: quantity)), alternatives: [])
            }
            let material = try VoiceMaterialProposalValueV1(description: text, quantity: nil)
            return Parsed(
                resolution: .ambiguous,
                proposed: nil,
                alternatives: [.material(material)]
            )
        }
    }

    private static func exactDecimal(
        _ token: String,
        unit: String,
        locale: String
    ) throws -> VoiceExactDecimalV1? {
        guard supportedLocaleIdentifiers.contains(locale), !token.contains(",") else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        let negative = parts[0].hasPrefix("-")
        let integerDigits = negative ? parts[0].dropFirst() : parts[0][...]
        guard parts.count <= 2, !integerDigits.isEmpty,
              integerDigits.utf8.allSatisfy({ (48...57).contains($0) }),
              parts.dropFirst().allSatisfy({
                $0.utf8.allSatisfy { (48...57).contains($0) }
              }),
              (parts.count == 1 || (1...3).contains(parts[1].count)) else { return nil }
        let digits = (negative ? "-" : "") + ([String(integerDigits)] + parts.dropFirst().map(String.init)).joined()
        guard let mantissa = Int64(digits) else { return nil }
        guard let structuredUnit = normalizedStructuredUnit(unit) else { return nil }
        return try VoiceExactDecimalV1(mantissa: mantissa,
                                       scale: parts.count == 2 ? parts[1].count : 0,
                                       unit: structuredUnit)
    }

    private static func durationSeconds(_ token: String, unit: String, locale: String) -> UInt64? {
        guard supportedLocaleIdentifiers.contains(locale), !token.contains(",") else { return nil }
        guard let value = UInt64(token), value > 0 else { return nil }
        guard let durationUnit = normalizedDurationUnit(unit) else { return nil }
        let multiplier: UInt64
        switch durationUnit {
        case "SECOND": multiplier = 1
        case "MINUTE": multiplier = 60
        case "HOUR": multiplier = 3_600
        case "DAY": multiplier = 86_400
        default: return nil
        }
        let result = value.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow, result.partialValue <= 31_536_000 else { return nil }
        return result.partialValue
    }

    private static func normalizedStructuredUnit(_ value: String) -> VoiceStructuredUnitV1? {
        let word = value.lowercased()
        let singular = word.hasSuffix("s") ? String(word.dropLast()) : word
        switch singular {
        case "ea", "each": return .each
        case "%", "percent": return .percent
        case "mm", "millimeter": return .millimeter
        case "cm", "centimeter": return .centimeter
        case "m", "meter": return .meter
        case "in", "inch", "inche": return .inch
        case "ft", "foot", "feet": return .foot
        case "g", "gram": return .gram
        case "kg", "kilogram": return .kilogram
        case "oz", "ounce": return .ounce
        case "lb", "pound": return .pound
        case "ml", "milliliter": return .milliliter
        case "l", "liter": return .liter
        case "gal", "gallon": return .gallon
        default: return nil
        }
    }

    private static func normalizedDurationUnit(_ value: String) -> String? {
        let word = value.lowercased()
        let singular = word.hasSuffix("s") ? String(word.dropLast()) : word
        switch singular {
        case "sec", "second": return "SECOND"
        case "min", "minute": return "MINUTE"
        case "hr", "hour": return "HOUR"
        case "day": return "DAY"
        default: return nil
        }
    }

    private static func looksNumeric(_ value: String) -> Bool {
        guard let first = value.utf8.first else { return false }
        return (48...57).contains(first) || first == 0x2d
    }

    private static func normalizedPhrase(
        _ value: String,
        localeIdentifier: String
    ) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: localeIdentifier)
        ).precomposedStringWithCanonicalMapping
    }

    private static func rawTranscriptSHA256(_ transcript: String) -> String {
        SHA256.hash(data: Data(transcript.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static let unsupported = Parsed(
        resolution: .unsupported, proposed: nil, alternatives: []
    )
    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
    private static let supportedLocaleIdentifiers: Set<String> = [
        "en", "en-US", "en_US_POSIX",
    ]
    private static func isASCIISpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0d
    }
}

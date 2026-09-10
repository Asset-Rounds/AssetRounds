import Foundation

enum GlobalizedSearchNormalizationAlgorithmV1: Int, Codable, CaseIterable, Sendable {
    case v1 = 1

    static let maximumCJKChunkScalars = 32
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let bidiFormattingScalars: Set<UInt32> = [
        0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    static func normalizedText(from value: String) -> String {
        let safe = String(String.UnicodeScalarView(value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
                && !bidiFormattingScalars.contains($0.value)
        }))
        var output = ""
        var latinRun = ""
        func appendFoldedLatinRun() {
            guard !latinRun.isEmpty else { return }
            output += latinRun
                .decomposedStringWithCompatibilityMapping
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: posixLocale
                )
                .lowercased(with: posixLocale)
                .precomposedStringWithCanonicalMapping
            latinRun = ""
        }
        for scalar in safe.unicodeScalars {
            if scalar.isLatinBase || (!latinRun.isEmpty && scalar.isUnicodeMark) {
                latinRun.unicodeScalars.append(scalar)
            } else {
                appendFoldedLatinRun()
                output.unicodeScalars.append(scalar)
            }
        }
        appendFoldedLatinRun()
        return output.precomposedStringWithCanonicalMapping
    }

    static func projectionMaterial(from normalizedText: String) throws -> GlobalizedSearchDerivedMaterialV1 {
        try material(from: normalizedText, maximumTokens: SearchContractLimitsV1.maximumProjectionTokens, permitsCJKChunks: true)
    }

    static func queryMaterial(from normalizedText: String) throws -> GlobalizedSearchDerivedMaterialV1 {
        try material(from: normalizedText, maximumTokens: SearchContractLimitsV1.maximumQueryTokens, permitsCJKChunks: false)
    }

    static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.isCJKSearchScalar }
    }

    static func excludesBidiFormatting(_ scalar: Unicode.Scalar) -> Bool {
        !bidiFormattingScalars.contains(scalar.value)
    }

    private static func material(
        from normalizedText: String,
        maximumTokens: Int,
        permitsCJKChunks: Bool
    ) throws -> GlobalizedSearchDerivedMaterialV1 {
        var candidates: [String] = []
        var wordScalars: [Unicode.Scalar] = []
        var cjkRunCount = 0
        var cjkChunkCount = 0
        let scalars = Array(normalizedText.unicodeScalars)
        var index = 0
        func appendWord() throws {
            guard !wordScalars.isEmpty else { return }
            let token = String(String.UnicodeScalarView(wordScalars))
            guard token.utf8.count <= SearchContractLimitsV1.maximumNormalizedTokenBytes else {
                throw SearchContractFailureV1.limitExceeded
            }
            candidates.append(token)
            wordScalars = []
        }
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.isCJKSearchScalar {
                try appendWord()
                let start = index
                while index < scalars.count, scalars[index].isCJKSearchScalar { index += 1 }
                let run = Array(scalars[start..<index])
                cjkRunCount += 1
                let fullRun = String(String.UnicodeScalarView(run))
                if fullRun.utf8.count <= SearchContractLimitsV1.maximumNormalizedTokenBytes {
                    candidates.append(fullRun)
                    cjkChunkCount += 1
                } else {
                    guard permitsCJKChunks else { throw SearchContractFailureV1.limitExceeded }
                    var chunkStart = 0
                    while chunkStart < run.count {
                        var chunkEnd = chunkStart
                        var byteCount = 0
                        while chunkEnd < run.count,
                              chunkEnd - chunkStart < maximumCJKChunkScalars {
                            let nextBytes = String(run[chunkEnd]).utf8.count
                            guard byteCount + nextBytes <= SearchContractLimitsV1.maximumNormalizedTokenBytes else { break }
                            byteCount += nextBytes
                            chunkEnd += 1
                        }
                        guard chunkEnd > chunkStart else { throw SearchContractFailureV1.limitExceeded }
                        candidates.append(String(String.UnicodeScalarView(run[chunkStart..<chunkEnd])))
                        cjkChunkCount += 1
                        chunkStart = chunkEnd
                    }
                }
                continue
            }
            if CharacterSet.alphanumerics.contains(scalar) || scalar.isUnicodeMark {
                wordScalars.append(scalar)
            } else {
                try appendWord()
            }
            index += 1
        }
        try appendWord()
        let tokens = Array(Set(candidates)).sorted()
        guard tokens.count <= maximumTokens else { throw SearchContractFailureV1.limitExceeded }
        return GlobalizedSearchDerivedMaterialV1(tokens: tokens, cjkRunCount: cjkRunCount, cjkChunkCount: cjkChunkCount)
    }
}

struct GlobalizedSearchDerivedMaterialV1: Equatable, Sendable {
    let tokens: [String]
    let cjkRunCount: Int
    let cjkChunkCount: Int
}

enum GlobalizedSearchCJKSegmentationStrategyV1: String, Codable, CaseIterable, Sendable {
    case completeRunsAndBoundedChunks = "COMPLETE_RUNS_AND_BOUNDED_CHUNKS"
}

struct GlobalizedSearchDerivedNormalizationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let algorithmVersion: GlobalizedSearchNormalizationAlgorithmV1
    let normalizedText: String
    let tokens: [String]
    let cjkSegmentationStrategy: GlobalizedSearchCJKSegmentationStrategyV1
    let cjkRunCount: Int
    let cjkChunkCount: Int

    init(
        normalizedText: String,
        tokens: [String],
        cjkRunCount: Int,
        cjkChunkCount: Int,
        cjkSegmentationStrategy: GlobalizedSearchCJKSegmentationStrategyV1 = .completeRunsAndBoundedChunks
    ) throws {
        schemaVersion = Self.schemaVersion
        algorithmVersion = .v1
        self.normalizedText = normalizedText
        self.tokens = tokens
        self.cjkSegmentationStrategy = cjkSegmentationStrategy
        self.cjkRunCount = cjkRunCount
        self.cjkChunkCount = cjkChunkCount
        try validate(maximumTokens: SearchContractLimitsV1.maximumProjectionTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, algorithmVersion, normalizedText, tokens
        case cjkSegmentationStrategy, cjkRunCount, cjkChunkCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        algorithmVersion = try container.decode(GlobalizedSearchNormalizationAlgorithmV1.self, forKey: .algorithmVersion)
        normalizedText = try container.decode(String.self, forKey: .normalizedText)
        tokens = try container.decode([String].self, forKey: .tokens)
        cjkSegmentationStrategy = try container.decode(GlobalizedSearchCJKSegmentationStrategyV1.self, forKey: .cjkSegmentationStrategy)
        cjkRunCount = try container.decode(Int.self, forKey: .cjkRunCount)
        cjkChunkCount = try container.decode(Int.self, forKey: .cjkChunkCount)
        try validate(maximumTokens: SearchContractLimitsV1.maximumProjectionTokens)
    }

    func encode(to encoder: Encoder) throws {
        try validate(maximumTokens: SearchContractLimitsV1.maximumProjectionTokens)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(algorithmVersion, forKey: .algorithmVersion)
        try container.encode(normalizedText, forKey: .normalizedText)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(cjkSegmentationStrategy, forKey: .cjkSegmentationStrategy)
        try container.encode(cjkRunCount, forKey: .cjkRunCount)
        try container.encode(cjkChunkCount, forKey: .cjkChunkCount)
    }

    func validate(maximumTokens: Int) throws {
        guard schemaVersion == Self.schemaVersion,
              algorithmVersion == .v1,
              normalizedText.utf8.count <= SearchContractLimitsV1.maximumProjectionTokens * SearchContractLimitsV1.maximumNormalizedTokenBytes,
              !normalizedText.unicodeScalars.contains({ CharacterSet.controlCharacters.contains($0) }),
              normalizedText.unicodeScalars.allSatisfy(GlobalizedSearchNormalizationAlgorithmV1.excludesBidiFormatting),
              normalizedText.utf8.elementsEqual(normalizedText.precomposedStringWithCanonicalMapping.utf8),
              normalizedText.utf8.elementsEqual(
                  GlobalizedSearchNormalizationAlgorithmV1.normalizedText(from: normalizedText).utf8
              ),
              cjkSegmentationStrategy == .completeRunsAndBoundedChunks,
              SearchContractValidationV1.globalizedDerivedTokensAreCurrent(tokens, maximumCount: maximumTokens),
              let expected = try? GlobalizedSearchNormalizationAlgorithmV1.projectionMaterial(from: normalizedText),
              expected.tokens == tokens,
              expected.cjkRunCount == cjkRunCount,
              expected.cjkChunkCount == cjkChunkCount else {
            throw SearchContractFailureV1.incompatibleDerivedNormalization
        }
    }
}

extension SearchContractValidationV1 {
    static func isCurrentGlobalizedDerivedToken(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= SearchContractLimitsV1.maximumNormalizedTokenBytes,
              value.utf8.elementsEqual(value.precomposedStringWithCanonicalMapping.utf8) else {
            return false
        }
        var hasTokenBase = false
        var hasAlphabeticBase = false
        var hasMark = false
        for scalar in value.unicodeScalars {
            guard !CharacterSet.controlCharacters.contains(scalar),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  GlobalizedSearchNormalizationAlgorithmV1.excludesBidiFormatting(scalar) else {
                return false
            }
            if CharacterSet.alphanumerics.contains(scalar) {
                hasTokenBase = true
                hasAlphabeticBase = hasAlphabeticBase || CharacterSet.letters.contains(scalar)
            } else if scalar.isUnicodeMark {
                guard hasTokenBase else { return false }
                hasMark = true
            } else {
                return false
            }
        }
        return hasTokenBase && (!hasMark || hasAlphabeticBase)
    }

    static func globalizedDerivedTokensAreCurrent(_ values: [String], maximumCount: Int) -> Bool {
        maximumCount > 0 && values.count <= maximumCount && values == values.sorted()
            && Set(values).count == values.count && values.allSatisfy(isCurrentGlobalizedDerivedToken)
    }
}

private extension Unicode.Scalar {
    var isUnicodeMark: Bool {
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    var isLatinBase: Bool {
        switch value {
        case 0x0000...0x024F, 0x1E00...0x1EFF, 0x2C60...0x2C7F,
             0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFB00...0xFB06,
             0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A: true
        default: false
        }
    }

    var isCJKSearchScalar: Bool {
        switch value {
        case 0x3041...0x3096, 0x30A1...0x30FA, 0x31F0...0x31FF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0xFF66...0xFF9D, 0x20000...0x2EBEF: true
        default: false
        }
    }
}

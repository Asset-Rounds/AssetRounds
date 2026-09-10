import Foundation

enum GlobalizedSearchNormalizationServiceV1 {
    static func normalizeQuery(_ value: String) throws -> GlobalizedSearchDerivedNormalizationV1 {
        guard value.utf8.count <= SearchContractLimitsV1.maximumQueryBytes else {
            throw SearchContractFailureV1.limitExceeded
        }
        let normalizedText = GlobalizedSearchNormalizationAlgorithmV1.normalizedText(from: value)
        return try makeNormalization(
            normalizedText: normalizedText,
            material: GlobalizedSearchNormalizationAlgorithmV1.queryMaterial(from: normalizedText)
        )
    }

    static func normalizeProjectionText(_ value: String) throws -> GlobalizedSearchDerivedNormalizationV1 {
        guard value.utf8.count <= SearchContractLimitsV1.maximumProjectionTokens
            * SearchContractLimitsV1.maximumNormalizedTokenBytes else {
            throw SearchContractFailureV1.limitExceeded
        }
        let normalizedText = GlobalizedSearchNormalizationAlgorithmV1.normalizedText(from: value)
        return try makeNormalization(
            normalizedText: normalizedText,
            material: GlobalizedSearchNormalizationAlgorithmV1.projectionMaterial(from: normalizedText)
        )
    }

    static func containsCJK(_ value: String) -> Bool {
        GlobalizedSearchNormalizationAlgorithmV1.containsCJK(value)
    }

    static func displayPrecedes(
        lhsDisplay: String,
        lhsStableID: String,
        lhsKind: SearchSourceKindV1,
        rhsDisplay: String,
        rhsStableID: String,
        rhsKind: SearchSourceKindV1,
        localeIdentifier: String
    ) -> Bool {
        let comparison = lhsDisplay.compare(
            rhsDisplay,
            // Accents participate in locale collation (for example Swedish
            // A-ring follows Z); search folding is a separate policy.
            options: [.caseInsensitive, .widthInsensitive],
            range: nil,
            locale: Locale(identifier: localeIdentifier)
        )
        if comparison != .orderedSame { return comparison == .orderedAscending }
        if lhsKind != rhsKind { return lhsKind.rawValue < rhsKind.rawValue }
        return Array(lhsStableID.utf8).lexicographicallyPrecedes(Array(rhsStableID.utf8))
    }

    private static func makeNormalization(
        normalizedText: String,
        material: GlobalizedSearchDerivedMaterialV1
    ) throws -> GlobalizedSearchDerivedNormalizationV1 {
        try GlobalizedSearchDerivedNormalizationV1(
            normalizedText: normalizedText,
            tokens: material.tokens,
            cjkRunCount: material.cjkRunCount,
            cjkChunkCount: material.cjkChunkCount
        )
    }
}

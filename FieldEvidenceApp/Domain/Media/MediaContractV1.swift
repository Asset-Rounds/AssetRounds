import Foundation

enum MediaContractV1 {
    enum OutputKind: Equatable, Sendable {
        case original
        case thumbnail

        var longestEdgeMaximum: Int {
            switch self {
            case .original: 4_096
            case .thumbnail: 512
            }
        }

        var byteCountMaximum: Int {
            switch self {
            case .original: 32 * MediaContractV1.mebibyte
            case .thumbnail: 2 * MediaContractV1.mebibyte
            }
        }

        var compressionQuality: Double {
            switch self {
            case .original: 0.90
            case .thumbnail: 0.75
            }
        }
    }

    static let acceptedSourceTypeIdentifiers: Set<String> = [
        "public.jpeg",
        "public.heic",
        "public.heif",
        "public.png",
    ]

    static let durableMIMEType = "image/jpeg"
    static let sourceByteCountMaximum = 80 * mebibyte
    static let decodedPixelCountMaximum = 100_000_000
    static let sourceAxisMinimum = 1
    static let sourceAxisMaximum = 16_384

    static let originalLongestEdgeMaximum = OutputKind.original.longestEdgeMaximum
    static let originalByteCountMaximum = OutputKind.original.byteCountMaximum
    static let originalCompressionQuality = OutputKind.original.compressionQuality
    static let thumbnailLongestEdgeMaximum = OutputKind.thumbnail.longestEdgeMaximum
    static let thumbnailByteCountMaximum = OutputKind.thumbnail.byteCountMaximum
    static let thumbnailCompressionQuality = OutputKind.thumbnail.compressionQuality

    private static let mebibyte = 1_048_576
}

struct NormalizedMediaV1: Equatable, Sendable {
    let originalJPEG: Data
    let thumbnailJPEG: Data
}

struct CanonicalJPEGFactsV1: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
}

enum MediaImportErrorV1: Error, Equatable, LocalizedError {
    case sourceTooLarge
    case unsupportedSourceType
    case animatedOrMultipageSource
    case malformedSource
    case sourceDimensionsOutOfRange
    case decodedPixelCountTooLarge
    case normalizationFailed
    case canonicalOutputTooLarge(MediaContractV1.OutputKind)
    case invalidCanonicalJPEG

    var errorDescription: String? {
        switch self {
        case .sourceTooLarge:
            "This photo is too large to import. Choose a photo smaller than 80 MiB."
        case .unsupportedSourceType:
            "Choose one JPEG, HEIC, HEIF, or PNG still photo."
        case .animatedOrMultipageSource:
            "Choose one still photo. Animated or multi-page images are not supported."
        case .malformedSource:
            "This photo could not be read. Choose a different JPEG, HEIC, HEIF, or PNG."
        case .sourceDimensionsOutOfRange:
            "This photo's dimensions are not supported. Choose a photo no larger than 16,384 pixels per side."
        case .decodedPixelCountTooLarge:
            "This photo contains too many pixels. Choose a photo under 100 megapixels."
        case .normalizationFailed:
            "This photo could not be prepared. Choose a different photo and try again."
        case .canonicalOutputTooLarge:
            "This photo could not be reduced to the required size. Choose a different photo."
        case .invalidCanonicalJPEG:
            "The prepared photo failed validation. Choose the photo again and retry."
        }
    }
}

import Foundation

/// Metadata for the incumbent photo normalizer. These values describe stored
/// source/output claims; they do not establish that any bytes were processed.
enum CheckRunnerPhotoSourceMetadataProfileV1 {
    static let profileID = "assetrounds.checkrunner-photo-source-metadata"
    static let profileVersion = "1"
    static let sourceUTIToMediaType = [
        "public.jpeg": "image/jpeg",
        "public.heic": "image/heic",
        "public.heif": "image/heif",
        "public.png": "image/png",
    ]
    static let normalizerSanitizerID = "assetrounds.media-normalizer.metadata"
    static let normalizerSanitizerVersion = "1"
    static let thumbnailRendererID = "assetrounds.media-normalizer.thumbnail"
    static let thumbnailRendererVersion = "1"

    static func validate() throws {
        guard Set(sourceUTIToMediaType.keys) == MediaContractV1.acceptedSourceTypeIdentifiers,
              sourceUTIToMediaType.values.allSatisfy(ContentContractValidationV1.validMediaType),
              ContentContractValidationV1.validID(profileID),
              ContentContractValidationV1.validVersion(profileVersion),
              MediaContractV1.durableMIMEType == "image/jpeg" else {
            throw FieldDraftFailureV1.invalidValue
        }
        _ = try sanitizedDerivative()
        _ = try thumbnailDerivative(pixelWidth: 1, pixelHeight: 1)
    }

    static func mediaType(for sourceTypeIdentifier: String) throws -> String {
        try validate()
        guard let mediaType = sourceUTIToMediaType[sourceTypeIdentifier] else {
            throw FieldDraftFailureV1.invalidValue
        }
        return mediaType
    }

    static func sanitizedDerivative() throws -> SanitizedDerivativeV1 {
        try SanitizedDerivativeV1(sanitizerID: normalizerSanitizerID,
                                  sanitizerVersion: normalizerSanitizerVersion)
    }

    static func thumbnailDerivative(pixelWidth: Int, pixelHeight: Int) throws -> ThumbnailDerivativeV1 {
        try ThumbnailDerivativeV1(rendererID: thumbnailRendererID,
            rendererVersion: thumbnailRendererVersion, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}

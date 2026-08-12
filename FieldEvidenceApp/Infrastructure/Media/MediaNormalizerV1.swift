import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MediaNormalizerV1 {
    func normalize(_ sourceData: Data) throws -> NormalizedMediaV1 {
        guard sourceData.count <= MediaContractV1.sourceByteCountMaximum else {
            throw MediaImportErrorV1.sourceTooLarge
        }
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let sourceTypeReference = CGImageSourceGetType(source) else {
            throw MediaImportErrorV1.malformedSource
        }
        let sourceType = sourceTypeReference as String
        guard MediaContractV1.acceptedSourceTypeIdentifiers.contains(sourceType),
              UTType(sourceType) != nil else {
            throw MediaImportErrorV1.unsupportedSourceType
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw MediaImportErrorV1.animatedOrMultipageSource
        }

        let sourceDimensions = try dimensions(of: source)
        guard (MediaContractV1.sourceAxisMinimum...MediaContractV1.sourceAxisMaximum).contains(sourceDimensions.width),
              (MediaContractV1.sourceAxisMinimum...MediaContractV1.sourceAxisMaximum).contains(sourceDimensions.height) else {
            throw MediaImportErrorV1.sourceDimensionsOutOfRange
        }
        let (pixelCount, overflow) = sourceDimensions.width.multipliedReportingOverflow(
            by: sourceDimensions.height
        )
        guard !overflow, pixelCount <= MediaContractV1.decodedPixelCountMaximum else {
            throw MediaImportErrorV1.decodedPixelCountTooLarge
        }

        let original = try normalize(
            source: source,
            sourceDimensions: sourceDimensions,
            kind: .original
        )
        let thumbnail = try normalize(
            source: source,
            sourceDimensions: sourceDimensions,
            kind: .thumbnail
        )
        _ = try validateCanonicalJPEG(original, kind: .original)
        _ = try validateCanonicalJPEG(thumbnail, kind: .thumbnail)
        return NormalizedMediaV1(originalJPEG: original, thumbnailJPEG: thumbnail)
    }

    func validateCanonicalJPEG(
        _ data: Data,
        kind: MediaContractV1.OutputKind
    ) throws -> CanonicalJPEGFactsV1 {
        guard data.count <= kind.byteCountMaximum,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let typeReference = CGImageSourceGetType(source),
              typeReference as String == UTType.jpeg.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width >= 1,
              image.height >= 1,
              max(image.width, image.height) <= kind.longestEdgeMaximum,
              image.bitsPerComponent == 8,
              image.colorSpace?.model == .rgb,
              hasOnlyCanonicalJPEGMarkers(data) else {
            throw MediaImportErrorV1.invalidCanonicalJPEG
        }

        return CanonicalJPEGFactsV1(
            pixelWidth: image.width,
            pixelHeight: image.height,
            byteCount: data.count
        )
    }

    private func normalize(
        source: CGImageSource,
        sourceDimensions: (width: Int, height: Int),
        kind: MediaContractV1.OutputKind
    ) throws -> Data {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: kind.longestEdgeMaximum,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceDecodeToSDR: true,
        ]
        guard let orientedImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw MediaImportErrorV1.normalizationFailed
        }
        guard max(orientedImage.width, orientedImage.height)
                <= max(sourceDimensions.width, sourceDimensions.height),
              min(orientedImage.width, orientedImage.height)
                <= min(sourceDimensions.width, sourceDimensions.height),
              let canonicalImage = renderInSRGB(orientedImage),
              let encoded = encodeJPEG(canonicalImage, quality: kind.compressionQuality) else {
            throw MediaImportErrorV1.normalizationFailed
        }
        guard encoded.count <= kind.byteCountMaximum else {
            throw MediaImportErrorV1.canonicalOutputTooLarge(kind)
        }
        return encoded
    }

    private func dimensions(of source: CGImageSource) throws -> (width: Int, height: Int) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = integerValue(properties[kCGImagePropertyPixelWidth]),
              let height = integerValue(properties[kCGImagePropertyPixelHeight]) else {
            throw MediaImportErrorV1.malformedSource
        }
        return (width, height)
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func renderInSRGB(_ image: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        return context.makeImage()
    }

    private func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let profile = CGColorSpaceCopyICCData(colorSpace) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationEmbedThumbnail: false,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return canonicalizeMetadata(in: data as Data, profile: profile as Data)
    }

    private func canonicalizeMetadata(in data: Data, profile: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else {
            return nil
        }

        var output: [UInt8] = [0xff, 0xd8]
        output.append(contentsOf: jfifSegment)
        let maximumICCChunkSize = 65_533 - 14
        let chunkCount = max(1, (profile.count + maximumICCChunkSize - 1) / maximumICCChunkSize)
        guard chunkCount <= 255 else { return nil }
        for chunkIndex in 0..<chunkCount {
            let start = chunkIndex * maximumICCChunkSize
            let end = min(profile.count, start + maximumICCChunkSize)
            let payload = Array(profile[start..<end])
            let segmentLength = payload.count + 16
            output.append(contentsOf: [
                0xff, 0xe2,
                UInt8((segmentLength >> 8) & 0xff),
                UInt8(segmentLength & 0xff),
            ])
            output.append(contentsOf: "ICC_PROFILE\0".utf8)
            output.append(UInt8(chunkIndex + 1))
            output.append(UInt8(chunkCount))
            output.append(contentsOf: payload)
        }

        var offset = 2
        while offset + 1 < bytes.count {
            let markerStart = offset
            guard bytes[offset] == 0xff else { return nil }
            while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
            guard offset < bytes.count else { return nil }
            let marker = bytes[offset]
            offset += 1
            if marker == 0xd9 {
                output.append(contentsOf: [0xff, 0xd9])
                return Data(output)
            }
            if marker == 0xda {
                output.append(contentsOf: bytes[markerStart...])
                return Data(output)
            }
            if marker == 0x01 || (0xd0...0xd7).contains(marker) {
                output.append(contentsOf: bytes[markerStart..<offset])
                continue
            }
            guard offset + 1 < bytes.count else { return nil }
            let segmentLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            guard segmentLength >= 2, offset + segmentLength <= bytes.count else {
                return nil
            }
            if !(0xe0...0xef).contains(marker), marker != 0xfe {
                output.append(contentsOf: bytes[markerStart..<(offset + segmentLength)])
            }
            offset += segmentLength
        }
        return nil
    }

    private var jfifSegment: [UInt8] {
        [
            0xff, 0xe0, 0x00, 0x10,
            0x4a, 0x46, 0x49, 0x46, 0x00,
            0x01, 0x01, 0x00,
            0x00, 0x01, 0x00, 0x01,
            0x00, 0x00,
        ]
    }

    private func hasOnlyCanonicalJPEGMarkers(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 4,
              bytes[0] == 0xff,
              bytes[1] == 0xd8 else {
            return false
        }

        var offset = 2
        var foundJFIF = false
        var iccChunks: [Int: Data] = [:]
        var expectedICCChunkCount: Int?
        while offset + 1 < bytes.count {
            guard bytes[offset] == 0xff else { return false }
            while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
            guard offset < bytes.count else { return false }
            let marker = bytes[offset]
            offset += 1

            if marker == 0xd9 { return foundJFIF && selectedICCProfileMatches(iccChunks, expectedCount: expectedICCChunkCount) }
            if marker == 0xda {
                return foundJFIF
                    && selectedICCProfileMatches(iccChunks, expectedCount: expectedICCChunkCount)
                    && hasCanonicalScanEnding(bytes, segmentLengthOffset: offset)
            }
            if marker == 0x01 || (0xd0...0xd7).contains(marker) {
                continue
            }
            guard offset + 1 < bytes.count else { return false }
            let segmentLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            guard segmentLength >= 2, offset + segmentLength <= bytes.count else {
                return false
            }
            let payloadStart = offset + 2
            let payloadEnd = offset + segmentLength

            switch marker {
            case 0xe0:
                guard !foundJFIF,
                      segmentLength == 16,
                      Array(bytes[(offset - 2)..<payloadEnd]) == jfifSegment else {
                    return false
                }
                foundJFIF = true
            case 0xe2:
                guard payloadEnd - payloadStart >= 14,
                      Array(bytes[payloadStart..<(payloadStart + 12)]) == Array("ICC_PROFILE\0".utf8) else {
                    return false
                }
                let sequence = Int(bytes[payloadStart + 12])
                let count = Int(bytes[payloadStart + 13])
                guard sequence >= 1,
                      count >= 1,
                      sequence <= count,
                      expectedICCChunkCount == nil || expectedICCChunkCount == count,
                      iccChunks[sequence] == nil else {
                    return false
                }
                expectedICCChunkCount = count
                iccChunks[sequence] = Data(bytes[(payloadStart + 14)..<payloadEnd])
            case 0xe1, 0xe3...0xef, 0xfe:
                return false
            default:
                break
            }
            offset += segmentLength
        }
        return false
    }

    private func hasCanonicalScanEnding(
        _ bytes: [UInt8],
        segmentLengthOffset: Int
    ) -> Bool {
        guard segmentLengthOffset + 1 < bytes.count else { return false }
        let highByte = Int(bytes[segmentLengthOffset]) << 8
        let segmentLength = highByte | Int(bytes[segmentLengthOffset + 1])
        guard segmentLength >= 2,
              segmentLengthOffset + segmentLength < bytes.count else {
            return false
        }

        var offset = segmentLengthOffset + segmentLength
        while offset < bytes.count {
            guard bytes[offset] == 0xff else {
                offset += 1
                continue
            }
            guard offset + 1 < bytes.count else { return false }
            let followingByte = bytes[offset + 1]
            switch followingByte {
            case 0x00:
                offset += 2
            case 0xd0...0xd7:
                offset += 2
            case 0xd9:
                return offset + 2 == bytes.count
            default:
                return false
            }
        }
        return false
    }

    private func selectedICCProfileMatches(
        _ chunks: [Int: Data],
        expectedCount: Int?
    ) -> Bool {
        guard let expectedCount,
              chunks.count == expectedCount,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let selectedProfile = CGColorSpaceCopyICCData(colorSpace) else {
            return false
        }
        var profile = Data()
        for sequence in 1...expectedCount {
            guard let chunk = chunks[sequence] else { return false }
            profile.append(chunk)
        }
        return profile == selectedProfile as Data
    }
}

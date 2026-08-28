import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S3_2MediaPipelineTests: XCTestCase {
    private let fileManager = FileManager.default

    func testNormalizerAndStoragePreflightEnforceTheFrozenMediaContract() throws {
        let source = try makePNG(width: 960, height: 540, seed: 31)
        let normalizer = MediaNormalizerV1()
        let first = try normalizer.normalize(source)
        let second = try normalizer.normalize(source)

        XCTAssertEqual(first.originalJPEG, second.originalJPEG)
        XCTAssertEqual(first.thumbnailJPEG, second.thumbnailJPEG)
        let originalFacts = try normalizer.validateCanonicalJPEG(
            first.originalJPEG,
            kind: .original
        )
        let thumbnailFacts = try normalizer.validateCanonicalJPEG(
            first.thumbnailJPEG,
            kind: .thumbnail
        )
        XCTAssertEqual(originalFacts.byteCount, first.originalJPEG.count)
        XCTAssertEqual(thumbnailFacts.byteCount, first.thumbnailJPEG.count)
        XCTAssertLessThanOrEqual(max(originalFacts.pixelWidth, originalFacts.pixelHeight), 4_096)
        XCTAssertLessThanOrEqual(max(thumbnailFacts.pixelWidth, thumbnailFacts.pixelHeight), 512)
        XCTAssertLessThanOrEqual(originalFacts.byteCount, 32 * 1_024 * 1_024)
        XCTAssertLessThanOrEqual(thumbnailFacts.byteCount, 2 * 1_024 * 1_024)
        assertExactCanonicalJPEGMetadata(first.originalJPEG)
        assertExactCanonicalJPEGMetadata(first.thumbnailJPEG)

        let volume = fileManager.temporaryDirectory
        let requiredBytes = Int64(132 * 1_024 * 1_024)
        XCTAssertEqual(
            StoragePreflightService.evidenceAcceptanceEstimateBytes,
            68 * 1_024 * 1_024
        )
        XCTAssertEqual(StoragePreflightService.reserveBytes, 64 * 1_024 * 1_024)
        XCTAssertEqual(
            StoragePreflightService.evidenceAcceptanceRequiredBytes,
            requiredBytes
        )
        var checkedURL: URL?
        let exactCapacity = StoragePreflightService { url in
            checkedURL = url
            return requiredBytes
        }
        XCTAssertNoThrow(
            try exactCapacity.checkEvidenceAcceptance(onVolumeContaining: volume)
        )
        XCTAssertEqual(checkedURL?.standardizedFileURL, volume.standardizedFileURL)

        let insufficient = StoragePreflightService { _ in requiredBytes - 1 }
        XCTAssertThrowsError(
            try insufficient.checkEvidenceAcceptance(onVolumeContaining: volume)
        ) {
            XCTAssertEqual(
                $0 as? StoragePreflightError,
                .insufficientCapacity(
                    requiredBytes: requiredBytes,
                    availableBytes: requiredBytes - 1
                )
            )
        }
    }

    func testRepresentativeInvalidSourcesFailClosedAndAlphaOrientationNormalize() throws {
        let normalizer = MediaNormalizerV1()
        XCTAssertThrowsError(try normalizer.normalize(Data([0x00, 0x01, 0x02]))) {
            XCTAssertEqual($0 as? MediaImportErrorV1, .malformedSource)
        }

        let onePixelGIF = try XCTUnwrap(
            Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
        )
        XCTAssertThrowsError(try normalizer.normalize(onePixelGIF)) {
            XCTAssertEqual($0 as? MediaImportErrorV1, .unsupportedSourceType)
        }

        let animatedPNG = try makeAnimatedPNG()
        XCTAssertThrowsError(try normalizer.normalize(animatedPNG)) {
            XCTAssertEqual($0 as? MediaImportErrorV1, .animatedOrMultipageSource)
        }

        let overAxisLimit = try makePNG(width: 16_385, height: 1, seed: 17)
        XCTAssertThrowsError(try normalizer.normalize(overAxisLimit)) {
            XCTAssertEqual($0 as? MediaImportErrorV1, .sourceDimensionsOutOfRange)
        }

        let transparent = try normalizer.normalize(makeTransparentPNG(width: 64, height: 64))
        let whitePixel = try sampledRGBA(fromJPEG: transparent.originalJPEG)
        XCTAssertGreaterThanOrEqual(whitePixel.red, 250)
        XCTAssertGreaterThanOrEqual(whitePixel.green, 250)
        XCTAssertGreaterThanOrEqual(whitePixel.blue, 250)
        XCTAssertEqual(whitePixel.alpha, 255)

        let oriented = try normalizer.normalize(
            makePNG(width: 40, height: 20, seed: 53, orientation: 6)
        )
        let orientedFacts = try normalizer.validateCanonicalJPEG(
            oriented.originalJPEG,
            kind: .original
        )
        XCTAssertEqual(orientedFacts.pixelWidth, 20)
        XCTAssertEqual(orientedFacts.pixelHeight, 40)
    }

    func testTamperedStagingBundleWithExtraFileFailsPromotionClosed() async throws {
        let generationRoot = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: generationRoot) }
        let normalized = try MediaNormalizerV1().normalize(
            makePNG(width: 320, height: 180, seed: 41)
        )
        let evidenceID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let store = EvidenceBundleStore(generationRootURL: generationRoot)
        let staged = try await store.stage(evidenceID: evidenceID, normalized: normalized)
        let stagingURL = generationRoot.appendingPathComponent(
            staged.stagingDirectoryRelativePath,
            isDirectory: true
        )
        try Data("unexpected".utf8).write(
            to: stagingURL.appendingPathComponent("extra.bin")
        )

        do {
            _ = try await store.promote(staged)
            XCTFail("A staging bundle with an extra file must not be promoted")
        } catch {
            XCTAssertEqual(error as? EvidenceBundleStoreError, .bundleShapeInvalid)
        }
        XCTAssertTrue(fileManager.fileExists(atPath: stagingURL.path))
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: generationRoot
                    .appendingPathComponent(
                        "evidence/\(evidenceID.uuidString.lowercased())",
                        isDirectory: true
                    )
                    .path
            )
        )
    }

    @MainActor
    func testCapacityUnavailableStopsBeforeFilesRowsOrDraftStepMutation() throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let factory = StoreGenerationFactory(applicationSupportURL: applicationSupport)
        let session = try factory.openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let site = Site(label: "North Campus", timeZoneID: "America/New_York")
        let asset = Asset(
            siteID: site.id,
            packID: pack.packID,
            packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            label: "Monument Sign"
        )
        context.insert(site)
        context.insert(asset)
        try context.save()
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        let draft = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_768_438_923)
        )
        let stagingRoot = session.generationRootURL.appendingPathComponent(
            ".staging/evidence",
            isDirectory: true
        )
        let evidenceRoot = session.generationRootURL.appendingPathComponent(
            "evidence",
            isDirectory: true
        )
        let unavailable = StoragePreflightService { _ in nil }

        XCTAssertThrowsError(
            try unavailable.checkEvidenceAcceptance(
                onVolumeContaining: session.generationRootURL
            )
        ) {
            XCTAssertEqual($0 as? StoragePreflightError, .capacityUnavailable)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: stagingRoot.path))
        XCTAssertFalse(fileManager.fileExists(atPath: evidenceRoot.path))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 0)
        XCTAssertEqual(draft.draftStepKey, WorkflowDraftStep.wide.rawValue)
        withExtendedLifetime(session) {}
    }

    @MainActor
    func testWideCloseAcceptanceAndRetakePersistExactRowsStepsAndBundlesAcrossReopen() async throws {
        let applicationSupport = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let factory = StoreGenerationFactory(applicationSupportURL: applicationSupport)
        let pack = SignPack.illuminatedSignV1
        let observedAt = Date(timeIntervalSince1970: 1_768_438_923)
        let wideCreatedAt = Date(timeIntervalSince1970: 1_768_438_924)
        let closeCreatedAt = Date(timeIntervalSince1970: 1_768_438_925)
        let wideSource = try makePNG(width: 960, height: 540, seed: 31)
        let closeSource = try makePNG(width: 640, height: 960, seed: 79)
        var assetID: UUID!
        var draftID: UUID!
        var wideID: UUID!
        var closeID: UUID!
        var expectedWideOriginal = Data()
        var expectedWideThumbnail = Data()

        do {
            let session = try factory.openOrBootstrapCurrent()
            let context = session.modelContext
            let site = Site(label: "North Campus", timeZoneID: "America/New_York")
            let asset = Asset(
                siteID: site.id,
                packID: pack.packID,
                packSchemaVersion: pack.schemaVersion,
                packContentVersion: pack.contentVersion,
                label: "Monument Sign"
            )
            context.insert(site)
            context.insert(asset)
            try context.save()
            assetID = asset.id

            let coordinator = CheckRunnerCoordinator(
                modelContext: context,
                signPack: pack
            )
            coordinator.configureCapture(generationRootURL: session.generationRootURL)
            let draft = try coordinator.beginCheck(
                assetID: asset.id,
                timeZoneID: nil,
                isTimeZoneConfirmed: false,
                afterDarkAccepted: true,
                safePositionAccepted: true,
                observedAt: observedAt
            )
            draftID = draft.id

            let wideCandidate = try await coordinator.importCandidate(
                assetID: asset.id,
                sourceData: wideSource,
                createdAt: wideCreatedAt
            )
            wideID = wideCandidate.id
            XCTAssertEqual(wideCandidate.recordID, draft.id)
            XCTAssertEqual(wideCandidate.purposeKey, "wide_context")
            assertStagedOnly(
                wideCandidate.stagedBundle,
                generationRoot: session.generationRootURL
            )
            let wideEvidence = try await coordinator.accept(
                candidate: wideCandidate,
                assetID: asset.id
            )
            assertExactEvidence(
                wideEvidence,
                candidate: wideCandidate,
                purposeKey: "wide_context",
                createdAt: wideCreatedAt,
                generationRoot: session.generationRootURL
            )
            XCTAssertEqual(draft.draftStepKey, WorkflowDraftStep.close.rawValue)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 1)

            let wideOriginalURL = session.generationRootURL.appendingPathComponent(
                wideEvidence.relativePath
            )
            let wideThumbnailURL = session.generationRootURL.appendingPathComponent(
                wideEvidence.thumbnailRelativePath
            )
            expectedWideOriginal = try Data(contentsOf: wideOriginalURL)
            expectedWideThumbnail = try Data(contentsOf: wideThumbnailURL)

            let rejectedClose = try await coordinator.importCandidate(
                assetID: asset.id,
                sourceData: closeSource,
                createdAt: closeCreatedAt
            )
            let rejectedStagingURL = session.generationRootURL.appendingPathComponent(
                rejectedClose.stagedBundle.stagingDirectoryRelativePath,
                isDirectory: true
            )
            XCTAssertTrue(fileManager.fileExists(atPath: rejectedStagingURL.path))
            try await coordinator.retake(candidate: rejectedClose)
            XCTAssertFalse(fileManager.fileExists(atPath: rejectedStagingURL.path))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 1)
            XCTAssertEqual(draft.draftStepKey, WorkflowDraftStep.close.rawValue)
            XCTAssertEqual(try Data(contentsOf: wideOriginalURL), expectedWideOriginal)
            XCTAssertEqual(try Data(contentsOf: wideThumbnailURL), expectedWideThumbnail)

            let closeCandidate = try await coordinator.importCandidate(
                assetID: asset.id,
                sourceData: closeSource,
                createdAt: closeCreatedAt
            )
            closeID = closeCandidate.id
            XCTAssertEqual(closeCandidate.purposeKey, "close_detail")
            assertStagedOnly(
                closeCandidate.stagedBundle,
                generationRoot: session.generationRootURL
            )
            let closeEvidence = try await coordinator.accept(
                candidate: closeCandidate,
                assetID: asset.id
            )
            assertExactEvidence(
                closeEvidence,
                candidate: closeCandidate,
                purposeKey: "close_detail",
                createdAt: closeCreatedAt,
                generationRoot: session.generationRootURL
            )
            XCTAssertEqual(draft.draftStepKey, WorkflowDraftStep.outcome.rawValue)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 2)
            XCTAssertEqual(try Data(contentsOf: wideOriginalURL), expectedWideOriginal)
            XCTAssertEqual(try Data(contentsOf: wideThumbnailURL), expectedWideThumbnail)
            withExtendedLifetime(session) {}
        }

        do {
            let reopenedSession = try factory.openOrBootstrapCurrent()
            let reopenedContext = reopenedSession.modelContext
            let reopenedDraft = try XCTUnwrap(
                reopenedContext.fetch(FetchDescriptor<WorkflowRecord>()).first
            )
            XCTAssertEqual(reopenedDraft.id, draftID)
            XCTAssertEqual(reopenedDraft.assetID, assetID)
            XCTAssertEqual(reopenedDraft.state, WorkflowState.draft.rawValue)
            XCTAssertEqual(reopenedDraft.draftStepKey, WorkflowDraftStep.outcome.rawValue)

            let evidence = try reopenedContext.fetch(FetchDescriptor<EvidenceFile>())
            XCTAssertEqual(evidence.count, 2)
            let wide = try XCTUnwrap(evidence.first { $0.id == wideID })
            let close = try XCTUnwrap(evidence.first { $0.id == closeID })
            XCTAssertEqual(wide.recordID, draftID)
            XCTAssertEqual(wide.purposeKey, "wide_context")
            XCTAssertEqual(wide.createdAt, wideCreatedAt)
            XCTAssertEqual(close.recordID, draftID)
            XCTAssertEqual(close.purposeKey, "close_detail")
            XCTAssertEqual(close.createdAt, closeCreatedAt)
            XCTAssertEqual(
                try Data(
                    contentsOf: reopenedSession.generationRootURL
                        .appendingPathComponent(wide.relativePath)
                ),
                expectedWideOriginal
            )
            XCTAssertEqual(
                try Data(
                    contentsOf: reopenedSession.generationRootURL
                        .appendingPathComponent(wide.thumbnailRelativePath)
                ),
                expectedWideThumbnail
            )
            XCTAssertEqual(
                try coordinatorPreparation(
                    context: reopenedContext,
                    pack: pack,
                    generationRoot: reopenedSession.generationRootURL,
                    assetID: assetID
                ).step,
                .outcome
            )
            withExtendedLifetime(reopenedSession) {}
        }
    }

    @MainActor
    private func coordinatorPreparation(
        context: ModelContext,
        pack: SignPack,
        generationRoot: URL,
        assetID: UUID
    ) throws -> CapturePreparation {
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        coordinator.configureCapture(generationRootURL: generationRoot)
        return try coordinator.prepareCapture(assetID: assetID)
    }

    private func assertStagedOnly(
        _ staged: StagedEvidenceBundle,
        generationRoot: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let canonicalID = staged.evidenceID.uuidString.lowercased()
        XCTAssertEqual(
            staged.stagingDirectoryRelativePath,
            ".staging/evidence/\(canonicalID)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            staged.originalRelativePath,
            "evidence/\(canonicalID)/original.jpg",
            file: file,
            line: line
        )
        XCTAssertEqual(
            staged.thumbnailRelativePath,
            "evidence/\(canonicalID)/thumbnail.jpg",
            file: file,
            line: line
        )
        let staging = generationRoot.appendingPathComponent(
            staged.stagingDirectoryRelativePath,
            isDirectory: true
        )
        XCTAssertTrue(fileManager.fileExists(atPath: staging.path), file: file, line: line)
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: generationRoot
                    .appendingPathComponent("evidence/\(canonicalID)", isDirectory: true)
                    .path
            ),
            file: file,
            line: line
        )
    }

    private func assertExactEvidence(
        _ evidence: EvidenceFile,
        candidate: CaptureCandidate,
        purposeKey: String,
        createdAt: Date,
        generationRoot: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let staged = candidate.stagedBundle
        XCTAssertEqual(evidence.id, candidate.id, file: file, line: line)
        XCTAssertEqual(evidence.schemaVersion, 1, file: file, line: line)
        XCTAssertEqual(evidence.recordID, candidate.recordID, file: file, line: line)
        XCTAssertEqual(evidence.purposeKey, purposeKey, file: file, line: line)
        XCTAssertEqual(evidence.relativePath, staged.originalRelativePath, file: file, line: line)
        XCTAssertEqual(evidence.mimeType, "image/jpeg", file: file, line: line)
        XCTAssertEqual(evidence.byteCount, staged.originalByteCount, file: file, line: line)
        XCTAssertEqual(evidence.sha256, staged.originalSHA256, file: file, line: line)
        XCTAssertEqual(evidence.createdAt, createdAt, file: file, line: line)
        XCTAssertEqual(
            evidence.thumbnailRelativePath,
            staged.thumbnailRelativePath,
            file: file,
            line: line
        )
        XCTAssertEqual(
            evidence.thumbnailByteCount,
            staged.thumbnailByteCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            evidence.thumbnailSHA256,
            staged.thumbnailSHA256,
            file: file,
            line: line
        )
        let staging = generationRoot.appendingPathComponent(
            staged.stagingDirectoryRelativePath,
            isDirectory: true
        )
        XCTAssertFalse(fileManager.fileExists(atPath: staging.path), file: file, line: line)
        let original = try? Data(
            contentsOf: generationRoot.appendingPathComponent(evidence.relativePath)
        )
        let thumbnail = try? Data(
            contentsOf: generationRoot.appendingPathComponent(
                evidence.thumbnailRelativePath
            )
        )
        XCTAssertEqual(original?.count, evidence.byteCount, file: file, line: line)
        XCTAssertEqual(thumbnail?.count, evidence.thumbnailByteCount, file: file, line: line)
        XCTAssertEqual(original.map(sha256), evidence.sha256, file: file, line: line)
        XCTAssertEqual(thumbnail.map(sha256), evidence.thumbnailSHA256, file: file, line: line)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("S3_2MediaPipelineTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makePNG(
        width: Int,
        height: Int,
        seed: UInt8,
        orientation: Int? = nil
    ) throws -> Data {
        let image = try makeImage(width: width, height: height, seed: seed)
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        return try encodePNG(image, properties: properties)
    }

    private func makeImage(width: Int, height: Int, seed: UInt8) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = seed &+ UInt8(truncatingIfNeeded: x)
                pixels[index + 1] = seed &+ UInt8(truncatingIfNeeded: y)
                pixels[index + 2] = seed &+ UInt8(truncatingIfNeeded: x ^ y)
                pixels[index + 3] = 255
            }
        }
        let pixelData = Data(pixels)
        guard let provider = CGDataProvider(data: pixelData as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw FixtureError.couldNotCreateImage
        }
        return image
    }

    private func makeTransparentPNG(width: Int, height: Int) throws -> Data {
        let pixels = Data(repeating: 0, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw FixtureError.couldNotCreateImage
        }
        return try encodePNG(image, properties: [:])
    }

    private func makeAnimatedPNG() throws -> Data {
        let image = try makeImage(width: 8, height: 8, seed: 23)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            2,
            nil
        ) else {
            throw FixtureError.couldNotCreateImage
        }
        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGLoopCount: 0,
                ],
            ] as CFDictionary
        )
        let frameProperties = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGDelayTime: 0.1,
            ],
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, frameProperties)
        CGImageDestinationAddImage(destination, image, frameProperties)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.couldNotCreateImage
        }
        return output as Data
    }

    private func encodePNG(
        _ image: CGImage,
        properties: [CFString: Any]
    ) throws -> Data {

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(
            destination,
            image,
            properties.isEmpty ? nil : properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.couldNotCreateImage
        }
        return output as Data
    }

    private func sampledRGBA(
        fromJPEG data: Data
    ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw FixtureError.couldNotCreateImage
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { throw FixtureError.couldNotCreateImage }
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    private func assertExactCanonicalJPEGMetadata(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let segments = try jpegMetadataSegments(data)
            let jfif = segments.filter { $0.marker == 0xe0 }
            let icc = segments.filter { $0.marker == 0xe2 }
            XCTAssertEqual(jfif.count, 1, file: file, line: line)
            XCTAssertEqual(
                jfif.first?.payload,
                Data([
                    0x4a, 0x46, 0x49, 0x46, 0x00,
                    0x01, 0x01, 0x00,
                    0x00, 0x01, 0x00, 0x01,
                    0x00, 0x00,
                ]),
                file: file,
                line: line
            )
            XCTAssertFalse(icc.isEmpty, file: file, line: line)
            XCTAssertTrue(
                segments.allSatisfy { $0.marker == 0xe0 || $0.marker == 0xe2 },
                file: file,
                line: line
            )

            guard icc.allSatisfy({ $0.payload.count >= 14 }) else {
                throw FixtureError.invalidJPEG
            }
            let expectedCount = Int(icc[0].payload[13])
            XCTAssertEqual(icc.count, expectedCount, file: file, line: line)
            let orderedICC = icc.sorted {
                $0.payload[12] < $1.payload[12]
            }
            var reconstructed = Data()
            for (index, segment) in orderedICC.enumerated() {
                let signatureCount = 12
                XCTAssertEqual(
                    segment.payload.prefix(signatureCount),
                    Data("ICC_PROFILE\0".utf8),
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    segment.payload[signatureCount],
                    UInt8(index + 1),
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    segment.payload[signatureCount + 1],
                    UInt8(expectedCount),
                    file: file,
                    line: line
                )
                reconstructed.append(segment.payload.dropFirst(signatureCount + 2))
            }
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let selectedICC = try XCTUnwrap(colorSpace.copyICCData()) as Data
            XCTAssertEqual(reconstructed, selectedICC, file: file, line: line)
        } catch {
            XCTFail("Independent JPEG metadata parse failed: \(error)", file: file, line: line)
        }
    }

    private func jpegMetadataSegments(_ data: Data) throws -> [JPEGMetadataSegment] {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else {
            throw FixtureError.invalidJPEG
        }
        var offset = 2
        var segments: [JPEGMetadataSegment] = []
        while offset + 1 < bytes.count {
            guard bytes[offset] == 0xff else { throw FixtureError.invalidJPEG }
            while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
            guard offset < bytes.count else { throw FixtureError.invalidJPEG }
            let marker = bytes[offset]
            offset += 1
            if marker == 0xda || marker == 0xd9 { return segments }
            if marker == 0x01 || (0xd0...0xd7).contains(marker) { continue }
            guard offset + 1 < bytes.count else { throw FixtureError.invalidJPEG }
            let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            guard length >= 2, offset + length <= bytes.count else {
                throw FixtureError.invalidJPEG
            }
            if (0xe0...0xef).contains(marker) || marker == 0xfe {
                segments.append(
                    JPEGMetadataSegment(
                        marker: marker,
                        payload: Data(bytes[(offset + 2)..<(offset + length)])
                    )
                )
            }
            offset += length
        }
        throw FixtureError.invalidJPEG
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum FixtureError: Error {
    case couldNotCreateImage
    case invalidJPEG
}

private struct JPEGMetadataSegment {
    let marker: UInt8
    let payload: Data
}

extension S3_2MediaPipelineTests {
    func testC36AttachmentPreflightAccountsForScratchAndDurableStage() throws {
        let service = StoragePreflightService(capacityProvider: { _ in Int64.max })
        let byteCount: Int64 = 4_096
        XCTAssertEqual(
            try service.draftAttachmentRequiredBytes(byteCount: byteCount),
            byteCount * 2 + StoragePreflightService.reserveBytes
        )
        XCTAssertTrue(StoragePreflightService.c36StagingExcludedFromBackup)
        XCTAssertTrue(StoragePreflightService.c36StoragePressureIsRetryable)
        XCTAssertThrowsError(try service.draftAttachmentRequiredBytes(byteCount: 0))
    }
}

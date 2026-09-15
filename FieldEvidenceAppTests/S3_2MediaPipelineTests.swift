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

    func testSourceInspectionRetainsOriginalFactsAndExactNormalizedOutputs() async throws {
        let normalizer = MediaNormalizerV1()
        let source = try makePNG(width: 40, height: 20, seed: 53, orientation: 6)
        let sourceDigest = sha256(source)
        let facts = try normalizer.inspectSource(source)
        XCTAssertEqual(facts.sourceTypeIdentifier, UTType.png.identifier)
        XCTAssertEqual(facts.pixelWidth, 40)
        XCTAssertEqual(facts.pixelHeight, 20)
        XCTAssertEqual(facts.byteCount, source.count)

        let result = try normalizer.normalizeWithSourceFacts(source)
        XCTAssertEqual(result.sourceFacts, facts)
        XCTAssertEqual(result.normalized, try normalizer.normalize(source))
        XCTAssertEqual(sha256(source), sourceDigest)
        let normalizedFacts = try normalizer.validateCanonicalJPEG(
            result.normalized.originalJPEG, kind: .original
        )
        XCTAssertEqual(normalizedFacts.pixelWidth, 20)
        XCTAssertEqual(normalizedFacts.pixelHeight, 40)
        assertExactCanonicalJPEGMetadata(result.normalized.originalJPEG)
        assertExactCanonicalJPEGMetadata(result.normalized.thumbnailJPEG)

        let jpegFacts = try normalizer.inspectSource(result.normalized.originalJPEG)
        XCTAssertEqual(jpegFacts.sourceTypeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(jpegFacts.pixelWidth, normalizedFacts.pixelWidth)
        XCTAssertEqual(jpegFacts.pixelHeight, normalizedFacts.pixelHeight)
        XCTAssertEqual(jpegFacts.byteCount, result.normalized.originalJPEG.count)
        try await verifyCommittedPhotoMediaReadbacks(source: source, normalized: result.normalized)
    }

    private func verifyCommittedPhotoMediaReadbacks(source: Data, normalized: NormalizedMediaV1) async throws {
        let applicationSupport = try makeTemporaryDirectory().resolvingSymlinksInPath()
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let root = applicationSupport.appendingPathComponent(
            "FieldEvidenceData/generations/\(UUID().uuidString.lowercased())", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = WorkspaceID(rawValue: UUID())
        let childID = UUID(), stageID = UUID(), evidenceID = UUID()
        let date = Date(timeIntervalSince1970: 1_789_323_456)
        let normalizer = MediaNormalizerV1()
        let inspection = try CheckRunnerPhotoSourceInspectionV1(facts: normalizer.inspectSource(source),
            sourceSHA256: .init(algorithm: .sha256, hexadecimalValue: sha256(source)),
            workspaceID: workspace, provenanceID: "photo-media-read-original")
        let intent = try CheckRunnerPhotoRawStageIntentV1(stageID: stageID,
            stageMutationID: .init(rawValue: UUID()), stageCreatedAt: date,
            expectedSourceByteCount: Int64(source.count), provenanceID: inspection.provenanceID,
            evidenceID: evidenceID, evidenceCreatedAt: date)
        let ready = try AttachmentStagingItemV1(stageID: stageID, draftID: childID,
            workspaceID: workspace, attachmentKind: .photo, scratchLeaseID: stageID,
            expectedByteCount: Int64(source.count), actualByteCount: Int64(source.count),
            contentDigest: inspection.sourceSHA256, retryClass: .none, state: .readyLocal,
            protectionState: .available, revision: 1, mutationID: intent.stageMutationID)
        let provenance = try ContentOriginalProvenanceV1(provenanceID: inspection.provenanceID,
            workspaceID: workspace.rawValue.uuidString.lowercased(), contentID: inspection.rawContentID,
            contentDigest: inspection.sourceSHA256, origin: .humanCapture,
            recordedAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(date))
        let raw = try CheckRunnerPhotoRawReadyV1(intent: intent, inspection: inspection,
            readyItem: ready, stagePublicationMutationID: intent.stageMutationID,
            originalProvenance: provenance)
        let store = EvidenceBundleStore(generationRootURL: root)
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: workspace,
            contentID: inspection.rawContentID, digest: inspection.sourceSHA256,
            byteLength: inspection.sourceByteCount, mediaType: inspection.sourceMediaType,
            mutationID: .init(rawValue: UUID()),
            createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(date.addingTimeInterval(1)))
        let written = try await store.persistImmutableOriginal(bytes: source, request: request)
        try written.validate(request: request, bytes: source)
        let reference = try ContentReferenceV1(workspaceID: written.workspaceID.rawValue.uuidString.lowercased(),
            contentID: written.contentID, byteLength: written.byteLength, mediaType: written.mediaType,
            digests: .init([written.digest]), byteRole: written.byteRole, createdAt: written.createdAt)
        let staged = try await store.stage(evidenceID: evidenceID, normalized: normalized)
        let promoted = try await store.promote(staged)
        let originalPixels = try normalizer.validateCanonicalJPEG(normalized.originalJPEG, kind: .original)
        let thumbnailPixels = try normalizer.validateCanonicalJPEG(normalized.thumbnailJPEG, kind: .thumbnail)
        func expectedPair(originalWidth: Int? = nil) throws -> CheckRunnerPhotoNormalizedPairV1 {
            try .init(evidenceID: evidenceID, originalRelativePath: promoted.originalRelativePath,
                originalByteCount: Int64(promoted.originalByteCount), originalSHA256: promoted.originalSHA256,
                originalPixelWidth: originalWidth ?? originalPixels.pixelWidth,
                originalPixelHeight: originalPixels.pixelHeight,
                thumbnailRelativePath: promoted.thumbnailRelativePath,
                thumbnailByteCount: Int64(promoted.thumbnailByteCount), thumbnailSHA256: promoted.thumbnailSHA256,
                thumbnailPixelWidth: thumbnailPixels.pixelWidth, thumbnailPixelHeight: thumbnailPixels.pixelHeight,
                sourceBinding: .init(contentID: inspection.rawContentID, digest: inspection.sourceSHA256),
                sanitizedDerivative: CheckRunnerPhotoSourceMetadataProfileV1.sanitizedDerivative(),
                thumbnailDerivative: CheckRunnerPhotoSourceMetadataProfileV1.thumbnailDerivative(
                    pixelWidth: thumbnailPixels.pixelWidth, pixelHeight: thumbnailPixels.pixelHeight))
        }
        let pair = try expectedPair()
        let identity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        func read(pair expected: CheckRunnerPhotoNormalizedPairV1? = nil,
                  raw sourceClaim: CheckRunnerPhotoRawReadyV1? = nil) async throws -> CheckRunnerPhotoMediaReadbackV1 {
            try await store.readCheckRunnerPhotoMedia(raw: sourceClaim ?? raw, pair: expected ?? pair,
                reference: reference, expectedGenerationRootIdentity: (identity.device, identity.inode))
        }
        func reject(_ message: String, pair expected: CheckRunnerPhotoNormalizedPairV1? = nil,
                    raw sourceClaim: CheckRunnerPhotoRawReadyV1? = nil) async {
            do { _ = try await read(pair: expected, raw: sourceClaim); XCTFail(message) }
            catch { /* The exact owned bytes or their expected facts were rejected. */ }
        }
        let membersBefore = try fileManager.subpathsOfDirectory(atPath: root.path).sorted()
        let readback = try await read()
        XCTAssertEqual(readback.rawReference, reference)
        XCTAssertEqual(readback.sourceInspection, inspection)
        XCTAssertEqual(readback.normalizedPair, pair)
        let reopened = EvidenceBundleStore(generationRootURL: root)
        let coldRead = try await reopened.readCheckRunnerPhotoMedia(raw: raw, pair: pair,
            reference: reference, expectedGenerationRootIdentity: (identity.device, identity.inode))
        XCTAssertEqual(coldRead, readback)
        XCTAssertEqual(try fileManager.subpathsOfDirectory(atPath: root.path).sorted(), membersBefore)
        await reject("Declared pixels must match the actual canonical JPEG",
            pair: try expectedPair(originalWidth: originalPixels.pixelWidth + 1))
        let wrongInspection = try CheckRunnerPhotoSourceInspectionV1(
            sourceByteCount: inspection.sourceByteCount, sourceSHA256: inspection.sourceSHA256,
            detectedUTI: inspection.detectedUTI, sourceMediaType: inspection.sourceMediaType,
            pixelWidth: inspection.pixelWidth + 1, pixelHeight: inspection.pixelHeight,
            decodedPixelCount: Int64((inspection.pixelWidth + 1) * inspection.pixelHeight),
            frameCount: 1, rawContentID: inspection.rawContentID, provenanceID: inspection.provenanceID)
        let wrongRaw = try CheckRunnerPhotoRawReadyV1(intent: intent, inspection: wrongInspection,
            readyItem: ready, stagePublicationMutationID: intent.stageMutationID, originalProvenance: provenance)
        await reject("Source inspection must be repeated on the actual original bytes", raw: wrongRaw)
        do {
            _ = try await store.readCheckRunnerPhotoMedia(raw: raw, pair: pair, reference: reference,
                expectedGenerationRootIdentity: (identity.device, identity.inode &+ 1))
            XCTFail("A different generation inode must not supply media evidence")
        } catch { XCTAssertEqual(error as? EvidenceBundleStoreError, .generationRootInvalid) }

        let rawURL = root.appendingPathComponent(written.relativePath)
        let originalURL = root.appendingPathComponent(promoted.originalRelativePath)
        let thumbnailURL = root.appendingPathComponent(promoted.thumbnailRelativePath)
        for (url, bytes) in [(rawURL, source), (originalURL, normalized.originalJPEG),
                             (thumbnailURL, normalized.thumbnailJPEG)] {
            let hidden = url.appendingPathExtension("retained")
            try fileManager.moveItem(at: url, to: hidden)
            await reject("Missing owned media must fail without recreation")
            XCTAssertFalse(fileManager.fileExists(atPath: url.path))
            XCTAssertEqual(try Data(contentsOf: hidden), bytes)
            try fileManager.moveItem(at: hidden, to: url)
            var changed = bytes
            changed[changed.count - 1] ^= 1
            try changed.write(to: url)
            await reject("Changed raw or JPEG bytes must fail without repair")
            XCTAssertEqual(try Data(contentsOf: url), changed)
            try bytes.write(to: url)
        }
        let hiddenRaw = rawURL.appendingPathExtension("retained")
        try fileManager.moveItem(at: rawURL, to: hiddenRaw)
        try fileManager.createSymbolicLink(at: rawURL, withDestinationURL: hiddenRaw)
        await reject("A symlink cannot supply raw source authority")
        XCTAssertEqual(try Data(contentsOf: hiddenRaw), source)
        try fileManager.removeItem(at: rawURL)
        try fileManager.moveItem(at: hiddenRaw, to: rawURL)
        let marker = originalURL.deletingLastPathComponent().appendingPathComponent("pair-publication.json")
        try Data("unexpected final marker".utf8).write(to: marker)
        await reject("The committed evidence bundle must retain its exact two-file shape")
        XCTAssertTrue(fileManager.fileExists(atPath: marker.path))
        try fileManager.removeItem(at: marker)
        let finalRead = try await read()
        XCTAssertEqual(finalRead, readback)
        XCTAssertEqual(try fileManager.subpathsOfDirectory(atPath: root.path).sorted(), membersBefore)
        XCTAssertEqual(try Data(contentsOf: rawURL), source)
        XCTAssertEqual(try Data(contentsOf: originalURL), normalized.originalJPEG)
        XCTAssertEqual(try Data(contentsOf: thumbnailURL), normalized.thumbnailJPEG)
        try await verifyStagedPhotoPairReadbacks(raw: raw, wrongRaw: wrongRaw,
            normalized: .init(sourceFacts: normalizer.inspectSource(source), normalized: normalized))
    }

    private func verifyStagedPhotoPairReadbacks(raw: CheckRunnerPhotoRawReadyV1,
        wrongRaw: CheckRunnerPhotoRawReadyV1, normalized: NormalizedMediaWithSourceFactsV1) async throws {
        let applicationSupport = try makeTemporaryDirectory().resolvingSymlinksInPath()
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let root = applicationSupport.appendingPathComponent(
            "FieldEvidenceData/generations/\(UUID().uuidString.lowercased())", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        let rootIdentity = (device: identity.device, inode: identity.inode)
        let childID = raw.readyItem.draftID, parentID = UUID()
        let store = EvidenceBundleStore(generationRootURL: root)
        let id = raw.intent.evidenceID.uuidString.lowercased()
        let directory = root.appendingPathComponent(".staging/evidence/\(id)", isDirectory: true)
        let privateDirectory = root.appendingPathComponent(".staging/evidence/.\(id).pair.tmp", isDirectory: true)
        let original = directory.appendingPathComponent("original.jpg")
        let thumbnail = directory.appendingPathComponent("thumbnail.jpg")
        let marker = directory.appendingPathComponent("pair-publication.json")
        let names: Set<String> = ["original.jpg", "thumbnail.jpg", "pair-publication.json"]
        func read(_ selected: EvidenceBundleStore? = nil,
                  parent: UUID? = nil, source: CheckRunnerPhotoRawReadyV1? = nil) async throws
            -> CheckRunnerPhotoStagedPairReadbackV1? {
            try await (selected ?? store).readStagedCheckRunnerPhotoPair(childDraftID: childID,
                parentDraftID: parent ?? parentID, raw: source ?? raw,
                expectedGenerationRootIdentity: rootIdentity)
        }
        func publish(_ selected: EvidenceBundleStore? = nil,
                     input: NormalizedMediaWithSourceFactsV1? = nil) async throws -> CheckRunnerPhotoStagedPairReadbackV1 {
            try await (selected ?? store).stageOrAdoptCheckRunnerPhotoPair(childDraftID: childID,
                parentDraftID: parentID, raw: raw, normalized: input ?? normalized,
                expectedGenerationRootIdentity: rootIdentity)
        }
        func reject(_ message: String, parent: UUID? = nil, source: CheckRunnerPhotoRawReadyV1? = nil) async {
            do { _ = try await read(parent: parent, source: source); XCTFail(message) } catch {}
        }
        let absent = try await read()
        XCTAssertNil(absent)
        XCTAssertEqual(try fileManager.subpathsOfDirectory(atPath: root.path), [])
        let published = try await publish()
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: directory.path)), names)
        XCTAssertFalse(fileManager.fileExists(atPath: privateDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("evidence/\(id)").path))
        XCTAssertEqual(try Data(contentsOf: original), normalized.normalized.originalJPEG)
        XCTAssertEqual(try Data(contentsOf: thumbnail), normalized.normalized.thumbnailJPEG)
        XCTAssertEqual(try Data(contentsOf: marker), published.markerBytes)
        XCTAssertEqual(published.markerSHA256, sha256(published.markerBytes))
        XCTAssertEqual(published.marker.childDraftID, childID)
        XCTAssertEqual(published.marker.parentDraftID, parentID)
        XCTAssertEqual(published.marker.stageID, raw.intent.stageID)
        XCTAssertEqual(published.staged.evidenceID, raw.intent.evidenceID)
        XCTAssertEqual(published.markerSHA256, try CheckRunnerPhotoPairReadyV1.markerSHA256(
            childDraftID: childID, parentDraftID: parentID, raw: raw,
            normalizedPair: published.marker.normalizedPair))
        let coldStore = EvidenceBundleStore(generationRootURL: root)
        let cold = try await read(coldStore)
        XCTAssertEqual(cold, published)
        // Exact adoption reads no new normalization output. Even a deliberately
        // unusable unused input cannot replace a valid earlier publication.
        let unused = NormalizedMediaWithSourceFactsV1(
            sourceFacts: .init(sourceTypeIdentifier: "unused", pixelWidth: 0, pixelHeight: 0, byteCount: 0),
            normalized: .init(originalJPEG: Data(), thumbnailJPEG: Data()))
        let adopted = try await publish(coldStore, input: unused)
        XCTAssertEqual(adopted, published)
        await reject("A different parent cannot adopt this pair", parent: UUID())
        await reject("A marker must match the actual retained raw inspection", source: wrongRaw)
        do {
            _ = try await store.readStagedCheckRunnerPhotoPair(childDraftID: childID, parentDraftID: parentID,
                raw: raw, expectedGenerationRootIdentity: (identity.device, identity.inode &+ 1))
            XCTFail("A changed root must not publish staging facts")
        } catch { XCTAssertEqual(error as? EvidenceBundleStoreError, .generationRootInvalid) }
        do {
            _ = try await store.promote(published.staged)
            XCTFail("Legacy promotion must reject the extra staging marker")
        } catch { XCTAssertEqual(error as? EvidenceBundleStoreError, .bundleShapeInvalid) }
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: directory.path)), names)
        let retainedFiles = [(original, normalized.normalized.originalJPEG),
                             (thumbnail, normalized.normalized.thumbnailJPEG), (marker, published.markerBytes)]
        for (url, bytes) in retainedFiles {
            let retained = applicationSupport.appendingPathComponent("retained-\(url.lastPathComponent)")
            try fileManager.moveItem(at: url, to: retained)
            await reject("Every missing pair member must fail without recreation")
            do { _ = try await publish(); XCTFail("Partial staging must not be overwritten") } catch {}
            XCTAssertFalse(fileManager.fileExists(atPath: url.path))
            XCTAssertEqual(try Data(contentsOf: retained), bytes)
            try fileManager.moveItem(at: retained, to: url)
            var changed = bytes; changed[changed.count - 1] ^= 1
            try changed.write(to: url)
            await reject("Changed pair or marker bytes cannot be repaired on read")
            do { _ = try await publish(); XCTFail("Divergent staging must not be overwritten") } catch {}
            XCTAssertEqual(try Data(contentsOf: url), changed)
            try bytes.write(to: url)
        }
        let extra = directory.appendingPathComponent("unexpected.bin")
        try Data([1, 2, 3]).write(to: extra)
        await reject("Unknown staging members must remain a conflict")
        XCTAssertEqual(try Data(contentsOf: extra), Data([1, 2, 3]))
        try fileManager.removeItem(at: extra)
        let retainedOriginal = applicationSupport.appendingPathComponent("retained-original.jpg")
        try fileManager.moveItem(at: original, to: retainedOriginal)
        try fileManager.createSymbolicLink(at: original, withDestinationURL: retainedOriginal)
        await reject("A symlink does not own normalized JPEG bytes")
        XCTAssertEqual(try Data(contentsOf: retainedOriginal), normalized.normalized.originalJPEG)
        try fileManager.removeItem(at: original)
        try fileManager.moveItem(at: retainedOriginal, to: original)
        for (url, maximum, bytes) in [
            (original, MediaContractV1.originalByteCountMaximum, normalized.normalized.originalJPEG),
            (thumbnail, MediaContractV1.thumbnailByteCountMaximum, normalized.normalized.thumbnailJPEG),
            (marker, FieldDraftLimitsV1.maximumCanonicalBytes, published.markerBytes)
        ] {
            // Sparse oversize files exercise stat admission without allocating
            // a second maximum-size Data fixture in the test process.
            let handle = try FileHandle(forWritingTo: url)
            try handle.seek(toOffset: UInt64(maximum))
            try handle.write(contentsOf: Data([0]))
            try handle.close()
            await reject("Oversize members must fail before unbounded allocation")
            XCTAssertEqual((try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
                           maximum + 1)
            try bytes.write(to: url)
        }
        let cancelRead = Task<CheckRunnerPhotoStagedPairReadbackV1?, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.readStagedCheckRunnerPhotoPair(childDraftID: childID, parentDraftID: parentID,
                raw: raw, expectedGenerationRootIdentity: rootIdentity)
        }
        do { _ = try await cancelRead.value; XCTFail("Cancelled reads must not return a witness") }
        catch { XCTAssertTrue(error is CancellationError) }
        let afterHostile = try await read()
        XCTAssertEqual(afterHostile, published)
        for (url, bytes) in retainedFiles { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        try fileManager.removeItem(at: directory)
        let cancelledWrite = Task<CheckRunnerPhotoStagedPairReadbackV1, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.stageOrAdoptCheckRunnerPhotoPair(childDraftID: childID, parentDraftID: parentID,
                raw: raw, normalized: normalized, expectedGenerationRootIdentity: rootIdentity)
        }
        do { _ = try await cancelledWrite.value; XCTFail("Cancelled staging must not start writing") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: privateDirectory.path))
        try fileManager.createDirectory(at: privateDirectory, withIntermediateDirectories: false)
        let sentinel = privateDirectory.appendingPathComponent("unowned.bin")
        try Data([7, 8, 9]).write(to: sentinel)
        do { _ = try await publish(); XCTFail("A preexisting private directory must not be reused or cleaned") }
        catch { XCTAssertEqual(error as? EvidenceBundleStoreError, .stagingBundleAlreadyExists) }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([7, 8, 9]))
        try fileManager.removeItem(at: privateDirectory)
        let boundaries: [EvidenceBundleStoreFailurePoint] = [.checkRunnerPhotoOriginalWritten,
            .checkRunnerPhotoThumbnailWritten, .checkRunnerPhotoMarkerWritten, .checkRunnerPhotoPublished]
        for point in boundaries {
            let injected = EvidenceBundleStore(generationRootURL: root,
                failureInjection: .init(failOnceAt: point))
            do { _ = try await publish(injected); XCTFail("The requested publication boundary must interrupt") }
            catch { XCTAssertEqual(error as? EvidenceBundleStoreError, .fileOperationFailed) }
            XCTAssertFalse(fileManager.fileExists(atPath: privateDirectory.path))
            XCTAssertEqual(fileManager.fileExists(atPath: directory.path), point == .checkRunnerPhotoPublished)
            let reopened = EvidenceBundleStore(generationRootURL: root)
            let recovered = try await read(reopened)
            if point == .checkRunnerPhotoPublished {
                XCTAssertEqual(recovered, published)
                XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: directory.path)), names)
                let adoptedAgain = try await publish(reopened, input: unused)
                XCTAssertEqual(adoptedAgain, published)
            } else {
                XCTAssertNil(recovered)
                let regenerated = try await publish(reopened)
                XCTAssertEqual(regenerated, published)
            }
            for (url, bytes) in retainedFiles { XCTAssertEqual(try Data(contentsOf: url), bytes) }
            try fileManager.removeItem(at: directory)
        }
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path), [])
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("evidence/\(id)").path))
    }

    func testSourceInspectionPreservesInvalidInputFailurePrecedence() throws {
        let normalizer = MediaNormalizerV1()
        let onePixelGIF = try XCTUnwrap(
            Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")
        )
        let cases: [(Data, MediaImportErrorV1)] = [
            (Data([0x00, 0x01, 0x02]), .malformedSource),
            (onePixelGIF, .unsupportedSourceType),
            (try makeAnimatedPNG(), .animatedOrMultipageSource),
            (try makePNG(width: 16_385, height: 1, seed: 17), .sourceDimensionsOutOfRange),
            (Data(count: MediaContractV1.sourceByteCountMaximum + 1), .sourceTooLarge),
        ]
        for (source, expected) in cases {
            XCTAssertThrowsError(try normalizer.inspectSource(source)) {
                XCTAssertEqual($0 as? MediaImportErrorV1, expected)
            }
            XCTAssertThrowsError(try normalizer.normalizeWithSourceFacts(source)) {
                XCTAssertEqual($0 as? MediaImportErrorV1, expected)
            }
            XCTAssertThrowsError(try normalizer.normalize(source)) {
                XCTAssertEqual($0 as? MediaImportErrorV1, expected)
            }
        }
    }

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
        let applicationSupport = try makeTemporaryDirectory().resolvingSymlinksInPath()
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let generationRoot = applicationSupport.appendingPathComponent(
            "FieldEvidenceData/generations/\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(at: generationRoot, withIntermediateDirectories: true)
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
        let applicationSupport = try makeTemporaryDirectory().resolvingSymlinksInPath()
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

        var phase = "bootstrap"
        do {
        do {
            let session = try factory.openOrBootstrapCurrent()
            registerMediaSessionCleanup(root: applicationSupport, session: session)
            let context = session.modelContext
            phase = "writer-create"
            let storeCoordinator = try StoreSessionCoordinator(validatingSession: session)
            defer {
                do { try storeCoordinator.invalidateAndReleaseWriter() }
                catch { XCTFail("Media fixture writer release failed: \(error)") }
            }
            let siteID = UUID()
            assetID = UUID()
            let placementMutationID = try MutationIDV1(rawValue: UUID())
            phase = "first-sign"
            _ = try storeCoordinator.workspaceWriter.execute(
                .createFirstSign(.init(
                    siteID: siteID,
                    newSite: .init(id: siteID, label: "North Campus", address: nil,
                                   timeZoneID: "America/New_York"),
                    assetID: assetID,
                    assetLabel: "Monument Sign",
                    packID: pack.packID,
                    packSchemaVersion: pack.schemaVersion,
                    packContentVersion: pack.contentVersion,
                    createdAt: observedAt.addingTimeInterval(-100),
                    initialPlacementMutationID: placementMutationID,
                    initialPlacementEventID: UUID(),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
                )),
                mutationID: placementMutationID
            )
            let asset = try XCTUnwrap(context.fetch(FetchDescriptor<Asset>()).first { $0.id == assetID })
            phase = "runner-create"
            let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
            let coordinator = try CheckRunnerCoordinator(
                modelContext: context,
                packageLifecycleDependencies: storeCoordinator.packageLifecycleDependencies(),
                packageLifecycleProfile: profile
            )
            coordinator.configureCapture(generationRootURL: session.generationRootURL)
            phase = "begin-check"
            let draft = try coordinator.beginCheck(
                assetID: asset.id,
                timeZoneID: nil,
                isTimeZoneConfirmed: false,
                afterDarkAccepted: true,
                safePositionAccepted: true,
                observedAt: observedAt
            )
            draftID = draft.id

            phase = "wide-import"
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
            phase = "wide-accept"
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

            phase = "retake-import"
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
            phase = "retake"
            try await coordinator.retake(candidate: rejectedClose)
            XCTAssertFalse(fileManager.fileExists(atPath: rejectedStagingURL.path))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 1)
            XCTAssertEqual(draft.draftStepKey, WorkflowDraftStep.close.rawValue)
            XCTAssertEqual(try Data(contentsOf: wideOriginalURL), expectedWideOriginal)
            XCTAssertEqual(try Data(contentsOf: wideThumbnailURL), expectedWideThumbnail)

            phase = "close-import"
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
            phase = "close-accept"
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
            phase = "cold-reopen"
            let reopenedSession = try factory.openOrBootstrapCurrent()
            registerMediaSessionCleanup(root: applicationSupport, session: reopenedSession)
            let reopenedStoreCoordinator = try StoreSessionCoordinator(validatingSession: reopenedSession)
            defer {
                do { try reopenedStoreCoordinator.invalidateAndReleaseWriter() }
                catch { XCTFail("Media reopened fixture writer release failed: \(error)") }
            }
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
                    storeCoordinator: reopenedStoreCoordinator,
                    pack: pack,
                    generationRoot: reopenedSession.generationRootURL,
                    assetID: assetID
                ).step,
                .outcome
            )
            withExtendedLifetime(reopenedSession) {}
        }
        } catch {
            FileHandle.standardError.write(Data("S3_2 media fixture failure phase=\(phase) type=\(String(reflecting: type(of: error))) error=\(error)\n".utf8))
            throw error
        }
    }

    @MainActor
    private func coordinatorPreparation(
        context: ModelContext,
        storeCoordinator: StoreSessionCoordinator,
        pack: SignPack,
        generationRoot: URL,
        assetID: UUID
    ) throws -> CapturePreparation {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let coordinator = try CheckRunnerCoordinator(
            modelContext: context,
            packageLifecycleDependencies: storeCoordinator.packageLifecycleDependencies(),
            packageLifecycleProfile: profile
        )
        coordinator.configureCapture(generationRootURL: generationRoot)
        return try coordinator.prepareCapture(assetID: assetID)
    }

    @MainActor
    private func registerMediaSessionCleanup(root: URL, session: StoreGenerationSession) {
        addTeardownBlock { [weak session = session, root] in
            guard session == nil else {
                XCTFail("Media fixture cleanup requires the store session graph to be released")
                return
            }
            guard FileManager.default.fileExists(atPath: root.path) else { return }
            try FileManager.default.removeItem(at: root)
        }
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

extension S3_2MediaPipelineTests {
    func testV23P03C34SceneResumeDoesNotStartMediaWork() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x02)))
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .assets, requestedMode: .resume)
        let today = try NavigationTargetV1(workspaceID: workspace, destination: .today)
        let work = try NavigationTargetV1(workspaceID: workspace, destination: .work)
        let reports = try NavigationTargetV1(workspaceID: workspace, destination: .reports)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .assets, paths: [
            .init(root: .today, targets: [today]),
            .init(root: .work, targets: [work]),
            .init(root: .assets, targets: [target]),
            .init(root: .reports, targets: [reports])
        ], snapshotID: UUID())
        let receipt = try RouteCoordinatorV1(registry: try RouteRegistryV1()).restore(.init(
            context: .init(currentWorkspaceID: workspace, currentRevision: 0),
            startupMaintenanceTarget: nil,
            incompleteMutationRecoveryTarget: nil,
            explicitIngressTarget: nil,
            sceneSnapshot: snapshot,
            discardedSnapshotReason: nil,
            evidenceKind: .interruption,
            receiptID: UUID()
        ))
        XCTAssertEqual(receipt.source, .sceneSnapshot)
        XCTAssertEqual(receipt.result.target.destination, .assets)
        XCTAssertEqual(receipt.canonicalMutationCount, 0)
        XCTAssertFalse(receipt.startsAutomaticWork)
    }
}

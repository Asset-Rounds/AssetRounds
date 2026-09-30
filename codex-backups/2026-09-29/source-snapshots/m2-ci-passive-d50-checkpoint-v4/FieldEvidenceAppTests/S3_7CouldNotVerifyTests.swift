import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S3_7CouldNotVerifyTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testOneWideRequiredViewObstructedCreatesExactIncompleteAuthorityAndReplays() async throws {
        let applicationSupport = try makeTemporaryDirectory("golden")
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let harness = try await makeHarness(
            applicationSupportURL: applicationSupport,
            acceptsWide: true
        )
        let selection = CheckOutcomeSelection.couldNotVerify(
            reasonKey: "required_view_obstructed",
            note: "Tree branches blocked the close view."
        )
        let review = try harness.coordinator.prepareReview(
            assetID: harness.asset.id,
            selection: selection
        )
        XCTAssertEqual(review.outcomeKey, "could_not_verify")
        XCTAssertEqual(review.couldNotVerifyReasonDisplay, "Required view is blocked")
        XCTAssertEqual(review.note, "Tree branches blocked the close view.")
        XCTAssertNotNil(review.wideEvidence)
        XCTAssertNil(review.closeEvidence)
        XCTAssertEqual(review.missingPurposeDisplays, ["Close view"])

        let identifiers = makeIdentifiers()
        let completedAt = Date(timeIntervalSince1970: 1_768_700_003)
        let snapshotAt = Date(timeIntervalSince1970: 1_768_700_004)
        let sourceApp = SourceAppSnapshotV1(build: "37", version: "1.0")
        let result = try await harness.coordinator.finalize(
            assetID: harness.asset.id,
            selection: selection,
            completedAt: completedAt,
            snapshotCreatedAt: snapshotAt,
            sourceApp: sourceApp,
            identifiers: identifiers
        )
        let replay = try await harness.coordinator.finalize(
            assetID: harness.asset.id,
            selection: selection,
            completedAt: completedAt,
            snapshotCreatedAt: snapshotAt,
            sourceApp: sourceApp,
            identifiers: identifiers
        )
        XCTAssertEqual(replay, result)
        try assertCompletedAuthority(
            harness,
            result: result,
            reasonKey: "required_view_obstructed",
            reasonDisplay: "Required view is blocked",
            note: "Tree branches blocked the close view.",
            evidenceCount: 1
        )
        let snapshot = try snapshot(for: result, harness: harness)
        XCTAssertEqual(snapshot.evidence.map(\.purposeKey), ["wide_context"])
        XCTAssertEqual(snapshot.evidenceSourceRecordID, harness.draft.id)
        XCTAssertEqual(snapshot.couldNotVerify?.registryVersion, "cnv.reason.en-US.v1")
        XCTAssertTrue(snapshot.issues.isEmpty)
        withExtendedLifetime(harness.session) {}
    }

    @MainActor
    func testZeroPhotoCaptureUnavailableAndInvalidSelectionsFailClosed() async throws {
        let applicationSupport = try makeTemporaryDirectory("zero-photo")
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let harness = try await makeHarness(
            applicationSupportURL: applicationSupport,
            acceptsWide: false
        )
        let invalidSelections: [CheckOutcomeSelection] = [
            .couldNotVerify(reasonKey: " required_view_obstructed", note: nil),
            .couldNotVerify(reasonKey: "not_in_registry", note: nil),
            .couldNotVerify(reasonKey: "capture_unavailable", note: " untrimmed"),
            .couldNotVerify(reasonKey: "capture_unavailable", note: String(repeating: "x", count: 1_001)),
        ]
        for invalid in invalidSelections {
            XCTAssertThrowsError(
                try harness.coordinator.prepareReview(
                    assetID: harness.asset.id,
                    selection: invalid
                )
            ) {
                XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .invalidLineage)
            }
            try assertDraftOnly(harness)
        }

        let invalidService = try FinalizationService(
            modelContext: harness.context,
            signPack: harness.pack,
            generationRootURL: harness.session.generationRootURL
        )
        let invalidIdentifiers = makeIdentifiers()
        do {
            _ = try await invalidService.finalize(
                FinalizationServiceInput(
                    draft: harness.draft,
                    asset: harness.asset,
                    site: harness.site,
                    evidence: [],
                    outcomeKey: "could_not_verify",
                    outcomeDisplay: "Could not verify",
                    issueLabel: nil,
                    couldNotVerify: .init(
                        key: "capture_unavailable",
                        display: "Wrong display"
                    ),
                    note: nil,
                    completedAt: Date(timeIntervalSince1970: 1_768_700_003),
                    snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_700_004),
                    sourceApp: SourceAppSnapshotV1(build: "37", version: "1.0"),
                    identifiers: invalidIdentifiers
                )
            )
            XCTFail("A mismatched frozen CNV display must fail closed")
        } catch {
            XCTAssertEqual(error as? FinalizationServiceError, .invalidSelection)
        }
        try assertDraftOnly(harness)
        XCTAssertFalse(fileManager.fileExists(atPath: intentURL(invalidIdentifiers, appSupport: applicationSupport).path))

        let selection = CheckOutcomeSelection.couldNotVerify(
            reasonKey: "capture_unavailable",
            note: nil
        )
        let review = try harness.coordinator.prepareReview(
            assetID: harness.asset.id,
            selection: selection
        )
        XCTAssertNil(review.wideEvidence)
        XCTAssertNil(review.closeEvidence)
        XCTAssertEqual(review.missingPurposeDisplays, ["Wide view", "Close view"])
        let result = try await harness.coordinator.finalize(
            assetID: harness.asset.id,
            selection: selection,
            completedAt: Date(timeIntervalSince1970: 1_768_700_005),
            snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_700_006),
            sourceApp: SourceAppSnapshotV1(build: "37", version: "1.0"),
            identifiers: makeIdentifiers()
        )
        try assertCompletedAuthority(
            harness,
            result: result,
            reasonKey: "capture_unavailable",
            reasonDisplay: "Camera or photo capture is unavailable",
            note: nil,
            evidenceCount: 0
        )
        let decoded = try snapshot(for: result, harness: harness)
        XCTAssertTrue(decoded.evidence.isEmpty)
        XCTAssertNil(decoded.note)
        withExtendedLifetime(harness.session) {}
    }

    @MainActor
    func testDuplicateAndWrongPurposeEvidenceFailClosedWithoutFinalizationRows() async throws {
        for purposeKeys in [
            ["wide_context", "wide_context"],
            ["work_context"],
        ] {
            let applicationSupport = try makeTemporaryDirectory(
                "invalid-evidence-\(purposeKeys.joined(separator: "-"))"
            )
            defer { try? fileManager.removeItem(at: applicationSupport) }
            let harness = try await makeHarness(
                applicationSupportURL: applicationSupport,
                acceptsWide: false
            )
            for (index, purposeKey) in purposeKeys.enumerated() {
                let id = UUID()
                harness.context.insert(
                    EvidenceFile(
                        id: id,
                        recordID: harness.draft.id,
                        purposeKey: purposeKey,
                        relativePath: "evidence/\(id.uuidString.lowercased())/original.jpg",
                        mimeType: "image/jpeg",
                        byteCount: 1,
                        sha256: String(repeating: "a", count: 64),
                        createdAt: Date(timeIntervalSince1970: 1_768_700_010 + Double(index)),
                        thumbnailRelativePath: "evidence/\(id.uuidString.lowercased())/thumbnail.jpg",
                        thumbnailByteCount: 1,
                        thumbnailSHA256: String(repeating: "b", count: 64)
                    )
                )
            }
            try harness.context.save()
            XCTAssertThrowsError(
                try harness.coordinator.prepareReview(
                    assetID: harness.asset.id,
                    selection: .couldNotVerify(
                        reasonKey: "capture_unavailable",
                        note: nil
                    )
                )
            ) {
                XCTAssertEqual($0 as? CheckRunnerCoordinatorError, .invalidCaptureState)
            }
            XCTAssertEqual(harness.draft.state, WorkflowState.draft.rawValue)
            XCTAssertNil(harness.draft.outcomeKey)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 0)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 0)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0)
            withExtendedLifetime(harness.session) {}
        }
    }

    @MainActor
    func testPostSaveCNVJournalRecoversAndReplayCreatesNoDuplicate() async throws {
        let applicationSupport = try makeTemporaryDirectory("recovery")
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let injection = FinalizationIntentStoreFailureInjection(
            failOnceAt: .intentPhaseWrite(.databaseCommitted)
        )
        let harness = try await makeHarness(
            applicationSupportURL: applicationSupport,
            acceptsWide: true,
            finalizationStoreFailureInjection: injection
        )
        let selection = CheckOutcomeSelection.couldNotVerify(
            reasonKey: "required_view_obstructed",
            note: nil
        )
        let identifiers = makeIdentifiers()
        let completedAt = Date(timeIntervalSince1970: 1_768_700_007)
        let snapshotAt = Date(timeIntervalSince1970: 1_768_700_008)
        let sourceApp = SourceAppSnapshotV1(build: "37", version: "1.0")
        do {
            _ = try await harness.coordinator.finalize(
                assetID: harness.asset.id,
                selection: selection,
                completedAt: completedAt,
                snapshotCreatedAt: snapshotAt,
                sourceApp: sourceApp,
                identifiers: identifiers
            )
            XCTFail("The injected post-save journal write must interrupt the caller")
        } catch {
            XCTAssertEqual(error as? CheckRunnerCoordinatorError, .finalizationFailed)
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0)
        XCTAssertTrue(fileManager.fileExists(atPath: intentURL(identifiers, appSupport: applicationSupport).path))

        let summary = try await FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        ).reconcile()
        XCTAssertEqual(summary.completedRecordIDs, [harness.draft.id])
        XCTAssertTrue(summary.recoveredDraftRecordIDs.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, appSupport: applicationSupport).path))
        injection.removeFailure()
        let replay = try await harness.coordinator.finalize(
            assetID: harness.asset.id,
            selection: selection,
            completedAt: completedAt,
            snapshotCreatedAt: snapshotAt,
            sourceApp: sourceApp,
            identifiers: identifiers
        )
        XCTAssertEqual(replay.reportID, identifiers.reportID)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0)
        withExtendedLifetime(harness.session) {}
    }

    @MainActor
    private func makeHarness(
        applicationSupportURL: URL,
        acceptsWide: Bool,
        finalizationStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil
    ) async throws -> CNVHarness {
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let site = Site(
            label: "North Campus",
            address: "10 Main",
            timeZoneID: "America/New_York"
        )
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
        let coordinator = CheckRunnerCoordinator(
            modelContext: context,
            signPack: pack,
            finalizationStoreFailureInjection: finalizationStoreFailureInjection
        )
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        let draft = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_768_700_000)
        )
        if acceptsWide {
            let candidate = try await coordinator.importCandidate(
                assetID: asset.id,
                sourceData: try makePNG(seed: 37),
                createdAt: Date(timeIntervalSince1970: 1_768_700_001)
            )
            _ = try await coordinator.accept(candidate: candidate, assetID: asset.id)
        }
        return CNVHarness(
            session: session,
            context: context,
            pack: pack,
            site: site,
            asset: asset,
            draft: draft,
            coordinator: coordinator
        )
    }

    @MainActor
    private func assertDraftOnly(
        _ harness: CNVHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(harness.draft.state, WorkflowState.draft.rawValue, file: file, line: line)
        XCTAssertNil(harness.draft.outcomeKey, file: file, line: line)
        XCTAssertNil(harness.draft.couldNotVerifyKey, file: file, line: line)
        XCTAssertNil(harness.draft.note, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 0, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 0, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0, file: file, line: line)
    }

    @MainActor
    private func assertCompletedAuthority(
        _ harness: CNVHarness,
        result: FinalizationResult,
        reasonKey: String,
        reasonDisplay: String,
        note: String?,
        evidenceCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(harness.draft.state, WorkflowState.completed.rawValue, file: file, line: line)
        XCTAssertEqual(harness.draft.outcomeKey, "could_not_verify", file: file, line: line)
        XCTAssertEqual(harness.draft.couldNotVerifyKey, reasonKey, file: file, line: line)
        XCTAssertEqual(harness.draft.couldNotVerifyDisplaySnapshot, reasonDisplay, file: file, line: line)
        XCTAssertEqual(harness.draft.couldNotVerifyRegistryVersion, "cnv.reason.en-US.v1", file: file, line: line)
        XCTAssertEqual(harness.draft.note, note, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), evidenceCount, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1, file: file, line: line)
        let packet = try XCTUnwrap(harness.context.fetch(FetchDescriptor<Packet>()).first, file: file, line: line)
        let report = try XCTUnwrap(harness.context.fetch(FetchDescriptor<Report>()).first, file: file, line: line)
        XCTAssertEqual(packet.id, result.packetID, file: file, line: line)
        XCTAssertEqual(packet.currentRecordID, harness.draft.id, file: file, line: line)
        XCTAssertTrue(packet.evaluationCounted, file: file, line: line)
        XCTAssertEqual(report.id, result.reportID, file: file, line: line)
        XCTAssertEqual(report.pdfState, ReportPDFState.pending.rawValue, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0, file: file, line: line)
    }

    @MainActor
    private func snapshot(
        for result: FinalizationResult,
        harness: CNVHarness
    ) throws -> ReportSnapshotV1 {
        let data = try Data(
            contentsOf: harness.session.generationRootURL
                .appendingPathComponent(result.snapshotRelativePath)
        )
        return try ReportSnapshotEncoderV1().decode(data)
    }

    private func makeIdentifiers() -> FinalizationIdentifiers {
        FinalizationIdentifiers(
            mutationID: UUID(),
            packetID: UUID(),
            stableRootID: UUID(),
            reportID: UUID(),
            issueID: nil
        )
    }

    private func intentURL(_ identifiers: FinalizationIdentifiers, appSupport: URL) -> URL {
        appSupport.appendingPathComponent(
            "FieldEvidenceOperations/finalization/\(identifiers.mutationID.uuidString.lowercased()).json"
        )
    }

    private func makeTemporaryDirectory(_ label: String) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S3_7CouldNotVerifyTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makePNG(seed: UInt8) throws -> Data {
        let width = 48
        let height = 32
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
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw CNVFixtureError.couldNotCreateImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CNVFixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CNVFixtureError.couldNotCreateImage
        }
        return output as Data
    }
}

@MainActor
private struct CNVHarness {
    let session: StoreGenerationSession
    let context: ModelContext
    let pack: SignPack
    let site: Site
    let asset: Asset
    let draft: WorkflowRecord
    let coordinator: CheckRunnerCoordinator
}

private enum CNVFixtureError: Error {
    case couldNotCreateImage
}

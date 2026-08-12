import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S3_3FinalizationTests: XCTestCase {
    private let fileManager = FileManager.default

    func testCanonicalGoldenFixtureRoundTripsAndMatchesPinnedSHA256() throws {
        let fixture = try fixtureData(withExtension: "json")
        let expectedSHA256 = try XCTUnwrap(
            String(data: fixtureData(withExtension: "sha256"), encoding: .utf8)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = try ReportSnapshotEncoderV1().encode(goldenSnapshot())

        XCTAssertFalse(fixture.last == 0x0a)
        XCTAssertEqual(encoded.data, fixture)
        XCTAssertEqual(encoded.sha256, expectedSHA256)
        XCTAssertEqual(sha256(fixture), expectedSHA256)
        XCTAssertEqual(
            try ReportSnapshotEncoderV1().decode(fixture),
            goldenSnapshot()
        )
    }

    @MainActor
    func testNoVisibleIssuePersistsOneClosedFinalizationAndOrdersDiagnostics() async throws {
        let applicationSupportURL = try makeTemporaryDirectory(testName: "NoVisible")
        defer { try? fileManager.removeItem(at: applicationSupportURL) }
        let diagnosticsStore = DiagnosticsStore(
            applicationSupportURL: applicationSupportURL
        )
        let identifiers = FinalizationIdentifiers(
            mutationID: uuid("20000000-0000-0000-0000-000000000001"),
            packetID: uuid("20000000-0000-0000-0000-000000000002"),
            stableRootID: uuid("20000000-0000-0000-0000-000000000003"),
            reportID: uuid("20000000-0000-0000-0000-000000000004"),
            issueID: nil
        )
        let completedAt = Date(timeIntervalSince1970: 1_768_420_926)
        let snapshotCreatedAt = Date(timeIntervalSince1970: 1_768_420_927)
        var expectedDraftID: UUID!
        var expectedGenerationRoot: URL!

        do {
            let harness = try await makeReadyHarness(
                applicationSupportURL: applicationSupportURL,
                diagnosticsStore: diagnosticsStore
            )
            expectedDraftID = harness.draft.id
            expectedGenerationRoot = harness.session.generationRootURL

            let before = await diagnosticsStore.snapshot()
            XCTAssertEqual(before.reportSaved, 0)
            XCTAssertEqual(before.onboardingCompleted, 0)

            let result = try await harness.coordinator.finalize(
                assetID: harness.asset.id,
                selection: .noVisibleIssue,
                completedAt: completedAt,
                snapshotCreatedAt: snapshotCreatedAt,
                sourceApp: SourceAppSnapshotV1(build: "33", version: "1.0"),
                identifiers: identifiers
            )

            XCTAssertEqual(result.recordID, harness.draft.id)
            XCTAssertEqual(result.packetID, identifiers.packetID)
            XCTAssertEqual(result.stableRootID, identifiers.stableRootID)
            XCTAssertEqual(result.reportID, identifiers.reportID)
            XCTAssertNil(result.issueID)
            XCTAssertEqual(
                result.snapshotRelativePath,
                "snapshots/\(identifiers.reportID.uuidString.lowercased()).json"
            )

            let records = try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
            let packets = try harness.context.fetch(FetchDescriptor<Packet>())
            let reports = try harness.context.fetch(FetchDescriptor<Report>())
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(packets.count, 1)
            XCTAssertEqual(reports.count, 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0)

            let record = try XCTUnwrap(records.first)
            XCTAssertEqual(record.state, WorkflowState.completed.rawValue)
            XCTAssertNil(record.draftStepKey)
            XCTAssertEqual(record.completedAt, completedAt)
            XCTAssertEqual(record.outcomeKey, "no_visible_issue")
            XCTAssertEqual(record.packetID, identifiers.packetID)
            XCTAssertEqual(record.finalizationMutationID, identifiers.mutationID)

            let packet = try XCTUnwrap(packets.first)
            XCTAssertEqual(packet.currentRecordID, record.id)
            XCTAssertEqual(packet.stableRootID, identifiers.stableRootID)
            XCTAssertTrue(packet.evaluationCounted)

            let report = try XCTUnwrap(reports.first)
            XCTAssertEqual(report.sourceRecordID, record.id)
            XCTAssertEqual(report.packetID, packet.id)
            XCTAssertEqual(report.snapshotSHA256, result.snapshotSHA256)
            XCTAssertEqual(report.pdfState, ReportPDFState.pending.rawValue)
            XCTAssertNil(report.pdfRelativePath)
            XCTAssertNil(report.pdfSHA256)

            let snapshotURL = harness.session.generationRootURL.appendingPathComponent(
                result.snapshotRelativePath
            )
            let snapshotData = try Data(contentsOf: snapshotURL)
            XCTAssertEqual(sha256(snapshotData), report.snapshotSHA256)
            let snapshot = try ReportSnapshotEncoderV1().decode(snapshotData)
            XCTAssertEqual(snapshot.reportID, report.id)
            XCTAssertEqual(snapshot.sourceRecordID, record.id)
            XCTAssertEqual(snapshot.evidenceSourceRecordID, record.id)
            XCTAssertEqual(snapshot.packetID, packet.id)
            XCTAssertEqual(snapshot.stableRootID, packet.stableRootID)
            XCTAssertEqual(snapshot.outcome, "no_visible_issue")
            XCTAssertEqual(snapshot.evidence.count, 2)
            XCTAssertTrue(snapshot.history.isEmpty)
            XCTAssertTrue(snapshot.issues.isEmpty)

            assertJournalCleaned(
                applicationSupportURL: applicationSupportURL,
                generationRootURL: harness.session.generationRootURL,
                identifiers: identifiers
            )

            let afterFinalization = await diagnosticsStore.snapshot()
            XCTAssertEqual(afterFinalization.reportSaved, 1)
            XCTAssertEqual(afterFinalization.onboardingCompleted, 0)
            await harness.coordinator.valueReceiptDidPresent()
            await harness.coordinator.valueReceiptDidPresent()
            let afterReceipt = await diagnosticsStore.snapshot()
            XCTAssertEqual(afterReceipt.reportSaved, 1)
            XCTAssertEqual(afterReceipt.onboardingCompleted, 1)
            withExtendedLifetime(harness.session) {}
        }

        do {
            let reopenedSession = try StoreGenerationFactory(
                applicationSupportURL: applicationSupportURL
            ).openOrBootstrapCurrent()
            let context = reopenedSession.modelContext
            let record = try XCTUnwrap(
                context.fetch(FetchDescriptor<WorkflowRecord>()).first
            )
            let report = try XCTUnwrap(
                context.fetch(FetchDescriptor<Report>()).first
            )
            XCTAssertEqual(record.id, expectedDraftID)
            XCTAssertEqual(record.state, WorkflowState.completed.rawValue)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Packet>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Issue>()), 0)
            XCTAssertEqual(reopenedSession.generationRootURL, expectedGenerationRoot)
            let snapshotData = try Data(
                contentsOf: reopenedSession.generationRootURL.appendingPathComponent(
                    report.snapshotRelativePath
                )
            )
            XCTAssertEqual(sha256(snapshotData), report.snapshotSHA256)
            _ = try ReportSnapshotEncoderV1().decode(snapshotData)
            withExtendedLifetime(reopenedSession) {}
        }
    }

    @MainActor
    func testVisibleIssueRejectsInvalidLabelsAndPersistsExactlyOneValidIssue() async throws {
        let applicationSupportURL = try makeTemporaryDirectory(testName: "Visible")
        defer { try? fileManager.removeItem(at: applicationSupportURL) }
        let harness = try await makeReadyHarness(
            applicationSupportURL: applicationSupportURL,
            diagnosticsStore: nil
        )

        XCTAssertThrowsError(
            try harness.coordinator.prepareReview(
                assetID: harness.asset.id,
                selection: .visibleIssue(labelKey: "   ")
            )
        ) {
            XCTAssertEqual(
                $0 as? CheckRunnerCoordinatorError,
                .issueLabelRequired
            )
        }
        XCTAssertThrowsError(
            try harness.coordinator.prepareReview(
                assetID: harness.asset.id,
                selection: .visibleIssue(labelKey: "not_in_the_pack")
            )
        ) {
            XCTAssertEqual(
                $0 as? CheckRunnerCoordinatorError,
                .issueLabelInvalid
            )
        }

        let labelKey = "dark_section"
        let review = try harness.coordinator.prepareReview(
            assetID: harness.asset.id,
            selection: .visibleIssue(labelKey: labelKey)
        )
        XCTAssertEqual(review.outcomeKey, "visible_issue")
        XCTAssertEqual(review.outcomeDisplay, "Visible issue")
        XCTAssertEqual(review.issueLabelDisplay, "Section appears dark")

        let identifiers = FinalizationIdentifiers(
            mutationID: uuid("30000000-0000-0000-0000-000000000001"),
            packetID: uuid("30000000-0000-0000-0000-000000000002"),
            stableRootID: uuid("30000000-0000-0000-0000-000000000003"),
            reportID: uuid("30000000-0000-0000-0000-000000000004"),
            issueID: uuid("30000000-0000-0000-0000-000000000005")
        )
        let result = try await harness.coordinator.finalize(
            assetID: harness.asset.id,
            selection: .visibleIssue(labelKey: labelKey),
            completedAt: Date(timeIntervalSince1970: 1_768_420_926),
            snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_420_927),
            sourceApp: SourceAppSnapshotV1(build: "33", version: "1.0"),
            identifiers: identifiers
        )

        XCTAssertEqual(result.issueID, identifiers.issueID)
        let issues = try harness.context.fetch(FetchDescriptor<Issue>())
        XCTAssertEqual(issues.count, 1)
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.id, identifiers.issueID)
        XCTAssertEqual(issue.assetID, harness.asset.id)
        XCTAssertEqual(issue.openedByRecordID, harness.draft.id)
        XCTAssertEqual(issue.labelKey, labelKey)
        XCTAssertEqual(issue.labelDisplaySnapshot, "Section appears dark")
        XCTAssertEqual(issue.status, IssueStatus.open.rawValue)
        XCTAssertNil(issue.resolvedByRecordID)

        let record = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<WorkflowRecord>()).first
        )
        XCTAssertEqual(record.issueID, issue.id)
        XCTAssertEqual(record.outcomeKey, "visible_issue")
        let report = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<Report>()).first
        )
        let snapshotData = try Data(
            contentsOf: harness.session.generationRootURL.appendingPathComponent(
                report.snapshotRelativePath
            )
        )
        let snapshot = try ReportSnapshotEncoderV1().decode(snapshotData)
        XCTAssertEqual(snapshot.issues.count, 1)
        XCTAssertEqual(snapshot.issues.first?.issueID, issue.id)
        XCTAssertEqual(snapshot.issues.first?.key, labelKey)
        XCTAssertEqual(snapshot.issues.first?.status, IssueStatus.open.rawValue)
        assertJournalCleaned(
            applicationSupportURL: applicationSupportURL,
            generationRootURL: harness.session.generationRootURL,
            identifiers: identifiers
        )
        withExtendedLifetime(harness.session) {}
    }

    @MainActor
    private func makeReadyHarness(
        applicationSupportURL: URL,
        diagnosticsStore: DiagnosticsStore?
    ) async throws -> ReadyHarness {
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
            diagnosticsStore: diagnosticsStore
        )
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        let draft = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_768_420_923)
        )
        let wide = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: 31),
            createdAt: Date(timeIntervalSince1970: 1_768_420_924)
        )
        _ = try await coordinator.accept(candidate: wide, assetID: asset.id)
        let close = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: 79),
            createdAt: Date(timeIntervalSince1970: 1_768_420_925)
        )
        _ = try await coordinator.accept(candidate: close, assetID: asset.id)
        XCTAssertEqual(draft.draftStepKey, WorkflowDraftStep.outcome.rawValue)
        return ReadyHarness(
            session: session,
            context: context,
            coordinator: coordinator,
            asset: asset,
            draft: draft
        )
    }

    private func goldenSnapshot() -> ReportSnapshotV1 {
        let recordID = uuid("10000000-0000-0000-0000-000000000001")
        return ReportSnapshotV1(
            acknowledgements: [
                AcknowledgementSnapshotV1(
                    accepted: true,
                    copy: "It is dark enough to observe the sign's visible illumination.",
                    key: "after_dark",
                    version: "preflight.ack.en-US.v1"
                ),
                AcknowledgementSnapshotV1(
                    accepted: true,
                    copy: "I am in a safe, authorized position to take these photos.",
                    key: "safe_authorized_position",
                    version: "preflight.ack.en-US.v1"
                ),
            ],
            asset: AssetSnapshotV1(label: "Monument Sign"),
            couldNotVerify: nil,
            disclaimer: "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification.",
            display: DisplaySnapshotV1(
                assetSingular: "sign",
                checkSingular: "check",
                issueSingular: "visible issue",
                outcome: "No visible issue",
                stage: "Check"
            ),
            evidence: [
                EvidenceSnapshotV1(
                    byteCount: 101,
                    createdAt: Date(timeIntervalSince1970: 1_768_420_924),
                    evidenceID: uuid("10000000-0000-0000-0000-000000000005"),
                    mimeType: "image/jpeg",
                    purposeDisplay: "Wide view",
                    purposeKey: "wide_context",
                    recordID: recordID,
                    relativePath: "evidence/10000000-0000-0000-0000-000000000005/original.jpg",
                    sha256: String(repeating: "a", count: 64),
                    thumbnailByteCount: 51,
                    thumbnailRelativePath: "evidence/10000000-0000-0000-0000-000000000005/thumbnail.jpg",
                    thumbnailSHA256: String(repeating: "b", count: 64)
                ),
                EvidenceSnapshotV1(
                    byteCount: 102,
                    createdAt: Date(timeIntervalSince1970: 1_768_420_925),
                    evidenceID: uuid("10000000-0000-0000-0000-000000000006"),
                    mimeType: "image/jpeg",
                    purposeDisplay: "Close view",
                    purposeKey: "close_detail",
                    recordID: recordID,
                    relativePath: "evidence/10000000-0000-0000-0000-000000000006/original.jpg",
                    sha256: String(repeating: "c", count: 64),
                    thumbnailByteCount: 52,
                    thumbnailRelativePath: "evidence/10000000-0000-0000-0000-000000000006/thumbnail.jpg",
                    thumbnailSHA256: String(repeating: "d", count: 64)
                ),
            ],
            evidenceSourceRecordID: recordID,
            history: [],
            issues: [],
            note: nil,
            outcome: "no_visible_issue",
            pack: PackSnapshotV1(
                contentVersion: 1,
                id: "field.evidence.illuminated_sign.v1",
                schemaVersion: 1
            ),
            packetID: uuid("10000000-0000-0000-0000-000000000002"),
            pdfTemplate: PDFTemplateReferenceV1(
                id: "field.evidence.pdf.worklight.v1",
                version: 1
            ),
            reportID: uuid("10000000-0000-0000-0000-000000000003"),
            site: SiteSnapshotV1(address: "10 Main", label: "North Campus"),
            snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_420_926),
            snapshotSchemaVersion: 1,
            sourceApp: SourceAppSnapshotV1(build: "33", version: "1.0"),
            sourceRecordID: recordID,
            stableRootID: uuid("10000000-0000-0000-0000-000000000004"),
            stage: "check",
            timeContext: TimeContextSnapshotV1(
                localDate: "2026-01-14",
                localTime: "15:02:03",
                observedAtUTC: Date(timeIntervalSince1970: 1_768_420_923),
                timeZoneID: "America/New_York",
                utcOffsetMinutes: -300
            )
        )
    }

    private func assertJournalCleaned(
        applicationSupportURL: URL,
        generationRootURL: URL,
        identifiers: FinalizationIdentifiers,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mutation = identifiers.mutationID.uuidString.lowercased()
        let report = identifiers.reportID.uuidString.lowercased()
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: applicationSupportURL.appendingPathComponent(
                    "FieldEvidenceOperations/finalization/\(mutation).json"
                ).path
            ),
            file: file,
            line: line
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: generationRootURL.appendingPathComponent(
                    ".staging/snapshots/\(report).json"
                ).path
            ),
            file: file,
            line: line
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: generationRootURL.appendingPathComponent(
                    "snapshots/\(report).json"
                ).path
            ),
            file: file,
            line: line
        )
    }

    private func fixtureData(withExtension fileExtension: String) throws -> Data {
        let bundle = Bundle(for: S3_3FinalizationTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "S3_3ReportSnapshotV1",
                withExtension: fileExtension,
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "S3_3ReportSnapshotV1",
                withExtension: fileExtension
            )
        )
        return try Data(contentsOf: url)
    }

    private func makeTemporaryDirectory(testName: String) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S3_3FinalizationTests-\(testName)-\(UUID().uuidString)",
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
            throw TestFixtureError.couldNotCreateImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw TestFixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestFixtureError.couldNotCreateImage
        }
        return output as Data
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private struct ReadyHarness {
    let session: StoreGenerationSession
    let context: ModelContext
    let coordinator: CheckRunnerCoordinator
    let asset: Asset
    let draft: WorkflowRecord
}

private enum TestFixtureError: Error {
    case couldNotCreateImage
}

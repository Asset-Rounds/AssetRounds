import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S8_1SecondPackZeroForkTests: XCTestCase {
    private let fileManager = FileManager.default

    func testClosedLoaderAcceptsExactTestFixtureAndRejectsUnknownAuthority() throws {
        let data = try fixtureData()
        XCTAssertEqual(
            lowercaseSHA256(data),
            "6f72c39fa9909ccfec087e33cb82a456b1e7b083745601cc6ea1bb05f277f7c8"
        )

        let pack = try fixturePack(from: data)
        XCTAssertEqual(pack.packID, "test.field.evidence.exterior_light.v1")
        XCTAssertEqual(pack.nouns.asset.singular, "exterior light")
        XCTAssertEqual(pack.nouns.check.singular, "lighting survey")
        XCTAssertEqual(pack.nouns.issue.singular, "observed lighting condition")
        XCTAssertEqual(
            pack.evidencePurposes.map(\.display),
            ["Exterior area context", "Luminaire detail", "Lighting work photo"]
        )
        XCTAssertNotEqual(pack, .illuminatedSignV1)
        XCTAssertEqual(SignPackLoader.loadBundled(), .available(.illuminatedSignV1))

        var unknownObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        unknownObject["unexpectedAuthority"] = true
        let unknownData = try JSONSerialization.data(
            withJSONObject: unknownObject,
            options: [.sortedKeys]
        )
        XCTAssertEqual(SignPackLoader.load(data: unknownData), .unavailable)

        var wrongRegistryObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var labels = try XCTUnwrap(
            wrongRegistryObject["issueLabels"] as? [[String: Any]]
        )
        labels[0]["key"] = "unknown_condition"
        wrongRegistryObject["issueLabels"] = labels
        let wrongRegistryData = try JSONSerialization.data(
            withJSONObject: wrongRegistryObject,
            options: [.sortedKeys]
        )
        XCTAssertEqual(SignPackLoader.load(data: wrongRegistryData), .unavailable)

        XCTAssertNil(
            Bundle.main.url(
                forResource: "S8_1ExteriorLightPackV1",
                withExtension: "json"
            )
        )
        XCTAssertNil(
            Bundle.main.url(
                forResource: "S8_1ExteriorLightPackV1",
                withExtension: "json",
                subdirectory: "Fixtures"
            )
        )
    }

    @MainActor
    func testFixtureFlowsThroughCurrentHistoryPDFAndClearsCompletedRecheckAttempt() async throws {
        let applicationSupportURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: applicationSupportURL) }

        let pack = try fixturePack(from: fixtureData())
        let session = try StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL
        ).openOrBootstrapCurrent()
        let context = session.modelContext
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let site = Site(
            label: "East Campus",
            address: "40 Service Road",
            timeZoneID: "America/New_York",
            createdAt: observedAt.addingTimeInterval(-120)
        )
        let asset = Asset(
            siteID: site.id,
            packID: pack.packID,
            packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            label: "Parking Lot East",
            createdAt: observedAt.addingTimeInterval(-100)
        )
        context.insert(site)
        context.insert(asset)
        try context.save()

        let runner = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        runner.configureCapture(generationRootURL: session.generationRootURL)
        _ = try runner.beginCheck(
            assetID: asset.id,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: observedAt
        )
        try await capturePair(
            runner: runner,
            assetID: asset.id,
            firstCreatedAt: observedAt.addingTimeInterval(10),
            seeds: (11, 22)
        )
        let openingIdentifiers = FinalizationIdentifiers(
            mutationID: UUID(),
            packetID: UUID(),
            stableRootID: UUID(),
            reportID: UUID(),
            issueID: UUID()
        )
        let openingCompletedAt = observedAt.addingTimeInterval(60)
        let opening = try await runner.finalize(
            assetID: asset.id,
            selection: .visibleIssue(labelKey: "dark_section"),
            completedAt: openingCompletedAt,
            snapshotCreatedAt: openingCompletedAt,
            sourceApp: SourceAppSnapshotV1(build: "81", version: "1.0"),
            identifiers: openingIdentifiers
        )
        let issueID = try XCTUnwrap(opening.issueID)
        XCTAssertEqual(issueID, openingIdentifiers.issueID)

        let workCoordinator = try WorkCoordinator(
            modelContext: context,
            signPack: pack,
            generationRootURL: session.generationRootURL,
            checkRunnerCoordinator: runner
        )
        let workDraft = try workCoordinator.beginWork(issueID: issueID)
        let workCompletedAt = workDraft.startedAt.addingTimeInterval(30)
        _ = try await workCoordinator.saveWork(
            draftID: workDraft.recordID,
            submission: WorkSaveSubmission(
                performedLocalDate: "2026-08-15",
                description: "Replaced the exterior-light driver and verified steady output.",
                note: "Exterior-light work completed.",
                photos: [],
                completedAt: workCompletedAt
            ),
            identifiers: WorkIdentifiers(mutationID: UUID(), evidenceID: nil)
        )

        try runner.requestRecheck(assetID: asset.id, issueID: issueID)
        let recheckObservedAt = workCompletedAt.addingTimeInterval(60)
        _ = try runner.beginCheck(
            assetID: asset.id,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: recheckObservedAt
        )
        try await capturePair(
            runner: runner,
            assetID: asset.id,
            firstCreatedAt: recheckObservedAt.addingTimeInterval(10),
            seeds: (33, 44)
        )
        let recheckIdentifiers = FinalizationIdentifiers(
            mutationID: UUID(),
            packetID: UUID(),
            stableRootID: UUID(),
            reportID: UUID(),
            issueID: issueID
        )
        let recheckCompletedAt = recheckObservedAt.addingTimeInterval(60)
        let sourceApp = SourceAppSnapshotV1(build: "81", version: "1.0")
        let recheck = try await runner.finalize(
            assetID: asset.id,
            selection: .resolved(note: "Exterior-light output remained steady."),
            completedAt: recheckCompletedAt,
            snapshotCreatedAt: recheckCompletedAt,
            sourceApp: sourceApp,
            identifiers: recheckIdentifiers
        )
        let replay = try await runner.finalize(
            assetID: asset.id,
            selection: .resolved(note: "Exterior-light output remained steady."),
            completedAt: recheckCompletedAt,
            snapshotCreatedAt: recheckCompletedAt,
            sourceApp: sourceApp,
            identifiers: recheckIdentifiers
        )
        XCTAssertEqual(replay, recheck)

        let report = try onlyReport(id: recheck.reportID, context: context)
        let validated = try SnapshotValidatorV1(
            modelContext: context,
            generationRootURL: session.generationRootURL,
            signPack: pack
        ).validate(report: report)
        let snapshot = validated.snapshot
        XCTAssertEqual(snapshot.pack.id, pack.packID)
        XCTAssertEqual(snapshot.pack.schemaVersion, 1)
        XCTAssertEqual(snapshot.pack.contentVersion, 1)
        XCTAssertEqual(snapshot.display.assetSingular, "exterior light")
        XCTAssertEqual(snapshot.display.checkSingular, "lighting survey")
        XCTAssertEqual(snapshot.display.issueSingular, "observed lighting condition")
        XCTAssertEqual(snapshot.display.stage, "Exterior-light follow-up")
        XCTAssertEqual(snapshot.display.outcome, "Exterior-light condition resolved")
        XCTAssertEqual(
            snapshot.acknowledgements.map(\.copy),
            pack.acknowledgements.map(\.copy)
        )
        XCTAssertEqual(snapshot.disclaimer, pack.disclaimer)
        XCTAssertTrue(
            snapshot.evidence.allSatisfy { evidence in
                pack.evidencePurposes.first { $0.key == evidence.purposeKey }?.display
                    == evidence.purposeDisplay
            }
        )
        XCTAssertEqual(snapshot.issues.map(\.display), ["Exterior lamp section is dark"])
        XCTAssertEqual(snapshot.history.map(\.recordID), [opening.recordID, workDraft.recordID])
        XCTAssertEqual(snapshot.history[0].stageDisplay, "Exterior-light survey")
        XCTAssertEqual(
            snapshot.history[0].outcomeDisplay,
            "Exterior-light condition observed"
        )
        XCTAssertEqual(snapshot.history[1].stageDisplay, "Work")
        XCTAssertEqual(snapshot.history[1].outcomeDisplay, "Work recorded")

        var noLongerConsultedRegistry = pack
        noLongerConsultedRegistry = .illuminatedSignV1
        XCTAssertNotEqual(noLongerConsultedRegistry.packID, snapshot.pack.id)
        let rendered = try WorklightPDFRendererV1().render(validated)
        let rerendered = try WorklightPDFRendererV1().render(validated)
        XCTAssertEqual(rendered.data, rerendered.data)
        XCTAssertEqual(rendered.sha256, rerendered.sha256)
        XCTAssertGreaterThan(rendered.pageCount, 0)
        let pdfText = normalizedWhitespace(
            rendered.inspection.pages
                .flatMap { $0 }
                .compactMap(\.text)
                .joined(separator: "\n")
        )
        for expected in [
            "Lighting survey report",
            "Exterior Light: Parking Lot East",
            "Exterior area context",
            "Luminaire detail",
            "Stage: Exterior-light follow-up",
            "Outcome: Exterior-light condition resolved",
            "Observed Lighting Condition",
            "Exterior lamp section is dark",
            "Exterior-light survey — Exterior-light condition observed",
            pack.disclaimer,
        ] {
            XCTAssertTrue(
                pdfText.contains(normalizedWhitespace(expected)),
                "Missing PDF copy: \(expected)"
            )
        }
        for forbidden in ["Wide view", "Close view", "Section appears dark"] {
            XCTAssertFalse(
                pdfText.contains(normalizedWhitespace(forbidden)),
                "Production fallback leaked: \(forbidden)"
            )
        }

        let freshObservedAt = recheckCompletedAt.addingTimeInterval(120)
        _ = try runner.beginCheck(
            assetID: asset.id,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: freshObservedAt
        )
        try await capturePair(
            runner: runner,
            assetID: asset.id,
            firstCreatedAt: freshObservedAt.addingTimeInterval(10),
            seeds: (55, 66)
        )
        let freshIdentifiers = FinalizationIdentifiers(
            mutationID: UUID(),
            packetID: UUID(),
            stableRootID: UUID(),
            reportID: UUID(),
            issueID: nil
        )
        let fresh = try await runner.finalize(
            assetID: asset.id,
            selection: .noVisibleIssue,
            completedAt: freshObservedAt.addingTimeInterval(60),
            snapshotCreatedAt: freshObservedAt.addingTimeInterval(60),
            sourceApp: sourceApp,
            identifiers: freshIdentifiers
        )
        XCTAssertNil(fresh.issueID)
        let freshRecord = try onlyRecord(id: fresh.recordID, context: context)
        XCTAssertEqual(freshRecord.stage, WorkflowStage.check.rawValue)
        XCTAssertEqual(freshRecord.outcomeKey, "no_visible_issue")
        withExtendedLifetime(session) {}
    }

    @MainActor
    private func capturePair(
        runner: CheckRunnerCoordinator,
        assetID: UUID,
        firstCreatedAt: Date,
        seeds: (UInt8, UInt8)
    ) async throws {
        let wide = try await runner.importCandidate(
            assetID: assetID,
            sourceData: try makePNG(seed: seeds.0),
            createdAt: firstCreatedAt
        )
        _ = try await runner.accept(candidate: wide, assetID: assetID)
        let close = try await runner.importCandidate(
            assetID: assetID,
            sourceData: try makePNG(seed: seeds.1),
            createdAt: firstCreatedAt.addingTimeInterval(10)
        )
        _ = try await runner.accept(candidate: close, assetID: assetID)
    }

    private func fixturePack(from data: Data) throws -> SignPack {
        guard case let .available(pack) = SignPackLoader.load(data: data) else {
            XCTFail("The exact exterior-light fixture was unavailable")
            throw FixtureError.invalidFixture
        }
        return pack
    }

    private func fixtureData() throws -> Data {
        let bundle = Bundle(for: S8_1SecondPackZeroForkTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "S8_1ExteriorLightPackV1",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "S8_1ExteriorLightPackV1",
                withExtension: "json"
            )
        )
        return try Data(contentsOf: url)
    }

    @MainActor
    private func onlyReport(id: UUID, context: ModelContext) throws -> Report {
        let values = try context.fetch(FetchDescriptor<Report>()).filter { $0.id == id }
        XCTAssertEqual(values.count, 1)
        return try XCTUnwrap(values.first)
    }

    @MainActor
    private func onlyRecord(id: UUID, context: ModelContext) throws -> WorkflowRecord {
        let values = try context.fetch(FetchDescriptor<WorkflowRecord>()).filter { $0.id == id }
        XCTAssertEqual(values.count, 1)
        return try XCTUnwrap(values.first)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S8_1SecondPackZeroForkTests-\(UUID().uuidString)",
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
            throw FixtureError.invalidFixture
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.invalidFixture
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.invalidFixture
        }
        return output as Data
    }

    private func lowercaseSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private enum FixtureError: Error {
    case invalidFixture
}

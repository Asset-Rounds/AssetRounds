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
        let fixture = try await WorkCanonicalCurrentRouteFixtureV1.make(
            applicationSupportURL: applicationSupportURL,
            pack: pack,
            workPhotoData: nil,
            siteLabel: "East Campus",
            siteAddress: "40 Service Road",
            assetLabel: "Parking Lot East",
            workPerformedLocalDate: "2026-08-15",
            workDescription: "Replaced the exterior-light driver and verified steady output.",
            workNote: "Exterior-light work completed."
        )
        defer { try? fixture.close() }
        let session = fixture.session
        let context = fixture.context
        let runner = fixture.openingRunner
        let assetID = fixture.assetID
        let issueID = fixture.issueID
        let openingRecordID = fixture.openingRecordID
        let workRecordID = fixture.workRecordID
        let workCompletedAt = fixture.workSubmission.completedAt
        XCTAssertTrue(fixture.workSubmission.photos.isEmpty)
        XCTAssertNil(fixture.workIdentifiers.evidenceID)
        XCTAssertEqual(fixture.savedWork.status, .recheckDue)
        XCTAssertEqual(fixture.savedWork.records.map(\.id), [workRecordID])
        let workMutationID = try MutationIDV1(rawValue: fixture.workIdentifiers.mutationID)
        let workEnvelope = try XCTUnwrap(
            fixture.lifecycleDependencies.writer.workEnvelope(mutationID: workMutationID)
        )
        let workReceipt = try XCTUnwrap(
            fixture.lifecycleDependencies.writer.workCommitReceipt(envelope: workEnvelope)
        )
        guard case let .recordWork(workMutation) = workEnvelope.command,
              let writerAuthority = workMutation.writerAuthority else {
            XCTFail("Expected authority-bearing alternate-package Work envelope")
            throw FixtureError.invalidFixture
        }
        try writerAuthority.validate(envelope: workEnvelope)
        try workReceipt.validate()
        XCTAssertEqual(workReceipt.mutationID, workMutationID)
        XCTAssertEqual(Set(try workReceipt.postImages.map { try $0.identity }), Set([
            try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: workRecordID),
            try WorkspaceEntityIdentityV1(kind: .issue, id: issueID),
        ]))
        XCTAssertEqual(
            try writerAuthority.affectedIdentities,
            try workReceipt.postImages.map { try $0.identity }
                .sorted { $0.stableKey < $1.stableKey }
        )
        for postImage in workReceipt.postImages {
            let identity = try postImage.identity
            XCTAssertEqual(
                workReceipt.resultingRevision.entityRevisions.first {
                    $0.identity == identity
                }?.revision,
                postImage.revision
            )
        }
        XCTAssertEqual(
            try MutationJournalStoreV1(
                modelContext: context,
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                allowStateBootstrap: false
            ).receipt(mutationID: workMutationID),
            workReceipt
        )

        try runner.requestRecheck(assetID: assetID, issueID: issueID)
        let recheckObservedAt = workCompletedAt.addingTimeInterval(60)
        _ = try runner.beginCheck(
            assetID: assetID,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: recheckObservedAt
        )
        try await capturePair(
            runner: runner,
            assetID: assetID,
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
            assetID: assetID,
            selection: .resolved(note: "Exterior-light output remained steady."),
            completedAt: recheckCompletedAt,
            snapshotCreatedAt: recheckCompletedAt,
            sourceApp: sourceApp,
            identifiers: recheckIdentifiers
        )
        let replay = try await runner.finalize(
            assetID: assetID,
            selection: .resolved(note: "Exterior-light output remained steady."),
            completedAt: recheckCompletedAt,
            snapshotCreatedAt: recheckCompletedAt,
            sourceApp: sourceApp,
            identifiers: recheckIdentifiers
        )
        XCTAssertEqual(replay, recheck)
        let workReplay = try await fixture.workCoordinator.saveWork(
            draftID: workRecordID,
            submission: fixture.workSubmission,
            identifiers: fixture.workIdentifiers
        )
        XCTAssertEqual(workReplay.status, .resolved)
        XCTAssertEqual(workReplay.records.map(\.id), [workRecordID])
        XCTAssertEqual(
            try fixture.lifecycleDependencies.writer.workCommitReceipt(
                envelope: workEnvelope
            ),
            workReceipt
        )

        let report = try onlyReport(id: recheck.reportID, context: context)
        let validated = try SnapshotValidatorV1(
            modelContext: context,
            generationRootURL: session.generationRootURL,
            lifecycleProfile: fixture.lifecycleProfile,
            lifecycleDependencies: fixture.lifecycleDependencies
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
        XCTAssertEqual(snapshot.history.map(\.recordID), [openingRecordID, workRecordID])
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
            "Exterior light: Parking Lot East",
            "Exterior area context",
            "Luminaire detail",
            "Stage: Exterior-light follow-up",
            "Outcome: Exterior-light condition resolved",
            "Observed lighting condition",
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
            assetID: assetID,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: freshObservedAt
        )
        try await capturePair(
            runner: runner,
            assetID: assetID,
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
            assetID: assetID,
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
        value.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .replacingOccurrences(of: "- ", with: "-")
    }
}

private enum FixtureError: Error {
    case invalidFixture
}

extension S8_1SecondPackZeroForkTests {
    func testV23P03C18PromotionAuthorityStaysLocalAndSingleWriter() throws {
        XCTAssertEqual(
            PackagePromotionAuthorityV1.explicitLocalOperator.rawValue,
            "EXPLICIT_LOCAL_OPERATOR"
        )
        XCTAssertEqual(PackageEvolutionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertTrue(PackageEvolutionLifecycleV1.persistent)
    }
}

extension S8_1SecondPackZeroForkTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension S8_1SecondPackZeroForkTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferencePackLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertFalse(FieldReferencePackLifecycleV1.currentProjectionPersistent)
        XCTAssertFalse(FieldReferencePackLifecycleV1.runtimeFetchingAllowed)
    }
}
extension S8_1SecondPackZeroForkTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindV1.allCases.count, 5)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.quarantinePersistence, "DERIVED_ONLY")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}
extension S8_1SecondPackZeroForkTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift_Tests: XCTestCase {
    func testC47S81SecondPackZeroForkTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S8_1SecondPackZeroForkTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(.survey), .exactV1)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.v1(.survey), .survey)
    }
}

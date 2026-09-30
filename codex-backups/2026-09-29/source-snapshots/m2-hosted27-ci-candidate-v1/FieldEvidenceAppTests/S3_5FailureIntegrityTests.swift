import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S3_5FailureIntegrityTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testUnavailableAndInsufficientCapacityWriteNothingThenRetryOnce() async throws {
        for fault in CapacityFault.allCases {
            let applicationSupport = try makeTemporaryDirectory(label: "capacity-\(fault)")
            defer { try? fileManager.removeItem(at: applicationSupport) }
            var shouldFail = true
            let capacity = StoragePreflightService { _ in
                if shouldFail {
                    shouldFail = false
                    switch fault {
                    case .unavailable:
                        return nil
                    case .insufficient:
                        return StoragePreflightService.evidenceAcceptanceRequiredBytes - 1
                    }
                }
                return StoragePreflightService.evidenceAcceptanceRequiredBytes
            }
            let harness = try makeDraftHarness(
                applicationSupportURL: applicationSupport,
                storagePreflight: capacity
            )

            do {
                _ = try await harness.coordinator.importCandidate(
                    assetID: harness.asset.id,
                    sourceData: try makePNG(seed: 11),
                    createdAt: Date(timeIntervalSince1970: 1_768_510_101)
                )
                XCTFail("\(fault) must block before normalization or storage")
            } catch {
                XCTAssertEqual(error as? CheckRunnerCoordinatorError, .storageUnavailable)
            }

            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 0)
            XCTAssertEqual(harness.draft.draftStepKey, WorkflowDraftStep.wide.rawValue)
            XCTAssertEqual(directoryEntryCount(at: stagingEvidenceRoot(harness)), 0)
            XCTAssertEqual(directoryEntryCount(at: promotedEvidenceRoot(harness)), 0)

            let retry = try await harness.coordinator.importCandidate(
                assetID: harness.asset.id,
                sourceData: try makePNG(seed: 11),
                createdAt: Date(timeIntervalSince1970: 1_768_510_101)
            )
            _ = try await harness.coordinator.accept(
                candidate: retry,
                assetID: harness.asset.id
            )
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 1)
            XCTAssertEqual(harness.draft.draftStepKey, WorkflowDraftStep.close.rawValue)
            XCTAssertEqual(directoryEntryCount(at: promotedEvidenceRoot(harness)), 1)
            withExtendedLifetime(harness.session) {}
        }
    }

    @MainActor
    func testEvidenceWriteMoveAndDatabaseFailuresPreserveWideThenRetry() async throws {
        for fault in EvidenceFault.allCases {
            let applicationSupport = try makeTemporaryDirectory(label: "evidence-\(fault)")
            defer { try? fileManager.removeItem(at: applicationSupport) }
            let harness = try await makeHarnessWithAcceptedWide(
                applicationSupportURL: applicationSupport
            )
            let prior = try evidenceAuthority(in: harness)
            let faulted = faultedEvidenceCoordinator(for: fault, harness: harness)
            let source = try makePNG(seed: 73)
            let createdAt = Date(timeIntervalSince1970: 1_768_510_102)
            var activeID: UUID?

            do {
                let candidate = try await faulted.coordinator.importCandidate(
                    assetID: harness.asset.id,
                    sourceData: source,
                    createdAt: createdAt
                )
                activeID = candidate.id
                _ = try await faulted.coordinator.accept(
                    candidate: candidate,
                    assetID: harness.asset.id
                )
                XCTFail("\(fault) must interrupt the active evidence mutation")
            } catch {
                let coordinatorError = error as? CheckRunnerCoordinatorError
                XCTAssertTrue(
                    coordinatorError == .mediaImportFailed
                        || coordinatorError == .saveFailed
                )
            }

            try assertPriorAuthority(prior, in: harness)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 1)
            XCTAssertEqual(harness.draft.draftStepKey, WorkflowDraftStep.close.rawValue)
            XCTAssertEqual(directoryEntryCount(at: stagingEvidenceRoot(harness)), 0)
            XCTAssertEqual(directoryEntryCount(at: promotedEvidenceRoot(harness)), 1)
            if let activeID {
                XCTAssertFalse(
                    fileManager.fileExists(
                        atPath: harness.session.generationRootURL.appendingPathComponent(
                            "evidence/\(activeID.uuidString.lowercased())",
                            isDirectory: true
                        ).path
                    )
                )
            }

            faulted.removeFailure()
            let retry = try await faulted.coordinator.importCandidate(
                assetID: harness.asset.id,
                sourceData: source,
                createdAt: createdAt
            )
            _ = try await faulted.coordinator.accept(
                candidate: retry,
                assetID: harness.asset.id
            )
            try assertPriorAuthority(prior, in: harness)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 2)
            XCTAssertEqual(harness.draft.draftStepKey, WorkflowDraftStep.outcome.rawValue)
            XCTAssertEqual(directoryEntryCount(at: stagingEvidenceRoot(harness)), 0)
            XCTAssertEqual(directoryEntryCount(at: promotedEvidenceRoot(harness)), 2)
            withExtendedLifetime(harness.session) {}
        }
    }

    @MainActor
    func testSnapshotIntentAndModelSaveFailuresPreserveAuthorityThenRetry() async throws {
        for fault in FinalizationFault.precommitCases {
            let applicationSupport = try makeTemporaryDirectory(label: "finalize-\(fault)")
            defer { try? fileManager.removeItem(at: applicationSupport) }
            let harness = try await makeReadyHarness(applicationSupportURL: applicationSupport)
            let prior = try evidenceAuthority(in: harness)
            let faulted = faultedFinalizationCoordinator(for: fault, harness: harness)
            let identifiers = makeIdentifiers()
            let completedAt = Date(timeIntervalSince1970: 1_768_510_103)
            let snapshotAt = Date(timeIntervalSince1970: 1_768_510_104)

            do {
                _ = try await faulted.coordinator.finalize(
                    assetID: harness.asset.id,
                    selection: .noVisibleIssue,
                    completedAt: completedAt,
                    snapshotCreatedAt: snapshotAt,
                    sourceApp: SourceAppSnapshotV1(build: "35", version: "1.0"),
                    identifiers: identifiers
                )
                XCTFail("\(fault) must interrupt finalization before database commit")
            } catch {
                XCTAssertEqual(error as? CheckRunnerCoordinatorError, .finalizationFailed)
            }

            try assertPriorAuthority(prior, in: harness)
            XCTAssertEqual(harness.draft.state, WorkflowState.draft.rawValue)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 0)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 0)
            XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, appSupport: applicationSupport).path))
            XCTAssertFalse(fileManager.fileExists(atPath: stagingSnapshotURL(identifiers, harness: harness).path))
            XCTAssertFalse(fileManager.fileExists(atPath: finalSnapshotURL(identifiers, harness: harness).path))

            faulted.removeFailure()
            let result = try await faulted.coordinator.finalize(
                assetID: harness.asset.id,
                selection: .noVisibleIssue,
                completedAt: completedAt,
                snapshotCreatedAt: snapshotAt,
                sourceApp: SourceAppSnapshotV1(build: "35", version: "1.0"),
                identifiers: identifiers
            )
            XCTAssertEqual(result.reportID, identifiers.reportID)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
            try assertPriorAuthority(prior, in: harness)
            XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, appSupport: applicationSupport).path))
            XCTAssertTrue(fileManager.fileExists(atPath: finalSnapshotURL(identifiers, harness: harness).path))
            withExtendedLifetime(harness.session) {}
        }
    }

    @MainActor
    func testPostSaveIntentFailureLeavesRecoverableAuthorityAndRetryIsDuplicateFree() async throws {
        let applicationSupport = try makeTemporaryDirectory(label: "post-save")
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let harness = try await makeReadyHarness(applicationSupportURL: applicationSupport)
        let prior = try evidenceAuthority(in: harness)
        let faulted = faultedFinalizationCoordinator(
            for: .databaseCommittedIntent,
            harness: harness
        )
        let identifiers = makeIdentifiers()
        let completedAt = Date(timeIntervalSince1970: 1_768_510_105)
        let snapshotAt = Date(timeIntervalSince1970: 1_768_510_106)

        do {
            _ = try await faulted.coordinator.finalize(
                assetID: harness.asset.id,
                selection: .noVisibleIssue,
                completedAt: completedAt,
                snapshotCreatedAt: snapshotAt,
                sourceApp: SourceAppSnapshotV1(build: "35", version: "1.0"),
                identifiers: identifiers
            )
            XCTFail("database-committed phase write must expose recovery")
        } catch {
            XCTAssertEqual(error as? CheckRunnerCoordinatorError, .finalizationFailed)
        }

        try assertPriorAuthority(prior, in: harness)
        XCTAssertEqual(harness.draft.state, WorkflowState.completed.rawValue)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertTrue(fileManager.fileExists(atPath: intentURL(identifiers, appSupport: applicationSupport).path))
        XCTAssertTrue(fileManager.fileExists(atPath: finalSnapshotURL(identifiers, harness: harness).path))

        let recovery = FinalizationRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        let summary = try await recovery.reconcile()
        XCTAssertEqual(summary.recoveredDraftRecordIDs, [])
        XCTAssertEqual(summary.completedRecordIDs, [harness.draft.id])
        XCTAssertFalse(fileManager.fileExists(atPath: intentURL(identifiers, appSupport: applicationSupport).path))

        faulted.removeFailure()
        let replay = try await faulted.coordinator.finalize(
            assetID: harness.asset.id,
            selection: .noVisibleIssue,
            completedAt: completedAt,
            snapshotCreatedAt: snapshotAt,
            sourceApp: SourceAppSnapshotV1(build: "35", version: "1.0"),
            identifiers: identifiers
        )
        XCTAssertEqual(replay.reportID, identifiers.reportID)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0)
        try assertPriorAuthority(prior, in: harness)
        withExtendedLifetime(harness.session) {}
    }

    @MainActor
    private func makeDraftHarness(
        applicationSupportURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService()
    ) throws -> FailureHarness {
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
            storagePreflight: storagePreflight
        )
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        let draft = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_768_510_100)
        )
        return FailureHarness(
            session: session,
            context: context,
            pack: pack,
            asset: asset,
            draft: draft,
            coordinator: coordinator
        )
    }

    @MainActor
    private func makeHarnessWithAcceptedWide(
        applicationSupportURL: URL
    ) async throws -> FailureHarness {
        let harness = try makeDraftHarness(applicationSupportURL: applicationSupportURL)
        let wide = try await harness.coordinator.importCandidate(
            assetID: harness.asset.id,
            sourceData: try makePNG(seed: 31),
            createdAt: Date(timeIntervalSince1970: 1_768_510_101)
        )
        _ = try await harness.coordinator.accept(candidate: wide, assetID: harness.asset.id)
        return harness
    }

    @MainActor
    private func makeReadyHarness(
        applicationSupportURL: URL
    ) async throws -> FailureHarness {
        let harness = try await makeHarnessWithAcceptedWide(
            applicationSupportURL: applicationSupportURL
        )
        let close = try await harness.coordinator.importCandidate(
            assetID: harness.asset.id,
            sourceData: try makePNG(seed: 79),
            createdAt: Date(timeIntervalSince1970: 1_768_510_102)
        )
        _ = try await harness.coordinator.accept(candidate: close, assetID: harness.asset.id)
        XCTAssertEqual(harness.draft.draftStepKey, WorkflowDraftStep.outcome.rawValue)
        return harness
    }

    @MainActor
    private func faultedEvidenceCoordinator(
        for fault: EvidenceFault,
        harness: FailureHarness
    ) -> FaultedCoordinator {
        let storeInjection: EvidenceBundleStoreFailureInjection?
        let saveInjection: CheckRunnerCoordinatorFailureInjection?
        switch fault {
        case .stagingWrite:
            storeInjection = EvidenceBundleStoreFailureInjection(failOnceAt: .stagingWrite)
            saveInjection = nil
        case .atomicMove:
            storeInjection = EvidenceBundleStoreFailureInjection(failOnceAt: .atomicPromotionMove)
            saveInjection = nil
        case .databaseSave:
            storeInjection = nil
            saveInjection = CheckRunnerCoordinatorFailureInjection(failOnceAt: .evidenceModelSave)
        }
        let coordinator = CheckRunnerCoordinator(
            modelContext: harness.context,
            signPack: harness.pack,
            evidenceStoreFailureInjection: storeInjection,
            evidenceSaveFailureInjection: saveInjection
        )
        coordinator.configureCapture(generationRootURL: harness.session.generationRootURL)
        return FaultedCoordinator(
            coordinator: coordinator,
            removeFailure: {
                storeInjection?.removeFailure()
                saveInjection?.removeFailure()
            }
        )
    }

    @MainActor
    private func faultedFinalizationCoordinator(
        for fault: FinalizationFault,
        harness: FailureHarness
    ) -> FaultedCoordinator {
        let storeInjection: FinalizationIntentStoreFailureInjection?
        let serviceInjection: FinalizationServiceFailureInjection?
        switch fault {
        case .snapshotWrite:
            storeInjection = .init(failOnceAt: .snapshotStagingWrite)
            serviceInjection = nil
        case .snapshotMove:
            storeInjection = .init(failOnceAt: .snapshotPromotionMove)
            serviceInjection = nil
        case .snapshotPromotedIntent:
            storeInjection = .init(failOnceAt: .intentPhaseWrite(.snapshotPromoted))
            serviceInjection = nil
        case .modelSave:
            storeInjection = nil
            serviceInjection = .init(failOnceAt: .modelSave)
        case .databaseCommittedIntent:
            storeInjection = .init(failOnceAt: .intentPhaseWrite(.databaseCommitted))
            serviceInjection = nil
        }
        let coordinator = CheckRunnerCoordinator(
            modelContext: harness.context,
            signPack: harness.pack,
            finalizationStoreFailureInjection: storeInjection,
            finalizationServiceFailureInjection: serviceInjection
        )
        coordinator.configureCapture(generationRootURL: harness.session.generationRootURL)
        return FaultedCoordinator(
            coordinator: coordinator,
            removeFailure: {
                storeInjection?.removeFailure()
                serviceInjection?.removeFailure()
            }
        )
    }

    @MainActor
    private func evidenceAuthority(in harness: FailureHarness) throws -> [EvidenceAuthority] {
        try harness.context.fetch(FetchDescriptor<EvidenceFile>())
            .sorted { $0.purposeKey < $1.purposeKey }
            .map { evidence in
                EvidenceAuthority(
                    id: evidence.id,
                    original: try Data(
                        contentsOf: harness.session.generationRootURL
                            .appendingPathComponent(evidence.relativePath)
                    ),
                    thumbnail: try Data(
                        contentsOf: harness.session.generationRootURL
                            .appendingPathComponent(evidence.thumbnailRelativePath)
                    )
                )
            }
    }

    @MainActor
    private func assertPriorAuthority(
        _ authority: [EvidenceAuthority],
        in harness: FailureHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let rows = try harness.context.fetch(FetchDescriptor<EvidenceFile>())
        for expected in authority {
            let row = try XCTUnwrap(rows.first { $0.id == expected.id }, file: file, line: line)
            XCTAssertEqual(
                try Data(
                    contentsOf: harness.session.generationRootURL
                        .appendingPathComponent(row.relativePath)
                ),
                expected.original,
                file: file,
                line: line
            )
            XCTAssertEqual(
                try Data(
                    contentsOf: harness.session.generationRootURL
                        .appendingPathComponent(row.thumbnailRelativePath)
                ),
                expected.thumbnail,
                file: file,
                line: line
            )
        }
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

    @MainActor
    private func stagingEvidenceRoot(_ harness: FailureHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            ".staging/evidence",
            isDirectory: true
        )
    }

    @MainActor
    private func promotedEvidenceRoot(_ harness: FailureHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent("evidence", isDirectory: true)
    }

    private func directoryEntryCount(at url: URL) -> Int {
        (try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0
    }

    private func intentURL(_ identifiers: FinalizationIdentifiers, appSupport: URL) -> URL {
        appSupport.appendingPathComponent(
            "FieldEvidenceOperations/finalization/\(identifiers.mutationID.uuidString.lowercased()).json"
        )
    }

    @MainActor
    private func stagingSnapshotURL(
        _ identifiers: FinalizationIdentifiers,
        harness: FailureHarness
    ) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            ".staging/snapshots/\(identifiers.reportID.uuidString.lowercased()).json"
        )
    }

    @MainActor
    private func finalSnapshotURL(
        _ identifiers: FinalizationIdentifiers,
        harness: FailureHarness
    ) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            "snapshots/\(identifiers.reportID.uuidString.lowercased()).json"
        )
    }

    private func makeTemporaryDirectory(label: String) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S3_5FailureIntegrityTests-\(label)-\(UUID().uuidString)",
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
            throw FailureFixtureError.couldNotCreateImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FailureFixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FailureFixtureError.couldNotCreateImage
        }
        return output as Data
    }
}

private enum CapacityFault: CaseIterable {
    case unavailable
    case insufficient
}

private enum EvidenceFault: CaseIterable {
    case stagingWrite
    case atomicMove
    case databaseSave
}

private enum FinalizationFault {
    case snapshotWrite
    case snapshotMove
    case snapshotPromotedIntent
    case modelSave
    case databaseCommittedIntent

    static let precommitCases: [FinalizationFault] = [
        .snapshotWrite,
        .snapshotMove,
        .snapshotPromotedIntent,
        .modelSave,
    ]
}

@MainActor
private struct FailureHarness {
    let session: StoreGenerationSession
    let context: ModelContext
    let pack: SignPack
    let asset: Asset
    let draft: WorkflowRecord
    let coordinator: CheckRunnerCoordinator
}

@MainActor
private struct FaultedCoordinator {
    let coordinator: CheckRunnerCoordinator
    let removeFailure: @MainActor () -> Void
}

private struct EvidenceAuthority {
    let id: UUID
    let original: Data
    let thumbnail: Data
}

private enum FailureFixtureError: Error {
    case couldNotCreateImage
}

extension S3_5FailureIntegrityTests {
    func testC36PrePromotionRejectsEvidenceIdentityAndInvalidStage() throws {
        XCTAssertFalse(DraftContentPromotionBoundaryV1.assignsEvidenceID)
        XCTAssertTrue(DraftContentPromotionBoundaryV1.writesCanonicalBytes)
        XCTAssertTrue(DraftContentPromotionBoundaryV1.requiresImmutableContentWriter)
        XCTAssertTrue(EvidenceBundleStoreC36GuardV1.prePromotionRequiresNoEvidenceID)

        let draftID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let stageID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        XCTAssertNoThrow(
            try EvidenceBundleStoreC36GuardV1.validatePrePromotion(
                stageID: stageID,
                draftID: draftID
            )
        )
        XCTAssertThrowsError(
            try EvidenceBundleStoreC36GuardV1.validatePrePromotion(
                stageID: UUID(),
                draftID: draftID,
                evidenceID: UUID()
            )
        )
    }

    func testC36WriterReceiptBindsExactBytesWithoutEvidencePath() throws {
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000011")!)
        let mutationID = try MutationIDV1(
            rawValue: UUID(uuidString: "30000000-0000-0000-0000-000000000012")!
        )
        let bytes = Data("c36-payload".utf8)
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: "91f66597b62bf37789b428f57cc43330354ce71aed4f441e0167dcf656171c65"
        )
        let request = try DraftImmutableContentWriteRequestV1(
            workspaceID: workspaceID,
            contentID: "draft-content-\(workspaceID.rawValue.uuidString.lowercased())-\(digest.hexadecimalValue)",
            digest: digest,
            byteLength: Int64(bytes.count),
            mediaType: "application/octet-stream",
            mutationID: mutationID,
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let receipt = try DraftImmutableContentWriteReceiptV1(
            request: request,
            relativePath: request.relativePath,
            reusedExistingBytes: false
        )
        XCTAssertFalse(receipt.relativePath.contains("evidence/"))
        XCTAssertNoThrow(try receipt.validate(request: request, bytes: bytes))
        XCTAssertThrowsError(
            try receipt.validate(request: request, bytes: Data("changed".utf8))
        ) { error in
            XCTAssertEqual(error as? DraftImmutableContentWriterFailureV1, .byteLengthMismatch)
        }
    }
}

extension S3_5FailureIntegrityTests {
    func testV23P03C34CorruptSceneStateFallsBackAndClearsBytes() throws {
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try port.saveSceneNavigationData(Data("not-json".utf8))
        XCTAssertEqual(try adapter.loadAndReconcile(), .discarded(.corruptSnapshot))
        XCTAssertNil(port.data)
    }
}

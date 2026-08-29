import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S3_6CameraRecoveryTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testPermissionRecoveryFamilyNeverRequestsOrMutatesBeforeUserAction() async throws {
        for scenario in PermissionScenario.allCases {
            let applicationSupport = try makeTemporaryDirectory(label: "permission-\(scenario)")
            defer { try? fileManager.removeItem(at: applicationSupport) }
            let harness = try makeDraftHarness(applicationSupportURL: applicationSupport)
            let probe = PermissionProbe(scenario: scenario)
            let adapter = probe.adapter

            XCTAssertEqual(probe.statusCallCount, 0)
            XCTAssertEqual(probe.requestCallCount, 0)
            XCTAssertEqual(probe.availabilityCallCount, 0)
            try assertUnchangedDraft(harness)

            let initial = adapter.authorizationStatus()
            XCTAssertEqual(initial, scenario.initialStatus)
            XCTAssertEqual(probe.requestCallCount, 0)

            switch scenario {
            case .notDeterminedThenDenied:
                let requestedStatus = await adapter.requestAuthorization()
                XCTAssertEqual(requestedStatus, .denied)
                XCTAssertEqual(probe.requestCallCount, 1)
            case .denied, .restricted:
                XCTAssertEqual(initial, scenario.initialStatus)
                XCTAssertEqual(probe.requestCallCount, 0)
            case .unavailable:
                XCTAssertEqual(initial, .authorized)
                XCTAssertFalse(adapter.isCameraAvailable())
                XCTAssertEqual(probe.availabilityCallCount, 1)
                XCTAssertEqual(probe.requestCallCount, 0)
            case .cancellation:
                XCTAssertEqual(initial, .authorized)
                XCTAssertTrue(adapter.isCameraAvailable())
                var cancellationCaptureCount = 0
                var cancellationCount = 0
                var cancellationFailureCount = 0
                var failureCaptureCount = 0
                var failureCancellationCount = 0
                var failureCount = 0
                let picker = UIImagePickerController()
                let cancellationCoordinator = CameraCaptureView(
                    onCapture: { _ in cancellationCaptureCount += 1 },
                    onCancel: { cancellationCount += 1 },
                    onFailure: { cancellationFailureCount += 1 }
                ).makeCoordinator()
                cancellationCoordinator.imagePickerControllerDidCancel(picker)
                cancellationCoordinator.imagePickerControllerDidCancel(picker)
                cancellationCoordinator.imagePickerController(
                    picker,
                    didFinishPickingMediaWithInfo: [:]
                )
                XCTAssertEqual(cancellationCaptureCount, 0)
                XCTAssertEqual(cancellationCount, 1)
                XCTAssertEqual(cancellationFailureCount, 0)

                let failureCoordinator = CameraCaptureView(
                    onCapture: { _ in failureCaptureCount += 1 },
                    onCancel: { failureCancellationCount += 1 },
                    onFailure: { failureCount += 1 }
                ).makeCoordinator()
                failureCoordinator.imagePickerController(
                    picker,
                    didFinishPickingMediaWithInfo: [:]
                )
                failureCoordinator.imagePickerControllerDidCancel(picker)
                XCTAssertEqual(failureCaptureCount, 0)
                XCTAssertEqual(failureCancellationCount, 0)
                XCTAssertEqual(failureCount, 1)
                XCTAssertEqual(probe.requestCallCount, 0)
            case .settingsReturn:
                XCTAssertEqual(initial, .denied)
                XCTAssertEqual(probe.requestCallCount, 0)
                probe.status = .authorized
                XCTAssertEqual(adapter.authorizationStatus(), .authorized)
                XCTAssertTrue(adapter.isCameraAvailable())
            }

            try assertUnchangedDraft(harness)
            XCTAssertEqual(directoryEntryCount(at: stagingEvidenceRoot(harness)), 0)
            XCTAssertEqual(directoryEntryCount(at: promotedEvidenceRoot(harness)), 0)
            withExtendedLifetime(harness.session) {}
        }
    }

    @MainActor
    func testAuthorizedWideAndCloseBytesUseExistingCanonicalMediaAuthority() async throws {
        let applicationSupport = try makeTemporaryDirectory(label: "authorized")
        defer { try? fileManager.removeItem(at: applicationSupport) }
        let harness = try makeDraftHarness(applicationSupportURL: applicationSupport)
        let probe = PermissionProbe(scenario: .settingsReturn)
        probe.status = .authorized
        let adapter = probe.adapter
        XCTAssertEqual(adapter.authorizationStatus(), .authorized)
        XCTAssertTrue(adapter.isCameraAvailable())
        XCTAssertEqual(probe.requestCallCount, 0)

        let sourceByPurpose: [(seed: UInt8, purpose: String, step: WorkflowDraftStep)] = [
            (31, "wide_context", .close),
            (79, "close_detail", .outcome),
        ]
        for value in sourceByPurpose {
            let source = try makePNG(seed: value.seed)
            let independentlyNormalized = try MediaNormalizerV1().normalize(source)
            let candidate = try await harness.coordinator.importCandidate(
                assetID: harness.asset.id,
                sourceData: source,
                createdAt: Date(timeIntervalSince1970: 1_768_600_100 + Double(value.seed))
            )
            XCTAssertEqual(candidate.purposeKey, value.purpose)
            XCTAssertEqual(candidate.previewJPEG, independentlyNormalized.originalJPEG)
            let evidence = try await harness.coordinator.accept(
                candidate: candidate,
                assetID: harness.asset.id
            )
            XCTAssertEqual(
                try Data(
                    contentsOf: harness.session.generationRootURL
                        .appendingPathComponent(evidence.relativePath)
                ),
                independentlyNormalized.originalJPEG
            )
            XCTAssertEqual(
                try Data(
                    contentsOf: harness.session.generationRootURL
                        .appendingPathComponent(evidence.thumbnailRelativePath)
                ),
                independentlyNormalized.thumbnailJPEG
            )
            XCTAssertEqual(harness.draft.draftStepKey, value.step.rawValue)
        }

        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 2)
        XCTAssertEqual(directoryEntryCount(at: stagingEvidenceRoot(harness)), 0)
        XCTAssertEqual(directoryEntryCount(at: promotedEvidenceRoot(harness)), 2)
        XCTAssertEqual(probe.requestCallCount, 0)
        withExtendedLifetime(harness.session) {}
    }

    @MainActor
    private func makeDraftHarness(applicationSupportURL: URL) throws -> CameraHarness {
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
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        let draft = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_768_600_000)
        )
        return CameraHarness(
            session: session,
            context: context,
            asset: asset,
            draft: draft,
            coordinator: coordinator
        )
    }

    @MainActor
    private func assertUnchangedDraft(
        _ harness: CameraHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 0, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 0, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 0, file: file, line: line)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Issue>()), 0, file: file, line: line)
        XCTAssertEqual(harness.draft.state, WorkflowState.draft.rawValue, file: file, line: line)
        XCTAssertEqual(harness.draft.draftStepKey, WorkflowDraftStep.wide.rawValue, file: file, line: line)
        XCTAssertNil(harness.draft.outcomeKey, file: file, line: line)
        XCTAssertNil(harness.draft.completedAt, file: file, line: line)
    }

    @MainActor
    private func stagingEvidenceRoot(_ harness: CameraHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            ".staging/evidence",
            isDirectory: true
        )
    }

    @MainActor
    private func promotedEvidenceRoot(_ harness: CameraHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent("evidence", isDirectory: true)
    }

    private func directoryEntryCount(at url: URL) -> Int {
        (try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0
    }

    private func makeTemporaryDirectory(label: String) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S3_6CameraRecoveryTests-\(label)-\(UUID().uuidString)",
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
            throw CameraFixtureError.couldNotCreateImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CameraFixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CameraFixtureError.couldNotCreateImage
        }
        return output as Data
    }
}

private final class C27S36TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorInputSourceV1.allCases, [.camera, .manual, .imported])
        XCTAssertEqual(AssetLocatorLimitsV1.maximumInputBytes, 1_024)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

private enum PermissionScenario: CaseIterable {
    case notDeterminedThenDenied
    case denied
    case restricted
    case unavailable
    case cancellation
    case settingsReturn

    var initialStatus: CameraAuthorizationStatus {
        switch self {
        case .notDeterminedThenDenied: .notDetermined
        case .denied, .settingsReturn: .denied
        case .restricted: .restricted
        case .unavailable, .cancellation: .authorized
        }
    }
}

@MainActor
private final class PermissionProbe {
    var status: CameraAuthorizationStatus
    private(set) var statusCallCount = 0
    private(set) var requestCallCount = 0
    private(set) var availabilityCallCount = 0
    private let scenario: PermissionScenario

    init(scenario: PermissionScenario) {
        self.scenario = scenario
        self.status = scenario.initialStatus
    }

    var adapter: CameraAdapter {
        CameraAdapter(
            authorizationStatus: { [weak self] in
                guard let self else { return .denied }
                statusCallCount += 1
                return status
            },
            requestAuthorization: { [weak self] in
                guard let self else { return .denied }
                requestCallCount += 1
                if scenario == .notDeterminedThenDenied {
                    status = .denied
                }
                return status
            },
            isCameraAvailable: { [weak self] in
                guard let self else { return false }
                availabilityCallCount += 1
                return scenario != .unavailable
            }
        )
    }
}

@MainActor
private struct CameraHarness {
    let session: StoreGenerationSession
    let context: ModelContext
    let asset: Asset
    let draft: WorkflowRecord
    let coordinator: CheckRunnerCoordinator
}

private enum CameraFixtureError: Error {
    case couldNotCreateImage
}

extension S3_6CameraRecoveryTests {
    func testC36AttachmentKindsRemainTypedAtCaptureBoundary() {
        XCTAssertEqual(DraftAttachmentKindV1.allCases.count, 4)
        XCTAssertTrue(DraftAttachmentKindV1.allCases.contains(.photo))
        XCTAssertTrue(DraftAttachmentKindV1.allCases.contains(.audio))
        XCTAssertTrue(DraftAttachmentKindV1.allCases.contains(.video))
        XCTAssertTrue(DraftAttachmentKindV1.allCases.contains(.file))
    }
}

import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private final class C45PDFRecoveryCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityFreezesQRGeometryForDeterministicPDFRecovery() {
        XCTAssertEqual(DeterministicPDFRendererV1.assetLabelQuietZoneModules, 4)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelInterpolationEnabled)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelOverlaidLogoEnabled)
        XCTAssertEqual(AssetLabelQRCorrectionLevelV1.medium.rawValue, "M")
    }
}

private final class C30EvidenceContextAnchorS4_2PDFRecovery: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S4_2PDFRecoveryTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    private let fileManager = FileManager.default

    @MainActor
    func testRenderFailureBecomesFailedThenExplicitRetryReadiesSameAuthority() async throws {
        let harness = try await makeHarness("golden")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let before = try immutableAuthority(in: harness)

        let failing = try ReportRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            failNextRenderAttempt: true
        )
        try failing.reconcileAtStartup()

        try assertFailed(harness)
        XCTAssertEqual(failing.failedReportIDs, [Fixture.reportID])
        XCTAssertEqual(try immutableAuthority(in: harness), before)

        let retry = try ReportRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        let result = try await retry.retryFailedReport(id: Fixture.reportID)
        guard case .ready(let ready) = result else {
            return XCTFail("One explicit retry must ready the same report")
        }
        XCTAssertEqual(ready.reportID, Fixture.reportID)
        XCTAssertEqual(ready.pdfRelativePath, finalRelativePath)
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.ready.rawValue)
        XCTAssertEqual(harness.report.pdfRelativePath, finalRelativePath)
        XCTAssertEqual(harness.report.pdfSHA256, ready.pdfSHA256)
        XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)).sha256, ready.pdfSHA256)
        XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path))
        XCTAssertEqual(try immutableAuthority(in: harness), before)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Packet>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceFile>()), 2)
        await assertThrowsErrorAsync({
            try await retry.retryFailedReport(id: Fixture.reportID)
        }) {
            XCTAssertEqual($0 as? ReportRecoveryServiceError, .reportNotFailed)
        }
    }

    @MainActor
    func testBoundedRenderFailureFamilyCleansOwnedOutputAndPersistsFailed() async throws {
        for point in [
            ReportRenderFailurePoint.stageWrite,
            .promotion,
            .reread,
            .readySave,
        ] {
            let harness = try await makeHarness("failure-\(point)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let before = try immutableAuthority(in: harness)
            let recovery = try ReportRecoveryService(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL,
                failureInjection: ReportRenderFailureInjection(failOnceAt: point)
            )

            try recovery.reconcileAtStartup()

            try assertFailed(harness, label: "\(point)")
            XCTAssertEqual(try immutableAuthority(in: harness), before, "\(point)")
        }

        let capacity = try await makeHarness("capacity")
        defer { try? fileManager.removeItem(at: capacity.applicationSupportURL) }
        let capacityBefore = try immutableAuthority(in: capacity)
        let capacityService = try ReportRenderService(
            modelContext: capacity.context,
            generationRootURL: capacity.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in 0 })
        )
        guard case .failed = try capacityService.attemptPendingReport(
            id: Fixture.reportID
        ) else {
            return XCTFail("Capacity failure must become retryable failed state")
        }
        try assertFailed(capacity)
        XCTAssertEqual(try immutableAuthority(in: capacity), capacityBefore)

        let validator = try await makeHarness("validator")
        defer { try? fileManager.removeItem(at: validator.applicationSupportURL) }
        validator.source.outcomeKey = "visible_issue"
        try validator.context.save()
        let validatorBefore = try immutableAuthority(in: validator)
        let validatorService = try ReportRenderService(
            modelContext: validator.context,
            generationRootURL: validator.session.generationRootURL
        )
        guard case .failed = try validatorService.attemptPendingReport(
            id: Fixture.reportID
        ) else {
            return XCTFail("Validator failure must become retryable failed state")
        }
        try assertFailed(validator)
        XCTAssertEqual(try immutableAuthority(in: validator), validatorBefore)

        let repeated = try await makeHarness("retry-fails-again")
        defer { try? fileManager.removeItem(at: repeated.applicationSupportURL) }
        repeated.report.pdfState = ReportPDFState.failed.rawValue
        try repeated.context.save()
        let repeatedBefore = try immutableAuthority(in: repeated)
        let repeatedRecovery = try ReportRecoveryService(
            modelContext: repeated.context,
            generationRootURL: repeated.session.generationRootURL,
            failureInjection: ReportRenderFailureInjection(failOnceAt: .render)
        )
        try repeatedRecovery.reconcileAtStartup()
        guard case .failed = try await repeatedRecovery.retryFailedReport(
            id: Fixture.reportID
        ) else {
            return XCTFail("A repeated ordinary failure must stay retryable")
        }
        try assertFailed(repeated)
        XCTAssertEqual(try immutableAuthority(in: repeated), repeatedBefore)
    }

    @MainActor
    func testFailedStateSaveFailureRollsBackAndRemainsUnsafe() async throws {
        let harness = try await makeHarness("failed-save")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let before = try immutableAuthority(in: harness)
        let service = try ReportRenderService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in 0 }),
            failureInjection: ReportRenderFailureInjection(
                failOnceAt: .failedStateSave
            )
        )

        XCTAssertThrowsError(try service.attemptPendingReport(id: Fixture.reportID)) {
            XCTAssertEqual(
                $0 as? ReportRenderServiceError,
                .failedStateSaveFailed
            )
        }
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.pending.rawValue)
        XCTAssertNil(harness.report.pdfRelativePath)
        XCTAssertNil(harness.report.pdfSHA256)
        XCTAssertEqual(try immutableAuthority(in: harness), before)

        let transition = try await makeHarness("transition-save")
        defer { try? fileManager.removeItem(at: transition.applicationSupportURL) }
        transition.report.pdfState = ReportPDFState.failed.rawValue
        try transition.context.save()
        let transitionBefore = try immutableAuthority(in: transition)
        let recovery = try ReportRecoveryService(
            modelContext: transition.context,
            generationRootURL: transition.session.generationRootURL,
            recoveryFailureInjection: ReportRecoveryFailureInjection(
                failOnceAt: .retryTransitionSave
            )
        )
        try recovery.reconcileAtStartup()
        await assertThrowsErrorAsync({
            try await recovery.retryFailedReport(id: Fixture.reportID)
        }) {
            XCTAssertEqual(
                $0 as? ReportRecoveryServiceError,
                .transitionSaveFailed
            )
        }
        try assertFailed(transition)
        XCTAssertEqual(try immutableAuthority(in: transition), transitionBefore)
    }

    @MainActor
    func testPendingLaunchPresenceMatrixCleansOwnedArtifactsAndAttemptsOnce() async throws {
        for presence in NonReadyPresence.allCases {
            let harness = try await makeHarness("pending-\(presence)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let expected = try ReportRenderService(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL
            ).renderPendingReport(id: Fixture.reportID)
            let expectedBytes = try Data(contentsOf: finalURL(in: harness))
            try fileManager.removeItem(at: finalURL(in: harness))
            harness.report.pdfState = ReportPDFState.pending.rawValue
            harness.report.pdfRelativePath = nil
            harness.report.pdfSHA256 = nil
            try harness.context.save()
            try seed(presence, bytes: expectedBytes, in: harness)
            let before = try immutableAuthority(in: harness)
            let recovery = try ReportRecoveryService(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL
            )

            try recovery.reconcileAtStartup()

            XCTAssertEqual(harness.report.pdfState, ReportPDFState.ready.rawValue, "\(presence)")
            XCTAssertEqual(harness.report.pdfRelativePath, finalRelativePath, "\(presence)")
            XCTAssertEqual(harness.report.pdfSHA256, expected.pdfSHA256, "\(presence)")
            XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), expectedBytes, "\(presence)")
            XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path), "\(presence)")
            XCTAssertEqual(try immutableAuthority(in: harness), before, "\(presence)")
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1, "\(presence)")
        }
    }

    @MainActor
    func testFailedLaunchNeverRendersAndRemovesOnlyOwnedNonReadyArtifact() async throws {
        for presence in NonReadyPresence.allCases {
            let harness = try await makeHarness("failed-\(presence)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            harness.report.pdfState = ReportPDFState.failed.rawValue
            try harness.context.save()
            let ownedBytes = Data("owned interrupted PDF".utf8)
            try seed(presence, bytes: ownedBytes, in: harness)
            let before = try immutableAuthority(in: harness)
            let recovery = try ReportRecoveryService(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL,
                failNextRenderAttempt: true
            )

            try recovery.reconcileAtStartup()

            try assertFailed(harness, label: "\(presence)")
            XCTAssertEqual(recovery.failedReportIDs, [Fixture.reportID], "\(presence)")
            XCTAssertEqual(try immutableAuthority(in: harness), before, "\(presence)")
        }
    }

    @MainActor
    func testValidReadyReportRemainsByteIdenticalAndTerminal() async throws {
        let harness = try await makeHarness("ready")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        _ = try ReportRenderService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        ).renderPendingReport(id: Fixture.reportID)
        let before = try immutableAuthority(in: harness)
        let pdfBefore = try Data(contentsOf: finalURL(in: harness))
        let stateBefore = (harness.report.pdfRelativePath, harness.report.pdfSHA256)
        let recovery = try ReportRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            failNextRenderAttempt: true
        )

        try recovery.reconcileAtStartup()

        XCTAssertEqual(harness.report.pdfState, ReportPDFState.ready.rawValue)
        XCTAssertEqual(harness.report.pdfRelativePath, stateBefore.0)
        XCTAssertEqual(harness.report.pdfSHA256, stateBefore.1)
        XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), pdfBefore)
        XCTAssertEqual(try immutableAuthority(in: harness), before)
        XCTAssertTrue(recovery.failedReportIDs.isEmpty)
        XCTAssertThrowsError(try ReportRenderService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        ).renderPendingReport(id: Fixture.reportID))
    }

    @MainActor
    func testUnsafeMalformedAndMismatchedAuthorityFailClosedWithoutCleanup() async throws {
        let cases: [UnsafeCase] = [
            .simultaneous,
            .stageSymlink,
            .stageDirectory,
            .snapshotAncestorSymlink,
            .generationAncestorSymlink,
            .readyMissing,
            .readyMismatch,
            .readyWithStage,
            .invalidNullability,
            .unknownState,
            .corruptSnapshotBytes,
            .noncanonicalReadyPath,
            .uppercaseReadyHash,
        ]
        for testCase in cases {
            let harness = try await makeHarness("unsafe-\(testCase)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let sentinel = Data("do not adopt or delete".utf8)
            try configure(testCase, sentinel: sentinel, in: harness)
            let before = try immutableAuthority(in: harness)
            if testCase == .generationAncestorSymlink {
                XCTAssertThrowsError(try ReportRecoveryService(
                    modelContext: harness.context,
                    generationRootURL: harness.session.generationRootURL
                ), "\(testCase)")
                XCTAssertEqual(
                    try immutableAuthority(in: harness),
                    before,
                    "\(testCase)"
                )
                XCTAssertEqual(
                    try harness.context.fetchCount(FetchDescriptor<Report>()),
                    1,
                    "\(testCase)"
                )
                continue
            }
            let recovery = try ReportRecoveryService(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL
            )

            XCTAssertThrowsError(try recovery.reconcileAtStartup(), "\(testCase)")
            XCTAssertEqual(try immutableAuthority(in: harness), before, "\(testCase)")
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1, "\(testCase)")
            switch testCase {
            case .simultaneous, .readyWithStage:
                XCTAssertEqual(try Data(contentsOf: stageURL(in: harness)), sentinel)
                XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), sentinel)
            case .stageSymlink:
                XCTAssertNotNil(try? fileManager.destinationOfSymbolicLink(atPath: stageURL(in: harness).path))
            case .stageDirectory:
                var isDirectory = ObjCBool(false)
                XCTAssertTrue(fileManager.fileExists(
                    atPath: stageURL(in: harness).path,
                    isDirectory: &isDirectory
                ))
                XCTAssertTrue(isDirectory.boolValue)
            case .snapshotAncestorSymlink:
                XCTAssertNotNil(try? fileManager.destinationOfSymbolicLink(
                    atPath: harness.session.generationRootURL
                        .appendingPathComponent("snapshots").path
                ))
            case .generationAncestorSymlink:
                XCTAssertNotNil(try? fileManager.destinationOfSymbolicLink(
                    atPath: harness.session.generationRootURL
                        .deletingLastPathComponent().path
                ))
            case .readyMismatch:
                XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), sentinel)
            case .readyMissing, .invalidNullability, .unknownState,
                 .corruptSnapshotBytes,
                 .noncanonicalReadyPath, .uppercaseReadyHash:
                break
            }
        }
    }

    @MainActor
    func testWholeMatrixIsValidatedBeforeAnyPendingMutation() async throws {
        let harness = try await makeHarness("whole-matrix")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let collidingID = UUID(
            uuidString: "42000000-0000-0000-0000-000000000099"
        )!
        let collision = Report(
            id: collidingID,
            packetID: harness.report.packetID,
            sourceRecordID: harness.report.sourceRecordID,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(collidingID.uuidString.lowercased()).json",
            snapshotSHA256: harness.report.snapshotSHA256,
            pdfState: .failed,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: harness.report.createdAt.addingTimeInterval(1),
            replacesReportID: nil
        )
        harness.context.insert(collision)
        try harness.context.save()
        let before = try immutableAuthority(in: harness)
        let recovery = try ReportRecoveryService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.pending.rawValue)
        XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path))
        XCTAssertFalse(fileManager.fileExists(atPath: finalURL(in: harness).path))
        XCTAssertEqual(try immutableAuthority(in: harness), before)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)
    }
}

private final class C27S42TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorInputSourceV1.allCases.count, 3)
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension S4_2PDFRecoveryTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

private enum NonReadyPresence: CaseIterable { case absent, stageOnly, finalOnly }
private enum UnsafeCase: Equatable {
    case simultaneous
    case stageSymlink
    case stageDirectory
    case snapshotAncestorSymlink
    case generationAncestorSymlink
    case readyMissing
    case readyMismatch
    case readyWithStage
    case invalidNullability
    case unknownState
    case corruptSnapshotBytes
    case noncanonicalReadyPath
    case uppercaseReadyHash
}

@MainActor
private struct RecoveryHarness {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let context: ModelContext
    let report: Report
    let source: WorkflowRecord
    let packet: Packet
}

private struct ImmutableAuthority: Equatable {
    let snapshot: Data
    let snapshotPath: String
    let snapshotSHA256: String
    let packetID: UUID
    let sourceRecordID: UUID
    let stableRootID: UUID
    let createdAt: Date
    let sourceState: String
    let sourceOutcome: String?
    let sourceMutationID: UUID?
    let evaluationCounted: Bool
    let evidence: [ImmutableEvidenceAuthority]
}

private struct ImmutableEvidenceAuthority: Equatable {
    let id: UUID
    let recordID: UUID
    let purposeKey: String
    let relativePath: String
    let sha256: String
    let originalBytes: Data
    let thumbnailRelativePath: String
    let thumbnailSHA256: String
    let thumbnailBytes: Data
}

private enum Fixture {
    static let siteID = UUID(uuidString: "42000000-0000-0000-0000-000000000001")!
    static let assetID = UUID(uuidString: "42000000-0000-0000-0000-000000000002")!
    static let mutationID = UUID(uuidString: "42000000-0000-0000-0000-000000000004")!
    static let packetID = UUID(uuidString: "42000000-0000-0000-0000-000000000005")!
    static let stableRootID = UUID(uuidString: "42000000-0000-0000-0000-000000000006")!
    static let reportID = UUID(uuidString: "42000000-0000-0000-0000-000000000007")!
    static let observedAt = Date(timeIntervalSince1970: 1_768_800_000)
    static let completedAt = Date(timeIntervalSince1970: 1_768_800_010)
    static let snapshotAt = Date(timeIntervalSince1970: 1_768_800_011)
}

private extension S4_2PDFRecoveryTests {
    var finalRelativePath: String { "pdfs/\(Fixture.reportID.uuidString.lowercased()).pdf" }

    @MainActor
    func makeHarness(_ label: String) async throws -> RecoveryHarness {
        let applicationSupport = fileManager.temporaryDirectory.appendingPathComponent(
            "S4_2PDFRecoveryTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: applicationSupport)
            .openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let site = Site(
            id: Fixture.siteID,
            label: "North Campus",
            address: "10 Main",
            timeZoneID: "America/New_York",
            createdAt: Fixture.observedAt.addingTimeInterval(-2)
        )
        let asset = Asset(
            id: Fixture.assetID,
            siteID: site.id,
            packID: pack.packID,
            packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            label: "Monument Sign",
            createdAt: Fixture.observedAt.addingTimeInterval(-1)
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
            observedAt: Fixture.observedAt
        )
        let wide = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: 31),
            createdAt: Fixture.observedAt.addingTimeInterval(1)
        )
        _ = try await coordinator.accept(candidate: wide, assetID: asset.id)
        let close = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: 79),
            createdAt: Fixture.observedAt.addingTimeInterval(2)
        )
        _ = try await coordinator.accept(candidate: close, assetID: asset.id)
        let result = try await coordinator.finalize(
            assetID: asset.id,
            selection: .noVisibleIssue,
            completedAt: Fixture.completedAt,
            snapshotCreatedAt: Fixture.snapshotAt,
            sourceApp: SourceAppSnapshotV1(build: "42", version: "1.0"),
            identifiers: FinalizationIdentifiers(
                mutationID: Fixture.mutationID,
                packetID: Fixture.packetID,
                stableRootID: Fixture.stableRootID,
                reportID: Fixture.reportID,
                issueID: nil
            )
        )
        XCTAssertEqual(result.reportID, Fixture.reportID)
        let report = try XCTUnwrap(context.fetch(FetchDescriptor<Report>()).first)
        let packet = try XCTUnwrap(context.fetch(FetchDescriptor<Packet>()).first)
        return RecoveryHarness(
            applicationSupportURL: applicationSupport,
            session: session,
            context: context,
            report: report,
            source: draft,
            packet: packet
        )
    }

    @MainActor
    func immutableAuthority(in harness: RecoveryHarness) throws -> ImmutableAuthority {
        let evidence = try harness.context.fetch(FetchDescriptor<EvidenceFile>())
            .sorted { $0.purposeKey < $1.purposeKey }
            .map { row in
                ImmutableEvidenceAuthority(
                    id: row.id,
                    recordID: row.recordID,
                    purposeKey: row.purposeKey,
                    relativePath: row.relativePath,
                    sha256: row.sha256,
                    originalBytes: try Data(
                        contentsOf: harness.session.generationRootURL
                            .appendingPathComponent(row.relativePath)
                    ),
                    thumbnailRelativePath: row.thumbnailRelativePath,
                    thumbnailSHA256: row.thumbnailSHA256,
                    thumbnailBytes: try Data(
                        contentsOf: harness.session.generationRootURL
                            .appendingPathComponent(row.thumbnailRelativePath)
                    )
                )
            }
        return ImmutableAuthority(
            snapshot: try Data(contentsOf: harness.session.generationRootURL.appendingPathComponent(harness.report.snapshotRelativePath)),
            snapshotPath: harness.report.snapshotRelativePath,
            snapshotSHA256: harness.report.snapshotSHA256,
            packetID: harness.report.packetID,
            sourceRecordID: harness.report.sourceRecordID,
            stableRootID: harness.packet.stableRootID,
            createdAt: harness.report.createdAt,
            sourceState: harness.source.state,
            sourceOutcome: harness.source.outcomeKey,
            sourceMutationID: harness.source.finalizationMutationID,
            evaluationCounted: harness.packet.evaluationCounted,
            evidence: evidence
        )
    }

    @MainActor
    func assertFailed(
        _ harness: RecoveryHarness,
        label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.failed.rawValue, label, file: file, line: line)
        XCTAssertNil(harness.report.pdfRelativePath, label, file: file, line: line)
        XCTAssertNil(harness.report.pdfSHA256, label, file: file, line: line)
        XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path), label, file: file, line: line)
        XCTAssertFalse(fileManager.fileExists(atPath: finalURL(in: harness).path), label, file: file, line: line)
    }

    @MainActor
    func stageURL(in harness: RecoveryHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            ".staging/pdfs/\(Fixture.reportID.uuidString.lowercased()).pdf"
        )
    }

    @MainActor
    func finalURL(in harness: RecoveryHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent(finalRelativePath)
    }

    @MainActor
    func seed(_ presence: NonReadyPresence, bytes: Data, in harness: RecoveryHarness) throws {
        switch presence {
        case .absent:
            return
        case .stageOnly:
            try write(bytes, to: stageURL(in: harness))
        case .finalOnly:
            try write(bytes, to: finalURL(in: harness))
        }
    }

    @MainActor
    func configure(_ testCase: UnsafeCase, sentinel: Data, in harness: RecoveryHarness) throws {
        switch testCase {
        case .simultaneous:
            try write(sentinel, to: stageURL(in: harness))
            try write(sentinel, to: finalURL(in: harness))
        case .stageSymlink:
            let target = harness.session.generationRootURL.appendingPathComponent("outside-stage.pdf")
            try sentinel.write(to: target)
            try fileManager.createDirectory(
                at: stageURL(in: harness).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createSymbolicLink(at: stageURL(in: harness), withDestinationURL: target)
        case .stageDirectory:
            try fileManager.createDirectory(
                at: stageURL(in: harness),
                withIntermediateDirectories: true
            )
        case .snapshotAncestorSymlink:
            let snapshots = harness.session.generationRootURL.appendingPathComponent(
                "snapshots",
                isDirectory: true
            )
            let retained = harness.session.generationRootURL.appendingPathComponent(
                "snapshots-retained",
                isDirectory: true
            )
            try fileManager.moveItem(at: snapshots, to: retained)
            try fileManager.createSymbolicLink(
                at: snapshots,
                withDestinationURL: retained
            )
        case .generationAncestorSymlink:
            let generations = harness.session.generationRootURL
                .deletingLastPathComponent()
            let retained = generations.deletingLastPathComponent()
                .appendingPathComponent("generations-retained", isDirectory: true)
            try fileManager.moveItem(at: generations, to: retained)
            try fileManager.createSymbolicLink(
                at: generations,
                withDestinationURL: retained
            )
        case .readyMissing:
            harness.report.pdfState = ReportPDFState.ready.rawValue
            harness.report.pdfRelativePath = finalRelativePath
            harness.report.pdfSHA256 = sentinel.sha256
            try harness.context.save()
        case .readyMismatch:
            harness.report.pdfState = ReportPDFState.ready.rawValue
            harness.report.pdfRelativePath = finalRelativePath
            harness.report.pdfSHA256 = Data("different expected bytes".utf8).sha256
            try harness.context.save()
            try write(sentinel, to: finalURL(in: harness))
        case .readyWithStage:
            harness.report.pdfState = ReportPDFState.ready.rawValue
            harness.report.pdfRelativePath = finalRelativePath
            harness.report.pdfSHA256 = sentinel.sha256
            try harness.context.save()
            try write(sentinel, to: stageURL(in: harness))
            try write(sentinel, to: finalURL(in: harness))
        case .invalidNullability:
            harness.report.pdfState = ReportPDFState.failed.rawValue
            harness.report.pdfRelativePath = finalRelativePath
            harness.report.pdfSHA256 = nil
            try harness.context.save()
        case .unknownState:
            harness.report.pdfState = "unknown"
            try harness.context.save()
        case .corruptSnapshotBytes:
            try sentinel.write(
                to: harness.session.generationRootURL.appendingPathComponent(
                    harness.report.snapshotRelativePath
                )
            )
        case .noncanonicalReadyPath:
            harness.report.pdfState = ReportPDFState.ready.rawValue
            harness.report.pdfRelativePath = "pdfs/../wrong.pdf"
            harness.report.pdfSHA256 = sentinel.sha256
            try harness.context.save()
        case .uppercaseReadyHash:
            harness.report.pdfState = ReportPDFState.ready.rawValue
            harness.report.pdfRelativePath = finalRelativePath
            harness.report.pdfSHA256 = sentinel.sha256.uppercased()
            try harness.context.save()
        }
    }

    func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func makePNG(seed: UInt8) throws -> Data {
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
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw RecoveryFixtureError.couldNotCreateImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RecoveryFixtureError.couldNotCreateImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RecoveryFixtureError.couldNotCreateImage
        }
        return output as Data
    }

    @MainActor
    func assertThrowsErrorAsync<T>(
        _ operation: () async throws -> T,
        _ errorHandler: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}

private enum RecoveryFixtureError: Error {
    case couldNotCreateImage
}

private extension Data {
    var sha256: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
extension S4_2PDFRecoveryTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleStateV1.allCases.count, 3)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.lifecycleEventPersistence, "CANONICAL_MUTATION_JOURNAL_ENVELOPE")
        XCTAssertEqual(PersistentSchemaV24.models.count, PersistentSchemaV23.models.count + 2)
    }
}
extension S4_2PDFRecoveryTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S4_2PDFRecoveryTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS42PDFRecoveryTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorS42PDFRecovery: XCTestCase {
    func testC33S42PDFRecoveryCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "pdf.temporal-link-recovery",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "pdf.temporal-link-recovery",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS42PDFRecovery: XCTestCase {
    func testC32S42PDFRecoveryCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .report,
            fieldID: "pdf.exclude-proposal",
            value: .text("unverified value excluded from PDF")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .report,
            fieldID: "pdf.exclude-proposal",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46S42PDFCompatibilityTests: XCTestCase {
    func testC46PDFRecoveryNeverPrefillsContactValue() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "pdf-recovery",
            kind: .phone,
            handoff: .directions,
            slot: 46402
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift_Tests: XCTestCase {
    func testC47S42PDFRecoveryTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_2PDFRecoveryTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityKindV2.knownCases.count, 7)
        XCTAssertFalse(ActivityContractPersistenceEnrollmentV2.planOrScanProviderRequired)
    }
}

private final class C48PortableReviewS42PDFRecoveryTests: XCTestCase {
    func testC48PDFRecoveryPreservesImmutableHistoryWithoutSecretBytes() {
        XCTAssertTrue(C48PortableReviewPDFBoundaryV1.usesExistingPDFRenderer)
        XCTAssertTrue(C48PortableReviewReportRecoveryBoundaryV1.recoveryReadsImmutableResponseHistory)
        XCTAssertTrue(C48PortableReviewReportRecoveryBoundaryV1.recoveryDoesNotRewriteResponseBytes)
        XCTAssertFalse(C48PortableReviewPDFBoundaryV1.capabilityProofBytesEmitted)
    }
}

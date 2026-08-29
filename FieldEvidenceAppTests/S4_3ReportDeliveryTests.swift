import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private final class C45ReportDeliveryCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityDoesNotEquateGenerationWithExternalHandoff() {
        XCTAssertEqual(LabelOutputDispositionV1.generated.rawValue, "GENERATED")
        XCTAssertEqual(LabelOutputDispositionV1.handedOffToSystem.rawValue, "HANDED_OFF_TO_SYSTEM")
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelPhysicalScanAcceptanceClaimed)
    }
}

private final class C30EvidenceContextAnchorS4_3ReportDelivery: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S4_3ReportDeliveryTests: XCTestCase {
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
    func testReceiptAttemptsExactlyOnceAndEveryDeliveryUsesIdenticalCachedBytes() async throws {
        let harness = try await makeHarness("golden")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let readyBytes = try Data(contentsOf: finalURL(in: harness))
        try resetToPending(harness)
        let before = try immutableAuthority(in: harness)
        let coordinator = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )

        guard case let .ready(first) = try coordinator.prepareFinalizedReport(
            id: Fixture.reportID
        ) else { return XCTFail("The one receipt attempt must ready the PDF") }
        guard case let .ready(second) = try coordinator.prepareFinalizedReport(
            id: Fixture.reportID
        ) else { return XCTFail("Repeat receipt preparation must only reload ready bytes") }
        let loaded = try coordinator.loadReadyReport(id: Fixture.reportID)

        XCTAssertEqual(first, second)
        XCTAssertEqual(second, loaded)
        XCTAssertEqual(first.reportID, Fixture.reportID)
        XCTAssertEqual(first.pdfData, readyBytes)
        XCTAssertEqual(first.pdfSHA256, readyBytes.sha256)
        XCTAssertEqual(first.filename, "report-\(Fixture.reportID.uuidString.lowercased()).pdf")
        XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), readyBytes)
        XCTAssertEqual(try immutableAuthority(in: harness), before)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 1)

        let failed = try await makeHarness("one-failed-attempt")
        defer { try? fileManager.removeItem(at: failed.applicationSupportURL) }
        try resetToPending(failed)
        let failing = try ReportDeliveryCoordinator(
            modelContext: failed.context,
            generationRootURL: failed.session.generationRootURL,
            renderFailureInjection: ReportRenderFailureInjection(failOnceAt: .render)
        )
        XCTAssertEqual(
            try failing.prepareFinalizedReport(id: Fixture.reportID),
            .failed(reportID: Fixture.reportID)
        )
        XCTAssertEqual(
            try failing.prepareFinalizedReport(id: Fixture.reportID),
            .failed(reportID: Fixture.reportID)
        )
        XCTAssertThrowsError(try failing.loadReadyReport(id: Fixture.reportID))
        try assertFailed(failed)
    }

    @MainActor
    func testShareAccountingStartsOnlyAfterPresentationAndNeverMutatesDelivery() async throws {
        let harness = try await makeHarness("share-counter")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let diagnostics = DiagnosticsStore(applicationSupportURL: harness.applicationSupportURL)
        await diagnostics.prepare()
        let coordinator = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            diagnosticsStore: diagnostics
        )
        let delivery = try coordinator.loadReadyReport(id: Fixture.reportID)
        let authority = try immutableAuthority(in: harness)
        let pdf = try Data(contentsOf: finalURL(in: harness))

        let document = ReportPDFDocument(data: delivery.pdfData)
        let wrapper = document.exportedFileWrapper()
        let exported = try XCTUnwrap(wrapper.regularFileContents)
        XCTAssertEqual(exported, delivery.pdfData)
        XCTAssertEqual(exported.sha256, delivery.pdfSHA256)

        let payload = ReportSharePayload(delivery: delivery)
        XCTAssertEqual(payload.itemProvider.suggestedName, delivery.filename)
        XCTAssertTrue(
            payload.itemProvider.hasItemConformingToTypeIdentifier(
                UTType.pdf.identifier
            )
        )
        let shared: Data = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            _ = payload.itemProvider.loadDataRepresentation(
                forTypeIdentifier: UTType.pdf.identifier
            ) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: error ?? RecoveryFixtureError.couldNotCreateImage
                    )
                }
            }
        }
        XCTAssertEqual(shared, delivery.pdfData)
        XCTAssertEqual(shared.sha256, delivery.pdfSHA256)

        let beforePresentation = await diagnostics.snapshot()
        XCTAssertEqual(beforePresentation.reportShareSheetPresented, 0)
        XCTAssertEqual(try coordinator.loadReadyReport(id: Fixture.reportID), delivery)
        let beforePresentationAgain = await diagnostics.snapshot()
        XCTAssertEqual(beforePresentationAgain.reportShareSheetPresented, 0)
        let shareController = ReportShareSheet(
            delivery: delivery,
            coordinator: coordinator
        ).makeController()
        let beforeAppearance = await diagnostics.snapshot()
        XCTAssertEqual(beforeAppearance.reportShareSheetPresented, 0)
        shareController.viewDidAppear(false)
        shareController.viewDidAppear(false)
        for _ in 0..<10 {
            await Task.yield()
            if (await diagnostics.snapshot()).reportShareSheetPresented == 1 {
                break
            }
        }
        let afterPresentation = await diagnostics.snapshot()
        XCTAssertEqual(afterPresentation.reportShareSheetPresented, 1)
        XCTAssertEqual(try immutableAuthority(in: harness), authority)
        XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), pdf)
    }

    @MainActor
    func testSharePresentationThatNeverAppearsKeepsCounterZeroAndAuthorityImmutable() async throws {
        let harness = try await makeHarness("share-not-presented")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let diagnostics = DiagnosticsStore(applicationSupportURL: harness.applicationSupportURL)
        await diagnostics.prepare()
        let coordinator = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            diagnosticsStore: diagnostics
        )
        let delivery = try coordinator.loadReadyReport(id: Fixture.reportID)
        let authority = try immutableAuthority(in: harness)
        let pdf = try Data(contentsOf: finalURL(in: harness))

        // Controller creation and pre-appearance lifecycle are not a presentation.
        let controller = ReportShareSheet(
            delivery: delivery,
            coordinator: coordinator
        ).makeController()
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        for _ in 0..<3 { await Task.yield() }

        let afterFailedPresentation = await diagnostics.snapshot()
        XCTAssertEqual(afterFailedPresentation.reportShareSheetPresented, 0)
        XCTAssertEqual(try immutableAuthority(in: harness), authority)
        XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), pdf)
        XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path))
    }

    @MainActor
    func testOnlyReadyReportRequiresExactlyOneSignOwnedCandidate() async throws {
        let harness = try await makeHarness("exact-one")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let coordinator = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        XCTAssertEqual(
            try coordinator.onlyReadyReport(assetID: Fixture.assetID)?.reportID,
            Fixture.reportID
        )
        XCTAssertNil(try coordinator.onlyReadyReport(assetID: UUID()))

        let secondID = UUID(uuidString: "42000000-0000-0000-0000-000000000099")!
        harness.context.insert(Report(
            id: secondID,
            packetID: harness.report.packetID,
            sourceRecordID: harness.report.sourceRecordID,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(secondID.uuidString.lowercased()).json",
            snapshotSHA256: harness.report.snapshotSHA256,
            pdfState: .ready,
            pdfRelativePath: "pdfs/\(secondID.uuidString.lowercased()).pdf",
            pdfSHA256: harness.report.pdfSHA256,
            createdAt: harness.report.createdAt.addingTimeInterval(1),
            replacesReportID: nil
        ))
        try harness.context.save()
        XCTAssertNil(try coordinator.onlyReadyReport(assetID: Fixture.assetID))
        XCTAssertThrowsError(try coordinator.loadReadyReport(id: Fixture.reportID))
    }

    @MainActor
    func testCollidingPendingAuthorityFailsBeforeRenderOrMutation() async throws {
        let harness = try await makeHarness("pending-collision")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        try resetToPending(harness)
        let collisionID = UUID(uuidString: "42000000-0000-0000-0000-000000000098")!
        harness.context.insert(Report(
            id: collisionID,
            packetID: harness.report.packetID,
            sourceRecordID: harness.report.sourceRecordID,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(collisionID.uuidString.lowercased()).json",
            snapshotSHA256: harness.report.snapshotSHA256,
            pdfState: .failed,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: harness.report.createdAt.addingTimeInterval(1),
            replacesReportID: nil
        ))
        try harness.context.save()
        let before = try immutableAuthority(in: harness)
        let coordinator = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )

        XCTAssertThrowsError(try coordinator.prepareFinalizedReport(id: Fixture.reportID))
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.pending.rawValue)
        XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path))
        XCTAssertFalse(fileManager.fileExists(atPath: finalURL(in: harness).path))
        XCTAssertEqual(try immutableAuthority(in: harness), before)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<Report>()), 2)
    }

    @MainActor
    func testUnknownAndBrokenAuthorityNeverLoadsExportsMutatesOrTouchesUnownedPaths() async throws {
        for testCase in AuthorityNegativeCase.allCases {
            let harness = try await makeHarness("authority-negative-\(testCase)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let unownedURL = harness.applicationSupportURL.appendingPathComponent(
                "unowned-authority-sentinel.bin"
            )
            let unowned = Data("unowned authority sentinel".utf8)
            try unowned.write(to: unownedURL)

            switch testCase {
            case .unknownReportSchema:
                harness.report.schemaVersion = 2
            case .unknownTemplate:
                harness.source.pdfTemplateID = "unknown.template"
            case .brokenPacketSource:
                harness.packet.currentRecordID = UUID()
            case .brokenSourcePacket:
                harness.source.packetID = UUID()
            case .brokenEffectiveRevision:
                harness.source.evidenceSourceRecordID = UUID()
            }
            try harness.context.save()

            let rejectedAuthority = try immutableAuthority(in: harness)
            let cachedPDF = try Data(contentsOf: finalURL(in: harness))
            let coordinator = try ReportDeliveryCoordinator(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL
            )

            XCTAssertThrowsError(
                try coordinator.loadReadyReport(id: Fixture.reportID),
                "\(testCase) must not produce an exportable delivery"
            )
            XCTAssertEqual(try immutableAuthority(in: harness), rejectedAuthority)
            XCTAssertEqual(try Data(contentsOf: finalURL(in: harness)), cachedPDF)
            XCTAssertEqual(try Data(contentsOf: unownedURL), unowned)
            XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path))
        }
    }

    @MainActor
    func testUnsafeEvidencePDFAndCanonicalAncestorNeverLoadExportMutateOrFollowLinks() async throws {
        for testCase in FilesystemNegativeCase.allCases {
            let harness = try await makeHarness("filesystem-negative-\(testCase)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let evidence = try XCTUnwrap(
                try harness.context.fetch(FetchDescriptor<EvidenceFile>())
                    .sorted { $0.purposeKey < $1.purposeKey }
                    .first
            )
            let originalURL = harness.session.generationRootURL.appendingPathComponent(
                evidence.relativePath
            )
            let originalBytes = try Data(contentsOf: originalURL)
            let unownedSentinelURL = harness.applicationSupportURL.appendingPathComponent(
                "unowned-filesystem-sentinel.bin"
            )
            let unownedSentinel = Data("unowned filesystem sentinel".utf8)
            try unownedSentinel.write(to: unownedSentinelURL)
            let authority = try immutableAuthority(in: harness)

            let linkURL: URL?
            let retainedURL: URL?
            switch testCase {
            case .evidenceLeafSymlink:
                let retained = harness.applicationSupportURL.appendingPathComponent(
                    "unowned-evidence-original.bin"
                )
                try fileManager.moveItem(at: originalURL, to: retained)
                try fileManager.createSymbolicLink(
                    at: originalURL,
                    withDestinationURL: retained
                )
                linkURL = originalURL
                retainedURL = retained
            case .pdfLeafDirectory:
                try fileManager.removeItem(at: finalURL(in: harness))
                try fileManager.createDirectory(
                    at: finalURL(in: harness),
                    withIntermediateDirectories: false
                )
                linkURL = nil
                retainedURL = nil
            case .evidenceAncestorSymlink:
                let components = evidence.relativePath.split(separator: "/")
                let rootName = try XCTUnwrap(components.first.map(String.init))
                let canonicalRoot = harness.session.generationRootURL.appendingPathComponent(
                    rootName,
                    isDirectory: true
                )
                let retained = harness.applicationSupportURL.appendingPathComponent(
                    "unowned-evidence-root",
                    isDirectory: true
                )
                try fileManager.moveItem(at: canonicalRoot, to: retained)
                try fileManager.createSymbolicLink(
                    at: canonicalRoot,
                    withDestinationURL: retained
                )
                linkURL = canonicalRoot
                retainedURL = retained.appendingPathComponent(
                    components.dropFirst().joined(separator: "/")
                )
            }

            let coordinator = try ReportDeliveryCoordinator(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL
            )
            XCTAssertThrowsError(
                try coordinator.loadReadyReport(id: Fixture.reportID),
                "\(testCase) must not produce an exportable delivery"
            )
            XCTAssertEqual(try immutableAuthority(in: harness), authority)
            XCTAssertEqual(try Data(contentsOf: unownedSentinelURL), unownedSentinel)
            XCTAssertFalse(fileManager.fileExists(atPath: stageURL(in: harness).path))

            if let linkURL, let retainedURL {
                XCTAssertEqual(
                    try fileManager.attributesOfItem(atPath: linkURL.path)[.type]
                        as? FileAttributeType,
                    .typeSymbolicLink
                )
                XCTAssertEqual(try Data(contentsOf: retainedURL), originalBytes)
            } else {
                XCTAssertTrue(
                    (try finalURL(in: harness).resourceValues(
                        forKeys: [.isDirectoryKey]
                    )).isDirectory == true
                )
            }
        }
    }

    @MainActor
    func testMalformedReadyAuthorityNeverLoadsOrExports() async throws {
        for testCase in [UnsafeCase.readyMissing, .readyMismatch, .readyWithStage,
                         .noncanonicalReadyPath, .uppercaseReadyHash,
                         .corruptSnapshotBytes,
                         .snapshotAncestorSymlink] {
            let harness = try await makeHarness("invalid-\(testCase)")
            defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
            let sentinel = Data("untrusted cached bytes".utf8)
            try configure(testCase, sentinel: sentinel, in: harness)
            let before = try immutableAuthority(in: harness)
            let coordinator = try ReportDeliveryCoordinator(
                modelContext: harness.context,
                generationRootURL: harness.session.generationRootURL
            )
            XCTAssertThrowsError(try coordinator.loadReadyReport(id: Fixture.reportID))
            XCTAssertEqual(try immutableAuthority(in: harness), before)
        }

        let canonical = try await makeHarness("canonical-snapshot-mismatch")
        defer { try? fileManager.removeItem(at: canonical.applicationSupportURL) }
        let snapshotURL = canonical.session.generationRootURL.appendingPathComponent(
            canonical.report.snapshotRelativePath
        )
        let original = try ReportSnapshotEncoderV1().decode(Data(contentsOf: snapshotURL))
        let tampered = ReportSnapshotV1(
            acknowledgements: original.acknowledgements,
            asset: original.asset,
            couldNotVerify: original.couldNotVerify,
            disclaimer: original.disclaimer,
            display: original.display,
            evidence: original.evidence,
            evidenceSourceRecordID: original.evidenceSourceRecordID,
            history: original.history,
            issues: original.issues,
            note: original.note,
            outcome: "visible_issue",
            pack: original.pack,
            packetID: original.packetID,
            pdfTemplate: original.pdfTemplate,
            reportID: original.reportID,
            site: original.site,
            snapshotCreatedAt: original.snapshotCreatedAt,
            snapshotSchemaVersion: original.snapshotSchemaVersion,
            sourceApp: original.sourceApp,
            sourceRecordID: original.sourceRecordID,
            stableRootID: original.stableRootID,
            stage: original.stage,
            timeContext: original.timeContext
        )
        let tamperedBytes = try ReportSnapshotEncoderV1().encode(tampered).data
        let readyPath = try XCTUnwrap(canonical.report.pdfRelativePath)
        let readyHash = try XCTUnwrap(canonical.report.pdfSHA256)
        let sourceRecordID = canonical.report.sourceRecordID
        let createdAt = canonical.report.createdAt
        canonical.context.delete(canonical.report)
        try canonical.context.save()
        try tamperedBytes.write(to: snapshotURL)
        canonical.context.insert(Report(
            id: Fixture.reportID,
            packetID: Fixture.packetID,
            sourceRecordID: sourceRecordID,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(Fixture.reportID.uuidString.lowercased()).json",
            snapshotSHA256: tamperedBytes.sha256,
            pdfState: .ready,
            pdfRelativePath: readyPath,
            pdfSHA256: readyHash,
            createdAt: createdAt,
            replacesReportID: nil
        ))
        try canonical.context.save()
        let canonicalCoordinator = try ReportDeliveryCoordinator(
            modelContext: canonical.context,
            generationRootURL: canonical.session.generationRootURL
        )
        XCTAssertThrowsError(try canonicalCoordinator.loadReadyReport(id: Fixture.reportID))

        let dirty = try await makeHarness("dirty-context")
        defer { try? fileManager.removeItem(at: dirty.applicationSupportURL) }
        let dirtyCoordinator = try ReportDeliveryCoordinator(
            modelContext: dirty.context,
            generationRootURL: dirty.session.generationRootURL
        )
        dirty.report.pdfRelativePath = "pdfs/not-authoritative.pdf"
        XCTAssertThrowsError(try dirtyCoordinator.loadReadyReport(id: Fixture.reportID)) {
            XCTAssertEqual($0 as? ReportDeliveryCoordinatorError, .contextHasChanges)
        }
        dirty.context.rollback()
    }
}

private final class C27S43TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension S4_3ReportDeliveryTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension S4_3ReportDeliveryTests {
    func testV23P03C17IntegrationEventsAreNotReportOrDeliveryTruth() throws {
        XCTAssertNoThrow(try IntegrationProjectionReportExclusionV1.validate())
        XCTAssertFalse(IntegrationProjectionSchemaV1.canonicalReportSource)
        XCTAssertFalse(IntegrationProjectionSchemaV1.canonicalExportIncluded)
    }
}

private enum NonReadyPresence: CaseIterable { case absent, stageOnly, finalOnly }
private enum AuthorityNegativeCase: CaseIterable {
    case unknownReportSchema
    case unknownTemplate
    case brokenPacketSource
    case brokenSourcePacket
    case brokenEffectiveRevision
}
private enum FilesystemNegativeCase: CaseIterable {
    case evidenceLeafSymlink
    case pdfLeafDirectory
    case evidenceAncestorSymlink
}
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
    let reportSchemaVersion: Int
    let snapshot: Data
    let snapshotPath: String
    let snapshotSHA256: String
    let packetID: UUID
    let sourceRecordID: UUID
    let sourcePacketID: UUID?
    let sourceEvidenceSourceRecordID: UUID?
    let sourcePDFTemplateID: String
    let stableRootID: UUID
    let packetCurrentRecordID: UUID?
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

private extension S4_3ReportDeliveryTests {
    var finalRelativePath: String { "pdfs/\(Fixture.reportID.uuidString.lowercased()).pdf" }

    @MainActor
    func makeHarness(_ label: String) async throws -> RecoveryHarness {
        let applicationSupport = fileManager.temporaryDirectory.appendingPathComponent(
            "S4_3ReportDeliveryTests-\(label)-\(UUID().uuidString)",
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
        guard case .ready = try coordinator.prepareReportDelivery(result: result) else {
            throw RecoveryFixtureError.couldNotCreateImage
        }
        let report = try XCTUnwrap(context.fetch(FetchDescriptor<Report>()).first)
        let packet = try XCTUnwrap(context.fetch(FetchDescriptor<Packet>()).first)
        XCTAssertEqual(report.pdfState, ReportPDFState.ready.rawValue)
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
    func resetToPending(_ harness: RecoveryHarness) throws {
        if fileManager.fileExists(atPath: finalURL(in: harness).path) {
            try fileManager.removeItem(at: finalURL(in: harness))
        }
        if fileManager.fileExists(atPath: stageURL(in: harness).path) {
            try fileManager.removeItem(at: stageURL(in: harness))
        }
        harness.report.pdfState = ReportPDFState.pending.rawValue
        harness.report.pdfRelativePath = nil
        harness.report.pdfSHA256 = nil
        try harness.context.save()
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
            reportSchemaVersion: harness.report.schemaVersion,
            snapshot: try Data(contentsOf: harness.session.generationRootURL.appendingPathComponent(harness.report.snapshotRelativePath)),
            snapshotPath: harness.report.snapshotRelativePath,
            snapshotSHA256: harness.report.snapshotSHA256,
            packetID: harness.report.packetID,
            sourceRecordID: harness.report.sourceRecordID,
            sourcePacketID: harness.source.packetID,
            sourceEvidenceSourceRecordID: harness.source.evidenceSourceRecordID,
            sourcePDFTemplateID: harness.source.pdfTemplateID,
            stableRootID: harness.packet.stableRootID,
            packetCurrentRecordID: harness.packet.currentRecordID,
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
            if fileManager.fileExists(atPath: finalURL(in: harness).path) {
                try fileManager.removeItem(at: finalURL(in: harness))
            }
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

extension S4_3ReportDeliveryTests {
    func testV23P03C18ReportAndOpenJSONSandboxChecksAreTyped() throws {
        let required: Set<PackageSandboxCheckKindV1> = [.reportPDF, .openJSON, .export]
        XCTAssertTrue(required.isSubset(of: Set(PackageSandboxCheckKindV1.allCases)))
        XCTAssertTrue(PackageEvolutionLifecycleV1.exportReportRequired)
    }
}

extension S4_3ReportDeliveryTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension S4_3ReportDeliveryTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(FieldReferenceLicenseScopeV1.allCases.count, 4)
        XCTAssertEqual(FieldReferenceLicenseScopeV1.citationAndExportAllowed.rawValue, "CITATION_AND_EXPORT_ALLOWED")
        XCTAssertFalse(FieldReferencePackLifecycleV1.drmOrAccountRequired)
    }
}
extension S4_3ReportDeliveryTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.semanticDiffPersistence, "NONPERSISTENT")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.adoptionPreviewPersistence, "NONPERSISTENT")
    }
}
extension S4_3ReportDeliveryTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S4_3ReportDeliveryTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS43ReportDeliveryTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorS43ReportDelivery: XCTestCase {
    func testC33S43ReportDeliveryCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "report.temporal-accessible-link",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "report.temporal-accessible-link",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS43ReportDelivery: XCTestCase {
    func testC32S43ReportDeliveryCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .report,
            fieldID: "delivery.exclude-proposal",
            value: .singleOption("NOT_DELIVERED")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .report,
            fieldID: "delivery.exclude-proposal",
            valueKind: .singleOption
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}

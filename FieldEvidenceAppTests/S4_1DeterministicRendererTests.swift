import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PDFKit
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_S4_1DeterministicRendererTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45DeterministicRendererCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityReusesSoleDeterministicRendererPolicy() {
        XCTAssertEqual(DeterministicPDFRendererV1.assetLabelRendererID, "deterministic-pdf-renderer-v1")
        XCTAssertEqual(DeterministicPDFRendererV1.assetLabelQuietZoneModules, 4)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelInterpolationEnabled)
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelOverlaidLogoEnabled)
    }
}

private final class C51S41DeterministicRendererAnchorTests: XCTestCase {
    func testV23P03C51AdvancedScheduleRendererUsesTypedFrozenProjection() {
        let render: (AdvancedScheduleReportProjectionV1, String) throws -> ReportProjectionOutputV1 =
            DeterministicOpenJSONRendererV1.renderAdvancedSchedule
        _ = render
        XCTAssertEqual(AdvancedScheduleReportProjectionV1.projectionVersion,
                       "ADVANCED_SCHEDULE_REPORT_PROJECTION_V1")
        XCTAssertTrue(AdvancedScheduleReportProjectionPolicyV1.sourceTruthIsFrozen)
    }
}

private final class C30EvidenceContextAnchorS4_1DeterministicRenderer: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S4_1DeterministicRendererTests: XCTestCase {
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
    func testServiceProducesByteIdenticalReadyPDFsAcrossCleanRootsAndDeviceZones() throws {
        let first = try makeHarness(label: "determinism-a")
        let second = try makeHarness(label: "determinism-b")
        defer {
            try? fileManager.removeItem(at: first.applicationSupportURL)
            try? fileManager.removeItem(at: second.applicationSupportURL)
            withExtendedLifetime((first.session, second.session)) {}
        }

        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        let firstValidated = try SnapshotValidatorV1(
            modelContext: first.session.modelContext,
            generationRootURL: first.session.generationRootURL
        ).validate(report: first.report)
        let expectedReferencedBytes = first.evidenceRows.reduce(Int64(0)) { partial, row in
            partial + Int64(
                row.id == Fixture.currentWideID ? row.byteCount : row.thumbnailByteCount
            )
        }
        XCTAssertEqual(firstValidated.referencedImageByteCount, expectedReferencedBytes)
        let independentlyRendered = try WorklightPDFRendererV1().render(firstValidated)
        XCTAssertEqual(independentlyRendered.pageCount, 2)
        try assertInspectionContract(independentlyRendered.inspection)
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let firstResult = try first.service.renderPendingReport(id: Fixture.reportID)
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let secondResult = try second.service.renderPendingReport(id: Fixture.reportID)

        let firstPDF = try Data(contentsOf: first.session.generationRootURL.appendingPathComponent(firstResult.pdfRelativePath))
        let secondPDF = try Data(contentsOf: second.session.generationRootURL.appendingPathComponent(secondResult.pdfRelativePath))
        XCTAssertEqual(firstPDF, independentlyRendered.data)
        XCTAssertEqual(firstPDF, secondPDF)
        XCTAssertEqual(firstResult.pdfSHA256, sha256(firstPDF))
        XCTAssertEqual(firstResult.pdfSHA256, secondResult.pdfSHA256)
        XCTAssertEqual(firstResult.pdfRelativePath, "pdfs/\(Fixture.reportID.uuidString.lowercased()).pdf")
        try assertReadyAuthority(in: first, result: firstResult)
        try assertReadyAuthority(in: second, result: secondResult)
        try assertIndependentPDFContract(
            firstPDF,
            expectedPageCount: firstResult.pageCount,
            snapshotSHA256: firstValidated.snapshotSHA256
        )
        XCTAssertThrowsError(try first.service.renderPendingReport(id: Fixture.reportID)) {
            XCTAssertEqual($0 as? ReportRenderServiceError, .reportNotPending)
        }
        XCTAssertEqual(
            try Data(contentsOf: first.session.generationRootURL.appendingPathComponent(firstResult.pdfRelativePath)),
            firstPDF
        )
        attach(firstPDF, name: "S4.1 deterministic PDF root A")
        attach(secondPDF, name: "S4.1 deterministic PDF root B")
    }

    @MainActor
    func testValidatorRejectsFocusedCorruptionWithoutCreatingPDF() throws {
        let harness = try makeHarness(label: "validator")
        defer {
            try? fileManager.removeItem(at: harness.applicationSupportURL)
            withExtendedLifetime(harness.session) {}
        }
        let validator = try SnapshotValidatorV1(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL
        )
        XCTAssertNoThrow(try validator.validate(report: harness.report))

        let snapshotURL = harness.session.generationRootURL.appendingPathComponent(
            harness.report.snapshotRelativePath
        )
        let canonicalSnapshot = try Data(contentsOf: snapshotURL)
        var corruptSnapshot = canonicalSnapshot
        corruptSnapshot.append(0x0a)
        try corruptSnapshot.write(to: snapshotURL)
        XCTAssertThrowsError(try validator.validate(report: harness.report)) {
            XCTAssertEqual($0 as? SnapshotValidationErrorV1, .invalidAuthority)
        }
        try canonicalSnapshot.write(to: snapshotURL)

        let wide = try XCTUnwrap(harness.evidenceRows.first { $0.id == Fixture.currentWideID })
        let originalPath = wide.relativePath
        wide.relativePath = "evidence/../escape/original.jpg"
        XCTAssertThrowsError(try validator.validate(report: harness.report)) {
            XCTAssertEqual($0 as? SnapshotValidationErrorV1, .invalidAuthority)
        }
        harness.session.modelContext.rollback()
        wide.relativePath = originalPath
        XCTAssertEqual(wide.relativePath, originalPath)

        let source = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<WorkflowRecord>())
                .first { $0.id == Fixture.recheckID }
        )
        let originalTemplateVersion = source.pdfTemplateVersion
        source.pdfTemplateVersion = 2
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        source.pdfTemplateVersion = originalTemplateVersion

        let packet = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<Packet>())
                .first { $0.id == Fixture.packetID }
        )
        let originalCurrentRecordID = packet.currentRecordID
        packet.currentRecordID = Fixture.checkID
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        packet.currentRecordID = originalCurrentRecordID

        let work = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<WorkflowRecord>())
                .first { $0.id == Fixture.workID }
        )
        let originalWorkCompletedAt = work.completedAt
        work.completedAt = Fixture.snapshotDate.addingTimeInterval(1)
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        work.completedAt = originalWorkCompletedAt

        let originalMIMEType = wide.mimeType
        wide.mimeType = "image/png"
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        wide.mimeType = originalMIMEType

        let originalRecordID = wide.recordID
        wide.recordID = Fixture.checkID
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        wide.recordID = originalRecordID

        let originalByteCount = wide.byteCount
        wide.byteCount += 1
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        wide.byteCount = originalByteCount

        let originalSHA256 = wide.sha256
        wide.sha256 = String(repeating: "f", count: 64)
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        wide.sha256 = originalSHA256

        let originalThumbnailByteCount = wide.thumbnailByteCount
        wide.thumbnailByteCount += 1
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        wide.thumbnailByteCount = originalThumbnailByteCount

        let originalThumbnailSHA256 = wide.thumbnailSHA256
        wide.thumbnailSHA256 = String(repeating: "e", count: 64)
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()
        wide.thumbnailSHA256 = originalThumbnailSHA256

        let duplicateID = UUID(uuidString: "41000000-0000-0000-0000-000000000099")!
        let duplicate = EvidenceFile(
            id: duplicateID,
            recordID: Fixture.recheckID,
            purposeKey: "wide_context",
            relativePath: "evidence/\(duplicateID.uuidString.lowercased())/original.jpg",
            mimeType: "image/jpeg",
            byteCount: wide.byteCount,
            sha256: wide.sha256,
            createdAt: wide.createdAt,
            thumbnailRelativePath: "evidence/\(duplicateID.uuidString.lowercased())/thumbnail.jpg",
            thumbnailByteCount: wide.thumbnailByteCount,
            thumbnailSHA256: wide.thumbnailSHA256
        )
        harness.session.modelContext.insert(duplicate)
        assertValidatorFails(validator, report: harness.report)
        harness.session.modelContext.rollback()

        let originalURL = harness.session.generationRootURL.appendingPathComponent(originalPath)
        let originalBytes = try Data(contentsOf: originalURL)
        var corruptJPEG = originalBytes
        corruptJPEG[0] ^= 0xff
        try corruptJPEG.write(to: originalURL)
        assertValidatorFails(validator, report: harness.report)
        try originalBytes.write(to: originalURL)

        let thumbnailURL = harness.session.generationRootURL.appendingPathComponent(
            wide.thumbnailRelativePath
        )
        let thumbnailBytes = try Data(contentsOf: thumbnailURL)
        try fileManager.removeItem(at: thumbnailURL)
        assertValidatorFails(validator, report: harness.report)
        try thumbnailBytes.write(to: thumbnailURL)

        var corruptThumbnail = thumbnailBytes
        corruptThumbnail[0] ^= 0xff
        try corruptThumbnail.write(to: thumbnailURL)
        assertValidatorFails(validator, report: harness.report)
        try thumbnailBytes.write(to: thumbnailURL)

        let symlinkTarget = originalURL.deletingLastPathComponent()
            .appendingPathComponent("validator-symlink-target.jpg")
        try fileManager.moveItem(at: originalURL, to: symlinkTarget)
        try fileManager.createSymbolicLink(at: originalURL, withDestinationURL: symlinkTarget)
        assertValidatorFails(validator, report: harness.report)
        try fileManager.removeItem(at: originalURL)
        try fileManager.moveItem(at: symlinkTarget, to: originalURL)

        XCTAssertFalse(fileManager.fileExists(atPath: finalPDFURL(in: harness).path))
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.pending.rawValue)
        XCTAssertNil(harness.report.pdfRelativePath)
        XCTAssertNil(harness.report.pdfSHA256)
    }

    @MainActor
    func testCapacityOverflowAndUnexpectedStageOrFinalFailClosed() throws {
        let exactRequired = 2_468 + StoragePreflightService.pdfOperationAllowanceBytes
            + StoragePreflightService.reserveBytes
        XCTAssertEqual(try StoragePreflightService().pdfRequiredBytes(referencedImageByteCount: 1_234), exactRequired)
        XCTAssertNoThrow(
            try StoragePreflightService(capacityProvider: { _ in exactRequired })
                .checkPDFGeneration(
                    referencedImageByteCount: 1_234,
                    onVolumeContaining: fileManager.temporaryDirectory
                )
        )
        XCTAssertThrowsError(
            try StoragePreflightService(capacityProvider: { _ in exactRequired - 1 })
                .checkPDFGeneration(
                    referencedImageByteCount: 1_234,
                    onVolumeContaining: fileManager.temporaryDirectory
                )
        ) {
            XCTAssertEqual(
                $0 as? StoragePreflightError,
                .insufficientCapacity(
                    requiredBytes: exactRequired,
                    availableBytes: exactRequired - 1
                )
            )
        }
        XCTAssertThrowsError(
            try StoragePreflightService().pdfRequiredBytes(referencedImageByteCount: Int64.max)
        ) {
            XCTAssertEqual($0 as? StoragePreflightError, .capacityEstimateOverflow)
        }

        for authority in UnexpectedAuthority.allCases {
            let harness = try makeHarness(
                label: "authority-\(authority)",
                capacity: { _ in Int64.max }
            )
            defer {
                try? fileManager.removeItem(at: harness.applicationSupportURL)
                withExtendedLifetime(harness.session) {}
            }
            let unexpectedURL = authority == .stage
                ? stagingPDFURL(in: harness)
                : finalPDFURL(in: harness)
            try fileManager.createDirectory(
                at: unexpectedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let sentinel = Data("unowned authority".utf8)
            try sentinel.write(to: unexpectedURL)

            XCTAssertThrowsError(try harness.service.renderPendingReport(id: Fixture.reportID)) {
                XCTAssertEqual($0 as? ReportRenderServiceError, .invalidStorageAuthority)
            }
            XCTAssertEqual(try Data(contentsOf: unexpectedURL), sentinel)
            XCTAssertEqual(harness.report.pdfState, ReportPDFState.pending.rawValue)
            XCTAssertNil(harness.report.pdfRelativePath)
            XCTAssertNil(harness.report.pdfSHA256)
        }

        for available in [Int64?.none, Int64?(0)] {
            var observedTarget: URL?
            let harness = try makeHarness(label: "capacity", capacity: {
                observedTarget = $0
                return available
            })
            defer {
                try? fileManager.removeItem(at: harness.applicationSupportURL)
                withExtendedLifetime(harness.session) {}
            }
            XCTAssertThrowsError(try harness.service.renderPendingReport(id: Fixture.reportID))
            XCTAssertEqual(observedTarget, harness.session.generationRootURL)
            XCTAssertEqual(harness.report.pdfState, ReportPDFState.pending.rawValue)
            XCTAssertNil(harness.report.pdfRelativePath)
            XCTAssertNil(harness.report.pdfSHA256)
            XCTAssertFalse(fileManager.fileExists(atPath: stagingPDFURL(in: harness).path))
            XCTAssertFalse(fileManager.fileExists(atPath: finalPDFURL(in: harness).path))
        }
    }
}

private final class C27S41TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertEqual(ExternalKeyNormalizationV1.allCases.count, 2)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension S4_1DeterministicRendererTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

private enum UnexpectedAuthority: CaseIterable { case stage, final }

@MainActor
private struct RenderHarness {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let report: Report
    let evidenceRows: [EvidenceFile]
    let service: ReportRenderService
}

private enum Fixture {
    static let reportID = UUID(uuidString: "41000000-0000-0000-0000-000000000001")!
    static let packetID = UUID(uuidString: "41000000-0000-0000-0000-000000000002")!
    static let stableRootID = UUID(uuidString: "41000000-0000-0000-0000-000000000003")!
    static let siteID = UUID(uuidString: "41000000-0000-0000-0000-000000000004")!
    static let assetID = UUID(uuidString: "41000000-0000-0000-0000-000000000005")!
    static let checkID = UUID(uuidString: "41000000-0000-0000-0000-000000000006")!
    static let workID = UUID(uuidString: "41000000-0000-0000-0000-000000000007")!
    static let recheckID = UUID(uuidString: "41000000-0000-0000-0000-000000000008")!
    static let issueID = UUID(uuidString: "41000000-0000-0000-0000-000000000009")!
    static let currentWideID = UUID(uuidString: "41000000-0000-0000-0000-000000000010")!
    static let historyCloseID = UUID(uuidString: "41000000-0000-0000-0000-000000000011")!
    static let historyWorkID = UUID(uuidString: "41000000-0000-0000-0000-000000000012")!
    static let historyWideID = UUID(uuidString: "41000000-0000-0000-0000-000000000013")!
    static let historicalPacketID = UUID(uuidString: "41000000-0000-0000-0000-000000000014")!
    static let historicalStableRootID = UUID(uuidString: "41000000-0000-0000-0000-000000000015")!
    static let snapshotDate = Date(timeIntervalSince1970: 1_768_420_926)
}

private extension S4_1DeterministicRendererTests {
    @MainActor
    func assertValidatorFails(
        _ validator: SnapshotValidatorV1,
        report: Report,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try validator.validate(report: report), file: file, line: line) {
            XCTAssertEqual(
                $0 as? SnapshotValidationErrorV1,
                .invalidAuthority,
                file: file,
                line: line
            )
        }
    }

    @MainActor
    func makeHarness(
        label: String,
        c42Projection: String? = nil,
        capacity: @escaping StoragePreflightService.CapacityProvider = { _ in Int64.max }
    ) throws -> RenderHarness {
        let appSupport = fileManager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(
            "S4_1DeterministicRendererTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: appSupport)
            .openOrBootstrapCurrent()
        let context = session.modelContext
        let snapshot = try fixtureSnapshotAndRows(in: session, c42Projection: c42Projection)
        context.insert(snapshot.site)
        context.insert(snapshot.asset)
        context.insert(snapshot.check)
        context.insert(snapshot.work)
        context.insert(snapshot.recheck)
        context.insert(snapshot.issue)
        context.insert(snapshot.historicalPacket)
        context.insert(snapshot.packet)
        for row in snapshot.rows { context.insert(row) }
        context.insert(snapshot.report)
        try context.save()

        let encoded = try ReportSnapshotEncoderV1().encode(snapshot.snapshot)
        XCTAssertEqual(encoded.sha256, snapshot.report.snapshotSHA256)
        let snapshotURL = session.generationRootURL.appendingPathComponent(
            snapshot.report.snapshotRelativePath
        )
        try fileManager.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoded.data.write(to: snapshotURL)

        let service = try ReportRenderService(
            modelContext: context,
            generationRootURL: session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: capacity)
        )
        return RenderHarness(
            applicationSupportURL: appSupport,
            session: session,
            report: snapshot.report,
            evidenceRows: snapshot.rows,
            service: service
        )
    }

    @MainActor
    func fixtureSnapshotAndRows(
        in session: StoreGenerationSession,
        c42Projection: String? = nil
    ) throws -> FixtureAuthority {
        let normalizer = MediaNormalizerV1()
        let currentWide = try normalizer.normalize(makePNG(width: 320, height: 180, seed: 17))
        let historyWide = try normalizer.normalize(makePNG(width: 960, height: 540, seed: 31))
        let historyClose = try normalizer.normalize(makePNG(width: 600, height: 900, seed: 43))
        let historyWork = try normalizer.normalize(makePNG(width: 800, height: 480, seed: 79))
        let evidence = [
            try makeEvidence(
                id: Fixture.currentWideID,
                recordID: Fixture.recheckID,
                purpose: "wide_context",
                display: "Wide view",
                media: currentWide,
                createdAt: Date(timeIntervalSince1970: 1_768_420_924),
                root: session.generationRootURL
            ),
            try makeEvidence(
                id: Fixture.historyWideID,
                recordID: Fixture.checkID,
                purpose: "wide_context",
                display: "Wide view",
                media: historyWide,
                createdAt: Date(timeIntervalSince1970: 1_768_420_799),
                root: session.generationRootURL
            ),
            try makeEvidence(
                id: Fixture.historyCloseID,
                recordID: Fixture.checkID,
                purpose: "close_detail",
                display: "Close view",
                media: historyClose,
                createdAt: Date(timeIntervalSince1970: 1_768_420_800),
                root: session.generationRootURL
            ),
            try makeEvidence(
                id: Fixture.historyWorkID,
                recordID: Fixture.workID,
                purpose: "work_context",
                display: "Work photo",
                media: historyWork,
                createdAt: Date(timeIntervalSince1970: 1_768_420_850),
                root: session.generationRootURL
            ),
        ]
        let rows = evidence.map(\.row)
        let site = Site(
            id: Fixture.siteID,
            label: "North Campus",
            address: c42Projection ?? "10 Main",
            timeZoneID: "America/New_York",
            createdAt: Date(timeIntervalSince1970: 1_768_420_700)
        )
        let asset = Asset(
            id: Fixture.assetID,
            siteID: site.id,
            packID: "field.evidence.illuminated_sign.v1",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Monument Sign",
            createdAt: Date(timeIntervalSince1970: 1_768_420_701)
        )
        let check = makeRecord(
            id: Fixture.checkID,
            parentID: nil,
            stage: .check,
            outcome: "visible_issue",
            completedAt: Date(timeIntervalSince1970: 1_768_420_810),
            issueID: Fixture.issueID,
            workDate: nil,
            workDescription: nil
        )
        let work = makeRecord(
            id: Fixture.workID,
            parentID: check.id,
            stage: .work,
            outcome: "work_recorded",
            completedAt: Date(timeIntervalSince1970: 1_768_420_860),
            issueID: Fixture.issueID,
            workDate: "2026-01-14",
            workDescription: "Replaced the sign power supply."
        )
        let recheck = makeRecord(
            id: Fixture.recheckID,
            parentID: work.id,
            stage: .recheck,
            outcome: "could_not_verify",
            completedAt: Fixture.snapshotDate,
            issueID: Fixture.issueID,
            workDate: nil,
            workDescription: nil
        )
        let issue = Issue(
            id: Fixture.issueID,
            assetID: asset.id,
            openedByRecordID: check.id,
            labelKey: "dark_section",
            labelDisplaySnapshot: "Section appears dark",
            status: .recheckDue,
            resolvedByRecordID: nil,
            createdAt: Date(timeIntervalSince1970: 1_768_420_810),
            updatedAt: Date(timeIntervalSince1970: 1_768_420_860)
        )
        let packet = Packet(
            id: Fixture.packetID,
            stableRootID: Fixture.stableRootID,
            currentRecordID: recheck.id,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_768_420_700)
        )
        let historicalPacket = Packet(
            id: Fixture.historicalPacketID,
            stableRootID: Fixture.historicalStableRootID,
            currentRecordID: check.id,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_768_420_700)
        )
        let snapshot = ReportSnapshotV1(
            acknowledgements: acknowledgements(),
            asset: AssetSnapshotV1(label: asset.label),
            couldNotVerify: CouldNotVerifySnapshotV1(
                display: "Required view is blocked",
                key: "required_view_obstructed",
                registryVersion: "cnv.reason.en-US.v1"
            ),
            disclaimer: "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification.",
            display: DisplaySnapshotV1(
                assetSingular: "sign",
                checkSingular: "check",
                issueSingular: "visible issue",
                outcome: "Could not verify",
                stage: "Recheck"
            ),
            evidence: evidence.map(\.snapshot),
            evidenceSourceRecordID: recheck.id,
            history: [
                historySnapshot(check, evidenceIDs: [Fixture.historyWideID, Fixture.historyCloseID], stageDisplay: "Check", outcomeDisplay: "Visible issue"),
                historySnapshot(work, evidenceIDs: [Fixture.historyWorkID], stageDisplay: "Work", outcomeDisplay: "Work recorded"),
            ],
            issues: [IssueSnapshotV1(
                createdAt: issue.createdAt,
                display: issue.labelDisplaySnapshot,
                issueID: issue.id,
                key: issue.labelKey,
                openedByRecordID: issue.openedByRecordID,
                resolvedByRecordID: nil,
                status: IssueStatus.recheckDue.rawValue,
                updatedAt: work.completedAt!
            )],
            note: "Access was blocked at the close-view position.",
            outcome: "could_not_verify",
            pack: PackSnapshotV1(contentVersion: 1, id: "field.evidence.illuminated_sign.v1", schemaVersion: 1),
            packetID: packet.id,
            pdfTemplate: PDFTemplateReferenceV1(id: "field.evidence.pdf.worklight.v1", version: 1),
            reportID: Fixture.reportID,
            site: SiteSnapshotV1(address: site.address, label: site.label),
            snapshotCreatedAt: Fixture.snapshotDate,
            snapshotSchemaVersion: 1,
            sourceApp: SourceAppSnapshotV1(build: "41", version: "1.0"),
            sourceRecordID: recheck.id,
            stableRootID: packet.stableRootID,
            stage: "recheck",
            timeContext: TimeContextSnapshotV1(
                localDate: "2026-01-14",
                localTime: "15:02:03",
                observedAtUTC: Date(timeIntervalSince1970: 1_768_420_923),
                timeZoneID: "America/New_York",
                utcOffsetMinutes: -300
            )
        )
        let encoded = try ReportSnapshotEncoderV1().encode(snapshot)
        let report = Report(
            id: Fixture.reportID,
            packetID: packet.id,
            sourceRecordID: recheck.id,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(Fixture.reportID.uuidString.lowercased()).json",
            snapshotSHA256: encoded.sha256,
            pdfState: .pending,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: Fixture.snapshotDate,
            replacesReportID: nil
        )
        return FixtureAuthority(
            site: site,
            asset: asset,
            check: check,
            work: work,
            recheck: recheck,
            issue: issue,
            historicalPacket: historicalPacket,
            packet: packet,
            report: report,
            rows: rows,
            snapshot: snapshot
        )
    }

    func makeRecord(
        id: UUID,
        parentID: UUID?,
        stage: WorkflowStage,
        outcome: String,
        completedAt: Date,
        issueID: UUID?,
        workDate: String?,
        workDescription: String?
    ) -> WorkflowRecord {
        let hasPreflight = stage != .work
        let isCurrentCNV = id == Fixture.recheckID
        return WorkflowRecord(
            id: id,
            assetID: Fixture.assetID,
            packetID: stage == .work
                ? nil
                : (id == Fixture.recheckID ? Fixture.packetID : Fixture.historicalPacketID),
            issueID: issueID,
            parentRecordID: parentID,
            recordRevisionRootID: id,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: stage,
            state: .completed,
            draftStepKey: nil,
            startedAt: completedAt.addingTimeInterval(-120),
            completedAt: completedAt,
            observedAtUTC: hasPreflight ? Date(timeIntervalSince1970: 1_768_420_923) : nil,
            timeZoneID: hasPreflight ? "America/New_York" : nil,
            utcOffsetMinutes: hasPreflight ? -300 : nil,
            localDate: hasPreflight ? "2026-01-14" : nil,
            localTime: hasPreflight ? "15:02:03" : nil,
            afterDarkAcknowledgementKey: hasPreflight ? "after_dark" : nil,
            afterDarkAcknowledgementCopy: hasPreflight ? "It is dark enough to observe the sign's visible illumination." : nil,
            afterDarkAcknowledgementVersion: hasPreflight ? "preflight.ack.en-US.v1" : nil,
            afterDarkAcknowledgementAccepted: hasPreflight ? true : nil,
            safePositionAcknowledgementKey: hasPreflight ? "safe_authorized_position" : nil,
            safePositionAcknowledgementCopy: hasPreflight ? "I am in a safe, authorized position to take these photos." : nil,
            safePositionAcknowledgementVersion: hasPreflight ? "preflight.ack.en-US.v1" : nil,
            safePositionAcknowledgementAccepted: hasPreflight ? true : nil,
            packID: "field.evidence.illuminated_sign.v1",
            packSchemaVersion: 1,
            packContentVersion: 1,
            pdfTemplateID: "field.evidence.pdf.worklight.v1",
            pdfTemplateVersion: 1,
            outcomeKey: outcome,
            couldNotVerifyKey: isCurrentCNV ? "required_view_obstructed" : nil,
            couldNotVerifyDisplaySnapshot: isCurrentCNV ? "Required view is blocked" : nil,
            couldNotVerifyRegistryVersion: isCurrentCNV ? "cnv.reason.en-US.v1" : nil,
            workPerformedLocalDate: workDate,
            workDescription: workDescription,
            note: isCurrentCNV ? "Access was blocked at the close-view position." : nil,
            finalizationMutationID: UUID(uuidString: id.uuidString.replacingOccurrences(of: "41000000", with: "42000000"))!
        )
    }

    func acknowledgements() -> [AcknowledgementSnapshotV1] {
        [
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
        ]
    }

    func historySnapshot(
        _ record: WorkflowRecord,
        evidenceIDs: [UUID],
        stageDisplay: String,
        outcomeDisplay: String
    ) -> HistoryEntrySnapshotV1 {
        HistoryEntrySnapshotV1(
            completedAt: record.completedAt!,
            couldNotVerify: nil,
            evidenceIDs: evidenceIDs,
            issueIDs: record.issueID.map { [$0] } ?? [],
            note: record.note,
            outcome: record.outcomeKey!,
            outcomeDisplay: outcomeDisplay,
            recordID: record.id,
            stage: record.stage,
            stageDisplay: stageDisplay,
            workDescription: record.workDescription,
            workPerformedLocalDate: record.workPerformedLocalDate
        )
    }

    func makeEvidence(
        id: UUID,
        recordID: UUID,
        purpose: String,
        display: String,
        media: NormalizedMediaV1,
        createdAt: Date,
        root: URL
    ) throws -> EvidenceFixture {
        let canonicalID = id.uuidString.lowercased()
        let originalPath = "evidence/\(canonicalID)/original.jpg"
        let thumbnailPath = "evidence/\(canonicalID)/thumbnail.jpg"
        let directory = root.appendingPathComponent("evidence/\(canonicalID)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try media.originalJPEG.write(to: root.appendingPathComponent(originalPath))
        try media.thumbnailJPEG.write(to: root.appendingPathComponent(thumbnailPath))
        let row = EvidenceFile(
            id: id,
            recordID: recordID,
            purposeKey: purpose,
            relativePath: originalPath,
            mimeType: "image/jpeg",
            byteCount: media.originalJPEG.count,
            sha256: sha256(media.originalJPEG),
            createdAt: createdAt,
            thumbnailRelativePath: thumbnailPath,
            thumbnailByteCount: media.thumbnailJPEG.count,
            thumbnailSHA256: sha256(media.thumbnailJPEG)
        )
        return EvidenceFixture(
            row: row,
            snapshot: EvidenceSnapshotV1(
                byteCount: row.byteCount,
                createdAt: createdAt,
                evidenceID: id,
                mimeType: row.mimeType,
                purposeDisplay: display,
                purposeKey: purpose,
                recordID: recordID,
                relativePath: originalPath,
                sha256: row.sha256,
                thumbnailByteCount: row.thumbnailByteCount,
                thumbnailRelativePath: thumbnailPath,
                thumbnailSHA256: row.thumbnailSHA256
            )
        )
    }

    @MainActor
    func assertReadyAuthority(
        in harness: RenderHarness,
        result: ReportRenderResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(harness.report.pdfState, ReportPDFState.ready.rawValue, file: file, line: line)
        XCTAssertEqual(harness.report.pdfRelativePath, result.pdfRelativePath, file: file, line: line)
        XCTAssertEqual(harness.report.pdfSHA256, result.pdfSHA256, file: file, line: line)
        XCTAssertFalse(fileManager.fileExists(atPath: stagingPDFURL(in: harness).path), file: file, line: line)
        let final = finalPDFURL(in: harness)
        XCTAssertTrue(fileManager.fileExists(atPath: final.path), file: file, line: line)
        XCTAssertEqual(sha256(try Data(contentsOf: final)), result.pdfSHA256, file: file, line: line)
    }

    func assertInspectionContract(
        _ inspection: PDFRenderInspectionV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(inspection.pageRect, CGRect(x: 0, y: 0, width: 612, height: 792), file: file, line: line)
        XCTAssertEqual(inspection.contentRect, CGRect(x: 42, y: 72, width: 528, height: 678), file: file, line: line)
        XCTAssertEqual(inspection.footerRect, CGRect(x: 42, y: 42, width: 528, height: 18), file: file, line: line)
        XCTAssertEqual(inspection.pages.count, 2, file: file, line: line)

        let located = inspection.pages.enumerated().flatMap { page, items in
            items.map { (page: page, item: $0) }
        }
        let allowed = inspection.contentRect.insetBy(dx: -0.01, dy: -0.01)
        for value in located {
            XCTAssertTrue(
                allowed.contains(value.item.rect),
                "\(value.item.role) escaped content: \(value.item.rect)",
                file: file,
                line: line
            )
            guard value.item.kind == .text else { continue }
            let expected: (String, CGFloat, CGFloat)
            if value.item.role == "title" {
                expected = ("Helvetica-Bold", 22, 27)
            } else if value.item.role.hasSuffix(".heading") {
                expected = ("Helvetica-Bold", 15, 18)
            } else if value.item.role.hasSuffix(".caption")
                        || value.item.role.hasSuffix(".summary") {
                expected = ("Helvetica", 8, 11)
            } else {
                expected = ("Helvetica", 10, 14)
            }
            XCTAssertEqual(value.item.fontName, expected.0, file: file, line: line)
            XCTAssertEqual(
                try XCTUnwrap(value.item.fontSize, file: file, line: line),
                expected.1,
                accuracy: 0.001,
                file: file,
                line: line
            )
            XCTAssertEqual(
                try XCTUnwrap(value.item.lineHeight, file: file, line: line),
                expected.2,
                accuracy: 0.001,
                file: file,
                line: line
            )
        }

        func first(_ role: String, kind: PDFRenderInspectionItemV1.Kind? = nil) throws -> (page: Int, item: PDFRenderInspectionItemV1) {
            try XCTUnwrap(located.first {
                $0.item.role == role && (kind == nil || $0.item.kind == kind)
            }, "Missing inspection role \(role)", file: file, line: line)
        }
        func assertGap(_ upperRole: String, _ lowerRole: String, _ expected: CGFloat) throws {
            let upper = try first(upperRole)
            let lower = try first(lowerRole)
            XCTAssertEqual(upper.page, lower.page, file: file, line: line)
            XCTAssertEqual(
                upper.item.rect.minY - lower.item.rect.maxY,
                expected,
                accuracy: 0.001,
                "\(upperRole) → \(lowerRole)",
                file: file,
                line: line
            )
        }

        try assertGap("title", "identity.heading", 30)
        try assertGap("identity.heading", "identity.body", 6)
        try assertGap("identity.body", "current.wide_context.heading", 18)
        try assertGap("current.wide_context.heading", "current.wide_context", 6)
        try assertGap("current.wide_context", "current.wide_context.caption", 4)
        try assertGap("current.close_detail.heading", "current.close_detail.missing", 6)
        try assertGap("result.heading", "result.body", 6)
        try assertGap("issues.heading", "issue.\(Fixture.issueID.uuidString.lowercased())", 6)
        try assertGap("disclaimer.heading", "disclaimer.body", 6)

        let current = try first("current.wide_context", kind: .image)
        XCTAssertEqual(current.item.rect.size, CGSize(width: 320, height: 180), file: file, line: line)
        for value in located where value.item.kind == .image
            && value.item.role.hasPrefix("history.") {
            XCTAssertLessThanOrEqual(value.item.rect.width, 160.001, file: file, line: line)
            XCTAssertLessThanOrEqual(value.item.rect.height, 120.001, file: file, line: line)
        }

        for recordID in [Fixture.checkID, Fixture.workID] {
            let prefix = "history.\(recordID.uuidString.lowercased())"
            let pages = Set(located.filter { $0.item.role.hasPrefix(prefix) }.map(\.page))
            XCTAssertEqual(pages.count, 1, "History row split across pages", file: file, line: line)
        }
        for pair in [
            ("identity.heading", "identity.body"),
            ("current.wide_context.heading", "current.wide_context"),
            ("current.close_detail.heading", "current.close_detail.missing"),
            ("result.heading", "result.body"),
            ("issues.heading", "issue.\(Fixture.issueID.uuidString.lowercased())"),
            ("history.heading", "history.\(Fixture.checkID.uuidString.lowercased()).wide_context"),
            ("disclaimer.heading", "disclaimer.body"),
        ] {
            XCTAssertEqual(try first(pair.0).page, try first(pair.1).page, file: file, line: line)
        }

        let orderedRoles = [
            "title", "identity.heading", "identity.body",
            "current.wide_context.heading", "current.wide_context",
            "current.close_detail.heading", "current.close_detail.missing",
            "result.heading", "result.body", "issues.heading",
            "history.heading", "disclaimer.heading", "disclaimer.body",
        ]
        var previous = -1
        for role in orderedRoles {
            let index = try XCTUnwrap(located.firstIndex { $0.item.role == role }, file: file, line: line)
            XCTAssertGreaterThan(index, previous, "Unexpected render order at \(role)", file: file, line: line)
            previous = index
        }
        XCTAssertEqual(
            try first("current.close_detail.missing").item.text,
            "Not captured — Could not verify",
            file: file,
            line: line
        )
    }

    func assertIndependentPDFContract(
        _ data: Data,
        expectedPageCount: Int,
        snapshotSHA256: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let document = try XCTUnwrap(PDFDocument(data: data), file: file, line: line)
        XCTAssertEqual(document.pageCount, expectedPageCount, file: file, line: line)
        XCTAssertGreaterThan(document.pageCount, 0, file: file, line: line)
        let text = (0..<document.pageCount).compactMap {
            document.page(at: $0)?.string
        }.joined(separator: "\n")
        let orderedTruth = [
            "North Campus",
            "Monument Sign",
            "Wide view",
            "Not captured — Could not verify",
            "Recheck",
            "Could not verify",
            "Required view is blocked",
            "Section appears dark",
            "Work recorded",
            "This report records visible conditions",
        ]
        var prior = text.startIndex
        for value in orderedTruth {
            let range = try XCTUnwrap(text.range(of: value, range: prior..<text.endIndex), file: file, line: line)
            prior = range.upperBound
        }
        XCTAssertEqual(text.components(separatedBy: "Not captured — Could not verify").count - 1, 1, file: file, line: line)
        XCTAssertTrue(text.contains("field.evidence.pdf.worklight.v1/1"), file: file, line: line)
        XCTAssertTrue(text.contains("field.evidence.illuminated_sign.v1/1/1"), file: file, line: line)
        XCTAssertTrue(text.contains("2026-01-14T20:02:06.000Z"), file: file, line: line)
        XCTAssertTrue(text.contains("A1.0/41"), file: file, line: line)
        XCTAssertTrue(text.contains("SHA256 \(snapshotSHA256)"), file: file, line: line)
        XCTAssertTrue(text.contains("Page 1 of \(expectedPageCount)"), file: file, line: line)

        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData), file: file, line: line)
        let cgDocument = try XCTUnwrap(CGPDFDocument(provider), file: file, line: line)
        XCTAssertEqual(cgDocument.numberOfPages, expectedPageCount, file: file, line: line)
        let attributes = document.documentAttributes ?? [:]
        XCTAssertEqual(attributes[PDFDocumentAttribute.creatorAttribute] as? String, "FieldEvidenceApp PDFTemplateV1", file: file, line: line)
        XCTAssertEqual(attributes[PDFDocumentAttribute.creationDateAttribute] as? Date, Fixture.snapshotDate, file: file, line: line)
        XCTAssertEqual(attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date, Fixture.snapshotDate, file: file, line: line)
        XCTAssertNil(attributes[PDFDocumentAttribute.authorAttribute], file: file, line: line)
        XCTAssertNil(attributes[PDFDocumentAttribute.subjectAttribute], file: file, line: line)
        XCTAssertNil(attributes[PDFDocumentAttribute.keywordsAttribute], file: file, line: line)
        XCTAssertNil(data.range(of: Data("/ID".utf8)), "Volatile PDF identifier is forbidden", file: file, line: line)

        var baseFonts = Set<String>()
        var imagePixelSizes = Set<String>()
        for pageIndex in 1...cgDocument.numberOfPages {
            let page = try XCTUnwrap(cgDocument.page(at: pageIndex), file: file, line: line)
            XCTAssertEqual(page.getBoxRect(.mediaBox), CGRect(x: 0, y: 0, width: 612, height: 792), file: file, line: line)
            let pageText = document.page(at: pageIndex - 1)?.string ?? ""
            XCTAssertTrue(pageText.contains("Page \(pageIndex) of \(expectedPageCount)"), file: file, line: line)
            for footerTruth in [
                "2026-01-14T20:02:06.000Z",
                "A1.0/41",
                "Pfield.evidence.illuminated_sign.v1/1/1",
                "Tfield.evidence.pdf.worklight.v1/1",
                "SHA256 \(snapshotSHA256)",
            ] {
                XCTAssertTrue(pageText.contains(footerTruth), "Missing footer truth: \(footerTruth)", file: file, line: line)
            }
            collectResourceFacts(page: page, fonts: &baseFonts, imagePixelSizes: &imagePixelSizes)
            for selectionText in [
                "North Campus",
                "2026-01-14T20:02:06.000Z",
                "SHA256 \(snapshotSHA256)",
                "Page \(pageIndex) of \(expectedPageCount)",
            ] where pageText.contains(selectionText) {
                let pdfPage = try XCTUnwrap(document.page(at: pageIndex - 1), file: file, line: line)
                let selection = try XCTUnwrap(
                    document.findString(selectionText, withOptions: []).first { $0.pages.contains(pdfPage) },
                    file: file,
                    line: line
                )
                let bounds = selection.bounds(for: pdfPage)
                let isFooter = selectionText.hasPrefix("Page ")
                    || selectionText.hasPrefix("SHA256 ")
                    || selectionText.hasPrefix("2026-")
                let allowed = isFooter
                    ? CGRect(x: 42, y: 42, width: 528, height: 18)
                    : CGRect(x: 42, y: 72, width: 528, height: 678)
                XCTAssertTrue(allowed.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(selectionText): \(bounds)", file: file, line: line)
            }
        }
        XCTAssertTrue(baseFonts.contains("Helvetica"), file: file, line: line)
        XCTAssertTrue(baseFonts.contains("Helvetica-Bold"), file: file, line: line)
        XCTAssertTrue(baseFonts.contains("Courier"), file: file, line: line)
        XCTAssertTrue(imagePixelSizes.contains("320x180"), "Current original missing", file: file, line: line)
        XCTAssertFalse(imagePixelSizes.contains("960x540"), "History original must not be embedded", file: file, line: line)
        XCTAssertFalse(imagePixelSizes.contains("600x900"), "History original must not be embedded", file: file, line: line)
        XCTAssertFalse(imagePixelSizes.contains("800x480"), "History original must not be embedded", file: file, line: line)
        XCTAssertGreaterThanOrEqual(imagePixelSizes.count, 4, "Current original plus history thumbnails expected", file: file, line: line)
    }

    func collectResourceFacts(
        page: CGPDFPage,
        fonts: inout Set<String>,
        imagePixelSizes: inout Set<String>
    ) {
        guard let dictionary = page.dictionary,
              let resources = pdfDictionary(dictionary, key: "Resources") else { return }
        let facts = PDFResourceFacts(fonts: fonts, images: imagePixelSizes)
        if let fontDictionary = pdfDictionary(resources, key: "Font") {
            CGPDFDictionaryApplyFunction(
                fontDictionary,
                collectPDFFontResource,
                Unmanaged.passUnretained(facts).toOpaque()
            )
        }
        if let xObjects = pdfDictionary(resources, key: "XObject") {
            CGPDFDictionaryApplyFunction(
                xObjects,
                collectPDFImageResource,
                Unmanaged.passUnretained(facts).toOpaque()
            )
        }
        fonts.formUnion(facts.fonts)
        imagePixelSizes.formUnion(facts.images)
    }

    func pdfDictionary(_ dictionary: CGPDFDictionaryRef, key: String) -> CGPDFDictionaryRef? {
        var result: CGPDFDictionaryRef?
        return key.withCString { CGPDFDictionaryGetDictionary(dictionary, $0, &result) } ? result : nil
    }

    func pdfName(_ dictionary: CGPDFDictionaryRef, key: String) -> String? {
        var result: UnsafePointer<CChar>?
        guard key.withCString({ CGPDFDictionaryGetName(dictionary, $0, &result) }), let result else { return nil }
        return String(cString: result)
    }

    func pdfInteger(_ dictionary: CGPDFDictionaryRef, key: String) -> Int? {
        var result: CGPDFInteger = 0
        return key.withCString { CGPDFDictionaryGetInteger(dictionary, $0, &result) } ? Int(result) : nil
    }

    @MainActor
    func stagingPDFURL(in harness: RenderHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            ".staging/pdfs/\(Fixture.reportID.uuidString.lowercased()).pdf"
        )
    }

    @MainActor
    func finalPDFURL(in harness: RenderHarness) -> URL {
        harness.session.generationRootURL.appendingPathComponent(
            "pdfs/\(Fixture.reportID.uuidString.lowercased()).pdf"
        )
    }

    func attach(_ data: Data, name: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.pdf.identifier)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func makePNG(width: Int, height: Int, seed: UInt8) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = seed &+ UInt8(truncatingIfNeeded: x)
                pixels[offset + 1] = seed &+ UInt8(truncatingIfNeeded: y)
                pixels[offset + 2] = seed &+ UInt8(truncatingIfNeeded: x ^ y)
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
              ) else { throw RendererFixtureError.image }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw RendererFixtureError.image }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RendererFixtureError.image }
        return output as Data
    }

    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class PDFResourceFacts {
    var fonts: Set<String>
    var images: Set<String>
    init(fonts: Set<String>, images: Set<String>) {
        self.fonts = fonts
        self.images = images
    }
}

@MainActor
private struct FixtureAuthority {
    let site: Site
    let asset: Asset
    let check: WorkflowRecord
    let work: WorkflowRecord
    let recheck: WorkflowRecord
    let issue: Issue
    let historicalPacket: Packet
    let packet: Packet
    let report: Report
    let rows: [EvidenceFile]
    let snapshot: ReportSnapshotV1
}

private struct EvidenceFixture {
    let row: EvidenceFile
    let snapshot: EvidenceSnapshotV1
}

private enum RendererFixtureError: Error { case image }

private func collectPDFFontResource(
    _ key: UnsafePointer<CChar>,
    _ value: CGPDFObjectRef,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info, CGPDFObjectGetType(value) == .dictionary else { return }
    var dictionary: CGPDFDictionaryRef?
    guard CGPDFObjectGetValue(value, .dictionary, &dictionary), let dictionary else { return }
    var baseFont: UnsafePointer<CChar>?
    guard "BaseFont".withCString({ CGPDFDictionaryGetName(dictionary, $0, &baseFont) }),
          let baseFont else { return }
    let resourceName = String(cString: baseFont)
    let parts = resourceName.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    let normalizedName: String
    if parts.count == 2,
       parts[0].count == 6,
       parts[0].allSatisfy({ $0.isASCII && $0.isUppercase }) {
        normalizedName = String(parts[1])
    } else {
        normalizedName = resourceName
    }
    Unmanaged<PDFResourceFacts>.fromOpaque(info).takeUnretainedValue().fonts
        .insert(normalizedName)
}

private func collectPDFImageResource(
    _ key: UnsafePointer<CChar>,
    _ value: CGPDFObjectRef,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info, CGPDFObjectGetType(value) == .stream else { return }
    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
          let dictionary = CGPDFStreamGetDictionary(stream) else { return }
    var subtype: UnsafePointer<CChar>?
    var width: CGPDFInteger = 0
    var height: CGPDFInteger = 0
    guard "Subtype".withCString({ CGPDFDictionaryGetName(dictionary, $0, &subtype) }),
          subtype.map({ String(cString: $0) }) == "Image",
          "Width".withCString({ CGPDFDictionaryGetInteger(dictionary, $0, &width) }),
          "Height".withCString({ CGPDFDictionaryGetInteger(dictionary, $0, &height) }) else { return }
    Unmanaged<PDFResourceFacts>.fromOpaque(info).takeUnretainedValue().images
        .insert("\(width)x\(height)")
}
extension S4_1DeterministicRendererTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindV1.allCases.count, 5)
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .inspection).completion, .criterionAssessment)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .inspection).mayClaimReleaseToService)
    }
}
extension S4_1DeterministicRendererTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S4_1DeterministicRendererTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS41DeterministicRendererTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S4_1DeterministicRendererTests {
    @MainActor
    func testV23P03C42RendererProjectionUsesByteStableTypedModelRuns() throws {
        let scenario = try CompositeAreaSafetyArchetypeV1.scenario(
            seed: CompositeAreaSafetyArchetypeV1.defaultSeed
        )
        let first = try CompositeAreaSafetyArchetypeV1.run(
            seed: CompositeAreaSafetyArchetypeV1.defaultSeed
        )
        let second = try CompositeAreaSafetyArchetypeV1.run(
            seed: CompositeAreaSafetyArchetypeV1.defaultSeed
        )
        let projection = "\(scenario.archetypeID):\(first.normalizedResultSHA256)"
        let firstHarness = try makeHarness(label: "c42-render-a", c42Projection: projection)
        let secondHarness = try makeHarness(label: "c42-render-b", c42Projection: projection)
        defer {
            try? fileManager.removeItem(at: firstHarness.applicationSupportURL)
            try? fileManager.removeItem(at: secondHarness.applicationSupportURL)
        }
        let firstValidated = try SnapshotValidatorV1(
            modelContext: firstHarness.session.modelContext,
            generationRootURL: firstHarness.session.generationRootURL
        ).validate(report: firstHarness.report)
        let secondValidated = try SnapshotValidatorV1(
            modelContext: secondHarness.session.modelContext,
            generationRootURL: secondHarness.session.generationRootURL
        ).validate(report: secondHarness.report)
        XCTAssertEqual(firstValidated.snapshot.site.address, projection)
        XCTAssertEqual(secondValidated.snapshot.site.address, projection)
        let firstPDF = try WorklightPDFRendererV1().render(firstValidated)
        let secondPDF = try WorklightPDFRendererV1().render(secondValidated)
        XCTAssertEqual(firstPDF.data, secondPDF.data)
        XCTAssertEqual(firstPDF.pageCount, secondPDF.pageCount)
        XCTAssertEqual(first.operations, second.operations)
    }
}

private final class C33TemporalEvidenceAnchorS41DeterministicRenderer: XCTestCase {
    func testC33S41DeterministicRendererCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "renderer.temporal-typed-link",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "renderer.temporal-typed-link",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS41DeterministicRenderer: XCTestCase {
    func testC32S41DeterministicRendererCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .report,
            fieldID: "renderer.exclude-proposal",
            value: .text("unverified render exclusion")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .report,
            fieldID: "renderer.exclude-proposal",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46S41RendererCompatibilityTests: XCTestCase {
    func testC46RendererDoesNotProjectOperationalContactValue() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "renderer",
            kind: .phone,
            handoff: .directions,
            slot: 46401
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift_Tests: XCTestCase {
    func testC47S41DeterministicRendererTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_1DeterministicRendererTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertFalse(ActivityContractPersistenceEnrollmentV2.completionClaimsCommissioningComplianceApprovalOrCertification)
        XCTAssertEqual(Set(ActivityContractPersistenceEnrollmentV2.nonpersistentFamilies).count, 3)
    }
}

private final class C48PortableReviewS41RendererTests: XCTestCase {
    func testC48OpenJSONRendersDerivedMetadataWithoutExchangeSecrets() {
        XCTAssertTrue(C48PortableReviewOpenJSONBoundaryV1.usesExistingOpenJSONRenderer)
        XCTAssertTrue(C48PortableReviewOpenJSONBoundaryV1.emitsDerivedMetadataOnly)
        XCTAssertFalse(C48PortableReviewOpenJSONBoundaryV1.capabilityBytesEmitted)
        XCTAssertFalse(C48PortableReviewOpenJSONBoundaryV1.rawRequestResponseBytesEmitted)
    }
}
private final class C49WorkResourceRendererBoundaryTests: XCTestCase {
    func testManualFactsRenderWithoutInventoryOrConversionAuthority() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertFalse(C49WorkResourceContractBoundaryV1.liveInventoryReference)
    }
}

private final class C50IncumbentAdapterS41RendererBoundaryTests: XCTestCase {
    func testPreviewAndRenderStayOutsideCanonicalAndExternalFileAuthority() {
        XCTAssertTrue(C50IncumbentFileExchangeProtectedFileBoundaryV1.validate())
        XCTAssertFalse(C50IncumbentFileExchangeProtectedFileBoundaryV1.externalSourceAndExportFilesAreAppOwned)
        XCTAssertFalse(C50IncumbentFileExchangeProtectedFileBoundaryV1.persistsSecurityScopedBookmarks)
    }
}

extension S4_1DeterministicRendererTests {
    func testV23P03C34SceneStateStaysOutsideCanonicalRenderOutputs() {
        let lifecycle = SceneNavigationLifecycleDispositionV1()
        XCTAssertEqual(lifecycle.persistenceClass, "DEVICE_OPERATIONAL_NONCANONICAL")
        XCTAssertFalse(lifecycle.workspaceTruth)
        XCTAssertFalse(lifecycle.backupIncluded)
        XCTAssertFalse(lifecycle.reportIncluded)
        XCTAssertFalse(lifecycle.exportIncluded)
        XCTAssertFalse(lifecycle.searchIncluded)
    }
}

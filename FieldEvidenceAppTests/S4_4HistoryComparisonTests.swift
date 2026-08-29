import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private final class C30EvidenceContextAnchorS4_4HistoryComparison: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S4_4HistoryComparisonTests: XCTestCase {
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
    func testIndexFiltersHistoryAndStrictImmediateComparisonUseValidatedVisitTruth() async throws {
        let harness = try await makeHarness("golden")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let old = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate,
            site: harness.siteA,
            asset: harness.assetA,
            seed: 10
        )
        let otherSign = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate.addingTimeInterval(60),
            site: harness.siteA,
            asset: harness.assetB,
            seed: 40
        )
        let newest = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate.addingTimeInterval(120),
            site: harness.siteA,
            asset: harness.assetA,
            seed: 70
        )
        let siteB = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate.addingTimeInterval(30),
            site: harness.siteB,
            asset: harness.assetC,
            seed: 100
        )
        let coordinator = try historyCoordinator(in: harness)

        let all = try coordinator.index()
        XCTAssertEqual(
            all.visits.map(\.reportID),
            [newest.report.id, otherSign.report.id, siteB.report.id, old.report.id]
        )
        XCTAssertEqual(all.siteOptions.map(\.label), ["North Campus", "South Campus"])
        XCTAssertEqual(
            all.assetOptions.map(\.label),
            ["Lobby Sign", "Monument Sign", "Road Sign"]
        )
        XCTAssertEqual(
            try coordinator.index(filter: .site(harness.siteA.id)).visits.map(\.reportID),
            [newest.report.id, otherSign.report.id, old.report.id]
        )
        XCTAssertEqual(
            try coordinator.index(filter: .asset(harness.assetA.id)).visits.map(\.reportID),
            [newest.report.id, old.report.id]
        )

        let history = try XCTUnwrap(coordinator.signHistory(assetID: harness.assetA.id))
        XCTAssertEqual(history.siteLabel, "North Campus")
        XCTAssertEqual(history.assetLabel, "Monument Sign")
        XCTAssertEqual(history.visits.map(\.reportID), [newest.report.id, old.report.id])
        let comparison = try XCTUnwrap(
            coordinator.comparison(stableRootID: newest.packet.stableRootID)
        )
        XCTAssertEqual(comparison.then.reportID, old.report.id)
        XCTAssertEqual(comparison.now.reportID, newest.report.id)
        XCTAssertEqual(comparison.then.completedAt, old.source.completedAt)
        XCTAssertEqual(comparison.now.completedAt, newest.source.completedAt)
        XCTAssertEqual(comparison.then.evidence.map(\.purposeKey), ["wide_context", "close_detail"])
        XCTAssertEqual(comparison.now.evidence.map(\.purposeKey), ["wide_context", "close_detail"])
        XCTAssertNotEqual(comparison.then.evidence[0].originalData, comparison.now.evidence[0].originalData)
        XCTAssertNil(try coordinator.comparison(stableRootID: old.packet.stableRootID))
    }

    @MainActor
    func testCurrentRevisionCollapsesOneStableRootAndCorrectionIsNotAnotherVisit() async throws {
        let harness = try await makeHarness("collapse")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let visit = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate,
            site: harness.siteA,
            asset: harness.assetA,
            seed: 130
        )
        let correction = try addCorrection(to: visit, in: harness)
        let coordinator = try historyCoordinator(in: harness)

        XCTAssertEqual(try coordinator.index().visits.map(\.stableRootID), [visit.packet.stableRootID])
        XCTAssertEqual(try coordinator.index().visits.map(\.reportID), [correction.report.id])
        XCTAssertEqual(try coordinator.index().visits.first?.completedAt, visit.source.completedAt)
        XCTAssertEqual(
            try coordinator.signHistory(assetID: harness.assetA.id)?.visits.count,
            1
        )
        XCTAssertNil(try coordinator.comparison(stableRootID: visit.packet.stableRootID))
    }

    @MainActor
    func testMutableMembershipLabelsNeverRewriteFrozenReportTruth() async throws {
        let harness = try await makeHarness("frozen-labels")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let visit = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate,
            site: harness.siteA,
            asset: harness.assetA,
            seed: 140
        )
        harness.siteA.label = "Renamed live site"
        harness.assetA.label = "Renamed live sign"
        try harness.context.save()
        let coordinator = try historyCoordinator(in: harness)

        let index = try coordinator.index()
        XCTAssertEqual(index.siteOptions.map(\.label), ["North Campus"])
        XCTAssertEqual(index.assetOptions.map(\.label), ["Monument Sign"])
        XCTAssertEqual(index.visits.map(\.siteLabel), ["North Campus"])
        XCTAssertEqual(index.visits.map(\.assetLabel), ["Monument Sign"])
        XCTAssertEqual(index.visits.map(\.reportID), [visit.report.id])
        let history = try XCTUnwrap(coordinator.signHistory(assetID: harness.assetA.id))
        XCTAssertEqual(history.siteLabel, "North Campus")
        XCTAssertEqual(history.assetLabel, "Monument Sign")
        XCTAssertEqual(history.visits.map(\.reportID), [visit.report.id])
    }

    @MainActor
    func testMissingImmediateEvidenceAndEqualChronologyOmitComparisonButKeepHistory() async throws {
        let harness = try await makeHarness("comparison-alt")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let incomplete = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate,
            site: harness.siteA,
            asset: harness.assetA,
            seed: 150,
            includesClose: false
        )
        let now = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate.addingTimeInterval(60),
            site: harness.siteA,
            asset: harness.assetA,
            seed: 180
        )
        let coordinator = try historyCoordinator(in: harness)

        XCTAssertEqual(try coordinator.signHistory(assetID: harness.assetA.id)?.visits.count, 2)
        XCTAssertNil(try coordinator.comparison(stableRootID: now.packet.stableRootID))
        XCTAssertEqual(
            try coordinator.index(filter: .asset(harness.assetA.id)).visits.map(\.reportID),
            [now.report.id, incomplete.report.id]
        )

        let equal = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate.addingTimeInterval(60),
            site: harness.siteA,
            asset: harness.assetA,
            seed: 210
        )
        XCTAssertEqual(try coordinator.signHistory(assetID: harness.assetA.id)?.visits.count, 3)
        XCTAssertNil(try coordinator.comparison(stableRootID: equal.packet.stableRootID))
    }

    @MainActor
    func testAmbiguousAndBrokenImmediatePredecessorsNeverFallThroughToOlderVisit() async throws {
        let ambiguous = try await makeHarness("ambiguous-prior")
        defer { try? fileManager.removeItem(at: ambiguous.applicationSupportURL) }
        _ = try await addVisit(
            to: ambiguous, completedAt: Fixture.baseDate,
            site: ambiguous.siteA, asset: ambiguous.assetA, seed: 11
        )
        _ = try await addVisit(
            to: ambiguous, completedAt: Fixture.baseDate.addingTimeInterval(60),
            site: ambiguous.siteA, asset: ambiguous.assetA, seed: 41
        )
        _ = try await addVisit(
            to: ambiguous, completedAt: Fixture.baseDate.addingTimeInterval(60),
            site: ambiguous.siteA, asset: ambiguous.assetA, seed: 71
        )
        let now = try await addVisit(
            to: ambiguous, completedAt: Fixture.baseDate.addingTimeInterval(120),
            site: ambiguous.siteA, asset: ambiguous.assetA, seed: 101
        )
        let ambiguousCoordinator = try historyCoordinator(in: ambiguous)
        XCTAssertEqual(
            try ambiguousCoordinator.signHistory(assetID: ambiguous.assetA.id)?.visits.count,
            4
        )
        XCTAssertNil(
            try ambiguousCoordinator.comparison(stableRootID: now.packet.stableRootID)
        )

        let broken = try await makeHarness("broken-prior")
        defer { try? fileManager.removeItem(at: broken.applicationSupportURL) }
        let old = try await addVisit(
            to: broken, completedAt: Fixture.baseDate,
            site: broken.siteA, asset: broken.assetA, seed: 131
        )
        let invalidPrior = try await addVisit(
            to: broken, completedAt: Fixture.baseDate.addingTimeInterval(60),
            site: broken.siteA, asset: broken.assetA, seed: 161
        )
        let newest = try await addVisit(
            to: broken, completedAt: Fixture.baseDate.addingTimeInterval(120),
            site: broken.siteA, asset: broken.assetA, seed: 191
        )
        invalidPrior.report.pdfState = ReportPDFState.pending.rawValue
        invalidPrior.report.pdfRelativePath = nil
        invalidPrior.report.pdfSHA256 = nil
        try broken.context.save()
        let brokenCoordinator = try historyCoordinator(in: broken)
        XCTAssertEqual(
            try brokenCoordinator.signHistory(assetID: broken.assetA.id)?.visits.map(\.reportID),
            [newest.report.id, old.report.id]
        )
        XCTAssertNil(
            try brokenCoordinator.comparison(stableRootID: newest.packet.stableRootID)
        )
    }

    @MainActor
    func testCrossPacketReverseReplacementAndTombstoneNeverBecomeBrowsable() async throws {
        let replacement = try await makeHarness("foreign-replacement")
        defer { try? fileManager.removeItem(at: replacement.applicationSupportURL) }
        let valid = try await addVisit(
            to: replacement, completedAt: Fixture.baseDate,
            site: replacement.siteA, asset: replacement.assetA, seed: 31
        )
        replacement.context.insert(Report(
            id: UUID(), packetID: UUID(), sourceRecordID: UUID(),
            snapshotSchemaVersion: 1, snapshotRelativePath: "snapshots/foreign.json",
            snapshotSHA256: String(repeating: "a", count: 64), pdfState: .failed,
            pdfRelativePath: nil, pdfSHA256: nil,
            createdAt: Fixture.baseDate.addingTimeInterval(1),
            replacesReportID: valid.report.id
        ))
        try replacement.context.save()
        let before = try authoritySnapshot(in: replacement)
        let replacementCoordinator = try historyCoordinator(in: replacement)
        XCTAssertTrue(try replacementCoordinator.index().visits.isEmpty)
        XCTAssertNil(
            try replacementCoordinator.comparison(stableRootID: valid.packet.stableRootID)
        )
        XCTAssertEqual(try authoritySnapshot(in: replacement), before)

        let tombstone = try await makeHarness("tombstone-collision")
        defer { try? fileManager.removeItem(at: tombstone.applicationSupportURL) }
        let live = try await addVisit(
            to: tombstone, completedAt: Fixture.baseDate,
            site: tombstone.siteA, asset: tombstone.assetA, seed: 61
        )
        tombstone.context.insert(Packet(
            id: UUID(), stableRootID: UUID(),
            currentRecordID: live.packet.currentRecordID, evaluationCounted: false,
            contentDeletedAt: Fixture.baseDate, createdAt: Fixture.baseDate
        ))
        try tombstone.context.save()
        let tombstoneBefore = try authoritySnapshot(in: tombstone)
        let tombstoneCoordinator = try historyCoordinator(in: tombstone)
        XCTAssertTrue(try tombstoneCoordinator.index().visits.isEmpty)
        XCTAssertNil(try tombstoneCoordinator.signHistory(assetID: tombstone.assetA.id))
        XCTAssertNil(
            try tombstoneCoordinator.comparison(stableRootID: live.packet.stableRootID)
        )
        XCTAssertEqual(try authoritySnapshot(in: tombstone), tombstoneBefore)
    }

    @MainActor
    func testDirtyCollisionAndUnsafeAuthorityFailClosedWithoutMutationOrUnownedTouch() async throws {
        let dirty = try await makeHarness("dirty")
        defer { try? fileManager.removeItem(at: dirty.applicationSupportURL) }
        let dirtyVisit = try await addVisit(
            to: dirty,
            completedAt: Fixture.baseDate,
            site: dirty.siteA,
            asset: dirty.assetA,
            seed: 20
        )
        let dirtyCoordinator = try historyCoordinator(in: dirty)
        dirtyVisit.source.note = "unsaved"
        let dirtyBefore = try authoritySnapshot(in: dirty)
        XCTAssertThrowsError(try dirtyCoordinator.index()) {
            XCTAssertEqual($0 as? ReportHistoryCoordinatorError, .contextHasChanges)
        }
        XCTAssertEqual(try authoritySnapshot(in: dirty), dirtyBefore)
        dirty.context.rollback()

        let collision = try await makeHarness("collision")
        defer { try? fileManager.removeItem(at: collision.applicationSupportURL) }
        let collisionVisit = try await addVisit(
            to: collision,
            completedAt: Fixture.baseDate,
            site: collision.siteA,
            asset: collision.assetA,
            seed: 50
        )
        collision.context.insert(Packet(
            id: UUID(),
            stableRootID: UUID(),
            currentRecordID: collisionVisit.packet.currentRecordID,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: Fixture.baseDate
        ))
        try collision.context.save()
        let collisionBefore = try authoritySnapshot(in: collision)
        XCTAssertThrowsError(try historyCoordinator(in: collision).index()) {
            XCTAssertEqual($0 as? ReportHistoryCoordinatorError, .invalidAuthority)
        }
        XCTAssertEqual(try authoritySnapshot(in: collision), collisionBefore)

        let unsafe = try await makeHarness("unsafe")
        defer { try? fileManager.removeItem(at: unsafe.applicationSupportURL) }
        let unsafeVisit = try await addVisit(
            to: unsafe,
            completedAt: Fixture.baseDate,
            site: unsafe.siteA,
            asset: unsafe.assetA,
            seed: 80
        )
        let evidence = try XCTUnwrap(
            try unsafe.context.fetch(FetchDescriptor<EvidenceFile>()).first
        )
        let canonical = unsafe.session.generationRootURL.appendingPathComponent(
            evidence.relativePath
        )
        let retained = unsafe.applicationSupportURL.appendingPathComponent("unowned-evidence.bin")
        let retainedBytes = try Data(contentsOf: canonical)
        try fileManager.moveItem(at: canonical, to: retained)
        try fileManager.createSymbolicLink(at: canonical, withDestinationURL: retained)
        let before = try authoritySnapshot(in: unsafe)
        let unsafeCoordinator = try historyCoordinator(in: unsafe)

        XCTAssertTrue(try unsafeCoordinator.index().visits.isEmpty)
        XCTAssertNil(try unsafeCoordinator.signHistory(assetID: unsafe.assetA.id)?.visits.first)
        XCTAssertNil(try unsafeCoordinator.comparison(stableRootID: unsafeVisit.packet.stableRootID))
        XCTAssertEqual(try authoritySnapshot(in: unsafe), before)
        XCTAssertEqual(try Data(contentsOf: retained), retainedBytes)
        XCTAssertEqual(
            try fileManager.attributesOfItem(atPath: canonical.path)[.type]
                as? FileAttributeType,
            .typeSymbolicLink
        )
    }
}

private final class C27S44TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertEqual(LocatorInputSourceV1.allCases.count, 3)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension S4_4HistoryComparisonTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

@MainActor
private struct HistoryHarness {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let context: ModelContext
    let siteA: Site
    let siteB: Site
    let assetA: Asset
    let assetB: Asset
    let assetC: Asset
}

@MainActor
private struct VisitFixture {
    let source: WorkflowRecord
    let packet: Packet
    let report: Report
}

private struct AuthoritySnapshot: Equatable {
    let reportFacts: [String]
    let packetFacts: [String]
    let recordFacts: [String]
    let evidenceFacts: [String]
    let fileHashes: [String: String]
}

private enum Fixture {
    static let baseDate = Date(timeIntervalSince1970: 1_768_800_000)
}

private extension S4_4HistoryComparisonTests {
    @MainActor
    func makeHarness(_ label: String) async throws -> HistoryHarness {
        let applicationSupport = fileManager.temporaryDirectory.appendingPathComponent(
            "S4_4HistoryComparisonTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: applicationSupport)
            .openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let siteA = Site(
            id: UUID(), label: "North Campus", address: "10 Main",
            timeZoneID: "America/New_York", createdAt: Fixture.baseDate.addingTimeInterval(-10)
        )
        let siteB = Site(
            id: UUID(), label: "South Campus", address: "20 Main",
            timeZoneID: "America/New_York", createdAt: Fixture.baseDate.addingTimeInterval(-9)
        )
        let assetA = Asset(
            id: UUID(), siteID: siteA.id, packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            label: "Monument Sign", createdAt: Fixture.baseDate.addingTimeInterval(-8)
        )
        let assetB = Asset(
            id: UUID(), siteID: siteA.id, packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            label: "Lobby Sign", createdAt: Fixture.baseDate.addingTimeInterval(-7)
        )
        let assetC = Asset(
            id: UUID(), siteID: siteB.id, packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            label: "Road Sign", createdAt: Fixture.baseDate.addingTimeInterval(-6)
        )
        [siteA, siteB].forEach { context.insert($0) }
        [assetA, assetB, assetC].forEach { context.insert($0) }
        try context.save()
        return HistoryHarness(
            applicationSupportURL: applicationSupport,
            session: session,
            context: context,
            siteA: siteA,
            siteB: siteB,
            assetA: assetA,
            assetB: assetB,
            assetC: assetC
        )
    }

    @MainActor
    func addVisit(
        to harness: HistoryHarness,
        completedAt: Date,
        site: Site,
        asset: Asset,
        seed: UInt8,
        includesClose: Bool = true
    ) async throws -> VisitFixture {
        guard asset.siteID == site.id else {
            throw HistoryFixtureError.couldNotCreateFixture
        }
        let coordinator = CheckRunnerCoordinator(
            modelContext: harness.context,
            signPack: .illuminatedSignV1
        )
        coordinator.configureCapture(generationRootURL: harness.session.generationRootURL)
        let source = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: completedAt.addingTimeInterval(-10)
        )
        let wide = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: seed),
            createdAt: completedAt.addingTimeInterval(-8)
        )
        _ = try await coordinator.accept(candidate: wide, assetID: asset.id)
        if includesClose {
            let close = try await coordinator.importCandidate(
                assetID: asset.id,
                sourceData: try makePNG(seed: seed &+ 1),
                createdAt: completedAt.addingTimeInterval(-7)
            )
            _ = try await coordinator.accept(candidate: close, assetID: asset.id)
        }
        let selection: CheckOutcomeSelection = includesClose
            ? .noVisibleIssue
            : .couldNotVerify(reasonKey: "required_view_obstructed", note: nil)
        let result = try await coordinator.finalize(
            assetID: asset.id,
            selection: selection,
            completedAt: completedAt,
            snapshotCreatedAt: completedAt.addingTimeInterval(1),
            sourceApp: SourceAppSnapshotV1(build: "44", version: "1.0"),
            identifiers: FinalizationIdentifiers(
                mutationID: UUID(), packetID: UUID(), stableRootID: UUID(),
                reportID: UUID(), issueID: nil
            )
        )
        guard case .ready = try coordinator.prepareReportDelivery(result: result) else {
            throw HistoryFixtureError.couldNotCreateFixture
        }
        let reports = try harness.context.fetch(FetchDescriptor<Report>()).filter {
            $0.id == result.reportID
        }
        let report = try XCTUnwrap(reports.first)
        let packets = try harness.context.fetch(FetchDescriptor<Packet>()).filter {
            $0.id == report.packetID
        }
        return VisitFixture(source: source, packet: try XCTUnwrap(packets.first), report: report)
    }

    @MainActor
    func addCorrection(
        to prior: VisitFixture,
        in harness: HistoryHarness
    ) throws -> VisitFixture {
        let source = prior.source
        let correctionID = UUID()
        let correction = WorkflowRecord(
            id: correctionID,
            assetID: source.assetID,
            packetID: source.packetID,
            issueID: source.issueID,
            parentRecordID: source.parentRecordID,
            recordRevisionRootID: source.id,
            revisesRecordID: source.id,
            evidenceSourceRecordID: source.id,
            revisionKind: .clericalCorrection,
            stage: WorkflowStage(rawValue: source.stage)!,
            state: .completed,
            draftStepKey: nil,
            startedAt: source.startedAt,
            completedAt: try XCTUnwrap(source.completedAt).addingTimeInterval(300),
            observedAtUTC: source.observedAtUTC,
            timeZoneID: source.timeZoneID,
            utcOffsetMinutes: source.utcOffsetMinutes,
            localDate: source.localDate,
            localTime: source.localTime,
            afterDarkAcknowledgementKey: source.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: source.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: source.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: source.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: source.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: source.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: source.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: source.safePositionAcknowledgementAccepted,
            packID: source.packID,
            packSchemaVersion: source.packSchemaVersion,
            packContentVersion: source.packContentVersion,
            pdfTemplateID: source.pdfTemplateID,
            pdfTemplateVersion: source.pdfTemplateVersion,
            outcomeKey: source.outcomeKey,
            couldNotVerifyKey: source.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: source.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: source.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: source.workPerformedLocalDate,
            workDescription: source.workDescription,
            note: "Corrected clerical note",
            finalizationMutationID: UUID()
        )
        let priorSnapshotURL = harness.session.generationRootURL.appendingPathComponent(
            prior.report.snapshotRelativePath
        )
        let priorSnapshot = try ReportSnapshotEncoderV1().decode(
            Data(contentsOf: priorSnapshotURL)
        )
        let reportID = UUID()
        let snapshotAt = try XCTUnwrap(source.completedAt).addingTimeInterval(301)
        let snapshot = ReportSnapshotV1(
            acknowledgements: priorSnapshot.acknowledgements,
            asset: priorSnapshot.asset,
            couldNotVerify: priorSnapshot.couldNotVerify,
            disclaimer: priorSnapshot.disclaimer,
            display: priorSnapshot.display,
            evidence: priorSnapshot.evidence,
            evidenceSourceRecordID: source.id,
            history: priorSnapshot.history,
            issues: priorSnapshot.issues,
            note: correction.note,
            outcome: priorSnapshot.outcome,
            pack: priorSnapshot.pack,
            packetID: prior.packet.id,
            pdfTemplate: priorSnapshot.pdfTemplate,
            reportID: reportID,
            site: priorSnapshot.site,
            snapshotCreatedAt: snapshotAt,
            snapshotSchemaVersion: 1,
            sourceApp: priorSnapshot.sourceApp,
            sourceRecordID: correctionID,
            stableRootID: prior.packet.stableRootID,
            stage: priorSnapshot.stage,
            timeContext: priorSnapshot.timeContext
        )
        let snapshotBytes = try ReportSnapshotEncoderV1().encode(snapshot).data
        let snapshotRelativePath = "snapshots/\(reportID.uuidString.lowercased()).json"
        try snapshotBytes.write(
            to: harness.session.generationRootURL.appendingPathComponent(snapshotRelativePath)
        )
        let report = Report(
            id: reportID,
            packetID: prior.packet.id,
            sourceRecordID: correctionID,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: snapshotRelativePath,
            snapshotSHA256: snapshotBytes.sha256,
            pdfState: .pending,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: snapshotAt,
            replacesReportID: prior.report.id
        )
        harness.context.insert(correction)
        harness.context.insert(report)
        prior.packet.currentRecordID = correctionID
        try harness.context.save()
        let delivery = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        guard case .ready = try delivery.prepareFinalizedReport(id: reportID) else {
            throw HistoryFixtureError.couldNotCreateFixture
        }
        return VisitFixture(source: correction, packet: prior.packet, report: report)
    }

    @MainActor
    func historyCoordinator(in harness: HistoryHarness) throws -> ReportHistoryCoordinator {
        let delivery = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL
        )
        return ReportHistoryCoordinator(
            modelContext: harness.context,
            deliveryCoordinator: delivery
        )
    }

    @MainActor
    func authoritySnapshot(in harness: HistoryHarness) throws -> AuthoritySnapshot {
        let reports = try harness.context.fetch(FetchDescriptor<Report>())
        let packets = try harness.context.fetch(FetchDescriptor<Packet>())
        let records = try harness.context.fetch(FetchDescriptor<WorkflowRecord>())
        let evidence = try harness.context.fetch(FetchDescriptor<EvidenceFile>())
        var hashes: [String: String] = [:]
        let enumerator = fileManager.enumerator(
            at: harness.session.generationRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                let relative = url.path.replacingOccurrences(
                    of: harness.session.generationRootURL.path + "/",
                    with: ""
                )
                hashes[relative] = try Data(contentsOf: url).sha256
            }
        }
        return AuthoritySnapshot(
            reportFacts: reports.map {
                [
                    $0.id.uuidString, String($0.schemaVersion), $0.packetID.uuidString,
                    $0.sourceRecordID.uuidString, $0.snapshotRelativePath,
                    $0.snapshotSHA256, $0.pdfState, $0.pdfRelativePath ?? "nil",
                    $0.pdfSHA256 ?? "nil", $0.replacesReportID?.uuidString ?? "nil",
                ].joined(separator: "|")
            }.sorted(),
            packetFacts: packets.map {
                [
                    $0.id.uuidString, String($0.schemaVersion), $0.stableRootID.uuidString,
                    $0.currentRecordID?.uuidString ?? "nil", String($0.evaluationCounted),
                    $0.contentDeletedAt.map { String(describing: $0) } ?? "nil",
                ].joined(separator: "|")
            }.sorted(),
            recordFacts: records.map {
                [
                    $0.id.uuidString, String($0.schemaVersion), $0.assetID.uuidString,
                    $0.packetID?.uuidString ?? "nil", $0.recordRevisionRootID.uuidString,
                    $0.revisesRecordID?.uuidString ?? "nil",
                    $0.evidenceSourceRecordID?.uuidString ?? "nil", $0.revisionKind,
                    $0.state, $0.completedAt.map { String(describing: $0) } ?? "nil",
                    $0.outcomeKey ?? "nil", $0.note ?? "nil",
                ].joined(separator: "|")
            }.sorted(),
            evidenceFacts: evidence.map {
                [
                    $0.id.uuidString, String($0.schemaVersion), $0.recordID.uuidString,
                    $0.purposeKey, $0.relativePath, $0.sha256,
                    $0.thumbnailRelativePath, $0.thumbnailSHA256,
                ].joined(separator: "|")
            }.sorted(),
            fileHashes: hashes
        )
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
                  width: width, height: height, bitsPerComponent: 8,
                  bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace,
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { throw HistoryFixtureError.couldNotCreateFixture }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw HistoryFixtureError.couldNotCreateFixture }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HistoryFixtureError.couldNotCreateFixture
        }
        return output as Data
    }
}

private enum HistoryFixtureError: Error { case couldNotCreateFixture }

private extension Data {
    var sha256: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
extension S4_4HistoryComparisonTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleStateV1.allCases, [.draft, .published, .retired])
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies, ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"])
        XCTAssertTrue(SurveyDefinitionLimitsV1.digest(String(repeating: "a", count: 64)))
    }
}
extension S4_4HistoryComparisonTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S4_4HistoryComparisonTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS44HistoryComparisonTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S4_4HistoryComparisonTests {
    @MainActor
    func testV23P03C42HistorySurfaceKeepsTypedSupersessionAndReportProjectionDistinct() async throws {
        let scenario = try CompositeAreaSafetyArchetypeV1.scenario()
        let receipt = try CompositeAreaSafetyArchetypeV1.run()
        let signoff = try XCTUnwrap(scenario.operations.first { $0.entityKind == .signoffSnapshot })
        let report = try XCTUnwrap(scenario.operations.first { $0.entityKind == .report })
        let supersede = try XCTUnwrap(scenario.operations.first { $0.kind == .supersede })
        let projection = try XCTUnwrap(scenario.operations.first { $0.kind == .rebuildProjection })
        let staleRevision = try XCTUnwrap(scenario.operations.first { $0.kind == .rejectStaleRevision })

        let harness = try await makeHarness("c42-history")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        harness.siteA.label = scenario.archetypeID
        harness.assetA.label = receipt.normalizedResultSHA256
        try harness.context.save()
        let first = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate,
            site: harness.siteA,
            asset: harness.assetA,
            seed: UInt8(signoff.ordinal)
        )
        let second = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate.addingTimeInterval(Double(projection.ordinal)),
            site: harness.siteA,
            asset: harness.assetA,
            seed: UInt8(report.ordinal)
        )
        let owner = try historyCoordinator(in: harness)
        let history = try XCTUnwrap(owner.signHistory(assetID: harness.assetA.id))
        let comparison = try XCTUnwrap(owner.comparison(stableRootID: second.packet.stableRootID))
        XCTAssertEqual(history.siteLabel, scenario.archetypeID)
        XCTAssertEqual(history.assetLabel, receipt.normalizedResultSHA256)
        XCTAssertEqual(history.visits.map(\.reportID), [second.report.id, first.report.id])
        XCTAssertEqual(comparison.then.reportID, first.report.id)
        XCTAssertEqual(comparison.now.reportID, second.report.id)
        XCTAssertEqual(supersede.resultingRevision, 2)
        XCTAssertEqual(staleRevision.expectedDisposition, .rejectedPrecondition)
    }
}

private final class C32AssistanceAnchorS44HistoryComparison: XCTestCase {
    func testC32S44HistoryComparisonCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .report,
            fieldID: "history.accepted-fact-only",
            value: .text("historic report stays immutable")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .report,
            fieldID: "history.accepted-fact-only",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}

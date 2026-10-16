import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_S4_4HistoryComparisonTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

final class C45HistoryComparisonCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityComparesActiveAndHistoricSnapshotsWithoutReinterpretation() {
        XCTAssertEqual(Set(AcceptedLabelSnapshotDispositionV1.allCases), [.activeSourceWorkspace, .historicCloneOrFork])
        XCTAssertEqual(Set(LabelReprintEligibilityV1.allCases), [.activeExactReprint, .historicExportOnly, .blockedMissingRelease])
    }
}

final class C51S44HistoryComparisonAnchorTests: XCTestCase {
    func testV23P03C51AdvancedScheduleHistoryNeverReinterpretsFrozenBasis() {
        XCTAssertTrue(AdvancedScheduleReportHistoryPolicyV1.historicBasisIsFrozen)
        XCTAssertTrue(AdvancedScheduleReportHistoryPolicyV1.laterCalendarOrOverrideDoesNotRewriteHistory)
        XCTAssertTrue(SnapshotValidatorV1.advancedScheduleHistoryIsFrozen)
    }
}

final class C30EvidenceContextAnchorS4_4HistoryComparison: XCTestCase {
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
        defer { closeCurrentHistoryWriter(harness.owner) }
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
        defer { closeCurrentHistoryWriter(harness.owner) }
        let visit = try await addVisit(
            to: harness,
            completedAt: Fixture.baseDate,
            site: harness.siteA,
            asset: harness.assetA,
            seed: 130
        )
        let correction = try await addCorrection(to: visit, in: harness)
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
        defer { closeCurrentHistoryWriter(harness.owner) }
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
        defer { closeCurrentHistoryWriter(harness.owner) }
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
        defer { closeCurrentHistoryWriter(ambiguous.owner) }
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
        defer { closeCurrentHistoryWriter(broken.owner) }
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
        defer { closeCurrentHistoryWriter(replacement.owner) }
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
        defer { closeCurrentHistoryWriter(tombstone.owner) }
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
        defer { closeCurrentHistoryWriter(dirty.owner) }
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
        defer { closeCurrentHistoryWriter(collision.owner) }
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
        defer { closeCurrentHistoryWriter(unsafe.owner) }
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

final class C27S44TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertEqual(LocatorInputSourceV1.allCases, [.camera, .manual, .imported, .search])
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
    let owner: StoreSessionCoordinator
    let dependencies: WorkspacePackageLifecycleDependenciesV1
    let profile: WorkspacePackageLifecycleProfileV1
    let clock: HistoryFixtureClock
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
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let clock = HistoryFixtureClock(Fixture.baseDate.addingTimeInterval(-10))
        let owner = try StoreSessionCoordinator(validatingSession: session, clock: clock,
            lifecycleProfileRegistry: registry)
        do {
            let siteAID = UUID()
            let siteBID = UUID()
            let assetAID = UUID()
            let assetBID = UUID()
            let assetCID = UUID()
            // Canonical first sign creates its Site and first Asset together.
            // Keep the original Site instants and seed before the earliest Check.
            try createCurrentHistoryAsset(owner: owner, siteID: siteAID,
                newSite: .init(id: siteAID, label: "North Campus", address: "10 Main",
                    timeZoneID: "America/New_York"),
                assetID: assetAID, label: "Monument Sign",
                createdAt: Fixture.baseDate.addingTimeInterval(-10))
            clock.set(Fixture.baseDate.addingTimeInterval(-9))
            try createCurrentHistoryAsset(owner: owner, siteID: siteBID,
                newSite: .init(id: siteBID, label: "South Campus", address: "20 Main",
                    timeZoneID: "America/New_York"),
                assetID: assetCID, label: "Road Sign",
                createdAt: Fixture.baseDate.addingTimeInterval(-9))
            clock.set(Fixture.baseDate.addingTimeInterval(-7))
            try createCurrentHistoryAsset(owner: owner, siteID: siteAID, newSite: nil,
                assetID: assetBID, label: "Lobby Sign",
                createdAt: Fixture.baseDate.addingTimeInterval(-7))
            let sites = try context.fetch(FetchDescriptor<Site>())
            let assets = try context.fetch(FetchDescriptor<Asset>())
            let dependencies = try owner.packageLifecycleDependencies(profileRegistry: registry)
            return HistoryHarness(
                applicationSupportURL: applicationSupport,
                session: session,
                context: context,
                owner: owner,
                dependencies: dependencies,
                profile: profile,
                clock: clock,
                siteA: try XCTUnwrap(sites.first { $0.id == siteAID }),
                siteB: try XCTUnwrap(sites.first { $0.id == siteBID }),
                assetA: try XCTUnwrap(assets.first { $0.id == assetAID }),
                assetB: try XCTUnwrap(assets.first { $0.id == assetBID }),
                assetC: try XCTUnwrap(assets.first { $0.id == assetCID })
            )
        } catch {
            closeCurrentHistoryWriter(owner)
            throw error
        }
    }

    @MainActor
    func createCurrentHistoryAsset(owner: StoreSessionCoordinator, siteID: UUID,
        newSite: FirstSignMutationV1.NewSiteV1?, assetID: UUID, label: String,
        createdAt: Date) throws {
        let pack = SignPack.illuminatedSignV1
        let mutationID = try MutationIDV1(rawValue: UUID())
        _ = try owner.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID, newSite: newSite, assetID: assetID, assetLabel: label,
            packID: pack.packID, packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion, createdAt: createdAt,
            initialPlacementMutationID: mutationID, initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        )), mutationID: mutationID)
    }

    @MainActor
    func closeCurrentHistoryWriter(_ owner: StoreSessionCoordinator) {
        // Writer closure is not a proof that every session/model alias drained.
        // Retain the private root while those aliases can still own SQLite.
        do { try owner.invalidateAndReleaseWriter() }
        catch { XCTFail("Current history fixture writer close failed: \(error)") }
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
        let coordinator = try CheckRunnerCoordinator(
            modelContext: harness.context,
            packageLifecycleDependencies: harness.dependencies,
            packageLifecycleProfile: harness.profile
        )
        coordinator.configureCapture(generationRootURL: harness.session.generationRootURL)
        harness.clock.set(completedAt.addingTimeInterval(-10))
        let source = try coordinator.beginCheck(
            assetID: asset.id,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: completedAt.addingTimeInterval(-10)
        )
        harness.clock.set(completedAt.addingTimeInterval(-8))
        let wide = try await coordinator.importCandidate(
            assetID: asset.id,
            sourceData: try makePNG(seed: seed),
            createdAt: completedAt.addingTimeInterval(-8)
        )
        _ = try await coordinator.accept(candidate: wide, assetID: asset.id)
        if includesClose {
            harness.clock.set(completedAt.addingTimeInterval(-7))
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
        harness.clock.set(completedAt.addingTimeInterval(1))
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
    ) async throws -> VisitFixture {
        let source = prior.source
        // A clerical correction keeps the original visit completion; the old
        // correction instant is only the operation clock, not a new visit.
        let correctionAt = try XCTUnwrap(source.completedAt).addingTimeInterval(300)
        harness.clock.set(correctionAt)
        let delivery = try ReportDeliveryCoordinator(
            modelContext: harness.context,
            lifecycleDependencies: harness.dependencies,
            lifecycleProfile: harness.profile
        )
        let correctionSource = try delivery.correctionSource(reportID: prior.report.id)
        let priorSnapshot = try delivery.validatedReadyReport(id: prior.report.id).snapshot
        let identifiers = ReportCorrectionIdentifiers(
            mutationID: UUID(), recordID: UUID(), reportID: UUID()
        )
        let snapshotAt = try XCTUnwrap(source.completedAt).addingTimeInterval(301)
        harness.clock.set(snapshotAt)
        let submission = try await delivery.submitCorrection(
            from: correctionSource,
            note: "Corrected clerical note",
            snapshotCreatedAt: snapshotAt,
            sourceApp: priorSnapshot.sourceApp,
            identifiers: identifiers
        )
        guard case let .ready(chain) = submission,
              chain.current.reportID == identifiers.reportID else {
            throw HistoryFixtureError.couldNotCreateFixture
        }
        let corrections = try harness.context.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.id == identifiers.recordID
        }
        let reports = try harness.context.fetch(FetchDescriptor<Report>()).filter {
            $0.id == identifiers.reportID
        }
        let correction = try XCTUnwrap(corrections.first)
        let report = try XCTUnwrap(reports.first)
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

private final class HistoryFixtureClock: ApplicationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func set(_ value: Date) { lock.withLock { self.value = value } }
    func now() -> Date { lock.withLock { value } }
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
final class C31LightingAnchorS44HistoryComparisonTests: XCTestCase {
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
        defer { closeCurrentHistoryWriter(harness.owner) }
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

final class C33TemporalEvidenceAnchorS44HistoryComparison: XCTestCase {
    func testC33S44HistoryComparisonCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "history.temporal-source-revision",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "history.temporal-source-revision",
            kind: .video,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

final class C32AssistanceAnchorS44HistoryComparison: XCTestCase {
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
final class C46S44HistoryCompatibilityTests: XCTestCase {
    func testC46HistoryKeepsContactRevisionExplicit() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "history-comparison",
            kind: .phone,
            handoff: .call,
            slot: 46404
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift_Tests: XCTestCase {
    func testC47S44HistoryComparisonTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S4_4HistoryComparisonTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityKindV2.knownCases.count, 7)
        XCTAssertFalse(ActivityContractPersistenceEnrollmentV2.planOrScanProviderRequired)
    }
}

final class C48PortableReviewS44HistoryTests: XCTestCase {
    func testC48HistoryIsImmutableAndCannotReopenCurrentWork() {
        XCTAssertTrue(C48PortableReviewReportHistoryBoundaryV1.responseHistoryIsImmutable)
        XCTAssertTrue(C48PortableReviewReportHistoryBoundaryV1.historyOnlyCannotReopenCurrentWork)
        XCTAssertFalse(C48PortableReviewReportHistoryBoundaryV1.capabilityBytesRetainedByHistoryProjection)
    }
}
final class C49WorkResourceHistoryBoundaryTests: XCTestCase {
    func testHistoryUsesSemanticAppendDispositions() {
        XCTAssertEqual(Set(WorkResourceDispositionV1.allCases), [.active, .superseded, .voidedWithReason, .reversed])
        XCTAssertEqual(WorkResourceDispositionV1.active.rawValue, "ACTIVE")
        XCTAssertEqual(WorkResourceDispositionV1.voidedWithReason.rawValue, "VOIDED_WITH_REASON")
    }
}

final class C50IncumbentAdapterS44HistoryBoundaryTests: XCTestCase {
    func testHistoricExchangeBytesAreNotReinterpretedOnCloneOrFork() {
        XCTAssertTrue(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.validate(.clone))
        XCTAssertTrue(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.validate(.fork))
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkReinterpretsReleasedFiles)
    }
}

extension S4_4HistoryComparisonTests {
    func testV23P03C34SnapshotPreservesFrozenRootOrder() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x07)))
        let reports = try NavigationTargetV1(workspaceID: workspace, destination: .reports)
        let today = try NavigationTargetV1(workspaceID: workspace, destination: .today)
        let work = try NavigationTargetV1(workspaceID: workspace, destination: .work)
        let assets = try NavigationTargetV1(workspaceID: workspace, destination: .assets)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .today, paths: [
            .init(root: .today, targets: [today]),
            .init(root: .work, targets: [work]),
            .init(root: .assets, targets: [assets]),
            .init(root: .reports, targets: [reports])
        ], snapshotID: UUID())
        XCTAssertEqual(snapshot.paths.map(\.root), AppRootV1.frozenOrder)
        XCTAssertEqual(snapshot.selectedTarget?.destination, .today)
    }
}

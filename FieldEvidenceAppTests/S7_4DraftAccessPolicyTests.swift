import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S7_4DraftAccessPolicyTests: XCTestCase {
    private let fileManager = FileManager.default

    func testPurePolicyUsesExactPrecedenceAndLoadingTruth() throws {
        let assetID = UUID()
        let issueID = UUID()
        let gate = Date(timeIntervalSince1970: 1_800_000_100)
        let proof = try XCTUnwrap(RepositoryValidatedDraftV1(
            draftID: UUID(),
            assetID: assetID,
            issueID: issueID,
            entry: .work,
            createdAt: gate.addingTimeInterval(-1),
            gateCheckedAt: gate
        ))
        let threeRoots = Set([UUID(), UUID(), UUID()])

        XCTAssertEqual(evaluate(.formerPaidInactive, .work, 1, threeRoots, proof), .continueExisting)
        XCTAssertEqual(evaluate(.entitled, .createSign, 9, threeRoots), .allow)
        XCTAssertEqual(evaluate(.formerPaidInactive, .check, 1, []), .blockPaid)
        XCTAssertEqual(evaluate(.neverPaid, .createSign, 0, []), .allow)
        XCTAssertEqual(evaluate(.neverPaid, .createSign, 1, []), .blockEvaluation)
        XCTAssertEqual(evaluate(.neverPaid, .check, 1, Set(threeRoots.prefix(2))), .allow)
        XCTAssertEqual(evaluate(.neverPaid, .work, 1, threeRoots), .blockEvaluation)
        XCTAssertEqual(evaluate(.neverPaid, .recheck, 0, []), .blockEvaluation)
        XCTAssertEqual(
            evaluate(.loading(.validCachedEntitlement), .createSign, 4, threeRoots),
            .allow
        )
        XCTAssertEqual(
            evaluate(.loading(.priorPaidWithoutValidCache), .check, 1, []),
            .waitForStore
        )
        XCTAssertEqual(
            evaluate(.loading(.neverPaidWithoutCache), .check, 1, []),
            .allow
        )
        XCTAssertEqual(evaluate(.neverPaid, .check, -1, []), .blockInvalidRequest)
    }

    @MainActor
    func testPaidAccessCreatesMultipleSignsAcrossExistingAndNewSites() async throws {
        let root = try makeApplicationSupport()
        defer { try? fileManager.removeItem(at: root) }
        let session = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        let diagnostics = DiagnosticsStore(applicationSupportURL: root)
        var access = DraftAccessNormalizedStateV1.neverPaid
        let coordinator = FirstSignCoordinator(
            modelContext: session.modelContext,
            diagnosticsStore: diagnostics,
            signPack: .illuminatedSignV1,
            accessState: { access }
        )

        let first = try await coordinator.create(FirstSignInput(
            siteLabel: "North Campus",
            signLabel: "Monument Sign",
            address: "10 Main Street",
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true
        ))
        do {
            _ = try await coordinator.create(FirstSignInput(
                siteLabel: "South Campus",
                signLabel: "Wall Sign"
            ))
            XCTFail("Never-paid access must not create a concurrent sign.")
        } catch let error as FirstSignCoordinatorError {
            XCTAssertEqual(error, .accessDenied(.blockEvaluation))
        }
        XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)

        access = .entitled
        let second = try await coordinator.create(FirstSignInput(
            existingSiteID: first.siteID,
            siteLabel: "",
            signLabel: "Wall Sign"
        ))
        let third = try await coordinator.create(FirstSignInput(
            siteLabel: "South Campus",
            signLabel: "Pylon Sign"
        ))
        XCTAssertEqual(second.siteID, first.siteID)
        XCTAssertNotEqual(third.siteID, first.siteID)
        XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Site>()), 2)
        XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Asset>()), 3)
        XCTAssertEqual(Set(try coordinator.loadAll().map(\.assetID)), [first.assetID, second.assetID, third.assetID])
        XCTAssertEqual((await diagnostics.snapshot()).firstSignCreated, 1)

        let reopened = FirstSignCoordinator(
            modelContext: session.modelContext,
            diagnosticsStore: diagnostics,
            signPack: .illuminatedSignV1,
            accessState: { access }
        )
        XCTAssertEqual(try reopened.loadAll().count, 3)
        XCTAssertEqual(try reopened.siteOptions().count, 2)
    }

    @MainActor
    func testDeletionFreesOnlyLiveSlotWhileCountedRootsRemain() async throws {
        let root = try makeApplicationSupport()
        defer { try? fileManager.removeItem(at: root) }
        let session = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        let context = session.modelContext
        let diagnostics = DiagnosticsStore(applicationSupportURL: root)
        let coordinator = FirstSignCoordinator(
            modelContext: context,
            diagnosticsStore: diagnostics,
            signPack: .illuminatedSignV1,
            accessState: { .neverPaid }
        )
        let createdAt = Date(timeIntervalSince1970: 1_800_100_000)
        insertTombstones(2, into: context, createdAt: createdAt)
        try context.save()

        let first = try await coordinator.create(FirstSignInput(
            siteLabel: "North Campus",
            signLabel: "Monument Sign"
        ))
        try deleteSignRows(first, in: context)
        let replacement = try await coordinator.create(FirstSignInput(
            siteLabel: "Replacement Site",
            signLabel: "Replacement Sign"
        ))
        XCTAssertEqual((await diagnostics.snapshot()).firstSignCreated, 1)

        try deleteSignRows(replacement, in: context)
        insertTombstones(1, into: context, createdAt: createdAt.addingTimeInterval(10))
        try context.save()
        do {
            _ = try await coordinator.create(FirstSignInput(
                siteLabel: "Blocked Site",
                signLabel: "Blocked Sign"
            ))
            XCTFail("Three retained counted roots must block replacement.")
        } catch let error as FirstSignCoordinatorError {
            XCTAssertEqual(error, .accessDenied(.blockEvaluation))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Site>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Packet>()), 3)
    }

    @MainActor
    func testSharedCoordinatorGateBlocksBeforeMutationAndContinuesOnlyExactDraft() async throws {
        let root = try makeApplicationSupport()
        defer { try? fileManager.removeItem(at: root) }
        let session = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        let context = session.modelContext
        let diagnostics = DiagnosticsStore(applicationSupportURL: root)
        let sign = try await FirstSignCoordinator(
            modelContext: context,
            diagnosticsStore: diagnostics,
            signPack: .illuminatedSignV1
        ).create(FirstSignInput(
            siteLabel: "North Campus",
            signLabel: "Monument Sign",
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true
        ))
        var access = DraftAccessNormalizedStateV1.neverPaid
        let runner = CheckRunnerCoordinator(
            modelContext: context,
            signPack: .illuminatedSignV1,
            draftAccessState: { access }
        )
        let createdAt = Date(timeIntervalSince1970: 1_800_200_000)
        insertTombstones(3, into: context, createdAt: createdAt)
        try context.save()

        XCTAssertEqual(
            try runner.accessDecision(
                assetID: sign.assetID,
                requestedStage: .check,
                issueID: nil
            ),
            .blockEvaluation
        )
        do {
            _ = try runner.beginOrResumeDraft(checkSubmission(
                assetID: sign.assetID,
                observedAt: Date().addingTimeInterval(-60)
            ))
            XCTFail("A blocked check must not create a draft.")
        } catch let error as CheckRunnerCoordinatorError {
            XCTAssertEqual(error, .accessDenied(.blockEvaluation))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)

        let packets = try context.fetch(FetchDescriptor<Packet>())
        context.delete(try XCTUnwrap(packets.first))
        try context.save()
        let draft = try runner.beginOrResumeDraft(checkSubmission(
            assetID: sign.assetID,
            observedAt: Date().addingTimeInterval(-60)
        ))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)

        insertTombstones(1, into: context, createdAt: createdAt.addingTimeInterval(20))
        try context.save()
        access = .formerPaidInactive
        XCTAssertEqual(
            try runner.accessDecision(
                assetID: sign.assetID,
                requestedStage: .check,
                issueID: nil
            ),
            .continueExisting
        )
        XCTAssertEqual(
            try runner.beginOrResumeDraft(checkSubmission(
                assetID: sign.assetID,
                observedAt: Date()
            )).id,
            draft.id
        )
        XCTAssertEqual(
            try runner.accessDecision(
                assetID: sign.assetID,
                requestedStage: .work,
                issueID: UUID()
            ),
            .blockInvalidRequest
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
    }
}

private extension S7_4DraftAccessPolicyTests {
    func evaluate(
        _ state: DraftAccessNormalizedStateV1,
        _ entry: DraftAccessEntryV1,
        _ liveAssetCount: Int,
        _ roots: Set<UUID>,
        _ draft: RepositoryValidatedDraftV1? = nil
    ) -> DraftAccessDecisionV1 {
        DraftAccessPolicy.evaluate(DraftAccessPolicyInputV1(
            accessState: state,
            liveAssetCount: liveAssetCount,
            countedStableRootIDs: roots,
            requestedEntry: entry,
            existingDraft: draft
        ))
    }

    func makeApplicationSupport() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S7_4_\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }

    @MainActor
    func insertTombstones(
        _ count: Int,
        into context: ModelContext,
        createdAt: Date
    ) {
        for offset in 0..<count {
            context.insert(Packet(
                id: UUID(),
                stableRootID: UUID(),
                currentRecordID: nil,
                evaluationCounted: true,
                contentDeletedAt: createdAt.addingTimeInterval(Double(offset + 1)),
                createdAt: createdAt
            ))
        }
    }

    @MainActor
    func deleteSignRows(
        _ snapshot: FirstSignSnapshot,
        in context: ModelContext
    ) throws {
        let assets = try context.fetch(FetchDescriptor<Asset>()).filter {
            $0.id == snapshot.assetID
        }
        let sites = try context.fetch(FetchDescriptor<Site>()).filter {
            $0.id == snapshot.siteID
        }
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(sites.count, 1)
        context.delete(try XCTUnwrap(assets.first))
        context.delete(try XCTUnwrap(sites.first))
        try context.save()
    }

    func checkSubmission(
        assetID: UUID,
        observedAt: Date
    ) -> BeginDraftSubmission {
        BeginDraftSubmission(
            assetID: assetID,
            requestedStage: .check,
            issueID: nil,
            observedAtUTC: observedAt,
            confirmedTimeZoneID: nil,
            afterDarkAccepted: true,
            safePositionAccepted: true
        )
    }
}

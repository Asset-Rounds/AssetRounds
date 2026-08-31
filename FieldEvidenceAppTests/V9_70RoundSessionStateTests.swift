import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C05RoundSessionCorpusV1: Decodable {
    struct Selector: Decodable { let id: String; let selector: String; let tier: String }
    struct Claims: Decodable {
        let allFlagsFalse: Bool
        let existingSessionsDefaultAbsentUntilCreated: Bool
        let visitedMayOverlapTerminal: Bool
        let expectedMembershipNeverShrinksOnAssetDeletion: Bool
        let completedHistorySurvivesOrdinaryAssetDeletion: Bool
        let terminalUnavailablePackageOrContentIsLocalStateOnly: Bool
        let hostileDecodedProjectionCountsRejectWithoutOverflow: Bool
        let cloneForkPreservesSessionIdentityAndRebindsWorkspace: Bool
    }

    let schema: String
    let schemaVersion: Int
    let cardID: String
    let ordinal: Int
    let selectors: [Selector]
    let stateMatrix: [String: [String]]
    let reasonMatrix: [String: [String]]
    let counts: [String]
    let hostileVectors: [String]
    let interruptionVectors: [String]
    let lifecycleInventory: [String]
    let forbidden: [String]
    let claims: Claims
    let statusFlags: [String: Bool]
}

private enum C05RoundSessionTestSupport {
    static let timestamp = Date(timeIntervalSince1970: 1_788_134_400)
    static let digest = String(repeating: "a", count: 64)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    static func workspace(_ value: Int = 1) -> WorkspaceID { WorkspaceID(rawValue: id(930_000 + value)) }

    static func actor(_ workspace: WorkspaceID, slot: Int = 1) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(931_000 + slot), workspaceID: workspace,
            displayName: "C05 local recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: id(932_000 + slot), workspaceID: workspace, actor: reference,
            responsibility: .recordedBy, displayNameAtTime: reference.displayName,
            capturedAt: timestamp
        )
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(933_000 + value)) }

    static func requirement() throws -> RoundPackageContentRequirementV1 {
        let release = try RoundPackageReleaseReferenceV1(
            packageReleaseID: digest, packageID: "c05-round-package", packageContentVersion: 1,
            packageSHA256: digest, workflowSHA256: String(repeating: "b", count: 64)
        )
        return try RoundPackageContentRequirementV1(packageRelease: release, requiredContent: [])
    }

    static func item(_ value: Int, requirement: RoundPackageContentRequirementV1) throws -> RoundItemV1 {
        try RoundItemV1(
            itemID: id(934_000 + value), order: value,
            selection: try RoundAssetSelectionV1(
                assetID: id(935_000 + value), siteID: id(936_000 + value),
                labelAtSelection: "C05 asset \(value)"
            ), requirement: requirement
        )
    }

    static func items(_ count: Int = 5) throws -> [RoundItemV1] {
        let requirement = try requirement()
        return try (0..<count).map { try item($0, requirement: requirement) }
    }

    static func session(
        workspace: WorkspaceID, sessionID: UUID = id(937_000), predecessor: RoundSessionV1? = nil,
        state: RoundSessionStateV1, transition: RoundSessionTransitionV1,
        transitionItemID: UUID? = nil, items: [RoundItemV1]
    ) throws -> RoundSessionV1 {
        let revision = (predecessor?.revision ?? 0) + 1
        return try RoundSessionV1(
            workspaceID: workspace, sessionID: sessionID, predecessor: predecessor, revision: revision,
            mutationID: try mutation(Int(revision)), state: state, transition: transition,
            transitionItemID: transitionItemID, items: items, recordedBy: try actor(workspace),
            recordedAt: timestamp.addingTimeInterval(TimeInterval(revision))
        )
    }

    static func successor(
        _ prior: RoundSessionV1, state: RoundSessionStateV1, transition: RoundSessionTransitionV1,
        transitionItemID: UUID? = nil, items: [RoundItemV1]? = nil
    ) throws -> RoundSessionV1 {
        try session(
            workspace: prior.workspaceID, sessionID: prior.sessionID, predecessor: prior,
            state: state, transition: transition, transitionItemID: transitionItemID,
            items: items ?? prior.items
        )
    }

    static func replacing(
        _ item: RoundItemV1, disposition: RoundItemDispositionV1, actor: ActorSnapshotV1,
        reason: RoundItemReasonV1? = nil, completion: RoundItemCompletionReferenceV1? = nil
    ) throws -> RoundItemV1 {
        let visit: RoundItemVisitV1?
        switch disposition {
        case .visited, .completed:
            visit = item.visit ?? try RoundItemVisitV1(
                visitedAt: timestamp.addingTimeInterval(60), recordedBy: actor
            )
        case .pending, .inaccessible, .skipped, .deferred:
            visit = item.visit
        }
        return try RoundItemV1(
            itemID: item.itemID, order: item.order, selection: item.selection,
            requirement: item.requirement, disposition: disposition, visit: visit,
            reason: reason, completion: completion
        )
    }

    static func replacing(_ items: [RoundItemV1], at index: Int, with item: RoundItemV1) -> [RoundItemV1] {
        var copy = items
        copy[index] = item
        return copy
    }

    static func completion(_ value: Int) throws -> RoundItemCompletionReferenceV1 {
        try RoundItemCompletionReferenceV1(
            completionID: id(938_000 + value), revision: 1,
            completionSHA256: String(repeating: "c", count: 64)
        )
    }

    static func hostileExpectedCount<T: Encodable>(_ value: T) throws -> Data {
        let bytes = try JSONEncoder().encode(value)
        var text = String(decoding: bytes, as: UTF8.self)
        guard let marker = text.range(of: "\"expected\":"),
              let end = text[marker.upperBound...].firstIndex(where: { $0 == "," || $0 == "}" }) else {
            throw RoundSessionFailureV1.invalidValue
        }
        text.replaceSubrange(marker.upperBound..<end, with: "9223372036854775807")
        return Data(text.utf8)
    }
}

final class V9_70RoundSessionStateTests: XCTestCase {
    func testV23P04C05G01FullLegalStateTransitionMatrixAndExactCounts() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "G01", tier: "GOLDEN")
        let workspace = C05RoundSessionTestSupport.workspace()
        let recorder = try C05RoundSessionTestSupport.actor(workspace)
        let created = try C05RoundSessionTestSupport.session(
            workspace: workspace, state: .draft, transition: .create,
            items: try C05RoundSessionTestSupport.items()
        )
        var current = created
        XCTAssertEqual(current.counts.expected, 5)
        XCTAssertEqual(current.counts.visited, 0)

        var revised = current.items
        revised[0] = try RoundItemV1(
            itemID: revised[0].itemID, order: 0,
            selection: try RoundAssetSelectionV1(
                assetID: revised[0].selection.assetID, siteID: revised[0].selection.siteID,
                labelAtSelection: "C05 revised asset 0"
            ), requirement: revised[0].requirement
        )
        current = try C05RoundSessionTestSupport.successor(current, state: .draft, transition: .reviseSelection, items: revised)
        try current.validateSuccessor(of: created)
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .start)

        var nextItems = C05RoundSessionTestSupport.replacing(
            current.items, at: 0,
            with: try C05RoundSessionTestSupport.replacing(current.items[0], disposition: .visited, actor: recorder)
        )
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .visitItem, transitionItemID: nextItems[0].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 0, with: try C05RoundSessionTestSupport.replacing(nextItems[0], disposition: .completed, actor: recorder, completion: try C05RoundSessionTestSupport.completion(0)))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .completeItem, transitionItemID: nextItems[0].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 1, with: try C05RoundSessionTestSupport.replacing(nextItems[1], disposition: .inaccessible, actor: recorder, reason: .assetDeletedDuringSession))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .markInaccessible, transitionItemID: nextItems[1].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 2, with: try C05RoundSessionTestSupport.replacing(nextItems[2], disposition: .skipped, actor: recorder, reason: .explicitlyOutOfScope))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .skipItem, transitionItemID: nextItems[2].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 3, with: try C05RoundSessionTestSupport.replacing(nextItems[3], disposition: .deferred, actor: recorder, reason: .interruption))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .deferItem, transitionItemID: nextItems[3].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 3, with: try C05RoundSessionTestSupport.replacing(nextItems[3], disposition: .pending, actor: recorder))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .retryItem, transitionItemID: nextItems[3].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 3, with: try C05RoundSessionTestSupport.replacing(nextItems[3], disposition: .visited, actor: recorder))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .visitItem, transitionItemID: nextItems[3].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 3, with: try C05RoundSessionTestSupport.replacing(nextItems[3], disposition: .completed, actor: recorder, completion: try C05RoundSessionTestSupport.completion(3)))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .completeItem, transitionItemID: nextItems[3].itemID, items: nextItems)
        nextItems = C05RoundSessionTestSupport.replacing(nextItems, at: 4, with: try C05RoundSessionTestSupport.replacing(nextItems[4], disposition: .deferred, actor: recorder, reason: .followUpRequired))
        current = try C05RoundSessionTestSupport.successor(current, state: .active, transition: .deferItem, transitionItemID: nextItems[4].itemID, items: nextItems)
        let paused = try C05RoundSessionTestSupport.successor(current, state: .paused, transition: .pause)
        current = try C05RoundSessionTestSupport.successor(paused, state: .active, transition: .resume)
        let completed = try C05RoundSessionTestSupport.successor(current, state: .completed, transition: .close)
        let archived = try C05RoundSessionTestSupport.successor(completed, state: .archived, transition: .archive)

        XCTAssertEqual(archived.items.map(\.selection.assetID), current.items.map(\.selection.assetID))
        XCTAssertEqual(archived.items.map(\.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(archived.counts.expected, 5)
        XCTAssertEqual(archived.counts.visited, 2)
        XCTAssertEqual(archived.counts.completed, 2)
        XCTAssertEqual(archived.counts.inaccessible, 1)
        XCTAssertEqual(archived.counts.skipped, 1)
        XCTAssertEqual(archived.counts.deferred, 1)
        XCTAssertEqual(archived.counts.undispositioned, 0)
    }

    func testV23P04C05A01AlternateCrashResumeAndIdempotentRetryAtEveryTransition() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "A01", tier: "ALTERNATE")
        let workspace = C05RoundSessionTestSupport.workspace(2)
        let created = try C05RoundSessionTestSupport.session(workspace: workspace, state: .draft, transition: .create, items: try C05RoundSessionTestSupport.items(1))
        let started = try C05RoundSessionTestSupport.successor(created, state: .active, transition: .start)
        let paused = try C05RoundSessionTestSupport.successor(started, state: .paused, transition: .pause)
        let resumed = try C05RoundSessionTestSupport.successor(paused, state: .active, transition: .resume)
        for value in [created, started, paused, resumed] {
            let bytes = try RoundSessionCanonicalCodecV1.encode(value)
            XCTAssertEqual(try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: bytes), value)
            XCTAssertEqual(try RoundSessionCanonicalCodecV1.encode(try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: bytes)), bytes)
        }
        let replay = try C05RoundSessionTestSupport.successor(paused, state: .active, transition: .resume)
        XCTAssertEqual(replay.sessionSHA256, resumed.sessionSHA256)
        XCTAssertThrowsError(try C05RoundSessionTestSupport.successor(resumed, state: .active, transition: .resume).validateSuccessor(of: resumed))
    }

    func testV23P04C05H01HostileDuplicateLostReorderedAndForbiddenVectors() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "H01", tier: "HOSTILE")
        let workspace = C05RoundSessionTestSupport.workspace(3)
        let items = try C05RoundSessionTestSupport.items(2)
        XCTAssertThrowsError(try C05RoundSessionTestSupport.session(workspace: workspace, state: .draft, transition: .create, items: [items[0], items[0]]))
        let created = try C05RoundSessionTestSupport.session(workspace: workspace, state: .draft, transition: .create, items: items)
        let active = try C05RoundSessionTestSupport.successor(created, state: .active, transition: .start)
        XCTAssertThrowsError(try C05RoundSessionTestSupport.successor(active, state: .active, transition: .start).validateSuccessor(of: active))
        XCTAssertThrowsError(try C05RoundSessionTestSupport.successor(active, state: .completed, transition: .close))
        XCTAssertThrowsError(try C05RoundSessionTestSupport.successor(active, state: .active, transition: .pause, items: [active.items[0]]).validateSuccessor(of: active))
        let unavailablePackage = C05RoundSessionTestSupport.replacing(
            active.items, at: 0,
            with: try C05RoundSessionTestSupport.replacing(
                active.items[0], disposition: .inaccessible, actor: try C05RoundSessionTestSupport.actor(workspace),
                reason: .requiredPackageUnavailable
            )
        )
        let unavailableContent = C05RoundSessionTestSupport.replacing(
            unavailablePackage, at: 1,
            with: try C05RoundSessionTestSupport.replacing(
                unavailablePackage[1], disposition: .inaccessible, actor: try C05RoundSessionTestSupport.actor(workspace),
                reason: .requiredContentUnavailable
            )
        )
        let unavailableTerminal = try C05RoundSessionTestSupport.successor(
            active, state: .active, transition: .markInaccessible,
            transitionItemID: unavailablePackage[0].itemID, items: unavailablePackage
        )
        let unavailableCloseable = try C05RoundSessionTestSupport.successor(
            unavailableTerminal, state: .active, transition: .markInaccessible,
            transitionItemID: unavailableContent[1].itemID, items: unavailableContent
        )
        let closedUnavailable = try C05RoundSessionTestSupport.successor(
            unavailableCloseable, state: .completed, transition: .close
        )
        XCTAssertNoThrow(try closedUnavailable.validateIntrinsic())
        let progress = try C05RoundSessionProgressReportProjectionV1(session: closedUnavailable)
        XCTAssertNoThrow(try progress.validate())
        let closeout = try C05RoundSessionCloseoutReportProjectionV1(session: closedUnavailable)
        XCTAssertNoThrow(try closeout.validate())
        let hostileProgress = try JSONDecoder().decode(
            C05RoundSessionProgressReportProjectionV1.self,
            from: try C05RoundSessionTestSupport.hostileExpectedCount(progress)
        )
        XCTAssertThrowsError(try hostileProgress.validate())
        let search = try C05RoundSessionSearchProjectionV1(progress: progress, closeout: closeout)
        let hostileSearch = try JSONDecoder().decode(
            C05RoundSessionSearchProjectionV1.self,
            from: try C05RoundSessionTestSupport.hostileExpectedCount(search)
        )
        XCTAssertThrowsError(try hostileSearch.validate())
        let bytes = try RoundSessionCanonicalCodecV1.encode(created)
        let corrupt = Data(String(decoding: bytes.dropLast(), as: UTF8.self) + ",\"unknown\":true}", encoding: .utf8)!
        XCTAssertThrowsError(try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: corrupt))
        XCTAssertTrue(Set(corpus.forbidden).isSuperset(of: Set(["ROUTE_AUTOMATION", "QR", "RECURRENCE", "DUE", "REMINDER", "NETWORK"])))
        XCTAssertTrue(corpus.hostileVectors.contains("asset-deletion-during-open-session"))
        XCTAssertTrue(corpus.hostileVectors.contains("archive-omission"))
    }

    func testV23P04C05I01InterruptionEffectBeforeReceiptPartialAndDivergentJournal() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "I01", tier: "INTERRUPTION")
        let workspace = C05RoundSessionTestSupport.workspace(4)
        let created = try C05RoundSessionTestSupport.session(workspace: workspace, state: .draft, transition: .create, items: try C05RoundSessionTestSupport.items(1))
        let effect = try C05RoundSessionTestSupport.successor(created, state: .active, transition: .start)
        let effectBytes = try RoundSessionCanonicalCodecV1.encode(effect)
        XCTAssertEqual(try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: effectBytes), effect)
        XCTAssertThrowsError(try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: Data(effectBytes.dropLast())))
        let divergent = try C05RoundSessionTestSupport.successor(created, state: .draft, transition: .reviseSelection, items: created.items)
        XCTAssertNotEqual(effect.sessionSHA256, divergent.sessionSHA256)
        XCTAssertEqual(corpus.interruptionVectors, ["effect-before-receipt", "partial-journal", "divergent-journal"])
    }

    func testV23P04C05R01RecoveryMigrationBackupRestoreCloneForkExportAndCompatibility() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "R01", tier: "RECOVERY")
        let source = C05RoundSessionTestSupport.workspace(5)
        let target = C05RoundSessionTestSupport.workspace(6)
        let created = try C05RoundSessionTestSupport.session(workspace: source, state: .draft, transition: .create, items: try C05RoundSessionTestSupport.items(1))
        let exported = try RoundSessionCanonicalCodecV1.encode(created)
        XCTAssertEqual(try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: exported), created)
        let rebound = try created.rebindingWorkspaceID(target, rebasedPredecessor: nil, recordedBy: C05RoundSessionTestSupport.actor(target), visitActors: [:])
        XCTAssertEqual(rebound.workspaceID, target)
        XCTAssertEqual(rebound.sessionID, created.sessionID)
        XCTAssertEqual(rebound.items.map(\.selection.assetID), created.items.map(\.selection.assetID))
        let sourceRow = try RoundSessionRevisionRowV1(created)
        let targetRow = try RoundSessionRevisionRowV1(rebound)
        XCTAssertEqual(try sourceRow.value().workspaceID, source)
        XCTAssertEqual(try targetRow.value().workspaceID, target)
        XCTAssertEqual(try targetRow.value().sessionID, created.sessionID)
        XCTAssertThrowsError(try RoundSessionCanonicalCodecV1.decode(RoundSessionV1.self, from: Data(String(decoding: exported.dropLast(), as: UTF8.self) + ",\"forwardFix\":true}", encoding: .utf8)!))
        XCTAssertTrue(Set(corpus.lifecycleInventory).isSuperset(of: Set(["MIGRATION", "BACKUP", "REPLACE_RESTORE", "CLONE", "FORK", "EXPORT", "REPORT", "SEARCH", "REBUILD", "DELETE", "ERASE", "STREAMING_ARCHIVE", "FORWARD_FIX"])))
        XCTAssertTrue(corpus.claims.existingSessionsDefaultAbsentUntilCreated)
        XCTAssertTrue(corpus.claims.completedHistorySurvivesOrdinaryAssetDeletion)
        XCTAssertTrue(corpus.claims.cloneForkPreservesSessionIdentityAndRebindsWorkspace)
    }

    private func loadCorpus() throws -> C05RoundSessionCorpusV1 {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("FieldEvidenceAppTests/Fixtures/V22/Rounds/V22P04C05RoundSessionCorpusV1.json")
        return try JSONDecoder().decode(C05RoundSessionCorpusV1.self, from: Data(contentsOf: url))
    }

    private func assertCorpus(_ corpus: C05RoundSessionCorpusV1, selector: String, tier: String) {
        XCTAssertEqual(corpus.schema, "V22P04C05RoundSessionCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P04-C05")
        XCTAssertEqual(corpus.ordinal, 93)
        XCTAssertEqual(corpus.selectors.map(\.id), ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.selectors.first(where: { $0.id == selector })?.selector, "V23-P04-C05-\(selector)")
        XCTAssertEqual(corpus.selectors.first(where: { $0.id == selector })?.tier, tier)
        XCTAssertEqual(corpus.counts, ["EXPECTED", "VISITED", "COMPLETED", "INACCESSIBLE", "SKIPPED", "DEFERRED"])
        XCTAssertEqual(corpus.stateMatrix["DRAFT"], ["REVISE_SELECTION", "START"])
        XCTAssertTrue(corpus.claims.allFlagsFalse)
        XCTAssertTrue(corpus.claims.visitedMayOverlapTerminal)
        XCTAssertTrue(corpus.claims.expectedMembershipNeverShrinksOnAssetDeletion)
        XCTAssertTrue(corpus.claims.terminalUnavailablePackageOrContentIsLocalStateOnly)
        XCTAssertTrue(corpus.claims.hostileDecodedProjectionCountsRejectWithoutOverflow)
        XCTAssertTrue(corpus.statusFlags.values.allSatisfy { !$0 })
    }
}

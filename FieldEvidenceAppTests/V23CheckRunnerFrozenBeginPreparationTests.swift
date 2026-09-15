import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23CheckRunnerFrozenBeginPreparationTests: XCTestCase {
    func testCaptureSourceUsesAuthenticatedEntryAndClosedCanonicalRoundTripWithoutEffects() throws {
        try withFrozenBeginFixture("capture-source", entry: .check, storedTimeZoneID: "America/Chicago") { h in
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            let source = try h.captureSource()

            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(source.sourceCheckpoint.draftID, h.read.chain.sourceCheckpoint.draftID)
            XCTAssertEqual(source.entryProgressCheckpoint.draftID, h.read.chain.nodes.last?.checkpoint.draftID)
            XCTAssertEqual(source.roundAtEntry, try h.read.chain.currentRound.reference)
            XCTAssertEqual(source.originalItem, h.originalItem)
            XCTAssertEqual(source.itemAtEntry, h.entryItem)
            XCTAssertEqual(source.assetID, h.assetID)
            XCTAssertEqual(source.packageRelease, try RoundPackageReleaseReferenceV1(h.publishedRelease))
            XCTAssertEqual(source.legacyPackageIdentity, try PackageReleaseIdentityV1(package: h.signPack))
            XCTAssertEqual(source.requestedEntry, .check)

            let bytes = try FieldDraftCanonicalCodecV1.encode(source)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerRoundItemSourceV1.self, from: bytes
            )
            XCTAssertEqual(decoded, source)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
            try decoded.validate(read: h.read, publishedRelease: h.publishedRelease, signPack: h.signPack)
            XCTAssertEqual(try h.snapshot(), before)

            var unknown = try frozenBeginJSONObject(bytes)
            unknown["futureSourceAuthority"] = true
            assertSourceDecodeFails(unknown)
            var nested = try frozenBeginJSONObject(bytes)
            var request = try XCTUnwrap(nested["requestedEntry"] as? [String: Any])
            request["futureRequestAuthority"] = true
            nested["requestedEntry"] = request
            assertSourceDecodeFails(nested)
            var relationship = try frozenBeginJSONObject(bytes)
            relationship["entryProgressCheckpoint"] = relationship["sourceCheckpoint"]
            assertSourceDecodeFails(relationship)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testPrepareCheckFreezesStoredZoneCompleteCommandAndSourceCASWithoutEffects() throws {
        try withFrozenBeginFixture("stored-zone-check", entry: .check,
                                   storedTimeZoneID: "America/Chicago") { h in
            let source = try h.captureSource()
            let before = try h.snapshot()
            let recordID = beginPreparationUUID(9_001)
            h.ids.enqueue([recordID])
            let idCalls = h.ids.callCount
            let submittedAt = Date(timeIntervalSince1970: 1_789_123_456.789)
            let submission = BeginDraftSubmission(
                assetID: h.assetID, requestedStage: .check, issueID: nil,
                observedAtUTC: submittedAt,
                confirmedTimeZoneID: " Mars/Olympus is ignored because the stored zone wins ",
                afterDarkAccepted: true, safePositionAccepted: true
            )

            let attempt = try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: submission
            )

            XCTAssertEqual(h.ids.callCount, idCalls + 1)
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(attempt.source, source)
            XCTAssertEqual(attempt.sourceWorkspaceID, h.workspaceID)
            XCTAssertEqual(attempt.recordMutationID.rawValue, recordID)
            XCTAssertEqual(attempt.recordCommittedAt, h.clock.millisecondValue)
            XCTAssertNil(attempt.timeZone)
            XCTAssertEqual(attempt.siteID, h.siteID)
            XCTAssertEqual(attempt.resolvedSiteTimeZoneID, "America/Chicago")
            XCTAssertEqual(attempt.recordExpectedEntityRevisions,
                           try h.expectedRecordRevisions(recordID: recordID))
            XCTAssertEqual(attempt.recordCommand,
                           try h.expectedCommand(recordID: recordID, observedAt: submittedAt,
                                                 timeZoneID: "America/Chicago", parentID: nil))

            let sourceBytes = try FieldDraftCanonicalCodecV1.encode(source)
            let attemptBytes = try FieldDraftCanonicalCodecV1.encode(attempt)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerFrozenBeginAttemptV1.self, from: attemptBytes
            )
            XCTAssertEqual(decoded, attempt)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), attemptBytes)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded.source), sourceBytes)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testPrepareRecheckFreezesExplicitIssueParentAndOptionalZoneCommandWithoutEffects() throws {
        let issueID = beginPreparationUUID(9_101)
        try withFrozenBeginFixture("missing-zone-recheck", entry: .recheck(issueID: issueID),
                                   storedTimeZoneID: nil) { h in
            let source = try h.captureSource()
            let before = try h.snapshot()
            let recordID = beginPreparationUUID(9_102)
            let zoneMutationID = beginPreparationUUID(9_103)
            h.ids.enqueue([recordID, zoneMutationID])
            let idCalls = h.ids.callCount
            let submittedAt = Date(timeIntervalSince1970: 1_789_223_456.123)
            let submission = BeginDraftSubmission(
                assetID: h.assetID, requestedStage: .recheck, issueID: issueID,
                observedAtUTC: submittedAt, confirmedTimeZoneID: " America/New_York ",
                afterDarkAccepted: true, safePositionAccepted: true
            )

            let attempt = try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: submission
            )

            XCTAssertEqual(h.ids.callCount, idCalls + 2)
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(attempt.source, source)
            XCTAssertEqual(attempt.recordMutationID.rawValue, recordID)
            XCTAssertEqual(attempt.recordCommand.stage, WorkflowStage.recheck.rawValue)
            XCTAssertEqual(attempt.recordCommand.issueID, issueID)
            XCTAssertEqual(attempt.recordCommand.parentRecordID, h.recheckParentID)
            XCTAssertEqual(attempt.recordExpectedEntityRevisions,
                           try h.expectedRecordRevisions(recordID: recordID))
            XCTAssertEqual(attempt.recordCommand,
                           try h.expectedCommand(recordID: recordID, observedAt: submittedAt,
                                                 timeZoneID: "America/New_York",
                                                 parentID: h.recheckParentID))
            let zone = try XCTUnwrap(attempt.timeZone)
            XCTAssertEqual(zone.mutationID.rawValue, zoneMutationID)
            XCTAssertEqual(zone.command.siteID, h.siteID)
            XCTAssertEqual(zone.command.timeZoneID, "America/New_York")
            XCTAssertEqual(zone.command.confirmedAt, submittedAt)
            XCTAssertEqual(zone.committedAt, h.clock.millisecondValue)
            let current = try h.coordinator.workspaceWriter.currentRevision()
            let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: h.siteID)
            XCTAssertEqual(zone.expectedSiteRevision, try XCTUnwrap(
                current.entityRevisions.first { $0.identity == siteIdentity }
            ).revision)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testInvalidPreflightRequestPackageAndAccessAllocateNoIDsOrEffects() throws {
        try withFrozenBeginFixture("invalid-preflight", entry: .check, storedTimeZoneID: nil) { h in
            let source = try h.captureSource()
            let valid = BeginDraftSubmission(
                assetID: h.assetID, requestedStage: .check, issueID: nil,
                observedAtUTC: Date(timeIntervalSince1970: 1_789_323_456),
                confirmedTimeZoneID: "America/New_York",
                afterDarkAccepted: true, safePositionAccepted: true
            )
            let otherRelease = try frozenBeginShippingRelease(stage: .recheck)
            let cases: [(String, InspectionPackageReleaseV1, BeginDraftSubmission)] = [
                ("missing-observation", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: nil, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("missing-zone", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: nil,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("invalid-zone", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: "Mars/Olympus",
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("missing-after-dark", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: false, safePositionAccepted: true)),
                ("missing-safe-position", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: false)),
                ("asset-mismatch", h.publishedRelease, .init(
                    assetID: beginPreparationUUID(9_204), requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("request-mismatch", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .recheck,
                    issueID: beginPreparationUUID(9_205), observedAtUTC: valid.observedAtUTC,
                    confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("package-mismatch", otherRelease, valid),
            ]
            for (label, release, submission) in cases {
                let before = try h.snapshot()
                let idCalls = h.ids.callCount
                XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                    source: source, progress: h.progress,
                    publishedRelease: release, submission: submission
                ), label)
                XCTAssertEqual(h.ids.callCount, idCalls, label)
                XCTAssertEqual(try h.snapshot(), before, label)
            }

            let denied = try h.makeRunner(draftAccessState: { .formerPaidInactive })
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try denied.captureFrozenBeginSource(
                read: h.read, progress: h.progress, itemID: h.itemID,
                publishedRelease: h.publishedRelease, requestedEntry: .check
            )) { error in
                XCTAssertEqual(error as? CheckRunnerCoordinatorError,
                               .accessDenied(.blockPaid))
            }
            XCTAssertThrowsError(try denied.prepareFrozenBegin(
                source: source, progress: h.progress, publishedRelease: h.publishedRelease,
                submission: valid
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testChangedSourceForeignOwnerDirtyContextCompatibilityAndInvalidSessionFailWithoutPreparationEffects() throws {
        try withFrozenBeginFixture("changed-source", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let latest = try h.progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
            let next = try h.progress.prepareStep(
                read: latest, action: .keepOpenAndNext, focus: .facts,
                completionRecordID: nil, recordedByName: "Advance after frozen entry"
            )
            _ = try h.progress.persistStep(next)
            h.read = try h.progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }

        try withFrozenBeginFixture("foreign-owner", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let foreignProgress = try h.coordinator.makeRepetitiveCaptureProgressService(
                transitions: h.transitions
            )
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try h.runner.captureFrozenBeginSource(
                read: h.read, progress: foreignProgress, itemID: h.itemID,
                publishedRelease: h.publishedRelease, requestedEntry: .check
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }

        try withFrozenBeginFixture("dirty-context", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let site = try XCTUnwrap(h.context.fetch(FetchDescriptor<Site>()).first { $0.id == h.siteID })
            site.label = "Unsaved hostile label"
            XCTAssertTrue(h.context.hasChanges)
            let before = try h.rowSnapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.rowSnapshot(), before)
            XCTAssertTrue(h.context.hasChanges)
            h.context.rollback()
        }

        try withFrozenBeginFixture("invalid-session", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let compatibility = CheckRunnerCoordinator(
                modelContext: h.context, signPack: h.signPack,
                clock: h.clock, idSource: h.ids
            )
            let before = try h.rowSnapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try compatibility.captureFrozenBeginSource(
                read: h.read, progress: h.progress, itemID: h.itemID,
                publishedRelease: h.publishedRelease, requestedEntry: .check
            )) { error in
                XCTAssertEqual(error as? CheckRunnerCoordinatorError,
                               .packageLifecycleMismatch)
            }
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.rowSnapshot(), before)
            try h.closeCoordinator()
            XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.rowSnapshot(), before)
        }
    }

    func testFrozenContractsRejectMalformedClosedBytesAndEncodeNoDestinationAuthority() throws {
        try withFrozenBeginFixture("closed-contract", entry: .check, storedTimeZoneID: nil) { h in
            let source = try h.captureSource()
            let recordID = beginPreparationUUID(9_301)
            let zoneID = beginPreparationUUID(9_302)
            h.ids.enqueue([recordID, zoneID])
            let attempt = try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            )
            let before = try h.snapshot()
            let bytes = try FieldDraftCanonicalCodecV1.encode(attempt)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerFrozenBeginAttemptV1.self, from: bytes
            )
            XCTAssertEqual(decoded, attempt)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)

            let top = try frozenBeginJSONObject(bytes)
            XCTAssertEqual(try decodeFrozenBeginJSON(CheckRunnerFrozenBeginAttemptV1.self, object: top), attempt)
            XCTAssertEqual(try decodeFrozenBeginJSON(CheckRunnerRoundItemSourceV1.self,
                object: frozenBeginJSONObject(FieldDraftCanonicalCodecV1.encode(source))), source)
            XCTAssertEqual(Set(top.keys), Set([
                "source", "sourceWorkspaceID", "recordCommand", "recordMutationID",
                "recordExpectedEntityRevisions", "recordCommittedAt", "timeZone",
                "siteID", "resolvedSiteTimeZoneID",
            ]))
            let allKeys = jsonKeys(top)
            for forbidden in ["destination", "generation", "writer", "bound", "receipt"] {
                XCTAssertFalse(allKeys.contains { $0.lowercased().contains(forbidden) }, forbidden)
            }

            var mutations: [(String, ([String: Any]) throws -> [String: Any])] = []
            mutations.append(("unknown-top", { value in
                var value = value; value["futureDestination"] = true; return value
            }))
            mutations.append(("unknown-source", { value in
                var value = value; var source = try XCTUnwrap(value["source"] as? [String: Any])
                source["futureSource"] = true; value["source"] = source; return value
            }))
            mutations.append(("unknown-command", { value in
                var value = value; var command = try XCTUnwrap(value["recordCommand"] as? [String: Any])
                command["futureCommand"] = true; value["recordCommand"] = command; return value
            }))
            mutations.append(("unknown-revision", { value in
                var value = value; var revisions = try XCTUnwrap(value["recordExpectedEntityRevisions"] as? [[String: Any]])
                revisions[0]["futureRevision"] = true; value["recordExpectedEntityRevisions"] = revisions; return value
            }))
            mutations.append(("unknown-identity", { value in
                var value = value; var revisions = try XCTUnwrap(value["recordExpectedEntityRevisions"] as? [[String: Any]])
                var identity = try XCTUnwrap(revisions[0]["identity"] as? [String: Any])
                identity["futureIdentity"] = true; revisions[0]["identity"] = identity
                value["recordExpectedEntityRevisions"] = revisions; return value
            }))
            mutations.append(("source-relationship", { value in
                var value = value; var source = try XCTUnwrap(value["source"] as? [String: Any])
                source["entryProgressCheckpoint"] = source["sourceCheckpoint"]
                value["source"] = source; return value
            }))
            mutations.append(("command-identity", { value in
                var value = value; var command = try XCTUnwrap(value["recordCommand"] as? [String: Any])
                command["recordID"] = beginPreparationUUID(9_399).uuidString.lowercased()
                value["recordCommand"] = command; return value
            }))
            mutations.append(("zero-mutation-id", { value in
                var value = value; value["recordMutationID"] = "00000000-0000-0000-0000-000000000000"; return value
            }))
            mutations.append(("negative-revision", { value in
                var value = value; var revisions = try XCTUnwrap(value["recordExpectedEntityRevisions"] as? [[String: Any]])
                revisions[0]["revision"] = -1; value["recordExpectedEntityRevisions"] = revisions; return value
            }))
            mutations.append(("negative-time", { value in
                var value = value; value["recordCommittedAt"] = -1_000_000_000; return value
            }))
            mutations.append(("malformed-zone", { value in
                var value = value; var command = try XCTUnwrap(value["recordCommand"] as? [String: Any])
                command["timeZoneID"] = "Mars/Olympus"; value["recordCommand"] = command
                value["resolvedSiteTimeZoneID"] = "Mars/Olympus"
                var zone = try XCTUnwrap(value["timeZone"] as? [String: Any])
                var zoneCommand = try XCTUnwrap(zone["command"] as? [String: Any])
                zoneCommand["timeZoneID"] = "Mars/Olympus"; zone["command"] = zoneCommand
                value["timeZone"] = zone; return value
            }))
            mutations.append(("unknown-zone-command", { value in
                var value = value; var zone = try XCTUnwrap(value["timeZone"] as? [String: Any])
                var command = try XCTUnwrap(zone["command"] as? [String: Any])
                command["futureZoneAuthority"] = true; zone["command"] = command
                value["timeZone"] = zone; return value
            }))
            mutations.append(("unknown-zone-attempt", { value in
                var value = value; var zone = try XCTUnwrap(value["timeZone"] as? [String: Any])
                zone["futureZoneAttemptAuthority"] = true; value["timeZone"] = zone
                return value
            }))

            for (label, mutate) in mutations {
                let hostile = try mutate(top)
                XCTAssertThrowsError(try decodeFrozenBeginJSON(
                    CheckRunnerFrozenBeginAttemptV1.self, object: hostile
                ), label)
            }
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(source),
                           try FieldDraftCanonicalCodecV1.encode(attempt.source))
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(attempt), bytes)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    private func assertSourceDecodeFails(
        _ object: [String: Any], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try decodeFrozenBeginJSON(
            CheckRunnerRoundItemSourceV1.self, object: object
        ), file: file, line: line)
    }
}

@MainActor
func withFrozenBeginFixture<Value>(
    _ label: String, entry: CheckRunnerRequestedEntryV1, storedTimeZoneID: String?,
    _ body: (FrozenBeginFixture) throws -> Value
) throws -> Value {
    var root: URL?
    do {
        let value = try autoreleasepool { () throws -> Value in
            let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
                "V23-frozen-begin-\(label)-\(UUID().uuidString)", isDirectory: true
            )
            root = fixtureRoot
            let fixture = try FrozenBeginFixture(
                root: fixtureRoot, entry: entry, storedTimeZoneID: storedTimeZoneID
            )
            do {
                let value = try body(fixture)
                try fixture.closeCoordinator()
                return value
            } catch {
                try? fixture.closeCoordinator()
                throw error
            }
        }
        if let root { try FileManager.default.removeItem(at: root) }
        return value
    } catch {
        if let root { try? FileManager.default.removeItem(at: root) }
        throw error
    }
}

@MainActor
final class FrozenBeginFixture {
    struct SiteAnchor: Equatable { let id: UUID; let label: String; let timeZoneID: String?; let updatedAt: Date }
    struct AssetAnchor: Equatable {
        let id: UUID; let siteID: UUID; let packID: String
        let schemaVersion: Int; let contentVersion: Int; let label: String; let updatedAt: Date
    }
    struct WorkflowAnchor: Equatable {
        let id: UUID; let assetID: UUID; let issueID: UUID?; let parentID: UUID?
        let stage: String; let state: String; let startedAt: Date; let timeZoneID: String?
    }
    struct IssueAnchor: Equatable {
        let id: UUID; let assetID: UUID; let openedBy: UUID; let status: String; let resolvedBy: UUID?
    }
    struct RowSnapshot: Equatable {
        let checkpointBytes: [Data]; let roundBytes: [Data]; let packageBytes: [Data]
        let sites: [SiteAnchor]; let assets: [AssetAnchor]
        let workflows: [WorkflowAnchor]; let issues: [IssueAnchor]; let hasChanges: Bool
    }
    struct Snapshot: Equatable {
        let revision: WorkspaceRevisionV1
        let history: MutationHistorySnapshotV1
        let rows: RowSnapshot
    }

    let root: URL
    let factory: StoreGenerationFactory
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let profile: WorkspacePackageLifecycleProfileV1
    let signPack: SignPack
    let publishedRelease: InspectionPackageReleaseV1
    let ids: FrozenBeginCountingIDs
    let clock: FrozenBeginClock
    let transitions: ProductionRoundSessionTransitionServiceV1
    let progress: ProductionRepetitiveCaptureProgressServiceV2
    let runner: CheckRunnerCoordinator
    let siteID: UUID
    let assetID: UUID
    let itemID: UUID
    let originalItem: RoundItemV1
    let entryItem: RoundItemV1
    let issueID: UUID?
    let recheckParentID: UUID?
    var read: ProductionRepetitiveCaptureReadV2
    private var coordinatorClosed = false

    var context: ModelContext { session.modelContext }
    var workspaceID: WorkspaceID { session.workspaceID }

    init(root: URL, entry: CheckRunnerRequestedEntryV1, storedTimeZoneID: String?) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: beginPreparationUUID(10_001)),
            replicaID: ReplicaID(rawValue: beginPreparationUUID(10_002))
        )
        let localFactory = StoreGenerationFactory(
            applicationSupportURL: root, pointerEnrichmentIdentity: identity
        )
        factory = localFactory
        let localSession = try localFactory.openOrBootstrapCurrent()
        session = localSession
        let localIDs = FrozenBeginCountingIDs()
        ids = localIDs
        let localClock = FrozenBeginClock(value: Date(timeIntervalSince1970: 1_789_500_000.4567))
        clock = localClock
        let registry = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        let localCoordinator = try StoreSessionCoordinator(
            validatingSession: localSession, clock: localClock, idSource: localIDs,
            lifecycleProfileRegistry: registry
        )
        coordinator = localCoordinator
        let localProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: .illuminatedSignV1
        )
        profile = localProfile
        signPack = localProfile.package
        let localRelease = try frozenBeginShippingRelease(stage: entry.stage)
        publishedRelease = localRelease
        try Self.installPublishedRelease(localRelease, in: localCoordinator, context: localSession.modelContext)

        let localSiteID = beginPreparationUUID(10_010)
        let localAssetID = beginPreparationUUID(10_011)
        siteID = localSiteID
        assetID = localAssetID
        let firstMutation = try MutationIDV1(rawValue: beginPreparationUUID(10_012))
        _ = try localCoordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: localSiteID,
            newSite: .init(id: localSiteID, label: "North Campus", address: "10 Main",
                           timeZoneID: storedTimeZoneID),
            assetID: localAssetID, assetLabel: "Monument Sign",
            packID: localProfile.package.packID,
            packSchemaVersion: localProfile.package.schemaVersion,
            packContentVersion: localProfile.package.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_789_000_000),
            initialPlacementMutationID: firstMutation,
            initialPlacementEventID: beginPreparationUUID(10_013),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                rawValue: beginPreparationUUID(10_014)
            )
        )), mutationID: firstMutation)

        var localIssueID: UUID?
        var localParentID: UUID?
        if case let .recheck(requestedIssueID) = entry {
            localIssueID = requestedIssueID
            localParentID = beginPreparationUUID(10_020)
            try Self.installRecheckLineage(
                issueID: requestedIssueID, parentID: localParentID!, assetID: localAssetID,
                signPack: localProfile.package, coordinator: localCoordinator,
                context: localSession.modelContext
            )
        }
        issueID = localIssueID
        recheckParentID = localParentID

        let localItemID = beginPreparationUUID(10_030)
        itemID = localItemID
        let actor = try Self.actor(workspaceID: localSession.workspaceID)
        let requirement = try RoundPackageContentRequirementV1(
            packageRelease: .init(localRelease), requiredContent: []
        )
        let pending = try RoundItemV1(
            itemID: localItemID, order: 0,
            selection: .init(assetID: localAssetID, siteID: localSiteID,
                             labelAtSelection: "Monument Sign"),
            requirement: requirement
        )
        originalItem = pending
        let draft = try RoundSessionV1(
            workspaceID: localSession.workspaceID, sessionID: beginPreparationUUID(10_031),
            revision: 1, mutationID: .init(rawValue: beginPreparationUUID(10_032)),
            state: .draft, transition: .create, items: [pending],
            recordedBy: actor, recordedAt: Date(timeIntervalSince1970: 1_789_000_100)
        )
        _ = try localCoordinator.workspaceWriter.commitRoundSession(.init(
            workspaceID: localSession.workspaceID, expectedRevision: 0,
            mutationID: draft.mutationID, session: draft
        ))
        let active = try RoundSessionV1(
            workspaceID: localSession.workspaceID, sessionID: draft.sessionID,
            predecessor: draft, revision: 2,
            mutationID: .init(rawValue: beginPreparationUUID(10_033)),
            state: .active, transition: .start, items: [pending],
            recordedBy: actor, recordedAt: Date(timeIntervalSince1970: 1_789_000_101)
        )
        _ = try localCoordinator.workspaceWriter.commitRoundSession(.init(
            workspaceID: localSession.workspaceID, expectedRevision: draft.revision,
            mutationID: active.mutationID, session: active
        ))

        let gate = AppAccessGateV1(
            setting: .absentDisabled, authentication: FrozenBeginAuthentication(),
            clock: localClock, identifiers: localIDs
        )
        let localTransitions = try localCoordinator.makeRoundSessionTransitionService(accessGate: gate)
        transitions = localTransitions
        let localProgress = try localCoordinator.makeRepetitiveCaptureProgressService(
            transitions: localTransitions
        )
        progress = localProgress
        let manifest = try Self.manifest(round: active, release: localRelease)
        let sourceWrite = try localProgress.prepareSource(round: active, manifest: manifest)
        let sourceRead = try localProgress.persistSource(sourceWrite)
        let entryWrite = try localProgress.prepareStep(
            read: sourceRead, action: .enter, focus: .facts, completionRecordID: nil,
            recordedByName: "Frozen Begin entry recorder"
        )
        _ = try localProgress.persistStep(entryWrite)
        let roundMutation = try XCTUnwrap(entryWrite.step.roundMutation)
        _ = try localCoordinator.workspaceWriter.commitRoundSession(roundMutation)
        let localRead = try localProgress.read(sourceDraftID: sourceWrite.checkpoint.draftID)
        read = localRead
        entryItem = try XCTUnwrap(localRead.chain.currentRound.items.first { $0.itemID == localItemID })
        try localProgress.validateForPublication(localRead)
        runner = try CheckRunnerCoordinator(
            modelContext: localSession.modelContext,
            packageLifecycleDependencies: localCoordinator.packageLifecycleDependencies(
                profileRegistry: registry
            ),
            packageLifecycleProfile: localProfile
        )
        _ = try localCoordinator.workspaceWriter.sourceMutationHistorySnapshot()
        XCTAssertFalse(localSession.modelContext.hasChanges)
    }

    func captureSource() throws -> CheckRunnerRoundItemSourceV1 {
        try runner.captureFrozenBeginSource(
            read: read, progress: progress, itemID: itemID,
            publishedRelease: publishedRelease,
            requestedEntry: issueID.map { .recheck(issueID: $0) } ?? .check
        )
    }

    func validSubmission() -> BeginDraftSubmission {
        BeginDraftSubmission(
            assetID: assetID, requestedStage: issueID == nil ? .check : .recheck,
            issueID: issueID,
            observedAtUTC: Date(timeIntervalSince1970: 1_789_323_456),
            confirmedTimeZoneID: "America/New_York",
            afterDarkAccepted: true, safePositionAccepted: true
        )
    }

    func makeRunner(
        draftAccessState: @escaping @MainActor () -> DraftAccessNormalizedStateV1
    ) throws -> CheckRunnerCoordinator {
        try CheckRunnerCoordinator(
            modelContext: context,
            packageLifecycleDependencies: coordinator.packageLifecycleDependencies(
                profileRegistry: coordinator.lifecycleProfileRegistry
            ),
            packageLifecycleProfile: profile,
            draftAccessState: draftAccessState
        )
    }

    func expectedRecordRevisions(recordID: UUID) throws -> [WorkspaceEntityRevisionV1] {
        let current = try coordinator.workspaceWriter.currentRevision()
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        var identities = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: recordID),
            WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
        ]
        if let issueID { identities.append(try .init(kind: .issue, id: issueID)) }
        if let recheckParentID {
            identities.append(try .init(kind: .workflowRecord, id: recheckParentID))
        }
        return identities.sorted { $0.stableKey < $1.stableKey }.map {
            .init(identity: $0, revision: known[$0, default: 0])
        }
    }

    func expectedCommand(
        recordID: UUID, observedAt: Date, timeZoneID: String, parentID: UUID?
    ) throws -> CheckDraftMutationV1 {
        let frozen = try TimeContextRule.freeze(
            observedAtUTC: observedAt, confirmedTimeZoneID: timeZoneID
        )
        let afterDark = try XCTUnwrap(signPack.acknowledgements.first { $0.key == "after_dark" })
        let safe = try XCTUnwrap(signPack.acknowledgements.first {
            $0.key == "safe_authorized_position"
        })
        return CheckDraftMutationV1(
            recordID: recordID, assetID: assetID, issueID: issueID,
            parentRecordID: parentID, stage: issueID == nil
                ? WorkflowStage.check.rawValue : WorkflowStage.recheck.rawValue,
            draftStepKey: WorkflowDraftStep.wide.rawValue,
            startedAt: observedAt, observedAtUTC: frozen.observedAtUTC,
            timeZoneID: frozen.timeZoneID, utcOffsetMinutes: frozen.utcOffsetMinutes,
            localDate: frozen.localDate, localTime: frozen.localTime,
            afterDarkAcknowledgementKey: afterDark.key,
            afterDarkAcknowledgementCopy: afterDark.copy,
            afterDarkAcknowledgementVersion: afterDark.version,
            afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: safe.key,
            safePositionAcknowledgementCopy: safe.copy,
            safePositionAcknowledgementVersion: safe.version,
            safePositionAcknowledgementAccepted: true,
            packID: signPack.packID, packSchemaVersion: signPack.schemaVersion,
            packContentVersion: signPack.contentVersion,
            pdfTemplateID: profile.pdfTemplate.id,
            pdfTemplateVersion: profile.pdfTemplate.version
        )
    }

    func snapshot() throws -> Snapshot {
        Snapshot(
            revision: try coordinator.workspaceWriter.currentRevision(),
            history: try coordinator.workspaceWriter.sourceMutationHistorySnapshot(),
            rows: try rowSnapshot()
        )
    }

    func rowSnapshot() throws -> RowSnapshot {
        let checkpoints = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map {
            try $0.value()
        }.sorted { $0.draftID.uuidString < $1.draftID.uuidString }
        let rounds = try context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).map {
            try $0.value()
        }.sorted {
            ($0.sessionID.uuidString, $0.revision) < ($1.sessionID.uuidString, $1.revision)
        }
        let packages = try context.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map {
            try $0.value()
        }.sorted { $0.releaseRecordID.uuidString < $1.releaseRecordID.uuidString }
        return RowSnapshot(
            checkpointBytes: try checkpoints.map { try FieldDraftCanonicalCodecV1.encode($0) },
            roundBytes: try rounds.map { try RoundSessionCanonicalCodecV1.encode($0) },
            packageBytes: try packages.map { try PackageEvolutionCanonicalCodecV1.encode($0) },
            sites: try context.fetch(FetchDescriptor<Site>()).map {
                .init(id: $0.id, label: $0.label, timeZoneID: $0.timeZoneID, updatedAt: $0.updatedAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: try context.fetch(FetchDescriptor<Asset>()).map {
                .init(id: $0.id, siteID: $0.siteID, packID: $0.packID,
                      schemaVersion: $0.packSchemaVersion,
                      contentVersion: $0.packContentVersion,
                      label: $0.label, updatedAt: $0.updatedAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            workflows: try context.fetch(FetchDescriptor<WorkflowRecord>()).map {
                .init(id: $0.id, assetID: $0.assetID, issueID: $0.issueID,
                      parentID: $0.parentRecordID, stage: $0.stage, state: $0.state,
                      startedAt: $0.startedAt, timeZoneID: $0.timeZoneID)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            issues: try context.fetch(FetchDescriptor<Issue>()).map {
                .init(id: $0.id, assetID: $0.assetID, openedBy: $0.openedByRecordID,
                      status: $0.status, resolvedBy: $0.resolvedByRecordID)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            hasChanges: context.hasChanges
        )
    }

    func closeCoordinator() throws {
        guard !coordinatorClosed else { return }
        try coordinator.invalidateAndReleaseWriter()
        coordinatorClosed = true
    }

    private static func installPublishedRelease(
        _ release: InspectionPackageReleaseV1,
        in coordinator: StoreSessionCoordinator,
        context: ModelContext
    ) throws {
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID, allowStateBootstrap: false
        )
        try journal.validateAll()
        let promoted = try PromotedPackageReleaseV1(
            releaseRecordID: beginPreparationUUID(10_040),
            workspaceID: coordinator.workspaceID, packageRelease: release,
            mutationID: .init(rawValue: beginPreparationUUID(10_041)),
            promotedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )
        context.insert(try PromotedPackageReleaseRow(promoted))
        context.insert(EntityMutationRevisionRow(
            identity: try .init(kind: .promotedPackageRelease, id: promoted.releaseRecordID),
            revision: promoted.revision, externalProjectionSHA256: promoted.releaseRecordSHA256
        ))
        try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
        try context.save()
        try journal.validateAll()
    }

    private static func installRecheckLineage(
        issueID: UUID, parentID: UUID, assetID: UUID, signPack: SignPack,
        coordinator: StoreSessionCoordinator, context: ModelContext
    ) throws {
        let openingID = beginPreparationUUID(10_021)
        let opening = completedRecord(
            id: openingID, assetID: assetID, issueID: issueID, parentID: nil,
            stage: .check, signPack: signPack
        )
        let parent = completedRecord(
            id: parentID, assetID: assetID, issueID: issueID, parentID: openingID,
            stage: .work, signPack: signPack
        )
        let issue = Issue(
            id: issueID, assetID: assetID, openedByRecordID: openingID,
            labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark",
            status: .recheckDue, resolvedByRecordID: nil,
            createdAt: opening.startedAt, updatedAt: parent.completedAt ?? parent.startedAt
        )
        context.insert(opening); context.insert(parent); context.insert(issue)
        for record in [opening, parent] {
            let basis = try XCTUnwrap(ObservationAndTimeLegacyMigrationV1.observationBasis(
                couldNotVerifyKey: record.couldNotVerifyKey,
                displaySnapshot: record.couldNotVerifyDisplaySnapshot,
                registryVersion: record.couldNotVerifyRegistryVersion
            ))
            let temporal = try XCTUnwrap(ObservationAndTimeLegacyMigrationV1.temporalContext(
                observedAtUTC: record.observedAtUTC, recordedAtUTC: record.startedAt,
                timeZoneID: record.timeZoneID, utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate, localTime: record.localTime
            ))
            context.insert(try ObservationAndTimeRow(
                recordID: record.id, observationBasis: basis, temporalContext: temporal
            ))
        }
        XCTAssertEqual(Set(try ObservationAndTimeRowStoreV1.validatedIndex(in: context).keys),
                       Set([openingID, parentID]))
        for identity in try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: openingID),
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: parentID),
            WorkspaceEntityIdentityV1(kind: .issue, id: issueID),
        ] {
            context.insert(EntityMutationRevisionRow(identity: identity, revision: 1))
        }
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID, allowStateBootstrap: false
        )
        try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
        try context.save()
        try journal.validateAll()
    }

    private static func completedRecord(
        id: UUID, assetID: UUID, issueID: UUID, parentID: UUID?,
        stage: WorkflowStage, signPack: SignPack
    ) -> WorkflowRecord {
        WorkflowRecord(
            id: id, assetID: assetID, packetID: nil, issueID: issueID,
            parentRecordID: parentID, recordRevisionRootID: id,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: stage, state: .completed,
            draftStepKey: nil, startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200), observedAtUTC: nil,
            timeZoneID: nil, utcOffsetMinutes: nil, localDate: nil, localTime: nil,
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: nil,
            packID: signPack.packID, packSchemaVersion: signPack.schemaVersion,
            packContentVersion: signPack.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: stage == .work ? "work_recorded" : "visible_issue",
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: stage == .work ? "1970-01-01" : nil,
            workDescription: stage == .work ? "Completed fixture work" : nil,
            note: nil, finalizationMutationID: beginPreparationUUID(10_090 + (stage == .work ? 1 : 0))
        )
    }

    private static func actor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let actor = try LocalActorReferenceV1(
            actorReferenceID: beginPreparationUUID(10_050), workspaceID: workspaceID,
            displayName: "Frozen Begin fixture"
        )
        return try ActorSnapshotV1(
            snapshotID: beginPreparationUUID(10_051), workspaceID: workspaceID,
            actor: actor, responsibility: .recordedBy,
            displayNameAtTime: "Frozen Begin fixture",
            capturedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )
    }

    private static func manifest(
        round: RoundSessionV1, release: InspectionPackageReleaseV1
    ) throws -> OfflineReadinessManifestV1 {
        let package = try RoundPackageReleaseReferenceV1(release)
        return try OfflineReadinessManifestBuilderV1.build(snapshot: .init(
            session: round.reference, expectedPackage: package, observedPackage: package,
            selectedAssets: round.items.map(\.selection).sorted {
                $0.assetID.uuidString < $1.assetID.uuidString
            },
            observedAssetIDs: Set(round.items.map { $0.selection.assetID }),
            guidanceReferenceIDs: [], availableGuidanceReferenceIDs: [],
            contentRequirements: [], contentObservations: [], expectedFieldReferences: [],
            fieldReferenceReadiness: [],
            storage: .init(capacityState: .checked, availableBytes: 100_000),
            access: .init(protectedDataAvailable: true),
            checkedAt: Date(timeIntervalSince1970: 1_789_000_000),
            timeZoneIdentifier: "America/New_York", clockState: .checked
        ))
    }
}

final class FrozenBeginCountingIDs: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [UUID] = []
    private var count = 0

    var callCount: Int { lock.withLock { count } }

    func enqueue(_ values: [UUID]) {
        lock.withLock { queued.append(contentsOf: values) }
    }

    func makeID() -> UUID {
        lock.withLock {
            count += 1
            if !queued.isEmpty { return queued.removeFirst() }
            return beginPreparationUUID(20_000 + count)
        }
    }
}

final class FrozenBeginClock: ApplicationClock, @unchecked Sendable {
    let value: Date
    var millisecondValue: Date {
        Date(timeIntervalSince1970: floor(value.timeIntervalSince1970 * 1_000) / 1_000)
    }
    init(value: Date) { self.value = value }
    func now() -> Date { value }
}

actor FrozenBeginAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

func frozenBeginShippingRelease(stage: WorkflowStage) throws -> InspectionPackageReleaseV1 {
    let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
    let workflow = try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(
        from: .illuminatedSignV1, stage: stage
    )
    return try InspectionPackageReleasePublisherV1.publish(
        InspectionPackageReleasePublisherV1.test(.makeDraft(package: package, workflow: workflow))
    ).release
}

func beginPreparationUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", value))!
}

func frozenBeginJSONObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Semantic fixture mutations still pass closed typed decoding and the real
/// canonical codec. Transport formatting must not mask their target predicate.
func decodeFrozenBeginJSON<Value: Codable>(_ type: Value.Type, object: [String: Any]) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    let value = try decoder.decode(type, from: data)
    return try FieldDraftCanonicalCodecV1.decode(type, from: FieldDraftCanonicalCodecV1.encode(value))
}

private func jsonKeys(_ value: Any) -> Set<String> {
    if let object = value as? [String: Any] {
        return object.reduce(into: Set(object.keys)) { result, pair in
            result.formUnion(jsonKeys(pair.value))
        }
    }
    if let array = value as? [Any] {
        return array.reduce(into: Set<String>()) { result, element in
            result.formUnion(jsonKeys(element))
        }
    }
    return []
}

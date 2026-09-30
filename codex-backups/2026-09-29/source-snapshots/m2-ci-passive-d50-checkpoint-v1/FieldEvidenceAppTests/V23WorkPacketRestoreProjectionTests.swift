import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23WorkPacketRestoreProjectionTests: XCTestCase {
    private let lifetime = WorkPacketRestoreFixtureLifetime()

    func testWriterProducedFiveKindHistoryPlansExactImagesAndRejectsHostileDTOs() throws {
        let fixture = try makeSource("planner")
        let sourceHistory = try journal(fixture.harness.session).exportSnapshot()
        let records = try exportRecords(fixture.harness)
        let original = try XCTUnwrap(records.mutationHistory)
        try MutationJournalStoreV1.validateImportedSnapshot(original)
        // Archive identity order is lexical (10 precedes 2); the live journal
        // retains numeric sequence order. Both preserve each complete record.
        XCTAssertEqual(try sourceHistory.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData).identity.localSequence
        }, Array(UInt64(1)...UInt64(10)))
        XCTAssertEqual(try original.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData).identity.localSequence
        }, [UInt64(1), 10, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(original, try BackupCanonicalEncoderV1.archiveOrderedMutationHistory(sourceHistory))
        XCTAssertEqual(records.workPackets, try fixture.values.records())
        XCTAssertEqual(Set(records.workPackets.map(\.kind)), Set(V15BackupWorkPacketRecordV1.Kind.allCases))
        XCTAssertEqual(records.workPackets.count, 7) // Includes genuine claim and lease successors.
        XCTAssertEqual(try MutationJournalStoreV1.planningCoreRestoreHistory(
            in: records, workspaceID: fixture.values.workspaceID), original)
        try assertImages(fixture.values, history: original, externallyProjected: false)

        let destination = try Values(workspaceID: WorkspaceID())
        let projectedInput = try replacing(records, workPackets: destination.records(),
            actors: destination.actorRecords())
        let projected = try MutationJournalStoreV1.planningCoreRestoreHistory(
            in: projectedInput, workspaceID: destination.workspaceID)
        XCTAssertEqual(projected.receipts, original.receipts)
        XCTAssertEqual(projected.quarantines, original.quarantines)
        XCTAssertEqual(projected.workspaceRevision, original.workspaceRevision)
        XCTAssertEqual(projected.lastLocalSequence, original.lastLocalSequence)
        XCTAssertEqual(projected.entityRevisions.map(\.identity), original.entityRevisions.map(\.identity))
        XCTAssertEqual(projected.entityRevisions.map(\.revision), original.entityRevisions.map(\.revision))
        try assertImages(destination, history: projected, externallyProjected: true)

        // The exact construction used by every hostile must preserve all fields
        // when unchanged, so a codec artifact cannot make the negatives vacuous.
        let unchanged = try replacing(projectedInput, workPackets: projectedInput.workPackets)
        XCTAssertEqual(unchanged, projectedInput)
        XCTAssertEqual(try MutationJournalStoreV1.planningCoreRestoreHistory(
            in: unchanged, workspaceID: destination.workspaceID), projected)
        for row in projectedInput.workPackets {
            let remaining = projectedInput.workPackets.filter { !($0.kind == row.kind && $0.id == row.id) }
            let wrongKind: V15BackupWorkPacketRecordV1.Kind = row.kind == .manifest ? .claim : .manifest
            let hostiles: [[V15BackupWorkPacketRecordV1]] = [
                remaining,
                projectedInput.workPackets + [row],
                remaining + [.init(kind: wrongKind, id: row.id, workspaceID: row.workspaceID,
                    revision: row.revision, canonicalData: row.canonicalData)],
                remaining + [.init(kind: row.kind, id: UUID(), workspaceID: row.workspaceID,
                    revision: row.revision, canonicalData: row.canonicalData)],
                remaining + [.init(kind: row.kind, id: row.id, workspaceID: UUID(),
                    revision: row.revision, canonicalData: row.canonicalData)],
                remaining + [.init(kind: row.kind, id: row.id, workspaceID: row.workspaceID,
                    revision: row.revision + 1, canonicalData: row.canonicalData)],
                remaining + [.init(kind: row.kind, id: row.id, workspaceID: row.workspaceID,
                    revision: row.revision, canonicalData: Data("{}".utf8))],
            ]
            for (index, hostile) in hostiles.enumerated() {
                let input = try replacing(projectedInput, workPackets: hostile)
                XCTAssertThrowsError(try MutationJournalStoreV1.planningCoreRestoreHistory(
                    in: input, workspaceID: destination.workspaceID), "\(row.kind)/\(row.id)/\(index)")
            }
            // Intrinsically valid foreign bytes cannot hide behind a target wrapper.
            let foreign = try XCTUnwrap(records.workPackets.first { $0.kind == row.kind && $0.id == row.id })
            let foreignInput = try replacing(projectedInput, workPackets: remaining + [.init(
                kind: row.kind, id: row.id, workspaceID: row.workspaceID,
                revision: row.revision, canonicalData: foreign.canonicalData)])
            XCTAssertThrowsError(try MutationJournalStoreV1.planningCoreRestoreHistory(
                in: foreignInput, workspaceID: destination.workspaceID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
        }
        // Planning and all hostile probes leave the actual source untouched.
        XCTAssertEqual(try journal(fixture.harness.session).exportSnapshot(), sourceHistory)
        XCTAssertEqual(try persistedRecords(fixture.harness.session), records.workPackets)
        XCTAssertFalse(fixture.harness.session.modelContext.hasChanges)
    }

    func testFiveKindPublicReplacementAndColdReadbackPreserveImmutableOriginals() async throws {
        let fixture = try makeSource("physical")
        let source = fixture.harness
        let sourceHistory = try journal(source.session).exportSnapshot()
        let archive = try V906Integration.exportStreaming(source)
        let target = try V906Integration.makeHarness("work-packet-target", withAsset: false)
        registerCleanup(target)
        let targetHistory = try seedNonemptyDestination(target)
        XCTAssertFalse(BackupRestoreService.isEmptyCurrent(target.session.modelContext))
        let expected = try Values(workspaceID: target.session.workspaceID)
        let expectedRows = try expected.records()
        XCTAssertNotEqual(expectedRows, try fixture.values.records())
        let restoredID: UUID
        let restoredHistory: MutationHistorySnapshotV1
        do {
            lifetime.beginAcquisition(root: target.root)
            let restored = try await V906Integration.restore(archive, into: target,
                mode: .replaceExisting, ids: V906Integration.restoreIDs(.replaceExisting, offset: 901))
            lifetime.observe(restored, root: target.root)
            restoredID = restored.generationID
            XCTAssertEqual(try persistedRecords(restored), expectedRows)
            restoredHistory = try journal(restored).exportSnapshot()
            XCTAssertEqual(restoredHistory.receipts.count, sourceHistory.receipts.count + targetHistory.receipts.count)
            XCTAssertEqual(try restoredHistory.receipts.filter {
                try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).workspaceID == source.session.workspaceID
            }, sourceHistory.receipts)
            XCTAssertEqual(try restoredHistory.receipts.filter {
                try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).workspaceID == target.session.workspaceID
            }, targetHistory.receipts)
            XCTAssertEqual(restoredHistory.quarantines, sourceHistory.quarantines + targetHistory.quarantines)
            try assertImages(expected, history: restoredHistory, externallyProjected: true)
        }
        lifetime.beginAcquisition(root: target.root)
        let cold = try target.factory.openOrBootstrapCurrent()
        lifetime.observe(cold, root: target.root)
        XCTAssertEqual(cold.generationID, restoredID)
        XCTAssertEqual(try persistedRecords(cold), expectedRows)
        XCTAssertEqual(try journal(cold).exportSnapshot(), restoredHistory)
        let coldHarness = V906Integration.Harness(root: target.root, support: target.support,
            caches: target.caches, temporary: target.temporary, factory: target.factory, session: cold)
        let coldRecords = try exportRecords(coldHarness)
        XCTAssertEqual(coldRecords.workPackets, expectedRows)
        XCTAssertEqual(try XCTUnwrap(coldRecords.mutationHistory),
            try BackupCanonicalEncoderV1.archiveOrderedMutationHistory(restoredHistory))
        XCTAssertEqual(try journal(source.session).exportSnapshot(), sourceHistory)
    }

    private struct Values {
        let workspaceID: WorkspaceID
        let actors: [ActorSnapshotV1]
        let manifest: WorkPacketManifestV1
        let claim: WorkItemClaimV1
        let successorClaim: WorkItemClaimV1
        let lease: WorkLeaseV1
        let successorLease: WorkLeaseV1
        let release: WorkReleaseV1
        let handoff: WorkHandoffV1

        init(workspaceID: WorkspaceID) throws {
            self.workspaceID = workspaceID
            let date = Self.date
            func actor(_ slot: Int, responsibility: ResponsibilityKindV1) throws -> ActorSnapshotV1 {
                let name = "Work packet actor \(slot)"
                return try .init(snapshotID: Self.id(slot), workspaceID: workspaceID,
                    actor: .init(actorReferenceID: Self.id(slot + 100), workspaceID: workspaceID, displayName: name),
                    responsibility: responsibility, displayNameAtTime: name, capturedAt: date)
            }
            let creator = try actor(1, responsibility: .recordedBy)
            let holder = try actor(2, responsibility: .assignedTo)
            let recipient = try actor(3, responsibility: .assignedTo)
            actors = [creator, holder, recipient]
            let item = try WorkPacketItemV1(itemID: "restore-work-packet", kind: .inspection,
                expectedRevision: 1, itemSHA256: String(repeating: "e", count: 64))
            manifest = try .init(manifestID: Self.id(10), packetID: Self.id(90), packetVersion: 1,
                workspaceID: workspaceID, items: [item], packageReleases: [],
                creationBasis: .explicitLocalSelection, creator: creator, createdAt: date,
                mutationID: .init(rawValue: Self.id(210)))
            let reference = try WorkPacketManifestReferenceV1(manifest)
            let itemReference = try WorkPacketItemReferenceV1(manifest: manifest, item: item)
            claim = try .init(claimID: Self.id(20), workspaceID: workspaceID, manifest: reference,
                item: itemReference, holder: holder, claimSequence: 1, claimedAt: date.addingTimeInterval(1),
                mutationID: .init(rawValue: Self.id(220)))
            successorClaim = try .init(claimID: Self.id(21), workspaceID: workspaceID, manifest: reference,
                item: itemReference, holder: holder, claimSequence: 2, claimedAt: date.addingTimeInterval(2),
                supersedesClaimID: claim.claimID, revision: 2, mutationID: .init(rawValue: Self.id(221)))
            lease = try .init(leaseID: Self.id(30), workspaceID: workspaceID, claimID: successorClaim.claimID,
                item: itemReference, holder: holder, leaseSequence: 1, startsAt: date.addingTimeInterval(3),
                expiresAt: date.addingTimeInterval(60), mutationID: .init(rawValue: Self.id(230)))
            successorLease = try .init(leaseID: Self.id(31), workspaceID: workspaceID, claimID: successorClaim.claimID,
                item: itemReference, holder: holder, leaseSequence: 2, startsAt: date.addingTimeInterval(4),
                expiresAt: date.addingTimeInterval(70), supersedesLeaseID: lease.leaseID,
                revision: 2, mutationID: .init(rawValue: Self.id(231)))
            release = try .init(releaseID: Self.id(40), workspaceID: workspaceID,
                claimID: successorClaim.claimID, leaseID: successorLease.leaseID, item: itemReference,
                holder: holder, reason: .handoff, releasedAt: date.addingTimeInterval(5),
                mutationID: .init(rawValue: Self.id(240)))
            handoff = try .init(handoffID: Self.id(50), workspaceID: workspaceID, releaseID: release.releaseID,
                item: itemReference, fromHolder: holder, toHolder: recipient, resultLinks: [],
                reason: "Explicit local handoff", handedOffAt: date.addingTimeInterval(6),
                mutationID: .init(rawValue: Self.id(250)))
        }

        var payloads: [WorkPacketMutationPayloadV1] {
            [.appendManifest(manifest), .appendClaim(claim), .supersedeClaim(successorClaim),
             .appendLease(lease), .supersedeLease(successorLease), .recordRelease(release), .recordHandoff(handoff)]
        }
        func records() throws -> [V15BackupWorkPacketRecordV1] {
            try payloads.map { payload in
                let kind: V15BackupWorkPacketRecordV1.Kind
                let bytes: Data
                switch payload {
                case let .appendManifest(value): kind = .manifest; bytes = try WorkPacketCanonicalCodecV1.encode(value)
                case let .appendClaim(value), let .supersedeClaim(value): kind = .claim; bytes = try WorkPacketCanonicalCodecV1.encode(value)
                case let .appendLease(value), let .supersedeLease(value): kind = .lease; bytes = try WorkPacketCanonicalCodecV1.encode(value)
                case let .recordRelease(value): kind = .release; bytes = try WorkPacketCanonicalCodecV1.encode(value)
                case let .recordHandoff(value): kind = .handoff; bytes = try WorkPacketCanonicalCodecV1.encode(value)
                }
                return .init(kind: kind, id: try payload.affectedIdentity.id,
                    workspaceID: workspaceID.rawValue, revision: payload.revision, canonicalData: bytes)
            }.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
        }
        func actorRecords() throws -> [V9BackupPartyAccountabilityRecordV1] {
            try actors.map { .init(kind: .actorSnapshot, id: $0.snapshotID,
                workspaceID: workspaceID.rawValue, revision: nil,
                canonicalData: try PartyAccountabilitySnapshotCodecV1.encode($0)) }
        }
        static let date = Date(timeIntervalSince1970: 1_780_000_000)
        static func id(_ n: Int) -> UUID { V906Integration.id(900_000 + n) }
    }

    private func makeSource(_ label: String) throws -> (harness: V906Integration.Harness, values: Values) {
        let h = try V906Integration.makeHarness("work-packet-\(label)", withAsset: false)
        registerCleanup(h)
        // Reviewed retained Packet baseline, not a claimed end-user finalization.
        // Every C15 value and receipt below is independently produced by the writer.
        h.session.modelContext.insert(Packet(id: Values.id(90), stableRootID: Values.id(91),
            currentRecordID: nil, evaluationCounted: true, contentDeletedAt: Values.date, createdAt: Values.date))
        try DeletionLedgerStore(context: h.session.modelContext).stageUnion([
            try .init(identity: .init(kind: .packet, id: Values.id(90)), deletedAt: Values.date)
        ])
        try V906Integration.adoptSeededDeletionBaseline(h.session)
        let baseline = try journal(h.session).exportSnapshot()
        XCTAssertTrue(baseline.receipts.isEmpty)
        XCTAssertEqual(baseline.workspaceRevision, 0)
        XCTAssertTrue(WorkPacketEraseBoundaryV1.ordinaryDeletionPreservesReplayHistory)
        XCTAssertTrue(WorkPacketEraseBoundaryV1.immutableManifestClaimLeaseReleaseAndHandoffHistoryClearedOnlyByWorkspaceErase)
        XCTAssertEqual(try DeletionLedgerStore(context: h.session.modelContext).snapshot().entries, [
            try .init(identity: .init(kind: .packet, id: Values.id(90)), deletedAt: Values.date)
        ])
        let owners = try h.session.modelContext.fetch(FetchDescriptor<Packet>())
        XCTAssertEqual(owners.count, 1)
        let owner = try XCTUnwrap(owners.first)
        XCTAssertEqual(owner.id, Values.id(90)); XCTAssertEqual(owner.stableRootID, Values.id(91))
        XCTAssertNil(owner.currentRecordID); XCTAssertTrue(owner.evaluationCounted)
        XCTAssertEqual(owner.contentDeletedAt, Values.date); XCTAssertEqual(owner.createdAt, Values.date)
        let values = try Values(workspaceID: h.session.workspaceID)
        let coordinator = try StoreSessionCoordinator(validatingSession: h.session)
        defer { XCTAssertNoThrow(try coordinator.invalidateAndReleaseWriter()) }
        let writer = coordinator.workspaceWriter
        for (index, actor) in values.actors.enumerated() {
            _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(actor)),
                mutationID: .init(rawValue: Values.id(300 + index)))
        }
        for payload in values.payloads {
            let before = try writer.currentRevision()
            let mutation = try WorkPacketMutationV1(workspaceID: values.workspaceID,
                expectedRevision: payload.revision - 1, mutationID: payload.mutationID, postImage: payload)
            let outcome = try writer.execute(.applyWorkPacket(mutation), mutationID: mutation.mutationID)
            XCTAssertEqual(outcome.before, before)
            XCTAssertEqual(outcome.after.revision, before.revision + 1)
            let receipt = try XCTUnwrap(writer.durableReceipt(mutationID: mutation.mutationID))
            XCTAssertEqual(receipt.postImages, [try payload.mutationPostImage])
            let concurrency = try mutation.concurrencyIdentity
            XCTAssertEqual(receipt.expectedRevision.entityRevisions.first {
                $0.identity == concurrency
            }?.revision, mutation.expectedRevision)
        }
        let history = try journal(h.session).exportSnapshot()
        XCTAssertEqual(history.receipts.count, 10)
        XCTAssertEqual(try history.receipts.map { try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData) }
            .filter { $0.commandKind == .applyWorkPacket }.count, 7)
        XCTAssertEqual(try persistedRecords(h.session), try values.records())
        return (h, values)
    }

    private func seedNonemptyDestination(_ h: V906Integration.Harness) throws -> MutationHistorySnapshotV1 {
        let owner = try StoreSessionCoordinator(validatingSession: h.session)
        defer { XCTAssertNoThrow(try owner.invalidateAndReleaseWriter()) }
        let mutationID = try MutationIDV1(rawValue: Values.id(410))
        let pack = SignPack.illuminatedSignV1
        _ = try owner.workspaceWriter.execute(.createFirstSign(.init(
            siteID: Values.id(400), newSite: .init(id: Values.id(400), label: "Target before replacement",
                address: nil, timeZoneID: "America/Chicago"),
            assetID: Values.id(401), assetLabel: "Actual destination asset", packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: Values.date, initialPlacementMutationID: mutationID,
            initialPlacementEventID: Values.id(402),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: Values.id(403)))),
            mutationID: mutationID)
        let history = try journal(h.session).exportSnapshot()
        XCTAssertEqual(history.receipts.count, 1)
        XCTAssertEqual(try MutationEnvelopeV1.decodeCanonical(from: XCTUnwrap(history.receipts.first).envelopeData).commandKind,
            .createFirstSign)
        XCTAssertEqual(try h.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
        return history
    }
    private func registerCleanup(_ h: V906Integration.Harness) {
        let roots = lifetime
        roots.observe(h.session, root: h.root)
        addTeardownBlock { [roots, root = h.root] in
            try await MainActor.run { try roots.removeIfDrained(root) }
        }
    }
    private func journal(_ session: StoreGenerationSession) throws -> MutationJournalStoreV1 {
        try .init(modelContext: session.modelContext, identity: session.workspaceIdentity,
            generationID: session.generationID, allowStateBootstrap: false)
    }
    private func exportRecords(_ h: V906Integration.Harness) throws -> V4BackupRecordsV1 {
        let archive = try V906Integration.exportStreaming(h)
        let directory = h.root.appendingPathComponent("decoded-\(UUID().uuidString).fieldrecordbackup")
        _ = try StreamingArchiveService().extract(archive, to: directory)
        return try BackupPackageValidatorV1().validate(stagedPackageURL: directory).records
    }
    private func persistedRecords(_ session: StoreGenerationSession) throws -> [V15BackupWorkPacketRecordV1] {
        let c = session.modelContext
        var rows: [V15BackupWorkPacketRecordV1] = []
        @MainActor
        func append<T: Encodable>(_ value: T, kind: V15BackupWorkPacketRecordV1.Kind,
                                   id: UUID, revision: UInt64) throws {
            rows.append(.init(kind: kind, id: id, workspaceID: session.workspaceID.rawValue,
                revision: revision, canonicalData: try WorkPacketCanonicalCodecV1.encode(value)))
        }
        for row in try c.fetch(FetchDescriptor<WorkPacketManifestRow>()) {
            let v = try row.value(); try append(v, kind: .manifest, id: v.manifestID, revision: v.revision)
        }
        for row in try c.fetch(FetchDescriptor<WorkItemClaimRow>()) {
            let v = try row.value(); try append(v, kind: .claim, id: v.claimID, revision: v.revision)
        }
        for row in try c.fetch(FetchDescriptor<WorkLeaseRow>()) {
            let v = try row.value(); try append(v, kind: .lease, id: v.leaseID, revision: v.revision)
        }
        for row in try c.fetch(FetchDescriptor<WorkReleaseRow>()) {
            let v = try row.value(); try append(v, kind: .release, id: v.releaseID, revision: v.revision)
        }
        for row in try c.fetch(FetchDescriptor<WorkHandoffRow>()) {
            let v = try row.value(); try append(v, kind: .handoff, id: v.handoffID, revision: v.revision)
        }
        return rows.sorted { ($0.kind.rawValue, $0.id.uuidString) < ($1.kind.rawValue, $1.id.uuidString) }
    }
    private func assertImages(_ values: Values, history: MutationHistorySnapshotV1,
                              externallyProjected: Bool) throws {
        for payload in values.payloads {
            let image = try payload.mutationPostImage
            let identity = try image.identity
            let revision = try XCTUnwrap(history.entityRevisions.first { $0.identity == identity })
            XCTAssertEqual(revision.revision, payload.revision)
            XCTAssertEqual(revision.externalProjectionSHA256, externallyProjected ? image.semanticSHA256 : nil)
            let basis: MutationJournalStoreV1.WorkPacketPostImageBasis
            switch payload {
            case let .appendManifest(v): basis = .manifest(v)
            case let .appendClaim(v), let .supersedeClaim(v): basis = .claim(v)
            case let .appendLease(v), let .supersedeLease(v): basis = .lease(v)
            case let .recordRelease(v): basis = .release(v)
            case let .recordHandoff(v): basis = .handoff(v)
            }
            XCTAssertEqual(try basis.postImage(identity: identity, revision: image.revision,
                workspaceID: values.workspaceID), image)
            XCTAssertThrowsError(try basis.postImage(identity: identity, revision: image.revision + 1,
                workspaceID: values.workspaceID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
        }
    }
    private func replacing(_ records: V4BackupRecordsV1, workPackets: [V15BackupWorkPacketRecordV1],
                           actors: [V9BackupPartyAccountabilityRecordV1]? = nil) throws -> V4BackupRecordsV1 {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(records)) as? [String: Any])
        object["workPackets"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workPackets))
        if let actors { object["partyAccountability"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(actors)) }
        return try JSONDecoder().decode(V4BackupRecordsV1.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

/// Tracks the store owners created by this fixture, including replaced and cold
/// sessions. This is a weak object-lifetime proof, not a claim about all SQLite FDs.
@MainActor
private final class WorkPacketRestoreFixtureLifetime {
    @MainActor
    private final class Probe {
        weak var session: StoreGenerationSession?
        weak var context: ModelContext?
        weak var container: ModelContainer?
        let generationID: UUID
        init(_ session: StoreGenerationSession) {
            self.session = session
            context = session.modelContext
            container = session.modelContext.container
            generationID = session.generationID
        }
        var drained: Bool { session == nil && context == nil && container == nil }
    }
    private var probes: [String: [Probe]] = [:]
    private var unprovenRoots: Set<String> = []
    enum Failure: Error { case retainedStore }
    func beginAcquisition(root: URL) {
        unprovenRoots.insert(root.standardizedFileURL.path)
    }
    func observe(_ session: StoreGenerationSession, root: URL) {
        let key = root.standardizedFileURL.path
        guard session.generationRootURL.standardizedFileURL.path.hasPrefix(key + "/") else {
            unprovenRoots.insert(key)
            XCTFail("WorkPacket fixture root does not own observed generation")
            return
        }
        probes[key, default: []].append(Probe(session))
        unprovenRoots.remove(key)
    }
    func removeIfDrained(_ root: URL) throws {
        let key = root.standardizedFileURL.path
        guard !unprovenRoots.contains(key), let observed = probes[key], !observed.isEmpty else {
            throw Failure.retainedStore
        }
        guard observed.allSatisfy({ $0.drained }) else {
            for value in observed where !value.drained {
                print("WorkPacket fixture retained generation=\(value.generationID) session=\(value.session != nil) context=\(value.context != nil) container=\(value.container != nil)")
            }
            throw Failure.retainedStore
        }
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        probes.removeValue(forKey: key)
    }
}

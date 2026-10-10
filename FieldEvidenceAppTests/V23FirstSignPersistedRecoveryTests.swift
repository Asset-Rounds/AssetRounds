import Foundation
import CryptoKit
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23FirstSignPersistedRecoveryTests: XCTestCase {
    func testDiskOrdinarySchema1AndAbsentBasisForwardReplayPreserveCanonicalBytes() throws {
        let disk = try FirstSignPersistedFixture()
        defer { disk.removeFiles() }
        let originals = try disk.withStore { session, writer in
            let seed = try Self.firstSignRequest(writer: writer)
            _ = try writer.execute(seed)
            guard case let .createFirstSign(first) = seed.command else {
                throw FirstSignPersistedFixtureFailure.unexpectedCommand
            }
            let site = try WorkspaceEntityIdentityV1(kind: .site, id: first.siteID)
            let targetID = try MutationIDV1(rawValue: UUID())
            let expected = try Self.expected(writer: writer, identities: [site])
            let command = WorkspaceCommandV1.updateSiteTimeZone(.init(
                siteID: first.siteID, timeZoneID: "America/New_York",
                confirmedAt: FirstSignPersistedClock.instant))
            let request = WorkspaceMutationRequestV1(mutationID: targetID,
                expectedRevision: expected, command: command)
            // This is an ordinary currently supported reversible operation,
            // not a manufactured historically accepted first-sign basis.
            let plan = try SemanticReversalPlanV1(mutationID: targetID,
                commandKind: command.kind, expectedRevision: expected,
                prospectiveTargets: [site],
                requiredSemanticValues: [.init(key: "prior_timezone", value: "UTC")],
                contentReferences: [], dependencyGraph: [], conflicts: [],
                compensatingCommands: [.updateSiteTimeZone(.init(siteID: first.siteID,
                    timeZoneID: "UTC", confirmedAt: FirstSignPersistedClock.instant))])
            _ = try writer.execute(request, reversalPlan: plan)
            let ordinary = try Self.storedMutation(targetID, in: session.modelContext)
            let basis = try XCTUnwrap(ordinary.basis)
            let decoded = try ReversalBasisV1.decodeCanonical(from: basis)
            XCTAssertEqual(decoded.schemaVersion, 1)
            XCTAssertNil(decoded.firstSignCompensation)
            XCTAssertEqual(try decoded.canonicalData(), basis)
            XCTAssertEqual(Set(try Self.object(basis).keys), ["schemaVersion",
                "targetMutationID", "targetReceiptIdentity", "policyVersion",
                "planDigest", "compensatingCommandKinds"])
            let nilID = try MutationIDV1(rawValue: UUID())
            _ = try writer.execute(.updateSiteTimeZone(.init(siteID: first.siteID,
                timeZoneID: "America/Chicago", confirmedAt: FirstSignPersistedClock.instant)),
                mutationID: nilID)
            let withoutBasis = try Self.storedMutation(nilID, in: session.modelContext)
            XCTAssertNil(withoutBasis.basis)
            XCTAssertNil(try MutationEnvelopeV1.decodeCanonical(from: withoutBasis.envelope).reversalPlanDigest)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
            XCTAssertFalse(session.modelContext.hasChanges)
            return (ordinary, withoutBasis, try Self.snapshot(session.modelContext), plan)
        }
        try disk.withStore { session, writer in
            for original in [originals.0, originals.1] {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelope)
                let request = try Self.replayRequest(envelope: envelope, writer: writer)
                if original == originals.0 {
                    // The schema1 digest includes the ORIGINAL writer token.
                    // Durable replay precedes new-commit plan/revision checks;
                    // do not reconstruct or change that accepted commitment.
                    XCTAssertEqual(originals.3.planDigest, envelope.reversalPlanDigest)
                    _ = try writer.execute(request, reversalPlan: originals.3)
                } else {
                    _ = try writer.execute(request)
                }
                XCTAssertEqual(try Self.storedMutation(envelope.mutationID,
                    in: session.modelContext), original)
            }
            XCTAssertEqual(try Self.snapshot(session.modelContext), originals.2)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: originals.0.envelope)
            guard case let .updateSiteTimeZone(value) = envelope.command else {
                throw FirstSignPersistedFixtureFailure.unexpectedCommand
            }
            let exact = try Self.replayRequest(envelope: envelope, writer: writer)
            let changed = WorkspaceMutationRequestV1(mutationID: exact.mutationID,
                expectedRevision: exact.expectedRevision,
                command: .updateSiteTimeZone(.init(siteID: value.siteID,
                    timeZoneID: "Europe/London", confirmedAt: value.confirmedAt)))
            XCTAssertThrowsError(try writer.execute(changed, reversalPlan: originals.3)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertEqual(try Self.storedMutation(envelope.mutationID,
                in: session.modelContext), originals.0)
            XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<Site>()).first?.timeZoneID,
                "America/Chicago")
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
            XCTAssertFalse(session.modelContext.hasChanges)
        }
        try disk.withStore { session, writer in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: originals.0.envelope)
            XCTAssertThrowsError(try writer.execute(Self.replayRequest(envelope: envelope, writer: writer),
                reversalPlan: originals.3)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertEqual(try Self.storedMutation(envelope.mutationID,
                in: session.modelContext), originals.0)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
            XCTAssertFalse(session.modelContext.hasChanges)
        }
    }

    func testDiskSchema2NewContainerCompensationReplayRetainsOriginalHistory() throws {
        let disk = try FirstSignPersistedFixture()
        defer { disk.removeFiles() }
        let original = try disk.withStore { session, writer in
            let request = try Self.firstSignRequest(writer: writer)
            _ = try writer.execute(request)
            let saved = try Self.storedMutation(request.mutationID, in: session.modelContext)
            let basis = try ReversalBasisV1.decodeCanonical(from: XCTUnwrap(saved.basis))
            XCTAssertEqual(basis.schemaVersion, 2)
            let payload = try XCTUnwrap(basis.firstSignCompensation)
            XCTAssertEqual(try payload.requireOriginalCommand(
                MutationEnvelopeV1.decodeCanonical(from: saved.envelope).command).assetID,
                payload.assetID)
            return (saved, payload, try Self.placementBytes(session.modelContext))
        }
        let reversalID = try MutationIDV1(rawValue: UUID())
        let accepted = try disk.withStore { session, writer in
            let preview = try writer.firstSignReversalEligibility(targetMutationID: original.1.targetMutationID)
            XCTAssertEqual(preview.eligibility, .eligible)
            let portable = try XCTUnwrap(preview.portablePlan)
            XCTAssertEqual(portable.schemaVersion, 2)
            XCTAssertEqual(portable.firstSignCompensation, original.1)
            let data = try WorkspaceMutationCanonicalV1.data(portable)
            XCTAssertEqual(try JSONDecoder().decode(PortableReversalPlanV1.self, from: data), portable)
            let request = try Self.reversalRequest(writer: writer, payload: original.1,
                mutationID: reversalID)
            _ = try writer.executeSemanticReversal(request, targetMutationID: original.1.targetMutationID,
                plan: original.1.semanticPlan(expectedRevision: request.expectedRevision),
                compensatingMutationIDs: [reversalID])
            let saved = try Self.storedMutation(reversalID, in: session.modelContext)
            try Self.requireCompleted(session.modelContext, original: original.0,
                targetID: original.1.targetMutationID, placement: original.2)
            return saved
        }
        try disk.withStore { session, writer in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: accepted.envelope)
            let replay = try Self.replayRequest(envelope: envelope, writer: writer)
            for _ in 0..<2 {
                _ = try writer.executeSemanticReversal(replay,
                    targetMutationID: original.1.targetMutationID,
                    plan: original.1.semanticPlan(expectedRevision: replay.expectedRevision),
                    compensatingMutationIDs: [reversalID])
            }
            XCTAssertEqual(try Self.storedMutation(reversalID, in: session.modelContext), accepted)
            try Self.requireCompleted(session.modelContext, original: original.0,
                targetID: original.1.targetMutationID, placement: original.2)
        }
    }

    func testDiskEachAtomicBoundaryReopensWholeCompensationAndReplaysOnce() throws {
        XCTAssertEqual(MutationJournalFaultBoundaryV1.allCases.count, 3)
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let disk = try FirstSignPersistedFixture()
            defer { disk.removeFiles() }
            let original = try disk.withStore { session, writer in
                let request = try Self.firstSignRequest(writer: writer)
                _ = try writer.execute(request)
                let saved = try Self.storedMutation(request.mutationID, in: session.modelContext)
                let basis = try ReversalBasisV1.decodeCanonical(from: XCTUnwrap(saved.basis))
                return (saved, try XCTUnwrap(basis.firstSignCompensation),
                    try Self.placementBytes(session.modelContext))
            }
            let reversalID = try MutationIDV1(rawValue: UUID())
            let attempted = try disk.withStore(failOnceAt: boundary) { _, writer in
                let request = try Self.reversalRequest(writer: writer,
                    payload: original.1, mutationID: reversalID)
                XCTAssertThrowsError(try writer.executeSemanticReversal(request,
                    targetMutationID: original.1.targetMutationID,
                    plan: original.1.semanticPlan(expectedRevision: request.expectedRevision),
                    compensatingMutationIDs: [reversalID])) {
                    XCTAssertEqual($0 as? MutationJournalFailureV1, .injected(boundary))
                }
                return request
            }
            let final = try disk.withStore { session, writer in
                let committed = boundary == .afterSaveBeforeReturn
                XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Asset>()), committed ? 0 : 1)
                XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<DeletionLedgerRow>()), committed ? 1 : 0)
                XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), committed ? 2 : 1)
                XCTAssertEqual(try Self.storedMutation(original.1.targetMutationID,
                    in: session.modelContext), original.0)
                XCTAssertEqual(try Self.placementBytes(session.modelContext), original.2)
                let replay = WorkspaceMutationRequestV1(mutationID: attempted.mutationID,
                    expectedRevision: try Self.rebound(attempted.expectedRevision, writer: writer),
                    command: attempted.command)
                for _ in 0..<2 {
                    _ = try writer.executeSemanticReversal(replay,
                        targetMutationID: original.1.targetMutationID,
                        plan: original.1.semanticPlan(expectedRevision: replay.expectedRevision),
                        compensatingMutationIDs: [reversalID])
                }
                try Self.requireCompleted(session.modelContext, original: original.0,
                    targetID: original.1.targetMutationID, placement: original.2)
                return try Self.storedMutation(reversalID, in: session.modelContext)
            }
            try disk.withStore { session, _ in
                XCTAssertEqual(try Self.storedMutation(reversalID, in: session.modelContext), final)
                try Self.requireCompleted(session.modelContext, original: original.0,
                    targetID: original.1.targetMutationID, placement: original.2)
            }
        }
    }

    func testDiskMissingOrCorruptPromisedPayloadRefusesFreshWriterWithoutEffects() throws {
        for damage in ["missing", "corrupt"] {
            let disk = try FirstSignPersistedFixture()
            defer { disk.removeFiles() }
            let retained = try disk.withStore { session, writer in
                let request = try Self.firstSignRequest(writer: writer)
                _ = try writer.execute(request)
                let row = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).first)
                var basis = try Self.object(XCTUnwrap(row.reversalBasisData))
                if damage == "missing" {
                    basis.removeValue(forKey: "firstSignCompensation")
                } else {
                    var payload = try XCTUnwrap(basis["firstSignCompensation"] as? [String: Any])
                    payload["originalCommandSHA256"] = String(repeating: "0", count: 64)
                    basis["firstSignCompensation"] = payload
                }
                let bytes = try JSONSerialization.data(withJSONObject: basis,
                    options: [.sortedKeys, .withoutEscapingSlashes])
                row.reversalBasisData = bytes
                row.reversalBasisSHA256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                // Hostile persisted fixture only. No receipt/authority is
                // invented and neither expected decoder nor writer is relaxed.
                try session.modelContext.save()
                return try Self.snapshot(session.modelContext)
            }
            XCTAssertThrowsError(try disk.withStore { _, _ in
                XCTFail("A new production writer must refuse the damaged promised payload")
            }) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
            }
            try disk.withReadOnlyStore { session in
                XCTAssertEqual(try Self.snapshot(session.modelContext), retained)
                XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
                XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
                XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
                XCTAssertFalse(session.modelContext.hasChanges)
            }
        }
    }

    private static func firstSignRequest(writer: WorkspaceWriterV1) throws -> WorkspaceMutationRequestV1 {
        let siteID = UUID(), assetID = UUID(), placementID = UUID()
        let mutationID = try MutationIDV1(rawValue: UUID())
        let identities = try [WorkspaceEntityIdentityV1(kind: .site, id: siteID),
            WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
            WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: placementID)]
        return .init(mutationID: mutationID,
            expectedRevision: try expected(writer: writer, identities: identities),
            command: .createFirstSign(.init(siteID: siteID,
                newSite: .init(id: siteID, label: "Persisted first sign site", address: nil, timeZoneID: "UTC"),
                assetID: assetID, assetLabel: "Persisted first sign asset", packID: "test.pack",
                packSchemaVersion: 1, packContentVersion: 1, createdAt: FirstSignPersistedClock.instant,
                initialPlacementMutationID: mutationID, initialPlacementEventID: placementID,
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID()))))
    }

    private static func expected(writer: WorkspaceWriterV1,
        identities: [WorkspaceEntityIdentityV1]) throws -> WorkspaceExpectedRevisionV1 {
        let current = try writer.currentRevision()
        let values = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        return try .init(workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: identities.map { .init(identity: $0, revision: values[$0, default: 0]) })
    }

    private static func reversalRequest(writer: WorkspaceWriterV1,
        payload: FirstSignCompensationV1, mutationID: MutationIDV1) throws -> WorkspaceMutationRequestV1 {
        .init(mutationID: mutationID, expectedRevision: try expected(writer: writer,
            identities: [WorkspaceEntityIdentityV1(kind: .asset, id: payload.assetID)]),
            command: try payload.compensatingCommand())
    }

    private static func rebound(_ value: WorkspaceExpectedRevisionV1,
        writer: WorkspaceWriterV1) throws -> WorkspaceExpectedRevisionV1 {
        try .init(workspaceID: value.workspaceID, generationID: value.generationID,
            writerInstanceID: writer.currentRevision().writerInstanceID,
            workspaceRevision: value.workspaceRevision, entityRevisions: value.entityRevisions)
    }

    private static func replayRequest(envelope: MutationEnvelopeV1,
        writer: WorkspaceWriterV1) throws -> WorkspaceMutationRequestV1 {
        let current = try writer.currentRevision()
        return .init(mutationID: envelope.mutationID,
            expectedRevision: try WorkspaceExpectedRevisionV1(workspaceID: envelope.expectedRevision.workspaceID,
                generationID: envelope.expectedRevision.generationID,
                writerInstanceID: current.writerInstanceID,
                workspaceRevision: envelope.expectedRevision.workspaceRevision,
                entityRevisions: envelope.expectedRevision.entityRevisions), command: envelope.command)
    }

    private static func object(_ bytes: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private static func storedMutation(_ id: MutationIDV1,
        in context: ModelContext) throws -> FirstSignPersistedMutation {
        let rows = try context.fetch(FetchDescriptor<MutationReceiptRow>()).filter { $0.mutationID == id.rawValue }
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        return FirstSignPersistedMutation(row)
    }

    private static func placementBytes(_ context: ModelContext) throws -> [Data] {
        try context.fetch(FetchDescriptor<AssetPlacementEventRow>()).map(\.canonicalData)
    }

    private static func requireCompleted(_ context: ModelContext,
        original: FirstSignPersistedMutation, targetID: MutationIDV1, placement: [Data]) throws {
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AssetPlacementEventRow>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 1)
        XCTAssertEqual(try storedMutation(targetID, in: context), original)
        XCTAssertEqual(try placementBytes(context), placement)
        XCTAssertFalse(context.hasChanges)
    }

    private static func snapshot(_ context: ModelContext) throws -> FirstSignPersistedSnapshot {
        let rows = try context.fetch(FetchDescriptor<MutationReceiptRow>())
        let receipts = rows.sorted { $0.mutationID.uuidString < $1.mutationID.uuidString }.map {
            FirstSignPersistedMutation($0)
        }
        return .init(receipts: receipts,
            assets: try context.fetch(FetchDescriptor<Asset>()).map(\.id),
            sites: try context.fetch(FetchDescriptor<Site>()).map(\.id),
            placements: try placementBytes(context),
            ledgerCount: try context.fetchCount(FetchDescriptor<DeletionLedgerRow>()))
    }
}

private struct FirstSignPersistedMutation: Equatable {
    let mutationID: UUID
    let workspaceMutationKey: String
    let receiptIdentity: String
    let workspaceID: UUID
    let replicaID: UUID
    let localSequence: Int64
    let commandKind: String
    let envelope: Data
    let envelopeSHA256: String
    let receipt: Data
    let receiptSHA256: String
    let basis: Data?
    let basisSHA256: String?
    let semanticReversal: Data?

    @MainActor init(_ row: MutationReceiptRow) {
        mutationID = row.mutationID
        workspaceMutationKey = row.workspaceMutationKey
        receiptIdentity = row.receiptIdentity
        workspaceID = row.workspaceID
        replicaID = row.replicaID
        localSequence = row.localSequence
        commandKind = row.commandKind
        envelope = row.envelopeData
        envelopeSHA256 = row.envelopeSHA256
        receipt = row.receiptData
        receiptSHA256 = row.receiptSHA256
        basis = row.reversalBasisData
        basisSHA256 = row.reversalBasisSHA256
        semanticReversal = row.semanticReversalData
    }
}

private struct FirstSignPersistedSnapshot: Equatable {
    let receipts: [FirstSignPersistedMutation]
    let assets: [UUID]
    let sites: [UUID]
    let placements: [Data]
    let ledgerCount: Int
}

private enum FirstSignPersistedFixtureFailure: Error {
    case unexpectedCommand
}

private struct FirstSignPersistedClock: ApplicationClock {
    static let instant = Date(timeIntervalSince1970: 1_700_000_010)
    func now() -> Date { Self.instant }
}

@MainActor
private final class FirstSignPersistedFixture {
    let root: URL
    private weak var previousContainer: ModelContainer?

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-first-sign-persisted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func withStore<T>(failOnceAt boundary: MutationJournalFaultBoundaryV1? = nil,
        _ body: (StoreGenerationSession, WorkspaceWriterV1) throws -> T) throws -> T {
        // Every call invokes the real opening provider and a newly constructed
        // on-disk ModelContainer. No previous session/writer is returned or
        // cached, and only value snapshots escape these test call sites.
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let session = try factory.openOrBootstrapCurrent()
        try requireDiskSession(session)
        let coordinator: StoreSessionCoordinator
        if let boundary {
            coordinator = try StoreSessionCoordinator(validatingSessionForTesting: session,
                clock: FirstSignPersistedClock(),
                mutationJournalFailureInjection: .init(failOnceAt: boundary))
        } else {
            coordinator = try StoreSessionCoordinator(validatingSession: session,
                clock: FirstSignPersistedClock())
        }
        let result: Result<T, Error>
        do { result = .success(try body(session, coordinator.workspaceWriter)) }
        catch { result = .failure(error) }
        do { try coordinator.invalidateAndReleaseWriter() }
        catch {
            if case .success = result { throw error }
        }
        return try result.get()
    }

    func withReadOnlyStore(_ body: (StoreGenerationSession) throws -> Void) throws {
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let session = try factory.openOrBootstrapCurrent()
        try requireDiskSession(session)
        try body(session)
    }

    private func requireDiskSession(_ session: StoreGenerationSession) throws {
        XCTAssertEqual(session.storeSchemaRelease, .v53)
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            session.generationRootURL.appendingPathComponent("model.sqlite").path))
        if let previousContainer {
            XCTAssertFalse(session.modelContext.container === previousContainer)
        }
        previousContainer = session.modelContext.container
        XCTAssertFalse(session.modelContext.hasChanges)
    }

    func removeFiles() {
        // Called after every withStore/withReadOnlyStore lexical scope has
        // released its production writer and session. This is never a claim
        // of process-cold restart, power-loss simulation or device protection.
        try? FileManager.default.removeItem(at: root)
    }
}

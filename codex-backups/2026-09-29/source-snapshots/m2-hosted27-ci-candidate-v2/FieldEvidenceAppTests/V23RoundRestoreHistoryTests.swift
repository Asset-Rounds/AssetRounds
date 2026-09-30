import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23RoundRestoreHistoryTests: XCTestCase {
    private typealias Projector = PartsStockReplacementHistoryProjectionV1

    func testRoundAppendUsesDestinationPrefixAndPreservesEveryOriginal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for current in [Fixture.emptyHistory, fixture.current] {
            let input = try fixture.input(current: current)
            let result = try Projector.project(input, roundProjection: fixture.projection)
            XCTAssertGreaterThan(fixture.source.history.workspaceRevision, current.workspaceRevision)
            XCTAssertEqual(result.history.workspaceRevision,
                           current.workspaceRevision + UInt64(fixture.source.rounds.count))
            XCTAssertEqual(result.roundSessions, fixture.projection.commands.map { $0.mutation.session })
            try assertOriginals(current, retainedIn: result.history)
            try assertOriginals(fixture.source.history, retainedIn: result.history)
            let target = try ReplacementHistoryCommandEmissionV1.decoded(result.history).filter {
                $0.envelope.workspaceID == fixture.target && $0.envelope.command.kind == .applyRoundSession
            }
            XCTAssertEqual(target.count, fixture.source.rounds.count)
            for (offset, value) in target.enumerated() {
                let original = fixture.projection.commands[offset]
                XCTAssertEqual(value.envelope.command, .applyRoundSession(original.mutation))
                XCTAssertEqual(value.receipt.expectedRevision.workspaceRevision,
                               current.workspaceRevision + UInt64(offset))
                XCTAssertEqual(value.receipt.postImages, [original.postImage])
                XCTAssertEqual(value.receipt.committedAt, original.source.receipt.committedAt)
                _ = try RoundSessionMutationReceiptV1(mutation: original.mutation,
                                                      mutationReceipt: value.receipt)
            }
            for original in fixture.source.history.entityRevisions {
                let retained = try XCTUnwrap(result.history.entityRevisions.first { $0.identity == original.identity })
                XCTAssertGreaterThanOrEqual(retained.revision, original.revision)
            }
            try MutationJournalStoreV1.validateImportedSnapshot(result.history)
        }
    }

    func testRoundBindingsAndSourceHistoryMustMatchExactly() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let input = try fixture.input()
        var wrongBindings = input.mutationBindings
        wrongBindings[0] = .init(source: wrongBindings[0].source,
                                 target: try MutationIDV1(rawValue: UUID()))
        XCTAssertThrowsError(try Projector.project(try fixture.input(bindings: wrongBindings),
                                                   roundProjection: fixture.projection))
        XCTAssertThrowsError(try Projector.project(try fixture.input(bindings: []),
                                                   roundProjection: fixture.projection))
        XCTAssertThrowsError(try Projector.project(try fixture.input(incoming: Fixture.emptyHistory),
                                                   roundProjection: fixture.projection))
        let activeReplica = try XCTUnwrap(fixture.current.receipts.first).receiptData
        let identity = try MutationReceiptV1.decodeCanonical(from: activeReplica).identity
        let collisions = input.replicaBindings.map { Projector.ReplicaBinding(source: $0.source,
                                                                             target: identity.replicaID) }
        XCTAssertThrowsError(try Projector.project(try fixture.input(replicas: collisions),
                                                   roundProjection: fixture.projection))
    }

    func testRoundAppendPreservesIncumbentQuarantineAndForeignFrontier() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try XCTUnwrap(ReplacementHistoryCommandEmissionV1.decoded(fixture.current).first)
        let quarantine = MutationHistoryQuarantineRecordV1(workspaceID: fixture.target,
            mutationID: first.envelope.mutationID.rawValue, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: try first.envelope.canonicalSHA256(),
            conflictingIdentitySHA256: String(repeating: "f", count: 64),
            detectedAt: RepetitiveCaptureSourcePackageFixture.date)
        let current = MutationHistorySnapshotV1(workspaceRevision: fixture.current.workspaceRevision,
            lastLocalSequence: fixture.current.lastLocalSequence, receipts: fixture.current.receipts,
            quarantines: [quarantine], entityRevisions: fixture.current.entityRevisions)
        let result = try Projector.project(try fixture.input(current: current),
                                          roundProjection: fixture.projection)
        XCTAssertEqual(result.history.quarantines, [quarantine])
        try assertOriginals(current, retainedIn: result.history)
        try assertOriginals(fixture.source.history, retainedIn: result.history)
    }

    func testEarlierTargetRoundCannotBeHiddenByLastReceiptFrontier() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try Projector.project(try fixture.input(), roundProjection: fixture.projection)
        // Obtain a distinct real sign command, then append its authenticated
        // receipt with a minimal frontier that does not repeat the earlier Round.
        let nextSession = try fixture.harness.populate()
        let nextHistory = try fixture.harness.history(in: nextSession)
        let next = try XCTUnwrap(ReplacementHistoryCommandEmissionV1.decoded(nextHistory).last)
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: fixture.target,
            generationID: fixture.projection.identity.targetPointer.generationID,
            writerInstanceID: UUID(), workspaceRevision: first.history.workspaceRevision,
            entityRevisions: next.envelope.expectedRevision.entityRevisions)
        let envelope = try MutationEnvelopeV1(request: .init(mutationID: next.envelope.mutationID,
            expectedRevision: expected, command: next.envelope.command),
            identity: nextSession.workspaceIdentity, sourceKind: .localRecovery)
        let resulting = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
            workspaceID: fixture.target, generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID,
            workspaceRevision: first.history.workspaceRevision + 1,
            entityRevisions: next.receipt.resultingRevision.entityRevisions))
        let receipt = try MutationReceiptV1(identity: next.receipt.identity, envelope: envelope,
            resultingRevision: resulting, postImages: next.receipt.postImages,
            committedAt: next.receipt.committedAt)
        let record = MutationHistoryReceiptRecordV1(envelopeData: try envelope.canonicalData(),
            receiptData: try receipt.canonicalData(), reversalBasisData: nil, semanticReversalData: nil)
        let tail = MutationHistorySnapshotV1(workspaceRevision: resulting.workspaceRevision,
            lastLocalSequence: 0, receipts: [record], quarantines: [],
            entityRevisions: nextHistory.entityRevisions)
        let current = Fixture.merging(first.history, tail)
        try MutationJournalStoreV1.validateImportedSnapshot(current)
        XCTAssertFalse(receipt.resultingRevision.entityRevisions.contains { $0.identity.kind == .roundSession })
        let second = try fixture.makeProjection(targetGenerationID: UUID())
        let freshReplica = [Projector.ReplicaBinding(
            source: fixture.projection.commands[0].source.receipt.identity.replicaID,
            target: ReplicaID(rawValue: UUID()))]
        XCTAssertThrowsError(try Projector.project(try fixture.input(current: current, projection: second,
                                                                    replicas: freshReplica),
                                                   roundProjection: second)) {
            XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .collision)
        }
    }

    func testRoundMetadataIsRetainedAndUnresolvedCausationIsDenied() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let correlation = UUID()
        let sourceID = fixture.projection.commands[0].source.envelope.mutationID
        let mapped = try fixture.historyWithMetadata(mutationID: sourceID,
            correlationID: correlation, causationID: nil)
        let projection = try fixture.makeProjection(history: mapped)
        let result = try Projector.project(try fixture.input(incoming: mapped, projection: projection),
                                          roundProjection: projection)
        let emitted = try XCTUnwrap(ReplacementHistoryCommandEmissionV1.decoded(result.history).first {
            $0.envelope.mutationID == projection.commands[0].mutation.mutationID
        })
        XCTAssertEqual(emitted.envelope.correlationID, correlation)
        XCTAssertEqual(emitted.envelope.contentDependencyIDs,
                       projection.commands[0].source.envelope.contentDependencyIDs)
        let unresolved = try fixture.historyWithMetadata(mutationID: sourceID,
            correlationID: correlation, causationID: MutationIDV1(rawValue: UUID()))
        XCTAssertThrowsError(try {
            let denied = try fixture.makeProjection(history: unresolved)
            return try Projector.project(fixture.input(incoming: unresolved, projection: denied),
                                         roundProjection: denied)
        }())
    }

    func testRoundReversalClosureCannotBorrowArchivedStockPlanException() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let history = try fixture.historyWithRoundReversal()
        // A structurally complete admitted closure, not malformed sidecars.
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        let projection = try fixture.makeProjection(history: history)
        XCTAssertEqual(projection.commands.count, 2)
        XCTAssertTrue(projection.commands.contains { $0.source.record.reversalBasisData != nil })
        XCTAssertTrue(projection.commands.contains { $0.source.record.semanticReversalData != nil })
        XCTAssertThrowsError(try Projector.project(fixture.input(incoming: history, projection: projection),
                                                   roundProjection: projection)) {
            XCTAssertEqual($0 as? PartsStockReplacementHistoryProjectionFailureV1, .invalidSource)
        }
    }

    private func assertOriginals(_ original: MutationHistorySnapshotV1,
                                 retainedIn result: MutationHistorySnapshotV1,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        for record in original.receipts {
            XCTAssertEqual(result.receipts.filter { $0 == record }.count, 1, file: file, line: line)
        }
    }

    @MainActor
    private final class Fixture {
        let source: RepetitiveCaptureSourcePackageFixture
        let harness: RestoreReviewHarness
        let current: MutationHistorySnapshotV1
        let target: WorkspaceID
        let identity: RestoreIdentityV1
        let projection: RoundSessionReplacementCommandProjectionV1.Projection
        let mappedReplica = ReplicaID(rawValue: UUID())
        static let emptyHistory = MutationHistorySnapshotV1(workspaceRevision: 0,
            lastLocalSequence: 0, receipts: [], quarantines: [], entityRevisions: [])

        init() throws {
            source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
            harness = try RestoreReviewHarness()
            let session = try harness.populate()
            current = try harness.history(in: session)
            target = session.workspaceIdentity.workspaceID
            identity = try RestoreIdentityDecisionV1.decide(.init(mode: .replaceExisting,
                source: .init(workspaceID: source.workspaceID.rawValue,
                              replicaID: RepetitiveCaptureSourcePackageFixture.id(2)),
                oldPointer: .init(generationID: session.generationID,
                    generationManifestSHA256: String(repeating: "a", count: 64),
                    workspaceID: target.rawValue, replicaID: session.workspaceIdentity.replicaID.rawValue),
                targetGenerationID: UUID(), targetGenerationManifestSHA256: String(repeating: "b", count: 64),
                allocatedWorkspaceID: UUID(), allocatedReplicaID: UUID()))
            projection = try RoundSessionReplacementCommandProjectionV1.project(
                source: ReferenceOwnerReplacementSourceV1.source(workspaceID: source.workspaceID,
                                                                history: source.history),
                identity: identity)
        }

        func remove() { source.removePackages(); harness.remove() }

        func makeProjection(history: MutationHistorySnapshotV1? = nil,
                            targetGenerationID: UUID? = nil) throws -> RoundSessionReplacementCommandProjectionV1.Projection {
            let decision = try RestoreIdentityDecisionV1.decide(.init(mode: .replaceExisting,
                source: identity.source, oldPointer: identity.oldPointer,
                targetGenerationID: targetGenerationID ?? identity.targetPointer.generationID,
                targetGenerationManifestSHA256: String(repeating: "b", count: 64),
                allocatedWorkspaceID: UUID(), allocatedReplicaID: UUID()))
            return try RoundSessionReplacementCommandProjectionV1.project(
                source: ReferenceOwnerReplacementSourceV1.source(workspaceID: source.workspaceID,
                    history: history ?? source.history), identity: decision)
        }

        func input(current: MutationHistorySnapshotV1? = nil,
                   incoming: MutationHistorySnapshotV1? = nil,
                   projection: RoundSessionReplacementCommandProjectionV1.Projection? = nil,
                   bindings: [Projector.MutationBinding]? = nil,
                   replicas: [Projector.ReplicaBinding]? = nil) throws -> Projector.Input {
            let current = current ?? self.current, incoming = incoming ?? source.history
            let projection = projection ?? self.projection
            let incomingReplica = ReplicaID(rawValue: RepetitiveCaptureSourcePackageFixture.id(2))
            return try .init(currentSnapshot: Self.emptyStock(target),
                incomingSnapshot: Self.emptyStock(source.workspaceID),
                currentHistory: current, incomingHistory: incoming,
                plannedHistory: Self.merging(current, incoming),
                currentWorkResources: [], incomingWorkResources: [], plannedWorkResources: [],
                targetWorkspaceID: target, targetGenerationID: projection.identity.targetPointer.generationID,
                writerInstanceID: UUID(), mutationBindings: bindings ?? projection.commands.map {
                    .init(source: $0.source.envelope.mutationID, target: $0.mutation.mutationID)
                }, subjectBindings: [], replicaBindings: replicas ?? [.init(source: incomingReplica, target: mappedReplica)])
        }

        func historyWithMetadata(mutationID: MutationIDV1, correlationID: UUID,
                                 causationID: MutationIDV1?) throws -> MutationHistorySnapshotV1 {
            let records = try source.history.receipts.map { record -> MutationHistoryReceiptRecordV1 in
                let old = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                guard old.mutationID == mutationID else { return record }
                let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
                let expected = try WorkspaceExpectedRevisionV1(workspaceID: old.workspaceID,
                    generationID: old.generationID, writerInstanceID: UUID(),
                    workspaceRevision: old.expectedRevision.workspaceRevision,
                    entityRevisions: old.expectedRevision.entityRevisions)
                let envelope = try MutationEnvelopeV1(request: .init(mutationID: old.mutationID,
                    expectedRevision: expected, command: old.command),
                    identity: WorkspaceReplicaIdentityV1(workspaceID: old.workspaceID, replicaID: old.replicaID),
                    sourceKind: old.sourceKind, contentDependencyIDs: old.contentDependencyIDs,
                    causationMutationID: causationID, correlationID: correlationID)
                let updated = try MutationReceiptV1(identity: receipt.identity, envelope: envelope,
                    resultingRevision: receipt.resultingRevision, postImages: receipt.postImages,
                    committedAt: receipt.committedAt)
                return .init(envelopeData: try envelope.canonicalData(), receiptData: try updated.canonicalData(),
                             reversalBasisData: nil, semanticReversalData: nil)
            }
            return .init(workspaceRevision: source.history.workspaceRevision,
                lastLocalSequence: source.history.lastLocalSequence, receipts: records,
                quarantines: source.history.quarantines, entityRevisions: source.history.entityRevisions)
        }

        func historyWithRoundReversal() throws -> MutationHistorySnapshotV1 {
            let target = projection.commands[0].source
            let reversal = projection.commands[1].source
            func expected(_ entry: ReferenceOwnerReplacementSourceV1.Entry) throws -> WorkspaceExpectedRevisionV1 {
                try .init(workspaceID: entry.envelope.workspaceID,
                    generationID: entry.envelope.generationID, writerInstanceID: UUID(),
                    workspaceRevision: entry.envelope.expectedRevision.workspaceRevision,
                    entityRevisions: entry.envelope.expectedRevision.entityRevisions)
            }
            let targetExpected = try expected(target)
            let plan = try SemanticReversalPlanV1(mutationID: target.envelope.mutationID,
                commandKind: .applyRoundSession, expectedRevision: targetExpected,
                prospectiveTargets: target.receipt.postImages.map { try $0.identity },
                requiredSemanticValues: [], contentReferences: [], dependencyGraph: [], conflicts: [],
                compensatingCommands: [reversal.envelope.command])
            let basis = try ReversalBasisV1(targetMutationID: target.envelope.mutationID,
                targetReceiptIdentity: target.receipt.identity, plan: plan)
            let replica = try WorkspaceReplicaIdentityV1(workspaceID: source.workspaceID,
                                                         replicaID: target.envelope.replicaID)
            let targetEnvelope = try MutationEnvelopeV1(request: .init(mutationID: target.envelope.mutationID,
                expectedRevision: targetExpected, command: target.envelope.command),
                identity: replica, reversalPlanDigest: basis.planDigest)
            let targetReceipt = try MutationReceiptV1(identity: target.receipt.identity,
                envelope: targetEnvelope, resultingRevision: target.receipt.resultingRevision,
                postImages: target.receipt.postImages, committedAt: target.receipt.committedAt)
            let request = WorkspaceMutationRequestV1(mutationID: reversal.envelope.mutationID,
                expectedRevision: try expected(reversal), command: reversal.envelope.command)
            let execution = try SemanticReversalExecutionV1(targetMutationID: target.envelope.mutationID,
                targetReceiptIdentity: target.receipt.identity,
                reversalBasisSHA256: basis.canonicalSHA256(), planDigest: basis.planDigest,
                compensatingMutationIDs: [reversal.envelope.mutationID])
            let replay = try SemanticReversalReplayIdentityV1(request: request, identity: replica,
                targetMutationID: target.envelope.mutationID, planDigest: basis.planDigest,
                compensatingMutationIDs: [reversal.envelope.mutationID]).canonicalSHA256()
            let reversalEnvelope = try MutationEnvelopeV1(request: request, identity: replica,
                sourceKind: .semanticReversal, causationMutationID: target.envelope.mutationID,
                semanticReversalReplayIdentitySHA256: replay, semanticReversalExecution: execution)
            let reversalReceipt = try MutationReceiptV1(identity: reversal.receipt.identity,
                envelope: reversalEnvelope, resultingRevision: reversal.receipt.resultingRevision,
                postImages: reversal.receipt.postImages, reversesMutationID: target.envelope.mutationID,
                committedAt: reversal.receipt.committedAt)
            let semantic = try SemanticReversalReceiptV1(reversalReceiptIdentity: reversalReceipt.identity,
                reversesMutationID: target.envelope.mutationID, targetReceiptIdentity: targetReceipt.identity,
                reversalBasisSHA256: basis.canonicalSHA256(), planDigest: basis.planDigest,
                compensatingMutationIDs: [reversal.envelope.mutationID],
                resultingRevision: reversalReceipt.resultingRevision)
            let targetRecord = MutationHistoryReceiptRecordV1(envelopeData: try targetEnvelope.canonicalData(),
                receiptData: try targetReceipt.canonicalData(), reversalBasisData: try basis.canonicalData(),
                semanticReversalData: nil)
            let reversalRecord = MutationHistoryReceiptRecordV1(envelopeData: try reversalEnvelope.canonicalData(),
                receiptData: try reversalReceipt.canonicalData(), reversalBasisData: nil,
                semanticReversalData: try semantic.canonicalData())
            return .init(workspaceRevision: source.history.workspaceRevision,
                lastLocalSequence: source.history.lastLocalSequence,
                receipts: source.history.receipts.map {
                    if $0 == target.record { return targetRecord }
                    if $0 == reversal.record { return reversalRecord }
                    return $0
                }, quarantines: source.history.quarantines, entityRevisions: source.history.entityRevisions)
        }

        static func emptyStock(_ workspace: WorkspaceID) throws -> PartsStockBackupSnapshotV1 {
            try .init(workspaceID: workspace, parts: [], locations: [], movements: [], uses: [],
                      reversals: [], returns: [], abandonments: [])
        }

        static func merging(_ left: MutationHistorySnapshotV1,
                            _ right: MutationHistorySnapshotV1) -> MutationHistorySnapshotV1 {
            var rows: [WorkspaceEntityIdentityV1: MutationHistoryEntityRevisionV1] = [:]
            for row in left.entityRevisions + right.entityRevisions {
                if rows[row.identity].map({ $0.revision >= row.revision }) != true { rows[row.identity] = row }
            }
            var receipts = left.receipts
            for record in right.receipts where !receipts.contains(record) { receipts.append(record) }
            return .init(workspaceRevision: max(left.workspaceRevision, right.workspaceRevision),
                lastLocalSequence: max(left.lastLocalSequence, right.lastLocalSequence),
                receipts: receipts, quarantines: left.quarantines + right.quarantines,
                entityRevisions: rows.values.sorted { $0.identity.stableKey < $1.identity.stableKey })
        }
    }
}

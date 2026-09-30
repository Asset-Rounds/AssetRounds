import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23RoundSessionReplacementCommandProjectionTests: XCTestCase {
    func testFiveReplacementMutationNamespacesAreDeterministicDisjointAndIdentityBound() throws {
        let sourceID = try RoundReplacementFixture.mutation(30)
        let baseline = try RoundReplacementFixture.mappedIDs(
            sourceID, identity: RoundReplacementFixture.identity()
        )
        XCTAssertEqual(baseline, try RoundReplacementFixture.mappedIDs(
            sourceID, identity: RoundReplacementFixture.identity()
        ))
        XCTAssertEqual(Set(baseline).count, 5)
        XCTAssertFalse(baseline.contains(sourceID))
        XCTAssertFalse(baseline.contains(try RoundReplacementFixture.identity()
            .destinationPartsStockMutationID(for: sourceID)))
        XCTAssertFalse(baseline.contains(try RoundReplacementFixture.identity()
            .destinationWorkResourceMutationID(for: sourceID)))

        let otherSource = try RoundReplacementFixture.mappedIDs(
            sourceID, identity: RoundReplacementFixture.identity(sourceWorkspace: 11)
        )
        let otherTarget = try RoundReplacementFixture.mappedIDs(
            sourceID, identity: RoundReplacementFixture.identity(targetWorkspace: 12)
        )
        let otherGeneration = try RoundReplacementFixture.mappedIDs(
            sourceID, identity: RoundReplacementFixture.identity(targetGeneration: 13)
        )
        XCTAssertEqual(Set(baseline + otherSource + otherTarget + otherGeneration).count, 20)
        for mode in [BackupRestoreMode.emptyInstall, .clone, .fork] {
            let identity = try RoundReplacementFixture.identity(mode: mode)
            XCTAssertThrowsError(try identity.destinationRoundSessionMutationID(for: sourceID))
        }
    }

    func testAuthenticatedSourceClassifiesRoundDistinctFromGuidedSurveyAndRetainsForeignHistory() throws {
        let corpus = try RoundReplacementFixture.corpus()
        XCTAssertEqual(corpus.source.history, corpus.history)
        XCTAssertEqual(corpus.source.entries.filter { $0.family == .roundSession }.count,
                       corpus.sessions.count)
        XCTAssertEqual(corpus.source.entries.filter { $0.family == .guidedSurvey }.count, 1)
        XCTAssertFalse(corpus.source.entries.contains { $0.envelope.workspaceID == corpus.foreignWorkspace })
        XCTAssertTrue(corpus.history.receipts.contains(corpus.foreignRecord))
        XCTAssertEqual(corpus.source.entries.map(\.record), corpus.orderedRecords)
        XCTAssertEqual(
            corpus.source.entries.dropLast().map(\.family),
            Array(repeating: .roundSession, count: corpus.sessions.count)
        )
        XCTAssertEqual(corpus.source.entries.last?.family, .guidedSurvey)
        for entry in corpus.source.entries where entry.family == .roundSession {
            guard case let .applyRoundSession(mutation) = entry.envelope.command else {
                return XCTFail("round family selected a different command")
            }
            XCTAssertNoThrow(try RoundSessionMutationReceiptV1(
                mutation: mutation, mutationReceipt: entry.receipt
            ))
        }
        let surveyEntry = try XCTUnwrap(corpus.source.entries.last)
        guard case .applySurveySession = surveyEntry.envelope.command else {
            return XCTFail("guided survey family was not kept distinct")
        }
    }

    func testSourceRejectsRelevantQuarantineAndTypedRoundReceiptMismatch() throws {
        let corpus = try RoundReplacementFixture.corpus()
        let firstRecord = try XCTUnwrap(corpus.orderedRecords.first)
        let firstEnvelope = try MutationEnvelopeV1.decodeCanonical(from: firstRecord.envelopeData)
        let quarantine = MutationHistoryQuarantineRecordV1(
            workspaceID: corpus.workspaceID,
            mutationID: firstEnvelope.mutationID.rawValue,
            identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: try firstEnvelope.canonicalSHA256(),
            conflictingIdentitySHA256: String(repeating: "f", count: 64),
            detectedAt: RoundReplacementFixture.date
        )
        let quarantined = RoundReplacementFixture.replacing(
            corpus.history, quarantines: [quarantine]
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(quarantined))
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID, history: quarantined
        ))

        let originalReceipt = try MutationReceiptV1.decodeCanonical(from: firstRecord.receiptData)
        let originalMutation = corpus.mutations[0]
        let wrongImage = MutationPostImageV1.roundSession(
            id: originalMutation.session.sessionID,
            concurrencyIdentity: try originalMutation.concurrencyIdentity,
            revision: originalMutation.session.revision,
            semanticSHA256: String(repeating: "e", count: 64)
        )
        let wrongReceipt = try MutationReceiptV1(
            identity: originalReceipt.identity,
            envelope: firstEnvelope,
            resultingRevision: originalReceipt.resultingRevision,
            postImages: [wrongImage],
            committedAt: originalReceipt.committedAt
        )
        XCTAssertThrowsError(try RoundSessionMutationReceiptV1(
            mutation: originalMutation, mutationReceipt: wrongReceipt
        ))
        let mismatchedRecord = MutationHistoryReceiptRecordV1(
            envelopeData: firstRecord.envelopeData,
            receiptData: try wrongReceipt.canonicalData(),
            reversalBasisData: nil,
            semanticReversalData: nil
        )
        let mismatched = RoundReplacementFixture.replacing(
            corpus.history, record: firstRecord, with: mismatchedRecord
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(mismatched))
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID, history: mismatched
        ))
    }

    func testProjectsCompleteHistoricalTransitionChainAndPreservesLiteralFacts() throws {
        let corpus = try RoundReplacementFixture.corpus()
        let identity = try RoundReplacementFixture.identity(
            sourceWorkspaceID: corpus.workspaceID.rawValue
        )
        let projection = try RoundSessionReplacementCommandProjectionV1.project(
            source: corpus.source, identity: identity
        )
        let targetWorkspace = WorkspaceID(rawValue: identity.targetPointer.workspaceID)
        let targetSessions = projection.commands.map(\.mutation.session)

        XCTAssertEqual(projection.source, corpus.source)
        XCTAssertEqual(projection.commands.map(\.source),
                       corpus.source.entries.filter { $0.family == .roundSession })
        XCTAssertEqual(projection.commands.map(\.mutation.expectedRevision),
                       Array(0..<UInt64(corpus.sessions.count)))
        XCTAssertEqual(projection.commands.map { $0.mutation.session.transition }, [
            .create, .reviseSelection, .start, .visitItem, .completeItem,
            .markInaccessible, .skipItem, .deferItem, .retryItem,
            .markInaccessible, .deferItem, .pause, .resume, .close, .archive,
        ])
        XCTAssertNoThrow(try RoundSessionHistoryValidatorV1.validate(
            corpus.sessions, workspaceID: corpus.workspaceID, sessionID: corpus.sessionID
        ))
        XCTAssertNoThrow(try RoundSessionHistoryValidatorV1.validate(
            targetSessions, workspaceID: targetWorkspace, sessionID: corpus.sessionID
        ))
        XCTAssertNotEqual(
            corpus.sessions[3].items[0].visit?.recordedBy.snapshotID,
            corpus.sessions[3].recordedBy.snapshotID
        )

        for index in corpus.sessions.indices {
            let source = corpus.sessions[index]
            let command = projection.commands[index]
            let target = command.mutation.session
            XCTAssertEqual(target.workspaceID, targetWorkspace)
            XCTAssertEqual(target.sessionID, source.sessionID)
            XCTAssertEqual(target.revision, source.revision)
            XCTAssertEqual(target.state, source.state)
            XCTAssertEqual(target.transition, source.transition)
            XCTAssertEqual(target.transitionItemID, source.transitionItemID)
            XCTAssertEqual(target.counts, source.counts)
            XCTAssertEqual(target.recordedAt, source.recordedAt)
            XCTAssertEqual(target.mutationID, try identity.destinationRoundSessionMutationID(
                for: source.mutationID
            ))
            XCTAssertEqual(command.postImage, try command.mutation.mutationPostImage)
            XCTAssertEqual(command.sourceDependencyMutationIDs,
                           index == 0 ? [] : [corpus.sessions[index - 1].mutationID])
            XCTAssertEqual(command.targetDependencyMutationIDs,
                           index == 0 ? [] : [targetSessions[index - 1].mutationID])
            XCTAssertEqual(target.predecessor,
                           index == 0 ? nil : try targetSessions[index - 1].reference)
            RoundReplacementFixture.assertActor(
                source.recordedBy, target.recordedBy, workspaceID: targetWorkspace
            )
            try RoundReplacementFixture.assertItems(
                source.items, target.items, workspaceID: targetWorkspace
            )
        }

        let final = try XCTUnwrap(targetSessions.last)
        XCTAssertEqual(final.state, .archived)
        XCTAssertEqual(final.items.map(\.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(final.items.map(\.disposition), [
            .completed, .inaccessible, .skipped, .inaccessible, .deferred,
        ])
        XCTAssertEqual(final.items.map(\.reason), [
            nil, .assetDeletedDuringSession, .explicitlyOutOfScope,
            .permissionUnavailable, .followUpRequired,
        ])
        XCTAssertEqual(final.items[0].completion, corpus.completion)
        XCTAssertEqual(final.counts, RoundSessionCountsV1(items: final.items))
    }

    func testExactOlderAndNewerReferencesResolveDespiteNewerSnapshotFrontierAndRecordOrder() throws {
        let reversed = try RoundReplacementFixture.corpus(reverseStoredRecords: true)
        let forward = try RoundReplacementFixture.corpus(reverseStoredRecords: false)
        let identity = try RoundReplacementFixture.identity(
            sourceWorkspaceID: reversed.workspaceID.rawValue
        )
        let reversedProjection = try RoundSessionReplacementCommandProjectionV1.project(
            source: reversed.source, identity: identity
        )
        let forwardProjection = try RoundSessionReplacementCommandProjectionV1.project(
            source: forward.source, identity: identity
        )
        XCTAssertNotEqual(reversed.source.history.receipts, forward.source.history.receipts)
        XCTAssertEqual(reversedProjection.commands, forwardProjection.commands)

        let olderReference = try reversed.sessions[3].reference
        let newerReference = try reversed.sessions[12].reference
        let targetOlder = try reversedProjection.targetSession(for: olderReference)
        let targetNewer = try reversedProjection.targetSession(for: newerReference)
        XCTAssertEqual(targetOlder.revision, olderReference.revision)
        XCTAssertEqual(targetNewer.revision, newerReference.revision)
        XCTAssertEqual(targetOlder.transition, .visitItem)
        XCTAssertEqual(targetNewer.transition, .resume)
        XCTAssertNotEqual(targetOlder.sessionSHA256, targetNewer.sessionSHA256)
        XCTAssertEqual(targetOlder.predecessor, try reversedProjection.commands[2].mutation.session.reference)

        let identityRow = try WorkspaceEntityIdentityV1(
            kind: .roundSession, id: reversed.sessionID
        )
        let snapshotFrontier = try XCTUnwrap(reversed.history.entityRevisions.first {
            $0.identity == identityRow
        })
        XCTAssertGreaterThan(snapshotFrontier.revision, reversed.sessions.last!.revision)
        let tamperedReference = try RoundSessionReferenceV1(
            workspaceID: olderReference.workspaceID,
            sessionID: olderReference.sessionID,
            revision: olderReference.revision,
            sessionSHA256: String(repeating: "f", count: 64)
        )
        XCTAssertThrowsError(try reversedProjection.targetSession(for: tamperedReference)) {
            XCTAssertEqual($0 as? RoundSessionReplacementCommandProjectionFailureV1,
                           .missingDependency)
        }
        let wrongWorkspaceReference = try RoundSessionReferenceV1(
            workspaceID: WorkspaceID(rawValue: RoundReplacementFixture.id(9_700)),
            sessionID: olderReference.sessionID,
            revision: olderReference.revision,
            sessionSHA256: olderReference.sessionSHA256
        )
        XCTAssertThrowsError(try reversedProjection.targetSession(for: wrongWorkspaceReference)) {
            XCTAssertEqual($0 as? RoundSessionReplacementCommandProjectionFailureV1,
                           .missingDependency)
        }
    }

    func testMissingDuplicateAndForkedHistoricalPredecessorsFailClosed() throws {
        let values = try RoundReplacementFixture.values()
        let missing = values.sessions.enumerated().compactMap {
            $0.offset == 6 ? nil : $0.element
        }
        try assertProjectionRejectsMalformedHistory(sessions: missing, expected: .staleRevision)

        var revisedItems = values.sessions[0].items
        revisedItems[1] = try RoundReplacementFixture.item(
            index: 1, workspaceID: values.workspaceID,
            label: "Divergent draft selection"
        )
        let duplicateRevision = try RoundReplacementFixture.session(
            workspaceID: values.workspaceID, sessionID: values.sessionID,
            predecessor: values.sessions[0], state: .draft,
            transition: .reviseSelection, items: revisedItems, mutationSlot: 9_801
        )
        try assertProjectionRejectsMalformedHistory(
            sessions: [values.sessions[0], values.sessions[1], duplicateRevision],
            expected: .staleRevision
        )

        var forkItems = values.sessions[0].items
        forkItems[0] = try RoundReplacementFixture.item(
            index: 0, workspaceID: values.workspaceID,
            label: "Forked draft selection"
        )
        let forkRevision = try RoundReplacementFixture.session(
            workspaceID: values.workspaceID, sessionID: values.sessionID,
            predecessor: values.sessions[0], state: .draft,
            transition: .reviseSelection, items: forkItems, mutationSlot: 9_802
        )
        let forkStart = try RoundReplacementFixture.session(
            workspaceID: values.workspaceID, sessionID: values.sessionID,
            predecessor: forkRevision, state: .active,
            transition: .start, items: forkRevision.items, mutationSlot: 9_803
        )
        try assertProjectionRejectsMalformedHistory(
            sessions: [values.sessions[0], values.sessions[1], forkStart],
            expected: .staleRevision
        )
    }

    func testWrongOwnerAndMappedMutationCollisionFailClosedWhileForeignRoundIsIgnored() throws {
        let corpus = try RoundReplacementFixture.corpus()
        XCTAssertThrowsError(try RoundSessionReplacementCommandProjectionV1.project(
            source: corpus.source,
            identity: RoundReplacementFixture.identity(sourceWorkspace: 91)
        )) { error in
            XCTAssertEqual(error as? RoundSessionReplacementCommandProjectionFailureV1,
                           .invalidIdentity)
        }
        for mode in [BackupRestoreMode.emptyInstall, .clone, .fork] {
            let identity = try RoundReplacementFixture.identity(
                sourceWorkspaceID: corpus.workspaceID.rawValue, mode: mode
            )
            XCTAssertThrowsError(try RoundSessionReplacementCommandProjectionV1.project(
                source: corpus.source, identity: identity
            )) { error in
                XCTAssertEqual(error as? RoundSessionReplacementCommandProjectionFailureV1,
                               .invalidIdentity)
            }
        }

        let identity = try RoundReplacementFixture.identity(
            sourceWorkspaceID: corpus.workspaceID.rawValue
        )
        let mappedID = try identity.destinationRoundSessionMutationID(
            for: corpus.mutations[0].mutationID
        )
        let collisionCorpus = try RoundReplacementFixture.corpus(
            foreignMutationID: mappedID
        )
        XCTAssertThrowsError(try RoundSessionReplacementCommandProjectionV1.project(
            source: collisionCorpus.source, identity: identity
        )) { error in
            XCTAssertEqual(error as? RoundSessionReplacementCommandProjectionFailureV1,
                           .collision)
        }
    }

    func testProjectedCommandsProduceValidTypedTargetReceiptsWithoutStorageClaim() throws {
        let corpus = try RoundReplacementFixture.corpus()
        let identity = try RoundReplacementFixture.identity(
            sourceWorkspaceID: corpus.workspaceID.rawValue
        )
        let projection = try RoundSessionReplacementCommandProjectionV1.project(
            source: corpus.source, identity: identity
        )
        for (index, command) in projection.commands.enumerated() {
            let evidence = try RoundReplacementFixture.record(
                command: .applyRoundSession(command.mutation),
                generationID: identity.targetPointer.generationID,
                workspaceRevision: UInt64(index),
                localSequence: UInt64(index + 1),
                replicaID: ReplicaID(rawValue: RoundReplacementFixture.id(9_900))
            )
            XCTAssertNoThrow(try RoundSessionMutationReceiptV1(
                mutation: command.mutation, mutationReceipt: evidence.receipt
            ))
        }
    }

    private func assertProjectionRejectsMalformedHistory(
        sessions: [RoundSessionV1],
        expected: RoundSessionFailureV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let corpus = try RoundReplacementFixture.corpus(
            sessions: sessions, includeSurvey: false
        )
        let identity = try RoundReplacementFixture.identity(
            sourceWorkspaceID: corpus.workspaceID.rawValue
        )
        XCTAssertEqual(corpus.source.entries.filter { $0.family == .roundSession }.count,
                       sessions.count, file: file, line: line)
        XCTAssertThrowsError(try RoundSessionReplacementCommandProjectionV1.project(
            source: corpus.source, identity: identity
        ), file: file, line: line) {
            XCTAssertEqual($0 as? RoundSessionFailureV1,
                           expected, file: file, line: line)
        }
    }
}

private enum RoundReplacementFixture {
    struct Values {
        let workspaceID: WorkspaceID
        let sessionID: UUID
        let sessions: [RoundSessionV1]
        let completion: RoundItemCompletionReferenceV1
    }

    struct Corpus {
        let workspaceID: WorkspaceID
        let sessionID: UUID
        let sessions: [RoundSessionV1]
        let mutations: [RoundSessionMutationV1]
        let completion: RoundItemCompletionReferenceV1
        let orderedRecords: [MutationHistoryReceiptRecordV1]
        let history: MutationHistorySnapshotV1
        let source: ReferenceOwnerReplacementSourceV1.Source
        let foreignWorkspace: WorkspaceID
        let foreignRecord: MutationHistoryReceiptRecordV1
    }

    struct RecordEvidence {
        let record: MutationHistoryReceiptRecordV1
        let receipt: MutationReceiptV1
        let images: [MutationPostImageV1]
    }

    struct CommandBinding {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
        let expected: [WorkspaceEntityRevisionV1]
        let images: [MutationPostImageV1]
    }

    static let date = Date(timeIntervalSince1970: 1_812_000_000)
    static let digestA = String(repeating: "a", count: 64)
    static let digestB = String(repeating: "b", count: 64)
    static let digestC = String(repeating: "c", count: 64)
    static let generationID = id(8_001)
    static let writerID = id(8_002)
    static let replicaID = ReplicaID(rawValue: id(8_003))

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c5720000-0000-4000-8000-%012x", value))!
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(10_000 + value))
    }

    static func identity(
        sourceWorkspace: Int = 1,
        targetWorkspace: Int = 3,
        targetGeneration: Int = 6,
        mode: BackupRestoreMode = .replaceExisting
    ) throws -> RestoreIdentityV1 {
        try identity(
            sourceWorkspaceID: id(sourceWorkspace), targetWorkspace: targetWorkspace,
            targetGeneration: targetGeneration, mode: mode
        )
    }

    static func identity(
        sourceWorkspaceID: UUID,
        targetWorkspace: Int = 3,
        targetGeneration: Int = 6,
        mode: BackupRestoreMode = .replaceExisting
    ) throws -> RestoreIdentityV1 {
        try RestoreIdentityDecisionV1.decide(.init(
            mode: mode,
            source: .init(workspaceID: sourceWorkspaceID, replicaID: id(2)),
            oldPointer: .init(
                generationID: id(5),
                generationManifestSHA256: digestA,
                workspaceID: id(targetWorkspace), replicaID: id(4)
            ),
            targetGenerationID: id(targetGeneration),
            targetGenerationManifestSHA256: digestB,
            allocatedWorkspaceID: id(20), allocatedReplicaID: id(21)
        ))
    }

    static func mappedIDs(
        _ sourceID: MutationIDV1,
        identity: RestoreIdentityV1
    ) throws -> [MutationIDV1] {
        try [
            identity.destinationWorkPacketMutationID(for: sourceID),
            identity.destinationSurveySessionMutationID(for: sourceID),
            identity.destinationRoundSessionMutationID(for: sourceID),
            identity.destinationScheduleMutationID(for: sourceID),
            identity.destinationFieldDraftMutationID(for: sourceID),
        ]
    }

    static func actor(
        workspaceID: WorkspaceID,
        slot: Int,
        name: String
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(20_000 + slot),
            workspaceID: workspaceID,
            partyID: id(21_000 + slot),
            displayName: name
        )
        return try ActorSnapshotV1(
            snapshotID: id(22_000 + slot),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: .recordedBy,
            displayNameAtTime: reference.displayName,
            capturedAt: date.addingTimeInterval(Double(slot))
        )
    }

    static func requirement(
        workspaceID: WorkspaceID,
        index: Int
    ) throws -> RoundPackageContentRequirementV1 {
        let release = try RoundPackageReleaseReferenceV1(
            packageReleaseID: digestA,
            packageID: "c57-round-package",
            packageContentVersion: 1,
            packageSHA256: digestB,
            workflowSHA256: digestC
        )
        let digest = try ContentDigestV1(
            algorithm: .sha256,
            hexadecimalValue: index.isMultiple(of: 2) ? digestA : digestB
        )
        let content = try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: "round-content-\(index)",
            byteLength: Int64(100 + index),
            mediaType: "image/jpeg",
            digests: ContentDigestSetV1([digest]),
            byteRole: .immutableOriginal,
            createdAt: "2027-06-03T00:00:00.000Z"
        )
        return try RoundPackageContentRequirementV1(
            packageRelease: release, requiredContent: [content]
        )
    }

    static func item(
        index: Int,
        workspaceID: WorkspaceID,
        label: String? = nil
    ) throws -> RoundItemV1 {
        try RoundItemV1(
            itemID: id(30_000 + index), order: index,
            selection: RoundAssetSelectionV1(
                assetID: id(31_000 + index), siteID: id(32_000 + index),
                labelAtSelection: label ?? "Round asset \(index)"
            ),
            requirement: requirement(workspaceID: workspaceID, index: index)
        )
    }

    static func session(
        workspaceID: WorkspaceID,
        sessionID: UUID,
        predecessor: RoundSessionV1? = nil,
        state: RoundSessionStateV1,
        transition: RoundSessionTransitionV1,
        transitionItemID: UUID? = nil,
        items: [RoundItemV1],
        mutationSlot: Int? = nil,
        mutationID: MutationIDV1? = nil
    ) throws -> RoundSessionV1 {
        let revision = (predecessor?.revision ?? 0) + 1
        return try RoundSessionV1(
            workspaceID: workspaceID, sessionID: sessionID,
            predecessor: predecessor, revision: revision,
            mutationID: try mutationID ?? mutation(mutationSlot ?? Int(revision)),
            state: state, transition: transition,
            transitionItemID: transitionItemID, items: items,
            recordedBy: actor(workspaceID: workspaceID, slot: 100, name: "Round recorder"),
            recordedAt: date.addingTimeInterval(1_000 + Double(revision))
        )
    }

    static func replacing(
        _ item: RoundItemV1,
        disposition: RoundItemDispositionV1,
        visitActor: ActorSnapshotV1,
        reason: RoundItemReasonV1? = nil,
        completion: RoundItemCompletionReferenceV1? = nil
    ) throws -> RoundItemV1 {
        let visit: RoundItemVisitV1?
        switch disposition {
        case .visited, .completed:
            visit = try item.visit ?? RoundItemVisitV1(
                visitedAt: date.addingTimeInterval(2_000), recordedBy: visitActor
            )
        case .pending, .inaccessible, .skipped, .deferred:
            visit = item.visit
        }
        return try RoundItemV1(
            itemID: item.itemID, order: item.order,
            selection: item.selection, requirement: item.requirement,
            disposition: disposition, visit: visit,
            reason: reason, completion: completion
        )
    }

    static func replacing(
        _ items: [RoundItemV1],
        index: Int,
        with item: RoundItemV1
    ) -> [RoundItemV1] {
        var result = items
        result[index] = item
        return result
    }

    static func values() throws -> Values {
        let workspaceID = WorkspaceID(rawValue: id(1))
        let sessionID = id(40_000)
        let visitRecorder = try actor(
            workspaceID: workspaceID, slot: 200, name: "Distinct visit recorder"
        )
        let completion = try RoundItemCompletionReferenceV1(
            completionID: id(41_000), revision: 7,
            completionSHA256: digestC
        )
        var items = try (0..<5).map { try item(index: $0, workspaceID: workspaceID) }
        var sessions: [RoundSessionV1] = []

        var current = try session(
            workspaceID: workspaceID, sessionID: sessionID,
            state: .draft, transition: .create, items: items
        )
        sessions.append(current)
        items[0] = try item(
            index: 0, workspaceID: workspaceID, label: "Revised Round asset 0"
        )
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .draft, transition: .reviseSelection, items: items
        )
        sessions.append(current)
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .start, items: items
        )
        sessions.append(current)

        items = replacing(items, index: 0, with: try replacing(
            items[0], disposition: .visited, visitActor: visitRecorder
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .visitItem,
            transitionItemID: items[0].itemID, items: items
        )
        sessions.append(current)
        items = replacing(items, index: 0, with: try replacing(
            items[0], disposition: .completed, visitActor: visitRecorder,
            completion: completion
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .completeItem,
            transitionItemID: items[0].itemID, items: items
        )
        sessions.append(current)
        items = replacing(items, index: 1, with: try replacing(
            items[1], disposition: .inaccessible, visitActor: visitRecorder,
            reason: .assetDeletedDuringSession
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .markInaccessible,
            transitionItemID: items[1].itemID, items: items
        )
        sessions.append(current)
        items = replacing(items, index: 2, with: try replacing(
            items[2], disposition: .skipped, visitActor: visitRecorder,
            reason: .explicitlyOutOfScope
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .skipItem,
            transitionItemID: items[2].itemID, items: items
        )
        sessions.append(current)
        items = replacing(items, index: 3, with: try replacing(
            items[3], disposition: .deferred, visitActor: visitRecorder,
            reason: .interruption
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .deferItem,
            transitionItemID: items[3].itemID, items: items
        )
        sessions.append(current)
        items = replacing(items, index: 3, with: try replacing(
            items[3], disposition: .pending, visitActor: visitRecorder
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .retryItem,
            transitionItemID: items[3].itemID, items: items
        )
        sessions.append(current)
        items = replacing(items, index: 3, with: try replacing(
            items[3], disposition: .inaccessible, visitActor: visitRecorder,
            reason: .permissionUnavailable
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .markInaccessible,
            transitionItemID: items[3].itemID, items: items
        )
        sessions.append(current)
        items = replacing(items, index: 4, with: try replacing(
            items[4], disposition: .deferred, visitActor: visitRecorder,
            reason: .followUpRequired
        ))
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .deferItem,
            transitionItemID: items[4].itemID, items: items
        )
        sessions.append(current)
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .paused, transition: .pause, items: items
        )
        sessions.append(current)
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .active, transition: .resume, items: items
        )
        sessions.append(current)
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .completed, transition: .close, items: items
        )
        sessions.append(current)
        current = try session(
            workspaceID: workspaceID, sessionID: sessionID, predecessor: current,
            state: .archived, transition: .archive, items: items
        )
        sessions.append(current)

        _ = try RoundSessionHistoryValidatorV1.validate(
            sessions, workspaceID: workspaceID, sessionID: sessionID
        )
        return Values(
            workspaceID: workspaceID, sessionID: sessionID,
            sessions: sessions, completion: completion
        )
    }

    static func corpus(
        sessions explicitSessions: [RoundSessionV1]? = nil,
        includeSurvey: Bool = true,
        reverseStoredRecords: Bool = true,
        foreignMutationID: MutationIDV1? = nil
    ) throws -> Corpus {
        let values = try values()
        let sessions = explicitSessions ?? values.sessions
        let mutations = try sessions.map {
            try RoundSessionMutationV1(
                workspaceID: $0.workspaceID,
                expectedRevision: $0.revision - 1,
                mutationID: $0.mutationID,
                session: $0
            )
        }
        var commands = mutations.map { WorkspaceCommandV1.applyRoundSession($0) }
        if includeSurvey {
            commands.append(try surveyCommand(workspaceID: values.workspaceID))
        }
        var records: [RecordEvidence] = []
        for (index, command) in commands.enumerated() {
            records.append(try record(
                command: command, generationID: generationID,
                workspaceRevision: UInt64(index), localSequence: UInt64(index + 1),
                replicaID: replicaID
            ))
        }

        let foreignWorkspace = WorkspaceID(rawValue: id(9_000))
        let foreignItem = try item(index: 0, workspaceID: foreignWorkspace)
        let foreignSession = try session(
            workspaceID: foreignWorkspace, sessionID: id(49_000),
            state: .draft, transition: .create, items: [foreignItem],
            mutationID: try foreignMutationID ?? mutation(9_000)
        )
        let foreignMutation = try RoundSessionMutationV1(
            workspaceID: foreignWorkspace, expectedRevision: 0,
            mutationID: foreignSession.mutationID, session: foreignSession
        )
        let foreign = try record(
            command: .applyRoundSession(foreignMutation),
            generationID: id(9_001), workspaceRevision: 0, localSequence: 1,
            replicaID: ReplicaID(rawValue: id(9_002))
        )

        let orderedRecords = records.map(\.record)
        var stored = reverseStoredRecords
            ? Array(orderedRecords.reversed()) : orderedRecords
        stored.append(foreign.record)
        var terminal: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for evidence in records + [foreign] {
            for image in evidence.images {
                terminal[try image.identity] = max(
                    terminal[try image.identity, default: 0], image.revision
                )
            }
        }
        let roundIdentity = try WorkspaceEntityIdentityV1(
            kind: .roundSession, id: values.sessionID
        )
        terminal[roundIdentity] = (terminal[roundIdentity] ?? 0) + 4
        let history = MutationHistorySnapshotV1(
            workspaceRevision: UInt64(records.count),
            lastLocalSequence: UInt64(records.count),
            receipts: stored, quarantines: [],
            entityRevisions: terminal.map {
                MutationHistoryEntityRevisionV1(identity: $0.key, revision: $0.value)
            }.sorted { $0.identity.stableKey < $1.identity.stableKey }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        let source = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: values.workspaceID, history: history
        )
        return Corpus(
            workspaceID: values.workspaceID, sessionID: values.sessionID,
            sessions: sessions, mutations: mutations, completion: values.completion,
            orderedRecords: orderedRecords, history: history, source: source,
            foreignWorkspace: foreignWorkspace, foreignRecord: foreign.record
        )
    }

    static func surveyCommand(workspaceID: WorkspaceID) throws -> WorkspaceCommandV1 {
        let provisional = try C26SurveySessionTestSupport.provisional(
            workspaceID: workspaceID, slot: 7_700,
            mutationID: C26SurveySessionTestSupport.mutation(7_701)
        )
        let mutation = try SurveySessionMutationV1(
            workspaceID: workspaceID,
            mutationID: provisional.mutationID,
            payload: .applyProvisionalSubject(provisional)
        )
        return .applySurveySession(mutation)
    }

    static func record(
        command: WorkspaceCommandV1,
        generationID: UUID,
        workspaceRevision: UInt64,
        localSequence: UInt64,
        replicaID: ReplicaID
    ) throws -> RecordEvidence {
        let binding = try binding(command)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: binding.workspaceID,
            generationID: generationID,
            writerInstanceID: writerID,
            workspaceRevision: workspaceRevision,
            entityRevisions: binding.expected
        )
        let envelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: binding.mutationID,
                expectedRevision: expected,
                command: command
            ),
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: binding.workspaceID, replicaID: replicaID
            )
        )
        let resulting = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: binding.workspaceID,
                generationID: generationID,
                writerInstanceID: writerID,
                workspaceRevision: workspaceRevision + 1,
                entityRevisions: try binding.images.map {
                    WorkspaceEntityRevisionV1(
                        identity: try $0.identity, revision: $0.revision
                    )
                }
            )
        )
        let receipt = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: binding.workspaceID, replicaID: replicaID,
                localSequence: localSequence
            ),
            envelope: envelope,
            resultingRevision: resulting,
            postImages: binding.images,
            committedAt: date.addingTimeInterval(3_000 + Double(localSequence))
        )
        switch command {
        case let .applyRoundSession(mutation):
            _ = try RoundSessionMutationReceiptV1(
                mutation: mutation, mutationReceipt: receipt
            )
        case let .applySurveySession(mutation):
            _ = try SurveySessionMutationReceiptV1(
                mutation: mutation, mutationReceipt: receipt
            )
        default:
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return RecordEvidence(
            record: MutationHistoryReceiptRecordV1(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: nil,
                semanticReversalData: nil
            ),
            receipt: receipt,
            images: binding.images
        )
    }

    static func binding(_ command: WorkspaceCommandV1) throws -> CommandBinding {
        switch command {
        case let .applyRoundSession(mutation):
            let identity = try mutation.concurrencyIdentity
            return CommandBinding(
                workspaceID: mutation.workspaceID,
                mutationID: mutation.mutationID,
                expected: [WorkspaceEntityRevisionV1(
                    identity: identity, revision: mutation.expectedRevision
                )],
                images: [try mutation.mutationPostImage]
            )
        case let .applySurveySession(mutation):
            let identities = try mutation.concurrencyIdentities
            return CommandBinding(
                workspaceID: mutation.workspaceID,
                mutationID: mutation.mutationID,
                expected: try identities.map {
                    WorkspaceEntityRevisionV1(
                        identity: $0,
                        revision: try mutation.expectedRevision(for: $0)
                    )
                },
                images: try mutation.mutationPostImages
            )
        default:
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    static func replacing(
        _ history: MutationHistorySnapshotV1,
        quarantines: [MutationHistoryQuarantineRecordV1]
    ) -> MutationHistorySnapshotV1 {
        MutationHistorySnapshotV1(
            workspaceRevision: history.workspaceRevision,
            lastLocalSequence: history.lastLocalSequence,
            receipts: history.receipts,
            quarantines: quarantines,
            entityRevisions: history.entityRevisions
        )
    }

    static func replacing(
        _ history: MutationHistorySnapshotV1,
        record: MutationHistoryReceiptRecordV1,
        with replacement: MutationHistoryReceiptRecordV1
    ) -> MutationHistorySnapshotV1 {
        MutationHistorySnapshotV1(
            workspaceRevision: history.workspaceRevision,
            lastLocalSequence: history.lastLocalSequence,
            receipts: history.receipts.map { $0 == record ? replacement : $0 },
            quarantines: history.quarantines,
            entityRevisions: history.entityRevisions
        )
    }

    static func assertActor(
        _ source: ActorSnapshotV1,
        _ target: ActorSnapshotV1,
        workspaceID: WorkspaceID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(target.workspaceID, workspaceID, file: file, line: line)
        XCTAssertEqual(target.snapshotID, source.snapshotID, file: file, line: line)
        XCTAssertEqual(target.actor.actorReferenceID,
                       source.actor.actorReferenceID, file: file, line: line)
        XCTAssertEqual(target.actor.workspaceID, workspaceID, file: file, line: line)
        XCTAssertEqual(target.actor.partyID, source.actor.partyID, file: file, line: line)
        XCTAssertEqual(target.actor.displayName,
                       source.actor.displayName, file: file, line: line)
        XCTAssertEqual(target.responsibility,
                       source.responsibility, file: file, line: line)
        XCTAssertEqual(target.displayNameAtTime,
                       source.displayNameAtTime, file: file, line: line)
        XCTAssertEqual(target.capturedAt, source.capturedAt, file: file, line: line)
    }

    static func assertItems(
        _ source: [RoundItemV1],
        _ target: [RoundItemV1],
        workspaceID: WorkspaceID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(target.count, source.count, file: file, line: line)
        for (old, new) in zip(source, target) {
            XCTAssertEqual(new.itemID, old.itemID, file: file, line: line)
            XCTAssertEqual(new.order, old.order, file: file, line: line)
            XCTAssertEqual(new.selection, old.selection, file: file, line: line)
            XCTAssertEqual(new.requirement.packageRelease,
                           old.requirement.packageRelease, file: file, line: line)
            XCTAssertEqual(new.disposition, old.disposition, file: file, line: line)
            XCTAssertEqual(new.reason, old.reason, file: file, line: line)
            XCTAssertEqual(new.completion, old.completion, file: file, line: line)
            XCTAssertEqual(new.visit?.visitedAt,
                           old.visit?.visitedAt, file: file, line: line)
            if let oldActor = old.visit?.recordedBy,
               let newActor = new.visit?.recordedBy {
                assertActor(oldActor, newActor, workspaceID: workspaceID,
                            file: file, line: line)
            } else {
                XCTAssertEqual(new.visit == nil, old.visit == nil, file: file, line: line)
            }
            XCTAssertEqual(new.requirement.requiredContent.count,
                           old.requirement.requiredContent.count, file: file, line: line)
            for (oldContent, newContent) in zip(
                old.requirement.requiredContent, new.requirement.requiredContent
            ) {
                XCTAssertEqual(newContent.workspaceID,
                               workspaceID.rawValue.uuidString.lowercased(),
                               file: file, line: line)
                XCTAssertEqual(newContent.contentID,
                               oldContent.contentID, file: file, line: line)
                XCTAssertEqual(newContent.byteLength,
                               oldContent.byteLength, file: file, line: line)
                XCTAssertEqual(newContent.mediaType,
                               oldContent.mediaType, file: file, line: line)
                XCTAssertEqual(newContent.digests,
                               oldContent.digests, file: file, line: line)
                XCTAssertEqual(newContent.byteRole,
                               oldContent.byteRole, file: file, line: line)
                XCTAssertEqual(newContent.createdAt,
                               oldContent.createdAt, file: file, line: line)
            }
        }
    }
}

import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23ReferenceOwnerReplacementSourceTests: XCTestCase {
    func testAuthenticatedMixedHistoryRetainsExactOriginalsAndOrdersOwnFourFamilies() throws {
        let corpus = try ReferenceOwnerSourceFixture.make()
        let source = try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID,
            history: corpus.history
        )

        XCTAssertEqual(source.workspaceID, corpus.workspaceID)
        XCTAssertEqual(source.history, corpus.history)
        XCTAssertEqual(source.entries.map(\.family), [
            .workPacket, .guidedSurvey, .schedule, .fieldDraft,
        ])
        XCTAssertEqual(
            source.entries.map { $0.receipt.resultingRevision.workspaceRevision },
            [1, 2, 3, 4]
        )
        XCTAssertEqual(source.entries.map(\.record), corpus.targetRecords)
        XCTAssertEqual(source.history.receipts.count, 5)
        XCTAssertTrue(source.history.receipts.contains(corpus.foreignRecord))
        let foreignEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: corpus.foreignRecord.envelopeData
        )
        XCTAssertEqual(foreignEnvelope.mutationID, source.entries[0].envelope.mutationID)
        XCTAssertNotEqual(foreignEnvelope.workspaceID, source.entries[0].envelope.workspaceID)
        let historicalImage = try XCTUnwrap(source.entries[0].receipt.postImages.first)
        let physicalTip = try XCTUnwrap(source.history.entityRevisions.first {
            $0.identity == (try? historicalImage.identity)
        })
        XCTAssertGreaterThan(physicalTip.revision, historicalImage.revision)
        XCTAssertEqual(source.entries.flatMap(\.receipt.postImages).count, 4)
        for entry in source.entries {
            XCTAssertEqual(try entry.envelope.canonicalData(), entry.record.envelopeData)
            XCTAssertEqual(try entry.receipt.canonicalData(), entry.record.receiptData)
        }
    }

    func testWrongOwnerMutationAndExpectedFrontierFailClosed() throws {
        let corpus = try ReferenceOwnerSourceFixture.make()
        let original = corpus.targetRecords[1]
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
        let originalText = try XCTUnwrap(String(data: original.envelopeData, encoding: .utf8))

        let wrongOwnerBytes = Data(originalText.replacingOccurrences(
            of: corpus.workspaceID.rawValue.uuidString,
            with: ReferenceOwnerSourceFixture.id(998).uuidString
        ).utf8)
        XCTAssertNotEqual(wrongOwnerBytes, original.envelopeData)
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID,
            history: ReferenceOwnerSourceFixture.replacing(
                original, envelopeData: wrongOwnerBytes, in: corpus.history
            )
        ))

        let wrongMutationBytes = Data(originalText.replacingOccurrences(
            of: envelope.mutationID.rawValue.uuidString,
            with: ReferenceOwnerSourceFixture.id(997).uuidString
        ).utf8)
        XCTAssertNotEqual(wrongMutationBytes, original.envelopeData)
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID,
            history: ReferenceOwnerSourceFixture.replacing(
                original, envelopeData: wrongMutationBytes, in: corpus.history
            )
        ))

        let wrongExpected = try ReferenceOwnerSourceFixture.envelope(
            command: envelope.command,
            workspaceRevision: envelope.expectedRevision.workspaceRevision,
            entityRevisionOverride: 1
        )
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID,
            history: ReferenceOwnerSourceFixture.replacing(
                original, envelopeData: wrongExpected.canonicalData(), in: corpus.history
            )
        ))
    }

    func testReceiptBodyMismatchAndDuplicateQualifiedMutationFailClosed() throws {
        let corpus = try ReferenceOwnerSourceFixture.make()
        let first = corpus.targetRecords[1]
        let receipt = try XCTUnwrap(String(data: first.receiptData, encoding: .utf8))
        let originalBody = try MutationReceiptV1.decodeCanonical(from: first.receiptData)
            .commandBodySHA256
        let changedBody = String(repeating: originalBody.first == "a" ? "b" : "a", count: 64)
        let hostileBytes = Data(receipt.replacingOccurrences(
            of: originalBody, with: changedBody
        ).utf8)
        XCTAssertNoThrow(try MutationReceiptV1.decodeCanonical(from: hostileBytes))
        let hostileRecord = MutationHistoryReceiptRecordV1(
            envelopeData: first.envelopeData,
            receiptData: hostileBytes,
            reversalBasisData: nil,
            semanticReversalData: nil
        )
        let hostileHistory = MutationHistorySnapshotV1(
            workspaceRevision: corpus.history.workspaceRevision,
            lastLocalSequence: corpus.history.lastLocalSequence,
            receipts: corpus.history.receipts.map { $0 == first ? hostileRecord : $0 },
            quarantines: [],
            entityRevisions: corpus.history.entityRevisions
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(hostileHistory))
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID, history: hostileHistory
        ))

        let duplicateHistory = MutationHistorySnapshotV1(
            workspaceRevision: corpus.history.workspaceRevision,
            lastLocalSequence: corpus.history.lastLocalSequence,
            receipts: corpus.history.receipts + [first],
            quarantines: [],
            entityRevisions: corpus.history.entityRevisions
        )
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID, history: duplicateHistory
        ))
    }

    func testRelevantQuarantineIsDeniedAfterSnapshotAuthentication() throws {
        let corpus = try ReferenceOwnerSourceFixture.make()
        let envelope = try MutationEnvelopeV1.decodeCanonical(
            from: corpus.targetRecords[1].envelopeData
        )
        let quarantine = MutationHistoryQuarantineRecordV1(
            workspaceID: corpus.workspaceID,
            mutationID: envelope.mutationID.rawValue,
            identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: try envelope.canonicalSHA256(),
            conflictingIdentitySHA256: String(repeating: "f", count: 64),
            detectedAt: ReferenceOwnerSourceFixture.date
        )
        let history = MutationHistorySnapshotV1(
            workspaceRevision: corpus.history.workspaceRevision,
            lastLocalSequence: corpus.history.lastLocalSequence,
            receipts: corpus.history.receipts,
            quarantines: [quarantine],
            entityRevisions: corpus.history.entityRevisions
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(history))
        XCTAssertThrowsError(try ReferenceOwnerReplacementSourceV1.source(
            workspaceID: corpus.workspaceID, history: history
        ))
    }
}

private enum ReferenceOwnerSourceFixture {
    struct Corpus {
        let workspaceID: WorkspaceID
        let history: MutationHistorySnapshotV1
        let targetRecords: [MutationHistoryReceiptRecordV1]
        let foreignRecord: MutationHistoryReceiptRecordV1
    }

    static let date = Date(timeIntervalSince1970: 1_810_000_000)
    static let generationID = id(2)
    static let writerID = id(3)
    static let replicaID = ReplicaID(rawValue: id(4))

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c5700000-0000-4000-8000-%012x", value))!
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(value))
    }

    static func make() throws -> Corpus {
        let workspaceID = WorkspaceID(rawValue: id(1))
        let commands = try targetCommands(workspaceID: workspaceID)
        var targetRecords: [MutationHistoryReceiptRecordV1] = []
        var terminal: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for (offset, command) in commands.enumerated() {
            let evidence = try record(
                command: command,
                workspaceRevision: UInt64(offset),
                localSequence: UInt64(offset + 1)
            )
            targetRecords.append(evidence.record)
            for image in evidence.images {
                terminal[try image.identity] = image.revision
            }
        }
        if let firstImage = try targetRecords.first.map({
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData).postImages[0]
        }) {
            terminal[try firstImage.identity] = firstImage.revision + 3
        }

        let foreignWorkspace = WorkspaceID(rawValue: id(900))
        let foreignCommand = try workPacketCommand(
            workspaceID: foreignWorkspace,
            slot: 900,
            mutationID: try mutation(11)
        )
        let foreign = try record(
            command: foreignCommand,
            workspaceRevision: 0,
            localSequence: 1
        )
        for image in foreign.images {
            terminal[try image.identity] = image.revision
        }

        // Deliberately store records out of revision order. Selection ordering must
        // derive from authenticated receipts without rewriting the source history.
        let stored = [targetRecords[2], foreign.record, targetRecords[0],
                      targetRecords[3], targetRecords[1]]
        let history = MutationHistorySnapshotV1(
            workspaceRevision: 4,
            lastLocalSequence: 4,
            receipts: stored,
            quarantines: [],
            entityRevisions: terminal.map {
                MutationHistoryEntityRevisionV1(identity: $0.key, revision: $0.value)
            }.sorted { $0.identity.stableKey < $1.identity.stableKey }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        return Corpus(
            workspaceID: workspaceID,
            history: history,
            targetRecords: targetRecords,
            foreignRecord: foreign.record
        )
    }

    static func targetCommands(workspaceID: WorkspaceID) throws -> [WorkspaceCommandV1] {
        let work = try workPacketCommand(workspaceID: workspaceID, slot: 10)

        let provisional = try C26SurveySessionTestSupport.provisional(
            workspaceID: workspaceID,
            slot: 30,
            mutationID: mutation(31)
        )
        let survey = try SurveySessionMutationV1(
            workspaceID: workspaceID,
            mutationID: provisional.mutationID,
            payload: .applyProvisionalSubject(provisional)
        )

        let scheduleRelease = try schedule(workspaceID: workspaceID, slot: 50)
        let schedule = try ScheduleMutationV1(
            workspaceID: workspaceID,
            mutationID: scheduleRelease.mutationID,
            payload: .appendRelease(scheduleRelease, predecessor: nil)
        )

        let draftFixture = try C36FieldDraftTestSupportV1.makeFixture(seed: 136_700)
        let checkpoint = try replacingWorkspace(
            draftFixture.activeCheckpoint,
            workspaceID: workspaceID,
            mutationID: mutation(71)
        )
        let field = try FieldDraftMutationV1(
            workspaceID: workspaceID,
            expectedRevision: 0,
            expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
            mutationID: checkpoint.mutationID,
            postImage: .createCheckpoint(checkpoint)
        )
        return [work, .applySurveySession(survey),
                .applySchedule(schedule), .applyFieldDraft(field)]
    }

    static func workPacketCommand(
        workspaceID: WorkspaceID,
        slot: Int,
        mutationID explicitMutationID: MutationIDV1? = nil
    ) throws -> WorkspaceCommandV1 {
        let mutationID = try explicitMutationID ?? mutation(slot + 1)
        let actor = try C26SurveySessionTestSupport.actor(
            workspaceID: workspaceID, slot: slot + 2
        )
        let item = try WorkPacketItemV1(
            itemID: "c57-\(slot)", kind: .inspection,
            expectedRevision: 1, itemSHA256: String(repeating: "a", count: 64)
        )
        let manifest = try WorkPacketManifestV1(
            manifestID: id(slot + 3), packetID: id(slot + 4), packetVersion: 1,
            workspaceID: workspaceID, items: [item], packageReleases: [],
            creationBasis: .explicitLocalSelection, creator: actor,
            createdAt: date, mutationID: mutationID
        )
        return .applyWorkPacket(try WorkPacketMutationV1(
            workspaceID: workspaceID, expectedRevision: 0,
            mutationID: mutationID, postImage: .appendManifest(manifest)
        ))
    }

    static func schedule(workspaceID: WorkspaceID, slot: Int) throws
        -> ScheduleDefinitionReleaseV1 {
        let definition = try C26SurveySessionTestSupport.release(
            releaseSlot: slot + 1, workspaceID: workspaceID
        )
        let anchor = ScheduleLocalAnchorV1(
            year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
            hour: 9, minute: 0, second: 0
        )
        return try ScheduleDefinitionReleaseV1(
            scheduleDefinitionID: id(slot + 2), releaseID: id(slot + 3),
            workspaceID: workspaceID, occurrenceIdentityNamespaceID: id(slot + 4),
            action: .create, lifecycleState: .active,
            recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)),
            timeBasis: .init(
                ianaTimeZoneIdentifier: "America/New_York",
                timeZoneRuleSetVersion: "2026a",
                timeZoneRuleSetSHA256: String(repeating: "b", count: 64),
                ambiguousTimePolicy: .earlierOffset,
                nonexistentTimePolicy: .shiftForwardByGap,
                calendarBasisSHA256: String(repeating: "c", count: 64)
            ),
            startsAtUTC: date, generationHorizonDays: 30,
            maximumGeneratedOccurrences: 8, readyLeadSeconds: 3_600,
            overdueGraceSeconds: 7_200,
            subject: .init(kind: .asset, subjectID: id(slot + 5), revision: 1,
                           ownerAssetID: nil),
            workDefinition: try .init(
                kind: .roundSession, definition: definition,
                packageRelease: C26SurveySessionTestSupport.packageRelease()
            ),
            revision: 1, mutationID: mutation(slot + 6),
            authoredBy: C26SurveySessionTestSupport.actor(
                workspaceID: workspaceID, slot: slot + 7
            ),
            authoredAt: date
        )
    }

    static func replacingWorkspace(
        _ value: FieldDraftCheckpointV1,
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(
            draftID: value.draftID, workspaceID: workspaceID,
            scope: value.scope, purpose: value.purpose, codec: value.codec,
            baseCanonicalRevision: value.baseCanonicalRevision,
            draftRevision: value.draftRevision, payloadData: value.payloadData,
            stageIDs: value.stageIDs, resumeAnchor: value.resumeAnchor,
            state: value.state,
            lastDurableMutationID: value.lastDurableMutationID,
            lastReceiptSHA256: value.lastReceiptSHA256,
            updatedAt: value.updatedAt, mutationID: mutationID
        )
    }

    struct RecordEvidence {
        let record: MutationHistoryReceiptRecordV1
        let images: [MutationPostImageV1]
    }

    static func record(
        command: WorkspaceCommandV1,
        workspaceRevision: UInt64,
        localSequence: UInt64
    ) throws -> RecordEvidence {
        let binding = try bindings(command)
        let envelope = try envelope(
            command: command, workspaceRevision: workspaceRevision
        )
        let resulting = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: binding.workspaceID,
                generationID: generationID,
                writerInstanceID: writerID,
                workspaceRevision: workspaceRevision + 1,
                entityRevisions: try binding.images.map {
                    WorkspaceEntityRevisionV1(identity: try $0.identity, revision: $0.revision)
                }
            )
        )
        let receipt = try MutationReceiptV1(
            identity: .init(
                workspaceID: binding.workspaceID,
                replicaID: replicaID,
                localSequence: localSequence
            ),
            envelope: envelope,
            resultingRevision: resulting,
            postImages: binding.images,
            committedAt: date.addingTimeInterval(Double(localSequence))
        )
        return RecordEvidence(
            record: MutationHistoryReceiptRecordV1(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: nil,
                semanticReversalData: nil
            ),
            images: binding.images
        )
    }

    static func envelope(
        command: WorkspaceCommandV1,
        workspaceRevision: UInt64,
        entityRevisionOverride: UInt64? = nil
    ) throws -> MutationEnvelopeV1 {
        let binding = try bindings(command)
        let expectedRows = binding.expected.map {
            WorkspaceEntityRevisionV1(
                identity: $0.identity,
                revision: entityRevisionOverride ?? $0.revision
            )
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: binding.workspaceID,
            generationID: generationID,
            writerInstanceID: writerID,
            workspaceRevision: workspaceRevision,
            entityRevisions: expectedRows
        )
        return try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: binding.mutationID,
                expectedRevision: expected,
                command: command
            ),
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: binding.workspaceID, replicaID: replicaID
            )
        )
    }

    static func replacing(
        _ original: MutationHistoryReceiptRecordV1,
        envelopeData: Data,
        in history: MutationHistorySnapshotV1
    ) -> MutationHistorySnapshotV1 {
        let replacement = MutationHistoryReceiptRecordV1(
            envelopeData: envelopeData,
            receiptData: original.receiptData,
            reversalBasisData: original.reversalBasisData,
            semanticReversalData: original.semanticReversalData
        )
        return MutationHistorySnapshotV1(
            workspaceRevision: history.workspaceRevision,
            lastLocalSequence: history.lastLocalSequence,
            receipts: history.receipts.map { $0 == original ? replacement : $0 },
            quarantines: history.quarantines,
            entityRevisions: history.entityRevisions
        )
    }

    struct Bindings {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
        let expected: [WorkspaceEntityRevisionV1]
        let images: [MutationPostImageV1]
    }

    static func bindings(_ command: WorkspaceCommandV1) throws -> Bindings {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
        let identities: [WorkspaceEntityIdentityV1]
        let expectedValues: [UInt64]
        let images: [MutationPostImageV1]
        switch command {
        case let .applyWorkPacket(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = [try value.concurrencyIdentity]
            expectedValues = [value.expectedRevision]
            images = [try value.postImage.mutationPostImage]
        case let .applySurveySession(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = try value.concurrencyIdentities
            expectedValues = try identities.map { try value.expectedRevision(for: $0) }
            images = try value.mutationPostImages
        case let .applySchedule(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = try value.concurrencyIdentities
            expectedValues = try identities.map { try value.expectedRevision(for: $0) }
            images = try value.mutationPostImages
        case let .applyFieldDraft(value):
            workspaceID = value.workspaceID; mutationID = value.mutationID
            identities = try value.concurrencyIdentities
            expectedValues = try identities.map { try value.expectedRevision(for: $0) }
            images = try value.postImage.mutationPostImages
        default:
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return Bindings(
            workspaceID: workspaceID,
            mutationID: mutationID,
            expected: zip(identities, expectedValues).map {
                WorkspaceEntityRevisionV1(identity: $0.0, revision: $0.1)
            },
            images: images
        )
    }
}

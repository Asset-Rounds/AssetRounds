import Foundation
import XCTest
@testable import FieldEvidenceApp

private enum V23MyDayDraftFixtures {
    static let workspaceID = WorkspaceID(rawValue: id(1))
    static let now = Date(timeIntervalSince1970: 1_789_084_800)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "57000000-0000-4000-8000-%012d", value))!
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try .init(rawValue: id(value))
    }

    static func key(_ day: String = "2026-09-10") throws -> MyDayKeyV1 {
        try .init(
            workspaceID: workspaceID,
            civilDate: .init(day),
            ianaTimeZoneIdentifier: "America/New_York"
        )
    }

    static func actor(
        _ value: Int = 10,
        responsibility: ResponsibilityKindV1 = .recordedBy
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(value),
            workspaceID: workspaceID,
            displayName: "My Day recorder"
        )
        return try .init(
            snapshotID: id(value + 1),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: responsibility,
            displayNameAtTime: reference.displayName,
            capturedAt: now
        )
    }

    static func editingPayload() throws -> MyDayPlanningDraftPayloadV1 {
        let key = try key()
        let context = try MyDayPlanningConfirmedContextV1(
            key: key,
            recordedBy: actor(),
            keyWasExplicitlyConfirmed: true,
            recordedByWasExplicitlySelectedOrCaptured: true
        )
        let draft = try MyDayPlanDraftV1(
            key: key,
            items: [],
            eligibleReferences: []
        )
        return try .init(editing: context, intent: .plan(draft: draft, predecessor: nil))
    }

    static func saveCommand() throws -> MyDayCommandV1 {
        let key = try key()
        let predecessor = try MyDayPlanV1(
            planID: id(40),
            key: key,
            items: [],
            revision: 1,
            mutationID: mutation(41),
            authoredBy: actor(),
            authoredAt: now
        )
        let successor = try MyDayPlanV1(
            planID: predecessor.planID,
            key: key,
            items: [],
            predecessor: predecessor,
            revision: 2,
            mutationID: mutation(42),
            authoredBy: actor(),
            authoredAt: now.addingTimeInterval(1)
        )
        return .save(successor: successor, predecessor: predecessor)
    }

    static func carryoverCommand() throws -> MyDayCommandV1 {
        let sourceKey = try key("2026-09-10")
        let targetKey = try key("2026-09-11")
        let reference = MyDayEligibleReferenceV1.roundSession(
            workspaceID: workspaceID,
            sessionID: id(50),
            revision: 1,
            sessionSHA256: String(repeating: "a", count: 64)
        )
        let item = try MyDayItemV1(
            membershipID: id(51),
            reference: reference,
            manualOrder: 0,
            estimate: .init(wholeMinutes: 30)
        )
        let source = try MyDayPlanV1(
            planID: id(52),
            key: sourceKey,
            items: [item],
            revision: 1,
            mutationID: mutation(53),
            authoredBy: actor(),
            authoredAt: now
        )
        let carryover = try MyDayCarryoverPlanV1(
            sourcePlan: source,
            targetKey: targetKey,
            membershipIDs: [item.membershipID]
        )
        let target = try MyDayPlanV1(
            planID: id(54),
            key: targetKey,
            items: [item],
            revision: 1,
            mutationID: mutation(55),
            authoredBy: actor(),
            authoredAt: now.addingTimeInterval(1)
        )
        let receipt = try MyDayCarryoverReceiptV1(
            plan: carryover,
            source: source,
            target: target,
            mutationID: target.mutationID,
            committedAt: now.addingTimeInterval(1)
        )
        return .carryover(plan: carryover, source: source, target: target, receipt: receipt)
    }

    static func attempt(
        command: MyDayCommandV1,
        seed: Int = 100
    ) throws -> MyDayPlanningCommitAttemptInputsV1 {
        try .init(
            command: command,
            fieldDraftPlanID: id(seed),
            preparedSagaID: id(seed + 1),
            contentPromotedSagaID: id(seed + 2),
            targetCommittedSagaID: id(seed + 3),
            draftRetirePendingSagaID: id(seed + 4),
            draftRetiredSagaID: id(seed + 5),
            preparedSagaMutationID: mutation(seed + 10),
            contentPromotedSagaMutationID: mutation(seed + 11),
            targetCommittedSagaMutationID: mutation(seed + 12),
            draftRetirePendingSagaMutationID: mutation(seed + 13),
            terminalBundleMutationID: mutation(seed + 14),
            commitReceiptID: id(seed + 6),
            preparedSagaUpdatedAt: now,
            contentPromotedSagaUpdatedAt: now.addingTimeInterval(1),
            targetCommittedSagaUpdatedAt: now.addingTimeInterval(2),
            draftRetirePendingSagaUpdatedAt: now.addingTimeInterval(3),
            draftRetiredSagaUpdatedAt: now.addingTimeInterval(4),
            terminalCheckpointUpdatedAt: now.addingTimeInterval(5)
        )
    }

    static func checkpoint(
        payload: MyDayPlanningDraftPayloadV1,
        key: MyDayKeyV1,
        baseRevision: UInt64,
        draftRevision: UInt64,
        state: FieldDraftStateV1,
        mutation: MutationIDV1,
        scope: DraftScopeKeyV1? = nil,
        stageIDs: [UUID] = [],
        updatedAt: Date = now,
        lastDurableMutationID: MutationIDV1? = nil,
        lastReceiptSHA256: String? = nil
    ) throws -> FieldDraftCheckpointV1 {
        let resolvedScope: DraftScopeKeyV1
        if let scope {
            resolvedScope = scope
        } else {
            resolvedScope = try MyDayPlanningDraftCodecV1.scope(for: key)
        }
        return try .init(
            draftID: id(900),
            workspaceID: workspaceID,
            scope: resolvedScope,
            purpose: .myDayPlanning,
            codec: MyDayPlanningDraftCodecV1.release(),
            baseCanonicalRevision: baseRevision,
            draftRevision: draftRevision,
            payloadData: MyDayPlanningDraftCodecV1.encode(payload),
            stageIDs: stageIDs,
            resumeAnchor: .init(sectionID: "my-day-planning"),
            state: state,
            lastDurableMutationID: lastDurableMutationID,
            lastReceiptSHA256: lastReceiptSHA256,
            updatedAt: updatedAt,
            mutationID: mutation
        )
    }
}

final class V23MyDayPlanningDraftContractTests: XCTestCase {
    func testEditingPayloadRoundTripsCanonicallyAndBindsExplicitInputs() throws {
        let payload = try V23MyDayDraftFixtures.editingPayload()
        let bytes = try MyDayPlanningDraftCodecV1.encode(payload)

        XCTAssertEqual(try MyDayPlanningDraftCodecV1.decode(bytes), payload)
        XCTAssertEqual(try MyDayPlanningDraftCodecV1.encode(payload), bytes)
        XCTAssertLessThanOrEqual(bytes.count, MyDayPlanningDraftCodecV1.maximumPayloadBytes)

        let checkpoint = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: V23MyDayDraftFixtures.key(),
            baseRevision: 0,
            draftRevision: 1,
            state: .active,
            mutation: V23MyDayDraftFixtures.mutation(920)
        )
        XCTAssertEqual(
            try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint),
            payload
        )

        XCTAssertThrowsError(try MyDayPlanningConfirmedContextV1(
            key: V23MyDayDraftFixtures.key(),
            recordedBy: V23MyDayDraftFixtures.actor(),
            keyWasExplicitlyConfirmed: false,
            recordedByWasExplicitlySelectedOrCaptured: true
        ))
        XCTAssertThrowsError(try MyDayPlanningConfirmedContextV1(
            key: V23MyDayDraftFixtures.key(),
            recordedBy: V23MyDayDraftFixtures.actor(20, responsibility: .performedBy),
            keyWasExplicitlyConfirmed: true,
            recordedByWasExplicitlySelectedOrCaptured: true
        ))
    }

    func testEditingDiscardRecoveryKeepsPayloadAndRequiresExplicitReview() throws {
        let payload = try V23MyDayDraftFixtures.editingPayload()
        let key = try V23MyDayDraftFixtures.key()
        let pending = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: key,
            baseRevision: 0,
            draftRevision: 2,
            state: .discardPending,
            mutation: V23MyDayDraftFixtures.mutation(921)
        )
        let recovery = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: key,
            baseRevision: 0,
            draftRevision: 3,
            state: .recoveryRequired,
            mutation: V23MyDayDraftFixtures.mutation(922),
            updatedAt: V23MyDayDraftFixtures.now.addingTimeInterval(1)
        )

        XCTAssertEqual(recovery.payloadData, pending.payloadData)
        XCTAssertNoThrow(try recovery.validateSuccessor(
            of: pending,
            expectedDraftRevision: pending.draftRevision,
            expectedBaseRevision: pending.baseCanonicalRevision
        ))
        XCTAssertEqual(
            try MyDayPlanningDraftCodecV1.validateCheckpointPayload(recovery),
            payload
        )
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.reconstructCommit(from: recovery)) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidTransition)
        }
    }

    func testReleasedDefinitionAndSinglePurposeAuthorityAreExactAndClosed() throws {
        XCTAssertEqual(
            FieldDraftCanonicalCodecV1.sha256(
                Data(MyDayPlanningDraftCodecV1.grammarDescriptor.utf8)
            ),
            MyDayPlanningDraftCodecV1.releaseSHA256
        )
        let release = try MyDayPlanningDraftCodecV1.release()
        let definition = try MyDayPlanningDraftCodecV1.definition()
        XCTAssertEqual(release.codecID, "assetrounds.my-day-planning.v1")
        XCTAssertEqual(release.codecVersion, 1)
        XCTAssertEqual(definition.purpose, .myDayPlanning)
        XCTAssertEqual(definition.maximumPayloadBytes, 1_048_576)
        XCTAssertEqual(definition.maximumStageItems, 0)
        XCTAssertEqual(definition.targetCommandKind, .applyMyDay)
        XCTAssertEqual(definition.retention, .retireAfterCommit)
        XCTAssertEqual(definition.attachmentKinds, [])
        XCTAssertEqual(definition.privacyClass, .workspacePrivate)

        let authority = try MyDayPlanningDraftPurposeAuthorityV1()
        XCTAssertEqual(try authority.require(.myDayPlanning, codec: release), definition)
        XCTAssertThrowsError(try DraftPurposeRegistryV1([definition])) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .unknownPurpose)
        }
        for purpose in DraftPurposeV1.allCases where purpose != .myDayPlanning {
            XCTAssertThrowsError(try authority.require(purpose, codec: release)) { error in
                XCTAssertEqual(error as? FieldDraftFailureV1, .unknownPurpose)
            }
        }
        let wrongVersion = try DraftPayloadCodecReleaseV1(
            codecID: release.codecID,
            codecVersion: release.codecVersion + 1,
            releaseSHA256: release.releaseSHA256
        )
        XCTAssertThrowsError(try authority.require(.myDayPlanning, codec: wrongVersion)) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .unknownCodec)
        }
        let wrongDigest = try DraftPayloadCodecReleaseV1(
            codecID: release.codecID,
            codecVersion: release.codecVersion,
            releaseSHA256: String(repeating: "b", count: 64)
        )
        XCTAssertThrowsError(try authority.require(.myDayPlanning, codec: wrongDigest)) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .unknownCodec)
        }
    }

    func testCodecRejectsUnknownNoncanonicalOversizeAndMalformedPreparedBytes() throws {
        let editing = try V23MyDayDraftFixtures.editingPayload()
        let encoded = try MyDayPlanningDraftCodecV1.encode(editing)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["futureField"] = true
        let unknown = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(unknown))

        object.removeValue(forKey: "futureField")
        let noncanonical = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(noncanonical))
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(
            Data(repeating: 0x20, count: MyDayPlanningDraftCodecV1.maximumPayloadBytes + 1)
        ))

        let command = try V23MyDayDraftFixtures.saveCommand()
        let attempt = try V23MyDayDraftFixtures.attempt(command: command)
        var preparedObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt))
        ) as? [String: Any])
        preparedObject["contentPromotedSagaMutationID"] = preparedObject["preparedSagaMutationID"]
        let duplicateMutation = try JSONSerialization.data(
            withJSONObject: preparedObject,
            options: [.sortedKeys]
        )
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(duplicateMutation))

        preparedObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt))
        ) as? [String: Any])
        preparedObject["contentPromotedSagaID"] = preparedObject["preparedSagaID"]
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(
            JSONSerialization.data(withJSONObject: preparedObject, options: [.sortedKeys])
        ))

        preparedObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt))
        ) as? [String: Any])
        preparedObject["commitReceiptID"] = preparedObject["fieldDraftPlanID"]
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(
            JSONSerialization.data(withJSONObject: preparedObject, options: [.sortedKeys])
        ))

        preparedObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt))
        ) as? [String: Any])
        let preparedMilliseconds = try XCTUnwrap(
            preparedObject["preparedSagaUpdatedAt"] as? NSNumber
        ).doubleValue
        preparedObject["contentPromotedSagaUpdatedAt"] = preparedMilliseconds - 1_000
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(
            JSONSerialization.data(withJSONObject: preparedObject, options: [.sortedKeys])
        ))

        preparedObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt))
        ) as? [String: Any])
        preparedObject["preparedSagaUpdatedAt"] = preparedMilliseconds + 0.5
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.decode(
            JSONSerialization.data(withJSONObject: preparedObject, options: [.sortedKeys])
        ))
    }

    func testSavePreparedCheckpointReconstructsIdenticalPlanAndFiveSagas() throws {
        let command = try V23MyDayDraftFixtures.saveCommand()
        let attempt = try V23MyDayDraftFixtures.attempt(command: command)
        let payload = try MyDayPlanningDraftPayloadV1(prepared: attempt)
        let checkpoint = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: V23MyDayDraftFixtures.key(),
            baseRevision: 1,
            draftRevision: 2,
            state: .committing,
            mutation: V23MyDayDraftFixtures.mutation(930)
        )

        let first = try MyDayPlanningDraftCodecV1.reconstructCommit(from: checkpoint)
        let second = try MyDayPlanningDraftCodecV1.reconstructCommit(from: checkpoint)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.command, command)
        XCTAssertEqual(first.plan.payloadSHA256, checkpoint.payloadSHA256)
        XCTAssertEqual(first.plan.expectedTargetRevision, 1)
        XCTAssertEqual(first.plan.targetCommandKind, .applyMyDay)
        XCTAssertEqual(first.plan.mutationID, command.mutationID)
        XCTAssertEqual(first.plan.stageDigests, [])
        XCTAssertEqual(first.rowMutationIDs.reservationByStageID, [:])
        XCTAssertEqual(first.rowMutationIDs.terminalBundleMutationID, attempt.terminalBundleMutationID)
        XCTAssertEqual(first.sagas.map(\.state), [
            .prepared,
            .contentPromotedUnbound,
            .targetCommitted,
            .draftRetirePending,
            .draftRetired
        ])
        XCTAssertEqual(first.sagas.map(\.revision), [1, 2, 3, 4, 5])
        XCTAssertEqual(first.retired.mutationID, attempt.terminalBundleMutationID)
        let firstPlanBytes = try FieldDraftCanonicalCodecV1.encode(first.plan)
        let secondPlanBytes = try FieldDraftCanonicalCodecV1.encode(second.plan)
        let firstSagaBytes = try first.sagas.map { try FieldDraftCanonicalCodecV1.encode($0) }
        let secondSagaBytes = try second.sagas.map { try FieldDraftCanonicalCodecV1.encode($0) }
        XCTAssertEqual(firstPlanBytes, secondPlanBytes)
        XCTAssertEqual(firstSagaBytes, secondSagaBytes)

        let topLevel = try XCTUnwrap(JSONSerialization.jsonObject(
            with: checkpoint.payloadData
        ) as? [String: Any])
        XCTAssertEqual(Set(topLevel.keys), Set([
            "schemaVersion", "phase", "command", "fieldDraftPlanID",
            "preparedSagaID", "contentPromotedSagaID", "targetCommittedSagaID",
            "draftRetirePendingSagaID", "draftRetiredSagaID",
            "preparedSagaMutationID", "contentPromotedSagaMutationID",
            "targetCommittedSagaMutationID", "draftRetirePendingSagaMutationID",
            "terminalBundleMutationID", "commitReceiptID", "preparedSagaUpdatedAt",
            "contentPromotedSagaUpdatedAt", "targetCommittedSagaUpdatedAt",
            "draftRetirePendingSagaUpdatedAt", "draftRetiredSagaUpdatedAt",
            "terminalCheckpointUpdatedAt"
        ]))
        XCTAssertNil(topLevel["payloadSHA256"])
        XCTAssertNil(topLevel["planSHA256"])
        XCTAssertNil(topLevel["sagaSHA256"])
        XCTAssertNil(topLevel["expectedRevision"])
    }

    func testCarryoverReconstructionMapsOnlyTargetPlanAndReceiptOutputs() throws {
        let command = try V23MyDayDraftFixtures.carryoverCommand()
        let attempt = try V23MyDayDraftFixtures.attempt(command: command, seed: 200)
        let payload = try MyDayPlanningDraftPayloadV1(prepared: attempt)
        let checkpoint = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: V23MyDayDraftFixtures.key("2026-09-11"),
            baseRevision: 0,
            draftRevision: 3,
            state: .committing,
            mutation: V23MyDayDraftFixtures.mutation(940)
        )
        let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: checkpoint)
        let expected: [String]
        switch command {
        case .carryover(_, let source, let target, _):
            expected = try [
                WorkspaceEntityIdentityV1(kind: .myDayPlan, id: target.planID).stableKey,
                WorkspaceEntityIdentityV1(
                    kind: .myDayCarryoverReceipt,
                    id: command.mutationID.rawValue
                ).stableKey
            ].sorted()
            let sourceOutputKey = try WorkspaceEntityIdentityV1(
                kind: .myDayPlan,
                id: source.planID
            ).stableKey
            XCTAssertFalse(reconstruction.plan.outputKeys.contains(sourceOutputKey))
        case .save:
            XCTFail("Expected carryover command")
            return
        }
        XCTAssertEqual(reconstruction.plan.expectedTargetRevision, 0)
        XCTAssertEqual(reconstruction.plan.outputKeys, expected)
    }

    func testCheckpointBindingRejectsStagesWrongScopeBaseAndLaterRevisionReconstruction() throws {
        let command = try V23MyDayDraftFixtures.saveCommand()
        let attempt = try V23MyDayDraftFixtures.attempt(command: command, seed: 300)
        let payload = try MyDayPlanningDraftPayloadV1(prepared: attempt)
        let key = try V23MyDayDraftFixtures.key()

        let staged = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: key,
            baseRevision: 1,
            draftRevision: 2,
            state: .committing,
            mutation: V23MyDayDraftFixtures.mutation(950),
            stageIDs: [V23MyDayDraftFixtures.id(951)]
        )
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(staged))

        let wrongBase = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: key,
            baseRevision: 0,
            draftRevision: 2,
            state: .committing,
            mutation: V23MyDayDraftFixtures.mutation(952)
        )
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(wrongBase))

        let wrongScope = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: key,
            baseRevision: 1,
            draftRevision: 2,
            state: .committing,
            mutation: V23MyDayDraftFixtures.mutation(954),
            scope: .init(scopeKind: "MY_DAY_PLANNING", stableComponentIDs: ["wrong-key"])
        )
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(wrongScope))

        let laterRecovery = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: key,
            baseRevision: 1,
            draftRevision: 3,
            state: .recoveryRequired,
            mutation: V23MyDayDraftFixtures.mutation(953),
            updatedAt: V23MyDayDraftFixtures.now.addingTimeInterval(10)
        )
        XCTAssertEqual(
            try MyDayPlanningDraftCodecV1.validateCheckpointPayload(laterRecovery),
            payload
        )
        XCTAssertThrowsError(
            try MyDayPlanningDraftCodecV1.reconstructCommit(from: laterRecovery)
        ) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidTransition)
        }

        let committed = try V23MyDayDraftFixtures.checkpoint(
            payload: payload,
            key: key,
            baseRevision: 1,
            draftRevision: 3,
            state: .committed,
            mutation: attempt.terminalBundleMutationID,
            updatedAt: attempt.terminalCheckpointUpdatedAt,
            lastDurableMutationID: attempt.terminalBundleMutationID,
            lastReceiptSHA256: String(repeating: "c", count: 64)
        )
        XCTAssertEqual(
            try MyDayPlanningDraftCodecV1.validateCheckpointPayload(committed),
            payload
        )
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.reconstructCommit(from: committed))
    }
}


/// Shared actual My Day values for reviewed-command, writer and receipt tests.
/// Production persistence tests seed only the recorder before writer admission.
struct ReviewedResolutionTestFixtureV1 {
    let workspaceID: WorkspaceID
    let key: MyDayKeyV1
    let actor: ActorSnapshotV1
    let initial: FieldDraftCheckpointV1
    let conflicted: FieldDraftCheckpointV1
    let target: MyDayPlanV1
    let now: Date

    init(workspaceID: WorkspaceID = .init(rawValue: UUID()),
         now: Date = Date(timeIntervalSince1970: 1_789_084_800)) throws {
        self.workspaceID = workspaceID; self.now = now
        let key = try MyDayKeyV1(workspaceID: workspaceID, civilDate: .init("2026-09-10"),
                        ianaTimeZoneIdentifier: "America/New_York")
        self.key = key
        let reference = try LocalActorReferenceV1(actorReferenceID: UUID(),
            workspaceID: workspaceID, displayName: "Reviewed plan recorder")
        let actor = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, actor: reference,
            responsibility: .recordedBy, displayNameAtTime: reference.displayName, capturedAt: now)
        self.actor = actor
        let context = try MyDayPlanningConfirmedContextV1(key: key, recordedBy: actor,
            keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        let draft = try MyDayPlanDraftV1(key: key, items: [], eligibleReferences: [])
        let payload = try MyDayPlanningDraftPayloadV1(editing: context,
            intent: .plan(draft: draft, predecessor: nil))
        let draftID = UUID()
        func checkpoint(_ revision: UInt64, _ state: FieldDraftStateV1) throws -> FieldDraftCheckpointV1 {
            try .init(draftID: draftID, workspaceID: workspaceID,
                scope: MyDayPlanningDraftCodecV1.scope(for: key), purpose: .myDayPlanning,
                codec: MyDayPlanningDraftCodecV1.release(), baseCanonicalRevision: 0,
                draftRevision: revision, payloadData: MyDayPlanningDraftCodecV1.encode(payload),
                stageIDs: [], resumeAnchor: .init(sectionID: "my-day-planning"),
                state: state, updatedAt: now, mutationID: .init(rawValue: UUID()))
        }
        initial = try checkpoint(1, .active)
        conflicted = try checkpoint(2, .conflicted)
        target = try .init(planID: UUID(), key: key, items: [], revision: 1,
            mutationID: .init(rawValue: UUID()), authoredBy: actor, authoredAt: now)
    }

    func ordinary(_ checkpoint: FieldDraftCheckpointV1) throws -> FieldDraftMutationV1 {
        try .init(workspaceID: workspaceID, expectedRevision: checkpoint.draftRevision - 1,
            expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
            mutationID: checkpoint.mutationID,
            postImage: checkpoint.draftRevision == 1 ? .createCheckpoint(checkpoint) : .reviseCheckpoint(checkpoint))
    }

    func resolution(target: MyDayPlanV1?, workspaceRevision: UInt64,
                    mutationID: MutationIDV1? = nil) throws -> FieldDraftMutationV1 {
        let context = try MyDayPlanningConfirmedContextV1(key: key, recordedBy: actor,
            keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        let draft = try MyDayPlanDraftV1(key: key, items: [], eligibleReferences: [])
        let payload = try MyDayPlanningDraftPayloadV1(editing: context,
            intent: .plan(draft: draft, predecessor: target))
        let successor = try FieldDraftCheckpointV1(draftID: conflicted.draftID,
            workspaceID: workspaceID, scope: conflicted.scope, purpose: conflicted.purpose,
            codec: conflicted.codec, baseCanonicalRevision: target?.revision ?? 0,
            draftRevision: 3, payloadData: MyDayPlanningDraftCodecV1.encode(payload),
            stageIDs: conflicted.stageIDs, resumeAnchor: conflicted.resumeAnchor,
            state: .active, updatedAt: now,
            mutationID: mutationID ?? MutationIDV1(rawValue: UUID()))
        let basis: ReviewedMyDayTargetBasisV1
        if let target {
            basis = .existing(identity: try .init(kind: .myDayPlan, id: target.planID),
                key: key, revision: target.revision, canonicalSHA256: target.planSHA256)
        } else {
            basis = .absent(key: key, expectedWorkspaceRevision: workspaceRevision)
        }
        let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
            expectedCheckpoint: conflicted, reviewedTargetBasis: basis, successorCheckpoint: successor)
        return try .init(workspaceID: workspaceID, expectedRevision: conflicted.draftRevision,
            expectedBaseCanonicalRevision: conflicted.baseCanonicalRevision,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
    }

    func expected(_ mutation: FieldDraftMutationV1, workspaceRevision: UInt64,
                  generationID: UUID = UUID(), writerInstanceID: UUID = UUID()) throws -> WorkspaceExpectedRevisionV1 {
        try .init(workspaceID: workspaceID, generationID: generationID,
            writerInstanceID: writerInstanceID, workspaceRevision: workspaceRevision,
            entityRevisions: mutation.concurrencyIdentities.map {
                .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
            })
    }
}

extension V23MyDayPlanningDraftContractTests {
    func testEditingConflictCodecPreservesPayloadBeforeExplicitReviewedResolution() throws {
        let fixture = try ReviewedResolutionTestFixtureV1()
        XCTAssertEqual(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(fixture.conflicted),
                       try MyDayPlanningDraftCodecV1.validateCheckpointPayload(fixture.initial))
        XCTAssertEqual(fixture.conflicted.payloadData, fixture.initial.payloadData)
        try fixture.conflicted.validateSuccessor(of: fixture.initial,
            expectedDraftRevision: 1, expectedBaseRevision: 0)
        let mutation = try fixture.resolution(target: fixture.target, workspaceRevision: 3)
        guard case let .resolveConflict(resolution) = mutation.postImage else { return XCTFail("Wrong command") }
        XCTAssertEqual(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(resolution.successorCheckpoint).phase, .editing)
        XCTAssertThrowsError(try resolution.successorCheckpoint.validateSuccessor(of: fixture.conflicted,
            expectedDraftRevision: 2, expectedBaseRevision: 0))
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.reconstructCommit(from: fixture.conflicted))
    }
}


extension ReviewedResolutionTestFixtureV1 {
    static func preparedConflictResolution() throws -> (checkpoint: FieldDraftCheckpointV1, mutation: FieldDraftMutationV1) {
        let command = try V23MyDayDraftFixtures.saveCommand()
        guard case let .save(_, predecessor) = command, let predecessor else {
            throw FieldDraftFailureV1.invalidValue
        }
        let attempt = try V23MyDayDraftFixtures.attempt(command: command)
        let checkpoint = try V23MyDayDraftFixtures.checkpoint(
            payload: .init(prepared: attempt), key: predecessor.key, baseRevision: 1,
            draftRevision: 2, state: .conflicted, mutation: V23MyDayDraftFixtures.mutation(978))
        let context = try MyDayPlanningConfirmedContextV1(key: predecessor.key,
            recordedBy: predecessor.authoredBy, keyWasExplicitlyConfirmed: true,
            recordedByWasExplicitlySelectedOrCaptured: true)
        let payload = try MyDayPlanningDraftPayloadV1(editing: context, intent: .plan(
            draft: .init(key: predecessor.key, items: [], eligibleReferences: []), predecessor: predecessor))
        let successor = try V23MyDayDraftFixtures.checkpoint(payload: payload, key: predecessor.key,
            baseRevision: 1, draftRevision: 3, state: .active,
            mutation: V23MyDayDraftFixtures.mutation(979))
        let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
            expectedCheckpoint: checkpoint, reviewedTargetBasis: .existing(
                identity: .init(kind: .myDayPlan, id: predecessor.planID), key: predecessor.key,
                revision: predecessor.revision, canonicalSHA256: predecessor.planSHA256),
            successorCheckpoint: successor)
        return (checkpoint, try .init(workspaceID: checkpoint.workspaceID,
            expectedRevision: checkpoint.draftRevision, expectedBaseCanonicalRevision: 1,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution)))
    }
}

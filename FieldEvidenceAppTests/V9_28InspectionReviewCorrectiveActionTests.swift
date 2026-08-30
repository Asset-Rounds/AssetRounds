import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private struct C14CorpusReviewEdge: Codable {
    let from: String
    let to: String
    let requiresExactSuccessorSubject: Bool
}

private struct C14CorpusActionEdge: Codable {
    let from: String
    let to: String
}

private struct C14CorpusFlags: Codable {
    let native: Bool
    let hosted: Bool
    let adoption: Bool
    let acceptance: Bool
    let release: Bool
}

private struct C14Corpus: Codable {
    let cardID: String
    let ordinal: Int
    let phase: String
    let reviewStates: [String]
    let correctiveActionStates: [String]
    let declaredReviewTransitions: [C14CorpusReviewEdge]
    let declaredCorrectiveActionTransitions: [C14CorpusActionEdge]
    let boundaryRefs: [String]
    let coverage: [String]
    let evidenceIDs: [String]
    let persistentModelCount: Int
    let recordsSchemaVersion: Int
    let provisionalFlags: C14CorpusFlags
}

@MainActor
final class V9_28InspectionReviewCorrectiveActionTests: XCTestCase {
    func testV23P03C14GoldenReviewRequestsResolutionAndCorrectiveClosure() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture()

        XCTAssertEqual(
            fixture.transitions.map(\.toState),
            [.fieldComplete, .readyForReview, .changesRequested, .readyForReview,
             .accepted, .finalized, .amended]
        )
        for index in fixture.transitions.indices {
            try fixture.transitions[index].validate()
            if index > 0 {
                try fixture.transitions[index].validateSuccessor(of: fixture.transitions[index - 1])
            }
        }
        try fixture.supersedingTransition.validateSuccessor(of: fixture.transitions.last!)
        XCTAssertEqual(fixture.supersedingTransition.toState, .superseded)
        XCTAssertEqual(
            fixture.supersedingTransition.successorReviewID,
            C14InspectionReviewTestSupportV1.id(140_072)
        )

        try fixture.changeRequest.validate()
        try fixture.resolvedChangeRequest.validateSuccessor(of: fixture.changeRequest)
        XCTAssertEqual(fixture.changeRequest.state, .open)
        XCTAssertEqual(fixture.resolvedChangeRequest.state, .resolved)
        XCTAssertEqual(fixture.resolvedChangeRequest.resolution?.kind, .fulfilled)
        XCTAssertFalse(fixture.resolvedChangeRequest.resolution?.evidence.isEmpty ?? true)

        let reviewProjection = try InspectionReviewProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, reviewID: fixture.reviewID,
            transitions: fixture.transitions,
            dispositions: [fixture.changesRequestedDisposition, fixture.acceptedDisposition],
            changeRequests: [fixture.changeRequest, fixture.resolvedChangeRequest]
        )
        XCTAssertEqual(reviewProjection.state, .amended)
        XCTAssertEqual(reviewProjection.revision, 7)
        XCTAssertTrue(reviewProjection.openChangeRequests.isEmpty)
        XCTAssertEqual(reviewProjection.headTransitionID, fixture.transitions.last?.transitionID)

        for index in fixture.actions.indices {
            try fixture.actions[index].validate()
            if index > 0 {
                try fixture.actions[index].validateSuccessor(
                    of: fixture.actions[index - 1], policy: fixture.policy
                )
            }
        }
        let actionProjection = try CorrectiveActionProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, actionID: fixture.actionID, events: fixture.actions,
            policies: [fixture.policy], now: C14InspectionReviewTestSupportV1.fixedDate
        )
        XCTAssertEqual(actionProjection.state, .superseded)
        XCTAssertEqual(actionProjection.revision, 6)
        XCTAssertEqual(actionProjection.headEventID, fixture.actions.last?.eventID)
        XCTAssertEqual(actionProjection.dueStatus, .notDue)
        XCTAssertEqual(fixture.actions[3].closureEvidence.count, 2)
        XCTAssertEqual(fixture.actions[3].verifier?.responsibility, .verifiedBy)
        XCTAssertEqual(fixture.actions[4].reopenTrigger, .failedVerifiedRecheck)
    }

    func testV23P03C14ReviewAndCorrectiveActionTransitionMatricesAreClosed() throws {
        let ordinaryReviewEdges: Set<String> = [
            "DRAFT|FIELD_COMPLETE", "FIELD_COMPLETE|READY_FOR_REVIEW",
            "READY_FOR_REVIEW|CHANGES_REQUESTED", "CHANGES_REQUESTED|READY_FOR_REVIEW",
            "READY_FOR_REVIEW|ACCEPTED", "ACCEPTED|FINALIZED", "FINALIZED|AMENDED"
        ]
        for from in InspectionReviewStateV1.allCases {
            for to in InspectionReviewStateV1.allCases {
                let key = "\(from.rawValue)|\(to.rawValue)"
                XCTAssertEqual(
                    InspectionReviewTransitionTableV1.permits(from: from, to: to),
                    ordinaryReviewEdges.contains(key),
                    "unexpected review transition \(key)"
                )
                let successorAllowed = to == .superseded && from != .superseded
                XCTAssertEqual(
                    InspectionReviewTransitionTableV1.permits(
                        from: from, to: to, hasExactSuccessorSubject: true
                    ),
                    ordinaryReviewEdges.contains(key) || successorAllowed,
                    "unexpected successor review transition \(key)"
                )
            }
        }

        let ordinaryActionEdges: Set<String> = [
            "OPEN|IN_PROGRESS", "OPEN|AWAITING_VERIFICATION",
            "IN_PROGRESS|AWAITING_VERIFICATION", "AWAITING_VERIFICATION|IN_PROGRESS",
            "AWAITING_VERIFICATION|CLOSED", "CLOSED|REOPENED",
            "REOPENED|IN_PROGRESS", "REOPENED|AWAITING_VERIFICATION"
        ]
        for from in CorrectiveActionStateV1.allCases {
            for to in CorrectiveActionStateV1.allCases {
                let key = "\(from.rawValue)|\(to.rawValue)"
                let expected = ordinaryActionEdges.contains(key)
                    || (to == .superseded && from != .superseded)
                XCTAssertEqual(
                    CorrectiveActionTransitionTableV1.permits(from: from, to: to),
                    expected,
                    "unexpected corrective-action transition \(key)"
                )
            }
        }
    }

    func testV23P03C14DueGraceNoDueAndDSTGapOverlapAreDeterministic() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 141_000)
        let due = try XCTUnwrap(fixture.due.dueAt)
        let grace = try XCTUnwrap(fixture.due.graceEndsAt)
        XCTAssertEqual(
            try CorrectiveActionDueCalculatorV1.status(fixture.due, at: fixture.due.openedAt),
            .notDue
        )
        XCTAssertEqual(
            try CorrectiveActionDueCalculatorV1.status(fixture.due, at: due), .notDue
        )
        XCTAssertEqual(
            try CorrectiveActionDueCalculatorV1.status(fixture.due, at: grace), .dueWithinGrace
        )
        XCTAssertEqual(
            try CorrectiveActionDueCalculatorV1.status(
                fixture.due, at: grace.addingTimeInterval(0.001)
            ),
            .overdue
        )
        XCTAssertEqual(
            try CorrectiveActionDueCalculatorV1.status(fixture.noDue, at: fixture.noDue.openedAt),
            .noDueDate
        )
        try fixture.noDueClosedAction.validateSuccessor(
            of: fixture.noDueOpenAction, policy: fixture.noDuePolicy
        )
        XCTAssertEqual(fixture.noDueClosedAction.state, .closed)
        XCTAssertNil(fixture.noDueClosedAction.verifier)

        let dstRule = try CorrectiveActionPriorityRuleV1(
            priority: .high,
            dueRule: try CorrectiveActionDueRuleV1(
                kind: .calendarDaysAtLocalTime, amount: 1, localHour: 2, localMinute: 30
            ),
            graceSeconds: 60
        )
        let dstPolicy = try CorrectiveActionPolicyV1(
            releaseID: C14InspectionReviewTestSupportV1.id(150_000),
            policyID: C14InspectionReviewTestSupportV1.id(150_001),
            workspaceID: fixture.workspaceID, priorityRules: [dstRule],
            assignmentRule: .optional, closureEvidenceRequirements: [],
            verifierRule: .notRequired, reopenTriggers: [],
            effectiveAt: C14InspectionReviewTestSupportV1.fixedDate,
            mutationID: try C14InspectionReviewTestSupportV1.mutation(150_002)
        )
        let iso = ISO8601DateFormatter()
        let springOpened = try XCTUnwrap(iso.date(from: "2025-03-08T12:00:00Z"))
        let spring = try CorrectiveActionDueCalculatorV1.calculate(
            policy: dstPolicy, priority: .high, openedAt: springOpened,
            timeZoneIdentifier: "America/New_York"
        )
        XCTAssertNotNil(spring.dueAt)
        let springDue = try XCTUnwrap(spring.dueAt)
        let springGrace = try XCTUnwrap(spring.graceEndsAt)
        XCTAssertEqual(springGrace.timeIntervalSince(springDue), 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(spring.resolvedUTCOffsetSeconds), -14_400)
        XCTAssertThrowsError(
            try CorrectiveActionDueCalculatorV1.calculate(
                policy: dstPolicy, priority: .high, openedAt: springOpened,
                timeZoneIdentifier: nil
            )
        )

        let overlapRule = try CorrectiveActionPriorityRuleV1(
            priority: .high,
            dueRule: try CorrectiveActionDueRuleV1(
                kind: .calendarDaysAtLocalTime, amount: 1, localHour: 1, localMinute: 30
            ),
            graceSeconds: 60
        )
        let overlapPolicy = try CorrectiveActionPolicyV1(
            releaseID: C14InspectionReviewTestSupportV1.id(150_010),
            policyID: C14InspectionReviewTestSupportV1.id(150_011),
            workspaceID: fixture.workspaceID, priorityRules: [overlapRule],
            assignmentRule: .optional, closureEvidenceRequirements: [],
            verifierRule: .notRequired, reopenTriggers: [],
            effectiveAt: C14InspectionReviewTestSupportV1.fixedDate,
            mutationID: try C14InspectionReviewTestSupportV1.mutation(150_012)
        )
        let overlapOpened = try XCTUnwrap(iso.date(from: "2025-11-01T12:00:00Z"))
        let overlap = try CorrectiveActionDueCalculatorV1.calculate(
            policy: overlapPolicy, priority: .high, openedAt: overlapOpened,
            timeZoneIdentifier: "America/New_York"
        )
        let overlapAgain = try CorrectiveActionDueCalculatorV1.calculate(
            policy: overlapPolicy, priority: .high, openedAt: overlapOpened,
            timeZoneIdentifier: "America/New_York"
        )
        XCTAssertEqual(overlap, overlapAgain)
        XCTAssertTrue([-18_000, -14_400].contains(overlap.resolvedUTCOffsetSeconds ?? 0))
    }

    func testV23P03C14AlternateSelfVerificationAndInterruptionRecoveryRemainExplicit() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 141_500)
        let selfPolicy = try C14InspectionReviewTestSupportV1.makePolicy(
            seed: 151_000, workspaceID: fixture.workspaceID,
            assignmentRule: .optional, verifierRule: .selfVerificationPermitted,
            noDue: true
        )
        let selfDue = try CorrectiveActionDueCalculatorV1.calculate(
            policy: selfPolicy, priority: .low,
            openedAt: C14InspectionReviewTestSupportV1.fixedDate.addingTimeInterval(101),
            timeZoneIdentifier: nil
        )
        let selfItem = try C14InspectionReviewTestSupportV1.changeItem(
            kind: .criterion, itemID: "c14-self-verification"
        )
        let selfOpen = try C14InspectionReviewTestSupportV1.makeAction(
            seed: 151_010, actionID: C14InspectionReviewTestSupportV1.id(151_011),
            workspaceID: fixture.workspaceID, source: selfItem, policy: selfPolicy,
            priority: .low, state: .open, recorder: fixture.recorder,
            assignee: nil, due: selfDue, revision: 1
        )
        let selfVerifier = try C14InspectionReviewTestSupportV1.actorSnapshot(
            seed: 151_013, workspaceID: fixture.workspaceID, actor: fixture.actor,
            responsibility: .verifiedBy
        )
        let selfClosed = try C14InspectionReviewTestSupportV1.makeAction(
            seed: 151_012, actionID: selfOpen.actionID,
            workspaceID: fixture.workspaceID, source: selfItem, policy: selfPolicy,
            priority: .low, state: .closed, recorder: fixture.recorder,
            assignee: nil, due: selfDue, verifier: selfVerifier,
            predecessor: selfOpen.eventID, revision: 2
        )
        try selfClosed.validateSuccessor(of: selfOpen, policy: selfPolicy)
        XCTAssertEqual(selfPolicy.verifierRule, .selfVerificationPermitted)
        XCTAssertEqual(selfClosed.verifier?.actor.actorReferenceID, fixture.recorder.actor.actorReferenceID)

        let interruptedPrefix = Array(fixture.transitions.prefix(2))
        let prefixProjection = try InspectionReviewProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID, reviewID: fixture.reviewID,
            transitions: interruptedPrefix, changeRequests: []
        )
        XCTAssertEqual(prefixProjection.state, .readyForReview)
        XCTAssertEqual(prefixProjection.revision, 2)
        XCTAssertEqual(prefixProjection.headTransitionID, interruptedPrefix.last?.transitionID)
        let recovered = try InspectionReviewCanonicalCodecV1.decode(
            InspectionReviewTransitionV1.self,
            from: InspectionReviewCanonicalCodecV1.encode(interruptedPrefix[1])
        )
        XCTAssertEqual(recovered, interruptedPrefix[1])

        var unknownVersion = try InspectionReviewCanonicalCodecV1.encode(interruptedPrefix[0])
        let versionOne = Data(#""schemaVersion":1"#.utf8)
        let versionTwo = Data(#""schemaVersion":2"#.utf8)
        if let range = unknownVersion.range(of: versionOne) {
            unknownVersion.replaceSubrange(range, with: versionTwo)
        }
        XCTAssertThrowsError(
            try InspectionReviewCanonicalCodecV1.decode(
                InspectionReviewTransitionV1.self, from: unknownVersion
            )
        )
    }

    func testV23P03C14HostileStaleMissingEvidenceAndUnauthorizedInputsFailClosed() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 142_000)
        XCTAssertThrowsError(
            try C14InspectionReviewTestSupportV1.makeTransition(
                seed: 142_100, reviewID: fixture.reviewID,
                workspaceID: fixture.workspaceID, subject: fixture.subject,
                from: .draft, to: .accepted, actor: fixture.reviewer,
                revision: 1, mutationSeed: 142_101
            )
        ) { error in
            XCTAssertEqual(error as? InspectionReviewFailureV1, .digestMismatch)
        }

        let missingClosure = try C14InspectionReviewTestSupportV1.makeAction(
            seed: 142_110, actionID: fixture.actionID, workspaceID: fixture.workspaceID,
            source: fixture.changeRequest.item, policy: fixture.policy, priority: .urgent,
            state: .closed, recorder: fixture.recorder, assignee: fixture.assignee,
            due: fixture.due, verifier: fixture.verifier,
            predecessor: fixture.actions[2].eventID, revision: 4
        )
        XCTAssertThrowsError(
            try missingClosure.validateSuccessor(of: fixture.actions[2], policy: fixture.policy)
        ) { error in
            XCTAssertEqual(error as? InspectionReviewFailureV1, .missingEvidence)
        }

        let stale = try C14InspectionReviewTestSupportV1.makeAction(
            seed: 142_120, actionID: fixture.actionID, workspaceID: fixture.workspaceID,
            source: fixture.changeRequest.item, policy: fixture.policy, priority: .urgent,
            state: .inProgress, recorder: fixture.recorder, assignee: fixture.assignee,
            due: fixture.due, predecessor: fixture.actions[0].eventID, revision: 3
        )
        XCTAssertThrowsError(
            try stale.validateSuccessor(of: fixture.actions[0], policy: fixture.policy)
        ) { error in
            XCTAssertEqual(error as? InspectionReviewFailureV1, .staleRevision)
        }

        let sameActorVerifier = try C14InspectionReviewTestSupportV1.makeAction(
            seed: 142_130, actionID: fixture.actionID, workspaceID: fixture.workspaceID,
            source: fixture.changeRequest.item, policy: fixture.policy, priority: .urgent,
            state: .closed, recorder: fixture.recorder, assignee: fixture.assignee,
            due: fixture.due, closureEvidence: fixture.closureEvidence,
            verifier: try C14InspectionReviewTestSupportV1.actorSnapshot(
                seed: 142_131, workspaceID: fixture.workspaceID, actor: fixture.actor,
                responsibility: .verifiedBy
            ), predecessor: fixture.actions[2].eventID, revision: 4
        )
        XCTAssertThrowsError(
            try sameActorVerifier.validateSuccessor(of: fixture.actions[2], policy: fixture.policy)
        ) { error in
            XCTAssertEqual(error as? InspectionReviewFailureV1, .verifierRequired)
        }

        let reboundSubject = try fixture.subject.rebound(to: fixture.otherWorkspaceID)
        XCTAssertEqual(reboundSubject.workspaceID, fixture.otherWorkspaceID)
        let reboundTransition = try fixture.transitions[0].rebound(to: fixture.otherWorkspaceID)
        XCTAssertEqual(reboundTransition.workspaceID, fixture.otherWorkspaceID)
        XCTAssertEqual(reboundTransition.actor.workspaceID, fixture.otherWorkspaceID)

        var tampered = try InspectionReviewCanonicalCodecV1.encode(fixture.transitions[0])
        tampered.append(0x20)
        XCTAssertThrowsError(
            try InspectionReviewCanonicalCodecV1.decode(
                InspectionReviewTransitionV1.self, from: tampered
            )
        ) { error in
            XCTAssertEqual(error as? InspectionReviewFailureV1, .digestMismatch)
        }
    }

    func testV23P03C14MutationConcurrencyRowsBackupAndSchemaBoundaries() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 143_000)
        let first = fixture.transitions[0]
        let second = fixture.transitions[1]
        let firstBundle = try InspectionReviewAtomicBundleV1(transition: first)
        let appendTransition = try InspectionReviewMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: first.mutationID, postImage: .applyReviewBundle(firstBundle)
        )
        let secondBundle = try InspectionReviewAtomicBundleV1(transition: second)
        let appendSuccessor = try InspectionReviewMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 1,
            mutationID: second.mutationID, postImage: .applyReviewBundle(secondBundle)
        )
        let reviewBundle = try InspectionReviewAtomicBundleV1(
            transition: fixture.transitions[2],
            disposition: fixture.changesRequestedDisposition,
            changeRequests: [fixture.changeRequest]
        )
        let applyReviewBundle = try InspectionReviewMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 2,
            mutationID: fixture.transitions[2].mutationID,
            postImage: .applyReviewBundle(reviewBundle)
        )
        let supersedePolicy = try InspectionReviewMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 1,
            mutationID: fixture.supersedingPolicy.mutationID,
            postImage: .supersedeCorrectivePolicy(fixture.supersedingPolicy)
        )
        let appendActionSuccessor = try InspectionReviewMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 1,
            mutationID: fixture.actions[1].mutationID,
            postImage: .appendCorrectiveEventSuccessor(fixture.actions[1])
        )
        for mutation in [appendTransition, appendSuccessor, applyReviewBundle, supersedePolicy, appendActionSuccessor] {
            try mutation.validate()
            let digest = try mutation.canonicalSHA256()
            XCTAssertEqual(digest.count, 64)
        }
        let appendIdentity = try appendTransition.affectedIdentity
        let appendConcurrency = try appendTransition.concurrencyIdentity
        let successorConcurrency = try appendSuccessor.concurrencyIdentity
        let reviewAffected = try applyReviewBundle.affectedIdentities
        let reviewConcurrency = try applyReviewBundle.concurrencyIdentities
        let requestIdentity = reviewAffected.first { $0.kind == .changeRequest }
        let policyIdentity = try supersedePolicy.affectedIdentity
        let actionIdentity = try appendActionSuccessor.affectedIdentity
        XCTAssertEqual(appendIdentity.kind, .inspectionReviewTransition)
        XCTAssertEqual(appendConcurrency.id, first.transitionID)
        XCTAssertEqual(successorConcurrency.id, first.transitionID)
        XCTAssertEqual(reviewAffected.count, 3)
        XCTAssertEqual(reviewConcurrency.count, 3)
        let reviewPredecessor = try applyReviewBundle.predecessorIdentity
        XCTAssertEqual(reviewPredecessor?.id, second.transitionID)
        XCTAssertEqual(requestIdentity?.kind, .changeRequest)
        XCTAssertEqual(requestIdentity?.id, fixture.changeRequest.requestRevisionID)
        XCTAssertEqual(policyIdentity.kind, .correctiveActionPolicy)
        XCTAssertEqual(actionIdentity.kind, .correctiveActionEvent)

        let transitionRow = try InspectionReviewTransitionRow(first)
        let dispositionRow = try ReviewDispositionRow(fixture.changesRequestedDisposition)
        let requestRow = try ChangeRequestRow(fixture.resolvedChangeRequest)
        let policyRow = try CorrectiveActionPolicyRow(fixture.policy)
        let eventRow = try CorrectiveActionEventRow(fixture.actions[3])
        XCTAssertEqual(try transitionRow.value(), first)
        XCTAssertEqual(try dispositionRow.value(), fixture.changesRequestedDisposition)
        XCTAssertEqual(try requestRow.value(), fixture.resolvedChangeRequest)
        XCTAssertEqual(try policyRow.value(), fixture.policy)
        XCTAssertEqual(try eventRow.value(), fixture.actions[3])

        try assertCanonicalRoundTrip(first)
        try assertCanonicalRoundTrip(fixture.resolvedChangeRequest)
        try assertCanonicalRoundTrip(fixture.policy)
        try assertCanonicalRoundTrip(fixture.actions[3])

        XCTAssertEqual(PersistentSchemaV14.versionIdentifier, Schema.Version(14, 0, 0))
        XCTAssertEqual(PersistentSchemaV14.models.count, 53)
        XCTAssertEqual(PersistentSchemaMigrationPlanV13.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV13.stages.count, 1)
        for rowType in [
            ObjectIdentifier(InspectionReviewTransitionRow.self),
            ObjectIdentifier(ReviewDispositionRow.self),
            ObjectIdentifier(ChangeRequestRow.self),
            ObjectIdentifier(CorrectiveActionPolicyRow.self),
            ObjectIdentifier(CorrectiveActionEventRow.self)
        ] {
            XCTAssertTrue(PersistentSchemaV14.models.contains { ObjectIdentifier($0) == rowType })
        }
        try V14InspectionReviewImportBoundaryV1.validate(persistent: 14, records: 13)
        XCTAssertThrowsError(
            try V14InspectionReviewImportBoundaryV1.validate(persistent: 13, records: 13)
        )
        XCTAssertEqual(V14BackupInspectionReviewRecordV1.Kind.allCases.count, 5)
        XCTAssertEqual(V13EvidenceAssuranceImportBoundaryV1.recordsSchemaVersion, 12)
    }

    func testV23P03C14CorpusAndCheckRunnerBoundaryAreTypedAndProvisional() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 144_000)
        let candidate = try CheckRunnerInspectionReviewCandidateV1(subject: fixture.subject)
        XCTAssertEqual(candidate.initialState, .draft)
        XCTAssertEqual(candidate.subject, fixture.subject)
        XCTAssertEqual(fixture.subject.kind, .completedActivitySnapshot)

        let data = try Data(contentsOf: C14InspectionReviewTestSupportV1.corpusURL())
        let corpus = try JSONDecoder().decode(C14Corpus.self, from: data)
        XCTAssertEqual(corpus.cardID, "V23-P03-C14")
        XCTAssertEqual(corpus.ordinal, 51)
        XCTAssertEqual(corpus.phase, "P03")
        XCTAssertEqual(corpus.reviewStates, InspectionReviewStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(
            corpus.correctiveActionStates,
            CorrectiveActionStateV1.allCases.map(\.rawValue)
        )
        XCTAssertEqual(corpus.persistentModelCount, 53)
        XCTAssertEqual(corpus.recordsSchemaVersion, 13)
        for boundary in ["V23-P03-C13", "V23-P03-C38", "V23-P03-C40", "V23-P03-C41"] {
            XCTAssertTrue(corpus.boundaryRefs.contains(boundary))
        }
        for marker in ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"] {
            XCTAssertTrue(corpus.coverage.contains(marker))
        }
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertFalse(corpus.provisionalFlags.native)
        XCTAssertFalse(corpus.provisionalFlags.hosted)
        XCTAssertFalse(corpus.provisionalFlags.adoption)
        XCTAssertFalse(corpus.provisionalFlags.acceptance)
        XCTAssertFalse(corpus.provisionalFlags.release)

        XCTAssertTrue(corpus.declaredReviewTransitions.contains {
            $0.from == "DRAFT" && $0.to == "FIELD_COMPLETE"
                && !$0.requiresExactSuccessorSubject
        })
        XCTAssertTrue(corpus.declaredReviewTransitions.contains {
            $0.from == "AMENDED" && $0.to == "SUPERSEDED"
                && $0.requiresExactSuccessorSubject
        })
        XCTAssertTrue(corpus.declaredCorrectiveActionTransitions.contains {
            $0.from == "AWAITING_VERIFICATION" && $0.to == "CLOSED"
        })
        XCTAssertTrue(corpus.declaredCorrectiveActionTransitions.contains {
            $0.from == "CLOSED" && $0.to == "REOPENED"
        })
    }

    private func assertCanonicalRoundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try InspectionReviewCanonicalCodecV1.encode(value)
        let decoded = try InspectionReviewCanonicalCodecV1.decode(T.self, from: data)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try InspectionReviewCanonicalCodecV1.encode(decoded), data)
    }
}

private final class C48PortableReviewV928C14ReconciliationTests: XCTestCase {
    func testC48AcceptedResponseUsesExistingC14WriterAndOriginRemainsUnverified() {
        XCTAssertTrue(C48PortableExchangePersistentLifecycleBoundaryV2.acceptedResponseUsesExistingC14Writer)
        XCTAssertEqual(C48PortableExchangeSyncBoundaryV2.canonicalAcceptedResponseOwner, "C14")
        XCTAssertTrue(C48PortableReviewOriginMetadataBoundaryV1.originIsSelfAssertedAndUnverified)
        XCTAssertTrue(C48PortableReviewOriginMetadataBoundaryV1.identityVerificationIsForbidden)
    }
}
private final class C49WorkResourceCorrectiveSubjectBoundaryTests: XCTestCase {
    func testCorrectiveWorkIsExplicitSupportedSubject() { XCTAssertTrue(WorkResourceSubjectKindV1.allCases.contains(.correctiveWork)) }

    @MainActor
    func testC49EffectBeforeReceiptRetriesThroughRealWriterToOneRowAndReceipt() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 149_000)
        let action = fixture.actions[3]
        let schema = Schema(PersistentSchemaV37.models, version: PersistentSchemaV37.versionIdentifier)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C49RealWriterRecovery", schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        context.insert(try ActorSnapshotRow(fixture.recorder))
        context.insert(try CorrectiveActionEventRow(action))
        try context.save()

        let replica = try WorkspaceReplicaIdentityV1(
            workspaceID: fixture.workspaceID,
            replicaID: ReplicaID(rawValue: C49WriterRecoverySupportV1.id(1))
        )
        let generationID = C49WriterRecoverySupportV1.id(2)
        let writerID = C49WriterRecoverySupportV1.id(3)
        let journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: replica,
            generationID: generationID,
            failureInjection: MutationJournalFailureInjectionV1(failOnceAt: .afterEffectBeforeReceipt)
        )
        let writer = try WorkspaceWriterV1(
            identity: replica,
            generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerID),
            clock: C49WriterRecoverySupportV1.Clock(),
            idSource: C49WriterRecoverySupportV1.IDSource(value: writerID),
            fileAuthority: C49WriterRecoverySupportV1.FileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: journal
        )
        let mutationID = try MutationIDV1(rawValue: C49WriterRecoverySupportV1.id(4))
        let subject = try WorkResourceSubjectV1(
            workspaceID: fixture.workspaceID,
            kind: .correctiveWork,
            subjectID: action.eventID.uuidString,
            subjectRevision: action.revision,
            subjectSHA256: action.eventSHA256
        )
        let entry = try WorkResourceEntryV1(
            entryID: C49WriterRecoverySupportV1.id(5),
            workspaceID: fixture.workspaceID,
            subject: subject,
            actor: fixture.recorder,
            duration: ManualDurationV1(minutes: 20),
            recordedAt: C49WriterRecoverySupportV1.Clock().now(),
            expectedRevision: 0,
            revision: 1,
            mutationID: mutationID
        )
        let mutation = try WorkResourceMutationV1(
            workspaceID: fixture.workspaceID,
            mutationID: mutationID,
            postImage: entry
        )
        let current = try writer.currentRevision()
        let concurrency = try mutation.concurrencyIdentity
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: [WorkspaceEntityRevisionV1(identity: concurrency, revision: 0)]
        )

        XCTAssertThrowsError(try writer.commitWorkResource(mutation, expectedRevision: expected)) {
            XCTAssertEqual($0 as? MutationJournalFailureV1, .injected(.afterEffectBeforeReceipt))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).isEmpty)
        XCTAssertNil(try journal.receipt(mutationID: mutationID))

        let recovered = try writer.commitWorkResource(mutation, expectedRevision: expected)
        let rows = try context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows[0].value(), entry)
        XCTAssertEqual(recovered.mutationReceipt.mutationID, mutationID)
        XCTAssertEqual(try writer.commitWorkResource(mutation, expectedRevision: expected), recovered)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 1)
    }
}

private enum C49WriterRecoverySupportV1 {
    static func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0x49, value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    struct Clock: ApplicationClock {
        func now() -> Date { Date(timeIntervalSince1970: 1_800_000_049) }
    }

    struct IDSource: ApplicationIDSource {
        let value: UUID
        func makeID() -> UUID { value }
    }

    struct FileAuthority: ApplicationFileAuthorityV1 {
        func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
            "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
        }
    }
}

import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_14FindingLifecycleTests: XCTestCase {
    private let instant = "2026-08-26T20:14:00Z"
    private let policySHA = String(repeating: "c", count: 64)

    func testV9_14G01CompleteLifecycleReopenAndHumanOperationalDispositionMatrix() throws {
        let fixture = try loadFixture()
        XCTAssertTrue(fixture.testOnly)
        XCTAssertEqual(fixture.lifecycleStates, FindingStateV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(fixture.dispositionStates, OperationalDispositionStateV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(fixture.severityBinding.fields, ["severityID", "severityScaleReleaseID", "severityScaleSHA256"])
        XCTAssertEqual(fixture.canonicalAggregate.codec, "FindingLifecycleCanonicalEvidenceCodecV1")
        XCTAssertTrue(fixture.canonicalAggregate.exactByteReconciliation)

        var lifecycle = try FindingLifecycleV1(findingID: "finding.001")
        let path: [(FindingStateV1, Bool)] = [
            (.correctiveWorkInProgress, false), (.awaitingVerifiedRecheck, false),
            (.verifiedResolved, true), (.closed, false), (.reopened, false),
            (.correctiveWorkInProgress, false), (.awaitingVerifiedRecheck, false),
            (.verifiedResolved, true), (.closed, false),
        ]
        var resolutionRechecks: [VerifiedRecheckV1] = []
        for (index, step) in path.enumerated() {
            let verifiedRecheck = step.1
                ? try recheck(
                    id: "recheck.resolution.\(index)", findingRevision: lifecycle.currentRevision,
                    outcome: .passed, priorRecheckID: resolutionRechecks.last?.recheckID,
                    expectedRevision: resolutionRechecks.count
                )
                : nil
            if let verifiedRecheck { resolutionRechecks.append(verifiedRecheck) }
            lifecycle = try lifecycle.appending(transition(
                index: index, from: lifecycle.currentState, to: step.0,
                verifiedRecheck: verifiedRecheck, expectedRevision: lifecycle.currentRevision
            ))
        }
        XCTAssertEqual(lifecycle.currentState, .closed)
        XCTAssertEqual(lifecycle.currentRevision, path.count)
        let decodedLifecycle = try roundTrip(lifecycle)
        XCTAssertEqual(decodedLifecycle, lifecycle)
        try lifecycle.validateVerifiedResolutionLineage(resolutionRechecks)
        assertFailure(.recheckRequired) { try decodedLifecycle.validateVerifiedResolutionLineage([]) }

        let passedRecheck = try recheck(
            id: "recheck.release", findingRevision: lifecycle.currentRevision - 1, outcome: .passed,
            priorRecheckID: resolutionRechecks.last?.recheckID, expectedRevision: resolutionRechecks.count
        )
        let release = try ReleaseToServiceV1(
            releaseID: "release.001", subjectID: "asset.001", findingID: lifecycle.findingID,
            findingRevision: lifecycle.currentRevision, verifiedRecheck: passedRecheck,
            mutationID: "mutation.release.001", authorizingActorID: "actor.authorizer",
            authority: "Release authority", reason: "Explicit human release", effectiveAt: instant
        )
        var predecessor: String?
        let dispositions = try OperationalDispositionStateV1.allCases.enumerated().map { index, state in
            let event = try OperationalDispositionEventV1(
                eventID: "disposition.\(index)", subjectID: "asset.001", findingID: lifecycle.findingID,
                findingRevision: lifecycle.currentRevision, evidenceRevisionIDs: ["evidence.001"],
                expectedDispositionRevision: index, resultingDispositionRevision: index + 1,
                mutationID: "mutation.disposition.\(index)", state: state, actorID: "actor.inspector",
                authority: "Authorized inspector", reason: "Human recorded disposition", effectiveAt: instant,
                supersedesEventID: predecessor,
                releaseToServiceID: state == .returnedToServiceRecorded ? release.releaseID : nil
            )
            predecessor = event.eventID
            return event
        }
        XCTAssertEqual(dispositions.map(\.state), OperationalDispositionStateV1.allCases)
        XCTAssertTrue(dispositions.allSatisfy { !$0.actorID.isEmpty && !$0.authority.isEmpty && !$0.reason.isEmpty })
        try OperationalDispositionLedgerV1.validate(dispositions)
        try OperationalDispositionLedgerV1.validateReturnedToService(
            event: try XCTUnwrap(dispositions.first { $0.state == .returnedToServiceRecorded }),
            release: release,
            verifiedRecheck: passedRecheck
        )
        let aggregate = try FindingLifecycleCanonicalEvidenceV1(
            finding: try finding(revision: lifecycle.currentRevision),
            lifecycle: lifecycle,
            correctiveWorkLinks: [try correctiveLink(
                id: "work-link.aggregate", findingRevision: 1, workRevision: 4, expectedRevision: 0
            )],
            verifiedRechecks: resolutionRechecks + [passedRecheck],
            releasesToService: [release],
            operationalDispositionEvents: dispositions
        )
        let aggregateBytes = try FindingLifecycleCanonicalEvidenceCodecV1.encode(aggregate)
        let reconciled = try FindingLifecycleCanonicalEvidenceCodecV1.decode(aggregateBytes)
        XCTAssertEqual(reconciled, aggregate)
        XCTAssertEqual(try FindingLifecycleCanonicalEvidenceCodecV1.encode(reconciled), aggregateBytes)
    }

    func testV9_14A01InvalidTransitionMissingTargetAndUnpermittedResolutionFailClosed() throws {
        assertFailure(.invalidTransition) {
            _ = try transition(index: 0, from: .open, to: .closed, expectedRevision: 0)
        }
        assertFailure(.recheckRequired) {
            _ = try transition(index: 0, from: .awaitingVerifiedRecheck, to: .verifiedResolved, expectedRevision: 0)
        }
        for (index, outcome) in [VerifiedRecheckOutcomeV1.failed, .inconclusive].enumerated() {
            assertFailure(.recheckRequired) {
                _ = try transition(
                    index: index + 1, from: .awaitingVerifiedRecheck, to: .verifiedResolved,
                    verifiedRecheck: try recheck(
                        id: "recheck.rejected-transition.\(index)", findingRevision: 0, outcome: outcome
                    ),
                    expectedRevision: 0
                )
            }
        }
        assertFailure(.missingTarget) {
            _ = try recheck(id: "recheck.missing", findingRevision: 2, outcome: .passed, evidence: [])
        }

        let failed = try recheck(id: "recheck.failed", findingRevision: 2, outcome: .failed)
        let inconclusive = try recheck(id: "recheck.inconclusive", findingRevision: 2, outcome: .inconclusive)
        XCTAssertFalse(failed.permitsVerifiedResolution)
        XCTAssertFalse(inconclusive.permitsVerifiedResolution)
        for rejected in [failed, inconclusive] {
            assertFailure(.releaseNotEligible) {
                _ = try ReleaseToServiceV1(
                    releaseID: "release.rejected", subjectID: "asset.001", findingID: "finding.001",
                    findingRevision: 3, verifiedRecheck: rejected, mutationID: "mutation.release.rejected",
                    authorizingActorID: "actor.authorizer", authority: "Release authority",
                    reason: "Explicit human decision", effectiveAt: instant
                )
            }
        }
        assertFailure(.invalidValue) {
            _ = try disposition(
                id: "disposition.repair-closed", state: .returnedToServiceRecorded,
                releaseToServiceID: nil
            )
        }
        let canonical = try canonicalEvidenceFixture()
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(canonical) { root in
                var lifecycle = root["lifecycle"] as! [String: Any]
                var transitions = lifecycle["transitions"] as! [[String: Any]]
                transitions[2]["verifiedRecheckID"] = "recheck.fabricated"
                lifecycle["transitions"] = transitions
                root["lifecycle"] = lifecycle
            })
        }
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(canonical) { root in
                var releases = root["releasesToService"] as! [[String: Any]]
                releases[0]["verifiedRecheckID"] = "recheck.absent"
                root["releasesToService"] = releases
            })
        }
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(canonical) { root in
                var events = root["operationalDispositionEvents"] as! [[String: Any]]
                events[0]["releaseToServiceID"] = "release.absent"
                root["operationalDispositionEvents"] = events
            })
        }
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(canonical) { root in
                var finding = root["finding"] as! [String: Any]
                finding["revision"] = 2
                root["finding"] = finding
            })
        }
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(canonical) { root in
                var finding = root["finding"] as! [String: Any]
                var subject = finding["subject"] as! [String: Any]
                subject["subjectID"] = "asset.other"
                finding["subject"] = subject
                root["finding"] = finding
            })
        }
    }

    func testV9_14H01StaleConcurrentCorrectiveRecheckAndHistoryMutationFailClosed() throws {
        var lifecycle = try FindingLifecycleV1(findingID: "finding.001")
        let accepted = try transition(index: 0, from: .open, to: .correctiveWorkInProgress, expectedRevision: 0)
        lifecycle = try lifecycle.appending(accepted)
        let sameMutation = try lifecycle.appending(accepted)
        XCTAssertEqual(sameMutation, lifecycle)

        assertFailure(.staleRevision) {
            _ = try lifecycle.appending(transition(
                index: 1, from: .correctiveWorkInProgress, to: .awaitingVerifiedRecheck, expectedRevision: 0
            ))
        }
        let workA = try correctiveLink(id: "work-link.a", findingRevision: 1, workRevision: 4, expectedRevision: 0)
        let workB = try correctiveLink(id: "work-link.b", findingRevision: 0, workRevision: 3, expectedRevision: 0)
        XCTAssertNotEqual(workA.findingRevision, workB.findingRevision)
        XCTAssertNotEqual(workA.workRevision, workB.workRevision)
        let removedWork = try correctiveLink(
            id: "work-link.removed", findingRevision: 2, workRevision: 5, expectedRevision: 1,
            action: .removed, supersedesLinkEventID: workA.linkID
        )
        try CorrectiveWorkLinkLedgerV1.validate([workA, removedWork])
        assertFailure(.historyRewrite) { try CorrectiveWorkLinkLedgerV1.validate([workA, workA]) }
        assertFailure(.invalidValue) {
            _ = try correctiveLink(id: "work-link.stale", findingRevision: 1, workRevision: 4, expectedRevision: 1)
        }

        let currentRecheck = try recheck(id: "recheck.current", findingRevision: 2, outcome: .passed)
        let staleRecheck = try recheck(id: "recheck.stale", findingRevision: 1, outcome: .passed)
        XCTAssertNotEqual(currentRecheck.findingRevision, staleRecheck.findingRevision)
        assertFailure(.historyRewrite) {
            try VerifiedRecheckLineageV1.validate([currentRecheck, staleRecheck])
        }
        assertFailure(.releaseNotEligible) {
            _ = try ReleaseToServiceV1(
                releaseID: "release.cross-finding", subjectID: "asset.001", findingID: "finding.other",
                findingRevision: 3, verifiedRecheck: currentRecheck, mutationID: "mutation.release.cross",
                authorizingActorID: "actor.authorizer", authority: "Release authority", reason: "No inferred release",
                effectiveAt: instant
            )
        }

        let rewritten = try transition(
            index: 2, findingID: "finding.001", from: .correctiveWorkInProgress,
            to: .awaitingVerifiedRecheck, expectedRevision: 2
        )
        assertFailure(.historyRewrite) {
            _ = try FindingLifecycleV1(findingID: "finding.001", transitions: [accepted, rewritten])
        }
        let canonical = try canonicalEvidenceFixture()
        let linked = try XCTUnwrap(canonical.correctiveWorkLinks.first)
        let removed = try correctiveLink(
            id: "work-link.aggregate.removed", findingRevision: 2,
            workRevision: linked.workRevision, expectedRevision: 1,
            action: .removed, supersedesLinkEventID: linked.linkID
        )
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceV1(
                finding: canonical.finding, lifecycle: canonical.lifecycle,
                correctiveWorkLinks: [linked, removed], verifiedRechecks: canonical.verifiedRechecks,
                releasesToService: canonical.releasesToService,
                operationalDispositionEvents: canonical.operationalDispositionEvents
            )
        }
    }

    func testV9_14I01EveryDormantRegistryPublicationBoundaryRecoversZeroOrCompleteExactBytes() throws {
        for boundary in FindingContractRegistryPublisherV1.Boundary.allCases {
            assertFailure(.publicationInterrupted) {
                _ = try FindingContractRegistryPublisherV1.publish { reached in
                    if reached == boundary { throw FindingContractFailureV1.publicationInterrupted }
                }
            }
        }
        XCTAssertNil(try FindingContractRegistryPublisherV1.recover(canonicalData: nil, receipt: nil))
        let publication = try FindingContractRegistryPublisherV1.publish()
        let bytes = try FindingContractRegistryCanonicalCodecV1.encode(publication.registry)
        XCTAssertEqual(try FindingContractRegistryPublisherV1.recover(canonicalData: bytes, receipt: publication.receipt), publication.registry)
        XCTAssertEqual(try FindingContractRegistryCanonicalCodecV1.encode(try XCTUnwrap(
            FindingContractRegistryPublisherV1.recover(canonicalData: bytes, receipt: publication.receipt)
        )), bytes)
        assertFailure(.publicationInterrupted) {
            _ = try FindingContractRegistryPublisherV1.recover(canonicalData: bytes, receipt: nil)
        }
        XCTAssertEqual(KernelFindingLifecycleV1.mode, "DECLARATION_ONLY")
        XCTAssertFalse(KernelFindingLifecycleV1.persistent)
        XCTAssertFalse(KernelFindingLifecycleV1.writerCommandRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.canonicalQueryRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.migrationRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.backupRestoreRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.cloneForkRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.importExportRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.journalReplayRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.searchRebuildReplayRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.deleteEraseRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.retentionRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.compatibilityWriteRequired)
        XCTAssertFalse(KernelFindingLifecycleV1.forwardFixRequired)
    }

    func testV9_14R01SnapshotFixtureLineageAndExplicitRelatedWorkSafeguardsReconcile() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schema, "V21P03C04FindingLifecycleCorpusV1")
        XCTAssertEqual(fixture.historicC03.packageSHA256, "7da926f2203d303b953b040cf80d2939eb56b962d75ecf045f792f6e34958141")
        XCTAssertEqual(fixture.historicC03.workflowSHA256, "33b5d769791b641bbea4e7ee954aa904cb7f7e70695d6f046a9002c63a1ac13e")
        XCTAssertEqual(fixture.relationshipDecisions, WorkRelationshipDecisionKindV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(fixture.negativeCases, fixture.negativeCases.sorted())
        let finding = try finding()
        XCTAssertEqual(finding.severity.severityID, "severity.fixture.observed")
        XCTAssertEqual(finding.severity.severityScaleReleaseID, fixture.severityBinding.scaleReleaseID)
        XCTAssertEqual(finding.severity.severityScaleSHA256, fixture.severityBinding.scaleSHA256)
        XCTAssertEqual(try roundTrip(finding).severity, finding.severity)

        let suggestion = try relatedSuggestion(sourceRevision: 1, candidateRevision: 1, policySHA: policySHA)
        XCTAssertTrue(suggestion.isCurrent(sourceRevision: 1, candidateRevision: 1, policySHA256: policySHA))
        let sameCandidate = try relatedSuggestion(sourceRevision: 1, candidateRevision: 1, policySHA: policySHA)
        XCTAssertEqual(sameCandidate.suggestionID, suggestion.suggestionID)
        let changedBasis = try relatedSuggestion(sourceRevision: 1, candidateRevision: 2, policySHA: policySHA)
        XCTAssertNotEqual(changedBasis.suggestionID, suggestion.suggestionID)
        XCTAssertFalse(suggestion.isCurrent(sourceRevision: 1, candidateRevision: 2, policySHA256: policySHA))
        let changedPolicy = try relatedSuggestion(
            sourceRevision: 1, candidateRevision: 1, policySHA: String(repeating: "e", count: 64)
        )
        XCTAssertNotEqual(changedPolicy.suggestionID, suggestion.suggestionID)
        try WorkRelationshipValidatorV1.validateSuggestions([suggestion, changedBasis, changedPolicy])

        let relationship = try relationship(id: "relationship.001", source: "work.001", target: "work.002")
        let confirm = try decision(id: "decision.confirm", suggestion: suggestion, revision: 0, kind: .confirm, relationshipID: relationship.relationshipID)
        let remove = try decision(id: "decision.remove", suggestion: suggestion, revision: 1, kind: .removeRelation, relationshipID: relationship.relationshipID)
        let suppressionSuggestion = try relatedSuggestion(source: "work.010", target: "work.011")
        let notRelated = try decision(id: "decision.not-related", suggestion: suppressionSuggestion, revision: 0, kind: .notRelated)
        let resuggestedChangedBasis = try relatedSuggestion(
            source: "work.010", target: "work.011", candidateRevision: 2
        )
        XCTAssertEqual([confirm.decision, notRelated.decision, remove.decision], [.confirm, .notRelated, .removeRelation])
        try WorkRelationshipDecisionLedgerV1.validate([confirm, remove, notRelated])
        XCTAssertNil(try WorkRelationshipDecisionLedgerV1.activeRelationshipID(
            for: suggestion, decisions: [confirm, remove]
        ))
        XCTAssertTrue(try WorkRelationshipDecisionLedgerV1.suppresses(
            suppressionSuggestion, decisions: [notRelated]
        ))
        XCTAssertFalse(try WorkRelationshipDecisionLedgerV1.suppresses(
            resuggestedChangedBasis, decisions: [notRelated]
        ))
        let removeBeforeConfirm = try decision(
            id: "decision.invalid-remove", suggestion: changedBasis, revision: 0,
            kind: .removeRelation, relationshipID: relationship.relationshipID
        )
        assertFailure(.invalidTransition) {
            try WorkRelationshipDecisionLedgerV1.validate([removeBeforeConfirm])
        }
        let relationshipAggregate = try FindingLifecycleCanonicalEvidenceV1(
            finding: finding, lifecycle: FindingLifecycleV1(findingID: "finding.001"),
            relatedWorkSuggestions: [suggestion], workRelationships: [relationship],
            workRelationshipDecisions: [confirm, remove]
        )
        assertFailure(.hashMismatch) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(relationshipAggregate) { root in
                var decisions = root["workRelationshipDecisions"] as! [[String: Any]]
                decisions[0]["sourceWorkRevision"] = 99
                root["workRelationshipDecisions"] = decisions
            })
        }
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(relationshipAggregate) { root in
                root["workRelationships"] = []
            })
        }
        assertFailure(.canonicalEvidenceIncomplete) {
            _ = try FindingLifecycleCanonicalEvidenceCodecV1.decode(try mutatedCanonicalBytes(relationshipAggregate) { root in
                var suggestions = root["relatedWorkSuggestions"] as! [[String: Any]]
                suggestions[0]["subjectID"] = "asset.other"
                root["relatedWorkSuggestions"] = suggestions
            })
        }
        XCTAssertEqual(try roundTrip(relationship), relationship)
        XCTAssertEqual(try roundTrip([confirm, notRelated, remove]), [confirm, notRelated, remove])

        XCTAssertThrowsError(try relatedSuggestion(source: "work.001", target: "work.001"))
        let reverse = try relationship(id: "relationship.reverse", source: "work.002", target: "work.001")
        assertFailure(.reverseRelationship) { try WorkRelationshipValidatorV1.validate([relationship, reverse]) }
        let edgeBC = try relationship(id: "relationship.bc", source: "work.002", target: "work.003")
        let edgeCA = try relationship(id: "relationship.ca", source: "work.003", target: "work.001")
        assertFailure(.relationshipCycle) { try WorkRelationshipValidatorV1.validate([relationship, edgeBC, edgeCA]) }

        let untouchedLifecycle = try FindingLifecycleV1(findingID: "finding.001")
        let untouchedFinding = finding
        XCTAssertEqual(untouchedLifecycle.currentState, .open)
        XCTAssertEqual(untouchedFinding.revision, 0)
        XCTAssertEqual(relationship.sourceWorkRevision, 1)
        XCTAssertEqual(relationship.targetWorkRevision, 1)
    }

    private func transition(
        index: Int, findingID: String = "finding.001", from: FindingStateV1, to: FindingStateV1,
        verifiedRecheck: VerifiedRecheckV1? = nil, expectedRevision: Int
    ) throws -> FindingTransitionV1 {
        if let verifiedRecheck {
            return try FindingTransitionV1(
                transitionID: "transition.\(index)", findingID: findingID,
                expectedFindingRevision: expectedRevision, resultingFindingRevision: expectedRevision + 1,
                mutationID: "mutation.transition.\(index)", fromState: from, toState: to,
                actorID: "actor.inspector", reason: "Explicit lifecycle step", effectiveAt: instant,
                verifiedRecheck: verifiedRecheck
            )
        }
        return try FindingTransitionV1(
            transitionID: "transition.\(index)", findingID: findingID,
            expectedFindingRevision: expectedRevision, resultingFindingRevision: expectedRevision + 1,
            mutationID: "mutation.transition.\(index)", fromState: from, toState: to,
            actorID: "actor.inspector", reason: "Explicit lifecycle step", effectiveAt: instant
        )
    }

    private func correctiveLink(
        id: String, findingRevision: Int, workRevision: Int, expectedRevision: Int,
        action: CorrectiveWorkLinkActionV1 = .linked, supersedesLinkEventID: String? = nil
    ) throws -> CorrectiveWorkLinkV1 {
        try CorrectiveWorkLinkV1(
            linkID: id, findingID: "finding.001", findingRevision: findingRevision,
            workID: "work.001", workRevision: workRevision, expectedLinkRevision: expectedRevision,
            resultingLinkRevision: expectedRevision + 1, mutationID: "mutation.\(id)", action: action,
            actorID: "actor.inspector", reason: "Explicit corrective link", effectiveAt: instant,
            supersedesLinkEventID: supersedesLinkEventID
        )
    }

    private func recheck(
        id: String, findingRevision: Int, outcome: VerifiedRecheckOutcomeV1,
        evidence: [String] = ["evidence.recheck.001"], priorRecheckID: String? = nil,
        expectedRevision: Int = 0
    ) throws -> VerifiedRecheckV1 {
        try VerifiedRecheckV1(
            recheckID: id, findingID: "finding.001", findingRevision: findingRevision,
            correctiveWorkID: "work.001", correctiveWorkRevision: 4,
            priorRecheckID: priorRecheckID, evidenceRevisionIDs: evidence,
            expectedRecheckRevision: expectedRevision, resultingRecheckRevision: expectedRevision + 1,
            mutationID: "mutation.\(id)", outcome: outcome,
            verifierActorID: "actor.verifier", verifierAuthority: "Authorized verifier",
            reason: "Observed recheck result", effectiveAt: instant
        )
    }

    private func relatedSuggestion(
        source: String = "work.001", target: String = "work.002", sourceRevision: Int = 1,
        candidateRevision: Int = 1, policySHA: String? = nil
    ) throws -> RelatedWorkSuggestionV1 {
        try RelatedWorkSuggestionV1(
            sourceWorkID: source, sourceWorkRevision: sourceRevision,
            candidateWorkID: target, candidateWorkRevision: candidateRevision,
            subjectID: "asset.001", categoryID: "category.condition",
            policySHA256: policySHA ?? self.policySHA, reason: "Same subject and category"
        )
    }

    private func relationship(id: String, source: String, target: String) throws -> WorkRelationshipV1 {
        try WorkRelationshipV1(
            relationshipID: id, sourceWorkID: source, sourceWorkRevision: 1,
            targetWorkID: target, targetWorkRevision: 1, kind: .duplicateOf, direction: .directed,
            reason: "Human confirmed relationship", actorID: "actor.inspector",
            mutationID: "mutation.\(id)", createdAt: instant
        )
    }

    private func decision(
        id: String, suggestion: RelatedWorkSuggestionV1, revision: Int,
        kind: WorkRelationshipDecisionKindV1, relationshipID: String? = nil
    ) throws -> WorkRelationshipDecisionV1 {
        try WorkRelationshipDecisionV1(
            decisionID: id, suggestion: suggestion, expectedDecisionRevision: revision,
            resultingDecisionRevision: revision + 1, decision: kind, relationshipID: relationshipID,
            actorID: "actor.inspector", reason: "Explicit human decision", mutationID: "mutation.\(id)",
            effectiveAt: instant
        )
    }

    private func finding(revision: Int = 0) throws -> FindingV1 {
        try FindingV1(
            findingID: "finding.001", revision: revision,
            severity: FindingSeverityBindingV1(
                severityID: "severity.fixture.observed",
                severityScaleReleaseID: "severity-scale.fixture.release.v1",
                severityScaleSHA256: String(repeating: "d", count: 64)
            ),
            categoryID: "category.condition",
            subject: FindingSubjectV1(subjectKindID: "asset", subjectID: "asset.001", subjectRevision: 2),
            source: FindingSourceV1(kind: .inspectionResponse, sourceID: "response.001", sourceRevision: 3,
                                    evidenceRevisionIDs: ["evidence.001"]),
            summary: "Observed damaged component"
        )
    }

    private func disposition(
        id: String,
        state: OperationalDispositionStateV1,
        releaseToServiceID: String?
    ) throws -> OperationalDispositionEventV1 {
        try OperationalDispositionEventV1(
            eventID: id, subjectID: "asset.001", findingID: "finding.001", findingRevision: 3,
            evidenceRevisionIDs: ["evidence.001"], expectedDispositionRevision: 0,
            resultingDispositionRevision: 1, mutationID: "mutation.\(id)", state: state,
            actorID: "actor.inspector", authority: "Authorized inspector",
            reason: "Human recorded disposition", effectiveAt: instant,
            releaseToServiceID: releaseToServiceID
        )
    }

    private func canonicalEvidenceFixture() throws -> FindingLifecycleCanonicalEvidenceV1 {
        var lifecycle = try FindingLifecycleV1(findingID: "finding.001")
        lifecycle = try lifecycle.appending(transition(
            index: 80, from: .open, to: .correctiveWorkInProgress, expectedRevision: 0
        ))
        lifecycle = try lifecycle.appending(transition(
            index: 81, from: .correctiveWorkInProgress, to: .awaitingVerifiedRecheck, expectedRevision: 1
        ))
        let verified = try recheck(id: "recheck.aggregate", findingRevision: 2, outcome: .passed)
        lifecycle = try lifecycle.appending(transition(
            index: 82, from: .awaitingVerifiedRecheck, to: .verifiedResolved,
            verifiedRecheck: verified, expectedRevision: 2
        ))
        let link = try correctiveLink(
            id: "work-link.aggregate.fixture", findingRevision: 1, workRevision: 4, expectedRevision: 0
        )
        let release = try ReleaseToServiceV1(
            releaseID: "release.aggregate", subjectID: "asset.001", findingID: "finding.001",
            findingRevision: 3, verifiedRecheck: verified, mutationID: "mutation.release.aggregate",
            authorizingActorID: "actor.authorizer", authority: "Release authority",
            reason: "Explicit human release", effectiveAt: instant
        )
        let returned = try disposition(
            id: "disposition.aggregate", state: .returnedToServiceRecorded,
            releaseToServiceID: release.releaseID
        )
        return try FindingLifecycleCanonicalEvidenceV1(
            finding: finding(revision: 3), lifecycle: lifecycle, correctiveWorkLinks: [link],
            verifiedRechecks: [verified], releasesToService: [release],
            operationalDispositionEvents: [returned]
        )
    }

    private func mutatedCanonicalBytes(
        _ evidence: FindingLifecycleCanonicalEvidenceV1,
        mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        let bytes = try FindingLifecycleCanonicalEvidenceCodecV1.encode(evidence)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        mutate(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try JSONDecoder().decode(T.self, from: encoder.encode(value))
    }

    private func assertFailure(
        _ expected: FindingContractFailureV1, file: StaticString = #filePath, line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, expected, file: file, line: line)
        }
    }

    private func loadFixture() throws -> FindingLifecycleFixture {
        let name = "V21P03C04FindingLifecycleCorpusV1"
        let url = Bundle(for: Self.self).url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures/V21/InspectionKernel"
        ) ?? Bundle(for: Self.self).url(forResource: name, withExtension: "json")
        return try JSONDecoder().decode(FindingLifecycleFixture.self, from: Data(contentsOf: try XCTUnwrap(url)))
    }
}

private struct FindingLifecycleFixture: Decodable {
    struct CanonicalAggregate: Decodable {
        let codec: String
        let exactByteReconciliation: Bool
    }
    struct HistoricC03: Decodable {
        let bindingSHA256: String
        let packageReleaseSHA256: String
        let packageSHA256: String
        let workflowSHA256: String
    }
    struct SeverityBinding: Decodable {
        let fields: [String]
        let scaleReleaseID: String
        let scaleSHA256: String
    }
    let schema: String
    let schemaVersion: Int
    let testOnly: Bool
    let lifecycleStates: [String]
    let dispositionStates: [String]
    let relationshipDecisions: [String]
    let negativeCases: [String]
    let historicC03: HistoricC03
    let severityBinding: SeverityBinding
    let canonicalAggregate: CanonicalAggregate
}

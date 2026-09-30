import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Intrinsic owner values and supplied-closure checks only. Constructed references
/// do not authenticate receipts, current heads or complete relationship membership.
@MainActor
final class V23FindingOwnerContractTests: XCTestCase {
    private let a = String(repeating: "a", count: 64)
    private let b = String(repeating: "b", count: 64)
    private let instant = "2026-09-22T12:00:00Z"
    private let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "CF480000-0000-4000-8000-%012d", slot))!
    }
    private var workspace: WorkspaceID { WorkspaceID(rawValue: id(1)) }
    private func mutation(_ slot: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(slot)) }
    private func actor(workspace: WorkspaceID? = nil, responsibility: ResponsibilityKindV1 = .recordedBy) throws -> ActorSnapshotV1 {
        let actual = workspace ?? self.workspace
        let actor = try LocalActorReferenceV1(actorReferenceID: id(10), workspaceID: actual, displayName: "Recorder")
        return try ActorSnapshotV1(snapshotID: id(11), workspaceID: actual, actor: actor,
            responsibility: responsibility, displayNameAtTime: "Recorder", capturedAt: Date(timeIntervalSince1970: 0))
    }
    private func finding(_ name: String = "finding.one", revision: Int = 0,
                         sourceKind: FindingSourceKindV1 = .humanObservation, summary: String = "Original finding") throws -> FindingV1 {
        try FindingV1(findingID: name, revision: revision,
            severity: FindingSeverityBindingV1(severityID: "medium", severityScaleReleaseID: "scale.one", severityScaleSHA256: a),
            categoryID: "leak", subject: FindingSubjectV1(subjectKindID: "asset", subjectID: "subject.one", subjectRevision: 0),
            source: FindingSourceV1(kind: sourceKind, sourceID: "observation.one", sourceRevision: 0), summary: summary)
    }
    private func evidence(_ fact: FindingV1? = nil, transitions: [FindingTransitionV1] = [],
                          links: [CorrectiveWorkLinkV1] = [], dispositions: [OperationalDispositionEventV1] = []) throws -> FindingLifecycleCanonicalEvidenceV1 {
        let finding = try fact ?? self.finding()
        let lifecycle = try FindingLifecycleV1(findingID: finding.findingID, transitions: transitions)
        return try FindingLifecycleCanonicalEvidenceV1(finding: finding, lifecycle: lifecycle,
            correctiveWorkLinks: links, operationalDispositionEvents: dispositions)
    }
    private func disposition(_ slot: Int = 1, findingID: String = "finding.one", reason: String = "Recorded restriction") throws -> OperationalDispositionEventV1 {
        try OperationalDispositionEventV1(eventID: "disposition.\(slot)", subjectID: "subject.one", findingID: findingID,
            findingRevision: 0, evidenceRevisionIDs: [], expectedDispositionRevision: slot - 1,
            resultingDispositionRevision: slot, mutationID: "disposition-mutation.\(slot)", state: .restrictedUseRecorded,
            actorID: "actor.one", authority: "Operator", reason: reason, effectiveAt: instant,
            supersedesEventID: slot == 1 ? nil : "disposition.\(slot - 1)")
    }
    private func record(facts: FindingOwnedFactsV1? = nil, previous: FindingOwnerRecordV1? = nil,
                        ownerSlot: Int = 30, mutationSlot: Int = 20, workspace: WorkspaceID? = nil,
                        origin: FindingOwnerOriginIdentityV1? = nil) throws -> FindingOwnerRecordV1 {
        let local = workspace ?? self.workspace
        let owned = try facts ?? FindingOwnedFactsV1(evidence: evidence())
        let origin = try origin ?? previous?.origin ?? FindingOwnerOriginIdentityV1(workspaceID: local,
            kind: .finding, ownerID: id(ownerSlot), creationMutationID: mutation(mutationSlot))
        let oldRevision = previous?.ownerRevision ?? 0
        guard oldRevision < UInt64.max else { throw FindingContractFailureV1.invalidValue }
        let revision = oldRevision + 1
        return try FindingOwnerRecordV1(workspaceID: local, kind: .finding, ownerID: id(ownerSlot),
            ownerRevision: revision, predecessor: previous?.reference, mutationID: mutation(mutationSlot),
            recordedBy: actor(workspace: local), recordedAt: Date(timeIntervalSince1970: Double(revision)),
            origin: origin, finding: owned)
    }
    private func accepted(_ slot: Int, workspace: WorkspaceID? = nil) throws -> FindingAcceptedMutationReferenceV1 {
        try FindingAcceptedMutationReferenceV1(workspaceID: workspace ?? self.workspace, generationID: id(2),
            mutationID: mutation(slot), envelopeSHA256: a, receiptSHA256: b)
    }
    private func direct(_ workID: String, ownerSlot: Int, workRevision: Int = 0,
                        ownerRevision: UInt64 = 7) throws -> FindingRelationshipEndpointReferenceV1 {
        let reference = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
            ownerID: id(ownerSlot), ownerRevision: ownerRevision, recordSHA256: a)
        let acceptance = try accepted(ownerSlot + 70)
        let owner = try FindingSelectedOwnerReferenceV1(original: reference, selected: reference,
            originalAcceptance: acceptance, selectedAcceptance: acceptance)
        return try FindingRelationshipEndpointReferenceV1(workID: workID, workRevision: workRevision, owner: .finding(owner))
    }
    private func relation(source: FindingRelationshipEndpointReferenceV1? = nil,
                          candidate: FindingRelationshipEndpointReferenceV1? = nil,
                          confirm: Bool = false, removed: Bool = false,
                          relationshipID: String = "relationship.one", decisionID: String = "decision.one",
                          direction: WorkRelationshipDirectionV1 = .directed) throws -> FindingOwnedRelationshipV1 {
        let source = try source ?? direct("finding.one", ownerSlot: 31)
        let candidate = try candidate ?? direct("finding.two", ownerSlot: 32)
        let suggestion = try RelatedWorkSuggestionV1(sourceWorkID: source.workID, sourceWorkRevision: source.workRevision,
            candidateWorkID: candidate.workID, candidateWorkRevision: candidate.workRevision,
            subjectID: "subject.one", categoryID: "leak", policySHA256: a, reason: "Possible duplicate")
        var relationship: WorkRelationshipV1?
        if confirm {
            relationship = try WorkRelationshipV1(relationshipID: relationshipID,
                sourceWorkID: source.workID, sourceWorkRevision: source.workRevision,
                targetWorkID: candidate.workID, targetWorkRevision: candidate.workRevision,
                kind: direction == .directed ? .duplicateOf : .relatedTo, direction: direction,
                reason: "Confirmed connection", actorID: "actor.one", mutationID: "relationship-mutation." + relationshipID,
                createdAt: instant)
        }
        let first = try WorkRelationshipDecisionV1(decisionID: decisionID, suggestion: suggestion,
            expectedDecisionRevision: 0, resultingDecisionRevision: 1, decision: confirm ? .confirm : .notRelated,
            relationshipID: relationship?.relationshipID, actorID: "actor.one",
            reason: confirm ? "Confirmed" : "Different cause", mutationID: "decision-mutation." + decisionID,
            effectiveAt: instant)
        var decisions = [first]
        if removed {
            decisions.append(try WorkRelationshipDecisionV1(decisionID: decisionID + ".removed", suggestion: suggestion,
                expectedDecisionRevision: 1, resultingDecisionRevision: 2, decision: .removeRelation,
                relationshipID: relationship?.relationshipID, actorID: "actor.one", reason: "Removed connection",
                mutationID: "decision-mutation." + decisionID + ".removed", effectiveAt: instant))
        }
        return try FindingOwnedRelationshipV1(suggestion: suggestion, source: source, candidate: candidate,
            relationship: relationship, decisions: decisions)
    }
    private func relationshipRecord(_ payload: FindingOwnedRelationshipV1? = nil,
                                    previous: FindingOwnerRecordV1? = nil, ownerSlot: Int = 40,
                                    mutationSlot: Int = 20) throws -> FindingOwnerRecordV1 {
        let origin = try previous?.origin ?? FindingOwnerOriginIdentityV1(workspaceID: workspace, kind: .relationship,
            ownerID: id(ownerSlot), creationMutationID: mutation(mutationSlot))
        let oldRevision = previous?.ownerRevision ?? 0
        guard oldRevision < UInt64.max else { throw FindingContractFailureV1.invalidValue }
        let revision = oldRevision + 1
        return try FindingOwnerRecordV1(workspaceID: workspace, kind: .relationship, ownerID: id(ownerSlot),
            ownerRevision: revision, predecessor: previous?.reference, mutationID: mutation(mutationSlot),
            recordedBy: actor(), recordedAt: Date(timeIntervalSince1970: Double(revision)), origin: origin,
            relationship: payload ?? relation())
    }
    private func correctiveEvent(actionSlot: Int = 50, sourceKind: ChangeRequestItemKindV1 = .criterion) throws -> CorrectiveActionEventV1 {
        let time = Date(timeIntervalSince1970: 0)
        let rule = try CorrectiveActionPriorityRuleV1(priority: .normal,
            dueRule: CorrectiveActionDueRuleV1(kind: .noDueDate))
        let policy = try CorrectiveActionPolicyV1(releaseID: id(actionSlot + 2), policyID: id(actionSlot + 3),
            workspaceID: workspace, priorityRules: [rule], assignmentRule: .optional,
            closureEvidenceRequirements: [], verifierRule: .notRequired, reopenTriggers: [],
            effectiveAt: time, mutationID: mutation(actionSlot + 4))
        let source: ChangeRequestItemReferenceV1
        if sourceKind == .finding {
            source = try finding().inspectionReviewItemReference()
        } else {
            source = try ChangeRequestItemReferenceV1(kind: sourceKind, itemID: "criterion.one", itemRevision: 0, itemSHA256: a)
        }
        let due = try CorrectiveActionDueCalculationV1(openedAt: time, timeZoneIdentifier: nil,
            dueAt: nil, graceEndsAt: nil, resolvedUTCOffsetSeconds: nil)
        return try CorrectiveActionEventV1(eventID: id(actionSlot + 1), actionID: id(actionSlot), workspaceID: workspace,
            source: source, policy: CorrectiveActionPolicyReferenceV1(policy), priority: .normal, state: .open,
            recorder: actor(), due: due, reason: "Corrective action", occurredAt: time, recordedAt: time,
            mutationID: mutation(actionSlot + 5))
    }
    private func support(_ event: CorrectiveActionEventV1, workID: String? = nil) throws -> FindingC14SupportReferenceV1 {
        let acceptance = try FindingAcceptedMutationReferenceV1(workspaceID: event.workspaceID, generationID: id(2),
            mutationID: event.mutationID, envelopeSHA256: a, receiptSHA256: b)
        let reference = try FindingCorrectiveEventReferenceV1(workspaceID: event.workspaceID, actionID: event.actionID,
            eventID: event.eventID, eventRevision: event.revision, eventSHA256: event.eventSHA256, acceptance: acceptance)
        let revision = try XCTUnwrap(Int(exactly: event.revision))
        return try FindingC14SupportReferenceV1(correctiveWorkID: workID ?? event.actionID.uuidString.lowercased(),
            correctiveWorkRevision: revision, original: reference, selected: reference)
    }
    private func c14Endpoint(_ event: CorrectiveActionEventV1) throws -> FindingRelationshipEndpointReferenceV1 {
        let reference = try support(event)
        return try FindingRelationshipEndpointReferenceV1(workID: reference.correctiveWorkID,
            workRevision: reference.correctiveWorkRevision, owner: .correctiveAction(reference))
    }
    private func workLink(_ workID: String, workRevision: Int = 1, removed: Bool = false) throws -> CorrectiveWorkLinkV1 {
        try CorrectiveWorkLinkV1(linkID: removed ? "link.removed" : "link.one", findingID: "finding.one", findingRevision: 0,
            workID: workID, workRevision: workRevision, expectedLinkRevision: removed ? 1 : 0,
            resultingLinkRevision: removed ? 2 : 1, mutationID: removed ? "link-mutation.removed" : "link-mutation.one",
            action: removed ? .removed : .linked, actorID: "actor.one", reason: "Explicit link", effectiveAt: instant,
            supersedesLinkEventID: removed ? "link.one" : nil)
    }
    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func object(_ value: FindingOwnerRecordV1) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: FindingOwnerCanonicalCodecV1.encode(value)) as? [String: Any])
    }
    private func roundTrip(_ value: FindingOwnerRecordV1) throws {
        let bytes = try FindingOwnerCanonicalCodecV1.encode(value)
        let decoded = try FindingOwnerCanonicalCodecV1.decode(bytes)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try FindingOwnerCanonicalCodecV1.encode(decoded), bytes)
    }
    private func rejected(_ value: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try FindingOwnerCanonicalCodecV1.decode(json(value)), file: file, line: line)
    }

    func testBothOwnerKindsRoundTripWithIndependentGoldenDigests() throws {
        let finding = try record()
        let relationship = try relationshipRecord()
        try roundTrip(finding)
        try roundTrip(relationship)
        XCTAssertEqual(finding.recordSHA256, "ca001bd64810565a8b2b65a2e6d652dae0d159eebcec193b04e817deebe21e55")
        XCTAssertEqual(relationship.recordSHA256, "81a8a086cabbe560c654b7dd2c12769a482311de4daa4fcb705821c0e4ce1e95")
        XCTAssertEqual(finding.finding?.evidence.finding.findingID, "finding.one")
        XCTAssertEqual(finding.finding?.evidence.finding.revision, 0)
        XCTAssertEqual(finding.ownerRevision, 1)
        XCTAssertEqual(relationship.relationship?.decisions.map(\.decision), [.notRelated])
        XCTAssertNil(relationship.relationship?.relationship)
    }

    func testSemanticReferencesStayDistinctFromTransportHashesAndBindConsumers() throws {
        let finding = try record()
        let relationship = try relationshipRecord()
        let findingBytes = try FindingOwnerCanonicalCodecV1.encode(finding)
        let relationshipBytes = try FindingOwnerCanonicalCodecV1.encode(relationship)
        let findingTransportHash = KernelCanonicalHashV1.sha256(findingBytes)
        let relationshipTransportHash = KernelCanonicalHashV1.sha256(relationshipBytes)
        XCTAssertEqual(findingTransportHash, "de3d4ba2c54833114267e0c21d0082b83b24a7e3e5d82aa5d2b4a28e88aa63cd")
        XCTAssertEqual(relationshipTransportHash, "4f4aa2a3076ed99c994d4d1d159d0cf685ba4e6542ed4f394aa82be5d81c4cc1")
        XCTAssertEqual(findingBytes.count, 1_836)
        XCTAssertEqual(relationshipBytes.count, 4_568)
        XCTAssertEqual(try finding.reference.recordSHA256, finding.recordSHA256)
        XCTAssertEqual(try relationship.reference.recordSHA256, relationship.recordSHA256)
        XCTAssertNotEqual(finding.recordSHA256, findingTransportHash)
        XCTAssertNotEqual(relationship.recordSHA256, relationshipTransportHash)
        for (value, wrongHash) in [(finding, findingTransportHash), (relationship, relationshipTransportHash)] {
            var raw = try object(value)
            raw["recordSHA256"] = wrongHash
            try rejected(raw)
        }
        var changedFinding = try object(finding)
        var findingPayload = try XCTUnwrap(changedFinding["finding"] as? [String: Any])
        var evidence = try XCTUnwrap(findingPayload["evidence"] as? [String: Any])
        var fact = try XCTUnwrap(evidence["finding"] as? [String: Any])
        fact["summary"] = "Valid changed payload, stale digest"
        evidence["finding"] = fact
        findingPayload["evidence"] = evidence
        changedFinding["finding"] = findingPayload
        try rejected(changedFinding)
        var changedRelationship = try object(relationship)
        var relationshipPayload = try XCTUnwrap(changedRelationship["relationship"] as? [String: Any])
        var suggestion = try XCTUnwrap(relationshipPayload["suggestion"] as? [String: Any])
        suggestion["reason"] = "Valid changed decision basis, stale digest"
        relationshipPayload["suggestion"] = suggestion
        changedRelationship["relationship"] = relationshipPayload
        try rejected(changedRelationship)

        let transportReference = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
            ownerID: finding.ownerID, ownerRevision: finding.ownerRevision, recordSHA256: findingTransportHash)
        let nextFacts = try FindingOwnedFactsV1(evidence: self.evidence(dispositions: [disposition()]))
        let falsePredecessor = try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: finding.ownerID,
            ownerRevision: 2, predecessor: transportReference, mutationID: mutation(21), recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), origin: finding.origin, finding: nextFacts)
        XCTAssertThrowsError(try falsePredecessor.validateAppendOnlySuccessor(of: finding))
        let acceptance = try accepted(101)
        let selected = try FindingSelectedOwnerReferenceV1(original: transportReference, selected: transportReference,
            originalAcceptance: acceptance, selectedAcceptance: acceptance)
        let endpoint = try FindingRelationshipEndpointReferenceV1(workID: "finding.one", workRevision: 0, owner: .finding(selected))
        XCTAssertThrowsError(try endpoint.validate(findingRecord: finding))
    }

    func testHumanAndImportedSourcesNeedNoFabricatedActivityBinding() throws {
        for kind in [FindingSourceKindV1.humanObservation, .importedRecord, .inspectionObservation, .inspectionResponse] {
            let facts = try FindingOwnedFactsV1(evidence: evidence(finding(sourceKind: kind)))
            let value = try record(facts: facts)
            try roundTrip(value)
            XCTAssertNil(value.finding?.activitySource)
            XCTAssertEqual(value.finding?.evidence.finding.source.sourceID, "observation.one")
            XCTAssertEqual(value.finding?.evidence.finding.source.kind, kind)
        }
        let foreign = WorkspaceID(rawValue: id(99))
        let context = try FindingSourceContextV1(workspaceID: foreign, activityID: id(3), activityKind: .punchReview,
            activityRevision: 1, activitySHA256: a)
        let acceptance = try accepted(90, workspace: foreign)
        let source = try FindingActivitySourceReferenceV1(original: context, selected: context,
            originalAcceptance: acceptance, selectedAcceptance: acceptance)
        let supplied = try FindingOwnedFactsV1(evidence: evidence(), activitySource: source)
        XCTAssertThrowsError(try record(facts: supplied))
    }

    func testOwnerRevisionAdvancesWithoutChangingFindingRevision() throws {
        let first = try record()
        let facts = try FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition()]))
        let second = try record(facts: facts, previous: first, mutationSlot: 21)
        try second.validateAppendOnlySuccessor(of: first)
        try FindingOwnerHistoryV1.validate([first, second])
        XCTAssertEqual(second.ownerRevision, 2)
        XCTAssertEqual(second.finding?.evidence.finding.revision, 0)
        XCTAssertEqual(second.origin, first.origin)
        XCTAssertEqual(second.predecessor, try first.reference)
        try roundTrip(second)
    }

    func testHistoricalValueClassificationDoesNotGrantRetryAcceptance() throws {
        let first = try record()
        let second = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition()])),
            previous: first, mutationSlot: 21)
        XCTAssertEqual(try FindingOwnerHistoryV1.classify(first, against: []), .newStream)
        XCTAssertEqual(try FindingOwnerHistoryV1.classify(second, against: [first]), .append)
        XCTAssertEqual(try FindingOwnerHistoryV1.classify(first, against: [first, second]), .identicalHistoricalValue)
        let changed = try record(facts: FindingOwnedFactsV1(evidence: evidence(finding(summary: "Changed original"))))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.classify(changed, against: [first, second]))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validate([first, first]))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validate([second]))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validate([second, first]))
    }

    func testSuccessorCannotRewriteDropOrReplaceOldFacts() throws {
        let first = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition()])))
        let changed = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition(reason: "Rewritten")])),
            previous: first, mutationSlot: 21)
        XCTAssertThrowsError(try changed.validateAppendOnlySuccessor(of: first))
        let dropped = try record(previous: first, mutationSlot: 21)
        XCTAssertThrowsError(try dropped.validateAppendOnlySuccessor(of: first))
        let noEffect = try record(facts: XCTUnwrap(first.finding), previous: first, mutationSlot: 21)
        XCTAssertThrowsError(try noEffect.validateAppendOnlySuccessor(of: first))
        let changedFinding = try record(facts: FindingOwnedFactsV1(evidence: evidence(finding(summary: "New summary"),
            dispositions: [disposition(), disposition(2)])), previous: first, mutationSlot: 21)
        XCTAssertThrowsError(try changedFinding.validateAppendOnlySuccessor(of: first))
        let valid = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition(), disposition(2)])),
            previous: first, mutationSlot: 21)
        try valid.validateAppendOnlySuccessor(of: first)
    }

    func testLifecycleTransitionPreservesOriginalFieldsAndRevisionLaw() throws {
        let first = try record()
        let transition = try FindingTransitionV1(transitionID: "transition.one", findingID: "finding.one",
            expectedFindingRevision: 0, resultingFindingRevision: 1, mutationID: "transition-mutation.one",
            fromState: .open, toState: .correctiveWorkInProgress, actorID: "actor.one", reason: "Started", effectiveAt: instant)
        let facts = try FindingOwnedFactsV1(evidence: evidence(finding(revision: 1), transitions: [transition]))
        let second = try record(facts: facts, previous: first, mutationSlot: 21)
        try second.validateAppendOnlySuccessor(of: first)
        XCTAssertEqual(second.finding?.evidence.lifecycle.currentState, .correctiveWorkInProgress)
        XCTAssertEqual(second.finding?.evidence.finding.revision, 1)
        XCTAssertThrowsError(try evidence(finding(revision: 0), transitions: [transition]))
    }

    func testWorkspaceOwnerAndKernelIdentityCensusRejectsConflicts() throws {
        let first = try record()
        let duplicateFindingOwner = try record(ownerSlot: 31)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([first, duplicateFindingOwner], workspaceID: workspace))
        let sameOwnerOtherFinding = try record(facts: FindingOwnedFactsV1(evidence: evidence(finding("finding.two"))))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([first, sameOwnerOtherFinding], workspaceID: workspace))
        let second = try record(facts: FindingOwnedFactsV1(evidence: evidence(finding("finding.two"))), ownerSlot: 31)
        try FindingOwnerHistoryV1.validateHeads([first, second], workspaceID: workspace)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([first], workspaceID: WorkspaceID(rawValue: id(99))))
    }

    func testC14SupportRequiresOriginalGenuineActionAndRetainsUnlinkedHistory() throws {
        let event = try correctiveEvent(sourceKind: .finding)
        let reference = try support(event)
        let linked = try workLink(reference.correctiveWorkID)
        let facts = try FindingOwnedFactsV1(evidence: evidence(links: [linked]), correctiveActions: [reference])
        let first = try record(facts: facts)
        try roundTrip(first)
        let removal = try workLink(reference.correctiveWorkID, removed: true)
        let removed = try FindingOwnedFactsV1(evidence: evidence(links: [linked, removal]), correctiveActions: [reference])
        let second = try record(facts: removed, previous: first, mutationSlot: 21)
        try second.validateAppendOnlySuccessor(of: first)
        XCTAssertEqual(second.finding?.correctiveActions, [reference])
        XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: evidence(), correctiveActions: [reference]))
        let alias = try support(event, workID: "work.alias")
        XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: evidence(links: [workLink("work.alias")]), correctiveActions: [alias]))
        XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: evidence(links: [linked]), correctiveActions: [reference, reference]))
        let conflicting = try FindingAcceptedMutationReferenceV1(workspaceID: workspace, generationID: id(3),
            mutationID: event.mutationID, envelopeSHA256: a, receiptSHA256: b)
        let later = try FindingCorrectiveEventReferenceV1(workspaceID: workspace, actionID: event.actionID,
            eventID: id(59), eventRevision: 2, eventSHA256: a, acceptance: conflicting)
        let laterSupport = try FindingC14SupportReferenceV1(correctiveWorkID: reference.correctiveWorkID,
            correctiveWorkRevision: 1, original: later, selected: later)
        XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: evidence(links: [linked]),
            correctiveActions: [reference, laterSupport]))
    }

    func testDirectFindingEndpointsAllowRevisionZeroWithoutCorrection() throws {
        let sourceRecord = try record(ownerSlot: 31)
        let accepted = try accepted(101)
        let owner = try FindingSelectedOwnerReferenceV1(original: sourceRecord.reference, selected: sourceRecord.reference,
            originalAcceptance: accepted, selectedAcceptance: accepted)
        let endpoint = try FindingRelationshipEndpointReferenceV1(workID: "finding.one", workRevision: 0, owner: .finding(owner))
        try endpoint.validate(findingRecord: sourceRecord)
        XCTAssertTrue(try XCTUnwrap(sourceRecord.finding).evidence.correctiveWorkLinks.isEmpty)
        let wrongRevision = try FindingRelationshipEndpointReferenceV1(workID: "finding.one", workRevision: 1, owner: .finding(owner))
        XCTAssertThrowsError(try wrongRevision.validate(findingRecord: sourceRecord))
        let wrongString = try FindingRelationshipEndpointReferenceV1(workID: "finding.other", workRevision: 0, owner: .finding(owner))
        XCTAssertThrowsError(try wrongString.validate(findingRecord: sourceRecord))
        let payload = try relation(source: endpoint)
        try roundTrip(relationshipRecord(payload))
    }

    func testRealC14NonFindingSourceAndMixedEndpointsAreSupported() throws {
        let event = try correctiveEvent()
        let endpoint = try c14Endpoint(event)
        try endpoint.validate(originalCorrectiveEvent: event, selectedCorrectiveEvent: event)
        XCTAssertEqual(event.source.kind, .criterion)
        XCTAssertEqual(endpoint.workID, id(50).uuidString.lowercased())
        XCTAssertEqual(endpoint.workRevision, 1)
        let otherEvent = try correctiveEvent(actionSlot: 60, sourceKind: .review)
        let c14Pair = try relation(source: endpoint, candidate: c14Endpoint(otherEvent), confirm: true)
        try roundTrip(relationshipRecord(c14Pair))
        let mixed = try relation(source: direct("finding.one", ownerSlot: 31), candidate: endpoint, confirm: true)
        try roundTrip(relationshipRecord(mixed))
        XCTAssertThrowsError(try endpoint.validate(originalCorrectiveEvent: event, selectedCorrectiveEvent: otherEvent))
        let reference = try support(event)
        XCTAssertThrowsError(try FindingRelationshipEndpointReferenceV1(workID: event.eventID.uuidString.lowercased(),
            workRevision: 1, owner: .correctiveAction(reference)))
        XCTAssertThrowsError(try FindingRelationshipEndpointReferenceV1(workID: reference.correctiveWorkID,
            workRevision: 0, owner: .correctiveAction(reference)))
    }

    func testRelationshipHistoryPreservesConfirmationAndExplicitRemoval() throws {
        let firstPayload = try relation(confirm: true)
        let first = try relationshipRecord(firstPayload)
        let removedPayload = try relation(confirm: true, removed: true)
        let second = try relationshipRecord(removedPayload, previous: first, mutationSlot: 21)
        try second.validateAppendOnlySuccessor(of: first)
        try FindingOwnerHistoryV1.validate([first, second])
        XCTAssertEqual(second.relationship?.relationship, first.relationship?.relationship)
        XCTAssertEqual(second.relationship?.decisions.map(\.decision), [.confirm, .removeRelation])
        XCTAssertNil(try WorkRelationshipDecisionLedgerV1.activeRelationshipID(for: removedPayload.suggestion,
                                                                              decisions: removedPayload.decisions))
        let rejection = try relationshipRecord()
        let inventedConfirmation = try relationshipRecord(firstPayload, previous: rejection, mutationSlot: 21)
        XCTAssertThrowsError(try inventedConfirmation.validateAppendOnlySuccessor(of: rejection))
        let noEffect = try relationshipRecord(firstPayload, previous: first, mutationSlot: 21)
        XCTAssertThrowsError(try noEffect.validateAppendOnlySuccessor(of: first))
        XCTAssertThrowsError(try FindingOwnedRelationshipV1(suggestion: firstPayload.suggestion, source: firstPayload.source,
            candidate: firstPayload.candidate, relationship: firstPayload.relationship, decisions: []))
    }

    func testRelationshipBasisRolesKindsAndSingleOwnershipAreClosed() throws {
        let payload = try relation(confirm: true)
        XCTAssertThrowsError(try FindingOwnedRelationshipV1(suggestion: payload.suggestion, source: payload.candidate,
            candidate: payload.source, relationship: payload.relationship, decisions: payload.decisions))
        let changedBasis = try RelatedWorkSuggestionV1(sourceWorkID: "finding.one", sourceWorkRevision: 1,
            candidateWorkID: "finding.two", candidateWorkRevision: 0, subjectID: "subject.one", categoryID: "leak",
            policySHA256: a, reason: "Possible duplicate")
        XCTAssertThrowsError(try FindingOwnedRelationshipV1(suggestion: changedBasis, source: payload.source,
            candidate: payload.candidate, relationship: payload.relationship, decisions: payload.decisions))
        let fact = try finding()
        let lifecycle = try FindingLifecycleV1(findingID: fact.findingID)
        let duplicated = try FindingLifecycleCanonicalEvidenceV1(finding: fact, lifecycle: lifecycle,
            relatedWorkSuggestions: [payload.suggestion], workRelationships: [XCTUnwrap(payload.relationship)],
            workRelationshipDecisions: payload.decisions)
        XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: duplicated))
        let liveSuggestion = try FindingLifecycleCanonicalEvidenceV1(finding: fact, lifecycle: lifecycle,
            relatedWorkSuggestions: [payload.suggestion])
        XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: liveSuggestion))
        var raw = try object(relationshipRecord(payload))
        var relationship = try XCTUnwrap(raw["relationship"] as? [String: Any])
        var source = try XCTUnwrap(relationship["source"] as? [String: Any])
        var owner = try XCTUnwrap(source["owner"] as? [String: Any])
        owner["kind"] = "workflowRecord"
        source["owner"] = owner
        relationship["source"] = source
        raw["relationship"] = relationship
        try rejected(raw)
    }

    func testAffectedClosureRejectsCrossStreamReversePairsCyclesAndDomainAmbiguity() throws {
        let ab = try relationshipRecord(relation(confirm: true), ownerSlot: 40)
        let reverse = try relation(source: direct("finding.two", ownerSlot: 32), candidate: direct("finding.one", ownerSlot: 31),
            confirm: true, relationshipID: "relationship.reverse", decisionID: "decision.reverse")
        let ba = try relationshipRecord(reverse, ownerSlot: 41)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateRelationshipClosure([ab, ba], workspaceID: workspace))
        let bc = try relationshipRecord(relation(source: direct("finding.two", ownerSlot: 32),
            candidate: direct("finding.three", ownerSlot: 33), confirm: true,
            relationshipID: "relationship.bc", decisionID: "decision.bc"), ownerSlot: 42)
        let ca = try relationshipRecord(relation(source: direct("finding.three", ownerSlot: 33),
            candidate: direct("finding.one", ownerSlot: 31), confirm: true,
            relationshipID: "relationship.ca", decisionID: "decision.ca"), ownerSlot: 43)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateRelationshipClosure([ab, bc, ca], workspaceID: workspace))
        try FindingOwnerHistoryV1.validateRelationshipClosure([ab, bc], workspaceID: workspace)
        // Passing this subset does not establish that an omitted CA stream does
        // not exist. The future writer must authenticate the complete closure.
        let event = try correctiveEvent()
        let token = event.actionID.uuidString.lowercased()
        let findingDomain = try relationshipRecord(relation(source: direct(token, ownerSlot: 35),
            candidate: direct("finding.two", ownerSlot: 32), relationshipID: "unused.one", decisionID: "decision.finding"), ownerSlot: 44)
        let c14Domain = try relationshipRecord(relation(source: c14Endpoint(event),
            candidate: direct("finding.three", ownerSlot: 33), relationshipID: "unused.two", decisionID: "decision.c14"), ownerSlot: 45)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([findingDomain, c14Domain], workspaceID: workspace))
        XCTAssertThrowsError(try relation(source: direct(token, ownerSlot: 35), candidate: c14Endpoint(event)))
    }

    func testEndpointOwnerTokensAndAcceptanceIdentitiesCannotConflict() throws {
        let first = try direct("finding.one", ownerSlot: 31)
        let alias = try direct("finding.alias", ownerSlot: 31)
        XCTAssertThrowsError(try relation(source: first, candidate: alias))
        let a = try relationshipRecord(relation(source: first), ownerSlot: 40)
        let b = try relationshipRecord(relation(source: alias, candidate: direct("finding.three", ownerSlot: 33),
            decisionID: "decision.alias"), ownerSlot: 41)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([a, b], workspaceID: workspace))
        let known = try record(ownerSlot: 31)
        try FindingOwnerHistoryV1.validateHeads([known, a], workspaceID: workspace)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([known, b], workspaceID: workspace))
        // Revision currentness is writer-owned; the immutable String identity
        // still cannot contradict an explicitly supplied head.

        func endpoint(_ workID: String, ownerSlot: Int,
                      acceptance: FindingAcceptedMutationReferenceV1) throws -> FindingRelationshipEndpointReferenceV1 {
            let reference = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
                ownerID: id(ownerSlot), ownerRevision: 7, recordSHA256: self.a)
            let selected = try FindingSelectedOwnerReferenceV1(original: reference, selected: reference,
                originalAcceptance: acceptance, selectedAcceptance: acceptance)
            return try FindingRelationshipEndpointReferenceV1(workID: workID, workRevision: 0, owner: .finding(selected))
        }
        let original = try accepted(101)
        let shared = try endpoint("finding.two", ownerSlot: 32, acceptance: original)
        try roundTrip(relationshipRecord(relation(source: first, candidate: shared)))
        // One genuine envelope can contain several owner effects; equal keys
        // require equal reference facts, not distinct mutation IDs per owner.
        let conflicting = try FindingAcceptedMutationReferenceV1(workspaceID: workspace, generationID: id(3),
            mutationID: mutation(101), envelopeSHA256: self.a, receiptSHA256: self.b)
        let wrong = try endpoint("finding.two", ownerSlot: 32, acceptance: conflicting)
        XCTAssertThrowsError(try relation(source: first, candidate: wrong))
        let foreignPair = try relationshipRecord(relation(source: wrong,
            candidate: direct("finding.three", ownerSlot: 33), decisionID: "decision.conflict"), ownerSlot: 42)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([a, foreignPair], workspaceID: workspace))
        let separate = try FindingAcceptedMutationReferenceV1(workspaceID: workspace, generationID: id(3),
            mutationID: mutation(105), envelopeSHA256: self.b, receiptSHA256: self.a)
        try roundTrip(relationshipRecord(relation(source: first,
            candidate: endpoint("finding.two", ownerSlot: 32, acceptance: separate))))
        // Different accepted identities may coexist in one workspace. These
        // fixtures test intrinsic consistency, never authenticity or currentness.
    }

    func testPredecessorOriginActorAndTimeAreExact() throws {
        let first = try record()
        let facts = try FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition()]))
        let falsePrevious = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
            ownerID: first.ownerID, ownerRevision: 1, recordSHA256: a)
        let candidate = try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: 2, predecessor: falsePrevious, mutationID: mutation(21), recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), origin: first.origin, finding: facts)
        XCTAssertThrowsError(try candidate.validateAppendOnlySuccessor(of: first))
        let alteredOrigin = try FindingOwnerOriginIdentityV1(workspaceID: workspace, kind: .finding,
            ownerID: first.ownerID, creationMutationID: mutation(99))
        let altered = try record(facts: facts, previous: first, mutationSlot: 21, origin: alteredOrigin)
        XCTAssertThrowsError(try altered.validateAppendOnlySuccessor(of: first))
        XCTAssertThrowsError(try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: 1, mutationID: mutation(21), recordedBy: actor(), recordedAt: Date(timeIntervalSince1970: 1),
            origin: first.origin, finding: first.finding))
        XCTAssertThrowsError(try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: 1, mutationID: mutation(20), recordedBy: actor(responsibility: .verifiedBy),
            recordedAt: Date(timeIntervalSince1970: 1), origin: first.origin, finding: first.finding))
        let backwards = try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: 2, predecessor: first.reference, mutationID: mutation(21), recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 0), origin: first.origin, finding: facts)
        XCTAssertThrowsError(try backwards.validateAppendOnlySuccessor(of: first))
        XCTAssertThrowsError(try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: 1, mutationID: mutation(20), recordedBy: actor(), recordedAt: Date(timeIntervalSince1970: -1),
            origin: first.origin, finding: first.finding))
        let foreign = WorkspaceID(rawValue: id(99))
        let mapped = try record(workspace: foreign, origin: first.origin)
        try roundTrip(mapped)
        XCTAssertEqual(mapped.origin, first.origin)
        XCTAssertEqual(mapped.ownerID, first.ownerID)
        XCTAssertEqual(mapped.finding?.evidence, first.finding?.evidence)
        // This preserved origin identity is not proof of an authorized Fork or
        // its original accepted bytes. The lifecycle importer still owns that.
    }

    func testHistoryRejectsReusedMutationAndSkippedOwnerRevision() throws {
        let first = try record()
        let second = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition()])),
            previous: first, mutationSlot: 21)
        let third = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition(), disposition(2)])),
            previous: second, mutationSlot: 20)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.classify(third, against: [first, second]))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validate([first, second, third]))
        var raw = try object(second)
        raw["ownerRevision"] = 3
        try rejected(raw)
        raw = try object(first)
        raw["ownerRevision"] = 0
        try rejected(raw)
        raw = try object(first)
        raw["ownerID"] = zero.uuidString
        try rejected(raw)
    }

    func testUInt64AndIntEdgesRejectWithoutInvokingUnsafeLegacyArithmetic() throws {
        let first = try record()
        let maximumPrevious = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
            ownerID: first.ownerID, ownerRevision: UInt64.max, recordSHA256: a)
        XCTAssertThrowsError(try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: 1, predecessor: maximumPrevious, mutationID: mutation(21), recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), origin: first.origin, finding: first.finding))
        let lastPrevious = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
            ownerID: first.ownerID, ownerRevision: UInt64.max - 1, recordSHA256: a)
        let last = try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: UInt64.max, predecessor: lastPrevious, mutationID: mutation(21), recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), origin: first.origin, finding: first.finding)
        try roundTrip(last)
        let fields: [(String, String)] = [
            ("correctiveWorkLinks", "expectedLinkRevision"), ("verifiedRechecks", "expectedRecheckRevision"),
            ("releasesToService", "verifiedRecheckFindingRevision"),
            ("operationalDispositionEvents", "expectedDispositionRevision"),
            ("workRelationshipDecisions", "expectedDecisionRevision")
        ]
        for (array, field) in fields {
            var raw = try object(first)
            var payload = try XCTUnwrap(raw["finding"] as? [String: Any])
            var evidence = try XCTUnwrap(payload["evidence"] as? [String: Any])
            evidence[array] = [[field: NSNumber(value: Int.max)]]
            payload["evidence"] = evidence
            raw["finding"] = payload
            XCTAssertThrowsError(try FindingOwnerCanonicalCodecV1.decode(json(raw))) { error in
                XCTAssertEqual(error as? FindingContractFailureV1, .invalidValue)
            }
        }
        var raw = try object(first)
        var payload = try XCTUnwrap(raw["finding"] as? [String: Any])
        var evidence = try XCTUnwrap(payload["evidence"] as? [String: Any])
        var lifecycle = try XCTUnwrap(evidence["lifecycle"] as? [String: Any])
        lifecycle["initialRevision"] = NSNumber(value: Int.max)
        lifecycle["transitions"] = [["expectedFindingRevision": 0]]
        evidence["lifecycle"] = lifecycle
        payload["evidence"] = evidence
        raw["finding"] = payload
        try rejected(raw)
        let event = try correctiveEvent()
        let old = try support(event)
        let maximumEvent = try FindingCorrectiveEventReferenceV1(workspaceID: workspace, actionID: event.actionID,
            eventID: event.eventID, eventRevision: UInt64.max, eventSHA256: a, acceptance: old.original.acceptance)
        let tooWide = try FindingC14SupportReferenceV1(correctiveWorkID: old.correctiveWorkID,
            correctiveWorkRevision: Int.max, original: maximumEvent, selected: maximumEvent)
        XCTAssertThrowsError(try FindingRelationshipEndpointReferenceV1(workID: old.correctiveWorkID,
            workRevision: Int.max, owner: .correctiveAction(tooWide)))
        var relationship = try object(relationshipRecord())
        var relation = try XCTUnwrap(relationship["relationship"] as? [String: Any])
        relation["decisions"] = [["expectedDecisionRevision": NSNumber(value: Int.max)]]
        relationship["relationship"] = relation
        try rejected(relationship)
    }

    func testRecordAndEndpointUnionKeysNullsAndDigestsAreClosed() throws {
        for value in try [record(), relationshipRecord()] {
            let raw = try object(value)
            let keys: Set<String> = ["workspaceID", "kind", "ownerID", "ownerRevision", "mutationID", "recordedBy",
                                     "recordedAt", "origin", value.kind == .finding ? "finding" : "relationship", "recordSHA256"]
            XCTAssertEqual(Set(raw.keys), keys)
            for key in keys {
                var missing = raw
                missing.removeValue(forKey: key)
                try rejected(missing)
                var null = raw
                null[key] = NSNull()
                try rejected(null)
            }
            var unknown = raw
            unknown["schemaVersion"] = 999
            try rejected(unknown)
            var future = raw
            future["kind"] = "workflowRecord"
            try rejected(future)
            for digest in [a, "", String(repeating: "A", count: 64), String(repeating: "a", count: 63) + "g"] {
                var tampered = raw
                tampered["recordSHA256"] = digest
                try rejected(tampered)
            }
            for optional in ["predecessor", value.kind == .finding ? "relationship" : "finding"] {
                var null = raw
                null[optional] = NSNull()
                try rejected(null)
            }
        }
        var raw = try object(relationshipRecord())
        var relationship = try XCTUnwrap(raw["relationship"] as? [String: Any])
        var endpoint = try XCTUnwrap(relationship["source"] as? [String: Any])
        var owner = try XCTUnwrap(endpoint["owner"] as? [String: Any])
        owner["correctiveAction"] = NSNull()
        endpoint["owner"] = owner
        relationship["source"] = endpoint
        raw["relationship"] = relationship
        try rejected(raw)
        var both = try object(record())
        both["relationship"] = try object(relationshipRecord())["relationship"]
        try rejected(both)
    }

    func testCanonicalTransportRejectsUnknownNestedFieldsDuplicateKeysAndOversize() throws {
        let value = try relationshipRecord(relation(confirm: true))
        let event = try correctiveEvent(sourceKind: .finding)
        let support = try support(event)
        let withSupport = try record(facts: FindingOwnedFactsV1(
            evidence: evidence(links: [workLink(support.correctiveWorkID)]), correctiveActions: [support]))
        let mixed = try relationshipRecord(relation(candidate: c14Endpoint(event), confirm: true))
        for record in [value, withSupport, mixed] {
            for changed in try unknownVariants(object(record)) {
                try rejected(XCTUnwrap(changed as? [String: Any]))
            }
        }
        let bytes = try FindingOwnerCanonicalCodecV1.encode(value)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let duplicate = "{\"kind\":\"relationship\"," + String(text.dropFirst())
        XCTAssertThrowsError(try FindingOwnerCanonicalCodecV1.decode(Data(duplicate.utf8)))
        XCTAssertThrowsError(try FindingOwnerCanonicalCodecV1.decode(Data((text + "\n").utf8)))
        XCTAssertThrowsError(try FindingOwnerCanonicalCodecV1.decode(Data(repeating: 0x20,
            count: FindingContractLimitsV1.maximumCanonicalBytes + 1)))
        XCTAssertThrowsError(try FindingOwnerCanonicalCodecV1.decode(Data()))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validate(Array(repeating: value,
            count: FindingOwnerHistoryV1.maximumHistoryRecords + 1)))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads(Array(repeating: value,
            count: FindingOwnerHistoryV1.maximumOwnerStreams + 1), workspaceID: workspace))
    }

    func testCompleteRecordByteBoundIncludesRetainedSupportReferences() throws {
        let event = try correctiveEvent(sourceKind: .finding)
        let workID = event.actionID.uuidString.lowercased()
        let boundEvidence = try evidence(links: [workLink(workID)])
        var supports: [FindingC14SupportReferenceV1] = []
        for revision in 1...FindingContractLimitsV1.maximumRegistryEntries {
            let acceptance = try accepted(4_000 + revision)
            let reference = try FindingCorrectiveEventReferenceV1(workspaceID: workspace,
                actionID: event.actionID, eventID: id(2_000 + revision), eventRevision: UInt64(revision),
                eventSHA256: a, acceptance: acceptance)
            supports.append(try FindingC14SupportReferenceV1(correctiveWorkID: workID,
                correctiveWorkRevision: 1, original: reference, selected: reference))
        }
        let facts = try FindingOwnedFactsV1(evidence: boundEvidence, correctiveActions: supports)
        XCTAssertGreaterThan(try WorkspaceMutationCanonicalV1.data(facts).count,
                             FindingContractLimitsV1.maximumCanonicalBytes)
        XCTAssertThrowsError(try record(facts: facts)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .limitExceeded)
        }
        supports.append(try XCTUnwrap(supports.last))
        XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: boundEvidence, correctiveActions: supports)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .limitExceeded)
        }
    }

    func testAppendOnlyRetentionUsesExactBytesAndGroupedEventIdentity() throws {
        let composed = try disposition(reason: "caf\u{00e9}")
        let decomposed = try disposition(reason: "cafe\u{0301}")
        XCTAssertEqual(composed.reason, decomposed.reason)
        XCTAssertNotEqual(try WorkspaceMutationCanonicalV1.data(composed),
                          try WorkspaceMutationCanonicalV1.data(decomposed))
        let first = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [composed])))
        let rewritten = try record(facts: FindingOwnedFactsV1(evidence: evidence(dispositions: [decomposed, disposition(2)])),
            previous: first, mutationSlot: 21)
        XCTAssertThrowsError(try rewritten.validateAppendOnlySuccessor(of: first))

        func link(_ identity: String, workID: String, removed: Bool = false) throws -> CorrectiveWorkLinkV1 {
            try CorrectiveWorkLinkV1(linkID: identity, findingID: "finding.one", findingRevision: 0,
                workID: workID, workRevision: 0, expectedLinkRevision: removed ? 1 : 0,
                resultingLinkRevision: removed ? 2 : 1, mutationID: "mutation." + identity,
                action: removed ? .removed : .linked, actorID: "actor.one", reason: "Recorded", effectiveAt: instant,
                supersedesLinkEventID: removed ? "link.b" : nil)
        }
        let b = try link("link.b", workID: "work.b")
        let z = try link("link.z", workID: "work.z")
        let removed = try link("link.b-removed", workID: "work.b", removed: true)
        let prior = try record(facts: FindingOwnedFactsV1(evidence: evidence(links: [b, z])))
        let next = try record(facts: FindingOwnedFactsV1(evidence: evidence(links: [b, removed, z])),
            previous: prior, mutationSlot: 21)
        try next.validateAppendOnlySuccessor(of: prior)
        XCTAssertEqual(next.finding?.evidence.correctiveWorkLinks.map(\.linkID), ["link.b", "link.b-removed", "link.z"])
    }

    func testR2OwnerRevisionFactsAcrossRelationshipsIncludeBothReferenceSides() throws {
        let originalWorkspace = WorkspaceID(rawValue: id(99))
        let first = try r2OwnerReference(digest: a)
        let same = try r2OwnerReference(digest: a)
        let changed = try r2OwnerReference(digest: b)
        let endpointA = try r2FindingEndpoint("finding.one", selected: first, receiptSlot: 101)
        let endpointB = try r2FindingEndpoint("finding.one", selected: changed, receiptSlot: 105)
        let ab = try relationshipRecord(relation(source: endpointA), ownerSlot: 40)
        let ac = try relationshipRecord(relation(source: endpointB, candidate: direct("finding.three", ownerSlot: 33),
            decisionID: "decision.ac"), ownerSlot: 41)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([ab, ac], workspaceID: workspace)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
        }
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateRelationshipClosure([ab, ac], workspaceID: workspace))
        let equalEndpoint = try r2FindingEndpoint("finding.one", selected: same, receiptSlot: 105)
        let equalAC = try relationshipRecord(relation(source: equalEndpoint, candidate: direct("finding.three", ownerSlot: 33),
            decisionID: "decision.ac"), ownerSlot: 41)
        try FindingOwnerHistoryV1.validateRelationshipClosure([ab, equalAC], workspaceID: workspace)
        let laterReference = try r2OwnerReference(revision: 8, digest: b)
        let laterEndpoint = try r2FindingEndpoint("finding.one", selected: laterReference, receiptSlot: 105)
        let laterAC = try relationshipRecord(relation(source: laterEndpoint, candidate: direct("finding.three", ownerSlot: 33),
            decisionID: "decision.ac"), ownerSlot: 41)
        try FindingOwnerHistoryV1.validateRelationshipClosure([ab, laterAC], workspaceID: workspace)

        for conflictInOriginal in [true, false] {
            let originalA = try r2OwnerReference(workspace: originalWorkspace, digest: a)
            let originalB = try r2OwnerReference(workspace: originalWorkspace, digest: conflictInOriginal ? b : a)
            let selectedB = try r2OwnerReference(digest: conflictInOriginal ? a : b)
            let mappedA = try r2FindingEndpoint("finding.one", original: originalA, selected: first, receiptSlot: 110)
            let mappedB = try r2FindingEndpoint("finding.one", original: originalB, selected: selectedB, receiptSlot: 120)
            let left = try relationshipRecord(relation(source: mappedA), ownerSlot: 40)
            let right = try relationshipRecord(relation(source: mappedB, candidate: direct("finding.three", ownerSlot: 33),
                decisionID: "decision.mapped"), ownerSlot: 41)
            XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([left, right], workspaceID: workspace)) { error in
                XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
            }
        }
        let foreign = try r2OwnerReference(workspace: originalWorkspace, digest: b)
        let permitted = try r2FindingEndpoint("finding.one", original: foreign, selected: first, receiptSlot: 130)
        let foreignAC = try relationshipRecord(relation(source: permitted, candidate: direct("finding.three", ownerSlot: 33),
            decisionID: "decision.foreign"), ownerSlot: 41)
        try FindingOwnerHistoryV1.validateHeads([ab, foreignAC], workspaceID: workspace)
    }

    func testR2ActualRecordAndPredecessorReferencesJoinFactCensus() throws {
        let first = try record(ownerSlot: 31)
        let actual = try first.reference
        let wrong = try r2OwnerReference(revision: 1, digest: a)
        let endpoint = try r2FindingEndpoint("finding.one", selected: actual, receiptSlot: 101)
        let badEndpoint = try r2FindingEndpoint("finding.one", selected: wrong, receiptSlot: 105)
        let relationship = try relationshipRecord(relation(source: endpoint))
        let divergent = try relationshipRecord(relation(source: badEndpoint))
        try FindingOwnerHistoryV1.validateHeads([first, relationship], workspaceID: workspace)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([first, divergent], workspaceID: workspace)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
        }
        let facts = try FindingOwnedFactsV1(evidence: evidence(dispositions: [disposition()]))
        let second = try record(facts: facts, previous: first, ownerSlot: 31, mutationSlot: 21)
        try FindingOwnerHistoryV1.validate([first, second])
        try FindingOwnerHistoryV1.validateHeads([second, relationship], workspaceID: workspace)
        // first is absent: the only authentic-shaped fact for revision 1 in
        // this supplied set is second.predecessor, which must still participate.
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([second, divergent], workspaceID: workspace)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
        }
        let falseSuccessor = try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: first.ownerID,
            ownerRevision: 2, predecessor: wrong, mutationID: mutation(21), recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), origin: first.origin, finding: facts)
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validate([first, falseSuccessor]))
        XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([falseSuccessor, relationship], workspaceID: workspace))
    }

    func testR2RetainedC14ActionRevisionRejectsChangedEventAndDigestOnBothSides() throws {
        let foreign = WorkspaceID(rawValue: id(99))
        let workID = id(50).uuidString.lowercased()
        let firstLink = try workLink(workID)
        let removal = try workLink(workID, removed: true)
        let relink = try CorrectiveWorkLinkV1(linkID: "link.relinked", findingID: "finding.one", findingRevision: 0,
            workID: workID, workRevision: 2, expectedLinkRevision: 2, resultingLinkRevision: 3,
            mutationID: "link-mutation.relinked", action: .linked, actorID: "actor.one", reason: "Relinked",
            effectiveAt: instant, supersedesLinkEventID: "link.removed")
        let facts = try evidence(links: [firstLink, removal, relink])
        for conflictInOriginal in [true, false] {
            for changeEventID in [true, false] {
                let oldOriginal = try r2CorrectiveReference(workspace: foreign, receiptSlot: 201)
                let oldSelected = try r2CorrectiveReference(receiptSlot: 202)
                let nextEventSlot = changeEventID ? 59 : 51
                let nextDigest = changeEventID ? a : b
                let newOriginal = try r2CorrectiveReference(workspace: foreign,
                    eventSlot: conflictInOriginal ? nextEventSlot : 51,
                    digest: conflictInOriginal ? nextDigest : a, receiptSlot: 203)
                let newSelected = try r2CorrectiveReference(eventSlot: conflictInOriginal ? 51 : nextEventSlot,
                    digest: conflictInOriginal ? a : nextDigest, receiptSlot: 204)
                let old = try r2Support(original: oldOriginal, selected: oldSelected, workRevision: 1)
                let changed = try r2Support(original: newOriginal, selected: newSelected, workRevision: 2)
                XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: facts, correctiveActions: [old, changed])) { error in
                    XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
                }
                let equalOriginal = try r2CorrectiveReference(workspace: foreign, receiptSlot: 205)
                let equalSelected = try r2CorrectiveReference(receiptSlot: 206)
                let equal = try r2Support(original: equalOriginal, selected: equalSelected, workRevision: 2)
                let retained = try FindingOwnedFactsV1(evidence: facts, correctiveActions: [old, equal])
                try roundTrip(record(facts: retained))
            }
        }
    }

    func testR2RetainedC14EventIdentityRejectsRevisionReuseAndAllowsDifferentEvents() throws {
        let foreign = WorkspaceID(rawValue: id(99))
        let workID = id(50).uuidString.lowercased()
        let facts = try evidence(links: [workLink(workID)])
        for conflictInOriginal in [true, false] {
            let oldOriginal = try r2CorrectiveReference(workspace: foreign, receiptSlot: 211)
            let oldSelected = try r2CorrectiveReference(receiptSlot: 212)
            let original = try r2CorrectiveReference(workspace: foreign,
                eventSlot: conflictInOriginal ? 51 : 52, revision: 2, receiptSlot: 213)
            let selected = try r2CorrectiveReference(eventSlot: conflictInOriginal ? 52 : 51,
                revision: 2, receiptSlot: 214)
            let old = try r2Support(original: oldOriginal, selected: oldSelected, workRevision: 1)
            let reused = try r2Support(original: original, selected: selected, workRevision: 1)
            XCTAssertThrowsError(try FindingOwnedFactsV1(evidence: facts, correctiveActions: [old, reused])) { error in
                XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
            }
            let nextOriginal = try r2CorrectiveReference(workspace: foreign, eventSlot: 52, revision: 2, digest: b, receiptSlot: 215)
            let nextSelected = try r2CorrectiveReference(eventSlot: 52, revision: 2, digest: b, receiptSlot: 216)
            let next = try r2Support(original: nextOriginal, selected: nextSelected, workRevision: 1)
            let valid = try FindingOwnedFactsV1(evidence: facts, correctiveActions: [old, next])
            try roundTrip(record(facts: valid))
        }
        // Identical raw action/event UUIDs may name different immutable facts in
        // different workspaces. This asserts shape, not a genuine Fork mapping.
        let original = try r2CorrectiveReference(workspace: foreign, digest: b, receiptSlot: 217)
        let selected = try r2CorrectiveReference(digest: a, receiptSlot: 218)
        let mapped = try r2Support(original: original, selected: selected, workRevision: 1)
        let valid = try FindingOwnedFactsV1(evidence: facts, correctiveActions: [mapped])
        try roundTrip(record(facts: valid))
    }

    func testR2C14EndpointEventActionConflictsReachRelationshipAndCombinedHeads() throws {
        let foreign = WorkspaceID(rawValue: id(99))
        for conflictInOriginal in [true, false] {
            let originalA = try r2CorrectiveReference(workspace: foreign, receiptSlot: 221)
            let selectedA = try r2CorrectiveReference(receiptSlot: 222)
            let originalB = try r2CorrectiveReference(workspace: foreign, actionSlot: 60,
                eventSlot: conflictInOriginal ? 51 : 61, receiptSlot: 223)
            let selectedB = try r2CorrectiveReference(actionSlot: 60,
                eventSlot: conflictInOriginal ? 61 : 51, receiptSlot: 224)
            let supportA = try r2Support(original: originalA, selected: selectedA, workRevision: 1)
            let supportB = try r2Support(original: originalB, selected: selectedB, workRevision: 1)
            let endpointA = try FindingRelationshipEndpointReferenceV1(workID: supportA.correctiveWorkID,
                workRevision: 1, owner: .correctiveAction(supportA))
            let endpointB = try FindingRelationshipEndpointReferenceV1(workID: supportB.correctiveWorkID,
                workRevision: 1, owner: .correctiveAction(supportB))
            XCTAssertThrowsError(try relation(source: endpointA, candidate: endpointB)) { error in
                XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
            }
            let left = try relationshipRecord(relation(source: endpointA), ownerSlot: 40)
            let right = try relationshipRecord(relation(source: endpointB, candidate: direct("finding.three", ownerSlot: 33),
                decisionID: "decision.c14"), ownerSlot: 41)
            XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([left, right], workspaceID: workspace)) { error in
                XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
            }
            let validOriginal = try r2CorrectiveReference(workspace: foreign, actionSlot: 60, eventSlot: 61, receiptSlot: 225)
            let validSelected = try r2CorrectiveReference(actionSlot: 60, eventSlot: 61, receiptSlot: 226)
            let validSupport = try r2Support(original: validOriginal, selected: validSelected, workRevision: 1)
            let validEndpoint = try FindingRelationshipEndpointReferenceV1(workID: validSupport.correctiveWorkID,
                workRevision: 1, owner: .correctiveAction(validSupport))
            try roundTrip(relationshipRecord(relation(source: endpointA, candidate: validEndpoint)))
        }
    }

    func testR2ActivityRevisionFactsRejectKindAndDigestConflictsOnBothSides() throws {
        let foreign = WorkspaceID(rawValue: id(99))
        for conflictInOriginal in [true, false] {
            for changeKind in [true, false] {
                let kind: ActivityKindV2 = changeKind ? .inspection : .punchReview
                let digest = changeKind ? a : b
                let originalA = try r2ActivityContext(workspace: foreign, activitySlot: 90)
                let selectedA = try r2ActivityContext(activitySlot: 90)
                let originalB = try r2ActivityContext(workspace: foreign, activitySlot: conflictInOriginal ? 90 : 91,
                    kind: kind, digest: conflictInOriginal ? digest : a)
                let selectedB = try r2ActivityContext(activitySlot: conflictInOriginal ? 91 : 90,
                    kind: kind, digest: conflictInOriginal ? a : digest)
                let left = try r2ActivityRecord("finding.one", ownerSlot: 30,
                    original: originalA, selected: selectedA, receiptSlot: 301)
                let right = try r2ActivityRecord("finding.two", ownerSlot: 31,
                    original: originalB, selected: selectedB, receiptSlot: 303)
                XCTAssertThrowsError(try FindingOwnerHistoryV1.validateHeads([left, right], workspaceID: workspace)) { error in
                    XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
                }
            }
        }
    }

    func testR2ActivityScopesReceiptsRevisionsAndWorkspacesStayIndependent() throws {
        let first = try r2ActivityContext(scope: "scope.one")
        let second = try r2ActivityContext(scope: "scope.two")
        let left = try r2ActivityRecord("finding.one", ownerSlot: 30, original: first, selected: first, receiptSlot: 311)
        let right = try r2ActivityRecord("finding.two", ownerSlot: 31, original: second, selected: second, receiptSlot: 313)
        try FindingOwnerHistoryV1.validateHeads([left, right], workspaceID: workspace)
        try roundTrip(left)
        try roundTrip(right)
        let later = try r2ActivityContext(revision: 4, digest: b, scope: "scope.three")
        let third = try r2ActivityRecord("finding.three", ownerSlot: 32, original: later, selected: later, receiptSlot: 315)
        try FindingOwnerHistoryV1.validateHeads([left, right, third], workspaceID: workspace)
        let foreign = WorkspaceID(rawValue: id(99))
        let original = try r2ActivityContext(workspace: foreign, digest: b, scope: "scope.two")
        let mapped = try r2ActivityRecord("finding.two", ownerSlot: 31, original: original, selected: second, receiptSlot: 317)
        try FindingOwnerHistoryV1.validateHeads([left, mapped], workspaceID: workspace)
        // These references carry independent receipt-shaped identities. None of
        // these value checks authenticates receipts, currentness or mapping.
    }

    private func r2OwnerReference(workspace: WorkspaceID? = nil, revision: UInt64 = 7,
                                  digest: String) throws -> FindingOwnerRevisionReferenceV1 {
        try FindingOwnerRevisionReferenceV1(workspaceID: workspace ?? self.workspace, kind: .finding,
            ownerID: id(31), ownerRevision: revision, recordSHA256: digest)
    }

    private func r2FindingEndpoint(_ workID: String, original: FindingOwnerRevisionReferenceV1? = nil,
                                   selected: FindingOwnerRevisionReferenceV1,
                                   receiptSlot: Int) throws -> FindingRelationshipEndpointReferenceV1 {
        let source = original ?? selected
        let originalAcceptance = try accepted(receiptSlot, workspace: source.workspaceID)
        let selectedAcceptance = try accepted(receiptSlot, workspace: selected.workspaceID)
        let reference = try FindingSelectedOwnerReferenceV1(original: source, selected: selected,
            originalAcceptance: originalAcceptance, selectedAcceptance: selectedAcceptance)
        return try FindingRelationshipEndpointReferenceV1(workID: workID, workRevision: 0, owner: .finding(reference))
    }

    private func r2CorrectiveReference(workspace: WorkspaceID? = nil, actionSlot: Int = 50,
                                       eventSlot: Int = 51, revision: UInt64 = 1, digest: String? = nil,
                                       receiptSlot: Int) throws -> FindingCorrectiveEventReferenceV1 {
        let local = workspace ?? self.workspace
        let acceptance = try accepted(receiptSlot, workspace: local)
        return try FindingCorrectiveEventReferenceV1(workspaceID: local, actionID: id(actionSlot), eventID: id(eventSlot),
            eventRevision: revision, eventSHA256: digest ?? a, acceptance: acceptance)
    }

    private func r2Support(original: FindingCorrectiveEventReferenceV1, selected: FindingCorrectiveEventReferenceV1,
                            workRevision: Int) throws -> FindingC14SupportReferenceV1 {
        try FindingC14SupportReferenceV1(correctiveWorkID: original.actionID.uuidString.lowercased(),
            correctiveWorkRevision: workRevision, original: original, selected: selected)
    }

    private func r2ActivityContext(workspace: WorkspaceID? = nil, activitySlot: Int = 90,
                                   revision: UInt64 = 3, kind: ActivityKindV2 = .punchReview,
                                   digest: String? = nil, scope: String? = nil) throws -> FindingSourceContextV1 {
        try FindingSourceContextV1(workspaceID: workspace ?? self.workspace, activityID: id(activitySlot),
            activityKind: kind, activityRevision: revision, activitySHA256: digest ?? a, taskOrScopeID: scope)
    }

    private func r2ActivityRecord(_ findingID: String, ownerSlot: Int, original: FindingSourceContextV1,
                                  selected: FindingSourceContextV1, receiptSlot: Int) throws -> FindingOwnerRecordV1 {
        let originalAcceptance = try accepted(receiptSlot, workspace: original.workspaceID)
        let selectedAcceptance = try accepted(receiptSlot + 1, workspace: selected.workspaceID)
        let source = try FindingActivitySourceReferenceV1(original: original, selected: selected,
            originalAcceptance: originalAcceptance, selectedAcceptance: selectedAcceptance)
        let facts = try FindingOwnedFactsV1(evidence: evidence(finding(findingID)), activitySource: source)
        return try record(facts: facts, ownerSlot: ownerSlot)
    }

    private func unknownVariants(_ value: Any) throws -> [Any] {
        var result: [Any] = []
        if let object = value as? [String: Any] {
            var extra = object
            extra["futureField"] = true
            result.append(extra)
            for key in object.keys.sorted() {
                for nested in try unknownVariants(XCTUnwrap(object[key])) {
                    var changed = object
                    changed[key] = nested
                    result.append(changed)
                }
            }
        } else if let array = value as? [Any] {
            for index in array.indices {
                for nested in try unknownVariants(array[index]) {
                    var changed = array
                    changed[index] = nested
                    result.append(changed)
                }
            }
        }
        return result
    }
}

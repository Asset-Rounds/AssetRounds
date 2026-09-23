import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Pure command/derivation checks. The fixtures are typed expectations, not
/// authenticated source owners, accepted receipts, or a production writer.
@MainActor
final class V23FindingOwnerMutationContractTests: XCTestCase {
    private let a = String(repeating: "a", count: 64)
    private let b = String(repeating: "b", count: 64)
    private let instant = "2026-09-22T12:00:00Z"
    private let findingID = "finding.non-uuid"
    private func id(_ slot: Int) -> UUID { UUID(uuidString: String(format: "CF490000-0000-4000-8000-%012d", slot))! }
    private var workspace: WorkspaceID { WorkspaceID(rawValue: id(1)) }
    private func mutation(_ slot: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(slot)) }
    private func actor(workspace: WorkspaceID? = nil, responsibility: ResponsibilityKindV1 = .recordedBy) throws -> ActorSnapshotV1 {
        let local = workspace ?? self.workspace
        let actor = try LocalActorReferenceV1(actorReferenceID: id(10), workspaceID: local, displayName: "Recorder")
        return try ActorSnapshotV1(snapshotID: id(11), workspaceID: local, actor: actor, responsibility: responsibility,
            displayNameAtTime: "Recorder", capturedAt: Date(timeIntervalSince1970: 0))
    }
    private func scale(workspace: WorkspaceID? = nil) throws -> SeverityScaleReleaseV1 {
        let level = try SeverityLevelDefinitionV1(levelID: "medium", localizedLabelKey: "severity.medium",
                                                  descriptionKey: "severity.medium.detail")
        return try SeverityScaleReleaseV1(releaseID: id(20), workspaceID: workspace ?? self.workspace,
            scaleID: id(21), designation: "Explicit scale", levels: [level], recordedAt: Date(timeIntervalSince1970: 0),
            revision: 2, mutationID: mutation(22))
    }
    private func creation(findingID: String? = nil, sourceID: String = "observation.new",
                          subjectRevision: UInt64 = 0, subjectHash: String? = nil,
                          classification: FindingClassificationBindingV1? = nil,
                          activitySource: FindingActivitySourceReferenceV1? = nil) throws -> FindingHumanObservationCreationV1 {
        let scale = try self.scale()
        let severity = try FindingSeverityBindingV1(severityID: "medium", severityScaleReleaseID: scale.releaseID.uuidString.lowercased(),
            severityScaleSHA256: scale.releaseSHA256)
        let subject = try FindingAssetSubjectSelectionV1(assetID: id(30), entityRevision: subjectRevision, postImageSHA256: subjectHash ?? a)
        return try FindingHumanObservationCreationV1(findingID: findingID ?? self.findingID, sourceID: sourceID,
            categoryID: "leak", summary: "New finding", severity: severity, severityScale: scale, subject: subject,
            classification: classification, activitySource: activitySource)
    }
    private func read(_ kind: WorkspaceEntityKindV1, _ slot: Int, _ revision: UInt64) throws -> WorkspaceEntityRevisionV1 {
        let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id(slot))
        return WorkspaceEntityRevisionV1(identity: identity, revision: revision)
    }
    private func expected(assetRevision: UInt64 = 0, extra: [WorkspaceEntityRevisionV1] = [],
                          workspaceRevision: UInt64 = 7) throws -> WorkspaceExpectedRevisionV1 {
        let entries = try [read(.actorSnapshot, 11, 1), read(.asset, 30, assetRevision), read(.severityScaleRelease, 20, 9)]
        return try WorkspaceExpectedRevisionV1(workspaceID: workspace, generationID: id(2), writerInstanceID: id(3),
            workspaceRevision: workspaceRevision, entityRevisions: entries + extra)
    }
    private func accepted(_ slot: Int, workspace: WorkspaceID? = nil) throws -> FindingAcceptedMutationReferenceV1 {
        try FindingAcceptedMutationReferenceV1(workspaceID: workspace ?? self.workspace, generationID: id(2),
            mutationID: mutation(slot), envelopeSHA256: a, receiptSHA256: b)
    }
    private func selected(_ record: FindingOwnerRecordV1) throws -> FindingSelectedOwnerReferenceV1 {
        let reference = try record.reference
        let acceptance = try FindingAcceptedMutationReferenceV1(workspaceID: record.workspaceID, generationID: id(2),
            mutationID: record.mutationID, envelopeSHA256: a, receiptSHA256: b)
        return try FindingSelectedOwnerReferenceV1(original: reference, selected: reference,
            originalAcceptance: acceptance, selectedAcceptance: acceptance)
    }
    private func command(_ operation: FindingOwnerOperationV1, prior: FindingOwnerRecordV1? = nil,
                         mutationSlot: Int = 100, frontier: WorkspaceExpectedRevisionV1? = nil) throws -> FindingOwnerMutationV1 {
        let predecessor: FindingSelectedOwnerReferenceV1?
        if let prior { predecessor = try selected(prior) } else { predecessor = nil }
        return try FindingOwnerMutationV1(workspaceID: workspace, expectedRevision: frontier ?? expected(),
            mutationID: mutation(mutationSlot), ownerID: id(40), predecessor: predecessor, recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: Double(mutationSlot - 99)), operation: operation)
    }
    private func create() throws -> FindingOwnerRecordV1 {
        try command(.createHumanObservation(creation())).derive(predecessor: nil)
    }
    private func transition(to state: FindingStateV1 = .correctiveWorkInProgress,
                            expected: Int = 0, from: FindingStateV1 = .open,
                            kernelMutation: String = "kernel.transition.one") throws -> FindingTransitionV1 {
        guard expected >= 0, expected < Int.max else { throw FindingContractFailureV1.invalidValue }
        return try FindingTransitionV1(transitionID: "transition.one", findingID: findingID,
            expectedFindingRevision: expected, resultingFindingRevision: expected + 1, mutationID: kernelMutation,
            fromState: from, toState: state, actorID: "actor.recorder", reason: "Explicit transition", effectiveAt: instant)
    }
    private func link(removed: Bool = false, workRevision: Int = 1) throws -> CorrectiveWorkLinkV1 {
        try CorrectiveWorkLinkV1(linkID: removed ? "link.removed" : "link.one", findingID: findingID, findingRevision: 0,
            workID: id(50).uuidString.lowercased(), workRevision: workRevision,
            expectedLinkRevision: removed ? 1 : 0, resultingLinkRevision: removed ? 2 : 1,
            mutationID: removed ? "kernel.remove.one" : "kernel.link.one", action: removed ? .removed : .linked,
            actorID: "actor.linker", reason: "Explicit link decision", effectiveAt: instant,
            supersedesLinkEventID: removed ? "link.one" : nil)
    }
    private func support() throws -> FindingC14SupportReferenceV1 {
        let acceptance = try accepted(150)
        let reference = try FindingCorrectiveEventReferenceV1(workspaceID: workspace, actionID: id(50), eventID: id(51),
            eventRevision: 1, eventSHA256: a, acceptance: acceptance)
        return try FindingC14SupportReferenceV1(correctiveWorkID: id(50).uuidString.lowercased(),
            correctiveWorkRevision: 1, original: reference, selected: reference)
    }
    private func linked() throws -> FindingOwnerRecordV1 {
        let initial = try create()
        let operation = try FindingC14LinkOperationV1(event: link(), support: support())
        let frontier = try expected(extra: [read(.correctiveActionEvent, 51, 1)])
        return try command(.linkC14CorrectiveWork(operation), prior: initial, mutationSlot: 101,
                           frontier: frontier).derive(predecessor: initial)
    }
    private func roundTrip(_ value: FindingOwnerMutationV1, prior: FindingOwnerRecordV1?) throws -> FindingOwnerRecordV1 {
        let bytes = try FindingOwnerMutationCanonicalCodecV1.encode(value)
        let decoded = try FindingOwnerMutationCanonicalCodecV1.decode(bytes)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try FindingOwnerMutationCanonicalCodecV1.encode(decoded), bytes)
        let result = try decoded.derive(predecessor: prior)
        let resultBytes = try FindingOwnerCanonicalCodecV1.encode(result)
        XCTAssertEqual(try FindingOwnerCanonicalCodecV1.decode(resultBytes), result)
        return result
    }
    private func object(_ value: FindingOwnerMutationV1) throws -> [String: Any] {
        let bytes = try FindingOwnerMutationCanonicalCodecV1.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
    private func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func rejected(_ value: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(json(value)), file: file, line: line)
    }

    func testFreshHumanCreationDerivesOnlyItsOriginalFacts() throws {
        let command = try self.command(.createHumanObservation(creation()))
        let result = try roundTrip(command, prior: nil)
        let facts = try XCTUnwrap(result.finding)
        XCTAssertEqual(result.kind, .finding)
        XCTAssertEqual(result.ownerID, id(40))
        XCTAssertEqual(result.ownerRevision, 1)
        XCTAssertNil(result.predecessor)
        XCTAssertEqual(result.origin.creationMutationID, try mutation(100))
        XCTAssertEqual(result.recordedBy, try actor())
        XCTAssertEqual(result.recordedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(facts.evidence.finding.findingID, "finding.non-uuid")
        XCTAssertEqual(facts.evidence.finding.revision, 0)
        XCTAssertEqual(facts.evidence.finding.source.kind, .humanObservation)
        XCTAssertEqual(facts.evidence.finding.source.sourceID, "observation.new")
        XCTAssertEqual(facts.evidence.finding.source.sourceRevision, 0)
        XCTAssertEqual(facts.evidence.finding.source.evidenceRevisionIDs, [])
        XCTAssertEqual(facts.evidence.finding.subject.subjectKindID, "asset")
        XCTAssertEqual(facts.evidence.finding.subject.subjectID, "cf490000-0000-4000-8000-000000000030")
        XCTAssertEqual(facts.evidence.finding.subject.subjectRevision, 0)
        XCTAssertEqual(facts.evidence.lifecycle.currentState, .open)
        XCTAssertTrue(facts.evidence.lifecycle.transitions.isEmpty)
        XCTAssertTrue(facts.evidence.correctiveWorkLinks.isEmpty)
        XCTAssertTrue(facts.evidence.verifiedRechecks.isEmpty)
        XCTAssertTrue(facts.evidence.releasesToService.isEmpty)
        XCTAssertTrue(facts.evidence.operationalDispositionEvents.isEmpty)
        XCTAssertTrue(facts.evidence.workRelationshipDecisions.isEmpty)
        XCTAssertTrue(facts.correctiveActions.isEmpty)
        XCTAssertNil(facts.activitySource)
        XCTAssertThrowsError(try command.derive(predecessor: result))
        // The selected release's lineage2 is distinct from its journal entity9.
        XCTAssertEqual(try scale().revision, 2)
        XCTAssertEqual(command.expectedRevision.entityRevisions.last?.revision, 9)
    }

    func testCanonicalCreationMatchesIndependentCommandAndRecordExpectations() throws {
        let request = try command(.createHumanObservation(creation()))
        let bytes = try FindingOwnerMutationCanonicalCodecV1.encode(request)
        XCTAssertEqual(bytes.count, 2_238)
        XCTAssertEqual(try request.canonicalSHA256(), "d394c4ad4de5ab23060808d1f00b4942d3100d1c9e3795957da85f044bac9d4c")
        let result = try roundTrip(request, prior: nil)
        XCTAssertEqual(result.recordSHA256, "9a521d544c1168173c111453027217ddfe58a91f3e31c5b805e65d46b7510cfd")
        let recordBytes = try FindingOwnerCanonicalCodecV1.encode(result)
        XCTAssertEqual(recordBytes.count, 1_893)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(recordBytes), "6f6c0036eb22aebc711ee45ea5a425a84c35022ba61510f12a324c0992703cc3")
        XCTAssertNotEqual(result.recordSHA256, KernelCanonicalHashV1.sha256(recordBytes))
        XCTAssertEqual(try result.reference.recordSHA256, result.recordSHA256)
    }

    func testLegalKernelStringsAndUnicodeTextBytesRemainExact() throws {
        let base = try creation()
        let input = try FindingHumanObservationCreationV1(findingID: "finding._-legacy", sourceID: "new-observation._1",
            categoryID: base.categoryID, summary: "cafe\u{0301}", severity: base.severity, severityScale: base.severityScale,
            subject: base.subject)
        let request = try command(.createHumanObservation(input))
        let result = try roundTrip(request, prior: nil)
        let finding = try XCTUnwrap(result.finding?.evidence.finding)
        XCTAssertEqual(finding.findingID, "finding._-legacy")
        XCTAssertEqual(finding.source.sourceID, "new-observation._1")
        XCTAssertEqual(Array(finding.summary.utf8), [99, 97, 102, 101, 204, 129])
        XCTAssertThrowsError(try creation(findingID: "Finding.UPPER"))
        XCTAssertThrowsError(try creation(sourceID: "observation.Ã©"))
        XCTAssertThrowsError(try creation(findingID: String(repeating: "f", count: 129)))
        XCTAssertThrowsError(try FindingAssetSubjectSelectionV1(assetID: id(30), entityRevision: 0, postImageSHA256: ""))
        XCTAssertThrowsError(try FindingAssetSubjectSelectionV1(assetID: id(30), entityRevision: 0,
            postImageSHA256: String(repeating: "A", count: 64)))
    }

    func testCreationOptionalClassificationAndActivityNeverBecomeUniversalIDGates() throws {
        let value = try scale()
        let classification = try FindingClassificationBindingV1(bindingID: id(70), workspaceID: workspace, findingID: id(71),
            criterionID: "criterion.one", result: .doesNotMeet, severityScaleReleaseID: value.releaseID,
            severityLevelID: "medium", applicabilityContextID: id(72), assessmentScopeID: id(73),
            recordedAt: Date(timeIntervalSince1970: 0), mutationID: mutation(74))
        let input = try creation(findingID: id(71).uuidString.lowercased(), classification: classification)
        let frontier = try expected(extra: [read(.findingClassificationBinding, 70, 4)])
        let classified = try command(.createHumanObservation(input), frontier: frontier)
        _ = try roundTrip(classified, prior: nil)
        XCTAssertThrowsError(try creation(classification: classification))
        _ = try creation()
        let context = try FindingSourceContextV1(workspaceID: workspace, activityID: id(60), activityKind: .punchReview,
            activityRevision: 3, activitySHA256: a, taskOrScopeID: "scope.one")
        let acceptance = try accepted(160)
        let source = try FindingActivitySourceReferenceV1(original: context, selected: context,
            originalAcceptance: acceptance, selectedAcceptance: acceptance)
        let withSource = try creation(activitySource: source)
        let sourceFrontier = try expected(extra: [read(.activitySessionEnvelope, 60, 3)])
        let sourced = try command(.createHumanObservation(withSource), frontier: sourceFrontier)
        let result = try roundTrip(sourced, prior: nil)
        XCTAssertEqual(result.finding?.activitySource, source)
        XCTAssertEqual(result.finding?.evidence.finding.source.kind, .humanObservation)
        XCTAssertThrowsError(try command(.createHumanObservation(withSource)))
        for value in [classified, sourced] {
            for variant in unknownVariants(try object(value)) {
                try rejected(XCTUnwrap(variant as? [String: Any]))
            }
        }
    }

    func testCreationRejectsSubstitutedScaleSubjectWorkspaceAndAttribution() throws {
        let value = try creation()
        let foreign = WorkspaceID(rawValue: id(99))
        let wrongScale = try scale(workspace: foreign)
        XCTAssertThrowsError(try FindingHumanObservationCreationV1(findingID: findingID, sourceID: "observation.new",
            categoryID: "leak", summary: "New finding", severity: value.severity, severityScale: wrongScale, subject: value.subject))
        let wrongSubject = try creation(subjectRevision: 1)
        XCTAssertThrowsError(try command(.createHumanObservation(wrongSubject)))
        XCTAssertThrowsError(try FindingOwnerMutationV1(workspaceID: workspace, expectedRevision: expected(),
            mutationID: mutation(100), ownerID: id(40), recordedBy: actor(workspace: foreign),
            recordedAt: Date(timeIntervalSince1970: 1), operation: .createHumanObservation(value)))
        XCTAssertThrowsError(try FindingOwnerMutationV1(workspaceID: workspace, expectedRevision: expected(),
            mutationID: mutation(100), ownerID: id(40), recordedBy: actor(responsibility: .verifiedBy),
            recordedAt: Date(timeIntervalSince1970: 1), operation: .createHumanObservation(value)))
        XCTAssertThrowsError(try FindingOwnerMutationV1(workspaceID: workspace, expectedRevision: expected(),
            mutationID: mutation(100), ownerID: id(40), recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: -1), operation: .createHumanObservation(value)))
    }

    func testTransitionDerivesOneRevisionWithoutReplacingAnyOtherFact() throws {
        let initial = try create()
        let event = try transition()
        let operation = try FindingTransitionOperationV1(event: event)
        let command = try self.command(.transitionFinding(operation), prior: initial, mutationSlot: 101)
        let result = try roundTrip(command, prior: initial)
        let old = try XCTUnwrap(initial.finding)
        let new = try XCTUnwrap(result.finding)
        XCTAssertEqual(result.ownerRevision, 2)
        XCTAssertEqual(result.predecessor, try initial.reference)
        XCTAssertEqual(result.origin, initial.origin)
        XCTAssertEqual(new.evidence.finding.revision, 1)
        XCTAssertEqual(new.evidence.lifecycle.transitions, [event])
        XCTAssertEqual(new.evidence.finding.source, old.evidence.finding.source)
        XCTAssertEqual(new.evidence.finding.subject, old.evidence.finding.subject)
        XCTAssertEqual(new.evidence.finding.summary, "New finding")
        XCTAssertEqual(new.evidence.correctiveWorkLinks, old.evidence.correctiveWorkLinks)
        XCTAssertEqual(new.evidence.verifiedRechecks, old.evidence.verifiedRechecks)
        XCTAssertEqual(new.evidence.operationalDispositionEvents, old.evidence.operationalDispositionEvents)
        XCTAssertEqual(new.activitySource, old.activitySource)
        XCTAssertEqual(new.correctiveActions, old.correctiveActions)
        // Kernel attribution and mutation Strings remain separate from UUIDs.
        XCTAssertEqual(new.evidence.lifecycle.transitions[0].actorID, "actor.recorder")
        XCTAssertEqual(new.evidence.lifecycle.transitions[0].mutationID, "kernel.transition.one")
        XCTAssertEqual(result.mutationID, try mutation(101))
        XCTAssertThrowsError(try command.derive(predecessor: result))
        XCTAssertThrowsError(try command.derive(predecessor: nil))
    }

    func testCorrectiveLinkAndRemovalPreserveFindingRevisionAndOriginalSupport() throws {
        let initial = try create()
        let support = try self.support()
        let event = try link()
        let operation = try FindingC14LinkOperationV1(event: event, support: support)
        let frontier = try expected(extra: [read(.correctiveActionEvent, 51, 1)])
        let linked = try roundTrip(command(.linkC14CorrectiveWork(operation), prior: initial, mutationSlot: 101,
                                          frontier: frontier), prior: initial)
        XCTAssertEqual(linked.ownerRevision, 2)
        XCTAssertEqual(linked.finding?.evidence.finding, initial.finding?.evidence.finding)
        XCTAssertEqual(linked.finding?.evidence.correctiveWorkLinks, [event])
        XCTAssertEqual(linked.finding?.correctiveActions, [support])
        let removal = try link(removed: true)
        let removed = try roundTrip(command(.removeCorrectiveWork(removal), prior: linked, mutationSlot: 102), prior: linked)
        XCTAssertEqual(removed.ownerRevision, 3)
        XCTAssertEqual(removed.finding?.evidence.finding.revision, 0)
        XCTAssertEqual(removed.finding?.evidence.correctiveWorkLinks, [event, removal])
        XCTAssertEqual(removed.finding?.correctiveActions, [support])
        XCTAssertEqual(removed.finding?.evidence.lifecycle.currentState, .open)
        XCTAssertEqual(removed.origin, initial.origin)
        try FindingOwnerHistoryV1.validate([initial, linked, removed])
    }

    func testCorrectiveOperationsRejectWrongRolesRevisionsMissingReadsAndStaleBasis() throws {
        let initial = try create()
        let valid = try FindingC14LinkOperationV1(event: link(), support: support())
        XCTAssertThrowsError(try command(.linkC14CorrectiveWork(valid), prior: initial, mutationSlot: 101))
        XCTAssertThrowsError(try FindingC14LinkOperationV1(event: link(removed: true), support: support()))
        XCTAssertThrowsError(try FindingC14LinkOperationV1(event: link(workRevision: 2), support: support()))
        XCTAssertThrowsError(try command(.removeCorrectiveWork(link()), prior: initial, mutationSlot: 101))
        let removal = try command(.removeCorrectiveWork(link(removed: true)), prior: initial, mutationSlot: 101)
        XCTAssertThrowsError(try removal.derive(predecessor: initial))
        let linked = try self.linked()
        let wrongRemoval = try command(.removeCorrectiveWork(link(removed: true, workRevision: 2)), prior: linked, mutationSlot: 102)
        XCTAssertThrowsError(try wrongRemoval.derive(predecessor: linked))
        let advanced = try command(.transitionFinding(FindingTransitionOperationV1(event: self.transition())),
            prior: initial, mutationSlot: 101).derive(predecessor: initial)
        let frontier = try expected(extra: [read(.correctiveActionEvent, 51, 1)])
        let stale = try command(.linkC14CorrectiveWork(valid), prior: advanced, mutationSlot: 102, frontier: frontier)
        XCTAssertThrowsError(try stale.derive(predecessor: advanced))
    }

    func testExactPredecessorAndMutationMetadataCannotBeSubstituted() throws {
        let initial = try create()
        let operation = try FindingOwnerOperationV1.transitionFinding(FindingTransitionOperationV1(event: self.transition()))
        let command = try self.command(operation, prior: initial, mutationSlot: 101)
        let replacement = try self.command(.createHumanObservation(creation(sourceID: "observation.other"))).derive(predecessor: nil)
        XCTAssertThrowsError(try command.derive(predecessor: replacement))
        let reused = try self.command(operation, prior: initial, mutationSlot: 100)
        XCTAssertThrowsError(try reused.derive(predecessor: initial))
        let wrongOwner = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
            ownerID: id(41), ownerRevision: 1, recordSHA256: initial.recordSHA256)
        let receipt = try accepted(100)
        let selected = try FindingSelectedOwnerReferenceV1(original: wrongOwner, selected: wrongOwner,
            originalAcceptance: receipt, selectedAcceptance: receipt)
        XCTAssertThrowsError(try FindingOwnerMutationV1(workspaceID: workspace, expectedRevision: expected(),
            mutationID: mutation(101), ownerID: id(40), predecessor: selected, recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), operation: operation))
        XCTAssertThrowsError(try self.command(.createHumanObservation(creation()), prior: initial))
    }

    func testVerifiedResolutionRequiresTheExactRetainedPassedRecheck() throws {
        let linked = try self.linked()
        let awaitingEvent = try transition(to: .awaitingVerifiedRecheck)
        let awaiting = try command(.transitionFinding(FindingTransitionOperationV1(event: awaitingEvent)),
            prior: linked, mutationSlot: 102).derive(predecessor: linked)
        let recheck = try VerifiedRecheckV1(recheckID: "recheck.actual", findingID: findingID, findingRevision: 1,
            correctiveWorkID: id(50).uuidString.lowercased(), correctiveWorkRevision: 1,
            evidenceRevisionIDs: ["evidence.retained"], mutationID: "kernel.recheck.one", outcome: .passed,
            verifierActorID: "verifier.actual", verifierAuthority: "Recorded authority", reason: "Measured result", effectiveAt: instant)
        let old = try XCTUnwrap(awaiting.finding)
        let evidence = try FindingLifecycleCanonicalEvidenceV1(finding: old.evidence.finding, lifecycle: old.evidence.lifecycle,
            correctiveWorkLinks: old.evidence.correctiveWorkLinks, verifiedRechecks: [recheck])
        let facts = try FindingOwnedFactsV1(evidence: evidence, correctiveActions: old.correctiveActions)
        // Fixture for a separately accepted recheck owner revision. This command
        // slice has no recordRecheck operation or evidence-authentication claim.
        let prior = try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: id(40), ownerRevision: 4,
            predecessor: awaiting.reference, mutationID: mutation(103), recordedBy: actor(), recordedAt: Date(timeIntervalSince1970: 4),
            origin: awaiting.origin, finding: facts)
        try prior.validateAppendOnlySuccessor(of: awaiting)
        let reference = try FindingVerifiedRecheckReferenceV1(owner: prior.reference, recheckID: recheck.recheckID,
            resultingRecheckRevision: 1, recheckSHA256: WorkspaceMutationCanonicalV1.sha256(recheck))
        let event = try FindingTransitionV1(transitionID: "transition.resolved", findingID: findingID,
            expectedFindingRevision: 1, resultingFindingRevision: 2, mutationID: "kernel.resolve.one",
            fromState: .awaitingVerifiedRecheck, toState: .verifiedResolved, actorID: "actor.recorder", reason: "Explicit resolution",
            effectiveAt: instant, verifiedRecheck: recheck)
        let operation = try FindingTransitionOperationV1(event: event, verifiedRecheck: reference)
        let result = try roundTrip(command(.transitionFinding(operation), prior: prior, mutationSlot: 104), prior: prior)
        XCTAssertEqual(result.finding?.evidence.finding.revision, 2)
        XCTAssertEqual(result.finding?.evidence.lifecycle.currentState, .verifiedResolved)
        XCTAssertEqual(result.finding?.evidence.verifiedRechecks, [recheck])
        XCTAssertThrowsError(try FindingTransitionOperationV1(event: event))
        let wrong = try FindingVerifiedRecheckReferenceV1(owner: prior.reference, recheckID: recheck.recheckID,
            resultingRecheckRevision: 1, recheckSHA256: b)
        let bad = try FindingTransitionOperationV1(event: event, verifiedRecheck: wrong)
        let rejected = try command(.transitionFinding(bad), prior: prior, mutationSlot: 104)
        XCTAssertThrowsError(try rejected.derive(predecessor: prior))
        for outcome in [VerifiedRecheckOutcomeV1.failed, .inconclusive] {
            let failed = try VerifiedRecheckV1(recheckID: recheck.recheckID, findingID: findingID, findingRevision: 1,
                correctiveWorkID: recheck.correctiveWorkID, correctiveWorkRevision: 1,
                evidenceRevisionIDs: recheck.evidenceRevisionIDs, mutationID: recheck.mutationID, outcome: outcome,
                verifierActorID: recheck.verifierActorID, verifierAuthority: recheck.verifierAuthority,
                reason: recheck.reason, effectiveAt: instant)
            let failedEvidence = try FindingLifecycleCanonicalEvidenceV1(finding: old.evidence.finding,
                lifecycle: old.evidence.lifecycle, correctiveWorkLinks: old.evidence.correctiveWorkLinks, verifiedRechecks: [failed])
            let failedFacts = try FindingOwnedFactsV1(evidence: failedEvidence, correctiveActions: old.correctiveActions)
            let failedPrior = try FindingOwnerRecordV1(workspaceID: workspace, kind: .finding, ownerID: id(40), ownerRevision: 4,
                predecessor: awaiting.reference, mutationID: mutation(103), recordedBy: actor(), recordedAt: Date(timeIntervalSince1970: 4),
                origin: awaiting.origin, finding: failedFacts)
            let failedReference = try FindingVerifiedRecheckReferenceV1(owner: failedPrior.reference, recheckID: failed.recheckID,
                resultingRecheckRevision: 1, recheckSHA256: WorkspaceMutationCanonicalV1.sha256(failed))
            let attempt = try FindingTransitionOperationV1(event: event, verifiedRecheck: failedReference)
            let request = try command(.transitionFinding(attempt), prior: failedPrior, mutationSlot: 104)
            XCTAssertThrowsError(try request.derive(predecessor: failedPrior)) { error in
                XCTAssertEqual(error as? FindingContractFailureV1, .recheckRequired)
            }
        }
    }

    func testCanonicalCommandBindsDependenciesAndAttributionWithoutClaimingAuthenticity() throws {
        let first = try command(.createHumanObservation(creation()))
        let changedSubjectHash = try command(.createHumanObservation(creation(subjectHash: b)))
        XCTAssertNotEqual(try first.canonicalSHA256(), try changedSubjectHash.canonicalSHA256())
        // Post-image hashes need actual writer comparison. The same scalar
        // Finding fields alone cannot establish which asset bytes were selected.
        XCTAssertEqual(try first.derive(predecessor: nil), try changedSubjectHash.derive(predecessor: nil))
        let otherMutation = try command(.createHumanObservation(creation()), mutationSlot: 101)
        XCTAssertNotEqual(try first.canonicalSHA256(), try otherMutation.canonicalSHA256())
        let initial = try create()
        let one = try command(.transitionFinding(FindingTransitionOperationV1(event: self.transition())), prior: initial, mutationSlot: 101)
        let two = try command(.transitionFinding(FindingTransitionOperationV1(event: transition(kernelMutation: "kernel.other"))),
            prior: initial, mutationSlot: 101)
        XCTAssertNotEqual(try one.canonicalSHA256(), try two.canonicalSHA256())
    }

    func testClosedCommandAndOperationWireRejectReplacementSourceAndProofFields() throws {
        let value = try command(.createHumanObservation(creation()))
        let original = try object(value)
        let expected: Set<String> = ["workspaceID", "expectedRevision", "mutationID", "ownerID", "recordedBy", "recordedAt", "operation"]
        XCTAssertEqual(Set(original.keys), expected)
        for key in expected {
            var absent = original
            absent.removeValue(forKey: key)
            try rejected(absent)
            var null = original
            null[key] = NSNull()
            try rejected(null)
        }
        for field in ["record", "evidence", "authenticated", "schemaVersion", "predecessor"] {
            var changed = original
            if field == "predecessor" { changed[field] = NSNull() } else { changed[field] = true }
            try rejected(changed)
        }
        var operation = try XCTUnwrap(original["operation"] as? [String: Any])
        XCTAssertEqual(Set(operation.keys), ["kind", "createHumanObservation"])
        var creation = try XCTUnwrap(operation["createHumanObservation"] as? [String: Any])
        for field in ["sourceKind", "sourceRevision", "evidenceRevisionIDs", "lifecycle", "findingRevision", "correctiveWorkLinks"] {
            var payload = creation
            payload[field] = "IMPORTED_RECORD"
            var op = operation
            op["createHumanObservation"] = payload
            var raw = original
            raw["operation"] = op
            try rejected(raw)
        }
        creation["classification"] = NSNull()
        operation["createHumanObservation"] = creation
        var null = original
        null["operation"] = operation
        try rejected(null)
        for tag in ["replaceFinding", "recordVerifiedRecheck", "confirmRelationship", "CREATE_HUMAN_OBSERVATION"] {
            var raw = original
            var op = try XCTUnwrap(raw["operation"] as? [String: Any])
            op["kind"] = tag
            raw["operation"] = op
            try rejected(raw)
        }
    }

    func testNestedUnknownFieldsAndNoncanonicalBytesRejectThroughActualCodec() throws {
        let initial = try create()
        let creation = try command(.createHumanObservation(self.creation()))
        let transition = try command(.transitionFinding(FindingTransitionOperationV1(event: self.transition())), prior: initial, mutationSlot: 101)
        let link = try FindingC14LinkOperationV1(event: self.link(), support: support())
        let frontier = try expected(extra: [read(.correctiveActionEvent, 51, 1)])
        let linking = try command(.linkC14CorrectiveWork(link), prior: initial, mutationSlot: 101, frontier: frontier)
        let linked = try linking.derive(predecessor: initial)
        let removing = try command(.removeCorrectiveWork(self.link(removed: true)), prior: linked, mutationSlot: 102)
        for value in [creation, transition, linking, removing] {
            let raw = try object(value)
            for variant in unknownVariants(raw) {
                try rejected(XCTUnwrap(variant as? [String: Any]))
            }
        }
        let bytes = try FindingOwnerMutationCanonicalCodecV1.encode(creation)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(Data((text + "\n").utf8)))
        let duplicate = "{\"ownerID\":\"" + id(40).uuidString + "\"," + String(text.dropFirst())
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(Data(duplicate.utf8)))
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(Data()))
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(Data(repeating: 0x20,
            count: FindingContractLimitsV1.maximumCanonicalBytes + 1)))
    }

    func testRevisionBoundsRejectBeforeLegacyIncrementAndPreserveAssetZero() throws {
        let limit = UInt64(Int.max)
        let atLimit = try creation(subjectRevision: limit)
        let frontier = try expected(assetRevision: limit)
        let result = try command(.createHumanObservation(atLimit), frontier: frontier).derive(predecessor: nil)
        XCTAssertEqual(result.finding?.evidence.finding.subject.subjectRevision, Int.max)
        XCTAssertThrowsError(try FindingAssetSubjectSelectionV1(assetID: id(30), entityRevision: UInt64.max, postImageSHA256: a))
        XCTAssertThrowsError(try command(.createHumanObservation(creation()), frontier: expected(workspaceRevision: UInt64.max)))
        let initial = try create()
        let transition = try command(.transitionFinding(FindingTransitionOperationV1(event: self.transition())), prior: initial, mutationSlot: 101)
        var raw = try object(transition)
        var operation = try XCTUnwrap(raw["operation"] as? [String: Any])
        var payload = try XCTUnwrap(operation["transitionFinding"] as? [String: Any])
        var event = try XCTUnwrap(payload["event"] as? [String: Any])
        event["expectedFindingRevision"] = NSNumber(value: Int.max)
        payload["event"] = event
        operation["transitionFinding"] = payload
        raw["operation"] = operation
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(json(raw))) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .invalidValue)
        }
        let removal = try command(.removeCorrectiveWork(link(removed: true)), prior: initial, mutationSlot: 101)
        raw = try object(removal)
        operation = try XCTUnwrap(raw["operation"] as? [String: Any])
        event = try XCTUnwrap(operation["removeCorrectiveWork"] as? [String: Any])
        event["expectedLinkRevision"] = NSNumber(value: Int.max)
        operation["removeCorrectiveWork"] = event
        raw["operation"] = operation
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(json(raw))) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .invalidValue)
        }
        let maximum = try FindingOwnerRevisionReferenceV1(workspaceID: workspace, kind: .finding,
            ownerID: id(40), ownerRevision: UInt64.max, recordSHA256: a)
        let acceptance = try accepted(100)
        let selected = try FindingSelectedOwnerReferenceV1(original: maximum, selected: maximum,
            originalAcceptance: acceptance, selectedAcceptance: acceptance)
        XCTAssertThrowsError(try FindingOwnerMutationV1(workspaceID: workspace, expectedRevision: expected(),
            mutationID: mutation(101), ownerID: id(40), predecessor: selected, recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), operation: transition.operation))
    }

    func testFrontierDuplicateConflictsUnknownIdentitiesAndMissingDependencyFailClosed() throws {
        let original = try object(command(.createHumanObservation(creation())))
        var raw = original
        var frontier = try XCTUnwrap(raw["expectedRevision"] as? [String: Any])
        var entries = try XCTUnwrap(frontier["entityRevisions"] as? [[String: Any]])
        entries.append(try XCTUnwrap(entries.first))
        frontier["entityRevisions"] = entries
        raw["expectedRevision"] = frontier
        try rejected(raw)
        raw = original
        frontier = try XCTUnwrap(raw["expectedRevision"] as? [String: Any])
        frontier["entityRevisions"] = []
        raw["expectedRevision"] = frontier
        try rejected(raw)
        raw = original
        frontier = try XCTUnwrap(raw["expectedRevision"] as? [String: Any])
        frontier["entityRevisions"] = Array(repeating: try XCTUnwrap(entries.first), count: 2)
        raw["expectedRevision"] = frontier
        try rejected(raw)
        raw = original
        frontier = try XCTUnwrap(raw["expectedRevision"] as? [String: Any])
        frontier["writerInstanceID"] = "00000000-0000-0000-0000-000000000000"
        raw["expectedRevision"] = frontier
        try rejected(raw)
        raw = original
        frontier = try XCTUnwrap(raw["expectedRevision"] as? [String: Any])
        entries = try XCTUnwrap(frontier["entityRevisions"] as? [[String: Any]])
        var entry = try XCTUnwrap(entries.first)
        var identity = try XCTUnwrap(entry["identity"] as? [String: Any])
        identity["kind"] = "findingOwner"
        entry["identity"] = identity
        entries[0] = entry
        frontier["entityRevisions"] = entries
        raw["expectedRevision"] = frontier
        try rejected(raw)
    }

    func testWholeWorkspaceFrontierExceedsRegistryCountAndRetainsCanonicalByteLimit() throws {
        let operation = try FindingOwnerOperationV1.createHumanObservation(creation())
        var entries: [WorkspaceEntityRevisionV1] = []
        for index in 0..<1_100 { entries.append(try read(.asset, 1_000 + index, 0)) }
        let request = try command(operation, frontier: expected(extra: entries))
        XCTAssertEqual(request.expectedRevision.entityRevisions.count, 1_103)
        XCTAssertGreaterThan(request.expectedRevision.entityRevisions.count, FindingContractLimitsV1.maximumRegistryEntries)
        let bytes = try FindingOwnerMutationCanonicalCodecV1.encode(request)
        XCTAssertLessThan(bytes.count, FindingContractLimitsV1.maximumCanonicalBytes)
        let result = try roundTrip(request, prior: nil)
        XCTAssertEqual(result.ownerRevision, 1)
        XCTAssertEqual(result.finding?.evidence.finding.subject.subjectRevision, 0)

        for index in 1_100..<16_000 { entries.append(try read(.asset, 1_000 + index, 0)) }
        let oversized = try command(operation, frontier: expected(extra: entries))
        let oversizedBytes = try WorkspaceMutationCanonicalV1.data(oversized)
        XCTAssertGreaterThan(oversizedBytes.count, FindingContractLimitsV1.maximumCanonicalBytes)
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.encode(oversized)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .limitExceeded)
        }
        XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(oversizedBytes)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .limitExceeded)
        }
    }

    func testCommandAcceptanceCensusRejectsEveryPredecessorAndSupportOverlap() throws {
        let initial = try create()
        let reference = try initial.reference
        let originalAcceptance = try accepted(100)
        let selectedAcceptance = try accepted(160)
        let predecessor = try FindingSelectedOwnerReferenceV1(original: reference, selected: reference,
            originalAcceptance: originalAcceptance, selectedAcceptance: selectedAcceptance)
        let originalSupportAcceptance = try accepted(150)
        let selectedSupportAcceptance = try accepted(151)
        let baseSupport = try support(originalAcceptance: originalSupportAcceptance, selectedAcceptance: selectedSupportAcceptance)
        let base = try linking(predecessor: predecessor, support: baseSupport)
        let original = try object(base)
        for overlap in [originalAcceptance, selectedAcceptance] {
            let generationConflict = try FindingAcceptedMutationReferenceV1(workspaceID: overlap.workspaceID,
                generationID: id(99), mutationID: overlap.mutationID, envelopeSHA256: overlap.envelopeSHA256,
                receiptSHA256: overlap.receiptSHA256)
            let envelopeConflict = try FindingAcceptedMutationReferenceV1(workspaceID: overlap.workspaceID,
                generationID: overlap.generationID, mutationID: overlap.mutationID, envelopeSHA256: b,
                receiptSHA256: overlap.receiptSHA256)
            let receiptConflict = try FindingAcceptedMutationReferenceV1(workspaceID: overlap.workspaceID,
                generationID: overlap.generationID, mutationID: overlap.mutationID,
                envelopeSHA256: overlap.envelopeSHA256, receiptSHA256: a)
            for conflict in [generationConflict, envelopeConflict, receiptConflict] {
                for side in ["original", "selected"] {
                    let first = side == "original" ? conflict : originalSupportAcceptance
                    let second = side == "selected" ? conflict : selectedSupportAcceptance
                    // Each support pair is valid in isolation: its two receipt keys differ.
                    let input = try support(originalAcceptance: first, selectedAcceptance: second)
                    XCTAssertThrowsError(try linking(predecessor: predecessor, support: input)) { error in
                        XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
                    }
                    var raw = original
                    var operation = try XCTUnwrap(raw["operation"] as? [String: Any])
                    var payload = try XCTUnwrap(operation["linkC14CorrectiveWork"] as? [String: Any])
                    var rawSupport = try XCTUnwrap(payload["support"] as? [String: Any])
                    var event = try XCTUnwrap(rawSupport[side] as? [String: Any])
                    let acceptanceBytes = try WorkspaceMutationCanonicalV1.data(conflict)
                    event["acceptance"] = try JSONSerialization.jsonObject(with: acceptanceBytes)
                    rawSupport[side] = event
                    payload["support"] = rawSupport
                    operation["linkC14CorrectiveWork"] = payload
                    raw["operation"] = operation
                    // The real decoder rejects before an invalid command can reach derivation.
                    XCTAssertThrowsError(try FindingOwnerMutationCanonicalCodecV1.decode(json(raw)).derive(predecessor: initial)) { error in
                        XCTAssertEqual(error as? FindingContractFailureV1, .historyRewrite)
                    }
                }
            }
        }
    }

    func testCommandAcceptanceCensusAllowsExactOverlapAndDistinctKeysThroughDerivation() throws {
        let initial = try create()
        let reference = try initial.reference
        let originalAcceptance = try accepted(100)
        let selectedAcceptance = try accepted(160)
        let predecessor = try FindingSelectedOwnerReferenceV1(original: reference, selected: reference,
            originalAcceptance: originalAcceptance, selectedAcceptance: selectedAcceptance)
        let overlap = try support(originalAcceptance: originalAcceptance, selectedAcceptance: selectedAcceptance)
        let reversedOverlap = try support(originalAcceptance: selectedAcceptance, selectedAcceptance: originalAcceptance)
        let distinctMutationKey = try FindingAcceptedMutationReferenceV1(workspaceID: workspace,
            generationID: id(99), mutationID: mutation(150), envelopeSHA256: b, receiptSHA256: a)
        let distinctMutationKeys = try support(originalAcceptance: distinctMutationKey, selectedAcceptance: accepted(151))
        let otherWorkspace = WorkspaceID(rawValue: id(98))
        let distinctWorkspaceKey = try FindingAcceptedMutationReferenceV1(workspaceID: otherWorkspace,
            generationID: id(99), mutationID: mutation(100), envelopeSHA256: b, receiptSHA256: a)
        let distinctWorkspace = try support(originalAcceptance: distinctWorkspaceKey, selectedAcceptance: accepted(150))
        for support in [overlap, reversedOverlap, distinctMutationKeys, distinctWorkspace] {
            let request = try linking(predecessor: predecessor, support: support)
            try request.validate()
            let result = try roundTrip(request, prior: initial)
            XCTAssertEqual(result.ownerRevision, 2)
            XCTAssertEqual(result.predecessor, reference)
            XCTAssertEqual(result.finding?.correctiveActions, [support])
            XCTAssertEqual(result.finding?.evidence.correctiveWorkLinks, [try link()])
        }
    }

    private func support(originalAcceptance: FindingAcceptedMutationReferenceV1,
                         selectedAcceptance: FindingAcceptedMutationReferenceV1) throws -> FindingC14SupportReferenceV1 {
        let original = try FindingCorrectiveEventReferenceV1(workspaceID: originalAcceptance.workspaceID,
            actionID: id(50), eventID: id(51), eventRevision: 1, eventSHA256: a, acceptance: originalAcceptance)
        let selected = try FindingCorrectiveEventReferenceV1(workspaceID: selectedAcceptance.workspaceID,
            actionID: id(50), eventID: id(51), eventRevision: 1, eventSHA256: a, acceptance: selectedAcceptance)
        return try FindingC14SupportReferenceV1(correctiveWorkID: id(50).uuidString.lowercased(),
            correctiveWorkRevision: 1, original: original, selected: selected)
    }

    private func linking(predecessor: FindingSelectedOwnerReferenceV1,
                         support: FindingC14SupportReferenceV1) throws -> FindingOwnerMutationV1 {
        let operation = try FindingC14LinkOperationV1(event: link(), support: support)
        let frontier = try expected(extra: [read(.correctiveActionEvent, 51, 1)])
        return try FindingOwnerMutationV1(workspaceID: workspace, expectedRevision: frontier,
            mutationID: mutation(101), ownerID: id(40), predecessor: predecessor, recordedBy: actor(),
            recordedAt: Date(timeIntervalSince1970: 2), operation: .linkC14CorrectiveWork(operation))
    }

    private func unknownVariants(_ value: Any) -> [Any] {
        var result: [Any] = []
        if let object = value as? [String: Any] {
            var extra = object
            extra["futureField"] = true
            result.append(extra)
            for key in object.keys.sorted() {
                guard let item = object[key] else { continue }
                for nested in unknownVariants(item) {
                    var changed = object
                    changed[key] = nested
                    result.append(changed)
                }
            }
        } else if let array = value as? [Any] {
            for index in array.indices {
                for nested in unknownVariants(array[index]) {
                    var changed = array
                    changed[index] = nested
                    result.append(changed)
                }
            }
        }
        return result
    }
}

import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_97PunchReviewWorkflowTests: XCTestCase {
    func testV23P04C34G01StandalonePreparationDecisionCorrectionRecheckCloseoutAndReport() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "G01", "GOLDEN")
        let h = try C34Harness()
        var p = try h.projection()
        XCTAssertTrue(p.canStart); XCTAssertFalse(p.installationSnapshotAvailable)
        XCTAssertEqual(p.planDisposition, .manualFallback); XCTAssertFalse(p.reportReady)
        try await h.accept(.start(try h.lifecycle(to: .inProgress, slot: 501)))
        let facts = try h.resolvedFacts(slot: 510)
        try await h.accept(.recordBasisVariation(facts.mutation), facts: facts)
        p = try h.projection()
        XCTAssertEqual(p.report.unresolvedFindingCount, 0)
        XCTAssertEqual(p.report.resolvedFindingCount, 1)
        XCTAssertEqual(p.report.correctiveActionSHA256s, h.context.correctiveActionEvents.map(\.eventSHA256))
        XCTAssertEqual(p.report.verifiedRecheckSHA256s.count, 1)
        XCTAssertEqual(p.nextCloseoutAction, .recordFieldComplete)
        try await h.accept(.closeout(try h.lifecycle(to: .fieldComplete, slot: 520)))
        XCTAssertEqual(try h.projection().nextCloseoutAction, .submitForReview)
        try await h.accept(.closeout(try h.lifecycle(to: .readyForReview, slot: 521)))
        XCTAssertEqual(try h.projection().nextCloseoutAction, .finalizeRecordedCloseout)
        let closeout = try h.closeout()
        let completed = try h.completedSnapshot(sourceRevision: Int(h.context.envelope.revision + 1))
        let reference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
            completed, activityCloseoutSHA256: closeout.closeoutSHA256
        )
        try await h.accept(.closeout(try h.lifecycle(
            to: .finalized, slot: 522, closeout: closeout, completedReference: reference
        )))
        p = try h.projection()
        XCTAssertEqual(p.envelope.state, .finalized); XCTAssertTrue(p.reportReady)
        XCTAssertEqual(p.reportReadiness, .readyForExistingRenderer)
        XCTAssertEqual(p.report.closeoutSHA256, closeout.closeoutSHA256)
        XCTAssertFalse(p.report.claimsSafe); XCTAssertFalse(p.report.claimsCompliant)
        XCTAssertFalse(p.report.claimsApproved); XCTAssertFalse(p.report.claimsAccepted)
        XCTAssertEqual(h.memory.effectCounts.count, 5)
        XCTAssertTrue(h.memory.effectCounts.values.allSatisfy { $0 == 1 })
    }

    func testV23P04C34A01OptionalInstallationSnapshotIsReadOnlyAndStandaloneRemainsValid() throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "A01", "ALTERNATE")
        let standalone = try C34Harness()
        let linked = try standalone.installationSnapshot(slot: 600)
        let context = try standalone.contextWith(installationSnapshot: linked)
        let projection = try standalone.workflow.projection(for: context)
        XCTAssertTrue(projection.installationSnapshotAvailable)
        XCTAssertEqual(projection.report.installationSnapshotSHA256, linked.completedSnapshot.snapshotSHA256)
        XCTAssertEqual(linked.envelope.state, .finalized)
        XCTAssertEqual(context.basis.source, standalone.context.basis.source)
        XCTAssertEqual(context.envelope, standalone.context.envelope)
    }

    func testV23P04C34H01StaleWrongAssetConflictingRecheckAndUnresolvedCountFailWithoutEffect() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "H01", "HOSTILE")
        let h = try C34Harness(); try await h.accept(.start(try h.lifecycle(to: .inProgress, slot: 701)))
        let before = h.memory.effectCounts
        let incomplete = try h.contextWith(scopeDecisions: [])
        do {
            _ = try await h.workflow.execute(.closeout(try h.lifecycle(to: .fieldComplete, slot: 702)), context: incomplete)
            XCTFail("Incomplete scope count must fail closed")
        } catch { XCTAssertEqual(error as? PunchReviewWorkflowFailureV1, .unresolvedCloseoutCount) }
        XCTAssertEqual(h.memory.effectCounts, before)

        for (slot, decisions) in try [
            (703, h.decisions(overridingFirstWith: .notReviewed)),
            (704, h.decisions(overridingFirstWith: .deferred)),
            (705, h.decisions(overridingFirstWith: .unable))
        ] {
            let rejected = try h.contextWith(scopeDecisions: decisions)
            do {
                _ = try await h.workflow.execute(
                    .closeout(try h.lifecycle(to: .fieldComplete, slot: slot)), context: rejected
                )
                XCTFail("Incomplete disposition without matching closeout intent must fail closed")
            } catch { XCTAssertEqual(error as? PunchReviewWorkflowFailureV1, .unresolvedCloseoutCount) }
            XCTAssertEqual(h.memory.effectCounts, before)
        }

        for (slot, disposition, completion) in [
            (706, PunchReviewItemDispositionV1.deferred, PunchReviewCompletionDispositionV1.partiallyReviewed),
            (707, PunchReviewItemDispositionV1.unable, PunchReviewCompletionDispositionV1.unableAttemptRecorded)
        ] {
            let permitted = try C34Harness()
            try await permitted.accept(.start(try permitted.lifecycle(to: .inProgress, slot: slot + 100)))
            let decisions = try permitted.decisions(overridingFirstWith: disposition)
            let intent = try PunchReviewCloseoutV1(
                completion: completion, basisSHA256: permitted.context.basis.basisSHA256,
                scope: decisions, scopeAndTimeLimitation: "Recorded incomplete punch-review attempt."
            )
            let intended = try permitted.contextWith(scopeDecisions: decisions, closeoutIntent: intent)
            XCTAssertEqual(try permitted.workflow.projection(for: intended).nextCloseoutAction, .recordFieldComplete)
            let mutation = try permitted.lifecycle(to: .fieldComplete, slot: slot + 200)
            _ = try await permitted.workflow.execute(.closeout(mutation), context: intended)
            XCTAssertEqual(permitted.memory.effectCounts[mutation.mutationID], 1)
        }

        let recorded = try h.resolvedFacts(slot: 705)
        try await h.accept(.recordBasisVariation(recorded.mutation), facts: recorded)
        let wrong = try h.installationSnapshot(slot: 710, subjectID: C34Support.id(799))
        XCTAssertThrowsError(try h.contextWith(installationSnapshot: wrong)) {
            XCTAssertEqual($0 as? PunchReviewWorkflowFailureV1, .staleOrWrongAsset)
        }
        let findingID = try XCTUnwrap(h.context.findings.first?.findingID)
        let one = try C34Support.recheck(findingID: findingID, workID: "work.one", slot: 721)
        let conflict = try C34Support.recheck(findingID: findingID, workID: "work.two", slot: 722)
        XCTAssertThrowsError(try h.contextWith(verifiedRechecks: [one, conflict])) {
            XCTAssertEqual($0 as? PunchReviewWorkflowFailureV1, .conflictingRecheck)
        }

        let resolvedDecision = try XCTUnwrap(h.context.scopeDecisions.first(where: { !$0.findingLinks.isEmpty }))
        let resolvedLink = try XCTUnwrap(resolvedDecision.findingLinks.first)
        let missingLink = try C34Support.rebound(
            resolvedLink, operationalRecheck: nil
        )
        let missingDecision = try PunchItemProjectionV1(
            scopeItemID: resolvedDecision.scopeItemID, disposition: .reviewedWithItems,
            findingLinks: [missingLink]
        )
        let missingContext = try h.contextWith(
            scopeDecisions: [missingDecision] + h.context.scopeDecisions.filter {
                $0.scopeItemID != missingDecision.scopeItemID
            }, verifiedRechecks: []
        )
        XCTAssertNil(try h.workflow.projection(for: missingContext).nextCloseoutAction)
        let effectsBeforeMissing = h.memory.effectCounts
        do {
            _ = try await h.workflow.execute(
                .closeout(try h.lifecycle(to: .fieldComplete, slot: 725)), context: missingContext
            )
            XCTFail("A linked finding without an explicit recheck must fail closed")
        } catch { XCTAssertEqual(error as? PunchReviewWorkflowFailureV1, .unresolvedCloseoutCount) }
        XCTAssertEqual(h.memory.effectCounts, effectsBeforeMissing)

        let actionID = try XCTUnwrap(h.context.correctiveActionEvents.first?.actionID.uuidString.lowercased())
        let failed = try C34Support.recheck(
            findingID: findingID.uuidString.lowercased(), workID: actionID, slot: 726, outcome: .failed
        )
        let failedLink = try C34Support.rebound(resolvedLink, operationalRecheck: failed)
        let failedDecision = try PunchItemProjectionV1(
            scopeItemID: resolvedDecision.scopeItemID, disposition: .reviewedWithItems,
            findingLinks: [failedLink]
        )
        let failedContext = try h.contextWith(
            scopeDecisions: [failedDecision] + h.context.scopeDecisions.filter {
                $0.scopeItemID != failedDecision.scopeItemID
            }, verifiedRechecks: [failed]
        )
        XCTAssertNil(try h.workflow.projection(for: failedContext).nextCloseoutAction)
        let effectsBeforeFailed = h.memory.effectCounts
        do {
            _ = try await h.workflow.execute(
                .closeout(try h.lifecycle(to: .fieldComplete, slot: 727)), context: failedContext
            )
            XCTFail("A linked finding whose current recheck is not passed must fail closed")
        } catch { XCTAssertEqual(error as? PunchReviewWorkflowFailureV1, .unresolvedCloseoutCount) }
        XCTAssertEqual(h.memory.effectCounts, effectsBeforeFailed)

        let stale = try h.lifecycle(to: .fieldComplete, slot: 723)
        try await h.accept(.pause(try h.lifecycle(to: .paused, slot: 724)))
        let effectsBeforeStale = h.memory.effectCounts
        do {
            _ = try await h.workflow.execute(.closeout(stale), context: h.context)
            XCTFail("Stale predecessor must fail")
        } catch { XCTAssertNotNil(error as? PunchReviewWorkflowFailureV1) }
        XCTAssertEqual(h.memory.effectCounts, effectsBeforeStale)
    }

    func testV23P04C34I01EffectBeforeReceiptInterruptionRecoversExactlyOnce() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "I01", "INTERRUPTION")
        let h = try C34Harness(failFirstWrite: true)
        let start = try h.lifecycle(to: .inProgress, slot: 801)
        do {
            _ = try await h.workflow.execute(.start(start), context: h.context)
            XCTFail("Effect-before-receipt interruption must surface")
        } catch { XCTAssertEqual(error as? C34MemoryFailure, .afterEffectBeforeReceipt) }
        XCTAssertEqual(h.memory.effectCounts[start.mutationID], 1)
        let recovered = try await h.workflow.recover(.start(start), context: h.context)
        XCTAssertEqual(recovered.mutationID, start.mutationID)
        XCTAssertEqual(h.memory.effectCounts[start.mutationID], 1)
        XCTAssertEqual(h.memory.receiptCount, 1)
    }

    func testV23P04C34R01ReopenRetryImmutableHistoryAndDeterministicReportReconstruction() async throws {
        let corpus = try loadCorpus(); assertScenario(corpus, "R01", "RECOVERY")
        let h = try C34Harness()
        try await h.accept(.start(try h.lifecycle(to: .inProgress, slot: 901)))
        try await h.accept(.pause(try h.lifecycle(to: .paused, slot: 902)))
        try await h.accept(.resume(try h.lifecycle(to: .inProgress, slot: 903)))
        let facts = try h.resolvedFacts(slot: 910)
        let findingID = try XCTUnwrap(facts.findings.first?.findingID)
        let actionID = try XCTUnwrap(facts.actions.first?.actionID.uuidString.lowercased())
        let failed = try C34Support.recheck(findingID: findingID, workID: actionID, slot: 916, outcome: .failed)
        let passed = try C34Support.recheck(findingID: findingID, workID: actionID, slot: 917, prior: failed)
        let originalDecision = try XCTUnwrap(facts.decisions.first)
        let originalLink = try XCTUnwrap(originalDecision.findingLinks.first)
        let passedID = try XCTUnwrap(UUID(uuidString: passed.recheckID))
        let reboundLink = try PunchFindingLinkV1(
            findingID: originalLink.findingID, findingRevision: originalLink.findingRevision,
            findingSHA256: originalLink.findingSHA256, sourceContext: originalLink.sourceContext,
            supportingRecords: originalLink.supportingRecords.filter { $0.kind != .operationalRecheck } + [
                try .init(kind: .operationalRecheck, recordID: passedID,
                          revision: UInt64(passed.resultingRecheckRevision),
                          recordSHA256: WorkspaceMutationCanonicalV1.sha256(passed))
            ]
        )
        let reboundDecision = try PunchItemProjectionV1(
            scopeItemID: originalDecision.scopeItemID, disposition: originalDecision.disposition,
            findingLinks: [reboundLink]
        )
        let reopened = C34Facts(mutation: facts.mutation,
                                decisions: [reboundDecision] + Array(facts.decisions.dropFirst()),
                                findings: facts.findings, actions: facts.actions,
                                rechecks: [failed, passed], sources: facts.sources)
        try await h.accept(.recordBasisVariation(reopened.mutation), facts: reopened)
        try await h.accept(.closeout(try h.lifecycle(to: .fieldComplete, slot: 920)))
        try await h.accept(.closeout(try h.lifecycle(to: .readyForReview, slot: 921)))
        let closeout = try h.closeout()
        let completed = try h.completedSnapshot(sourceRevision: Int(h.context.envelope.revision + 1))
        let reference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(
            completed, activityCloseoutSHA256: closeout.closeoutSHA256
        )
        try await h.accept(.closeout(try h.lifecycle(
            to: .finalized, slot: 922, closeout: closeout, completedReference: reference
        )))
        let immutableDecisions = h.context.scopeDecisions
        let immutableRechecks = h.context.verifiedRechecks
        let effects = h.memory.effectCounts
        let first = try h.projection().report
        let rebuilt = try h.workflow.projection(for: try h.contextWith()).report
        XCTAssertEqual(first, rebuilt)
        XCTAssertEqual(first.projectionSHA256, rebuilt.projectionSHA256)
        XCTAssertEqual(h.context.scopeDecisions, immutableDecisions)
        XCTAssertEqual(h.context.verifiedRechecks, immutableRechecks)
        XCTAssertEqual(h.memory.effectCounts, effects)
        XCTAssertTrue(h.memory.effectCounts.values.allSatisfy { $0 == 1 })
        XCTAssertEqual(try h.projection().reportReadiness, .readyForExistingRenderer)
    }

    private func loadCorpus() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Activities/V23P04C34PunchReviewWorkflowCorpusV1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func assertScenario(_ corpus: [String: Any], _ id: String, _ kind: String) {
        XCTAssertEqual(corpus["schema"] as? String, "V23P04C34PunchReviewWorkflowCorpusV1")
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C34")
        XCTAssertEqual(corpus["ordinal"] as? Int, 119)
        XCTAssertEqual((corpus["persistence"] as? [String: Any])?["persistentSchemaVersion"] as? Int, 36)
        XCTAssertTrue((corpus["scenarios"] as? [[String: Any]])?.contains {
            $0["id"] as? String == id && $0["kind"] as? String == kind
        } == true)
    }
}

private enum C34Support {
    static let fixedDate = Date(timeIntervalSince1970: 2_310_000_000)
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "97000000-0000-4000-8000-%012d", n))! }
    static func mutation(_ n: Int) throws -> MutationIDV1 { try .init(rawValue: id(n)) }
    static func actor(_ workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        try .init(snapshotID: id(40), workspaceID: workspaceID,
                  actor: .init(actorReferenceID: id(41), workspaceID: workspaceID, displayName: "Punch recorder"),
                  responsibility: .recordedBy, displayNameAtTime: "Punch recorder", capturedAt: fixedDate)
    }
    static func recheck(findingID: String, workID: String, slot: Int,
                        prior: VerifiedRecheckV1? = nil, outcome: VerifiedRecheckOutcomeV1 = .passed) throws -> VerifiedRecheckV1 {
        try .init(recheckID: id(slot).uuidString.lowercased(), findingID: findingID, findingRevision: 1,
                  correctiveWorkID: workID, correctiveWorkRevision: 1,
                  priorRecheckID: prior?.recheckID, evidenceRevisionIDs: ["evidence.\(slot)"],
                  expectedRecheckRevision: prior?.resultingRecheckRevision ?? 0,
                  resultingRecheckRevision: (prior?.resultingRecheckRevision ?? 0) + 1,
                  mutationID: id(slot + 10_000).uuidString.lowercased(), outcome: outcome, verifierActorID: "actor.verifier",
                  verifierAuthority: "Recorded verifier", reason: "Recorded correction recheck.",
                  effectiveAt: "2027-03-15T08:00:00.000Z")
    }

    static func correctiveAction(workspaceID: WorkspaceID, finding: FindingV1, slot: Int) throws -> CorrectiveActionEventV1 {
        let policy = try CorrectiveActionPolicyV1(
            releaseID: id(slot), policyID: id(slot + 1), workspaceID: workspaceID,
            priorityRules: [try .init(priority: .low, dueRule: .init(kind: .noDueDate))],
            assignmentRule: .prohibited, closureEvidenceRequirements: [], verifierRule: .notRequired,
            reopenTriggers: [.failedVerifiedRecheck, .manualRecordedReason], effectiveAt: fixedDate,
            revision: 1, mutationID: mutation(slot + 2)
        )
        let findingSHA = try WorkspaceMutationCanonicalV1.sha256(finding)
        return try CorrectiveActionEventV1(
            eventID: id(slot + 3), actionID: id(slot + 4), workspaceID: workspaceID,
            source: .init(kind: .finding, itemID: finding.findingID,
                          itemRevision: UInt64(finding.revision), itemSHA256: findingSHA),
            policy: .init(policy), priority: .low, state: .open,
            recorder: actor(workspaceID), due: .init(openedAt: fixedDate, timeZoneIdentifier: nil,
                                                     dueAt: nil, graceEndsAt: nil, resolvedUTCOffsetSeconds: nil),
            reason: "Recorded punch correction request.", occurredAt: fixedDate, recordedAt: fixedDate,
            revision: 1, mutationID: mutation(slot + 5)
        )
    }

    static func rebound(_ link: PunchFindingLinkV1,
                        operationalRecheck: VerifiedRecheckV1?) throws -> PunchFindingLinkV1 {
        var records = link.supportingRecords.filter { $0.kind != .operationalRecheck }
        if let recheck = operationalRecheck {
            guard let recheckID = UUID(uuidString: recheck.recheckID) else {
                throw PunchReviewWorkflowFailureV1.invalidContext
            }
            records.append(try .init(
                kind: .operationalRecheck,
                recordID: recheckID,
                revision: UInt64(recheck.resultingRecheckRevision),
                recordSHA256: WorkspaceMutationCanonicalV1.sha256(recheck)
            ))
        }
        return try .init(
            findingID: link.findingID, findingRevision: link.findingRevision,
            findingSHA256: link.findingSHA256, sourceContext: link.sourceContext,
            supportingRecords: records
        )
    }
}

private struct C34Facts {
    let mutation: ActivityContractMutationV2
    let decisions: [PunchItemProjectionV1]
    let findings: [FindingV1]
    let actions: [CorrectiveActionEventV1]
    let rechecks: [VerifiedRecheckV1]
    let sources: [ActivitySessionEnvelopeV2]
}

@MainActor
private final class C34Harness {
    let release: PunchReviewWorkflowDefinitionReleaseV1
    let workflow: PunchReviewWorkflowCoordinatorV1
    let memory: C34Memory
    private(set) var context: PunchReviewWorkflowContextV1

    init(failFirstWrite: Bool = false) throws {
        let workspaceID = WorkspaceID(rawValue: C34Support.id(1)), activityID = C34Support.id(2), subjectID = C34Support.id(3)
        let fallback = try NoPlanFallbackV1(limitation: "Standalone punch review; no plan or installation is required.")
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let registry = try InspectionPackageRegistryV2(packages: [package])
        let selected = try registry.bundledActivityWorkflowRelease(kind: .punchReview,
            packageID: ShippingIlluminatedSignAdapterV1.packageID, workspaceID: workspaceID)
        guard case let .punch(value) = selected.release else { throw PunchReviewWorkflowFailureV1.invalidContext }
        release = value
        let basis = try PunchReviewBasisSnapshotV1(
            basisID: C34Support.id(4), workspaceID: workspaceID, activityID: activityID, subjectID: subjectID,
            workflowReleaseReference: try .init(punchReview: value, package: package), source: .noPlan(fallback),
            scopeLimitation: "Standalone recorded scope; no installation truth is inferred.",
            capturedAt: C34Support.fixedDate, revision: 1, mutationID: C34Support.mutation(4))
        let readiness = try value.readinessPolicy.requiredFacets.map {
            try ActivityReadinessFacetV1(facetID: "ready-\($0.rawValue.lowercased())", kind: $0, disposition: .ready)
        }
        let envelope = try ActivitySessionEnvelopeV2(
            activityID: activityID, workspaceID: workspaceID, kind: .punchReview, state: .ready,
            reviewState: .notRequested, subjectID: subjectID, title: "Standalone punch review",
            readiness: readiness, readinessPolicy: .punchReview(value.readinessPolicy),
            currentBasisReference: .punchReview(try .init(basis)), revision: 1, mutationID: C34Support.mutation(5))
        let plan = try PunchReviewPlanCapabilityV1(disposition: .manualFallback, noPlanFallback: fallback)
        context = try .init(envelope: envelope, release: value, basis: basis, planCapability: plan)
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: workspaceID,
            generationID: C34Support.id(6), writerInstanceID: C34Support.id(7), workspaceRevision: 1,
            entityRevisions: [try .init(identity: .init(kind: .activitySessionEnvelope, id: activityID), revision: 1)])
        memory = C34Memory(envelope: envelope, expected: expected, failFirstWrite: failFirstWrite)
        let authority = try ActivityContractConformanceAuthorityV2(
            sharedReceipt: .init(sharedContractSHA256: String(repeating: "a", count: 64)),
            installationContractSHA256: String(repeating: "b", count: 64),
            punchContractSHA256: String(repeating: "c", count: 64), noPlanFallback: fallback)
        workflow = try .init(contractCoordinator: .init(query: memory, writer: memory, conformanceAuthority: authority),
                             punchContractSHA256: authority.punchContractSHA256, noPlanFallback: fallback)
    }

    func projection() throws -> PunchReviewWorkflowProjectionV1 { try workflow.projection(for: context) }
    func contextWith(scopeDecisions: [PunchItemProjectionV1]? = nil,
                     correctiveActionEvents: [CorrectiveActionEventV1]? = nil,
                     verifiedRechecks: [VerifiedRecheckV1]? = nil,
                     installationSnapshot: PunchReviewInstallationSnapshotContextV1? = nil,
                     closeoutIntent: PunchReviewCloseoutV1? = nil) throws -> PunchReviewWorkflowContextV1 {
        try .init(envelope: context.envelope, release: context.release, basis: context.basis,
                  scopeDecisions: scopeDecisions ?? context.scopeDecisions, findings: context.findings,
                  correctiveActionEvents: correctiveActionEvents ?? context.correctiveActionEvents,
                  verifiedRechecks: verifiedRechecks ?? context.verifiedRechecks,
                  sourceEnvelopes: context.sourceEnvelopes, planCapability: context.planCapability,
                  installationSnapshot: installationSnapshot ?? context.installationSnapshot,
                  closeoutIntent: closeoutIntent ?? context.closeoutIntent)
    }

    func accept(_ command: PunchReviewWorkflowCommandV1, facts: C34Facts? = nil) async throws {
        let prior = context, accepted = try await workflow.execute(command, context: prior)
        let replay = try await workflow.execute(command, context: prior)
        guard accepted == replay else { throw PunchReviewWorkflowFailureV1.invalidContext }
        let mutation = command.mutation
        context = try .init(envelope: mutation.successorEnvelope, release: release,
            basis: mutation.punchReviewBasisSnapshot ?? prior.basis,
            scopeDecisions: facts?.decisions ?? prior.scopeDecisions,
            findings: facts?.findings ?? prior.findings,
            correctiveActionEvents: facts?.actions ?? prior.correctiveActionEvents,
            verifiedRechecks: facts?.rechecks ?? prior.verifiedRechecks,
            sourceEnvelopes: facts?.sources ?? prior.sourceEnvelopes,
            planCapability: prior.planCapability, installationSnapshot: prior.installationSnapshot,
            closeoutIntent: prior.closeoutIntent)
    }

    func decisions(overridingFirstWith disposition: PunchReviewItemDispositionV1) throws -> [PunchItemProjectionV1] {
        try release.scope.enumerated().map { index, item in
            let value = index == 0 ? disposition : .reviewedNoItemRecorded
            return try .init(
                scopeItemID: item.scopeItemID, disposition: value,
                deferredReason: value == .deferred ? .accessUnavailable : nil,
                unableReason: value == .unable ? .irrecoverableAccess : nil
            )
        }
    }

    func lifecycle(to state: ActivityStateV2, slot: Int,
                   closeout: PunchReviewCloseoutV1? = nil,
                   completedReference: CompletedActivitySnapshotV2CompatibilityReferenceV1? = nil) throws -> ActivityContractMutationV2 {
        let id = try C34Support.mutation(slot), successor = try envelope(from: context.envelope, state: state,
            mutationID: id, closeout: closeout, completedReference: completedReference)
        return try .init(workspaceID: context.envelope.workspaceID, expectedRevision: memory.expected,
            mutationID: id, predecessorEnvelope: context.envelope, successorEnvelope: successor,
            transition: try transition(from: context.envelope, to: successor, slot: slot),
            completedSnapshotReference: successor.completedSnapshotReference)
    }

    func resolvedFacts(slot: Int) throws -> C34Facts {
        let predecessor = context.envelope, mutationID = try C34Support.mutation(slot)
        let nextBasis = try PunchReviewBasisSnapshotV1(
            basisID: C34Support.id(slot + 1), workspaceID: predecessor.workspaceID,
            activityID: predecessor.activityID, subjectID: predecessor.subjectID,
            workflowReleaseReference: context.basis.workflowReleaseReference, source: context.basis.source,
            scopeLimitation: "Recorded scope includes correction and verified recheck history.",
            capturedAt: C34Support.fixedDate, revision: context.basis.revision + 1, mutationID: mutationID,
            predecessorBasisID: context.basis.basisID, predecessorBasisSHA256: context.basis.basisSHA256)
        let variation = try ActivityVariationV1(variationID: C34Support.id(slot + 2), workspaceID: predecessor.workspaceID,
            revision: UInt64(predecessor.variations.count + 1), kind: .recordedScopeChanged,
            predecessorBasisSHA256: context.basis.basisSHA256, successorBasisSHA256: nextBasis.basisSHA256,
            reason: "Recorded correction and recheck changed the reviewed scope facts.",
            actor: C34Support.actor(predecessor.workspaceID), occurredAt: C34Support.fixedDate, mutationID: mutationID)
        let successor = try envelope(from: predecessor, state: predecessor.state, mutationID: mutationID,
                                     basis: nextBasis, variations: predecessor.variations + [variation])
        let mutation = try ActivityContractMutationV2(workspaceID: predecessor.workspaceID,
            expectedRevision: memory.expected, mutationID: mutationID, predecessorEnvelope: predecessor,
            successorEnvelope: successor, punchReviewBasisSnapshot: nextBasis)
        let findingID = C34Support.id(slot + 3)
        let finding = try FindingV1(findingID: findingID.uuidString.lowercased(), revision: 1,
            severity: .init(severityID: "observed", severityScaleReleaseID: "punch.scale.v1",
                            severityScaleSHA256: String(repeating: "d", count: 64)),
            categoryID: "punch.condition",
            subject: .init(subjectKindID: "asset", subjectID: predecessor.subjectID.uuidString.lowercased(), subjectRevision: 1),
            source: .init(kind: .humanObservation, sourceID: "punch.observation", sourceRevision: 1),
            summary: "Recorded punch finding requiring correction and recheck.")
        let action = try C34Support.correctiveAction(
            workspaceID: predecessor.workspaceID, finding: finding, slot: slot + 20
        )
        let recheck = try C34Support.recheck(
            findingID: finding.findingID,
            workID: action.actionID.uuidString.lowercased(),
            slot: slot + 30
        )
        let recheckID = try XCTUnwrap(UUID(uuidString: recheck.recheckID))
        let link = try PunchFindingLinkV1(findingID: findingID, findingRevision: finding.revision,
            findingSHA256: WorkspaceMutationCanonicalV1.sha256(finding),
            sourceContext: .init(workspaceID: predecessor.workspaceID, activityID: predecessor.activityID,
                activityKind: .punchReview, activityRevision: predecessor.revision,
                activitySHA256: predecessor.envelopeSHA256, taskOrScopeID: release.scope[0].scopeItemID),
            supportingRecords: [
                try .init(kind: .correctiveAction, recordID: action.actionID,
                          revision: action.revision, recordSHA256: action.eventSHA256),
                try .init(kind: .operationalRecheck, recordID: recheckID,
                          revision: UInt64(recheck.resultingRecheckRevision),
                          recordSHA256: WorkspaceMutationCanonicalV1.sha256(recheck))
            ])
        var decisions = [try PunchItemProjectionV1(scopeItemID: release.scope[0].scopeItemID,
                                                   disposition: .reviewedWithItems, findingLinks: [link])]
        decisions += try release.scope.dropFirst().map { try .init(scopeItemID: $0.scopeItemID, disposition: .reviewedNoItemRecorded) }
        return .init(mutation: mutation, decisions: decisions, findings: [finding], actions: [action],
                     rechecks: [recheck], sources: [predecessor])
    }

    func closeout() throws -> PunchReviewCloseoutV1 {
        try .init(completion: context.scopeDecisions.contains(where: { !$0.findingLinks.isEmpty })
                    ? .completedWithPunchItemsRecorded : .completedNoPunchItemsRecordedInScope,
                  basisSHA256: context.basis.basisSHA256, scope: context.scopeDecisions,
                  scopeAndTimeLimitation: "Only the declared recorded scope and time were reviewed.")
    }

    func completedSnapshot(sourceRevision: Int) throws -> CompletedActivitySnapshotV2 {
        try Self.snapshot(workspaceID: context.envelope.workspaceID, activityID: context.envelope.activityID,
                          subjectID: context.envelope.subjectID, sourceRevision: sourceRevision)
    }

    func installationSnapshot(slot: Int, subjectID: UUID? = nil) throws -> PunchReviewInstallationSnapshotContextV1 {
        let workspaceID=context.envelope.workspaceID,activityID=C34Support.id(slot),assetID=subjectID ?? context.envelope.subjectID
        let fallback=try NoPlanFallbackV1(limitation:"Recorded installation fixture uses explicit no-plan truth.")
        let package=try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let registry=try InspectionPackageRegistryV2(packages:[package])
        let selected=try registry.bundledActivityWorkflowRelease(kind:.installation,
            packageID:ShippingIlluminatedSignAdapterV1.packageID,workspaceID:workspaceID)
        guard case let .installation(release)=selected.release else{throw PunchReviewWorkflowFailureV1.invalidContext}
        let basis=try InstallationBasisSnapshotV1(basisID:C34Support.id(slot+1),workspaceID:workspaceID,
            activityID:activityID,subjectID:assetID,workflowReleaseReference:try .init(installation:release,package:package),
            source:.noPlan(fallback),capturedAt:C34Support.fixedDate,revision:1,mutationID:C34Support.mutation(slot+1))
        let asBuilt=try InstallationAsBuiltSnapshotV1(snapshotID:C34Support.id(slot+2),workspaceID:workspaceID,
            activityID:activityID,basisReference:.init(basis),taskResultSHA256s:[String(repeating:"f",count:64)],
            completion:.completedAsRecorded,revision:1,mutationID:C34Support.mutation(slot+2))
        let closeout=try InstallationCloseoutV1(completion:.completedAsRecorded,asBuiltSnapshotSHA256:asBuilt.snapshotSHA256)
        let completed=try Self.snapshot(workspaceID:workspaceID,activityID:activityID,subjectID:assetID,sourceRevision:1)
        let reference=try CompletedActivitySnapshotV2CompatibilityReferenceV1(completed,activityCloseoutSHA256:closeout.closeoutSHA256)
        let envelope=try ActivitySessionEnvelopeV2(activityID:activityID,workspaceID:workspaceID,kind:.installation,
            state:.finalized,reviewState:.acceptedRecordedFacts,subjectID:assetID,title:"Read-only installation snapshot",
            readiness:[try .init(facetID:"access",kind:.access,disposition:.ready)],
            currentBasisReference:.installation(try .init(basis)),installationCloseout:closeout,
            completedSnapshotReference:reference,startedAt:C34Support.fixedDate,
            finalizedAt:C34Support.fixedDate.addingTimeInterval(60),revision:1,mutationID:C34Support.mutation(slot+3))
        return try .init(envelope:envelope,asBuiltSnapshot:asBuilt,completedSnapshot:completed)
    }

    private static func snapshot(workspaceID:WorkspaceID,activityID:UUID,subjectID:UUID,
                                 sourceRevision:Int)throws->CompletedActivitySnapshotV2{
        let formats:[ReportProjectionFormatV1]=[.openJSON,.pdf,.structuredText]
        let sections=try ["identity","limitations","provenance","supersession","manifest"].enumerated().map{
            try ReportSectionDefinitionV1(sectionID:$0.element,version:1,required:true,supportedFormats:formats,
                privacyClass:.mandatoryPublicTruth,requiresHeading:true,requiresTextAlternative:true,order:$0.offset)}
        let registry=try ReportSectionRegistryV1(registryID:"c34-section-registry-v1",registryVersion:1,sections:sections)
        let manifest=try ContractManifestV1(manifestID:"c34-completed-activity-v2",manifestVersion:1,
            codec:.init(codecVersion:1),compatibility:.init(minimumReaderVersion:1,maximumReaderVersion:1,unknownObjectFields:.reject),
            objects:[try .init(typeID:"completed-snapshot",version:1,unknownFieldPolicy:.reject,
                fields:[try .init(fieldID:"snapshot-id",jsonName:"snapshotID",kind:.string,required:true,maximumUTF8Bytes:128)])],
            enums:[],reportSectionRegistry:registry)
        let layout=try ReportLayoutProfileV1(profileID:"c34-customer-complete-v1",profileRelease:1,audience:.customerSafe,
            detail:.complete,sectionIDs:sections.map(\.sectionID),mediaLayout:.standardGrid,orientation:.portrait,
            localeIdentifier:"en_US",unitsProfileID:"units-si-v1",displayProfileID:"display-v1",registry:registry)
        let export=try ExportProfileV1(exportProfileID:"c34-portable-v1",exportProfileRelease:1,formats:formats,
            packaging:.combined,privacyTransformID:"customer-safe-v1",maximumMediaItems:32,
            maximumArchiveBytes:Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes))
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let workspaceToken=workspaceID.rawValue.uuidString.lowercased(),snapshotID="c34-completed-snapshot-v1"
        let binding=try FinalizedReportProfileBindingV1(workspaceID:workspaceToken,snapshotID:snapshotID,
            outputScopeID:"c34-output-scope-v1",reportProfileID:layout.profileID,reportProfileRelease:layout.profileRelease,
            reportProfileSHA256:KernelCanonicalHashV1.sha256(try encoder.encode(layout)),exportProfileID:export.exportProfileID,
            exportProfileRelease:export.exportProfileRelease,exportProfileSHA256:KernelCanonicalHashV1.sha256(try encoder.encode(export)),
            sectionRegistryID:registry.registryID,sectionRegistryVersion:registry.registryVersion,
            sectionRegistrySHA256:KernelCanonicalHashV1.sha256(try encoder.encode(registry)),contractManifestID:manifest.manifestID,
            contractManifestVersion:manifest.manifestVersion,contractManifestSHA256:KernelCanonicalHashV1.sha256(try encoder.encode(manifest)),
            sectionIDs:layout.sectionIDs,audience:.customerSafe,detail:.complete,privacyTransformID:export.privacyTransformID,
            localeIdentifier:layout.localeIdentifier,unitsProfileID:layout.unitsProfileID,displayProfileID:layout.displayProfileID,
            orientation:layout.orientation,mediaLayout:layout.mediaLayout,rendererVersion:ReportSemanticProjectorV1.rendererVersion,
            projectionVersion:"c47-activity-contract-v2")
        let activity=try CompletedActivitySnapshotPayloadV1(workspaceID:workspaceToken,snapshotID:snapshotID,snapshotRevision:1,
            sourceActivityID:activityID.uuidString.lowercased(),sourceRevision:sourceRevision,reportID:"c34-report-v1",
            packageReleaseID:"c34-bundled-workflow-v1",generatedAt:"2027-03-15T08:00:00.000Z",
            completedAt:"2027-03-15T08:00:00.000Z",supersedesSnapshotID:nil,supersededSnapshotSHA256:nil,
            amendmentReason:nil,profileBinding:binding,serviceFacts:[],evidenceCards:[],
            limitations:["Recorded punch review is not approval, compliance, safety, or authorization."])
        let site=C34Support.id(950),path=try LocationPathSnapshotV1(siteID:site,siteDisplay:"Recorded site",nodes:[])
        let placement=try AssetPlacementEventV1(id:C34Support.id(951),workspaceID:workspaceID,assetID:subjectID,
            siteID:site,locationNodeID:nil,predecessorEventID:nil,source:.migratedBaseline,
            physicalEpisodeID:.init(rawValue:C34Support.id(952)),continuity:.samePhysicalInstallation,pathSnapshot:path,
            mutationID:C34Support.mutation(953),occurredAt:C34Support.fixedDate)
        let location=try CompletedLocationCompositionSnapshotV1.build(workspaceID:workspaceID,assetID:subjectID,
            currentLocationPath:path,currentPlacementByAssetID:[subjectID:placement],activeCompositionEdges:[],frozenAtRevision:1)
        return try CompletedActivitySnapshotV2.freezeOriginal(.init(activity:activity,assetID:subjectID,locationComposition:location))
    }

    private func envelope(from p: ActivitySessionEnvelopeV2, state: ActivityStateV2,
                          mutationID: MutationIDV1, basis: PunchReviewBasisSnapshotV1? = nil,
                          variations: [ActivityVariationV1]? = nil, closeout: PunchReviewCloseoutV1? = nil,
                          completedReference: CompletedActivitySnapshotV2CompatibilityReferenceV1? = nil) throws -> ActivitySessionEnvelopeV2 {
        try .init(activityID: p.activityID, workspaceID: p.workspaceID, kind: .punchReview, state: state,
            reviewState: state == .readyForReview ? .pending : state == .finalized ? .acceptedRecordedFacts : .notRequested,
            subjectID: p.subjectID, title: p.title, readiness: p.readiness, readinessPolicy: p.readinessPolicy,
            variations: variations ?? p.variations,
            currentBasisReference: try basis.map { .punchReview(.init($0)) } ?? p.currentBasisReference,
            punchReviewCloseout: closeout ?? p.punchReviewCloseout,
            completedSnapshotReference: completedReference ?? p.completedSnapshotReference,
            startedAt: p.startedAt ?? (state.hasStarted ? C34Support.fixedDate : nil),
            finalizedAt: state == .finalized ? C34Support.fixedDate.addingTimeInterval(60) : p.finalizedAt,
            revision: p.revision + 1, mutationID: mutationID, predecessorEnvelopeSHA256: p.envelopeSHA256)
    }

    private func transition(from p: ActivitySessionEnvelopeV2, to s: ActivitySessionEnvelopeV2, slot: Int) throws -> ActivityStateTransitionV2 {
        try .init(transitionID: C34Support.id(slot + 100), workspaceID: p.workspaceID, activityID: p.activityID,
                  kind: .punchReview, fromState: p.state, toState: s.state,
                  actor: C34Support.actor(p.workspaceID), occurredAt: C34Support.fixedDate,
                  revision: s.revision, mutationID: s.mutationID)
    }
}

private enum C34MemoryFailure: Error, Equatable { case afterEffectBeforeReceipt }

@MainActor
private final class C34Memory: ActivityContractCurrentStateQueryingV2, ActivityContractCanonicalWorkspaceWritingV2 {
    private(set) var envelope: ActivitySessionEnvelopeV2
    private(set) var expected: WorkspaceExpectedRevisionV1
    private var receipts: [MutationIDV1: MutationReceiptV1] = [:]
    private var unreceipted: MutationIDV1?
    private var failFirstWrite: Bool
    private(set) var effectCounts: [MutationIDV1: Int] = [:]
    var receiptCount: Int { receipts.count }
    init(envelope: ActivitySessionEnvelopeV2, expected: WorkspaceExpectedRevisionV1, failFirstWrite: Bool) {
        self.envelope=envelope;self.expected=expected;self.failFirstWrite=failFirstWrite
    }
    func currentActivityContract(workspaceID: WorkspaceID, activityID: UUID) async throws -> ActivityContractCurrentStateV2? {
        guard workspaceID==envelope.workspaceID,activityID==envelope.activityID else{return nil}
        return try .init(workspaceID:workspaceID,activityID:activityID,expectedRevision:expected,envelope:envelope)
    }
    func durableActivityContractReceipt(workspaceID: WorkspaceID, mutationID: MutationIDV1) async throws -> MutationReceiptV1? {
        workspaceID == envelope.workspaceID ? receipts[mutationID] : nil
    }
    func commitActivityContract(_ mutation: ActivityContractMutationV2) async throws -> MutationReceiptV1 {
        if let value=receipts[mutation.mutationID]{return value}
        if unreceipted==mutation.mutationID,envelope==mutation.successorEnvelope{
            let value=try receipt(mutation);receipts[mutation.mutationID]=value;unreceipted=nil;return value}
        let predecessorExpected=expected
        let value=try receipt(mutation);envelope=mutation.successorEnvelope
        effectCounts[mutation.mutationID,default:0]+=1
        if failFirstWrite{failFirstWrite=false;unreceipted=mutation.mutationID;expected=predecessorExpected
            throw C34MemoryFailure.afterEffectBeforeReceipt}
        receipts[mutation.mutationID]=value;return value
    }
    private func receipt(_ mutation: ActivityContractMutationV2) throws -> MutationReceiptV1 {
        let images=try mutation.mutationPostImages
        let next=try WorkspaceExpectedRevisionV1(workspaceID:mutation.workspaceID,generationID:expected.generationID,
            writerInstanceID:expected.writerInstanceID,workspaceRevision:expected.workspaceRevision+1,
            entityRevisions:try images.map{try .init(identity:$0.identity,revision:$0.revision)})
        let replica=ReplicaID(rawValue:C34Support.id(8)),identity=try WorkspaceReplicaIdentityV1(workspaceID:mutation.workspaceID,replicaID:replica)
        let env=try MutationEnvelopeV1(request:.init(mutationID:mutation.mutationID,expectedRevision:mutation.expectedRevision,
            command:.applyActivityContract(mutation)),identity:identity)
        let value=try MutationReceiptV1(identity:.init(workspaceID:mutation.workspaceID,replicaID:replica,
            localSequence:UInt64(receipts.count+1)),envelope:env,resultingRevision:.init(next),postImages:images,
            committedAt:C34Support.fixedDate)
        expected=next;return value
    }
}

import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionDestinationReviewTests: XCTestCase {
    @MainActor
    func testSavedReviewReferenceAuthenticatesCurrentPendingAndTerminalOriginalsWithoutReadEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source, materializeRound: false)
        defer { try? fixture.close() }
        let services = try DestinationOperationServices(fixture)
        let initial = fixture.initialCheckpoint
        let before = try fixture.target.rawState()
        let initialRead = try services.primary.destinationReview(reference: destinationReference(initial))
        XCTAssertEqual(initialRead?.selectedReview.checkpoint, initial)
        XCTAssertEqual(try fixture.target.rawState(), before)
        XCTAssertEqual(services.ids.count, 0)

        let choice = try services.primary.prepareDestinationResolution(
            reviewDraftID: initial.draftID, plan: .discard, round: nil)
        _ = try services.primary.persistDestinationResolution(choice)
        let pending = try fixture.currentCheckpoint()
        let pendingState = try fixture.target.rawState()
        XCTAssertThrowsError(try services.primary.destinationReview(reference: destinationReference(initial)))
        let pendingRead = try services.primary.destinationReview(reference: destinationReference(pending))
        XCTAssertEqual(pendingRead?.selectedReview.checkpoint, pending)
        XCTAssertEqual(try fixture.target.rawState(), pendingState)

        let prepared = try services.primary.prepareDestinationDiscard(reviewDraftID: initial.draftID)
        let discarded = try services.primary.persistDestinationDiscard(prepared, confirmed: true)
        let terminal = try fixture.currentCheckpoint()
        let settled = try fixture.target.rawState()
        let reads = try DestinationOperationServices(fixture)
        let terminalRead = try reads.primary.destinationReview(reference: destinationReference(terminal))
        XCTAssertEqual(terminalRead?.selectedReview.checkpoint, terminal)
        XCTAssertEqual(try reads.primary.destinationDiscard(reviewDraftID: terminal.draftID)?.evidence,
                       discarded.evidence)
        XCTAssertThrowsError(try reads.primary.destinationReview(reference: destinationReference(pending)))
        XCTAssertEqual(try fixture.target.rawState(), settled)
        XCTAssertEqual(reads.ids.count, 0)
        XCTAssertTrue(try fixture.rounds().isEmpty)
        try fixture.assertOriginalsRetained()
    }

    @MainActor
    func testSavedReviewReferenceRejectsEverySubstitutedFieldAndNonDraftWithoutEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let services = try DestinationOperationServices(fixture)
        let checkpoint = fixture.initialCheckpoint
        let foreign = WorkspaceID(rawValue: UUID())
        let wrongDigest = checkpoint.checkpointSHA256 == String(repeating: "a", count: 64)
            ? String(repeating: "b", count: 64) : String(repeating: "a", count: 64)
        let wrongAnchor = try DraftResumeAnchorV1(sectionID: "unrelated-review")
        let references: [MyDayEligibleReferenceV1] = [
            .resumableDraft(workspaceID: foreign, draftID: checkpoint.draftID,
                revision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
                anchor: checkpoint.resumeAnchor),
            .resumableDraft(workspaceID: checkpoint.workspaceID, draftID: UUID(),
                revision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
                anchor: checkpoint.resumeAnchor),
            .resumableDraft(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID,
                revision: checkpoint.draftRevision + 1, checkpointSHA256: checkpoint.checkpointSHA256,
                anchor: checkpoint.resumeAnchor),
            .resumableDraft(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID,
                revision: checkpoint.draftRevision, checkpointSHA256: wrongDigest, anchor: checkpoint.resumeAnchor),
            .resumableDraft(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID,
                revision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
                anchor: wrongAnchor),
            .roundSession(workspaceID: checkpoint.workspaceID, sessionID: checkpoint.draftID,
                revision: checkpoint.draftRevision, sessionSHA256: checkpoint.checkpointSHA256)
        ]
        let before = try fixture.target.rawState()
        for reference in references {
            XCTAssertThrowsError(try services.primary.destinationReview(reference: reference))
            XCTAssertEqual(try fixture.target.rawState(), before)
        }
        XCTAssertEqual(services.ids.count, 0)
    }

    @MainActor
    func testSavedReviewReferenceReturnsUnsupportedOnlyAfterAuthenticCurrentReceipt() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let services = try DestinationOperationServices(fixture)
        let template = try C36FieldDraftTestSupportV1.makeFixture().activeCheckpoint
        let checkpoint = try FieldDraftCheckpointV1(draftID: template.draftID,
            workspaceID: fixture.initialCheckpoint.workspaceID, scope: template.scope,
            purpose: template.purpose, codec: template.codec,
            baseCanonicalRevision: fixture.initialCheckpoint.baseCanonicalRevision, draftRevision: 1,
            payloadData: template.payloadData, stageIDs: [], resumeAnchor: template.resumeAnchor,
            state: .active, updatedAt: template.updatedAt, mutationID: template.mutationID)
        let mutation = try FieldDraftMutationV1(workspaceID: checkpoint.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
            mutationID: checkpoint.mutationID, postImage: .createCheckpoint(checkpoint))
        _ = try fixture.target.writer.commitFieldDraft(mutation)
        let reference = destinationReference(checkpoint)
        let before = try fixture.target.rawState()
        XCTAssertNil(try services.primary.destinationReview(reference: reference))
        XCTAssertEqual(try fixture.target.rawState(), before)
        let row = try XCTUnwrap(fixture.target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == MutationWorkspaceKeyV1.value(
                workspaceID: checkpoint.workspaceID, mutationID: checkpoint.mutationID)
        })
        let originalDigest = row.receiptSHA256
        row.receiptSHA256 = String(repeating: "f", count: 64)
        try fixture.target.context.save()
        let corrupt = try fixture.target.rawState()
        XCTAssertThrowsError(try services.primary.destinationReview(reference: reference))
        XCTAssertEqual(try fixture.target.rawState(), corrupt)
        row.receiptSHA256 = originalDigest
        try fixture.target.context.save()
        XCTAssertNil(try services.primary.destinationReview(reference: reference))
        fixture.target.context.delete(row)
        try fixture.target.context.save()
        let missing = try fixture.target.rawState()
        XCTAssertThrowsError(try services.primary.destinationReview(reference: reference))
        XCTAssertEqual(try fixture.target.rawState(), missing)
        XCTAssertEqual(services.ids.count, 0)
    }

    @MainActor
    func testSavedReviewReferenceRejectsDirtyCorruptQuarantinedAndRetiredHistoryWithoutEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let services = try DestinationOperationServices(fixture)
        let reference = destinationReference(fixture.initialCheckpoint)
        let original = try XCTUnwrap(fixture.lineage().retainedSource.requiredHistory.first)
        let row = try XCTUnwrap(fixture.target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == MutationWorkspaceKeyV1.value(
                workspaceID: original.envelope.workspaceID, mutationID: original.envelope.mutationID)
        })
        let digest = row.receiptSHA256
        row.receiptSHA256 = String(repeating: "f", count: 64)
        let dirty = try fixture.target.rawState()
        XCTAssertThrowsError(try services.primary.destinationReview(reference: reference))
        XCTAssertEqual(try fixture.target.rawState(), dirty)
        try fixture.target.context.save()
        let corrupt = try fixture.target.rawState()
        XCTAssertThrowsError(try services.primary.destinationReview(reference: reference))
        XCTAssertEqual(try fixture.target.rawState(), corrupt)
        row.receiptSHA256 = digest
        try fixture.target.context.save()
        let quarantine = MutationQuarantineRow(workspaceID: original.envelope.workspaceID,
            mutationID: original.envelope.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: original.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "b", count: 64),
            detectedAt: fixture.initialCheckpoint.updatedAt)
        fixture.target.context.insert(quarantine)
        try fixture.target.context.save()
        let quarantined = try fixture.target.rawState()
        XCTAssertThrowsError(try services.primary.destinationReview(reference: reference))
        XCTAssertEqual(try fixture.target.rawState(), quarantined)
        fixture.target.context.delete(quarantine)
        try fixture.target.context.save()
        XCTAssertNotNil(try services.primary.destinationReview(reference: reference))
        let beforeRetirement = try fixture.target.rawState()
        try fixture.target.coordinator.invalidateAndReleaseWriter()
        XCTAssertThrowsError(try services.primary.destinationReview(reference: reference))
        XCTAssertEqual(try fixture.target.rawState(), beforeRetirement)
        XCTAssertEqual(services.ids.count, 0)
    }

    @MainActor
    func testProductionResolutionFreezesOneChoiceAndRecoversOriginalWithoutNewIDs() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        for plan in [DraftConflictResolutionPlanV1.continueEditing, .reviewAndRebase, .discard] {
            let fixture = try RepetitiveResolutionFixture(source: source)
            defer { try? fixture.close() }
            let services = try DestinationOperationServices(fixture)
            if plan == .reviewAndRebase { try fixture.advance(.pause, state: .paused, mutationSeed: 900) }
            let round = try XCTUnwrap(fixture.rounds().last)
            let prepared = try services.primary.prepareDestinationResolution(
                reviewDraftID: fixture.initialCheckpoint.draftID, plan: plan,
                round: plan == .discard ? nil : round)
            XCTAssertEqual(prepared.attemptState, .notAttempted)
            XCTAssertEqual(services.ids.count, 1)
            let before = try fixture.target.rawState()
            XCTAssertThrowsError(try services.other.persistDestinationResolution(prepared))
            XCTAssertEqual(try fixture.target.rawState(), before)
            let original = try services.primary.persistDestinationResolution(prepared)
            XCTAssertEqual(prepared.attemptState, .checkpointWriteAttempted)
            XCTAssertEqual(original.evidence.original.mutation, prepared.mutation)
            XCTAssertEqual(original.evidence.resolution.plan, plan)
            XCTAssertEqual(original.evidence.resolution.successorCheckpoint, try fixture.currentCheckpoint())
            XCTAssertEqual(try fixture.rounds().last, round)
            try services.primary.validateForPublication(original)
            let settled = try fixture.target.rawState()
            XCTAssertEqual(try services.primary.persistDestinationResolution(prepared).evidence, original.evidence)
            XCTAssertEqual(try services.primary.committedDestinationResolution(prepared)?.evidence, original.evidence)
            XCTAssertEqual(try fixture.target.rawState(), settled)
            XCTAssertEqual(services.ids.count, 1)
            XCTAssertThrowsError(try services.other.validateForPublication(original))
        }
    }

    @MainActor
    func testProductionResolutionRejectsStaleTargetAndRetiredOwnerWithoutEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let services = try DestinationOperationServices(fixture)
        let round = try XCTUnwrap(fixture.rounds().last)
        let prepared = try services.primary.prepareDestinationResolution(
            reviewDraftID: fixture.initialCheckpoint.draftID, plan: .continueEditing, round: round)
        try fixture.advance(.pause, state: .paused, mutationSeed: 901)
        let changed = try fixture.target.rawState()
        XCTAssertThrowsError(try services.primary.persistDestinationResolution(prepared))
        XCTAssertEqual(try fixture.target.rawState(), changed)
        XCTAssertEqual(try fixture.currentCheckpoint(), fixture.initialCheckpoint)
        XCTAssertThrowsError(try services.primary.prepareDestinationResolution(
            reviewDraftID: fixture.initialCheckpoint.draftID, plan: .reviewAndRebase, round: round))
        XCTAssertEqual(try fixture.target.rawState(), changed)
        XCTAssertEqual(services.ids.count, 1)
        try fixture.target.coordinator.invalidateAndReleaseWriter()
        XCTAssertThrowsError(try services.primary.persistDestinationResolution(prepared))
        XCTAssertThrowsError(try services.primary.destinationReview(reviewDraftID: fixture.initialCheckpoint.draftID))
        XCTAssertEqual(try fixture.target.rawState(), changed)
    }

    @MainActor
    func testProductionDiscardRequiresConfirmationThenReplaysOriginalWithoutConfirmationOrEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let services = try DestinationOperationServices(fixture)
        let rounds = try fixture.rounds()
        let choice = try services.primary.prepareDestinationResolution(
            reviewDraftID: fixture.initialCheckpoint.draftID, plan: .discard, round: nil)
        _ = try services.primary.persistDestinationResolution(choice)
        let prepared = try services.primary.prepareDestinationDiscard(reviewDraftID: fixture.initialCheckpoint.draftID)
        XCTAssertTrue(prepared.proposal.plan.nonemptyPayload)
        XCTAssertEqual(services.ids.count, 3)
        let pending = try fixture.target.rawState()
        XCTAssertNil(try services.primary.destinationDiscard(reviewDraftID: fixture.initialCheckpoint.draftID))
        XCTAssertThrowsError(try services.primary.persistDestinationDiscard(prepared, confirmed: false)) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .invalidTransition)
        }
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertThrowsError(try services.other.persistDestinationDiscard(prepared, confirmed: true))
        XCTAssertEqual(try fixture.target.rawState(), pending)
        let original = try services.primary.persistDestinationDiscard(prepared, confirmed: true)
        XCTAssertEqual(prepared.attemptState, .checkpointWriteAttempted)
        XCTAssertEqual(original.evidence.bundle, prepared.proposal.terminalBundle)
        XCTAssertEqual(original.evidence.resolution.resolution.plan, .discard)
        XCTAssertEqual(try fixture.currentCheckpoint().state, .discarded)
        XCTAssertEqual(try fixture.rounds(), rounds)
        try services.primary.validateForPublication(original)
        let settled = try fixture.target.rawState()
        XCTAssertEqual(try services.primary.persistDestinationDiscard(prepared, confirmed: false).evidence,
                       original.evidence)
        XCTAssertEqual(try services.other.destinationDiscard(reviewDraftID: fixture.initialCheckpoint.draftID)?.evidence,
                       original.evidence)
        XCTAssertThrowsError(try services.other.validateForPublication(original))
        XCTAssertEqual(try fixture.target.rawState(), settled)
        XCTAssertEqual(services.ids.count, 3)
    }

    @MainActor
    func testProductionDiscardCanCompleteReviewWithoutOperationalRoundAndRejectsRetirement() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source, materializeRound: false)
        defer { try? fixture.close() }
        let services = try DestinationOperationServices(fixture)
        let choice = try services.primary.prepareDestinationResolution(
            reviewDraftID: fixture.initialCheckpoint.draftID, plan: .discard, round: nil)
        _ = try services.primary.persistDestinationResolution(choice)
        let prepared = try services.primary.prepareDestinationDiscard(reviewDraftID: fixture.initialCheckpoint.draftID)
        let original = try services.primary.persistDestinationDiscard(prepared, confirmed: true)
        XCTAssertTrue(try fixture.rounds().isEmpty)
        let settled = try fixture.target.rawState()
        try fixture.target.coordinator.invalidateAndReleaseWriter()
        XCTAssertThrowsError(try services.primary.persistDestinationDiscard(prepared, confirmed: true))
        XCTAssertThrowsError(try services.primary.validateForPublication(original))
        XCTAssertEqual(try fixture.target.rawState(), settled)
    }
}

private func destinationReference(_ checkpoint: FieldDraftCheckpointV1) -> MyDayEligibleReferenceV1 {
    .resumableDraft(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID,
        revision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
        anchor: checkpoint.resumeAnchor)
}

@MainActor
private struct DestinationOperationServices {
    let primary: ProductionRepetitiveCaptureProgressServiceV2
    let other: ProductionRepetitiveCaptureProgressServiceV2
    let ids = DestinationOperationIDs()

    init(_ fixture: RepetitiveResolutionFixture) throws {
        let clock = DestinationOperationClock()
        let gate = AppAccessGateV1(setting: .absentDisabled, authentication: DestinationOperationAuthentication(),
            clock: clock, identifiers: ids)
        let transitions = try ProductionRoundSessionTransitionServiceV1(session: fixture.target.coordinator,
            accessGate: gate, clock: clock, idSource: ids)
        primary = try .init(session: fixture.target.coordinator, transitions: transitions, clock: clock, idSource: ids)
        other = try .init(session: fixture.target.coordinator, transitions: transitions, clock: clock, idSource: ids)
    }
}

private struct DestinationOperationClock: ApplicationClock {
    func now() -> Date { RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(3_000) }
}

private final class DestinationOperationIDs: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func makeID() -> UUID { lock.lock(); defer { lock.unlock() }; calls += 1; return UUID() }
}

private struct DestinationOperationAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}

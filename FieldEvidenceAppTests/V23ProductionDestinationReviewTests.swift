import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionDestinationReviewTests: XCTestCase {
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

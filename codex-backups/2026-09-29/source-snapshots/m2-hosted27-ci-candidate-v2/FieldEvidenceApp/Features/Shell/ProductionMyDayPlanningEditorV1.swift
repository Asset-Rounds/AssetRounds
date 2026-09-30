import Combine
import Foundation
import SwiftUI

/// Values and one incumbent editing session belonging to the original app
/// publication. This owner has no persistence context or canonical writer.
@MainActor
final class ProductionMyDayPlanningEditorStateV1: ObservableObject, Identifiable {
    let id = UUID()
    let objectWillChange = ObservableObjectPublisher()
    let workspaceID: WorkspaceID
    let initialCivilDate: String
    let initialTimeZone: String

    private let access: AppAccessPresentationV1.MyDayAccess
    private let clock: any ApplicationClock
    private var operationID: UUID?
    private var invalidated = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    #if DEBUG
    private(set) var lastOperationFailureForTesting: String?
    #endif
    private(set) var context: MyDayPlanningContextSnapshotV1?
    private(set) var checkpoints: [FieldDraftCheckpointV1] = []
    private(set) var sources: MyDaySourceSnapshotV1?
    private(set) var editingSession: MyDayPlanningEditingSessionV1?
    private(set) var outcome: MyDayPlanningCommitOutcomeV1?
    private(set) var carryoverEditingSession: MyDayPlanningCarryoverEditingSessionV1?
    private(set) var carryoverSourcePlan: MyDayPlanV1?
    private(set) var carryoverSources: MyDaySourceSnapshotV1?
    private(set) var discardWrite: MyDayPlanningDiscardWriteV1?
    private(set) var discardOutcome: MyDayPlanningDiscardOutcomeV1?
    private(set) var classificationWrite: MyDayPlanningConflictClassificationWriteV1?
    private(set) var conflictReview: MyDayPlanningConflictReviewV1?
    private(set) var reviewedRebaseWrite: MyDayPlanningReviewedResolutionWriteV1?
    private(set) var carryoverClassificationWrite: MyDayPlanningCarryoverConflictClassificationWriteV1?
    private(set) var carryoverConflictReview: MyDayPlanningCarryoverConflictReviewV1?
    private(set) var reviewedCarryoverRebaseWrite: MyDayPlanningReviewedCarryoverResolutionWriteV1?
    private var classificationExecuteAttempted = false
    private var reviewedRebaseExecuteAttempted = false
    private var carryoverClassificationExecuteAttempted = false
    private var reviewedCarryoverRebaseExecuteAttempted = false
    private var acknowledgedRebaseDraftID: UUID?

    var hasEditingSession: Bool { editingSession != nil || carryoverEditingSession != nil }
    var canCancelPreparedConflictReview: Bool {
        (classificationWrite != nil && !classificationExecuteAttempted)
            || (reviewedRebaseWrite != nil && !reviewedRebaseExecuteAttempted)
            || (carryoverClassificationWrite != nil && !carryoverClassificationExecuteAttempted)
            || (reviewedCarryoverRebaseWrite != nil && !reviewedCarryoverRebaseExecuteAttempted)
    }
    var hasPendingPlanningOperation: Bool {
        discardWrite != nil || classificationWrite != nil || conflictReview != nil || reviewedRebaseWrite != nil
            || carryoverClassificationWrite != nil || carryoverConflictReview != nil
            || reviewedCarryoverRebaseWrite != nil
    }
    var carryoverSelectableItems: [MyDayItemV1] {
        guard let source = carryoverSourcePlan, let facts = carryoverSources else { return [] }
        return selectableCarryoverItems(source: source, facts: facts, target: context?.currentPlan)
    }

    #if DEBUG
    /// Runs after the actual source read without replacing its values.
    var afterResumeSourcesReadyForTesting: (@MainActor () async throws -> Void)?
    var afterClassificationAcknowledgementForTesting:
        (@MainActor @Sendable (MyDayPlanningCheckpointAcknowledgementV1) async throws -> Void)?
    var afterReviewedRebaseAcknowledgementForTesting:
        (@MainActor @Sendable (MyDayPlanningCheckpointAcknowledgementV1) async throws -> Void)?
    #endif

    init(workspaceID: WorkspaceID, access: AppAccessPresentationV1.MyDayAccess,
         clock: any ApplicationClock = SystemApplicationClock()) {
        self.workspaceID = workspaceID
        self.access = access
        self.clock = clock
        let zone = TimeZone.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        initialCivilDate = formatter.string(from: clock.now())
        initialTimeZone = zone.identifier
    }

    @discardableResult
    func openDay(civilDate: String, timeZone: String) async -> Bool {
        await perform(failure: "Could not open this day. Check the date and time zone, then try again.") { operation in
            guard !self.hasEditingSession, !self.hasPendingPlanningOperation else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let key = try MyDayKeyV1(workspaceID: self.workspaceID,
                civilDate: ScheduleLocalDateV1(civilDate), ianaTimeZoneIdentifier: timeZone)
            let context = try self.access.planningContext(for: key)
            let sources = try await self.access.snapshot(for: context.currentPlan, evaluatedAt: self.instant())
            let current = try self.access.planningContext(for: key)
            guard current.currentPlan == context.currentPlan else { throw MyDayWorkflowFailureV1.staleProjection }
            let checkpoints = try self.access.planningCheckpoints(for: key)
            try self.publish(operation) {
                self.context = current
                self.sources = sources
                self.checkpoints = checkpoints
                self.outcome = nil
                self.discardWrite = nil
                self.discardOutcome = nil
                self.carryoverSourcePlan = nil
                self.carryoverSources = nil
            }
        }
    }

    @discardableResult
    func beginNew(recordedByName: String) async -> Bool {
        await perform(failure: "Could not open the plan. Check the recorder name or reopen the day and try again.") { operation in
            guard let context = self.context, let sources = self.sources,
                  !self.hasEditingSession, !self.hasPendingPlanningOperation,
                  self.checkpoints.isEmpty else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let current = try self.access.planningContext(for: context.key)
            guard current.currentPlan == context.currentPlan,
                  try self.access.planningCheckpoints(for: context.key).isEmpty else {
                throw MyDayWorkflowFailureV1.staleProjection
            }
            let confirmed = try self.access.captureConfirmedPlanningContext(
                for: context.key, recordedByName: recordedByName)
            let items = try (current.currentPlan?.items ?? []).map {
                try MyDayDraftItemV1(membershipID: $0.membershipID, reference: $0.reference, estimate: $0.estimate)
            }
            let draft = try MyDayWorkflowCoordinatorV1.projectDraft(key: context.key,
                selectedItems: items, eligibleReferences: sources.eligibleReferences,
                predecessor: current.currentPlan)
            let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: confirmed,
                draft: draft, predecessor: current.currentPlan)
            let session = try MyDayPlanningEditingSessionV1(request: request,
                resumeAnchor: DraftResumeAnchorV1(sectionID: "my-day"), access: self.access)
            try self.publish(operation) { self.editingSession = session }
            try await session.start()
        }
    }

    @discardableResult
    func resume(draftID: UUID) async -> Bool {
        await perform(failure: "This draft could not be resumed. Reopen the day to check its current state.") { operation in
            guard let context = self.context, !self.hasEditingSession,
                  !self.hasPendingPlanningOperation else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let checkpoint = try self.access.loadPlanningCheckpoint(draftID: draftID)
            guard checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)) else {
                throw MyDayWorkflowFailureV1.invalidContext
            }
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
            if case .carryover? = payload.editingIntent {
                try await self.resumeCarryover(checkpoint: checkpoint, operation: operation)
                return
            }
            let session = try MyDayPlanningEditingSessionV1(resumingDraftID: draftID, access: self.access)
            guard session.request.predecessor == (try self.access.planningContext(for: context.key)).currentPlan else {
                throw MyDayWorkflowFailureV1.staleProjection
            }
            let sources = try await self.access.snapshot(for: session.request.predecessor, evaluatedAt: self.instant())
            #if DEBUG
            try await self.afterResumeSourcesReadyForTesting?()
            #endif
            let currentCheckpoint = try self.access.loadPlanningCheckpoint(draftID: draftID)
            guard currentCheckpoint == checkpoint, currentCheckpoint.state == .active,
                  session.request.predecessor == (try self.access.planningContext(for: context.key)).currentPlan else {
                throw MyDayWorkflowFailureV1.staleProjection
            }
            try self.publish(operation) {
                self.sources = sources
                self.editingSession = session
            }
            try await session.start()
        }
    }

    @discardableResult
    func finishSave(draftID: UUID) async -> Bool {
        await perform(failure: "The plan has not finished saving. Try again to continue the same save.") { operation in
            guard let context = self.context, !self.hasEditingSession,
                  !self.hasPendingPlanningOperation else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let checkpoint = try self.access.loadPlanningCheckpoint(draftID: draftID)
            guard checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)),
                  checkpoint.state == .committing else { throw MyDayPlanningExecutionFailureV1.unsupportedState }
            let result = try await self.access.retryPlanningCommit(draftID: draftID)
            try self.publish(operation) { self.outcome = result }
        }
    }

    var canOfferStalePlanReview: Bool {
        guard let session = editingSession, !session.hasDirtyChanges, !session.isCommitInFlight,
              session.commitOutcome == nil, session.durabilityState == .saveBlocked,
              carryoverEditingSession == nil, discardWrite == nil, classificationWrite == nil,
              conflictReview == nil, reviewedRebaseWrite == nil,
              carryoverClassificationWrite == nil, carryoverConflictReview == nil,
              reviewedCarryoverRebaseWrite == nil else { return false }
        return true
    }

    @discardableResult
    func requestStalePlanReview() async -> Bool {
        await perform(failure: "This draft cannot be reviewed as a plan change. Continue saving or return to saved drafts.") { operation in
            guard let session = self.editingSession, self.canOfferStalePlanReview else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let write = try self.access.prepareStalePlanPredecessorConflict(draftID: session.draftID)
            try self.publish(operation) { self.classificationWrite = write }
        }
    }

    @discardableResult
    func requestStalePlanReview(draftID: UUID) async -> Bool {
        await perform(failure: "This draft cannot be reviewed as a plan change. Continue saving or return to saved drafts.") { operation in
            guard let context = self.context, self.editingSession == nil,
                  self.carryoverEditingSession == nil, self.discardWrite == nil,
                  self.outcome == nil, self.classificationWrite == nil,
                  self.conflictReview == nil, self.reviewedRebaseWrite == nil,
                  self.carryoverClassificationWrite == nil, self.carryoverConflictReview == nil,
                  self.reviewedCarryoverRebaseWrite == nil,
                  let checkpoint = self.checkpoints.first(where: { $0.draftID == draftID }),
                  checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)),
                  [.active, .committing].contains(checkpoint.state) else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
            switch (checkpoint.state, payload.phase) {
            case (.active, .editing):
                guard case .plan? = payload.editingIntent else {
                    throw MyDayPlanningExecutionFailureV1.unsupportedState
                }
            case (.committing, .preparedCommit):
                guard case .save? = payload.commitAttempt?.command else {
                    throw MyDayPlanningExecutionFailureV1.unsupportedState
                }
            default:
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let write = try self.access.prepareStalePlanPredecessorConflict(draftID: draftID)
            guard write.evidence.currentCheckpoint == checkpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            try self.publish(operation) { self.classificationWrite = write }
        }
    }

    @discardableResult
    func cancelPreparedConflictReview() async -> Bool {
        await perform(failure: "The saved drafts could not be refreshed.") { operation in
            guard (self.classificationWrite != nil && !self.classificationExecuteAttempted)
                    || (self.reviewedRebaseWrite != nil && !self.reviewedRebaseExecuteAttempted)
                    || (self.carryoverClassificationWrite != nil && !self.carryoverClassificationExecuteAttempted)
                    || (self.reviewedCarryoverRebaseWrite != nil && !self.reviewedCarryoverRebaseExecuteAttempted),
                  let context = self.context else { throw MyDayPlanningExecutionFailureV1.unsupportedState }
            let current = try self.access.planningContext(for: context.key)
            let drafts = try self.access.planningCheckpoints(for: context.key)
            try self.publish(operation) {
                self.classificationWrite = nil
                self.reviewedRebaseWrite = nil
                self.classificationExecuteAttempted = false
                self.reviewedRebaseExecuteAttempted = false
                self.carryoverClassificationWrite = nil
                self.reviewedCarryoverRebaseWrite = nil
                self.carryoverClassificationExecuteAttempted = false
                self.reviewedCarryoverRebaseExecuteAttempted = false
                self.conflictReview = nil
                self.carryoverConflictReview = nil
                self.context = current
                self.checkpoints = drafts
            }
        }
    }

    @discardableResult
    func backToSavedDrafts() async -> Bool {
        await perform(failure: "The saved drafts could not be refreshed.") { operation in
            guard self.classificationWrite == nil, self.reviewedRebaseWrite == nil,
                  self.carryoverClassificationWrite == nil, self.reviewedCarryoverRebaseWrite == nil,
                  (self.conflictReview != nil || self.carryoverConflictReview != nil),
                  let context = self.context else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let current = try self.access.planningContext(for: context.key)
            let drafts = try self.access.planningCheckpoints(for: context.key)
            try self.publish(operation) {
                self.conflictReview = nil
                self.carryoverConflictReview = nil
                self.context = current
                self.checkpoints = drafts
            }
        }
    }

    @discardableResult
    func confirmStalePlanReview() async -> Bool {
        await completeStalePlanReview(retry: false)
    }

    @discardableResult
    func retryStalePlanReview() async -> Bool {
        await completeStalePlanReview(retry: true)
    }

    private func completeStalePlanReview(retry: Bool) async -> Bool {
        await perform(failure: "The plan review has not finished. Retry review to continue the same review.") { operation in
            guard let write = self.classificationWrite else { throw MyDayPlanningExecutionFailureV1.unsupportedState }
            try self.publish(operation) { self.classificationExecuteAttempted = true }
            let acknowledgement = try (retry
                ? self.access.retryStalePlanPredecessorConflict(write)
                : self.access.executeStalePlanPredecessorConflict(write))
            #if DEBUG
            try await self.afterClassificationAcknowledgementForTesting?(acknowledgement)
            #endif
            let review = try self.access.planningConflictReview(draftID: acknowledgement.checkpoint.draftID)
            guard review.pending.conflictedCheckpoint == acknowledgement.checkpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            let oldSession = self.editingSession
            try self.publish(operation) {
                self.classificationWrite = nil
                self.classificationExecuteAttempted = false
                self.conflictReview = review
                self.editingSession = nil
                self.checkpoints = [acknowledgement.checkpoint]
            }
            Task { await oldSession?.invalidate() }
        }
    }

    @discardableResult
    func requestExistingConflictReview(draftID: UUID) async -> Bool {
        await perform(failure: "This draft cannot be reviewed right now. Return to saved drafts and try again.") { operation in
            guard let context = self.context, self.editingSession == nil,
                  self.carryoverEditingSession == nil, self.discardWrite == nil,
                  self.outcome == nil, self.classificationWrite == nil,
                  self.conflictReview == nil, self.reviewedRebaseWrite == nil,
                  self.carryoverClassificationWrite == nil, self.carryoverConflictReview == nil,
                  self.reviewedCarryoverRebaseWrite == nil,
                  let checkpoint = self.checkpoints.first(where: { $0.draftID == draftID }),
                  checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)),
                  checkpoint.state == .conflicted else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let review = try self.access.planningConflictReview(draftID: draftID)
            guard review.pending.conflictedCheckpoint == checkpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            try self.publish(operation) { self.conflictReview = review }
        }
    }

    @discardableResult
    func confirmReviewedRebase() async -> Bool {
        await completeReviewedRebase(retry: false)
    }

    @discardableResult
    func retryReviewedRebase() async -> Bool {
        await completeReviewedRebase(retry: true)
    }

    private func completeReviewedRebase(retry: Bool) async -> Bool {
        let completed = await perform(failure: "The plan review has not finished. Retry review to continue the same review.") { operation in
            guard retry || self.reviewedRebaseWrite == nil else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            if !retry, let review = self.conflictReview {
                let write = try self.access.prepareReviewedPlanRebase(review,
                    editedDraft: review.originalEditingRequest.draft)
                try self.publish(operation) {
                    self.reviewedRebaseWrite = write
                    self.reviewedRebaseExecuteAttempted = false
                }
            }
            guard let write = self.reviewedRebaseWrite else { throw MyDayPlanningExecutionFailureV1.unsupportedState }
            try self.publish(operation) { self.reviewedRebaseExecuteAttempted = true }
            let acknowledgement = try (retry
                ? self.access.retryReviewedPlanRebase(write)
                : self.access.executeReviewedPlanRebase(write))
            guard acknowledgement.checkpoint == write.resolution.successorCheckpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            #if DEBUG
            try await self.afterReviewedRebaseAcknowledgementForTesting?(acknowledgement)
            #endif
            let key = write.review.originalEditingRequest.confirmedContext.key
            let current = try? self.access.planningContext(for: key)
            let drafts = try? self.access.planningCheckpoints(for: key)
            try self.publish(operation) {
                self.reviewedRebaseWrite = nil
                self.reviewedRebaseExecuteAttempted = false
                self.conflictReview = nil
                self.outcome = nil
                self.context = current ?? self.context
                if let drafts, drafts.contains(acknowledgement.checkpoint) {
                    self.checkpoints = drafts
                } else {
                    self.checkpoints = [acknowledgement.checkpoint]
                }
                self.acknowledgedRebaseDraftID = acknowledgement.checkpoint.draftID
            }
        }
        guard completed, let draftID = acknowledgedRebaseDraftID else { return completed }
        acknowledgedRebaseDraftID = nil
        _ = await resume(draftID: draftID)
        return true
    }

    var canOfferStaleCarryoverReview: Bool {
        guard let session = carryoverEditingSession, !session.hasDirtyChanges, !session.isCommitInFlight,
              session.commitOutcome == nil, session.durabilityState == .saveBlocked,
              editingSession == nil, discardWrite == nil, classificationWrite == nil,
              conflictReview == nil, reviewedRebaseWrite == nil,
              carryoverClassificationWrite == nil, carryoverConflictReview == nil,
              reviewedCarryoverRebaseWrite == nil else { return false }
        return true
    }

    @discardableResult
    func requestStaleCarryoverReview() async -> Bool {
        await perform(failure: "This carryover draft cannot be reviewed. Continue saving or return to saved drafts.") { operation in
            guard let session = self.carryoverEditingSession, self.canOfferStaleCarryoverReview else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let write = try self.access.prepareStaleCarryoverTargetConflict(draftID: session.draftID)
            try self.publish(operation) { self.carryoverClassificationWrite = write }
        }
    }

    @discardableResult
    func requestStaleCarryoverReview(draftID: UUID) async -> Bool {
        await perform(failure: "This carryover draft cannot be reviewed. Continue saving or return to saved drafts.") { operation in
            guard let context = self.context, self.editingSession == nil,
                  self.carryoverEditingSession == nil, self.discardWrite == nil,
                  self.outcome == nil, self.classificationWrite == nil,
                  self.conflictReview == nil, self.reviewedRebaseWrite == nil,
                  self.carryoverClassificationWrite == nil, self.carryoverConflictReview == nil,
                  self.reviewedCarryoverRebaseWrite == nil,
                  let checkpoint = self.checkpoints.first(where: { $0.draftID == draftID }),
                  checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)),
                  [.active, .committing].contains(checkpoint.state) else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
            switch (checkpoint.state, payload.phase) {
            case (.active, .editing):
                guard case .carryover? = payload.editingIntent else {
                    throw MyDayPlanningExecutionFailureV1.unsupportedState
                }
            case (.committing, .preparedCommit):
                guard case .carryover? = payload.commitAttempt?.command else {
                    throw MyDayPlanningExecutionFailureV1.unsupportedState
                }
            default:
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let write = try self.access.prepareStaleCarryoverTargetConflict(draftID: draftID)
            guard write.evidence.currentCheckpoint == checkpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            try self.publish(operation) { self.carryoverClassificationWrite = write }
        }
    }

    @discardableResult
    func confirmStaleCarryoverReview() async -> Bool {
        await completeStaleCarryoverReview(retry: false)
    }

    @discardableResult
    func retryStaleCarryoverReview() async -> Bool {
        await completeStaleCarryoverReview(retry: true)
    }

    private func completeStaleCarryoverReview(retry: Bool) async -> Bool {
        await perform(failure: "The carryover review has not finished. Retry review to continue the same review.") { operation in
            guard let write = self.carryoverClassificationWrite else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            try self.publish(operation) { self.carryoverClassificationExecuteAttempted = true }
            let acknowledgement = try (retry
                ? self.access.retryStaleCarryoverTargetConflict(write)
                : self.access.executeStaleCarryoverTargetConflict(write))
            #if DEBUG
            try await self.afterClassificationAcknowledgementForTesting?(acknowledgement)
            #endif
            let review = try self.access.carryoverConflictReview(draftID: acknowledgement.checkpoint.draftID)
            guard review.pending.conflictedCheckpoint == acknowledgement.checkpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            let oldSession = self.carryoverEditingSession
            try self.publish(operation) {
                self.carryoverClassificationWrite = nil
                self.carryoverClassificationExecuteAttempted = false
                self.carryoverConflictReview = review
                self.carryoverEditingSession = nil
                self.checkpoints = [acknowledgement.checkpoint]
            }
            Task { await oldSession?.invalidate() }
        }
    }

    @discardableResult
    func requestExistingCarryoverConflictReview(draftID: UUID) async -> Bool {
        await perform(failure: "This carryover draft cannot be reviewed right now. Return to saved drafts and try again.") { operation in
            guard let context = self.context, self.editingSession == nil,
                  self.carryoverEditingSession == nil, self.discardWrite == nil,
                  self.outcome == nil, self.classificationWrite == nil,
                  self.conflictReview == nil, self.reviewedRebaseWrite == nil,
                  self.carryoverClassificationWrite == nil, self.carryoverConflictReview == nil,
                  self.reviewedCarryoverRebaseWrite == nil,
                  let checkpoint = self.checkpoints.first(where: { $0.draftID == draftID }),
                  checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)),
                  checkpoint.state == .conflicted,
                  self.isCarryoverConflictCandidate(checkpoint) else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let review = try self.access.carryoverConflictReview(draftID: draftID)
            guard review.pending.conflictedCheckpoint == checkpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            try self.publish(operation) { self.carryoverConflictReview = review }
        }
    }

    @discardableResult
    func confirmReviewedCarryoverRebase() async -> Bool {
        await completeReviewedCarryoverRebase(retry: false)
    }

    @discardableResult
    func retryReviewedCarryoverRebase() async -> Bool {
        await completeReviewedCarryoverRebase(retry: true)
    }

    private func completeReviewedCarryoverRebase(retry: Bool) async -> Bool {
        let completed = await perform(failure: "The carryover review has not finished. Retry review to continue the same review.") { operation in
            guard retry || self.reviewedCarryoverRebaseWrite == nil else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            if !retry, let review = self.carryoverConflictReview {
                let write = try self.access.prepareReviewedCarryoverRebase(review)
                try self.publish(operation) {
                    self.reviewedCarryoverRebaseWrite = write
                    self.reviewedCarryoverRebaseExecuteAttempted = false
                }
            }
            guard let write = self.reviewedCarryoverRebaseWrite else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            try self.publish(operation) { self.reviewedCarryoverRebaseExecuteAttempted = true }
            let acknowledgement = try (retry
                ? self.access.retryReviewedCarryoverRebase(write)
                : self.access.executeReviewedCarryoverRebase(write))
            guard acknowledgement.checkpoint == write.resolution.successorCheckpoint else {
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
            #if DEBUG
            try await self.afterReviewedRebaseAcknowledgementForTesting?(acknowledgement)
            #endif
            let key = write.review.originalEditingRequest.confirmedContext.key
            let current = try? self.access.planningContext(for: key)
            let drafts = try? self.access.planningCheckpoints(for: key)
            try self.publish(operation) {
                self.reviewedCarryoverRebaseWrite = nil
                self.reviewedCarryoverRebaseExecuteAttempted = false
                self.carryoverConflictReview = nil
                self.outcome = nil
                self.context = current ?? self.context
                if let drafts, drafts.contains(acknowledgement.checkpoint) {
                    self.checkpoints = drafts
                } else {
                    self.checkpoints = [acknowledgement.checkpoint]
                }
                self.acknowledgedRebaseDraftID = acknowledgement.checkpoint.draftID
            }
        }
        guard completed, let draftID = acknowledgedRebaseDraftID else { return completed }
        acknowledgedRebaseDraftID = nil
        _ = await resume(draftID: draftID)
        return true
    }

    func isCarryoverConflictCandidate(_ checkpoint: FieldDraftCheckpointV1) -> Bool {
        guard let payload = try? MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint) else {
            return false
        }
        switch (checkpoint.state, payload.phase) {
        case (.active, .editing), (.conflicted, .editing):
            if case .carryover? = payload.editingIntent { return true }
        case (.committing, .preparedCommit), (.conflicted, .preparedCommit):
            if case .carryover? = payload.commitAttempt?.command { return true }
        default:
            break
        }
        return false
    }

    func canDiscard(_ checkpoint: FieldDraftCheckpointV1) -> Bool {
        guard let context, let scope = try? MyDayPlanningDraftCodecV1.scope(for: context.key),
              !hasEditingSession, !hasPendingPlanningOperation, discardOutcome == nil,
              checkpoint.scope == scope,
              checkpoints.contains(checkpoint),
              [.active, .recoveryRequired, .discardPending].contains(checkpoint.state),
              let payload = try? MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint),
              payload.phase == .editing else {
            return false
        }
        return true
    }

    @discardableResult
    func requestDiscard(checkpoint: FieldDraftCheckpointV1) async -> Bool {
        await perform(failure: "This saved draft changed. Review the current saved drafts before discarding it.") { operation in
            guard self.canDiscard(checkpoint), let context = self.context,
                  checkpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)) else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            do {
                let write = try self.access.preparePlanningDiscard(expectedCheckpoint: checkpoint)
                try self.publish(operation) {
                    self.discardWrite = write
                    self.discardOutcome = nil
                }
            } catch {
                let current = try self.access.planningContext(for: context.key)
                let drafts = try self.access.planningCheckpoints(for: context.key)
                try self.publish(operation) {
                    self.context = current
                    self.checkpoints = drafts
                    self.carryoverSourcePlan = nil
                    self.carryoverSources = nil
                }
                throw error
            }
        }
    }

    @discardableResult
    func confirmDiscard(_ write: MyDayPlanningDiscardWriteV1) async -> Bool {
        await perform(failure: "Discard is not confirmed. Try again, or go back to review saved drafts.") { operation in
            guard let context = self.context, self.discardWrite == write,
                  write.expectedCheckpoint.scope == (try MyDayPlanningDraftCodecV1.scope(for: context.key)),
                  self.editingSession == nil, self.carryoverEditingSession == nil else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            do {
                let result = try await self.access.discardPlanningDraft(write)
                let current = try self.access.planningContext(for: context.key)
                let drafts = try self.access.planningCheckpoints(for: context.key)
                guard current.key == context.key,
                      !drafts.contains(where: { $0.draftID == write.expectedCheckpoint.draftID }) else {
                    throw MyDayWorkflowFailureV1.staleProjection
                }
                try self.publish(operation) {
                    self.context = current
                    self.checkpoints = drafts
                    self.discardWrite = nil
                    self.discardOutcome = result
                    self.outcome = nil
                    self.carryoverSourcePlan = nil
                    self.carryoverSources = nil
                }
            } catch {
                let current = try self.access.planningContext(for: context.key)
                let drafts = try self.access.planningCheckpoints(for: context.key)
                let visibleDrafts = drafts.contains(where: { $0.draftID == write.expectedCheckpoint.draftID })
                    ? drafts : drafts + [write.expectedCheckpoint]
                try self.publish(operation) {
                    self.context = current
                    self.checkpoints = visibleDrafts
                    self.discardOutcome = nil
                    self.carryoverSourcePlan = nil
                    self.carryoverSources = nil
                }
                throw error
            }
        }
    }

    @discardableResult
    func cancelDiscard(_ write: MyDayPlanningDiscardWriteV1) async -> Bool {
        await perform(failure: "The saved draft could not be refreshed. Reopen the day to review its current state.") { operation in
            guard let context = self.context, self.discardWrite == write else {
                throw MyDayPlanningExecutionFailureV1.unsupportedState
            }
            let current = try self.access.planningContext(for: context.key)
            let drafts = try self.access.planningCheckpoints(for: context.key)
            try self.publish(operation) {
                self.context = current
                self.checkpoints = drafts
                self.discardWrite = nil
                self.discardOutcome = nil
                self.carryoverSourcePlan = nil
                self.carryoverSources = nil
            }
        }
    }

    @discardableResult
    func add(_ reference: MyDayEligibleReferenceV1) async -> Bool {
        await edit { request in
            let id = try self.access.nextPlanningMembershipID()
            return request.draft.items + [try MyDayDraftItemV1(membershipID: id, reference: reference)]
        }
    }

    @discardableResult
    func remove(membershipID: UUID) async -> Bool {
        await edit { request in
            guard request.draft.items.contains(where: { $0.membershipID == membershipID }) else {
                throw MyDayWorkflowFailureV1.invalidManualOrder
            }
            return request.draft.items.filter { $0.membershipID != membershipID }
        }
    }

    @discardableResult
    func move(_ action: MyDayAccessibleMoveV1) async -> Bool {
        await edit { request in
            try MyDayWorkflowCoordinatorV1.projectMove(request.draft, action: action).items
        }
    }

    @discardableResult
    func estimate(membershipID: UUID, wholeMinutes: Int?) async -> Bool {
        await edit { request in
            guard request.draft.items.contains(where: { $0.membershipID == membershipID }) else {
                throw MyDayWorkflowFailureV1.invalidManualOrder
            }
            let estimate = try wholeMinutes.map { try MyDayEstimateV1(wholeMinutes: $0) }
            return try request.draft.items.map { item in
                guard item.membershipID == membershipID else { return item }
                return try MyDayDraftItemV1(membershipID: item.membershipID,
                    reference: item.reference, estimate: estimate)
            }
        }
    }

    @discardableResult
    func save() async -> Bool {
        await perform(failure: "The plan has not finished saving. Try again to continue the same save.") { operation in
            let result: MyDayPlanningCommitOutcomeV1
            if let session = self.editingSession { result = try await session.save() }
            else if let session = self.carryoverEditingSession { result = try await session.save() }
            else { throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle }
            try self.publish(operation) { self.outcome = result }
        }
    }

    @discardableResult
    func flush(reason: MyDayPlanningEditingFlushReasonV1) async -> Bool {
        if classificationWrite != nil || reviewedRebaseWrite != nil
            || carryoverClassificationWrite != nil || reviewedCarryoverRebaseWrite != nil {
            return await perform(failure: "The plan review has not finished. Retry review before closing.") { _ in
                throw MyDayPlanningExecutionFailureV1.incompleteReadback
            }
        }
        let unfinishedPlan = (editingSession.map { $0.durabilityState == .saveBlocked && !$0.hasDirtyChanges } ?? false)
            || (carryoverEditingSession.map { $0.durabilityState == .saveBlocked && !$0.hasDirtyChanges } ?? false)
        let message = unfinishedPlan
            ? "The plan has not finished saving. Choose Retry saving plan before closing."
            : "Changes have not been saved on this iPhone. Keep this editor open and try again."
        return await perform(failure: message) { _ in
            if let session = self.editingSession, session.commitOutcome == nil {
                guard session.durabilityState != .saveBlocked || session.hasDirtyChanges else {
                    throw MyDayPlanningExecutionFailureV1.incompleteReadback
                }
                try await session.forceFlush(reason: reason)
            }
            if let session = self.carryoverEditingSession, session.commitOutcome == nil {
                guard session.durabilityState != .saveBlocked || session.hasDirtyChanges else {
                    throw MyDayPlanningExecutionFailureV1.incompleteReadback
                }
                try await session.forceFlush(reason: reason)
            }
        }
    }

    func discardPresentation() {
        guard !invalidated else { return }
        invalidated = true
        objectWillChange.send()
        operationID = nil
        isBusy = false
        errorMessage = nil
        context = nil
        checkpoints = []
        sources = nil
        outcome = nil
        discardWrite = nil
        discardOutcome = nil
        classificationWrite = nil
        conflictReview = nil
        reviewedRebaseWrite = nil
        carryoverClassificationWrite = nil
        carryoverConflictReview = nil
        reviewedCarryoverRebaseWrite = nil
        classificationExecuteAttempted = false
        reviewedRebaseExecuteAttempted = false
        carryoverClassificationExecuteAttempted = false
        reviewedCarryoverRebaseExecuteAttempted = false
        acknowledgedRebaseDraftID = nil
        let session = editingSession
        editingSession = nil
        let carryoverSession = carryoverEditingSession
        carryoverEditingSession = nil
        carryoverSourcePlan = nil
        carryoverSources = nil
        Task {
            await session?.invalidate()
            await carryoverSession?.invalidate()
        }
    }

    private func edit(_ change: (MyDayPlanningPlanSaveRequestV1) throws -> [MyDayDraftItemV1]) async -> Bool {
        await perform(failure: "The change could not be kept. Check the item and try again.") { _ in
            guard let session = self.editingSession, let sources = self.sources else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let previous = session.request
            let draft = try MyDayWorkflowCoordinatorV1.projectDraft(key: previous.confirmedContext.key,
                selectedItems: change(previous), eligibleReferences: sources.eligibleReferences,
                predecessor: previous.predecessor)
            let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: previous.confirmedContext,
                draft: draft, predecessor: previous.predecessor)
            try await session.meaningfulEdit(request, resumeAnchor: DraftResumeAnchorV1(sectionID: "my-day"))
        }
    }


    @discardableResult
    func openCarryoverSource(civilDate: String, timeZone: String) async -> Bool {
        await perform(failure: "Could not open the source plan. Check both days and try again.") { operation in
            guard let target = self.context, !self.hasEditingSession,
                  !self.hasPendingPlanningOperation, self.checkpoints.isEmpty else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let key = try MyDayKeyV1(workspaceID: self.workspaceID,
                civilDate: .init(civilDate), ianaTimeZoneIdentifier: timeZone)
            guard key != target.key,
                  let source = try self.access.planningContext(for: key).currentPlan else {
                throw MyDayWorkflowFailureV1.invalidContext
            }
            let facts = try await self.access.snapshot(for: source, evaluatedAt: self.instant())
            try self.validateCarryoverTips(source: source, target: target)
            try self.publish(operation) {
                self.carryoverSourcePlan = source
                self.carryoverSources = facts
            }
        }
    }

    @discardableResult
    func beginCarryover(selectedMembershipIDs: [UUID], recordedByName: String) async -> Bool {
        await perform(failure: "Could not begin carryover. Reopen both plans and check the selected work and recorder.") { operation in
            guard let source = self.carryoverSourcePlan, let target = self.context,
                  !self.hasEditingSession, !self.hasPendingPlanningOperation,
                  self.checkpoints.isEmpty else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let facts = try await self.access.snapshot(for: source, evaluatedAt: self.instant())
            try self.validateCarryoverTips(source: source, target: target)
            let ordered = try self.orderedCarryoverSelection(selectedMembershipIDs,
                source: source, facts: facts, target: target.currentPlan)
            let confirmed = try self.access.captureConfirmedPlanningContext(for: target.key,
                recordedByName: recordedByName)
            let request = try MyDayPlanningCarryoverRequestV1(confirmedContext: confirmed,
                sourcePlan: MyDayPlanReferenceV1(source), selectedMembershipIDs: ordered,
                targetPredecessor: target.currentPlan.map { try MyDayPlanReferenceV1($0) })
            let session = try MyDayPlanningCarryoverEditingSessionV1(request: request,
                resumeAnchor: .init(sectionID: "carryover"), access: self.access)
            try self.publish(operation) {
                self.carryoverSources = facts
                self.carryoverEditingSession = session
            }
            try await session.start()
        }
    }

    @discardableResult
    func selectCarryover(membershipID: UUID, selected: Bool) async -> Bool {
        await perform(failure: "The selection could not be kept. Keep at least one eligible item selected.") { _ in
            guard let session = self.carryoverEditingSession, let source = self.carryoverSourcePlan,
                  let facts = self.carryoverSources else {
                throw MyDayPlanningEditingSessionFailureV1.invalidLifecycle
            }
            let previous = session.request
            guard source.items.contains(where: { $0.membershipID == membershipID }) else {
                throw MyDayWorkflowFailureV1.carryoverIneligible
            }
            var membershipIDs = Set(previous.selectedMembershipIDs)
            if selected { membershipIDs.insert(membershipID) } else { membershipIDs.remove(membershipID) }
            let ordered = try self.orderedCarryoverSelection(Array(membershipIDs), source: source,
                facts: facts, target: self.context?.currentPlan)
            let request = try MyDayPlanningCarryoverRequestV1(confirmedContext: previous.confirmedContext,
                sourcePlan: previous.sourcePlan, selectedMembershipIDs: ordered,
                targetPredecessor: previous.targetPredecessor)
            try await session.meaningfulEdit(request, resumeAnchor: .init(sectionID: "carryover"))
        }
    }

    private func resumeCarryover(checkpoint: FieldDraftCheckpointV1, operation: UUID) async throws {
        guard let target = context else { throw MyDayWorkflowFailureV1.invalidContext }
        let session = try MyDayPlanningCarryoverEditingSessionV1(resumingDraftID: checkpoint.draftID, access: access)
        let request = session.request
        guard let source = try access.planningContext(for: request.sourcePlan.key).currentPlan,
              try MyDayPlanReferenceV1(source) == request.sourcePlan,
              try target.currentPlan.map({ try MyDayPlanReferenceV1($0) }) == request.targetPredecessor else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
        let facts = try await access.snapshot(for: source, evaluatedAt: instant())
        #if DEBUG
        try await afterResumeSourcesReadyForTesting?()
        #endif
        try validateCarryoverTips(source: source, target: target, resuming: checkpoint.draftID)
        guard try access.loadPlanningCheckpoint(draftID: checkpoint.draftID) == checkpoint else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
        let ordered = try orderedCarryoverSelection(request.selectedMembershipIDs,
            source: source, facts: facts, target: target.currentPlan)
        guard ordered == request.selectedMembershipIDs else { throw MyDayWorkflowFailureV1.staleProjection }
        try publish(operation) {
            carryoverSourcePlan = source
            carryoverSources = facts
            carryoverEditingSession = session
        }
        try await session.start()
    }

    private func validateCarryoverTips(source: MyDayPlanV1, target: MyDayPlanningContextSnapshotV1,
                                       resuming draftID: UUID? = nil) throws {
        guard try access.planningContext(for: source.key).currentPlan == source,
              try access.planningContext(for: target.key).currentPlan == target.currentPlan else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
        let drafts = try access.planningCheckpoints(for: target.key)
        guard drafts.allSatisfy({ $0.draftID == draftID }) else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
    }

    private func selectableCarryoverItems(source: MyDayPlanV1, facts: MyDaySourceSnapshotV1,
                                          target: MyDayPlanV1?) -> [MyDayItemV1] {
        source.items.filter { item in
            guard !(target?.items.contains { $0.membershipID == item.membershipID
                || $0.reference.stableKey == item.reference.stableKey } ?? false),
                  let frontier = facts.frontiers.first(where: { $0.membershipID == item.membershipID }),
                  frontier.plannedReference == item.reference else { return false }
            return MyDaySummaryItemV1.isCarryoverEligible(plannedReference: item.reference,
                currentReference: frontier.currentReference, state: frontier.state)
        }
    }

    private func orderedCarryoverSelection(_ membershipIDs: [UUID], source: MyDayPlanV1,
                                           facts: MyDaySourceSnapshotV1, target: MyDayPlanV1?) throws -> [UUID] {
        let selected = Set(membershipIDs)
        let eligible = selectableCarryoverItems(source: source, facts: facts, target: target)
        guard !selected.isEmpty, selected.count == membershipIDs.count,
              selected.isSubset(of: Set(eligible.map(\.membershipID))),
              (target?.items.count ?? 0) + selected.count <= MyDayLimitsV1.maximumItems else {
            throw MyDayWorkflowFailureV1.carryoverIneligible
        }
        return source.items.filter { selected.contains($0.membershipID) }.map(\.membershipID)
    }

    private func instant() throws -> Date {
        let value = Date(timeIntervalSince1970: (clock.now().timeIntervalSince1970 * 1_000)
            .rounded(.toNearestOrAwayFromZero) / 1_000)
        try MyDayLimitsV1.millisecondInstant(value)
        return value
    }

    private func publish(_ operation: UUID, _ body: () -> Void) throws {
        try Task.checkCancellation()
        objectWillChange.send()
        try access.withCurrentPresentation {
            try Task.checkCancellation()
            guard !invalidated, operationID == operation else {
                throw MyDayPlanningEditingSessionFailureV1.staleCompletion
            }
            body()
        }
    }

    private func perform(failure: String, _ body: (UUID) async throws -> Void) async -> Bool {
        guard !invalidated, !isBusy else { return false }
        let operation = UUID()
        do {
            objectWillChange.send()
            try access.withCurrentPresentation {
                guard !invalidated, !isBusy else { throw MyDayPlanningEditingSessionFailureV1.staleCompletion }
                operationID = operation
                isBusy = true
                errorMessage = nil
                #if DEBUG
                lastOperationFailureForTesting = nil
                #endif
            }
            try await body(operation)
            try Task.checkCancellation()
            try publish(operation) { isBusy = false }
            return true
        } catch {
            #if DEBUG
            lastOperationFailureForTesting = String(reflecting: error)
            #endif
            do {
                try publish(operation) { isBusy = false; errorMessage = failure }
            } catch {
                discardPresentation()
            }
            return false
        }
    }
}

@MainActor
struct ProductionMyDayPlanningEditorV1: View {
    @ObservedObject var state: ProductionMyDayPlanningEditorStateV1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var civilDate: String
    @State private var timeZone: String
    @State private var recorderName = ""
    @State private var sourceCivilDate = ""
    @State private var sourceTimeZone: String
    @State private var carryoverSelection: Set<UUID> = []

    init(state: ProductionMyDayPlanningEditorStateV1) {
        self.state = state
        _civilDate = State(initialValue: state.initialCivilDate)
        _timeZone = State(initialValue: state.initialTimeZone)
        _sourceTimeZone = State(initialValue: state.initialTimeZone)
    }

    var body: some View {
        NavigationStack {
            Form {
                if state.discardOutcome != nil {
                    Section {
                        Label("Saved draft discarded", systemImage: "checkmark.circle")
                        if let context = state.context {
                            Text("\(context.key.civilDate.canonicalString) · \(context.key.ianaTimeZoneIdentifier)")
                                .font(.footnote)
                        }
                    }
                    .accessibilityIdentifier("v23.my-day.planning.discard.success")
                } else if let write = state.discardWrite {
                    discardConfirmation(write)
                } else if let outcome = state.outcome {
                    Section {
                        Label("Plan saved", systemImage: "checkmark.circle")
                        Text("\(outcome.targetResult.plan.items.count) items in your manual order.")
                    }
                } else if let review = state.carryoverConflictReview {
                    carryoverConflictReview(review)
                } else if let write = state.carryoverClassificationWrite {
                    carryoverClassificationConfirmation(write)
                } else if let review = state.conflictReview {
                    conflictReview(review)
                } else if let write = state.classificationWrite {
                    classificationConfirmation(write)
                } else if let session = state.editingSession {
                    ProductionMyDayPlanningItemsV1(state: state, session: session)
                } else if let session = state.carryoverEditingSession {
                    ProductionMyDayCarryoverItemsV1(state: state, session: session)
                } else {
                    dayAndDrafts
                }
                if let error = state.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("v23.my-day.planning.error")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.Colors.canvas)
            .navigationTitle("Plan My Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Task {
                            if let write = state.discardWrite {
                                await state.cancelDiscard(write)
                            } else if await state.flush(reason: .navigation) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(state.isBusy)
                }
            }
        }
        .interactiveDismissDisabled((state.hasEditingSession || state.hasPendingPlanningOperation)
            && state.outcome == nil)
        .accessibilityIdentifier("v23.my-day.planning.editor")
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await state.flush(reason: .background) } }
        }
        .onDisappear { state.discardPresentation() }
    }

    @ViewBuilder
    private var dayAndDrafts: some View {
        Section("Choose the day") {
            TextField("Date (YYYY-MM-DD)", text: $civilDate)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("v23.my-day.planning.date")
            TextField("Time zone", text: $timeZone)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("v23.my-day.planning.time-zone")
            Button("Open day") { Task { await state.openDay(civilDate: civilDate, timeZone: timeZone) } }
                .disabled(state.isBusy)
            Text("Plans keep the day and time zone you choose.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
        }
        if let context = state.context {
            Section("\(context.key.civilDate.canonicalString) · \(context.key.ianaTimeZoneIdentifier)") {
                if state.checkpoints.isEmpty {
                    TextField("Recorded by", text: $recorderName)
                        .textContentType(.name)
                        .accessibilityIdentifier("v23.my-day.planning.recorder")
                    Button(context.currentPlan == nil ? "Begin planning" : "Edit this plan") {
                        Task { await state.beginNew(recordedByName: recorderName) }
                    }
                    .disabled(state.isBusy || recorderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Confirm the displayed day, time zone and recorder name to begin.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                } else {
                    ForEach(state.checkpoints, id: \.draftID) { checkpoint in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                            Text(checkpoint.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            if checkpoint.state == .active {
                                Button("Resume saved draft") { Task { await state.resume(draftID: checkpoint.draftID) } }
                                if state.isCarryoverConflictCandidate(checkpoint) {
                                    Button("Review carryover changes") {
                                        Task { await state.requestStaleCarryoverReview(draftID: checkpoint.draftID) }
                                    }
                                } else {
                                    Button("Review plan changes") {
                                        Task { await state.requestStalePlanReview(draftID: checkpoint.draftID) }
                                    }
                                }
                            } else if checkpoint.state == .committing {
                                Button("Continue saving") { Task { await state.finishSave(draftID: checkpoint.draftID) } }
                                if state.isCarryoverConflictCandidate(checkpoint) {
                                    Button("Review carryover changes") {
                                        Task { await state.requestStaleCarryoverReview(draftID: checkpoint.draftID) }
                                    }
                                } else {
                                    Button("Review plan changes") {
                                        Task { await state.requestStalePlanReview(draftID: checkpoint.draftID) }
                                    }
                                }
                            } else if checkpoint.state == .conflicted {
                                if state.isCarryoverConflictCandidate(checkpoint) {
                                    Button("Review carryover changes") {
                                        Task { await state.requestExistingCarryoverConflictReview(draftID: checkpoint.draftID) }
                                    }
                                } else {
                                    Button("Review plan changes") {
                                        Task { await state.requestExistingConflictReview(draftID: checkpoint.draftID) }
                                    }
                                }
                            } else {
                                Text("This draft needs recovery review before editing.")
                                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                            }
                            if state.canDiscard(checkpoint) {
                                Button("Discard saved draft", role: .destructive) {
                                    Task { await state.requestDiscard(checkpoint: checkpoint) }
                                }
                                .accessibilityIdentifier("v23.my-day.planning.discard.request.\(checkpoint.draftID.uuidString)")
                            }
                        }
                        .disabled(state.isBusy)
                    }
                }
            }

            if state.checkpoints.isEmpty {
                Section("Carry work from another plan") {
                    TextField("Source date (YYYY-MM-DD)", text: $sourceCivilDate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("v23.my-day.carryover.source-date")
                    TextField("Source time zone", text: $sourceTimeZone)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("v23.my-day.carryover.source-zone")
                    Button("Open source plan") {
                        Task {
                            if await state.openCarryoverSource(civilDate: sourceCivilDate, timeZone: sourceTimeZone) {
                                carryoverSelection = []
                            }
                        }
                    }
                    .disabled(state.isBusy)
                    if let source = state.carryoverSourcePlan {
                        Text("From \(source.key.civilDate.canonicalString) · \(source.key.ianaTimeZoneIdentifier)")
                        Text("To \(context.key.civilDate.canonicalString) · \(context.key.ianaTimeZoneIdentifier)")
                        if state.carryoverSelectableItems.isEmpty {
                            Text("No current eligible work is available to carry into this plan.")
                        }
                        ForEach(state.carryoverSelectableItems, id: \.membershipID) { item in
                            Toggle(isOn: Binding(get: { carryoverSelection.contains(item.membershipID) }, set: { selected in
                                if selected { carryoverSelection.insert(item.membershipID) }
                                else { carryoverSelection.remove(item.membershipID) }
                            })) {
                                Text("\(ProductionWorkSourceRowV1.title(for: item.reference)) · \(ProductionWorkSourceRowV1.shortIdentity(for: item.reference))")
                            }
                            .disabled(state.isBusy)
                        }
                        Text("Selected work keeps its source order and estimates. The source plan and actual work stay unchanged.")
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                        Button("Begin carryover") {
                            Task { await state.beginCarryover(selectedMembershipIDs: Array(carryoverSelection), recordedByName: recorderName) }
                        }
                        .disabled(state.isBusy || carryoverSelection.isEmpty
                            || recorderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("v23.my-day.carryover.begin")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func classificationConfirmation(_ write: MyDayPlanningConflictClassificationWriteV1) -> some View {
        Section("Review plan changes") {
            Text("Keep this draft and review the current plan before continuing.")
            Button("Keep draft and review") { Task { await state.confirmStalePlanReview() } }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
                .accessibilityIdentifier("v23.my-day.planning.conflict.classify.confirm")
            if state.canCancelPreparedConflictReview {
                Button("Back to saved drafts") { Task { await state.cancelPreparedConflictReview() } }
                    .disabled(state.isBusy)
            } else {
                Button("Retry review") { Task { await state.retryStalePlanReview() } }
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.planning.conflict.classify.retry")
            }
        }
        .accessibilityIdentifier("v23.my-day.planning.conflict.classify")
    }

    @ViewBuilder
    private func carryoverClassificationConfirmation(_ write: MyDayPlanningCarryoverConflictClassificationWriteV1) -> some View {
        Section("Review carryover changes") {
            Text("Keep this carryover draft and review the current target plan before continuing.")
            Button("Keep carryover draft and review") { Task { await state.confirmStaleCarryoverReview() } }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
                .accessibilityIdentifier("v23.my-day.carryover.conflict.classify.confirm")
            if state.canCancelPreparedConflictReview {
                Button("Back to saved drafts") { Task { await state.cancelPreparedConflictReview() } }
                    .disabled(state.isBusy)
            } else {
                Button("Retry review") { Task { await state.retryStaleCarryoverReview() } }
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.carryover.conflict.classify.retry")
            }
        }
        .accessibilityIdentifier("v23.my-day.carryover.conflict.classify")
    }

    @ViewBuilder
    private func conflictReview(_ review: MyDayPlanningConflictReviewV1) -> some View {
        Section("Review plan changes") {
            Text("\(review.originalEditingRequest.confirmedContext.key.civilDate.canonicalString) · \(review.originalEditingRequest.confirmedContext.key.ianaTimeZoneIdentifier)")
            Text("Recorded by \(review.originalEditingRequest.confirmedContext.recordedBy.displayNameAtTime)")
            Text("Your saved draft")
                .font(DesignTokens.Typography.sectionHeading)
            ForEach(Array(review.originalEditingRequest.draft.items.enumerated()), id: \.element.membershipID) { index, item in
                Text("\(index + 1). \(ProductionWorkSourceRowV1.title(for: item.reference))")
                Text("\(ProductionWorkSourceRowV1.shortIdentity(for: item.reference)) · Planned version \(item.reference.sourceRevision)")
                if let estimate = item.estimate {
                    Text("Estimate: \(estimate.wholeMinutes) minutes")
                } else {
                    Text("No estimate")
                }
            }
            Text("Current plan")
                .font(DesignTokens.Typography.sectionHeading)
            if let target = review.reviewRequest.predecessor {
                ForEach(Array(target.items.enumerated()), id: \.element.membershipID) { index, item in
                    Text("\(index + 1). \(ProductionWorkSourceRowV1.title(for: item.reference)) · \(ProductionWorkSourceRowV1.shortIdentity(for: item.reference))")
                    if let estimate = item.estimate {
                        Text("Estimate: \(estimate.wholeMinutes) minutes")
                    } else {
                        Text("No estimate")
                    }
                }
            } else {
                Text("No current plan")
            }
            if state.reviewedRebaseWrite == nil {
                Button("Review and continue editing") { Task { await state.confirmReviewedRebase() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.planning.conflict.rebase.confirm")
                Button("Back to saved drafts") { Task { await state.backToSavedDrafts() } }
                    .disabled(state.isBusy)
            } else {
                Button("Retry review") { Task { await state.retryReviewedRebase() } }
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.planning.conflict.rebase.retry")
            }
        }
        .accessibilityIdentifier("v23.my-day.planning.conflict.review")
    }

    @ViewBuilder
    private func carryoverConflictReview(_ review: MyDayPlanningCarryoverConflictReviewV1) -> some View {
        Section("Review carryover changes") {
            Text("From \(review.originalEditingRequest.sourcePlan.key.civilDate.canonicalString) · \(review.originalEditingRequest.sourcePlan.key.ianaTimeZoneIdentifier)")
            Text("To \(review.originalEditingRequest.confirmedContext.key.civilDate.canonicalString) · \(review.originalEditingRequest.confirmedContext.key.ianaTimeZoneIdentifier)")
            Text("Recorded by \(review.originalEditingRequest.confirmedContext.recordedBy.displayNameAtTime)")
            Text("Your selected source work")
                .font(DesignTokens.Typography.sectionHeading)
            ForEach(Array(review.originalEditingRequest.selectedMembershipIDs.enumerated()), id: \.element) { index, membershipID in
                Text("\(index + 1). \(membershipID.uuidString)")
            }
            Text("Current target plan")
                .font(DesignTokens.Typography.sectionHeading)
            if let target = review.capturedTarget {
                ForEach(Array(target.items.enumerated()), id: \.element.membershipID) { index, item in
                    Text("\(index + 1). \(ProductionWorkSourceRowV1.title(for: item.reference)) · \(ProductionWorkSourceRowV1.shortIdentity(for: item.reference))")
                    if let estimate = item.estimate {
                        Text("Estimate: \(estimate.wholeMinutes) minutes")
                    } else {
                        Text("No estimate")
                    }
                }
            } else {
                Text("No current plan")
            }
            if state.reviewedCarryoverRebaseWrite == nil {
                Button("Review and continue carryover") { Task { await state.confirmReviewedCarryoverRebase() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.carryover.conflict.rebase.confirm")
                Button("Back to saved drafts") { Task { await state.backToSavedDrafts() } }
                    .disabled(state.isBusy)
            } else {
                Button("Retry review") { Task { await state.retryReviewedCarryoverRebase() } }
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.carryover.conflict.rebase.retry")
            }
        }
        .accessibilityIdentifier("v23.my-day.carryover.conflict.review")
    }

    @ViewBuilder
    private func discardConfirmation(_ write: MyDayPlanningDiscardWriteV1) -> some View {
        if let context = state.context {
            Section("Discard saved draft") {
                Text("Discard the saved draft for \(context.key.civilDate.canonicalString) · \(context.key.ianaTimeZoneIdentifier)?")
                    .font(DesignTokens.Typography.sectionHeading)
                Text("Saved \(write.expectedCheckpoint.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute()). This removes the saved draft only; it does not change planned or actual work.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                Button("Discard saved draft", role: .destructive) {
                    Task { await state.confirmDiscard(write) }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.SemanticColors.error)
                .disabled(state.isBusy)
                .accessibilityIdentifier("v23.my-day.planning.discard.confirm")
                Button("Back to saved drafts") {
                    Task { await state.cancelDiscard(write) }
                }
                .disabled(state.isBusy)
                .accessibilityIdentifier("v23.my-day.planning.discard.cancel")
            }
            .accessibilityIdentifier("v23.my-day.planning.discard.confirmation")
        }
    }
}

@MainActor
private struct ProductionMyDayPlanningItemsV1: View {
    @ObservedObject var state: ProductionMyDayPlanningEditorStateV1
    @ObservedObject var session: MyDayPlanningEditingSessionV1

    var body: some View {
        Section {
            Text("\(session.request.confirmedContext.key.civilDate.canonicalString) · \(session.request.confirmedContext.key.ianaTimeZoneIdentifier)")
            Text("Recorded by \(session.request.confirmedContext.recordedBy.displayNameAtTime)")
            Text(durabilityLabel)
                .font(.footnote)
                .accessibilityIdentifier("v23.my-day.planning.durability")
        }
        Section("Manual order") {
            if session.request.draft.items.isEmpty {
                Text("Add available work below.")
            }
            ForEach(Array(session.request.draft.items.enumerated()), id: \.element.membershipID) { index, item in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                    Text("\(index + 1). \(ProductionWorkSourceRowV1.title(for: item.reference))")
                        .font(DesignTokens.Typography.sectionHeading)
                    Text("\(ProductionWorkSourceRowV1.shortIdentity(for: item.reference)) · Planned version \(item.reference.sourceRevision)")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    if let sources = state.sources,
                       let current = sources.sources.first(where: { $0.reference.stableKey == item.reference.stableKey }) {
                        ProductionWorkSourceRowV1(source: current,
                            readiness: sources.readinessAssessments.first { $0.reference == current.reference })
                    } else {
                        Text("Current work is unavailable. This item remains in your plan.")
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    }
                    Stepper(value: estimateBinding(item), in: 0...720) {
                        if let estimate = item.estimate {
                            Text("Estimate: \(estimate.wholeMinutes) minutes")
                        } else {
                            Text("No estimate")
                        }
                    }
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                        Button("Move up") { Task { await state.move(.up(membershipID: item.membershipID)) } }
                            .disabled(index == 0 || state.isBusy)
                        Button("Move down") { Task { await state.move(.down(membershipID: item.membershipID)) } }
                            .disabled(index == session.request.draft.items.count - 1 || state.isBusy)
                        Button("Remove", role: .destructive) { Task { await state.remove(membershipID: item.membershipID) } }
                    }
                    .buttonStyle(.borderless)
                }
                .disabled(state.isBusy)
                .accessibilityElement(children: .contain)
            }
            Text("Removing an item only changes this plan. Estimated time is separate from actual work time.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
        }
        Section("Available work") {
            if let sources = state.sources {
                ForEach(sources.sources.filter { source in
                    source.isSelectable && !session.request.draft.items.contains { $0.reference.stableKey == source.reference.stableKey }
                }, id: \.reference) { source in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                        ProductionWorkSourceRowV1(source: source,
                            readiness: sources.readinessAssessments.first { $0.reference == source.reference })
                        Button("Add to plan") { Task { await state.add(source.reference) } }
                            .disabled(state.isBusy || session.request.draft.items.count >= 50)
                    }
                }
            }
        }
        Section {
            Button(session.durabilityState == .saveBlocked && !session.hasDirtyChanges ? "Retry saving plan" : "Save plan") {
                Task { await state.save() }
            }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(state.isBusy || session.isCommitInFlight)
                .accessibilityIdentifier("v23.my-day.planning.save")
            if session.durabilityState == .saveBlocked && session.hasDirtyChanges {
                Button("Retry saving draft") { Task { await state.flush(reason: .navigation) } }
                    .disabled(state.isBusy)
            }
            if state.canOfferStalePlanReview {
                Button("Keep draft and review") { Task { await state.requestStalePlanReview() } }
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.planning.conflict.request")
            }
        }
    }

    private func estimateBinding(_ item: MyDayDraftItemV1) -> Binding<Int> {
        Binding(get: { item.estimate?.wholeMinutes ?? 0 }, set: { value in
            Task { await state.estimate(membershipID: item.membershipID, wholeMinutes: value == 0 ? nil : value) }
        })
    }

    private var durabilityLabel: String {
        switch session.durabilityState {
        case .unsavedChanges: return "Unsaved changes"
        case .savingOnThisIPhone: return "Saving on this iPhone"
        case .savedOnThisIPhone: return "Saved on this iPhone"
        case .saveBlocked: return session.hasDirtyChanges ? "Changes have not been saved" : "Plan has not finished saving"
        case .committing: return "Saving plan"
        case .conflicted: return "Plan changed elsewhere; review required"
        case .recoveryRequired: return "Recovery review required"
        case .committed: return "Plan saved"
        case .discarding: return "Discard pending"
        case .discarded: return "Draft discarded"
        }
    }
}


@MainActor
private struct ProductionMyDayCarryoverItemsV1: View {
    @ObservedObject var state: ProductionMyDayPlanningEditorStateV1
    @ObservedObject var session: MyDayPlanningCarryoverEditingSessionV1

    var body: some View {
        Section("Carryover") {
            Text("From \(session.request.sourcePlan.key.civilDate.canonicalString) · \(session.request.sourcePlan.key.ianaTimeZoneIdentifier)")
            Text("To \(session.request.confirmedContext.key.civilDate.canonicalString) · \(session.request.confirmedContext.key.ianaTimeZoneIdentifier)")
            Text("Recorded by \(session.request.confirmedContext.recordedBy.displayNameAtTime)")
            Text(durabilityLabel)
                .font(.footnote)
                .accessibilityIdentifier("v23.my-day.carryover.durability")
        }
        Section("Source order") {
            ForEach(state.carryoverSelectableItems, id: \.membershipID) { item in
                Toggle(isOn: Binding(get: { session.request.selectedMembershipIDs.contains(item.membershipID) }, set: { selected in
                    Task { await state.selectCarryover(membershipID: item.membershipID, selected: selected) }
                })) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                        Text(ProductionWorkSourceRowV1.title(for: item.reference))
                        Text("\(ProductionWorkSourceRowV1.shortIdentity(for: item.reference)) · Planned version \(item.reference.sourceRevision)")
                            .font(.footnote)
                        if let estimate = item.estimate { Text("Estimate: \(estimate.wholeMinutes) minutes") }
                        else { Text("No estimate") }
                    }
                }
                .disabled(state.isBusy || session.isCommitInFlight || session.durabilityState == .saveBlocked && !session.hasDirtyChanges)
            }
            Text("At least one item must remain selected. Selected work follows existing target items in source order. You can edit the target plan after saving.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
        }
        Section {
            Button(session.durabilityState == .saveBlocked && !session.hasDirtyChanges ? "Retry saving carryover" : "Save carryover") {
                Task { await state.save() }
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(state.isBusy || session.isCommitInFlight)
            .accessibilityIdentifier("v23.my-day.carryover.save")
            if session.durabilityState == .saveBlocked && session.hasDirtyChanges {
                Button("Retry saving draft") { Task { await state.flush(reason: .navigation) } }
                    .disabled(state.isBusy)
            }
            if state.canOfferStaleCarryoverReview {
                Button("Keep carryover draft and review") { Task { await state.requestStaleCarryoverReview() } }
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("v23.my-day.carryover.conflict.request")
            }
        }
    }

    private var durabilityLabel: String {
        switch session.durabilityState {
        case .unsavedChanges: return "Unsaved changes"
        case .savingOnThisIPhone: return "Saving on this iPhone"
        case .savedOnThisIPhone: return "Saved on this iPhone"
        case .saveBlocked: return session.hasDirtyChanges ? "Changes have not been saved" : "Carryover has not finished saving"
        case .committing: return "Saving carryover"
        case .conflicted: return "Plan changed elsewhere; review required"
        case .recoveryRequired: return "Recovery review required"
        case .committed: return "Carryover saved"
        case .discarding: return "Discard pending"
        case .discarded: return "Draft discarded"
        }
    }
}

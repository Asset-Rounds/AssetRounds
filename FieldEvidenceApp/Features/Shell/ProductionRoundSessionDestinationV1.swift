import Foundation
import SwiftUI

struct ProductionRoundDraftOrderingIntentV1: Equatable {
    let expectedSession: RoundSessionV1
    let itemID: UUID
    let delta: Int
}

struct ProductionRoundSessionTransitionIntentV1: Equatable {
    let expectedSession: RoundSessionV1
    let transition: RoundSessionTransitionV1
    let itemID: UUID?
    let reason: RoundItemReasonV1?
    let completion: RoundItemCompletionReferenceV1?

    init(expectedSession: RoundSessionV1, transition: RoundSessionTransitionV1,
         itemID: UUID? = nil, reason: RoundItemReasonV1? = nil,
         completion: RoundItemCompletionReferenceV1? = nil) {
        self.expectedSession = expectedSession
        self.transition = transition
        self.itemID = itemID
        self.reason = reason
        self.completion = completion
    }
}

/// Presentation of one canonical session under the original scene and content
/// publication. Explicit draft ordering uses one immutable caller-owned action;
/// merely opening or resuming a route never issues a Round command.
@MainActor
final class ProductionRoundSessionPresentationV1: ObservableObject {
    let target: NavigationTargetV1
    private let scene: AppShellSceneStateV1
    private let access: AppAccessPresentationV1.RoundAccess
    @Published private(set) var session: RoundSessionV1?
    @Published private(set) var readiness: OfflineReadinessManifestV1?
    @Published private(set) var isLoading = false
    @Published private(set) var isRebuilding = false
    @Published private(set) var couldNotLoad = false
    @Published private(set) var couldNotRebuild = false
    @Published private(set) var orderingIntent: ProductionRoundDraftOrderingIntentV1?
    @Published private(set) var pendingReorder: PreparedRoundDraftReorderV1?
    @Published private(set) var couldNotOrder = false
    @Published private(set) var isOrdering = false
    @Published private(set) var transitionIntent: ProductionRoundSessionTransitionIntentV1?
    @Published private(set) var pendingTransition: PreparedRoundSessionTransitionV1?
    @Published private(set) var couldNotTransition = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var captureIntent: UUID?
    @Published private(set) var isOpeningCapture = false
    @Published private(set) var couldNotOpenCapture = false
    @Published private(set) var captureOutOfOrder = false
    @Published private(set) var captureHost: ProductionCheckRunnerItemCapturePresentationV1?
    private var transitionSceneSnapshot: SceneNavigationSnapshotV1?
    private var operationID: UUID?
    private var orderingSceneSnapshot: SceneNavigationSnapshotV1?

    #if DEBUG
    struct ReadinessFailureObservationForTesting: Equatable {
        let stage: String
        let errorType: String
        let errorCode: Int

        var summary: String { "stage=\(stage) type=\(errorType) code=\(errorCode)" }
    }
    private(set) var lastReadinessFailureForTesting: ReadinessFailureObservationForTesting?
    var afterSessionReadForTesting: (@MainActor () throws -> Void)?
    var afterReadinessReadForTesting: (@MainActor () throws -> Void)?
    static var didCreateForTesting: (@MainActor (ProductionRoundSessionPresentationV1) -> Void)?
    #endif

    init(target: NavigationTargetV1, scene: AppShellSceneStateV1,
         access: AppAccessPresentationV1.RoundAccess) {
        self.target = target
        self.scene = scene
        self.access = access
        #if DEBUG
        Self.didCreateForTesting?(self)
        #endif
    }

    static func accepts(_ target: NavigationTargetV1) -> Bool {
        target.destination == .work && target.root == .work
            && [.read, .resume].contains(target.requestedMode)
            && target.stableSessionID != nil && target.stableEntityID == nil
            && target.stableScheduleDefinitionID == nil && target.stableScheduleReleaseID == nil
            && target.stableOccurrenceID == nil && target.stableLocationID == nil
            && target.packageSurfaceID == nil && target.draftResumeAnchor == nil
            && target.fieldPosition == nil && target.searchAnchor == nil
            && target.fallback.root == .work && target.fallback.destination == .work
    }

    var isActiveRoute: Bool {
        Self.accepts(target) && scene.snapshot?.selectedRoot == .work
            && scene.snapshot?.path(for: .work)?.targets == [target]
    }

    var hasUnacknowledgedReorder: Bool {
        pendingReorder?.attemptState == .canonicalWriteAttempted
    }

    var permitsDraftOrdering: Bool {
        access.supportsDraftOrdering && session?.state == .draft
            && !isLoading && !isRebuilding && !isOrdering && orderingIntent == nil
            && !isTransitioning && transitionIntent == nil
    }

    func requestDraftReorder(itemID: UUID, delta: Int) {
        guard permitsDraftOrdering,
              let displayed = session, displayed.state == .draft,
              delta == -1 || delta == 1,
              let index = displayed.items.firstIndex(where: { $0.itemID == itemID }),
              displayed.items.indices.contains(index + delta) else { return }
        do {
            try validateScene()
            try access.validateSessionForPublication(displayed)
            orderingIntent = .init(expectedSession: displayed, itemID: itemID, delta: delta)
            couldNotOrder = false
        } catch {
            couldNotOrder = true
        }
    }

    @discardableResult
    func cancelDraftReorder() -> Bool {
        guard !isOrdering, !hasUnacknowledgedReorder else { return false }
        orderingIntent = nil
        pendingReorder = nil
        orderingSceneSnapshot = nil
        couldNotOrder = false
        return true
    }

    @discardableResult
    func confirmDraftReorder(recordedByName: String) async -> Bool {
        guard !isOrdering, !isTransitioning, transitionIntent == nil,
              let intent = orderingIntent, isActiveRoute else { return false }
        isOrdering = true
        couldNotOrder = false
        var acknowledged = false
        defer { isOrdering = false }
        do {
            if pendingReorder == nil {
                try validateScene()
                guard session == intent.expectedSession else {
                    throw RoundSessionFailureV1.staleRevision
                }
                pendingReorder = try access.prepareDraftReorder(expected: intent.expectedSession,
                    itemID: intent.itemID, delta: intent.delta, recordedByName: recordedByName)
                orderingSceneSnapshot = scene.snapshot
            }
            guard let write = pendingReorder, let capturedScene = orderingSceneSnapshot else {
                throw RoundSessionFailureV1.authorityMismatch
            }
            let receipt = try await access.executeDraftReorder(write) {
                try Task.checkCancellation()
                guard self.pendingReorder === write, self.orderingIntent == intent,
                      self.isActiveRoute else { throw AppAccessContractFailureV1.accessDenied }
                try self.scene.validatePersistedIntent(self.target, expectedSnapshot: capturedScene)
            }
            guard pendingReorder === write,
                  receipt.sessionFrontier == (try write.proposedSession.reference) else {
                throw RoundSessionFailureV1.authorityMismatch
            }
            // The exact durable receipt acknowledges this command. A later
            // presentation failure must not turn it into a fresh delta.
            acknowledged = true
            pendingReorder = nil
            orderingIntent = nil
            orderingSceneSnapshot = nil
            readiness = nil
            guard isActiveRoute else { throw AppAccessContractFailureV1.accessDenied }
            try scene.validatePersistedIntent(target, expectedSnapshot: capturedScene)
            try access.validateSessionForPublication(write.proposedSession)
            let destination = try NavigationTargetV1(workspaceID: target.workspaceID,
                destination: .work, stableSessionID: write.proposedSession.sessionID,
                requestedMode: target.requestedMode,
                expectedRevision: target.expectedRevision == nil ? nil : write.proposedSession.revision,
                fallback: target.fallback)
            try scene.open(destination)
            if destination == target {
                try access.validateSessionForPublication(write.proposedSession)
                session = write.proposedSession
            } else {
                // The existing stack's target identity constructs the successor
                // presentation at its newly saved exact expected revision.
                session = nil
            }
            couldNotLoad = false
            return true
        } catch {
            if pendingReorder?.attemptState == .notAttempted {
                pendingReorder = nil
                orderingSceneSnapshot = nil
            }
            if Task.isCancelled && !hasUnacknowledgedReorder {
                orderingIntent = nil
                couldNotOrder = false
            } else {
                couldNotOrder = true
            }
            if acknowledged {
                session = nil
                readiness = nil
                couldNotLoad = true
            }
            return false
        }
    }

    var hasUnacknowledgedTransition: Bool {
        pendingTransition?.attemptState == .canonicalWriteAttempted
    }

    var availableSessionTransition: RoundSessionTransitionV1? {
        switch session?.state {
        case .draft: return .start
        case .active: return .pause
        case .paused: return .resume
        default: return nil
        }
    }

    var permitsSessionTransition: Bool {
        access.supportsSessionTransitions && availableSessionTransition != nil
            && !isLoading && !isRebuilding && !isOrdering && orderingIntent == nil
            && !isTransitioning && transitionIntent == nil
    }

    func requestSessionTransition(_ transition: RoundSessionTransitionV1) {
        guard permitsSessionTransition, transition == availableSessionTransition,
              let displayed = session else { return }
        do {
            try validateScene()
            try access.validateSessionForPublication(displayed)
            transitionIntent = .init(expectedSession: displayed, transition: transition)
            couldNotTransition = false
        } catch {
            couldNotTransition = true
        }
    }

    var permitsItemTransitions: Bool {
        access.supportsSessionTransitions && session?.state == .active
            && !isLoading && !isRebuilding && !isOrdering && orderingIntent == nil
            && !isTransitioning && transitionIntent == nil
    }

    func requestItemTransition(itemID: UUID, transition: RoundSessionTransitionV1,
                               reason: RoundItemReasonV1? = nil,
                               completion: RoundItemCompletionReferenceV1? = nil) {
        guard permitsItemTransitions, let displayed = session,
              let item = displayed.items.first(where: { $0.itemID == itemID }) else { return }
        switch transition {
        case .visitItem:
            guard item.disposition == .pending, reason == nil, completion == nil else { return }
        case .completeItem:
            guard item.disposition == .visited, reason == nil, completion != nil else { return }
        case .markInaccessible, .skipItem, .deferItem:
            guard [.pending, .visited].contains(item.disposition), completion == nil,
                  let reason else { return }
            let disposition: RoundItemDispositionV1
            switch transition {
            case .markInaccessible: disposition = .inaccessible
            case .skipItem: disposition = .skipped
            default: disposition = .deferred
            }
            guard reason.isAllowed(for: disposition) else { return }
        case .retryItem:
            guard [.inaccessible, .deferred].contains(item.disposition),
                  reason == nil, completion == nil else { return }
        default:
            return
        }
        do {
            try validateScene()
            try access.validateSessionForPublication(displayed)
            transitionIntent = .init(expectedSession: displayed, transition: transition,
                                     itemID: itemID, reason: reason, completion: completion)
            couldNotTransition = false
        } catch {
            couldNotTransition = true
        }
    }

    @discardableResult
    func cancelSessionTransition() -> Bool {
        guard !isTransitioning, !hasUnacknowledgedTransition else { return false }
        transitionIntent = nil
        pendingTransition = nil
        transitionSceneSnapshot = nil
        couldNotTransition = false
        return true
    }

    @discardableResult
    func confirmSessionTransition(recordedByName: String) async -> Bool {
        guard !isTransitioning, !isOrdering, orderingIntent == nil,
              let intent = transitionIntent, isActiveRoute else { return false }
        isTransitioning = true
        couldNotTransition = false
        var acknowledged = false
        defer { isTransitioning = false }
        do {
            if pendingTransition == nil {
                try validateScene()
                guard session == intent.expectedSession else {
                    throw RoundSessionFailureV1.staleRevision
                }
                if let itemID = intent.itemID {
                    pendingTransition = try access.prepareItemTransition(expected: intent.expectedSession,
                        itemID: itemID, transition: intent.transition, reason: intent.reason,
                        completion: intent.completion, recordedByName: recordedByName)
                } else {
                    pendingTransition = try access.prepareSessionTransition(expected: intent.expectedSession,
                        transition: intent.transition, recordedByName: recordedByName)
                }
                transitionSceneSnapshot = scene.snapshot
            }
            guard let write = pendingTransition, let capturedScene = transitionSceneSnapshot else {
                throw RoundSessionFailureV1.authorityMismatch
            }
            let receipt = try await access.executeSessionTransition(write) {
                try Task.checkCancellation()
                guard self.pendingTransition === write, self.transitionIntent == intent,
                      self.isActiveRoute else { throw AppAccessContractFailureV1.accessDenied }
                try self.scene.validatePersistedIntent(self.target, expectedSnapshot: capturedScene)
            }
            guard pendingTransition === write,
                  receipt.sessionFrontier == (try write.proposedSession.reference) else {
                throw RoundSessionFailureV1.authorityMismatch
            }
            // The exact durable receipt acknowledges this command. A later
            // presentation failure must not turn it into a new command.
            acknowledged = true
            pendingTransition = nil
            transitionIntent = nil
            transitionSceneSnapshot = nil
            readiness = nil
            guard isActiveRoute else { throw AppAccessContractFailureV1.accessDenied }
            try scene.validatePersistedIntent(target, expectedSnapshot: capturedScene)
            try access.validateSessionForPublication(write.proposedSession)
            let destination = try NavigationTargetV1(workspaceID: target.workspaceID,
                destination: .work, stableSessionID: write.proposedSession.sessionID,
                requestedMode: target.requestedMode,
                expectedRevision: target.expectedRevision == nil ? nil : write.proposedSession.revision,
                fallback: target.fallback)
            try scene.open(destination)
            if destination == target {
                try access.validateSessionForPublication(write.proposedSession)
                session = write.proposedSession
            } else {
                // The existing stack's target identity constructs the successor
                // presentation at its newly saved exact expected revision.
                session = nil
            }
            couldNotLoad = false
            return true
        } catch {
            if pendingTransition?.attemptState == .notAttempted {
                pendingTransition = nil
                transitionSceneSnapshot = nil
            }
            if Task.isCancelled && !hasUnacknowledgedTransition {
                transitionIntent = nil
                couldNotTransition = false
            } else {
                couldNotTransition = true
            }
            if acknowledged {
                session = nil
                readiness = nil
                couldNotLoad = true
            }
            return false
        }
    }

    // MARK: Item capture — explicit Continue only; opening or resuming never writes.

    /// Capture progress is linear, so an item opens only when it is the chain's
    /// navigation item. Every write is receipt-backed and reused on retry.
    var permitsCapture: Bool {
        access.supportsRepetitiveCaptureProgress && session?.state == .active
            && !isLoading && !isRebuilding && !isOrdering && orderingIntent == nil
            && !isTransitioning && transitionIntent == nil
            && !isOpeningCapture && captureIntent == nil && captureHost == nil
    }

    func requestCapture(itemID: UUID) {
        guard permitsCapture, let displayed = session,
              let item = displayed.items.first(where: { $0.itemID == itemID }),
              !item.disposition.isTerminal else { return }
        do {
            try validateScene()
            try access.validateSessionForPublication(displayed)
            captureIntent = itemID
            couldNotOpenCapture = false
            captureOutOfOrder = false
        } catch {
            couldNotOpenCapture = true
        }
    }

    @discardableResult
    func cancelCapture() -> Bool {
        guard !isOpeningCapture else { return false }
        captureIntent = nil
        couldNotOpenCapture = false
        captureOutOfOrder = false
        return true
    }

    /// Resume the Round's one capture source or launch it with fresh readiness,
    /// record ENTRY on the navigation item unless it is already the tip, then
    /// open the existing durable item host. No Begin, camera or finalization.
    @discardableResult
    func confirmCapture(recordedByName: String) async -> Bool {
        guard !isOpeningCapture, captureHost == nil, let itemID = captureIntent,
              let displayed = session, displayed.state == .active, isActiveRoute else { return false }
        isOpeningCapture = true
        couldNotOpenCapture = false
        captureOutOfOrder = false
        defer { isOpeningCapture = false }
        var createdHost: ProductionCheckRunnerItemCapturePresentationV1?
        do {
            try validateScene()
            try access.validateSessionForPublication(displayed)
            guard let capturedScene = scene.snapshot else { throw AppAccessContractFailureV1.accessDenied }
            let validateIntent: @MainActor () throws -> Void = {
                try Task.checkCancellation()
                guard self.captureIntent == itemID, self.isActiveRoute else {
                    throw AppAccessContractFailureV1.accessDenied
                }
                try self.scene.validatePersistedIntent(self.target, expectedSnapshot: capturedScene)
            }
            let sources = try access.readRepetitiveCaptureSources(round: displayed)
            guard sources.count <= 1 else { throw ScanToWorkFailureV1.duplicate }
            var read: ProductionRepetitiveCaptureReadV2
            if let existing = sources.first {
                read = existing
            } else {
                // A new chain starts at the first incomplete item; never launch for another tap.
                guard displayed.items.sorted(by: { $0.order < $1.order })
                        .first(where: { !$0.disposition.isTerminal })?.itemID == itemID else {
                    captureOutOfOrder = true
                    throw ScanToWorkFailureV1.authorityMismatch
                }
                try access.validateCheckRunnerItemEntry(round: displayed, itemID: itemID)
                let readiness = try await access.rebuildReadiness(for: displayed, previous: nil)
                try validateIntent()
                let launch = try access.prepareRepetitiveCaptureLaunch(round: displayed, readiness: readiness)
                read = try access.persistRepetitiveCaptureLaunch(launch, validateIntent: validateIntent)
            }
            // Settling a stored Round effect never changes its navigation item, so
            // the order check comes first and an out-of-order tap writes nothing.
            let navigationItemID = read.chain.nodes.last?.step.navigationItemID
                ?? (read.chain.nodes.isEmpty ? read.chain.launch.firstIncompleteItemID : nil)
            guard navigationItemID == itemID else {
                captureOutOfOrder = true
                throw ScanToWorkFailureV1.authorityMismatch
            }
            if let tip = read.chain.nodes.last, tip.isPendingRoundEffect {
                // Settle the one stored Round effect before any new step.
                read = try await access.resumeRepetitiveCaptureProgress(
                    sourceDraftID: read.chain.sourceCheckpoint.draftID,
                    stepDraftID: tip.checkpoint.draftID, validateIntent: validateIntent).progress
                guard read.chain.nodes.last?.step.navigationItemID == itemID else {
                    throw ScanToWorkFailureV1.authorityMismatch
                }
            }
            if let tip = read.chain.nodes.last, tip.step.action == .enter, tip.step.itemID == itemID {
                // The original ENTRY is reused; reopening performs no Round write.
            } else {
                try access.validateCheckRunnerItemEntry(round: read.chain.currentRound, itemID: itemID)
                let readiness = try await access.rebuildReadiness(for: read.chain.currentRound, previous: nil)
                try validateIntent()
                let step = try access.prepareRepetitiveCaptureStep(read: read, readiness: readiness,
                    action: .enter, focus: .facts, recordedByName: recordedByName)
                read = try await access.executeRepetitiveCaptureStep(step, validateIntent: validateIntent).progress
            }
            let round = read.chain.currentRound
            try access.validateSessionForPublication(round)
            let destination = try NavigationTargetV1(workspaceID: target.workspaceID,
                destination: .work, stableSessionID: round.sessionID,
                requestedMode: target.requestedMode,
                expectedRevision: target.expectedRevision == nil ? nil : round.revision,
                fallback: target.fallback)
            guard destination == target else {
                // A revision-pinned route re-targets first; its successor reopens
                // this same ENTRY without another write.
                try scene.open(destination)
                captureIntent = nil
                session = nil
                return false
            }
            session = round
            let source = try access.captureCheckRunnerItemSource(read: read, itemID: itemID)
            try validateIntent()
            let host = try ProductionCheckRunnerItemCapturePresentationV1(source: source,
                target: target, scene: scene, access: access)
            createdHost = host
            if host.checkpoint == nil, let snapshot = host.preflight?.snapshot {
                try host.startEditing(preflight: .init(timeZoneID: snapshot.timeZoneID ?? "",
                    isTimeZoneConfirmed: snapshot.timeZoneID != nil,
                    confirmedTimeZoneID: snapshot.timeZoneID))
            }
            // Present only an editable parent or an already begun one; anything
            // else would open a screen with no durable content.
            guard host.editor != nil || host.checkpoint != nil else {
                throw ProductionCheckRunnerItemCaptureFailureV1.missingEditor
            }
            try validateIntent()
            captureIntent = nil
            captureHost = host
            return true
        } catch {
            if let createdHost, captureHost !== createdHost {
                Task { await createdHost.retire() }
            }
            if Task.isCancelled {
                captureIntent = nil
                couldNotOpenCapture = false
            } else {
                couldNotOpenCapture = true
            }
            return false
        }
    }

    /// Called after the host's own forced flush. The durable parent stays
    /// resumable from its original ENTRY; nothing is discarded or finalized.
    func dismissCapture() {
        guard let host = captureHost else { return }
        captureHost = nil
        Task { await host.retire() }
    }

    /// After the host's receipt-backed Round step: close the host and show the
    /// Round at the result's revision; a revision-pinned route re-targets.
    func acceptCaptureProgress(_ result: AppAccessPresentationV1.RoundAccess.RepetitiveCaptureProgressResultV2) {
        guard let host = captureHost else { return }
        captureHost = nil
        Task { await host.retire() }
        readiness = nil
        do {
            guard isActiveRoute else { throw AppAccessContractFailureV1.accessDenied }
            let round = result.progress.chain.currentRound
            try access.validateRepetitiveCaptureProgressForPublication(result)
            let destination = try NavigationTargetV1(workspaceID: target.workspaceID,
                destination: .work, stableSessionID: round.sessionID,
                requestedMode: target.requestedMode,
                expectedRevision: target.expectedRevision == nil ? nil : round.revision,
                fallback: target.fallback)
            if destination == target {
                session = round
            } else {
                try scene.open(destination)
                session = nil
            }
            couldNotLoad = false
        } catch {
            session = nil
            couldNotLoad = true
        }
    }

    func refresh() async {
        if isOpeningCapture || captureHost != nil { return }
        if isOrdering || hasUnacknowledgedReorder || isTransitioning || hasUnacknowledgedTransition {
            if !isActiveRoute { session = nil; readiness = nil }
            return
        }
        guard isActiveRoute else { discardValues(); return }
        let request = UUID()
        operationID = request
        session = nil
        readiness = nil
        couldNotLoad = false
        couldNotRebuild = false
        isRebuilding = false
        isLoading = true
        defer { if operationID == request { isLoading = false } }
        do {
            try validateScene()
            guard let sessionID = target.stableSessionID else {
                throw AppAccessContractFailureV1.accessDenied
            }
            let value = try await access.readSession(sessionID: sessionID,
                expectedRevision: target.expectedRevision)
            #if DEBUG
            try afterSessionReadForTesting?()
            #endif
            guard operationID == request else { return }
            try validateScene()
            guard value.workspaceID == target.workspaceID, value.sessionID == sessionID,
                  target.expectedRevision == nil || target.expectedRevision == value.revision else {
                throw AppAccessContractFailureV1.accessDenied
            }
            try access.validateSessionForPublication(value)
            session = value
        } catch {
            guard operationID == request else { return }
            session = nil
            readiness = nil
            couldNotLoad = true
        }
    }

    func rebuildReadiness() async {
        guard !isLoading, !isRebuilding, orderingIntent == nil, transitionIntent == nil,
              let displayed = session else { return }
        let request = UUID()
        operationID = request
        let previous = readiness
        readiness = nil
        couldNotRebuild = false
        isRebuilding = true
        defer { if operationID == request { isRebuilding = false } }
        #if DEBUG
        lastReadinessFailureForTesting = nil
        var readinessStage = "scene-before-read"
        #endif
        do {
            try validateScene()
            #if DEBUG
            readinessStage = "readiness-read"
            #endif
            let read = try await access.rebuildReadiness(for: displayed, previous: previous)
            #if DEBUG
            readinessStage = "final-read-hook"
            try afterReadinessReadForTesting?()
            #endif
            guard operationID == request else { return }
            #if DEBUG
            readinessStage = "scene-before-publication"
            #endif
            try validateScene()
            #if DEBUG
            readinessStage = "session-manifest-binding"
            #endif
            guard session == displayed, read.manifest.session == (try displayed.reference) else {
                throw AppAccessContractFailureV1.accessDenied
            }
            #if DEBUG
            readinessStage = "readiness-publication-fence"
            #endif
            try access.validateReadinessForPublication(read)
            readiness = read.manifest
        } catch {
            guard operationID == request else { return }
            #if DEBUG
            let observation = ReadinessFailureObservationForTesting(stage: readinessStage,
                errorType: String(reflecting: type(of: error)), errorCode: (error as NSError).code)
            lastReadinessFailureForTesting = observation
            print("ProductionRoundSessionPresentationV1.rebuildReadiness \(observation.summary)")
            #endif
            readiness = nil
            couldNotRebuild = true
            do {
                try validateScene()
                try access.validateSessionForPublication(displayed)
            } catch {
                session = nil
                couldNotLoad = true
            }
        }
    }

    func validateForLeaving() throws {
        guard !isOrdering, !hasUnacknowledgedReorder,
              !isTransitioning, !hasUnacknowledgedTransition,
              !isOpeningCapture, captureHost == nil else {
            throw AppAccessContractFailureV1.accessDenied
        }
        try validateScene()
    }

    func leave() {
        guard isActiveRoute else { return }
        do {
            try validateForLeaving()
            try scene.setPath([], for: .work)
            discardValues()
        } catch {
            if isOrdering || hasUnacknowledgedReorder {
                couldNotOrder = true
            } else if isTransitioning || hasUnacknowledgedTransition {
                couldNotTransition = true
            } else {
                discardValues()
                couldNotLoad = true
            }
        }
    }

    private func validateScene() throws {
        guard isActiveRoute else { throw AppAccessContractFailureV1.accessDenied }
        try scene.restore()
        guard isActiveRoute, let result = scene.lastRestoration,
              result.receipt.source == .sceneSnapshot,
              result.receipt.result.disposition == .resolved,
              result.receipt.result.target == target else {
            throw AppAccessContractFailureV1.accessDenied
        }
    }

    private func discardValues() {
        operationID = nil
        session = nil
        readiness = nil
        isLoading = false
        isRebuilding = false
        captureIntent = nil
        couldNotOpenCapture = false
        captureOutOfOrder = false
        if let host = captureHost {
            captureHost = nil
            Task { await host.retire() }
        }
        if !hasUnacknowledgedReorder {
            orderingIntent = nil
            pendingReorder = nil
            orderingSceneSnapshot = nil
        }
        if !hasUnacknowledgedTransition {
            transitionIntent = nil
            pendingTransition = nil
            transitionSceneSnapshot = nil
        }
    }
}

/// The opened item. Close forces a flush first; if that save cannot complete,
/// leaving keeps the last durable checkpoint and never discards the draft.
/// Every screen is derived from the durable parent; only explicit actions write.
@MainActor
private struct ProductionRoundCaptureHostViewV1: View {
    @ObservedObject var host: ProductionCheckRunnerItemCapturePresentationV1
    let recordedByName: String
    let dismiss: @MainActor () -> Void
    let advanced: @MainActor (AppAccessPresentationV1.RoundAccess.RepetitiveCaptureProgressResultV2) -> Void
    @State private var isClosing = false
    @State private var closeFailed = false
    @State private var actionFailed = false

    var body: some View {
        NavigationStack {
            Group {
                switch host.stage {
                case .preflight:
                    ProductionCheckRunnerItemPreflightViewV1(state: host, leave: { dismiss() })
                case .interruptedBegin:
                    // An interrupted Begin has no editor; recovery never flushes fields.
                    actionScreen(title: "Finish starting this check",
                        message: "Starting this check was interrupted. Finish starting it with the details you already confirmed.",
                        action: "Finish starting", identifier: "production.round.capture.finish-begin") {
                        try host.finishPreparedBegin()
                    }
                case .capture, .pendingPhoto:
                    captureScreen
                case let .outcome(photosIncomplete):
                    outcomeScreen(photosIncomplete: photosIncomplete)
                case .preparedFinalization:
                    actionScreen(title: "Finish saving this check",
                        message: "Saving this check was interrupted. Finish saving the report you already confirmed.",
                        action: "Finish saving", identifier: "production.round.capture.finish-save") {
                        finish()
                    }
                case .completed:
                    actionScreen(title: "Check saved",
                        message: "This check is saved on this iPhone. Continue to record it in the round.",
                        action: "Continue", identifier: "production.round.capture.completed") {
                        finish()
                    }
                case .unavailable:
                    unavailable
                }
            }
            .overlay {
                if host.isPerformingAction { ProgressView("Saving check") }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    // One visible failure for every stage's explicit action.
                    failureText
                    if closeFailed {
                        VStack(spacing: 8) {
                            Text("Your latest changes could not be saved.")
                            Button("Leave anyway") { dismiss() }
                                .accessibilityIdentifier("production.round.capture.leave-anyway")
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(DesignTokens.SemanticColors.workBackground)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                        .disabled(isClosing || host.isPerformingAction)
                        .accessibilityIdentifier("production.round.capture.close")
                }
                if host.hasBoundBegin, host.editor != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Next item") {
                            Button("Defer and go to next") { advance(.defer) }
                                .accessibilityIdentifier("production.round.capture.defer")
                            Button("Keep open and go to next") { advance(.keepOpenAndNext) }
                                .accessibilityIdentifier("production.round.capture.keep-open")
                        }
                        .disabled(isClosing || host.isPerformingAction)
                        .accessibilityIdentifier("production.round.capture.next-menu")
                    }
                }
            }
        }
    }

    private var sourceApp: SourceAppSnapshotV1 {
        let info = Bundle.main.infoDictionary ?? [:]
        return SourceAppSnapshotV1(build: info["CFBundleVersion"] as? String ?? "0",
                                   version: info["CFBundleShortVersionString"] as? String ?? "0")
    }

    @ViewBuilder
    private func outcomeScreen(photosIncomplete: Bool) -> some View {
        if let actions = outcomeActions(photosIncomplete: photosIncomplete) {
            OutcomeReviewView(assetID: host.source.assetID, durable: actions)
        } else {
            unavailable
        }
    }

    /// Explicitly typed durable actions, kept out of the view builder.
    private func outcomeActions(photosIncomplete: Bool) -> CheckRunnerDurableOutcomeActionsV1? {
        guard let presentation = host.outcomePresentation, let editor = host.editor else { return nil }
        let host = self.host
        let recordedByName = self.recordedByName
        let sourceApp = self.sourceApp
        let advanced = self.advanced
        let values: @MainActor () -> CheckRunnerEditableOutcomeV1 = { editor.values.outcome }
        let update: @MainActor (CheckRunnerEditableOutcomeV1) throws -> Void = { outcome in
            guard host.editor === editor else { throw CheckRunnerItemEditingSessionFailureV1.changedCheckpoint }
            try host.replaceEditableValues(.init(preflight: editor.values.preflight,
                outcome: outcome, semanticAnchor: editor.values.semanticAnchor))
        }
        let review: @MainActor () async throws -> FinalizationReview = { try await host.readReview() }
        let thumbnail: @MainActor (ReviewEvidence) -> Data? = { evidence in host.reviewThumbnail(evidence) }
        var returnToPhotos: (@MainActor () throws -> Void)?
        if photosIncomplete {
            returnToPhotos = { try host.returnToPhotos() }
        }
        let finish: @MainActor () async throws -> Void = {
            let result = try await host.finish(recordedByName: recordedByName, sourceApp: sourceApp)
            advanced(result)
        }
        return CheckRunnerDurableOutcomeActionsV1(presentation: presentation, couldNotVerifyOnly: photosIncomplete,
            values: values, update: update, review: review, thumbnail: thumbnail,
            returnToPhotos: returnToPhotos, finish: finish)
    }

    /// The shared capture screen with its durable backend: selection stages
    /// through the C36 pipeline and Use Photo commits; neither runs implicitly.
    private var captureScreen: some View {
        CaptureStepView(assetID: host.source.assetID, durable: .init(
            preparation: host.capturePreparation, pending: host.pendingPhoto,
            preview: host.selectedPhotoPreview,
            stagePhoto: { data, origin in try await host.stagePhoto(data, origin: origin) },
            usePhoto: { try await host.usePhoto() },
            cannotComplete: { try host.openCouldNotVerify() }))
            .accessibilityIdentifier("production.round.capture.photo-step")
    }

    private func actionScreen(title: String, message: String, action: LocalizedStringKey, identifier: String,
                              perform: @escaping @MainActor () throws -> Void) -> some View {
        VStack(spacing: DesignTokens.Spacing.space16) {
            AssetRoundsEmptyState(title: Text(title), message: Text(message))
            AssetRoundsPrimaryAction(action) {
                do { try perform(); actionFailed = false } catch { actionFailed = true }
            }
            .disabled(host.isPerformingAction)
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var failureText: some View {
        if actionFailed {
            Text("This could not be saved. Try again.")
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(DesignTokens.SemanticColors.workBackground)
                .accessibilityIdentifier("production.round.capture.action-failed")
        }
    }

    /// No authenticated parent is presented; an explicit reread may recover it.
    private var unavailable: some View {
        VStack(spacing: DesignTokens.Spacing.space16) {
            AssetRoundsEmptyState(title: Text("Check unavailable"),
                message: Text("Your saved check could not be opened."))
            AssetRoundsSecondaryAction("Try again") { Task { try? await host.reload() } }
                .disabled(host.isPerformingAction)
                .accessibilityIdentifier("production.round.capture.reload")
        }
    }

    private func finish() {
        actionFailed = false
        Task {
            do { advanced(try await host.finish(recordedByName: recordedByName, sourceApp: sourceApp)) }
            catch { actionFailed = true }
        }
    }

    private func advance(_ action: RepetitiveCaptureProgressActionV2) {
        actionFailed = false
        Task {
            do { advanced(try await host.advance(action, recordedByName: recordedByName)) }
            catch { actionFailed = true }
        }
    }

    private func close() {
        guard host.editor != nil else { dismiss(); return }
        isClosing = true
        closeFailed = false
        Task {
            defer { isClosing = false }
            do { try await host.flushAndPerform(reason: .back) { dismiss() } }
            catch { closeFailed = true }
        }
    }
}

@MainActor
struct ProductionRoundSessionDestinationV1: View {
    @ObservedObject private var scene: AppShellSceneStateV1
    @StateObject private var state: ProductionRoundSessionPresentationV1
    @State private var showsReadiness = false
    @State private var recorderName = ""
    @State private var orderingTask: Task<Void, Never>?
    @State private var transitionTask: Task<Void, Never>?
    @State private var captureTask: Task<Void, Never>?

    init(target: NavigationTargetV1, scene: AppShellSceneStateV1,
         access: AppAccessPresentationV1.RoundAccess) {
        self.scene = scene
        _state = StateObject(wrappedValue: ProductionRoundSessionPresentationV1(
            target: target, scene: scene, access: access))
    }

    var body: some View {
        Group {
            if let session = state.session {
                RoundSessionView(session: session, readiness: state.readiness,
                    fieldSectionIndex: nil, fieldPositionAnchor: nil,
                    fieldPositionRequirement: .notRequired, batchHandoffStatus: .unavailable,
                    actions: .init(openItem: state.permitsCapture ? { itemID in
                            showsReadiness = false
                            recorderName = ""
                            state.requestCapture(itemID: itemID)
                        } : nil, requestReorder: state.permitsDraftOrdering ? { itemID, delta in
                            showsReadiness = false
                            recorderName = ""
                            state.requestDraftReorder(itemID: itemID, delta: delta)
                        } : nil,
                        jumpToNextIncomplete: nil, jumpToNextFlagged: nil,
                        requestBatchHandoff: nil, requestRecovery: nil,
                        preserveFieldPosition: { _ in throw AppAccessContractFailureV1.accessDenied },
                        flushBeforeLeaving: { try state.validateForLeaving() },
                        leaveAfterFlush: { state.leave() },
                        requestSessionTransition: state.permitsSessionTransition ? { transition in
                            showsReadiness = false
                            recorderName = ""
                            state.requestSessionTransition(transition)
                        } : nil,
                        requestItemTransition: state.permitsItemTransitions ? { itemID, transition, reason in
                            showsReadiness = false
                            recorderName = ""
                            state.requestItemTransition(itemID: itemID, transition: transition, reason: reason)
                        } : nil))
            } else if state.couldNotLoad {
                AssetRoundsEmptyState(title: Text("Work unavailable"),
                    message: Text("Your current work could not be opened. Try again."))
            } else {
                ProgressView("Opening work")
            }
        }
        .navigationBarBackButtonHidden(state.isOrdering || state.hasUnacknowledgedReorder
            || state.isTransitioning || state.hasUnacknowledgedTransition
            || state.isOpeningCapture || state.captureHost != nil)
        .toolbar {
            if state.session != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(BundledLocalizationCatalogV1.offlineReadinessPreflightLocalized(.heading)) {
                        showsReadiness = true
                        Task { await state.rebuildReadiness() }
                    }
                    .disabled(state.orderingIntent != nil || state.transitionIntent != nil
                        || state.captureIntent != nil)
                }
            }
        }
        .sheet(isPresented: $showsReadiness) {
            OfflineReadinessPreflightView(manifest: state.readiness,
                isLoading: state.isRebuilding,
                errorMessage: state.couldNotRebuild
                    ? BundledLocalizationCatalogV1.roundSessionLocalized(.readinessUnavailable) : nil,
                onRebuild: { Task { await state.rebuildReadiness() } },
                onCancel: { showsReadiness = false })
        }
        .sheet(isPresented: Binding(get: {
            state.orderingIntent != nil && scene.snapshot?.selectedRoot == .work
        }, set: { presented in
            if !presented { state.cancelDraftReorder() }
        })) {
            draftOrderingConfirmation
                .interactiveDismissDisabled(state.isOrdering || state.hasUnacknowledgedReorder)
        }
        .sheet(isPresented: Binding(get: {
            state.transitionIntent != nil && scene.snapshot?.selectedRoot == .work
        }, set: { presented in
            if !presented { state.cancelSessionTransition() }
        })) {
            sessionTransitionConfirmation
                .interactiveDismissDisabled(state.isTransitioning || state.hasUnacknowledgedTransition)
        }
        // One sheet swaps confirmation for the opened host, so no dismissal and
        // presentation race; the host leaves only through its own Close.
        .sheet(isPresented: Binding(get: {
            (state.captureIntent != nil || state.captureHost != nil)
                && scene.snapshot?.selectedRoot == .work
        }, set: { presented in
            guard !presented else { return }
            if state.captureHost != nil { state.dismissCapture() } else { state.cancelCapture() }
        })) {
            Group {
                if let host = state.captureHost {
                    ProductionRoundCaptureHostViewV1(host: host, recordedByName: recorderName,
                        dismiss: { state.dismissCapture() },
                        advanced: { state.acceptCaptureProgress($0) })
                } else {
                    captureConfirmation
                }
            }
            .interactiveDismissDisabled(state.isOpeningCapture || state.captureHost != nil)
        }
        .task(id: scene.snapshot?.selectedRoot == .work) {
            if scene.snapshot?.selectedRoot != .work { showsReadiness = false }
            await state.refresh()
        }
        .onDisappear {
            orderingTask?.cancel()
            transitionTask?.cancel()
            captureTask?.cancel()
        }
    }

    private var captureConfirmation: some View {
        NavigationStack {
            Form {
                Section {
                    if let itemID = state.captureIntent,
                       let item = state.session?.items.first(where: { $0.itemID == itemID }) {
                        Text("Continue: \(item.selection.labelAtSelection)")
                    }
                    TextField("Recorded by", text: $recorderName)
                        .textInputAutocapitalization(.words)
                        .disabled(state.isOpeningCapture)
                        .accessibilityIdentifier("production.round.capture.recorder")
                }
                if state.couldNotOpenCapture {
                    Section {
                        Text(state.captureOutOfOrder
                            ? "Continue with the next item in this round first."
                            : "This item could not be opened. Try again.")
                    }
                }
                if state.isOpeningCapture { ProgressView("Opening item") }
            }
            .navigationTitle("Continue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if state.isOpeningCapture { captureTask?.cancel() }
                        else { state.cancelCapture() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        captureTask = Task { _ = await state.confirmCapture(recordedByName: recorderName) }
                    }
                    .disabled(state.isOpeningCapture
                        || recorderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("production.round.capture.open")
                }
            }
            .accessibilityIdentifier("production.round.capture.confirmation")
        }
    }

    private var draftOrderingConfirmation: some View {
        NavigationStack {
            Form {
                if let intent = state.orderingIntent,
                   let item = intent.expectedSession.items.first(where: { $0.itemID == intent.itemID }) {
                    Section {
                        Text(intent.delta < 0
                            ? "Move \(item.selection.labelAtSelection) earlier"
                            : "Move \(item.selection.labelAtSelection) later")
                        TextField("Recorded by", text: $recorderName)
                            .textInputAutocapitalization(.words)
                            .disabled(state.pendingReorder != nil || state.isOrdering)
                            .accessibilityIdentifier("production.round.ordering.recorder")
                    }
                }
                if state.couldNotOrder {
                    Section {
                        Text("The order could not be confirmed. Try again.")
                        if state.hasUnacknowledgedReorder {
                            Text("Retry this save to confirm its recorded result before leaving.")
                        }
                    }
                }
                if state.isOrdering { ProgressView("Checking and saving order") }
            }
            .navigationTitle("Save order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if state.isOrdering { orderingTask?.cancel() }
                        else { state.cancelDraftReorder() }
                    }
                    .disabled(state.hasUnacknowledgedReorder)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(state.pendingReorder == nil ? "Save order" : "Retry save") {
                        orderingTask = Task { _ = await state.confirmDraftReorder(recordedByName: recorderName) }
                    }
                    .disabled(state.isOrdering || (state.pendingReorder == nil
                        && recorderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .accessibilityIdentifier("production.round.ordering.save")
                }
            }
            .accessibilityIdentifier("production.round.ordering.confirmation")
        }
    }
    private var sessionTransitionTitle: String {
        switch state.transitionIntent?.transition {
        case .start: return "Start"
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .visitItem: return "Mark visited"
        case .completeItem: return "Complete"
        case .markInaccessible: return "Mark inaccessible"
        case .skipItem: return "Skip"
        case .deferItem: return "Defer"
        case .retryItem: return "Retry item"
        default: return "Save"
        }
    }

    private var sessionTransitionConfirmation: some View {
        NavigationStack {
            Form {
                Section {
                    if let intent = state.transitionIntent, let itemID = intent.itemID,
                       let item = intent.expectedSession.items.first(where: { $0.itemID == itemID }) {
                        Text("\(sessionTransitionTitle): \(item.selection.labelAtSelection)")
                        if let reason = intent.reason {
                            Text(RoundSessionLocalizationPolicyV1.reason(reason))
                        }
                    } else {
                        Text("\(sessionTransitionTitle) this round")
                    }
                    TextField("Recorded by", text: $recorderName)
                        .textInputAutocapitalization(.words)
                        .disabled(state.pendingTransition != nil || state.isTransitioning)
                        .accessibilityIdentifier("production.round.transition.recorder")
                }
                if state.couldNotTransition {
                    Section {
                        Text("The change could not be confirmed. Try again.")
                        if state.hasUnacknowledgedTransition {
                            Text("Retry this save to confirm its recorded result before leaving.")
                        }
                    }
                }
                if state.isTransitioning { ProgressView("Checking and saving round") }
            }
            .navigationTitle(sessionTransitionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if state.isTransitioning { transitionTask?.cancel() }
                        else { state.cancelSessionTransition() }
                    }
                    .disabled(state.hasUnacknowledgedTransition)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(state.pendingTransition == nil ? sessionTransitionTitle : "Retry save") {
                        transitionTask = Task { _ = await state.confirmSessionTransition(recordedByName: recorderName) }
                    }
                    .disabled(state.isTransitioning || (state.pendingTransition == nil
                        && recorderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .accessibilityIdentifier("production.round.transition.save")
                }
            }
            .accessibilityIdentifier("production.round.transition.confirmation")
        }
    }

}

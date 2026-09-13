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
    private var transitionSceneSnapshot: SceneNavigationSnapshotV1?
    private var operationID: UUID?
    private var orderingSceneSnapshot: SceneNavigationSnapshotV1?

    #if DEBUG
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

    func refresh() async {
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
        do {
            try validateScene()
            let read = try await access.rebuildReadiness(for: displayed, previous: previous)
            #if DEBUG
            try afterReadinessReadForTesting?()
            #endif
            guard operationID == request else { return }
            try validateScene()
            guard session == displayed, read.manifest.session == (try displayed.reference) else {
                throw AppAccessContractFailureV1.accessDenied
            }
            try access.validateReadinessForPublication(read)
            readiness = read.manifest
        } catch {
            guard operationID == request else { return }
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
              !isTransitioning, !hasUnacknowledgedTransition else {
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

@MainActor
struct ProductionRoundSessionDestinationV1: View {
    @ObservedObject private var scene: AppShellSceneStateV1
    @StateObject private var state: ProductionRoundSessionPresentationV1
    @State private var showsReadiness = false
    @State private var recorderName = ""
    @State private var orderingTask: Task<Void, Never>?
    @State private var transitionTask: Task<Void, Never>?

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
                    actions: .init(openItem: nil, requestReorder: state.permitsDraftOrdering ? { itemID, delta in
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
            || state.isTransitioning || state.hasUnacknowledgedTransition)
        .toolbar {
            if state.session != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(BundledLocalizationCatalogV1.offlineReadinessPreflightLocalized(.heading)) {
                        showsReadiness = true
                        Task { await state.rebuildReadiness() }
                    }
                    .disabled(state.orderingIntent != nil || state.transitionIntent != nil)
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
        .task(id: scene.snapshot?.selectedRoot == .work) {
            if scene.snapshot?.selectedRoot != .work { showsReadiness = false }
            await state.refresh()
        }
        .onDisappear {
            orderingTask?.cancel()
            transitionTask?.cancel()
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

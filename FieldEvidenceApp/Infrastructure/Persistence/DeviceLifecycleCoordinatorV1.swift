import Foundation

enum ProtectedDataLifecycleStateV1: String, Equatable, Sendable {
    case available = "AVAILABLE"
    case unavailable = "UNAVAILABLE"
}

enum SceneLifecycleStateV1: String, Equatable, Sendable {
    case active = "ACTIVE"
    case inactive = "INACTIVE"
    case background = "BACKGROUND"
}

struct DeviceLifecycleStateV1: Equatable, Sendable {
    let protectedData: ProtectedDataLifecycleStateV1
    let scene: SceneLifecycleStateV1

    static let initiallyActive = DeviceLifecycleStateV1(
        protectedData: .available,
        scene: .active
    )

    static let initiallyConservative = DeviceLifecycleStateV1(
        protectedData: .unavailable,
        scene: .inactive
    )
}

enum DeviceLifecycleEventV1: Equatable, Sendable {
    case protectedDataBecameAvailable
    case protectedDataBecameUnavailable
    case sceneBecameActive
    case sceneBecameInactive
    case sceneEnteredBackground
}

enum DeviceLifecycleActionV1: Equatable, Hashable, Sendable {
    case none
    case suspend(LocalJobLifecycleSuspensionReasonV1)
    case resume(LocalJobLifecycleSuspensionReasonV1)
}

enum DeviceLifecycleRecoveryFailureV1: Error, Equatable, Sendable {
    case missingDeviceLocalAuthority
}

struct DeviceLifecycleTransitionV1: Equatable, Sendable {
    let previous: DeviceLifecycleStateV1
    let current: DeviceLifecycleStateV1
    let action: DeviceLifecycleActionV1

    /// Draft staging bytes are protected-data gated. Callers use this edge to
    /// refresh persisted staging protection state through the sole writer.
    var requiresFieldDraftProtectionRefresh: Bool {
        previous.protectedData != current.protectedData
    }
}

enum DeviceLifecycleReducerV1 {
    static func reduce(
        _ state: DeviceLifecycleStateV1,
        event: DeviceLifecycleEventV1
    ) -> DeviceLifecycleTransitionV1 {
        let current: DeviceLifecycleStateV1
        let action: DeviceLifecycleActionV1
        switch event {
        case .protectedDataBecameUnavailable:
            current = DeviceLifecycleStateV1(
                protectedData: .unavailable,
                scene: state.scene
            )
            action = state.protectedData == .unavailable
                ? .none
                : .suspend(.protectedDataUnavailable)
        case .protectedDataBecameAvailable:
            current = DeviceLifecycleStateV1(
                protectedData: .available,
                scene: state.scene
            )
            action = state.protectedData == .available
                ? .none
                : .resume(.protectedDataUnavailable)
        case .sceneEnteredBackground:
            current = DeviceLifecycleStateV1(
                protectedData: state.protectedData,
                scene: .background
            )
            action = state.scene == .background
                ? .none
                : .suspend(.sceneBackground)
        case .sceneBecameActive:
            current = DeviceLifecycleStateV1(
                protectedData: state.protectedData,
                scene: .active
            )
            action = state.scene == .active
                ? .none
                : .resume(.sceneBackground)
        case .sceneBecameInactive:
            current = DeviceLifecycleStateV1(
                protectedData: state.protectedData,
                scene: .inactive
            )
            action = .none
        }
        return DeviceLifecycleTransitionV1(
            previous: state,
            current: current,
            action: action
        )
    }
}

/// Provisional, injection-only lifecycle coordinator. Shipping scene and
/// protected-data notification wiring remains reserved for S10.6 adoption.
actor DeviceLifecycleCoordinatorV1 {
    private let jobs: any ResumableLocalJobLifecyclePortV1
    private let operationalSupportStore: (any DeviceOperationalSupportStoreV2)?
    private let scratchDataLeaseStore: (any ScratchDataLeasePortV1)?
    private var state: DeviceLifecycleStateV1
    private var pendingActions: Set<DeviceLifecycleActionV1> = []
    private var deviceLocalRecoveryPending: Bool

    private init(
        jobs: any ResumableLocalJobLifecyclePortV1,
        operationalSupportStore: (any DeviceOperationalSupportStoreV2)?,
        scratchDataLeaseStore: (any ScratchDataLeasePortV1)?,
        initialState: DeviceLifecycleStateV1
    ) {
        self.jobs = jobs
        self.operationalSupportStore = operationalSupportStore
        self.scratchDataLeaseStore = scratchDataLeaseStore
        state = initialState
        deviceLocalRecoveryPending = operationalSupportStore != nil
            || scratchDataLeaseStore != nil
    }

    /// Applies fail-closed initial suspension before the coordinator is
    /// returned to a caller. No active/available assumption escapes bootstrap.
    static func bootstrap(
        jobs: any ResumableLocalJobLifecyclePortV1,
        initialState: DeviceLifecycleStateV1 = .initiallyConservative
    ) async throws -> DeviceLifecycleCoordinatorV1 {
        if initialState.protectedData == .unavailable {
            try await jobs.suspendForLifecycle(.protectedDataUnavailable)
        }
        if initialState.scene == .background {
            try await jobs.suspendForLifecycle(.sceneBackground)
        }
        return DeviceLifecycleCoordinatorV1(
            jobs: jobs,
            operationalSupportStore: nil,
            scratchDataLeaseStore: nil,
            initialState: initialState
        )
    }

    /// Relaunch recovery for device-local support state. This overload does
    /// not receive or open canonical storage. When protected data is not yet
    /// available it returns suspended and defers all support-store access
    /// until the availability edge. Corrupt support bytes or scratch cleanup
    /// failures (including protected-data/storage failures) are propagated,
    /// so jobs cannot resume on an unverified bootstrap.
    static func bootstrap(
        jobs: any ResumableLocalJobLifecyclePortV1,
        operationalSupportStore: any DeviceOperationalSupportStoreV2,
        scratchDataLeaseStore: any ScratchDataLeasePortV1,
        initialState: DeviceLifecycleStateV1 = .initiallyConservative
    ) async throws -> DeviceLifecycleCoordinatorV1 {
        // Use the existing durable protected-data suspension as the bootstrap
        // gate even when availability was already observed. A failed support
        // or scratch recovery therefore leaves jobs suspended across relaunch.
        try await jobs.suspendForLifecycle(.protectedDataUnavailable)
        if initialState.scene == .background {
            try await jobs.suspendForLifecycle(.sceneBackground)
        }
        let coordinator = DeviceLifecycleCoordinatorV1(
            jobs: jobs,
            operationalSupportStore: operationalSupportStore,
            scratchDataLeaseStore: scratchDataLeaseStore,
            initialState: initialState
        )
        if initialState.protectedData == .available {
            try await coordinator.recoverDeviceLocalStateIfNeeded()
            try await jobs.resumeAfterLifecycle(.protectedDataUnavailable)
        }
        return coordinator
    }

    func currentState() -> DeviceLifecycleStateV1 {
        state
    }

    @discardableResult
    func handle(
        _ event: DeviceLifecycleEventV1
    ) async throws -> DeviceLifecycleTransitionV1 {
        let transition = DeviceLifecycleReducerV1.reduce(state, event: event)
        // Observed device state remains truthful even when durable recovery is
        // blocked. A retry of the same edge is performed by an explicit event.
        state = transition.current
        if event == .protectedDataBecameUnavailable {
            // Every lock edge invalidates the prior recovery proof. The next
            // availability edge must re-open support state and reconcile
            // scratch before protected-data jobs are allowed to resume.
            deviceLocalRecoveryPending = operationalSupportStore != nil
                || scratchDataLeaseStore != nil
        }
        enqueue(transition.action)
        try await recoverDeviceLocalStateIfNeeded()
        for action in eligiblePendingActions() {
            switch action {
            case .none:
                break
            case .suspend(let reason):
                try await jobs.suspendForLifecycle(reason)
            case .resume(let reason):
                try await jobs.resumeAfterLifecycle(reason)
            }
            pendingActions.remove(action)
        }
        return transition
    }

    /// Clears reset-scoped operational history and every scratch lease while
    /// leaving canonical workspace deletion to its existing authority.
    func resetDeviceLocalState() async throws {
        guard let operationalSupportStore, let scratchDataLeaseStore else {
            throw DeviceLifecycleRecoveryFailureV1.missingDeviceLocalAuthority
        }
        try await scratchDataLeaseStore.resetScratchData()
        try await operationalSupportStore.resetOperationalSupport()
        deviceLocalRecoveryPending = false
    }

    private func recoverDeviceLocalStateIfNeeded() async throws {
        guard deviceLocalRecoveryPending,
              state.protectedData == .available else {
            return
        }
        if let operationalSupportStore {
            _ = try await operationalSupportStore.operationalSupportSnapshot()
        }
        if let scratchDataLeaseStore {
            _ = try await scratchDataLeaseStore.recoverScratchLeases()
        }
        deviceLocalRecoveryPending = false
    }

    private func enqueue(_ action: DeviceLifecycleActionV1) {
        switch action {
        case .none:
            return
        case .suspend(let reason):
            pendingActions.remove(.resume(reason))
        case .resume(let reason):
            pendingActions.remove(.suspend(reason))
        }
        pendingActions.insert(action)
    }

    private func eligiblePendingActions() -> [DeviceLifecycleActionV1] {
        let ordered: [DeviceLifecycleActionV1] = [
            .suspend(.protectedDataUnavailable),
            .suspend(.sceneBackground),
            .resume(.protectedDataUnavailable),
            .resume(.sceneBackground),
        ]
        return ordered.filter { action in
            guard pendingActions.contains(action) else { return false }
            switch action {
            case .none:
                return false
            case .suspend(.protectedDataUnavailable):
                return state.protectedData == .unavailable
            case .resume(.protectedDataUnavailable):
                return state.protectedData == .available
            case .suspend(.sceneBackground):
                return state.scene == .background
            case .resume(.sceneBackground):
                return state.scene == .active
            }
        }
    }
}

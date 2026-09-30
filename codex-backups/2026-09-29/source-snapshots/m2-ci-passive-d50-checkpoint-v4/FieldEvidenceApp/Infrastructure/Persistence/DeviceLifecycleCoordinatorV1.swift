import Foundation

enum C34SceneNavigationDeviceLifecycleBoundaryV1 {
    static let disposition = SceneNavigationLifecycleDispositionV1()

    static func validate() -> Bool {
        C34SceneNavigationCompatibilityBoundaryV1.validate()
            && !disposition.workspaceTruth
            && !disposition.backupIncluded
            && !disposition.journalIncluded
            && !disposition.reportIncluded
            && !disposition.exportIncluded
            && !disposition.searchIncluded
            && disposition.eraseClears
            && disposition.tolerantDecode
    }
}

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
    case appLockEngaged
    case memoryPressure
}

enum EncryptedPortableEnvelopeSecretRevocationReasonV1: String, Equatable, Sendable {
    case explicitCancellation = "EXPLICIT_CANCELLATION"
    case sceneBackground = "SCENE_BACKGROUND"
    case appLock = "APP_LOCK"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case memoryPressure = "MEMORY_PRESSURE"
    case erase = "ERASE"
}

protocol EncryptedPortableEnvelopeSecretLifecycleV1: AnyObject, Sendable {
    func revokeEncryptedPortableEnvelopeSecrets(
        reason: EncryptedPortableEnvelopeSecretRevocationReasonV1
    ) async
    func resumeEncryptedPortableEnvelopeOperations(
        after reason: EncryptedPortableEnvelopeSecretRevocationReasonV1
    ) async
}

extension EncryptedPortableEnvelopeSecretLifecycleV1 {
    func resumeEncryptedPortableEnvelopeOperations(
        after reason: EncryptedPortableEnvelopeSecretRevocationReasonV1
    ) async { _ = reason }
}

struct EncryptedPortableEnvelopeLifecycleRegistrationTokenV1: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Process-local fan-out used by the production-default device coordinator.
/// Active C54 attempts register lazily before their first fallible operation;
/// weak handlers cannot prolong an operation or become persistence.
actor EncryptedPortableEnvelopeSecretLifecycleRegistryV1:
    EncryptedPortableEnvelopeSecretLifecycleV1 {
    static let shared = EncryptedPortableEnvelopeSecretLifecycleRegistryV1()

    private var handlers: [
        EncryptedPortableEnvelopeLifecycleRegistrationTokenV1:
            @Sendable (EncryptedPortableEnvelopeSecretRevocationReasonV1) async -> Void
    ] = [:]
    private var persistentBlocks: Set<EncryptedPortableEnvelopeSecretRevocationReasonV1> = []
    private var revocationDepth = 0

    func register(
        token: EncryptedPortableEnvelopeLifecycleRegistrationTokenV1,
        lifecycle: any EncryptedPortableEnvelopeSecretLifecycleV1
    ) -> Bool {
        guard revocationDepth == 0, persistentBlocks.isEmpty else { return false }
        handlers[token] = { [weak lifecycle] reason in
            await lifecycle?.revokeEncryptedPortableEnvelopeSecrets(reason: reason)
        }
        return true
    }

    func unregister(token: EncryptedPortableEnvelopeLifecycleRegistrationTokenV1) {
        handlers.removeValue(forKey: token)
    }

    func revokeEncryptedPortableEnvelopeSecrets(
        reason: EncryptedPortableEnvelopeSecretRevocationReasonV1
    ) async {
        if Self.persistsBlock(reason) { persistentBlocks.insert(reason) }
        revocationDepth += 1
        let activeHandlers = Array(handlers.values)
        for handler in activeHandlers {
            await handler(reason)
        }
        revocationDepth -= 1
    }

    func resumeEncryptedPortableEnvelopeOperations(
        after reason: EncryptedPortableEnvelopeSecretRevocationReasonV1
    ) async {
        persistentBlocks.remove(reason)
        if reason == .sceneBackground { persistentBlocks.remove(.appLock) }
    }

    func activeRegistrationCount() -> Int { handlers.count }
    func activeBlockCount() -> Int { persistentBlocks.count + (revocationDepth > 0 ? 1 : 0) }

    private static func persistsBlock(
        _ reason: EncryptedPortableEnvelopeSecretRevocationReasonV1
    ) -> Bool {
        switch reason {
        case .sceneBackground, .appLock, .protectedDataUnavailable, .erase: true
        case .explicitCancellation, .memoryPressure: false
        }
    }
}

enum DeviceLifecycleActionV1: Equatable, Hashable, Sendable {
    case none
    case suspend(LocalJobLifecycleSuspensionReasonV1)
    case resume(LocalJobLifecycleSuspensionReasonV1)
}

enum DeviceLifecycleRecoveryFailureV1: Error, Equatable, Sendable {
    case missingDeviceLocalAuthority
    case encryptedPortableEnvelopeResetAlreadyInProgress
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
        case .appLockEngaged, .memoryPressure:
            current = state
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
    private let sceneNavigationState: SceneNavigationStateAdapterV1?
    private let encryptedPortableEnvelopeSecrets:
        any EncryptedPortableEnvelopeSecretLifecycleV1
    private var state: DeviceLifecycleStateV1
    private var pendingActions: Set<DeviceLifecycleActionV1> = []
    private var deviceLocalRecoveryPending: Bool
    private var encryptedPortableEnvelopeResetInProgress = false

    private init(
        jobs: any ResumableLocalJobLifecyclePortV1,
        operationalSupportStore: (any DeviceOperationalSupportStoreV2)?,
        scratchDataLeaseStore: (any ScratchDataLeasePortV1)?,
        sceneNavigationState: SceneNavigationStateAdapterV1?,
        encryptedPortableEnvelopeSecrets:
            (any EncryptedPortableEnvelopeSecretLifecycleV1)?,
        initialState: DeviceLifecycleStateV1
    ) {
        self.jobs = jobs
        self.operationalSupportStore = operationalSupportStore
        self.scratchDataLeaseStore = scratchDataLeaseStore
        self.sceneNavigationState = sceneNavigationState
        self.encryptedPortableEnvelopeSecrets = encryptedPortableEnvelopeSecrets
            ?? EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared
        state = initialState
        deviceLocalRecoveryPending = operationalSupportStore != nil
            || scratchDataLeaseStore != nil
    }

    /// Applies fail-closed initial suspension before the coordinator is
    /// returned to a caller. No active/available assumption escapes bootstrap.
    static func bootstrap(
        jobs: any ResumableLocalJobLifecyclePortV1,
        encryptedPortableEnvelopeSecrets:
            (any EncryptedPortableEnvelopeSecretLifecycleV1)? = nil,
        initialState: DeviceLifecycleStateV1 = .initiallyConservative
    ) async throws -> DeviceLifecycleCoordinatorV1 {
        let secrets = encryptedPortableEnvelopeSecrets
            ?? EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared
        if initialState.protectedData == .unavailable {
            await secrets.revokeEncryptedPortableEnvelopeSecrets(
                reason: .protectedDataUnavailable
            )
            try await jobs.suspendForLifecycle(.protectedDataUnavailable)
        }
        if initialState.scene == .background {
            await secrets.revokeEncryptedPortableEnvelopeSecrets(
                reason: .sceneBackground
            )
            try await jobs.suspendForLifecycle(.sceneBackground)
        }
        return DeviceLifecycleCoordinatorV1(
            jobs: jobs,
            operationalSupportStore: nil,
            scratchDataLeaseStore: nil,
            sceneNavigationState: nil,
            encryptedPortableEnvelopeSecrets: secrets,
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
        encryptedPortableEnvelopeSecrets:
            (any EncryptedPortableEnvelopeSecretLifecycleV1)? = nil,
        initialState: DeviceLifecycleStateV1 = .initiallyConservative
    ) async throws -> DeviceLifecycleCoordinatorV1 {
        let secrets = encryptedPortableEnvelopeSecrets
            ?? EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared
        // Use the existing durable protected-data suspension as the bootstrap
        // gate even when availability was already observed. A failed support
        // or scratch recovery therefore leaves jobs suspended across relaunch.
        if initialState.protectedData == .unavailable {
            await secrets.revokeEncryptedPortableEnvelopeSecrets(
                reason: .protectedDataUnavailable
            )
        }
        if initialState.scene == .background {
            await secrets.revokeEncryptedPortableEnvelopeSecrets(
                reason: .sceneBackground
            )
        }
        try await jobs.suspendForLifecycle(.protectedDataUnavailable)
        if initialState.scene == .background {
            try await jobs.suspendForLifecycle(.sceneBackground)
        }
        let coordinator = DeviceLifecycleCoordinatorV1(
            jobs: jobs,
            operationalSupportStore: operationalSupportStore,
            scratchDataLeaseStore: scratchDataLeaseStore,
            sceneNavigationState: nil,
            encryptedPortableEnvelopeSecrets: secrets,
            initialState: initialState
        )
        if initialState.protectedData == .available {
            try await coordinator.recoverDeviceLocalStateIfNeeded()
            try await jobs.resumeAfterLifecycle(.protectedDataUnavailable)
        }
        return coordinator
    }

    /// The scene snapshot is device-operational state. It is accepted only
    /// through the tolerant adapter and never opens canonical storage.
    static func bootstrap(
        jobs: any ResumableLocalJobLifecyclePortV1,
        operationalSupportStore: any DeviceOperationalSupportStoreV2,
        scratchDataLeaseStore: any ScratchDataLeasePortV1,
        sceneNavigationStatePort: any SceneNavigationDeviceStatePortV1,
        encryptedPortableEnvelopeSecrets:
            (any EncryptedPortableEnvelopeSecretLifecycleV1)? = nil,
        initialState: DeviceLifecycleStateV1 = .initiallyConservative
    ) async throws -> DeviceLifecycleCoordinatorV1 {
        let coordinator = try await bootstrap(
            jobs: jobs,
            operationalSupportStore: operationalSupportStore,
            scratchDataLeaseStore: scratchDataLeaseStore,
            encryptedPortableEnvelopeSecrets: encryptedPortableEnvelopeSecrets
                ?? EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared,
            initialState: initialState
        )
        return DeviceLifecycleCoordinatorV1(
            jobs: jobs,
            operationalSupportStore: operationalSupportStore,
            scratchDataLeaseStore: scratchDataLeaseStore,
            sceneNavigationState: SceneNavigationStateAdapterV1(port: sceneNavigationStatePort),
            encryptedPortableEnvelopeSecrets: encryptedPortableEnvelopeSecrets,
            initialState: await coordinator.currentState()
        )
    }

    func currentState() -> DeviceLifecycleStateV1 {
        state
    }

    @discardableResult
    func handle(
        _ event: DeviceLifecycleEventV1
    ) async throws -> DeviceLifecycleTransitionV1 {
        let transition = DeviceLifecycleReducerV1.reduce(state, event: event)
        let encryptedPortableEnvelopeResumeReason =
            Self.encryptedPortableEnvelopeResumeReason(for: event)
        if let reason = Self.encryptedPortableEnvelopeRevocationReason(for: event) {
            await encryptedPortableEnvelopeSecrets.revokeEncryptedPortableEnvelopeSecrets(
                reason: reason
            )
        }
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
        if let reason = encryptedPortableEnvelopeResumeReason {
            await encryptedPortableEnvelopeSecrets.resumeEncryptedPortableEnvelopeOperations(
                after: reason
            )
        }
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
        guard !encryptedPortableEnvelopeResetInProgress else {
            throw DeviceLifecycleRecoveryFailureV1
                .encryptedPortableEnvelopeResetAlreadyInProgress
        }
        encryptedPortableEnvelopeResetInProgress = true
        defer { encryptedPortableEnvelopeResetInProgress = false }
        await encryptedPortableEnvelopeSecrets.revokeEncryptedPortableEnvelopeSecrets(
            reason: .erase
        )
        guard let operationalSupportStore, let scratchDataLeaseStore else {
            throw DeviceLifecycleRecoveryFailureV1.missingDeviceLocalAuthority
        }
        try await scratchDataLeaseStore.resetScratchData()
        try await operationalSupportStore.resetOperationalSupport()
        try sceneNavigationState?.erase()
        deviceLocalRecoveryPending = false
        await encryptedPortableEnvelopeSecrets.resumeEncryptedPortableEnvelopeOperations(
            after: .erase
        )
    }

    func cancelEncryptedPortableEnvelopeOperation() async {
        await encryptedPortableEnvelopeSecrets.revokeEncryptedPortableEnvelopeSecrets(
            reason: .explicitCancellation
        )
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
            if let envelopeScratch = scratchDataLeaseStore
                as? any EncryptedPortableEnvelopeScratchRecoveringV1 {
                _ = try await envelopeScratch.recoverEncryptedPortableEnvelopeScratch()
            }
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

    private static func encryptedPortableEnvelopeRevocationReason(
        for event: DeviceLifecycleEventV1
    ) -> EncryptedPortableEnvelopeSecretRevocationReasonV1? {
        switch event {
        case .protectedDataBecameUnavailable: .protectedDataUnavailable
        case .sceneEnteredBackground: .sceneBackground
        case .appLockEngaged: .appLock
        case .memoryPressure: .memoryPressure
        case .protectedDataBecameAvailable, .sceneBecameActive, .sceneBecameInactive: nil
        }
    }

    private static func encryptedPortableEnvelopeResumeReason(
        for event: DeviceLifecycleEventV1
    ) -> EncryptedPortableEnvelopeSecretRevocationReasonV1? {
        switch event {
        case .protectedDataBecameAvailable: .protectedDataUnavailable
        case .sceneBecameActive: .sceneBackground
        case .protectedDataBecameUnavailable, .sceneBecameInactive,
             .sceneEnteredBackground, .appLockEngaged, .memoryPressure: nil
        }
    }
}

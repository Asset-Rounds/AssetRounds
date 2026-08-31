import Foundation

enum PrivateSystemDiscoveryIngressBoundaryV1 {
    static let supportedKind: LockedIngressKindV1 = .appIntent
    static let stagesResolvedParametersWhileLocked = false
    static let returnsGenericUnlockRequired = true
    static let requiresFreshAuthorizedRetry = true
}

/// Production state machine over an injected descriptor-pinned durable effect.
/// It adds boundedness, exact-value adoption, and collision rejection without
/// introducing a newly adopted store or durable kind in this card.
actor InjectedProtectedIngressStoreV1: ProtectedIngressStoreV1 {
    private let effects: any ProtectedIngressDurableEffectPortV1
    private var mutationInProgress = false

    init(effects: any ProtectedIngressDurableEffectPortV1) {
        self.effects = effects
    }

    func performBlindStartupHygiene(
        now: Date,
        operationID: UUID
    ) async throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try claimMutation()
        defer { mutationInProgress = false }
        guard now.timeIntervalSinceReferenceDate.isFinite,
              operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let receipt = try await effects.performBlindStartupHygieneEffect(
            now: now,
            operationID: operationID
        )
        guard receipt.operationID == operationID, !receipt.contentRead else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let receiptReadback = try await effects.readBlindStartupHygieneReceiptEffect(
            operationID: operationID
        )
        guard receiptReadback == receipt else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let pendingReadback = try await validatedSnapshot()
        guard pendingReadback.count == receipt.retainedValidCount
                + receipt.deferredAmbiguousCount else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return receipt
    }

    func stageContentBlind(
        _ request: ProtectedIngressStageRequestV1,
        source: URL
    ) async throws -> ProtectedIngressStageReceiptV1 {
        try claimMutation()
        defer { mutationInProgress = false }
        let before = try await validatedSnapshot()
        if let existing = before.first(where: { $0.intentID == request.intentID }) {
            guard Self.matches(existing, request) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            return ProtectedIngressStageReceiptV1(
                intent: existing,
                disposition: .duplicateAdopted,
                adoptedExistingEffect: true
            )
        }
        guard before.count < ProtectedIngressCoordinatorV1.maximumPendingIntentCount else {
            throw AppAccessContractFailureV1.ingressLimitExceeded
        }
        let staged = try await effects.stageContentBlindEffect(request, source: source)
        try staged.validate()
        guard Self.matches(staged, request),
              staged.disposition == .stagedProtectedPendingAuthentication else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let after = try await validatedSnapshot()
        guard after.first(where: { $0.intentID == request.intentID }) == staged else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return ProtectedIngressStageReceiptV1(
            intent: staged,
            disposition: .stagedProtectedPendingAuthentication,
            adoptedExistingEffect: false
        )
    }

    func pendingIntents() async throws -> [PendingLockedExternalIntentV1] {
        try await validatedSnapshot()
    }

    func markReadyForAuthenticatedValidation(intentID: UUID) async throws
        -> PendingLockedExternalIntentV1 {
        try claimMutation()
        defer { mutationInProgress = false }
        guard intentID != SettingsValidationV1.zeroUUID,
              let existing = try await validatedSnapshot().first(where: {
                  $0.intentID == intentID
              }) else {
            throw AppAccessContractFailureV1.invalidValue
        }
        if existing.disposition == .readyForAuthenticatedValidation { return existing }
        guard existing.disposition == .stagedProtectedPendingAuthentication
                || existing.disposition == .deferredAmbiguousOwnership else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        // A deferred row advances only after authenticated metadata/ownership
        // reconciliation through the injected compare-and-swap effect.
        // Payload parsing remains forbidden until this ready receipt returns.
        let replacement = try existing.advancing(to: .readyForAuthenticatedValidation)
        try await effects.replacePendingIntentEffect(
            expected: existing,
            replacement: replacement
        )
        guard try await validatedSnapshot().first(where: {
            $0.intentID == intentID
        }) == replacement else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return replacement
    }

    func remove(
        intentID: UUID,
        disposition: LockedIngressDispositionV1
    ) async throws {
        try claimMutation()
        defer { mutationInProgress = false }
        let before = try await validatedSnapshot()
        guard let existing = before.first(where: { $0.intentID == intentID }) else { return }
        guard disposition == .expiredDeleted || disposition == .consumed
                || disposition == .erased else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        try await effects.removePendingIntentEffect(
            expected: existing,
            disposition: disposition
        )
        guard try await validatedSnapshot().allSatisfy({ $0.intentID != intentID }) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    func eraseAllProtectedIngress(operationID: UUID) async throws {
        try claimMutation()
        defer { mutationInProgress = false }
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        try await effects.erasePendingIntentsEffect(operationID: operationID)
        guard try await validatedSnapshot().isEmpty else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    private func claimMutation() throws {
        guard !mutationInProgress else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        mutationInProgress = true
    }

    private func validatedSnapshot() async throws -> [PendingLockedExternalIntentV1] {
        let values = try await effects.loadPendingIntentsEffect()
        guard values.count <= ProtectedIngressCoordinatorV1.maximumPendingIntentCount,
              Set(values.map(\.intentID)).count == values.count,
              values.allSatisfy({ Self.isActivePersistedDisposition($0.disposition) }) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try values.forEach { try $0.validate() }
        return values.sorted { $0.intentID.uuidString < $1.intentID.uuidString }
    }

    private static func matches(
        _ value: PendingLockedExternalIntentV1,
        _ request: ProtectedIngressStageRequestV1
    ) -> Bool {
        value.intentID == request.intentID
            && value.operationID == request.operationID
            && value.kind == request.kind
            && value.byteCount == request.byteCount
            && value.receivedAt == request.receivedAt
            && value.expiresAt == request.expiresAt
    }

    private static func isActivePersistedDisposition(
        _ value: LockedIngressDispositionV1
    ) -> Bool {
        switch value {
        case .stagedProtectedPendingAuthentication,
             .readyForAuthenticatedValidation,
             .deferredAmbiguousOwnership:
            return true
        case .duplicateAdopted, .rejectedUnsupportedKind, .rejectedSize,
             .rejectedStorage, .rejectedProtectedData, .expiredDeleted,
             .consumed, .erased:
            return false
        }
    }
}

actor ProtectedIngressCoordinatorV1 {
    static let maximumPendingIntentCount = 128

    private let gate: any AppAccessGatePortV1
    private let store: any ProtectedIngressStoreV1
    private let clock: any ApplicationClock

    init(
        gate: any AppAccessGatePortV1,
        store: any ProtectedIngressStoreV1,
        clock: any ApplicationClock
    ) {
        self.gate = gate
        self.store = store
        self.clock = clock
    }

    func stageWhileLocked(
        _ request: ProtectedIngressStageRequestV1,
        source: URL
    ) async throws -> ProtectedIngressStageReceiptV1 {
        try validate(request)
        guard source.isFileURL else {
            throw AppAccessContractFailureV1.invalidValue
        }
        let state = await gate.currentState()
        guard !state.permitsContentAccess else {
            throw AppAccessContractFailureV1.invalidTransition
        }
        let pending = try await store.pendingIntents()
        guard pending.count < Self.maximumPendingIntentCount
                || pending.contains(where: { $0.intentID == request.intentID }) else {
            throw AppAccessContractFailureV1.ingressLimitExceeded
        }
        // The injected store owns descriptor-pinned copy and digest authority.
        // This coordinator deliberately never opens or interprets source bytes.
        let receipt = try await store.stageContentBlind(request, source: source)
        try receipt.intent.validate()
        guard receipt.intent.intentID == request.intentID,
              receipt.intent.operationID == request.operationID,
              receipt.intent.kind == request.kind,
              receipt.intent.byteCount == request.byteCount,
              receipt.intent.receivedAt == request.receivedAt,
              receipt.intent.expiresAt == request.expiresAt,
              receipt.disposition == .stagedProtectedPendingAuthentication
                || receipt.disposition == .duplicateAdopted else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return receipt
    }

    /// Returns metadata only after access is authorized. Payload parsing and
    /// canonical application remain responsibilities of the downstream owner.
    func resumeAfterAuthentication() async throws -> [PendingLockedExternalIntentV1] {
        let sessionID = try await unlockedSessionID()
        let now = clock.now()
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw AppAccessContractFailureV1.invalidValue
        }
        var ready: [PendingLockedExternalIntentV1] = []
        let pending = try await store.pendingIntents()
        try await requireSameUnlockedSession(sessionID)
        guard pending.count <= Self.maximumPendingIntentCount,
              Set(pending.map(\.intentID)).count == pending.count else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        for value in pending.sorted(by: { $0.intentID.uuidString < $1.intentID.uuidString }) {
            try value.validate()
            if now >= value.expiresAt {
                try await store.remove(intentID: value.intentID, disposition: .expiredDeleted)
                try await requireSameUnlockedSession(sessionID)
            } else {
                let adopted = try await store.markReadyForAuthenticatedValidation(
                    intentID: value.intentID
                )
                try await requireSameUnlockedSession(sessionID)
                try adopted.validate()
                guard adopted.disposition == .readyForAuthenticatedValidation,
                      adopted.intentID == value.intentID,
                      adopted.sha256 == value.sha256,
                      adopted.byteCount == value.byteCount else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                ready.append(adopted)
            }
        }
        return ready
    }

    func erase(operationID: UUID) async throws {
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        try await store.eraseAllProtectedIngress(operationID: operationID)
        guard try await store.pendingIntents().isEmpty else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    private func validate(_ request: ProtectedIngressStageRequestV1) throws {
        guard request.intentID != SettingsValidationV1.zeroUUID,
              request.operationID != SettingsValidationV1.zeroUUID,
              request.byteCount > 0,
              request.byteCount <= PendingLockedExternalIntentV1.maximumByteCount,
              request.receivedAt.timeIntervalSinceReferenceDate.isFinite,
              request.expiresAt.timeIntervalSinceReferenceDate.isFinite,
              request.expiresAt > request.receivedAt,
              request.expiresAt.timeIntervalSince(request.receivedAt)
                <= PendingLockedExternalIntentV1.maximumLifetimeSeconds else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    private func unlockedSessionID() async throws -> UUID {
        guard case .unlockedForeground(let sessionID) = await gate.currentState() else {
            throw AppAccessContractFailureV1.accessDenied
        }
        return sessionID
    }

    private func requireSameUnlockedSession(_ expected: UUID) async throws {
        guard case .unlockedForeground(let observed) = await gate.currentState(),
              observed == expected else {
            throw AppAccessContractFailureV1.staleAttempt
        }
    }
}

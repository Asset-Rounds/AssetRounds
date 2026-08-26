import Foundation
import LocalAuthentication

actor SystemLocalAuthenticationClient: LocalAuthenticationClient {
    private var contexts: [UUID: LAContext] = [:]
    private var acceptedPolicyDomainState: Data?

    /// The accepted domain state is device-local authentication metadata, not
    /// an unlocked session. Composition may restore the last accepted bytes so
    /// a biometric-set change is detected across process launches.
    init(acceptedPolicyDomainState: Data? = nil) {
        self.acceptedPolicyDomainState = acceptedPolicyDomainState
    }

    func acceptedPolicyDomainStateSnapshot() -> Data? {
        acceptedPolicyDomainState
    }

    func availability() async -> LocalAuthenticationAvailabilityV1 {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        )
        let biometry = Self.biometry(context.biometryType)
        if available {
            return LocalAuthenticationAvailabilityV1.systemValue(
                status: .available,
                biometry: biometry
            )
        }
        return LocalAuthenticationAvailabilityV1.systemValue(
            status: Self.availabilityStatus(error),
            biometry: biometry
        )
    }

    func authenticate(
        _ attempt: LocalAuthenticationAttemptV1
    ) async -> LocalAuthenticationOutcomeV1 {
        do {
            try attempt.validate()
        } catch {
            return .unavailable
        }
        guard contexts[attempt.attemptID] == nil else { return .interrupted }
        // A fresh context is created here, never cached or reused across attempts.
        let context = LAContext()
        contexts[attempt.attemptID] = context
        var outcome = await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: attempt.localizedReason
            ) { success, error in
                continuation.resume(returning: Self.outcome(success: success, error: error))
            }
        }
        // Cancellation removes the attempt-owned context. A late callback may
        // not update accepted domain metadata or become an authentication.
        guard contexts[attempt.attemptID] === context else {
            context.invalidate()
            return .interrupted
        }
        contexts.removeValue(forKey: attempt.attemptID)
        if outcome == .authenticated,
           let observed = context.evaluatedPolicyDomainState {
            if let acceptedPolicyDomainState {
                if acceptedPolicyDomainState != observed {
                    outcome = .biometryChanged
                    // The attempt itself completed device-owner authentication.
                    // Keep this attempt locked and observable, but accept the
                    // new domain bytes so a fresh retry can recover instead of
                    // entering a permanent biometric-change loop.
                    self.acceptedPolicyDomainState = observed
                }
            } else {
                acceptedPolicyDomainState = observed
            }
        }
        context.invalidate()
        return outcome
    }

    func cancel(attemptID: UUID) async {
        guard let context = contexts.removeValue(forKey: attemptID) else { return }
        context.invalidate()
    }

    private nonisolated static func biometry(
        _ value: LABiometryType
    ) -> LocalAuthenticationBiometryV1 {
        switch value {
        case .none: return .none
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .unavailableUnknown
        @unknown default: return .unavailableUnknown
        }
    }

    private nonisolated static func availabilityStatus(
        _ error: NSError?
    ) -> LocalAuthenticationAvailabilityStatusV1 {
        guard let code = error.flatMap({ LAError.Code(rawValue: $0.code) }) else {
            return .temporarilyUnavailable
        }
        switch code {
        case .passcodeNotSet: return .devicePasscodeNotSet
        case .biometryNotEnrolled: return .biometryNotEnrolled
        case .biometryLockout: return .biometryLockedOut
        case .biometryNotAvailable: return .unsupported
        default: return .temporarilyUnavailable
        }
    }

    private nonisolated static func outcome(
        success: Bool,
        error: Error?
    ) -> LocalAuthenticationOutcomeV1 {
        if success { return .authenticated }
        guard let error = error as NSError?,
              let code = LAError.Code(rawValue: error.code) else {
            return .unavailable
        }
        switch code {
        case .userCancel, .userFallback: return .userCancelled
        case .appCancel, .invalidContext: return .appCancelled
        case .systemCancel: return .systemCancelled
        case .authenticationFailed: return .authenticationFailed
        case .biometryLockout: return .biometryLockedOut
        case .biometryNotEnrolled: return .biometryNotEnrolled
        case .passcodeNotSet: return .devicePasscodeNotSet
        case .biometryNotAvailable, .notInteractive: return .unavailable
        default: return .interrupted
        }
    }
}

import Foundation
@testable import FieldEvidenceApp

/// Test-only orchestration of genuine production Erase capabilities. Callers
/// keep their service configuration and choose assertion boundaries explicitly.
@MainActor
final class V23EraseOperationHarnessV1 {
    let router: StartupRouter
    let accessGate: AppAccessGateV1
    private var ticket: StartupRouter.OriginalOperationTicket?
    private var operation: EraseRouterOperationV1?
    private var reservation: AppAccessGateV1.EraseAdoptionToken?
    private var receipt: CompletedEraseReceiptV1?
    private var activationFailure: Error?
    private(set) var activationCallbackEntryCount = 0
    private var failedCoordinator: StoreSessionCoordinator?
    private var adopted = false
    private static var retainedRoots: [(URL, V23EraseOperationHarnessV1)] = []

    init(retainingRoot root: URL, applicationSupportURL: URL,
        runtime: StoreKitEntitlementRuntimeV1,
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1) {
        accessGate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23EraseHarnessAuthenticationV1(),
            clock: SystemApplicationClock(), identifiers: SystemApplicationIDSource())
        router = StartupRouter(applicationSupportURL: applicationSupportURL,
            entitlementRuntime: runtime, lifecycleProfileRegistry: profileRegistry)
        // Before any admission/acquisition, retain the real owner and root for
        // host lifetime. This is storage retention, never cleanup permission.
        Self.retainedRoots.append((root, self))
        FileHandle.standardError.write(Data((
            "V23_ERASE_FIXTURE_RETAINED_V1 root=\(root.path) " +
            "retention=until-host-termination reason=checked-root-close-unavailable\n").utf8))
    }

    /// Start the genuine Router under its authenticated gate and return only
    /// the writer that Router itself published for the original generation.
    /// Seed fixtures must release all of their own store aliases before this.
    func startOriginalOwner() async throws -> (StoreSessionCoordinator, DiagnosticsStore) {
#if DEBUG
        let previousStartupDiagnostic = router.startupFailureDiagnosticForTesting
        var startupFailure = "none"
        router.startupFailureDiagnosticForTesting = { message in
            previousStartupDiagnostic?(message)
            startupFailure = message
        }
        defer { router.startupFailureDiagnosticForTesting = previousStartupDiagnostic }
#endif
        var stage = "authenticate"
        do {
            guard ticket == nil,
                  await accessGate.authenticate(trigger: .unlock) == .authenticated else {
                throw Failure.admission
            }
            stage = "bind-startup-gate"
            try router.bindStartupAccessGate(accessGate)
            stage = "router-start"
            try await router.startIfNeeded(accessGate: accessGate)
            stage = "router-ready"
            guard case let .ready(coordinator, diagnostics, _) = router.route else {
                throw Failure.admission
            }
            return (coordinator, diagnostics)
        } catch {
#if DEBUG
            Self.reportFailure("startOriginalOwner stage=\(stage) "
                + "type=\(String(reflecting: type(of: error))) "
                + "route=\(Self.routeDescription(router.route)) "
                + "startup=\(startupFailure)")
#endif
            throw error
        }
    }

    func admit(coordinator: StoreSessionCoordinator) async throws {
        do {
            guard ticket == nil,
                  case let .ready(published, _, _) = router.route,
                  published === coordinator else { throw Failure.admission }
            // startOriginalOwner authenticated this gate. Router independently
            // validates its current content-read epoch before admitting Erase.
            try router.bindStartupAccessGate(accessGate)
            let actual = try await router.beginEraseOperation(coordinator: coordinator, accessGate: accessGate)
            ticket = actual
            operation = try router.eraseRetirementOperation(for: actual)
        } catch { failedCoordinator = coordinator; throw error }
    }

    func admitSubject(_ subject: EraseAllOperationSubjectV1) async throws
        -> AppAccessGateV1.EraseAdoptionToken {
        guard let ticket else { throw Failure.admission }
        if let authorization = try await router.eraseAdmissionAuthorization(ticket, subject: subject) {
            let token = try await accessGate.reserveEraseAdoption(subject: subject, authorization: authorization)
            try router.recordEraseReservation(ticket, reservation: token)
            reservation = token
            return token
        }
        guard let reservation else { throw Failure.admission }
        return reservation
    }

    func configure(_ service: EraseAllService) throws -> EraseAllService {
        guard let operation else { throw Failure.admission }
        return try router.configureEraseService(service, operation: operation)
    }

    /// Exposes only the operation actually minted by this authenticated
    /// Router admission. Interruption tests still have to satisfy the
    /// production handoff witness before a new owner may start.
    func originalOperationForInterruption() throws -> EraseRouterOperationV1 {
        guard let operation else { throw Failure.admission }
        return operation
    }

    func originalTicketForInterruption() throws -> StartupRouter.OriginalOperationTicket {
        guard let ticket else { throw Failure.admission }
        return ticket
    }

    func originalReservationForInterruption() throws
        -> AppAccessGateV1.EraseAdoptionToken {
        guard let reservation, operation != nil else {
            throw Failure.admission
        }
        return reservation
    }

    /// Retains the existing compatibility route; no implicit live profile or
    /// weaker operation is substituted. Service callbacks stay caller-owned.
    func prepareCompatibility(service: EraseAllService, confirmation: String,
        coordinator: StoreSessionCoordinator, diagnostics: DiagnosticsStore) async throws {
        guard let operation else { throw Failure.admission }
#if DEBUG
        let previousEraseDiagnostic = service.erasePhaseDiagnosticForTesting
        var eraseStage = "not-entered"
        var originalFailure = "none"
        service.erasePhaseDiagnosticForTesting = { message in
            previousEraseDiagnostic?(message)
            if message.hasPrefix("original-failure.") {
                originalFailure = message
            } else if !message.hasPrefix("ERASE_FILE_SNAPSHOT_V1 ") {
                eraseStage = message
            }
        }
        defer { service.erasePhaseDiagnosticForTesting = previousEraseDiagnostic }
#endif
        var serviceReturned = false
        do {
            _ = try await service.erase(confirmation: confirmation, coordinator: coordinator,
                diagnosticsStore: diagnostics, operation: operation,
                activate: { [self, weak coordinator] replacement in
                    activationCallbackEntryCount += 1
                    do {
                        guard let coordinator else { throw Failure.activation }
                        try router.activateErasePreparationSession(replacement,
                            coordinator: coordinator, operation: operation)
                    } catch { activationFailure = error }
                })
            serviceReturned = true
            if let activationFailure { throw activationFailure }
        } catch {
            failedCoordinator = coordinator
#if DEBUG
            Self.reportFailure("prepareCompatibility stage=\(serviceReturned ? "post-service-activation" : "service-erase") "
                + "type=\(String(reflecting: type(of: error))) "
                + "eraseStage=\(eraseStage) originalFailure=\(originalFailure) "
                + "callbackEntries=\(activationCallbackEntryCount) "
                + "activationErrorType=\(activationFailure.map { String(reflecting: type(of: $0)) } ?? "none")")
#endif
            throw error
        }
    }

    /// Caller scopes must release all source readers first. Only the actual
    /// production witness decides whether the operation is ready to advance.
    func completeCleanup() async throws {
        guard failedCoordinator == nil, let operation,
              try await operation.advanceCleanup() else { throw Failure.drainPending }
        let (_, _, actualReceipt) = try operation.completedRetirement()
        guard let actualReceipt, let reservation,
              actualReceipt.reservation == reservation else { throw Failure.receipt }
        receipt = actualReceipt
    }

    func adoptCompletedReceipt() async throws {
        guard !adopted, let receipt, let reservation else { throw Failure.receipt }
        try await accessGate.adoptCompletedErase(receipt, token: reservation)
        adopted = true
    }

    func activateFreshOrdinarySession() async throws {
        guard adopted, let operation else { throw Failure.receipt }
        try await router.finishRetiredEraseActivation(operation, accessGate: accessGate)
    }

    enum Failure: Error { case admission, activation, drainPending, receipt }

#if DEBUG
    private static func routeDescription(_ route: StartupRouter.Route) -> String {
        switch route {
        case .checking:
            return "checking"
        case .awaitingIndependentValidation:
            return "awaiting-independent-validation"
        case .ready:
            return "ready"
        case .eraseCleanupPending(.preparing):
            return "erase-cleanup-pending.preparing"
        case .eraseCleanupPending(.retiring):
            return "erase-cleanup-pending.retiring"
        case .maintenance(let reason):
            return "maintenance.\(reason.rawValue)"
        }
    }

    private static func reportFailure(_ message: String) {
        FileHandle.standardError.write(Data(("V23_ERASE_HARNESS_FAILURE_V1 " + message + "\n").utf8))
    }
#endif
}

private actor V23EraseHarnessAuthenticationV1: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}

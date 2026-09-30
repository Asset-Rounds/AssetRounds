import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23AppAccessPresentationTests: XCTestCase {
    @MainActor
    func testSuspendedBootstrapQueuesInactiveAndActiveWithoutPreauthenticationStart() async throws {
        let fixture = try PresentationFixture()
        defer { fixture.remove() }
        let presentation = fixture.presentation()
        let bootstrap = Task { await presentation.bootstrapIfNeeded() }
        await fixture.factory.waitUntilEntered()

        presentation.receive(.sceneInactive)
        presentation.receive(.sceneActive)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertEqual(fixture.begunSteps.count, 0)

        await fixture.factory.release()
        await bootstrap.value
        XCTAssertNotNil(presentation.accessState)
    }

    @MainActor
    func testHardRevocationDuringSuspendedBootstrapPreventsLateStartupPublication() async throws {
        let fixture = try PresentationFixture()
        defer { fixture.remove() }
        let presentation = fixture.presentation()
        let bootstrap = Task { await presentation.bootstrapIfNeeded() }
        await fixture.factory.waitUntilEntered()

        presentation.receive(.protectedDataUnavailable)
        await fixture.factory.release()
        await bootstrap.value
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertEqual(fixture.router.recoveryBootstrapState, .checking)
    }

    @MainActor
    func testRepeatedActiveEdgesRemainCoveredUntilTheSingleLifecycleDrainSettles() async throws {
        let fixture = try PresentationFixture()
        defer { fixture.remove() }
        let presentation = fixture.presentation()
        let bootstrap = Task { await presentation.bootstrapIfNeeded() }
        await fixture.factory.waitUntilEntered()

        presentation.receive(.sceneInactive)
        presentation.receive(.sceneActive)
        presentation.receive(.sceneActive)
        await fixture.factory.release()
        await bootstrap.value
        // A repeated scene-active notification is a lifecycle observation,
        // never a second authentication or independent startup owner.
        XCTAssertNotNil(presentation.accessState)
    }

    @MainActor
    func testInactivePreservesAuthenticationButNeverPublishesContent() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-AppAccessPresentation-Auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        let authentication = PresentationGatedAuthentication()
        let setting = PresentationSetting(enabled: true)
        let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: setting,
            authentication: authentication,
            ingressStore: PresentationIngress(),
            notifications: PresentationNotifications(),
            clock: PresentationClock(),
            identifiers: PresentationIDs()
        )
        let gate = await lifecycle.accessGate()
        let router = StartupRouter(applicationSupportURL: support)
        let sceneState = InMemorySceneNavigationDeviceStatePortV1()
        let presentation = AppAccessPresentationV1(startupRouter: router) {
            .init(lifecycle: lifecycle, gate: gate, setting: setting,
                  authentication: authentication, sceneNavigationStatePort: { sceneState })
        }
        await presentation.bootstrapIfNeeded()

        let unlock = Task { await presentation.unlock() }
        await authentication.waitUntilAuthenticationBegins()
        presentation.receive(.sceneInactive)
        await authentication.finish(.authenticated)
        await unlock.value

        guard case .unlockedForeground = await gate.currentState() else {
            return XCTFail("inactive system authentication was unexpectedly revoked")
        }
        XCTAssertFalse(presentation.permitsContentPresentation)

        presentation.receive(.sceneActive)
        await Task.yield()
        let inactiveThenActiveEvaluationCount = await authentication.evaluationCount
        XCTAssertEqual(inactiveThenActiveEvaluationCount, 1)
    }

    @MainActor
    func testRepeatedUserActionAndHardRevocationCannotReviveLateAuthentication() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-AppAccessPresentation-Revoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        let authentication = PresentationGatedAuthentication()
        let setting = PresentationSetting(enabled: true)
        let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: setting,
            authentication: authentication,
            ingressStore: PresentationIngress(),
            notifications: PresentationNotifications(),
            clock: PresentationClock(),
            identifiers: PresentationIDs()
        )
        let gate = await lifecycle.accessGate()
        let router = StartupRouter(applicationSupportURL: support)
        let sceneState = InMemorySceneNavigationDeviceStatePortV1()
        let presentation = AppAccessPresentationV1(startupRouter: router) {
            .init(lifecycle: lifecycle, gate: gate, setting: setting,
                  authentication: authentication, sceneNavigationStatePort: { sceneState })
        }
        await presentation.bootstrapIfNeeded()

        let first = Task { await presentation.unlock() }
        await authentication.waitUntilAuthenticationBegins()
        await presentation.unlock()
        let repeatedActionEvaluationCount = await authentication.evaluationCount
        XCTAssertEqual(repeatedActionEvaluationCount, 1)

        presentation.receive(.protectedDataUnavailable)
        await authentication.finish(.authenticated)
        await first.value
        presentation.receive(.sceneActive)
        await Task.yield()

        XCTAssertFalse(presentation.permitsContentPresentation)
        let hardRevocationEvaluationCount = await authentication.evaluationCount
        XCTAssertEqual(hardRevocationEvaluationCount, 1)
    }

    @MainActor
    func testRealRouterExplicitRetryRunsChecksAgainWithTheSameConcreteGate() async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-AppAccessPresentation-Retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        let recorder = PresentationStepRecorder()
        let authentication = PresentationImmediateAuthentication()
        let setting = PresentationSetting(enabled: true)
        let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: setting,
            authentication: authentication,
            ingressStore: PresentationIngress(),
            notifications: PresentationNotifications(),
            clock: PresentationClock(),
            identifiers: PresentationIDs()
        )
        let gate = await lifecycle.accessGate()
        var revokesFirstStartup = true
        let router = StartupRouter(
            applicationSupportURL: support,
            didBeginStep: { step in recorder.steps.append(step) },
            beforeCommerceActivation: { _ in
                guard revokesFirstStartup else { return }
                revokesFirstStartup = false
                // Return to an authorized state while invalidating the first
                // startup's original token. Only explicit retry may recover.
                _ = try? await lifecycle.handle(.lockNow)
                let outcome = await gate.authenticate(trigger: .unlock)
                XCTAssertEqual(outcome, .authenticated)
            }
        )
        let sceneState = InMemorySceneNavigationDeviceStatePortV1()
        let presentation = AppAccessPresentationV1(startupRouter: router) {
            .init(lifecycle: lifecycle, gate: gate, setting: setting,
                  authentication: authentication, sceneNavigationStatePort: { sceneState })
        }
        await presentation.bootstrapIfNeeded()
        await presentation.unlock()
        XCTAssertEqual(presentation.failure, .startup)
        XCTAssertFalse(presentation.permitsContentPresentation)
        XCTAssertNotNil(router.lastStartupAccessFailure)
        let failedStartupStepCount = recorder.steps.count
        XCTAssertGreaterThan(failedStartupStepCount, 0)

        await presentation.retryStartup()
        let firstRetryStepCount = recorder.steps.count
        XCTAssertTrue(presentation.permitsContentPresentation)
        XCTAssertNil(presentation.failure)
        XCTAssertNil(router.lastStartupAccessFailure)
        XCTAssertEqual(router.recoveryBootstrapState, .ready)
        await presentation.retryStartup()
        let secondRetryStepCount = recorder.steps.count

        XCTAssertGreaterThan(firstRetryStepCount, failedStartupStepCount)
        XCTAssertGreaterThan(secondRetryStepCount, firstRetryStepCount)
    }
}

@MainActor
private final class PresentationFixture {
    let support: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String
    let router: StartupRouter
    let factory = PresentationFactoryGate()
    private let recorder: PresentationStepRecorder
    var begunSteps: [StartupStep] { recorder.steps }

    init() throws {
        defaultsSuiteName = "V23.AppAccessPresentation.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-AppAccessPresentation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        recorder = PresentationStepRecorder()
        router = StartupRouter(applicationSupportURL: support) { [recorder] step in
            recorder.steps.append(step)
        }
    }

    func presentation() -> AppAccessPresentationV1 {
        AppAccessPresentationV1(startupRouter: router) { [support, defaults, router, factory] in
            await factory.enter()
            return try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: support,
                startupRouter: router,
                defaults: defaults
            )
        }
    }

    func remove() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: support)
    }

}

@MainActor
private final class PresentationStepRecorder {
    var steps: [StartupStep] = []
}

private actor PresentationFactoryGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func enter() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        if released { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private struct PresentationClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

private final class PresentationIDs: ApplicationIDSource, @unchecked Sendable {
    func makeID() -> UUID { UUID() }
}

private actor PresentationSetting: DeviceLocalAppLockSettingPortV1 {
    private let value: DeviceLocalAppLockSettingReadV1
    init(enabled: Bool) { value = .value(.init(isEnabled: enabled)) }
    func readAppLockSetting() -> DeviceLocalAppLockSettingReadV1 { value }
    func writeAppLockSetting(_ value: DeviceLocalAppLockSettingV1, operationID: UUID,
                             authorization: NotificationOperationAuthorizationV1) throws
        -> DeviceLocalAppLockSettingWriteReceiptV1 {
        throw AppAccessContractFailureV1.invalidTransition
    }
    func eraseAppLockSetting(operationID: UUID) {}
}

private actor PresentationIngress: ProtectedIngressStoreV1 {
    func performBlindStartupHygiene(now: Date, operationID: UUID) throws
        -> ProtectedIngressStartupHygieneReceiptV1 {
        try .init(operationID: operationID, inspectedCount: 0, removedKnownOwnedCount: 0,
                  retainedValidCount: 0, deferredAmbiguousCount: 0, contentRead: false)
    }
    func stageContentBlind(_ request: ProtectedIngressStageRequestV1, source: URL) throws
        -> ProtectedIngressStageReceiptV1 { throw AppAccessContractFailureV1.invalidTransition }
    func pendingIntents() -> [PendingLockedExternalIntentV1] { [] }
    func markReadyForAuthenticatedValidation(intentID: UUID) throws -> PendingLockedExternalIntentV1 {
        throw AppAccessContractFailureV1.ingressNotFound
    }
    func remove(intentID: UUID, disposition: LockedIngressDispositionV1) {}
    func eraseAllProtectedIngress(operationID: UUID) {}
}

private actor PresentationNotifications: AppLockNotificationPrivacyPortV1 {
    func bindNotificationGate(_ gate: AppAccessGateV1) {}
    func loadAuthenticationSubject() -> NotificationOperationSubjectV1? { nil }
    func validatesLocalConfiguration(_ setting: DeviceLocalAppLockSettingReadV1) -> Bool { true }
    func loadJournal() -> AppLockNotificationJournalV1? { nil }
    func prepareEnable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) throws
        -> AppLockNotificationJournalV1 { throw AppAccessContractFailureV1.invalidTransition }
    func applyGenericProjection(_ journal: AppLockNotificationJournalV1,
                                authorization: NotificationOperationAuthorizationV1) throws
        -> AppLockNotificationPrivacyDispositionV1 { throw AppAccessContractFailureV1.invalidTransition }
    func prepareDisable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) throws
        -> AppLockNotificationJournalV1 { throw AppAccessContractFailureV1.invalidTransition }
    func rebuildPriorPolicy(_ journal: AppLockNotificationJournalV1,
                            authorization: NotificationOperationAuthorizationV1) throws
        -> AppLockNotificationPrivacyDispositionV1 { throw AppAccessContractFailureV1.invalidTransition }
    func resolveOpaqueTokenAfterAuthentication(_ token: String, now: Date,
                                               authorization: NotificationOperationAuthorizationV1) -> String? { nil }
    func eraseNotificationsAndMappings(operationID: UUID) {}
}

private actor PresentationGatedAuthentication: LocalAuthenticationClient {
    private var evaluations = 0
    private var started: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<LocalAuthenticationOutcomeV1, Never>?
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 {
        evaluations += 1
        started?.resume()
        started = nil
        return await withCheckedContinuation { completion = $0 }
    }
    func cancel(attemptID: UUID) {}
    func waitUntilAuthenticationBegins() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ outcome: LocalAuthenticationOutcomeV1) {
        completion?.resume(returning: outcome)
        completion = nil
    }
    var evaluationCount: Int { evaluations }
}

private actor PresentationImmediateAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

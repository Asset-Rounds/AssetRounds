import Combine
import Foundation
import XCTest
@testable import FieldEvidenceApp

private actor ReminderSettingsAuthentication: LocalAuthenticationClient {
    func availability() async -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 { .userCancelled }
    func cancel(attemptID: UUID) async {}
}

private actor ReminderJourneyAuthentication: LocalAuthenticationClient {
    func availability() async -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) async {}
}

@MainActor private final class ReminderJourneySystem: NotificationPermissionRequestingV1 {
    enum Failure: Error { case unavailable }
    var status: LocalReminderAuthorizationV1 = .notDetermined
    var promptResult: LocalReminderAuthorizationV1 = .authorized
    var prompts = 0
    var adds: [NotificationSystemRequestV1] = []
    var removals: [[String]] = []
    var failObservations = false
    var duringRequest: (@MainActor () async throws -> Void)?
    func authorization() async throws -> LocalReminderAuthorizationV1 { status }
    func requestAuthorization() async throws -> LocalReminderAuthorizationV1 {
        prompts += 1
        let callback = duringRequest
        duringRequest = nil
        try await callback?()
        status = promptResult
        return status
    }
    func observations() async throws -> [NotificationSystemObservationV1] {
        if failObservations { throw Failure.unavailable }
        return []
    }
    func add(_ request: NotificationSystemRequestV1) async throws { adds.append(request) }
    func remove(_ requestIDs: [String]) async throws { removals.append(requestIDs) }
}

/// Real startup, Preferences, AppLock control and completed-Erase composition.
/// The empty store deliberately has no due entries; payload cases use the
/// authenticated populated schedule fixtures in the delivery test suite.
@MainActor private struct ReminderJourneyFixture {
    let suite: String
    let defaults: UserDefaults
    let root: URL
    let support: URL
    let router: StartupRouter
    let session: ProductionAppAccessSessionV1
    let presentation: AppAccessPresentationV1
    let system: ReminderJourneySystem

    static func start(_ test: XCTestCase) async throws -> Self {
        let suite = "V23.ReminderJourney." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("Library/Application Support")
        let caches = root.appendingPathComponent("Library/Caches")
        let temporary = root.appendingPathComponent("tmp")
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let system = ReminderJourneySystem()
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: ReminderJourneyAuthentication(), notificationSystem: system)
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                EraseAllService(applicationSupportURL: support, cachesDirectoryURL: caches,
                    temporaryDirectoryURL: temporary, userDefaults: defaults, defaultsDomainName: suite,
                    sceneNavigationStatePort: sceneState, privateSystemDiscoveryIndex: nil,
                    notificationSystem: system, admitErase: admission,
                    didCompleteErase: completion, didAbortEraseAdmission: aborted)
            }, sessionFactory: { session })
        let published = test.expectation(description: "Production startup publishes reminder Settings")
        let observation = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        await presentation.bootstrapIfNeeded()
        await test.fulfillment(of: [published], timeout: 30)
        observation.cancel()
        _ = try XCTUnwrap(presentation.reminderSettingsAccess)
        return .init(suite: suite, defaults: defaults, root: root, support: support,
                     router: router, session: session, presentation: presentation, system: system)
    }

    func owners() throws -> ProductionReminderSettingsOwnersV1 {
        try XCTUnwrap(session.reminderSettingsOwners)()
    }

    func erase() async throws {
        guard case .ready(let coordinator, let diagnostics, _) = router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try await presentation.performErase(applicationSupportURL: support, confirmation: "ERASE",
            coordinator: coordinator, diagnosticsStore: diagnostics)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

extension V23ReminderProductionSettingsTests {
    func testProductionReconciliationRetryKeepsSavedRevisionAndNeverPrompts() async throws {
        let fixture = try await ReminderJourneyFixture.start(self)
        defer { fixture.remove() }
        let access = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let initial = try await access.read()
        fixture.system.status = .authorized
        fixture.system.failObservations = true
        do {
            try await access.update(expected: initial.policy, isEnabled: true, detail: .generic)
            XCTFail("Unavailable notification readback reported success")
        } catch { XCTAssertTrue(error is ReminderJourneySystem.Failure) }
        let persisted = try XCTUnwrap(fixture.owners().preferences.readStoredReminderPolicy())
        XCTAssertTrue(persisted.isEnabled)
        XCTAssertEqual(persisted.revision, initial.policy.revision + 1)
        fixture.system.failObservations = false
        let republished = expectation(description: "Foreground publishes fresh reminder Settings after failed OS reconciliation")
        let observation = fixture.presentation.$permitsContentPresentation.dropFirst().filter { $0 }.prefix(1)
            .sink { _ in republished.fulfill() }
        fixture.presentation.receive(.sceneInactive)
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [republished], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        XCTAssertNotEqual(fresh.id, access.id)
        try await fresh.reconcileSavedPolicy()
        XCTAssertEqual(try fixture.owners().preferences.readStoredReminderPolicy(), persisted)
        XCTAssertEqual(fixture.system.prompts, 0)
        XCTAssertTrue(fixture.system.adds.isEmpty)
    }

    func testProductionSettingsReadDoesNotPromptAndDeniedEnablePersistsExplicitChoice() async throws {
        let fixture = try await ReminderJourneyFixture.start(self)
        defer { fixture.remove() }
        let access = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let initial = try await access.read()
        XCTAssertFalse(initial.policy.isEnabled)
        XCTAssertEqual(initial.policy.detail, .generic)
        XCTAssertEqual(fixture.system.prompts, 0)
        fixture.system.promptResult = .denied
        try await access.update(expected: initial.policy, isEnabled: true, detail: .details)
        let saved = try await access.read()
        XCTAssertEqual(fixture.system.prompts, 1)
        XCTAssertEqual(saved.authorization, .denied)
        XCTAssertTrue(saved.policy.isEnabled)
        XCTAssertEqual(saved.policy.detail, .details)
        XCTAssertEqual(saved.policy.revision, initial.policy.revision + 1)
        XCTAssertEqual(try PreferencesAdapterV1(defaults: fixture.defaults).readStoredReminderPolicy(), saved.policy)
        XCTAssertTrue(fixture.system.adds.isEmpty)
        XCTAssertTrue(fixture.presentation.permitsContentPresentation)
        guard case .ready = fixture.router.route else { return XCTFail("Permission denial hid My Day") }
    }

    func testProductionDetailChoiceWhileDisabledDoesNotPromptAndRejectsStaleEdit() async throws {
        let fixture = try await ReminderJourneyFixture.start(self)
        defer { fixture.remove() }
        let access = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let initial = try await access.read()
        try await access.update(expected: initial.policy, isEnabled: false, detail: .details)
        let saved = try await access.read()
        XCTAssertFalse(saved.policy.isEnabled)
        XCTAssertEqual(saved.policy.detail, .details)
        XCTAssertEqual(fixture.system.prompts, 0)
        do {
            try await access.update(expected: initial.policy, isEnabled: true, detail: .generic)
            XCTFail("Stale Settings action overwrote the saved choice")
        } catch {
            XCTAssertEqual(error as? SettingsContractFailureV1, .staleRevision)
        }
        XCTAssertEqual(try fixture.owners().preferences.readStoredReminderPolicy(), saved.policy)
        XCTAssertEqual(fixture.system.prompts, 0)
        XCTAssertTrue(fixture.system.adds.isEmpty)
    }

    func testProductionAppLockRequiresUnlockAndOldSettingsPublicationStaysRevoked() async throws {
        let fixture = try await ReminderJourneyFixture.start(self)
        defer { fixture.remove() }
        let old = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let initial = try await old.read()
        await fixture.presentation.setEnabled(true)
        XCTAssertNil(fixture.presentation.reminderSettingsAccess)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        do {
            try await old.update(expected: initial.policy, isEnabled: false, detail: .details)
            XCTFail("Locked Settings publication changed the saved choice")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        await fixture.presentation.unlock()
        let unlocked = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        XCTAssertNotEqual(unlocked.id, old.id)
        let current = try await unlocked.read()
        XCTAssertTrue(current.appLockEnabled)
        try await unlocked.update(expected: current.policy, isEnabled: false, detail: .details)
        let saved = try await unlocked.read()
        XCTAssertTrue(saved.appLockEnabled)
        XCTAssertEqual(saved.policy.detail, .details)
        do {
            _ = try await old.read()
            XCTFail("A later unlock renewed the earlier Settings publication")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        XCTAssertEqual(fixture.system.prompts, 0)
    }

    func testProductionPermissionReplyAfterBackgroundCannotSaveConsent() async throws {
        let fixture = try await ReminderJourneyFixture.start(self)
        defer { fixture.remove() }
        let access = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let initial = try await access.read()
        let backgroundHandled = expectation(description: "Queued background lifecycle settles before fixture cleanup")
        let observation = fixture.presentation.$accessState.dropFirst().prefix(1)
            .sink { _ in backgroundHandled.fulfill() }
        fixture.system.duringRequest = {
            fixture.presentation.receive(.sceneBackground)
        }
        do {
            try await access.update(expected: initial.policy, isEnabled: true, detail: .details)
            XCTFail("Late permission reply saved consent after backgrounding")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        await fulfillment(of: [backgroundHandled], timeout: 30)
        observation.cancel()
        XCTAssertEqual(fixture.system.prompts, 1)
        XCTAssertEqual(fixture.system.status, .authorized)
        XCTAssertEqual(try fixture.owners().preferences.readStoredReminderPolicy(), initial.policy)
        XCTAssertNil(fixture.presentation.reminderSettingsAccess)
        XCTAssertTrue(fixture.system.adds.isEmpty)
    }

    func testProductionCompletedEraseReplacesOwnersAndRejectsPendingPermissionEdit() async throws {
        let fixture = try await ReminderJourneyFixture.start(self)
        defer { fixture.remove() }
        let oldOwners = try fixture.owners()
        let old = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let initial = try await old.read()
        fixture.system.duringRequest = { try await fixture.erase() }
        do {
            try await old.update(expected: initial.policy, isEnabled: true, detail: .details)
            XCTFail("Pre-Erase permission reply edited replacement Preferences")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let freshOwners = try fixture.owners()
        XCTAssertFalse(oldOwners.preferences === freshOwners.preferences)
        XCTAssertFalse(oldOwners.notifications === freshOwners.notifications)
        let fresh = try XCTUnwrap(fixture.presentation.reminderSettingsAccess)
        let reset = try await fresh.read()
        XCTAssertNotEqual(reset.policy.instanceID, initial.policy.instanceID)
        XCTAssertFalse(reset.policy.isEnabled)
        XCTAssertEqual(reset.policy.detail, .generic)
        do {
            _ = try await old.read()
            XCTFail("Completed Erase renewed old Settings access")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        try await fresh.update(expected: reset.policy, isEnabled: false, detail: .details)
        let saved = try await fresh.read()
        XCTAssertEqual(saved.policy.detail, .details)
        XCTAssertEqual(fixture.system.prompts, 1)
        XCTAssertTrue(fixture.system.adds.isEmpty)
    }
}

@MainActor private final class ReminderSettingsSystem: NotificationPermissionRequestingV1 {
    var status: LocalReminderAuthorizationV1 = .notDetermined
    var prompts = 0
    var authorizationReads = 0
    var afterAuthorizationRead: (@MainActor () async -> Void)?
    var duringRequest: (@MainActor () async -> Void)?
    func authorization() async throws -> LocalReminderAuthorizationV1 {
        authorizationReads += 1
        await afterAuthorizationRead?()
        return status
    }
    func requestAuthorization() async throws -> LocalReminderAuthorizationV1 {
        prompts += 1
        await duringRequest?()
        status = .authorized
        return status
    }
    func observations() async throws -> [NotificationSystemObservationV1] { [] }
    func add(_ request: NotificationSystemRequestV1) async throws { XCTFail("Permission flow scheduled a notification") }
    func remove(_ requestIDs: [String]) async throws { XCTFail("Permission flow removed notifications") }
}

@MainActor private final class ReminderSettingsFixture {
    let suite = "V23.ReminderProduction." + UUID().uuidString
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let preferences: PreferencesAdapterV1
    let control: AppLockNotificationControlStoreV1
    let system = ReminderSettingsSystem()
    let gate: AppAccessGateV1
    let owner: DeviceLocalNotificationOwnerV1

    init(appLockEnabled: Bool = false) async throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences = PreferencesAdapterV1(defaults: defaults)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        control = try AppLockNotificationControlStoreV1(applicationSupportURL: root, preferences: preferences)
        gate = AppAccessGateV1(setting: .value(.init(isEnabled: appLockEnabled)),
            authentication: ReminderSettingsAuthentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        owner = DeviceLocalNotificationOwnerV1(control: control, preferences: preferences,
            system: system, clock: SystemApplicationClock()) { _ in
            XCTFail("Permission flow opened workspace content")
            throw AppAccessContractFailureV1.accessDenied
        }
        try await owner.bindNotificationGateEffect(gate)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor final class V23ReminderProductionSettingsTests: XCTestCase {
    private func assertPermissionDenied(_ owner: DeviceLocalNotificationOwnerV1,
                                        file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await owner.requestReminderAuthorization()
            XCTFail("Stale foreground permission action was accepted", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied, file: file, line: line)
        }
    }

    func testPermissionReadNeverPromptsAndExplicitRequestNeverWritesConsent() async throws {
        let fixture = try await ReminderSettingsFixture()
        defer { fixture.remove() }
        let before = fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?
        let initial = try await fixture.owner.reminderAuthorization()
        XCTAssertEqual(initial, .notDetermined)
        XCTAssertEqual(fixture.system.prompts, 0)
        let allowed = try await fixture.owner.requestReminderAuthorization()
        XCTAssertEqual(allowed, .authorized)
        XCTAssertEqual(fixture.system.prompts, 1)
        let repeated = try await fixture.owner.requestReminderAuthorization()
        XCTAssertEqual(repeated, .authorized)
        XCTAssertEqual(fixture.system.prompts, 1)
        XCTAssertNil(try fixture.preferences.readStoredReminderPolicy())
        XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suite) as NSDictionary?, before)
    }

    func testInactiveDisabledAndLockedEnabledStatesCannotPrompt() async throws {
        for appLockEnabled in [false, true] {
            let fixture = try await ReminderSettingsFixture(appLockEnabled: appLockEnabled)
            defer { fixture.remove() }
            if !appLockEnabled { await fixture.gate.sceneBecameInactive() }
            await assertPermissionDenied(fixture.owner)
            XCTAssertEqual(fixture.system.authorizationReads, 0)
            XCTAssertEqual(fixture.system.prompts, 0)
            XCTAssertNil(try fixture.preferences.readStoredReminderPolicy())
        }
    }

    func testRevocationDuringAuthorizationReadPreventsPrompt() async throws {
        let fixture = try await ReminderSettingsFixture()
        defer { fixture.remove() }
        let gate = fixture.gate
        fixture.system.afterAuthorizationRead = { await gate.sceneBecameInactive() }
        await assertPermissionDenied(fixture.owner)
        XCTAssertEqual(fixture.system.prompts, 0)
        XCTAssertNil(try fixture.preferences.readStoredReminderPolicy())
    }

    func testPermissionReplyAfterRevocationCannotRenewForegroundOrConsent() async throws {
        let fixture = try await ReminderSettingsFixture()
        defer { fixture.remove() }
        let gate = fixture.gate
        fixture.system.duringRequest = { await gate.sceneBecameInactive() }
        await assertPermissionDenied(fixture.owner)
        XCTAssertEqual(fixture.system.prompts, 1)
        XCTAssertEqual(fixture.system.status, .authorized)
        XCTAssertNil(try fixture.preferences.readStoredReminderPolicy())
        await assertPermissionDenied(fixture.owner)
        XCTAssertEqual(fixture.system.prompts, 1)
    }
}

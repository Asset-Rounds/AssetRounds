import Foundation
import XCTest
@testable import FieldEvidenceApp

private actor ReminderEditAuthentication: LocalAuthenticationClient {
    func availability() async -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) async {}
}

private final class ReminderEditBlockingDefaults: UserDefaults, @unchecked Sendable {
    private let armLock = NSLock()
    private var armedKey: String?
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let transitionStarted = DispatchSemaphore(value: 0)
    let transitionFinished = DispatchSemaphore(value: 0)

    func arm(_ key: String) {
        armLock.lock()
        armedKey = key
        armLock.unlock()
    }

    override func object(forKey defaultName: String) -> Any? {
        armLock.lock()
        let pauses = armedKey == defaultName
        if pauses { armedKey = nil }
        armLock.unlock()
        if pauses {
            entered.signal()
            // Keep a failed assertion from stranding a native worker forever.
            guard release.wait(timeout: .now() + 10) == .success else { return nil }
        }
        return super.object(forKey: defaultName)
    }
}

@MainActor private final class ReminderEditFixture {
    let suite = "V23.ReminderEdit." + UUID().uuidString
    let defaults: UserDefaults
    let preferences: PreferencesAdapterV1
    let gate: AppAccessGateV1
    let initial: DeviceLocalReminderPolicyV1
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("ReminderEdit-" + UUID().uuidString)
    private var controls: [AppLockNotificationControlStoreV1] = []

    init(enabled: Bool = false, bound: Bool = true,
         blocksLeafRead: Bool = false) throws {
        if blocksLeafRead {
            defaults = try XCTUnwrap(ReminderEditBlockingDefaults(suiteName: suite))
        } else {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        }
        preferences = PreferencesAdapterV1(defaults: defaults)
        gate = AppAccessGateV1(setting: .value(.init(isEnabled: enabled)),
            authentication: ReminderEditAuthentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        initial = try preferences.readReminderPolicy()
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if bound { try bind(preferences, to: gate) }
    }

    func bind(_ preferences: PreferencesAdapterV1, to gate: AppAccessGateV1) throws {
        let control = try AppLockNotificationControlStoreV1(applicationSupportURL: support, preferences: preferences)
        try preferences.bindReminderPolicyEdits(to: gate, control: control)
        controls.append(control)
    }

    func request() -> ReminderPolicyEditRequestV1 {
        .init(expected: initial, isEnabled: true, detail: .details, operationID: UUID())
    }

    func domain() -> NSDictionary {
        NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:])
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: support)
    }
}

@MainActor final class V23ReminderPolicyEditTests: XCTestCase {
    private func assertMintDenied(_ preferences: PreferencesAdapterV1,
                                  _ request: ReminderPolicyEditRequestV1,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await preferences.authorizeReminderPolicyEdit(request)
            XCTFail("Unusable owner/session minted an edit", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied, file: file, line: line)
        }
    }

    func testUnboundAndRetiredOwnersCannotMintOrRebind() async throws {
        let fixture = try ReminderEditFixture(bound: false)
        defer { fixture.remove() }
        let before = fixture.domain()
        await assertMintDenied(fixture.preferences, fixture.request())
        try fixture.bind(fixture.preferences, to: fixture.gate)
        XCTAssertThrowsError(try fixture.bind(fixture.preferences, to: fixture.gate))
        fixture.preferences.retireReminderPolicyEdits()
        await assertMintDenied(fixture.preferences, fixture.request())
        XCTAssertThrowsError(try fixture.bind(fixture.preferences, to: fixture.gate))
        XCTAssertEqual(fixture.domain(), before)
    }

    func testDisabledForegroundEditAndFreshAuthorityReplayPreserveExactBytes() async throws {
        let fixture = try ReminderEditFixture()
        defer { fixture.remove() }
        let request = fixture.request()
        let first = try await fixture.preferences.authorizeReminderPolicyEdit(request)
        let updated = try fixture.preferences.updateReminderPolicy(first)
        XCTAssertTrue(updated.isEnabled)
        XCTAssertEqual(updated.detail, .details)
        XCTAssertEqual(updated.revision, fixture.initial.revision + 1)
        let written = fixture.domain()
        await fixture.gate.sceneBecameInactive()
        await assertMintDenied(fixture.preferences, request)
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(first))
        await fixture.gate.sceneBecameActive()
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(first))
        XCTAssertEqual(fixture.domain(), written)
        let fresh = try await fixture.preferences.authorizeReminderPolicyEdit(request)
        XCTAssertEqual(try fixture.preferences.updateReminderPolicy(fresh), updated)
        XCTAssertEqual(fixture.domain(), written)
    }

    func testEnabledPolicyRequiresUnlockAndOldCommandCannotSurviveRelock() async throws {
        let fixture = try ReminderEditFixture(enabled: true)
        defer { fixture.remove() }
        let request = fixture.request(), before = fixture.domain()
        await assertMintDenied(fixture.preferences, request)
        XCTAssertEqual(fixture.domain(), before)
        let unlocked = await fixture.gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlocked, .authenticated)
        let first = try await fixture.preferences.authorizeReminderPolicyEdit(request)
        await fixture.gate.lock(reason: .lockNow)
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(first))
        await assertMintDenied(fixture.preferences, request)
        let unlockedAgain = await fixture.gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlockedAgain, .authenticated)
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(first))
        XCTAssertEqual(fixture.domain(), before)
        let fresh = try await fixture.preferences.authorizeReminderPolicyEdit(request)
        XCTAssertTrue(try fixture.preferences.updateReminderPolicy(fresh).isEnabled)
    }

    func testCommandsCannotTransferAcrossAdaptersOrGateIssuers() async throws {
        let fixture = try ReminderEditFixture()
        defer { fixture.remove() }
        let request = fixture.request(), before = fixture.domain()
        let sibling = PreferencesAdapterV1(defaults: fixture.defaults)
        try fixture.bind(sibling, to: fixture.gate)
        let own = try await fixture.preferences.authorizeReminderPolicyEdit(request)
        let siblingCommand = try await sibling.authorizeReminderPolicyEdit(request)
        XCTAssertThrowsError(try sibling.updateReminderPolicy(own))
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(siblingCommand))
        let foreignGate = AppAccessGateV1(setting: .absentDisabled,
            authentication: ReminderEditAuthentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let foreign = PreferencesAdapterV1(defaults: fixture.defaults)
        try fixture.bind(foreign, to: foreignGate)
        let foreignCommand = try await foreign.authorizeReminderPolicyEdit(request)
        XCTAssertFalse(fixture.gate.issuedReminderPolicyEditCommand(foreignCommand))
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(foreignCommand))
        XCTAssertEqual(fixture.domain(), before)
        let updated = try fixture.preferences.updateReminderPolicy(own)
        let written = fixture.domain()
        let replay = try await sibling.authorizeReminderPolicyEdit(request)
        XCTAssertEqual(try sibling.updateReminderPolicy(replay), updated)
        XCTAssertEqual(fixture.domain(), written)
    }

    func testReplacementOwnerAcceptsOnlyFreshCommandsAndRetirementIsMonotonic() async throws {
        let fixture = try ReminderEditFixture()
        defer { fixture.remove() }
        let request = fixture.request(), before = fixture.domain()
        let held = try await fixture.preferences.authorizeReminderPolicyEdit(request)
        let replacement = PreferencesAdapterV1(defaults: fixture.defaults)
        try fixture.bind(replacement, to: fixture.gate)
        fixture.preferences.retireReminderPolicyEdits()
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(held))
        XCTAssertThrowsError(try replacement.updateReminderPolicy(held))
        await fixture.gate.sceneBecameInactive()
        await fixture.gate.sceneBecameActive()
        await assertMintDenied(fixture.preferences, request)
        let fresh = try await replacement.authorizeReminderPolicyEdit(request)
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(fresh))
        XCTAssertEqual(fixture.domain(), before)
        XCTAssertTrue(try replacement.updateReminderPolicy(fresh).isEnabled)
    }

    func testProtectedDataAndConfigurationTransitionsRevokeHeldEditsWithoutEffects() async throws {
        for configurationFailure in [false, true] {
            let fixture = try ReminderEditFixture()
            defer { fixture.remove() }
            let request = fixture.request(), before = fixture.domain()
            let held = try await fixture.preferences.authorizeReminderPolicyEdit(request)
            if configurationFailure { await fixture.gate.markConfigurationUnknown() }
            else { await fixture.gate.markProtectedDataUnavailable() }
            XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(held))
            await assertMintDenied(fixture.preferences, request)
            XCTAssertEqual(fixture.domain(), before)
            if !configurationFailure {
                let generation = await fixture.gate.protectedDataAvailabilityRecoveryGeneration()
                let expected = try XCTUnwrap(generation)
                try await fixture.gate.recoverProtectedDataAvailability(setting: .value(.init(isEnabled: false)),
                    configurationVerified: true, expectedGeneration: expected)
                XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(held))
                let fresh = try await fixture.preferences.authorizeReminderPolicyEdit(request)
                XCTAssertTrue(try fixture.preferences.updateReminderPolicy(fresh).isEnabled)
            }
        }
    }

    func testActualPreferenceWriteSerializesWithRevocationAndRetirement() async throws {
        for retiresOwner in [false, true] {
            let fixture = try ReminderEditFixture(blocksLeafRead: true)
            defer { fixture.remove() }
            let blocked = try XCTUnwrap(fixture.defaults as? ReminderEditBlockingDefaults)
            defer { blocked.release.signal() }
            let preferences = fixture.preferences, gate = fixture.gate
            let request = fixture.request()
            let command = try await preferences.authorizeReminderPolicyEdit(request)
            let keys = fixture.defaults.persistentDomain(forName: fixture.suite)?.keys.map { $0 } ?? []
            XCTAssertEqual(keys.count, 1)
            blocked.arm(try XCTUnwrap(keys.first))
            // Pause the real leaf after it owns both locks, without wrapping
            // update in a second acquisition of the nonrecursive reference.
            let writer = Task.detached { try preferences.updateReminderPolicy(command) }
            XCTAssertEqual(blocked.entered.wait(timeout: .now() + 5), .success)
            let transition = Task.detached {
                blocked.transitionStarted.signal()
                if retiresOwner { preferences.retireReminderPolicyEdits() }
                else { await gate.sceneBecameInactive() }
                blocked.transitionFinished.signal()
            }
            XCTAssertEqual(blocked.transitionStarted.wait(timeout: .now() + 5), .success)
            XCTAssertEqual(blocked.transitionFinished.wait(timeout: .now() + 0.1), .timedOut)
            blocked.release.signal()
            let updated = try await writer.value
            await transition.value
            XCTAssertEqual(blocked.transitionFinished.wait(timeout: .now()), .success)
            XCTAssertEqual(updated.revision, request.expected.revision + 1)
            XCTAssertTrue(updated.isEnabled)
            XCTAssertEqual(updated.detail, .details)
            XCTAssertEqual(try preferences.readReminderPolicy(), updated)
            let written = fixture.domain()
            XCTAssertThrowsError(try preferences.updateReminderPolicy(command))
            await assertMintDenied(preferences, request)
            XCTAssertEqual(fixture.domain(), written)
        }
    }
}

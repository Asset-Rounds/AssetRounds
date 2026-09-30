import Foundation
import XCTest
@testable import FieldEvidenceApp

private actor ReminderContinuationAuthentication: LocalAuthenticationClient {
    func availability() async -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) async {}
}

@MainActor private final class ReminderContinuationSystem: NotificationSystemPortV1 {
    var calls = 0
    func authorization() async throws -> LocalReminderAuthorizationV1 { calls += 1; return .denied }
    func observations() async throws -> [NotificationSystemObservationV1] { calls += 1; return [] }
    func add(_ request: NotificationSystemRequestV1) async throws { calls += 1 }
    func remove(_ requestIDs: [String]) async throws { calls += 1 }
}

@MainActor private final class ReminderContinuationFixture {
    let suite = "V23.ReminderContinuation." + UUID().uuidString
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("ReminderContinuation-" + UUID().uuidString)
    let defaults: UserDefaults
    let preferences: PreferencesAdapterV1
    let control: AppLockNotificationControlStoreV1
    let original: AppLockNotificationControlV1
    let initial: DeviceLocalReminderPolicyV1
    let gate: AppAccessGateV1
    var root: URL { support.appendingPathComponent("FieldEvidenceOperations")
        .appendingPathComponent(AppLockNotificationControlStoreV1.rootName) }
    var record: URL { root.appendingPathComponent(AppLockNotificationControlStoreV1.recordName) }
    var pending: URL { root.appendingPathComponent(AppLockNotificationControlStoreV1.pendingName) }
    var policyKey: String { PreferencesAdapterV1.storagePrefix + DeviceLocalReminderPolicyV1.key }

    init(enabled: Bool = true, failure: AppLockNotificationControlFailurePointV1 = .none) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences = PreferencesAdapterV1(defaults: defaults)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let setup = try AppLockNotificationControlStoreV1(applicationSupportURL: support, preferences: preferences)
        initial = try preferences.readReminderPolicy()
        // Storage-protocol fixture dispositions do not claim a real OS effect.
        let enableID = UUID()
        let plan = try preferences.planAppLockSettingWrite(expectedSetting: preferences.readAppLockSettingSnapshot(),
            expectedReminderPolicy: initial, target: .init(isEnabled: true), operationID: enableID)
        let journal = try AppLockNotificationJournalV1(operationID: enableID, targetEnabled: true,
            priorPolicy: initial.appLockReference(), projections: [], disposition: .genericProjectionApplied)
        let prepared = try setup.prepareControl(journal: journal, priorReminderPolicy: initial,
            settingWrite: plan, expectedPredecessor: nil)
        let committed = try setup.completeSetting(expected: prepared)
        if enabled {
            original = committed
        } else {
            let disableID = UUID()
            let disablePlan = try preferences.planAppLockSettingWrite(expectedSetting: preferences.readAppLockSettingSnapshot(),
                expectedReminderPolicy: initial, target: .init(isEnabled: false), operationID: disableID)
            let disabling = try AppLockNotificationJournalV1(operationID: disableID, targetEnabled: false,
                priorPolicy: initial.appLockReference(), projections: [], disposition: .disablingPrepared)
            let next = try setup.prepareControl(journal: disabling, priorReminderPolicy: initial,
                settingWrite: disablePlan, expectedPredecessor: committed)
            let disabled = try setup.completeSetting(expected: next)
            let rebuilt = try AppLockNotificationJournalV1(operationID: disableID, targetEnabled: false,
                priorPolicy: initial.appLockReference(), projections: [], disposition: .priorPolicyRebuilt)
            original = try setup.recordJournal(rebuilt, expected: disabled)
        }
        control = try AppLockNotificationControlStoreV1(applicationSupportURL: support,
            preferences: preferences, failurePoint: failure)
        gate = AppAccessGateV1(setting: .value(.init(isEnabled: enabled)),
            authentication: ReminderContinuationAuthentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        try preferences.bindReminderPolicyEdits(to: gate, control: control)
    }

    func command(expected: DeviceLocalReminderPolicyV1? = nil, enabled: Bool = true,
                 detail: ReminderNotificationDetailV1 = .details,
                 operationID: UUID = UUID()) async throws -> AppAccessGateV1.ReminderPolicyEditCommandV1 {
        if original.journal.targetEnabled {
            if case .unlockedForeground = await gate.currentState() {} else {
                let outcome = await gate.authenticate(trigger: .unlock)
                XCTAssertEqual(outcome, .authenticated)
            }
        }
        return try await preferences.authorizeReminderPolicyEdit(.init(
            expected: expected ?? preferences.readReminderPolicy(), isEnabled: enabled,
            detail: detail, operationID: operationID))
    }

    func reopened() throws -> (preferences: PreferencesAdapterV1, control: AppLockNotificationControlStoreV1) {
        let fresh = PreferencesAdapterV1(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        return (fresh, try AppLockNotificationControlStoreV1(applicationSupportURL: support, preferences: fresh))
    }

    func policyBytes() throws -> Data { try XCTUnwrap(defaults.data(forKey: policyKey)) }
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: support)
    }
}

@MainActor final class V23ReminderControlContinuationTests: XCTestCase {
    func testIncompleteEnableAndDisableRemainAvailableForAuthenticatedRecovery() async throws {
        for targetEnabled in [true, false] {
            let fixture = try ReminderContinuationFixture(enabled: !targetEnabled)
            defer { fixture.remove() }
            let operation = UUID()
            let plan = try fixture.preferences.planAppLockSettingWrite(
                expectedSetting: fixture.preferences.readAppLockSettingSnapshot(),
                expectedReminderPolicy: fixture.initial, target: .init(isEnabled: targetEnabled), operationID: operation)
            let journal = try AppLockNotificationJournalV1(operationID: operation, targetEnabled: targetEnabled,
                priorPolicy: fixture.initial.appLockReference(), projections: [],
                disposition: targetEnabled ? .enablingPrepared : .disablingPrepared)
            let prepared = try fixture.control.prepareControl(journal: journal, priorReminderPolicy: fixture.initial,
                settingWrite: plan, expectedPredecessor: fixture.original)
            if !targetEnabled { _ = try fixture.control.completeSetting(expected: prepared) }
            let record = try Data(contentsOf: fixture.record), policy = try fixture.policyBytes()
            let fresh = try fixture.reopened(), system = ReminderContinuationSystem()
            let owner = DeviceLocalNotificationOwnerV1(control: fresh.control, preferences: fresh.preferences,
                system: system, clock: SystemApplicationClock()) { _ in
                XCTFail("Incomplete local control opened content")
                throw AppAccessContractFailureV1.accessDenied
            }
            let setting = await owner.readAppLockSetting()
            let valid = try await owner.validatesLocalConfigurationEffect(setting)
            XCTAssertFalse(valid)
            XCTAssertEqual(try Data(contentsOf: fixture.record), record)
            XCTAssertEqual(try fixture.policyBytes(), policy)
            XCTAssertEqual(system.calls, 0)
        }
    }

    func testEnabledAndCompletedDisabledEditsReopenWithoutReplayingPolicyOrOSEffects() async throws {
        for enabled in [true, false] {
            let fixture = try ReminderContinuationFixture(enabled: enabled)
            defer { fixture.remove() }
            let command = try await fixture.command()
            let successor = try fixture.preferences.updateReminderPolicy(command)
            let bytes = try fixture.policyBytes()
            let fresh = try fixture.reopened()
            let continued = try XCTUnwrap(fresh.control.readyControlForReminderPolicy())
            XCTAssertEqual(continued.currentReminderPolicy, successor)
            XCTAssertEqual(continued.journal, fixture.original.journal)
            XCTAssertEqual(continued.settingWrite, fixture.original.settingWrite)
            XCTAssertEqual(continued.priorReminderPolicy, fixture.original.priorReminderPolicy)
            let system = ReminderContinuationSystem()
            let owner = DeviceLocalNotificationOwnerV1(control: fresh.control, preferences: fresh.preferences,
                system: system, clock: SystemApplicationClock()) { _ in
                XCTFail("Local readiness opened workspace content")
                throw AppAccessContractFailureV1.accessDenied
            }
            let setting = await owner.readAppLockSetting()
            XCTAssertEqual(setting, .value(.init(isEnabled: enabled)))
            let valid = try await owner.validatesLocalConfigurationEffect(setting)
            XCTAssertTrue(valid)
            XCTAssertEqual(system.calls, 0)
            XCTAssertEqual(try fixture.policyBytes(), bytes)
            XCTAssertEqual(try fresh.preferences.readStoredReminderPolicy(), successor)
        }
    }

    func testSecondEditRollsContinuationAndRejectsOldOperationAndAuthenticationSubject() async throws {
        let fixture = try ReminderContinuationFixture()
        defer { fixture.remove() }
        let oldSubject = try NotificationOperationSubjectV1(control: fixture.original)
        let first = try await fixture.command()
        let firstPolicy = try fixture.preferences.updateReminderPolicy(first)
        let firstControl = try XCTUnwrap(fixture.control.loadControl())
        let freshReplay = try await fixture.command(expected: fixture.initial, operationID: first.request.operationID)
        XCTAssertEqual(try fixture.preferences.updateReminderPolicy(freshReplay), firstPolicy)
        let second = try await fixture.command(expected: firstPolicy, enabled: false, detail: .generic)
        let secondPolicy = try fixture.preferences.updateReminderPolicy(second)
        let continued = try XCTUnwrap(fixture.control.loadControl())
        XCTAssertEqual(secondPolicy.revision, fixture.initial.revision + 2)
        XCTAssertEqual(continued.reminderPolicyContinuation?.expectedControlSHA256,
            try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(firstControl)))
        let newSubject = try NotificationOperationSubjectV1(control: continued)
        XCTAssertFalse(oldSubject.hasSameImmutableSubject(as: newSubject))
        XCTAssertNotEqual(try oldSubject.immutableSHA256(), try newSubject.immutableSHA256())
        let stale = try await fixture.command(expected: fixture.initial, operationID: first.request.operationID)
        let before = try fixture.policyBytes()
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(stale))
        XCTAssertThrowsError(try fixture.control.completeSetting(expected: fixture.original))
        XCTAssertThrowsError(try fixture.control.recordJournal(fixture.original.journal, expected: fixture.original))
        XCTAssertEqual(try fixture.policyBytes(), before)
        XCTAssertEqual(try fixture.control.loadControl(), continued)
    }

    func testInterruptedPreferenceAndPendingPublicationRecoverMetadataExactlyOnce() async throws {
        for failure: AppLockNotificationControlFailurePointV1 in [.afterReminderPreferenceWrite, .afterPendingWriteBeforeSync] {
            let fixture = try ReminderContinuationFixture(failure: failure)
            defer { fixture.remove() }
            let command = try await fixture.command()
            XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(command))
            let stored = try XCTUnwrap(fixture.preferences.readStoredReminderPolicy())
            XCTAssertEqual(stored.revision, fixture.initial.revision + 1)
            XCTAssertEqual(try fixture.control.loadControl(), fixture.original)
            let bytes = try fixture.policyBytes()
            let fresh = try fixture.reopened()
            let settled = try XCTUnwrap(fresh.control.readyControlForReminderPolicy())
            XCTAssertEqual(settled.currentReminderPolicy, stored)
            XCTAssertEqual(try fresh.control.readyControlForReminderPolicy(), settled)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.pending.path))
            XCTAssertEqual(try fixture.policyBytes(), bytes)
            try fresh.preferences.bindReminderPolicyEdits(to: fixture.gate, control: fresh.control)
            let next = try await fresh.preferences.authorizeReminderPolicyEdit(.init(expected: stored,
                isEnabled: false, detail: .generic, operationID: UUID()))
            let successor = try fresh.preferences.updateReminderPolicy(next)
            XCTAssertEqual(successor.revision, fixture.initial.revision + 2)
            XCTAssertEqual(try fresh.control.readyControlForReminderPolicy()?.currentReminderPolicy, successor)
        }
    }

    func testInterruptedPolicyEditRejectsOldSubjectBeforeNewToggleSourceOrOSEffects() async throws {
        let fixture = try ReminderContinuationFixture(failure: .afterReminderPreferenceWrite)
        defer { fixture.remove() }
        let oldSubject = try NotificationOperationSubjectV1(control: fixture.original)
        let command = try await fixture.command(enabled: false, detail: .generic)
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(command))
        let bytes = try fixture.policyBytes()
        let outcome = await fixture.gate.authenticate(trigger: .disableAppLock)
        XCTAssertEqual(outcome, .authenticated)
        let token = try await fixture.gate.toggleAuthenticationToken(targetEnabled: false)
        let operation = UUID()
        let authorization = NotificationOperationAuthorizationV1(gate: fixture.gate,
            proof: .toggle(token, targetEnabled: false), operationID: operation, subject: oldSubject)
        let system = ReminderContinuationSystem()
        let owner = DeviceLocalNotificationOwnerV1(control: fixture.control, preferences: fixture.preferences,
            system: system, clock: SystemApplicationClock()) { _ in
            XCTFail("Stale pre-edit subject opened content")
            throw AppAccessContractFailureV1.accessDenied
        }
        try await owner.bindNotificationGateEffect(fixture.gate)
        do {
            _ = try await owner.prepareDisableEffect(operationID: operation,
                expectedPredecessor: fixture.original.journal, authorization: authorization)
            XCTFail("Pre-edit subject prepared a new toggle")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch)
        }
        let continued = try XCTUnwrap(fixture.control.loadControl())
        XCTAssertEqual(continued.journal, fixture.original.journal)
        XCTAssertEqual(continued.settingWrite, fixture.original.settingWrite)
        XCTAssertEqual(continued.currentReminderPolicy, try fixture.preferences.readStoredReminderPolicy())
        let newSubject = try await owner.loadAuthenticationSubjectEffect()
        XCTAssertNotEqual(newSubject, oldSubject)
        XCTAssertNil(try fixture.control.loadPrivateNotificationMapping())
        XCTAssertEqual(try fixture.policyBytes(), bytes)
        XCTAssertEqual(system.calls, 0)
    }

    func testDivergentPendingBlocksSettlementAndSecondPolicyWriteWithoutDiscardingEvidence() async throws {
        let fixture = try ReminderContinuationFixture(failure: .afterReminderPreferenceWrite)
        defer { fixture.remove() }
        let first = try await fixture.command()
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(first))
        let divergent = Data("divergent publication".utf8)
        try divergent.write(to: fixture.pending)
        try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: fixture.pending)
        let before = try fixture.policyBytes(), record = try Data(contentsOf: fixture.record)
        let fresh = try fixture.reopened()
        XCTAssertThrowsError(try fresh.control.readyControlForReminderPolicy())
        try fresh.preferences.bindReminderPolicyEdits(to: fixture.gate, control: fresh.control)
        let next = try await fresh.preferences.authorizeReminderPolicyEdit(.init(
            expected: XCTUnwrap(fresh.preferences.readStoredReminderPolicy()),
            isEnabled: false, detail: .generic, operationID: UUID()))
        XCTAssertThrowsError(try fresh.preferences.updateReminderPolicy(next))
        XCTAssertEqual(try fixture.policyBytes(), before)
        XCTAssertEqual(try Data(contentsOf: fixture.record), record)
        XCTAssertEqual(try Data(contentsOf: fixture.pending), divergent)
    }

    func testUnstampedResetEraseAndChangedStampCannotRepairControl() async throws {
        for mode in 0..<7 {
            let fixture = try ReminderContinuationFixture(failure: .afterReminderPreferenceWrite)
            defer { fixture.remove() }
            if mode == 0 {
                _ = try fixture.preferences.resetReminderPolicy(expected: fixture.initial, operationID: UUID())
            } else if mode == 1 {
                _ = try fixture.preferences.eraseReminderPolicy(expected: fixture.initial, operationID: UUID())
            } else {
                let command = try await fixture.command()
                XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(command))
                var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture.policyBytes()) as? [String: Any])
                var operation = try XCTUnwrap(envelope["reminderOperation"] as? [String: Any])
                if mode == 2 { operation.removeValue(forKey: "controlStamp") }
                else {
                    var stamp = try XCTUnwrap(operation["controlStamp"] as? [String: Any])
                    switch mode {
                    case 3: stamp["rootIdentity"] = "0:0:0:0"
                    case 4: stamp["expectedControlSHA256"] = String(repeating: "0", count: 64)
                    case 5: stamp["operationID"] = UUID().uuidString
                    default: stamp["unknownAuthority"] = true
                    }
                    operation["controlStamp"] = stamp
                }
                envelope["reminderOperation"] = operation
                fixture.defaults.set(try JSONSerialization.data(withJSONObject: envelope,
                    options: [.sortedKeys, .withoutEscapingSlashes]), forKey: fixture.policyKey)
            }
            let bytes = try fixture.policyBytes(), record = try Data(contentsOf: fixture.record)
            XCTAssertThrowsError(try fixture.reopened().control.readyControlForReminderPolicy())
            XCTAssertEqual(try fixture.policyBytes(), bytes)
            XCTAssertEqual(try Data(contentsOf: fixture.record), record)
        }
    }

    func testForeignPreferencesControlBindingAndChangedSettingDenyBeforePolicyWrite() async throws {
        let fixture = try ReminderContinuationFixture()
        defer { fixture.remove() }
        let foreign = PreferencesAdapterV1(defaults: fixture.defaults)
        XCTAssertThrowsError(try foreign.bindReminderPolicyEdits(to: fixture.gate, control: fixture.control))
        let command = try await fixture.command()
        let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalAppLockSettingV1.key)
        try fixture.preferences.writeCanonicalValue(CompatibilityCanonicalV1.encode(true),
            descriptor: descriptor, operationID: UUID())
        let bytes = try fixture.policyBytes(), record = try Data(contentsOf: fixture.record)
        XCTAssertThrowsError(try fixture.preferences.updateReminderPolicy(command))
        XCTAssertEqual(try fixture.policyBytes(), bytes)
        XCTAssertEqual(try Data(contentsOf: fixture.record), record)
    }

    func testMissingDisabledControlWithStampOrPendingIsNotReady() async throws {
        for stamped in [true, false] {
            let fixture = try ReminderContinuationFixture(enabled: false)
            defer { fixture.remove() }
            if stamped {
                let command = try await fixture.command()
                _ = try fixture.preferences.updateReminderPolicy(command)
            } else {
                try Data("orphan pending".utf8).write(to: fixture.pending)
                try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: fixture.pending)
            }
            try FileManager.default.removeItem(at: fixture.record)
            let bytes = try fixture.policyBytes(), system = ReminderContinuationSystem()
            let owner = DeviceLocalNotificationOwnerV1(control: fixture.control, preferences: fixture.preferences,
                system: system, clock: SystemApplicationClock()) { _ in
                XCTFail("Missing control opened content")
                throw AppAccessContractFailureV1.accessDenied
            }
            let setting = await owner.readAppLockSetting()
            let valid = try await owner.validatesLocalConfigurationEffect(setting)
            XCTAssertFalse(valid)
            XCTAssertEqual(try fixture.policyBytes(), bytes)
            do {
                _ = try await owner.loadAuthenticationSubjectEffect()
                XCTFail("Missing stamped or pending control exposed a new-operation subject")
            } catch {
                XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.record.path))
            XCTAssertEqual(system.calls, 0)
        }
    }

    func testNilContinuationPreservesLegacyCanonicalControlAndSubjectBytes() throws {
        let fixture = try ReminderContinuationFixture()
        defer { fixture.remove() }
        struct LegacyControl: Encodable {
            let schemaVersion = 1
            let journal: AppLockNotificationJournalV1
            let priorReminderPolicy: DeviceLocalReminderPolicyV1
            let settingWrite: AppLockSettingWritePlanV1
            let phase: AppLockNotificationControlV1.Phase
        }
        struct LegacySubject: Encodable {
            let operationID: UUID
            let targetEnabled: Bool
            let priorPolicy: AppLockNotificationCanonicalPolicyV1
            let projections: [AppLockGenericNotificationV1]
            let settingWriteSHA256: String
        }
        let original = fixture.original
        let legacy = try CompatibilityCanonicalV1.encode(LegacyControl(journal: original.journal,
            priorReminderPolicy: original.priorReminderPolicy, settingWrite: original.settingWrite, phase: original.phase))
        XCTAssertEqual(try CompatibilityCanonicalV1.encode(original), legacy)
        XCTAssertEqual(try CompatibilityCanonicalV1.decode(AppLockNotificationControlV1.self, from: legacy), original)
        let subject = try NotificationOperationSubjectV1(control: original)
        let oldBasis = try CompatibilityCanonicalV1.encode(LegacySubject(operationID: original.journal.operationID,
            targetEnabled: original.journal.targetEnabled, priorPolicy: original.journal.priorPolicy,
            projections: original.journal.projections,
            settingWriteSHA256: CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(original.settingWrite))))
        XCTAssertEqual(try subject.immutableSHA256(), CompatibilityCanonicalV1.sha256(oldBasis))
    }
}

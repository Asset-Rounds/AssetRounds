import Foundation
import CryptoKit
import Darwin
import XCTest

@testable import FieldEvidenceApp

private struct C16NotificationControlFixture {
    let support: URL
    let suiteName: String
    let defaults: UserDefaults
    let preferences: PreferencesAdapterV1
    var controlRoot: URL { support.appendingPathComponent("FieldEvidenceOperations")
        .appendingPathComponent(AppLockNotificationControlStoreV1.rootName) }
    var recordURL: URL { controlRoot.appendingPathComponent(AppLockNotificationControlStoreV1.recordName) }

    init() throws {
        support = FileManager.default.temporaryDirectory.appendingPathComponent("C16-control-" + UUID().uuidString)
        suiteName = "C16.control." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        preferences = PreferencesAdapterV1(defaults: defaults)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func owner(_ failure: AppLockNotificationControlFailurePointV1 = .none) throws -> AppLockNotificationControlStoreV1 {
        try .init(applicationSupportURL: support, preferences: preferences, failurePoint: failure)
    }

    func policy() throws -> DeviceLocalReminderPolicyV1 {
        let initial = try preferences.readReminderPolicy()
        return try preferences.updateReminderPolicy(expected: initial, isEnabled: true,
            detail: .details, operationID: UUID())
    }

    // Fixture dispositions test the storage protocol only; no OS observation is claimed.
    func journal(_ policy: DeviceLocalReminderPolicyV1, operation: UUID,
        disposition: AppLockNotificationPrivacyDispositionV1, enabled: Bool = true) throws -> AppLockNotificationJournalV1 {
        try .init(operationID: operation, targetEnabled: enabled, priorPolicy: policy.appLockReference(),
            projections: [], disposition: disposition)
    }

    func plan(_ policy: DeviceLocalReminderPolicyV1, operation: UUID, enabled: Bool = true) throws -> AppLockSettingWritePlanV1 {
        try preferences.planAppLockSettingWrite(expectedSetting: preferences.readAppLockSettingSnapshot(),
            expectedReminderPolicy: policy, target: .init(isEnabled: enabled), operationID: operation)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: support)
    }
}

extension V9_15AppLockLifecycleTests {
    @MainActor
    func testConcreteNotificationOwnerKeepsBootstrapLazyAndCompletesOnlyFreshToggle() async throws {
        let fixture = try C16NotificationControlFixture()
        // The Simulator owns final cleanup while SQLite may still be retained.
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        _ = try fixture.preferences.readReminderPolicy()
        let session = try StoreGenerationFactory(applicationSupportURL: fixture.support).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let probe = V915NotificationSystemProbe()
        let control = try fixture.owner()
        let owner = DeviceLocalNotificationOwnerV1(control: control, preferences: fixture.preferences,
            system: probe, clock: V915Clock()) { authorization in
                probe.sourceOpenCount += 1
                return ProductionMyDaySourceProviderV1(session: coordinator, accessGate: authorization.gate)
            }
        let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(setting: owner,
            authentication: V915AuthenticationClient(outcomes: [.authenticated, .authenticated]),
            ingressStore: V915IngressStore(), notifications: AppLockNotificationPrivacyCoordinatorV1(effects: owner),
            clock: V915Clock(), identifiers: V915IDs(values: (901...914).map(Self.id)))
        XCTAssertEqual(probe.sourceOpenCount, 0)
        XCTAssertEqual(probe.observationCount, 0)
        XCTAssertNil(try control.loadPrivateNotificationMapping())
        let receipt = try await lifecycle.enable(operationID: Self.id(915))
        XCTAssertTrue(receipt.enabled)
        XCTAssertGreaterThan(probe.sourceOpenCount, 0)
        XCTAssertGreaterThan(probe.observationCount, 0)
        let completed = try XCTUnwrap(control.loadControl())
        XCTAssertEqual(completed.phase, .settingCommitted)
        XCTAssertEqual(try fixture.preferences.readAppLockSettingSnapshot(), completed.settingWrite.successor)
        let gate = await lifecycle.accessGate()
        let state = await gate.currentState()
        XCTAssertEqual(state, .locked(reason: .coldLaunch))
        _ = await gate.authenticate(trigger: .unlock)
        let ordinary = NotificationOperationAuthorizationV1(gate: gate,
            proof: .content(try await gate.beginContentRead(for: .render)), operationID: Self.id(916),
            subject: try NotificationOperationSubjectV1(control: completed))
        let beforeOpens = probe.sourceOpenCount
        do {
            _ = try await owner.prepareDisableEffect(operationID: Self.id(916),
                expectedPredecessor: completed.journal, authorization: ordinary)
            XCTFail("ordinary content proof prepared a setting mutation")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        XCTAssertEqual(probe.sourceOpenCount, beforeOpens)
        XCTAssertEqual(try control.loadControl(), completed)
        XCTAssertTrue(probe.requests.isEmpty)
    }

    @MainActor
    func testConcreteNotificationRepairReadsCanonicalSchedulesWhileOrdinaryContentStaysCovered() async throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        _ = try fixture.preferences.readReminderPolicy()
        let session = try StoreGenerationFactory(applicationSupportURL: fixture.support).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let probe = V915NotificationSystemProbe()
        let control = try fixture.owner()
        let owner = DeviceLocalNotificationOwnerV1(control: control, preferences: fixture.preferences,
            system: probe, clock: V915Clock()) { authorization in
                probe.sourceOpenCount += 1
                return ProductionMyDaySourceProviderV1(session: coordinator, accessGate: authorization.gate)
            }
        let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(setting: owner,
            authentication: V915AuthenticationClient(outcomes: [.authenticated, .authenticated]),
            ingressStore: V915IngressStore(), notifications: AppLockNotificationPrivacyCoordinatorV1(effects: owner),
            clock: V915Clock(), identifiers: V915IDs(values: (921...938).map(Self.id)))
        let gate = await lifecycle.accessGate()
        probe.beforeObservation = { await gate.lock(reason: .returnedFromBackground) }
        do { _ = try await lifecycle.enable(operationID: Self.id(939)); XCTFail("revoked OS read published setting") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        XCTAssertNil(try fixture.preferences.readAppLockSettingSnapshot().setting)
        XCTAssertEqual(try control.loadControl()?.phase, .prepared)
        let original = try XCTUnwrap(control.loadControl())
        probe.beforeObservation = {
            do { _ = try await gate.beginContentRead(for: .render); XCTFail("repair opened ordinary content") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            let covered = await gate.privacyCoverRequired()
            XCTAssertTrue(covered)
        }
        let result = try await lifecycle.recoverAfterAuthentication()
        XCTAssertEqual(result, .resumedToLocked)
        let repaired = try XCTUnwrap(control.loadControl())
        XCTAssertEqual(repaired.journal.operationID, original.journal.operationID)
        XCTAssertEqual(repaired.settingWrite, original.settingWrite)
        XCTAssertEqual(repaired.phase, .settingCommitted)
        XCTAssertEqual(try fixture.preferences.readAppLockSettingSnapshot(), repaired.settingWrite.successor)
        let finalState = await gate.currentState()
        XCTAssertEqual(finalState, .locked(reason: .coldLaunch))
    }

    @MainActor
    func testConcreteNotificationColdRepairRebindsOnlyEphemeralSourceIdentity() async throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        _ = try fixture.preferences.readReminderPolicy()
        let probe = V915NotificationSystemProbe()
        do {
            let session = try StoreGenerationFactory(applicationSupportURL: fixture.support).openOrBootstrapCurrent()
            let coordinator = try StoreSessionCoordinator(validatingSession: session)
            let owner = DeviceLocalNotificationOwnerV1(control: try fixture.owner(), preferences: fixture.preferences,
                system: probe, clock: V915Clock()) { authorization in
                    ProductionMyDaySourceProviderV1(session: coordinator, accessGate: authorization.gate)
                }
            let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(setting: owner,
                authentication: V915AuthenticationClient(outcomes: [.authenticated]),
                ingressStore: V915IngressStore(), notifications: AppLockNotificationPrivacyCoordinatorV1(effects: owner),
                clock: V915Clock(), identifiers: V915IDs(values: (941...955).map(Self.id)))
            let gate = await lifecycle.accessGate()
            probe.beforeObservation = { await gate.lock(reason: .returnedFromBackground) }
            do { _ = try await lifecycle.enable(operationID: Self.id(956)); XCTFail("revoked read completed toggle") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            probe.beforeObservation = nil
        }
        let reopenedControl = try fixture.owner()
        let original = try XCTUnwrap(reopenedControl.loadControl())
        let oldMapping = try XCTUnwrap(reopenedControl.loadPrivateNotificationMapping())
        XCTAssertEqual(original.phase, .prepared)
        let session = try StoreGenerationFactory(applicationSupportURL: fixture.support).openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        let owner = DeviceLocalNotificationOwnerV1(control: reopenedControl, preferences: fixture.preferences,
            system: probe, clock: V915Clock()) { authorization in
                probe.sourceOpenCount += 1
                return ProductionMyDaySourceProviderV1(session: coordinator, accessGate: authorization.gate)
            }
        let reopened = try await AppLockLifecycleCoordinatorV1.bootstrap(setting: owner,
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            ingressStore: V915IngressStore(), notifications: AppLockNotificationPrivacyCoordinatorV1(effects: owner),
            clock: V915Clock(), identifiers: V915IDs(values: (961...975).map(Self.id)))
        XCTAssertEqual(probe.sourceOpenCount, 0)
        let gate = await reopened.accessGate()
        probe.beforeObservation = {
            do { _ = try await gate.beginContentRead(for: .render); XCTFail("cold repair exposed ordinary content") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        }
        let result = try await reopened.recoverAfterAuthentication()
        XCTAssertEqual(result, .resumedToLocked)
        let repaired = try XCTUnwrap(reopenedControl.loadControl())
        let mapping = try XCTUnwrap(reopenedControl.loadPrivateNotificationMapping())
        XCTAssertEqual(repaired.phase, .settingCommitted)
        XCTAssertEqual(repaired.settingWrite, original.settingWrite)
        XCTAssertEqual(mapping.operationID, oldMapping.operationID)
        XCTAssertEqual(mapping.controlSubjectSHA256, oldMapping.controlSubjectSHA256)
        XCTAssertEqual(mapping.source.projection, oldMapping.source.projection)
        XCTAssertEqual(mapping.source.sourceClosureSHA256, oldMapping.source.sourceClosureSHA256)
        XCTAssertEqual(mapping.source.generationID, oldMapping.source.generationID)
        XCTAssertEqual(mapping.source.rootDevice, oldMapping.source.rootDevice)
        XCTAssertEqual(mapping.source.rootInode, oldMapping.source.rootInode)
        XCTAssertEqual(mapping.source.writerRevision.revision, oldMapping.source.writerRevision.revision)
        XCTAssertEqual(mapping.source.writerRevision.entityRevisions, oldMapping.source.writerRevision.entityRevisions)
        XCTAssertNotEqual(mapping.source.writerRevision.writerInstanceID, oldMapping.source.writerRevision.writerInstanceID)
        XCTAssertNotEqual(mapping.source.uiGenerationToken, oldMapping.source.uiGenerationToken)
        XCTAssertEqual(try fixture.preferences.readAppLockSettingSnapshot(), repaired.settingWrite.successor)
    }

    func testNotificationControlPersistsBeforeProjectionAndCompletesAfterPhysicalReopen() throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.remove() }
        let policy = try fixture.policy(), operation = UUID()
        let journal = try fixture.journal(policy, operation: operation, disposition: .enablingPrepared)
        let plan = try fixture.plan(policy, operation: operation)
        let owner = try fixture.owner()
        let prepared = try owner.prepareControl(journal: journal, priorReminderPolicy: policy,
            settingWrite: plan, expectedPredecessor: nil)
        let originalBytes = try Data(contentsOf: fixture.recordURL)
        XCTAssertEqual(prepared.journal, journal)
        XCTAssertEqual(try CompatibilityCanonicalV1.encode(prepared.journal), try CompatibilityCanonicalV1.encode(journal))
        XCTAssertThrowsError(try owner.completeSetting(expected: prepared))
        XCTAssertEqual(try Data(contentsOf: fixture.recordURL), originalBytes)
        XCTAssertNil(try fixture.preferences.readAppLockSettingSnapshot().storedEnvelope)
        let reopened = try fixture.owner()
        XCTAssertEqual(try reopened.loadControl(), prepared)
        let interrupted = try fixture.journal(policy, operation: operation, disposition: .interruptedRecoveryRequired)
        let recovering = try reopened.recordJournal(interrupted, expected: prepared)
        XCTAssertThrowsError(try reopened.completeSetting(expected: recovering))
        let applied = try fixture.journal(policy, operation: operation, disposition: .genericProjectionApplied)
        let ready = try reopened.recordJournal(applied, expected: recovering)
        XCTAssertEqual(ready.priorReminderPolicy, policy)
        XCTAssertEqual(ready.settingWrite, plan)
        XCTAssertEqual(ready.phase, .prepared)
        XCTAssertThrowsError(try reopened.recordJournal(journal, expected: ready))
        let committed = try reopened.completeSetting(expected: ready)
        XCTAssertEqual(committed.phase, .settingCommitted)
        XCTAssertEqual(try fixture.preferences.readAppLockSettingSnapshot(), plan.successor)
        XCTAssertEqual(try fixture.owner().completeSetting(expected: ready), committed)
        XCTAssertEqual(try fixture.preferences.readStoredReminderPolicy(), policy)
    }

    func testNotificationControlRecoversPreparedRecordAfterPreferenceWriteInterruption() throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.remove() }
        let policy = try fixture.policy(), operation = UUID()
        let owner = try fixture.owner(.afterPreferenceWrite)
        let plan = try fixture.plan(policy, operation: operation)
        let prepared = try owner.prepareControl(journal: fixture.journal(policy, operation: operation,
            disposition: .genericProjectionAdopted), priorReminderPolicy: policy,
            settingWrite: plan, expectedPredecessor: nil)
        let originalBytes = try Data(contentsOf: fixture.recordURL)
        XCTAssertThrowsError(try owner.completeSetting(expected: prepared))
        XCTAssertEqual(try Data(contentsOf: fixture.recordURL), originalBytes)
        XCTAssertEqual(try fixture.preferences.readAppLockSettingSnapshot(), plan.successor)
        let reopened = try fixture.owner()
        XCTAssertEqual(try reopened.loadControl(), prepared)
        let completed = try reopened.completeSetting(expected: prepared)
        XCTAssertEqual(completed.phase, .settingCommitted)
        let completedBytes = try Data(contentsOf: fixture.recordURL)
        XCTAssertEqual(try reopened.completeSetting(expected: prepared), completed)
        XCTAssertEqual(try Data(contentsOf: fixture.recordURL), completedBytes)
    }

    func testNotificationControlTwoOwnersRejectChangedPredecessorsAndOperationSubjects() throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.remove() }
        let policy = try fixture.policy(), firstID = UUID(), secondID = UUID()
        let first = try fixture.owner(), second = try fixture.owner()
        let firstPlan = try fixture.plan(policy, operation: firstID)
        let secondPlan = try fixture.plan(policy, operation: secondID)
        let prepared = try first.prepareControl(journal: fixture.journal(policy, operation: firstID,
            disposition: .enablingPrepared), priorReminderPolicy: policy,
            settingWrite: firstPlan, expectedPredecessor: nil)
        let bytes = try Data(contentsOf: fixture.recordURL)
        XCTAssertThrowsError(try second.prepareControl(journal: fixture.journal(policy, operation: secondID,
            disposition: .enablingPrepared), priorReminderPolicy: policy,
            settingWrite: secondPlan, expectedPredecessor: nil))
        XCTAssertThrowsError(try second.prepareControl(journal: fixture.journal(policy, operation: secondID,
            disposition: .enablingPrepared), priorReminderPolicy: policy,
            settingWrite: secondPlan, expectedPredecessor: prepared))
        XCTAssertThrowsError(try first.recordJournal(fixture.journal(policy, operation: secondID,
            disposition: .genericProjectionApplied), expected: prepared))
        XCTAssertEqual(try Data(contentsOf: fixture.recordURL), bytes)
        XCTAssertNil(try fixture.preferences.readAppLockSettingSnapshot().storedEnvelope)
    }

    func testNotificationControlCompletedReplayRejectsPreferenceResetAndPostEraseABA() throws {
        for mode in 0..<4 {
            let fixture = try C16NotificationControlFixture()
            defer { fixture.remove() }
            let policy = try fixture.policy(), operation = UUID()
            let owner = try fixture.owner()
            let prepared = try owner.prepareControl(journal: fixture.journal(policy, operation: operation,
                disposition: .genericProjectionApplied), priorReminderPolicy: policy,
                settingWrite: fixture.plan(policy, operation: operation), expectedPredecessor: nil)
            _ = try owner.completeSetting(expected: prepared)
            if mode == 0 {
                let descriptor = try SettingsRegistryV1.current().descriptor(for: DeviceLocalAppLockSettingV1.key)
                try fixture.preferences.writeCanonicalValue(CompatibilityCanonicalV1.encode(true),
                    descriptor: descriptor, operationID: UUID())
            } else if mode == 1 {
                _ = try fixture.preferences.resetReminderPolicy(expected: policy, operationID: UUID())
            } else {
                try fixture.preferences.preparePreferencesForCompletedErase(operationID: UUID(),
                    persistentDomainName: fixture.suiteName)
                if mode == 3 {
                    XCTAssertNotEqual(try fixture.preferences.readReminderPolicy().instanceID, policy.instanceID)
                }
            }
            let bytes = try Data(contentsOf: fixture.recordURL)
            let defaultsBefore = fixture.defaults.persistentDomain(forName: fixture.suiteName) as NSDictionary?
            XCTAssertThrowsError(try fixture.owner().completeSetting(expected: prepared))
            XCTAssertEqual(try Data(contentsOf: fixture.recordURL), bytes)
            XCTAssertEqual(fixture.defaults.persistentDomain(forName: fixture.suiteName) as NSDictionary?, defaultsBefore)
        }
    }

    func testNotificationControlDisableRetainsHistoricalDetailWithoutRestoringConsent() throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.remove() }
        let policy = try fixture.policy(), enableID = UUID()
        let owner = try fixture.owner()
        let enabling = try owner.prepareControl(journal: fixture.journal(policy, operation: enableID,
            disposition: .genericProjectionApplied), priorReminderPolicy: policy,
            settingWrite: fixture.plan(policy, operation: enableID), expectedPredecessor: nil)
        let enabled = try owner.completeSetting(expected: enabling)
        let current = try fixture.preferences.updateReminderPolicy(expected: policy, isEnabled: false,
            detail: .generic, operationID: UUID())
        let disableID = UUID()
        let disablePlan = try fixture.plan(current, operation: disableID, enabled: false)
        let rebuilt = try fixture.journal(policy, operation: disableID, disposition: .priorPolicyRebuilt, enabled: false)
        XCTAssertThrowsError(try owner.prepareControl(journal: rebuilt, priorReminderPolicy: policy,
            settingWrite: disablePlan, expectedPredecessor: enabled))
        let disabling = try owner.prepareControl(journal: fixture.journal(policy, operation: disableID,
            disposition: .disablingPrepared, enabled: false), priorReminderPolicy: policy,
            settingWrite: disablePlan, expectedPredecessor: enabled)
        XCTAssertThrowsError(try owner.recordJournal(rebuilt, expected: disabling))
        let disabled = try owner.completeSetting(expected: disabling)
        let complete = try owner.recordJournal(rebuilt, expected: disabled)
        XCTAssertEqual(complete.priorReminderPolicy.detail, .details)
        XCTAssertEqual(complete.settingWrite.expectedReminderPolicy, current)
        XCTAssertEqual(try fixture.preferences.readStoredReminderPolicy(), current)
        XCTAssertFalse(try XCTUnwrap(fixture.preferences.readStoredReminderPolicy()).isEnabled)
        XCTAssertEqual(try fixture.preferences.readAppLockSettingSnapshot().setting,
            DeviceLocalAppLockSettingV1(isEnabled: false))
    }

    func testNotificationControlRejectsCorruptUnknownOversizedAndNonregularFilesWithoutRepair() throws {
        for mode in 0..<6 {
            let fixture = try C16NotificationControlFixture()
            defer { fixture.remove() }
            let policy = try fixture.policy(), operation = UUID(), owner = try fixture.owner()
            _ = try owner.prepareControl(journal: fixture.journal(policy, operation: operation,
                disposition: .enablingPrepared), priorReminderPolicy: policy,
                settingWrite: fixture.plan(policy, operation: operation), expectedPredecessor: nil)
            let original = try Data(contentsOf: fixture.recordURL)
            if mode < 4 {
                let hostile: Data
                if mode == 0 { hostile = Data("not-json".utf8) }
                else if mode == 3 { hostile = Data(repeating: 32, count: AppLockNotificationControlStoreV1.maximumRecordBytes + 1) }
                else {
                    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
                    object[mode == 1 ? "unknownAuthority" : "schemaVersion"] = mode == 1 ? 1 : 2
                    hostile = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                }
                try hostile.write(to: fixture.recordURL)
                try ProtectedFilePolicyV1.applyAndVerify(.journal, at: fixture.recordURL)
                XCTAssertThrowsError(try owner.loadControl())
                XCTAssertEqual(try Data(contentsOf: fixture.recordURL), hostile)
            } else if mode == 4 {
                let alias = fixture.controlRoot.appendingPathComponent("foreign-link")
                XCTAssertEqual(Darwin.link(fixture.recordURL.path, alias.path), 0)
                XCTAssertThrowsError(try owner.loadControl())
                XCTAssertEqual(try Data(contentsOf: alias), original)
            } else {
                try FileManager.default.removeItem(at: fixture.recordURL)
                try FileManager.default.createDirectory(at: fixture.recordURL, withIntermediateDirectories: false)
                XCTAssertThrowsError(try owner.loadControl())
                XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.recordURL.path))
            }
            XCTAssertNil(try fixture.preferences.readAppLockSettingSnapshot().storedEnvelope)
        }
    }

    func testNotificationControlRejectsReplacedControlAndOperationsRootsBeforeSettingWrite() throws {
        for replaceOperations in [false, true] {
            let fixture = try C16NotificationControlFixture()
            defer { fixture.remove() }
            let policy = try fixture.policy(), operation = UUID(), owner = try fixture.owner()
            let prepared = try owner.prepareControl(journal: fixture.journal(policy, operation: operation,
                disposition: .genericProjectionApplied), priorReminderPolicy: policy,
                settingWrite: fixture.plan(policy, operation: operation), expectedPredecessor: nil)
            let original = try Data(contentsOf: fixture.recordURL)
            let target = replaceOperations ? fixture.controlRoot.deletingLastPathComponent() : fixture.controlRoot
            let held = fixture.support.appendingPathComponent("retired-control")
            try FileManager.default.moveItem(at: target, to: held)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: target)
            XCTAssertThrowsError(try owner.completeSetting(expected: prepared))
            XCTAssertNil(try fixture.preferences.readAppLockSettingSnapshot().storedEnvelope)
            let retained = (replaceOperations ? held.appendingPathComponent(AppLockNotificationControlStoreV1.rootName) : held)
                .appendingPathComponent(AppLockNotificationControlStoreV1.recordName)
            XCTAssertEqual(try Data(contentsOf: retained), original)
        }
    }

    func testNotificationControlRejectsDivergentPendingPublicationBeforePreferenceEffect() throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.remove() }
        let policy = try fixture.policy(), operation = UUID(), owner = try fixture.owner()
        let prepared = try owner.prepareControl(journal: fixture.journal(policy, operation: operation,
            disposition: .genericProjectionApplied), priorReminderPolicy: policy,
            settingWrite: fixture.plan(policy, operation: operation), expectedPredecessor: nil)
        let pendingURL = fixture.controlRoot.appendingPathComponent(AppLockNotificationControlStoreV1.pendingName)
        let hostile = Data("unknown interrupted bytes".utf8)
        try hostile.write(to: pendingURL)
        try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: pendingURL)
        XCTAssertThrowsError(try owner.completeSetting(expected: prepared))
        XCTAssertEqual(try owner.loadControl(), prepared)
        XCTAssertNil(try fixture.preferences.readAppLockSettingSnapshot().storedEnvelope)
        XCTAssertEqual(try Data(contentsOf: pendingURL), hostile)
    }

    func testNotificationControlReopensAndAdoptsExactPendingFileAfterPreSyncInterruption() throws {
        let fixture = try C16NotificationControlFixture()
        defer { fixture.remove() }
        let policy = try fixture.policy(), operation = UUID()
        let journal = try fixture.journal(policy, operation: operation, disposition: .genericProjectionApplied)
        let plan = try fixture.plan(policy, operation: operation)
        let interrupted = try fixture.owner(.afterPendingWriteBeforeSync)
        XCTAssertThrowsError(try interrupted.prepareControl(journal: journal, priorReminderPolicy: policy,
            settingWrite: plan, expectedPredecessor: nil))
        XCTAssertNil(try interrupted.loadControl())
        XCTAssertNil(try fixture.preferences.readAppLockSettingSnapshot().storedEnvelope)
        let pendingURL = fixture.controlRoot.appendingPathComponent(AppLockNotificationControlStoreV1.pendingName)
        var pending = stat()
        XCTAssertEqual(Darwin.lstat(pendingURL.path, &pending), 0)
        let pendingBytes = try Data(contentsOf: pendingURL)
        let reopened = try fixture.owner()
        let prepared = try reopened.prepareControl(journal: journal, priorReminderPolicy: policy,
            settingWrite: plan, expectedPredecessor: nil)
        var published = stat()
        XCTAssertEqual(Darwin.lstat(fixture.recordURL.path, &published), 0)
        XCTAssertEqual(published.st_ino, pending.st_ino)
        XCTAssertEqual(published.st_dev, pending.st_dev)
        XCTAssertEqual(try Data(contentsOf: fixture.recordURL), pendingBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path))
        XCTAssertEqual(try reopened.completeSetting(expected: prepared).phase, .settingCommitted)
    }
}

@MainActor
final class V9_15AppLockLifecycleTests: XCTestCase {
    private func assertReadDenied(_ gate: AppAccessGateV1,
                                  token: AppAccessGateV1.ContentReadToken? = nil,
                                  surface: AppAccessContentReadSurfaceV1 = .search,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        do {
            if let token { try await gate.validateContentRead(token, for: surface) }
            else { _ = try await gate.beginContentRead(for: surface) }
            XCTFail("revoked or unavailable content read was admitted", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied, file: file, line: line)
        }
    }

    func testPhysicalIngressFactoryStreamsReopensAndRejectsChangedDuplicateBytes() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 3 * 1_048_576 + 37)
        defer { fixture.remove() }
        let request = fixture.request()
        let store = try ProductionCompositionRoot.makePreAuthenticationIngressStore(applicationSupportURL: fixture.support)
        let first = try await store.stageContentBlind(request, source: fixture.source)
        XCTAssertFalse(first.adoptedExistingEffect)
        XCTAssertEqual(first.intent.sha256, fixture.digest)
        XCTAssertEqual(try Data(contentsOf: fixture.payload(request)), fixture.bytes)
        let reopened = try ProductionCompositionRoot.makePreAuthenticationIngressStore(applicationSupportURL: fixture.support)
        let pending = try await reopened.pendingIntents()
        XCTAssertEqual(pending, [first.intent])
        let replay = try await reopened.stageContentBlind(request, source: fixture.source)
        XCTAssertTrue(replay.adoptedExistingEffect)
        XCTAssertEqual(replay.intent, first.intent)
        var altered = fixture.bytes
        altered[0] ^= 0xff
        try altered.write(to: fixture.source)
        do {
            _ = try await reopened.stageContentBlind(request, source: fixture.source)
            XCTFail("same intent accepted different source bytes")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: fixture.payload(request)), fixture.bytes)
        try fixture.bytes.write(to: fixture.source)
        let restored = try await reopened.stageContentBlind(request, source: fixture.source)
        XCTAssertEqual(restored.intent, first.intent)
    }

    func testPhysicalIngressCASAndRepeatedReadyRequireExactOwnedPayload() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let request = fixture.request()
        let first = try fixture.effects()
        let second = try fixture.effects()
        let staged = try await first.stageContentBlindEffect(request, source: fixture.source)
        let ready = try staged.advancing(to: .readyForAuthenticatedValidation)
        try await first.replacePendingIntentEffect(expected: staged, replacement: ready)
        do {
            try await second.replacePendingIntentEffect(expected: staged, replacement: ready)
            XCTFail("stale compare-and-swap accepted")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
        let wrapper = InjectedProtectedIngressStoreV1(effects: second)
        let repeated = try await wrapper.markReadyForAuthenticatedValidation(intentID: request.intentID)
        XCTAssertEqual(repeated, ready)
        try fixture.tamperPayloadPreservingMetadata(request)
        let metadataOnly = try await second.loadPendingIntentsEffect()
        XCTAssertEqual(metadataOnly, [ready], "fixture must retain metadata identity so payload hashing is tested")
        do {
            _ = try await wrapper.markReadyForAuthenticatedValidation(intentID: request.intentID)
            XCTFail("repeated ready skipped payload hash validation")
        } catch {}
    }

    func testPhysicalIngressPublicationInterruptionsConvergeAfterReopen() async throws {
        for boundary in [C16IngressMutationFailureInjectionV1.afterPrepare, .afterPublication, .afterPending] {
            let fixture = try C16PhysicalIngressFixture(byteCount: 64)
            defer { fixture.remove() }
            let request = fixture.request()
            let interrupted = try fixture.effects(failure: boundary)
            do {
                _ = try await interrupted.stageContentBlindEffect(request, source: fixture.source)
                XCTFail("publication interruption was not reached")
            } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
            let reopened = try fixture.effects()
            let settled = try await reopened.loadPendingIntentsEffect()
            XCTAssertEqual(settled.count, boundary == .afterPrepare ? 0 : 1)
            let recovered = try await reopened.stageContentBlindEffect(request, source: fixture.source)
            let pending = try await reopened.loadPendingIntentsEffect()
            XCTAssertEqual(pending, [recovered])
            XCTAssertEqual(recovered.sha256, fixture.digest)
            XCTAssertEqual(try Data(contentsOf: fixture.payload(request)), fixture.bytes)
            let duplicate = try await reopened.stageContentBlindEffect(request, source: fixture.source)
            XCTAssertEqual(duplicate, recovered)
        }
    }

    func testPhysicalIngressRemovalInterruptionsRetainExactTerminalReplay() async throws {
        for boundary in [C16IngressMutationFailureInjectionV1.afterRemovalPrepare, .afterRemovalEffect] {
            let fixture = try C16PhysicalIngressFixture(byteCount: 64)
            defer { fixture.remove() }
            let request = fixture.request()
            let original = try fixture.effects()
            let staged = try await original.stageContentBlindEffect(request, source: fixture.source)
            let ready = try staged.advancing(to: .readyForAuthenticatedValidation)
            try await original.replacePendingIntentEffect(expected: staged, replacement: ready)
            let interrupted = try fixture.effects(failure: boundary)
            do {
                try await interrupted.removePendingIntentEffect(expected: ready, disposition: .consumed)
                XCTFail("removal interruption was not reached")
            } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
            let reopened = try fixture.effects()
            let pending = try await reopened.loadPendingIntentsEffect()
            XCTAssertTrue(pending.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).path))
            try await reopened.removePendingIntentEffect(expected: ready, disposition: .consumed)
            do {
                try await reopened.removePendingIntentEffect(expected: ready, disposition: .erased)
                XCTFail("terminal receipt accepted a different disposition")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
        }
    }

    func testPhysicalIngressPartialPreparedDeletionPreservesUnrelatedTombstoneFile() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let request = fixture.request()
        let initial = try await fixture.effects().stageContentBlindEffect(request, source: fixture.source)
        do {
            try await fixture.effects(failure: .afterPreparedDirectoryFileDeletion)
                .removePendingIntentEffect(expected: initial, disposition: .erased)
            XCTFail("prepared-file deletion interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let tombstone = fixture.scratchRoot.appendingPathComponent(".deleting-import-" + request.intentID.uuidString.lowercased())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tombstone.path), ["opaque-data"])
        let unrelated = tombstone.appendingPathComponent("unrelated.bin")
        let unrelatedBytes = Data("preserve this later file".utf8)
        try unrelatedBytes.write(to: unrelated)
        try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: unrelated)
        let reopened = try fixture.effects()
        do {
            try await reopened.removePendingIntentEffect(expected: initial, disposition: .erased)
            XCTFail("an unrelated tombstone child was accepted for deletion")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
        XCTAssertEqual(try Data(contentsOf: unrelated), unrelatedBytes)
        XCTAssertEqual(try Data(contentsOf: tombstone.appendingPathComponent("opaque-data")), fixture.bytes)
        try FileManager.default.removeItem(at: unrelated)
        try await reopened.removePendingIntentEffect(expected: initial, disposition: .erased)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tombstone.path))
        let pending = try await reopened.loadPendingIntentsEffect()
        XCTAssertTrue(pending.isEmpty)
        try await reopened.removePendingIntentEffect(expected: initial, disposition: .erased)
    }

    func testPhysicalIngressEraseRetryPreservesLaterIntentAndReportsNonemptyReadback() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let original = try fixture.effects()
        let firstRequest = fixture.request()
        _ = try await original.stageContentBlindEffect(firstRequest, source: fixture.source)
        let operationID = UUID()
        let interrupted = try fixture.effects(failure: .afterErasePrepare)
        do {
            try await interrupted.erasePendingIntentsEffect(operationID: operationID)
            XCTFail("erase snapshot interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let laterRequest = fixture.request()
        let later = try await original.stageContentBlindEffect(laterRequest, source: fixture.source)
        let reopened = try fixture.effects()
        try await reopened.erasePendingIntentsEffect(operationID: operationID)
        let pending = try await reopened.loadPendingIntentsEffect()
        XCTAssertEqual(pending, [later])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(firstRequest).path))
        XCTAssertEqual(try Data(contentsOf: fixture.payload(laterRequest)), fixture.bytes)
        let wrapper = InjectedProtectedIngressStoreV1(effects: reopened)
        do {
            try await wrapper.eraseAllProtectedIngress(operationID: operationID)
            XCTFail("old erase snapshot falsely claimed later ingress was gone")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
        try await wrapper.eraseAllProtectedIngress(operationID: UUID())
        let erased = try await wrapper.pendingIntents()
        XCTAssertTrue(erased.isEmpty)
    }

    func testPhysicalIngressEraseIncludesOriginalUnpublishedCopiesAndPreservesLaterIntent() async throws {
        for boundary in [C16IngressMutationFailureInjectionV1.afterPrepare, .afterClaim, .afterOpaqueCopy] {
            let fixture = try C16PhysicalIngressFixture(byteCount: 64)
            defer { fixture.remove() }
            let request = fixture.request()
            let interruptedStage = try fixture.effects(failure: boundary)
            do {
                _ = try await interruptedStage.stageContentBlindEffect(request, source: fixture.source)
                XCTFail("unpublished stage boundary was not reached")
            } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
            let original = try fixture.effects()
            let before = try await original.loadPendingIntentsEffect()
            XCTAssertTrue(before.isEmpty)
            XCTAssertEqual(FileManager.default.fileExists(atPath: fixture.payload(request).path), boundary == .afterOpaqueCopy)
            let operationID = UUID()
            let interruptedErase = try fixture.effects(failure: .afterErasePrepare)
            do {
                try await interruptedErase.erasePendingIntentsEffect(operationID: operationID)
                XCTFail("unfinished target was not frozen before erase")
            } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
            let laterRequest = fixture.request()
            let later = try await original.stageContentBlindEffect(laterRequest, source: fixture.source)
            let reopened = try fixture.effects()
            try await reopened.erasePendingIntentsEffect(operationID: operationID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).deletingLastPathComponent().path))
            let after = try await reopened.loadPendingIntentsEffect()
            XCTAssertEqual(after, [later])
            XCTAssertEqual(try Data(contentsOf: fixture.payload(laterRequest)), fixture.bytes)
            try await reopened.erasePendingIntentsEffect(operationID: operationID)
            do {
                _ = try await reopened.stageContentBlindEffect(request, source: fixture.source)
                XCTFail("aborted intent identifier was reused")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .invalidTransition) }
        }
    }

    func testPhysicalIngressUnpublishedEraseReopensAfterRemovalBeforeTerminalWrite() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let request = fixture.request()
        let interruptedStage = try fixture.effects(failure: .afterOpaqueCopy)
        do {
            _ = try await interruptedStage.stageContentBlindEffect(request, source: fixture.source)
            XCTFail("copy interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let operationID = UUID()
        let interruptedErase = try fixture.effects(failure: .afterUnpublishedRemoval)
        do {
            try await interruptedErase.erasePendingIntentsEffect(operationID: operationID)
            XCTFail("deletion-before-terminal interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).path))
        let reopened = try fixture.effects()
        do {
            _ = try await reopened.loadPendingIntentsEffect()
            XCTFail("missing unfinished directory was silently accepted before Erase recovery")
        } catch {}
        try await reopened.erasePendingIntentsEffect(operationID: operationID)
        let pending = try await reopened.loadPendingIntentsEffect()
        XCTAssertTrue(pending.isEmpty)
        // A later unclaimed entry at the old name is never part of this receipt.
        let laterDirectory = fixture.payload(request).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: laterDirectory, withIntermediateDirectories: false)
        let sentinel = laterDirectory.appendingPathComponent("later-owner")
        try Data("preserve".utf8).write(to: sentinel)
        try await reopened.erasePendingIntentsEffect(operationID: operationID)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("preserve".utf8))
    }

    func testPhysicalIngressRecognizesOnlyCompletedHygieneForExpiredPublication() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let request = fixture.request()
        let original = try fixture.effects()
        _ = try await original.stageContentBlindEffect(request, source: fixture.source)
        let future = fixture.now.addingTimeInterval(25 * 3_600)
        let reopened = try fixture.effects(at: future)
        let receipt = try await reopened.performBlindStartupHygieneEffect(now: future, operationID: UUID())
        XCTAssertFalse(receipt.contentRead)
        XCTAssertEqual(receipt.removedKnownOwnedCount, 1)
        let pending = try await reopened.loadPendingIntentsEffect()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).path))
    }

    func testPhysicalIngressScratchResetCompletesUnpublishedAndPublishedRemoval() async throws {
        for boundary in [C16IngressMutationFailureInjectionV1.afterClaim, .afterOpaqueCopy] {
            let fixture = try C16PhysicalIngressFixture(byteCount: 64)
            defer { fixture.remove() }
            let unfinished = fixture.request()
            do {
                _ = try await fixture.effects(failure: boundary).stageContentBlindEffect(unfinished, source: fixture.source)
                XCTFail("unfinished-copy interruption was not reached")
            } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
            let request = fixture.request()
            let effects = try fixture.effects()
            let published = try await effects.stageContentBlindEffect(request, source: fixture.source)
            do {
                try await fixture.effects(failure: .afterRemovalPrepare).removePendingIntentEffect(expected: published, disposition: .erased)
                XCTFail("removal preparation interruption was not reached")
            } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
            let scratch = try fixture.scratch()
            try await scratch.resetScratchData()
            let pending = try await fixture.effects().loadPendingIntentsEffect()
            XCTAssertTrue(pending.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.scratchRoot.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(unfinished).deletingLastPathComponent().path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).deletingLastPathComponent().path))
            try await effects.removePendingIntentEffect(expected: published, disposition: .erased)
            do {
                _ = try await fixture.effects().stageContentBlindEffect(unfinished, source: fixture.source)
                XCTFail("reset forgot the original aborted intent")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .invalidTransition) }
        }
    }

    func testPhysicalIngressScratchRecoveryRetainsLiveCopiesAndCountsExactExpiryBytes() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let published = fixture.request()
        _ = try await fixture.effects().stageContentBlindEffect(published, source: fixture.source)
        let unfinished = fixture.request()
        do {
            _ = try await fixture.effects(failure: .afterOpaqueCopy).stageContentBlindEffect(unfinished, source: fixture.source)
            XCTFail("opaque-copy interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let scratch = try fixture.scratch()
        let before = try await scratch.recoverScratchLeases()
        XCTAssertEqual(before.recoveredExpiredLeaseCount, 0)
        XCTAssertEqual(before.removedByteCount, 0)
        let ordinaryRequest = try ScratchDataLeaseRequestV1(leaseID: UUID(), purpose: .source, owner: .source,
            ownerOperationID: UUID(), requestedByteCount: 8, createdAt: fixture.now, expiresAt: fixture.now.addingTimeInterval(3 * 3_600))
        let ordinary = try await scratch.acquireScratchLease(ordinaryRequest)
        let ordinaryURL = try await scratch.writeScratchData(Data("ordinary".utf8), named: "source.bin", lease: ordinary)
        let expectedBytes = try fixture.leaseByteCount(published) + fixture.leaseByteCount(unfinished)
        let future = fixture.now.addingTimeInterval(2 * 3_600)
        let recovered = try await fixture.scratch(at: future).recoverScratchLeases()
        XCTAssertEqual(recovered.recoveredExpiredLeaseCount, 2)
        XCTAssertEqual(recovered.removedByteCount, expectedBytes)
        XCTAssertEqual(try Data(contentsOf: ordinaryURL), Data("ordinary".utf8))
        let pending = try await fixture.effects(at: future).loadPendingIntentsEffect()
        XCTAssertTrue(pending.isEmpty)
        let repeated = try await fixture.scratch(at: future).recoverScratchLeases()
        XCTAssertEqual(repeated.recoveredExpiredLeaseCount, 0)
        XCTAssertEqual(repeated.removedByteCount, 0)
    }

    func testPhysicalIngressScratchResetResumesOriginalInterruptedUnpublishedErase() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let request = fixture.request()
        do {
            _ = try await fixture.effects(failure: .afterOpaqueCopy).stageContentBlindEffect(request, source: fixture.source)
            XCTFail("opaque-copy interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let operationID = UUID()
        do {
            try await fixture.effects(failure: .afterUnpublishedRemoval).erasePendingIntentsEffect(operationID: operationID)
            XCTFail("unpublished deletion interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        try await fixture.scratch().resetScratchData()
        let effects = try fixture.effects()
        let pending = try await effects.loadPendingIntentsEffect()
        XCTAssertTrue(pending.isEmpty)
        try await effects.erasePendingIntentsEffect(operationID: operationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).deletingLastPathComponent().path))
    }

    func testPhysicalIngressScratchReleaseCompletesExactPendingTerminal() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let request = fixture.request()
        let effects = try fixture.effects()
        let published = try await effects.stageContentBlindEffect(request, source: fixture.source)
        let metadata = fixture.payload(request).deletingLastPathComponent().appendingPathComponent("lease.json")
        let lease = try JSONDecoder().decode(ScratchDataLeaseV1.self, from: Data(contentsOf: metadata))
        try await fixture.scratch().releaseScratchLease(lease, terminal: .cancelled)
        let pending = try await fixture.effects().loadPendingIntentsEffect()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.deletingLastPathComponent().path))
        try await effects.removePendingIntentEffect(expected: published, disposition: .erased)
        try await fixture.scratch().releaseScratchLease(lease, terminal: .cancelled)
    }

    func testPhysicalIngressScratchEraseReopensAfterControlDeletionInterruptions() async throws {
        for boundary in [C16IngressMutationFailureInjectionV1.none, .afterScratchControlErasePublication,
                         .afterScratchControlErasePrepare, .afterScratchControlEraseFile] {
            let fixture = try C16PhysicalIngressFixture(byteCount: 64)
            defer { fixture.remove() }
            _ = try await fixture.effects().stageContentBlindEffect(fixture.request(), source: fixture.source)
            _ = try await fixture.effects().stageContentBlindEffect(fixture.request(), source: fixture.source)
            let scratch = try fixture.scratch(failure: boundary)
            if boundary == .none {
                try await scratch.eraseScratchData()
            } else {
                do {
                    try await scratch.eraseScratchData()
                    XCTFail("control cleanup interruption was not reached")
                } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
                if boundary == .afterScratchControlErasePublication {
                    let marker = fixture.controlRoot.appendingPathComponent("scratch-erase.json")
                    var metadata = stat()
                    XCTAssertEqual(Darwin.lstat(marker.path, &metadata), 0)
                    XCTAssertEqual(metadata.st_nlink, 1)
                    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.controlRoot.path)
                        .contains(where: { $0.hasPrefix(".partial-") }))
                }
                do {
                    _ = try await fixture.effects().loadPendingIntentsEffect()
                    XCTFail("active scratch Erase marker admitted ingress")
                } catch {}
                try await fixture.scratch().eraseScratchData()
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.scratchRoot.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.controlRoot.path))
            let reopened = try ProductionCompositionRoot.makePreAuthenticationIngressStore(applicationSupportURL: fixture.support)
            let request = fixture.request()
            let receipt = try await reopened.stageContentBlind(request, source: fixture.source)
            let pending = try await reopened.pendingIntents()
            XCTAssertEqual(pending, [receipt.intent])
            XCTAssertEqual(try Data(contentsOf: fixture.payload(request)), fixture.bytes)
        }
    }

    func testPhysicalIngressScratchErasePreservesSubstitutedControlAndUnrelatedFiles() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        _ = try await fixture.effects().stageContentBlindEffect(fixture.request(), source: fixture.source)
        do {
            try await fixture.scratch(failure: .afterScratchControlErasePrepare).eraseScratchData()
            XCTFail("control cleanup interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let originalNames = try FileManager.default.contentsOfDirectory(atPath: fixture.controlRoot.path).sorted()
        let targetName = try XCTUnwrap(originalNames.first { $0 != "scratch-erase.json" })
        let target = fixture.controlRoot.appendingPathComponent(targetName)
        let bytes = try Data(contentsOf: target)
        try bytes.write(to: target, options: .atomic)
        do {
            try await fixture.scratch().eraseScratchData()
            XCTFail("substituted original control file was removed")
        } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.controlRoot.path).sorted(), originalNames)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.scratchRoot.path))
    }

    func testPhysicalIngressScratchErasePreservesLaterPartialPublicationFile() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        _ = try await fixture.effects().stageContentBlindEffect(fixture.request(), source: fixture.source)
        do {
            try await fixture.scratch(failure: .afterScratchControlErasePrepare).eraseScratchData()
            XCTFail("control cleanup interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let later = fixture.controlRoot.appendingPathComponent(".partial-" + UUID().uuidString.lowercased())
        try Data("later unrelated publication".utf8).write(to: later)
        try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: later)
        let before = try fixture.fileBytes(in: fixture.controlRoot)
        do {
            try await fixture.scratch().eraseScratchData()
            XCTFail("cleanup deleted a later partial file outside its original snapshot")
        } catch {}
        XCTAssertEqual(try fixture.fileBytes(in: fixture.controlRoot), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.scratchRoot.path))
        try FileManager.default.removeItem(at: later)
        try await fixture.scratch().eraseScratchData()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.controlRoot.path))
    }

    func testPhysicalIngressScratchErasePreservesLaterMarkerHardLink() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        _ = try await fixture.effects().stageContentBlindEffect(fixture.request(), source: fixture.source)
        do {
            try await fixture.scratch(failure: .afterScratchControlErasePublication).eraseScratchData()
            XCTFail("atomic marker publication interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let marker = fixture.controlRoot.appendingPathComponent("scratch-erase.json")
        let later = fixture.controlRoot.appendingPathComponent(".partial-" + UUID().uuidString.lowercased())
        try FileManager.default.linkItem(at: marker, to: later)
        let before = try fixture.fileBytes(in: fixture.controlRoot)
        do {
            try await fixture.scratch().eraseScratchData()
            XCTFail("later marker hard link was mistaken for an owned publication")
        } catch {}
        XCTAssertEqual(try fixture.fileBytes(in: fixture.controlRoot), before)
        var metadata = stat()
        XCTAssertEqual(Darwin.lstat(marker.path, &metadata), 0)
        XCTAssertEqual(metadata.st_nlink, 2)
        try FileManager.default.removeItem(at: later)
        try await fixture.scratch().eraseScratchData()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.controlRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.scratchRoot.path))
    }

    func testPhysicalIngressGenericRecoveryAndResetPreserveInterruptedHygieneSnapshot() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let old = fixture.now.addingTimeInterval(-3 * 86_400)
        let scratch = try fixture.scratch(at: old)
        let request = try ScratchDataLeaseRequestV1(leaseID: UUID(), purpose: .source, owner: .source,
            ownerOperationID: UUID(), requestedByteCount: 8, createdAt: old, expiresAt: old.addingTimeInterval(3_600))
        let lease = try await scratch.acquireScratchLease(request)
        let payload = try await scratch.writeScratchData(Data("ordinary".utf8), named: "a.bin", lease: lease)
        let directory = payload.deletingLastPathComponent()
        try fixture.ageFiles(in: directory, to: old)
        let operationID = UUID()
        do {
            _ = try fixture.scratch(failure: .afterPreparedDirectoryFileDeletion)
                .reconcileProtectedIngressHygiene(now: fixture.now, operationID: operationID)
            XCTFail("hygiene did not interrupt after its first actual file deletion")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let tombstone = fixture.scratchRoot.appendingPathComponent(".deleting-" + directory.lastPathComponent)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tombstone.path), ["lease.json"])
        let later = tombstone.appendingPathComponent("unrelated.bin")
        try Data("preserve later tombstone child".utf8).write(to: later)
        try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: later)
        let before = try fixture.fileBytes(in: tombstone)
        do {
            _ = try await fixture.scratch().recoverScratchLeases()
            XCTFail("generic recovery bypassed the original hygiene snapshot")
        } catch {}
        XCTAssertEqual(try fixture.fileBytes(in: tombstone), before)
        do {
            try await fixture.scratch().resetScratchData()
            XCTFail("generic reset bypassed the original hygiene snapshot")
        } catch {}
        XCTAssertEqual(try fixture.fileBytes(in: tombstone), before)
        try FileManager.default.removeItem(at: later)
        let receipt = try fixture.scratch().reconcileProtectedIngressHygiene(now: fixture.now, operationID: operationID)
        XCTAssertEqual(receipt.removedKnownOwnedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tombstone.path))
        XCTAssertEqual(try fixture.scratch().reconcileProtectedIngressHygiene(now: fixture.now, operationID: operationID), receipt)
    }

    func testPhysicalIngressFIFORejectsPromptlyWithoutHoldingScratchFence() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let fifo = fixture.root.appendingPathComponent("external.fifo")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, mode_t(0o600)), 0)
        let effects = try fixture.effects()
        let request = fixture.request()
        let finished = expectation(description: "nonregular source rejects without waiting for a writer")
        let staging = Task.detached {
            defer { finished.fulfill() }
            do {
                _ = try await effects.stageContentBlindEffect(request, source: fifo)
                return false
            } catch { return true }
        }
        await fulfillment(of: [finished], timeout: 2)
        // If blocking open regresses, release its reader after recording the
        // timeout so this test cannot strand the process-wide scratch fence.
        let writer = Darwin.open(fifo.path, O_RDWR | O_NONBLOCK | O_NOFOLLOW)
        defer { if writer >= 0 { _ = Darwin.close(writer) } }
        let rejected = await staging.value
        XCTAssertTrue(rejected)
        let pending = try await effects.loadPendingIntentsEffect()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.scratchRoot.path).isEmpty)
        let ordinary = try ScratchDataLeaseRequestV1(leaseID: UUID(), purpose: .source, owner: .source,
            ownerOperationID: UUID(), requestedByteCount: 8, createdAt: fixture.now, expiresAt: fixture.now.addingTimeInterval(3_600))
        let scratch = try fixture.scratch()
        let lease = try await scratch.acquireScratchLease(ordinary)
        let payload = try await scratch.writeScratchData(Data("ordinary".utf8), named: "source.bin", lease: lease)
        XCTAssertEqual(try Data(contentsOf: payload), Data("ordinary".utf8))
        try await scratch.releaseScratchLease(lease, terminal: .cancelled)
    }

    func testPhysicalIngressStaleCachedLeaseCannotWriteOrReleaseLaterReusedIngressID() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let old = fixture.now.addingTimeInterval(-3 * 86_400)
        let storeA = try fixture.scratch(at: old)
        let oldRequest = try ScratchDataLeaseRequestV1(leaseID: UUID(), purpose: .importData, owner: .importData,
            ownerOperationID: UUID(), requestedByteCount: 1_024, createdAt: old, expiresAt: old.addingTimeInterval(3_600))
        let oldLease = try await storeA.acquireScratchLease(oldRequest)
        let oldPayload = try await storeA.writeScratchData(Data("ordinary".utf8), named: "source.bin", lease: oldLease)
        try fixture.ageFiles(in: oldPayload.deletingLastPathComponent(), to: old)
        let hygiene = try fixture.scratch().reconcileProtectedIngressHygiene(now: fixture.now, operationID: UUID())
        XCTAssertEqual(hygiene.removedKnownOwnedCount, 1)
        let newRequest = ProtectedIngressStageRequestV1(intentID: oldRequest.leaseID, operationID: UUID(), kind: .document,
            byteCount: UInt64(fixture.bytes.count), receivedAt: fixture.now, expiresAt: fixture.now.addingTimeInterval(3_600))
        let effects = try fixture.effects()
        let newIntent = try await effects.stageContentBlindEffect(newRequest, source: fixture.source)
        let directory = fixture.payload(newRequest).deletingLastPathComponent()
        let before = try fixture.fileBytes(in: directory)
        do {
            _ = try await storeA.writeScratchData(Data([0x01]), named: "later.bin", lease: oldLease)
            XCTFail("stale active lease wrote into a later ingress owner's directory")
        } catch {}
        XCTAssertEqual(try fixture.fileBytes(in: directory), before)
        do {
            try await storeA.releaseScratchLease(oldLease, terminal: .cancelled)
            XCTFail("stale active lease released a later ingress owner at the reused ID")
        } catch {}
        XCTAssertEqual(try fixture.fileBytes(in: directory), before)
        let pending = try await effects.loadPendingIntentsEffect()
        XCTAssertEqual(pending, [newIntent])
        let newLease = try JSONDecoder().decode(ScratchDataLeaseV1.self,
            from: Data(contentsOf: directory.appendingPathComponent("lease.json")))
        try await fixture.scratch().releaseScratchLease(newLease, terminal: .cancelled)
        let after = try await effects.loadPendingIntentsEffect()
        XCTAssertTrue(after.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testPhysicalIngressRejectsUnsupportedSizeAndCorruptControlWithoutLosingBytes() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let effects = try fixture.effects()
        for (kind, byteCount) in [(LockedIngressKindV1.appIntent, UInt64(64)), (.document, 65)] {
            let request = ProtectedIngressStageRequestV1(intentID: UUID(), operationID: UUID(), kind: kind,
                byteCount: byteCount, receivedAt: fixture.now, expiresAt: fixture.now.addingTimeInterval(3_600))
            do {
                _ = try await effects.stageContentBlindEffect(request, source: fixture.source)
                XCTFail("unsupported ingress or false byte count was admitted")
            } catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).deletingLastPathComponent().path))
        }
        let request = fixture.request()
        _ = try await effects.stageContentBlindEffect(request, source: fixture.source)
        let unknown = fixture.controlRoot.appendingPathComponent("unknown.json")
        try Data("preserve unknown".utf8).write(to: unknown)
        do {
            _ = try await fixture.effects().loadPendingIntentsEffect()
            XCTFail("unknown control entry was silently ignored")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: unknown), Data("preserve unknown".utf8))
        try FileManager.default.removeItem(at: unknown)
        let prepare = fixture.controlRoot.appendingPathComponent("ingress-" + request.intentID.uuidString.lowercased() + ".prepare.json")
        try Data("{".utf8).write(to: prepare)
        do {
            _ = try await fixture.effects().loadPendingIntentsEffect()
            XCTFail("corrupt preparation was admitted")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: fixture.payload(request)), fixture.bytes)
        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.bytes)
    }

    func testPhysicalIngressUnfinishedPreparationsEnforceThe128IntentLimit() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let effects = try fixture.effects(failure: .afterPrepare)
        for _ in 0..<128 {
            do {
                _ = try await effects.stageContentBlindEffect(fixture.request(), source: fixture.source)
                XCTFail("preparation interruption was not reached")
            } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        }
        let rejected = fixture.request()
        do {
            _ = try await effects.stageContentBlindEffect(rejected, source: fixture.source)
            XCTFail("129th unfinished intent was admitted")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .ingressLimitExceeded) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(rejected).deletingLastPathComponent().path))
        try await fixture.scratch().resetScratchData()
        let fresh = try fixture.effects()
        let admitted = try await fresh.stageContentBlindEffect(rejected, source: fixture.source)
        let pending = try await fresh.loadPendingIntentsEffect()
        XCTAssertEqual(pending, [admitted])
    }

    func testPhysicalIngressFullPublishedCapacityErasesThroughOriginalBoundedSnapshot() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 1)
        defer { fixture.remove() }
        let effects = try fixture.effects()
        var requests: [ProtectedIngressStageRequestV1] = []
        for index in 0..<128 {
            let request = fixture.request()
            let staged = try await effects.stageContentBlindEffect(request, source: fixture.source)
            if index.isMultiple(of: 2) {
                let ready = try staged.advancing(to: .readyForAuthenticatedValidation)
                try await effects.replacePendingIntentEffect(expected: staged, replacement: ready)
            }
            requests.append(request)
        }
        let before = try await effects.loadPendingIntentsEffect()
        XCTAssertEqual(before.count, 128)
        do {
            _ = try await effects.stageContentBlindEffect(fixture.request(), source: fixture.source)
            XCTFail("129th published intent was admitted")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .ingressLimitExceeded) }
        let operationID = UUID()
        do {
            try await fixture.effects(failure: .afterErasePrepare).erasePendingIntentsEffect(operationID: operationID)
            XCTFail("full-population Erase preparation interruption was not reached")
        } catch { XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision) }
        let reopened = try fixture.effects()
        let retained = try await reopened.loadPendingIntentsEffect()
        XCTAssertEqual(retained, before)
        for request in requests { XCTAssertEqual(try Data(contentsOf: fixture.payload(request)), fixture.bytes) }
        try await reopened.erasePendingIntentsEffect(operationID: operationID)
        let after = try await reopened.loadPendingIntentsEffect()
        XCTAssertTrue(after.isEmpty)
        for request in requests {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.payload(request).deletingLastPathComponent().path))
        }
        let laterRequest = fixture.request()
        let later = try await reopened.stageContentBlindEffect(laterRequest, source: fixture.source)
        try await reopened.erasePendingIntentsEffect(operationID: operationID)
        let final = try await reopened.loadPendingIntentsEffect()
        XCTAssertEqual(final, [later])
        XCTAssertEqual(try Data(contentsOf: fixture.payload(laterRequest)), fixture.bytes)
    }

    func testPhysicalIngressAuthenticationResumeAndRelockUseRealPendingBytes() async throws {
        let fixture = try C16PhysicalIngressFixture(byteCount: 64)
        defer { fixture.remove() }
        let clock = C16PhysicalIngressClock(value: fixture.now)
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V915AuthenticationClient(outcomes: [.authenticated]), clock: clock,
            identifiers: V915IDs(values: [UUID(), UUID(), UUID()]))
        let store = try ProductionCompositionRoot.makePreAuthenticationIngressStore(applicationSupportURL: fixture.support)
        let coordinator = ProtectedIngressCoordinatorV1(gate: gate, store: store, clock: clock)
        let request = fixture.request()
        let staged = try await coordinator.stageWhileLocked(request, source: fixture.source)
        do {
            _ = try await coordinator.resumeAfterAuthentication()
            XCTFail("locked resume returned staged ingress")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let outcome = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(outcome, .authenticated)
        let ready = try await coordinator.resumeAfterAuthentication()
        XCTAssertEqual(ready, [try staged.intent.advancing(to: .readyForAuthenticatedValidation)])
        XCTAssertEqual(try Data(contentsOf: fixture.payload(request)), fixture.bytes)
        await gate.lock(reason: .returnedFromBackground)
        do {
            _ = try await coordinator.resumeAfterAuthentication()
            XCTFail("relocked resume returned ready ingress")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let reopened = try ProductionCompositionRoot.makePreAuthenticationIngressStore(applicationSupportURL: fixture.support)
        let pending = try await reopened.pendingIntents()
        XCTAssertEqual(pending, ready)
    }

    func testContentReadTokensBindOwnerSurfaceAndNeverAuthenticateOrConsumeIDs() async throws {
        let auth = V915AuthenticationClient(outcomes: [.authenticated])
        let gate = AppAccessGateV1(setting: .absentDisabled, authentication: auth,
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(701), Self.id(702)]))
        let token = try await gate.beginContentRead(for: .search)
        for _ in 0..<3 {
            try await gate.validateContentRead(token, for: .search)
            let fresh = try await gate.beginContentRead(for: .render)
            try await gate.validateContentRead(fresh, for: .render)
        }
        await assertReadDenied(gate, token: token, surface: .render)
        let other = AppAccessGateV1(setting: .absentDisabled, authentication: auth,
            clock: V915Clock(), identifiers: V915IDs(values: []))
        await assertReadDenied(other, token: token)
        for setting in [DeviceLocalAppLockSettingReadV1.value(.init(isEnabled: true)),
                        .corruptOrAmbiguous, .protectedDataUnavailable] {
            let locked = AppAccessGateV1(setting: setting, authentication: auth,
                clock: V915Clock(), identifiers: V915IDs(values: []))
            await assertReadDenied(locked)
            await assertReadDenied(locked, token: token)
        }
        let noAttempts = await auth.attempts
        XCTAssertTrue(noAttempts.isEmpty)
        let outcome = await gate.authenticate(trigger: .enableAppLock)
        XCTAssertEqual(outcome, .authenticated)
        let attempts = await auth.attempts
        XCTAssertEqual(attempts.map(\.attemptID), [Self.id(701)])
        let state = await gate.currentState()
        XCTAssertEqual(state, .unlockedForeground(sessionID: Self.id(702)))
        await assertReadDenied(gate, token: token)
        let authenticated = try await gate.beginContentRead(for: .search)
        try await gate.validateContentRead(authenticated, for: .search)
    }

    func testContentReadTokensRejectLockInactivityRecoverySettingAndEraseABA() async throws {
        let auth = V915AuthenticationClient(outcomes: [.authenticated, .authenticated, .authenticated])
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)), authentication: auth,
            clock: V915Clock(), identifiers: V915IDs(values: (710...715).map(Self.id)))
        let firstUnlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(firstUnlock, .authenticated)
        let token = try await gate.beginContentRead(for: .search)
        let beforeInactive = await gate.currentState()
        await gate.sceneBecameInactive()
        await assertReadDenied(gate)
        await assertReadDenied(gate, token: token)
        let covered = await gate.privacyCoverRequired()
        let duringInactive = await gate.currentState()
        XCTAssertTrue(covered)
        XCTAssertEqual(duringInactive, beforeInactive)
        await gate.sceneBecameActive()
        let afterActive = await gate.currentState()
        XCTAssertEqual(afterActive, beforeInactive)
        await assertReadDenied(gate, token: token)
        let beforeLock = try await gate.beginContentRead(for: .search)
        await gate.lock(reason: .returnedFromBackground)
        await assertReadDenied(gate)
        let secondUnlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(secondUnlock, .authenticated)
        await assertReadDenied(gate, token: beforeLock)
        let beforeConfiguration = try await gate.beginContentRead(for: .search)
        await gate.markConfigurationUnknown()
        await assertReadDenied(gate)
        let repair = await gate.authenticate(trigger: .repairConfiguration)
        XCTAssertEqual(repair, .authenticated)
        await assertReadDenied(gate)
        await assertReadDenied(gate, token: beforeConfiguration)
        let configurationToken = try await gate.configurationAuthenticationToken()
        try await gate.setEnabledAfterAuthenticated(false, configurationToken: configurationToken)
        await assertReadDenied(gate, token: beforeConfiguration)
        let beforeRecovery = try await gate.beginContentRead(for: .search)
        try await gate.markRecoveryComplete(enabled: false)
        await assertReadDenied(gate, token: beforeRecovery)
        let beforeErase = try await gate.beginContentRead(for: .search)
        await gate.eraseAccessState()
        await assertReadDenied(gate, token: beforeErase)
        let fresh = try await gate.beginContentRead(for: .search)
        try await gate.validateContentRead(fresh, for: .search)
        let attempts = await auth.attempts
        XCTAssertEqual(attempts.count, 3)
    }

    func testConfigurationRepairProofKeepsContentClosedAndRejectsForeignAndConsumedAuthority() async throws {
        let gate = AppAccessGateV1(
            setting: .corruptOrAmbiguous,
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(800), Self.id(801)])
        )
        do { _ = try await gate.configurationAuthenticationToken(); XCTFail("proof existed before authentication") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let outcome = await gate.authenticate(trigger: .repairConfiguration)
        XCTAssertEqual(outcome, .authenticated)
        let proof = try await gate.configurationAuthenticationToken()
        try await gate.validateConfigurationAuthentication(proof)
        let state = await gate.currentState()
        let covered = await gate.privacyCoverRequired()
        XCTAssertEqual(state, .configurationUnknownLocked)
        XCTAssertTrue(covered)
        await assertReadDenied(gate)
        do { _ = try await gate.requireContentAccess(for: .startupRecovery); XCTFail("repair proof opened startup content") }
        catch { XCTAssertEqual(error as? AppAccessContentReadFailureV1, .denied(surface: .startupRecovery, state: .configurationUnknownLocked)) }
        do { try await gate.setEnabledAfterAuthenticated(false); XCTFail("missing repair proof completed configuration") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        do { try await gate.markRecoveryComplete(enabled: true); XCTFail("public completion bypassed repair proof") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }

        // Deliberately reuse the same UUIDs: owner identity must still distinguish gates.
        let other = AppAccessGateV1(
            setting: .corruptOrAmbiguous,
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(800), Self.id(801)])
        )
        let otherOutcome = await other.authenticate(trigger: .repairConfiguration)
        XCTAssertEqual(otherOutcome, .authenticated)
        do { try await other.validateConfigurationAuthentication(proof); XCTFail("foreign repair proof validated") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        do { try await other.setEnabledAfterAuthenticated(false, configurationToken: proof); XCTFail("foreign repair proof completed configuration") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        await assertReadDenied(other)

        try await gate.setEnabledAfterAuthenticated(false, configurationToken: proof)
        let completed = await gate.currentState()
        let requiresRecovery = await gate.requiresConfigurationRecovery()
        XCTAssertEqual(completed, .disabled)
        XCTAssertFalse(requiresRecovery)
        do { try await gate.validateConfigurationAuthentication(proof); XCTFail("consumed repair proof validated") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        do { try await gate.setEnabledAfterAuthenticated(true, configurationToken: proof); XCTFail("consumed proof changed the completed setting") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        _ = try await gate.beginContentRead(for: .search)
    }

    func testConfigurationRepairProofExpiresAcrossEveryRevocationBoundary() async throws {
        for boundary in 0..<5 {
            let gate = AppAccessGateV1(
                setting: .corruptOrAmbiguous,
                authentication: V915AuthenticationClient(outcomes: [.authenticated, .authenticated]),
                clock: V915Clock(), identifiers: V915IDs(values: (810...813).map(Self.id))
            )
            let outcome = await gate.authenticate(trigger: .repairConfiguration)
            XCTAssertEqual(outcome, .authenticated)
            let proof = try await gate.configurationAuthenticationToken()
            switch boundary {
            case 0: await gate.lock(reason: .lockNow)
            case 1:
                await gate.sceneBecameInactive()
                await gate.sceneBecameActive()
            case 2: await gate.markConfigurationUnknown()
            case 3: await gate.eraseAccessState()
            default:
                let later = await gate.authenticate(trigger: .repairConfiguration)
                XCTAssertEqual(later, .authenticated)
                let current = try await gate.configurationAuthenticationToken()
                try await gate.validateConfigurationAuthentication(current)
            }
            do { try await gate.validateConfigurationAuthentication(proof); XCTFail("revoked proof survived boundary \(boundary)") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            if boundary < 4 {
                do { _ = try await gate.configurationAuthenticationToken(); XCTFail("getter revived a revoked proof") }
                catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            }
            do { try await gate.setEnabledAfterAuthenticated(false, configurationToken: proof); XCTFail("revoked proof completed after boundary \(boundary)") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            if boundary != 3 { await assertReadDenied(gate) }
        }
    }

    func testCancelledAndFailedConfigurationRepairCannotBecomeOrdinaryUnlock() async throws {
        for initial in [DeviceLocalAppLockSettingReadV1.corruptOrAmbiguous, .protectedDataUnavailable] {
            for failure in [LocalAuthenticationOutcomeV1.userCancelled, .authenticationFailed] {
                let auth = V915AuthenticationClient(outcomes: [failure, .authenticated])
                let gate = AppAccessGateV1(
                    setting: initial, authentication: auth,
                    clock: V915Clock(), identifiers: V915IDs(values: (820...824).map(Self.id))
                )
                let outcome = await gate.authenticate(trigger: .repairConfiguration)
                XCTAssertEqual(outcome, failure)
                await gate.lock(reason: .returnedFromBackground)
                let ordinary = await gate.authenticate(trigger: .unlock)
                XCTAssertEqual(ordinary, .interrupted)
                let attempts = await auth.attempts
                let unresolved = await gate.requiresConfigurationRecovery()
                XCTAssertEqual(attempts.count, 1)
                XCTAssertTrue(unresolved)
                await assertReadDenied(gate)
                do { _ = try await gate.configurationAuthenticationToken(); XCTFail("failed repair minted proof") }
                catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
                let repaired = await gate.authenticate(trigger: .repairConfiguration)
                XCTAssertEqual(repaired, .authenticated)
                let proof = try await gate.configurationAuthenticationToken()
                try await gate.setEnabledAfterAuthenticated(true, configurationToken: proof)
                try await gate.markRecoveryComplete(enabled: true)
                let completed = await gate.currentState()
                XCTAssertEqual(completed, .locked(reason: .coldLaunch))
                await assertReadDenied(gate)
            }
        }
    }

    func testCompletedNotificationJournalsRelaunchWithoutRecoveryEffectsOrAuthentication() async throws {
        let cases: [(Bool, AppLockNotificationPrivacyDispositionV1)] = [
            (true, .genericProjectionApplied), (true, .genericProjectionAdopted),
            (false, .priorPolicyRebuilt)
        ]
        for (enabled, disposition) in cases {
            let journal = try recoveryJournal(enabled: enabled, disposition: disposition)
            let effects = try recoveryEffects(journal: journal)
            let notifications = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
            let setting = V915SettingStore(value: .init(isEnabled: enabled))
            let auth = V915AuthenticationClient(outcomes: [])
            for _ in 0..<2 {
                let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
                    setting: setting, authentication: auth, ingressStore: V915IngressStore(),
                    notifications: notifications, clock: V915Clock(),
                    identifiers: V915IDs(values: (830...834).map(Self.id))
                )
                let gate = await lifecycle.accessGate()
                let state = await gate.currentState()
                XCTAssertEqual(state, enabled ? .locked(reason: .coldLaunch) : .disabled)
                let recovery = try await lifecycle.recoverAfterAuthentication()
                XCTAssertEqual(recovery, .noRecoveryRequired)
                let unchanged = await gate.currentState()
                XCTAssertEqual(unchanged, state)
            }
            let attempts = await auth.attempts
            let writes = await setting.writeEffectCount
            let publishes = await effects.publishCount
            let rebuilds = await effects.rebuildCount
            let retained = try await notifications.loadJournal()
            XCTAssertTrue(attempts.isEmpty)
            XCTAssertEqual(writes, 0)
            XCTAssertEqual(publishes, 0)
            XCTAssertEqual(rebuilds, 0)
            XCTAssertEqual(retained, journal)
        }
    }

    func testIncompleteMismatchedAndAbsentNotificationConfigurationStaysUnknown() async throws {
        let cases: [(DeviceLocalAppLockSettingReadV1, Bool, AppLockNotificationPrivacyDispositionV1)] = [
            (.value(.init(isEnabled: false)), true, .genericProjectionApplied),
            (.value(.init(isEnabled: true)), false, .priorPolicyRebuilt),
            (.value(.init(isEnabled: true)), true, .enablingPrepared),
            (.value(.init(isEnabled: false)), false, .disablingPrepared),
            (.absentDisabled, false, .priorPolicyRebuilt),
            (.corruptOrAmbiguous, false, .priorPolicyRebuilt),
            (.protectedDataUnavailable, true, .genericProjectionApplied)
        ]
        for (read, enabled, disposition) in cases {
            let journal = try recoveryJournal(enabled: enabled, disposition: disposition)
            let effects = try recoveryEffects(journal: journal)
            let auth = V915AuthenticationClient(outcomes: [])
            let setting = V915SettingStore(value: nil, readOverride: read)
            let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
                setting: setting, authentication: auth, ingressStore: V915IngressStore(),
                notifications: AppLockNotificationPrivacyCoordinatorV1(effects: effects),
                clock: V915Clock(), identifiers: V915IDs(values: [Self.id(840)])
            )
            let gate = await lifecycle.accessGate()
            let state = await gate.currentState()
            let unresolved = await gate.requiresConfigurationRecovery()
            XCTAssertEqual(state, .configurationUnknownLocked)
            XCTAssertTrue(unresolved)
            await assertReadDenied(gate)
            let attempts = await auth.attempts
            let writes = await setting.writeEffectCount
            XCTAssertTrue(attempts.isEmpty)
            XCTAssertEqual(writes, 0)
        }
    }

    func testUnresolvedStartupHygieneAndMissingJournalReturnHonestRecoveryHolds() async throws {
        let completed = try recoveryJournal(enabled: false, disposition: .priorPolicyRebuilt)
        let pending = try recoveryJournal(enabled: true, disposition: .enablingPrepared)
        let cases: [(DeviceLocalAppLockSettingReadV1, AppLockNotificationJournalV1?, Int)] = [
            (.value(.init(isEnabled: false)), nil, 1),
            (.value(.init(isEnabled: false)), completed, 1),
            (.value(.init(isEnabled: true)), pending, 1),
            (.corruptOrAmbiguous, nil, 0),
            (.protectedDataUnavailable, nil, 0)
        ]
        for (read, journal, deferred) in cases {
            let effects = try recoveryEffects(journal: journal)
            let auth = V915AuthenticationClient(outcomes: [])
            let setting = V915SettingStore(value: nil, readOverride: read)
            let ingressEffects = V915IngressEffects(deferredCount: deferred)
            let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
                setting: setting, authentication: auth,
                ingressStore: InjectedProtectedIngressStoreV1(effects: ingressEffects),
                notifications: AppLockNotificationPrivacyCoordinatorV1(effects: effects),
                clock: V915Clock(), identifiers: V915IDs(values: (850...854).map(Self.id))
            )
            let loadsBefore = await effects.loadCount
            let recovery = try await lifecycle.recoverAfterAuthentication()
            XCTAssertEqual(recovery, .ambiguousStateLocked)
            let loadsAfter = await effects.loadCount
            if deferred > 0 { XCTAssertEqual(loadsAfter, loadsBefore) }
            if deferred > 0 {
                do {
                    try await lifecycle.erase(operationID: Self.id(855))
                    XCTFail("Erase treated pending-intent deletion as scratch ownership recovery")
                } catch {
                    XCTAssertEqual(error as? AppAccessContractFailureV1, .configurationUnknown)
                }
                let stillHeld = try await lifecycle.recoverAfterAuthentication()
                XCTAssertEqual(stillHeld, .ambiguousStateLocked)
                let loadsAfterErase = await effects.loadCount
                let erasedSetting = await setting.eraseCallCount
                XCTAssertEqual(loadsAfterErase, loadsBefore)
                XCTAssertEqual(erasedSetting, 0)
            }
            let gate = await lifecycle.accessGate()
            let unresolved = await gate.requiresConfigurationRecovery()
            XCTAssertTrue(unresolved)
            await assertReadDenied(gate)
            let attempts = await auth.attempts
            let writes = await setting.writeEffectCount
            let publishes = await effects.publishCount
            let rebuilds = await effects.rebuildCount
            let retained = await effects.loadJournalEffect()
            let pendingIntents = await ingressEffects.loadPendingIntentsEffect()
            let notificationErases = await effects.eraseCallCount
            let ingressErases = await ingressEffects.eraseCallCount
            XCTAssertTrue(attempts.isEmpty)
            XCTAssertEqual(writes, 0)
            XCTAssertEqual(publishes, 0)
            XCTAssertEqual(rebuilds, 0)
            XCTAssertEqual(notificationErases, 0)
            XCTAssertEqual(ingressErases, 0)
            XCTAssertEqual(retained, journal)
            XCTAssertEqual(pendingIntents.count, deferred)
            XCTAssertTrue(pendingIntents.allSatisfy { $0.disposition == .deferredAmbiguousOwnership })
        }
    }

    func testSuspendedNotificationRecoveryDeniesContentAndBackgroundPreemptsSettingWrite() async throws {
        for background in [false, true] {
            let journal = try recoveryJournal(enabled: true, disposition: .enablingPrepared)
            let effects = try recoveryEffects(journal: journal, pausesPublication: true)
            let notifications = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
            let setting = V915SettingStore(value: .init(isEnabled: false))
            let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
                setting: setting, authentication: V915AuthenticationClient(outcomes: [.authenticated]),
                ingressStore: V915IngressStore(), notifications: notifications,
                clock: V915Clock(), identifiers: V915IDs(values: (860...869).map(Self.id))
            )
            let recovering = Task { try await lifecycle.recoverAfterAuthentication() }
            await effects.waitUntilPublicationStarted()
            let gate = await lifecycle.accessGate()
            let state = await gate.currentState()
            let cover = await gate.privacyCoverRequired()
            XCTAssertEqual(state, .configurationUnknownLocked)
            XCTAssertTrue(cover)
            await assertReadDenied(gate)
            do { _ = try await lifecycle.requireContentAccess(for: .startupRecovery); XCTFail("pending recovery opened content") }
            catch { XCTAssertEqual(error as? AppAccessContentReadFailureV1, .denied(surface: .startupRecovery, state: .configurationUnknownLocked)) }
            let writesBefore = await setting.writeEffectCount
            XCTAssertEqual(writesBefore, 0)
            if background { _ = try await lifecycle.handle(.sceneBackground) }
            await effects.releasePublication()
            if background {
                do { _ = try await recovering.value; XCTFail("backgrounded repair changed setting") }
                catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            } else {
                let result = try await recovering.value
                XCTAssertEqual(result, .resumedToLocked)
            }
            let writes = await setting.writeEffectCount
            let durableSetting = await setting.readAppLockSetting()
            let retained = try await notifications.loadJournal()
            let finalState = await gate.currentState()
            let unresolved = await gate.requiresConfigurationRecovery()
            XCTAssertEqual(writes, background ? 0 : 1)
            XCTAssertEqual(durableSetting, .value(.init(isEnabled: !background)))
            XCTAssertEqual(retained?.disposition, .genericProjectionApplied)
            XCTAssertEqual(finalState, background ? .configurationUnknownLocked : .locked(reason: .coldLaunch))
            XCTAssertEqual(unresolved, background)
            await assertReadDenied(gate)
        }
    }

    func testDisabledNotificationRecoveryCompletesWithRebuiltPolicyAndConsumesRepairProof() async throws {
        let journal = try recoveryJournal(enabled: false, disposition: .disablingPrepared)
        let effects = try recoveryEffects(journal: journal)
        let notifications = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
        let setting = V915SettingStore(value: .init(isEnabled: true))
        let auth = V915AuthenticationClient(outcomes: [.authenticated])
        let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: setting, authentication: auth, ingressStore: V915IngressStore(),
            notifications: notifications, clock: V915Clock(),
            identifiers: V915IDs(values: (900...909).map(Self.id))
        )
        let result = try await lifecycle.recoverAfterAuthentication()
        XCTAssertEqual(result, .resumedToLocked)
        let gate = await lifecycle.accessGate()
        let state = await gate.currentState()
        let unresolved = await gate.requiresConfigurationRecovery()
        let retained = try await notifications.loadJournal()
        let settingRead = await setting.readAppLockSetting()
        let writes = await setting.writeEffectCount
        let rebuilds = await effects.rebuildCount
        XCTAssertEqual(state, .disabled)
        XCTAssertFalse(unresolved)
        XCTAssertEqual(retained?.operationID, journal.operationID)
        XCTAssertEqual(retained?.priorPolicy, journal.priorPolicy)
        XCTAssertEqual(retained?.disposition, .priorPolicyRebuilt)
        XCTAssertEqual(settingRead, .value(.init(isEnabled: false)))
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(rebuilds, 1)
        do { _ = try await gate.configurationAuthenticationToken(); XCTFail("completed disable retained a repair proof") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        _ = try await gate.beginContentRead(for: .search)
        let repeated = try await lifecycle.recoverAfterAuthentication()
        let attempts = await auth.attempts
        let writesAfterRetry = await setting.writeEffectCount
        let rebuildsAfterRetry = await effects.rebuildCount
        XCTAssertEqual(repeated, .noRecoveryRequired)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(writesAfterRetry, 1)
        XCTAssertEqual(rebuildsAfterRetry, 1)
    }

    func testNotificationJournalChangedDuringAuthenticationCannotWriteStaleDisabledSetting() async throws {
        let original = try recoveryJournal(enabled: false, disposition: .disablingPrepared)
        let replacement = try recoveryJournal(enabled: true, disposition: .genericProjectionApplied, slot: 891)
        for current in [nil, replacement] as [AppLockNotificationJournalV1?] {
            let effects = try recoveryEffects(journal: original)
            let notifications = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
            let auth = V915GatedAuthenticationClient()
            let setting = V915SettingStore(value: .init(isEnabled: true))
            let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
                setting: setting, authentication: auth, ingressStore: V915IngressStore(),
                notifications: notifications, clock: V915Clock(),
                identifiers: V915IDs(values: (880...887).map(Self.id))
            )
            let recovering = Task { try await lifecycle.recoverAfterAuthentication() }
            await auth.waitUntilAttemptStarted()
            await effects.replaceJournalForAuthenticationRace(current)
            await auth.finish(.authenticated)
            do { _ = try await recovering.value; XCTFail("stale disabled recovery survived journal replacement") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
            let writes = await setting.writeEffectCount
            let settingRead = await setting.readAppLockSetting()
            let retained = try await notifications.loadJournal()
            let publishes = await effects.publishCount
            let rebuilds = await effects.rebuildCount
            XCTAssertEqual(writes, 0)
            XCTAssertEqual(settingRead, .value(.init(isEnabled: true)))
            XCTAssertEqual(retained, current)
            XCTAssertEqual(publishes, 0)
            XCTAssertEqual(rebuilds, 0)
            let gate = await lifecycle.accessGate()
            await assertReadDenied(gate)
        }
    }

    func testUnavailableAuthenticationCanRetryOrdinaryUnlockAndFirstEnableWithoutJournalRepair() async throws {
        for enabled in [false, true] {
            for mode in 0..<3 {
                let status: LocalAuthenticationAvailabilityStatusV1 = mode == 0
                    ? .temporarilyUnavailable : (mode == 1 ? .unsupported : .available)
                let outcomes: [LocalAuthenticationOutcomeV1] = mode == 2
                    ? [.unavailable, .authenticated] : [.authenticated]
                let auth = V915AuthenticationClient(outcomes: outcomes, availabilityStatus: status)
                let effects = try recoveryEffects(journal: nil)
                let notifications = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
                let setting = V915SettingStore(value: .init(isEnabled: enabled))
                let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
                    setting: setting, authentication: auth, ingressStore: V915IngressStore(),
                    notifications: notifications, clock: V915Clock(),
                    identifiers: V915IDs(values: (920...939).map(Self.id))
                )
                let gate = await lifecycle.accessGate()
                if enabled {
                    let unavailable = await gate.authenticate(trigger: .unlock)
                    XCTAssertEqual(unavailable, .unavailable)
                } else {
                    do { _ = try await lifecycle.enable(operationID: Self.id(940)); XCTFail("unavailable authentication enabled App Lock") }
                    catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
                }
                let state = await gate.currentState()
                let unresolved = await gate.requiresConfigurationRecovery()
                let journal = try await notifications.loadJournal()
                let writesBefore = await setting.writeEffectCount
                XCTAssertEqual(state, .interruptedLocked)
                XCTAssertFalse(unresolved)
                XCTAssertNil(journal)
                XCTAssertEqual(writesBefore, 0)
                await assertReadDenied(gate)
                await auth.setAvailability(.available)
                let noRepair = try await lifecycle.recoverAfterAuthentication()
                XCTAssertEqual(noRepair, .noRecoveryRequired)
                if enabled {
                    let retry = await gate.authenticate(trigger: .unlock)
                    XCTAssertEqual(retry, .authenticated)
                    _ = try await gate.beginContentRead(for: .search)
                } else {
                    let retry = try await lifecycle.enable(operationID: Self.id(941))
                    XCTAssertTrue(retry.enabled)
                    XCTAssertEqual(retry.authenticationOutcome, .authenticated)
                    let retryState = await gate.currentState()
                    XCTAssertEqual(retryState, .locked(reason: .coldLaunch))
                }
                let attempts = await auth.attempts
                let writes = await setting.writeEffectCount
                XCTAssertEqual(attempts.count, mode == 2 ? 2 : 1)
                XCTAssertTrue(attempts.allSatisfy { $0.trigger == (enabled ? .unlock : .enableAppLock) })
                XCTAssertEqual(writes, enabled ? 0 : 1)
            }
        }
    }

    func testSpecializedContentPermitsRejectRepairProofAndTransientInactivity() async throws {
        let surfaces: [AppAccessContentReadSurfaceV1] = [
            .ocrProposal, .dictationProposal, .oneShotLocationProposal,
            .temporalAudioCapture, .temporalVideoCapture
        ]
        let repairGate = AppAccessGateV1(
            setting: .corruptOrAmbiguous,
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(950), Self.id(951)])
        )
        let repair = await repairGate.authenticate(trigger: .repairConfiguration)
        XCTAssertEqual(repair, .authenticated)
        _ = try await repairGate.configurationAuthenticationToken()
        for surface in surfaces {
            do { _ = try await specializedPermit(repairGate, surface: surface); XCTFail("repair proof opened \(surface)") }
            catch { XCTAssertEqual(error as? AppAccessContentReadFailureV1, .denied(surface: surface, state: .configurationUnknownLocked)) }
        }
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)),
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(952), Self.id(953)])
        )
        let unlocked = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlocked, .authenticated)
        for surface in surfaces {
            let permit = try await specializedPermit(gate, surface: surface)
            XCTAssertEqual(permit.surface, surface)
        }
        let stateBefore = await gate.currentState()
        await gate.sceneBecameInactive()
        for surface in surfaces {
            do { _ = try await specializedPermit(gate, surface: surface); XCTFail("inactive scene opened \(surface)") }
            catch { XCTAssertEqual(error as? AppAccessContentReadFailureV1, .denied(surface: surface, state: stateBefore)) }
        }
        await gate.sceneBecameActive()
        let stateAfter = await gate.currentState()
        XCTAssertEqual(stateAfter, stateBefore)
        for surface in surfaces {
            let permit = try await specializedPermit(gate, surface: surface)
            XCTAssertEqual(permit.surface, surface)
        }
    }

    func testAppLockStoredPreferencesDistinguishAbsenceAndExplicitFalseAcrossReopen() async throws {
        let suiteName = "V915.AppLock.Stored.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = try SettingsRegistryV1.current()
        let descriptor = try registry.descriptor(for: DeviceLocalAppLockSettingV1.key)
        let key = PreferencesAdapterV1.storagePrefix + descriptor.key
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let setting = try DeviceLocalAppLockSettingAdapterV1(preferences: preferences, registry: registry)
        XCTAssertNil(try preferences.readStoredCanonicalValue(for: descriptor))
        XCTAssertEqual(try preferences.readCanonicalValue(for: descriptor), descriptor.defaultCanonicalValue)
        let absent = await setting.readAppLockSetting()
        XCTAssertEqual(absent, .absentDisabled)
        XCTAssertNil(defaults.object(forKey: key))
        _ = try await setting.writeAppLockSetting(.init(isEnabled: false), operationID: Self.id(960), authorization: try await v915Authorization(operationID: Self.id(960), targetEnabled: false))
        let bytes = try XCTUnwrap(defaults.data(forKey: key))
        let reopenedPreferences = PreferencesAdapterV1(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let reopenedSetting = try DeviceLocalAppLockSettingAdapterV1(preferences: reopenedPreferences, registry: registry)
        let explicit = await reopenedSetting.readAppLockSetting()
        XCTAssertEqual(explicit, .value(.init(isEnabled: false)))
        XCTAssertEqual(try reopenedPreferences.readStoredCanonicalValue(for: descriptor), descriptor.defaultCanonicalValue)
        XCTAssertEqual(defaults.data(forKey: key), bytes)
        defaults.removeObject(forKey: key)
        let removed = await reopenedSetting.readAppLockSetting()
        XCTAssertEqual(removed, .absentDisabled)
        XCTAssertEqual(try reopenedPreferences.readCanonicalValue(for: descriptor), descriptor.defaultCanonicalValue)
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testAppLockStoredPreferencesRejectMalformedValuesWithoutRepairAcrossReopen() async throws {
        let suiteName = "V915.AppLock.Malformed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = try SettingsRegistryV1.current()
        let descriptor = try registry.descriptor(for: DeviceLocalAppLockSettingV1.key)
        let key = PreferencesAdapterV1.storagePrefix + descriptor.key
        let original = try DeviceLocalAppLockSettingAdapterV1(
            preferences: PreferencesAdapterV1(defaults: defaults), registry: registry
        )
        _ = try await original.writeAppLockSetting(.init(isEnabled: false), operationID: Self.id(961), authorization: try await v915Authorization(operationID: Self.id(961), targetEnabled: false))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: key))) as? [String: Any])
        let wrongType = Data("\"false\"".utf8)
        envelope["canonicalValue"] = wrongType.base64EncodedString()
        var writeRecord = try XCTUnwrap(envelope["writeRecord"] as? [String: Any])
        writeRecord["canonicalValueDigest"] = CompatibilityCanonicalV1.sha256(wrongType)
        envelope["writeRecord"] = writeRecord
        let wrongTypeEnvelope = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        let hostileValues: [Any] = ["false", Data("false".utf8), wrongTypeEnvelope]
        for hostile in hostileValues {
            defaults.set(hostile, forKey: key)
            let reopened = PreferencesAdapterV1(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
            let setting = try DeviceLocalAppLockSettingAdapterV1(preferences: reopened, registry: registry)
            XCTAssertThrowsError(try reopened.readStoredCanonicalValue(for: descriptor))
            let read = await setting.readAppLockSetting()
            XCTAssertEqual(read, .corruptOrAmbiguous)
            if let bytes = hostile as? Data { XCTAssertEqual(defaults.data(forKey: key), bytes) }
            else { XCTAssertEqual(defaults.string(forKey: key), hostile as? String) }
        }
    }

    func testRetainedDisabledJournalRequiresActuallyStoredFalseAtBootstrap() async throws {
        let suiteName = "V915.AppLock.Bootstrap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = try SettingsRegistryV1.current()
        let journal = try recoveryJournal(enabled: false, disposition: .priorPolicyRebuilt)
        let notifications = AppLockNotificationPrivacyCoordinatorV1(effects: try recoveryEffects(journal: journal))
        let auth = V915AuthenticationClient(outcomes: [])
        for explicit in [false, true] {
            let preferences = PreferencesAdapterV1(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
            let setting = try DeviceLocalAppLockSettingAdapterV1(preferences: preferences, registry: registry)
            if explicit {
                _ = try await setting.writeAppLockSetting(.init(isEnabled: false), operationID: Self.id(962), authorization: try await v915Authorization(operationID: Self.id(962), targetEnabled: false))
            }
            let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
                setting: setting, authentication: auth, ingressStore: V915IngressStore(),
                notifications: notifications, clock: V915Clock(),
                identifiers: V915IDs(values: (963...969).map(Self.id))
            )
            let gate = await lifecycle.accessGate()
            let state = await gate.currentState()
            XCTAssertEqual(state, explicit ? .disabled : .configurationUnknownLocked)
            if !explicit { await assertReadDenied(gate) }
            else {
                let recovery = try await lifecycle.recoverAfterAuthentication()
                XCTAssertEqual(recovery, .noRecoveryRequired)
            }
        }
        let attempts = await auth.attempts
        XCTAssertTrue(attempts.isEmpty)
    }

    private func specializedPermit(
        _ gate: AppAccessGateV1, surface: AppAccessContentReadSurfaceV1
    ) async throws -> AppAccessContentPermitV1 {
        switch surface {
        case .ocrProposal: return try await gate.requireOCRProposalContentAccess()
        case .dictationProposal: return try await gate.requireDictationProposalContentAccess()
        case .oneShotLocationProposal: return try await gate.requireOneShotLocationProposalContentAccess()
        case .temporalAudioCapture: return try await gate.requireTemporalAudioCaptureAccess()
        case .temporalVideoCapture: return try await gate.requireTemporalVideoCaptureAccess()
        default: throw AppAccessContractFailureV1.invalidValue
        }
    }

    private func recoveryJournal(
        enabled: Bool, disposition: AppLockNotificationPrivacyDispositionV1, slot: Int = 890
    ) throws -> AppLockNotificationJournalV1 {
        try .init(
            operationID: Self.id(slot), targetEnabled: enabled,
            priorPolicy: .init(policyID: "recovery-policy", revision: 1, canonicalDigest: Self.digest(890)),
            projections: [], disposition: disposition
        )
    }

    private func recoveryEffects(
        journal: AppLockNotificationJournalV1?, pausesPublication: Bool = false
    ) throws -> V915NotificationEffects {
        let policy = AppLockNotificationCanonicalPolicyV1(
            policyID: "recovery-policy", revision: 1, canonicalDigest: Self.digest(890)
        )
        let projection = AppLockGenericNotificationV1(
            requestID: "recovery-generic", opaqueCorrelationToken: Self.digest(890),
            title: AppLockCopyV1.genericNotificationTitle, body: AppLockCopyV1.genericNotificationBody
        )
        return V915NotificationEffects(
            policy: policy, projection: projection, initialJournal: journal,
            pausesPublication: pausesPublication
        )
    }

    func testTransientInactiveRevokesReadsWithoutCancellingSystemAuthentication() async throws {
        let auth = V915GatedAuthenticationClient()
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)), authentication: auth,
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(720), Self.id(721)]))
        let unlocking = Task { await gate.authenticate(trigger: .unlock) }
        await auth.waitUntilAttemptStarted()
        let authenticating = await gate.currentState()
        await gate.sceneBecameInactive()
        let stillAuthenticating = await gate.currentState()
        XCTAssertEqual(stillAuthenticating, authenticating)
        await assertReadDenied(gate)
        await auth.finish(.authenticated)
        let outcome = await unlocking.value
        XCTAssertEqual(outcome, .authenticated)
        let cancellations = await auth.cancelledAttemptIDs
        XCTAssertTrue(cancellations.isEmpty)
        let covered = await gate.privacyCoverRequired()
        XCTAssertTrue(covered)
        let unlocked = await gate.currentState()
        XCTAssertEqual(unlocked, .unlockedForeground(sessionID: Self.id(721)))
        await assertReadDenied(gate)
        await gate.sceneBecameActive()
        let token = try await gate.beginContentRead(for: .search)
        try await gate.validateContentRead(token, for: .search)
        let revealed = await gate.privacyCoverRequired()
        XCTAssertFalse(revealed)
    }

    func testToggleProofBindsFreshAuthenticationOwnerTargetAndSingleCompletion() async throws {
        for enabled in [false, true] {
            let gate = AppAccessGateV1(setting: .value(.init(isEnabled: !enabled)),
                authentication: V915AuthenticationClient(outcomes: [.authenticated, .authenticated]),
                clock: V915Clock(), identifiers: V915IDs(values: (801...804).map(Self.id)))
            if !enabled {
                let unlockOutcome = await gate.authenticate(trigger: .unlock)
                XCTAssertEqual(unlockOutcome, .authenticated)
            }
            let outcome = await gate.authenticate(trigger: enabled ? .enableAppLock : .disableAppLock)
            XCTAssertEqual(outcome, .authenticated)
            let proof = try await gate.toggleAuthenticationToken(targetEnabled: enabled)
            try await gate.validateToggleAuthentication(proof, targetEnabled: enabled)
            do {
                try await gate.validateToggleAuthentication(proof, targetEnabled: !enabled)
                XCTFail("toggle proof crossed its target")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            let other = AppAccessGateV1(setting: .value(.init(isEnabled: !enabled)),
                authentication: V915AuthenticationClient(outcomes: [.authenticated, .authenticated]),
                clock: V915Clock(), identifiers: V915IDs(values: (801...804).map(Self.id)))
            if !enabled {
                let unlockOutcome = await other.authenticate(trigger: .unlock)
                XCTAssertEqual(unlockOutcome, .authenticated)
            }
            let otherOutcome = await other.authenticate(trigger: enabled ? .enableAppLock : .disableAppLock)
            XCTAssertEqual(otherOutcome, .authenticated)
            do {
                try await other.setEnabledAfterAuthenticated(enabled, toggleToken: proof)
                XCTFail("matching session identifiers accepted another gate's proof")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            do {
                try await gate.setEnabledAfterAuthenticated(enabled)
                XCTFail("an unlocked state replaced fresh toggle proof")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
            try await gate.setEnabledAfterAuthenticated(enabled, toggleToken: proof)
            do {
                try await gate.setEnabledAfterAuthenticated(enabled, toggleToken: proof)
                XCTFail("completed toggle proof replayed")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        }
    }

    func testToggleProofRevocationAndOrdinaryUnlockCannotAuthorizeConfiguration() async throws {
        for boundary in 0..<5 {
            let targetEnabled = boundary != 3
            let gate = AppAccessGateV1(setting: targetEnabled ? .absentDisabled : .value(.init(isEnabled: true)),
                authentication: V915AuthenticationClient(outcomes: [.authenticated, .authenticated, .authenticated]),
                clock: V915Clock(), identifiers: V915IDs(values: (811...818).map(Self.id)))
            if !targetEnabled {
                let unlockOutcome = await gate.authenticate(trigger: .unlock)
                XCTAssertEqual(unlockOutcome, .authenticated)
            }
            let outcome = await gate.authenticate(trigger: targetEnabled ? .enableAppLock : .disableAppLock)
            XCTAssertEqual(outcome, .authenticated)
            let proof = try await gate.toggleAuthenticationToken(targetEnabled: targetEnabled)
            try await gate.validateToggleAuthentication(proof, targetEnabled: targetEnabled)
            switch boundary {
            case 0: await gate.sceneBecameInactive(); await gate.sceneBecameActive()
            case 1: await gate.lock(reason: .returnedFromBackground)
            case 2: await gate.markConfigurationUnknown()
            case 3:
                let freshOutcome = await gate.authenticate(trigger: .disableAppLock)
                XCTAssertEqual(freshOutcome, .authenticated)
            default: await gate.eraseAccessState()
            }
            do {
                try await gate.validateToggleAuthentication(proof, targetEnabled: targetEnabled)
                XCTFail("revoked toggle proof survived boundary \(boundary)")
            } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        }
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(821), Self.id(822)]))
        let unlockOutcome = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlockOutcome, .authenticated)
        _ = try await gate.beginContentRead(for: .render)
        do {
            _ = try await gate.toggleAuthenticationToken(targetEnabled: false)
            XCTFail("ordinary unlock minted a disable proof")
        } catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
    }

    func testV9_15G01OptInAccessGateUsesFreshDeviceOwnerAuthentication() async throws {
        let corpus = try Self.corpus()
        XCTAssertEqual(corpus.string("authority.cardID"), "V23-P02-C11")
        XCTAssertEqual(corpus.bool("activation.provisionalKernelOnly"), true)
        XCTAssertEqual(corpus.bool("activation.adopted"), false)
        XCTAssertEqual(corpus.bool("activation.shippingSurfaceEnabled"), false)

        let registry = try SettingsRegistryV1.current()
        let descriptor = try registry.descriptor(for: DeviceLocalAppLockSettingV1.key)
        XCTAssertEqual(descriptor.scope, .deviceLocal)
        XCTAssertEqual(descriptor.storage, .soleDevicePreferencesAdapter)
        XCTAssertEqual(descriptor.backup, .excludedDeviceLocal)
        XCTAssertEqual(descriptor.erase, .restoreDefault)
        XCTAssertEqual(
            try CompatibilityCanonicalV1.decode(Bool.self, from: descriptor.defaultCanonicalValue),
            false
        )

        let authentication = V915AuthenticationClient(outcomes: [.authenticated, .authenticated, .authenticated])
        let gate = AppAccessGateV1(
            setting: .absentDisabled,
            authentication: authentication,
            clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(1), Self.id(2), Self.id(3), Self.id(4), Self.id(5), Self.id(6)])
        )
        var observedState = await gate.currentState()
        XCTAssertEqual(observedState, .disabled)
        try await gate.requireContentAccess()

        var outcome = await gate.authenticate(trigger: .enableAppLock)
        XCTAssertEqual(outcome, .authenticated)
        let toggleProof = try await gate.toggleAuthenticationToken(targetEnabled: true)
        try await gate.setEnabledAfterAuthenticated(true, toggleToken: toggleProof)
        try await gate.markRecoveryComplete(enabled: true)
        observedState = await gate.currentState()
        XCTAssertEqual(observedState, .locked(reason: .coldLaunch))
        do { try await gate.requireContentAccess(); XCTFail("locked gate allowed content") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        outcome = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(outcome, .authenticated)
        guard case .unlockedForeground = await gate.currentState() else {
            return XCTFail("successful device-owner authentication must create an in-memory foreground session")
        }
        await gate.sceneBecameInactive()
        let inactiveCover = await gate.privacyCoverRequired()
        let inactiveState = await gate.currentState()
        XCTAssertTrue(inactiveCover)
        guard case .unlockedForeground = inactiveState else {
            return XCTFail("transient inactive must cover without relocking")
        }
        await gate.lock(reason: .returnedFromBackground)
        observedState = await gate.currentState()
        XCTAssertEqual(observedState, .locked(reason: .returnedFromBackground))
        outcome = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(outcome, .authenticated)

        let attempts = await authentication.attempts
        XCTAssertEqual(attempts.count, 3)
        XCTAssertEqual(Set(attempts.map(\.attemptID)).count, attempts.count)
        XCTAssertTrue(attempts.allSatisfy { $0.policy == LocalAuthenticationAttemptV1.policy })
        XCTAssertTrue(attempts.allSatisfy { $0.contextLifecycle == .freshContextPerAttempt })
        XCTAssertEqual(attempts.map(\.trigger), [.enableAppLock, .unlock, .unlock])
        let maximumEvaluations = await authentication.maximumEvaluationCountPerAttempt
        XCTAssertEqual(maximumEvaluations, 1)

        let cold = AppAccessGateV1(
            setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)),
            authentication: authentication,
            clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(9)])
        )
        let coldState = await cold.currentState()
        let coldCover = await cold.privacyCoverRequired()
        XCTAssertEqual(coldState, .locked(reason: .coldLaunch))
        XCTAssertTrue(coldCover)
        XCTAssertEqual(AppLockShippingAdoptionV1.deferredUntilAcceptedS10_6Composition.rawValue,
                       "DEFERRED_UNTIL_ACCEPTED_S10_6_COMPOSITION")
        XCTAssertEqual(Set(AppLockReasonV1.allCases.map(\.rawValue)), Set(corpus.strings("lockReasons")))
        XCTAssertEqual(Set(AppLockLifecycleEventV1.allCases.map(\.rawValue)), Set(corpus.strings("lifecycleEvents")))
        XCTAssertEqual(Set(LocalAuthenticationAvailabilityStatusV1.allCases.map(\.rawValue)), Set(corpus.strings("authentication.availabilityCases")))
        XCTAssertEqual(Set(LocalAuthenticationOutcomeV1.allCases.map(\.rawValue)), Set(corpus.strings("authentication.outcomeCases")))
    }

    func testV9_15A01LockedIngressAndNotificationsRemainContentBlind() async throws {
        let corpus = try Self.corpus()
        XCTAssertEqual(Set(corpus.strings("gatedEntryPoints")).count, 17)
        XCTAssertEqual(Set(corpus.strings("ingressKinds")), Set(LockedIngressKindV1.allCases.map(\.rawValue)))
        XCTAssertEqual(AppLockCopyV1.genericNotificationTitle, corpus.string("exactCopy.genericNotificationTitle"))
        XCTAssertEqual(AppLockCopyV1.genericNotificationBody, corpus.string("exactCopy.genericNotificationBody"))

        let ingress = V915IngressStore()
        let lockedGate = AppAccessGateV1(
            setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)),
            authentication: V915AuthenticationClient(outcomes: []), clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(19)])
        )
        let protectedIngress = ProtectedIngressCoordinatorV1(
            gate: lockedGate, store: ingress, clock: V915Clock()
        )
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("v915-opaque-source")
        let now = V915Clock.value
        for (offset, kind) in LockedIngressKindV1.allCases.enumerated() {
            let receipt = try await protectedIngress.stageWhileLocked(
                ProtectedIngressStageRequestV1(
                    intentID: Self.id(20 + offset), operationID: Self.id(40 + offset), kind: kind,
                    byteCount: UInt64(offset + 1), receivedAt: now,
                    expiresAt: now.addingTimeInterval(60)
                ),
                source: source
            )
            XCTAssertEqual(receipt.disposition, .stagedProtectedPendingAuthentication)
            XCTAssertFalse(receipt.adoptedExistingEffect)
            XCTAssertEqual(receipt.intent.kind, kind)
            try receipt.intent.validate()
        }
        let pending = try await ingress.pendingIntents()
        XCTAssertEqual(pending.count, LockedIngressKindV1.allCases.count)
        let counters = await ingress.contentCounters
        XCTAssertEqual(counters, .zero)

        let durableEffects = V915IngressEffects()
        let productionIngress = InjectedProtectedIngressStoreV1(effects: durableEffects)
        let durableRequest = ProtectedIngressStageRequestV1(
            intentID: Self.id(93), operationID: Self.id(94), kind: .document,
            byteCount: 20, receivedAt: now, expiresAt: now.addingTimeInterval(60)
        )
        let durableFirst = try await productionIngress.stageContentBlind(durableRequest, source: source)
        let durableReplay = try await productionIngress.stageContentBlind(durableRequest, source: source)
        XCTAssertFalse(durableFirst.adoptedExistingEffect)
        XCTAssertTrue(durableReplay.adoptedExistingEffect)
        XCTAssertEqual(durableReplay.disposition, .duplicateAdopted)
        let conflictingRequest = ProtectedIngressStageRequestV1(
            intentID: durableRequest.intentID, operationID: Self.id(95), kind: .document,
            byteCount: 20, receivedAt: now, expiresAt: now.addingTimeInterval(60)
        )
        do { _ = try await productionIngress.stageContentBlind(conflictingRequest, source: source); XCTFail("same intent adopted a different subject") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
        let readyFirst = try await productionIngress.markReadyForAuthenticatedValidation(intentID: durableRequest.intentID)
        let readyReplay = try await productionIngress.markReadyForAuthenticatedValidation(intentID: durableRequest.intentID)
        XCTAssertEqual(readyFirst, readyReplay)
        try await productionIngress.eraseAllProtectedIngress(operationID: Self.id(96))
        try await productionIngress.eraseAllProtectedIngress(operationID: Self.id(96))
        let durableErased = try await productionIngress.pendingIntents()
        XCTAssertEqual(durableErased, [])

        XCTAssertThrowsError(try PendingLockedExternalIntentV1(
            intentID: Self.id(90), operationID: Self.id(91), kind: .document,
            opaqueStagingID: "opaque-90", byteCount: PendingLockedExternalIntentV1.maximumByteCount + 1,
            sha256: Self.digest(90), receivedAt: now, expiresAt: now.addingTimeInterval(60),
            disposition: .stagedProtectedPendingAuthentication
        )) { XCTAssertEqual($0 as? AppAccessContractFailureV1, .configurationUnknown) }

        let policy = AppLockNotificationCanonicalPolicyV1(
            policyID: "notification-detail-policy", revision: 7, canonicalDigest: Self.digest(7)
        )
        let projection = AppLockGenericNotificationV1(
            requestID: "reminder-opaque-1", opaqueCorrelationToken: Self.digest(8),
            title: AppLockCopyV1.genericNotificationTitle, body: AppLockCopyV1.genericNotificationBody
        )
        try projection.validate()
        let journal = try AppLockNotificationJournalV1(
            operationID: Self.id(92), targetEnabled: true, priorPolicy: policy,
            projections: [projection], disposition: .enablingPrepared
        )
        XCTAssertEqual(journal.projections, [projection])
        let canonical = try CompatibilityCanonicalV1.encode(projection)
        for forbidden in corpus.strings("notificationPrivacy.payloadForbiddenFields") {
            XCTAssertFalse(String(decoding: canonical, as: UTF8.self).localizedCaseInsensitiveContains(forbidden))
        }
        XCTAssertThrowsError(try AppLockGenericNotificationV1(
            requestID: "private", opaqueCorrelationToken: Self.digest(9),
            title: "Customer Alpha", body: "Site 7"
        ).validate()) { XCTAssertEqual($0 as? AppAccessContractFailureV1, .invalidValue) }

        let notifications = V915NotificationStore(journal: journal)
        let lockedResolution = try await notifications.resolveOpaqueTokenAfterAuthentication(Self.digest(8), now: now, authorization: try await v915ContentAuthorization())
        XCTAssertNil(lockedResolution)
        await notifications.markAuthenticated()
        let unlockedResolution = try await notifications.resolveOpaqueTokenAfterAuthentication(Self.digest(8), now: now, authorization: try await v915ContentAuthorization())
        let applied = try await notifications.applyGenericProjection(journal, authorization: try await v915Authorization(notifications: notifications, operationID: journal.operationID, targetEnabled: journal.targetEnabled))
        let adopted = try await notifications.applyGenericProjection(journal, authorization: try await v915Authorization(notifications: notifications, operationID: journal.operationID, targetEnabled: journal.targetEnabled))
        let mixed = await notifications.mixedPrivateAndGeneric
        XCTAssertEqual(unlockedResolution, "opaque-route")
        XCTAssertEqual(applied, .genericProjectionApplied)
        XCTAssertEqual(adopted, .genericProjectionAdopted)
        XCTAssertFalse(mixed)

        let notificationEffects = V915NotificationEffects(policy: policy, projection: projection)
        let productionNotifications = AppLockNotificationPrivacyCoordinatorV1(effects: notificationEffects)
        let productionPrepared = try await productionNotifications.prepareEnable(operationID: Self.id(97), authorization: try await v915Authorization(notifications: productionNotifications, operationID: Self.id(97), targetEnabled: true))
        let productionApplied = try await productionNotifications.applyGenericProjection(productionPrepared, authorization: try await v915Authorization(notifications: productionNotifications, operationID: productionPrepared.operationID, targetEnabled: productionPrepared.targetEnabled))
        let productionAdopted = try await productionNotifications.applyGenericProjection(productionPrepared, authorization: try await v915Authorization(notifications: productionNotifications, operationID: productionPrepared.operationID, targetEnabled: productionPrepared.targetEnabled))
        XCTAssertEqual(productionApplied, .genericProjectionApplied)
        XCTAssertEqual(productionAdopted, .genericProjectionAdopted)
        let wrongSubject = try AppLockNotificationJournalV1(
            operationID: productionPrepared.operationID, targetEnabled: true,
            priorPolicy: productionPrepared.priorPolicy,
            projections: [AppLockGenericNotificationV1(
                requestID: "wrong-subject", opaqueCorrelationToken: Self.digest(98)
            )], disposition: .enablingPrepared
        )
        do { _ = try await productionNotifications.applyGenericProjection(wrongSubject, authorization: try await v915Authorization(notifications: productionNotifications, operationID: wrongSubject.operationID, targetEnabled: wrongSubject.targetEnabled)); XCTFail("terminal journal adopted the wrong subject") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
        let completedEnableReadback = try await productionNotifications.loadJournal()
        let completedEnable = try XCTUnwrap(completedEnableReadback)
        let enableRetry = try await productionNotifications.prepareEnable(operationID: Self.id(97), authorization: try await v915Authorization(notifications: productionNotifications, operationID: Self.id(97), targetEnabled: true))
        XCTAssertEqual(enableRetry, completedEnable)
        let disablePrepared = try await productionNotifications.prepareDisable(operationID: Self.id(100), authorization: try await v915Authorization(notifications: productionNotifications, operationID: Self.id(100), targetEnabled: false))
        XCTAssertEqual(disablePrepared.priorPolicy, policy)
        XCTAssertTrue(disablePrepared.projections.isEmpty)
        let disableRetry = try await productionNotifications.prepareDisable(operationID: Self.id(100), authorization: try await v915Authorization(notifications: productionNotifications, operationID: Self.id(100), targetEnabled: false))
        XCTAssertEqual(disableRetry, disablePrepared)
        let rebuilt = try await productionNotifications.rebuildPriorPolicy(disablePrepared, authorization: try await v915Authorization(notifications: productionNotifications, operationID: disablePrepared.operationID, targetEnabled: disablePrepared.targetEnabled))
        XCTAssertEqual(rebuilt, .priorPolicyRebuilt)
        let completedDisable = try await productionNotifications.prepareDisable(operationID: Self.id(100), authorization: try await v915Authorization(notifications: productionNotifications, operationID: Self.id(100), targetEnabled: false))
        XCTAssertEqual(completedDisable.disposition, .priorPolicyRebuilt)
        XCTAssertEqual(completedDisable.priorPolicy, policy)
        let updatedPolicy = AppLockNotificationCanonicalPolicyV1(
            policyID: "new-canonical-policy", revision: policy.revision + 1,
            canonicalDigest: Self.digest(101)
        )
        await notificationEffects.setCanonicalPolicy(updatedPolicy)
        let nextEnable = try await productionNotifications.prepareEnable(operationID: Self.id(101), authorization: try await v915Authorization(notifications: productionNotifications, operationID: Self.id(101), targetEnabled: true))
        XCTAssertEqual(nextEnable.priorPolicy, updatedPolicy)
        let nextApplied = try await productionNotifications.applyGenericProjection(nextEnable, authorization: try await v915Authorization(notifications: productionNotifications, operationID: nextEnable.operationID, targetEnabled: nextEnable.targetEnabled))
        XCTAssertEqual(nextApplied, .genericProjectionApplied)
        let prepareCounts = await notificationEffects.prepareCounts
        XCTAssertEqual(prepareCounts, [2, 1])
        try await productionNotifications.eraseNotificationsAndMappings(operationID: Self.id(99))
        let erasedProductionJournal = try await productionNotifications.loadJournal()
        XCTAssertNil(erasedProductionJournal)
    }

    func testNotificationPreparationPreservesUnfinishedOperationsAndExactRetries() async throws {
        let policy = AppLockNotificationCanonicalPolicyV1(
            policyID: "details-disabled", revision: 7, canonicalDigest: Self.digest(102)
        )
        let projection = AppLockGenericNotificationV1(
            requestID: "generic-reminder", opaqueCorrelationToken: Self.digest(103)
        )
        let effects = V915NotificationEffects(policy: policy, projection: projection)
        let coordinator = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
        let enable = try await coordinator.prepareEnable(operationID: Self.id(104), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(104), targetEnabled: true))
        let enableRetry = try await coordinator.prepareEnable(operationID: Self.id(104), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(104), targetEnabled: true))
        XCTAssertEqual(enableRetry, enable)
        for operation in [Self.id(104), Self.id(105)] {
            do { _ = try await coordinator.prepareDisable(operationID: operation, authorization: try await v915Authorization(notifications: coordinator, operationID: operation, targetEnabled: false)); XCTFail("replaced unfinished enable") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired) }
        }
        do { _ = try await coordinator.prepareEnable(operationID: Self.id(105), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(105), targetEnabled: true)); XCTFail("replaced original enable operation") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired) }
        let retainedEnable = try await coordinator.loadJournal()
        let enableCounts = await effects.prepareCounts
        XCTAssertEqual(retainedEnable, enable)
        XCTAssertEqual(enableCounts, [1, 0])
        _ = try await coordinator.applyGenericProjection(enable, authorization: try await v915Authorization(notifications: coordinator, operationID: enable.operationID, targetEnabled: enable.targetEnabled))
        let disable = try await coordinator.prepareDisable(operationID: Self.id(105), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(105), targetEnabled: false))
        let disableRetry = try await coordinator.prepareDisable(operationID: Self.id(105), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(105), targetEnabled: false))
        XCTAssertEqual(disableRetry, disable)
        for operation in [Self.id(105), Self.id(106)] {
            do { _ = try await coordinator.prepareEnable(operationID: operation, authorization: try await v915Authorization(notifications: coordinator, operationID: operation, targetEnabled: true)); XCTFail("replaced unfinished disable") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired) }
        }
        do { _ = try await coordinator.prepareDisable(operationID: Self.id(106), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(106), targetEnabled: false)); XCTFail("replaced original disable operation") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired) }
        let retainedDisable = try await coordinator.loadJournal()
        let disableCounts = await effects.prepareCounts
        XCTAssertEqual(retainedDisable, disable)
        XCTAssertEqual(disableCounts, [1, 1])
        _ = try await coordinator.rebuildPriorPolicy(disable, authorization: try await v915Authorization(notifications: coordinator, operationID: disable.operationID, targetEnabled: disable.targetEnabled))
        let nextEnable = try await coordinator.prepareEnable(operationID: Self.id(106), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(106), targetEnabled: true))
        XCTAssertEqual(nextEnable.disposition, .enablingPrepared)
    }

    func testNotificationDisableRejectsSubstitutedPriorPolicyBeforeRebuild() async throws {
        let policy = AppLockNotificationCanonicalPolicyV1(
            policyID: "details-disabled", revision: 7, canonicalDigest: Self.digest(107)
        )
        let replacement = AppLockNotificationCanonicalPolicyV1(
            policyID: "details-enabled", revision: 8, canonicalDigest: Self.digest(108)
        )
        let effects = V915NotificationEffects(
            policy: policy,
            projection: .init(requestID: "generic-reminder", opaqueCorrelationToken: Self.digest(109)),
            disablePolicyOverride: replacement
        )
        let coordinator = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
        let enable = try await coordinator.prepareEnable(operationID: Self.id(110), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(110), targetEnabled: true))
        _ = try await coordinator.applyGenericProjection(enable, authorization: try await v915Authorization(notifications: coordinator, operationID: enable.operationID, targetEnabled: enable.targetEnabled))
        let original = try await coordinator.loadJournal()
        do { _ = try await coordinator.prepareDisable(operationID: Self.id(111), authorization: try await v915Authorization(notifications: coordinator, operationID: Self.id(111), targetEnabled: false)); XCTFail("admitted substituted detail policy") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired) }
        let reopened = AppLockNotificationPrivacyCoordinatorV1(effects: effects)
        do { _ = try await reopened.prepareDisable(operationID: Self.id(111), authorization: try await v915Authorization(notifications: reopened, operationID: Self.id(111), targetEnabled: false)); XCTFail("reopened retry admitted substituted detail policy") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .notificationReconciliationRequired) }
        let retained = try await reopened.loadJournal()
        XCTAssertEqual(retained, original)
        let rebuildCount = await effects.rebuildCount
        XCTAssertEqual(rebuildCount, 0)
        await effects.setDisablePolicyOverride(nil)
        let validRetry = try await reopened.prepareDisable(operationID: Self.id(111), authorization: try await v915Authorization(notifications: reopened, operationID: Self.id(111), targetEnabled: false))
        XCTAssertEqual(validRetry.priorPolicy, policy)
        let rebuilt = try await reopened.rebuildPriorPolicy(validRetry, authorization: try await v915Authorization(notifications: reopened, operationID: validRetry.operationID, targetEnabled: validRetry.targetEnabled))
        XCTAssertEqual(rebuilt, .priorPolicyRebuilt)
    }

    func testV9_15H01CorruptSettingsAndAuthenticationFailuresFailLocked() async throws {
        let corpus = try Self.corpus()
        for (read, expected) in [
            (DeviceLocalAppLockSettingReadV1.corruptOrAmbiguous, AppAccessStateV1.configurationUnknownLocked),
            (.protectedDataUnavailable, .locked(reason: .protectedDataUnavailable)),
        ] {
            let gate = AppAccessGateV1(
                setting: read,
                authentication: V915AuthenticationClient(outcomes: [.unavailable]),
                clock: V915Clock(), identifiers: V915IDs(values: [Self.id(100)])
            )
            let state = await gate.currentState()
            let cover = await gate.privacyCoverRequired()
            XCTAssertEqual(state, expected)
            XCTAssertFalse(state.permitsContentAccess)
            XCTAssertTrue(cover)
            do { try await gate.requireContentAccess(); XCTFail("hostile setting allowed content") }
            catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        }

        let cases: [(LocalAuthenticationOutcomeV1, AppAccessStateV1)] = [
            (.userCancelled, .locked(reason: .authenticationCancelled)),
            (.authenticationFailed, .locked(reason: .authenticationFailed)),
            (.biometryLockedOut, .locked(reason: .authenticationLockedOut)),
            (.biometryNotEnrolled, .locked(reason: .biometryNotEnrolled)),
            (.biometryChanged, .locked(reason: .biometryChanged)),
            (.devicePasscodeNotSet, .locked(reason: .devicePasscodeRemoved)),
            (.interrupted, .interruptedLocked),
        ]
        for (index, item) in cases.enumerated() {
            let client = V915AuthenticationClient(outcomes: [item.0])
            let gate = AppAccessGateV1(
                setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)), authentication: client,
                clock: V915Clock(), identifiers: V915IDs(values: [Self.id(110 + index)])
            )
            let outcome = await gate.authenticate(trigger: .unlock)
            let state = await gate.currentState()
            XCTAssertEqual(outcome, item.0)
            XCTAssertEqual(state, item.1)
            XCTAssertFalse(state.permitsContentAccess)
        }

        let unavailable = V915AuthenticationClient(
            outcomes: [], availabilityStatus: .devicePasscodeNotSet
        )
        let unavailableGate = AppAccessGateV1(
            setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)), authentication: unavailable,
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(130)])
        )
        let unavailableOutcome = await unavailableGate.authenticate(trigger: .unlock)
        let unavailableState = await unavailableGate.currentState()
        let unavailableAttempts = await unavailable.attempts
        XCTAssertEqual(unavailableOutcome, .devicePasscodeNotSet)
        XCTAssertEqual(unavailableState, .locked(reason: .devicePasscodeRemoved))
        XCTAssertEqual(unavailableAttempts.count, 0)

        XCTAssertEqual(corpus.bool("claimFlags.appPIN"), false)
        XCTAssertEqual(corpus.bool("claimFlags.databaseEncryption"), false)
        XCTAssertEqual(corpus.bool("claimFlags.identityVerification"), false)
        XCTAssertEqual(corpus.bool("claimFlags.persistedUnlockedSession"), false)
        XCTAssertEqual(corpus.bool("claimFlags.backgroundBypass"), false)
        XCTAssertEqual(AppLockCopyV1.setting, corpus.string("exactCopy.setting"))
        XCTAssertEqual(AppLockCopyV1.disclosure, corpus.string("exactCopy.disclosure"))
        XCTAssertEqual(AppLockCopyV1.locked, corpus.string("exactCopy.lockedState"))
        XCTAssertEqual(AppLockCopyV1.faceIDPurpose, corpus.string("exactCopy.faceIDPurpose"))
        XCTAssertThrowsError(try JSONDecoder().decode(
            DeviceLocalAppLockSettingV1.self,
            from: Data("{\"schemaVersion\":2,\"isEnabled\":false}".utf8)
        )) { XCTAssertEqual($0 as? AppAccessContractFailureV1, .invalidValue) }
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppLockLifecycleEventV1.self,
            from: Data("\"FUTURE_EVENT\"".utf8)
        ))
        try AppLockLifecycleDeclarationV1.current.validate()
        let declarationBytes = try CompatibilityCanonicalV1.encode(AppLockLifecycleDeclarationV1.current)
        var hostileDeclaration = try XCTUnwrap(
            JSONSerialization.jsonObject(with: declarationBytes) as? [String: Any]
        )
        hostileDeclaration["schemaVersion"] = AppLockLifecycleDeclarationV1.schemaVersion + 1
        let hostileDeclarationBytes = try JSONSerialization.data(withJSONObject: hostileDeclaration)
        XCTAssertThrowsError(try JSONDecoder().decode(
            AppLockLifecycleDeclarationV1.self,
            from: hostileDeclarationBytes
        )) { XCTAssertEqual($0 as? AppAccessContractFailureV1, .invalidValue) }

        let knownOwnedEffects = V915IngressEffects(removedCount: 1)
        let knownOwnedStore = InjectedProtectedIngressStoreV1(effects: knownOwnedEffects)
        let knownOwnedHygiene = try await knownOwnedStore.performBlindStartupHygiene(
            now: V915Clock.value, operationID: Self.id(200)
        )
        XCTAssertEqual(knownOwnedHygiene.removedKnownOwnedCount, 1)
        XCTAssertEqual(knownOwnedHygiene.deferredAmbiguousCount, 0)
        XCTAssertFalse(knownOwnedHygiene.contentRead)

        let ambiguousStoreEffects = V915IngressEffects(deferredCount: 1)
        let ambiguousStore = InjectedProtectedIngressStoreV1(effects: ambiguousStoreEffects)
        let ambiguousLifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: V915SettingStore(value: nil),
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            ingressStore: ambiguousStore,
            notifications: V915NotificationStore(journal: nil),
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(201), Self.id(204), Self.id(205)])
        )
        let ambiguousGate = await ambiguousLifecycle.accessGate()
        let ambiguousState = await ambiguousGate.currentState()
        XCTAssertEqual(ambiguousState, .configurationUnknownLocked)
        let repairOutcome = await ambiguousGate.authenticate(trigger: .repairConfiguration)
        XCTAssertEqual(repairOutcome, .authenticated)
        await assertReadDenied(ambiguousGate)
        let ambiguousIngress = await ambiguousLifecycle.protectedIngress()
        do {
            _ = try await ambiguousIngress.resumeAfterAuthentication()
            XCTFail("repair authentication bypassed unresolved scratch ownership")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        let retainedAmbiguous = try await ambiguousStore.pendingIntents()
        XCTAssertEqual(retainedAmbiguous.count, 1)
        XCTAssertEqual(retainedAmbiguous.first?.disposition, .deferredAmbiguousOwnership)
        let ambiguousCounters = await ambiguousStoreEffects.contentCounters
        XCTAssertEqual(ambiguousCounters, .zero)

        let terminalIntentID = Self.id(202)
        let terminalIntent = try PendingLockedExternalIntentV1(
            intentID: terminalIntentID, operationID: Self.id(203), kind: .document,
            opaqueStagingID: "opaque-\(terminalIntentID.uuidString.lowercased())",
            byteCount: 12, sha256: Self.digest(202), receivedAt: V915Clock.value,
            expiresAt: V915Clock.value.addingTimeInterval(60), disposition: .erased
        )
        let terminalSnapshotStore = InjectedProtectedIngressStoreV1(
            effects: V915IngressEffects(initialValues: [terminalIntent])
        )
        do { _ = try await terminalSnapshotStore.pendingIntents(); XCTFail("terminal ingress survived as pending") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .configurationUnknown) }
    }

    func testV9_15I01BackgroundTerminationAndJournalInterruptionRecoverLocked() async throws {
        let availabilityAuthentication = V915AvailabilityGatedAuthenticationClient()
        let availabilityGate = AppAccessGateV1(
            setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)),
            authentication: availabilityAuthentication, clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(138), Self.id(139)])
        )
        let firstAvailabilityAttempt = Task { await availabilityGate.authenticate(trigger: .unlock) }
        await availabilityAuthentication.waitUntilAvailabilityRequested()
        let overlappingOutcome = await availabilityGate.authenticate(trigger: .unlock)
        XCTAssertEqual(overlappingOutcome, .interrupted)
        await availabilityGate.lock(reason: .returnedFromBackground)
        await availabilityAuthentication.releaseAvailability()
        let invalidatedAvailabilityOutcome = await firstAvailabilityAttempt.value
        let availabilityEvaluationCount = await availabilityAuthentication.authenticationEvaluationCount
        let availabilityCancelledIDs = await availabilityAuthentication.cancelledAttemptIDs
        XCTAssertEqual(invalidatedAvailabilityOutcome, .interrupted)
        XCTAssertEqual(availabilityEvaluationCount, 0)
        XCTAssertEqual(availabilityCancelledIDs, [Self.id(138)])

        let resumeAuthentication = V915AuthenticationClient(outcomes: [.authenticated])
        let resumeGate = AppAccessGateV1(
            setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)),
            authentication: resumeAuthentication, clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(132), Self.id(133)])
        )
        let resumeOutcome = await resumeGate.authenticate(trigger: .unlock)
        XCTAssertEqual(resumeOutcome, .authenticated)
        let resumeStore = try V915ResumeGatedIngressStore(now: V915Clock.value)
        let resumeCoordinator = ProtectedIngressCoordinatorV1(
            gate: resumeGate, store: resumeStore, clock: V915Clock()
        )
        let resumeTask = Task { try await resumeCoordinator.resumeAfterAuthentication() }
        await resumeStore.waitUntilPendingRead()
        await resumeGate.lock(reason: .returnedFromBackground)
        await resumeStore.releasePendingRead()
        do { _ = try await resumeTask.value; XCTFail("stale session resumed protected ingress") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .staleAttempt) }
        let readyEffects = await resumeStore.readyEffectCount
        XCTAssertEqual(readyEffects, 0)

        let authentication = V915GatedAuthenticationClient()
        let gate = AppAccessGateV1(
            setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)), authentication: authentication,
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(140), Self.id(141)])
        )
        let task = Task { await gate.authenticate(trigger: .unlock) }
        await authentication.waitUntilAttemptStarted()
        await gate.lock(reason: .returnedFromBackground)
        await authentication.finish(.authenticated)
        let staleOutcome = await task.value
        let lockedState = await gate.currentState()
        let cancelledIDs = await authentication.cancelledAttemptIDs
        XCTAssertEqual(staleOutcome, .interrupted)
        XCTAssertEqual(lockedState, .locked(reason: .returnedFromBackground))
        XCTAssertEqual(cancelledIDs, [Self.id(140)])

        let relaunched = AppAccessGateV1(
            setting: .value(DeviceLocalAppLockSettingV1(isEnabled: true)),
            authentication: V915AuthenticationClient(outcomes: []), clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(142)])
        )
        let relaunchedState = await relaunched.currentState()
        XCTAssertEqual(relaunchedState, .locked(reason: .coldLaunch))
        do { try await relaunched.requireContentAccess(); XCTFail("relaunch allowed locked content") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }

        let policy = AppLockNotificationCanonicalPolicyV1(
            policyID: "prior-policy", revision: 2, canonicalDigest: Self.digest(2)
        )
        let journal = try AppLockNotificationJournalV1(
            operationID: Self.id(143), targetEnabled: true, priorPolicy: policy,
            projections: [AppLockGenericNotificationV1(
                requestID: "generic-143", opaqueCorrelationToken: Self.digest(143),
                title: AppLockCopyV1.genericNotificationTitle, body: AppLockCopyV1.genericNotificationBody
            )], disposition: .interruptedRecoveryRequired
        )
        let first = V915NotificationStore(journal: journal)
        let firstEffect = try await first.applyGenericProjection(journal, authorization: try await v915Authorization(notifications: first, operationID: journal.operationID, targetEnabled: journal.targetEnabled))
        XCTAssertEqual(firstEffect, .genericProjectionApplied)
        let recovered = V915NotificationStore(journal: try await first.loadJournal(), applied: true)
        let recoveredEffect = try await recovered.applyGenericProjection(journal, authorization: try await v915Authorization(notifications: recovered, operationID: journal.operationID, targetEnabled: journal.targetEnabled))
        let recoveredMixed = await recovered.mixedPrivateAndGeneric
        let recoveredJournal = try await recovered.loadJournal()
        XCTAssertEqual(recoveredEffect, .genericProjectionAdopted)
        XCTAssertFalse(recoveredMixed)
        XCTAssertEqual(recoveredJournal?.priorPolicy, policy)

        let corpus = try Self.corpus()
        XCTAssertGreaterThanOrEqual(corpus.strings("interruptionBoundaries").count, 12)
        XCTAssertEqual(corpus.bool("recovery.zeroOrCompleteEffectsOnly"), true)
        XCTAssertEqual(corpus.bool("recovery.retryIsIdempotent"), true)
        XCTAssertEqual(corpus.bool("recovery.lateAuthenticationCannotUnlock"), true)

        let enableOperationID = Self.id(170)
        let concurrentPolicy = AppLockNotificationCanonicalPolicyV1(
            policyID: "concurrent-policy", revision: 1, canonicalDigest: Self.digest(170)
        )
        let concurrentJournal = try AppLockNotificationJournalV1(
            operationID: enableOperationID, targetEnabled: true, priorPolicy: concurrentPolicy,
            projections: [], disposition: .enablingPrepared
        )
        let concurrentNotifications = V915GatedNotificationStore(enableJournal: concurrentJournal)
        let concurrentSettings = V915SettingStore(value: nil)
        let concurrentLifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: concurrentSettings,
            authentication: V915AuthenticationClient(outcomes: [.authenticated]),
            ingressStore: V915IngressStore(), notifications: concurrentNotifications,
            clock: V915Clock(), identifiers: V915IDs(values: [Self.id(171), Self.id(172), Self.id(176)])
        )
        let enableTask = Task { try await concurrentLifecycle.enable(operationID: enableOperationID) }
        await concurrentNotifications.waitUntilEnablePrepared()
        do { try await concurrentLifecycle.erase(operationID: Self.id(173)); XCTFail("Erase overlapped enable") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .invalidTransition) }
        do { _ = try await concurrentLifecycle.disable(operationID: Self.id(174)); XCTFail("disable overlapped enable") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .invalidTransition) }
        await concurrentNotifications.releaseEnablePreparation()
        let enabledReceipt = try await enableTask.value
        XCTAssertTrue(enabledReceipt.enabled)
        try await concurrentLifecycle.erase(operationID: Self.id(175))
        let postRaceGate = await concurrentLifecycle.accessGate()
        let postRaceState = await postRaceGate.currentState()
        XCTAssertEqual(postRaceState, .disabled)

        let firstEnableAuthentication = V915GatedAuthenticationClient()
        let firstEnableLifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: V915SettingStore(value: nil), authentication: firstEnableAuthentication,
            ingressStore: V915IngressStore(), notifications: V915NotificationStore(journal: nil),
            clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(180), Self.id(181), Self.id(182), Self.id(183), Self.id(184)])
        )
        let interruptedEnable = Task {
            try await firstEnableLifecycle.enable(operationID: Self.id(179))
        }
        await firstEnableAuthentication.waitUntilAttemptCount(1)
        _ = try await firstEnableLifecycle.handle(.sceneBackground)
        await firstEnableAuthentication.finish(.authenticated)
        do { _ = try await interruptedEnable.value; XCTFail("background allowed first enable to complete") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let firstEnableGate = await firstEnableLifecycle.accessGate()
        let postBackgroundEnableState = await firstEnableGate.currentState()
        let firstEnableCancelled = await firstEnableAuthentication.cancelledAttemptIDs
        XCTAssertEqual(postBackgroundEnableState, .disabled)
        XCTAssertEqual(firstEnableCancelled, [Self.id(181)])
        let secondEnableAttempt = Task { await firstEnableGate.authenticate(trigger: .enableAppLock) }
        await firstEnableAuthentication.waitUntilAttemptCount(2)
        await firstEnableAuthentication.finish(.authenticated)
        let secondEnableOutcome = await secondEnableAttempt.value
        XCTAssertEqual(secondEnableOutcome, .authenticated)
    }

    func testV9_15R01EraseClearsDeviceLocalLockAndProtectedIngress() async throws {
        let settings = V915SettingStore(value: DeviceLocalAppLockSettingV1(isEnabled: true))
        let ingress = V915IngressStore()
        let now = V915Clock.value
        _ = try await ingress.stageContentBlind(
            ProtectedIngressStageRequestV1(
                intentID: Self.id(160), operationID: Self.id(161), kind: .share,
                byteCount: 64, receivedAt: now, expiresAt: now.addingTimeInterval(60)
            ), source: FileManager.default.temporaryDirectory.appendingPathComponent("opaque")
        )
        let policy = AppLockNotificationCanonicalPolicyV1(
            policyID: "erase-policy", revision: 3, canonicalDigest: Self.digest(3)
        )
        let journal = try AppLockNotificationJournalV1(
            operationID: Self.id(162), targetEnabled: true, priorPolicy: policy,
            projections: [AppLockGenericNotificationV1(
                requestID: "erase-request", opaqueCorrelationToken: Self.digest(162),
                title: AppLockCopyV1.genericNotificationTitle, body: AppLockCopyV1.genericNotificationBody
            )], disposition: .genericProjectionApplied
        )
        let notifications = V915NotificationStore(journal: journal)

        let lifecycle = try await AppLockLifecycleCoordinatorV1.bootstrap(
            setting: settings,
            authentication: V915AuthenticationClient(outcomes: []),
            ingressStore: ingress,
            notifications: notifications,
            clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(164), Self.id(165)])
        )
        try await lifecycle.erase(operationID: Self.id(163))
        let erasedSetting = await settings.readAppLockSetting()
        let erasedIntents = try await ingress.pendingIntents()
        let erasedJournal = try await notifications.loadJournal()
        let erasedResolution = try await notifications.resolveOpaqueTokenAfterAuthentication(Self.digest(162), now: now, authorization: try await v915ContentAuthorization())
        XCTAssertEqual(erasedSetting, .absentDisabled)
        XCTAssertEqual(erasedIntents, [])
        XCTAssertNil(erasedJournal)
        XCTAssertNil(erasedResolution)

        try await lifecycle.erase(operationID: Self.id(163))
        let settingEraseCount = await settings.eraseEffectCount
        let ingressEraseCount = await ingress.eraseEffectCount
        let notificationEraseCount = await notifications.eraseEffectCount
        XCTAssertEqual(settingEraseCount, 1)
        XCTAssertEqual(ingressEraseCount, 1)
        XCTAssertEqual(notificationEraseCount, 1)

        let gate = AppAccessGateV1(
            setting: await settings.readAppLockSetting(),
            authentication: V915AuthenticationClient(outcomes: []), clock: V915Clock(),
            identifiers: V915IDs(values: [Self.id(166)])
        )
        let erasedGateState = await gate.currentState()
        XCTAssertEqual(erasedGateState, .disabled)
        try await gate.requireContentAccess()
        let corpus = try Self.corpus()
        XCTAssertEqual(corpus.bool("erase.canRecallSharedFiles"), false)
        XCTAssertEqual(Set(corpus.strings("erase.clears")), Set([
            "DEVICE_LOCAL_SETTING", "GENERIC_NOTIFICATION_REQUESTS", "NOTIFICATION_CORRELATION_MAPPINGS",
            "NOTIFICATION_JOURNAL", "PENDING_LOCKED_EXTERNAL_INTENTS", "PROTECTED_INGRESS_STAGING",
            "UNLOCKED_FOREGROUND_SESSION",
        ]))
    }

    nonisolated fileprivate static func id(_ byte: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0x40, 0, 0, 0x80, 0, 0, 0, 0, 0,
                    UInt8(truncatingIfNeeded: byte >> 8), UInt8(truncatingIfNeeded: byte)))
    }

    nonisolated fileprivate static func digest(_ byte: Int) -> String {
        String(format: "%064x", byte)
    }

    private static func corpus() throws -> V915Corpus {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "V23P02C11AppLockLifecycleCorpusV1", withExtension: "json",
            subdirectory: "Fixtures/V23/AppLock"
        ))
        return try V915Corpus(data: Data(contentsOf: url))
    }
}

private struct V915Clock: ApplicationClock {
    static let value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { Self.value }
}

private final class V915IDs: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]
    init(values: [UUID]) { self.values = values }
    func makeID() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return SettingsValidationV1.zeroUUID }
        return values.removeFirst()
    }
}

private actor V915AuthenticationClient: LocalAuthenticationClient {
    private var outcomes: [LocalAuthenticationOutcomeV1]
    private var availabilityValue: LocalAuthenticationAvailabilityV1
    private(set) var attempts: [LocalAuthenticationAttemptV1] = []
    private var counts: [UUID: Int] = [:]
    private(set) var cancelledAttemptIDs: [UUID] = []

    init(outcomes: [LocalAuthenticationOutcomeV1], availabilityStatus: LocalAuthenticationAvailabilityStatusV1 = .available) {
        self.outcomes = outcomes
        availabilityValue = .systemValue(status: availabilityStatus, biometry: .faceID)
    }
    func availability() -> LocalAuthenticationAvailabilityV1 { availabilityValue }
    func setAvailability(_ status: LocalAuthenticationAvailabilityStatusV1) {
        availabilityValue = .systemValue(status: status, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        attempts.append(attempt); counts[attempt.attemptID, default: 0] += 1
        guard !outcomes.isEmpty else { return .unavailable }
        return outcomes.removeFirst()
    }
    func cancel(attemptID: UUID) { cancelledAttemptIDs.append(attemptID) }
    var maximumEvaluationCountPerAttempt: Int { counts.values.max() ?? 0 }
}

private actor V915GatedAuthenticationClient: LocalAuthenticationClient {
    private var attemptCount = 0
    private var awaitedAttemptCount = 0
    private var started: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<LocalAuthenticationOutcomeV1, Never>?
    private(set) var cancelledAttemptIDs: [UUID] = []
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 {
        attemptCount += 1
        if attemptCount >= awaitedAttemptCount { started?.resume(); started = nil }
        return await withCheckedContinuation { result = $0 }
    }
    func cancel(attemptID: UUID) { cancelledAttemptIDs.append(attemptID) }
    func waitUntilAttemptStarted() async { await waitUntilAttemptCount(1) }
    func waitUntilAttemptCount(_ value: Int) async {
        if attemptCount >= value { return }
        awaitedAttemptCount = value
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ outcome: LocalAuthenticationOutcomeV1) { result?.resume(returning: outcome); result = nil }
}

private actor V915AvailabilityGatedAuthenticationClient: LocalAuthenticationClient {
    private var didRequestAvailability = false
    private var requestedWaiter: CheckedContinuation<Void, Never>?
    private var availabilityContinuation: CheckedContinuation<LocalAuthenticationAvailabilityV1, Never>?
    private(set) var authenticationEvaluationCount = 0
    private(set) var cancelledAttemptIDs: [UUID] = []

    func availability() async -> LocalAuthenticationAvailabilityV1 {
        didRequestAvailability = true
        requestedWaiter?.resume()
        requestedWaiter = nil
        return await withCheckedContinuation { availabilityContinuation = $0 }
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        authenticationEvaluationCount += 1
        return .authenticated
    }
    func cancel(attemptID: UUID) { cancelledAttemptIDs.append(attemptID) }
    func waitUntilAvailabilityRequested() async {
        if didRequestAvailability { return }
        await withCheckedContinuation { requestedWaiter = $0 }
    }
    func releaseAvailability() {
        availabilityContinuation?.resume(returning: .systemValue(status: .available, biometry: .faceID))
        availabilityContinuation = nil
    }
}

private struct V915ContentCounters: Equatable, Sendable {
    static let zero = Self(parse: 0, preview: 0, index: 0, apply: 0, render: 0)
    let parse: Int; let preview: Int; let index: Int; let apply: Int; let render: Int
}

private actor V915IngressStore: ProtectedIngressStoreV1 {
    private var intents: [UUID: PendingLockedExternalIntentV1] = [:]
    private(set) var eraseEffectCount = 0
    let contentCounters = V915ContentCounters.zero
    func performBlindStartupHygiene(now: Date, operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try .init(operationID: operationID, inspectedCount: 0, removedKnownOwnedCount: 0,
                  retainedValidCount: 0, deferredAmbiguousCount: 0, contentRead: false)
    }
    func stageContentBlind(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> ProtectedIngressStageReceiptV1 {
        if let prior = intents[request.intentID] { return .init(intent: prior, disposition: .duplicateAdopted, adoptedExistingEffect: true) }
        let intent = try PendingLockedExternalIntentV1(
            intentID: request.intentID, operationID: request.operationID, kind: request.kind,
            opaqueStagingID: "opaque-\(request.intentID.uuidString.lowercased())", byteCount: request.byteCount,
            sha256: String(repeating: "a", count: 64), receivedAt: request.receivedAt,
            expiresAt: request.expiresAt, disposition: .stagedProtectedPendingAuthentication
        )
        intents[intent.intentID] = intent
        return .init(intent: intent, disposition: .stagedProtectedPendingAuthentication, adoptedExistingEffect: false)
    }
    func pendingIntents() -> [PendingLockedExternalIntentV1] { intents.values.sorted { $0.intentID.uuidString < $1.intentID.uuidString } }
    func markReadyForAuthenticatedValidation(intentID: UUID) throws -> PendingLockedExternalIntentV1 {
        guard let value = intents[intentID] else { throw AppAccessContractFailureV1.ingressNotFound }
        let ready = try PendingLockedExternalIntentV1(
            intentID: value.intentID, operationID: value.operationID, kind: value.kind,
            opaqueStagingID: value.opaqueStagingID, byteCount: value.byteCount, sha256: value.sha256,
            receivedAt: value.receivedAt, expiresAt: value.expiresAt,
            disposition: .readyForAuthenticatedValidation
        )
        intents[intentID] = ready
        return ready
    }
    func remove(intentID: UUID, disposition: LockedIngressDispositionV1) throws { intents.removeValue(forKey: intentID) }
    func eraseAllProtectedIngress(operationID: UUID) { if !intents.isEmpty { eraseEffectCount += 1 }; intents.removeAll() }
}

private actor V915IngressEffects: ProtectedIngressDurableEffectPortV1 {
    private var values: [UUID: PendingLockedExternalIntentV1] = [:]
    private var hygieneReceipt: ProtectedIngressStartupHygieneReceiptV1?
    private let removedCount: Int
    private let deferredCount: Int
    private(set) var eraseEffectCount = 0
    private(set) var eraseCallCount = 0
    let contentCounters = V915ContentCounters.zero
    init(
        initialValues: [PendingLockedExternalIntentV1] = [],
        removedCount: Int = 0,
        deferredCount: Int = 0
    ) {
        var seeded: [UUID: PendingLockedExternalIntentV1] = [:]
        for value in initialValues { seeded[value.intentID] = value }
        values = seeded
        self.removedCount = removedCount; self.deferredCount = deferredCount
    }
    func performBlindStartupHygieneEffect(now: Date, operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        let receipt = try ProtectedIngressStartupHygieneReceiptV1(
            operationID: operationID, inspectedCount: removedCount + deferredCount,
            removedKnownOwnedCount: removedCount, retainedValidCount: 0,
            deferredAmbiguousCount: deferredCount, contentRead: false
        )
        values.removeAll()
        for offset in 0..<deferredCount {
            let intentID = V9_15AppLockLifecycleTests.id(210 + offset)
            let value = try PendingLockedExternalIntentV1(
                intentID: intentID, operationID: V9_15AppLockLifecycleTests.id(220 + offset),
                kind: .document,
                opaqueStagingID: "opaque-\(intentID.uuidString.lowercased())",
                byteCount: 1, sha256: V9_15AppLockLifecycleTests.digest(210 + offset),
                receivedAt: now, expiresAt: now.addingTimeInterval(60),
                disposition: .deferredAmbiguousOwnership
            )
            values[intentID] = value
        }
        hygieneReceipt = receipt
        return receipt
    }
    func readBlindStartupHygieneReceiptEffect(operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        guard let hygieneReceipt, hygieneReceipt.operationID == operationID else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return hygieneReceipt
    }
    func loadPendingIntentsEffect() -> [PendingLockedExternalIntentV1] { Array(values.values) }
    func stageContentBlindEffect(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> PendingLockedExternalIntentV1 {
        let value = try PendingLockedExternalIntentV1(
            intentID: request.intentID, operationID: request.operationID, kind: request.kind,
            opaqueStagingID: "opaque-\(request.intentID.uuidString.lowercased())",
            byteCount: request.byteCount, sha256: String(repeating: "b", count: 64),
            receivedAt: request.receivedAt, expiresAt: request.expiresAt,
            disposition: .stagedProtectedPendingAuthentication
        )
        values[value.intentID] = value
        return value
    }
    func replacePendingIntentEffect(expected: PendingLockedExternalIntentV1, replacement: PendingLockedExternalIntentV1) throws {
        guard values[expected.intentID] == expected else { throw AppAccessContractFailureV1.effectMismatch }
        values[expected.intentID] = replacement
    }
    func removePendingIntentEffect(expected: PendingLockedExternalIntentV1, disposition: LockedIngressDispositionV1) throws {
        guard values[expected.intentID] == expected else { throw AppAccessContractFailureV1.effectMismatch }
        values.removeValue(forKey: expected.intentID)
    }
    func erasePendingIntentsEffect(operationID: UUID) { eraseCallCount += 1; eraseEffectCount += 1; values.removeAll() }
}

private actor V915ResumeGatedIngressStore: ProtectedIngressStoreV1 {
    private let intent: PendingLockedExternalIntentV1
    private var didRead = false
    private var readWaiter: CheckedContinuation<Void, Never>?
    private var readContinuation: CheckedContinuation<Void, Never>?
    private(set) var readyEffectCount = 0

    init(now: Date) throws {
        let intentID = V9_15AppLockLifecycleTests.id(134)
        intent = try PendingLockedExternalIntentV1(
            intentID: intentID,
            operationID: V9_15AppLockLifecycleTests.id(135), kind: .document,
            opaqueStagingID: "opaque-\(intentID.uuidString.lowercased())", byteCount: 10,
            sha256: V9_15AppLockLifecycleTests.digest(134), receivedAt: now,
            expiresAt: now.addingTimeInterval(60),
            disposition: .stagedProtectedPendingAuthentication
        )
    }
    func performBlindStartupHygiene(now: Date, operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try .init(operationID: operationID, inspectedCount: 1, removedKnownOwnedCount: 0,
                  retainedValidCount: 1, deferredAmbiguousCount: 0, contentRead: false)
    }
    func stageContentBlind(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> ProtectedIngressStageReceiptV1 {
        throw AppAccessContractFailureV1.invalidTransition
    }
    func pendingIntents() async -> [PendingLockedExternalIntentV1] {
        didRead = true; readWaiter?.resume(); readWaiter = nil
        await withCheckedContinuation { readContinuation = $0 }
        return [intent]
    }
    func markReadyForAuthenticatedValidation(intentID: UUID) throws -> PendingLockedExternalIntentV1 {
        readyEffectCount += 1
        return intent
    }
    func remove(intentID: UUID, disposition: LockedIngressDispositionV1) {}
    func eraseAllProtectedIngress(operationID: UUID) {}
    func waitUntilPendingRead() async {
        if didRead { return }
        await withCheckedContinuation { readWaiter = $0 }
    }
    func releasePendingRead() { readContinuation?.resume(); readContinuation = nil }
}

@MainActor private final class V915NotificationSystemProbe: NotificationSystemPortV1 {
    var requests: [NotificationSystemRequestV1] = []
    var sourceOpenCount = 0
    var observationCount = 0
    var beforeObservation: (@MainActor () async -> Void)?
    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }
    func observations() async throws -> [NotificationSystemObservationV1] {
        observationCount += 1
        await beforeObservation?()
        return requests.map { .init(requestID: $0.notification.requestID, request: $0, delivered: false) }
    }
    func add(_ request: NotificationSystemRequestV1) async throws { requests.append(request) }
    func remove(_ requestIDs: [String]) async throws { requests.removeAll { requestIDs.contains($0.notification.requestID) } }
}

// Legacy coordinator probes model control subjects; concrete owner tests use
// the actual descriptor-pinned control store and incumbent canonical reader.
nonisolated private func v915Subject(_ journal: AppLockNotificationJournalV1?) throws -> NotificationOperationSubjectV1? {
    try journal.map { try .init(journal: $0,
        settingWriteSHA256: CompatibilityCanonicalV1.sha256(try CompatibilityCanonicalV1.encode($0.priorPolicy))) }
}

nonisolated private func v915LocalConfiguration(_ journal: AppLockNotificationJournalV1?,
                                               _ setting: DeviceLocalAppLockSettingReadV1) -> Bool {
    guard let journal else { return setting == .absentDisabled || setting == .value(.init(isEnabled: false)) }
    guard case .value(let value) = setting, value.isEnabled == journal.targetEnabled else { return false }
    return journal.targetEnabled
        ? journal.disposition == .genericProjectionApplied || journal.disposition == .genericProjectionAdopted
        : journal.disposition == .priorPolicyRebuilt
}

@MainActor private func v915Authorization(notifications: any AppLockNotificationPrivacyPortV1,
                                        operationID: UUID, targetEnabled: Bool) async throws -> NotificationOperationAuthorizationV1 {
    try await v915Authorization(operationID: operationID, targetEnabled: targetEnabled,
        subject: notifications.loadAuthenticationSubject())
}

@MainActor private func v915Authorization(operationID: UUID, targetEnabled: Bool,
                                        subject: NotificationOperationSubjectV1? = nil) async throws -> NotificationOperationAuthorizationV1 {
    let gate = AppAccessGateV1(setting: .value(.init(isEnabled: !targetEnabled)),
        authentication: V915AuthenticationClient(outcomes: [.authenticated]), clock: V915Clock(),
        identifiers: V915IDs(values: [UUID(), UUID()]))
    guard await gate.authenticate(trigger: targetEnabled ? .enableAppLock : .disableAppLock) == .authenticated else {
        throw AppAccessContractFailureV1.accessDenied
    }
    return .init(gate: gate, proof: .toggle(try await gate.toggleAuthenticationToken(targetEnabled: targetEnabled),
        targetEnabled: targetEnabled), operationID: operationID, subject: subject)
}

@MainActor private func v915ContentAuthorization() async throws -> NotificationOperationAuthorizationV1 {
    let gate = AppAccessGateV1(setting: .absentDisabled, authentication: V915AuthenticationClient(outcomes: []),
        clock: V915Clock(), identifiers: V915IDs(values: []))
    return .init(gate: gate, proof: .content(try await gate.beginContentRead(for: .render)),
        operationID: UUID(), subject: nil)
}

private actor V915NotificationStore: AppLockNotificationPrivacyPortV1 {
    private var journal: AppLockNotificationJournalV1?
    private var applied = false
    private var authenticated = false
    private(set) var eraseEffectCount = 0
    init(journal: AppLockNotificationJournalV1?, applied: Bool = false) {
        self.journal = journal
        self.applied = applied
    }
    func loadJournal() -> AppLockNotificationJournalV1? { journal }
    func bindNotificationGate(_ gate: AppAccessGateV1) {}
    func loadAuthenticationSubject() throws -> NotificationOperationSubjectV1? { try v915Subject(journal) }
    func validatesLocalConfiguration(_ setting: DeviceLocalAppLockSettingReadV1) -> Bool { v915LocalConfiguration(journal, setting) }
    func prepareEnable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) throws -> AppLockNotificationJournalV1 { guard let journal else { throw AppAccessContractFailureV1.notificationReconciliationRequired }; return journal }
    func applyGenericProjection(_ journal: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1) -> AppLockNotificationPrivacyDispositionV1 { defer { applied = true }; return applied ? .genericProjectionAdopted : .genericProjectionApplied }
    func prepareDisable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) throws -> AppLockNotificationJournalV1 { guard let journal else { throw AppAccessContractFailureV1.notificationReconciliationRequired }; return journal }
    func rebuildPriorPolicy(_ journal: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1) -> AppLockNotificationPrivacyDispositionV1 { .priorPolicyRebuilt }
    func resolveOpaqueTokenAfterAuthentication(_ token: String, now: Date, authorization: NotificationOperationAuthorizationV1) -> String? { authenticated && journal?.projections.contains(where: { $0.opaqueCorrelationToken == token }) == true ? "opaque-route" : nil }
    func eraseNotificationsAndMappings(operationID: UUID) { if journal != nil { eraseEffectCount += 1 }; journal = nil; authenticated = false }
    func markAuthenticated() { authenticated = true }
    var mixedPrivateAndGeneric: Bool { false }
}

private actor V915NotificationEffects: AppLockNotificationEffectPortV1 {
    private var journal: AppLockNotificationJournalV1?
    private var policy: AppLockNotificationCanonicalPolicyV1
    private let projection: AppLockGenericNotificationV1
    private var disablePolicyOverride: AppLockNotificationCanonicalPolicyV1?
    private var enablePrepareCount = 0
    private var disablePrepareCount = 0
    private(set) var rebuildCount = 0
    private(set) var publishCount = 0
    private(set) var loadCount = 0
    private(set) var eraseEffectCount = 0
    private(set) var eraseCallCount = 0
    private let pausesPublication: Bool
    private var publicationStarted = false
    private var publicationWaiter: CheckedContinuation<Void, Never>?
    private var publicationContinuation: CheckedContinuation<Void, Never>?
    var prepareCounts: [Int] { [enablePrepareCount, disablePrepareCount] }
    init(policy: AppLockNotificationCanonicalPolicyV1, projection: AppLockGenericNotificationV1,
         disablePolicyOverride: AppLockNotificationCanonicalPolicyV1? = nil,
         initialJournal: AppLockNotificationJournalV1? = nil, pausesPublication: Bool = false) {
        self.policy = policy; self.projection = projection
        self.disablePolicyOverride = disablePolicyOverride
        journal = initialJournal
        self.pausesPublication = pausesPublication
    }
    func setCanonicalPolicy(_ value: AppLockNotificationCanonicalPolicyV1) { policy = value }
    func setDisablePolicyOverride(_ value: AppLockNotificationCanonicalPolicyV1?) {
        disablePolicyOverride = value
    }
    func loadJournalEffect() -> AppLockNotificationJournalV1? { loadCount += 1; return journal }
    func bindNotificationGateEffect(_ gate: AppAccessGateV1) {}
    func loadAuthenticationSubjectEffect() throws -> NotificationOperationSubjectV1? { try v915Subject(journal) }
    func validatesLocalConfigurationEffect(_ setting: DeviceLocalAppLockSettingReadV1) -> Bool { v915LocalConfiguration(journal, setting) }
    func replaceJournalForAuthenticationRace(_ value: AppLockNotificationJournalV1?) { journal = value }
    func waitUntilPublicationStarted() async {
        if publicationStarted { return }
        await withCheckedContinuation { publicationWaiter = $0 }
    }
    func releasePublication() { publicationContinuation?.resume(); publicationContinuation = nil }
    func prepareEnableEffect(operationID: UUID,
                             expectedPredecessor: AppLockNotificationJournalV1?, authorization: NotificationOperationAuthorizationV1) throws
        -> AppLockNotificationJournalV1 {
        guard journal == expectedPredecessor else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        if let journal, journal.operationID == operationID { return journal }
        enablePrepareCount += 1
        let value = try AppLockNotificationJournalV1(
            operationID: operationID, targetEnabled: true, priorPolicy: policy,
            projections: [projection], disposition: .enablingPrepared
        )
        journal = value; return value
    }
    func publishGenericEffect(expected: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        publishCount += 1
        if pausesPublication {
            publicationStarted = true
            publicationWaiter?.resume(); publicationWaiter = nil
            await withCheckedContinuation { publicationContinuation = $0 }
        }
        guard journal == expected else { throw AppAccessContractFailureV1.effectMismatch }
        let value = try AppLockNotificationJournalV1(
            operationID: expected.operationID, targetEnabled: true,
            priorPolicy: expected.priorPolicy, projections: expected.projections,
            disposition: expected.disposition == .enablingPrepared ? .genericProjectionApplied : .genericProjectionAdopted
        )
        journal = value; return value
    }
    func prepareDisableEffect(operationID: UUID,
                              expectedPredecessor: AppLockNotificationJournalV1?, authorization: NotificationOperationAuthorizationV1) throws
        -> AppLockNotificationJournalV1 {
        guard journal == expectedPredecessor else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        if let journal, journal.operationID == operationID { return journal }
        disablePrepareCount += 1
        let priorPolicy = disablePolicyOverride ?? expectedPredecessor?.priorPolicy ?? policy
        if let expectedPredecessor {
            guard priorPolicy == expectedPredecessor.priorPolicy else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        let value = try AppLockNotificationJournalV1(
            operationID: operationID, targetEnabled: false, priorPolicy: priorPolicy,
            projections: [], disposition: .disablingPrepared
        )
        journal = value; return value
    }
    func rebuildPriorPolicyEffect(expected: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1) throws -> AppLockNotificationJournalV1 {
        rebuildCount += 1
        guard journal == expected else { throw AppAccessContractFailureV1.effectMismatch }
        let value = try AppLockNotificationJournalV1(
            operationID: expected.operationID, targetEnabled: false,
            priorPolicy: expected.priorPolicy, projections: expected.projections,
            disposition: .priorPolicyRebuilt
        )
        journal = value; return value
    }
    func resolveOpaqueTokenEffect(_ token: String, now: Date, authorization: NotificationOperationAuthorizationV1) -> String? {
        token == projection.opaqueCorrelationToken ? "opaque-route" : nil
    }
    func eraseNotificationsAndMappingsEffect(operationID: UUID) { eraseCallCount += 1; eraseEffectCount += 1; journal = nil }
}

private actor V915GatedNotificationStore: AppLockNotificationPrivacyPortV1 {
    private var journal: AppLockNotificationJournalV1?
    private var didPrepare = false
    private var prepareWaiter: CheckedContinuation<Void, Never>?
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    init(enableJournal: AppLockNotificationJournalV1) { journal = nil; self.enableJournal = enableJournal }
    private let enableJournal: AppLockNotificationJournalV1
    func loadJournal() -> AppLockNotificationJournalV1? { journal }
    func bindNotificationGate(_ gate: AppAccessGateV1) {}
    func loadAuthenticationSubject() throws -> NotificationOperationSubjectV1? { try v915Subject(journal) }
    func validatesLocalConfiguration(_ setting: DeviceLocalAppLockSettingReadV1) -> Bool { v915LocalConfiguration(journal, setting) }
    func prepareEnable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) async throws -> AppLockNotificationJournalV1 {
        guard operationID == enableJournal.operationID else { throw AppAccessContractFailureV1.effectMismatch }
        didPrepare = true; prepareWaiter?.resume(); prepareWaiter = nil
        await withCheckedContinuation { prepareContinuation = $0 }
        journal = enableJournal
        return enableJournal
    }
    func applyGenericProjection(_ journal: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1) -> AppLockNotificationPrivacyDispositionV1 { .genericProjectionApplied }
    func prepareDisable(operationID: UUID, authorization: NotificationOperationAuthorizationV1) throws -> AppLockNotificationJournalV1 { throw AppAccessContractFailureV1.invalidTransition }
    func rebuildPriorPolicy(_ journal: AppLockNotificationJournalV1, authorization: NotificationOperationAuthorizationV1) -> AppLockNotificationPrivacyDispositionV1 { .priorPolicyRebuilt }
    func resolveOpaqueTokenAfterAuthentication(_ token: String, now: Date, authorization: NotificationOperationAuthorizationV1) -> String? { nil }
    func eraseNotificationsAndMappings(operationID: UUID) { journal = nil }
    func waitUntilEnablePrepared() async {
        if didPrepare { return }
        await withCheckedContinuation { prepareWaiter = $0 }
    }
    func releaseEnablePreparation() { prepareContinuation?.resume(); prepareContinuation = nil }
}

private actor V915SettingStore: DeviceLocalAppLockSettingPortV1 {
    private var value: DeviceLocalAppLockSettingV1?
    private let readOverride: DeviceLocalAppLockSettingReadV1?
    private(set) var eraseEffectCount = 0
    private(set) var eraseCallCount = 0
    private(set) var writeEffectCount = 0
    init(value: DeviceLocalAppLockSettingV1?, readOverride: DeviceLocalAppLockSettingReadV1? = nil) {
        self.value = value; self.readOverride = readOverride
    }
    func readAppLockSetting() -> DeviceLocalAppLockSettingReadV1 { readOverride ?? value.map(DeviceLocalAppLockSettingReadV1.value) ?? .absentDisabled }
    func writeAppLockSetting(_ value: DeviceLocalAppLockSettingV1, operationID: UUID, authorization: NotificationOperationAuthorizationV1) -> DeviceLocalAppLockSettingWriteReceiptV1 { writeEffectCount += 1; self.value = value; return .init(operationID: operationID, value: value, adoptedExistingEffect: false) }
    func eraseAppLockSetting(operationID: UUID) { eraseCallCount += 1; if value != nil { eraseEffectCount += 1 }; value = nil }
}

private struct V915Corpus {
    private let root: [String: Any]
    init(data: Data) throws { root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
    func value(_ path: String) -> Any? { path.split(separator: ".").reduce(root as Any?) { current, key in (current as? [String: Any])?[String(key)] } }
    func string(_ path: String) -> String? { value(path) as? String }
    func bool(_ path: String) -> Bool? { value(path) as? Bool }
    func strings(_ path: String) -> [String] { value(path) as? [String] ?? [] }
}

private struct C16PhysicalIngressClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct C16PhysicalIngressFixture {
    let root: URL
    let support: URL
    let source: URL
    let now: Date
    let bytes: Data
    var digest: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    init(byteCount: Int) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        support = root.appendingPathComponent("support", isDirectory: true)
        source = root.appendingPathComponent("external.bin")
        now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        bytes = Data((0..<byteCount).map { UInt8($0 % 251) })
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try bytes.write(to: source)
    }

    func request() -> ProtectedIngressStageRequestV1 {
        .init(intentID: UUID(), operationID: UUID(), kind: .document,
              byteCount: UInt64(bytes.count), receivedAt: now, expiresAt: now.addingTimeInterval(3_600))
    }

    func effects(at date: Date? = nil, failure: C16IngressMutationFailureInjectionV1 = .none) throws
        -> OwnedStorageLedgerProtectedIngressEffectV1 {
        let instant = date ?? now
        return try .init(applicationSupportURL: support, clock: { instant }, failureInjection: failure)
    }

    func payload(_ request: ProtectedIngressStageRequestV1) -> URL {
        support.appendingPathComponent("FieldEvidenceOperations/ScratchDataV1/import-" + request.intentID.uuidString.lowercased())
            .appendingPathComponent("opaque-data")
    }

    var scratchRoot: URL { support.appendingPathComponent("FieldEvidenceOperations/ScratchDataV1") }
    var controlRoot: URL { support.appendingPathComponent("FieldEvidenceOperations/ProtectedIngressReceiptsV1") }

    func scratch(at date: Date? = nil, failure: C16IngressMutationFailureInjectionV1 = .none) throws -> ScratchDataLeaseStoreV1 {
        let instant = date ?? now
        return try .init(applicationSupportURL: support, clock: { instant }, capacityProvider: { _ in Int64.max },
            ingressMutationFailureInjection: failure)
    }

    func leaseByteCount(_ request: ProtectedIngressStageRequestV1) throws -> UInt64 {
        let directory = payload(request).deletingLastPathComponent()
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).reduce(UInt64(0)) { total, name in
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            return total + (try XCTUnwrap(attributes[.size] as? NSNumber)).uint64Value
        }
    }

    func tamperPayloadPreservingMetadata(_ request: ProtectedIngressStageRequestV1) throws {
        let descriptor = Darwin.open(payload(request).path, O_RDWR | O_NOFOLLOW)
        guard descriptor >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        defer { _ = Darwin.close(descriptor) }
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        var byte: UInt8 = 0xff
        guard Darwin.pwrite(descriptor, &byte, 1, 0) == 1,
              Darwin.fsync(descriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        let times = [information.st_atimespec, information.st_mtimespec]
        guard times.withUnsafeBufferPointer({ Darwin.futimens(descriptor, $0.baseAddress) }) == 0 else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }

    func fileBytes(in directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: directory.path).map {
            ($0, try Data(contentsOf: directory.appendingPathComponent($0)))
        })
    }

    func ageFiles(in directory: URL, to date: Date) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.appendingPathComponent(name).path)
        }
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

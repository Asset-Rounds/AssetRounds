import Foundation
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_15AppLockLifecycleTests: XCTestCase {
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
        try await gate.setEnabledAfterAuthenticated(true)
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
        let lockedResolution = try await notifications.resolveOpaqueTokenAfterAuthentication(Self.digest(8), now: now)
        XCTAssertNil(lockedResolution)
        await notifications.markAuthenticated()
        let unlockedResolution = try await notifications.resolveOpaqueTokenAfterAuthentication(Self.digest(8), now: now)
        let applied = try await notifications.applyGenericProjection(journal)
        let adopted = try await notifications.applyGenericProjection(journal)
        let mixed = await notifications.mixedPrivateAndGeneric
        XCTAssertEqual(unlockedResolution, "opaque-route")
        XCTAssertEqual(applied, .genericProjectionApplied)
        XCTAssertEqual(adopted, .genericProjectionAdopted)
        XCTAssertFalse(mixed)

        let notificationEffects = V915NotificationEffects(policy: policy, projection: projection)
        let productionNotifications = AppLockNotificationPrivacyCoordinatorV1(effects: notificationEffects)
        let productionPrepared = try await productionNotifications.prepareEnable(operationID: Self.id(97))
        let productionApplied = try await productionNotifications.applyGenericProjection(productionPrepared)
        let productionAdopted = try await productionNotifications.applyGenericProjection(productionPrepared)
        XCTAssertEqual(productionApplied, .genericProjectionApplied)
        XCTAssertEqual(productionAdopted, .genericProjectionAdopted)
        let wrongSubject = try AppLockNotificationJournalV1(
            operationID: productionPrepared.operationID, targetEnabled: true,
            priorPolicy: productionPrepared.priorPolicy,
            projections: [AppLockGenericNotificationV1(
                requestID: "wrong-subject", opaqueCorrelationToken: Self.digest(98)
            )], disposition: .enablingPrepared
        )
        do { _ = try await productionNotifications.applyGenericProjection(wrongSubject); XCTFail("terminal journal adopted the wrong subject") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .effectMismatch) }
        try await productionNotifications.eraseNotificationsAndMappings(operationID: Self.id(99))
        let erasedProductionJournal = try await productionNotifications.loadJournal()
        XCTAssertNil(erasedProductionJournal)
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
        let ambiguousIngress = await ambiguousLifecycle.protectedIngress()
        let reconciled = try await ambiguousIngress.resumeAfterAuthentication()
        XCTAssertEqual(reconciled.count, 1)
        XCTAssertEqual(reconciled.first?.disposition, .readyForAuthenticatedValidation)
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
        let firstEffect = try await first.applyGenericProjection(journal)
        XCTAssertEqual(firstEffect, .genericProjectionApplied)
        let recovered = V915NotificationStore(journal: try await first.loadJournal(), applied: true)
        let recoveredEffect = try await recovered.applyGenericProjection(journal)
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
        let erasedResolution = try await notifications.resolveOpaqueTokenAfterAuthentication(Self.digest(162), now: now)
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
        UUID(uuid: (0, 0, 0, 0, 0, 0x40, 0, 0, 0x80, 0, 0, 0, 0,
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
    private let availabilityValue: LocalAuthenticationAvailabilityV1
    private(set) var attempts: [LocalAuthenticationAttemptV1] = []
    private var counts: [UUID: Int] = [:]
    private(set) var cancelledAttemptIDs: [UUID] = []

    init(outcomes: [LocalAuthenticationOutcomeV1], availabilityStatus: LocalAuthenticationAvailabilityStatusV1 = .available) {
        self.outcomes = outcomes
        availabilityValue = .systemValue(status: availabilityStatus, biometry: .faceID)
    }
    func availability() -> LocalAuthenticationAvailabilityV1 { availabilityValue }
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
    func erasePendingIntentsEffect(operationID: UUID) { values.removeAll() }
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
    func prepareEnable(operationID: UUID) throws -> AppLockNotificationJournalV1 { guard let journal else { throw AppAccessContractFailureV1.notificationReconciliationRequired }; return journal }
    func applyGenericProjection(_ journal: AppLockNotificationJournalV1) -> AppLockNotificationPrivacyDispositionV1 { defer { applied = true }; return applied ? .genericProjectionAdopted : .genericProjectionApplied }
    func prepareDisable(operationID: UUID) throws -> AppLockNotificationJournalV1 { guard let journal else { throw AppAccessContractFailureV1.notificationReconciliationRequired }; return journal }
    func rebuildPriorPolicy(_ journal: AppLockNotificationJournalV1) -> AppLockNotificationPrivacyDispositionV1 { .priorPolicyRebuilt }
    func resolveOpaqueTokenAfterAuthentication(_ token: String, now: Date) -> String? { authenticated && journal?.projections.contains(where: { $0.opaqueCorrelationToken == token }) == true ? "opaque-route" : nil }
    func eraseNotificationsAndMappings(operationID: UUID) { if journal != nil { eraseEffectCount += 1 }; journal = nil; authenticated = false }
    func markAuthenticated() { authenticated = true }
    var mixedPrivateAndGeneric: Bool { false }
}

private actor V915NotificationEffects: AppLockNotificationEffectPortV1 {
    private var journal: AppLockNotificationJournalV1?
    private let policy: AppLockNotificationCanonicalPolicyV1
    private let projection: AppLockGenericNotificationV1
    init(policy: AppLockNotificationCanonicalPolicyV1, projection: AppLockGenericNotificationV1) {
        self.policy = policy; self.projection = projection
    }
    func loadJournalEffect() -> AppLockNotificationJournalV1? { journal }
    func prepareEnableEffect(operationID: UUID) throws -> AppLockNotificationJournalV1 {
        let value = try AppLockNotificationJournalV1(
            operationID: operationID, targetEnabled: true, priorPolicy: policy,
            projections: [projection], disposition: .enablingPrepared
        )
        journal = value; return value
    }
    func publishGenericEffect(expected: AppLockNotificationJournalV1) throws -> AppLockNotificationJournalV1 {
        guard journal == expected else { throw AppAccessContractFailureV1.effectMismatch }
        let value = try AppLockNotificationJournalV1(
            operationID: expected.operationID, targetEnabled: true,
            priorPolicy: expected.priorPolicy, projections: expected.projections,
            disposition: .genericProjectionApplied
        )
        journal = value; return value
    }
    func prepareDisableEffect(operationID: UUID) throws -> AppLockNotificationJournalV1 {
        let value = try AppLockNotificationJournalV1(
            operationID: operationID, targetEnabled: false, priorPolicy: policy,
            projections: [], disposition: .disablingPrepared
        )
        journal = value; return value
    }
    func rebuildPriorPolicyEffect(expected: AppLockNotificationJournalV1) throws -> AppLockNotificationJournalV1 {
        guard journal == expected else { throw AppAccessContractFailureV1.effectMismatch }
        let value = try AppLockNotificationJournalV1(
            operationID: expected.operationID, targetEnabled: false,
            priorPolicy: expected.priorPolicy, projections: expected.projections,
            disposition: .priorPolicyRebuilt
        )
        journal = value; return value
    }
    func resolveOpaqueTokenEffect(_ token: String, now: Date) -> String? {
        token == projection.opaqueCorrelationToken ? "opaque-route" : nil
    }
    func eraseNotificationsAndMappingsEffect(operationID: UUID) { journal = nil }
}

private actor V915GatedNotificationStore: AppLockNotificationPrivacyPortV1 {
    private var journal: AppLockNotificationJournalV1?
    private var didPrepare = false
    private var prepareWaiter: CheckedContinuation<Void, Never>?
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    init(enableJournal: AppLockNotificationJournalV1) { journal = nil; self.enableJournal = enableJournal }
    private let enableJournal: AppLockNotificationJournalV1
    func loadJournal() -> AppLockNotificationJournalV1? { journal }
    func prepareEnable(operationID: UUID) async throws -> AppLockNotificationJournalV1 {
        guard operationID == enableJournal.operationID else { throw AppAccessContractFailureV1.effectMismatch }
        didPrepare = true; prepareWaiter?.resume(); prepareWaiter = nil
        await withCheckedContinuation { prepareContinuation = $0 }
        journal = enableJournal
        return enableJournal
    }
    func applyGenericProjection(_ journal: AppLockNotificationJournalV1) -> AppLockNotificationPrivacyDispositionV1 { .genericProjectionApplied }
    func prepareDisable(operationID: UUID) throws -> AppLockNotificationJournalV1 { throw AppAccessContractFailureV1.invalidTransition }
    func rebuildPriorPolicy(_ journal: AppLockNotificationJournalV1) -> AppLockNotificationPrivacyDispositionV1 { .priorPolicyRebuilt }
    func resolveOpaqueTokenAfterAuthentication(_ token: String, now: Date) -> String? { nil }
    func eraseNotificationsAndMappings(operationID: UUID) { journal = nil }
    func waitUntilEnablePrepared() async {
        if didPrepare { return }
        await withCheckedContinuation { prepareWaiter = $0 }
    }
    func releaseEnablePreparation() { prepareContinuation?.resume(); prepareContinuation = nil }
}

private actor V915SettingStore: DeviceLocalAppLockSettingPortV1 {
    private var value: DeviceLocalAppLockSettingV1?
    private(set) var eraseEffectCount = 0
    init(value: DeviceLocalAppLockSettingV1?) { self.value = value }
    func readAppLockSetting() -> DeviceLocalAppLockSettingReadV1 { value.map(DeviceLocalAppLockSettingReadV1.value) ?? .absentDisabled }
    func writeAppLockSetting(_ value: DeviceLocalAppLockSettingV1, operationID: UUID) -> DeviceLocalAppLockSettingWriteReceiptV1 { self.value = value; return .init(operationID: operationID, value: value, adoptedExistingEffect: false) }
    func eraseAppLockSetting(operationID: UUID) { if value != nil { eraseEffectCount += 1 }; value = nil }
}

private struct V915Corpus {
    private let root: [String: Any]
    init(data: Data) throws { root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
    func value(_ path: String) -> Any? { path.split(separator: ".").reduce(root as Any?) { current, key in (current as? [String: Any])?[String(key)] } }
    func string(_ path: String) -> String? { value(path) as? String }
    func bool(_ path: String) -> Bool? { value(path) as? Bool }
    func strings(_ path: String) -> [String] { value(path) as? [String] ?? [] }
}

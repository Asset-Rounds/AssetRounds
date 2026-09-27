import Darwin
import Combine
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_S6_6EraseRecoveryTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_S6_6EraseRecoveryTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

private struct S66EraseReceiptClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

private final class S66EraseReceiptIDs: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]
    init(_ values: [UUID]) { self.values = values }
    func makeID() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? UUID() : values.removeFirst()
    }
}

private actor S66EraseReceiptAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .unavailable }
    func cancel(attemptID: UUID) {}
}

fileprivate actor S66ColdEraseAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

final class C45EraseRecoveryCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityLeavesNoDurableRenderScratch() {
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies, ["AcceptedLabelGenerationSnapshotRow"])
        XCTAssertTrue(AssetLabelPersistenceEnrollmentV1.derivedFamilies.contains("LabelProjectionResultV1"))
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("LabelProjectedArtifactV1"))
    }
}

final class C30EvidenceContextAnchorS6_6EraseRecovery: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S6_6EraseRecoveryTests: XCTestCase {
    @MainActor fileprivate static var retainedS6ColdOwners:
        [(URL, StartupRouter, AppAccessGateV1)] = []
    @MainActor private static var retainedKernelAbortOwners:
        [(URL, StartupRouter, ProductionAppAccessSessionV1, AppAccessPresentationV1)] = []
    /// A Service may own a pinned intent/control descriptor even when its
    /// operation is terminal. Keep the exact original and cold copies alive
    /// through every checked-close or refusal outcome.
    @MainActor private static var retainedS6EraseServices:
        [(URL, EraseAllService)] = []

    @MainActor
    private final class WeakKernelSourceAliases {
        weak var context: ModelContext?
        weak var container: ModelContainer?
        init(_ context: ModelContext) {
            self.context = context
            container = context.container
        }
        var drained: Bool { context == nil && container == nil }
    }

    @MainActor
    private func startKernelColdOwner(_ harness: Harness,
        service: EraseAllService) async throws -> StoreSessionCoordinator {
        try await startKernelColdOwner(root: harness.root, support: harness.support,
            service: service)
    }

    @MainActor
    private func startKernelColdOwner(root: URL, support: URL,
        service: EraseAllService) async throws -> StoreSessionCoordinator {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: S66ColdEraseAuthentication(),
            clock: SystemApplicationClock(), identifiers: SystemApplicationIDSource())
        guard await gate.authenticate(trigger: .unlock) == .authenticated else {
            throw FixtureError.invalid
        }
        let router = StartupRouter(applicationSupportURL: support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: profiles)
        // Retain the new cold owner and its root even if startup refuses.
        Self.retainedS6ColdOwners.append((root, router, gate))
        Self.retainedS6EraseServices.append((root, service))
        try router.bindStartupAccessGate(gate)
        try await router.retryColdEraseForTesting(service: service, accessGate: gate)
        guard case let .ready(coordinator, _, _) = router.route else {
            throw FixtureError.invalid
        }
        return coordinator
    }

    @MainActor
    func testSeededEraseFixtureRejectsLaterDirectMutationWithoutCheckpointAdoption() async throws {
        let harness = try await makeHarness("checkpoint-drift")
        defer { cleanup(harness) }
        let coordinator = try XCTUnwrap(harness.coordinator)
        let context = coordinator.modelContext
        context.insert(Site(
            id: uuid("66000000-0000-0000-0000-000000000901"),
            label: "Unadopted erase fixture site",
            address: nil,
            timeZoneID: "UTC",
            createdAt: Date(timeIntervalSince1970: 1_786_800_901)
        ))
        try context.save()

        let journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID,
            allowStateBootstrap: false
        )
        XCTAssertThrowsError(try journal.validateAll()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
    }

    @MainActor
    func testActualEraseRetainsGenerationAndPreferencesUntilNotificationAbsenceIsVerified() async throws {
        var diagnosticPhase = "harness"
        do {
            let harness = try await makeHarness("notification-readback", observePhase: { diagnosticPhase = $0 })
            defer { cleanup(harness) }
            var coordinator: StoreSessionCoordinator? = try XCTUnwrap(harness.coordinator)
            let oldID = try XCTUnwrap(coordinator).generationID
            let owner = harness.originalOwner
            try await owner.admit(coordinator: try XCTUnwrap(coordinator))
            let eraseOperation = try owner.originalOperationForInterruption()
            let preferences = PreferencesAdapterV1(defaults: harness.defaults)
            let policy = try preferences.readReminderPolicy()
            diagnosticPhase = "prepare-notification-control"
            let control = try AppLockNotificationControlStoreV1(applicationSupportURL: harness.support, preferences: preferences)
            let operation = UUID()
            let request = NotificationSystemRequestV1(notification: .init(requestID: UUID().uuidString.lowercased(),
                opaqueCorrelationToken: String(repeating: "a", count: 64)), fireAtUTC: Date().addingTimeInterval(600))
            let journal = try AppLockNotificationJournalV1(operationID: operation, targetEnabled: true,
                priorPolicy: policy.appLockReference(), projections: [request.notification], disposition: .enablingPrepared)
            let plan = try preferences.planAppLockSettingWrite(expectedSetting: preferences.readAppLockSettingSnapshot(),
                expectedReminderPolicy: policy, target: .init(isEnabled: true), operationID: operation)
            let prepared = try control.prepareControl(journal: journal, priorReminderPolicy: policy,
                settingWrite: plan, expectedPredecessor: nil)
            harness.defaults.set("retain-until-notifications-cleared", forKey: "notification-erase-sentinel")
            let system = S66NotificationSystemProbe(requests: [request])
            let service = try owner.configure(EraseAllService(applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches, temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults, bundleIdentifier: bundleID,
                defaultsDomainName: harness.defaultsSuiteName, notificationSystem: system,
                admitErase: { try await owner.admitSubject($0) }))
            service.enableOriginalColdExitWitnessForTesting = true
            Self.retainedS6EraseServices.append((harness.root, service))
            service.erasePhaseDiagnosticForTesting = { diagnosticPhase = $0 }
            diagnosticPhase = "erase-with-unverified-notification-removal"
            var activationFailure: Error?
            do {
                _ = try await service.erase(
                    confirmation: "ERASE",
                    coordinator: try XCTUnwrap(coordinator),
                    diagnosticsStore: harness.diagnostics,
                    operation: eraseOperation,
                    activate: { [weak coordinator, weak router = owner.router] session in
                        do {
                            guard let coordinator, let router else {
                                throw FixtureError.invalid
                            }
                            try router.activateErasePreparationSession(
                                session, coordinator: coordinator,
                                operation: eraseOperation)
                        } catch {
                            activationFailure = error
                        }
                    })
                XCTFail("an ignored OS removal completed Erase")
            } catch {
                recordReminderEraseDiagnostic(error, method: "testActualEraseRetainsGenerationAndPreferencesUntilNotificationAbsenceIsVerified", phase: diagnosticPhase, enabled: true)
                /* The retained intent and bytes below are the recovery proof. */
            }
            XCTAssertNil(activationFailure)
            XCTAssertGreaterThan(system.observationCount, 0)
            XCTAssertTrue(fileManager.fileExists(atPath: harness.factory.installedGenerationURL(id: oldID).path))
            XCTAssertEqual(harness.defaults.string(forKey: "notification-erase-sentinel"), "retain-until-notifications-cleared")
            XCTAssertEqual(try control.loadControl(), prepared)
            XCTAssertThrowsError(try control.requireNotificationPublicationAllowed())
            let retained = try XCTUnwrap(EraseIntentStore(applicationSupportURL: harness.support).load())
            XCTAssertEqual(retained.phase, .sessionActivated)
            try await owner.router.beginNotificationRefusalEraseColdRestartForTesting(
                eraseOperation, originalService: service)
            coordinator = nil
            harness.coordinator = nil
            try owner.router.finishNotificationRefusalEraseColdRestartForTesting(
                eraseOperation)
            system.removalEnabled = true
            let recovery = EraseAllService(applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches, temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults, bundleIdentifier: bundleID,
                defaultsDomainName: harness.defaultsSuiteName, notificationSystem: system)
            recovery.erasePhaseDiagnosticForTesting = { diagnosticPhase = $0 }
            diagnosticPhase = "startup-reconcile-after-notification-removal"
            let recovered = try await startKernelColdOwner(harness, service: recovery)
            diagnosticPhase = "post-recovery-assertions"
            XCTAssertEqual(recovered.generationID, retained.newGenerationID)
            XCTAssertTrue(system.requests.isEmpty)
            XCTAssertFalse(fileManager.fileExists(atPath: harness.factory.installedGenerationURL(id: oldID).path))
            XCTAssertNil(harness.defaults.object(forKey: "notification-erase-sentinel"))
            XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: harness.support))
            XCTAssertThrowsError(try control.requireNotificationPublicationAllowed())
        } catch {
            recordReminderEraseDiagnostic(error, method: "testActualEraseRetainsGenerationAndPreferencesUntilNotificationAbsenceIsVerified", phase: diagnosticPhase, enabled: true)
            throw error
        }
    }

    @MainActor
    func testNotificationPreferenceEraseFencePreservesExactCooldownAndRejectsHeldSettingAuthority() async throws {
        let suite = "S6_6.notification-control." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let policy = try preferences.readReminderPolicy()
        let heldPlan = try preferences.planAppLockSettingWrite(expectedSetting: preferences.readAppLockSettingSnapshot(),
            expectedReminderPolicy: policy, target: .init(isEnabled: true), operationID: UUID())
        let eraseID = UUID(), erasedAt = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertFalse(try preferences.preparePreferencesForCompletedErase(operationID: eraseID, persistentDomainName: suite))
        XCTAssertThrowsError(try preferences.applyAppLockSettingWrite(heldPlan))
        XCTAssertNil(try preferences.readStoredReminderPolicy())
        let rating = try RatingEligibilityCoordinatorV1(store: preferences,
            nativeRequest: AppStoreRatingRequestAdapterV1(), clock: SystemApplicationClock())
        let original = try await rating.applyCompletedErase(eraseOperationID: eraseID, erasedAt: erasedAt)
        let bytes = try XCTUnwrap(defaults.persistentDomain(forName: suite)) as NSDictionary
        XCTAssertEqual(bytes.count, 1)
        XCTAssertTrue(try preferences.preparePreferencesForCompletedErase(operationID: eraseID, persistentDomainName: suite))
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, bytes)
        let retry = try await rating.applyCompletedErase(eraseOperationID: eraseID,
            erasedAt: erasedAt.addingTimeInterval(10_000))
        XCTAssertEqual(retry.suppressUntil, original.suppressUntil)
        XCTAssertEqual(retry.receipt.stateSHA256, original.receipt.stateSHA256)
        defaults.set("foreign preference", forKey: "notification-test-foreign")
        XCTAssertFalse(try preferences.preparePreferencesForCompletedErase(operationID: eraseID, persistentDomainName: suite))
        XCTAssertNil(try preferences.readStoredReminderPolicy())
        XCTAssertThrowsError(try preferences.applyAppLockSettingWrite(heldPlan))
        let replacement = try preferences.readReminderPolicy()
        XCTAssertNotEqual(replacement.instanceID, policy.instanceID)
        XCTAssertThrowsError(try preferences.applyAppLockSettingWrite(heldPlan))
        XCTAssertEqual(try preferences.readStoredReminderPolicy(), replacement)
        XCTAssertNil(try preferences.readAppLockSettingSnapshot().storedEnvelope)
    }

    func testCompleteKernelEraseMappingsValidateWithoutDroppingRegistrations() throws {
        try KernelDeletionEraseRegistryV4.validate()
        XCTAssertEqual(KernelDeletionEraseRegistryV4.registrations.map(\.kind),
                       KernelPersistenceV4RecordKind.allCases.sorted())
        var incomplete = KernelDeletionEraseRegistryV4.registrations
        incomplete.removeLast()
        XCTAssertThrowsError(try KernelDeletionEraseRegistryV4.validate(incomplete))
        try C04ShopReportProfileKernelDeletionEraseEnrollmentV1.validate()
    }

    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    private let fileManager = FileManager.default
    private let bundleID = "com.palatis3.fieldrecord"

    @MainActor
    func testCompletedEraseReceiptUsesActualIDsAndOnlyPublishesAfterEraseRootRemoval() async throws {
        let harness = try await makeHarness("completed-receipt")
        defer { cleanup(harness) }
        let owner = harness.originalOwner
        let newGenerationID = uuid("66000000-0000-0000-0000-000000000701")
        let eraseID = uuid("66000000-0000-0000-0000-000000000702")
        var supportStatus = stat()
        XCTAssertEqual(harness.support.path.withCString {
            lstat($0, &supportStatus)
        }, 0)
        var received: CompletedEraseReceiptV1?
        var admittedReservation: AppAccessGateV1.EraseAdoptionToken?
        try await { @MainActor () async throws -> Void in
            let coordinator = try XCTUnwrap(harness.coordinator)
            try await owner.admit(coordinator: coordinator)
            let operation = try owner.originalOperationForInterruption()
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID,
                defaultsDomainName: harness.defaultsSuiteName,
                makeUUID: sequence([newGenerationID, eraseID]),
                admitErase: { subject in
                    let reservation = try await owner.admitSubject(subject)
                    admittedReservation = reservation
                    return reservation
                },
                didCompleteErase: { receipt in
                    XCTAssertFalse(self.fileManager.fileExists(atPath: harness.support
                        .appendingPathComponent("FieldEvidenceErase").path))
                    XCTAssertTrue((try? EraseIntentStore.completedCleanupRootIsAbsent(
                        applicationSupportURL: harness.support)) == true)
                    XCTAssertFalse(self.fileManager.fileExists(atPath: harness.support
                        .appendingPathComponent("FieldEvidenceErase").path))
                    received = receipt
                }
            ))
            Self.retainedS6EraseServices.append((harness.root, service))
            var activationFailure: Error?
            let prepared = try await service.erase(
                confirmation: "ERASE", coordinator: coordinator,
                diagnosticsStore: harness.diagnostics, operation: operation
            ) { [weak coordinator] session in
                do {
                    guard let coordinator else { throw V23EraseOperationHarnessV1.Failure.activation }
                    try owner.router.activateErasePreparationSession(
                        session, coordinator: coordinator, operation: operation
                    )
                } catch { activationFailure = error }
            }
            if let activationFailure { throw activationFailure }
            XCTAssertTrue(prepared.operation === operation)
            XCTAssertEqual(try EraseIntentStore(applicationSupportURL: harness.support)
                .load()?.phase, .sessionActivated)
            XCTAssertNil(received)
            harness.coordinator = nil
        }()
        try await owner.completeCleanup()

        let receipt = try XCTUnwrap(received)
        XCTAssertEqual(receipt.subject.eraseID, eraseID)
        XCTAssertEqual(receipt.subject.newGenerationID, newGenerationID)
        XCTAssertEqual(receipt.subject.applicationSupportURL, harness.support.standardizedFileURL)
        XCTAssertEqual(receipt.subject.applicationSupportDevice, Int64(supportStatus.st_dev))
        XCTAssertEqual(receipt.subject.applicationSupportInode, UInt64(supportStatus.st_ino))
        XCTAssertEqual(receipt.reservation, try XCTUnwrap(admittedReservation))
        try await owner.adoptCompletedReceipt()
    }

    @MainActor
    func testFaultedEraseNeverPublishesCompletedReceipt() async throws {
        let harness = try await makeHarness("faulted-receipt")
        defer { cleanup(harness) }
        let owner = harness.originalOwner
        var completionCount = 0
        weak var originalContext: ModelContext?
        weak var originalContainer: ModelContainer?
        try await { @MainActor () async throws -> Void in
            let coordinator = try XCTUnwrap(harness.coordinator)
            originalContext = coordinator.modelContext
            originalContainer = coordinator.modelContext.container
            try await owner.admit(coordinator: coordinator)
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID,
                defaultsDomainName: harness.defaultsSuiteName,
                failureInjection: EraseAllFailureInjection(failOnceAt: .beforeJournalRemoval),
                admitErase: { try await owner.admitSubject($0) },
                didCompleteErase: { _ in completionCount += 1 }
            ))
            Self.retainedS6EraseServices.append((harness.root, service))
            try await owner.prepareCompatibility(
                service: service, confirmation: "ERASE",
                coordinator: coordinator, diagnostics: harness.diagnostics
            )
            harness.coordinator = nil
        }()
        let drained = expectation(for: NSPredicate { _, _ in
            originalContext == nil && originalContainer == nil
        }, evaluatedWith: NSObject())
        await fulfillment(of: [drained], timeout: 30)
        XCTAssertNil(originalContext)
        XCTAssertNil(originalContainer)
        let operation = try owner.originalOperationForInterruption()
        await XCTAssertThrowsErrorAsync {
            _ = try await operation.advanceCleanup()
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
        }
        XCTAssertEqual(completionCount, 0)
        XCTAssertNotNil(try EraseIntentStore(applicationSupportURL: harness.support).load())
    }

    @MainActor
    func testAdmissionRevalidationFailureAbortsExactGateReservationWithoutEraseEffect() async throws {
        let harness = try await makeHarness("abort-revalidation")
        defer { cleanup(harness) }
        let coordinator = try XCTUnwrap(harness.coordinator)
        let oldID = coordinator.generationID
        let owner = harness.originalOwner
        try await owner.admit(coordinator: coordinator)
        let operation = try owner.originalOperationForInterruption()
        var reservation: AppAccessGateV1.EraseAdoptionToken?
        var aborts = [AbortedEraseAdmissionReceiptV1]()
        var completions = 0
        let service = try owner.configure(EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            defaultsDomainName: harness.defaultsSuiteName,
            admitErase: { subject in
                let token = try await owner.admitSubject(subject)
                reservation = token
                coordinator.modelContext.insert(Site(label: "admission changed"))
                return token
            },
            didCompleteErase: { _ in completions += 1 },
            didAbortEraseAdmission: { aborts.append($0) }
        ))
        Self.retainedS6EraseServices.append((harness.root, service))
        var activationFailure: Error?
        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "ERASE", coordinator: coordinator,
                diagnosticsStore: harness.diagnostics, operation: operation,
                activate: { [weak coordinator] session in
                    do {
                        guard let coordinator else { throw V23EraseOperationHarnessV1.Failure.activation }
                        try owner.router.activateErasePreparationSession(
                            session, coordinator: coordinator, operation: operation
                        )
                    } catch { activationFailure = error }
                }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .contextHasChanges)
        }
        XCTAssertNil(activationFailure)
        XCTAssertEqual(aborts.count, 1)
        let abort = try XCTUnwrap(aborts.first)
        XCTAssertEqual(abort.reservation, reservation)
        XCTAssertEqual(abort.originalGenerationID, oldID)
        XCTAssertEqual(completions, 0)
        XCTAssertNil(try EraseIntentStore(applicationSupportURL: harness.support).load())
        XCTAssertNil(try EraseIntentStore(applicationSupportURL: harness.support).loadPreparation())
        XCTAssertEqual(try harness.factory.currentGenerationID(), oldID)
        coordinator.modelContext.rollback()
    }

    @MainActor
    func testRolledBackPreparationAbortsExactGateReservationButDurableIntentDoesNot() async throws {
        for (point, expectsAbort) in [
            (EraseAllFailurePoint.afterEmptyGenerationDirectoryCreate, true),
            (EraseAllFailurePoint.afterPreparedWrite, false),
        ] {
            let harness = try await makeHarness("abort-\(point)")
            defer { cleanup(harness) }
            let coordinator = try XCTUnwrap(harness.coordinator)
            let owner = harness.originalOwner
            try await owner.admit(coordinator: coordinator)
            let operation = try owner.originalOperationForInterruption()
            var reservation: AppAccessGateV1.EraseAdoptionToken?
            var aborts = [AbortedEraseAdmissionReceiptV1]()
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: harness.support, cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary, userDefaults: harness.defaults,
                bundleIdentifier: bundleID, defaultsDomainName: harness.defaultsSuiteName,
                failureInjection: EraseAllFailureInjection(failOnceAt: point),
                admitErase: { subject in
                    let token = try await owner.admitSubject(subject)
                    reservation = token
                    return token
                },
                didAbortEraseAdmission: { aborts.append($0) }
            ))
            Self.retainedS6EraseServices.append((harness.root, service))
            var activationFailure: Error?
            await XCTAssertThrowsErrorAsync {
                _ = try await service.erase(confirmation: "ERASE", coordinator: coordinator,
                    diagnosticsStore: harness.diagnostics, operation: operation,
                    activate: { [weak coordinator] session in
                        do {
                            guard let coordinator else { throw V23EraseOperationHarnessV1.Failure.activation }
                            try owner.router.activateErasePreparationSession(
                                session, coordinator: coordinator, operation: operation
                            )
                        } catch { activationFailure = error }
                    })
            } verify: { error in XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure) }
            XCTAssertNil(activationFailure)
            XCTAssertEqual(aborts.count, expectsAbort ? 1 : 0)
            if expectsAbort {
                XCTAssertEqual(aborts.first?.reservation, reservation)
                XCTAssertNil(try EraseIntentStore(applicationSupportURL: harness.support).load())
                XCTAssertNil(try EraseIntentStore(applicationSupportURL: harness.support).loadPreparation())
            } else {
                XCTAssertNotNil(try EraseIntentStore(applicationSupportURL: harness.support).load())
            }
        }
    }

    @MainActor
    func testAbsentApplicationSupportHasNoEraseAuthority() async throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_6-absent-support-\(UUID().uuidString)",
            isDirectory: true
        )
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(
            at: caches,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: root) }

        let recovered = try await EraseAllService(
            applicationSupportURL: support,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary
        ).reconcileAtStartup(
            diagnosticsStore: DiagnosticsStore(applicationSupportURL: support)
        )

        XCTAssertNil(recovered)
        XCTAssertFalse(fileManager.fileExists(atPath: support.path))
    }

    @MainActor
    private func seedGoldenMutationEvidence(
        coordinator: StoreSessionCoordinator,
        diagnostic: (String) -> Void
    ) throws {
        diagnostic("authority-source")
        let authoritySource = try C40BackupLifecycleTestValues.source(
            workspace: coordinator.workspaceIdentity.workspaceID.rawValue
        )
        let authoritySourceRow = try AuthoritySourceReleaseRow(authoritySource)
        coordinator.modelContext.insert(authoritySourceRow)
        let persistedAuthoritySource = try authoritySourceRow.value()
        coordinator.modelContext.insert(EntityMutationRevisionRow(
            identity: try WorkspaceEntityIdentityV1(
                kind: .authoritySourceRelease,
                id: persistedAuthoritySource.releaseID
            ),
            revision: persistedAuthoritySource.revision
        ))
        diagnostic("journal-adoption")
        let journal = try MutationJournalStoreV1(
            modelContext: coordinator.modelContext,
            identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID,
            allowStateBootstrap: false
        )
        try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
        try coordinator.modelContext.save()
        try journal.validateAll()
        XCTAssertEqual(
            try coordinator.modelContext.fetchCount(FetchDescriptor<AuthoritySourceReleaseRow>()),
            1
        )
        let mutationID = try MutationIDV1(rawValue: uuid(
            "66000000-0000-0000-0000-000000000100"
        ))
        let writer = coordinator.workspaceWriter
        diagnostic("writer-revision")
        let beforeMutation = try writer.currentRevision()
        let eraseSiteIdentity = try WorkspaceEntityIdentityV1(
            kind: .site,
            id: uuid("66000000-0000-0000-0000-000000000001")
        )
        let mutationExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: beforeMutation.workspaceID,
            generationID: beforeMutation.generationID,
            writerInstanceID: beforeMutation.writerInstanceID,
            workspaceRevision: beforeMutation.revision,
            entityRevisions: [.init(identity: eraseSiteIdentity, revision: 0)]
        )
        diagnostic("writer-execute")
        _ = try writer.execute(WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: mutationExpected,
            command: .updateSiteTimeZone(.init(
                siteID: uuid("66000000-0000-0000-0000-000000000001"),
                timeZoneID: "UTC",
                confirmedAt: Date(timeIntervalSince1970: 1_786_800_010)
            ))
        ))
        XCTAssertNotNil(try writer.durableReceipt(mutationID: mutationID))
    }

    @MainActor
    func testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState() async throws {
        try verifyCompletedCleanupProbe()
        var diagnosticPhase = "harness"
        defer { print("EraseGolden.exit phase=" + diagnosticPhase) }
        let harness = try await makeHarness("golden", observePhase: { diagnosticPhase = $0 })
        defer { cleanup(harness) }
        let owner = harness.originalOwner
        let newID = uuid("66000000-0000-0000-0000-000000000101")
        let erasedCustomerSentinel = "customer-only-before-erase"
        var completedReceipts = [CompletedEraseReceiptV1]()
        let (oldID, oldWriterID) = try await { @MainActor () async throws -> (UUID, UUID) in
            let coordinator = try XCTUnwrap(harness.coordinator)
            let oldID = coordinator.generationID
            let retiredWriter = coordinator.workspaceWriter
            let oldWriterID = try retiredWriter.currentRevision().writerInstanceID
            try seedGoldenMutationEvidence(coordinator: coordinator) { diagnosticPhase = $0 }
            diagnosticPhase = "diagnostic-seed"
            try await harness.diagnostics.recordOperationalFailure(try OperationalFailureV1(
                code: .interrupted,
                occurredAt: Date(timeIntervalSince1970: 1_786_800_011)
            ))
            let diagnosticBeforeErase = try await harness.diagnostics.operationalSupportSnapshot()
            XCTAssertEqual(diagnosticBeforeErase.health.failures.count, 1)
            weak var endedScratchOwner: ScratchDataLeaseStoreV1?
            // Finish the real producer without releasing/deleting its durable
            // scratch lease. Erase must still remove that abandoned payload.
            let residualScratch = try await { @MainActor () async throws -> URL in
                diagnosticPhase = "scratch-open"
                let scratch = try ScratchDataLeaseStoreV1(
                    applicationSupportURL: harness.support,
                    clock: { Date(timeIntervalSince1970: 1_786_800_012) },
                    capacityProvider: { _ in Int64.max }
                )
                let scratchRequest = try ScratchDataLeaseRequestV1(
                    leaseID: uuid("66000000-0000-0000-0000-000000000103"),
                    purpose: .supportExport,
                    owner: .supportExport,
                    ownerOperationID: uuid("66000000-0000-0000-0000-000000000104"),
                    requestedByteCount: 16,
                    createdAt: Date(timeIntervalSince1970: 1_786_800_012),
                    expiresAt: Date(timeIntervalSince1970: 1_786_800_912)
                )
                diagnosticPhase = "scratch-acquire"
                let scratchLease = try await scratch.acquireScratchLease(scratchRequest)
                diagnosticPhase = "scratch-write"
                let payload = try await scratch.writeScratchData(
                    Data("erase scratch".utf8), named: "support.json", lease: scratchLease
                )
                // A genuinely active producer must exclude an exclusive root owner.
                let probe = Darwin.open(harness.support.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                XCTAssertGreaterThanOrEqual(probe, 0)
                if probe >= 0 {
                    let result = withExtendedLifetime(scratch) { flock(probe, LOCK_EX | LOCK_NB) }
                    let failure = errno
                    if result == 0 { XCTAssertEqual(flock(probe, LOCK_UN), 0) }
                    XCTAssertEqual(Darwin.close(probe), 0)
                    XCTAssertEqual(result, -1)
                    XCTAssertEqual(failure, EWOULDBLOCK)
                }
                endedScratchOwner = scratch
                return payload
            }()
            XCTAssertNil(endedScratchOwner)
            XCTAssertEqual(try Data(contentsOf: residualScratch), Data("erase scratch".utf8))
            harness.defaults.set(erasedCustomerSentinel, forKey: "customer-sentinel")
            try await owner.admit(coordinator: coordinator)
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID,
                defaultsDomainName: harness.defaultsSuiteName,
                makeUUID: sequence([
                    newID,
                    uuid("66000000-0000-0000-0000-000000000102"),
                ]),
                admitErase: { try await owner.admitSubject($0) },
                didCompleteErase: { completedReceipts.append($0) }
            ))
            Self.retainedS6EraseServices.append((harness.root, service))
            service.erasePhaseDiagnosticForTesting = { diagnosticPhase = "service." + $0 }
            diagnosticPhase = "service-erase"
            try await owner.prepareCompatibility(service: service,
                confirmation: "ERASE", coordinator: coordinator,
                diagnostics: harness.diagnostics)
            XCTAssertThrowsError(try retiredWriter.currentRevision())
            harness.coordinator = nil
            return (oldID, oldWriterID)
        }()
        XCTAssertTrue(completedReceipts.isEmpty)
        try await owner.completeCleanup()
        XCTAssertEqual(completedReceipts.count, 1)
        XCTAssertEqual(completedReceipts.first?.subject.newGenerationID, newID)
        diagnosticPhase = "erase-postconditions"
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent("FieldEvidenceErase").path
        ))
        assertAuxiliaryRootsCleared(harness)
        let handedOffManifest = harness.support.appendingPathComponent("FieldEvidenceData/erase-current-manifest.json")
        diagnosticPhase = "handoff-bytes"
        let erasedManifestBytes = try Data(contentsOf: handedOffManifest)
        diagnosticPhase = "handoff-identity"
        let erasedManifestIdentity = try regularFileIdentity(handedOffManifest)
        let pointerURL = harness.support.appendingPathComponent("FieldEvidenceData/current.json")
        diagnosticPhase = "pointer-bytes"
        let erasedPointerBytes = try Data(contentsOf: pointerURL)
        try await owner.adoptCompletedReceipt()
        try await owner.activateFreshOrdinarySession()
        guard case let .ready(fresh, _, _) = owner.router.route else {
            return XCTFail("Golden Erase must publish a fresh ordinary owner")
        }
        XCTAssertEqual(fresh.generationID, newID)
        XCTAssertNotEqual(try fresh.workspaceWriter.currentRevision().writerInstanceID, oldWriterID)
        diagnosticPhase = "factory-current-id"
        XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
        diagnosticPhase = "factory-retired-ids"
        XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [])
        diagnosticPhase = "empty-row-counts"
        XCTAssertEqual(
            try counts(fresh.modelContext),
            [0, 0, 0, 0, 0, 0, 0]
        )
        XCTAssertEqual(
            try fresh.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            0
        )
        XCTAssertEqual(
            try fresh.modelContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
            0
        )
        XCTAssertEqual(
            try fresh.modelContext.fetchCount(FetchDescriptor<EntityMutationRevisionRow>()),
            0
        )
        XCTAssertEqual(
            try fresh.modelContext.fetchCount(FetchDescriptor<AuthoritySourceReleaseRow>()),
            0
        )
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<RequirementBasisBindingRow>()), 0)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<ApplicabilityContextSnapshotRow>()), 0)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<AssessmentScopeSnapshotRow>()), 0)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<SeverityScaleReleaseRow>()), 0)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<FindingClassificationBindingRow>()), 0)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<MeasurementProtocolReleaseRow>()), 0)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()), 0)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<DerivedFactProvenanceRow>()), 0)
        diagnosticPhase = "diagnostic-readback"
        let diagnosticsAfterErase = await harness.diagnostics.snapshot()
        XCTAssertEqual(diagnosticsAfterErase, .zero)
        diagnosticPhase = "diagnostics-readback"
        let operationalAfterErase = try await harness.diagnostics.operationalSupportSnapshot()
        XCTAssertEqual(operationalAfterErase.schemaVersion, 2)
        XCTAssertEqual(operationalAfterErase.counters, .zero)
        XCTAssertTrue(operationalAfterErase.health.failures.isEmpty)
        let diagnosticsURL = harness.support
            .appendingPathComponent("FieldEvidenceDiagnostics", isDirectory: true)
            .appendingPathComponent("counters.json")
        let persistedBytes = try Data(contentsOf: diagnosticsURL)
        // The retained owner resets its in-memory health timestamp separately.
        // Read physical canonical bytes through the actual reopened disk owner.
        let reopenedDiagnostics = DiagnosticsStore(applicationSupportURL: harness.support)
        let canonicalV3Bytes = try await reopenedDiagnostics
            .canonicalOperationalSupportEnvelopeDataV3()
        XCTAssertEqual(persistedBytes, canonicalV3Bytes)
        let persistedEnvelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: persistedBytes) as? [String: Any]
        )
        XCTAssertEqual(
            (persistedEnvelope["schemaVersion"] as? NSNumber)?.intValue,
            3
        )
        let persistedCounters = try XCTUnwrap(
            persistedEnvelope["counters"] as? [String: Any]
        )
        let counterEncoder = JSONEncoder()
        counterEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expectedCounters = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: counterEncoder.encode(DiagnosticsV1.zero)
            ) as? [String: Any]
        )
        XCTAssertEqual(persistedCounters as NSDictionary, expectedCounters as NSDictionary)
        XCTAssertNil(persistedEnvelope["feedbackDraft"])
        XCTAssertEqual(
            (persistedEnvelope["feedbackDraftRecoveryRequired"] as? NSNumber)?.boolValue,
            false
        )
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support
                .appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
                .appendingPathComponent("ScratchDataV1", isDirectory: true).path
        ))
        // A fresh adapter represents relaunch: Erase may retain only its
        // customer-free installation cooldown, never the old Defaults domain.
        diagnosticPhase = "defaults-readback"
        let relaunchedDefaults = try XCTUnwrap(
            UserDefaults(suiteName: harness.defaultsSuiteName)
        )
        let reloadedRatingStore = PreferencesAdapterV1(defaults: relaunchedDefaults)
        guard case .current(let ratingLedger) = try await reloadedRatingStore.load(),
              case .erasedCooldown(let erasedAt, let suppressUntil) = ratingLedger.origin else {
            return XCTFail("Erase must persist an ERASED_COOLDOWN ledger")
        }
        XCTAssertTrue(ratingLedger.attempts.isEmpty)
        XCTAssertEqual(
            suppressUntil.timeIntervalSince(erasedAt),
            RatingEligibilityPolicyV1.eraseCooldownSeconds,
            accuracy: 0.001
        )
        let remainingDefaults = relaunchedDefaults.persistentDomain(
            forName: harness.defaultsSuiteName
        ) ?? [:]
        XCTAssertEqual(Set(remainingDefaults.keys), Set(["rating-eligibility.v1"]))
        let ratingBytes = try XCTUnwrap(
            remainingDefaults["rating-eligibility.v1"] as? Data
        )
        let ratingText = String(decoding: ratingBytes, as: UTF8.self)
        XCTAssertFalse(ratingText.contains(erasedCustomerSentinel))
        XCTAssertFalse(ratingText.contains(oldID.uuidString.lowercased()))
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.factory.installedGenerationURL(id: oldID).path
        ))
        diagnosticPhase = "published-owner-readback"
        // The Router's post-adoption publication is the genuine fresh owner.
        // Physical pointer/manifest reads below add no second store lease.
        XCTAssertEqual(fresh.generationID, newID)
        let pointer = try harness.factory.currentGenerationPointerV3(expectedGenerationID: newID)
        diagnosticPhase = "manifest-readback"
        let manifest = try StoreMigrationJournalStoreV1(applicationSupportURL: harness.support)
            .loadManifest(targetGenerationID: newID, expectedDigest: pointer.generationManifestSHA256)
        let restoredManifestURL = manifestURL(harness, generationID: newID)
        XCTAssertEqual(try Data(contentsOf: restoredManifestURL), erasedManifestBytes)
        XCTAssertEqual(try regularFileIdentity(restoredManifestURL), erasedManifestIdentity)
        XCTAssertEqual(try Data(contentsOf: pointerURL), erasedPointerBytes)
        XCTAssertFalse(fileManager.fileExists(atPath: handedOffManifest.path))
        let marker = try XCTUnwrap(fresh.modelContext.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>()).first)
        XCTAssertEqual(pointer.storeSchemaVersion, 53)
        XCTAssertEqual(manifest.storeSchemaRelease, .v53)
        XCTAssertEqual(marker.schemaVersion, 53)
        XCTAssertEqual(marker.releaseID, PersistentSchemaReleaseV1.v53.compatibilityID)
        XCTAssertEqual(marker.predecessorReleaseID, PersistentSchemaReleaseV1.v52.compatibilityID)
        XCTAssertEqual(marker.migrationID, manifest.migrationID)
        XCTAssertEqual(fresh.workspaceIdentity.workspaceID.rawValue.uuidString.lowercased(),
            pointer.workspaceID)
        XCTAssertEqual(fresh.workspaceIdentity.replicaID.rawValue.uuidString.lowercased(),
            pointer.replicaID)
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<LightingNightWorkflowRowV1>()), 0)
        XCTAssertEqual(try counts(fresh.modelContext), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(
            try fresh.modelContext.fetchCount(FetchDescriptor<AuthoritySourceReleaseRow>()),
            0
        )
        // The original writer was rejected before source aliases drained.
        // After actual cleanup, receipt adoption publishes a distinct writer.
        XCTAssertNoThrow(try fresh.workspaceWriter.currentRevision())
        diagnosticPhase = "complete"
    }

    @MainActor
    private func verifyCompletedCleanupProbe() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S66-completed-cleanup-probe-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let erased = root.appendingPathComponent("FieldEvidenceErase", isDirectory: true)

        XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: root))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), [])

        try fileManager.createDirectory(at: erased, withIntermediateDirectories: false)
        XCTAssertFalse(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: root))
        let pending = erased.appendingPathComponent(".preparation.json.next")
        let pendingBytes = Data("untrusted pending authority".utf8)
        try pendingBytes.write(to: pending)
        XCTAssertFalse(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: root))
        XCTAssertEqual(try Data(contentsOf: pending), pendingBytes)
        try fileManager.removeItem(at: erased)

        let regularBytes = Data("unexpected regular entry".utf8)
        try regularBytes.write(to: erased)
        XCTAssertFalse(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: root))
        XCTAssertEqual(try Data(contentsOf: erased), regularBytes)
        try fileManager.removeItem(at: erased)

        let missing = root.appendingPathComponent("missing-target")
        try fileManager.createSymbolicLink(at: erased, withDestinationURL: missing)
        XCTAssertFalse(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: root))
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: erased.path), missing.path)
        XCTAssertFalse(fileManager.fileExists(atPath: missing.path))
        try fileManager.removeItem(at: erased)
        XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: root))

        let alias = root.appendingPathComponent("support-alias")
        try fileManager.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertThrowsError(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: alias))
        XCTAssertThrowsError(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: missing))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), ["support-alias"])
    }

    @MainActor
    func testEraseManifestHandoffPreservesExactInodeAndSupportsRepeatedConstructorRecovery() async throws {
        let harness = try await makeHarness("manifest-handoff")
        defer { cleanup(harness) }
        let generationID = try XCTUnwrap(harness.coordinator).generationID
        let pointerURL = harness.support.appendingPathComponent("FieldEvidenceData/current.json")
        let sidecarURL = harness.support.appendingPathComponent("FieldEvidenceData/erase-current-manifest.json")
        let sourceURL = manifestURL(harness, generationID: generationID)
        let pointerBytes = try Data(contentsOf: pointerURL)
        let manifestBytes = try Data(contentsOf: sourceURL)
        let identity = try regularFileIdentity(sourceURL)
        let pointer = try harness.factory.currentGenerationPointerV3(expectedGenerationID: generationID)

        for attempt in 0..<2 {
            let store = try StoreMigrationJournalStoreV1(applicationSupportURL: harness.support)
            XCTAssertThrowsError(try store.preserveCurrentManifestForErase(expectedGenerationID: UUID()))
            XCTAssertEqual(try Data(contentsOf: sourceURL), manifestBytes)
            XCTAssertFalse(fileManager.fileExists(atPath: sidecarURL.path))
            try store.preserveCurrentManifestForErase(expectedGenerationID: generationID)
            XCTAssertFalse(fileManager.fileExists(atPath: sourceURL.path))
            XCTAssertEqual(try Data(contentsOf: sidecarURL), manifestBytes)
            XCTAssertEqual(try regularFileIdentity(sidecarURL), identity)
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBytes)
            XCTAssertThrowsError(try store.preserveCurrentManifestForErase(expectedGenerationID: generationID))
            if attempt == 1 {
                // An exact already-restored target is an idempotent completion,
                // while the conflicting target case below must remain denied.
                try manifestBytes.write(to: sourceURL)
            }
            let recovered = try StoreMigrationJournalStoreV1(applicationSupportURL: harness.support)
            XCTAssertEqual(try recovered.loadManifest(targetGenerationID: generationID,
                expectedDigest: pointer.generationManifestSHA256).generationID, generationID)
            XCTAssertEqual(try Data(contentsOf: sourceURL), manifestBytes)
            if attempt == 0 { XCTAssertEqual(try regularFileIdentity(sourceURL), identity) }
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBytes)
            XCTAssertFalse(fileManager.fileExists(atPath: sidecarURL.path))
        }
        let reopened = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, generationID)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    func testEraseManifestHandoffRejectsHostileSidecarsTargetsAndChangedPointerWithoutConsumption() async throws {
        let harness = try await makeHarness("manifest-hostile")
        defer { cleanup(harness) }
        let generationID = try XCTUnwrap(harness.coordinator).generationID
        let pointerURL = harness.support.appendingPathComponent("FieldEvidenceData/current.json")
        let sidecarURL = harness.support.appendingPathComponent("FieldEvidenceData/erase-current-manifest.json")
        let sourceURL = manifestURL(harness, generationID: generationID)
        let heldURL = harness.root.appendingPathComponent("held-manifest.json")
        let pointerBytes = try Data(contentsOf: pointerURL)
        let manifestBytes = try Data(contentsOf: sourceURL)
        let malformed = Data("{partial-manifest".utf8)

        for scenario in ["partial-sidecar", "conflicting-target", "symlink-sidecar", "hardlink-sidecar",
                         "symlink-target", "hardlink-target", "changed-pointer"] {
            let store = try StoreMigrationJournalStoreV1(applicationSupportURL: harness.support)
            try store.preserveCurrentManifestForErase(expectedGenerationID: generationID)
            switch scenario {
            case "partial-sidecar":
                try malformed.write(to: sidecarURL)
            case "conflicting-target":
                try malformed.write(to: sourceURL)
            case "symlink-sidecar":
                try fileManager.moveItem(at: sidecarURL, to: heldURL)
                try fileManager.createSymbolicLink(at: sidecarURL, withDestinationURL: heldURL)
            case "hardlink-sidecar":
                try fileManager.linkItem(at: sidecarURL, to: heldURL)
            case "symlink-target":
                try manifestBytes.write(to: heldURL)
                try fileManager.createSymbolicLink(at: sourceURL, withDestinationURL: heldURL)
            case "hardlink-target":
                try manifestBytes.write(to: heldURL)
                try fileManager.linkItem(at: heldURL, to: sourceURL)
            case "changed-pointer":
                var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: pointerBytes) as? [String: Any])
                changed["generationID"] = UUID().uuidString.lowercased()
                try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes])
                    .write(to: pointerURL)
            default:
                throw FixtureError.invalid
            }
            let hostilePointer = try Data(contentsOf: pointerURL)
            let hostileSidecar = try Data(contentsOf: sidecarURL)
            XCTAssertThrowsError(try StoreMigrationJournalStoreV1(applicationSupportURL: harness.support), scenario)
            XCTAssertEqual(try Data(contentsOf: pointerURL), hostilePointer, scenario)
            XCTAssertEqual(try Data(contentsOf: sidecarURL), hostileSidecar, scenario)
            if scenario == "conflicting-target" {
                XCTAssertEqual(try Data(contentsOf: sourceURL), malformed)
                try fileManager.removeItem(at: sourceURL)
            } else if scenario == "symlink-target" || scenario == "hardlink-target" {
                XCTAssertEqual(try Data(contentsOf: sourceURL), manifestBytes)
                XCTAssertEqual(try Data(contentsOf: heldURL), manifestBytes)
                if scenario == "symlink-target" {
                    XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: sourceURL.path), heldURL.path)
                }
                try fileManager.removeItem(at: sourceURL)
                try fileManager.removeItem(at: heldURL)
            } else {
                XCTAssertFalse(fileManager.fileExists(atPath: sourceURL.path), scenario)
            }
            if scenario == "symlink-sidecar" {
                XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: sidecarURL.path), heldURL.path)
                try fileManager.removeItem(at: sidecarURL)
                try fileManager.moveItem(at: heldURL, to: sidecarURL)
            } else if scenario == "hardlink-sidecar" {
                XCTAssertEqual(try Data(contentsOf: heldURL), manifestBytes)
                try fileManager.removeItem(at: heldURL)
            } else if scenario == "partial-sidecar" {
                try manifestBytes.write(to: sidecarURL)
            }
            try pointerBytes.write(to: pointerURL)
            _ = try StoreMigrationJournalStoreV1(applicationSupportURL: harness.support)
            XCTAssertEqual(try Data(contentsOf: sourceURL), manifestBytes)
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBytes)
            XCTAssertFalse(fileManager.fileExists(atPath: sidecarURL.path))
        }
        XCTAssertEqual(try harness.factory.openOrBootstrapCurrent().generationID, generationID)
    }

    @MainActor
    func testRetainedLiveContextDefersCleanupUntilColdRecovery() async throws {
        var diagnosticPhase = "harness"
        do {
            let harness = try await makeHarness("deferred-drain", diagnoseInitialOpen: true,
                observePhase: { diagnosticPhase = $0 })
            // The deliberately edited original remains pinned after the
            // physical-identity refusal; test teardown cannot unlink it.
            var coordinator: StoreSessionCoordinator? = try XCTUnwrap(harness.coordinator)
            let oldID = try XCTUnwrap(coordinator).generationID
            let owner = harness.originalOwner
            try await owner.admit(coordinator: try XCTUnwrap(coordinator))
            let eraseOperation = try owner.originalOperationForInterruption()
            let newID = uuid("66000000-0000-0000-0000-000000000111")
            var retainedContext: ModelContext? = try XCTUnwrap(coordinator).modelContext
            // ModelContext does not keep its ModelContainer alive. The added
            // retained-source checks need both until their final read completes.
            var retainedContainer: ModelContainer? =
                try XCTUnwrap(coordinator).modelContext.container
            var initialCompletionCount = 0
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID,
                makeUUID: sequence([
                    newID,
                    uuid("66000000-0000-0000-0000-000000000112"),
                ]),
                admitErase: { try await owner.admitSubject($0) },
                didCompleteErase: { _ in initialCompletionCount += 1 }
            ))
            service.enableOriginalColdExitWitnessForTesting = true
            Self.retainedS6EraseServices.append((harness.root, service))
            service.erasePhaseDiagnosticForTesting = { diagnosticPhase = $0 }

            diagnosticPhase = "erase-with-retained-context"
            var activationFailure: Error?
            let outcome = try await service.erase(
                confirmation: "ERASE",
                coordinator: try XCTUnwrap(coordinator),
                diagnosticsStore: harness.diagnostics,
                operation: eraseOperation,
                activate: { [weak coordinator, weak router = owner.router] session in
                    do {
                        guard let coordinator, let router else {
                            throw FixtureError.invalid
                        }
                        try router.activateErasePreparationSession(
                            session, coordinator: coordinator,
                            operation: eraseOperation)
                    } catch {
                        activationFailure = error
                    }
                })
            if let activationFailure { throw activationFailure }

            diagnosticPhase = "post-erase-assertions"
            XCTAssertTrue(outcome.operation === eraseOperation)
            XCTAssertTrue(outcome.operation.detached)
            XCTAssertTrue(outcome.operation.hasPreparedCleanup)
            XCTAssertEqual(try XCTUnwrap(coordinator).generationID, newID)
            let preparedContext = try XCTUnwrap(coordinator).modelContext
            XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
            XCTAssertTrue(fileManager.fileExists(atPath:
                harness.factory.installedGenerationURL(id: oldID).path
            ))
            let pending = try XCTUnwrap(try EraseIntentStore(
                applicationSupportURL: harness.support
            ).load())
            XCTAssertEqual(pending.phase, .sessionActivated)
            XCTAssertEqual(initialCompletionCount, 0)

            diagnosticPhase = "authenticated-retained-summary"
            do {
                let oldContext = try XCTUnwrap(retainedContext)
                let authority = try harness.factory.makeRestoreGenerationAuthority()
                let validation = try EraseRetainedSourceValidationV1.acquire(
                    intent: pending, generationFactory: harness.factory, authority: authority
                )
                XCTAssertEqual(validation.generationRootURL,
                    harness.factory.installedGenerationURL(id: oldID))
                _ = try BackupRestoreService.retainedEraseSummary(
                    modelContext: oldContext, validation: validation
                )
                XCTAssertThrowsError(try BackupRestoreService.currentSummary(
                    modelContext: oldContext,
                    generationRootURL: validation.generationRootURL
                )) { error in
                    XCTAssertEqual(error as? BackupExportServiceError, .invalidGeneration)
                }
                XCTAssertThrowsError(try validation.revalidate(
                    modelContext: preparedContext
                ))
                XCTAssertThrowsError(try EraseRetainedSourceValidationV1.acquire(
                    intent: pending.advancing(to: .cleanupComplete),
                    generationFactory: harness.factory, authority: authority
                ))

                let ledgerRows = try oldContext.fetch(FetchDescriptor<DeletionLedgerRow>())
                XCTAssertEqual(ledgerRows.count, 1)
                let ledgerRow = try XCTUnwrap(ledgerRows.first)
                let originalDeletionDate = ledgerRow.deletedAt
                let originalLedger = try DeletionLedgerStore(context: oldContext)
                    .snapshot().canonicalData()
                do {
                    defer {
                        ledgerRow.deletedAt = originalDeletionDate
                        try? oldContext.save()
                    }
                    ledgerRow.deletedAt = originalDeletionDate.addingTimeInterval(1)
                    try oldContext.save()
                    XCTAssertFalse(oldContext.hasChanges)
                    XCTAssertThrowsError(try validation.revalidate(modelContext: oldContext)) {
                        error in
                        XCTAssertEqual(error as? BackupExportServiceError, .invalidGeneration)
                    }
                    XCTAssertEqual(ledgerRow.deletedAt,
                        originalDeletionDate.addingTimeInterval(1))
                }
                XCTAssertFalse(oldContext.hasChanges)
                XCTAssertEqual(try DeletionLedgerStore(context: oldContext)
                    .snapshot().canonicalData(), originalLedger)

                let sourceManifestURL = manifestURL(harness, generationID: oldID)
                let currentPointerURL = harness.support
                    .appendingPathComponent("FieldEvidenceData/current.json")
                let manifestBefore = try Data(contentsOf: sourceManifestURL)
                let pointerBefore = try Data(contentsOf: currentPointerURL)
                for url in [sourceManifestURL, currentPointerURL] {
                    let original = try Data(contentsOf: url)
                    let hostile = Data("{invalid-retained-authority".utf8)
                    do {
                        defer { try? original.write(to: url) }
                        try hostile.write(to: url)
                        XCTAssertThrowsError(try EraseRetainedSourceValidationV1.acquire(
                            intent: pending, generationFactory: harness.factory,
                            authority: authority
                        ))
                        XCTAssertThrowsError(try BackupRestoreService.retainedEraseSummary(
                            modelContext: oldContext, validation: validation
                        ))
                        XCTAssertEqual(try Data(contentsOf: url), hostile)
                    }
                    XCTAssertEqual(try Data(contentsOf: url), original)
                }
                XCTAssertEqual(try Data(contentsOf: sourceManifestURL), manifestBefore)
                XCTAssertEqual(try Data(contentsOf: currentPointerURL), pointerBefore)
                XCTAssertEqual(try EraseIntentStore(
                    applicationSupportURL: harness.support
                ).load(), pending)
                XCTAssertFalse(oldContext.hasChanges)
                XCTAssertFalse(preparedContext.hasChanges)
                try validation.revalidate(modelContext: oldContext)
            }

            diagnosticPhase = "same-root-physical-identity-refusal"
            let beforeRefusalFiles = try tree(harness.support)
            let beforeRefusalDefaults =
                harness.defaults.persistentDomain(
                    forName: harness.defaultsSuiteName) as NSDictionary?
            XCTAssertThrowsError(
                try owner.router.beginPristinePreparedEraseColdRestartForTesting(
                    eraseOperation, originalService: service)
            ) { error in
                XCTAssertEqual(error as? EraseAllServiceError,
                    .invalidAuthority)
            }
            XCTAssertEqual(initialCompletionCount, 0)
            XCTAssertEqual(try EraseIntentStore(
                applicationSupportURL: harness.support).load(), pending)
            XCTAssertEqual(try tree(harness.support), beforeRefusalFiles)
            XCTAssertEqual(harness.defaults.persistentDomain(
                forName: harness.defaultsSuiteName) as NSDictionary?,
                beforeRefusalDefaults)
            XCTAssertTrue(try owner.router.eraseRetirementOperation(
                for: owner.originalTicketForInterruption())
                === eraseOperation)
            XCTAssertTrue(fileManager.fileExists(atPath:
                harness.factory.installedGenerationURL(id: oldID).path))

            // A second genuine original owner proves positive cold recovery
            // without adopting bytes after an intervening hostile rewrite.
            let pristine = try await makeHarness("deferred-drain-pristine",
                diagnoseInitialOpen: true,
                observePhase: { diagnosticPhase = $0 })
            defer { cleanup(pristine) }
            let pristineOwner = pristine.originalOwner
            var pristineCoordinator: StoreSessionCoordinator? =
                try XCTUnwrap(pristine.coordinator)
            let pristineOldID = try XCTUnwrap(pristineCoordinator).generationID
            let pristineNewID = uuid("66000000-0000-0000-0000-000000000113")
            var pristineContext: ModelContext? =
                try XCTUnwrap(pristineCoordinator).modelContext
            var pristineContainer: ModelContainer? =
                try XCTUnwrap(pristineCoordinator).modelContext.container
            try await pristineOwner.admit(
                coordinator: try XCTUnwrap(pristineCoordinator))
            let pristineOperation =
                try pristineOwner.originalOperationForInterruption()
            var pristineInitialCompletions = 0
            let pristineService = try pristineOwner.configure(EraseAllService(
                applicationSupportURL: pristine.support,
                cachesDirectoryURL: pristine.caches,
                temporaryDirectoryURL: pristine.temporary,
                userDefaults: pristine.defaults,
                bundleIdentifier: bundleID,
                makeUUID: sequence([pristineNewID, UUID()]),
                admitErase: { try await pristineOwner.admitSubject($0) },
                didCompleteErase: { _ in pristineInitialCompletions += 1 }
            ))
            pristineService.enableOriginalColdExitWitnessForTesting = true
            Self.retainedS6EraseServices.append(
                (pristine.root, pristineService))
            var pristineActivationFailure: Error?
            diagnosticPhase = "pristine-original-preparation"
            let pristineOutcome = try await pristineService.erase(
                confirmation: "ERASE",
                coordinator: try XCTUnwrap(pristineCoordinator),
                diagnosticsStore: pristine.diagnostics,
                operation: pristineOperation,
                activate: {
                    [weak pristineCoordinator,
                     weak router = pristineOwner.router] session in
                    do {
                        guard let pristineCoordinator, let router else {
                            throw FixtureError.invalid
                        }
                        try router.activateErasePreparationSession(
                            session, coordinator: pristineCoordinator,
                            operation: pristineOperation)
                    } catch {
                        pristineActivationFailure = error
                    }
                })
            if let pristineActivationFailure {
                throw pristineActivationFailure
            }
            XCTAssertTrue(pristineOutcome.operation === pristineOperation)
            XCTAssertTrue(pristineOutcome.operation.detached)
            XCTAssertTrue(pristineOutcome.operation.hasPreparedCleanup)
            XCTAssertEqual(try XCTUnwrap(pristineCoordinator).generationID,
                pristineNewID)
            XCTAssertEqual(pristineInitialCompletions, 0)
            XCTAssertTrue(fileManager.fileExists(atPath:
                pristine.factory.installedGenerationURL(
                    id: pristineOldID).path))
            let pristinePending = try XCTUnwrap(try EraseIntentStore(
                applicationSupportURL: pristine.support).load())
            XCTAssertEqual(pristinePending.phase, .sessionActivated)
            let pristineReservation =
                try pristineOwner.originalReservationForInterruption()
            try pristineOwner.router
                .beginPristinePreparedEraseColdRestartForTesting(
                    pristineOperation, originalService: pristineService)
            pristineCoordinator = nil
            pristine.coordinator = nil
            pristineContext = nil
            pristineContainer = nil
            try await pristineOwner.router
                .finishPristinePreparedEraseColdRestartForTesting(
                    pristineOperation,
                    subject: pristineReservation.subject,
                    reservation: pristineReservation)
            var recoveryReceipts = [CompletedEraseReceiptV1]()
            diagnosticPhase = "startup-reconcile-after-context-release"
            let recovery = EraseAllService(
                applicationSupportURL: pristine.support,
                cachesDirectoryURL: pristine.caches,
                temporaryDirectoryURL: pristine.temporary,
                userDefaults: pristine.defaults,
                bundleIdentifier: bundleID,
                didCompleteErase: { recoveryReceipts.append($0) }
            )
            recovery.erasePhaseDiagnosticForTesting = { diagnosticPhase = $0 }
            let recovered = try await startKernelColdOwner(
                pristine, service: recovery)

            diagnosticPhase = "post-recovery-assertions"
            XCTAssertEqual(recovered.generationID, pristineNewID)
            XCTAssertEqual(recoveryReceipts.map(\.subject.eraseID),
                [pristinePending.eraseID])
            XCTAssertEqual(recoveryReceipts.map(\.subject.newGenerationID),
                [pristineNewID])
            XCTAssertFalse(fileManager.fileExists(atPath:
                pristine.factory.installedGenerationURL(id: pristineOldID).path
            ))
            XCTAssertFalse(fileManager.fileExists(atPath:
                pristine.support.appendingPathComponent("FieldEvidenceErase").path
            ))
            let diagnosticsAfterRecovery = await pristine.diagnostics.snapshot()
            XCTAssertEqual(diagnosticsAfterRecovery, .zero)
        } catch {
            recordReminderEraseDiagnostic(error, method: "testRetainedLiveContextDefersCleanupUntilColdRecovery", phase: diagnosticPhase, enabled: true)
            throw error
        }
    }

    @MainActor
    private func runKernelCompletedAbortOriginal(
        presentation: AppAccessPresentationV1, router: StartupRouter,
        support: URL, caches: URL, temporary: URL,
        point: EraseAllFailurePoint
    ) async throws -> (UUID, WeakKernelSourceAliases, [FileFact], Data) {
        guard case let .ready(coordinator, diagnostics, _) = router.route else {
            throw FixtureError.invalid
        }
        let oldID = coordinator.generationID
        try await seedRouterOwnedSource(coordinator: coordinator,
            diagnostics: diagnostics, support: support, caches: caches,
            temporary: temporary)
        let aliases = WeakKernelSourceAliases(coordinator.modelContext)
        let sourceRoot = StoreGenerationFactory(applicationSupportURL: support)
            .installedGenerationURL(id: oldID)
        let before = try tree(sourceRoot)
        let pointer = try Data(contentsOf: support
            .appendingPathComponent("FieldEvidenceData/current.json"))
        try presentation.expectCompletedAbortColdRestartForTesting(point)
        do {
            try await presentation.performErase(applicationSupportURL: support,
                confirmation: "ERASE", coordinator: coordinator,
                diagnosticsStore: diagnostics)
            XCTFail("pre-intent injection did not interrupt original Erase")
            throw FixtureError.invalid
        } catch EraseAllServiceError.injectedFailure {
            return (oldID, aliases, before, pointer)
        }
    }

    @MainActor
    private func exerciseKernelCompletedAbort(point: EraseAllFailurePoint,
        offset: Int) async throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_6-phase-\(offset)-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        for url in [support, caches, temporary] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let defaultsName = "S6_6-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.setPersistentDomain(["erase-test": true], forName: bundleID)
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let router = StartupRouter(applicationSupportURL: support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: profiles)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: S66ColdEraseAuthentication())
        var aborts = [AbortedEraseAdmissionReceiptV1]()
        var completions = [CompletedEraseReceiptV1]()
        let newID = UUID(uuid: (0x66, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, UInt8(0x40 + offset), UInt8(0x60 + offset)))
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                let original = EraseAllService(applicationSupportURL: support,
                    cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                    userDefaults: defaults, bundleIdentifier: self.bundleID,
                    defaultsDomainName: defaultsName,
                    makeUUID: self.sequence([newID, UUID()]),
                    failureInjection: EraseAllFailureInjection(failOnceAt: point),
                    sceneNavigationStatePort: sceneState,
                    privateSystemDiscoveryIndex: nil,
                    admitErase: admission,
                    didCompleteErase: { receipt in
                        completions.append(receipt)
                        XCTAssertNotNil(completion)
                        completion?(receipt)
                    },
                    didAbortEraseAdmission: { receipt in
                        aborts.append(receipt)
                        XCTAssertNotNil(aborted)
                        aborted?(receipt)
                    })
                Self.retainedS6EraseServices.append((root, original))
                return original
            }, sessionFactory: { session })
        Self.retainedKernelAbortOwners.append((root, router, session, presentation))
        let published = expectation(description: "S6 original abort Router publishes ready")
        let subscription = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        await presentation.bootstrapIfNeeded()
        await fulfillment(of: [published], timeout: 30)
        let (oldID, aliases, sourceBefore, pointerBefore) = try await
            runKernelCompletedAbortOriginal(presentation: presentation,
                router: router, support: support, caches: caches,
                temporary: temporary, point: point)
        XCTAssertEqual(aborts.count, 1, "\(point) must deliver its genuine abort receipt once")
        XCTAssertTrue(completions.isEmpty, "\(point) cannot complete Erase")
        let abort = try XCTUnwrap(aborts.first)
        XCTAssertEqual(abort.originalGenerationID, oldID)
        XCTAssertEqual(abort.subject.newGenerationID, newID)
        XCTAssertEqual(abort.reservation.subject, abort.subject)
        XCTAssertNil(try EraseIntentStore(applicationSupportURL: support).load())
        XCTAssertNil(try EraseIntentStore(applicationSupportURL: support).loadPreparation())
        let sourceRoot = StoreGenerationFactory(applicationSupportURL: support)
            .installedGenerationURL(id: oldID)
        XCTAssertEqual(try tree(sourceRoot), sourceBefore)
        XCTAssertEqual(try Data(contentsOf: support
            .appendingPathComponent("FieldEvidenceData/current.json")), pointerBefore)
        let operation = try await presentation.continueCompletedAbortColdRestartForTesting()
        let drained = expectation(for: NSPredicate { _, _ in aliases.drained },
            evaluatedWith: NSObject())
        await fulfillment(of: [drained], timeout: 30)
        XCTAssertTrue(aliases.drained)
        try presentation.finishCompletedAbortColdRestartForTesting(operation)
        XCTAssertThrowsError(try operation.completedRetirement())
        do {
            try await router.startIfNeeded(accessGate: session.gate)
            XCTFail("completed-abort original Router re-entered")
        } catch { }
        XCTAssertEqual(try tree(sourceRoot), sourceBefore)
        XCTAssertEqual(try Data(contentsOf: support
            .appendingPathComponent("FieldEvidenceData/current.json")), pointerBefore)
        let recovered = try await startKernelColdOwner(root: root, support: support,
            service: EraseAllService(applicationSupportURL: support,
                cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                userDefaults: defaults, bundleIdentifier: bundleID,
                defaultsDomainName: defaultsName))
        XCTAssertEqual(recovered.generationID, oldID)
        XCTAssertEqual(try recovered.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
        let diagnostics = await DiagnosticsStore(applicationSupportURL: support).snapshot()
        XCTAssertNotEqual(diagnostics, .zero)
        XCTAssertEqual(aborts.count, 1)
        XCTAssertTrue(completions.isEmpty)
    }

    /// Executes the real ticketed original frame. The configured copy is
    /// retained even when the injected fault throws, because the checked
    /// shutdown seam authenticates that exact Service frame.
    @MainActor
    private func runKernelOriginalErase(_ harness: Harness,
        service: EraseAllService) async throws {
        let coordinator = try XCTUnwrap(harness.coordinator)
        try await harness.originalOwner.admit(coordinator: coordinator)
        let operation = try harness.originalOwner.originalOperationForInterruption()
        let configured = try harness.originalOwner.configure(service)
        configured.erasePhaseDiagnosticForTesting = service.erasePhaseDiagnosticForTesting
        Self.retainedS6EraseServices.append((harness.root, configured))
        harness.interruptedOperation = operation
        harness.interruptedService = configured
        var activationFailure: Error?
        do {
            let outcome = try await configured.erase(
                confirmation: EraseAllService.requiredConfirmation,
                coordinator: coordinator, diagnosticsStore: harness.diagnostics,
                operation: operation,
                activate: { [weak coordinator, weak router = harness.originalOwner.router] replacement in
                    do {
                        guard let coordinator, let router else { throw FixtureError.invalid }
                        try router.activateErasePreparationSession(replacement,
                            coordinator: coordinator, operation: operation)
                    } catch { activationFailure = error }
                })
            if let activationFailure { throw activationFailure }
            XCTAssertTrue(outcome.operation === operation)
        } catch {
            if let activationFailure { throw activationFailure }
            throw error
        }
    }

    @MainActor
    func testEveryInterruptionRecoversOldOrFullyErasedNew() async throws {
        var diagnosticPhase = "harness"
        do {
            for (offset, point) in EraseAllFailurePoint.allCases.enumerated() {
                if point == .afterEmptyGenerationDirectoryCreate
                    || point == .beforePreparedWrite {
                    try await exerciseKernelCompletedAbort(point: point, offset: offset)
                    continue
                }
                let harness = try await makeHarness(
                    "phase-\(offset)",
                    diagnoseInitialOpen: true,
                    observePhase: { diagnosticPhase = "interruption.\(offset).\(point).\($0)" }
                )
                defer { cleanup(harness) }
                let oldID = try XCTUnwrap(harness.coordinator).generationID
                let newID = UUID(uuid: (
                    0x66, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0,
                    UInt8(0x40 + offset), UInt8(0x60 + offset)
                ))
                var originalCompletionCount = 0
                let service = EraseAllService(
                    applicationSupportURL: harness.support,
                    cachesDirectoryURL: harness.caches,
                    temporaryDirectoryURL: harness.temporary,
                    userDefaults: harness.defaults,
                    bundleIdentifier: bundleID,
                    defaultsDomainName: point == .afterCleanup
                        ? harness.defaultsSuiteName
                        : nil,
                    makeUUID: sequence([newID, UUID()]),
                    failureInjection: EraseAllFailureInjection(failOnceAt: point),
                    admitErase: { try await harness.originalOwner.admitSubject($0) },
                    didCompleteErase: { _ in originalCompletionCount += 1 }
                )
                service.erasePhaseDiagnosticForTesting = { phase in
                    if phase.hasPrefix("ERASE_FILE_SNAPSHOT_V1 ") {
                        FileHandle.standardError.write(Data((phase + "\n").utf8))
                    } else {
                        diagnosticPhase = phase
                    }
                }
                diagnosticPhase = "erase.injection.\(point)"
                weak var originalContext = harness.coordinator?.modelContext
                weak var originalContainer = harness.coordinator?.modelContext.container
                let retiresBeforeInjection = point == .afterSessionRetirementBeforeCleanup
                    || point == .afterCleanup || point == .beforeCleanupPhaseWrite
                    || point == .afterCleanupPhaseWrite || point == .beforeJournalRemoval
                if retiresBeforeInjection {
                    try await runKernelOriginalErase(harness, service: service)
                    harness.coordinator = nil
                    let operation = try XCTUnwrap(harness.interruptedOperation)
                    let drain = expectation(for: NSPredicate { _, _ in
                        originalContext == nil && originalContainer == nil
                    }, evaluatedWith: NSObject())
                    await fulfillment(of: [drain], timeout: 30)
                    XCTAssertNil(originalContext)
                    XCTAssertNil(originalContainer)
                    do {
                        let complete = try await operation.advanceCleanup()
                        XCTFail("Actual post-retirement fault returned \(complete)")
                    } catch {
                        recordReminderEraseDiagnostic(error,
                            method: "testEveryInterruptionRecoversOldOrFullyErasedNew",
                            phase: diagnosticPhase, enabled: true)
                        XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
                    }
                } else {
                    await XCTAssertThrowsErrorAsync {
                        try await runKernelOriginalErase(harness, service: service)
                    } verify: { error in
                        recordReminderEraseDiagnostic(error,
                            method: "testEveryInterruptionRecoversOldOrFullyErasedNew",
                            phase: diagnosticPhase, enabled: true)
                        XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
                    }
                }
                XCTAssertEqual(originalCompletionCount, 0,
                    "interrupted original Erase cannot deliver a completed receipt")

                diagnosticPhase = "post-injection.\(point)"
                let handoffBeforeRecovery: (manifest: Data, pointer: Data, identity: ManifestFileIdentity)?
                let sidecarURL = harness.support.appendingPathComponent("FieldEvidenceData/erase-current-manifest.json")
                let pointerURL = harness.support.appendingPathComponent("FieldEvidenceData/current.json")
                if point == .afterCleanup || point == .beforeCleanupPhaseWrite
                    || point == .afterCleanupPhaseWrite || point == .beforeJournalRemoval {
                    if point == .afterCleanupPhaseWrite {
                        // The immediate post-write crash leaves only the newly
                        // opened empty lock registry. Recovery must remove it;
                        // moving this injection would skip the real crash window.
                        try assertOnlyCompletionControlRemains(
                            harness, oldID: oldID, newID: newID
                        )
                    } else {
                        assertAuxiliaryRootsCleared(harness)
                    }
                    handoffBeforeRecovery = (
                        try Data(contentsOf: sidecarURL), try Data(contentsOf: pointerURL),
                        try regularFileIdentity(sidecarURL)
                    )
                    XCTAssertFalse(fileManager.fileExists(atPath: manifestURL(harness, generationID: newID).path))
                } else {
                    handoffBeforeRecovery = nil
                }

                let cooldownBeforeRecovery: (
                    RatingRequestAttemptLedgerStateV1,
                    Data
                )?
                if point == .afterCleanup {
                    let store = PreferencesAdapterV1(defaults: harness.defaults)
                    guard case .current(let state) = try await store.load(),
                          case .erasedCooldown = state.origin,
                          let domain = harness.defaults.persistentDomain(
                            forName: harness.defaultsSuiteName
                          ),
                          let bytes = domain["rating-eligibility.v1"] as? Data else {
                        return XCTFail("afterCleanup must persist a cooldown before interruption")
                    }
                    cooldownBeforeRecovery = (state, bytes)
                } else {
                    cooldownBeforeRecovery = nil
                }

                let originalOperation = try XCTUnwrap(harness.interruptedOperation)
                let originalService = try XCTUnwrap(harness.interruptedService)
                if !retiresBeforeInjection {
                    try await harness.originalOwner.router
                        .beginInterruptedEarlyEraseColdRestartForTesting(
                            originalOperation, originalService: originalService,
                            expectedFault: point)
                    harness.coordinator = nil
                    let drain = expectation(for: NSPredicate { _, _ in
                        originalContext == nil && originalContainer == nil
                    }, evaluatedWith: NSObject())
                    await fulfillment(of: [drain], timeout: 30)
                    XCTAssertNil(originalContext)
                    XCTAssertNil(originalContainer)
                    try harness.originalOwner.router
                        .finishInterruptedEarlyEraseColdRestartForTesting(originalOperation)
                } else if point == .afterSessionRetirementBeforeCleanup {
                    try harness.originalOwner.router
                        .abandonInterruptedPostRetiredEraseForColdRestartForTesting(
                            originalOperation, originalService: originalService)
                } else {
                    try harness.originalOwner.router
                        .abandonInterruptedLateEraseForColdRestartForTesting(
                            originalOperation, expectedFault: point)
                }
                XCTAssertThrowsError(try originalOperation.completedRetirement())
                XCTAssertEqual(originalCompletionCount, 0)
                XCTAssertThrowsError(try harness.originalOwner.router.eraseRetirementOperation(
                    for: try harness.originalOwner.originalTicketForInterruption()))
                do {
                    try await harness.originalOwner.router.startIfNeeded(
                        accessGate: harness.originalOwner.accessGate)
                    XCTFail("original Router re-entered after checked shutdown at \(point)")
                } catch { }
                let recovery = EraseAllService(
                    applicationSupportURL: harness.support,
                    cachesDirectoryURL: harness.caches,
                    temporaryDirectoryURL: harness.temporary,
                    userDefaults: harness.defaults,
                    bundleIdentifier: bundleID,
                    defaultsDomainName: point == .afterCleanup
                        ? harness.defaultsSuiteName
                        : nil
                )
                recovery.erasePhaseDiagnosticForTesting = { phase in
                    if phase.hasPrefix("ERASE_FILE_SNAPSHOT_V1 ") {
                        FileHandle.standardError.write(Data((phase + "\n").utf8))
                    } else {
                        diagnosticPhase = phase
                    }
                }
                diagnosticPhase = "startup-reconcile.\(point)"
                let recovered = try await startKernelColdOwner(harness, service: recovery)

                diagnosticPhase = "post-recovery-assertions.\(point)"
                do {
                    let session = recovered
                    XCTAssertEqual(session.generationID, newID, "\(point)")
                    assertAuxiliaryRootsCleared(harness)
                    if let handoff = handoffBeforeRecovery {
                        XCTAssertEqual(try Data(contentsOf: sidecarURL), handoff.manifest, "\(point)")
                        XCTAssertEqual(try regularFileIdentity(sidecarURL), handoff.identity, "\(point)")
                        XCTAssertEqual(try Data(contentsOf: pointerURL), handoff.pointer, "\(point)")
                    }
                    XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [])
                    XCTAssertEqual(
                        try counts(session.modelContext),
                        [0, 0, 0, 0, 0, 0, 0],
                        "\(point)"
                    )
                    let clearedDiagnostics = await harness.diagnostics.snapshot()
                    XCTAssertEqual(clearedDiagnostics, .zero)
                    if let handoff = handoffBeforeRecovery {
                        // A passive factory was never the original owner;
                        // startup refusal was checked on the exact old Router
                        // before this fresh cold owner began.
                        XCTAssertEqual(try Data(contentsOf: sidecarURL), handoff.manifest, "\(point)")
                        XCTAssertEqual(try regularFileIdentity(sidecarURL), handoff.identity, "\(point)")
                        XCTAssertEqual(session.generationID, newID, "\(point)")
                        XCTAssertEqual(try counts(session.modelContext), [0, 0, 0, 0, 0, 0, 0], "\(point)")
                        let restoredURL = manifestURL(harness, generationID: newID)
                        XCTAssertEqual(try Data(contentsOf: restoredURL), handoff.manifest, "\(point)")
                        XCTAssertEqual(try regularFileIdentity(restoredURL), handoff.identity, "\(point)")
                        XCTAssertEqual(try Data(contentsOf: pointerURL), handoff.pointer, "\(point)")
                        XCTAssertFalse(fileManager.fileExists(atPath: sidecarURL.path), "\(point)")
                    }
                    // This read restores the manifest handoff; perform the
                    // cold-owner/no-effect witnesses above before it.
                    XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
                    if let beforeRecovery = cooldownBeforeRecovery {
                        let relaunchedDefaults = try XCTUnwrap(
                            UserDefaults(suiteName: harness.defaultsSuiteName)
                        )
                        let store = PreferencesAdapterV1(defaults: relaunchedDefaults)
                        guard case .current(let afterState) = try await store.load(),
                              let afterBytes = relaunchedDefaults.persistentDomain(
                                forName: harness.defaultsSuiteName
                              )?["rating-eligibility.v1"] as? Data else {
                            return XCTFail("recovery must retain the exact cooldown ledger")
                        }
                        XCTAssertEqual(afterState, beforeRecovery.0)
                        XCTAssertEqual(afterBytes, beforeRecovery.1)
                    }
                }
                XCTAssertFalse(fileManager.fileExists(
                    atPath: harness.support.appendingPathComponent(
                        "FieldEvidenceErase/erase.json"
                    ).path
                ))
            }
        } catch {
            recordReminderEraseDiagnostic(error, method: "testEveryInterruptionRecoversOldOrFullyErasedNew", phase: diagnosticPhase, enabled: true)
            throw error
        }
    }

    @MainActor
    func testCancelAndDirtyContextChangeNothingBeforeMarker() async throws {
        let harness = try await makeHarness("no-marker")
        defer { cleanup(harness) }
        let coordinator = try XCTUnwrap(harness.coordinator)
        let owner = harness.originalOwner
        try await owner.admit(coordinator: coordinator)
        let operation = try owner.originalOperationForInterruption()
        let before = try tree(harness.support)
        let service = try owner.configure(EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            defaultsDomainName: harness.defaultsSuiteName,
            admitErase: { try await owner.admitSubject($0) }
        ))
        Self.retainedS6EraseServices.append((harness.root, service))
        var activationFailure: Error?

        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "erase",
                coordinator: coordinator,
                diagnosticsStore: harness.diagnostics,
                operation: operation,
                activate: { [weak coordinator] session in
                    do {
                        guard let coordinator else { throw V23EraseOperationHarnessV1.Failure.activation }
                        try owner.router.activateErasePreparationSession(
                            session, coordinator: coordinator, operation: operation
                        )
                    } catch { activationFailure = error }
                }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .invalidConfirmation)
        }
        XCTAssertEqual(try tree(harness.support), before)

        coordinator.modelContext.insert(Site(label: "Unsaved"))
        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "ERASE",
                coordinator: coordinator,
                diagnosticsStore: harness.diagnostics,
                operation: operation,
                activate: { [weak coordinator] session in
                    do {
                        guard let coordinator else { throw V23EraseOperationHarnessV1.Failure.activation }
                        try owner.router.activateErasePreparationSession(
                            session, coordinator: coordinator, operation: operation
                        )
                    } catch { activationFailure = error }
                }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .contextHasChanges)
        }
        coordinator.modelContext.rollback()
        XCTAssertNil(activationFailure)
        XCTAssertEqual(try tree(harness.support), before)
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent(
                "FieldEvidenceErase/erase.json"
            ).path
        ))
    }

    @MainActor
    func testLiveCleanupWaitsForOldContextReferenceDrain() async throws {
        var diagnosticPhase = "harness"
        do {
            let harness = try await makeHarness("drain", observePhase: { diagnosticPhase = $0 })
            defer { cleanup(harness) }
            let owner = harness.originalOwner
            let newID = uuid("66000000-0000-0000-0000-000000000301")
            var retainedContext: ModelContext?
            var retainedContainer: ModelContainer?
            weak var observedOldCoordinator: StoreSessionCoordinator?
            weak var observedOldContext: ModelContext?
            weak var observedOldContainer: ModelContainer?
            var completedReceipts = [CompletedEraseReceiptV1]()
            let (operation, oldID) = try await { @MainActor () async throws
                -> (EraseRouterOperationV1, UUID) in
                let coordinator = try XCTUnwrap(harness.coordinator)
                observedOldCoordinator = coordinator
                retainedContext = coordinator.modelContext
                retainedContainer = coordinator.modelContext.container
                observedOldContext = retainedContext
                observedOldContainer = retainedContainer
                let oldID = coordinator.generationID
                try await owner.admit(coordinator: coordinator)
                let operation = try owner.originalOperationForInterruption()
                let service = try owner.configure(EraseAllService(
                    applicationSupportURL: harness.support,
                    cachesDirectoryURL: harness.caches,
                    temporaryDirectoryURL: harness.temporary,
                    userDefaults: harness.defaults,
                    bundleIdentifier: bundleID,
                    defaultsDomainName: harness.defaultsSuiteName,
                    makeUUID: sequence([
                        newID,
                        uuid("66000000-0000-0000-0000-000000000302"),
                    ]),
                    admitErase: { try await owner.admitSubject($0) },
                    didCompleteErase: { completedReceipts.append($0) }
                ))
                Self.retainedS6EraseServices.append((harness.root, service))
                diagnosticPhase = "erase-with-retained-context"
                try await owner.prepareCompatibility(service: service,
                    confirmation: "ERASE", coordinator: coordinator,
                    diagnostics: harness.diagnostics)
                harness.coordinator = nil
                return (operation, oldID)
            }()
            diagnosticPhase = "post-erase-assertions"
            XCTAssertNil(observedOldCoordinator)
            XCTAssertNotNil(retainedContext)
            XCTAssertNotNil(retainedContainer)
            let cleanupAdvancedWhileHeld = try await operation.advanceCleanup()
            XCTAssertFalse(cleanupAdvancedWhileHeld)
            XCTAssertEqual(completedReceipts.count, 0)
            XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
            XCTAssertTrue(fileManager.fileExists(
                atPath: harness.factory.installedGenerationURL(id: oldID).path
            ))
            XCTAssertEqual(
                try EraseIntentStore(applicationSupportURL: harness.support).load()?.phase,
                .sessionActivated
            )

            retainedContext = nil
            retainedContainer = nil
            guard observedOldContext == nil, observedOldContainer == nil else {
                XCTFail("Old context and container must drain before live cleanup")
                throw V23EraseOperationHarnessV1.Failure.drainPending
            }
            diagnosticPhase = "live-cleanup-after-context-release"
            try await owner.completeCleanup()
            XCTAssertEqual(completedReceipts.count, 1)
            XCTAssertEqual(completedReceipts.first?.subject.newGenerationID, newID)
            try await owner.adoptCompletedReceipt()
            try await owner.activateFreshOrdinarySession()
            guard case let .ready(reopened, _, _) = owner.router.route else {
                return XCTFail("Live cleanup must publish the fresh ordinary owner")
            }
            diagnosticPhase = "post-cleanup-assertions"
            XCTAssertEqual(reopened.generationID, newID)
            XCTAssertFalse(fileManager.fileExists(
                atPath: harness.factory.installedGenerationURL(id: oldID).path
            ))
        } catch {
            recordReminderEraseDiagnostic(error, method: "testLiveCleanupWaitsForOldContextReferenceDrain",
                phase: diagnosticPhase, enabled: true)
            throw error
        }
    }

    @MainActor
    func testMalformedAuxiliaryTreeFailsBeforeAnyDeletion() async throws {
        let harness = try await makeHarness("auxiliary")
        defer { cleanup(harness) }
        let coordinator = try XCTUnwrap(harness.coordinator)
        let owner = harness.originalOwner
        try await owner.admit(coordinator: coordinator)
        let operation = try owner.originalOperationForInterruption()
        let external = harness.root.appendingPathComponent("external.bin")
        let externalBytes = Data("outside erase authority".utf8)
        try externalBytes.write(to: external)
        let service = try owner.configure(EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            defaultsDomainName: harness.defaultsSuiteName,
            admitErase: { try await owner.admitSubject($0) }
        ))
        Self.retainedS6EraseServices.append((harness.root, service))
        let link = harness.support.appendingPathComponent(
            "FieldEvidenceOperations/unsafe-link"
        )
        try fileManager.createSymbolicLink(
            at: link,
            withDestinationURL: external
        )
        let before = try tree(harness.support)
        var activationFailure: Error?

        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "ERASE",
                coordinator: coordinator,
                diagnosticsStore: harness.diagnostics,
                operation: operation,
                activate: { [weak coordinator] session in
                    do {
                        guard let coordinator else { throw V23EraseOperationHarnessV1.Failure.activation }
                        try owner.router.activateErasePreparationSession(
                            session, coordinator: coordinator, operation: operation
                        )
                    } catch { activationFailure = error }
                }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .invalidAuthority)
        }
        XCTAssertNil(activationFailure)
        XCTAssertEqual(try tree(harness.support), before)
        XCTAssertEqual(try Data(contentsOf: external), externalBytes)
        XCTAssertTrue(fileManager.fileExists(atPath: link.path))
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent(
                "FieldEvidenceErase/erase.json"
            ).path
        ))
    }

    @MainActor
    func testPinnedEmptyGenerationCreationRejectsReplacementBeforeSQLiteWrite() async throws {
        for replaceParent in [true, false] {
            let harness = try await makeHarness(
                replaceParent ? "create-parent" : "create-leaf"
            )
            defer { cleanup(harness) }
            let authority = try harness.factory.makeRestoreGenerationAuthority()
            let oldID = try XCTUnwrap(harness.coordinator).generationID
            let oldRoot = harness.factory.installedGenerationURL(id: oldID)
            let oldBefore = try tree(oldRoot)
            let newID = replaceParent
                ? uuid("66000000-0000-0000-0000-000000000411")
                : uuid("66000000-0000-0000-0000-000000000412")
            let dataRoot = harness.support.appendingPathComponent(
                "FieldEvidenceData",
                isDirectory: true
            )
            let generations = dataRoot.appendingPathComponent(
                "generations",
                isDirectory: true
            )
            let newName = newID.uuidString.lowercased()
            var detached: URL?
            var replacement: URL?

            XCTAssertThrowsError(try harness.factory.createEmptyInstalledGeneration(
                id: newID,
                authority: authority,
                beforeStoreCreate: {
                    if replaceParent {
                        let moved = dataRoot.appendingPathComponent(
                            "generations.detached",
                            isDirectory: true
                        )
                        try self.fileManager.moveItem(at: generations, to: moved)
                        try self.fileManager.createDirectory(
                            at: generations,
                            withIntermediateDirectories: false
                        )
                        detached = moved
                        replacement = generations.appendingPathComponent(
                            "replacement.bin"
                        )
                    } else {
                        let owned = generations.appendingPathComponent(
                            newName,
                            isDirectory: true
                        )
                        let moved = generations.appendingPathComponent(
                            "\(newName).detached",
                            isDirectory: true
                        )
                        try self.fileManager.moveItem(at: owned, to: moved)
                        try self.fileManager.createDirectory(
                            at: owned,
                            withIntermediateDirectories: false
                        )
                        detached = moved
                        replacement = owned.appendingPathComponent(
                            "replacement.bin"
                        )
                    }
                    try Data("unowned replacement".utf8).write(
                        to: try XCTUnwrap(replacement)
                    )
                }
            )) { error in
                XCTAssertEqual(
                    error as? StoreGenerationFailure,
                    .dataPointerInvalid
                )
            }

            let replacementURL = try XCTUnwrap(replacement)
            XCTAssertEqual(
                try Data(contentsOf: replacementURL),
                Data("unowned replacement".utf8)
            )
            if replaceParent {
                XCTAssertEqual(
                    try tree(
                        try XCTUnwrap(detached).appendingPathComponent(
                            oldID.uuidString.lowercased(),
                            isDirectory: true
                        )
                    ),
                    oldBefore
                )
            } else {
                XCTAssertEqual(try tree(oldRoot), oldBefore)
                XCTAssertFalse(fileManager.fileExists(
                    atPath: try XCTUnwrap(detached).path
                ))
            }
            XCTAssertFalse(fileManager.fileExists(
                atPath: harness.support.appendingPathComponent(
                    "FieldEvidenceErase/erase.json"
                ).path
            ))
        }
    }

    @MainActor
    func testReplacedGenerationAncestorFailsClosedWithoutDeletingEitherTree() async throws {
        let harness = try await makeHarness("ancestor")
        defer { cleanup(harness) }
        let owner = harness.originalOwner
        let newID = uuid("66000000-0000-0000-0000-000000000401")
        weak var releasedCoordinator: StoreSessionCoordinator?
        let (originalService, originalOperation) = try await { @MainActor () async throws
            -> (EraseAllService, EraseRouterOperationV1) in
            let coordinator = try XCTUnwrap(harness.coordinator)
            releasedCoordinator = coordinator
            try await owner.admit(coordinator: coordinator)
            let operation = try owner.originalOperationForInterruption()
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID,
                defaultsDomainName: harness.defaultsSuiteName,
                makeUUID: sequence([
                    newID,
                    uuid("66000000-0000-0000-0000-000000000402"),
                ]),
                failureInjection: EraseAllFailureInjection(failOnceAt: .afterPreparedWrite),
                admitErase: { try await owner.admitSubject($0) }
            ))
            Self.retainedS6EraseServices.append((harness.root, service))
            var activationEntries = 0
            await XCTAssertThrowsErrorAsync {
                _ = try await service.erase(
                    confirmation: "ERASE", coordinator: coordinator,
                    diagnosticsStore: harness.diagnostics, operation: operation,
                    activate: { _ in activationEntries += 1 }
                )
            } verify: { error in
                XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
            }
            XCTAssertEqual(activationEntries, 0)
            try await owner.router.beginInterruptedEarlyEraseColdRestartForTesting(
                operation, originalService: service, expectedFault: .afterPreparedWrite
            )
            harness.coordinator = nil
            return (service, operation)
        }()
        guard releasedCoordinator == nil else {
            XCTFail("The source coordinator must drain before hostile ancestor mutation")
            throw FixtureError.invalid
        }
        try withExtendedLifetime(originalService) {
            try owner.router.finishInterruptedEarlyEraseColdRestartForTesting(originalOperation)
        }

        let dataRoot = harness.support.appendingPathComponent("FieldEvidenceData")
        let canonical = dataRoot.appendingPathComponent("generations")
        let detached = dataRoot.appendingPathComponent("generations.detached")
        try fileManager.moveItem(at: canonical, to: detached)
        try fileManager.createDirectory(at: canonical, withIntermediateDirectories: false)
        let replacement = canonical.appendingPathComponent("replacement.bin")
        let replacementBytes = Data("unowned replacement".utf8)
        try replacementBytes.write(to: replacement)
        let detachedBefore = try tree(detached)
        let replacementBefore = try tree(canonical)
        let intentBefore = try XCTUnwrap(EraseIntentStore(
            applicationSupportURL: harness.support).load())

        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let freshGate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: S66ColdEraseAuthentication(), clock: S66EraseReceiptClock(),
            identifiers: SystemApplicationIDSource())
        let freshRouter = StartupRouter(applicationSupportURL: harness.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: profiles)
        // Shared fixture owns this static host-lifetime holder across a denied retry.
        Self.retainedS6ColdOwners.append((harness.root, freshRouter, freshGate))
        let freshAuthentication = await freshGate.authenticate(trigger: .unlock)
        XCTAssertEqual(freshAuthentication, .authenticated)
        let recovery = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            defaultsDomainName: harness.defaultsSuiteName
        )
        Self.retainedS6EraseServices.append((harness.root, recovery))
        try await freshRouter.retryColdEraseForTesting(service: recovery, accessGate: freshGate)
        guard case .maintenance(.eraseInconsistent) = freshRouter.route else {
            return XCTFail("The hostile ancestor must keep cold startup in Erase maintenance")
        }
        XCTAssertEqual(try tree(detached), detachedBefore)
        XCTAssertEqual(try tree(canonical), replacementBefore)
        XCTAssertEqual(try Data(contentsOf: replacement), replacementBytes)
        XCTAssertEqual(try EraseIntentStore(applicationSupportURL: harness.support).load(), intentBefore)
    }
}

final class C27S66TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(PersistentSchemaV26.models.count, 94)
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension S6_6EraseRecoveryTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension S6_6EraseRecoveryTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistent: 21, records: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.receiptPersistence,
                       "RECOVERABILITY_VERIFICATION_RECEIPT_V1_IMMUTABLE_EVIDENCE")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C18EraseRecoveryRetainsTypedLifecycleRequirement() throws {
        XCTAssertTrue(PackageEvolutionLifecycleV1.deleteEraseRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.backupRestoreRequired)
        XCTAssertTrue(PackageSandboxCheckKindV1.allCases.contains(.deleteErase))
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.downgradePolicy,
            "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V17_WRITE"
        )
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C34EraseClearsDeviceSceneState() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x0b)))
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .assets)
        let today = try NavigationTargetV1(workspaceID: workspace, destination: .today)
        let work = try NavigationTargetV1(workspaceID: workspace, destination: .work)
        let reports = try NavigationTargetV1(workspaceID: workspace, destination: .reports)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .assets, paths: [
            .init(root: .today, targets: [today]),
            .init(root: .work, targets: [work]),
            .init(root: .assets, targets: [target]),
            .init(root: .reports, targets: [reports])
        ], snapshotID: UUID())
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try adapter.save(snapshot)
        try adapter.erase()
        XCTAssertEqual(try adapter.loadAndReconcile(), .absent)
        XCTAssertTrue(SceneNavigationLifecycleDispositionV1().eraseClears)
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C17DeleteAndEraseOwnOnlyDerivedProjectionCleanup() throws {
        XCTAssertNoThrow(try KernelDeletionEraseRegistryV4.validateIntegrationProjectionLifecycle())
        XCTAssertEqual(
            KernelDeletionEraseRegistryV4.integrationProjectionLifecycle.map(\.rawValue),
            ["DROP_DERIVED_AND_REBUILD", "DROP_DERIVED_AND_REBUILD_EMPTY"]
        )
    }

    func testV23P03C17OperationalStoreCleanupNeverMutatesCanonicalRows() async throws {
        let store = C17IntegrationProjectionStoreSpy()
        let workspaceID = WorkspaceID(rawValue: UUID())
        try await IntegrationProjectionOrdinaryDeletionPolicyV1.purge(
            store: store,
            workspaceID: workspaceID
        )
        try await IntegrationProjectionEraseAllPolicyV1.purge(
            store: store,
            workspaceID: workspaceID
        )
        let dropCount = await store.dropCount()
        let workspaceIDs = await store.workspaceIDs()
        let usedScopedConsumer = await store.usedScopedConsumer()
        XCTAssertEqual(dropCount, 2)
        XCTAssertEqual(workspaceIDs, [workspaceID, workspaceID])
        XCTAssertFalse(usedScopedConsumer)
    }
}

private actor C17IntegrationProjectionStoreSpy: IntegrationProjectionOperationalStoreV1 {
    private var droppedWorkspaceIDs: [WorkspaceID] = []
    private var receivedScopedConsumer = false

    func checkpoint(
        consumerID: String,
        workspaceID: WorkspaceID
    ) async throws -> ProjectionCheckpointV1? { nil }

    func replaceDerivedProjection(
        events: [IntegrationEventV1],
        checkpoint: ProjectionCheckpointV1,
        consumerID: String,
        workspaceID: WorkspaceID
    ) async throws {}

    func dropDerivedProjection(
        consumerID: String?,
        workspaceID: WorkspaceID
    ) async throws {
        receivedScopedConsumer = receivedScopedConsumer || consumerID != nil
        droppedWorkspaceIDs.append(workspaceID)
    }

    func dropCount() -> Int { droppedWorkspaceIDs.count }
    func workspaceIDs() -> [WorkspaceID] { droppedWorkspaceIDs }
    func usedScopedConsumer() -> Bool { receivedScopedConsumer }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C36EraseIsSoleAuthorityForDraftRows() throws {
        let id=UUID()
        let before=FieldDraftDeletionInventoryV1(draftIDs:[id],stageIDs:[],sagaIDs:[],reservationIDs:[],commitReceiptIDs:[],discardReceiptIDs:[])
        let empty=FieldDraftDeletionInventoryV1(draftIDs:[],stageIDs:[],sagaIDs:[],reservationIDs:[],commitReceiptIDs:[],discardReceiptIDs:[])
        XCTAssertNoThrow(try WholeSignDeletionRule.validateFieldDraftLifecycle(authority:.workspaceErase,before:before,after:empty))
        XCTAssertThrowsError(try WholeSignDeletionRule.validateFieldDraftLifecycle(authority:.workspaceErase,before:before,after:before))
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C15EraseRecoveryRebindsPacketHistoryWithoutChangingIDs() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_166)
        let reboundManifest = try fixture.manifest.rebound(to: fixture.otherWorkspaceID)
        let reboundClaim = try fixture.claim.rebound(to: fixture.otherWorkspaceID)
        let reboundLease = try fixture.lease.rebound(to: fixture.otherWorkspaceID)
        XCTAssertEqual(reboundManifest.manifestID, fixture.manifest.manifestID)
        XCTAssertEqual(reboundClaim.claimID, fixture.claim.claimID)
        XCTAssertEqual(reboundLease.leaseID, fixture.lease.leaseID)
        XCTAssertEqual(reboundManifest.workspaceID, fixture.otherWorkspaceID)
        XCTAssertEqual(reboundClaim.workspaceID, fixture.otherWorkspaceID)
        XCTAssertEqual(reboundLease.workspaceID, fixture.otherWorkspaceID)
    }
}

@MainActor private final class S66NotificationSystemProbe: NotificationSystemPortV1 {
    var requests: [NotificationSystemRequestV1]
    var removalEnabled = false
    var observationCount = 0
    init(requests: [NotificationSystemRequestV1]) { self.requests = requests }
    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }
    func observations() async throws -> [NotificationSystemObservationV1] {
        observationCount += 1
        return requests.map { .init(requestID: $0.notification.requestID, request: $0, delivered: false) }
    }
    func add(_ request: NotificationSystemRequestV1) async throws { requests.append(request) }
    func remove(_ requestIDs: [String]) async throws {
        if removalEnabled { requests.removeAll { requestIDs.contains($0.notification.requestID) } }
    }
}

private extension S6_6EraseRecoveryTests {
    final class Harness {
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
        let factory: StoreGenerationFactory
        let originalOwner: V23EraseOperationHarnessV1
        var coordinator: StoreSessionCoordinator?
        var interruptedOperation: EraseRouterOperationV1?
        var interruptedService: EraseAllService?
        let diagnostics: DiagnosticsStore
        let defaults: UserDefaults
        let defaultsSuiteName: String

        init(
            root: URL,
            support: URL,
            caches: URL,
            temporary: URL,
            factory: StoreGenerationFactory,
            originalOwner: V23EraseOperationHarnessV1,
            coordinator: StoreSessionCoordinator,
            diagnostics: DiagnosticsStore,
            defaults: UserDefaults,
            defaultsSuiteName: String
        ) {
            self.root = root
            self.support = support
            self.caches = caches
            self.temporary = temporary
            self.factory = factory
            self.originalOwner = originalOwner
            self.coordinator = coordinator
            self.diagnostics = diagnostics
            self.defaults = defaults
            self.defaultsSuiteName = defaultsSuiteName
        }
    }

    struct FileFact: Equatable {
        let path: String
        let bytes: Data
    }

    struct ManifestFileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    func regularFileIdentity(_ url: URL) throws -> ManifestFileIdentity {
        var information = stat()
        guard url.path.withCString({ lstat($0, &information) }) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_nlink == 1 else { throw FixtureError.invalid }
        return ManifestFileIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
    }

    func manifestURL(_ harness: Harness, generationID: UUID) -> URL {
        harness.support.appendingPathComponent(
            "FieldEvidenceOperations/schema-migration/manifest-" + generationID.uuidString.lowercased() + ".json"
        )
    }

    enum FixtureError: Error { case invalid }

    @MainActor
    func recordReminderEraseDiagnostic(
        _ error: Error, method: String, phase: String, enabled: Bool = false
    ) {
        guard enabled else { return }
        let dynamicType = String(reflecting: type(of: error))
        let nsError = error as NSError
        let isPolicyMismatch = (error as? ProtectedFilePolicyError) == .resourceValueMismatch
        let isInvalidGeneration = (error as? BackupExportServiceError) == .invalidGeneration
        let facts = "REMINDER_ERASE_DIAGNOSTIC_V1 method=\(method) phase=\(phase)"
            + " type=\(dynamicType) domain=\(nsError.domain) code=\(nsError.code)"
            + " policyMismatch=\(isPolicyMismatch) backupInvalidGeneration=\(isInvalidGeneration)\n"
        FileHandle.standardError.write(Data(facts.utf8))
    }

    @MainActor
    func makeHarness(
        _ name: String,
        diagnoseInitialOpen: Bool = false,
        observePhase: (@MainActor (String) -> Void)? = nil
    ) async throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_6-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        observePhase?("harness.directories")
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        // The original Erase owner must be the Router's published writer.
        // Opening a separate factory here would retain a competing registry
        // and make the checked cold-restart seam impossible to prove.
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let owner = V23EraseOperationHarnessV1(retainingRoot: root,
            applicationSupportURL: support,
            runtime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            profileRegistry: profiles)
        owner.router.startupFailureDiagnosticForTesting = { observePhase?($0) }
        observePhase?("harness.open-current")
        let (coordinator, diagnostics) = try await owner.startOriginalOwner()
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        try await seedRouterOwnedSource(coordinator: coordinator, diagnostics: diagnostics,
            support: support, caches: caches, temporary: temporary, observePhase: observePhase)
        observePhase?("harness.defaults")
        let defaultsSuiteName = "S6_6-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.setPersistentDomain(["erase-test": true], forName: bundleID)
        observePhase?("harness.coordinator")
        return Harness(
            root: root,
            support: support,
            caches: caches,
            temporary: temporary,
            factory: factory,
            originalOwner: owner,
            coordinator: coordinator,
            diagnostics: diagnostics,
            defaults: defaults,
            defaultsSuiteName: defaultsSuiteName
        )
    }

    @MainActor
    func seedRouterOwnedSource(
        coordinator: StoreSessionCoordinator, diagnostics: DiagnosticsStore,
        support: URL, caches: URL, temporary: URL,
        observePhase: (@MainActor (String) -> Void)? = nil
    ) async throws {
        let context = coordinator.modelContext
        let created = Date(timeIntervalSince1970: 1_786_800_000)
        let siteID = uuid("66000000-0000-0000-0000-000000000001")
        context.insert(Site(
            id: siteID,
            label: "Erase campus",
            address: nil,
            timeZoneID: "America/New_York",
            createdAt: created
        ))
        context.insert(Asset(
            id: uuid("66000000-0000-0000-0000-000000000002"),
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Erase sign",
            createdAt: created.addingTimeInterval(1)
        ))
        let consumedPacketID = uuid("66000000-0000-0000-0000-000000000003")
        let packetDeletedAt = created.addingTimeInterval(3)
        context.insert(Packet(
            id: consumedPacketID,
            stableRootID: uuid("66000000-0000-0000-0000-000000000004"),
            currentRecordID: nil,
            evaluationCounted: true,
            contentDeletedAt: packetDeletedAt,
            createdAt: created.addingTimeInterval(2)
        ))
        let packetTombstone = try DeletionLedgerEntryV2(
            identity: DeletionIdentityV2(kind: .packet, id: consumedPacketID),
            deletedAt: packetDeletedAt
        )
        let deletionLedger = DeletionLedgerStore(context: context)
        try deletionLedger.stageUnion([packetTombstone])
        observePhase?("harness.seed-journal")
        try adoptSeededEraseBaseline(coordinator)
        XCTAssertEqual(try deletionLedger.snapshot().entries, [packetTombstone])

        observePhase?("harness.auxiliary-seed")
        for relative in [
            "FieldEvidenceRestore/owned.bin",
            "FieldEvidenceOperations/owned.bin",
            "FieldEvidenceCommerce/entitlement.json",
        ] {
            let url = support.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(relative.utf8).write(to: url)
        }
        observePhase?("harness.cache-seed")
        for rootURL in [
            caches.appendingPathComponent("FieldEvidenceApp"),
            temporary.appendingPathComponent("FieldEvidenceApp"),
        ] {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try Data("owned cache".utf8).write(
                to: rootURL.appendingPathComponent("owned.bin")
            )
        }
        observePhase?("harness.diagnostics")
        await diagnostics.prepare()
        await diagnostics.increment(.reportSaved)
    }

    @MainActor
    func adoptSeededEraseBaseline(_ coordinator: StoreSessionCoordinator) throws {
        let context = coordinator.modelContext
        let journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID,
            allowStateBootstrap: false
        )
        try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
        try context.save()
        try journal.validateAll()
    }

    @MainActor
    func counts(_ context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<Site>()),
            try context.fetchCount(FetchDescriptor<Asset>()),
            try context.fetchCount(FetchDescriptor<WorkflowRecord>()),
            try context.fetchCount(FetchDescriptor<EvidenceFile>()),
            try context.fetchCount(FetchDescriptor<Issue>()),
            try context.fetchCount(FetchDescriptor<Packet>()),
            try context.fetchCount(FetchDescriptor<Report>()),
        ]
    }

    @MainActor
    func assertOnlyCompletionControlRemains(
        _ harness: Harness, oldID: UUID, newID: UUID,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let operations = harness.support.appendingPathComponent("FieldEvidenceOperations")
        let leases = operations.appendingPathComponent("generation-leases")
        let owners = leases.appendingPathComponent("owners")
        let directories: [(URL, [String])] = [
            (operations, ["generation-leases"]),
            (leases, ["mutation.lock", "owners", "registry.json"]),
            (owners, []),
        ]
        for (url, expectedNames) in directories {
            var information = stat()
            guard url.path.withCString({ lstat($0, &information) }) == 0,
                  information.st_mode & S_IFMT == S_IFDIR else {
                XCTFail("Expected an exact completion-control directory", file: file, line: line)
                throw FixtureError.invalid
            }
            XCTAssertEqual(
                try fileManager.contentsOfDirectory(atPath: url.path).sorted(),
                expectedNames, file: file, line: line
            )
        }
        let registry = leases.appendingPathComponent("registry.json")
        let mutationLock = leases.appendingPathComponent("mutation.lock")
        _ = try regularFileIdentity(registry)
        _ = try regularFileIdentity(mutationLock)
        XCTAssertEqual(try Data(contentsOf: registry),
            Data(#"{"leases":[],"schemaVersion":1}"#.utf8), file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: mutationLock), Data(), file: file, line: line)
        for url in [
            harness.support.appendingPathComponent("FieldEvidenceRestore"),
            harness.support.appendingPathComponent("FieldEvidenceCommerce"),
            harness.caches.appendingPathComponent("FieldEvidenceApp"),
            harness.temporary.appendingPathComponent("FieldEvidenceApp"),
        ] {
            XCTAssertFalse(fileManager.fileExists(atPath: url.path), url.path, file: file, line: line)
        }
        let pending = try XCTUnwrap(try EraseIntentStore(
            applicationSupportURL: harness.support
        ).load(), file: file, line: line)
        XCTAssertEqual(pending.phase, .cleanupComplete, file: file, line: line)
        XCTAssertEqual(pending.oldGenerationID, oldID, file: file, line: line)
        XCTAssertEqual(pending.newGenerationID, newID, file: file, line: line)
    }

    func assertAuxiliaryRootsCleared(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for url in [
            harness.support.appendingPathComponent("FieldEvidenceRestore"),
            harness.support.appendingPathComponent("FieldEvidenceOperations"),
            harness.support.appendingPathComponent("FieldEvidenceCommerce"),
            harness.caches.appendingPathComponent("FieldEvidenceApp"),
            harness.temporary.appendingPathComponent("FieldEvidenceApp"),
        ] {
            XCTAssertFalse(
                fileManager.fileExists(atPath: url.path),
                url.path,
                file: file,
                line: line
            )
        }
    }

    func cleanup(_ harness: Harness) {
        harness.defaults.removePersistentDomain(forName: bundleID)
        harness.defaults.removePersistentDomain(forName: harness.defaultsSuiteName)
        harness.coordinator = nil
        // These roots are unique and live under the Simulator's temporary
        // container. A synchronous XCTest defer can still retain a local
        // ModelContext/ModelContainer while it runs, so unlinking the SQLite
        // vnode here is an API violation. The Simulator owns final temp cleanup.
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return {
            guard !remaining.isEmpty else { return UUID() }
            return remaining.removeFirst()
        }
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    func tree(_ root: URL) throws -> [FileFact] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw FixtureError.invalid }
        var facts: [FileFact] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relative = String(
                url.standardizedFileURL.path.dropFirst(
                    root.standardizedFileURL.path.count + 1
                )
            )
            facts.append(FileFact(path: relative, bytes: try Data(contentsOf: url)))
        }
        return facts.sorted { $0.path < $1.path }
    }

    @MainActor
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        verify: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C41EraseRecoveryRetainsSnapshotAndZeroWriteDisposition() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_660)
        let preview = try FunctionalRelationshipDispositionPreviewEngineV1.preview(
            change: .retired,
            relationship: fixture.added,
            descriptor: fixture.descriptor,
            currentSiteID: C41FunctionalRelationshipTestSupportV1.id(41_661)
        )
        let snapshot = try CompletedFunctionalRelationshipSnapshotV1(
            snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_662),
            workspaceID: fixture.workspaceID,
            capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            descriptorReleases: [fixture.descriptor],
            relationships: [fixture.added]
        )

        XCTAssertEqual(preview.disposition, .end)
        XCTAssertFalse(preview.persistentWriteOccurred)
        XCTAssertEqual(snapshot.relationships.count, 1)
        XCTAssertEqual(snapshot.frozenReferences.first?.relationshipID, fixture.relationshipID)
        try snapshot.validate()
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C13EraseRecoveryRetainsRecordedAndVoidedAttestationHistory() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_660)
        let voided = try AttestationV1(
            attestationID: C13EvidenceAssuranceTestSupportV1.id(51_661),
            workspaceID: fixture.workspaceID,
            purpose: fixture.customerAttestation.purpose,
            scope: fixture.customerAttestation.scope,
            manifest: fixture.customerManifest,
            declaredActor: fixture.actor,
            method: fixture.customerAttestation.method,
            action: .voided,
            occurredAt: fixture.customerAttestation.recordedAt.addingTimeInterval(1),
            recordedAt: fixture.customerAttestation.recordedAt.addingTimeInterval(1),
            supersedesAttestationID: fixture.customerAttestation.attestationID,
            revision: 2,
            mutationID: try C13EvidenceAssuranceTestSupportV1.mutation(51_662)
        )
        try voided.validateSuccessor(of: fixture.customerAttestation)
        let row = try AttestationRow(voided)
        let restored = try row.value()

        XCTAssertEqual(fixture.customerAttestation.action, .recorded)
        XCTAssertEqual(restored.action, .voided)
        XCTAssertEqual(restored.supersedesAttestationID, fixture.customerAttestation.attestationID)
        XCTAssertEqual(restored.revision, fixture.customerAttestation.revision + 1)
        try restored.validate(manifest: fixture.customerManifest)
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C14RecoveryRebindPreservesCorrectiveActionEvidence() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_166)
        let rebound = try fixture.actions[3].rebound(to: fixture.otherWorkspaceID)
        XCTAssertEqual(rebound.workspaceID, fixture.otherWorkspaceID)
        XCTAssertEqual(rebound.state, .closed)
        XCTAssertEqual(rebound.closureEvidence, fixture.actions[3].closureEvidence)
        XCTAssertEqual(rebound.eventSHA256.count, 64)
        XCTAssertNotEqual(rebound.eventSHA256, fixture.actions[3].eventSHA256)
    }

    func testV23P03C19ErasePolicyClearsClosureOnlyAtWorkspaceErase() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try MeasurementIntegrityEraseIntentStorePolicyV1.validate()
        XCTAssertTrue(MeasurementIntegrityEraseBoundaryV1.ordinaryDeletionPreservesFrozenHistory)
        XCTAssertTrue(MeasurementIntegrityEraseBoundaryV1.workspaceEraseClearsEntireClosure)
        XCTAssertEqual(fixture.unknownCalibration.status, .unknown)
    }

    func testC20PrivacyTransformEraseQuarantinesPartialEffect() throws {
        let adapter = PrivacyTransformLifecycleAdapterV1(authority: C20PrivacyPublicationAuthorityForAnchors())
        XCTAssertEqual(
            adapter.disposition(hasDerivativeBytes: true, hasManifest: true, hasReview: true, receiptValid: false),
            .quarantinePartialEffect
        )
        XCTAssertEqual(
            adapter.disposition(hasDerivativeBytes: false, hasManifest: false, hasReview: false, receiptValid: false),
            .retain
        )
    }
}

extension S6_6EraseRecoveryTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension S6_6EraseRecoveryTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.importDisposition, "QUARANTINE_THEN_NEW_DRAFT_IDENTITY")
        XCTAssertEqual(V24BackupSurveyDefinitionRecordV1.Kind.allCases, [.identity, .release])
        XCTAssertEqual(PersistentSchemaV24.models.count, 87)
    }
}
extension S6_6EraseRecoveryTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
final class C31LightingAnchorS66EraseRecoveryTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S6_6EraseRecoveryTests {
    @MainActor
    func testV23P03C42EraseRecoveryLeavesNoTypedArchetypeStateBehind() async throws {
        let scenarios = [
            try CompositeAreaSafetyArchetypeV1.scenario(),
            try ControllerZoneDistributionArchetypeV1.scenario()
        ]

        for (index, scenario) in scenarios.enumerated() {
            XCTAssertTrue(scenario.operations.contains { $0.kind == .deleteErase })
            let harness = try await makeHarness("c42-\(index)")
            defer { cleanup(harness) }
            let owner = harness.originalOwner
            let replacementID = UUID(
                uuidString: String(format: "42000000-0000-4000-8000-%012x", index + 1)
            )!
            var completedReceipts = [CompletedEraseReceiptV1]()
            try await { @MainActor () async throws -> Void in
                let coordinator = try XCTUnwrap(harness.coordinator)
                let asset = try XCTUnwrap(
                    coordinator.modelContext.fetch(FetchDescriptor<Asset>()).first
                )
                asset.label = scenario.archetypeID
                try coordinator.modelContext.save()
                try adoptSeededEraseBaseline(coordinator)
                XCTAssertEqual(
                    try coordinator.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label),
                    [scenario.archetypeID]
                )
                try await owner.admit(coordinator: coordinator)
                let service = try owner.configure(EraseAllService(
                    applicationSupportURL: harness.support,
                    cachesDirectoryURL: harness.caches,
                    temporaryDirectoryURL: harness.temporary,
                    userDefaults: harness.defaults,
                    bundleIdentifier: bundleID,
                    defaultsDomainName: harness.defaultsSuiteName,
                    makeUUID: sequence([
                        replacementID,
                        UUID(uuidString: String(
                            format: "42000000-0000-4000-8001-%012x", index + 1
                        ))!,
                    ]),
                    admitErase: { try await owner.admitSubject($0) },
                    didCompleteErase: { completedReceipts.append($0) }
                ))
                Self.retainedS6EraseServices.append((harness.root, service))
                try await owner.prepareCompatibility(service: service,
                    confirmation: "ERASE", coordinator: coordinator,
                    diagnostics: harness.diagnostics)
                harness.coordinator = nil
            }()
            XCTAssertTrue(completedReceipts.isEmpty)
            try await owner.completeCleanup()
            XCTAssertEqual(completedReceipts.count, 1)
            XCTAssertEqual(completedReceipts.first?.subject.newGenerationID, replacementID)
            try await owner.adoptCompletedReceipt()
            try await owner.activateFreshOrdinarySession()
            guard case let .ready(reopened, _, _) = owner.router.route else {
                return XCTFail("C42 Erase must publish a fresh ordinary owner")
            }
            XCTAssertEqual(reopened.generationID, replacementID)
            XCTAssertEqual(try counts(reopened.modelContext), [0, 0, 0, 0, 0, 0, 0])
            assertAuxiliaryRootsCleared(harness)
        }
    }
}

extension S6_6EraseRecoveryTests {
    @MainActor
    func testC33RealEraseRemovesTemporalRowsJournalAndCanonicalOriginalBytes() async throws {
        let harness = try await makeHarness("c33-temporal-evidence")
        defer { cleanup(harness) }
        let owner = harness.originalOwner
        var completedReceipts = [CompletedEraseReceiptV1]()
        let originalURL = try await { @MainActor () async throws -> URL in
            let coordinator = try XCTUnwrap(harness.coordinator)
            let fixture = try C33TemporalEvidenceTestSupport.clip(
                slot: 760,
                workspaceID: coordinator.workspaceIdentity.workspaceID,
                reportProjection: .typedLinkOnly
            )
            let current = try coordinator.workspaceWriter.currentRevision()
            let expected = try C33TemporalEvidenceTestSupport.expectedRevision(
                for: fixture.clip,
                generationID: current.generationID,
                writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision
            )
            let digest = try XCTUnwrap(fixture.clip.original.digests.digest(for: .sha256))
            let contentRequest = try DraftImmutableContentWriteRequestV1(
                workspaceID: fixture.clip.workspaceID,
                contentID: fixture.clip.original.contentID,
                digest: digest,
                byteLength: fixture.clip.original.byteLength,
                mediaType: fixture.clip.original.mediaType,
                mutationID: fixture.clip.mutationID,
                createdAt: fixture.clip.original.createdAt
            )
            _ = try await EvidenceBundleStore(
                generationRootURL: coordinator.generationRootURL
            ).persistImmutableOriginal(
                bytes: C33TemporalEvidenceTestSupport.bytes(for: fixture.clip.facts.kind),
                request: contentRequest
            )
            _ = try coordinator.workspaceWriter.commitTemporalEvidence(TemporalEvidenceMutationV1(
                workspaceID: fixture.clip.workspaceID,
                expectedRevision: expected,
                mutationID: fixture.clip.mutationID,
                payload: .acceptClip(
                    fixture.clip,
                    review: C33TemporalEvidenceTestSupport.review(for: fixture.clip),
                    predecessor: nil
                )
            ))
            XCTAssertEqual(
                try coordinator.modelContext.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()),
                1
            )
            let originalURL = coordinator.generationRootURL.appendingPathComponent(
                try TemporalEvidenceBackupMemberV1.original(for: fixture.clip)
            )
            XCTAssertTrue(fileManager.fileExists(atPath: originalURL.path))
            try await owner.admit(coordinator: coordinator)
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID,
                defaultsDomainName: harness.defaultsSuiteName,
                makeUUID: sequence([
                    uuid("66000000-0000-0000-0000-00000000c331"),
                    uuid("66000000-0000-0000-0000-00000000c332")
                ]),
                admitErase: { try await owner.admitSubject($0) },
                didCompleteErase: { completedReceipts.append($0) }
            ))
            Self.retainedS6EraseServices.append((harness.root, service))
            try await owner.prepareCompatibility(service: service,
                confirmation: "ERASE", coordinator: coordinator,
                diagnostics: harness.diagnostics)
            harness.coordinator = nil
            return originalURL
        }()
        XCTAssertTrue(completedReceipts.isEmpty)
        try await owner.completeCleanup()
        XCTAssertEqual(completedReceipts.count, 1)
        try await owner.adoptCompletedReceipt()
        try await owner.activateFreshOrdinarySession()
        guard case let .ready(reopened, _, _) = owner.router.route else {
            return XCTFail("C33 Erase must publish a fresh ordinary owner")
        }
        XCTAssertEqual(reopened.generationID,
            try XCTUnwrap(completedReceipts.first).subject.newGenerationID)
        // Exact predicate body of validateTemporalEvidenceEraseClosure, read
        // through the Router's published coordinator without a second lease.
        XCTAssertEqual(
            try reopened.modelContext.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 0
        )
        XCTAssertEqual(
            try reopened.modelContext.fetchCount(FetchDescriptor<TimecodedEvidenceAnchorRow>()), 0
        )
        let contentRoot = reopened.generationRootURL.appendingPathComponent(
            "content", isDirectory: true
        )
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: contentRoot.path, isDirectory: &isDirectory) {
            XCTAssertTrue(isDirectory.boolValue)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: contentRoot.path).isEmpty)
        }
        try TemporalEvidenceEraseAllEnrollmentV1.validate()
        XCTAssertEqual(
            try reopened.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0
        )
        XCTAssertFalse(fileManager.fileExists(atPath: originalURL.path))
    }
}

final class C33TemporalEvidenceAnchorS66EraseRecovery: XCTestCase {
    func testC33S66EraseRecoveryCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "erase.temporal-evidence-no-orphan",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "erase.temporal-evidence-no-orphan",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

final class C32AssistanceAnchorS66EraseRecovery: XCTestCase {
    func testC32S66EraseRecoveryCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .site,
            fieldID: "erase.workspace-receipt",
            value: .boolean(true)
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .site,
            fieldID: "erase.workspace-receipt",
            valueKind: .boolean
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
final class C46S66EraseRecoveryCompatibilityTests: XCTestCase {
    func testC46EraseRecoveryKeepsContactWorkspaceScoped() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "erase-recovery",
            kind: .phone,
            handoff: .text,
            slot: 46606
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift_Tests: XCTestCase {
    func testC47S66EraseRecoveryTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_6EraseRecoveryTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

final class C48PortableReviewS66EraseTests: XCTestCase {
    func testC48EraseRemovesAppOwnedExchangeStaging() {
        XCTAssertTrue(C48PortableExchangePersistentLifecycleBoundaryV2.eraseRemovesAppOwnedStagingOnly)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.quarantineIsExcludedFromBackup)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.sessionStoreIsNonpersistent)
    }
}
final class C49WorkResourceEraseBoundaryTests: XCTestCase {
    func testEraseClassificationIncludesEmbeddedCostNotASecondLedger() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.directCostIsEmbedded)
        XCTAssertFalse(C49WorkResourceContractBoundaryV1.liveInventoryReference)
        XCTAssertTrue(C49WorkResourcePersistenceBoundaryV1.appendOnlyHistory)
    }
}

final class C50IncumbentAdapterS66EraseBoundaryTests: XCTestCase {
    func testEraseClearsOnlyAppOwnedExchangeScratchAndQuarantine() {
        XCTAssertTrue(C50IncumbentFileExchangeEraseAllBoundaryV1.removesAppOwnedScratch)
        XCTAssertTrue(C50IncumbentFileExchangeEraseAllBoundaryV1.removesAppOwnedQuarantine)
        XCTAssertFalse(C50IncumbentFileExchangeEraseAllBoundaryV1.recallsEscapedFiles)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentStoreBoundaryV1.appOwnedScratchParticipatesInEraseInventory)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentStoreBoundaryV1.appOwnedQuarantineParticipatesInEraseInventory)
    }
}

extension C45EraseRecoveryCompatibilityTests {
    func testV23P03C51EraseClearsFourScheduleFamiliesAsOneClosure() {
        XCTAssertTrue(
            ScheduleEraseBoundaryV1.validate()
                && ScheduleEraseBoundaryV1.atomicFamilyCount == 4
                && ScheduleEraseBoundaryV1.embeddedClosureComponentCount == 6
                && !ScheduleEraseBoundaryV1.notificationStateIsTruth
        )
    }
}

private actor C54EncryptedEnvelopeEraseProbe: EncryptedPortableEnvelopeEraseScratchV1 {
    private var eraseCount = 0

    func eraseEncryptedPortableEnvelopeScratch() async throws {
        eraseCount += 1
    }

    func count() -> Int { eraseCount }
}

extension S6_6EraseRecoveryTests {
    func testV23P03C54EraseRemovesOnlyAppOwnedEnvelopeScratchAndCreatesNoCanonicalRows() async throws {
        let probe = C54EncryptedEnvelopeEraseProbe()

        try await C54EncryptedPortableEnvelopeEraseAllBoundaryV1.eraseScratch(using: probe)
        let eraseCount = await probe.count()

        XCTAssertEqual(eraseCount, 1)
        XCTAssertTrue(C54EncryptedPortableEnvelopeEraseAllBoundaryV1.validate())
        XCTAssertTrue(C54EncryptedPortableEnvelopeEraseAllBoundaryV1.removesAppOwnedAttemptScratch)
        XCTAssertTrue(C54EncryptedPortableEnvelopeEraseAllBoundaryV1.clearsMemoryOnlySecrets)
        XCTAssertFalse(C54EncryptedPortableEnvelopeEraseAllBoundaryV1.recallsEscapedFiles)
        XCTAssertFalse(C54EncryptedPortableEnvelopeEraseAllBoundaryV1.revokesAlreadySharedBytes)
        XCTAssertFalse(C54EncryptedPortableEnvelopeEraseAllBoundaryV1.createsCanonicalDeletionRows)
    }
}

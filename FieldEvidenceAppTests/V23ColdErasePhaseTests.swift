import Darwin
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

/// Exercises the historical schema-2 pointer cut through the real cold Router.
/// The C05 V3 job-drain continuation is a separate, still-unimplemented case.
final class V23ColdErasePhaseTests: XCTestCase {
    @MainActor private static var retainedOriginalServices: [EraseAllService] = []
    @MainActor private static var retainedColdOwners:
        [(URL, StartupRouter, AppAccessGateV1, EraseAllService)] = []

    private actor Authentication: LocalAuthenticationClient {
        func availability() -> LocalAuthenticationAvailabilityV1 {
            .systemValue(status: .available, biometry: .faceID)
        }
        func authenticate(_ attempt: LocalAuthenticationAttemptV1)
            -> LocalAuthenticationOutcomeV1 { .authenticated }
        func cancel(attemptID: UUID) {}
    }

    /// The same port the original and cold owners use for OS readback. Its
    /// pending and delivered observations are seeded only for the populated
    /// notification fixture; removal is an actual port effect in that fixture.
    @MainActor
    private final class NotificationProbe: NotificationSystemPortV1 {
        private(set) var observed: [NotificationSystemObservationV1]
        private(set) var removedIDs: [String] = []
        private(set) var observationCount = 0

        init(observed: [NotificationSystemObservationV1]) {
            self.observed = observed
        }

        func authorization() async throws -> LocalReminderAuthorizationV1 {
            .authorized
        }

        func observations() async throws -> [NotificationSystemObservationV1] {
            observationCount += 1
            return observed
        }

        func add(_ request: NotificationSystemRequestV1) async throws {
            observed.append(.init(requestID: request.notification.requestID,
                request: request, delivered: false))
        }

        func remove(_ requestIDs: [String]) async throws {
            removedIDs.append(contentsOf: requestIDs)
            observed.removeAll { requestIDs.contains($0.requestID) }
        }
    }

    @MainActor
    private struct NotificationSeed {
        let probe: NotificationProbe
        let ownedIDs: Set<String>
    }

    private enum FixtureFailure: Error { case missingOriginalFault, activation, coldRoute }

    private func requireAbsentWithoutFollowing(_ url: URL) throws {
        var status = stat()
        let result = url.path.withCString { lstat($0, &status) }
        guard result == -1, errno == ENOENT else {
            throw FixtureFailure.activation
        }
    }

    /// Compare the actual canonical pointer and manifest to the operation's
    /// authenticated target, not merely to a byte snapshot taken after fault.
    private func requireTargetPointerBinding(
        support: URL, intent: EraseIntentV1, pointerBytes: Data
    ) throws {
        let expected = try XCTUnwrap(intent.targetPointer)
        let pointer = try CurrentGenerationPointerV3.decodeCanonical(
            from: pointerBytes)
        let manifestURL = support.appendingPathComponent(
            "FieldEvidenceOperations/schema-migration/manifest-"
                + intent.newGenerationID.uuidString.lowercased() + ".json")
        let manifest = try StoreGenerationManifestV1.decodeCanonical(
            from: Data(contentsOf: manifestURL))
        guard pointer.generationID
                == intent.newGenerationID.uuidString.lowercased(),
              pointer.generationID == expected.generationID.uuidString.lowercased(),
              pointer.generationManifestSHA256
                == expected.generationManifestSHA256,
              pointer.generationManifestSHA256
                == (try manifest.canonicalSHA256()),
              pointer.workspaceID == expected.workspaceID.uuidString.lowercased(),
              pointer.replicaID == expected.replicaID.uuidString.lowercased(),
              pointer.knownReplicaIDs
                == expected.knownReplicaIDs.map { $0.uuidString.lowercased() }.sorted(),
              manifest.generationID == intent.newGenerationID else {
            throw FixtureFailure.activation
        }
    }

    private struct PhysicalFact: Equatable {
        let device: UInt64
        let inode: UInt64
        let mode: UInt32
        let links: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        let bytes: Data?
    }

    /// Capture every named canonical data/Erase/schema-migration node. This
    /// includes the original and target SQLite, WAL and SHM bytes and inode
    /// facts, while excluding a cold attempt's separately owned Registry and
    /// private-copy workspace from the pre-effect baseline.
    private func protectedFacts(in support: URL) throws -> [String: PhysicalFact] {
        var result: [String: PhysicalFact] = [:]
        for root in ["FieldEvidenceData", "FieldEvidenceErase",
                     "FieldEvidenceOperations/schema-migration"] {
            let directory = support.appendingPathComponent(root, isDirectory: true)
            let descendants = try FileManager.default.subpathsOfDirectory(
                atPath: directory.path).sorted()
            for relative in [root] + descendants.map({ root + "/" + $0 }) {
                let url = support.appendingPathComponent(relative)
                var status = stat()
                guard url.path.withCString({ lstat($0, &status) }) == 0 else {
                    throw FixtureFailure.activation
                }
                let kind = status.st_mode & S_IFMT
                guard kind == S_IFREG || kind == S_IFDIR else {
                    throw FixtureFailure.activation
                }
                let bytes = kind == S_IFREG ? try Data(contentsOf: url) : nil
                result[relative] = PhysicalFact(
                    device: UInt64(status.st_dev), inode: UInt64(status.st_ino),
                    mode: UInt32(status.st_mode), links: UInt64(status.st_nlink),
                    size: Int64(status.st_size),
                    modifiedSeconds: Int(status.st_mtimespec.tv_sec),
                    modifiedNanoseconds: Int(status.st_mtimespec.tv_nsec),
                    changedSeconds: Int(status.st_ctimespec.tv_sec),
                    changedNanoseconds: Int(status.st_ctimespec.tv_nsec),
                    bytes: bytes)
            }
        }
        return result
    }

    @MainActor
    private func seedOriginalSign(_ coordinator: StoreSessionCoordinator) throws {
        let mutationID = try MutationIDV1(rawValue: UUID())
        let siteID = UUID()
        _ = try coordinator.workspaceWriter.execute(.createFirstSign(FirstSignMutationV1(
            siteID: siteID,
            newSite: .init(id: siteID, label: "Cold Erase source", address: nil,
                timeZoneID: nil),
            assetID: UUID(), assetLabel: "Cold Erase asset",
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            initialPlacementMutationID: mutationID,
            initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        )), mutationID: mutationID)
        let journal = try MutationJournalStoreV1(modelContext: coordinator.modelContext,
            identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID)
        XCTAssertNotNil(try journal.receipt(mutationID: mutationID))
        try journal.validateAll()
    }

    @MainActor
    private final class CompletionBox { var count = 0 }

    @MainActor
    private struct PointerFixture {
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
        let defaults: UserDefaults
        let defaultsName: String
        let intent: EraseIntentV1
        let pointerBefore: Data
        let completion: CompletionBox
        let preexistingRetiredIDs: [UUID]
        let notificationSeed: NotificationSeed?
        var pointerURL: URL { support.appendingPathComponent("FieldEvidenceData/current.json") }
        var intentURL: URL { support.appendingPathComponent("FieldEvidenceErase/erase.json") }
    }

    /// Publish a genuine app-lock notification control whose two typed
    /// projections bind the IDs observed by the system port. The original
    /// after-session-phase fault precedes cleanup's notification drain, so
    /// these observations must still exist at the checked cold handoff.
    @MainActor
    private func seedPendingAndDeliveredNotifications(
        support: URL, defaults: UserDefaults
    ) throws -> NotificationSeed {
        let preferences = PreferencesAdapterV1(defaults: defaults)
        let policy = try preferences.readReminderPolicy()
        let requests = try ["a", "b"].map { token in
            let request = NotificationSystemRequestV1(notification: .init(
                requestID: UUID().uuidString.lowercased(),
                opaqueCorrelationToken: String(repeating: token, count: 64)),
                fireAtUTC: Date(timeIntervalSince1970: 1_900_000_000))
            try request.validate()
            return request
        }
        let notificationOperationID = UUID()
        let journal = try AppLockNotificationJournalV1(
            operationID: notificationOperationID, targetEnabled: true,
            priorPolicy: policy.appLockReference(),
            projections: requests.map(\.notification),
            disposition: .enablingPrepared)
        let plan = try preferences.planAppLockSettingWrite(
            expectedSetting: preferences.readAppLockSettingSnapshot(),
            expectedReminderPolicy: policy, target: .init(isEnabled: true),
            operationID: notificationOperationID)
        let control = try AppLockNotificationControlStoreV1(
            applicationSupportURL: support, preferences: preferences)
        let prepared = try control.prepareControl(journal: journal,
            priorReminderPolicy: policy, settingWrite: plan,
            expectedPredecessor: nil)
        XCTAssertEqual(try control.loadControl(), prepared)
        let observations = requests.enumerated().map { index, request in
            NotificationSystemObservationV1(
                requestID: request.notification.requestID,
                request: request, delivered: index == 1)
        }
        return NotificationSeed(probe: NotificationProbe(observed: observations),
            ownedIDs: Set(requests.map(\.notification.requestID)))
    }

    /// Build actual retired pointers and installed generations before the
    /// original Router opens. The first source has a real committed sign;
    /// the second retired source is the empty target of the first publication.
    @MainActor
    private func makeTwoPreexistingRetiredSources(support: URL) throws -> [UUID] {
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        try autoreleasepool {
            let session = try factory.openOrBootstrapCurrent()
            let coordinator = try StoreSessionCoordinator(validatingSession: session)
            try seedOriginalSign(coordinator)
            try coordinator.invalidateAndReleaseWriter()
        }
        var retired: [UUID] = []
        for _ in 0..<2 {
            let observed = try autoreleasepool { () throws ->
                (CurrentGenerationPointerV3, WorkspaceReplicaIdentityV1) in
                let session = try factory.openOrBootstrapCurrent()
                return (try factory.currentGenerationPointerV3(
                    expectedGenerationID: session.generationID),
                    session.workspaceIdentity)
            }
            let pointer = observed.0
            let oldID = try XCTUnwrap(UUID(uuidString: pointer.generationID))
            let identity = RestorePointerIdentityV1(generationID: oldID,
                generationManifestSHA256: pointer.generationManifestSHA256,
                knownReplicaIDs: Set(try pointer.knownReplicaIdentitySet().map(\.rawValue)),
                workspaceID: observed.1.workspaceID.rawValue,
                replicaID: observed.1.replicaID.rawValue)
            let authority = try factory.makeRestoreGenerationAuthority()
            let nextID = UUID()
            let created = try factory.createEmptyEraseGeneration(id: nextID,
                expectedOldPointer: identity, identity: observed.1, authority: authority)
            try factory.publishEmptyEraseGeneration(expectedOldPointer: identity,
                targetPointer: created.pointer, expectedEmptyLedger: created.ledgerProof,
                authority: authority)
            try factory.retireGeneration(oldID: oldID, currentID: nextID,
                authority: authority)
            retired.append(oldID)
            XCTAssertEqual(try factory.currentGenerationID(), nextID)
            XCTAssertEqual(Set(try factory.retiredGenerationIDs()), Set(retired))
        }
        XCTAssertEqual(try factory.makeGenerationLeaseRegistry().activeEpochs(), [])
        return retired
    }

    /// A value-only result after the exact original operation's checked exit.
    /// The host retains its root and configured Service even if a later cold
    /// opening fails; no fixture deinit can authorize file cleanup.
    @MainActor
    private func makeOriginalColdCut(
        at fault: EraseAllFailurePoint = .afterPointerPhaseWrite,
        seedTwoPreexistingRetired: Bool = false,
        seedNotifications: Bool = false
    ) async throws -> PointerFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-schema2-cold-phase-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let preexistingRetiredIDs = seedTwoPreexistingRetired
            ? try makeTwoPreexistingRetiredSources(support: support) : []
        let profiles = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        let runtime = StoreKitEntitlementRuntimeV1(initialEvents: { [] },
            transactionUpdates: { AsyncStream { $0.finish() } },
            statusUpdates: { AsyncStream { $0.finish() } })
        let original = V23EraseOperationHarnessV1(retainingRoot: root,
            applicationSupportURL: support, runtime: runtime, profileRegistry: profiles)
        defer { original.router.entitlementProcessor?.stop() }
        let defaultsName = "V23-schema2-cold-phase-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let newID = UUID()
        let completion = CompletionBox()
        var notificationSeed: NotificationSeed?
        weak var sourceContext: ModelContext?
        weak var sourceContainer: ModelContainer?

        let interrupted = try await { () async throws -> (EraseIntentV1, EraseRouterOperationV1) in
            let (coordinator, diagnostics) = try await original.startOriginalOwner()
            sourceContext = coordinator.modelContext
            sourceContainer = coordinator.modelContext.container
            let sourceID = coordinator.generationID
            try seedOriginalSign(coordinator)
            try await original.admit(coordinator: coordinator)
            let operation = try original.originalOperationForInterruption()
            if seedNotifications {
                notificationSeed = try seedPendingAndDeliveredNotifications(
                    support: support, defaults: defaults)
            }
            var nextID = newID
            let service = EraseAllService(applicationSupportURL: support,
                cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                userDefaults: defaults, bundleIdentifier: "com.palatis3.fieldrecord",
                defaultsDomainName: defaultsName,
                makeUUID: { defer { nextID = UUID() }; return nextID },
                failureInjection: EraseAllFailureInjection(failOnceAt: fault),
                notificationSystem: notificationSeed?.probe,
                admitErase: { try await original.admitSubject($0) },
                didCompleteErase: { _ in completion.count += 1 })
            let configured = try original.configure(service)
            Self.retainedOriginalServices.append(configured)
            var activationFailure: Error?
            do {
                _ = try await configured.erase(
                    confirmation: EraseAllService.requiredConfirmation,
                    coordinator: coordinator, diagnosticsStore: diagnostics,
                    operation: operation,
                    activate: { [weak coordinator, weak router = original.router] session in
                        do {
                            guard let coordinator, let router else {
                                throw FixtureFailure.activation
                            }
                            try router.activateErasePreparationSession(session,
                                coordinator: coordinator, operation: operation)
                        } catch { activationFailure = error }
                    })
                throw FixtureFailure.missingOriginalFault
            } catch EraseAllServiceError.injectedFailure { }
            catch {
                FileHandle.standardError.write(Data((
                    "V23_COLD_NOTIFICATION_FIXTURE_V1 phase="
                    + configured.eraseFixedPhaseForTesting
                    + " fixed-history="
                    + configured.eraseFixedPhaseHistoryForTesting.joined(separator: ",")
                    + " prepared-failure="
                    + configured.erasePreparedFailureCategoryForTesting
                    + " rollback="
                    + configured.erasePreparedRollbackStateForTesting
                    + " first-catch="
                    + configured.eraseFirstCatchBoundaryForTesting
                    + " first-error="
                    + configured.eraseFirstCatchCategoryForTesting
                    + " category=unexpected-original-erase\n"
                ).utf8))
                throw error
            }
            if let activationFailure { throw activationFailure }
            let intent = try configured.interruptedRetiredAuthorityIntentForTesting(
                fault, operation: operation)
            XCTAssertEqual(intent.schemaVersion, 2)
            XCTAssertEqual(intent.phase,
                fault == .afterSessionPhaseWrite ? .sessionActivated : .pointerSwitched)
            XCTAssertEqual(intent.oldGenerationID, sourceID)
            XCTAssertEqual(intent.newGenerationID, newID)
            XCTAssertEqual(completion.count, 0)
            try await original.router.beginInterruptedEarlyEraseColdRestartForTesting(
                operation, originalService: configured,
                expectedFault: fault)
            return (intent, operation)
        }()
        let intent = interrupted.0
        let operation = interrupted.1
        let drain = expectation(for: NSPredicate { _, _ in
            sourceContext == nil && sourceContainer == nil
        }, evaluatedWith: NSObject())
        await fulfillment(of: [drain], timeout: 30)
        XCTAssertNil(sourceContext)
        XCTAssertNil(sourceContainer)
        try original.router.finishInterruptedEarlyEraseColdRestartForTesting(operation)
        XCTAssertThrowsError(try operation.completedRetirement())
        XCTAssertEqual(completion.count, 0)
        let pointerURL = support.appendingPathComponent("FieldEvidenceData/current.json")
        let intentURL = support.appendingPathComponent("FieldEvidenceErase/erase.json")
        let pointerBefore = try Data(contentsOf: pointerURL)
        XCTAssertEqual(try EraseIntentCodecV1.decode(Data(contentsOf: intentURL)).phase,
            intent.phase)
        try requireTargetPointerBinding(support: support, intent: intent,
            pointerBytes: pointerBefore)
        if let notificationSeed {
            XCTAssertEqual(Set(notificationSeed.probe.observed.map(\.requestID)),
                notificationSeed.ownedIDs)
            XCTAssertEqual(Set(notificationSeed.probe.observed.map(\.delivered)),
                Set([false, true]))
            XCTAssertTrue(notificationSeed.probe.removedIDs.isEmpty)
        }

        return PointerFixture(root: root, support: support, caches: caches,
            temporary: temporary, defaults: defaults, defaultsName: defaultsName,
            intent: intent, pointerBefore: pointerBefore, completion: completion,
            preexistingRetiredIDs: preexistingRetiredIDs,
            notificationSeed: notificationSeed)
    }

    /// The injected original fault is after its real pointer-phase CAS. Cold
    /// recovery must open and retain the empty target session before writing
    /// sessionActivated, and only later publish the fresh Router coordinator.
    @MainActor
    func testSchema2PointerSwitchedColdOpensActualEmptyTargetBeforeSessionPhaseCAS() async throws {
        let fixture = try await makeOriginalColdCut()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let root = fixture.root
        let support = fixture.support
        let caches = fixture.caches
        let temporary = fixture.temporary
        let defaults = fixture.defaults
        let defaultsName = fixture.defaultsName
        let intent = fixture.intent
        let pointerBefore = fixture.pointerBefore
        let pointerURL = fixture.pointerURL
        let intentURL = fixture.intentURL
        let profiles = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()

        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authentication, .authenticated)
        let cold = StartupRouter(applicationSupportURL: support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: profiles)
        let recovery = EraseAllService(applicationSupportURL: support,
            cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
            userDefaults: defaults, bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: defaultsName)
        // The callback is copied onto the Router-configured cold Service. It
        // fires only after Factory's real installed target open and operation
        // retention, immediately before the pointerSwitched→sessionActivated CAS.
        var liveTargetCount = 0
        var liveTargetFailure: Error?
        let targetURL = support.appendingPathComponent("FieldEvidenceData/generations",
            isDirectory: true).appendingPathComponent(
                intent.newGenerationID.uuidString.lowercased(), isDirectory: true)
        recovery.schema2ColdBeforeSessionPhaseCASForTesting = { session in
            liveTargetCount += 1
            do {
                guard session.generationID == intent.newGenerationID,
                      session.readerLeaseToken != nil,
                      session.generationRootURL.standardizedFileURL
                        == targetURL.standardizedFileURL,
                      try EraseIntentCodecV1.decode(Data(contentsOf: intentURL)).phase
                        == .pointerSwitched,
                      try Data(contentsOf: pointerURL) == pointerBefore,
                      BackupRestoreService.isEmptyCurrent(session.modelContext),
                      try session.modelContext.fetchCount(
                        FetchDescriptor<MutationReceiptRow>()) == 0 else {
                    throw FixtureFailure.activation
                }
                try self.requireTargetPointerBinding(support: support,
                    intent: intent, pointerBytes: Data(contentsOf: pointerURL))
                XCTAssertTrue(session.modelContext.container.mainContext
                    === session.modelContext)
            } catch { liveTargetFailure = error }
        }
        Self.retainedColdOwners.append((root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        try await cold.retryColdEraseForTesting(service: recovery, accessGate: gate)
        if let liveTargetFailure { throw liveTargetFailure }
        XCTAssertEqual(liveTargetCount, 1,
            "Cold phase CAS cannot be reached by a private copy or phase-only fixture")
        guard case let .ready(fresh, diagnostics, _) = cold.route else {
            throw FixtureFailure.coldRoute
        }
        XCTAssertEqual(fresh.generationID, intent.newGenerationID)
        XCTAssertTrue(BackupRestoreService.isEmptyCurrent(fresh.modelContext))
        XCTAssertEqual(try fresh.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        // Borrow the already published writer's own provider. The durable
        // registry readback is the same one-writer observation used by the S2
        // ready-owner controls; no second Registry or writer is constructed.
        let readyWriter = fresh.workspaceWriter
        let readyOwner = try fresh.originalAssetLabelFixtureJobOwnerForTesting(
            expectedWriter: readyWriter)
        XCTAssertEqual(try readyOwner.registry.activeEpochs(), [readyOwner.epoch])
        XCTAssertEqual(try readyWriter.currentRevision().generationID,
            intent.newGenerationID)
        let registryURL = support.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/registry.json")
        let registryData = try Data(contentsOf: registryURL)
        let registryObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: registryData) as? [String: Any])
        let leases = try XCTUnwrap(registryObject["leases"] as? [[String: Any]])
        XCTAssertEqual(leases.filter {
            $0["role"] as? String == GenerationLeaseRoleV1.writer.rawValue
        }.count, 1)
        let freshDiagnostics = await diagnostics.snapshot()
        XCTAssertEqual(freshDiagnostics, .zero)
        try requireAbsentWithoutFollowing(intentURL)
        let sourceURL = support.appendingPathComponent("FieldEvidenceData/generations",
            isDirectory: true).appendingPathComponent(
                intent.oldGenerationID.uuidString.lowercased(), isDirectory: true)
        try requireAbsentWithoutFollowing(sourceURL)
        XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBefore)
        try requireTargetPointerBinding(support: support, intent: intent,
            pointerBytes: Data(contentsOf: pointerURL))
        XCTAssertEqual(fixture.completion.count, 0)
    }

    /// A reserved retired-pointer temporary with alien bytes is inserted only
    /// after the original operation's authenticated pointer CAS and checked
    /// shutdown. Cold recovery must refuse before opening the live target or
    /// changing any canonical generation/control node.
    @MainActor
    func testSchema2PointerSwitchedWrongRetiredTemporaryRefusesWithoutCanonicalEffects() async throws {
        let fixture = try await makeOriginalColdCut()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let temporaryPointer = fixture.support.appendingPathComponent(
            "FieldEvidenceData/.retired.json.restore-next")
        let hostileBytes = Data("not-an-empty-retired-pointer".utf8)
        try hostileBytes.write(to: temporaryPointer)
        let before = try protectedFacts(in: fixture.support)
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authentication, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        var coldCompletionCount = 0
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName,
            didCompleteErase: { _ in coldCompletionCount += 1 })
        var liveTargetCount = 0
        recovery.schema2ColdBeforeSessionPhaseCASForTesting = { _ in
            liveTargetCount += 1
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        try await cold.retryColdEraseForTesting(service: recovery, accessGate: gate)
        guard case .maintenance(.eraseInconsistent) = cold.route else {
            throw FixtureFailure.coldRoute
        }
        XCTAssertEqual(liveTargetCount, 0,
            "Alien retired-pointer temporary reached the live target session")
        XCTAssertEqual(try protectedFacts(in: fixture.support), before,
            "Cold refusal changed a canonical control or source/target SQLite sidecar")
        XCTAssertEqual(try Data(contentsOf: temporaryPointer), hostileBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), fixture.pointerBefore)
        XCTAssertEqual(try EraseIntentCodecV1.decode(
            Data(contentsOf: fixture.intentURL)), fixture.intent)
        XCTAssertEqual(fixture.completion.count, 0)
        XCTAssertEqual(coldCompletionCount, 0)
    }

    /// The original operation writes sessionActivated before this fault. Its
    /// checked shutdown, rather than a fabricated cold intent or session,
    /// supplies the fresh Router with an authentic first R entry and no
    /// displaced P temporary. The target session must already be retained
    /// when the typed R callback runs; cleanup and writer publication follow.
    @MainActor
    func testSchema2OriginalSessionPhaseCutColdRResumesActualTargetAndReady() async throws {
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let intent = fixture.intent
        XCTAssertEqual(intent.phase, .sessionActivated)
        XCTAssertEqual(try EraseIntentCodecV1.decode(
            Data(contentsOf: fixture.intentURL)), intent)
        let displacedTemporary = fixture.support.appendingPathComponent(
            "FieldEvidenceErase/.erase.json.next")
        try requireAbsentWithoutFollowing(displacedTemporary)
        let pointerBefore = fixture.pointerBefore
        try requireTargetPointerBinding(support: fixture.support, intent: intent,
            pointerBytes: pointerBefore)

        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authentication, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry:
                try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName)
        var actualRSessionCount = 0
        var actualRSessionFailure: Error?
        let targetURL = fixture.support.appendingPathComponent(
            "FieldEvidenceData/generations", isDirectory: true)
            .appendingPathComponent(
                intent.newGenerationID.uuidString.lowercased(), isDirectory: true)
        // S2's typed first-R observation runs after the real Factory opening,
        // checked reader acquisition and Router physical/token reproof. It
        // does not manufacture a session or bypass the R forward owner.
        recovery.schema2ColdActivatedEntrySessionForTesting = { session in
            actualRSessionCount += 1
            do {
                guard session.generationID == intent.newGenerationID,
                      session.readerLeaseToken != nil,
                      session.generationRootURL.standardizedFileURL
                        == targetURL.standardizedFileURL,
                      session.modelContext.container.mainContext
                        === session.modelContext,
                      BackupRestoreService.isEmptyCurrent(session.modelContext),
                      try session.modelContext.fetchCount(
                        FetchDescriptor<MutationReceiptRow>()) == 0,
                      try EraseIntentCodecV1.decode(Data(contentsOf:
                        fixture.intentURL)) == intent,
                      try Data(contentsOf: fixture.pointerURL)
                        == pointerBefore else {
                    throw FixtureFailure.activation
                }
                try self.requireAbsentWithoutFollowing(displacedTemporary)
                try self.requireTargetPointerBinding(support: fixture.support,
                    intent: intent, pointerBytes: Data(contentsOf:
                        fixture.pointerURL))
            } catch { actualRSessionFailure = error }
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        try await cold.retryColdEraseForTesting(service: recovery,
            accessGate: gate)
        if let actualRSessionFailure { throw actualRSessionFailure }
        XCTAssertEqual(actualRSessionCount, 1,
            "R entry must retain the genuine target session before cleanup")
        guard case let .ready(fresh, diagnostics, _) = cold.route else {
            throw FixtureFailure.coldRoute
        }
        XCTAssertEqual(fresh.generationID, intent.newGenerationID)
        XCTAssertTrue(BackupRestoreService.isEmptyCurrent(fresh.modelContext))
        XCTAssertEqual(try fresh.modelContext.fetchCount(
            FetchDescriptor<MutationReceiptRow>()), 0)
        let readyWriter = fresh.workspaceWriter
        let readyOwner = try fresh.originalAssetLabelFixtureJobOwnerForTesting(
            expectedWriter: readyWriter)
        XCTAssertEqual(try readyOwner.registry.activeEpochs(), [readyOwner.epoch])
        XCTAssertEqual(try readyWriter.currentRevision().generationID,
            intent.newGenerationID)
        let registryURL = fixture.support.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/registry.json")
        let registryData = try Data(contentsOf: registryURL)
        let registryObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: registryData) as? [String: Any])
        let leases = try XCTUnwrap(registryObject["leases"] as? [[String: Any]])
        XCTAssertEqual(leases.filter {
            $0["role"] as? String == GenerationLeaseRoleV1.writer.rawValue
        }.count, 1)
        let freshDiagnostics = await diagnostics.snapshot()
        XCTAssertEqual(freshDiagnostics, .zero)
        try requireAbsentWithoutFollowing(fixture.intentURL)
        try requireAbsentWithoutFollowing(displacedTemporary)
        let sourceURL = fixture.support.appendingPathComponent(
            "FieldEvidenceData/generations", isDirectory: true)
            .appendingPathComponent(intent.oldGenerationID.uuidString.lowercased(),
                isDirectory: true)
        try requireAbsentWithoutFollowing(sourceURL)
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), pointerBefore)
        try requireTargetPointerBinding(support: fixture.support, intent: intent,
            pointerBytes: Data(contentsOf: fixture.pointerURL))
        XCTAssertEqual(fixture.completion.count, 0)
    }

    /// Two real pointer publications retire two installed generations before
    /// the original Erase starts. Its authentic R fault freezes those IDs and
    /// its then-current source as one deletion roster. The fresh Router must
    /// retain the actual empty target while all three old roots are still
    /// present, then remove the entire frozen roster before publishing ready.
    /// A crash between individual unlinks needs a separate production cut.
    @MainActor
    func testSchema2MultiRetiredOriginalRCutColdCleansEntireFrozenRoster() async throws {
        let fixture = try await makeOriginalColdCut(
            at: .afterSessionPhaseWrite, seedTwoPreexistingRetired: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let intent = fixture.intent
        XCTAssertEqual(intent.phase, .sessionActivated)
        XCTAssertEqual(fixture.preexistingRetiredIDs.count, 2)
        let frozenIDs = intent.generationIDsToDelete
        XCTAssertEqual(frozenIDs.count, 3)
        XCTAssertEqual(Set(frozenIDs).count, 3)
        XCTAssertEqual(Set(frozenIDs), Set(fixture.preexistingRetiredIDs + [intent.oldGenerationID]))
        XCTAssertEqual(frozenIDs, frozenIDs.sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        })
        let generationsURL = fixture.support.appendingPathComponent(
            "FieldEvidenceData/generations", isDirectory: true)
        let expectedInstalled = Set((frozenIDs + [intent.newGenerationID]).map {
            $0.uuidString.lowercased()
        })
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(
            atPath: generationsURL.path)), expectedInstalled)
        let oldPrefixes = frozenIDs.map {
            "FieldEvidenceData/generations/" + $0.uuidString.lowercased()
        }
        let preColdOldFacts = try protectedFacts(in: fixture.support).filter {
            entry in oldPrefixes.contains {
                entry.key == $0 || entry.key.hasPrefix($0 + "/")
            }
        }
        XCTAssertEqual(preColdOldFacts.filter { oldPrefixes.contains($0.key) }.count, 3)
        let pointerBefore = fixture.pointerBefore
        try requireTargetPointerBinding(support: fixture.support,
            intent: intent, pointerBytes: pointerBefore)
        let displacedTemporary = fixture.support.appendingPathComponent(
            "FieldEvidenceErase/.erase.json.next")
        try requireAbsentWithoutFollowing(displacedTemporary)

        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authentication, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry:
                try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        var coldCompletionCount = 0
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName,
            didCompleteErase: { _ in coldCompletionCount += 1 })
        var actualRSessionCount = 0
        var actualRSessionFailure: Error?
        let targetURL = generationsURL.appendingPathComponent(
            intent.newGenerationID.uuidString.lowercased(), isDirectory: true)
        recovery.schema2ColdActivatedEntrySessionForTesting = { session in
            actualRSessionCount += 1
            do {
                guard session.generationID == intent.newGenerationID,
                      session.readerLeaseToken != nil,
                      session.generationRootURL.standardizedFileURL
                        == targetURL.standardizedFileURL,
                      session.modelContext.container.mainContext
                        === session.modelContext,
                      BackupRestoreService.isEmptyCurrent(session.modelContext),
                      try session.modelContext.fetchCount(
                        FetchDescriptor<MutationReceiptRow>()) == 0,
                      try EraseIntentCodecV1.decode(Data(contentsOf:
                        fixture.intentURL)) == intent,
                      try Data(contentsOf: fixture.pointerURL) == pointerBefore else {
                    throw FixtureFailure.activation
                }
                try self.requireAbsentWithoutFollowing(displacedTemporary)
                try self.requireTargetPointerBinding(support: fixture.support,
                    intent: intent, pointerBytes: Data(contentsOf:
                        fixture.pointerURL))
                XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(
                    atPath: generationsURL.path)), expectedInstalled)
                let actualOldFacts = try self.protectedFacts(in: fixture.support).filter {
                    entry in oldPrefixes.contains {
                        entry.key == $0 || entry.key.hasPrefix($0 + "/")
                    }
                }
                XCTAssertEqual(actualOldFacts, preColdOldFacts,
                    "Cold pre-cleanup validation changed a frozen old generation")
            } catch { actualRSessionFailure = error }
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        try await cold.retryColdEraseForTesting(service: recovery, accessGate: gate)
        if let actualRSessionFailure { throw actualRSessionFailure }
        XCTAssertEqual(actualRSessionCount, 1,
            "Three-generation R entry must retain the genuine target before cleanup")
        guard case let .ready(fresh, diagnostics, _) = cold.route else {
            throw FixtureFailure.coldRoute
        }
        XCTAssertEqual(fresh.generationID, intent.newGenerationID)
        XCTAssertTrue(BackupRestoreService.isEmptyCurrent(fresh.modelContext))
        XCTAssertEqual(try fresh.modelContext.fetchCount(
            FetchDescriptor<MutationReceiptRow>()), 0)
        let readyWriter = fresh.workspaceWriter
        let readyOwner = try fresh.originalAssetLabelFixtureJobOwnerForTesting(
            expectedWriter: readyWriter)
        XCTAssertEqual(try readyOwner.registry.activeEpochs(), [readyOwner.epoch])
        XCTAssertEqual(try readyWriter.currentRevision().generationID,
            intent.newGenerationID)
        let registryURL = fixture.support.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/registry.json")
        let registryObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: registryURL)) as? [String: Any])
        let leases = try XCTUnwrap(registryObject["leases"] as? [[String: Any]])
        XCTAssertEqual(leases.filter {
            $0["role"] as? String == GenerationLeaseRoleV1.writer.rawValue
        }.count, 1)
        let freshDiagnostics = await diagnostics.snapshot()
        XCTAssertEqual(freshDiagnostics, .zero)
        try requireAbsentWithoutFollowing(fixture.intentURL)
        try requireAbsentWithoutFollowing(displacedTemporary)
        for id in frozenIDs {
            try requireAbsentWithoutFollowing(generationsURL.appendingPathComponent(
                id.uuidString.lowercased(), isDirectory: true))
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(
            atPath: generationsURL.path)), Set([intent.newGenerationID.uuidString.lowercased()]))
        XCTAssertTrue(try StoreGenerationFactory(applicationSupportURL:
            fixture.support).retiredGenerationIDs().isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), pointerBefore)
        try requireTargetPointerBinding(support: fixture.support,
            intent: intent, pointerBytes: Data(contentsOf: fixture.pointerURL))
        XCTAssertEqual(fixture.completion.count, 0)
        XCTAssertEqual(coldCompletionCount, 0,
            "Cold recovery must not issue a second user-command completion receipt")
    }
    /// Draft only: requires S2's still-mutable genuine post-drain/pre-unlink
    /// callback to freeze and receive independent source review.
    @MainActor
    func testSchema2PopulatedNotificationColdRDrainsBeforeFirstGenerationUnlink()
        async throws {
        let fixture = try await makeOriginalColdCut(
            at: .afterSessionPhaseWrite, seedNotifications: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let seed = try XCTUnwrap(fixture.notificationSeed)
        let intent = fixture.intent
        XCTAssertEqual(intent.phase, .sessionActivated)
        XCTAssertEqual(Set(seed.probe.observed.map(\.requestID)), seed.ownedIDs)
        XCTAssertEqual(Set(seed.probe.observed.map(\.delivered)), Set([false, true]))
        XCTAssertTrue(seed.probe.removedIDs.isEmpty)
        let pointerBefore = fixture.pointerBefore
        try requireTargetPointerBinding(support: fixture.support, intent: intent,
            pointerBytes: pointerBefore)
        let generationsURL = fixture.support.appendingPathComponent(
            "FieldEvidenceData/generations", isDirectory: true)
        let oldURL = generationsURL.appendingPathComponent(
            intent.oldGenerationID.uuidString.lowercased(), isDirectory: true)
        let oldPrefix = "FieldEvidenceData/generations/"
            + intent.oldGenerationID.uuidString.lowercased()
        let beforeOldFacts = try protectedFacts(in: fixture.support).filter {
            $0.key == oldPrefix || $0.key.hasPrefix(oldPrefix + "/")
        }
        XCTAssertFalse(beforeOldFacts.isEmpty)

        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authentication, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry:
                try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        var coldCompletionCount = 0
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName,
            notificationSystem: seed.probe,
            didCompleteErase: { _ in coldCompletionCount += 1 })
        var actualSessionCount = 0
        var preUnlinkCount = 0
        var callbackFailure: Error?
        recovery.schema2ColdActivatedEntrySessionForTesting = { session in
            actualSessionCount += 1
            do {
                guard session.generationID == intent.newGenerationID,
                      session.readerLeaseToken != nil,
                      BackupRestoreService.isEmptyCurrent(session.modelContext),
                      try session.modelContext.fetchCount(
                        FetchDescriptor<MutationReceiptRow>()) == 0 else {
                    throw FixtureFailure.activation
                }
                XCTAssertEqual(Set(seed.probe.observed.map(\.requestID)),
                    seed.ownedIDs)
                XCTAssertTrue(seed.probe.removedIDs.isEmpty)
                XCTAssertEqual(try Data(contentsOf: fixture.pointerURL),
                    pointerBefore)
                try self.requireTargetPointerBinding(support: fixture.support,
                    intent: intent, pointerBytes: pointerBefore)
            } catch { callbackFailure = error }
        }
        recovery.schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting = {
            preUnlinkCount += 1
            guard seed.probe.observed.isEmpty,
                  Set(seed.probe.removedIDs) == seed.ownedIDs,
                  seed.probe.removedIDs.count == seed.ownedIDs.count,
                  seed.probe.observationCount > 0 else {
                throw FixtureFailure.activation
            }
            try self.requireTargetPointerBinding(support: fixture.support,
                intent: intent, pointerBytes: Data(contentsOf:
                    fixture.pointerURL))
            guard try self.protectedFacts(in: fixture.support).filter({
                      $0.key == oldPrefix || $0.key.hasPrefix(oldPrefix + "/")
                  }) == beforeOldFacts else {
                throw FixtureFailure.activation
            }
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        try await cold.retryColdEraseForTesting(service: recovery,
            accessGate: gate)
        if let callbackFailure { throw callbackFailure }
        XCTAssertEqual(actualSessionCount, 1)
        XCTAssertEqual(preUnlinkCount, 1)
        guard case let .ready(fresh, diagnostics, _) = cold.route else {
            throw FixtureFailure.coldRoute
        }
        XCTAssertEqual(fresh.generationID, intent.newGenerationID)
        XCTAssertTrue(BackupRestoreService.isEmptyCurrent(fresh.modelContext))
        XCTAssertEqual(try fresh.modelContext.fetchCount(
            FetchDescriptor<MutationReceiptRow>()), 0)
        let readyWriter = fresh.workspaceWriter
        let readyOwner = try fresh.originalAssetLabelFixtureJobOwnerForTesting(
            expectedWriter: readyWriter)
        XCTAssertEqual(try readyOwner.registry.activeEpochs(), [readyOwner.epoch])
        XCTAssertEqual(try readyWriter.currentRevision().generationID,
            intent.newGenerationID)
        let registryURL = fixture.support.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/registry.json")
        let registryObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: registryURL)) as? [String: Any])
        let leases = try XCTUnwrap(registryObject["leases"] as? [[String: Any]])
        XCTAssertEqual(leases.filter {
            $0["role"] as? String == GenerationLeaseRoleV1.writer.rawValue
        }.count, 1)
        let freshDiagnostics = await diagnostics.snapshot()
        XCTAssertEqual(freshDiagnostics, .zero)
        XCTAssertTrue(seed.probe.observed.isEmpty)
        XCTAssertEqual(Set(seed.probe.removedIDs), seed.ownedIDs)
        XCTAssertEqual(seed.probe.removedIDs.count, seed.ownedIDs.count)
        try requireAbsentWithoutFollowing(oldURL)
        try requireAbsentWithoutFollowing(fixture.intentURL)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(
            atPath: generationsURL.path)),
            Set([intent.newGenerationID.uuidString.lowercased()]))
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), pointerBefore)
        try requireTargetPointerBinding(support: fixture.support,
            intent: intent, pointerBytes: Data(contentsOf: fixture.pointerURL))
        // Observe the already-owned notification root without a reparative
        // Store constructor after ready. The revocation marker is retained.
        let notificationRoot = fixture.support.appendingPathComponent(
            "FieldEvidenceOperations/AppLockNotificationControlV1",
            isDirectory: true)
        try requireAbsentWithoutFollowing(notificationRoot.appendingPathComponent(
            AppLockNotificationControlStoreV1.recordName))
        try requireAbsentWithoutFollowing(notificationRoot.appendingPathComponent(
            AppLockNotificationControlStoreV1.mappingName))
        XCTAssertEqual(fixture.completion.count, 0)
        XCTAssertEqual(coldCompletionCount, 0)
    }

    /// This checks the first cold owner's actual durable writer cut. Fresh
    /// Router replay is exercised separately after checked owner transfer.
    @MainActor
    private func requireActualNotificationTemporaryCut(
        stage expectedStage: EraseSchema2ColdNotificationMutationStageV1,
        cut expectedCut: EraseSchema2ColdNotificationTemporaryFaultCutV1
    ) async throws {
        let fixture = try await makeOriginalColdCut(
            at: .afterSessionPhaseWrite, seedNotifications: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let seed = try XCTUnwrap(fixture.notificationSeed)
        let intent = fixture.intent
        let oldPrefix = "FieldEvidenceData/generations/"
            + intent.oldGenerationID.uuidString.lowercased()
        let oldBefore = try protectedFacts(in: fixture.support).filter {
            $0.key == oldPrefix || $0.key.hasPrefix(oldPrefix + "/")
        }
        XCTAssertFalse(oldBefore.isEmpty)
        let notificationRoot = fixture.support.appendingPathComponent(
            "FieldEvidenceOperations/AppLockNotificationControlV1",
            isDirectory: true)
        let temporaryName: String
        let canonicalName: String
        switch expectedStage {
        case .publishOwnedIDs:
            temporaryName = EraseSchema2ColdNotificationSourceV1
                .ownedIDsTemporaryName
            canonicalName = EraseSchema2ColdNotificationSourceV1.ownedIDsName
        case .publishRevocation:
            temporaryName = AppLockNotificationControlStoreV1.erasePendingName
            canonicalName = AppLockNotificationControlStoreV1.eraseName
        case .publishDrainReceipt:
            temporaryName = EraseSchema2ColdNotificationSourceV1
                .drainTemporaryName
            canonicalName = EraseSchema2ColdNotificationSourceV1.drainName
        default:
            throw FixtureFailure.activation
        }
        let temporaryURL = notificationRoot.appendingPathComponent(temporaryName)
        let canonicalURL = notificationRoot.appendingPathComponent(canonicalName)
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authentication, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry:
                try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName,
            notificationSystem: seed.probe)
        var lastFixedStage = "none"
        var fixedStageHistory: [String] = []
        var rForwardFailure = "none"
        recovery.schema2ColdFixedStageForTesting = { stage in
            lastFixedStage = stage
            fixedStageHistory.append(stage)
            if fixedStageHistory.count > 32 {
                fixedStageHistory.removeFirst()
            }
        }
        recovery.schema2ColdRForwardFailureForTesting = { category in
            rForwardFailure = category
        }
        var matchedFaultCount = 0
        var preUnlinkCount = 0
        var capturedInode: UInt64?
        var capturedBytes: Data?
        recovery.schema2ColdNotificationTemporaryFaultForTesting = {
            stage, cut in
            guard stage == expectedStage else { return }
            let matched: Bool
            switch (expectedCut, cut) {
            case (.afterCreateBeforePolicy, .afterCreateBeforePolicy),
                 (.afterStrictPrefixBeforePolicy,
                  .afterStrictPrefixBeforePolicy):
                matched = true
            default:
                matched = false
            }
            guard matched else { return }
            matchedFaultCount += 1
            var fact = stat()
            guard temporaryURL.path.withCString({ lstat($0, &fact) }) == 0,
                  fact.st_mode & S_IFMT == S_IFREG,
                  fact.st_mode & 0o777 == 0o600,
                  fact.st_nlink == 1 else {
                throw FixtureFailure.activation
            }
            let bytes = try Data(contentsOf: temporaryURL)
            switch expectedCut {
            case .afterCreateBeforePolicy:
                guard bytes.isEmpty else { throw FixtureFailure.activation }
            case .afterStrictPrefixBeforePolicy:
                guard bytes == Data("{".utf8) else {
                    throw FixtureFailure.activation
                }
            }
            capturedInode = UInt64(fact.st_ino)
            capturedBytes = bytes
            try self.requireAbsentWithoutFollowing(canonicalURL)
            throw FixtureFailure.activation
        }
        recovery.schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting = {
            preUnlinkCount += 1
            throw FixtureFailure.activation
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        var stopped: Error?
        do {
            try await cold.retryColdEraseForTesting(service: recovery,
                accessGate: gate)
        } catch {
            stopped = error
        }
        if matchedFaultCount == 0 {
            let category: String
            if let error = stopped as? StoreMigrationFailure {
                switch error {
                case .invalidIdentity: category = "migration-invalid-identity"
                case .invalidPhaseTransition: category = "migration-phase"
                case .invalidDigest, .digestMismatch: category = "migration-digest"
                default: category = "migration-other"
                }
            } else if let error = stopped as? GenerationLeaseRegistryFailureV1 {
                switch error {
                case .uncertainOwner: category = "registry-uncertain-owner"
                case .invalidIdentity: category = "registry-invalid-identity"
                default: category = "registry-other"
                }
            } else if let error = stopped as? EraseAllServiceError {
                switch error {
                case .recoveryRequired: category = "erase-recovery-required"
                case .invalidAuthority: category = "erase-invalid-authority"
                default: category = "erase-other"
                }
            } else if stopped is AppAccessContractFailureV1 {
                category = "app-access"
            } else if stopped is ProtectedFilePolicyError {
                category = "protected-file-policy"
            } else if stopped == nil {
                category = "none"
            } else {
                category = "other"
            }
            XCTFail("cold-entry-fixed-stage=\(lastFixedStage) category=\(category) r-forward-error=\(rForwardFailure) history=\(fixedStageHistory.joined(separator: ","))")
        }
        XCTAssertEqual(matchedFaultCount, 1,
            "The selected cut must come from the actual cold writer")
        XCTAssertEqual(preUnlinkCount, 0)
        XCTAssertNotNil(stopped)
        let firstInode = try XCTUnwrap(capturedInode)
        let firstBytes = try XCTUnwrap(capturedBytes)
        var afterFact = stat()
        XCTAssertEqual(temporaryURL.path.withCString({ lstat($0, &afterFact) }), 0)
        XCTAssertEqual(UInt64(afterFact.st_ino), firstInode)
        XCTAssertEqual(try Data(contentsOf: temporaryURL), firstBytes)
        try requireAbsentWithoutFollowing(canonicalURL)
        XCTAssertEqual(try EraseIntentCodecV1.decode(
            Data(contentsOf: fixture.intentURL)), intent)
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL),
            fixture.pointerBefore)
        XCTAssertEqual(try protectedFacts(in: fixture.support).filter {
            $0.key == oldPrefix || $0.key.hasPrefix(oldPrefix + "/")
        }, oldBefore)
        if expectedStage == .publishDrainReceipt {
            XCTAssertTrue(seed.probe.observed.isEmpty)
            XCTAssertEqual(Set(seed.probe.removedIDs), seed.ownedIDs)
        } else {
            XCTAssertEqual(Set(seed.probe.observed.map(\.requestID)),
                seed.ownedIDs)
            XCTAssertTrue(seed.probe.removedIDs.isEmpty)
        }
        XCTAssertEqual(fixture.completion.count, 0)
    }

    @MainActor
    func testSchema2OwnedIDsActualZeroTemporaryCut() async throws {
        try await requireActualNotificationTemporaryCut(stage: .publishOwnedIDs,
            cut: .afterCreateBeforePolicy)
    }

    @MainActor
    func testSchema2OwnedIDsActualPrefixTemporaryCut() async throws {
        try await requireActualNotificationTemporaryCut(stage: .publishOwnedIDs,
            cut: .afterStrictPrefixBeforePolicy)
    }

    @MainActor
    func testSchema2RevocationActualZeroTemporaryCut() async throws {
        try await requireActualNotificationTemporaryCut(stage: .publishRevocation,
            cut: .afterCreateBeforePolicy)
    }

    @MainActor
    func testSchema2RevocationActualPrefixTemporaryCut() async throws {
        try await requireActualNotificationTemporaryCut(stage: .publishRevocation,
            cut: .afterStrictPrefixBeforePolicy)
    }

    @MainActor
    func testSchema2DrainActualZeroTemporaryCut() async throws {
        try await requireActualNotificationTemporaryCut(stage: .publishDrainReceipt,
            cut: .afterCreateBeforePolicy)
    }

    @MainActor
    func testSchema2DrainActualPrefixTemporaryCut() async throws {
        try await requireActualNotificationTemporaryCut(stage: .publishDrainReceipt,
            cut: .afterStrictPrefixBeforePolicy)
    }

    /// The fault is after the real original R cut has become a complete
    /// checked generation prefix. A same-owner retry must consume the exact
    /// context-free seal and eventually publish a genuine empty ready target.
    @MainActor
    func testSchema2PostGenerationSealInterruptedOwnerResumesReady() async throws {
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authenticated = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authenticated, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry:
                try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName)
        var first: EraseSchema2ColdPostGenerationProjectionV1?
        var observations = 0
        recovery.schema2ColdPostGenerationProjectionForTesting = { projection in
            observations += 1
            guard projection.intent == fixture.intent,
                  projection.pointerBytes == fixture.pointerBefore,
                  projection.generationNames == [fixture.intent.newGenerationID
                    .uuidString.lowercased()],
                  try projection.roster.step(at: projection.deletedCount) == nil,
                  projection.controls.intentBytes == (try EraseIntentCodecV1
                    .encode(fixture.intent)),
                  projection.controls.auxiliaryBytes ==
                    (try Data(contentsOf: fixture.support.appendingPathComponent(
                        "FieldEvidenceErase/auxiliary-retirement.json"))) else {
                throw FixtureFailure.activation
            }
            for id in fixture.intent.generationIDsToDelete {
                try self.requireAbsentWithoutFollowing(fixture.support
                    .appendingPathComponent("FieldEvidenceData/generations")
                    .appendingPathComponent(id.uuidString.lowercased()))
            }
            if let first {
                guard first === projection else { throw FixtureFailure.activation }
            } else {
                first = projection
                throw FixtureFailure.activation
            }
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        var interrupted: Error?
        do {
            try await cold.retryColdEraseForTesting(service: recovery,
                accessGate: gate)
        } catch { interrupted = error }
        XCTAssertNotNil(interrupted)
        XCTAssertEqual(observations, 1)
        XCTAssertNotNil(first)
        XCTAssertEqual(try EraseIntentCodecV1.decode(
            Data(contentsOf: fixture.intentURL)), fixture.intent)
        try await cold.retryColdEraseForTesting(service: recovery, accessGate: gate)
        XCTAssertEqual(observations, 2,
            "Retry must reprove the same held seal before continuing")
        guard case let .ready(fresh, diagnostics, _) = cold.route else {
            throw FixtureFailure.coldRoute
        }
        XCTAssertEqual(fresh.generationID, fixture.intent.newGenerationID)
        XCTAssertTrue(BackupRestoreService.isEmptyCurrent(fresh.modelContext))
        XCTAssertEqual(try fresh.modelContext.fetchCount(
            FetchDescriptor<MutationReceiptRow>()), 0)
        let diagnosticsSnapshot = await diagnostics.snapshot()
        XCTAssertEqual(diagnosticsSnapshot, .zero)
        try requireAbsentWithoutFollowing(fixture.intentURL)
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), fixture.pointerBefore)
        XCTAssertEqual(fixture.completion.count, 0)
    }

    /// Equal bytes at a new inode cannot replace the first canonical roster
    /// after generation loss. Failure must retain R and cannot recapture that
    /// foreign leaf as a new same-operation baseline on retry.
    @MainActor
    func testSchema2PostGenerationSameBytesForeignRosterRetainsIntent() async throws {
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authenticated = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authenticated, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry:
                try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName)
        let rosterURL = fixture.support.appendingPathComponent(
            "FieldEvidenceErase/auxiliary-retirement.json")
        var observations = 0
        var firstFact: EraseColdControlLeafFactV1?
        var foreignFact: EraseColdControlLeafFactV1?
        var raw: Data?
        recovery.schema2ColdPostGenerationProjectionForTesting = { projection in
            observations += 1
            guard observations == 1,
                  projection.intent == fixture.intent,
                  try projection.roster.step(at: projection.deletedCount) == nil else {
                throw FixtureFailure.activation
            }
            let bytes = try Data(contentsOf: rosterURL)
            guard bytes == projection.controls.auxiliaryBytes else {
                throw FixtureFailure.activation
            }
            var before = stat(), after = stat()
            guard rosterURL.path.withCString({ lstat($0, &before) }) == 0,
                  EraseColdControlLeafFactV1(before)
                    == projection.controls.auxiliaryProjectedFact else {
                throw FixtureFailure.activation
            }
            try bytes.write(to: rosterURL, options: .atomic)
            guard rosterURL.path.withCString({ lstat($0, &after) }) == 0,
                  after.st_ino != before.st_ino,
                  after.st_mode & S_IFMT == S_IFREG,
                  after.st_nlink == 1,
                  try Data(contentsOf: rosterURL) == bytes else {
                throw FixtureFailure.activation
            }
            firstFact = EraseColdControlLeafFactV1(before)
            foreignFact = EraseColdControlLeafFactV1(after)
            raw = bytes
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        var refused: Error?
        do {
            try await cold.retryColdEraseForTesting(service: recovery,
                accessGate: gate)
        } catch { refused = error }
        XCTAssertNotNil(refused)
        XCTAssertEqual(observations, 1)
        XCTAssertNotEqual(try XCTUnwrap(firstFact), try XCTUnwrap(foreignFact))
        XCTAssertEqual(try Data(contentsOf: rosterURL), try XCTUnwrap(raw))
        XCTAssertEqual(try EraseIntentCodecV1.decode(
            Data(contentsOf: fixture.intentURL)), fixture.intent)
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), fixture.pointerBefore)
        if case .ready = cold.route { XCTFail("Foreign roster must not publish ready") }
        var retryRefused: Error?
        do {
            try await cold.retryColdEraseForTesting(service: recovery,
                accessGate: gate)
        } catch { retryRefused = error }
        XCTAssertNotNil(retryRefused)
        XCTAssertEqual(observations, 1,
            "Uncertainty must not reconstruct another projection or effect")
        XCTAssertEqual(try Data(contentsOf: rosterURL), try XCTUnwrap(raw))
        XCTAssertEqual(try EraseIntentCodecV1.decode(
            Data(contentsOf: fixture.intentURL)), fixture.intent)
        XCTAssertEqual(fixture.completion.count, 0)
    }

    private enum PostSealForeignLeafRole {
        case canonicalIntent, currentPointer
    }

    /// Add complete represented full11 facts to the existing byte census.
    /// The incumbent helper and all original expectations stay untouched.
    private func fullPostSealFacts(in support: URL) throws
        -> [String: EraseColdControlLeafFactV1] {
        let names = try protectedFacts(in: support).keys.sorted()
        var result: [String: EraseColdControlLeafFactV1] = [:]
        for relative in names {
            let url = support.appendingPathComponent(relative)
            var named = stat()
            guard url.path.withCString({ lstat($0, &named) }) == 0,
                  named.st_mode & S_IFMT == S_IFDIR
                    || (named.st_mode & S_IFMT == S_IFREG && named.st_nlink == 1) else {
                throw FixtureFailure.activation
            }
            result[relative] = EraseColdControlLeafFactV1(named)
        }
        return result
    }

    /// Hostile fixture IO only: retain the exact bytes and owned mode but
    /// replace the named inode after the actual post-generation seal. No
    /// original-control receipt, policy outcome or replay history is minted.
    private func replacePostSealLeafWithSameBytes(
        _ url: URL, expectedFact: EraseColdControlLeafFactV1, bytes: Data
    ) throws -> EraseColdControlLeafFactV1 {
        var before = stat()
        guard url.path.withCString({ lstat($0, &before) }) == 0,
              EraseColdControlLeafFactV1(before) == expectedFact,
              before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
              try Data(contentsOf: url) == bytes else {
            throw FixtureFailure.activation
        }
        try bytes.write(to: url, options: .atomic)
        var named = stat()
        guard url.path.withCString({ lstat($0, &named) }) == 0,
              named.st_ino != before.st_ino,
              named.st_dev == before.st_dev,
              named.st_uid == before.st_uid, named.st_gid == before.st_gid,
              named.st_mode & S_IFMT == S_IFREG, named.st_nlink == 1 else {
            throw FixtureFailure.activation
        }
        let descriptor = url.path.withCString {
            open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw FixtureFailure.activation }
        var closeEntered = false
        do {
            var held = stat()
            guard fstat(descriptor, &held) == 0,
                  EraseColdControlLeafFactV1(held) == EraseColdControlLeafFactV1(named),
                  fchmod(descriptor, before.st_mode & mode_t(0o7777)) == 0 else {
                throw FixtureFailure.activation
            }
            var finalHeld = stat(), finalNamed = stat()
            guard fstat(descriptor, &finalHeld) == 0,
                  url.path.withCString({ lstat($0, &finalNamed) }) == 0,
                  EraseColdControlLeafFactV1(finalHeld) == EraseColdControlLeafFactV1(finalNamed),
                  finalHeld.st_ino != before.st_ino,
                  finalHeld.st_dev == before.st_dev,
                  finalHeld.st_mode == before.st_mode,
                  finalHeld.st_uid == before.st_uid, finalHeld.st_gid == before.st_gid,
                  finalHeld.st_nlink == 1, finalHeld.st_size == before.st_size,
                  try Data(contentsOf: url) == bytes else {
                throw FixtureFailure.activation
            }
            closeEntered = true // Fence before the only close invocation.
            guard close(descriptor) == 0 else { throw FixtureFailure.activation }
            var afterClose = stat()
            guard url.path.withCString({ lstat($0, &afterClose) }) == 0,
                  EraseColdControlLeafFactV1(afterClose) == EraseColdControlLeafFactV1(finalHeld) else {
                throw FixtureFailure.activation
            }
            return EraseColdControlLeafFactV1(afterClose)
        } catch {
            if !closeEntered {
                closeEntered = true
                guard close(descriptor) == 0 else { throw FixtureFailure.activation }
            }
            throw error
        }
    }

    @MainActor
    private func requirePostSealForeignLeafRefusal(
        _ role: PostSealForeignLeafRole
    ) async throws {
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authenticated = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authenticated, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry:
                try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        let completion = CompletionBox()
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName,
            didCompleteErase: { _ in completion.count += 1 })
        var observations = 0
        var actualSeal: EraseSchema2ColdPostGenerationProjectionV1?
        var expectedFact: EraseColdControlLeafFactV1?
        var foreignFact: EraseColdControlLeafFactV1?
        var afterForeign: [String: PhysicalFact]?
        var afterForeignFull11: [String: EraseColdControlLeafFactV1]?
        recovery.schema2ColdPostGenerationProjectionForTesting = { projection in
            observations += 1
            guard observations == 1, projection.intent == fixture.intent,
                  projection.pointerBytes == fixture.pointerBefore,
                  projection.generationNames == [fixture.intent.newGenerationID.uuidString.lowercased()],
                  try projection.roster.step(at: projection.deletedCount) == nil,
                  projection.controls.intentBytes == (try EraseIntentCodecV1.encode(fixture.intent)) else {
                throw FixtureFailure.activation
            }
            for id in fixture.intent.generationIDsToDelete {
                try self.requireAbsentWithoutFollowing(fixture.support
                    .appendingPathComponent("FieldEvidenceData/generations")
                    .appendingPathComponent(id.uuidString.lowercased()))
            }
            let url: URL
            let raw: Data
            let first: EraseColdControlLeafFactV1
            switch role {
            case .canonicalIntent:
                url = fixture.intentURL
                raw = projection.controls.intentBytes
                first = projection.controls.intentFact
            case .currentPointer:
                url = fixture.pointerURL
                raw = projection.pointerBytes
                first = projection.pointerFact
            }
            actualSeal = projection; expectedFact = first
            foreignFact = try self.replacePostSealLeafWithSameBytes(url,
                expectedFact: first, bytes: raw)
            try self.requireTargetPointerBinding(support: fixture.support,
                intent: fixture.intent, pointerBytes: Data(contentsOf: fixture.pointerURL))
            afterForeign = try self.protectedFacts(in: fixture.support)
            afterForeignFull11 = try self.fullPostSealFacts(in: fixture.support)
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        var refused: Error?
        do {
            try await cold.retryColdEraseForTesting(service: recovery,
                accessGate: gate)
        } catch { refused = error }
        XCTAssertNotNil(refused)
        XCTAssertEqual(observations, 1)
        XCTAssertNotNil(actualSeal)
        let first = try XCTUnwrap(expectedFact)
        let foreign = try XCTUnwrap(foreignFact)
        XCTAssertNotEqual(first.inode, foreign.inode)
        XCTAssertEqual(first.device, foreign.device)
        XCTAssertEqual(first.mode, foreign.mode)
        XCTAssertEqual(first.user, foreign.user)
        XCTAssertEqual(first.group, foreign.group)
        XCTAssertEqual(first.links, foreign.links)
        XCTAssertEqual(first.size, foreign.size)
        XCTAssertEqual(try Data(contentsOf: fixture.intentURL),
            try EraseIntentCodecV1.encode(fixture.intent))
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), fixture.pointerBefore)
        XCTAssertEqual(try protectedFacts(in: fixture.support), try XCTUnwrap(afterForeign),
            "Seal reproof must refuse before changing canonical data or controls")
        XCTAssertEqual(try fullPostSealFacts(in: fixture.support), try XCTUnwrap(afterForeignFull11))
        if case .ready = cold.route { XCTFail("Same bytes cannot replace the sealed control identity") }
        var retryRefused: Error?
        do {
            try await cold.retryColdEraseForTesting(service: recovery,
                accessGate: gate)
        } catch { retryRefused = error }
        XCTAssertNotNil(retryRefused)
        XCTAssertEqual(observations, 1,
            "An uncertain same-owner retry must not recapture another seal")
        XCTAssertEqual(try protectedFacts(in: fixture.support), try XCTUnwrap(afterForeign))
        XCTAssertEqual(try fullPostSealFacts(in: fixture.support), try XCTUnwrap(afterForeignFull11))
        XCTAssertEqual(try EraseIntentCodecV1.decode(Data(contentsOf: fixture.intentURL)), fixture.intent)
        try requireTargetPointerBinding(support: fixture.support,
            intent: fixture.intent, pointerBytes: Data(contentsOf: fixture.pointerURL))
        XCTAssertEqual(completion.count, 0)
        XCTAssertEqual(fixture.completion.count, 0)
        if case .ready = cold.route { XCTFail("Poisoned retry must retain the R hold") }
    }

    /// Canonical R bytes at a fresh inode do not grant a new control baseline.
    @MainActor
    func testSchema2PostGenerationSameBytesForeignIntentRefusesWithoutEffects() async throws {
        try await requirePostSealForeignLeafRefusal(.canonicalIntent)
    }

    /// A semantically equal target pointer cannot replace its sealed inode.
    @MainActor
    func testSchema2PostGenerationSameBytesForeignPointerRefusesWithoutEffects() async throws {
        try await requirePostSealForeignLeafRefusal(.currentPointer)
    }
}

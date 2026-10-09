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
        // A foreign-owner fixture pauses at the genuine asynchronous OS
        // readback port, with its actual cold service frame/EX still live.
        var beforeObservationForTesting: (@MainActor () async -> Void)?

        init(observed: [NotificationSystemObservationV1]) {
            self.observed = observed
        }

        func authorization() async throws -> LocalReminderAuthorizationV1 {
            .authorized
        }

        func observations() async throws -> [NotificationSystemObservationV1] {
            await beforeObservationForTesting?()
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

#if DEBUG
    /// Enable only existing fixed-label diagnostics on the actual fresh
    /// cold owners. No error description, path, capability or predicate changes.
    @MainActor
    private func installColdREntryDiagnosticsForTesting(
        router: StartupRouter,service: EraseAllService
    ) {
        FileHandle.standardError.write(Data(
            "V23_C23_COLD_ENTRY_DIAG_V1 kind=installed\n".utf8))
        router.startupFailureDiagnosticForTesting = { observation in
            FileHandle.standardError.write(Data((
                "V23_C23_COLD_ENTRY_DIAG_V1 kind=startup "
                + observation + "\n").utf8))
        }
        service.schema2ColdFixedStageForTesting = { stage in
            FileHandle.standardError.write(Data((
                "V23_C23_COLD_ENTRY_DIAG_V1 kind=stage stage="
                + stage + "\n").utf8))
        }
        service.schema2ColdRForwardFailureForTesting = { family in
            FileHandle.standardError.write(Data((
                "V23_C23_COLD_ENTRY_DIAG_V1 kind=r-forward-failure family="
                + family + "\n").utf8))
        }
    }
#endif

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
        let operation: EraseRouterOperationV1
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
        seedNotifications: Bool = false,
        physicalTransitionControl: (@MainActor (OriginalErasePhysicalTransitionStageV1, URL) throws -> Void)? = nil
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
        var physicalHookOperation: EraseRouterOperationV1?
        defer {
            if let physicalHookOperation {
                StoreGenerationFactory.clearOriginalErasePhysicalTransitionTestHook(operation: physicalHookOperation)
            }
        }

        let interrupted = try await { () async throws -> (EraseIntentV1, EraseRouterOperationV1) in
            let (coordinator, diagnostics) = try await original.startOriginalOwner()
            sourceContext = coordinator.modelContext
            sourceContainer = coordinator.modelContext.container
            let sourceID = coordinator.generationID
            try seedOriginalSign(coordinator)
            try await original.admit(coordinator: coordinator)
            let operation = try original.originalOperationForInterruption()
            if let physicalTransitionControl {
                physicalHookOperation = operation
                try StoreGenerationFactory.installOriginalErasePhysicalTransitionTestHook(
                    operation: operation, applicationSupportURL: support,
                    callback: physicalTransitionControl)
            }
            // The final completion occurs after this lexical source owner is
            // gone; keep the bound hook until that exact operation completes.
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
        defer { StoreGenerationFactory.clearOriginalErasePhysicalTransitionTestHook(operation: operation) }
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
            notificationSeed: notificationSeed, operation: operation)
    }

    /// The real ordinary P publisher emits aux and no recovery record pair.
    /// Enter its real cold target callback before the hostile canonical swap;
    /// this fixture never manufactures a recovered pair or admission witness.
    @MainActor
    func testSchema2OwnPointerFirstAuxiliaryRejectsLateSameBytesNewInode() async throws {
        let fixture = try await makeOriginalColdCut()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        XCTAssertEqual(fixture.intent.phase, .pointerSwitched)
        let erase = fixture.support.appendingPathComponent("FieldEvidenceErase",
            isDirectory: true)
        let preparationURL = erase.appendingPathComponent("preparation.json")
        let preparationBytes = try Data(contentsOf: preparationURL)
        let preparation = try ErasePreparationCodecV2.decode(preparationBytes)
        XCTAssertTrue(preparation.matches(fixture.intent))
        let role = "auxiliary-retirement.json"
        let auxiliaryURL = erase.appendingPathComponent(role)
        let auxiliaryBytes = try Data(contentsOf: auxiliaryURL)
        XCTAssertFalse(auxiliaryBytes.isEmpty)
        let auxiliary = try EraseSchema2ColdAuxiliaryPhysicalRosterV1.decodeCanonical(
            auxiliaryBytes, intent: fixture.intent, preparation: preparation)
        XCTAssertEqual(auxiliary.record.firstIntentPhase,
            EraseIntentPhaseV1.emptyGenerationPrepared.rawValue)
        let recoveredNames = ["original-retired-transition.json",
            "original-retired-stage-identity.json"]
        for name in recoveredNames {
            try requireAbsentWithoutFollowing(erase.appendingPathComponent(name))
        }
        let retiredURL = fixture.support.appendingPathComponent(
            "FieldEvidenceData/retired.json")
        let retiredBytes = try Data(contentsOf: retiredURL)

        // Prepare only a disposable hostile leaf outside the control namespace
        // before the real cold first cut. Its canonical replacement is later.
        let substituteURL = fixture.root.appendingPathComponent(
            "ordinary-p-auxiliary-new-inode.fixture")
        var originalLeaf = stat()
        guard lstat(auxiliaryURL.path, &originalLeaf) == 0,
              originalLeaf.st_mode & S_IFMT == S_IFREG,
              originalLeaf.st_nlink == 1,
              originalLeaf.st_size == off_t(auxiliaryBytes.count) else {
            throw FixtureFailure.activation
        }
        let substituteFD = Darwin.open(substituteURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600))
        guard substituteFD >= 0 else { throw FixtureFailure.activation }
        var preparationFailure: Error?
        var preparedFact = stat()
        do {
            var cursor = 0
            while cursor < auxiliaryBytes.count {
                let wrote = auxiliaryBytes.withUnsafeBytes { raw in
                    Darwin.write(substituteFD,
                        raw.baseAddress?.advanced(by: cursor),
                        auxiliaryBytes.count - cursor)
                }
                guard wrote > 0 else { throw FixtureFailure.activation }
                cursor += wrote
            }
            guard Darwin.fchmod(substituteFD, originalLeaf.st_mode & 0o777) == 0,
                  Darwin.fsync(substituteFD) == 0,
                  Darwin.fstat(substituteFD, &preparedFact) == 0,
                  preparedFact.st_mode & S_IFMT == S_IFREG,
                  preparedFact.st_nlink == 1,
                  preparedFact.st_mode == originalLeaf.st_mode,
                  preparedFact.st_uid == originalLeaf.st_uid,
                  preparedFact.st_gid == originalLeaf.st_gid,
                  preparedFact.st_size == off_t(auxiliaryBytes.count) else {
                throw FixtureFailure.activation
            }
        } catch { preparationFailure = error }
        let substituteClose = Darwin.close(substituteFD) // one actual attempt
        if let preparationFailure { throw preparationFailure }
        guard substituteClose == 0 else { throw FixtureFailure.activation }
        XCTAssertEqual(try Data(contentsOf: substituteURL), auxiliaryBytes)

        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: Authentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let authentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(authentication, .authenticated)
        let cold = StartupRouter(applicationSupportURL: fixture.support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: try WorkspacePackageLifecycleCompatibilityV1
                .shippingRegistry())
        var completionCount = 0
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches,
            temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName,
            didCompleteErase: { _ in completionCount += 1 })
        var actualTargetCallbacks = 0
        var mutationFailure: Error?
        var capturedActualFact: stat?
        var replacedActualFact: stat?
        recovery.schema2ColdBeforeSessionPhaseCASForTesting = { session in
            actualTargetCallbacks += 1
            do {
                XCTAssertEqual(session.generationID, fixture.intent.newGenerationID)
                XCTAssertNotNil(session.readerLeaseToken)
                XCTAssertTrue(BackupRestoreService.isEmptyCurrent(session.modelContext))
                XCTAssertEqual(try EraseIntentCodecV1.decode(
                    Data(contentsOf: fixture.intentURL)), fixture.intent)
                try self.requireTargetPointerBinding(support: fixture.support,
                    intent: fixture.intent, pointerBytes: fixture.pointerBefore)
                XCTAssertEqual(try Data(contentsOf: auxiliaryURL), auxiliaryBytes)
                for name in recoveredNames {
                    try self.requireAbsentWithoutFollowing(erase.appendingPathComponent(name))
                }
                var named = stat(), substitute = stat()
                guard lstat(auxiliaryURL.path, &named) == 0,
                      named.st_mode & S_IFMT == S_IFREG,
                      named.st_nlink == 1,
                      named.st_size == off_t(auxiliaryBytes.count),
                      lstat(substituteURL.path, &substitute) == 0,
                      EraseColdControlLeafFactV1(substitute) ==
                        EraseColdControlLeafFactV1(preparedFact),
                      named.st_dev == substitute.st_dev,
                      named.st_ino != substitute.st_ino else {
                    throw FixtureFailure.activation
                }
                capturedActualFact = named
                let parent = Darwin.open(erase.path,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard parent >= 0 else { throw FixtureFailure.activation }
                var firstFailure: Error?
                do {
                    var heldParent = stat(), namedParent = stat(), after = stat()
                    guard Darwin.fstat(parent, &heldParent) == 0,
                          lstat(erase.path, &namedParent) == 0,
                          EraseColdControlLeafFactV1(heldParent) ==
                            EraseColdControlLeafFactV1(namedParent),
                          Darwin.renameat(AT_FDCWD, substituteURL.path,
                            parent, role) == 0,
                          Darwin.fsync(parent) == 0,
                          Darwin.fstatat(parent, role, &after,
                            AT_SYMLINK_NOFOLLOW) == 0,
                          after.st_mode & S_IFMT == S_IFREG,
                          after.st_nlink == 1,
                          after.st_size == named.st_size,
                          after.st_dev == substitute.st_dev,
                          after.st_ino == substitute.st_ino,
                          after.st_ino != named.st_ino else {
                        throw FixtureFailure.activation
                    }
                    replacedActualFact = after
                } catch { firstFailure = error }
                let parentClose = Darwin.close(parent) // one actual attempt
                if let firstFailure { throw firstFailure }
                guard parentClose == 0 else { throw FixtureFailure.activation }
                XCTAssertEqual(try Data(contentsOf: auxiliaryURL), auxiliaryBytes)
                try self.requireAbsentWithoutFollowing(substituteURL)
            } catch { mutationFailure = error }
        }
        defer { recovery.schema2ColdBeforeSessionPhaseCASForTesting = nil }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        try await cold.retryColdEraseForTesting(service: recovery, accessGate: gate)
        if let mutationFailure { throw mutationFailure }
        XCTAssertEqual(actualTargetCallbacks, 1,
            "Actual first P proof and target-reader entry must precede substitution")
        let before = try XCTUnwrap(capturedActualFact)
        let after = try XCTUnwrap(replacedActualFact)
        XCTAssertEqual(before.st_dev, after.st_dev)
        XCTAssertNotEqual(before.st_ino, after.st_ino)
        XCTAssertEqual(before.st_mode, after.st_mode)
        XCTAssertEqual(before.st_uid, after.st_uid)
        XCTAssertEqual(before.st_gid, after.st_gid)
        XCTAssertEqual(before.st_size, after.st_size)
        XCTAssertEqual(try Data(contentsOf: auxiliaryURL), auxiliaryBytes)
        guard case .maintenance(.eraseInconsistent) = cold.route else {
            throw FixtureFailure.coldRoute
        }
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), fixture.pointerBefore)
        XCTAssertEqual(try Data(contentsOf: retiredURL), retiredBytes)
        XCTAssertEqual(try Data(contentsOf: preparationURL), preparationBytes)
        let current = try EraseIntentCodecV1.decode(Data(contentsOf: fixture.intentURL))
        XCTAssertTrue(current == fixture.intent ||
            current == fixture.intent.advancing(to: .sessionActivated),
            "Only the same authentic own P-to-R result may precede refusal")
        for name in recoveredNames {
            try requireAbsentWithoutFollowing(erase.appendingPathComponent(name))
        }
        let generations = fixture.support.appendingPathComponent(
            "FieldEvidenceData/generations", isDirectory: true)
        for id in fixture.intent.generationIDsToDelete + [fixture.intent.newGenerationID] {
            var actual = stat()
            guard lstat(generations.appendingPathComponent(
                    id.uuidString.lowercased()).path, &actual) == 0,
                  actual.st_mode & S_IFMT == S_IFDIR else {
                throw FixtureFailure.activation
            }
        }
        try requireAbsentWithoutFollowing(erase.appendingPathComponent(
            EraseSchema2ColdDeletionRosterV1.canonicalName))
        XCTAssertEqual(fixture.completion.count, 0)
        XCTAssertEqual(completionCount, 0)
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
#if DEBUG
        installColdREntryDiagnosticsForTesting(router: cold,service: recovery)
#endif
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

#if DEBUG
    /// Borrow the real creator after its checked complete temporary write.
    /// Its own regular entry must admit the owner; an additional foreign
    /// regular sibling must refuse before policy, root creation or cleanup.
    @MainActor
    func testSchema2ColdRootCreationOwnTemporaryRejectsForeignRegularSiblingBeforeEffect() async throws {
        typealias Manifest = EraseSchema2ColdManifestOwnerV1
        guard Manifest.notificationCreationTemporaryForTesting == nil else {
            throw FixtureFailure.activation
        }
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
        defer {
            Manifest.notificationCreationTemporaryForTesting = nil
            fixture.defaults.removePersistentDomain(forName: fixture.defaultsName)
        }
        XCTAssertEqual(fixture.intent.phase, .sessionActivated)
        let operations = fixture.support.appendingPathComponent(
            "FieldEvidenceOperations", isDirectory: true)
        let temporary = operations.appendingPathComponent(
            EraseSchema2ColdNotificationSourceV1.creationTemporaryName)
        let foreign = operations.appendingPathComponent("foreign-creator-sibling.bin")
        try requireAbsentWithoutFollowing(temporary)
        try requireAbsentWithoutFollowing(foreign)
        let oldPrefix = "FieldEvidenceData/generations/"
            + fixture.intent.oldGenerationID.uuidString.lowercased()
        let oldBefore = try protectedFacts(in: fixture.support).filter {
            $0.key == oldPrefix || $0.key.hasPrefix(oldPrefix + "/")
        }
        XCTAssertFalse(oldBefore.isEmpty)
        let fileFact: (URL) throws -> PhysicalFact = { url in
            var value = stat()
            guard lstat(url.path, &value) == 0,
                  value.st_mode & S_IFMT == S_IFREG,
                  value.st_nlink == 1 else { throw FixtureFailure.activation }
            return PhysicalFact(device: UInt64(value.st_dev), inode: UInt64(value.st_ino),
                mode: UInt32(value.st_mode), links: UInt64(value.st_nlink),
                size: Int64(value.st_size), modifiedSeconds: Int(value.st_mtimespec.tv_sec),
                modifiedNanoseconds: Int(value.st_mtimespec.tv_nsec),
                changedSeconds: Int(value.st_ctimespec.tv_sec),
                changedNanoseconds: Int(value.st_ctimespec.tv_nsec),
                bytes: try Data(contentsOf: url))
        }
        var temporaryBefore: PhysicalFact?
        var foreignBefore: PhysicalFact?
        var creatorCuts = 0, ownAdmissions = 0, hostileRefusals = 0
        Manifest.notificationCreationTemporaryForTesting = { manifest, operation, source, actualTemporary in
            guard source.eraseID == fixture.intent.eraseID,
                  actualTemporary.standardizedFileURL == temporary.standardizedFileURL,
                  creatorCuts == 0 else { throw FixtureFailure.activation }
            creatorCuts += 1
            try operation.requireSchema2ColdManifestOwner(manifest)
            temporaryBefore = try fileFact(actualTemporary)
            XCTAssertFalse(try XCTUnwrap(temporaryBefore?.bytes).isEmpty)
            try operation.requireSchema2ColdNotificationMutationOwner(
                source: source, stage: .createRoot)
            ownAdmissions += 1
            let foreignBytes = Data("foreign creator sibling".utf8)
            try foreignBytes.write(to: foreign, options: .withoutOverwriting)
            foreignBefore = try fileFact(foreign)
            do {
                try operation.requireSchema2ColdNotificationMutationOwner(
                    source: source, stage: .createRoot)
                XCTFail("A foreign regular sibling cannot join the creator's owned entry count")
            } catch let error as StoreMigrationFailure {
                guard case .invalidIdentity = error else { throw error }
                hostileRefusals += 1
            }
            XCTAssertEqual(try fileFact(actualTemporary), try XCTUnwrap(temporaryBefore))
        }
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
        let notification = NotificationProbe(observed: [])
        var completionCount = 0, preUnlinkCount = 0
        let recovery = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches, temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults, bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName, notificationSystem: notification,
            didCompleteErase: { _ in completionCount += 1 })
        recovery.schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting = {
            preUnlinkCount += 1
            throw FixtureFailure.activation
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        var firstFailure: Error?
        var firstFailureLoans = 0
        try await cold.retryColdEraseForTesting(service: recovery, accessGate: gate,
            firstColdEraseFailureForTesting: { error in
                firstFailureLoans += 1
                firstFailure = error
            })
        XCTAssertEqual(creatorCuts, 1)
        XCTAssertEqual(ownAdmissions, 1)
        XCTAssertEqual(hostileRefusals, 1)
        XCTAssertEqual(firstFailureLoans, 1)
        let firstError = try XCTUnwrap(firstFailure as? StoreMigrationFailure)
        guard case .invalidIdentity = firstError else { throw firstError }
        if case .ready = cold.route { XCTFail("Foreign creator sibling published ready") }
        XCTAssertEqual(preUnlinkCount, 0)
        XCTAssertEqual(notification.observationCount, 0)
        XCTAssertTrue(notification.removedIDs.isEmpty)
        XCTAssertEqual(try fileFact(temporary), try XCTUnwrap(temporaryBefore))
        XCTAssertEqual(try fileFact(foreign), try XCTUnwrap(foreignBefore))
        for name in [AppLockNotificationControlStoreV1.rootName,
                     EraseSchema2ColdNotificationSourceV1.creationStageName,
                     EraseSchema2ColdNotificationSourceV1.creationRecordName] {
            try requireAbsentWithoutFollowing(operations.appendingPathComponent(name))
        }
        XCTAssertEqual(try EraseIntentCodecV1.decode(Data(contentsOf: fixture.intentURL)),
            fixture.intent)
        XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), fixture.pointerBefore)
        try requireTargetPointerBinding(support: fixture.support, intent: fixture.intent,
            pointerBytes: fixture.pointerBefore)
        XCTAssertEqual(try protectedFacts(in: fixture.support).filter {
            $0.key == oldPrefix || $0.key.hasPrefix(oldPrefix + "/")
        }, oldBefore)
        XCTAssertEqual(fixture.completion.count, 0)
        XCTAssertEqual(completionCount, 0)
    }
#endif

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

    @MainActor
    private struct ActualOrdinaryReadyFixture {
        let original: PointerFixture
        let router: StartupRouter
        let coordinator: StoreSessionCoordinator
        let session: StoreGenerationSession
        let lifetime: ColdEraseSchema2CompletedSessionLifetimeOwnerV1
    }

    @MainActor
    private func makeActualOrdinaryReadyFixture() async throws -> ActualOrdinaryReadyFixture {
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
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
        var actualRecoveredSession: StoreGenerationSession?
        var actualRSessionFailure: Error?
        let targetURL = fixture.support.appendingPathComponent(
            "FieldEvidenceData/generations", isDirectory: true)
            .appendingPathComponent(
                intent.newGenerationID.uuidString.lowercased(), isDirectory: true)
        // S2's typed first-R observation runs after the real Factory opening,
        // checked reader acquisition and Router physical/token reproof. It
        // does not manufacture a session or bypass the R forward owner.
        recovery.schema2ColdActivatedEntrySessionForTesting = { session in
            actualRecoveredSession = session // actual returned Session before any fixture postproof
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
#if DEBUG
        installColdREntryDiagnosticsForTesting(router: cold,service: recovery)
#endif
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

        let session = try XCTUnwrap(actualRecoveredSession)
        let lifetime = try XCTUnwrap(
            fresh.completedSessionLifetimeOwnerForCurrentSession())
        XCTAssertTrue(session.modelContext === fresh.modelContext)
        XCTAssertTrue(fresh.modelContext.autosaveEnabled)
        return ActualOrdinaryReadyFixture(original: fixture, router: cold,
            coordinator: fresh, session: session, lifetime: lifetime)
    }


    @MainActor
    private func requireOrdinaryBackingWithinOriginalEnvelope(
        _ actual: ColdEraseSchema2CompletedOrdinaryBackingSnapshotV1
    ) throws {
        XCTAssertEqual(actual.maximumRetainedRequests, 64)
        XCTAssertEqual(actual.maximumSourceAttempts, 16)
        guard actual.maximumRetainedRequests == 64,
              actual.occupiedSlots >= 0,
              actual.occupiedSlots <= actual.maximumRetainedRequests,
              actual.retainedOrdinaryFamilies >= 0,
              actual.retainedOrdinaryFamilies <= actual.maximumRetainedRequests,
              actual.perRequestBackingBytes > 0 else {
            throw FixtureFailure.activation
        }
        let whole = actual.perRequestBackingBytes.multipliedReportingOverflow(
            by: UInt64(actual.occupiedSlots))
        let envelope = actual.perRequestBackingBytes.multipliedReportingOverflow(
            by: UInt64(actual.maximumRetainedRequests))
        let retained = whole.partialValue.addingReportingOverflow(
            actual.retainedHistoricalBackingBytes)
        let total = retained.partialValue.addingReportingOverflow(
            actual.reservedCurrentAndPendingCheckpointBackingBytes)
        guard !whole.overflow, !envelope.overflow,
              !retained.overflow, !total.overflow else {
            throw FixtureFailure.activation
        }
        XCTAssertLessThanOrEqual(total.partialValue, envelope.partialValue,
            "Every unretired whole request, retained history and current/checkpoint reservation remains inside the SAME64 envelope")
        XCTAssertLessThanOrEqual(actual.successfulOrdinaryReturns,
            actual.actualRequestBirths)
    }

    @MainActor
    private func requireOneFreshOrdinaryReproof(
        session: StoreGenerationSession,
        lifetime: ColdEraseSchema2CompletedSessionLifetimeOwnerV1
    ) throws {
        let before = lifetime.ordinaryBackingSnapshotForTesting()
        try requireOrdinaryBackingWithinOriginalEnvelope(before)
        XCTAssertFalse(before.quarantined)
        guard before.activeRequestIdentity == nil,
              !before.currentScopePresent,
              !before.currentResourceFramePresent else {
            throw FixtureFailure.activation
        }
        try session.reproofAfterSave() // real explicit relay outside every writer/lease body
        let after = lifetime.ordinaryBackingSnapshotForTesting()
        try requireOrdinaryBackingWithinOriginalEnvelope(after)
        XCTAssertEqual(after.actualRequestBirths, before.actualRequestBirths + 1)
        XCTAssertEqual(after.successfulOrdinaryReturns,
            before.successfulOrdinaryReturns + 1)
        XCTAssertNotNil(after.lastBornRequestIdentity)
        XCTAssertEqual(after.lastBornRequestIdentity, after.lastReturnedRequestIdentity)
        XCTAssertNil(after.activeRequestIdentity)
        XCTAssertFalse(after.currentScopePresent)
        XCTAssertFalse(after.currentResourceFramePresent)
        XCTAssertEqual(after.occupiedSlots, before.occupiedSlots)
        XCTAssertGreaterThanOrEqual(after.returnedHistoricalCohorts,
            before.returnedHistoricalCohorts)
        XCTAssertFalse(after.quarantined)
        // Swift allocator address reuse is legal. The constructor count and
        // SAME birth-to-checked-return association attest this operation;
        // there is deliberately no Set of supposedly unique addresses.
    }
    /// Real behavior only; actual constructor/returned-transition snapshots
    /// distinguish top-level requests from nested automatic save borrowers.
    /// UNCOMPILED/UNRUN: Root must bind/review/compile the three-owner Source.
    @MainActor
    func testSchema2OneActualColdReadySessionSurvives129DistinctSaveReproofCycles() async throws {
        guard ColdEraseSchema2CompletedSessionCurrentScopeV1
            .ordinaryDeclaredOwnersBeforeReturnForTesting == nil,
              ColdEraseSchema2CompletedSessionAfterSaveConsumerV1
            .ordinaryNativeBorrowerEnteredForTesting == nil else {
            throw FixtureFailure.activation
        }
        let ready = try await makeActualOrdinaryReadyFixture()
        let fixture = ready.original
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let intent = fixture.intent
        let fresh = ready.coordinator
        let cold = ready.router
        let session = ready.session
        let lifetime = ready.lifetime
        XCTAssertTrue(session.modelContext === fresh.modelContext)
        let context = fresh.modelContext
        let writer = fresh.workspaceWriter
        XCTAssertTrue(context.autosaveEnabled,
            "This regression requires the actual Ready autosave state; do not force-enable it")
        let journal = try MutationJournalStoreV1(modelContext: context,
            identity: fresh.workspaceIdentity, generationID: fresh.generationID)
        let saves = CompletionBox()
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { _ in
            MainActor.assumeIsolated { saves.count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        for cycle in 1...129 {
            // Canonical writer performs a real atomic content+journal save.
            // This helper returns before the explicit reproof below; neither
            // the whole loop nor this call is wrapped in withProvenLease.
            try seedOriginalSign(fresh)
            XCTAssertEqual(saves.count, cycle,
                "Each cycle must have one genuine save notification on the SAME context")
            XCTAssertFalse(context.hasChanges)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Site>()), cycle)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Asset>()), cycle)
            XCTAssertEqual(try context.fetchCount(
                FetchDescriptor<MutationReceiptRow>()), cycle)

            // Existing real Session API: if the automatic callback latched an
            // error this throws it. Otherwise activeCurrentRequest is absent
            // after the writer return and this is a NEW top-level .afterSave
            // entry, not a nested borrower or a no-op count increment.
            try requireOneFreshOrdinaryReproof(session: session, lifetime: lifetime)
            XCTAssertTrue(context.autosaveEnabled,
                "Silent automatic-save reproof failure must not disable autosave")
            XCTAssertTrue(fresh.completedSessionLifetimeOwnerForCurrentSession()
                === lifetime)
            XCTAssertTrue(session.modelContext === context)
            XCTAssertTrue(fresh.workspaceWriter === writer)
            guard case let .ready(current, _, _) = cold.route else {
                throw FixtureFailure.coldRoute
            }
            XCTAssertTrue(current === fresh)
            XCTAssertEqual(try writer.currentRevision().generationID,
                intent.newGenerationID)
        }
        XCTAssertEqual(saves.count, 129)
        try journal.validateAll()
        let sites = try context.fetch(FetchDescriptor<Site>())
        let assets = try context.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(Set(sites.map(\.id)).count, 129)
        XCTAssertEqual(Set(assets.map(\.id)).count, 129)
        XCTAssertTrue(sites.allSatisfy { $0.label == "Cold Erase source" })
        XCTAssertTrue(assets.allSatisfy { $0.label == "Cold Erase asset" })

        // Subsequent ordinary access AND a further save remain usable after
        // both64 and128 boundaries. A new Router/Session cannot mask failure.
        XCTAssertEqual(try writer.currentRevision().generationID,
            intent.newGenerationID)
        try seedOriginalSign(fresh)
        try requireOneFreshOrdinaryReproof(session: session, lifetime: lifetime)
        XCTAssertEqual(saves.count, 130)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Asset>()), 130)
        XCTAssertEqual(try context.fetchCount(
            FetchDescriptor<MutationReceiptRow>()), 130)
        XCTAssertTrue(context.autosaveEnabled)
        XCTAssertTrue(fresh.completedSessionLifetimeOwnerForCurrentSession()
            === lifetime)
        XCTAssertFalse(context.hasChanges)
        try journal.validateAll()
    }


    @MainActor
    func testSchema2ActualLiveSaveNestedReproofRetainsSameChargedRequestUntilOuterReturn() async throws {
        let ready = try await makeActualOrdinaryReadyFixture()
        defer { ready.original.defaults.removePersistentDomain(
            forName: ready.original.defaultsName) }
        let fresh = ready.coordinator
        let session = ready.session
        let lifetime = ready.lifetime
        let context = fresh.modelContext
        let beforeSave = lifetime.ordinaryBackingSnapshotForTesting()
        try requireOrdinaryBackingWithinOriginalEnvelope(beforeSave)
        XCTAssertFalse(beforeSave.quarantined)
        var nestedResults: [Result<Void, Error>] = []
        var liveSuccessfulReturns: UInt64?
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                let actual = Result<Void, Error> {
                    let entered = lifetime.ordinaryBackingSnapshotForTesting()
                    guard entered.activeRequestIdentity != nil,
                          entered.currentScopePresent,
                          entered.currentResourceFramePresent else {
                        throw FixtureFailure.activation
                    }
                    try self.requireOrdinaryBackingWithinOriginalEnvelope(entered)
                    XCTAssertEqual(entered.activeRequestIdentity,
                        entered.lastBornRequestIdentity)
                    XCTAssertGreaterThan(entered.occupiedSlots,
                        beforeSave.occupiedSlots)
                    liveSuccessfulReturns = entered.successfulOrdinaryReturns
                    // Real authenticated explicit relay while the actual
                    // canonical commit is still holding this Request/G frame.
                    try session.reproofAfterSave()
                    let nestedReturned = lifetime.ordinaryBackingSnapshotForTesting()
                    XCTAssertEqual(nestedReturned.activeRequestIdentity,
                        entered.activeRequestIdentity)
                    XCTAssertTrue(nestedReturned.currentScopePresent)
                    XCTAssertTrue(nestedReturned.currentResourceFramePresent)
                    XCTAssertEqual(nestedReturned.actualRequestBirths,
                        entered.actualRequestBirths)
                    XCTAssertEqual(nestedReturned.successfulOrdinaryReturns,
                        entered.successfulOrdinaryReturns)
                    XCTAssertEqual(nestedReturned.occupiedSlots, entered.occupiedSlots)
                    XCTAssertEqual(nestedReturned.retainedHistoricalBackingBytes,
                        entered.retainedHistoricalBackingBytes)
                    try self.requireOrdinaryBackingWithinOriginalEnvelope(nestedReturned)
                }
                nestedResults.append(actual) // actual nested return, never a fake receipt
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try seedOriginalSign(fresh)
        XCTAssertEqual(nestedResults.count, 1)
        try XCTUnwrap(nestedResults.first).get()
        let returned = lifetime.ordinaryBackingSnapshotForTesting()
        try requireOrdinaryBackingWithinOriginalEnvelope(returned)
        XCTAssertNil(returned.activeRequestIdentity)
        XCTAssertFalse(returned.currentScopePresent)
        XCTAssertFalse(returned.currentResourceFramePresent)
        XCTAssertEqual(returned.occupiedSlots, beforeSave.occupiedSlots)
        XCTAssertGreaterThan(returned.successfulOrdinaryReturns,
            try XCTUnwrap(liveSuccessfulReturns))
        XCTAssertFalse(returned.quarantined)
        XCTAssertTrue(context.autosaveEnabled)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try context.fetchCount(
            FetchDescriptor<MutationReceiptRow>()), 1)
        try session.reproofAfterSave()
    }

    @MainActor
    func testSchema2ActualNativeHistoryLoanRefusesPrematureBorrowerReturnGuard() async throws {
        let ready = try await makeActualOrdinaryReadyFixture()
        defer { ready.original.defaults.removePersistentDomain(
            forName: ready.original.defaultsName) }
        try seedOriginalSign(ready.coordinator)
        try ready.session.reproofAfterSave()
        guard ColdEraseSchema2CompletedSessionAfterSaveConsumerV1
            .ordinaryNativeBorrowerEnteredForTesting == nil else {
            throw FixtureFailure.activation
        }
        var loanGuardRefusals = 0
        var actualConsumers: [ColdEraseSchema2CompletedSessionAfterSaveConsumerV1] = []
        ColdEraseSchema2CompletedSessionAfterSaveConsumerV1
            .ordinaryNativeBorrowerEnteredForTesting = { consumer, _ in
                let beforeGuard = ready.lifetime.ordinaryBackingSnapshotForTesting()
                let alias = consumer.ordinaryNativeAliasStateForTesting()
                XCTAssertTrue(alias.registered)
                actualConsumers.append(consumer) // genuine exported borrower owner remains paid
                do {
                    try consumer.requireOrdinaryNativeBorrowersReturnedForTesting()
                    XCTFail("An actual active history loan must refuse premature returned-borrower proof")
                } catch {
                    XCTAssertEqual(error as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
                    loanGuardRefusals += 1
                }
                let afterGuard = ready.lifetime.ordinaryBackingSnapshotForTesting()
                XCTAssertEqual(afterGuard.actualRequestBirths, beforeGuard.actualRequestBirths)
                XCTAssertEqual(afterGuard.successfulOrdinaryReturns,
                    beforeGuard.successfulOrdinaryReturns)
                XCTAssertEqual(afterGuard.occupiedSlots, beforeGuard.occupiedSlots)
                XCTAssertEqual(afterGuard.retainedHistoricalBackingBytes,
                    beforeGuard.retainedHistoricalBackingBytes)
                // Do not synthesize loan return or retirement. The genuine
                // callback/body/postproof must now return under its real issuer.
            }
        defer {
            ColdEraseSchema2CompletedSessionAfterSaveConsumerV1
                .ordinaryNativeBorrowerEnteredForTesting = nil
        }
        try ready.session.reproofAfterSave()
        ColdEraseSchema2CompletedSessionAfterSaveConsumerV1
            .ordinaryNativeBorrowerEnteredForTesting = nil
        XCTAssertGreaterThan(loanGuardRefusals, 0)
        XCTAssertEqual(loanGuardRefusals, actualConsumers.count)
        for consumer in actualConsumers {
            try consumer.requireOrdinaryNativeBorrowersReturnedForTesting()
        }
        let returned = ready.lifetime.ordinaryBackingSnapshotForTesting()
        try requireOrdinaryBackingWithinOriginalEnvelope(returned)
        XCTAssertNil(returned.activeRequestIdentity)
        XCTAssertFalse(returned.quarantined)
        XCTAssertTrue(ready.coordinator.modelContext.autosaveEnabled)
        // Captured consumer objects and the nonnil hook are deliberate
        // unregistered export debt, not proof of historical-family discharge.
    }

    private final class OrdinaryRetirementFixtureFailure: Error {}

    @MainActor
    func testSchema2ActualReturnedScopeFailedCollectiveCutKeepsDebitAndFirstError() async throws {
        let ready = try await makeActualOrdinaryReadyFixture()
        defer { ready.original.defaults.removePersistentDomain(
            forName: ready.original.defaultsName) }
        guard ColdEraseSchema2CompletedSessionCurrentScopeV1
            .ordinaryDeclaredOwnersBeforeReturnForTesting == nil else {
            throw FixtureFailure.activation
        }
        let before = ready.lifetime.ordinaryBackingSnapshotForTesting()
        try requireOrdinaryBackingWithinOriginalEnvelope(before)
        let injected = OrdinaryRetirementFixtureFailure()
        var actualReturnedScopeObservations = 0
        var actualBeforeCut: ColdEraseSchema2CompletedOrdinaryBackingSnapshotV1?
        ColdEraseSchema2CompletedSessionCurrentScopeV1
            .ordinaryDeclaredOwnersBeforeReturnForTesting = { scope in
                let actual = scope.ordinaryDeclaredOwnerStateForTesting()
                XCTAssertTrue(actual.returned)
                XCTAssertTrue(actual.consumed)
                XCTAssertFalse(actual.uncertain)
                XCTAssertFalse(actual.pendingSourceBacking)
                XCTAssertEqual(actual.chargedSourceBacking, actual.reservedSourceBacking)
                XCTAssertFalse(actual.owningReturnPresent)
                let pending = ready.lifetime.ordinaryBackingSnapshotForTesting()
                XCTAssertNotNil(pending.activeRequestIdentity)
                XCTAssertEqual(pending.activeRequestIdentity,
                    pending.lastBornRequestIdentity)
                XCTAssertFalse(pending.currentScopePresent)
                XCTAssertFalse(pending.currentResourceFramePresent)
                XCTAssertEqual(pending.successfulOrdinaryReturns,
                    before.successfulOrdinaryReturns)
                actualBeforeCut = pending
                actualReturnedScopeObservations += 1
                // Actual wrapper/positive resource return already exists.
                // Inject only the subsequent collective-cut postproof failure;
                // never fabricate syscall outcome, success, loan or receipt.
                throw injected
            }
        defer {
            ColdEraseSchema2CompletedSessionCurrentScopeV1
                .ordinaryDeclaredOwnersBeforeReturnForTesting = nil
        }
        do {
            try ready.session.reproofAfterSave()
            XCTFail("The actual failed collective cut must remain the first result")
        } catch {
            XCTAssertTrue((error as? OrdinaryRetirementFixtureFailure) === injected)
        }
        ColdEraseSchema2CompletedSessionCurrentScopeV1
            .ordinaryDeclaredOwnersBeforeReturnForTesting = nil
        XCTAssertEqual(actualReturnedScopeObservations, 1)
        let pendingCut = try XCTUnwrap(actualBeforeCut)
        let failed = ready.lifetime.ordinaryBackingSnapshotForTesting()
        XCTAssertTrue(failed.quarantined)
        XCTAssertEqual(failed.actualRequestBirths, before.actualRequestBirths + 1)
        XCTAssertEqual(failed.successfulOrdinaryReturns, before.successfulOrdinaryReturns)
        XCTAssertEqual(failed.occupiedSlots, before.occupiedSlots + 1)
        XCTAssertEqual(failed.retainedHistoricalBackingBytes,
            pendingCut.retainedHistoricalBackingBytes)
        XCTAssertEqual(failed.occupiedSlots, pendingCut.occupiedSlots)
        XCTAssertEqual(failed.activeRequestIdentity, failed.lastBornRequestIdentity)
        XCTAssertFalse(ready.coordinator.modelContext.autosaveEnabled)
        do {
            try ready.session.reproofAfterSave()
            XCTFail("The SAME Session must retain its original after-save failure")
        } catch {
            XCTAssertTrue((error as? OrdinaryRetirementFixtureFailure) === injected)
        }
        XCTAssertThrowsError(try ready.coordinator.workspaceWriter.currentRevision())
        let refused = ready.lifetime.ordinaryBackingSnapshotForTesting()
        XCTAssertEqual(refused.actualRequestBirths, failed.actualRequestBirths)
        XCTAssertEqual(refused.successfulOrdinaryReturns, failed.successfulOrdinaryReturns)
        XCTAssertEqual(refused.occupiedSlots, failed.occupiedSlots)
        XCTAssertEqual(refused.retainedHistoricalBackingBytes,
            failed.retainedHistoricalBackingBytes)
        XCTAssertTrue(refused.quarantined)
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
    /// The genuine P entry carries two prior retired generations and its old
    /// source. Its own completed P->R CAS must admit the notification consumer
    /// while retaining immutable first-P authority for all three old trees.
    @MainActor
    func testSchema2MultiRetiredOriginalPCutOwnSessionCASColdCleansEntireFrozenRoster() async throws {
        let fixture = try await makeOriginalColdCut(
            at: .afterPointerPhaseWrite, seedTwoPreexistingRetired: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        let intent = fixture.intent
        XCTAssertEqual(intent.phase, .pointerSwitched)
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
        recovery.schema2ColdBeforeSessionPhaseCASForTesting = { session in
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
        var afterNotificationCount = 0
        recovery.schema2ColdAfterNotificationDrainBeforeFirstUnlinkForTesting = {
            afterNotificationCount += 1
            XCTAssertEqual(try EraseIntentCodecV1.decode(Data(contentsOf: fixture.intentURL)),
                intent.advancing(to: .sessionActivated))
            XCTAssertEqual(try Data(contentsOf: fixture.pointerURL), pointerBefore)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: generationsURL.path)),
                expectedInstalled)
            let oldFacts = try self.protectedFacts(in: fixture.support).filter { entry in
                oldPrefixes.contains { entry.key == $0 || entry.key.hasPrefix($0 + "/") }
            }
            XCTAssertEqual(oldFacts, preColdOldFacts,
                "Own R must not recapture a changed first-P old-generation baseline")
        }
        Self.retainedColdOwners.append((fixture.root, cold, gate, recovery))
        try cold.bindStartupAccessGate(gate)
        try await cold.retryColdEraseForTesting(service: recovery, accessGate: gate)
        if let actualRSessionFailure { throw actualRSessionFailure }
        XCTAssertEqual(afterNotificationCount, 1,
            "The actual own-CAS notification drain must finish before any first-P unlink")
        XCTAssertEqual(actualRSessionCount, 1,
            "The genuine prior-retired P entry must retain its target before its own CAS")
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
                accessGate: gate, firstColdEraseFailureForTesting: { error in
                    stopped = error
                })
        } catch {
            if stopped == nil { stopped = error }
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
#if DEBUG
        installColdREntryDiagnosticsForTesting(router: cold,service: recovery)
#endif
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
#if DEBUG
        installColdREntryDiagnosticsForTesting(router: cold,service: recovery)
#endif
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

#if DEBUG
    /// The original fixture really publishes and seals the retained reader.
    /// Only then replace its named publication with equal bytes at a new inode.
    @MainActor
    func testOriginalRetainedShutdownRejectsSameBytesPublicationSubstitutionBeforeClose() async throws {
        typealias Reader = GenerationLeaseAllocationAttemptV1
        guard Reader.originalEraseRetainedShutdownForTesting == nil else {
            throw FixtureFailure.activation
        }
        var boundaries: [Reader.OriginalEraseRetainedShutdownBoundaryForTesting] = []
        var retained: (reader: Reader,witness: EraseOriginalShutdownWitnessV1,
            activity: GenerationTemporalActivityHandleV1,recordURL: URL)?
        var originalFact: EraseColdControlLeafFactV1?
        var foreignFact: EraseColdControlLeafFactV1?
        var publicationBytes: Data?
        var registryBefore: Data?
        var canonicalAfterSubstitution: [String: PhysicalFact]?
        var fullAfterSubstitution: [String: EraseColdControlLeafFactV1]?
        Reader.originalEraseRetainedShutdownForTesting = {
            boundary,reader,witness,activity,recordURL in
            boundaries.append(boundary)
            guard boundary == .beforePublicationProof,retained == nil else {
                throw FixtureFailure.activation
            }
            // These are the actual retained owners supplied by the shutdown
            // path. Their deliberate strong test retention remains paid.
            retained = (reader,witness,activity,recordURL)
            let state = reader.originalEraseRetainedShutdownStateForTesting
            XCTAssertFalse(state.closed)
            XCTAssertFalse(state.uncertainClose)
            XCTAssertTrue(state.recordDescriptorPresent)
            XCTAssertTrue(state.recordDurable)
            XCTAssertTrue(state.registryRenamed)
            try witness.requirePreparationReader(reader,registry: witness.registry)
            let support = recordURL.deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let registryURL = recordURL.deletingLastPathComponent()
                .appendingPathComponent("registry.json")
            registryBefore = try Data(contentsOf: registryURL)
            var named = stat()
            guard recordURL.path.withCString({ lstat($0,&named) }) == 0 else {
                throw FixtureFailure.activation
            }
            let first = EraseColdControlLeafFactV1(named)
            let bytes = try Data(contentsOf: recordURL)
            originalFact = first
            publicationBytes = bytes
            foreignFact = try self.replacePostSealLeafWithSameBytes(
                recordURL,expectedFact: first,bytes: bytes)
            canonicalAfterSubstitution = try self.protectedFacts(in: support)
            fullAfterSubstitution = try self.fullPostSealFacts(in: support)
        }
        defer { Reader.originalEraseRetainedShutdownForTesting = nil }
        var refused: Error?
        do {
            _ = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
            XCTFail("A substituted retained publication cannot complete original shutdown")
        } catch { refused = error }
        XCTAssertEqual(refused as? GenerationLeaseRegistryFailureV1,.invalidIdentity)
        XCTAssertEqual(boundaries,[.beforePublicationProof])
        let held = try XCTUnwrap(retained)
        let first = try XCTUnwrap(originalFact)
        let foreign = try XCTUnwrap(foreignFact)
        XCTAssertNotEqual(first.inode,foreign.inode)
        XCTAssertEqual(first.device,foreign.device)
        XCTAssertEqual(first.mode,foreign.mode)
        XCTAssertEqual(first.user,foreign.user)
        XCTAssertEqual(first.group,foreign.group)
        XCTAssertEqual(first.links,foreign.links)
        XCTAssertEqual(first.size,foreign.size)
        XCTAssertEqual(try Data(contentsOf: held.recordURL),try XCTUnwrap(publicationBytes))
        var current = stat()
        XCTAssertEqual(held.recordURL.path.withCString({ lstat($0,&current) }),0)
        XCTAssertEqual(EraseColdControlLeafFactV1(current),foreign)
        let state = held.reader.originalEraseRetainedShutdownStateForTesting
        XCTAssertFalse(state.closed)
        XCTAssertFalse(state.uncertainClose,
            "Binding refusal precedes the handle and record close attempts")
        XCTAssertTrue(state.recordDescriptorPresent,
            "The held original publication descriptor remains paid")
        let support = held.recordURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(try Data(contentsOf: held.recordURL.deletingLastPathComponent()
            .appendingPathComponent("registry.json")),try XCTUnwrap(registryBefore))
        XCTAssertEqual(try protectedFacts(in: support),try XCTUnwrap(canonicalAfterSubstitution))
        XCTAssertEqual(try fullPostSealFacts(in: support),try XCTUnwrap(fullAfterSubstitution))
        // The real original operation is terminally uncertain. A subsequent
        // guard call cannot acquire a new witness or attempt a numeric close.
        XCTAssertThrowsError(try held.witness.requireDrained(registry: held.witness.registry)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1,.uncertainOwner)
        }
        XCTAssertThrowsError(try held.reader.closeForOriginalEraseShutdown(
            proof: held.witness,activity: held.activity)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1,.uncertainOwner)
        }
        XCTAssertEqual(boundaries,[.beforePublicationProof])
        XCTAssertEqual(held.reader.originalEraseRetainedShutdownStateForTesting,state)
        withExtendedLifetime(held) { }
    }



    @MainActor
    private struct NotificationAdmissionFixture {
        let pointer: PointerFixture
        let cold: StartupRouter
        let gate: AppAccessGateV1
        let service: EraseAllService
    }

    @MainActor
    private func makeNotificationAdmissionFixture(seedNotifications: Bool = false) async throws
        -> NotificationAdmissionFixture {
        let fixture = try await makeOriginalColdCut(at: .afterPointerPhaseWrite,
            seedTwoPreexistingRetired: true, seedNotifications: seedNotifications)
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
        let service = EraseAllService(applicationSupportURL: fixture.support,
            cachesDirectoryURL: fixture.caches, temporaryDirectoryURL: fixture.temporary,
            userDefaults: fixture.defaults, bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: fixture.defaultsName,
            notificationSystem: fixture.notificationSeed?.probe)
        Self.retainedColdOwners.append((fixture.root, cold, gate, service))
        return NotificationAdmissionFixture(pointer: fixture, cold: cold, gate: gate, service: service)
    }

    @MainActor
    private func executeNotificationAdmissionFixture(_ owner: NotificationAdmissionFixture) async throws {
        try owner.cold.bindStartupAccessGate(owner.gate)
        try await owner.cold.retryColdEraseForTesting(service: owner.service, accessGate: owner.gate)
    }

    @MainActor
    func testSchema2OwnPCASNotificationAdmissionRejectsPreCASAndInFlightWithoutOriginPromotion() async throws {
        typealias Manifest = EraseSchema2ColdManifestOwnerV1
        guard Manifest.retainedSourceProjectionForTesting == nil else { throw FixtureFailure.activation }
        let owner = try await makeNotificationAdmissionFixture()
        defer {
            Manifest.retainedSourceProjectionForTesting = nil
            owner.pointer.defaults.removePersistentDomain(forName: owner.pointer.defaultsName)
        }
        var preCAS = 0
        var cuts: [Manifest.RetainedSourceProjectionBoundaryForTesting] = []
        var failure: Error?
        owner.service.schema2ColdBeforeSessionPhaseCASForTesting = { _ in
            do {
                let access = try owner.cold.borrowSchema2ColdNotificationFixtureAccessForTesting()
                preCAS += 1
                XCTAssertEqual(access.intent, owner.pointer.intent)
                XCTAssertThrowsError(try access.manifest.requireSchema2ColdNotificationAdmissionForTesting(
                    intent: access.intent.advancing(to: .sessionActivated), preparation: access.preparation,
                    store: access.store, operation: access.operation))
            } catch { failure = error }
        }
        Manifest.retainedSourceProjectionForTesting = { cut, manifest, operation, store, first, published, preparation, error in
            guard first.eraseID == owner.pointer.intent.eraseID else { return }
            cuts.append(cut)
            XCTAssertNil(error)
            switch cut {
            case .beforeProjection, .inFlight:
                do {
                    XCTAssertThrowsError(try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                        intent: published, preparation: preparation, store: store, operation: operation))
                } catch {
                    if failure == nil { failure = error }
                }
            case .completed:
                do {
                    // Guard-only success cannot pre-capture an owner. The real
                    // flow below still performs its sole notification capture.
                    try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                        intent: published, preparation: preparation, store: store, operation: operation)
                    XCTAssertThrowsError(try manifest.requireFirstAbsentRetiredSourceIDs(
                        intent: published, operation: operation),
                        "An own R projection is never a fresh-R first-absence origin")
                    XCTAssertThrowsError(try manifest.captureRetainedRetiredSources(
                        intent: published, preparation: preparation, operation: operation),
                        "Completed own CAS cannot recapture retired sources as a late R baseline")
                } catch {
                    if failure == nil { failure = error }
                }
            case .failed:
                if failure == nil { failure = error ?? FixtureFailure.activation }
            }
        }
        try await executeNotificationAdmissionFixture(owner)
        if let failure { throw failure }
        XCTAssertEqual(preCAS, 1)
        XCTAssertEqual(cuts, [.beforeProjection, .inFlight, .completed])
        guard case .ready = owner.cold.route else { throw FixtureFailure.coldRoute }
        XCTAssertEqual(owner.pointer.intent.phase, .pointerSwitched)
    }

    @MainActor
    func testSchema2OwnPCASNotificationAdmissionRejectsGenuineFailedProjectionAndLateRecapture() async throws {
        typealias Manifest = EraseSchema2ColdManifestOwnerV1
        guard Manifest.retainedSourceProjectionForTesting == nil else { throw FixtureFailure.activation }
        let owner = try await makeNotificationAdmissionFixture()
        defer {
            Manifest.retainedSourceProjectionForTesting = nil
            owner.pointer.defaults.removePersistentDomain(forName: owner.pointer.defaultsName)
        }
        var cuts: [Manifest.RetainedSourceProjectionBoundaryForTesting] = []
        var mutationFailure: Error?
        var actualFailure: Error?
        var changedFact: EraseColdControlLeafFactV1?
        var beforeFact: EraseColdControlLeafFactV1?
        Manifest.retainedSourceProjectionForTesting = { cut, manifest, operation, store, first, published, preparation, error in
            guard first.eraseID == owner.pointer.intent.eraseID else { return }
            cuts.append(cut)
            switch cut {
            case .inFlight:
                do {
                    let url = owner.pointer.support.appendingPathComponent("FieldEvidenceErase/preparation.json")
                    var before = stat(), after = stat()
                    guard lstat(url.path, &before) == 0 else { throw FixtureFailure.activation }
                    let bytes = try Data(contentsOf: url)
                    try bytes.write(to: url, options: .atomic)
                    guard lstat(url.path, &after) == 0 else { throw FixtureFailure.activation }
                    beforeFact = EraseColdControlLeafFactV1(before)
                    changedFact = EraseColdControlLeafFactV1(after)
                    XCTAssertEqual(try Data(contentsOf: url), bytes)
                } catch {
                    if mutationFailure == nil { mutationFailure = error }
                }
            case .failed:
                actualFailure = error
                XCTAssertNotNil(error, "The actual retained producer must retain its own proof error")
                do {
                    XCTAssertThrowsError(try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                        intent: published, preparation: preparation, store: store, operation: operation))
                    XCTAssertThrowsError(try manifest.captureRetainedRetiredSources(
                        intent: published, preparation: preparation, operation: operation))
                } catch {
                    if mutationFailure == nil { mutationFailure = error }
                }
            case .completed: XCTFail("A thrown projection proof cannot become completed")
            case .beforeProjection: break
            }
        }
        try await executeNotificationAdmissionFixture(owner)
        if let mutationFailure { throw mutationFailure }
        XCTAssertNotNil(actualFailure)
        XCTAssertEqual(cuts, [.beforeProjection, .inFlight, .failed])
        XCTAssertNotEqual(try XCTUnwrap(beforeFact).inode, try XCTUnwrap(changedFact).inode)
        guard case .maintenance(.eraseInconsistent) = owner.cold.route else { throw FixtureFailure.coldRoute }
        XCTAssertEqual(try Data(contentsOf: owner.pointer.pointerURL), owner.pointer.pointerBefore)
        for id in owner.pointer.intent.generationIDsToDelete {
            var fact = stat()
            XCTAssertEqual(lstat(owner.pointer.support.appendingPathComponent(
                "FieldEvidenceData/generations/" + id.uuidString.lowercased()).path, &fact), 0)
        }
    }

    @MainActor
    func testSchema2OwnPCASNotificationAdmissionRejectsForeignLiveOperationAndGenuineStore() async throws {
        typealias Manifest = EraseSchema2ColdManifestOwnerV1
        guard Manifest.retainedSourceProjectionForTesting == nil else { throw FixtureFailure.activation }
        let foreign = try await makeNotificationAdmissionFixture(seedNotifications: true)
        let owner = try await makeNotificationAdmissionFixture()
        let probe = try XCTUnwrap(foreign.pointer.notificationSeed?.probe)
        let suspended = expectation(description: "Actual foreign notification OS readback awaits while its owner is live")
        var resume: CheckedContinuation<Void, Never>?
        var paused = false
        var settling = false
        var foreignAccess: Schema2ColdNotificationFixtureAccessV1?
        var accessFailure: Error?
        probe.beforeObservationForTesting = {
            guard !paused, !settling else { return }
            paused = true
            do { foreignAccess = try foreign.cold.borrowSchema2ColdNotificationFixtureAccessForTesting() }
            catch { accessFailure = error }
            suspended.fulfill()
            await withCheckedContinuation { resume = $0 }
        }
        let foreignTask = Task { @MainActor in try await self.executeNotificationAdmissionFixture(foreign) }
        defer {
            settling = true
            probe.beforeObservationForTesting = nil
            if let held = resume { resume = nil; held.resume() }
            foreignTask.cancel()
            Manifest.retainedSourceProjectionForTesting = nil
            foreign.pointer.defaults.removePersistentDomain(forName: foreign.pointer.defaultsName)
            owner.pointer.defaults.removePersistentDomain(forName: owner.pointer.defaultsName)
        }
        do {
        await fulfillment(of: [suspended], timeout: 30)
        if let accessFailure { throw accessFailure }
        let genuineForeign = try XCTUnwrap(foreignAccess)
        var consumerCalls = 0
        var failure: Error?
        Manifest.retainedSourceProjectionForTesting = { cut, manifest, operation, store, first, published, preparation, _ in
            guard first.eraseID == owner.pointer.intent.eraseID, cut == .completed else { return }
            do {
                // Prove foreign liveness NOW. A stale-owner/setup refusal
                // cannot satisfy either direct consumer negative below.
                try genuineForeign.operation.requireServiceAccess()
                try genuineForeign.operation.requireSchema2ColdManifestOwner(genuineForeign.manifest)
                XCTAssertFalse(operation === genuineForeign.operation)
                XCTAssertFalse(store === genuineForeign.store)
                consumerCalls += 1
                XCTAssertThrowsError(try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                    intent: published, preparation: preparation, store: store,
                    operation: genuineForeign.operation))
                XCTAssertThrowsError(try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                    intent: published, preparation: preparation, store: genuineForeign.store,
                    operation: operation))
                try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                    intent: published, preparation: preparation, store: store, operation: operation)
            } catch { failure = error }
        }
        try await executeNotificationAdmissionFixture(owner)
        if let failure { throw failure }
        XCTAssertEqual(consumerCalls, 1)
        guard case .ready = owner.cold.route else { throw FixtureFailure.coldRoute }
        settling = true
        probe.beforeObservationForTesting = nil
        if let held = resume { resume = nil; held.resume() }
        try await foreignTask.value
        guard case .ready = foreign.cold.route else { throw FixtureFailure.coldRoute }
        } catch {
            // Settle the genuine foreign task before preserving the first
            // fixture error; no OS-port waiter may escape this selector.
            settling = true
            probe.beforeObservationForTesting = nil
            if let held = resume { resume = nil; held.resume() }
            foreignTask.cancel()
            _ = try? await foreignTask.value
            throw error
        }
    }

    private enum NotificationPublishedControl: Equatable { case intent, preparation, currentPointer }
    @MainActor
    private func requireChangedPublishedNotificationControlRefusal(_ control: NotificationPublishedControl) async throws {
        typealias Manifest = EraseSchema2ColdManifestOwnerV1
        guard Manifest.retainedSourceProjectionForTesting == nil else { throw FixtureFailure.activation }
        let owner = try await makeNotificationAdmissionFixture()
        defer {
            Manifest.retainedSourceProjectionForTesting = nil
            owner.pointer.defaults.removePersistentDomain(forName: owner.pointer.defaultsName)
        }
        var reachedConsumer = 0
        var mutationFailure: Error?
        var beforeFact: EraseColdControlLeafFactV1?
        var afterFact: EraseColdControlLeafFactV1?
        Manifest.retainedSourceProjectionForTesting = { cut, manifest, operation, store, first, published, preparation, _ in
            guard first.eraseID == owner.pointer.intent.eraseID, cut == .completed else { return }
            do {
                try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                    intent: published, preparation: preparation, store: store, operation: operation)
                let url: URL
                switch control {
                case .intent: url = owner.pointer.intentURL
                case .preparation: url = owner.pointer.support.appendingPathComponent("FieldEvidenceErase/preparation.json")
                case .currentPointer: url = owner.pointer.pointerURL
                }
                let bytes = try Data(contentsOf: url)
                var before = stat(), after = stat()
                guard lstat(url.path, &before) == 0 else { throw FixtureFailure.activation }
                try bytes.write(to: url, options: .atomic)
                guard lstat(url.path, &after) == 0 else { throw FixtureFailure.activation }
                beforeFact = EraseColdControlLeafFactV1(before); afterFact = EraseColdControlLeafFactV1(after)
                XCTAssertEqual(try Data(contentsOf: url), bytes)
                reachedConsumer += 1
                XCTAssertThrowsError(try manifest.requireSchema2ColdNotificationAdmissionForTesting(
                    intent: published, preparation: preparation, store: store, operation: operation),
                    "The direct production admission must refuse its changed published control")
            } catch { mutationFailure = error }
        }
        try await executeNotificationAdmissionFixture(owner)
        if let mutationFailure { throw mutationFailure }
        XCTAssertEqual(reachedConsumer, 1)
        XCTAssertNotEqual(try XCTUnwrap(beforeFact).inode, try XCTUnwrap(afterFact).inode)
        guard case .maintenance(.eraseInconsistent) = owner.cold.route else { throw FixtureFailure.coldRoute }
        let intent = try EraseIntentCodecV1.decode(Data(contentsOf: owner.pointer.intentURL))
        XCTAssertEqual(intent, owner.pointer.intent.advancing(to: .sessionActivated))
        for id in owner.pointer.intent.generationIDsToDelete {
            var fact = stat()
            XCTAssertEqual(lstat(owner.pointer.support.appendingPathComponent(
                "FieldEvidenceData/generations/" + id.uuidString.lowercased()).path, &fact), 0)
        }
    }
    @MainActor
    func testSchema2OwnPCASNotificationAdmissionRejectsChangedPublishedIntent() async throws {
        try await requireChangedPublishedNotificationControlRefusal(.intent)
    }
    @MainActor
    func testSchema2OwnPCASNotificationAdmissionRejectsChangedCapturedPreparation() async throws {
        try await requireChangedPublishedNotificationControlRefusal(.preparation)
    }
    @MainActor
    func testSchema2OwnPCASNotificationAdmissionRejectsChangedPublishedPointer() async throws {
        try await requireChangedPublishedNotificationControlRefusal(.currentPointer)
    }

    @MainActor
    func testDrainedSourceProjectionRefusesLateLoanFromGenuineSettledShutdown() async throws {
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        XCTAssertThrowsError(try fixture.operation.loanOriginalEraseDrainedSourceProjectionForTesting())
        try requireTargetPointerBinding(support: fixture.support, intent: fixture.intent,
            pointerBytes: fixture.pointerBefore)
        XCTAssertEqual(fixture.completion.count, 0)
    }

    @MainActor
    func testOriginalPhysicalTransitionConservesPopulatedSourceAndEmptyTargetBeforeRetirement() async throws {
        var handoffs = 0
        var drained = 0
        var finalIntent: EraseIntentV1?
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite,
            physicalTransitionControl: { stage, support in
                switch stage {
                case .sourceOwnerHandoff: handoffs += 1
                case .drainedShutdown:
                    drained += 1
                    finalIntent = try EraseIntentCodecV1.decode(Data(contentsOf:
                        support.appendingPathComponent("FieldEvidenceErase/erase.json")))
                default: throw FixtureFailure.activation
                }
            })
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        XCTAssertEqual(handoffs, 1)
        XCTAssertEqual(drained, 1)
        XCTAssertEqual(finalIntent, fixture.intent)
        XCTAssertEqual(try StoreGenerationFactory(applicationSupportURL: fixture.support)
            .makeGenerationLeaseRegistry().activeEpochs(), [])
        XCTAssertEqual(fixture.completion.count, 0)
        try requireTargetPointerBinding(support: fixture.support, intent: fixture.intent,
            pointerBytes: fixture.pointerBefore)
        let generations = fixture.support.appendingPathComponent("FieldEvidenceData/generations")
        for id in fixture.intent.generationIDsToDelete + [fixture.intent.newGenerationID] {
            var actual = stat()
            XCTAssertEqual(lstat(generations.appendingPathComponent(id.uuidString.lowercased()).path, &actual), 0)
            XCTAssertEqual(actual.st_mode & S_IFMT, S_IFDIR)
        }
    }

    private enum OriginalPhysicalMutation: Equatable { case sameBytesNewInode, nonSQLiteTree, committedPage, validWALSalt }

    /// Re-salt the genuine pre-release WAL with correct checksums. Its real
    /// committed page payloads are unchanged, so the consumer must refuse the
    /// surviving WAL frontier rewrite rather than relying on malformed bytes.
    private func reSaltedOriginalWAL(_ data: Data) throws -> Data {
        var bytes = Array(data)
        func word(_ at: Int, little: Bool = false) throws -> UInt32 {
            guard at >= 0, at + 4 <= bytes.count else { throw FixtureFailure.activation }
            let indices = little ? Array((at..<(at + 4)).reversed()) : Array(at..<(at + 4))
            return indices.reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[$1]) }
        }
        func put(_ value: UInt32, at: Int) {
            for i in 0..<4 { bytes[at + i] = UInt8(truncatingIfNeeded: value >> (24 - 8 * i)) }
        }
        let magic = try word(0)
        guard magic == 0x377f0682 || magic == 0x377f0683,
              bytes.count >= 32 else { throw FixtureFailure.activation }
        let pageSize = Int(try word(8)); let frameSize = 24 + pageSize
        guard pageSize >= 512, pageSize <= 65_536, pageSize.nonzeroBitCount == 1,
              bytes.count > 32, (bytes.count - 32) % frameSize == 0 else { throw FixtureFailure.activation }
        let oldSalt1 = try word(16), oldSalt2 = try word(20)
        let newSalt1 = oldSalt1 &+ 1
        put(newSalt1, at: 16)
        var checksum: (UInt32, UInt32) = (0, 0)
        func update(_ range: Range<Int>) throws {
            guard range.count % 8 == 0 else { throw FixtureFailure.activation }
            for offset in stride(from: range.lowerBound, to: range.upperBound, by: 8) {
                checksum.0 = checksum.0 &+ (try word(offset, little: magic == 0x377f0682)) &+ checksum.1
                checksum.1 = checksum.1 &+ (try word(offset + 4, little: magic == 0x377f0682)) &+ checksum.0
            }
        }
        try update(0..<24)
        put(checksum.0, at: 24); put(checksum.1, at: 28)
        var rewritten = 0
        for frame in stride(from: 32, to: bytes.count, by: frameSize) {
            guard try word(frame + 8) == oldSalt1, try word(frame + 12) == oldSalt2 else { break }
            put(newSalt1, at: frame + 8)
            try update(frame..<(frame + 8))
            try update((frame + 24)..<(frame + frameSize))
            put(checksum.0, at: frame + 16); put(checksum.1, at: frame + 20)
            rewritten += 1
        }
        guard rewritten > 0 else { throw FixtureFailure.activation }
        return Data(bytes)
    }

    @MainActor
    private func requireOriginalPhysicalMutationRefusal(_ mutation: OriginalPhysicalMutation) async throws {
        typealias Reader = GenerationLeaseAllocationAttemptV1
        guard Reader.originalEraseRetainedShutdownForTesting == nil else { throw FixtureFailure.activation }
        var closeEntries = 0
        Reader.originalEraseRetainedShutdownForTesting = { _, _, _, _, _ in closeEntries += 1 }
        defer { Reader.originalEraseRetainedShutdownForTesting = nil }
        var supportURL: URL?
        var beforeIntent: Data?
        var beforeCurrent: Data?
        var beforeRetired: Data?
        var beforeRegistry: Data?
        var genuineWAL: Data?
        var reachedDrain = 0
        var oldLeaf: EraseColdControlLeafFactV1?
        var newLeaf: EraseColdControlLeafFactV1?
        var changedURL: URL?
        var mutationFailure: Error?
        var sameBytesBefore: Data?
        var sameBytesAfter: Data?
        do {
            _ = try await makeOriginalColdCut(at: .afterSessionPhaseWrite,
                physicalTransitionControl: { stage, support in
                    do {
                    let intentURL = support.appendingPathComponent("FieldEvidenceErase/erase.json")
                    let intent = try EraseIntentCodecV1.decode(Data(contentsOf: intentURL))
                    let generations = support.appendingPathComponent("FieldEvidenceData/generations")
                    let source = generations.appendingPathComponent(intent.oldGenerationID.uuidString.lowercased())
                    if stage == .sourceOwnerHandoff {
                        if mutation == .validWALSalt {
                            genuineWAL = try Data(contentsOf: source.appendingPathComponent("model.sqlite-wal"))
                            XCTAssertGreaterThan(try XCTUnwrap(genuineWAL).count, 32,
                                "The genuine populated source must supply actual WAL frames")
                        }
                        return
                    }
                    guard stage == .drainedShutdown else { throw FixtureFailure.activation }
                    reachedDrain += 1; supportURL = support
                    beforeIntent = try Data(contentsOf: intentURL)
                    beforeCurrent = try Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/current.json"))
                    beforeRetired = try Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/retired.json"))
                    beforeRegistry = try Data(contentsOf: support.appendingPathComponent("FieldEvidenceOperations/generation-leases/registry.json"))
                    let target = generations.appendingPathComponent(intent.newGenerationID.uuidString.lowercased())
                    let url: URL
                    switch mutation {
                    case .sameBytesNewInode: url = target.appendingPathComponent("model.sqlite")
                    case .committedPage: url = source.appendingPathComponent("model.sqlite")
                    case .validWALSalt: url = source.appendingPathComponent("model.sqlite-wal")
                    case .nonSQLiteTree: url = generations.appendingPathComponent("c28-unowned-non-sqlite-leaf")
                    }
                    changedURL = url
                    var before = stat()
                    if mutation != .nonSQLiteTree {
                        guard lstat(url.path, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
                              before.st_nlink == 1 else { throw FixtureFailure.activation }
                        oldLeaf = EraseColdControlLeafFactV1(before)
                    }
                    switch mutation {
                    case .sameBytesNewInode:
                        let bytes = try Data(contentsOf: url)
                        sameBytesBefore = bytes
                        try bytes.write(to: url, options: .atomic)
                        sameBytesAfter = try Data(contentsOf: url)
                    case .nonSQLiteTree:
                        try Data("Unowned non-SQLite tree change".utf8).write(to: url)
                    case .committedPage:
                        var bytes = try Data(contentsOf: url)
                        guard bytes.count >= 512 else { throw FixtureFailure.activation }
                        bytes[bytes.count - 1] ^= 1
                        try bytes.write(to: url)
                    case .validWALSalt:
                        let rewritten = try self.reSaltedOriginalWAL(try XCTUnwrap(genuineWAL))
                        try rewritten.write(to: url)
                        let model = Darwin.open(source.appendingPathComponent("model.sqlite").path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                        guard model >= 0 else { throw FixtureFailure.activation }
                        let wal = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                        if wal < 0 {
                            let closeResult = Darwin.close(model)
                            guard closeResult == 0 else { throw FixtureFailure.activation }
                            throw FixtureFailure.activation
                        }
                        var validationFailure: Error?
                        do { _ = try CompletedAbortSQLitePhysicalImageV1.capture(model: model, wal: wal) }
                        catch { validationFailure = error }
                        let walClose = Darwin.close(wal), modelClose = Darwin.close(model)
                        if let validationFailure { throw validationFailure }
                        guard walClose == 0, modelClose == 0 else { throw FixtureFailure.activation }
                    }
                    var after = stat()
                    guard lstat(url.path, &after) == 0 else { throw FixtureFailure.activation }
                    newLeaf = EraseColdControlLeafFactV1(after)
                    } catch {
                        mutationFailure = error
                        throw error
                    }
                })
            XCTFail("The real physical-transition consumer must refuse the hostile image")
        } catch {
            XCTAssertEqual(reachedDrain, 1,
                "A setup/constructor refusal cannot substitute for the actual drained consumer")
        }
        if let mutationFailure { throw mutationFailure }
        XCTAssertEqual(closeEntries, 0,
            "Physical refusal must precede every authenticated record/handle close")
        let support = try XCTUnwrap(supportURL)
        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("FieldEvidenceErase/erase.json")), beforeIntent)
        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/current.json")), beforeCurrent)
        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/retired.json")), beforeRetired)
        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("FieldEvidenceOperations/generation-leases/registry.json")), beforeRegistry)
        let after = try XCTUnwrap(newLeaf)
        if mutation == .sameBytesNewInode {
            XCTAssertEqual(try XCTUnwrap(sameBytesBefore), try XCTUnwrap(sameBytesAfter))
            XCTAssertNotEqual(try XCTUnwrap(oldLeaf).inode, after.inode)
        } else if mutation != .nonSQLiteTree {
            XCTAssertEqual(try XCTUnwrap(oldLeaf).inode, after.inode)
        }
        XCTAssertNotNil(changedURL)
    }

    @MainActor
    func testOriginalPhysicalTransitionRejectsSameBytesNewInodeBeforeRetirement() async throws {
        try await requireOriginalPhysicalMutationRefusal(.sameBytesNewInode)
    }
    @MainActor
    func testOriginalPhysicalTransitionRejectsNonSQLiteTreeMutationBeforeRetirement() async throws {
        try await requireOriginalPhysicalMutationRefusal(.nonSQLiteTree)
    }
    @MainActor
    func testOriginalPhysicalTransitionRejectsCommittedPageCorruptionBeforeRetirement() async throws {
        try await requireOriginalPhysicalMutationRefusal(.committedPage)
    }
    @MainActor
    func testOriginalPhysicalTransitionRejectsChecksumValidSurvivingWALRewriteBeforeRetirement() async throws {
        try await requireOriginalPhysicalMutationRefusal(.validWALSalt)
    }

    /// The actual Original owner removes its authenticated record before its
    /// real sole close. This verifies that complete shutdown leaves no record
    /// for the later cold owner's first lease-name census to misinterpret.
    @MainActor
    func testOriginalRetainedShutdownRemovesOnlyAuthenticatedPublicationBeforeCheckedClose() async throws {
        typealias Reader = GenerationLeaseAllocationAttemptV1
        guard Reader.originalEraseRetainedShutdownForTesting == nil else {
            throw FixtureFailure.activation
        }
        var boundaries: [Reader.OriginalEraseRetainedShutdownBoundaryForTesting] = []
        var retained: Reader?
        var recordURL: URL?
        var namedRecord: EraseColdControlLeafFactV1?
        var namedLease: EraseColdControlLeafFactV1?
        var registryAfterHandleClose: Data?
        var leaseNamespaceBefore: OriginalRetainedNamespaceForTesting?
        var canonicalBefore: [String: PhysicalFact]?
        var fullBefore: [String: EraseColdControlLeafFactV1]?
        var retirement: Reader.OriginalEraseRetainedRetirementProjectionForTesting?
        Reader.originalEraseRetainedShutdownForTesting = { boundary,reader,witness,activity,url in
            boundaries.append(boundary)
            let state = reader.originalEraseRetainedShutdownStateForTesting
            XCTAssertFalse(state.closed)
            XCTAssertFalse(state.uncertainClose)
            let support = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            switch boundary {
            case .beforePublicationProof:
                XCTAssertNil(retained)
                retained = reader; recordURL = url
                try witness.requirePreparationReader(reader,registry: witness.registry)
                XCTAssertTrue(state.recordDescriptorPresent)
                canonicalBefore = try self.protectedFacts(in: support)
                fullBefore = try self.fullPostSealFacts(in: support)
            case .beforeRecordClose:
                XCTAssertTrue(retained === reader)
                XCTAssertEqual(recordURL,url)
                XCTAssertTrue(state.recordDescriptorPresent)
                try XCTUnwrap(reader.allocatedHandle).requireCheckedClosedForOriginalEraseShutdown(registry: witness.registry)
                var leaf = stat(), parent = stat()
                guard url.path.withCString({ lstat($0,&leaf) }) == 0,
                      url.deletingLastPathComponent().path.withCString({ lstat($0,&parent) }) == 0 else {
                    throw FixtureFailure.activation
                }
                namedRecord = EraseColdControlLeafFactV1(leaf)
                namedLease = EraseColdControlLeafFactV1(parent)
                registryAfterHandleClose = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent("registry.json"))
                leaseNamespaceBefore = try self.originalRetainedNamespaceForTesting(record: url)
            case .afterRecordClose:
                XCTAssertFalse(state.recordDescriptorPresent)
                let proof = try XCTUnwrap(reader.originalEraseRetainedRetirementProjectionForTesting)
                XCTAssertTrue(proof.recordCloseReturned)
                XCTAssertEqual(proof.recordBefore,try XCTUnwrap(namedRecord))
                XCTAssertEqual(proof.leaseBefore,try XCTUnwrap(namedLease))
                XCTAssertEqual(proof.recordAfterUnlink.links,0)
                XCTAssertEqual(proof.recordAfterUnlink.device,proof.recordBefore.device)
                XCTAssertEqual(proof.recordAfterUnlink.inode,proof.recordBefore.inode)
                XCTAssertEqual(proof.recordAfterUnlink.mode,proof.recordBefore.mode)
                XCTAssertEqual(proof.recordAfterUnlink.user,proof.recordBefore.user)
                XCTAssertEqual(proof.recordAfterUnlink.group,proof.recordBefore.group)
                XCTAssertEqual(proof.recordAfterUnlink.size,proof.recordBefore.size)
                XCTAssertEqual(proof.recordAfterUnlink.modifiedSeconds,proof.recordBefore.modifiedSeconds)
                XCTAssertEqual(proof.recordAfterUnlink.modifiedNanoseconds,proof.recordBefore.modifiedNanoseconds)
                try self.requireAbsentWithoutFollowing(url)
                var parent = stat()
                guard url.deletingLastPathComponent().path.withCString({ lstat($0,&parent) }) == 0 else {
                    throw FixtureFailure.activation
                }
                XCTAssertEqual(EraseColdControlLeafFactV1(parent),proof.leaseAfterUnlink)
                XCTAssertEqual(try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent("registry.json")),try XCTUnwrap(registryAfterHandleClose))
                XCTAssertEqual(try self.protectedFacts(in: support),try XCTUnwrap(canonicalBefore))
                XCTAssertEqual(try self.fullPostSealFacts(in: support),try XCTUnwrap(fullBefore))
                try self.requireOnlyOriginalRetainedPublicationRemovedForTesting(
                    before: try XCTUnwrap(leaseNamespaceBefore),record: url,projection: proof)
                retirement = proof
            }
        }
        defer { Reader.originalEraseRetainedShutdownForTesting = nil }
        let fixture = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.defaultsName) }
        XCTAssertEqual(boundaries,[.beforePublicationProof,.beforeRecordClose,.afterRecordClose])
        let actual = try XCTUnwrap(retained)
        let proof = try XCTUnwrap(retirement)
        XCTAssertEqual(actual.originalEraseRetainedRetirementProjectionForTesting,proof)
        XCTAssertTrue(actual.originalEraseRetainedShutdownStateForTesting.closed)
        XCTAssertFalse(actual.originalEraseRetainedShutdownStateForTesting.uncertainClose)
        XCTAssertFalse(actual.originalEraseRetainedShutdownStateForTesting.recordDescriptorPresent)
        try requireAbsentWithoutFollowing(try XCTUnwrap(recordURL))
        withExtendedLifetime(actual) { }
    }

    private final class OriginalRetainedShutdownInjectedPostCloseProofFault: Error { }

    private struct OriginalRetainedNamespaceLeafForTesting: Equatable {
        let fact: EraseColdControlLeafFactV1
        let bytes: Data?
    }
    private struct OriginalRetainedNamespaceForTesting {
        let lease: EraseColdControlLeafFactV1
        let operations: EraseColdControlLeafFactV1
        let support: EraseColdControlLeafFactV1
        let nodes: [String: OriginalRetainedNamespaceLeafForTesting]
    }
    private func originalRetainedNamespaceForTesting(record: URL) throws
        -> OriginalRetainedNamespaceForTesting {
        let lease = record.deletingLastPathComponent()
        func full(_ url: URL) throws -> EraseColdControlLeafFactV1 {
            var value = stat()
            guard url.path.withCString({ lstat($0,&value) }) == 0 else {
                throw FixtureFailure.activation
            }
            return EraseColdControlLeafFactV1(value)
        }
        let root = try full(lease)
        let operations = try full(lease.deletingLastPathComponent())
        let support = try full(lease.deletingLastPathComponent().deletingLastPathComponent())
        var nodes: [String: OriginalRetainedNamespaceLeafForTesting] = [:]
        func visit(_ directory: URL, prefix: String) throws {
            let first = try full(directory)
            guard first.mode & S_IFMT == S_IFDIR else { throw FixtureFailure.activation }
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            guard names.count == Set(names).count else { throw FixtureFailure.activation }
            for name in names {
                guard name != ".",name != "..",!name.contains("/"),nodes.count < 256 else {
                    throw FixtureFailure.activation
                }
                let url = directory.appendingPathComponent(name)
                let fact = try full(url)
                let key = prefix + name
                guard nodes[key] == nil else { throw FixtureFailure.activation }
                let kind = fact.mode & S_IFMT
                guard kind == S_IFDIR || (kind == S_IFREG && fact.links == 1) else {
                    throw FixtureFailure.activation
                }
                let bytes = kind == S_IFREG ? try Data(contentsOf: url) : nil
                nodes[key] = .init(fact: fact,bytes: bytes)
                if kind == S_IFDIR { try visit(url,prefix: key + "/") }
                guard try full(url) == fact else { throw FixtureFailure.activation }
            }
            guard try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == names,
                  try full(directory) == first else { throw FixtureFailure.activation }
        }
        try visit(lease,prefix: "")
        guard try full(lease) == root,
              try full(lease.deletingLastPathComponent()) == operations,
              try full(lease.deletingLastPathComponent().deletingLastPathComponent()) == support else {
            throw FixtureFailure.activation
        }
        return .init(lease: root,operations: operations,support: support,nodes: nodes)
    }
    private func requireOnlyOriginalRetainedPublicationRemovedForTesting(
        before: OriginalRetainedNamespaceForTesting, record: URL,
        projection: GenerationLeaseAllocationAttemptV1.OriginalEraseRetainedRetirementProjectionForTesting
    ) throws {
        let after = try originalRetainedNamespaceForTesting(record: record)
        let name = record.lastPathComponent
        let leaf = try XCTUnwrap(before.nodes[name])
        XCTAssertEqual(leaf.fact,projection.recordBefore)
        XCTAssertEqual(before.lease,projection.leaseBefore)
        XCTAssertEqual(after.lease,projection.leaseAfterUnlink)
        XCTAssertEqual(after.operations,before.operations)
        XCTAssertEqual(after.support,before.support)
        XCTAssertNil(after.nodes[name])
        XCTAssertEqual(after.nodes,before.nodes.filter({ $0.key != name }),
            "Every unrelated Registry/owner leaf retains exact bytes and full facts")
    }

    /// This injects a proof fault AFTER a genuine checked record close. It
    /// neither substitutes a close result nor claims an observed close failure.
    @MainActor
    func testOriginalRetainedShutdownPostCloseProofFaultKeepsFirstErrorAndRefusesReclose() async throws {
        typealias Reader = GenerationLeaseAllocationAttemptV1
        guard Reader.originalEraseRetainedShutdownForTesting == nil else {
            throw FixtureFailure.activation
        }
        let injected = OriginalRetainedShutdownInjectedPostCloseProofFault()
        var boundaries: [Reader.OriginalEraseRetainedShutdownBoundaryForTesting] = []
        var retained: (reader: Reader,witness: EraseOriginalShutdownWitnessV1,
            activity: GenerationTemporalActivityHandleV1,recordURL: URL)?
        var canonicalBefore: [String: PhysicalFact]?
        var fullBefore: [String: EraseColdControlLeafFactV1]?
        var registryAfterHandleClose: Data?
        var leaseNamespaceBefore: OriginalRetainedNamespaceForTesting?
        var retirementProjection: Reader.OriginalEraseRetainedRetirementProjectionForTesting?
        var publicationBytes: Data?
        Reader.originalEraseRetainedShutdownForTesting = {
            boundary,reader,witness,activity,recordURL in
            boundaries.append(boundary)
            let state = reader.originalEraseRetainedShutdownStateForTesting
            XCTAssertFalse(state.closed)
            XCTAssertFalse(state.uncertainClose)
            XCTAssertTrue(state.recordDurable)
            XCTAssertTrue(state.registryRenamed)
            let support = recordURL.deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            switch boundary {
            case .beforePublicationProof:
                guard retained == nil else { throw FixtureFailure.activation }
                retained = (reader,witness,activity,recordURL)
                XCTAssertTrue(state.recordDescriptorPresent)
                try witness.requirePreparationReader(reader,registry: witness.registry)
                canonicalBefore = try self.protectedFacts(in: support)
                fullBefore = try self.fullPostSealFacts(in: support)
            case .beforeRecordClose:
                let held = try XCTUnwrap(retained)
                XCTAssertTrue(held.reader === reader)
                XCTAssertTrue(held.witness === witness)
                XCTAssertTrue(held.activity === activity)
                XCTAssertEqual(held.recordURL,recordURL)
                XCTAssertTrue(state.recordDescriptorPresent)
                let handle = try XCTUnwrap(reader.allocatedHandle)
                try handle.requireCheckedClosedForOriginalEraseShutdown(registry: witness.registry)
                registryAfterHandleClose = try Data(contentsOf:
                    recordURL.deletingLastPathComponent().appendingPathComponent("registry.json"))
                publicationBytes = try Data(contentsOf: recordURL)
                leaseNamespaceBefore = try self.originalRetainedNamespaceForTesting(record: recordURL)
            case .afterRecordClose:
                XCTAssertFalse(state.recordDescriptorPresent,
                    "The actual checked close returned before clearing its stored descriptor")
                let handle = try XCTUnwrap(reader.allocatedHandle)
                try handle.requireCheckedClosedForOriginalEraseShutdown(registry: witness.registry)
                let proof = try XCTUnwrap(reader.originalEraseRetainedRetirementProjectionForTesting)
                XCTAssertTrue(proof.recordCloseReturned)
                XCTAssertEqual(proof.recordBefore.links,1)
                XCTAssertEqual(proof.recordAfterUnlink.links,0)
                XCTAssertEqual(proof.recordBefore.device,proof.recordAfterUnlink.device)
                XCTAssertEqual(proof.recordBefore.inode,proof.recordAfterUnlink.inode)
                XCTAssertEqual(proof.recordBefore.mode,proof.recordAfterUnlink.mode)
                XCTAssertEqual(proof.recordBefore.user,proof.recordAfterUnlink.user)
                XCTAssertEqual(proof.recordBefore.group,proof.recordAfterUnlink.group)
                XCTAssertEqual(proof.recordBefore.size,proof.recordAfterUnlink.size)
                XCTAssertEqual(proof.recordBefore.modifiedSeconds,proof.recordAfterUnlink.modifiedSeconds)
                XCTAssertEqual(proof.recordBefore.modifiedNanoseconds,proof.recordAfterUnlink.modifiedNanoseconds)
                try self.requireAbsentWithoutFollowing(recordURL)
                var parent = stat()
                guard recordURL.deletingLastPathComponent().path.withCString({ lstat($0,&parent) }) == 0 else {
                    throw FixtureFailure.activation
                }
                XCTAssertEqual(EraseColdControlLeafFactV1(parent),proof.leaseAfterUnlink)
                try self.requireOnlyOriginalRetainedPublicationRemovedForTesting(
                    before: try XCTUnwrap(leaseNamespaceBefore),record: recordURL,projection: proof)
                retirementProjection = proof
                throw injected
            }
        }
        defer { Reader.originalEraseRetainedShutdownForTesting = nil }
        var refused: Error?
        do {
            _ = try await makeOriginalColdCut(at: .afterSessionPhaseWrite)
            XCTFail("An injected post-close proof fault cannot publish closed success")
        } catch { refused = error }
        XCTAssertTrue((refused as? OriginalRetainedShutdownInjectedPostCloseProofFault) === injected,
            "The exact injected earliest error object must survive outward shutdown settlement")
        XCTAssertEqual(boundaries,[.beforePublicationProof,.beforeRecordClose,.afterRecordClose])
        let held = try XCTUnwrap(retained)
        let state = held.reader.originalEraseRetainedShutdownStateForTesting
        XCTAssertFalse(state.closed)
        XCTAssertTrue(state.uncertainClose)
        XCTAssertFalse(state.recordDescriptorPresent,
            "An actual successful close is retained; no second numeric close is authorized")
        XCTAssertTrue(state.recordDurable)
        XCTAssertTrue(state.registryRenamed)
        let handle = try XCTUnwrap(held.reader.allocatedHandle)
        try handle.requireCheckedClosedForOriginalEraseShutdown(registry: held.witness.registry)
        let support = held.recordURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(try protectedFacts(in: support),try XCTUnwrap(canonicalBefore))
        XCTAssertEqual(try fullPostSealFacts(in: support),try XCTUnwrap(fullBefore))
        XCTAssertEqual(try Data(contentsOf: held.recordURL.deletingLastPathComponent()
            .appendingPathComponent("registry.json")),try XCTUnwrap(registryAfterHandleClose))
        let proof = try XCTUnwrap(retirementProjection)
        XCTAssertEqual(held.reader.originalEraseRetainedRetirementProjectionForTesting,proof)
        try requireOnlyOriginalRetainedPublicationRemovedForTesting(
            before: try XCTUnwrap(leaseNamespaceBefore),record: held.recordURL,projection: proof)
        XCTAssertEqual(try XCTUnwrap(publicationBytes).count,Int(proof.recordBefore.size))
        try requireAbsentWithoutFollowing(held.recordURL)
        var parent = stat()
        XCTAssertEqual(held.recordURL.deletingLastPathComponent().path.withCString({ lstat($0,&parent) }),0)
        XCTAssertEqual(EraseColdControlLeafFactV1(parent),proof.leaseAfterUnlink)
        XCTAssertThrowsError(try held.witness.requireDrained(registry: held.witness.registry)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1,.uncertainOwner)
        }
        XCTAssertThrowsError(try held.reader.closeForOriginalEraseShutdown(
            proof: held.witness,activity: held.activity)) {
            XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1,.uncertainOwner)
        }
        XCTAssertEqual(boundaries,[.beforePublicationProof,.beforeRecordClose,.afterRecordClose],
            "The refusal cannot enter another checked record close")
        XCTAssertEqual(held.reader.originalEraseRetainedShutdownStateForTesting,state)
        withExtendedLifetime(held) { }
    }
#endif
}

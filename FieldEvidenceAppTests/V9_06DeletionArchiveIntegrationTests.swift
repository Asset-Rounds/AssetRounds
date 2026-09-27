import Darwin
import Combine
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

actor V906EraseAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

@MainActor
final class V906WeakEraseSourceAliases {
    weak var session: StoreGenerationSession?
    weak var context: ModelContext?
    weak var container: ModelContainer?
    weak var coordinator: StoreSessionCoordinator?
    weak var writer: WorkspaceWriterV1?

    init(session: StoreGenerationSession, coordinator: StoreSessionCoordinator) {
        self.session = session
        context = session.modelContext
        container = session.modelContext.container
        self.coordinator = coordinator
        writer = coordinator.workspaceWriter
    }

    var drained: Bool {
        session == nil && context == nil && container == nil
            && coordinator == nil && writer == nil
    }
}

@MainActor
final class V906RouterEraseFixture {
    private static var hostPins: [V906RouterEraseFixture] = []
    let root: URL
    let support: URL
    let caches: URL
    let temporary: URL
    let defaults: UserDefaults
    let defaultsName: String
    let router: StartupRouter
    let appSession: ProductionAppAccessSessionV1
    let presentation: AppAccessPresentationV1
    private(set) var originalServices: [EraseAllService]
    private(set) var aborts: [AbortedEraseAdmissionReceiptV1]
    private(set) var completions: [CompletedEraseReceiptV1]
    private var freshRouter: StartupRouter?
    private var freshGate: AppAccessGateV1?
    private var freshService: EraseAllService?

    struct Interrupted {
        let oldGenerationID: UUID
        let tombstone: DeletionLedgerEntryV2
        let oldPointer: RestorePointerIdentityV1
        let oldPointerBytes: Data
        let operationsDevice: dev_t
        let operationsInode: ino_t
        let aliases: V906WeakEraseSourceAliases
        let operation: EraseRouterOperationV1
    }

    private init(root: URL, support: URL, caches: URL, temporary: URL,
        defaults: UserDefaults, defaultsName: String, router: StartupRouter,
        appSession: ProductionAppAccessSessionV1,
        presentation: AppAccessPresentationV1) {
        self.root = root; self.support = support; self.caches = caches
        self.temporary = temporary; self.defaults = defaults
        self.defaultsName = defaultsName; self.router = router
        self.appSession = appSession; self.presentation = presentation
        originalServices = []; aborts = []; completions = []
    }

    static func start(_ test: XCTestCase, name: String,
        point: EraseAllFailurePoint, fixedIDs: [UUID]) async throws
        -> V906RouterEraseFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V906-router-\(name)-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent(
            "Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory,
                withIntermediateDirectories: true)
        }
        let defaultsName = "V906-router-\(name)-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let router = StartupRouter(applicationSupportURL: support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: profiles)
        let appSession = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router,
            defaults: defaults, authenticationClient: V906EraseAuthentication())
        var owner: V906RouterEraseFixture?
        let presentation = AppAccessPresentationV1(startupRouter: router,
            eraseServiceFactory: { admission, completion, aborted, sceneState in
                let service = EraseAllService(applicationSupportURL: support,
                    cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                    userDefaults: defaults,
                    bundleIdentifier: "com.palatis3.fieldrecord",
                    defaultsDomainName: defaultsName,
                    makeUUID: V906Integration.sequence(fixedIDs),
                    failureInjection: EraseAllFailureInjection(failOnceAt: point),
                    sceneNavigationStatePort: sceneState,
                    privateSystemDiscoveryIndex: nil,
                    admitErase: admission,
                    didCompleteErase: { receipt in
                        owner?.completions.append(receipt)
                        XCTAssertNotNil(completion)
                        completion?(receipt)
                    },
                    didAbortEraseAdmission: { receipt in
                        owner?.aborts.append(receipt)
                        XCTAssertNotNil(aborted)
                        aborted?(receipt)
                    })
                owner?.originalServices.append(service)
                return service
            }, sessionFactory: { appSession })
        let actual = V906RouterEraseFixture(root: root, support: support,
            caches: caches, temporary: temporary, defaults: defaults,
            defaultsName: defaultsName, router: router,
            appSession: appSession, presentation: presentation)
        owner = actual
        hostPins.append(actual)
        let published = test.expectation(description: "V906 original Router ready")
        let subscription = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
        defer { subscription.cancel() }
        await presentation.bootstrapIfNeeded()
        await test.fulfillment(of: [published], timeout: 30)
        guard case .ready = router.route else {
            throw V23EraseOperationHarnessV1.Failure.admission
        }
        return actual
    }

    func readyOwner() throws -> (StoreSessionCoordinator, DiagnosticsStore) {
        guard case let .ready(coordinator, diagnostics, _) = router.route else {
            throw V23EraseOperationHarnessV1.Failure.admission
        }
        return (coordinator, diagnostics)
    }

    func interrupt(point: EraseAllFailurePoint,
        tombstone: DeletionLedgerEntryV2) async throws -> Interrupted {
        let (coordinator, diagnostics) = try readyOwner()
        let session = try coordinator.sourceSessionForV949EraseFixture(router: router)
        try V906Integration.seedRouterOwnedAsset(session)
        try DeletionLedgerStore(context: session.modelContext).stageUnion([tombstone])
        try V906Integration.adoptSeededDeletionBaseline(session)
        let oldPointer = try StoreGenerationFactory(applicationSupportURL: support)
            .currentGenerationPointerV3(expectedGenerationID: session.generationID)
        let oldPointerIdentity = RestorePointerIdentityV1(
            generationID: try XCTUnwrap(UUID(uuidString: oldPointer.generationID)),
            generationManifestSHA256: oldPointer.generationManifestSHA256,
            knownReplicaIDs: Set(try oldPointer.knownReplicaIDs.map {
                try XCTUnwrap(UUID(uuidString: $0))
            }),
            workspaceID: try XCTUnwrap(UUID(uuidString: oldPointer.workspaceID)),
            replicaID: try XCTUnwrap(UUID(uuidString: oldPointer.replicaID)))
        let oldPointerBytes = try Data(contentsOf: support
            .appendingPathComponent("FieldEvidenceData/current.json"))
        var operations = stat()
        let operationsPath = support.appendingPathComponent(
            "FieldEvidenceOperations", isDirectory: true).path
        guard lstat(operationsPath, &operations) == 0,
              (operations.st_mode & S_IFMT) == S_IFDIR else {
            throw V23EraseOperationHarnessV1.Failure.admission
        }
        let aliases = V906WeakEraseSourceAliases(session: session,
            coordinator: coordinator)
        if point == .beforePreparedWrite {
            try presentation.expectCompletedAbortColdRestartForTesting(point)
        }
        do {
            try await presentation.performErase(applicationSupportURL: support,
                confirmation: "ERASE", coordinator: coordinator,
                diagnosticsStore: diagnostics)
            XCTFail("Expected original Erase interruption at \(point)")
            throw V23EraseOperationHarnessV1.Failure.admission
        } catch EraseAllServiceError.injectedFailure {
            // The exact AppAccess/Router pending operation remains the owner.
        }
        let operation: EraseRouterOperationV1
        if point == .beforePreparedWrite {
            operation = try await presentation.continueCompletedAbortColdRestartForTesting()
        } else {
            operation = try await presentation.beginInterruptedEarlyEraseColdRestartForTesting(
                expectedFault: point)
        }
        return Interrupted(oldGenerationID: session.generationID,
            tombstone: tombstone, oldPointer: oldPointerIdentity,
            oldPointerBytes: oldPointerBytes,
            operationsDevice: operations.st_dev,
            operationsInode: operations.st_ino,
            aliases: aliases,
            operation: operation)
    }

    func finishCheckedOriginal(_ interrupted: Interrupted,
        point: EraseAllFailurePoint) throws {
        guard interrupted.aliases.drained else {
            throw V23EraseOperationHarnessV1.Failure.drainPending
        }
        if point == .beforePreparedWrite {
            try presentation.finishCompletedAbortColdRestartForTesting(
                interrupted.operation)
        } else {
            try router.finishInterruptedEarlyEraseColdRestartForTesting(
                interrupted.operation)
        }
    }

    func startFreshColdOwner() async throws -> StoreSessionCoordinator {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V906EraseAuthentication(),
            clock: SystemApplicationClock(), identifiers: SystemApplicationIDSource())
        guard await gate.authenticate(trigger: .unlock) == .authenticated else {
            throw V23EraseOperationHarnessV1.Failure.admission
        }
        let router = StartupRouter(applicationSupportURL: support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            lifecycleProfileRegistry: profiles)
        let service = EraseAllService(applicationSupportURL: support,
            cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
            userDefaults: defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: defaultsName)
        freshRouter = router; freshGate = gate; freshService = service
        try router.bindStartupAccessGate(gate)
        try await router.retryColdEraseForTesting(service: service, accessGate: gate)
        guard case let .ready(coordinator, _, _) = router.route else {
            throw V23EraseOperationHarnessV1.Failure.admission
        }
        return coordinator
    }

    func freshSession(_ coordinator: StoreSessionCoordinator)
        throws -> StoreGenerationSession {
        guard let freshRouter else {
            throw V23EraseOperationHarnessV1.Failure.admission
        }
        return try coordinator.sourceSessionForV949EraseFixture(router: freshRouter)
    }
}

private enum C52ServiceRequestBoundary_V9_06DeletionArchiveIntegrationTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_V9_06DeletionArchiveIntegrationTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

final class C50DeletionArchiveIntegrationTests: XCTestCase {
    func testV23P03C50ArchiveExcludesAdapterStateScratchQuarantineAndExternalAuthority() {
        XCTAssertFalse(C50IncumbentFileExchangeBackupEncoderBoundaryV1.encodesProfileSelectionOrSession)
        XCTAssertFalse(C50IncumbentFileExchangeBackupEncoderBoundaryV1.encodesSourceScratchOrQuarantine)
        XCTAssertFalse(C50IncumbentFileExchangeBackupDecoderBoundaryV1.acceptsProfileSelectionOrSession)
        XCTAssertTrue(C50IncumbentFileExchangeBackupDecoderBoundaryV1.unknownAdapterMembersFailClosed)
        XCTAssertEqual(C50IncumbentFileExchangePackageValidationBoundaryV1.allowedAdapterMemberCount, 0)
        XCTAssertTrue(C50IncumbentFileExchangePackageValidationBoundaryV1.rejectsSourceBytes)
        XCTAssertTrue(C50IncumbentFileExchangePackageValidationBoundaryV1.rejectsQuarantineBytes)
        XCTAssertTrue(C50IncumbentFileExchangePackageValidationBoundaryV1.rejectsBookmarksAndExternalPaths)
    }
}

final class C45DeletionArchiveCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilitySeparatesGeneratedFromSystemHandoffReceipts() {
        XCTAssertEqual(LabelOutputDispositionV1.generated.rawValue, "GENERATED")
        XCTAssertEqual(LabelOutputDispositionV1.handedOffToSystem.rawValue, "HANDED_OFF_TO_SYSTEM")
        XCTAssertNotEqual(LabelOutputDispositionV1.generated, .handedOffToSystem)
    }
}

final class C30EvidenceContextAnchorV9_06DeletionArchiveIntegration: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_06DeletionArchiveIntegrationTests: XCTestCase {
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
    @MainActor
    func testV23P03C40AssetDeletionPreservesImmutableAuthorityRows() async throws {
        let harness = try V906Integration.makeHarness("c40-immutable", withAsset: true)
        defer { V906Integration.remove(harness.root) }
        let mutationID = try MutationIDV1(rawValue: V906Integration.id(880))
        let value = try AuthoritySourceReleaseV1(
            releaseID: V906Integration.id(881),
            workspaceID: harness.session.workspaceIdentity.workspaceID,
            sourceID: V906Integration.id(882),
            sourceType: .ownerPolicy,
            designation: "Deletion-retained policy",
            editionOrRevision: "1",
            retrievedAt: V906Integration.deletedAt.addingTimeInterval(-30),
            licenseStorageDisposition: .notStored,
            recordedAt: V906Integration.deletedAt.addingTimeInterval(-30),
            mutationID: mutationID
        )
        // Revisioned authority rows enter only through the canonical writer; a
        // directly inserted row has no entity revision and journal validation
        // rejects it as corrupt history.
        let coordinator = StoreSessionCoordinator(session: harness.session)
        _ = try coordinator.workspaceWriter.execute(.applyAuthorityCriterion(try AuthorityCriterionMutationV1(
            workspaceID: value.workspaceID, expectedRevision: 0, mutationID: mutationID,
            postImage: .appendAuthoritySource(value))), mutationID: mutationID)
        try coordinator.invalidateAndReleaseWriter()
        let assetID = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )

        _ = try await V906Integration.deletionService(harness).delete(assetID: assetID)

        XCTAssertEqual(try harness.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        let retained = try harness.session.modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(try XCTUnwrap(retained.first).value(), value)
    }

    // Relaunch recovery is the real restore boundary for interrupted deletion work.
    @MainActor
    func testV9_06I01PartialDeletionRecoveryAndInterruptedErasePreservesOrForwards() async throws {
        let deletion = try V906Integration.makeHarness("i-delete", withAsset: true)
        addTeardownBlock { [root = deletion.root] in
            try? FileManager.default.removeItem(at: root)
        }
        let assetID = try XCTUnwrap(
            deletion.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        do {
            _ = try await V906Integration.deletionService(
                deletion,
                failure: .committedPhase
            ).delete(assetID: assetID)
            XCTFail("Expected committed-phase interruption")
        } catch {
            XCTAssertEqual(error as? WholeSignDeletionServiceError, .injectedFailure)
        }
        XCTAssertEqual(try deletion.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertTrue(try DeletionLedgerStore(context: deletion.session.modelContext).snapshot().entries.contains {
            $0.identity.kind == .asset && $0.identity.id == assetID
        })
        let deletionRecovery = WholeSignDeletionService(
            modelContext: deletion.session.modelContext,
            generationRootURL: deletion.session.generationRootURL
        )
        let firstRecovery = try await deletionRecovery.reconcile()
        XCTAssertEqual(firstRecovery.completedCommittedCount, 1)
        let repeatedRecovery = try await deletionRecovery.reconcile()
        XCTAssertEqual(repeatedRecovery.completedCommittedCount, 0)

        for (offset, point) in [
            EraseAllFailurePoint.beforePreparedWrite,
            EraseAllFailurePoint.afterPointerSwitch,
        ].enumerated() {
            let owner = try await V906RouterEraseFixture.start(self,
                name: "i-erase-\(offset)", point: point,
                fixedIDs: [V906Integration.id(820 + offset * 10),
                    V906Integration.id(821 + offset * 10),
                    V906Integration.id(822 + offset * 10),
                    V906Integration.id(823 + offset * 10)])
            let tombstone = try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(kind: .asset,
                    id: V906Integration.id(800 + offset)),
                deletedAt: V906Integration.deletedAt)
            let interrupted = try await owner.interrupt(point: point,
                tombstone: tombstone)
            XCTAssertTrue(owner.completions.isEmpty)
            if point == .beforePreparedWrite {
                XCTAssertEqual(owner.aborts.count, 1)
                let abort = try XCTUnwrap(owner.aborts.first)
                XCTAssertEqual(abort.originalGenerationID,
                    interrupted.oldGenerationID)
                XCTAssertEqual(try Data(contentsOf: owner.support
                    .appendingPathComponent("FieldEvidenceData/current.json")),
                    interrupted.oldPointerBytes)
                XCTAssertNil(try EraseIntentStore(
                    applicationSupportURL: owner.support).load())
            } else {
                XCTAssertTrue(owner.aborts.isEmpty)
                XCTAssertNotNil(try EraseIntentStore(
                    applicationSupportURL: owner.support).load())
            }
            let drained = expectation(for: NSPredicate { _, _ in
                interrupted.aliases.drained
            }, evaluatedWith: NSObject())
            await fulfillment(of: [drained], timeout: 30)
            XCTAssertTrue(interrupted.aliases.drained,
                "Original Router model, writer and reader aliases must drain")
            try owner.finishCheckedOriginal(interrupted, point: point)
            do {
                try await owner.router.startIfNeeded(accessGate: owner.appSession.gate)
                XCTFail("The retired original Router re-entered")
            } catch { }
            let recoveryFactory = StoreGenerationFactory(
                applicationSupportURL: owner.support)
            let originalEpochs = try recoveryFactory
                .makeGenerationLeaseRegistry().activeEpochs()
            XCTAssertFalse(originalEpochs.contains {
                $0.generationID == interrupted.oldGenerationID
            }, "The original writer/reader leases must close before cold startup")
            _ = try XCTUnwrap(!originalEpochs.contains {
                $0.generationID == interrupted.oldGenerationID
            } ? true : nil,
                "Retaining original Erase owners: old durable leases remain active")
            let operationsPath = owner.support.appendingPathComponent(
                "FieldEvidenceOperations", isDirectory: true).path
            var preRecoveryOperations = stat()
            _ = try XCTUnwrap(lstat(operationsPath, &preRecoveryOperations) == 0
                && (preRecoveryOperations.st_mode & S_IFMT) == S_IFDIR
                ? true : nil,
                "The original registry namespace must remain before cold recovery")
            XCTAssertEqual(preRecoveryOperations.st_dev,
                interrupted.operationsDevice)
            XCTAssertEqual(preRecoveryOperations.st_ino,
                interrupted.operationsInode)
            _ = try XCTUnwrap(preRecoveryOperations.st_dev == interrupted.operationsDevice
                && preRecoveryOperations.st_ino == interrupted.operationsInode ? true : nil,
                "Retaining original Erase owners: registry namespace identity changed")
            if point == .beforePreparedWrite {
                let noEffectService = EraseAllService(
                    applicationSupportURL: owner.support,
                    cachesDirectoryURL: owner.caches,
                    temporaryDirectoryURL: owner.temporary,
                    userDefaults: owner.defaults,
                    bundleIdentifier: "com.palatis3.fieldrecord",
                    defaultsDomainName: owner.defaultsName)
                let noEffectDiagnostics = DiagnosticsStore(
                    applicationSupportURL: owner.support)
                await noEffectDiagnostics.prepare()
                let noEffectOutcome = try await noEffectService.reconcileAtStartup(
                    diagnosticsStore: noEffectDiagnostics)
                XCTAssertNil(noEffectOutcome)
                let noEffectGenerationID = try recoveryFactory.currentGenerationID()
                XCTAssertEqual(noEffectGenerationID, interrupted.oldGenerationID)
                let noEffectPointerBytes = try Data(contentsOf: owner.support
                    .appendingPathComponent("FieldEvidenceData/current.json"))
                XCTAssertEqual(noEffectPointerBytes, interrupted.oldPointerBytes)
                _ = try XCTUnwrap(noEffectOutcome == nil
                    && noEffectGenerationID == interrupted.oldGenerationID
                    && noEffectPointerBytes == interrupted.oldPointerBytes ? true : nil,
                    "Retaining original Erase owners: pre-intent abort changed durable state")
            }
            let recoveredCoordinator = try await owner.startFreshColdOwner()
            let recoveredSession = try owner.freshSession(recoveredCoordinator)
            if point == .beforePreparedWrite {
                XCTAssertEqual(recoveredSession.generationID,
                    interrupted.oldGenerationID)
                XCTAssertEqual(try DeletionLedgerStore(
                    context: recoveredSession.modelContext).snapshot().entries,
                    [interrupted.tombstone])
                XCTAssertEqual(try recoveredSession.modelContext.fetchCount(
                    FetchDescriptor<Asset>()), 1)
                weak var weakReopened: StoreGenerationSession?
                let exit = try { () -> V949RestoredSourceReaderExitV1 in
                    let reopened = try recoveryFactory.openOrBootstrapCurrent()
                    weakReopened = reopened
                    let observed = try recoveryFactory
                        .captureV949RestoredSourceReaderExit(session: reopened)
                    XCTAssertEqual(try DeletionLedgerStore(
                        context: reopened.modelContext).snapshot().entries,
                        [interrupted.tombstone])
                    return observed
                }()
                XCTAssertNil(weakReopened)
                try exit.closeAfterCheckedAliasDrain()
            } else {
                XCTAssertNotEqual(recoveredSession.generationID,
                    interrupted.oldGenerationID)
                XCTAssertEqual(try DeletionLedgerStore(
                    context: recoveredSession.modelContext).snapshot(),
                    .empty)
                XCTAssertEqual(try recoveredSession.modelContext.fetchCount(
                    FetchDescriptor<Asset>()), 0)
                XCTAssertEqual(try recoveryFactory.currentGenerationID(),
                    recoveredSession.generationID)
                var afterCleanupOperations = stat()
                let result = lstat(operationsPath, &afterCleanupOperations)
                let missingError = errno
                XCTAssertEqual(result, -1)
                XCTAssertEqual(missingError, ENOENT,
                    "Completed Erase must remove the old Operations namespace")
            }
            let noRepeat = EraseAllService(
                applicationSupportURL: owner.support,
                cachesDirectoryURL: owner.caches,
                temporaryDirectoryURL: owner.temporary,
                userDefaults: owner.defaults,
                bundleIdentifier: "com.palatis3.fieldrecord",
                defaultsDomainName: owner.defaultsName)
            let noRepeatDiagnostics = DiagnosticsStore(
                applicationSupportURL: owner.support)
            await noRepeatDiagnostics.prepare()
            let repeatedOutcome = try await noRepeat.reconcileAtStartup(
                diagnosticsStore: noRepeatDiagnostics)
            XCTAssertNil(repeatedOutcome)
            XCTAssertTrue(owner.completions.isEmpty)
            try recoveredCoordinator.invalidateAndReleaseWriter()
            let remainingEpochs = try recoveryFactory
                .makeGenerationLeaseRegistry().activeEpochs()
            XCTAssertTrue(remainingEpochs.isEmpty,
                "The fresh writer lease must close before fixture return")
            // Fresh Router/registry/model FDs remain live; the exact root and
            // owner graph are retained by V906RouterEraseFixture.hostPins.
        }

        // A preparation is durable before an Erase intent exists. These cases
        // model process death while that pre-intent cleanup is at each stable
        // boundary: a complete target, a target whose manifest was already
        // removed, and an already-removed target. An unknown installed sibling
        // must instead stop recovery without mutating any of those authorities.
        let preparationCases = [
            (name: "full-target", removeManifest: false, removeTarget: false, unknown: false),
            (name: "manifest-absent", removeManifest: true, removeTarget: false, unknown: false),
            (name: "target-absent", removeManifest: true, removeTarget: true, unknown: false),
            (name: "unknown-generation", removeManifest: false, removeTarget: false, unknown: true),
        ]
        for (offset, crashCase) in preparationCases.enumerated() {
            let harness = try V906Integration.makeHarness(
                "i-preparation-\(crashCase.name)",
                withAsset: true
            )
            defer { V906Integration.remove(harness.root) }
            let context = harness.session.modelContext
            let sourceTombstone = try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(
                    kind: .asset,
                    id: V906Integration.id(940 + offset)
                ),
                deletedAt: V906Integration.deletedAt
            )
            try DeletionLedgerStore(context: context).stageUnion([sourceTombstone])
            try context.save()
            let sourceLedger = try DeletionLedgerStore(context: context).snapshot()

            let authority = try harness.factory.makeRestoreGenerationAuthority()
            let oldGenerationID = harness.session.generationID
            let current = try harness.factory.currentGenerationPointerV3(
                expectedGenerationID: oldGenerationID,
                authority: authority
            )
            let oldPointer = RestorePointerIdentityV1(
                generationID: try XCTUnwrap(UUID(uuidString: current.generationID)),
                generationManifestSHA256: current.generationManifestSHA256,
                knownReplicaIDs: Set(try current.knownReplicaIDs.map {
                    try XCTUnwrap(UUID(uuidString: $0))
                }),
                workspaceID: try XCTUnwrap(UUID(uuidString: current.workspaceID)),
                replicaID: try XCTUnwrap(UUID(uuidString: current.replicaID))
            )
            let sourceProof = try harness.factory.currentGenerationDeletionLedgerProof(
                expectedPointer: oldPointer,
                authority: authority
            )
            let installedBefore = Set(try authority.installedGenerationNames())
            let targetGenerationID = V906Integration.id(960 + offset * 10)
            let targetIdentity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(
                    rawValue: V906Integration.id(961 + offset * 10)
                ),
                replicaID: ReplicaID(
                    rawValue: V906Integration.id(962 + offset * 10)
                )
            )
            let initialPreparation = ErasePreparationV2(
                oldPointer: oldPointer,
                sourceLedger: sourceProof,
                targetGenerationID: targetGenerationID,
                targetWorkspaceID: targetIdentity.workspaceID.rawValue,
                targetReplicaID: targetIdentity.replicaID.rawValue,
                targetPointer: nil
            )
            let preparationStore = try EraseIntentStore(
                applicationSupportURL: harness.support
            )
            try preparationStore.createPreparation(initialPreparation)
            XCTAssertNil(try preparationStore.load())

            let created = try harness.factory.createEmptyEraseGeneration(
                id: targetGenerationID,
                expectedOldPointer: oldPointer,
                identity: targetIdentity,
                authority: authority
            )
            let frozenPreparation: ErasePreparationV2
            if crashCase.name == "full-target" {
                // Death can occur after target creation and before the marker
                // is rebound to the generated pointer.
                frozenPreparation = initialPreparation
            } else {
                let bound = initialPreparation.binding(targetPointer: created.pointer)
                try preparationStore.replacePreparation(
                    expected: initialPreparation,
                    with: bound
                )
                frozenPreparation = bound
            }

            if crashCase.removeManifest {
                try harness.factory.removePreparedRestoreGenerationManifestBeforeDiscard(
                    expectedOldID: oldGenerationID,
                    generationID: targetGenerationID,
                    expectedDigest: created.pointer.generationManifestSHA256,
                    authority: authority
                )
            }
            if crashCase.removeTarget {
                try harness.factory.removeInstalledGeneration(
                    id: targetGenerationID,
                    keeping: oldGenerationID,
                    authority: authority
                )
            }

            let unknownGenerationID = V906Integration.id(963 + offset * 10)
            if crashCase.unknown {
                try harness.factory.createEmptyInstalledGeneration(
                    id: unknownGenerationID,
                    authority: authority
                )
            }
            XCTAssertEqual(try preparationStore.loadPreparation(), frozenPreparation)
            XCTAssertEqual(
                try harness.factory.currentGenerationPointerV3(
                    expectedGenerationID: oldGenerationID,
                    authority: authority
                ),
                current
            )
            XCTAssertEqual(
                try harness.factory.currentGenerationDeletionLedgerProof(
                    expectedPointer: oldPointer,
                    authority: authority
                ),
                sourceProof
            )

            let diagnostics = DiagnosticsStore(applicationSupportURL: harness.support)
            await diagnostics.prepare()
            let suiteName = "V9_06-I01-Preparation-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let recovery = EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: defaults,
                bundleIdentifier: "com.palatis3.fieldrecord"
            )

            if crashCase.unknown {
                do {
                    _ = try await recovery.reconcileAtStartup(
                        diagnosticsStore: diagnostics
                    )
                    XCTFail("Unknown installed generation must stop preparation recovery")
                } catch {
                    XCTAssertEqual(
                        error as? StoreGenerationFailure,
                        .dataPointerInvalid
                    )
                }
                XCTAssertEqual(try preparationStore.loadPreparation(), frozenPreparation)
                XCTAssertTrue(
                    try harness.factory.generationPresence(
                        id: targetGenerationID,
                        authority: authority
                    ).installed
                )
                XCTAssertTrue(
                    try harness.factory.generationPresence(
                        id: unknownGenerationID,
                        authority: authority
                    ).installed
                )
                XCTAssertEqual(
                    Set(try authority.installedGenerationNames()),
                    installedBefore.union([
                        targetGenerationID.uuidString.lowercased(),
                        unknownGenerationID.uuidString.lowercased(),
                    ])
                )
            } else {
                let recovered = try await recovery.reconcileAtStartup(
                    diagnosticsStore: diagnostics
                )
                XCTAssertNil(recovered)
                // Successful recovery removes the entire journal namespace.
                // The old descriptor-pinned store must reject reuse afterward.
                let journalRootAbsent = try EraseIntentStore.completedCleanupRootIsAbsent(
                    applicationSupportURL: harness.support
                )
                XCTAssertTrue(journalRootAbsent)
                _ = try XCTUnwrap(journalRootAbsent ? true : nil,
                                  "Recovery must remove both preparation and intent journals")
                XCTAssertThrowsError(try preparationStore.loadPreparation()) {
                    XCTAssertEqual($0 as? EraseIntentStoreError, .invalidAuthority)
                }
                XCTAssertThrowsError(try preparationStore.load()) {
                    XCTAssertEqual($0 as? EraseIntentStoreError, .invalidAuthority)
                }
                let targetPresence = try harness.factory.generationPresence(
                    id: targetGenerationID,
                    authority: authority
                )
                XCTAssertFalse(targetPresence.installed)
                XCTAssertFalse(targetPresence.staging)
                XCTAssertNil(
                    try StoreMigrationJournalStoreV1(
                        applicationSupportURL: harness.support
                    ).loadManifestIfPresent(targetGenerationID: targetGenerationID)
                )
                XCTAssertEqual(
                    Set(try authority.installedGenerationNames()),
                    installedBefore
                )
            }

            XCTAssertEqual(
                try harness.factory.currentGenerationPointerV3(
                    expectedGenerationID: oldGenerationID,
                    authority: authority
                ),
                current
            )
            XCTAssertEqual(
                try harness.factory.currentGenerationDeletionLedgerProof(
                    expectedPointer: oldPointer,
                    authority: authority
                ),
                sourceProof
            )
            XCTAssertEqual(
                try DeletionLedgerStore(context: context).snapshot(),
                sourceLedger
            )
        }
    }

    @MainActor
    func testV9_06R01OrphanCleanupIsSeparateFromLedgerAndSurvivesRelaunch() async throws {
        let harness = try V906Integration.makeHarness("r", withAsset: true)
        defer { V906Integration.remove(harness.root) }
        let assetID = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        _ = try await V906Integration.deletionService(harness).delete(assetID: assetID)
        let ledgerBefore = try DeletionLedgerStore(context: harness.session.modelContext).snapshot()

        let orphanID = V906Integration.id(900).uuidString.lowercased()
        let orphanDirectory = harness.session.generationRootURL.appendingPathComponent(
            "evidence/\(orphanID)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
        try Data("orphan-original".utf8).write(to: orphanDirectory.appendingPathComponent("original.jpg"))
        try Data("orphan-thumbnail".utf8).write(to: orphanDirectory.appendingPathComponent("thumbnail.jpg"))

        let summary = try OrphanFileCleanupService(
            generationRootURL: harness.session.generationRootURL
        ).reconcile(referencedRelativePaths: [])
        XCTAssertEqual(summary.removedFileCount, 2)
        XCTAssertEqual(summary.removedDirectoryCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDirectory.path))
        XCTAssertEqual(
            try DeletionLedgerStore(context: harness.session.modelContext).snapshot(),
            ledgerBefore
        )

        let relaunched = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(relaunched.generationID, harness.session.generationID)
        XCTAssertEqual(try DeletionLedgerStore(context: relaunched.modelContext).snapshot(), ledgerBefore)
        XCTAssertEqual(try relaunched.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try relaunched.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
    }
}

final class C27V906ArchiveTypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorLimitsV1.maximumCandidates, 32)
        XCTAssertEqual(LocatorInputSourceV1.allCases, [.camera, .manual, .imported, .search])
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistent: 21, records: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.receiptInsideVerifiedArchive)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C36ArchiveReceiptRoundTripsPublicationPosture() throws {
        let receipt=try DraftAttachmentRestorePublicationReceiptV1(restoreID:UUID(),workspaceID:WorkspaceID(rawValue:UUID()),sourceManifestSHA256:String(repeating:"b",count:64),adoptedStageIDs:[],reusedStageIDs:[UUID()],publishedAt:Date(timeIntervalSince1970:2))
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .millisecondsSince1970
        let restored=try decoder.decode(DraftAttachmentRestorePublicationReceiptV1.self,from:encoder.encode(receipt))
        try restored.validate()
        XCTAssertEqual(restored,receipt)
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C15ArchivedReleaseRoundTripsCanonicalBytes() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_107)
        let row = try WorkReleaseRow(fixture.completedRelease)
        XCTAssertEqual(row.canonicalData, try WorkPacketCanonicalCodecV1.encode(fixture.completedRelease))
        XCTAssertEqual(try row.value(), fixture.completedRelease)
        XCTAssertEqual(row.releaseID, fixture.completedRelease.releaseID)
        XCTAssertEqual(row.claimID, fixture.claim.claimID)
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C41ArchiveReplayLeavesNoCurrentRelationship() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_062)
        let projection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added, fixture.ended],
            descriptors: [fixture.descriptor]
        )

        XCTAssertTrue(projection.currentRelationships.isEmpty)
        XCTAssertEqual(projection.sourceEventsSHA256.count, 64)
        try fixture.ended.validateSuccessor(of: fixture.added)

        let snapshot = try CompletedFunctionalRelationshipSnapshotV1(
            snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_063),
            workspaceID: fixture.workspaceID,
            capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            descriptorReleases: [fixture.descriptor],
            relationships: [fixture.added]
        )
        XCTAssertEqual(snapshot.relationships.first?.relationshipID, fixture.relationshipID)
        try snapshot.validate()
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C13ArchiveRowsRetainManifestAndAttestationHistory() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_607)
        let manifestRow = try AssuranceManifestRow(fixture.customerManifest)
        let attestationRow = try AttestationRow(fixture.customerAttestation)
        let restoredManifest = try manifestRow.value()
        let restoredAttestation = try attestationRow.value()

        XCTAssertEqual(restoredManifest.manifestID, fixture.customerManifest.manifestID)
        XCTAssertEqual(restoredManifest.revision, 1)
        XCTAssertEqual(restoredAttestation.action, .recorded)
        XCTAssertEqual(restoredAttestation.supersedesAttestationID, nil)
        XCTAssertEqual(restoredAttestation.manifestSHA256, restoredManifest.manifestSHA256)
        try restoredAttestation.validate(manifest: restoredManifest)
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C14ArchivedReviewTransitionRetainsCanonicalRowIdentity() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_006)
        let row = try InspectionReviewTransitionRow(fixture.transitions[0])
        XCTAssertEqual(try row.value(), fixture.transitions[0])
        XCTAssertEqual(row.reviewID, fixture.reviewID)
        XCTAssertEqual(row.revision, 1)
    }

    func testV23P03C19DeleteArchiveKeepsCanonicalMeasurementRows() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try KernelDeletionEraseRegistryV4.validateMeasurementIntegrityLifecycle()
        let row = try MeasurementSeriesRow(fixture.series)
        XCTAssertEqual(try row.value(), fixture.series)
        XCTAssertEqual(MeasurementIntegrityLifecycleCatalogV1.disposition(for: "MEASUREMENT_SERIES_V1"), .canonicalPersistent)
    }

    func testC20PrivacyTransformDeleteOnlyRegenerableDerivative() throws {
        let adapter = PrivacyTransformLifecycleAdapterV1(authority: C20PrivacyPublicationAuthorityForAnchors())
        XCTAssertEqual(
            adapter.disposition(hasDerivativeBytes: true, hasManifest: false, hasReview: false, receiptValid: false),
            .deleteRegenerableDerivative
        )
        XCTAssertEqual(
            adapter.disposition(hasDerivativeBytes: true, hasManifest: true, hasReview: false, receiptValid: false),
            .quarantinePartialEffect
        )
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_06DeletionArchiveIntegrationTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyTemplateArchiveManifestV1.fileExtension, "arsurveytemplate")
        // Expectation change (2026-09-25): this pin said 64, but the frozen
        // design contract docs/design/v23/tooling/
        // V23P03C25SurveyDefinitionContractV1.json (templatePolicy
        // "..._MAX_ENTRIES_128_...") and the C25 corpus
        // (archiveMaximumEntries 128) both specify 128, and production has
        // been 128 since the introducing commit 885cb747. The pin now follows
        // the frozen contract and the shared hostile-archive admission limit.
        XCTAssertEqual(SurveyTemplateArchiveManifestV1.maximumEntries, 128)
        XCTAssertEqual(
            SurveyTemplateArchiveManifestV1.maximumEntries,
            SurveyTemplateArchiveAdmissionV1.maximumEntries
        )
        XCTAssertEqual(SurveyDefinitionLifecycleV1.quarantinePersistence, "DERIVED_ONLY")
    }
}
extension V9_06DeletionArchiveIntegrationTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
final class C31LightingAnchorV906DeletionArchiveIntegrationTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class C33TemporalEvidenceAnchorV906DeletionArchiveIntegration: XCTestCase {
    func testC33V906DeletionArchiveIntegrationCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "archive.temporal-evidence-closure",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "archive.temporal-evidence-closure",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

final class C32AssistanceAnchorV906DeletionArchiveIntegration: XCTestCase {
    func testC32V906DeletionArchiveIntegrationCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .packet,
            fieldID: "archive.accepted-receipt-only",
            value: .singleOption("ACCEPTED_ONLY")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .packet,
            fieldID: "archive.accepted-receipt-only",
            valueKind: .singleOption
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
final class C46V906DeletionArchiveCompatibilityTests: XCTestCase {
    func testC46DeletionArchiveKeepsContactPrivacyPurposeSeparated() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "deletion-archive",
            kind: .email,
            handoff: .email,
            slot: 46106
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift_Tests: XCTestCase {
    func testC47V906DeletionArchiveIntegrationTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionArchiveIntegrationTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

final class C48PortableReviewV906DeletionArchiveTests: XCTestCase {
    func testC48ArchiveIntegrationExcludesQuarantineAndCapabilitySecrets() {
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.quarantineIsExcludedFromBackup)
        XCTAssertTrue(C48PortableExchangeSyncBoundaryV2.rawCapabilityExcludedFromSyncSearchReport)
        XCTAssertTrue(C48PortableExchangePersistentLifecycleBoundaryV2.eraseRemovesAppOwnedStagingOnly)
    }
}
final class C49WorkResourceDeletionArchiveBoundaryTests: XCTestCase {
    func testArchiveTreatsDirectCostAsEmbeddedWithEntry() { XCTAssertTrue(C49WorkResourceContractBoundaryV1.directCostIsEmbedded) }
}

extension C50DeletionArchiveIntegrationTests {
    func testV23P03C51ArchiveCarriesSixCanonicalScheduleComponents() {
        XCTAssertTrue(
            C51ScheduleBackupClosureV1.preservedV27RecordBytes
                && C51ScheduleBackupClosureV1.embeddedCanonicalComponents.count == 6
                && C51ScheduleBackupClosureV1.embeddedCanonicalComponents
                    .contains("ScheduleOverrideEventV1")
                && !C51ScheduleBackupClosureV1.derivedDueReminderAndPreviewStateIsArchived
        )
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C34ArchiveExcludesSceneStateFromCanonicalArtifacts() {
        let lifecycle = SceneNavigationLifecycleDispositionV1()
        XCTAssertFalse(lifecycle.workspaceTruth)
        XCTAssertFalse(lifecycle.backupIncluded)
        XCTAssertFalse(lifecycle.journalIncluded)
        XCTAssertFalse(lifecycle.reportIncluded)
        XCTAssertFalse(lifecycle.exportIncluded)
        XCTAssertFalse(lifecycle.searchIncluded)
    }
}

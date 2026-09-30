import Darwin
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// These four faults occur after genuine source retirement. The original
/// Router/operation and their inert file owners remain retained for the host
/// lifetime. This is a controlled test-host restart, not an OS-crash claim.
final class V23LateEraseAbandonmentTests: XCTestCase {
    @MainActor
    func testAfterCleanupCanAbandonAndColdReplay() async throws {
        try await exercise(.afterCleanup, expectedIntentPhase: .sessionActivated)
    }

    @MainActor
    func testBeforeCleanupPhaseWriteCanAbandonAndColdReplay() async throws {
        try await exercise(.beforeCleanupPhaseWrite, expectedIntentPhase: .sessionActivated)
    }

    @MainActor
    func testAfterCleanupPhaseWriteCanAbandonAndColdReplay() async throws {
        try await exercise(.afterCleanupPhaseWrite, expectedIntentPhase: .cleanupComplete)
    }

    @MainActor
    func testBeforeJournalRemovalCanAbandonAndColdReplay() async throws {
        try await exercise(.beforeJournalRemoval, expectedIntentPhase: .cleanupComplete)
    }

    @MainActor
    private func exercise(_ point: EraseAllFailurePoint,
        expectedIntentPhase: EraseIntentPhaseV1) async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("v23-late-erase-abandon-\(UUID().uuidString)", isDirectory: true)
        let support = base.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let caches = base.appendingPathComponent("Caches", isDirectory: true)
        let temporary = base.appendingPathComponent("Temporary", isDirectory: true)
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let defaultsName = "V23LateEraseAbandonment-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
        let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
        let gate = makeGate()
        let unlocked = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlocked, .authenticated)
        let original = StartupRouter(applicationSupportURL: support,
            entitlementRuntime: isolatedRuntime(), lifecycleProfileRegistry: registry)
        try original.bindStartupAccessGate(gate)
        let owner = V23LateEraseRetainedOwner(base: base, original: original, originalGate: gate)
        try await original.startIfNeeded(accessGate: gate)
        let oldID: UUID
        let oldWriterID: UUID
        let oldGeneration: URL
        let expectedNewID = UUID()
        do {
            guard case let .ready(initial, _, _) = original.route else {
                return XCTFail("Real authenticated original startup must be ready")
            }
            oldID = initial.generationID
            oldWriterID = try initial.workspaceWriter.currentRevision().writerInstanceID
            let assetID = try await createAsset(in: initial, profile: profile)
            XCTAssertEqual(try initial.modelContext.fetch(FetchDescriptor<Asset>()).map(\.id), [assetID])
            XCTAssertGreaterThan(try initial.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
            oldGeneration = StoreGenerationFactory(applicationSupportURL: support)
                .installedGenerationURL(id: oldID)
            XCTAssertTrue(FileManager.default.fileExists(atPath: oldGeneration.path))
            owner.sourceCoordinator = initial
            owner.sourceContext = initial.modelContext
            owner.sourceWriter = initial.workspaceWriter

            // The helper frame and this scope end before retirement. The
            // actual Router and operation remain strongly owned by `owner`.
            try await startOriginalErase(owner: owner, coordinator: initial,
                support: support, caches: caches, temporary: temporary,
                defaults: defaults, defaultsName: defaultsName,
                newID: expectedNewID, point: point, registry: registry)
        }
        let drained = expectation(for: NSPredicate { _, _ in owner.modelAliasesAreDrained },
            evaluatedWith: NSObject())
        await fulfillment(of: [drained], timeout: 30)
        XCTAssertTrue(owner.modelAliasesAreDrained)
        guard owner.modelAliasesAreDrained else {
            throw AppAccessContractFailureV1.staleAttempt
        }

        let operation = try XCTUnwrap(owner.operation)
        do {
            let complete = try await operation.advanceCleanup()
            XCTFail("Actual injected late fault must throw, returned \(complete)")
            return
        } catch EraseAllServiceError.injectedFailure {
            // The actual cleanup advanced to this precise injected boundary.
        }
        XCTAssertEqual(owner.originalCompletionCount, 0)
        XCTAssertEqual(owner.coldCompletionCount, 0)
        XCTAssertThrowsError(try operation.completedRetirement())
        guard case let .eraseCleanupPending(.retiring(held)) = original.route else {
            return XCTFail("Original Router must still own the faulting operation")
        }
        XCTAssertTrue(held === operation)
        let intent = try XCTUnwrap(try EraseIntentStore(applicationSupportURL: support).load())
        XCTAssertEqual(intent.phase, expectedIntentPhase)
        XCTAssertEqual(intent.newGenerationID, expectedNewID)
        XCTAssertEqual(intent.generationIDsToDelete, [oldID])
        let dataRoot = support.appendingPathComponent("FieldEvidenceData", isDirectory: true)
        let eraseRoot = support.appendingPathComponent("FieldEvidenceErase", isDirectory: true)
        let before = V23LateEraseDiskState(data: try captureTree(dataRoot),
            erase: try captureTree(eraseRoot))
        let beforeDefaults = defaults.persistentDomain(forName: defaultsName) ?? [:]
        XCTAssertFalse(before.erase.isEmpty, "Interrupted durable Erase intent must remain")
        XCTAssertNotNil(before.erase["erase.json"])
        if point == .beforeJournalRemoval {
            XCTAssertNil(before.erase["preparation.json"])
        } else {
            XCTAssertNotNil(before.erase["preparation.json"])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldGeneration.path),
            "The late fault is after old-generation removal")
        try requireNamedOldOperationsAbsent(in: support)
        // The original EX still owns this interruption. Opening a new factory
        // here would construct a second lease Registry and could recreate the
        // named Operations namespace. Decode the captured canonical pointer
        // bytes instead, without constructing any new filesystem owner.
        guard case let .file(currentPointerBytes) = before.data["current.json"] else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let currentPointer = try CurrentGenerationPointerV3.decodeCanonical(from: currentPointerBytes)
        XCTAssertEqual(currentPointer.generationID, expectedNewID.uuidString.lowercased())

        if point == .afterCleanup {
            // A wrong fault must not poison the real original or mutate disk.
            XCTAssertThrowsError(try original.abandonInterruptedLateEraseForColdRestartForTesting(
                operation, expectedFault: .beforeJournalRemoval))
            XCTAssertEqual(try captureTree(dataRoot), before.data)
            XCTAssertEqual(try captureTree(eraseRoot), before.erase)
            XCTAssertEqual(owner.originalCompletionCount, 0)
        }
        try original.abandonInterruptedLateEraseForColdRestartForTesting(operation, expectedFault: point)
        XCTAssertEqual(try captureTree(dataRoot), before.data,
            "Abandonment must leave pointer, retired controls and all generation bytes unchanged")
        XCTAssertEqual(try captureTree(eraseRoot), before.erase,
            "Abandonment must leave the actual intent/preparation bytes unchanged")
        XCTAssertTrue(NSDictionary(dictionary: beforeDefaults).isEqual(
            to: defaults.persistentDomain(forName: defaultsName) ?? [:]))
        XCTAssertEqual(try XCTUnwrap(EraseIntentStore(applicationSupportURL: support).load()), intent)
        try requireNamedOldOperationsAbsent(in: support)
        XCTAssertEqual(owner.originalCompletionCount, 0)
        XCTAssertEqual(owner.coldCompletionCount, 0)

        // All old effects, including a second cleanup/receipt and a fresh
        // startup attempt through the old Router, are permanently refused.
        XCTAssertThrowsError(try operation.completedRetirement())
        XCTAssertThrowsError(try original.eraseRetirementOperation(for: try XCTUnwrap(owner.ticket)))
        do {
            _ = try await operation.advanceCleanup()
            XCTFail("Abandoned operation must not advance or complete")
        } catch { }
        do {
            try await original.retryColdEraseForTesting(service: EraseAllService(
                applicationSupportURL: support, cachesDirectoryURL: caches,
                temporaryDirectoryURL: temporary, userDefaults: defaults), accessGate: gate)
            XCTFail("Abandoned original Router must not run cold replay")
        } catch { }
        do {
            try await original.startIfNeeded(accessGate: gate)
            XCTFail("Abandoned original Router must refuse another startup")
        } catch { }
        XCTAssertEqual(try captureTree(dataRoot), before.data)
        XCTAssertEqual(try captureTree(eraseRoot), before.erase)

        let first = try await coldStartup(owner: owner, support: support, caches: caches,
            temporary: temporary, defaults: defaults, defaultsName: defaultsName,
            registry: registry)
        XCTAssertEqual(first.generationID, expectedNewID)
        XCTAssertNotEqual(first.writerID, oldWriterID)
        XCTAssertEqual(first.assetCount, 0)
        XCTAssertEqual(first.canonicalRowCount, 0)
        XCTAssertEqual(first.mutationReceiptCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldGeneration.path))
        XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: support))
        XCTAssertTrue(try StoreGenerationFactory(applicationSupportURL: support).retiredGenerationIDs().isEmpty)
        XCTAssertTrue(try allNamedLeaseIDs(in: support).isEmpty)
        let pointerURL = dataRoot.appendingPathComponent("current.json")
        let retiredURL = dataRoot.appendingPathComponent("retired.json")
        let pointerAfterFirst = try Data(contentsOf: pointerURL)
        let retiredAfterFirst = try Data(contentsOf: retiredURL)

        let second = try await coldStartup(owner: owner, support: support, caches: caches,
            temporary: temporary, defaults: defaults, defaultsName: defaultsName,
            registry: registry)
        XCTAssertEqual(second.generationID, first.generationID)
        XCTAssertNotEqual(second.writerID, first.writerID)
        XCTAssertEqual(second.assetCount, 0)
        XCTAssertEqual(second.canonicalRowCount, 0)
        XCTAssertEqual(second.mutationReceiptCount, 0)
        XCTAssertEqual(try Data(contentsOf: pointerURL), pointerAfterFirst)
        XCTAssertEqual(try Data(contentsOf: retiredURL), retiredAfterFirst)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldGeneration.path))
        XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: support))
        XCTAssertTrue(try StoreGenerationFactory(applicationSupportURL: support).retiredGenerationIDs().isEmpty)
        XCTAssertTrue(try allNamedLeaseIDs(in: support).isEmpty)
        XCTAssertEqual(owner.originalCompletionCount, 0)
        XCTAssertEqual(owner.coldCompletionCount, 0)
    }

    @MainActor
    private func startOriginalErase(owner: V23LateEraseRetainedOwner,
        coordinator: StoreSessionCoordinator, support: URL, caches: URL,
        temporary: URL, defaults: UserDefaults, defaultsName: String,
        newID: UUID, point: EraseAllFailurePoint,
        registry: WorkspacePackageLifecycleProfileRegistryV1) async throws {
        let router = owner.original
        let gate = owner.originalGate
        let ticket = try await router.beginEraseOperation(coordinator: coordinator, accessGate: gate)
        let operation = try router.eraseRetirementOperation(for: ticket)
        owner.ticket = ticket
        owner.operation = operation
        var identifiers = [newID, UUID(), UUID(), UUID()]
        var reservation: AppAccessGateV1.EraseAdoptionToken?
        var activationFailure: Error?
        let service = try router.configureEraseService(EraseAllService(
            applicationSupportURL: support, cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary, userDefaults: defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: defaultsName,
            makeUUID: { identifiers.removeFirst() },
            failureInjection: EraseAllFailureInjection(failOnceAt: point),
            privateSystemDiscoveryIndex: nil,
            admitErase: { subject in
                if let authorization = try await router.eraseAdmissionAuthorization(ticket, subject: subject) {
                    let actual = try await gate.reserveEraseAdoption(subject: subject,
                        authorization: authorization)
                    try router.recordEraseReservation(ticket, reservation: actual)
                    reservation = actual
                    return actual
                }
                guard let reservation, reservation.subject == subject else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
                return reservation
            },
            didCompleteErase: { _ in owner.originalCompletionCount += 1 }
        ), operation: operation)
        let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: registry)
        let outcome = try await service.erase(confirmation: EraseAllService.requiredConfirmation,
            coordinator: coordinator, diagnosticsStore: DiagnosticsStore(applicationSupportURL: support),
            operation: operation,
            activate: { [weak coordinator] session in
                do {
                    let actual = try XCTUnwrap(coordinator)
                    try router.activateErasePreparationSession(session, coordinator: actual,
                        operation: operation)
                    owner.targetContext = actual.modelContext
                    owner.targetWriter = actual.workspaceWriter
                } catch { activationFailure = error }
            }, lifecycleDependencies: dependencies)
        if let activationFailure { throw activationFailure }
        XCTAssertTrue(outcome.operation === operation)
        XCTAssertEqual(try XCTUnwrap(reservation).subject.newGenerationID, newID)
        XCTAssertEqual(owner.originalCompletionCount, 0)
    }

    @MainActor
    private func coldStartup(owner: V23LateEraseRetainedOwner, support: URL,
        caches: URL, temporary: URL, defaults: UserDefaults, defaultsName: String,
        registry: WorkspacePackageLifecycleProfileRegistryV1) async throws -> V23LateEraseObservation {
        let gate = makeGate()
        let unlocked = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlocked, .authenticated)
        let router = StartupRouter(applicationSupportURL: support,
            entitlementRuntime: isolatedRuntime(), lifecycleProfileRegistry: registry)
        let service = EraseAllService(applicationSupportURL: support,
            cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
            userDefaults: defaults, bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: defaultsName, privateSystemDiscoveryIndex: nil,
            didCompleteErase: { _ in owner.coldCompletionCount += 1 })
        try await router.retryColdEraseForTesting(service: service, accessGate: gate)
        guard case let .ready(coordinator, _, _) = router.route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        let observation = V23LateEraseObservation(generationID: coordinator.generationID,
            writerID: try coordinator.workspaceWriter.currentRevision().writerInstanceID,
            assetCount: try coordinator.modelContext.fetchCount(FetchDescriptor<Asset>()),
            canonicalRowCount: try canonicalRows(coordinator.modelContext),
            mutationReceiptCount: try coordinator.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()))
        try coordinator.invalidateAndReleaseWriter()
        router.failClosedPDFRecovery()
        XCTAssertFalse(router.hasPendingWriterCleanup)
        owner.coldRouters.append(router)
        return observation
    }

    @MainActor
    private func createAsset(in coordinator: StoreSessionCoordinator,
        profile: WorkspacePackageLifecycleProfileV1) async throws -> UUID {
        let siteID = UUID(), assetID = UUID()
        let mutation = try MutationIDV1(rawValue: UUID())
        _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID, newSite: .init(id: siteID, label: "Late Erase Site",
                address: nil, timeZoneID: "America/New_York"),
            assetID: assetID, assetLabel: "Late Erase Asset",
            packID: profile.package.packID,
            packSchemaVersion: profile.package.schemaVersion,
            packContentVersion: profile.package.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_040_000),
            initialPlacementMutationID: mutation,
            initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        )), mutationID: mutation)
        try await coordinator.awaitSearchIndexLifecycle()
        return assetID
    }

    private func canonicalRows(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Site>())
            + context.fetchCount(FetchDescriptor<Asset>())
            + context.fetchCount(FetchDescriptor<LocationNodeRow>())
            + context.fetchCount(FetchDescriptor<WorkflowRecord>())
            + context.fetchCount(FetchDescriptor<EvidenceFile>())
            + context.fetchCount(FetchDescriptor<Issue>())
            + context.fetchCount(FetchDescriptor<Packet>())
            + context.fetchCount(FetchDescriptor<Report>())
            + context.fetchCount(FetchDescriptor<DeletionLedgerRow>())
    }

    @MainActor
    private func makeGate() -> AppAccessGateV1 {
        AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23LateEraseAuthentication(),
            clock: V23LateEraseClock(), identifiers: SystemApplicationIDSource())
    }

    @MainActor
    private func isolatedRuntime() -> StoreKitEntitlementRuntimeV1 {
        StoreKitEntitlementRuntimeV1(initialEvents: { [] },
            transactionUpdates: { AsyncStream { $0.finish() } },
            statusUpdates: { AsyncStream { $0.finish() } })
    }

    /// Snapshot only durable Erase and data roots. A genuine checked lease
    /// release may remove its own token under Operations; that is outside the
    /// fault state and is deliberately not called byte-identical.
    private func captureTree(_ root: URL) throws -> [String: V23LateEraseTreeEntry] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [:] }
        var result: [String: V23LateEraseTreeEntry] = [:]
        func visit(_ url: URL, _ relative: String) throws {
            var info = stat()
            guard Darwin.lstat(url.path, &info) == 0 else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            let mode = info.st_mode & mode_t(S_IFMT)
            if mode == mode_t(S_IFDIR) {
                result[relative] = .directory
                let children = try FileManager.default.contentsOfDirectory(at: url,
                    includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
                for child in children {
                    let next = relative.isEmpty ? child.lastPathComponent
                        : relative + "/" + child.lastPathComponent
                    try visit(child, next)
                }
            } else if mode == mode_t(S_IFREG) {
                result[relative] = .file(try Data(contentsOf: url))
            } else {
                throw AppAccessContractFailureV1.staleAttempt
            }
        }
        try visit(root, "")
        return result
    }

    /// The old named Operations root must be physically absent. The retained
    /// owner guard remains locked on its old unlinked inode, not checked closed.
    private func requireNamedOldOperationsAbsent(in support: URL) throws {
        let path = support.appendingPathComponent("FieldEvidenceOperations", isDirectory: true).path
        var information = stat()
        let result = Darwin.lstat(path, &information)
        let lookupError = errno
        guard result == -1, lookupError == ENOENT else {
            XCTFail("Original named Operations remains or lookup failed: \(path), errno \(lookupError)")
            throw AppAccessContractFailureV1.staleAttempt
        }
    }

    /// Fresh cold startup creates a new named Registry. Missing and empty are
    /// distinct; count every lease role after actual checked writer release.
    private func allNamedLeaseIDs(in support: URL) throws -> Set<String> {
        let url = support.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/registry.json")
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG else {
            XCTFail("Fresh named lease Registry is missing or not a regular file")
            throw AppAccessContractFailureV1.staleAttempt
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let leases = try XCTUnwrap(object["leases"] as? [[String: Any]])
        return Set(try leases.map { try XCTUnwrap($0["leaseID"] as? String) })
    }
}

private enum V23LateEraseTreeEntry: Equatable {
    case directory
    case file(Data)
}

private struct V23LateEraseDiskState {
    let data: [String: V23LateEraseTreeEntry]
    let erase: [String: V23LateEraseTreeEntry]
}

private struct V23LateEraseObservation {
    let generationID: UUID
    let writerID: UUID
    let assetCount: Int
    let canonicalRowCount: Int
    let mutationReceiptCount: Int
}

@MainActor
private final class V23LateEraseRetainedOwner {
    private static var retained: [V23LateEraseRetainedOwner] = []
    let base: URL
    let original: StartupRouter
    let originalGate: AppAccessGateV1
    var ticket: StartupRouter.OriginalOperationTicket?
    var operation: EraseRouterOperationV1?
    var coldRouters: [StartupRouter] = []
    var originalCompletionCount = 0
    var coldCompletionCount = 0
    weak var sourceCoordinator: StoreSessionCoordinator?
    weak var sourceContext: ModelContext?
    weak var sourceWriter: WorkspaceWriterV1?
    weak var targetContext: ModelContext?
    weak var targetWriter: WorkspaceWriterV1?
    var modelAliasesAreDrained: Bool {
        sourceCoordinator == nil && sourceContext == nil && sourceWriter == nil
            && targetContext == nil && targetWriter == nil
    }

    init(base: URL, original: StartupRouter, originalGate: AppAccessGateV1) {
        self.base = base
        self.original = original
        self.originalGate = originalGate
        Self.retained.append(self)
        FileHandle.standardError.write(Data(("V23LateErase.rootRetained " + base.path + "\n").utf8))
    }
}

private actor V23LateEraseAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

private struct V23LateEraseClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

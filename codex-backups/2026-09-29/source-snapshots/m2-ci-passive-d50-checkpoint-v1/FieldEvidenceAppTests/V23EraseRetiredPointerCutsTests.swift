import Darwin
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Stages the exact reserved retired-pointer crash shapes under a genuine
/// original Erase operation. The original Router, Service, operation, and root
/// remain strongly owned throughout; only model aliases are allowed to drain.
final class V23EraseRetiredPointerCutsTests: XCTestCase {
    private enum Cut: CaseIterable, Equatable {
        case emptyTemporary, prefixTemporary, completeTemporary
        case swappedOldTemporary, alreadyCleared
    }

    private enum Hostile: CaseIterable, Equatable {
        case wrongPrefix, symlink, hardlink, extraDataChild, replacedCurrent
        case prematureSwap, prematureClear
    }

    private struct RetiredWire: Codable {
        let generationIDs: [String]
        let schemaVersion: Int
    }

    @MainActor
    private final class Owner {
        static var retained: [Owner] = []
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
        let defaults: UserDefaults
        let defaultsName: String
        let gate: AppAccessGateV1
        let router: StartupRouter
        let profiles: WorkspacePackageLifecycleProfileRegistryV1
        let newID: UUID
        var oldID: UUID?
        var operation: EraseRouterOperationV1?
        var service: EraseAllService?
        var completionCount = 0
        weak var sourceCoordinator: StoreSessionCoordinator?
        weak var sourceContext: ModelContext?
        weak var sourceWriter: WorkspaceWriterV1?
        weak var targetContext: ModelContext?
        weak var targetWriter: WorkspaceWriterV1?
        var modelAliasesDrained: Bool {
            sourceCoordinator == nil && sourceContext == nil && sourceWriter == nil
                && targetContext == nil && targetWriter == nil
        }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("v23-retired-pointer-cut-\(UUID().uuidString)",
                    isDirectory: true)
            support = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
            caches = root.appendingPathComponent("Caches", isDirectory: true)
            temporary = root.appendingPathComponent("Temporary", isDirectory: true)
            for directory in [support, caches, temporary] {
                try FileManager.default.createDirectory(at: directory,
                    withIntermediateDirectories: true)
            }
            defaultsName = "V23RetiredPointerCut-\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
            gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
                authentication: CutAuthentication(), clock: CutClock(),
                identifiers: SystemApplicationIDSource())
            let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
            profiles = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
            router = StartupRouter(applicationSupportURL: support,
                entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                    transactionUpdates: { AsyncStream { $0.finish() } },
                    statusUpdates: { AsyncStream { $0.finish() } }),
                lifecycleProfileRegistry: profiles)
            newID = UUID()
            Self.retained.append(self)
        }

        var dataRoot: URL {
            support.appendingPathComponent("FieldEvidenceData", isDirectory: true)
        }
        var currentURL: URL { dataRoot.appendingPathComponent("current.json") }
        var retiredURL: URL { dataRoot.appendingPathComponent("retired.json") }
        var temporaryURL: URL {
            dataRoot.appendingPathComponent(".retired.json.restore-next")
        }
        var oldGenerationURL: URL {
            support.appendingPathComponent("FieldEvidenceData/generations")
                .appendingPathComponent(oldID!.uuidString.lowercased(), isDirectory: true)
        }
    }

    @MainActor
    func testEmptyReservedTemporaryCompletesGenuineErase() async throws {
        try await exercisePositive(.emptyTemporary)
    }

    @MainActor
    func testPrefixReservedTemporaryCompletesGenuineErase() async throws {
        try await exercisePositive(.prefixTemporary)
    }

    @MainActor
    func testCompletePreSwapTemporaryCompletesGenuineErase() async throws {
        try await exercisePositive(.completeTemporary)
    }

    @MainActor
    func testSwappedOldTemporaryCompletesGenuineErase() async throws {
        try await exercisePositive(.swappedOldTemporary)
    }

    @MainActor
    func testAlreadyClearedRetiredPointerCompletesGenuineErase() async throws {
        try await exercisePositive(.alreadyCleared)
    }

    @MainActor
    func testHostileReservedPointerShapesRefuseWithoutCanonicalDeletion() async throws {
        for hostile in Hostile.allCases {
            let owner = try await prepareOriginalErase()
            let oldID = try XCTUnwrap(owner.oldID)
            let pointer = try Data(contentsOf: owner.currentURL)
            let retired = try Data(contentsOf: owner.retiredURL)
            try stage(hostile, owner: owner, retired: retired)
            let stagedPointer = try Data(contentsOf: owner.currentURL)
            let stagedRetired = try Data(contentsOf: owner.retiredURL)
            let stagedRetiredBackup = try backupExcluded(owner.retiredURL)
            let stagedTemporary = try optionalBytes(owner.temporaryURL)
            let stagedExtra = try optionalBytes(owner.dataRoot.appendingPathComponent("alien.json"))
            let intentURL = owner.support.appendingPathComponent("FieldEvidenceErase/erase.json")
            let stagedIntent = try Data(contentsOf: intentURL)
            let operation = try XCTUnwrap(owner.operation)
            do {
                _ = try await operation.advanceCleanup()
                XCTFail("\(hostile) was admitted by genuine Erase cleanup")
            } catch { }
            XCTAssertEqual(owner.completionCount, 0, "\(hostile)")
            XCTAssertEqual(try Data(contentsOf: owner.currentURL), stagedPointer, "\(hostile)")
            XCTAssertEqual(try Data(contentsOf: owner.retiredURL), stagedRetired, "\(hostile)")
            XCTAssertEqual(try backupExcluded(owner.retiredURL), stagedRetiredBackup,
                "\(hostile) changed retired pointer policy")
            XCTAssertEqual(try optionalBytes(owner.temporaryURL), stagedTemporary, "\(hostile)")
            XCTAssertEqual(try optionalBytes(owner.dataRoot.appendingPathComponent("alien.json")),
                stagedExtra, "\(hostile)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: owner.oldGenerationURL.path),
                "\(hostile) must not delete frozen old generation \(oldID)")
            XCTAssertEqual(try Data(contentsOf: intentURL), stagedIntent, "\(hostile)")
            if hostile == .symlink {
                XCTAssertEqual(try Data(contentsOf: owner.root.appendingPathComponent(
                    "outside-canary")), Data("outside".utf8))
            }
            XCTAssertNotEqual(pointer, Data(), "\(hostile)")
            XCTAssertNotEqual(retired, Data(), "\(hostile)")
        }
    }

    @MainActor
    private func exercisePositive(_ cut: Cut) async throws {
        let afterDeletion = cut == .swappedOldTemporary || cut == .alreadyCleared
        let owner = try await prepareOriginalErase(cutHook: afterDeletion ? cut : nil)
        let oldID = try XCTUnwrap(owner.oldID)
        let current = try Data(contentsOf: owner.currentURL)
        let oldRetired = try Data(contentsOf: owner.retiredURL)
        XCTAssertEqual(try backupExcluded(owner.retiredURL), false)
        let oldWire = try JSONDecoder().decode(RetiredWire.self, from: oldRetired)
        XCTAssertEqual(oldWire.generationIDs, [oldID.uuidString.lowercased()])
        let emptyRetired = try canonicalRetired([], version: oldWire.schemaVersion)
        if !afterDeletion { try stage(cut, owner: owner, empty: emptyRetired) }
        // Decode the already-published canonical leaf as an assertion only.
        // A second EraseIntentStore would create/reconcile under the retained
        // original operation's exclusion and would itself change the cut.
        let intent = try EraseIntentCodecV1.decode(Data(contentsOf:
            owner.support.appendingPathComponent("FieldEvidenceErase/erase.json")))
        XCTAssertEqual(intent.phase, .sessionActivated)
        XCTAssertEqual(intent.generationIDsToDelete, [oldID])
        XCTAssertEqual(intent.newGenerationID, owner.newID)
        XCTAssertEqual(try Data(contentsOf: owner.currentURL), current)
        XCTAssertEqual(owner.completionCount, 0)

        let operation = try XCTUnwrap(owner.operation)
        if afterDeletion {
            do {
                _ = try await operation.advanceCleanup()
                XCTFail("Expected one-shot interruption at genuine post-deletion cut")
            } catch EraseAllServiceError.injectedFailure { }
            XCTAssertEqual(owner.completionCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: owner.oldGenerationURL.path))
            XCTAssertEqual(try Data(contentsOf: owner.retiredURL), emptyRetired)
            XCTAssertEqual(try backupExcluded(owner.retiredURL), true,
                "the swapped temporary still has its temporary policy at the cut")
            XCTAssertEqual(try optionalBytes(owner.temporaryURL),
                cut == .swappedOldTemporary ? oldRetired : nil)
            XCTAssertEqual(try Data(contentsOf: owner.currentURL), current)
        }
        let completed = try await operation.advanceCleanup()
        XCTAssertTrue(completed, "\(cut)")
        XCTAssertEqual(owner.completionCount, 1, "\(cut)")
        XCTAssertNotNil(try operation.completedRetirement().2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owner.oldGenerationURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: owner.temporaryURL.path))
        XCTAssertEqual(try Data(contentsOf: owner.currentURL), current)
        XCTAssertEqual(try Data(contentsOf: owner.retiredURL), emptyRetired)
        XCTAssertEqual(try backupExcluded(owner.retiredURL), false,
            "published retired pointer must have pointer policy")
        XCTAssertTrue(eraseRootIsAbsentNoFollow(owner.support))
        let completedAgain = try await operation.advanceCleanup()
        XCTAssertTrue(completedAgain, "idempotent \(cut)")
        XCTAssertEqual(owner.completionCount, 1, "callback repeats for \(cut)")
        XCTAssertEqual(try Data(contentsOf: owner.retiredURL), emptyRetired)
    }

    @MainActor
    private func prepareOriginalErase(cutHook: Cut? = nil) async throws -> Owner {
        let owner = try Owner()
        let unlocked = await owner.gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlocked, .authenticated)
        try owner.router.bindStartupAccessGate(owner.gate)
        try await owner.router.startIfNeeded(accessGate: owner.gate)
        do {
            guard case let .ready(coordinator, _, _) = owner.router.route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            owner.oldID = coordinator.generationID
            owner.sourceCoordinator = coordinator
            owner.sourceContext = coordinator.modelContext
            owner.sourceWriter = coordinator.workspaceWriter
            let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
            let siteID = UUID(), assetID = UUID()
            let mutation = try MutationIDV1(rawValue: UUID())
            _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "Retired cut site",
                    address: nil, timeZoneID: "America/New_York"),
                assetID: assetID, assetLabel: "Retired cut asset",
                packID: profile.package.packID,
                packSchemaVersion: profile.package.schemaVersion,
                packContentVersion: profile.package.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_700_040_000),
                initialPlacementMutationID: mutation,
                initialPlacementEventID: UUID(),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
            )), mutationID: mutation)
            try await coordinator.awaitSearchIndexLifecycle()
            XCTAssertEqual(try coordinator.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
            try await beginErase(owner, coordinator: coordinator, cutHook: cutHook)
        }
        let drained = expectation(for: NSPredicate { _, _ in owner.modelAliasesDrained },
            evaluatedWith: NSObject())
        await fulfillment(of: [drained], timeout: 30)
        XCTAssertTrue(owner.modelAliasesDrained)
        return owner
    }

    @MainActor
    private func beginErase(_ owner: Owner,
        coordinator: StoreSessionCoordinator, cutHook: Cut?) async throws {
        let ticket = try await owner.router.beginEraseOperation(
            coordinator: coordinator, accessGate: owner.gate)
        let operation = try owner.router.eraseRetirementOperation(for: ticket)
        owner.operation = operation
        var identifiers = [owner.newID, UUID(), UUID(), UUID()]
        var reservation: AppAccessGateV1.EraseAdoptionToken?
        var activationFailure: Error?
        let service = try owner.router.configureEraseService(EraseAllService(
            applicationSupportURL: owner.support, cachesDirectoryURL: owner.caches,
            temporaryDirectoryURL: owner.temporary, userDefaults: owner.defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: owner.defaultsName,
            makeUUID: { identifiers.removeFirst() },
            privateSystemDiscoveryIndex: nil,
            admitErase: { subject in
                if let authorization = try await owner.router.eraseAdmissionAuthorization(
                    ticket, subject: subject) {
                    let actual = try await owner.gate.reserveEraseAdoption(
                        subject: subject, authorization: authorization)
                    try owner.router.recordEraseReservation(ticket, reservation: actual)
                    reservation = actual
                    return actual
                }
                guard let reservation, reservation.subject == subject else {
                    throw AppAccessContractFailureV1.staleAttempt
                }
                return reservation
            },
            didCompleteErase: { _ in owner.completionCount += 1 }
        ), operation: operation)
        owner.service = service
        if let cutHook {
            service.afterOldGenerationDeletionBeforeRetiredPointerClearForTesting = {
                let old = try Data(contentsOf: owner.retiredURL)
                let wire = try JSONDecoder().decode(RetiredWire.self, from: old)
                let empty = try self.canonicalRetired([], version: wire.schemaVersion)
                try self.stage(cutHook, owner: owner, empty: empty)
                throw EraseAllServiceError.injectedFailure
            }
        }
        let dependencies = try coordinator.packageLifecycleDependencies(
            profileRegistry: owner.profiles)
        let result = try await service.erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: coordinator,
            diagnosticsStore: DiagnosticsStore(applicationSupportURL: owner.support),
            operation: operation,
            activate: { [weak coordinator] session in
                do {
                    let actual = try XCTUnwrap(coordinator)
                    try owner.router.activateErasePreparationSession(session,
                        coordinator: actual, operation: operation)
                    owner.targetContext = actual.modelContext
                    owner.targetWriter = actual.workspaceWriter
                } catch { activationFailure = error }
            }, lifecycleDependencies: dependencies)
        if let activationFailure { throw activationFailure }
        XCTAssertTrue(result.operation === operation)
        XCTAssertEqual(try XCTUnwrap(reservation).subject.newGenerationID, owner.newID)
        XCTAssertEqual(owner.completionCount, 0)
    }

    @MainActor
    private func stage(_ cut: Cut, owner: Owner, empty: Data) throws {
        switch cut {
        case .emptyTemporary:
            try Data().write(to: owner.temporaryURL)
            try synchronizeTemporary(owner)
        case .prefixTemporary:
            try Data(empty.prefix(max(1, empty.count / 2))).write(to: owner.temporaryURL)
            try synchronizeTemporary(owner)
        case .completeTemporary:
            try empty.write(to: owner.temporaryURL)
            try synchronizeTemporary(owner)
        case .swappedOldTemporary, .alreadyCleared:
            try empty.write(to: owner.temporaryURL)
            _ = try ProtectedFilePolicyV1.applyAndVerify(.generationPointerTemporary,
                at: owner.temporaryURL)
            try synchronizeTemporary(owner)
            try swapRetiredAndTemporary(owner)
            if cut == .alreadyCleared { try unlinkTemporary(owner) }
        }
    }

    @MainActor
    private func stage(_ hostile: Hostile, owner: Owner, retired: Data) throws {
        let fileManager = FileManager.default
        switch hostile {
        case .wrongPrefix:
            try Data("not-an-empty-retired-pointer".utf8).write(to: owner.temporaryURL)
        case .symlink:
            let canary = owner.root.appendingPathComponent("outside-canary")
            try Data("outside".utf8).write(to: canary)
            try fileManager.createSymbolicLink(at: owner.temporaryURL,
                withDestinationURL: canary)
        case .hardlink:
            guard Darwin.link(owner.retiredURL.path, owner.temporaryURL.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        case .extraDataChild:
            try Data("alien".utf8).write(to: owner.dataRoot.appendingPathComponent("alien.json"))
        case .replacedCurrent:
            let bytes = try Data(contentsOf: owner.currentURL)
            try bytes.write(to: owner.currentURL, options: .atomic)
        case .prematureSwap, .prematureClear:
            let oldWire = try JSONDecoder().decode(RetiredWire.self, from: retired)
            let empty = try canonicalRetired([], version: oldWire.schemaVersion)
            try empty.write(to: owner.temporaryURL)
            _ = try ProtectedFilePolicyV1.applyAndVerify(.generationPointerTemporary,
                at: owner.temporaryURL)
            try synchronizeTemporary(owner)
            try swapRetiredAndTemporary(owner)
            if hostile == .prematureClear { try unlinkTemporary(owner) }
        }
        if hostile == .prematureSwap || hostile == .prematureClear {
            let oldWire = try JSONDecoder().decode(RetiredWire.self, from: retired)
            XCTAssertEqual(try Data(contentsOf: owner.retiredURL),
                try canonicalRetired([], version: oldWire.schemaVersion))
        } else {
            XCTAssertEqual(try Data(contentsOf: owner.retiredURL), retired)
        }
    }

    private func canonicalRetired(_ ids: [String], version: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(RetiredWire(generationIDs: ids, schemaVersion: version))
    }

    private func optionalBytes(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError { return nil }
    }

    private func backupExcluded(_ url: URL) throws -> Bool? {
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        return try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup
    }

    private func eraseRootIsAbsentNoFollow(_ support: URL) -> Bool {
        var named = stat()
        let result = Darwin.lstat(support.appendingPathComponent(
            "FieldEvidenceErase", isDirectory: true).path, &named)
        return result != 0 && errno == ENOENT
    }

    @MainActor
    private func swapRetiredAndTemporary(_ owner: Owner) throws {
        let directory = Darwin.open(owner.dataRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { XCTAssertEqual(Darwin.close(directory), 0) }
        guard Darwin.renameatx_np(directory, ".retired.json.restore-next",
            directory, "retired.json", UInt32(RENAME_SWAP)) == 0,
              Darwin.fsync(directory) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    @MainActor
    private func synchronizeTemporary(_ owner: Owner) throws {
        let file = Darwin.open(owner.temporaryURL.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard Darwin.fsync(file) == 0 else {
            let error = errno
            XCTAssertEqual(Darwin.close(file), 0)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
        }
        guard Darwin.close(file) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let directory = Darwin.open(owner.dataRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard Darwin.fsync(directory) == 0 else {
            let error = errno
            XCTAssertEqual(Darwin.close(directory), 0)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
        }
        guard Darwin.close(directory) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    @MainActor
    private func unlinkTemporary(_ owner: Owner) throws {
        let directory = Darwin.open(owner.dataRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { XCTAssertEqual(Darwin.close(directory), 0) }
        guard Darwin.unlinkat(directory, ".retired.json.restore-next", 0) == 0,
              Darwin.fsync(directory) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

private actor CutAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

private struct CutClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

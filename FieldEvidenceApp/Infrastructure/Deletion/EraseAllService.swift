import Darwin
import Foundation
import SwiftData

enum EraseAllServiceError: Error, Equatable {
    case contextHasChanges
    case invalidAuthority
    case invalidConfirmation
    case recoveryRequired
    case injectedFailure
}

enum EraseAllFailurePoint: CaseIterable, Equatable, Sendable {
    case afterEmptyGenerationDirectoryCreate
    case beforePreparedWrite
    case afterPreparedWrite
    case beforePointerSwitch
    case afterPointerSwitch
    case beforePointerPhaseWrite
    case afterPointerPhaseWrite
    case beforeSessionActivation
    case afterSessionActivation
    case beforeSessionPhaseWrite
    case afterSessionPhaseWrite
    case beforeCleanup
    case afterCleanup
    case beforeCleanupPhaseWrite
    case afterCleanupPhaseWrite
    case beforeJournalRemoval
}

@MainActor
final class EraseAllFailureInjection {
    private var pending: EraseAllFailurePoint?

    init(failOnceAt point: EraseAllFailurePoint) {
        pending = point
    }

    func consume(_ point: EraseAllFailurePoint) -> Bool {
        guard pending == point else { return false }
        pending = nil
        return true
    }
}

@MainActor
final class EraseGenerationDrainProof {
    private weak var priorContext: ModelContext?
    private weak var priorContainer: ModelContainer?

    init(priorContext: ModelContext) {
        self.priorContext = priorContext
        self.priorContainer = priorContext.container
    }

    var isDrained: Bool {
        priorContext == nil && priorContainer == nil
    }
}

@MainActor
final class EraseAllService {
    static let requiredConfirmation = "ERASE"

    private let applicationSupportURL: URL
    private let cachesDirectoryURL: URL
    private let temporaryDirectoryURL: URL
    private let generationFactory: StoreGenerationFactory
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let bundleIdentifier: String
    private let makeUUID: () -> UUID
    private let failureInjection: EraseAllFailureInjection?

    init(
        applicationSupportURL: URL,
        cachesDirectoryURL: URL? = nil,
        temporaryDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier
            ?? "com.palatis3.fieldrecord",
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: EraseAllFailureInjection? = nil
    ) {
        let support = applicationSupportURL.standardizedFileURL
        self.applicationSupportURL = support
        self.cachesDirectoryURL = (
            cachesDirectoryURL
                ?? support.deletingLastPathComponent()
                    .appendingPathComponent("Caches", isDirectory: true)
        ).standardizedFileURL
        self.temporaryDirectoryURL = (
            temporaryDirectoryURL ?? fileManager.temporaryDirectory
        ).standardizedFileURL
        self.generationFactory = StoreGenerationFactory(
            applicationSupportURL: support,
            fileManager: fileManager
        )
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.bundleIdentifier = bundleIdentifier
        self.makeUUID = makeUUID
        self.failureInjection = failureInjection
    }

    func erase(
        confirmation: String,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> StoreGenerationSession {
        guard confirmation == Self.requiredConfirmation else {
            throw EraseAllServiceError.invalidConfirmation
        }
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
        let auxiliary = try makeAuxiliaryAuthority()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()
        let applicationSupportIdentity = auxiliary.applicationSupportRootIdentity

        let generationAuthority = try generationFactory
            .makeRestoreGenerationAuthority(
                expectedApplicationSupportIdentity: applicationSupportIdentity
            )
        let drainProof = EraseGenerationDrainProof(
            priorContext: coordinator.modelContext
        )
        let oldGenerationID = coordinator.generationID
        let oldGenerationRootURL = coordinator.generationRootURL
        let priorRetired = try generationAuthority.retiredGenerationIDs()
        try validateCurrentAuthority(
            coordinator: coordinator,
            expectedID: oldGenerationID,
            expectedRootURL: oldGenerationRootURL,
            retiredIDs: priorRetired,
            authority: generationAuthority
        )
        try auxiliary.verifyTargets()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()

        let newGenerationID = makeUUID()
        let eraseID = makeUUID()
        let generationIDsToDelete = (priorRetired + [oldGenerationID]).sorted(
            by: Self.idOrder
        )
        let intent = EraseIntentV1(
            auxiliaryRoots: EraseIntentV1.canonicalAuxiliaryRoots,
            eraseID: eraseID,
            generationIDsToDelete: generationIDsToDelete,
            newGenerationID: newGenerationID,
            oldGenerationID: oldGenerationID,
            phase: .emptyGenerationPrepared,
            schemaVersion: 1
        )
        guard EraseIntentCodecV1.valid(intent),
              newGenerationID != eraseID,
              !generationIDsToDelete.contains(newGenerationID) else {
            throw EraseAllServiceError.invalidAuthority
        }

        var createdNewGeneration = false
        var createdIntent = false
        var intentStore: EraseIntentStore?
        do {
            createdNewGeneration = true
            try generationFactory.createEmptyInstalledGeneration(
                id: newGenerationID,
                authority: generationAuthority,
                beforeStoreCreate: {
                    try self.inject(.afterEmptyGenerationDirectoryCreate)
                }
            )
            _ = try validatedEmptySession(
                id: newGenerationID,
                authority: generationAuthority
            )
            try requirePreparedPresence(intent, authority: generationAuthority)
            try auxiliary.requireNoEraseIntent()
            try auxiliary.requireNoRestoreIntent()

            try inject(.beforePreparedWrite)
            let store = try EraseIntentStore(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager,
                expectedApplicationSupportIdentity: applicationSupportIdentity
            )
            guard try store.load() == nil else {
                throw EraseAllServiceError.recoveryRequired
            }
            intentStore = store
            try store.create(intent)
            createdIntent = true
            try inject(.afterPreparedWrite)

            guard let intentStore else {
                throw EraseAllServiceError.invalidAuthority
            }
            let session = try await advanceToActivatedSession(
                intent,
                authority: generationAuthority,
                intentStore: intentStore,
                activate: activate
            )
            guard coordinator.generationID == session.generationID,
                  coordinator.generationRootURL.standardizedFileURL
                    == session.generationRootURL.standardizedFileURL,
                  coordinator.modelContext === session.modelContext,
                  await waitForDrain(drainProof) else {
                throw EraseAllServiceError.recoveryRequired
            }
            let activated = intent.advancing(to: .sessionActivated)
            let completed = try await completeCleanup(
                activated,
                session: session,
                authority: generationAuthority,
                auxiliary: auxiliary,
                diagnosticsStore: diagnosticsStore,
                intentStore: intentStore
            )
            return completed
        } catch {
            if !createdIntent {
                var ownsUnjournaledGeneration = true
                if let intentStore {
                    do {
                        if let stored = try intentStore.load() {
                            guard stored == intent else {
                                throw EraseAllServiceError.recoveryRequired
                            }
                            ownsUnjournaledGeneration = false
                        }
                    } catch {
                        throw EraseAllServiceError.recoveryRequired
                    }
                }
                do {
                    if createdNewGeneration,
                       ownsUnjournaledGeneration,
                       try generationAuthority.installedGenerationNames()
                        .contains(Self.canonical(newGenerationID)) {
                        try generationAuthority.removeInstalledGeneration(
                            id: newGenerationID
                        )
                    }
                    if ownsUnjournaledGeneration {
                        try auxiliary.removeEraseRootIfEmpty()
                    }
                } catch {
                    throw EraseAllServiceError.recoveryRequired
                }
            }
            throw error
        }
    }

    /// Runs before Restore and ordinary pointer maintenance. A nonnil result
    /// is the one reopened empty generation that startup must activate.
    func reconcileAtStartup(
        diagnosticsStore: DiagnosticsStore
    ) async throws -> StoreGenerationSession? {
        var supportStatus = stat()
        let supportResult = applicationSupportURL.path.withCString {
            lstat($0, &supportStatus)
        }
        if supportResult != 0 {
            guard errno == ENOENT else {
                throw EraseAllServiceError.invalidAuthority
            }
            return nil
        }
        guard (supportStatus.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        let auxiliary = try makeAuxiliaryAuthority()
        let intentStore = try EraseIntentStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        guard let intent = try intentStore.load() else {
            try auxiliary.removeEraseRootIfEmpty()
            return nil
        }
        guard EraseIntentCodecV1.valid(intent) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        try auxiliary.verifyTargets()
        try requireRecoveryPresence(intent, authority: authority)

        let session: StoreGenerationSession
        switch intent.phase {
        case .emptyGenerationPrepared:
            session = try await advanceToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                activate: { _ in }
            )
        case .pointerSwitched:
            session = try await advancePointerPhaseToActivatedSession(
                intent,
                authority: authority,
                intentStore: intentStore,
                activate: { _ in }
            )
        case .sessionActivated:
            try requireActivatedCurrent(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        case .cleanupComplete:
            try requireCleanupPresence(intent, authority: authority)
            session = try validatedEmptySession(
                id: intent.newGenerationID,
                authority: authority
            )
        }

        let activated = intent.phase == .cleanupComplete
            ? intent
            : intent.advancing(to: .sessionActivated)
        return try await completeCleanup(
            activated,
            session: session,
            authority: authority,
            auxiliary: auxiliary,
            diagnosticsStore: diagnosticsStore,
            intentStore: intentStore
        )
    }

    func validateMaintenanceEntry(_ session: StoreGenerationSession) throws {
        let coordinator = StoreSessionCoordinator(session: session)
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
        let auxiliary = try makeAuxiliaryAuthority()
        try auxiliary.requireNoEraseIntent()
        try auxiliary.requireNoRestoreIntent()
        let authority = try generationFactory.makeRestoreGenerationAuthority(
            expectedApplicationSupportIdentity:
                auxiliary.applicationSupportRootIdentity
        )
        let retired = try authority.retiredGenerationIDs()
        try validateCurrentAuthority(
            coordinator: coordinator,
            expectedID: session.generationID,
            expectedRootURL: session.generationRootURL,
            retiredIDs: retired,
            authority: authority
        )
        try auxiliary.verifyTargets()
    }
}

private extension EraseAllService {
    func makeAuxiliaryAuthority() throws -> EraseAuxiliaryAuthority {
        guard bundleIdentifier == "com.palatis3.fieldrecord" else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try EraseAuxiliaryAuthority(
            applicationSupportURL: applicationSupportURL,
            cachesDirectoryURL: cachesDirectoryURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
    }

    func validateCurrentAuthority(
        coordinator: StoreSessionCoordinator,
        expectedID: UUID,
        expectedRootURL: URL,
        retiredIDs: [UUID],
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
        let installed = try authority.installedGenerationNames()
        let expectedNames = Set((retiredIDs + [expectedID]).map(Self.canonical))
        guard try generationFactory.currentGenerationID(authority: authority)
                == expectedID,
              !retiredIDs.contains(expectedID),
              Set(installed) == expectedNames,
              generationFactory.installedGenerationURL(id: expectedID)
                == expectedRootURL.standardizedFileURL,
              try ReportPDFAnchoredFile.rootIdentity(at: expectedRootURL)
                == ReportPDFAnchoredFile.rootIdentity(
                    at: generationFactory.installedGenerationURL(id: expectedID)
                ),
              try authority.restoreGenerationNames().isEmpty,
              try authority.importStagingNames().isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        try validateFrozenGeneration(
            id: expectedID,
            modelContext: coordinator.modelContext,
            generationRootURL: expectedRootURL,
            authority: authority
        )
        for id in retiredIDs {
            let retiredSession = try generationFactory.openInstalledGeneration(
                id: id,
                authority: authority
            )
            try validateFrozenGeneration(
                id: id,
                modelContext: retiredSession.modelContext,
                generationRootURL: retiredSession.generationRootURL,
                authority: authority
            )
        }
        guard !coordinator.modelContext.hasChanges else {
            throw EraseAllServiceError.contextHasChanges
        }
    }

    func requirePreparedPresence(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let expected = Set(
            (intent.generationIDsToDelete + [intent.newGenerationID])
                .map(Self.canonical)
        )
        guard Set(try authority.installedGenerationNames()) == expected,
              try generationFactory.currentGenerationID(authority: authority)
                == intent.oldGenerationID,
              try authority.retiredGenerationIDs()
                == priorRetiredIDs(intent) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireRecoveryPresence(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let installed = Set(try authority.installedGenerationNames())
        let all = Set(
            (intent.generationIDsToDelete + [intent.newGenerationID])
                .map(Self.canonical)
        )
        guard installed.contains(Self.canonical(intent.newGenerationID)),
              installed.isSubset(of: all),
              try authority.restoreGenerationNames().isEmpty,
              try authority.importStagingNames().isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        switch intent.phase {
        case .emptyGenerationPrepared, .pointerSwitched:
            guard installed == all else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .sessionActivated, .cleanupComplete:
            break
        }
        _ = try validatedEmptySession(
            id: intent.newGenerationID,
            authority: authority
        )
        for id in intent.generationIDsToDelete
        where installed.contains(Self.canonical(id)) {
            let session = try generationFactory.openInstalledGeneration(
                id: id,
                authority: authority
            )
            try validateFrozenGeneration(
                id: id,
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                authority: authority
            )
        }
    }

    func advanceToActivatedSession(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> StoreGenerationSession {
        try inject(.beforePointerSwitch)
        try normalizePointerAndRetired(intent, authority: authority)
        try inject(.afterPointerSwitch)

        let switched = intent.advancing(to: .pointerSwitched)
        try inject(.beforePointerPhaseWrite)
        if intent.phase == .emptyGenerationPrepared {
            try intentStore.replace(expected: intent, with: switched)
        }
        try inject(.afterPointerPhaseWrite)
        return try await advancePointerPhaseToActivatedSession(
            switched,
            authority: authority,
            intentStore: intentStore,
            activate: activate
        )
    }

    func advancePointerPhaseToActivatedSession(
        _ switched: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority,
        intentStore: EraseIntentStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) async throws -> StoreGenerationSession {
        try normalizePointerAndRetired(switched, authority: authority)
        try requireNewCurrent(switched, authority: authority)
        let session = try validatedEmptySession(
            id: switched.newGenerationID,
            authority: authority
        )
        try inject(.beforeSessionActivation)
        await activate(session)
        await Task.yield()
        try inject(.afterSessionActivation)

        let activated = switched.advancing(to: .sessionActivated)
        try inject(.beforeSessionPhaseWrite)
        try intentStore.replace(expected: switched, with: activated)
        try inject(.afterSessionPhaseWrite)
        return session
    }

    func normalizePointerAndRetired(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let current = try generationFactory.currentGenerationID(authority: authority)
        if current == intent.oldGenerationID {
            try generationFactory.switchCurrentGeneration(
                expected: intent.oldGenerationID,
                to: intent.newGenerationID,
                authority: authority
            )
        } else if current != intent.newGenerationID {
            throw EraseAllServiceError.invalidAuthority
        }
        let retired = try authority.retiredGenerationIDs()
        let prior = priorRetiredIDs(intent)
        if retired == prior {
            try generationFactory.replaceRetiredGenerationIDs(
                expected: prior,
                with: intent.generationIDsToDelete,
                currentID: intent.newGenerationID,
                authority: authority
            )
        } else if retired != intent.generationIDsToDelete {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireNewCurrent(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID,
              try authority.retiredGenerationIDs()
                == intent.generationIDsToDelete else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireActivatedCurrent(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let retired = try authority.retiredGenerationIDs()
        let installed = Set(try authority.installedGenerationNames())
        let newName = Self.canonical(intent.newGenerationID)
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID,
              retired == intent.generationIDsToDelete
                || (retired.isEmpty && installed == [newName]) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func completeCleanup(
        _ value: EraseIntentV1,
        session: StoreGenerationSession,
        authority: StoreRestoreGenerationAuthority,
        auxiliary: EraseAuxiliaryAuthority,
        diagnosticsStore: DiagnosticsStore,
        intentStore: EraseIntentStore
    ) async throws -> StoreGenerationSession {
        let activated: EraseIntentV1
        if value.phase == .cleanupComplete {
            activated = value.advancing(to: .sessionActivated)
        } else {
            activated = value
        }
        guard activated.phase == .sessionActivated,
              session.generationID == activated.newGenerationID,
              BackupRestoreService.isEmptyCurrent(session.modelContext) else {
            throw EraseAllServiceError.invalidAuthority
        }

        if value.phase != .cleanupComplete {
            try inject(.beforeCleanup)
        }
        try cleanupGenerations(activated, authority: authority)
        try requireCleanupPresence(
            activated.advancing(to: .cleanupComplete),
            authority: authority
        )
        try auxiliary.removeFrozenTargets()
        userDefaults.removePersistentDomain(forName: bundleIdentifier)
        let diagnosticsZero = try canonicalDiagnosticsZero()
        try auxiliary.createZeroDiagnostics(data: diagnosticsZero)
        await diagnosticsStore.acceptDescriptorErasedZero()
        guard await diagnosticsStore.isExactlyZero(),
              (userDefaults.persistentDomain(forName: bundleIdentifier) ?? [:])
                .isEmpty,
              BackupRestoreService.isEmptyCurrent(session.modelContext) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try auxiliary.verifyTargetsRemovedExceptDiagnostics()
        try auxiliary.verifyDiagnostics(
            expectedData: diagnosticsZero
        )
        if value.phase != .cleanupComplete {
            try inject(.afterCleanup)
        }

        let completed = activated.advancing(to: .cleanupComplete)
        if value.phase != .cleanupComplete {
            try inject(.beforeCleanupPhaseWrite)
            try intentStore.replace(expected: activated, with: completed)
            try inject(.afterCleanupPhaseWrite)
        }
        try inject(.beforeJournalRemoval)
        try intentStore.remove(expected: completed)
        try auxiliary.removeEraseRootIfEmpty()
        return session
    }

    func cleanupGenerations(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        let initialRetired = try authority.retiredGenerationIDs()
        guard initialRetired == intent.generationIDsToDelete
                || initialRetired.isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        let allowedNames = Set(
            (intent.generationIDsToDelete + [intent.newGenerationID])
                .map(Self.canonical)
        )
        guard Set(try authority.installedGenerationNames())
                .isSubset(of: allowedNames),
              try authority.installedGenerationNames().contains(
                Self.canonical(intent.newGenerationID)
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for id in intent.generationIDsToDelete {
            let name = Self.canonical(id)
            if try authority.installedGenerationNames().contains(name) {
                try generationFactory.removeInstalledGeneration(
                    id: id,
                    keeping: intent.newGenerationID,
                    authority: authority
                )
            }
        }
        guard Set(try authority.installedGenerationNames())
                == [Self.canonical(intent.newGenerationID)] else {
            throw EraseAllServiceError.invalidAuthority
        }
        if initialRetired == intent.generationIDsToDelete {
            try generationFactory.replaceRetiredGenerationIDs(
                expected: initialRetired,
                with: [],
                currentID: intent.newGenerationID,
                authority: authority
            )
        } else if !initialRetired.isEmpty {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func requireCleanupPresence(
        _ intent: EraseIntentV1,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        let currentSession = try generationFactory.openInstalledGeneration(
            id: intent.newGenerationID,
            authority: authority
        )
        guard try generationFactory.currentGenerationID(authority: authority)
                == intent.newGenerationID,
              try authority.retiredGenerationIDs().isEmpty,
              Set(try authority.installedGenerationNames())
                == [Self.canonical(intent.newGenerationID)],
              BackupRestoreService.isEmptyCurrent(
                currentSession.modelContext
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func validatedEmptySession(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        let session = try generationFactory.openInstalledGeneration(
            id: id,
            authority: authority
        )
        let tree = try authority.installedTree(id: id)
        let allowedFiles: Set<String> = [
            "model.sqlite",
            "model.sqlite-shm",
            "model.sqlite-wal",
        ]
        guard BackupRestoreService.isEmptyCurrent(session.modelContext),
              tree.directories.isEmpty,
              tree.files.contains("model.sqlite"),
              tree.files.isSubset(of: allowedFiles) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return session
    }

    func validateFrozenGeneration(
        id: UUID,
        modelContext: ModelContext,
        generationRootURL: URL,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard !modelContext.hasChanges,
              generationRootURL.standardizedFileURL
                == generationFactory.installedGenerationURL(id: id) else {
            throw EraseAllServiceError.invalidAuthority
        }
        if !BackupRestoreService.isEmptyCurrent(modelContext) {
            _ = try BackupRestoreService.currentSummary(
                modelContext: modelContext,
                generationRootURL: generationRootURL
            )
        }
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        var expectedDirectories = Set<String>()
        var expectedFiles: Set<String> = ["model.sqlite"]
        if !evidence.isEmpty { expectedDirectories.insert("evidence") }
        for value in evidence {
            expectedDirectories.insert("evidence/\(Self.canonical(value.id))")
            expectedFiles.insert(value.relativePath)
            expectedFiles.insert(value.thumbnailRelativePath)
        }
        if !reports.isEmpty { expectedDirectories.insert("snapshots") }
        if reports.contains(where: { $0.pdfRelativePath != nil }) {
            expectedDirectories.insert("pdfs")
        }
        for value in reports {
            expectedFiles.insert(value.snapshotRelativePath)
            if let path = value.pdfRelativePath { expectedFiles.insert(path) }
        }
        let allowedStagingDirectories: Set<String> = [
            ".staging",
            ".staging/evidence",
            ".staging/pdfs",
            ".staging/snapshots",
        ]
        let optionalFiles: Set<String> = [
            "model.sqlite-shm",
            "model.sqlite-wal",
        ]
        let tree = try authority.installedTree(id: id)
        guard expectedDirectories.isSubset(of: tree.directories),
              tree.directories.isSubset(
                of: expectedDirectories.union(allowedStagingDirectories)
              ),
              expectedFiles.isSubset(of: tree.files),
              tree.files.isSubset(of: expectedFiles.union(optionalFiles)),
              !modelContext.hasChanges else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    func priorRetiredIDs(_ intent: EraseIntentV1) -> [UUID] {
        intent.generationIDsToDelete.filter { $0 != intent.oldGenerationID }
    }

    func inject(_ point: EraseAllFailurePoint) throws {
        if failureInjection?.consume(point) == true {
            throw EraseAllServiceError.injectedFailure
        }
    }

    func canonicalDiagnosticsZero() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(DiagnosticsV1.zero)
    }

    static func canonical(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        canonical(lhs) < canonical(rhs)
    }

    func waitForDrain(_ proof: EraseGenerationDrainProof) async -> Bool {
        for _ in 0..<200 {
            if proof.isDrained { return true }
            await Task.yield()
            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                return proof.isDrained
            }
        }
        return proof.isDrained
    }
}

private final class EraseAuxiliaryAuthority {
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private let applicationSupportURL: URL
    private let cachesDirectoryURL: URL
    private let temporaryDirectoryURL: URL
    private let applicationSupportDescriptor: Int32
    private let cachesDescriptor: Int32
    private let temporaryDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let cachesIdentity: Identity
    private let temporaryIdentity: Identity

    var applicationSupportRootIdentity: StoreApplicationSupportIdentity {
        StoreApplicationSupportIdentity(
            device: applicationSupportIdentity.device,
            inode: applicationSupportIdentity.inode
        )
    }

    init(
        applicationSupportURL: URL,
        cachesDirectoryURL: URL,
        temporaryDirectoryURL: URL
    ) throws {
        let support = applicationSupportURL.standardizedFileURL
        let caches = cachesDirectoryURL.standardizedFileURL
        let temporary = temporaryDirectoryURL.standardizedFileURL
        guard support.isFileURL, caches.isFileURL, temporary.isFileURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        let supportDescriptor = Darwin.open(
            support.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard supportDescriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        var retained = [supportDescriptor]
        var succeeded = false
        defer {
            if !succeeded {
                for descriptor in retained.reversed() {
                    _ = Darwin.close(descriptor)
                }
            }
        }
        let cachesDescriptor = Darwin.open(
            caches.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard cachesDescriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        retained.append(cachesDescriptor)
        let temporaryDescriptor = Darwin.open(
            temporary.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard temporaryDescriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        retained.append(temporaryDescriptor)

        self.applicationSupportURL = support
        self.cachesDirectoryURL = caches
        self.temporaryDirectoryURL = temporary
        self.applicationSupportDescriptor = supportDescriptor
        self.cachesDescriptor = cachesDescriptor
        self.temporaryDescriptor = temporaryDescriptor
        self.applicationSupportIdentity = try Self.identity(supportDescriptor)
        self.cachesIdentity = try Self.identity(cachesDescriptor)
        self.temporaryIdentity = try Self.identity(temporaryDescriptor)
        succeeded = true
    }

    deinit {
        _ = Darwin.close(temporaryDescriptor)
        _ = Darwin.close(cachesDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func verifyTargets() throws {
        try verify()
        for name in [
            "FieldEvidenceRestore",
            "FieldEvidenceOperations",
            "FieldEvidenceCommerce",
            "FieldEvidenceDiagnostics",
            "FieldEvidenceErase",
        ] {
            try Self.requireAbsentOrValidDirectory(
                parent: applicationSupportDescriptor,
                name: name
            )
        }
        try Self.requireAbsentOrValidDirectory(
            parent: cachesDescriptor,
            name: "FieldEvidenceApp"
        )
        try Self.requireAbsentOrValidDirectory(
            parent: temporaryDescriptor,
            name: "FieldEvidenceApp"
        )
        try verify()
    }

    func requireNoEraseIntent() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.names(in: descriptor).isEmpty else {
            throw EraseAllServiceError.recoveryRequired
        }
        try verify()
    }

    func requireNoRestoreIntent() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceRestore",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT {
            try verify()
            return
        }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try !Self.itemExists(parent: descriptor, name: "restore.json"),
              try !Self.itemExists(
                parent: descriptor,
                name: ".restore.json.next"
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
    }

    func removeFrozenTargets() throws {
        try verifyTargets()
        for name in [
            "FieldEvidenceRestore",
            "FieldEvidenceOperations",
            "FieldEvidenceCommerce",
            "FieldEvidenceDiagnostics",
        ] {
            try Self.removeDirectoryIfPresent(
                parent: applicationSupportDescriptor,
                name: name
            )
        }
        try Self.removeDirectoryIfPresent(
            parent: cachesDescriptor,
            name: "FieldEvidenceApp"
        )
        try Self.removeDirectoryIfPresent(
            parent: temporaryDescriptor,
            name: "FieldEvidenceApp"
        )
        try verify()
    }

    func verifyTargetsRemovedExceptDiagnostics() throws {
        try verify()
        for name in [
            "FieldEvidenceRestore",
            "FieldEvidenceOperations",
            "FieldEvidenceCommerce",
        ] {
            guard try !Self.itemExists(
                parent: applicationSupportDescriptor,
                name: name
            ) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard try !Self.itemExists(
            parent: cachesDescriptor,
            name: "FieldEvidenceApp"
        ),
              try !Self.itemExists(
                parent: temporaryDescriptor,
                name: "FieldEvidenceApp"
              ) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try Self.requireAbsentOrDirectory(
            parent: applicationSupportDescriptor,
            name: "FieldEvidenceDiagnostics"
        )
        try verify()
    }

    func verifyDiagnostics(expectedData: Data) throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceDiagnostics",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.names(in: descriptor) == ["counters.json"],
              try Self.readRegularFile(
                parent: descriptor,
                name: "counters.json"
              ) == expectedData else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
    }

    func createZeroDiagnostics(data: Data) throws {
        try verify()
        guard Darwin.mkdirat(
            applicationSupportDescriptor,
            "FieldEvidenceDiagnostics",
            mode_t(0o700)
        ) == 0,
              Darwin.fsync(applicationSupportDescriptor) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        let directory = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceDiagnostics",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard directory >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(directory) }
        let expectedDirectory = try Self.identity(directory)
        let file = Darwin.openat(
            directory,
            "counters.json",
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard file >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        do {
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(
                        file,
                        base.advanced(by: offset),
                        raw.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else if errno != EINTR {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            }
            guard Darwin.fsync(file) == 0 else {
                throw EraseAllServiceError.invalidAuthority
            }
        } catch {
            _ = Darwin.close(file)
            throw error
        }
        _ = Darwin.close(file)
        guard Darwin.fsync(directory) == 0,
              try Self.directoryIdentity(
                parent: applicationSupportDescriptor,
                name: "FieldEvidenceDiagnostics"
              ) == expectedDirectory,
              try Self.names(in: directory) == ["counters.json"],
              try Self.readRegularFile(
                parent: directory,
                name: "counters.json"
              ) == data else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
    }

    func removeEraseRootIfEmpty() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.names(in: descriptor).isEmpty,
              Darwin.unlinkat(
                applicationSupportDescriptor,
                "FieldEvidenceErase",
                AT_REMOVEDIR
              ) == 0,
              Darwin.fsync(applicationSupportDescriptor) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try verify()
    }

    private func verify() throws {
        try Self.require(applicationSupportDescriptor, applicationSupportIdentity)
        try Self.require(cachesDescriptor, cachesIdentity)
        try Self.require(temporaryDescriptor, temporaryIdentity)
        try Self.requirePath(applicationSupportURL, applicationSupportIdentity)
        try Self.requirePath(cachesDirectoryURL, cachesIdentity)
        try Self.requirePath(temporaryDirectoryURL, temporaryIdentity)
    }

    private static func removeDirectoryIfPresent(
        parent: Int32,
        name: String
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        let expected: Identity
        do {
            expected = try identity(descriptor)
            try removeContents(descriptor)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
        _ = Darwin.close(descriptor)
        guard try directoryIdentity(parent: parent, name: name) == expected,
              Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0,
              Darwin.fsync(parent) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func removeContents(_ directory: Int32) throws {
        for name in try names(in: directory) {
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw EraseAllServiceError.invalidAuthority
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                try removeDirectoryIfPresent(parent: directory, name: name)
            case S_IFREG:
                guard info.st_nlink == 1,
                      Darwin.unlinkat(directory, name, 0) == 0 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            default:
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard Darwin.fsync(directory) == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func requireAbsentOrDirectory(
        parent: Int32,
        name: String
    ) throws {
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else {
                throw EraseAllServiceError.invalidAuthority
            }
            return
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func requireAbsentOrValidDirectory(
        parent: Int32,
        name: String
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        let expected = try identity(descriptor)
        try validateContents(descriptor)
        guard try directoryIdentity(parent: parent, name: name) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func validateContents(_ directory: Int32) throws {
        for name in try names(in: directory) {
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw EraseAllServiceError.invalidAuthority
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let child = Darwin.openat(
                    directory,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                do {
                    let opened = try identity(child)
                    guard opened.device == info.st_dev,
                          opened.inode == info.st_ino else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    try validateContents(child)
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
            case S_IFREG:
                guard info.st_nlink == 1 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            default:
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }

    private static func itemExists(parent: Int32, name: String) throws -> Bool {
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            return true
        }
        guard errno == ENOENT else {
            throw EraseAllServiceError.invalidAuthority
        }
        return false
    }

    private static func directoryIdentity(
        parent: Int32,
        name: String
    ) throws -> Identity {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        return try identity(descriptor)
    }

    private static func names(in descriptor: Int32) throws -> [String] {
        let independent = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard independent >= 0,
              let directory = Darwin.fdopendir(independent) else {
            if independent >= 0 { _ = Darwin.close(independent) }
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.closedir(directory) }
        var result = [String]()
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { result.append(name) }
            errno = 0
        }
        guard errno == 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        return result.sorted()
    }

    private static func readRegularFile(
        parent: Int32,
        name: String
    ) throws -> Data {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw EraseAllServiceError.invalidAuthority
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                result.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        guard result.count == Int(info.st_size) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return result
    }

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func require(
        _ descriptor: Int32,
        _ expected: Identity
    ) throws {
        guard try identity(descriptor) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    private static func requirePath(
        _ url: URL,
        _ expected: Identity
    ) throws {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        guard try identity(descriptor) == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

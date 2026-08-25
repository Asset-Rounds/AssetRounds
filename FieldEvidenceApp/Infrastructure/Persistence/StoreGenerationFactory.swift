import Darwin
import Foundation
import SwiftData

struct StoreApplicationSupportIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}

enum StoreGenerationFailure: Error, Equatable {
    case dataPointerInvalid
    case dataGenerationMissing
}

private enum StorePointerSchemaRegistry {
    static let currentVersion = 1
    static let retiredVersion = 1

    static func requireCurrent(_ version: Int) throws {
        guard version == currentVersion else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    static func requireRetired(_ version: Int) throws {
        guard version == retiredVersion else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }
}

@MainActor
final class StoreGenerationSession {
    let generationID: UUID
    let generationRootURL: URL
    let modelContext: ModelContext

    private let modelContainer: ModelContainer
    private let afterSaveReproof: () throws -> Void
    private var didSaveObserver: NSObjectProtocol? = nil
    private var afterSaveFailure: Error? = nil

    fileprivate init(
        generationID: UUID,
        generationRootURL: URL,
        modelContainer: ModelContainer,
        afterSaveReproof: @escaping () throws -> Void
    ) {
        self.generationID = generationID
        self.generationRootURL = generationRootURL
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
        self.afterSaveReproof = afterSaveReproof
        let context = self.modelContext
        self.didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAutomaticSaveReproof()
            }
        }
    }

    deinit {
        if let didSaveObserver {
            NotificationCenter.default.removeObserver(didSaveObserver)
        }
    }

    private func handleAutomaticSaveReproof() {
        guard afterSaveFailure == nil else { return }
        do {
            try afterSaveReproof()
        } catch {
            recordAfterSaveFailure(error)
        }
    }

    private func recordAfterSaveFailure(_ error: Error) {
        guard afterSaveFailure == nil else { return }
        afterSaveFailure = error
        modelContext.autosaveEnabled = false
    }

    /// Revalidates the closed generation file set and protection policy after a
    /// successful ModelContext save. Automatic didSave reproof failures are
    /// retained and surfaced here; callers retain ownership of the save.
    func reproofAfterSave() throws {
        if let afterSaveFailure {
            throw afterSaveFailure
        }
        do {
            try afterSaveReproof()
        } catch {
            recordAfterSaveFailure(error)
            throw error
        }
    }
}

/// Descriptor-pinned authority used only by atomic backup restore. It keeps the
/// installed and restore-staging generation parents bound to the same directory
/// identities for the complete restore/recovery operation, so a renamed or
/// replaced ancestor can never redirect a cleanup or installation mutation.
final class StoreRestoreGenerationAuthority {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    fileprivate struct RegularFileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
    }

    fileprivate struct RegularFileRead {
        let data: Data
        let identity: RegularFileIdentity
    }

    struct Presence {
        let staging: Bool
        let installed: Bool
    }

    struct Tree: Equatable {
        let directories: Set<String>
        let files: Set<String>
    }

    final class InstalledGenerationHandle {
        fileprivate let id: UUID
        fileprivate let descriptor: Int32
        fileprivate let identity: Identity

        fileprivate init(id: UUID, descriptor: Int32, identity: Identity) {
            self.id = id
            self.descriptor = descriptor
            self.identity = identity
        }

        deinit {
            _ = Darwin.close(descriptor)
        }
    }

    private static let dataName = "FieldEvidenceData"
    private static let restoreName = "FieldEvidenceRestore"
    private static let generationsName = "generations"
    private static let importStagingName = "staging"
    private static let pointerMutationLock = NSLock()
    fileprivate static let generationStoreNames: Set<String> = [
        "model.sqlite",
        "model.sqlite-wal",
        "model.sqlite-shm"
    ]

    private let applicationSupportURL: URL
    private let applicationSupportDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let dataDescriptor: Int32
    private let dataIdentity: Identity
    private let installedGenerationsDescriptor: Int32
    private let installedGenerationsIdentity: Identity
    private let restoreDescriptor: Int32
    private let restoreIdentity: Identity
    private let stagingGenerationsDescriptor: Int32
    private let stagingGenerationsIdentity: Identity
    private let importStagingDescriptor: Int32
    private let importStagingIdentity: Identity

    init(
        applicationSupportURL: URL,
        expectedApplicationSupportIdentity: StoreApplicationSupportIdentity? = nil
    ) throws {
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else { throw StoreGenerationFailure.dataPointerInvalid }
        let app = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard app >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        var retained = [app]
        var succeeded = false
        defer {
            if !succeeded {
                for descriptor in retained.reversed() { _ = Darwin.close(descriptor) }
            }
        }

        let appIdentity = try Self.identity(app)
        if let expectedApplicationSupportIdentity {
            guard appIdentity.device == expectedApplicationSupportIdentity.device,
                  appIdentity.inode == expectedApplicationSupportIdentity.inode else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        let data = try Self.openDirectory(parent: app, name: Self.dataName)
        retained.append(data)
        let dataIdentity = try Self.identity(data)
        let installed = try Self.openDirectory(
            parent: data,
            name: Self.generationsName
        )
        retained.append(installed)
        let installedIdentity = try Self.identity(installed)
        let restore = try Self.openOrCreateDirectory(
            parent: app,
            name: Self.restoreName
        )
        retained.append(restore)
        let restoreIdentity = try Self.identity(restore)
        let stagingGenerations = try Self.openOrCreateDirectory(
            parent: restore,
            name: Self.generationsName
        )
        retained.append(stagingGenerations)
        let stagingGenerationsIdentity = try Self.identity(stagingGenerations)
        let importStaging = try Self.openOrCreateDirectory(
            parent: restore,
            name: Self.importStagingName
        )
        retained.append(importStaging)
        let importStagingIdentity = try Self.identity(importStaging)

        self.applicationSupportURL = root
        self.applicationSupportDescriptor = app
        self.applicationSupportIdentity = appIdentity
        self.dataDescriptor = data
        self.dataIdentity = dataIdentity
        self.installedGenerationsDescriptor = installed
        self.installedGenerationsIdentity = installedIdentity
        self.restoreDescriptor = restore
        self.restoreIdentity = restoreIdentity
        self.stagingGenerationsDescriptor = stagingGenerations
        self.stagingGenerationsIdentity = stagingGenerationsIdentity
        self.importStagingDescriptor = importStaging
        self.importStagingIdentity = importStagingIdentity
        try protectAuthorityRoots()
        succeeded = true
    }

    deinit {
        _ = Darwin.close(importStagingDescriptor)
        _ = Darwin.close(stagingGenerationsDescriptor)
        _ = Darwin.close(restoreDescriptor)
        _ = Darwin.close(installedGenerationsDescriptor)
        _ = Darwin.close(dataDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    private var dataURL: URL {
        applicationSupportURL.appendingPathComponent(Self.dataName, isDirectory: true)
    }

    private var installedGenerationsURL: URL {
        dataURL.appendingPathComponent(Self.generationsName, isDirectory: true)
    }

    private var restoreURL: URL {
        applicationSupportURL.appendingPathComponent(Self.restoreName, isDirectory: true)
    }

    private var stagingGenerationsURL: URL {
        restoreURL.appendingPathComponent(Self.generationsName, isDirectory: true)
    }

    private var importStagingURL: URL {
        restoreURL.appendingPathComponent(Self.importStagingName, isDirectory: true)
    }

    private func enforce(
        _ kind: OwnedFileKindV1,
        at url: URL,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws {
        do {
            let root = applicationSupportURL.standardizedFileURL
            let target = url.standardizedFileURL
            let insideRoot = root.path == "/"
                ? target.path.hasPrefix("/")
                : target.path.hasPrefix(root.path + "/")
            guard insideRoot else {
                throw ProtectedFilePolicyError.invalidRelativePath
            }
            let relativePath = String(target.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: relativePath,
                within: root,
                authorityCheck: {
                    try self.verify()
                    try authorityCheck()
                }
            )
        } catch let failure as StoreGenerationFailure {
            throw failure
        } catch let error as ProtectedFilePolicyError
            where error == .protectedDataUnavailable {
            throw error
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func enforceGenerationFile(
        descriptor: Int32,
        root: URL,
        name: String,
        kind: OwnedFileKindV1
    ) throws {
        try Self.requireSafeBasename(name)
        let generationIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        )
        let fileDescriptor = Darwin.openat(
            descriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard fileDescriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(fileDescriptor) }
        let fileIdentity = try Self.regularFileIdentity(descriptor: fileDescriptor)
        let url = root.appendingPathComponent(name, isDirectory: false)
        try enforce(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: descriptor
                      ) == generationIdentity,
                      try Self.directoryIdentity(at: root) == generationIdentity,
                      try Self.regularFileIdentity(descriptor: fileDescriptor)
                          == fileIdentity,
                      try Self.regularFileIdentity(at: url) == fileIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )
    }

    private func protectAuthorityRoots() throws {
        try enforce(.durableDirectory, at: dataURL)
        try enforce(.durableDirectory, at: installedGenerationsURL)
        try enforce(.stagingDirectory, at: restoreURL)
        try enforce(.stagingDirectory, at: stagingGenerationsURL)
        try enforce(.stagingDirectory, at: importStagingURL)
    }

    private func protectKnownStoreFiles(
        parent: Int32,
        id: UUID,
        root: URL,
        rootKind: OwnedFileKindV1,
        requireModel: Bool = false
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            Self.canonical(id),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }

        let generationIdentity = try Self.identity(descriptor)
        try enforce(
            rootKind,
            at: root,
            authorityCheck: {
                guard try Self.identity(descriptor) == generationIdentity,
                      try Self.directoryIdentity(at: root) == generationIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )

        let before = try Self.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )

        let modelKind: OwnedFileKindV1 = rootKind == .restoreStaging
            ? .stagingFile
            : .database
        let walKind: OwnedFileKindV1 = rootKind == .restoreStaging
            ? .stagingFile
            : .databaseWAL
        let shmKind: OwnedFileKindV1 = rootKind == .restoreStaging
            ? .stagingFile
            : .databaseSHM

        for name in before {
            let kind: OwnedFileKindV1
            switch name {
            case "model.sqlite": kind = modelKind
            case "model.sqlite-wal": kind = walKind
            case "model.sqlite-shm": kind = shmKind
            default: throw StoreGenerationFailure.dataPointerInvalid
            }
            try enforceGenerationFile(
                descriptor: descriptor,
                root: root,
                name: name,
                kind: kind
            )
        }
        let after = try Self.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )
        guard before == after else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func protectStagingGeneration(
        id: UUID,
        requireModel: Bool = false
    ) throws {
        try requireStagingGeneration(id: id)
        let root = stagingGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        try protectKnownStoreFiles(
            parent: stagingGenerationsDescriptor,
            id: id,
            root: root,
            rootKind: .restoreStaging,
            requireModel: requireModel
        )
        try requireStagingGeneration(id: id)
    }

    func protectInstalledGeneration(
        id: UUID,
        requireModel: Bool = false
    ) throws {
        try requireInstalledGeneration(id: id)
        let root = installedGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        try protectKnownStoreFiles(
            parent: installedGenerationsDescriptor,
            id: id,
            root: root,
            rootKind: .durableDirectory,
            requireModel: requireModel
        )
        try requireInstalledGeneration(id: id)
    }

    func protectStagingFile(
        id: UUID,
        name: String,
        kind: OwnedFileKindV1,
        ifPresent: Bool = false
    ) throws {
        try Self.requireSafeBasename(name)
        try requireStagingGeneration(id: id)
        let root = stagingGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        let descriptor = Darwin.openat(
            stagingGenerationsDescriptor,
            Self.canonical(id),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        if ifPresent, try !Self.itemExists(parent: descriptor, name: name) { return }
        try enforceGenerationFile(
            descriptor: descriptor,
            root: root,
            name: name,
            kind: kind
        )
        try requireStagingGeneration(id: id)
    }

    func protectInstalledFile(
        id: UUID,
        name: String,
        kind: OwnedFileKindV1,
        ifPresent: Bool = false
    ) throws {
        try Self.requireSafeBasename(name)
        try requireInstalledGeneration(id: id)
        let root = installedGenerationsURL.appendingPathComponent(
            Self.canonical(id),
            isDirectory: true
        )
        let descriptor = Darwin.openat(
            installedGenerationsDescriptor,
            Self.canonical(id),
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        if ifPresent, try !Self.itemExists(parent: descriptor, name: name) { return }
        try enforceGenerationFile(
            descriptor: descriptor,
            root: root,
            name: name,
            kind: kind
        )
        try requireInstalledGeneration(id: id)
    }

    fileprivate static func requireSafeBasename(_ name: String) throws {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\") else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    fileprivate static func requireExactGenerationContents(
        parent: Int32,
        requireModel: Bool
    ) throws {
        _ = try exactGenerationEntries(parent: parent, requireModel: requireModel)
    }

    fileprivate static func exactGenerationEntries(
        parent: Int32,
        requireModel: Bool
    ) throws -> Set<String> {
        let entries = Set(try Self.names(in: parent))
        guard entries.isSubset(of: Self.generationStoreNames) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let hasModel = entries.contains("model.sqlite")
        guard !requireModel || hasModel else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        guard hasModel ||
                (!entries.contains("model.sqlite-wal") &&
                 !entries.contains("model.sqlite-shm")) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        for name in entries {
            var info = stat()
            guard Darwin.fstatat(
                parent,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_nlink == 1 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        return entries
    }

    func verify() throws {
        try Self.require(applicationSupportDescriptor, applicationSupportIdentity)
        try Self.require(dataDescriptor, dataIdentity)
        try Self.require(installedGenerationsDescriptor, installedGenerationsIdentity)
        try Self.require(restoreDescriptor, restoreIdentity)
        try Self.require(stagingGenerationsDescriptor, stagingGenerationsIdentity)
        try Self.require(importStagingDescriptor, importStagingIdentity)

        let app = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard app >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(app) }
        guard try Self.identity(app) == applicationSupportIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let data = try Self.openDirectory(parent: app, name: Self.dataName)
        defer { _ = Darwin.close(data) }
        guard try Self.identity(data) == dataIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let installed = try Self.openDirectory(
            parent: data,
            name: Self.generationsName
        )
        defer { _ = Darwin.close(installed) }
        guard try Self.identity(installed) == installedGenerationsIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let restore = try Self.openDirectory(parent: app, name: Self.restoreName)
        defer { _ = Darwin.close(restore) }
        guard try Self.identity(restore) == restoreIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let stagingGenerations = try Self.openDirectory(
            parent: restore,
            name: Self.generationsName
        )
        defer { _ = Darwin.close(stagingGenerations) }
        guard try Self.identity(stagingGenerations) == stagingGenerationsIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let importStaging = try Self.openDirectory(
            parent: restore,
            name: Self.importStagingName
        )
        defer { _ = Darwin.close(importStaging) }
        guard try Self.identity(importStaging) == importStagingIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func requireNoEraseAuthority() throws {
        try verify()
        let descriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        let expected = try Self.identity(descriptor)
        guard try Self.names(in: descriptor).isEmpty else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let reopened = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceErase",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopened >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(reopened) }
        guard try Self.identity(reopened) == expected else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
    }

    func requireNoRestoreJournal() throws {
        try verify()
        guard try !Self.itemExists(
            parent: restoreDescriptor,
            name: "restore.json"
        ),
              try !Self.itemExists(
                parent: restoreDescriptor,
                name: ".restore.json.next"
              ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
    }

    func presence(id: UUID) throws -> Presence {
        try verify()
        let name = Self.canonical(id)
        return Presence(
            staging: try Self.directoryPresence(
                parent: stagingGenerationsDescriptor,
                name: name
            ),
            installed: try Self.directoryPresence(
                parent: installedGenerationsDescriptor,
                name: name
            )
        )
    }

    func currentGenerationID() throws -> UUID {
        try verify()
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent("current.json", isDirectory: false)
        )
        let value: CurrentPointerV1 = try Self.decodeCanonicalPointer(
            parent: dataDescriptor,
            name: "current.json"
        )
        try StorePointerSchemaRegistry.requireCurrent(value.schemaVersion)
        guard let id = UUID(uuidString: value.generationID),
              Self.canonical(id) == value.generationID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return id
    }

    func retiredGenerationIDs() throws -> [UUID] {
        try verify()
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent("retired.json", isDirectory: false)
        )
        let value: RetiredPointerV1 = try Self.decodeCanonicalPointer(
            parent: dataDescriptor,
            name: "retired.json"
        )
        try StorePointerSchemaRegistry.requireRetired(value.schemaVersion)
        guard value.generationIDs == value.generationIDs.sorted(),
              Set(value.generationIDs).count == value.generationIDs.count else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let ids = value.generationIDs.compactMap(UUID.init(uuidString:))
        guard ids.count == value.generationIDs.count,
              zip(ids, value.generationIDs).allSatisfy({
                  Self.canonical($0.0) == $0.1
              }) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return ids
    }

    func switchCurrentGeneration(expected oldID: UUID, to newID: UUID) throws {
        try verify()
        guard oldID != newID,
              try currentGenerationID() == oldID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(oldID)
        )
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(newID)
        )
        try replacePointer(
            name: "current.json",
            value: CurrentPointerV1(
                generationID: Self.canonical(newID),
                schemaVersion: StorePointerSchemaRegistry.currentVersion
            )
        )
        guard try currentGenerationID() == newID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func retireGeneration(oldID: UUID, currentID: UUID) throws {
        try verify()
        guard oldID != currentID,
              try currentGenerationID() == currentID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(oldID)
        )
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(currentID)
        )
        let retired = try retiredGenerationIDs()
        guard !retired.contains(currentID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let values = Array(Set(retired + [oldID])).sorted {
            Self.canonical($0) < Self.canonical($1)
        }
        try replacePointer(
            name: "retired.json",
            value: RetiredPointerV1(
                generationIDs: values.map(Self.canonical),
                schemaVersion: StorePointerSchemaRegistry.retiredVersion
            )
        )
        guard try retiredGenerationIDs() == values else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func createStagingGeneration(id: UUID) throws {
        try verify()
        let name = Self.canonical(id)
        guard try !Self.itemExists(parent: stagingGenerationsDescriptor, name: name),
              try !Self.itemExists(parent: installedGenerationsDescriptor, name: name),
              Darwin.mkdirat(
                  stagingGenerationsDescriptor,
                  name,
                  mode_t(0o700)
              ) == 0,
              Darwin.fsync(stagingGenerationsDescriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
        guard try Self.directoryPresence(
            parent: stagingGenerationsDescriptor,
            name: name
        ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try enforce(
            .restoreStaging,
            at: stagingGenerationsURL.appendingPathComponent(name, isDirectory: true)
        )
    }

    func createInstalledGeneration(id: UUID) throws -> InstalledGenerationHandle {
        try verify()
        let name = Self.canonical(id)
        guard try !Self.itemExists(parent: stagingGenerationsDescriptor, name: name),
              try !Self.itemExists(parent: installedGenerationsDescriptor, name: name),
              Darwin.mkdirat(
                  installedGenerationsDescriptor,
                  name,
                  mode_t(0o700)
              ) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let descriptor = Darwin.openat(
            installedGenerationsDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            _ = Darwin.unlinkat(
                installedGenerationsDescriptor,
                name,
                AT_REMOVEDIR
            )
            _ = Darwin.fsync(installedGenerationsDescriptor)
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var createdIdentity: Identity?
        do {
            let identity = try Self.identity(descriptor)
            createdIdentity = identity
            guard Darwin.fsync(installedGenerationsDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verify()
            try Self.require(descriptor, identity)
            guard try Self.requiredDirectoryIdentity(
                parent: installedGenerationsDescriptor,
                name: name
            ) == identity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try protectInstalledGeneration(id: id)
            return InstalledGenerationHandle(
                id: id,
                descriptor: descriptor,
                identity: identity
            )
        } catch {
            if let createdIdentity,
               let currentIdentity = try? Self.requiredDirectoryIdentity(
                   parent: installedGenerationsDescriptor,
                   name: name
               ), currentIdentity == createdIdentity {
                _ = Darwin.unlinkat(
                    installedGenerationsDescriptor,
                    name,
                    AT_REMOVEDIR
                )
                _ = Darwin.fsync(installedGenerationsDescriptor)
            }
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    func modelStoreURL(
        for handle: InstalledGenerationHandle,
        name: String
    ) throws -> URL {
        try Self.requireSafeBasename(name)
        try requireInstalledGeneration(handle)
        let root = try Self.currentURL(for: handle.descriptor)
        guard root.isFileURL,
              root.lastPathComponent == Self.canonical(handle.id) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let reopened = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopened >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(reopened) }
        guard try Self.identity(reopened) == handle.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try requireInstalledGeneration(handle)
        return root.appendingPathComponent(name, isDirectory: false)
    }

    func requireRegularFile(
        named name: String,
        in handle: InstalledGenerationHandle
    ) throws {
        try Self.requireSafeBasename(name)
        try requireInstalledGeneration(handle)
        let descriptor = Darwin.openat(
            handle.descriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Darwin.fsync(descriptor) == 0,
              Darwin.fsync(handle.descriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let before = try Self.exactGenerationEntries(
            parent: handle.descriptor,
            requireModel: true
        )
        guard before.contains(name) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        if name == "model.sqlite" {
            let root = try Self.currentURL(for: handle.descriptor)
            for entry in before {
                let kind: OwnedFileKindV1
                switch entry {
                case "model.sqlite": kind = .database
                case "model.sqlite-wal": kind = .databaseWAL
                case "model.sqlite-shm": kind = .databaseSHM
                default: throw StoreGenerationFailure.dataPointerInvalid
                }
                try enforceGenerationFile(
                    descriptor: handle.descriptor,
                    root: root,
                    name: entry,
                    kind: kind
                )
            }
        }
        let after = try Self.exactGenerationEntries(
            parent: handle.descriptor,
            requireModel: true
        )
        guard before == after else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try requireInstalledGeneration(handle)
    }

    func requireInstalledGeneration(
        _ handle: InstalledGenerationHandle
    ) throws {
        try verify()
        try Self.require(handle.descriptor, handle.identity)
        guard try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(handle.id)
        ) == handle.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func removeCreatedInstalledGeneration(
        _ handle: InstalledGenerationHandle
    ) throws {
        try Self.require(handle.descriptor, handle.identity)
        let currentURL = try Self.currentURL(for: handle.descriptor)
        let parentURL = currentURL.deletingLastPathComponent()
        let parent = Darwin.open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parent >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(parent) }
        guard try Self.identity(parent) == installedGenerationsIdentity,
              try Self.requiredDirectoryIdentity(
                  parent: parent,
                  name: currentURL.lastPathComponent
              ) == handle.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try Self.removeContents(of: handle.descriptor)
        guard try Self.requiredDirectoryIdentity(
            parent: parent,
            name: currentURL.lastPathComponent
        ) == handle.identity,
              Darwin.unlinkat(
                  parent,
                  currentURL.lastPathComponent,
                  AT_REMOVEDIR
              ) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func installStagingGeneration(id: UUID) throws {
        try verify()
        let name = Self.canonical(id)
        try protectStagingGeneration(id: id, requireModel: true)
        let sourceIdentity = try Self.requiredDirectoryIdentity(
            parent: stagingGenerationsDescriptor,
            name: name
        )
        guard try !Self.itemExists(parent: installedGenerationsDescriptor, name: name),
              Darwin.renameatx_np(
                  stagingGenerationsDescriptor,
                  name,
                  installedGenerationsDescriptor,
                  name,
                  UInt32(RENAME_EXCL)
              ) == 0,
              Darwin.fsync(stagingGenerationsDescriptor) == 0,
              Darwin.fsync(installedGenerationsDescriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
        guard try !Self.itemExists(parent: stagingGenerationsDescriptor, name: name),
              try Self.requiredDirectoryIdentity(
                  parent: installedGenerationsDescriptor,
                  name: name
              ) == sourceIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protectInstalledGeneration(id: id, requireModel: true)
    }

    func requireStagingGeneration(id: UUID) throws {
        try verify()
        _ = try Self.requiredDirectoryIdentity(
            parent: stagingGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func requireInstalledGeneration(id: UUID) throws {
        try verify()
        _ = try Self.requiredDirectoryIdentity(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func stagingTree(id: UUID) throws -> Tree {
        try tree(parent: stagingGenerationsDescriptor, id: id)
    }

    func installedTree(id: UUID) throws -> Tree {
        try tree(parent: installedGenerationsDescriptor, id: id)
    }

    func removeStagingGeneration(id: UUID) throws {
        try removeDirectory(
            parent: stagingGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func removeInstalledGeneration(id: UUID) throws {
        try removeDirectory(
            parent: installedGenerationsDescriptor,
            name: Self.canonical(id)
        )
    }

    func replaceRetiredGenerationIDs(
        expected: [UUID],
        with replacement: [UUID],
        currentID: UUID
    ) throws {
        try verify()
        guard try currentGenerationID() == currentID,
              try retiredGenerationIDs() == expected,
              !replacement.contains(currentID),
              Set(replacement).count == replacement.count,
              replacement == replacement.sorted(by: Self.idOrder) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try replacePointer(
            name: "retired.json",
            value: RetiredPointerV1(
                generationIDs: replacement.map(Self.canonical),
                schemaVersion: StorePointerSchemaRegistry.retiredVersion
            )
        )
        guard try retiredGenerationIDs() == replacement else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func restoreGenerationNames() throws -> [String] {
        try verify()
        return try Self.names(in: stagingGenerationsDescriptor)
    }

    func installedGenerationNames() throws -> [String] {
        try verify()
        return try Self.names(in: installedGenerationsDescriptor)
    }

    func importStagingNames() throws -> [String] {
        try verify()
        return try Self.names(in: importStagingDescriptor)
    }

    func removeImportStagingPackage(name: String) throws {
        try Self.requireSafeBasename(name)
        try removeDirectory(parent: importStagingDescriptor, name: name)
    }

    private func replacePointer<Value: Encodable>(
        name: String,
        value: Value
    ) throws {
        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        try verify()
        try enforce(
            .generationPointer,
            at: dataURL.appendingPathComponent(name, isDirectory: false)
        )
        let expectedRead = try Self.readRegularFileWithIdentity(
            parent: dataDescriptor,
            name: name
        )
        let expectedIdentity = expectedRead.identity
        let expected = expectedRead.data
        let replacement = try Self.canonicalData(value)
        let temporary = ".\(name).restore-next"
        if try Self.itemExists(parent: dataDescriptor, name: temporary) {
            try enforce(
                .generationPointerTemporary,
                at: dataURL.appendingPathComponent(temporary, isDirectory: false)
            )
            let existingTemporary = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: temporary
            )
            let existingCurrent = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            guard existingTemporary.data == replacement,
                  existingTemporary.identity.linkCount == 1,
                  existingCurrent.data == expected,
                  existingCurrent.identity == expectedIdentity,
                  Darwin.unlinkat(dataDescriptor, temporary, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verify()
        }
        try Self.createRegularFile(
            parent: dataDescriptor,
            name: temporary,
            data: replacement
        )
        try enforce(
            .generationPointerTemporary,
            at: dataURL.appendingPathComponent(temporary, isDirectory: false)
        )
        let replacementIdentity = try Self.regularFileIdentity(
            parent: dataDescriptor,
            name: temporary
        )
        var published = false
        let publishedIdentity = replacementIdentity
        do {
            try verify()
            let currentBeforeSwap = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            guard currentBeforeSwap.identity == expectedIdentity,
                  currentBeforeSwap.data == expected,
                  Darwin.renameatx_np(
                      dataDescriptor,
                      temporary,
                      dataDescriptor,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            published = true
            guard Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verify()
            try enforce(
                .generationPointer,
                at: dataURL.appendingPathComponent(name, isDirectory: false)
            )
            let currentAfterSwap = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            let oldTemporary = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: temporary
            )
            guard currentAfterSwap.data == replacement,
                  currentAfterSwap.identity == replacementIdentity,
                  oldTemporary.data == expected,
                  oldTemporary.identity == expectedIdentity,
                  Darwin.unlinkat(dataDescriptor, temporary, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            if published,
               let current = try? Self.readRegularFileWithIdentity(
                   parent: dataDescriptor,
                   name: name
               ),
               current.data == replacement,
               current.identity == publishedIdentity {
                do {
                    let oldTemporary = try Self.readRegularFileWithIdentity(
                        parent: dataDescriptor,
                        name: temporary
                    )
                    guard oldTemporary.data == expected,
                          oldTemporary.identity == expectedIdentity,
                          Darwin.renameatx_np(
                              dataDescriptor,
                              name,
                              dataDescriptor,
                              temporary,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(dataDescriptor) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                    try verify()
                    try enforce(
                        .generationPointer,
                        at: dataURL.appendingPathComponent(name, isDirectory: false)
                    )
                    let restored = try Self.readRegularFileWithIdentity(
                        parent: dataDescriptor,
                        name: name
                    )
                    let replacementTemporary = try Self.readRegularFileWithIdentity(
                        parent: dataDescriptor,
                        name: temporary
                    )
                    guard restored.data == expected,
                          restored.identity == expectedIdentity,
                          replacementTemporary.data == replacement,
                          replacementTemporary.identity == replacementIdentity,
                          Darwin.unlinkat(dataDescriptor, temporary, 0) == 0,
                          Darwin.fsync(dataDescriptor) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            if let temporaryData = try? Self.readRegularFile(
                parent: dataDescriptor,
                name: temporary
            ), temporaryData == replacement {
                _ = Darwin.unlinkat(dataDescriptor, temporary, 0)
                _ = Darwin.fsync(dataDescriptor)
            }
            throw error
        }
    }

    private func restorePointer(
        name: String,
        data: Data,
        expectedCurrentIdentity: RegularFileIdentity? = nil
    ) throws {
        let rollback = ".\(name).restore-rollback"
        let replacedIdentity = try Self.regularFileIdentity(
            parent: dataDescriptor,
            name: name
        )
        if let expectedCurrentIdentity {
            guard replacedIdentity == expectedCurrentIdentity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        if try Self.itemExists(parent: dataDescriptor, name: rollback) {
            guard try Self.readRegularFile(parent: dataDescriptor, name: rollback)
                    == data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            guard Darwin.unlinkat(dataDescriptor, rollback, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        try Self.createRegularFile(
            parent: dataDescriptor,
            name: rollback,
            data: data
        )
        try enforce(
            .generationPointerTemporary,
            at: dataURL.appendingPathComponent(rollback, isDirectory: false)
        )
        let publishedIdentity = try Self.regularFileIdentity(
            parent: dataDescriptor,
            name: rollback
        )
        var swapped = false
        do {
            guard try Self.regularFileIdentity(
                      parent: dataDescriptor,
                      name: name
                  ) == replacedIdentity,
                  Darwin.renameatx_np(
                      dataDescriptor,
                      rollback,
                      dataDescriptor,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = true
            guard Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try enforce(
                .generationPointer,
                at: dataURL.appendingPathComponent(name, isDirectory: false)
            )
            let restored = try Self.readRegularFileWithIdentity(
                parent: dataDescriptor,
                name: name
            )
            let replaced = try Self.regularFileIdentity(
                parent: dataDescriptor,
                name: rollback
            )
            guard restored.data == data,
                  restored.identity == publishedIdentity,
                  replaced == replacedIdentity,
                  Darwin.unlinkat(dataDescriptor, rollback, 0) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = false
        } catch {
            if swapped,
               let currentIdentity = try? Self.regularFileIdentity(
                   parent: dataDescriptor,
                   name: name
               ),
               currentIdentity == publishedIdentity,
               let rollbackIdentity = try? Self.regularFileIdentity(
                   parent: dataDescriptor,
                   name: rollback
               ),
               rollbackIdentity == replacedIdentity {
                do {
                    guard Darwin.renameatx_np(
                              dataDescriptor,
                              name,
                              dataDescriptor,
                              rollback,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(dataDescriptor) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            throw error
        }
    }

    private func tree(parent: Int32, id: UUID) throws -> Tree {
        try verify()
        let name = Self.canonical(id)
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        let expected = try Self.identity(descriptor)
        var directories = Set<String>()
        var files = Set<String>()
        try Self.enumerateTree(
            directory: descriptor,
            prefix: "",
            directories: &directories,
            files: &files
        )
        try verify()
        guard try Self.requiredDirectoryIdentity(parent: parent, name: name) == expected else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return Tree(directories: directories, files: files)
    }

    private func removeDirectory(parent: Int32, name: String) throws {
        try Self.requireSafeBasename(name)
        try verify()
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return }
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        let expected = try Self.identity(descriptor)
        try Self.removeContents(of: descriptor)
        try verify()
        guard try Self.requiredDirectoryIdentity(parent: parent, name: name) == expected,
              Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try verify()
        guard try !Self.itemExists(parent: parent, name: name) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    fileprivate static func removeContents(of directory: Int32) throws {
        for name in try names(in: directory) {
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let child = Darwin.openat(
                    directory,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                let expected: Identity
                do {
                    expected = try identity(child)
                    try removeContents(of: child)
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
                guard try requiredDirectoryIdentity(parent: directory, name: name)
                        == expected,
                      Darwin.unlinkat(directory, name, AT_REMOVEDIR) == 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            case S_IFREG:
                guard info.st_nlink == 1,
                      Darwin.unlinkat(directory, name, 0) == 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            default:
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        guard Darwin.fsync(directory) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private static func enumerateTree(
        directory: Int32,
        prefix: String,
        directories: inout Set<String>,
        files: inout Set<String>
    ) throws {
        for name in try names(in: directory) {
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            var info = stat()
            guard Darwin.fstatat(
                directory,
                name,
                &info,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let child = Darwin.openat(
                    directory,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                let expected: Identity
                do {
                    expected = try identity(child)
                    directories.insert(path)
                    try enumerateTree(
                        directory: child,
                        prefix: path,
                        directories: &directories,
                        files: &files
                    )
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
                guard try requiredDirectoryIdentity(parent: directory, name: name)
                        == expected else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            case S_IFREG:
                guard info.st_nlink == 1 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                files.insert(path)
            default:
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
    }

    fileprivate static func names(in descriptor: Int32) throws -> [String] {
        let independent = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard independent >= 0, let directory = Darwin.fdopendir(independent) else {
            if independent >= 0 { _ = Darwin.close(independent) }
            throw StoreGenerationFailure.dataPointerInvalid
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
        guard errno == 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        return result.sorted()
    }

    fileprivate static func itemExists(parent: Int32, name: String) throws -> Bool {
        try requireSafeBasename(name)
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            return true
        }
        guard errno == ENOENT else { throw StoreGenerationFailure.dataPointerInvalid }
        return false
    }

    private static func directoryPresence(parent: Int32, name: String) throws -> Bool {
        var info = stat()
        if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw StoreGenerationFailure.dataPointerInvalid }
            return false
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return true
    }

    private static func requiredDirectoryIdentity(
        parent: Int32,
        name: String
    ) throws -> Identity {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        return try identity(descriptor)
    }

    private static func openDirectory(parent: Int32, name: String) throws -> Int32 {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        return descriptor
    }

    private static func openOrCreateDirectory(parent: Int32, name: String) throws -> Int32 {
        var descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT {
            guard Darwin.mkdirat(parent, name, mode_t(0o700)) == 0 || errno == EEXIST,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            descriptor = Darwin.openat(
                parent,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        return descriptor
    }

    fileprivate static func readRegularFileWithIdentity(
        parent: Int32,
        name: String
    ) throws -> RegularFileRead {
        try requireSafeBasename(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return RegularFileRead(
            data: data,
            identity: RegularFileIdentity(
                device: after.st_dev,
                inode: after.st_ino,
                linkCount: after.st_nlink
            )
        )
    }

    fileprivate static func readRegularFile(
        parent: Int32,
        name: String
    ) throws -> Data {
        try readRegularFileWithIdentity(parent: parent, name: name).data
    }

    fileprivate static func createRegularFile(
        parent: Int32,
        name: String,
        data: Data
    ) throws {
        try requireSafeBasename(name)
        let descriptor = Darwin.openat(
            parent,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        defer { _ = Darwin.close(descriptor) }
        do {
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(
                        descriptor,
                        base.advanced(by: offset),
                        raw.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else if errno != EINTR {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                }
            }
            guard Darwin.fsync(descriptor) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            _ = Darwin.unlinkat(parent, name, 0)
            _ = Darwin.fsync(parent)
            throw error
        }
    }

    private static func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func decodeCanonicalPointer<Value: Codable>(
        _ data: Data
    ) throws -> Value {
        do {
            let value = try JSONDecoder().decode(Value.self, from: data)
            guard try canonicalData(value) == data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return value
        } catch let error as StoreGenerationFailure {
            throw error
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    fileprivate static func decodeCanonicalPointer<Value: Codable>(
        parent: Int32,
        name: String
    ) throws -> Value {
        let captured = try readRegularFileWithIdentity(parent: parent, name: name)
        let value: Value = try decodeCanonicalPointer(captured.data)
        guard try regularFileIdentity(parent: parent, name: name) == captured.identity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return value
    }

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    fileprivate static func regularFileIdentity(
        parent: Int32,
        name: String
    ) throws -> RegularFileIdentity {
        try requireSafeBasename(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return RegularFileIdentity(
            device: after.st_dev,
            inode: after.st_ino,
            linkCount: after.st_nlink
        )
    }

    fileprivate static func regularFileIdentity(
        descriptor: Int32
    ) throws -> RegularFileIdentity {
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_nlink == 1,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return RegularFileIdentity(
            device: after.st_dev,
            inode: after.st_ino,
            linkCount: after.st_nlink
        )
    }

    fileprivate static func regularFileIdentity(
        at url: URL
    ) throws -> RegularFileIdentity {
        let descriptor = Darwin.open(url.standardizedFileURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        return try regularFileIdentity(descriptor: descriptor)
    }

    fileprivate static func directoryIdentity(
        at url: URL
    ) throws -> Identity {
        let descriptor = Darwin.open(
            url.standardizedFileURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(descriptor) }
        return try identity(descriptor)
    }

    fileprivate static func directoryIdentity(
        descriptor: Int32
    ) throws -> Identity {
        try identity(descriptor)
    }

    private static func require(_ descriptor: Int32, _ expected: Identity) throws {
        guard try identity(descriptor) == expected else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private static func currentURL(for descriptor: Int32) throws -> URL {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = Darwin.fcntl(descriptor, F_GETPATH, &path)
        guard result >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let value = String(cString: path)
        guard !value.isEmpty else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return URL(fileURLWithPath: value, isDirectory: true)
            .standardizedFileURL
    }

    private static func canonical(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        canonical(lhs) < canonical(rhs)
    }
}

struct StoreGenerationFactory {
    private static let dataDirectoryName = "FieldEvidenceData"
    private static let bootstrapDirectoryName = ".FieldEvidenceData.bootstrap"
    private static let generationsDirectoryName = "generations"
    private static let currentPointerName = "current.json"
    private static let retiredPointerName = "retired.json"
    private static let modelStoreName = "model.sqlite"
    private static let pointerMutationLock = NSLock()

    private let applicationSupportURL: URL
    private let fileManager: FileManager

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
    }

    var restoreApplicationSupportURL: URL {
        applicationSupportURL
    }

    func currentGenerationID() throws -> UUID {
        try protectPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName, isDirectory: false)
        )
        let pointer: CurrentPointerV1 = try decodeCanonicalPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        try StorePointerSchemaRegistry.requireCurrent(pointer.schemaVersion)
        guard let value = canonicalUUID(from: pointer.generationID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return value
    }

    func currentGenerationID(
        authority: StoreRestoreGenerationAuthority
    ) throws -> UUID {
        try authority.currentGenerationID()
    }

    func restoreStagingGenerationURL(id: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(canonicalString(for: id), isDirectory: true)
    }

    func installedGenerationURL(id: UUID) -> URL {
        generationsURL.appendingPathComponent(
            canonicalString(for: id),
            isDirectory: true
        )
    }

    func makeRestoreGenerationAuthority(
        expectedApplicationSupportIdentity: StoreApplicationSupportIdentity? = nil
    ) throws -> StoreRestoreGenerationAuthority {
        try StoreRestoreGenerationAuthority(
            applicationSupportURL: applicationSupportURL,
            expectedApplicationSupportIdentity: expectedApplicationSupportIdentity
        )
    }

    func generationPresence(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreRestoreGenerationAuthority.Presence {
        try authority.presence(id: id)
    }

    @MainActor
    func createRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority,
        populate: (ModelContext) throws -> Void
    ) throws {
        let root = restoreStagingGenerationURL(id: id)
        do {
            try authority.createStagingGeneration(id: id)
            try autoreleasepool {
                let container = try makeContainer(
                    at: root.appendingPathComponent(Self.modelStoreName)
                )
                let context = container.mainContext
                try populate(context)
                if context.hasChanges {
                    try context.save()
                    guard !context.hasChanges else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                }
            }
            try authority.protectStagingGeneration(id: id)
            try authority.requireStagingGeneration(id: id)
            guard try itemType(
                at: root.appendingPathComponent(Self.modelStoreName)
            ) == .typeRegular else {
                throw StoreGenerationFailure.dataGenerationMissing
            }
        } catch {
            try? authority.removeStagingGeneration(id: id)
            throw error
        }
    }

    func installRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try authority.installStagingGeneration(id: id)
    }

    @MainActor
    func createEmptyInstalledGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority,
        beforeStoreCreate: () throws -> Void = {}
    ) throws {
        var handle: StoreRestoreGenerationAuthority.InstalledGenerationHandle?
        do {
            let created = try authority.createInstalledGeneration(id: id)
            handle = created
            try beforeStoreCreate()
            try createAndReleaseEmptyContainer(
                at: try authority.modelStoreURL(
                    for: created,
                    name: Self.modelStoreName
                )
            )
            try authority.protectInstalledGeneration(id: id)
            try authority.requireRegularFile(
                named: Self.modelStoreName,
                in: created
            )
        } catch {
            if let handle {
                try? authority.removeCreatedInstalledGeneration(handle)
            }
            throw error
        }
    }

    func removeRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try authority.removeStagingGeneration(id: id)
    }

    func removeInstalledGeneration(
        id: UUID,
        keeping currentID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        guard id != currentID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try authority.removeInstalledGeneration(id: id)
    }

    func switchCurrentGeneration(
        expected oldID: UUID,
        to newID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try authority.switchCurrentGeneration(expected: oldID, to: newID)
    }

    func switchCurrentGeneration(expected oldID: UUID, to newID: UUID) throws {
        guard oldID != newID,
              try currentGenerationID() == oldID,
              try itemType(at: installedGenerationURL(id: oldID)) == .typeDirectory,
              try itemType(at: installedGenerationURL(id: newID)) == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let pointer = CurrentPointerV1(
            generationID: canonicalString(for: newID),
            schemaVersion: StorePointerSchemaRegistry.currentVersion
        )
        try replacePointer(name: Self.currentPointerName, value: pointer)
        guard try currentGenerationID() == newID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func retireGeneration(
        oldID: UUID,
        currentID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try authority.retireGeneration(oldID: oldID, currentID: currentID)
    }

    func replaceRetiredGenerationIDs(
        expected: [UUID],
        with replacement: [UUID],
        currentID: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws {
        try authority.replaceRetiredGenerationIDs(
            expected: expected,
            with: replacement,
            currentID: currentID
        )
    }

    func retireGeneration(oldID: UUID, currentID: UUID) throws {
        guard oldID != currentID,
              try currentGenerationID() == currentID,
              try itemType(at: installedGenerationURL(id: oldID)) == .typeDirectory,
              try itemType(at: installedGenerationURL(id: currentID)) == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let retired = try retiredGenerationIDs()
        guard !retired.contains(currentID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let values = Array(Set(retired + [oldID])).sorted {
            canonicalString(for: $0) < canonicalString(for: $1)
        }
        let pointer = RetiredPointerV1(
            generationIDs: values.map { canonicalString(for: $0) },
            schemaVersion: StorePointerSchemaRegistry.retiredVersion
        )
        try replacePointer(name: Self.retiredPointerName, value: pointer)
        guard try retiredGenerationIDs() == values else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func retiredGenerationIDs() throws -> [UUID] {
        try protectPointer(
            at: dataRootURL.appendingPathComponent(Self.retiredPointerName, isDirectory: false)
        )
        let pointer: RetiredPointerV1 = try decodeCanonicalPointer(
            at: dataRootURL.appendingPathComponent(Self.retiredPointerName)
        )
        try StorePointerSchemaRegistry.requireRetired(pointer.schemaVersion)
        guard pointer.generationIDs == pointer.generationIDs.sorted(),
              Set(pointer.generationIDs).count == pointer.generationIDs.count else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let values = pointer.generationIDs.compactMap(canonicalUUID)
        guard values.count == pointer.generationIDs.count else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return values
    }

    @MainActor
    func openInstalledGeneration(id: UUID) throws -> StoreGenerationSession {
        try openGeneration(id: id, at: installedGenerationURL(id: id))
    }

    @MainActor
    func openInstalledGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        try authority.requireInstalledGeneration(id: id)
        try authority.protectInstalledGeneration(id: id)
        let session = try openGeneration(id: id, at: installedGenerationURL(id: id))
        try authority.protectInstalledGeneration(id: id)
        try authority.requireInstalledGeneration(id: id)
        return session
    }

    @MainActor
    func openRestoreStagingGeneration(id: UUID) throws -> StoreGenerationSession {
        try openGeneration(id: id, at: restoreStagingGenerationURL(id: id))
    }

    @MainActor
    func openRestoreStagingGeneration(
        id: UUID,
        authority: StoreRestoreGenerationAuthority
    ) throws -> StoreGenerationSession {
        try authority.requireStagingGeneration(id: id)
        try authority.protectStagingGeneration(id: id)
        let session = try openGeneration(id: id, at: restoreStagingGenerationURL(id: id))
        try authority.protectStagingGeneration(id: id)
        try authority.requireStagingGeneration(id: id)
        return session
    }

    static func backupImportStagingDirectory(
        containing generationRootURL: URL
    ) throws -> URL {
        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        guard root.isFileURL,
              generations.lastPathComponent == Self.generationsDirectoryName,
              dataRoot.lastPathComponent == Self.dataDirectoryName,
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return dataRoot.deletingLastPathComponent()
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("staging", isDirectory: true)
    }

    private var dataRootURL: URL {
        applicationSupportURL.appendingPathComponent(
            Self.dataDirectoryName,
            isDirectory: true
        )
    }

    private var generationsURL: URL {
        dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
    }

    private func openOwnedDirectory(at url: URL) throws -> Int32 {
        let root = applicationSupportURL.standardizedFileURL
        let target = url.standardizedFileURL
        let insideRoot = target.path == root.path ||
            (root.path == "/"
                ? target.path.hasPrefix("/")
                : target.path.hasPrefix(root.path + "/"))
        guard root.isFileURL, target.isFileURL, insideRoot else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let relativePath = String(target.path.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relativePath.isEmpty
            ? []
            : relativePath.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        var descriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        for component in components {
            let next = Darwin.openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard next >= 0 else {
                _ = Darwin.close(descriptor)
                throw StoreGenerationFailure.dataPointerInvalid
            }
            _ = Darwin.close(descriptor)
            descriptor = next
        }
        return descriptor
    }

    private func verifyOwnedDirectory(
        at url: URL,
        descriptor: Int32
    ) throws {
        var expected = stat()
        guard Darwin.fstat(descriptor, &expected) == 0,
              (expected.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let reopened = try openOwnedDirectory(at: url)
        defer { _ = Darwin.close(reopened) }
        var actual = stat()
        guard Darwin.fstat(reopened, &actual) == 0,
              (actual.st_mode & S_IFMT) == S_IFDIR,
              actual.st_dev == expected.st_dev,
              actual.st_ino == expected.st_ino else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func removeOwnedEntry(parent: Int32, name: String) throws {
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return }
            throw StoreGenerationFailure.dataPointerInvalid
        }
        switch info.st_mode & S_IFMT {
        case S_IFLNK:
            guard Darwin.unlinkat(parent, name, 0) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        case S_IFREG:
            guard info.st_nlink == 1,
                  Darwin.unlinkat(parent, name, 0) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        case S_IFDIR:
            let child = Darwin.openat(
                parent,
                name,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard child >= 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            do {
                for childName in try StoreRestoreGenerationAuthority.names(in: child) {
                    try removeOwnedEntry(parent: child, name: childName)
                }
            } catch {
                _ = Darwin.close(child)
                throw error
            }
            _ = Darwin.close(child)
            guard Darwin.unlinkat(parent, name, AT_REMOVEDIR) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        default:
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func createOwnedDirectory(parent: Int32, name: String) throws -> Int32 {
        guard Darwin.mkdirat(parent, name, mode_t(0o700)) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return descriptor
    }

    private func protect(
        _ kind: OwnedFileKindV1,
        at url: URL,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws {
        do {
            let root = applicationSupportURL.standardizedFileURL
            let target = url.standardizedFileURL
            let insideRoot = root.path == "/"
                ? target.path.hasPrefix("/")
                : target.path.hasPrefix(root.path + "/")
            guard insideRoot else {
                throw ProtectedFilePolicyError.invalidRelativePath
            }
            let relativePath = String(target.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: relativePath,
                within: root,
                authorityCheck: authorityCheck
            )
        } catch let failure as StoreGenerationFailure {
            throw failure
        } catch let error as ProtectedFilePolicyError
            where error == .protectedDataUnavailable {
            throw error
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func protectGenerationFile(
        descriptor: Int32,
        root: URL,
        name: String,
        kind: OwnedFileKindV1
    ) throws {
        try StoreRestoreGenerationAuthority.requireSafeBasename(name)
        let generationIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        )
        let fileDescriptor = Darwin.openat(
            descriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard fileDescriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        defer { _ = Darwin.close(fileDescriptor) }
        let fileIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
            descriptor: fileDescriptor
        )
        let url = root.appendingPathComponent(name, isDirectory: false)
        try protect(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: descriptor
                      ) == generationIdentity,
                      try StoreRestoreGenerationAuthority.directoryIdentity(
                          at: root
                      ) == generationIdentity,
                      try StoreRestoreGenerationAuthority.regularFileIdentity(
                          descriptor: fileDescriptor
                      ) == fileIdentity,
                      try StoreRestoreGenerationAuthority.regularFileIdentity(
                          at: url
                      ) == fileIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )
    }

    private func protectPointer(at url: URL) throws {
        try protectPointerFile(.generationPointer, at: url)
    }

    private func protectPointer(
        at url: URL,
        parent: Int32,
        root: URL
    ) throws {
        try protectPointerFile(
            .generationPointer,
            at: url,
            parent: parent,
            root: root
        )
    }

    private func protectPointerFile(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        let root = url.deletingLastPathComponent().standardizedFileURL
        let parent = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let parentIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: parent
        )
        try protect(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: parent
                      ) == parentIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                try self.verifyOwnedDirectory(at: root, descriptor: parent)
            }
        )
    }

    private func protectPointerFile(
        _ kind: OwnedFileKindV1,
        at url: URL,
        parent: Int32,
        root: URL
    ) throws {
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let parentIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: parent
        )
        try protect(
            kind,
            at: url,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: parent
                      ) == parentIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                try self.verifyOwnedDirectory(at: root, descriptor: parent)
            }
        )
    }

    private func protectGeneration(
        at root: URL,
        staging: Bool,
        requireModel: Bool
    ) throws {
        let descriptor = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(descriptor) }
        let generationIdentity = try StoreRestoreGenerationAuthority.directoryIdentity(
            descriptor: descriptor
        )
        try protect(
            staging ? .restoreStaging : .durableDirectory,
            at: root,
            authorityCheck: {
                guard try StoreRestoreGenerationAuthority.directoryIdentity(
                          descriptor: descriptor
                      ) == generationIdentity,
                      try StoreRestoreGenerationAuthority.directoryIdentity(
                          at: root
                      ) == generationIdentity else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
        )
        let before = try StoreRestoreGenerationAuthority.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )
        let modelKind: OwnedFileKindV1 = staging ? .stagingFile : .database
        let walKind: OwnedFileKindV1 = staging ? .stagingFile : .databaseWAL
        let shmKind: OwnedFileKindV1 = staging ? .stagingFile : .databaseSHM
        for name in before {
            let kind: OwnedFileKindV1
            switch name {
            case "model.sqlite": kind = modelKind
            case "\(Self.modelStoreName)-wal": kind = walKind
            case "\(Self.modelStoreName)-shm": kind = shmKind
            default: throw StoreGenerationFailure.dataPointerInvalid
            }
            try protectGenerationFile(
                descriptor: descriptor,
                root: root,
                name: name,
                kind: kind
            )
        }
        let after = try StoreRestoreGenerationAuthority.exactGenerationEntries(
            parent: descriptor,
            requireModel: requireModel
        )
        guard before == after else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func publishPointer<Value: Encodable>(
        name: String,
        value: Value,
        in root: URL
    ) throws {
        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        try StoreRestoreGenerationAuthority.requireSafeBasename(name)
        let parent = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let temporaryName = ".\(name).restore-next"
        guard try !StoreRestoreGenerationAuthority.itemExists(parent: parent, name: name),
              try !StoreRestoreGenerationAuthority.itemExists(
                  parent: parent,
                  name: temporaryName
              ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let target = root.appendingPathComponent(name, isDirectory: false)
        let temporary = root.appendingPathComponent(temporaryName, isDirectory: false)
        let data = try canonicalData(for: value)
        var published = false
        var publishedIdentity: StoreRestoreGenerationAuthority.RegularFileIdentity?
        do {
            try StoreRestoreGenerationAuthority.createRegularFile(
                parent: parent,
                name: temporaryName,
                data: data
            )
            try protectPointerFile(
                .generationPointerTemporary,
                at: temporary,
                parent: parent,
                root: root
            )
            try verifyOwnedDirectory(at: root, descriptor: parent)
            let temporaryIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: temporaryName
            )
            publishedIdentity = temporaryIdentity
            guard try !StoreRestoreGenerationAuthority.itemExists(parent: parent, name: name),
                  Darwin.renameatx_np(
                      parent,
                      temporaryName,
                      parent,
                      name,
                      UInt32(RENAME_EXCL)
            ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            published = true
            guard Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verifyOwnedDirectory(at: root, descriptor: parent)
            try protectPointer(at: target, parent: parent, root: root)
            let current = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            guard current.data == data,
                  current.identity == temporaryIdentity,
                  try !StoreRestoreGenerationAuthority.itemExists(
                      parent: parent,
                      name: temporaryName
                  ) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            if published,
               let publishedIdentity,
               let current = try? StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                   parent: parent,
                   name: name
               ),
               current.data == data,
               current.identity == publishedIdentity {
                _ = Darwin.unlinkat(parent, name, 0)
                _ = Darwin.fsync(parent)
            } else if (try? StoreRestoreGenerationAuthority.itemExists(
                parent: parent,
                name: temporaryName
            )) == true {
                _ = Darwin.unlinkat(parent, temporaryName, 0)
                _ = Darwin.fsync(parent)
            }
            throw error
        }
    }

    private func replacePointer<Value: Encodable>(
        name: String,
        value: Value
    ) throws {
        Self.pointerMutationLock.lock()
        defer { Self.pointerMutationLock.unlock() }
        try StoreRestoreGenerationAuthority.requireSafeBasename(name)
        let root = dataRootURL
        let parent = try openOwnedDirectory(at: root)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let target = root.appendingPathComponent(name, isDirectory: false)
        try protectPointer(at: target, parent: parent, root: root)
        let expectedRead = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
            parent: parent,
            name: name
        )
        let expected = expectedRead.data
        let expectedIdentity = expectedRead.identity
        let replacement = try canonicalData(for: value)
        let temporaryName = ".\(name).restore-next"
        let temporary = root.appendingPathComponent(temporaryName, isDirectory: false)
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: temporaryName
        ) {
            guard try StoreRestoreGenerationAuthority.readRegularFile(
                parent: parent,
                name: temporaryName
            ) == replacement else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try removeOwnedEntry(parent: parent, name: temporaryName)
        }
        let currentBeforeSwap = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
            parent: parent,
            name: name
        )
        guard currentBeforeSwap.data == expected,
              currentBeforeSwap.identity == expectedIdentity else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var published = false
        var publishedIdentity: StoreRestoreGenerationAuthority.RegularFileIdentity?
        do {
            try StoreRestoreGenerationAuthority.createRegularFile(
                parent: parent,
                name: temporaryName,
                data: replacement
            )
            try protectPointerFile(
                .generationPointerTemporary,
                at: temporary,
                parent: parent,
                root: root
            )
            try verifyOwnedDirectory(at: root, descriptor: parent)
            let replacementIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: temporaryName
            )
            let current = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            guard current.identity == expectedIdentity,
                  current.data == expected,
                  Darwin.renameatx_np(
                      parent,
                      temporaryName,
                      parent,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            published = true
            publishedIdentity = replacementIdentity
            guard Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verifyOwnedDirectory(at: root, descriptor: parent)
            try protectPointer(at: target, parent: parent, root: root)
            let currentAfterSwap = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            let oldTemporary = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: temporaryName
            )
            guard currentAfterSwap.data == replacement,
                  currentAfterSwap.identity == replacementIdentity,
                  oldTemporary.data == expected,
                  oldTemporary.identity == expectedIdentity,
                  Darwin.unlinkat(parent, temporaryName, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
            if published,
               let publishedIdentity,
               let current = try? StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                   parent: parent,
                   name: name
               ),
               current.data == replacement,
               current.identity == publishedIdentity {
                do {
                    let oldTemporary = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                        parent: parent,
                        name: temporaryName
                    )
                    guard oldTemporary.data == expected,
                          oldTemporary.identity == expectedIdentity,
                          Darwin.renameatx_np(
                              parent,
                              name,
                              parent,
                              temporaryName,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(parent) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                    try verifyOwnedDirectory(at: root, descriptor: parent)
                    try protectPointer(at: target, parent: parent, root: root)
                    let restored = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                        parent: parent,
                        name: name
                    )
                    let replacementTemporary = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                        parent: parent,
                        name: temporaryName
                    )
                    guard restored.data == expected,
                          restored.identity == expectedIdentity,
                          replacementTemporary.data == replacement,
                          replacementTemporary.identity == publishedIdentity,
                          Darwin.unlinkat(parent, temporaryName, 0) == 0,
                          Darwin.fsync(parent) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            if (try? StoreRestoreGenerationAuthority.itemExists(
                parent: parent,
                name: temporaryName
            )) == true {
                _ = Darwin.unlinkat(parent, temporaryName, 0)
                _ = Darwin.fsync(parent)
            }
            throw error
        }
    }

    private func restorePointer(
        parent: Int32,
        root: URL,
        name: String,
        data: Data,
        expectedCurrentIdentity: StoreRestoreGenerationAuthority.RegularFileIdentity? = nil
    ) throws {
        let rollbackName = ".\(name).restore-rollback"
        let replacedIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
            parent: parent,
            name: name
        )
        if let expectedCurrentIdentity {
            guard replacedIdentity == expectedCurrentIdentity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: rollbackName
        ) {
            try removeOwnedEntry(parent: parent, name: rollbackName)
        }
        try StoreRestoreGenerationAuthority.createRegularFile(
            parent: parent,
            name: rollbackName,
            data: data
        )
        let rollbackURL = root.appendingPathComponent(rollbackName, isDirectory: false)
        try protectPointerFile(
            .generationPointerTemporary,
            at: rollbackURL,
            parent: parent,
            root: root
        )
        try verifyOwnedDirectory(at: root, descriptor: parent)
        let publishedIdentity = try StoreRestoreGenerationAuthority.regularFileIdentity(
            parent: parent,
            name: rollbackName
        )
        var swapped = false
        do {
            guard try StoreRestoreGenerationAuthority.regularFileIdentity(
                      parent: parent,
                      name: name
                  ) == replacedIdentity,
                  Darwin.renameatx_np(
                      parent,
                      rollbackName,
                      parent,
                      name,
                      UInt32(RENAME_SWAP)
                  ) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = true
            guard Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try protectPointer(
                at: root.appendingPathComponent(name, isDirectory: false),
                parent: parent,
                root: root
            )
            let restored = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            let replaced = try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: rollbackName
            )
            guard restored.data == data,
                  restored.identity == publishedIdentity,
                  replaced == replacedIdentity,
                  Darwin.unlinkat(parent, rollbackName, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            swapped = false
        } catch {
            if swapped,
               let currentIdentity = try? StoreRestoreGenerationAuthority.regularFileIdentity(
                   parent: parent,
                   name: name
               ),
               currentIdentity == publishedIdentity,
               let rollbackIdentity = try? StoreRestoreGenerationAuthority.regularFileIdentity(
                   parent: parent,
                   name: rollbackName
               ),
               rollbackIdentity == replacedIdentity {
                do {
                    guard Darwin.renameatx_np(
                              parent,
                              name,
                              parent,
                              rollbackName,
                              UInt32(RENAME_SWAP)
                          ) == 0,
                          Darwin.fsync(parent) == 0 else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                } catch {
                    if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
                        throw error
                    }
                }
            }
            throw error
        }
    }

    @MainActor
    func openOrBootstrapCurrent() throws -> StoreGenerationSession {
        let dataRootURL = applicationSupportURL.appendingPathComponent(
            Self.dataDirectoryName,
            isDirectory: true
        )

        switch try itemType(at: dataRootURL) {
        case nil:
            try bootstrapDataRoot(at: dataRootURL)
        case .some(.typeDirectory):
            break
        case .some:
            throw StoreGenerationFailure.dataPointerInvalid
        }

        return try openCurrent(in: dataRootURL)
    }

    @MainActor
    private func bootstrapDataRoot(at dataRootURL: URL) throws {
        if let type = try itemType(at: applicationSupportURL),
           type != .typeDirectory {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        guard try itemType(at: applicationSupportURL) == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let bootstrapURL = applicationSupportURL.appendingPathComponent(
            Self.bootstrapDirectoryName,
            isDirectory: true
        )
        let applicationSupportDescriptor = try openOwnedDirectory(at: applicationSupportURL)
        defer { _ = Darwin.close(applicationSupportDescriptor) }
        try verifyOwnedDirectory(
            at: applicationSupportURL,
            descriptor: applicationSupportDescriptor
        )
        if try StoreRestoreGenerationAuthority.itemExists(
            parent: applicationSupportDescriptor,
            name: Self.bootstrapDirectoryName
        ) {
            try removeOwnedEntry(
                parent: applicationSupportDescriptor,
                name: Self.bootstrapDirectoryName
            )
        }

        let generationID = UUID()
        let generationName = canonicalString(for: generationID)
        let bootstrapDescriptor = try createOwnedDirectory(
            parent: applicationSupportDescriptor,
            name: Self.bootstrapDirectoryName
        )
        defer { _ = Darwin.close(bootstrapDescriptor) }
        let bootstrapGenerationsDescriptor = try createOwnedDirectory(
            parent: bootstrapDescriptor,
            name: Self.generationsDirectoryName
        )
        defer { _ = Darwin.close(bootstrapGenerationsDescriptor) }
        let generationDescriptor = try createOwnedDirectory(
            parent: bootstrapGenerationsDescriptor,
            name: generationName
        )
        defer { _ = Darwin.close(generationDescriptor) }
        let generationRootURL = bootstrapURL
            .appendingPathComponent(Self.generationsDirectoryName, isDirectory: true)
            .appendingPathComponent(generationName, isDirectory: true)

        let bootstrapGenerationsURL = bootstrapURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
        try protect(.stagingDirectory, at: bootstrapURL)
        try protect(.stagingDirectory, at: bootstrapGenerationsURL)
        try protect(.restoreStaging, at: generationRootURL)

        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        try createAndReleaseEmptyContainer(at: modelStoreURL)

        guard try itemType(at: modelStoreURL) == .typeRegular else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        try protectGeneration(at: generationRootURL, staging: false, requireModel: true)

        let currentPointer = CurrentPointerV1(
            generationID: generationName,
            schemaVersion: StorePointerSchemaRegistry.currentVersion
        )
        let retiredPointer = RetiredPointerV1(
            generationIDs: [],
            schemaVersion: StorePointerSchemaRegistry.retiredVersion
        )
        try publishPointer(
            name: Self.currentPointerName,
            value: currentPointer,
            in: bootstrapURL
        )
        try publishPointer(
            name: Self.retiredPointerName,
            value: retiredPointer,
            in: bootstrapURL
        )

        try protect(.durableDirectory, at: bootstrapURL)
        try protect(.durableDirectory, at: bootstrapGenerationsURL)
        try protectGeneration(at: generationRootURL, staging: false, requireModel: true)
        try protectPointer(
            at: bootstrapURL.appendingPathComponent(Self.currentPointerName, isDirectory: false)
        )
        try protectPointer(
            at: bootstrapURL.appendingPathComponent(Self.retiredPointerName, isDirectory: false)
        )

        // The staging root is a fixed sibling, so this move is a same-volume
        // atomic publication of an already complete generation and pointers.
        try verifyOwnedDirectory(
            at: applicationSupportURL,
            descriptor: applicationSupportDescriptor
        )
        guard try !StoreRestoreGenerationAuthority.itemExists(
            parent: applicationSupportDescriptor,
            name: Self.dataDirectoryName
        ),
              Darwin.renameatx_np(
                  applicationSupportDescriptor,
                  Self.bootstrapDirectoryName,
                  applicationSupportDescriptor,
                  Self.dataDirectoryName,
                  UInt32(RENAME_EXCL)
              ) == 0,
              Darwin.fsync(applicationSupportDescriptor) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protect(.durableDirectory, at: dataRootURL)
        let publishedGenerationsURL = dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
        try protect(.durableDirectory, at: publishedGenerationsURL)
        try protectGeneration(
            at: publishedGenerationsURL.appendingPathComponent(
                generationName,
                isDirectory: true
            ),
            staging: false,
            requireModel: true
        )
        try protectPointer(
            at: dataRootURL.appendingPathComponent(
                Self.currentPointerName,
                isDirectory: false
            )
        )
        try protectPointer(
            at: dataRootURL.appendingPathComponent(
                Self.retiredPointerName,
                isDirectory: false
            )
        )
    }

    @MainActor
    private func openCurrent(in dataRootURL: URL) throws -> StoreGenerationSession {
        try protect(.durableDirectory, at: dataRootURL)
        let generationsRoot = dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
        try protect(.durableDirectory, at: generationsRoot)
        let currentURL = dataRootURL.appendingPathComponent(
            Self.currentPointerName,
            isDirectory: false
        )
        let retiredURL = dataRootURL.appendingPathComponent(
            Self.retiredPointerName,
            isDirectory: false
        )
        guard try itemType(at: currentURL) == .typeRegular,
              try itemType(at: retiredURL) == .typeRegular else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protectPointer(at: currentURL)
        try protectPointer(at: retiredURL)

        let current: CurrentPointerV1 = try decodeCanonicalPointer(at: currentURL)
        let retired: RetiredPointerV1 = try decodeCanonicalPointer(at: retiredURL)
        try StorePointerSchemaRegistry.requireCurrent(current.schemaVersion)
        try StorePointerSchemaRegistry.requireRetired(retired.schemaVersion)
        guard let currentID = canonicalUUID(from: current.generationID),
              retired.generationIDs.allSatisfy({ canonicalUUID(from: $0) != nil }),
              retired.generationIDs == retired.generationIDs.sorted(),
              Set(retired.generationIDs).count == retired.generationIDs.count,
              !retired.generationIDs.contains(current.generationID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let generationsURL = generationsRoot
        guard let generationsType = try itemType(at: generationsURL) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        guard generationsType == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let expectedGenerationNames = Set(
            [current.generationID] + retired.generationIDs
        )
        let actualGenerationNames: Set<String>
        do {
            actualGenerationNames = Set(
                try fileManager.contentsOfDirectory(atPath: generationsURL.path)
            )
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard actualGenerationNames == expectedGenerationNames else {
            if expectedGenerationNames.subtracting(actualGenerationNames).isEmpty {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            throw StoreGenerationFailure.dataGenerationMissing
        }

        for generationName in expectedGenerationNames {
            let generationURL = generationsURL.appendingPathComponent(
                generationName,
                isDirectory: true
            )
            guard let generationType = try itemType(at: generationURL) else {
                throw StoreGenerationFailure.dataGenerationMissing
            }
            guard generationType == .typeDirectory else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try protectGeneration(at: generationURL, staging: false, requireModel: true)
        }

        let generationRootURL = generationsURL.appendingPathComponent(
            current.generationID,
            isDirectory: true
        )
        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        guard let modelStoreType = try itemType(at: modelStoreURL) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        guard modelStoreType == .typeRegular else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protectGeneration(at: generationRootURL, staging: false, requireModel: true)

        let container: ModelContainer
        do {
            container = try makeContainer(at: modelStoreURL)
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try protectGeneration(at: generationRootURL, staging: false, requireModel: true)
        return StoreGenerationSession(
            generationID: currentID,
            generationRootURL: generationRootURL,
            modelContainer: container,
            afterSaveReproof: { [self] in
                try self.protectGeneration(
                    at: generationRootURL,
                    staging: false,
                    requireModel: true
                )
            }
        )
    }

    @MainActor
    private func createAndReleaseEmptyContainer(at modelStoreURL: URL) throws {
        _ = try makeContainer(at: modelStoreURL)
    }

    @MainActor
    private func openGeneration(
        id: UUID,
        at generationRootURL: URL
    ) throws -> StoreGenerationSession {
        guard generationRootURL.lastPathComponent == canonicalString(for: id),
              try itemType(at: generationRootURL) == .typeDirectory else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        let restoreRoot = restoreStagingGenerationURL(id: id)
        let staging = generationRootURL.standardizedFileURL == restoreRoot.standardizedFileURL
        try protectGeneration(at: generationRootURL, staging: staging, requireModel: true)
        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        guard try itemType(at: modelStoreURL) == .typeRegular else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        let container: ModelContainer
        do { container = try makeContainer(at: modelStoreURL) }
        catch { throw StoreGenerationFailure.dataPointerInvalid }
        try protectGeneration(at: generationRootURL, staging: staging, requireModel: true)
        return StoreGenerationSession(
            generationID: id,
            generationRootURL: generationRootURL,
            modelContainer: container,
            afterSaveReproof: { [self] in
                try self.protectGeneration(
                    at: generationRootURL,
                    staging: staging,
                    requireModel: true
                )
            }
        )
    }

    private func removeOwnedDirectory(
        _ url: URL,
        expectedParent: URL
    ) throws {
        let value = url.standardizedFileURL
        guard value.deletingLastPathComponent() == expectedParent.standardizedFileURL,
              let id = UUID(uuidString: value.lastPathComponent),
              canonicalString(for: id) == value.lastPathComponent else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let parent = try openOwnedDirectory(at: expectedParent)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: expectedParent, descriptor: parent)
        try removeOwnedEntry(parent: parent, name: value.lastPathComponent)
        guard try !StoreRestoreGenerationAuthority.itemExists(
            parent: parent,
            name: value.lastPathComponent
        ) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    @MainActor
    private func makeContainer(at modelStoreURL: URL) throws -> ModelContainer {
        let schema = PersistentSchemaV1.makeSchema()
        let configuration = ModelConfiguration(
            "FieldEvidenceV1",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    private func decodeCanonicalPointer<Value: Decodable & Encodable>(
        at url: URL
    ) throws -> Value {
        let parentURL = url.deletingLastPathComponent()
        let parent = try openOwnedDirectory(at: parentURL)
        defer { _ = Darwin.close(parent) }
        try verifyOwnedDirectory(at: parentURL, descriptor: parent)
        return try decodeCanonicalPointer(parent: parent, name: url.lastPathComponent)
    }

    private func decodeCanonicalPointer<Value: Decodable & Encodable>(
        parent: Int32,
        name: String
    ) throws -> Value {
        do {
            let captured = try StoreRestoreGenerationAuthority.readRegularFileWithIdentity(
                parent: parent,
                name: name
            )
            let data = captured.data
            let value = try JSONDecoder().decode(Value.self, from: data)
            guard try canonicalData(for: value) == data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            guard try StoreRestoreGenerationAuthority.regularFileIdentity(
                parent: parent,
                name: name
            ) == captured.identity else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return value
        } catch let failure as StoreGenerationFailure {
            throw failure
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func canonicalData<Value: Encodable>(for value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func canonicalUUID(from value: String) -> UUID? {
        guard let uuid = UUID(uuidString: value),
              canonicalString(for: uuid) == value else {
            return nil
        }
        return uuid
    }

    private func canonicalString(for uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }

    private func itemType(at url: URL) throws -> FileAttributeType? {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw StoreGenerationFailure.dataPointerInvalid
        }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return .typeDirectory
        case S_IFREG:
            return .typeRegular
        case S_IFLNK:
            return .typeSymbolicLink
        default:
            return .typeUnknown
        }
    }
}

private struct CurrentPointerV1: Codable {
    let generationID: String
    let schemaVersion: Int
}

private struct RetiredPointerV1: Codable {
    let generationIDs: [String]
    let schemaVersion: Int
}

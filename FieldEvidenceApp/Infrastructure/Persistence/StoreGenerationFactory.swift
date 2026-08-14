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

@MainActor
final class StoreGenerationSession {
    let generationID: UUID
    let generationRootURL: URL
    let modelContext: ModelContext

    private let modelContainer: ModelContainer

    fileprivate init(
        generationID: UUID,
        generationRootURL: URL,
        modelContainer: ModelContainer
    ) {
        self.generationID = generationID
        self.generationRootURL = generationRootURL
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
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
        let restore = try Self.openDirectory(parent: app, name: Self.restoreName)
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
        let value: CurrentPointerV1 = try Self.decodeCanonicalPointer(
            try Self.readRegularFile(
                parent: dataDescriptor,
                name: "current.json"
            )
        )
        guard value.schemaVersion == 1,
              let id = UUID(uuidString: value.generationID),
              Self.canonical(id) == value.generationID else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return id
    }

    func retiredGenerationIDs() throws -> [UUID] {
        try verify()
        let value: RetiredPointerV1 = try Self.decodeCanonicalPointer(
            try Self.readRegularFile(
                parent: dataDescriptor,
                name: "retired.json"
            )
        )
        guard value.schemaVersion == 1,
              value.generationIDs == value.generationIDs.sorted(),
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
                schemaVersion: 1
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
                schemaVersion: 1
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
                schemaVersion: 1
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
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\") else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try removeDirectory(parent: importStagingDescriptor, name: name)
    }

    private func replacePointer<Value: Encodable>(
        name: String,
        value: Value
    ) throws {
        try verify()
        let expected = try Self.readRegularFile(parent: dataDescriptor, name: name)
        let replacement = try Self.canonicalData(value)
        let temporary = ".\(name).restore-next"
        if try Self.itemExists(parent: dataDescriptor, name: temporary) {
            guard try Self.readRegularFile(
                parent: dataDescriptor,
                name: temporary
            ) == replacement,
                  try Self.readRegularFile(parent: dataDescriptor, name: name)
                    == expected,
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
        do {
            try verify()
            guard try Self.readRegularFile(parent: dataDescriptor, name: name)
                    == expected,
                  Darwin.renameat(
                      dataDescriptor,
                      temporary,
                      dataDescriptor,
                      name
                  ) == 0,
                  Darwin.fsync(dataDescriptor) == 0 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try verify()
            guard try Self.readRegularFile(parent: dataDescriptor, name: name)
                    == replacement,
                  try !Self.itemExists(
                      parent: dataDescriptor,
                      name: temporary
                  ) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        } catch {
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

    private static func removeContents(of directory: Int32) throws {
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

    private static func names(in descriptor: Int32) throws -> [String] {
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

    private static func itemExists(parent: Int32, name: String) throws -> Bool {
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

    private static func readRegularFile(
        parent: Int32,
        name: String
    ) throws -> Data {
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
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return data
    }

    private static func createRegularFile(
        parent: Int32,
        name: String,
        data: Data
    ) throws {
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

    private static func identity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
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
        let pointer: CurrentPointerV1 = try decodeCanonicalPointer(
            at: dataRootURL.appendingPathComponent(Self.currentPointerName)
        )
        guard pointer.schemaVersion == 1,
              let value = canonicalUUID(from: pointer.generationID) else {
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
            schemaVersion: 1
        )
        let url = dataRootURL.appendingPathComponent(Self.currentPointerName)
        try canonicalData(for: pointer).write(to: url, options: .atomic)
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
            schemaVersion: 1
        )
        let url = dataRootURL.appendingPathComponent(Self.retiredPointerName)
        try canonicalData(for: pointer).write(to: url, options: .atomic)
        guard try retiredGenerationIDs() == values else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    func retiredGenerationIDs() throws -> [UUID] {
        let pointer: RetiredPointerV1 = try decodeCanonicalPointer(
            at: dataRootURL.appendingPathComponent(Self.retiredPointerName)
        )
        guard pointer.schemaVersion == 1,
              pointer.generationIDs == pointer.generationIDs.sorted(),
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
        let session = try openGeneration(id: id, at: installedGenerationURL(id: id))
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
        let session = try openGeneration(id: id, at: restoreStagingGenerationURL(id: id))
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
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )

        let bootstrapURL = applicationSupportURL.appendingPathComponent(
            Self.bootstrapDirectoryName,
            isDirectory: true
        )
        if try itemType(at: bootstrapURL) != nil {
            try fileManager.removeItem(at: bootstrapURL)
        }

        let generationID = UUID()
        let generationName = canonicalString(for: generationID)
        let generationRootURL = bootstrapURL
            .appendingPathComponent(Self.generationsDirectoryName, isDirectory: true)
            .appendingPathComponent(generationName, isDirectory: true)

        try fileManager.createDirectory(
            at: generationRootURL,
            withIntermediateDirectories: true
        )

        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        try createAndReleaseEmptyContainer(at: modelStoreURL)

        guard try itemType(at: modelStoreURL) == .typeRegular else {
            throw StoreGenerationFailure.dataGenerationMissing
        }

        let currentPointer = CurrentPointerV1(
            generationID: generationName,
            schemaVersion: 1
        )
        let retiredPointer = RetiredPointerV1(
            generationIDs: [],
            schemaVersion: 1
        )
        try canonicalData(for: currentPointer).write(
            to: bootstrapURL.appendingPathComponent(Self.currentPointerName),
            options: .atomic
        )
        try canonicalData(for: retiredPointer).write(
            to: bootstrapURL.appendingPathComponent(Self.retiredPointerName),
            options: .atomic
        )

        // The staging root is a fixed sibling, so this move is a same-volume
        // atomic publication of an already complete generation and pointers.
        try fileManager.moveItem(at: bootstrapURL, to: dataRootURL)
    }

    @MainActor
    private func openCurrent(in dataRootURL: URL) throws -> StoreGenerationSession {
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

        let current: CurrentPointerV1 = try decodeCanonicalPointer(at: currentURL)
        let retired: RetiredPointerV1 = try decodeCanonicalPointer(at: retiredURL)
        guard current.schemaVersion == 1,
              retired.schemaVersion == 1,
              let currentID = canonicalUUID(from: current.generationID),
              retired.generationIDs.allSatisfy({ canonicalUUID(from: $0) != nil }),
              retired.generationIDs == retired.generationIDs.sorted(),
              Set(retired.generationIDs).count == retired.generationIDs.count,
              !retired.generationIDs.contains(current.generationID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let generationsURL = dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
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

        let container: ModelContainer
        do {
            container = try makeContainer(at: modelStoreURL)
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return StoreGenerationSession(
            generationID: currentID,
            generationRootURL: generationRootURL,
            modelContainer: container
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
        return StoreGenerationSession(
            generationID: id,
            generationRootURL: generationRootURL,
            modelContainer: container
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
        guard let type = try itemType(at: value) else { return }
        guard type == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        try fileManager.removeItem(at: value)
        guard try itemType(at: value) == nil else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    @MainActor
    private func makeContainer(at modelStoreURL: URL) throws -> ModelContainer {
        let schema = Schema(
            [
                Site.self,
                Asset.self,
                WorkflowRecord.self,
                EvidenceFile.self,
                Issue.self,
                Packet.self,
                Report.self,
            ],
            version: Schema.Version(1, 0, 0)
        )
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
        do {
            let data = try Data(contentsOf: url)
            let value = try JSONDecoder().decode(Value.self, from: data)
            guard try canonicalData(for: value) == data else {
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
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.type] as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw error
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

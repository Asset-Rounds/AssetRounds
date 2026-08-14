import Darwin
import Foundation

enum RestoreIntentStoreError: Error, Equatable {
    case invalidAuthority
    case invalidIntent
    case intentAlreadyExists
    case intentMissing
    case intentMismatch
    case writeFailed
    case cleanupFailed
}

/// Descriptor-pinned authority for the single restore journal. The canonical
/// leaf is never followed through a symbolic link and phase replacement is an
/// atomic exchange whose displaced bytes must equal the expected prior phase.
final class RestoreIntentStore {
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static let directoryName = "FieldEvidenceRestore"
    private static let intentName = "restore.json"
    private static let nextName = ".restore.json.next"

    private let applicationSupportURL: URL
    private let applicationSupportDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let restoreDescriptor: Int32
    private let restoreIdentity: Identity

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else { throw RestoreIntentStoreError.invalidAuthority }
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let appDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard appDescriptor >= 0 else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        var ownsAppDescriptor = true
        defer {
            if ownsAppDescriptor { _ = Darwin.close(appDescriptor) }
        }
        let appIdentity = try Self.directoryIdentity(appDescriptor)

        var restoreDescriptor = Darwin.openat(
            appDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if restoreDescriptor < 0, errno == ENOENT {
            guard Darwin.mkdirat(
                appDescriptor,
                Self.directoryName,
                mode_t(0o700)
            ) == 0 || errno == EEXIST else {
                throw RestoreIntentStoreError.invalidAuthority
            }
            restoreDescriptor = Darwin.openat(
                appDescriptor,
                Self.directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
        }
        guard restoreDescriptor >= 0 else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        var ownsRestoreDescriptor = true
        defer {
            if ownsRestoreDescriptor { _ = Darwin.close(restoreDescriptor) }
        }
        let restoreIdentity = try Self.directoryIdentity(restoreDescriptor)

        self.applicationSupportURL = root
        self.applicationSupportDescriptor = appDescriptor
        self.applicationSupportIdentity = appIdentity
        self.restoreDescriptor = restoreDescriptor
        self.restoreIdentity = restoreIdentity
        ownsAppDescriptor = false
        ownsRestoreDescriptor = false
    }

    deinit {
        _ = Darwin.close(restoreDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func load() throws -> RestoreIntentV1? {
        try verifyAuthority()
        let canonical = try readIfPresent(Self.intentName)
        let pending = try readIfPresent(Self.nextName)

        switch (canonical, pending) {
        case (nil, nil):
            return nil
        case (nil, let pending?):
            let value = try decode(pending.data)
            guard value.phase == .prepared,
                  Darwin.renameatx_np(
                    restoreDescriptor,
                    Self.nextName,
                    restoreDescriptor,
                    Self.intentName,
                    UInt32(RENAME_EXCL)
                  ) == 0,
                  Darwin.fsync(restoreDescriptor) == 0 else {
                throw RestoreIntentStoreError.invalidIntent
            }
            try verifyAuthority()
            return value
        case (let canonical?, nil):
            return try decode(canonical.data)
        case (let canonical?, let pending?):
            let current = try decode(canonical.data)
            let next = try decode(pending.data)
            guard sameOperation(current, next),
                  next.phase == nextPhase(after: current.phase)
                    || current.phase == nextPhase(after: next.phase) else {
                throw RestoreIntentStoreError.invalidIntent
            }
            try removeExact(Self.nextName, expected: pending)
            return current
        }
    }

    func create(_ value: RestoreIntentV1) throws {
        try verifyAuthority()
        guard try readIfPresent(Self.intentName) == nil,
              try readIfPresent(Self.nextName) == nil else {
            throw RestoreIntentStoreError.intentAlreadyExists
        }
        let data = try encode(value)
        try createLeaf(Self.nextName, data: data)
        guard Darwin.renameatx_np(
            restoreDescriptor,
            Self.nextName,
            restoreDescriptor,
            Self.intentName,
            UInt32(RENAME_EXCL)
        ) == 0,
              Darwin.fsync(restoreDescriptor) == 0 else {
            try? removeMatching(Self.nextName, data: data)
            throw RestoreIntentStoreError.writeFailed
        }
        guard try readIfPresent(Self.intentName)?.data == data else {
            throw RestoreIntentStoreError.writeFailed
        }
        try verifyAuthority()
    }

    func replace(
        expected: RestoreIntentV1,
        with replacement: RestoreIntentV1
    ) throws {
        try verifyAuthority()
        let expectedData = try encode(expected)
        let replacementData = try encode(replacement)
        guard sameOperation(expected, replacement),
              replacement.phase == nextPhase(after: expected.phase),
              try readIfPresent(Self.intentName)?.data == expectedData,
              try readIfPresent(Self.nextName) == nil else {
            throw RestoreIntentStoreError.intentMismatch
        }
        try createLeaf(Self.nextName, data: replacementData)
        guard Darwin.renameatx_np(
            restoreDescriptor,
            Self.nextName,
            restoreDescriptor,
            Self.intentName,
            UInt32(RENAME_SWAP)
        ) == 0 else {
            try? removeMatching(Self.nextName, data: replacementData)
            throw RestoreIntentStoreError.writeFailed
        }
        do {
            guard Darwin.fsync(restoreDescriptor) == 0,
                  try readIfPresent(Self.intentName)?.data == replacementData,
                  try readIfPresent(Self.nextName)?.data == expectedData else {
                throw RestoreIntentStoreError.writeFailed
            }
            try removeMatching(Self.nextName, data: expectedData)
            try verifyAuthority()
        } catch {
            if try readIfPresent(Self.intentName)?.data == replacementData,
               try readIfPresent(Self.nextName)?.data == expectedData {
                _ = Darwin.renameatx_np(
                    restoreDescriptor,
                    Self.nextName,
                    restoreDescriptor,
                    Self.intentName,
                    UInt32(RENAME_SWAP)
                )
                _ = Darwin.fsync(restoreDescriptor)
            }
            throw error
        }
    }

    func remove(expected: RestoreIntentV1) throws {
        try verifyAuthority()
        let data = try encode(expected)
        guard let current = try readIfPresent(Self.intentName) else {
            throw RestoreIntentStoreError.intentMissing
        }
        guard current.data == data else {
            throw RestoreIntentStoreError.intentMismatch
        }
        try removeExact(Self.intentName, expected: current)
        try verifyAuthority()
    }
}

private extension RestoreIntentStore {
    func verifyAuthority() throws {
        try Self.requireDirectory(
            applicationSupportDescriptor,
            identity: applicationSupportIdentity
        )
        try Self.requireDirectory(restoreDescriptor, identity: restoreIdentity)
        let reopenedApp = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedApp >= 0 else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedApp) }
        guard try Self.directoryIdentity(reopenedApp) == applicationSupportIdentity else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        let reopenedRestore = Darwin.openat(
            reopenedApp,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedRestore >= 0 else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedRestore) }
        guard try Self.directoryIdentity(reopenedRestore) == restoreIdentity else {
            throw RestoreIntentStoreError.invalidAuthority
        }
    }

    func encode(_ value: RestoreIntentV1) throws -> Data {
        do { return try RestoreIntentCodecV1.encode(value) }
        catch { throw RestoreIntentStoreError.invalidIntent }
    }

    func decode(_ data: Data) throws -> RestoreIntentV1 {
        do { return try RestoreIntentCodecV1.decode(data) }
        catch { throw RestoreIntentStoreError.invalidIntent }
    }

    func sameOperation(_ lhs: RestoreIntentV1, _ rhs: RestoreIntentV1) -> Bool {
        lhs.newGenerationID == rhs.newGenerationID
            && lhs.newGenerationRelativePath == rhs.newGenerationRelativePath
            && lhs.oldGenerationID == rhs.oldGenerationID
            && lhs.restoreID == rhs.restoreID
            && lhs.schemaVersion == rhs.schemaVersion
            && lhs.stagingGenerationRelativePath == rhs.stagingGenerationRelativePath
    }

    func nextPhase(after phase: RestoreIntentPhaseV1) -> RestoreIntentPhaseV1? {
        switch phase {
        case .prepared: .generationInstalled
        case .generationInstalled: .pointerSwitched
        case .pointerSwitched: .newGenerationValidated
        case .newGenerationValidated: nil
        }
    }

    private func readIfPresent(
        _ name: String
    ) throws -> (data: Data, identity: Identity)? {
        let descriptor = Darwin.openat(
            restoreDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw RestoreIntentStoreError.invalidAuthority
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
                throw RestoreIntentStoreError.invalidAuthority
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        return (
            data,
            Identity(device: after.st_dev, inode: after.st_ino)
        )
    }

    func createLeaf(_ name: String, data: Data) throws {
        let descriptor = Darwin.openat(
            restoreDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw RestoreIntentStoreError.writeFailed
        }
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
                        throw RestoreIntentStoreError.writeFailed
                    }
                }
            }
            guard Darwin.fsync(descriptor) == 0 else {
                throw RestoreIntentStoreError.writeFailed
            }
        } catch {
            _ = Darwin.unlinkat(restoreDescriptor, name, 0)
            _ = Darwin.fsync(restoreDescriptor)
            throw error
        }
    }

    func removeMatching(_ name: String, data: Data) throws {
        guard let current = try readIfPresent(name), current.data == data else {
            throw RestoreIntentStoreError.cleanupFailed
        }
        try removeExact(name, expected: current)
    }

    private func removeExact(
        _ name: String,
        expected: (data: Data, identity: Identity)
    ) throws {
        guard let current = try readIfPresent(name),
              current.identity == expected.identity,
              current.data == expected.data,
              Darwin.unlinkat(restoreDescriptor, name, 0) == 0,
              Darwin.fsync(restoreDescriptor) == 0 else {
            throw RestoreIntentStoreError.cleanupFailed
        }
        guard case nil = try readIfPresent(name) else {
            throw RestoreIntentStoreError.cleanupFailed
        }
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func requireDirectory(
        _ descriptor: Int32,
        identity: Identity
    ) throws {
        guard try directoryIdentity(descriptor) == identity else {
            throw RestoreIntentStoreError.invalidAuthority
        }
    }
}

import Darwin
import Foundation

enum EraseIntentStoreError: Error, Equatable {
    case invalidAuthority
    case invalidIntent
    case intentAlreadyExists
    case intentMissing
    case intentMismatch
    case writeFailed
    case cleanupFailed
}

/// Descriptor-pinned authority for the single erase journal. The canonical
/// leaf is never followed through a symbolic link and phase replacement is an
/// atomic exchange whose displaced bytes must equal the expected prior phase.
final class EraseIntentStore {
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static let directoryName = "FieldEvidenceErase"
    private static let intentName = "erase.json"
    private static let nextName = ".erase.json.next"

    private let applicationSupportURL: URL
    private let applicationSupportDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let eraseDescriptor: Int32
    private let eraseIdentity: Identity

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        expectedApplicationSupportIdentity: StoreApplicationSupportIdentity? = nil
    ) throws {
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else { throw EraseIntentStoreError.invalidAuthority }
        if expectedApplicationSupportIdentity == nil {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }
        let appDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard appDescriptor >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        var ownsAppDescriptor = true
        defer {
            if ownsAppDescriptor { _ = Darwin.close(appDescriptor) }
        }
        let appIdentity = try Self.directoryIdentity(appDescriptor)
        if let expectedApplicationSupportIdentity {
            guard appIdentity.device == expectedApplicationSupportIdentity.device,
                  appIdentity.inode == expectedApplicationSupportIdentity.inode else {
                throw EraseIntentStoreError.invalidAuthority
            }
        }

        var eraseDescriptor = Darwin.openat(
            appDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if eraseDescriptor < 0, errno == ENOENT {
            guard Darwin.mkdirat(
                appDescriptor,
                Self.directoryName,
                mode_t(0o700)
            ) == 0 || errno == EEXIST else {
                throw EraseIntentStoreError.invalidAuthority
            }
            eraseDescriptor = Darwin.openat(
                appDescriptor,
                Self.directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
        }
        guard eraseDescriptor >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        var ownsEraseDescriptor = true
        defer {
            if ownsEraseDescriptor { _ = Darwin.close(eraseDescriptor) }
        }
        let eraseIdentity = try Self.directoryIdentity(eraseDescriptor)

        self.applicationSupportURL = root
        self.applicationSupportDescriptor = appDescriptor
        self.applicationSupportIdentity = appIdentity
        self.eraseDescriptor = eraseDescriptor
        self.eraseIdentity = eraseIdentity
        ownsAppDescriptor = false
        ownsEraseDescriptor = false
    }

    deinit {
        _ = Darwin.close(eraseDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func load() throws -> EraseIntentV1? {
        try verifyAuthority()
        let canonical = try readIfPresent(Self.intentName)
        let pending = try readIfPresent(Self.nextName)

        switch (canonical, pending) {
        case (nil, nil):
            return nil
        case (nil, let pending?):
            let value = try decode(pending.data)
            guard value.phase == .emptyGenerationPrepared,
                  Darwin.renameatx_np(
                    eraseDescriptor,
                    Self.nextName,
                    eraseDescriptor,
                    Self.intentName,
                    UInt32(RENAME_EXCL)
                  ) == 0,
                  Darwin.fsync(eraseDescriptor) == 0 else {
                throw EraseIntentStoreError.invalidIntent
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
                throw EraseIntentStoreError.invalidIntent
            }
            try removeExact(Self.nextName, expected: pending)
            return current
        }
    }

    func create(_ value: EraseIntentV1) throws {
        try verifyAuthority()
        guard try readIfPresent(Self.intentName) == nil,
              try readIfPresent(Self.nextName) == nil else {
            throw EraseIntentStoreError.intentAlreadyExists
        }
        let data = try encode(value)
        try createLeaf(Self.nextName, data: data)
        guard Darwin.renameatx_np(
            eraseDescriptor,
            Self.nextName,
            eraseDescriptor,
            Self.intentName,
            UInt32(RENAME_EXCL)
        ) == 0,
              Darwin.fsync(eraseDescriptor) == 0 else {
            try? removeMatching(Self.nextName, data: data)
            throw EraseIntentStoreError.writeFailed
        }
        guard try readIfPresent(Self.intentName)?.data == data else {
            throw EraseIntentStoreError.writeFailed
        }
        try verifyAuthority()
    }

    func replace(
        expected: EraseIntentV1,
        with replacement: EraseIntentV1
    ) throws {
        try verifyAuthority()
        let expectedData = try encode(expected)
        let replacementData = try encode(replacement)
        guard sameOperation(expected, replacement),
              replacement.phase == nextPhase(after: expected.phase),
              try readIfPresent(Self.intentName)?.data == expectedData,
              try readIfPresent(Self.nextName) == nil else {
            throw EraseIntentStoreError.intentMismatch
        }
        try createLeaf(Self.nextName, data: replacementData)
        guard Darwin.renameatx_np(
            eraseDescriptor,
            Self.nextName,
            eraseDescriptor,
            Self.intentName,
            UInt32(RENAME_SWAP)
        ) == 0 else {
            try? removeMatching(Self.nextName, data: replacementData)
            throw EraseIntentStoreError.writeFailed
        }
        do {
            guard Darwin.fsync(eraseDescriptor) == 0,
                  try readIfPresent(Self.intentName)?.data == replacementData,
                  try readIfPresent(Self.nextName)?.data == expectedData else {
                throw EraseIntentStoreError.writeFailed
            }
            try removeMatching(Self.nextName, data: expectedData)
            try verifyAuthority()
        } catch {
            if try readIfPresent(Self.intentName)?.data == replacementData,
               try readIfPresent(Self.nextName)?.data == expectedData {
                _ = Darwin.renameatx_np(
                    eraseDescriptor,
                    Self.nextName,
                    eraseDescriptor,
                    Self.intentName,
                    UInt32(RENAME_SWAP)
                )
                _ = Darwin.fsync(eraseDescriptor)
            }
            throw error
        }
    }

    func remove(expected: EraseIntentV1) throws {
        try verifyAuthority()
        let data = try encode(expected)
        guard let current = try readIfPresent(Self.intentName) else {
            throw EraseIntentStoreError.intentMissing
        }
        guard current.data == data else {
            throw EraseIntentStoreError.intentMismatch
        }
        try removeExact(Self.intentName, expected: current)
        try verifyAuthority()
    }
}

private extension EraseIntentStore {
    func verifyAuthority() throws {
        try Self.requireDirectory(
            applicationSupportDescriptor,
            identity: applicationSupportIdentity
        )
        try Self.requireDirectory(eraseDescriptor, identity: eraseIdentity)
        let reopenedApp = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedApp >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedApp) }
        guard try Self.directoryIdentity(reopenedApp) == applicationSupportIdentity else {
            throw EraseIntentStoreError.invalidAuthority
        }
        let reopenedErase = Darwin.openat(
            reopenedApp,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedErase >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedErase) }
        guard try Self.directoryIdentity(reopenedErase) == eraseIdentity else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }

    func encode(_ value: EraseIntentV1) throws -> Data {
        do { return try EraseIntentCodecV1.encode(value) }
        catch { throw EraseIntentStoreError.invalidIntent }
    }

    func decode(_ data: Data) throws -> EraseIntentV1 {
        do { return try EraseIntentCodecV1.decode(data) }
        catch { throw EraseIntentStoreError.invalidIntent }
    }

    func sameOperation(_ lhs: EraseIntentV1, _ rhs: EraseIntentV1) -> Bool {
        lhs.auxiliaryRoots == rhs.auxiliaryRoots
            && lhs.eraseID == rhs.eraseID
            && lhs.generationIDsToDelete == rhs.generationIDsToDelete
            && lhs.newGenerationID == rhs.newGenerationID
            && lhs.oldGenerationID == rhs.oldGenerationID
            && lhs.schemaVersion == rhs.schemaVersion
    }

    func nextPhase(after phase: EraseIntentPhaseV1) -> EraseIntentPhaseV1? {
        switch phase {
        case .emptyGenerationPrepared: .pointerSwitched
        case .pointerSwitched: .sessionActivated
        case .sessionActivated: .cleanupComplete
        case .cleanupComplete: nil
        }
    }

    private func readIfPresent(
        _ name: String
    ) throws -> (data: Data, identity: Identity)? {
        let descriptor = Darwin.openat(
            eraseDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw EraseIntentStoreError.invalidAuthority
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
                throw EraseIntentStoreError.invalidAuthority
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw EraseIntentStoreError.invalidAuthority
        }
        return (
            data,
            Identity(device: after.st_dev, inode: after.st_ino)
        )
    }

    func createLeaf(_ name: String, data: Data) throws {
        let descriptor = Darwin.openat(
            eraseDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw EraseIntentStoreError.writeFailed
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
                        throw EraseIntentStoreError.writeFailed
                    }
                }
            }
            guard Darwin.fsync(descriptor) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
        } catch {
            _ = Darwin.unlinkat(eraseDescriptor, name, 0)
            _ = Darwin.fsync(eraseDescriptor)
            throw error
        }
    }

    func removeMatching(_ name: String, data: Data) throws {
        guard let current = try readIfPresent(name), current.data == data else {
            throw EraseIntentStoreError.cleanupFailed
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
              Darwin.unlinkat(eraseDescriptor, name, 0) == 0,
              Darwin.fsync(eraseDescriptor) == 0 else {
            throw EraseIntentStoreError.cleanupFailed
        }
        guard case nil = try readIfPresent(name) else {
            throw EraseIntentStoreError.cleanupFailed
        }
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseIntentStoreError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func requireDirectory(
        _ descriptor: Int32,
        identity: Identity
    ) throws {
        guard try directoryIdentity(descriptor) == identity else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }
}

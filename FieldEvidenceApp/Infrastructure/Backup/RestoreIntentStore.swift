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
        let linkCount: nlink_t

        init(device: dev_t, inode: ino_t, linkCount: nlink_t = 0) {
            self.device = device
            self.inode = inode
            self.linkCount = linkCount
        }
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
        try ProtectedFilePolicyV1.applyAndVerify(
            .stagingDirectory,
            at: root.appendingPathComponent(Self.directoryName, isDirectory: true),
            authorityCheck: { try self.verifyAuthority() }
        )
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
            try protect(
                .journalTemporary,
                name: Self.nextName,
                expected: pending.identity
            )
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
            try protect(
                .journal,
                name: Self.intentName,
                expected: pending.identity
            )
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
        let temporaryIdentity = try createLeaf(Self.nextName, data: data)
        try protect(
            .journalTemporary,
            name: Self.nextName,
            expected: temporaryIdentity
        )
        guard Darwin.renameatx_np(
            restoreDescriptor,
            Self.nextName,
            restoreDescriptor,
            Self.intentName,
            UInt32(RENAME_EXCL)
        ) == 0,
                  Darwin.fsync(restoreDescriptor) == 0 else {
            do {
                try removeMatching(Self.nextName, data: data)
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw failure
            } catch {
                // The original rename/fsync failure remains authoritative.
            }
            throw RestoreIntentStoreError.writeFailed
        }
        try protect(
            .journal,
            name: Self.intentName,
            expected: temporaryIdentity
        )
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
               let current = try readIfPresent(Self.intentName),
               current.data == expectedData,
               try readIfPresent(Self.nextName) == nil else {
            throw RestoreIntentStoreError.intentMismatch
        }
        let expectedIdentity = current.identity
        let replacementIdentity = try createLeaf(
            Self.nextName,
            data: replacementData
        )
        try protect(
            .journalTemporary,
            name: Self.nextName,
            expected: replacementIdentity
        )
        guard Darwin.renameatx_np(
            restoreDescriptor,
            Self.nextName,
            restoreDescriptor,
            Self.intentName,
            UInt32(RENAME_SWAP)
        ) == 0 else {
            do {
                try removeMatching(Self.nextName, data: replacementData)
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw failure
            } catch {
                // The failed exchange remains the authoritative outcome.
            }
            throw RestoreIntentStoreError.writeFailed
        }
        do {
            guard Darwin.fsync(restoreDescriptor) == 0 else {
                throw RestoreIntentStoreError.writeFailed
            }
            try protect(
                .journal,
                name: Self.intentName,
                expected: replacementIdentity
            )
            try protect(
                .journalTemporary,
                name: Self.nextName,
                expected: expectedIdentity
            )
            guard try readIfPresent(Self.intentName)?.data == replacementData,
                  try readIfPresent(Self.nextName)?.data == expectedData else {
                throw RestoreIntentStoreError.writeFailed
            }
            try removeMatching(Self.nextName, data: expectedData)
            try verifyAuthority()
        } catch {
            if let current = try? readIfPresent(
                Self.intentName,
                verifyPolicy: false
            ),
               let pending = try? readIfPresent(
                   Self.nextName,
                   verifyPolicy: false
               ),
               current.identity == replacementIdentity,
               pending.identity == expectedIdentity,
               current.data == replacementData,
               pending.data == expectedData {
                _ = Darwin.renameatx_np(
                    restoreDescriptor,
                    Self.nextName,
                    restoreDescriptor,
                    Self.intentName,
                    UInt32(RENAME_SWAP)
                )
                _ = Darwin.fsync(restoreDescriptor)
                try? protect(
                    .journal,
                    name: Self.intentName,
                    expected: expectedIdentity
                )
                try? protect(
                    .journalTemporary,
                    name: Self.nextName,
                    expected: replacementIdentity
                )
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
    func protect(
        _ kind: OwnedFileKindV1,
        name: String,
        expected: Identity? = nil
    ) throws {
        let identity: Identity
        if let expected {
            identity = expected
        } else {
            identity = try leafIdentity(name)
        }
        try verifyLeafIdentity(name, expected: identity)
        try ProtectedFilePolicyV1.applyAndVerify(
            kind,
            at: path(for: name),
            authorityCheck: {
                try verifyAuthority()
                try verifyLeafIdentity(name, expected: identity)
            }
        )
        try verifyLeafIdentity(name, expected: identity)
    }

    func path(for name: String) -> URL {
        applicationSupportURL
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }

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
            && lhs.identity == rhs.identity
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
        _ name: String,
        verifyPolicy: Bool = true
    ) throws -> (data: Data, identity: Identity)? {
        try verifyAuthority()
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
        let beforeIdentity = Identity(
            device: before.st_dev,
            inode: before.st_ino,
            linkCount: before.st_nlink
        )
        try verifyLeafIdentity(name, expected: beforeIdentity)
        let kind: OwnedFileKindV1 = name == Self.intentName
            ? .journal
            : .journalTemporary
        if verifyPolicy {
            try ProtectedFilePolicyV1.verify(kind, at: path(for: name))
        }
        try verifyLeafIdentity(name, expected: beforeIdentity)
        try verifyAuthority()
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
               before.st_nlink == after.st_nlink,
               before.st_size == after.st_size,
               data.count == Int(after.st_size),
               try leafIdentity(name) == beforeIdentity else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        return (
            data,
            Identity(
                device: after.st_dev,
                inode: after.st_ino,
                linkCount: after.st_nlink
            )
        )
    }

    func createLeaf(_ name: String, data: Data) throws -> Identity {
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
        var createdIdentity: Identity?
        do {
            var initial = stat()
            guard Darwin.fstat(descriptor, &initial) == 0,
                  (initial.st_mode & S_IFMT) == S_IFREG,
                  initial.st_nlink == 1 else {
                throw RestoreIntentStoreError.writeFailed
            }
            createdIdentity = Identity(
                device: initial.st_dev,
                inode: initial.st_ino,
                linkCount: initial.st_nlink
            )
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
            var info = stat()
            guard let expectedIdentity = createdIdentity,
                  Darwin.fstat(descriptor, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_nlink == 1,
                  Identity(
                      device: info.st_dev,
                      inode: info.st_ino,
                      linkCount: info.st_nlink
                  ) == expectedIdentity else {
                throw RestoreIntentStoreError.writeFailed
            }
            try verifyLeafIdentity(name, expected: expectedIdentity)
            return expectedIdentity
        } catch {
            if let createdIdentity,
               let currentIdentity = try? leafIdentity(name),
               currentIdentity == createdIdentity {
                _ = Darwin.unlinkat(restoreDescriptor, name, 0)
                _ = Darwin.fsync(restoreDescriptor)
            }
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
              let currentIdentity = try? leafIdentity(name),
              currentIdentity == expected.identity,
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

    private func leafIdentity(_ name: String) throws -> Identity {
        var info = stat()
        guard Darwin.fstatat(
            restoreDescriptor,
            name,
            &info,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw RestoreIntentStoreError.invalidAuthority
        }
        return Identity(
            device: info.st_dev,
            inode: info.st_ino,
            linkCount: info.st_nlink
        )
    }

    private func verifyLeafIdentity(
        _ name: String,
        expected: Identity
    ) throws {
        guard try leafIdentity(name) == expected else {
            throw RestoreIntentStoreError.invalidAuthority
        }
    }
}

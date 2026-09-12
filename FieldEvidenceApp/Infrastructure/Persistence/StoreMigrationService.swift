import Darwin
import Foundation

/// The one aggregate control reader is also used by lease admission/owner
/// cleanup. Opening it never creates paths; its caller owns the mutation lock.
final class StoreAggregateMigrationControlV1 {
    static let name = "aggregate.json"
    static let temporaryName = "aggregate.next.json"
    private static let maximumBytes = 4 * 1024 * 1024

    struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }
    private struct Directory {
        let descriptor: Int32
        let name: String
        let device: UInt64
        let inode: UInt64
    }
    private let rootURL: URL
    private var chain: [Directory] = []
    private var descriptor: Int32 { chain.last!.descriptor }

    final class Allocation {
        let id: UUID
        let descriptor: Int32
        let device: UInt64
        let inode: UInt64
        fileprivate init(id: UUID, descriptor: Int32, device: UInt64, inode: UInt64) {
            self.id = id; self.descriptor = descriptor; self.device = device; self.inode = inode
        }
        deinit { _ = Darwin.close(descriptor) }
    }

    static func allocationID(for name: String) -> UUID? {
        guard name.hasPrefix("allocation-"), let id = UUID(uuidString: String(name.dropFirst(11))),
              name == "allocation-" + id.uuidString.lowercased(), id != GenerationEpochV1.zeroUUID else { return nil }
        return id
    }

    func requireNoConflictingIntentAuthority() throws {
        try verify()
        for name in ["FieldEvidenceRestore", "FieldEvidenceErase"] {
            let opened = Darwin.openat(chain[0].descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if opened < 0, errno == ENOENT { continue }
            guard opened >= 0 else { throw StoreMigrationFailure.invalidIdentity }
            defer { _ = Darwin.close(opened) }
            var initial = stat(), named = stat()
            guard Darwin.fstat(opened, &initial) == 0 else { throw StoreMigrationFailure.invalidIdentity }
            let names = try StoreRestoreGenerationAuthority.names(in: opened)
            if name == "FieldEvidenceErase" {
                guard names.isEmpty else { throw StoreMigrationFailure.maintenanceRequired(.invalidJournal) }
            } else {
                guard Set(names).isDisjoint(with: ["restore.json", ".restore.json.next"]) else {
                    throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
                }
            }
            guard Darwin.fstatat(chain[0].descriptor, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_mode & S_IFMT == S_IFDIR,
                  named.st_dev == initial.st_dev, named.st_ino == initial.st_ino else {
                throw StoreMigrationFailure.invalidIdentity
            }
        }
        try verify()
    }

    func createAllocation(expected: StoreAggregateMigrationJournalV1) throws -> Allocation {
        guard expected.phase == .sourceFrozen, expected.allocationID == nil,
              try load() == expected else { throw StoreMigrationFailure.invalidPhaseTransition }
        try verify()
        let id = UUID(), name = "allocation-" + id.uuidString.lowercased()
        guard Darwin.mkdirat(descriptor, name, mode_t(0o700)) == 0 else { throw StoreMigrationFailure.invalidIdentity }
        // A crash here leaves only unbound evidence. No retry will adopt it.
        let opened = Darwin.openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard opened >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        var info = stat()
        guard Darwin.fstat(opened, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            _ = Darwin.close(opened); throw StoreMigrationFailure.invalidIdentity
        }
        let allocation = Allocation(id: id, descriptor: opened, device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
        try verifyAllocation(allocation)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory,
            at: rootURL.appendingPathComponent("FieldEvidenceOperations/schema-migration/" + name),
            authorityCheck: { try self.verifyAllocation(allocation) })
        guard Darwin.fsync(opened) == 0, Darwin.fsync(descriptor) == 0 else { throw StoreMigrationFailure.invalidIdentity }
        try verifyAllocation(allocation)
        return allocation
    }

    func verifyAllocation(_ allocation: Allocation) throws {
        try verify()
        var opened = stat(), named = stat()
        guard Darwin.fstat(allocation.descriptor, &opened) == 0,
              Darwin.fstatat(descriptor, "allocation-" + allocation.id.uuidString.lowercased(), &named, AT_SYMLINK_NOFOLLOW) == 0,
              opened.st_mode & S_IFMT == S_IFDIR, named.st_mode & S_IFMT == S_IFDIR,
              UInt64(opened.st_dev) == allocation.device, UInt64(opened.st_ino) == allocation.inode,
              UInt64(named.st_dev) == allocation.device, UInt64(named.st_ino) == allocation.inode else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    func publishBoundAllocation(_ journal: StoreAggregateMigrationJournalV1,
                                afterRenameBeforeSync: () throws -> Void = {}) throws {
        guard journal.phase == .sourceFrozen, let allocationID = journal.allocationID,
              let device = journal.candidateRootDevice, let inode = journal.candidateRootInode,
              try load() == journal else { throw StoreMigrationFailure.invalidPhaseTransition }
        try verify()
        // Derive the actual destination from this control owner's pinned root;
        // no independently supplied FD, URL or callback grants authority.
        let restore = Darwin.openat(chain[0].descriptor, "FieldEvidenceRestore", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard restore >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        defer { _ = Darwin.close(restore) }
        let destinationParent = Darwin.openat(restore, "generations", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard destinationParent >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        defer { _ = Darwin.close(destinationParent) }
        var restoreInfo = stat(), destinationInfo = stat()
        guard Darwin.fstat(restore, &restoreInfo) == 0, Darwin.fstat(destinationParent, &destinationInfo) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        func reproveDestination() throws {
            try verify()
            for (parent, name, opened, expected) in [
                (chain[0].descriptor, "FieldEvidenceRestore", restore, restoreInfo),
                (restore, "generations", destinationParent, destinationInfo),
            ] {
                var named = stat(), current = stat()
                guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                      Darwin.fstat(opened, &current) == 0,
                      named.st_mode & S_IFMT == S_IFDIR, current.st_mode & S_IFMT == S_IFDIR,
                      named.st_dev == expected.st_dev, named.st_ino == expected.st_ino,
                      current.st_dev == expected.st_dev, current.st_ino == expected.st_ino else {
                    throw StoreMigrationFailure.invalidIdentity
                }
            }
        }
        try reproveDestination()
        var parent = stat()
        guard Darwin.fstat(destinationParent, &parent) == 0, parent.st_mode & S_IFMT == S_IFDIR,
              UInt64(parent.st_dev) == device else { throw StoreMigrationFailure.invalidIdentity }
        let allocationName = "allocation-" + allocationID.uuidString.lowercased()
        let targetName = journal.targetGenerationID.uuidString.lowercased()
        func presence(_ parent: Int32, _ name: String) throws -> Bool {
            var info = stat()
            if Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { return false }
                throw StoreMigrationFailure.invalidIdentity
            }
            guard info.st_mode & S_IFMT == S_IFDIR, UInt64(info.st_dev) == device, UInt64(info.st_ino) == inode else {
                throw StoreMigrationFailure.invalidIdentity
            }
            return true
        }
        let atAllocation = try presence(descriptor, allocationName)
        let atTarget = try presence(destinationParent, targetName)
        guard atAllocation != atTarget else { throw StoreMigrationFailure.invalidIdentity }
        if atAllocation {
            let opened = Darwin.openat(descriptor, allocationName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard opened >= 0 else { throw StoreMigrationFailure.invalidIdentity }
            let allocation = Allocation(id: allocationID, descriptor: opened, device: device, inode: inode)
            try verifyAllocation(allocation)
            guard try StoreRestoreGenerationAuthority.names(in: opened).isEmpty else { throw StoreMigrationFailure.invalidIdentity }
            try reproveDestination(); try verifyAllocation(allocation)
            guard Darwin.renameatx_np(descriptor, allocationName, destinationParent, targetName, UInt32(RENAME_EXCL)) == 0 else {
                throw StoreMigrationFailure.invalidIdentity
            }
            try afterRenameBeforeSync()
        }
        try verify(); try reproveDestination()
        guard try !presence(descriptor, allocationName), try presence(destinationParent, targetName) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        // A target-only retry may be the first process after rename but before
        // either parent sync. Complete both durability obligations every time.
        guard Darwin.fsync(descriptor) == 0, Darwin.fsync(destinationParent) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try verify(); try reproveDestination()
        guard try !presence(descriptor, allocationName), try presence(destinationParent, targetName) else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    init?(applicationSupportURL: URL) throws {
        rootURL = applicationSupportURL.standardizedFileURL
        guard rootURL.isFileURL else { throw StoreMigrationFailure.invalidPath }
        let root = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if root < 0, errno == ENOENT { return nil }
        guard root >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        do {
            var info = stat()
            guard Darwin.fstat(root, &info) == 0 else { _ = Darwin.close(root); throw StoreMigrationFailure.invalidIdentity }
            chain.append(Directory(descriptor: root, name: "", device: UInt64(info.st_dev), inode: UInt64(info.st_ino)))
            for name in ["FieldEvidenceOperations", "schema-migration"] {
                let child = Darwin.openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                if child < 0, errno == ENOENT { close(); return nil }
                guard child >= 0 else { throw StoreMigrationFailure.invalidIdentity }
                guard Darwin.fstat(child, &info) == 0 else { _ = Darwin.close(child); throw StoreMigrationFailure.invalidIdentity }
                chain.append(Directory(descriptor: child, name: name, device: UInt64(info.st_dev), inode: UInt64(info.st_ino)))
            }
            try verify()
        } catch { close(); throw error }
    }
    deinit { close() }
    private func close() { for entry in chain.reversed() { _ = Darwin.close(entry.descriptor) }; chain.removeAll() }

    private func verify() throws {
        guard !chain.isEmpty else { throw StoreMigrationFailure.invalidIdentity }
        for (index, entry) in chain.enumerated() {
            var info = stat()
            guard Darwin.fstat(entry.descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  UInt64(info.st_dev) == entry.device, UInt64(info.st_ino) == entry.inode else { throw StoreMigrationFailure.invalidIdentity }
            let result = index == 0
                ? Darwin.lstat(rootURL.path, &info)
                : Darwin.fstatat(chain[index - 1].descriptor, entry.name, &info, AT_SYMLINK_NOFOLLOW)
            guard result == 0, info.st_mode & S_IFMT == S_IFDIR,
                  UInt64(info.st_dev) == entry.device, UInt64(info.st_ino) == entry.inode else { throw StoreMigrationFailure.invalidIdentity }
        }
    }

    private static func identity(_ descriptor: Int32) throws -> FileIdentity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size >= 0, info.st_size <= maximumBytes else { throw StoreMigrationFailure.invalidIdentity }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    static func readFile(parent: Int32, name: String) throws -> (Data, FileIdentity)? {
        let fd = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        defer { _ = Darwin.close(fd) }
        let before = try identity(fd)
        var bytes = Data(count: Int(before.size))
        try bytes.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw StoreMigrationFailure.invalidIdentity }
                offset += count
            }
        }
        guard try identity(fd) == before else { throw StoreMigrationFailure.invalidIdentity }
        var named = stat()
        guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFREG, named.st_nlink == 1,
              UInt64(named.st_dev) == before.device, UInt64(named.st_ino) == before.inode else { throw StoreMigrationFailure.invalidIdentity }
        return (bytes, before)
    }

    /// A not-yet-published initial temporary is still exclusive intent. Readers
    /// must deny admission until the journal owner reconciles it.
    func load() throws -> StoreAggregateMigrationJournalV1? {
        try verify()
        let current = try Self.readFile(parent: descriptor, name: Self.name)
        let temporary = try Self.readFile(parent: descriptor, name: Self.temporaryName)
        let value = try current.map { try StoreAggregateMigrationJournalV1.decodeCanonical(from: $0.0) }
        if let temporary {
            let pending = try StoreAggregateMigrationJournalV1.decodeCanonical(from: temporary.0)
            if let value {
                if pending.revision == value.revision + 1 { try pending.validateReplacement(of: value) }
                else if value.revision == pending.revision + 1 { try value.validateReplacement(of: pending) }
                else { throw StoreMigrationFailure.invalidPhaseTransition }
            } else {
                guard pending.phase == .recoveringSource, pending.revision == 0 else { throw StoreMigrationFailure.invalidPhaseTransition }
            }
            try verify()
            return value ?? pending
        }
        try verify()
        return value
    }

    func reconcile() throws {
        _ = try load()
        guard let temporary = try Self.readFile(parent: descriptor, name: Self.temporaryName) else { return }
        let pending = try StoreAggregateMigrationJournalV1.decodeCanonical(from: temporary.0)
        if let current = try Self.readFile(parent: descriptor, name: Self.name) {
            let value = try StoreAggregateMigrationJournalV1.decodeCanonical(from: current.0)
            if pending.revision == value.revision + 1 { try pending.validateReplacement(of: value) }
            else if value.revision == pending.revision + 1 { try value.validateReplacement(of: pending) }
            else { throw StoreMigrationFailure.invalidPhaseTransition }
            guard try Self.readFile(parent: descriptor, name: Self.name)?.1 == current.1 else { throw StoreMigrationFailure.invalidIdentity }
            try unlink(Self.temporaryName, expected: temporary.1)
        } else {
            guard pending.phase == .recoveringSource, pending.revision == 0 else { throw StoreMigrationFailure.invalidPhaseTransition }
            try verify()
            guard try Self.readFile(parent: descriptor, name: Self.temporaryName)?.1 == temporary.1,
                  Darwin.renameatx_np(descriptor, Self.temporaryName, descriptor, Self.name, UInt32(RENAME_EXCL)) == 0,
                  Darwin.fsync(descriptor) == 0 else { throw StoreMigrationFailure.invalidIdentity }
            guard let published = try Self.readFile(parent: descriptor, name: Self.name),
                  published.0 == temporary.0, published.1.device == temporary.1.device,
                  published.1.inode == temporary.1.inode else { throw StoreMigrationFailure.invalidIdentity }
        }
        try verify()
    }

    func write(_ value: StoreAggregateMigrationJournalV1, expected: StoreAggregateMigrationJournalV1?) throws {
        try value.validate()
        if let expected { try value.validateReplacement(of: expected) }
        else { guard value.phase == .recoveringSource, value.revision == 0 else { throw StoreMigrationFailure.invalidPhaseTransition } }
        try reconcile()
        guard try load() == expected else { throw StoreMigrationFailure.invalidPhaseTransition }
        let prior = try Self.readFile(parent: descriptor, name: Self.name)
        let data = try value.canonicalData()
        guard data.count <= Self.maximumBytes else { throw StoreMigrationFailure.invalidContract }
        let fd = Darwin.openat(descriptor, Self.temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        defer { _ = Darwin.close(fd) }
        try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw StoreMigrationFailure.invalidIdentity }
                    offset += count
                }
        }
        guard Darwin.fsync(fd) == 0 else { throw StoreMigrationFailure.invalidIdentity }
        let created = try Self.identity(fd)
        func reproveCreated(_ name: String) throws {
            try verify()
            let openIdentity = try Self.identity(fd)
            guard openIdentity.device == created.device, openIdentity.inode == created.inode,
                  let named = try Self.readFile(parent: descriptor, name: name),
                  named.1.device == created.device, named.1.inode == created.inode else { throw StoreMigrationFailure.invalidIdentity }
        }
        let temporaryURL = rootURL.appendingPathComponent("FieldEvidenceOperations/schema-migration/\(Self.temporaryName)")
        try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: temporaryURL,
            authorityCheck: { try reproveCreated(Self.temporaryName) })
        try reproveCreated(Self.temporaryName)
        guard let temporary = try Self.readFile(parent: descriptor, name: Self.temporaryName), temporary.0 == data else { throw StoreMigrationFailure.invalidIdentity }
        try verify()
        guard try Self.readFile(parent: descriptor, name: Self.name)?.0 == prior?.0 else { throw StoreMigrationFailure.invalidIdentity }
        if let prior {
            guard try Self.readFile(parent: descriptor, name: Self.temporaryName)?.1 == temporary.1,
                  try Self.readFile(parent: descriptor, name: Self.name)?.1 == prior.1,
                  Darwin.renameatx_np(descriptor, Self.temporaryName, descriptor, Self.name, UInt32(RENAME_SWAP)) == 0,
                  Darwin.fsync(descriptor) == 0 else { throw StoreMigrationFailure.invalidIdentity }
            guard let displaced = try Self.readFile(parent: descriptor, name: Self.temporaryName),
                  displaced.0 == prior.0, displaced.1.device == prior.1.device, displaced.1.inode == prior.1.inode else {
                throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
            }
            try unlink(Self.temporaryName, expected: displaced.1)
        } else {
            guard try Self.readFile(parent: descriptor, name: Self.temporaryName)?.1 == temporary.1,
                  Darwin.renameatx_np(descriptor, Self.temporaryName, descriptor, Self.name, UInt32(RENAME_EXCL)) == 0,
                  Darwin.fsync(descriptor) == 0 else { throw StoreMigrationFailure.invalidIdentity }
        }
        try reproveCreated(Self.name)
        guard try load() == value else { throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired) }
        try ProtectedFilePolicyV1.applyAndVerify(.journal,
            at: rootURL.appendingPathComponent("FieldEvidenceOperations/schema-migration/\(Self.name)"),
            authorityCheck: { try reproveCreated(Self.name) })
    }

    private func unlink(_ name: String, expected: FileIdentity) throws {
        try verify()
        guard try Self.readFile(parent: descriptor, name: name)?.1 == expected,
              Darwin.unlinkat(descriptor, name, 0) == 0, Darwin.fsync(descriptor) == 0 else { throw StoreMigrationFailure.invalidIdentity }
    }

    func withOriginalSource<T>(_ journal: StoreAggregateMigrationJournalV1,
                               _ operation: () throws -> T) throws -> T {
        try verify()
        var sourceChain = [Directory]()
        defer { for entry in sourceChain.reversed() { _ = Darwin.close(entry.descriptor) } }
        var parent = chain[0].descriptor
        for name in ["FieldEvidenceData", "generations", journal.sourceGenerationID.uuidString.lowercased()] {
            let fd = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { throw StoreMigrationFailure.invalidIdentity }
            var info = stat()
            guard Darwin.fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
                _ = Darwin.close(fd); throw StoreMigrationFailure.invalidIdentity
            }
            sourceChain.append(Directory(descriptor: fd, name: name, device: UInt64(info.st_dev), inode: UInt64(info.st_ino)))
            parent = fd
        }
        guard let source = sourceChain.last, source.device == journal.sourceRootDevice,
              source.inode == journal.sourceRootInode,
              let pointer = try Self.readFile(parent: sourceChain[0].descriptor, name: "current.json"),
              pointer.0 == journal.originalPointerData else { throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch) }
        func reprove() throws {
            try verify()
            var parent = chain[0].descriptor
            for entry in sourceChain {
                var info = stat()
                guard Darwin.fstat(entry.descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                      UInt64(info.st_dev) == entry.device, UInt64(info.st_ino) == entry.inode,
                      Darwin.fstatat(parent, entry.name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                      info.st_mode & S_IFMT == S_IFDIR, UInt64(info.st_dev) == entry.device,
                      UInt64(info.st_ino) == entry.inode else { throw StoreMigrationFailure.invalidIdentity }
                parent = entry.descriptor
            }
            guard let current = try Self.readFile(parent: sourceChain[0].descriptor, name: "current.json"),
                  current.0 == pointer.0, current.1 == pointer.1 else { throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch) }
        }
        try reprove()
        let result = try operation()
        try reprove()
        return result
    }

    func verifyOriginalSource(_ journal: StoreAggregateMigrationJournalV1) throws { try withOriginalSource(journal) {} }
}

/// No ModelContext or actor state crosses this synchronization seam. Every
/// recovery save/filesystem mutation is fenced inside one synchronous body.
final class StoreMigrationSourceMutationGuardV1: @unchecked Sendable {
    private let registry: GenerationLeaseRegistryV1
    private let control: StoreAggregateMigrationControlV1
    private let expected: StoreAggregateMigrationJournalV1
    // Registry lock -> capability lock is the sole operation lock ordering.
    // Revocation takes only the capability lock before any fallible FS proof.
    private let capabilityLock = NSRecursiveLock()
    private var revoked = false

    init(registry: GenerationLeaseRegistryV1, control: StoreAggregateMigrationControlV1,
         expected: StoreAggregateMigrationJournalV1) throws {
        self.registry = registry; self.control = control; self.expected = expected
        try validateCurrent()
    }
    func validateCurrent() throws { try withAuthorizedMutation {} }
    func withAuthorizedMutation<T>(_ operation: () throws -> T) throws -> T {
        try registry.withExclusiveGenerationMutationLock {
            capabilityLock.lock()
            defer { capabilityLock.unlock() }
            guard !revoked, expected.phase == .recoveringSource, expected.ownerID == registry.ownerID,
                  try control.load() == expected else { throw StoreMigrationFailure.maintenanceRequired(.sourceMismatch) }
            return try control.withOriginalSource(expected, operation)
        }
    }
    func revoke() throws {
        capabilityLock.lock()
        revoked = true
        capabilityLock.unlock()
        // Failure here is still reported, but cannot revive the local latch.
        try registry.withExclusiveGenerationMutationLock {}
    }
}

/// Descriptor-pinned storage for the one active schema-migration journal and
/// immutable activation manifests. All artifacts are operational evidence and
/// therefore use the backup-excluded journal policy from P01-C02.
@MainActor
final class StoreMigrationJournalStoreV1 {
    private struct PreparedMigrationEnvelopeV1: Codable, Equatable {
        let schemaVersion: Int
        let journal: StoreMigrationJournalV1
        let journalDigest: String
        let sourceManifest: StoreGenerationManifestV1
        let sourceManifestDigest: String
        let journalWasPresent: Bool
        let sourceManifestWasPresent: Bool

        init(
            journal: StoreMigrationJournalV1,
            sourceManifest: StoreGenerationManifestV1,
            journalWasPresent: Bool,
            sourceManifestWasPresent: Bool
        ) throws {
            schemaVersion = 1
            self.journal = journal
            journalDigest = try journal.canonicalSHA256()
            self.sourceManifest = sourceManifest
            sourceManifestDigest = try sourceManifest.canonicalSHA256()
            self.journalWasPresent = journalWasPresent
            self.sourceManifestWasPresent = sourceManifestWasPresent
            try validate()
        }

        func validate() throws {
            try journal.validate()
            try sourceManifest.validate()
            let exactJournalDigest = try journal.canonicalSHA256()
            let exactManifestDigest = try sourceManifest.canonicalSHA256()
            guard schemaVersion == 1,
                  journal.phase == .prepared,
                  journalDigest == exactJournalDigest,
                  sourceManifestDigest == exactManifestDigest,
                  sourceManifestDigest == journal.sourceManifestDigest,
                  sourceManifest.generationID == journal.sourceGenerationID,
                  sourceManifest.migrationID == journal.migrationID,
                  sourceManifest.storeSchemaRelease == journal.sourceRelease,
                  sourceManifest.frozenIdentityDigest
                    == journal.frozenIdentityDigest,
                  !sourceManifest.files.isEmpty else {
                throw StoreMigrationFailure.invalidContract
            }
            try sourceManifest.files.forEach { try $0.validate() }
        }

        func canonicalData() throws -> Data {
            try validate()
            return try StoreMigrationCanonicalJSONV1.encode(self)
        }

        static func decodeCanonical(from data: Data) throws -> Self {
            try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
                Self.self,
                from: data,
                validate: { try $0.validate() }
            )
        }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
        let type: mode_t

        init(_ information: stat) {
            device = information.st_dev
            inode = information.st_ino
            linkCount = information.st_nlink
            type = information.st_mode & S_IFMT
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            // Creating an owned child changes directory membership, not the
            // identity of the directory. Every directory read still verifies
            // its type and positive link count; regular files remain single-link.
            lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.type == rhs.type
                && (lhs.type == S_IFDIR || lhs.linkCount == rhs.linkCount)
        }
    }

    private struct FileSnapshot: Equatable {
        let identity: Identity
        let byteCount: off_t
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        init(_ information: stat) {
            identity = Identity(information)
            byteCount = information.st_size
            modifiedSeconds = Int64(information.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(information.st_mtimespec.tv_nsec)
            changedSeconds = Int64(information.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(information.st_ctimespec.tv_nsec)
        }
    }

    private static let operationsName = "FieldEvidenceOperations"
    private static let migrationName = "schema-migration"
    private static let journalName = "journal.json"
    private static let journalTemporaryName = "journal.next.json"
    private static let preparedEnvelopeName = "prepared-migration.json"
    private static let preparedEnvelopeTemporaryName =
        "prepared-migration.next.json"
    private static let deletionSuffix = ".deleting"
    private static let maximumOwnedArtifactByteCount = 4 * 1024 * 1024

    private let applicationSupportURL: URL
    private let operationsURL: URL
    private let migrationURL: URL
    private let applicationSupportDescriptor: Int32
    private let operationsDescriptor: Int32
    private let migrationDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let operationsIdentity: Identity
    private let migrationIdentity: Identity

    init(applicationSupportURL: URL) throws {
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else {
            throw StoreMigrationFailure.invalidPath
        }

        let rootDescriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }

        var retained = [rootDescriptor]
        var succeeded = false
        defer {
            if !succeeded {
                retained.reversed().forEach { _ = Darwin.close($0) }
            }
        }
        do {
            let rootIdentity = try Self.directoryIdentity(rootDescriptor)
            let operationsDescriptor = try Self.openOrCreateDirectory(
                parent: rootDescriptor,
                name: Self.operationsName
            )
            retained.append(operationsDescriptor)
            let operationsIdentity = try Self.directoryIdentity(
                operationsDescriptor
            )
            let migrationDescriptor = try Self.openOrCreateDirectory(
                parent: operationsDescriptor,
                name: Self.migrationName
            )
            retained.append(migrationDescriptor)
            let migrationIdentity = try Self.directoryIdentity(
                migrationDescriptor
            )

            self.applicationSupportURL = root
            self.operationsURL = root.appendingPathComponent(
                Self.operationsName,
                isDirectory: true
            )
            self.migrationURL = self.operationsURL.appendingPathComponent(
                Self.migrationName,
                isDirectory: true
            )
            self.applicationSupportDescriptor = rootDescriptor
            self.operationsDescriptor = operationsDescriptor
            self.migrationDescriptor = migrationDescriptor
            self.applicationSupportIdentity = rootIdentity
            self.operationsIdentity = operationsIdentity
            self.migrationIdentity = migrationIdentity
            try protectDirectory(.stagingDirectory, at: self.operationsURL)
            try protectDirectory(.stagingDirectory, at: self.migrationURL)
            guard Darwin.fsync(migrationDescriptor) == 0,
                  Darwin.fsync(operationsDescriptor) == 0,
                  Darwin.fsync(rootDescriptor) == 0 else {
                throw StoreMigrationFailure.invalidIdentity
            }
            try verify()
            try reconcileDeletionTombstones()
            try requireOnlyOwnedNames(validateManifests: false)
            try reconcilePreparedEnvelopeIfPresent()
            try requireOnlyOwnedNames()
            succeeded = true
            retained.removeAll()
        } catch {
            throw error
        }
    }

    deinit {
        _ = Darwin.close(migrationDescriptor)
        _ = Darwin.close(operationsDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func loadJournal() throws -> StoreMigrationJournalV1? {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames(validateManifests: false)
        try reconcilePreparedEnvelopeIfPresent()
        try requireOnlyOwnedNames()
        try reconcileJournalTemporaryIfPresent()
        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        ) else {
            try verify()
            return nil
        }
        let captured = try readRegularFile(name: Self.journalName)
        let value = try StoreMigrationJournalV1.decodeCanonical(
            from: captured.data
        )
        try verifyNamedIdentity(
            name: Self.journalName,
            expected: captured.identity
        )
        try protectFile(
            .journal,
            name: Self.journalName,
            expected: captured.identity
        )
        return value
    }

    func aggregateControl() throws -> StoreAggregateMigrationControlV1 {
        try verify()
        guard let control = try StoreAggregateMigrationControlV1(applicationSupportURL: applicationSupportURL) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return control
    }

    /// Durably commits the coupled prepared state. The envelope is the commit
    /// authority: recovery materializes the immutable source manifest first,
    /// then the hash-bound prepared journal, and removes the envelope last.
    func createPreparedMigration(
        journal: StoreMigrationJournalV1,
        sourceManifest: StoreGenerationManifestV1
    ) throws {
        // Validate the complete coupling before any recovery or filesystem
        // mutation. Presence flags are recorded only after current state is
        // pinned and proven below.
        _ = try PreparedMigrationEnvelopeV1(
            journal: journal,
            sourceManifest: sourceManifest,
            journalWasPresent: false,
            sourceManifestWasPresent: false
        )

        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames(validateManifests: false)
        try reconcilePreparedEnvelopeIfPresent()
        try reconcileJournalTemporaryIfPresent()
        try requireOnlyOwnedNames()

        let journalData = try journal.canonicalData()
        let manifestName = try Self.manifestName(
            for: sourceManifest.generationID
        )
        let manifestData = try sourceManifest.canonicalData()
        let journalExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        )
        let manifestExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: manifestName
        )

        if journalExists {
            let current = try readRegularFile(name: Self.journalName)
            guard current.data == journalData else {
                throw StoreMigrationFailure.invalidPhaseTransition
            }
        }
        if manifestExists {
            let current = try readRegularFile(name: manifestName)
            guard current.data == manifestData else {
                throw StoreMigrationFailure.digestMismatch
            }
        }
        if journalExists && manifestExists {
            return
        }

        let envelope = try PreparedMigrationEnvelopeV1(
            journal: journal,
            sourceManifest: sourceManifest,
            journalWasPresent: journalExists,
            sourceManifestWasPresent: manifestExists
        )
        let envelopeData = try envelope.canonicalData()
        guard envelopeData.count <= Self.maximumOwnedArtifactByteCount else {
            throw StoreMigrationFailure.invalidContract
        }

        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeName
        ), try !Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeTemporaryName
        ) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }
        try createRegularFile(
            name: Self.preparedEnvelopeTemporaryName,
            data: envelopeData,
            kind: .journalTemporary
        )
        let temporary = try readRegularFile(
            name: Self.preparedEnvelopeTemporaryName
        )
        guard temporary.data == envelopeData else {
            throw StoreMigrationFailure.digestMismatch
        }
        try verifyNamedIdentity(
            name: Self.preparedEnvelopeTemporaryName,
            expected: temporary.identity
        )
        guard Darwin.renameatx_np(
            migrationDescriptor,
            Self.preparedEnvelopeTemporaryName,
            migrationDescriptor,
            Self.preparedEnvelopeName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let committed = try readRegularFile(
            name: Self.preparedEnvelopeName
        )
        guard committed.data == envelopeData,
              committed.identity == temporary.identity else {
            throw StoreMigrationFailure.maintenanceRequired(
                .forwardFixRequired
            )
        }
        try protectFile(
            .journal,
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )
        try reconcilePreparedEnvelopeIfPresent()

        let persistedJournal = try readRegularFile(name: Self.journalName)
        let persistedManifest = try readRegularFile(name: manifestName)
        guard persistedJournal.data == journalData,
              persistedManifest.data == manifestData,
              try !Self.itemExists(
                parent: migrationDescriptor,
                name: Self.preparedEnvelopeName
              ) else {
            throw StoreMigrationFailure.maintenanceRequired(
                .forwardFixRequired
            )
        }
    }

    func replaceJournal(
        expected: StoreMigrationJournalV1,
        with replacement: StoreMigrationJournalV1
    ) throws {
        try replacement.validateReplacement(of: expected)
        guard let current = try loadJournal(), current == expected else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        let expectedData = try expected.canonicalData()
        let replacementData = try replacement.canonicalData()
        let expectedRead = try readRegularFile(name: Self.journalName)
        guard expectedRead.data == expectedData else {
            throw StoreMigrationFailure.digestMismatch
        }

        try createRegularFile(
            name: Self.journalTemporaryName,
            data: replacementData,
            kind: .journalTemporary
        )
        let replacementRead = try readRegularFile(
            name: Self.journalTemporaryName
        )
        try verifyNamedIdentity(
            name: Self.journalName,
            expected: expectedRead.identity
        )
        try verifyNamedIdentity(
            name: Self.journalTemporaryName,
            expected: replacementRead.identity
        )
        guard Darwin.renameatx_np(
            migrationDescriptor,
            Self.journalTemporaryName,
            migrationDescriptor,
            Self.journalName,
            UInt32(RENAME_SWAP)
        ) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }

        // From this point forward the replacement may be published. Never
        // roll it back: every failure is an ambiguous forward-recovery state.
        do {
            guard Darwin.fsync(migrationDescriptor) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            let published = try readRegularFile(name: Self.journalName)
            let displaced = try readRegularFile(name: Self.journalTemporaryName)
            guard published.data == replacementData,
                  published.identity == replacementRead.identity,
                  displaced.data == expectedData,
                  displaced.identity == expectedRead.identity else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            try unlinkExact(
                name: Self.journalTemporaryName,
                expected: displaced.identity
            )
            try protectFile(
                .journal,
                name: Self.journalName,
                expected: published.identity
            )
            try verify()
        } catch {
            throw Self.forwardFailure(for: error)
        }
    }

    func removeJournal(expected: StoreMigrationJournalV1) throws {
        guard let current = try loadJournal(), current == expected else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        let captured = try readRegularFile(name: Self.journalName)
        guard captured.data == (try expected.canonicalData()) else {
            throw StoreMigrationFailure.digestMismatch
        }
        do {
            try unlinkExact(name: Self.journalName, expected: captured.identity)
        } catch {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        try verify()
        try requireOnlyOwnedNames()
    }

    @discardableResult
    func writeManifest(_ manifest: StoreGenerationManifestV1) throws -> String {
        try manifest.validate()
        let name = try Self.manifestName(for: manifest.generationID)
        let data = try manifest.canonicalData()
        let digest = StoreMigrationCanonicalJSONV1.sha256(data)
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        if try Self.itemExists(parent: migrationDescriptor, name: name) {
            let existing = try readRegularFile(name: name)
            guard existing.data == data else {
                throw StoreMigrationFailure.digestMismatch
            }
            try protectFile(.journal, name: name, expected: existing.identity)
            return digest
        }
        try createRegularFile(name: name, data: data, kind: .journal)
        let persisted = try readRegularFile(name: name)
        guard persisted.data == data else {
            throw StoreMigrationFailure.digestMismatch
        }
        try protectFile(.journal, name: name, expected: persisted.identity)
        return digest
    }

    func loadManifest(
        targetGenerationID: UUID,
        expectedDigest: String
    ) throws -> StoreGenerationManifestV1 {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(expectedDigest) else {
            throw StoreMigrationFailure.invalidDigest
        }
        let name = try Self.manifestName(for: targetGenerationID)
        let captured = try readRegularFile(name: name)
        guard StoreMigrationCanonicalJSONV1.sha256(captured.data)
                == expectedDigest else {
            throw StoreMigrationFailure.digestMismatch
        }
        let manifest = try StoreGenerationManifestV1.decodeCanonical(
            from: captured.data
        )
        guard manifest.generationID == targetGenerationID else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try protectFile(.journal, name: name, expected: captured.identity)
        return manifest
    }

    func loadManifestIfPresent(
        targetGenerationID: UUID
    ) throws -> (manifest: StoreGenerationManifestV1, digest: String)? {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        let name = try Self.manifestName(for: targetGenerationID)
        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: name
        ) else {
            return nil
        }
        let captured = try readRegularFile(name: name)
        let manifest = try StoreGenerationManifestV1.decodeCanonical(
            from: captured.data
        )
        guard manifest.generationID == targetGenerationID else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try protectFile(.journal, name: name, expected: captured.identity)
        return (
            manifest,
            StoreMigrationCanonicalJSONV1.sha256(captured.data)
        )
    }

    func removeManifest(
        targetGenerationID: UUID,
        expectedDigest: String
    ) throws {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        let name = try Self.manifestName(for: targetGenerationID)
        let captured = try readRegularFile(name: name)
        guard StoreMigrationCanonicalJSONV1.sha256(captured.data)
                == expectedDigest else {
            throw StoreMigrationFailure.digestMismatch
        }
        _ = try StoreGenerationManifestV1.decodeCanonical(from: captured.data)
        try unlinkExact(name: name, expected: captured.identity)
        try verify()
    }

    private func reconcilePreparedEnvelopeIfPresent() throws {
        if try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeTemporaryName
        ) {
            let temporary = try readRegularFile(
                name: Self.preparedEnvelopeTemporaryName
            )
            try protectFile(
                .journalTemporary,
                name: Self.preparedEnvelopeTemporaryName,
                expected: temporary.identity
            )

            // A temporary-only envelope never crossed the commit rename and
            // therefore has no authority to publish either coupled artifact.
            try unlinkExact(
                name: Self.preparedEnvelopeTemporaryName,
                expected: temporary.identity
            )
        }

        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeName
        ) else { return }

        let committed = try readRegularFile(
            name: Self.preparedEnvelopeName
        )
        let envelope = try PreparedMigrationEnvelopeV1.decodeCanonical(
            from: committed.data
        )
        try protectFile(
            .journal,
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )

        // The immutable source manifest is made durable before the journal so
        // every visible prepared journal has its exact hash-bound dependency.
        try materializePreparedSourceManifest(envelope)
        let persistedManifest = try loadManifest(
            targetGenerationID: envelope.sourceManifest.generationID,
            expectedDigest: envelope.sourceManifestDigest
        )
        guard persistedManifest == envelope.sourceManifest else {
            throw StoreMigrationFailure.digestMismatch
        }

        try materializePreparedJournal(
            envelope.journal,
            wasPresent: envelope.journalWasPresent
        )
        let persistedJournal = try readRegularFile(name: Self.journalName)
        guard persistedJournal.data == (try envelope.journal.canonicalData()),
              StoreMigrationCanonicalJSONV1.sha256(persistedJournal.data)
                == envelope.journalDigest else {
            throw StoreMigrationFailure.digestMismatch
        }

        // The final envelope remains recoverable authority until both payloads
        // have been independently reread and proven exact.
        try verifyNamedIdentity(
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )
        try unlinkExact(
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )
        try verify()
    }

    private func materializePreparedSourceManifest(
        _ envelope: PreparedMigrationEnvelopeV1
    ) throws {
        let manifest = envelope.sourceManifest
        let name = try Self.manifestName(for: manifest.generationID)
        let data = try manifest.canonicalData()
        let exists = try Self.itemExists(
            parent: migrationDescriptor,
            name: name
        )
        if exists {
            let current = try readRegularFile(name: name)
            if current.data == data {
                try protectFile(
                    .journal,
                    name: name,
                    expected: current.identity
                )
                return
            }
            // A manifest at its immutable final name is never replaced. The
            // coupled path publishes through a temporary and RENAME_EXCL, so a
            // mismatch is conflicting accepted state, not crash residue.
            throw StoreMigrationFailure.digestMismatch
        } else if envelope.sourceManifestWasPresent {
            throw StoreMigrationFailure.maintenanceRequired(
                .sourceUnavailable
            )
        }

        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeTemporaryName
        ) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }
        try createRegularFile(
            name: Self.preparedEnvelopeTemporaryName,
            data: data,
            kind: .journalTemporary
        )
        let temporary = try readRegularFile(
            name: Self.preparedEnvelopeTemporaryName
        )
        guard temporary.data == data else {
            throw StoreMigrationFailure.digestMismatch
        }
        try verifyNamedIdentity(
            name: Self.preparedEnvelopeTemporaryName,
            expected: temporary.identity
        )
        if Darwin.renameatx_np(
            migrationDescriptor,
            Self.preparedEnvelopeTemporaryName,
            migrationDescriptor,
            name,
            UInt32(RENAME_EXCL)
        ) != 0 {
            let renameError = errno
            if renameError == EEXIST,
               let raced = try? readRegularFile(name: name),
               raced.data == data {
                try unlinkExact(
                    name: Self.preparedEnvelopeTemporaryName,
                    expected: temporary.identity
                )
                return
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(renameError))
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let persisted = try readRegularFile(name: name)
        guard persisted.data == data,
              persisted.identity == temporary.identity,
              StoreMigrationCanonicalJSONV1.sha256(persisted.data)
                == envelope.sourceManifestDigest else {
            throw StoreMigrationFailure.digestMismatch
        }
        try protectFile(.journal, name: name, expected: persisted.identity)
    }

    private func materializePreparedJournal(
        _ journal: StoreMigrationJournalV1,
        wasPresent: Bool
    ) throws {
        try journal.validate()
        guard journal.phase == .prepared else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        let data = try journal.canonicalData()
        let canonicalExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        )
        let temporaryExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalTemporaryName
        )

        if canonicalExists {
            let current = try readRegularFile(name: Self.journalName)
            guard current.data == data else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .invalidJournal
                )
            }
            if temporaryExists {
                let temporary = try readRegularFile(
                    name: Self.journalTemporaryName
                )
                guard temporary.data == data else {
                    throw StoreMigrationFailure.maintenanceRequired(
                        .invalidJournal
                    )
                }
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: temporary.identity
                )
            }
            try protectFile(
                .journal,
                name: Self.journalName,
                expected: current.identity
            )
            return
        }
        guard !wasPresent else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }

        var temporary: (data: Data, identity: Identity)
        if temporaryExists {
            temporary = try readRegularFile(
                name: Self.journalTemporaryName
            )
            if temporary.data != data {
                // No journal existed when the envelope committed, and startup
                // reconciled any older temporary before that commit. A partial
                // temporary here is therefore envelope-owned crash residue.
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: temporary.identity
                )
                try createRegularFile(
                    name: Self.journalTemporaryName,
                    data: data,
                    kind: .journalTemporary
                )
                temporary = try readRegularFile(
                    name: Self.journalTemporaryName
                )
            }
        } else {
            try createRegularFile(
                name: Self.journalTemporaryName,
                data: data,
                kind: .journalTemporary
            )
            temporary = try readRegularFile(
                name: Self.journalTemporaryName
            )
        }
        try verifyNamedIdentity(
            name: Self.journalTemporaryName,
            expected: temporary.identity
        )
        guard Darwin.renameatx_np(
            migrationDescriptor,
            Self.journalTemporaryName,
            migrationDescriptor,
            Self.journalName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let persisted = try readRegularFile(name: Self.journalName)
        guard persisted.data == data,
              persisted.identity == temporary.identity else {
            throw StoreMigrationFailure.maintenanceRequired(
                .forwardFixRequired
            )
        }
        try protectFile(
            .journal,
            name: Self.journalName,
            expected: persisted.identity
        )
    }

    private func reconcileJournalTemporaryIfPresent() throws {
        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalTemporaryName
        ) else { return }

        let temporary = try readRegularFile(name: Self.journalTemporaryName)
        let temporaryJournal = try StoreMigrationJournalV1.decodeCanonical(
            from: temporary.data
        )
        try protectFile(
            .journalTemporary,
            name: Self.journalTemporaryName,
            expected: temporary.identity
        )

        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        ) else {
            guard temporaryJournal.phase == .prepared else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .invalidJournal
                )
            }
            try verifyNamedIdentity(
                name: Self.journalTemporaryName,
                expected: temporary.identity
            )
            guard Darwin.renameatx_np(
                migrationDescriptor,
                Self.journalTemporaryName,
                migrationDescriptor,
                Self.journalName,
                UInt32(RENAME_EXCL)
            ) == 0,
                  Darwin.fsync(migrationDescriptor) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            let persisted = try readRegularFile(name: Self.journalName)
            guard persisted.data == temporary.data,
                  persisted.identity == temporary.identity else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            try protectFile(
                .journal,
                name: Self.journalName,
                expected: persisted.identity
            )
            return
        }

        let current = try readRegularFile(name: Self.journalName)
        let currentJournal = try StoreMigrationJournalV1.decodeCanonical(
            from: current.data
        )
        if (try? temporaryJournal.validateReplacement(of: currentJournal)) != nil {
            try verifyNamedIdentity(
                name: Self.journalName,
                expected: current.identity
            )
            try verifyNamedIdentity(
                name: Self.journalTemporaryName,
                expected: temporary.identity
            )
            guard Darwin.renameatx_np(
                migrationDescriptor,
                Self.journalTemporaryName,
                migrationDescriptor,
                Self.journalName,
                UInt32(RENAME_SWAP)
            ) == 0,
                  Darwin.fsync(migrationDescriptor) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            do {
                let displaced = try readRegularFile(
                    name: Self.journalTemporaryName
                )
                guard displaced.data == current.data,
                      displaced.identity == current.identity else {
                    throw StoreMigrationFailure.maintenanceRequired(
                        .forwardFixRequired
                    )
                }
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: displaced.identity
                )
            } catch {
                throw Self.forwardFailure(for: error)
            }
        } else if (try? currentJournal.validateReplacement(
            of: temporaryJournal
        )) != nil {
            // The swap succeeded and only old-journal cleanup was interrupted.
            do {
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: temporary.identity
                )
            } catch {
                throw Self.forwardFailure(for: error)
            }
        } else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }
    }

    private func createRegularFile(
        name: String,
        data: Data,
        kind: OwnedFileKindV1
    ) throws {
        try Self.requireSafeName(name)
        guard data.count <= Self.maximumOwnedArtifactByteCount else {
            throw StoreMigrationFailure.invalidContract
        }
        try verify()
        guard try !Self.itemExists(parent: migrationDescriptor, name: name) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var cleanupIdentity: Identity?
        var shouldRemove = true
        defer {
            _ = Darwin.close(descriptor)
            if shouldRemove, let cleanupIdentity {
                try? unlinkExact(name: name, expected: cleanupIdentity)
            }
        }
        let identity = try Self.regularFileIdentity(descriptor)
        cleanupIdentity = identity
        try protectFile(kind, name: name, expected: identity)
        try Self.writeAll(data, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try verifyNamedIdentity(name: name, expected: identity)
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let reread = try readRegularFile(name: name)
        guard reread.identity == identity, reread.data == data else {
            throw StoreMigrationFailure.digestMismatch
        }
        shouldRemove = false
    }

    private func readRegularFile(
        name: String
    ) throws -> (data: Data, identity: Identity) {
        try Self.requireSafeName(name)
        try verify()
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        let identity = try Self.regularFileIdentity(descriptor)
        try protectFile(
            Self.ownedFileKind(for: name),
            name: name,
            expected: identity
        )
        let before = try Self.regularFileSnapshot(descriptor)
        let data = try Self.readAll(from: descriptor)
        guard try Self.regularFileSnapshot(descriptor) == before else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try verifyNamedIdentity(name: name, expected: before.identity)
        return (data, before.identity)
    }

    private func unlinkExact(name: String, expected: Identity) throws {
        try verifyNamedIdentity(name: name, expected: expected)
        let tombstone = try Self.deletionTombstoneName(for: name)
        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: tombstone
        ), Darwin.renameatx_np(
            migrationDescriptor,
            name,
            migrationDescriptor,
            tombstone,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        let moved = try readRegularFile(name: tombstone)
        guard moved.identity == expected else {
            if try !Self.itemExists(parent: migrationDescriptor, name: name) {
                _ = Darwin.renameatx_np(
                    migrationDescriptor,
                    tombstone,
                    migrationDescriptor,
                    name,
                    UInt32(RENAME_EXCL)
                )
                _ = Darwin.fsync(migrationDescriptor)
            }
            throw StoreMigrationFailure.invalidIdentity
        }
        try unlinkQuarantined(name: tombstone, expected: expected)
        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: name
        ) else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func unlinkQuarantined(name: String, expected: Identity) throws {
        try verifyNamedIdentity(name: name, expected: expected)
        guard Darwin.unlinkat(migrationDescriptor, name, 0) == 0,
              Darwin.fsync(migrationDescriptor) == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
    }

    private func reconcileDeletionTombstones() throws {
        let names = try Self.names(in: migrationDescriptor)
        for tombstone in names where tombstone.hasSuffix(Self.deletionSuffix) {
            let original = String(tombstone.dropLast(Self.deletionSuffix.count))
            guard Self.isOwnedBaseName(original),
                  try !Self.itemExists(
                    parent: migrationDescriptor,
                    name: original
                  ) else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
            }
            let captured = try readRegularFile(name: tombstone)
            try unlinkQuarantined(
                name: tombstone,
                expected: captured.identity
            )
        }
    }

    private func protectDirectory(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        try ProtectedFilePolicyV1.applyAndVerify(
            kind,
            at: url,
            authorityCheck: { [self] in try verify() }
        )
    }

    private func protectFile(
        _ kind: OwnedFileKindV1,
        name: String,
        expected: Identity
    ) throws {
        let url = migrationURL.appendingPathComponent(
            name,
            isDirectory: false
        )
        try ProtectedFilePolicyV1.applyAndVerify(
            kind,
            at: url,
            authorityCheck: { [self] in
                try verify()
                try verifyNamedIdentity(name: name, expected: expected)
            }
        )
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.regularFileIdentity(descriptor) == expected,
              Darwin.fsync(descriptor) == 0,
              Darwin.fsync(migrationDescriptor) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func verify() throws {
        try Self.requireDirectory(
            applicationSupportDescriptor,
            identity: applicationSupportIdentity
        )
        try Self.requireDirectory(
            operationsDescriptor,
            identity: operationsIdentity
        )
        try Self.requireDirectory(
            migrationDescriptor,
            identity: migrationIdentity
        )
        let currentRoot = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard currentRoot >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(currentRoot) }
        guard try Self.directoryIdentity(currentRoot)
                == applicationSupportIdentity else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try verifyChildDirectory(
            parent: applicationSupportDescriptor,
            name: Self.operationsName,
            expected: operationsIdentity
        )
        try verifyChildDirectory(
            parent: operationsDescriptor,
            name: Self.migrationName,
            expected: migrationIdentity
        )
    }

    private func verifyChildDirectory(
        parent: Int32,
        name: String,
        expected: Identity
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.directoryIdentity(descriptor) == expected else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func verifyNamedIdentity(
        name: String,
        expected: Identity
    ) throws {
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.regularFileIdentity(descriptor) == expected else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func requireOnlyOwnedNames(
        validateManifests: Bool = true
    ) throws {
        let names = try Self.names(in: migrationDescriptor)
        guard names.allSatisfy({ name in
            name == Self.journalName
                || name == Self.journalTemporaryName
                || name == Self.preparedEnvelopeName
                || name == Self.preparedEnvelopeTemporaryName
                || name == StoreAggregateMigrationControlV1.name
                || name == StoreAggregateMigrationControlV1.temporaryName
                || StoreAggregateMigrationControlV1.allocationID(for: name) != nil
                || Self.isManifestName(name)
        }) else {
            throw StoreMigrationFailure.invalidPath
        }
        // Unbound allocation residues are never opened, protected or adopted.
        // Check only exact spelling/type, preserving all their unknown contents.
        for name in names where StoreAggregateMigrationControlV1.allocationID(for: name) != nil {
            var info = stat()
            guard Darwin.fstatat(migrationDescriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  info.st_mode & S_IFMT == S_IFDIR else { throw StoreMigrationFailure.invalidPath }
        }
        guard validateManifests else { return }
        for name in names where Self.isManifestName(name) {
            let captured = try readRegularFile(name: name)
            let manifest = try StoreGenerationManifestV1.decodeCanonical(
                from: captured.data
            )
            guard try Self.manifestName(for: manifest.generationID) == name else {
                throw StoreMigrationFailure.invalidIdentity
            }
        }
    }

    private static func manifestName(for id: UUID) throws -> String {
        let canonical = id.uuidString.lowercased()
        guard UUID(uuidString: canonical)?.uuidString.lowercased()
                == canonical else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return "manifest-\(canonical).json"
    }

    private static func isManifestName(_ name: String) -> Bool {
        let prefix = "manifest-"
        let suffix = ".json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
            return false
        }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        let value = String(name[start..<end])
        return UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    private static func isOwnedBaseName(_ name: String) -> Bool {
        name == journalName
            || name == journalTemporaryName
            || name == preparedEnvelopeName
            || name == preparedEnvelopeTemporaryName
            || isManifestName(name)
    }

    private static func deletionTombstoneName(for name: String) throws -> String {
        guard isOwnedBaseName(name) else {
            throw StoreMigrationFailure.invalidPath
        }
        return name + deletionSuffix
    }

    private static func ownedFileKind(for name: String) -> OwnedFileKindV1 {
        let baseName = name.hasSuffix(deletionSuffix)
            ? String(name.dropLast(deletionSuffix.count))
            : name
        return baseName == journalTemporaryName
            || baseName == preparedEnvelopeTemporaryName
            ? .journalTemporary
            : .journal
    }

    private static func forwardFailure(for error: Error) -> StoreMigrationFailure {
        if let failure = error as? StoreMigrationFailure {
            switch failure {
            case .maintenanceRequired:
                return failure
            default:
                break
            }
        }
        if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
            return .maintenanceRequired(.protectedDataUnavailable)
        }
        var current = error as NSError
        for _ in 0..<8 {
            if current.domain == NSPOSIXErrorDomain,
               current.code == ENOSPC {
                return .maintenanceRequired(.insufficientStorage)
            }
            if current.domain == NSCocoaErrorDomain,
               current.code == NSFileWriteOutOfSpaceError {
                return .maintenanceRequired(.insufficientStorage)
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey]
                    as? NSError,
                  underlying !== current else {
                break
            }
            current = underlying
        }
        return .maintenanceRequired(.forwardFixRequired)
    }

    private static func requireSafeName(_ name: String) throws {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\") else {
            throw StoreMigrationFailure.invalidPath
        }
    }

    private static func openOrCreateDirectory(
        parent: Int32,
        name: String
    ) throws -> Int32 {
        try requireSafeName(name)
        var descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor >= 0 { return descriptor }
        guard errno == ENOENT,
              Darwin.mkdirat(parent, name, mode_t(0o700)) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return descriptor
    }

    private static func requireDirectory(
        _ descriptor: Int32,
        identity: Identity
    ) throws {
        guard try directoryIdentity(descriptor) == identity else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFDIR,
              information.st_nlink >= 1 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return Identity(information)
    }

    private static func regularFileIdentity(_ descriptor: Int32) throws -> Identity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return Identity(information)
    }

    private static func regularFileSnapshot(_ descriptor: Int32) throws -> FileSnapshot {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,
              information.st_size <= off_t(maximumOwnedArtifactByteCount) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return FileSnapshot(information)
    }

    private static func itemExists(parent: Int32, name: String) throws -> Bool {
        try requireSafeName(name)
        var information = stat()
        guard Darwin.fstatat(
            parent,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            if errno == ENOENT { return false }
            throw StoreMigrationFailure.invalidIdentity
        }
        guard (information.st_mode & S_IFMT) != S_IFLNK else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return true
    }

    private static func readAll(from descriptor: Int32) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { return result }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw StoreMigrationFailure.invalidIdentity
            }
            guard result.count <= maximumOwnedArtifactByteCount - count else {
                throw StoreMigrationFailure.invalidContract
            }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard count > 0 else {
                    if count < 0 && errno == EINTR { continue }
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(errno)
                    )
                }
                offset += count
            }
        }
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
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.closedir(directory) }
        var values: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: capacity
                ) { String(cString: $0) }
            }
            if name != "." && name != ".." { values.append(name) }
            errno = 0
        }
        guard errno == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return values.sorted()
    }
}

/// Durable, descriptor-pinned ownership for generation readers and writers.
/// The registry is operational state, is excluded from backup, and never uses
/// wall-clock expiry as liveness authority. An owner is abandoned only when
/// its exact owner-lock file can be locked exclusively.
final class GenerationLeaseRegistryV1: @unchecked Sendable {
    private struct RegistryStateV1: Codable, Equatable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let leases: [GenerationLeaseTokenV1]

        init(leases: [GenerationLeaseTokenV1]) throws {
            schemaVersion = Self.currentSchemaVersion
            self.leases = leases.sorted {
                Self.canonical($0.leaseID) < Self.canonical($1.leaseID)
            }
            try validate()
        }

        func validate() throws {
            try leases.forEach { try $0.validate() }
            let leaseIDs = leases.map(\.leaseID)
            let owners = Set(leases.map(\.ownerID))
            guard schemaVersion == Self.currentSchemaVersion,
                  leases.count <= GenerationLeaseRegistryV1.maximumActiveLeaseCount,
                  owners.count <= GenerationLeaseRegistryV1.maximumOwnerCount,
                  Set(leaseIDs).count == leaseIDs.count,
                  leases == leases.sorted(by: {
                      Self.canonical($0.leaseID) < Self.canonical($1.leaseID)
                  }) else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
        }

        func canonicalData() throws -> Data {
            try validate()
            return try StoreMigrationCanonicalJSONV1.encode(self)
        }

        static func decodeCanonical(from data: Data) throws -> Self {
            guard data.count <= GenerationLeaseRegistryV1.maximumControlFileBytes else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            return try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
                Self.self,
                from: data,
                validate: { try $0.validate() }
            )
        }

        private static func canonical(_ value: UUID) -> String {
            value.uuidString.lowercased()
        }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
        let type: mode_t

        init(_ information: stat) {
            device = information.st_dev
            inode = information.st_ino
            linkCount = information.st_nlink
            type = information.st_mode & S_IFMT
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            // Directory link counts may change when this or another canonical
            // owner creates a child. Named-object and file hard-link proofs
            // remain independent checks on every use.
            lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.type == rhs.type
                && (lhs.type == S_IFDIR || lhs.linkCount == rhs.linkCount)
        }
    }

    private struct FileSnapshot: Equatable {
        let identity: Identity
        let byteCount: off_t
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let changeSeconds: Int64
        let changeNanoseconds: Int64

        init(_ information: stat) {
            identity = Identity(information)
            byteCount = information.st_size
            modificationSeconds = Int64(information.st_mtimespec.tv_sec)
            modificationNanoseconds = Int64(information.st_mtimespec.tv_nsec)
            changeSeconds = Int64(information.st_ctimespec.tv_sec)
            changeNanoseconds = Int64(information.st_ctimespec.tv_nsec)
        }
    }

    static let maximumActiveLeaseCount = 256
    static let maximumOwnerCount = 64
    static let maximumControlFileBytes = 4 * 1024 * 1024

    private static let operationsName = "FieldEvidenceOperations"
    private static let leaseDirectoryName = "generation-leases"
    private static let ownerDirectoryName = "owners"
    private static let registryName = "registry.json"
    private static let registryTemporaryName = "registry.next.json"
    private static let mutationLockName = "mutation.lock"
    private static let pruneIntentName = "prune-intent.json"
    private static let pruneIntentTemporaryName = "prune-intent.next.json"
    private static let pruneReceiptName = "last-prune-receipt.json"
    private static let pruneReceiptTemporaryName =
        "last-prune-receipt.next.json"
    private static let processMutationLock = NSRecursiveLock()

    let ownerID: UUID

    private let applicationSupportURL: URL
    private let operationsURL: URL
    private let leaseURL: URL
    private let ownersURL: URL
    private let rootDescriptor: Int32
    private let operationsDescriptor: Int32
    private let leaseDescriptor: Int32
    private let ownersDescriptor: Int32
    private let mutationLockDescriptor: Int32
    private let ownerLockDescriptor: Int32
    private let rootIdentity: Identity
    private let operationsIdentity: Identity
    private let leaseIdentity: Identity
    private let ownersIdentity: Identity
    private let mutationLockIdentity: Identity
    private let ownerLockIdentity: Identity
    private let makeLeaseID: @Sendable () -> UUID
    private let now: @Sendable () -> Date
    private var generationMutationLockDepth = 0

    init(
        applicationSupportURL: URL,
        ownerID: UUID = UUID(),
        makeLeaseID: @escaping @Sendable () -> UUID = UUID.init,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        guard applicationSupportURL.isFileURL,
              ownerID != GenerationEpochV1.zeroUUID else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        let root = applicationSupportURL.standardizedFileURL
        let rootDescriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw Self.mappedFailure()
        }
        var retained = [rootDescriptor]
        var ownerLockWasAcquired = false
        var succeeded = false
        defer {
            if !succeeded {
                if ownerLockWasAcquired, let descriptor = retained.last {
                    _ = flock(descriptor, LOCK_UN)
                }
                retained.reversed().forEach { _ = Darwin.close($0) }
            }
        }

        let rootIdentity = try Self.directoryIdentity(rootDescriptor)
        let operationsDescriptor = try Self.openOrCreateDirectory(
            parent: rootDescriptor,
            name: Self.operationsName
        )
        retained.append(operationsDescriptor)
        let operationsIdentity = try Self.directoryIdentity(
            operationsDescriptor
        )
        let leaseDescriptor = try Self.openOrCreateDirectory(
            parent: operationsDescriptor,
            name: Self.leaseDirectoryName
        )
        retained.append(leaseDescriptor)
        let leaseIdentity = try Self.directoryIdentity(leaseDescriptor)
        let ownersDescriptor = try Self.openOrCreateDirectory(
            parent: leaseDescriptor,
            name: Self.ownerDirectoryName
        )
        retained.append(ownersDescriptor)
        let ownersIdentity = try Self.directoryIdentity(ownersDescriptor)
        let mutation = try Self.openOrCreateRegularFile(
            parent: leaseDescriptor,
            name: Self.mutationLockName
        )
        retained.append(mutation.descriptor)
        let ownerName = Self.ownerLockName(ownerID)
        let owner = try Self.openOrCreateRegularFile(
            parent: ownersDescriptor,
            name: ownerName
        )
        retained.append(owner.descriptor)
        guard flock(owner.descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw GenerationLeaseRegistryFailureV1.duplicateLease
        }
        ownerLockWasAcquired = true

        self.ownerID = ownerID
        self.applicationSupportURL = root
        self.operationsURL = root.appendingPathComponent(
            Self.operationsName,
            isDirectory: true
        )
        self.leaseURL = self.operationsURL.appendingPathComponent(
            Self.leaseDirectoryName,
            isDirectory: true
        )
        self.ownersURL = self.leaseURL.appendingPathComponent(
            Self.ownerDirectoryName,
            isDirectory: true
        )
        self.rootDescriptor = rootDescriptor
        self.operationsDescriptor = operationsDescriptor
        self.leaseDescriptor = leaseDescriptor
        self.ownersDescriptor = ownersDescriptor
        self.mutationLockDescriptor = mutation.descriptor
        self.ownerLockDescriptor = owner.descriptor
        self.rootIdentity = rootIdentity
        self.operationsIdentity = operationsIdentity
        self.leaseIdentity = leaseIdentity
        self.ownersIdentity = ownersIdentity
        self.mutationLockIdentity = mutation.identity
        self.ownerLockIdentity = owner.identity
        self.makeLeaseID = makeLeaseID
        self.now = now

        try protectDirectory(.generationLeaseDirectory, at: self.operationsURL)
        try protectDirectory(.generationLeaseDirectory, at: self.leaseURL)
        try protectDirectory(.generationLeaseDirectory, at: self.ownersURL)
        try protectFile(
            .generationLeaseControl,
            parent: leaseDescriptor,
            directoryURL: self.leaseURL,
            name: Self.mutationLockName,
            expected: mutation.identity
        )
        try protectFile(
            .generationLeaseOwnerLock,
            parent: ownersDescriptor,
            directoryURL: self.ownersURL,
            name: ownerName,
            expected: owner.identity
        )
        try withExclusiveGenerationMutationLock {
            try reconcileConservativeTemporariesLocked()
            try ensureRegistryLocked()
            _ = try loadStateLocked()
        }
        succeeded = true
        retained.removeAll()
    }

    deinit {
        try? removeOwnerGuardIfUnused()
        _ = flock(ownerLockDescriptor, LOCK_UN)
        _ = Darwin.close(ownerLockDescriptor)
        _ = Darwin.close(mutationLockDescriptor)
        _ = Darwin.close(ownersDescriptor)
        _ = Darwin.close(leaseDescriptor)
        _ = Darwin.close(operationsDescriptor)
        _ = Darwin.close(rootDescriptor)
    }

    func acquire(
        epoch: GenerationEpochV1,
        role: GenerationLeaseRoleV1
    ) throws -> GenerationLeaseTokenV1 {
        try epoch.validate()
        return try withExclusiveGenerationMutationLock {
            try requireNoMigrationReservationLocked()
            var state = try loadStateLocked()
            guard state.leases.count < Self.maximumActiveLeaseCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let owners = Set(state.leases.map(\.ownerID))
            guard owners.contains(ownerID)
                    || owners.count < Self.maximumOwnerCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let leaseID = makeLeaseID()
            guard leaseID != GenerationEpochV1.zeroUUID,
                  !state.leases.contains(where: { $0.leaseID == leaseID }) else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            let token = try GenerationLeaseTokenV1(
                leaseID: leaseID,
                ownerID: ownerID,
                epoch: epoch,
                role: role,
                acquiredAt: now()
            )
            var leases = state.leases
            leases.append(token)
            state = try RegistryStateV1(leases: leases)
            try replaceStateLocked(with: state)
            try validateActiveLocked(token, requiredRole: role)
            return token
        }
    }

    func acquireHandle(
        epoch: GenerationEpochV1,
        role: GenerationLeaseRoleV1
    ) throws -> GenerationLeaseHandleV1 {
        try GenerationLeaseHandleV1(
            registry: self,
            token: acquire(epoch: epoch, role: role)
        )
    }

    func release(_ token: GenerationLeaseTokenV1) throws {
        try token.validate()
        try withExclusiveGenerationMutationLock {
            let state = try loadStateLocked()
            guard token.ownerID == ownerID else {
                throw GenerationLeaseRegistryFailureV1.leaseNotActive
            }
            let matches = state.leases.filter {
                $0.leaseID == token.leaseID
            }
            if matches.isEmpty {
                // Idempotent adoption after registry rename succeeded but its
                // directory fsync reported failure.
                guard Darwin.fsync(leaseDescriptor) == 0 else {
                    throw Self.mappedFailure()
                }
                return
            }
            guard matches == [token] else {
                throw GenerationLeaseRegistryFailureV1.leaseNotActive
            }
            let replacement = try RegistryStateV1(
                leases: state.leases.filter { $0.leaseID != token.leaseID }
            )
            try replaceStateLocked(with: replacement)
        }
    }

    func validateActive(
        _ token: GenerationLeaseTokenV1,
        requiredRole: GenerationLeaseRoleV1
    ) throws {
        try withExclusiveGenerationMutationLock {
            try validateActiveLocked(token, requiredRole: requiredRole)
        }
    }

    func activeEpochs() throws -> Set<GenerationEpochV1> {
        try withExclusiveGenerationMutationLock {
            let state = try loadStateLocked()
            return Set(state.leases.map(\.epoch))
        }
    }

    private func migrationReservationLocked() throws -> StoreAggregateMigrationJournalV1? {
        guard let control = try StoreAggregateMigrationControlV1(applicationSupportURL: applicationSupportURL),
              let journal = try control.load(), journal.reservationIsActive else { return nil }
        return journal
    }

    fileprivate func requireNoMigrationReservationLocked() throws {
        guard try migrationReservationLocked() == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
    }

    func requireNoMigrationReservation() throws {
        try withExclusiveGenerationMutationLock { try requireNoMigrationReservationLocked() }
    }

    func withNoMigrationReservation<T>(_ operation: () throws -> T) throws -> T {
        try withExclusiveGenerationMutationLock {
            try requireNoMigrationReservationLocked()
            return try operation()
        }
    }

    /// Only this exact operation owner may act inside its durable reservation.
    /// This does not grant an ordinary lease or a canonical writer capability.
    func withMigrationReservation<T>(expected: StoreAggregateMigrationJournalV1,
                                      _ operation: () throws -> T) throws -> T {
        try withExclusiveGenerationMutationLock {
            guard expected.ownerID == ownerID, expected.reservationIsActive,
                  try migrationReservationLocked() == expected else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            guard let control = try StoreAggregateMigrationControlV1(applicationSupportURL: applicationSupportURL) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try control.requireNoConflictingIntentAuthority()
            return try operation()
        }
    }

    /// Retains the exact abandoned owner's guard through CAS transfer. A
    /// missing file or process-ID difference is never proof of abandonment.
    func withProvenAbandonedMigrationOwner<T>(ownerID previousOwner: UUID,
                                               _ replaceReservation: () throws -> T) throws -> T {
        try withExclusiveGenerationMutationLock {
            guard previousOwner != ownerID,
                  let expected = try migrationReservationLocked(), expected.ownerID == previousOwner else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let name = Self.ownerLockName(previousOwner)
            let fd = Darwin.openat(ownersDescriptor, name, O_RDWR | O_NONBLOCK | O_NOFOLLOW)
            guard fd >= 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            defer { _ = Darwin.close(fd) }
            let identity = try Self.regularFileIdentity(fd)
            try requireNamedIdentity(parent: ownersDescriptor, name: name, expected: identity)
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            defer { _ = flock(fd, LOCK_UN) }
            try requireNamedIdentity(parent: ownersDescriptor, name: name, expected: identity)
            let result = try replaceReservation()
            guard let replacement = try migrationReservationLocked(), replacement.ownerID == ownerID else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try replacement.validateReplacement(of: expected)
            try requireNamedIdentity(parent: ownersDescriptor, name: name, expected: identity)
            let state = try loadStateLocked()
            if !state.leases.contains(where: { $0.ownerID == previousOwner }) {
                guard Darwin.unlinkat(ownersDescriptor, name, 0) == 0, Darwin.fsync(ownersDescriptor) == 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            return result
        }
    }

    /// Removes only leases whose exact owner guard is provably unlocked. A
    /// missing, malformed, or unprobeable owner guard is uncertain and retains
    /// all associated lease records.
    @discardableResult
    func reconcileAbandonedOwners() throws -> Int {
        try withExclusiveGenerationMutationLock {
            let state = try loadStateLocked()
            let reservedOwner = try migrationReservationLocked()?.ownerID
            let owners = Set(state.leases.map(\.ownerID)).subtracting(
                Set([ownerID])
            )
            var abandoned = Set<UUID>()
            var retainedDescriptors: [(UUID, Int32, Identity)] = []
            defer {
                for (_, descriptor, _) in retainedDescriptors {
                    _ = flock(descriptor, LOCK_UN)
                    _ = Darwin.close(descriptor)
                }
            }
            for candidate in owners.sorted(by: Self.idOrder) {
                let name = Self.ownerLockName(candidate)
                let descriptor = Darwin.openat(
                    ownersDescriptor,
                    name,
                    O_RDWR | O_NOFOLLOW
                )
                guard descriptor >= 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                let identity: Identity
                do {
                    identity = try Self.regularFileIdentity(descriptor)
                } catch {
                    _ = Darwin.close(descriptor)
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                    abandoned.insert(candidate)
                    retainedDescriptors.append((candidate, descriptor, identity))
                } else {
                    let failure = errno
                    _ = Darwin.close(descriptor)
                    guard failure == EWOULDBLOCK || failure == EAGAIN else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                }
            }
            guard !abandoned.isEmpty else {
                guard Darwin.fsync(leaseDescriptor) == 0,
                      Darwin.fsync(ownersDescriptor) == 0 else {
                    throw Self.mappedFailure()
                }
                return 0
            }
            let replacement = try RegistryStateV1(
                leases: state.leases.filter { !abandoned.contains($0.ownerID) }
            )
            try replaceStateLocked(with: replacement)
            for (candidate, descriptor, identity) in retainedDescriptors {
                // The aggregate can reference an owner with no ordinary lease.
                // Its guard survives until exact guarded reservation takeover.
                if candidate == reservedOwner { continue }
                try requireNamedIdentity(
                    parent: ownersDescriptor,
                    name: Self.ownerLockName(candidate),
                    expected: identity
                )
                guard Darwin.unlinkat(
                    ownersDescriptor,
                    Self.ownerLockName(candidate),
                    0
                ) == 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                _ = descriptor
            }
            guard Darwin.fsync(ownersDescriptor) == 0 else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return state.leases.count - replacement.leases.count
        }
    }

    /// Serializes lease acquisition/release, canonical commits, current-pointer
    /// publication, and prune. The closure must be synchronous and must not
    /// suspend while the cross-process lock is held.
    func withExclusiveGenerationMutationLock<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        try withExclusiveGenerationMutationLock(
            verifyAfterOperation: true,
            operation
        )
    }

    /// Commit-only lock path. Root authority is proved before the closure and
    /// StaleWriterFenceV1 proves the exact active writer lease/current epoch
    /// inside this same cross-process critical section. Once the synchronous
    /// closure returns, its durable commit must not be reported as an ordinary
    /// failure by a post-commit path reproof; pointer mutations are serialized
    /// by this lock and the next operation performs the normal prevalidation.
    fileprivate func withExclusiveGenerationCommitLock<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        try withExclusiveGenerationMutationLock(
            verifyAfterOperation: false,
            operation
        )
    }

    private func withExclusiveGenerationMutationLock<Value>(
        verifyAfterOperation: Bool,
        _ operation: () throws -> Value
    ) throws -> Value {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        if generationMutationLockDepth == 0 {
            guard flock(mutationLockDescriptor, LOCK_EX) == 0 else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
        }
        generationMutationLockDepth += 1
        defer {
            generationMutationLockDepth -= 1
            if generationMutationLockDepth == 0 {
                _ = flock(mutationLockDescriptor, LOCK_UN)
            }
        }
        try verify()
        let result = try operation()
        if verifyAfterOperation { try verify() }
        return result
    }

    func loadPruneIntent() throws -> GenerationPruneIntentV1? {
        try withExclusiveGenerationMutationLock {
            try loadControlLocked(
                name: Self.pruneIntentName,
                decode: GenerationPruneIntentV1.decodeCanonical
            )
        }
    }

    func createPruneIntent(_ intent: GenerationPruneIntentV1) throws {
        try intent.validate()
        try withExclusiveGenerationMutationLock {
            guard try !itemExistsLocked(Self.pruneIntentName) else {
                let existing: GenerationPruneIntentV1? = try loadControlLocked(
                    name: Self.pruneIntentName,
                    decode: GenerationPruneIntentV1.decodeCanonical
                )
                guard existing == intent else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
                // This may be a retry after canonical rename succeeded but
                // its parent-directory fsync failed.
                guard Darwin.fsync(leaseDescriptor) == 0 else {
                    throw Self.mappedFailure()
                }
                return
            }
            try publishNewControlLocked(
                name: Self.pruneIntentName,
                temporaryName: Self.pruneIntentTemporaryName,
                data: try intent.canonicalData()
            )
        }
    }

    func replacePruneIntent(
        expected: GenerationPruneIntentV1,
        with replacement: GenerationPruneIntentV1
    ) throws {
        try replacement.validateReplacement(of: expected)
        try withExclusiveGenerationMutationLock {
            let current: GenerationPruneIntentV1? = try loadControlLocked(
                name: Self.pruneIntentName,
                decode: GenerationPruneIntentV1.decodeCanonical
            )
            if current == replacement {
                guard Darwin.fsync(leaseDescriptor) == 0 else {
                    throw Self.mappedFailure()
                }
                return
            }
            guard current == expected else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            try replaceControlLocked(
                name: Self.pruneIntentName,
                temporaryName: Self.pruneIntentTemporaryName,
                data: try replacement.canonicalData()
            )
        }
    }

    /// A prepared intent has not removed bytes or changed the retired pointer.
    /// It may therefore be abandoned when a newly live or uncertain lease
    /// makes the frozen plan ineligible. Later phases are forward-only.
    func discardPreparedPruneIntent(
        expected: GenerationPruneIntentV1
    ) throws {
        guard expected.phase == .prepared else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        try withExclusiveGenerationMutationLock {
            let current: GenerationPruneIntentV1? = try loadControlLocked(
                name: Self.pruneIntentName,
                decode: GenerationPruneIntentV1.decodeCanonical
            )
            if current == nil {
                guard Darwin.fsync(leaseDescriptor) == 0 else {
                    throw Self.mappedFailure()
                }
                return
            }
            guard current == expected else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            try removeControlLocked(
                name: Self.pruneIntentName,
                expectedData: try expected.canonicalData()
            )
        }
    }

    func loadLastPruneReceipt() throws -> GenerationPruneReceiptV1? {
        try withExclusiveGenerationMutationLock {
            try loadControlLocked(
                name: Self.pruneReceiptName,
                decode: GenerationPruneReceiptV1.decodeCanonical
            )
        }
    }

    /// Publishes a durable receipt for a no-mutation prune decision. Actual
    /// byte removal remains coupled to the exact forward-only intent overload
    /// below, so a caller cannot use this seam to bypass recovery authority.
    func publishPruneReceipt(
        _ receipt: GenerationPruneReceiptV1
    ) throws {
        try receipt.validate()
        guard receipt.disposition != .pruned,
              receipt.prunedEpochs.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        try withExclusiveGenerationMutationLock {
            guard try !itemExistsLocked(Self.pruneIntentName) else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            let data = try receipt.canonicalData()
            if try itemExistsLocked(Self.pruneReceiptName) {
                try replaceControlLocked(
                    name: Self.pruneReceiptName,
                    temporaryName: Self.pruneReceiptTemporaryName,
                    data: data
                )
            } else {
                try publishNewControlLocked(
                    name: Self.pruneReceiptName,
                    temporaryName: Self.pruneReceiptTemporaryName,
                    data: data
                )
            }
        }
    }

    func publishPruneReceipt(
        _ receipt: GenerationPruneReceiptV1,
        completing intent: GenerationPruneIntentV1
    ) throws {
        try receipt.validate()
        guard receipt.operationID == intent.operationID,
              intent.phase == .receiptPublished,
              receipt.currentEpoch == intent.currentEpoch,
              receipt.retainedEpochs == intent.retainedEpochs,
              receipt.prunedEpochs == intent.candidateEpochs,
              receipt.activeRetainedEpochs == intent.activeRetainedEpochs,
              receipt.uncertainRetainedGenerationIDs
                == intent.uncertainRetainedGenerationIDs,
              receipt.inventoryBeforeSHA256 == intent.inventoryBeforeSHA256,
              receipt.disposition == .pruned else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        try withExclusiveGenerationMutationLock {
            let current: GenerationPruneIntentV1? = try loadControlLocked(
                name: Self.pruneIntentName,
                decode: GenerationPruneIntentV1.decodeCanonical
            )
            if current == nil {
                let persisted: GenerationPruneReceiptV1? = try loadControlLocked(
                    name: Self.pruneReceiptName,
                    decode: GenerationPruneReceiptV1.decodeCanonical
                )
                guard persisted == receipt else {
                    throw GenerationLeaseRegistryFailureV1.corruptRegistry
                }
                guard Darwin.fsync(leaseDescriptor) == 0 else {
                    throw Self.mappedFailure()
                }
                return
            }
            guard current == intent else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            let data = try receipt.canonicalData()
            if try itemExistsLocked(Self.pruneReceiptName) {
                try replaceControlLocked(
                    name: Self.pruneReceiptName,
                    temporaryName: Self.pruneReceiptTemporaryName,
                    data: data
                )
            } else {
                try publishNewControlLocked(
                    name: Self.pruneReceiptName,
                    temporaryName: Self.pruneReceiptTemporaryName,
                    data: data
                )
            }
            try removeControlLocked(
                name: Self.pruneIntentName,
                expectedData: try intent.canonicalData()
            )
        }
    }

    fileprivate func validateActiveLocked(
        _ token: GenerationLeaseTokenV1,
        requiredRole: GenerationLeaseRoleV1
    ) throws {
        try token.validate()
        guard token.role == requiredRole else {
            throw GenerationLeaseRegistryFailureV1.wrongLeaseRole
        }
        let matches = try loadStateLocked().leases.filter {
            $0.leaseID == token.leaseID
        }
        guard matches == [token] else {
            throw GenerationLeaseRegistryFailureV1.leaseNotActive
        }
    }

    private func ensureRegistryLocked() throws {
        guard try !itemExistsLocked(Self.registryName) else {
            // Adopt an already-published first registry only after closing a
            // possible rename-success/directory-fsync-failure ambiguity.
            guard Darwin.fsync(leaseDescriptor) == 0 else {
                throw Self.mappedFailure()
            }
            return
        }
        try publishNewControlLocked(
            name: Self.registryName,
            temporaryName: Self.registryTemporaryName,
            data: try RegistryStateV1(leases: []).canonicalData()
        )
    }

    private func removeOwnerGuardIfUnused() throws {
        try withExclusiveGenerationMutationLock(
            verifyAfterOperation: false
        ) {
            let state = try loadStateLocked()
            guard !state.leases.contains(where: { $0.ownerID == ownerID }),
                  try migrationReservationLocked()?.ownerID != ownerID else {
                return
            }
            try requireNamedIdentity(
                parent: ownersDescriptor,
                name: Self.ownerLockName(ownerID),
                expected: ownerLockIdentity
            )
            guard Darwin.unlinkat(
                ownersDescriptor,
                Self.ownerLockName(ownerID),
                0
            ) == 0,
                  Darwin.fsync(ownersDescriptor) == 0 else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
        }
    }

    private func loadStateLocked() throws -> RegistryStateV1 {
        guard let value: RegistryStateV1 = try loadControlLocked(
            name: Self.registryName,
            decode: RegistryStateV1.decodeCanonical
        ) else {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
        return value
    }

    private func replaceStateLocked(with replacement: RegistryStateV1) throws {
        try replacement.validate()
        try replaceControlLocked(
            name: Self.registryName,
            temporaryName: Self.registryTemporaryName,
            data: try replacement.canonicalData()
        )
    }

    private func reconcileConservativeTemporariesLocked() throws {
        for name in [
            Self.registryTemporaryName,
            Self.pruneIntentTemporaryName,
            Self.pruneReceiptTemporaryName,
        ] {
            // A temporary is never authority. Keeping the current published
            // file conservatively retains leases and prune intent state. The
            // absent path also fsyncs the parent to close a prior unlink whose
            // directory fsync reported failure.
            try removeControlLocked(name: name, expectedData: nil)
        }
    }

    private func loadControlLocked<Value>(
        name: String,
        decode: (Data) throws -> Value
    ) throws -> Value? {
        guard try itemExistsLocked(name) else { return nil }
        let captured = try readControlLocked(name: name)
        do {
            return try decode(captured.data)
        } catch {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
    }

    private func createControlLocked(
        name: String,
        data: Data,
        kind: OwnedFileKindV1
    ) throws {
        try Self.requireSafeName(name)
        guard data.count <= Self.maximumControlFileBytes,
              try !itemExistsLocked(name) else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        let descriptor = Darwin.openat(
            leaseDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Self.mappedFailure() }
        var cleanupSnapshot: FileSnapshot?
        var permitsProtectionMetadataDrift = false
        var completed = false
        defer {
            _ = Darwin.close(descriptor)
            if !completed,
               let cleanupSnapshot,
               let namedSnapshot = try? Self.namedRegularFileSnapshot(
                   parent: leaseDescriptor,
                   name: name
               ),
               namedSnapshot.identity == cleanupSnapshot.identity,
               namedSnapshot.byteCount == cleanupSnapshot.byteCount,
               (permitsProtectionMetadataDrift
                    || namedSnapshot == cleanupSnapshot) {
                if Darwin.unlinkat(leaseDescriptor, name, 0) == 0 {
                    _ = Darwin.fsync(leaseDescriptor)
                }
            }
        }
        let initialSnapshot = try Self.regularFileSnapshot(descriptor)
        cleanupSnapshot = initialSnapshot
        permitsProtectionMetadataDrift = true
        let identity = initialSnapshot.identity
        // Protection and backup exclusion are established while the file is
        // still empty. A protected-data failure therefore cannot leave
        // plaintext control bytes at the canonical or temporary name.
        try protectFile(
            kind,
            parent: leaseDescriptor,
            directoryURL: leaseURL,
            name: name,
            expected: identity
        )
        permitsProtectionMetadataDrift = false
        cleanupSnapshot = try Self.regularFileSnapshot(descriptor)
        try Self.writeAll(data, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else { throw Self.mappedFailure() }
        cleanupSnapshot = try Self.regularFileSnapshot(descriptor)
        guard Darwin.fsync(leaseDescriptor) == 0 else {
            throw Self.mappedFailure()
        }
        guard try readControlLocked(name: name).data == data else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        completed = true
    }

    /// Publishes a previously absent control through a fully protected,
    /// fsynced temporary. A retry after rename success and directory-fsync
    /// failure adopts only the exact desired canonical bytes.
    private func publishNewControlLocked(
        name: String,
        temporaryName: String,
        data: Data
    ) throws {
        try Self.requireSafeName(name)
        try Self.requireSafeName(temporaryName)
        guard data.count <= Self.maximumControlFileBytes,
              name != temporaryName else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }

        if try itemExistsLocked(name) {
            let current = try readControlLocked(name: name)
            guard current.data == data else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            if try itemExistsLocked(temporaryName) {
                try removeControlLocked(
                    name: temporaryName,
                    expectedData: data
                )
            }
            guard Darwin.fsync(leaseDescriptor) == 0 else {
                throw Self.mappedFailure()
            }
            return
        }

        if try itemExistsLocked(temporaryName) {
            guard try readControlLocked(name: temporaryName).data == data else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
        } else {
            try createControlLocked(
                name: temporaryName,
                data: data,
                kind: .generationLeaseControlTemporary
            )
        }

        let temporary = try readControlLocked(name: temporaryName)
        guard temporary.data == data,
              try !itemExistsLocked(name) else {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: temporaryName,
            expected: temporary.identity
        )
        guard Darwin.renameatx_np(
            leaseDescriptor,
            temporaryName,
            leaseDescriptor,
            name,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw Self.mappedFailure()
        }
        // If this fsync fails, canonical already contains complete desired
        // bytes and the next identical call takes the adoption path above.
        guard Darwin.fsync(leaseDescriptor) == 0 else {
            throw Self.mappedFailure()
        }
        let persisted = try readControlLocked(name: name)
        guard persisted.identity == temporary.identity,
              persisted.data == data,
              try !itemExistsLocked(temporaryName) else {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
    }

    private func replaceControlLocked(
        name: String,
        temporaryName: String,
        data: Data
    ) throws {
        try Self.requireSafeName(name)
        try Self.requireSafeName(temporaryName)
        guard data.count <= Self.maximumControlFileBytes,
              name != temporaryName,
              try itemExistsLocked(name) else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        let expected = try readControlLocked(name: name)
        if expected.data == data {
            if try itemExistsLocked(temporaryName) {
                try removeControlLocked(
                    name: temporaryName,
                    expectedData: data
                )
            }
            guard Darwin.fsync(leaseDescriptor) == 0 else {
                throw Self.mappedFailure()
            }
            return
        }
        if try itemExistsLocked(temporaryName) {
            guard try readControlLocked(name: temporaryName).data == data else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
        } else {
            try createControlLocked(
                name: temporaryName,
                data: data,
                kind: .generationLeaseControlTemporary
            )
        }
        let temporary = try readControlLocked(name: temporaryName)
        guard temporary.data == data else {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: name,
            expected: expected.identity
        )
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: temporaryName,
            expected: temporary.identity
        )
        guard Darwin.renameat(
            leaseDescriptor,
            temporaryName,
            leaseDescriptor,
            name
        ) == 0 else {
            throw Self.mappedFailure()
        }
        // Rename has committed a complete protected file. A directory-fsync
        // failure is intentionally retryable: the desired-data branch above
        // recognizes this exact post-rename state without another mutation.
        guard Darwin.fsync(leaseDescriptor) == 0 else {
            throw Self.mappedFailure()
        }
        let persisted = try readControlLocked(name: name)
        guard persisted.identity == temporary.identity,
              persisted.data == data else {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
    }

    private func removeControlLocked(
        name: String,
        expectedData: Data?
    ) throws {
        guard try itemExistsLocked(name) else {
            // A retry can observe absence after unlink succeeded but its
            // directory fsync failed. Close that durability ambiguity before
            // treating the removal as idempotently complete.
            guard Darwin.fsync(leaseDescriptor) == 0 else {
                throw Self.mappedFailure()
            }
            return
        }
        let captured = try readControlLocked(name: name)
        if let expectedData, captured.data != expectedData {
            throw GenerationLeaseRegistryFailureV1.corruptRegistry
        }
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: name,
            expected: captured.identity
        )
        guard Darwin.unlinkat(leaseDescriptor, name, 0) == 0,
              Darwin.fsync(leaseDescriptor) == 0 else {
            throw Self.mappedFailure()
        }
    }

    private func readControlLocked(
        name: String
    ) throws -> (data: Data, identity: Identity) {
        try Self.requireSafeName(name)
        let descriptor = Darwin.openat(
            leaseDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw Self.mappedFailure() }
        defer { _ = Darwin.close(descriptor) }
        let before = try Self.regularFileSnapshot(descriptor)
        try verifyControlFilePolicy(
            try Self.controlKind(for: name),
            name: name,
            expected: before.identity
        )
        let data = try Self.readAll(from: descriptor)
        let after = try Self.regularFileSnapshot(descriptor)
        guard before == after,
              data.count == Int(before.byteCount) else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: name,
            expected: before.identity
        )
        return (data, before.identity)
    }

    private func itemExistsLocked(_ name: String) throws -> Bool {
        try Self.itemExists(parent: leaseDescriptor, name: name)
    }

    private func protectDirectory(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        try ProtectedFilePolicyV1.applyAndVerify(
            kind,
            at: url,
            authorityCheck: { [self] in try verify() }
        )
    }

    private func protectFile(
        _ kind: OwnedFileKindV1,
        parent: Int32,
        directoryURL: URL,
        name: String,
        expected: Identity
    ) throws {
        try ProtectedFilePolicyV1.applyAndVerify(
            kind,
            at: directoryURL.appendingPathComponent(name),
            authorityCheck: { [self] in
                try verify()
                try requireNamedIdentity(
                    parent: parent,
                    name: name,
                    expected: expected
                )
            }
        )
    }

    private func verifyControlFilePolicy(
        _ kind: OwnedFileKindV1,
        name: String,
        expected: Identity
    ) throws {
        try verify()
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: name,
            expected: expected
        )
        try ProtectedFilePolicyV1.verify(
            kind,
            at: leaseURL.appendingPathComponent(name)
        )
        try verify()
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: name,
            expected: expected
        )
    }

    private func verify() throws {
        let reopenedRoot = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedRoot >= 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        defer { _ = Darwin.close(reopenedRoot) }
        guard try Self.directoryIdentity(rootDescriptor) == rootIdentity,
              try Self.directoryIdentity(reopenedRoot) == rootIdentity,
              try Self.directoryIdentity(operationsDescriptor)
                == operationsIdentity,
              try Self.directoryIdentity(leaseDescriptor) == leaseIdentity,
              try Self.directoryIdentity(ownersDescriptor) == ownersIdentity,
              try Self.regularFileIdentity(mutationLockDescriptor)
                == mutationLockIdentity,
              try Self.regularFileIdentity(ownerLockDescriptor)
                == ownerLockIdentity else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        try requireNamedDirectoryIdentity(
            parent: rootDescriptor,
            name: Self.operationsName,
            expected: operationsIdentity
        )
        try requireNamedDirectoryIdentity(
            parent: operationsDescriptor,
            name: Self.leaseDirectoryName,
            expected: leaseIdentity
        )
        try requireNamedDirectoryIdentity(
            parent: leaseDescriptor,
            name: Self.ownerDirectoryName,
            expected: ownersIdentity
        )
        try requireNamedIdentity(
            parent: leaseDescriptor,
            name: Self.mutationLockName,
            expected: mutationLockIdentity
        )
        try requireNamedIdentity(
            parent: ownersDescriptor,
            name: Self.ownerLockName(ownerID),
            expected: ownerLockIdentity
        )
    }

    private func requireNamedIdentity(
        parent: Int32,
        name: String,
        expected: Identity
    ) throws {
        try Self.requireNamedIdentity(
            parent: parent,
            name: name,
            expected: expected
        )
    }

    private static func requireNamedIdentity(
        parent: Int32,
        name: String,
        expected: Identity
    ) throws {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try regularFileIdentity(descriptor) == expected else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
    }

    private func requireNamedDirectoryIdentity(
        parent: Int32,
        name: String,
        expected: Identity
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.directoryIdentity(descriptor) == expected else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
    }

    private static func openOrCreateDirectory(
        parent: Int32,
        name: String
    ) throws -> Int32 {
        try requireSafeName(name)
        var descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor >= 0 { return descriptor }
        guard errno == ENOENT else { throw mappedFailure() }
        if Darwin.mkdirat(parent, name, mode_t(0o700)) != 0,
           errno != EEXIST {
            throw mappedFailure()
        }
        guard Darwin.fsync(parent) == 0 else { throw mappedFailure() }
        descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw mappedFailure() }
        return descriptor
    }

    private static func openOrCreateRegularFile(
        parent: Int32,
        name: String
    ) throws -> (descriptor: Int32, identity: Identity) {
        try requireSafeName(name)
        var descriptor = Darwin.openat(
            parent,
            name,
            O_RDWR | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT {
            descriptor = Darwin.openat(
                parent,
                name,
                O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW,
                mode_t(0o600)
            )
            if descriptor < 0, errno == EEXIST {
                descriptor = Darwin.openat(
                    parent,
                    name,
                    O_RDWR | O_NOFOLLOW
                )
            }
            guard descriptor >= 0, Darwin.fsync(parent) == 0 else {
                if descriptor >= 0 { _ = Darwin.close(descriptor) }
                throw mappedFailure()
            }
        }
        guard descriptor >= 0 else { throw mappedFailure() }
        do {
            return (descriptor, try regularFileIdentity(descriptor))
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFDIR,
              information.st_nlink >= 1 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        return Identity(information)
    }

    private static func regularFileIdentity(_ descriptor: Int32) throws -> Identity {
        try regularFileSnapshot(descriptor).identity
    }

    private static func regularFileSnapshot(
        _ descriptor: Int32
    ) throws -> FileSnapshot {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,
              information.st_size <= off_t(maximumControlFileBytes) else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        return FileSnapshot(information)
    }

    private static func namedRegularFileSnapshot(
        parent: Int32,
        name: String
    ) throws -> FileSnapshot {
        try requireSafeName(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw mappedFailure() }
        defer { _ = Darwin.close(descriptor) }
        return try regularFileSnapshot(descriptor)
    }

    private static func controlKind(
        for name: String
    ) throws -> OwnedFileKindV1 {
        switch name {
        case registryTemporaryName,
             pruneIntentTemporaryName,
             pruneReceiptTemporaryName:
            return .generationLeaseControlTemporary
        case registryName,
             pruneIntentName,
             pruneReceiptName:
            return .generationLeaseControl
        default:
            throw GenerationLeaseRegistryFailureV1.invalidPath
        }
    }

    private static func itemExists(parent: Int32, name: String) throws -> Bool {
        try requireSafeName(name)
        var information = stat()
        guard Darwin.fstatat(
            parent,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            if errno == ENOENT { return false }
            throw mappedFailure()
        }
        guard (information.st_mode & S_IFMT) != S_IFLNK else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        return true
    }

    private static func readAll(from descriptor: Int32) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { return data }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw mappedFailure()
            }
            guard data.count <= maximumControlFileBytes - count else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        guard data.count <= maximumControlFileBytes else {
            throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                guard count > 0 else {
                    if count < 0 && errno == EINTR { continue }
                    throw mappedFailure()
                }
                offset += count
            }
        }
    }

    private static func requireSafeName(_ name: String) throws {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\") else {
            throw GenerationLeaseRegistryFailureV1.invalidPath
        }
    }

    private static func ownerLockName(_ ownerID: UUID) -> String {
        "\(ownerID.uuidString.lowercased()).lock"
    }

    private static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    private static func mappedFailure() -> GenerationLeaseRegistryFailureV1 {
        if errno == EACCES || errno == EPERM {
            return .protectedDataUnavailable
        }
        return .invalidIdentity
    }
}

/// Idempotent lifetime wrapper. A failed close deliberately leaves the durable
/// lease record in place; startup owner-lock reconciliation is the only crash
/// cleanup authority.
final class GenerationLeaseHandleV1: @unchecked Sendable {
    let token: GenerationLeaseTokenV1

    private let registry: GenerationLeaseRegistryV1
    private let lock = NSLock()
    private var isClosed = false

    init(
        registry: GenerationLeaseRegistryV1,
        token: GenerationLeaseTokenV1
    ) throws {
        try token.validate()
        self.registry = registry
        self.token = token
        try registry.validateActive(token, requiredRole: token.role)
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        try registry.release(token)
        isClosed = true
    }

    deinit {
        // Failure is fail-closed: the record remains durable and cannot make a
        // generation prune-eligible until owner-lock recovery proves death.
        try? close()
    }
}

@MainActor
final class StaleWriterFenceV1 {
    let expectedGenerationEpoch: GenerationEpochV1
    let writerLeaseToken: GenerationLeaseTokenV1

    private let registry: GenerationLeaseRegistryV1
    private let currentGenerationEpoch: () throws -> GenerationEpochV1

    init(
        expectedGenerationEpoch: GenerationEpochV1,
        writerLeaseToken: GenerationLeaseTokenV1,
        registry: GenerationLeaseRegistryV1,
        currentGenerationEpoch: @escaping () throws -> GenerationEpochV1
    ) throws {
        try expectedGenerationEpoch.validate()
        try writerLeaseToken.validate()
        guard writerLeaseToken.role == .writer,
              writerLeaseToken.epoch == expectedGenerationEpoch else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        self.expectedGenerationEpoch = expectedGenerationEpoch
        self.writerLeaseToken = writerLeaseToken
        self.registry = registry
        self.currentGenerationEpoch = currentGenerationEpoch
    }

    func validateCurrent() throws {
        try registry.withExclusiveGenerationMutationLock {
            try validateCurrentLocked()
        }
    }

    func withAuthorizedCommit<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        try registry.withExclusiveGenerationCommitLock {
            try validateCurrentLocked()
            return try operation()
        }
    }

    private func validateCurrentLocked() throws {
        try registry.requireNoMigrationReservationLocked()
        try registry.validateActiveLocked(
            writerLeaseToken,
            requiredRole: .writer
        )
        guard try currentGenerationEpoch() == expectedGenerationEpoch else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
    }
}
